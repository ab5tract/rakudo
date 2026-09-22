# Task 4 report — Knob 1, `NQP_CODE_MAX_COMPILE=2069`

**Status: DONE.** Verdict **KEEP** (build side only).

Base: rakudo `f72f4be91e` (worktree `jesp-direct-lazy-records`), nqp tree
unmodified. No source file was changed; this task is measurement only.

---

## Step 1 — the threshold, and the two cheap checks

Task 3 reported `min-too-large-size=2070`. The knob's predicate is
`programSize <= MAX_COMPILE_SIZE` (`nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java:119-123`,
verified by reading it), i.e. **inclusive**, so setting the knob to 2070
would still admit the root the number came from. The exclusive threshold
is therefore

    2070 - 1 = 2069

I re-ran `tools/build/truffle-trace-summary.raku` over Task 3's baseline
log to read the blocks the brief demands, not the number alone:

```
--- failures by reason ---
  count=442  mean=54ms    PermanentBailoutException: Too deep inlining, probably caused by recursive inlining.
  count=2    mean=3474ms  BailoutException: Code installation failed: code is too large

min-too-large-size=2070
  too-large roots: 2 (2 sized, 0 unsized)
  by size: IMPL-FOLD-CONSTANT[2070], IMPL-OPTIMIZE-EXPRESSION[4030]
  unclassified failure reasons (not matched as a size bailout):
    count=442 ... PermanentBailoutException: Too deep inlining, probably caused by recursive inlining.
```

- **Plausible against its neighbour?** Yes. 2070 and 4030 are the same
  order of magnitude — a factor of 1.9 apart, not orders. There is no
  spuriously tiny root dragging the minimum down, so the threshold does
  not destroy the measurement by refusing nearly everything.
- **Anything unclassified that is really about size?** No. The single
  unclassified reason is `Too deep inlining, probably caused by recursive
  inlining` — an inlining-depth bailout, not a code-size bailout. It is
  correctly excluded. Nothing suggests a third size spelling exists in
  this tree, so 2070 is not reading high.

## Step 2 — the probe

`NqpCheck` with `NQP_CODE_MAX_COMPILE=2069` on the module path from the
brief printed the required positive marker:

```
# Truffle runtime: Oracle GraalVM
ok - add
ok - fib
ok - warm add
ok - wire fib
nqp-code check passed
```

The static initializer's `Integer.parseInt` accepted the value, so the
eight-minute compile could not die on a parse.

## Step 3 — one compile

Run exactly as the brief specifies, through `watched-run.raku`, with
`--output` to `$CLAUDE_JOB_DIR/tmp/m6-corec-maxcompile.jar`. `blib` was
not touched. Exit 0, `verdict=ok`, `elapsed=419s`.

Artifacts: `/home/longwalker/.claude/jobs/804818e2/tmp/m6-corec-maxcompile.{log,markers,jar}`

## Step 4 — the four quantities

| quantity | baseline (Task 3) | knob=2069 | delta |
|---|---|---|---|
| **wall clock** | 434 s | **419 s** | **-15 s (-3.5 %)** |
| **`total-compiler-ms`** | 2 143 944 | **1 898 458** | **-245 486 (-11.5 %)** |
| **`done`** | 5 658 | **5 671** | **+13 (+0.2 %)** |
| **`failed`** | 444 | **408** | **-36 (-8.1 %)** |

Supporting numbers:

| | baseline | knob=2069 |
|---|---|---|
| `nqp-root-ms` | 1 937 603 | 1 699 179 (-12.3 %) |
| Stage parse | 333.841 | **318.561** (-15.3 s) |
| Stage optimize | 36.584 | 36.047 |
| Stage qast | 34.266 | 33.958 |
| Stage unit | 27.539 | 28.999 |
| events / deopt / inval. / reprof | 10759 / 3249 / 1267 / 143 | 10561 / 3106 / 1271 / 107 |
| `unparsed` | 0 | 0 |

(`done` and `failed` corrected in fix round 2 to the engine's own
`Success` / `Permanent Bailouts` counters, which the raw `opt done` /
`opt failed` line counts match exactly; the summarizer reports 5 656/5 670
and 444/407. The deltas are unchanged in sign and near-unchanged in size.
`inval.` likewise: raw counts are 1 268 → 1 273.)

(Stage parse/optimize/qast/unit numbers are recovered from the stray
timing lines in each log; `TraceCompilation` output interleaves into the
`Stage X :` line itself, in both runs identically, so the numbers are
comparable.)

### Did the two "too large" failures vanish? Yes.

```
min-too-large-size=none
--- failures by reason ---
  count=407  mean=51ms  PermanentBailoutException: Too deep inlining, probably caused by recursive inlining.
```

The `code is too large` reason is gone from the run entirely. The
threshold was right, and it was not off by one — had it been 2070,
`IMPL-FOLD-CONSTANT[2070]` would still have been admitted and would still
have burned its ~3.5 s failing to install.

### The knob redistributed compile requests; it did not remove them

*(This section rewritten in fix round 1; see the fix-round appendix.)*

**Start with the cleanest number: `done` + `failed` is essentially flat,
6 102 → 6 079 (-23, -0.4 %).** (Raw `opt done` / `opt failed` line counts;
corrected in fix round 2 — the summarizer reports 5 656/5 670 and 444/407,
but the engine's own statistics block gives `Success` 5 658/5 671 and
`Permanent Bailouts` 444/408, which the raw line counts match exactly.
Throughout this report the engine-verified figures are used: **done
5 658 → 5 671 (+13)**, **failed 444 → 408 (-36)**.) The knob refused 184
compilations outright and the total number of compilation *attempts*
barely moved. Whatever else is true, the knob redistributed compile
requests rather than removing them.

The gate itself is airtight. Direct count of `opt done` lines by root
size, parsed off the trace line independently of the summarizer:

| | baseline | knob=2069 |
|---|---|---|
| successful compiles of roots **>2069** | **178** (+6 OSR = **184**) | **0** |
| successful compiles of roots ≤2069 | 5 474 | 5 671 |
| distinct roots ≤2069 compiled at least once | 1 965 | 1 977 |
| summed `Inlined Y` over all `done` | 2 279 | 2 468 |
| …of which contributed by roots >2069 | **47** (against 4 423 `N`) | 0 |
| …of which contributed by roots ≤2069 | **2 232** | **2 468** |

(Counts corrected in fix round 2. -184 + 197 = +13, reconciling with the
engine's `Success` delta exactly. The ≤2069 compile counts in the earlier
version, 5 175 → 5 373, came from a parse that silently dropped ~300 lines
whose root label did not end in `[size]`; the figures above parse the
whole population.)

**Convention note on "distinct roots".** Keyed on the `name[size]` label
with `<OSR@…>` collapsed I get 1 965 → 1 977 (**+12**); keyed on the
trace's own `id=` call-target identity I get 2 206 → 2 221 (**+15**); the
reviewer's parse gives 1 759 → 1 771 (**+12**). The absolute number is
convention-dependent and I do not claim one; every convention agrees the
increase in *distinct* roots is 12-15, which is the load-bearing figure.

**Label correction:** the "178" figure counts only lines whose root name
ends in `[size]`; it therefore *excludes* 6 OSR compiles, all of
`encode_block[4626]<OSR@…>`, worth 1 964 ms. The 184 and the 308 797 ms
below **include** them: 306 833 ms (178 non-OSR) + 1 964 ms (6 OSR) =
308 797 ms exactly.

The same holds on the failure side — baseline had **41** failures on roots
>2069 (**2** too-large plus **39** recursive-inlining), and the knob run
has none; the new run's unclassified size list tops out at 2042, where the
baseline's ran to 17 545. *(Corrected in fix round 2: the earlier text said
"39 = 2 + 37", contradicting this report's own "39 → 0" for the
recursive-inlining split.)* The failure delta reconciles exactly:
**-41 suppressed + 5 growth in the ≤2069 cluster = -36**, matching
444 → 408.

### The retry storm — the single most important fact about this run

*(Added in fix round 2. This corrects a false statement: I wrote that
nothing in the trace measures queue behaviour. The engine's own statistics
block does, and it says something large.)*

| statistics block field | baseline | knob=2069 |
|---|---|---|
| `Compilations` | **6 358** | **1 462 534** |
| `RetryableBailoutException: Compilable not ready for compilation.` | **144** | **1 456 361** |
| `Success` | 5 658 | 5 671 |
| `Permanent Bailouts` | 444 | 408 |

(Knob run: log line 433549. Baseline: log line 469277. Both read
directly.)

**The knob does not refuse 184 compilations. It converts them into
roughly 1.46 million refused submissions** — a factor of ~10 100 over the
baseline's 144. `prepareForCompilation` answering `false` does not retire
the root; the compilation is re-submitted, refused, re-submitted, for the
life of the run. Three consequences:

**(a) It argues against Reading A far more strongly than anything else
here.** Capacity is not *freed*, it is *churned*. A refused root does not
leave the system; it comes back immediately and keeps coming back. Any
story in which the large roots "stop occupying the queue" is
incompatible with 1.46 million submissions from that same population.

**(b) It is an adoption caveat for Task 11, not a footnote.** The measured
-11.5 % compiler work and -3.5 % wall are achieved *despite* 1.46 million
wasted submissions. That is remarkable, and it is also fragile: the
overhead is workload-shaped — it scales with how long the run lives and
how often those roots stay hot — and there is no reason to assume it
behaves the same on BOOTSTRAP, on a different setting, or on a longer
run. A configuration whose win survives that much waste could equally
lose to it under a different shape.

**(c) The knob run's `Compilations` and `Compilation Accuracy` statistics
are meaningless for cross-configuration comparison.** `Compilations`
counts submissions, not compilations attempted in any useful sense, and
under this knob it is ~230x the baseline for reasons that have nothing to
do with compiler work done. A later task comparing those two fields
across configurations would be comparing nothing. Use `Success`,
`Permanent Bailouts`, and the summarizer's `total-compiler-ms` instead.

**Implication for a proper fix, not implemented here.** A size refusal
ought to mark the root *permanently* non-compilable — one refusal, then
never submitted again — rather than answering `false` on every
submission. That is a change to `NqpRootNode`/the runtime's compilation
policy and therefore **milestone 7's**, not this milestone's. It would
also make the knob's measured win a floor rather than a coincidence.

**Why did `done` rise by 13 when 184 compiles were refused?** Two
readings fit, and the *`TraceCompilation` event stream* cannot
distinguish them — it contains **zero `opt queued` lines**, recording
completion, not enqueue. The statistics block above, which I initially
overlooked, is what breaks the tie.

*Reading A — freed capacity (the knob's own comment).* A capacity-bound
compiler queue drains further once the large roots stop occupying it, so
roots that never reached the front now get compiled. This is what the
`NqpRootNode` comment predicts ("frees the compiler for the hot roots
queued behind it").

*Reading B — inlining redistribution.* Callees that were previously
inlined **into** the 178 suppressed large roots are no longer reached
that way, so they keep accumulating their own interpreter call counts and
eventually compile as roots in their own right.

**The evidence favours B, but not for the reason I first gave.**
*(Evidence restated in fix round 2 — my `Inlined Y` argument was
misattributed.)*

- **The retry storm is the strongest evidence.** 1.46 million refused
  submissions from the gated population mean capacity is churned, not
  released. Reading A's premise — that the large roots stop occupying the
  compiler — is directly contradicted by the engine's own counters.
- **The extra compiles are repeats, not new roots.** The +197 extra
  small-root compiles come with an increase in *distinct* roots of only
  12-15 (see the convention note above). A capacity-bound queue draining
  further should surface new roots roughly in proportion; it does not.
  The per-root deltas are recompilation churn (`PERFORM-BEGIN[966]` +7,
  `IMPL-APPLY-SINK-TO-OPERANDS[894]` +7).
- **Withdrawn: the `Inlined Y` total as redistribution evidence.** I
  cited the rise 2 279 → 2 468 (+189) as callees redistributing out of
  the suppressed roots. The split does not support that. The 184
  suppressed compiles contributed only **47** inlined callees in total
  (against 4 423 *refused* inlinings, `N`); small-root inlining rose
  **2 232 → 2 468, i.e. +236**. So the movement is inlining *growth
  inside small roots*, not callees escaping the suppressed ones — and a
  donor population of 47 could not account for 197 extra compiles in any
  case. The `+189` net figure is simply +236 growth minus the 47 that
  went away with the gated roots. It is consistent with Reading B's
  *spirit* (small roots doing more work on their own) but it is not
  evidence of redistribution, and I should not have presented it as such.

Reading A is not refuted in principle — both effects could operate — but
it is asserted by the knob's comment, and the statistics block argues
against it.

The compiler-time arithmetic is consistent either way: baseline spent
**308 797 ms** on the 184 successful large-root compiles, plus ~6.9 s on
the two too-large failures. Removing ~316 s of compiler work and
observing a net fall of 245 s means roughly 70 s of it was re-spent on
the extra small-root compiles.

### The wall clock — what carries the verdict, and what does not

*(This section rewritten in fix round 1.)*

**What carries the verdict is `total-compiler-ms` at -11.5 % and
`nqp-root-ms` at -12.3 %.** Both are wall-clock-independent, both are
counted directly off ~10 500 trace events, and both are far outside any
plausible noise band. Behind them stands the deterministic 178→0 (184→0
with OSR): a gate predicate answering `false`, not a timing.

**Stage parse is an observation, not corroboration.** The 15 s gain does
sit in Stage parse (333.841 → 318.561), but parse is 77 % of the wall and
is where essentially all compilation happens, so *any* wall-clock change
would have landed there a priori. Citing it as independent evidence is
near-tautological, and I withdraw that claim. (Correction to the original
text: the other stages are *not* all flat to within a second — `Stage
unit` rose 27.539 → 28.999, **+1.46 s**. Optimize -0.54 s and qast
-0.31 s are flat.)

**The 3.5 % wall-clock gain is unproven at n = 1.** Forward-only gives no
variance estimate for this workload, and none is available elsewhere:
Task 1 and Task 3 are different configurations, not repeats. 419 s vs
434 s is the number the KEEP rests on per Step 4's rule, but it is a
single sample and should be treated as such by every later task.

This is still **not** the "large fall in compiler work at a flat wall
clock" case the brief warned about: compiler work fell 11.5 % and the
wall clock moved 3.5 % in the same direction — a real but heavily damped
transfer. With ~2.1 Ms of compiler work spread over 16 cores against a
434 s wall, removing an eighth of that work buys about a twenty-ninth of
the wall. Task 7's thread-count knob is therefore **not** demoted — there
is contention — but its ceiling looks low.

### The deep-inlining cluster did not shrink — milestone 7's lever is 442 / 447

The `failed` count fell 444 → **408** (**-36**), but **none of that is a
fix**. Split by size: among roots at or below 2069 the recursive-inlining
cluster *grew*, **403 → 408**; the entire reduction is the above-2069
population — **39** recursive-inlining bailouts plus the 2 too-large —
which was **suppressed, not repaired**. Drop the knob and the 39 return.

Milestone 7's lever estimate must therefore be stated as **442 latent
deep-inlining bailouts on the baseline, 447 going forward** (408 still
occurring + 39 suppressed by the knob), **not 408**. An estimate built on
the observed 408 understates the lever by about 9 %.

### Observation for later work: deoptimisation churn

This run reports **deopt = 3 106** and **inval. = 1 273** (raw line counts;
the summarizer says 1 271. Baseline: deopt 3 249, inval. 1 268). Three thousand
deoptimisations during a single CORE.c compile is a large number, and the
same signal shows in the per-root counts: `PERFORM-BEGIN[2085]` compiling
26 times is recompilation driven by repeated invalidation, not by 26
distinct roots. Nothing in this milestone acts on it; recording it so
milestone 7 has it. Not investigated here.

## Verdict

**KEEP**, on the wall clock: **419 s vs 434 s, -15 s (-3.5 %)**, per the
brief's rule. Later tasks in the sweep carry `NQP_CODE_MAX_COMPILE=2069`.

**Build side only.** A root that is never compiled never speeds up at
runtime either, and runtime performance outranks compile time
(ruling: reframing block, and memory `runtime-perf-over-compile-time`).
Nothing here argues for the knob at Rakudo run time; Task 11 decides that
separately.

## Concerns

1. **One sample per configuration.** *(Rewritten in fix round 2 — the
   previous version still rested on the Stage-parse argument this report
   had already withdrawn two sections earlier.)* 15 s on 434 s is 3.5 %,
   and forward-only (correctly) forbids a confirmation run, so I have no
   variance estimate for this workload and none exists elsewhere. What
   makes me willing to call it a win rather than drift is exactly what
   the verdict rests on and nothing else: `total-compiler-ms` -11.5 % and
   `nqp-root-ms` -12.3 %, both counted off ~10 500 trace events, both
   wall-clock-independent, both far outside any plausible noise band; and
   the 184 → 0 gated-compile count, which is a predicate answering
   `false`, not a timing. The 3.5 % wall figure itself stays unproven at
   n = 1 and later tasks should treat it that way.
2. **The knob is doing something subtler than "suppress work".** It is
   mostly *reallocating* compiler capacity from 178 large roots to 198
   small ones. A later task that reasons about it as a pure subtraction
   will be wrong.
3. **The threshold is not merely unprincipled, it is *sensitive*.**
   *(Sharpened in fix round 1.)* 2069 has no meaning beyond "one below
   the smallest root that failed to install on 2026-09-12" — but worse,
   it sits **directly beneath `PERFORM-BEGIN[2085]`**, the second-largest
   single contributor to the saving at **41.8 s across 26 compiles**.
   Move the threshold to 2100 and that root comes straight back, taking a
   sixth of the compiler-time saving with it. The population the knob
   actually targets is small and lumpy: the 184 suppressed compiles are
   **29 distinct `id=` call targets** (28 distinct `name[size]` labels —
   one of them, `encode_block[4626]`, appears *only* as OSR compilations,
   so the gate blocks OSR entry to large roots too; the reviewer's
   convention counts 30, which I could not reproduce under either of
   mine — the convention, not the population, is what differs). It is
   dominated by `encode_var[6418]` (18 compiles,
   **70.0 s**) and `PERFORM-BEGIN[2085]` (26 compiles, 41.8 s) — i.e. a
   recompilation-churn population sitting just above the threshold, not a
   broad tail. Task 11 must record this sensitivity explicitly: the
   knob's value is a function of where the cut falls relative to a
   handful of churning roots, and an encoder change that shifts wire
   sizes by a few percent can move roots across it.
4. **The recursive-inlining cluster did not shrink** — see the dedicated
   section above. Baseline 442, knob run 408, but the whole difference is
   suppression of >2069 roots, not repair; ≤2069 it *grew* 403 → 408.
   Milestone 7 must size its lever at **442 baseline / 447 forward**, not
   408.
5. **The knob run's `Compilations` / `Compilation Accuracy` statistics are
   unusable across configurations** (1.46 M refused submissions). Any
   later task that tabulates those fields per configuration will produce
   a nonsense column. See the retry-storm section.
6. **A one-line divergence between the summarizer and the engine's own
   counters.** The summarizer reports `done` two lower and (in this run)
   `failed` one lower than the engine's `Success` / `Permanent Bailouts`,
   and `inval.` two lower than the raw line count. The deltas are
   unaffected and nothing here changes; noting it because the summarizer
   is closed to edits and later tasks should prefer the statistics block
   for absolute counts.

---

# Fix round 1 (2026-09-12) — appendix

Verdict unchanged: **KEEP**. No number in the measurement changed; six
characterisations of the evidence did. No re-run (forward-only); every
figure below was recovered from the two logs already on disk.

| # | Finding | What I changed |
|---|---|---|
| 1 | "freed capacity on the queue behind the large roots" was asserted, not established | Mechanism section rewritten around two readings (freed capacity vs inlining redistribution), states the evidence favours redistribution (unique roots +12 against +198 compiles; `Inlined Y` +189), and states plainly that the trace **cannot** distinguish them — I verified there are **0 `opt queued` lines** in either log, so nothing here measures enqueue at all |
| 2 | "the whole wall delta sits in Stage parse" is near-tautological | Demoted from evidence to observation (parse is 77 % of the wall and holds essentially all compilation). Verdict now rests explicitly on `total-compiler-ms` -11.5 %, `nqp-root-ms` -12.3 % and the deterministic 178→0; the 3.5 % wall gain is stated as **unproven at n = 1**, with Tasks 1 and 3 named as different configurations providing no variance estimate |
| 3 | Missing: `done`+`failed` flat | Added as the **opening** of the mechanism argument: 6 100 → 6 077 (-23, -0.4 %) from the summarizer; my independent line count gives 6 102 → 6 079, the same -23 |
| 4 | Deep-inlining cluster did not shrink | New dedicated section: ≤2069 it went **403 → 408**, the whole -37 is the suppressed >2069 population, drop the knob and the 37 return. **Milestone 7's lever stays ~442, not 407.** (Reviewer's independent parse gave 400 → 405; same +5, different no-size handling) |
| 5 | Concern 3 sharpened | 2069 sits directly beneath `PERFORM-BEGIN[2085]` — 26 compiles, **41 841 ms**; a threshold of 2100 returns it. Population shape recorded: 184 compiles are only **29 unique roots**, top two `encode_var[6418]` 18×/69 968 ms and `PERFORM-BEGIN[2085]` 26×/41 841 ms. Flagged as a *sensitivity* Task 11 must record, not mere arbitrariness |
| 6 | Deopt churn observation | Added: deopt = 3 106, inval. = 1 271 in this run; a root compiling 26 times is invalidation-driven recompilation. Named for milestone 7, not investigated |
| 7 | Small corrections | `Stage unit` **rose 1.46 s** (27.539 → 28.999), so "every other stage flat to within a second" was wrong and is withdrawn. The "178" label excludes **6 OSR compiles** of `encode_block[4626]<OSR@…>`; the 308 797 ms figure includes them — verified exactly: 306 833 + 1 964 = 308 797 |

Figures I re-derived independently for this round, from
`m6-corec-{baseline,maxcompile}.log`: unique roots ≤2069 compiled
1 753 → 1 765; summed `Inlined NY` 2 279 → 2 468; `opt done` + `opt failed`
raw lines 6 102 → 6 079; deep-inlining failures ≤2069 403 → 408 and >2069
39 → 0; large-root compiles 184 across 29 unique roots totalling
308 797 ms; `opt queued` lines 0.

**Restated mechanism sentence.** The knob did not remove compilation work
so much as move it: total compile attempts were flat (`done`+`failed`
6 100 → 6 077) while 184 large-root compiles worth 308 797 ms were
refused and ~198 additional small-root compiles appeared — almost all
repeats of roots already being compiled (unique roots +12) with summed
inlining up 189 — which the trace cannot attribute between freed compiler
capacity and callees no longer being inlined into the suppressed roots,
because it records no enqueue events at all.

---

# Fix round 2 (2026-09-12) — appendix

Verdict unchanged: **KEEP**. No re-run. One false statement retracted, one
argument's evidence replaced, one retracted claim removed from where it was
still load-bearing, and six arithmetic corrections.

| # | Finding | What I changed |
|---|---|---|
| 1 | **"nothing in the trace measures queue depth or queue wait at all" was false, and hid the most important fact about the configuration** | New section "The retry storm". The engine statistics block (knob run, log line 433549) reports `Compilations : 1462534` with `RetryableBailoutException: Compilable not ready for compilation.` = **1 456 361**; the baseline (line 469277) reports 6 358 and **144**. The knob does not refuse 184 compiles, it converts them into ~1.46 M refused submissions, ~10 100x the baseline. All three consequences written up: **(a)** it argues against Reading A harder than anything I had — capacity is churned, not freed, a refused root comes straight back; **(b)** it is a Task 11 adoption caveat, not a footnote — the -11.5 %/-3.5 % win is achieved *despite* 1.46 M wasted submissions, which is fragile because that overhead is workload-shaped and may not behave the same on BOOTSTRAP or another setting; **(c)** the knob run's `Compilations` and `Compilation Accuracy` fields are **meaningless for cross-configuration comparison** (~230x baseline for reasons unrelated to compiler work), so a later task tabulating them would be comparing nothing. Also named, not implemented: a size refusal ought to mark the root **permanently non-compilable** instead of answering `false` on every submission — a runtime-policy change, therefore **milestone 7's** |
| 2 | `Inlined Y` argument misattributed | Evidence restated. Totals were right (2 279 → 2 468, +189) but the split is: suppressed roots contributed only **47** inlined callees (against **4 423** `N`) across their 184 compiles, while small-root inlining rose **2 232 → 2 468 = +236**. So the movement is inlining *growth inside small roots*, not callees redistributing out of the suppressed ones, and a donor population of 47 cannot account for ~197 extra compiles. Conclusion (Reading B over Reading A) survives and is now carried by the retry storm plus the distinct-root count, not by `Inlined Y` |
| 3 | Concern 1 still rested on the retracted Stage-parse argument | Rewritten to rest on the same quantities as the verdict: `total-compiler-ms` -11.5 %, `nqp-root-ms` -12.3 %, and the 184→0 predicate outcome; the 3.5 % wall figure is restated as unproven at n = 1 |
| 4a | baseline failures >2069 | **41 = 2 too-large + 39 deep-inline**, not "39 = 2 + 37". Delta now reconciles exactly: -41 suppressed + 5 growth = **-36** |
| 4b | failed delta | **-36** (444 → **408**), not -37 |
| 4c | "407" | reads **408** throughout; milestone 7's lever restated as **442 baseline / 447 forward** |
| 4d | done+failed | **6 102 → 6 079**; headline corrected (was 6 100 → 6 077). `done` **5 658 → 5 671**, `failed` **444 → 408**, from the engine's `Success` / `Permanent Bailouts`, which the raw line counts match exactly |
| 4e | distinct roots ≤2069 | convention stated rather than a single number: `name[size]` 1 965 → 1 977 (+12); `id=` call-target 2 206 → 2 221 (+15); reviewer's parse 1 759 → 1 771 (+12). All agree on +12-15, which is what the argument uses |
| 4f | `inval.` | **1 273** (raw count; summarizer says 1 271). Baseline 1 268 |
| 4g | gated population size | convention stated: **29 distinct `id=` call targets**, **28 distinct `name[size]` labels**, one of which (`encode_block[4626]`) appears *only* as OSR — so the gate blocks OSR entry too. I could not reproduce the reviewer's 30 under either convention and say so rather than adopting a number I cannot derive |

Also corrected: the earlier ≤2069 compile counts (5 175 → 5 373) came from a
parse that dropped ~300 lines whose label did not end in `[size]`. The whole
population gives **5 474 → 5 671 (+197)**, and -184 + 197 = **+13**, matching the
engine's `Success` delta exactly.

New concerns added: the unusable `Compilations`/`Compilation Accuracy` fields
(concern 5), and a small systematic divergence between the summarizer and the
engine's own counters — `done` two low, `failed` one low in this run, `inval.`
two low — noted for later tasks since the summarizer is closed to edits
(concern 6).

Figures re-derived independently for this round: statistics blocks at log lines
433549 (knob) and 469277 (baseline); inlining split 47 Y / 4 423 N above
threshold and 2 232 → 2 468 below; deep-inline failures ≤2069 403 → 408 and
>2069 39 → 0; suppressed population 184 compiles / 29 ids / 28 labels; raw
`opt done` 5 658 → 5 671 and `opt failed` 444 → 408; `opt inval.` 1 268 → 1 273;
`opt deopt` 3 249 → 3 106.

**Restated mechanism sentence (fix round 2).** The knob did not remove
compilation work so much as churn it: total attempts were flat
(`done`+`failed` 6 102 → 6 079) while 184 large-root compiles worth 308 797 ms
were refused — and refused ~1.46 million times over, because
`prepareForCompilation` answering `false` re-submits rather than retires the
root — so compiler capacity was never actually freed, and the ~197 extra
small-root compiles that appeared are overwhelmingly repeats of roots already
compiling (distinct roots up only 12-15) with inlining *growing* inside them
(+236) rather than callees escaping the suppressed roots (which had only 47 to
give).
