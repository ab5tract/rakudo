# JVM perf findings, milestone 6 (compiler workload)

**These numbers describe the PRE-REBASE tree.** rakudo
`3db3362101` on `worktree-jesp-direct-lazy-records`, nqp `41c294b02`,
Oracle GraalVM 25.2.4 (`25.0.4+7-LTS-jvmci-25.2-b20`). Upstream rakudo
had 21 commits not in this tree at the engine merge and has not been
rebased in.

## 1. The configuration table

One row per traced CORE.c compile. The command is the Makefile's own
recipe with `--output` redirected out of `blib`:

```bash
RAKUDO_RAKUAST=1 perl rakudo-j-build \
  --setting=NULL.c --ll-exception --optimize=3 --target=jar --stagestats \
  --output=<scratch>/m6-corec.jar gen/jvm/CORE.c.setting
```

under
`-Dpolyglot.engine.TraceCompilation=true -Dpolyglot.engine.CompilationStatistics=true`
and `NQP_CODE_CLOSE_AT_EXIT=1`.

| # | configuration | wall | Stage parse | Stage optimize | done | failed | total-compiler-ms | verdict |
|---|---|---|---|---|---|---|---|---|
| 0 | baseline (no knobs) | **434 s** | **333.8 s** | **36.6 s** | 5656 | 444 | 2 143 944 | reference |
| 1 | Task 4 `NQP_CODE_MAX_COMPILE` | | | | | | | |
| 2 | Task 5 | | | | | | | |
| 3 | Task 6 | | | | | | | |
| 4 | Task 7 | | | | | | | |

Baseline stage table in full:

```
Stage start      :   0.001
Stage parse      : 333.841
Stage syntaxcheck:   0.000
Stage ast        :   0.001
Stage optimize   :  36.584
Stage qast       :  34.266
Stage unit       :  27.539
Stage jar        :   0.000
```

Stages sum to 432.2 s against a 434 s wall clock.

### Baseline failure population

| reason | count | mean | total |
|---|---|---|---|
| `PermanentBailoutException: Too deep inlining, probably caused by recursive inlining.` | 442 | 54 ms | 23.7 s |
| `BailoutException: Code installation failed: code is too large` | 2 | 3474 ms | 6.9 s |

`min-too-large-size=2070` — the two roots are
`IMPL-FOLD-CONSTANT[2070]` (3861 ms) and `IMPL-OPTIMIZE-EXPRESSION[4030]`
(3086 ms). That there are exactly two is confirmed independently of the
summarizer by Graal's own `CompilationStatistics` bailout tally, which
reads `jdk.vm.ci.code.BailoutException: Code installation failed: code
is too large: 2`, and by the fact that the string `too large` occurs
three times in the entire 30 MB log (two trace lines plus that tally).
`total-compiler-ms=2143944`,
`nqp-root-ms=1937603` (90 % of compiler time is spent on roots that
carry a wire-word count, i.e. on nqp/Raku roots rather than on the
runtime's own Java).

### The 2026-09-07 "code is too large" cluster did not reproduce

The 2026-09-07 trace recorded **114** roots failing `code is too large`
at a mean 6.4 s, 733 s of compiler time. This trace records **2**, 6.9 s
in total — **0.9 %** of the compiler time that cluster once cost, and
0.3 % of this run's 2144 s. (Two different ratios: 6.9/733 = 0.9 %,
6.9/2144 = 0.3 %.) Whatever closed it (milestone 5's RakuObject
layout and the engine merge are the two candidates, neither measured
against it), the size-bailout lever that Task 4 exists to pull now has
essentially nothing left to gain on CORE.c.

### The dominant bailout is recursive inlining, it enters through OUR code, and it is a milestone 7 lever

442 of the 444 permanent bailouts are `Too deep inlining, probably
caused by recursive inlining.` Each carries its own inlined-method dump,
and the 442 dumps in the trace split cleanly into **two** recursions —
238 + 204 = 442, with no remainder. Both are recursions inside the JDK,
and **both are entered from our own Truffle operation nodes**: the graph
starts in generated code, walks into a Java error-reporting branch that
nothing proves dead, and drowns there.

**Chain A — the `noisyExceptions` debug branch (238 of 442).** Read
bottom-up, the way the graph is built:

```
NqpRootNodeGen.execute -> …CachedBytecodeNode.handleCreateOp_
  -> NqpRootNode$CreateOp.doCreate
  -> NqpTypeOps.create(NqpTypeOps$CreateSite, Object, ThreadContext)     <-- ours
  -> VMArray.allocate(ThreadContext, STable)                             <-- ours
  -> ExceptionHandling.dieInternal(ExceptionHandling.kt:47)              <-- ours
  -> java.lang.Throwable.printStackTrace()
  -> sun.reflect.generics.repository.ClassRepository.parse(String)  [33]
  -> sun.reflect.generics.parser.SignatureParser.parseClassSignature()
```

`ExceptionHandling.kt:47` is
`if (tc.gc.noisyExceptions) (t ?: Throwable(msg)).printStackTrace()` —
a debug-only branch behind a mutable runtime flag. Graal cannot fold the
flag, so it inlines `printStackTrace`, which reaches the generics
signature parser through reflection and recurses 33 deep. Counts:
238 dumps top-led by `ClassRepository.parse(String)` or
`AbstractRepository.<init>`, and exactly 476 = 238 x 2 occurrences of
`ExceptionHandling.dieInternal` (one in each dump's frequency list, one
in each stack trace).

**Chain B — the sited `invokeExact` attribute road (204 of 442).**

```
NqpRootNodeGen.execute -> …CachedBytecodeNode.handleBindAttrOp_
  -> NqpRootNode$BindAttrOp.doBind
  -> NqpOps.bindattr(NqpOps.java:1517)  /  NqpOps.getattr(NqpOps.java:1482)   <-- ours
  -> java.lang.invoke.Invokers.newWrongMethodTypeException(Invokers.java:522)
  -> java.lang.String.valueOf -> java.lang.invoke.MethodType.toString(MethodType.java:936)
  -> java.lang.Class.getSimpleName()  [495]
```

This is the sited MethodHandle road added in milestone 5: the
`getter.invokeExact((SixModelObject) o)` / `setter.invokeExact(…)` calls
in `NqpOps.getattr`/`bindattr`. Graal inlines the **exception-construction
branch** of `invokeExact`, and building that exception's message drags
`MethodType.toString` into a `Class.getSimpleName` recursion 495 frames
deep. Counts: 204 dumps top-led by `Class.getSimpleName()` (201 of them
at exactly `[495]`), 408 = 204 x 2 occurrences of
`newWrongMethodTypeException`, and entry points
`NqpOps.getattr(NqpOps.java:1482)` 165 + `NqpOps.bindattr(NqpOps.java:1517)`
39 = 204, exactly. (The built jar's line numbering runs a few lines
behind this worktree's source, where the two `invokeExact` calls are at
`NqpOps.java:1500` and `:1536`.)

**Nothing is actually throwing.** This is speculation, not failure, and
a reader should not go looking for a crash. The evidence: all 476
occurrences of `ExceptionHandling.dieInternal` are *dump entries*, never
printed output; there are zero `Unhandled exception` or `at org.raku…`
lines in the whole 30 MB log; and `non-trace-lines=464803` is
approximately 442 dumps x ~1000 lines, which leaves no room for 442
printed stack traces. Graal inlines these branches because nothing in
the graph proves them dead, not because they run.

**Why this is not a size bailout, and must not be taught to the
selector.** The sizes behind these 442 failures run from **27** wire
words to **17545**, with 5 carrying no size at all. A limit that refuses
a 27-word root while a 989-word root compiles successfully in 11 s is
not a limit on size. Adding this spelling to
`@SIZE-BAILOUT-SPELLINGS` would set `min-too-large-size=27`, and
`NQP_CODE_MAX_COMPILE=26` would refuse essentially every compilation in
every later measurement — not biasing the sweep but destroying it. The
unclassified block exists precisely so this reason is read by a human
instead of being absorbed; leave it there.

**The lever.** 23.7 s of compiler time is not the point. The point is
**442 roots that bail and therefore stay interpreted for the whole
compile**, on a workload whose wall clock is 90 % interpretation
(`Stage parse` 333.8 s of 434 s). Two candidate fixes, both small and
both one-sided:

1. `@TruffleBoundary` on `ExceptionHandling.dieInternal` (or on the
   `noisyExceptions` branch alone), which removes chain A from every
   compilation graph. 238 roots.
2. An `asType`/explicit-cast or guard at the `invokeExact` sites so the
   `WrongMethodTypeException` construction branch is provably dead, or a
   boundary on it. 204 roots.

Neither changes semantics, and neither is a knob — they are code, which
is why they belong to milestone 7 rather than to this sweep.

## 2. The three clocks

_(CORE.c filled in above; cold start, the green subset and the loop
bench are Tasks 8 to 10.)_

## 3. Ranked lever list for milestone 7

_(Task 11.)_

## 4. The BOOTSTRAP v6c clock — named, and left unmeasured on purpose

Task 1 measured `blib/Perl6/BOOTSTRAP/v6c.jar` at **398 s** of the
1122 s `make`, 35 % of the build and second only to CORE.c's parse. It
is not on this milestone's measurement list. The sweep's knobs are
build-wide, so BOOTSTRAP receives every adopted knob without ever being
measured, and no adopted knob was chosen against it. It is milestone 7's
leading candidate.

## 5. What the build graph does not express

No rakudo target lists an nqp artifact as a prerequisite, so a rebuilt
nqp is invisible to `make` (Task 1 found a `make` at HEAD finishing in
0 s after a clean nqp `buildJvm`). Any future measurement that changes
nqp must run `perl Configure.pl --backends=jvm` and `make clean` first,
or it measures the old nqp.

## 6. Truffle Sources do not reach the compilation statistics

Every one of the 10 763 trace lines carrying a `Src` field reports
`Src n/a`, and the `CompilationStatistics` block has no per-Source
grouping at all: it identifies targets by root name
(`maxTarget=IMPL-FOLD-CONSTANT[2070]`, `maxTarget=walk[7260]`). The
engine merge's per-block Sources therefore do **not** reach the
statistics; what does reach them is `NqpRootNode.getName()`, which is
per-block, distinguishing, and carries the wire-word count in brackets.
Attribution works — through names, not Sources. Anything that wants
file/line attribution out of the engine's own reporting needs a real
`SourceSection` on the root node first.
