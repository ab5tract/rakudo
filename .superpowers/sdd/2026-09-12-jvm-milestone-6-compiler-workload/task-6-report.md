# Task 6 report — Knob 3, tier policy (the CONFOUNDED combination run)

> **Ruling 28 landed while this compile was in flight.** Task 4's
> `NQP_CODE_MAX_COMPILE=2069` is no longer carried forward, and a clean Task 6
> without it is dispatched separately. This run **carries** it, so per ruling 28
> it is the milestone's record of *tier policy ON TOP OF the size knob* and is
> **not** the milestone's tier-policy verdict. Its correct baseline is Task 4,
> which carries the same knob. Read §6 for what it does and does not decide —
> and §5a, which tests ruling 28's own premise against this run's data and finds
> it runs the other way.

**Status: DONE.** Verdict **KEEP** for the combination, decisively: wall
**419 s → 329 s**
(**-90 s, -21.5 %**) against Task 4's incumbent, and `total-compiler-ms`
**1 898 458 → 644 314** (**-66.1 %**). Both are two orders of magnitude outside
the milestone's noise floor.

The configuration is **three** options, not four: SCREEN A screened
`engine.MultiTier=true` out as a default before any compile was spent.

- rakudo HEAD at start: **`04ed5e38da`** (worktree `jesp-direct-lazy-records`)
- nqp HEAD: **`41c294b02`** (the nested, gitignored nqp.git tree) — unmodified
- Commit created: rakudo **`5aed763460`** (ledger only; the report directory is
  gitignored). No nqp commit — nqp tree clean at `41c294b02`.
  No source file changed in either tree; this task is measurement only.
- `java`: Oracle GraalVM 25.2.4 (`25.0.4+7-LTS-jvmci-25.2-b20`), confirmed
  before the run.
- `blib` untouched; `--output` went to
  `/home/longwalker/.claude/jobs/804818e2/tmp/m6-corec.jar`.
- Artifacts: `/home/longwalker/.claude/jobs/804818e2/tmp/m6-corec-tier.{log,markers}`,
  driver script `/home/longwalker/.claude/jobs/804818e2/tmp/run-task6.sh`.

---

## 1. SCREEN A — the default check (~2 minutes, no compile spent)

Read out of the exact jar this run loads,
`nqp/build/jvm/share/truffle/truffle-runtime-25.2.4.jar`, in **both** places a
default is written down: the `OptionKey` constructions in
`OptimizedRuntimeOptions.<clinit>` (the authority) and the generated
`OptimizedRuntimeOptionsOptionDescriptors` help text (the prose).

| option | default | bytecode evidence | changing it? |
|---|---|---|---|
| `engine.Mode` | **`default`** (`EngineModeEnum.DEFAULT`) | `getstatic EngineModeEnum.DEFAULT` → `putstatic Mode` | **YES** → `latency` |
| `engine.MultiTier` | **`true`** | `iconst_1` → `putstatic MultiTier` | **NO — screened out, omitted** |
| `engine.FirstTierCompilationThreshold` | **`400`** | `sipush 400` → `putstatic FirstTierCompilationThreshold` | **YES** → `1600` (4x) |
| `engine.LastTierCompilationThreshold` | **`10000`** | `sipush 10000` → `putstatic LastTierCompilationThreshold` | **YES** → `40000` (4x) |

The descriptor prose agrees on all four: *"(default: 400)"*, *"(default:
10000)"*, *"Whether to use multiple Truffle compilation tiers by default.
(default: true)"*, and for Mode *"Available modes are 'latency' and
'throughput'. The default value balances between the two"* — i.e. the default is
a third value, neither of the two the option advertises. The engine says so
itself when handed a bad one: `Mode can be: 'default', 'latency' or
'throughput'.`

**`engine.MultiTier=true` was therefore dropped from the command line**, for
exactly the reason Task 5's ruling dropped `PartialBlockCompilation` from this
brief: writing out a value the option already holds sets nothing, and the habit
is what cost Task 5 a 433-second compile. It is also inert by a second route —
`EngineData.<init>` computes `multiTier = !compileImmediately && MultiTier`, and
`compileImmediately` is false here, so the field is `true` either way.

The defaults the brief's Step 1 asked for (`400`, `10000`) are **observed
defaults**, not chosen values, so the "use 1000 and 10000 and record that these
are chosen" fallback did not apply.

**The 4x arithmetic:** 400x4 = 1600, 10000x4 = 40000.

## 2. SCREEN B — structural: does the mechanism exist on our path? **YES**

Task 5's option lived only in `OptimizedBlockNode`, which a Bytecode DSL
language never instantiates. Tier policy lives somewhere else entirely: all
three options are read in `com.oracle.truffle.runtime.EngineData.<init>` into
plain fields, and those fields are read by
`com.oracle.truffle.runtime.OptimizedCallTarget` — the one call-target class
every guest root gets on the optimizing runtime, Bytecode DSL or AST, with no
node-class precondition at all. Verified by disassembly:

- `EngineData`: `firstTierOnly = (Mode == LATENCY)`;
  `computeCallAndLoopThresholdInInterpreter()` returns
  `FirstTierCompilationThreshold` when `multiTier`;
  `computeCallAndLoopThresholdInFirstTier()` returns
  `LastTierCompilationThreshold`.
- `OptimizedCallTarget` reads `EngineData.callThresholdInInterpreter`,
  `callAndLoopThresholdInInterpreter`, `callThresholdInFirstTier`,
  `callAndLoopThresholdInFirstTier` and `firstTierOnly` (two sites each).

`NqpRootNode` (`nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java:47,53`)
is a `@GenerateBytecode` `BytecodeRootNode extends RootNode`, so it gets an
`OptimizedCallTarget` like anything else. Screen B passes.

**A side effect Screen B also turned up, and it matters for adoption:**
`Mode=latency` does more than tier policy. `EngineData.<init>` computes
`splitting = Splitting && (Mode != LATENCY)`, so **latency also switches
Truffle splitting off**. That is a second mechanism riding in the same option,
and it is not in the knob's name.

## 3. The probe false-rejected, exactly as the dispatch predicted

The briefed `NqpCheck` probe never printed `nqp-code check passed`:

```
Exception in thread "main" java.lang.IllegalArgumentException: Option
'engine.FirstTierCompilationThreshold' is experimental and must be enabled with
allowExperimentalOptions(boolean) in Context.Builder or Engine.Builder.
        ...
        at org.raku.nqp.truffle.NqpCheck.main(NqpCheck.java:31)
```

`NqpCheck.java:31` builds `Context.newBuilder(NqpLanguage.ID).build()` with no
`allowExperimentalOptions`. `NqpPolyglot.build()`
(`nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpPolyglot.kt:49-51`) —
the context the compiler actually runs in — calls `.allowExperimentalOptions(true)`.
So this is the probe's limitation, not the workload's. **NOT BLOCKED.**

## 4. Real-path verification: accepted, and IN FORCE

**Accepted** (~20 s), on the engine path the compile uses:

```
$ JDK_JAVA_OPTIONS='-Dpolyglot.engine.Mode=latency \
    -Dpolyglot.engine.FirstTierCompilationThreshold=1600 \
    -Dpolyglot.engine.LastTierCompilationThreshold=40000' \
  RAKUDO_RAKUAST=1 ./nqp/nqp-j-gradle -e 'say("engine-ok")'
engine-ok
```

**Accepted is not in force**, so three separate pieces of evidence:

1. **Negative controls prove the values are parsed, not ignored.**
   `Mode=bogus` → `IllegalArgumentException: Mode can be: 'default', 'latency'
   or 'throughput'.`; `FirstTierCompilationThreshold=notanint` →
   `IllegalArgumentException: For input string: "notanint"`. An option that were
   being dropped on the floor could not reject a value.
2. **`Mode=latency` is observable in the run's own trace, and is decisive.**
   `firstTierOnly` should abolish tier-2 compilation outright:

   | | Task 4 | Task 6 |
   |---|---|---|
   | `opt done ... Tier 2` | **1394** | **0** |
   | `opt done ... Tier 1` | 4277 | 3203 |

   The single `Tier 2` string left in the Task 6 log is the statistics block's
   own histogram label `Compilation Tier 2 :`, not a compilation. Every one of
   the top 20 roots by compile time is `tier 1`.
3. **`FirstTierCompilationThreshold=1600` is visible as the residual.** With
   tier 2 abolished, tier-1 successes still fell 4277 → 3203 (**-1074**); the
   raised first-tier bar is the only thing in this configuration that can do
   that.

**`LastTierCompilationThreshold=40000` is accepted and parsed but structurally
inert here**, and I want that on the record rather than counted as a win: under
`firstTierOnly` the call target never promotes, so
`callAndLoopThresholdInFirstTier` is never the gate. Its one surviving use is
`traversingFirstTierBonus = TraversingQueueFirstTierBonus * LastTier / FirstTier`
— and because both thresholds were multiplied by the same 4, that ratio is
*identical to the default*. This third option contributed nothing measurable.

## 5. Result

Command actually run (from `run-task6.sh`; `engine.MultiTier` absent per §1):

```bash
NQP_CODE_MAX_COMPILE=2069 \
JDK_JAVA_OPTIONS='-Dpolyglot.engine.TraceCompilation=true -Dpolyglot.engine.CompilationStatistics=true -Dpolyglot.engine.Mode=latency -Dpolyglot.engine.FirstTierCompilationThreshold=1600 -Dpolyglot.engine.LastTierCompilationThreshold=40000' \
NQP_CODE_CLOSE_AT_EXIT=1 RAKUDO_RAKUAST=1 \
raku tools/build/watched-run.raku \
  --log=$CLAUDE_JOB_DIR/tmp/m6-corec-tier.log \
  --show-file=$CLAUDE_JOB_DIR/tmp/m6-corec-tier.markers \
  --show='Stage' \
  -- perl rakudo-j-build --setting=NULL.c --ll-exception --optimize=3 \
       --target=jar --stagestats \
       --output=$CLAUDE_JOB_DIR/tmp/m6-corec.jar gen/jvm/CORE.c.setting
```

| quantity | T3 (no knobs) | T4 (incumbent) | **T6 tier policy** | vs T4 | vs T3 | floor |
|---|---|---|---|---|---|---|
| wall clock | 434 s | 419 s | **329 s** | **-90 s (-21.5 %)** | -105 s (-24.2 %) | 0.2 % |
| `total-compiler-ms` | 2 143 944 | 1 898 458 | **644 314** | **-1 254 144 (-66.1 %)** | -69.9 % | 0.7 % |
| `nqp-root-ms` | 1 937 603 | 1 699 179 | **590 650** | **-1 108 529 (-65.2 %)** | -69.5 % | — |
| `Success` (stats block) | 5 658 | 5 671 | **3 203** | **-2 468 (-43.5 %)** | -43.4 % | 0.7 % |
| `Permanent Bailouts` (stats block) | 444 | 408 | **331** | **-77 (-18.9 %)** | -25.5 % | 0.9 % |

`unparsed=0`. `min-too-large-size=none` — the `NQP_CODE_MAX_COMPILE=2069` gate
this run carries still holds, exactly as in Task 4.

**Judged against the floor.** The floor is one replicate pair with zero degrees
of freedom, and its wall component is a single one-second difference at the
measurement's whole-second quantum, so it is a resolution limit, not a variance
estimate. That caution does not bite here: -90 s is ninety times the floor's
wall resolution and -66 % is a hundred times its `total-compiler-ms` component.
Nothing about the floor's weakness can turn a 21.5 % wall fall into noise.

**The three count channels, kept apart as instructed:**
- statistics block `Permanent Bailouts`: **331**
- summarizer (`opt failed` anchored) `failed=`: **330**
- raw `grep -c PermanentBailoutException`: **336** (it also catches the
  statistics block's own per-reason breakdown line and the `opt failed` reason
  texts)

Never compared across runs, per lesson 1: `Compilations` (2 080 000 here vs
1 462 534 in Task 4) and `Compilation Accuracy` are dominated by
`NQP_CODE_MAX_COMPILE`'s retryable refusals — 2 076 384 `Compilable not ready
for compilation` resubmissions. They measure resubmission pressure, not work.

### 5a. Ruling 28's premise, tested against this run — it runs the other way

Ruling 28 removed the carried knob because tier policy "raises the call counts
at which a target submits for compilation, which directly changes how often a
size-refused root resubmits", so part of a tier-policy result measured on top of
it would really be "the retry storm shrank". The reasoning is sound a priori.
**This run's data says the storm did not shrink — it grew by 43 %:**

| | Task 4 | Task 6 (this run) | delta |
|---|---|---|---|
| `Compilations` (submissions) | 1 462 534 | **2 080 000** | **+42.2 %** |
| `Compilable not ready for compilation` | 1 456 361 | **2 076 384** | **+42.6 %** |
| useful compilations per submission | 1 in 258 | **1 in 649** | 2.5x worse |

*(Lesson 1 forbids comparing `Compilations` across runs **as a measure of
compiler work**, because resubmissions swamp it. Here the resubmission count is
not a proxy for anything — it **is** the quantity ruling 28 is about, so it is
reported directly, and only for that question.)*

Two consequences, and I would rather flag them than have the clean Task 6 find
them the hard way:

1. **The direction of the confound is the opposite of the one assumed.** A
   larger retry storm is overhead added, not removed, so if it biases this run's
   wall clock at all it biases it *against* tier policy. The -90 s is therefore
   a floor on the combination's effect, not an inflated figure.
2. **Higher thresholds mean a root spends longer being ineligible, and a
   size-refused root resubmits for the whole of that longer window.** That is
   the mechanism for the growth, and it predicts the clean Task 6 (no size
   refusals to resubmit) will show a *smaller* `Compilations` figure than this
   one, not a larger one. If it does not, something else is driving
   resubmissions and ruling 28's model needs revisiting.

None of this reopens ruling 28 — removing a confound whose sign you cannot
predict in advance is right regardless of which way it later turns out to point,
and a clean baseline is worth having on its own. It does mean this run's numbers
are conservative rather than flattering.

### Mechanism, decomposed — and it is not the Stage-parse tautology

Lesson 2 says "the delta lives in Stage parse" is not evidence, because parse is
most of the wall. So here is the per-stage split from the markers (cumulative
elapsed; the stage's own printed number is clobbered by trace lines for the
middle stages, so these are marker-to-marker deltas):

| stage | Task 4 | Task 6 | delta |
|---|---|---|---|
| parse | 320 s (318.561 printed) | 246 s (244.734 printed) | **-74 s** |
| optimize+qast | 36 s | 31 s | -5 s |
| qast→unit | 34 s | 25 s | -9 s |
| unit→jar | 29 s | 27 s | -2 s |

Parse holds most of it because parse holds most of the compilation, but **every
stage fell** — this is a whole-run effect, not a parse artifact.

Where the compiler time went, exactly:

- **Tier-2 abolition is the bulk.** Summing the `Time` field of Task 4's
  tier-2 `opt done` lines: **1 019 837 ms over 1394 compilations** — 54 % of its
  entire `total-compiler-ms`. Task 6 spends **zero** there. Second-tier
  recompilation of roots that the build runs a handful of times was, on this
  workload, more than half of all compiler work.
- **The raised first-tier bar is the rest.** 1074 fewer tier-1 successes and 72
  fewer tier-1 failures account for the remaining ~234 000 ms.

**This is the shape Task 4 was not.** Task 4 refused big roots and the compiler
re-spent the freed capacity on the queue behind them (`done` went *up*); tier
policy **reduces compilations** instead — 5671 → 3203 — exactly as the dispatch
predicted it should. Work fell 66 % and the wall followed at 21.5 %, still
damped, but a far better transfer ratio than Task 4's 11.5 %→3.5 %.

### The deep-inlining cluster moved, and it is the only reason

`failures by reason` holds **exactly one** reason, `PermanentBailoutException:
Too deep inlining, probably caused by recursive inlining` — no new reason
appeared, and `min-too-large-size=none`. The cluster the milestone has been
tracking at **442-447** across Tasks 3/4/5 (444 / 407 / 446) is now **330-331**.
It did not get fixed; there are simply 43 % fewer compilations in which to hit
it. The summarizer's `unclassified failure reasons` block holds that same single
reason — expected, since a deep-inlining bailout is correctly not a size bailout
— with sizes spanning 43 to 2042 and three `no-size` entries (host roots without
a wire size).

Milestone 7's lever should be re-stated as **~330 under tier policy**, not ~442.

## 6. Verdict: **KEEP** — for the combination, which is what this run measures

Wall 329 s vs Task 4's 419 s, at 100x the noise floor. What this decides and
what it does not, under ruling 28:

- **It decides the combination.** Tier policy added to
  `NQP_CODE_MAX_COMPILE=2069` is worth -90 s and -66 % compiler work over the
  size knob alone. This is the configuration Task 11 would have shipped under
  the old greedy-sequential design, and it is now the only measurement of it.
  It should not need re-running.
- **It does not decide tier policy.** That is the clean Task 6's job, against
  Task 3's 434 s. My expectation, recorded before that run exists so it can be
  wrong: the clean run will show a *larger* absolute tier-policy gain than the
  -90 s here, because Task 4's knob has already removed 178 of the largest
  compilations that tier policy would otherwise also have removed — the two
  knobs overlap in what they suppress. Against Task 3's 434 s, a clean tier
  policy landing near or below 329 s would confirm that.
- **The mechanism carries over regardless.** Tier-2 abolition (1 019 837 ms,
  54 % of Task 4's compiler work) is not a property of the carried knob; the
  clean run will have its own, larger tier-2 population to abolish.

I recommend Task 11 **drop `LastTierCompilationThreshold=40000`** from any
carried set: §4 shows it is structurally inert under `latency`, and carrying an
inert option forward is how a sweep accumulates cargo. The clean Task 6 should
drop it too rather than reproduce it.

**Build-side adoption only** — the same boundary Task 4 drew, and here it is
much sharper. `Mode=latency` pins every root to tier 1 forever and switches
splitting off. That is right for a compiler process that runs once and exits;
it is the opposite of what Rakudo's *runtime* wants, and runtime performance
outranks compile time by standing user priority. Nothing measured here argues
for this knob anywhere but the build.

## 7. Concerns, for review

1. **The configuration is confounded and cannot be decomposed by design.**
   Three options moved at once. The trace decomposes the *effect* cleanly
   (tier-2 abolition 1 019 837 ms; raised first-tier bar ~234 000 ms), so the
   confounding is answerable from this one run — but if Task 11 wants
   `Mode=latency` alone, that is a separate compile, not an inference.
2. **`Mode=latency` smuggles in splitting=off.** It is not purely tier policy.
   The measurement cannot separate "no tier 2" from "no splitting"; both are
   downstream of the same option, and both plausibly help a run-once workload.
   A reviewer treating this as a pure tier knob will mis-model it.
3. **One sample, as always.** The effect is 100x the floor, so this is a
   formality here — but the floor itself is still n=2 with zero degrees of
   freedom and a whole-second wall quantum.
4. **`Success` falling 43 % is the knob working, not a gate tightening.** No
   root was refused: `min-too-large-size=none`, one failure reason, no new
   reason. The compilations simply never became eligible. A later task reading
   the fall as suppression-by-size will be wrong.
5. **`NQP_CODE_MAX_COMPILE=2069`'s value is now questionable under tier
   policy.** It was tuned on a run whose largest compiles included tier-2 work
   that no longer exists. Its gate still holds (`min-too-large-size=none`), but
   Task 11 should re-derive rather than assume 2069 is still the right cut.
6. **Ruling 28's confound points the other way here (§5a).** The retry storm
   grew 43 % rather than shrinking, so this run understates tier policy rather
   than flattering it. Worth carrying into the clean Task 6's reading.
7. **Deviation from the brief, argued in §1:** the brief's Step 3 command lists
   `engine.MultiTier=true`; I omitted it as a screened-out default. This makes
   the measured configuration three options, not four. It changes nothing in the
   engine (`multiTier` is `true` either way), but the ledger row must read as
   three or the configuration will not reproduce as written.

---

# Fix round 1 — five items, no re-run

All five answered from the logs already on disk. rakudo commit
**`b0ad6ef40c`**. The verdict, the headline numbers and
the table in §5 are unchanged.

## IMPORTANT 1 — the retry-storm mechanism: my explanation was wrong, and inverted

**Withdrawn.** I wrote that higher thresholds keep a root ineligible longer, so
it resubmits for the whole of that longer window. That is backwards on its own
terms: a root that is ineligible longer submits *less*. Pure threshold-gating
predicts roughly 4x **fewer** resubmissions (the bar went 400 → 1600), not the
1.43x more that was measured. My §5a stated a mechanism that its own data
contradicts.

**Replacement, and it is a fit rather than a proof.** `prepareForCompilation`
returning false is a *retryable* bailout: it does not set `compilationFailed`,
so the refused target becomes re-submittable again as soon as no task is
pending for it. Resubmission is therefore **congestion-bound, not
threshold-bound** — the loop's period is how fast the queue turns a refused
task around, and that is set by how much real work is in front of it. This run's
queue carries 66 % less real work, so refused tasks turn around faster. Verified
by me from the two statistics blocks and the two wall clocks:

| | submissions | wall | **resubmissions/s** |
|---|---|---|---|
| Task 4 | 1 456 361 | 419 s | **3 475.8** |
| Task 6 | 2 076 384 | 329 s | **6 311.2** |

The count rose 1.43x; the *rate* rose 1.82x, which is the quantity the
congestion model is about. **This is a fit to the observed rates, not something
the trace proves**: `TraceCompilation` records `done`/`failed`/`inval`/`deopt`/
`reprof`, and records **no enqueue events at all**, so the submission loop's
period is never directly observed. It is the best available explanation of two
numbers, and it should be labelled as such wherever it is reused.

**Prediction deleted.** I attached a falsifiable prediction that the clean Task
6 would show a smaller `Compilations` figure. It cannot test anything: the clean
run drops `NQP_CODE_MAX_COMPILE` entirely, so `prepareForCompilation` is always
true, nothing is ever refused, and there is no storm to count — Task 3, the
clean baseline, recorded **144** submissions. A prediction about the size of a
population that does not exist in the test is not falsifiable. Struck rather
than rephrased.

## Concern 2 CLOSED — the splitting side effect contributed exactly zero

I flagged that `Mode=latency` also switches splitting off (`EngineData`:
`splitting = Splitting && (Mode != LATENCY)`), so the configuration is not
purely tier policy, and passed it to Task 11. My own logs close it. Both
statistics blocks print:

```
    Splits                      : 0
```

Task 4 — splitting *enabled* — split nothing. Splitting produced no work on this
workload, so switching it off removed no work, and the side effect's
contribution to the -90 s is **zero, measured, not estimated**. The bytecode
finding stands and is worth keeping on the record for a workload where splitting
does fire; it is not a caveat on *this* measurement. Concern 2 is closed here
and is **not** carried to Task 11.

## Attribution split — both halves are genuinely tier policy

Decomposed by me from the `Time` fields, using the summarizer's own line
population (lines beginning `[engine]`, see the MINOR item):

| | Task 4 | Task 6 | drop |
|---|---|---|---|
| tier-2 `done` | 1 019 837 ms (1394) | 0 (0) | **1 019 837** |
| tier-2 `failed` | 226 ms (5) | 0 (0) | **226** |
| tier-1 `done` | 857 951 ms (4276) | 626 710 ms (3203) | **231 241** |
| tier-1 `failed` | 20 444 ms (402) | 17 604 ms (330) | **2 840** |
| **total** | **1 898 458** | **644 314** | **1 254 144** |

Both column totals reproduce the summarizer's `total-compiler-ms` **exactly**,
and the four drops sum to **exactly** the 1 254 144 ms fall. The split:

- **`Mode=latency` abolishing tier 2: 1 020 063 ms = 81.3 %**
- **the raised first-tier bar: 234 081 ms = 18.7 %**

Neither half is an artifact of the carried size knob, and both are tier policy,
which strengthens the KEEP rather than qualifying it.

## `LastTierCompilationThreshold` is inert for a CONFIRMED reason

§4 called it "structurally inert" reasoning from `EngineData`. The direct
confirmation is one instruction sequence at the top of
`OptimizedCallTarget.compile(boolean, CompilationTask$SubmissionReason)`:

```
 0: aload_0
 1: getfield  EngineData engine
 4: getfield  EngineData.firstTierOnly:Z
 7: ifne  18          // firstTierOnly -> jump to iconst_0
10: iload_1           // the caller's lastTierCompilation argument
11: ifeq  18
14: iconst_1
18: iconst_0
19: istore_3          // lastTierCompilation := !firstTierOnly && arg
```

`firstTierOnly` forces the last-tier flag to false on **every** entry, whatever
the caller asked for, so a last-tier compilation is never submitted and
`LastTierCompilationThreshold` is never consulted as a gate. Confirmed, not
suspected. It should be dropped from any carried set.

## MINOR — the channel reconciliation, corrected and now exact

My §5 listed 331 / 330 / 336 but misattributed the gaps. The correct
decomposition, re-derived by me line by line:

**336 raw `grep -c PermanentBailoutException`** =
**330** clean `^[engine] opt failed` lines
+ **1** `opt failed` line carrying a watched-run `Stage unit       : ` prefix
(log line 343573)
+ **5** repetitions of the reason inside the statistics block's own per-reason
breakdown (lines 349945, 350999, 352019, 353039, 354061).

So the **331 vs 330** gap is that single Stage-prefixed line: the engine counted
it (`Permanent Bailouts : 331`), and the summarizer's starts-with filter drops
it (`failed=330`). This is exactly the undercount lesson 3 warns about, caught
in the act.

The same filter explains, to the millisecond, why my raw-grep sums exceeded the
summarizer's totals: the dropped lines are Task 6's one `opt failed` at **31 ms**
(raw 644 345 - 31 = 644 314 ✓) and Task 4's one `opt failed` at **28 ms** plus
one `Stage start`-prefixed `opt done` at **59 ms** (raw 1 898 545 - 87 =
1 898 458 ✓). Both channels are now fully reconciled, with no residual.
