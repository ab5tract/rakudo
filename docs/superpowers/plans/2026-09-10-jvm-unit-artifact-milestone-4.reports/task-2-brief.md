### Task 2: The JASTNodes module, the stage lists, nqp's own JAST closures

**Files:**
- Delete: `nqp/src/vm/jvm/QAST/JASTNodes.nqp`
- Modify: `nqp/build.gradle.kts:56` (the gen-cat `lists` map), `:148-149` (`JastNodes` stage target), `:150-156` (the `Hll` and `Qast` `deps` lists), `:434-442` (`jBootstrapFiles` copies whatever `stageTargets` lists: unchanged, but see Task 4)
- Modify: `nqp/buildSrc/src/main/kotlin/NqpSources.kt:84` (`JASTNODES`)
- Modify: `nqp/tools/templates/jvm/Makefile.in:41` (`ASTNODES_SOURCES`)
- Modify: `nqp/src/vm/jvm/NQP/Ops.nqp` (177 lines; the 8 `add_hll_op` and 4 `add_hll_unbox` closures and their helpers)
- Test: `./nqp/gradlew -p nqp checkSourceLists genCatParityCheck`; `clean buildJvm`; t/nqp

**Interfaces:**
- Consumes: Task 1's compiler (nothing `use`s JASTNodes any more).
- Produces: `stageTargets` without `JastNodes`; nine stage jars (`JASTNodes.jar` gone from `build/jvm/stage1`, `stage2`, `share/lib`); `nqp/src/vm/jvm/NQP/Ops.nqp` with no `JAST::` construction.

- [ ] **Step 1**: `grep -rn 'JASTNodes\|JAST::' nqp/src nqp/t nqp/tools nqp/buildSrc nqp/build.gradle.kts nqp/docs src/vm/jvm src/Raku src/main.nqp tools` and record the hits: the expected ones are the six files above plus rakudo's `src/vm/jvm/Raku/Ops.nqp` (Task 3) and docs (Task 11). Anything else is a finding for the report.

- [ ] **Step 2**: delete the module and its build entries: `git rm nqp/src/vm/jvm/QAST/JASTNodes.nqp` (from the nqp dir); in `build.gradle.kts` remove the `"JASTNodes" to NqpSources.JASTNODES,` line and the `StageTarget("JastNodes", ...)` entry, and change `deps = listOf("Qregex", "JastNodes")` to `deps = listOf("Qregex")` (Hll) and `deps = listOf("Hll", "JastNodes", "Qregex", "QastNode")` to `deps = listOf("Hll", "Qregex", "QastNode")` (Qast); in `NqpSources.kt` delete `val JASTNODES = ...`; in `jvm/Makefile.in` delete the `ASTNODES_SOURCES` line (Makefile road unverified; ruling above).

- [ ] **Step 3**: `nqp/src/vm/jvm/NQP/Ops.nqp`: delete every `$ops.add_hll_op('nqp', ...)` block (`preinc`, `predec`, `postinc`, `postdec`, `intify`, `numify`, `stringify`, `falsey`: the encoder has rows for all eight at `TruffleEncoder.nqp:1689-1979`) and every `QAST::OperationsJAST.add_hll_unbox('nqp', ...)` block (`:150-177`), plus the JAST type constants they used. If nothing but comments remains, delete the file, drop `"src/vm/jvm/NQP/Ops.nqp"` from `NqpSources.NQP` and `NQP_SOURCES_EXTRA` from `jvm/Makefile.in:43`, and check `checkSourceLists` still passes (`COMMON_NQP_SOURCES` is `NQP.drop(1)`: when the file goes, change the map entry to `NQP` itself). Any `map_classlib_hll_op('nqp', ...)` calls stay.

- [ ] **Step 4**: drift guards: `./nqp/gradlew -p nqp checkSourceLists genCatParityCheck`. Expected: both OK.

- [ ] **Step 5**: nqp clean build (same command as Task 1 Step 10, log `t2-build.log`). Expected EXIT=0; census: 10 jars in `share/lib` (no `JASTNodes.jar`), all `unit.meta`-only.

- [ ] **Step 6**: t/nqp + t/qast (Task 1 Step 11's command, `t2-sweep`). Expected 118/118, 1/2.

- [ ] **Step 7**: Commit (nqp): `git add -A` on the five files plus the deletion; message `unit compiler: the JASTNodes module and nqp's JAST op closures are gone; nine stage targets`.

---

