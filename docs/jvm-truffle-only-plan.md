# The Truffle-only plan, ranked (2026-09-08)

The direction is settled: everything in both the runtime and the
compiler becomes Truffle-based, no JAST-to-bytecode machinery remains,
and the engine toolchain is the only build. This is the ordered list of
what stands between here and there, with what each item unblocks. The
inventory it ranks is under Phase 5 in `docs/jvm-truffle-migration.md`;
the measurements are in `docs/jvm-jesp.md`.

Rules of the road (user directives, 2026-09-07/08): one compile per
change on the engine toolchain (check the artifacts: `raku
tools/build/jar-census.raku nqp/build/jvm/share/lib/*.jar` must report
every jar `unit.meta`-only, zero `.class`; the old sidecar check
`unzip -l ... | grep -c codeprograms` is history — there is no sidecar
since milestone 4, 2026-09-10), its
timings are the baseline for the next change; no bytecode-vs-engine
comparisons, no A/B arms; runtime-jar-only changes need no setting
compile at all. Baseline at the directive: CORE.c parse 270.5 s
standalone, `+` loop 82 ns, cold `t/01-sanity` 139 s at 4 jobs, warm
67-81 s.

## Position (2026-09-13)

Milestones 1-6 of the unit-artifact road are closed; the previous
position table (kept below as history) is unchanged for items 1-3 and
5-9. What the branch gained since the milestone-6 close (rakudo
`211f7ac21c` / nqp `41c294b02`, 2026-09-12), in the order it landed:

- **Item 4, second measurement (2026-09-12, "milestone 7 build timings"):**
  the tier policy now reaches `J_NQP_RR` too (rakudo `b62f083d75`), with
  the `-Xss512m` that driver never had; clean `make` 985 -> 922 s. BOOTSTRAP
  v6c at 412 s is the largest single compile in the build and has never
  been profiled; the tier knobs are worth 5.5 % on it because v6c
  *executes* a 55k-line BEGIN block as well as parsing it. One JVM for
  several setting compiles is blocked by process-global compiler state
  (`Package 'Mu' already has a method`, `Circular dependency compiling
  routine 'FALLBACK'`), a project rather than a knob.
- **The nqp suite back to 154/154 (2026-09-13, nqp `1e24c3e34`..`17b47d46e`):**
  `$*X` reads take the dynamic road unless the block declares the name,
  `getlexdyn`/`bindlexdyn` start at the caller as MoarVM does, a
  frame-free callee's bind failure resumes the dispatch it was entered
  from, lookarounds over group nodes, a continuation clone gets its own
  engine frame, two encoder refusals became compile errors, and the JVM
  builds no `NQPP5QRegex` (rakudo `0a2f4600e7` guards the slang in RakuAST).
- **Cold start, designed then measured (2026-09-13):** the lazy unit
  loading design (`docs/superpowers/specs/2026-09-13-jvm-lazy-unit-loading-design.md`,
  rakudo `1658840f07`, revision 1 in `d614e62313`) and its Phase 0.
  Phase 0 overturned the premise: artifact decoding was under 3 % of
  `nqp -e` and about 11 % of `rakudo -e`. The top cost was quadratic
  wire pool parsing (a fresh `BreakIterator` with `setText` per pooled
  string in `NqpWire` and `RxWire`), fixed by `GraphemeCursor` (nqp
  `f2407eff9`, runtime-only): cold `nqp -e` 1.92 -> 1.12 s, cold
  `rakudo -e` 3.64 -> 2.68 s, warm nqp suite 340 -> 186 s, warm
  `t/01-sanity` 105 -> 56 s. Per-stage load timers ship behind
  `NQP_UNIT_LOAD_STATS=1` (nqp `dacbdd4fd`); the profile and exclusive-time
  tools are `tools/build/unit-load-profile.raku` and
  `unit-load-exclusive.raku` (rakudo `4a44ecd6e3`).
- **Milestone 7, Phase A closed 2026-09-15** (rakudo `9789a8d7bf` / nqp
  `4736905d0`): eight runtime levers measured one at a time on the rig
  (`tools/build/m7-rig.raku`); only three had an effect. A6' (a native
  static clone road) took dispatch misses 6815 -> 5661 and hits 125055 ->
  100697; 8c (one constant method handle per `getattr`/`bindattr` branch)
  made `raku-invoke`, the busiest root of a cold run, compile at all; 7b
  put the generated runners on the class path. Cold `rakudo -e` 2.504 s,
  cold `nqp -e` 1.192 s. Full table in
  `docs/jvm-perf-findings-2026-09.md`, "Milestone 7, Phase A".
- **Milestone 7, Phase B closed 2026-09-15** (rakudo `107eca63a3` / nqp
  `318558c2d`, plus nine v2 stage0 jars that stay UNCOMMITTED by user
  rule): the unit artifact is **version 2** -- a stored, mappable zip of
  five entries with three fixed-width index tables, a `BlockRecord` per
  block, lazy `StaticCodeInfo` bodies behind `ensureBody()`, one load
  road for files and in-memory units, site identity through the compile
  key, and an empty `unit.dispatch` table for Phase C to fill. Row `b`:
  cold `rakudo -e` **2.461 s**, cold `nqp -e` **1.160 s**, misses 5667,
  hits 100711, warm `t/01-sanity` 50 s -- all inside the series' spread,
  so **the format change is clock-neutral at the top level**. Per stage
  it is not: the whole decode stage is gone (133.8 ms on CORE.c, 19.3 ms
  on nqp.jar), `static-lex-values` 10.15 -> 0.20 ms, nqp.jar's
  `load-total` 662 -> 613 ms; the cost reappears inside
  `deserialize-program` and the SC read, where the record decode moved
  and where mapped slices now pay page faults. Artifacts are 8-10x on
  disk (CORE.c 5.9 -> 56.1 MB) because nothing is compressed any more;
  compression is Phase C's inbox. Build unchanged: make 854/861/863 s,
  CORE.c 283/280/281 s. Format doc: `docs/jvm-unit-lazy-loading.md`;
  numbers: `docs/jvm-perf-findings-2026-09.md`, "Milestone 7, Phase B".

**Milestone 7 closed 2026-09-16** (rakudo `6217a89e61` / nqp
`a837bf1bb`, plus nine v2 stage0 jars that stay UNCOMMITTED by user
rule). The milestone was "first execution", and it ran in three phases:
**A** measured ten runtime levers one at a time and landed three of them
(A7b, the generated runners on the class path, so the runtime tree's
`@TruffleBoundary`s are real; A8c, one constant `MethodHandle` per
attribute-cache branch, which made `raku-invoke` -- the busiest root of
a cold run -- compile at all; and A6', a native static clone road, which
took dispatch misses 6815 -> 5661); **B** rewrote the unit artifact as
**version 2** -- a stored, mappable zip, a `BlockRecord` per block, lazy
`StaticCodeInfo` bodies, one load road, site identity through the
compile key, and an empty `unit.dispatch` table -- clock-neutral at the
top level and structural underneath; **C** filled that table: both
builds run one training pass of the trivial program, and every site now
restores its recorded dispatch programs at its first miss instead of
running the dispatcher's guest code. On the program the build trains,
`recorded=` falls **4723 -> 195** and `hits=` **80298 -> 13292**. Rig
row `close`: cold `rakudo -e` **2.247 s** (from the milestone's 2.68 s
baseline, -16 %), cold `nqp -e` 1.198 s, misses 4931, hits 35512, with
the verify gate at `mismatched=0` over the nqp suite and `t/01-sanity`
and `staleSchema=0` on a cold run. CORE.c is unchanged at 296 s: this
milestone bought first execution, not compile time. **What it left:**
lazy-loading phase 2 (SC demand deserialization), the compression
decision (presented with numbers, the user's call), training's ~1 %
run-to-run variation and what it costs reproducibility, the empty A7
promotion list, the warm-clock question, one new red (`t/02-rakudo/closure-static-clone.t`, not
Phase C's doing -- it fails with `NQP_DISPATCH_PERSIST=off` too), and the
suite clock itself: the close's whole-`t/` run lost its server to the
server's own 9 GiB `MemoryMax` cap (the kernel's cgroup OOM killer, after
55 minutes, at file 310 of 482) and is recorded as **not gathered**
(`docs/jvm-full-suite-run-2026-09-16.md`). Full table:
`docs/jvm-perf-findings-2026-09.md`, "Milestone 7: the close".
**Next: milestone 8, an `Assumption` per STable.**

**Milestone 8, Phase A landed 2026-09-16** (rakudo `dd60f647e0` / nqp
`055e14ae9`): the type state. An STable's mutable facts -- method cache,
v-table, type-check cache, container/invocation/boolification specs, HLL
owner and role -- moved into an immutable `TypeState` with one Truffle
`Assumption`; writers publish a complete successor state, and every sited
op, every dispatch guard on all three roads and every folded dispatch
program tests the assumption of each state whose facts it trusted, so a
republish re-resolves instead of folding a stale fact. Gates: nqp suite
156/156 (195 s), `t/01-sanity` 25/25 (45 s), `make` exit 0 with no
recompile on an up-to-date tree (2 s; the phase's own full build was
855 s), `t/02-rakudo/type-state.t` 4/4, verify `mismatched=0`. **Row `a`
is a no-op clock**: cold `rakudo -e` 2.290 s and cold `nqp -e` 1.190 s
against the close's 2.247 / 1.198, misses 4933 and hits 35541 against
4931 / 35512 -- inside the series' spread on both sides, so the
dependent-load risk did not show. **The storm baseline says there is no
storm**: on a cold `-e ''` (`engine.TraceAssumptions`) `publishes=7460`
invalidate installed code four times -- two `validRootAssumption`, two
`nodeRewritingAssumption` -- and **none of the four is a `TypeState`**, the
type states all publishing before anything they touch is compiled; a test
written expressly to republish twice produces six type-state
invalidations out of 63. **After the fix wave** (rakudo `77ec6d01b3` / nqp
`93851fbce`) the same cold run reads `publishes=14858` -- the reader's new
republish per deserialized STable, roughly doubling the count -- with the
same **4** invalidations of installed code and still **none** of them a type
state. Two findings carried forward: a Rakudo-side runtime edit
costs a full setting recompile (`Makefile:320` makes `$(RUNTIME_JAR)` a
hard prerequisite of `rakudo.jar`; the Makefile was deliberately not
changed -- the user's call), and `dedicatedClasslib` is a third promotion
road, engine-only and without an encoder row. **Phase B (the promotion
campaign) is next.**

**Milestone 8, Phase B parked at row b2b; Phase C closed 2026-09-19**
(rakudo `ebffa026a4` / nqp `dd159b2a7`; ledger
`docs/superpowers/plans/2026-09-18-jvm-milestone-8-phase-c.ledger.md`).
Phase B landed batch 1, the typed classlib road (row b2a) and the run0
split (row b2b: CORE.c 243-245 s) and was parked there with plan B (rows
b2c, b2d) and three items open. Phase C is lazy-loading phase 2: format 12
halved the SC blob (CORE.c 28.2 -> 13.5 MB, the setting jar 56.4 -> 41.7
MB) and a demand reader finishes SC entries on first reference. Cold
`rakudo -e` 2.361 (c0) -> 2.301 (c1) -> **2.273 s** (c2), cold `nqp -e`
1.264 -> 1.220 -> **1.183 s**; the c2 step alone is inside the run-to-run
spread, and the SC work of a cold run (load plus demand, 266.8 ms) is level
with c1's eager read. **The exit finding:** after `-e 'say 1'` CORE.c has
150176 of its 276157 objects finished (54.4 %), above the spec's threshold,
so a C3 (the code object carried in the serialized code-ref table,
attached on first `getcodeobj`; compiler-side, one full build) is proposed.
CORE.c compile 231 s (one compile). Numbers:
`docs/jvm-perf-findings-2026-09.md`, "Milestone 8, Phase C". **The two
decisions that are the user's:** whether to brainstorm the C3, and Phase
B's plan B against the milestone close.

| item | state on 2026-09-13, cold start updated 2026-09-15 |
|---|---|
| 1 plain call | unchanged: partial, paused (per-call `Object[]`, mainline OSR shape) |
| 2 language id | unchanged: partial, paused (slice 2: hllbool, box types, hlllist/hllhash) |
| 3 calling convention | unchanged: partial, paused (`NQP_CODE_NOFRAME` off, dispatch blocks deferred) |
| 4 compiler workload | **measured twice, partly landed**, and milestone 7 closed the *execution* half rather than this one. Tier policy + one compiler thread on every setting compile and on `J_NQP_RR`: CORE.c 434 -> 297 s, clean make 985 -> 922 s; the close's `make` reads CORE.c **296 s** and the whole build 888 s, so milestone 7 moved this item **not at all**, as designed. Ceiling found: guest compilation is at most 17.5 % of a CORE.c compile. Milestone 7 closed two of the eight items it inherited (the `raku-invoke` bailout half of item 1 via A8c, and the boundary-visibility half via A7b) and left the rest, including the empty A7 promotion list and the in-build stage `JavaExec` tasks still on the boot class path; v6c unprofiled (375 s here, the build's largest single compile); setting compilation not idempotent |
| 5-9 | DONE, unchanged (milestones 1-5) |
| cold start (outside the nine) | **milestone 7 CLOSED 2026-09-16** (rakudo `6217a89e61` / nqp `a837bf1bb`). Phase 1 of lazy loading landed as Phase B (artifact v2, the mapped store, lazy bodies, site identity) and is clock-neutral by design; Phase C filled the dispatch table from a training run in both builds, and that is where the clock moved: cold `rakudo -e` **2.68 -> 2.247 s**, `recorded=` 4723 -> 195 on the trained program, hits 100711 -> 35512. **Phase 2 (SC demand deserialization) is what remains of the lazy-loading spec.** Left open at the close: the compression decision, training's ~1 % run-to-run variation (artifacts are no longer reproducible byte for byte), one new red (`closure-static-clone.t`), and the suite clock, not gathered because the sweep's single server wedged at file 310 of 482 |

**Against the north star.** `docs/jvm-truffle-migration.md` is at its
end state except for two entries of its Phase 5 inventory: the calling
convention (item 3 here) and `Ops.kt` reached across a boundary from the
engine (items 1-2 plus the `@TruffleBoundary` pattern above). Everything
else that document set out to delete is gone. The measurable proxy for
the whole direction is the suite clock: the whole `t/` suite under 30
minutes on one warm server (user rule 2026-09-12), last measured at
6039 s for 420 files at the milestone-5 close and **not re-measured since
the wire fix**, which cut the warm sanity run by 47 %. NFG on
TruffleString stays parked behind that gate (its checklist is `t/spec`).

**The order from here (proposed 2026-09-13, cheapest and most decisive
first):**

0. Hygiene before code: both branches are unpushed (rakudo 7 commits,
   nqp 9 ahead of `ab5tract`); rakudo owes 145 upstream commits (57 at
   the milestone-6 close), and they touch `src/Raku/Grammar.nqp`,
   `src/Raku/Actions.nqp`, four `src/Raku/ast/*.rakumod` files and three
   `src/core.c` files this branch also changed, so the rebase gets
   harder every day it waits. The gates it needs are cheap now (nqp
   suite 186 s, `t/01-sanity` 56 s, both warm). Also: two stray untracked
   scripts under `tools/build/` (`t3b-repro.raku`, `t3b-wait.raku`) and
   the log files at the worktree root.
1. **Measure the suite clock once**, whole `t/` on one warm server
   (`evalserver-sweep.raku '--chunk=*'`), on the post-wire-fix runtime.
   That number is the distance to 1800 s and decides how much of the
   next work is cold start versus warm throughput. With it, one JFR of
   the server during a single `t/` file: Phase 0 profiled cold runs only,
   and the eval server rebuilds every table and deserializes every SC
   per run (`UnitLoader.prime` caches parsed records only), so the warm
   path has its own unprofiled repeat work.
2. **Profile below the two unprofiled cold rows** (CORE.c load block,
   deserialize programs) with JFR stack filtering or `NQP_CODE_WHY` on
   the named blocks. Minutes, not hours, and it decides item 3.
3. Then rank, on those numbers, between (a) the `@TruffleBoundary`
   survey (milestone 7 item 1: runtime-only rebuild, runtime performance,
   the side the user weights higher), (b) cross-run sharing in the eval
   server (out of the spec's scope today, but the direct suite-clock
   lever if step 1's JFR shows per-run rebuild), and (c) the lazy-loading
   phases 1-2 as designed (a format change plus a stage0 regeneration,
   about 535 ms cold). Recommendation: (a) and (b) before (c); (c) only
   if step 2 shows decoding and tables dominate what is left.
4. Items 1-3 resume after that, as the migration document's remaining
   inventory; item 4's other inherited entries (size refusal, deopt
   churn, decont pinning, root names) ride along with (a).

**Update, 2026-09-13 evening (steps 0 and 2 of the order above done; step 1
running).** Step 0: both branches pushed; rakudo rebased onto upstream main
(164 commits over it; one conflict, the P5Regex slang guard moved into
upstream's new `standard-slangs` table; one setting fix, `$*COLLATION`'s
registration guarded `#?if !jvm` because Collation.rakumod is JVM-excluded
and upstream's streamlined dynamic-variable table registers it in
Process.rakumod; `RAKUDO_DUMP_UNDECLARED=1` now names the symbols behind
an unrenderable X::Undeclared::Symbols); clean make green, CORE.c parse
232.9 s (231.7 before the rebase). Step 2, the profile below the two
rows, is Revision 2 of the lazy-loading spec: **the CORE.c load block is
guest execution, not loading** — the mainline runs 1207 package bodies
once each and about 4600 dispatch misses inside it each run a dispatcher
program cold (`raku-invoke`, the method-call dispatchers, ~1400 each) plus
1148 `Block.clone`s; the lazy phases 1-2 cover decode + SC + tables, about
21 % of the cold start, and the larger lever is the dispatch miss (fewer,
cheaper, or persisted per call site in the artifact). The ranking in
step 3 waits for step 1's suite clock, running on the rebased build.

**Update, 2026-09-13 night (step 1 done; step 3 is a recommendation, to
be decided in a brainstorm with the user, not here).** The suite clock:
whole `t/`, 427 files, one warm 8 GB server, **5078 s** against
milestone 5's 6039 s (-16 %); 2.8x from the 30-minute rule; 23 red = 21
of milestone 5's 22 plus two tests upstream added this week; no
regression. A warm-server JFR mid-sweep put per-run loading at 4 % of
the server's time (eval-server cross-run sharing is struck) and the rest
in the DSL interpreter, the `NqpOps.classlib` boundary road and the
dispatch cold path. Recommendation for step 3, from both clocks: a
"first execution" milestone ahead of the lazy-loading phases — the
dispatch miss (about 6800 per cold start, each an interpreted dispatcher
run plus CHM-heavy record/realize: fewer, cheaper, or persisted per call
site in the artifact), the classlib boundary and the `@TruffleBoundary`
survey (milestone 7's inherited pattern), the stub road and its
method-handle spinning; then lazy phases 1-2 for the remaining ~0.55 s
of cold start (they do not move the suite clock); eval-server sharing
dropped. Cheap and independent: presize the SC reader's maps. The
findings are Revision 2 of the lazy-loading spec.

**Update, 2026-09-15 (milestone 7 Phase A closed).** Ten levers were
measured forward-only on the rig (`tools/build/m7-rig.raku`), and the
honest headline is that only one of them moved a counter: cold
`rakudo -e` went 2.502 -> 2.504 s from base to the closing row a6 with
dispatch misses 6815 -> 5661 and hits 125055 -> 100697, cold `nqp -e`
1.135 -> 1.192 s, and warm `t/02-rakudo` ran 3204 -> 3202 s over the
comparable base..8c (the ledger's row `a8`) series (best 3153 at a5;
a6's warm number was not gathered — the box was on battery and it was the first sweep after the
rig's precomp-cache clear). Three things landed: **7b**, which moved the
generated runners' runtime jars off `-Xbootclasspath/a` so the
runtime-tree `@TruffleBoundary`s are real under every nqp runner; **8c**,
which gives each attribute-cache entry its own branch with a constant
`MethodHandle`, so `invokeExact`'s type check folds, the JDK's
wrong-method-type message construction leaves the graph, and the three
permanently bailing roots — `raku-invoke` among them, the busiest root of
the whole cold run at 2546 entries — compile instead of running
interpreted (`opt failed` 3 -> 0); and **A6'**, the static clone road,
which is where the -1154 misses and -24k hits come from. Struck, each
inside the clocks' own spread and each kept in the tree because it cannot
regress: A1 (presized SC maps), A3 (dispatcher callbacks through the unit
road), A4 (stub-road fast path), A5 (record and realize off the hash
maps) and A7 (the classlib and targeted boundaries, with
`NQP_CLASSLIB_INLINE=1` left as the A/B); A2 claimed no number and
delivered the misses histogram the phase was steered by; A8 was struck by
its own spike, which showed four of the five hot dispatcher roots already
compiling 22-42 % of the way through their traced entries and every
first-tier threshold below the default 400 costing cold start in every
round (+455 ms at 50, +691 ms at 10); and A6 as specified was struck on a
false premise (`BOOTSTRAP.nqp` defines `Code.clone` and `Block.clone`, so
the compile-time `clone` test never matched) and replaced by A6'. The
phase also changed how it measures itself: from a6 on, a lever's row is
the two cold clocks plus warm `t/01-sanity`, the gates are the nqp suite
and `t/01-sanity`, and the `t/02-rakudo` clock is a phase-close
measurement — the user's rule of 2026-09-15, "stop measuring everything
to such a low granularity", with its amendment that a failed or throttled
benchmark is recorded as not gathered and taken at the next point the
plan already measures, never re-run for its own sake. Full table and the
Phase B inbox: `docs/jvm-perf-findings-2026-09.md`, "Milestone 7, Phase A:
the runtime levers". Phase B (artifact v2 + lazy tables + the empty
dispatch entry) is next; its plan is written from the a6 row.

Targets: keep cold `nqp -e` under 1.0 s (0.12 s away); cold `rakudo -e`
under 2.0 s stays the direction, not the done-criterion of any single
phase, since the spec's phases alone cannot reach it.

**Milestone 8, decided 2026-09-14 (user):** an `Assumption` per STable — the
object model giving compiled code constants to fold (method cache, type
check, container spec) and invalidating them on change — becomes
milestone 8, or at least a piece of it, after milestone 7's Phases B and
C. The likely second piece is the hot-op promotion list milestone 7's
Phase A ledger carries (ops on the classlib road becoming specialized
nodes). Not started; brainstormed when milestone 7 closes.

## Position (2026-09-12) -- history

Where each item stands with milestone 4 of the unit-artifact plan closed
by its fix wave (2026-09-11) and **milestone 5 closed 2026-09-12**: the
JVM backend generates no class at run time and ASM is gone from the build
(item 9). Item 4, the compiler's own workload, is next, starting with the
perf measurement session:

| item | state |
|---|---|
| 1 plain call | partial, paused: sited sink and frame-free outer reads landed; the per-call `Object[]` and the mainline OSR shape open |
| 2 language id | partial, paused: HLL-simplification slice 1 landed (hllize off `%hll_ops`); slice 2 (hllbool, box types, hlllist/hllhash) open; diamond 7 re-validation deferred behind it |
| 3 calling convention | partial, paused: frame-free blocks (phase A) landed knob-gated, `NQP_CODE_NOFRAME` off (it breaks the CORE.d compile); dispatch blocks deferred |
| 4 compiler workload | not started; the CORE.c parse regression (206 -> 389 s) lives here. Mechanism (profile 2026-09-07, census 2026-09-09): the compiler's own blocks now run as engine programs, so run-once code pays the DSL interpreter (2% -> 18% of samples) and Truffle compiles it on ~5 cores (61% + 14% JVMCI). Levers, cheapest first: tier policy for compile-time units; Oracle GraalVM's auxiliary engine cache (the artifact road makes units stable); per-node interpreter overhead; items 1-3; the JAST stage is gone as of milestone 4. **Milestone 4's fix wave landed 2026-09-11 and both its gate regressions are fixed; item 4 is next (user, 2026-09-09), starting with the perf measurement session in `docs/superpowers/plans/2026-09-10-perf-measurement-session.md`. The `is_inlinable` regression that would have invalidated every runtime number is repaired (nqp `47697ca29` + rakudo `548dc2544d`), so the measurement session must run on a build made at or after those -- anything measured on the milestone-4 jars was measured on a setting that never lowered native arithmetic**; the revised rule: a compile-time cost is acceptable only paired with a measured, significant runtime win |
| **5 reflection-free unit** | milestone 1 DONE 2026-09-09: nqp stage2 as artifacts (nqp `e2628a882` after the final-review fix wave; gate ran at `57460ccd7`), all 21 stage2/share-lib jars `unit.meta`-only (zero `.class`), t/nqp 115/115 through `nqp-j-gradle` (113/115 from the rakudo root: 019-file-ops and 063-slurp are cwd-relative); clean build 273 s, suite 487 s at 3 jobs; post-completion gate GREEN 2026-09-09 (Rakudo builds and runs on the artifact nqp, `t/01-sanity` 25/25): see item 6. **Milestone 2 DONE 2026-09-09** (nqp `da1f5088a`): a runtime compile under `NQP_UNIT` (script, `-e`, EVAL, BEGIN-time unit) is a record built in memory and loaded as a `ProgramUnit` with no class definition; `ProgramUnit` answers `lookupCodeRef(cuid)`; see item 6. **Milestone 3 DONE 2026-09-10** (nqp `30e849e3c`, rakudo `a22eb40b73`): the encoder and the record road are the defaults, the knob is gone from the compiler, and every jar Rakudo builds is a `unit.meta`-only artifact entered through `UnitMain` -- 16 Rakudo jars and 11 nqp jars, zero `.class`; see item 6 for the numbers. **Milestone 4 code complete 2026-09-10, gate open** (nqp `55bdee5b7`..`e270f070d`, rakudo `670c3645b0`..`09f349adda`): the reflective road is gone from the runtime, not merely unused -- `CompilationUnit` no longer reflects over `@CodeRefAnnotation` methods into method handles, `getCodeRefs()` is non-null `Array<CodeRef>` for every unit, and the only `CompilationUnit` subclasses left are `ProgramUnit`, the hand-written `KnowHOWMethods`, and `AdaptorUnit` for Java interop; see item 6 for the numbers |
| **6 unit artifact, no class file** | milestone 1 DONE 2026-09-09: nqp stage2 as artifacts (nqp `e2628a882` after the final-review fix wave; gate ran at `57460ccd7`), all 21 stage2/share-lib jars `unit.meta`-only (zero `.class`), t/nqp 115/115 through `nqp-j-gradle` (113/115 from the rakudo root: 019-file-ops and 063-slurp are cwd-relative); clean build 273 s, suite 487 s at 3 jobs; milestone 2 DONE (below), milestones 3-4 (Rakudo units + the deletions, stage0) open. **Post-completion gate (2026-09-09): GREEN.** Rakudo builds and runs on the artifact nqp; `t/01-sanity` **25/25** at 2 jobs in 210 s. Two blockers were found and fixed, neither of them an artifact/class-road crossing. (a) *Build entry point*, rakudo `a5f9ef3d80`: the Makefile's `J_NQP_RR` (`tools/templates/jvm/Makefile.in`) starts a JVM directly and ended on main class `nqp`, which an artifact `nqp.jar` no longer has (`Could not find or load main class nqp`); it now enters through `org.raku.nqp.runtime.unit.UnitMain <nqp.jar>`, nqp `15c20930c`'s entry, correct on either road. (b) *custom_args*, nqp `e1c29714e` + `2035d43e2`: the four `use`-ing sanity files died in one CORE.c program with `nqpp: unknown tag 11142 at 79 of 1060 words` (reproducer `./rakudo-j -e 'say("abc".subst(/b/,"x"))'`). Wire layout was innocent -- encoder, `NqpWire.java` and reader agree word for word on P6BINDSIG/P6TRYBINDSIG (1 word each) and on the `PARAMS 0 -1 0` header (4 words). `patch_params` spliced that four-word header OVER the one-word placeholder without shifting the positions recorded in `%e<nested>`, so every deferred qbid was written three cells early, onto a neighbouring tag (11142..11145 sat on a STMTS tag and three CODEREF tags whose real slots 82/84/86/88 were still 0). Behind it, a second one: the PARAMS reader re-made the extra-named rejection for a header that declares no parameters, so a custom_args block refused every named argument its Binder exists to bind (`Unexpected named argument 'g'`); `n == 0 && accepted == -1` now suppresses it. Both fixes keep the wire additive and unchanged. Timings for the full build on the fixed toolchain (from the top, after `Configure.pl` cleaned the jvm products): `make` 1173 s; nqp `clean buildJvm` 285 s. **Milestone 2 DONE 2026-09-09** (nqp `da1f5088a`, plan `docs/superpowers/plans/2026-09-09-jvm-unit-artifact-milestone-2.md`): under `NQP_UNIT` every unit takes the road -- a jar-bound unit with an output is written, anything else is built in memory by the `jvm-build-unit` syscall (`UnitWriter.record()`) and loaded by `loadcompunit` as a `ProgramUnit`; a record compiled while a compilation is under way is retained in `GlobalContext.inMemoryUnitRecords` and embedded under `nested/` by the parent's writer (the milestone-1 refusal is gone); the encoder's four splice-and-shift sites are one `splice_code`. **Deviation from the spec (user, 2026-09-09):** the record road stays behind the knob, because Rakudo builds and runs on the class road until milestone 3; the spec's deletions (string-constant road, its size gate, `ByteClassLoader`'s define road, nested `.class` embedding) are milestone 3's closing item. Gate: `NQP_UNIT=1 clean buildJvm` 296 s, 11/11 share-lib jars `unit.meta`-only; t/nqp on the record road **115/118 in 381 s** (baseline 487 s) -- the three FAILs are encoder refusals the class road hid behind per-block fallback (059/067 `withy general`, 084 `labeled control`; strict-campaign items, runtime-compile side); Rakudo `make` EXIT=0 1274 s, `t/01-sanity` **25/25** in 214 s; Rakudo `-e` with BEGIN and EVAL runs as three records under the knob; a Rakudo module precompiles as an artifact under the knob (its BEGIN closure is re-pointed, so no nested unit: CORE.c's four come from another shape). Open for milestone 3: the record-road mainline frame loses its filename in backtraces; `$*UNIT_FALLBACKS` is a constant 0 scaffold; `--target=jar` without `--output` dies in HLL::Compiler's result dumper on either road (pre-existing). **Milestone 3 DONE 2026-09-10** (nqp `da1f5088a`..`30e849e3c`, rakudo `5ae25a8d3c`..`a22eb40b73`; plan `docs/superpowers/plans/2026-09-09-jvm-unit-artifact-milestone-3.md`, its ledger and reports beside it). Four pieces. (a) *The last refused shapes*, nqp `c872c83af`: exit-handler blocks, `withy` general, labeled control, and `for :label` on the additive wire op `FORLOOPL = 35`. (b) *The flip*, nqp `388173781`..`e5f2b3840` + rakudo `08a997dc2b`: the encoder and the unit road are on by default (`NQP_UNIT` is gone), the generated runners and the eval server enter through `UnitMain <unit jar>`, and a record-road mainline frame carries its file in backtraces again; two flip regressions were fixed in the encoder (a `BVal` naming a block of the same tree; `with`/`without` over a native condition, which broke every `use Test`). (c) *The gaps the first t/ sweep found*, nqp `171d37508`..`8bab02391`: sized and unsigned natives, the unnamed chain link, suspendable dedicated ops with typed tokens (additive wire op `OPCALLT = 36`), an empty-message NPE, a sized `uint` attribute -- 7 of 8, the eighth parked below. (d) *The compiler-side deletions*, nqp `30e849e3c` + rakudo `a22eb40b73`: item 8. Gate on that toolchain, sleep suppressed (this is the timing baseline): nqp clean build 222 s; `make` 1154 s from the top (rakudo.jar 171 s, BOOTSTRAP v6c starts 200 s, CORE.c 594 s to 1069 s = 475 s, CORE.d 1069 s, CORE.e 1096 s); t/nqp 118/118 on the unit road; t/01-sanity 25/25 in 161 s; precomp 14/14; t/03-jvm + t/10-qast 2/2; all 16 Rakudo jars and all 11 nqp jars `unit.meta`-only; CORE.c carries 4 nested units (8 `nested/` entries). t/ ran twice through the eval server: sweep 1 (after the flip) 7858 s over two invocations on two 6 GB servers; sweep 2 (after the deletions) 7270 s -- the 7200 s ceiling after 59 of 60 chunks on three 4 GB servers, plus a 70 s tail -- with no new failures and 26 files fixed since sweep 1. t/spec did not run (user, 2026-09-09: not until t/ takes under two hours). Parked, real, narrow: a where-constrained parameter of a routine declared *and* called inside one `BEGIN` (two t/02-rakudo files red; evidence and the next lead in the milestone's `task-3b-report.md`). Carried into milestone 4: a suspended typed op resumes with the inner call's value instead of re-running the op (a `take` inside a `Proxy` `FETCH` inside a typed op); torn-frame `LEAVE` never runs on the JVM (both roads, pre-existing); the interop adaptors (item 9). **Milestone 4 CODE COMPLETE 2026-09-10, milestone NOT CLOSED** (nqp `55bdee5b7`..`e270f070d`, rakudo `670c3645b0`..`09f349adda`; plan `docs/superpowers/plans/2026-09-10-jvm-unit-artifact-milestone-4.md`, its ledger twin and eleven task reports beside it). Everything the milestone set out to build landed: the JAST-free driver (`Compiler.nqp` 6363 -> 1948 lines), `JASTNodes.nqp` and both `Ops.nqp` op tables deleted, **stage0 regenerated as 9 `unit.meta`-only artifact jars**, the whole runtime class road deleted (jast2bc, the sidecar and its `$!codeprograms` pass-through, `LibraryLoader`, `MemoryClassLoader`, `JarFileClassLoader`, `IndyBootstrap`, the indy budget, `setup_blv`, the per-block stub emission, `CompilationUnit`'s reflective half), the interop adaptors moved onto `AdaptorUnit` (item 9's adaptor half), and all three carried gaps fixed (torn-frame `LEAVE`, the resume value of a suspended typed op, and the parked where-in-`BEGIN` shape, which closed both parked t/02-rakudo files). Numbers: nqp clean build 214-263 s (baseline 222 s); `make` from the top 1185 s at Task 7 and 1103 s at Task 10 (baseline 1154 s), CORE.c 472-511 s (baseline 475 s); t/nqp 118/118; `t/01-sanity` 25/25; precomp 13/14, 14/14 with `RAKUDOLIB=lib`; t/03-jvm + t/10-qast 2/2; interop 30/30; **census 35/35 jars `unit.meta`-only, zero `.class`** (10 nqp share-lib, 9 stage0, 16 Rakudo). **What holds the milestone open is the t/ gate** (2026-09-10/11, on the final jars, 2 servers x 4g -- 3 x 4g exceeds the sweep's own budget at 20 g MemAvailable): eleven files are red that milestone 3's sweep 2 did not list, with two mechanisms named. (a) **`QAST::OperationsJVM.is_inlinable` lost its table.** `%core_inlinability` is now filled only by `map_classlib_core_op`; the ops that used to arrive through `add_core_op`/`map_jvm_core_op` -- `add_i`, `sub_i`, `mul_i`, `add_n`, `mul_n`, `if`, `while`, `list` -- answer 0, so RakuAST's `IMPL-INLINE-INFO` refuses to inline any routine that uses them and native arithmetic stops lowering. This is the mirror of the `supports_op` finding Task 1's review caught and fixed; `core_op_supported` was repaired, `is_inlinable` was not. Red because of it: `t/08-performance/22-rakuast-ct-dispatch.t`, `29-rakuast-attr-self-types.t`, `32-rakuast-native-param-bind.t` (all three green in milestone 3) and `t/02-rakudo/native-return-coercion.t`. It is a **runtime-performance** regression baked into the built setting, not a test-content failure. (b) **A multi-character `Str` range never terminates**: `("aa".."ac").elems` hangs (`"a".."e"` is fine, `"aa".succ` is fine), which hangs `t/02-rakudo/sort-element-kinds.t` and stalled both sweeps. Six more are red and not yet root-caused: `21-begin-time-compile-sub.t` ("Failed to deserialize lexical `$?PACKAGE`"), `custom-declarator-naming.t` ("Method 'find_method' not found for invocant of class 'MetamodelX::RakuLevelNameHOW'"), `make-regex-frame.t` (engine refusal: "qastnode walks the caller chain (curcode)"), `try-statement-backtrace-frame.t`, `regex-interpolation-backtrack.t`, `m-flag-module-spec.t`. Caveat on the comparison: milestone 3's list of 13 came from a chunk-attributed verify sweep whose infrastructure-attributed FAIL chunks were never resolved per file, so some of the six may have been red then too. Expected red, unchanged: the corekeys/settingkeys cluster (7 files), `t/05-messages/02-errors.t`, `t/08-performance/15-rakuast-native-metaop.t` and `36-rakuast-begin-compiled-remark.t`, `begin-called-block-routine.t`, `compiler-frontend-id.t`, `constant-anon-var-value.t`, `parse-target-match-tree.t`. The item-8 pair (`yada-trait-timing.t`, `begin-time-attributive-param-method.t`) is green, as Task 10 promised. **FIX WAVE 2026-09-11 -- both named mechanisms are fixed** (nqp `908134f3f`, `47697ca29`, `3b9615f4b`, `b3d75f993`; rakudo `548dc2544d`, `cd5799df09`). (a) `is_inlinable` now answers HLL override, then the classlib registry, then an explicit twelve-name `%core_noninlinable` table (the ops that carried `:!inlinable` on their deleted `add_core_op` call), and otherwise the same "the encoder has a row for it" rule `core_op_supported` uses; the five Raku ops that said `:!inlinable` through `add_hll_op` say it again through `set_hll_op_inlinability` in `src/vm/jvm/Raku/Ops.nqp`, which is correctness rather than speed (an inlined `p6return` or signature binder acts on the inliner's frame). Probed before the make and pinned by a new test, `nqp/t/jvm/16-op-registry.t`: `add_i`/`if`/`while`/`list`/`callmethod`/`defor`/`control`/`getlexouter` = 1, `call`/`callstatic`/`dispatch`/`syscall`/`handle`/`handlepayload`/`usecapture`/`savecapture`/`ctx`/`curlexpad`/`p6return`/`p6bindsig` = 0. `t/08-performance/22`, `29` and `32` are **green**. (b) The `Str` range hang was **not** CORE.c's build of `SEQUENCE` and not the compiler at all: the gather block's record and its wire program are structurally identical to a working precompiled module copy (879 wire words each, differing at 44 operand positions, every one a string-table, SC-handle, handler or qbid index), and the pre-Task-8 runtime hangs identically. The cause is `CallFrame`: the continuation save road called `leave()`, giving the frame's live-invocation count back and pointing `priorInvocation` at the frame being packed away, so a **second invocation of the same static frame** -- which `SEQUENCE`'s multi-character branch creates, because it builds each character position's range with the sequence operator, i.e. with `SEQUENCE` -- resolved its blocks' outer to the suspended outer invocation. The inner `$stop = 1` landed in the wrong frame's lexicals and its `until $stop` never saw it. `leaveSuspended()` now restores `tc.curFrame` and nothing else; the real exit still gives the count back exactly once. `("aa".."ac").elems` = 3, `sort-element-kinds.t` **green**, regression test `t/02-rakudo/nested-invocation-continuation.t` 6/6. (c) Also in the wave: a continuation-captured frame keeps its exit handler for its real exit (`gather { LEAVE ...; take 1; take 2 }` fires once, after the block ends, not at the first `take`), `UnitLoader` records a unit as loaded only after the load succeeds, the `$extra_ops` list names its three consumers, and the stale JAST/`add_core_op`/stage0-`NQP_CODE_RUN` comments are gone. **New timings, and these are the milestone's baseline** (the earlier 1103-1185 s / 472-511 s were taken with the inliner idle and are not comparable to anything): nqp `clean buildJvm` 253 s; `make` from the top **1142 s** (rakudo.jar 163 s, BOOTSTRAP v6c 193 s, CORE.c 585 s to 1052 s = **467 s**, CORE.d 1058 s, CORE.e 1084 s) against milestone 3's 1154 s / 475 s. Still open from the gate's eleven: `native-return-coercion.t` is **unchanged at 19/23**, so its four `dies-ok` failures were never the `is_inlinable` regression and need their own session; the other six were not root-caused in this wave |
| 7 encoder takes the refused shapes | nqp DONE (strict-green, nqp `ca71c19cb`); Rakudo census 2026-09-09: 10 op refusals (p6trialbind/p6setbinder, fixed, unbuilt), CORE.c 0; two shapes left: `custom_args` routine bodies (IN PROGRESS in the campaign session as of 2026-09-09 10:40, uncommitted in the worktree: wire ops P6BINDSIG 33 / P6TRYBINDSIG 34 bind the frame's own csd/args through Binder.kt inside the program, plus a custom_args header flag in the encoder) and exit-handler blocks (14 in CORE.c, not started). The raw/immediate unit wrappers are item 6's, not 7's. Census table: `docs/jvm-strict-campaign-handoff.md`. **Rakudo shapes DONE 2026-09-10**: `custom_args` routine bodies landed in the campaign (P6BINDSIG/P6TRYBINDSIG); exit-handler blocks landed with `withy` general, labeled control and `for :label` in milestone 3 (nqp `c872c83af`), and the milestone's first t/ sweep found and closed seven more runtime-compile refusals (nqp `171d37508`..`8bab02391`). One shape was parked, not fixed: a where-constrained parameter of a routine declared and called inside one `BEGIN`, a code-ref pairing fault in a dynamically compiled unit rather than an encoder refusal (two t/02-rakudo files red). **FIXED 2026-09-10** in milestone 4 (nqp `e270f070d`): `patch_params` was overwriting the parameter prologue's deferred code-ref slots, so a `BVal` in a parameter default or a `where` constraint resolved to the mainline (qbid 0); `yada-trait-timing.t` and `begin-time-attributive-param-method.t` are green. Item 7 is closed |
| 8 deletion | **DONE 2026-09-10** (compiler side nqp `30e849e3c` + rakudo `a22eb40b73` in milestone 3; runtime side nqp `55bdee5b7`..`e270f070d` + rakudo `670c3645b0`..`09f349adda` in milestone 4). Nothing in either tree is JAST-named any more and there is no class road: `Compiler.nqp` is a 1950-line unit driver over the QAST tree (was 6363), `JASTNodes.nqp` and `nqp/src/vm/jvm/NQP/Ops.nqp` are deleted, and with them the whole `jast2bc` package (`JASTCompiler.kt`, `JastClass.kt`, `JavaClass.kt`, `AutosplitMethodWriter`), `Ops.compilejast`, `loadcompunit`'s define branch, `MemoryClassLoader`, `JarFileClassLoader`, `LibraryLoader.java`, the `.codeprograms.lz4` sidecar with its reader and its `$!codeprograms` pass-through, the JAST method carrier and `@CodeRefAnnotation`'s reflective half, `IndyBootstrap` and the indy budget, the per-block stub emission (arity check, locals, postlude, save sites, `getCallSites`/`entryQbid`), `setup_blv`, and the class-file build plumbing including `JASTNodes.jar` from stage0 (9 bootstrap jars now, all `unit.meta`-only). This row used to end with "what deliberately stays: ASM and `ByteClassLoader`"; milestone 5 took both (item 9), so nothing stays. The `NQP_CODE_RUN`-presence caveat this row used to carry died with stage0's class-road compiler |
| 9 ASM outside jast2bc | **DONE 2026-09-12 (milestone 5)** (nqp `739ce7517`..`df564ddbb`, rakudo `b64c52cb1c`..this commit — the last pair of each range is the final review's fix wave; plan `docs/superpowers/plans/2026-09-11-jvm-milestone-5-rakuobject-layout.md`, spec `docs/superpowers/specs/2026-09-11-jvm-unit-artifact-milestone-5-design.md`, seven task reports beside its ledger). P6Opaque objects are `RakuObject`s on a static class family (six storage classes, `RakuObject4`/`4L`/`8`/`8L`/`16`/`16L`: inline reference and `long` fields up to the class's capacity, an overflow array after it) with a per-STable `RakuObjectLayout` holding the slot kinds, the specs, the flattened STables, the name-to-slot map, the auto-viv table and the unbox/delegate slots; the interop adaptor is `JavaCallout` over `MemberPlan`s built from method handles; **ASM is not a dependency and nothing generates a class at run time**. `ByteClassLoader`, `BytecodeVersion`, `storageForType`, `JavaCallinException` and the vendored `3rdparty/asm/` are all deleted, and the runtime jar directory is seven jars with no `asm*.jar`. Numbers on the milestone build: nqp `clean buildJvm` **256 s** (baseline 253), `make` from the top **1054 s** (baseline 1142), CORE.c **464 s** (baseline 467; parse 352.4 / optimize 36.6). Benches before → after (ns/op): plusquick 82.6 → 85.5, getattr 68.8 → 71.7, bindattr 57.1 → 57.7, getattr_i 107.3 → 86.0 (−19.9 %), decont 78.4 → 77.3, bigint+ 172.4 → 133.0 (−22.9 %), create 573.3 → 463.3 (−19.2 %). Layout stats after a CORE.c load: **2120 layouts, 0 variants, 0 reblesses**. Gates: `t/01-sanity` 25/25, `t/03-jvm/01-interop.t` 33/33 (8 in-source skips), `nqp/t/jvm/17-object-layout.t` **50/50**, `18-rebless-layout.t` 14/14, jar census 10/10 `unit.meta`-only, the nqp suite at its nine pre-existing reds, and `t/serialization/04-repossession.t` now runs at all (20/22 + 2 reader skips; it died at line 18 before). Closing t/ sweep: 420 files in 6039 s, 22 red — 2 fixed since milestone 4, 3 new. The one that looked like a regression, **unsigned native attributes** (`uint`/`uint32` throwing `ArrayIndexOutOfBoundsException` when boxed and dying with `nqpp: unknown tag 51` when written, `int`/`int32` unaffected), **was not a milestone 5 regression at all**: `TruffleEncoder.encode_args` patched the callsite argument flag with the wire RESULT type, and `$T_UINT` is 4, which is the callsite NAMED bit — so a positional uint was read as a named object argument and the reader ate the next word as a name-pool index, slipping the stream (hence the bogus tag). The encoder had been byte-identical since milestone 4, and milestone 4's gate had cleared the file as a cold-run artefact; the bug is older than the layout work. Fixed in nqp `7e7aaca61` (a uint ARGUMENT travels in the int slot; only a uint RESULT stays `$T_UINT`, where the unsignedness reaches the box), with `encode_args` now dying on any flag outside 0..3 so the next such slip cannot be silent. **Task 2's two kept UINT rulings are not implicated.** Gates after it: `t/02-rakudo/native-argument-snapshot.t` 9/9 and a new `t/02-rakudo/native-uint-attribute.t` 7/7. Known residual, pre-existing and needing a wire change: a uint above 63 bits still reaches a callee signed |

Item 7 ran ahead of 5-6 because the 2026-09-08 directive (all QAST via
Truffle) made zero refusals layer 1; it stops here because its last two
shapes and the wrappers all want the unit artifact to exist first.

**The sidecar, placed (side-run 2026-09-09) — HISTORY, gone 2026-09-10.**
Everything in this paragraph is written in the present tense of
2026-09-09. None of it exists any more: milestone 4 deleted the sidecar,
its writer, its readers and the whole class road with them; the unit
artifact carries the programs, byte-framed, inside `unit.meta`. Kept
because it explains why the artifact format frames by byte.
`<class>.codeprograms.lz4`
came in with nqp `404d9f898` (2026-09-02) when CORE.c overflowed the
class-file constant pool (71010 program strings against 65535, on top
of the 65535-byte cap per constant that the encoder's 60000-char gate
guards). It is held up by six sites: `Compiler.nqp` (`@*ENGINE_PROGRAMS`,
the index stub), `JASTNodes.nqp` (`JAST::Class.codeprograms`), the
jast2bc writer (`JASTCompiler.kt`, `JastClass.kt`, `JavaClass.kt`) and
the runtime readers (`CompilationUnit.loadEnginePrograms`,
`LibraryLoader`, `CodeEngine.codeRunIdx`). Its framing is by grapheme
count, an NFG accident that cost a reader bug and an O(n^2) first fix;
the artifact format must frame by byte. It is not removed on its own: it
is the seed of item 6, and the 2026-09-09 gate lift (`:sidecar`) already
treats it as the primary road, confining the class-file limits to the
runtime-compile string road, which item 6 retires too.

## The list

1. **Arguments in registers, which turned out to mean the plain call.**
   The loop bench's `+` and assign run on special roads and had hidden
   what an ordinary sub call costs: 462 ns and ~1 KB per call, none of
   it the argument arrays. Landed so far: the sink of a statement's
   value as a sited op (the value's `sink` was called through the
   generic method-dispatch road, building a descriptor, a string key and
   a frame per call: sub loop 462 → 239-249 ns), and outer lexical reads
   that no longer force a frame (the program gets its code ref; a block
   whose only lexical traffic is with its outers runs frame-free). Still
   open on this item: the `+` loop's own `Object[]` (~200 B/iter, not the
   thread-context store, not the catch handlers -- both tried), with the
   call node's own frame-arguments array and its argument profiling as
   the remaining suspect; and the mainline shape of the bench, which
   only ever compiles by on-stack replacement onto the interpreter's
   real frame. Measure by JFR allocation rate, never by the expansion
   tree's allocation count.

2. **A two-valued language id instead of `HLLConfig` identity.** The
   only languages that exist are `nqp` and `Raku`; NQP cannot go
   (RakuAST, the metamodel, the dispatchers and the bootstrap are NQP
   code). What diamond 7 tripped over was not a third language but a
   third config object: a bootstrap holds the compiler's and the
   compilee's `nqp` configs as distinct objects. Carry a two-valued id
   on each block in the wire header and on each STable as its owner,
   compare ids, and let the encoder hand the id as a constant to every
   op that today reads the language off `tc.frame` (`hllbool`, the box
   types, `hlllist`/`hllhash`, getattr's native boxing, the `hllize`
   site). Every same-language decision moves to encode time; the
   runtime check and the config-identity trap go; `%hll_ops` shrinks to
   the genuinely dynamic few; a whole class of "needs a frame" reasons
   disappears. It does not shorten the class-file inventory, which is
   why it sits here and not at the top: it is a prerequisite for
   retiring the frame, not the class file. `HLLConfig` stays as the
   per-language table.

3. **The calling convention.** `ArgsExpectation` (the engine's direct
   road is gated on `USE_BINDER`), `StaticCodeInfo.mh`/`mhResume`, and
   `CallFrame`'s argument storage. With arguments in registers (1) and
   the language static (2), what still forces a frame is a short list
   the docs already keep (`docs/jvm-truffle-calling-convention.md`);
   retire the method-handle invoke road and leave `CallFrame` as the
   reified-frame shim for introspection only.

4. **The compiler's own workload.** The last profile of a CORE.c
   compile: Truffle compiler threads 61% and JVMCI 14% of all CPU
   samples, the main thread 17%. The engine JIT-compiles run-once
   compiler code on about five cores for the whole compile. That is the
   compile-time problem, and it is a tier-policy problem, not a diamond:
   compilation thresholds and budget for code that runs a handful of
   times, plus the per-node interpreter overhead the sites added. It is
   parallel to 1-3 and can start any time; it is placed here because it
   is the largest lever on the number the user watches most, and because
   items 1-3 do not touch it.

5. **A `CompilationUnit` that maps block ids to code objects without
   reflection — DONE (milestones 1-4).** Every code object used to be a
   JVM method: the unit reflected over `@CodeRefAnnotation` methods into
   method handles and CodeRefs, and the engine's nested-block operation
   resolved through that table. All of it is gone; `getCodeRefs()` is a
   plain non-null array.

6. **A program-and-serialized-context artifact per unit, no class
   file — DONE (milestones 1-4).** The sidecar became the unit, and then
   the sidecar itself went. `--target=classfile` has no artifact form,
   every `blib/*.jar` and every stage jar is `unit.meta`-only,
   `LibraryLoader` is deleted, `ByteClassLoader` defines only the interop
   adaptors' plain class, stage0 is serialized programs + SC, and every
   runner enters through `UnitMain <unit jar>` rather than
   `CompilationUnit.enterFromMain`.

7. **The encoder takes over the refused shapes.** CORE.c 6% and
   BOOTSTRAP 11% of blocks still fall back to full bytecode: exit
   handlers, `raw`/`immediate` blocks, `custom_args`, the
   60,000-character program gate, ~90 bail sites. At zero refusals the
   QAST-to-JAST compiler has nothing left to emit but stubs.

8. **Deletion — DONE 2026-09-10.** As planned, in this order: the JAST
   layer (`Compiler.nqp` 6363 lines down to a 1948-line unit driver,
   `JASTNodes.nqp` and both `Ops.nqp` op tables deleted outright),
   `jast2bc` in full including `JASTCompiler.kt` and
   `AutosplitMethodWriter`, the program sidecar with its writer and its
   readers, `IndyBootstrap` and the indy budget, `LibraryLoader`,
   `MemoryClassLoader` and `JarFileClassLoader`, the build plumbing that
   assumed class-file output, and the stage jars — stage0 included, now
   nine `unit.meta`-only artifacts. This entry used to name two things
   that did NOT go — the ASM dependency and `ByteClassLoader` — because
   item 9's remaining half still needed them; milestone 5 took both, so
   the deletion is whole.

9. **ASM outside jast2bc — DONE 2026-09-12 (milestone 5).** `P6Opaque`
   objects are `RakuObject`s on a static family of six storage classes
   with a per-STable `RakuObjectLayout`; the interop adaptor is
   `JavaCallout` over plans built from method handles;
   ASM is not a dependency and nothing generates a class at run time.
   `ByteClassLoader`, `BytecodeVersion` and the vendored `3rdparty/asm/`
   are deleted. See the Position table's row 9 for the numbers and the
   gates, `RakuObjectLayout.kt`'s class comment for the layout itself,
   and
   `docs/superpowers/specs/2026-09-11-jvm-unit-artifact-milestone-5-design.md`
   for the design and its "Done" section.

## Smaller, any time

- The small-int cache knob (`JESP_INTCACHE`), worth re-measuring now
  that the surrounding costs are lower.
- Mainline natives: a `my int` at file scope is a lexical and boxes on
  every read and write; lowering mainline natives helps any loop
  written at file scope.
- A classlib histogram by op name, to attribute the remaining
  method-handle road.
- The never-null `curFrame` lockdown.
