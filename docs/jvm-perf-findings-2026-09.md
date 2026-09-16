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

## Milestone 7, Phase A: the runtime levers (2026-09-13 to 2026-09-15)

Spec: `docs/superpowers/specs/2026-09-13-jvm-milestone-7-first-execution-design.md`;
plan and ledger: `docs/superpowers/plans/2026-09-13-jvm-milestone-7-first-execution-phase-a*.md`.
Rig: `tools/build/m7-rig.raku`; rows are cold `rakudo-j -e 'say 1'` and
`nqp-j-gradle -e 'say(1)'` best of 5, the dispatch counters of the best
rakudo run, and warm `t/02-rakudo` (306 files) on one 8 GB eval server.
**From row a6 on, the rig's per-lever row is the two cold rows plus warm
`t/01-sanity`** (Task 9b, user rule 2026-09-15: no fine-grained gating),
so the warm `t/02-rakudo` column is a series taken base..8c (the
ledger's row `a8`) and closed there; the gates are the nqp suite and
`t/01-sanity`.

| lever | rakudo / nqp hash | cold rakudo-e | cold nqp-e | misses | warm t/02-rakudo | verdict |
|---|---|---|---|---|---|---|
| base | bc00863fef / c17d93d27 | 2.502 s | 1.135 s | 6815 | 3204 s | base |
| A1 presized SC maps | 76b62a0b4f / cb654e4bf | 2.518 s | 1.125 s | 6815 | 3232 s | struck (kept: harmless) |
| A2 diagnostics | b5c559de25 / 793161369 | 2.509 s | 1.085 s | 6815 | 3193 s | diagnostics (no claim) |
| A3 callback via unit road | ee460e4775 / 7602b2254 | 2.543 s | 1.100 s | 6815 | 3209 s | struck (kept) |
| A4 stub fast path | e6a29ddc9e / 39688c263 | 2.496 s | 1.116 s | 6815 | 3179 s | struck (kept) |
| A5 record off the maps | 7287e64a60 / 942ff0a5f | 2.516 s | 1.145 s | 6815 | 3153 s | struck (kept) |
| A7 boundaries | e965a90438 / f36509da7 | 2.611 s | 1.151 s | 6815 | 3165 s | struck (kept) |
| 7b runners on the class path | b3daa412c1 / 9f0417c5d | 2.604 s | 1.165 s | 6815 | - (cold only) | landed (marker true) |
| A8 dispatcher compilation (spike) | 114175eaa8 / f36509da7 (ledger only, no rig row) | - | - | - | - | struck: no threshold change |
| 8b raku-invoke bailout (diagnosis) | 157695f982 / 9f0417c5d (ledger only, no rig row) | - | - | - | - | finding; the fix is 8c |
| 8c constant handle per branch | 56e78028bf / 4736905d0 | 2.597 s | 1.148 s | 6815 | 3202 s | landed (compile shape) |
| A6' static clone road | 96f643b334 / 4736905d0 | 2.504 s | 1.192 s | **5661** | 3735 s (not gathered: battery + first post-cache-clear sweep) | landed (counters) |

Hits, the second counter, are 125055 for every row base..8c (the
ledger's row `a8`) and **100697** at a6. The cold clocks' own spread
over the series is 2.50-2.64 s
(rakudo) and 1.09-1.19 s (nqp); the warm series runs 3204, 3232, 3193,
3209, 3179, 3153, 3165, 3202 — a 1.6 % drift across a2..a5 that no single
row can claim.

**What moved and why.**

**A6' (the static clone road) is the only lever with a counter change.**
A6 as specified rested on a false premise: the 2026-09-13 survey looked
for `method clone` under `src/core.c` only, but `BOOTSTRAP.nqp` defines
`Code.clone` (:3099) and `Block.clone` (:3165), which Routine/Sub/Method
inherit, so the compile-time test `findmethod($code-obj,'clone') =:= Mu's`
was false for every closure and the emitted road would never have fired.
A6' keeps the spec's intent — fewer misses — by having `p6clonecode`
mirror `Block.clone`'s mandatory half natively (REPR clone, clone of the
`$!do` CodeRef, `setcodeobj`, rebind); the three optional tails are split
between a compile-time check (a phasers hash or `$!why` on the code
object, and a `clone` that resolves to Block's or Code's, and not a
regex) and a run-time check (`@!compstuff` non-null takes the method
road). Result: misses 6815 -> 5661 (`lang-meth-call` 4626 -> 3472, the
1148 setting closure sites plus a few), hits 125055 -> 100697 as the
per-creation method road goes with them, cold rakudo-e 2.504 s. The
compile side pays nothing measurable: CORE.c stagestats on the A6' make
(723 s) read parse 213.806 s / optimize 22.152 s / qast 16.977 s / unit
22.619 s against 215.383 / 22.369 / 16.790 / 22.839 on the same day's
struck-A6 make.

**8c (one constant handle per branch) is the only compile-shape change.**
`NqpOps.getattr`/`bindattr` merged the two cache entries' `MethodHandle`s
into a phi, so `invokeExact`'s exact-type check could not fold and the
JDK's `newWrongMethodTypeException` -> `MethodType.toString` ->
`Class.getSimpleName` recursion entered every graph. Each entry now
invokes its own handle on its own branch (`readSlot`/`writeSlot`, private
statics that PE inlines with the branch's constant handle). Over a cold
`rakudo-j -e 'say 1'`: `opt failed` 3 -> 0, `Too deep inlining` 3 -> 0,
and `<anon>@perl6:qb_4626[2838]` — `raku-invoke`, the busiest root in the
whole cold run at 2546 traced entries — now compiles (Tier 1, 202 ms, IR
3463/8175, CodeSize 41157, queued at `Count/Thres 400/400`) instead of
running interpreted for the process lifetime. The other two bailing roots
(`<anon>@perl6:qb_126[349]`, `mro@FD5A9459…:qb_187[204]`) compile with
it, which closes the 204-root half of inherited item 1. The clocks are
inside the spread; the log is the measurement.

**7b (runners on the class path) made the runtime-tree boundaries real
under the nqp runners.** `NQP_BOUNDARY_CHECK` printed
`dieInternal TruffleBoundary=false` under `nqp-j-gradle` and `true` under
`./rakudo-j`: the generated runners put the runtime jars on
`-Xbootclasspath/a`, where the boot loader cannot resolve
`CompilerDirectives$TruffleBoundary` and silently drops the annotation.
Moving every former boot entry ahead of `$CP` in
`nqp/buildSrc/src/main/kotlin/GenerateRunnerTask.kt` flips the marker to
`true` under all three runners. Cold nqp-e 1.165 s, flat. Collateral
worth knowing: editing `nqp/buildSrc` invalidates gradle's whole nqp
stage graph, so `generateRunner` rebuilt stage1/stage2 and every
share/lib jar, and the fresh serialization-context handles broke
`./rakudo-j` ("Missing or wrong version of dependency
`.../stage2/NQPHLL.nqp`") until a full rakudo `make` (797 s) re-linked
it — which is why a7b's cold rakudo-e is a rebuilt-artifact reading, not
a like-for-like delta against a7.

**A2 claimed no number and delivered the instrument the phase ran on**:
the misses-by-dispatcher histogram, `decont` pinning a layout mismatch as
well as an STable mismatch, `AttrSrc.slow` split in two, and root names
carrying the block id (`<name>@<cuid>[N]`, or `<name>@<unit-sha>:qb_N[N]`
for a jar-bound block, whose `cuid` is null by design) so the engine's
`CompilationStatistics` stops merging distinct targets. The histogram is
five dispatchers long, not eight, and `lang-meth-call` is 68 % of all
misses — which is what made A6' the phase's one moving lever.

**Struck.**

- **A1, presized SC maps** (`76b62a0b4f`): every clock inside the base
  row's own spread, counters bit-identical; kept because it cannot
  regress. The reader's rehash share is 17 % of the SC read, about 1.7 %
  of the cold run — below the rig's resolution by construction.
- **A3, dispatcher callbacks through the unit road** (`ee460e4775`):
  2.543 / 1.100 / 3209, counters identical; kept, the road is simpler
  than what it replaced.
- **A4, stub-road fast path** (`e6a29ddc9e`): 2.496 / 1.116 / 3179, every
  clock better than base by less than the spread; kept, three lines that
  remove a switch from the hot path.
- **A5, record and realize off the hash maps** (`7287e64a60`): 2.516 /
  1.145 / 3153 (the fastest warm row of the series), counters identical;
  kept.
- **A7, the classlib boundary and the targeted ones** (`e965a90438`):
  2.611 / 1.151 / 3165 — the high end of the cold spread, inside it on
  both clocks; kept, since it matches the table road, with
  `NQP_CLASSLIB_INLINE=1` left in as the A/B. The lever the spec expected
  to move the warm clock moved it neither way.
- **A8, compiling the dispatcher programs early** (spike, no code): four
  of the five hot dispatcher roots already reach compiled code 22-42 % of
  the way through their traced entries, and lowering the first-tier
  threshold is worse in *every* round measured — medians of 7 interleaved
  rounds, 2531 ms at the default 400 against 2714 (150), **2986 (50,
  +455)** and **3222 (10, +691)**. The bottleneck is compilation
  *capacity*, not latency: only 22 roots finish a compilation in the
  ~2.5 s a cold run lasts, so submitting more roots earlier steals CPU
  from the interpreter doing the work. No option goes into the runner
  defaults. The spike's real output was the `raku-invoke` permanent
  bailout, diagnosed in 8b and fixed in 8c.
- **A6 as specified** — struck on the false premise above and replaced by
  A6', which is what the row measures.

**The promotion list (A7 Step 8): empty.** Its trigger was cold rakudo-e
above 2.64 s or warm above ~3210 s; a7 read 2.611 s and 3165 s, so Step 8
never ran and no classlib op was promoted to a sited node. The list stays
open for Phase B, where `NQP_CLASSLIB_INLINE=1` is the one-command A/B.

**What Phase B starts from:** the a6 row — rakudo `96f643b334` / nqp
`4736905d0`, cold rakudo-e **2.504 s**, cold nqp-e **1.192 s**, misses
**5661**, hits **100697**, histogram `3472 lang-meth-call` /
`1947 lang-call` / `206 boot-syscall`. The warm basis is the comparable
base..8c (the ledger's row `a8`) series (3204 -> 3202 s, best 3153 at
a5); a6's own warm number is not gathered (the box was on battery and it was the first sweep after
the rig's precomp-cache clear, so 120 modules re-precompiled inside it:
client CPU rose 12 s while wall rose 531 s). Per the user rule of
2026-09-15 it is not re-run; the next `t/02-rakudo` clock is the one
Phase B already plans to take.

**Phase B's inbox** (carried out of Phase A's rulings and deferred
minors):

1. **CLOSED by the Phase A fix wave (nqp `fdab66706`): the getattr/bindattr road's remaining minors** (the doc comments and the three-copy note landed; the `RakuObject` narrowing stays deferred), ranked here because
   8c sits on them: the helper doc comments name the handle types as
   `(SixModelObject)Object` / `(SixModelObject,Object)void` where the
   exact descriptors are `(SixModelObject)SixModelObject` /
   `(SixModelObject,SixModelObject)void`; `readSlot` could take the
   narrowed `RakuObject`; the null-read-falls-to-slow policy exists in
   three deliberate copies and wants a one-line comment.
2. **`NqpTypeOps.create` still misses unconditionally** on a
   layout/REPRData mismatch (not the deserialization-stub shape A2
   fixed in `decont`) — an uncountable, unpinnable site by construction.
3. **The in-build stage `JavaExec` tasks are still on the boot class
   path** (`nqp/build.gradle.kts:232-241`, its comment now stale), so
   runtime-tree boundaries stay invisible to the JVM that compiles nqp's
   own stages. Compile-time only; 7b fixed the generated runners, not
   these.
4. **The classlib boundary's deopt-on-exception, as a narrow claim**:
   `@TruffleBoundary` on `NqpOps.classlib` (and on the table road's
   `run()`) uses the default `transferToInterpreterOnException = true`,
   so an exception leaving a classlib op deoptimizes the enclosing
   compiled root instead of propagating inside compiled code. The
   earlier form of this item said NQP's control-flow categories
   (`EX_CAT_NEXT`, `LAST`, `RETURN`) travel that way, and that is
   **wrong**: every throwing op is registered `:cont`
   (`nqp/src/vm/jvm/QAST/Compiler.nqp:511-529`) and the encoder refuses
   the classlib road for a `:cont` op
   (`nqp/src/vm/jvm/QAST/TruffleEncoder.nqp:2567`, `cbail('classlib
   cont op ...')`), so NQP control flow never leaves through
   `NqpOps.classlib` at all. What is left is the one exception that
   *can* cross the boundary: one raised inside a classlib op that
   re-enters guest code — the binder's `ACCEPTS`, `p6bindsig` and
   friends — a narrow path. The item stays in the inbox as that narrow
   claim, and its A/B is `NQP_CLASSLIB_INLINE=1` on a workload that
   actually throws through a classlib op (not a workload that merely
   uses `next`/`last`/`return`).
5. **The promotion list (A7 Step 8) is empty** and stays open: no
   classlib op has been promoted to a sited node, and the trigger that
   would have found one never fired.
6. **`NFGString.of`'s boundary is coarser than needed** — it also hides
   the `isEmpty` short-circuit and the interned-hit read; a miss-path-only
   boundary would keep the hit path PE-visible.
7. **`dispatchWithDescriptor` still `find`s per record**
   (`Dispatch.kt:193`) — a linear scan on the record path A5 otherwise
   took off the hash maps.
8. **CLOSED by the Phase A fix wave (nqp `fdab66706`): the site fields' memory model** (one volatile immutable `CachedDispatcher` holder): `DispatchCallSite.dispatcher` and
   `dispatcherEpoch` (added by A5) are plain fields, so a torn read pairs
   a fresh epoch with a stale `Dispatcher`. Bounded today because
   `register` runs at load scope only; `@Volatile` or an immutable pair
   if a language ever registers mid-run.
9. **`signature.rakumod:1918` stays on the method road** — a `Code`
   default value in a signature is the one closure site A6''s static road
   does not take.

---

## Milestone 7, Phase B: the format, once (2026-09-15)

Spec: `docs/superpowers/specs/2026-09-13-jvm-milestone-7-first-execution-design.md`,
"Phase B", over
`docs/superpowers/specs/2026-09-13-jvm-lazy-unit-loading-design.md`
tasks 1.1-1.6. Plan and ledger:
`docs/superpowers/plans/2026-09-15-jvm-milestone-7-first-execution-phase-b*.md`.
The format itself is documented in `docs/jvm-unit-lazy-loading.md`.

What landed: artifact **v2** -- a stored (uncompressed, mappable) zip of
five entries, one mapping sliced per entry, three fixed-width index
tables, a `BlockRecord` per block instead of one global blob, lazy
`StaticCodeInfo` bodies behind `ensureBody()`, one load road for a file
and for an in-memory unit, **site identity** through the compile key, an
**empty `unit.dispatch`** table, stage0 regenerated as v2, and the v1
reader deleted.

### (a) The row

| lever | rakudo / nqp hash | cold rakudo-e | cold nqp-e | misses | hits | warm t/01-sanity |
|---|---|---|---|---|---|---|
| a6 (Phase A close) | 96f643b334 / 4736905d0 | 2.504 s | 1.192 s | 5661 | 100697 | 51 s (proxy smoke) |
| **b (Phase B close)** | 107eca63a3 / 318558c2d | **2.461 s** | **1.160 s** | 5667 | 100711 | **50 s** |

Best of five, stock runners, `NQP_UNIT_LOAD_STATS` and
`NQP_DISPATCH_STATS` on; the rig itself took 70 s. The b run's five
rakudo walls were 2.50 2.53 2.46 2.67 2.61 and its five nqp walls 1.23
1.17 1.16 1.22 1.25, so both clocks are **inside the series' own
spread** (2.50-2.64 s and 1.09-1.19 s across Phase A) and Phase B claims
neither. Miss histogram, essentially unchanged from a6 (3472 / 1947 /
206): `lang-meth-call=3473 lang-call=1952 boot-syscall=206
raku-assign=35 raku-meth-call-qualified=1`; the +6 misses and +14 hits
over a6 are site-identity bookkeeping, not a behaviour change. New
counters on the same line: `sites=7427 anon=6`. **These count WIRE
dispatch sites only**: both are incremented in `NqpDispatch.Cache`'s
constructor, and a `Cache` is built in exactly one place --
`NqpOps.EngineSite`, once per `DISPATCH` instruction of a parsed program
-- so 7427 is the dispatch instructions a cold `rakudo -e 'say 1'`
parses, and the six without an identity are **the `-e` script's own**,
whose unit is in-memory and therefore identity-less. The runtime's own
sites (`Ops.helperDispatchSites`, Rakudo's rv-decont site in `RakOps.kt`,
the indy road's `DispatchBootstrap.fromIndy`) build a `DispatchCallSite`
directly, never a `Cache`, so they are identity-less AND uncounted; if
the number is to mean "every site in the process", Phase C has to count
them. (Corrected 2026-09-15: the close first read the six as the helper,
rv-decont and indy sites. Ruling 8's point -- that identity-less sites
exist and Phase C must tolerate them -- stands; only the attribution of
the six was wrong.)

**The honest summary: the format change is clock-neutral at the top
level.** It was not undertaken for the cold clock alone -- it is what
Phase C's persisted miss addresses through, and what phase 2's demand SC
read needs -- but the per-stage rows below say where the time went, and
they did move.

### (b) Per-stage, before and after

From the best cold run's `unit-load` lines (v1 = the a6 rig's
`a6-rakudo-e-run1.err` / `a6-nqp-e-run1.err`; v2 = this rig's
`b-rakudo-e-run3.err` / `b-nqp-e-run3.err`). **The stage names do not
line up one to one**: v2 has no decode stage at all, because record
decoding moved into the `ensureBody` fills that happen during
`deserialize-program` and `load-block`. Compare `load-total`, and the
sum of the stages that are pure load-road work.

`CORE.c.setting.jar`, cold `rakudo-j -e 'say 1'` (ms):

| v1 stage | v1 | v2 stage | v2 |
|---|---|---|---|
| `read-file` (5892366 B) | 4.05 | `open-store` (56067270 B) | 2.07 |
| `inflate` (-> 13104735 B) | 54.74 | - | - |
| `decode-meta` (19933 blocks, 49963 staticlex) | 27.93 | - | - |
| `decode-programs` (19933) | 29.60 | - | - |
| `decompress-sc` (-> 28159756 B) | 18.46 | - | - |
| `decode-nested` (4) | 0.14 | - | - |
| **`decode-total`** | **133.77** | (no decode stage) | - |
| `build-table` (19933 + 4x4 blocks) | 13.74 | `shells` (same) | 22.31 |
| `sc-stub` (5558 stables, 276103 objects) | 37.82 | `sc-stub` (same) | 83.53 |
| `sc-finish` | 63.78 | `sc-finish` | 92.89 |
| `deserialize-program` (+ 4 nested) | 164.02 | `deserialize-program` (+ 4 nested) | 271.17 |
| `static-lex-values` (49963 rows) | 10.15 | `static-lex-drain` (98 blocks) | 0.20 |
| `load-block` | 327.63 | `load-block` | 381.64 |
| **`load-total`** | **653.59** | **`load-total`** | **676.80** |
| load road only (all but `deserialize-program`/`load-block`) | 263.31 | same | 200.99 |

`nqp.jar`, cold `nqp-j-gradle -e 'say(1)'` (ms):

| v1 stage | v1 | v2 stage | v2 |
|---|---|---|---|
| `read-file` (139990 B) | 1.00 | `open-store` (1145720 B) | 22.82 |
| **`decode-total`** (inflate + meta + programs + sc; 559 blocks, 559 programs) | **19.27** | (no decode stage) | - |
| `build-table` (559) | 5.19 | `shells` (559) | 1.98 |
| `sc-stub` (23 stables, 2989 objects) | 0.85 | `sc-stub` | 1.17 |
| `sc-finish` | 6.18 | `sc-finish` | 2.96 |
| `deserialize-program` | 628.51 | `deserialize-program` | 581.17 |
| `static-lex-values` (24 rows) | 0.02 | `static-lex-drain` (0 blocks) | 0.00 |
| **`load-total`** | **662.37** | **`load-total`** | **612.75** |

What this says:

- **The decode stage is gone, as designed.** 133.8 ms on CORE.c and
  19.3 ms on nqp.jar of inflate + record decode + program decode + LZ4
  of the SC blob do not happen. `read-file` -> `open-store` is an
  `mmap` instead of a 5.9 MB read.
- **`build-table` -> `shells` is a wash on the big unit and a win on the
  small one** (13.7 -> 22.3 on CORE.c, 5.2 -> 2.0 on nqp.jar). CORE.c's
  19933 shells now walk 19933 rows of a mapped index table, which is the
  first touch of a 1.27 MB entry; nqp.jar's 559 are free.
- **`static-lex-values` collapses**: 49963 rows applied eagerly at load
  became 98 blocks drained after deserialization, 10.15 ms -> 0.20 ms.
  The rest are applied inside the fills of blocks that are entered.
- **The cost came back inside the stages that execute guest code.**
  CORE.c's `deserialize-program` 164.0 -> 271.2 and `sc-stub`/`sc-finish`
  101.6 -> 176.4. Two mechanisms, both expected: the record decode moved
  there (every block a deserializing program enters fills its body on
  the spot), and the mapped slices pay page faults on first touch where
  v1 had already paid one sequential decompress -- the SC blob is 28.2 MB
  read through a mapping instead of a heap array. Net on CORE.c:
  **+23 ms on `load-total`, -62 ms on the load road proper**.
- **nqp.jar is 50 ms faster end to end** (-7.5 %), and that is the unit
  whose load is nearly all of a cold `nqp -e`. Its `open-store` at
  22.8 ms is the FIRST store opened in the process and carries the class
  loading of `UnitStore`, `ZipDirectory` and the kotlinx codec; in the
  rakudo run, where `rakudo.jar` pays that first (19.5 ms), CORE.c's
  `open-store` is 2.1 ms.

### (c) Sizes: 8-10x, and the plan's estimate was wrong

Every entry is STORED, so nothing on disk is compressed any more (v1
deflated `unit.meta` and LZ4'd the SC blob). Bytes:

| artifact | v1 | v2 | v2 breakdown |
|---|---|---|---|
| `blib/CORE.c.setting.jar` | 5892366 | **56067438** | index 1267299, records 5426077, programs 21204318, serialized 28159968, dispatch 0, + 4 nested at 1568 |
| `blib/Perl6/BOOTSTRAP/v6c.jar` | 1299129 | **11269824** | index 404944, records 552603, programs 6117912, serialized 4193837, dispatch 0 |
| stage2 `nqp.jar` | 139990 | **1145720** | index 41102, records 61969, programs 693906, serialized 348215, dispatch 0 |
| `rakudo.jar` | 7537 | **22858** | index 921, records 1286, programs 12919, serialized 7204, dispatch 0 |
| stage0, all 9 jars | 557061 | **4048135** | 7.3x |

**The plan's ruling 1 estimated CORE.c at about 13 MB and was wrong by
4x.** The error was reading v1's own stage lines as "the uncompressed
size": `inflate 54.74 bytes=13104735` is the size of the inflated
`unit.meta`, whose SC member was still LZ4'd inside it; the real
uncompressed SC is the 28159756 bytes the next line reports. That is
where the missing 40-odd MB is.

**Compression of stored entries is Phase C's inbox, by user decision
(2026-09-15).** Compressing an entry costs the mapping, so it is a real
trade (mmap and demand paging against 8x less disk and page cache), not
a flag. The same decision put a second rule on the phase: **no jar of
any type is committed to git until the user says so**, so the nine v2
stage0 jars exist only in the nqp working tree (see the end of this
section).

### (d) The build and the gates

CORE.c compile, over the three full makes of the phase, against Phase
A's makes at about 300 s:

| build | make clean + make | CORE.c |
|---|---|---|
| Task 7, the window build (v1 stage0, v2 output) | 854 s | 283 s |
| Task 8, after stage0 was regenerated as v2 | 861 s | 280 s |
| Task 9, after the v1 reader was deleted | 863 s | 281 s |

Flat, as expected once stage0 was v2: the window build never actually
transcoded (`transcode-v1` lines: 0), so deleting the v1 reader could
not change a clock. **v2 costs the build nothing and the CORE.c compile
is about 6 % better than Phase A's makes**, which is on the right side
of noise but is not claimed as a Phase B result.

Every gate clock of the phase (user rule 2026-09-15: gate timings are
recorded, not just verdicts):

| gate | Task 4 | Task 5 | Task 6 | Task 7 (window) | Task 8 (stage0) | Task 9 (v1 gone) |
|---|---|---|---|---|---|---|
| nqp suite, 155 files, one 6 GB server | 189 s | 188 / 193 s | 192 s | 200 s pre-fix, **191 s** post-fix | 192 s | 197 s |
| `clean buildJvm` | - | - | - | 219 s | 229 s | 255 s |
| `:nqp-runtime:test` | - | - | 45/45 | 46/46 in 11 s | 46/46 in 25 s | 36/36 in 10 s |
| `Configure.pl --gen-nqp` | - | - | - | 3 s | 7 s | 7 s |
| `make clean && make` | - | - | - | 854 s | 861 s | 863 s |
| CORE.c inside it | - | - | - | 283 s | 280 s | 281 s |
| `t/01-sanity` (25 files, 303 tests) | - | - | - | 58 s | 59 s | 60 s |

Phase A closed the suite at 186-200 s, so it is flat across the whole
phase. `:nqp-runtime:test` grows 45 -> 46 with the namespace regression
test and drops to 36 when `UnitFormatTest`'s ten leave with the v1
reader. `jBootstrapFiles` (the stage0 regeneration itself) was 216 s.
Task 6's suite run first read **587 s**; a diagnostic re-run on the same
jars read 192 s, and the 587 s run had spanned a laptop suspend.

**The correctness gate before stage0 was regenerated** was one warm
`t/02-rakudo` sweep: 307 files, **red=21, new-red=0** against the
24-file baseline, and three baseline reds newly green (`15-gh_1202.t`,
`16-begin-time-eval.t`, `native-argument-snapshot.t`). It took 3455 s,
but **that clock is not comparable to the single-server 3200 s series**:
four attempts at the planned one-server `--chunk=307` shape were each
killed by the harness's low-memory guard seconds after the server
banner, with MemAvailable at 25-27 GB and nothing else running, so the
sweep ran as seven sequential servers at `--heap=4 --chunk=50`. The red
list is what the gate needed and the red list is clean; the launcher
refusal is an open question (below).

One red was found and fixed during the phase, and it was the phase's
sharpest lesson. The window build's first `make` died in the CORE.c
compile with `Lexical '$*STACK-ID' not found in guard-type-concreteness`
-- inside a sub that reads no lexical, because the frame was running
**another unit's program**. Site identity had keyed a store-backed
program by `"<unit id>#<program index>"` on the assumption that a unit
id identifies an artifact; Rakudo's Makefile passes `--javaclass=perl6`
to `rakudo.jar`, `v6c.jar`, `v6d.jar`, `v6e.jar` and `rakudo-debug.jar`
alike, so with two of them in one process, program N of whichever loaded
first answered for the other's. The key is now the store's name and the
unit id together (`ProgramUnit.identityNamespace`); see the rulings.

### (e) The rulings that changed the spec's letter

The plan's twelve, written before Task 3 and open to veto until it:

1. **v1 is fully deflated; v2 entries are stored**, sizes recorded not
   reduced. Wrong -> artifacts 8-10x on disk with no owner (it happened,
   and is item (c)).
2. **`unit.serialized` is written raw** and the mapped slice handed to
   the reader. Wrong -> another copy per load, and phase 2 has no mapped
   SC to demand-read.
3. **The call-site table is dead**; v2 drops it and Phase C carries the
   descriptor inline in the slot. Wrong -> Phase C's payload has no way
   to name a descriptor and the schema must change after stage0 is
   frozen.
4. **Every shell is built eagerly** (the reader needs 97 % of them);
   bodies are what go lazy. Wrong -> either a wasted lazy layer or a
   per-lookup cost on the 97 %.
5. **Static lexical values live per block** and are applied on body
   fill, queued until the SC is ready. Wrong -> a block's values are
   applied before its SC exists, or all 49963 are applied at load again.
6. **Roots have no unit identity today**; the compile key
   `"<unit>#<index>"` names the Source for store-backed units; in-memory
   units keep the text key and get no identity. Wrong -> identical
   `EVAL` texts stop sharing a parsed root (memory growth over a server
   sweep), never a wrong answer.
7. **Loop bodies are emitted twice**, so the ordinal is keyed by the
   `DISPATCH` node's wire offset; the encoder's per-block count sizes
   the slot table; `NQP_SITE_CHECK` compares the two. Wrong -> one node
   numbered twice and every later ordinal in the program shifted, so
   Phase C loads the wrong slot.
8. **Helper, rv-decont and indy sites have no identity**; the schema
   tolerates it. Wrong -> a null identity is an error in Phase C instead
   of "no persisted record for this site". Measured: 6 of 7427 sites in
   a cold `rakudo -e`.
9. **In-memory units take the same store road** through a heap image,
   and v1 is transcoded into that image during the window. Wrong -> two
   load roads to maintain, which is what v1 had.
10. **The `mh` identity test becomes a `staticInfo` identity test**
    before `mh` goes lazy (`CallFrame.kt:40,320`,
    `Syscalls.kt:396,409`). Wrong -> spinning a body to compare handles,
    i.e. no laziness where it matters, or a wrong comparison. It
    narrowed one real case: a frame running a `freshcoderef`'d outer no
    longer matches by shared `mh`+`compUnit`; `RakOps` already behaved
    that way.
11. **kotlinx `AbstractEncoder`/`AbstractDecoder` under
    `@OptIn(ExperimentalSerializationApi)`** -- a deliberate deviation
    from the project's "stable API only". Wrong -> a kotlinx upgrade
    breaks the codec.
12. **Gates**: the window build gets the nqp suite + make + `t/01-sanity`
    + one warm `t/02-rakudo` before stage0 is regenerated; the two later
    steps get the first three. Wrong -> a regression baked into stage0,
    which is the expensive one to find.

The rulings made while executing, each with what it costs if it is
wrong:

- **Pre-flight, Task 1**: the stage tasks set `classpath` inside
  `doFirst`, not at configuration time, because `thirdPartySorted()`
  resolves a configuration that must stay lazy. Cost: a
  configuration-cache warning.
- **Pre-flight, Task 2**: the codec's null-mark test declares its
  `@Serializable` class as a nested class of the test class -- the
  kotlinx plugin rejects local serializable classes. Cost: nothing.
- **Pre-flight, Task 6**: `ProgramIdentity.siteKey(ordinal): String` is
  what Java calls; `SiteIdentity` stays a Kotlin value class (which is
  its underlying type in Java, so it has no `getKey()`). Cost: nothing.
- **UTF-8 replacement stays** (`UTF_8.decode` maps malformed input to
  U+FFFD rather than throwing): the codec reads what the writer wrote,
  and the index's (offset, length) tables bound every read, so
  corruption surfaces as a bounds error or a decode exception, both hard
  errors naming the unit. Cost if wrong: a corrupt artifact decodes a
  program text to garbage instead of failing at open, and the engine's
  wire decoder fails on it instead.
- **`_sourceLine` keeps its pre-existing default -1**, not the plan's 0
  (a transcription slip: -1 is guest-visible through
  `getcodelocation`). Cost: nothing.
- **Two `internal` raw accessors on `StaticCodeInfo`**
  (`rawOLexicalIdx`, `rawSetOLexStatic`) exist so that applying static
  lexical values inside a fill does not re-enter `ensureBody`. Cost if
  wrong: a `StackOverflowError` at unit load.
- **A static lexical row naming a gap qbid is dropped**, with an
  `NQP_CODE_WHY`-gated line, not a hard error: `cuid_to_qbid` allocates
  a qbid for every cuid in `%*BLOCK_LEX_VALUES` including blocks never
  compiled into the unit, and v1 dropped those rows silently. Cost:
  nothing (behaviour-preserving); the plan's `dieInternal` would have
  broken the build.
- **`t/nqp/123-unit-artifact.t` subtests 2-3 assert the v2 shape** by
  walking the zip's local-header chain (the originals asserted
  `unit.meta` and scanned the whole jar for `.class`, which now hits the
  string literal `ModuleLoader.class` in a stored program text). Cost:
  nothing; the rewrite is strictly stronger.
- **`applyLexValues` throws `IllegalStateException`** (there is no
  `ThreadContext` inside a fill; `UnitLoader` wraps load-time failures
  in `dieInternal`), so a fill forced mid-execution surfaces at the
  block's first invocation rather than at load. Cost: an error message
  shape.
- **`UnitImageWriter`'s `require()` checks fire at write time for
  in-memory units too** (the invariants v1 enforced at read). Cost: an
  in-memory unit with a corrupt table dies at write instead of later.
- **`isStoreBacked()` tests the store's NAME**, not `cu is ProgramUnit`
  (since Task 5 every unit is a `ProgramUnit`): a file path never starts
  with `<`, and the in-memory makers name theirs `<memory:...>` and
  `<buffer>`. Cost if wrong: an in-memory unit's programs keyed by
  identity are parsed per compile instead of shared by text -- memory
  growth over a long server sweep, never a wrong result.
- **`$*BREC` is read in the encoder through `nqp::getlexdyn`** (null
  when unbound) rather than `nqp::defined($*BREC)`, which throws on an
  unbound dynamic. Cost: nothing.
- **The identity namespace is store name + `!` + unit id**, after the
  `perl6` collision above. The store name is a file path, so a site
  identity is no longer a pure function of the artifact's content across
  machines. Cost if wrong, and this is the one to carry forward: **Phase
  C must not key anything cross-process by the identity string** -- it
  resolves a slot through the site's own unit, program index and
  ordinal.
- **The chunked `t/02-rakudo` sweep counts as the gate** (7 sequential
  servers rather than the planned one), because the gate is the red list
  and the red list is unaffected by chunking; its wall time is recorded
  but not comparable. Cost: nothing -- the clock was never a Phase B
  deliverable.
- **Task 8 produced no diff, so its review is the controller's check of
  the gate logs**; no reviewer was dispatched. Cost: nothing.
- **The `Co-Authored-By: Claude Fable 5.1` trailer names the directing
  session**, not the implementer (implementers run on Opus by the user's
  model policy), and is the phase's convention on every commit. Cost: it
  reads as a model attribution if not stated, which is why it is stated
  here.

### (f) What Phase C inherits

- **The empty `unit.dispatch` table, already addressable.** A program's
  slot count is the encoder's per-block `DISPATCH` count (`$!dispatches`
  on `QAST::BlockRecord` -> `UnitImage.dispatchCounts`), and
  `ProgramUnit.dispatchSlot(programIndex, ordinal)` returns the slot's
  mapped slice or null. Phase C fills slots; it does not change the
  index, so **stage0 does not have to be regenerated again**.
- **The descriptor travels inline in the slot** (ruling 3). The v1
  per-unit call-site table is gone -- `getCallSites()`, `callSites` and
  every index path have left the runtime, and the engine builds its own
  `CallSiteDescriptor` from the wire -- so a payload cannot name a
  descriptor by index.
- **Identity-less sites have no slot.** Two disjoint groups, and the
  `anon=` counter sees only the first: wire sites of an in-memory unit
  (6 of the 7427 in a cold `rakudo -e`, all of them the `-e` script's
  own), and the runtime's own sites (helper, rv-decont, indy), which
  build a `DispatchCallSite` directly and are counted by neither
  `sites=` nor `anon=`. Phase C treats a null identity as "nothing
  persisted", not as an error, and must count the second group itself if
  it needs a process-wide total.
- **The identity string is not a cross-process key.** It embeds this
  process's store path. Resolve a slot through the site's own unit +
  program index + ordinal.
- **`NQP_SITE_CHECK` is the invariant's test.** `site-check` (engine,
  per program), `unit-check` (runtime, per unit) and `unit-check-prog`
  (runtime, per live program) all name the unit by
  `identityNamespace()`, so they join by prefix even where five loaded
  artifacts share the unit id `perl6` -- and the per-program pair joins
  exactly. `tools/build/site-check.raku` does the join and exits 1 on
  any program whose ordinals exceed its slots; the per-program line is
  what makes the check real, since `UnitStore.dispatchSlot` returns null
  past the count and an undercount is otherwise silent. On a cold
  `rakudo-j -e 'say 1'`: 2598 site-check programs numbered, max ordinal
  1060, 26 unit-check lines, and no program numbers more ordinals than
  it stores slots.
- **The five Rakudo units still share `--javaclass=perl6`** (the
  Makefile's `J_NQP_FLAGS_EXTRA`). The namespace makes it harmless, but
  it is a latent trap for any future per-unit keying; distinct names per
  unit would remove it. Left as is: changing the template churns
  Configure for no behaviour gain.
- **Whether stored entries should be compressed** -- the user's decision
  is that this question belongs to Phase C, with item (c)'s sizes as its
  input.
- **The single-server sweep's launcher refusals.** Four
  `--jobs=1 --chunk=307` attempts (heap 6/5/4/3, with and without
  `watched-run`) were killed by the harness's low-memory guard seconds
  after the server banner, at 25-27 GB MemAvailable with nothing else
  running; a 3-file background sweep survives. The milestone close needs
  a whole-`t/` run on one server, so this has to be understood first --
  the guard, or the systemd `MemoryMax` scope the server runs in.

**Deferred minors, collected** (each was ruled harmless where it was
found; the ledger has the context):

- *Docs and comments*: `nqp/build.gradle.kts` still says "boot
  classpath" at :108, :273, :287 and the snapshot `classpath` at :231 is
  uncommented; `NqpDeps.runnerJars`' KDoc says "bootclasspath" and its
  KDoc still claims to mirror the `Makefile.in`/`nqp-j.in` templates;
  `ProgramUnit`'s KDoc says "two" in-memory makers where a third
  (`<nested:...>`) exists on the write side only.
- *Robustness on hand-corrupted artifacts* (unreachable for
  writer-produced ones): `dispatchSlot` never checks
  `firstSlot + slotCount <= dispatchSlotCount`; negative offsets pass
  the `off + len > remaining` guards; `ZipDirectory`'s cen/loc offsets
  are unbounded below; `require(b.outerQbid < nb)` has no lower bound;
  `UnitStore.open(ByteBuffer)` reads from index 0 while `isUnit` honours
  `position()`; heap-opened stores hand out writable slices where the
  mapped path hands out read-only ones. Phase C should revisit these
  when slots become writable.
- *Test coverage*: no test for a zero-block unit, a gap at qbid 0,
  `entry()`, `ZipDirectory`'s non-STORED refusal, or
  `UnitLoader.load(tc, ByteArray)`'s rejection path; the codec tests do
  not cover present-nullable decode, empty collections or a >64 KB
  string (Task 3's records exercise them); `123-unit-artifact.t`'s
  header walk would go vacuous on a deflated entry (a `5 entries`
  assertion would pin it); `isThunk`/`sourceLineDelta`/`sourceSection*`
  getters are untested; `SiteIdentity.site()` and the value class are
  unexercised until Phase C.
- *Small costs*: `ArgsExpectation`'s invoke road pays one volatile read
  per invoke (plan-mandated, expected in the noise);
  `RecordReader.intOr` allocates a `Pair` before the `absent` test;
  `ProgramUnit.gc` could be `@Volatile` (safe today through
  `lexValuesReady` and the unit monitor); `ProgramIdentity.parse`
  accepts a negative index (`foo#-3`); an empty dispatch-slot payload is
  indistinguishable from an empty slot (Phase C decides).
- *Elsewhere in the trees*: the runtime still looks the engine up
  reflectively (`CodeEngine.kt:172`, `GrammarEngine.kt:198`) although
  nothing is on the boot class path any more; the **legacy Perl
  configure path** still names the vendored `nqp/3rdparty/lz4` jar
  (`NQP/Config/NQP.pm:249`, `tools/templates/jvm/Makefile.in`,
  `nqp-j.in`, `nqp-j.windows`, `install-jvm-runner.pl.in`, the legacy
  `nqp/Makefile`) -- dead weight now that `NqpDeps` has dropped lz4, and
  the last lz4 in either tree; `m7-rig.raku --parse-sweep` cannot name
  red files from a chunked sweep log (no `Wstat` lines).

### The stage0 state at the close

**The nine v2 stage0 jars are UNCOMMITTED working-tree changes in the
nqp tree** (user rule 2026-09-15: no jar of any type is committed until
the user says so). The branch pushed to `ab5tract` therefore carries the
**v1** stage0, which the runtime on that same branch can no longer read:
a fresh clone of the pushed branch does not build. **The working tree is
the source of truth until the rule is lifted**, and any destructive
working-tree operation in the nqp tree (a checkout, a clean, a stash, a
hard reset) reverts stage0 to v1 and breaks the build.

---

## Milestone 7, Phase C: the persisted miss (2026-09-15)

### (a) C0, the spike

Instrument: `NQP_DISPATCH_DUMP=<path>` (`DispatchDump.kt`, nqp-runtime), a
shutdown hook that prints every registered site and each installed program
in a normalised text form where every reference is `obj:<handle>:<idx>`,
`code:<handle>:<idx>`, `st:<handle>:<idx>` or `NP(<class>:<type>:<reason>)`.
Analysis: `tools/build/dispatch-dump-diff.raku`. Two cold
`RAKUDO_RAKUAST=1 ./rakudo-j -e ''` runs on rakudo `9bfa3fe86c` / nqp
`b51c1a0db` (the Phase B close):

| dispatcher | sites | programs | persistable | unpersistable | same in run 2 | misses |
|---|---|---|---|---|---|---|
| lang-meth-call | 2145 | 2450 | 2440 | 10 | 2448 | 2872 |
| lang-call | 1910 | 1912 | 1907 | 5 | 1908 | 1909 |
| boot-syscall | 206 | 206 | 206 | 0 | 206 | 206 |
| raku-assign | 35 | 35 | 0 | 35 | 35 | 35 |
| raku-meth-call-qualified | 1 | 1 | 1 | 0 | 1 | 1 |
| total | 4297 | 4604 | 4554 | 50 | 4598 | 5023 |

- **98.9 % of the programs are persistable** (4554 of 4604); the two runs'
  dumps are byte-identical (`diff` empty), so the recorded outcome of the
  trivial program is deterministic and structurally stable.
- **Misses vs programs**: 5023 misses, 4604 installed programs, 4297 sites
  that recorded, 2135 sites parsed but never dispatched, 4 anonymous sites
  with programs (the `-e` unit's own). The 419 misses above the program
  count are polymorphic sites' interpreted-tail hits (a program past the
  folded prefix still counts as a miss in `NqpDispatch.miss`) and
  re-recordings. The persisted share of first-execution work is about 4550
  of the 5023 misses; what remains after Phase C is the 50 unpersistable
  programs, the anonymous sites and the tail hits.
- **Unpersistable causes** (programs carrying each): 40 `CodeRef` with no SC
  (all 35 `raku-assign` outcomes invoke a runtime-made code ref; 5
  `lang-meth-call` on the bootstrap KnowHOW's `find_method`/`new_type`/
  `name`, Kotlin-made methods); 5 `RakuObject4` with no SC (runtime-made
  Raku objects in `lang-call` bind guards); 4 `VMHashInstance` with no SC (an
  nqp class's runtime-published method cache as a `lookup` table); 1
  `VMArrayInstance` owned by an SC object but not in its root set
  (`@!dispatchees`). None is worth a naming scheme in this phase.
- **Per artifact** (sites that recorded / programs): CORE.c 1526/1527, nqp's
  QAST.jar 1111/1113 (the trivial program still runs the QAST compiler), v6c
  BOOTSTRAP 831/1095, NQPCORE 101/115, NQPHLL 100/109, Metamodel 92/104,
  Actions 87/91, Ops 78/78, Grammar 59/59, QRegex 39/40, nqpmo 38/38,
  rakudo.jar 35/35, QASTNode 35/35, ModuleLoader (Perl6) 35/35, Compiler
  33/33, CORE.d 22/22, Optimizer 20/20, NQPP6QRegex 18/18, SysConfig 16/16,
  ModuleLoader (nqp) 10/10, v6d 7/7. A third of the sites are in nqp's
  jars, so Rakudo's training run must write nqp's artifacts too.
- **Five identity strings are shared by two live sites each** (three in v6c,
  one each in NQPCORE and NQPHLL): the same program parsed twice. The
  producer merges programs per identity.
- Every SC referenced resolves by handle through `tc.gc.scs`, including the
  bootstrap's `__6MODEL_CORE__` (`KnowHOWBootstrapper.kt:110`).

The instrument stays: `NQP_DISPATCH_DUMP` is the normalisation verify mode
compares with. Plan and rulings:
`docs/superpowers/plans/2026-09-15-jvm-milestone-7-first-execution-phase-c.md`.

### (b) The rulings, as landed

Phase C closed 2026-09-16 on rakudo `79829d402e` / nqp `f5c5bc8fa`
(schema nqp `e27a795d8`, consumer `5fd74d9b6`, recorder and writer
`3d0b54fa4`, verify by outcome `d3e602917`, gradle training `f5c5bc8fa`;
rakudo's Makefile training `79829d402e`). **Those are the hashes the phase
was measured on; the handoff rebase at the close rewrote them** (rakudo
`79829d402e` -> `5b51570903`, nqp `f5c5bc8fa` -> `e3c800371`, trees
identical) -- the full before/after mapping is in the ledger. The ledger
with every gate clock is
`docs/superpowers/plans/2026-09-15-jvm-milestone-7-first-execution-phase-c.ledger.md`.

The plan's fifteen rulings, written before Task 3 and open to the user's
veto until it, each with what it costs if it is wrong:

1. **No site identity and no descriptor index in the slot** -- the slot's
   address is the identity, and the descriptor travels inline per
   program. Wrong -> a slot cannot be read without a side table, and v2's
   index would have to change after stage0 was frozen.
2. **References are `PRef(handle, index, kind)`** (0 object, 1 code, 2
   STable); the HLL config by name, the syscall by name, a resumption's
   dispatcher by id; anything unresolvable is not persisted, and is
   dropped at restore. Wrong -> a realised program names a different
   object than the one recorded, which replay's own invariant does not
   catch.
3. **kotlinx sealed hierarchies with short `@SerialName`s through
   `UnitCodec`** (plus `Double` as raw long bits). Wrong -> a second
   codec to maintain beside the unit records'.
4. **The training process rewrites the artifacts itself at exit**
   (`UnitDispatchWriter`, tmp file + atomic rename), driven by
   `NQP_DISPATCH_RECORD=all` or a list of store-name prefixes. Wrong ->
   the build needs a second process that can resolve the recorded
   references, which only the training process can do.
5. **Rakudo's training run rewrites nqp's lib jars too** -- a third of a
   cold run's sites are in them -- and slots merge (restored + new).
   Wrong -> nqp's share of the cold miss stays unpersisted, or Rakudo's
   run truncates what nqp's run wrote.
6. **Gradle trains a copy** (`build/jvm/stage2-trained`) and `syncLib`
   takes it; `jBootstrapFiles` keeps the untrained stage2. Wrong ->
   stage0 acquires filled slots and has to be regenerated and committed,
   which the no-jar rule forbids.
7. **Programs merge per slot**, deduplicated by their `DispatchDump`
   text, capped at `MAX_PROGRAMS`. Wrong -> a polymorphic site's slot
   grows without bound across training runs.
8. **Restore happens at the first miss** (in `Dispatch.fallback`, before
   the record), so `misses` keeps its meaning and the claim is on
   `recorded=`, with `restored=`/`restoredSites=`/`dropped=` beside it.
   Wrong -> the phase's headline number measures the wrong thing.
9. **Verify compares applicable persisted programs only** (same shape,
   guards pass); an unseen program is not a mismatch; the gate is zero
   mismatches over the nqp suite and `t/01-sanity`. Wrong -> a gate that
   is red for shapes that never run.
10. **The five `perl6` units need nothing** -- the namespace is store
    name + unit id, which Phase B already made unambiguous. Wrong ->
    Phase B's collision returns, as one unit's slots answering for
    another's.
11. **Compression of records and programs is presented with numbers at
    the close, not built** (clock-negative by construction; the
    runtime-first rule). Wrong -> a smaller artifact that loads slower,
    against the stated priority. The numbers are item (e).
12. **Bounds hardening lands with the writer** (the absolute slot against
    `dispatchSlotCount`, negative offsets, per-program windows checked at
    open). Wrong -> the first writable entry in the format is also the
    first unchecked one.
13. **Runtime-made sites are counted** -- `DispatchBootstrap.created`
    feeds a new `sitesAll=`. Wrong -> the phase cannot say what share of
    the process's sites a slot can reach.
14. **The deferred rakudo rebase is Task 2**, gated by `make` +
    `t/01-sanity`, before any Phase C build. Wrong -> Phase C's numbers
    are measured on a tree that is about to be rewritten.
15. **The whole-`t/` close run goes through `watched-run` as a plain
    background job with a 6 GB heap**; a second kill by the low-memory
    guard means not gathered, and the user decides. Wrong -> the close
    burns hours on a run the harness will kill anyway.

The seven made while executing:

16. **HLL guards persist as (name, compiler-side)** and realise through a
    non-creating `GlobalContext.findHLLConfig`; a null result is
    `Unpersistable`. Why: a type's `hllOwner` comes from whichever of the
    two config maps was current at deserialize, and `Guard.OfHll`
    compares by identity, so the name alone does not name the object.
    Cost if wrong: a dead or dropped HLL-guarded program -- the site
    records as before -- never a wrong answer.
17. **Verify compares by evaluated outcome after text**: the same outcome
    kind, the same callee object by identity / the same syscall name /
    the same value, the same evaluated argument capture on the recorded
    call's own arguments, the same resumption dispatchers and init
    captures, equal `bindControl`; resuming programs stay text-only.
    Counted `byOutcome`; the gate is `mismatched=0`. Why: nqp's
    `lang-meth-call` records a type-guarded form before a class publishes
    its method cache and a cache-lookup form after, and verify mode, by
    not installing, makes the site re-record after the cache exists -- so
    the *form* differs while the target is the same. Cost if wrong: a
    program whose outcome coincides on the training call but whose guards
    are too weak passes verify -- which is the invariant replay already
    rests on.
18. **`NQP_DISPATCH_VERIFY_LOG=<path>` routes every verify line to a
    file**, pid-prefixed and flushed per line; stderr otherwise. Why:
    `t/01-sanity/55-use-trace.t` compares a child process's whole stderr,
    and TAP swallows per-run `MISMATCH` blocks. Cost if wrong: none
    (diagnostics routing) -- but without it the verify gate reads 24/25.
19. **`NQP_DISPATCH_PERSIST_TRACE=1` names each dropped program's
    reason** (`realise` gains an `onDrop` callback carrying the
    `Unpersistable` message). Cost if wrong: none; without it the erosion
    in ruling 20 has no cause.
20. **A slot rewrite carries restored plus new, minus what did not
    resolve in the training process.** Measured: training Rakudo after
    nqp loses about 1.3 % of nqp's slot programs (restored 1677 -> 1656,
    recorded 87 -> 108). Accepted once ruling 19 gave the cause (item
    (c)). Cost if wrong: a few nqp-side sites record once more under
    Rakudo.
21. **Training is reproduced by any clean build only up to the run's own
    nondeterminism** -- NQPCORE wrote 103/114/9
    slots/programs/unpersistable in one clean `buildJvm` and 102/112/8 in
    another, about 1 % of its slots -- so the plan's "deterministically"
    is relaxed to that, and the verify gate is the correctness net. Cost
    if wrong: a cache keyed on jar bytes (the gradle build cache) misses;
    no behavioural cost.
22. **The default-mode nqp suite runs on the post-`make` lib jars** as
    part of Task 8, because Task 7's suite ran on the gradle-trained jars
    before `make` retrained them. Cost if wrong: an untested lib-jar
    state ships.

### (c) The numbers

Rig row `c` against Phase B's `b`, both `--warm=proxy`, best of five cold
runs, stock runners, `NQP_UNIT_LOAD_STATS` and `NQP_DISPATCH_STATS` on:

| lever | rakudo / nqp hash | cold rakudo-e | cold nqp-e | misses | hits | warm t/01-sanity |
|---|---|---|---|---|---|---|
| b (Phase B close) | 107eca63a3 / 318558c2d | 2.461 s | 1.160 s | 5667 | 100711 | 50 s |
| **c (Phase C close)** | 79829d402e / f5c5bc8fa | **2.272 s** | 1.203 s | 4931 | **35512** | 63 s |

The five rakudo walls were 2.27 2.34 2.38 2.31 2.29 and the five nqp
walls 1.29 1.23 1.20 1.22 1.24. **The number that moved is `hits`:
100711 -> 35512, -65 %.** That is the mechanism working: a restored site
installs its programs and replays, instead of running the dispatcher's
guest code to record, and the dispatcher's own dispatch hits are what
vanish. `misses` falls only 5667 -> 4931, exactly as ruling 8 predicted
-- a restored site's first miss is still a miss, because restore happens
*at* it.

The Phase C counters from the same two runs (the rig's programs are
`say 1` and `say(1)`):

| counter | cold rakudo-e | cold nqp-e |
|---|---|---|
| `sites=` (wire sites parsed) | 7463 | 3012 |
| `anon=` (of those, no identity) | 6 | 4 |
| `sitesAll=` (ruling 13: every site the process made) | 7569 | 3059 |
| `restored=` | 4470 | 1644 |
| `restoredSites=` | 4188 | 1634 |
| `dropped=` | 37 | 30 |
| `recorded=` | 849 | 257 |

What is left, from the same runs' `misses` histogram:

| dispatcher | cold rakudo-e | cold nqp-e |
|---|---|---|
| lang-meth-call | 2747 | 1329 |
| lang-call | 1950 | 448 |
| boot-syscall | 197 | 52 |
| raku-assign | 35 | - |
| raku-coercion | 1 | - |
| raku-meth-call-qualified | 1 | - |

**The headline claim is on the trivial program, which is what the build
trains.** On `-e ''`, one run each with stats on (Task 6, reproduced by
Task 7's post-`make` check at `restored=4475 recorded=195`):

| figure | untrained (Task 4 smoke) | trained (Task 6 / Task 7) |
|---|---|---|
| rakudo `recorded=` | 4723 | **193 / 195** |
| rakudo `hits=` | 80298 | **13292** |
| rakudo `restored=` / `restoredSites=` | 0 / 0 | 4477 / 4195 |
| rakudo `dropped=` | 0 | 37 |
| rakudo `byKind[syscall]` | 38151 | 2179 |
| nqp `recorded=` | 1766 | **87** |

That is **-96 % on `recorded`**, against C0's prediction of "5023 -> under
500". The rig's `recorded=849` is higher than 195 because the rig's
program is `say 1`, not `''`: its extra sites were never trained, and the
`-e` unit is in-memory, so its own sites have no identity and no slot
(ruling 8, and Phase B's `anon=`). A cold `say 1` on an untrained build
was not gathered, so the rig row claims no `recorded` delta of its own.

Wall time on one pair of single `-e ''` runs on the same build: 1.943 s
with restore on against 2.483 s with it off (the verify run). That is
single-sample and not a benchmark. The rig row is the measurement, and it
reads -7.7 % on cold rakudo-e and +3.7 % on cold nqp-e, both inside the
series' own spread.

**Drops have one cause.** Under `NQP_DISPATCH_PERSIST_TRACE=1` all 37
rakudo drops and all 30 nqp drops print `no SC <handle>`, over five
handles that exist in no jar: the program's guard or outcome names an
object owned by a serialization context created during the run itself
(the process's own SC, the BOOTSTRAP/EXPORTHOW metaobjects). By unit:
v6c 18, CORE.c 10, NQPCORE 6, NQPHLL 2, QRegex 1; 20 of the v6c ones are
one contiguous block of sibling callsites in a single frame
(`v6c.jar!perl6#4703#20..40`). **0.8 % of installed programs** is the
floor for this workload, and those sites record as before.

**Verify, per gate** (ruling 17's classification; `mismatched=0`
everywhere, and zero `MISMATCH` blocks in the logs):

| gate | processes | matched | byOutcome | mismatched | unseen |
|---|---|---|---|---|---|
| cold nqp `-e ''` | 1 | 1658 | 8 | 0 | 62 |
| cold rakudo `-e ''` | 1 | 4475 | 4 | 0 | 127 |
| `t/01-sanity` (Task 6) | 2 | 117490 | 327 | 0 | 73893 |
| `t/01-sanity` (Task 8) | 2 | 117441 | 327 | 0 | 73941 |
| nqp suite, 155 files (Task 8) | 11 | 271378 | 1309 | 0 | 116617 |

Every mismatch the first pass reported (8 nqp cold, 4 rakudo cold, 313
warm) reclassified to `byOutcome` under ruling 17: they were
differently-shaped programs with the same target, not wrong ones.

### (d) The gates, with their clocks

User rule 2026-09-15: a gate is reported with its wall time, never as a
bare verdict.

| gate | Task 2 (rebase) | Task 7 (build hooks) | Task 7 (validation) | Task 8 (modes) |
|---|---|---|---|---|
| `make clean && make` | 869 s | 883 s | 880 s | - |
| CORE.c parse inside it | 220 s | 221 s | 224 s | - |
| stage sum inside it | - | 282 s | 284 s | - |
| `t/01-sanity`, default | 62 s (25/25) | 55 s (25/25) | - | - |
| clean `buildJvm` | - | 218 s | - | - |
| nqp suite, 155 files, default | - | 196 s (155/155) | - | 206 s (155/155, post-`make` lib jars, ruling 22) |
| nqp suite, verify | - | - | - | 204 s (155/155) |
| nqp suite, `off` | - | - | - | 201 s (155/155) |
| `t/01-sanity`, verify | - | - | - | 51 s (25/25) |
| `t/01-sanity`, `off` | - | - | - | 49 s (25/25) |
| `Configure.pl --gen-nqp` | - | - | 5 s | - |
| second `make` (the no-op check) | - | - | no-op | - |

`off` reproduces the default reference exactly (196 s and 56 s at the
time those were taken), so switching consumption off costs nothing
measurable; verify costs about 8 s on the suite and 2 s on sanity.
Task 6's by-hand runs add `t/01-sanity` 25/25 in 40 s default, 42 s
default after the rulings, and 43 s under verify. **The whole-`t/` run is
Task 10's**, at the milestone close, not this phase's.

One build-graph fact the validation pinned down: **removing the training
stamp does not give an incremental build.** A `make` after `rm` of it is
a full 880 s build, because `Configure.pl` re-expands
`gen/jvm/main-version.nqp` and invalidates everything. That is
pre-existing and not Phase C's, but it is what a "retrain only" attempt
costs today.

### (e) Sizes, and the compression question

The rewrite is slot-in-place: `unit.index` is the same size before and
after in every jar (only its crc changes), so the whole cost is the
`unit.dispatch` blob.

| jar | `unit.dispatch` | jar before | jar after | growth |
|---|---:|---:|---:|---:|
| `blib/CORE.c.setting.jar` | 284 060 | 56 077 905 | 56 362 465 | +0.51 % |
| `nqp/.../QAST.jar` | 489 289 | 750 084 | 1 239 373 | **+65 %** |
| `blib/Perl6/BOOTSTRAP/v6c.jar` | 386 486 | 11 348 915 | 11 735 401 | +3.4 % |
| `blib/Raku/Actions.jar` | not measured | 955 667 | 998 281 | +4.5 % |
| `nqp/.../NQPHLL.jar` | not measured | 572 756 | 627 174 | +9.5 % |
| `nqp/.../nqpmo.jar` | not measured | 211 969 | 263 205 | +24 % |
| `rakudo.jar` | not measured | 22 858 | 37 335 | +63 % |

Cost per persisted program: CORE.c 284 060 / 1487 = ~191 B, QAST
489 289 / 1113 = ~440 B, v6c 386 486 / 1105 = ~350 B. QAST's +65 % is a
small jar with an outsized number of hot sites (1111 slots), not a loose
encoding.

**The compression question, for the user to decide** (ruling 11: the
numbers are presented, nothing was built). CORE.c's jar is 56 MB with
every entry stored: `unit.index` 1.27 MB, `unit.records` ~5.4 MB,
`unit.programs` ~21 MB, `unit.serialized` ~28.2 MB, `unit.dispatch`
0.28 MB. Only records and programs are candidates -- `unit.serialized`
must stay raw and mappable for lazy-loading phase 2, and the index and
the dispatch table are read by offset. Deflating those ~26 MB would take
the jar to roughly half, and would cost an inflate of ~26 MB at open:
**20-80 ms on every cold start**, against an `open-store` stage that
costs 2.07 ms today. By construction that is clock-negative and against
the runtime-first rule, which is why it was not built. Whether disk
matters more here than 20-80 ms per cold process is the user's call.

### (f) Open items and deferred minors

**The phase's own open items:**

- **The warm proxy clock reads 63 s against row `b`'s 50 s**, while the
  same directory under `t/harness5 --evalserver` read 55/51/49 s across
  Tasks 7-8, against Phase B's 58-60 s. Single samples on both sides, not
  re-run (user rule: a benchmark is not re-taken). Nothing in the phase
  predicts a warm regression -- the restored programs are the programs
  the site would have recorded -- so this is an open question for the
  milestone close, and the whole-`t/` run is where it shows or does not.
- **Training is not bit-reproducible** (ruling 21): about 1 % of slots
  vary run to run, from execution-order variation in the training run. A
  two-dump diff of two gradle trainings was deferred.
- **The ~1.3 % erosion** (ruling 20): training Rakudo after nqp lets a
  Raku-flavoured program win an nqp site's slot. The cause is known (`no
  SC`) and it is accepted.
- **`Configure.pl` invalidates the whole build** (item (d)), so there is
  no cheap "retrain only" path.
- **`evalserver-sweep.raku` silently accepts a non-existent explicit
  target** -- a typo in a sweep's directory reads as a clean run.
- **`blib/.dispatch-trained` and `blib/.dispatch-train.log`** are in
  neither the `make` cleanups nor `.gitignore`.

**Deferred minors, collected** (each was ruled harmless where it was
found; the SDD ledger has the context):

- *Schema and codec (Task 3)*: no kitchen-sink round-trip test over every
  P-type; `PLiteral.i` wants a comment on Long normalisation; an unused
  binding at `DispatchSlotCodec.kt:183`; `!!` after `ref()` in
  `DispatchDump.kt:60,69`; non-`Unpersistable` throwables escape
  `persist`/`realise` (ruled hard errors); `g.hll?.name` would persist a
  non-null config with a null name as a null-HLL guard (unreachable
  today).
- *Consumer (Task 4)*: an unrecognised `NQP_DISPATCH_PERSIST` value means
  on; racing first misses can install duplicates (a plain `restored`
  field -- harmless, wastes cap slots, double-counts); `restored=` and
  `restoredSites=` also count in verify mode; the counters are
  process-wide and are not cleared by `resetAll`, so a figure must name
  its population; verify's `recorded` parameter shadows the counter; the
  verify test's same-descriptor instance short-circuits
  `Captures.sameShape`, and its case (a) does not assert silence;
  `verifySay` prefixes only the first physical line of a `MISMATCH`
  block; the drop trace goes to stderr, not to the verify log;
  `sameOutcome` ignores `resumeLevels`/`bindFailureProgram` (vacuous for
  non-resuming programs); no test pins that the `NQP_DISPATCH_RECORD`
  hook is installed -- a whole-file rewrite that dropped `recordAtExit`
  compiled clean.
- *Writer (Task 5)*: `patch()` does not check MAGIC/VERSION; an empty
  named slot writes off/0 silently; the `.tmp` name is fixed (two
  concurrent trainings on one artifact would race -- none exist in the
  build) and is left behind on a failed move; `selected()` NPEs if
  `recordAtExit()` is called without the env var; programs dropped by the
  `MAX_PROGRAMS` cap are not counted on the marker line; the test's
  surviving slot stays at offset 0, so a moved unnamed slot is untested;
  no test for an absent nested prefix or an empty `newSlots`.
- *Build (Task 7)*: the `touch -r` window is open for a source edited
  during the build (documented in the recipe); neither training marker
  asserts a quantity floor; a greedy `sed` range in the log grep; the tee
  objects are configuration-cache-hostile; `engineJarFile` is an input by
  classpath snapshot only; the marker file records absolute paths.

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
