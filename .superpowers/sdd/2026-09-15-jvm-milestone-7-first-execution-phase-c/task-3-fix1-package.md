 .../org/raku/nqp/dispatch/DispatchSlotCodecTest.kt | 45 +++++++++++++++++++---
 .../runtime/org/raku/nqp/dispatch/DispatchSlot.kt  |  4 +-
 .../org/raku/nqp/dispatch/DispatchSlotCodec.kt     |  9 ++++-
 .../runtime/org/raku/nqp/runtime/GlobalContext.kt  | 19 ++++++++-
 .../jvm/runtime/org/raku/nqp/runtime/HLLConfig.kt  | 10 +++++
 5 files changed, 77 insertions(+), 10 deletions(-)
diff --git a/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchSlotCodecTest.kt b/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchSlotCodecTest.kt
index cfefc4d9a..6282346b5 100644
--- a/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchSlotCodecTest.kt
+++ b/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchSlotCodecTest.kt
@@ -1,58 +1,91 @@
 package org.raku.nqp.dispatch
 
 import java.nio.ByteBuffer
 import kotlin.test.Test
 import kotlin.test.assertEquals
+import kotlin.test.assertNotSame
 import kotlin.test.assertNotNull
 import kotlin.test.assertNull
+import kotlin.test.assertSame
 import org.raku.nqp.runtime.CallSiteDescriptor
 import org.raku.nqp.runtime.ThreadContext
 import org.raku.nqp.runtime.unit.ProgramUnitTestSupport
 import org.raku.nqp.runtime.unit.UnitCodec
 
 class DispatchSlotCodecTest {
     private val csd = CallSiteDescriptor(byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_STR), null)
 
+    /** persist -> encode -> decode -> realise, the whole road a slot takes. */
+    private fun roundTrip(tc: ThreadContext, p: DispatchProgram): DispatchProgram {
+        val persisted = assertNotNull(DispatchSlotCodec.persist(p))
+        val bytes = UnitCodec.encode(DispatchSlot.serializer(), DispatchSlot(listOf(persisted)))
+        val back = UnitCodec.decode(DispatchSlot.serializer(), ByteBuffer.wrap(bytes))
+        return assertNotNull(DispatchSlotCodec.realise(tc, back.programs.single()))
+    }
+
     /** A program guarding arg 0 by the bootstrap's KnowHOW type and a
      *  string literal on arg 1, invoking the KnowHOW type object itself as
      *  a stand-in callee: every reference is in __6MODEL_CORE__, so it
-     *  persists. */
+     *  persists. The HLL guard names a config of its own rather than
+     *  knowhow.st.hllOwner, which the bootstrap leaves null. */
     private fun program(tc: ThreadContext): DispatchProgram {
         val knowhow = tc.gc.KnowHOW!!
         return DispatchProgram(csd,
             listOf(Guard.OfType(ValueSource.Arg(0), knowhow.st),
                    Guard.Concreteness(ValueSource.Arg(0), false),
                    Guard.Literal(ValueSource.Arg(1), DispatchValue(ArgKind.STR, "new_type")),
-                   Guard.OfHll(ValueSource.Arg(0), knowhow.st.hllOwner)),
+                   Guard.OfHll(ValueSource.Arg(0), tc.gc.getHLLConfigFor("nqp"))),
             Outcome.InvokeCode(ValueSource.Literal(ArgKind.OBJ, knowhow),
                 CaptureShape(listOf(ValueSource.Arg(0), ValueSource.Literal(ArgKind.INT, 3L)),
                     CallSiteDescriptor(byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_INT), null))),
             emptyList(), ResumeKind.NONE, emptyList(), null)
     }
 
     @Test fun aProgramOverScObjectsRoundTripsToTheSameText() {
         val tc = ProgramUnitTestSupport.tc()
         val p = program(tc)
-        val persisted = assertNotNull(DispatchSlotCodec.persist(p))
-        val bytes = UnitCodec.encode(DispatchSlot.serializer(), DispatchSlot(listOf(persisted)))
-        val back = UnitCodec.decode(DispatchSlot.serializer(), ByteBuffer.wrap(bytes))
-        val realised = assertNotNull(DispatchSlotCodec.realise(tc, back.programs.single()))
+        val realised = roundTrip(tc, p)
         assertEquals(DispatchDump.describe(p), DispatchDump.describe(realised))
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
     }
 
     @Test fun anObjectInNoScMakesTheProgramUnpersistable() {
         val tc = ProgramUnitTestSupport.tc()
         val orphan = tc.gc.KnowHOW!!.st.REPR.type_object_for(tc, null)   // a fresh type object, in no SC
         val p = DispatchProgram(csd, listOf(Guard.Literal(ValueSource.Arg(0), DispatchValue(ArgKind.OBJ, orphan))),
             Outcome.Value(ValueSource.Arg(0)), emptyList(), ResumeKind.NONE, emptyList(), null)
         assertNull(DispatchSlotCodec.persist(p))
     }
 
     @Test fun aReferenceThatDoesNotResolveDropsTheProgram() {
         val tc = ProgramUnitTestSupport.tc()
         val ghost = PProgram(PDescriptor(byteArrayOf(0), null),
             listOf(PGuardType(PArg(0), PRef("no-such-sc", 0, PRef.STABLE))),
             POutcomeValue(PArg(0)), emptyList(), ResumeKind.NONE, emptyList(), null, null)
         assertNull(DispatchSlotCodec.realise(tc, ghost))
+
+        val ghostHll = PProgram(PDescriptor(byteArrayOf(0), null),
+            listOf(PGuardHll(PArg(0), "no-such-hll", false)),
+            POutcomeValue(PArg(0)), emptyList(), ResumeKind.NONE, emptyList(), null, null)
+        assertNull(DispatchSlotCodec.realise(tc, ghostHll))
     }
 }
diff --git a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlot.kt b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlot.kt
index 44d144086..21590d4ec 100644
--- a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlot.kt
+++ b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlot.kt
@@ -25,21 +25,23 @@ import kotlinx.serialization.Serializable
 @Serializable @SerialName("how") class PHow(val from: PSource) : PSource()
 @Serializable @SerialName("unbox") class PUnbox(val from: PSource, val kind: ArgKind) : PSource()
 @Serializable @SerialName("lookup") class PLookup(val table: PSource, val key: PSource) : PSource()
 @Serializable @SerialName("rstate") class PResumeState(val level: Int) : PSource()
 
 @Serializable sealed class PGuard
 @Serializable @SerialName("type") class PGuardType(val on: PSource, val type: PRef?) : PGuard()
 @Serializable @SerialName("conc") class PGuardConcreteness(val on: PSource, val concrete: Boolean) : PGuard()
 @Serializable @SerialName("lit") class PGuardLiteral(val on: PSource, val expected: PLiteral) : PGuard()
 @Serializable @SerialName("notlit") class PGuardNotLiteralObj(val on: PSource, val rejected: PRef?) : PGuard()
-@Serializable @SerialName("hll") class PGuardHll(val on: PSource, val hll: String?) : PGuard()
+/** The name alone does not name a config: [compilerSide] picks the registry
+ *  it lives in (HLLConfig.compilerSide). */
+@Serializable @SerialName("hll") class PGuardHll(val on: PSource, val hll: String?, val compilerSide: Boolean) : PGuard()
 
 @Serializable class PShape(val sources: List<PSource>, val descriptor: PDescriptor)
 
 @Serializable sealed class POutcome
 @Serializable @SerialName("value") class POutcomeValue(val source: PSource) : POutcome()
 @Serializable @SerialName("invoke") class POutcomeInvoke(val callee: PSource, val args: PShape) : POutcome()
 @Serializable @SerialName("syscall") class POutcomeSyscall(val syscall: String, val args: PShape) : POutcome()
 
 @Serializable class PResumption(val dispatcher: String, val initArgs: PShape)
 @Serializable class PLevel(val dispatcher: String, val initDescriptor: PDescriptor, val guards: List<PGuard>,
diff --git a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlotCodec.kt b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlotCodec.kt
index 70798fb11..7c5000539 100644
--- a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlotCodec.kt
+++ b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlotCodec.kt
@@ -86,21 +86,21 @@ object DispatchSlotCodec {
         is ValueSource.Unbox -> PUnbox(source(s.from), s.kind)
         is ValueSource.Lookup -> PLookup(source(s.table), source(s.key))
         is ValueSource.ResumeState -> PResumeState(s.level)
     }
 
     private fun guard(g: Guard): PGuard = when (g) {
         is Guard.OfType -> PGuardType(source(g.on), ref(g.type))
         is Guard.Concreteness -> PGuardConcreteness(source(g.on), g.concrete)
         is Guard.Literal -> PGuardLiteral(source(g.on), literal(g.expected.kind, g.expected.value))
         is Guard.NotLiteralObj -> PGuardNotLiteralObj(source(g.on), ref(g.rejected))
-        is Guard.OfHll -> PGuardHll(source(g.on), g.hll?.name)
+        is Guard.OfHll -> PGuardHll(source(g.on), g.hll?.name, g.hll?.compilerSide ?: false)
     }
 
     private fun shape(c: CaptureShape) = PShape(c.sources.map { source(it) }, descriptor(c.descriptor))
 
     private fun outcome(o: Outcome): POutcome = when (o) {
         is Outcome.Value -> POutcomeValue(source(o.source))
         is Outcome.InvokeCode -> POutcomeInvoke(source(o.callee), shape(o.args))
         is Outcome.InvokeSyscall -> POutcomeSyscall(o.syscall.name, shape(o.args))
     }
 
@@ -164,21 +164,26 @@ object DispatchSlotCodec {
         is PUnbox -> ValueSource.Unbox(source(tc, s.from), s.kind)
         is PLookup -> ValueSource.Lookup(source(tc, s.table), source(tc, s.key))
         is PResumeState -> ValueSource.ResumeState(s.level)
     }
 
     private fun guard(tc: ThreadContext, g: PGuard): Guard = when (g) {
         is PGuardType -> Guard.OfType(source(tc, g.on), stable(tc, g.type))
         is PGuardConcreteness -> Guard.Concreteness(source(tc, g.on), g.concrete)
         is PGuardLiteral -> Guard.Literal(source(tc, g.on), DispatchValue(g.expected.kind, literal(tc, g.expected)))
         is PGuardNotLiteralObj -> Guard.NotLiteralObj(source(tc, g.on), obj(tc, g.rejected))
-        is PGuardHll -> Guard.OfHll(source(tc, g.on), g.hll?.let { tc.gc.getHLLConfigFor(it) })
+        /* findHLLConfig, not getHLLConfigFor: the guard compares by identity,
+         * so a config minted here -- or taken from whichever registry happens
+         * to be current -- would be a guard that can never match. */
+        is PGuardHll -> Guard.OfHll(source(tc, g.on), g.hll?.let {
+            tc.gc.findHLLConfig(it, g.compilerSide)
+                ?: throw Unpersistable("no HLL config $it (compilerSide=${g.compilerSide})") })
     }
 
     private fun shape(tc: ThreadContext, s: PShape) = CaptureShape(s.sources.map { source(tc, it) }, descriptor(s.descriptor))
 
     private fun outcome(tc: ThreadContext, o: POutcome): Outcome = when (o) {
         is POutcomeValue -> Outcome.Value(source(tc, o.source))
         is POutcomeInvoke -> Outcome.InvokeCode(source(tc, o.callee), shape(tc, o.args))
         is POutcomeSyscall -> Outcome.InvokeSyscall(
             try { Syscalls.find(tc, o.syscall) } catch (e: Exception) { throw Unpersistable("no syscall ${o.syscall}") },
             shape(tc, o.args))
diff --git a/src/vm/jvm/runtime/org/raku/nqp/runtime/GlobalContext.kt b/src/vm/jvm/runtime/org/raku/nqp/runtime/GlobalContext.kt
index fd95f9d49..9ab1702af 100644
--- a/src/vm/jvm/runtime/org/raku/nqp/runtime/GlobalContext.kt
+++ b/src/vm/jvm/runtime/org/raku/nqp/runtime/GlobalContext.kt
@@ -249,24 +249,27 @@ class GlobalContext {
      */
     init {
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
 
         contConfigs = HashMap<String, ContainerConfigurer>()
         contConfigs.put("code_pair", CodePairContainerConfigurer())
@@ -294,27 +297,41 @@ class GlobalContext {
 
     /**
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
         config.arrayIteratorType = BOOTIter
         config.hashIteratorType = BOOTIter
diff --git a/src/vm/jvm/runtime/org/raku/nqp/runtime/HLLConfig.kt b/src/vm/jvm/runtime/org/raku/nqp/runtime/HLLConfig.kt
index 40420af68..55533c02b 100644
--- a/src/vm/jvm/runtime/org/raku/nqp/runtime/HLLConfig.kt
+++ b/src/vm/jvm/runtime/org/raku/nqp/runtime/HLLConfig.kt
@@ -17,20 +17,30 @@ class HLLConfig {
         const val ROLE_NUM = 2
         const val ROLE_STR = 3
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
 
     /** The type to use for nqp::hash(...) */
