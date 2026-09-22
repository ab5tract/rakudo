18310f0a2 Dispatch: the persisted program -- DispatchSlot schema and DispatchSlotCodec (Phase C)
 .../org/raku/nqp/dispatch/DispatchSlotCodecTest.kt |  58 +++++++
 .../org/raku/nqp/runtime/unit/UnitCodecTest.kt     |   9 +
 .../runtime/org/raku/nqp/dispatch/DispatchDump.kt  |  40 ++---
 .../runtime/org/raku/nqp/dispatch/DispatchSlot.kt  |  54 ++++++
 .../org/raku/nqp/dispatch/DispatchSlotCodec.kt     | 186 +++++++++++++++++++++
 .../runtime/org/raku/nqp/runtime/unit/UnitCodec.kt |  15 +-
 6 files changed, 332 insertions(+), 30 deletions(-)
diff --git a/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchSlotCodecTest.kt b/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchSlotCodecTest.kt
new file mode 100644
index 000000000..cfefc4d9a
--- /dev/null
+++ b/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchSlotCodecTest.kt
@@ -0,0 +1,58 @@
+package org.raku.nqp.dispatch
+
+import java.nio.ByteBuffer
+import kotlin.test.Test
+import kotlin.test.assertEquals
+import kotlin.test.assertNotNull
+import kotlin.test.assertNull
+import org.raku.nqp.runtime.CallSiteDescriptor
+import org.raku.nqp.runtime.ThreadContext
+import org.raku.nqp.runtime.unit.ProgramUnitTestSupport
+import org.raku.nqp.runtime.unit.UnitCodec
+
+class DispatchSlotCodecTest {
+    private val csd = CallSiteDescriptor(byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_STR), null)
+
+    /** A program guarding arg 0 by the bootstrap's KnowHOW type and a
+     *  string literal on arg 1, invoking the KnowHOW type object itself as
+     *  a stand-in callee: every reference is in __6MODEL_CORE__, so it
+     *  persists. */
+    private fun program(tc: ThreadContext): DispatchProgram {
+        val knowhow = tc.gc.KnowHOW!!
+        return DispatchProgram(csd,
+            listOf(Guard.OfType(ValueSource.Arg(0), knowhow.st),
+                   Guard.Concreteness(ValueSource.Arg(0), false),
+                   Guard.Literal(ValueSource.Arg(1), DispatchValue(ArgKind.STR, "new_type")),
+                   Guard.OfHll(ValueSource.Arg(0), knowhow.st.hllOwner)),
+            Outcome.InvokeCode(ValueSource.Literal(ArgKind.OBJ, knowhow),
+                CaptureShape(listOf(ValueSource.Arg(0), ValueSource.Literal(ArgKind.INT, 3L)),
+                    CallSiteDescriptor(byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_INT), null))),
+            emptyList(), ResumeKind.NONE, emptyList(), null)
+    }
+
+    @Test fun aProgramOverScObjectsRoundTripsToTheSameText() {
+        val tc = ProgramUnitTestSupport.tc()
+        val p = program(tc)
+        val persisted = assertNotNull(DispatchSlotCodec.persist(p))
+        val bytes = UnitCodec.encode(DispatchSlot.serializer(), DispatchSlot(listOf(persisted)))
+        val back = UnitCodec.decode(DispatchSlot.serializer(), ByteBuffer.wrap(bytes))
+        val realised = assertNotNull(DispatchSlotCodec.realise(tc, back.programs.single()))
+        assertEquals(DispatchDump.describe(p), DispatchDump.describe(realised))
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
+    }
+}
diff --git a/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitCodecTest.kt b/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitCodecTest.kt
index 8f21fee22..d5f666496 100644
--- a/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitCodecTest.kt
+++ b/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitCodecTest.kt
@@ -14,20 +14,22 @@ class UnitCodecTest {
         val i: Int, val l: Long, val b: Boolean, val s: String, val ns: String?,
         val list: List<String>, val nlist: List<String>?, val ints: IntArray, val longs: LongArray,
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
         val back = UnitCodec.decode(Probe.serializer(), ByteBuffer.wrap(bytes))
         assertEquals(sample.i, back.i); assertEquals(sample.l, back.l); assertEquals(sample.b, back.b)
@@ -45,15 +47,22 @@ class UnitCodecTest {
 
     @Test fun decodesFromASliceWithoutMovingTheCallersBuffer() {
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
diff --git a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchDump.kt b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchDump.kt
index b9814a8e9..429faeea9 100644
--- a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchDump.kt
+++ b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchDump.kt
@@ -1,18 +1,16 @@
 package org.raku.nqp.dispatch
 
 import java.io.File
 import java.io.PrintWriter
 import org.raku.nqp.runtime.CallSiteDescriptor
-import org.raku.nqp.runtime.CodeRef
 import org.raku.nqp.sixmodel.STable
-import org.raku.nqp.sixmodel.SerializationContext
 import org.raku.nqp.sixmodel.SixModelObject
 
 /**
  * `NQP_DISPATCH_DUMP=<path>`: at exit, every registered callsite's installed
  * programs in a normalised text form -- one `site` line per callsite, one
  * `prog` line per program. Every object, STable and code reference is named
  * by its serialization context (handle and root-set index) when it has one,
  * and marked `NP(...)` with the reason when it has none, so two dumps of the
  * same build compare textually and the unpersistable programs show their
  * cause. Milestone 7 Phase C's spike (C0) sizes the persisted miss from
@@ -34,55 +32,51 @@ object DispatchDump {
                 out.println("site ${site.identity ?: "anon"} ${site.linkedName ?: "?"} " +
                     "${programs.size}${if (site.fromIndy) " indy" else ""}")
                 for ((i, prog) in programs.withIndex())
                     out.println("prog $i ${describe(prog)}")
             }
         }
     }
 
     /* ----- references ----- */
 
+    /* The addressing itself is DispatchSlotCodec's, so that a dump names a
+     * reference exactly when the program carrying it persists; what has no
+     * address is spelled out here instead, with the reason the codec gave. */
+
     private fun typeName(obj: SixModelObject): String =
         if (obj.stInitialized) obj.st.debugName ?: "?" else "?"
 
-    private fun objectIndex(sc: SerializationContext, obj: SixModelObject): Int {
-        val i = sc.getObjectIndex(obj)
-        return if (i >= 0 && i < sc.objectCount() && sc.getObject(i) === obj) i else -1
+    private fun kindName(kind: Int): String = when (kind) {
+        PRef.CODE -> "code"
+        PRef.STABLE -> "st"
+        else -> "obj"
     }
 
-    private fun codeIndex(sc: SerializationContext, obj: SixModelObject): Int {
-        if (obj !is CodeRef) return -1
-        val i = try { sc.getCodeIndex(obj) } catch (_: NullPointerException) { -1 }
-        return if (i >= 0 && i < sc.coderefCount() && sc.getCodeRef(i) === obj) i else -1
-    }
+    private fun address(r: PRef): String = "${kindName(r.kind)}:${r.handle}:${r.index}"
 
     private fun ref(obj: SixModelObject?): String {
         if (obj == null) return "null"
-        val sc = obj.sc
-        if (sc != null) {
-            val oi = objectIndex(sc, obj)
-            if (oi >= 0) return "obj:${sc.handle}:$oi"
-            val ci = codeIndex(sc, obj)
-            if (ci >= 0) return "code:${sc.handle}:$ci"
+        return try {
+            address(DispatchSlotCodec.ref(obj)!!)
+        } catch (_: Unpersistable) {
+            "NP(obj:${obj.javaClass.simpleName}:${typeName(obj)}:${if (obj.sc == null) "nosc" else "notroot"})"
         }
-        return "NP(obj:${obj.javaClass.simpleName}:${typeName(obj)}:${if (sc == null) "nosc" else "notroot"})"
     }
 
     private fun ref(st: STable?): String {
         if (st == null) return "null"
-        val sc = st.sc
-        if (sc != null) {
-            val i = try { sc.getSTableIndex(st) } catch (_: NullPointerException) { -1 }
-            if (i >= 0 && i < sc.stableCount() && sc.getSTable(i) === st)
-                return "st:${sc.handle}:$i"
+        return try {
+            address(DispatchSlotCodec.ref(st)!!)
+        } catch (_: Unpersistable) {
+            "NP(st:${st.debugName}:${if (st.sc == null) "nosc" else "notroot"})"
         }
-        return "NP(st:${st.debugName}:${if (sc == null) "nosc" else "notroot"})"
     }
 
     private fun literal(kind: ArgKind, value: Any?): String = when (kind) {
         ArgKind.OBJ -> ref(value as SixModelObject?)
         ArgKind.STR -> "str:" + (value as String?)?.let { quote(it) }
         else -> "${kind.name.lowercase()}:$value"
     }
 
     private fun quote(s: String): String {
         val cut = if (s.length > 60) s.substring(0, 60) + "..." else s
diff --git a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlot.kt b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlot.kt
new file mode 100644
index 000000000..44d144086
--- /dev/null
+++ b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlot.kt
@@ -0,0 +1,54 @@
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
+@Serializable @SerialName("hll") class PGuardHll(val on: PSource, val hll: String?) : PGuard()
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
index 000000000..70798fb11
--- /dev/null
+++ b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlotCodec.kt
@@ -0,0 +1,186 @@
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
+        is Guard.OfHll -> PGuardHll(source(g.on), g.hll?.name)
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
+    fun realise(tc: ThreadContext, p: PProgram): DispatchProgram? =
+        try { program(tc, p) } catch (_: Unpersistable) { null }
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
+        is PGuardHll -> Guard.OfHll(source(tc, g.on), g.hll?.let { tc.gc.getHLLConfigFor(it) })
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
diff --git a/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitCodec.kt b/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitCodec.kt
index 6879e34b3..0a8f50ed9 100644
--- a/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitCodec.kt
+++ b/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitCodec.kt
@@ -10,25 +10,26 @@ import kotlinx.serialization.SerializationStrategy
 import kotlinx.serialization.descriptors.SerialDescriptor
 import kotlinx.serialization.encoding.AbstractDecoder
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
         val out = ByteArrayOutputStream(256)
         Writer(out).encodeSerializableValue(serializer, value)
@@ -45,21 +46,21 @@ object UnitCodec {
         private val scratch = ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN)
 
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
         }
     }
@@ -68,21 +69,21 @@ object UnitCodec {
         override val serializersModule: SerializersModule = EmptySerializersModule()
         private var elementIndex = 0
 
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
         override fun decodeNull(): Nothing? = null
         override fun decodeSequentially(): Boolean = true
