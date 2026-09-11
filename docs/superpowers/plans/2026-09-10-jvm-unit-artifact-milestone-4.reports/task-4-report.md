# Task 4 report: stage0 regenerated as artifacts; stage compiles enter through UnitMain

## Status: DONE

## Gradle edit (Step 1)

`nqp/build.gradle.kts`, in `registerStage` (`JavaExec` block, ~line 227-256):

- `mainClass = "nqp"` → `mainClass = "org.raku.nqp.runtime.unit.UnitMain"`.
- `classpath` unchanged (`files(compilerDir, engineJarFile)`).
- `doFirst`'s boot classpath dropped its trailing `"${compilerDir.absolutePath}/nqp.jar"` entry
  (the compiler unit is no longer a class-road jar the boot loader needs to see;
  it is the first program argument instead).
- New `val compilerUnit = listOf("${compilerDir.absolutePath}/nqp.jar")`, prepended to both
  branches of `args` (the `t.isNqp` branch and the general branch) ahead of `--bootstrap`.

This is structurally similar to `GenerateRunnerTask.kt`'s `nqp-j-gradle` runner shape
(`CP="$lib:$engineJar"`, `UnitMain "$lib/nqp.jar" "$@"`) — compilerDir on `-cp` for the module
search path, the compiled unit's own jar as `UnitMain`'s first argument — minus the trailing
`nqp.jar` the runner still appends to its *boot* classpath (`bootEntries`), which the stage
compile's `doFirst` block does not.

Diff verified in the commit; matches the brief's Step 1 code verbatim.

## Build A — old (class-road) stage0 through UnitMain (Step 2)

Command: `RAKUDO_RAKUAST=1 NQP_CODE_STRICT=1 raku tools/build/watched-run.raku --log=.../t4-build-a.log ... -- ./nqp/gradlew -p nqp clean buildJvm`

Result: **EXIT=0, elapsed=206s (3m26s)**. Proves the UnitMain entry point correctly loads and
runs the OLD class-road `nqp.jar` (via `-cp` module-path resolution) to bootstrap stage1 and
stage2. No `Could not find` / `loadbytecode` failures — the classpath-derived module search path
worked on the first try, so ruling 2's fallback comparison against `nqp-j-gradle`'s `CP` was not
needed.

## Regeneration (Step 3)

`raku tools/build/watched-run.raku --log=.../t4-bootstrap.log -- ./nqp/gradlew -p nqp jBootstrapFiles`
→ EXIT=0, elapsed=0s (pure `Copy` task, stage2 outputs already built by Build A).

`git rm src/vm/jvm/stage0/JASTNodes.jar` (from the nqp tree) — the ninth pre-existing stage0 jar
that `jBootstrapFiles` no longer produces (task no longer emits a JASTNodes module).

### stage0 census — before regeneration (10 jars, one stale)

```
JASTNodes.jar        28058  (removed this task; class-road leftover)
ModuleLoader.jar      12001
NQPCORE.setting.jar   63982
NQPHLL.jar           135367
nqp.jar              226582
nqpmo.jar             53417
NQPP6QRegex.jar      116486
QAST.jar             438088
QASTNode.jar          51487
QRegex.jar            79011
```

### stage0 census — after regeneration (9 jars, all unit artifacts)

```
ModuleLoader.jar       5404
NQPCORE.setting.jar   33022
NQPHLL.jar            81673
nqp.jar              139798
nqpmo.jar             28861
NQPP6QRegex.jar       72054
QAST.jar             120330
QASTNode.jar          32506
QRegex.jar            43413
```

`raku tools/build/jar-census.raku nqp/src/vm/jvm/stage0/*.jar`:

```
ARTIFACT meta=1 class=0  ModuleLoader.jar
ARTIFACT meta=1 class=0  NQPCORE.setting.jar
ARTIFACT meta=1 class=0  NQPHLL.jar
ARTIFACT meta=1 class=0  nqp.jar
ARTIFACT meta=1 class=0  nqpmo.jar
ARTIFACT meta=1 class=0  NQPP6QRegex.jar
ARTIFACT meta=1 class=0  QAST.jar
ARTIFACT meta=1 class=0  QASTNode.jar
ARTIFACT meta=1 class=0  QRegex.jar
CENSUS: all 9 jars are unit artifacts
```

All nine are `unit.meta`-only, zero `.class`, zero `.codeprograms.lz4`, and roughly a third the
size of the class-road jars they replace (e.g. `nqp.jar` 226,582 → 139,798 bytes; `QAST.jar`
438,088 → 120,330 bytes).

## Build B — new (unit-artifact) stage0 (Step 4)

Same clean-build command, log `t4-build-b.log`.

Result: **EXIT=0, elapsed=263s (4m23s)** — the first "stage0-as-artifact" build time. Stage1 is
now compiled entirely by a JAST-free, unit-artifact compiler bootstrapping from unit-artifact
stage0 jars.

(Build A → Build B: +57s. Not investigated further — Task 4's scope is correctness/regeneration,
not perf; the delta is plausibly explained by the different stage2-output jar shapes/sizes
feeding stage1 compilation, not by anything in the UnitMain change itself, since Build A already
used UnitMain end to end.)

## Sweep (Step 5)

`RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=nqp/t/nqp -t=nqp/t/qast --jobs=3 ... -- nqp/nqp-j-gradle`

Result: **117 of 120 ok in 353s**. Three failures, all pre-existing/expected:

- `nqp/t/nqp/019-file-ops.t` — `EXIT=1`, `NoSuchFileException: t/nqp/019-setinputlinesep.txt`.
  Relative-path test; watched-run's `-t=nqp/t/nqp` sweep runs with cwd = rakudo worktree root,
  not `nqp/`. Verified independently: `cd nqp && ./nqp-j-gradle t/nqp/019-file-ops.t` → all 112
  subtests ok. This is the documented "019/063 from the nqp dir" caveat, not a regression.
- `nqp/t/nqp/063-slurp.t` — same cwd cause. Verified: `cd nqp && ./nqp-j-gradle t/nqp/063-slurp.t`
  → `1..1 / ok 1 - File slurped`.
- `nqp/t/qast/01-qast.t` — `EXIT=1`, known moar-only red (expected 1/2 on t/qast).

So against the documented baseline: t/nqp effectively 118/118 (accounting for the cwd caveat on
019/063), t/qast 1/2 exactly as expected. No new failures introduced by the UnitMain switch or
the stage0 regeneration.

## Docs edit (Step 6)

`nqp/docs/gradle-jvm-build.md`:

- "How the bootstrap is modeled" paragraph rewritten to name
  `org.raku.nqp.runtime.unit.UnitMain <stageDir>/nqp.jar --bootstrap ...` as the stage-compile
  entry point and to describe the committed `src/vm/jvm/stage0` jars as unit artifacts, not class
  files.
- Added a bullet under "Modernization (2026-08)"'s regeneration note: "stage0 regenerated 2026-09
  as unit artifacts (`./gradlew jBootstrapFiles` after the JAST-free driver landed). Rule: a
  change that an OLD stage0 could not read (an incompatible wire change, a meta format bump, a
  syscall shape change) is preceded by a regeneration from the LAST compiler that still speaks the
  old shape; additive wire changes need none."

## Files changed (all in nqp/, commit `08000b41a`)

- `build.gradle.kts` — Step 1 edit.
- `docs/gradle-jvm-build.md` — Step 6 edit.
- `src/vm/jvm/stage0/JASTNodes.jar` — deleted.
- `src/vm/jvm/stage0/{ModuleLoader,NQPCORE.setting,NQPHLL,nqp,nqpmo,NQPP6QRegex,QAST,QASTNode,QRegex}.jar`
  — regenerated as unit artifacts.

## Self-review findings

- Verified the applied `build.gradle.kts` diff against the brief's Step 1 code block: identical
  except for the diff context (matches verbatim, including the explanatory comment).
- Verified `jBootstrapFiles`'s existing filter `it.jar != "NQPP5QRegex.jar"` was left untouched
  per the brief (unchanged code, just run) — it is a no-op today since `NQPP5QRegex` is not in
  `stageTargets` (it's cat-only, compiled afterward by the finished runner), consistent with the
  pre-existing stage0 layout (no `NQPP5QRegex.jar` in stage0 before or after this task).
  `stageTargets` has exactly 9 entries, matching the census.
  `nqp-runtime.jar`/engine jars are untouched by this task.
- Confirmed `git status` in nqp/ was clean before starting (only the Step 1 `build.gradle.kts`
  edit pending) and clean after the commit.
- Spot-checked that the two cwd-caused sweep failures are not silent regressions by re-running
  both test files directly with cwd inside `nqp/`; both pass in full.
- Did not modify anything under `src/vm/jvm/HLL/Backend.nqp`, `JASTCompiler`, or any JAST-related
  source — this task only touches the Gradle stage-compile driver, stage0 binaries, and docs, as
  scoped.

## Concerns

- Build B is 57s slower than Build A (263s vs 206s). Both are clean builds of the same stage
  graph through the same UnitMain entry point, so this is not a UnitMain-vs-`nqp`-mainclass
  effect — it's most likely attributable to the unit-artifact stage0 jars themselves (different
  I/O/parse shape than the class-road jars they replaced) feeding stage1's compile. Flagged here
  since the controller ruling asked both times to be recorded; no action taken since Task 4's
  scope is correctness, and "runtime perf over compile time" per project memory deprioritizes a
  compile-time regression unless it were much larger.
- The sweep's two cwd-relative-path failures (019, 063) are pre-existing test-harness behavior
  (not introduced by this task) but will keep showing as red in any `-t=nqp/t/nqp` sweep run with
  cwd outside `nqp/`. Worth a follow-up (either fixing the tests to resolve paths relative to
  `$*PROGRAM` / `%*ENV<TEST_DIR>`, or teaching watched-run to cd into `nqp/` for `-t=nqp/t/...`
  targets) but out of scope here per the brief.

## Build/test logs

- `/home/longwalker/.claude/jobs/25fa1a35/tmp/t4-build-a.log` (+ `.markers`)
- `/home/longwalker/.claude/jobs/25fa1a35/tmp/t4-bootstrap.log`
- `/home/longwalker/.claude/jobs/25fa1a35/tmp/t4-build-b.log` (+ `.markers`)
- `/home/longwalker/.claude/jobs/25fa1a35/tmp/t4-sweep.markers`, per-file logs under
  `/home/longwalker/.claude/jobs/25fa1a35/tmp/t4-sweep-logs/`

## Fix round 1 (review: docs, ONE Important finding)

**Finding addressed (Important, `nqp/docs/gradle-jvm-build.md:117-119`):** the pre-existing
"Modernization (2026-08)" bullet still asserted "the committed bootstrap jars are now Java 25
class files" — false as of this task's regeneration (stage0 is now zero `.class`, `unit.meta`-only)
and directly contradicted the newly-added bullet immediately below it.

**Fix:** rewrote the 2026-08 bullet to record the class-file regeneration as history, explicitly
superseded by the 2026-09 unit-artifact regeneration, keeping the JDK 25+ toolchain floor (still
true — the *build* toolchain is JDK 25 regardless of what stage0 contains) while dropping the
now-false "class files" claim:

> **stage0 regenerated (2026-08)** as Java 25 class files (`./gradlew jBootstrapFiles`), which set
> the JDK 25+ floor for building or running the JVM backend; superseded 2026-09 by the
> unit-artifact regeneration below — the JDK 25+ floor stands, but stage0 is no longer class
> files.

**Also fixed while in that paragraph (reviewer minor):** "How the bootstrap is modeled" described
the `JavaExec`'s classpath as `-cp <stageDir>` only; corrected to `-cp <stageDir>:<engine jar>` to
match the actual `classpath = files(compilerDir, engineJarFile)` in `build.gradle.kts`.

**Report wording fixed (reviewer minor, no code change):** softened the Step 1 write-up's claim
that the edit "mirrors" `GenerateRunnerTask.kt`'s classpath shape — the runner still appends
`nqp.jar` onto its *boot* classpath (`bootEntries`), which the stage-compile `doFirst` block does
not. Reworded to "structurally similar ... minus the trailing `nqp.jar`" (see the Gradle-edit
section above, now updated in place).

**Files changed:** `nqp/docs/gradle-jvm-build.md` only. No `build.gradle.kts` or jar changes —
docs-only fix, amended into the existing Task 4 commit (forward only, per instruction).

**Testing:** N/A — docs-only change, no build or test run required or performed.

**Commit:** amended `nqp 08000b41a` → `nqp 9844a0de9` (same message; `git commit --amend --no-edit`
after staging the doc fix). `git log`/`git status` confirmed clean, single commit, no stray
changes.
