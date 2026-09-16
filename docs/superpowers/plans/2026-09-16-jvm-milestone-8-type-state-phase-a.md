# Milestone 8, Phase A: the type state — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking. Keep a ledger twin at
> `docs/superpowers/plans/2026-09-16-jvm-milestone-8-type-state-phase-a.ledger.md`
> (project convention: every ruling, every deferred minor, every task
> verdict, every gate with its wall time and every rig row goes in it as
> it happens, not at the end).

**Goal:** Move every fact compiled code folds out of `STable`'s mutable
fields into an immutable `TypeState` that carries its own Truffle
`Assumption`, make every writer publish a new state, and make every
consumer (the diamond-3 sites, the dispatch folder, all three guard
roads) trust a fact only under that assumption; then gate, measure rig
row `a`, and record the storm baseline.

**Architecture:** `STable.state` is a `@Volatile` reference to an
immutable `TypeState` (method cache and authority, type-check cache and
mode, the three specs, HLL owner and role, the v-table, an `Assumption`).
`STable.publish(next)` stores the new state and then invalidates the old
assumption. States are never shared, so `obj.st.state === s` implies
`obj.st` is the owner: a state-identity guard subsumes a type-identity
guard, and in compiled code the assumption folds away. `REPRData` and
`parametricity` stay on the STable; a compose or a deserialization
republishes. Consumers capture the state at resolve/record time and read
facts from that captured object; a republish deoptimizes exactly the code
that trusted it. Nothing on the wire or on disk changes: Phase A is
runtime-jar rebuilds only.

**Tech Stack:** NQP and Raku on the JVM; Oracle GraalVM 25.2.4 with
Truffle (Bytecode DSL); Kotlin for runtime code (Java only inside the
DSL-bound files `NqpOps.java`, `NqpProgramBuilder.java`,
`NqpRootNode.java`, `NqpLanguage.java`, `NqpCodeEngine.java`); Raku for
all tooling; Gradle (Kotlin DSL) for the nqp side; GNU make for the
Rakudo side.

**Spec:** `docs/superpowers/specs/2026-09-16-jvm-milestone-8-type-state-design.md`
(rakudo `22e2cc2e75`), sections 1-3 and 5 (Phase A), plus decisions 4-6.
Baselines are milestone 7's close row (spec, "Baselines"): cold
rakudo-e 2.247 s, cold nqp-e 1.198 s, misses 4931, hits 35512,
`recorded=` 195, warm `t/01-sanity` proxy 59 s.

## Global Constraints

Every task's requirements implicitly include this section. They are
milestone 7 Phase C's constraints, carried over where they still hold,
with the two changes this phase makes marked **(M8)**.

- **Work in the worktree, never the stale checkout.** The repository root
  for every path and command in this plan is
  `/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records`
  (rakudo branch `worktree-jesp-direct-lazy-records`; nested nqp branch
  `jesp-direct-lazy-records`). The session starts in the stale checkout:
  pin every path. The Bash tool's cwd drifts into `nqp/` after any
  command that `cd`s there: pin the directory in every command. Below,
  `$ROOT` means that worktree root.
- **Two git working trees.** The root is rakudo.git; `nqp/` is the nqp.git
  working tree nested inside it, gitignored, NOT a submodule. Run
  `cd $ROOT/nqp && git ...` for that tree. Label every hash with its tree
  ("nqp `8ea35ba95`" vs "rakudo `22e2cc2e75`"). Write nqp paths with the
  `nqp/` prefix. Run gradle from the root: `./nqp/gradlew -p nqp ...`.
- **`RAKUDO_RAKUAST=1` on every build, test and run.** The Makefile exports
  it into its own recipes; nothing sets it for your own invocations.
- **`NQP_CODE_RUN` and `NQP_CODE_PRECOMP` must not be set at all.** The
  compiler dies on `=0`.
- **`java` must be Oracle GraalVM 25.2.4.** Verify with `java -version`
  before any build or measurement.
- **Runtime-jar rebuild** after any edit under `nqp/src/vm/jvm/runtime/` or
  `nqp/nqp-truffle/`: `./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar
  syncRuntimeJars` (about 30 s). Restart any eval server afterwards. An
  edit to a `build.gradle.kts` reconfigures on the next gradle run.
- **(M8) The Rakudo side follows with `make`, not `make clean`.** This
  phase changes class shapes in `nqp-runtime` (`STable`, the two spec
  classes, `ContainerConfigurer`), and `rakudo-runtime.jar` compiles
  against `nqp-runtime.jar`: a plain `make` rebuilds `rakudo-runtime.jar`
  (its target depends on `$(NQP_RUNTIME_JAR)`) and re-runs the dispatch
  training stamp (which depends on both runtime jars,
  `tools/templates/jvm/Makefile.in:193`); no setting recompiles, because
  no artifact references a Java field name. Task 2 verifies that claim
  on the first `make` (no `Compiling` marker). Phase C's "never a bare
  make after a class-shape change" was about `Configure.pl --gen-nqp`
  re-bootstrapping nqp; nothing here re-bootstraps.
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
  `perl t/harness5 --jvm --evalserver`, after a Rakudo `make`). This
  phase runs that gate twice (after A1, Task 2, and after A2, Task 5)
  and takes **one rig row, `a`**, `--warm=proxy`. A failed benchmark run
  is recorded as not gathered and the number taken at the next planned
  point. Whole `t/` runs once, at the milestone close (Phase B's plan).
- **Every gate is reported with its wall time** (user rule 2026-09-15), in
  the ledger and in status updates. A bare "green" is not a report.
- **Runtime performance outranks compile time.** CORE.c is reported in
  passing from the builds; it is never a gate.
- **Tooling in Raku**, never Python or shell.
- **Every diagnostic env-gated**: `System.getenv(...)` read once into a
  `val` in runtime code; `nqp::say(...) if nqp::getenvhash()<VAR>;` in
  NQP. Never a bare print. Counters live behind `NqpDispatch.STATS`
  (`NQP_DISPATCH_STATS`); the one counter this phase adds
  (`STable.PUBLISHES`, a `LongAdder`) is always on and printed only under
  that knob.
- **Smoke-test every instrument on a short workload and require a
  positive marker** before any long run. This phase's markers: `dispatch
  stats:` with `publishes=` (Task 4), at least one assumption-trace line
  from `t/02-rakudo/type-state.t` (Task 5), `m7-rig: DONE`.
- **Kotlin, never Java**, for new code, except inside the DSL-bound Java
  files named above.
- **(M8) Truffle in `nqp-runtime` is limited to `TypeState.kt`** (the
  `Assumption` and `Truffle.getRuntime()`), the existing
  `ExceptionHandling.kt` boundary and `NFGString`. Review checks every
  runtime import of `com.oracle.truffle` against that list. The spec's
  decision 2 supersedes Phase C's "no Truffle dependency in nqp-runtime
  logic" for exactly this class.
- **No jar of any kind is committed** (user rule 2026-09-15): the nine v2
  stage0 jars stay an uncommitted working-tree change in `nqp/`; nothing
  in this plan regenerates or commits stage0. Before every nqp commit,
  `git status --short` must show the nine `src/vm/jvm/stage0/*.jar` as
  unstaged and nothing else unexpected.
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
  `use` (Test included) needs `-Ilib`: `./rakudo-j -Ilib t/02-rakudo/x.t`.
- **Read facts from the captured state object, never from `st.state`
  twice.** A consumer that captures `val s = st.state` reads every fact
  it folds from `s`, so the facts and the assumption it holds agree.
  Reading `st.state.x` and then holding `st.state.assumption` can pair a
  new fact with an old assumption across a concurrent publish.

## File structure

| file | responsibility |
|---|---|
| `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/TypeState.kt` (new) | the immutable facts object + its `Assumption`; `withFacts(...)` copy-with; `initial()` |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/STable.kt` | identity/structure fields only; `state`, `publish`, `republish`, `PUBLISHES` |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/BoolificationSpec.kt`, `InvocationSpec.kt` | constructed-complete immutable specs |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/ContainerConfigurer.kt` + the three configurers (`CodePair…`, `NativeRef…`, rakudo `RakudoContainerConfigurer.kt`) | `newContainerSpec` returns a spec; `configureContainerSpec(tc, cs, config)` fills it; the caller publishes |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt` | the writer ops publish; `composetype`/`setdebugtypename` republish |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/KnowHOWMethods.kt`, `KnowHOWBootstrapper.kt`, `reprs/KnowHOWREPRInstance.kt` | compose publishes a COPY; `composedType` back-reference; `add_method` republishes |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/BootJavaInterop.kt`, rakudo `src/vm/jvm/runtime/org/raku/rakudo/RakudoJavaInterop.kt` | interop bootstraps publish |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationReader.kt`, `SerializationWriter.kt` | reader builds one state and publishes once; writer reads `st.state` |
| `nqp/nqp-runtime/build.gradle.kts` | `testRuntimeOnly` truffle-api |
| `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/sixmodel/TypeStateTest.kt` (new) | unit tests for the state, publish, the writer ops |
| `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt` | sites capture a state; `valid()`; `republished()`; `create` drops its re-read; Mu-sink under Mu's state |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchModel.kt` | `Guard.OfType.state` (transient), `isFresh`; `DispatchProgram.isFresh` |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchCompiler.kt` | the chain tests state identity |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchBootstrap.kt` | `install` evicts stale programs |
| `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt` | folder collects states; `Program.assumptions`; `matches` tests them; `miss` refolds on stale; `publishes=` in the stats line |
| `nqp/t/jvm/19-type-state.t` (new), `t/02-rakudo/type-state.t` (new) | the two correctness tests |
| `tools/build/m7-rig.raku` | parses `publishes=` |
| docs: the ledger, `docs/jvm-perf-findings-2026-09.md`, `docs/jvm-jesp.md`, `docs/jvm-truffle-only-plan.md` | Phase A's record |

---

### Task 1: `TypeState`, `STable.publish`, every writer (nqp tree)

**Files:**
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/TypeState.kt`
- Create: `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/sixmodel/TypeStateTest.kt`
- Create: `docs/superpowers/plans/2026-09-16-jvm-milestone-8-type-state-phase-a.ledger.md`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/STable.kt` (whole file)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/BoolificationSpec.kt`, `InvocationSpec.kt` (whole files)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/ContainerConfigurer.kt:9-15`, `CodePairContainerConfigurer.kt`, `NativeRefContainerConfigurer.kt`, `src/vm/jvm/runtime/org/raku/rakudo/RakudoContainerConfigurer.kt`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt:3234-3301` (composetype, setmethcache, setmethcacheauth, settypecache, settypecheckmode, setinvokespec), `:4518-4536` (setdebugtypename, setcontspec), `:4773-4779` (setboolspec), `:7987-7995` (settypehll, settypehllrole)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/KnowHOWMethods.kt:73`, `:127-131` and the `REPR.compose` call at the end of `compose`; `reprs/KnowHOWREPRInstance.kt`; `KnowHOWBootstrapper.kt:33-38`, `:102-105`, `:145-146`, `:166-167`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/BootJavaInterop.kt:156-157`, `src/vm/jvm/runtime/org/raku/rakudo/RakudoJavaInterop.kt:823-824`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationReader.kt:509-607`
- Modify: `nqp/nqp-runtime/build.gradle.kts:43-45`

**Interfaces:**
- Produces: `class TypeState(methodCache, vTable, typeCheckCache, modeFlags, containerSpec, invocationSpec, boolificationSpec, hllOwner, hllRole, name)` with `@JvmField val assumption: Assumption`, `val methodCacheAuthoritative: Boolean`, `val typeCheckMode: Int`, `fun withFacts(...named defaults...): TypeState`, `companion fun initial(): TypeState`.
- Produces: on `STable`: `@Volatile @JvmField var state: TypeState`, `fun publish(next: TypeState)`, `fun republish()`, `companion @JvmField val PUBLISHES: LongAdder`; and, **transitionally until Task 2**, read-only properties `MethodCache`, `VTable`, `TypeCheckCache`, `ModeFlags`, `ContainerSpec`, `InvocationSpec`, `BoolificationSpec`, `hllOwner`, `hllRole` delegating to `state` (so every reader compiles and every writer fails to compile: the compiler is the writer audit).
- Produces: `BoolificationSpec(Mode: Int, Method: SixModelObject?)`, `InvocationSpec(ClassHandle, AttrName, Hint: Long, InvocationHandler)` as immutable classes with the same field names.
- Produces: `ContainerConfigurer.newContainerSpec(tc, st): ContainerSpec` and `configureContainerSpec(tc, cs: ContainerSpec, config)`.
- Produces: `KnowHOWREPRInstance.composedType: SixModelObject?`.

- [ ] **Step 1: Open the ledger**

Write `docs/superpowers/plans/2026-09-16-jvm-milestone-8-type-state-phase-a.ledger.md`:

```markdown
# SDD ledger — plan: docs/superpowers/plans/2026-09-16-jvm-milestone-8-type-state-phase-a.md

Spec: docs/superpowers/specs/2026-09-16-jvm-milestone-8-type-state-design.md
(rakudo 22e2cc2e75), sections 1-3 and 5.

BASE before Task 1: rakudo <hash of HEAD>, nqp <hash of HEAD> (the nine v2 stage0
jars are an uncommitted working-tree change in nqp/, user rule). Baseline = milestone
7's close row: cold rakudo-e 2.247 s, cold nqp-e 1.198 s, misses 4931, hits 35512,
recorded= 195, warm t/01-sanity 59 s.

Claude-Session trailer: <the executing session's URL, or "not known">.

Model policy (user rule 2026-09-11): subagents on Opus; Fable only after erroneous
output; escalations logged here.

The plan's rulings (open to the user's veto):
1. The serialization reader publishes ONCE, after the HLL facts are read and BEFORE
   parametricity and deserialize_repr_data -- the point at which the old code had
   assigned every fact field -- so any object deserialized from inside those two
   steps sees the same facts it saw before. No republish after deserialize_repr_data:
   no site folds a stub's REPR data (decont takes the slow road on a null layout,
   create pins), so there is nothing to invalidate. Deviation from the spec's
   "at the end of the STable read"; cost if wrong: a stale layout fold on a type
   whose STable was read lazily -- the nqp suite would show it.
2. `setdebugtypename` republishes, so the assumption carries the type's name for the
   trace; one extra publish per type at creation, before any code folds it.
3. Task 1 keeps read-only aliases of the old field names on STable so every reader
   compiles unchanged and every writer fails to compile; Task 2 renames the readers
   and deletes the aliases.
4. `KnowHOWREPRInstance.composedType` is an in-process back-reference (not
   serialized), matching the in-process aliasing it replaces.
5. A stale program (a type guard whose state was republished) is evicted from the
   runtime site's list at the next install, and the engine cache refolds at the next
   miss without counting toward REFOLD_AFTER.
6. `Guard.OfType.state` is transient: outside data-class equality, outside
   DispatchDump, never persisted; a restored program captures the state current at
   restore. Verify mode is unaffected.
7. `Truffle.getRuntime().createAssumption` runs in nqp-runtime (TypeState.kt);
   the runtime's gradle test task gets truffle-api as testRuntimeOnly, where the
   default (interpreter) runtime supplies assumptions.
8. The Rakudo side rebuilds with a plain `make` (rakudo-runtime.jar + the training
   stamp); Task 2 verifies no setting recompiled.
```

Fill in the two BASE hashes from `cd $ROOT && git rev-parse --short HEAD` and
`cd $ROOT/nqp && git rev-parse --short HEAD`.

- [ ] **Step 2: Write the failing unit test**

Create `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/sixmodel/TypeStateTest.kt`:

```kotlin
package org.raku.nqp.sixmodel

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotSame
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue
import org.raku.nqp.runtime.Ops
import org.raku.nqp.runtime.unit.ProgramUnitTestSupport

class TypeStateTest {
    private fun freshSTable() = STable(ProgramUnitTestSupport.tc().gc.BOOTArray!!.st.REPR, null)

    @Test fun aFreshSTableStartsWithAValidEmptyState() {
        val st = freshSTable()
        val s = st.state
        assertTrue(s.assumption.isValid)
        assertNull(s.methodCache)
        assertNull(s.typeCheckCache)
        assertEquals(0, s.modeFlags)
        assertNull(s.containerSpec)
        assertNull(s.boolificationSpec)
        assertNull(s.invocationSpec)
        assertNull(s.hllOwner)
        assertEquals(0L, s.hllRole)
        assertFalse(s.methodCacheAuthoritative)
    }

    @Test fun statesAreNeverShared() {
        assertNotSame(freshSTable().state, freshSTable().state)
    }

    @Test fun publishInstallsTheNextStateAndInvalidatesTheOld() {
        val st = freshSTable()
        val old = st.state
        val before = STable.PUBLISHES.sum()
        val next = old.withFacts(modeFlags = STable.METHOD_CACHE_AUTHORITATIVE)
        st.publish(next)
        assertSame(next, st.state)
        assertFalse(old.assumption.isValid)
        assertTrue(next.assumption.isValid)
        assertTrue(st.state.methodCacheAuthoritative)
        assertEquals(before + 1, STable.PUBLISHES.sum())
    }

    @Test fun withFactsKeepsEveryOtherFact() {
        val cache = HashMap<String, SixModelObject?>()
        val base = TypeState.initial().withFacts(methodCache = cache, hllRole = 4L, modeFlags = 2)
        val next = base.withFacts(typeCheckCache = arrayOfNulls(0))
        assertSame(cache, next.methodCache)
        assertEquals(4L, next.hllRole)
        assertEquals(2, next.modeFlags)
        assertNotSame(base.assumption, next.assumption)
        assertTrue(base.assumption.isValid, "withFacts does not publish")
    }

    @Test fun republishKeepsTheFactsUnderAFreshAssumption() {
        val st = freshSTable()
        st.publish(st.state.withFacts(hllRole = 3L))
        val old = st.state
        st.republish()
        assertNotSame(old, st.state)
        assertFalse(old.assumption.isValid)
        assertEquals(3L, st.state.hllRole)
    }

    @Test fun theWriterOpsPublish() {
        val tc = ProgramUnitTestSupport.tc()
        val type = tc.gc.BOOTHash!!
        val st = type.st
        val s0 = st.state
        Ops.setmethcacheauth(type, 1L, tc)
        val s1 = st.state
        assertNotSame(s0, s1); assertFalse(s0.assumption.isValid); assertTrue(s1.methodCacheAuthoritative)
        Ops.settypecheckmode(type, STable.TYPE_CHECK_CACHE_THEN_METHOD.toLong(), tc)
        val s2 = st.state
        assertNotSame(s1, s2); assertFalse(s1.assumption.isValid)
        assertEquals(STable.TYPE_CHECK_CACHE_THEN_METHOD, s2.typeCheckMode)
        assertTrue(s2.methodCacheAuthoritative, "the mode write keeps the authority bit")
        Ops.setboolspec(type, BoolificationSpec.MODE_HAS_ELEMS.toLong(), null, tc)
        val s3 = st.state
        assertNotSame(s2, s3); assertFalse(s2.assumption.isValid)
        assertEquals(BoolificationSpec.MODE_HAS_ELEMS, s3.boolificationSpec!!.Mode)
        Ops.settypehllrole(type, 5L, tc)
        assertEquals(5L, st.state.hllRole)
        assertFalse(s3.assumption.isValid)
        assertTrue(st.state.assumption.isValid)
    }
}
```

- [ ] **Step 3: Put truffle-api on the runtime's test path and run the test to see it fail**

In `nqp/nqp-runtime/build.gradle.kts`, after the `compileOnly(...)` line (:43), add:

```kotlin
    // TypeState creates its Assumption through Truffle.getRuntime(); the tests run
    // without the engine module, so the default (interpreter) runtime supplies it.
    testRuntimeOnly("org.graalvm.truffle:truffle-api:${property("truffleVersion")}")
```

Run: `cd $ROOT && ./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.sixmodel.TypeStateTest' --console=plain 2>&1 | tail -20`
Expected: compilation FAILS (`Unresolved reference: TypeState`, `state`, `publish`).

- [ ] **Step 4: Write `TypeState.kt`**

```kotlin
package org.raku.nqp.sixmodel

import com.oracle.truffle.api.Assumption
import com.oracle.truffle.api.Truffle
import org.raku.nqp.runtime.HLLConfig

/**
 * The published facts of a type: what compiled code folds to constants.
 *
 * Immutable. A state belongs to exactly one STable and is replaced, never
 * mutated, through [STable.publish], which installs the next state and then
 * invalidates this one's [assumption]. Because states are never shared,
 * `obj.st.state === s` implies `obj.st` is s's owner, so a state-identity
 * guard subsumes a type-identity guard; in compiled code `assumption.isValid`
 * folds to nothing and a publish deoptimizes exactly the code that trusted it.
 *
 * Not here: `REPRData` (REPR-owned, read by the REPRs themselves) and
 * `parametricity` (a lookup table that grows). A change to either
 * republishes the state instead (Ops.composetype, SerializationReader).
 */
class TypeState(
    @JvmField val methodCache: Map<String, SixModelObject?>?,
    @JvmField val vTable: Array<SixModelObject?>?,
    @JvmField val typeCheckCache: Array<SixModelObject?>?,
    @JvmField val modeFlags: Int,
    @JvmField val containerSpec: ContainerSpec?,
    @JvmField val invocationSpec: InvocationSpec?,
    @JvmField val boolificationSpec: BoolificationSpec?,
    @JvmField val hllOwner: HLLConfig?,
    @JvmField val hllRole: Long,
    /** The owning type's debug name, so the assumption trace names the type. */
    @JvmField val name: String?,
) {
    /** Valid exactly while this state is its STable's current one. */
    @JvmField val assumption: Assumption = Truffle.getRuntime().createAssumption(name ?: "type")

    val methodCacheAuthoritative: Boolean
        get() = (modeFlags and STable.METHOD_CACHE_AUTHORITATIVE) != 0

    val typeCheckMode: Int
        get() = modeFlags and STable.TYPE_CHECK_CACHE_FLAG_MASK

    /** A new state, with a fresh assumption, differing in the named facts only. Does not publish. */
    fun withFacts(
        methodCache: Map<String, SixModelObject?>? = this.methodCache,
        vTable: Array<SixModelObject?>? = this.vTable,
        typeCheckCache: Array<SixModelObject?>? = this.typeCheckCache,
        modeFlags: Int = this.modeFlags,
        containerSpec: ContainerSpec? = this.containerSpec,
        invocationSpec: InvocationSpec? = this.invocationSpec,
        boolificationSpec: BoolificationSpec? = this.boolificationSpec,
        hllOwner: HLLConfig? = this.hllOwner,
        hllRole: Long = this.hllRole,
        name: String? = this.name,
    ): TypeState = TypeState(methodCache, vTable, typeCheckCache, modeFlags, containerSpec,
        invocationSpec, boolificationSpec, hllOwner, hllRole, name)

    companion object {
        /** The state every STable starts in: no facts, valid. One per STable, never shared. */
        @JvmStatic
        fun initial(): TypeState = TypeState(null, null, null, 0, null, null, null, null, 0L, null)
    }
}
```

- [ ] **Step 5: Rewrite `STable.kt`**

Replace the field block (everything after the companion object) with:

```kotlin
    /** REPR-specific data (a RakuObjectREPRData for P6opaque). REPR-owned; a change republishes [state]. */
    @JvmField var REPRData: Any? = null

    /** The type object. */
    lateinit var WHAT: SixModelObject

    /** Parametric/parameterized type data; a growing lookup table, so a cache, not a fact. */
    @JvmField var parametricity: AbstractParametricity? = null

    /**
     * The type's published facts. Every reader goes through here; the only
     * writer is [publish]. Volatile: a publish on one thread is seen whole
     * by every other (the state object itself is immutable).
     */
    @Volatile @JvmField var state: TypeState = TypeState.initial()

    /** The stash / package. */
    @JvmField var WHO: SixModelObject? = null

    /** The serialization context this STable belongs to, if any. */
    @JvmField var sc: SerializationContext? = null

    /** The HLL owner's debug name for the type, if it set one. */
    @JvmField var debugName: String? = null

    /**
     * Installs the next state, then invalidates the previous one's assumption
     * -- in that order, so a thread that read a valid assumption and then reads
     * the state sees a state at least as new as the assumption (the ordering
     * NqpDispatch.Cache.publish uses).
     */
    fun publish(next: TypeState) {
        val old = state
        state = next
        old.assumption.invalidate()
        PUBLISHES.increment()
    }

    /** The same facts under a fresh assumption: for a change outside the state (REPR data). */
    fun republish() = publish(state.withFacts())

    /* ----- TRANSITIONAL (Task 1 only; Task 2 renames the readers and deletes these) -----
     * Read-only views under the old field names, so every reader keeps compiling and
     * every writer fails to compile: the compiler enumerates the writers. */
    val MethodCache: Map<String, SixModelObject?>? get() = state.methodCache
    val VTable: Array<SixModelObject?>? get() = state.vTable
    val TypeCheckCache: Array<SixModelObject?>? get() = state.typeCheckCache
    val ModeFlags: Int get() = state.modeFlags
    val ContainerSpec: ContainerSpec? get() = state.containerSpec
    val InvocationSpec: InvocationSpec? get() = state.invocationSpec
    val BoolificationSpec: BoolificationSpec? get() = state.boolificationSpec
    val hllOwner: HLLConfig? get() = state.hllOwner
    val hllRole: Long get() = state.hllRole
}
```

Add to the companion object, after `NO_HINT`:

```kotlin
        /** Every publish in the process; printed as `publishes=` in the dispatch stats line. */
        @JvmField val PUBLISHES = java.util.concurrent.atomic.LongAdder()
```

Delete the old `MethodCache`, `VTable`, `TypeCheckCache`, `ModeFlags`,
`TypeCacheId` (never read or written anywhere), `ContainerSpec`,
`InvocationSpec`, `BoolificationSpec`, `hllOwner`, `hllRole` fields. Keep
the class header, the constants and the KDoc.

- [ ] **Step 6: The two specs become immutable**

`BoolificationSpec.kt` (keep the `MODE_*` constants in the companion):

```kotlin
class BoolificationSpec(@JvmField val Mode: Int, @JvmField val Method: SixModelObject?) {
    companion object { /* the nine MODE_* constants, unchanged */ }
}
```

`InvocationSpec.kt`:

```kotlin
class InvocationSpec(
    @JvmField val ClassHandle: SixModelObject?,
    @JvmField val AttrName: String?,
    @JvmField val Hint: Long,
    @JvmField val InvocationHandler: SixModelObject?,
)
```

- [ ] **Step 7: The configurer API: build, then the caller publishes**

`ContainerConfigurer.kt`:

```kotlin
abstract class ContainerConfigurer {
    /**
     * A fresh, unconfigured container spec for the type. The CALLER publishes
     * it (Ops.setcontspec, SerializationReader) once it is complete: a spec
     * is never reachable through a state before it is filled.
     */
    abstract fun newContainerSpec(tc: ThreadContext, st: STable): ContainerSpec

    /** Fills the spec from its configuration hash. */
    abstract fun configureContainerSpec(tc: ThreadContext, cs: ContainerSpec, config: SixModelObject)
}
```

`CodePairContainerConfigurer.kt`:

```kotlin
open class CodePairContainerConfigurer : ContainerConfigurer() {
    override fun newContainerSpec(tc: ThreadContext, st: STable): ContainerSpec = CodePairContainerSpec()

    override fun configureContainerSpec(tc: ThreadContext, cs: ContainerSpec, config: SixModelObject) {
        cs as CodePairContainerSpec
        val fetch = config.at_key_boxed(tc, "fetch")
        if (Ops.isnull(fetch) == 1L)
            throw ExceptionHandling.dieInternal(tc,
                "Container spec 'code_pair' must be configured with a fetch")
        val store = config.at_key_boxed(tc, "store")
        if (Ops.isnull(store) == 1L)
            throw ExceptionHandling.dieInternal(tc,
                "Container spec 'code_pair' must be configured with a store")
        cs.fetchCode = fetch
        cs.storeCode = store
    }
}
```

`NativeRefContainerConfigurer.kt`: `newContainerSpec` returns
`NativeRefContainerSpec()`; `configureContainerSpec(tc, cs, config)` stays
empty. `src/vm/jvm/runtime/org/raku/rakudo/RakudoContainerConfigurer.kt`:
`newContainerSpec` returns `RakudoContainerSpec()`;
`configureContainerSpec(tc, cs, config)` does `cs as RakudoContainerSpec`
then the four `grabOneValue` assignments as today.

- [ ] **Step 8: The writer ops in `Ops.kt`**

`composetype` (:3234):

```kotlin
    @JvmStatic
    fun composetype(obj: SixModelObject?, reprinfo: SixModelObject?, tc: ThreadContext): SixModelObject? {
        val st = obj!!.st
        st.REPR.compose(tc, st, reprinfo!!)
        /* The REPR data changed (a P6opaque layout was installed): a site that
         * folded the old REPR data is invalidated by the fresh assumption. */
        st.republish()
        return obj
    }
```

`setmethcache`: replace the three lines from `obj!!.st.MethodCache = cache` with

```kotlin
        val st = obj!!.st
        st.publish(st.state.withFacts(methodCache = cache))
        if (st.sc != null)
            scwbSTable(tc, st)
        return obj
```

`setmethcacheauth`:

```kotlin
    @JvmStatic
    fun setmethcacheauth(obj: SixModelObject?, flag: Long, tc: ThreadContext): SixModelObject? {
        val st = obj!!.st
        var newFlags = st.state.modeFlags and (STable.METHOD_CACHE_AUTHORITATIVE.inv())
        if (flag != 0L)
            newFlags = newFlags or STable.METHOD_CACHE_AUTHORITATIVE
        st.publish(st.state.withFacts(modeFlags = newFlags))
        if (st.sc != null)
            scwbSTable(tc, st)
        return obj
    }
```

`settypecache`: after building `cache`, `val st = obj!!.st;
st.publish(st.state.withFacts(typeCheckCache = cache))`, then the write
barrier as today.

`settypecheckmode`:

```kotlin
    @JvmStatic
    fun settypecheckmode(obj: SixModelObject?, mode: Long, tc: ThreadContext): SixModelObject? {
        val st = obj!!.st
        st.publish(st.state.withFacts(modeFlags = mode.toInt() or
            (st.state.modeFlags and (STable.TYPE_CHECK_CACHE_FLAG_MASK.inv()))))
        if (st.sc != null)
            scwbSTable(tc, st)
        return obj
    }
```

(The two `st.state` reads here are the same object unless a concurrent
publish lands between them; the op is a compile-time metamodel call and
has no concurrent writer, and the write goes through `publish` either way.)

`setinvokespec`:

```kotlin
    @JvmStatic
    fun setinvokespec(obj: SixModelObject?, ch: SixModelObject?,
            name: String?, invocationHandler: SixModelObject?, tc: ThreadContext): SixModelObject? {
        val st = obj!!.st
        st.publish(st.state.withFacts(invocationSpec = InvocationSpec(ch, name, STable.NO_HINT, invocationHandler)))
        return obj
    }
```

`setdebugtypename` (:4519):

```kotlin
    @JvmStatic
    fun setdebugtypename(type: SixModelObject?, debugName: String?, tc: ThreadContext): SixModelObject? {
        val st = type!!.st
        st.debugName = debugName
        /* The assumption carries the name, for the trace. */
        st.publish(st.state.withFacts(name = debugName))
        return type
    }
```

`setcontspec` (:4525):

```kotlin
    @JvmStatic
    fun setcontspec(obj: SixModelObject?, confname: String?, confarg: SixModelObject?, tc: ThreadContext): SixModelObject? {
        val st = obj!!.st
        if (st.state.containerSpec != null)
            ExceptionHandling.dieInternal(tc, "Cannot change a type's container specification")
        val cc = tc.gc.contConfigs.get(confname)
            ?: throw ExceptionHandling.dieInternal(tc, "No such container spec " + confname)
        val cs = cc.newContainerSpec(tc, st)
        cc.configureContainerSpec(tc, cs, confarg!!)
        st.publish(st.state.withFacts(containerSpec = cs))
        return obj
    }
```

`setboolspec` (:4773):

```kotlin
    @JvmStatic
    fun setboolspec(obj: SixModelObject?, mode: Long, method: SixModelObject?, tc: ThreadContext): SixModelObject? {
        val st = obj!!.st
        st.publish(st.state.withFacts(boolificationSpec = BoolificationSpec(mode.toInt(), method)))
        return obj
    }
```

`settypehll` / `settypehllrole` (:7987-7995):

```kotlin
    @JvmStatic
    fun settypehll(type: SixModelObject?, language: String, tc: ThreadContext): SixModelObject? {
        val st = type!!.st
        st.publish(st.state.withFacts(hllOwner = tc.gc.getHLLConfigFor(language)))
        return type
    }
    @JvmStatic
    fun settypehllrole(type: SixModelObject?, role: Long, tc: ThreadContext): SixModelObject? {
        val st = type!!.st
        st.publish(st.state.withFacts(hllRole = role))
        return type
    }
```

- [ ] **Step 9: KnowHOW: compose publishes a copy, add_method republishes**

`reprs/KnowHOWREPRInstance.kt`: add

```kotlin
    /**
     * The type this meta-object composed (or was bootstrapped as the HOW of),
     * whose STable holds a published COPY of [methods]; add_method after that
     * republishes the copy. In-process only, like the aliasing it replaces.
     */
    @JvmField var composedType: SixModelObject? = null
```

`KnowHOWMethods.kt` `compose` (:126-131): replace the three `typeObj!!.st.…`
assignments with

```kotlin
            /* Publish a COPY of the live table: add_method after compose must
             * not edit a published cache (it republishes instead). */
            val st = typeObj!!.st
            st.publish(st.state.withFacts(methodCache = HashMap(self.methods!!),
                modeFlags = STable.METHOD_CACHE_AUTHORITATIVE,
                typeCheckCache = arrayOf(typeObj)))
            self.composedType = typeObj
```

Then find the `REPR.compose(` call at the end of the same method (after the
attribute protocol is built) and add `st.republish()` immediately after it.

`KnowHOWMethods.kt` `add_method` (:73): after `self.methods!![name!!] = method` add

```kotlin
            /* A type this meta-object composed holds a published copy of the table. */
            val composed = self.composedType
            if (composed != null) {
                val cst = composed.st
                cst.publish(cst.state.withFacts(methodCache = HashMap(self.methods!!)))
            }
```

`KnowHOWBootstrapper.kt`:
- `:33-38`: each `X.st.hllRole = R` becomes `X.st.let { it.publish(it.state.withFacts(hllRole = R)) }`.
- `:102-105`:

```kotlin
        knowhow.st.publish(knowhow.st.state.withFacts(methodCache = HashMap(methods),
            modeFlags = STable.METHOD_CACHE_AUTHORITATIVE))
        knowhowHow.st.publish(knowhowHow.st.state.withFacts(methodCache = HashMap(methods),
            modeFlags = STable.METHOD_CACHE_AUTHORITATIVE))
        knowhowHow.composedType = knowhow
```

- `:145-146` (KnowHOWAttribute): `typeObj.st.publish(typeObj.st.state.withFacts(methodCache =
  HashMap(methods), modeFlags = STable.METHOD_CACHE_AUTHORITATIVE)); metaObj.composedType = typeObj`.
- `:166-167` (`bootType`): `typeObj.st.publish(typeObj.st.state.withFacts(methodCache =
  HashMap(metaObj.methods!!), modeFlags = STable.METHOD_CACHE_AUTHORITATIVE)); metaObj.composedType = typeObj`.

Then run `grep -n 'methods' nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/KnowHOWBootstrapper.kt`
and confirm every fill of a `methods` map precedes the publish that copies
it. If a fill follows its publish, add `X.st.publish(X.st.state.withFacts(methodCache =
HashMap(map)))` after the last fill and record it in the ledger.

- [ ] **Step 10: The two interop bootstraps**

`BootJavaInterop.kt:156-157` and `RakudoJavaInterop.kt:823-824`, both:

```kotlin
        val fst = freshType.st
        fst.publish(fst.state.withFacts(methodCache = names,
            modeFlags = fst.state.modeFlags or STable.METHOD_CACHE_AUTHORITATIVE))
```

- [ ] **Step 11: The serialization reader builds one state**

Replace `deserializeSTableInner` (`SerializationReader.kt:509-607`) from the
method-cache read through the HLL read with:

```kotlin
        /* Method cache and v-table. */
        val methodCacheRef = readRef()
        val methodCache: Map<String, SixModelObject?>? =
            if (Ops.isnull(methodCacheRef) == 0L) (methodCacheRef as VMHashInstance).storage else null
        val vTable = arrayOfNulls<SixModelObject>(orig.getLong().toInt())
        for (j in vTable.indices)
            vTable[j] = readRef()
        /* Type check cache. */
        val tcCacheSize = orig.getLong().toInt()
        var typeCheckCache: Array<SixModelObject?>? = null
        if (tcCacheSize > 0) {
            val cache = arrayOfNulls<SixModelObject>(tcCacheSize)
            for (j in cache.indices)
                cache[j] = readRef()
            typeCheckCache = cache
        }
        /* Mode flags. */
        val modeFlags = orig.getLong().toInt()
        /* Boolification spec. */
        var boolSpec: BoolificationSpec? = null
        if (orig.getLong() != 0L) {
            val mode = orig.getLong().toInt()
            boolSpec = BoolificationSpec(mode, readRef())
        }
        /* Container spec: built complete, then published with the rest. */
        var contSpec: ContainerSpec? = null
        if (orig.getLong() != 0L) {
            if (version >= 5) {
                val ccName = readStr()
                val cc = tc.gc.contConfigs[ccName]
                    ?: throw RuntimeException("Unknown container config $ccName")
                val cs = cc.newContainerSpec(tc, st)
                cs.deserialize(tc, st, this)
                contSpec = cs
            } else {
                throw RuntimeException("Unable to deserialize old container spec format")
            }
        }
        /* Invocation spec. */
        var invSpec: InvocationSpec? = null
        if (version >= 5) {
            if (orig.getLong() != 0L) {
                val classHandle = readRef()
                val attrName = lookupString(orig.getInt())
                val hint = orig.getLong().toInt().toLong()
                invSpec = InvocationSpec(classHandle, attrName, hint, readRef())
            }
        }
        /* HLL stuff. */
        var hllOwner: HLLConfig? = null
        var hllRole = 0L
        if (version >= 6) {
            hllOwner = tc.gc.getHLLConfigFor(readStr()!!)
            hllRole = orig.getLong()
        }
        /* One publish, here: the point at which every fact field used to be
         * assigned, so an object deserialized from inside the parametricity
         * or REPR-data reads below sees the same facts it saw before (ledger
         * ruling 1). No republish after deserialize_repr_data: no site folds
         * a stub's REPR data. */
        st.publish(TypeState(methodCache, vTable, typeCheckCache, modeFlags, contSpec, invSpec,
            boolSpec, hllOwner, hllRole, st.debugName))
```

Keep the parametricity block and the `st.REPR.deserialize_repr_data(tc, st, this)`
call after it unchanged. Add `import org.raku.nqp.runtime.HLLConfig` if the file
lacks it. Check the argument order of the two spec constructors against
Step 6 and the old field-by-field order (the reader used to read `Mode`
then `Method`; `ClassHandle`, `AttrName`, `Hint`, `InvocationHandler`),
which the code above preserves as read order.

- [ ] **Step 12: Compile: the compiler lists any writer this plan missed**

Run: `cd $ROOT && ./nqp/gradlew -p nqp :nqp-runtime:compileKotlin --console=plain 2>&1 | grep -E 'error|warning: unused' | head -40`

Expected: zero errors. Any `Val cannot be reassigned` names a writer this
plan missed: convert it to a publish the same way and add it to the ledger.
(The rakudo tree's two files are compiled by Task 2's `make`.)

- [ ] **Step 13: Run the unit tests**

Run: `cd $ROOT && ./nqp/gradlew -p nqp :nqp-runtime:test --console=plain 2>&1 | grep -E 'TypeStateTest|tests completed|FAILED|BUILD' | head`
Expected: `BUILD SUCCESSFUL`, no `FAILED`, the whole runtime test set green
(it was 36 s in milestone 7).

- [ ] **Step 14: Sync the jars and smoke the nqp runner**

Run: `cd $ROOT && ./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars --console=plain 2>&1 | tail -3`
Then: `cd $ROOT/nqp && ./nqp-j-gradle -e 'say(1)'` (expected `1`), and
`cd $ROOT/nqp && ./nqp-j-gradle t/jvm/17-object-layout.t` (50/50) and
`t/jvm/18-rebless-layout.t` (14/14).

- [ ] **Step 15: Commit (nqp tree only)**

```bash
cd $ROOT/nqp && git status --short   # the nine stage0 jars unstaged, nothing else unexpected
cd $ROOT/nqp && git add src/vm/jvm/runtime/org/raku/nqp/sixmodel/TypeState.kt \
  src/vm/jvm/runtime/org/raku/nqp/sixmodel/STable.kt \
  src/vm/jvm/runtime/org/raku/nqp/sixmodel/BoolificationSpec.kt \
  src/vm/jvm/runtime/org/raku/nqp/sixmodel/InvocationSpec.kt \
  src/vm/jvm/runtime/org/raku/nqp/sixmodel/ContainerConfigurer.kt \
  src/vm/jvm/runtime/org/raku/nqp/sixmodel/CodePairContainerConfigurer.kt \
  src/vm/jvm/runtime/org/raku/nqp/sixmodel/NativeRefContainerConfigurer.kt \
  src/vm/jvm/runtime/org/raku/nqp/sixmodel/KnowHOWMethods.kt \
  src/vm/jvm/runtime/org/raku/nqp/sixmodel/KnowHOWBootstrapper.kt \
  src/vm/jvm/runtime/org/raku/nqp/sixmodel/reprs/KnowHOWREPRInstance.kt \
  src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationReader.kt \
  src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt \
  src/vm/jvm/runtime/org/raku/nqp/runtime/BootJavaInterop.kt \
  nqp-runtime/build.gradle.kts \
  nqp-runtime/src/test/kotlin/org/raku/nqp/sixmodel/TypeStateTest.kt
STAMP="$(date +%F)T20:30:00+02:00"
cd $ROOT/nqp && GIT_AUTHOR_DATE=$STAMP GIT_COMMITTER_DATE=$STAMP git commit -F - <<'MSG'
Object model: the type state -- an immutable TypeState with an Assumption per STable (milestone 8, A1)

The facts compiled code folds (method cache and authority, type-check
cache and mode, the three specs, HLL owner and role, the v-table) move
out of STable's mutable fields into one immutable TypeState carrying a
Truffle Assumption. STable.publish installs the next state and then
invalidates the previous assumption. Every writer publishes: the set/
publish ops, KnowHOW's compose (a COPY of its live table, and add_method
republishes through the new composedType back-reference), the KnowHOW
bootstrap, both Java interop bootstraps, and the serialization reader,
which now builds one state per STable and publishes it once. Container
specs are built complete and published by the caller (the configurer API
returns the spec); the boolification and invocation specs are immutable.
composetype and setdebugtypename republish. The old field names stay as
read-only views until the readers are renamed (next commit).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
```

Add `Claude-Session:` to the trailer when the session knows its URL. Record
the commit hash and the `:nqp-runtime:test` wall time in the ledger.

---

### Task 2: readers read `st.state`, the Rakudo side follows, first gate

**Files:**
- Modify: every `.kt` under `nqp/src/vm/jvm/runtime/`, `nqp/nqp-truffle/src/`, `src/vm/jvm/runtime/` that reads one of the nine old names (the list is the survey's grep; the sed below finds them)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/STable.kt` (delete the transitional block)
- Modify: `src/vm/jvm/runtime/org/raku/rakudo/RakudoContainerConfigurer.kt`, `RakudoJavaInterop.kt` (written in Task 1, committed here), `RakOps.kt:455,910` (by the sed)

**Interfaces:**
- Consumes: `STable.state` and the `TypeState` field names from Task 1.
- Produces: the final `STable` shape (no fact fields, no aliases). Every later task reads `x.st.state.<fact>`.

- [ ] **Step 1: Rename every reader, mechanically**

```bash
cd $ROOT
FILES=$(grep -rlE '\.(MethodCache|TypeCheckCache|ModeFlags|ContainerSpec|BoolificationSpec|InvocationSpec|hllOwner|hllRole|VTable)\b' \
    nqp/src/vm/jvm/runtime nqp/nqp-truffle/src src/vm/jvm/runtime --include='*.kt' \
  | grep -v 'sixmodel/STable.kt' | grep -v 'sixmodel/TypeState.kt')
for f in $FILES; do
  sed -i -E '/^import /! { s/\.MethodCache\b/.state.methodCache/g; s/\.TypeCheckCache\b/.state.typeCheckCache/g; s/\.ModeFlags\b/.state.modeFlags/g; s/\.ContainerSpec\b/.state.containerSpec/g; s/\.BoolificationSpec\b/.state.boolificationSpec/g; s/\.InvocationSpec\b/.state.invocationSpec/g; s/\.hllOwner\b/.state.hllOwner/g; s/\.hllRole\b/.state.hllRole/g; s/\.VTable\b/.state.vTable/g }' "$f"
done
git -C $ROOT diff --stat; cd $ROOT/nqp && git diff --stat
```

The `/^import /!` guard keeps `import org.raku.nqp.sixmodel.ContainerSpec`
lines intact. Then inspect every changed line once
(`cd $ROOT/nqp && git diff | grep '^[-+]' | grep -v '^+++\|^---'`): the
only acceptable change is an old name becoming `.state.<newName>` on a
value read. A `.state.state.` (a line Task 1 already converted) or a
changed type reference must be fixed by hand.

- [ ] **Step 2: Delete the transitional block from `STable.kt`**

Remove the nine `val … get() = state.…` lines and their comment. Run:
`cd $ROOT && ./nqp/gradlew -p nqp :nqp-runtime:compileKotlin :nqp-truffle:compileKotlin --console=plain 2>&1 | grep -E 'error' | head -20`
Expected: zero errors. Any `Unresolved reference` names a reader the sed
could not see (a receiver that is not followed by the name on the same
line): convert by hand.

- [ ] **Step 3: Runtime tests, jars, nqp smoke**

Run: `cd $ROOT && ./nqp/gradlew -p nqp :nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars --console=plain 2>&1 | grep -E 'FAILED|BUILD' | head`
Expected: `BUILD SUCCESSFUL`. Then `cd $ROOT/nqp && ./nqp-j-gradle -e 'say(1)'` prints `1`.

- [ ] **Step 4: The Rakudo side: `make`, and prove no setting recompiled**

```bash
cd $ROOT && java -version 2>&1 | head -1    # Oracle GraalVM 25.2.4
cd $ROOT && RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/m8-a1-make.log \
    --show='Compiling' --show='Training' --show='rakudo-runtime' --stall=1800 -- make
```

Expected: exit 0; the log shows the `rakudo-runtime` gradle jar build and
one `+++ Training dispatch slots` line, and **no `Compiling` marker**. If a
setting does recompile, let it finish, then record in the ledger which
target pulled it and why (global constraint "(M8) The Rakudo side follows
with make"); if `rakudo-runtime` fails to compile, the error names a
Rakudo-tree reader or writer the sed missed: fix, rerun. Record the wall
time.

- [ ] **Step 5: Gate: the nqp suite and `t/01-sanity`, with wall times**

```bash
cd $ROOT && RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/m8-a1-nqp-suite.log \
    --show='files=' --show='red=' --stall=7200 --max=10800 -- \
    raku tools/build/evalserver-sweep.raku --suite=nqp '--chunk=*' --jobs=1
cd $ROOT && RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/m8-a1-sanity.log \
    --show='Result' --show='Files=' --stall=1800 -- perl t/harness5 --jvm --evalserver t/01-sanity
```

Expected: nqp suite 155/155 green; `t/01-sanity` 25/25. Both wall times
into the ledger. A red is a regression of this task (the runtime is
functionally unchanged by design): bisect by reverting the sed on the
file the failing test names before anything else.

- [ ] **Step 6: Commit both trees**

```bash
STAMP="$(date +%F)T20:45:00+02:00"
cd $ROOT/nqp && git add -u src/vm/jvm/runtime nqp-truffle/src && git status --short
cd $ROOT/nqp && GIT_AUTHOR_DATE=$STAMP GIT_COMMITTER_DATE=$STAMP git commit -F - <<'MSG'
Object model: readers read st.state; the transitional views are gone (milestone 8, A1)

Every reader of a type fact goes through STable.state now (one dependent
load next to the lookup it feeds), and STable carries only identity and
structure: REPR, HOW, WHAT, WHO, sc, debugName, REPRData, parametricity
and the state. The v2 artifacts and stage0 are untouched: no wire, no
serialization format, no field name reaches disk.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
cd $ROOT && git add src/vm/jvm/runtime/org/raku/rakudo/RakudoContainerConfigurer.kt \
  src/vm/jvm/runtime/org/raku/rakudo/RakudoJavaInterop.kt src/vm/jvm/runtime/org/raku/rakudo/RakOps.kt \
  docs/superpowers/plans/2026-09-16-jvm-milestone-8-type-state-phase-a.ledger.md
cd $ROOT && GIT_AUTHOR_DATE=$STAMP GIT_COMMITTER_DATE=$STAMP git commit -F - <<'MSG'
Runtime: the Rakudo container configurer and interop publish a type state (milestone 8, A1)

Follows nqp's TypeState: the configurer returns its spec for the caller to
publish, the Java interop bootstrap publishes the method cache, RakOps reads
container specs through st.state. Gate: nqp suite 155/155, t/01-sanity
25/25 (wall times in the ledger).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
```

---

### Task 3: the sites trust a fact only under its state's assumption (A2, part 1)

**Files:**
- Modify: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt` (the `Site` base :62-73, `miss` :311-318, and every site: `SinkSite` :93-135, `HllizeSite` :158-205, `DecontSite` :220-310, `IsConcreteSite` :365-368, `IsTypeSite` :398-480, `RvCheckSite` :511-600, `CreateSite` :622-680, `BigIntSite` :687-811)
- Create: `nqp/t/jvm/19-type-state.t`

**Interfaces:**
- Consumes: `STable.state: TypeState`, `TypeState.assumption`, `typeCheckCache`, `typeCheckMode`, `modeFlags`, `containerSpec`, `hllOwner`, `hllRole` (Task 1/2).
- Produces: on `NqpTypeOps.Site`: `@CompilationFinal var state: TypeState?`, `fun valid(): Boolean`, `fun reset()` (concrete; calls the new abstract `clear()`), and the file-private `republished(site)`.

- [ ] **Step 1: Write the failing test (the site half)**

Create `nqp/t/jvm/19-type-state.t`:

```
# Milestone 8, the type state: a site or a dispatch program that folded a
# type's published facts sees a republish. istype folds the type-check
# cache (this half); a method call folds the resolved method (Task 4's
# half, tests 1-2).

plan(4);

class Foo { method m() { 'old' } }
my $o := Foo.new;
my $r := '';
my $i := 0;
while $i < 200 { $r := $o.m; $i++ }
is($r, 'old', 'the method call resolves before the republish');
my %new := nqp::clone(Foo.HOW.method_table(Foo));
%new<m> := sub ($self) { 'new' };
nqp::setmethcache(Foo, %new);
is($o.m, 'new', 'a dispatch program recorded before setmethcache misses and re-records');

class Bar { }
class Baz { }
my $b := Bar.new;
my $t := -1;
$i := 0;
while $i < 200 { $t := nqp::istype($b, Baz); $i++ }
is($t, 0, 'istype is false before settypecache');
nqp::settypecache(Bar, [Bar, Baz]);
is(nqp::istype($b, Baz), 1, 'an istype site resolved before settypecache sees the new cache');
```

- [ ] **Step 2: Run it to see the istype half fail**

Run: `cd $ROOT/nqp && ./nqp-j-gradle t/jvm/19-type-state.t`
Expected: test 4 `not ok` (the site answers its cached 0). Tests 1-2 may
pass or fail at this point; Task 4 owns them. If test 4 passes already,
the loop did not reach the site's fast path: raise the iteration count
to 2000 and re-run; it must fail before Step 3.

- [ ] **Step 3: The `Site` base: a captured state, `valid()`, `clear()`**

Replace the `Site` class (`NqpTypeOps.kt:62-73`) with:

```kotlin
    abstract class Site {
        /** Guard failures so far; at MAX_MISSES the site is generic for good. */
        @JvmField @field:CompilationFinal var misses: Int = 0
        /**
         * The state of the type the site resolved on. The site's constants
         * were read from THIS object, and its assumption is the licence to
         * trust them: compiled code folds `valid()` to nothing, and a
         * republish deoptimizes exactly the code that trusted it.
         */
        @JvmField @field:CompilationFinal var state: TypeState? = null
        init { SITES.add(this) }
        /** Back to unresolved, misses included. */
        fun reset() { clear(); state = null; misses = 0 }
        /** The site's own speculation fields back to unresolved. */
        protected abstract fun clear()
        /** Whether the site may still (re)speculate. */
        fun mayResolve(): Boolean = misses < MAX_MISSES
        /** Give the site up: generic from here on. */
        fun pin() { misses = MAX_MISSES }
        /** The resolved type's facts still hold. */
        fun valid(): Boolean { val s = state; return s != null && s.assumption.isValid }
    }
```

Add `import org.raku.nqp.sixmodel.TypeState` to the file. Below `miss`
(:318) add:

```kotlin
    /**
     * The type republished: forget the speculation WITHOUT spending a miss
     * (a republish is not polymorphism); the next run re-resolves against the
     * new facts, or pins if it cannot.
     */
    private fun republished(site: Site) {
        CompilerDirectives.transferToInterpreterAndInvalidate()
        val misses = site.misses
        site.reset()
        site.misses = misses
        if (DEBUG) debug("republished " + site.javaClass.simpleName)
    }
```

In every site class, rename `override fun reset()` to `override fun clear()`
and drop the `misses = 0` from its body (the base does it). `IsConcreteSite`'s
`clear()` is empty (`override fun clear() {}`); its state stays null and it
never calls `valid()`.

- [ ] **Step 4: Each site captures the state it resolves on and checks it first**

The pattern, applied to every site whose fast path reads a resolved field
(`SinkSite`, `HllizeSite`, `DecontSite`, `IsTypeSite`, `RvCheckSite`,
`CreateSite`, `BigIntSite`): where the fast path does

```kotlin
            if (st != null) {
                if (<identity guards>) return <constant>
                miss(site)
            }
```

it becomes

```kotlin
            if (st != null) {
                if (!site.valid()) republished(site)
                else if (<identity guards>) return <constant>
                else miss(site)
            }
```

and the resolver captures the state FIRST and reads its facts from the
captured object (global constraint "read facts from the captured state
object"). Concretely:

`resolveSink` (:117-129):

```kotlin
        val st = o.st
        val s = st.state
        val trivial = s.containerSpec != null || run {
            val m = Ops.findmethodNonFatal(o, "sink", tc)
            Ops.isnull(m) == 1L || m === muSink(tc)
        }
        site.st = st
        site.trivial = trivial
        site.state = s
```

and Mu's sink (:133-141) keyed under Mu's state:

```kotlin
    /** Mu's `sink` (the Raku language's null value is Mu) under Mu's state. */
    private class MuSink(@JvmField val state: TypeState, @JvmField val method: SixModelObject?)
    @Volatile private var muSinkCache: MuSink? = null
    @TruffleBoundary
    private fun muSink(tc: ThreadContext): SixModelObject? {
        val cached = muSinkCache
        if (cached != null && cached.state.assumption.isValid) return cached.method
        val mu = tc.gc.getHLLConfigFor("Raku").nullValue ?: return null
        val s = mu.st.state
        val m = Ops.findmethodNonFatal(mu, "sink", tc)
        if (Ops.isnull(m) == 0L) muSinkCache = MuSink(s, m)
        return m
    }
```

`resolveHllize` (:180-186): `val s = st.state; val identity = hllizeIsIdentity(s, NqpRaw.hll(cu)); if (identity) { site.st = st; site.state = s } else site.pin()`, and `hllizeIsIdentity` takes a `TypeState` and reads `s.hllOwner` / `s.hllRole` (its two reads at :191 and :193).

`decont` (:243): the non-container early exit reads the live state,
`val ost = NqpRaw.st(o); if (ost != null && ost.state.containerSpec == null) return o` (already the
sed's form). `resolveDecont` (:282-304): `val st = o.st ?: …; val s = st.state; val cs =
s.containerSpec ?: …` and on success `site.state = s` beside `site.st = st`.
The fast path: `if (st != null) { if (!site.valid()) republished(site) else if (ost === st) { … as
today … } else miss(site) }`. The per-object `o.layout === layout` compare and its variant `miss`
stay exactly as they are (a shape check).

`istype` / `resolveIsType` (:451-471): the site gains a second state,
because the answer depends on the type operand's `NEEDS_ACCEPTS` flag:

```kotlin
    class IsTypeSite : Site() {
        @JvmField val objDecont = DecontSite()
        @JvmField val typeDecont = DecontSite()
        @JvmField @field:CompilationFinal var objSt: STable? = null
        @JvmField @field:CompilationFinal var typeSt: STable? = null
        /** The type operand's state: its NEEDS_ACCEPTS flag went into the answer. */
        @JvmField @field:CompilationFinal var typeState: TypeState? = null
        @JvmField @field:CompilationFinal var result: Long = 0
        override fun clear() { objSt = null; typeSt = null; typeState = null; result = 0 }
        fun typeValid(): Boolean { val s = typeState; return s != null && s.assumption.isValid }
    }
```

fast path (:433-437):

```kotlin
            if (objSt != null) {
                if (!site.valid() || !site.typeValid()) republished(site)
                else if (NqpRaw.st(v) === objSt && NqpRaw.st(t) === site.typeSt) return site.result
                else miss(site)
            }
```

resolver:

```kotlin
    @TruffleBoundary
    private fun resolveIsType(site: IsTypeSite, v: SixModelObject, t: SixModelObject) {
        val vst = v.st
        val tst = t.st
        if (vst == null || tst == null || Ops.isnull(v) == 1L) { site.pin(); return }
        val vs = vst.state
        val ts = tst.state
        val cache = vs.typeCheckCache ?: run { site.pin(); return }
        val mode = vs.typeCheckMode
        val needsAccept = (ts.modeFlags and STable.TYPE_CHECK_NEEDS_ACCEPTS) != 0
        for (entry in cache) {
            if (entry === t) {
                site.objSt = vst; site.typeSt = tst; site.state = vs; site.typeState = ts; site.result = 1
                return
            }
        }
        if ((mode and STable.TYPE_CHECK_CACHE_THEN_METHOD) == 0 && !needsAccept) {
            site.objSt = vst; site.typeSt = tst; site.state = vs; site.typeState = ts; site.result = 0
            return
        }
        site.pin()
    }
```

Update the class comment at :46-48 ("trust `STable.TypeCheckCache` to be
stable once published") to say the trust is checked: the site holds the
states it read and their assumptions.

`resolveRvCheck` (:571-583): `val vst = v.st; val vs = vst?.state; … if (vst != null && vs != null
&& routine is SixModelObject && rvCacheable(routine, tc)) { site.rvSt = vst; site.state = vs; … }`;
fast path (:524-532): `if (cached != null) { if (!site.valid()) republished(site) else if (routine
=== cached && …) return rv else miss(site) }`.

`create` (:630-651): the fast path drops the REPR-data re-read:

```kotlin
            if (st != null) {
                if (!site.valid()) republished(site)
                else if (NqpRaw.st(type) === st) {
                    val layout = site.layout
                    if (layout != null) return layout.newInstance()
                    val repr = site.repr
                    if (repr != null) return repr.allocate(tc, st)
                    miss(site)
                }
                else miss(site)
            }
```

`resolveCreate` (:654-665): `val st = type.st ?: …; val s = st.state; val rd = st.REPRData; …;
site.state = s; site.st = st` (the state is captured before the REPR data is read: a compose
between the two invalidates `s`, and the site re-resolves).

`resolveBigInt` (:783-811): `val s = st.state` right after the three-type check passes, and
`site.state = s` beside `site.st = st` at the end; the fast path (:713-717) gets `if
(!site.valid()) republished(site) else if (NqpRaw.st(a) === st && …) { … } else miss(site)`
(keep `debugBigMiss` on the miss branch).

- [ ] **Step 5: Rebuild the engine jar and run the test**

Run: `cd $ROOT && ./nqp/gradlew -p nqp :nqp-truffle:jar syncRuntimeJars --console=plain 2>&1 | grep -E 'error|BUILD' | head`
Then: `cd $ROOT/nqp && ./nqp-j-gradle t/jvm/19-type-state.t`
Expected: tests 3 and 4 `ok`. (Tests 1-2 are Task 4's.)

Also: `cd $ROOT/nqp && ./nqp-j-gradle t/jvm/17-object-layout.t` (50/50),
`t/jvm/18-rebless-layout.t` (14/14), and `JESP_DEBUG=1 ./nqp-j-gradle
t/jvm/19-type-state.t 2>&1 | grep -c republished` prints at least 1 (the
istype site was told, not missed).

- [ ] **Step 6: Commit (nqp tree)**

```bash
STAMP="$(date +%F)T21:00:00+02:00"
cd $ROOT/nqp && git add nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt t/jvm/19-type-state.t
cd $ROOT/nqp && GIT_AUTHOR_DATE=$STAMP GIT_COMMITTER_DATE=$STAMP git commit -F - <<'MSG'
Engine: the sited ops fold a type fact only under its state's assumption (milestone 8, A2)

Every NqpTypeOps site captures the TypeState it resolved on and reads its
constants from that object; the fast path tests the state's assumption
before its identity guards, which partial evaluation folds to nothing. A
republish tells the site (no miss spent) and it re-resolves. create drops
its per-call REPR-data re-read and layout compare; istype's trust in the
type-check cache is checked, on both operands' states; Mu's sink is cached
under Mu's state. The per-object layout compares stay: they guard shape.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
```

---

### Task 4: the dispatch programs, on all three roads (A2, part 2)

**Files:**
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchModel.kt:226-229` (`Guard.OfType`), `:411-446` (`DispatchProgram.isFresh`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchCompiler.kt:63`, `:149`, `:267-269`, `:286-289`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchBootstrap.kt:115-126` (`install`)
- Modify: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt` (`Program` :273-345, `Folder` :396-424, `Cache` :485-540, `replay`/`miss`/`matches` :624-670, the stats line :592)
- Modify: `tools/build/m7-rig.raku:55-75` (`parse-cold`)
- Create: `t/02-rakudo/type-state.t`

**Interfaces:**
- Consumes: `TypeState`, `STable.state`, `STable.PUBLISHES` (Task 1); `Guard.OfType(on, type)` and the codec's `PGuardType` decode at `DispatchSlotCodec.kt:172` (unchanged).
- Produces: `Guard.OfType.state: TypeState?` (transient), `Guard.OfType.isFresh`, `DispatchProgram.isFresh`; `NqpDispatch.Program.assumptions: Array<Assumption>`; `NqpDispatch.Cache.hasStale()`; `publishes=` in the `dispatch stats:` line and in the rig's `parse-cold`.

- [ ] **Step 1: Write the failing Rakudo test**

Create `t/02-rakudo/type-state.t`:

```raku
use lib <lib>;
use Test;
use nqp;
use MONKEY-TYPING;
# Milestone 8, the type state: a type's published facts (method cache,
# type-check cache) live in an immutable TypeState with an Assumption. A
# dispatch program or a site that folded a fact must see the change when
# the type republishes -- an augment republishes the method cache, and
# nqp::settypecache republishes the type-check cache.
plan 4;

class Foo { }
my $f = Foo.new;
my $r;
$r = $f.gist for ^200;
is $r, 'Foo.new', 'gist resolves to Mu.gist before the augment';
augment class Foo { method gist { 'augmented' } }
is $f.gist, 'augmented', 'a method-call site resolved before an augment sees the added method';

class Bar { }
class Baz { }
my $b = Bar.new;
my $t;
$t = nqp::istype($b, Baz) for ^200;
is $t, 0, 'istype is false before the type-check cache changes';
nqp::settypecache(Bar, nqp::list(Bar, Baz));
is nqp::istype($b, Baz), 1, 'an istype site resolved before settypecache sees the new cache';
```

Run: `cd $ROOT && RAKUDO_RAKUAST=1 ./rakudo-j -Ilib t/02-rakudo/type-state.t`
Expected: test 2 `not ok` (the recorded program still invokes Mu's gist);
test 4 `ok` (Task 3). Also `cd $ROOT/nqp && ./nqp-j-gradle t/jvm/19-type-state.t`:
test 2 `not ok`. If test 2 passes in either, Rakudo's augment did not
republish or the loop never recorded; check with `NQP_DISPATCH_STATS=1`
that `misses=` grows by at least one across the augment before deciding
the test is wrong.

- [ ] **Step 2: `Guard.OfType` carries the state it was recorded against**

`DispatchModel.kt:226-229`:

```kotlin
    /** The value has exactly this type, with the facts the program was recorded against. */
    data class OfType(override val on: ValueSource, val type: STable?) : Guard {
        /**
         * The type's state when the guard was made -- at recording, or at
         * restore from a persisted slot. The program's constants (its literal
         * method, attribute slots, unbox kinds) came from those facts, so a
         * republished type must miss on every road. Transient: outside the
         * data-class equality (constructor parameters only), outside
         * DispatchDump, never persisted.
         */
        @JvmField val state: TypeState? = type?.state
        /** False once the type republished: the guard can never match again. */
        val isFresh: Boolean
            get() = type == null || type.state === state
        override fun check(ctx: DispatchContext) =
            (on.evaluateRaw(ctx) as? SixModelObject)?.st?.state === state
    }
```

Add `import org.raku.nqp.sixmodel.TypeState`. In `DispatchProgram`
(:411-446) add:

```kotlin
    /** False once a type this program guards on has republished. */
    val isFresh: Boolean
        get() {
            for (g in guards) if (g is Guard.OfType && !g.isFresh) return false
            return true
        }
```

- [ ] **Step 3: The MethodHandle chain tests state identity**

`DispatchCompiler.kt`:
- `:63`: `private val TEST_TYPE_ARG = test("testTypeArg", Integer.TYPE, TypeState::class.java)`
- `:149`: `return MethodHandles.insertArguments(TEST_TYPE_ARG, 0, index, guard.state)`
- `:267-269`:

```kotlin
    @JvmStatic
    fun testTypeArg(index: Int, state: TypeState?, tc: ThreadContext, args: Array<Any?>): Boolean =
        (args[index] as? SixModelObject)?.st?.state === state
```

- `:286-289` (`testGuard`): `is Guard.OfType -> (evalRaw(guard.on, tc, args) as? SixModelObject)?.st?.state === guard.state`.

Add `import org.raku.nqp.sixmodel.TypeState`; the `STable` import stays if
anything else uses it, else remove it.

- [ ] **Step 4: The runtime site evicts stale programs at install**

`DispatchBootstrap.kt` `install` (:115-126):

```kotlin
    fun install(program: DispatchProgram) {
        /* A program whose type guard's state was republished can never match
         * again: drop it, so a republish does not spend the site's program
         * budget (MAX_PROGRAMS) on dead entries. */
        var current = programs
        if (current.any { !it.isFresh })
            current = current.filter { it.isFresh }.toTypedArray()
        if (current.size < Dispatch.MAX_PROGRAMS) {
            programs = current + program
            /* A hot site stays compiled as its cache grows; a cold one waits
             * for the dispatch entry to see it cross the threshold. */
            if (chain != null || heat >= DispatchCompiler.threshold)
                recompile()
        }
    }
```

- [ ] **Step 5: The engine: folded programs carry their assumptions**

`NqpDispatch.kt` `Program` (:273-279): add the field

```kotlin
        /**
         * The assumptions of every type state this program's constants came
         * from (its type and identity guards, hence its literal method, its
         * attribute getters and unbox sources). Tested first in replay; a
         * constant of the compiled code, so they fold to nothing.
         */
        @JvmField @field:CompilationFinal(dimensions = 1) val assumptions: Array<Assumption>
```

and in `init`, as its LAST statement (after the outcome sources are folded, so every state the folder saw is in):
`assumptions = f.assumptions()`.

`Folder` (:396-424): add `private val states = LinkedHashSet<TypeState>()` beside
`known`, and

```kotlin
        /** The assumptions of the states the folded constants were read from, in guard order. */
        fun assumptions(): Array<Assumption> = states.map { it.assumption }.toTypedArray()
```

In `fold(g: Guard)`: `is Guard.OfType -> { val t = g.type; if (t != null) { known[g.on] = t;
g.state?.let { states.add(it) } }; return TypeChk(on, t) }` and in the `Guard.Literal` OBJ branch,
after `known[g.on] = st`: `states.add(st.state)`. (`TypeChk` keeps its STable compare: the
assumption is what makes the compare sufficient.) Import `org.raku.nqp.sixmodel.TypeState`.

`matches` (:664-670):

```kotlin
    @ExplodeLoop
    private fun matches(p: Program, tc: ThreadContext, args: Array<Any?>): Boolean {
        val assumptions = p.assumptions
        for (i in assumptions.indices)
            if (!assumptions[i].isValid) return false
        val guards = p.guards
        for (i in guards.indices)
            if (!guards[i].test(tc, args)) return false
        return true
    }
```

`Cache` (:485-540): add

```kotlin
        /** A folded program whose type state republished: it can never match again. */
        fun hasStale(): Boolean {
            for (p in programs) for (a in p.assumptions) if (!a.isValid) return true
            return false
        }
```

`miss` (:655-660): the refold condition becomes
`if (cache.programs.isEmpty() || cache.hasStale() || ++cache.missesSinceFold >= REFOLD_AFTER)
cache.refresh(tc)`, and the `REFOLD_AFTER` comment gains one sentence: "A stale program (its
type republished) refolds at once and does not count: the runtime site has already evicted it at
the install that followed the miss."

The stats line (:592): append `" publishes=" + org.raku.nqp.sixmodel.STable.PUBLISHES.sum()`
after `" recorded=" + DispatchPersist.recorded`.

- [ ] **Step 6: The rig parses `publishes=`**

`tools/build/m7-rig.raku` `parse-cold` (:55-75): after the `recorded` line
add `%r<publishes> = +$0 if $text ~~ / ' publishes=' (\d+) /;` and append
`publishes={%r<publishes> // '-'}` to the summary string at :73.

- [ ] **Step 7: Rebuild both jars, run the two tests and the smoke markers**

Run: `cd $ROOT && ./nqp/gradlew -p nqp :nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars --console=plain 2>&1 | grep -E 'error|FAILED|BUILD' | head`
Expected: `BUILD SUCCESSFUL` (the `DispatchSlotCodecTest` and
`DispatchPersistTest` still pass: the state is outside equality and the dump).

Then:
- `cd $ROOT/nqp && ./nqp-j-gradle t/jvm/19-type-state.t` — 4/4.
- `cd $ROOT && RAKUDO_RAKUAST=1 ./rakudo-j -Ilib t/02-rakudo/type-state.t` — 4/4.
- `cd $ROOT && NQP_DISPATCH_STATS=1 RAKUDO_RAKUAST=1 ./rakudo-j -e '' 2>&1 | grep -o 'publishes=[0-9]*'` — a positive number (the marker for Task 5's row).
- `cd $ROOT && NQP_DISPATCH_PERSIST=verify NQP_DISPATCH_STATS=1 RAKUDO_RAKUAST=1 ./rakudo-j -Ilib t/02-rakudo/type-state.t 2>&1 | grep -E 'mismatched=|dispatch-verify'` — `mismatched=0` (a restored program's transient state does not change its text).

- [ ] **Step 8: Commit (both trees)**

```bash
STAMP="$(date +%F)T21:20:00+02:00"
cd $ROOT/nqp && git add src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchModel.kt \
  src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchCompiler.kt \
  src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchBootstrap.kt \
  nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt t/jvm/19-type-state.t
cd $ROOT/nqp && GIT_AUTHOR_DATE=$STAMP GIT_COMMITTER_DATE=$STAMP git commit -F - <<'MSG'
Dispatch: a type guard is a state guard, on all three roads (milestone 8, A2)

Guard.OfType captures the type's TypeState when it is made (recording or
restore) and checks state identity, which subsumes type identity because
states are never shared: the interpreted check, the MethodHandle chain and
the engine's folded replay all miss once the type republishes, so the
method literal, attribute getters and unbox sources a program folded from
the type's facts are never used past them. The engine's folded Program
carries the assumptions of every state it read (tested first, folded to
nothing compiled); a stale program refolds at once without counting toward
REFOLD_AFTER, and the runtime site evicts it at the next install. The
stats line prints publishes=.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
cd $ROOT && git add t/02-rakudo/type-state.t tools/build/m7-rig.raku
cd $ROOT && GIT_AUTHOR_DATE=$STAMP GIT_COMMITTER_DATE=$STAMP git commit -F - <<'MSG'
Tests: an augment reaches a resolved method-call site; the rig reads publishes= (milestone 8, A2)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
```

---

### Task 5: gate, the storm baseline, rig row `a`, the record

**Files:**
- Modify: the ledger; `docs/jvm-perf-findings-2026-09.md` (new section "Milestone 8, Phase A"); `docs/jvm-jesp.md:146-152` (istype's contract) and `:801-812` (the object-model paragraph); `docs/jvm-truffle-only-plan.md` (one paragraph after the milestone-7 close note)
- Modify: the memory file `milestone-8-stable-assumption.md` and its `MEMORY.md` line (outside the repo)

**Interfaces:**
- Consumes: everything above; `tools/build/m7-rig.raku --tag=... --warm=proxy`.
- Produces: rig row `a`; the storm baseline number; the docs.

- [ ] **Step 1: `make`, then the gate with wall times**

```bash
cd $ROOT && RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/m8-a2-make.log \
    --show='Compiling' --show='Training' --stall=1800 -- make
cd $ROOT && RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/m8-a2-nqp-suite.log \
    --show='files=' --show='red=' --stall=7200 --max=10800 -- \
    raku tools/build/evalserver-sweep.raku --suite=nqp '--chunk=*' --jobs=1
cd $ROOT && RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/m8-a2-sanity.log \
    --show='Result' --show='Files=' --stall=1800 -- perl t/harness5 --jvm --evalserver t/01-sanity
```

Expected: `make` exit 0 with one training line and no `Compiling`; nqp
suite 155/155; `t/01-sanity` 25/25. All three wall times into the ledger.
Also run `t/02-rakudo/type-state.t` and `closure-static-clone.t` through
`./rakudo-j -Ilib` and record both (the second is the inherited red: its
state, not a gate).

- [ ] **Step 2: The storm baseline**

Probe the option first: `cd $ROOT && RAKUDO_JVM_XOPTS='-Dpolyglot.engine.TraceAssumptions=true' RAKUDO_RAKUAST=1 ./rakudo-j -Ilib t/02-rakudo/type-state.t 2>&1 | grep -ci 'assumption'`.
Expected: at least 1 (the augment invalidates an assumption compiled code
depended on, or the interpreter's). If the count is 0, the option name is
wrong for this Truffle: probe `org.raku.nqp.truffle.NqpCheck` with the
option (global constraint: options are probed through NqpCheck), try
`-Dpolyglot.engine.TraceDeoptimizeFrame=true` as the fallback marker, and
record which one produced output. Do not proceed on a silent instrument.

Then the number: `cd $ROOT && RAKUDO_JVM_XOPTS='-Dpolyglot.engine.TraceAssumptions=true' NQP_DISPATCH_STATS=1 RAKUDO_RAKUAST=1 ./rakudo-j -e '' 2>&1 | tee $CLAUDE_JOB_DIR/tmp/m8-trace.log | grep -ci 'assumption'`
and `grep -o 'publishes=[0-9]*' $CLAUDE_JOB_DIR/tmp/m8-trace.log`. Record
both in the ledger as **the storm baseline**: `publishes=` is every
publish; the trace count is the publishes that invalidated compiled code.
The spec's reading: a trace count in the tens is no storm; in the
thousands, the per-facet split (approach B) is designed as A2' before
Phase B. Either way the number is recorded, not acted on, in this task.

- [ ] **Step 3: Rig row `a`**

`cd $ROOT && RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/m8-rig-a.log --show='m7-rig' --stall=3600 -- raku tools/build/m7-rig.raku --tag=m8a --warm=proxy`

Expected marker `m7-rig: DONE`. Record the row (cold rakudo-e, cold nqp-e,
misses, hits, restored, recorded, publishes, warm proxy, rig wall) in the
ledger next to milestone 7's close row. Read it honestly: the series'
spread is 2.50-2.64 s on the old baseline and about ±0.05 s around 2.25 s
now; a delta inside it claims nothing. A cold row slower by more than the
spread is risk 2 of the spec (the dependent load) and is reported as such.

- [ ] **Step 4: The record**

- `docs/jvm-perf-findings-2026-09.md`: a new section "Milestone 8, Phase A
  (2026-MM-DD)" after "Milestone 7: the close": what landed (one paragraph
  from the two commit messages), the gate table with wall times, row `a`
  against the close row, the storm baseline (both numbers), the rulings
  1-8 with their cost-if-wrong, and the deferred minors.
- `docs/jvm-jesp.md:146-152`: istype's contract now reads "cached only
  when the type-check cache answered definitively, under both operands'
  type-state assumptions; a republish re-resolves without a miss".
  `:801-812`: replace "the per-STable `Assumption` is still only an idea"
  with a sentence pointing at `TypeState` and the milestone-8 spec.
- `docs/jvm-truffle-only-plan.md`: after the milestone-7 close paragraph,
  one paragraph: "Milestone 8, Phase A landed <date> (rakudo `…` / nqp
  `…`): the type state …; row `a` …; Phase B (the promotion campaign) next."
- Memory: update `milestone-8-stable-assumption.md` (status: Phase A
  closed, hashes, row `a`, storm baseline, NEXT = Phase B plan) and its
  `MEMORY.md` line.

- [ ] **Step 5: Commit, rebase, push**

```bash
STAMP="$(date +%F)T21:40:00+02:00"
cd $ROOT && git add docs/jvm-perf-findings-2026-09.md docs/jvm-jesp.md docs/jvm-truffle-only-plan.md \
  docs/superpowers/plans/2026-09-16-jvm-milestone-8-type-state-phase-a.ledger.md
cd $ROOT && GIT_AUTHOR_DATE=$STAMP GIT_COMMITTER_DATE=$STAMP git commit -F - <<'MSG'
Docs: milestone 8 Phase A closed -- the type state, measured

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
```

Then the handoff rebase (user rule): `cd $ROOT && git fetch origin && git rebase origin/main`
and `cd $ROOT/nqp && git fetch upstream && git rebase upstream/main` (set the nine stage0
jars aside with `git stash push -u -m m8-stage0-<date>` ONLY if the rebase refuses to run over
them, restore with `git stash apply <sha>` and verify their md5sums against the pre-rebase
list; never `stash pop`). A conflict is aborted and recorded, not guessed at. Then
`cd $ROOT && git push --force-with-lease ab5tract worktree-jesp-direct-lazy-records` and
`cd $ROOT/nqp && git push --force-with-lease ab5tract jesp-direct-lazy-records`. Record the
before/after hashes of both trees in the ledger and the memory file.

Remind the user to leave the session rather than `/clear` (user request 2026-09-08).

---

## Self-review (done while writing; the executor re-checks)

**Spec coverage.** Section 1 (the state, publish ordering, initial state,
identity subsumption): Task 1 Steps 4-5. Section 2 (writers, KnowHOW copy
+ `composedType`, specs built complete, configurer API, REPR data
republish via `composetype`, the reader builds once, the counter): Task 1
Steps 6-11, Task 4 Step 5 (the stats line). Section 3 (sites capture
state, `create` drops its re-read, istype checked on both operands, Mu's
sink, `Guard.OfType` transient state, three roads, `Program.assumptions`,
stale eviction and uncounted refold, persisted slots, the two tests):
Tasks 3-4. Section 5 (A1/A2 split, runtime-jar rebuilds, `make` without a
setting recompile, gates with wall times, row `a`, storm baseline): Tasks
2 and 5. Spec deviation recorded as ruling 1 (the reader's publish point).
Not in this plan by design: Phase B (its own plan after row `a`), the
whole-`t/` run (milestone close).

**Placeholders.** None: every code step has its code; the only "find"
instructions point at a named call (`REPR.compose` at the end of KnowHOW
`compose`) or a named grep whose outcome is specified both ways.

**Type consistency.** `TypeState.withFacts` named parameters
(`methodCache`, `vTable`, `typeCheckCache`, `modeFlags`, `containerSpec`,
`invocationSpec`, `boolificationSpec`, `hllOwner`, `hllRole`, `name`) are
the names used by every writer in Task 1 and by the sed in Task 2
(`.state.methodCache` etc.). `Site.state`/`valid()`/`clear()`/
`republished()` are used consistently across Task 3's sites.
`Guard.OfType.state` / `isFresh` (Task 4 Step 2) are what Steps 3-5 read.
`STable.PUBLISHES` (Task 1) is what Task 4's stats line and the rig read.
`BoolificationSpec(Mode, Method)` and `InvocationSpec(ClassHandle,
AttrName, Hint, InvocationHandler)` keep their field names, so the
readers the sed does not touch (`bs.Mode`, `invSpec.ClassHandle`) compile.
