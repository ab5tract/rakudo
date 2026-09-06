import com.oracle.truffle.api.CallTarget;
import com.oracle.truffle.api.CompilerDirectives;
import com.oracle.truffle.api.CompilerDirectives.CompilationFinal;
import com.oracle.truffle.api.CompilerDirectives.TruffleBoundary;
import com.oracle.truffle.api.Truffle;
import com.oracle.truffle.api.TruffleLanguage;
import com.oracle.truffle.api.frame.FrameDescriptor;
import com.oracle.truffle.api.frame.FrameSlotKind;
import com.oracle.truffle.api.frame.VirtualFrame;
import com.oracle.truffle.api.nodes.DirectCallNode;
import com.oracle.truffle.api.nodes.LoopNode;
import com.oracle.truffle.api.nodes.Node;
import com.oracle.truffle.api.nodes.RepeatingNode;
import com.oracle.truffle.api.nodes.RootNode;

import org.graalvm.polyglot.Context;

/**
 * Phase-0 PE prototype for the calling-convention port
 * (docs/jvm-truffle-calling-convention.md). Reproduces the callbench loop
 * `while (i<N) { acc = f(acc); i++ }` with `sub f($x){ $x + 1 }`, two ways:
 *
 *   HEAP  — the callee's single lexical lives in a boundary-allocated heap
 *           object published to a static field, mirroring today's CallFrame
 *           (priorInvocation / tc.curFrame make it escape, so PE cannot
 *           remove it). This is what an engine call costs now.
 *   SLOT  — the callee's lexical lives in a FrameDescriptor slot of its own
 *           VirtualFrame. With the callee force-inlined, PE's escape
 *           analysis virtualizes that frame: no allocation.
 *
 * Both callees are force-inlined, so the ONLY difference between the two
 * numbers is the frame representation. LOOP is the call-free baseline
 * (acc = acc + 1) — the JIT/loopbench floor.
 */
@TruffleLanguage.Registration(id = CcBench.ID, name = "ccbench")
public final class CcBench extends TruffleLanguage<Object> {
    public static final String ID = "ccbench";

    @Override protected Object createContext(Env env) { return new Object(); }

    /* The per-iteration step f($x). A data-dependent shift-add: no closed
     * form the compiler can fold a loop of these into, so all three variants
     * actually iterate N times. Identical in every variant, so the frame
     * delta between them is preserved. */
    static long step(long x) { return x + (x >>> 7) + 1; }

    @Override protected CallTarget parse(ParsingRequest request) {
        return new DriverRoot(this).getCallTarget();
    }

    public static void main(String[] args) {
        try (Context ctx = Context.newBuilder(ID).allowExperimentalOptions(true).build()) {
            String runtime = Truffle.getRuntime().getName();
            if (!runtime.contains("Graal"))
                System.err.println("WARNING: runtime is '" + runtime
                    + "', not optimizing — numbers are meaningless. Fix --module-path/--add-modules.");
            ctx.eval(ID, "run");
        }
    }

    /* ---- the heap frame model: today's CallFrame, in miniature ---- */

    static final class Frm {
        long[] iLex = new long[1];
        long iRet;
        /* Published so the object escapes the compiled region, exactly as
         * CallFrame.<init> does (sci.priorInvocation = this; tc.curFrame =
         * this). This is what forces the allocation to survive PE. */
        static volatile Frm prior;
    }

    /* ---- callees: sub f($x){ $x + 1 } ---- */

    /** Heap-framed callee. Frame alloc behind a boundary, like newFrame(). */
    static final class CalleeHeapRoot extends RootNode {
        CalleeHeapRoot(CcBench lang) { super(lang); }
        @Override public Object execute(VirtualFrame frame) {
            Frm fr = alloc();
            fr.iLex[0] = (long) frame.getArguments()[0]; // bind $x
            long x = fr.iLex[0];                          // read $x
            long r = step(x);
            fr.iRet = r;                                  // return register
            Frm.prior = fr;                               // escape (priorInvocation)
            return r;
        }
        @TruffleBoundary private static Frm alloc() { return new Frm(); }
        @Override public boolean isCloningAllowed() { return true; }
    }

    /** Slot-framed callee. The lexical is a FrameDescriptor slot. */
    static final class CalleeSlotRoot extends RootNode {
        private final int slot;
        CalleeSlotRoot(CcBench lang, FrameDescriptor fd, int slot) { super(lang, fd); this.slot = slot; }
        @Override public Object execute(VirtualFrame frame) {
            frame.setLong(slot, (long) frame.getArguments()[0]); // bind $x
            long x = frame.getLong(slot);                        // read $x
            return step(x);
        }
        @Override public boolean isCloningAllowed() { return true; }
    }

    /* ---- the measured loop ---- */

    static final class CallRepeat extends Node implements RepeatingNode {
        @Child DirectCallNode callNode;
        private final int accSlot, iSlot;
        long limit;
        CallRepeat(CallTarget callee, int accSlot, int iSlot) {
            this.callNode = DirectCallNode.create(callee);
            this.callNode.forceInlining();
            this.accSlot = accSlot;
            this.iSlot = iSlot;
        }
        @Override public boolean executeRepeating(VirtualFrame frame) {
            long i = frame.getLong(iSlot);
            if (i >= limit) return false;
            long acc = frame.getLong(accSlot);
            acc = (long) callNode.call(acc);
            frame.setLong(accSlot, acc);
            frame.setLong(iSlot, i + 1);
            return true;
        }
    }

    /** The call-free floor: acc = acc + 1. */
    static final class LoopRepeat extends Node implements RepeatingNode {
        private final int accSlot, iSlot;
        long limit;
        LoopRepeat(int accSlot, int iSlot) { this.accSlot = accSlot; this.iSlot = iSlot; }
        @Override public boolean executeRepeating(VirtualFrame frame) {
            long i = frame.getLong(iSlot);
            if (i >= limit) return false;
            frame.setLong(accSlot, step(frame.getLong(accSlot)));
            frame.setLong(iSlot, i + 1);
            return true;
        }
    }

    static final class LoopRoot extends RootNode {
        @Child LoopNode loop;
        private final int accSlot, iSlot;
        LoopRoot(CcBench lang, FrameDescriptor fd, int accSlot, int iSlot, RepeatingNode body) {
            super(lang, fd);
            this.accSlot = accSlot;
            this.iSlot = iSlot;
            this.loop = Truffle.getRuntime().createLoopNode(body);
        }
        @Override public Object execute(VirtualFrame frame) {
            frame.setLong(accSlot, (long) frame.getArguments()[0]);
            frame.setLong(iSlot, 0L);
            loop.execute(frame);
            return frame.getLong(accSlot);
        }
    }

    /* ---- driver: build, warm, time, print ---- */

    static final class DriverRoot extends RootNode {
        final CcBench lang;
        DriverRoot(CcBench lang) { super(lang); this.lang = lang; }

        private long[] loopSlots(FrameDescriptor.Builder b) {
            return new long[] { b.addSlot(FrameSlotKind.Long, "acc", null),
                                b.addSlot(FrameSlotKind.Long, "i", null) };
        }

        @Override public Object execute(VirtualFrame frame) {
            final long N = 50_000_000L, WARM = 5_000_000L, WARM_CALLS = 200;

            // HEAP callee + loop
            CallTarget heapCallee = new CalleeHeapRoot(lang).getCallTarget();
            FrameDescriptor.Builder hb = FrameDescriptor.newBuilder();
            long[] hs = loopSlots(hb);
            CallRepeat heapBody = new CallRepeat(heapCallee, (int) hs[0], (int) hs[1]);
            CallTarget heapLoop = new LoopRoot(lang, hb.build(), (int) hs[0], (int) hs[1], heapBody).getCallTarget();

            // SLOT callee + loop
            FrameDescriptor.Builder cfd = FrameDescriptor.newBuilder();
            int calleeSlot = cfd.addSlot(FrameSlotKind.Long, "x", null);
            CallTarget slotCallee = new CalleeSlotRoot(lang, cfd.build(), calleeSlot).getCallTarget();
            FrameDescriptor.Builder sb = FrameDescriptor.newBuilder();
            long[] ss = loopSlots(sb);
            CallRepeat slotBody = new CallRepeat(slotCallee, (int) ss[0], (int) ss[1]);
            CallTarget slotLoop = new LoopRoot(lang, sb.build(), (int) ss[0], (int) ss[1], slotBody).getCallTarget();

            // LOOP floor (no call)
            FrameDescriptor.Builder lb = FrameDescriptor.newBuilder();
            long[] ls = loopSlots(lb);
            LoopRepeat loopBody = new LoopRepeat((int) ls[0], (int) ls[1]);
            CallTarget floorLoop = new LoopRoot(lang, lb.build(), (int) ls[0], (int) ls[1], loopBody).getCallTarget();

            double heap = measure(heapLoop, heapBody, null, N, WARM, WARM_CALLS);
            double slot = measure(slotLoop, slotBody, null, N, WARM, WARM_CALLS);
            double floor = measure(floorLoop, null, loopBody, N, WARM, WARM_CALLS);

            /* All three run the identical recurrence N times from 0, so they
             * must agree — proof the loops actually iterated (were not folded)
             * and that the callee did the work. */
            if (accHeap != accSlot || accSlot != accFloor)
                throw new IllegalStateException("variants disagree: heap=" + accHeap
                    + " slot=" + accSlot + " floor=" + accFloor);

            System.out.printf("%n=== calling-convention PE prototype (GraalVM, warm) ===%n");
            System.out.printf("N=%,d  acc=%d (all three agree)%n%n", N, accFloor);
            System.out.printf("LOOP  (step inline, no call)    : %6.3f ns/iter%n", floor);
            System.out.printf("SLOT  (call, frame in slots)    : %6.3f ns/call  (frame virtualized)%n", slot);
            System.out.printf("HEAP  (call, CallFrame-style)   : %6.3f ns/call  (frame allocated)%n", heap);
            System.out.printf("%nframe tax    HEAP - SLOT       : %6.3f ns/call%n", heap - slot);
            System.out.printf("call overhead SLOT - LOOP       : %6.3f ns/call%n", slot - floor);
            System.out.printf("speedup      HEAP / SLOT        : %6.2fx%n", heap / slot);
            return "ok";
        }

        long accHeap, accSlot, accFloor;

        private double measure(CallTarget loop, CallRepeat cbody, LoopRepeat lbody,
                               long N, long WARM, long WARM_CALLS) {
            if (cbody != null) cbody.limit = WARM; else lbody.limit = WARM;
            for (long k = 0; k < WARM_CALLS; k++) loop.call(0L);
            if (cbody != null) cbody.limit = N; else lbody.limit = N;
            long best = Long.MAX_VALUE, acc = 0;
            for (int rep = 0; rep < 5; rep++) {
                long t0 = System.nanoTime();
                acc = (long) loop.call(0L);
                long dt = System.nanoTime() - t0;
                if (dt < best) best = dt;
            }
            if (cbody != null) { if (cbody.callNode != null) accHeapOrSlot(acc); }
            else accFloor = acc;
            return (double) best / N;
        }

        /** heap runs before slot; first call sets accHeap, second accSlot. */
        private void accHeapOrSlot(long acc) {
            if (accHeap == 0) accHeap = acc; else accSlot = acc;
        }
    }
}
