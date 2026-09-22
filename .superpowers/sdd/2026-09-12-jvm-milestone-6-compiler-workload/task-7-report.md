# Task 7 — Knob 4, `engine.CompilerThreads`, layered on the adopted tier policy

**Status: DONE. Verdict KEEP.** Wall **337 s → 327 s** (-10 s, -2.97 %) and
`total-compiler-ms` **783 440 → 619 075** (-164 365, -21.0 %) against the Task 6
CLEAN baseline. This is the sweep's last compile, so the configuration in force
here is the shipping configuration.

- rakudo HEAD: **`b4dfe0a4de`** (worktree `jesp-direct-lazy-records`). Working
  tree carries only the pre-existing untracked logs plus the controller's own
  uncommitted Task 7 dispatch entry in the ledger; **no tracked source file
  changed** — this task is measurement only.
- nqp HEAD: **`41c294b02`** (the nested, gitignored nqp.git tree) — clean.
- `java`: Oracle GraalVM 25.2.4 (`25.0.4+7-LTS-jvmci-25.2-b20`), confirmed
  before the run.
- `blib` untouched (nothing under it newer than the task's start).
- `--output` went to `/home/longwalker/.claude/jobs/804818e2/tmp/m6-corec-threads.jar`,
  a filename distinct from every earlier run's.
- Artifacts: `…/tmp/m6-corec-threads.{log,markers}`, driver `…/tmp/run-task7.sh`,
  driver stdout `…/tmp/m6-task7-driver.out`, thread samples
  `…/tmp/task7-threadsample2.txt` and `…/tmp/t7-defaultthreads.txt`,
  screen-A disassembly `…/tmp/t7-screenA/{opts,desc,bcq}.txt`.
- FORWARD ONLY: one compile, `EXIT=0 verdict=ok elapsed=327s`, no re-runs.
- **`NQP_CODE_MAX_COMPILE` was NOT set.** `env | grep -i nqp_code` returned
  nothing before the run, and the driver script executes an explicit
  `unset NQP_CODE_MAX_COMPILE` before exporting anything.

---

## 1. SCREEN A — the default, and why the brief's `cores/2` would have been the
## wrong experiment

`nproc` = **16**. The brief said "use half of it" — **8**. Screen A says 8 would
have been an *increase*, not a reduction, and would have tested the opposite of
the milestone's hypothesis. Here is the evidence.

**The declared default is `-1`.** From `javap -p -c` on
`com/oracle/truffle/runtime/OptimizedRuntimeOptions.class` (extracted from
`nqp/build/jvm/share/truffle/truffle-runtime-25.2.4.jar`), the `<clinit>`
sequence that builds the `CompilerThreads` key:

```
181: new           #22   // class org/graalvm/options/OptionKey
185: iconst_m1                       <-- default value is -1
186: invokestatic  #102  // Integer.valueOf
189: invokespecial #30   // OptionKey.<init>
192: putstatic     #107  // Field CompilerThreads
```

The generated `OptimizedRuntimeOptionsOptionDescriptors` confirms the identity
and the help text: `engine.CompilerThreads`, usage syntax `[1, inf)`, help
*"Manually set the number of compiler threads. By default, the number of
compiler threads is scaled with the number of available cores on the CPU."*
Category `EXPERT`, stability **`STABLE`** — this particular option is *not*
experimental, though the tier-policy options it is layered on are, which is why
the probe still false-rejects the set as a whole.

**What `-1` resolves to here.** The only consumer is
`com/oracle/truffle/runtime/BackgroundCompileQueue`, whose constructor
disassembles to:

```
 93: iload 4; ifne 118          ; if (threads == 0)
 98: Runtime.availableProcessors -> procs
109: if procs >= 4 -> threads = 2
118: iload 4; ifge 163          ; else if (threads < 0)   <-- our -1
123: Runtime.availableProcessors -> procs
133: log2(procs)                        ; log2 = 31 - numberOfLeadingZeros
141: Math.max(log2(procs), 1)
144: log2(  ... )
149: procs / 4
155: iadd                               ; procs/4 + log2(max(log2(procs),1))
158: Math.min( ... , 16)
163: threads = Math.max(1, threads)
```

At `procs = 16`: `log2(16) = 4`; `max(4,1) = 4`; `log2(4) = 2`; `16/4 = 4`;
`4 + 2 = 6`; `min(6,16) = 6`; `max(1,6) = 6`. **The default resolves to 6 on
this box.**

**Confirmed empirically, not just by arithmetic.** A short engine run with the
tier options but *no* `CompilerThreads` option, sampled non-invasively from
`/proc/<pid>/task/*/comm` (Linux truncates the thread name
`TruffleCompilerThread` to `TruffleCompiler`):

```
1789223176 pid=1270709 trufflecompiler=6 totalthreads=50
1789223177 pid=1270709 trufflecompiler=6 totalthreads=50
1789223178 pid=1270709 trufflecompiler=6 totalthreads=50
1789223179 pid=1270709 trufflecompiler=6 totalthreads=50
```

Six, exactly as the formula predicts. (`t7-defaultthreads.txt`; the two low
samples in that file are the pool warming up — 0 then 1 — before it reaches its
core size.)

**Chosen value: `CompilerThreads=3`.** Reasoning:

1. **8 would be a replicate of nothing useful.** It is 33 % *more* than the
   real default of 6, so it would probe the increase direction the milestone did
   not ask about, and weakly.
2. **3 halves the real default**, a clean 2x factor — the largest single
   reduction that is still defensible as non-starving.
3. **3 still covers measured average demand.** The baseline's
   `Compilation Utilization` is 2.501061, i.e. on average ~2.5 compiler threads
   were busy. A cap of 3 sits just above that, so steady-state capacity is
   preserved and only *bursts* are queued — which is precisely the contention
   the milestone wanted tested.
4. **2 was rejected** as below average demand: it would confound "less
   contention" with "obvious starvation" and make the result hard to attribute.

## 2. SCREEN B — structural

The thread count is implemented in `com.oracle.truffle.runtime.BackgroundCompileQueue`
(truffle-runtime jar), read **once** at pool construction via
`OptimizedCallTarget.getOptionValue(OptimizedRuntimeOptions.CompilerThreads)`
and passed as both core and maximum pool size to the inner
`BackgroundCompileQueue$TruffleThreadPoolExecutor`, whose threads are named
`TruffleCompilerThread` by `newThreadFactory`. **That machinery is on our path**:
the same class prints the `Queues` / `Dequeues` / `Time waiting in queue` /
`Remaining Compilation Queue` lines that both this run's and the baseline's
statistics blocks contain, and the baseline's own
`Time waiting in queue : count=3852` proves that executor ran the compile's
tasks. Checked: the `<clinit>` default, the constructor's resolution arithmetic,
the option descriptor's name/stability, the set of classes referencing the
option (`grep -rl --text` over the extracted jar returns exactly
`OptimizedRuntimeOptions`, its descriptors, and `BackgroundCompileQueue`), and
the live thread names in both a default run and the measured run.

## 3. Real-path acceptance — NOT BLOCKED

`NqpCheck.java:31` builds its context without `allowExperimentalOptions(true)`
while `NqpPolyglot.kt:49-51` — the context the compiler actually uses — enables
them, so the probe cannot judge this option set. Per the dispatch, verified on
the engine path instead (~20 s):

```
$ JDK_JAVA_OPTIONS='-Dpolyglot.engine.Mode=latency \
    -Dpolyglot.engine.FirstTierCompilationThreshold=1600 \
    -Dpolyglot.engine.LastTierCompilationThreshold=40000 \
    -Dpolyglot.engine.CompilerThreads=3' \
  RAKUDO_RAKUAST=1 ./nqp/nqp-j-gradle -e 'say("engine-ok")'
NOTE: Picked up JDK_JAVA_OPTIONS: ...
engine-ok
```

Accepted.

## 4. IN FORCE — three independent channels, one of them direct

Accepted is not in force. This run has direct evidence, which the earlier knobs
did not.

**(a) Direct thread count, the decisive one.** Sampled from
`/proc/<pid>/task/*/comm` — a plain file read, no JVMCI attach, no safepoint, so
the measurement cannot perturb the wall clock it sits beside. **14 samples
spanning the whole 327 s compile, every one of them 3:**

```
1789222756 pid=1269031 trufflecompiler=3 totalthreads=41
1789222776 pid=1269031 trufflecompiler=3 totalthreads=38
  ... (12 more, all trufflecompiler=3) ...
1789223016 pid=1269031 trufflecompiler=3 totalthreads=37
```

Against the 6 observed under the default in §1. **The pool is exactly half its
default size and stays there.**

**(b) The utilization ceiling.** `Compilation Utilization` **2.501061 → 1.996044**.
With a 3-thread cap the figure is structurally bounded by 3, and 1.996 means the
3 threads ran ~67 % busy where the baseline's 6 ran ~42 % busy. Consistent with
(a) and with nothing else.

**(c) The queue-wait signature.** `Time waiting in queue` average
**54 184.82 → 1 900 656.61** ns, a **35x** rise, max 2 219 707 → 31 076 832.
Halving service capacity against an unchanged arrival process is the only thing
in this configuration that can do that.

## 5. Result — every stage reported

"The delta lives in Stage parse" is not evidence: parse is ~76 % of this wall
and holds essentially all compilation. So every stage:

| stage | T6 clean (s) | **T7 (s)** | delta | % |
|---|---|---|---|---|
| `Stage start` | 0.001 | 0.001 | 0.000 | — |
| `Stage parse` | 253.998 | **248.832** | **-5.166** | **-2.03 %** |
| `Stage syntaxcheck` | 0.000 | 0.000 | 0.000 | — |
| `Stage ast` | 0.000 | 0.000 | 0.000 | — |
| `Stage optimize` | 32.017 | **27.217** | **-4.800** | **-15.0 %** |
| `Stage qast` | 25.389 | **25.524** | **+0.135** | +0.53 % |
| `Stage unit` | 23.476 | **24.030** | **+0.554** | +2.36 % |
| `Stage jar` | 0.000 | 0.000 | 0.000 | — |
| **stage sum** | **334.881** | **325.604** | **-9.277** | **-2.77 %** |

The stage sum falls 9.277 s independently of the wall's 10 s, which is the
corroboration the one-second wall quantum needs. Note the shape is **not** the
uniform fall Task 6 produced: `optimize` carries 4.8 s of the 9.3 s on a stage
that is only 9.6 % of the wall, while `qast` and `unit` each moved *up* slightly.
That asymmetry is reported rather than smoothed over — it is what a capacity cap
looks like when background compilation is not evenly distributed across stages.

Three stage times again collided with compiler-thread trace lines on the same
output line (the known `--stagestats` artifact Task 3 documented: the label
prints, the stage runs while compiler threads write, and the value is flushed
only a few lines before the *next* `Stage` marker). Each was read from its
flushed value line — `optimize` 27.217 at log line 356808, `qast` 25.524 at
374643, `unit` 24.030 at 383918. The same loss occurs identically in the
baseline, so the comparison is unaffected.

| quantity | T6 clean | **T7** | delta | floor |
|---|---|---|---|---|
| wall clock | 337 s | **327 s** | **-10 s (-2.97 %)** | 0.2 % |
| `total-compiler-ms` | 783 440 | **619 075** | **-164 365 (-21.0 %)** | 0.7 % |
| `nqp-root-ms` | 727 228 | **565 834** | **-161 394 (-22.2 %)** | — |
| `Success` (stats block) | 3 334 | **3 000** | **-334 (-10.0 %)** | 0.7 % |
| `Permanent Bailouts` (stats block) | 372 | **366** | **-6 (-1.6 %)** | 0.9 % |
| `Compilation Utilization` | 2.501061 | **1.996044** | -0.505 (-20.2 %) | — |
| `Splits` | 0 | **0** | 0 | — |

`Splits` is **0 on both sides**, as it has been in every run of this milestone —
splitting is disabled by `Mode=latency` here, and it produced zero splits in
Task 3 when it was enabled, so it remains incapable of contributing to any
verdict. `unparsed=0`, `reasons-parsed=4642`. `min-too-large-size=2070` with the
same two roots as every prior run (`IMPL-FOLD-CONSTANT[2070]`,
`IMPL-OPTIMIZE-EXPRESSION[4030]`) — good evidence the two compiles did the same
work. Tier-2 compiles: **0** on both sides (`grep -c 'opt done .*|Tier 2|'`),
so the tier policy carried over intact and this run adds nothing to it.

**The three failure-count channels, kept apart as instructed:**

| channel | T6 clean | **T7** |
|---|---|---|
| statistics block `Permanent Bailouts` | 372 | **366** |
| summarizer (`[engine] opt failed` anchored) `failed=` | 371 | **366** |
| raw `grep -c PermanentBailoutException` | 376 | **370** |

In this run the statistics block and the summarizer agree exactly at 366 (the
baseline's 372/371 split came from a single `Stage`-prefixed `opt failed` line
the summarizer's anchor could not see; this run has no such collision on a
`failed` line). The raw grep runs 4 high by the same mechanism as always — the
statistics block's own per-reason breakdown repeats the string. The spread moves
no conclusion.

## 6. What actually happened — labelled as a fit, not an established mechanism

Per ruling 5, no queue mechanism is asserted as established; the trace records
no enqueue events. What follows is a **fit to observed quantities**, all of
which come from the statistics block's own counters rather than from inference:

| quantity | T6 clean | **T7** |
|---|---|---|
| `Queues` | 4 098 | **4 726** (+628) |
| `Dequeues` | 343 | **1 343** (+1 000) |
| ↳ `Stale compilation task` | 190 | **1 137** (+947) |
| `Compilations` | 3 853 | **3 422** (-431) |
| `Queue Accuracy` | 0.916301 | **0.715827** |
| `Compilation Accuracy` | 0.755775 | **0.779369** |
| `Temporary Bailouts` | 147 | **56** |
| ↳ retryable `Compilable not ready` | 44 | **2** |
| `Time waiting in queue` (avg ns) | 54 184.82 | **1 900 656.61** |

The quantities cohere as: capacity halved → each task waits ~35x longer before
pickup → far more tasks are already stale when a thread reaches them
(`Stale compilation task` +947) and are dropped instead of compiled → 431 fewer
compilations run and 334 fewer succeed → 164 s of compiler-thread work is never
performed. The retryable "not ready" count collapsing 44 → 2 fits the same
picture from the other side: a task that would previously have been *caught
mid-flight* by an invalidation is now discarded at the queue instead, before a
compiler thread ever starts it.

**This matters for how the win is described.** The -21 % compiler time is only
partly contention relief; a large share is **compilation that was never done**,
because the queue discarded it as stale. For a run-once 327-second build that is
a clean win — those compiles were servicing targets that had already been
superseded. It is emphatically **not** transferable to a long-lived Rakudo
process, where the discarded compilations would have been worth having.

I record honestly that neither of the dispatch's two predicted outcomes occurred
in pure form. Contention relief alone would have cut wall without cutting
`Success`; starvation would have pushed wall *up*. What happened is a third
thing: wall fell modestly **and** less compilation was done, with no wall
penalty from the work that was dropped.

## 7. Verdict: **KEEP**

**-10 s wall (-2.97 %) and -164 365 `total-compiler-ms` (-21.0 %)**, layered on
top of the tier policy, with the option's effect directly observed rather than
inferred.

Judged against the floor: the wall floor is 0.2 %, so -2.97 % is ~15x it, and
the floor's wall component is a single one-second difference at the measurement
quantum — a resolution limit, not a variance estimate. A 10-second fall is ten
quanta, and it is corroborated independently by the stage sum (-9.277 s, a
finer-grained clock) and by the compiler-side counters. `total-compiler-ms` at
-21.0 % against a 0.7 % floor is ~30x.

This is the **smallest** effect the milestone has adopted — Task 6 was -22.4 %
wall — and it deserves to be labelled as such. It is kept because it is outside
the floor on two independent clocks, because its mechanism is directly observed
(3 threads, not 6), and because it costs nothing: it is one JVM flag on a
build-side command line.

**Knobs in force at the end of the sweep — this run's exact set:**

```
-Dpolyglot.engine.Mode=latency -Dpolyglot.engine.FirstTierCompilationThreshold=1600 -Dpolyglot.engine.LastTierCompilationThreshold=40000 -Dpolyglot.engine.CompilerThreads=3
```

**The line Task 11 should adopt** drops `LastTierCompilationThreshold`, which
Task 6 established is accepted and parsed but structurally inert under
`Mode=latency` (`firstTierOnly` forces its gate false) and which this run
confirms is inert by producing zero tier-2 compiles:

```
-Dpolyglot.engine.Mode=latency -Dpolyglot.engine.FirstTierCompilationThreshold=1600 -Dpolyglot.engine.CompilerThreads=3
```

`NQP_CODE_MAX_COMPILE` is **not** in the shipping configuration and was dropped
from the milestone entirely.

## 8. Concerns

1. The -21 % compiler-time win is substantially **work not done** (`Success`
   -334, stale dequeues +947), not purely contention relief; correct for a
   run-once build, not transferable to a long-lived process.
2. **`CompilerThreads=3` is hardware-specific.** The default formula yields 6 at
   16 cores but only **2** at 4 cores, so a literal `3` would *raise* the thread
   count on small machines. It should ship expressed against the box it was
   measured on, or be guarded by a core-count check.
3. `Time waiting in queue` rose 35x and `Queue Accuracy` fell to 0.716 — the
   queue is now the binding constraint. **2 threads is untested** and plausibly
   past the starvation knee; this run does not locate that knee.
4. One compile, no replicate. -2.97 % wall is the narrowest margin the milestone
   has adopted and rests on the floor being an order-of-magnitude guide rather
   than a confidence interval.
5. The stale-dequeue chain in §6 is a **fit** to the statistics block's counters,
   not an established mechanism; the trace records no enqueue events.
6. `qast` (+0.135 s) and `unit` (+0.554 s) moved the wrong way. Both are inside
   any plausible per-stage noise, but the fall is not uniform across stages as
   it was in Task 6, so the effect is less structurally corroborated.
7. Measured on CORE.c only; BOOTSTRAP or a longer-lived stage could differ.
