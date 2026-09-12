# Milestone 6: the compiler's own workload (truffle-only plan item 4)

Design, 2026-09-12. Approved in chat the same day.

Position: `docs/jvm-truffle-only-plan.md` item 4. Milestones 1-5 of the
unit-artifact road are closed and the engine merge is done (rakudo
`f0694e1d6b`, nqp `41c294b02`). Items 5, 6, 7, 8 and 9 are closed;
items 1, 2 and 3 are partial and paused. Item 4 has never been started
and is the only item that owns the CORE.c clock.

## Goal

Rank and adopt the levers on the compiler's own workload, then answer
whether an ahead-of-time image is worth pursuing.

The problem, as the 2026-09-07 profile and the 2026-09-09 census state
it: the compiler's own blocks now run as engine programs, so run-once
compiler code pays the DSL interpreter (2 % -> 18 % of samples) and
Truffle JIT-compiles it on about five cores for the whole compile
(compiler threads 61 % of CPU samples, JVMCI 14 %, the main thread
17 %). A traced compile found 1880 s of Truffle compiler time, 733 s of
it spent on 114 roots that failed with "code installation failed: code
is too large" after 6.4 s each.

`NQP_CODE_MAX_COMPILE` (`nqp/nqp-truffle/.../NqpRootNode.java`) already
gates `prepareForCompilation` on program size and has never been
measured. That is the single largest named-and-unmeasured lever in the
tree.

## User decisions (2026-09-12)

1. **The spine is item 4**, not the suite clock, and not the correctness
   debt.
2. **Forward-only, taken to its conclusion.** Every measurement runs
   with all knobs adopted so far, so the LAST measurement is already a
   measurement of the shipping configuration. There is no confirmation
   build. The configuration in force at the last measurement is adopted
   wholesale.
3. **Then the spike.** Phase B is the Native Image spike on nqp alone,
   and it forces an answer to the question tabled 2026-09-11 about
   signature immutability for `native`-trait callables.
4. **Rebase at close, not at open.** The tree stays exactly as milestone
   5 and the engine merge left it, so every baseline is comparable; the
   57-commit upstream catch-up is Phase C.
5. **Greedy sequential sweep, cheapest knob first**, one knob per
   compile, for per-knob attribution in the findings doc.
6. **`t/spec` now waits for `t/` under 30 minutes** (revised from two
   hours the same day). Closed milestones keep the two-hour wording as
   historical record; no new plan may cite it.

7. **Never replace an eval server mid-sweep.** Before any `t/` run,
   pass the total file count as `--chunk` to
   `tools/build/evalserver-sweep.raku`. The script's own guidance is
   stale: its default (`max(3, heap * 15 div 8)`, about 15 files at 8 GB)
   and its "lower `--chunk`" advice both date from the memory leak,
   which has been fixed for some time. Every replacement discards a warm
   JIT state that cost the whole previous chunk to build. Note the
   arithmetic: `--chunk` equal to the total yields exactly one chunk, so
   the sweep runs on one server and `--jobs` has nothing to parallelise
   over; `--chunk` equal to total divided by server count keeps the rule
   while keeping N servers.

Standing rules that bind this milestone: one compile per change on the
engine toolchain and no A/B arms; runtime performance outranks compile
time when a change trades one for the other, and the milestone must say
which clock moved; tooling in Raku; Kotlin for new runtime code; every
diagnostic env-gated; every instrument smoke-tested on a 30 s workload
with a required positive marker before a long run; subagents on Opus
first; commits stamped in the evening.

## The finding that sets Task 0

**The tree's build products do not correspond to its HEAD.**

| artifact | built |
|---|---|
| nqp stage and compiler jars (`nqp/build/jvm/share/lib/`) | 2026-09-11 21:16 |
| rakudo `blib/` jars and the three settings | 2026-09-11 21:17 - 21:34 |
| nqp runtime and truffle jars | 2026-09-11 23:46 |

Two nqp encoder commits land after all of them: `7e7aaca61` (a uint
argument travels in the int slot) and `df564ddbb` (`encode_args`
refuses an out-of-range flag). Encoder changes under
`nqp/src/vm/jvm/QAST/` need a `clean buildJvm`, because the stage graph
misses that edge. The engine merge (nqp `b34bc52e5`, `8f8b2909d`) then
replaced the runtime jars again.

Measuring on this state would repeat the trap that voided milestone 4's
numbers, where every runtime figure was taken on a setting that never
lowered native arithmetic. Milestone 6 therefore opens with a clean
build from the top, and that build's numbers are the milestone
baseline.

Baselines to beat, for reference only (milestone 5's build, nqp
`df564ddbb` / rakudo `e0e4bbc35d`): nqp `clean buildJvm` 256 s; CORE.c
464 s, of which parse 352.4 s and optimize 36.6 s.

**`make` has TWO milestone 5 figures, and using the wrong one invents a
regression.** Milestone 5 measured `make` after a clean nqp build
(incremental) at **1054 s**, and `make clean && make` at **1133 s**,
twice, with an identical CORE.c parse of 352 s. Its own record says the
perf session baselines against BOTH. A clean-build measurement therefore
compares against 1133 s, never against 1054 s. This correction was made
2026-09-12 after the milestone 6 baseline (a clean build at 1122 s) was
briefly read as a 6.5 % regression against 1054 s; against the right
comparator it is 11 s faster, which is what every component clock
already said. Always pin the method to the number.

## Phase A: baseline and knob sweep

### Task 0 — the clean build

`./nqp/gradlew -p nqp clean buildJvm`, then `make` from the top, both
through `tools/build/watched-run.raku` with `--log` and `--show-file`.

Deliverable: the current-HEAD baseline for the nqp build, the full
make, and the CORE.c stage times. Any breakage the two unbuilt encoder
commits surface is repaired here; that repair is in scope.

Gate: `t/01-sanity` 25/25 and the nqp suite at its nine known reds
(`t/jvm/01-continuations` 3/22, `t/jvm/11-dispatch` 20/160,
`t/nqp/021` 6/33, `t/nqp/022` 1/7, `t/nqp/044` 1/62, `t/nqp/112` 2/26,
`t/p5regex` 3/182, `t/qast` 175/184, `t/qregex` 21/845).

### Task 1 — the instruments

Two summarizers in Raku under `tools/build/`, each smoke-tested on a
30 s workload and required to print a positive marker before any long
run starts:

- `truffle-trace-summary.raku` — input a log carrying
  `engine.TraceCompilation` and `engine.CompilationStatistics` output;
  output compiles, failures grouped by reason, mean compile time, and
  the top 20 roots by compile time. `CompilationStatistics` prints only
  with `NQP_CODE_CLOSE_AT_EXIT=1`.
- `jfr-summary.raku` — input `jfr print --events jdk.ExecutionSample
  --stack-depth N`; output top frames by inclusive share, grouped by
  load-path stage (`UnitZip.read` / LZ4, `UnitFormat.readMeta`,
  `ProgramUnit.buildTable`, deserialize, `initializeCompilationUnit`,
  `NqpLanguage.parse`, HotSpot warm-up markers).

### Task 2 — the traced CORE.c baseline

The standalone compile, taken from the Makefile's own recipe (`make -n
blib/CORE.c.setting.jar` prints the `rakudo-j-build ... --target=jar
--output=blib/CORE.c.setting.jar ... CORE.c` command), with `--output`
redirected to a scratch path so `blib` stays the built state. Run under
`watched-run.raku` with `--show='Stage'`.

Configuration: `JDK_JAVA_OPTIONS='-Dpolyglot.engine.TraceCompilation=true
-Dpolyglot.engine.CompilationStatistics=true'` and
`NQP_CODE_CLOSE_AT_EXIT=1`.

Records: wall clock, the stage times, the count and mean compile time
of roots failing "code is too large", and total compiler time. This is
the reference every later configuration is judged against.

### Tasks 3-6 — the greedy sequential sweep

One knob per compile, cheapest first. A knob that measurably wins stays
in for every later compile; a knob that does not is dropped and never
revisited. Every option set is probed first through
`org.raku.nqp.truffle.NqpCheck` on the same module path (seconds),
because a bad option surfaces through `rakudo-j` as an opaque
`ExceptionInInitializerError`.

| task | lever | note |
|---|---|---|
| 3 | `NQP_CODE_MAX_COMPILE` | set just below the smallest failing root's wire size, taken from Task 2's trace |
| 4 | `engine.PartialBlockCompilation=true` (+ `PartialBlockMaximumSize`) | with Task 3's threshold removed, so big roots split instead of being skipped; if both help, combine |
| 5 | tier policy | `engine.Mode=latency`, `engine.MultiTier`, `engine.FirstTierCompilationThreshold` / `LastTierCompilationThreshold`, `engine.DynamicCompilationThresholds*`. There is no `engine.CompilationThreshold` |
| 6 | `engine.CompilerThreads` | at cores/2; this box has 16 cores and Truffle currently takes about five |

Task 1 Step 4 of the superseded 2026-09-10 session asked for one shared
`Engine` across the two contexts. The engine merge delivered it
(`NqpPolyglot.kt`, one language `nqp`, one context), so that step is
already banked and is not repeated here. Sources are named per block
and per rule pass; confirm the named Sources appear in
`engine.CompilationStatistics` output while Task 2 runs.

### Task 7 — the other two clocks, once, under the adopted configuration

- **Cold start.** JFR of `./rakudo-j -e 'say 1'` via
  `RAKUDO_JVM_XOPTS='-XX:StartFlightRecording=...,settings=profile'`,
  summarized by Task 1's script. Reference: 4.10 s cold, 3.77 s with
  compilation off. Output is a ranked list of load-path levers (lazy
  meta decode per block, lazy `CodeRef`/`StaticCodeInfo` tables, mapped
  or streamed `unit.programs`, a smaller serialized context, class-data
  sharing) for a later milestone. No code changes in this task.
- **The green `t/` subset**, warm and cold: `t/01-sanity` (25),
  `t/06-telemetry` (4), `t/13-experimental` (9), `t/07-pod-to-text`
  (2) = 40 files, all green in milestone 3's sweep 2. Warm through one
  eval server, `--chunk=40` so no server is replaced mid-run (user rule,
  decision 7); cold through `watched-run.raku -t=<dirs> --jobs=3`. The
  difference divided by 40, against the cold-start figure, gives the
  start-up share of the test clock. This is also the milestone's first
  data point against the 30-minute `t/` gate.
- **The loop baseline.** `docs/bench/jesp/plusquick.raku` once with
  `NQP_DISPATCH_STATS=1`, and `docs/bench/jesp/resume-smoke.raku` once
  (its output must not change). This is the place to explain milestone
  5's unexplained `slowEvals` 364 -> 976 on the plusquick road, with
  every other dispatch counter identical and plusquick +3.5 %
  (82.625 -> 85.525 ns/op).

### Task 8 — adopt and record

The configuration in force at the last measurement becomes the default.
**Build-side and runtime-side adoption are separate decisions**: a knob
that skips compiling a huge root helps the build and may cost runtime,
because a root that never compiles never speeds up either. Report both
clocks for every adopted knob.

Adoption sites:

| site | file |
|---|---|
| build | `tools/templates/jvm/rakudo-j-build.in`, and `Makefile.in`'s `j_truffle_args` via `tools/lib/NQP/Config/Rakudo.pm` |
| runtime | `tools/build/create-jvm-runner.pl`'s `$jopts` |
| eval server | its runner line |

Findings doc: `docs/jvm-perf-findings-2026-09.md` (new). It carries the
configuration-versus-wall-clock table, the stage times, compiler time,
failed-root counts, the three clocks, and the ranked lever list that
milestone 7 inherits: for each lever, which clock it moves, the
measured or estimated gain, and its cost (config, runtime-only code,
stage build, or RakuAST).

No confirmation build.

## Phase B: the ahead-of-time spike

A spike, not a deliverable: the output is an answer plus a recipe, never
a binary. Images are invalidated by every runtime change, so a kept
binary would be stale within the week.

Scope: Native Image of **nqp alone**. No Rakudo, no NativeCall, no
interop. Measure `nqp-j -e` startup and the nqp suite against Task 0's
baseline.

Why it belongs in this milestone rather than a separate one: the second
of the three ranked values of an image is precompiling the Truffle
interpreter itself, so run-once compiler blocks stop paying HotSpot's
interpretation of the interpreter. That is item 4's problem stated from
the other side. The third value, the auxiliary engine cache, is a
Native Image feature and is unreachable on the JVM, which the 2026-09-10
research already established.

Blockers, as of 2026-09-12: the class road is gone (milestone 4), the
P6Opaque ASM classes and the interop adaptor generator are gone
(milestone 5), and the engines are merged. What remains is NativeCall's
runtime-chosen FFM signatures, plus interop's runtime reflection over
arbitrary classes. Neither is in the nqp-only spike's path.

Deliverables:

1. The recipe (what it took to build, or precisely where it stopped).
2. `nqp-j -e` startup and nqp-suite numbers, or the reason there are
   none.
3. **A written answer to the question tabled 2026-09-11**: would a rule
   that a callable with the `native` trait cannot have its signature
   rewritten dynamically (a runtime error if tried) give the closed set
   of downcall and upcall descriptor shapes that an image needs at build
   time? Grounding: the JVM runtime builds FFM handles at run time in
   `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/NativeCallOps.kt`
   (`downcallHandle` at :96, :418, :669 from a `FunctionDescriptor`
   built at :662; `upcallStub` at :1111), and `lib/NativeCall.rakumod`
   computes the call lazily at first call (`!setup`, :338).
4. A recommendation: pursue, park, or drop.

Time-boxed. If the image will not build, the reason is the finding and
that closes the phase.

## Phase C: the close

1. Rebase rakudo onto `rakudo/rakudo` main (57 commits behind as of
   2026-09-12; it was 21 at the engine-merge close) and nqp onto
   `Raku/nqp` main.
2. Fix what the rebase breaks; re-gate with `t/01-sanity` and the nqp
   suite.
3. `git push --force-with-lease ab5tract ...` in both trees.
4. Add the missing rows to `docs/jvm-pr-stack.md`: milestone 5, the
   engine merge, and milestone 6. The table currently stops at
   milestone 4.
5. Update `docs/jvm-truffle-only-plan.md`'s position row for item 4 and
   the relevant memory files.

Note for planning: the rebase changes the setting sources, so it changes
what CORE.c compiles. Every Phase A number describes the pre-rebase
tree and must be labelled as such. A post-rebase re-measure is milestone
7's business, not this milestone's.

## Out of scope

- **Engine code work for tier policy.** Phase A is configuration only.
  Every lever in tasks 3-6 is reachable as a knob.
- **Items 1, 2 and 3** (the plain call's per-call `Object[]` and OSR
  shape; HLL-simplification slice 2 and the diamond 7 re-validation;
  dispatch blocks and the `NQP_CODE_NOFRAME` knob that breaks the CORE.d
  compile).
- **The correctness debt**, registered below.
- **`t/spec`**, gated at `t/` under 30 minutes. Task 7's subset
  measurement says how far off we are; the last full sweep was 420 files
  in 6039 s, so the target is roughly a 3.3x reduction.
- **A full `t/` sweep.** It is not a perf instrument and costs about 100
  minutes.

## Inherited open-item register

Milestone 7's inbox, gathered from the milestone 4 and 5 ledgers, the
milestone 5 spec, the migration doc, the strict-campaign handoff and the
PR-stack doc. Nothing here is milestone 6's work; it is written down so
it is not rediscovered.

**Correctness, with a named mechanism**

| item | where |
|---|---|
| A unit loads twice when a `ControlException` (continuation capture) crosses its load block; the `finally` un-marks it. Fix named: set `loaded = true` in the `ControlException` arm | `nqp/.../UnitLoader.kt:95-100`, milestone 4 ruling r2, PARKED for the PR stack |
| `native-return-coercion.t` 19/23, carried unchanged through milestones 4 and 5; the four `dies-ok` reds assert a boxed operand does not auto-coerce to a native target, and it still does | reds #7, #17, #18, #19 |
| Suspension inside the multi-dispatch bind/accepts site resumes with the inner value; also the mechanism behind `nqp/t/jvm/11-dispatch.t` #141 | `NqpOps.java:176`, `:963` |
| `RakOps.p6typecheckrv`'s failure tail raises `dieInternal` instead of `X::TypeCheck::Return` | milestone 4 task 9 |
| `enter-leave.t` #35: a LEAVE value clobbers a do-block return | milestone 4 task 8 |
| `AdaptorUnit` sets no `staticInfo.methodName`, so backtrace line info through interop frames regresses; fix named (`sci.methodName = "qb_$i"`, as `ProgramUnit.kt:42`) | marked final fix wave, appears never done |
| The unsigned/uint boxing campaign is unfinished and was drawn at batch 23: `RET_UINT` readers, `ARG_UINT` binder sites (boxed with `box_i` at four sites), container FETCH, the `RT_UINT` compiler box. Milestone 5's `encode_args` fix (nqp `7e7aaca61`) cut into it but the named sites remain. A uint above 63 bits still reaches a callee signed, which needs a wire change | migration doc, batches 24/24b/24c attempted and reverted |
| Six milestone-4 reds never root-caused | `21-begin-time-compile-sub.t` ("Failed to deserialize lexical `$?PACKAGE`"), `custom-declarator-naming.t`, `make-regex-frame.t`, `try-statement-backtrace-frame.t`, `regex-interpolation-backtrack.t`, `m-flag-module-spec.t` (11 -> 1 failing since) |
| `t/02-rakudo/long-int-literal.t` 8/33: dies compiling `-Ⅼ` (U+216C) with `Confused` | may have regressed in milestone 4's fix wave |
| `t/02-rakudo/03-cmp-ok.t` 6/7: `Method 'find_method' not found for invocant of class 'FooHOW'`; same mechanism as `custom-declarator-naming.t` | one bug, two files |
| Latent: `NqpTypeOps.resolveBigInt` indexes `kinds[unboxIntSlot]` unchecked; `BigIntSite` does not re-verify `rd.layout === layout` | milestone 5 task 3 minors |

**Perf, unexplained or noted**

| item | where |
|---|---|
| `slowEvals` 364 -> 976 on the plusquick road, every other dispatch counter identical, plusquick +3.5 % | milestone 5; assigned to this milestone's Task 7 |
| Build B (new stage0) 57 s slower than build A, 206 s -> 263 s, stage1 compiled by the artifact stage0 | milestone 4 task 4 observation |
| `DecontSite` never `miss()`es on a layout mismatch | milestone 5 task 3, explicitly a perf nit |
| The small-int cache knob `JESP_INTCACHE`, worth re-measuring now that surrounding costs are lower; mainline natives (a `my int` at file scope boxes on every read and write); a classlib histogram by op name; the never-null `curFrame` lockdown | truffle-only plan, "smaller, any time" |

**Process and tooling**

| item | where |
|---|---|
| Nothing runs the engine harnesses automatically; three rots stacked unseen before the merge found them. Wire `rxcheck`/`nqpcheck`/`rxdesc` into a gradle `check`-style task | engine-merge ledger |
| `evalserver-sweep.raku`'s in-script guidance is WRONG and should be rewritten: its `--chunk` default (`max(3, heap * 15 div 8)`) and its "lower `--chunk`" advice both date from the memory leak, which has been fixed for some time. See the global constraint above; the milestone 5 spec's "pass `--chunk=5`" note is superseded | user correction 2026-09-12 |
| Hazard H5: doc contents still cite pre-rewrite commit hashes; only `backup/pre-pr-stack-2026-09-11` keeps them resolvable | `docs/jvm-pr-stack.md` |
| Milestone 4 ruling r1, PARKED: `CallFrame.kt:420-425` and `:443-445` comments still say the save road gives the invocation count back, false since nqp `b3d75f993` | owed to the PR stack |
| `nqp/tools/templates/Makefile-backend-common.in:103,116,117` still reference `ASTNODES_*`, which `jvm/Makefile.in` no longer defines | milestone 4 task 2 |
| The `rakudo-j` precomp gap: `rakuast-suspend-precomp-deps.t` spawns `$*EXECUTABLE` without `-Ilib`; precomp is 13/14, and 14/14 with `RAKUDOLIB=lib` | known since milestone 3 |
| Registry test leaves `%hll_inlinability{regtest}` set | `nqp/t/jvm/16-op-registry.t` |
| Anonymous blocks have no names in backtraces; `<anon>` should be at least `anon_N` via RakuAST/QAST block naming | strict-campaign handoff |

## Gates

- After Task 0: `t/01-sanity` 25/25, nqp suite at its nine known reds.
- After Phase C: the same two, on the rebased trees.
- No full `t/` sweep in this milestone.
- Jar census stays clean: `raku tools/build/jar-census.raku
  nqp/build/jvm/share/lib/*.jar` must report every jar `unit.meta`-only,
  zero `.class`.

## Risks

| risk | handling |
|---|---|
| The clean build surfaces breakage from the two unbuilt encoder commits | in scope for Task 0; it is a finding, and repairing it is the task |
| A knob that helps the build costs runtime | adoption is per-site; both clocks reported for every adopted knob |
| A bad polyglot option costs eight minutes before failing opaquely | probe every option set through `NqpCheck` first (seconds) |
| The greedy order misses a pair that only wins together | accepted; the findings doc records the order so milestone 7 can revisit |
| The image build consumes the milestone | Phase B is time-boxed; "it would not build, and here is why" is a valid close |

## Done

Milestone 6 is closeable when:

1. A clean build at HEAD exists and its numbers are recorded as the
   baseline.
2. The knob sweep has run, the winning configuration is adopted at the
   three sites, and `docs/jvm-perf-findings-2026-09.md` carries the
   configuration table, the three clocks and the ranked lever list.
3. The spike has produced its recipe, its numbers or its reason, the
   written answer on `native`-trait signature immutability, and a
   recommendation.
4. Both trees are rebased onto their upstream mains, re-gated and
   pushed, and `docs/jvm-pr-stack.md` has rows for milestones 5 and 6
   and the engine merge.
