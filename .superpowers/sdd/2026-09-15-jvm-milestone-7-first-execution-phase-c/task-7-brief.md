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

