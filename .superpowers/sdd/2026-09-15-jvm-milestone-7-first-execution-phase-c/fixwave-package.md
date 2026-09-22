diff --git a/build.gradle.kts b/build.gradle.kts
index 06dd8a1ee..0299af224 100644
--- a/build.gradle.kts
+++ b/build.gradle.kts
@@ -277,16 +277,24 @@ val stage2 = registerStage(2, jvmDir.dir("stage1").asFile, stage1.values)
  * so stage0 stays empty-tabled. */
 val stage2TrainedDir = jvmDir.dir("stage2-trained")
 val stage2Trained = tasks.register<Sync>("stage2Trained") {
     group = "nqp jvm"
     description = "Copies the stage2 jars for dispatch training"
     stageTargets.forEach { from(jvmDir.dir("stage2").file(it.jar)) }
     into(stage2TrainedDir)
     stage2.values.forEach { dependsOn(it) }
+    // Always out of date, for the same reason trainDispatch is: the task
+    // that follows this one REWRITES these copies, so up-to-date checking
+    // cannot describe the pair. The copy has to be restored from stage2
+    // every build, or each training run would start from the last one's
+    // output and compound onto it instead of training fresh jars. (Until
+    // the marker file moved out of this directory, the stray file made the
+    // Sync out of date by accident; that is now said rather than inherited.)
+    outputs.upToDateWhen { false }
 }
 
 // Tees the training run's stderr: the build log goes on showing it while
 // doLast turns the same text into the marker file. (commons-io's
 // TeeOutputStream is not on the build script's class path here.)
 val trainDispatchLog = ByteArrayOutputStream()
 val trainDispatchTee = object : OutputStream() {
     override fun write(b: Int) {
@@ -304,39 +312,58 @@ val trainDispatchTee = object : OutputStream() {
         trainDispatchLog.flush()
     }
 }
 
 val trainDispatch = tasks.register<JavaExec>("trainDispatch") {
     group = "nqp jvm"
     description = "Runs the trivial program with NQP_DISPATCH_RECORD=all against the stage2 copy, filling its dispatch slots"
     dependsOn(stage2Trained, ":nqp-runtime:jar", ":nqp-truffle:jar", "syncTruffleModules")
-    val marker = stage2TrainedDir.file("dispatch-trained.txt").asFile
+    // Outside the synced directory: the marker is this task's only declared
+    // output, and the jars it rewrites are its INPUTS. A marker inside
+    // stage2TrainedDir would overlap stage2Trained's output directory, which
+    // is Gradle's business, not ours.
+    val marker = jvmDir.file("dispatch-trained.txt").asFile
     inputs.files(stageTargets.map { stage2TrainedDir.file(it.jar) })
     inputs.file(runtimeJarFile)
     outputs.file(marker)
+    // INTENTIONALLY always out of date. The task rewrites the very jars it
+    // declares as inputs, so up-to-date checking cannot describe it: every
+    // build's Sync restores the untrained jars and this run trains them
+    // again, which is what we want -- each build trains from FRESH jars
+    // rather than compounding one training run onto the last.
+    outputs.upToDateWhen { false }
     javaLauncher = javaToolchains.launcherFor { languageVersion = JavaLanguageVersion.of(toolchainVersion) }
     workingDir = projectDir
     mainClass = "org.raku.nqp.runtime.unit.UnitMain"
-    // Class-path input snapshot only; the real class path is set in doFirst.
-    classpath = files(stage2TrainedDir, engineJarFile)
+    // The engine jar alone here: this is the configuration-time class path,
+    // whose only job is the input snapshot, and it must NOT name
+    // stage2TrainedDir -- the directory this task modifies. The real class
+    // path is built in doFirst.
+    classpath = files(engineJarFile)
     environment("NQP_DISPATCH_RECORD", "all")
     errorOutput = trainDispatchTee
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
         val text = trainDispatchLog.toString(Charsets.UTF_8)
-        check(text.contains("dispatch-record: wrote")) { "trainDispatch: no 'dispatch-record: wrote' line -- the training run recorded nothing" }
+        // The recorder ends every run with `done`, and contains its own
+        // failures as FAILED lines rather than dying: a run that rewrote
+        // some artifacts and then threw would otherwise satisfy a
+        // per-artifact marker and leave a half-trained build behind, green.
+        check(text.contains("dispatch-record: done") && !text.contains("dispatch-record: FAILED")) {
+            "trainDispatch: the training run did not finish cleanly -- no 'dispatch-record: done' line, or a 'dispatch-record: FAILED' one"
+        }
         marker.writeText(text.lines().filter { it.startsWith("dispatch-record:") }.joinToString("\n") + "\n")
     }
 }
 
 val syncRuntimeJars = tasks.register<Sync>("syncRuntimeJars") {
     from(nqpThirdParty)
     from(runtimeJarFile)
     // The engine sits here with the rest of the runtime, but the runner puts
diff --git a/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchPersistTest.kt b/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchPersistTest.kt
index e9dcf0609..294194267 100644
--- a/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchPersistTest.kt
+++ b/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchPersistTest.kt
@@ -1,17 +1,19 @@
 package org.raku.nqp.dispatch
 
 import java.io.ByteArrayOutputStream
+import java.io.File
 import java.io.PrintStream
 import java.lang.invoke.MethodType
 import java.nio.ByteBuffer
 import java.nio.charset.StandardCharsets
 import kotlin.test.Test
 import kotlin.test.assertEquals
+import kotlin.test.assertNotNull
 import kotlin.test.assertTrue
 import org.raku.nqp.runtime.CallSiteDescriptor
 import org.raku.nqp.runtime.unit.ProgramUnitTestSupport
 import org.raku.nqp.runtime.unit.UnitCodec
 import org.raku.nqp.runtime.unit.UnitImage
 import org.raku.nqp.runtime.unit.UnitImageWriter
 import org.raku.nqp.runtime.unit.UnitStore
 
@@ -26,33 +28,100 @@ class DispatchPersistTest {
     }
 
     @Test fun restoreRealisesTheSlotsProgramsAndCountsThem() {
         val tc = ProgramUnitTestSupport.tc()
         val knowhow = tc.gc.KnowHOW!!
         val csd = CallSiteDescriptor(byteArrayOf(CallSiteDescriptor.ARG_OBJ), null)
         val p = DispatchProgram(csd, listOf(Guard.OfType(ValueSource.Arg(0), knowhow.st)),
             Outcome.Value(ValueSource.Arg(0)), emptyList(), ResumeKind.NONE, emptyList(), null)
-        val bytes = UnitCodec.encode(DispatchSlot.serializer(), DispatchSlot(listOf(DispatchSlotCodec.persist(p)!!)))
+        val bytes = UnitCodec.encode(DispatchSlot.serializer(),
+            DispatchSlot(DispatchSlot.SCHEMA, listOf(DispatchSlotCodec.persist(p)!!)))
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
 
+    /** A slot written by another schema is not decoded at all: UnitCodec is
+     *  untagged and fixed-width, so the bytes of an older layout would read
+     *  as a plausible program rather than fail. */
+    @Test fun aSlotOfAnotherSchemaIsTreatedAsEmpty() {
+        val tc = ProgramUnitTestSupport.tc()
+        val knowhow = tc.gc.KnowHOW!!
+        val csd = CallSiteDescriptor(byteArrayOf(CallSiteDescriptor.ARG_OBJ), null)
+        val p = DispatchProgram(csd, listOf(Guard.OfType(ValueSource.Arg(0), knowhow.st)),
+            Outcome.Value(ValueSource.Arg(0)), emptyList(), ResumeKind.NONE, emptyList(), null)
+        val bytes = UnitCodec.encode(DispatchSlot.serializer(),
+            DispatchSlot(DispatchSlot.SCHEMA + 1, listOf(DispatchSlotCodec.persist(p)!!)))
+        val ns = "/x/fixture.jar!unit-stale"
+        DispatchPersist.register(ns, storeWith(bytes))
+        val site = DispatchCallSite(MethodType.methodType(Void.TYPE))
+        site.unitNamespace = ns; site.programIndex = 0; site.ordinal = 1
+        val stale = DispatchPersist.staleSchema.get()
+        val restored = DispatchPersist.restored.get()
+        assertTrue(DispatchPersist.restore(tc, site).isEmpty(), "a stale slot restores nothing")
+        assertEquals(stale + 1, DispatchPersist.staleSchema.get())
+        assertEquals(restored, DispatchPersist.restored.get(), "and is not counted as restored")
+    }
+
+    /**
+     * The recorder, end to end: a live site with an installed program, its
+     * store registered, rewrites the artifact on disk -- and the program
+     * reads back out of the file. Everything below this (the codec, the
+     * writer) has its own test; what only this one covers is the hook's own
+     * road from DispatchBootstrap.sites() to a file, and the marker lines
+     * both builds gate on.
+     */
+    @Test fun recordAtExitWritesTheInstalledProgramsIntoTheArtifact() {
+        val tc = ProgramUnitTestSupport.tc()
+        val knowhow = tc.gc.KnowHOW!!
+        val f = File.createTempFile("unit-record-", ".jar"); f.deleteOnExit()
+        f.writeBytes(UnitImageWriter.bytes(ProgramUnitTestSupport.image()))
+        val ns = f.path + "!unit-record-" + System.nanoTime()
+        DispatchPersist.register(ns, UnitStore.open(f.path))
+        val csd = CallSiteDescriptor(byteArrayOf(CallSiteDescriptor.ARG_OBJ), null)
+        val p = DispatchProgram(csd, listOf(Guard.OfType(ValueSource.Arg(0), knowhow.st)),
+            Outcome.Value(ValueSource.Arg(0)), emptyList(), ResumeKind.NONE, emptyList(), null)
+        val site = DispatchCallSite(MethodType.methodType(Void.TYPE))
+        site.unitNamespace = ns; site.programIndex = 0; site.ordinal = 1
+        site.identity = "$ns#0#1"
+        site.install(p)
+        DispatchBootstrap.registerSite(site)
+
+        /* Unarmed -- NQP_DISPATCH_RECORD is not set in a test JVM -- the
+         * hook's own entry point does nothing and says nothing. */
+        assertEquals("", capturingErr { DispatchPersist.recordAtExit() },
+            "an unselected run records nothing")
+
+        val printed = capturingErr { DispatchPersist.recordAtExit(listOf("all")) }
+
+        val after = UnitStore.open(f.path)
+        val slot = assertNotNull(after.dispatchSlot(0, 1), "the site's slot was written")
+        val decoded = UnitCodec.decode(DispatchSlot.serializer(), slot)
+        assertEquals(DispatchSlot.SCHEMA, decoded.schema)
+        assertEquals(1, decoded.programs.size)
+        assertEquals(DispatchDump.describe(p),
+            DispatchDump.describe(assertNotNull(DispatchSlotCodec.realise(tc, decoded.programs.single()))))
+        assertTrue("dispatch-record: rewriting ${f.path}" in printed, printed)
+        assertTrue("dispatch-record: wrote 1 slots" in printed, printed)
+        assertTrue("dispatch-record: done 1 paths, 1 slots" in printed, printed)
+        assertTrue("FAILED" !in printed, printed)
+    }
+
     /** verify mode's three outcomes, which no run can reach until slots are
      *  written: a kept program that applies and reads the same as the
      *  recording (matched), one that applies and differs (mismatched, with
      *  the MISMATCH line), and one whose guards do not hold for this call at
      *  all (unseen). A verify bug looks exactly like an empty artifact --
      *  matched=0 mismatched=0 -- so the branches are covered here. */
     @Test fun verifyCountsAMatchAMismatchAndACallItDoesNotApplyTo() {
         val tc = ProgramUnitTestSupport.tc()
diff --git a/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchSlotCodecTest.kt b/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchSlotCodecTest.kt
index 6282346b5..e45058b1d 100644
--- a/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchSlotCodecTest.kt
+++ b/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchSlotCodecTest.kt
@@ -13,17 +13,17 @@ import org.raku.nqp.runtime.unit.ProgramUnitTestSupport
 import org.raku.nqp.runtime.unit.UnitCodec
 
 class DispatchSlotCodecTest {
     private val csd = CallSiteDescriptor(byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_STR), null)
 
     /** persist -> encode -> decode -> realise, the whole road a slot takes. */
     private fun roundTrip(tc: ThreadContext, p: DispatchProgram): DispatchProgram {
         val persisted = assertNotNull(DispatchSlotCodec.persist(p))
-        val bytes = UnitCodec.encode(DispatchSlot.serializer(), DispatchSlot(listOf(persisted)))
+        val bytes = UnitCodec.encode(DispatchSlot.serializer(), DispatchSlot(DispatchSlot.SCHEMA, listOf(persisted)))
         val back = UnitCodec.decode(DispatchSlot.serializer(), ByteBuffer.wrap(bytes))
         return assertNotNull(DispatchSlotCodec.realise(tc, back.programs.single()))
     }
 
     /** A program guarding arg 0 by the bootstrap's KnowHOW type and a
      *  string literal on arg 1, invoking the KnowHOW type object itself as
      *  a stand-in callee: every reference is in __6MODEL_CORE__, so it
      *  persists. The HLL guard names a config of its own rather than
@@ -63,16 +63,79 @@ class DispatchSlotCodecTest {
          * registry is the current one -- which is the state a unit is loaded
          * in (Ops.loadcompunit switches to the compiler config). */
         val realised = roundTrip(tc, DispatchProgram(csd,
             listOf(Guard.OfHll(ValueSource.Arg(0), compilee)),
             Outcome.Value(ValueSource.Arg(0)), emptyList(), ResumeKind.NONE, emptyList(), null))
         assertSame(compilee, realised.guards.filterIsInstance<Guard.OfHll>().single().hll)
     }
 
+    /**
+     * Every persisted form in one program. The codec is a pair of total
+     * functions over the tree, so the risk is not logic but COVERAGE: a
+     * P-type nothing round-trips is a shape whose first test is a build.
+     * This one carries a resume init arg, an attribute, a `how`, an unbox,
+     * a lookup, resume state, a not-literal guard, a syscall outcome, a
+     * resumption, a resume level, a bind control and its failure program, a
+     * NUM literal, a named descriptor and a resume kind. Nothing evaluates
+     * it -- realise only rebuilds -- so a program no dispatcher would ever
+     * record is still a faithful test of the road.
+     */
+    @Test fun everyPersistedFormRoundTrips() {
+        val tc = ProgramUnitTestSupport.tc()
+        val knowhow = tc.gc.KnowHOW!!
+        fun dispatcher(id: String) = assertNotNull(tc.gc.dispatchers.findOrNull(id), "dispatcher $id")
+        /* An obj positional and a named num: PDescriptor carries names. */
+        val named = CallSiteDescriptor(
+            byteArrayOf(CallSiteDescriptor.ARG_OBJ,
+                        (CallSiteDescriptor.ARG_NUM + CallSiteDescriptor.ARG_NAMED).toByte()),
+            arrayOf("epsilon"))
+        val everySource = listOf(
+            ValueSource.Arg(0),
+            ValueSource.ResumeInitArg(1, 2),
+            ValueSource.Literal(ArgKind.NUM, 2.5),
+            ValueSource.Literal(ArgKind.OBJ, knowhow),
+            ValueSource.Attribute(ValueSource.Arg(0), knowhow, "\$!count", ArgKind.INT),
+            ValueSource.How(ValueSource.Arg(0)),
+            ValueSource.Unbox(ValueSource.Arg(0), ArgKind.STR),
+            ValueSource.Lookup(ValueSource.Literal(ArgKind.OBJ, knowhow), ValueSource.ResumeState(0)))
+        val argShape = CaptureShape(everySource,
+            CallSiteDescriptor(ByteArray(everySource.size) { CallSiteDescriptor.ARG_OBJ }, null))
+        val onFailure = DispatchProgram(named,
+            listOf(Guard.NotLiteralObj(ValueSource.Arg(0), knowhow)),
+            Outcome.Value(ValueSource.ResumeState(1)),
+            emptyList(), ResumeKind.BIND_FAILURE, emptyList(), null)
+        val p = DispatchProgram(named,
+            listOf(Guard.OfType(ValueSource.Arg(0), knowhow.st),
+                   Guard.Concreteness(ValueSource.Arg(0), true),
+                   Guard.Literal(ValueSource.Arg(1), DispatchValue(ArgKind.NUM, 2.5)),
+                   Guard.NotLiteralObj(ValueSource.Arg(0), knowhow),
+                   Guard.OfHll(ValueSource.Arg(0), tc.gc.getHLLConfigFor("nqp"))),
+            Outcome.InvokeSyscall(Syscalls.find(tc, "dispatcher-drop-arg"), argShape),
+            listOf(ResumptionSpec(dispatcher("boot-value"), argShape)),
+            ResumeKind.CALLER,
+            listOf(ResumptionLevel(dispatcher("lang-call"), named,
+                listOf(Guard.Concreteness(ValueSource.ResumeInitArg(0, 0), false)),
+                ValueSource.ResumeState(0), true)),
+            BindControl(3L, 5L, true))
+        p.bindFailureProgram = onFailure
+
+        val realised = roundTrip(tc, p)
+        assertEquals(DispatchDump.describe(p), DispatchDump.describe(realised))
+        /* The text names a syscall, a dispatcher and an HLL config by name;
+         * all three must come back as the objects themselves. */
+        assertSame((p.outcome as Outcome.InvokeSyscall).syscall,
+                   (realised.outcome as Outcome.InvokeSyscall).syscall)
+        assertSame(p.resumptions.single().dispatcher, realised.resumptions.single().dispatcher)
+        assertSame(p.resumeLevels.single().dispatcher, realised.resumeLevels.single().dispatcher)
+        assertSame(p.guards.filterIsInstance<Guard.OfHll>().single().hll,
+                   realised.guards.filterIsInstance<Guard.OfHll>().single().hll)
+        assertNotNull(realised.bindFailureProgram)
+    }
+
     @Test fun anObjectInNoScMakesTheProgramUnpersistable() {
         val tc = ProgramUnitTestSupport.tc()
         val orphan = tc.gc.KnowHOW!!.st.REPR.type_object_for(tc, null)   // a fresh type object, in no SC
         val p = DispatchProgram(csd, listOf(Guard.Literal(ValueSource.Arg(0), DispatchValue(ArgKind.OBJ, orphan))),
             Outcome.Value(ValueSource.Arg(0)), emptyList(), ResumeKind.NONE, emptyList(), null)
         assertNull(DispatchSlotCodec.persist(p))
     }
 
diff --git a/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitDispatchWriterTest.kt b/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitDispatchWriterTest.kt
index f7b2b0701..b602b47e6 100644
--- a/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitDispatchWriterTest.kt
+++ b/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitDispatchWriterTest.kt
@@ -33,16 +33,42 @@ class UnitDispatchWriterTest {
         assertContentEquals(byteArrayOf(9, 9), bytesOf(assertNotNull(after.dispatchSlot(2, 0))))
         assertContentEquals(byteArrayOf(4, 5, 6), bytesOf(assertNotNull(after.nested("n1")!!.dispatchSlot(0, 1))))
         assertContentEquals(recordsBefore, bytesOf(after.entry(UnitStore.RECORDS)!!))
         assertContentEquals(serializedBefore, bytesOf(after.entry(UnitStore.SERIALIZED)!!))
         assertEquals(before.header.dispatchSlotCount, after.header.dispatchSlotCount)
         assertEquals(PROG2_TEXT, after.program(2))
     }
 
+    /** The branch no other case reaches: a NAMED lower slot GROWS, so every
+     *  slot above it moves. The unnamed slot 2 is copied forward out of the
+     *  OLD dispatch entry at its old offset and repointed to a new one; a
+     *  writer that repointed it wrongly -- or read it back at its old offset
+     *  -- would hand out another slot's bytes at the next miss, which is the
+     *  one way this file can corrupt a whole artifact. */
+    @Test fun aGrowingNamedSlotMovesTheUnnamedOnesAndTheyStillReadBack() {
+        val f = File.createTempFile("unit-", ".jar"); f.deleteOnExit()
+        val image = ProgramUnitTestSupport.image()
+        f.writeBytes(UnitImageWriter.bytes(UnitImage(image.unitId, image.hll, image.scHandle, image.scDesc,
+            image.serializedCodeRefCount, image.mainlineQbid, image.entryQbid, image.deserializeQbid, image.loadQbid,
+            image.blocks, image.programs, image.dispatchCounts, image.serialized, image.nested,
+            mapOf(0 to byteArrayOf(1, 2, 3), 2 to byteArrayOf(7, 7)))))
+        val before = UnitStore.open(f.path)
+        assertContentEquals(byteArrayOf(7, 7), bytesOf(assertNotNull(before.dispatchSlot(2, 0))))
+
+        val grown = ByteArray(8) { 9 }
+        UnitDispatchWriter.rewrite(f.path, mapOf("unit" to mapOf(0 to grown)))
+
+        val after = UnitStore.open(f.path)
+        assertContentEquals(grown, bytesOf(assertNotNull(after.dispatchSlot(0, 0))), "the named slot grew")
+        assertContentEquals(byteArrayOf(7, 7), bytesOf(assertNotNull(after.dispatchSlot(2, 0))),
+            "the unnamed slot moved and still reads back")
+        assertNull(after.dispatchSlot(0, 1), "an unnamed empty slot stays empty")
+    }
+
     @Test fun refusesASlotOutsideTheTable() {
         val f = File.createTempFile("unit-", ".jar"); f.deleteOnExit()
         f.writeBytes(UnitImageWriter.bytes(ProgramUnitTestSupport.image()))
         assertFailsWith<IllegalArgumentException> { UnitDispatchWriter.rewrite(f.path, mapOf("unit" to mapOf(3 to byteArrayOf(1)))) }
     }
 
     companion object { val PROG2_TEXT = ProgramUnitTestSupport.PROG2 }
 }
diff --git a/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt b/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt
index 3aab2afab..319bb668c 100644
--- a/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt
+++ b/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt
@@ -588,16 +588,17 @@ object NqpDispatch {
         arrayOf(AtomicLong(), AtomicLong(), AtomicLong(), AtomicLong(), AtomicLong())
 
     init {
         if (STATS) Runtime.getRuntime().addShutdownHook(Thread {
             System.err.println("dispatch stats: hits=" + hits + " misses=" + misses +
                 " sites=" + sites + " anon=" + anonSites +
                 " sitesAll=" + DispatchBootstrap.created + " restored=" + DispatchPersist.restored +
                 " restoredSites=" + DispatchPersist.restoredSites + " dropped=" + DispatchPersist.dropped +
+                " staleSchema=" + DispatchPersist.staleSchema +
                 " recorded=" + DispatchPersist.recorded +
                 " slowEvals=" + slowEvals + " invokes=" + invokes + " directs=" + directs +
                 " noTarget=" + noTarget + " badExpectation=" + badExpectation + " notCodeRef=" + notCodeRef +
                 " slowLayout=" + slowEvalsLayout + " slowNull=" + slowEvalsNull +
                 " byKind[value,syscall,mapped,invoke,resumable]=" + hitsByKind.contentToString())
             noTargetBy.entries.sortedByDescending { it.value.get() }.take(10)
                 .forEach { System.err.println("  noTarget " + it.value + " " + it.key) }
             missesBy.entries.sortedByDescending { it.value.get() }.take(20)
diff --git a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchDump.kt b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchDump.kt
index 429faeea9..fc15c6cc5 100644
--- a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchDump.kt
+++ b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchDump.kt
@@ -52,26 +52,26 @@ object DispatchDump {
         else -> "obj"
     }
 
     private fun address(r: PRef): String = "${kindName(r.kind)}:${r.handle}:${r.index}"
 
     private fun ref(obj: SixModelObject?): String {
         if (obj == null) return "null"
         return try {
-            address(DispatchSlotCodec.ref(obj)!!)
+            DispatchSlotCodec.ref(obj)?.let(::address) ?: "null"
         } catch (_: Unpersistable) {
             "NP(obj:${obj.javaClass.simpleName}:${typeName(obj)}:${if (obj.sc == null) "nosc" else "notroot"})"
         }
     }
 
     private fun ref(st: STable?): String {
         if (st == null) return "null"
         return try {
-            address(DispatchSlotCodec.ref(st)!!)
+            DispatchSlotCodec.ref(st)?.let(::address) ?: "null"
         } catch (_: Unpersistable) {
             "NP(st:${st.debugName}:${if (st.sc == null) "nosc" else "notroot"})"
         }
     }
 
     private fun literal(kind: ArgKind, value: Any?): String = when (kind) {
         ArgKind.OBJ -> ref(value as SixModelObject?)
         ArgKind.STR -> "str:" + (value as String?)?.let { quote(it) }
diff --git a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt
index fdaa1028a..32e953c5f 100644
--- a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt
+++ b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt
@@ -15,17 +15,18 @@ import org.raku.nqp.sixmodel.SixModelObject
  * the programs its unit.dispatch slot holds before anything is recorded.
  *
  * NQP_DISPATCH_PERSIST: unset or "on" consumes slots; "off" ignores them;
  * "verify" restores into DispatchCallSite.verifyPrograms without installing,
  * records fresh, and compares (see verify). NQP_DISPATCH_VERIFY_LOG=<path>
  * sends verify's lines to that file instead of stderr, pid-prefixed, so a
  * TAP run and a stderr-comparing test survive the mode. NQP_DISPATCH_RECORD
  * ("all" or a comma-separated list of store-name prefixes) makes the process
- * rewrite the selected artifacts' slots at exit (recordAtExit).
+ * rewrite the selected artifacts' slots at exit (recordAtExit); no selector
+ * reaches src/vm/jvm/stage0, which the next build compiles from.
  * NQP_DISPATCH_PERSIST_TRACE names every program a restore drops.
  *
  * Stores are registered by identity namespace (store name + "!" + unit
  * id) when a ProgramUnit initializes; they are immutable and process-wide,
  * so the eval server's runs share them.
  */
 object DispatchPersist {
     enum class Mode { ON, OFF, VERIFY }
@@ -42,22 +43,31 @@ object DispatchPersist {
     /** Names each dropped program's reason; a restore is otherwise silent. */
     private val TRACE = System.getenv("NQP_DISPATCH_PERSIST_TRACE") != null
 
     private val stores = ConcurrentHashMap<String, UnitStore>()
 
     /** NQP_DISPATCH_RECORD: "all", or comma-separated store-name prefixes. */
     private val recordSelector: List<String>? = System.getenv("NQP_DISPATCH_RECORD")?.split(',')?.map { it.trim() }?.filter { it.isNotEmpty() }
 
-    private fun selected(storeName: String): Boolean =
-        recordSelector!!.any { it == "all" || storeName.startsWith(it) }
+    private fun selected(selector: List<String>, storeName: String): Boolean =
+        selector.any { it == "all" || storeName.startsWith(it) }
+
+    /** stage0 is the bootstrap the next build compiles FROM: its jars are
+     *  committed, and the gradle build deliberately copies the UNTRAINED
+     *  stage2 into them. A hand-set NQP_DISPATCH_RECORD=all would otherwise
+     *  rewrite them as a side effect of any run that loads them. */
+    private fun isStage0(path: String): Boolean =
+        path.contains("/src/vm/jvm/stage0/") || path.startsWith("src/vm/jvm/stage0/")
 
     @JvmField val restored = AtomicLong()
     @JvmField val restoredSites = AtomicLong()
     @JvmField val dropped = AtomicLong()
+    /** Slots skipped because their first int was not DispatchSlot.SCHEMA. */
+    @JvmField val staleSchema = AtomicLong()
     @JvmField val recorded = AtomicLong()
     @JvmField val verifyMatched = AtomicLong()
     @JvmField val verifyByOutcome = AtomicLong()
     @JvmField val verifyMismatched = AtomicLong()
     @JvmField val verifyUnseen = AtomicLong()
 
     /** The verify log's stream, opened on its first line; stderr needs none. */
     @Volatile private var logStream: PrintStream? = null
@@ -99,16 +109,28 @@ object DispatchPersist {
     fun store(namespace: String): UnitStore? = stores[namespace]
 
     /** The slot's programs realised against this process, empty when the
      *  site is anonymous, the slot empty, or nothing resolves. */
     fun restore(tc: ThreadContext, site: DispatchCallSite): List<DispatchProgram> {
         val ns = site.unitNamespace ?: return emptyList()
         val store = stores[ns] ?: return emptyList()
         val bytes = store.dispatchSlot(site.programIndex, site.ordinal) ?: return emptyList()
+        /* The schema int by hand, BEFORE any decode: UnitCodec is untagged
+         * and fixed-width, so a slot of another layout would not fail to
+         * decode, it would decode into a plausible program. The slice is
+         * already little-endian and the version is deliberately its first
+         * field. A slot this runtime does not read is simply an empty one --
+         * the build that reads a slot is the build that wrote it. */
+        val schema = if (bytes.remaining() >= 4) bytes.getInt(bytes.position()) else -1
+        if (schema != DispatchSlot.SCHEMA) {
+            staleSchema.incrementAndGet()
+            if (TRACE) System.err.println("dispatch-persist: stale schema $schema at ${site.identity}")
+            return emptyList()
+        }
         val slot = try { UnitCodec.decode(DispatchSlot.serializer(), bytes) }
                    catch (e: Exception) { throw IllegalStateException("unit ${ns}: dispatch slot of program ${site.programIndex} ordinal ${site.ordinal} does not decode: ${e.message}", e) }
         val onDrop: ((String) -> Unit)? =
             if (TRACE) { reason -> System.err.println("dispatch-persist: dropped ${site.identity} $reason") }
             else null
         val out = ArrayList<DispatchProgram>(slot.programs.size)
         for (p in slot.programs) {
             val r = DispatchSlotCodec.realise(tc, p, onDrop)
@@ -195,48 +217,97 @@ object DispatchPersist {
         return true
     }
 
     /** An object is the same only when it IS the same: two type objects of
      *  one type are distinct values to a dispatch. */
     private fun sameValue(x: Any?, y: Any?): Boolean =
         if (x is SixModelObject || y is SixModelObject) x === y else x == y
 
-    /** The training run's exit: every recorded site of every selected
-     *  store, persisted into its slot; duplicates of one slot (two live
-     *  sites with one identity) merge by text, capped at MAX_PROGRAMS. */
+    /** The hook's entry point: does nothing, and says nothing, unless
+     *  NQP_DISPATCH_RECORD armed it. */
     @JvmStatic
     fun recordAtExit() {
-        val bySlot = HashMap<String, HashMap<String, HashMap<Int, LinkedHashMap<String, DispatchProgram>>>>()
-        for (site in DispatchBootstrap.sites()) {
-            val ns = site.unitNamespace ?: continue
-            val programs = site.programs
-            if (programs.isEmpty()) continue
-            val store = stores[ns] ?: continue
-            if (!selected(store.name)) continue
-            val slot = store.absoluteSlot(site.programIndex, site.ordinal)
-            if (slot < 0) continue
-            val byText = bySlot.getOrPut(store.name) { HashMap() }.getOrPut(store.entryPrefix) { HashMap() }.getOrPut(slot) { LinkedHashMap() }
-            for (p in programs) byText.putIfAbsent(DispatchDump.describe(p), p)
-        }
-        for ((path, perPrefix) in bySlot) {
-            var slots = 0; var written = 0; var unpersistable = 0
-            val encoded = HashMap<String, Map<Int, ByteArray>>()
-            for ((prefix, perSlot) in perPrefix) {
-                val m = HashMap<Int, ByteArray>()
-                for ((slot, byText) in perSlot) {
-                    val persisted = ArrayList<PProgram>()
-                    for (p in byText.values) {
-                        val pp = DispatchSlotCodec.persist(p)
-                        if (pp == null) unpersistable++ else if (persisted.size < Dispatch.MAX_PROGRAMS) persisted.add(pp)
+        recordAtExit(recordSelector ?: return)
+    }
+
+    /**
+     * The training run's exit: every recorded site of every selected store,
+     * persisted into its slot; duplicates of one slot (two live sites with
+     * one identity) merge by text, capped at MAX_PROGRAMS.
+     *
+     * Nothing here may throw. This runs in a shutdown hook, whose exception
+     * the JVM prints to a stream nobody greps and whose exit status stays 0;
+     * a throwable part way through -- after some artifacts were rewritten --
+     * would leave a HALF-trained build that the per-artifact markers cannot
+     * tell from a whole one. So every program and every artifact is
+     * contained on its own, and the run ends with one `done` line, in a
+     * finally, that the builds gate on together with the absence of FAILED.
+     *
+     * [selector] is NQP_DISPATCH_RECORD's, parsed; a test passes its own.
+     */
+    internal fun recordAtExit(selector: List<String>) {
+        var paths = 0; var slots = 0; var programs = 0; var unpersistable = 0; var failed = 0
+        try {
+            val bySlot = HashMap<String, HashMap<String, HashMap<Int, LinkedHashMap<String, DispatchProgram>>>>()
+            for (site in DispatchBootstrap.sites()) {
+                val ns = site.unitNamespace ?: continue
+                val sitePrograms = site.programs
+                if (sitePrograms.isEmpty()) continue
+                val store = stores[ns] ?: continue
+                if (!selected(selector, store.name)) continue
+                val slot = store.absoluteSlot(site.programIndex, site.ordinal)
+                if (slot < 0) continue
+                val byText = bySlot.getOrPut(store.name) { HashMap() }.getOrPut(store.entryPrefix) { HashMap() }.getOrPut(slot) { LinkedHashMap() }
+                for (p in sitePrograms) byText.putIfAbsent(DispatchDump.describe(p), p)
+            }
+            for ((path, perPrefix) in bySlot) {
+                if (isStage0(path)) {
+                    System.err.println("dispatch-record: refused $path (stage0 is never trained)")
+                    continue
+                }
+                System.err.println("dispatch-record: rewriting $path")
+                try {
+                    var pathSlots = 0; var pathPrograms = 0; var pathUnpersistable = 0
+                    val encoded = HashMap<String, Map<Int, ByteArray>>()
+                    for ((prefix, perSlot) in perPrefix) {
+                        val m = HashMap<Int, ByteArray>()
+                        for ((slot, byText) in perSlot) {
+                            val persisted = ArrayList<PProgram>()
+                            for (p in byText.values) {
+                                val pp = try { DispatchSlotCodec.persist(p) }
+                                         catch (t: Throwable) {
+                                             failed++
+                                             System.err.println("dispatch-record: FAILED program $path!$prefix#$slot: ${reason(t)}")
+                                             null
+                                         }
+                                if (pp == null) pathUnpersistable++
+                                else if (persisted.size < Dispatch.MAX_PROGRAMS) persisted.add(pp)
+                            }
+                            if (persisted.isEmpty()) continue
+                            m[slot] = UnitCodec.encode(DispatchSlot.serializer(), DispatchSlot(DispatchSlot.SCHEMA, persisted))
+                            pathSlots++; pathPrograms += persisted.size
+                        }
+                        if (m.isNotEmpty()) encoded[prefix] = m
                     }
-                    if (persisted.isEmpty()) continue
-                    m[slot] = UnitCodec.encode(DispatchSlot.serializer(), DispatchSlot(persisted))
-                    slots++; written += persisted.size
+                    if (encoded.isEmpty()) continue
+                    org.raku.nqp.runtime.unit.UnitDispatchWriter.rewrite(path, encoded)
+                    System.err.println("dispatch-record: wrote $pathSlots slots ($pathPrograms programs, $pathUnpersistable unpersistable) to $path")
+                    paths++; slots += pathSlots; programs += pathPrograms; unpersistable += pathUnpersistable
+                }
+                catch (t: Throwable) {
+                    failed++
+                    System.err.println("dispatch-record: FAILED $path: ${reason(t)}")
                 }
-                if (m.isNotEmpty()) encoded[prefix] = m
             }
-            if (encoded.isEmpty()) continue
-            org.raku.nqp.runtime.unit.UnitDispatchWriter.rewrite(path, encoded)
-            System.err.println("dispatch-record: wrote $slots slots ($written programs, $unpersistable unpersistable) to $path")
+        }
+        catch (t: Throwable) {
+            failed++
+            System.err.println("dispatch-record: FAILED: ${reason(t)}")
+        }
+        finally {
+            System.err.println("dispatch-record: done $paths paths, $slots slots, $programs programs," +
+                " $unpersistable unpersistable, $failed failed")
         }
     }
+
+    private fun reason(t: Throwable): String = "${t.javaClass.name}: ${t.message}"
 }
diff --git a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlot.kt b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlot.kt
index 21590d4ec..301544f96 100644
--- a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlot.kt
+++ b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlot.kt
@@ -48,9 +48,30 @@ import kotlinx.serialization.Serializable
                            val newState: PSource?, val requireNoFurther: Boolean)
 @Serializable class PBind(val failureFlag: Long, val successFlag: Long?, val onSuccessToo: Boolean)
 
 @Serializable class PProgram(
     val descriptor: PDescriptor, val guards: List<PGuard>, val outcome: POutcome,
     val resumptions: List<PResumption>, val resumeKind: ResumeKind, val resumeLevels: List<PLevel>,
     val bindControl: PBind?, val bindFailure: PProgram?)
 
-@Serializable class DispatchSlot(val programs: List<PProgram>)
+@Serializable class DispatchSlot(val schema: Int, val programs: List<PProgram>) {
+    companion object {
+        /**
+         * The slot layout's version, and deliberately the FIRST field, so
+         * that it is the first four little-endian bytes of every encoded
+         * slot and a reader can check it before decoding anything (see
+         * DispatchPersist.restore).
+         *
+         * **Bump this on ANY change to the P-types above**: a field added,
+         * removed, reordered or retyped, a @SerialName changed, or a change
+         * to the declaration order of ArgKind or ResumeKind -- the enums a
+         * slot persists BY INDEX. UnitCodec is untagged and fixed-width, so
+         * none of that is visible on the wire: a slot of an older layout
+         * does not fail to decode, it decodes into a plausible program.
+         *
+         * Nothing migrates: every slot is regenerated by the build that
+         * reads it (the training run), so a slot of another schema is
+         * simply an empty one.
+         */
+        const val SCHEMA = 1
+    }
+}
diff --git a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlotCodec.kt b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlotCodec.kt
index f94010ad3..83f1c66dc 100644
--- a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlotCodec.kt
+++ b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlotCodec.kt
@@ -182,12 +182,12 @@ object DispatchSlotCodec {
     }
 
     private fun shape(tc: ThreadContext, s: PShape) = CaptureShape(s.sources.map { source(tc, it) }, descriptor(s.descriptor))
 
     private fun outcome(tc: ThreadContext, o: POutcome): Outcome = when (o) {
         is POutcomeValue -> Outcome.Value(source(tc, o.source))
         is POutcomeInvoke -> Outcome.InvokeCode(source(tc, o.callee), shape(tc, o.args))
         is POutcomeSyscall -> Outcome.InvokeSyscall(
-            try { Syscalls.find(tc, o.syscall) } catch (e: Exception) { throw Unpersistable("no syscall ${o.syscall}") },
+            try { Syscalls.find(tc, o.syscall) } catch (_: Exception) { throw Unpersistable("no syscall ${o.syscall}") },
             shape(tc, o.args))
     }
 }
diff --git a/.gitignore b/.gitignore
index 2b4b159602..713b58b8f2 100644
--- a/.gitignore
+++ b/.gitignore
@@ -23,16 +23,18 @@ Makefile
 *.pdb
 *.res
 *.exp
 *.lib
 *.jar
 *.moarvm
 *.js.map
 blib/Perl6/**/*.js
+/blib/.dispatch-trained
+/blib/.dispatch-train.log
 lib/Test.pir
 lib/Pod/To/Text.pir
 lib/lib.pir
 CORE.setting.pbc
 SAFE.setting.pbc
 perl6.class
 perl6.pbc
 perl6.moarvm
diff --git a/docs/jvm-unit-lazy-loading.md b/docs/jvm-unit-lazy-loading.md
index e8cb9f0e90..e97230b8d3 100644
--- a/docs/jvm-unit-lazy-loading.md
+++ b/docs/jvm-unit-lazy-loading.md
@@ -169,23 +169,36 @@ real run (below).
 **Phase B wrote every slot empty; Phase C fills them** (2026-09-16,
 rakudo `79829d402e`, nqp `f5c5bc8fa`). Phase C changed no index and no
 other entry, so stage0 did not have to be regenerated again. The
 numbers are in `docs/jvm-perf-findings-2026-09.md`, "Milestone 7,
 Phase C".
 
 ### The slot schema
 
-A filled slot is a kotlinx-serialized `DispatchSlot(programs:
-List<PProgram>)` in `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlot.kt`,
+A filled slot is a kotlinx-serialized `DispatchSlot(schema: Int,
+programs: List<PProgram>)` in `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlot.kt`,
 written and read through `UnitCodec` -- the same codec the unit records
 use -- with short `@SerialName`s (`arg`, `lit`, `attr`, `how`, `unbox`,
 `lookup`, `type`, `conc`, `hll`, `invoke`, `syscall`, ...) and `Double`
-as raw long bits. A `PProgram` is a `DispatchProgram` with every
-reference replaced by a stable name:
+as raw long bits.
+
+`schema` is `DispatchSlot.SCHEMA` (1 today) and comes first precisely so
+that it is the slot's first four little-endian bytes: `UnitCodec` is
+untagged and fixed-width, so a slot of an older layout would not fail to
+decode but decode into a plausible program, and `DispatchPersist.restore`
+therefore reads that int by hand and treats any other value as an **empty
+slot** (`staleSchema=` on the `dispatch stats:` line, named per site under
+`NQP_DISPATCH_PERSIST_TRACE`). Nothing migrates: the build that reads a
+slot is the build that wrote it, so bumping `SCHEMA` -- required for any
+change to the `P`-types, including the declaration order of `ArgKind` or
+`ResumeKind`, which persist by index -- costs one retraining run.
+
+A `PProgram` is a `DispatchProgram` with every reference replaced by a
+stable name:
 
 - **Objects, code refs and STables** are `PRef(handle, index, kind)` --
   the serialization context's handle, the object's index in it, and the
   kind (0 object, 1 code ref, 2 STable).
 - **The HLL config** is (name, `compilerSide`), because a type's
   `hllOwner` comes from whichever of the two config maps was current at
   deserialize and `Guard.OfHll` compares by identity; it realises
   through the non-creating `GlobalContext.findHLLConfig`.
@@ -209,32 +222,51 @@ The compiler never executes what it compiles, so the outcomes come from
 running. `NQP_DISPATCH_RECORD=all` (or a comma-separated list of
 store-name prefixes) arms `DispatchPersist.recordAtExit`: at exit every
 site's installed programs are persisted into their unit's slot and
 `UnitDispatchWriter.rewrite` rebuilds each named artifact -- index slot
 rows repointed, `unit.dispatch` rebuilt, every other entry copied byte
 for byte, through a tmp file and an atomic rename. Programs merge per
 slot (restored plus new, deduplicated by their `DispatchDump` text,
 capped at `Dispatch.MAX_PROGRAMS`), so training Rakudo after nqp does
-not truncate what nqp's run wrote. The marker is `dispatch-record: wrote
-<n> slots (<n> programs, <n> unpersistable) to <artifact>`, one line per
-artifact, and both builds fail if it never appears.
+not truncate what nqp's run wrote. A path under `src/vm/jvm/stage0` is
+**refused**, whatever the selector says: stage0 is what the next build
+compiles from, and the gradle build deliberately copies the untrained
+stage2 into it.
+
+The recorder runs in a shutdown hook, whose throwable the JVM prints to a
+stream nobody greps while the exit status stays 0, so it contains every
+failure itself: per program and per artifact, as a `dispatch-record:
+FAILED ...` line, and it ends every run with one `dispatch-record: done
+<n> paths, <n> slots, <n> programs, <n> unpersistable, <n> failed`. That
+pair is the gate -- **both builds require the `done` line and the absence
+of any `FAILED` one** -- because a run that rewrote some artifacts and
+then threw satisfies the per-artifact `dispatch-record: wrote <n> slots
+(<n> programs, <n> unpersistable) to <artifact>` lines just as well as a
+whole run does. Each artifact is announced by `dispatch-record: rewriting
+<path>` before it is touched.
 
 Both builds train, with the trivial program (`-e ''`), because loading a
 setting or a module is itself the first execution under attack:
 
 - **nqp** (`nqp/build.gradle.kts`): a `Sync` task copies the nine stage2
   jars to `build/jvm/stage2-trained`, `trainDispatch` runs the trivial
   program against the copy with `NQP_DISPATCH_RECORD=all`, and `syncLib`
   takes the trained copy. `jBootstrapFiles` goes on copying the
   **untrained** stage2 into `src/vm/jvm/stage0`, so **stage0 stays
-  empty-tabled**.
+  empty-tabled**. `trainDispatch` is INTENTIONALLY always out of date
+  (`outputs.upToDateWhen { false }`, marker at
+  `build/jvm/dispatch-trained.txt`, outside the synced directory): it
+  rewrites the very jars it declares as inputs, so each build's `Sync`
+  restores the untrained jars and this run trains them afresh rather than
+  compounding one training run onto the last.
 - **rakudo** (`tools/templates/jvm/Makefile.in`): a stamp target after
-  `rakudo.jar` and the three settings runs the trivial program the same
-  way, tests the runner's exit status, greps for the marker, and then
+  `rakudo.jar`, the three settings and the two runtime jars (so a
+  runtime-only rebuild retrains) runs the trivial program the same way,
+  tests the runner's exit status, greps for the markers, and then
   `touch -r`-normalises the rewritten artifacts' mtimes so that a second
   `make` is a no-op. The runner depends on the stamp. Rakudo's run
   rewrites nqp's lib jars too -- about a third of a cold run's sites are
   in them.
 
 Training is reproduced by any clean build only up to the training run's
 own execution-order nondeterminism (about 1 % of slots); the verify mode
 below is the correctness net, not byte equality.
diff --git a/tools/templates/jvm/Makefile.in b/tools/templates/jvm/Makefile.in
index 8a8977c935..6b8660f2a3 100644
--- a/tools/templates/jvm/Makefile.in
+++ b/tools/templates/jvm/Makefile.in
@@ -104,17 +104,19 @@ NQP_RUNTIME_JAR = @nfp(nqp/build/jvm/share/runtime/nqp-runtime.jar)@
   $(RUNTIME_JAR) \
   @bpm(RUN_RAKUDO_SCRIPT)@ \
   rakudo-eval-server \
   perl6-eval-server \
   rakudo-jdb-server \
   perl6-jdb-server \
   eval-client.pl \
   perl6-j \
-  perl6-debug-j
+  perl6-debug-j \
+  @nfp(@bpm(BLIB)@/.dispatch-trained)@ \
+  @nfp(@bpm(BLIB)@/.dispatch-train.log)@
 
 @bpv(ML_EXTRA)@ = @nfp(src/vm/jvm/Raku/JavaModuleLoader.nqp)@
 # NQP_RUNTIME_JAR sits after the | : order-only, GNU make syntax. The jar
 # must be fresh before any build JVM runs on it, but its rebuild (seconds)
 # must not timestamp-cascade into a full setting recompile (many minutes)
 # -- compiled bytecode does not depend on the runtime that executes it.
 @bpv(RAKUDO_DEPS_EXTRA)@ = $(RUNTIME_JAR) | $(NQP_RUNTIME_JAR)
 
@@ -153,40 +155,52 @@ $(RUNTIME_JAR): $(RUNTIME_SOURCES) @nfp(rakudo-runtime/build.gradle.kts)@ | $(NQ
 	$(NOECHO)$(RM_F) @q(@bpm(RUN_RAKUDO_SCRIPT)@)@
 	$(NOECHO)$(CONFIGURE) --expand @nfpq(@backend_subdir@/@bpm(RUN_RAKUDO_SCRIPT)@)@ --out @bpm(RUN_RAKUDO_SCRIPT)@ \
 		--set-var=base_dir=@q($(BASE_DIR))@ \
 		--set-var=java=$(JAVA) \
 		--set-var=classpath=@q(@nfp(./blib)@@cpsep@@nop($(BLD_NQP_JARS))@@cpsep@rakudo-runtime.jar@cpsep@rakudo.jar@cpsep@@nop($(SYSROOT))@@abs2rel(@nqp_classpath@)@)@
 
 # Milestone 7 Phase C: one training run of the trivial program fills the
 # dispatch slots of every artifact it loads (blib/*.jar, rakudo.jar and
-# nqp's lib jars). The stamp keeps make's graph honest; the grep is the
-# positive marker (a run that wrote nothing fails the build). The run writes
-# to the log and the log is shown afterwards, rather than piped through tee:
-# make gives each recipe line a plain sh with no pipefail, so a pipeline
-# would report tee's status and a trainer that died PART WAY -- after some
-# artifacts were rewritten, which the grep cannot tell apart from a whole
-# run -- would leave a half-trained build behind, green.
+# nqp's lib jars). The stamp keeps make's graph honest; the two greps are
+# the positive marker. The run writes to the log and the log is shown
+# afterwards, rather than piped through tee: make gives each recipe line a
+# plain sh with no pipefail, so a pipeline would report tee's status.
+#
+# The recorder contains its own failures rather than dying (a shutdown hook's
+# throwable leaves the exit status at 0), so the exit test alone cannot see a
+# trainer that died PART WAY, after some artifacts were rewritten: it ends
+# every run with one `dispatch-record: done` line and names each contained
+# failure `dispatch-record: FAILED`. Both are tested here -- the done line
+# must be there and no FAILED line may be -- so a half-trained build cannot
+# come out green.
+#
+# The stamp also depends on the two runtime jars: they carry the recorder,
+# the codec and the slot schema, so a runtime-only rebuild (seconds, no
+# setting recompile) must retrain. That is exactly the cascade the order-only
+# `|` above avoids for the compiled artifacts, and exactly what is wanted
+# here -- retraining is one `rakudo -e ''`.
 #
 # The run rewrites those artifacts in its own order, which is not make's:
 # blib/Raku/Actions.jar landing a moment after blib/Raku/Grammar.jar would
 # make the next `make` recompile Grammar and everything below it. The
 # content changed but nothing went stale, so every rewritten artifact gets
 # one and the same mtime back -- make remakes on a STRICTLY newer
 # prerequisite -- and the stamp alone is newer than all of them. The trivial
 # program never loads 6.e (nor any later spec), so the settings and the
 # bootstraps join that one mtime explicitly: training is the last build
 # step, and everything the build produced is current as of it.
 @bpv(TRAIN_STAMP)@ = @nfp(@bpm(BLIB)@/.dispatch-trained)@
 
-@bpm(TRAIN_STAMP)@: @bsm(RAKUDO)@@for_specs( @bsm(SETTING_@ucspec@)@)@
+@bpm(TRAIN_STAMP)@: @bsm(RAKUDO)@@for_specs( @bsm(SETTING_@ucspec@)@)@ $(RUNTIME_JAR) $(NQP_RUNTIME_JAR)
 	@echo(+++ Training	dispatch slots)@
 	$(NOECHO)NQP_DISPATCH_RECORD=all @bpm(RUN_RAKUDO)@ -e '' > @nfpq(@bpm(BLIB)@/.dispatch-train.log)@ 2>&1 || { cat @nfpq(@bpm(BLIB)@/.dispatch-train.log)@; exit 1; }
 	$(NOECHO)cat @nfpq(@bpm(BLIB)@/.dispatch-train.log)@
-	$(NOECHO)grep -q 'dispatch-record: wrote' @nfpq(@bpm(BLIB)@/.dispatch-train.log)@
+	$(NOECHO)grep -q 'dispatch-record: done' @nfpq(@bpm(BLIB)@/.dispatch-train.log)@
+	$(NOECHO)if grep -q 'dispatch-record: FAILED' @nfpq(@bpm(BLIB)@/.dispatch-train.log)@; then exit 1; fi
 	$(NOECHO)sed -n 's|^dispatch-record: wrote .* to ||p' @nfpq(@bpm(BLIB)@/.dispatch-train.log)@ | xargs touch -r @nfpq(@bpm(BLIB)@/.dispatch-train.log)@
 	$(NOECHO)touch -r @nfpq(@bpm(BLIB)@/.dispatch-train.log)@ @bsm(RAKUDO)@@for_specs( @bsm(SETTING_@ucspec@)@)@ @bpm(RAKUDO_BOOTSTRAP_PRECOMPS)@
 	$(NOECHO)touch $@
 
 $(J_RUNNER): @@script(create-jvm-runner.pl)@@@for_specs( @bsm(SETTING_@ucspec@)@)@ @bpm(TRAIN_STAMP)@
 	@echo(+++ Setting up	$@)@
 	$(NOECHO)$(PERL5) @shquot(@script(create-jvm-runner.pl)@)@ dev @q($(BASE_DIR))@ . . @q(@nqp_home@)@ @q(@static_nqp_home@)@ @q(@static_rakudo_home@)@ @q($(NQP_JARS))@
 
