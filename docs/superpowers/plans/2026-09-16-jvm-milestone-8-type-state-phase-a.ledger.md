# SDD ledger — plan: docs/superpowers/plans/2026-09-16-jvm-milestone-8-type-state-phase-a.md

Spec: docs/superpowers/specs/2026-09-16-jvm-milestone-8-type-state-design.md
(rakudo 22e2cc2e75), sections 1-3 and 5.

BASE before Task 1: rakudo 352c927b66, nqp 8ea35ba95 (the nine v2 stage0
jars are an uncommitted working-tree change in nqp/, user rule). Baseline = milestone
7's close row: cold rakudo-e 2.247 s, cold nqp-e 1.198 s, misses 4931, hits 35512,
recorded= 195, warm t/01-sanity 59 s.

Claude-Session trailer: not known.

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

## Task 1 (nqp tree) — DONE

Commit: nqp `d4fba0e51` "Object model: the type state -- an immutable TypeState
with an Assumption per STable (milestone 8, A1)", stamped 2026-09-16T20:30:00+02:00.
15 files, +352/-186. The nine stage0 jars were left unstaged (user rule).

Gates, with wall times:
- `:nqp-runtime:compileKotlin` + `:nqp-truffle:compileKotlin` — BUILD SUCCESSFUL, 3 s,
  zero errors. **No writer the plan missed**: the compiler named none beyond the
  fifteen files listed, so the plan's writer audit was complete.
- `:nqp-runtime:test` (whole runtime suite, `--rerun`) — BUILD SUCCESSFUL, 1 s wall
  (0.2 s of test time), 10 classes / 56 tests / 0 failures / 0 skipped, TypeStateTest
  6/6. (Milestone 7's "36 s" was a cold-daemon figure; a warm daemon runs it in ~1 s.)
- `:nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars` — BUILD SUCCESSFUL, 3 s.
- Smoke on `./nqp-j-gradle`: `-e 'say(1)'` → `1`; `t/jvm/17-object-layout.t` 50/50;
  `t/jvm/18-rebless-layout.t` 14/14. Extra MOP smoke (the compose copy-vs-alias
  change): t/nqp/025-class 12/12, 026-methodops 5/5, 028-subclass 9/9, 053-knowhow
  12/12, 056-role 18/18, 057-construction 2/2, 058-attrs 35/35.

Deviations from the Task 1 brief:
1. **Step 3 `testRuntimeOnly` → `testImplementation`.** TypeStateTest reads
   `state.assumption.isValid`, so `com.oracle.truffle.api.Assumption` has to be on the
   test COMPILE path, not only the test runtime path; with `testRuntimeOnly` the test
   compile failed with "Cannot access class 'com.oracle.truffle.api.Assumption'".
   Test configurations are not bundled into nqp-runtime.jar, so the main-path
   isolation the comment above it describes is unchanged.
2. **`TypeStateTest.theWriterOpsPublish` operates on a fresh type object**
   (`tc.gc.BOOTHash!!.st.REPR.type_object_for(tc, tc.gc.BOOTHash!!.st.HOW)`) rather
   than on `tc.gc.BOOTHash` itself — the controller's pre-flight ruling. Every
   assertion is otherwise as written.
3. **Commit trailer names the executing model** (`Claude Opus 5 (1M context)`), not
   the brief's literal `Claude Fable 5.1`: this task ran on Opus per the model policy.

## Task 2 (both trees) — DONE

Base: nqp `c1b73c43b` (Task 1, amended — the "d4fba0e51" above is the pre-amend
hash), rakudo `352c927b66`.

The sed of the brief's Step 1 renamed 14 files (RakudoContainerSpec.kt matched
only on its `import`, so the `/^import /!` guard left it unchanged and it
carries no diff). Hand fixes after the sed: four safe-call chains where the
receiver was already nullable — `?.st?.ContainerSpec`-shaped reads became
`?.st?.state.hllOwner`, which does not compile; they are now
`?.st?.state?.hllOwner` (BootDispatchers.kt:294, DispatchCompiler.kt:300,
DispatchModel.kt:255 and :267). No `.state.state.` was produced anywhere, and
no type reference changed. One doc comment in NqpTypeOps.kt was rewritten by
the sed from `STable.TypeCheckCache` to `STable.state.typeCheckCache`, which is
what it now describes. `Ops.setcontspec`'s deliberate double read of `st.state`
was left alone. No `.java` file in either runtime tree read an old name.

The nine `val … get() = state.…` views and their TRANSITIONAL comment are gone
from STable.kt, which now ends at `republish()`.

Gates, with wall times:
- `:nqp-runtime:compileKotlin` + `:nqp-truffle:compileKotlin` — BUILD SUCCESSFUL,
  3 s, **zero errors**: the sed plus the four hand fixes found every reader.
- `:nqp-runtime:test` — BUILD SUCCESSFUL, 7 s wall on a forced rerun
  (0.54 s of test time), 56 tests / 0 failures / 0 skipped.
- `:nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars` — BUILD SUCCESSFUL, ~3 s.
- Smoke `./nqp-j-gradle -e 'say(1)'` → `1`.
- **`make` — exit 0, 855 s (14 m 15 s).** Markers: eight `Compiling` lines for
  the frontend, then `Generating rakudo-runtime.jar (Gradle)` at 116 s,
  `Compiling rakudo.jar`, v6c + CORE.c (294 s on its own), v6d + CORE.d,
  v6e + CORE.e, and `+++ Training dispatch slots` at 853 s.
- **nqp suite — 155 files, 1 chunk, exit 0, 197 s**, `chunk 1/1: ok` (no reds),
  one server x 6g heap + 3g off-heap.
- **`t/01-sanity` — Result: PASS, Files=25, Tests=303, 54 s.**

### Deviation: the settings DID recompile, and ruling 8 is wrong as written

Ruling 8 and the Task 2 brief expected "no `Compiling` marker" — only
`rakudo-runtime.jar` and the training stamp. A full frontend + BOOTSTRAP +
CORE.c/d/e recompile ran instead. Two independent causes, both pre-existing
Makefile facts and neither a defect of this change:

1. **`RUNTIME_JAR` is a hard prerequisite of `rakudo.jar`.** Makefile:320 reads
   `J_RAKUDO_DEPS_EXTRA = $(RUNTIME_JAR) | $(NQP_RUNTIME_JAR)`. The comment
   above it (316-319) explains that *nqp's* runtime jar sits after the `|` so
   its rebuild cannot timestamp-cascade into a setting recompile — but
   *Rakudo's own* `rakudo-runtime.jar` sits before it, as an ordinary
   prerequisite. Phase A touches three files under `src/vm/jvm/runtime/`
   (RakudoContainerConfigurer.kt, RakudoJavaInterop.kt, RakOps.kt), so
   `rakudo-runtime.jar` rebuilds and `rakudo.jar`, the three BOOTSTRAPs and the
   three settings follow by design. Any Rakudo-side runtime edit in this
   milestone costs a full setting recompile; budget for it.
2. **`gen/jvm/main-version.nqp` was re-expanded first** (the make log's very
   first line, at t=0), because rakudo HEAD moved since the last build in this
   worktree. Every frontend jar depends on `$(J_NQP_VERSION_FILE)`
   (Makefile:1293, 1301, 1305), so ModuleLoader/Ops/Actions/Grammar/Metamodel/
   Optimizer/Compiler were already stale before `rakudo-runtime.jar` was even
   generated at 116 s.

The same argument as the nqp side applies — compiled bytecode does not depend
on the runtime that executes it — so moving `$(RUNTIME_JAR)` after the `|` on
line 320 would make ruling 8 true. That is a Makefile change outside Task 2's
scope and is NOT made here; it is recorded as a candidate for the milestone.

### Other deviations

1. **`git status --short` in the rakudo root does not merely warn.** The
   `3rdparty/nqp-configure` submodule gitlink makes it `fatal: not a git
   repository` with **exit 128 and no listing at all**; `2>/dev/null` hides the
   message but not the missing output. `git status --short --ignore-submodules=all`
   works. Used throughout; the brief's Step 6 `git status --short` is run that way.
2. **The brief's `for f in $FILES` loop is a no-op under zsh**, which does not
   word-split an unquoted parameter: the whole newline-joined list went to sed
   as one filename and nothing was edited (verified: both trees clean afterwards).
   Re-run as `… | while IFS= read -r f; do …; done`, same sed script verbatim.
3. **`t/01-sanity` was killed once at file 19/25 by the agent harness's
   low-memory guard** (not by the eval server, not by a test failure, and not
   the systemd MemoryMax cage of 2026-09-16 — 22 GiB was available). Three
   Gradle/Kotlin daemons held ~3 GiB; `./nqp/gradlew -p nqp --stop` freed them
   and the re-run passed 25/25 in 54 s. The recorded time is the clean run's.
4. **Commit trailer.** Both commits carry the brief's literal
   `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` (the directing
   session), per this task's instructions — unlike Task 1, which substituted the
   executing model's name.
