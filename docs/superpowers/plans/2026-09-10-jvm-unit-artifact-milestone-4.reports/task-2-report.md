# Task 2 report: The JASTNodes module, the stage lists, nqp's own JAST closures

## Status: DONE

## What was implemented

Followed the brief's Steps 1-7, taking the "if nothing but comments remains"
branch of Step 3 per the controller's ruling 1 (Task 1 had already stripped
`nqp/src/vm/jvm/NQP/Ops.nqp` down to a 9-line comment).

1. **Step 1 (grep)** — ran the exact grep from the brief. See "Step 1 hits"
   below.
2. **Step 2 (delete module + build entries)**:
   - `git rm nqp/src/vm/jvm/QAST/JASTNodes.nqp` (715 lines).
   - `nqp/build.gradle.kts`: removed `"JASTNodes" to NqpSources.JASTNODES,`
     from the `genCatParityCheck` `lists` map; removed the
     `StageTarget("JastNodes", ...)` entry; changed `Hll`'s
     `deps = listOf("Qregex", "JastNodes")` to `deps = listOf("Qregex")`;
     changed `Qast`'s `deps = listOf("Hll", "JastNodes", "Qregex", "QastNode")`
     to `deps = listOf("Hll", "Qregex", "QastNode")`.
   - `nqp/buildSrc/src/main/kotlin/NqpSources.kt`: deleted
     `val JASTNODES = listOf("src/vm/jvm/QAST/JASTNodes.nqp")`.
   - `nqp/tools/templates/jvm/Makefile.in`: deleted the `ASTNODES_SOURCES`
     line (Makefile road unverified, per ruling).
   - Checked `nqp/tools/templates/Makefile-backend-common.in` and
     `nqp/build.gradle.kts`'s `jBootstrapFiles` task: neither needed edits.
     `Makefile-backend-common.in` defines `ASTNODES_SOURCES`/`ASTNODES_*`
     generically and is shared with the moar backend, which still supplies
     its own `ASTNODES_SOURCES = MAST/Nodes.nqp` in
     `nqp/tools/templates/moar/Makefile.in:33` — so the generic template
     stays untouched and moar is unaffected. `jBootstrapFiles` iterates
     `stageTargets` directly, so it tracks the stage-target list edit
     automatically with no source change needed.
3. **Step 3 (ruling-1 branch)**: `nqp/src/vm/jvm/NQP/Ops.nqp` deleted
   (`git rm`, 9 lines, comment-only). Per the ruling:
   - Dropped `"src/vm/jvm/NQP/Ops.nqp"` from `NqpSources.NQP` in
     `NqpSources.kt`.
   - Dropped the `NQP_SOURCES_EXTRA` line from `jvm/Makefile.in:43`
     (grouped with the `ASTNODES_SOURCES` deletion above, same hunk).
   - Changed the `fromMakefileCommon` map entry from
     `"COMMON_NQP_SOURCES" to NQP.drop(1)` to
     `"COMMON_NQP_SOURCES" to NQP` (verified against
     `nqp/tools/templates/Makefile-common.in:78-84`, which lists exactly
     the five `src/NQP/*.nqp` files with no `Ops.nqp` — confirms `NQP_SOURCES_EXTRA`
     was always the JVM-only addition, never part of the generic list).
4. **Step 4 (drift guards)**: `./nqp/gradlew -p nqp checkSourceLists
   genCatParityCheck` — both OK (see output below).
5. **Step 5 (clean build)**: EXIT=0, 221s elapsed / "BUILD SUCCESSFUL in
   3m 41s". Census: 10 jars in `share/lib`, no `JASTNodes.jar`, all
   `unit.meta`-only.
6. **Step 6 (sweep)**: t/nqp + t/qast sweep, 117/120 in the raw sweep; the
   three non-EXIT=0 files were exactly the three expected known cases
   (`019-file-ops.t`, `063-slurp.t` — rerun individually below to confirm
   the pass; `01-qast.t` — moar-only, known red). Net: t/nqp 118/118,
   t/qast 1/2.
7. **Step 7 (commit)**: `git add -A` on the five files (two deletions via
   `git rm`, three modifications), committed with the brief's exact message
   plus the required attribution lines.

## Step 1 grep hits and disposition

Command: `grep -rn 'JASTNodes\|JAST::' nqp/src nqp/t nqp/tools nqp/buildSrc
nqp/build.gradle.kts nqp/docs src/vm/jvm src/Raku src/main.nqp tools`

- `nqp/src/vm/jvm/QAST/JASTNodes.nqp` — the module itself. **Deleted.**
- `nqp/build.gradle.kts:56,148-149,150-156` — the gen-cat list, stage
  target, and two `deps` lists. **Edited** (Step 2).
- `nqp/buildSrc/src/main/kotlin/NqpSources.kt:84` — `val JASTNODES`.
  **Deleted.**
- `nqp/tools/templates/jvm/Makefile.in:41,43` — `ASTNODES_SOURCES` and
  `NQP_SOURCES_EXTRA`. **Deleted** (both, per ruling 1).
- `src/vm/jvm/Raku/Ops.nqp` (many hits, `JAST::Instruction`/`InstructionList`/
  `Label` construction) — **expected, Task 3's file. Left alone.**
- `nqp/docs/truffle-grammar-engine.md:259,407` — prose mentions of
  `JAST::Class`. — **expected, Task 11 (docs). Left alone.**
- **Finding beyond the expected list**: six Kotlin runtime files under
  `nqp/src/vm/jvm/runtime/org/raku/nqp/{jast2bc,runtime/unit}` reference
  `"JAST::Class"`, `"JAST::Field"`, `"JAST::Method"`, `"JAST::Label"`,
  `"JAST::Instruction"`, `"JAST::InvokeDynamic"`, `"JAST::InstructionList"`,
  `"JAST::PushIVal"`/`PushNVal`/`PushSVal`/`PushCVal`/`PushIndex`,
  `"JAST::TryCatch"`, `"JAST::Annotation"` as string keys into a runtime
  `jastNodes` map: `JastField.kt:16`, `JastMethod.kt:50`, `JastClass.kt:36`,
  `JavaClass.kt:8` (comment only), `JASTCompiler.kt` (many, the jast2bc
  bytecode writer's type-lookup table), `runtime/unit/UnitWriter.kt:29-30`.
  These are the jast2bc bytecode-writer runtime (nqp-runtime.jar), not
  consumers of the deleted `nqp/src/vm/jvm/QAST/JASTNodes.nqp` NQP module —
  the task's Interfaces section names only stage targets/jars and
  `NQP/Ops.nqp` as in scope, and `JASTNodes.jar` never appeared in any
  runtime classpath (it was an NQP-level class hierarchy for building JAST
  trees at compile time, unrelated to Kotlin's own JAST-shaped types used
  by the bytecode writer). Left untouched; flagged here for whoever owns
  jast2bc/JAST deletion (per MEMORY.md's "all QAST handling via Truffle"
  entry, JAST/JAST->bytecode retirement is a separate, larger effort not
  in this task's brief).

## Drift guard output

```
> Task :checkSourceLists
checkSourceLists: OK (8 lists)

> Task :genCatParityCheck
genCatParityCheck: OK (18 target/stage combinations)

BUILD SUCCESSFUL in 9s
```

(`genCatParityCheck` dropped from 20 to 18 combinations: 9 lists × 2 stages,
down from 10 × 2 — consistent with removing the `JASTNodes` entry from the
`lists` map.)

## Build

Log: `/home/longwalker/.claude/jobs/25fa1a35/tmp/t2-build.log`
Command: `RAKUDO_RAKUAST=1 NQP_CODE_STRICT=1 raku tools/build/watched-run.raku
--log=... --show-file=... --show='> Task :stage' --show='code-bail'
--show='BUILD' --show='rror' -- ./nqp/gradlew -p nqp clean buildJvm`

`=== EXIT=0 verdict=ok elapsed=221s ===` ("BUILD SUCCESSFUL in 3m 41s", 58
actionable tasks: 53 executed, 2 from cache, 3 up-to-date).

Jar census (`raku tools/build/jar-census.raku nqp/build/jvm/share/lib/*.jar`):

```
ARTIFACT meta=1   class=0      nqp/build/jvm/share/lib/ModuleLoader.jar
ARTIFACT meta=1   class=0      nqp/build/jvm/share/lib/NQPCORE.setting.jar
ARTIFACT meta=1   class=0      nqp/build/jvm/share/lib/NQPHLL.jar
ARTIFACT meta=1   class=0      nqp/build/jvm/share/lib/nqp.jar
ARTIFACT meta=1   class=0      nqp/build/jvm/share/lib/nqpmo.jar
ARTIFACT meta=1   class=0      nqp/build/jvm/share/lib/NQPP5QRegex.jar
ARTIFACT meta=1   class=0      nqp/build/jvm/share/lib/NQPP6QRegex.jar
ARTIFACT meta=1   class=0      nqp/build/jvm/share/lib/QAST.jar
ARTIFACT meta=1   class=0      nqp/build/jvm/share/lib/QASTNode.jar
ARTIFACT meta=1   class=0      nqp/build/jvm/share/lib/QRegex.jar
CENSUS: all 10 jars are unit artifacts
```

10 jars, no `JASTNodes.jar`, all `unit.meta`-only, matching the brief's
"nine stage jars" (the tenth is `nqp.jar` itself, the `Nqp` stage target —
the brief's phrasing "nine stage targets" in the commit subject refers to
the `stageTargets` list going from ten entries to nine).

## Suite

Log dir: `/home/longwalker/.claude/jobs/25fa1a35/tmp/t2-sweep-logs`
Command: `RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=nqp/t/nqp
-t=nqp/t/qast --jobs=3 --log-dir=... --show-file=... -- nqp/nqp-j-gradle`

Raw sweep: **117 of 120 ok in 350s**. Non-EXIT=0 files:
`nqp_t_nqp_019-file-ops_t.log`, `nqp_t_nqp_063-slurp_t.log`,
`nqp_t_qast_01-qast_t.log` — exactly the three expected exceptions.

Verified individually (per the brief's note that these two need to run
from the nqp dir):
- `cd .../nqp && RAKUDO_RAKUAST=1 ./nqp-j-gradle t/nqp/019-file-ops.t` →
  `1..112`, all ok, exit=0.
- `cd .../nqp && RAKUDO_RAKUAST=1 ./nqp-j-gradle t/nqp/063-slurp.t` →
  `1..1`, ok, exit=0.
- `01-qast.t` — EXIT=1, moar-only, known red (not investigated further,
  per the brief's expected "1/2").

**Net: t/nqp 118/118, t/qast 1/2** — matches the brief's expected result
exactly.

## Files changed (nqp tree, commit `5cf759de6`)

- `nqp/build.gradle.kts` (M, 7 insertions/5 deletions net −2... actually
  +2/−7, see diff)
- `nqp/buildSrc/src/main/kotlin/NqpSources.kt` (M)
- `nqp/src/vm/jvm/NQP/Ops.nqp` (D, 9 lines)
- `nqp/src/vm/jvm/QAST/JASTNodes.nqp` (D, 715 lines)
- `nqp/tools/templates/jvm/Makefile.in` (M)

Total: 5 files changed, 5 insertions(+), 739 deletions(-).

## Self-review

- Confirmed `stageTargets` deps for `Hll` and `Qast` now read exactly as
  the brief specified (`listOf("Qregex")` and
  `listOf("Hll", "Qregex", "QastNode")`).
- Confirmed no leftover `JASTNodes`/`JASTNODES`/`JastNodes` string anywhere
  in `build.gradle.kts`, `buildSrc/`, or `jvm/Makefile.in` after the edit
  (re-grepped, zero hits).
- Confirmed `nqp/src/vm/jvm/NQP/` directory itself is gone from the working
  tree (it held only `Ops.nqp`) — no dangling empty directory tracked by
  git.
- Confirmed `Makefile-backend-common.in` and `moar/Makefile.in` are
  unaffected/still self-consistent — moar keeps its own
  `ASTNODES_SOURCES`/`NQP_SOURCES_EXTRA` definitions, so the shared
  template continues to resolve for that backend.
- Confirmed the `fromMakefileCommon` map's `"COMMON_NQP_SOURCES" to NQP`
  change is correct against the actual Makefile-common.in text (5 files,
  no Ops.nqp) — `checkSourceLists` passing is direct evidence, but I
  independently read the template to make sure the fix was for the right
  reason (Ops.nqp was never in the generic list) rather than accidentally
  compensating for something else.
- Did not touch the six Kotlin `jast2bc`/`UnitWriter` files that also match
  `JAST::` — confirmed via the Interfaces section and the runtime/build
  architecture (they're `nqp-runtime.jar`, a different consumer of a
  same-named-but-unrelated concept) that this is correct scope, not an
  oversight. Documented as a finding above rather than silently ignored.

## Concerns

None blocking. One item worth the controller's attention: the jast2bc
Kotlin runtime (`nqp/src/vm/jvm/runtime/org/raku/nqp/jast2bc/*.kt` +
`runtime/unit/UnitWriter.kt`) still names `"JAST::*"` string keys — this is
pre-existing, unrelated to this task's deletion, but is presumably in
scope for a later milestone-4 task (or the "retire JAST" effort mentioned
in MEMORY.md's "all QAST handling via Truffle" entry) since the class
names read as vestigial once `JASTNodes.nqp` (the NQP-side JAST class
hierarchy) no longer exists anywhere in the source tree.
