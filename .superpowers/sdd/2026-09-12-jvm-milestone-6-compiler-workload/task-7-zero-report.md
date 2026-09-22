# Task 7 ZERO POINT — `engine.Compilation=false`: the curve's lower bound

**Status: DONE, one compile, `EXIT=0 verdict=ok elapsed=360s`.**

**Wall 360 s, `Stage parse` 278.213.** That is **+63 s (+21.2 %) against the
1-thread minimum of 297 s** and **+14 s (+4.0 %) against the slowest compiled
point on the curve (16 threads, 346 s)**. **Zero compilation is slower than every
compiled configuration measured in this milestone.** The prediction is
**CONFIRMED in direction**: the curve does not keep falling below 1 thread, it
turns. The minimum is interior, at **1 compiler thread**.

The prediction is **REFUTED in magnitude, and that is the interesting half.** The
registered reasoning said interpreted execution is "typically an order of
magnitude worse". Removing *all* Truffle compilation — 1826 compilations and
277 722 ms of compiler time at the 1-thread point, gone — costs **21 %**. Not
10x, not 2x. **The entire value of Truffle compilation on this workload is 63 s
of a 360 s run, and the 1→16 thread spread (297→346 s, +49 s) is 78 % as large as
that.** Compiling more than the minimum costs almost as much as not compiling at
all saves.

---

## 0. Provenance

- rakudo HEAD at launch: **`ac4980f905`**, worktree `jesp-direct-lazy-records`.
  HEAD moved to **`37c5e465c3`** mid-run as the controller committed ledger prose
  concurrently; `git diff ac4980f905..37c5e465c3 --stat` is **one file, the
  ledger, +25 lines**. No source file changed, so the run is against the same
  tree as the 1/2/3/4/6/16-thread curve.
- nqp HEAD: **`41c294b029`** (the nested, gitignored nqp.git tree), unchanged.
- `java`: Oracle GraalVM 25.2.4 (`25.0.4+7-LTS-jvmci-25.2-b20`), confirmed before
  the run. `nproc` 16.
- `blib` untouched: `find blib -newermt '2026-09-12 16:50'` empty before and after.
- `--output` to `m6-corec-nocomp.jar`, a filename no earlier run used.
- **`NQP_CODE_MAX_COMPILE` NOT set**: `env | grep -ci nqp_code` returned `0`
  before and after, and the driver `unset`s it explicitly before exporting.
- **`CompilerThreads` NOT set** — correct, since its floor is 1 and it cannot
  express zero.
- FORWARD ONLY: one compile, no re-run.
- `tools/build/truffle-trace-summary.raku` **not edited**.
- Artifacts under `/home/longwalker/.claude/jobs/804818e2/tmp/`:
  `m6-corec-nocomp.{log,markers,jar}`, driver `run-task7-zero.sh`, driver stdout
  `m6-task7zero-driver.out`, thread samples `t7zero-threadsample.txt`.

---

## 1. SCREEN — the option, from the jar this tree runs

`javap` on `com.oracle.truffle.runtime.OptimizedRuntimeOptions` and on
`OptimizedRuntimeOptionsOptionDescriptors`, both extracted from
`nqp/build/jvm/share/truffle/truffle-runtime-25.2.4.jar`.

| property | value | how read |
|---|---|---|
| **exists** | **yes** — `public static final OptionKey<Boolean> Compilation` | `javap -p` field list |
| **option name** | `engine.Compilation` | `ldc` in the descriptor builder |
| **default** | **`true`** | `<clinit>`: `iconst_1` → `Boolean.valueOf` → `new OptionKey(...)` → `putstatic Compilation` |
| **stability** | **EXPERIMENTAL** | `getstatic OptionStability.EXPERIMENTAL` in its builder chain |
| **category** | EXPERT | `getstatic OptionCategory.EXPERT` |
| **deprecated** | **no** | `Builder.deprecated(false)` — `iconst_0` |
| **help** | "Enable or disable Truffle compilation." | `Builder.help(...)` string constant |

EXPERIMENTAL is the same stability class as `CompilerThreads`, which Task 7 already
verified is accepted on the real engine path despite the NqpCheck probe rejecting
it. Consistent with the prior use the dispatch cites (cold `say 1` 4.10 s → 3.77 s).
It was **accepted here with no error, no warning and no experimental-option
rejection** — the log's only engine chatter is the log-redirection hint and the
statistics block.

---

## 2. IN FORCE — three independent channels, all zero

**(a) `opt done` lines: ZERO.** Not "few" — none, and no other trace verb either.
The option took.

| trace verb | count in `m6-corec-nocomp.log` |
|---|---|
| `opt done` | **0** |
| `opt queued` | **0** |
| `opt failed` | **0** |
| any line containing `id=` | **0** |
| any `[engine]` line | 1 — the statistics banner only |

`TraceCompilation=true` was on throughout (it is in the `JDK_JAVA_OPTIONS` echoed
by the JVM into the log), so the absence is the listener having nothing to report,
not the listener being off. The whole log is **86 lines**, against tens of
thousands in every compiled run of this milestone.

**(b) `/proc` thread count: NO Truffle compiler threads, ever.** Sampled every
12 s from `/proc/<pid>/task/*/comm`, the same non-invasive reader the curve used
(Linux truncates `TruffleCompilerThread` to `TruffleCompiler`).

| samples taken | samples with a `TruffleCompiler` thread | max seen |
|---|---|---|
| **30** | **0 / 30** | **0** |

Not an idle pool — **the pool is never created.** Total JVM thread count ranged
34-42 across the run, all of it the mutator, GC, and HotSpot's own threads.

**(c) The statistics block itself.** `CompilationStatistics=true` still printed a
full block; every counter in it is zero or the sentinel for an empty population:
`Compilations 0`, `Success 0`, `Queues 0`, `Dequeues 0`, `Splits 0`,
`Invalidated 0`, `Remaining Compilation Queue 0`, **`Compilation Utilization
0.000000`**, and `Compilation Accuracy` / `Queue Accuracy` both **`NaN`** —
0/0. The Tier 1 and Tier 2 sections print with `count=0` and
`min=9223372036854775` / `max=-9223372036854775`, the untouched `Long` extremes.
The summarizer agrees independently: `events=0 unparsed=0 total-compiler-ms=0
nqp-root-ms=0`, with `non-trace-lines=86` and **`unparsed=0`**, so nothing was
silently dropped on the way to that zero.

**One caveat stated plainly, because it bounds the whole result: the HOST JIT was
never off.** `engine.Compilation=false` disables *Truffle* compilation of guest
programs. HotSpot's own JVMCI/Graal compiler kept compiling the Java bytecode of
the Truffle interpreter itself — the sampler counted 1-5 `jvmci`-named threads
alive throughout. So "interpreted" here means *AST-interpreted by a fully
JIT-compiled Java interpreter*, not interpretation all the way down. This is the
reason the penalty is 21 % and not 10x, and any reading of the magnitude must
carry it.

---

## 3. RESULT — wall and every stage

`wall` is watched-run's own `EXIT=0 verdict=ok elapsed=Ns`. Stage values are the
`--stagestats` numbers; with no trace output to interleave, **every stage line
printed clean on its own line this time** — none of the marker/trace collisions
Task 3 documented and the curve had to work around. These are read directly.

| stage | **none (this run)** | 1 thread | 6 (default) | Δ vs 1 thread |
|---|---|---|---|---|
| `Stage start` | 0.000 | 0.001 | — | — |
| **`Stage parse`** | **278.213** | **225.941** | **253.998** | **+52.272 (+23.1 %)** |
| `Stage syntaxcheck` | 0.001 | 0.000 | — | — |
| `Stage ast` | 0.001 | 0.000 | — | — |
| `Stage optimize` | **33.406** | 23.680 | — | **+9.726 (+41.1 %)** |
| `Stage qast` | **21.751** | 21.169 | — | **+0.582 (+2.7 %)** |
| `Stage unit` | **25.644** | 24.352 | — | **+1.292 (+5.3 %)** |
| `Stage jar` | 0.000 | 0.000 | — | — |
| **stage sum** | **359.016** | 295.143 | — | **+63.873** |
| **wall** | **360 s** | **297 s** | **337 s** | **+63 s (+21.2 %)** |

The stage sum sits 1.0 s under the wall, the same ~1-2 s offset every run in this
milestone shows, and the stage-sum delta (+63.873) reproduces the wall delta
(+63) to within the wall's own one-second quantisation.

**Per ruling 2, the stage breakdown is reported in full and it is not uniform —
this is the one place where "the delta lives in parse" is actually earned, and
where it is qualified.**

- **`Stage parse` carries 82 % of the penalty** (52.3 of 63.9 s) while being 77 %
  of the run. Mildly over-represented, not dramatically.
- **`Stage optimize` carries 15 %** (9.7 s) off a 6.6 % base — **proportionally
  the worst-hit stage of the run at +41 %**, three times parse's relative
  penalty. The curve never surfaced this because optimize also rises with thread
  count (23.680 / 24.975 / 28.803 / 31.926 at 1/2/4/16) and the zero point simply
  extends that line to 33.406.
- **`Stage qast` and `Stage unit` are essentially unaffected** (+2.7 %, +5.3 %)
  and are in fact **faster than the 4- and 16-thread compiled runs** (qast 21.751
  here against 25.920 and 25.988). Those two stages were getting nothing from
  Truffle compilation to begin with; removing it costs them nearly nothing, and
  they were *paying* for it at high thread counts.

Against the noise floor (wall 0.2 % on one replicate pair): **+21.2 % is ~100x
the floor.** The floor is nowhere near binding, exactly as the dispatch expected.

---

## 4. The seven-point curve

| compiler threads | wall | `Stage parse` | total-compiler-ms | unique targets (`id=`) |
|---|---|---|---|---|
| **none (`Compilation=false`)** | **360 s** | **278.213** | **0** | **0 (0 %)** |
| **1** | **297 s** ← **minimum** | 225.941 | 277 722 | 1033 (61.8 %) |
| 2 | 323 s | 249.839 | 503 022 | 1552 |
| 3 | 327 s | 248.832 | 619 075 | 1626 |
| 4 | 341 s | 260.621 | 728 428 | 1649 |
| 6 (default) | 337 s | 253.998 | 783 440 | 1672 |
| 16 | 346 s | 262.367 | 893 381 | 1672 |

`total-compiler-ms` and unique-target counts are from the **summarizer channel**
over the trace log; wall is the **watched-run channel**; stage times are the
**stagestats channel**. Unique targets are counted by `id=`, per ruling 5.

**The curve is U-shaped with an interior minimum at 1 thread.** Compiler time is
still strictly monotone increasing across the whole seven points (0 is its floor),
but wall is not monotone in it — wall falls from 360 s at zero compilation to
297 s at minimal compilation, then rises again to 346 s at maximal. The 63 s fall
from none→1 is **larger than the 49 s rise from 1→16**, so the left arm is the
steeper one, but only by 29 %.

---

## 5. PREDICTION — confirmed in direction, refuted in magnitude

**CONFIRMED, by +63 s / +21.2 % against the 1-thread minimum.** The controller's
account survives its sharpest test. "Less compilation has meant a faster compile
at every measurable level" does **not** extrapolate to zero; the trend reverses
between 0 and 1 thread. The hotness-filter reading is intact: the 1033 targets a
single thread does reach are worth having, and the 639 it skips are the ones that
were not paying for themselves. The queue is a filter, not a tax, and this run
shows what happens when the filter is set to reject everything.

**REFUTED on magnitude, and this is the finding worth carrying forward.** The
registered reasoning predicted "SHARPLY slower" on the grounds that parse contains
loops executing millions of times and interpreted execution is "typically an order
of magnitude worse". Parse is 23 % slower, not 1000 % slower. **Guest-level
Truffle compilation is worth 21 % of a CORE.c compile.** Three things follow:

1. **The workload is not loop-dominated in the way the prediction assumed.** If
   grapheme scanning, regex matching and the dispatch loop were genuinely
   dominating parse and genuinely getting 10x from compilation, parse could not
   come within 23 % of its compiled time with compilation off. Either those loops
   are a smaller share of parse than believed, or the compiled versions are not
   winning much over the AST interpreter, or both. **This is testable and is not
   yet tested.**
2. **The host JIT is doing most of the work** (see §2's caveat). The Truffle AST
   interpreter is itself hot Java and HotSpot compiles it thoroughly. A large part
   of what is normally credited to "Truffle" on this workload is already being
   delivered by HotSpot underneath, and the guest-level layer is adding 21 % on
   top.
3. **It reframes the whole milestone's ranking.** A 1→16 thread misconfiguration
   costs 49 s; having no guest compiler at all costs 63 s. The tier and thread
   knobs are not fine-tuning around a large effect — **they are the same order of
   magnitude as the effect itself.** Getting the knobs wrong throws away most of
   what the compiler earns.

The dispatch's "if instead this run is FASTER than 297 s" branch did **not** fire.
The controller's account of why tier policy works is not overturned. But its
implicit sizing of the compiled/interpreted gap on this workload was off by
roughly an order of magnitude, and the ranking consequence in point 3 above is a
direct result.

---

## 6. Correctness

Build output is unaffected. The jar is 5 865 111 bytes, inside the same ±20-byte
band as all seven prior runs (5 865 108 - 5 865 130); those differ only in
embedded zip timestamps, so byte-identity is not available as a check and size
band plus `EXIT=0` is what can be claimed. How much of the compiler runs compiled
changes speed, never what it emits.

## 7. Concerns

- **The host JIT was never disabled**, so this measures the guest-compilation
  layer alone, not "interpretation" in the usual sense; the 21 % figure must
  always be quoted with that qualifier.
- **One replicate.** The effect is ~100x the wall noise floor, so the direction is
  safe, but the exact 63 s is a single sample.
- **The box was not idle**: the controller session was committing to the ledger
  concurrently (HEAD moved mid-run), the same condition the curve ran under.
- **`Stage optimize` at +41 % is the proportionally worst-hit stage** and no prior
  task in this milestone examined it; the curve's rising optimize times (23.7 →
  31.9 across 1→16 threads) suggest something stage-specific that neither the
  thread story nor the tier story currently explains.
- **CORE.c only, one machine.** Nothing here transfers to a long-running Rakudo
  process, where the compiled/interpreted gap should be far larger than 21 %
  because targets get to run more than once.
- **`--stall`/`--max` were raised to 1560 s** for this run (the default 900 s
  keys on output silence, and a run with no trace output is silent for the whole
  parse stage); the run finished in 360 s and never approached either, so nothing
  was truncated.
