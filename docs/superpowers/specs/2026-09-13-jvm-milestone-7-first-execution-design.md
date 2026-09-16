# Milestone 7: first execution (truffle-only plan item 4, continued)

Design, 2026-09-13. Approved in chat the same day, section by section.

Position: `docs/jvm-truffle-only-plan.md`, "Position (2026-09-13)" and
the order it proposes. Milestones 1-6 of the unit-artifact road are
closed. Milestone 6 handed over eight items under the pattern "slow
paths visible to the inliner" (`docs/jvm-perf-findings-2026-09.md`,
"What milestone 7 inherits, ranked"); the lazy-loading spec's
Revision 2 (`docs/superpowers/specs/2026-09-13-jvm-lazy-unit-loading-design.md`)
then found that the largest row of cold start is not loading but the
first execution of the setting's code, and that the warm suite clock is
the same shape. This milestone takes that finding as its spine and
absorbs lazy-loading phase 1 so the artifact format changes once.

## Goal

Cut what a block, a call site or an op pays the first time it runs,
on the two clocks that matter:

| clock | now (2026-09-13, rakudo `68e21e4ae9` / nqp `c17d93d27`) |
|---|---|
| cold `rakudo-j -e 'say 1'`, best of 5, stock runner | 2.68 s |
| cold `nqp-j -e 'say(1)'` | 1.12 s |
| whole `t/`, 427 files, one warm 8 GB eval server | 5078 s (rule: 1800 s) |

The largest row on both clocks is the dispatch miss: about 4600 inside
the CORE.c load block, 6815 in the cold run, each one an interpreted
run of a dispatcher program plus the Java record and realize, entered
through the stub road. Behind it: the classlib boundary road
(`NqpOps.classlib` is 17.7 % of the warm path's exclusive samples) and
method-handle spinning (7.6 % cold, 4.8 % warm).

The milestone also lands artifact v2 with lazy tables (lazy-loading
phase 1), which carries a per-site dispatch entry, so the format
changes once and stage0 regenerates once.

## User decisions (2026-09-13)

1. **The spine is first execution**: the dispatch miss, the classlib
   boundary road, the stub road, the `@TruffleBoundary` survey. Not
   the inherited compile-clock list on its own, not lazy loading on
   its own.
2. **Done-criterion: levers exhausted, both clocks re-measured.** Each
   named lever gets one forward-only measurement and is landed or
   struck; the two clocks are re-measured once at close. No numeric
   target is a pass/fail gate. Cold `rakudo -e` under 2.0 s stays the
   direction.
3. **The persisted miss is in scope from the start**, designed as a
   phase, sharing the v2 store with lazy-loading phase 1.
4. **Milestone 7 absorbs all of lazy-loading phase 1**: store, codec,
   lazy tables, eval-server mapping, the transition window. Phase 2
   (SC demand) stays in the lazy-loading spec.
5. **Order: runtime levers first, the format once, the persisted miss
   last.** Phase A's levers are runtime-jar rebuilds measured in
   seconds; Phase B changes the format and regenerates stage0; Phase C
   fills the entry Phase B reserved, sized by what Phase A left.
6. **Name: "first execution"**, the cost being attacked. The memory
   that carried "milestone 7" for the 2026-09-12 build timings was
   renamed `build-timings-2026-09-12`.
7. **A compile-only dependency on `truffle-api` in `nqp-runtime`, for
   the annotation alone.** `nqp/src/vm/jvm/runtime` has no Truffle
   dependency today and zero `@TruffleBoundary`; the targeted
   boundaries of A7 and inherited item 1 need the annotation in that
   tree. Nothing else in the runtime may use Truffle.
8. Standing rules carried over: forward-only, one compile per change
   (2026-09-08); subagents on Opus, Fable only after erroneous output
   (2026-09-11); runtime performance outweighs compile time
   (2026-09-07); every debug print env-gated; Kotlin, never Java;
   no `t/spec` until whole `t/` is under 30 minutes; never replace an
   eval server mid-sweep (`--chunk` = total file count); rebase at
   close, not at open.

## The code, as surveyed on 2026-09-13

Facts the design rests on, with locations after the rebase (rakudo
`68e21e4ae9`, nqp `c17d93d27`). Paths under `nqp/` are the nested nqp
working tree.

**The dispatch miss road.** One `EngineSite` per dispatch instruction,
built at wire-walk time
(`nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java:517-565`),
holding a `DispatchCallSite` and an `NqpDispatch.Cache`
(`NqpOps.java:824-836`). Replay is `NqpDispatch.kt:592-606`; a miss
(`:623-630`) calls `Dispatch.fallback` (`nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/Dispatch.kt:131-141`),
which records (`:264-349`): the dispatcher is looked up by name in a
`ConcurrentHashMap` (`DispatchRegistry.kt:39`) on every miss, the
delegation chain runs, each NQP-coded dispatcher (raku-invoke,
raku-meth-call, from `src/vm/moar/dispatchers.nqp`, compiled into the
JVM BOOTSTRAP) is entered as an ordinary block call through
`Ops.invokeDirect` (`Dispatch.kt:368-389`), the record compiles to a
`DispatchProgram` (`DispatchRecord.kt:477`) and installs at the site.
Helper sites are keyed by a string built per call (`Ops.kt:2806-2807`,
`:2850-2853`). **Nothing is persisted**: `DispatchBootstrap.resetAll`
(`DispatchBootstrap.kt:143-150`) empties every site at the start of
each eval-server run, and no unit artifact carries dispatch data.

**The closure road.** `IMPL-CLOSURE-QAST` (`src/Raku/ast/code.rakumod:214-224`)
emits `callmethod clone` over a WVal, wrapped in `p6capturelex`. The
encoder turns `callmethod` into a `lang-meth-call` dispatch
(`nqp/src/vm/jvm/QAST/TruffleEncoder.nqp:2933-2951`); `p6capturelex` is
a classlib op (`src/vm/jvm/Raku/Ops.nqp:88`). Raku's `clone` on a
Block resolves to `Mu.clone`, a proto with a `Mu:D:` multi
(`src/core.c/Mu.rakumod:1182-1188`), so every closure creation is a
method-call miss followed by a multi dispatch. At setting load that is
1148 distinct sites, one miss each, every run.

**The classlib boundary road.** Ops with no encoder row fall to the
registry (`TruffleEncoder.nqp:2550-2589`, `%CODE_CLASSLIB_OPS` in
`nqp/src/vm/jvm/QAST/Compiler.nqp:169-172`): 624 core ops (584 into
`org.raku.nqp.runtime.Ops`) and 40 Raku ops. A `ClassLibSite` resolves
a spread-and-typed method handle once (`NqpOps.java:897-928`) and
`NqpOps.classlib` (`:946-971`) invokes it with **no `@TruffleBoundary`**
and a fresh `Object[]` per call, so the 9.5k-line `Ops.kt` is
partial-evaluation-visible from every call site. The table road
(`NqpOps.run`, 383 ops) **is** annotated (`NqpOps.java:162-164`). The
census: `nqp/src/vm/jvm/runtime` 0 annotations, `nqp/nqp-truffle/src`
103.

**The stub road.** `ArgsExpectation.invokeByExpectation`
(`nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/ArgsExpectation.java:17-137`),
called only from `Ops.invokeDirect` (`Ops.kt:2965`), re-examines the
descriptor on every call although on the unit road every block has the
same expectation and the same entry body (`ProgramEntry.kt:25-45`,
`ProgramUnit.kt:34-39`). At load, `StaticCodeInfo` spins two bound
method handles per block for every block in the table, entered or not
(`StaticCodeInfo.kt:246-276`).

**The inherited chains, still where the findings doc put them.**
`ExceptionHandling.dieInternal` (`ExceptionHandling.kt:44-83`, the gated
print at `:47`, the 40-frame walk at `:53-64`); `VMArray.allocate`'s die
arm (`VMArray.kt:43`) under `NqpTypeOps.create` (`NqpTypeOps.kt:623`);
`getattr`/`bindattr` message construction (`NqpOps.java:1503`, `:1539`);
`decont` falling through to `decontSlow` without `miss(site)` when the
STable matches and the layout does not (`NqpTypeOps.kt:245-270`);
`AttrSrc.slow`'s single counter (`NqpDispatch.kt:160-172`);
`NFGString.atomsOf`'s `WeakHashMap` (`NFGString.kt:138-155`, reached
from `RxCursor.OfString` under `RxMatchRootNode.execute`).

**The dispatch model is data, not code.** `DispatchModel.kt`: a
`DispatchProgram` (`:411`) holds a descriptor, a guard list (`Guard`,
`:215-258`: `OfType`, `Concreteness`, `Literal`, `NotLiteralObj`,
`OfHll`), an `Outcome` (`:348-356`: `Value`, `InvokeCode`,
`InvokeSyscall`) and resumption levels (`:366-391`). Its object
references are STables, `SixModelObject`s, an `HLLConfig`, a `Syscall`
and a `Dispatcher`.

**The counters.** `NQP_DISPATCH_STATS=1` prints totals at exit
(`NqpDispatch.kt:556-580`): hits, misses, slowEvals, invokes, directs,
hits by kind. There is no per-dispatcher split.

## Task 0: the rig

The rig is one Raku script, `tools/build/m7-rig.raku` (tooling in Raku,
2026-09-09), run from the milestone's job directory; it refuses to start
with `NQP_DISPATCH_RECORD` set. Four numbers per lever, each recorded
with the lever's commit hashes (both trees):

1. Cold `rakudo-j -e 'say 1'`, best of 5, stock runner, with
   `NQP_UNIT_LOAD_STATS=1` so the per-stage rows are on the same line.
2. Cold `nqp-j -e 'say(1)'`, the same.
3. The dispatch counters on the cold rakudo run, extended in Task 0
   with a **misses-by-dispatcher histogram** (dispatcher name to
   count, top 20 at exit, under the same env gate).
4. Warm `t/02-rakudo` on one eval server, `--chunk` equal to its file
   count, wall clock and the red list against the milestone-5
   baseline for that directory.

**Revision 2026-09-15 (user, during Phase A, supersedes the 2026-09-14
revision):** a lever's row is the two cold rows and `t/01-sanity` warm
on one server, nothing else; the correctness gates are the nqp suite and
`t/01-sanity` as before; there is NO per-lever `t/02-rakudo` (neither as
a clock nor as a parallel gate) and NO re-take of a suspect row; the
whole `t/` clock runs once at the milestone close. Sensible benchmarks,
no additional gating of any kind.
Whole `t/` runs once, at close. CORE.c compile time is recorded
whenever a setting recompile happens anyway (A6, Phase B) and never
measured on purpose. Every benchmark run is a stock runner, never the
eval server (it exports `Compilation=false` to its children).

A training run (Phase C) is never a measured run.

## Phase A: runtime levers

Cheapest first, one forward-only measurement each on the rig; every
lever is a runtime-jar rebuild (`./nqp/gradlew -p nqp :nqp-runtime:jar
:nqp-truffle:jar syncRuntimeJars`, restart servers) except A6.
A lever whose measurement shows nothing is struck and its result
recorded; nothing is reverted to re-measure. A lever that regresses
either clock is reverted in a follow-up commit and recorded as struck
with both numbers.

- **A1. Presize the SC reader's maps** (`Object2IntOpenHashMap` and the
  `HashMap`s) from the header counts. Rehash and resize are 23 % of
  the reader's samples, about 2.5 % of the cold run. One file.
- **A2. Diagnostics that ride along** (inherited items 5-8), no
  measurement claimed: the misses-by-dispatcher histogram (Task 0);
  `decont` calling `miss(site)` on a layout mismatch as well as an
  STable mismatch so the site pins and appears in the counters;
  `AttrSrc.slow` split into a layout-mismatch counter and a null-slot
  counter; root names carrying the block id so the engine's
  `CompilationStatistics` stops merging distinct targets; the
  root-multiset analysis re-run by id.
- **A3. Dispatcher callbacks enter through the engine road.**
  `Dispatch.invokeCallback` enters an NQP-coded dispatcher through
  `Ops.invokeDirect` and the stub road; the callee has a call target
  already (`CodeEngines.materialize`), so enter it the way
  `NqpDispatch.enterEngine` does. Moves the record share (9-10 % cold,
  3 % warm) and `invokeByExpectation` (8 % cold, 3.5 % warm).
- **A4. Stub-road fast path at call time.** In `Ops.invokeDirect`, a
  `USE_BINDER` code ref with the shared entry body is entered directly
  with its descriptor, skipping `invokeByExpectation`'s re-examination.
  Small; measured with A3's counters.
- **A5. Record and realize off the hash maps.** The dispatcher is
  cached on the site after the first lookup (the name is a site
  constant); helper sites are keyed without building a string per
  call; anything else the record path's `ConcurrentHashMap` traffic
  shows in a JFR of the cold run.
- **A6. The static clone road.** In `IMPL-CLOSURE-QAST`, under
  `#?if jvm`, when `nqp::findmethod($code-obj, 'clone')` at compile
  time is Mu's own `clone` proto, emit `nqp::clone` of the WVal in
  place of the method call, still inside `p6capturelex`. Any other
  resolution keeps the method call. Removes the 1148 setting-load
  misses and one miss per closure-creation site in every test file.
  Needs a setting recompile (one `make`); goes last in Phase A and
  records CORE.c in passing. The behaviour of `Mu.clone(Mu:D:)` with
  no twiddles is verified against `src/core.c/Mu.rakumod:1188` before
  the change lands.
- **A7. The boundary survey, as one knob then repaired selectively.**
  `NqpOps.classlib` gets `@TruffleBoundary`, matching the table road,
  behind `NQP_CLASSLIB_INLINE=1` (which restores today's behaviour) for
  exactly one measurement on both clocks; then adopted with the knob
  removed. Ops that lose from the boundary (found by the same JFR and
  the warm run's red list) are promoted to sited nodes, the road the
  JESP diamonds built; the promotion list is recorded in the findings
  and may be empty. The 442-root chains are not on this road and get
  targeted boundaries in the runtime tree under decision 7: the die
  arm of `VMArray.allocate`, `dieInternal`, the message construction
  in `getattr`/`bindattr`; plus `NFGString.atomsOf` (inherited
  item 4). A `static final` hoist of the noisy-exceptions flag is the
  cheap complement, not a substitute.
- **A8. Dispatcher programs compiled early: a spike.** The six
  dispatcher blocks run thousands of times cold in the DSL interpreter.
  The spike answers, with `NQP_CODE_CALLSTATS=1`, whether they reach
  compiled code during a cold run at all, and if not, what the engine
  offers per root. Its output is a recommendation in the findings, not
  code; if it names a mechanism worth one runtime rebuild, that becomes
  A9 by ruling in the ledger.

Phase A closes with the rig once more on its last commit; that is the
baseline Phase B is measured against.

## Phase B: the format, once

Lazy-loading phase 1 as specified in
`docs/superpowers/specs/2026-09-13-jvm-lazy-unit-loading-design.md`,
tasks 1.1 to 1.6, carried over by reference and unchanged in
substance: the direct-field survey, the mapped store of stored zip
entries, the kotlinx codec over `ByteBuffer` slices, shells and bodies
behind `ensureBody()`, the process-wide store in the eval server, and
the transition (window build, stage0 regeneration, v1 removal, full
gate at each step). This spec records only what milestone 7 adds:

- **Site identity.** Every dispatch instruction gets an ordinal within
  its program, assigned where `NqpProgramBuilder` constructs the
  `EngineSite`, in wire order, so it is a function of the program text
  stored in the same artifact. A site's identity is (unit id, program
  index, site ordinal); the `EngineSite` carries it.
- **A fifth entry, `unit.dispatch`.** A count in the `unit.index`
  header and a fixed-width `(offset, length)` table like the others,
  one slot per (program index, site ordinal), so a lookup is O(1)
  without decoding. Phase B writes every slot empty. The record schema
  is fixed here (the "Phase C" section states it) so that Phase C only
  fills slots. An empty table is valid under any schema version, which
  is what lets stage0 regenerate once, in Phase B, and never again in
  this milestone.
- **Lazy tables close the stub road's load cost.** The two bound
  method handles per block are spun by `ensureBody()` only for blocks
  that are entered. This is A4's counterpart and needs no separate
  task.
- **Measurement.** The rig once on the v2 build; the per-stage rows
  expected to move are unit decode and build-table (about 11 % of the
  cold run before Phase A); SC read stays. CORE.c is recorded from the
  window build's setting compile.

Phase B does not do phase 2 (SC demand). Persisted programs address
SC objects by handle and index, the addressing phase 2 will need, so
nothing here forecloses it.

**Phase B: closed 2026-09-15** (rakudo `107eca63a3`, nqp `318558c2d`,
plus nine v2 stage0 jars that stay uncommitted by user rule). Everything
above landed: the mapped store of stored entries, the kotlinx codec,
shells with lazy bodies, per-block static lexical values, site identity
through the compile key, the empty `unit.dispatch` table sized by the
encoder's per-block count, stage0 regenerated once as v2, and the v1
reader deleted. Row `b`: cold `rakudo -e` 2.461 s, cold `nqp -e`
1.160 s, misses 5667, hits 100711, warm `t/01-sanity` 50 s -- all inside
the Phase A spread, so the format change is clock-neutral at the top
level while the per-stage rows moved as the spec expected (the decode
stage is gone; the cost reappears inside `deserialize-program` and the
SC read). Plan and ledger:
`docs/superpowers/plans/2026-09-15-jvm-milestone-7-first-execution-phase-b.md`
and its `.ledger.md`; the format:
`docs/jvm-unit-lazy-loading.md`; the numbers and the rulings:
`docs/jvm-perf-findings-2026-09.md`, "Milestone 7, Phase B". One
correction the phase forced on the letter above: a site's identity is
**not** (unit id, program index, ordinal) -- a unit id is
author-supplied and Rakudo builds five artifacts as `perl6`, which put
one unit's programs in another's place. It is (store name + unit id,
program index, ordinal), and the string is a live-process key only.

## Phase C: the persisted miss

**C0, the spike, first.** Two cold `rakudo -e` runs with the recorder
on: how many of the misses are persistable (every referenced object in
an SC), how many are structurally identical between the two runs after
normalisation, split by dispatcher. That sizes the expected gain and
lists the unpersistable classes before the writer is built. Its
findings may reorder the rest of Phase C; they do not remove it
(decision 3).

**Schema** (`DispatchSlot`, kotlinx, one per site slot): the site
identity; the descriptor by index in the unit's call-site table; up to
the site's program cap of `PersistedProgram`s, each the
`DispatchProgram` with every reference replaced by a stable name:
STables and objects by (SC handle, index), the HLL config by name, the
syscall by name, the dispatcher of a resumption level by name. Native
literals inline. A program is persistable only if every reference
resolves to an SC object; otherwise it is not written and the site
behaves as today.

**Producer: a training run in the build.** The compiler never executes
the code it compiles, so outcomes come from running. A runner mode
`NQP_DISPATCH_RECORD=<path>` records, for every site of every unit
named in the recording, the programs installed at exit; a Kotlin entry point in `nqp-runtime`
(`UnitDispatchWriter`), driven by the Makefile and by nqp's gradle build,
rewrites the named units' `unit.dispatch` entries in place. The
training program is the trivial one (`-e ''`), because loading a
setting or a module is itself the first execution under attack.
Rakudo's build trains nqp.jar, rakudo.jar and each setting after it
compiles; nqp's build trains its stage2 jars; stage0 stays
empty-tabled. Training is deterministic input to the build, not a
cache: a clean build always reproduces it.

**Consumer.** On a site's first miss, before `Dispatch.fallback`, the
site looks up its slot, realises each persisted program against the
current process's SCs (a program with an unresolvable reference is
dropped), installs them and replays. If no persisted program's guards
pass, the ordinary miss follows and the recorder (if on) sees a fresh
record. This rests on the invariant replay already rests on: a program
is valid whenever its guards pass. In the eval server, `resetAll`
empties the sites per run and each site re-arms from its slot on its
first miss, so the cross-run benefit needs no object shared between
runs.

**Verification.** `NQP_DISPATCH_PERSIST=off` disables consumption;
`NQP_DISPATCH_PERSIST=verify` records fresh at every first miss,
compares structurally with the persisted programs after normalisation,
and prints each mismatch with the site identity and dispatcher name
(env-gated, to stderr). Phase C's gate runs the full gate once in
verify mode and requires zero mismatches, and once with `off` with
results identical to the default.

**Measurement.** The rig once on the trained build (a measured run is
never a training run); the dispatch counters must show the miss count
falling by the persisted share C0 predicted, and the histogram must
name what is left.

**Phase C: closed 2026-09-16** (rakudo `79829d402e`, nqp `f5c5bc8fa`).
Everything above landed: the `DispatchSlot` schema and its codec (nqp
`e27a795d8`), the consumer, the modes and the counters (`5fd74d9b6`),
the recorder and `UnitDispatchWriter` (`3d0b54fa4`), verify by evaluated
outcome with a verify log and drop reasons (`d3e602917`), the gradle
training of a stage2 copy (`f5c5bc8fa`) and the Makefile's training
stamp (rakudo `79829d402e`). **The headline: on the trivial program the
build trains, cold rakudo `recorded=` falls 4723 -> 193 (-96 %, C0
predicted "under 500") with `restored=4477` over 4195 sites and
`dropped=37`; nqp's falls 1766 -> 87; `hits` falls 80298 -> 13292,
because the dispatcher's guest code no longer runs to record.** Rig row
`c`: cold `rakudo -e` 2.461 -> 2.272 s, cold `nqp -e` 1.160 -> 1.203 s,
misses 5667 -> 4931 (ruling 8: restore happens *at* the miss), hits
100711 -> 35512, warm `t/01-sanity` 63 s against 50 s (an open item).
The verify gate is `mismatched=0` on the nqp suite (155/155, 204 s) and
`t/01-sanity` (25/25, 51 s), and `off` reproduces the default exactly.
Plan and ledger:
`docs/superpowers/plans/2026-09-15-jvm-milestone-7-first-execution-phase-c.md`
and its `.ledger.md`; the numbers, the 22 rulings, the sizes and the
compression question:
`docs/jvm-perf-findings-2026-09.md`, "Milestone 7, Phase C"; the
mechanism: `docs/jvm-unit-lazy-loading.md`, "The dispatch table". One
correction to the letter above: **verify does not compare structurally
alone** -- text first, then the evaluated outcome on the recorded call's
own arguments, counted `byOutcome`, because a `lang-meth-call` site
legitimately records two shapes around a class publishing its method
cache. A second, smaller one: the slot carries **programs only**
(`DispatchSlot(programs)`) -- no site identity, since the slot's address
is the identity, and no descriptor index, since the descriptor travels
inline.

## The close

1. The rig once on the final build; whole `t/` once on one warm
   server; CORE.c from the last `make`.
2. Findings appended to `docs/jvm-perf-findings-2026-09.md` as a
   milestone 7 section: one row per lever with both hashes, the four
   numbers, landed or struck, and the promotion list of A7.
3. `docs/jvm-truffle-only-plan.md`: the position section rewritten;
   item 4's row states what this milestone closed and what it left.
4. The lazy-loading spec gets a Revision 3 note: phase 1 landed in
   milestone 7, phase 2 is what remains of it.
5. The milestone memory written; `MEMORY.md` pointed at it.
6. Rebase both trees onto upstream main, gates once more, push to
   ab5tract.

## Gates

Before any task lands, in cost order:

1. The nqp suite through `tools/build/evalserver-sweep.raku --suite=nqp
   '--chunk=*'`, 154 files green.
2. Rakudo `make`, only after step 1 is green.
3. `t/01-sanity`, 25/25.
4. Warm `t/02-rakudo` on one server, `--chunk` = its file count, no new
   red against the milestone-5 baseline for that directory. No `t/spec`.
5. Phase B: the lazy-loading spec's window sequence, full gate at each
   of its three steps; nqp suite green on the window build **before**
   `jBootstrapFiles` runs.
6. Phase C: the full gate once in `verify` mode with zero mismatches,
   once with persistence `off`, identical results.

Every lever is measured on the rig before its gate, so a struck lever
costs one runtime rebuild and one rig run, not a gate.

## Out of scope

- SC demand deserialization (lazy-loading phase 2).
- Plan items 1-3 (plain call, language id, calling convention).
- Sharing objects across eval-server runs (struck 2026-09-13: per-run
  loading is 4 % of the server's time).
- Profiling BOOTSTRAP v6c; idempotent setting compilation.
- NFG on TruffleString; `t/spec`; the ahead-of-time image.
- Compression of `unit.dispatch`; its size is measured, not reduced.

## Risks

| risk | answer |
|---|---|
| A persisted program valid in the training process but not in the consumer, because a dispatcher read state it did not guard | the verify gate; training only on the trivial program before any user code runs; residual risk recorded in the findings as such |
| A7's boundary slows a hot classlib op | measured on both clocks before adoption; the promotion list to sited nodes; the knob stays until the list is empty |
| A6 changes semantics for a class that overrides `clone` | the compile-time check that the resolved method is Mu's own proto; anything else keeps the method call |
| Direct field reads bypassing `ensureBody()` | lazy-loading task 1.1, carried over |
| `unit.dispatch` inflates artifacts, CORE.c most | measured at Phase C close and recorded; reduction is a later decision |
| A stage0 regeneration from a broken window build | gate order: nqp suite green on the window build before `jBootstrapFiles` |
| The training run and the measured run get confused | separate job-directory subfolders and the `NQP_DISPATCH_RECORD` gate in the rig script: a rig run refuses to start with it set |
| A Truffle annotation dependency creeps into runtime logic | decision 7 allows the annotation only; review checks each runtime import of `com.oracle.truffle` |

## Done

- Every lever A1-A8 landed or struck, its four numbers and hashes in
  the findings.
- Phase B passed its window sequence; stage0 regenerated once; v1
  reader deleted.
- Phase C passed the verify gate; the dispatch counters show the
  persisted share.
- Both clocks re-measured on the final build and recorded against
  2.68 s and 5078 s; CORE.c recorded from the last make.
- Docs, memory, rebase and push per "The close".

**Milestone 7: closed 2026-09-16** (rakudo `6217a89e61`, nqp
`a837bf1bb` -- row `c`'s tree plus the final review's fix wave; the nine
v2 stage0 jars stay uncommitted by user rule). Every item of "Done"
above is met. A1-A8 are landed or struck with their four numbers and
hashes in the findings; Phase B passed its window sequence, stage0 was
regenerated once and the v1 reader deleted; Phase C passed the verify
gate at `mismatched=0` -- re-taken on the fixed tree after the schema
version landed, and with `staleSchema=0` on a cold run -- and the
dispatch counters show the persisted share (`restored=4475` at 4193
sites against `recorded=195` on the program the build trains). Both
clocks were re-measured on the final build: cold `rakudo -e` **2.247 s**
against the 2.68 s baseline, cold `nqp -e` 1.198 s against 1.12 s, and
`blib/CORE.c.setting.jar` **296 s** from the last `make` (888 s, one
`+++ Training`). The whole-`t/` clock against 5078 s is **not gathered**: the sweep's single server was killed by its own 9 GiB
`MemoryMax` cgroup cap at file 310 of 482 (its native memory outgrew the
off-heap allowance over 55 minutes) and the user rule forbids re-running a failed benchmark
(`docs/jvm-full-suite-run-2026-09-16.md`). The 310 files that did run
hold one new red, `t/02-rakudo/closure-static-clone.t`, which is not
Phase C's doing -- it fails with `NQP_DISPATCH_PERSIST=off` too.
What the milestone left -- lazy-loading phase 2, the compression
decision, training's ~1 % run-to-run variation and the reproducibility
it costs, the markers' missing quantity floor, the empty A7 promotion
list, the warm-clock question -- is listed in
`docs/jvm-perf-findings-2026-09.md`, "Milestone 7: the close".
