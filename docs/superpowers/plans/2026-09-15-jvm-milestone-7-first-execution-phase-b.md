# Milestone 7, Phase B: the format, once — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking. Keep a ledger twin at
> `docs/superpowers/plans/2026-09-15-jvm-milestone-7-first-execution-phase-b.ledger.md`
> (project convention: every ruling, every deferred minor, every task
> verdict and every rig row goes in it as it happens, not at the end).

**Goal:** Replace unit artifact v1 with v2 — stored, memory-mapped
entries, an index of fixed-width tables, per-block records decoded on
first need, lazy code-ref bodies, a site identity on every dispatch
instruction and an empty `unit.dispatch` table — regenerate stage0 once,
delete the v1 reader, and measure the cold clocks once on the result.

**Architecture:** One load road for every unit, file-backed or in
memory: the compiler's record is encoded by `UnitImageWriter` into a
stored zip (a file, or a heap byte array for an in-memory unit),
`UnitStore` opens it by parsing the zip's central directory and slicing
one mapping, and `ProgramUnit` builds identity-only shells from the
index and fills each `StaticCodeInfo` body from its record slice behind
`ensureBody()`. The v1 zip reader survives one build (the window) as a
transcoder into an in-memory v2 image, stage0 is regenerated from that
build, and the transcoder is deleted. Site identity rides through the
engine's compile key: `(unit id, program index)` names the Source, the
program builder numbers each dispatch wire node once, and the slot
table in `unit.index` is addressed by `(program index, ordinal)`.

**Tech Stack:** NQP and Raku on the JVM; Oracle GraalVM 25.2.4 with
Truffle (Bytecode DSL); Kotlin for runtime code (Java only inside the
three DSL-bound files `NqpRootNode.java`, `NqpOps.java`,
`NqpProgramBuilder.java`, plus `NqpLanguage.java`/`NqpCodeEngine.java`
which already exist as Java); kotlinx.serialization core 1.11.0 with a
custom binary encoder/decoder; Raku for all tooling; Gradle for the nqp
side; GNU make for the Rakudo side.

**Spec:** `docs/superpowers/specs/2026-09-13-jvm-milestone-7-first-execution-design.md`
(rakudo `83375a77ae`), section "Phase B: the format, once", which
carries in by reference tasks 1.1–1.6 of
`docs/superpowers/specs/2026-09-13-jvm-lazy-unit-loading-design.md`
(Revision 3). Both are the reference text; where a survey fact forced a
deviation, the "Rulings" section below says which and why.

## Global Constraints

Every task's requirements implicitly include this section.

- **Work in the worktree, never the stale checkout.** The repository root
  for every path and command in this plan is
  `/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records`
  (rakudo branch `worktree-jesp-direct-lazy-records`; nested nqp branch
  `jesp-direct-lazy-records`). The session starts in the stale checkout:
  pin every path.
- **Two git working trees.** The root is rakudo.git; `nqp/` is the nqp.git
  working tree nested inside it, gitignored, NOT a submodule.
  `git -C nqp ...` for that tree. Label every hash with its tree ("nqp
  `fdab66706`" vs "rakudo `3516470a6a`"). Write nqp paths with the `nqp/`
  prefix. Run gradle from the root: `./nqp/gradlew -p nqp ...`, never via
  `cd`.
- **`RAKUDO_RAKUAST=1` on every build, test and run.** The Makefile exports
  it into its own recipes; nothing sets it for your own invocations.
- **`NQP_CODE_RUN` and `NQP_CODE_PRECOMP` must not be set at all.** The
  compiler dies on `=0`.
- **`java` must be Oracle GraalVM 25.2.4.** Verify with `java -version`
  before any build or measurement.
- **Runtime-jar rebuild** after any edit under `nqp/src/vm/jvm/runtime/` or
  `nqp/nqp-truffle/`: `./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar
  syncRuntimeJars` (about 5 s). Restart any eval server afterwards. An
  edit under `nqp/src/vm/jvm/QAST/*.nqp` or `nqp/src/vm/jvm/HLL/*.nqp`
  needs `./nqp/gradlew -p nqp clean buildJvm` (the stage graph misses
  that edge); an edit to `nqp/buildSrc/` or any `build.gradle.kts`
  reconfigures on the next gradle run.
- **Rakudo's runtime jar does not follow nqp's.** The Makefile rule for
  `rakudo-runtime.jar` has `nqp-runtime.jar` as an order-only
  prerequisite, so after an nqp-runtime change that alters a class shape
  (a `@JvmField` becoming a property does) the Rakudo side must be
  `perl Configure.pl --backends=jvm --gen-nqp && make clean && make`, never
  a bare `make`.
- **Long builds and test runs go through `tools/build/watched-run.raku`**
  with `--log` and `--show`. Never hand-roll timestamp wrappers or
  tail-based monitors. `--show` takes a literal, repeatable; `--show-rx`
  takes a `/.../` regex only. Monitor a log every 90 s or more, never
  more often.
- **The eval-server sweep is silent until its chunk ends.** Launch it with
  `--stall` past the run (`--stall=7200`) and a `--max` ceiling
  (`--max=10800`), or watched-run's default 900 s watchdog kills it.
- **Never replace an eval server mid-sweep.** Pass the total file count as
  `--chunk` (`'--chunk=*'` for the nqp suite; t/02-rakudo: 306) with
  `--jobs=1`.
- **Benchmark runs use the stock runners**, `./rakudo-j` from the root and
  `./nqp-j-gradle` with cwd `nqp/`, never the eval server (it exports
  `Compilation=false` to its children).
- **No fine-grained gating (user rule 2026-09-15).** Correctness gates
  are the nqp suite (`raku tools/build/evalserver-sweep.raku --suite=nqp
  '--chunk=*'`, 155 files, all green) and `t/01-sanity` (25/25 through
  `perl t/harness5 --jvm --evalserver`, after a Rakudo `make`). One rig
  row for the whole phase, `--warm=proxy` (cold rows + warm t/01-sanity).
  The single warm `t/02-rakudo` sweep in this plan (Task 7) is the
  correctness gate the spec names before stage0 regeneration, not a
  measurement; it is run once and never re-taken. A failed benchmark run
  is recorded as not gathered and the number taken at the next planned
  point.
- **Runtime performance outranks compile time.** CORE.c is reported in
  passing from the window build; it is never a gate.
- **Tooling in Raku**, never Python or shell. Tests for tools live in
  `tools/build/t/*.rakutest`.
- **Every diagnostic env-gated**: `nqp::say(...) if
  nqp::getenvhash()<AN_ENVVAR>;` in NQP/Raku sources, `System.getenv(...)`
  read once into a `val` in runtime code. Never a bare print. Counters
  live behind `NqpDispatch.STATS` (`NQP_DISPATCH_STATS`); load timers
  behind `UnitLoadStats.ON` (`NQP_UNIT_LOAD_STATS`).
- **Smoke-test every instrument on a short workload and require a
  positive marker** before any long run (`unit-load: stats on`,
  `dispatch stats:`, `m7-rig: DONE`). Abort a long run whose marker never
  appears.
- **Kotlin, never Java**, for new code, except inside the DSL-bound Java
  files named above. New Kotlin files under `nqp/src/vm/jvm/runtime/`
  take the `-Xno-*-assertions` flags of `nqp-runtime/build.gradle.kts`
  as given (no null assertions on Java interop).
- **No Truffle dependency in `nqp-runtime` logic.** `truffle-api` is
  `compileOnly` there for TruffleString and the `@TruffleBoundary`
  annotation only; review checks every runtime import of
  `com.oracle.truffle`.
- **Subagents default to Opus.** Re-run on Fable only after erroneous
  output; log the escalation in the ledger.
- **Commits stamped in the evening of the date the work happened**,
  18:00-23:00: `STAMP="$(date +%F)T20:30:00+02:00"; GIT_AUTHOR_DATE=$STAMP
  GIT_COMMITTER_DATE=$STAMP git commit ...`; step the minute for a second
  commit the same evening.
- **Commit trailers on every commit, both trees:**
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and
  `Claude-Session: <the executing session's URL>` — the controller of the
  executing session pastes its own session URL (Phase A's plan hardcoded
  its own; this plan was written by a session whose URL is not known to
  it, so the trailer is supplied at execution time, once, into the
  ledger header, and copied from there).
- **The in-tree runners have no installed module repo**: anything with a
  `use` needs `-Ilib`.
- **No `t/spec`** in this milestone (gated on whole `t/` under 30 minutes;
  last measured 5078 s).
- **Stage0 rule** (worktree `CLAUDE.md`): regenerate stage0 with
  `./nqp/gradlew -p nqp jBootstrapFiles` only from the last compiler
  that still reads the old shape, and only after the nqp suite is green
  on that build.

## Rulings (where the surveys forced a decision)

Three read-only surveys on 2026-09-15 (rakudo `3516470a6a`, nqp
`fdab66706`) measured the ground against the two specs. What they found,
and what this plan does about it. Each ruling is recorded in the ledger
at Task 1 so the user can overrule it before the format is written.

1. **Nothing in v1 is stored; the meta deflates by 88 %.** Every v1 entry
   is DEFLATEd (`UnitZip.write` sets level 1), programs and the SC are
   LZ4'd *and then* deflated, and `unit.meta` is the entry that shrinks
   most (6.16 MB → 719 KB for CORE.c). Stored v2 entries make
   `CORE.c.setting.jar` about 13 MB on disk instead of 5.9 MB. The
   lazy-loading spec's decision 6 and its "Stored entries inflate
   artifacts" risk accept this; Task 10 records the sizes in the
   findings. No compression in this phase (spec, out of scope).
2. **`unit.serialized` is LZ4'd today** (entry name `unit.serialized.lz4`).
   v2 writes the SC bytes raw, as the spec says, and hands the reader the
   mapped slice: `SerializationReader` already takes a `ByteBuffer`
   (`orig`), so no copy is needed.
3. **The call-site table is dead.** `get_callsite_idx` in
   `nqp/src/vm/jvm/QAST/Compiler.nqp` has no callers and every measured
   artifact has 0 rows; the engine builds its own `CallSiteDescriptor` at
   decode. v2 has no call-site record kind. Phase C's `DispatchSlot`
   schema, which the milestone spec says addresses "the descriptor by
   index in the unit's call-site table", will carry the descriptor inline
   (flags + names) instead; noted for Phase C's plan, nothing to do here.
4. **Shells cannot be lazy for the serialized prefix.** The
   SerializationReader requires the first `serializedCodeRefCount` code
   refs (19 328 of CORE.c's 19 933) to be real `CodeRef` objects before
   the SC is read, and `attachClosureOuters` revisits them. The spec's
   layer 1 already builds that prefix eagerly; this plan builds **every**
   shell eagerly in one pass (identity only: qbid, name, cuid, program
   index, outer link, `USE_BINDER`), and drops the compare-and-set
   lazy-shell machinery — 3 % of the blocks are not worth a second code
   path. Bodies are what get lazy.
5. **Static lexical values are per block, applied on body fill.** v1
   applies 49 963 rows for CORE.c in one pass after deserialization, and
   each row resolves a lexical by name — which would force nearly every
   body. v2 stores each block's rows inside its record; `ensureBody()`
   applies them when the unit's SC is ready, and queues the block
   otherwise (a body forced during deserialization) — the spec's queue.
6. **Roots have no unit identity today.** The engine compiles by program
   text (`CodeEngines.programs` keyed by the string, `NqpLanguage.PARSED`
   keyed by the source text), so the program builder cannot see a unit or
   an index. This plan passes the identity as the Source name and the
   cache key: for a store-backed unit the key is `"<unit id>#<program
   index>"`, and `NqpLanguage.PARSED` is keyed by that name; an
   in-memory unit (EVAL, BEGIN, a script) keeps today's text key and gets
   **no** site identity (its unit id is a fresh sha1 per compile, so
   nothing could ever persist against it; its identical texts keep
   deduplicating as they do now). A store-backed program identical in
   text to another unit's is therefore parsed twice, once per unit — the
   cost of an injective identity, and today's `qb_N` Source names
   already defeat most of that sharing.
7. **Loop bodies are emitted twice.** `NqpProgramBuilder` walks a
   `repeat` body and both halves of a for-loop twice with `emit`, so a
   counter at `new EngineSite` is neither wire order nor dense. The
   ordinal is keyed by the DISPATCH node's **wire offset**: a per-parse
   map from offset to ordinal, assigned on the node's first visit in the
   (deterministic) walk, so both emissions of one node carry one identity
   and share one slot. The encoder's per-block `%e<dispatches>` count is
   the writer's slot count per program; the builder's map size must not
   exceed it, checked under `NQP_SITE_CHECK=1` (an artifact written by a
   compiler older than Task 6 carries count 0, so the check is a knob, not
   an assertion).
8. **Not every site is on the wire.** The helper sites in `Ops.kt`
   (`helperDispatchSites`), Rakudo's per-routine rv-decont site and the
   indy road's sites are keyed by runtime objects. They get a null
   identity; Phase C's schema tolerates identity-less sites.
9. **In-memory units take the same road.** Instead of keeping the
   `UnitRecord` object graph as a second consumer of `ProgramUnit`, the
   in-memory road (`jvm-build-unit-record`, `loadbytecodebuffer`) writes
   the same stored zip into a heap byte array and opens it with the same
   `UnitStore`. One road, exercised by every EVAL in the nqp suite; the
   encode is a memcpy-sized cost against the compile that produced it.
   The v1 window reader is a transcoder into that same in-memory image,
   so `ProgramUnit` never has two sources.
10. **The `mh` identity test moves to `staticInfo` identity first.**
    `CallFrame.outerFor`, the auto-close constructor and the two
    capture-lex syscalls recognise "a frame of that static block" by
    `mh === wanted.mh && compUnit === wanted.compUnit`, reading the
    bound handle of a block that may never have been entered. Rakudo's
    `RakOps` already tests `staticInfo === wanted`; the four nqp sites
    are converted before `mh` goes behind `ensureBody()`.
11. **kotlinx's `AbstractEncoder`/`AbstractDecoder` are used with
    `@OptIn(ExperimentalSerializationApi::class)`.** The spec asks for the
    stable core API only; the two abstract bases are the one experimental
    surface a custom format needs, they have not changed shape since
    1.0, and the alternative is re-implementing four interfaces by hand.
    Recorded as the deviation it is; the format modules (ProtoBuf, CBOR)
    stay out, as the spec intends.
12. **Gates for the three transition steps.** The window build (Task 7)
    runs the nqp suite, `make`, `t/01-sanity` and the one warm
    `t/02-rakudo` sweep before stage0 is regenerated — the spec's named
    risk is "a stage0 regeneration from a broken window build". The
    regeneration and the v1 removal (Tasks 8-9) run the nqp suite,
    `make` and `t/01-sanity`; the whole `t/` clock waits for the
    milestone close, per the user's 2026-09-15 rule.

## File Structure

Created:

| path | responsibility |
|---|---|
| `docs/superpowers/plans/2026-09-15-jvm-milestone-7-first-execution-phase-b.ledger.md` | the ledger twin |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitCodec.kt` | the kotlinx binary encoder/decoder over `ByteBuffer` (task 1.3) |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitImage.kt` | the v2 record classes (`UnitHeader`, `BlockRecord`, `StaticLexValue`) and the in-memory `UnitImage` the writer takes |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitImageWriter.kt` | encodes a `UnitImage` into a stored zip: `unit.index`, `unit.records`, `unit.programs`, `unit.serialized`, `unit.dispatch`, nested entries |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitStore.kt` | opens a stored zip (file mapping or heap buffer), parses the central directory, decodes the index, answers slices by index (task 1.2) |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ZipDirectory.kt` | the minimal central-directory parser `UnitStore` uses |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/StaticBodySource.kt` | the interface a lazy `StaticCodeInfo` fills its body from |
| `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/SiteIdentity.kt` | `(unit id, program index, ordinal)` as a value class, parsed from and printed to the compile key |
| `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitCodecTest.kt` | codec round trips |
| `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitStoreTest.kt` | writer → store round trips, index lookups, gaps, nested, dispatch slots, hard errors |
| `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/StaticCodeInfoLazyTest.kt` | shell/body semantics of `StaticCodeInfo` |
| `docs/jvm-unit-lazy-loading.md` | the v2 format, the laziness layers, the site identity, the dispatch table |

Modified (one line of responsibility each; exact lines in the tasks):

| path | what changes |
|---|---|
| `nqp/build.gradle.kts` | hygiene: stage `JavaExec` tasks off `-Xbootclasspath/a`; kotlinx plugin id for subprojects |
| `nqp/nqp-runtime/build.gradle.kts` | `plugin.serialization`; kotlinx dependency comes through `NqpDeps` |
| `nqp/buildSrc/src/main/kotlin/NqpDeps.kt` | `kotlinx-serialization-core` in `thirdParty` and `moduleOrder` |
| `nqp/buildSrc/src/main/kotlin/GenerateRunnerTask.kt` | hygiene: `bootEntries` → `classPathEntries`, comments |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/StaticCodeInfo.kt` | body fields behind `ensureBody()`; `argsExpectation`, identity and runtime state stay raw |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CodeRef.kt` | a shell constructor (no lexical arrays, no handlers, no handle spinning) |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CallFrame.kt`, `dispatch/Syscalls.kt` | ruling 10: identity by `staticInfo` |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/ArgsExpectation.java`, `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java`, `NqpCodeEngine.java`, `NqpRaw.java` | Java readers of former `@JvmField`s use the getters |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationReader.kt`, `SerializationWriter.kt` | explicit `ensureBody()` at the non-invocation barriers |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt` | built over a `UnitStore`: shells, body source, static-lex queue, programs by index, `dispatchSlot` |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitLoader.kt` | process-wide `UnitStore` cache; one open per path; v1 transcode during the window |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitWriter.kt`, `RecordReader.kt` | read the guest record into a `UnitImage` (with `dispatches` per block), write with `UnitImageWriter` |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitZip.kt`, `UnitFormat.kt`, `UnitRecord.kt` | window: v1 read only, sniff accepts both first-entry names; Task 9 deletes them |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitLoadStats.kt` | stage names for v2 (`open-store`, `shells`, `static-lex-drain`) |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/GlobalContext.kt`, `Ops.kt` | `inMemoryUnitRecords` holds `UnitStore`s |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CodeEngine.kt`, `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpPolyglot.kt`, `.../NqpLanguage.java`, `.../NqpProgramBuilder.java`, `.../NqpOps.java` (EngineSite), `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchBootstrap.kt` | site identity through the compile key into `EngineSite` and `DispatchCallSite` |
| `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt` | stats: `sites=` / `anon=` on the exit line |
| `nqp/src/vm/jvm/QAST/Compiler.nqp`, `nqp/src/vm/jvm/QAST/TruffleEncoder.nqp` | `QAST::BlockRecord.dispatches`, set from `%e<dispatches>` |
| `nqp/t/nqp/125-dispatch-stats.t` | asserts the `sites=` field |
| `nqp/src/vm/jvm/stage0/*.jar` | regenerated once (Task 8) |
| `src/Raku/ast/code.rakumod` | hygiene: the twelve-line clone guard becomes one `#?if jvm` helper |
| `src/vm/jvm/runtime/org/raku/rakudo/RakOps.kt` | hygiene: `p6clonecode` KDoc |
| `docs/jvm-perf-findings-2026-09.md`, `docs/jvm-truffle-only-plan.md`, `docs/jvm-eval-server.md`, `docs/superpowers/specs/2026-09-13-jvm-lazy-unit-loading-design.md` | Task 10: findings, position, the mapped-store note, Revision 4 |

Facts every task relies on (from the 2026-09-15 surveys, current at
rakudo `3516470a6a` / nqp `fdab66706`):

- v1 entries: `unit.meta` (hand-rolled LE binary, magic `NQPU` int
  `0x5550514E`, version 1, header then call sites, block table, static
  lexical rows, nested ids), `unit.programs` (count, then length-prefixed
  UTF-8, LZ4'd), `unit.serialized.lz4` (LZ4'd SC), `nested/<id>.meta`,
  `nested/<id>.programs`. `UnitZip.read` throws on any other entry name.
  The writer is `UnitWriter.write(unit, filename, tc)` from the syscall
  `jvm-write-unit-record` (`nqp/src/vm/jvm/HLL/Backend.nqp:65`); the
  in-memory road is `jvm-build-unit-record` → `UnitWriter.record` →
  `tc.gc.inMemoryUnitRecords` (`Ops.kt:9077`).
- `ProgramUnit.buildTable` (`ProgramUnit.kt:28-81`) builds one `CodeRef`
  + `StaticCodeInfo` per live qbid; `StaticCodeInfo.init` spins two
  `MethodHandles.insertArguments` handles per block from
  `ProgramEntry.ENTER` and allocates `oLexStatic`/`oLexStaticFlags`.
  `programIndex` is 1:1 with qbid in every measured artifact.
- `CodeEngines.materialize(sci)` (`CodeEngine.kt:136-148`) keys its
  cache by the program text, obtained from
  `sci.compUnit.engineProgram(sci.programIndex)`; `NqpPolyglot.compile`
  evals a `Source` named `sci.methodName` (`"qb_N"`) and collects the
  target from `NqpLanguage.PARSED[encoded]`. `PARSED` is never cleared;
  `CodeEngines.programs` is cleared per eval-server run by
  `DispatchBootstrap.resetAll`.
- `NqpProgramBuilder.java:517-566` decodes `DISPATCH` (wire tag 14:
  `rtype pName nargs (flag [pName])* child*`) and allocates
  `new NqpOps.EngineSite(csd)` at `:555` before walking the children.
  `EngineSite` (`NqpOps.java:824-837`) holds `csd`, `site`
  (`DispatchCallSite`), `cache`. The builder has no unit, index or
  counter; `walk(at, false)` is the measuring walk.
- The eval server (`nqp/src/vm/jvm/runtime/org/raku/nqp/tools/EvalServer.java:125,237`)
  calls `UnitLoader.prime(mainPath)` once and `UnitLoader.loadApp(tc,
  mainPath, true)` per request after `resetAll()`.
- `NqpDeps.orderKey` rejects any runtime jar not in `moduleOrder`;
  `GenerateRunnerTask.runnerJarNames` and the stage tasks'
  `thirdPartySorted()` both derive from it. kotlinx is absent from every
  build file and from the gradle cache; Maven Central is reachable and
  serves `org.jetbrains.kotlinx:kotlinx-serialization-core:1.11.0`.
- Artifact sizes at base (`unzip -lv`): `blib/CORE.c.setting.jar` 5 892 366
  bytes (meta 6 161 390 → 719 462, programs 2 393 382 → 2 001 922, SC
  4 544 231 → 3 166 793); `blib/Perl6/BOOTSTRAP/v6c.jar` 1 299 129;
  `nqp/build/jvm/stage2/nqp.jar` 139 990. CORE.c: 19 933 blocks, 0 gaps,
  19 328 serialized code refs, 49 963 static lexical rows.
- The nqp suite through the sweep: 155 files, about 200 s. Rakudo
  `make clean && make`: about 1000 s, CORE.c about 300 s inside it. The
  warm `t/02-rakudo` sweep: about 3200 s on one 8 GB server.

---

## Task 1: The ledger, the rulings, and the deferred hygiene

**Files:**
- Create: `docs/superpowers/plans/2026-09-15-jvm-milestone-7-first-execution-phase-b.ledger.md`
- Modify: `nqp/build.gradle.kts:232-243` (the stage `JavaExec` class path)
- Modify: `nqp/buildSrc/src/main/kotlin/GenerateRunnerTask.kt:26,31-37,59-64,74-75,159`
- Modify: `src/Raku/ast/code.rakumod:220-240` and `:1000-1021`
- Modify: `src/vm/jvm/runtime/org/raku/rakudo/RakOps.kt:695-702` (the `p6clonecode` KDoc)
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java:1507` (line wrap)

**Interfaces:**
- Consumes: nothing.
- Produces: the ledger every later task appends to; edits that are
  compiled and verified by Task 7's window build (a buildSrc/gradle or
  setting edit costs a full rebuild, so nothing here is built on its
  own — the Phase A fix-wave ruling).

- [ ] **Step 1: Record the base and the rulings in the ledger**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records
R=$(git rev-parse --short=10 HEAD); N=$(git -C nqp rev-parse --short=9 HEAD)
cat > docs/superpowers/plans/2026-09-15-jvm-milestone-7-first-execution-phase-b.ledger.md <<LEDGER
# SDD ledger — plan: docs/superpowers/plans/2026-09-15-jvm-milestone-7-first-execution-phase-b.md

Spec: docs/superpowers/specs/2026-09-13-jvm-milestone-7-first-execution-design.md
(rakudo 83375a77ae), Phase B, over the lazy-loading spec's tasks 1.1-1.6.
Plan committed in the same session it was written (2026-09-15).

BASE before Task 1: rakudo $R, nqp $N (Phase A's close; the a6 rig row:
cold rakudo-e 2.504 s, cold nqp-e 1.192 s, misses 5661, hits 100697).

Claude-Session trailer for this phase's commits: (the controller fills
this line in from its own session URL before the first commit)

Model policy (user rule 2026-09-11): subagents on Opus; Fable only after
erroneous output.

Rulings carried in from the plan's "Rulings" section, 1-12, open to the
user's veto until Task 3 writes the format: (copy the twelve one-line
headings here)
LEDGER
```

Replace the parenthetical with the twelve headings, one line each.

- [ ] **Step 2: Stage tasks off the boot class path**

In `nqp/build.gradle.kts`, the stage `JavaExec` configuration at lines
232-243 reads:

```kotlin
            classpath = files(compilerDir, engineJarFile)

            doFirst {
                // The compiler's own units resolve against the module
                // search path the classpath yields (compilerDir); the
                // runtime and its third-party jars ride on the boot
                // classpath as the runner's do (GenerateRunnerTask).
                val bootcp = (
                    listOf(compilerDir.absolutePath, runtimeJarFile.absolutePath) +
                        thirdPartySorted().map { it.absolutePath }
                    ).joinToString(File.pathSeparator)
                jvmArgs("--enable-native-access=ALL-UNNAMED", "-Xmx$nqpStageMaxHeap", "-XX:+AllowParallelDefineClass", "-Xbootclasspath/a:$bootcp")
```

Change it to put everything on the class path, in the runner's order
(lib, runtime, third party, engine), and say why:

```kotlin
            // Everything on the class path, in the generated runner's
            // order (GenerateRunnerTask): the compiler's own units resolve
            // against compilerDir, then nqp-runtime, the third-party jars
            // and the engine. Not the boot class path: a @TruffleBoundary
            // in the runtime tree is invisible to the compiler when the
            // runtime is loaded by the boot loader (milestone 7, A7/7b).
            classpath = files(compilerDir, runtimeJarFile) + files(thirdPartySorted()) + files(engineJarFile)

            doFirst {
                jvmArgs("--enable-native-access=ALL-UNNAMED", "-Xmx$nqpStageMaxHeap", "-XX:+AllowParallelDefineClass")
```

Keep the `--module-path` / `--add-modules` `jvmArgs` line that follows
unchanged. `thirdPartySorted()` is defined at `:120`.

- [ ] **Step 3: GenerateRunnerTask names and comments**

In `nqp/buildSrc/src/main/kotlin/GenerateRunnerTask.kt`:
- `:26` `/** Third-party jar file names, in runner bootclasspath order. */`
  → `/** Third-party jar file names, in runner class path order. */`
- `:31-37`: rewrite the KDoc on `truffleModuleDir` to say that every jar
  goes on the class path (since 7b, milestone 7) and the engine needs the
  module path for Truffle; drop the boot-loader-delegation sentence.
- `:59` rename `bootEntries` → `classPathEntries` (and its use at `:159`).
- `:74-75`: the emitted comment says "goes on the class path rather than
  the boot classpath because the boot loader cannot see the module path";
  change to "Every jar is on the class path (nothing on the boot class
  path since milestone 7, 7b): a runtime-tree @TruffleBoundary must be
  visible to the compiler, and the boot loader cannot see the module
  path either."

- [ ] **Step 4: One `#?if jvm` helper for the static clone road**

In `src/Raku/ast/code.rakumod`, the guard at `:220-237` decides
`$static-clone` inline. Add, next to `IMPL-CLOSURE-QAST` in the same
class, one helper and call it from both sites (`:232-236` and the
`$static-throwaway` computation near `:1000`, which uses the same test
on the throwaway code object):

```raku
#?if jvm
    # The static clone road (milestone 7 A6'): p6clonecode does what
    # Block.clone / Code.clone do for a code object with no phasers and
    # no declarator docs (both static, checked here); a pending
    # compile-time fixup is checked by the op at run time. tryfindmethod,
    # not findmethod: the first CORE.c files compile before the setting
    # installs these methods, and findmethod throws there. A missing
    # clone means no static road either way.
    method IMPL-STATIC-CLONE-ROAD(Mu $code-obj, Bool $regex) {
        return 0 if $regex;
        my $clone-meth := nqp::tryfindmethod($code-obj, 'clone');
        return 0 if nqp::isnull($clone-meth);
        my $block-clone := nqp::tryfindmethod(Block, 'clone');
        my $code-clone  := nqp::tryfindmethod(Code, 'clone');
        (nqp::eqaddr($clone-meth, $block-clone) || nqp::eqaddr($clone-meth, $code-clone))
            && (!nqp::istype($code-obj, Block)
                || (!nqp::ishash(nqp::getattr($code-obj, Block, '$!phasers'))
                    && nqp::isnull(nqp::getattr($code-obj, Block, '$!why'))))
    }
#?endif
```

and at the first site:

```raku
        my int $static-clone := 0;
#?if jvm
        $static-clone := self.IMPL-STATIC-CLONE-ROAD($code-obj, $regex);
#?endif
```

Read the second site (`grep -n 'static-throwaway' src/Raku/ast/code.rakumod`)
and replace its inline copy of the same test the same way. The test is
a RakuAST source edit: it takes effect at the next Rakudo `make` (Task 7).

- [ ] **Step 5: `p6clonecode` KDoc and the long comment line**

In `src/vm/jvm/runtime/org/raku/rakudo/RakOps.kt`, extend the KDoc above
`fun p6clonecode` (ends at `:702`) with two sentences:

```
     * No SC barrier is needed: Ops.clone of the code object nulls its sc,
     * as Block.clone's REPR clone does. The guard is compile-time only, so
     * a runtime .wrap of clone is bypassed on the JVM for such code objects
     * (the method road is taken only for phasers, $!why and @!compstuff).
```

In `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java:1507`,
wrap the 130-column comment at 80 columns (two lines, same words).

- [ ] **Step 6: Commit both trees**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records
STAMP="$(date +%F)T20:30:00+02:00"
git -C nqp add build.gradle.kts buildSrc/src/main/kotlin/GenerateRunnerTask.kt nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java
GIT_AUTHOR_DATE=$STAMP GIT_COMMITTER_DATE=$STAMP git -C nqp commit -m "Build: stage JavaExec tasks on the class path; runner comments follow 7b

The in-build stage compiles still loaded nqp-runtime through the boot
loader, where a runtime-tree @TruffleBoundary is invisible to the
compiler (milestone 7, Phase A's 7b fixed the generated runners only).
Everything is on the class path now, in the runner's order.
GenerateRunnerTask's bootEntries and its comments said the old thing.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: <URL>"
git add docs/superpowers/plans/2026-09-15-jvm-milestone-7-first-execution-phase-b.ledger.md src/Raku/ast/code.rakumod src/vm/jvm/runtime/org/raku/rakudo/RakOps.kt
GIT_AUTHOR_DATE=$STAMP GIT_COMMITTER_DATE=$STAMP git commit -m "Docs, RakuAST: the Phase B ledger; the static clone guard as one helper

The twelve-line test behind p6clonecode lived twice in code.rakumod;
IMPL-STATIC-CLONE-ROAD holds it once. p6clonecode's KDoc says why it
needs no SC barrier and what a runtime .wrap of clone loses.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: <URL>"
```

Append to the ledger: `Task 1: complete (commits nqp <hash>, rakudo <hash>; built by Task 7)`.

---

## Task 2: The codec (lazy-loading task 1.3)

**Files:**
- Modify: `nqp/buildSrc/src/main/kotlin/NqpDeps.kt:13-27`
- Modify: `nqp/nqp-runtime/build.gradle.kts:3-6` (plugins)
- Modify: `nqp/build.gradle.kts:3-5` (plugins, `apply false`)
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitCodec.kt`
- Test: `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitCodecTest.kt`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  `object UnitCodec { fun <T> encode(serializer: SerializationStrategy<T>, value: T): ByteArray;
  fun <T> decode(serializer: DeserializationStrategy<T>, buf: ByteBuffer): T }`
  where `decode` reads from `buf.position()` forward on a duplicate
  (the caller's buffer is untouched) and the encoding is: `Int`/`Long`
  little-endian fixed width; `Boolean` one byte; `Byte` one byte;
  `String` an `Int` byte length then UTF-8; a nullable value one mark
  byte (0 = null, 1 = present) then the value; a collection an `Int`
  size then the elements; `IntArray`/`LongArray` through kotlinx's
  built-in array serializers (size then elements); no field tags, no
  varints. Every `@Serializable` record in Task 3 is decodable on its
  own from a slice that starts at its first byte.

- [ ] **Step 1: Declare the dependency where the allowlist lives**

`nqp/buildSrc/src/main/kotlin/NqpDeps.kt`: add to `thirdParty` after
the kotlin-stdlib line, and to `moduleOrder` after `"kotlin-stdlib"`:

```kotlin
        // Records of the unit artifact (v2, milestone 7 Phase B) are
        // kotlinx-serialization records behind a binary codec of our own.
        "org.jetbrains.kotlinx:kotlinx-serialization-core:1.11.0",
```

```kotlin
    val moduleOrder = listOf(
        "fastutil", "jline", "lz4-java",
        "kotlin-stdlib", "kotlinx-serialization-core-jvm", "annotations",
    )
```

The resolved jar is `kotlinx-serialization-core-jvm-1.11.0.jar`;
`orderKey` matches `Regex.escape(it) + "-\d.*"` against the file name,
so the `moduleOrder` entry must be `"kotlinx-serialization-core-jvm"`,
not the artifact id. Use that string. Check the transitive closure:
`./nqp/gradlew -p nqp :nqp-runtime:dependencies --configuration runtimeClasspath`
must list no jar outside `moduleOrder` (kotlinx-serialization-core-jvm
depends on kotlin-stdlib only).

- [ ] **Step 2: The serialization compiler plugin**

`nqp/build.gradle.kts:3-5`:

```kotlin
plugins {
    kotlin("jvm") version "2.4.10"
    kotlin("plugin.serialization") version "2.4.10" apply false
}
```

`nqp/nqp-runtime/build.gradle.kts:3-6`:

```kotlin
plugins {
    java
    kotlin("jvm")
    kotlin("plugin.serialization")
}
```

Run `./nqp/gradlew -p nqp :nqp-runtime:compileKotlin` once; expected:
`BUILD SUCCESSFUL`, and the gradle cache now holds
`org.jetbrains.kotlinx/kotlinx-serialization-core-jvm/1.11.0`.

- [ ] **Step 3: Write the failing codec test**

`nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitCodecTest.kt`:

```kotlin
package org.raku.nqp.runtime.unit

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertContentEquals
import kotlin.test.assertNull
import kotlinx.serialization.Serializable

class UnitCodecTest {
    @Serializable
    data class Probe(
        val i: Int, val l: Long, val b: Boolean, val s: String, val ns: String?,
        val list: List<String>, val nlist: List<String>?, val ints: IntArray, val longs: LongArray,
        val nested: List<Inner>,
    )
    @Serializable data class Inner(val name: String, val idx: Int)

    private val sample = Probe(
        -7, 1L shl 40, true, "grüße 🐪", null,
        listOf("", "a", "\u0000b"), null, intArrayOf(1, -1, Int.MAX_VALUE), longArrayOf(0L, Long.MIN_VALUE),
        listOf(Inner("x", 1), Inner("", -1)),
    )

    @Test fun roundTrips() {
        val bytes = UnitCodec.encode(Probe.serializer(), sample)
        val back = UnitCodec.decode(Probe.serializer(), ByteBuffer.wrap(bytes))
        assertEquals(sample.i, back.i); assertEquals(sample.l, back.l); assertEquals(sample.b, back.b)
        assertEquals(sample.s, back.s); assertNull(back.ns)
        assertEquals(sample.list, back.list); assertNull(back.nlist)
        assertContentEquals(sample.ints, back.ints); assertContentEquals(sample.longs, back.longs)
        assertEquals(sample.nested, back.nested)
    }

    @Test fun layoutIsLittleEndianAndUntagged() {
        val bytes = UnitCodec.encode(Inner.serializer(), Inner("ab", 0x01020304))
        // "ab": Int length 2 (LE) + 2 bytes; then the Int, LE.
        assertContentEquals(byteArrayOf(2, 0, 0, 0, 'a'.code.toByte(), 'b'.code.toByte(), 4, 3, 2, 1), bytes)
    }

    @Test fun decodesFromASliceWithoutMovingTheCallersBuffer() {
        val bytes = UnitCodec.encode(Inner.serializer(), Inner("z", 9))
        val padded = ByteBuffer.allocate(bytes.size + 8).order(ByteOrder.LITTLE_ENDIAN)
        padded.position(5); padded.put(bytes); padded.position(5)
        val back = UnitCodec.decode(Inner.serializer(), padded)
        assertEquals(Inner("z", 9), back)
        assertEquals(5, padded.position())
    }

    @Test fun nullMarkIsOneByte() {
        @Serializable data class N(val s: String?)
        assertContentEquals(byteArrayOf(0), UnitCodec.encode(N.serializer(), N(null)))
        assertContentEquals(byteArrayOf(1, 0, 0, 0, 0), UnitCodec.encode(N.serializer(), N("")))
    }
}
```

- [ ] **Step 4: Run it to see it fail**

Run: `./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.runtime.unit.UnitCodecTest'`
Expected: compilation failure, `Unresolved reference: UnitCodec`.

- [ ] **Step 5: Write the codec**

`nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitCodec.kt`:

```kotlin
package org.raku.nqp.runtime.unit

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.StandardCharsets
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.SerializationStrategy
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.AbstractDecoder
import kotlinx.serialization.encoding.AbstractEncoder
import kotlinx.serialization.encoding.CompositeDecoder
import kotlinx.serialization.modules.EmptySerializersModule
import kotlinx.serialization.modules.SerializersModule

/**
 * The unit artifact's record codec: kotlinx.serialization records over a
 * binary layout of our own. Fixed-width little-endian ints, a byte per
 * boolean, an Int byte length before UTF-8 text, a mark byte before a
 * nullable value, an Int size before a collection; no field tags. A
 * record therefore decodes from a slice that starts at its first byte,
 * which is what unit.index's (offset, length) tables address.
 *
 * AbstractEncoder/AbstractDecoder are kotlinx's experimental surface for
 * a custom format; nothing else experimental is used, and the format
 * modules (ProtoBuf, CBOR) stay out (milestone 7 Phase B, ruling 11).
 */
@OptIn(ExperimentalSerializationApi::class)
object UnitCodec {
    fun <T> encode(serializer: SerializationStrategy<T>, value: T): ByteArray {
        val out = ByteArrayOutputStream(256)
        Writer(out).encodeSerializableValue(serializer, value)
        return out.toByteArray()
    }

    /** Decodes from buf.position() forward, on a duplicate: the caller's
     *  buffer keeps its position, limit and order. */
    fun <T> decode(serializer: DeserializationStrategy<T>, buf: ByteBuffer): T =
        Reader(buf.duplicate().order(ByteOrder.LITTLE_ENDIAN)).decodeSerializableValue(serializer)

    private class Writer(private val out: ByteArrayOutputStream) : AbstractEncoder() {
        override val serializersModule: SerializersModule = EmptySerializersModule()
        private val scratch = ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN)

        private fun int(v: Int) { scratch.clear(); scratch.putInt(v); out.write(scratch.array(), 0, 4) }
        override fun encodeInt(value: Int) = int(value)
        override fun encodeLong(value: Long) { scratch.clear(); scratch.putLong(value); out.write(scratch.array(), 0, 8) }
        override fun encodeBoolean(value: Boolean) = out.write(if (value) 1 else 0)
        override fun encodeByte(value: Byte) = out.write(value.toInt())
        override fun encodeShort(value: Short) = throw UnsupportedOperationException("unit codec: no Short")
        override fun encodeChar(value: Char) = throw UnsupportedOperationException("unit codec: no Char")
        override fun encodeFloat(value: Float) = throw UnsupportedOperationException("unit codec: no Float")
        override fun encodeDouble(value: Double) = throw UnsupportedOperationException("unit codec: no Double")
        override fun encodeString(value: String) {
            val b = value.toByteArray(StandardCharsets.UTF_8); int(b.size); out.write(b, 0, b.size)
        }
        override fun encodeEnum(enumDescriptor: SerialDescriptor, index: Int) = int(index)
        override fun encodeNull() = out.write(0)
        override fun encodeNotNullMark() = out.write(1)
        override fun beginCollection(descriptor: SerialDescriptor, collectionSize: Int): kotlinx.serialization.encoding.CompositeEncoder {
            int(collectionSize); return this
        }
    }

    private class Reader(private val buf: ByteBuffer) : AbstractDecoder() {
        override val serializersModule: SerializersModule = EmptySerializersModule()
        private var elementIndex = 0

        override fun decodeInt(): Int = buf.getInt()
        override fun decodeLong(): Long = buf.getLong()
        override fun decodeBoolean(): Boolean = buf.get() != 0.toByte()
        override fun decodeByte(): Byte = buf.get()
        override fun decodeShort(): Short = throw UnsupportedOperationException("unit codec: no Short")
        override fun decodeChar(): Char = throw UnsupportedOperationException("unit codec: no Char")
        override fun decodeFloat(): Float = throw UnsupportedOperationException("unit codec: no Float")
        override fun decodeDouble(): Double = throw UnsupportedOperationException("unit codec: no Double")
        override fun decodeString(): String {
            val n = buf.getInt()
            val slice = buf.slice(buf.position(), n)
            buf.position(buf.position() + n)
            return StandardCharsets.UTF_8.decode(slice).toString()
        }
        override fun decodeEnum(enumDescriptor: SerialDescriptor): Int = buf.getInt()
        override fun decodeNotNullMark(): Boolean = buf.get() != 0.toByte()
        override fun decodeNull(): Nothing? = null
        override fun decodeSequentially(): Boolean = true
        override fun decodeCollectionSize(descriptor: SerialDescriptor): Int = buf.getInt()
        override fun decodeElementIndex(descriptor: SerialDescriptor): Int =
            if (elementIndex < descriptor.elementsCount) elementIndex++ else CompositeDecoder.DECODE_DONE
        override fun beginStructure(descriptor: SerialDescriptor): CompositeDecoder = Reader(buf)
    }
}
```

`decodeSequentially() = true` makes kotlinx read a class's fields in
declaration order without tags; `beginStructure` hands a fresh
`Reader` over the same buffer so a nested record's element index starts
at 0. The writer needs no such care: `AbstractEncoder` calls
`encodeElement` before each field and the default returns `true`.

- [ ] **Step 6: Run the tests**

Run: `./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.runtime.unit.UnitCodecTest'`
Expected: 4 tests, `BUILD SUCCESSFUL`.

- [ ] **Step 7: The runner still starts with the new jar on its path**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records
./nqp/gradlew -p nqp :nqp-runtime:jar syncRuntimeJars generateRunner
ls nqp/build/jvm/share/runtime/ | grep kotlinx
( cd nqp && ./nqp-j-gradle -e 'say("codec-ok")' )
```

Expected: `kotlinx-serialization-core-jvm-1.11.0.jar` listed;
`codec-ok`. If `generateRunner` is not the task name, find it with
`./nqp/gradlew -p nqp tasks --all | grep -i runner`.

- [ ] **Step 8: Commit (nqp tree)**

```bash
STAMP="$(date +%F)T20:35:00+02:00"
git -C nqp add buildSrc/src/main/kotlin/NqpDeps.kt build.gradle.kts nqp-runtime/build.gradle.kts \
  src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitCodec.kt nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitCodecTest.kt
GIT_AUTHOR_DATE=$STAMP GIT_COMMITTER_DATE=$STAMP git -C nqp commit -m "Unit artifact v2, 1/n: the record codec (kotlinx over a ByteBuffer)

kotlinx-serialization-core 1.11.0 joins the runtime jars (NqpDeps, so
the runner and the stage tasks carry it) with the plugin.serialization
compiler plugin on nqp-runtime. UnitCodec is the binary layout: fixed
little-endian ints, length-prefixed UTF-8, a mark byte per nullable, no
tags, so every record decodes from a slice on its own.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: <URL>"
```

Ledger: `Task 2: complete (nqp <hash>; 4 codec tests; runner starts)`.

---

## Task 3: The v2 records, the writer and the store (lazy-loading task 1.2, plus the dispatch table)

**Files:**
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitImage.kt`
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ZipDirectory.kt`
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitImageWriter.kt`
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitStore.kt`
- Test: `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitStoreTest.kt`

**Interfaces:**
- Consumes: `UnitCodec.encode/decode` (Task 2).
- Produces (the names every later task uses):

```kotlin
@Serializable class UnitHeader(
    val unitId: String, val hll: String, val scHandle: String?, val scDesc: String?,
    val serializedCodeRefCount: Int, val mainlineQbid: Int, val entryQbid: Int,
    val deserializeQbid: Int, val loadQbid: Int,
    val blockCount: Int, val programCount: Int, val dispatchSlotCount: Int,
    val names: List<String>,     // per qbid, "" for a gap
    val cuids: List<String?>,    // per qbid, null when the block carries none
    val nestedIds: List<String>,
)
@Serializable class StaticLexValue(val name: String, val scHandle: String, val scIdx: Int, val flags: Int)
@Serializable class BlockRecord(
    val oLex: List<String>, val iLex: List<String>, val nLex: List<String>, val sLex: List<String>,
    val handlers: LongArray,                 // flat: [count, (len, fields...)*], as v1
    val hasExitHandler: Boolean, val isThunk: Boolean,
    val sourceFile: String?, val sourceLine: Int, val sourceLineDelta: Int,
    val sectionRaw: IntArray?, val sectionLine: IntArray?, val sectionFile: List<String>?,
    val staticLex: List<StaticLexValue>,     // this block's rows (v1 kept one global list)
)
class BlockEntry(val name: String, val cuid: String?, val outerQbid: Int, val programIndex: Int, val record: BlockRecord)
class UnitImage(
    val unitId: String, val hll: String, val scHandle: String?, val scDesc: String?,
    val serializedCodeRefCount: Int, val mainlineQbid: Int, val entryQbid: Int,
    val deserializeQbid: Int, val loadQbid: Int,
    val blocks: List<BlockEntry?>,           // per qbid; null = gap
    val programs: List<String>,
    val dispatchCounts: IntArray,            // per program index: its slot count
    val serialized: ByteArray?,              // raw SC bytes; null for a nested unit
    val nested: Map<String, UnitStore>,      // already-encoded nested units, copied entry for entry
    val dispatchSlots: Map<Int, ByteArray> = emptyMap(),   // absolute slot index -> bytes; empty in Phase B
)
object UnitImageWriter {
    fun write(image: UnitImage, out: OutputStream)
    fun bytes(image: UnitImage): ByteArray
}
class UnitStore {
    companion object {
        fun open(path: String): UnitStore                       // one read-only mapping of the file
        fun open(bytes: ByteBuffer, name: String): UnitStore    // a heap image (in-memory units, tests)
        fun isUnit(buf: ByteBuffer): Boolean                    // first local file header names unit.index
        const val INDEX = "unit.index"; const val RECORDS = "unit.records"; const val PROGRAMS = "unit.programs"
        const val SERIALIZED = "unit.serialized"; const val DISPATCH = "unit.dispatch"; const val NESTED_DIR = "nested/"
        const val MAGIC = 0x5550514E; const val VERSION = 2
    }
    val name: String; val header: UnitHeader
    val blockCount: Int; val programCount: Int
    fun programIndex(qbid: Int): Int        // -1 for a gap
    fun outerQbid(qbid: Int): Int           // -1 for none or a gap
    fun blockRecord(qbid: Int): BlockRecord? // decodes the slice; null for a gap
    fun program(idx: Int): String           // UTF-8 decode of the slice
    fun dispatchSlotCount(programIndex: Int): Int
    fun dispatchSlot(programIndex: Int, ordinal: Int): ByteBuffer?   // null when empty or out of range
    val serialized: ByteBuffer?             // read-only slice; the reader sets its own byte order
    fun nested(id: String): UnitStore?      // over nested/<id>.* ; cached per id
    fun entry(name: String): ByteBuffer?    // a raw entry slice (the writer copies nested units with it)
}
```

`unit.index` layout: `Int MAGIC`, `Int VERSION`, `Int headerLength`,
the `UnitHeader` bytes (`UnitCodec`), then three little-endian tables:
the block table (`blockCount` rows of 4 ints: recordOffset,
recordLength, programIndex, outerQbid; a gap is `0, 0, -1, -1`), the
program table (`programCount` rows of 4 ints: offset, length,
firstSlot, slotCount), the dispatch slot table (`dispatchSlotCount`
rows of 2 ints: offset, length; `0, 0` is empty). Tables begin at byte
`12 + headerLength`. `firstSlot` is the prefix sum of `dispatchCounts`.
Every zip entry is STORED; `unit.index` is the first entry; nested units
are `nested/<id>.index`, `.records`, `.programs`, `.dispatch` (no
`.serialized`).

- [ ] **Step 1: Write the failing store test**

`nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitStoreTest.kt`:

```kotlin
package org.raku.nqp.runtime.unit

import java.io.File
import java.nio.ByteBuffer
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.assertFailsWith
import kotlin.test.assertContentEquals

class UnitStoreTest {
    private fun block(name: String, outer: Int, program: Int, olex: List<String> = emptyList(),
                      lex: List<StaticLexValue> = emptyList(), cuid: String? = null) =
        BlockEntry(name, cuid, outer, program, BlockRecord(
            olex, emptyList(), emptyList(), emptyList(), longArrayOf(0), false, false,
            "t.nqp", 3, 0, null, null, null, lex))

    /** qbids 0, 1, 3 live; 2 is a gap; programs 0..2 map to them; program 0 has 2 dispatch slots, 2 has 1. */
    private fun image(nested: Map<String, UnitStore> = emptyMap(), slots: Map<Int, ByteArray> = emptyMap()) = UnitImage(
        "unit-x", "nqp", "sc-x", "desc", 2, 0, -1, 1, 3,
        listOf(block("main", -1, 0, listOf("\$x", "\$y"), listOf(StaticLexValue("\$y", "sc-x", 7, 1))),
               block("deser", 0, 1), null, block("löad 🐪", 0, 2, cuid = "cuid-3")),
        listOf("PROG0 ${"x".repeat(70000)}", "PROG1", "PROG2 ü"),
        intArrayOf(2, 0, 1), byteArrayOf(9, 8, 7), nested, slots)

    @Test fun roundTripsThroughAHeapImage() {
        val s = UnitStore.open(ByteBuffer.wrap(UnitImageWriter.bytes(image())), "<test>")
        assertEquals("unit-x", s.header.unitId)
        assertEquals(4, s.blockCount); assertEquals(3, s.programCount)
        assertEquals(listOf("main", "deser", "", "löad 🐪"), s.header.names)
        assertEquals(listOf(null, null, null, "cuid-3"), s.header.cuids)
        assertEquals(0, s.programIndex(0)); assertEquals(-1, s.programIndex(2)); assertEquals(2, s.programIndex(3))
        assertEquals(-1, s.outerQbid(0)); assertEquals(0, s.outerQbid(3)); assertEquals(-1, s.outerQbid(2))
        assertNull(s.blockRecord(2))
        val r0 = s.blockRecord(0)!!
        assertEquals(listOf("\$x", "\$y"), r0.oLex)
        assertEquals(1, r0.staticLex.size); assertEquals(7, r0.staticLex[0].scIdx)
        assertEquals("t.nqp", s.blockRecord(3)!!.sourceFile)
        assertTrue(s.program(0).startsWith("PROG0 ") && s.program(0).length == 70006)
        assertEquals("PROG2 ü", s.program(2))
        assertContentEquals(byteArrayOf(9, 8, 7), ByteArray(3).also { s.serialized!!.duplicate().get(it) })
    }

    @Test fun dispatchSlotsAreAddressedByProgramAndOrdinalAndEmptyByDefault() {
        val s = UnitStore.open(ByteBuffer.wrap(UnitImageWriter.bytes(image())), "<test>")
        assertEquals(3, s.header.dispatchSlotCount)
        assertEquals(2, s.dispatchSlotCount(0)); assertEquals(0, s.dispatchSlotCount(1)); assertEquals(1, s.dispatchSlotCount(2))
        assertNull(s.dispatchSlot(0, 0)); assertNull(s.dispatchSlot(0, 1)); assertNull(s.dispatchSlot(2, 0))
        assertNull(s.dispatchSlot(0, 2)); assertNull(s.dispatchSlot(1, 0)); assertNull(s.dispatchSlot(9, 0))
    }

    @Test fun aFilledSlotComesBackAsItsBytes() {
        // absolute slot 2 = program 2, ordinal 0
        val s = UnitStore.open(ByteBuffer.wrap(UnitImageWriter.bytes(image(slots = mapOf(2 to byteArrayOf(4, 2))))), "<test>")
        assertNull(s.dispatchSlot(0, 0))
        val slot = s.dispatchSlot(2, 0)!!
        assertContentEquals(byteArrayOf(4, 2), ByteArray(slot.remaining()).also { slot.get(it) })
    }

    @Test fun nestedUnitsAreCopiedEntryForEntry() {
        val inner = UnitStore.open(ByteBuffer.wrap(UnitImageWriter.bytes(UnitImage(
            "inner", "nqp", null, null, 0, 0, -1, -1, -1,
            listOf(block("m", -1, 0)), listOf("P"), intArrayOf(0), null, emptyMap()))), "<inner>")
        val s = UnitStore.open(ByteBuffer.wrap(UnitImageWriter.bytes(image(nested = mapOf("inner" to inner)))), "<test>")
        assertEquals(listOf("inner"), s.header.nestedIds)
        val n = s.nested("inner")!!
        assertEquals("inner", n.header.unitId); assertEquals("P", n.program(0)); assertNull(n.serialized)
        assertTrue(n === s.nested("inner"))
        assertNull(s.nested("nope"))
    }

    @Test fun mapsAFile() {
        val f = File.createTempFile("unit-store", ".jar"); f.deleteOnExit()
        f.outputStream().use { UnitImageWriter.write(image(), it) }
        val s = UnitStore.open(f.path)
        assertEquals("unit-x", s.header.unitId); assertEquals("PROG1", s.program(1))
        assertEquals(f.path, s.name)
        // every entry is stored, and unit.index comes first
        java.util.zip.ZipFile(f).use { z ->
            val entries = z.entries().toList()
            assertEquals(UnitStore.INDEX, entries[0].name)
            entries.forEach { assertEquals(java.util.zip.ZipEntry.STORED, it.method, it.name) }
        }
    }

    @Test fun sniffsTheFirstEntryName() {
        val bytes = UnitImageWriter.bytes(image())
        assertTrue(UnitStore.isUnit(ByteBuffer.wrap(bytes)))
        assertFalse(UnitStore.isUnit(ByteBuffer.wrap(byteArrayOf(0xCA.toByte(), 0xFE.toByte(), 0xBA.toByte(), 0xBE.toByte()))))
        assertFalse(UnitStore.isUnit(ByteBuffer.wrap(ByteArray(10))))
    }

    @Test fun errorsNameTheUnitEntryAndIndex() {
        val bytes = UnitImageWriter.bytes(image())
        val s = UnitStore.open(ByteBuffer.wrap(bytes), "<test>")
        val e1 = assertFailsWith<IllegalStateException> { s.program(3) }
        assertTrue(e1.message!!.contains("unit-x") && e1.message!!.contains("unit.programs") && e1.message!!.contains("3"), e1.message)
        val e2 = assertFailsWith<IllegalStateException> { s.blockRecord(4) }
        assertTrue(e2.message!!.contains("unit.records") && e2.message!!.contains("4"), e2.message)
        val truncated = ByteBuffer.wrap(bytes.copyOf(bytes.size - 40))
        val e3 = assertFailsWith<IllegalStateException> { UnitStore.open(truncated, "<cut>") }
        assertTrue(e3.message!!.contains("<cut>"), e3.message)
        val wrongVersion = bytes.copyOf()
        // the version int follows the magic in unit.index; the index data starts after the 30-byte local header + name
        val dataStart = 30 + UnitStore.INDEX.length
        wrongVersion[dataStart + 4] = 9
        val e4 = assertFailsWith<IllegalStateException> { UnitStore.open(ByteBuffer.wrap(wrongVersion), "<v9>") }
        assertTrue(e4.message!!.contains("version 9"), e4.message)
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.runtime.unit.UnitStoreTest'`
Expected: compilation failure (`UnitImage`, `UnitStore` unresolved).

- [ ] **Step 3: The records and the image**

`nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitImage.kt`: the
classes exactly as the Interfaces block declares them (`@Serializable`
on `UnitHeader`, `StaticLexValue`, `BlockRecord`; plain classes for
`BlockEntry` and `UnitImage`), with this header comment:

```kotlin
/**
 * The unit artifact's records (v2, milestone 7 Phase B). UnitHeader is
 * decoded once at open; a BlockRecord is decoded from its own slice
 * when the block's body is first needed (StaticCodeInfo.ensureBody);
 * the block's identity (name, cuid, outer, program index) lives in the
 * header's per-qbid lists and the index's block table, so a shell costs
 * no record decode. UnitImage is what the writer takes: the compiler's
 * record (RecordReader) or a transcoded v1 record, in memory.
 */
```

- [ ] **Step 4: The central-directory parser**

`nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ZipDirectory.kt`:

```kotlin
package org.raku.nqp.runtime.unit

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.StandardCharsets

/** The stored entries of a zip, by name: data offset and size within the
 *  buffer. Reads the end-of-central-directory record and the central
 *  directory only; refuses any entry that is not STORED, since a slice
 *  of a deflated entry is not its data. Zip64 is not supported (no unit
 *  artifact approaches 4 GB). */
internal object ZipDirectory {
    class Entry(@JvmField val offset: Int, @JvmField val size: Int)

    private const val EOCD_SIG = 0x06054b50
    private const val CEN_SIG = 0x02014b50
    private const val LOC_SIG = 0x04034b50

    fun read(buf0: ByteBuffer, name: String): LinkedHashMap<String, Entry> {
        val buf = buf0.duplicate().order(ByteOrder.LITTLE_ENDIAN)
        val end = buf.limit()
        var eocd = -1
        var p = end - 22
        val floor = maxOf(0, end - 22 - 0xFFFF)
        while (p >= floor) { if (buf.getInt(p) == EOCD_SIG) { eocd = p; break }; p-- }
        if (eocd < 0) throw IllegalStateException("unit artifact $name: no end-of-central-directory record")
        val count = buf.getShort(eocd + 10).toInt() and 0xFFFF
        var cen = buf.getInt(eocd + 16)
        val out = LinkedHashMap<String, Entry>(count * 2)
        repeat(count) {
            if (cen + 46 > end || buf.getInt(cen) != CEN_SIG)
                throw IllegalStateException("unit artifact $name: bad central directory entry at $cen")
            val method = buf.getShort(cen + 10).toInt() and 0xFFFF
            val csize = buf.getInt(cen + 20); val usize = buf.getInt(cen + 24)
            val nameLen = buf.getShort(cen + 28).toInt() and 0xFFFF
            val extraLen = buf.getShort(cen + 30).toInt() and 0xFFFF
            val commentLen = buf.getShort(cen + 32).toInt() and 0xFFFF
            val loc = buf.getInt(cen + 42)
            val entryName = StandardCharsets.UTF_8.decode(buf.slice(cen + 46, nameLen)).toString()
            if (method != 0 || csize != usize)
                throw IllegalStateException("unit artifact $name: entry $entryName is not stored (method $method)")
            if (loc + 30 > end || buf.getInt(loc) != LOC_SIG)
                throw IllegalStateException("unit artifact $name: entry $entryName has a bad local header at $loc")
            val locName = buf.getShort(loc + 26).toInt() and 0xFFFF
            val locExtra = buf.getShort(loc + 28).toInt() and 0xFFFF
            val data = loc + 30 + locName + locExtra
            if (data + usize > end)
                throw IllegalStateException("unit artifact $name: entry $entryName runs past the end ($data + $usize > $end)")
            out[entryName] = Entry(data, usize)
            cen += 46 + nameLen + extraLen + commentLen
        }
        return out
    }
}
```

- [ ] **Step 5: The writer**

`nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitImageWriter.kt`:

```kotlin
package org.raku.nqp.runtime.unit

import java.io.ByteArrayOutputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.StandardCharsets
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Writes a UnitImage as a stored zip: unit.index first (the sniff reads
 *  the first local header), then records, programs, serialized (when
 *  present), dispatch, and each nested unit's four entries copied from
 *  its store. Stored, not deflated: the reader slices one mapping. */
object UnitImageWriter {
    fun bytes(image: UnitImage): ByteArray = ByteArrayOutputStream(1 shl 16).also { write(image, it) }.toByteArray()

    fun write(image: UnitImage, out: OutputStream) {
        ZipOutputStream(out).use { z ->
            z.setMethod(ZipOutputStream.STORED)
            val e = encode(image)
            put(z, UnitStore.INDEX, e.index)
            put(z, UnitStore.RECORDS, e.records)
            put(z, UnitStore.PROGRAMS, e.programs)
            image.serialized?.let { put(z, UnitStore.SERIALIZED, it) }
            put(z, UnitStore.DISPATCH, e.dispatch)
            for ((id, n) in image.nested) {
                for (suffix in listOf(".index", ".records", ".programs", ".dispatch")) {
                    val entry = n.entry("unit$suffix")
                        ?: throw IllegalStateException("unit ${image.unitId}: nested unit $id carries no unit$suffix")
                    put(z, UnitStore.NESTED_DIR + id + suffix, ByteArray(entry.remaining()).also { entry.duplicate().get(it) })
                }
            }
        }
    }

    private fun put(z: ZipOutputStream, name: String, bytes: ByteArray) {
        val entry = ZipEntry(name)
        entry.method = ZipEntry.STORED
        entry.size = bytes.size.toLong(); entry.compressedSize = bytes.size.toLong()
        entry.crc = CRC32().also { it.update(bytes) }.value
        z.putNextEntry(entry); z.write(bytes); z.closeEntry()
    }

    private class Encoded(val index: ByteArray, val records: ByteArray, val programs: ByteArray, val dispatch: ByteArray)

    private fun encode(image: UnitImage): Encoded {
        val nb = image.blocks.size
        val np = image.programs.size
        require(image.dispatchCounts.size == np) { "unit ${image.unitId}: ${image.dispatchCounts.size} dispatch counts for $np programs" }
        // records, back to back
        val records = ByteArrayOutputStream(1 shl 16)
        val blockRows = IntArray(nb * 4)
        for (q in 0 until nb) {
            val b = image.blocks[q]
            if (b == null) { blockRows[q * 4] = 0; blockRows[q * 4 + 1] = 0; blockRows[q * 4 + 2] = -1; blockRows[q * 4 + 3] = -1; continue }
            require(b.programIndex in 0 until np) { "unit ${image.unitId}: block $q names program ${b.programIndex} of $np" }
            require(b.outerQbid < nb) { "unit ${image.unitId}: block $q names outer qbid ${b.outerQbid} beyond the table" }
            val bytes = UnitCodec.encode(BlockRecord.serializer(), b.record)
            blockRows[q * 4] = records.size(); blockRows[q * 4 + 1] = bytes.size
            blockRows[q * 4 + 2] = b.programIndex; blockRows[q * 4 + 3] = b.outerQbid
            records.write(bytes)
        }
        // programs, raw UTF-8 back to back
        val programs = ByteArrayOutputStream(1 shl 16)
        val programRows = IntArray(np * 4)
        var slot = 0
        for (i in 0 until np) {
            val bytes = image.programs[i].toByteArray(StandardCharsets.UTF_8)
            programRows[i * 4] = programs.size(); programRows[i * 4 + 1] = bytes.size
            programRows[i * 4 + 2] = slot; programRows[i * 4 + 3] = image.dispatchCounts[i]
            slot += image.dispatchCounts[i]
            programs.write(bytes)
        }
        val nslots = slot
        // dispatch slots: empty unless the image fills one
        val dispatch = ByteArrayOutputStream()
        val slotRows = IntArray(nslots * 2)
        for ((s, bytes) in image.dispatchSlots) {
            require(s in 0 until nslots) { "unit ${image.unitId}: dispatch slot $s of $nslots" }
            slotRows[s * 2] = dispatch.size(); slotRows[s * 2 + 1] = bytes.size
            dispatch.write(bytes)
        }
        val header = UnitHeader(image.unitId, image.hll, image.scHandle, image.scDesc,
            image.serializedCodeRefCount, image.mainlineQbid, image.entryQbid, image.deserializeQbid, image.loadQbid,
            nb, np, nslots,
            image.blocks.map { it?.name ?: "" }, image.blocks.map { it?.cuid },
            image.nested.keys.toList())
        val headerBytes = UnitCodec.encode(UnitHeader.serializer(), header)
        val index = ByteBuffer.allocate(12 + headerBytes.size + 4 * (blockRows.size + programRows.size + slotRows.size))
            .order(ByteOrder.LITTLE_ENDIAN)
        index.putInt(UnitStore.MAGIC).putInt(UnitStore.VERSION).putInt(headerBytes.size).put(headerBytes)
        for (v in blockRows) index.putInt(v)
        for (v in programRows) index.putInt(v)
        for (v in slotRows) index.putInt(v)
        return Encoded(index.array(), records.toByteArray(), programs.toByteArray(), dispatch.toByteArray())
    }
}
```

- [ ] **Step 6: The store**

`nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitStore.kt`:

```kotlin
package org.raku.nqp.runtime.unit

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel
import java.nio.charset.StandardCharsets
import java.nio.file.Path
import java.nio.file.StandardOpenOption
import java.util.concurrent.ConcurrentHashMap

/**
 * A unit artifact, opened: one read-only mapping (or one heap buffer)
 * sliced per stored zip entry, the index decoded, everything else read
 * on demand by index -- a block's record when its body is first needed,
 * a program when it is first materialized, a dispatch slot when its
 * site first misses (Phase C). Immutable and shared: the eval server
 * keeps one per path across runs (UnitLoader.stores). A file replaced
 * on disk while mapped can fault the process; the server is restarted
 * after a rebuild, as it already had to be.
 */
class UnitStore private constructor(
    @JvmField val name: String,
    private val entries: Map<String, ByteBuffer>,      // each slice: position 0, LITTLE_ENDIAN
    private val prefix: String,                         // "unit" or "nested/<id>"
) {
    companion object {
        const val INDEX = "unit.index"; const val RECORDS = "unit.records"; const val PROGRAMS = "unit.programs"
        const val SERIALIZED = "unit.serialized"; const val DISPATCH = "unit.dispatch"; const val NESTED_DIR = "nested/"
        const val MAGIC = 0x5550514E   // "NQPU"
        const val VERSION = 2
        private const val LOC_SIG = 0x04034b50

        @JvmStatic
        fun open(path: String): UnitStore {
            val mapped = FileChannel.open(Path.of(path), StandardOpenOption.READ).use { ch ->
                ch.map(FileChannel.MapMode.READ_ONLY, 0, ch.size())
            }
            return open(mapped, path)
        }

        @JvmStatic
        fun open(bytes: ByteBuffer, name: String): UnitStore {
            val whole = bytes.duplicate().order(ByteOrder.LITTLE_ENDIAN)
            val dir = ZipDirectory.read(whole, name)
            val slices = HashMap<String, ByteBuffer>(dir.size * 2)
            for ((n, e) in dir) slices[n] = whole.slice(e.offset, e.size).order(ByteOrder.LITTLE_ENDIAN)
            return UnitStore(name, slices, "unit")
        }

        /** True when the first local file header names unit.index: the
         *  writer puts it first, so the sniff reads 30 + 10 bytes. */
        @JvmStatic
        fun isUnit(buffer: ByteBuffer): Boolean {
            val d = buffer.duplicate().order(ByteOrder.LITTLE_ENDIAN)
            val base = d.position()
            if (d.remaining() < 30 + INDEX.length || d.getInt(base) != LOC_SIG) return false
            val nameLen = d.getShort(base + 26).toInt() and 0xFFFF
            if (nameLen != INDEX.length) return false
            for (i in INDEX.indices) if ((d.get(base + 30 + i).toInt() and 0xFF) != INDEX[i].code) return false
            return true
        }
    }

    private val index: ByteBuffer = entries["$prefix.index"]
        ?: throw IllegalStateException("unit artifact $name: no $prefix.index entry")
    @JvmField val header: UnitHeader
    private val tables: Int          // byte offset of the block table within the index
    private val programTable: Int
    private val slotTable: Int
    private val nestedStores = ConcurrentHashMap<String, UnitStore>()

    init {
        if (index.remaining() < 12) throw IllegalStateException("unit artifact $name: $prefix.index is ${index.remaining()} bytes")
        val magic = index.getInt(0); val version = index.getInt(4)
        if (magic != MAGIC) throw IllegalStateException("unit artifact $name: bad magic ${Integer.toHexString(magic)}")
        if (version != VERSION) throw IllegalStateException("unit artifact $name: version $version, this runtime reads $VERSION")
        val headerLen = index.getInt(8)
        header = try { UnitCodec.decode(UnitHeader.serializer(), index.slice(12, headerLen)) }
                 catch (e: Exception) { throw IllegalStateException("unit artifact $name: header does not decode: ${e.message}", e) }
        tables = 12 + headerLen
        programTable = tables + 16 * header.blockCount
        slotTable = programTable + 16 * header.programCount
        val need = slotTable + 8 * header.dispatchSlotCount
        if (index.remaining() < need) throw IllegalStateException("unit artifact $name: $prefix.index holds ${index.remaining()} bytes, tables need $need")
        if (header.names.size != header.blockCount || header.cuids.size != header.blockCount)
            throw IllegalStateException("unit artifact $name: ${header.names.size} names / ${header.cuids.size} cuids for ${header.blockCount} blocks")
        if (header.serializedCodeRefCount > header.blockCount)
            throw IllegalStateException("unit ${header.unitId}: ${header.serializedCodeRefCount} serialized code refs, table of ${header.blockCount}")
    }

    val blockCount: Int get() = header.blockCount
    val programCount: Int get() = header.programCount

    private fun blockRow(qbid: Int, field: Int): Int {
        if (qbid < 0 || qbid >= header.blockCount)
            throw IllegalStateException("unit ${header.unitId}: $prefix.records index $qbid of ${header.blockCount}")
        return index.getInt(tables + 16 * qbid + 4 * field)
    }
    fun programIndex(qbid: Int): Int = blockRow(qbid, 2)
    fun outerQbid(qbid: Int): Int = blockRow(qbid, 3)

    fun blockRecord(qbid: Int): BlockRecord? {
        val len = blockRow(qbid, 1)
        if (len == 0) return null
        val off = blockRow(qbid, 0)
        val records = entry(RECORDS) ?: throw IllegalStateException("unit ${header.unitId}: no $prefix.records entry")
        if (off + len > records.remaining())
            throw IllegalStateException("unit ${header.unitId}: $prefix.records index $qbid at $off+$len past ${records.remaining()}")
        return try { UnitCodec.decode(BlockRecord.serializer(), records.slice(off, len)) }
               catch (e: Exception) { throw IllegalStateException("unit ${header.unitId}: $prefix.records index $qbid does not decode: ${e.message}", e) }
    }

    private fun programRow(idx: Int, field: Int): Int {
        if (idx < 0 || idx >= header.programCount)
            throw IllegalStateException("unit ${header.unitId}: $prefix.programs index $idx of ${header.programCount}")
        return index.getInt(programTable + 16 * idx + 4 * field)
    }
    fun program(idx: Int): String {
        val off = programRow(idx, 0); val len = programRow(idx, 1)
        val programs = entry(PROGRAMS) ?: throw IllegalStateException("unit ${header.unitId}: no $prefix.programs entry")
        if (off + len > programs.remaining())
            throw IllegalStateException("unit ${header.unitId}: $prefix.programs index $idx at $off+$len past ${programs.remaining()}")
        return StandardCharsets.UTF_8.decode(programs.slice(off, len)).toString()
    }

    fun dispatchSlotCount(programIndex: Int): Int =
        if (programIndex < 0 || programIndex >= header.programCount) 0 else programRow(programIndex, 3)
    fun dispatchSlot(programIndex: Int, ordinal: Int): ByteBuffer? {
        if (programIndex < 0 || programIndex >= header.programCount) return null
        if (ordinal < 0 || ordinal >= programRow(programIndex, 3)) return null
        val slot = programRow(programIndex, 2) + ordinal
        val len = index.getInt(slotTable + 8 * slot + 4)
        if (len == 0) return null
        val off = index.getInt(slotTable + 8 * slot)
        val dispatch = entry(DISPATCH) ?: throw IllegalStateException("unit ${header.unitId}: no $prefix.dispatch entry")
        if (off + len > dispatch.remaining())
            throw IllegalStateException("unit ${header.unitId}: $prefix.dispatch slot $slot at $off+$len past ${dispatch.remaining()}")
        return dispatch.slice(off, len).order(ByteOrder.LITTLE_ENDIAN)
    }

    val serialized: ByteBuffer? get() = entry(SERIALIZED)

    /** A raw entry of this unit (unit.index ... unit.dispatch), a fresh
     *  duplicate at position 0. */
    fun entry(unitEntryName: String): ByteBuffer? =
        entries[if (prefix == "unit") unitEntryName else prefix + unitEntryName.removePrefix("unit")]?.duplicate()

    fun nested(id: String): UnitStore? {
        if (id !in header.nestedIds) return null
        return nestedStores.computeIfAbsent(id) { UnitStore(name, entries, NESTED_DIR + it) }
    }
}
```

`entry()` for a nested store turns `"unit.records"` into
`"nested/<id>.records"`. A nested store's `serialized` is null because
the writer never emits `nested/<id>.serialized`.

- [ ] **Step 7: Run the tests**

Run: `./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.runtime.unit.UnitStoreTest'`
Expected: 7 tests pass. If `errorsNameTheUnitEntryAndIndex`'s version
case fails on the byte offset, dump the first 60 bytes of the zip and
fix the test's `dataStart` from what you see (a `ZipOutputStream`
STORED entry has no extra field, so 30 + name length should be right;
assert, don't guess).

- [ ] **Step 8: Commit (nqp tree)**

Stage the four new sources and the test; commit with the evening stamp
and the trailers, message:

```
Unit artifact v2, 2/n: the records, the stored-zip writer and the mapped store

unit.index (header + fixed-width block, program and dispatch-slot
tables), unit.records (one BlockRecord slice per block, its static
lexical rows inside), unit.programs (raw UTF-8 by index),
unit.serialized (raw SC bytes), unit.dispatch (every slot empty until
Phase C), nested units as the same four entries under nested/<id>. All
stored; UnitStore slices one mapping and decodes by index. Nothing
consumes it yet.
```

Ledger: `Task 3: complete (nqp <hash>; 7 store tests)`.

---

## Task 4: Lazy bodies on `StaticCodeInfo` (lazy-loading task 1.4, layer 2; task 1.1's verdicts applied)

**Files:**
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/StaticBodySource.kt`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/StaticCodeInfo.kt` (whole file)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CodeRef.kt:49-60` (a shell constructor)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CallFrame.kt:40,320`, `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/Syscalls.kt:396,409` (ruling 10)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/ArgsExpectation.java`, `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java`, `NqpCodeEngine.java`, `NqpRaw.java`, `NqpRootNode.java` (getter calls)
- Test: `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/StaticCodeInfoLazyTest.kt`, `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/ProgramUnitTestSupport.kt`

**Interfaces:**
- Consumes: nothing from Tasks 2-3 (this task is independent of the format).
- Produces:

```kotlin
interface StaticBodySource {
    /** Fills sci's body fields through their setters, then calls sci.finishBody();
     *  runs once, under sci's monitor, on the first read of any body field. */
    fun fill(sci: StaticCodeInfo)
}
// StaticCodeInfo
constructor(compUnit: CompilationUnit, mh: MethodHandle, uniqueId: String?, argsExpectation: Short,
            staticCode: SixModelObject?, source: StaticBodySource)      // a shell
fun ensureBody()                       // one volatile read on the fast path
internal fun finishBody()              // allocates oLexStatic/oLexStaticFlags, spins mh/mhResume
// CodeRef
constructor(compUnit: CompilationUnit, mh: MethodHandle, name: String?, uniqueId: String?,
            argsExpectation: Short, source: StaticBodySource)          // a shell
```

Shell (raw) fields, unchanged as `@JvmField`: `compUnit`, `uniqueId`,
`programIndex`, `unitEntry`, `methodName`, `argsExpectation`,
`outerStaticInfo`, `staticCode`, `liveInvocations`, `engineTarget`,
`priorInvocation`, `contextsAwaitingOuter`. Body fields, now Kotlin
properties whose getter calls `ensureBody()` (Java sees `getX()`/`setX()`):
`mh`, `mhResume`, `oLexicalNames`, `iLexicalNames`, `nLexicalNames`,
`sLexicalNames`, `oLexStatic`, `oLexStaticFlags`, `handlers`,
`hasExitHandler`, `isThunk`, `sourceFile`, `sourceLine`,
`sourceLineDelta`, `sourceSectionRaw`, `sourceSectionLine`,
`sourceSectionFile`. The four `*LexicalMap`s become `private`.

- [ ] **Step 1: Ruling 10 first — identity by `staticInfo`**

Four sites test "a frame of that static block" by handle identity:

```
nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CallFrame.kt:40    (outerFor)
nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CallFrame.kt:320   (the auto-close constructor)
nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/Syscalls.kt:396   (try-capture-lex)
nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/Syscalls.kt:409   (try-capture-lex-callers)
```

Each has the shape `f.codeRef.staticInfo.mh === wanted.mh && f.codeRef.staticInfo.compUnit === wanted.compUnit`
(read the exact expression; the variable names differ). Replace each
with `f.codeRef.staticInfo === wanted` (the `StaticCodeInfo` object is
one per block and shared by every clone of its `CodeRef`, so identity of
the info is identity of the block; `RakOps.kt:686,688,742` already test
it this way). Add above the first one, in `outerFor`:

```kotlin
        // Identity of the static info, not of its bound handle: the handle
        // is part of the body (spun on first need, milestone 7 Phase B) and
        // this search runs on blocks that may never be entered.
```

Run: `./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars`
then `( cd nqp && ./nqp-j-gradle -e 'my $x := 1; my sub f() { $x + 1 }; say(f())' )`
Expected: `2`.

- [ ] **Step 2: Write the failing lazy test**

`nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/StaticCodeInfoLazyTest.kt`.
`ProgramUnitTestSupport.unit()` is a small test-only helper you add
next to `ProgramUnitTest.kt` (same package `org.raku.nqp.runtime.unit`,
file `ProgramUnitTestSupport.kt`) that returns the `CompilationUnit`
`ProgramUnitTest` already constructs in its fixture (read that file; at
this task it is still a v1 `ProgramUnit` over a `UnitRecord`, and any
instance will do since the shell only holds the reference).

```kotlin
package org.raku.nqp.runtime

import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.raku.nqp.runtime.unit.ProgramEntry
import org.raku.nqp.runtime.unit.ProgramUnitTestSupport

class StaticCodeInfoLazyTest {
    private class Source(val names: Array<String>?) : StaticBodySource {
        val fills = AtomicInteger()
        override fun fill(sci: StaticCodeInfo) {
            fills.incrementAndGet()
            sci.oLexicalNames = names
            sci.handlers = arrayOf(longArrayOf(1, 2, 3))
            sci.hasExitHandler = true
            sci.sourceFile = "lazy.nqp"; sci.sourceLine = 42
            sci.finishBody()
        }
    }

    private fun shell(src: Source): CodeRef =
        CodeRef(ProgramUnitTestSupport.unit(), ProgramEntry.ENTER, "f", "cuid-f", ArgsExpectation.USE_BINDER, src)

    @Test fun shellFieldsDoNotFill() {
        val src = Source(arrayOf("\$a"))
        val sci = shell(src).staticInfo
        sci.programIndex = 3; sci.methodName = "qb_3"
        assertEquals(3, sci.programIndex); assertEquals("qb_3", sci.methodName)
        assertEquals(ArgsExpectation.USE_BINDER, sci.argsExpectation)
        assertEquals("cuid-f", sci.uniqueId)
        assertNull(sci.outerStaticInfo); assertNull(sci.engineTarget)
        assertEquals(0, sci.liveInvocations.get())
        assertEquals(0, src.fills.get())
    }

    @Test fun firstBodyReadFillsOnceAndSpinsTheHandles() {
        val src = Source(arrayOf("\$a", "\$b"))
        val sci = shell(src).staticInfo
        assertEquals(0, src.fills.get())
        assertEquals(1, sci.oTryGetLexicalIdx("\$b"))
        assertEquals(1, src.fills.get())
        assertEquals(2, sci.oLexStatic!!.size); assertEquals(2, sci.oLexStaticFlags!!.size)
        assertTrue(sci.hasExitHandler); assertEquals("lazy.nqp", sci.sourceFile); assertEquals(42, sci.sourceLine)
        assertEquals(4, sci.mh.type().parameterCount())      // ENTER minus the resume slot
        assertNotNull(sci.mhResume)
        assertEquals(1, src.fills.get())
        sci.sourceLine; sci.handlers; sci.mh
        assertEquals(1, src.fills.get())
    }

    @Test fun racingReadersFillOnce() {
        val src = Source(arrayOf("\$a"))
        val sci = shell(src).staticInfo
        val go = CountDownLatch(1)
        val threads = (1..8).map { Thread { go.await(); sci.oLexicalNames } }
        threads.forEach { it.start() }; go.countDown(); threads.forEach { it.join() }
        assertEquals(1, src.fills.get())
    }

    @Test fun eagerConstructorIsReadyAtOnce() {
        val cr = CodeRef(ProgramUnitTestSupport.unit(), ProgramEntry.ENTER, "g", "cuid-g",
            arrayOf("\$x"), null, null, null, null, ArgsExpectation.USE_BINDER)
        assertEquals(1, cr.staticInfo.oLexStatic!!.size)
        assertEquals(4, cr.staticInfo.mh.type().parameterCount())
    }

    @Test fun cloneFillsFirst() {
        val src = Source(arrayOf("\$a"))
        val sci = shell(src).staticInfo
        val c = sci.clone()
        assertEquals(1, src.fills.get())
        assertEquals(1, c.oLexStatic!!.size)
        assertTrue(c.oLexStatic !== sci.oLexStatic)
        c.oLexicalNames; assertEquals(1, src.fills.get())
    }
}
```

- [ ] **Step 3: Run it to see it fail**

Run: `./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.runtime.StaticCodeInfoLazyTest'`
Expected: compilation failure (`StaticBodySource`, the shell constructor).

- [ ] **Step 4: The interface**

`nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/StaticBodySource.kt`:

```kotlin
package org.raku.nqp.runtime

/**
 * Where a lazy StaticCodeInfo gets its body from (milestone 7 Phase B,
 * lazy-loading layer 2). ProgramUnit implements it per block over the
 * block's record slice. fill() sets the body fields through their
 * setters (which never trigger a fill), calls finishBody(), and then
 * applies or queues the block's static lexical values. It runs once,
 * under the info's monitor, on the first read of any body field.
 */
interface StaticBodySource {
    fun fill(sci: StaticCodeInfo)
}
```

- [ ] **Step 5: Rewrite `StaticCodeInfo`**

Replace the class header and the field block of
`nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/StaticCodeInfo.kt` (keep
the `*TryGetLexicalIdx` methods and `sourceSectionFor`, adding
`ensureBody()` as their first statement and reading the `_`-backed
fields; keep every KDoc that still applies):

```kotlin
class StaticCodeInfo private constructor(
    /** The compilation unit where the code lives. */
    @JvmField var compUnit: CompilationUnit,
    mh: MethodHandle,
    /** The compilation-unit unique ID of the routine (from QAST cuuid). */
    @JvmField var uniqueId: String?,
    /** Static code object (base of any clones). */
    @JvmField var staticCode: SixModelObject?,
    /** The expected arguments needed to invoke the method handle. Read on
     *  the dispatch path before any body is needed, so never lazy. */
    @JvmField var argsExpectation: Short,
    private val bodySource: StaticBodySource?,
) : Cloneable {
    /** The eager constructor: the adaptor and KnowHOW blocks, and the
     *  clone road. Everything is present at construction. */
    constructor(compUnit: CompilationUnit, mh: MethodHandle, uniqueId: String?,
                oLexicalNames: Array<String>?, iLexicalNames: Array<String>?,
                nLexicalNames: Array<String>?, sLexicalNames: Array<String>?,
                handlers: Array<LongArray>?, staticCode: SixModelObject?, argsExpectation: Short)
        : this(compUnit, mh, uniqueId, staticCode, argsExpectation, null) {
        _oLexicalNames = oLexicalNames; _iLexicalNames = iLexicalNames
        _nLexicalNames = nLexicalNames; _sLexicalNames = sLexicalNames
        _handlers = handlers
        finishBody()
        bodyReady = true
    }

    /** The shell constructor (the artifact road): identity now, the body
     *  from [source] on first need. */
    constructor(compUnit: CompilationUnit, mh: MethodHandle, uniqueId: String?,
                argsExpectation: Short, staticCode: SixModelObject?, source: StaticBodySource)
        : this(compUnit, mh, uniqueId, staticCode, argsExpectation, source)

    // ---- the body: filled once, read through ensureBody() ----

    @Volatile private var bodyReady = false

    /** One volatile read on the fast path; the slow path fills under the
     *  monitor. Every body getter calls this, so no caller can see a shell
     *  by mistake -- the failure mode lazy-loading task 1.1 surveyed. */
    fun ensureBody() { if (!bodyReady) fillBody() }

    @Synchronized private fun fillBody() {
        if (bodyReady) return
        val src = bodySource ?: throw IllegalStateException("StaticCodeInfo ${uniqueId ?: methodName}: no body and no source")
        src.fill(this)
        bodyReady = true
    }

    /** Allocates the static-lexical arrays from the lexical names and
     *  spins the two bound handles from the base handle; the tail of the
     *  old init block. A source calls it after setting the name arrays. */
    internal fun finishBody() {
        _oLexicalNames?.let {
            _oLexStatic = arrayOfNulls(it.size)
            _oLexStaticFlags = ByteArray(it.size)
        }
        val base = _mh
        val t = base.type()
        if (t.parameterCount() == 5 && t.parameterType(4) == ResumeStatus.Frame::class.java) {
            _mhResume = MethodHandles.insertArguments(base, 0, null, null, null, null)
            _mh = MethodHandles.insertArguments(base, 4, null as Any?)
        }
        else if (t.parameterCount() >= 4 && t.parameterType(3) == ResumeStatus.Frame::class.java) {
            var resume = MethodHandles.insertArguments(base, 0, null, null, null)
            when (argsExpectation) {
                ArgsExpectation.USE_BINDER -> resume = MethodHandles.insertArguments(resume, 1, null as Any?)
                ArgsExpectation.NO_ARGS -> { }
                ArgsExpectation.OBJ -> resume = MethodHandles.insertArguments(resume, 1, null as SixModelObject?)
                ArgsExpectation.OBJ_OBJ -> resume = MethodHandles.insertArguments(resume, 1, null as SixModelObject?, null as SixModelObject?)
                else -> throw RuntimeException("Unhandled ArgsExpectation in StaticCodeInfo")
            }
            _mhResume = resume
            _mh = MethodHandles.insertArguments(base, 3, null as Any?)
        }
    }

    private var _mh: MethodHandle = mh
    /** Method handle for the code ref (bound; the body). */
    var mh: MethodHandle
        get() { ensureBody(); return _mh }
        set(v) { _mh = v }
    private var _mhResume: MethodHandle? = null
    var mhResume: MethodHandle?
        get() { ensureBody(); return _mhResume }
        set(v) { _mhResume = v }

    private var _oLexicalNames: Array<String>? = null
    var oLexicalNames: Array<String>?
        get() { ensureBody(); return _oLexicalNames }
        set(v) { _oLexicalNames = v }
    private var _iLexicalNames: Array<String>? = null
    var iLexicalNames: Array<String>?
        get() { ensureBody(); return _iLexicalNames }
        set(v) { _iLexicalNames = v }
    private var _nLexicalNames: Array<String>? = null
    var nLexicalNames: Array<String>?
        get() { ensureBody(); return _nLexicalNames }
        set(v) { _nLexicalNames = v }
    private var _sLexicalNames: Array<String>? = null
    var sLexicalNames: Array<String>?
        get() { ensureBody(); return _sLexicalNames }
        set(v) { _sLexicalNames = v }
    private var _handlers: Array<LongArray>? = null
    var handlers: Array<LongArray>?
        get() { ensureBody(); return _handlers }
        set(v) { _handlers = v }
    private var _oLexStatic: Array<SixModelObject?>? = null
    var oLexStatic: Array<SixModelObject?>?
        get() { ensureBody(); return _oLexStatic }
        set(v) { _oLexStatic = v }
    private var _oLexStaticFlags: ByteArray? = null
    var oLexStaticFlags: ByteArray?
        get() { ensureBody(); return _oLexStaticFlags }
        set(v) { _oLexStaticFlags = v }
    private var _hasExitHandler = false
    var hasExitHandler: Boolean
        get() { ensureBody(); return _hasExitHandler }
        set(v) { _hasExitHandler = v }
    private var _isThunk = false
    var isThunk: Boolean
        get() { ensureBody(); return _isThunk }
        set(v) { _isThunk = v }
    private var _sourceFile: String? = null
    var sourceFile: String?
        get() { ensureBody(); return _sourceFile }
        set(v) { _sourceFile = v }
    private var _sourceLine = 0
    var sourceLine: Int
        get() { ensureBody(); return _sourceLine }
        set(v) { _sourceLine = v }
    private var _sourceLineDelta = 0
    var sourceLineDelta: Int
        get() { ensureBody(); return _sourceLineDelta }
        set(v) { _sourceLineDelta = v }
    private var _sourceSectionRaw: IntArray? = null
    var sourceSectionRaw: IntArray?
        get() { ensureBody(); return _sourceSectionRaw }
        set(v) { _sourceSectionRaw = v }
    private var _sourceSectionLine: IntArray? = null
    var sourceSectionLine: IntArray?
        get() { ensureBody(); return _sourceSectionLine }
        set(v) { _sourceSectionLine = v }
    private var _sourceSectionFile: Array<String>? = null
    var sourceSectionFile: Array<String>?
        get() { ensureBody(); return _sourceSectionFile }
        set(v) { _sourceSectionFile = v }

    // ---- the shell: identity and run-time state, plain fields ----
    // (liveInvocations, engineTarget, programIndex, unitEntry, methodName,
    //  outerStaticInfo, priorInvocation, contextsAwaitingOuter: unchanged,
    //  their KDocs kept as they were)
```

Then: the four `*LexicalMap` fields become `private var`; `clone()` becomes:

```kotlin
    public override fun clone(): StaticCodeInfo {
        ensureBody()   // a clone is always ready: it must never fill again from a source it does not own
        try {
            val result = super.clone() as StaticCodeInfo
            result._oLexStatic?.let {
                result._oLexStatic = it.clone()
                result._oLexStaticFlags = result._oLexStaticFlags!!.clone()
            }
            return result
        }
        catch (e: Exception) { throw RuntimeException(e) }
    }
```

(`bodyReady` is copied as `true` by `super.clone()`, and `bodySource`
along with it is harmless: `fillBody` is never reached.)

- [ ] **Step 6: The `CodeRef` shell constructor**

`nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CodeRef.kt`, after the
existing constructor at `:49-60`:

```kotlin
    /** A shell (the artifact road): identity now, the body from [source]
     *  on first need; see StaticCodeInfo. */
    constructor(compUnit: CompilationUnit, mh: MethodHandle, name: String?, uniqueId: String?,
                argsExpectation: Short, source: StaticBodySource) {
        this.staticInfo = StaticCodeInfo(compUnit, mh, uniqueId, argsExpectation, this, source)
        this.name = name
    }
```

- [ ] **Step 7: Java readers use the getters**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records
grep -n -E '\.(mh|mhResume|oLexicalNames|iLexicalNames|nLexicalNames|sLexicalNames|oLexStatic|oLexStaticFlags|handlers|hasExitHandler|isThunk|sourceFile|sourceLine|sourceLineDelta|sourceSectionRaw|sourceSectionLine|sourceSectionFile)\b' \
  nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/ArgsExpectation.java \
  nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java \
  nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpCodeEngine.java \
  nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRaw.java \
  nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java
```

For every hit whose receiver is a `StaticCodeInfo` (not a `CallFrame`
or a handler entry with a field of the same name), change `x.field` to
`x.getField()` (Kotlin's getter name: `mh` → `getMh()`, `oLexicalNames`
→ `getOLexicalNames()`, `isThunk` → `isThunk()` — Kotlin keeps the
`is` prefix for a Boolean property named `isThunk` — `hasExitHandler`
→ `getHasExitHandler()`), and an assignment `x.field = v` to
`x.setField(v)`. Kotlin readers need no change: property syntax is the
same. `tc.handlers` in `ExceptionHandling.kt` is a `ThreadContext`
field, not this one.

- [ ] **Step 8: Build, run the tests, run the old fixtures**

Run: `./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.runtime.StaticCodeInfoLazyTest' --tests 'org.raku.nqp.runtime.unit.ProgramUnitTest'`
Expected: 5 + 8 tests pass (`ProgramUnitTest.blocksAreRawArgsEngineBlocksWithDistinctHandles`
reads `mh` through the getter on an eager info; unchanged semantics).

Run: `./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars`
then `( cd nqp && ./nqp-j-gradle -e 'say(1)' )`. Expected: `1`.

- [ ] **Step 9: The nqp suite**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records
raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/b-task4-nqp.log --stall=1800 --max=3600 \
  --show='files in' --show='not ok' --show='EXIT' -- \
  raku tools/build/evalserver-sweep.raku --suite=nqp '--chunk=*'
```

Expected: `155 files in <S>s across 1 server(s)`, no `not ok`, exit 0.
A red file here is a body field read before its barrier that the
getters did not cover — there is none by construction, so a red is a
`finishBody` order bug (names set after `finishBody`) or the ruling-10
edit; fix, rebuild the runtime jars, re-run the one file with
`( cd nqp && ./nqp-j-gradle t/nqp/<file>.t )`, then the sweep again.

- [ ] **Step 10: Commit (nqp tree)**

Stage the new interface and test, the modified `StaticCodeInfo.kt`,
`CodeRef.kt`, `CallFrame.kt`, `Syscalls.kt`, `ArgsExpectation.java`,
the `nqp-truffle` Java files and `ProgramUnitTestSupport.kt`; commit
with the evening stamp and the trailers, message:

```
Unit artifact v2, 3/n: StaticCodeInfo bodies behind ensureBody()

A shell holds identity and run-time state as plain fields; every body
field (the two bound handles, the lexical name arrays, handlers, source
position, the static-lexical arrays) is a property whose getter fills
the body once from a StaticBodySource, so no reader can see a shell.
outerFor, the auto-close constructor and the capture-lex syscalls now
recognise a block by its StaticCodeInfo, not by its bound handle, which
kept them from forcing bodies of blocks never entered. Every unit is
still eager: ProgramUnit follows.
```

Ledger: `Task 4: complete (nqp <hash>; lazy tests 5/5; nqp suite 155 green in <S> s)`.

---

## Task 5: `ProgramUnit` over the store; one load road (lazy-loading task 1.4 layers 1 and 3, task 1.5, and the window reader)

**Files:**
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt` (whole file)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitLoader.kt` (whole file)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/RecordReader.kt:40-136`, `UnitWriter.kt` (whole file)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitZip.kt` (add `toImage`; keep `read` and the sniffs)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitLoadStats.kt` (only if it enumerates stage names)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/GlobalContext.kt:236`, `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt` (the `inMemoryUnitRecords` and `UnitWriter.record` sites), `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/Syscalls.kt:484-492`
- Test: `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/ProgramUnitTest.kt` (over a `UnitStore`), `ProgramUnitTestSupport.kt`

**Interfaces:**
- Consumes: `UnitStore`, `UnitImage`, `UnitImageWriter`, `BlockEntry`, `BlockRecord`, `StaticLexValue` (Task 3); the shell constructors and `StaticBodySource` (Task 4).
- Produces:

```kotlin
class ProgramUnit(@JvmField val store: UnitStore) : CompilationUnit()
    fun dispatchSlot(programIndex: Int, ordinal: Int): ByteBuffer?   // Phase C's consumer entry; always null in Phase B
    fun buildTable(bootSt: STable?)                                   // shells only
    override fun engineProgram(idx: Int): String = store.program(idx)
    override fun serializedBlob(): ByteBuffer? = store.serialized
object UnitLoader
    fun store(fn: String, shared: Boolean): UnitStore     // shared: one per path, process-wide
    fun prime(path: String)                               // = store(path, true)
    fun isUnitFile(fn: String): Boolean                   // sniffs the first 64 bytes
    fun loadUnit / loadAndRun / load / loadApp            // signatures unchanged
object UnitWriter
    fun image(unit: SixModelObject?, tc: ThreadContext): UnitImage        // through RecordReader
    fun store(unit: SixModelObject?, tc: ThreadContext): UnitStore        // image -> bytes -> open: the in-memory road
    fun write(unit: SixModelObject?, filename: String?, tc: ThreadContext) // image -> file
object UnitZip   (window only; Task 9 deletes it)
    fun read(bytes: ByteArray): UnitRecord            // as today
    fun toImage(r: UnitRecord): UnitImage             // the transcoder
GlobalContext.inMemoryUnitRecords: ConcurrentHashMap<String, UnitStore>
```

Static lexical values: `BlockRecord.staticLex` is applied by the body
source when the unit's `lexValuesReady` flag is set and queued
otherwise; `runDeserializeIfAvailable` sets the flag and drains the
queue (stage `static-lex-drain`). `RecordReader` groups the guest's
`@!blockvalues` rows by qbid into the block records and reads
`$!dispatches` per block, 0 when the guest class has no such attribute
yet (Task 6 adds it; stage0's compiler never will).

- [ ] **Step 1: Rewrite `ProgramUnitTest` over a store**

Rewrite `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/ProgramUnitTest.kt`
to build its unit from a `UnitImage` through `UnitImageWriter.bytes` and
`UnitStore.open(ByteBuffer, "<test>")`; make `ProgramUnitTestSupport.unit()`
return one built the same way (the 4-qbid image of `UnitStoreTest`,
one gap, `deserializeQbid = -1`), and add `ProgramUnitTestSupport.tc()`
and `unitWithSc()` (below). Keep the eight test names and their
assertions (`tableFollowsTheBlockTable`,
`aQbidGapStaysAGapAndShiftsNothingAfterIt`,
`blocksAreRawArgsEngineBlocksWithDistinctHandles`,
`everyTableCodeRefIsAUnitEntry`, `aCodeRefNotFromBuildTableIsNotAUnitEntry`,
`handlersUnflatten`, `hooksAnswerFromTheMeta`, `cuidLookupFollowsTheBlockTable`)
and add three:

```kotlin
    @Test fun shellsAreBuiltForEveryLiveBlockWithoutDecodingARecord() {
        val u = ProgramUnitTestSupport.unit()
        u.buildTable(null)
        assertEquals(3, u.codeRefs!!.size)
        val sci = u.lookupCodeRef(0)!!.staticInfo
        assertEquals(0, sci.programIndex); assertTrue(sci.unitEntry); assertEquals("qb_0", sci.methodName)
        assertSame(u.lookupCodeRef(0)!!.staticInfo, u.lookupCodeRef(3)!!.staticInfo.outerStaticInfo)
        assertEquals(2, sci.oLexicalNames!!.size)        // fills now
        assertEquals("t.nqp", sci.sourceFile)
    }

    @Test fun staticLexValuesWaitForTheSc() {
        // block 0 has a static lexical "$y" from sc-x index 7: forced before the
        // deserialize program has run, the row is queued; the drain applies it.
        val (u, tc) = ProgramUnitTestSupport.unitWithSc()
        u.initializeCompilationUnit(tc, false)
        val sci = u.lookupCodeRef(0)!!.staticInfo
        assertNull(sci.oLexStatic!![1])
        u.runDeserializeIfAvailable(tc)                  // deserializeQbid = -1: only the drain runs
        assertNotNull(sci.oLexStatic!![1])
        assertEquals(1, sci.oLexStaticFlags!![1].toInt())
        // a body filled after the drain applies its rows at once
        val later = u.lookupCodeRef(3)!!.staticInfo
        assertEquals("löad 🐪", u.lookupCodeRef(3)!!.name); later.oLexicalNames
    }

    @Test fun dispatchSlotsReadThroughTheUnit() {
        val u = ProgramUnitTestSupport.unit()
        assertNull(u.dispatchSlot(0, 0)); assertNull(u.dispatchSlot(7, 0))
    }
```

`unitWithSc()` returns a `Pair<ProgramUnit, ThreadContext>`: read
`SerializationContextTest.kt` for how a `GlobalContext`/`ThreadContext`
and a `SerializationContext` are made in a test, register the SC under
handle `"sc-x"` in `tc.gc.scs` with any `SixModelObject` at index 7
(the test asserts non-null, not a type), and build the unit over the
same 4-qbid image.

- [ ] **Step 2: Run to see it fail**

Run: `./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.runtime.unit.ProgramUnitTest'`
Expected: compilation failure (`ProgramUnit(UnitStore)`).

- [ ] **Step 3: `ProgramUnit` over the store**

Replace `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt`:

```kotlin
package org.raku.nqp.runtime.unit

import java.nio.ByteBuffer
import org.raku.nqp.runtime.ArgsExpectation
import org.raku.nqp.runtime.CallSiteDescriptor
import org.raku.nqp.runtime.CodeRef
import org.raku.nqp.runtime.CompilationUnit
import org.raku.nqp.runtime.ExceptionHandling
import org.raku.nqp.runtime.GlobalContext
import org.raku.nqp.runtime.Ops
import org.raku.nqp.runtime.StaticBodySource
import org.raku.nqp.runtime.StaticCodeInfo
import org.raku.nqp.runtime.ThreadContext
import org.raku.nqp.sixmodel.STable

/**
 * A compilation unit over a unit artifact's store. buildTable builds a
 * shell per live block from the index alone (name, cuid, program index,
 * outer); a block's body is decoded from its record on first need
 * (StaticCodeInfo.ensureBody through BodySource), and its static lexical
 * values are applied then -- or queued until the deserialize program has
 * installed the SC they point into. Frame argument 0 of every engine
 * program is a CompilationUnit, so this stays one.
 */
class ProgramUnit(@JvmField val store: UnitStore) : CompilationUnit() {
    private val header get() = store.header

    /** cuid -> code ref, for the blocks that carry one. */
    private val byCuid = HashMap<String, CodeRef>()

    /** The GlobalContext this unit was initialized in: a body filled at
     *  run time resolves its static lexical SCs through it. */
    private var gc: GlobalContext? = null

    @Volatile private var lexValuesReady = false
    private val pendingLexValues = ArrayList<Pair<StaticCodeInfo, List<StaticLexValue>>>()  // guarded by this

    fun buildTable(bootSt: STable?) {
        val n = store.blockCount
        val table = arrayOfNulls<CodeRef>(n)
        val list = ArrayList<CodeRef>(n)
        for (qbid in 0 until n) {
            val pidx = store.programIndex(qbid)
            if (pidx < 0) continue   // a gap
            val cuid = header.cuids[qbid]
            val cr = CodeRef(this, ProgramEntry.ENTER, header.names[qbid], cuid,
                ArgsExpectation.USE_BINDER, BodySource(qbid))
            val sci = cr.staticInfo
            sci.programIndex = pidx
            sci.unitEntry = true
            sci.methodName = "qb_$qbid"
            if (cuid != null && cuid.isNotEmpty()) byCuid[cuid] = cr
            if (bootSt != null) cr.st = bootSt
            table[qbid] = cr
            list.add(cr)
        }
        for (qbid in 0 until n) {
            val cr = table[qbid] ?: continue
            val o = store.outerQbid(qbid)
            if (o >= 0) cr.staticInfo.outerStaticInfo = table[o]?.staticInfo
        }
        qbidToCodeRef = table
        codeRefs = list.toTypedArray()
        callSites = emptyArray()   // the v1 call-site table was never written; the engine builds its own descriptors
        if (Ops.REPOINT_TRACE) {
            val sb = StringBuilder("nqp buildTable: unit ${header.unitId}" +
                " blocks=$n live=${list.size}" +
                " serializedCodeRefCount=${header.serializedCodeRefCount}" +
                " mainlineQbid=${header.mainlineQbid}")
            for (q in 0 until n)
                sb.append("\n  qbid ").append(q).append(" -> ")
                  .append(if (table[q] == null) "GAP" else "cuid=" + table[q]!!.staticInfo.uniqueId + " '" + table[q]!!.name + "'")
            System.err.println(sb)
        }
    }

    private inner class BodySource(private val qbid: Int) : StaticBodySource {
        override fun fill(sci: StaticCodeInfo) {
            val r = store.blockRecord(qbid)
                ?: throw IllegalStateException("unit ${header.unitId}: block $qbid is a gap but has a code ref")
            sci.oLexicalNames = r.oLex.takeIf { it.isNotEmpty() }?.toTypedArray()
            sci.iLexicalNames = r.iLex.takeIf { it.isNotEmpty() }?.toTypedArray()
            sci.nLexicalNames = r.nLex.takeIf { it.isNotEmpty() }?.toTypedArray()
            sci.sLexicalNames = r.sLex.takeIf { it.isNotEmpty() }?.toTypedArray()
            sci.handlers = unflatten(r.handlers)
            sci.hasExitHandler = r.hasExitHandler
            sci.isThunk = r.isThunk
            if (r.sourceFile != null) {
                sci.sourceFile = r.sourceFile
                sci.sourceLine = r.sourceLine
                sci.sourceLineDelta = r.sourceLineDelta
                if (r.sectionRaw != null) {
                    sci.sourceSectionRaw = r.sectionRaw
                    sci.sourceSectionLine = r.sectionLine
                    sci.sourceSectionFile = r.sectionFile?.toTypedArray()
                }
            }
            sci.finishBody()
            if (r.staticLex.isNotEmpty()) applyOrQueue(sci, r.staticLex)
        }
    }

    private fun applyOrQueue(sci: StaticCodeInfo, rows: List<StaticLexValue>) {
        if (!lexValuesReady) {
            synchronized(this) {
                if (!lexValuesReady) { pendingLexValues.add(sci to rows); return }
            }
        }
        applyLexValues(sci, rows)
    }

    /** The SC a row names must be installed: this unit's own by the
     *  deserialize program, a dependency's by the dependency load that
     *  program triggers. A body filled before that is queued. */
    private fun applyLexValues(sci: StaticCodeInfo, rows: List<StaticLexValue>) {
        val gc = this.gc ?: throw IllegalStateException("unit ${header.unitId}: static lexical values applied before initialization")
        for (v in rows) {
            val idx = sci.oTryGetLexicalIdx(v.name)
            if (idx == -1) continue
            val sc = gc.scs.get(v.scHandle)
                ?: throw IllegalStateException("unit ${header.unitId}: static lexical ${v.name} of block ${sci.methodName} names unknown SC ${v.scHandle}")
            sci.oLexStatic!![idx] = sc.getObject(v.scIdx)
            sci.oLexStaticFlags!![idx] = v.flags.toByte()
        }
    }

    override fun initializeCompilationUnit(tc: ThreadContext, runDeserialize: Boolean) {
        gc = tc.gc
        UnitLoadStats.time(header.unitId, "shells", { "blocks=${store.blockCount}" }) {
            buildTable(tc.gc.BOOTCode?.st)
        }
        hllConfig = tc.gc.getHLLConfigFor(hllName())
        if (runDeserialize) runDeserializeIfAvailable(tc)
    }

    override fun runDeserializeIfAvailable(tc: ThreadContext) {
        if (gc == null) gc = tc.gc
        UnitLoadStats.time(header.unitId, "deserialize-program") { super.runDeserializeIfAvailable(tc) }
        val pending: List<Pair<StaticCodeInfo, List<StaticLexValue>>>
        synchronized(this) {
            lexValuesReady = true
            pending = ArrayList(pendingLexValues)
            pendingLexValues.clear()
        }
        UnitLoadStats.time(header.unitId, "static-lex-drain", { "blocks=${pending.size}" }) {
            for ((sci, rows) in pending) applyLexValues(sci, rows)
        }
    }

    /** Phase C's consumer entry: the persisted programs of one site, or
     *  null. Every slot is empty in Phase B. */
    fun dispatchSlot(programIndex: Int, ordinal: Int): ByteBuffer? = store.dispatchSlot(programIndex, ordinal)

    override fun getCallSites(): Array<CallSiteDescriptor> = emptyArray()
    override fun hllName(): String = header.hll
    override fun deserializeQbid(): Int = header.deserializeQbid
    override fun loadQbid(): Int = header.loadQbid
    override fun mainlineQbid(): Int = header.mainlineQbid
    override fun entryQbid(): Int = header.entryQbid
    override fun serializedCodeRefCount(): Int = header.serializedCodeRefCount
    override fun unitId(): String = header.unitId
    override fun lookupCodeRef(uniqueId: String): CodeRef? = byCuid[uniqueId]
    override fun engineProgram(idx: Int): String = store.program(idx)
    override fun serializedBlob(): ByteBuffer? = store.serialized

    /** A nested unit rides in the parent's zip, or was resolved into the
     *  parent's in-memory image by UnitWriter.image() before this unit
     *  existed. A missing entry is a hard error, never a lookup elsewhere. */
    override fun claimNested(tc: ThreadContext, name: String): CompilationUnit {
        val s = store.nested(name)
            ?: throw ExceptionHandling.dieInternal(tc, "unit ${unitId()} carries no nested unit named $name")
        val nested = ProgramUnit(s)
        nested.shared = tc.gc.sharingHint
        nested.initializeCompilationUnit(tc, false)
        return nested
    }

    private fun unflatten(flat: LongArray): Array<LongArray> {
        var p = 0
        val n = flat[p++].toInt()
        return Array(n) {
            val len = flat[p++].toInt()
            LongArray(len) { flat[p++] }
        }
    }
}
```

Check `CompilationUnit.callSites` and `getCallSites()`'s declared types
in `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CompilationUnit.kt`;
if `callSites` is non-nullable and assigned in `buildTable` as today,
`emptyArray()` is the right value. `Ops.kt:2885` and `Dispatch.kt:234`
index it only for `csIdx >= 0`, which no engine program emits.

- [ ] **Step 4: `RecordReader` produces an image; `UnitWriter` writes it or opens it**

In `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/RecordReader.kt`,
`read(unit)` returns a `UnitImage`:
- nested: `nested[id] = tc.gc.inMemoryUnitRecords[id]` (a `UnitStore` now), the same error when missing;
- per block: read as today, plus `val dispatches = intOr(b, "\$!dispatches", 0)`; write `intOr`
  next to `int` so a guest `QAST::BlockRecord` without the attribute (stage0's compiler during
  the window) yields 0 instead of dying — read how `int` fetches the attribute and catch the one
  exception type an unknown attribute name raises;
- group the `@!blockvalues` rows `[qbid, name, sc_handle, sc_idx, flags]` into
  `HashMap<Int, ArrayList<StaticLexValue>>` and hand each block its list (a row naming a gap or
  a qbid beyond the table is a `dieInternal` like today's "two blocks with qbid" family);
- drop the `@!callsites` read (ruling 3); keep the serialized blob's base64 decode, raw bytes, no LZ4;
- `dispatchCounts[b.programIndex] = dispatches` (programs are 1:1 with blocks).

Replace `UnitWriter.kt`'s body:

```kotlin
object UnitWriter {
    private val WHY = System.getenv("NQP_CODE_WHY") != null

    /** The driver's record (QAST::UnitRecord), read into an image. */
    @JvmStatic
    fun image(unit: SixModelObject?, tc: ThreadContext): UnitImage {
        if (unit == null) throw ExceptionHandling.dieInternal(tc, "unit record: needs a QAST::UnitRecord")
        return RecordReader(tc).read(unit)
    }

    /** The in-memory road (EVAL, BEGIN, a script): the same stored zip,
     *  in a heap buffer, opened like a file. */
    @JvmStatic
    fun store(unit: SixModelObject?, tc: ThreadContext): UnitStore {
        val img = image(unit, tc)
        return UnitStore.open(ByteBuffer.wrap(UnitImageWriter.bytes(img)), "<memory:${img.unitId}>")
    }

    @JvmStatic
    fun write(unit: SixModelObject?, filename: String?, tc: ThreadContext) {
        if (filename == null) throw ExceptionHandling.dieInternal(tc, "jvm-write-unit-record: needs a filename")
        val img = image(unit, tc)
        try { FileOutputStream(filename).use { UnitImageWriter.write(img, it) } }
        catch (e: java.io.IOException) { throw ExceptionHandling.dieInternal(tc, e) }
        if (WHY) System.err.println("unit artifact ${img.unitId} -> $filename " +
            "(${img.programs.size} programs, ${img.blocks.size} qbids, ${img.dispatchCounts.sum()} dispatch slots, ${img.nested.size} nested)")
    }
}
```

`GlobalContext.kt:236`: `inMemoryUnitRecords: ConcurrentHashMap<String, UnitStore>`.
Every `UnitWriter.record(` under `nqp/src/vm/jvm/runtime` becomes
`UnitWriter.store(` (`grep -rn 'UnitWriter.record\|inMemoryUnitRecords' nqp/src/vm/jvm/runtime`
lists them: `Ops.kt` near `:9077`, `Syscalls.kt:484-492`, `RecordReader.kt:44`).

- [ ] **Step 5: `UnitLoader` over stores, with the window transcoder**

In `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitLoader.kt`
replace the record cache and the readers; keep `load(tc, filename0)`,
`load(tc, ByteBuffer)` and `loadApp` as they are apart from the calls
named here:

```kotlin
object UnitLoader {
    /** One store per path, process-wide, for shared loads (the eval
     *  server): immutable, so every run's ProgramUnit slices the same
     *  mapping. Replaces the parsed-record cache. */
    private val stores = ConcurrentHashMap<String, UnitStore>()

    /** Sniffs the first local file header only: v2's unit.index, or --
     *  for the transition window -- v1's unit.meta. */
    @JvmStatic
    fun isUnitFile(fn: String): Boolean {
        val f = File(fn)
        if (!f.isFile) return false
        return try {
            FileChannel.open(f.toPath(), StandardOpenOption.READ).use { ch ->
                val head = ByteBuffer.allocate(64)
                ch.read(head); head.flip()
                UnitStore.isUnit(head) || UnitZip.isUnit(head)
            }
        } catch (t: Exception) { false }
    }

    /** The shared-load sniff cache of v1 is gone: the sniff now reads 64
     *  bytes, not a central directory. */
    @JvmStatic
    fun isUnitFile(fn: String, shared: Boolean): Boolean = isUnitFile(fn)

    @JvmStatic
    fun store(fn: String, shared: Boolean): UnitStore =
        if (shared) stores.computeIfAbsent(fn) { openStore(it) } else openStore(fn)

    private fun openStore(fn: String): UnitStore {
        val name = File(fn).name
        return UnitLoadStats.time(name, "open-store", { "bytes=${File(fn).length()}" }) {
            FileChannel.open(Path.of(fn), StandardOpenOption.READ).use { ch ->
                val mapped = ch.map(FileChannel.MapMode.READ_ONLY, 0, ch.size())
                if (UnitStore.isUnit(mapped)) UnitStore.open(mapped, fn) else transcodeV1(mapped, fn)
            }
        }
    }

    /** The transition window (deleted with v1, Task 9): a v1 artifact is
     *  decoded by the old reader and re-encoded as an in-memory v2 image. */
    private fun transcodeV1(bytes: ByteBuffer, name: String): UnitStore {
        val arr = ByteArray(bytes.remaining()).also { bytes.duplicate().get(it) }
        val rec = UnitLoadStats.time(File(name).name, "transcode-v1") { UnitZip.read(arr) }
        return UnitStore.open(ByteBuffer.wrap(UnitImageWriter.bytes(UnitZip.toImage(rec))), name)
    }

    private fun openStore(bytes: ByteArray, name: String): UnitStore =
        if (UnitStore.isUnit(ByteBuffer.wrap(bytes))) UnitStore.open(ByteBuffer.wrap(bytes), name)
        else transcodeV1(ByteBuffer.wrap(bytes), name)

    @JvmStatic
    @Throws(IOException::class)
    fun loadUnit(tc: ThreadContext, fn: String, shared: Boolean): ProgramUnit {
        val u = ProgramUnit(store(fn, shared))
        u.shared = shared
        u.initializeCompilationUnit(tc)
        return u
    }

    // loadAndRun(tc, fn, shared): unchanged, over loadUnit.

    @JvmStatic
    fun loadAndRun(tc: ThreadContext, bytes: ByteArray) {
        val u = ProgramUnit(openStore(bytes, "<buffer>"))
        u.shared = tc.gc.sharingHint
        u.initializeCompilationUnit(tc)
        u.runLoadIfAvailable(tc)
    }

    // load(tc, buffer: ByteArray): the sniff becomes
    //   if (!UnitStore.isUnit(ByteBuffer.wrap(buffer)) && !UnitZip.isUnit(buffer)) throw ...

    /** Warms the store cache, so a server pays for the open once. */
    @JvmStatic
    @Throws(IOException::class)
    fun prime(path: String) { store(path, true) }
}
```

`UnitZip.toImage(rec: UnitRecord): UnitImage` goes into `UnitZip.kt`
(window only): per qbid a `BlockEntry(b.name, b.cuid, b.outerQbid,
b.programIndex, BlockRecord(b.oLex.toList(), b.iLex.toList(),
b.nLex.toList(), b.sLex.toList(), b.handlers, b.hasExitHandler,
b.isThunk, b.sourceFile, b.sourceLine, b.sourceLineDelta, b.sectionRaw,
b.sectionLine, b.sectionFile?.toList(), staticLexOf(qbid)))`, where
`staticLexOf` groups `rec.meta.staticLexValues` by qbid into
`StaticLexValue(v.name, v.scHandle, v.scIdx, v.flags)`; `programs =
rec.programs.toList()`; `dispatchCounts = IntArray(rec.programs.size)`
(a v1 artifact carries no counts: its sites get ordinals but no
slots); `serialized = rec.serialized`; nested: each `rec.nested[id]`
transcoded recursively through
`UnitStore.open(ByteBuffer.wrap(UnitImageWriter.bytes(toImage(n))), "<nested:$id>")`.

`UnitLoadStats.kt`: if it enumerates stage names anywhere (read it),
add `open-store`, `transcode-v1`, `shells`, `static-lex-drain` and drop
`read-file`, `decode-total`, `inflate`, `decode-meta`,
`decode-programs`, `decompress-sc`, `decode-nested`, `build-table`,
`static-lex-values`. The marker `unit-load: stats on` stays as it is.

- [ ] **Step 6: Build and run the unit tests**

Run: `./nqp/gradlew -p nqp :nqp-runtime:test`
Expected: everything green (`UnitFormatTest`'s v1 round trips keep
running until Task 9).

- [ ] **Step 7: Runtime jars, the smoke, the stats marker**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records
./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars
( cd nqp && ./nqp-j-gradle -e 'say(1)' )
( cd nqp && NQP_UNIT_LOAD_STATS=1 ./nqp-j-gradle -e 'say(1)' 2>&1 | grep -E 'unit-load' | head -20 )
( cd nqp && ./nqp-j-gradle -e 'my $c := 0; sub f() { $c := $c + 1 }; f(); f(); say($c); say(nqp::getcodelocation(&f)<file>)' )
RAKUDO_RAKUAST=1 ./rakudo-j -e 'say 1'
RAKUDO_RAKUAST=1 NQP_UNIT_LOAD_STATS=1 ./rakudo-j -e 'say 1' 2>&1 | grep -c 'unit-load '
```

Expected: `1`; the stats lines show `open-store`, `transcode-v1` (the
stage2 `nqp.jar` is still v1), `shells`, `deserialize-program`,
`static-lex-drain`, `load-block`; `2` and a file name from the
reflection op (a body filled off the invocation path); `1` from Rakudo
(CORE.c through the transcoder), with more than 20 stage lines.

- [ ] **Step 8: The nqp suite**

As Task 4 Step 9, `--log=$CLAUDE_JOB_DIR/tmp/b-task5-nqp.log`.
Expected: 155 green. Every EVAL in the suite now writes and reopens a
stored zip. A red that names a lexical is a static-lexical row applied
to a block whose `oTryGetLexicalIdx` answered -1 (v1 skipped -1
silently and so does `applyLexValues`; compare the grouping); a red at
load naming "unknown SC" is a row applied before its dependency loaded,
which the drain's position after `super.runDeserializeIfAvailable`
should make impossible — check that first.

- [ ] **Step 9: Commit (nqp tree)**

Stage `src/vm/jvm/runtime/org/raku/nqp/runtime/unit/`,
`GlobalContext.kt`, `Ops.kt`, `dispatch/Syscalls.kt` and the tests;
commit with the evening stamp and the trailers, message:

```
Unit artifact v2, 4/n: ProgramUnit over the store; one load road

Shells from the index, bodies from the record slice on first need,
static lexical values per block applied when the SC is ready and queued
until then; programs decoded by index; the eval server keeps one store
per path. In-memory units (EVAL, BEGIN, scripts) take the same road
through a heap image, and a v1 artifact is transcoded into one at open
for the transition window. The v2 writer is live: every artifact
written from here on is v2; stage0 is still v1 and reads through the
transcoder.
```

Ledger: `Task 5: complete (nqp <hash>; runtime tests green; nqp suite 155 green in <S> s; stage lines seen: open-store, transcode-v1, shells, static-lex-drain)`.

---

## Task 6: Site identity, and the dispatch count on the wire's record

**Files:**
- Create: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/SiteIdentity.kt`
- Modify: `nqp/src/vm/jvm/QAST/Compiler.nqp:67-125` (`QAST::BlockRecord`: `$!dispatches`)
- Modify: `nqp/src/vm/jvm/QAST/TruffleEncoder.nqp:936-960` (set it from `%e<dispatches>`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/RecordReader.kt` (the `intOr` read of Task 5 now finds the attribute)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CodeEngine.kt:16-23,71-73,136-148`
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpCodeEngine.java:56`
- Modify: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpPolyglot.kt:42-46`
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpLanguage.java:65-81`
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java:26-43,517-566`
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java:824-837` (`EngineSite`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchBootstrap.kt:30-40` (`DispatchCallSite.identity`)
- Modify: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt:556-590` (stats)
- Modify: `nqp/t/nqp/125-dispatch-stats.t`

**Interfaces:**
- Consumes: `ProgramUnit.store` (Task 5) to tell a store-backed unit from an in-memory one.
- Produces:

```kotlin
// nqp-truffle
@JvmInline value class SiteIdentity(val key: String) {     // "<unit id>#<program index>#<ordinal>"
    companion object { fun parse(sourceName: String): ProgramIdentity? }   // null unless the name is "<unit>#<index>"
}
data class ProgramIdentity(val unitId: String, val programIndex: Int) { fun site(ordinal: Int): SiteIdentity }
// nqp-runtime (no Truffle import): the site carries its identity as a String key
class DispatchCallSite(...) { @JvmField var identity: String? = null }     // null: an anonymous site (ruling 8)
// CodeEngine
interface CodeEngine { fun compile(encoded: String, name: String): Any }   // unchanged; `name` IS the identity for a store-backed unit
// CodeEngines.materialize: the cache key and the Source name are
//   "<unit id>#<program index>" for a ProgramUnit, and the program text / "qb_N" for anything else
// NqpLanguage.PARSED: keyed by the Source NAME for identity-named sources, by the text otherwise
// Stats line: "dispatch stats: hits=... misses=... sites=<N> anon=<M> ..." (N sites with an identity, M without)
// Knob: NQP_SITE_CHECK=1 -> one stderr line per parse whose ordinal count exceeds the unit's slot count for that program
```

The ordinal (ruling 7): `NqpProgramBuilder` keeps a per-parse
`HashMap<Integer,Integer> siteOrdinals` from the DISPATCH node's wire
offset to its ordinal, assigned in walk order on first visit (the
measuring walk `walk(at, false)` counts as a visit); both emissions of
a duplicated body get the same identity.

- [ ] **Step 1: The dispatch count on the guest record**

`nqp/src/vm/jvm/QAST/Compiler.nqp`, class `QAST::BlockRecord`: add
`has int $!dispatches;   # DISPATCH nodes in the block's program: its unit.dispatch slot count`
after `$!program`, initialise it to 0 in `BUILD`, and add the accessor
`method dispatches(*@value) { @value ?? ($!dispatches := @value[0]) !! $!dispatches }`.

`nqp/src/vm/jvm/QAST/TruffleEncoder.nqp`, in `encode_block` right after
the `NQP_CODE_WHY` block that prints `dispatches=` (ends near `:960`):

```nqp
        # The block's DISPATCH node count is its unit.dispatch slot count
        # (milestone 7 Phase B): the record carries it, the writer sizes
        # the table from it, the builder numbers the nodes in walk order.
        $*BREC.dispatches(%e<dispatches>) if nqp::defined($*BREC);
```

(`$*BREC` is bound in `QAST::UnitCompiler.compile_block` before
`encode_block` is called, `Compiler.nqp:1789`; the harness paths that
encode without a block record leave it undefined.)

`RecordReader.intOr(b, "$!dispatches", 0)` (Task 5) now reads a real
value from a compiler built from this source; stage0's compiler keeps
yielding 0.

- [ ] **Step 2: `SiteIdentity`**

`nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/SiteIdentity.kt`:

```kotlin
package org.raku.nqp.truffle

/** A program of a store-backed unit: the compile key CodeEngines.materialize
 *  hands the engine as the Source name, "<unit id>#<program index>". An
 *  in-memory unit's programs are named "qb_N" and have no identity. */
data class ProgramIdentity(val unitId: String, val programIndex: Int) {
    fun site(ordinal: Int): SiteIdentity = SiteIdentity("$unitId#$programIndex#$ordinal")
    override fun toString() = "$unitId#$programIndex"

    companion object {
        /** Null unless [sourceName] has the "<unit id>#<index>" shape. A unit id
         *  never contains '#': it is a class-like name or a sha1. */
        @JvmStatic
        fun parse(sourceName: String): ProgramIdentity? {
            val hash = sourceName.lastIndexOf('#')
            if (hash <= 0 || hash == sourceName.length - 1) return null
            val idx = sourceName.substring(hash + 1).toIntOrNull() ?: return null
            return ProgramIdentity(sourceName.substring(0, hash), idx)
        }
    }
}

/** (unit id, program index, ordinal) as one key: what a dispatch instruction
 *  is known by across processes (spec, Phase B "Site identity"). */
@JvmInline
value class SiteIdentity(val key: String)
```

- [ ] **Step 3: The compile key**

`nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CodeEngine.kt`, `materialize`:

```kotlin
    @JvmStatic
    fun materialize(sci: StaticCodeInfo): Any? {
        sci.engineTarget?.let { return it }
        if (sci.programIndex < 0) return null
        val engine = engine ?: return null
        synchronized(sci) {
            sci.engineTarget?.let { return it }
            val cu = sci.compUnit
            // A store-backed unit's program is keyed by identity, so a hit
            // never decodes the text and the engine learns which unit and
            // program it is parsing (site identity, milestone 7 Phase B).
            // Anything else keeps the text key: an in-memory unit's id is a
            // fresh sha1 per compile, so its identical texts share a root.
            val key = if (cu is org.raku.nqp.runtime.unit.ProgramUnit) cu.unitId() + "#" + sci.programIndex else null
            val program = if (key != null)
                programs.computeIfAbsent(key) { engine.compile(cu.engineProgram(sci.programIndex), key) }
            else
                programs.computeIfAbsent(cu.engineProgram(sci.programIndex)) { engine.compile(it, sci.methodName ?: "<anon>") }
            sci.engineTarget = program
            return program
        }
    }
```

Update the KDoc on `programs` (`:64-71`): "keyed by identity for a
store-backed unit, by the program text otherwise".

`NqpPolyglot.compile(encoded, name)` (`NqpPolyglot.kt:42-46`): the
lookup after `context.eval` becomes
`NqpLanguage.PARSED[NqpLanguage.parsedKey(encoded, name)]`.

`NqpLanguage.java`: add

```java
    /** The PARSED key: the Source name when it is a program identity
     *  ("<unit>#<index>", CodeEngines.materialize), else the text. */
    static String parsedKey(String source, String name) {
        return ProgramIdentity.parse(name) != null ? name : source;
    }
```

and in `parse(ParsingRequest)` replace both `PARSED.put(source, target)`
with `PARSED.put(parsedKey(source, request.getSource().getName()), target)`,
and pass the identity into the builder:

```java
            ProgramIdentity identity = ProgramIdentity.parse(request.getSource().getName());
            BytecodeRootNodes<NqpRootNode> nodes = NqpRootNodeGen.create(
                this, BytecodeConfig.DEFAULT, b -> NqpProgramBuilder.build(b, p, identity));
```

Update the `PARSED` Javadoc (`:60-64`) to say what the key is.

- [ ] **Step 4: The builder numbers the sites**

`nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java`:
add two fields after the existing ones (`:26-37`):

```java
    /** The unit and program being parsed, or null for an in-memory
     *  unit's program (no identity, no unit.dispatch slot). */
    private final ProgramIdentity identity;
    /** DISPATCH wire offset -> ordinal, in walk order of first visit. A
     *  repeat/for body is walked twice with emit, so a counter at site
     *  construction would number one node twice; the offset does not. */
    private final java.util.HashMap<Integer, Integer> siteOrdinals = new java.util.HashMap<>();
    private static final boolean SITE_CHECK = System.getenv("NQP_SITE_CHECK") != null;
```

`build(b, p)` becomes `build(b, p, identity)` (update the one caller,
`NqpLanguage.parse`), storing the identity. At the DISPATCH case
(`:517-566`), before the children are walked:

```java
            int ordinal = siteOrdinals.computeIfAbsent(at, k -> siteOrdinals.size());
            ...
                b.beginDispatchOp(rtype, name, new NqpOps.EngineSite(csd,
                    identity == null ? null : identity.site(ordinal).getKey()));
```

(`at` here is the offset of the DISPATCH tag itself: capture it in a
local before `at += 4`.) After the walk finishes in `build` (where the
root's `programSize` etc. are known), under the knob:

```java
        if (SITE_CHECK && identity != null)
            System.err.println("site-check " + identity + " ordinals=" + siteOrdinals.size());
```

(The slot count lives in the unit's index, which the engine cannot see;
the check compares the two lines with the `unit-check` line Task 7
Step 5 prints from the runtime side. One line per parse, env-gated.)

- [ ] **Step 5: The site carries it**

`NqpOps.java:824-837`, `EngineSite`: a second constructor argument
`String identity`, stored on the `DispatchCallSite`:

```java
        EngineSite(CallSiteDescriptor csd, String identity) {
            this.csd = csd;
            this.site = new org.raku.nqp.dispatch.DispatchCallSite(
                java.lang.invoke.MethodType.methodType(void.class));
            this.site.identity = identity;
            org.raku.nqp.dispatch.DispatchBootstrap.registerSite(this.site);
            this.cache = new NqpDispatch.Cache(this.site, csd);
        }
```

`DispatchBootstrap.kt:30-40`, `DispatchCallSite`: add

```kotlin
    /** "<unit id>#<program index>#<ordinal>" for a site of a store-backed
     *  unit's program; null for an anonymous site (an in-memory unit, the
     *  helper sites in Ops, Rakudo's rv-decont site, the indy road). Phase
     *  C keys unit.dispatch by it. Set once at construction. */
    @JvmField var identity: String? = null
```

Grep every other `EngineSite(` constructor call (`grep -rn 'new NqpOps.EngineSite\|EngineSite(' nqp/nqp-truffle/src`)
and pass `null` where no identity exists.

- [ ] **Step 6: The stats marker**

`NqpDispatch.kt:556-590`: two counters `sites` and `anonSites`
incremented in `Cache.init` (`:490-496`) by `site.identity != null`,
under `STATS`; the exit line gains ` sites=$sites anon=$anonSites`
after ` misses=`. The rig's regex reads `hits=` and `misses=` and is
not anchored at the end; the two leading spaces of the `  misses `
lines stay.

`nqp/t/nqp/125-dispatch-stats.t`: `plan(6)` and one more assertion
after the `slowLayout=` one:

```nqp
    ok(nqp::index($text, ' sites=') >= 0,                'sites with an identity are counted');
```

- [ ] **Step 7: Runtime-only verification**

The QAST edits (Steps 1) take effect at Task 7's `clean buildJvm`; the
runtime and engine edits can be checked now:

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records
./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars
( cd nqp && NQP_DISPATCH_STATS=1 ./nqp-j-gradle -e 'say(1)' 2>&1 | grep 'dispatch stats:' )
( cd nqp && NQP_SITE_CHECK=1 ./nqp-j-gradle -e 'say(1)' 2>&1 | grep -c '^site-check ' )
( cd nqp && ./nqp-j-gradle t/nqp/125-dispatch-stats.t )
```

Expected: the stats line carries `sites=<N> anon=<M>` with N > 0 (the
stage2 nqp.jar is store-backed through the transcoder, so its programs
have identities) and M > 0 (the `-e` unit is in memory); at least one
`site-check` line; `1..6` all ok.

Then the nqp suite as Task 4 Step 9 (`--log=$CLAUDE_JOB_DIR/tmp/b-task6-nqp.log`):
155 green. The suite compiles every test in memory (anonymous sites)
and runs the compiler's own programs (identified sites); a regression
here is the `PARSED` key: a text-keyed lookup that now misses because
the parse stored under the name (or the reverse) throws "the language
parsed nothing for".

- [ ] **Step 8: Commit (nqp tree)**

Stage `src/vm/jvm/QAST/Compiler.nqp`, `src/vm/jvm/QAST/TruffleEncoder.nqp`,
`src/vm/jvm/runtime/org/raku/nqp/runtime/CodeEngine.kt`,
`src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchBootstrap.kt`,
`nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/SiteIdentity.kt`,
`nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpPolyglot.kt`,
`nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt`,
`nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpLanguage.java`,
`nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java`,
`nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java`,
`t/nqp/125-dispatch-stats.t`; commit with the evening stamp and the
trailers, message:

```
Unit artifact v2, 5/n: every dispatch site of a stored unit has an identity

(unit id, program index, ordinal): the unit and index travel as the
engine's compile key and Source name, the program builder numbers each
DISPATCH wire node once in walk order (a repeat/for body is emitted
twice; the offset dedupes it), and the DispatchCallSite carries the key.
The block record carries its DISPATCH count, which sizes unit.dispatch.
In-memory units keep the text key and get no identity; helper sites
stay anonymous. dispatch stats: sites=/anon= on the exit line.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: <URL>
```

Ledger: `Task 6: complete (nqp <hash>; stats sites=N anon=M; nqp suite 155 green in <S> s; the encoder edit waits for Task 7's clean build)`.

---

## Task 7: The window build (lazy-loading task 1.6, step 1)

**Files:**
- No source edits of its own beyond fixes; builds and gates everything from Tasks 1-6.
- Produces: a compiler that reads v1 and v2 and writes v2; the `unit-check` diagnostic line (one small runtime edit, Step 5).

**Interfaces:**
- Consumes: everything above.
- Produces: the build Task 8 regenerates stage0 from; CORE.c's compile
  time and the artifact sizes for the findings.

- [ ] **Step 1: nqp, clean, from stage0**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records
java -version 2>&1 | head -1     # Oracle GraalVM 25.2.4
raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/b-window-nqp.log --stall=1500 --max=5400 \
  --show='Task :' --show='BUILD' --show='error:' -- \
  ./nqp/gradlew -p nqp clean buildJvm
```

Expected: `BUILD SUCCESSFUL`. Stage1 is compiled by stage0's compiler
(v1 artifacts, transcoded at open) on the new runtime and written as
v2 with every dispatch count 0; stage2 is compiled by stage1 (the new
encoder) and carries real counts. Check both:

```bash
unzip -l nqp/build/jvm/stage2/nqp.jar | head -12      # unit.index first, unit.dispatch present
( cd nqp && NQP_UNIT_LOAD_STATS=1 ./nqp-j-gradle -e 'say(1)' 2>&1 | grep -E 'open-store|transcode' )
```

Expected: five `unit.*` entries, no `transcode-v1` line (nothing v1 is
loaded by the runner any more; stage0 is only read by the build).

- [ ] **Step 2: Runtime tests and the nqp suite on the window build**

```bash
./nqp/gradlew -p nqp :nqp-runtime:test
raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/b-window-nqp-suite.log --stall=1800 --max=3600 \
  --show='files in' --show='not ok' --show='EXIT' -- \
  raku tools/build/evalserver-sweep.raku --suite=nqp '--chunk=*'
```

Expected: tests green; `155 files in <S>s`, no `not ok`. **This is the
gate the stage0 rule requires before `jBootstrapFiles`** (Task 8): a
red here stops the phase until fixed; do not regenerate stage0 from a
red window build.

- [ ] **Step 3: Rakudo, clean**

The rakudo runtime jar must be rebuilt against the new nqp-runtime
(ruling: a `@JvmField` became a property), and the settings must be
written as v2, so:

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records
perl Configure.pl --backends=jvm --gen-nqp 2>&1 | tail -3
raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/b-window-make.log --stall=1500 --max=7200 \
  --show='Compiling' --show='Generating' --show='Error' -- \
  sh -c 'make clean && make'
```

Expected: `rakudo-j` built. Record from the log, with the elapsed
prefixes, the CORE.c setting's compile time (the gap between its
`Compiling` line and the next `Compiling`/`Generating` line) in the
ledger as `CORE.c (window build): <s> s` — reported, not gated.

- [ ] **Step 4: Sizes, and `t/01-sanity`**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records
for j in blib/CORE.c.setting.jar blib/Perl6/BOOTSTRAP/v6c.jar nqp/build/jvm/stage2/nqp.jar rakudo.jar; do
  echo "== $j $(stat -c %s $j) bytes"; unzip -lv "$j" | grep -E 'unit\.|nested/' | awk '{print $8, $1, $2}'
done
RAKUDO_RAKUAST=1 perl t/harness5 --jvm --evalserver t/01-sanity 2>&1 | tail -3
```

Expected: the sizes (into the ledger as a table: per artifact, on-disk
bytes, per-entry bytes; against the base numbers in "Facts every task
relies on"); `t/01-sanity` 25/25 (`Files=25, Tests=...`, `Result: PASS`).
The knob check on the trained pair: `NQP_SITE_CHECK=1 RAKUDO_RAKUAST=1
./rakudo-j -e 'say 1' 2>&1 | grep -c site-check` > 0.

- [ ] **Step 5: The `unit-check` line (runtime side of the site check)**

So that `NQP_SITE_CHECK=1` can be judged without the engine seeing the
index: in `ProgramUnit.buildTable`, under the same knob (read once into
a `private val SITE_CHECK = System.getenv("NQP_SITE_CHECK") != null` in
the companion), print one line per unit
`unit-check <unitId> programs=<N> slots=<dispatchSlotCount>` and, in
`CodeEngines.materialize` after a compile with a key, nothing more (the
`site-check` line already names the program). A run's `site-check
<unit>#<idx> ordinals=K` must satisfy `K <= store.dispatchSlotCount(idx)`
for a unit whose slot count is non-zero; write the comparison as a
one-off Raku one-liner over the two greps and record the result in the
ledger for `./rakudo-j -e 'say 1'`:

```bash
NQP_SITE_CHECK=1 RAKUDO_RAKUAST=1 ./rakudo-j -e 'say 1' 2> $CLAUDE_JOB_DIR/tmp/site-check.err >/dev/null
raku -e 'my %slots; for "$*ENV<CLAUDE_JOB_DIR>/tmp/site-check.err".IO.lines { if /^ "site-check " (\S+) "#" (\d+) " ordinals=" (\d+)/ { %slots{"$0#$1"} = +$2 } }; say %slots.elems, " programs numbered; max ordinals ", %slots.values.max'
```

(A stricter per-program comparison needs the store's per-program count,
which `unit-check` does not print per program; Phase C's consumer will
be the real check, since a lookup past the slot count answers null and
is counted.) Rebuild the runtime jars after the edit
(`:nqp-runtime:jar syncRuntimeJars`) and commit it with Step 7.

- [ ] **Step 6: The one warm `t/02-rakudo` sweep (correctness gate, ruling 12)**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records
raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/b-window-t02.log --stall=7200 --max=10800 \
  --show='files in' --show='Wstat' -- \
  raku tools/build/evalserver-sweep.raku --jobs=1 --chunk=306 t/02-rakudo
raku tools/build/m7-rig.raku --parse-sweep=$CLAUDE_JOB_DIR/tmp/b-window-t02.log --baseline=docs/jvm-t02-rakudo-red-baseline.txt
```

Expected: `new-red=0` against the 24-file baseline. Runs as a plain
background job through watched-run; monitor its log every 90 s or
more. A new red is fixed before Task 8, with the fix committed and the
nqp suite re-run (not the sweep: the one file, through
`RAKUDO_RAKUAST=1 ./rakudo-j -Ilib t/02-rakudo/<file>.t`, then the
suite). Record the red list and the wall time in the ledger; the wall
time is not a measurement.

- [ ] **Step 7: Commit the window (both trees, if anything changed)**

Fixes found in Steps 1-6 are committed as they land, each with the
evening stamp and the trailers; the Step 5 diagnostic lands as
`Unit artifact v2, 6/n: the unit-check line beside site-check`. Ledger:
`Task 7: complete (window build: nqp <hash> rakudo <hash>; nqp suite
155 green; make clean+make <s> s, CORE.c <s> s; t/01-sanity 25/25;
t/02-rakudo new-red=0 in <s> s; sizes: CORE.c <bytes> ...)`.

---

## Task 8: Stage0 regeneration (lazy-loading task 1.6, step 2)

**Files:**
- Modify: `nqp/src/vm/jvm/stage0/*.jar` (9 artifacts, regenerated)

**Interfaces:**
- Consumes: the window build (Task 7), nqp suite green on it.
- Produces: a stage0 that is v2, from which Task 9's compiler can be built without a v1 reader.

- [ ] **Step 1: Regenerate from the window build**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records
git -C nqp status --short src/vm/jvm/stage0 | head      # clean before
./nqp/gradlew -p nqp jBootstrapFiles
git -C nqp status --short src/vm/jvm/stage0 | head      # 9 modified jars
for j in nqp/src/vm/jvm/stage0/*.jar; do unzip -l "$j" | grep -c 'unit.index' ; done
```

Expected: every stage0 jar now has a `unit.index` entry (9 lines of
`1`). `jBootstrapFiles` copies stage2's jars over `src/vm/jvm/stage0`
(`nqp/build.gradle.kts:404-412`); stage2 was written by the new encoder
and carries dispatch counts, so stage0's slot tables are sized.

- [ ] **Step 2: Clean nqp build from the new stage0, tests, suite**

```bash
raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/b-stage0-nqp.log --stall=1500 --max=5400 \
  --show='Task :' --show='BUILD' --show='error:' -- \
  ./nqp/gradlew -p nqp clean buildJvm
./nqp/gradlew -p nqp :nqp-runtime:test
raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/b-stage0-nqp-suite.log --stall=1800 --max=3600 \
  --show='files in' --show='not ok' --show='EXIT' -- \
  raku tools/build/evalserver-sweep.raku --suite=nqp '--chunk=*'
```

Expected: `BUILD SUCCESSFUL`; tests green; 155 green. During this
build no `transcode-v1` can occur; confirm with
`NQP_UNIT_LOAD_STATS=1` on one stage task if in doubt (the stage tasks
inherit the environment: `NQP_UNIT_LOAD_STATS=1 ./nqp/gradlew -p nqp
:stage1CompileNqp 2>&1 | grep -c transcode` — find the stage task's name
with `./nqp/gradlew -p nqp tasks --all | grep -i stage1`; expected 0).

- [ ] **Step 3: Rakudo again, and `t/01-sanity`**

The stage2 `nqp.jar` Rakudo builds against changed (rebuilt from a v2
stage0); the settings must be recompiled by it:

```bash
perl Configure.pl --backends=jvm --gen-nqp 2>&1 | tail -3
raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/b-stage0-make.log --stall=1500 --max=7200 \
  --show='Compiling' --show='Generating' --show='Error' -- \
  sh -c 'make clean && make'
RAKUDO_RAKUAST=1 perl t/harness5 --jvm --evalserver t/01-sanity 2>&1 | tail -3
```

Expected: `rakudo-j` built; 25/25. CORE.c's time into the ledger in
passing.

- [ ] **Step 4: Commit stage0 (nqp tree)**

```bash
STAMP="$(date +%F)T21:00:00+02:00"
git -C nqp add src/vm/jvm/stage0
GIT_AUTHOR_DATE=$STAMP GIT_COMMITTER_DATE=$STAMP git -C nqp commit -m "Stage0: regenerated as unit artifact v2

From the window build (nqp <window hash>): the last compiler that read
v1. Nine artifacts, unit.index first, every dispatch slot empty. The
v1 reader goes next.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: <URL>"
```

Ledger: `Task 8: complete (nqp <hash>; stage0 = 9 v2 jars; clean buildJvm ok; nqp suite 155 green; make <s> s, CORE.c <s> s; t/01-sanity 25/25)`.

---

## Task 9: v1 removal (lazy-loading task 1.6, step 3)

**Files:**
- Delete: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitFormat.kt`, `UnitRecord.kt`, `UnitZip.kt`
- Delete: `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitFormatTest.kt`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitLoader.kt` (the transcoder and the v1 sniff go)
- Modify: `nqp/buildSrc/src/main/kotlin/NqpDeps.kt` (lz4-java leaves the allowlist if nothing else uses it)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitLoadStats.kt` (drop `transcode-v1` if enumerated)

**Interfaces:**
- Consumes: a v2 stage0 (Task 8).
- Produces: a runtime with exactly one artifact reader.

- [ ] **Step 1: Delete, and cut the window paths**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records
git -C nqp rm -q src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitFormat.kt \
  src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitRecord.kt \
  src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitZip.kt \
  nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitFormatTest.kt
grep -rn 'UnitZip\|UnitRecord\b\|UnitFormat\|transcodeV1\|lz4' nqp/src/vm/jvm/runtime nqp/nqp-truffle/src src/vm/jvm/runtime nqp/buildSrc | grep -v '^Binary'
```

In `UnitLoader.kt`: `isUnitFile` keeps only `UnitStore.isUnit(head)`;
`openStore(fn)` maps and opens (`UnitStore.open(mapped, fn)`; a non-v2
file is the `IllegalStateException` the store throws — no fallback,
spec "Errors"); `openStore(bytes, name)` likewise; `transcodeV1` is
deleted; `load(tc, ByteArray)`'s sniff is `UnitStore.isUnit` only.
`ProgramUnitTestSupport` and `ProgramUnitTest` already build from
images. If the grep shows `lz4` used nowhere else, remove
`org.lz4:lz4-java:1.8.0` from `NqpDeps.thirdParty` and `"lz4-java"`
from `moduleOrder`, and delete the LZ4 imports; if something else uses
it (grep `LZ4` in `nqp/src/vm/jvm/runtime` and `src/vm/jvm/runtime`),
leave the dependency and say so in the ledger.

- [ ] **Step 2: Clean build, tests, suite, Rakudo, sanity**

The same four commands as Task 8 Steps 2-3 (logs `b-v1gone-*.log`).
Expected: `BUILD SUCCESSFUL`; tests green (`UnitCodecTest`,
`UnitStoreTest`, `ProgramUnitTest`, `StaticCodeInfoLazyTest`,
`SerializationContextTest`, `GraphemeCursorTest`); 155 green; `rakudo-j`
built; 25/25. A precompiled module cache from an earlier build
(`~/.raku/precomp` or the rig's precomp dir) that still holds v1 jars
would fail to load with "version"/"bad magic": the rig clears its own
precomp cache; a stray user cache is cleared by hand and noted.

- [ ] **Step 3: Commit (nqp tree)**

```bash
STAMP="$(date +%F)T21:10:00+02:00"
git -C nqp add -A src/vm/jvm/runtime/org/raku/nqp/runtime/unit nqp-runtime/src/test buildSrc/src/main/kotlin/NqpDeps.kt
GIT_AUTHOR_DATE=$STAMP GIT_COMMITTER_DATE=$STAMP git -C nqp commit -m "Unit artifact v2, 7/7: the v1 reader is gone

UnitFormat, UnitRecord, UnitZip, the transcoder and the v1 sniff are
deleted; a non-v2 file is a hard error naming the file. LZ4 leaves the
runtime with them (nothing else compressed anything).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: <URL>"
```

Ledger: `Task 9: complete (nqp <hash>; one reader; clean build + suite + make + sanity green)`.

---

## Task 10: Measure once, document, close the phase

**Files:**
- Create: `docs/jvm-unit-lazy-loading.md`
- Modify: `docs/jvm-perf-findings-2026-09.md` (a "Milestone 7, Phase B" section after Phase A's)
- Modify: `docs/jvm-truffle-only-plan.md` (the position: item 4's row; Phase B closed)
- Modify: `docs/jvm-eval-server.md` (mapped stores are shared across runs)
- Modify: `docs/superpowers/specs/2026-09-13-jvm-lazy-unit-loading-design.md` (Revision 4 note)
- Modify: the milestone memory (`milestone-7-first-execution.md`) and `MEMORY.md`

**Interfaces:**
- Consumes: the final build of Task 9.
- Produces: the numbers Phase C is measured against; the format's documentation.

- [ ] **Step 1: The rig row**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records
java -version 2>&1 | head -1
raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/m7-rig-b.log --stall=2400 --max=5400 \
  --show='m7-rig:' -- \
  raku tools/build/m7-rig.raku --tag=b --out=$CLAUDE_JOB_DIR/tmp/m7-rig
cat $CLAUDE_JOB_DIR/tmp/m7-rig/b.md
```

Expected: `m7-rig: DONE tag=b`; the row: cold rakudo-e, cold nqp-e
(best of 5), misses, hits, the histogram, the warm `t/01-sanity` clock.
Against the a6 row (2.504 s / 1.192 s / 5661 / 100697): the spec
expects unit decode and build-table (about 11 % of the cold run) to
move; SC read stays. Whatever the numbers say, they go into the
findings as they are; no re-take (user rule). From the cold run's
`unit-load` lines, the per-stage table (open-store, shells,
deserialize-program, static-lex-drain, load-block) for CORE.c and for
nqp.jar.

- [ ] **Step 2: `docs/jvm-unit-lazy-loading.md`**

Sections, each a paragraph or a table, no more: *The v2 format* (the
five entries, the index layout with the three tables and their row
shapes, nested units, "every entry stored, one mapping"); *The load
road* (open-store → shells → deserialize program → drain; the in-memory
road through the same writer; the eval server's store cache and the
restart-after-rebuild rule); *Lazy bodies* (`ensureBody`, what is on
the shell and why — `argsExpectation`, `outerStaticInfo`, the run-time
state — the `staticInfo` identity test that replaced the handle test,
the static-lexical queue); *Site identity* (the compile key, the Source
name, `PARSED`'s key, the ordinal by wire offset, anonymous sites, the
`NQP_SITE_CHECK` lines, in-memory units without identity); *The
dispatch table* (slot addressing, empty in Phase B, what Phase C
writes, the slot-count-from-the-encoder invariant); *Diagnostics*
(`NQP_UNIT_LOAD_STATS` stages, `NQP_CODE_WHY`'s writer line,
`NQP_SITE_CHECK`, `dispatch stats: sites=/anon=`); *What phase 2 will
do* (SC demand, the `serialized` slice already mapped for it) — one
paragraph pointing at the lazy-loading spec.

- [ ] **Step 3: The findings section**

In `docs/jvm-perf-findings-2026-09.md` after "Milestone 7, Phase A":
`## Milestone 7, Phase B: the format, once` with (a) the row `b`
against `a6` (both hashes, the four numbers, the histogram), (b) the
per-stage table before/after for CORE.c (the a6 run's `unit-load` lines
are in the Phase A rig directory; if not, the spec's "about 11 %"
estimate is the before), (c) the artifact sizes table from Task 7 Step
4 against the base sizes, (d) CORE.c compile times from the three
makes, (e) the rulings that changed the spec's letter (1-12, one line
each, pointing at this plan), (f) what Phase C inherits: the empty
table, the descriptor-inline schema note (ruling 3), anonymous sites
(ruling 8), the `site-check`/`unit-check` pair, and the open question of
whether stored entries should be compressed (sizes say).

- [ ] **Step 4: Position, eval-server note, Revision 4, memory**

`docs/jvm-truffle-only-plan.md`: in the position section, item 4's
row: Phase B closed on <date> with the b row's numbers; Phase C next.
`docs/jvm-eval-server.md`: one paragraph under the server's caches:
unit stores are mapped once per path and shared by every run; a
rebuilt jar needs a server restart (it did already), and the
per-request work is shells + deserialization, not parsing.
`docs/superpowers/specs/2026-09-13-jvm-lazy-unit-loading-design.md`:
`## Revision 4 — phase 1 landed (date)`: tasks 1.1-1.6 done in milestone
7 Phase B (this plan), the rulings that departed from the letter (4, 5,
6, 9, 11), phase 2 is what remains; the SC slice is mapped and handed
to the reader as a `ByteBuffer` already.
Memory: `milestone-7-first-execution.md` gets a "PHASE B CLOSED" status
paragraph (hashes, the b row, the rulings' one-liners, NEXT = Phase C
plan from C0 the spike), and `MEMORY.md`'s line for it is updated.

- [ ] **Step 5: Commit docs (rakudo tree), rebase both trees, push**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records
STAMP="$(date +%F)T21:30:00+02:00"
git add docs/jvm-unit-lazy-loading.md docs/jvm-perf-findings-2026-09.md docs/jvm-truffle-only-plan.md docs/jvm-eval-server.md \
  docs/superpowers/specs/2026-09-13-jvm-lazy-unit-loading-design.md docs/superpowers/plans/2026-09-15-jvm-milestone-7-first-execution-phase-b.ledger.md
GIT_AUTHOR_DATE=$STAMP GIT_COMMITTER_DATE=$STAMP git commit -m "Docs: milestone 7 Phase B closed -- artifact v2, lazy bodies, site identity, measured

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: <URL>"
```

Then the handoff rule (memory `worktree-source-of-truth-and-rebase`):
`git fetch origin && git rebase origin/main` in the rakudo tree,
`git -C nqp fetch upstream && git -C nqp rebase upstream/main` in the
nqp tree (add `upstream = https://github.com/Raku/nqp` if missing),
conflicts expected to be few; then `git push --force-with-lease
ab5tract worktree-jesp-direct-lazy-records` and
`git -C nqp push --force-with-lease ab5tract jesp-direct-lazy-records`.
No gate after the handoff rebase (user, 2026-09-09). Record both
pushed hashes in the ledger and the memory.

Ledger: `Task 10: complete; PHASE B CLOSED (rakudo <hash>, nqp <hash>, pushed); NEXT = Phase C plan (C0 the spike first)`.

---

## Self-review (done at writing time, 2026-09-15)

**Spec coverage.** Milestone spec, Phase B: site identity → Task 6;
the fifth entry `unit.dispatch` with a count in the header and a
fixed-width table, every slot empty, O(1) lookup → Task 3 (`UnitStore.dispatchSlot`,
`UnitHeader.dispatchSlotCount`) and Task 5 (`ProgramUnit.dispatchSlot`);
lazy tables closing the stub road's load cost (two handles per block
only for entered blocks) → Task 4's `finishBody` inside `ensureBody`;
measurement, the rig once on the v2 build, CORE.c from the window build
→ Task 10 and Task 7 Step 3; persisted programs addressing SC objects
by handle and index → nothing to do in Phase B, noted in the findings
(Task 10 Step 3 f). Lazy-loading spec: 1.1 the survey → done 2026-09-15,
verdicts applied in Task 4; 1.2 the store, stored entries, one open,
central directory, mapped slices, `unit.index` tables, nested units
mapped when claimed → Task 3 (nested: sliced from the one mapping, built
when claimed); 1.3 the codec → Task 2; 1.4 shells, bodies, unit-level
tables (`CallSiteDescriptor` per index: dropped by ruling 3; programs
by index; the engine cache keyed by (unit, index)) → Tasks 4, 5, 6;
static lexical values applied at once or queued → Task 5; 1.5 the eval
server's process-wide store → Task 5 (`UnitLoader.stores`, `prime`);
1.6 window build, stage0 regeneration, v1 removal, gates at each →
Tasks 7, 8, 9. Errors: a malformed entry is a hard error naming unit,
entry and index → `UnitStore`'s messages, tested. Documentation:
`docs/jvm-unit-lazy-loading.md`, the eval-server note → Task 10.
Milestone spec "The close" items are Phase-level, not Phase B's; the
memory and push happen in Task 10 all the same. Gates: the nqp suite
before `jBootstrapFiles` → Task 7 Step 2, restated at Task 8.

**Placeholders.** None: every step names its file, its code or its
command and its expected output. The one deliberately open value is the
`Claude-Session` URL (Global Constraints say who fills it and where).

**Type consistency.** `UnitStore.open(ByteBuffer, String)` /
`open(String)`; `UnitImageWriter.bytes(UnitImage)` / `write(UnitImage,
OutputStream)`; `BlockRecord` fields in the same order in the
Interfaces block, `UnitStoreTest.block`, `ProgramUnit.BodySource` and
`UnitZip.toImage`; `StaticBodySource.fill(StaticCodeInfo)`;
`CodeRef(compUnit, mh, name, uniqueId, argsExpectation, source)` in
Task 4's interface, its test and Task 5's `buildTable`;
`StaticCodeInfo(compUnit, mh, uniqueId, argsExpectation, staticCode,
source)` in the interface and the `CodeRef` constructor;
`UnitWriter.store/image/write`; `ProgramIdentity.parse` /
`site(ordinal)` / `SiteIdentity.key`; `DispatchCallSite.identity:
String?`; `EngineSite(csd, identity)`; `dispatch stats: ... sites= anon=`.
