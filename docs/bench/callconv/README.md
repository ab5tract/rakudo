# Calling-convention PE prototype

Phase-0 measurement for the calling-convention port
(`docs/jvm-truffle-calling-convention.md`). Isolates the cost of the
frame representation on an inlined engine call: today's boundary-allocated,
escaping `CallFrame` (HEAP) vs. a `FrameDescriptor` slot (SLOT), against
the call-free loop floor (LOOP). All three run the identical non-foldable
recurrence N=50M times, so the loops actually iterate and the only
difference is the frame.

Build + run (GraalVM 25.2.4 required for an optimizing Truffle runtime):

    JH=/usr/lib/jvm/java-25-graalvm
    TR=nqp/build/jvm/share/truffle
    DSL=$(find ~/.gradle -name 'truffle-dsl-processor-25.2.4.jar' | head -1)
    CP="$TR/truffle-api-25.2.4.jar:$TR/polyglot-25.2.4.jar:$TR/collections-25.2.4.jar"
    $JH/bin/javac -processorpath "$DSL:$CP" -cp "$CP" -d out CcBench.java
    $JH/bin/java --module-path "$TR" \
      --add-modules org.graalvm.truffle,org.graalvm.truffle.runtime \
      --enable-native-access=org.graalvm.truffle --sun-misc-unsafe-memory-access=allow \
      -cp "$CP:out" CcBench

Result (2026-09-06, GraalVM 25.2.4, warm):

    LOOP  (step inline, no call)    :  0.558 ns/iter
    SLOT  (call, frame in slots)    :  0.561 ns/call   (frame virtualized)
    HEAP  (call, CallFrame-style)   : 10.497 ns/call   (frame allocated)
    frame tax    HEAP - SLOT        :  9.936 ns/call   (18.7x)
    call overhead SLOT - LOOP       :  0.003 ns/call   (the call is free)

The frame allocation is the entire per-call cost in this model, and a
slot-based frame removes it completely: an inlined call to a slot-framed
callee costs the same as no call at all. This is a conservative proxy —
the real `CallFrame.<init>` also allocates up to four typed lexical
arrays, resolves `outer`, bumps `liveInvocations`, and sets `tc.curFrame`,
and the arg road adds `ArgsExpectation`/dispatch/binding on top (the
callbench measured ~47 ns/call total overhead). The prototype isolates the
frame slice (~10 ns) and shows it is fully recoverable; inlining then lets
PE fold the dispatch guards and binding the same way.

The HEAP model's `Frm.prior` static publish mirrors what actually pins
today's frame to the heap: `CallFrame.<init>` sets `sci.priorInvocation =
this` and `tc.curFrame = this`, so the object escapes and PE cannot
scalar-replace it. Remove the escape (a non-escaping leaf frame) and the
slot frame virtualizes away.
