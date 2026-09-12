# JVM perf findings, September 2026 (milestone 6: the compiler's own workload)

Truffle-only plan item 4. Measured 2026-09-12 on one 16-core box, 32 GB,
Oracle GraalVM 25.2.4, at rakudo `fa16081af3` / nqp `41c294b02`.

Plan and ledger:
`docs/superpowers/plans/2026-09-12-jvm-milestone-6-compiler-workload.md`
and its `.ledger.md` twin, which carries 64 numbered rulings including
every correction made to the numbers below.

---

## The headline, and it is smaller than the milestone assumed

**Guest-level Truffle compilation is worth at most 17.5 % of a CORE.c
compile, and the stock configuration captured about a third of that.**

With compilation disabled entirely the compile takes **360 s**. At the
best configuration measured it takes **297 s**. Everything Truffle's JIT
contributes to this workload lives in that 63-second gap. The unknobbed
default lands at 337 s, so it was banking roughly 23 s of the 63
available.

So this milestone did not tune a large effect. It recovered most of a
small one that the default was discarding. Every number below should be
read against that ceiling.

One qualifier that changes what the ceiling means: **the host JIT was
never off.** HotSpot kept compiling the interpreter's own bytecode
throughout, 1-5 JVMCI threads in every sample. "Compilation disabled"
means guest code runs in an interpreter that is itself JIT-compiled, not
that anything is interpreted in the naive sense.

---

## What was adopted

In `tools/templates/jvm/rakudo-j-build.in`, both platform branches:

    -Dpolyglot.engine.Mode=latency
    -Dpolyglot.engine.FirstTierCompilationThreshold=1600
    -Dpolyglot.engine.CompilerThreads=1

**Scope is exact, not approximate.** That driver is `J_RUN_RAKUDO`,
which the Makefile invokes three times — CORE.c (`:1312`), CORE.d
(`:1331`), CORE.e (`:1350`) — and nowhere else. BOOTSTRAP goes through
`J_NQP_RR` and is untouched. These options cannot reach the shipped
`rakudo-j`, which `create-jvm-runner.pl` generates separately, so the
build-side-only boundary holds by construction rather than by discipline.

**Why build-side only, and this is the load-bearing sentence for anyone
revisiting:** `EngineData.<init>` computes `firstTierOnly = (Mode ==
LATENCY)` and `splitting = Splitting && (Mode != LATENCY)`, and
`OptimizedCallTarget.compile` uses `firstTierOnly` to force every
submission to first tier. No root reaches the top tier for the life of
the process. That is right for a compile that runs once and exits and
ruinous for a long-lived Rakudo, which would cap every hot loop at
first-tier code and lose splitting as well.

### What was deliberately NOT adopted

| option | why not |
|---|---|
| `engine.MultiTier` | already defaults to **true** |
| `engine.LastTierCompilationThreshold` | **inert** under latency: `firstTierOnly` forces its gate false, confirmed in bytecode |
| `engine.PartialBlockCompilation` | already defaults to **true**, and its mechanism (`OptimizedBlockNode`) does not exist on a Bytecode DSL language |
| `NQP_CODE_MAX_COMPILE` | see below |

**`NQP_CODE_MAX_COMPILE` measured a 11.5 % fall in compiler work and was
still not adopted.** Four reasons. It is the sole cause of a
reject-and-retry storm (below). Its own case collapsed once tier policy
landed, because its saving came from suppressing large roots and large
roots are where second-tier compilation happened, which tier policy
abolishes outright. Its threshold of 2069 was derived from a cost profile
that no longer exists. And its marginal value cannot be evaluated while
its refusal mechanism is broken. Milestone 7 fixes the mechanism, then
re-derives and re-evaluates.

---

## Measurement caveats — read before any table

Every row inherits these.

**The noise floor, measured by accident.** Task 5 set an option to the
value it already defaults to, so its command line was byte-identical to
the baseline's and the pair is a genuine replicate — the only one the
forward-only rule permits.

| quantity | spread at n=2 |
|---|---|
| wall clock | 0.2 % |
| `total-compiler-ms` | 0.7 % |
| `Success` | 0.7 % (41 compiles) |
| `Permanent Bailouts` | 0.9 % (4) |

**How far it may be leaned on.** It is one pair with zero degrees of
freedom; two draws are on average closer than the true spread, so it
likely *understates* noise. Treat it as an order of magnitude, not a
confidence interval. Its wall component is a single one-second difference
at the measurement's own quantum, i.e. a **resolution limit rather than a
variance estimate**.

**`total-compiler-ms` and `nqp-root-ms` are the trustworthy quantities.**
They are wall-clock-independent and moved an order of magnitude further
than the wall did.

**"The delta lives in Stage parse" is not evidence.** Parse is ~75 % of
the wall and holds essentially all compilation, so any wall change lands
there a priori.

**The stage sum is not an independent clock.** It is a finer-resolution
reading of the same run. It defeats quantization doubt, not variance.

**Two engine statistics fields are poisoned** wherever
`NQP_CODE_MAX_COMPILE` is set: `Compilations` and `Compilation Accuracy`
are dominated by resubmissions. Compare `Success`, `Permanent Bailouts`
and `total-compiler-ms` instead. This is the caveat most likely to bite,
because those two fields look authoritative.

**Three channels report failure counts and they differ**, reconciling
exactly: the summarizer anchors on `[engine] opt failed`; a raw grep also
catches the statistics block's per-reason repetitions and any line
Truffle wrote into a `Stage` line; the statistics block gives `Permanent
Bailouts`. Always say which channel a number came from.

**The summarizer undercounts by one to four lines per run**, where a
trace line landed inside a stage line and its `starts-with` filter
dropped it. It is **not a constant bias** (3 in one run, 4 in another),
so never correct by a fixed offset — read the statistics block.

**Identity is `id=`, not `name[size]`.** That label merges about 10 % of
distinct call targets (1672 targets against 1515 labels). Anything
counting unique roots must count by id.

---

## The CORE.c configuration table

Standalone traced compiles, one sample per configuration, forward-only.

| # | configuration | wall | `Stage parse` | `total-compiler-ms` | `Success` | verdict |
|---|---|---|---|---|---|---|
| 3 | none (baseline) | 434 s | 333.841 | 2 143 944 | 5658 | reference |
| 5 | `PartialBlockCompilation=true` | 433 s | 335.187 | 2 129 872 | 5617 | DROP — it is the default; this is a replicate |
| 4 | `NQP_CODE_MAX_COMPILE=2069` | 419 s | — | 1 898 458 | 5671 | measured, **not adopted** |
| 6 | tier policy alone | **337 s** | 253.998 | **783 440** | 3334 | **KEEP** |
| 7 | tier policy + 3 threads | 327 s | 248.832 | 619 075 | 3000 | superseded by 1 thread |
| — | tier policy + 1 thread | **297 s** | 225.941 | **277 722** | 1578 | **KEEP** |
| — | compilation disabled | 360 s | 278.213 | 0 | 0 | bound, not a configuration |

Row 5 is a replicate of row 3: it set an option to its own default, which
is how the noise floor above was obtained. Row 4's parse is omitted
because that run's stage lines collided with trace output.

**Tier policy's mechanism, verified to the millisecond.** `Mode=latency`
eliminates second-tier compilation entirely: 1372 second-tier compiles
become 0, and that tier was **1 019 837 ms — 53.7 % of compiler time for
a quarter of the compilations**. The residual reconciles exactly: the
first-tier fall of 234 147 ms plus the second-tier block accounts for the
whole 1 254 144 ms drop. Attribution is roughly **81 % latency mode, 19 %
the raised first-tier bar**, both genuinely tier policy. Splitting is not
a confound: every run reports `Splits : 0`, so disabling it contributed
zero.

---

## The compiler-thread curve

Seven points, tier policy throughout, unique targets by `id=`.

| threads | wall | `Stage parse` | `total-compiler-ms` | unique targets | coverage |
|---|---|---|---|---|---|
| none | 360 s | 278.213 | 0 | 0 | 0 % |
| **1** | **297 s** | 225.941 | 277 722 | 1033 | 61.8 % |
| 2 | 323 s | 249.839 | 503 022 | 1552 | 92.8 % |
| 3 | 327 s | 248.832 | 619 075 | 1626 | 97.2 % |
| 4 | 341 s | 260.621 | 728 428 | 1649 | 98.6 % |
| 6 (default) | 337 s | 253.998 | 783 440 | 1672 | 100 % |
| 16 | 346 s | 262.367 | 893 381 | 1672 | 100 % |

**A U with its minimum at the engine's hard floor of one.** Compiler time
is strictly monotone increasing across the whole range; the second thread
alone costs +81 % of it. The per-thread wall slope flattens ~29x, from
26 s for the second thread to 0.9 s for each of the last ten.

**Why fewer threads is faster, and it is not a scheduling win.**
Compilation is ordered by call count, so one thread compiles the 1033
hottest targets and never reaches the tail; the 639 it skips were not
repaying themselves inside a run-once compile. Going from 6 to 16 threads
buys **21 extra compilations and zero new targets** — every one a
recompile of something already compiled. Compiles per target run
1.84 / 1.99 / 2.01 across 3/6/16, and deoptimisations rise in step
(3522 / 3767 / 3808).

The fit, labelled a fit: **the compile queue is a debouncer.** A root
that deoptimises and re-requests compilation several times in quick
succession has those requests superseded and collapsed when the queue is
slow — stale dequeues run 1137 / 190 / 2 across 3/6/16 threads. A fast
queue faithfully services every redundant request.

**So reducing compiler threads is a workaround for deoptimisation churn,
not a scheduling optimisation.** Testable prediction for milestone 7: fix
the churn and this knob's benefit should shrink or vanish. If it does
not, the debounce fit is wrong.

**Unresolved, and the weakest part of this milestone.** Occupancy across
the curve is 0.94-2.58 cores of 16. The fastest run left about fourteen
idle, so no contention account fits, and "off the critical path" was
reached by subtraction rather than shown. One untested candidate:
installation and invalidation are not free to the mutator even when
compilation is off-thread, which would make cost scale with compilation
*count* rather than CPU — which is what the curve shows. Settling it
needs process-CPU accounting nobody took.

---

## The hot loop

`docs/bench/jesp/plusquick.raku`, stock (no engine options; the bench is
a runtime measurement and everything adopted is build-side).

**ns/op 85.825**, `hits=90247946 misses=11623 slowEvals=976 invokes=13867
directs=13848`. `resume-smoke.raku` unchanged.

**Milestone 5's +3.5 % regression is NOT established.** Four identical
stock runs at one build gave **85.825 / 89.375 / 87.400 / 89.175 ns/op —
a 4.1 % spread, wider than the delta being explained** — with a
byte-identical dispatch-stats line every time. Milestone 5 ran one sample
per side.

The noise has a named cause and it is a **benchmark defect**: plusquick's
mainline has two OSR call targets, one per `while` loop, so its 5 M
warm-up warms a different target than the one timed, and the timed
target's compiles land 200 ms and 470 ms into a 3.010 s window. **Future
ns/op comparisons need a median of five or more runs**, and the bench
wants fixing.

**The dispatch counters cost 10-15 %.** Six runs: 85.8-89.4 ns/op with
`NQP_DISPATCH_STATS=1`, **75.3 and 82.9 without**. Milestone 5's pair was
instrumented on both sides so its comparison stands, but **no jesp ns/op
figure on record is the runtime's actual cost per operation.**

The tripled `slowEvals` counter is inert: all 976 are
`NqpDispatch.AttrSrc.slow` over three keys, all at start-up,
deterministic. 976 boundary crossings cannot buy 116 ms. Both of
milestone 5's leads are ruled out **categorically** — `DecontSite` and
`BigIntSite` are `NqpTypeOps.Site`s with a per-site `misses` counter and
touch neither quantity. Variant layouts ruled out by measurement
(`layouts=2122 variants=0 reblesses=2`).

---

## The ahead-of-time spike: closed

Measured, then closed on the numbers. It loses on every wall clock at
every workload size.

| workload | JVM | image |
|---|---|---|
| CORE.c compile | 297 s complete | **785 s, still in parse** |
| `nqp -e 'say(1)'` | 1.93 s | 2.82 s (1.46x) |
| `rakudo -e` | 3.66 s | 5.45 s |
| nqp suite, 151 files | 599 s | 648 s (+8 %) |

Its one favourable axis is CPU — 4.3x cheaper on startup, ~4x across the
suite — which matters only where CPU rather than wall time is scarce.

**What is banked regardless, and it is substantial:**

1. **The unit-artifact road is validated end to end.** An image built
   from nqp alone **loaded `rakudo.jar` as pure data and ran Raku** —
   `unit.meta` + `unit.programs` + a serialized context, zero `.class`.
   Rakudo did not exist at image-build time and did not need to. That is
   what milestones 1-4 were for and it had never been tested.
2. **The nqp runtime is semantically identical under a different
   execution model.** 151 files, 13 144 tests: the nine known-red files
   are **nine for nine identical, down to individual test numbers**.
   Nothing moved either way.
3. **A premise of mine was wrong and is corrected here:** an image
   removes **class** loading, not **artifact** loading. JVM boot is ~0.1 s
   of the 1.9 s baseline; our cold start is artifact decoding, which an
   image never touches.
4. **The engine cache is retired as a motivation.** It would hold nothing
   today (zero successful compilations in the image) and first-tier code
   at best once fixed, all under the 17.5 % ceiling.
5. **The recipe rebuilds in ~90 s**, with the full list of what a build
   demands — the real measure of the distance, should anyone revisit.

Two findings about the codebase that have nothing to do with imaging:
**character encodings are not compiled in** (`UnsupportedCharsetException:
windows-1252`; Rakudo would hit it too, and it was on nobody's list), and
**`try`/`CATCH` masks missing-registration errors as nonsense
NullPointerExceptions** — `NQP_VERBOSE_EXCEPTIONS=1` is the first triage
step on any image.

Also: **the tracing agent that generates image metadata is structurally
insufficient for this codebase.** Classlib ops resolve by *name*, so it
under-registers silently and dies at an arbitrary op, arbitrarily late.
That is not a gap to fill but a method that cannot work here.

---

## The FFI question, answered

Tabled by the user 2026-09-11: would prohibiting runtime use of the
`native` trait give the closed set of descriptor shapes an image needs?
The rule, as specified: for any routine declared with the `native` trait,
prohibit (i) **adding arguments to a signature** at run time and
(ii) **replacing the signature of a routine** at run time.

**Verified in code.** `lib/NativeCall.rakumod`'s `!setup` reads
`$routine.signature` and derives arg info via `param_list_for` and the
return via `map_return_type`; `NativeCallOps.kt`'s `descriptorFor` maps
`ArgType` — a finite enum — through `layoutFor` onto ~7 `ValueLayout`
carriers plus `ADDRESS`. **A descriptor shape is a pure function of a
compile-time signature over a small fixed alphabet.** `!setup`'s laziness
is handle *construction*, not shape *determination*; do not confuse them.

**The answer, in two cases.** For an image of a **specific Raku program**
the rule **closes the set completely** — and it is what makes that case
*provable*, not merely a tightening of it, because without it a program
could demand a shape appearing nowhere in its own source. For an image of
the **Rakudo distribution** the set stays open, but because the image
ships a compiler, which is a property of distributing a compiler rather
than a flaw in the rule.

**The rule's real value: it makes a covering-set or trampoline design
sound.** The alphabet is small and every shape statically derivable, so a
bounded pre-registered set can be proven to cover everything. It also
enables **precomputation** — a module's descriptor set can be emitted when
the module is precompiled, and an image registers the union of what is
installed. That replaces registration-by-tracing, which is unsound here.

**A third vector the rule does not cover:** `EVAL` of source containing
`is native` is compilation, not mutation, so the distribution problem
reappears inside an imaged program. Needs its own decision.

Empirical note: NativeCall fails in an image before user signatures
matter at all — `buildnativecall` itself performs an FFM downcall for
symbol lookup (`MissingForeignRegistrationError: (long,long,long)long`).

---

## What milestone 7 inherits, ranked

**Six of these eight are one pattern: slow paths visible to the
inliner.** `nqp/src/vm/jvm/runtime` contains **zero `@TruffleBoundary`
annotations** against 113 in `nqp/nqp-truffle/src`. That whole older tree
is called from Truffle nodes with every slow path fully visible. The
survey is the highest-value item here.

1. **The 442-root inlining bailout.** 442 of 444 compilation bailouts in
   a CORE.c compile are Graal inlining slow paths that never execute
   until it gives up on depth, leaving those roots interpreted for the
   whole compile. Two chains: 238 enter at `NqpTypeOps.create` →
   `VMArray.allocate` → `ExceptionHandling.dieInternal(:47)`, whose
   `printStackTrace` sits behind an env flag; 204 enter at
   `NqpOps.getattr:1482` and `bindattr:1517`, where the JDK constructs a
   wrong-method-type exception message. **Nothing throws — this is
   speculation.** Fix: `@TruffleBoundary`, not a constant; folding the
   flag removes only the print branch while `dieInternal`'s 40-frame
   `StringBuilder` walk stays inlinable. A `static final` hoist is a
   cheap complement. Note `@CompilationFinal` on the instance field would
   be a **no-op**, because `tc` comes off the frame so `tc.gc` is never a
   PE constant.
2. **Make the size refusal permanent**, then re-derive the threshold and
   re-evaluate the knob. `prepareForCompilation` returning false is a
   *retryable* bailout, so a refused root resubmits forever: **1 456 361
   retryable "not ready" bailouts against 144** in the baseline, about one
   useful compilation per 258 submissions. Its measured -11.5 % was
   achieved despite that, so a permanent refusal should beat it.
3. **Deoptimisation churn.** 1672 targets averaging ~2 compilations each;
   `encode_var[6418]` compiles **13 times** (one id, verified), with 10
   uncommon traps and **6 `validRootAssumption local tags updated`** —
   the Bytecode DSL's per-local type-tag guard invalidating a whole root
   when a local holds a type outside its tag set. Whole-run reasons:
   uncommon trap 1192, dispatch site 580, JVMCI invalidate 539, local
   tags 245, profiled return type 113, and `Unknown` 2030 (so the
   aggregate is suggestive; per-root figures are exact).
4. **The image's 100 % compilation bailout:** `NFGString.atomsOf` reads a
   `WeakHashMap` inside `RxMatchRootNode.execute`. One `@TruffleBoundary`.
5. **`NqpTypeOps.decont:267` calls `miss(site)` only when `ost !== st`.**
   A site with a matching STable but a mismatching layout re-crosses the
   boundary forever, never pinning and **never appearing in any counter**
   — invisible by construction.
6. **`AttrSrc.slow` merges two branches into one counter**, so a
   layout-matched null slot is indistinguishable from a real slow path.
7. **Disambiguate root names.** `name[size]` merges ~10 % of distinct
   targets, and the engine's own `CompilationStatistics` groups by it, so
   a target reported as compiled 13 times could be two at 7 and 6.
8. **Re-run the root-multiset analysis by `id=`** before relying on it.

**Named and deliberately unmeasured: BOOTSTRAP v6c is 398 s of the
build**, 35 %, second only to the CORE.c parse. The adopted options are
build-wide within the setting compiles but BOOTSTRAP runs through a
different driver and receives none of them. It is milestone 7's leading
*measurement* candidate.

---

## Things that cost time to learn

**The build graph does not express the nqp dependency.** No rakudo target
lists an nqp artifact as a prerequisite, so a rebuilt nqp is invisible to
`make` and a plain `make` after an nqp change is a **0-second no-op**.
Any measurement that changes nqp must run `Configure.pl` and `make clean`
first, or it measures the old nqp.

**Milestone 5 recorded two `make` figures** — 1054 s incremental after a
clean nqp build, and 1133 s for `make clean && make` — and its own record
says to baseline against both. Comparing a clean build to the incremental
number invents a 68-second regression that does not exist.

**Screen every knob before spending a compile.** Two checks, each seconds
long, each of which would have saved a 433-second measurement on its own:
*is the value already the default* (`javap` on
`OptimizedRuntimeOptions`), and *does the mechanism exist on our path*
(`PartialBlockCompilation` lives only in `OptimizedBlockNode`, which a
`@GenerateBytecode` language never uses).

**`NqpCheck` false-rejects experimental options.** It builds its context
without `allowExperimentalOptions(true)` while `NqpPolyglot.kt:49-51` —
the context the compiler actually uses — enables them. A missing
`nqp-code check passed` means the probe cannot judge, not that the option
is bad. Verify on the real engine path instead
(`./nqp/nqp-j-gradle -e 'say("engine-ok")'`, ~20 s), and remember that
**accepted is not the same as in force**.

**The eval server exports `Compilation=false` to its children**
(`create-jvm-runner.pl:301`). Any benchmark run through it measures an
interpreter.

**Two benchmarks in the tree have defects of their own**: plusquick times
a loop its warm-up does not warm, and `resume-smoke.raku` has no
`.expected` file beside it, so "unchanged" is a judgement call.
