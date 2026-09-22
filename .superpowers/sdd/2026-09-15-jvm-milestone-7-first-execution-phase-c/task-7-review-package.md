diff --git a/build.gradle.kts b/build.gradle.kts
index b39e4277a..06dd8a1ee 100644
--- a/build.gradle.kts
+++ b/build.gradle.kts
@@ -1,10 +1,12 @@
+import java.io.ByteArrayOutputStream
+import java.io.OutputStream
 import java.io.StringWriter
 
 plugins {
     kotlin("jvm") version "2.4.10"
     kotlin("plugin.serialization") version "2.4.10" apply false
 }
 // Root project: orchestrates the JVM backend build (runtime jar, bootstrap
 // stages, runner generation). The Makefile build path remains authoritative
 // until parity is proven; see docs/gradle-jvm-build.md.
 repositories {
@@ -261,20 +263,86 @@ fun registerStage(
                     stableSc + listOf("--output=$outputJar", inputFile.absolutePath)
             }
         }
     }
     return compileTasks
 }
 
 val stage1 = registerStage(1, File(projectDir, "src/vm/jvm/stage0"), emptyList())
 val stage2 = registerStage(2, jvmDir.dir("stage1").asFile, stage1.values)
 
+/* Milestone 7 Phase C: the stage2 jars are trained on the trivial
+ * program before they become the lib jars. A COPY is trained, because
+ * rewriting the compile tasks' outputs would make every later build
+ * recompile stage2; jBootstrapFiles keeps copying the untrained jars,
+ * so stage0 stays empty-tabled. */
+val stage2TrainedDir = jvmDir.dir("stage2-trained")
+val stage2Trained = tasks.register<Sync>("stage2Trained") {
+    group = "nqp jvm"
+    description = "Copies the stage2 jars for dispatch training"
+    stageTargets.forEach { from(jvmDir.dir("stage2").file(it.jar)) }
+    into(stage2TrainedDir)
+    stage2.values.forEach { dependsOn(it) }
+}
+
+// Tees the training run's stderr: the build log goes on showing it while
+// doLast turns the same text into the marker file. (commons-io's
+// TeeOutputStream is not on the build script's class path here.)
+val trainDispatchLog = ByteArrayOutputStream()
+val trainDispatchTee = object : OutputStream() {
+    override fun write(b: Int) {
+        System.err.write(b)
+        trainDispatchLog.write(b)
+    }
+
+    override fun write(b: ByteArray, off: Int, len: Int) {
+        System.err.write(b, off, len)
+        trainDispatchLog.write(b, off, len)
+    }
+
+    override fun flush() {
+        System.err.flush()
+        trainDispatchLog.flush()
+    }
+}
+
+val trainDispatch = tasks.register<JavaExec>("trainDispatch") {
+    group = "nqp jvm"
+    description = "Runs the trivial program with NQP_DISPATCH_RECORD=all against the stage2 copy, filling its dispatch slots"
+    dependsOn(stage2Trained, ":nqp-runtime:jar", ":nqp-truffle:jar", "syncTruffleModules")
+    val marker = stage2TrainedDir.file("dispatch-trained.txt").asFile
+    inputs.files(stageTargets.map { stage2TrainedDir.file(it.jar) })
+    inputs.file(runtimeJarFile)
+    outputs.file(marker)
+    javaLauncher = javaToolchains.launcherFor { languageVersion = JavaLanguageVersion.of(toolchainVersion) }
+    workingDir = projectDir
+    mainClass = "org.raku.nqp.runtime.unit.UnitMain"
+    // Class-path input snapshot only; the real class path is set in doFirst.
+    classpath = files(stage2TrainedDir, engineJarFile)
+    environment("NQP_DISPATCH_RECORD", "all")
+    errorOutput = trainDispatchTee
+    doFirst {
+        classpath = files(stage2TrainedDir, runtimeJarFile) + files(thirdPartySorted()) + files(engineJarFile)
+        jvmArgs("--enable-native-access=ALL-UNNAMED", "-Xmx$nqpStageMaxHeap", "-XX:+AllowParallelDefineClass")
+        jvmArgs("--module-path", shareTruffleDir.asFile.absolutePath,
+            "--add-modules", "org.graalvm.truffle,org.graalvm.truffle.runtime")
+        args = listOf("${stage2TrainedDir.asFile.absolutePath}/nqp.jar",
+            "--module-path=${stage2TrainedDir.asFile.absolutePath}",
+            "--setting-path=${stage2TrainedDir.asFile.absolutePath}", "-e", "")
+    }
+    doLast {
+        val text = trainDispatchLog.toString(Charsets.UTF_8)
+        check(text.contains("dispatch-record: wrote")) { "trainDispatch: no 'dispatch-record: wrote' line -- the training run recorded nothing" }
+        marker.writeText(text.lines().filter { it.startsWith("dispatch-record:") }.joinToString("\n") + "\n")
+    }
+}
+
 val syncRuntimeJars = tasks.register<Sync>("syncRuntimeJars") {
     from(nqpThirdParty)
     from(runtimeJarFile)
     // The engine sits here with the rest of the runtime, but the runner puts
     // it on the class path: runnerJars decides the class path by name, so
     // an extra jar in this directory is not picked up by accident.
     from(engineJarFile)
     into(shareRuntimeDir)
     dependsOn(":nqp-runtime:jar", ":nqp-truffle:jar")
 }
@@ -291,23 +359,25 @@ val syncTruffleModules = tasks.register<Sync>("syncTruffleModules") {
 // Makefile build uses with its repo-root jvmconfig.properties.
 val generateLocalJvmConfig = tasks.register<JvmConfigPropertiesTask>("generateLocalJvmConfig") {
     prefix = projectDir.absolutePath
     nqpHome = jvmDir.dir("share").asFile.absolutePath
     thirdPartyJars.set(provider { thirdPartySorted().map { it.absolutePath } })
     generatorLabel = layout.projectDirectory.file("tools/build/gen-jvm-properties.pl").asFile.absolutePath
     output = shareLibDir.file("jvmconfig.properties")
 }
 
 val syncLib = tasks.register<Sync>("syncLib") {
-    stageTargets.forEach { from(jvmDir.dir("stage2").file(it.jar)) }
+    // The trained copy, not stage2's own output: the lib jars carry the
+    // recorded dispatch programs (milestone 7 Phase C).
+    stageTargets.forEach { from(stage2TrainedDir.file(it.jar)) }
     into(shareLibDir)
-    stage2.values.forEach { dependsOn(it) }
+    dependsOn(trainDispatch)
     // jvmconfig.properties is produced into this directory by its own task;
     // don't delete it.
     preserve {
         include("jvmconfig.properties")
     }
 }
 
 val generateRunner = tasks.register<GenerateRunnerTask>("generateRunner") {
     jarDir = shareRuntimeDir.asFile.absolutePath
     libDir = shareLibDir.asFile.absolutePath
diff --git a/tools/templates/jvm/Makefile.in b/tools/templates/jvm/Makefile.in
index bcf731ebb6..e2027f598a 100644
--- a/tools/templates/jvm/Makefile.in
+++ b/tools/templates/jvm/Makefile.in
@@ -149,21 +149,45 @@ $(RUNTIME_JAR): $(RUNTIME_SOURCES) @nfp(rakudo-runtime/build.gradle.kts)@ | $(NQ
 	$(NOECHO)cd @nfp(rakudo-runtime)@ && @nfp(../nqp/gradlew)@ --console=plain jar
 	$(NOECHO)$(CP) @nfp(rakudo-runtime/build/libs/rakudo-runtime.jar)@ $(RUNTIME_JAR)
 
 @bpm(RUN_RAKUDO_SCRIPT)@: @@nfp(@template(@backend_subdir@/rakudo-j-build.in)@)@@
 	$(NOECHO)$(RM_F) @q(@bpm(RUN_RAKUDO_SCRIPT)@)@
 	$(NOECHO)$(CONFIGURE) --expand @nfpq(@backend_subdir@/@bpm(RUN_RAKUDO_SCRIPT)@)@ --out @bpm(RUN_RAKUDO_SCRIPT)@ \
 		--set-var=base_dir=@q($(BASE_DIR))@ \
 		--set-var=java=$(JAVA) \
 		--set-var=classpath=@q(@nfp(./blib)@@cpsep@@nop($(BLD_NQP_JARS))@@cpsep@rakudo-runtime.jar@cpsep@rakudo.jar@cpsep@@nop($(SYSROOT))@@abs2rel(@nqp_classpath@)@)@
 
-$(J_RUNNER): @@script(create-jvm-runner.pl)@@@for_specs( @bsm(SETTING_@ucspec@)@)@
+# Milestone 7 Phase C: one training run of the trivial program fills the
+# dispatch slots of every artifact it loads (blib/*.jar, rakudo.jar and
+# nqp's lib jars). The stamp keeps make's graph honest; the grep is the
+# positive marker (a run that wrote nothing fails the build).
+#
+# The run rewrites those artifacts in its own order, which is not make's:
+# blib/Raku/Actions.jar landing a moment after blib/Raku/Grammar.jar would
+# make the next `make` recompile Grammar and everything below it. The
+# content changed but nothing went stale, so every rewritten artifact gets
+# one and the same mtime back -- make remakes on a STRICTLY newer
+# prerequisite -- and the stamp alone is newer than all of them. The trivial
+# program never loads 6.e (nor any later spec), so the settings and the
+# bootstraps join that one mtime explicitly: training is the last build
+# step, and everything the build produced is current as of it.
+@bpv(TRAIN_STAMP)@ = @nfp(@bpm(BLIB)@/.dispatch-trained)@
+
+@bpm(TRAIN_STAMP)@: @bsm(RAKUDO)@@for_specs( @bsm(SETTING_@ucspec@)@)@
+	@echo(+++ Training	dispatch slots)@
+	$(NOECHO)NQP_DISPATCH_RECORD=all @bpm(RUN_RAKUDO)@ -e '' 2>&1 | tee @nfpq(@bpm(BLIB)@/.dispatch-train.log)@
+	$(NOECHO)grep -q 'dispatch-record: wrote' @nfpq(@bpm(BLIB)@/.dispatch-train.log)@
+	$(NOECHO)sed -n 's|^dispatch-record: wrote .* to ||p' @nfpq(@bpm(BLIB)@/.dispatch-train.log)@ | xargs touch -r @nfpq(@bpm(BLIB)@/.dispatch-train.log)@
+	$(NOECHO)touch -r @nfpq(@bpm(BLIB)@/.dispatch-train.log)@ @bsm(RAKUDO)@@for_specs( @bsm(SETTING_@ucspec@)@)@ @bpm(RAKUDO_BOOTSTRAP_PRECOMPS)@
+	$(NOECHO)touch $@
+
+$(J_RUNNER): @@script(create-jvm-runner.pl)@@@for_specs( @bsm(SETTING_@ucspec@)@)@ @bpm(TRAIN_STAMP)@
 	@echo(+++ Setting up	$@)@
 	$(NOECHO)$(PERL5) @shquot(@script(create-jvm-runner.pl)@)@ dev @q($(BASE_DIR))@ . . @q(@nqp_home@)@ @q(@static_nqp_home@)@ @q(@static_rakudo_home@)@ @q($(NQP_JARS))@
 
 @backend_prefix@-runner-default: @backend_prefix@-all
 	@echo(+++ Setting up @uc(@backend@)@ runner)@
 	$(NOECHO)$(CP) $(J_RUNNER) rakudo$(J_BAT)
 	$(NOECHO)$(CHMOD) 755 rakudo$(J_BAT)
 
 	@echo(+++ Setting up	$@)@
 	$(NOECHO)$(PERL5) @shquot(@script(create-jvm-runner.pl)@)@ dev-debug @q($(BASE_DIR))@ . . @q(@nqp_home@)@ @q(@static_nqp_home@)@ @q(@static_rakudo_home@)@ @q($(NQP_JARS))@
