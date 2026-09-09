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

