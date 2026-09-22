953251714 Dispatch: restore a site's persisted programs at its first miss; verify mode; the counters (Phase C)
 .../org/raku/nqp/dispatch/DispatchPersistTest.kt   | 47 +++++++++++
 .../src/main/java/org/raku/nqp/truffle/NqpOps.java |  9 ++-
 .../org/raku/nqp/truffle/NqpProgramBuilder.java    |  3 +-
 .../kotlin/org/raku/nqp/truffle/NqpDispatch.kt     |  5 ++
 .../jvm/runtime/org/raku/nqp/dispatch/Dispatch.kt  | 25 ++++++
 .../org/raku/nqp/dispatch/DispatchBootstrap.kt     | 23 ++++++
 .../org/raku/nqp/dispatch/DispatchPersist.kt       | 94 ++++++++++++++++++++++
 .../org/raku/nqp/runtime/unit/ProgramUnit.kt       |  3 +
 .../runtime/org/raku/nqp/runtime/unit/UnitStore.kt | 19 ++++-
 9 files changed, 220 insertions(+), 8 deletions(-)
diff --git a/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchPersistTest.kt b/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchPersistTest.kt
new file mode 100644
index 000000000..26de24da8
--- /dev/null
+++ b/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchPersistTest.kt
@@ -0,0 +1,47 @@
+package org.raku.nqp.dispatch
+
+import java.lang.invoke.MethodType
+import java.nio.ByteBuffer
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
+}
diff --git a/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java b/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java
index fbc8aeea1..5acd50d04 100644
--- a/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java
+++ b/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java
@@ -819,25 +819,30 @@ final class NqpOps {
      * callback then holds captures of a dead recording -- "capture that
      * is not part of this dispatch" under race/hyper loads). Settled
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
      * is PE-visible; only a miss, a flattening shape, and the outcome's
      * invocation cross into the bytecode world.
diff --git a/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java b/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java
index 17e9f8497..21dd47f17 100644
--- a/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java
+++ b/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java
@@ -565,22 +565,21 @@ final class NqpProgramBuilder {
                     names.isEmpty() ? null : names.toArray(new String[0]));
                 // Every dispatch is a potential continuation suspension
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
                 }
                 return at;
diff --git a/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt b/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt
index 6a72130f3..3aab2afab 100644
--- a/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt
+++ b/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt
@@ -15,22 +15,24 @@ import java.lang.invoke.MethodHandle
 import java.lang.invoke.MethodType
 import java.util.Objects
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
 import org.raku.nqp.runtime.CallSiteDescriptor
 import org.raku.nqp.runtime.CodeEngines
@@ -582,20 +584,23 @@ object NqpDispatch {
     @JvmField val noTarget = AtomicLong()
     @JvmField val badExpectation = AtomicLong()
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
         })
     }
diff --git a/src/vm/jvm/runtime/org/raku/nqp/dispatch/Dispatch.kt b/src/vm/jvm/runtime/org/raku/nqp/dispatch/Dispatch.kt
index 78a7d3aae..4f7e57973 100644
--- a/src/vm/jvm/runtime/org/raku/nqp/dispatch/Dispatch.kt
+++ b/src/vm/jvm/runtime/org/raku/nqp/dispatch/Dispatch.kt
@@ -100,20 +100,37 @@ object Dispatch {
     @JvmStatic
     fun fallback(site: DispatchCallSite, name: String, descriptor: CallSiteDescriptor,
                  compiled: Int, tc: ThreadContext, args: Array<Any?>) {
         val programs = site.programs
         if (programs.size > compiled) {
             val ctx = GuardCheckContext(tc, descriptor, args)
             for (i in compiled until programs.size)
                 if (run(tc, ctx, programs[i], site)) return
         }
         if (site.linkedName == null) site.linkedName = name
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
     }
 
@@ -242,24 +259,27 @@ object Dispatch {
                         callback = resumeCallback(tc, dispatcher)
                         capture = outcome.capture ?: record.initialCapture
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
                     "Cannot capture a continuation across a dispatch recording (" +
                     (record.currentDispatcher?.id ?: dispatcher?.id ?: "?") + ")")
@@ -332,20 +352,25 @@ object Dispatch {
     ) : DispatchContext {
         override fun resumeInitArg(level: Int, index: Int): DispatchValue =
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
     private fun run(tc: ThreadContext, ctx: GuardCheckContext, program: DispatchProgram,
                     site: DispatchCallSite?, bindFailureOf: DispatchRecord? = null): Boolean {
diff --git a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchBootstrap.kt b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchBootstrap.kt
index 888cd938d..4e40c8663 100644
--- a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchBootstrap.kt
+++ b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchBootstrap.kt
@@ -22,36 +22,52 @@ class CachedDispatcher(@JvmField val dispatcher: Dispatcher, @JvmField val epoch
  *
  * A site that runs hot compiles its programs into a MethodHandle guard chain
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
      * dispatch entry; indy-born sites also install its adapted form as the
      * invokedynamic target. The volatile store publishes the fields the
@@ -77,20 +93,22 @@ class DispatchCallSite @JvmOverloads constructor(type: MethodType,
     /**
      * Forgets everything recorded here, returning the site to the state it was
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
      * Adds a program to the cache. Past the limit the callsite is megamorphic
      * and we stop growing: dispatches still work by recording each time.
@@ -110,20 +128,25 @@ class DispatchCallSite @JvmOverloads constructor(type: MethodType,
     fun recompile() {
         val compiled = DispatchCompiler.compileChain(this) ?: return
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
      * loaded class -- which is the expensive part -- without carrying the
      * recordings across.
diff --git a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt
new file mode 100644
index 000000000..99eafaa2d
--- /dev/null
+++ b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt
@@ -0,0 +1,94 @@
+package org.raku.nqp.dispatch
+
+import java.util.concurrent.ConcurrentHashMap
+import java.util.concurrent.atomic.AtomicLong
+import org.raku.nqp.runtime.CallSiteDescriptor
+import org.raku.nqp.runtime.ThreadContext
+import org.raku.nqp.runtime.unit.UnitCodec
+import org.raku.nqp.runtime.unit.UnitStore
+
+/**
+ * The persisted miss (milestone 7 Phase C): a site's first miss restores
+ * the programs its unit.dispatch slot holds before anything is recorded.
+ *
+ * NQP_DISPATCH_PERSIST: unset or "on" consumes slots; "off" ignores them;
+ * "verify" restores into DispatchCallSite.verifyPrograms without installing,
+ * records fresh, and compares (see verify). NQP_DISPATCH_RECORD ("all" or
+ * a comma-separated list of store-name prefixes) makes the process rewrite
+ * the selected artifacts' slots at exit (recordAtExit, Task 5).
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
+    private val stores = ConcurrentHashMap<String, UnitStore>()
+
+    @JvmField val restored = AtomicLong()
+    @JvmField val restoredSites = AtomicLong()
+    @JvmField val dropped = AtomicLong()
+    @JvmField val recorded = AtomicLong()
+    @JvmField val verifyMatched = AtomicLong()
+    @JvmField val verifyMismatched = AtomicLong()
+    @JvmField val verifyUnseen = AtomicLong()
+
+    init {
+        if (mode == Mode.VERIFY) {
+            System.err.println("dispatch-verify: on")
+            Runtime.getRuntime().addShutdownHook(Thread {
+                System.err.println("dispatch-verify: matched=$verifyMatched mismatched=$verifyMismatched unseen=$verifyUnseen")
+            })
+        }
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
+        val out = ArrayList<DispatchProgram>(slot.programs.size)
+        for (p in slot.programs) {
+            val r = DispatchSlotCodec.realise(tc, p)
+            if (r == null) dropped.incrementAndGet() else out.add(r)
+        }
+        if (out.isNotEmpty()) { restored.addAndGet(out.size.toLong()); restoredSites.incrementAndGet() }
+        return out
+    }
+
+    /** verify mode: after a fresh recording, every kept-aside program that
+     *  applies to the recorded call must read the same as the recording. */
+    fun verify(tc: ThreadContext, site: DispatchCallSite, recorded: DispatchProgram,
+               descriptor: CallSiteDescriptor, args: Array<Any?>) {
+        val kept = site.verifyPrograms ?: return
+        val ctx = Dispatch.guardContext(tc, descriptor, args)
+        var applicable = 0
+        val text = DispatchDump.describe(recorded)
+        for (p in kept) {
+            if (!Captures.sameShape(p.descriptor, descriptor) || !p.guardsMatch(ctx)) continue
+            applicable++
+            val theirs = DispatchDump.describe(p)
+            if (theirs == text) verifyMatched.incrementAndGet()
+            else {
+                verifyMismatched.incrementAndGet()
+                System.err.println("dispatch-verify: MISMATCH ${site.identity} ${site.linkedName}\n  persisted: $theirs\n  recorded:  $text")
+            }
+        }
+        if (applicable == 0) verifyUnseen.incrementAndGet()
+    }
+}
diff --git a/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt b/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt
index e271bfe0d..08f45f5b5 100644
--- a/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt
+++ b/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt
@@ -154,20 +154,23 @@ class ProgramUnit(@JvmField val store: UnitStore) : CompilationUnit() {
             val idx = sci.rawOLexicalIdx(v.name)
             if (idx == -1) continue
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
         if (gc == null) gc = tc.gc
         // Includes the dependency loads the program triggers; they print
diff --git a/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitStore.kt b/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitStore.kt
index 8d647e4c2..23e502749 100644
--- a/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitStore.kt
+++ b/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitStore.kt
@@ -122,29 +122,40 @@ class UnitStore private constructor(
     fun program(idx: Int): String {
         val off = programRow(idx, 0); val len = programRow(idx, 1)
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
     fun entry(unitEntryName: String): ByteBuffer? =
         entries[if (prefix == "unit") unitEntryName else prefix + unitEntryName.removePrefix("unit")]?.duplicate()
