 .../org/raku/nqp/dispatch/DispatchPersistTest.kt   |  62 +++++++++--
 .../org/raku/nqp/dispatch/DispatchPersist.kt       | 117 +++++++++++++++++++--
 .../org/raku/nqp/dispatch/DispatchSlotCodec.kt     |   6 +-
 3 files changed, 167 insertions(+), 18 deletions(-)
diff --git a/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchPersistTest.kt b/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchPersistTest.kt
index a02ffd234..e9dcf0609 100644
--- a/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchPersistTest.kt
+++ b/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchPersistTest.kt
@@ -74,34 +74,80 @@ class DispatchPersistTest {
         var unseen = DispatchPersist.verifyUnseen.get()
         DispatchPersist.verify(tc, site, program(Outcome.Value(ValueSource.Arg(0))), csd, matching)
         assertEquals(matched + 1, DispatchPersist.verifyMatched.get(), "the same program matches")
         assertEquals(mismatched, DispatchPersist.verifyMismatched.get())
         assertEquals(unseen, DispatchPersist.verifyUnseen.get())
 
         matched = DispatchPersist.verifyMatched.get()
         mismatched = DispatchPersist.verifyMismatched.get()
         unseen = DispatchPersist.verifyUnseen.get()
         val differing = program(Outcome.Value(ValueSource.Literal(ArgKind.INT, 1L)))
-        val err = ByteArrayOutputStream()
-        val saved = System.err
-        try {
-            System.setErr(PrintStream(err, true, StandardCharsets.UTF_8))
-            DispatchPersist.verify(tc, site, differing, csd, matching)
-        }
-        finally { System.setErr(saved) }
+        val printed = capturingErr { DispatchPersist.verify(tc, site, differing, csd, matching) }
         assertEquals(mismatched + 1, DispatchPersist.verifyMismatched.get(), "a different outcome mismatches")
         assertEquals(matched, DispatchPersist.verifyMatched.get())
         assertEquals(unseen, DispatchPersist.verifyUnseen.get())
-        val printed = err.toString(StandardCharsets.UTF_8)
         assertTrue("dispatch-verify: MISMATCH" in printed, "the mismatch prints: $printed")
         assertTrue("persisted:" in printed && "recorded:" in printed, "both texts print: $printed")
 
         matched = DispatchPersist.verifyMatched.get()
         mismatched = DispatchPersist.verifyMismatched.get()
         unseen = DispatchPersist.verifyUnseen.get()
         DispatchPersist.verify(tc, site, program(Outcome.Value(ValueSource.Arg(0))), csd,
             arrayOf<Any?>(tc.gc.BOOTArray))
         assertEquals(unseen + 1, DispatchPersist.verifyUnseen.get(), "a call the guards reject is unseen")
         assertEquals(matched, DispatchPersist.verifyMatched.get())
         assertEquals(mismatched, DispatchPersist.verifyMismatched.get())
     }
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
 }
diff --git a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt
index 0157432c3..fdaa1028a 100644
--- a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt
+++ b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt
@@ -1,111 +1,212 @@
 package org.raku.nqp.dispatch
 
+import java.io.FileOutputStream
+import java.io.PrintStream
 import java.util.concurrent.ConcurrentHashMap
 import java.util.concurrent.atomic.AtomicLong
 import org.raku.nqp.runtime.CallSiteDescriptor
 import org.raku.nqp.runtime.ThreadContext
 import org.raku.nqp.runtime.unit.UnitCodec
 import org.raku.nqp.runtime.unit.UnitStore
+import org.raku.nqp.sixmodel.SixModelObject
 
 /**
  * The persisted miss (milestone 7 Phase C): a site's first miss restores
  * the programs its unit.dispatch slot holds before anything is recorded.
  *
  * NQP_DISPATCH_PERSIST: unset or "on" consumes slots; "off" ignores them;
  * "verify" restores into DispatchCallSite.verifyPrograms without installing,
- * records fresh, and compares (see verify). NQP_DISPATCH_RECORD ("all" or
- * a comma-separated list of store-name prefixes) makes the process rewrite
- * the selected artifacts' slots at exit (recordAtExit).
+ * records fresh, and compares (see verify). NQP_DISPATCH_VERIFY_LOG=<path>
+ * sends verify's lines to that file instead of stderr, pid-prefixed, so a
+ * TAP run and a stderr-comparing test survive the mode. NQP_DISPATCH_RECORD
+ * ("all" or a comma-separated list of store-name prefixes) makes the process
+ * rewrite the selected artifacts' slots at exit (recordAtExit).
+ * NQP_DISPATCH_PERSIST_TRACE names every program a restore drops.
  *
  * Stores are registered by identity namespace (store name + "!" + unit
  * id) when a ProgramUnit initializes; they are immutable and process-wide,
  * so the eval server's runs share them.
  */
 object DispatchPersist {
     enum class Mode { ON, OFF, VERIFY }
 
     @JvmField val mode: Mode = when (System.getenv("NQP_DISPATCH_PERSIST")) {
         "off" -> Mode.OFF
         "verify" -> Mode.VERIFY
         else -> Mode.ON
     }
 
+    /** Where verify's lines go; null is stderr. */
+    private val verifyLog: String? = System.getenv("NQP_DISPATCH_VERIFY_LOG")
+
+    /** Names each dropped program's reason; a restore is otherwise silent. */
+    private val TRACE = System.getenv("NQP_DISPATCH_PERSIST_TRACE") != null
+
     private val stores = ConcurrentHashMap<String, UnitStore>()
 
     /** NQP_DISPATCH_RECORD: "all", or comma-separated store-name prefixes. */
     private val recordSelector: List<String>? = System.getenv("NQP_DISPATCH_RECORD")?.split(',')?.map { it.trim() }?.filter { it.isNotEmpty() }
 
     private fun selected(storeName: String): Boolean =
         recordSelector!!.any { it == "all" || storeName.startsWith(it) }
 
     @JvmField val restored = AtomicLong()
     @JvmField val restoredSites = AtomicLong()
     @JvmField val dropped = AtomicLong()
     @JvmField val recorded = AtomicLong()
     @JvmField val verifyMatched = AtomicLong()
+    @JvmField val verifyByOutcome = AtomicLong()
     @JvmField val verifyMismatched = AtomicLong()
     @JvmField val verifyUnseen = AtomicLong()
 
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
     init {
         if (mode == Mode.VERIFY) {
-            System.err.println("dispatch-verify: on")
+            verifySay("dispatch-verify: on")
             Runtime.getRuntime().addShutdownHook(Thread {
-                System.err.println("dispatch-verify: matched=$verifyMatched mismatched=$verifyMismatched unseen=$verifyUnseen")
+                verifySay("dispatch-verify: matched=$verifyMatched byOutcome=$verifyByOutcome" +
+                    " mismatched=$verifyMismatched unseen=$verifyUnseen")
+                logStream?.close()
             })
         }
         if (recordSelector != null) Runtime.getRuntime().addShutdownHook(Thread { recordAtExit() })
     }
 
     @JvmStatic
     fun register(namespace: String, store: UnitStore) { stores.putIfAbsent(namespace, store) }
 
     fun store(namespace: String): UnitStore? = stores[namespace]
 
     /** The slot's programs realised against this process, empty when the
      *  site is anonymous, the slot empty, or nothing resolves. */
     fun restore(tc: ThreadContext, site: DispatchCallSite): List<DispatchProgram> {
         val ns = site.unitNamespace ?: return emptyList()
         val store = stores[ns] ?: return emptyList()
         val bytes = store.dispatchSlot(site.programIndex, site.ordinal) ?: return emptyList()
         val slot = try { UnitCodec.decode(DispatchSlot.serializer(), bytes) }
                    catch (e: Exception) { throw IllegalStateException("unit ${ns}: dispatch slot of program ${site.programIndex} ordinal ${site.ordinal} does not decode: ${e.message}", e) }
+        val onDrop: ((String) -> Unit)? =
+            if (TRACE) { reason -> System.err.println("dispatch-persist: dropped ${site.identity} $reason") }
+            else null
         val out = ArrayList<DispatchProgram>(slot.programs.size)
         for (p in slot.programs) {
-            val r = DispatchSlotCodec.realise(tc, p)
+            val r = DispatchSlotCodec.realise(tc, p, onDrop)
             if (r == null) dropped.incrementAndGet() else out.add(r)
         }
         if (out.isNotEmpty()) { restored.addAndGet(out.size.toLong()); restoredSites.incrementAndGet() }
         return out
     }
 
     /** verify mode: after a fresh recording, every kept-aside program that
-     *  applies to the recorded call must read the same as the recording. */
+     *  applies to the recorded call must agree with the recording -- by its
+     *  text, or failing that by what its outcome evaluates to (see
+     *  [sameOutcome]). */
     fun verify(tc: ThreadContext, site: DispatchCallSite, recorded: DispatchProgram,
                descriptor: CallSiteDescriptor, args: Array<Any?>) {
         val kept = site.verifyPrograms ?: return
+        if (kept.isEmpty()) { verifyUnseen.incrementAndGet(); return }
         val ctx = Dispatch.guardContext(tc, descriptor, args)
         var applicable = 0
         val text = DispatchDump.describe(recorded)
         for (p in kept) {
             if (!Captures.sameShape(p.descriptor, descriptor) || !p.guardsMatch(ctx)) continue
             applicable++
             val theirs = DispatchDump.describe(p)
             if (theirs == text) verifyMatched.incrementAndGet()
+            else if (sameOutcome(ctx, p, recorded)) verifyByOutcome.incrementAndGet()
             else {
                 verifyMismatched.incrementAndGet()
-                System.err.println("dispatch-verify: MISMATCH ${site.identity} ${site.linkedName}\n  persisted: $theirs\n  recorded:  $text")
+                verifySay("dispatch-verify: MISMATCH ${site.identity} ${site.linkedName}\n  persisted: $theirs\n  recorded:  $text")
             }
         }
         if (applicable == 0) verifyUnseen.incrementAndGet()
     }
 
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
     /** The training run's exit: every recorded site of every selected
      *  store, persisted into its slot; duplicates of one slot (two live
      *  sites with one identity) merge by text, capped at MAX_PROGRAMS. */
     @JvmStatic
     fun recordAtExit() {
         val bySlot = HashMap<String, HashMap<String, HashMap<Int, LinkedHashMap<String, DispatchProgram>>>>()
         for (site in DispatchBootstrap.sites()) {
             val ns = site.unitNamespace ?: continue
             val programs = site.programs
             if (programs.isEmpty()) continue
diff --git a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlotCodec.kt b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlotCodec.kt
index 7c5000539..f94010ad3 100644
--- a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlotCodec.kt
+++ b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlotCodec.kt
@@ -99,22 +99,24 @@ object DispatchSlotCodec {
     private fun shape(c: CaptureShape) = PShape(c.sources.map { source(it) }, descriptor(c.descriptor))
 
     private fun outcome(o: Outcome): POutcome = when (o) {
         is Outcome.Value -> POutcomeValue(source(o.source))
         is Outcome.InvokeCode -> POutcomeInvoke(source(o.callee), shape(o.args))
         is Outcome.InvokeSyscall -> POutcomeSyscall(o.syscall.name, shape(o.args))
     }
 
     /* ----- from the persisted form ----- */
 
-    fun realise(tc: ThreadContext, p: PProgram): DispatchProgram? =
-        try { program(tc, p) } catch (_: Unpersistable) { null }
+    /** [onDrop], when given, is handed the reason a program did not realise
+     *  (NQP_DISPATCH_PERSIST_TRACE reads it); the program is dropped either way. */
+    fun realise(tc: ThreadContext, p: PProgram, onDrop: ((String) -> Unit)? = null): DispatchProgram? =
+        try { program(tc, p) } catch (e: Unpersistable) { onDrop?.invoke(e.message ?: "?"); null }
 
     private fun program(tc: ThreadContext, p: PProgram): DispatchProgram {
         val out = DispatchProgram(descriptor(p.descriptor), p.guards.map { guard(tc, it) }, outcome(tc, p.outcome),
             p.resumptions.map { ResumptionSpec(dispatcher(tc, it.dispatcher), shape(tc, it.initArgs)) },
             p.resumeKind,
             p.resumeLevels.map { l ->
                 ResumptionLevel(dispatcher(tc, l.dispatcher), descriptor(l.initDescriptor),
                     l.guards.map { guard(tc, it) }, l.newState?.let { source(tc, it) }, l.requireNoFurther) },
             p.bindControl?.let { BindControl(it.failureFlag, it.successFlag, it.onSuccessToo) })
         p.bindFailure?.let { out.bindFailureProgram = program(tc, it) }
