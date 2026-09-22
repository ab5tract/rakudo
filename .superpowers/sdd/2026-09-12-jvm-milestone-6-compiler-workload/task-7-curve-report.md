# Task 7 CURVE — `engine.CompilerThreads` at 1, 2 and 4: the low end, and the six-point curve

**Status: DONE, all three compiles.** Wall **297 s / 323 s / 341 s** at 1 / 2 / 4
threads, against 327 s at 3. **Wall is monotone INCREASING from the hard floor
upward across 1 / 2 / 3 / 4, so 3 is NOT a minimum — it is a point on a slope
that keeps falling all the way to 1.** `total-compiler-ms` is strictly monotone
increasing across all six points with no exception. **There is no starvation knee
on wall down to 1.** There *is* a knee on compilation — it sits between 2 and 1
and is plainly visible in target coverage and in the compilation queue — but on
this run-once workload it never reaches the wall clock.

- rakudo HEAD at run time: **`f766603dce`**, worktree `jesp-direct-lazy-records`.
  HEAD moved to **`ab0ecd81d4`** during the batch as the controller committed
  ledger prose concurrently; `git diff f766603dce..ab0ecd81d4 --stat` is
  **one file, the ledger, +194 lines** — no source file changed, so all three
  compiles ran against an identical tree.
- nqp HEAD: **`41c294b029`** (the nested, gitignored nqp.git tree), unchanged
  across the batch.
- `java`: Oracle GraalVM 25.2.4 (`25.0.4+7-LTS-jvmci-25.2-b20`), confirmed before
  the batch.
- `blib` untouched: `find blib -newermt '2026-09-12 16:50'` empty, before and
  after.
- `--output` went to `m6-corec-threads{1,2,4}.jar`, three distinct filenames,
  none colliding with any earlier run.
- FORWARD ONLY: one compile per configuration, `EXIT=0 verdict=ok` on all three,
  no re-runs.
- **`NQP_CODE_MAX_COMPILE` was NOT set.** `env | grep -ci nqp_code` returned `0`
  before and after, and the driver runs an explicit `unset` before exporting.
- Artifacts, all under `/home/longwalker/.claude/jobs/804818e2/tmp/`:
  `m6-corec-threads{1,2,4}.{log,markers,jar}`, driver `run-task7-curve.sh`,
  driver stdout `m6-task7curve-driver.out`, thread samples
  `t7curve-threadsample-{1,2,4}.txt`, helper readers `t7curve-extract.sh`,
  `t7curve-stages.sh`, `t7curve-ids.sh`.
- `tools/build/truffle-trace-summary.raku` was **not edited**.

---

## 1. Acceptance and IN FORCE — directly observed

All three values were **accepted** with no error, no warning and no
experimental-option rejection on the real engine path; the engine reached the end
of a full CORE.c compile in each case. Screens were not redone, per the dispatch.

**The decisive channel is the direct thread count**, sampled from
`/proc/<pid>/task/*/comm` every 12 s — a plain file read, no attach, no
safepoint, so it cannot perturb the wall clock beside it. Linux truncates
`TruffleCompilerThread` to `TruffleCompiler`.

| requested | samples taken | samples at the requested count | any other count |
|---|---|---|---|
| **1** | 24 | **24 / 24** | none |
| **2** | 26 | **26 / 26** | none |
| **4** | 28 | **28 / 28** | none |

Not one sample in 78 deviated. **At 1 thread especially, 1 was observed, every
time** — the `Math.max(1, threads)` floor is the only clamp and the request is
honoured exactly.

Corroborated by the engine's own `Compilation Utilization`, which is structurally
bounded by the pool size and tracks it closely: **0.958300 / 1.603661 /
2.256520** for 1 / 2 / 4. The 1-thread figure sitting just under 1.0 is as tight
a confirmation as this counter can give.

Corroborated again by queue wait, which moves the way a shrinking service
capacity must — average `Time waiting in queue` **11 261 151.57 ns** at 1 thread,
**5 180 716.12** at 2, **843 631.41** at 4, against 732.25 ns at 16. That is a
**15 400x spread** across the curve, and the 1-thread run's 11.3 ms average wait
is the largest recorded anywhere in this milestone.

## 2. RESULT — wall and `Stage parse` first

`elapsed` is watched-run's own figure (`EXIT=0 verdict=ok elapsed=Ns`);
`Stage parse` is the stagestats value read from the log.

| | **1 thread** | **2 threads** | **3 (Task 7)** | **4 threads** |
|---|---|---|---|---|
| **wall clock** | **297 s** | **323 s** | 327 s | **341 s** |
| **`Stage parse`** | **225.941** | **249.839** | 248.832 | **260.621** |

Against the 3-thread control: 1 thread is **-30 s (-9.2 %)**, 2 threads is
**-4 s (-1.2 %)**, 4 threads is **+14 s (+4.3 %)**.

Every stage, per ruling 2 — parse is ~76 % of wall and holds essentially all
compilation, so the rest is reported because it was asked for, not as independent
corroboration:

| stage | **1 thread** | **2 threads** | 3 (Task 7) | **4 threads** |
|---|---|---|---|---|
| `Stage start` | 0.001 | 0.001 | 0.001 | 0.002 |
| `Stage parse` | **225.941** | **249.839** | 248.832 | **260.621** |
| `Stage syntaxcheck` | 0.000 | 0.001 | 0.000 | 0.001 |
| `Stage ast` | 0.000 | 0.000 | 0.000 | 0.000 |
| `Stage optimize` | **23.680** | **24.975** | — | **28.803** |
| `Stage qast` | **21.169** | **22.946** | — | **25.920** |
| `Stage unit` | **24.352** | **23.692** | — | **23.786** |
| `Stage jar` | 0.000 | 0.000 | 0.000 | 0.000 |
| **stage sum** | **295.143** | **321.454** | — | **339.133** |

The stage sums (295.1 / 321.5 / 339.1) sit ~2 s under their walls in all three
runs, the same offset each time, and reproduce the wall ordering exactly. Per
ruling 3 that is a finer-resolution reading of the *same* run — it defeats the
one-second quantisation doubt, not run-to-run variance.

Three stage values per run again collided with interleaved trace lines on the
same output line (the `--stagestats` artifact Task 3 documented); each was read
from its flushed bare-number line a few lines later, the same way Task 7-max did
it. The reader was validated by reproducing the 16-thread run's published values
(262.367 / 31.926 / 25.988 / 24.370) exactly before being used here.

## 3. Counters — from the statistics block unless labelled

| quantity | **1** | **2** | 3 (Task 7) | **4** | 6 | 16 |
|---|---|---|---|---|---|---|
| `total-compiler-ms` (summarizer) | **277 722** | **503 022** | 619 075 | **728 428** | 783 440 | 893 381 |
| `nqp-root-ms` (summarizer) | **247 000** | **452 916** | — | **668 467** | 727 228 | 832 026 |
| `Compilations` | **1 826** | **3 030** | — | **3 602** | 3 853 | 3 902 |
| `Success` | **1 578** | **2 653** | 3 000 | **3 156** | 3 334 | 3 355 |
| `Permanent Bailouts` | **235** | **351** | 366 | **373** | 372 | 372 |
| `Temporary Bailouts` | **12** | **26** | — | **73** | 147 | 175 |
| ↳ `Compilation cancelled` | 9 | 19 | — | 53 | 87 | 101 |
| ↳ `Compilable not ready` | 0 | 1 | — | 8 | 44 | 54 |
| `Invalidated` | **290** | **614** | 754 | **843** | 939 | 954 |
| `Compilation Utilization` | **0.958300** | **1.603661** | 1.996044 | **2.256520** | 2.501061 | 2.730003 |
| `Splits` | **0** | **0** | 0 | **0** | 0 | 0 |
| `Queues` | **2 921** | **5 329** | 4 726 | **4 349** | 4 098 | 3 920 |
| `Dequeues` | **1 105** | **2 323** | — | **804** | 343 | 127 |
| ↳ `Stale compilation task` | **972** | **2 103** | 1 137 | **622** | 190 | 2 |
| `Queue Accuracy` | **0.621705** | **0.564083** | — | **0.815130** | 0.916301 | 0.967602 |
| `Compilation Accuracy` | **0.841183** | **0.797360** | — | **0.765963** | 0.755775 | 0.755510 |
| `Time waiting in queue` avg (ns) | **11 261 151.57** | **5 180 716.12** | 1 900 657 | **843 631.41** | 54 184.82 | 732.25 |
| `Time waiting in queue` max (ns) | **135 359 640** | **45 668 236** | — | **26 450 030** | 2 219 707 | 337 114 |
| **`Remaining Compilation Queue`** | **7** | **0** | 0 | **0** | 0 | 0 |

**`Remaining Compilation Queue` is 7 at 1 thread — the first non-zero value
anywhere in this milestone.** At 2 and 4 threads it is 0, as at 3, 6 and 16. So
at the hard floor, and only there, the queue does *not* fully drain and seven
queued compilations were truncated by process exit. It is a small truncation
(7 of 2 921 enqueues, 0.24 %) and it does not move the wall reading, but it is
the honest signature that one thread is the first configuration where the engine
runs out of runway, and it means the 1-thread counters are a very slight
undercount of what the run intended to do.

Tier-2 compiles: **0** in all three runs (`grep -c 'opt done .*|Tier 2|'`), as at
3, 6 and 16, so `Mode=latency`'s first-tier-only gate carried over intact and
nothing here touches the tier question.

`Splits` is 0 in all three, as in every run of this milestone.

**The three failure-count channels, kept apart per ruling 4:**

| channel | **1** | **2** | **4** | 6 | 16 |
|---|---|---|---|---|---|
| statistics block `Permanent Bailouts` | **235** | **351** | **373** | 372 | 372 |
| summarizer (`[engine] opt failed` anchored) `failed=` | **235** | **351** | **372** | 371 | 371 |
| raw `grep -c PermanentBailoutException` | **240** | **355** | **376** | 376 | 376 |

The familiar spread holds: the raw grep runs 4-5 high because the statistics
block repeats the string in its own per-reason breakdown, and the summarizer runs
0-1 low depending on whether an `opt failed` line happened to collide with a
`Stage` line in that run (it did at 4 threads, not at 1 or 2). None of it moves a
conclusion. Summarizer hygiene was clean in all three: `unparsed=0`,
`reasons-parsed=2879 / 4159 / 4943`.

`min-too-large-size` is **4030** at 1 thread against **2070** at 2, 4, 6 and 16 —
at one thread the `IMPL-FOLD-CONSTANT[2070]` root never got far enough to record
its size bailout, which is coverage loss (§5) showing up in a second place.

## 4. THE SIX-POINT CURVE

All six points on this 16-core box, one sample each, same adopted tier policy
throughout (`Mode=latency`, `FirstTierCompilationThreshold=1600`,
`LastTierCompilationThreshold=40000`), same CORE.c workload.

| threads | wall | `Stage parse` | `total-compiler-ms` | `Success` | stale dequeues |
|---|---|---|---|---|---|
| **1** | **297 s** | **225.941** | **277 722** | **1 578** | **972** |
| **2** | **323 s** | **249.839** | **503 022** | **2 653** | **2 103** |
| 3 | 327 s | 248.832 | 619 075 | 3 000 | 1 137 |
| **4** | **341 s** | **260.621** | **728 428** | **3 156** | **622** |
| 6 (default) | 337 s | 253.998 | 783 440 | 3 334 | 190 |
| 16 | 346 s | 262.367 | 893 381 | 3 355 | 2 |

**On `total-compiler-ms` — the axis ruling instructs us to read the curve on —
277 722 → 503 022 → 619 075 → 728 428 → 783 440 → 893 381 is STRICTLY MONOTONE
INCREASING across all six points, with no exception and no near-tie.** The
smallest step is 6 → 16 at +14.0 %, twenty times the 0.7 % floor. The largest is
1 → 2 at **+81.1 %**: the second thread nearly doubles compiler CPU. This axis is
unambiguous.

**On wall — 297 → 323 → 327 → 341 → 337 → 346.** Monotone increasing across
1 / 2 / 3 / 4, then a **4 s inversion at 6**, then up again at 16. The rises that
matter are far outside the resolution limit: 1 → 2 is **26 s (8.8 %, ~44x the
0.2 % wall floor)** and 1 → 16 is **49 s (16.5 %)**. The 2 → 3 step (4 s) and the
4 → 6 inversion (-4 s) are each about 1.2 %, six wall quanta, and one sample
apiece — neither is worth resting anything on.

**Per-thread slope, which is the shape's real content:**

| interval | wall delta | per thread |
|---|---|---|
| 1 → 2 | +26 s | **+26.0 s** |
| 2 → 3 | +4 s | +4.0 s |
| 3 → 4 | +14 s | +14.0 s |
| 4 → 6 | -4 s | -2.0 s |
| 6 → 16 | +9 s | +0.9 s |

The slope is **steepest at the very bottom and flattens by more than an order of
magnitude toward the top** — 26 s for the second thread, 0.9 s for each of the
last ten. Ruling 42 corrected "~1 s per thread" to a 3.7x flattening across
3 → 16; adding the low end makes it roughly **29x** across the full range. The
cost of threads is concentrated in the first few.

## 5. What the low end does to compilation itself — ruling 44's identity

Counted by the engine's own `id=` call-target identity, per rulings 20 and 44,
never by `name[size]`. The counter was validated by reproducing ruling 44's
16-thread row (3 355 / 1 672 / 1 515 / 2.01) exactly before being used.

| threads | compiles (`opt done`) | **unique targets by `id=`** | unique by label | compiles/target | `opt deopt` | `opt inval.` |
|---|---|---|---|---|---|---|
| **1** | **1 578** | **1 033** | 968 | **1.53** | **2 355** | **290** |
| **2** | **2 653** | **1 552** | 1 415 | **1.71** | **3 196** | **614** |
| 3 | 2 998 | 1 626 | 1 479 | 1.84 | 3 522 | 754 |
| **4** | **3 156** | **1 649** | **1 497** | **1.91** | **3 730** | **843** |
| 6 | 3 334 | 1 672 | 1 515 | 1.99 | 3 767 | 939 |
| 16 | 3 355 | 1 672 | 1 515 | 2.01 | 3 808 | 954 |

**This is where the low end says something ruling 43 could not see from above.**
Ruling 43 established that at the top of the curve the extra compilations are
re-compiles and buy **zero** new targets — coverage saturates at 1 672. That
remains true from 4 upward: 4 threads reaches 1 649, within **23 targets (1.4 %)**
of saturation, and 6 and 16 are identical at 1 672.

**Below 3 it stops being true.** At 2 threads coverage is 1 552 — **120 targets
short, 7.2 %**. At 1 thread it is **1 033 — 639 targets short, 38.2 % of the
compiler's targets never compiled at all.** So at the hard floor the knob is no
longer debouncing redundant recompiles; it is genuinely starving compilation of
more than a third of its coverage.

**And the wall got faster anyway.** That is the finding. On a run-once compile,
38 % of the compiled-code coverage — and 1 777 of the 3 355 compilations — is not
worth what it costs to produce. `compiles/target` falling 2.01 → 1.53 shows the
debounce effect strengthening monotonically all the way down, and the deopt count
falling 3 808 → 2 355 in step confirms ruling 43's churn picture from the other
end: less compiled code means less to invalidate means fewer re-requests.

**So the starvation knee EXISTS and sits between 2 and 1 — but on compilation,
not on wall.** Three independent counters place it there and nowhere else:
coverage falls off a cliff (1 552 → 1 033, against 120 lost over the whole range
above), `Remaining Compilation Queue` goes non-zero for the first and only time,
and the average queue wait reaches 11.3 ms. What does *not* happen at that knee is
any rise in wall time. The compilations being starved are simply not hot enough,
within a 297 s single pass, for their absence to cost more than their production.

**`Queues` is non-monotone across the low end too, and more violently than
above** — 2 921 / 5 329 / 4 726 / 4 349 / 4 098 / 3 920, **peaking at 2 threads**,
with the 1-thread run enqueueing barely half of that peak. Per ruling 7 this
stays a fit to counters, not a mechanism: the trace records no enqueue events.
The fit is that arrivals are shaped by service rate — one thread produces so
little compiled code (1 033 targets) that there is little to invalidate
(`Invalidated` 290, against 954 at 16) and therefore little to re-enqueue. `Queue
Accuracy` bottoming at **0.564083** at 2 threads rather than at 1 is the same
non-monotonicity seen from another angle.

## 6. Reading the shape, and ruling 41

**The shape is MONOTONE INCREASING with the minimum AT THE HARD FLOOR, not a U
and not a plateau.**

- **Not a U.** A U needs wall to rise as threads fall. It never does. 1 is the
  fastest point measured, by 30 s over 3 and 49 s over 16.
- **Not a plateau.** The dispatch's plateau test was "1, 2, 3 and 4 all within a
  few seconds". They are not: the span is **44 s (297 to 341)**, and 1 → 2 alone
  is 26 s, roughly 44x the wall floor. On `total-compiler-ms` the same four
  points span **277 722 to 728 428, a factor of 2.6**. There is nothing flat here.
- **3 was not a minimum.** It was a point on a slope, exactly as the dispatch
  suspected. The slope keeps falling past 3 and past 2 and only stops because it
  runs out of room.

**Where the knee is: there isn't one on wall, down to 1.** The knob's real answer
on this workload is "as few as possible", and `Math.max(1, threads)` is what
stops it. Following ruling 42's caution I state the defensible version: **no dip
at any measured point, the low end strictly better on both axes, and the minimum
at the floor** — the curve cannot exclude something odd at 5, or between 7 and 15,
and with the redirect those will stay untested.

**On mechanism I add nothing and I do not revive ruling 40's causal half.**
Ruling 41 withdrew "contention dominates" because occupancy never exceeded 2.58
of 16 cores. The low end makes that puzzle **sharper, not weaker**: core-equivalent
occupancy (`total-compiler-ms` / wall) across the curve is **0.94 / 1.56 / 1.89 /
2.14 / 2.32 / 2.58 cores**, so the fastest run kept the box about **6 % busy** and
the slowest about **16 %**, and 49 s of wall separates them. Fourteen cores were
idle in every single run. Whatever makes background compilation cost wall time
here, it is not CPU scarcity, and one compiler thread on a 16-core box cannot
plausibly be starving the parse thread of anything. I label this a **fit to
counters** and leave ruling 41's question open exactly as it stands: settling it
needs process-CPU accounting or a box-idle record, and neither was taken here
either.

Ruling 43's debounce fit **survives and gains a boundary**: it describes 3
upward, where coverage is saturated and extra threads buy only re-compiles; below
3 the knob crosses from debouncing into genuine starvation of coverage, and the
crossing is visible between 2 and 1.

## 7. Concerns

1. **1 thread is the fastest build but would be a poor shipping default for
   anything long-lived**: it leaves 38.2 % of call targets never compiled. This
   milestone's workload is a run-once compile; a long-running Rakudo process is
   the opposite case, and nothing here measures it.
2. `Remaining Compilation Queue` is **7** at 1 thread, the only non-zero in the
   milestone: that point's counters are marginally truncated by process exit, and
   it is the one configuration whose queue did not drain.
3. One sample per point, no replicates; the 2 → 3 step (4 s) and the 4 → 6
   inversion (-4 s) are each ~1.2 % and cannot be separated from the wall's
   resolution limit — the shape rests on 1 → 2 and 1 → 16, not on those.
4. The 4 → 6 inversion breaks strict monotonicity on wall; with one sample each I
   cannot say whether it is noise or a genuine shallow dip at 6.
5. Mechanism remains unestablished per ruling 41, and the low end deepens the
   problem: the fastest run left ~15 of 16 cores idle, so no contention account
   yet fits.
6. `Queues` and `Queue Accuracy` are non-monotone and both extremise at 2 rather
   than at an endpoint, so any queue narrative stays a fit to counters.
7. Coverage is counted by `id=` per ruling 44, but `Success` and the statistics
   block's `maxTarget` groupings are still name-keyed and merge ~10 % of targets;
   the §5 table is safe, the §3 table's groupings inherit that known defect.
8. Measured on CORE.c only, on one machine, at one moment, with a concurrent
   ledger-committing session on the box (docs only, but it was not an idle
   machine).
