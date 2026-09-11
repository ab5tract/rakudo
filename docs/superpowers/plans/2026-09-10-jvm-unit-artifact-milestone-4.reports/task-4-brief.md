### Task 4: stage0 regenerated as artifacts; stage compiles enter through UnitMain

**Files:**
- Modify: `nqp/build.gradle.kts:214-224` (`mainClass`, `classpath`, the boot classpath, the args), `:434-442` (`jBootstrapFiles`: unchanged code; run it)
- Modify: `nqp/src/vm/jvm/stage0/*.jar` (nine regenerated; `JASTNodes.jar` removed)
- Modify: `nqp/docs/gradle-jvm-build.md:64-70` (how the bootstrap is modeled), `:114-117` (the regeneration note)
- Test: two clean builds; t/nqp

**Interfaces:**
- Consumes: Task 2's stage2 (`nqp/build/jvm/stage2/*.jar`, artifacts, nine targets); `org.raku.nqp.runtime.unit.UnitMain <unit.jar> args...` (either road; the loader sniffs).
- Produces: stage0 = nine `unit.meta`-only jars built by the Task 1-2 compiler; stage compiles that never touch a class file.

- [ ] **Step 1: The stage compile enters through UnitMain.** In `registerStage` (`build.gradle.kts:214-261`):

```kotlin
            workingDir = projectDir
            mainClass = "org.raku.nqp.runtime.unit.UnitMain"
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
                jvmArgs("--module-path", shareTruffleDir.asFile.absolutePath,
                    "--add-modules", "org.graalvm.truffle,org.graalvm.truffle.runtime")
            }

            val compilerUnit = listOf("${compilerDir.absolutePath}/nqp.jar")
            val stableSc = if (stage == 1) listOf("--stable-sc=stage1") else emptyList()
            args = if (t.isNqp) {
                compilerUnit + listOf("--bootstrap", "--module-path=$stageDirPath", "--setting-path=$stageDirPath",
                    "--setting=${t.setting}", "--target=jar", "--no-regex-lib") +
                    stableSc + listOf("--javaclass=nqp", "--output=$outputJar", inputFile.absolutePath)
            } else {
                compilerUnit + listOf("--bootstrap") +
                    (if (t.settingPath) listOf("--setting-path=$stageDirPath") else emptyList()) +
                    (if (t.modulePath) listOf("--module-path=$stageDirPath") else emptyList()) +
                    listOf("--no-regex-lib", "--target=jar", "--setting=${t.setting}") +
                    stableSc + listOf("--output=$outputJar", inputFile.absolutePath)
            }
```

(The only differences from today: `mainClass`, the boot classpath losing its trailing `<compilerDir>/nqp.jar`, and `compilerUnit` as the first argument.)

- [ ] **Step 2: Build from the class-road stage0 through UnitMain** (proves the entry on the old road): Task 1 Step 10's command with log `t4-build-a.log`. Expected EXIT=0. If `UnitMain` cannot find the compiler's modules (`Could not find ... QAST.jar` or a `loadbytecode` failure), the classpath-derived module search path is the suspect: compare with `nqp-j-gradle`'s `CP`.

- [ ] **Step 3: Regenerate**: `raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/25fa1a35/tmp/t4-bootstrap.log -- ./nqp/gradlew -p nqp jBootstrapFiles`; then from the nqp dir `git rm src/vm/jvm/stage0/JASTNodes.jar`. `ls -la nqp/src/vm/jvm/stage0/`: nine jars, dated now; `raku tools/build/jar-census.raku nqp/src/vm/jvm/stage0/*.jar`: all `unit.meta`-only, zero `.class`, zero `.codeprograms.lz4`.

- [ ] **Step 4: Build from the new stage0**: the clean build again, log `t4-build-b.log`. Expected EXIT=0; stage1 is now compiled by an artifact compiler. Record the build time (the first stage0-as-artifact number).

- [ ] **Step 5**: t/nqp + t/qast (`t4-sweep`). Expected 118/118, 1/2.

- [ ] **Step 6: Docs**: `nqp/docs/gradle-jvm-build.md`: the "How the bootstrap is modeled" paragraph names `org.raku.nqp.runtime.unit.UnitMain <stageDir>/nqp.jar --bootstrap ...` and says stage0 is a set of unit artifacts; add under the regeneration note: "stage0 regenerated 2026-09 as unit artifacts (`./gradlew jBootstrapFiles` after the JAST-free driver landed). Rule: a change that an OLD stage0 could not read (an incompatible wire change, a meta format bump, a syscall shape change) is preceded by a regeneration from the LAST compiler that still speaks the old shape; additive wire changes need none."

- [ ] **Step 7: Commit (nqp)**: `git add -A src/vm/jvm/stage0 build.gradle.kts docs/gradle-jvm-build.md && git commit -m "stage0: regenerated as unit artifacts from the JAST-free compiler; stage compiles enter through UnitMain"` (binary jars: label the hash in the report).

---

