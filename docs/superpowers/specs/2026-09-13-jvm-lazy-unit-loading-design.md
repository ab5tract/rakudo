# Lazy unit loading: artifact v2, lazy tables, SC demand deserialization

Design, 2026-09-13. Approved in chat the same day, section by section.

Position: milestones 1-6 of the unit-artifact road are closed. Milestone 6
established that the JVM backend's cold start is artifact decoding, not class
loading: a Native Image removed class loading and still started 1.46x slower
(`docs/jvm-perf-findings-2026-09.md`). The milestone-6 design named a per-stage
load profile as a later task (its Task 7) and it was never run. This design
starts there.

Measured starting points (recorded 2026-09-10 to 2026-09-12, not re-measured
here): cold `nqp-j -e 'say(1)'` 1.93 s wall / 9.8 s CPU, of which JVM boot is
about 0.1 s; cold `rakudo-j -e 'say 1'` 3.66-4.10 s.

## Revision 1 — Phase 0 findings and handoff (2026-09-13)

**Read this section first.** Phase 0 ran the same day the design was approved,
and it overturned the design's premise. The next session re-ranks the work
(user decision: "C", revise the spec and re-rank before choosing) and then
decides the order. Everything from "Goal" onward is the original design; the
parts Phase 0 superseded are marked in place.

### What Phase 0 found

1. **Artifact decoding was a small share of cold start.** Exclusive load time
   before any fix: `nqp -e` spent about 51 ms (under 3% of 1.92 s) in read,
   inflate, meta, programs, SC decompress and `buildTable`; `rakudo -e` about
   410 ms (about 11% of 3.64 s). Load blocks (62-72%) and deserialize programs
   (18-24%) dominated.
2. **The top cost was quadratic wire parsing, not load logic.** JFR
   `hot-methods`: `Grapheme.nextBoundary` + `GraphemeBreakIterator.setText` +
   `ArrayList.grow` were about 70% of `nqp -e` samples and 40% of `rakudo -e`.
   Every such stack came from `NqpWire.graphemeEnd` (engine programs) and the
   identical code in `RxWire.kt` (regex descriptors): a fresh `BreakIterator`
   with `setText` over the whole text for every pooled string, O(pool x
   length) per parse. It is the 2026-09-06 outer-framing bug again, in the
   inner pool framing. The "expensive" QAST.jar load block (742 ms) was mostly
   this: it is the first code to run, so it parses hundreds of programs.

### What landed (uncommitted at handoff)

`GraphemeCursor` (`nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/GraphemeCursor.kt`):
one lazily created iterator per text, `setText` once, plus an ASCII fast path
(a char below U+0300 that is not CR, followed by the end or another char below
U+0300, is one grapheme). `NqpWire.decode` and `RxWire.Reader` use one cursor
per parsed text. 7 unit tests (`nqp-runtime/src/test/.../GraphemeCursorTest.kt`)
compare it with the old fresh-iterator behaviour, including 500 mixed segments
in and out of order. Runtime-only: wire format unchanged, no stage0
regeneration, no setting recompile.

| Benchmark (best of 5, stock runners) | Before | After |
|---|---|---|
| `nqp-j -e 'say(1)'` | 1.924 s | **1.122 s** (-42%) |
| `rakudo-j -e 'say 1'` | 3.638 s | **2.681 s** (-26%) |
| `t/01-sanity/01-literals.t` | 5.017 s | **3.940 s** (-21%) |
| nqp suite, one warm eval server (154 files) | 340 s | **186 s**, green |
| `t/01-sanity`, one warm eval server | 105 s | **56 s**, 25/25 |

### What is left in `rakudo -e` cold start (after the fix)

Exclusive load time 1918 ms of 2.68 s wall; JFR's top method is now the Truffle
interpreter (`NqpRootNodeGen$CachedBytecodeNode.continueAt`, 33% of samples).

| Candidate | Evidence | Measured | Unknown |
|---|---|---|---|
| CORE.c load block | exclusive stage time | **541 ms** | what it runs; not profiled below the stage |
| Deserialize programs beyond the SC reader (`perl6` 223, CORE.c 222) | exclusive stage time | **~446 ms** | which ops: fixups, closures, orphan code refs, repossession |
| Interpreter cost of cold engine code | JFR `continueAt` 33% | overlaps the two rows above | whether it is parse, first execution, or specialization |
| Design phase 1: decoding and tables | inflate 89, SC decompress 65, programs 59, meta 48, table 41, read 14, static lex 12 | **~310 ms** | how much mmap and stored entries save against 6x artifact size (CORE.c SC is 28 MB uncompressed, 4.5 MB as LZ4) |
| Design phase 2: SC stub + finish | exclusive stage time | **~225 ms** | how much of CORE.c's 275k objects a small program touches |

### Decisions for the next session

1. **Re-rank the five candidates**, and choose the order. The first two rows
   are unprofiled below the stage; profiling inside them (JFR with stack
   filtering, or NQP_CODE_WHY on the named blocks) is the cheap first step.
2. **Keep or restate the targets.** Decision 5 below (nqp < 1.0 s, rakudo
   < 2.0 s) predates Phase 0. nqp is now 0.12 s off its target; rakudo is
   0.68 s off, which the design phases alone (~535 ms) would not close.
3. **Whether phases 1 and 2 stay as designed** (kotlinx records, mmap store,
   lazy tables, SC demand) once they are ranked against the first two rows.

### How to resume

- Work only in the worktree `.claude/worktrees/jesp-direct-lazy-records`
  (both trees). The session's starting directory is the stale main checkout.
- Timers: `NQP_UNIT_LOAD_STATS=1` (`UnitLoadStats.kt`; first line
  `unit-load: stats on`), one line per stage per unit, depth-indented.
- Profile: `raku tools/build/unit-load-profile.raku --out=<dir>` under
  watched-run (best-of-5 per benchmark, then one JFR each). Break a run down:
  `raku tools/build/unit-load-exclusive.raku <dir>/rakudo-e-run<N>.err`.
  Rank a recording: `jfr view --width 170 hot-methods <dir>/rakudo-e.jfr`;
  find callers: `jfr print --events jdk.ExecutionSample --stack-depth 30`.
- Pitfalls hit this session: launching a child JVM from a script with an
  inherited stdin and separate stdout/stderr hung `rakudo-j` under
  watched-run (the profile tool uses a closed stdin and merged output); a
  `cd` in one tool call moves the next call's directory (pin paths); a test
  file's non-ASCII literals are hard to verify (the unit test builds strings
  from codepoints).
- Gates: `tools/build/evalserver-sweep.raku --suite=nqp '--chunk=*'`, then
  rakudo `make` only if that is green, then `evalserver-sweep.raku '--chunk=*'
  t/01-sanity`. The wire fix is runtime-only; the rakudo build from before it
  (make 948 s) stays valid.

### Uncommitted inventory at handoff

**nqp tree** (`jesp-direct-lazy-records` at d328dc042), 20 modified and 3 new
files, all gated green together (nqp suite 154/154, `t/01-sanity` 25/25):

- *`$*` dynamic variables:* `TruffleEncoder.nqp` (contextual reads use the
  dynamic road unless the current block declares the name; explicit
  `getlexdyn`/`bindlexdyn` route to the engine op), `NqpOps.java` and `Ops.kt`
  (the engine op starts at the caller, or `tc.frame` for a frame-free block).
- *Signature order errors:* `TruffleEncoder.nqp` dies with MoarVM's messages.
- *Frame-free bind failure:* `TruffleEncoder.nqp` (explicit `assertparamcheck`
  routes to the engine op), `NqpDispatch.kt` (`enterEngine` resumes a
  resumable dispatch).
- *Regex lookaround over groups:* `RxTree.kt`, `RxDescriptor.kt`, `RxProgram.kt`,
  `RxDescriptor.nqp`.
- *Continuation clone:* `CodeEngine.kt`, `Ops.kt`, `NqpCodeEngine.java`.
- *qast:* `TruffleEncoder.nqp` ("has not appeared" wording), `t/qast/01-qast.t`
  (`backend.start` tests skipped on JVM).
- *No Perl 5 regex on JVM:* `build.gradle.kts`.
- *nqp eval server launcher:* `GenerateRunnerTask.kt`, `build.gradle.kts`,
  `.gitignore`.
- *Phase 0 timers:* `UnitLoadStats.kt` (new), `UnitLoader.kt`, `UnitZip.kt`,
  `ProgramUnit.kt`, `SerializationReader.kt`.
- *Wire fix:* `GraphemeCursor.kt` and its test (new), `NqpWire.java`,
  `RxWire.kt`.

**rakudo tree** (`worktree-jesp-direct-lazy-records` at 0a2f4600e7): the
`evalserver-sweep.raku` port (`--suite=nqp`, `--chunk=*`), and the two new
profile tools named above. Committed today: the RakuAST JVM Perl 5 regex guards
(0a2f4600e7) and this spec (1658840f07).


## Revision 2 — below the stage (2026-09-13, later the same day)

Revision 1 left two rows unprofiled: the CORE.c load block (541 ms) and
the deserialize programs (about 446 ms). This revision opens both, on
the rebased tree (rakudo `36ef2127e6`, nqp `c17d93d27`, the same
runtime as the wire fix). Method: cold `rakudo-j -e 'say 1'` under JFR
at 1 ms with `-XX:FlightRecorderOptions:stackdepth=512` (the default 64
frames truncates the interpreter's stacks below the container frames,
which is why an earlier recording showed 4 samples in the load block),
attributed with `tools/build/jfr-attribute.raku` (inclusive by container
frame, or `--innermost` for the Java frames between the leaf and the
nearest interpreter frame); then `NQP_CODE_TRACE=1`, whose line now
carries the block's id, unit and source line (nqp `c17d93d27`), cut at
the stage-timer lines; then `NQP_DISPATCH_STATS=1`.

### The rows, opened

| row | what it is | evidence |
|---|---|---|
| CORE.c load block, 45 % of main-thread samples | **guest execution**, not loading: the setting's mainline runs 1207 package bodies once each (1210 entries at `CORE.c.setting:0`, 1207 distinct blocks), and everything they touch dispatches cold | 8147 stub-road block entries between the CORE.c deserialize program and its `load-block` line; leaf is the interpreter loop for 37 % of the row's samples; entered through DispatchOp 20 %, ClassLibOp 13 %, RunOp 5 % |
| of which: dispatch misses | **4635 of those 8147 entries are dispatcher programs** from `src/vm/moar/dispatchers.nqp`, one run per miss: `raku-invoke` 1473, the method-call initial dispatch 1432, `raku-meth-call` 1422, the multi initial dispatch and proto 58 each, `raku-call` 49, `raku-rv-decont` 40; plus `Block.clone` from BOOTSTRAP 1148 times (the closure clone behind `p6capturelex`) | whole run: 6815 misses, 125 055 hits, 7733 invokes; the Java side of a miss (record + realize) is 9-10 % of main-thread samples on its own, the dispatcher program's interpreted run is inside "interpreter self" |
| deserialize programs, 73 % inclusive | **nesting**: contains the row above, the SC read and the dependency decode; its own share (the fixup tasks) is about 7 %; CORE.c's deserialize program enters 17 blocks | container view |
| SC read | 10 % of samples: fastutil `Object2IntOpenHashMap.rehash` 17 % of it, `Unsafe.getIntUnaligned` 13 %, `deserializeObjects` 11 %, `stubObjects` 7 %, `HashMap.resize` 6 % | `--innermost sc-read` |
| unit decode | 9 % of samples, LZ4 two thirds of it, `readMeta` a fifth | `--innermost unit-decode` |
| program materialization | 2-3 % (wire decode plus the Bytecode DSL builder) | `materialize` + Builder leaf frames |
| build-table | 2 % (`insertArguments`, the LambdaForm editor) | |
| GC | 145 ms in 18 pauses, about 4 % of wall | `jdk.GCPhasePause` |

Exclusive shares (innermost Java frames, 1479 main-thread samples):
interpreter self 35.7 %; hash maps of every kind 13.0 %; SC reader
10.1 %; dispatch miss/record/realize 9.3-9.6 %; unit decode 8.8 %;
`ArgsExpectation.invokeByExpectation` 8.0 %; `java.lang.invoke`
(LambdaForm spinning, `insertArguments`, `StackMapGenerator`) 7.6 %.
The rows overlap where one region holds several.

The compile of `-e` after the settings load is the same shape in
miniature: 6997 block entries, 3215 of them dispatcher programs.

### The warm path (one eval server, mid-sweep)

A two-minute JFR recording attached with `jcmd JFR.start` to the server
running the whole-t/ sweep (started 19:43, recording at 19:49-19:51,
inside `t/02-rakudo`), 773 samples over four busy threads. JFR samples
at most a handful of threads per tick, so the count is small but the
distribution across the busy threads holds; the default 64-frame depth
applies (attach-time recordings cannot deepen it), so only the
leaf-side `--innermost` view is read.

| subsystem (exclusive) | share |
|---|---|
| `NqpOps.classlib` as the leaf (the boundary road into the classlib; the op bodies behind its method handle are hidden frames, so they land here) | 17.7 % |
| interpreter self (generated frames as leaf) | 12.8 % |
| `sun.misc.Unsafe.putObject/putLong` under the Truffle frame API (interpreter frame slot writes) | 14.6 % |
| hash maps | 6.3 % |
| `java.lang.invoke` (MH spinning: `SplitConstantPool`, `EntryMap`) | 4.8 % |
| stub road `invokeByExpectation` | 3.5 % |
| dispatch record | 3.0 % |
| SC read | 2.6 % |
| program materialization | 1.2 % |
| build-table + unit decode | 0.5 % |
| GC pauses (from the recording, not samples) | 1.37 s in 120 s, about 1 % |

**Per-run loading is not a suite-clock lever.** The eval server
rebuilds tables and deserializes every SC per run, and all of that
together is about 4 % of the server's sampled time; eval-server
cross-run sharing (the candidate "(b)" of the 2026-09-13 order) is
struck. The warm clock is execution: the DSL interpreter running each
test file's fresh code (cached tier, frame writes through Unsafe), the
classlib boundary (`NqpOps.classlib` and its `ClassLibSite.resolve`),
and method-handle spinning. That is the plan's items 1-2 and milestone
7's "slow paths visible to the inliner", not this design.

### The suite clock (step 1 of the 2026-09-13 order)

The whole `t/` suite, the milestone-5 directory list (427 files), one
warm 8 GB eval server, on the rebased build with the wire fix:
**5078 s** (`Files=427, Tests=5653`), against milestone 5's 6039 s for
420 files: **-16 %**, per file -17 %. The 30-minute rule is 1800 s, so
the distance is **2.8x**. The wire fix's -47 % on warm `t/01-sanity`
did not carry: sanity files are tiny and load-dominated, the suite is
not. Red: 23 files, 21 of milestone 5's 22 (`04-settingkeys-6d.t` is
green) plus two tests upstream added on 2026-09-10/11 that the JVM had
never run (`regex-interpolation-fold-length.t` 18/21,
`str-raku-prepend.t` 7/9); no regression from the rebase or the fix.
Six more files appear in the harness summary only for "TODO passed".
Pitfall: the sweep is silent until its chunk ends, so watched-run's
default stall watchdog kills it at 900 s; launch with a `--max`
ceiling or a stall past the run.

### What this decides for the design

1. **Phases 1-2 as designed address unit decode + SC + tables, about
   21 % of main-thread samples, about 0.55 s** — the 535 ms Revision 1
   estimated, confirmed from the other side. They do not touch the
   largest row.
2. **The largest row is first-execution cost, and its unit is the
   dispatch miss.** Roughly 4600 misses inside the CORE.c load, 6800 in
   the run, each one an interpreted run of a dispatcher program plus
   the Java record/realize (9-10 %), plus the stub road and its method
   handles (8 % + 7.6 %). The levers are: fewer misses (why do 1207
   package bodies and 1148 `Block.clone`s dispatch cold at all: the
   `p6capturelex(clone(...))` road of `IMPL-CLOSURE-QAST` at setting
   load), a cheaper miss (the dispatcher programs run in the cold DSL
   interpreter; the record/realize Java side is CHM-heavy), or a
   persisted miss (a per-call-site dispatch outcome cached in the unit
   artifact, valid while the guards it recorded hold — the artifact
   road makes call sites stable, the same property the engine cache
   would have needed). The last is the one that fits this design's
   frame: it is a unit-artifact question.
   The suite clock says the same from the other side: the warm path is
   the interpreter, the classlib boundary and the dispatch cold path, and
   loading is 4 % of it, so the dispatch miss and the boundary road are
   the levers on both clocks while phases 1-2 move only the cold one.
3. **Cheap and independent of the ranking:** presize the SC reader's
   `Object2IntOpenHashMap` and `HashMap`s from the header counts (rehash
   and resize are 23 % of the reader's samples, about 2.5 % of the
   run); `UnitLoadStats.report` formats with `String.format` (only when
   the timers are on).

### Targets, restated

Cold `nqp-j -e 'say(1)'` under 1.0 s stays (0.12 s away). Cold
`rakudo-j -e 'say 1'` under 2.0 s stays as the direction and is not
reachable by phases 1-2 alone (2.68 - 0.55 = 2.13 s at best); it needs
the dispatch-miss row as well.


## Revision 3 — phase 1 moves into milestone 7 (2026-09-13)

Phase 1 (tasks 1.1-1.6: store, codec, lazy tables, eval-server mapping,
the transition window) is executed as Phase B of
`2026-09-13-jvm-milestone-7-first-execution-design.md`, which adds a
fifth entry, `unit.dispatch`, and a site identity to the v2 format so
that the format changes once. Phase 2 (SC demand deserialization) is
what remains of this design after milestone 7. The tasks below are
unchanged and are the reference text for milestone 7's Phase B.

## Revision 4 -- phase 1 landed (2026-09-15)

**Tasks 1.1 to 1.6 are done**, as milestone 7 Phase B (plan and ledger:
`docs/superpowers/plans/2026-09-15-jvm-milestone-7-first-execution-phase-b*.md`;
rakudo `107eca63a3`, nqp `318558c2d`). The format as built is documented
in `docs/jvm-unit-lazy-loading.md` and its numbers in
`docs/jvm-perf-findings-2026-09.md`, "Milestone 7, Phase B". 1.1 the
direct-field survey (verdicts applied in the lazy-body task); 1.2 the
store -- stored entries, one open, one mapping sliced per entry, the
`unit.index` tables, nested units sliced from the same mapping when
claimed; 1.3 the kotlinx codec over `ByteBuffer` slices; 1.4 shells and
bodies behind `ensureBody()`, with static lexical values applied at fill
or queued for the SC; 1.5 the eval server's process-wide store
(`UnitLoader.stores`, `prime`); 1.6 the transition -- window build,
stage0 regenerated as v2, the v1 reader deleted, a full gate at each
step.

Where the execution departed from this document's letter:

- **Task 1.4's per-unit `CallSiteDescriptor` table is not built.** The
  v1 call-site table was never written and the engine builds its own
  descriptors from the wire, so v2 drops the concept; `getCallSites()`
  returns empty. Phase C's persisted record therefore carries its
  descriptor inline rather than by index.
- **Task 1.4's engine cache is keyed by the program's identity string,
  not by (unit, index).** `CodeEngine.materialize` hands the engine a
  Source name `"<store name>!<unit id>#<program index>"`; `NqpLanguage`
  keys `PARSED` by that when it parses as an identity and by the program
  text otherwise. An in-memory unit keeps the text key deliberately: its
  unit id is a fresh sha1 per compile, so identical `EVAL` texts must go
  on sharing one parsed root.
- **Static lexical values live per block, not in one unit-level list**
  (this document's 1.4 left the shape open). A row naming a gap qbid is
  dropped with an `NQP_CODE_WHY`-gated line rather than being an error:
  the compiler allocates qbids for `%*BLOCK_LEX_VALUES` cuids it never
  compiles, and v1 skipped those rows silently.
- **Task 1.6's transition never transcoded anything.** The window build's
  v1 reader was in place but the stage0 compiler wrote v2 from the
  start, so `transcode-v1` lines were 0 throughout and removing the
  reader changed no clock.
- **Sizes went the other way from the estimate.** Stored entries make
  the artifacts 8-10x larger on disk (CORE.c 5.9 -> 56.1 MB), not the
  ~2x the transition task assumed; the estimate had read v1's inflate
  size as "uncompressed" when its SC member was still LZ4'd inside it.
  Whether to compress stored entries is deferred (user decision,
  2026-09-15) and is an open question for milestone 7 Phase C.

**Phase 2 (SC demand deserialization) is what remains of this design**,
and v2 has already done its groundwork: `unit.serialized` is written raw
(no LZ4) and reaches `SerializationReader` as a mapped `ByteBuffer`
slice (`ProgramUnit.serializedBlob()` -> `UnitStore.serialized`; the
reader sets its own byte order and never calls `array()`). It is the
largest entry of a large artifact -- 28.2 MB of CORE.c's 56.1 MB -- and
the whole of it is still read at load.

## Goal

Make loading a unit artifact lazy, so that a program pays only for the parts of
`nqp.jar`, `rakudo.jar` and the CORE settings it actually touches. Small-program
cold start is the design centre; build throughput gains whatever falls out of
it.

## Today's load path (what is eager)

Every load step is eager except engine program parsing, which already happens
on a block's first call (`CodeEngines.materialize`). Paths are relative to
`nqp/src/vm/jvm/runtime/org/raku/nqp/`.

- **Envelope.** The jar is opened twice (`runtime/unit/UnitLoader.kt:22-26`,
  `:37-39`), read whole, and every entry inflated in sequence
  (`runtime/unit/UnitZip.kt:88-104`).
- **`unit.meta`.** Hand-rolled little-endian binary with no per-block index
  (`runtime/unit/UnitFormat.kt:16-101`), so every block record, call site and
  static lexical row is decoded up front. About 6 MB for CORE.c.
- **`unit.programs`.** One LZ4 blob; every program becomes a `String` at load
  (`UnitFormat.kt:112-116`) although each is parsed only when first called.
- **Nested units.** Meta and programs decoded whether or not they are claimed
  (`UnitZip.kt:96-112`).
- **Block table.** `ProgramUnit.buildTable` builds a `CodeRef` + `StaticCodeInfo`
  per block, about three `MethodHandles.insertArguments` bindings each, plus a
  `CallSiteDescriptor` per call site (`runtime/unit/ProgramUnit.kt:28-109`,
  `runtime/StaticCodeInfo.kt:~246-275`).
- **SC.** `SerializationReader.deserialize()` stubs and then finishes every
  STable, object, closure and context (`sixmodel/SerializationReader.kt:92-153`).
  There is no demand hook: `SerializationContext.getObject` is an array read.
- **Dependencies.** Each dependency unit repeats all of the above, recursively.
- **Eval server.** `UnitLoader.prime` caches parsed records only; every request
  rebuilds tables and deserializes in full.

MoarVM, for comparison, keeps the SC reader alive and finishes objects on first
touch (`MVM_serialization_demand_object`/`_stable`/`_code`,
`src/6model/serialization.c`), and finishes a static frame's bytecode only on
first invoke (`MVM_bytecode_finish_frame`, `src/core/bytecode.c`).

## User decisions (2026-09-13)

1. **Design centre: small-program cold start first**, build throughput second
   (option C).
2. **kotlinx.serialization, lazy-friendly.** Metadata is split into small
   records, each serialized on its own with kotlinx, behind an index of our own
   that gives random access (option C).
3. **One spec, two phases.** SC demand deserialization is phase 2 of this
   design, so the phase-1 format and tables already leave room for it (option B).
4. **Transition window, then v1 is removed.** One build reads v1 and v2 and
   writes v2; stage0 is regenerated from it; the v1 reader is deleted (option A).
5. **Absolute clocks as the done-criterion** (option B): cold
   `nqp-j -e 'say(1)'` under 1.0 s and cold `rakudo-j -e 'say 1'` under 2.0 s
   once both phases have landed. *Superseded pending re-decision: see
   Revision 1. The phases alone cannot reach the rakudo target.*
6. **Approach 2: lazy tables inside today's runtime classes plus a
   memory-mapped store.** The mapping is part of the design, not a phase-0
   decision.
7. **Measure first, then rank** (standing rule, 2026-09-10): phase 0 profiles
   the current path before any format change and ranks the work inside phases
   1 and 2.

## Phase 0: measure

### Task 0.1 — per-stage timers

Timers gated by `NQP_UNIT_LOAD_STATS=1` (off by default, per the logging rule) around
each step of the current load path: envelope open and read, `unit.meta` decode,
program text decode, `buildTable`, SC deserialize (split into stub and finish),
each dependency load, and the unit's load blocks. Output goes to stderr, one
line per stage per unit, with unit id, elapsed time and item counts (blocks,
programs, STables, objects).

Per the fail-fast rule, the timers are first smoke-tested on a sub-30 s run and
must print a positive marker before any longer run relies on them.

### Task 0.2 — the profile

For each of cold `nqp-j -e 'say(1)'`, cold `rakudo-j -e 'say 1'`, and one
ordinary `t/01-sanity` file run cold:

- the per-stage timer lines, best of 5 runs;
- one JFR recording, to catch cost outside the instrumented stages;
- per unit: artifact size today (compressed) and projected size with every
  entry stored uncompressed.

Runs use the stock runners, never the eval server (it disables Truffle
compilation for its children).

### Task 0.3 — rank and record

A short findings section in the implementation plan's ledger: the share of each
cold-start clock taken by each stage, and the resulting order of work inside
phases 1 and 2. Phase 0 does not reopen the decisions above. *Superseded:
Phase 0 did reopen them, because it found decoding to be a small share of cold
start; see Revision 1.*

## Phase 1: artifact v2 and lazy tables

### Task 1.1 — direct-field survey

List every direct read of `StaticCodeInfo` and `CodeRef` fields
(`@JvmField` and Kotlin properties without getters) across
`nqp/src/vm/jvm/runtime`, `nqp/nqp-truffle/src` and rakudo's
`src/vm/jvm/runtime` (`RakOps`, `Binder`). For each field, record whether
every read is already dominated by one of the barrier call sites in Task 1.4.
The survey decides which fields stay raw fields and which become accessors
that call `ensureBody()`.

### Task 1.2 — the store

Jar entries are written **stored** (uncompressed), still inside a zip, so
`isUnit` sniffing and jar tooling keep working. `UnitStore` opens the file once
through a `FileChannel`, reads the zip central directory, finds each entry's
data offset from its local header (30 bytes plus name and extra lengths), and
maps each entry as a read-only `MappedByteBuffer` slice.

| Entry | Contents | Encoding |
|---|---|---|
| `unit.index` | Header record, then fixed-width offset tables | Header via kotlinx; tables as little-endian `(offset, length)` pairs, so lookup by index is O(1) without decoding |
| `unit.records` | One `BlockRecord` per block (name, cuid, outer, lexical name arrays, handlers, flags, source and `#line` sections, program index, its own static lexical values); one `CallSites` record; one `NestedUnit` header per nested unit | kotlinx, each record decodable on its own |
| `unit.programs` | Program texts back to back | Raw UTF-8, addressed through `unit.index`; no kotlinx |
| `unit.serialized` | The SC bytes, today's 6model format, not LZ4-compressed | Unchanged format, mapped for phase 2 |

The header holds magic `NQPU`, version 2, unit id, HLL, SC handle and
description, `serializedCodeRefCount`, the mainline, entry, deserialize and load
block ids, and the record counts.

Nested units use the same layout under `nested/<id>.index`,
`nested/<id>.records` and `nested/<id>.programs`, mapped only when claimed.
They carry no SC, as today.

### Task 1.3 — the codec

kotlinx.serialization core with a custom binary `Encoder`/`Decoder` pair, not
the ProtoBuf or CBOR modules:

- primitives match today's `unit.meta` (little-endian fixed-width ints,
  length-prefixed UTF-8, -1 for null);
- the decoder reads directly from a `ByteBuffer` slice, with no copy into a
  `ByteArray`;
- only kotlinx's stable core API is used.

Build changes: the `plugin.serialization` compiler plugin on `nqp-runtime`, and
`kotlinx-serialization-core` as a runtime jar, added to `NqpDeps`' allowlist
(`nqp/buildSrc/src/main/kotlin/NqpDeps.kt`, which rejects unknown runtime jars)
and to the generated runner classpaths.

### Task 1.4 — lazy runtime tables

Three layers, each built on first need.

1. **Shells.** A `CodeRef` + `StaticCodeInfo` shell holds identity only: qbid,
   unit, name, program index. `lookupCodeRef(qbid)` builds it. Each table slot is
   filled with compare-and-set; a thread that loses the race adopts the winner's
   object, so shell construction must have no side effects. The first
   `serializedCodeRefCount` shells are built before SC deserialization, because
   the reader installs them.
2. **Bodies.** A `StaticCodeInfo` body (lexical name tables, handlers, source
   info, outer link, the `MethodHandle` bindings, static lexical values) is
   decoded from its `BlockRecord` by one `ensureBody()`, synchronized on the
   static info as `CodeEngines.materialize` is. It is called at the entry points
   that need a body: frame creation; invocation entry (`ProgramEntry`, and the
   dispatcher's direct and engine roads); lexical lookup by name; and the
   reflection ops (`getstaticcode`, `ctxlexpad`, backtraces). The fast path is
   one volatile read. Outer links resolve inside `ensureBody()`, so no chain is
   forced up front.
3. **Unit-level tables.** A `CallSiteDescriptor` is built per index on first
   use. Programs are decoded from `unit.programs` by index. The engine's
   `programs` cache in `CodeEngines` is keyed by (unit, program index), so a
   lookup never builds the program text. Nested units are mapped and indexed
   when claimed.

**Static lexical values** reference SC objects. A body filled after
deserialization applies its values at once. A body filled during
deserialization (closure and context fixups can force one) is queued, and the
queue is applied when deserialization completes, which preserves today's
`applyStaticLexValues` ordering.

`nqp/src/vm/jvm/runtime` has no `@TruffleBoundary` (milestone 6), so the slow
path of `ensureBody()` stays outside compiled engine code: its call sites are
the existing boundary-marked entry points, and the runtime gains no Truffle
dependency.

### Task 1.5 — eval server

The mapped `UnitStore` is immutable and shared process-wide, replacing the
parsed-record cache (`UnitLoader.kt:16`). Each run still builds its own shells
and bodies on demand.

### Task 1.6 — the transition

Following the stage0 rule in the worktree's `CLAUDE.md`:

1. **Window build.** The reader dispatches on magic and version: v1 to today's
   `UnitFormat`, v2 to `UnitStore`. The writer emits v2 only. Full gate.
2. **Stage0 regeneration.** `./nqp/gradlew -p nqp jBootstrapFiles` from the
   window build, the last compiler that reads v1 and writes v2. Clean nqp build
   from the new stage0. Full gate.
3. **v1 removal.** `UnitFormat` and `UnitZip`'s v1 path are deleted. Clean build.
   Full gate.

## Phase 2: SC demand deserialization

No format change and no stage0 step; the SC reader and runtime only.

**Stays eager** in `SerializationReader.deserialize()`: header and string heap;
dependency resolution; installing the phase-1 code-ref shells; repossession
(it replaces objects in other SCs and cannot wait); stubbing every STable and
object, which gives each its identity but no contents.

**Becomes demand-driven:** finishing STables and objects, closures, and the
contexts and outer links they need. The reader stays alive on its
`SerializationContext`, holding the mapped `unit.serialized` slice, the string
heap, and per-index state (stub, finishing, finished) for STables, objects and
code refs.

**The barrier.** `SerializationContext.getObject`, `getSTable` and `getCodeRef`,
and so `wval`, check a volatile finished state and otherwise call
`reader.demand(kind, index)`. A demand drains a worklist: finishing an object
forces its STable first, and every object reference read while finishing
(`readObjRef`) enqueues its target instead of returning a stub. When control
returns to user code, everything reachable from what was touched is finished
and nothing unreachable has been read; user code never sees a stub. Closures and
their contexts are demanded with their code ref.

**Locking.** One global deserialization lock, not one per SC. A worklist crosses
SCs (an object in CORE.c's SC can reference one in a dependency's), and per-SC
locks would need an ordering across threads. The fast path takes no lock.

**Engine.** A `WvalSite` resolves through `getObject` once and caches the
finished object, so compiled code never reaches the barrier.

**Diagnostic.** `NQP_SC_EAGER=1` drains every SC at load, as today, for
bisecting a demand-order bug. It is removed once phase 2 has passed a full gate.

## Out of scope

- Eval-server sharing of decoded records or bodies across runs (a later cache
  on top of `UnitStore`).
- Rakudo module precompilation beyond what unit loading already covers.
- Making setting compilation idempotent (milestone 7's "one JVM for several
  compiles" probe).
- Compression of stored entries. Phase 0 records the size cost; reducing it is a
  later decision.

## Errors

- A malformed or truncated v2 entry is a hard error naming the unit, entry and
  index. There is no fallback to eager or to v1 after the window build.
- A demand reached in the middle of repossession, or into a dependency SC that
  is not loaded, dies naming the SC handle and object index. As today, a demand
  never triggers a load.

## Gates

Before any task lands, in cost order:

1. The nqp suite through `tools/build/evalserver-sweep.raku --suite=nqp
   '--chunk=*'`, fully green (154 files, green 2026-09-13).
2. Rakudo `make`, only after step 1 is green.
3. `t/01-sanity`, 25/25.
4. A named subset of `t/` chosen from the milestone-5 baselines, recorded in the
   plan. No `t/spec` (30-minute `t/` rule).
5. Phase 2 only: the whole gate once more with `NQP_SC_EAGER=1`, with identical
   results.

The two cold-start benchmarks (best of 5, stock runners) are re-run at every
phase close and recorded with the per-stage timers. After phase 1 the numbers
are reported without pass/fail; the targets are checked at phase 2 close.

## Risks

- **Direct field reads.** A read that bypasses `ensureBody()` sees a shell and
  fails far from the cause. Task 1.1 exists for this; any field whose readers
  cannot all be dominated becomes an accessor.
- **Stored entries inflate artifacts.** CORE.c grows most. Measured in phase 0;
  accepted by decision 6.
- **Demand order changes behaviour.** Deserialization side effects in REPR
  finishing, closure fixups or repossession may assume the eager order. The
  `NQP_SC_EAGER` gate run is the check.
- **Memory-mapped files and deletion.** A mapped jar replaced during a build
  while a long-lived process maps it can fault. The eval server is the exposed
  case; it must be restarted after a rebuild, which it already requires.
- **Stage0 regeneration.** A v2 writer bug would be baked into stage0. The
  window build's full gate runs before regeneration, and the clean build from
  the new stage0 is gated again.

## Documentation

- New `docs/jvm-unit-lazy-loading.md`: the v2 format, the three laziness layers,
  the SC barrier, and the diagnostic.
- `docs/jvm-eval-server.md`: a note that mapped stores are shared across runs.

## Done

- Phase 2 has landed and every gate passes, including the `NQP_SC_EAGER` run.
- Cold `nqp-j -e 'say(1)'` best of 5 is under 1.0 s and cold
  `rakudo-j -e 'say 1'` best of 5 is under 2.0 s. *Pending re-decision; see
  Revision 1.*
- The v1 reader and the `NQP_SC_EAGER` diagnostic are gone.
- The documentation above is written.
