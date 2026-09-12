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

`min-too-large-size=2070` (`IMPL-FOLD-CONSTANT[2070]`, then
`IMPL-OPTIMIZE-EXPRESSION[4030]`). `total-compiler-ms=2143944`,
`nqp-root-ms=1937603` (90 % of compiler time is spent on roots that
carry a wire-word count, i.e. on nqp/Raku roots rather than on the
runtime's own Java).

### The 2026-09-07 "code is too large" cluster did not reproduce

The 2026-09-07 trace recorded **114** roots failing `code is too large`
at a mean 6.4 s, 733 s of compiler time. This trace records **2**, 6.9 s
in total — 0.3 % of the compiler time that cluster once cost, and 0.3 %
of this run's 2144 s. Whatever closed it (milestone 5's RakuObject
layout and the engine merge are the two candidates, neither measured
against it), the size-bailout lever that Task 4 exists to pull now has
essentially nothing left to gain on CORE.c.

### The dominant bailout is now recursive inlining, and it is not about size

442 of the 444 permanent bailouts are `Too deep inlining, probably
caused by recursive inlining.` The bailout message carries its own
inlined-method dump, and the recursion it names is entirely on the Java
side:

```
java.lang.Throwable.printStackTrace()
org.raku.nqp.runtime.ExceptionHandling.dieInternal(ThreadContext, String, Throwable)
  -> sun.reflect.generics.repository.ClassRepository.parse(String)  [33 frames]
  -> sun.reflect.generics.parser.SignatureParser.parseClassSignature()
```

i.e. the generics-signature parser reached through the exception
reporting path, inlined 33 deep. It is independent of the nqp root's
size: the sizes behind these 442 failures run from **27** wire words to
17545. That is why the summarizer leaves them in the unclassified block
rather than treating them as a size bailout — classifying them would
set `min-too-large-size=27` and produce a threshold at which nothing
compiles.

At 23.7 s of 2144 s this is not itself a large clock, but it is 442
compilations thrown away, and the cause is one Java call chain rather
than anything in the generated code. Named here for milestone 7.

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
