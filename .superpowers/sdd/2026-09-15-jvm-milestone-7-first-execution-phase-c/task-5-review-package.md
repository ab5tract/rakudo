3d0b54fa4 Unit artifact: UnitDispatchWriter rewrites a unit's dispatch slots in place; NQP_DISPATCH_RECORD trains at exit (Phase C)
 .../nqp/runtime/unit/UnitDispatchWriterTest.kt     | 48 +++++++++++++
 .../org/raku/nqp/dispatch/DispatchPersist.kt       | 49 ++++++++++++-
 .../raku/nqp/runtime/unit/UnitDispatchWriter.kt    | 84 ++++++++++++++++++++++
 .../org/raku/nqp/runtime/unit/UnitImageWriter.kt   |  4 +-
 .../runtime/org/raku/nqp/runtime/unit/UnitStore.kt |  8 +++
 5 files changed, 191 insertions(+), 2 deletions(-)
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
diff --git a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt
index 99eafaa2d..0157432c3 100644
--- a/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt
+++ b/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt
@@ -8,52 +8,59 @@ import org.raku.nqp.runtime.unit.UnitCodec
 import org.raku.nqp.runtime.unit.UnitStore
 
 /**
  * The persisted miss (milestone 7 Phase C): a site's first miss restores
  * the programs its unit.dispatch slot holds before anything is recorded.
  *
  * NQP_DISPATCH_PERSIST: unset or "on" consumes slots; "off" ignores them;
  * "verify" restores into DispatchCallSite.verifyPrograms without installing,
  * records fresh, and compares (see verify). NQP_DISPATCH_RECORD ("all" or
  * a comma-separated list of store-name prefixes) makes the process rewrite
- * the selected artifacts' slots at exit (recordAtExit, Task 5).
+ * the selected artifacts' slots at exit (recordAtExit).
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
 
+    /** NQP_DISPATCH_RECORD: "all", or comma-separated store-name prefixes. */
+    private val recordSelector: List<String>? = System.getenv("NQP_DISPATCH_RECORD")?.split(',')?.map { it.trim() }?.filter { it.isNotEmpty() }
+
+    private fun selected(storeName: String): Boolean =
+        recordSelector!!.any { it == "all" || storeName.startsWith(it) }
+
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
+        if (recordSelector != null) Runtime.getRuntime().addShutdownHook(Thread { recordAtExit() })
     }
 
     @JvmStatic
     fun register(namespace: String, store: UnitStore) { stores.putIfAbsent(namespace, store) }
 
     fun store(namespace: String): UnitStore? = stores[namespace]
 
     /** The slot's programs realised against this process, empty when the
      *  site is anonymous, the slot empty, or nothing resolves. */
     fun restore(tc: ThreadContext, site: DispatchCallSite): List<DispatchProgram> {
@@ -84,11 +91,51 @@ object DispatchPersist {
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
 }
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
@@ -28,21 +28,23 @@ object UnitImageWriter {
             for ((id, n) in image.nested) {
                 for (suffix in listOf(".index", ".records", ".programs", ".dispatch")) {
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
 
     private fun encode(image: UnitImage): Encoded {
diff --git a/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitStore.kt b/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitStore.kt
index 23e502749..70584e3e0 100644
--- a/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitStore.kt
+++ b/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitStore.kt
@@ -79,20 +79,28 @@ class UnitStore private constructor(
         if (magic != MAGIC) throw IllegalStateException("unit artifact $name: bad magic ${Integer.toHexString(magic)}")
         if (version != VERSION) throw IllegalStateException("unit artifact $name: version $version, this runtime reads $VERSION")
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
 
     private fun blockRow(qbid: Int, field: Int): Int {
