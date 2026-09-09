# JVM Unit Artifact, Milestone 1: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** nqp's stage2 jars become zip artifacts holding engine programs, the serialized context and a block table, with no class file, loaded by a reflection-free `ProgramUnit`, and t/nqp stays green through the runner. (The eval server is milestone 3's vehicle, user decision 2026-09-09; Task 4's road-agnostic app load keeps it working, nothing more.)

**Architecture:** A Kotlin `UnitFormat`/`UnitZip` pair defines the artifact; `ProgramUnit` (a `CompilationUnit` subclass) builds its code-ref table from the block table and enters every block through one shared Kotlin entry function; `LibraryLoader` picks the artifact road whenever a jar carries `unit.meta`, the class road otherwise (the bilingual switch). On the compiler side Compiler.nqp stays the driver: under `NQP_UNIT=1` it records the per-block fields it already has on the JAST record, and `HLL::Backend::JVM` hands that record to a Kotlin `UnitWriter` through a syscall instead of the bytecode assembler.

**Tech Stack:** Kotlin 2.4 (nqp-runtime, nqp-truffle), NQP (Compiler.nqp, TruffleEncoder.nqp, JASTNodes.nqp, HLL/Backend.nqp), gradle (nqp/build.gradle.kts, buildSrc), java.util.zip, lz4-java.

**Spec:** `docs/superpowers/specs/2026-09-09-jvm-unit-artifact-design.md` (rakudo worktree). Read it first; this plan argues from it.

## Global Constraints

- Two git trees: rakudo root (this doc) and the nested `nqp/` tree. Every nqp path below is under `nqp/`; nqp git commands run as `cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git ...` in their own shell call (the worktree guard refuses `git -C nqp`).
- Kotlin, never Java, for new code (user rule). Existing Java files (`LibraryLoader.java`, `EvalServer.java`) get minimal edits.
- Every diagnostic print is env-gated (`System.getenv(...)` / `nqp::getenvhash()`); never a bare print.
- Wire-program changes must be additive (stage0 ships old programs). This plan adds no wire op.
- Framing is by byte, never by grapheme.
- Runtime-jar-only changes rebuild with `./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars` (~5-10 s) from the rakudo worktree root; a Compiler.nqp/encoder/JASTNodes/Backend change needs `./nqp/gradlew -p nqp clean buildJvm` (~10 min) through `raku tools/build/watched-run.raku`.
- Every build and run carries `RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1`; the artifact road additionally needs `NQP_UNIT=1`.
- `java` is Oracle GraalVM 25.2.4.
- One compile per change (forward only): no A/B builds. Timings of a green build are the next baseline.
- Commit trailer on every commit:
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01YRn8gLyZjirBAKS6urb3n4`

## Deviation from the spec, stated up front

The spec's writer section has nested BEGIN-time units written under `nested/` in milestone 1. They cannot be: a nested unit is a runtime compile, and runtime compiles produce class files until milestone 2. The format and loader handle nested units (Tasks 1, 3), but the writer refuses a unit that carries any (Task 7), naming them, so the milestone gate tells whether nqp's stage2 has one. If it does, milestone 2's in-memory road moves ahead of the gate.

Two rulings from Task 6's review supersede that task's text (the ledger in `.superpowers/sdd/` has the reasoning): the static-lexical-value rows are built right after the deserialize wrapper compiles (after `nqp::serialize`), not where `setup_blv` is skipped; and `NQP_UNIT` is all-or-nothing, so the fallback junction dies on the unit road instead of counting, and no unit falls back to the class road (a class file produced after the artifact-road decisions would be silently broken). Task 7's writer still checks `fallbacks`, which is now always 0.

## File structure

New, all under `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/` (package `org.raku.nqp.runtime.unit`, part of `:nqp-runtime`):

| file | responsibility |
|---|---|
| `UnitRecord.kt` | the in-memory record: `UnitMeta`, `BlockRec`, `CallSiteRec`, `LexValueRec`, `UnitRecord` |
| `UnitFormat.kt` | bytes <-> record for `unit.meta` and `unit.programs`; the one format version constant |
| `UnitZip.kt` | the zip envelope: entry names, write a record, read a record |
| `ProgramEntry.kt` | the shared block entry function and the method handle every artifact block binds |
| `ProgramUnit.kt` | the reflection-free `CompilationUnit` built from a record |
| `UnitLoader.kt` | file/buffer detection, record cache for shared loads, load-and-initialize |
| `UnitMain.kt` | the fixed entry main for runner scripts |
| `UnitWriter.kt` | JAST record -> `UnitRecord` -> zip file (the writer) |

New tests under `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/`: `UnitFormatTest.kt`, `ProgramUnitTest.kt`.

Modified: `CompilationUnit.kt`, `StaticCodeInfo.kt`, `CodeEngine.kt`, `LibraryLoader.java`, `Ops.kt`, `tools/EvalServer.java`, `dispatch/Syscalls.kt`, `jast2bc/JastClass.kt`, `jast2bc/JastMethod.kt`, `jast2bc/JASTCompiler.kt`, `nqp-truffle/.../NqpDispatch.kt`, `src/vm/jvm/QAST/JASTNodes.nqp`, `src/vm/jvm/QAST/Compiler.nqp`, `src/vm/jvm/QAST/TruffleEncoder.nqp`, `src/vm/jvm/HLL/Backend.nqp`, `nqp-runtime/build.gradle.kts`, `buildSrc/src/main/kotlin/GenerateRunnerTask.kt`, `tools/templates/jvm/nqp-j.in`, a new `t/nqp/123-unit-artifact.t`.

---

### Task 1: The artifact format and its round trip

**Files:**
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitRecord.kt`
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitFormat.kt`
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitZip.kt`
- Modify: `nqp/nqp-runtime/build.gradle.kts` (test dependencies and task)
- Test: `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitFormatTest.kt`

**Interfaces:**
- Produces: `UnitMeta`, `BlockRec`, `CallSiteRec`, `LexValueRec`, `UnitRecord` (data classes below); `UnitFormat.writeMeta(meta): ByteArray`, `UnitFormat.readMeta(bytes: ByteBuffer): UnitMeta`, `UnitFormat.writePrograms(programs: Array<String>): ByteArray` (LZ4), `UnitFormat.readPrograms(lz4: ByteBuffer): Array<String>`; `UnitZip.write(record, out: OutputStream)`, `UnitZip.read(bytes: ByteArray): UnitRecord`, `UnitZip.isUnit(bytes: ByteArray): Boolean`, constants `UnitZip.META = "unit.meta"`, `UnitZip.PROGRAMS = "unit.programs"`, `UnitZip.SERIALIZED = "unit.serialized.lz4"`, `UnitZip.NESTED_DIR = "nested/"`.

- [ ] **Step 1: Add the test task to nqp-runtime**

In `nqp/nqp-runtime/build.gradle.kts`, inside `dependencies { ... }` add:

```kotlin
    testImplementation(kotlin("test"))
```

and after the `tasks.jar { ... }` block add:

```kotlin
tasks.test {
    useJUnitPlatform()
}
```

The test source set keeps gradle's default location, `nqp-runtime/src/test/kotlin`; only `main` is remapped.

- [ ] **Step 2: Write the record classes**

`UnitRecord.kt`:

```kotlin
package org.raku.nqp.runtime.unit

/** One code-ref block of a unit, everything CodeRefAnnotation + the qb_<n>
 *  method name used to carry, plus the index of the block's program. */
class BlockRec(
    @JvmField val name: String,
    @JvmField val cuid: String?,          // written only for a nested unit
    @JvmField val outerQbid: Int,         // -1 = no outer
    @JvmField val oLex: Array<String>,
    @JvmField val iLex: Array<String>,
    @JvmField val nLex: Array<String>,
    @JvmField val sLex: Array<String>,
    @JvmField val handlers: LongArray,    // flat: [count, (len, fields...)*]
    @JvmField val hasExitHandler: Boolean,
    @JvmField val isThunk: Boolean,
    @JvmField val sourceFile: String?,
    @JvmField val sourceLine: Int,
    @JvmField val sourceLineDelta: Int,
    @JvmField val sectionRaw: IntArray?,
    @JvmField val sectionLine: IntArray?,
    @JvmField val sectionFile: Array<String>?,
    @JvmField val programIndex: Int,      // into UnitRecord.programs
)

class CallSiteRec(@JvmField val flags: ByteArray, @JvmField val names: Array<String>?)

class LexValueRec(
    @JvmField val qbid: Int,
    @JvmField val name: String,
    @JvmField val scHandle: String,
    @JvmField val scIdx: Int,
    @JvmField val flags: Int,
)

class UnitMeta(
    @JvmField val unitId: String,
    @JvmField val hll: String,
    @JvmField val scHandle: String?,
    @JvmField val scDesc: String?,
    @JvmField val serializedCodeRefCount: Int,
    @JvmField val mainlineQbid: Int,
    @JvmField val entryQbid: Int,
    @JvmField val deserializeQbid: Int,
    @JvmField val loadQbid: Int,
    @JvmField val callSites: List<CallSiteRec>,
    @JvmField val blocks: Array<BlockRec?>,   // indexed by qbid; null = gap
    @JvmField val staticLexValues: List<LexValueRec>,
    @JvmField val nestedIds: List<String>,
)

/** A whole unit as loaded: meta, programs (UTF-8 text each), the serialized
 *  context (decompressed; null for a nested unit), nested units by id. */
class UnitRecord(
    @JvmField val meta: UnitMeta,
    @JvmField val programs: Array<String>,
    @JvmField val serialized: ByteArray?,
    @JvmField val nested: Map<String, UnitRecord>,
)
```

- [ ] **Step 3: Write the failing round-trip test**

`UnitFormatTest.kt`:

```kotlin
package org.raku.nqp.runtime.unit

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class UnitFormatTest {
    private fun block(name: String, prog: Int, outer: Int = -1, cuid: String? = null) = BlockRec(
        name, cuid, outer,
        arrayOf("\$x", "naïve"), arrayOf("\$i"), arrayOf(), arrayOf("\$s"),
        longArrayOf(1, 3, 7, 8, 9), hasExitHandler = false, isThunk = true,
        sourceFile = "t/é.nqp", sourceLine = 12, sourceLineDelta = 3,
        sectionRaw = intArrayOf(20), sectionLine = intArrayOf(1), sectionFile = arrayOf("inc.nqp"),
        programIndex = prog,
    )

    private fun sample(): UnitRecord {
        val big = "x".repeat(70000) + "é"          // over a class-file constant's cap
        val nestedMeta = UnitMeta("nested1", "nqp", null, null, 0, 0, -1, -1, -1,
            listOf(), arrayOf(block("inner", 0, cuid = "cuid_inner")), listOf(), listOf())
        val nested = UnitRecord(nestedMeta, arrayOf("nqpp 1 0 0 0"), null, mapOf())
        val meta = UnitMeta(
            "ABC123", "nqp", "sc-handle", "desc 🎉", 3, 0, 2, 1, -1,
            listOf(CallSiteRec(byteArrayOf(1, 1), arrayOf("named")), CallSiteRec(byteArrayOf(), null)),
            arrayOf(block("<mainline>", 0), block("deser", 1, outer = 0), null, block("main", 2, outer = 0)),
            listOf(LexValueRec(0, "\$x", "sc-handle", 5, 1)),
            listOf("nested1"),
        )
        return UnitRecord(meta, arrayOf("nqpp 0", big, "nqpp 2  "), byteArrayOf(1, 2, 3, 255.toByte()), mapOf("nested1" to nested))
    }

    @Test
    fun metaRoundTrips() {
        val m = sample().meta
        val back = UnitFormat.readMeta(ByteBuffer.wrap(UnitFormat.writeMeta(m)))
        assertEquals("ABC123", back.unitId)
        assertEquals("desc 🎉", back.scDesc)
        assertEquals(4, back.blocks.size)
        assertNull(back.blocks[2])
        val b1 = back.blocks[1]!!
        assertEquals("deser", b1.name)
        assertEquals(0, b1.outerQbid)
        assertContentEquals(arrayOf("\$x", "naïve"), b1.oLex)
        assertContentEquals(longArrayOf(1, 3, 7, 8, 9), b1.handlers)
        assertTrue(b1.isThunk)
        assertEquals("t/é.nqp", b1.sourceFile)
        assertContentEquals(intArrayOf(20), b1.sectionRaw)
        assertEquals(1, b1.programIndex)
        assertEquals(2, back.callSites.size)
        assertContentEquals(arrayOf("named"), back.callSites[0].names)
        assertNull(back.callSites[1].names)
        assertEquals(5, back.staticLexValues[0].scIdx)
        assertEquals(listOf("nested1"), back.nestedIds)
    }

    @Test
    fun programsRoundTripByByte() {
        val progs = sample().programs
        val back = UnitFormat.readPrograms(ByteBuffer.wrap(UnitFormat.writePrograms(progs)))
        assertContentEquals(progs, back)
    }

    @Test
    fun zipRoundTrips() {
        val r = sample()
        val out = ByteArrayOutputStream()
        UnitZip.write(r, out)
        val bytes = out.toByteArray()
        assertTrue(UnitZip.isUnit(bytes))
        val back = UnitZip.read(bytes)
        assertEquals("ABC123", back.meta.unitId)
        assertContentEquals(r.programs, back.programs)
        assertContentEquals(r.serialized, back.serialized)
        assertEquals(1, back.nested.size)
        assertEquals("inner", back.nested["nested1"]!!.meta.blocks[0]!!.name)
        assertEquals("cuid_inner", back.nested["nested1"]!!.meta.blocks[0]!!.cuid)
        assertNull(back.nested["nested1"]!!.serialized)
    }

    @Test
    fun unknownVersionIsAHardError() {
        val bytes = UnitFormat.writeMeta(sample().meta)
        bytes[4] = 99   // the version int's low byte, right after the magic
        val e = runCatching { UnitFormat.readMeta(ByteBuffer.wrap(bytes)) }.exceptionOrNull()
        assertTrue(e is IllegalStateException && e.message!!.contains("version"))
    }

    @Test
    fun nonUnitBytesAreNotAUnit() {
        assertFalse(UnitZip.isUnit(byteArrayOf(0xCA.toByte(), 0xFE.toByte(), 0xBA.toByte(), 0xBE.toByte())))
    }
}
```

- [ ] **Step 4: Run the test to see it fail**

Run from the rakudo worktree root: `./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.runtime.unit.UnitFormatTest' 2>&1 | tail -20`
Expected: compilation failure, `Unresolved reference: UnitFormat`.

- [ ] **Step 5: Write UnitFormat**

`UnitFormat.kt`:

```kotlin
package org.raku.nqp.runtime.unit

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import net.jpountz.lz4.LZ4Factory
import net.jpountz.lz4.LZ4CompressorWithLength
import net.jpountz.lz4.LZ4DecompressorWithLength

/**
 * The unit artifact's binary sections. Little-endian, fixed-width ints,
 * strings as a byte length (-1 for null) plus UTF-8 bytes: framing is by
 * BYTE, never by grapheme (the .codeprograms.lz4 sidecar framed by
 * nqp::chars and paid for it with a reader bug and an O(n^2) fix).
 */
object UnitFormat {
    const val MAGIC = 0x5550514E            // "NQPU" as little-endian bytes
    const val VERSION = 1

    private val lz4c = LZ4CompressorWithLength(LZ4Factory.safeInstance().highCompressor(8))
    private val lz4d = LZ4DecompressorWithLength(LZ4Factory.safeInstance().fastDecompressor())

    private class Out {
        val bytes = ByteArrayOutputStream()
        fun int(v: Int) { bytes.write(v); bytes.write(v ushr 8); bytes.write(v ushr 16); bytes.write(v ushr 24) }
        fun long(v: Long) { int(v.toInt()); int((v ushr 32).toInt()) }
        fun bool(v: Boolean) = bytes.write(if (v) 1 else 0)
        fun str(s: String?) {
            if (s == null) { int(-1); return }
            val b = s.toByteArray(Charsets.UTF_8); int(b.size); bytes.write(b)
        }
        fun strs(a: Array<String>?) { if (a == null) int(-1) else { int(a.size); for (s in a) str(s) } }
        fun ints(a: IntArray?) { if (a == null) int(-1) else { int(a.size); for (v in a) int(v) } }
        fun longs(a: LongArray) { int(a.size); for (v in a) long(v) }
        fun bytesOf(a: ByteArray) { int(a.size); bytes.write(a) }
    }

    private class In(val bb: ByteBuffer) {
        init { bb.order(ByteOrder.LITTLE_ENDIAN) }
        fun int() = bb.getInt()
        fun long() = bb.getLong()
        fun bool() = bb.get().toInt() != 0
        fun str(): String? { val n = int(); if (n < 0) return null; val b = ByteArray(n); bb.get(b); return String(b, Charsets.UTF_8) }
        fun strs(): Array<String>? { val n = int(); if (n < 0) return null; return Array(n) { str()!! } }
        fun ints(): IntArray? { val n = int(); if (n < 0) return null; return IntArray(n) { int() } }
        fun longs(): LongArray { val n = int(); return LongArray(n) { long() } }
        fun bytesOf(): ByteArray { val n = int(); val b = ByteArray(n); bb.get(b); return b }
    }

    @JvmStatic
    fun writeMeta(m: UnitMeta): ByteArray {
        val o = Out()
        o.int(MAGIC); o.int(VERSION)
        o.str(m.unitId); o.str(m.hll); o.str(m.scHandle); o.str(m.scDesc)
        o.int(m.serializedCodeRefCount)
        o.int(m.mainlineQbid); o.int(m.entryQbid); o.int(m.deserializeQbid); o.int(m.loadQbid)
        o.int(m.callSites.size)
        for (cs in m.callSites) { o.bytesOf(cs.flags); o.strs(cs.names) }
        o.int(m.blocks.size)
        for (b in m.blocks) {
            if (b == null) { o.bool(false); continue }
            o.bool(true)
            o.str(b.name); o.str(b.cuid); o.int(b.outerQbid)
            o.strs(b.oLex); o.strs(b.iLex); o.strs(b.nLex); o.strs(b.sLex)
            o.longs(b.handlers); o.bool(b.hasExitHandler); o.bool(b.isThunk)
            o.str(b.sourceFile); o.int(b.sourceLine); o.int(b.sourceLineDelta)
            o.ints(b.sectionRaw); o.ints(b.sectionLine); o.strs(b.sectionFile)
            o.int(b.programIndex)
        }
        o.int(m.staticLexValues.size)
        for (v in m.staticLexValues) { o.int(v.qbid); o.str(v.name); o.str(v.scHandle); o.int(v.scIdx); o.int(v.flags) }
        o.strs(m.nestedIds.toTypedArray())
        return o.bytes.toByteArray()
    }

    @JvmStatic
    fun readMeta(bytes: ByteBuffer): UnitMeta {
        val i = In(bytes)
        check(i.int() == MAGIC) { "not a unit artifact: bad magic in unit.meta" }
        val version = i.int()
        check(version == VERSION) { "unit.meta format version $version, this runtime reads version $VERSION" }
        val unitId = i.str()!!; val hll = i.str()!!; val scHandle = i.str(); val scDesc = i.str()
        val count = i.int()
        val mainline = i.int(); val entry = i.int(); val deser = i.int(); val load = i.int()
        val callSites = List(i.int()) { CallSiteRec(i.bytesOf(), i.strs()) }
        val blocks = arrayOfNulls<BlockRec>(i.int())
        for (q in blocks.indices) {
            if (!i.bool()) continue
            blocks[q] = BlockRec(
                i.str()!!, i.str(), i.int(),
                i.strs()!!, i.strs()!!, i.strs()!!, i.strs()!!,
                i.longs(), i.bool(), i.bool(),
                i.str(), i.int(), i.int(),
                i.ints(), i.ints(), i.strs(),
                i.int(),
            )
        }
        val lex = List(i.int()) { LexValueRec(i.int(), i.str()!!, i.str()!!, i.int(), i.int()) }
        val nested = i.strs()!!.toList()
        return UnitMeta(unitId, hll, scHandle, scDesc, count, mainline, entry, deser, load, callSites, blocks, lex, nested)
    }

    @JvmStatic
    fun writePrograms(programs: Array<String>): ByteArray {
        val o = Out()
        o.int(programs.size)
        for (p in programs) o.bytesOf(p.toByteArray(Charsets.UTF_8))
        return lz4c.compress(o.bytes.toByteArray())
    }

    @JvmStatic
    fun readPrograms(lz4: ByteBuffer): Array<String> {
        val raw = ByteArray(lz4.remaining()); lz4.get(raw)
        val i = In(ByteBuffer.wrap(lz4d.decompress(raw)))
        return Array(i.int()) { String(i.bytesOf(), Charsets.UTF_8) }
    }

    @JvmStatic
    fun compress(bytes: ByteArray): ByteArray = lz4c.compress(bytes)

    @JvmStatic
    fun decompress(bytes: ByteArray): ByteArray = lz4d.decompress(bytes)
}
```

- [ ] **Step 6: Write UnitZip**

`UnitZip.kt`:

```kotlin
package org.raku.nqp.runtime.unit

import java.io.ByteArrayInputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

/** The envelope: a zip with fixed entry names and no class entries. */
object UnitZip {
    const val META = "unit.meta"
    const val PROGRAMS = "unit.programs"
    const val SERIALIZED = "unit.serialized.lz4"
    const val NESTED_DIR = "nested/"
    private const val NESTED_META = ".meta"
    private const val NESTED_PROGRAMS = ".programs"

    @JvmStatic
    fun write(r: UnitRecord, out: OutputStream) {
        ZipOutputStream(out).use { z ->
            z.setLevel(1)
            put(z, META, UnitFormat.writeMeta(r.meta))
            put(z, PROGRAMS, UnitFormat.writePrograms(r.programs))
            r.serialized?.let { put(z, SERIALIZED, UnitFormat.compress(it)) }
            for ((id, n) in r.nested) {
                put(z, NESTED_DIR + id + NESTED_META, UnitFormat.writeMeta(n.meta))
                put(z, NESTED_DIR + id + NESTED_PROGRAMS, UnitFormat.writePrograms(n.programs))
            }
        }
    }

    private fun put(z: ZipOutputStream, name: String, bytes: ByteArray) {
        z.putNextEntry(ZipEntry(name)); z.write(bytes); z.closeEntry()
    }

    /** True when the bytes are a zip whose first entries include unit.meta.
     *  A class file (0xCAFEBABE) and a class-road jar answer false. */
    @JvmStatic
    fun isUnit(bytes: ByteArray): Boolean {
        if (bytes.size < 4 || bytes[0] != 'P'.code.toByte() || bytes[1] != 'K'.code.toByte()) return false
        return try {
            ZipInputStream(ByteArrayInputStream(bytes)).use { z ->
                var e = z.nextEntry
                while (e != null) { if (e.name == META) return true; e = z.nextEntry }
                false
            }
        } catch (t: Exception) { false }
    }

    @JvmStatic
    fun read(bytes: ByteArray): UnitRecord {
        var meta: UnitMeta? = null
        var programs: Array<String>? = null
        var serialized: ByteArray? = null
        val nestedMeta = HashMap<String, UnitMeta>()
        val nestedProgs = HashMap<String, Array<String>>()
        ZipInputStream(ByteArrayInputStream(bytes)).use { z ->
            var e = z.nextEntry
            while (e != null) {
                val data = z.readAllBytes()
                when {
                    e.name == META -> meta = UnitFormat.readMeta(ByteBuffer.wrap(data))
                    e.name == PROGRAMS -> programs = UnitFormat.readPrograms(ByteBuffer.wrap(data))
                    e.name == SERIALIZED -> serialized = UnitFormat.decompress(data)
                    e.name.startsWith(NESTED_DIR) && e.name.endsWith(NESTED_META) ->
                        nestedMeta[e.name.removePrefix(NESTED_DIR).removeSuffix(NESTED_META)] = UnitFormat.readMeta(ByteBuffer.wrap(data))
                    e.name.startsWith(NESTED_DIR) && e.name.endsWith(NESTED_PROGRAMS) ->
                        nestedProgs[e.name.removePrefix(NESTED_DIR).removeSuffix(NESTED_PROGRAMS)] = UnitFormat.readPrograms(ByteBuffer.wrap(data))
                    else -> throw IllegalStateException("unit artifact holds an unexpected entry: ${e.name}")
                }
                e = z.nextEntry
            }
        }
        val m = meta ?: throw IllegalStateException("unit artifact lacks $META")
        val p = programs ?: throw IllegalStateException("unit artifact ${m.unitId} lacks $PROGRAMS")
        val nested = HashMap<String, UnitRecord>()
        for (id in m.nestedIds) {
            val nm = nestedMeta[id] ?: throw IllegalStateException("unit ${m.unitId} names nested unit $id but carries no $NESTED_DIR$id$NESTED_META")
            val np = nestedProgs[id] ?: throw IllegalStateException("unit ${m.unitId} names nested unit $id but carries no $NESTED_DIR$id$NESTED_PROGRAMS")
            nested[id] = UnitRecord(nm, np, null, mapOf())
        }
        for (b in m.blocks) if (b != null && (b.programIndex < 0 || b.programIndex >= p.size))
            throw IllegalStateException("unit ${m.unitId}: block ${b.name} names program ${b.programIndex} of ${p.size}")
        for ((q, b) in m.blocks.withIndex()) if (b != null && b.outerQbid >= m.blocks.size)
            throw IllegalStateException("unit ${m.unitId}: block $q names outer qbid ${b.outerQbid} beyond the table")
        if (m.serializedCodeRefCount > m.blocks.size)
            throw IllegalStateException("unit ${m.unitId}: ${m.serializedCodeRefCount} serialized code refs, table of ${m.blocks.size}")
        return UnitRecord(m, p, serialized, nested)
    }
}
```

- [ ] **Step 7: Run the test to see it pass**

Run: `./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.runtime.unit.UnitFormatTest' 2>&1 | tail -20`
Expected: `BUILD SUCCESSFUL`, 5 tests passed. If the lz4 classes are missing from the test runtime classpath, they are in `NqpDeps.thirdParty` (already `implementation`), so that is a test-classpath misconfiguration, not a code error.

- [ ] **Step 8: Commit (nqp tree)**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git add nqp-runtime/build.gradle.kts src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitRecord.kt src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitFormat.kt src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitZip.kt nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitFormatTest.kt && git commit -F - <<'EOF'
unit artifact: the format (unit.meta, byte-framed programs, zip envelope) with a round trip

Plan items 5-6, milestone 1 (rakudo docs/superpowers/specs/2026-09-09-jvm-unit-artifact-design.md).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRn8gLyZjirBAKS6urb3n4
EOF
```

---

### Task 2: Runtime hooks and the shared block entry

**Files:**
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CompilationUnit.kt` (lines 185-199 `runDeserializeIfAvailable`, 392-404 `engineProgram`; add hooks)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/StaticCodeInfo.kt` (add `programIndex`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CodeEngine.kt` (add `materialize`, `codeRunUnit`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt:6512-6532` (deserialize reads `cu.serializedBlob()`), `:8959-9001` (claim through `cu.claimNested`)
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramEntry.kt`

**Interfaces:**
- Produces on `CompilationUnit`: `open fun engineProgram(idx: Int): String`, `open fun serializedBlob(): ByteBuffer?`, `open fun claimNested(tc: ThreadContext, name: String): CompilationUnit`, `open fun unitId(): String`, `open fun runDeserializeIfAvailable(tc)`.
- Produces on `StaticCodeInfo`: `@JvmField var programIndex: Int = -1`.
- Produces on `CodeEngines`: `@JvmStatic fun materialize(sci: StaticCodeInfo): Any?`, `@JvmStatic fun codeRunUnit(sci, cu, tc, cf, csd, args)`.
- Produces `ProgramEntry.ENTER: MethodHandle` of type `(ThreadContext, CodeRef, CallSiteDescriptor, ResumeStatus.Frame, Array<Any?>) -> Unit`.

- [ ] **Step 1: Hooks on CompilationUnit**

In `CompilationUnit.kt`, change `fun runDeserializeIfAvailable` (line 185) to `open fun runDeserializeIfAvailable`, change `fun engineProgram(idx: Int): String` (line 392) to `open fun engineProgram(idx: Int): String`, and add after `serializedCodeRefCount()` (line 380):

```kotlin
    /** The unit's identity string: the class's simple name on the class
     *  road, the artifact's unit id on the artifact road. Replaces the
     *  Class object wherever a unit was named. */
    open fun unitId(): String = javaClass.simpleName

    /** The serialized context, decompressed, or null when the unit has
     *  none. The class road reads it as a class resource; the artifact
     *  road holds it. */
    open fun serializedBlob(): java.nio.ByteBuffer? {
        val cuName = javaClass.simpleName
        var stream = javaClass.getResourceAsStream("$cuName.serialized.lz4")
        if (stream != null)
            return stream.use { LibraryLoader.readToHeapBufferLz4(it) }
        stream = javaClass.getResourceAsStream("$cuName.serialized") ?: return null
        return stream.use { LibraryLoader.readToHeapBuffer(it) }
    }

    /** Instantiates and initializes (without deserializing) the nested
     *  unit of the given name that rides in this unit. The class road
     *  loads it by class name through this unit's class loader. */
    open fun claimNested(tc: ThreadContext, name: String): CompilationUnit {
        val klass = Class.forName(name, true, javaClass.classLoader)
        @Suppress("DEPRECATION")
        val nested = klass.getDeclaredConstructor().newInstance() as CompilationUnit
        nested.shared = tc.gc.sharingHint
        nested.initializeCompilationUnit(tc, false)
        return nested
    }
```

- [ ] **Step 2: Route deserialize and claim through the hooks**

In `Ops.kt`, replace lines 6512-6532 (the `val binaryBlob: ByteBuffer` ... `catch (e: IOException)` block for `blob == null`) with:

```kotlin
        val binaryBlob: ByteBuffer
        if (blob == null)
            binaryBlob = cu.serializedBlob()
                ?: throw ExceptionHandling.dieInternal(tc, "unit ${cu.unitId()} has no serialized context to deserialize")
        else
```

keeping the existing `try { binaryBlob = Base64.decode(blob) } ... ` else-arm as it is. In `jvmclaimnested` (8959-9001) replace the three lines

```kotlin
            val klass = Class.forName(className, true, cu.javaClass.classLoader)
            val nested = klass.getDeclaredConstructor().newInstance() as CompilationUnit
            nested.shared = tc.gc.sharingHint
```

and the following `nested.initializeCompilationUnit(tc, false)` line with

```kotlin
            val nested = cu.claimNested(tc, className!!)
```

and widen the catch from `ReflectiveOperationException` to `Exception` so a missing nested artifact reports through the same `Could not load nested compilation unit` message. Also change the `IOException` import usage only if the compiler now flags it unused.

- [ ] **Step 3: programIndex and the materializing engine road**

In `StaticCodeInfo.kt` after `engineTarget` (line 72) add:

```kotlin
    /** On the artifact road: the block's program index in its unit, so
     *  the target can be materialized on demand (see CodeEngines.materialize)
     *  instead of waiting for a first run through a stub. -1 on the class road. */
    @JvmField var programIndex: Int = -1
```

In `CodeEngine.kt`, inside `object CodeEngines` after `codeRun` add:

```kotlin
    /**
     * The block's engine target, compiling its program from the unit on
     * first need. Null for a class-road block that has not run yet (no
     * program index) or when there is no engine. Synchronized on the
     * static info so two threads racing on the first call agree on one
     * target.
     */
    @JvmStatic
    fun materialize(sci: StaticCodeInfo): Any? {
        sci.engineTarget?.let { return it }
        if (sci.programIndex < 0) return null
        val engine = engine ?: return null
        synchronized(sci) {
            sci.engineTarget?.let { return it }
            val program = engine.compile(sci.compUnit.engineProgram(sci.programIndex))
            sci.engineTarget = program
            return program
        }
    }

    /** The artifact road's block body: what codeRunIdx is for a stub. */
    @JvmStatic
    fun codeRunUnit(
        sci: StaticCodeInfo,
        cu: CompilationUnit,
        tc: ThreadContext,
        cf: CallFrame,
        csd: CallSiteDescriptor,
        args: Array<Any?>?,
    ) {
        val engine = engine ?: throw IllegalStateException(
            "this unit was compiled with the code engine, which is not available at run time:" +
            " the truffle module is missing from the class path.")
        val program = materialize(sci) ?: throw IllegalStateException(
            "block ${cf.codeRef?.name ?: "<anon>"} of unit ${cu.unitId()} has no program")
        if (trace) System.err.println("code> " + (cf.codeRef?.name ?: "<anon>"))
        engine.run(program, cu, tc, cf, csd, args ?: emptyArray())
    }
```

- [ ] **Step 4: The entry function**

`ProgramEntry.kt`:

```kotlin
package org.raku.nqp.runtime.unit

import java.lang.invoke.MethodHandle
import java.lang.invoke.MethodHandles
import java.lang.invoke.MethodType
import org.raku.nqp.runtime.CallFrame
import org.raku.nqp.runtime.CallSiteDescriptor
import org.raku.nqp.runtime.CodeEngines
import org.raku.nqp.runtime.CodeRef
import org.raku.nqp.runtime.ControlException
import org.raku.nqp.runtime.ExceptionHandling
import org.raku.nqp.runtime.ResumeStatus
import org.raku.nqp.runtime.ThreadContext

/**
 * The one body every artifact block has: what Compiler.nqp's emitted
 * stub did around codeRunIdx (Compiler.nqp as_jast(QAST::Block),
 * prelude and postlude), as a function. Its handle has the shape
 * StaticCodeInfo's init expects of a bound stub, (tc, cr, csd, resume,
 * args), so the invoke road and the resume surgery are untouched;
 * `resume` is unused because an engine program resumes through its own
 * handle (NqpCodeEngine.RESUME).
 */
object ProgramEntry {
    @JvmStatic
    fun enter(tc: ThreadContext, cr: CodeRef, csd: CallSiteDescriptor,
              @Suppress("UNUSED_PARAMETER") resume: ResumeStatus.Frame?, args: Array<Any?>?) {
        val sci = cr.staticInfo
        val cf = CallFrame(tc, cr)
        try {
            CodeEngines.codeRunUnit(sci, sci.compUnit, tc, cf, csd, args)
        } catch (e: ControlException) {
            cf.leave()
            throw e
        } catch (e: Throwable) {
            throw ExceptionHandling.dieInternal(tc, e)
        }
        cf.leave()
    }

    @JvmField
    val ENTER: MethodHandle = MethodHandles.lookup().findStatic(
        ProgramEntry::class.java, "enter",
        MethodType.methodType(Void.TYPE, ThreadContext::class.java, CodeRef::class.java,
            CallSiteDescriptor::class.java, ResumeStatus.Frame::class.java, Array<Any?>::class.java))
}
```

Note: `StaticCodeInfo.init` rebinds `mh` per instance with `insertArguments`, so every block's `staticInfo.mh` is a distinct object even though all share `ENTER`; `CallFrame.outerFor`'s identity test (`CallFrame.kt:40`) therefore keeps working.

- [ ] **Step 5: Build the runtime jar**

Run: `./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars 2>&1 | tail -5`
Expected: `BUILD SUCCESSFUL`. Then a class-road smoke, since the class road must be untouched: `RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'say(1+2)'`
Expected: `3`.

- [ ] **Step 6: Commit (nqp tree)**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git add src/vm/jvm/runtime/org/raku/nqp/runtime/CompilationUnit.kt src/vm/jvm/runtime/org/raku/nqp/runtime/StaticCodeInfo.kt src/vm/jvm/runtime/org/raku/nqp/runtime/CodeEngine.kt src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramEntry.kt && git commit -F - <<'EOF'
unit artifact: unit hooks (serializedBlob, claimNested, engineProgram, unitId), materialized targets, the shared block entry

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRn8gLyZjirBAKS6urb3n4
EOF
```

---

### Task 3: ProgramUnit, the reflection-free unit

**Files:**
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt`
- Test: `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/ProgramUnitTest.kt`

**Interfaces:**
- Consumes: `UnitRecord` (Task 1), `ProgramEntry.ENTER`, `CodeEngines.materialize`, the hooks (Task 2).
- Produces: `class ProgramUnit(record: UnitRecord) : CompilationUnit()` with `fun buildTable(bootSt: STable?)` (the pure part, testable without a ThreadContext), the overrides of every generated hook, and `fun applyStaticLexValues(tc)`.

- [ ] **Step 1: Write the failing table test**

`ProgramUnitTest.kt`:

```kotlin
package org.raku.nqp.runtime.unit

import org.raku.nqp.runtime.ArgsExpectation
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

class ProgramUnitTest {
    private fun block(name: String, prog: Int, outer: Int, handlers: LongArray = longArrayOf(0)) = BlockRec(
        name, null, outer, arrayOf("\$a", "\$b"), arrayOf(), arrayOf(), arrayOf(),
        handlers, false, false, "u.nqp", 1, 0, null, null, null, prog)

    private fun unit(): ProgramUnit {
        val meta = UnitMeta("U1", "nqp", "h", "d", 2, 0, -1, 1, 1,
            listOf(CallSiteRec(byteArrayOf(1), null)),
            arrayOf(block("<mainline>", 0, -1), block("deser", 1, 0, longArrayOf(1, 2, 5, 6)), null, block("orphan", 2, 0)),
            listOf(LexValueRec(0, "\$a", "h", 3, 0)), listOf())
        return ProgramUnit(UnitRecord(meta, arrayOf("p0", "p1", "p2"), byteArrayOf(), mapOf()))
    }

    @Test
    fun tableFollowsTheBlockTable() {
        val u = unit()
        u.buildTable(null)
        val t = u.qbidToCodeRef!!
        assertEquals(4, t.size)
        assertNull(t[2])
        assertEquals("deser", t[1]!!.name)
        assertSame(t[0]!!.staticInfo, t[1]!!.staticInfo.outerStaticInfo)
        assertSame(t[0]!!.staticInfo, t[3]!!.staticInfo.outerStaticInfo)
        assertNull(t[0]!!.staticInfo.outerStaticInfo)
        assertEquals(3, u.codeRefs!!.size)
    }

    @Test
    fun blocksAreRawArgsEngineBlocksWithDistinctHandles() {
        val u = unit()
        u.buildTable(null)
        val t = u.qbidToCodeRef!!
        assertEquals(ArgsExpectation.USE_BINDER, t[0]!!.staticInfo.argsExpectation)
        assertEquals(1, t[1]!!.staticInfo.programIndex)
        assertTrue(t[0]!!.staticInfo.mh !== t[1]!!.staticInfo.mh)
        assertNotNull(t[0]!!.staticInfo.mhResume)
        assertEquals(4, t[0]!!.staticInfo.mh.type().parameterCount())   // (tc, cr, csd, args)
    }

    @Test
    fun handlersUnflatten() {
        val u = unit()
        u.buildTable(null)
        val h = u.qbidToCodeRef!![1]!!.staticInfo.handlers!!
        assertEquals(1, h.size)
        assertEquals(listOf(5L, 6L), h[0].toList())
    }

    @Test
    fun hooksAnswerFromTheMeta() {
        val u = unit()
        assertEquals("nqp", u.hllName())
        assertEquals(0, u.mainlineQbid()); assertEquals(-1, u.entryQbid())
        assertEquals(1, u.deserializeQbid()); assertEquals(1, u.loadQbid())
        assertEquals(2, u.serializedCodeRefCount())
        assertEquals("U1", u.unitId())
        assertEquals("p2", u.engineProgram(2))
        assertEquals(1, u.getCallSites().size)
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.runtime.unit.ProgramUnitTest' 2>&1 | tail -20`
Expected: `Unresolved reference: ProgramUnit`.

- [ ] **Step 3: Write ProgramUnit**

`ProgramUnit.kt`:

```kotlin
package org.raku.nqp.runtime.unit

import java.nio.ByteBuffer
import org.raku.nqp.runtime.ArgsExpectation
import org.raku.nqp.runtime.CallSiteDescriptor
import org.raku.nqp.runtime.CodeRef
import org.raku.nqp.runtime.CompilationUnit
import org.raku.nqp.runtime.ExceptionHandling
import org.raku.nqp.runtime.ThreadContext
import org.raku.nqp.sixmodel.STable

/**
 * A compilation unit built from a unit artifact's record: the block
 * table gives every code ref, no reflection, no class. Frame argument 0
 * of every engine program is a CompilationUnit, so this stays one.
 */
class ProgramUnit(@JvmField val record: UnitRecord) : CompilationUnit() {
    private val meta get() = record.meta

    /** The pure part of initialization: code refs, outers, call sites. */
    fun buildTable(bootSt: STable?) {
        val blocks = meta.blocks
        val table = arrayOfNulls<CodeRef>(blocks.size)
        val list = ArrayList<CodeRef>(blocks.size)
        for (qbid in blocks.indices) {
            val b = blocks[qbid] ?: continue
            val cr = CodeRef(this, ProgramEntry.ENTER, b.name, b.cuid,
                if (b.oLex.isEmpty()) null else b.oLex,
                if (b.iLex.isEmpty()) null else b.iLex,
                if (b.nLex.isEmpty()) null else b.nLex,
                if (b.sLex.isEmpty()) null else b.sLex,
                unflatten(b.handlers), ArgsExpectation.USE_BINDER)
            val sci = cr.staticInfo
            sci.programIndex = b.programIndex
            sci.methodName = "qb_$qbid"
            sci.hasExitHandler = b.hasExitHandler
            sci.isThunk = b.isThunk
            if (b.sourceFile != null) {
                sci.sourceFile = b.sourceFile
                sci.sourceLine = b.sourceLine
                sci.sourceLineDelta = b.sourceLineDelta
                if (b.sectionRaw != null) {
                    sci.sourceSectionRaw = b.sectionRaw
                    sci.sourceSectionLine = b.sectionLine
                    sci.sourceSectionFile = b.sectionFile
                }
            }
            if (bootSt != null) cr.st = bootSt
            table[qbid] = cr
            list.add(cr)
        }
        for (qbid in blocks.indices) {
            val b = blocks[qbid] ?: continue
            if (b.outerQbid >= 0)
                table[qbid]!!.staticInfo.outerStaticInfo = table[b.outerQbid]?.staticInfo
        }
        qbidToCodeRef = table
        codeRefs = list.toTypedArray()
        callSites = getCallSites()
    }

    override fun initializeCompilationUnit(tc: ThreadContext, runDeserialize: Boolean) {
        buildTable(tc.gc.BOOTCode?.st)
        hllConfig = tc.gc.getHLLConfigFor(hllName())
        if (runDeserialize) runDeserializeIfAvailable(tc)
    }

    /** The deserialize program installs the SC; the static lexical values
     *  point into it, so they follow (setup_blv was the last post-deserialize
     *  task on the class road, exactly this position). */
    override fun runDeserializeIfAvailable(tc: ThreadContext) {
        super.runDeserializeIfAvailable(tc)
        applyStaticLexValues(tc)
    }

    fun applyStaticLexValues(tc: ThreadContext) {
        val table = qbidToCodeRef ?: return
        for (v in meta.staticLexValues) {
            val cr = table.getOrNull(v.qbid) ?: continue
            val idx = cr.staticInfo.oTryGetLexicalIdx(v.name)
            if (idx == -1) continue
            val sc = tc.gc.scs.get(v.scHandle)
                ?: throw ExceptionHandling.dieInternal(tc, "unit ${unitId()}: static lexical ${v.name} of block ${v.qbid} names unknown SC ${v.scHandle}")
            cr.staticInfo.oLexStatic!![idx] = sc.getObject(v.scIdx)
            cr.staticInfo.oLexStaticFlags!![idx] = v.flags.toByte()
        }
    }

    override fun getCallSites(): Array<CallSiteDescriptor> =
        Array(meta.callSites.size) { CallSiteDescriptor(meta.callSites[it].flags, meta.callSites[it].names) }

    override fun hllName(): String = meta.hll
    override fun deserializeQbid(): Int = meta.deserializeQbid
    override fun loadQbid(): Int = meta.loadQbid
    override fun mainlineQbid(): Int = meta.mainlineQbid
    override fun entryQbid(): Int = meta.entryQbid
    override fun serializedCodeRefCount(): Int = meta.serializedCodeRefCount
    override fun unitId(): String = meta.unitId
    override fun engineProgram(idx: Int): String = record.programs[idx]
    override fun serializedBlob(): ByteBuffer? = record.serialized?.let { ByteBuffer.wrap(it) }

    override fun claimNested(tc: ThreadContext, name: String): CompilationUnit {
        val rec = record.nested[name]
            ?: throw ExceptionHandling.dieInternal(tc, "unit ${unitId()} carries no nested unit named $name")
        val nested = ProgramUnit(rec)
        nested.shared = tc.gc.sharingHint
        nested.initializeCompilationUnit(tc, false)
        return nested
    }

    private fun unflatten(flat: LongArray): Array<LongArray> {
        var p = 0
        val n = flat[p++].toInt()
        return Array(n) {
            val len = flat[p++].toInt()
            LongArray(len) { flat[p++] }
        }
    }
}
```

`CallSiteDescriptor(ByteArray, Array<String>?)` is the constructor `getCallSites` bytecode already invokes (`Compiler.nqp:3612-3613`, `<init>(byte[], String[])`).

- [ ] **Step 4: Run the tests**

Run: `./nqp/gradlew -p nqp :nqp-runtime:test 2>&1 | tail -15`
Expected: `BUILD SUCCESSFUL`, all `UnitFormatTest` and `ProgramUnitTest` tests pass. If `StaticCodeInfo`'s init rejects the handle shape (`Unhandled ArgsExpectation`), the `ENTER` type in Task 2 is wrong; it must be `(ThreadContext, CodeRef, CallSiteDescriptor, ResumeStatus.Frame, Object[])void`.

- [ ] **Step 5: Commit (nqp tree)**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git add src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/ProgramUnitTest.kt && git commit -F - <<'EOF'
unit artifact: ProgramUnit, a CompilationUnit built from the block table without reflection

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRn8gLyZjirBAKS6urb3n4
EOF
```

---

### Task 4: The loader roads, the entry main, the eval server

**Files:**
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitLoader.kt`
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitMain.kt`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/LibraryLoader.java:32-83` (`load` overloads), add `loadApp`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/tools/EvalServer.java:66-91` and `:139-140`

**Interfaces:**
- Produces: `UnitLoader.isUnitFile(fn): Boolean`, `UnitLoader.record(fn, shared): UnitRecord`, `UnitLoader.loadUnit(tc, fn, shared): ProgramUnit` (initialized, load block not run), `UnitLoader.loadAndRun(tc, fn, shared)`, `UnitLoader.loadAndRun(tc, bytes: ByteArray)`; `LibraryLoader.loadApp(tc, path, shared): CompilationUnit` (road-agnostic: initialized, no load block); `LibraryLoader.prime(path)` (warms whichever road); `UnitMain.main(argv)`.

- [ ] **Step 1: UnitLoader**

```kotlin
package org.raku.nqp.runtime.unit

import java.io.File
import java.util.concurrent.ConcurrentHashMap
import org.raku.nqp.runtime.ThreadContext

/** Loads unit artifacts. A shared load (eval server) caches the parsed,
 *  immutable record by path and builds a fresh ProgramUnit per load,
 *  the way the class road shares the Class and instantiates per context. */
object UnitLoader {
    private val sharedRecords = ConcurrentHashMap<String, UnitRecord>()

    @JvmStatic
    fun isUnitFile(fn: String): Boolean {
        val f = File(fn)
        if (!f.isFile) return false
        return try { UnitZip.isUnit(f.readBytes()) } catch (t: Exception) { false }
    }

    @JvmStatic
    fun record(fn: String, shared: Boolean): UnitRecord =
        if (shared) sharedRecords.computeIfAbsent(fn) { UnitZip.read(File(it).readBytes()) }
        else UnitZip.read(File(fn).readBytes())

    @JvmStatic
    fun loadUnit(tc: ThreadContext, fn: String, shared: Boolean): ProgramUnit {
        val u = ProgramUnit(record(fn, shared))
        u.shared = shared
        u.initializeCompilationUnit(tc)
        return u
    }

    @JvmStatic
    fun loadAndRun(tc: ThreadContext, fn: String, shared: Boolean) {
        loadUnit(tc, fn, shared).runLoadIfAvailable(tc)
    }

    @JvmStatic
    fun loadAndRun(tc: ThreadContext, bytes: ByteArray) {
        val u = ProgramUnit(UnitZip.read(bytes))
        u.shared = tc.gc.sharingHint
        u.initializeCompilationUnit(tc)
        u.runLoadIfAvailable(tc)
    }
}
```

- [ ] **Step 2: The bilingual switch in LibraryLoader**

In `LibraryLoader.java`, in `load(ThreadContext tc, String filename)` replace the line `resolveClass(tc, loadFile(filename, tc.gc.byteClassLoader, tc.gc.sharingHint));` with:

```java
            if (org.raku.nqp.runtime.unit.UnitLoader.isUnitFile(filename))
                org.raku.nqp.runtime.unit.UnitLoader.loadAndRun(tc, filename, tc.gc.sharingHint);
            else
                resolveClass(tc, loadFile(filename, tc.gc.byteClassLoader, tc.gc.sharingHint));
```

Replace the body of `load(ThreadContext tc, ByteBuffer buffer)` with:

```java
        try {
            byte[] bytes = new byte[buffer.remaining()];
            buffer.duplicate().get(bytes);
            if (org.raku.nqp.runtime.unit.UnitZip.isUnit(bytes))
                org.raku.nqp.runtime.unit.UnitLoader.loadAndRun(tc, bytes);
            else
                resolveClass(tc, loadJar(buffer, tc.gc.byteClassLoader));
        }
        catch (IOException | IllegalArgumentException | ClassNotFoundException e) {
            throw ExceptionHandling.dieInternal(tc, e);
        }
```

Add after `resolveClass`:

```java
    /* Road-agnostic app load for entry points (runner main, eval server):
     * the unit is initialized (deserialized) but its load block is not run;
     * an entry block does that itself. */
    public static CompilationUnit loadApp(ThreadContext tc, String path, boolean shared) {
        if (org.raku.nqp.runtime.unit.UnitLoader.isUnitFile(path))
            return org.raku.nqp.runtime.unit.UnitLoader.loadUnit(tc, path, shared);
        try {
            return CompilationUnit.setupCompilationUnit(tc, loadFile(path, tc.gc.byteClassLoader, shared), shared);
        }
        catch (IOException | IllegalArgumentException | ClassNotFoundException | ReflectiveOperationException e) {
            throw ExceptionHandling.dieInternal(tc, e);
        }
    }

    /* Warms whichever road the path takes, so a server pays for parsing once. */
    public static void prime(String path, ByteClassLoader loader) throws IOException, ClassNotFoundException {
        if (org.raku.nqp.runtime.unit.UnitLoader.isUnitFile(path))
            org.raku.nqp.runtime.unit.UnitLoader.record(path, true);
        else
            loadFile(path, loader, true);
    }
```

- [ ] **Step 3: UnitMain**

```kotlin
package org.raku.nqp.runtime.unit

import org.raku.nqp.runtime.GlobalContext
import org.raku.nqp.runtime.LibraryLoader
import org.raku.nqp.runtime.Ops

/** The runner scripts' main class: `UnitMain <unit.jar> args...`. Either
 *  road: the loader decides. Replaces the generated `nqp`/`perl6` class
 *  main, which called CompilationUnit.enterFromMain on its own Class. */
object UnitMain {
    @JvmStatic
    fun main(argv: Array<String>) {
        require(argv.isNotEmpty()) { "usage: UnitMain <unit jar> [args...]" }
        val tc = GlobalContext().mainThread!!
        val cu = LibraryLoader.loadApp(tc, argv[0], false)
        val entry = cu.entryQbid()
        check(entry >= 0) { "${argv[0]} is not an entry point (no entry block)" }
        Ops.invokeMain(tc, cu.lookupCodeRef(entry), cu.unitId(), argv.copyOfRange(1, argv.size))
    }
}
```

- [ ] **Step 4: EvalServer through loadApp**

In `EvalServer.java`, in `run(String appPath, String[] argv)` replace the `cuType = LibraryLoader.loadFile(...)` try/catch and the `CompilationUnit cu = ...` / `entryRef` lines so the method reads:

```java
        gc = new GlobalContext();
        gc.in = new ByteArrayInputStream(new byte[0]);
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        gc.out = gc.err = new PrintStream( baos, true, "UTF-8" );
        gc.interceptExit = true;
        gc.sharingHint = true;

        CompilationUnit cu = LibraryLoader.loadApp(gc.mainThread, appPath, true);
        CodeRef entryRef = null;
        if (cu.entryQbid() >= 0) entryRef = cu.lookupCodeRef(cu.entryQbid());
        if (entryRef == null)
            throw new RuntimeException("This unit is not an entry point");
        try {
            Ops.invokeMain(gc.mainThread, entryRef, cu.unitId(), argv);
        } catch (ThreadDeath td) {
            baos.flush();
        }
        return baos.toString("UTF-8");
```

In `run()` (server start, line 140) replace `cuType = LibraryLoader.loadFile(mainPath, gc.byteClassLoader, true);` with `LibraryLoader.prime(mainPath, gc.byteClassLoader);`. Apply the same two-line change (`loadApp` + `cu.unitId()`) at the second `setupCompilationUnit(... cuType ...)` site near line 239-245 (the per-request `ServiceThread`), and delete the now-unused `cuType` field if the compiler flags it.

- [ ] **Step 5: Build and smoke both roads**

Run: `./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars 2>&1 | tail -5`
Then the class road through the new main, from the rakudo worktree root (the paths mirror `nqp/nqp-j-gradle`'s final `exec` line; copy its `-Xbootclasspath/a:` and `-cp` values verbatim):

```bash
RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 java --enable-native-access=ALL-UNNAMED,org.graalvm.truffle --sun-misc-unsafe-memory-access=allow -Xmx4g -Xss64m --module-path nqp/build/jvm/share/truffle --add-modules org.graalvm.truffle,org.graalvm.truffle.runtime -Xbootclasspath/a:"<the runner's boot entries>" -cp "nqp/build/jvm/share/lib:nqp/build/jvm/share/runtime/nqp-truffle.jar" org.raku.nqp.runtime.unit.UnitMain nqp/build/jvm/share/lib/nqp.jar -e 'say(6*7)'
```

Expected: `42` (nqp.jar is still a class-file unit here; this proves `loadApp`'s class road and the entry through `UnitMain`).

- [ ] **Step 6: Commit (nqp tree)**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git add src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitLoader.kt src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitMain.kt src/vm/jvm/runtime/org/raku/nqp/runtime/LibraryLoader.java src/vm/jvm/runtime/org/raku/nqp/tools/EvalServer.java && git commit -F - <<'EOF'
unit artifact: the bilingual loader (unit.meta picks the road), UnitMain, eval server through loadApp

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRn8gLyZjirBAKS6urb3n4
EOF
```

---

### Task 5: The dispatchers materialize a target on demand

**Files:**
- Modify: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt:673-683` (realize), `:773-777` (invoke), `:1090-1098` (adoptCallNode)

**Interfaces:**
- Consumes: `CodeEngines.materialize(sci)` (Task 2).

- [ ] **Step 1: realize**

At line 678-681, replace

```kotlin
            if (cn == null) {
                if (NqpRaw.staticInfo(lit).engineTarget != null) {
```

with

```kotlin
            if (cn == null) {
                if (hasTarget(NqpRaw.staticInfo(lit))) {
```

and add, next to `adoptCallNode`:

```kotlin
    /** A target exists or can be made from the unit (artifact road): the
     *  volatile read stays PE-visible, the compile goes behind a boundary. */
    private fun hasTarget(sci: StaticCodeInfo): Boolean =
        sci.engineTarget != null || (sci.programIndex >= 0 && materializeBoundary(sci) != null)

    @TruffleBoundary
    private fun materializeBoundary(sci: StaticCodeInfo): Any? = CodeEngines.materialize(sci)
```

(`StaticCodeInfo` and `CodeEngines` are `org.raku.nqp.runtime` imports; add them if the file lacks them.)

- [ ] **Step 2: invoke and adoptCallNode**

In `invoke` (line 774) replace `val target = callee.staticInfo.engineTarget` with `val target = CodeEngines.materialize(callee.staticInfo)`; the function is already a boundary. In `adoptCallNode` (line 1092) replace `val target = cr.staticInfo.engineTarget` with `val target = CodeEngines.materialize(cr.staticInfo)`.

- [ ] **Step 3: Build and smoke**

Run: `./nqp/gradlew -p nqp :nqp-truffle:jar syncRuntimeJars 2>&1 | tail -3` then `RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'sub f($x) { $x * 2 }; my $s := 0; my int $i := 0; while $i < 100000 { $s := $s + f($i); $i++ }; say($s)'`
Expected: `9999900000` (class-road blocks have `programIndex == -1`, so behaviour is unchanged).

- [ ] **Step 4: Commit (nqp tree)**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git add nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt && git commit -F - <<'EOF'
jesp/dispatch: materialize an artifact block's target on demand instead of waiting for a stub run

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRn8gLyZjirBAKS6urb3n4
EOF
```

---

### Task 6: The JAST record carries the unit, Compiler.nqp's artifact road

**Files:**
- Modify: `nqp/src/vm/jvm/QAST/JASTNodes.nqp:4-40` (JAST::Class), `:113-190` (JAST::Method)
- Modify: `nqp/src/vm/jvm/QAST/Compiler.nqp:3555-3570` (CodeRefBuilder), `:4092-4131` (unit prologue, setup_blv), `:4242-4256` (entry qbid), `:4270-4281` (programs), `:4381-4384` (serialized count), `:4576-4578` (method name), `:4653-4694` (engine body), `:4685` (fallback junction)
- Modify: `nqp/src/vm/jvm/QAST/TruffleEncoder.nqp:660,695` (`:unit_road`, raw accepted)

**Interfaces:**
- Produces on `JAST::Class`: `hll`, `mainline_qbid`, `entry_qbid`, `deserialize_qbid`, `load_qbid`, `serialized_count`, `sc_handle`, `sc_desc`, `fallbacks`, `unit_road`, `programs` (list of str), `callsites` (list of `[@flags, @names]`), `blockvalues` (list of `[qbid, name, handle, idx, flags]`).
- Produces on `JAST::Method`: `cr_qbid`, `cr_program` (both `-1` by default).
- Produces the dynamic `$*UNIT_ROAD` (1 when `NQP_UNIT` is set, `--target=jar`, comp mode) and `$*UNIT_FALLBACKS`.

- [ ] **Step 1: JASTNodes fields**

In `JAST::Class` add attributes after `@!nested_classes;`:

```
    has str $!hll;
    has int $!mainline_qbid;
    has int $!entry_qbid;
    has int $!deserialize_qbid;
    has int $!load_qbid;
    has int $!serialized_count;
    has str $!sc_handle;
    has str $!sc_desc;
    has int $!fallbacks;
    has int $!unit_road;
    has @!programs;
    has @!callsites;
    has @!blockvalues;
```

in `BUILD` add:

```
        $!hll := '';
        $!mainline_qbid := -1;
        $!entry_qbid := -1;
        $!deserialize_qbid := -1;
        $!load_qbid := -1;
        $!serialized_count := -1;
        $!sc_handle := '';
        $!sc_desc := '';
        @!programs := [];
        @!callsites := [];
        @!blockvalues := [];
```

and accessors after `nested_classes`:

```
    # The unit artifact's record (docs/superpowers/specs/2026-09-09-jvm-unit-artifact-design.md):
    # what the writer reads off this class instead of assembling bytecode.
    method hll(*@value) { @value ?? ($!hll := @value[0]) !! $!hll }
    method mainline_qbid(*@value) { @value ?? ($!mainline_qbid := @value[0]) !! $!mainline_qbid }
    method entry_qbid(*@value) { @value ?? ($!entry_qbid := @value[0]) !! $!entry_qbid }
    method deserialize_qbid(*@value) { @value ?? ($!deserialize_qbid := @value[0]) !! $!deserialize_qbid }
    method load_qbid(*@value) { @value ?? ($!load_qbid := @value[0]) !! $!load_qbid }
    method serialized_count(*@value) { @value ?? ($!serialized_count := @value[0]) !! $!serialized_count }
    method sc_handle(*@value) { @value ?? ($!sc_handle := @value[0]) !! $!sc_handle }
    method sc_desc(*@value) { @value ?? ($!sc_desc := @value[0]) !! $!sc_desc }
    method fallbacks(*@value) { @value ?? ($!fallbacks := @value[0]) !! $!fallbacks }
    method unit_road(*@value) { @value ?? ($!unit_road := @value[0]) !! $!unit_road }
    method programs(*@value) { @value ?? (@!programs := @value[0]) !! @!programs }
    method callsites(*@value) { @value ?? (@!callsites := @value[0]) !! @!callsites }
    method blockvalues(*@value) { @value ?? (@!blockvalues := @value[0]) !! @!blockvalues }
```

In `JAST::Method` add `has int $!cr_qbid;` and `has int $!cr_program;`, set both to `-1` in `BUILD`, and add accessors `method cr_qbid(*@value) { @value ?? ($!cr_qbid := @value[0]) !! $!cr_qbid }` and `method cr_program(*@value) { @value ?? ($!cr_program := @value[0]) !! $!cr_program }`.

- [ ] **Step 2: CodeRefBuilder exposes the call-site data**

In Compiler.nqp's `CodeRefBuilder` (after `get_callsite_idx`, line 3566) add:

```
        # The artifact road reads the descriptors as data instead of the
        # getCallSites bytecode: [@arg_types, @arg_names] per site.
        method callsite_data() { @!callsites }
```

- [ ] **Step 3: The unit prologue**

After `my @*ENGINE_PROGRAMS := nqp::list_s();` (line 4097) add:

```
        # The artifact road (rakudo docs/superpowers/specs/2026-09-09-jvm-
        # unit-artifact-design.md): under NQP_UNIT a jar-bound comp-mode
        # unit is written as programs + serialized context + block table,
        # no class file, PROVIDED every block encoded. $*UNIT_FALLBACKS
        # counts the blocks that did not; the backend takes the class road
        # for a unit with any.
        my $*UNIT_ROAD := nqp::existskey(nqp::getenvhash(), 'NQP_UNIT')
            && %*COMPILING<%?OPTIONS><target> eq 'jar'
            && $cu.compilation_mode ?? 1 !! 0;
        my $*UNIT_FALLBACKS := 0;
```

- [ ] **Step 4: Static lexical values as data**

Replace lines 4126-4131

```
        if %*BLOCK_LEX_VALUES {
            nqp::push(@post_des, QAST::Block.new(
                :blocktype('immediate'),
                QAST::Op.new( :op('setup_blv'), %*BLOCK_LEX_VALUES )
            ));
        }
```

with

```
        if %*BLOCK_LEX_VALUES {
            if $*UNIT_ROAD {
                # The artifact's meta carries them; the loader installs them
                # after the deserialize program, where setup_blv ran.
                my @rows;
                for %*BLOCK_LEX_VALUES {
                    my int $qbid := self.cuid_to_qbid($_.key);
                    for $_.value -> @lex {
                        my $sc := nqp::getobjsc(@lex[1]);
                        nqp::push(@rows, [$qbid, @lex[0], nqp::scgethandle($sc),
                            nqp::scgetobjidx($sc, @lex[1]), @lex[2]]);
                    }
                }
                $*JCLASS.blockvalues(@rows);
            }
            else {
                nqp::push(@post_des, QAST::Block.new(
                    :blocktype('immediate'),
                    QAST::Op.new( :op('setup_blv'), %*BLOCK_LEX_VALUES )
                ));
            }
        }
```

- [ ] **Step 5: Record the ids**

Where the deserialize block is registered (line 4213-4216, the `deserializeQbid` method), add `$*JCLASS.deserialize_qbid(self.cuid_to_qbid($block.cuid));` next to the `PushIndex`. Where `loadQbid` is built (4227-4230) add `$*JCLASS.load_qbid(self.cuid_to_qbid($load_block.cuid));`. Where `entryQbid` is built (4252-4255) add `$*JCLASS.entry_qbid(self.cuid_to_qbid($main_block.cuid));`. Next to `hllName` (4259) add `$*JCLASS.hll($*HLL);`, next to `mainlineQbid` (4265) add `$*JCLASS.mainline_qbid(self.cuid_to_qbid($cu[0].cuid));`. In `deserialization_code`, next to `serializedCodeRefCount` (4381-4384) add `$*JCLASS.serialized_count(+@code_ref_blocks); $*JCLASS.sc_handle(nqp::scgethandle($sc)); $*JCLASS.sc_desc(nqp::scgetdesc($sc));`.

Replace the programs block at 4270-4279 with:

```
        # Engine programs collected from jar-bound blocks. On the artifact
        # road they go to the writer as a list (byte-framed by it); on the
        # class road they travel as one sidecar entry, joined here, last,
        # so every block -- the deserialize and load methods included --
        # has had its say.
        if $*UNIT_ROAD {
            # A boxed list: @*ENGINE_PROGRAMS is a native str list, and
            # the writer reads its record through at_pos_boxed.
            my @progs;
            for @*ENGINE_PROGRAMS -> str $p { nqp::push(@progs, $p) }
            $*JCLASS.programs(@progs);
            $*JCLASS.callsites($*CODEREFS.callsite_data);
            $*JCLASS.fallbacks($*UNIT_FALLBACKS);
            $*JCLASS.unit_road(1);
            nqp::say('code unit ' ~ $*JCLASS.name ~ ' -> '
                ~ ($*UNIT_FALLBACKS ?? 'class fallbacks=' ~ $*UNIT_FALLBACKS !! 'artifact'))
                if nqp::existskey(nqp::getenvhash(), 'NQP_CODE_WHY');
        }
        elsif nqp::elems(@*ENGINE_PROGRAMS) {
            my @joined := [~nqp::elems(@*ENGINE_PROGRAMS)];
            for @*ENGINE_PROGRAMS -> str $p {
                nqp::push(@joined, ' ' ~ nqp::chars($p) ~ ':' ~ $p);
            }
            $*JCLASS.codeprograms(nqp::join('', @joined));
        }
```

- [ ] **Step 6: Per-block qbid, program index, fallback count, raw accepted**

At line 4576-4577 (`my $*JMETH := JAST::Method.new( :name('qb_'~...` ) add after it: `$*JMETH.cr_qbid(self.cuid_to_qbid($node.cuid));`.

In the engine-body branch, after `nqp::push_s(@*ENGINE_PROGRAMS, $engine_prog);` (line 4673) add `$*JMETH.cr_program($pidx);`. Change the `encode_block` call (4661-4662) to pass the road: `:comp_mode($*COMP_MODE), :sidecar($as_index), :unit_road($*UNIT_ROAD)`.

At the fallback junction (the `else` at 4684-4687 around `compile_all_the_stmts`) add as its first statement: `$*UNIT_FALLBACKS := $*UNIT_FALLBACKS + 1 if $*UNIT_ROAD;`.

In `TruffleEncoder.nqp`, change the signature at line 660 to `method encode_block($node, $block, $comp, :$comp_mode, :$sidecar, :$unit_road)` and line 695 to:

```
        # A raw block (Compiler.nqp's own deserialize/load/main wrappers)
        # is a parameterless declaration to the engine; on the class road
        # its body stays bytecode, on the artifact road it must encode.
        if $node.blocktype eq 'raw' && !$unit_road { trace('no: raw blocktype'); return '' }
```

- [ ] **Step 7: Stage build (class road), proving nothing regressed**

Run from the rakudo worktree root, without `NQP_UNIT` (the class road must be byte-for-byte the old behaviour):

```bash
RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 NQP_CODE_STRICT=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/b945970f/tmp/build-task6.log --show='> Task :stage' --show='BUILD' --show='rror' -- ./nqp/gradlew -p nqp clean buildJvm
```

Expected: `BUILD SUCCESSFUL` (about 10 min). Then `unzip -l nqp/build/jvm/share/lib/nqp.jar | grep -c codeprograms` prints `1`, and `RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'say("ok")'` prints `ok`.

- [ ] **Step 8: Commit (nqp tree)**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git add src/vm/jvm/QAST/JASTNodes.nqp src/vm/jvm/QAST/Compiler.nqp src/vm/jvm/QAST/TruffleEncoder.nqp && git commit -F - <<'EOF'
unit artifact: the JAST record carries the unit (ids, programs, call sites, static lexical values); NQP_UNIT road in Compiler.nqp

The wrappers (raw blocks) encode on the artifact road; a fallback body is
counted, and the backend takes the class road for a unit with any.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRn8gLyZjirBAKS6urb3n4
EOF
```

---

### Task 7: The writer, its syscall, the backend road, the end-to-end test

**Files:**
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/jast2bc/JastClass.kt`, `JastMethod.kt` (read the new fields), `JASTCompiler.kt:155-162` (expose setup)
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitWriter.kt`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/Syscalls.kt:474-476` (add `jvm-write-unit`)
- Modify: `nqp/src/vm/jvm/HLL/Backend.nqp:79-85`
- Test: `nqp/t/nqp/123-unit-artifact.t`

**Interfaces:**
- Consumes: JAST record fields (Task 6), `UnitRecord`/`UnitZip` (Task 1).
- Produces: syscall `jvm-write-unit(jast, jastnodes, filename)`; `UnitWriter.write(jast, jastNodes, filename, tc)`.

- [ ] **Step 1: Readers for the new fields**

In `JastClass.kt` add fields and reads (each wrapped like `codePrograms`, so an older node type without the field still loads):

```kotlin
    @JvmField var hll: String? = null
    @JvmField var mainlineQbid = -1
    @JvmField var entryQbid = -1
    @JvmField var deserializeQbid = -1
    @JvmField var loadQbid = -1
    @JvmField var serializedCount = -1
    @JvmField var scHandle: String? = null
    @JvmField var scDesc: String? = null
    @JvmField var fallbacks = 0
    @JvmField var unitRoad = false
    @JvmField var programs: SixModelObject? = null
    @JvmField var callsites: SixModelObject? = null
    @JvmField var blockvalues: SixModelObject? = null
```

in `init`, after the nested-classes block:

```kotlin
        try {
            hll = Ops.getattr_s(jast, jastClass, "$!hll", hllHint, tc)
            mainlineQbid = Ops.getattr_i(jast, jastClass, "$!mainline_qbid", mainlineQbidHint, tc).toInt()
            entryQbid = Ops.getattr_i(jast, jastClass, "$!entry_qbid", entryQbidHint, tc).toInt()
            deserializeQbid = Ops.getattr_i(jast, jastClass, "$!deserialize_qbid", deserializeQbidHint, tc).toInt()
            loadQbid = Ops.getattr_i(jast, jastClass, "$!load_qbid", loadQbidHint, tc).toInt()
            serializedCount = Ops.getattr_i(jast, jastClass, "$!serialized_count", serializedCountHint, tc).toInt()
            scHandle = Ops.getattr_s(jast, jastClass, "$!sc_handle", scHandleHint, tc)
            scDesc = Ops.getattr_s(jast, jastClass, "$!sc_desc", scDescHint, tc)
            fallbacks = Ops.getattr_i(jast, jastClass, "$!fallbacks", fallbacksHint, tc).toInt()
            unitRoad = Ops.getattr_i(jast, jastClass, "$!unit_road", unitRoadHint, tc) != 0L
            programs = jast.get_attribute_boxed(tc, jastClass, "@!programs", programsHint)
            callsites = jast.get_attribute_boxed(tc, jastClass, "@!callsites", callsitesHint)
            blockvalues = jast.get_attribute_boxed(tc, jastClass, "@!blockvalues", blockvaluesHint)
        }
        catch (t: Throwable) {
            /* A version of the node without the unit fields. */
        }
```

and the matching `private var ...Hint = 0L` entries plus `hint_for` lines in `setup` for each of `$!hll`, `$!mainline_qbid`, `$!entry_qbid`, `$!deserialize_qbid`, `$!load_qbid`, `$!serialized_count`, `$!sc_handle`, `$!sc_desc`, `$!fallbacks`, `$!unit_road`, `@!programs`, `@!callsites`, `@!blockvalues`.

In `JastMethod.kt` add `@JvmField var crQbid = -1` and `@JvmField var crProgram = -1`, read in `init` inside a try/catch:

```kotlin
        try {
            crQbid = Ops.getattr_i(jast, jastMethod, "$!cr_qbid", crQbidHint, tc).toInt()
            crProgram = Ops.getattr_i(jast, jastMethod, "$!cr_program", crProgramHint, tc).toInt()
        } catch (t: Throwable) {
            /* A version of the node without the fields. */
        }
```

with `crQbidHint`/`crProgramHint` in the companion and `setup`.

In `JASTCompiler.kt` add next to the private `setup`:

```kotlin
        @JvmStatic
        fun ensureSetup(jastNodes: SixModelObject, tc: ThreadContext) {
            if (!setup) setup(jastNodes, tc)
        }
```

- [ ] **Step 2: UnitWriter**

```kotlin
package org.raku.nqp.runtime.unit

import java.io.FileOutputStream
import org.raku.nqp.jast2bc.JASTCompiler
import org.raku.nqp.jast2bc.JastClass
import org.raku.nqp.jast2bc.JastMethod
import org.raku.nqp.runtime.Base64
import org.raku.nqp.runtime.ExceptionHandling
import org.raku.nqp.runtime.Ops
import org.raku.nqp.runtime.ThreadContext
import org.raku.nqp.sixmodel.SixModelObject

/**
 * The artifact writer: reads the JAST tree as a record (the code-ref
 * fields Compiler.nqp already collects per method, the programs list,
 * the serialized blob, the call-site data) and writes the zip.
 * Instruction lists are never looked at. Replaces JASTCompiler.writeClass
 * on the artifact road.
 */
object UnitWriter {
    @JvmStatic
    fun write(jast: SixModelObject, jastNodes: SixModelObject, filename: String, tc: ThreadContext) {
        JASTCompiler.ensureSetup(jastNodes, tc)
        val classType = jastNodes.at_key_boxed(tc, "JAST::Class")!!
        val methodType = jastNodes.at_key_boxed(tc, "JAST::Method")!!
        val jc = JastClass(jast, classType, tc)
        if (!jc.unitRoad) throw ExceptionHandling.dieInternal(tc, "jvm-write-unit: ${jc.className} was not compiled on the artifact road")
        if (jc.fallbacks != 0) throw ExceptionHandling.dieInternal(tc, "jvm-write-unit: ${jc.className} has ${jc.fallbacks} bytecode fallback bodies")
        if (jc.nestedClasses.isNotEmpty())
            throw ExceptionHandling.dieInternal(tc, "jvm-write-unit: ${jc.className} carries nested units (${jc.nestedClasses}); runtime-compiled units are milestone 2")

        /* Blocks, keyed by qbid; the table is sized by the highest qbid. */
        val blocks = ArrayList<Pair<Int, BlockRec>>()
        var maxQbid = -1
        val iter = Ops.iter(jc.methods, tc)
        while (Ops.istrue(iter, tc) != 0L) {
            val m = JastMethod(iter.shift_boxed(tc)!!, methodType, tc)
            if (m.crOuter == -2) continue                     // not a code ref (hllName, getCallSites, main...)
            if (m.crQbid < 0) throw ExceptionHandling.dieInternal(tc, "jvm-write-unit: block ${m.name} has no qbid")
            if (m.crProgram < 0) throw ExceptionHandling.dieInternal(tc, "jvm-write-unit: block ${m.crName} (${m.name}) has no program")
            val cuid = if (m.crCuid.isNullOrEmpty()) null else m.crCuid
            blocks.add(m.crQbid to BlockRec(
                m.crName ?: "", cuid, m.crOuter,
                strs(m.crOlex), strs(m.crIlex), strs(m.crNlex), strs(m.crSlex),
                m.crHandlers, m.hasExitHandler, m.isThunk,
                m.crFile, m.crLine, m.crRawLine - m.crLine,
                m.crSectionRaw, m.crSectionLine, m.crSectionFile?.map { it ?: "" }?.toTypedArray(),
                m.crProgram))
            if (m.crQbid > maxQbid) maxQbid = m.crQbid
        }
        val table = arrayOfNulls<BlockRec>(maxQbid + 1)
        for ((q, b) in blocks) {
            if (table[q] != null) throw ExceptionHandling.dieInternal(tc, "jvm-write-unit: two blocks with qbid $q")
            table[q] = b
        }

        val programs = strList(jc.programs, tc)
        val callSites = ArrayList<CallSiteRec>()
        jc.callsites?.let { cs ->
            val it = Ops.iter(cs, tc)
            while (Ops.istrue(it, tc) != 0L) {
                val row = it.shift_boxed(tc)!!
                val flagsObj = row.at_pos_boxed(tc, 0)!!
                val flags = ByteArray(Ops.elems(flagsObj, tc).toInt()) { flagsObj.at_pos_boxed(tc, it.toLong())!!.get_int(tc).toByte() }
                val names = strList(row.at_pos_boxed(tc, 1), tc)
                callSites.add(CallSiteRec(flags, if (names.isEmpty()) null else names))
            }
        }
        val lexValues = ArrayList<LexValueRec>()
        jc.blockvalues?.let { bv ->
            val it = Ops.iter(bv, tc)
            while (Ops.istrue(it, tc) != 0L) {
                val row = it.shift_boxed(tc)!!
                lexValues.add(LexValueRec(
                    row.at_pos_boxed(tc, 0)!!.get_int(tc).toInt(),
                    row.at_pos_boxed(tc, 1)!!.get_str(tc)!!,
                    row.at_pos_boxed(tc, 2)!!.get_str(tc)!!,
                    row.at_pos_boxed(tc, 3)!!.get_int(tc).toInt(),
                    row.at_pos_boxed(tc, 4)!!.get_int(tc).toInt()))
            }
        }
        val meta = UnitMeta(
            jc.className!!, jc.hll ?: "nqp",
            jc.scHandle?.ifEmpty { null }, jc.scDesc?.ifEmpty { null },
            jc.serializedCount, jc.mainlineQbid, jc.entryQbid, jc.deserializeQbid, jc.loadQbid,
            callSites, table, lexValues, listOf())
        val record = UnitRecord(meta, programs, jc.serialized, mapOf())
        try {
            FileOutputStream(filename).use { UnitZip.write(record, it) }
        } catch (e: java.io.IOException) {
            throw ExceptionHandling.dieInternal(tc, e)
        }
    }

    private fun strs(l: List<String?>): Array<String> = Array(l.size) { l[it] ?: "" }

    private fun strList(obj: SixModelObject?, tc: ThreadContext): Array<String> {
        if (obj == null) return arrayOf()
        val n = Ops.elems(obj, tc).toInt()
        return Array(n) { i -> obj.at_pos_boxed(tc, i.toLong())!!.get_str(tc) ?: "" }
    }
}
```

Note `jc.serialized` is already the decoded blob (`JastClass` Base64-decodes `$!serialized`); `UnitZip.write` compresses it.

- [ ] **Step 3: The syscall**

In `Syscalls.kt` after the `jvm-class-of-cuid` definition add:

```kotlin
        /* Writes the compiling unit as a unit artifact (programs +
         * serialized context + block table, no class file). A syscall so
         * HLL::Backend::JVM, compiled by the stage0 compiler, can reach it. */
        define("jvm-write-unit", OBJ, OBJ, STR) { args ->
            org.raku.nqp.runtime.unit.UnitWriter.write(args.obj(0), args.obj(1), args.str(2), args.tc)
            void
        }
```

(`OBJ`, `STR`, `void` and `define` follow the file's existing conventions; copy the `jvm-claim-nested` entry's shape.)

- [ ] **Step 4: The backend road**

In `Backend.nqp` replace lines 79-82:

```
        if (%adverbs<target> eq 'classfile' || %adverbs<target> eq 'jar') && %adverbs<output> {
            nqp::compilejasttofile($jast, %jastnodes, %adverbs<output>);
            nqp::null()
        }
```

with

```
        if (%adverbs<target> eq 'classfile' || %adverbs<target> eq 'jar') && %adverbs<output> {
            # The artifact road (NQP_UNIT): a jar-bound unit whose every
            # block encoded is written as programs + serialized context +
            # block table, no class file; any fallback body keeps the
            # class road. Compiler.nqp made the decision ($jast.unit_road,
            # $jast.fallbacks); this only acts on it.
            if %adverbs<target> eq 'jar' && $jast.unit_road && !$jast.fallbacks {
                nqp::syscall('jvm-write-unit', $jast, %jastnodes, %adverbs<output>);
            }
            else {
                nqp::compilejasttofile($jast, %jastnodes, %adverbs<output>);
            }
            nqp::null()
        }
```

- [ ] **Step 5: The end-to-end test**

`nqp/t/nqp/123-unit-artifact.t`:

```
# Compiles a module on the artifact road (NQP_UNIT=1, --target=jar) and
# loads it back: the jar must carry unit.meta and no class entry, and a
# sub, a closure over an outer, a handler and a regex from it must run.
plan(8);

my $dir := nqp::cwd() ~ '/t/nqp/123-unit-artifact.tmp';
nqp::mkdir($dir, 0o755) unless nqp::stat($dir, nqp::const::STAT_EXISTS);
my $src := $dir ~ '/UnitMod.nqp';
my $jar := $dir ~ '/UnitMod.jar';
my $fh := nqp::open($src, 'w');
nqp::printfh($fh, q{
module UnitMod {
    my $counter := 0;
    our sub twice($x) { $x * 2 }
    our sub counter() { $counter := $counter + 1; $counter }
    our sub guarded($x) {
        my $r := 'ok';
        try { nqp::die('boom ' ~ $x); CATCH { $r := 'caught ' ~ nqp::getmessage($_) } }
        $r
    }
    our sub matches($s) { $s ~~ /^ \d+ $/ ?? 1 !! 0 }
}
});
nqp::closefh($fh);

my %env := nqp::getenvhash();
%env<NQP_UNIT> := '1';
my $runner := nqp::atkey(%env, 'NQP_TEST_RUNNER') || 'nqp/nqp-j-gradle';
my $cmd := $runner ~ ' --target=jar --module-path=' ~ $dir ~ ' --output=' ~ $jar ~ ' ' ~ $src;
my $rc := nqp::shell($cmd, nqp::cwd(), %env);
ok($rc == 0, 'compiled the module on the artifact road');

# The zip's central directory keeps entry names in plain text.
my $list := $dir ~ '/listing.txt';
nqp::shell('unzip -l ' ~ $jar ~ ' > ' ~ $list, nqp::cwd(), %env);
my $listing := nqp::open($list, 'r');
my $text := nqp::readallfh($listing);
nqp::closefh($listing);
ok(nqp::index($text, 'unit.meta') >= 0, 'the jar carries unit.meta');
ok(nqp::index($text, '.class') < 0, 'the jar carries no class entry');

nqp::loadbytecode($jar);
my $mod := nqp::gethllsym('nqp', 'UnitMod') // nqp::null();
ok(UnitMod::twice(21) == 42, 'a sub from the artifact runs');
ok(UnitMod::counter() == 1 && UnitMod::counter() == 2, 'a closure over the mainline keeps its outer');
ok(UnitMod::guarded('x') eq 'caught boom x', 'a handler in an artifact block catches');
ok(UnitMod::matches('123') == 1, 'a regex from the artifact matches');
ok(UnitMod::matches('12a') == 0, 'and fails to match');
```

Adjust the `use`/symbol road to what `nqp::loadbytecode` of a module jar gives at runtime: if `UnitMod::twice` is not resolvable after `loadbytecode` alone, replace the four call lines with `use UnitMod;` at the top of a second, dynamically compiled string evaluated through `nqp::getcomp('nqp').compile(... :module-path)`; the existing `t/nqp/` module tests (grep `loadbytecode` and `module-path` in `nqp/t/nqp/*.t`) show the working shape on this branch.

- [ ] **Step 6: Stage build on the artifact road**

```bash
NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 NQP_CODE_STRICT=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/b945970f/tmp/build-task7.log --show='> Task :stage' --show='BUILD' --show='rror' --show='code unit' -- ./nqp/gradlew -p nqp clean buildJvm
```

Expected: `BUILD SUCCESSFUL`. The stage2 units log `code unit <name> -> artifact` when run with `NQP_CODE_WHY=1` added. Check: `for j in nqp/build/jvm/stage2/*.jar; do echo "$j $(unzip -l $j | grep -c 'unit.meta') $(unzip -l $j | grep -c '\.class')"; done` prints `1 0` for every jar. A stage2 compile that dies is diagnosed the campaign's way: the encoder's own verdict (`NQP_CODE_WHY=1`) names the block, and `NQP_CODE_STRICT` names the op; the deserialize wrapper is the likeliest first failure (an op with no encoding), fixed by giving that op its classlib-derived encoding in `TruffleEncoder.nqp`.

Then the runner is still the class-road `nqp` main class (Task 8 switches it), so smoke through `UnitMain` as in Task 4 step 5, pointing it at `nqp/build/jvm/share/lib/nqp.jar`:
Expected: `42`.

- [ ] **Step 7: Run the end-to-end test**

Run (after Task 8's runner switch, or with the `UnitMain` command line from Task 4 step 5 exported as `NQP_TEST_RUNNER`): `RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle nqp/t/nqp/123-unit-artifact.t`
Expected: `1..8` and eight `ok` lines.

- [ ] **Step 8: Commit (nqp tree)**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git add src/vm/jvm/runtime/org/raku/nqp/jast2bc/JastClass.kt src/vm/jvm/runtime/org/raku/nqp/jast2bc/JastMethod.kt src/vm/jvm/runtime/org/raku/nqp/jast2bc/JASTCompiler.kt src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitWriter.kt src/vm/jvm/runtime/org/raku/nqp/dispatch/Syscalls.kt src/vm/jvm/HLL/Backend.nqp t/nqp/123-unit-artifact.t && git commit -F - <<'EOF'
unit artifact: the writer (JAST record -> zip), jvm-write-unit, the backend's artifact road, t/nqp/123

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRn8gLyZjirBAKS6urb3n4
EOF
```

---

### Task 8: Runners enter through UnitMain

**Files:**
- Modify: `nqp/buildSrc/src/main/kotlin/GenerateRunnerTask.kt:140` (main class)
- Modify: `nqp/tools/templates/jvm/nqp-j.in` (last line)

**Interfaces:**
- Produces: `nqp/nqp-j-gradle` entering through `org.raku.nqp.runtime.unit.UnitMain "$LIB_DIR/nqp.jar"`.

- [ ] **Step 1: The runner's main class**

In `GenerateRunnerTask.kt` line 140 change the tail of the exec line from `-cp "${'$'}CP" nqp "${'$'}@"` to `-cp "${'$'}CP" org.raku.nqp.runtime.unit.UnitMain "${'$'}{LIB_DIR}/nqp.jar" "${'$'}@"`. `UnitMain` takes either road, so this is correct before and after the stage2 flip.

In `tools/templates/jvm/nqp-j.in`, the last line: replace `-cp "@cur_dir@@envvar(LIB_DIR)@" nqp "@sh_allparams@"` with `-cp "@cur_dir@@envvar(LIB_DIR)@" org.raku.nqp.runtime.unit.UnitMain "@cur_dir@@envvar(LIB_DIR)@/nqp.jar" "@sh_allparams@"`.

- [ ] **Step 2: Regenerate and smoke**

Run: `./nqp/gradlew -p nqp generateRunner 2>&1 | tail -3`, then `RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'say(nqp::x("ab", 3))'`
Expected: `ababab`.

- [ ] **Step 3: Commit (nqp tree)**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git add buildSrc/src/main/kotlin/GenerateRunnerTask.kt tools/templates/jvm/nqp-j.in && git commit -F - <<'EOF'
runners enter through UnitMain (either road)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRn8gLyZjirBAKS6urb3n4
EOF
```

---

### Task 9: Milestone 1 gate

**Files:**
- Modify (docs, rakudo tree): `docs/jvm-truffle-only-plan.md` (Position table rows 5 and 6), `docs/jvm-strict-campaign-handoff.md` (a "milestone 1" note)

- [ ] **Step 1: Clean artifact build**

```bash
NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 NQP_CODE_STRICT=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/b945970f/tmp/build-gate.log --show='> Task :stage' --show='BUILD' --show='rror' -- ./nqp/gradlew -p nqp clean buildJvm
```

Expected: `BUILD SUCCESSFUL`; record the wall time from the log's last elapsed marker. Then:

```bash
for j in nqp/build/jvm/stage2/*.jar nqp/build/jvm/share/lib/*.jar; do echo "$j meta=$(unzip -l $j | grep -c 'unit.meta') class=$(unzip -l $j | grep -c '\.class')"; done
```

Expected: every line `meta=1 class=0` (NQPP5QRegex.jar included, it is compiled by the stage2 compiler).

- [ ] **Step 2: Smoke**

`RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'say("artifact ok")'`
Expected: `artifact ok`.

- [ ] **Step 3: Full t/nqp through the runner**

From the rakudo worktree root, the campaign's own command:

```bash
NQP_JVM_MAXHEAP=2g RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/b945970f/tmp/tnqp-gate.log -t=nqp/t/nqp --jobs=3 -- nqp/nqp-j-gradle
```

Expected: 113 files pass (019-file-ops and 063-slurp are cwd-relative and pass only from the `nqp/` directory; 111/113 from the root is the campaign's baseline). Anything else failing is a runtime regression: triage with `NQP_CODE_WHY=1`/`NQP_CODE_TRACE=1` per the handoff doc's playbook, fix, rebuild (one compile per change), rerun.

- [ ] **Step 4: Record**

In `docs/jvm-truffle-only-plan.md`'s Position table, rows 5 and 6 become `milestone 1 DONE <date>: nqp stage2 as artifacts (nqp <hash>), t/nqp <n>/113 through the runner; build <s> s, suite <s> s`. Append the same line under "Where we are" in `docs/jvm-strict-campaign-handoff.md`. Commit in the rakudo tree:

```bash
git add docs/jvm-truffle-only-plan.md docs/jvm-strict-campaign-handoff.md && git commit -F - <<'EOF'
docs: unit artifact milestone 1 landed (nqp stage2 as artifacts, t/nqp through the runner)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRn8gLyZjirBAKS6urb3n4
EOF
```

Push both trees: `git push ab5tract worktree-jesp-direct-lazy-records` (rakudo) and, in the nqp dir, `git push ab5tract jesp-direct-lazy-records && git push origin jesp-direct-lazy-records`.

---

### Task 10: Post-completion gate, once on the green changeset

Run only after Task 9 is green in full (user rule: not per change).

- [ ] **Step 1: Rakudo on the artifact nqp, class road**

From the rakudo worktree root:

```bash
perl Configure.pl --backends=jvm --gen-nqp 2>&1 | tail -3
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/b945970f/tmp/rakudo-gate.log --show='Compiling' --show='Generating' --show='rror' -- make
```

Expected: `rakudo-j` built (the Makefile exports the knobs; `NQP_UNIT` is NOT set here, so Rakudo's units take the class road while the nqp they load are artifacts). `Configure.pl --gen-nqp` re-runs gradle `buildJvm`; export `NQP_UNIT=1` for that step so nqp stays on artifacts.

- [ ] **Step 2: t/01-sanity**

```bash
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/b945970f/tmp/sanity-gate.log -t=t/01-sanity --jobs=2 -- ./rakudo-j
```

Expected: 25/25. A failure here is a class-road unit loading an artifact unit's code refs across the boundary (Rakudo's `Perl6::*` class-file units call into nqp's artifact units); triage from the first failing file with `NQP_CODE_WHY=1` on that file's compile and `NQP_CODE_TRACE=1` on its run.

- [ ] **Step 3: Baseline and report**

Record BOOTSTRAP v6c, CORE.c stage timings from the make log and the sanity wall time next to the milestone line in `docs/jvm-truffle-only-plan.md` (forward-only rule: these are the next baseline). Commit and push as in Task 9 step 4.
