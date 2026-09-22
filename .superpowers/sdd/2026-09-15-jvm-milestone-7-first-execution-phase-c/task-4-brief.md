## Task 4: The site address, the consumer, verify mode, the counters

**Files:**
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchBootstrap.kt` (`DispatchCallSite` fields; `created`)
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/Dispatch.kt` (`fallback`, `record`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt` (register), `UnitStore.kt` (`entryPrefix`, `absoluteSlot`)
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java:824-840` (`EngineSite`), `NqpProgramBuilder.java:575-576`
- Modify: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt:589-597` (stats line)
- Test: `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchPersistTest.kt`

**Interfaces:**
- Consumes: Task 3's `DispatchSlotCodec`, `DispatchSlot`; `UnitStore.dispatchSlot`;
  `ProgramUnit.identityNamespace()`; `ProgramIdentity` (`namespace`, `programIndex`).
- Produces: `DispatchCallSite.unitNamespace: String?`, `.programIndex: Int`,
  `.ordinal: Int`, `.restored: Boolean`, `.verifyPrograms: List<DispatchProgram>?`;
  `DispatchPersist.register(namespace: String, store: UnitStore)`,
  `.store(namespace): UnitStore?`, `.restore(tc, site): List<DispatchProgram>`,
  `.mode`, the counters `restored`, `restoredSites`, `dropped`,
  `recorded`, `verifyMatched`, `verifyMismatched`, `verifyUnseen` (AtomicLong);
  `UnitStore.entryPrefix: String`, `UnitStore.absoluteSlot(programIndex, ordinal): Int`;
  `DispatchBootstrap.created: AtomicLong`.

- [ ] **Step 1: `UnitStore`** — add after `dispatchSlotCount`:
  ```kotlin
  /** "unit" or "nested/<id>": the entry-name prefix this store reads, for the writer. */
  val entryPrefix: String get() = prefix

  /** The absolute slot index of (program, ordinal) in this unit's table, or -1. */
  fun absoluteSlot(programIndex: Int, ordinal: Int): Int {
      if (programIndex < 0 || programIndex >= header.programCount) return -1
      if (ordinal < 0 || ordinal >= programRow(programIndex, 3)) return -1
      val slot = programRow(programIndex, 2) + ordinal
      return if (slot in 0 until header.dispatchSlotCount) slot else -1
  }
  ```
  and make `dispatchSlot` compute `slot` through `absoluteSlot` (return
  null on -1) and reject `off < 0` next to the `off + len` check (ruling 12).

- [ ] **Step 2: `DispatchCallSite`** — after `identity` add:
  ```kotlin
  /** Where the site's unit.dispatch slot is: the unit's identity namespace
   *  (DispatchPersist maps it to the store), the program index and the
   *  ordinal. -1/null for an anonymous site. Set once at construction. */
  @JvmField var unitNamespace: String? = null
  @JvmField var programIndex: Int = -1
  @JvmField var ordinal: Int = -1
  /** The slot has been consulted once for this site's current life; reset()
   *  clears it, so an eval-server run re-arms from the slot. */
  @JvmField var restored: Boolean = false
  /** verify mode only: the realised persisted programs, kept aside. */
  @JvmField var verifyPrograms: List<DispatchProgram>? = null
  ```
  In `reset()`: `restored = false; verifyPrograms = null`. In `init` (a
  new block at the top of the class body): `DispatchBootstrap.created.incrementAndGet()`.
  In `object DispatchBootstrap`: `@JvmField val created = java.util.concurrent.atomic.AtomicLong()`.

- [ ] **Step 3: Write the failing test** `DispatchPersistTest.kt`:
  ```kotlin
  package org.raku.nqp.dispatch

  import java.lang.invoke.MethodType
  import java.nio.ByteBuffer
  import kotlin.test.Test
  import kotlin.test.assertEquals
  import kotlin.test.assertTrue
  import org.raku.nqp.runtime.CallSiteDescriptor
  import org.raku.nqp.runtime.unit.ProgramUnitTestSupport
  import org.raku.nqp.runtime.unit.UnitCodec
  import org.raku.nqp.runtime.unit.UnitImage
  import org.raku.nqp.runtime.unit.UnitImageWriter
  import org.raku.nqp.runtime.unit.UnitStore

  class DispatchPersistTest {
      /** The shared fixture's image with slot 1 (program 0, ordinal 1) filled. */
      private fun storeWith(slot: ByteArray): UnitStore {
          val base = ProgramUnitTestSupport.image()
          val img = UnitImage(base.unitId, base.hll, base.scHandle, base.scDesc, base.serializedCodeRefCount,
              base.mainlineQbid, base.entryQbid, base.deserializeQbid, base.loadQbid, base.blocks, base.programs,
              base.dispatchCounts, base.serialized, base.nested, mapOf(1 to slot))
          return UnitStore.open(ByteBuffer.wrap(UnitImageWriter.bytes(img)), "/x/fixture.jar")
      }

      @Test fun restoreRealisesTheSlotsProgramsAndCountsThem() {
          val tc = ProgramUnitTestSupport.tc()
          val knowhow = tc.gc.KnowHOW!!
          val csd = CallSiteDescriptor(byteArrayOf(CallSiteDescriptor.ARG_OBJ), null)
          val p = DispatchProgram(csd, listOf(Guard.OfType(ValueSource.Arg(0), knowhow.st)),
              Outcome.Value(ValueSource.Arg(0)), emptyList(), ResumeKind.NONE, emptyList(), null)
          val bytes = UnitCodec.encode(DispatchSlot.serializer(), DispatchSlot(listOf(DispatchSlotCodec.persist(p)!!)))
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
  }
  ```
  (`UnitImage`'s constructor order is that of `UnitImage.kt`; the fixture's
  program 0 has two slots, so absolute slot 1 is ordinal 1 of program 0.)

- [ ] **Step 4: Run it, expect a compile failure** (`DispatchPersist`):
  `./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.dispatch.DispatchPersistTest' -q`

- [ ] **Step 5: Write `DispatchPersist.kt`**:
  ```kotlin
  package org.raku.nqp.dispatch

  import java.util.concurrent.ConcurrentHashMap
  import java.util.concurrent.atomic.AtomicLong
  import org.raku.nqp.runtime.CallSiteDescriptor
  import org.raku.nqp.runtime.ThreadContext
  import org.raku.nqp.runtime.unit.UnitCodec
  import org.raku.nqp.runtime.unit.UnitStore

  /**
   * The persisted miss (milestone 7 Phase C): a site's first miss restores
   * the programs its unit.dispatch slot holds before anything is recorded.
   *
   * NQP_DISPATCH_PERSIST: unset or "on" consumes slots; "off" ignores them;
   * "verify" restores into DispatchCallSite.verifyPrograms without installing,
   * records fresh, and compares (see verify). NQP_DISPATCH_RECORD ("all" or
   * a comma-separated list of store-name prefixes) makes the process rewrite
   * the selected artifacts' slots at exit (recordAtExit, Task 5).
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

      private val stores = ConcurrentHashMap<String, UnitStore>()

      @JvmField val restored = AtomicLong()
      @JvmField val restoredSites = AtomicLong()
      @JvmField val dropped = AtomicLong()
      @JvmField val recorded = AtomicLong()
      @JvmField val verifyMatched = AtomicLong()
      @JvmField val verifyMismatched = AtomicLong()
      @JvmField val verifyUnseen = AtomicLong()

      init {
          if (mode == Mode.VERIFY) {
              System.err.println("dispatch-verify: on")
              Runtime.getRuntime().addShutdownHook(Thread {
                  System.err.println("dispatch-verify: matched=$verifyMatched mismatched=$verifyMismatched unseen=$verifyUnseen")
              })
          }
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
          val out = ArrayList<DispatchProgram>(slot.programs.size)
          for (p in slot.programs) {
              val r = DispatchSlotCodec.realise(tc, p)
              if (r == null) dropped.incrementAndGet() else out.add(r)
          }
          if (out.isNotEmpty()) { restored.addAndGet(out.size.toLong()); restoredSites.incrementAndGet() }
          return out
      }

      /** verify mode: after a fresh recording, every kept-aside program that
       *  applies to the recorded call must read the same as the recording. */
      fun verify(tc: ThreadContext, site: DispatchCallSite, recorded: DispatchProgram,
                 descriptor: CallSiteDescriptor, args: Array<Any?>) {
          val kept = site.verifyPrograms ?: return
          val ctx = Dispatch.guardContext(tc, descriptor, args)
          var applicable = 0
          val text = DispatchDump.describe(recorded)
          for (p in kept) {
              if (!Captures.sameShape(p.descriptor, descriptor) || !p.guardsMatch(ctx)) continue
              applicable++
              val theirs = DispatchDump.describe(p)
              if (theirs == text) verifyMatched.incrementAndGet()
              else {
                  verifyMismatched.incrementAndGet()
                  System.err.println("dispatch-verify: MISMATCH ${site.identity} ${site.linkedName}\n  persisted: $theirs\n  recorded:  $text")
              }
          }
          if (applicable == 0) verifyUnseen.incrementAndGet()
      }
  }
  ```
  `Dispatch.guardContext` is new: in `Dispatch.kt` add
  `internal fun guardContext(tc: ThreadContext, descriptor: CallSiteDescriptor, args: Array<Any?>): DispatchContext = GuardCheckContext(tc, descriptor, args)`
  (the class is private; the function keeps it so). `Captures.sameShape`
  is what `run` uses at `Dispatch.kt:352`.

- [ ] **Step 6: The consumer in `Dispatch.fallback`** — after the
  interpreted-tail loop and before `val registry = tc.gc.dispatchers`:
  ```kotlin
  /* First miss of this site's life: the persisted programs, if any,
   * before a recording (milestone 7 Phase C). */
  if (!site.restored && site.unitNamespace != null) {
      site.restored = true
      when (DispatchPersist.mode) {
          DispatchPersist.Mode.ON -> {
              val persisted = DispatchPersist.restore(tc, site)
              if (persisted.isNotEmpty()) {
                  for (p in persisted) site.install(p)
                  val ctx = GuardCheckContext(tc, descriptor, args)
                  for (p in persisted) if (run(tc, ctx, p, site)) return
              }
          }
          DispatchPersist.Mode.VERIFY -> site.verifyPrograms = DispatchPersist.restore(tc, site)
          DispatchPersist.Mode.OFF -> {}
      }
  }
  ```
  In `record`, replace the install line pair with:
  ```kotlin
  DispatchPersist.recorded.incrementAndGet()
  if (bindFailureOf != null)
      bindFailureOf.program!!.bindFailureProgram = program
  else if (site != null && !record.doNotInstall)
      site.install(program)
  if (site != null && DispatchPersist.mode == DispatchPersist.Mode.VERIFY)
      DispatchPersist.verify(tc, site, program, descriptor, args)
  ```

- [ ] **Step 7: Registration and the site address.** In
  `ProgramUnit.initializeCompilationUnit`, after `gc = tc.gc`:
  `identityNamespace()?.let { org.raku.nqp.dispatch.DispatchPersist.register(it, store) }`.
  In `NqpOps.java`, change `EngineSite`'s constructor to
  `EngineSite(CallSiteDescriptor csd, ProgramIdentity identity, int ordinal)`:
  ```java
  this.site = new DispatchCallSite(MethodType.methodType(void.class));
  if (identity != null) {
      this.site.identity = identity.siteKey(ordinal);
      this.site.unitNamespace = identity.getNamespace();
      this.site.programIndex = identity.getProgramIndex();
      this.site.ordinal = ordinal;
  }
  ```
  and in `NqpProgramBuilder.java:575` pass `new NqpOps.EngineSite(csd, identity, ordinal)`
  (`ProgramIdentity` is imported there already for `identity.siteKey`).

- [ ] **Step 8: The stats line** (`NqpDispatch.kt` shutdown hook): append
  `" sitesAll=" + DispatchBootstrap.created + " restored=" + DispatchPersist.restored + " restoredSites=" + DispatchPersist.restoredSites + " dropped=" + DispatchPersist.dropped + " recorded=" + DispatchPersist.recorded`
  after `" anon=" + anonSites` (imports `org.raku.nqp.dispatch.DispatchBootstrap`,
  `org.raku.nqp.dispatch.DispatchPersist`).

- [ ] **Step 9: Tests and a smoke.** Run Step 4's command: pass. Rebuild
  the runtime jars; then `NQP_DISPATCH_STATS=1 RAKUDO_RAKUAST=1 ./rakudo-j -e '' 2>&1 | grep 'dispatch stats:'`
  Expected: the line carries `sitesAll=`, `restored=0 restoredSites=0
  dropped=0 recorded=` with `recorded` close to 5023 (no slot is filled
  yet). Then `NQP_DISPATCH_PERSIST=verify ... 2>&1 | grep dispatch-verify`
  Expected: `dispatch-verify: on` and `dispatch-verify: matched=0 mismatched=0 unseen=N`.
  Record `sitesAll - sites` (the runtime-made site count) in the ledger.

- [ ] **Step 10: Commit (nqp)**:
  ```
  Dispatch: restore a site's persisted programs at its first miss; verify mode; the counters (Phase C)
  ```

