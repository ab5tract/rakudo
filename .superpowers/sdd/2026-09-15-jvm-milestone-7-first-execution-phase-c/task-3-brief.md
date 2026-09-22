## Task 3: The schema and the codec (`DispatchSlot`, `DispatchSlotCodec`)

**Files:**
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlot.kt`
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlotCodec.kt`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitCodec.kt` (Double)
- Test: `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchSlotCodecTest.kt`,
  `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitCodecTest.kt`

**Interfaces:**
- Consumes: `DispatchModel.kt`'s classes (constructor names as in the
  code below), `DispatchDump.describe`, `UnitCodec.encode/decode`,
  `SerializationContext` (`handle`, `getObjectIndex`, `getObject`,
  `objectCount`, `getCodeIndex`, `getCodeRef`, `coderefCount`,
  `getSTableIndex`, `getSTable`, `stableCount`), `tc.gc.scs`,
  `tc.gc.dispatchers.findOrNull(id)`, `Syscalls.find(tc, name)`,
  `tc.gc.getHLLConfigFor(name)`.
- Produces: `DispatchSlotCodec.persist(p: DispatchProgram): PProgram?`,
  `DispatchSlotCodec.realise(tc: ThreadContext, p: PProgram): DispatchProgram?`,
  `DispatchSlot(programs: List<PProgram>)` with
  `DispatchSlot.serializer()`.

- [ ] **Step 1: Double in the codec.** In `UnitCodec.Writer` replace the
  throwing `encodeDouble` with
  `override fun encodeDouble(value: Double) = encodeLong(value.toRawBits())`
  and in `Reader` `override fun decodeDouble(): Double = Double.fromBits(buf.getLong())`.
  Add to `UnitCodecTest.kt`:
  ```kotlin
  @Serializable class WithDouble(val d: Double, val tag: Int)
  @Test fun doublesRoundTripAsRawBits() {
      val b = UnitCodec.encode(WithDouble.serializer(), WithDouble(-0.0, 7))
      assertEquals(12, b.size)
      val d = UnitCodec.decode(WithDouble.serializer(), ByteBuffer.wrap(b))
      assertEquals((-0.0).toRawBits(), d.d.toRawBits()); assertEquals(7, d.tag)
  }
  ```
  (a nested `@Serializable` class of the test class, as Phase B's codec
  tests do; the plugin rejects local ones.)

- [ ] **Step 2: Write `DispatchSlot.kt`**:
  ```kotlin
  package org.raku.nqp.dispatch

  import kotlinx.serialization.SerialName
  import kotlinx.serialization.Serializable

  /**
   * The persisted twin of a DispatchProgram (milestone 7 Phase C): the
   * same tree with every object reference replaced by an SC address, the
   * HLL config by its name, the syscall by its name and the dispatcher by
   * its id. One DispatchSlot per site slot of unit.dispatch, encoded by
   * UnitCodec. Data only; DispatchSlotCodec converts both ways.
   */
  @Serializable class PRef(val handle: String, val index: Int, val kind: Int) {
      companion object { const val OBJ = 0; const val CODE = 1; const val STABLE = 2 }
  }

  @Serializable class PDescriptor(val flags: ByteArray, val names: List<String>?)

  @Serializable sealed class PSource
  @Serializable @SerialName("arg") class PArg(val index: Int) : PSource()
  @Serializable @SerialName("rinit") class PResumeInitArg(val level: Int, val index: Int) : PSource()
  /** OBJ: [obj] (null is the null object); INT/UINT: [i]; NUM: [n]; STR: [s]. */
  @Serializable @SerialName("lit") class PLiteral(val kind: ArgKind, val obj: PRef?, val i: Long, val n: Double, val s: String?) : PSource()
  @Serializable @SerialName("attr") class PAttribute(val from: PSource, val classHandle: PRef?, val name: String, val kind: ArgKind) : PSource()
  @Serializable @SerialName("how") class PHow(val from: PSource) : PSource()
  @Serializable @SerialName("unbox") class PUnbox(val from: PSource, val kind: ArgKind) : PSource()
  @Serializable @SerialName("lookup") class PLookup(val table: PSource, val key: PSource) : PSource()
  @Serializable @SerialName("rstate") class PResumeState(val level: Int) : PSource()

  @Serializable sealed class PGuard
  @Serializable @SerialName("type") class PGuardType(val on: PSource, val type: PRef?) : PGuard()
  @Serializable @SerialName("conc") class PGuardConcreteness(val on: PSource, val concrete: Boolean) : PGuard()
  @Serializable @SerialName("lit") class PGuardLiteral(val on: PSource, val expected: PLiteral) : PGuard()
  @Serializable @SerialName("notlit") class PGuardNotLiteralObj(val on: PSource, val rejected: PRef?) : PGuard()
  @Serializable @SerialName("hll") class PGuardHll(val on: PSource, val hll: String?) : PGuard()

  @Serializable class PShape(val sources: List<PSource>, val descriptor: PDescriptor)

  @Serializable sealed class POutcome
  @Serializable @SerialName("value") class POutcomeValue(val source: PSource) : POutcome()
  @Serializable @SerialName("invoke") class POutcomeInvoke(val callee: PSource, val args: PShape) : POutcome()
  @Serializable @SerialName("syscall") class POutcomeSyscall(val syscall: String, val args: PShape) : POutcome()

  @Serializable class PResumption(val dispatcher: String, val initArgs: PShape)
  @Serializable class PLevel(val dispatcher: String, val initDescriptor: PDescriptor, val guards: List<PGuard>,
                             val newState: PSource?, val requireNoFurther: Boolean)
  @Serializable class PBind(val failureFlag: Long, val successFlag: Long?, val onSuccessToo: Boolean)

  @Serializable class PProgram(
      val descriptor: PDescriptor, val guards: List<PGuard>, val outcome: POutcome,
      val resumptions: List<PResumption>, val resumeKind: ResumeKind, val resumeLevels: List<PLevel>,
      val bindControl: PBind?, val bindFailure: PProgram?)

  @Serializable class DispatchSlot(val programs: List<PProgram>)
  ```

- [ ] **Step 3: Write the failing round-trip test** `DispatchSlotCodecTest.kt`
  (package `org.raku.nqp.dispatch`; uses `ProgramUnitTestSupport.tc()` for
  a fresh runtime whose bootstrap SC `__6MODEL_CORE__` is registered):
  ```kotlin
  package org.raku.nqp.dispatch

  import java.nio.ByteBuffer
  import kotlin.test.Test
  import kotlin.test.assertEquals
  import kotlin.test.assertNotNull
  import kotlin.test.assertNull
  import org.raku.nqp.runtime.CallSiteDescriptor
  import org.raku.nqp.runtime.unit.ProgramUnitTestSupport
  import org.raku.nqp.runtime.unit.UnitCodec
  import org.raku.nqp.sixmodel.SerializationContext

  class DispatchSlotCodecTest {
      private val csd = CallSiteDescriptor(byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_STR), null)

      /** A program guarding arg 0 by the bootstrap's KnowHOW type and a
       *  string literal on arg 1, invoking the KnowHOW type object's
       *  STable-carrying object as a stand-in callee: every reference is
       *  in __6MODEL_CORE__, so it persists. */
      private fun program(tc: org.raku.nqp.runtime.ThreadContext): DispatchProgram {
          val knowhow = tc.gc.KnowHOW!!
          return DispatchProgram(csd,
              listOf(Guard.OfType(ValueSource.Arg(0), knowhow.st),
                     Guard.Concreteness(ValueSource.Arg(0), false),
                     Guard.Literal(ValueSource.Arg(1), DispatchValue(ArgKind.STR, "new_type")),
                     Guard.OfHll(ValueSource.Arg(0), knowhow.st.hllOwner)),
              Outcome.InvokeCode(ValueSource.Literal(ArgKind.OBJ, knowhow),
                  CaptureShape(listOf(ValueSource.Arg(0), ValueSource.Literal(ArgKind.INT, 3L)),
                      CallSiteDescriptor(byteArrayOf(CallSiteDescriptor.ARG_OBJ, CallSiteDescriptor.ARG_INT), null))),
              emptyList(), ResumeKind.NONE, emptyList(), null)
      }

      @Test fun aProgramOverScObjectsRoundTripsToTheSameText() {
          val tc = ProgramUnitTestSupport.tc()
          val p = program(tc)
          val persisted = assertNotNull(DispatchSlotCodec.persist(p))
          val bytes = UnitCodec.encode(DispatchSlot.serializer(), DispatchSlot(listOf(persisted)))
          val back = UnitCodec.decode(DispatchSlot.serializer(), ByteBuffer.wrap(bytes))
          val realised = assertNotNull(DispatchSlotCodec.realise(tc, back.programs.single()))
          assertEquals(DispatchDump.describe(p), DispatchDump.describe(realised))
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
      }
  }
  ```
  If `tc.gc.KnowHOW` is not the field's name, take the KnowHOW type
  object from `KnowHOWBootstrapper`'s result the way `SerializationContextTest`
  gets an SC object (read that test first); the point is any object
  rooted in `__6MODEL_CORE__`. If `REPR.type_object_for(tc, null)` is not
  the REPR API's spelling, use `tc.gc.BOOTCode`'s REPR with `null` HOW as
  the tests in `runtime/` already do; the point is an object with `sc == null`.

- [ ] **Step 4: Run it, expect compile failure** (`DispatchSlotCodec`
  undefined): `./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.dispatch.DispatchSlotCodecTest' -q`

- [ ] **Step 5: Write `DispatchSlotCodec.kt`**:
  ```kotlin
  package org.raku.nqp.dispatch

  import org.raku.nqp.runtime.CallSiteDescriptor
  import org.raku.nqp.runtime.CodeRef
  import org.raku.nqp.runtime.ThreadContext
  import org.raku.nqp.sixmodel.STable
  import org.raku.nqp.sixmodel.SerializationContext
  import org.raku.nqp.sixmodel.SixModelObject

  /** A reference no serialization context names; caught at the top of
   *  persist/realise, never escapes. */
  class Unpersistable(what: String) : RuntimeException(what)

  /**
   * DispatchProgram <-> PProgram. persist() returns null for a program
   * with a reference that has no SC address (C0: 1.1 % of them; the
   * classes are listed in the findings); realise() returns null when a
   * persisted reference does not resolve in this process (an SC not
   * loaded yet, an index past the table, an empty root slot), and the
   * site then records as it always did. Both directions are total
   * functions of their input: no state, no caching.
   */
  object DispatchSlotCodec {
      /* ----- to the persisted form ----- */

      fun persist(p: DispatchProgram): PProgram? = try { program(p) } catch (_: Unpersistable) { null }

      private fun program(p: DispatchProgram): PProgram = PProgram(
          descriptor(p.descriptor), p.guards.map { guard(it) }, outcome(p.outcome),
          p.resumptions.map { PResumption(it.dispatcher.id, shape(it.initArgs)) },
          p.resumeKind,
          p.resumeLevels.map { l ->
              PLevel(l.dispatcher.id, descriptor(l.initDescriptor), l.guards.map { guard(it) },
                  l.newState?.let { source(it) }, l.requireNoFurther) },
          p.bindControl?.let { PBind(it.failureFlag, it.successFlag, it.onSuccessToo) },
          p.bindFailureProgram?.let { program(it) })

      private fun descriptor(d: CallSiteDescriptor) = PDescriptor(d.argFlags.copyOf(), d.names?.toList())

      private fun typeName(obj: SixModelObject): String =
          if (obj.stInitialized) obj.st.debugName ?: "?" else "?"

      /* The SC's index maps answer 0 / throw for an absent key, so every
       * index is validated by reading the root slot back. */
      private fun objectIndex(sc: SerializationContext, obj: SixModelObject): Int {
          val i = sc.getObjectIndex(obj)
          return if (i >= 0 && i < sc.objectCount() && sc.getObject(i) === obj) i else -1
      }
      private fun codeIndex(sc: SerializationContext, obj: SixModelObject): Int {
          if (obj !is CodeRef) return -1
          val i = try { sc.getCodeIndex(obj) } catch (_: NullPointerException) { -1 }
          return if (i >= 0 && i < sc.coderefCount() && sc.getCodeRef(i) === obj) i else -1
      }

      fun ref(obj: SixModelObject?): PRef? {
          if (obj == null) return null
          val sc = obj.sc ?: throw Unpersistable("object of ${typeName(obj)} in no SC")
          val oi = objectIndex(sc, obj)
          if (oi >= 0) return PRef(sc.handle, oi, PRef.OBJ)
          val ci = codeIndex(sc, obj)
          if (ci >= 0) return PRef(sc.handle, ci, PRef.CODE)
          throw Unpersistable("object of ${typeName(obj)} not in the root set of ${sc.handle}")
      }

      fun ref(st: STable?): PRef? {
          if (st == null) return null
          val sc = st.sc ?: throw Unpersistable("STable ${st.debugName} in no SC")
          val i = try { sc.getSTableIndex(st) } catch (_: NullPointerException) { -1 }
          if (i >= 0 && i < sc.stableCount() && sc.getSTable(i) === st) return PRef(sc.handle, i, PRef.STABLE)
          throw Unpersistable("STable ${st.debugName} not in the root set of ${sc.handle}")
      }

      private fun literal(kind: ArgKind, value: Any?): PLiteral = when (kind) {
          ArgKind.OBJ -> PLiteral(kind, ref(value as SixModelObject?), 0, 0.0, null)
          ArgKind.INT, ArgKind.UINT -> PLiteral(kind, null, (value as Number).toLong(), 0.0, null)
          ArgKind.NUM -> PLiteral(kind, null, 0, (value as Number).toDouble(), null)
          ArgKind.STR -> PLiteral(kind, null, 0, 0.0, value as String?)
      }

      private fun source(s: ValueSource): PSource = when (s) {
          is ValueSource.Arg -> PArg(s.index)
          is ValueSource.ResumeInitArg -> PResumeInitArg(s.level, s.index)
          is ValueSource.Literal -> literal(s.kind, s.value)
          is ValueSource.Attribute -> PAttribute(source(s.from), ref(s.classHandle), s.name, s.kind)
          is ValueSource.How -> PHow(source(s.from))
          is ValueSource.Unbox -> PUnbox(source(s.from), s.kind)
          is ValueSource.Lookup -> PLookup(source(s.table), source(s.key))
          is ValueSource.ResumeState -> PResumeState(s.level)
      }

      private fun guard(g: Guard): PGuard = when (g) {
          is Guard.OfType -> PGuardType(source(g.on), ref(g.type))
          is Guard.Concreteness -> PGuardConcreteness(source(g.on), g.concrete)
          is Guard.Literal -> PGuardLiteral(source(g.on), literal(g.expected.kind, g.expected.value))
          is Guard.NotLiteralObj -> PGuardNotLiteralObj(source(g.on), ref(g.rejected))
          is Guard.OfHll -> PGuardHll(source(g.on), g.hll?.name)
      }

      private fun shape(c: CaptureShape) = PShape(c.sources.map { source(it) }, descriptor(c.descriptor))

      private fun outcome(o: Outcome): POutcome = when (o) {
          is Outcome.Value -> POutcomeValue(source(o.source))
          is Outcome.InvokeCode -> POutcomeInvoke(source(o.callee), shape(o.args))
          is Outcome.InvokeSyscall -> POutcomeSyscall(o.syscall.name, shape(o.args))
      }

      /* ----- from the persisted form ----- */

      fun realise(tc: ThreadContext, p: PProgram): DispatchProgram? =
          try { program(tc, p) } catch (_: Unpersistable) { null }

      private fun program(tc: ThreadContext, p: PProgram): DispatchProgram {
          val out = DispatchProgram(descriptor(p.descriptor), p.guards.map { guard(tc, it) }, outcome(tc, p.outcome),
              p.resumptions.map { ResumptionSpec(dispatcher(tc, it.dispatcher), shape(tc, it.initArgs)) },
              p.resumeKind,
              p.resumeLevels.map { l ->
                  ResumptionLevel(dispatcher(tc, l.dispatcher), descriptor(l.initDescriptor),
                      l.guards.map { guard(tc, it) }, l.newState?.let { source(tc, it) }, l.requireNoFurther) },
              p.bindControl?.let { BindControl(it.failureFlag, it.successFlag, it.onSuccessToo) })
          p.bindFailure?.let { out.bindFailureProgram = program(tc, it) }
          return out
      }

      private fun descriptor(d: PDescriptor) = CallSiteDescriptor(d.flags.copyOf(), d.names?.toTypedArray())

      private fun sc(tc: ThreadContext, handle: String): SerializationContext =
          tc.gc.scs[handle] ?: throw Unpersistable("no SC $handle")

      private fun obj(tc: ThreadContext, r: PRef?): SixModelObject? {
          if (r == null) return null
          val sc = sc(tc, r.handle)
          val o: SixModelObject? = when (r.kind) {
              PRef.OBJ -> if (r.index in 0 until sc.objectCount()) sc.getObject(r.index) else null
              PRef.CODE -> if (r.index in 0 until sc.coderefCount()) sc.getCodeRef(r.index) else null
              else -> null
          }
          return o ?: throw Unpersistable("${r.handle}:${r.index} (kind ${r.kind}) is empty")
      }

      private fun stable(tc: ThreadContext, r: PRef?): STable? {
          if (r == null) return null
          val sc = sc(tc, r.handle)
          if (r.kind != PRef.STABLE || r.index !in 0 until sc.stableCount())
              throw Unpersistable("${r.handle}:${r.index} is not an STable slot")
          return sc.getSTable(r.index) ?: throw Unpersistable("${r.handle}:${r.index} STable is empty")
      }

      private fun dispatcher(tc: ThreadContext, id: String): Dispatcher =
          tc.gc.dispatchers.findOrNull(id) ?: throw Unpersistable("no dispatcher $id")

      private fun literal(tc: ThreadContext, l: PLiteral): Any? = when (l.kind) {
          ArgKind.OBJ -> obj(tc, l.obj)
          ArgKind.INT, ArgKind.UINT -> l.i
          ArgKind.NUM -> l.n
          ArgKind.STR -> l.s
      }

      private fun source(tc: ThreadContext, s: PSource): ValueSource = when (s) {
          is PArg -> ValueSource.Arg(s.index)
          is PResumeInitArg -> ValueSource.ResumeInitArg(s.level, s.index)
          is PLiteral -> ValueSource.Literal(s.kind, literal(tc, s))
          is PAttribute -> ValueSource.Attribute(source(tc, s.from), obj(tc, s.classHandle), s.name, s.kind)
          is PHow -> ValueSource.How(source(tc, s.from))
          is PUnbox -> ValueSource.Unbox(source(tc, s.from), s.kind)
          is PLookup -> ValueSource.Lookup(source(tc, s.table), source(tc, s.key))
          is PResumeState -> ValueSource.ResumeState(s.level)
      }

      private fun guard(tc: ThreadContext, g: PGuard): Guard = when (g) {
          is PGuardType -> Guard.OfType(source(tc, g.on), stable(tc, g.type))
          is PGuardConcreteness -> Guard.Concreteness(source(tc, g.on), g.concrete)
          is PGuardLiteral -> Guard.Literal(source(tc, g.on), DispatchValue(g.expected.kind, literal(tc, g.expected)))
          is PGuardNotLiteralObj -> Guard.NotLiteralObj(source(tc, g.on), obj(tc, g.rejected))
          is PGuardHll -> Guard.OfHll(source(tc, g.on), g.hll?.let { tc.gc.getHLLConfigFor(it) })
      }

      private fun shape(tc: ThreadContext, s: PShape) = CaptureShape(s.sources.map { source(tc, it) }, descriptor(s.descriptor))

      private fun outcome(tc: ThreadContext, o: POutcome): Outcome = when (o) {
          is POutcomeValue -> Outcome.Value(source(tc, o.source))
          is POutcomeInvoke -> Outcome.InvokeCode(source(tc, o.callee), shape(tc, o.args))
          is POutcomeSyscall -> Outcome.InvokeSyscall(
              try { Syscalls.find(tc, o.syscall) } catch (e: Exception) { throw Unpersistable("no syscall ${o.syscall}") },
              shape(tc, o.args))
      }
  }
  ```
  Constructor parameter names above are those of `DispatchModel.kt`
  (`Guard.OfType(on, type)`, `Guard.Literal(on, expected)`,
  `Guard.NotLiteralObj(on, rejected)`, `Guard.OfHll(on, hll)`,
  `ValueSource.Attribute(from, classHandle, name, kind)`,
  `Outcome.InvokeCode(callee, args)`, `Outcome.InvokeSyscall(syscall, args)`,
  `ResumptionSpec(dispatcher, initArgs)`, `ResumptionLevel(dispatcher,
  initDescriptor, guards, newState, requireNoFurther)`, `BindControl(
  failureFlag, successFlag, onSuccessToo)`, `DispatchProgram(descriptor,
  guards, outcome, resumptions, resumeKind, resumeLevels, bindControl)`).
  `DispatchDump.ref`/`objectIndex`/`codeIndex` duplicate the three
  helpers here: delete them from `DispatchDump.kt` and call
  `DispatchSlotCodec`'s, mapping `Unpersistable` to the `NP(...)` text.

- [ ] **Step 6: Run the tests**: same command as Step 4, plus `--tests 'org.raku.nqp.runtime.unit.UnitCodecTest'`. Expected: all pass. Run the whole `:nqp-runtime:test` once (36 -> 40).

- [ ] **Step 7: Commit (nqp)**:
  ```
  Dispatch: the persisted program -- DispatchSlot schema and DispatchSlotCodec (Phase C)
  ```

