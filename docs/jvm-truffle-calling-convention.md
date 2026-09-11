# Porting the calling convention to Truffle

Goal (user, 2026-09-06): **fully migrate to Truffle — no "engine" vs
"runtime" distinction.** Start with the calling convention, which the
NFG-perf investigation identified as the single dominant cost of every
workload (`docs/jvm-nfg-perf-findings-2026-09-06.md`): `CallFrame.<init>`
is ~13% of on-CPU samples everywhere, measured ~47 ns/call, against a
~0.04–2 ns JIT ceiling — ~25–50× headroom. Phase 5 encodability is 100%
(zero real bails) and the full t/+t/spec suite has run, so the bytecode
runtime is no longer load-bearing for coverage; what keeps it alive is
the *calling convention*, and that is what this work removes.

This doc is the plan of record for that port. Read
`docs/jvm-truffle-migration.md` first for how the engine got here; this
is the next arc.

## The dispatch cost (`infix:<+>`) — profiled 2026-09-06

Chasing "the dispatch cost directly" (a `$a+$b` loop measured ~677 ns/op).
JFR (`docs/bench/callconv` reproduction: attach `JFR.start settings=profile`
to a running `+` loop). Findings, in order of what they overturned:

- **`CallFrame.<init>` is ~50% of `+`**, and one `$a+$b` builds `CallFrame`s
  in ~6 distinct setting blocks (the proto, the multi-dispatch, the
  `Int:D+Int:D` candidate…). `Ops.add_I` — the actual addition — is ~2%.
  So the dispatch cost *is* the calling-convention cost × frames-per-operator.
  The multi-dispatch resolution is mostly cached (`findmethod`/`istype` ~5%);
  it's the *frame per call*, not re-resolution, that costs.
- **Inside `CallFrame.<init>`, ~80% is the outer-resolution caller-chain
  search** (`CallFrame.kt`, the `while (checkFrame != null)` loop) — ~40% of
  the whole `+`. The `liveInvocations` atomic is only ~9% of the constructor
  (a tempting but wrong target).
- **The naive gate fix `>0`→`>1` is UNSAFE** — proven by a throwaway: it
  broke instantly (`VMArray: Can't shift from an empty array`), a wrong-outer
  lexical lookup. The search genuinely guards a static block nested in a
  *recursive* outer, where `priorInvocation` picks the wrong level.
- **The search SUCCEEDS at runtime** (`NQP_OUTER_DEBUG` instrumentation:
  `found=true`, `live=1`–`2`). It is finding genuinely-live outers deep on
  the multi-dispatch chain — *not* wasted. The perf notes' "1.1M searches,
  zero successes" was a **compile** workload (exited module mainlines), a
  different problem.

**Two distinct problems, then:**

1. *Compile-time over-count* (the "zero successes" case): module mainlines
   exit via unwind without `leave()`, so their `liveInvocations` stays
   over-counted and every later dispatch pays for a doomed search against
   them. **Fixed (2026-09-06, uncommitted → committed):** the unwind path
   now gives back the count of every frame it tears past
   (`CallFrame.countLeft`, called from `ExceptionHandling.giveBackTornFrames`
   before each `throw tc.unwinder`; idempotent via `left`; only frames
   strictly between the current frame and the on-chain handler). Correct
   (01-sanity 25/25), low-risk. **Plausibly a build speedup (~14% of a CORE.c
   compile per the perf notes) but NOT YET MEASURED — measure the search's
   share on the next full build.** Does nothing for runtime `+` (the search
   there succeeds).
2. *Runtime deep-outer search* (the `+` case): the search walks up to a
   live outer deep on the chain. Optimizing it safely (an O(1) per-thread
   live-frame lookup, or setting `cr.outer` at code-ref creation like
   MoarVM) hits the cross-thread + recursion subtleties that sank `>1`. The
   clean big win is **frame-count reduction** — inline the resolved
   candidate so `$a+$b` stops building ~6 frames (spesh-level, a deliberate
   project). Deferred.

## The distinction we are collapsing

Today the Truffle interpreter (`NqpRootNode`/`NqpOps`, "the engine") is a
**guest inside the runtime's calling convention**. An engine block runs
its body on a Truffle `VirtualFrame`, but its *frame* — the thing that
holds lexicals, the outer chain, the return registers — is a heap
`CallFrame` (`nqp-runtime`), allocated by the runtime, exactly as a
bytecode block's is. The two worlds share one calling convention and one
frame object; "engine vs runtime" is really "which thing runs the body,"
not "which thing owns the call."

### The call path today (engine → engine, the hot case)

1. Caller's program hits a `DispatchOp` (`NqpRootNode.DispatchOp`).
2. `NqpDispatch.replay` folds the recorded dispatch programs to
   PE-visible guard tests (this part is already done — folded replay,
   2026-09-04). A monomorphic call to a literal engine-bodied callee
   resolves to an adopted `DirectCallNode` → `enterDirect`.
3. **`enterDirect` calls `newFrame(tc, cr)` = `new CallFrame(tc, cr)`
   behind a `@TruffleBoundary`** (`NqpDispatch.java:1013`). This is the
   ~47 ns. `CallFrame.<init>` (`CallFrame.kt:141`) allocates the frame,
   allocates up to four typed lexical arrays (`oLex`/`iLex`/`nLex`/`sLex`,
   `CallFrame.kt:187-223`), resolves `outer` (an explicit `cr.outer`, a
   caller-chain search now gated by `liveInvocations`, or auto-close),
   bumps `liveInvocations`, and sets `tc.curFrame`. It is *deliberately*
   behind a boundary so PE cannot fold it — because as written it cannot
   be folded (heap arrays, a caller-chain walk, a global side effect).
4. `cn.call(cu, tc, cf, csd, args)` runs the callee's program. Its
   prologue (`CheckArity`, `PosParam`/`NamedParam`, `NqpRootNode.java:454+`)
   binds arguments **into the `CallFrame`'s lexical arrays**, not the
   Truffle frame's slots.
5. `LexGet`/`LexBind` (`NqpRootNode.java:237-261`) read and write those
   `CallFrame` arrays via `NqpOps.getlex`/`bindlex(cf, …)`.
6. `leave(cf)` decrements `liveInvocations`, maybe runs an exit handler,
   restores `tc.curFrame`.

The `VirtualFrame` a program runs on carries only the operand stack and
the five `ARG_*` arguments (`NqpRootNode.java:54-58`). **Lexicals never
touch a frame slot.** That is why escape analysis can never remove the
frame allocation: the lexicals live in a heap object with global-ish
lifetime (`priorInvocation`, `liveInvocations`, the outer chain).

### Why the frame is pinned to the heap

A `CallFrame` outlives its call whenever the frame *escapes*:

- **Closures.** A nested block is `emitCodeRefGet(qbid)` →
  `cu.lookupCodeRef(qbid)` → a `CodeRef`; `p6capturelex` (`NqpOps.java:1503`)
  sets that CodeRef's `.outer` to the current `CallFrame`. Every lexical
  lookup in the closure then walks `f.outer` (`NqpOps.java:1083,1148,1156,…`),
  a chain of heap `CallFrame`s. A captured enclosing frame must survive
  after its own call returns.
- **Introspection.** `nqp::ctx`/`curlexpad` (`CurLexpad`), `callframe`,
  by-name lexical lookup, `getlexouter`/`getlexcaller` — all hand out or
  walk `CallFrame`s.
- **Continuations.** A captured continuation materializes and clones the
  `CallFrame` chain (`cloneContinuation`, `CallFrame.kt:386`).
- **Handlers + backtraces.** `ExceptionHandling.handlerDynamic` walks
  `cf.caller` and reads `cf.curHandler`; backtraces read the chain.

So the frame cannot simply vanish. But the overwhelming majority of hot
calls — the accessor methods, the arithmetic loop bodies, the leaf
routines the perf doc names — **never escape**: no nested block captures
them, they take no ctx, register no handler, are never resumed. For those,
the whole `CallFrame` is dead weight, and that is the win to capture.

## The target calling convention

The classic Truffle shape, and what the migration doc's architecture
target already commits to ("lexicals map to Truffle `FrameDescriptor`
slots; `CallFrame` stays as a materialized shim for interop"):

1. **Lexicals live in `FrameDescriptor` slots of the callee's own
   `VirtualFrame`**, not in `CallFrame` heap arrays. The frame descriptor
   is built once per block (static: the lexical name/type tables in
   `StaticCodeInfo` already give the slot layout) and attached to the
   `NqpRootNode`.
2. **Calls are `DirectCallNode.call(args)`** — already true for the
   monomorphic engine callee — but the callee runs in a fresh
   `VirtualFrame` whose *slots* are its lexicals. Arguments arrive in
   `frame.getArguments()` (Truffle-native) and the prologue binds them
   into slots.
3. **No `CallFrame` is allocated for a non-escaping call.** When the
   callee neither captures its frame nor otherwise escapes, there is no
   heap frame at all; PE's escape analysis virtualizes the `VirtualFrame`
   and the call becomes frame-allocation-free. This is the ~47 ns → single
   digits.
4. **`CallFrame` becomes a lazy materialization** — a *reified* view of a
   frame that escapes. It is created only when needed (a closure captures
   it, ctx/callframe asks for it, a continuation saves it, a handler
   registers against it), populated from the frame slots, and from then on
   the slots and the materialization are kept coherent (or the frame runs
   "materialized from the start" — see below).

### When a frame must materialize — decide it statically

Whether a frame escapes is almost always known at **compile time**, and
the encoder already sees everything it needs:

- the block **declares nested blocks** that could `capturelex` it,
- the block **uses `ctx`/`curlexpad`/`callframe`/by-name lexical ops**,
- the block **registers handlers** (`handle`/`handlepayload`/loop
  handlers) or can be **resumed** (continuations),
- the block is an **outer** that a descendant closure reads through.

Mark such blocks `needsMaterializedFrame` in the wire + `StaticCodeInfo`.
A marked block builds (or lazily builds) a `CallFrame` shim backed by the
slot array and behaves exactly as today — correctness first, no speed
regression, full interop. An **unmarked** block never allocates a
`CallFrame`; its prologue binds into slots, `LexGet`/`LexBind` are slot
reads/writes, and it leaves with nothing to decrement. This mirrors
MoarVM's "needs full frame" flag and the rx engine's own choice-point
discipline (state that must outlive the local stack lives where the
control stack lives — `docs/jvm-truffle-migration.md`, lessons).

The escape-analysis win is exactly the unmarked leaf blocks, which the
perf profile says are the hot ones. The marked blocks keep today's cost,
which is fine — they are the frames that genuinely have to exist.

## The hard parts, each with its mechanism

- **The outer chain.** A closure's `outer` currently points at a heap
  `CallFrame`. If the enclosing block is *marked* (it has nested blocks,
  so by definition it is), its materialized `CallFrame` is what the
  closure captures — unchanged. The closure body reads outer lexicals
  through that materialization. So the outer chain stays a `CallFrame`
  chain; only *leaf* frames (which are never someone's outer) skip it.
  Invariant to enforce: **a block that is any nested block's static outer
  is always marked.** The encoder knows the static outer relation
  (`outerStaticInfo`), so this is a compile-time closure of the mark.
- **`tc.curFrame`.** Handler walking, `descriptorFor`, and backtraces read
  `tc.curFrame`. An unmarked leaf that sets no handler and makes only
  calls that themselves manage `tc.curFrame` need not appear on the chain
  — but anything that *observes* it (a die inside the leaf) must see a
  coherent chain. Safe first cut: unmarked frames still push/pop a
  lightweight `tc.curFrame` marker, or the leaf materializes on first
  `tc.curFrame` read. Measure whether the marker alone costs anything; if
  it does, make it lazy like the rest.
- **Parameter binding.** `CheckArity`/`PosParam`/`NamedParam`/slurpies
  currently write the `CallFrame` arrays. Retarget them to frame slots for
  unmarked blocks (a slot-store variant), keeping the `CallFrame` variant
  for marked blocks until they too move. The binder's flattening/named
  logic is unchanged — only the destination of the bound value changes.
- **Return registers.** `StoreRet`/`readResult` and the dispatch
  `K_VALUE` outcome write `cf.oRet/iRet/…`. For a slot-only call, the
  return value rides the Truffle call's *return value* (`program.call(...)`
  already returns the typed result — see `NqpCodeEngine.runProgram`), so
  the register store is only needed on the materialized-frame road and for
  the continuation resume contract. Keep both; prefer the return value.
- **Continuations.** `enableYield` + `ContinuationResult` already save and
  restore the `VirtualFrame` (`resumeEngine`, `NqpCodeEngine.java:135`).
  A block that can be resumed is *marked* (it needs a materialized frame
  across the yield), so continuations ride the materialized road and the
  existing resume contract is unchanged.
- **Bytecode interop during the transition.** While any bytecode callee or
  caller remains, the boundary is `Ops.invokeDirect` (unchanged) and a
  materialized `CallFrame` (which a bytecode frame always is). A
  slot-only engine callee invoked *from bytecode* materializes on entry
  (the invoke boundary builds the shim); an engine caller calling a
  bytecode callee goes through `invokeBoundary` as today. The port does
  not require deleting bytecode first — it degrades to today's behaviour
  at every remaining bytecode edge.

## Phased plan and progress

**Gate policy (user decision 2026-09-06): `t/01-sanity` only, plus
differential micro-benchmarks, until there is a real performance win —
the full suite is too painful to run per iteration.** Everything is
**knob-gated behind `NQP_CODE_NOFRAME` (off by default)**, so the shipped
build is byte-identical regardless and a mistaken predicate can only
affect a knob-on run. The whole-suite `t/`+`t/spec` gate waits until the
setting-wide win justifies it. Anything touching `nqp/src/vm/jvm/QAST/*.nqp` (nqp tree)
or the wire needs a clean `buildJvm` + `make` (~12 min); runtime-only
edits test in ~5s via the jar sync.

### State as of 2026-09-06 EOD

- **Landed (uncommitted, on branch `truffle-grammar-engine`):** Phase 0
  prototype (`docs/bench/callconv/`), Phase A (`needsFrame` mechanism +
  frame-free leaves), Phase A-`%_` (frame-free methods), Phase A-static/cont
  (frame-free `my` vars + container params). Four clean `buildJvm`+`make`
  cycles, all EXIT=0; the default (knob-off) build is unchanged.
- **Correctness:** `t/01-sanity` **25/25 with the knob on** (and off).
- **Timing:** the accessor / leaf micro-benchmarks show a stable ~12–22%
  per-call win on frame-free blocks (tables above). **Cold-runner
  01-sanity shows no timing signal** (~62 s both ways, variance-controlled)
  — it is JVM-startup-dominated and the default *setting* is bytecode, so
  frame-free only touches the test files. An earlier 63→50 s reading was
  cache warmup and is **retracted**.
- **Not yet done:** the setting-wide measurement. The default `make`
  compiles the setting as bytecode (engine/precompiled/frame-free are
  opt-in per compile: `NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 NQP_CODE_NOFRAME=1`).
  To see the win across every setting method, build the setting engine +
  precompiled + frame-free and compare warm eval-server 01-sanity against
  an engine+precompiled baseline. Deferred until more per-call wins land.
- **Loose ends:** `state` vars (frame-forcing, once-only init); the whole
  dispatch-block class (deferred, see above).
- **Known bug (2026-09-07), why NQP_CODE_NOFRAME stays off by default:** a
  CORE.c setting encoded with frame-free blocks on breaks the CORE.d
  setting compile with "Bind check failed" (RakOps/BindFailure: a lowered
  parameter check rejected a call the full binder accepts) in the parse of
  CORE.d, inside `key-origin`/`FOREIGN-LANG`. Frontend jars encoded
  frame-free are fine (CORE.c parses with them); the same CORE.c recompiled
  with NQP_CODE_NOFRAME=0 lets CORE.d compile (parse 9.2s). So the
  divergence is in a frame-free routine of the setting itself, in the
  cf-free arity/parameter road. Next step: build CORE.c frame-free, then
  compile CORE.d with NQP_CODE_SKIP=<name> bisection over the setting's
  frame-free candidates, or make BindFailure name the routine.
  **Lead (2026-09-07, from the jesp work, docs/jvm-jesp.md):** a
  frame-free callee has no `CallFrame`, so `tc.frame` inside it is the
  *caller's* frame, and `BindFailure.failed` (an `assertparamcheck` on a
  `where`/subset/type-mismatched parameter that the multi dispatcher
  expects to resume past) reads the caller's invoking dispatch instead of
  its own: the failure is then rethrown by the wrong dispatch or reported
  as a plain "Bind check failed". Any frame-free block that can
  `assertparamcheck` is a candidate; the fix is to make the frame-free
  predicate exclude blocks with bind-failure-capable parameter checks, or
  to give a frame-free callee a place to carry its invoking dispatch.

### Phases

- **Phase A — the `needsFrame` mechanism + frame-free leaves. DONE
  2026-09-06 (knob-gated `NQP_CODE_NOFRAME`, off by default).** The
  investigation corrected the plan: the optimizer's `lexicals_to_locals`
  already puts every non-escaping own-lexical into a DSL frame slot
  (LOCGET/LOCBIND), so "move lexicals to slots" was largely done; the
  residual per-call cost is the `CallFrame` *object itself*. So Phase A
  instead **skips the CallFrame** for a provably frame-free block: the
  encoder marks a block frame-free (wire header word) when it declares no
  lexicals, makes no dispatch, has no nested block, reads no frame
  (lex/ctx/getlexouter/usecapture/args), runs no handler, and takes only
  positional local-scope params; the runtime (`enterDirect`/`enterEngine`)
  then runs it with `cf==null`, delivering the program's return value into
  the caller's registers (what a framed callee's StoreRet would), so PE
  virtualizes the callee's frame. `cf`-free `checkarity`/`posparam`/
  `checkNoExtraNamed` thread `tc`/`cu` instead of `cf`; `explodeFlattening`
  retargeted to `tc`.
    - *Delivered*: nqp `TruffleEncoder.nqp` (predicate + header word, wire
      version 2), `NqpWire`/`NqpRootNode`/`NqpLanguage` (parse the flag),
      `NqpDispatch` (the `cf==null` entry), `NqpOps` (`cf`-free binder +
      `storeReturnInto`), `CallSiteDescriptor` (tc-based `explodeFlattening`,
      callers updated in nqp-runtime + rakudo Binder/RakOps).
    - *Result* (full build passed, default byte-identical): a frame-free
      block called in a hot loop, `NQP_CODE_NOFRAME` off vs on: **127 → 98
      ns/call, ~22%** (~28 ns/call, the CallFrame). Output identical.
      Negative control (a closure reading an outer lexical → framed):
      **127 → 122, noise** — the knob is inert for framed blocks, as
      designed. Correctness holds framed and frame-free.
    - *Reach, honestly*: narrow, exactly as predicted. An **accessor
      `method getx() { $!x }` does NOT qualify** — `self` is read as a
      lexical (a `LEXGET`), so the block is framed (192 → 196, noise).
      Frame-free today means empty-signature pure-op blocks that read no
      lexical at all (not even `self`). Real, but not the headline.

- **Phase A-`%_` — dead named-args capture made frame-free. DONE
  2026-09-06.** The accessor investigation found the real blocker was NOT
  `self` (which the optimizer *does* localize) but the implicit **`%_`**:
  every method carries a `%_` named-args capture, dead in almost every
  body, that lowers to a `:decl(static)` lexical + a named-slurpy param —
  both frame-forcing. The lowering already puts an unused `%_` in *discard*
  mode (`IMPL-UNUSED-SLURPY`: accepts and drops stray nameds, builds no
  hash), but keeps the param + lexical. Fix, `#?if jvm` + knob-gated:
  the discard slurpy is annotated `discard_named` in the lowering
  (`signature.rakumod`, `code.rakumod`), the encoder emits it as a new wire
  **kind 4** (suppresses the extra-named rejection, no fetch, no `cf`), and
  a `%_`-named decl is excluded from `needsFrame`. Off the knob it stays a
  normal kind-3 slurpy; a `%_` that is actually read emits a lexical op and
  stays framed. *Result*: `method getx() { $!x }` went **framed → frame-free,
  198 → 175 ns/call (~12%)**, correctness intact. This is the everywhere
  case (methods).

- **Phase A-static/cont — `my` vars and container params made frame-free.
  DONE 2026-09-06.** A `my $y` / a container param lowers to a *local*
  (the live storage) plus a `:decl(static)`/`:decl(contvar)` companion
  lexical (a container prototype the body never names). Those placeholder
  decls forced a frame. They are dead unless read, and every read emits a
  lexical op (`frame_op`), so excluding `static`/`cont` decls from
  `needsFrame` is safe. *Result*: `sub g($x) { $x }` 181 → **146** (~19%);
  `my $y := $x; $y` 189 → **164**; `my $y; 5` 108 → **86** (~20%). A
  `my $y = $x` stays framed — `=` (`p6assign`) is a dispatch, the deferred
  category below, not a bug. (`state` left frame-forcing: its once-only
  init runs at frame construction.)

### Frame-free coverage today (knob on), measured 2026-09-06

| shape | frame-free? |
|---|---|
| empty-sig pure-op sub; unused-`$_` sub (lowering drops `$_`) | ✓ |
| positional-param op body `sub g($x){ nqp::add_i($x,1) }` | ✓ |
| method accessor `method m(){ $!x }` (dead `%_`) | ✓ |
| `my` decl / container param / `my $y := …` (bind) | ✓ |
| closure over an outer lexical; used `$_`/lexical | framed (correct) |
| **any block that makes a dispatch** (incl. `$x+1`, `$y = …`) | framed |

### Deferred: blocks that make a dispatch (user decision 2026-09-06)

The largest remaining framed class, but deliberately **not** the next
target. The blocker is the **return-register bounce**: `dispatch(...)`
ends with `readResult(rtype, cf)`, reading the callee's typed result off
`cf`'s registers, which the callee's `StoreRet` wrote into `cf.caller`.
A frame-free caller has no `cf` at either end. Decoupling it means moving
the return registers off the frame (to `tc`-level, or a boxing-eliminated
return value) — a real change touching the continuation resume path.

**Why deferred:** the frame is only ~4–14% of a *dispatch-making* call's
cost (a call whose body dispatches is 200–677 ns; `infix:<+>` measured
677 ns), versus ~15–22% of a *leaf* call. The dispatch itself dominates,
so freeing dispatch-blocks of their frame is broad coverage but modest
per-call. Higher-ROI directions first: finish leaf coverage, and the
dispatch cost itself (the 677 ns is the real fat). The `tc.curFrame`
edges are otherwise fine for frame-free-predicate blocks (they set no
dynamic vars, register no handlers, aren't resumed; `descriptorFor`
already resolves from the emitting class).

### Later phases (unchanged in intent)

- **Delete the bytecode calling convention.** Once every engine edge is
  slot-native and no bytecode body remains reachable (Phase 5's deletion),
  retire `ArgsExpectation`, the `mh` invoke road, and the `CallFrame`
  array storage, leaving `CallFrame` as the pure reified-frame shim. This
  is where "no engine vs runtime distinction" is finally true.

### Phase 0 — the PE prototype (DONE 2026-09-06)

Built and run (`docs/bench/callconv/`): a hand-written `RootNode` loop
`while(i<N){acc=f(acc);i++}` with `f($x){step($x)}`, the callee
force-inlined, measured three ways — the lexical in a boundary-allocated
escaping heap object (HEAP, today's `CallFrame`), the lexical in a
`FrameDescriptor` slot (SLOT, the target), and the step inlined with no
call at all (LOOP, the floor). All three run the identical non-foldable
recurrence N=50M times so the loops genuinely iterate.

    LOOP  (step inline, no call)    :  0.558 ns/iter
    SLOT  (call, frame in slots)    :  0.561 ns/call   (frame virtualized)
    HEAP  (call, CallFrame-style)   : 10.497 ns/call   (frame allocated)
    frame tax    HEAP - SLOT        :  9.936 ns/call   (18.7x)
    call overhead SLOT - LOOP       :  0.003 ns/call

**The frame allocation is the entire per-call cost, and a slot frame
removes it completely: an inlined call to a slot-framed callee costs the
same as no call.** This is a conservative proxy — the real
`CallFrame.<init>` also allocates up to four typed lexical arrays,
resolves `outer`, bumps `liveInvocations`, and sets `tc.curFrame`, with
`ArgsExpectation`/dispatch/binding on top (callbench measured ~47 ns/call
total). The prototype isolates the frame slice (~10 ns) and proves it is
fully recoverable; inlining then lets PE fold the dispatch guards and
binding the same way. The target is confirmed — proceed to Phase A.

## Load-bearing facts for the next session

- Lexicals are **not** in frame slots today — `LexGet`/`LexBind` hit
  `CallFrame` arrays via `NqpOps.getlex/bindlex`. Confirmed by reading
  `NqpRootNode.java:237-261` + `NqpOps` frame-access ops.
- `newFrame` is `@TruffleBoundary` on purpose (`NqpDispatch.java:1013`);
  the boundary is the thing Phase B removes for unmarked callees.
- `StaticCodeInfo` already carries the slot layout: `oLexicalNames` +
  `oLexStatic` + `oLexStaticFlags` (clone-on-first-read vivify semantics,
  `CallFrame.oLexOrVivify`), and `iLexicalNames`/`nLexicalNames`/
  `sLexicalNames`. The clone-flag vivify timing is **semantics, not
  thrift** (`CallFrame.kt:337` comment) — the slot representation must
  preserve first-read vivification, not eager-clone.
- `engineTarget` (`StaticCodeInfo.kt:72`) is the registered `CallTarget`;
  `argsExpectation == USE_BINDER` is the tag for "engine-bodied, takes the
  (cu,tc,cf,csd,args) shape." Both gate the direct-entry road.
- The dispatch fold + `DirectCallNode` inlining is already in place; the
  frame allocation is the remaining boundary between a folded call and a
  fully-inlined one.
- Rule from the dispatch work: **nothing Kotlin on a PE-visible path
  unless it is a plain field access**, and check every new fast path with
  `compiler.TraceMethodExpansion`. Frame-slot ops are Java in
  `NqpRootNode`/`NqpOps`; keep them so.
