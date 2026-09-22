# Task 7 MAX — `engine.CompilerThreads` at the high end (16), completing the curve

**Status: DONE.** Wall **337 s → 346 s** (**+9 s, +2.67 %**) and
`total-compiler-ms` **783 440 → 893 381** (**+109 941, +14.0 %**) against the
6-thread control. Wall rose. **The curve is monotone increasing on this box
across 3 / 6 / 16 and its minimum lies at or below 3 threads — contention
dominates, and Task 7's result stands.**

- rakudo HEAD at run time: **`37f3a76be6`** (worktree `jesp-direct-lazy-records`).
- nqp HEAD: **`41c294b029`** (the nested, gitignored nqp.git tree) — clean.
- `java`: Oracle GraalVM 25.2.4 (`25.0.4+7-LTS-jvmci-25.2-b20`), confirmed before
  the run.
- `blib` untouched: `find blib -newermt '2026-09-12 16:00'` is empty; newest file
  under it is 12:29, hours before this task started (16:42).
- `--output` went to `…/tmp/m6-corec-threads16.jar`, a filename distinct from
  every earlier run's.
- FORWARD ONLY: one compile, `EXIT=0 verdict=ok elapsed=346s`, no re-runs.
- **`NQP_CODE_MAX_COMPILE` was NOT set.** `env | grep -i nqp_code` returned
  nothing before the run and the driver executes an explicit
  `unset NQP_CODE_MAX_COMPILE` before exporting anything.
- Artifacts (all under `/home/longwalker/.claude/jobs/804818e2/tmp/`):
  `m6-corec-threads16.{log,markers,jar}`, driver `run-task7-max.sh`, driver
  stdout `m6-task7max-driver.out`, thread samples `t7max-threadsample-sh.txt`,
  over-16 probe `t7max-over16probe.sh` + `t7max-over16threads.txt` +
  `t7max-over16probe.out`. Screen-A disassembly reused from Task 7:
  `t7-screenA/{opts,desc,bcq}.txt`.

---

## 1. SCREEN A — what "maximum" means, and the value chosen

**May an EXPLICIT value exceed the 16 cap? YES.** The cap is inside the
default-resolution branch only. From `javap -p -c` on
`com/oracle/truffle/runtime/BackgroundCompileQueue` (extracted from
`nqp/build/jvm/share/truffle/truffle-runtime-25.2.4.jar`), the pool-construction
control flow in `getExecutorService`:

```
 63: OptimizedCallTarget.getOptionValue(OptimizedRuntimeOptions.CompilerThreads) -> threads (slot 4)
 93: iload 4; ifne 118        ; if (threads == 0) { procs>=4 ? threads=2 : - }   -> goto 163
118: iload 4; ifge 163        ; <-- an EXPLICIT POSITIVE VALUE JUMPS STRAIGHT TO 163
123..158:                     ; only reached when threads < 0 (the -1 default):
                              ;   min(procs/4 + log2(max(log2(procs),1)), 16)
156: bipush 16
158: Math.min                 ; <-- the 16 cap lives HERE, inside the threads<0 branch
163: threads = Math.max(1, threads)
171: newThreadFactory("TruffleCompilerThread", …)
```

`bipush 16 / Math.min` at 156–158 is unreachable for any explicit positive value:
the `ifge 163` at 118 has already branched past it. The only clamp an explicit
value meets is `Math.max(1, threads)` at 163, a floor, not a ceiling. The value
is then passed as both core and maximum pool size of the inner
`TruffleThreadPoolExecutor`.

**Is there a validator? NO.** In `OptimizedRuntimeOptions.<clinit>` the key is
built with the **single-argument** `OptionKey.<init>(Ljava/lang/Object;)V`
(constant-pool `#30`) around `Integer.valueOf(-1)` — not the two-argument
`OptionKey.<init>(Ljava/lang/Object;Lorg/graalvm/options/OptionType;)V` (`#60`)
that neighbouring options such as `CompilationFailureAction` use to attach a
custom `OptionType`. A single-argument `OptionKey` gets the default `OptionType`
for `Integer`, which parses and does not validate a range. The descriptor's
usage syntax `[1, inf)` is documentation, and `inf` is what the bytecode
actually implements upward.

**Stability, as the dispatch asked:** the descriptor builder for
`engine.CompilerThreads` sets `OptionStability.STABLE` (its neighbour
`CompilerThreadStackSize` sets EXPERIMENTAL two entries earlier in the same
method, so the distinction is visible side by side). It is EXPERT category but
**not experimental**.

**Empirical corroboration that an explicit value raises the ceiling.** A short
engine run (~40 s, a hot NQP loop, not a compile) with
`-Dpolyglot.engine.CompilerThreads=24` was accepted with no error and grew the
pool to **8** `TruffleCompilerThread`s, above the default 6 — while the default
run in Task 7 sat at exactly 6. It did not reach 24 because the executor creates
core threads **on demand** (no `prestartAllCoreThreads` appears anywhere in the
class) and the toy workload's burst never demanded more. So the probe proves the
explicit value is honoured and is not clamped down to the default, but a value
above 16 cannot be *shown* to materialise more than 16 threads without a
workload that bursts that hard.

**Chosen value: `CompilerThreads=16`.** Reasoning, stated plainly:

1. **16 is the honest maximum here.** One thread per core is the hardware
   ceiling, and it is also the engine's own ceiling for its default computation
   — the number GraalVM itself declines to exceed when choosing for you.
2. **Above 16 is accepted but would not be a cleaner experiment, it would be a
   dirtier one.** Every thread past 16 is pure oversubscription: it cannot add
   parallelism, only OS scheduler pressure, and it adds per-thread stack
   (640 KB default) and JVMCI working set. The third curve point would then
   confound "more compiler capacity" with "scheduler thrash", and the milestone
   has already spent one task on an option that could not do anything.
3. **16 already delivers the contention test the curve needs.** CORE.c parse is
   effectively single-threaded on the main thread; at 16 compiler threads the
   compiler alone can claim every core, so the main thread, GC and JVMCI must
   contend. If contention is the mechanism behind Task 7, 16 is where it shows.
4. **On-demand growth means a larger request is partly unfalsifiable.** With
   growth driven by burst demand, asking for 32 and observing 19 would tell us
   about the workload, not about the knob.

So: an explicit value above 16 **is** permitted and **is** unvalidated, and I
judge oversubscription not worth the one compile available. 16 is the honest
maximum on this box.

## 2. IN FORCE — directly observed, not inferred

**(a) Direct thread count, the decisive channel.** Sampled from
`/proc/<pid>/task/*/comm` — a plain file read, no JVMCI attach, no safepoint, so
it cannot perturb the wall clock it sits beside. Linux truncates the thread name
`TruffleCompilerThread` to `TruffleCompiler`. **20 samples spanning the compile,
19 of them exactly 16**, the twentieth (12) taken as the pool wound down during
the final `unit`/`jar` stages:

```
1789224220 pid=1273167 trufflecompiler=16 totalthreads=55
1789224235 pid=1273167 trufflecompiler=16 totalthreads=53
  … 16 further samples, every one trufflecompiler=16 …
1789224491 pid=1273167 trufflecompiler=16 totalthreads=53
1789224506 pid=1273167 trufflecompiler=12 totalthreads=46   (wind-down)
```

Against 6 observed under the default (Task 7 §1) and 3 under `CompilerThreads=3`.
The pool is exactly the requested size and stays there.

**(b) The utilization figure.** `Compilation Utilization` **2.501061 →
2.730003**. Structurally bounded by the pool size, so 2.73 is possible only with
a pool larger than… well, larger than 2.73 — but taken with (c) below it is the
right direction and magnitude: mean concurrency rose 9.2 % while the ceiling rose
167 %, i.e. the extra capacity was mostly idle.

**(c) The queue-wait signature, inverted from the 3-thread run.**
`Time waiting in queue` average **54 184.82 → 732.25 ns**, a **74x fall**; max
**2 219 707 → 337 114 ns**. At 3 threads the same figure rose 35x to 1 900 657.
Tripling service capacity against a comparable arrival process is the only thing
in this configuration that does that. The queue is no longer a constraint at all.

## 3. RESULT — wall and Stage parse first, then every stage

`elapsed=346s` from watched-run; `Stage parse` from the markers file.

| | T6 clean control (6 threads) | **THIS RUN (16 threads)** | delta | % |
|---|---|---|---|---|
| **wall clock** | **337 s** | **346 s** | **+9 s** | **+2.67 %** |
| **`Stage parse`** | **253.998** | **262.367** | **+8.369** | **+3.29 %** |

Every other stage, per ruling 2 — parse is ~76 % of the wall and holds
essentially all compilation, so it is reported because the user asked for it, not
as independent corroboration:

| stage | T6 clean (s) | **THIS RUN (s)** | delta | % |
|---|---|---|---|---|
| `Stage start` | 0.001 | 0.006 | +0.005 | — |
| `Stage parse` | 253.998 | **262.367** | **+8.369** | **+3.29 %** |
| `Stage syntaxcheck` | 0.000 | 0.000 | 0.000 | — |
| `Stage ast` | 0.000 | 0.000 | 0.000 | — |
| `Stage optimize` | 32.017 | **31.926** | -0.091 | -0.28 % |
| `Stage qast` | 25.389 | **25.988** | +0.599 | +2.36 % |
| `Stage unit` | 23.476 | **24.370** | +0.894 | +3.81 % |
| `Stage jar` | 0.000 | 0.000 | 0.000 | — |
| **stage sum** | **334.881** | **344.657** | **+9.776** | **+2.92 %** |

The stage sum rises 9.776 s beside the wall's +9 s. Per ruling 3 that is a
finer-resolution reading of the same run — it defeats the one-second quantisation
doubt, not run-to-run variance. Four of the five non-zero stages moved up; only
`optimize` is flat, and at -0.091 s it is inside any plausible per-stage noise.

Three stage values again collided with compiler-thread trace lines on the same
output line (the `--stagestats` artifact Task 3 documented). Each was read from
its flushed value line in the log: `optimize` 31.926 at line 366000, `qast`
25.988 at 382942, `unit` 24.370 at 392189. The same loss occurs identically in
the control, so the comparison is unaffected.

## 4. Counters, all from the statistics block unless labelled

| quantity | T6 clean (6) | **THIS RUN (16)** | delta |
|---|---|---|---|
| `total-compiler-ms` (summarizer) | 783 440 | **893 381** | **+109 941 (+14.0 %)** |
| `nqp-root-ms` (summarizer) | 727 228 | **832 026** | **+104 798 (+14.4 %)** |
| `Compilations` | 3 853 | **3 902** | +49 |
| `Success` | 3 334 | **3 355** | +21 (+0.63 %) |
| `Permanent Bailouts` | 372 | **372** | 0 |
| `Temporary Bailouts` | 147 | **175** | +28 |
| ↳ `Compilable not ready` (retryable) | 44 | **54** | +10 |
| ↳ `Compilation cancelled` | — | **101** | — |
| `Compilation Utilization` | 2.501061 | **2.730003** | +0.229 (+9.2 %) |
| `Splits` | 0 | **0** | 0 |
| `Queues` | 4 098 | **3 920** | **-178** |
| `Dequeues` | 343 | **127** | -216 |
| ↳ `Stale compilation task` | 190 | **2** | **-188** |
| `Queue Accuracy` | 0.916301 | **0.967602** | +0.051 |
| `Compilation Accuracy` | 0.755775 | **0.755510** | -0.000265 |
| `Time waiting in queue` (avg ns) | 54 184.82 | **732.25** | **-98.6 %** |
| `Time waiting in queue` (max ns) | 2 219 707 | **337 114** | -85 % |
| `Remaining Compilation Queue` | 0 | **0** | 0 |

`Remaining Compilation Queue : 0` is what proves nothing was truncated by process
exit — the queue drained fully here as it did at 3 and at 6 threads, so on all
three points lost compilations were superseded rather than deferred.

Tier-2 compiles: **0** (`grep -c 'opt done .*|Tier 2|'`), same as both other
points, so `Mode=latency`'s first-tier-only gate carried over intact and this run
adds nothing to the tier question. `Splits` is 0 as in every run of this
milestone. `unparsed=0`, `reasons-parsed=5131`, `min-too-large-size=2070` with
the same two roots as every prior run (`IMPL-FOLD-CONSTANT[2070]`,
`IMPL-OPTIMIZE-EXPRESSION[4030]`) — good evidence the three compiles did the same
work.

**The three failure-count channels, kept apart per ruling 4:**

| channel | T6 clean (6) | 3 threads | **THIS RUN (16)** |
|---|---|---|---|
| statistics block `Permanent Bailouts` | 372 | 366 | **372** |
| summarizer (`[engine] opt failed` anchored) `failed=` | 371 | 366 | **371** |
| raw `grep -c PermanentBailoutException` | 376 | 370 | **376** |

The summarizer runs 1 low against the statistics block (one `Stage`-prefixed
`opt failed` line its anchor cannot see — visible directly in the markers file,
the `Stage unit` line) and the raw grep 4 high (the statistics block's own
per-reason breakdown repeats the string). The 16-thread run reproduces the
control's 372 / 371 / 376 exactly. The spread moves no conclusion.

## 5. THE THREE-POINT CURVE

All three points on this 16-core box, same adopted tier policy
(`Mode=latency`, `FirstTierCompilationThreshold=1600`,
`LastTierCompilationThreshold=40000`), same CORE.c workload, one sample each.

| threads | wall (s) | `total-compiler-ms` | `Success` | stale dequeues | queue wait avg (ns) | Utilization |
|---|---|---|---|---|---|---|
| **3** | **327** | **619 075** | 3 000 | 1 137 | 1 900 657 | 1.996044 |
| **6** (default) | **337** | **783 440** | 3 334 | 190 | 54 185 | 2.501061 |
| **16** | **346** | **893 381** | 3 355 | 2 | 732 | 2.730003 |

**Wall: 327 → 337 → 346. Monotone increasing.**
**Compiler time: 619 075 → 783 440 → 893 381. Monotone increasing.**

There is no interior minimum. Wall rises by roughly 1 s per additional thread
across the whole measured range (+10 s over 3→6, +9 s over 6→16), and the
milestone's minimum on this workload lies at **or below** 3 threads — this curve
does not locate it, and 2 threads remains untested.

## 6. What the curve says about Task 7's mechanism

Task 7's mechanism survives, and the naive "more threads, more throughput"
expectation is refuted on wall time while being *confirmed* on the thing it
actually predicts — compilation throughput. Those are not the same quantity, and
separating them is what the third point buys.

Read the monotone columns together. Going 3 → 6 → 16, stale dequeues collapse
1 137 → 190 → **2**: with 16 threads essentially nothing is ever superseded
before a thread picks it up, queue wait falls to 732 ns, and the queue stops
being a constraint at all. So more threads genuinely do more compilation, exactly
as the naive expectation says. And yet **wall rises anyway**, which is the point:
the compilation those extra threads perform is not on the critical path, while
the CPU they consume is. Compiler time went up 14 % to buy 21 more successful
compilations.

The saturation is the sharpest single fact in the curve. From 3 → 6 threads,
`Success` gained **+334**; from 6 → 16 it gained **+21 (+0.63 %)** — which sits
*below* the milestone's 0.7 % noise floor for `Success` and therefore cannot be
claimed as a real gain at all. The third tranche of capacity bought nothing
measurable in compiled code while spending 110 s of extra compiler CPU, raising
cancellations (`Compilation cancelled` 101) and retryables (`Compilable not
ready` 44 → 54). Six threads already clear the queue nearly as well as sixteen.

So, in the dispatch's own terms: **wall time rises with more threads, the curve
has no minimum above 3, and contention dominates.** Task 7's -10 s is
contention relief; the compilation it lost was, on this evidence, compilation
that was not worth its CPU on a run-once build. Neither the "fewer stale
compiles" story nor the "more throughput" story is wrong — they describe
different axes, and the axis the wall clock lives on is contention.

Per ruling 7 I label the queue chain a **fit to the statistics block's own
counters**, not an established mechanism: the trace records no enqueue events.
One counter is worth flagging as not fitting a simple story — `Queues` itself is
non-monotone across the curve (4 726 at 3 threads, 4 098 at 6, **3 920** at 16),
so enqueue demand is not an independent arrival process but is itself shaped by
how fast compiles land. That is consistent with the fit and inconsistent with
treating arrivals as a fixed input.

## 7. Concerns

1. `Success` +0.63 % from 6 → 16 is below the 0.7 % floor: the extra
   compilation the high end buys is not distinguishable from noise.
2. One compile per point, no replicates; the wall column rests on the floor being
   an order-of-magnitude guide rather than a confidence interval.
3. +9 s wall is nine one-second quanta and is corroborated only by the stage sum,
   which is the same run at finer resolution, not an independent clock.
4. 16 threads on 16 cores leaves nothing for the main parse thread, GC and JVMCI;
   the result may be specific to this exact thread-to-core ratio.
5. An explicit value above 16 is accepted and unvalidated but was not measured at
   wall scale; on-demand pool growth means a larger request may not manifest more
   threads under this workload anyway.
6. `Queues` moves non-monotonically across the curve, so any queue story is a fit
   to counters and not an arrival-process model.
7. `optimize` is the one stage that did not rise (-0.091 s), so the increase is
   not uniform across stages.
8. Measured on CORE.c only, on one machine; BOOTSTRAP or a longer-lived process
   could differ, and a long-lived Rakudo would value the compilations the low end
   discards.
