# Milestone 7, Phase C: the persisted miss — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking. Keep a ledger twin at
> `docs/superpowers/plans/2026-09-15-jvm-milestone-7-first-execution-phase-c.ledger.md`
> (project convention: every ruling, every deferred minor, every task
> verdict and every rig row goes in it as it happens, not at the end).

**Goal:** Fill the `unit.dispatch` slots Phase B left empty with the
dispatch programs a training run records, restore them at a site's first
miss so a cold `rakudo -e` replays instead of recording, prove the
restored programs equal fresh recordings under a verify mode, and
measure the result once; then close milestone 7.

**Architecture:** A `DispatchProgram` is pure data whose only object
references are STables, SC-rooted objects and code refs (each addressed
as `(SC handle, index)`), the HLL config (by name), the syscall (by
name) and the dispatcher (by id). `DispatchSlotCodec` maps a program to
a kotlinx-serializable twin (`PProgram`) and back; a program with a
reference outside every SC is simply not persisted. A runner started
with `NQP_DISPATCH_RECORD=all` rewrites, at exit, every store-backed
artifact it loaded: the slot of each site that recorded gets its
programs, every other entry is copied byte for byte, and the file is
replaced atomically (`UnitDispatchWriter`). Each dispatch site carries
its unit namespace, program index and ordinal from construction; on its
first miss `Dispatch.fallback` asks `DispatchPersist` for the slot,
realises each program against this process's SCs (dropping any that do
not resolve), installs them and replays before it would record.
`NQP_DISPATCH_PERSIST=off` disables the consumer; `=verify` keeps the
restored programs aside, records fresh, and reports any restored
program whose guards pass but whose text (the `DispatchDump`
normalisation from the C0 spike) differs from the recording. The nqp
gradle build and the Rakudo Makefile each run one training step (the
trivial program) after their last artifact, so a clean build reproduces
the slots deterministically.

**Tech Stack:** NQP and Raku on the JVM; Oracle GraalVM 25.2.4 with
Truffle (Bytecode DSL); Kotlin for runtime code (Java only inside the
DSL-bound files `NqpOps.java`, `NqpProgramBuilder.java`,
`NqpRootNode.java`, `NqpLanguage.java`, `NqpCodeEngine.java`); kotlinx
serialization core 1.11.0 through the fixed-width `UnitCodec`; Raku for
all tooling; Gradle (Kotlin DSL) for the nqp side; GNU make for the
Rakudo side.

**Spec:** `docs/superpowers/specs/2026-09-13-jvm-milestone-7-first-execution-design.md`
(rakudo `83375a77ae`), section "Phase C: the persisted miss", plus "The
close", "Gates" item 6 and "Done". The C0 spike this plan starts from is
recorded below and in `docs/jvm-perf-findings-2026-09.md`, "Milestone 7,
Phase C".

## Global Constraints

Every task's requirements implicitly include this section. They are the
Phase B plan's constraints, carried over verbatim where they still hold.

- **Work in the worktree, never the stale checkout.** The repository root
  for every path and command in this plan is
  `/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records`
  (rakudo branch `worktree-jesp-direct-lazy-records`; nested nqp branch
  `jesp-direct-lazy-records`). The session starts in the stale checkout:
  pin every path. The Bash tool's cwd drifts into `nqp/` after any
  command that `cd`s there: pin the directory in every command.
- **Two git working trees.** The root is rakudo.git; `nqp/` is the nqp.git
  working tree nested inside it, gitignored, NOT a submodule. Run
  `cd <root>/nqp && git ...` for that tree (the worktree guard refuses
  `git -C`). Label every hash with its tree ("nqp `b51c1a0db`" vs "rakudo
  `9bfa3fe86c`"). Write nqp paths with the `nqp/` prefix. Run gradle from
  the root: `./nqp/gradlew -p nqp ...`.
- **`RAKUDO_RAKUAST=1` on every build, test and run.** The Makefile exports
  it into its own recipes; nothing sets it for your own invocations.
- **`NQP_CODE_RUN` and `NQP_CODE_PRECOMP` must not be set at all.** The
  compiler dies on `=0`.
- **`java` must be Oracle GraalVM 25.2.4.** Verify with `java -version`
  before any build or measurement.
- **Runtime-jar rebuild** after any edit under `nqp/src/vm/jvm/runtime/` or
  `nqp/nqp-truffle/`: `./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar
  syncRuntimeJars` (about 30 s). Restart any eval server afterwards. An
  edit to `nqp/build.gradle.kts` reconfigures on the next gradle run.
- **Rakudo's runtime jar does not follow nqp's.** After an nqp-runtime
  change that alters a class shape (this plan adds fields to
  `DispatchCallSite`) the Rakudo side must be `perl Configure.pl
  --backends=jvm --gen-nqp && make clean && make`, never a bare `make`.
- **Long builds and test runs go through `tools/build/watched-run.raku`**
  with `--log` and `--show`. Never hand-roll timestamp wrappers or
  tail-based monitors. `--show` takes a literal, repeatable; `--show-rx`
  takes a `/.../` regex only. Monitor a log every 90 s or more, never
  more often. If the harness keeps stopping a heavy task, start it as a
  plain background job (`run_in_background`, no `setsid`/`nohup`).
- **The eval-server sweep is silent until its chunk ends.** Launch it with
  `--stall` past the run (`--stall=7200`) and a `--max` ceiling
  (`--max=10800`).
- **Never replace an eval server mid-sweep.** Pass the total file count as
  `--chunk` (`'--chunk=*'` for the nqp suite) with `--jobs=1`.
- **Benchmark runs use the stock runners**, `./rakudo-j` from the root and
  `./nqp-j-gradle` with cwd `nqp/`, never the eval server (it exports
  `Compilation=false` to its children). **A training run is never a
  measured run**: the rig refuses to start with `NQP_DISPATCH_RECORD` set.
- **No fine-grained gating (user rule 2026-09-15).** Correctness gates
  are the nqp suite (`raku tools/build/evalserver-sweep.raku --suite=nqp
  '--chunk=*'`, 155 files, all green) and `t/01-sanity` (25/25 through
  `perl t/harness5 --jvm --evalserver`, after a Rakudo `make`). One rig
  row for the phase, `--warm=proxy`. A failed benchmark run is recorded as
  not gathered and the number taken at the next planned point. Whole `t/`
  runs once, at the milestone close (Task 10).
- **Every gate is reported with its wall time** (user rule 2026-09-15), in
  the ledger and in status updates. A bare "green" is not a report.
- **Runtime performance outranks compile time.** CORE.c is reported in
  passing from the builds; it is never a gate.
- **Tooling in Raku**, never Python or shell.
- **Every diagnostic env-gated**: `System.getenv(...)` read once into a
  `val` in runtime code; `nqp::say(...) if nqp::getenvhash()<VAR>;` in
  NQP. Never a bare print. Counters live behind `NqpDispatch.STATS`
  (`NQP_DISPATCH_STATS`).
- **Smoke-test every instrument on a short workload and require a
  positive marker** before any long run. This plan's markers:
  `dispatch-record: wrote` (training), `dispatch-verify: on` and
  `dispatch-verify: matched=` (verify mode), `dispatch stats:` with
  `restored=` (consumer), `m7-rig: DONE`. Abort a long run whose marker
  never appears.
- **Kotlin, never Java**, for new code, except inside the DSL-bound Java
  files named above.
- **No Truffle dependency in `nqp-runtime` logic.** Review checks every
  runtime import of `com.oracle.truffle`.
- **No jar of any kind is committed** (user rule 2026-09-15): the nine v2
  stage0 jars stay an uncommitted working-tree change in `nqp/`; nothing
  in this plan regenerates or commits stage0.
- **Subagents default to Opus.** Re-run on Fable only after erroneous
  output; log the escalation in the ledger.
- **Commits stamped in the evening of the date the work happened**,
  18:00-23:00: `STAMP="$(date +%F)T20:30:00+02:00"; GIT_AUTHOR_DATE=$STAMP
  GIT_COMMITTER_DATE=$STAMP git commit ...`; step the minute for a second
  commit the same evening.
- **Commit trailers on every commit, both trees:**
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and
  `Claude-Session: <the executing session's URL>` when the executing
  session knows its URL (never fabricated; the ledger header records it
  once).
- **The in-tree runners have no installed module repo**: anything with a
  `use` needs `-Ilib`.
- **No `t/spec`** in this milestone.

## What C0 found (2026-09-15, the spike that sizes this phase)

Instrument: `NQP_DISPATCH_DUMP=<path>` (`DispatchDump.kt`, nqp-runtime),
a shutdown hook that prints every registered site and each installed
program in a normalised text form where every reference is
`obj:<handle>:<idx>`, `code:<handle>:<idx>`, `st:<handle>:<idx>` or
`NP(<class>:<type>:<reason>)`. Analysis: `tools/build/dispatch-dump-diff.raku`.
Two cold `RAKUDO_RAKUAST=1 ./rakudo-j -e ''` runs on rakudo `9bfa3fe86c`
/ nqp `b51c1a0db` (the Phase B close):

| dispatcher | sites | programs | persistable | unpersistable | same in run 2 | misses |
|---|---|---|---|---|---|---|
| lang-meth-call | 2145 | 2450 | 2440 | 10 | 2448 | 2872 |
| lang-call | 1910 | 1912 | 1907 | 5 | 1908 | 1909 |
| boot-syscall | 206 | 206 | 206 | 0 | 206 | 206 |
| raku-assign | 35 | 35 | 0 | 35 | 35 | 35 |
| raku-meth-call-qualified | 1 | 1 | 1 | 0 | 1 | 1 |
| total | 4297 | 4604 | 4554 | 50 | 4598 | 5023 |

- **98.9 % of the programs are persistable** (4554 of 4604); the two
  runs' dumps are byte-identical (`diff` empty), so the recorded outcome
  of the trivial program is deterministic and structurally stable.
- **Misses vs programs**: 5023 misses, 4604 installed programs, 4297
  sites that recorded, 2135 sites parsed but never dispatched, 4 anonymous
  sites with programs (the `-e` unit's own). The 419 misses above the
  program count are polymorphic sites' interpreted-tail hits (a program
  past the folded prefix still counts as a miss in `NqpDispatch.miss`)
  and re-recordings. So the persisted share of first-execution work is
  **about 4550 of the 5023 misses**; what remains after Phase C is the
  50 unpersistable programs, the anonymous sites and the tail hits.
- **Unpersistable causes** (programs carrying each): 40 `CodeRef` with no
  SC (all 35 `raku-assign` outcomes invoke a runtime-made code ref; 5
  `lang-meth-call` on the bootstrap KnowHOW's `find_method`/`new_type`/
  `name`, Kotlin-made methods); 5 `RakuObject4` with no SC (runtime-made
  Raku objects in `lang-call` bind guards); 4 `VMHashInstance` with no SC
  (an nqp class's runtime-published method cache as a `lookup` table); 1
  `VMArrayInstance` owned by an SC object but not in its root set
  (`@!dispatchees`). None is worth a naming scheme in this phase.
- **Per artifact** (sites that recorded / programs): CORE.c 1526/1527,
  nqp's QAST.jar 1111/1113 (the trivial program still runs the QAST
  compiler), v6c BOOTSTRAP 831/1095, NQPCORE 101/115, NQPHLL 100/109,
  Metamodel 92/104, Actions 87/91, Ops 78/78, Grammar 59/59, QRegex
  39/40, nqpmo 38/38, rakudo.jar 35/35, QASTNode 35/35, ModuleLoader
  (Perl6) 35/35, Compiler 33/33, CORE.d 22/22, Optimizer 20/20,
  NQPP6QRegex 18/18, SysConfig 16/16, ModuleLoader (nqp) 10/10, v6d 7/7.
  **A third of the sites are in nqp's jars**, so Rakudo's training run
  must write nqp's artifacts too (ruling 5).
- **Five identity strings are shared by two live sites each** (three in
  v6c, one each in NQPCORE and NQPHLL): the same program parsed twice.
  The producer merges programs per identity (ruling 7).
- Every SC referenced resolves by handle through `tc.gc.scs`, including
  the bootstrap's `__6MODEL_CORE__` (registered by
  `KnowHOWBootstrapper.kt:110`).

## Rulings (where the surveys and C0 forced a decision)

Each with what it costs if wrong. Open to the user's veto until Task 3
writes the schema.

1. **No site identity and no descriptor index in the slot.** The spec's
   schema names both; Phase B made the slot addressable by (program
   index, ordinal) and deleted the call-site table, so the slot holds
   `DispatchSlot(programs: List<PProgram>)` and each program carries its
   post-flattening descriptor inline. Wrong -> nothing: the address IS
   the identity.
2. **References are `PRef(handle, index, kind)`** with kind 0 = SC object
   root, 1 = SC code ref, 2 = STable; the HLL config by `HLLConfig.name`,
   the syscall by `Syscall.name`, the dispatcher by `Dispatcher.id`
   (every JVM dispatcher is a builtin or registered by id;
   `DispatchRegistry.findOrNull(id)`). A program with a reference that
   has no such address is not persisted; a persisted reference that does
   not resolve at restore time drops the whole program (counted
   `dropped=`). Wrong -> a restored program invoking the wrong object;
   the verify gate is the check.
3. **kotlinx sealed hierarchies with short `@SerialName`s**, encoded by
   the existing `UnitCodec` (which gains `encodeDouble`/`decodeDouble` as
   raw long bits). Wrong -> a class-name string per node, a few bytes;
   the sizes are recorded.
4. **The training process writes the artifacts itself at exit**, in a
   shutdown hook that reads each selected file whole, patches the
   `.index` slot rows and the `.dispatch` entry of every unit in it (root
   and nested), copies every other entry byte for byte, writes
   `<path>.tmp` and renames it into place. There is no separate writer
   entry point to drive: `UnitDispatchWriter` is the class the hook
   calls. The spec's `NQP_DISPATCH_RECORD=<path>` becomes
   `NQP_DISPATCH_RECORD=all` (every store-backed unit the process
   loaded) or a comma-separated list of store-name prefixes. Wrong -> a
   build step that needs a second process; nothing in the format.
5. **Rakudo's training run rewrites nqp's jars under
   `nqp/build/jvm/share/lib` too** (`all`): a third of the cold run's
   sites are there. Slots merge: a site's programs at exit are the
   restored ones plus the new ones, so the second training adds Raku
   shapes to nqp's slots without losing nqp's. A later `syncLib` on the
   nqp side re-syncs those jars from nqp's own trained copies (losing
   Rakudo's additions until the next `make`), which is the deterministic
   order a clean build has anyway. Wrong -> the QAST.jar sites miss
   under Rakudo; measured by the rig row.
6. **The gradle training step trains a COPY** (`build/jvm/stage2-trained`,
   synced from stage2) and `syncLib` takes the lib jars from that copy.
   Rewriting the stage2 jars in place would change the compile tasks'
   outputs and make every later gradle run recompile stage2. Wrong ->
   every build recompiles nqp. `jBootstrapFiles` keeps copying the
   untrained stage2 jars, so stage0 stays empty-tabled as the spec says.
7. **Programs merge per slot**: the two live sites that share an identity
   (C0: five of them) contribute to one slot, deduplicated by their
   normalised text, capped at `Dispatch.MAX_PROGRAMS`. Wrong -> one
   site's programs lost; the verify gate would see the other site's
   recordings as unseen, not as mismatches.
8. **Restore at first miss, not at parse.** `Dispatch.fallback` restores
   once per site (a `restored` flag that `reset()` clears, so each
   eval-server run re-arms from the slot), installs the realised
   programs, and replays them before recording. The first miss still
   counts as a miss in `NqpDispatch.miss`; the counters that show the
   gain are `restored=` (programs installed from slots),
   `restoredSites=`, `dropped=` and `recorded=` (fresh recordings), all
   on the `dispatch stats:` line. The claim is on `recorded`, which C0
   predicts at about 5023 -> under 500; `misses` stays comparable with
   the earlier rows. Wrong -> the rig row's `misses` column does not
   move and the reader looks at `recorded`.
9. **Verify compares applicable programs only.** In `verify` mode the
   restored programs are kept aside; after each fresh recording at the
   site, every restored program whose descriptor shape matches and whose
   guards pass on the recorded call's arguments must have the same
   `DispatchDump.describe` text as the recording; otherwise a
   `dispatch-verify: MISMATCH` line prints with identity, dispatcher and
   both texts. A recording that no restored program applies to is
   `unseen`, not a mismatch (a test file exercises shapes the trivial
   program never did). The gate requires zero mismatches over the nqp
   suite and `t/01-sanity`. Wrong -> a persisted program that is valid in
   the training process but not in the consumer passes as "unseen"; the
   residual risk the spec names, recorded as such.
10. **The five Rakudo units sharing `--javaclass=perl6` need nothing**:
    the namespace is store name plus unit id and each slot is looked up
    through the site's own store. Recorded, not acted on.
11. **Compression of `unit.records`/`unit.programs` is presented, not
    built.** It is clock-negative by construction (an inflate at open of
    26 MB the mapped road demand-pages today, 20-80 ms cold), which the
    user's runtime-first rule makes a decision for the user, not a lever
    to strike by measurement. The findings record the `unit.dispatch`
    sizes this phase adds and the estimate; the user decides at the close.
12. **Bounds hardening lands with the writer** (Task 5): `dispatchSlot`
    checks the absolute slot against `dispatchSlotCount` and rejects a
    negative offset; the store's init checks every program's slot window.
    Wrong -> a hand-corrupted artifact reads past the table; none is
    writer-produced.
13. **Runtime-made sites are counted**: every `DispatchCallSite`
    construction bumps `DispatchBootstrap.created`, printed as
    `sitesAll=` next to `sites=` (wire sites) so the difference is the
    helper/rv-decont/indy count the Phase B close could not give.
14. **The deferred rakudo rebase is Task 2**, gated by `make` +
    `t/01-sanity` (the last handoff's instruction), before any Phase C
    build, so the phase's numbers are on a tree that includes upstream's
    48 commits.
15. **The milestone close's whole-`t/` run** (Task 10) goes through
    watched-run as a plain background job with a 6 GB server heap; if the
    low-memory guard kills it again, the clock is recorded as not
    gathered with the evidence, and the user decides where to run it.

## File Structure

nqp tree (`nqp/`), all Kotlin unless marked:

- `src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchDump.kt` (exists, C0):
  the normalised text form; verify mode reuses `describe`.
- `src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlot.kt` (new): the
  `@Serializable` twins (`PRef`, `PDescriptor`, `PSource`..., `PGuard`...,
  `PShape`, `POutcome`..., `PResumption`, `PLevel`, `PBind`, `PProgram`,
  `DispatchSlot`). Data only.
- `src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlotCodec.kt` (new):
  `persist(DispatchProgram): PProgram?` and
  `realise(tc, PProgram): DispatchProgram?`; `Unpersistable`.
- `src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt` (new): the
  mode knob, the namespace -> store registry, `restore`, `verify`, the
  counters, the `NQP_DISPATCH_RECORD` hook (`recordAtExit`).
- `src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitDispatchWriter.kt`
  (new): `rewrite(path, slots)`; patches one artifact file.
- `src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitStore.kt`: `entryPrefix`,
  `absoluteSlot`, bounds hardening.
- `src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitImageWriter.kt`: `put`
  becomes `internal`.
- `src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitCodec.kt`: Double.
- `src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt`: registers
  its namespace with `DispatchPersist`.
- `src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchBootstrap.kt`: the
  `created` counter; `DispatchCallSite` gains `unitNamespace`,
  `programIndex`, `ordinal`, `restored`, `verifyPrograms`.
- `src/vm/jvm/runtime/org/raku/nqp/dispatch/Dispatch.kt`: the consumer
  hook in `fallback`, the verify/recorded hook in `record`.
- `nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java`
  (`EngineSite`) and `NqpProgramBuilder.java`: pass the identity's parts.
- `nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt`: the
  stats line.
- `build.gradle.kts`: `stage2Trained` (Sync) + `trainDispatch` (JavaExec);
  `syncLib` from the trained copy.
- Tests: `nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchSlotCodecTest.kt`,
  `.../dispatch/DispatchPersistTest.kt`,
  `.../runtime/unit/UnitDispatchWriterTest.kt`, and a Double case in
  `.../runtime/unit/UnitCodecTest.kt`.

rakudo tree:

- `tools/templates/jvm/Makefile.in`: the `j-train-dispatch` stamp target;
  `$(J_RUNNER)` depends on it.
- `tools/build/m7-rig.raku`: parses `recorded=`/`restored=` into the cold
  summary.
- `tools/build/dispatch-dump-diff.raku` (exists, C0).
- Docs: `docs/jvm-unit-lazy-loading.md` ("The dispatch table" rewritten),
  `docs/jvm-perf-findings-2026-09.md` ("Milestone 7, Phase C" and the
  milestone summary), `docs/jvm-truffle-only-plan.md` (position), the
  spec ("Phase C: closed"), this plan's ledger, memory.

---

## Task 1: The ledger, the C0 record, and the spike code committed

**Files:**
- Create: `docs/superpowers/plans/2026-09-15-jvm-milestone-7-first-execution-phase-c.ledger.md`
- Modify: `docs/jvm-perf-findings-2026-09.md` (new section before "Things that cost time to learn")
- Commit (nqp): `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchDump.kt`,
  `DispatchBootstrap.kt` (`sites()`, the dump hook), `Dispatch.kt` (the
  `linkedName` line in `fallback`)
- Commit (rakudo): `tools/build/dispatch-dump-diff.raku`, this plan, the ledger, the findings section

**Interfaces:**
- Produces: `DispatchDump.describe(p: DispatchProgram): String` (the
  normalised text later tasks compare), `DispatchBootstrap.sites():
  Collection<DispatchCallSite>`.

- [ ] **Step 1: Write the ledger header** (mirror the Phase B ledger's
  head: plan path, spec, BASE hashes rakudo `9bfa3fe86c` / nqp
  `b51c1a0db`, the Phase B row `b` as the baseline: cold rakudo-e 2.461 s,
  cold nqp-e 1.160 s, misses 5667, hits 100711, sanity 50 s; the model
  policy line; the fifteen rulings as a numbered list; a "## Rig rows"
  table with the Phase B header and row `b` copied in).

- [ ] **Step 2: Append "## Milestone 7, Phase C: the persisted miss
  (2026-09-15)" to the findings** with a "### (a) C0, the spike" subsection
  holding the table and the bullets of "What C0 found" above, verbatim,
  and the sentence "The instrument stays: `NQP_DISPATCH_DUMP` is the
  normalisation verify mode compares with."

- [ ] **Step 3: Confirm the spike build is what is in the tree**:
  `cd <root> && ./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars -q`
  then `NQP_DISPATCH_DUMP=/tmp/x.dump NQP_DISPATCH_STATS=1 RAKUDO_RAKUAST=1 ./rakudo-j -e '' 2>&1 | grep -c 'dispatch stats:'`
  Expected: `1`, and `grep -c ^prog /tmp/x.dump` prints `4604`.

- [ ] **Step 4: Commit, nqp tree** (evening stamp, trailers):
  ```
  Dispatch: NQP_DISPATCH_DUMP -- every site's programs in a normalised text form (Phase C, C0)
  ```

- [ ] **Step 5: Commit, rakudo tree**:
  ```
  Docs, tools: milestone 7 Phase C plan, ledger, and the C0 spike's findings + dispatch-dump-diff.raku
  ```

## Task 2: The deferred rakudo rebase onto origin/main, gated

**Files:** none edited by hand except conflict resolution in
`src/Raku/ast/signature.rakumod`.

- [ ] **Step 1: Fetch and rebase**:
  `cd <root> && git fetch origin main && git rebase origin/main`
  (213 of ours over 48 upstream). The Phase B close hit a conflict at
  our commit `f4f4c2ff1f` "RakuAST: check a definite parameter type as its
  base type plus concreteness" against upstream's `bc78a3c7d1`,
  `e19a45978c`, `da0655783c` and the `IMPL-CAPTURE-DEFINITE` rework in the
  same file. Resolve by keeping upstream's structure and re-applying our
  intent (the base-type-plus-concreteness check for a definite type) on
  top of it; read both sides in full before editing. `git rebase
  --continue` until clean.
- [ ] **Step 2: Gate**: `raku tools/build/watched-run.raku --log=build-c-rebase.log --show='Compiling' --show='Setting up' -- make`
  (the frontend changed; a bare `make` recompiles the frontend and the
  settings, about 900 s). Then
  `RAKUDO_RAKUAST=1 perl t/harness5 --jvm --evalserver t/01-sanity`
  Expected: 25/25. Record both wall times in the ledger.
- [ ] **Step 3: Push**: `git push --force-with-lease ab5tract worktree-jesp-direct-lazy-records`.
  nqp `upstream/main` had 0 new commits at the Phase B close; re-check
  with `cd <root>/nqp && git fetch upstream main && git rev-list --count HEAD..upstream/main`
  and rebase only if non-zero.
- [ ] **Step 4: Ledger**: the new rakudo hash, the conflict resolution in
  one paragraph, both clocks.

## Task 3: The schema and the codec (`DispatchSlot`, `DispatchSlotCodec`)

**Files:**
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlot.kt`
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlotCodec.kt`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitCodec.kt` (Double)
- Test: `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchSlotCodecTest.kt`,
  `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitCodecTest.kt`

**Interfaces:**
- Consumes: `DispatchModel.kt`'s classes (constructor names as in the
  code below), `DispatchDump.describe`, `UnitCodec.encode/decode`,
  `SerializationContext` (`handle`, `getObjectIndex`, `getObject`,
  `objectCount`, `getCodeIndex`, `getCodeRef`, `coderefCount`,
  `getSTableIndex`, `getSTable`, `stableCount`), `tc.gc.scs`,
  `tc.gc.dispatchers.findOrNull(id)`, `Syscalls.find(tc, name)`,
  `tc.gc.getHLLConfigFor(name)`.
- Produces: `DispatchSlotCodec.persist(p: DispatchProgram): PProgram?`,
  `DispatchSlotCodec.realise(tc: ThreadContext, p: PProgram): DispatchProgram?`,
  `DispatchSlot(programs: List<PProgram>)` with
  `DispatchSlot.serializer()`.

- [ ] **Step 1: Double in the codec.** In `UnitCodec.Writer` replace the
  throwing `encodeDouble` with
  `override fun encodeDouble(value: Double) = encodeLong(value.toRawBits())`
  and in `Reader` `override fun decodeDouble(): Double = Double.fromBits(buf.getLong())`.
  Add to `UnitCodecTest.kt`:
  ```kotlin
  @Serializable class WithDouble(val d: Double, val tag: Int)
  @Test fun doublesRoundTripAsRawBits() {
      val b = UnitCodec.encode(WithDouble.serializer(), WithDouble(-0.0, 7))
      assertEquals(12, b.size)
      val d = UnitCodec.decode(WithDouble.serializer(), ByteBuffer.wrap(b))
      assertEquals((-0.0).toRawBits(), d.d.toRawBits()); assertEquals(7, d.tag)
  }
  ```
  (a nested `@Serializable` class of the test class, as Phase B's codec
  tests do; the plugin rejects local ones.)

- [ ] **Step 2: Write `DispatchSlot.kt`**:
  ```kotlin
  package org.raku.nqp.dispatch

  import kotlinx.serialization.SerialName
  import kotlinx.serialization.Serializable

  /**
   * The persisted twin of a DispatchProgram (milestone 7 Phase C): the
   * same tree with every object reference replaced by an SC address, the
   * HLL config by its name, the syscall by its name and the dispatcher by
   * its id. One DispatchSlot per site slot of unit.dispatch, encoded by
   * UnitCodec. Data only; DispatchSlotCodec converts both ways.
   */
  @Serializable class PRef(val handle: String, val index: Int, val kind: Int) {
      companion object { const val OBJ = 0; const val CODE = 1; const val STABLE = 2 }
  }

  @Serializable class PDescriptor(val flags: ByteArray, val names: List<String>?)

  @Serializable sealed class PSource
  @Serializable @SerialName("arg") class PArg(val index: Int) : PSource()
  @Serializable @SerialName("rinit") class PResumeInitArg(val level: Int, val index: Int) : PSource()
  /** OBJ: [obj] (null is the null object); INT/UINT: [i]; NUM: [n]; STR: [s]. */
  @Serializable @SerialName("lit") class PLiteral(val kind: ArgKind, val obj: PRef?, val i: Long, val n: Double, val s: String?) : PSource()
  @Serializable @SerialName("attr") class PAttribute(val from: PSource, val classHandle: PRef?, val name: String, val kind: ArgKind) : PSource()
  @Serializable @SerialName("how") class PHow(val from: PSource) : PSource()
  @Serializable @SerialName("unbox") class PUnbox(val from: PSource, val kind: ArgKind) : PSource()
  @Serializable @SerialName("lookup") class PLookup(val table: PSource, val key: PSource) : PSource()
  @Serializable @SerialName("rstate") class PResumeState(val level: Int) : PSource()

  @Serializable sealed class PGuard
  @Serializable @SerialName("type") class PGuardType(val on: PSource, val type: PRef?) : PGuard()
  @Serializable @SerialName("conc") class PGuardConcreteness(val on: PSource, val concrete: Boolean) : PGuard()
  @Serializable @SerialName("lit") class PGuardLiteral(val on: PSource, val expected: PLiteral) : PGuard()
  @Serializable @SerialName("notlit") class PGuardNotLiteralObj(val on: PSource, val rejected: PRef?) : PGuard()
  @Serializable @SerialName("hll") class PGuardHll(val on: PSource, val hll: String?) : PGuard()

  @Serializable class PShape(val sources: List<PSource>, val descriptor: PDescriptor)

  @Serializable sealed class POutcome
  @Serializable @SerialName("value") class POutcomeValue(val source: PSource) : POutcome()
  @Serializable @SerialName("invoke") class POutcomeInvoke(val callee: PSource, val args: PShape) : POutcome()
  @Serializable @SerialName("syscall") class POutcomeSyscall(val syscall: String, val args: PShape) : POutcome()

  @Serializable class PResumption(val dispatcher: String, val initArgs: PShape)
  @Serializable class PLevel(val dispatcher: String, val initDescriptor: PDescriptor, val guards: List<PGuard>,
                             val newState: PSource?, val requireNoFurther: Boolean)
  @Serializable class PBind(val failureFlag: Long, val successFlag: Long?, val onSuccessToo: Boolean)

  @Serializable class PProgram(
      val descriptor: PDescriptor, val guards: List<PGuard>, val outcome: POutcome,
      val resumptions: List<PResumption>, val resumeKind: ResumeKind, val resumeLevels: List<PLevel>,
      val bindControl: PBind?, val bindFailure: PProgram?)

  @Serializable class DispatchSlot(val programs: List<PProgram>)
  ```

- [ ] **Step 3: Write the failing round-trip test** `DispatchSlotCodecTest.kt`
  (package `org.raku.nqp.dispatch`; uses `ProgramUnitTestSupport.tc()` for
  a fresh runtime whose bootstrap SC `__6MODEL_CORE__` is registered):
  ```kotlin
  package org.raku.nqp.dispatch

  import java.nio.ByteBuffer
  import kotlin.test.Test
  import kotlin.test.assertEquals
  import kotlin.test.assertNotNull
  import kotlin.test.assertNull
  import org.raku.nqp.runtime.CallSiteDescriptor
  import org.raku.nqp.runtime.unit.ProgramUnitTestSupport
  import org.raku.nqp.runtime.unit.UnitCodec
  import org.raku.nqp.sixmodel.SerializationContext

  class DispatchSlotCodecTest {
      private val csd = CallSiteDescriptor(byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_STR), null)

      /** A program guarding arg 0 by the bootstrap's KnowHOW type and a
       *  string literal on arg 1, invoking the KnowHOW type object's
       *  STable-carrying object as a stand-in callee: every reference is
       *  in __6MODEL_CORE__, so it persists. */
      private fun program(tc: org.raku.nqp.runtime.ThreadContext): DispatchProgram {
          val knowhow = tc.gc.KnowHOW!!
          return DispatchProgram(csd,
              listOf(Guard.OfType(ValueSource.Arg(0), knowhow.st),
                     Guard.Concreteness(ValueSource.Arg(0), false),
                     Guard.Literal(ValueSource.Arg(1), DispatchValue(ArgKind.STR, "new_type")),
                     Guard.OfHll(ValueSource.Arg(0), knowhow.st.hllOwner)),
              Outcome.InvokeCode(ValueSource.Literal(ArgKind.OBJ, knowhow),
                  CaptureShape(listOf(ValueSource.Arg(0), ValueSource.Literal(ArgKind.INT, 3L)),
                      CallSiteDescriptor(byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_INT), null))),
              emptyList(), ResumeKind.NONE, emptyList(), null)
      }

      @Test fun aProgramOverScObjectsRoundTripsToTheSameText() {
          val tc = ProgramUnitTestSupport.tc()
          val p = program(tc)
          val persisted = assertNotNull(DispatchSlotCodec.persist(p))
          val bytes = UnitCodec.encode(DispatchSlot.serializer(), DispatchSlot(listOf(persisted)))
          val back = UnitCodec.decode(DispatchSlot.serializer(), ByteBuffer.wrap(bytes))
          val realised = assertNotNull(DispatchSlotCodec.realise(tc, back.programs.single()))
          assertEquals(DispatchDump.describe(p), DispatchDump.describe(realised))
      }

      @Test fun anObjectInNoScMakesTheProgramUnpersistable() {
          val tc = ProgramUnitTestSupport.tc()
          val orphan = tc.gc.KnowHOW!!.st.REPR.type_object_for(tc, null)   // a fresh type object, in no SC
          val p = DispatchProgram(csd, listOf(Guard.Literal(ValueSource.Arg(0), DispatchValue(ArgKind.OBJ, orphan))),
              Outcome.Value(ValueSource.Arg(0)), emptyList(), ResumeKind.NONE, emptyList(), null)
          assertNull(DispatchSlotCodec.persist(p))
      }

      @Test fun aReferenceThatDoesNotResolveDropsTheProgram() {
          val tc = ProgramUnitTestSupport.tc()
          val ghost = PProgram(PDescriptor(byteArrayOf(0), null),
              listOf(PGuardType(PArg(0), PRef("no-such-sc", 0, PRef.STABLE))),
              POutcomeValue(PArg(0)), emptyList(), ResumeKind.NONE, emptyList(), null, null)
          assertNull(DispatchSlotCodec.realise(tc, ghost))
      }
  }
  ```
  If `tc.gc.KnowHOW` is not the field's name, take the KnowHOW type
  object from `KnowHOWBootstrapper`'s result the way `SerializationContextTest`
  gets an SC object (read that test first); the point is any object
  rooted in `__6MODEL_CORE__`. If `REPR.type_object_for(tc, null)` is not
  the REPR API's spelling, use `tc.gc.BOOTCode`'s REPR with `null` HOW as
  the tests in `runtime/` already do; the point is an object with `sc == null`.

- [ ] **Step 4: Run it, expect compile failure** (`DispatchSlotCodec`
  undefined): `./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.dispatch.DispatchSlotCodecTest' -q`

- [ ] **Step 5: Write `DispatchSlotCodec.kt`**:
  ```kotlin
  package org.raku.nqp.dispatch

  import org.raku.nqp.runtime.CallSiteDescriptor
  import org.raku.nqp.runtime.CodeRef
  import org.raku.nqp.runtime.ThreadContext
  import org.raku.nqp.sixmodel.STable
  import org.raku.nqp.sixmodel.SerializationContext
  import org.raku.nqp.sixmodel.SixModelObject

  /** A reference no serialization context names; caught at the top of
   *  persist/realise, never escapes. */
  class Unpersistable(what: String) : RuntimeException(what)

  /**
   * DispatchProgram <-> PProgram. persist() returns null for a program
   * with a reference that has no SC address (C0: 1.1 % of them; the
   * classes are listed in the findings); realise() returns null when a
   * persisted reference does not resolve in this process (an SC not
   * loaded yet, an index past the table, an empty root slot), and the
   * site then records as it always did. Both directions are total
   * functions of their input: no state, no caching.
   */
  object DispatchSlotCodec {
      /* ----- to the persisted form ----- */

      fun persist(p: DispatchProgram): PProgram? = try { program(p) } catch (_: Unpersistable) { null }

      private fun program(p: DispatchProgram): PProgram = PProgram(
          descriptor(p.descriptor), p.guards.map { guard(it) }, outcome(p.outcome),
          p.resumptions.map { PResumption(it.dispatcher.id, shape(it.initArgs)) },
          p.resumeKind,
          p.resumeLevels.map { l ->
              PLevel(l.dispatcher.id, descriptor(l.initDescriptor), l.guards.map { guard(it) },
                  l.newState?.let { source(it) }, l.requireNoFurther) },
          p.bindControl?.let { PBind(it.failureFlag, it.successFlag, it.onSuccessToo) },
          p.bindFailureProgram?.let { program(it) })

      private fun descriptor(d: CallSiteDescriptor) = PDescriptor(d.argFlags.copyOf(), d.names?.toList())

      private fun typeName(obj: SixModelObject): String =
          if (obj.stInitialized) obj.st.debugName ?: "?" else "?"

      /* The SC's index maps answer 0 / throw for an absent key, so every
       * index is validated by reading the root slot back. */
      private fun objectIndex(sc: SerializationContext, obj: SixModelObject): Int {
          val i = sc.getObjectIndex(obj)
          return if (i >= 0 && i < sc.objectCount() && sc.getObject(i) === obj) i else -1
      }
      private fun codeIndex(sc: SerializationContext, obj: SixModelObject): Int {
          if (obj !is CodeRef) return -1
          val i = try { sc.getCodeIndex(obj) } catch (_: NullPointerException) { -1 }
          return if (i >= 0 && i < sc.coderefCount() && sc.getCodeRef(i) === obj) i else -1
      }

      fun ref(obj: SixModelObject?): PRef? {
          if (obj == null) return null
          val sc = obj.sc ?: throw Unpersistable("object of ${typeName(obj)} in no SC")
          val oi = objectIndex(sc, obj)
          if (oi >= 0) return PRef(sc.handle, oi, PRef.OBJ)
          val ci = codeIndex(sc, obj)
          if (ci >= 0) return PRef(sc.handle, ci, PRef.CODE)
          throw Unpersistable("object of ${typeName(obj)} not in the root set of ${sc.handle}")
      }

      fun ref(st: STable?): PRef? {
          if (st == null) return null
          val sc = st.sc ?: throw Unpersistable("STable ${st.debugName} in no SC")
          val i = try { sc.getSTableIndex(st) } catch (_: NullPointerException) { -1 }
          if (i >= 0 && i < sc.stableCount() && sc.getSTable(i) === st) return PRef(sc.handle, i, PRef.STABLE)
          throw Unpersistable("STable ${st.debugName} not in the root set of ${sc.handle}")
      }

      private fun literal(kind: ArgKind, value: Any?): PLiteral = when (kind) {
          ArgKind.OBJ -> PLiteral(kind, ref(value as SixModelObject?), 0, 0.0, null)
          ArgKind.INT, ArgKind.UINT -> PLiteral(kind, null, (value as Number).toLong(), 0.0, null)
          ArgKind.NUM -> PLiteral(kind, null, 0, (value as Number).toDouble(), null)
          ArgKind.STR -> PLiteral(kind, null, 0, 0.0, value as String?)
      }

      private fun source(s: ValueSource): PSource = when (s) {
          is ValueSource.Arg -> PArg(s.index)
          is ValueSource.ResumeInitArg -> PResumeInitArg(s.level, s.index)
          is ValueSource.Literal -> literal(s.kind, s.value)
          is ValueSource.Attribute -> PAttribute(source(s.from), ref(s.classHandle), s.name, s.kind)
          is ValueSource.How -> PHow(source(s.from))
          is ValueSource.Unbox -> PUnbox(source(s.from), s.kind)
          is ValueSource.Lookup -> PLookup(source(s.table), source(s.key))
          is ValueSource.ResumeState -> PResumeState(s.level)
      }

      private fun guard(g: Guard): PGuard = when (g) {
          is Guard.OfType -> PGuardType(source(g.on), ref(g.type))
          is Guard.Concreteness -> PGuardConcreteness(source(g.on), g.concrete)
          is Guard.Literal -> PGuardLiteral(source(g.on), literal(g.expected.kind, g.expected.value))
          is Guard.NotLiteralObj -> PGuardNotLiteralObj(source(g.on), ref(g.rejected))
          is Guard.OfHll -> PGuardHll(source(g.on), g.hll?.name)
      }

      private fun shape(c: CaptureShape) = PShape(c.sources.map { source(it) }, descriptor(c.descriptor))

      private fun outcome(o: Outcome): POutcome = when (o) {
          is Outcome.Value -> POutcomeValue(source(o.source))
          is Outcome.InvokeCode -> POutcomeInvoke(source(o.callee), shape(o.args))
          is Outcome.InvokeSyscall -> POutcomeSyscall(o.syscall.name, shape(o.args))
      }

      /* ----- from the persisted form ----- */

      fun realise(tc: ThreadContext, p: PProgram): DispatchProgram? =
          try { program(tc, p) } catch (_: Unpersistable) { null }

      private fun program(tc: ThreadContext, p: PProgram): DispatchProgram {
          val out = DispatchProgram(descriptor(p.descriptor), p.guards.map { guard(tc, it) }, outcome(tc, p.outcome),
              p.resumptions.map { ResumptionSpec(dispatcher(tc, it.dispatcher), shape(tc, it.initArgs)) },
              p.resumeKind,
              p.resumeLevels.map { l ->
                  ResumptionLevel(dispatcher(tc, l.dispatcher), descriptor(l.initDescriptor),
                      l.guards.map { guard(tc, it) }, l.newState?.let { source(tc, it) }, l.requireNoFurther) },
              p.bindControl?.let { BindControl(it.failureFlag, it.successFlag, it.onSuccessToo) })
          p.bindFailure?.let { out.bindFailureProgram = program(tc, it) }
          return out
      }

      private fun descriptor(d: PDescriptor) = CallSiteDescriptor(d.flags.copyOf(), d.names?.toTypedArray())

      private fun sc(tc: ThreadContext, handle: String): SerializationContext =
          tc.gc.scs[handle] ?: throw Unpersistable("no SC $handle")

      private fun obj(tc: ThreadContext, r: PRef?): SixModelObject? {
          if (r == null) return null
          val sc = sc(tc, r.handle)
          val o: SixModelObject? = when (r.kind) {
              PRef.OBJ -> if (r.index in 0 until sc.objectCount()) sc.getObject(r.index) else null
              PRef.CODE -> if (r.index in 0 until sc.coderefCount()) sc.getCodeRef(r.index) else null
              else -> null
          }
          return o ?: throw Unpersistable("${r.handle}:${r.index} (kind ${r.kind}) is empty")
      }

      private fun stable(tc: ThreadContext, r: PRef?): STable? {
          if (r == null) return null
          val sc = sc(tc, r.handle)
          if (r.kind != PRef.STABLE || r.index !in 0 until sc.stableCount())
              throw Unpersistable("${r.handle}:${r.index} is not an STable slot")
          return sc.getSTable(r.index) ?: throw Unpersistable("${r.handle}:${r.index} STable is empty")
      }

      private fun dispatcher(tc: ThreadContext, id: String): Dispatcher =
          tc.gc.dispatchers.findOrNull(id) ?: throw Unpersistable("no dispatcher $id")

      private fun literal(tc: ThreadContext, l: PLiteral): Any? = when (l.kind) {
          ArgKind.OBJ -> obj(tc, l.obj)
          ArgKind.INT, ArgKind.UINT -> l.i
          ArgKind.NUM -> l.n
          ArgKind.STR -> l.s
      }

      private fun source(tc: ThreadContext, s: PSource): ValueSource = when (s) {
          is PArg -> ValueSource.Arg(s.index)
          is PResumeInitArg -> ValueSource.ResumeInitArg(s.level, s.index)
          is PLiteral -> ValueSource.Literal(s.kind, literal(tc, s))
          is PAttribute -> ValueSource.Attribute(source(tc, s.from), obj(tc, s.classHandle), s.name, s.kind)
          is PHow -> ValueSource.How(source(tc, s.from))
          is PUnbox -> ValueSource.Unbox(source(tc, s.from), s.kind)
          is PLookup -> ValueSource.Lookup(source(tc, s.table), source(tc, s.key))
          is PResumeState -> ValueSource.ResumeState(s.level)
      }

      private fun guard(tc: ThreadContext, g: PGuard): Guard = when (g) {
          is PGuardType -> Guard.OfType(source(tc, g.on), stable(tc, g.type))
          is PGuardConcreteness -> Guard.Concreteness(source(tc, g.on), g.concrete)
          is PGuardLiteral -> Guard.Literal(source(tc, g.on), DispatchValue(g.expected.kind, literal(tc, g.expected)))
          is PGuardNotLiteralObj -> Guard.NotLiteralObj(source(tc, g.on), obj(tc, g.rejected))
          is PGuardHll -> Guard.OfHll(source(tc, g.on), g.hll?.let { tc.gc.getHLLConfigFor(it) })
      }

      private fun shape(tc: ThreadContext, s: PShape) = CaptureShape(s.sources.map { source(tc, it) }, descriptor(s.descriptor))

      private fun outcome(tc: ThreadContext, o: POutcome): Outcome = when (o) {
          is POutcomeValue -> Outcome.Value(source(tc, o.source))
          is POutcomeInvoke -> Outcome.InvokeCode(source(tc, o.callee), shape(tc, o.args))
          is POutcomeSyscall -> Outcome.InvokeSyscall(
              try { Syscalls.find(tc, o.syscall) } catch (e: Exception) { throw Unpersistable("no syscall ${o.syscall}") },
              shape(tc, o.args))
      }
  }
  ```
  Constructor parameter names above are those of `DispatchModel.kt`
  (`Guard.OfType(on, type)`, `Guard.Literal(on, expected)`,
  `Guard.NotLiteralObj(on, rejected)`, `Guard.OfHll(on, hll)`,
  `ValueSource.Attribute(from, classHandle, name, kind)`,
  `Outcome.InvokeCode(callee, args)`, `Outcome.InvokeSyscall(syscall, args)`,
  `ResumptionSpec(dispatcher, initArgs)`, `ResumptionLevel(dispatcher,
  initDescriptor, guards, newState, requireNoFurther)`, `BindControl(
  failureFlag, successFlag, onSuccessToo)`, `DispatchProgram(descriptor,
  guards, outcome, resumptions, resumeKind, resumeLevels, bindControl)`).
  `DispatchDump.ref`/`objectIndex`/`codeIndex` duplicate the three
  helpers here: delete them from `DispatchDump.kt` and call
  `DispatchSlotCodec`'s, mapping `Unpersistable` to the `NP(...)` text.

- [ ] **Step 6: Run the tests**: same command as Step 4, plus `--tests 'org.raku.nqp.runtime.unit.UnitCodecTest'`. Expected: all pass. Run the whole `:nqp-runtime:test` once (36 -> 40).

- [ ] **Step 7: Commit (nqp)**:
  ```
  Dispatch: the persisted program -- DispatchSlot schema and DispatchSlotCodec (Phase C)
  ```

## Task 4: The site address, the consumer, verify mode, the counters

**Files:**
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchBootstrap.kt` (`DispatchCallSite` fields; `created`)
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/Dispatch.kt` (`fallback`, `record`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt` (register), `UnitStore.kt` (`entryPrefix`, `absoluteSlot`)
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java:824-840` (`EngineSite`), `NqpProgramBuilder.java:575-576`
- Modify: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt:589-597` (stats line)
- Test: `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchPersistTest.kt`

**Interfaces:**
- Consumes: Task 3's `DispatchSlotCodec`, `DispatchSlot`; `UnitStore.dispatchSlot`;
  `ProgramUnit.identityNamespace()`; `ProgramIdentity` (`namespace`, `programIndex`).
- Produces: `DispatchCallSite.unitNamespace: String?`, `.programIndex: Int`,
  `.ordinal: Int`, `.restored: Boolean`, `.verifyPrograms: List<DispatchProgram>?`;
  `DispatchPersist.register(namespace: String, store: UnitStore)`,
  `.store(namespace): UnitStore?`, `.restore(tc, site): List<DispatchProgram>`,
  `.mode`, the counters `restored`, `restoredSites`, `dropped`,
  `recorded`, `verifyMatched`, `verifyMismatched`, `verifyUnseen` (AtomicLong);
  `UnitStore.entryPrefix: String`, `UnitStore.absoluteSlot(programIndex, ordinal): Int`;
  `DispatchBootstrap.created: AtomicLong`.

- [ ] **Step 1: `UnitStore`** — add after `dispatchSlotCount`:
  ```kotlin
  /** "unit" or "nested/<id>": the entry-name prefix this store reads, for the writer. */
  val entryPrefix: String get() = prefix

  /** The absolute slot index of (program, ordinal) in this unit's table, or -1. */
  fun absoluteSlot(programIndex: Int, ordinal: Int): Int {
      if (programIndex < 0 || programIndex >= header.programCount) return -1
      if (ordinal < 0 || ordinal >= programRow(programIndex, 3)) return -1
      val slot = programRow(programIndex, 2) + ordinal
      return if (slot in 0 until header.dispatchSlotCount) slot else -1
  }
  ```
  and make `dispatchSlot` compute `slot` through `absoluteSlot` (return
  null on -1) and reject `off < 0` next to the `off + len` check (ruling 12).

- [ ] **Step 2: `DispatchCallSite`** — after `identity` add:
  ```kotlin
  /** Where the site's unit.dispatch slot is: the unit's identity namespace
   *  (DispatchPersist maps it to the store), the program index and the
   *  ordinal. -1/null for an anonymous site. Set once at construction. */
  @JvmField var unitNamespace: String? = null
  @JvmField var programIndex: Int = -1
  @JvmField var ordinal: Int = -1
  /** The slot has been consulted once for this site's current life; reset()
   *  clears it, so an eval-server run re-arms from the slot. */
  @JvmField var restored: Boolean = false
  /** verify mode only: the realised persisted programs, kept aside. */
  @JvmField var verifyPrograms: List<DispatchProgram>? = null
  ```
  In `reset()`: `restored = false; verifyPrograms = null`. In `init` (a
  new block at the top of the class body): `DispatchBootstrap.created.incrementAndGet()`.
  In `object DispatchBootstrap`: `@JvmField val created = java.util.concurrent.atomic.AtomicLong()`.

- [ ] **Step 3: Write the failing test** `DispatchPersistTest.kt`:
  ```kotlin
  package org.raku.nqp.dispatch

  import java.lang.invoke.MethodType
  import java.nio.ByteBuffer
  import kotlin.test.Test
  import kotlin.test.assertEquals
  import kotlin.test.assertTrue
  import org.raku.nqp.runtime.CallSiteDescriptor
  import org.raku.nqp.runtime.unit.ProgramUnitTestSupport
  import org.raku.nqp.runtime.unit.UnitCodec
  import org.raku.nqp.runtime.unit.UnitImage
  import org.raku.nqp.runtime.unit.UnitImageWriter
  import org.raku.nqp.runtime.unit.UnitStore

  class DispatchPersistTest {
      /** The shared fixture's image with slot 1 (program 0, ordinal 1) filled. */
      private fun storeWith(slot: ByteArray): UnitStore {
          val base = ProgramUnitTestSupport.image()
          val img = UnitImage(base.unitId, base.hll, base.scHandle, base.scDesc, base.serializedCodeRefCount,
              base.mainlineQbid, base.entryQbid, base.deserializeQbid, base.loadQbid, base.blocks, base.programs,
              base.dispatchCounts, base.serialized, base.nested, mapOf(1 to slot))
          return UnitStore.open(ByteBuffer.wrap(UnitImageWriter.bytes(img)), "/x/fixture.jar")
      }

      @Test fun restoreRealisesTheSlotsProgramsAndCountsThem() {
          val tc = ProgramUnitTestSupport.tc()
          val knowhow = tc.gc.KnowHOW!!
          val csd = CallSiteDescriptor(byteArrayOf(CallSiteDescriptor.ARG_OBJ), null)
          val p = DispatchProgram(csd, listOf(Guard.OfType(ValueSource.Arg(0), knowhow.st)),
              Outcome.Value(ValueSource.Arg(0)), emptyList(), ResumeKind.NONE, emptyList(), null)
          val bytes = UnitCodec.encode(DispatchSlot.serializer(), DispatchSlot(listOf(DispatchSlotCodec.persist(p)!!)))
          val store = storeWith(bytes)
          val ns = "/x/fixture.jar!unit-x"
          DispatchPersist.register(ns, store)
          val site = DispatchCallSite(MethodType.methodType(Void.TYPE))
          site.unitNamespace = ns; site.programIndex = 0; site.ordinal = 1
          val before = DispatchPersist.restored.get()
          val got = DispatchPersist.restore(tc, site)
          assertEquals(1, got.size)
          assertEquals(DispatchDump.describe(p), DispatchDump.describe(got[0]))
          assertEquals(before + 1, DispatchPersist.restored.get())
          assertTrue(DispatchPersist.restore(tc, DispatchCallSite(MethodType.methodType(Void.TYPE))).isEmpty(),
              "an anonymous site restores nothing")
          site.ordinal = 0
          assertTrue(DispatchPersist.restore(tc, site).isEmpty(), "an empty slot restores nothing")
      }
  }
  ```
  (`UnitImage`'s constructor order is that of `UnitImage.kt`; the fixture's
  program 0 has two slots, so absolute slot 1 is ordinal 1 of program 0.)

- [ ] **Step 4: Run it, expect a compile failure** (`DispatchPersist`):
  `./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.dispatch.DispatchPersistTest' -q`

- [ ] **Step 5: Write `DispatchPersist.kt`**:
  ```kotlin
  package org.raku.nqp.dispatch

  import java.util.concurrent.ConcurrentHashMap
  import java.util.concurrent.atomic.AtomicLong
  import org.raku.nqp.runtime.CallSiteDescriptor
  import org.raku.nqp.runtime.ThreadContext
  import org.raku.nqp.runtime.unit.UnitCodec
  import org.raku.nqp.runtime.unit.UnitStore

  /**
   * The persisted miss (milestone 7 Phase C): a site's first miss restores
   * the programs its unit.dispatch slot holds before anything is recorded.
   *
   * NQP_DISPATCH_PERSIST: unset or "on" consumes slots; "off" ignores them;
   * "verify" restores into DispatchCallSite.verifyPrograms without installing,
   * records fresh, and compares (see verify). NQP_DISPATCH_RECORD ("all" or
   * a comma-separated list of store-name prefixes) makes the process rewrite
   * the selected artifacts' slots at exit (recordAtExit, Task 5).
   *
   * Stores are registered by identity namespace (store name + "!" + unit
   * id) when a ProgramUnit initializes; they are immutable and process-wide,
   * so the eval server's runs share them.
   */
  object DispatchPersist {
      enum class Mode { ON, OFF, VERIFY }

      @JvmField val mode: Mode = when (System.getenv("NQP_DISPATCH_PERSIST")) {
          "off" -> Mode.OFF
          "verify" -> Mode.VERIFY
          else -> Mode.ON
      }

      private val stores = ConcurrentHashMap<String, UnitStore>()

      @JvmField val restored = AtomicLong()
      @JvmField val restoredSites = AtomicLong()
      @JvmField val dropped = AtomicLong()
      @JvmField val recorded = AtomicLong()
      @JvmField val verifyMatched = AtomicLong()
      @JvmField val verifyMismatched = AtomicLong()
      @JvmField val verifyUnseen = AtomicLong()

      init {
          if (mode == Mode.VERIFY) {
              System.err.println("dispatch-verify: on")
              Runtime.getRuntime().addShutdownHook(Thread {
                  System.err.println("dispatch-verify: matched=$verifyMatched mismatched=$verifyMismatched unseen=$verifyUnseen")
              })
          }
      }

      @JvmStatic
      fun register(namespace: String, store: UnitStore) { stores.putIfAbsent(namespace, store) }

      fun store(namespace: String): UnitStore? = stores[namespace]

      /** The slot's programs realised against this process, empty when the
       *  site is anonymous, the slot empty, or nothing resolves. */
      fun restore(tc: ThreadContext, site: DispatchCallSite): List<DispatchProgram> {
          val ns = site.unitNamespace ?: return emptyList()
          val store = stores[ns] ?: return emptyList()
          val bytes = store.dispatchSlot(site.programIndex, site.ordinal) ?: return emptyList()
          val slot = try { UnitCodec.decode(DispatchSlot.serializer(), bytes) }
                     catch (e: Exception) { throw IllegalStateException("unit ${ns}: dispatch slot of program ${site.programIndex} ordinal ${site.ordinal} does not decode: ${e.message}", e) }
          val out = ArrayList<DispatchProgram>(slot.programs.size)
          for (p in slot.programs) {
              val r = DispatchSlotCodec.realise(tc, p)
              if (r == null) dropped.incrementAndGet() else out.add(r)
          }
          if (out.isNotEmpty()) { restored.addAndGet(out.size.toLong()); restoredSites.incrementAndGet() }
          return out
      }

      /** verify mode: after a fresh recording, every kept-aside program that
       *  applies to the recorded call must read the same as the recording. */
      fun verify(tc: ThreadContext, site: DispatchCallSite, recorded: DispatchProgram,
                 descriptor: CallSiteDescriptor, args: Array<Any?>) {
          val kept = site.verifyPrograms ?: return
          val ctx = Dispatch.guardContext(tc, descriptor, args)
          var applicable = 0
          val text = DispatchDump.describe(recorded)
          for (p in kept) {
              if (!Captures.sameShape(p.descriptor, descriptor) || !p.guardsMatch(ctx)) continue
              applicable++
              val theirs = DispatchDump.describe(p)
              if (theirs == text) verifyMatched.incrementAndGet()
              else {
                  verifyMismatched.incrementAndGet()
                  System.err.println("dispatch-verify: MISMATCH ${site.identity} ${site.linkedName}\n  persisted: $theirs\n  recorded:  $text")
              }
          }
          if (applicable == 0) verifyUnseen.incrementAndGet()
      }
  }
  ```
  `Dispatch.guardContext` is new: in `Dispatch.kt` add
  `internal fun guardContext(tc: ThreadContext, descriptor: CallSiteDescriptor, args: Array<Any?>): DispatchContext = GuardCheckContext(tc, descriptor, args)`
  (the class is private; the function keeps it so). `Captures.sameShape`
  is what `run` uses at `Dispatch.kt:352`.

- [ ] **Step 6: The consumer in `Dispatch.fallback`** — after the
  interpreted-tail loop and before `val registry = tc.gc.dispatchers`:
  ```kotlin
  /* First miss of this site's life: the persisted programs, if any,
   * before a recording (milestone 7 Phase C). */
  if (!site.restored && site.unitNamespace != null) {
      site.restored = true
      when (DispatchPersist.mode) {
          DispatchPersist.Mode.ON -> {
              val persisted = DispatchPersist.restore(tc, site)
              if (persisted.isNotEmpty()) {
                  for (p in persisted) site.install(p)
                  val ctx = GuardCheckContext(tc, descriptor, args)
                  for (p in persisted) if (run(tc, ctx, p, site)) return
              }
          }
          DispatchPersist.Mode.VERIFY -> site.verifyPrograms = DispatchPersist.restore(tc, site)
          DispatchPersist.Mode.OFF -> {}
      }
  }
  ```
  In `record`, replace the install line pair with:
  ```kotlin
  DispatchPersist.recorded.incrementAndGet()
  if (bindFailureOf != null)
      bindFailureOf.program!!.bindFailureProgram = program
  else if (site != null && !record.doNotInstall)
      site.install(program)
  if (site != null && DispatchPersist.mode == DispatchPersist.Mode.VERIFY)
      DispatchPersist.verify(tc, site, program, descriptor, args)
  ```

- [ ] **Step 7: Registration and the site address.** In
  `ProgramUnit.initializeCompilationUnit`, after `gc = tc.gc`:
  `identityNamespace()?.let { org.raku.nqp.dispatch.DispatchPersist.register(it, store) }`.
  In `NqpOps.java`, change `EngineSite`'s constructor to
  `EngineSite(CallSiteDescriptor csd, ProgramIdentity identity, int ordinal)`:
  ```java
  this.site = new DispatchCallSite(MethodType.methodType(void.class));
  if (identity != null) {
      this.site.identity = identity.siteKey(ordinal);
      this.site.unitNamespace = identity.getNamespace();
      this.site.programIndex = identity.getProgramIndex();
      this.site.ordinal = ordinal;
  }
  ```
  and in `NqpProgramBuilder.java:575` pass `new NqpOps.EngineSite(csd, identity, ordinal)`
  (`ProgramIdentity` is imported there already for `identity.siteKey`).

- [ ] **Step 8: The stats line** (`NqpDispatch.kt` shutdown hook): append
  `" sitesAll=" + DispatchBootstrap.created + " restored=" + DispatchPersist.restored + " restoredSites=" + DispatchPersist.restoredSites + " dropped=" + DispatchPersist.dropped + " recorded=" + DispatchPersist.recorded`
  after `" anon=" + anonSites` (imports `org.raku.nqp.dispatch.DispatchBootstrap`,
  `org.raku.nqp.dispatch.DispatchPersist`).

- [ ] **Step 9: Tests and a smoke.** Run Step 4's command: pass. Rebuild
  the runtime jars; then `NQP_DISPATCH_STATS=1 RAKUDO_RAKUAST=1 ./rakudo-j -e '' 2>&1 | grep 'dispatch stats:'`
  Expected: the line carries `sitesAll=`, `restored=0 restoredSites=0
  dropped=0 recorded=` with `recorded` close to 5023 (no slot is filled
  yet). Then `NQP_DISPATCH_PERSIST=verify ... 2>&1 | grep dispatch-verify`
  Expected: `dispatch-verify: on` and `dispatch-verify: matched=0 mismatched=0 unseen=N`.
  Record `sitesAll - sites` (the runtime-made site count) in the ledger.

- [ ] **Step 10: Commit (nqp)**:
  ```
  Dispatch: restore a site's persisted programs at its first miss; verify mode; the counters (Phase C)
  ```

## Task 5: The recorder and the artifact rewriter

**Files:**
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitDispatchWriter.kt`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitImageWriter.kt` (`put` internal),
  `UnitStore.kt` (init check of slot windows)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt` (`recordAtExit`)
- Test: `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitDispatchWriterTest.kt`

**Interfaces:**
- Consumes: `DispatchBootstrap.sites()`, `DispatchSlotCodec.persist`,
  `DispatchDump.describe`, `UnitStore.entryPrefix/absoluteSlot/name`,
  `ZipDirectory.read`, `UnitCodec`, `UnitHeader`.
- Produces: `UnitDispatchWriter.rewrite(path: String, slots: Map<String, Map<Int, ByteArray>>)`
  (outer key = entry prefix `"unit"` or `"nested/<id>"`, inner key =
  absolute slot index); `DispatchPersist.recordAtExit()` installed from
  `DispatchPersist`'s init when `NQP_DISPATCH_RECORD` is set.

- [ ] **Step 1: Write the failing test**:
  ```kotlin
  package org.raku.nqp.runtime.unit

  import java.io.File
  import java.nio.ByteBuffer
  import kotlin.test.Test
  import kotlin.test.assertContentEquals
  import kotlin.test.assertEquals
  import kotlin.test.assertFailsWith
  import kotlin.test.assertNotNull
  import kotlin.test.assertNull

  class UnitDispatchWriterTest {
      private fun bytesOf(b: ByteBuffer) = ByteArray(b.remaining()).also { b.duplicate().get(it) }

      @Test fun fillsTheNamedSlotsKeepsTheRestAndCopiesEveryOtherEntry() {
          val nestedStore = UnitStore.open(ByteBuffer.wrap(UnitImageWriter.bytes(ProgramUnitTestSupport.image())), "<n>")
          val image = ProgramUnitTestSupport.image(nested = mapOf("n1" to nestedStore))
          val f = File.createTempFile("unit-", ".jar"); f.deleteOnExit()
          f.writeBytes(UnitImageWriter.bytes(UnitImage(image.unitId, image.hll, image.scHandle, image.scDesc,
              image.serializedCodeRefCount, image.mainlineQbid, image.entryQbid, image.deserializeQbid, image.loadQbid,
              image.blocks, image.programs, image.dispatchCounts, image.serialized, image.nested, mapOf(0 to byteArrayOf(1, 2, 3)))))
          val before = UnitStore.open(f.path)
          val recordsBefore = bytesOf(before.entry(UnitStore.RECORDS)!!)
          val serializedBefore = bytesOf(before.entry(UnitStore.SERIALIZED)!!)

          UnitDispatchWriter.rewrite(f.path, mapOf(
              "unit" to mapOf(2 to byteArrayOf(9, 9)),          // program 2, ordinal 0
              "nested/n1" to mapOf(1 to byteArrayOf(4, 5, 6))))   // program 0, ordinal 1 of the nested unit

          val after = UnitStore.open(f.path)
          assertContentEquals(byteArrayOf(1, 2, 3), bytesOf(assertNotNull(after.dispatchSlot(0, 0))), "an unnamed slot keeps its bytes")
          assertNull(after.dispatchSlot(0, 1), "an unnamed empty slot stays empty")
          assertContentEquals(byteArrayOf(9, 9), bytesOf(assertNotNull(after.dispatchSlot(2, 0))))
          assertContentEquals(byteArrayOf(4, 5, 6), bytesOf(assertNotNull(after.nested("n1")!!.dispatchSlot(0, 1))))
          assertContentEquals(recordsBefore, bytesOf(after.entry(UnitStore.RECORDS)!!))
          assertContentEquals(serializedBefore, bytesOf(after.entry(UnitStore.SERIALIZED)!!))
          assertEquals(before.header.dispatchSlotCount, after.header.dispatchSlotCount)
          assertEquals(PROG2_TEXT, after.program(2))
      }

      @Test fun refusesASlotOutsideTheTable() {
          val f = File.createTempFile("unit-", ".jar"); f.deleteOnExit()
          f.writeBytes(UnitImageWriter.bytes(ProgramUnitTestSupport.image()))
          assertFailsWith<IllegalArgumentException> { UnitDispatchWriter.rewrite(f.path, mapOf("unit" to mapOf(3 to byteArrayOf(1)))) }
      }

      companion object { val PROG2_TEXT = ProgramUnitTestSupport.PROG2 }
  }
  ```

- [ ] **Step 2: Run, expect compile failure**: `./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.runtime.unit.UnitDispatchWriterTest' -q`

- [ ] **Step 3: Write `UnitDispatchWriter.kt`**:
  ```kotlin
  package org.raku.nqp.runtime.unit

  import java.io.ByteArrayOutputStream
  import java.io.File
  import java.nio.ByteBuffer
  import java.nio.ByteOrder
  import java.nio.file.Files
  import java.nio.file.StandardCopyOption
  import java.util.zip.ZipOutputStream

  /**
   * Rewrites the dispatch slots of a unit artifact in place (milestone 7
   * Phase C, the training run): for every unit in the file whose entry
   * prefix is named ("unit", "nested/<id>"), the named slots get their
   * bytes, every other slot keeps what it had, the .index slot rows are
   * repointed and the .dispatch entry rebuilt; every other entry is copied
   * byte for byte. The result goes to <path>.tmp and is renamed over the
   * original, so a process that has the old file mapped keeps reading the
   * old inode.
   */
  object UnitDispatchWriter {
      fun rewrite(path: String, slots: Map<String, Map<Int, ByteArray>>) {
          val file = File(path)
          val whole = ByteBuffer.wrap(file.readBytes()).order(ByteOrder.LITTLE_ENDIAN)
          val dir = ZipDirectory.read(whole, path)
          val patched = HashMap<String, Pair<ByteArray, ByteArray>>()   // prefix -> (index, dispatch)
          for ((prefix, newSlots) in slots) {
              val index = dir["$prefix.index"] ?: throw IllegalArgumentException("$path: no $prefix.index entry to patch")
              val dispatch = dir["$prefix.dispatch"] ?: throw IllegalArgumentException("$path: no $prefix.dispatch entry to patch")
              patched[prefix] = patch(path, prefix, whole.slice(index.offset, index.size).order(ByteOrder.LITTLE_ENDIAN),
                  whole.slice(dispatch.offset, dispatch.size), newSlots)
          }
          val out = ByteArrayOutputStream(whole.capacity() + (1 shl 16))
          ZipOutputStream(out).use { z ->
              z.setMethod(ZipOutputStream.STORED)
              for ((name, e) in dir) {
                  val prefix = when {
                      name.endsWith(".index") -> name.removeSuffix(".index")
                      name.endsWith(".dispatch") -> name.removeSuffix(".dispatch")
                      else -> null
                  }
                  val p = prefix?.let { patched[it] }
                  val bytes = when {
                      p != null && name.endsWith(".index") -> p.first
                      p != null -> p.second
                      else -> ByteArray(e.size).also { whole.slice(e.offset, e.size).get(it) }
                  }
                  UnitImageWriter.put(z, name, bytes)
              }
          }
          val tmp = File(path + ".tmp")
          tmp.writeBytes(out.toByteArray())
          Files.move(tmp.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
      }

      /** The new (index, dispatch) of one unit: fixed-width slot rows in the
       *  index repointed into a dispatch entry rebuilt slot by slot. */
      private fun patch(path: String, prefix: String, index: ByteBuffer, oldDispatch: ByteBuffer,
                        newSlots: Map<Int, ByteArray>): Pair<ByteArray, ByteArray> {
          val headerLen = index.getInt(8)
          val header = UnitCodec.decode(UnitHeader.serializer(), index.slice(12, headerLen))
          val slotTable = 12 + headerLen + 16 * header.blockCount + 16 * header.programCount
          val n = header.dispatchSlotCount
          for (s in newSlots.keys) require(s in 0 until n) { "$path: $prefix dispatch slot $s of $n" }
          val bytes = ByteArray(index.remaining()).also { index.duplicate().get(it) }
          val idx = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
          val dispatch = ByteArrayOutputStream(oldDispatch.remaining() + newSlots.values.sumOf { it.size })
          for (s in 0 until n) {
              val row = slotTable + 8 * s
              val slot = newSlots[s] ?: run {
                  val off = idx.getInt(row); val len = idx.getInt(row + 4)
                  if (len == 0) null
                  else {
                      require(off >= 0 && off + len <= oldDispatch.remaining()) { "$path: $prefix dispatch slot $s at $off+$len past ${oldDispatch.remaining()}" }
                      ByteArray(len).also { oldDispatch.slice(off, len).get(it) }
                  }
              }
              if (slot == null) { idx.putInt(row, 0); idx.putInt(row + 4, 0); continue }
              idx.putInt(row, dispatch.size()); idx.putInt(row + 4, slot.size)
              dispatch.write(slot)
          }
          return bytes to dispatch.toByteArray()
      }
  }
  ```
  In `UnitImageWriter`, `private fun put` becomes `internal fun put`. In
  `UnitStore`'s `init`, after the `need` check, add the window check
  (ruling 12):
  ```kotlin
  for (i in 0 until header.programCount) {
      val first = index.getInt(programTable + 16 * i + 8); val count = index.getInt(programTable + 16 * i + 12)
      if (first < 0 || count < 0 || first + count > header.dispatchSlotCount)
          throw IllegalStateException("unit artifact $name: program $i claims dispatch slots $first+$count of ${header.dispatchSlotCount}")
  }
  ```

- [ ] **Step 4: The recorder** — in `DispatchPersist`:
  ```kotlin
  /** NQP_DISPATCH_RECORD: "all", or comma-separated store-name prefixes. */
  private val recordSelector: List<String>? = System.getenv("NQP_DISPATCH_RECORD")?.split(',')?.map { it.trim() }?.filter { it.isNotEmpty() }

  private fun selected(storeName: String): Boolean =
      recordSelector!!.any { it == "all" || storeName.startsWith(it) }

  /** The training run's exit: every recorded site of every selected
   *  store, persisted into its slot; duplicates of one slot (two live
   *  sites with one identity) merge by text, capped at MAX_PROGRAMS. */
  @JvmStatic
  fun recordAtExit() {
      val bySlot = HashMap<String, HashMap<String, HashMap<Int, LinkedHashMap<String, DispatchProgram>>>>()
      for (site in DispatchBootstrap.sites()) {
          val ns = site.unitNamespace ?: continue
          val programs = site.programs
          if (programs.isEmpty()) continue
          val store = stores[ns] ?: continue
          if (!selected(store.name)) continue
          val slot = store.absoluteSlot(site.programIndex, site.ordinal)
          if (slot < 0) continue
          val byText = bySlot.getOrPut(store.name) { HashMap() }.getOrPut(store.entryPrefix) { HashMap() }.getOrPut(slot) { LinkedHashMap() }
          for (p in programs) byText.putIfAbsent(DispatchDump.describe(p), p)
      }
      for ((path, perPrefix) in bySlot) {
          var slots = 0; var written = 0; var unpersistable = 0
          val encoded = HashMap<String, Map<Int, ByteArray>>()
          for ((prefix, perSlot) in perPrefix) {
              val m = HashMap<Int, ByteArray>()
              for ((slot, byText) in perSlot) {
                  val persisted = ArrayList<PProgram>()
                  for (p in byText.values) {
                      val pp = DispatchSlotCodec.persist(p)
                      if (pp == null) unpersistable++ else if (persisted.size < Dispatch.MAX_PROGRAMS) persisted.add(pp)
                  }
                  if (persisted.isEmpty()) continue
                  m[slot] = UnitCodec.encode(DispatchSlot.serializer(), DispatchSlot(persisted))
                  slots++; written += persisted.size
              }
              if (m.isNotEmpty()) encoded[prefix] = m
          }
          if (encoded.isEmpty()) continue
          org.raku.nqp.runtime.unit.UnitDispatchWriter.rewrite(path, encoded)
          System.err.println("dispatch-record: wrote $slots slots ($written programs, $unpersistable unpersistable) to $path")
      }
  }
  ```
  and in the `init` block: `if (recordSelector != null) Runtime.getRuntime().addShutdownHook(Thread { recordAtExit() })`.
  The hook must run after the dump hook does not matter; both only read.
  The line `dispatch-record: wrote` is the build's positive marker.

- [ ] **Step 5: Run the writer test and the whole runtime suite**: pass.

- [ ] **Step 6: Commit (nqp)**:
  ```
  Unit artifact: UnitDispatchWriter rewrites a unit's dispatch slots in place; NQP_DISPATCH_RECORD trains at exit (Phase C)
  ```

## Task 6: End to end by hand, before the builds change

**Files:** none (ledger only).

- [ ] **Step 1: Rebuild the runtime jars.** Restart no server (none running).
- [ ] **Step 2: Train nqp's lib jars by hand**:
  `cd <root>/nqp && NQP_DISPATCH_RECORD=all NQP_DISPATCH_STATS=1 ./nqp-j-gradle -e '' 2>&1 | grep -E 'dispatch-record|dispatch stats'`
  Expected: one `dispatch-record: wrote N slots ... to <path>` line per
  loaded jar under `nqp/build/jvm/share/lib` (nqp.jar, NQPCORE,
  NQPHLL, QAST, QASTNode, QRegex, nqpmo, ModuleLoader, NQPP6QRegex as
  loaded), and the stats line with `recorded=` about 1300-1500.
- [ ] **Step 3: The consumer**: the same command WITHOUT
  `NQP_DISPATCH_RECORD`. Expected: `restored=` about the previous
  `recorded`, `recorded=` under 100, `dropped=` small. Record all four.
- [ ] **Step 4: Verify**: `NQP_DISPATCH_PERSIST=verify` on the same
  command, expecting `dispatch-verify: matched=N mismatched=0 unseen=M`.
  Any mismatch is a Task 3/4 bug: fix it (the two texts say what), amend
  the commit, redo Steps 2-4.
- [ ] **Step 5: Rakudo**: `cd <root> && NQP_DISPATCH_RECORD=all NQP_DISPATCH_STATS=1 RAKUDO_RAKUAST=1 ./rakudo-j -e '' 2>&1 | grep -E 'dispatch-record|dispatch stats'`
  (writes `blib/*.jar`, `rakudo.jar` and nqp's lib jars again), then the
  consumer run and the verify run as in Steps 3-4. Expected on the
  consumer run: `recorded=` below 500 (C0's prediction), `mismatched=0`.
- [ ] **Step 6: Sizes**: `ls -l blib/CORE.c.setting.jar nqp/build/jvm/share/lib/QAST.jar` before and after, and
  `unzip -lv blib/CORE.c.setting.jar | grep dispatch`. Record the
  `unit.dispatch` sizes.
- [ ] **Step 7: `t/01-sanity` warm** (a server started AFTER the training):
  `RAKUDO_RAKUAST=1 perl t/harness5 --jvm --evalserver t/01-sanity`, 25/25,
  with the wall time. Then the same with `NQP_DISPATCH_PERSIST=verify`
  exported and the server's stderr captured: zero `MISMATCH` lines.
- [ ] **Step 8: Ledger**: every number above.

## Task 7: The build hooks and the default-mode gate

**Files:**
- Modify: `nqp/build.gradle.kts` (after `val stage2 = ...`, and `syncLib`)
- Modify: `tools/templates/jvm/Makefile.in` (the `$(J_RUNNER)` rule and a new stamp target)

- [ ] **Step 1: Gradle** — after `val stage2 = registerStage(2, ...)`:
  ```kotlin
  /* Milestone 7 Phase C: the stage2 jars are trained on the trivial
   * program before they become the lib jars. A COPY is trained, because
   * rewriting the compile tasks' outputs would make every later build
   * recompile stage2; jBootstrapFiles keeps copying the untrained jars,
   * so stage0 stays empty-tabled. */
  val stage2TrainedDir = jvmDir.dir("stage2-trained")
  val stage2Trained = tasks.register<Sync>("stage2Trained") {
      group = "nqp jvm"
      description = "Copies the stage2 jars for dispatch training"
      stageTargets.forEach { from(jvmDir.dir("stage2").file(it.jar)) }
      into(stage2TrainedDir)
      stage2.values.forEach { dependsOn(it) }
  }
  val trainDispatch = tasks.register<JavaExec>("trainDispatch") {
      group = "nqp jvm"
      description = "Runs the trivial program with NQP_DISPATCH_RECORD=all against the stage2 copy, filling its dispatch slots"
      dependsOn(stage2Trained, ":nqp-runtime:jar", ":nqp-truffle:jar", "syncTruffleModules")
      val marker = stage2TrainedDir.file("dispatch-trained.txt").asFile
      inputs.files(stageTargets.map { stage2TrainedDir.file(it.jar) })
      inputs.file(runtimeJarFile)
      outputs.file(marker)
      javaLauncher = javaToolchains.launcherFor { languageVersion = JavaLanguageVersion.of(toolchainVersion) }
      workingDir = projectDir
      mainClass = "org.raku.nqp.runtime.unit.UnitMain"
      classpath = files(stage2TrainedDir, engineJarFile)
      environment("NQP_DISPATCH_RECORD", "all")
      val log = java.io.ByteArrayOutputStream()
      errorOutput = org.apache.commons.io.output.TeeOutputStream(System.err, log)
      doFirst {
          classpath = files(stage2TrainedDir, runtimeJarFile) + files(thirdPartySorted()) + files(engineJarFile)
          jvmArgs("--enable-native-access=ALL-UNNAMED", "-Xmx$nqpStageMaxHeap", "-XX:+AllowParallelDefineClass")
          jvmArgs("--module-path", shareTruffleDir.asFile.absolutePath,
              "--add-modules", "org.graalvm.truffle,org.graalvm.truffle.runtime")
          args = listOf("${stage2TrainedDir.asFile.absolutePath}/nqp.jar",
              "--module-path=${stage2TrainedDir.asFile.absolutePath}",
              "--setting-path=${stage2TrainedDir.asFile.absolutePath}", "-e", "")
      }
      doLast {
          val text = log.toString(Charsets.UTF_8)
          check(text.contains("dispatch-record: wrote")) { "trainDispatch: no 'dispatch-record: wrote' line -- the training run recorded nothing" }
          marker.writeText(text.lines().filter { it.startsWith("dispatch-record:") }.joinToString("\n") + "\n")
      }
  }
  ```
  If `org.apache.commons.io` is not on buildSrc's classpath, replace the
  tee with a small `OutputStream` subclass in the script that writes to
  both (ten lines), no new dependency. Then change `syncLib` to take
  `from(stage2TrainedDir.file(it.jar))` and `dependsOn(trainDispatch)`
  instead of the stage2 tasks.
- [ ] **Step 2: Makefile** — in `tools/templates/jvm/Makefile.in`, before
  the `$(J_RUNNER):` rule, add a stamp target and make the runner depend
  on it:
  ```make
  # Milestone 7 Phase C: one training run of the trivial program fills the
  # dispatch slots of every artifact it loads (blib/*.jar, rakudo.jar and
  # nqp's lib jars). The stamp keeps make's graph honest; the grep is the
  # positive marker (a run that wrote nothing fails the build).
  @bpm(TRAIN_STAMP)@ = @nfp(@bpm(BLIB)@/.dispatch-trained)@

  @bpm(TRAIN_STAMP)@: @bsm(RAKUDO)@@for_specs( @bsm(SETTING_@ucspec@)@)@
  	@echo '+++ Training	dispatch slots'
  	$(NOECHO)NQP_DISPATCH_RECORD=all $(J_RUN_RAKUDO) -e '' 2>&1 | tee @nfpq(@bpm(BLIB)@/.dispatch-train.log)@
  	$(NOECHO)grep -q 'dispatch-record: wrote' @nfpq(@bpm(BLIB)@/.dispatch-train.log)@
  	$(NOECHO)touch $@

  $(J_RUNNER): @@script(create-jvm-runner.pl)@@@for_specs( @bsm(SETTING_@ucspec@)@)@ @bpm(TRAIN_STAMP)@
  ```
  (replace the existing `$(J_RUNNER):` line's prerequisites with these).
  `@bpm(...)@`/`@bsm(...)@` are the template's prefixed-variable macros
  as used on the surrounding lines; check the expansion in the generated
  `Makefile` after `perl Configure.pl --backends=jvm --gen-nqp`. `tee`
  keeps the training output visible in the build log under watched-run.
- [ ] **Step 3: The gate, default mode**, each through watched-run with
  its wall time in the ledger:
  1. `./nqp/gradlew -p nqp clean buildJvm` (`--show='trainDispatch' --show='BUILD'`);
     expect `dispatch-trained.txt` under `nqp/build/jvm/stage2-trained/`
     and the lib jars' `unit.dispatch` entries non-empty (`unzip -lv nqp/build/jvm/share/lib/QAST.jar | grep dispatch`).
  2. `raku tools/build/evalserver-sweep.raku --suite=nqp '--chunk=*' --jobs=1 --stall=7200 --max=10800`: 155 files green.
  3. `perl Configure.pl --backends=jvm --gen-nqp && raku tools/build/watched-run.raku --log=build-c.log --show='Compiling' --show='Training' --show='Setting up' -- sh -c 'make clean && make'`;
     expect `+++ Training` once and `blib/.dispatch-trained` present.
     Record CORE.c's compile time from the log.
  4. `RAKUDO_RAKUAST=1 perl t/harness5 --jvm --evalserver t/01-sanity`: 25/25.
- [ ] **Step 4: Commit** (nqp: the gradle change; rakudo: the Makefile template):
  ```
  Build: train the dispatch slots of the stage2 copy before syncLib (Phase C)
  ```
  ```
  Build: one dispatch-training run of the trivial program after the settings; the runner depends on its stamp (Phase C)
  ```

## Task 8: The verify gate and the off gate

**Files:** none (ledger; a fix wave if a mismatch appears).

- [ ] **Step 1: Smoke the mode through a server** (fail-fast rule): start
  the sweep on ONE nqp test file with `NQP_DISPATCH_PERSIST=verify`
  exported and find `dispatch-verify: on` in the server's captured
  stderr (the sweep's per-server log under its output directory; if the
  sweep does not capture server stderr, add a `--server-log=<file>`
  option to `tools/build/evalserver-sweep.raku` that redirects it — Raku,
  ten lines — before going on).
- [ ] **Step 2: Verify gate**: the nqp suite and `t/01-sanity` with
  `NQP_DISPATCH_PERSIST=verify`; then `grep -c 'dispatch-verify: MISMATCH'`
  over every server log: expect 0, and the `matched=`/`unseen=` totals
  recorded. A mismatch is a real finding: record the pair of texts in the
  ledger, fix the codec or the guard it names, amend Task 3/4's commits,
  and re-run this step.
- [ ] **Step 3: Off gate**: the same two runs with `NQP_DISPATCH_PERSIST=off`;
  the pass/fail lists must equal the default-mode runs of Task 7 (diff
  the sweep summaries).
- [ ] **Step 4: Ledger**: four wall times, the totals, the verdict.

## Task 9: Measure once, document, close the phase

**Files:**
- Modify: `tools/build/m7-rig.raku` (`parse-cold` captures `recorded=(\d+)` and `restored=(\d+)`; `cold-summary` prints them)
- Modify: `docs/jvm-unit-lazy-loading.md` ("The dispatch table": the slot schema, training, the consumer, verify, the knobs and counters)
- Modify: `docs/jvm-perf-findings-2026-09.md` ("Milestone 7, Phase C": (b) the rulings as landed, (c) the numbers, (d) the gates with clocks, (e) sizes and the compression question for the user, (f) deferred minors)
- Modify: the spec (a "Phase C: closed" note after the Phase C section, like Phase B's)
- Modify: `docs/jvm-truffle-only-plan.md` (position)
- Modify: memory `milestone-7-first-execution.md` + `MEMORY.md`

- [ ] **Step 1: Rig row `c`**: `raku tools/build/m7-rig.raku --tag=c --out=$CLAUDE_JOB_DIR/tmp/m7-rig --warm=proxy`
  (no `NQP_DISPATCH_RECORD` in the environment). Append the row to the
  ledger's table under `b`; copy `recorded=`/`restored=` from the best
  cold run's stderr next to it. The claim is on `recorded` (C0: about
  5023 -> under 500) and on the cold clocks; the histogram names what is
  left.
- [ ] **Step 2: Docs** as listed. The findings section gets the per-jar
  `unit.dispatch` sizes and the compression estimate (ruling 11) as a
  question for the user.
- [ ] **Step 3: Commit (rakudo)**: `Docs: milestone 7 Phase C closed -- the persisted miss, measured`.
- [ ] **Step 4: Rebase both trees onto their upstream mains and push**
  `--force-with-lease` to ab5tract (the standing handoff rule).

## Task 10: The milestone 7 close (spec "The close")

- [ ] **Step 1: The rig once more only if the final build differs** from
  row `c`'s (it should not).
- [ ] **Step 2: Whole `t/` once on one warm server**:
  `raku tools/build/watched-run.raku --log=t-all.log --stall=7200 --max=14400 -- raku tools/build/evalserver-sweep.raku t/01-sanity t/02-rakudo t/03-jvm t/04-nativecall t/05-messages t/06-telemetry t/07-pod-to-text t/08-performance t/09-moar t/10-qast t/11-compiler t/12-rakuast --jobs=1 --heap=6 '--chunk=*'`
  (use the directory list `ls t/` actually holds; `--chunk` = the total
  file count if `'*'` is not accepted for multiple directories). Run it
  as a plain background job. If the harness's low-memory guard kills it
  (four attempts died at 25-27 GB MemAvailable in Phase B), record the
  evidence and "not gathered" and hand the decision to the user (ruling
  15). Compare the red list with `docs/jvm-t02-rakudo-red-baseline.txt`
  and the full-suite doc. Baseline: 5078 s.
- [ ] **Step 3: Findings**: the milestone-7 summary section — one row
  per lever with both hashes and the four numbers (A1-A8 from Phase A's
  section, `b`, `c`), the promotion list of A7, the two clocks against
  2.68 s and 5078 s, CORE.c from the last make.
- [ ] **Step 4: Position** in `docs/jvm-truffle-only-plan.md`; the memory
  file; `MEMORY.md`.
- [ ] **Step 5: Rebase, gates once more if the rebase brought commits
  (`make` + `t/01-sanity`), push.** Remind the user to leave the session
  rather than `/clear`.

## Self-review (done at writing time, 2026-09-15)

**Spec coverage.** C0 -> done, recorded in Task 1. Schema -> Task 3
(ruling 1 drops the identity and descriptor index, with the reason).
Producer -> Tasks 5 and 7 (ruling 4 folds the writer into the training
process; both builds train; stage0 stays empty-tabled by ruling 6).
Consumer -> Task 4 (first miss, before `record`, realise-drop-install-
replay; eval server re-arms through `reset()`). Verification -> Task 4
(`off`, `verify`, mismatch printing) and Task 8 (the gate, both modes).
Measurement -> Task 9 (rig row `c`, the counters, the histogram). Gates
item 6 -> Task 8. The close -> Task 10. Out-of-scope items untouched;
compression -> ruling 11 (presented, not built). Risks: "valid in
training, not in the consumer" -> verify gate + `unseen` recorded as the
residual; "training and measured run confused" -> the rig's refusal is
in place and Task 9 says so.

**Placeholder scan.** None. Two places name an alternative if a spelling
differs (`tc.gc.KnowHOW`, the gradle tee) with the concrete fallback
stated.

**Type consistency.** `DispatchSlotCodec.persist/realise`,
`DispatchPersist.register/store/restore/verify/recordAtExit`,
`UnitStore.entryPrefix/absoluteSlot`, `UnitDispatchWriter.rewrite(path,
Map<String, Map<Int, ByteArray>>)`, `DispatchCallSite.unitNamespace/
programIndex/ordinal/restored/verifyPrograms`, `EngineSite(csd,
ProgramIdentity, int)` — used with the same names in every task that
mentions them.
