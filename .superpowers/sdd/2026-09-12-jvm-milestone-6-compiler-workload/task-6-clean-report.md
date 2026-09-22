# Task 6 (CLEAN) — Knob 3, tier policy measured BY ITSELF

**Status: DONE. Verdict KEEP, decisively.**

This is the milestone's tier-policy verdict: three polyglot options, no
environment knob, against Task 3's clean traced baseline. Per ruling 33 no
comparison is drawn against the combination run; the size knob's marginal value
is a milestone 7 question.

Wall **434 s → 337 s** (**-97 s, -22.4 %**) and `total-compiler-ms`
**2 143 944 → 783 440** (**-1 360 504, -63.5 %**). Both are two orders of
magnitude outside the noise floor.

- rakudo HEAD: **`b01f00ce02`** (worktree `jesp-direct-lazy-records`) — working
  tree carries only the pre-existing untracked logs; no tracked file changed.
- nqp HEAD: **`41c294b02`** (the nested, gitignored nqp.git tree) — clean,
  unmodified. This task is measurement only; no source changed in either tree.
- `java`: Oracle GraalVM 25.2.4 (`25.0.4+7-LTS-jvmci-25.2-b20`), confirmed
  before the run.
- `blib` untouched. `--output` went to
  `/home/longwalker/.claude/jobs/804818e2/tmp/m6-corec-clean.jar`, a filename
  distinct from every earlier run's.
- Artifacts (all distinctly named):
  `/home/longwalker/.claude/jobs/804818e2/tmp/m6-corec-tier-clean.{log,markers}`,
  driver `/home/longwalker/.claude/jobs/804818e2/tmp/run-task6-clean.sh`,
  driver stdout `.../m6-task6-clean-driver.out`.
- FORWARD ONLY: one compile, exit 0, no re-runs.

---

## 1. The configuration, and the knob that is NOT in it

Exactly three polyglot options:

```
-Dpolyglot.engine.Mode=latency
-Dpolyglot.engine.FirstTierCompilationThreshold=1600
-Dpolyglot.engine.LastTierCompilationThreshold=40000
```

plus the two tracing options (`TraceCompilation`, `CompilationStatistics`).

`engine.MultiTier` is omitted: it is already default-`true`, screened out
before the combination run. `LastTierCompilationThreshold` is accepted and
parsed but **structurally inert under `Mode=latency`** — `firstTierOnly` forces
its gate false — and is present here only so this run's option set is the
combination run's minus the environment knob. Task 11 drops it at adoption.

**`NQP_CODE_MAX_COMPILE` was NOT set.** Confirmed three ways: `env | grep -i
nqp_code` returned nothing before the run; the driver script executes an
explicit `unset NQP_CODE_MAX_COMPILE` before exporting anything; and the run's
own data shows the storm is absent (§4). With it unset, `MAX_COMPILE_SIZE` is
`Integer.MAX_VALUE`, `prepareForCompilation` always returns true, nothing is
ever refused, and no retry storm exists. Its absence is the point of this run.

The exact command (from `run-task6-clean.sh`):

```bash
unset NQP_CODE_MAX_COMPILE
JDK_JAVA_OPTIONS='-Dpolyglot.engine.TraceCompilation=true -Dpolyglot.engine.CompilationStatistics=true -Dpolyglot.engine.Mode=latency -Dpolyglot.engine.FirstTierCompilationThreshold=1600 -Dpolyglot.engine.LastTierCompilationThreshold=40000' \
NQP_CODE_CLOSE_AT_EXIT=1 RAKUDO_RAKUAST=1 \
raku tools/build/watched-run.raku \
  --log=$CLAUDE_JOB_DIR/tmp/m6-corec-tier-clean.log \
  --show-file=$CLAUDE_JOB_DIR/tmp/m6-corec-tier-clean.markers \
  --show='Stage' \
  -- perl rakudo-j-build --setting=NULL.c --ll-exception --optimize=3 \
       --target=jar --stagestats \
       --output=$CLAUDE_JOB_DIR/tmp/m6-corec-clean.jar gen/jvm/CORE.c.setting
```

## 2. Real-path acceptance — NOT BLOCKED

The three options are experimental, so the `NqpCheck` probe false-rejects them
(`NqpCheck.java:31` builds a context without `allowExperimentalOptions`, while
`NqpPolyglot.build()` sets it). That is a probe limitation, not a workload
signal, and per the dispatch no BLOCKED is reported on it. Verified on the
engine path the compile actually uses, ~20 s:

```
$ JDK_JAVA_OPTIONS='-Dpolyglot.engine.Mode=latency \
    -Dpolyglot.engine.FirstTierCompilationThreshold=1600 \
    -Dpolyglot.engine.LastTierCompilationThreshold=40000' \
  RAKUDO_RAKUAST=1 ./nqp/nqp-j-gradle -e 'say("engine-ok")'
NOTE: Picked up JDK_JAVA_OPTIONS: ...
engine-ok
```

## 3. IN FORCE — accepted is not in force, so: tier 2 is abolished

`Mode=latency` sets `EngineData.firstTierOnly`, which should abolish tier-2
compilation outright. Counted with the briefed grep, against **this run's own
clean control, Task 3** (not the combination run's Task 4 figure):

| `grep -c` | T3 clean baseline | **T6 clean** |
|---|---|---|
| `opt done .*\|Tier 2\|` | **1372** | **0** |
| `opt done .*\|Tier 1\|` | 4286 | 3334 |

**Zero tier-2 compiles against 1372.** Every one of the top 20 roots by compile
time is `tier 1`, including `IMPL-FOLD-CONSTANT[2070]` and `encode_var[6418]`,
which were tier-2 roots in the baseline. The option is in force.

`FirstTierCompilationThreshold=1600` shows as the residual: with tier 2 gone,
tier-1 successes still fell 4286 → 3334 (**-952**), and the raised first-tier
bar is the only thing in this configuration that can do that.

## 4. The retry count — 44, not millions

Statistics block, the channel ruling 18 established:

| | T3 clean baseline | **T6 clean** |
|---|---|---|
| `Compilations` | 6358 | **3853** |
| `RetryableBailoutException: Compilable not ready for compilation.` | **144** | **44** |
| `Temporary Bailouts` | 255 | 147 |
| `Compilation Accuracy` | 0.800566 | 0.755775 |

**44 retries**, of the same order as the baseline's 144 and lower than it —
fewer compilations submitted, fewer to be caught mid-flight. Nothing resembling
the combination run's storm. `Compilations` and `Compilation Accuracy` are
therefore meaningful for this run, unlike in any run carrying the size knob.

## 5. Result — every stage reported

Three stage times collided with compiler-thread trace lines on the same output
line (the known `--stagestats` artifact Task 3 documented); each survived on the
following line of the log and was read from there — `Stage optimize` 32.017 at
log line 365919, `Stage qast` 25.389 at 382859, `Stage unit` 23.476 at 392103.
Every stage is reported, because "the delta lives in Stage parse" is not
evidence: parse is 75 % of this wall and holds essentially all compilation.

| stage | T3 (s) | **T6 clean (s)** | delta | % |
|---|---|---|---|---|
| `Stage start` | 0.001 | 0.001 | 0.000 | — |
| `Stage parse` | 333.841 | **253.998** | **-79.843** | **-23.9 %** |
| `Stage syntaxcheck` | 0.000 | 0.000 | 0.000 | — |
| `Stage ast` | 0.001 | 0.000 | -0.001 | — |
| `Stage optimize` | 36.584 | **32.017** | **-4.567** | **-12.5 %** |
| `Stage qast` | 34.266 | **25.389** | **-8.877** | **-25.9 %** |
| `Stage unit` | 27.539 | **23.476** | **-4.063** | **-14.8 %** |
| `Stage jar` | 0.000 | 0.000 | 0.000 | — |
| **stage sum** | **432.2** | **334.881** | **-97.3** | **-22.5 %** |

**Every non-zero stage moved in the same direction.** That matters: it is what
distinguishes a real reduction in background compiler pressure from a parse-only
artifact. `optimize`, `qast` and `unit` together account for 17.5 s of the fall,
18 % of it, on stages that are only 22 % of the wall.

| quantity | T3 clean baseline | **T6 clean** | delta | floor |
|---|---|---|---|---|
| wall clock | 434 s | **337 s** | **-97 s (-22.4 %)** | 0.2 % |
| `total-compiler-ms` | 2 143 944 | **783 440** | **-1 360 504 (-63.5 %)** | 0.7 % |
| `nqp-root-ms` | 1 937 603 | **727 228** | **-1 210 375 (-62.5 %)** | — |
| `Success` (stats block) | 5 658 | **3 334** | **-2 324 (-41.1 %)** | 0.7 % |
| `Permanent Bailouts` (stats block) | 444 | **372** | **-72 (-16.2 %)** | 0.9 % |
| `Compilation Utilization` | 5.224919 | 2.501061 | -52.1 % | — |

`unparsed=0`, `reasons-parsed=5077`. `min-too-large-size=2070`, the same two
roots as the baseline (`IMPL-FOLD-CONSTANT[2070]`, `IMPL-OPTIMIZE-EXPRESSION[4030]`) —
identical to T3, which is good evidence the two compiles are the same work.

**The three failure-count channels, kept apart as instructed:**

| channel | T3 | **T6 clean** |
|---|---|---|
| statistics block `Permanent Bailouts` | 444 | **372** |
| summarizer (`[engine] opt failed` anchored) `failed=` | 444 | **371** |
| raw `grep -c PermanentBailoutException` | 448 | **376** |

The raw grep runs high in both runs by the same mechanism — it also catches the
statistics block's own per-reason breakdown line and any `opt failed` line
Truffle wrote into a `Stage` line (one such, at log line 382860). The spread is
the same shape in both, so it moves no conclusion.

## 6. Verdict: **KEEP**, on the wall clock

**-97 s of wall, -22.4 %.** The floor's wall component is 0.2 %, so this is
~112x the floor. `total-compiler-ms` is -63.5 % against a 0.7 % floor, ~91x.

The floor is one replicate pair with zero degrees of freedom and its wall
component is a single one-second difference at the whole-second measurement
quantum — a resolution limit, not a variance estimate. That weakness does not
bite here: nothing about a one-second resolution limit can turn a 97-second fall
into noise, and the effect is corroborated independently by the compiler-side
counters, by every stage moving together, and by a mechanism (`firstTierOnly`)
whose signature — zero tier-2 compiles — is directly observed.

Mechanistically the result is coherent: CORE.c is a run-once workload compiled
under a 337-second process lifetime. Promoting roots to tier 2 buys peak
throughput that the process never lives long enough to collect, and the tier-2
compiles were where the expensive roots were. Abolishing them returns 1.36
million ms of compiler-thread work and halves compiler utilization (5.22 → 2.50)
on a machine where those threads were competing with the single interpreter
thread doing `Stage parse`.

**Build-side only.** `Mode=latency` pins every root to first tier for the
process's life and, by a second mechanism riding the same option
(`splitting = Splitting && (Mode != LATENCY)`), disables Truffle splitting.
Both are right for a run-once compile and wrong for a long-lived Rakudo process.
No runtime adoption is suggested here.

## 7. Concerns

1. `LastTierCompilationThreshold=40000` contributed nothing measurable and is
   inert under latency; it is in this run only for option-set parity and should
   not be read as part of the win (Task 11 already drops it).
2. `Mode=latency` also disables splitting, a second mechanism not named in the
   knob — the -22.4 % is the pair, and this run cannot separate them.
3. One compile per configuration, so the floor remains an order-of-magnitude
   guide, not a confidence interval; the effect's size is what carries it.
4. Measured on CORE.c only — the tier-policy case rests on the process being
   short-lived, so BOOTSTRAP or a longer-lived build stage could differ in
   magnitude (though not, on this mechanism, in sign).
5. Three stage times were recovered from the following log line rather than read
   in place, per the Task 3 artifact; the same loss occurs identically in the
   baseline, so the comparison is unaffected.

---

# Fix round 1 — four corrections. No number and no verdict moves.

Verdict stands: **KEEP**, wall 434 s → 337 s (-22.4 %). No re-run; every
correction below is read out of the log the original run already produced.

The review's independent reconciliation is recorded and accepted: summing the
trace's own time fields gives 783 461 ms against my `total-compiler-ms` of
783 440, and the 21 ms gap is exactly the one `Stage unit`-prefixed `opt failed`
line (`<anon>[27]`, 21 ms, log line 382860) that the summarizer's `[engine] opt `
anchor drops. The baseline reconciles the same way, so the comparison is
unaffected. My use of Task 3's own 1372 tier-2 count rather than the combination
run's 1394 was ruled correct: pairing across configurations would have imported
the size knob's effect on submission counts into the control.

## Fix 1 — concern 2 is STRUCK. The splitting confound does not exist.

I wrote that `Mode=latency` also disables Truffle splitting and that this run
could not separate the two mechanisms. **It can, and my own log settles it.**
Verified myself in both statistics blocks:

| | line | `Splits` |
|---|---|---|
| T6 clean (this run, splitting **disabled** by latency) | 398325 | **0** |
| T3 clean baseline (splitting **enabled**, default) | 475496 | **0** |

**Splitting produced zero splits on this workload even when it was enabled.**
Disabling something that was doing nothing cannot contribute to a 97-second
fall. Ruling 32 closed the same concern on the combination run for exactly this
reason, and I should have applied it here rather than re-raising it.

**Attribution, stated plainly: the -22.4 % wall and the -63.5 % compiler time
are tier policy.** Concern 2 is withdrawn, not softened. Carrying an unresolved
confound into Task 11 would have understated an adopted result on a doubt the
evidence does not support.

## Fix 2 — why the retry count fell 144 → 44

I reported the drop as proof the knob was absent and left it unaccounted for.
The mechanism, which belongs with the number:

`RetryableBailoutException: Compilable not ready for compilation.` fires when a
submission races an invalidation — the target is no longer in a compilable state
by the time a compiler thread picks it up. **Tier-2 promotion submissions are
its classic source**, because a promotion re-submits a target that is already
installed and running and therefore already exposed to invalidation.

Two independent causes push it down here, and together they over-explain the
69 % fall: total submissions fell 39 % (`Compilations` 6358 → 3853), and tier-2
promotions fell to **zero** (§3). A rate that tracked submissions alone would
predict ~87; the observed 44 is lower, which is what removing the promotion
population on top of the volume reduction predicts.

So the number is a **fourth** proof the knob was absent, alongside the empty
`env`, the explicit `unset`, and the absent storm — not an anomaly, and nothing
about it is unexamined.

## Fix 3 — the reviewer's root-multiset check, and why I am not drawing it

**First, a correction to the instruction itself: this report has no prediction
section.** Ruling 33 directed the clean run to be measured against Task 3 alone,
so I wrote no prediction about the size knob to strengthen. Nothing was cut; it
was never there.

The reviewer supplied a cross-run mechanism check: diffing per-compile root
multisets, 149 compiles occur in this run and not in the combination run, of
which **131 have root size >= 2069** — equal to the Success delta of 131, and
exactly the population the size knob refused; `encode_var[6418]` is compiled 13
times here and 0 times there, taking 13 of the top-20 slots by compile time; and
the 139 126 ms rise over 131 compiles is ~1062 ms each, coherent for roots of
that size. The reviewer also notes honestly that the earlier "roughly 184"
estimate overshot — 131 restored, same order and on the low side, because some
refused roots never re-reach the raised first-tier threshold.

**I record this as reviewer-supplied and I do not adopt it into this report's
findings, because it is the comparison ruling 33 forbids.** The check is a
decomposition of what the size knob suppressed, measured against a run in which
that knob is broken — precisely the "measure the knob in its broken form"
comparison the user ruled out, and precisely the run whose `Compilations` and
`Compilation Accuracy` ruling 18 declared meaningless for cross-configuration
use. The mechanism is plausible and the arithmetic is internally consistent; my
objection is jurisdictional, not technical.

It is therefore **filed for milestone 7**, where the refusal becomes permanent
and the comparison becomes answerable. **No marginal value is drawn here, and
this run's verdict rests on Task 3 alone.** If the user intends ruling 33
relaxed, that is a user decision and this paragraph is the place to reverse.

## Fix 4 — two phrasing corrections

**(a) The collided stage times are flushed ~10k lines later, not on the
following line.** My §5 wording was imprecise. `--stagestats` prints the label,
the stage then runs while compiler threads write trace lines, and the value is
flushed only when the stage ends — a few lines before the *next* `Stage` marker.
Values and line numbers in §5 were right; the description was not:

| stage | label line | value line | lines between | value |
|---|---|---|---|---|
| `Stage optimize` | 355977 | 365919 | 9 942 | 32.017 |
| `Stage qast` | 365920 | 382859 | 16 939 | 25.389 |
| `Stage unit` | 382860 | 392103 | 9 243 | 23.476 |

**(b) The exact channel decomposition**, replacing my loose prose. All five
counts verified by me in this run's log:

- **372** `opt failed` trace lines — **equal to** the statistics block's
  `Permanent Bailouts` (372). The two agree exactly.
- of those 372, **370** name `PermanentBailoutException`; the other 2 are the
  `code is too large` installation bailouts.
- 370 + **6** statistics-block repetitions of the string = **376**, the raw
  `grep -c PermanentBailoutException`.
- 372 - **1** `Stage`-prefixed line (the `Stage unit` collision at 382860, which
  the summarizer's `[engine] opt ` anchor cannot see) = **371**, the summarizer's
  `failed=`.

Every channel is now accounted for to the unit, and the 21 ms reconciliation gap
above is the same single line.
