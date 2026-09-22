## Task 5: The recorder and the artifact rewriter

**Files:**
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitDispatchWriter.kt`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitImageWriter.kt` (`put` internal),
  `UnitStore.kt` (init check of slot windows)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt` (`recordAtExit`)
- Test: `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitDispatchWriterTest.kt`

**Interfaces:**
- Consumes: `DispatchBootstrap.sites()`, `DispatchSlotCodec.persist`,
  `DispatchDump.describe`, `UnitStore.entryPrefix/absoluteSlot/name`,
  `ZipDirectory.read`, `UnitCodec`, `UnitHeader`.
- Produces: `UnitDispatchWriter.rewrite(path: String, slots: Map<String, Map<Int, ByteArray>>)`
  (outer key = entry prefix `"unit"` or `"nested/<id>"`, inner key =
  absolute slot index); `DispatchPersist.recordAtExit()` installed from
  `DispatchPersist`'s init when `NQP_DISPATCH_RECORD` is set.

- [ ] **Step 1: Write the failing test**:
  ```kotlin
  package org.raku.nqp.runtime.unit

  import java.io.File
  import java.nio.ByteBuffer
  import kotlin.test.Test
  import kotlin.test.assertContentEquals
  import kotlin.test.assertEquals
  import kotlin.test.assertFailsWith
  import kotlin.test.assertNotNull
  import kotlin.test.assertNull

  class UnitDispatchWriterTest {
      private fun bytesOf(b: ByteBuffer) = ByteArray(b.remaining()).also { b.duplicate().get(it) }

      @Test fun fillsTheNamedSlotsKeepsTheRestAndCopiesEveryOtherEntry() {
          val nestedStore = UnitStore.open(ByteBuffer.wrap(UnitImageWriter.bytes(ProgramUnitTestSupport.image())), "<n>")
          val image = ProgramUnitTestSupport.image(nested = mapOf("n1" to nestedStore))
          val f = File.createTempFile("unit-", ".jar"); f.deleteOnExit()
          f.writeBytes(UnitImageWriter.bytes(UnitImage(image.unitId, image.hll, image.scHandle, image.scDesc,
              image.serializedCodeRefCount, image.mainlineQbid, image.entryQbid, image.deserializeQbid, image.loadQbid,
              image.blocks, image.programs, image.dispatchCounts, image.serialized, image.nested, mapOf(0 to byteArrayOf(1, 2, 3)))))
          val before = UnitStore.open(f.path)
          val recordsBefore = bytesOf(before.entry(UnitStore.RECORDS)!!)
          val serializedBefore = bytesOf(before.entry(UnitStore.SERIALIZED)!!)

          UnitDispatchWriter.rewrite(f.path, mapOf(
              "unit" to mapOf(2 to byteArrayOf(9, 9)),          // program 2, ordinal 0
              "nested/n1" to mapOf(1 to byteArrayOf(4, 5, 6))))   // program 0, ordinal 1 of the nested unit

          val after = UnitStore.open(f.path)
          assertContentEquals(byteArrayOf(1, 2, 3), bytesOf(assertNotNull(after.dispatchSlot(0, 0))), "an unnamed slot keeps its bytes")
          assertNull(after.dispatchSlot(0, 1), "an unnamed empty slot stays empty")
          assertContentEquals(byteArrayOf(9, 9), bytesOf(assertNotNull(after.dispatchSlot(2, 0))))
          assertContentEquals(byteArrayOf(4, 5, 6), bytesOf(assertNotNull(after.nested("n1")!!.dispatchSlot(0, 1))))
          assertContentEquals(recordsBefore, bytesOf(after.entry(UnitStore.RECORDS)!!))
          assertContentEquals(serializedBefore, bytesOf(after.entry(UnitStore.SERIALIZED)!!))
          assertEquals(before.header.dispatchSlotCount, after.header.dispatchSlotCount)
          assertEquals(PROG2_TEXT, after.program(2))
      }

      @Test fun refusesASlotOutsideTheTable() {
          val f = File.createTempFile("unit-", ".jar"); f.deleteOnExit()
          f.writeBytes(UnitImageWriter.bytes(ProgramUnitTestSupport.image()))
          assertFailsWith<IllegalArgumentException> { UnitDispatchWriter.rewrite(f.path, mapOf("unit" to mapOf(3 to byteArrayOf(1)))) }
      }

      companion object { val PROG2_TEXT = ProgramUnitTestSupport.PROG2 }
  }
  ```

- [ ] **Step 2: Run, expect compile failure**: `./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.runtime.unit.UnitDispatchWriterTest' -q`

- [ ] **Step 3: Write `UnitDispatchWriter.kt`**:
  ```kotlin
  package org.raku.nqp.runtime.unit

  import java.io.ByteArrayOutputStream
  import java.io.File
  import java.nio.ByteBuffer
  import java.nio.ByteOrder
  import java.nio.file.Files
  import java.nio.file.StandardCopyOption
  import java.util.zip.ZipOutputStream

  /**
   * Rewrites the dispatch slots of a unit artifact in place (milestone 7
   * Phase C, the training run): for every unit in the file whose entry
   * prefix is named ("unit", "nested/<id>"), the named slots get their
   * bytes, every other slot keeps what it had, the .index slot rows are
   * repointed and the .dispatch entry rebuilt; every other entry is copied
   * byte for byte. The result goes to <path>.tmp and is renamed over the
   * original, so a process that has the old file mapped keeps reading the
   * old inode.
   */
  object UnitDispatchWriter {
      fun rewrite(path: String, slots: Map<String, Map<Int, ByteArray>>) {
          val file = File(path)
          val whole = ByteBuffer.wrap(file.readBytes()).order(ByteOrder.LITTLE_ENDIAN)
          val dir = ZipDirectory.read(whole, path)
          val patched = HashMap<String, Pair<ByteArray, ByteArray>>()   // prefix -> (index, dispatch)
          for ((prefix, newSlots) in slots) {
              val index = dir["$prefix.index"] ?: throw IllegalArgumentException("$path: no $prefix.index entry to patch")
              val dispatch = dir["$prefix.dispatch"] ?: throw IllegalArgumentException("$path: no $prefix.dispatch entry to patch")
              patched[prefix] = patch(path, prefix, whole.slice(index.offset, index.size).order(ByteOrder.LITTLE_ENDIAN),
                  whole.slice(dispatch.offset, dispatch.size), newSlots)
          }
          val out = ByteArrayOutputStream(whole.capacity() + (1 shl 16))
          ZipOutputStream(out).use { z ->
              z.setMethod(ZipOutputStream.STORED)
              for ((name, e) in dir) {
                  val prefix = when {
                      name.endsWith(".index") -> name.removeSuffix(".index")
                      name.endsWith(".dispatch") -> name.removeSuffix(".dispatch")
                      else -> null
                  }
                  val p = prefix?.let { patched[it] }
                  val bytes = when {
                      p != null && name.endsWith(".index") -> p.first
                      p != null -> p.second
                      else -> ByteArray(e.size).also { whole.slice(e.offset, e.size).get(it) }
                  }
                  UnitImageWriter.put(z, name, bytes)
              }
          }
          val tmp = File(path + ".tmp")
          tmp.writeBytes(out.toByteArray())
          Files.move(tmp.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
      }

      /** The new (index, dispatch) of one unit: fixed-width slot rows in the
       *  index repointed into a dispatch entry rebuilt slot by slot. */
      private fun patch(path: String, prefix: String, index: ByteBuffer, oldDispatch: ByteBuffer,
                        newSlots: Map<Int, ByteArray>): Pair<ByteArray, ByteArray> {
          val headerLen = index.getInt(8)
          val header = UnitCodec.decode(UnitHeader.serializer(), index.slice(12, headerLen))
          val slotTable = 12 + headerLen + 16 * header.blockCount + 16 * header.programCount
          val n = header.dispatchSlotCount
          for (s in newSlots.keys) require(s in 0 until n) { "$path: $prefix dispatch slot $s of $n" }
          val bytes = ByteArray(index.remaining()).also { index.duplicate().get(it) }
          val idx = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
          val dispatch = ByteArrayOutputStream(oldDispatch.remaining() + newSlots.values.sumOf { it.size })
          for (s in 0 until n) {
              val row = slotTable + 8 * s
              val slot = newSlots[s] ?: run {
                  val off = idx.getInt(row); val len = idx.getInt(row + 4)
                  if (len == 0) null
                  else {
                      require(off >= 0 && off + len <= oldDispatch.remaining()) { "$path: $prefix dispatch slot $s at $off+$len past ${oldDispatch.remaining()}" }
                      ByteArray(len).also { oldDispatch.slice(off, len).get(it) }
                  }
              }
              if (slot == null) { idx.putInt(row, 0); idx.putInt(row + 4, 0); continue }
              idx.putInt(row, dispatch.size()); idx.putInt(row + 4, slot.size)
              dispatch.write(slot)
          }
          return bytes to dispatch.toByteArray()
      }
  }
  ```
  In `UnitImageWriter`, `private fun put` becomes `internal fun put`. In
  `UnitStore`'s `init`, after the `need` check, add the window check
  (ruling 12):
  ```kotlin
  for (i in 0 until header.programCount) {
      val first = index.getInt(programTable + 16 * i + 8); val count = index.getInt(programTable + 16 * i + 12)
      if (first < 0 || count < 0 || first + count > header.dispatchSlotCount)
          throw IllegalStateException("unit artifact $name: program $i claims dispatch slots $first+$count of ${header.dispatchSlotCount}")
  }
  ```

- [ ] **Step 4: The recorder** — in `DispatchPersist`:
  ```kotlin
  /** NQP_DISPATCH_RECORD: "all", or comma-separated store-name prefixes. */
  private val recordSelector: List<String>? = System.getenv("NQP_DISPATCH_RECORD")?.split(',')?.map { it.trim() }?.filter { it.isNotEmpty() }

  private fun selected(storeName: String): Boolean =
      recordSelector!!.any { it == "all" || storeName.startsWith(it) }

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
          val store = stores[ns] ?: continue
          if (!selected(store.name)) continue
          val slot = store.absoluteSlot(site.programIndex, site.ordinal)
          if (slot < 0) continue
          val byText = bySlot.getOrPut(store.name) { HashMap() }.getOrPut(store.entryPrefix) { HashMap() }.getOrPut(slot) { LinkedHashMap() }
          for (p in programs) byText.putIfAbsent(DispatchDump.describe(p), p)
      }
      for ((path, perPrefix) in bySlot) {
          var slots = 0; var written = 0; var unpersistable = 0
          val encoded = HashMap<String, Map<Int, ByteArray>>()
          for ((prefix, perSlot) in perPrefix) {
              val m = HashMap<Int, ByteArray>()
              for ((slot, byText) in perSlot) {
                  val persisted = ArrayList<PProgram>()
                  for (p in byText.values) {
                      val pp = DispatchSlotCodec.persist(p)
                      if (pp == null) unpersistable++ else if (persisted.size < Dispatch.MAX_PROGRAMS) persisted.add(pp)
                  }
                  if (persisted.isEmpty()) continue
                  m[slot] = UnitCodec.encode(DispatchSlot.serializer(), DispatchSlot(persisted))
                  slots++; written += persisted.size
              }
              if (m.isNotEmpty()) encoded[prefix] = m
          }
          if (encoded.isEmpty()) continue
          org.raku.nqp.runtime.unit.UnitDispatchWriter.rewrite(path, encoded)
          System.err.println("dispatch-record: wrote $slots slots ($written programs, $unpersistable unpersistable) to $path")
      }
  }
  ```
  and in the `init` block: `if (recordSelector != null) Runtime.getRuntime().addShutdownHook(Thread { recordAtExit() })`.
  The hook must run after the dump hook does not matter; both only read.
  The line `dispatch-record: wrote` is the build's positive marker.

- [ ] **Step 5: Run the writer test and the whole runtime suite**: pass.

- [ ] **Step 6: Commit (nqp)**:
  ```
  Unit artifact: UnitDispatchWriter rewrites a unit's dispatch slots in place; NQP_DISPATCH_RECORD trains at exit (Phase C)
  ```

