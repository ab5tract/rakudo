 build.gradle.kts                                   |  74 ++++++-
 .../org/raku/nqp/dispatch/DispatchPersistTest.kt   | 153 +++++++++++++
 .../org/raku/nqp/dispatch/DispatchSlotCodecTest.kt |  91 ++++++++
 .../org/raku/nqp/runtime/unit/UnitCodecTest.kt     |   9 +
 .../nqp/runtime/unit/UnitDispatchWriterTest.kt     |  48 ++++
 .../src/main/java/org/raku/nqp/truffle/NqpOps.java |   9 +-
 .../org/raku/nqp/truffle/NqpProgramBuilder.java    |   3 +-
 .../kotlin/org/raku/nqp/truffle/NqpDispatch.kt     |   5 +
 .../jvm/runtime/org/raku/nqp/dispatch/Dispatch.kt  |  26 +++
 .../org/raku/nqp/dispatch/DispatchBootstrap.kt     |  29 +++
 .../runtime/org/raku/nqp/dispatch/DispatchDump.kt  | 143 ++++++++++++
 .../org/raku/nqp/dispatch/DispatchPersist.kt       | 242 +++++++++++++++++++++
 .../runtime/org/raku/nqp/dispatch/DispatchSlot.kt  |  56 +++++
 .../org/raku/nqp/dispatch/DispatchSlotCodec.kt     | 193 ++++++++++++++++
 .../runtime/org/raku/nqp/runtime/GlobalContext.kt  |  19 +-
 .../jvm/runtime/org/raku/nqp/runtime/HLLConfig.kt  |  10 +
 .../org/raku/nqp/runtime/unit/ProgramUnit.kt       |   3 +
 .../runtime/org/raku/nqp/runtime/unit/UnitCodec.kt |  15 +-
 .../raku/nqp/runtime/unit/UnitDispatchWriter.kt    |  84 +++++++
 .../org/raku/nqp/runtime/unit/UnitImageWriter.kt   |   4 +-
 .../runtime/org/raku/nqp/runtime/unit/UnitStore.kt |  27 ++-
 21 files changed, 1224 insertions(+), 19 deletions(-)
diff --git a/build.gradle.kts b/build.gradle.kts
index b39e4277a..06dd8a1ee 100644
--- a/build.gradle.kts
+++ b/build.gradle.kts
@@ -1,8 +1,10 @@
+import java.io.ByteArrayOutputStream
+import java.io.OutputStream
 import java.io.StringWriter
 
 plugins {
     kotlin("jvm") version "2.4.10"
     kotlin("plugin.serialization") version "2.4.10" apply false
 }
 // Root project: orchestrates the JVM backend build (runtime jar, bootstrap
 // stages, runner generation). The Makefile build path remains authoritative
@@ -263,16 +265,82 @@ fun registerStage(
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
@@ -293,19 +361,21 @@ val generateLocalJvmConfig = tasks.register<JvmConfigPropertiesTask>("generateLo
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
diff --git a/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchPersistTest.kt b/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchPersistTest.kt
new file mode 100644
index 000000000..e9dcf0609
--- /dev/null
+++ b/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchPersistTest.kt
@@ -0,0 +1,153 @@
+package org.raku.nqp.dispatch
+
+import java.io.ByteArrayOutputStream
+import java.io.PrintStream
+import java.lang.invoke.MethodType
+import java.nio.ByteBuffer
+import java.nio.charset.StandardCharsets
+import kotlin.test.Test
+import kotlin.test.assertEquals
+import kotlin.test.assertTrue
+import org.raku.nqp.runtime.CallSiteDescriptor
+import org.raku.nqp.runtime.unit.ProgramUnitTestSupport
+import org.raku.nqp.runtime.unit.UnitCodec
+import org.raku.nqp.runtime.unit.UnitImage
+import org.raku.nqp.runtime.unit.UnitImageWriter
+import org.raku.nqp.runtime.unit.UnitStore
+
+class DispatchPersistTest {
+    /** The shared fixture's image with slot 1 (program 0, ordinal 1) filled. */
+    private fun storeWith(slot: ByteArray): UnitStore {
+        val base = ProgramUnitTestSupport.image()
+        val img = UnitImage(base.unitId, base.hll, base.scHandle, base.scDesc, base.serializedCodeRefCount,
+            base.mainlineQbid, base.entryQbid, base.deserializeQbid, base.loadQbid, base.blocks, base.programs,
+            base.dispatchCounts, base.serialized, base.nested, mapOf(1 to slot))
+        return UnitStore.open(ByteBuffer.wrap(UnitImageWriter.bytes(img)), "/x/fixture.jar")
+    }
+
+    @Test fun restoreRealisesTheSlotsProgramsAndCountsThem() {
+        val tc = ProgramUnitTestSupport.tc()
+        val knowhow = tc.gc.KnowHOW!!
+        val csd = CallSiteDescriptor(byteArrayOf(CallSiteDescriptor.ARG_OBJ), null)
+        val p = DispatchProgram(csd, listOf(Guard.OfType(ValueSource.Arg(0), knowhow.st)),
+            Outcome.Value(ValueSource.Arg(0)), emptyList(), ResumeKind.NONE, emptyList(), null)
+        val bytes = UnitCodec.encode(DispatchSlot.serializer(), DispatchSlot(listOf(DispatchSlotCodec.persist(p)!!)))
+        val store = storeWith(bytes)
+        val ns = "/x/fixture.jar!unit-x"
+        DispatchPersist.register(ns, store)
+        val site = DispatchCallSite(MethodType.methodType(Void.TYPE))
+        site.unitNamespace = ns; site.programIndex = 0; site.ordinal = 1
+        val before = DispatchPersist.restored.get()
+        val got = DispatchPersist.restore(tc, site)
+        assertEquals(1, got.size)
+        assertEquals(DispatchDump.describe(p), DispatchDump.describe(got[0]))
+        assertEquals(before + 1, DispatchPersist.restored.get())
+        assertTrue(DispatchPersist.restore(tc, DispatchCallSite(MethodType.methodType(Void.TYPE))).isEmpty(),
+            "an anonymous site restores nothing")
+        site.ordinal = 0
+        assertTrue(DispatchPersist.restore(tc, site).isEmpty(), "an empty slot restores nothing")
+    }
+
+    /** verify mode's three outcomes, which no run can reach until slots are
+     *  written: a kept program that applies and reads the same as the
+     *  recording (matched), one that applies and differs (mismatched, with
+     *  the MISMATCH line), and one whose guards do not hold for this call at
+     *  all (unseen). A verify bug looks exactly like an empty artifact --
+     *  matched=0 mismatched=0 -- so the branches are covered here. */
+    @Test fun verifyCountsAMatchAMismatchAndACallItDoesNotApplyTo() {
+        val tc = ProgramUnitTestSupport.tc()
+        val knowhow = tc.gc.KnowHOW!!
+        val csd = CallSiteDescriptor(byteArrayOf(CallSiteDescriptor.ARG_OBJ), null)
+        fun program(outcome: Outcome) = DispatchProgram(csd,
+            listOf(Guard.OfType(ValueSource.Arg(0), knowhow.st)), outcome,
+            emptyList(), ResumeKind.NONE, emptyList(), null)
+        val site = DispatchCallSite(MethodType.methodType(Void.TYPE))
+        site.identity = "/x/fixture.jar!unit-x#0#1"
+        site.linkedName = "nqp-call"
+        site.verifyPrograms = listOf(program(Outcome.Value(ValueSource.Arg(0))))
+        /* The KnowHOW type object itself: Guard.OfType(Arg(0), knowhow.st)
+         * holds for it and for nothing else here. */
+        val matching = arrayOf<Any?>(knowhow)
+
+        var matched = DispatchPersist.verifyMatched.get()
+        var mismatched = DispatchPersist.verifyMismatched.get()
+        var unseen = DispatchPersist.verifyUnseen.get()
+        DispatchPersist.verify(tc, site, program(Outcome.Value(ValueSource.Arg(0))), csd, matching)
+        assertEquals(matched + 1, DispatchPersist.verifyMatched.get(), "the same program matches")
+        assertEquals(mismatched, DispatchPersist.verifyMismatched.get())
+        assertEquals(unseen, DispatchPersist.verifyUnseen.get())
+
+        matched = DispatchPersist.verifyMatched.get()
+        mismatched = DispatchPersist.verifyMismatched.get()
+        unseen = DispatchPersist.verifyUnseen.get()
+        val differing = program(Outcome.Value(ValueSource.Literal(ArgKind.INT, 1L)))
+        val printed = capturingErr { DispatchPersist.verify(tc, site, differing, csd, matching) }
+        assertEquals(mismatched + 1, DispatchPersist.verifyMismatched.get(), "a different outcome mismatches")
+        assertEquals(matched, DispatchPersist.verifyMatched.get())
+        assertEquals(unseen, DispatchPersist.verifyUnseen.get())
+        assertTrue("dispatch-verify: MISMATCH" in printed, "the mismatch prints: $printed")
+        assertTrue("persisted:" in printed && "recorded:" in printed, "both texts print: $printed")
+
+        matched = DispatchPersist.verifyMatched.get()
+        mismatched = DispatchPersist.verifyMismatched.get()
+        unseen = DispatchPersist.verifyUnseen.get()
+        DispatchPersist.verify(tc, site, program(Outcome.Value(ValueSource.Arg(0))), csd,
+            arrayOf<Any?>(tc.gc.BOOTArray))
+        assertEquals(unseen + 1, DispatchPersist.verifyUnseen.get(), "a call the guards reject is unseen")
+        assertEquals(matched, DispatchPersist.verifyMatched.get())
+        assertEquals(mismatched, DispatchPersist.verifyMismatched.get())
+    }
+
+    /** Two programs written differently that invoke the same callee with the
+     *  same arguments on this call agree (byOutcome, silently); one that
+     *  invokes something else does not. This is the polymorphic-site case
+     *  verify mode meets on a real run: the site re-records in a form the
+     *  persisted program predates. */
+    @Test fun verifyAcceptsADifferentFormWithTheSameEvaluatedOutcome() {
+        val tc = ProgramUnitTestSupport.tc()
+        val knowhow = tc.gc.KnowHOW!!
+        val csd = CallSiteDescriptor(byteArrayOf(CallSiteDescriptor.ARG_OBJ), null)
+        fun program(callee: ValueSource) = DispatchProgram(csd,
+            listOf(Guard.OfType(ValueSource.Arg(0), knowhow.st)),
+            Outcome.InvokeCode(callee, CaptureShape(listOf(ValueSource.Arg(0)), csd)),
+            emptyList(), ResumeKind.NONE, emptyList(), null)
+        val site = DispatchCallSite(MethodType.methodType(Void.TYPE))
+        site.identity = "/x/fixture.jar!unit-y#7#0"
+        site.linkedName = "lang-meth-call"
+        /* The kept program names the callee as a constant, the recording
+         * reads it off the invocant; on these args they are one object. */
+        site.verifyPrograms = listOf(program(ValueSource.Literal(ArgKind.OBJ, knowhow)))
+        val args = arrayOf<Any?>(knowhow)
+
+        var byOutcome = DispatchPersist.verifyByOutcome.get()
+        var matched = DispatchPersist.verifyMatched.get()
+        var mismatched = DispatchPersist.verifyMismatched.get()
+        var unseen = DispatchPersist.verifyUnseen.get()
+        var printed = capturingErr { DispatchPersist.verify(tc, site, program(ValueSource.Arg(0)), csd, args) }
+        assertEquals(byOutcome + 1, DispatchPersist.verifyByOutcome.get(), "the same callee agrees")
+        assertEquals(matched, DispatchPersist.verifyMatched.get())
+        assertEquals(mismatched, DispatchPersist.verifyMismatched.get())
+        assertEquals(unseen, DispatchPersist.verifyUnseen.get())
+        assertEquals("", printed, "an agreement prints nothing")
+
+        byOutcome = DispatchPersist.verifyByOutcome.get()
+        mismatched = DispatchPersist.verifyMismatched.get()
+        val elsewhere = program(ValueSource.Literal(ArgKind.OBJ, tc.gc.BOOTArray))
+        printed = capturingErr { DispatchPersist.verify(tc, site, elsewhere, csd, args) }
+        assertEquals(mismatched + 1, DispatchPersist.verifyMismatched.get(), "another callee does not")
+        assertEquals(byOutcome, DispatchPersist.verifyByOutcome.get())
+        assertTrue("dispatch-verify: MISMATCH" in printed, "the mismatch prints: $printed")
+    }
+
+    /** Runs [body] with stderr captured, and hands back what it wrote. */
+    private fun capturingErr(body: () -> Unit): String {
+        val err = ByteArrayOutputStream()
+        val saved = System.err
+        try {
+            System.setErr(PrintStream(err, true, StandardCharsets.UTF_8))
+            body()
+        }
+        finally { System.setErr(saved) }
+        return err.toString(StandardCharsets.UTF_8)
+    }
+}
diff --git a/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchSlotCodecTest.kt b/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchSlotCodecTest.kt
new file mode 100644
index 000000000..6282346b5
--- /dev/null
+++ b/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchSlotCodecTest.kt
@@ -0,0 +1,91 @@
+package org.raku.nqp.dispatch
+
+import java.nio.ByteBuffer
+import kotlin.test.Test
+import kotlin.test.assertEquals
+import kotlin.test.assertNotSame
+import kotlin.test.assertNotNull
+import kotlin.test.assertNull
+import kotlin.test.assertSame
+import org.raku.nqp.runtime.CallSiteDescriptor
+import org.raku.nqp.runtime.ThreadContext
+import org.raku.nqp.runtime.unit.ProgramUnitTestSupport
+import org.raku.nqp.runtime.unit.UnitCodec
+
+class DispatchSlotCodecTest {
+    private val csd = CallSiteDescriptor(byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_STR), null)
+
+    /** persist -> encode -> decode -> realise, the whole road a slot takes. */
+    private fun roundTrip(tc: ThreadContext, p: DispatchProgram): DispatchProgram {
+        val persisted = assertNotNull(DispatchSlotCodec.persist(p))
+        val bytes = UnitCodec.encode(DispatchSlot.serializer(), DispatchSlot(listOf(persisted)))
+        val back = UnitCodec.decode(DispatchSlot.serializer(), ByteBuffer.wrap(bytes))
+        return assertNotNull(DispatchSlotCodec.realise(tc, back.programs.single()))
+    }
+
+    /** A program guarding arg 0 by the bootstrap's KnowHOW type and a
+     *  string literal on arg 1, invoking the KnowHOW type object itself as
+     *  a stand-in callee: every reference is in __6MODEL_CORE__, so it
+     *  persists. The HLL guard names a config of its own rather than
+     *  knowhow.st.hllOwner, which the bootstrap leaves null. */
+    private fun program(tc: ThreadContext): DispatchProgram {
+        val knowhow = tc.gc.KnowHOW!!
+        return DispatchProgram(csd,
+            listOf(Guard.OfType(ValueSource.Arg(0), knowhow.st),
+                   Guard.Concreteness(ValueSource.Arg(0), false),
+                   Guard.Literal(ValueSource.Arg(1), DispatchValue(ArgKind.STR, "new_type")),
+                   Guard.OfHll(ValueSource.Arg(0), tc.gc.getHLLConfigFor("nqp"))),
+            Outcome.InvokeCode(ValueSource.Literal(ArgKind.OBJ, knowhow),
+                CaptureShape(listOf(ValueSource.Arg(0), ValueSource.Literal(ArgKind.INT, 3L)),
+                    CallSiteDescriptor(byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_INT), null))),
+            emptyList(), ResumeKind.NONE, emptyList(), null)
+    }
+
+    @Test fun aProgramOverScObjectsRoundTripsToTheSameText() {
+        val tc = ProgramUnitTestSupport.tc()
+        val p = program(tc)
+        val realised = roundTrip(tc, p)
+        assertEquals(DispatchDump.describe(p), DispatchDump.describe(realised))
+        /* The dump prints an HLL config by name, but the guard compares by
+         * identity, so the text agreeing is not enough. */
+        assertSame(p.guards.filterIsInstance<Guard.OfHll>().single().hll,
+                   realised.guards.filterIsInstance<Guard.OfHll>().single().hll)
+    }
+
+    @Test fun anHllGuardRealisesInTheRegistryItWasRecordedIn() {
+        val tc = ProgramUnitTestSupport.tc()
+        tc.gc.useCompileeHLLConfig()
+        val compilee = tc.gc.getHLLConfigFor("nqp")
+        tc.gc.useCompilerHLLConfig()
+        val compiler = tc.gc.getHLLConfigFor("nqp")
+        assertNotSame(compilee, compiler)
+        /* Recorded against the compilee-side config while the compiler-side
+         * registry is the current one -- which is the state a unit is loaded
+         * in (Ops.loadcompunit switches to the compiler config). */
+        val realised = roundTrip(tc, DispatchProgram(csd,
+            listOf(Guard.OfHll(ValueSource.Arg(0), compilee)),
+            Outcome.Value(ValueSource.Arg(0)), emptyList(), ResumeKind.NONE, emptyList(), null))
+        assertSame(compilee, realised.guards.filterIsInstance<Guard.OfHll>().single().hll)
+    }
+
+    @Test fun anObjectInNoScMakesTheProgramUnpersistable() {
+        val tc = ProgramUnitTestSupport.tc()
+        val orphan = tc.gc.KnowHOW!!.st.REPR.type_object_for(tc, null)   // a fresh type object, in no SC
+        val p = DispatchProgram(csd, listOf(Guard.Literal(ValueSource.Arg(0), DispatchValue(ArgKind.OBJ, orphan))),
+            Outcome.Value(ValueSource.Arg(0)), emptyList(), ResumeKind.NONE, emptyList(), null)
+        assertNull(DispatchSlotCodec.persist(p))
+    }
+
+    @Test fun aReferenceThatDoesNotResolveDropsTheProgram() {
+        val tc = ProgramUnitTestSupport.tc()
+        val ghost = PProgram(PDescriptor(byteArrayOf(0), null),
+            listOf(PGuardType(PArg(0), PRef("no-such-sc", 0, PRef.STABLE))),
+            POutcomeValue(PArg(0)), emptyList(), ResumeKind.NONE, emptyList(), null, null)
+        assertNull(DispatchSlotCodec.realise(tc, ghost))
+
+        val ghostHll = PProgram(PDescriptor(byteArrayOf(0), null),
+            listOf(PGuardHll(PArg(0), "no-such-hll", false)),
+            POutcomeValue(PArg(0)), emptyList(), ResumeKind.NONE, emptyList(), null, null)
+        assertNull(DispatchSlotCodec.realise(tc, ghostHll))
+    }
+}
diff --git a/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitCodecTest.kt b/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitCodecTest.kt
index 8f21fee22..d5f666496 100644
--- a/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitCodecTest.kt
+++ b/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitCodecTest.kt
@@ -16,16 +16,18 @@ class UnitCodecTest {
         val nested: List<Inner>,
     )
     @Serializable data class Inner(val name: String, val idx: Int)
 
     /** Nested, not local to the test function: the serialization compiler
      *  plugin does not process local classes. */
     @Serializable data class N(val s: String?)
 
+    @Serializable class WithDouble(val d: Double, val tag: Int)
+
     private val sample = Probe(
         -7, 1L shl 40, true, "gr\u00fc\u00dfe \ud83d\udc2a", null,
         listOf("", "a", "\u0000b"), null, intArrayOf(1, -1, Int.MAX_VALUE), longArrayOf(0L, Long.MIN_VALUE),
         listOf(Inner("x", 1), Inner("", -1)),
     )
 
     @Test fun roundTrips() {
         val bytes = UnitCodec.encode(Probe.serializer(), sample)
@@ -47,13 +49,20 @@ class UnitCodecTest {
         val bytes = UnitCodec.encode(Inner.serializer(), Inner("z", 9))
         val padded = ByteBuffer.allocate(bytes.size + 8).order(ByteOrder.LITTLE_ENDIAN)
         padded.position(5); padded.put(bytes); padded.position(5)
         val back = UnitCodec.decode(Inner.serializer(), padded)
         assertEquals(Inner("z", 9), back)
         assertEquals(5, padded.position())
     }
 
+    @Test fun doublesRoundTripAsRawBits() {
+        val b = UnitCodec.encode(WithDouble.serializer(), WithDouble(-0.0, 7))
+        assertEquals(12, b.size)
+        val d = UnitCodec.decode(WithDouble.serializer(), ByteBuffer.wrap(b))
+        assertEquals((-0.0).toRawBits(), d.d.toRawBits()); assertEquals(7, d.tag)
+    }
+
     @Test fun nullMarkIsOneByte() {
         assertContentEquals(byteArrayOf(0), UnitCodec.encode(N.serializer(), N(null)))
         assertContentEquals(byteArrayOf(1, 0, 0, 0, 0), UnitCodec.encode(N.serializer(), N("")))
     }
 }
diff --git a/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitDispatchWriterTest.kt b/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitDispatchWriterTest.kt
new file mode 100644
index 000000000..f7b2b0701
--- /dev/null
+++ b/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitDispatchWriterTest.kt
@@ -0,0 +1,48 @@
+package org.raku.nqp.runtime.unit
+
+import java.io.File
+import java.nio.ByteBuffer
+import kotlin.test.Test
+import kotlin.test.assertContentEquals
+import kotlin.test.assertEquals
+import kotlin.test.assertFailsWith
+import kotlin.test.assertNotNull
+import kotlin.test.assertNull
+
+class UnitDispatchWriterTest {
+    private fun bytesOf(b: ByteBuffer) = ByteArray(b.remaining()).also { b.duplicate().get(it) }
+
+    @Test fun fillsTheNamedSlotsKeepsTheRestAndCopiesEveryOtherEntry() {
+        val nestedStore = UnitStore.open(ByteBuffer.wrap(UnitImageWriter.bytes(ProgramUnitTestSupport.image())), "<n>")
+        val image = ProgramUnitTestSupport.image(nested = mapOf("n1" to nestedStore))
+        val f = File.createTempFile("unit-", ".jar"); f.deleteOnExit()
+        f.writeBytes(UnitImageWriter.bytes(UnitImage(image.unitId, image.hll, image.scHandle, image.scDesc,
+            image.serializedCodeRefCount, image.mainlineQbid, image.entryQbid, image.deserializeQbid, image.loadQbid,
+            image.blocks, image.programs, image.dispatchCounts, image.serialized, image.nested, mapOf(0 to byteArrayOf(1, 2, 3)))))
+        val before = UnitStore.open(f.path)
+        val recordsBefore = bytesOf(before.entry(UnitStore.RECORDS)!!)
+        val serializedBefore = bytesOf(before.entry(UnitStore.SERIALIZED)!!)
+
+        UnitDispatchWriter.rewrite(f.path, mapOf(
+            "unit" to mapOf(2 to byteArrayOf(9, 9)),          // program 2, ordinal 0
+            "nested/n1" to mapOf(1 to byteArrayOf(4, 5, 6))))   // program 0, ordinal 1 of the nested unit
+
+        val after = UnitStore.open(f.path)
+        assertContentEquals(byteArrayOf(1, 2, 3), bytesOf(assertNotNull(after.dispatchSlot(0, 0))), "an unnamed slot keeps its bytes")
+        assertNull(after.dispatchSlot(0, 1), "an unnamed empty slot stays empty")
+        assertContentEquals(byteArrayOf(9, 9), bytesOf(assertNotNull(after.dispatchSlot(2, 0))))
+        assertContentEquals(byteArrayOf(4, 5, 6), bytesOf(assertNotNull(after.nested("n1")!!.dispatchSlot(0, 1))))
+        assertContentEquals(recordsBefore, bytesOf(after.entry(UnitStore.RECORDS)!!))
+        assertContentEquals(serializedBefore, bytesOf(after.entry(UnitStore.SERIALIZED)!!))
+        assertEquals(before.header.dispatchSlotCount, after.header.dispatchSlotCount)
+        assertEquals(PROG2_TEXT, after.program(2))
+    }
+
+    @Test fun refusesASlotOutsideTheTable() {
+        val f = File.createTempFile("unit-", ".jar"); f.deleteOnExit()
+        f.writeBytes(UnitImageWriter.bytes(ProgramUnitTestSupport.image()))
+        assertFailsWith<IllegalArgumentException> { UnitDispatchWriter.rewrite(f.path, mapOf("unit" to mapOf(3 to byteArrayOf(1)))) }
+    }
+
+    companion object { val PROG2_TEXT = ProgramUnitTestSupport.PROG2 }
+}
diff --git a/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java b/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java
index fbc8aeea1..5acd50d04 100644
--- a/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java
+++ b/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java
@@ -821,21 +821,26 @@ final class NqpOps {
      * sites replay their programs with no recording to destroy, which is
      * why the bytecode world tolerates gather-heavy code.
      */
     static final class EngineSite {
         final CallSiteDescriptor csd;
         final org.raku.nqp.dispatch.DispatchCallSite site;
         /* The folded replay prefix of the site's programs; see NqpDispatch. */
         final NqpDispatch.Cache cache;
-        EngineSite(CallSiteDescriptor csd, String identity) {
+        EngineSite(CallSiteDescriptor csd, ProgramIdentity identity, int ordinal) {
             this.csd = csd;
             this.site = new org.raku.nqp.dispatch.DispatchCallSite(
                 java.lang.invoke.MethodType.methodType(void.class));
-            this.site.identity = identity;
+            if (identity != null) {
+                this.site.identity = identity.siteKey(ordinal);
+                this.site.unitNamespace = identity.getNamespace();
+                this.site.programIndex = identity.getProgramIndex();
+                this.site.ordinal = ordinal;
+            }
             org.raku.nqp.dispatch.DispatchBootstrap.registerSite(this.site);
             this.cache = new NqpDispatch.Cache(this.site, csd);
         }
     }
 
 
     /**
      * One dispatch instruction. The replay of the site's folded programs
diff --git a/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java b/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java
index 17e9f8497..21dd47f17 100644
--- a/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java
+++ b/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java
@@ -567,18 +567,17 @@ final class NqpProgramBuilder {
                 // point: the result rides a local so a suspend token can
                 // be yielded and the resumed value take its place.
                 BytecodeLocal dres = emit ? b.createLocal() : null;
                 if (emit) {
                     b.beginBlock();
                     b.beginStoreLocal(dres);
                     // The constant is the instruction's inline cache as
                     // well as its shape; see NqpOps.EngineSite.
-                    b.beginDispatchOp(rtype, name, new NqpOps.EngineSite(csd,
-                        identity == null ? null : identity.siteKey(ordinal)));
+                    b.beginDispatchOp(rtype, name, new NqpOps.EngineSite(csd, identity, ordinal));
                 }
                 for (int i = 0; i < nargs; i++) at = walk(at, emit);
                 if (emit) {
                     b.endDispatchOp();
                     b.endStoreLocal();
                     emitSuspendCheck(dres);
                     b.emitLoadLocal(dres);
                     b.endBlock();
diff --git a/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt b/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt
index 6a72130f3..3aab2afab 100644
--- a/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt
+++ b/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt
@@ -17,18 +17,20 @@ import java.util.Objects
 import java.util.concurrent.ConcurrentHashMap
 import java.util.concurrent.atomic.AtomicLong
 import org.raku.nqp.dispatch.ArgKind
 import org.raku.nqp.dispatch.BindFailure
 import org.raku.nqp.dispatch.BindFailureException
 import org.raku.nqp.dispatch.BindReturnException
 import org.raku.nqp.dispatch.Captures
 import org.raku.nqp.dispatch.Dispatch
+import org.raku.nqp.dispatch.DispatchBootstrap
 import org.raku.nqp.dispatch.DispatchCallSite
 import org.raku.nqp.dispatch.DispatchCompiler
+import org.raku.nqp.dispatch.DispatchPersist
 import org.raku.nqp.dispatch.DispatchProgram
 import org.raku.nqp.dispatch.DispatchRecord
 import org.raku.nqp.dispatch.Guard
 import org.raku.nqp.dispatch.Outcome
 import org.raku.nqp.dispatch.Syscall
 import org.raku.nqp.dispatch.ValueSource
 import org.raku.nqp.runtime.ArgsExpectation
 import org.raku.nqp.runtime.CallFrame
@@ -584,16 +586,19 @@ object NqpDispatch {
     @JvmField val notCodeRef = AtomicLong()
     @JvmField val hitsByKind: Array<AtomicLong> =
         arrayOf(AtomicLong(), AtomicLong(), AtomicLong(), AtomicLong(), AtomicLong())
 
     init {
         if (STATS) Runtime.getRuntime().addShutdownHook(Thread {
             System.err.println("dispatch stats: hits=" + hits + " misses=" + misses +
                 " sites=" + sites + " anon=" + anonSites +
+                " sitesAll=" + DispatchBootstrap.created + " restored=" + DispatchPersist.restored +
+                " restoredSites=" + DispatchPersist.restoredSites + " dropped=" + DispatchPersist.dropped +
+                " recorded=" + DispatchPersist.recorded +
                 " slowEvals=" + slowEvals + " invokes=" + invokes + " directs=" + directs +
                 " noTarget=" + noTarget + " badExpectation=" + badExpectation + " notCodeRef=" + notCodeRef +
                 " slowLayout=" + slowEvalsLayout + " slowNull=" + slowEvalsNull +
                 " byKind[value,syscall,mapped,invoke,resumable]=" + hitsByKind.contentToString())
             noTargetBy.entries.sortedByDescending { it.value.get() }.take(10)
                 .forEach { System.err.println("  noTarget " + it.value + " " + it.key) }
             missesBy.entries.sortedByDescending { it.value.get() }.take(20)
                 .forEach { System.err.println("  misses " + it.value + " " + it.key) }
diff --git a/src/vm/jvm/runtime/org/raku/nqp/dispatch/Dispatch.kt b/src/vm/jvm/runtime/org/raku/nqp/dispatch/Dispatch.kt
index 1f9692e5b..4f7e57973 100644
--- a/src/vm/jvm/runtime/org/raku/nqp/dispatch/Dispatch.kt
+++ b/src/vm/jvm/runtime/org/raku/nqp/dispatch/Dispatch.kt
@@ -101,16 +101,34 @@ object Dispatch {
     fun fallback(site: DispatchCallSite, name: String, descriptor: CallSiteDescriptor,
                  compiled: Int, tc: ThreadContext, args: Array<Any?>) {
         val programs = site.programs
         if (programs.size > compiled) {
             val ctx = GuardCheckContext(tc, descriptor, args)
             for (i in compiled until programs.size)
                 if (run(tc, ctx, programs[i], site)) return
         }
+        if (site.linkedName == null) site.linkedName = name
+        /* First miss of this site's life: the persisted programs, if any,
+         * before a recording (milestone 7 Phase C). */
+        if (!site.restored && site.unitNamespace != null) {
+            site.restored = true
+            when (DispatchPersist.mode) {
+                DispatchPersist.Mode.ON -> {
+                    val persisted = DispatchPersist.restore(tc, site)
+                    if (persisted.isNotEmpty()) {
+                        for (p in persisted) site.install(p)
+                        val ctx = GuardCheckContext(tc, descriptor, args)
+                        for (p in persisted) if (run(tc, ctx, p, site)) return
+                    }
+                }
+                DispatchPersist.Mode.VERIFY -> site.verifyPrograms = DispatchPersist.restore(tc, site)
+                DispatchPersist.Mode.OFF -> {}
+            }
+        }
         val registry = tc.gc.dispatchers
         val epoch = registry.epoch
         var cached = site.cachedDispatcher
         if (cached == null || cached.epoch != epoch) {
             cached = CachedDispatcher(registry.find(tc, name), epoch)
             site.cachedDispatcher = cached
         }
         record(tc, cached.dispatcher, descriptor, args, site)
@@ -243,20 +261,23 @@ object Dispatch {
                     }
                 }
             }
 
             record.endRecording()
             val program = record.compile()
             record.program = program
             if (chain != null) report(chain, program)
+            DispatchPersist.recorded.incrementAndGet()
             if (bindFailureOf != null)
                 bindFailureOf.program!!.bindFailureProgram = program
             else if (site != null && !record.doNotInstall)
                 site.install(program)
+            if (site != null && DispatchPersist.mode == DispatchPersist.Mode.VERIFY)
+                DispatchPersist.verify(tc, site, program, descriptor, args)
             } catch (sse: org.raku.nqp.runtime.SaveStackException) {
                 /* A continuation capture is crossing this recording. The
                  * recording cannot survive it -- this very Java frame is
                  * not part of the continuation -- so a resumed callback
                  * would hold captures of a dead recording and die far
                  * away in a dispatcher syscall. Refuse here, loudly, the
                  * way MoarVM refuses captures across a dispatch. */
                 throw ExceptionHandling.dieInternal(tc,
@@ -333,16 +354,21 @@ object Dispatch {
             throw ExceptionHandling.dieInternal(tc,
                 "Resumption state is not available while checking dispatch guards")
 
         override fun resumeState(level: Int): SixModelObject? =
             throw ExceptionHandling.dieInternal(tc,
                 "Resumption state is not available while checking dispatch guards")
     }
 
+    /** A guard-check context for a caller outside this file: the class is
+     *  private, so DispatchPersist.verify asks for one rather than making it. */
+    internal fun guardContext(tc: ThreadContext, descriptor: CallSiteDescriptor,
+                              args: Array<Any?>): DispatchContext = GuardCheckContext(tc, descriptor, args)
+
     /**
      * Tries to run a program: checks that it applies to these arguments and, if
      * it does, carries out its outcome. Returns false if a guard failed, in
      * which case nothing has been done. The dispatch record — needed for as
      * long as the outcome runs, so that the dispatch can be resumed — is only
      * made once the program's shape and guards have matched, so an attempt
      * that fails allocates nothing.
      */
diff --git a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchBootstrap.kt b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchBootstrap.kt
index e7bddd364..4e40c8663 100644
--- a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchBootstrap.kt
+++ b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchBootstrap.kt
@@ -24,32 +24,48 @@ class CachedDispatcher(@JvmField val dispatcher: Dispatcher, @JvmField val epoch
  * ([DispatchCompiler]); a site born from an invokedynamic instruction also
  * makes the chain its target, so settled dispatches bypass the interpreted
  * program loop entirely. Compilation waits for the heat threshold because
  * building a chain costs real time (MethodHandle combinators spin classes),
  * and most sites never run often enough to earn one back.
  */
 class DispatchCallSite @JvmOverloads constructor(type: MethodType,
                        @JvmField val fromIndy: Boolean = false) : MutableCallSite(type) {
+    init { DispatchBootstrap.created.incrementAndGet() }
+
     @Volatile @JvmField var programs: Array<DispatchProgram> = emptyArray()
 
     /**
      * The dispatcher name and callsite shape of the instruction this site
      * belongs to, noted on the first dispatch through it. Both are constants
      * of the instruction, which is what lets a compiled target bind them.
      */
     @JvmField var linkedName: String? = null
     @JvmField var staticDescriptor: CallSiteDescriptor? = null
 
     /** "<unit id>#<program index>#<ordinal>" for a site of a store-backed
      *  unit's program; null for an anonymous site (an in-memory unit, the
      *  helper sites in Ops, Rakudo's rv-decont site, the indy road). Phase
      *  C keys unit.dispatch by it. Set once at construction. */
     @JvmField var identity: String? = null
 
+    /** Where the site's unit.dispatch slot is: the unit's identity namespace
+     *  (DispatchPersist maps it to the store), the program index and the
+     *  ordinal. -1/null for an anonymous site. Set once at construction. */
+    @JvmField var unitNamespace: String? = null
+    @JvmField var programIndex: Int = -1
+    @JvmField var ordinal: Int = -1
+
+    /** The slot has been consulted once for this site's current life; reset()
+     *  clears it, so an eval-server run re-arms from the slot. */
+    @JvmField var restored: Boolean = false
+
+    /** verify mode only: the realised persisted programs, kept aside. */
+    @JvmField var verifyPrograms: List<DispatchProgram>? = null
+
     /** The dispatcher this site's instruction names, found once per
      *  registry epoch rather than on every miss. Dispatcher and epoch
      *  travel together in one immutable holder, published volatile. */
     @Volatile @JvmField var cachedDispatcher: CachedDispatcher? = null
 
     /**
      * The compiled guard chain, as (ThreadContext, Object[])void, once the
      * site has proven hot. Helper-made sites run it straight from the
@@ -79,16 +95,18 @@ class DispatchCallSite @JvmOverloads constructor(type: MethodType,
      * linked in. The programs cached at a callsite guard on the types of the
      * run that recorded them, and those belong to one GlobalContext; a process
      * that runs unrelated programs in turn must not carry them over.
      */
     fun reset() {
         programs = emptyArray()
         chain = null
         heat = 0
+        restored = false
+        verifyPrograms = null
         linkedName = null
         staticDescriptor = null
         cachedDispatcher = null
         coldTarget?.let { if (fromIndy) setTarget(it) }
         onReset?.run()
     }
 
     /**
@@ -112,16 +130,21 @@ class DispatchCallSite @JvmOverloads constructor(type: MethodType,
         chain = compiled
         if (fromIndy)
             setTarget(DispatchCompiler.adaptToIndy(compiled, type()))
     }
 }
 
 /** Links dispatch instructions to the dispatch machinery. */
 object DispatchBootstrap {
+    /** Every DispatchCallSite this process has made, indy-born, helper-made
+     *  and engine-made alike -- the denominator the dispatch stats line's
+     *  site counts are read against. */
+    @JvmField val created = java.util.concurrent.atomic.AtomicLong()
+
     /**
      * Every callsite linked in this process. A long-lived process that runs
      * unrelated programs in turn -- the eval server -- loads the compilation
      * unit once, so its dispatch instructions, and the inline caches they
      * carry, are shared by every run. Each run builds its own GlobalContext
      * and so its own type universe, which a program recorded by an earlier run
      * can never match; the re-recording that follows re-enters the same
      * callsite and does not terminate. Handing each run cold caches keeps the
@@ -135,16 +158,22 @@ object DispatchBootstrap {
      * dispatch state of its own that must go cold with everything else --
      * rakudo's per-routine rv-decont sites held every run's routines, and
      * through them each run's whole serialization-context graph, ~180MB a
      * run -- but it cannot be named from here: nqp does not see rakudo.
      * Whoever owns such a cache registers its clearing instead.
      */
     private val resettables = java.util.concurrent.CopyOnWriteArrayList<Runnable>()
 
+    init { DispatchDump.installIfRequested() }
+
+    /** Every callsite registered here, for diagnostics that walk them. */
+    @JvmStatic
+    fun sites(): Collection<DispatchCallSite> = linked
+
     @JvmStatic
     fun registerResettable(action: Runnable) {
         resettables.add(action)
     }
 
     /**
      * Registers a helper-made callsite for the per-run reset -- the code
      * engine's per-instruction sites use this: their programs record
diff --git a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchDump.kt b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchDump.kt
new file mode 100644
index 000000000..429faeea9
--- /dev/null
+++ b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchDump.kt
@@ -0,0 +1,143 @@
+package org.raku.nqp.dispatch
+
+import java.io.File
+import java.io.PrintWriter
+import org.raku.nqp.runtime.CallSiteDescriptor
+import org.raku.nqp.sixmodel.STable
+import org.raku.nqp.sixmodel.SixModelObject
+
+/**
+ * `NQP_DISPATCH_DUMP=<path>`: at exit, every registered callsite's installed
+ * programs in a normalised text form -- one `site` line per callsite, one
+ * `prog` line per program. Every object, STable and code reference is named
+ * by its serialization context (handle and root-set index) when it has one,
+ * and marked `NP(...)` with the reason when it has none, so two dumps of the
+ * same build compare textually and the unpersistable programs show their
+ * cause. Milestone 7 Phase C's spike (C0) sizes the persisted miss from
+ * these dumps; `tools/build/dispatch-dump-diff.raku` in Rakudo reads them.
+ */
+object DispatchDump {
+    private val path: String? = System.getenv("NQP_DISPATCH_DUMP")
+
+    @JvmStatic
+    fun installIfRequested() {
+        val p = path ?: return
+        Runtime.getRuntime().addShutdownHook(Thread { write(p) })
+    }
+
+    private fun write(p: String) {
+        PrintWriter(File(p).bufferedWriter()).use { out ->
+            for (site in DispatchBootstrap.sites()) {
+                val programs = site.programs
+                out.println("site ${site.identity ?: "anon"} ${site.linkedName ?: "?"} " +
+                    "${programs.size}${if (site.fromIndy) " indy" else ""}")
+                for ((i, prog) in programs.withIndex())
+                    out.println("prog $i ${describe(prog)}")
+            }
+        }
+    }
+
+    /* ----- references ----- */
+
+    /* The addressing itself is DispatchSlotCodec's, so that a dump names a
+     * reference exactly when the program carrying it persists; what has no
+     * address is spelled out here instead, with the reason the codec gave. */
+
+    private fun typeName(obj: SixModelObject): String =
+        if (obj.stInitialized) obj.st.debugName ?: "?" else "?"
+
+    private fun kindName(kind: Int): String = when (kind) {
+        PRef.CODE -> "code"
+        PRef.STABLE -> "st"
+        else -> "obj"
+    }
+
+    private fun address(r: PRef): String = "${kindName(r.kind)}:${r.handle}:${r.index}"
+
+    private fun ref(obj: SixModelObject?): String {
+        if (obj == null) return "null"
+        return try {
+            address(DispatchSlotCodec.ref(obj)!!)
+        } catch (_: Unpersistable) {
+            "NP(obj:${obj.javaClass.simpleName}:${typeName(obj)}:${if (obj.sc == null) "nosc" else "notroot"})"
+        }
+    }
+
+    private fun ref(st: STable?): String {
+        if (st == null) return "null"
+        return try {
+            address(DispatchSlotCodec.ref(st)!!)
+        } catch (_: Unpersistable) {
+            "NP(st:${st.debugName}:${if (st.sc == null) "nosc" else "notroot"})"
+        }
+    }
+
+    private fun literal(kind: ArgKind, value: Any?): String = when (kind) {
+        ArgKind.OBJ -> ref(value as SixModelObject?)
+        ArgKind.STR -> "str:" + (value as String?)?.let { quote(it) }
+        else -> "${kind.name.lowercase()}:$value"
+    }
+
+    private fun quote(s: String): String {
+        val cut = if (s.length > 60) s.substring(0, 60) + "..." else s
+        return "\"" + cut.replace("\\", "\\\\").replace("\"", "\\\"")
+            .replace("\n", "\\n").replace("\r", "\\r") + "\""
+    }
+
+    /* ----- the model ----- */
+
+    private fun descriptor(csd: CallSiteDescriptor): String =
+        "csd[" + csd.argFlags.joinToString(",") +
+            (csd.names?.let { "|" + it.joinToString(",") } ?: "") + "]"
+
+    private fun source(s: ValueSource): String = when (s) {
+        is ValueSource.Arg -> "arg(${s.index})"
+        is ValueSource.ResumeInitArg -> "rinit(${s.level},${s.index})"
+        is ValueSource.Literal -> "lit(${literal(s.kind, s.value)})"
+        is ValueSource.Attribute -> "attr(${source(s.from)},${ref(s.classHandle)},${s.name},${s.kind})"
+        is ValueSource.How -> "how(${source(s.from)})"
+        is ValueSource.Unbox -> "unbox(${source(s.from)},${s.kind})"
+        is ValueSource.Lookup -> "lookup(${source(s.table)},${source(s.key)})"
+        is ValueSource.ResumeState -> "rstate(${s.level})"
+    }
+
+    private fun guard(g: Guard): String = when (g) {
+        is Guard.OfType -> "type(${source(g.on)},${ref(g.type)})"
+        is Guard.Concreteness -> "conc(${source(g.on)},${g.concrete})"
+        is Guard.Literal -> "lit(${source(g.on)},${literal(g.expected.kind, g.expected.value)})"
+        is Guard.NotLiteralObj -> "notlit(${source(g.on)},${ref(g.rejected)})"
+        is Guard.OfHll -> "hll(${source(g.on)},${g.hll?.name})"
+    }
+
+    private fun shape(c: CaptureShape): String =
+        "shape(" + c.sources.joinToString(",") { source(it) } + ";" + descriptor(c.descriptor) + ")"
+
+    private fun outcome(o: Outcome): String = when (o) {
+        is Outcome.Value -> "value(${source(o.source)})"
+        is Outcome.InvokeCode -> "invoke(${source(o.callee)},${shape(o.args)})"
+        is Outcome.InvokeSyscall -> "syscall(${o.syscall.name},${shape(o.args)})"
+    }
+
+    fun describe(p: DispatchProgram): String {
+        val sb = StringBuilder()
+        sb.append(descriptor(p.descriptor))
+        sb.append(" guards=[").append(p.guards.joinToString(";") { guard(it) }).append(']')
+        sb.append(" outcome=").append(outcome(p.outcome))
+        if (p.resumptions.isNotEmpty())
+            sb.append(" resumptions=[").append(p.resumptions.joinToString(";") {
+                "${it.dispatcher.id}:${shape(it.initArgs)}" }).append(']')
+        if (p.resumeKind != ResumeKind.NONE) {
+            sb.append(" resume=").append(p.resumeKind.name)
+            sb.append(" levels=[").append(p.resumeLevels.joinToString(";") { l ->
+                "${l.dispatcher.id}:${descriptor(l.initDescriptor)}:[" +
+                    l.guards.joinToString(";") { guard(it) } + "]:" +
+                    (l.newState?.let { source(it) } ?: "-") + ":" + l.requireNoFurther
+            }).append(']')
+        }
+        p.bindControl?.let {
+            sb.append(" bind=(${it.failureFlag},${it.successFlag},${it.onSuccessToo})")
+        }
+        p.bindFailureProgram?.let { sb.append(" bindfail=(").append(describe(it)).append(')') }
+        return sb.toString()
+    }
+}
diff --git a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt
new file mode 100644
index 000000000..fdaa1028a
--- /dev/null
+++ b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt
@@ -0,0 +1,242 @@
+package org.raku.nqp.dispatch
+
+import java.io.FileOutputStream
+import java.io.PrintStream
+import java.util.concurrent.ConcurrentHashMap
+import java.util.concurrent.atomic.AtomicLong
+import org.raku.nqp.runtime.CallSiteDescriptor
+import org.raku.nqp.runtime.ThreadContext
+import org.raku.nqp.runtime.unit.UnitCodec
+import org.raku.nqp.runtime.unit.UnitStore
+import org.raku.nqp.sixmodel.SixModelObject
+
+/**
+ * The persisted miss (milestone 7 Phase C): a site's first miss restores
+ * the programs its unit.dispatch slot holds before anything is recorded.
+ *
+ * NQP_DISPATCH_PERSIST: unset or "on" consumes slots; "off" ignores them;
+ * "verify" restores into DispatchCallSite.verifyPrograms without installing,
+ * records fresh, and compares (see verify). NQP_DISPATCH_VERIFY_LOG=<path>
+ * sends verify's lines to that file instead of stderr, pid-prefixed, so a
+ * TAP run and a stderr-comparing test survive the mode. NQP_DISPATCH_RECORD
+ * ("all" or a comma-separated list of store-name prefixes) makes the process
+ * rewrite the selected artifacts' slots at exit (recordAtExit).
+ * NQP_DISPATCH_PERSIST_TRACE names every program a restore drops.
+ *
+ * Stores are registered by identity namespace (store name + "!" + unit
+ * id) when a ProgramUnit initializes; they are immutable and process-wide,
+ * so the eval server's runs share them.
+ */
+object DispatchPersist {
+    enum class Mode { ON, OFF, VERIFY }
+
+    @JvmField val mode: Mode = when (System.getenv("NQP_DISPATCH_PERSIST")) {
+        "off" -> Mode.OFF
+        "verify" -> Mode.VERIFY
+        else -> Mode.ON
+    }
+
+    /** Where verify's lines go; null is stderr. */
+    private val verifyLog: String? = System.getenv("NQP_DISPATCH_VERIFY_LOG")
+
+    /** Names each dropped program's reason; a restore is otherwise silent. */
+    private val TRACE = System.getenv("NQP_DISPATCH_PERSIST_TRACE") != null
+
+    private val stores = ConcurrentHashMap<String, UnitStore>()
+
+    /** NQP_DISPATCH_RECORD: "all", or comma-separated store-name prefixes. */
+    private val recordSelector: List<String>? = System.getenv("NQP_DISPATCH_RECORD")?.split(',')?.map { it.trim() }?.filter { it.isNotEmpty() }
+
+    private fun selected(storeName: String): Boolean =
+        recordSelector!!.any { it == "all" || storeName.startsWith(it) }
+
+    @JvmField val restored = AtomicLong()
+    @JvmField val restoredSites = AtomicLong()
+    @JvmField val dropped = AtomicLong()
+    @JvmField val recorded = AtomicLong()
+    @JvmField val verifyMatched = AtomicLong()
+    @JvmField val verifyByOutcome = AtomicLong()
+    @JvmField val verifyMismatched = AtomicLong()
+    @JvmField val verifyUnseen = AtomicLong()
+
+    /** The verify log's stream, opened on its first line; stderr needs none. */
+    @Volatile private var logStream: PrintStream? = null
+
+    private fun verifyOut(): PrintStream {
+        val path = verifyLog ?: return System.err
+        logStream?.let { return it }
+        synchronized(this) {
+            logStream?.let { return it }
+            val s = PrintStream(FileOutputStream(path, true), true)
+            logStream = s
+            return s
+        }
+    }
+
+    /** One verify line, pid-prefixed when it goes to the log: several
+     *  processes (the eval server's children, a parallel harness) append to
+     *  one file, so a line has to say who wrote it. */
+    private fun verifySay(text: String) {
+        if (verifyLog == null) System.err.println(text)
+        else verifyOut().println("[" + ProcessHandle.current().pid() + "] " + text)
+    }
+
+    init {
+        if (mode == Mode.VERIFY) {
+            verifySay("dispatch-verify: on")
+            Runtime.getRuntime().addShutdownHook(Thread {
+                verifySay("dispatch-verify: matched=$verifyMatched byOutcome=$verifyByOutcome" +
+                    " mismatched=$verifyMismatched unseen=$verifyUnseen")
+                logStream?.close()
+            })
+        }
+        if (recordSelector != null) Runtime.getRuntime().addShutdownHook(Thread { recordAtExit() })
+    }
+
+    @JvmStatic
+    fun register(namespace: String, store: UnitStore) { stores.putIfAbsent(namespace, store) }
+
+    fun store(namespace: String): UnitStore? = stores[namespace]
+
+    /** The slot's programs realised against this process, empty when the
+     *  site is anonymous, the slot empty, or nothing resolves. */
+    fun restore(tc: ThreadContext, site: DispatchCallSite): List<DispatchProgram> {
+        val ns = site.unitNamespace ?: return emptyList()
+        val store = stores[ns] ?: return emptyList()
+        val bytes = store.dispatchSlot(site.programIndex, site.ordinal) ?: return emptyList()
+        val slot = try { UnitCodec.decode(DispatchSlot.serializer(), bytes) }
+                   catch (e: Exception) { throw IllegalStateException("unit ${ns}: dispatch slot of program ${site.programIndex} ordinal ${site.ordinal} does not decode: ${e.message}", e) }
+        val onDrop: ((String) -> Unit)? =
+            if (TRACE) { reason -> System.err.println("dispatch-persist: dropped ${site.identity} $reason") }
+            else null
+        val out = ArrayList<DispatchProgram>(slot.programs.size)
+        for (p in slot.programs) {
+            val r = DispatchSlotCodec.realise(tc, p, onDrop)
+            if (r == null) dropped.incrementAndGet() else out.add(r)
+        }
+        if (out.isNotEmpty()) { restored.addAndGet(out.size.toLong()); restoredSites.incrementAndGet() }
+        return out
+    }
+
+    /** verify mode: after a fresh recording, every kept-aside program that
+     *  applies to the recorded call must agree with the recording -- by its
+     *  text, or failing that by what its outcome evaluates to (see
+     *  [sameOutcome]). */
+    fun verify(tc: ThreadContext, site: DispatchCallSite, recorded: DispatchProgram,
+               descriptor: CallSiteDescriptor, args: Array<Any?>) {
+        val kept = site.verifyPrograms ?: return
+        if (kept.isEmpty()) { verifyUnseen.incrementAndGet(); return }
+        val ctx = Dispatch.guardContext(tc, descriptor, args)
+        var applicable = 0
+        val text = DispatchDump.describe(recorded)
+        for (p in kept) {
+            if (!Captures.sameShape(p.descriptor, descriptor) || !p.guardsMatch(ctx)) continue
+            applicable++
+            val theirs = DispatchDump.describe(p)
+            if (theirs == text) verifyMatched.incrementAndGet()
+            else if (sameOutcome(ctx, p, recorded)) verifyByOutcome.incrementAndGet()
+            else {
+                verifyMismatched.incrementAndGet()
+                verifySay("dispatch-verify: MISMATCH ${site.identity} ${site.linkedName}\n  persisted: $theirs\n  recorded:  $text")
+            }
+        }
+        if (applicable == 0) verifyUnseen.incrementAndGet()
+    }
+
+    /**
+     * Do two programs do the same thing to this call, though they are not
+     * written the same way? A polymorphic site records the FORM its
+     * dispatchers found at the time: nqp's lang-meth-call records a
+     * type-guarded program before a class publishes its method cache and a
+     * method-cache lookup after, and verify mode -- which keeps the restored
+     * programs aside instead of installing them, so the site keeps recording
+     * -- then sees two texts that resolve to one target. Comparing what the
+     * outcome evaluates to on the recorded call's own arguments tells that
+     * apart from a real divergence.
+     *
+     * Resuming programs stay text-only: their sources read resumption state,
+     * which this context does not have, and they are rare. Evaluation itself
+     * only reads attributes and hash entries -- no side effects -- but a
+     * source that cannot be evaluated here (a shape built for another call)
+     * throws rather than answering, and an unanswerable comparison is not an
+     * agreement, so it counts as a difference.
+     */
+    private fun sameOutcome(ctx: DispatchContext, a: DispatchProgram, b: DispatchProgram): Boolean = try {
+        if (a.isResuming || b.isResuming) false
+        else if (a.bindControl != b.bindControl) false
+        else if (a.resumptions.size != b.resumptions.size) false
+        else if (a.resumptions.indices.any { i ->
+                    val x = a.resumptions[i]; val y = b.resumptions[i]
+                    x.dispatcher.id != y.dispatcher.id || !sameCapture(ctx, x.initArgs, y.initArgs) })
+            false
+        else {
+            val ao = a.outcome
+            val bo = b.outcome
+            when {
+                ao is Outcome.Value && bo is Outcome.Value ->
+                    sameValue(ao.source.evaluateRaw(ctx), bo.source.evaluateRaw(ctx))
+                ao is Outcome.InvokeCode && bo is Outcome.InvokeCode ->
+                    sameValue(ao.callee.evaluateRaw(ctx), bo.callee.evaluateRaw(ctx)) &&
+                        sameCapture(ctx, ao.args, bo.args)
+                ao is Outcome.InvokeSyscall && bo is Outcome.InvokeSyscall ->
+                    ao.syscall.name == bo.syscall.name && sameCapture(ctx, ao.args, bo.args)
+                else -> false
+            }
+        }
+    }
+    catch (_: Exception) { false }
+
+    private fun sameCapture(ctx: DispatchContext, a: CaptureShape, b: CaptureShape): Boolean {
+        if (!Captures.sameShape(a.descriptor, b.descriptor)) return false
+        val av = a.evaluate(ctx)
+        val bv = b.evaluate(ctx)
+        if (av.size != bv.size) return false
+        for (i in av.indices) if (!sameValue(av[i], bv[i])) return false
+        return true
+    }
+
+    /** An object is the same only when it IS the same: two type objects of
+     *  one type are distinct values to a dispatch. */
+    private fun sameValue(x: Any?, y: Any?): Boolean =
+        if (x is SixModelObject || y is SixModelObject) x === y else x == y
+
+    /** The training run's exit: every recorded site of every selected
+     *  store, persisted into its slot; duplicates of one slot (two live
+     *  sites with one identity) merge by text, capped at MAX_PROGRAMS. */
+    @JvmStatic
+    fun recordAtExit() {
+        val bySlot = HashMap<String, HashMap<String, HashMap<Int, LinkedHashMap<String, DispatchProgram>>>>()
+        for (site in DispatchBootstrap.sites()) {
+            val ns = site.unitNamespace ?: continue
+            val programs = site.programs
+            if (programs.isEmpty()) continue
+            val store = stores[ns] ?: continue
+            if (!selected(store.name)) continue
+            val slot = store.absoluteSlot(site.programIndex, site.ordinal)
+            if (slot < 0) continue
+            val byText = bySlot.getOrPut(store.name) { HashMap() }.getOrPut(store.entryPrefix) { HashMap() }.getOrPut(slot) { LinkedHashMap() }
+            for (p in programs) byText.putIfAbsent(DispatchDump.describe(p), p)
+        }
+        for ((path, perPrefix) in bySlot) {
+            var slots = 0; var written = 0; var unpersistable = 0
+            val encoded = HashMap<String, Map<Int, ByteArray>>()
+            for ((prefix, perSlot) in perPrefix) {
+                val m = HashMap<Int, ByteArray>()
+                for ((slot, byText) in perSlot) {
+                    val persisted = ArrayList<PProgram>()
+                    for (p in byText.values) {
+                        val pp = DispatchSlotCodec.persist(p)
+                        if (pp == null) unpersistable++ else if (persisted.size < Dispatch.MAX_PROGRAMS) persisted.add(pp)
+                    }
+                    if (persisted.isEmpty()) continue
+                    m[slot] = UnitCodec.encode(DispatchSlot.serializer(), DispatchSlot(persisted))
+                    slots++; written += persisted.size
+                }
+                if (m.isNotEmpty()) encoded[prefix] = m
+            }
+            if (encoded.isEmpty()) continue
+            org.raku.nqp.runtime.unit.UnitDispatchWriter.rewrite(path, encoded)
+            System.err.println("dispatch-record: wrote $slots slots ($written programs, $unpersistable unpersistable) to $path")
+        }
+    }
+}
diff --git a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlot.kt b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlot.kt
new file mode 100644
index 000000000..21590d4ec
--- /dev/null
+++ b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlot.kt
@@ -0,0 +1,56 @@
+package org.raku.nqp.dispatch
+
+import kotlinx.serialization.SerialName
+import kotlinx.serialization.Serializable
+
+/**
+ * The persisted twin of a DispatchProgram (milestone 7 Phase C): the
+ * same tree with every object reference replaced by an SC address, the
+ * HLL config by its name, the syscall by its name and the dispatcher by
+ * its id. One DispatchSlot per site slot of unit.dispatch, encoded by
+ * UnitCodec. Data only; DispatchSlotCodec converts both ways.
+ */
+@Serializable class PRef(val handle: String, val index: Int, val kind: Int) {
+    companion object { const val OBJ = 0; const val CODE = 1; const val STABLE = 2 }
+}
+
+@Serializable class PDescriptor(val flags: ByteArray, val names: List<String>?)
+
+@Serializable sealed class PSource
+@Serializable @SerialName("arg") class PArg(val index: Int) : PSource()
+@Serializable @SerialName("rinit") class PResumeInitArg(val level: Int, val index: Int) : PSource()
+/** OBJ: [obj] (null is the null object); INT/UINT: [i]; NUM: [n]; STR: [s]. */
+@Serializable @SerialName("lit") class PLiteral(val kind: ArgKind, val obj: PRef?, val i: Long, val n: Double, val s: String?) : PSource()
+@Serializable @SerialName("attr") class PAttribute(val from: PSource, val classHandle: PRef?, val name: String, val kind: ArgKind) : PSource()
+@Serializable @SerialName("how") class PHow(val from: PSource) : PSource()
+@Serializable @SerialName("unbox") class PUnbox(val from: PSource, val kind: ArgKind) : PSource()
+@Serializable @SerialName("lookup") class PLookup(val table: PSource, val key: PSource) : PSource()
+@Serializable @SerialName("rstate") class PResumeState(val level: Int) : PSource()
+
+@Serializable sealed class PGuard
+@Serializable @SerialName("type") class PGuardType(val on: PSource, val type: PRef?) : PGuard()
+@Serializable @SerialName("conc") class PGuardConcreteness(val on: PSource, val concrete: Boolean) : PGuard()
+@Serializable @SerialName("lit") class PGuardLiteral(val on: PSource, val expected: PLiteral) : PGuard()
+@Serializable @SerialName("notlit") class PGuardNotLiteralObj(val on: PSource, val rejected: PRef?) : PGuard()
+/** The name alone does not name a config: [compilerSide] picks the registry
+ *  it lives in (HLLConfig.compilerSide). */
+@Serializable @SerialName("hll") class PGuardHll(val on: PSource, val hll: String?, val compilerSide: Boolean) : PGuard()
+
+@Serializable class PShape(val sources: List<PSource>, val descriptor: PDescriptor)
+
+@Serializable sealed class POutcome
+@Serializable @SerialName("value") class POutcomeValue(val source: PSource) : POutcome()
+@Serializable @SerialName("invoke") class POutcomeInvoke(val callee: PSource, val args: PShape) : POutcome()
+@Serializable @SerialName("syscall") class POutcomeSyscall(val syscall: String, val args: PShape) : POutcome()
+
+@Serializable class PResumption(val dispatcher: String, val initArgs: PShape)
+@Serializable class PLevel(val dispatcher: String, val initDescriptor: PDescriptor, val guards: List<PGuard>,
+                           val newState: PSource?, val requireNoFurther: Boolean)
+@Serializable class PBind(val failureFlag: Long, val successFlag: Long?, val onSuccessToo: Boolean)
+
+@Serializable class PProgram(
+    val descriptor: PDescriptor, val guards: List<PGuard>, val outcome: POutcome,
+    val resumptions: List<PResumption>, val resumeKind: ResumeKind, val resumeLevels: List<PLevel>,
+    val bindControl: PBind?, val bindFailure: PProgram?)
+
+@Serializable class DispatchSlot(val programs: List<PProgram>)
diff --git a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlotCodec.kt b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlotCodec.kt
new file mode 100644
index 000000000..f94010ad3
--- /dev/null
+++ b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlotCodec.kt
@@ -0,0 +1,193 @@
+package org.raku.nqp.dispatch
+
+import org.raku.nqp.runtime.CallSiteDescriptor
+import org.raku.nqp.runtime.CodeRef
+import org.raku.nqp.runtime.ThreadContext
+import org.raku.nqp.sixmodel.STable
+import org.raku.nqp.sixmodel.SerializationContext
+import org.raku.nqp.sixmodel.SixModelObject
+
+/** A reference no serialization context names; caught at the top of
+ *  persist/realise, never escapes. */
+class Unpersistable(what: String) : RuntimeException(what)
+
+/**
+ * DispatchProgram <-> PProgram. persist() returns null for a program
+ * with a reference that has no SC address (C0: 1.1 % of them; the
+ * classes are listed in the findings); realise() returns null when a
+ * persisted reference does not resolve in this process (an SC not
+ * loaded yet, an index past the table, an empty root slot), and the
+ * site then records as it always did. Both directions are total
+ * functions of their input: no state, no caching.
+ */
+object DispatchSlotCodec {
+    /* ----- to the persisted form ----- */
+
+    fun persist(p: DispatchProgram): PProgram? = try { program(p) } catch (_: Unpersistable) { null }
+
+    private fun program(p: DispatchProgram): PProgram = PProgram(
+        descriptor(p.descriptor), p.guards.map { guard(it) }, outcome(p.outcome),
+        p.resumptions.map { PResumption(it.dispatcher.id, shape(it.initArgs)) },
+        p.resumeKind,
+        p.resumeLevels.map { l ->
+            PLevel(l.dispatcher.id, descriptor(l.initDescriptor), l.guards.map { guard(it) },
+                l.newState?.let { source(it) }, l.requireNoFurther) },
+        p.bindControl?.let { PBind(it.failureFlag, it.successFlag, it.onSuccessToo) },
+        p.bindFailureProgram?.let { program(it) })
+
+    private fun descriptor(d: CallSiteDescriptor) = PDescriptor(d.argFlags.copyOf(), d.names?.toList())
+
+    private fun typeName(obj: SixModelObject): String =
+        if (obj.stInitialized) obj.st.debugName ?: "?" else "?"
+
+    /* The SC's index maps answer 0 / throw for an absent key, so every
+     * index is validated by reading the root slot back. */
+    private fun objectIndex(sc: SerializationContext, obj: SixModelObject): Int {
+        val i = sc.getObjectIndex(obj)
+        return if (i >= 0 && i < sc.objectCount() && sc.getObject(i) === obj) i else -1
+    }
+    private fun codeIndex(sc: SerializationContext, obj: SixModelObject): Int {
+        if (obj !is CodeRef) return -1
+        val i = try { sc.getCodeIndex(obj) } catch (_: NullPointerException) { -1 }
+        return if (i >= 0 && i < sc.coderefCount() && sc.getCodeRef(i) === obj) i else -1
+    }
+
+    fun ref(obj: SixModelObject?): PRef? {
+        if (obj == null) return null
+        val sc = obj.sc ?: throw Unpersistable("object of ${typeName(obj)} in no SC")
+        val oi = objectIndex(sc, obj)
+        if (oi >= 0) return PRef(sc.handle, oi, PRef.OBJ)
+        val ci = codeIndex(sc, obj)
+        if (ci >= 0) return PRef(sc.handle, ci, PRef.CODE)
+        throw Unpersistable("object of ${typeName(obj)} not in the root set of ${sc.handle}")
+    }
+
+    fun ref(st: STable?): PRef? {
+        if (st == null) return null
+        val sc = st.sc ?: throw Unpersistable("STable ${st.debugName} in no SC")
+        val i = try { sc.getSTableIndex(st) } catch (_: NullPointerException) { -1 }
+        if (i >= 0 && i < sc.stableCount() && sc.getSTable(i) === st) return PRef(sc.handle, i, PRef.STABLE)
+        throw Unpersistable("STable ${st.debugName} not in the root set of ${sc.handle}")
+    }
+
+    private fun literal(kind: ArgKind, value: Any?): PLiteral = when (kind) {
+        ArgKind.OBJ -> PLiteral(kind, ref(value as SixModelObject?), 0, 0.0, null)
+        ArgKind.INT, ArgKind.UINT -> PLiteral(kind, null, (value as Number).toLong(), 0.0, null)
+        ArgKind.NUM -> PLiteral(kind, null, 0, (value as Number).toDouble(), null)
+        ArgKind.STR -> PLiteral(kind, null, 0, 0.0, value as String?)
+    }
+
+    private fun source(s: ValueSource): PSource = when (s) {
+        is ValueSource.Arg -> PArg(s.index)
+        is ValueSource.ResumeInitArg -> PResumeInitArg(s.level, s.index)
+        is ValueSource.Literal -> literal(s.kind, s.value)
+        is ValueSource.Attribute -> PAttribute(source(s.from), ref(s.classHandle), s.name, s.kind)
+        is ValueSource.How -> PHow(source(s.from))
+        is ValueSource.Unbox -> PUnbox(source(s.from), s.kind)
+        is ValueSource.Lookup -> PLookup(source(s.table), source(s.key))
+        is ValueSource.ResumeState -> PResumeState(s.level)
+    }
+
+    private fun guard(g: Guard): PGuard = when (g) {
+        is Guard.OfType -> PGuardType(source(g.on), ref(g.type))
+        is Guard.Concreteness -> PGuardConcreteness(source(g.on), g.concrete)
+        is Guard.Literal -> PGuardLiteral(source(g.on), literal(g.expected.kind, g.expected.value))
+        is Guard.NotLiteralObj -> PGuardNotLiteralObj(source(g.on), ref(g.rejected))
+        is Guard.OfHll -> PGuardHll(source(g.on), g.hll?.name, g.hll?.compilerSide ?: false)
+    }
+
+    private fun shape(c: CaptureShape) = PShape(c.sources.map { source(it) }, descriptor(c.descriptor))
+
+    private fun outcome(o: Outcome): POutcome = when (o) {
+        is Outcome.Value -> POutcomeValue(source(o.source))
+        is Outcome.InvokeCode -> POutcomeInvoke(source(o.callee), shape(o.args))
+        is Outcome.InvokeSyscall -> POutcomeSyscall(o.syscall.name, shape(o.args))
+    }
+
+    /* ----- from the persisted form ----- */
+
+    /** [onDrop], when given, is handed the reason a program did not realise
+     *  (NQP_DISPATCH_PERSIST_TRACE reads it); the program is dropped either way. */
+    fun realise(tc: ThreadContext, p: PProgram, onDrop: ((String) -> Unit)? = null): DispatchProgram? =
+        try { program(tc, p) } catch (e: Unpersistable) { onDrop?.invoke(e.message ?: "?"); null }
+
+    private fun program(tc: ThreadContext, p: PProgram): DispatchProgram {
+        val out = DispatchProgram(descriptor(p.descriptor), p.guards.map { guard(tc, it) }, outcome(tc, p.outcome),
+            p.resumptions.map { ResumptionSpec(dispatcher(tc, it.dispatcher), shape(tc, it.initArgs)) },
+            p.resumeKind,
+            p.resumeLevels.map { l ->
+                ResumptionLevel(dispatcher(tc, l.dispatcher), descriptor(l.initDescriptor),
+                    l.guards.map { guard(tc, it) }, l.newState?.let { source(tc, it) }, l.requireNoFurther) },
+            p.bindControl?.let { BindControl(it.failureFlag, it.successFlag, it.onSuccessToo) })
+        p.bindFailure?.let { out.bindFailureProgram = program(tc, it) }
+        return out
+    }
+
+    private fun descriptor(d: PDescriptor) = CallSiteDescriptor(d.flags.copyOf(), d.names?.toTypedArray())
+
+    private fun sc(tc: ThreadContext, handle: String): SerializationContext =
+        tc.gc.scs[handle] ?: throw Unpersistable("no SC $handle")
+
+    private fun obj(tc: ThreadContext, r: PRef?): SixModelObject? {
+        if (r == null) return null
+        val sc = sc(tc, r.handle)
+        val o: SixModelObject? = when (r.kind) {
+            PRef.OBJ -> if (r.index in 0 until sc.objectCount()) sc.getObject(r.index) else null
+            PRef.CODE -> if (r.index in 0 until sc.coderefCount()) sc.getCodeRef(r.index) else null
+            else -> null
+        }
+        return o ?: throw Unpersistable("${r.handle}:${r.index} (kind ${r.kind}) is empty")
+    }
+
+    private fun stable(tc: ThreadContext, r: PRef?): STable? {
+        if (r == null) return null
+        val sc = sc(tc, r.handle)
+        if (r.kind != PRef.STABLE || r.index !in 0 until sc.stableCount())
+            throw Unpersistable("${r.handle}:${r.index} is not an STable slot")
+        return sc.getSTable(r.index) ?: throw Unpersistable("${r.handle}:${r.index} STable is empty")
+    }
+
+    private fun dispatcher(tc: ThreadContext, id: String): Dispatcher =
+        tc.gc.dispatchers.findOrNull(id) ?: throw Unpersistable("no dispatcher $id")
+
+    private fun literal(tc: ThreadContext, l: PLiteral): Any? = when (l.kind) {
+        ArgKind.OBJ -> obj(tc, l.obj)
+        ArgKind.INT, ArgKind.UINT -> l.i
+        ArgKind.NUM -> l.n
+        ArgKind.STR -> l.s
+    }
+
+    private fun source(tc: ThreadContext, s: PSource): ValueSource = when (s) {
+        is PArg -> ValueSource.Arg(s.index)
+        is PResumeInitArg -> ValueSource.ResumeInitArg(s.level, s.index)
+        is PLiteral -> ValueSource.Literal(s.kind, literal(tc, s))
+        is PAttribute -> ValueSource.Attribute(source(tc, s.from), obj(tc, s.classHandle), s.name, s.kind)
+        is PHow -> ValueSource.How(source(tc, s.from))
+        is PUnbox -> ValueSource.Unbox(source(tc, s.from), s.kind)
+        is PLookup -> ValueSource.Lookup(source(tc, s.table), source(tc, s.key))
+        is PResumeState -> ValueSource.ResumeState(s.level)
+    }
+
+    private fun guard(tc: ThreadContext, g: PGuard): Guard = when (g) {
+        is PGuardType -> Guard.OfType(source(tc, g.on), stable(tc, g.type))
+        is PGuardConcreteness -> Guard.Concreteness(source(tc, g.on), g.concrete)
+        is PGuardLiteral -> Guard.Literal(source(tc, g.on), DispatchValue(g.expected.kind, literal(tc, g.expected)))
+        is PGuardNotLiteralObj -> Guard.NotLiteralObj(source(tc, g.on), obj(tc, g.rejected))
+        /* findHLLConfig, not getHLLConfigFor: the guard compares by identity,
+         * so a config minted here -- or taken from whichever registry happens
+         * to be current -- would be a guard that can never match. */
+        is PGuardHll -> Guard.OfHll(source(tc, g.on), g.hll?.let {
+            tc.gc.findHLLConfig(it, g.compilerSide)
+                ?: throw Unpersistable("no HLL config $it (compilerSide=${g.compilerSide})") })
+    }
+
+    private fun shape(tc: ThreadContext, s: PShape) = CaptureShape(s.sources.map { source(tc, it) }, descriptor(s.descriptor))
+
+    private fun outcome(tc: ThreadContext, o: POutcome): Outcome = when (o) {
+        is POutcomeValue -> Outcome.Value(source(tc, o.source))
+        is POutcomeInvoke -> Outcome.InvokeCode(source(tc, o.callee), shape(tc, o.args))
+        is POutcomeSyscall -> Outcome.InvokeSyscall(
+            try { Syscalls.find(tc, o.syscall) } catch (e: Exception) { throw Unpersistable("no syscall ${o.syscall}") },
+            shape(tc, o.args))
+    }
+}
diff --git a/src/vm/jvm/runtime/org/raku/nqp/runtime/GlobalContext.kt b/src/vm/jvm/runtime/org/raku/nqp/runtime/GlobalContext.kt
index fd95f9d49..9ab1702af 100644
--- a/src/vm/jvm/runtime/org/raku/nqp/runtime/GlobalContext.kt
+++ b/src/vm/jvm/runtime/org/raku/nqp/runtime/GlobalContext.kt
@@ -251,20 +251,23 @@ class GlobalContext {
         try {
             out = PrintStream(System.out, true, "UTF-8")
             err = PrintStream(System.err, true, "UTF-8")
         }
         catch (e: UnsupportedEncodingException) {
             throw RuntimeException(e)
         }
 
+        /* Both registries exist before the first config is made in either:
+         * getHLLConfigFor stamps the config it creates with which registry
+         * it went into, and that comparison needs both fields set. */
         compileeHLLConfiguration = HashMap<String, HLLConfig>()
+        compilerHLLConfiguration = HashMap<String, HLLConfig>()
         hllConfiguration = compileeHLLConfiguration
         getHLLConfigFor("")
-        compilerHLLConfiguration = HashMap<String, HLLConfig>()
         hllConfiguration = compilerHLLConfiguration
         getHLLConfigFor("")
 
         scs = HashMap<String, SerializationContext>()
         scRefs = HashMap<String, SixModelObject>()
         compilerRegistry = HashMap<String, SixModelObject?>()
         hllSyms = HashMap<String, HashMap<String, SixModelObject?>>()
 
@@ -296,23 +299,37 @@ class GlobalContext {
      * Gets HLL configuration object for the specified language.
      */
     fun getHLLConfigFor(language: String): HLLConfig {
         synchronized(hllConfiguration) {
             var config = hllConfiguration.get(language)
             if (config == null) {
                 config = HLLConfig()
                 config.name = language
+                config.compilerSide = hllConfiguration === compilerHLLConfiguration
                 setupConfig(config)
                 hllConfiguration.put(language, config)
             }
             return config
         }
     }
 
+    /**
+     * The config for a language in the named registry, without creating one:
+     * what a persisted reference to an HLL config resolves through, so that
+     * an unknown name answers null rather than minting a config no type is
+     * owned by (which would leave a dispatch guard that can never match).
+     */
+    fun findHLLConfig(language: String, compilerSide: Boolean): HLLConfig? {
+        val registry = if (compilerSide) compilerHLLConfiguration else compileeHLLConfiguration
+        synchronized(registry) {
+            return registry.get(language)
+        }
+    }
+
     private fun setupConfig(config: HLLConfig) {
         config.intBoxType = BOOTInt
         config.numBoxType = BOOTNum
         config.strBoxType = BOOTStr
         config.listType = BOOTArray
         config.hashType = BOOTHash
         config.slurpyArrayType = BOOTArray
         config.slurpyHashType = BOOTHash
diff --git a/src/vm/jvm/runtime/org/raku/nqp/runtime/HLLConfig.kt b/src/vm/jvm/runtime/org/raku/nqp/runtime/HLLConfig.kt
index 40420af68..55533c02b 100644
--- a/src/vm/jvm/runtime/org/raku/nqp/runtime/HLLConfig.kt
+++ b/src/vm/jvm/runtime/org/raku/nqp/runtime/HLLConfig.kt
@@ -19,16 +19,26 @@ class HLLConfig {
         const val ROLE_ARRAY = 4
         const val ROLE_HASH = 5
         const val ROLE_CODE = 6
     }
 
     /** HLL name. */
     @JvmField var name: String? = null
 
+    /**
+     * Which of the global context's two registries this config was created
+     * in: the compiler-side one, or the compilee-side one. A name alone does
+     * not identify a config -- both registries hold a config per name, and
+     * which one a type's hllOwner points at is decided by whichever registry
+     * was current when it was deserialized -- so a persisted dispatch program
+     * carries this flag alongside the name (GlobalContext.findHLLConfig).
+     */
+    @JvmField var compilerSide: Boolean = false
+
     /** The types the languages wish to get things boxed as. */
     @JvmField var intBoxType: SixModelObject? = null
     @JvmField var uintBoxType: SixModelObject? = null
     @JvmField var numBoxType: SixModelObject? = null
     @JvmField var strBoxType: SixModelObject? = null
 
     /** The type to use for nqp::list(...) */
     @JvmField var listType: SixModelObject? = null
diff --git a/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt b/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt
index e271bfe0d..08f45f5b5 100644
--- a/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt
+++ b/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt
@@ -156,16 +156,19 @@ class ProgramUnit(@JvmField val store: UnitStore) : CompilationUnit() {
             val sc = gc.scs.get(v.scHandle)
                 ?: throw IllegalStateException("unit ${header.unitId}: static lexical ${v.name} of block ${sci.methodName} names unknown SC ${v.scHandle}")
             sci.rawSetOLexStatic(idx, sc.getObject(v.scIdx), v.flags.toByte())
         }
     }
 
     override fun initializeCompilationUnit(tc: ThreadContext, runDeserialize: Boolean) {
         gc = tc.gc
+        /* A site of this unit's programs finds its dispatch slot through the
+         * namespace, so the store has to be reachable by it (Phase C). */
+        identityNamespace()?.let { org.raku.nqp.dispatch.DispatchPersist.register(it, store) }
         UnitLoadStats.time(header.unitId, "shells", { "blocks=${store.blockCount}" }) {
             buildTable(tc.gc.BOOTCode?.st)
         }
         hllConfig = tc.gc.getHLLConfigFor(hllName())
         if (runDeserialize) runDeserializeIfAvailable(tc)
     }
 
     override fun runDeserializeIfAvailable(tc: ThreadContext) {
diff --git a/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitCodec.kt b/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitCodec.kt
index 6879e34b3..0a8f50ed9 100644
--- a/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitCodec.kt
+++ b/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitCodec.kt
@@ -12,21 +12,22 @@ import kotlinx.serialization.encoding.AbstractDecoder
 import kotlinx.serialization.encoding.AbstractEncoder
 import kotlinx.serialization.encoding.CompositeDecoder
 import kotlinx.serialization.encoding.CompositeEncoder
 import kotlinx.serialization.modules.EmptySerializersModule
 import kotlinx.serialization.modules.SerializersModule
 
 /**
  * The unit artifact's record codec: kotlinx.serialization records over a
- * binary layout of our own. Fixed-width little-endian ints, a byte per
- * boolean, an Int byte length before UTF-8 text, a mark byte before a
- * nullable value, an Int size before a collection; no field tags. A
- * record therefore decodes from a slice that starts at its first byte,
- * which is what unit.index's (offset, length) tables address.
+ * binary layout of our own. Fixed-width little-endian ints, a Double as
+ * its raw bits, a byte per boolean, an Int byte length before UTF-8 text,
+ * a mark byte before a nullable value, an Int size before a collection;
+ * no field tags. A record therefore decodes from a slice that starts at
+ * its first byte, which is what unit.index's (offset, length) tables
+ * address.
  *
  * AbstractEncoder/AbstractDecoder are kotlinx's experimental surface for
  * a custom format; nothing else experimental is used, and the format
  * modules (ProtoBuf, CBOR) stay out (milestone 7 Phase B, ruling 11).
  */
 @OptIn(ExperimentalSerializationApi::class)
 object UnitCodec {
     fun <T> encode(serializer: SerializationStrategy<T>, value: T): ByteArray {
@@ -47,17 +48,17 @@ object UnitCodec {
         private fun int(v: Int) { scratch.clear(); scratch.putInt(v); out.write(scratch.array(), 0, 4) }
         override fun encodeInt(value: Int) = int(value)
         override fun encodeLong(value: Long) { scratch.clear(); scratch.putLong(value); out.write(scratch.array(), 0, 8) }
         override fun encodeBoolean(value: Boolean) = out.write(if (value) 1 else 0)
         override fun encodeByte(value: Byte) = out.write(value.toInt())
         override fun encodeShort(value: Short) = throw UnsupportedOperationException("unit codec: no Short")
         override fun encodeChar(value: Char) = throw UnsupportedOperationException("unit codec: no Char")
         override fun encodeFloat(value: Float) = throw UnsupportedOperationException("unit codec: no Float")
-        override fun encodeDouble(value: Double) = throw UnsupportedOperationException("unit codec: no Double")
+        override fun encodeDouble(value: Double) = encodeLong(value.toRawBits())
         override fun encodeString(value: String) {
             val b = value.toByteArray(StandardCharsets.UTF_8); int(b.size); out.write(b, 0, b.size)
         }
         override fun encodeEnum(enumDescriptor: SerialDescriptor, index: Int) = int(index)
         override fun encodeNull() = out.write(0)
         override fun encodeNotNullMark() = out.write(1)
         override fun beginCollection(descriptor: SerialDescriptor, collectionSize: Int): CompositeEncoder {
             int(collectionSize); return this
@@ -70,17 +71,17 @@ object UnitCodec {
 
         override fun decodeInt(): Int = buf.getInt()
         override fun decodeLong(): Long = buf.getLong()
         override fun decodeBoolean(): Boolean = buf.get() != 0.toByte()
         override fun decodeByte(): Byte = buf.get()
         override fun decodeShort(): Short = throw UnsupportedOperationException("unit codec: no Short")
         override fun decodeChar(): Char = throw UnsupportedOperationException("unit codec: no Char")
         override fun decodeFloat(): Float = throw UnsupportedOperationException("unit codec: no Float")
-        override fun decodeDouble(): Double = throw UnsupportedOperationException("unit codec: no Double")
+        override fun decodeDouble(): Double = Double.fromBits(buf.getLong())
         override fun decodeString(): String {
             val n = buf.getInt()
             val slice = buf.slice(buf.position(), n)
             buf.position(buf.position() + n)
             return StandardCharsets.UTF_8.decode(slice).toString()
         }
         override fun decodeEnum(enumDescriptor: SerialDescriptor): Int = buf.getInt()
         override fun decodeNotNullMark(): Boolean = buf.get() != 0.toByte()
diff --git a/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitDispatchWriter.kt b/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitDispatchWriter.kt
new file mode 100644
index 000000000..beb6b9e76
--- /dev/null
+++ b/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitDispatchWriter.kt
@@ -0,0 +1,84 @@
+package org.raku.nqp.runtime.unit
+
+import java.io.ByteArrayOutputStream
+import java.io.File
+import java.nio.ByteBuffer
+import java.nio.ByteOrder
+import java.nio.file.Files
+import java.nio.file.StandardCopyOption
+import java.util.zip.ZipOutputStream
+
+/**
+ * Rewrites the dispatch slots of a unit artifact in place (milestone 7
+ * Phase C, the training run): for every unit in the file whose entry
+ * prefix is named ("unit", "nested/<id>"), the named slots get their
+ * bytes, every other slot keeps what it had, the .index slot rows are
+ * repointed and the .dispatch entry rebuilt; every other entry is copied
+ * byte for byte. The result goes to <path>.tmp and is renamed over the
+ * original, so a process that has the old file mapped keeps reading the
+ * old inode.
+ */
+object UnitDispatchWriter {
+    fun rewrite(path: String, slots: Map<String, Map<Int, ByteArray>>) {
+        val file = File(path)
+        val whole = ByteBuffer.wrap(file.readBytes()).order(ByteOrder.LITTLE_ENDIAN)
+        val dir = ZipDirectory.read(whole, path)
+        val patched = HashMap<String, Pair<ByteArray, ByteArray>>()   // prefix -> (index, dispatch)
+        for ((prefix, newSlots) in slots) {
+            val index = dir["$prefix.index"] ?: throw IllegalArgumentException("$path: no $prefix.index entry to patch")
+            val dispatch = dir["$prefix.dispatch"] ?: throw IllegalArgumentException("$path: no $prefix.dispatch entry to patch")
+            patched[prefix] = patch(path, prefix, whole.slice(index.offset, index.size).order(ByteOrder.LITTLE_ENDIAN),
+                whole.slice(dispatch.offset, dispatch.size), newSlots)
+        }
+        val out = ByteArrayOutputStream(whole.capacity() + (1 shl 16))
+        ZipOutputStream(out).use { z ->
+            z.setMethod(ZipOutputStream.STORED)
+            for ((name, e) in dir) {
+                val prefix = when {
+                    name.endsWith(".index") -> name.removeSuffix(".index")
+                    name.endsWith(".dispatch") -> name.removeSuffix(".dispatch")
+                    else -> null
+                }
+                val p = prefix?.let { patched[it] }
+                val bytes = when {
+                    p != null && name.endsWith(".index") -> p.first
+                    p != null -> p.second
+                    else -> ByteArray(e.size).also { whole.slice(e.offset, e.size).get(it) }
+                }
+                UnitImageWriter.put(z, name, bytes)
+            }
+        }
+        val tmp = File(path + ".tmp")
+        tmp.writeBytes(out.toByteArray())
+        Files.move(tmp.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
+    }
+
+    /** The new (index, dispatch) of one unit: fixed-width slot rows in the
+     *  index repointed into a dispatch entry rebuilt slot by slot. */
+    private fun patch(path: String, prefix: String, index: ByteBuffer, oldDispatch: ByteBuffer,
+                      newSlots: Map<Int, ByteArray>): Pair<ByteArray, ByteArray> {
+        val headerLen = index.getInt(8)
+        val header = UnitCodec.decode(UnitHeader.serializer(), index.slice(12, headerLen))
+        val slotTable = 12 + headerLen + 16 * header.blockCount + 16 * header.programCount
+        val n = header.dispatchSlotCount
+        for (s in newSlots.keys) require(s in 0 until n) { "$path: $prefix dispatch slot $s of $n" }
+        val bytes = ByteArray(index.remaining()).also { index.duplicate().get(it) }
+        val idx = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
+        val dispatch = ByteArrayOutputStream(oldDispatch.remaining() + newSlots.values.sumOf { it.size })
+        for (s in 0 until n) {
+            val row = slotTable + 8 * s
+            val slot = newSlots[s] ?: run {
+                val off = idx.getInt(row); val len = idx.getInt(row + 4)
+                if (len == 0) null
+                else {
+                    require(off >= 0 && off + len <= oldDispatch.remaining()) { "$path: $prefix dispatch slot $s at $off+$len past ${oldDispatch.remaining()}" }
+                    ByteArray(len).also { oldDispatch.slice(off, len).get(it) }
+                }
+            }
+            if (slot == null) { idx.putInt(row, 0); idx.putInt(row + 4, 0); continue }
+            idx.putInt(row, dispatch.size()); idx.putInt(row + 4, slot.size)
+            dispatch.write(slot)
+        }
+        return bytes to dispatch.toByteArray()
+    }
+}
diff --git a/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitImageWriter.kt b/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitImageWriter.kt
index cd8d57fca..baea8d991 100644
--- a/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitImageWriter.kt
+++ b/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitImageWriter.kt
@@ -30,17 +30,19 @@ object UnitImageWriter {
                     val entry = n.entry("unit$suffix")
                         ?: throw IllegalStateException("unit ${image.unitId}: nested unit $id carries no unit$suffix")
                     put(z, UnitStore.NESTED_DIR + id + suffix, ByteArray(entry.remaining()).also { entry.duplicate().get(it) })
                 }
             }
         }
     }
 
-    private fun put(z: ZipOutputStream, name: String, bytes: ByteArray) {
+    /** internal, not private: UnitDispatchWriter rebuilds an artifact entry
+     *  by entry and must store them exactly as this writer first did. */
+    internal fun put(z: ZipOutputStream, name: String, bytes: ByteArray) {
         val entry = ZipEntry(name)
         entry.method = ZipEntry.STORED
         entry.size = bytes.size.toLong(); entry.compressedSize = bytes.size.toLong()
         entry.crc = CRC32().also { it.update(bytes) }.value
         z.putNextEntry(entry); z.write(bytes); z.closeEntry()
     }
 
     private class Encoded(val index: ByteArray, val records: ByteArray, val programs: ByteArray, val dispatch: ByteArray)
diff --git a/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitStore.kt b/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitStore.kt
index 8d647e4c2..70584e3e0 100644
--- a/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitStore.kt
+++ b/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitStore.kt
@@ -81,16 +81,24 @@ class UnitStore private constructor(
         val headerLen = index.getInt(8)
         header = try { UnitCodec.decode(UnitHeader.serializer(), index.slice(12, headerLen)) }
                  catch (e: Exception) { throw IllegalStateException("unit artifact $name: header does not decode: ${e.message}", e) }
         tables = 12 + headerLen
         programTable = tables + 16 * header.blockCount
         slotTable = programTable + 16 * header.programCount
         val need = slotTable + 8 * header.dispatchSlotCount
         if (index.remaining() < need) throw IllegalStateException("unit artifact $name: $prefix.index holds ${index.remaining()} bytes, tables need $need")
+        /* Every program's slot window must land inside the slot table: a
+         * rewriter that mispointed one would otherwise hand out another
+         * program's persisted programs at a miss. */
+        for (i in 0 until header.programCount) {
+            val first = index.getInt(programTable + 16 * i + 8); val count = index.getInt(programTable + 16 * i + 12)
+            if (first < 0 || count < 0 || first + count > header.dispatchSlotCount)
+                throw IllegalStateException("unit artifact $name: program $i claims dispatch slots $first+$count of ${header.dispatchSlotCount}")
+        }
         if (header.names.size != header.blockCount || header.cuids.size != header.blockCount)
             throw IllegalStateException("unit artifact $name: ${header.names.size} names / ${header.cuids.size} cuids for ${header.blockCount} blocks")
         if (header.serializedCodeRefCount > header.blockCount)
             throw IllegalStateException("unit ${header.unitId}: ${header.serializedCodeRefCount} serialized code refs, table of ${header.blockCount}")
     }
 
     val blockCount: Int get() = header.blockCount
     val programCount: Int get() = header.programCount
@@ -124,25 +132,36 @@ class UnitStore private constructor(
         val programs = entry(PROGRAMS) ?: throw IllegalStateException("unit ${header.unitId}: no $prefix.programs entry")
         if (off + len > programs.remaining())
             throw IllegalStateException("unit ${header.unitId}: $prefix.programs index $idx at $off+$len past ${programs.remaining()}")
         return StandardCharsets.UTF_8.decode(programs.slice(off, len)).toString()
     }
 
     fun dispatchSlotCount(programIndex: Int): Int =
         if (programIndex < 0 || programIndex >= header.programCount) 0 else programRow(programIndex, 3)
-    fun dispatchSlot(programIndex: Int, ordinal: Int): ByteBuffer? {
-        if (programIndex < 0 || programIndex >= header.programCount) return null
-        if (ordinal < 0 || ordinal >= programRow(programIndex, 3)) return null
+
+    /** "unit" or "nested/<id>": the entry-name prefix this store reads, for the writer. */
+    val entryPrefix: String get() = prefix
+
+    /** The absolute slot index of (program, ordinal) in this unit's table, or -1. */
+    fun absoluteSlot(programIndex: Int, ordinal: Int): Int {
+        if (programIndex < 0 || programIndex >= header.programCount) return -1
+        if (ordinal < 0 || ordinal >= programRow(programIndex, 3)) return -1
         val slot = programRow(programIndex, 2) + ordinal
+        return if (slot in 0 until header.dispatchSlotCount) slot else -1
+    }
+
+    fun dispatchSlot(programIndex: Int, ordinal: Int): ByteBuffer? {
+        val slot = absoluteSlot(programIndex, ordinal)
+        if (slot < 0) return null
         val len = index.getInt(slotTable + 8 * slot + 4)
         if (len == 0) return null
         val off = index.getInt(slotTable + 8 * slot)
         val dispatch = entry(DISPATCH) ?: throw IllegalStateException("unit ${header.unitId}: no $prefix.dispatch entry")
-        if (off + len > dispatch.remaining())
+        if (off < 0 || off + len > dispatch.remaining())
             throw IllegalStateException("unit ${header.unitId}: $prefix.dispatch slot $slot at $off+$len past ${dispatch.remaining()}")
         return dispatch.slice(off, len).order(ByteOrder.LITTLE_ENDIAN)
     }
 
     val serialized: ByteBuffer? get() = entry(SERIALIZED)
 
     /** A raw entry of this unit (unit.index ... unit.dispatch), a fresh
      *  duplicate at position 0. */
diff --git a/tools/build/dispatch-dump-diff.raku b/tools/build/dispatch-dump-diff.raku
new file mode 100644
index 0000000000..23e4a45f5d
--- /dev/null
+++ b/tools/build/dispatch-dump-diff.raku
@@ -0,0 +1,124 @@
+#!/usr/bin/env raku
+# Milestone 7 Phase C, C0: size the persisted miss from NQP_DISPATCH_DUMP files.
+#
+#   raku tools/build/dispatch-dump-diff.raku run1.dump [run2.dump] [--stats=run1.out]
+#
+# A dump (DispatchDump.kt in nqp-runtime) has one `site <identity|anon>
+# <dispatcher> <programs>[ indy]` line per registered callsite and one
+# `prog <n> <normalised text>` line per installed program, every reference
+# named by its serialization context or marked NP(...) when it has none.
+# Reported per dispatcher: sites that recorded, programs, persistable
+# programs (no NP), and -- with a second dump -- programs whose text also
+# stands at the same site identity in the other run. --stats adds the
+# misses-by-dispatcher histogram from a `dispatch stats:` capture so the
+# expected remaining recordings can be read off the same table.
+use v6.d;
+my %*SUB-MAIN-OPTS = :named-anywhere;
+
+class Site {
+    has Str $.identity;
+    has Str $.dispatcher;
+    has Bool $.indy;
+    has @.programs;
+}
+
+sub parse-dump(IO() $file) {
+    my @sites;
+    my Site $cur;
+    for $file.lines {
+        if .starts-with('site ') {
+            my @f = .split(' ');
+            $cur = Site.new(:identity(@f[1]), :dispatcher(@f[2]),
+                :indy(@f.elems > 4 && @f[4] eq 'indy'));
+            @sites.push($cur);
+        }
+        elsif .starts-with('prog ') {
+            die "prog line before any site line in $file" without $cur;
+            $cur.programs.push(.subst(/^ 'prog ' \d+ ' '/, ''));
+        }
+    }
+    @sites
+}
+
+sub parse-stats(IO() $file) {
+    my %misses;
+    for $file.lines {
+        %misses{$1} = +$0 if / ^ '  misses ' (\d+) ' ' (\S+) /;
+    }
+    %misses
+}
+
+sub np-causes(Str $text) {
+    $text.comb(/ 'NP(' <-[)]>* ')' /).map({ .subst(/ ':' \d+ $ /, '') }).unique
+}
+
+sub MAIN(IO() $a, IO() $b?, Str :$stats) {
+    my @a = parse-dump($a);
+    my %b-texts;   # identity -> set of program texts, from the second dump
+    my %b-count;
+    if $b {
+        for parse-dump($b) -> $s {
+            next if $s.identity eq 'anon';
+            %b-texts{$s.identity} = set $s.programs;
+            %b-count{$s.dispatcher}<sites>++ if $s.programs;
+            %b-count{$s.dispatcher}<programs> += $s.programs.elems;
+        }
+    }
+    my %misses = $stats ?? parse-stats($stats) !! ();
+
+    my %by;         # dispatcher -> counts
+    my %causes;     # NP cause -> programs carrying it
+    my %cause-by;   # dispatcher -> NP cause -> programs
+    my $anon-sites = 0;
+    my $anon-programs = 0;
+    my $silent = 0; # parsed, never dispatched
+    for @a -> $s {
+        if !$s.programs { $silent++; next }
+        if $s.identity eq 'anon' { $anon-sites++; $anon-programs += $s.programs.elems }
+        my $d = %by{$s.dispatcher} //= {};
+        $d<sites>++;
+        $d<sites-clean>++ unless $s.programs.first(*.contains('NP('));
+        for $s.programs -> $p {
+            $d<programs>++;
+            my @np = np-causes($p);
+            if @np {
+                $d<np>++;
+                for @np { %causes{$_}++; %cause-by{$s.dispatcher}{$_}++ }
+            }
+            if $b && $s.identity ne 'anon' {
+                $d<same>++ if %b-texts{$s.identity} && $p (elem) %b-texts{$s.identity};
+            }
+        }
+    }
+
+    my @cols = <dispatcher sites programs persistable unpersistable>;
+    @cols.push('same-in-B') if $b;
+    @cols.push('misses') if $stats;
+    say '| ' ~ @cols.join(' | ') ~ ' |';
+    say '|' ~ ('---|' xx @cols).join;
+    my %tot;
+    for %by.sort(-*.value<programs>) -> (:key($name), :value($d)) {
+        my @row = $name, $d<sites>, $d<programs>, $d<programs> - ($d<np> // 0), $d<np> // 0;
+        @row.push($d<same> // 0) if $b;
+        @row.push(%misses{$name} // '-') if $stats;
+        say '| ' ~ @row.join(' | ') ~ ' |';
+        %tot<sites> += $d<sites>; %tot<programs> += $d<programs>;
+        %tot<np> += $d<np> // 0; %tot<same> += $d<same> // 0;
+        %tot<misses> += %misses{$name} // 0;
+    }
+    my @row = 'total', %tot<sites>, %tot<programs>, %tot<programs> - %tot<np>, %tot<np>;
+    @row.push(%tot<same>) if $b;
+    @row.push(%tot<misses>) if $stats;
+    say '| ' ~ @row.join(' | ') ~ ' |';
+    say '';
+    printf "persistable programs: %d of %d (%.1f%%)\n",
+        %tot<programs> - %tot<np>, %tot<programs>, 100 * (%tot<programs> - %tot<np>) / %tot<programs>;
+    printf "identical at the same site in B: %d of %d (%.1f%%)\n",
+        %tot<same>, %tot<programs> - $anon-programs, 100 * %tot<same> / (%tot<programs> - $anon-programs) if $b;
+    say "sites parsed but never dispatched: $silent; anonymous sites with programs: $anon-sites ($anon-programs programs)";
+    say '';
+    say 'unpersistable causes (programs carrying each):';
+    for %causes.sort(-*.value) -> (:key($c), :value($n)) {
+        say "  $n  $c  [" ~ %cause-by.grep(*.value{$c}).map({ .key ~ '=' ~ .value{$c} }).join(' ') ~ ']';
+    }
+}
diff --git a/tools/build/m7-rig.raku b/tools/build/m7-rig.raku
index 12fa79f6c7..659f0b7a4b 100755
--- a/tools/build/m7-rig.raku
+++ b/tools/build/m7-rig.raku
@@ -52,25 +52,31 @@ sub rmtree(IO::Path $d) {
     $d.rmdir
 }
 
 sub parse-cold(Str $text) {
     my %r = :stage-lines(+$text.lines.grep(*.starts-with('unit-load '))), :by{};
     if $text ~~ / 'dispatch stats: hits=' (\d+) ' misses=' (\d+) / {
         %r<hits> = +$0; %r<misses> = +$1;
     }
+    # Phase C's two counters. Optional: a capture from before Phase C has
+    # neither, and the row line must stay comparable across the whole series,
+    # so they are summary-only and never enter the row.
+    %r<restored> = +$0 if $text ~~ / ' restored=' (\d+) /;
+    %r<recorded> = +$0 if $text ~~ / ' recorded=' (\d+) /;
     for $text.lines {
         %r<by>{$1} = +$0 if / ^ '  misses ' (\d+) ' ' (\S+) /;
     }
     %r
 }
 
 sub cold-summary(%r) {
     my @top = %r<by>.sort(-*.value).head(8).map({ .key ~ '=' ~ .value });
-    "hits={%r<hits> // '-'} misses={%r<misses> // '-'} stage-lines={%r<stage-lines>} top: @top.join(' ')"
+    "hits={%r<hits> // '-'} misses={%r<misses> // '-'} restored={%r<restored> // '-'} recorded={%r<recorded> // '-'} "
+      ~ "stage-lines={%r<stage-lines>} top: @top.join(' ')"
 }
 
 sub parse-sweep(Str $text, IO() $baseline) {
     my %base = $baseline.lines.grep(*.starts-with('t/')).map(* => True);
     my $warm = $text ~~ / (\d+) ' files in ' (\d+) 's across' / ?? +$1 !! Int;
     # t/harness5's Test Summary Report also lists a file that merely had TODO
     # passes -- 'Failed: 0' with a '  TODO passed:' line under it. That is not
     # a red. A 'Failed: 0' under '  Parse errors:' (a file that produced no
diff --git a/tools/templates/jvm/Makefile.in b/tools/templates/jvm/Makefile.in
index bcf731ebb6..8a8977c935 100644
--- a/tools/templates/jvm/Makefile.in
+++ b/tools/templates/jvm/Makefile.in
@@ -151,17 +151,47 @@ $(RUNTIME_JAR): $(RUNTIME_SOURCES) @nfp(rakudo-runtime/build.gradle.kts)@ | $(NQ
 
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
+# positive marker (a run that wrote nothing fails the build). The run writes
+# to the log and the log is shown afterwards, rather than piped through tee:
+# make gives each recipe line a plain sh with no pipefail, so a pipeline
+# would report tee's status and a trainer that died PART WAY -- after some
+# artifacts were rewritten, which the grep cannot tell apart from a whole
+# run -- would leave a half-trained build behind, green.
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
+	$(NOECHO)NQP_DISPATCH_RECORD=all @bpm(RUN_RAKUDO)@ -e '' > @nfpq(@bpm(BLIB)@/.dispatch-train.log)@ 2>&1 || { cat @nfpq(@bpm(BLIB)@/.dispatch-train.log)@; exit 1; }
+	$(NOECHO)cat @nfpq(@bpm(BLIB)@/.dispatch-train.log)@
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
 
