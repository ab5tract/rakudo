### Task 1: The record road in the runtime

**Files:**
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitWriter.kt` (whole file, 114 lines)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt:17-58, 104-111`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitRecord.kt:7`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/EvalResult.kt`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/GlobalContext.kt:228-235`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt:9000-9034` (`loadcompunit`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/Syscalls.kt:478-485` (beside `jvm-write-unit`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CodeEngine.kt:116-128` (`materialize`)
- Test: `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/ProgramUnitTest.kt`

**Interfaces:**
- Consumes (milestone 1): `UnitRecord(meta, programs, serialized, nested)`, `UnitMeta(..., nestedIds)`, `ProgramUnit(record)`, `JastClass.nestedClasses: MutableList<String>`, `JastClass.className`, `Syscalls`' private `obj(value: SixModelObject?)` helper (line 88) and `define(name, vararg kinds)`.
- Produces: `UnitWriter.record(jast: SixModelObject?, jastNodes: SixModelObject?, tc: ThreadContext): UnitRecord`; `UnitWriter.write(jast, jastNodes, filename, tc)` unchanged in signature; `EvalResult.record: UnitRecord?`; `GlobalContext.inMemoryUnitRecords: ConcurrentHashMap<String, UnitRecord>`; syscall `jvm-build-unit` (OBJ jast, OBJ jastnodes) -> `EvalResult` with `record` set; `ProgramUnit.lookupCodeRef(uniqueId: String): CodeRef?`; `nqp::loadcompunit` accepting an `EvalResult` whose `record` is set.

- [ ] **Step 1: Write the failing test (cuid lookup on a ProgramUnit)**

In `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/ProgramUnitTest.kt`, change the `block` helper to take a cuid and add a test:

```kotlin
    private fun block(name: String, prog: Int, outer: Int, handlers: LongArray = longArrayOf(0), cuid: String? = null) = BlockRec(
        name, cuid, outer, arrayOf("\$a", "\$b"), arrayOf(), arrayOf(), arrayOf(),
        handlers, false, false, "u.nqp", 1, 0, null, null, null, prog)

    @Test
    fun cuidLookupFollowsTheBlockTable() {
        val meta = UnitMeta("U2", "nqp", null, null, -1, 0, -1, -1, -1, listOf(),
            arrayOf(block("<mainline>", 0, -1, cuid = "cuid_1"), block("inner", 1, 0, cuid = "cuid_2"), block("nocuid", 2, 0)),
            listOf(), listOf())
        val u = ProgramUnit(UnitRecord(meta, arrayOf("p0", "p1", "p2"), null, mapOf()))
        u.buildTable(null)
        val t = u.qbidToCodeRef!!
        assertSame(t[1], u.lookupCodeRef("cuid_2"))
        assertSame(t[0], u.lookupCodeRef("cuid_1"))
        assertEquals("cuid_2", t[1]!!.staticInfo.uniqueId)
        assertNull(u.lookupCodeRef("cuid_9"))
        assertNull(u.lookupCodeRef(""))
    }
```

- [ ] **Step 2: Run it to verify it fails**

Run from the rakudo worktree root: `./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.runtime.unit.ProgramUnitTest' 2>&1 | tail -15`
Expected: FAIL on `cuidLookupFollowsTheBlockTable` (`lookupCodeRef("cuid_2")` is null: the base class's private `cuidToCodeRef` map is never filled by `buildTable`).

- [ ] **Step 3: ProgramUnit: cuid table and the in-memory nested fallback**

In `ProgramUnit.kt`, add a field after `private val meta get() = record.meta`:

```kotlin
    /** cuid -> code ref, for the blocks that carry one: a nested unit's
     *  (claimed by cuid) and a runtime-compiled unit's (re-pointed by cuid
     *  through jvm-repoint-dynamic-code, looked up by nqp::getcodecuid
     *  users). Jar-bound comp-mode units write no cuids and leave it empty. */
    private val byCuid = HashMap<String, CodeRef>()
```

In `buildTable`, right after `sci.methodName = "qb_$qbid"`:

```kotlin
            b.cuid?.let { if (it.isNotEmpty()) byCuid[it] = cr }
```

After `override fun lookupCodeRef`-less section (put it next to `override fun unitId()`):

```kotlin
    override fun lookupCodeRef(uniqueId: String): CodeRef? = byCuid[uniqueId]
```

Replace `claimNested`:

```kotlin
    /** A nested unit rides in the parent's zip (a loaded artifact) or, for
     *  a parent that is itself a record in memory, in the process's
     *  retention map -- the same map the writer embeds from. */
    override fun claimNested(tc: ThreadContext, name: String): CompilationUnit {
        val rec = record.nested[name] ?: tc.gc.inMemoryUnitRecords[name]
            ?: throw ExceptionHandling.dieInternal(tc, "unit ${unitId()} carries no nested unit named $name")
        val nested = ProgramUnit(rec)
        nested.shared = tc.gc.sharingHint
        nested.initializeCompilationUnit(tc, false)
        return nested
    }
```

In `UnitRecord.kt` line 7 change the comment on `cuid` to `// written for a nested or a runtime-compiled unit; null on a jar-bound comp-mode block`.

- [ ] **Step 4: EvalResult and GlobalContext**

`EvalResult.kt` becomes:

```kotlin
package org.raku.nqp.runtime

import org.raku.nqp.jast2bc.JavaClass
import org.raku.nqp.runtime.unit.UnitRecord
import org.raku.nqp.sixmodel.SixModelObject

/** A runtime compile's output before and after loadcompunit: the class
 *  road hands over class bytes, the record road (NQP_UNIT) a unit record;
 *  loadcompunit turns either into cu and clears the input it consumed. */
class EvalResult : SixModelObject() {
    @JvmField var jc: JavaClass? = null
    @JvmField var record: UnitRecord? = null
    @JvmField var cu: CompilationUnit? = null
}
```

In `GlobalContext.kt`, directly after the `inMemoryUnitOfCuid` declaration (line 235):

```kotlin
    /* The record road's twin of inMemoryUnitBytes: a unit compiled in
     * memory under NQP_UNIT while a compilation is under way, kept as its
     * record so the enclosing unit's writer can embed it under nested/
     * and a record parent can claim it. Keyed by unit id (the JAST class
     * name); inMemoryUnitOfCuid indexes into it on either road. */
    @JvmField val inMemoryUnitRecords: java.util.concurrent.ConcurrentHashMap<String, org.raku.nqp.runtime.unit.UnitRecord> = java.util.concurrent.ConcurrentHashMap()
```

- [ ] **Step 5: UnitWriter: record() split, nested from the registry**

Replace `UnitWriter.write` with a `record` function and a thin `write`. The class doc gains one sentence: "`record` is the record road's entry: the same reading, no file." Full new body of the object (keep `strs` and `strList` as they are):

```kotlin
object UnitWriter {
    /** Reads the JAST tree as a unit record. Refuses (a hard error naming
     *  the unit) a tree not compiled on the unit road, one with bytecode
     *  fallbacks, a block without a qbid or a program, two blocks sharing
     *  a qbid, and a nested unit id with no retained record. */
    @JvmStatic
    fun record(jast: SixModelObject?, jastNodes: SixModelObject?, tc: ThreadContext): UnitRecord {
        if (jast == null || jastNodes == null)
            throw ExceptionHandling.dieInternal(tc, "unit record: needs a JAST tree and the node types")
        JASTCompiler.ensureSetup(jastNodes, tc)
        val classType = jastNodes.at_key_boxed(tc, "JAST::Class")!!
        val methodType = jastNodes.at_key_boxed(tc, "JAST::Method")!!
        val jc = JastClass(jast, classType, tc)
        if (!jc.unitRoad)
            throw ExceptionHandling.dieInternal(tc, "unit record: ${jc.className} was not compiled on the artifact road")
        if (jc.fallbacks != 0)
            throw ExceptionHandling.dieInternal(tc, "unit record: ${jc.className} has ${jc.fallbacks} bytecode fallback bodies")

        /* Nested units (BEGIN-time compiles whose code refs this unit's
         * serialization points into) were retained as records by
         * loadcompunit; a missing one is a road mix-up, never a fallback. */
        val nested = LinkedHashMap<String, UnitRecord>()
        for (id in jc.nestedClasses) {
            nested[id] = tc.gc.inMemoryUnitRecords[id]
                ?: throw ExceptionHandling.dieInternal(tc, "unit record: ${jc.className} names nested unit $id, of which no record was retained")
        }

        /* Blocks, keyed by qbid; the table is sized by the highest qbid. */
        val blocks = ArrayList<Pair<Int, BlockRec>>()
        var maxQbid = -1
        val iter = Ops.iter(jc.methods, tc)
        while (Ops.istrue(iter, tc) != 0L) {
            val m = JastMethod(iter.shift_boxed(tc)!!, methodType, tc)
            if (m.crOuter == -2) continue                     // not a code ref (hllName, getCallSites, main...)
            if (m.crQbid < 0)
                throw ExceptionHandling.dieInternal(tc, "unit record: block ${m.name} has no qbid")
            if (m.crProgram < 0)
                throw ExceptionHandling.dieInternal(tc, "unit record: block ${m.crName} (${m.name}) has no program")
            val cuid = if (m.crCuid.isNullOrEmpty()) null else m.crCuid
            blocks.add(m.crQbid to BlockRec(
                m.crName ?: "", cuid, m.crOuter,
                strs(m.crOlex), strs(m.crIlex), strs(m.crNlex), strs(m.crSlex),
                m.crHandlers, m.hasExitHandler, m.isThunk,
                m.crFile, m.crLine, m.crRawLine - m.crLine,
                m.crSectionRaw, m.crSectionLine,
                m.crSectionFile?.let { f -> Array(f.size) { f[it] ?: "" } },
                m.crProgram))
            if (m.crQbid > maxQbid) maxQbid = m.crQbid
        }
        val table = arrayOfNulls<BlockRec>(maxQbid + 1)
        for ((q, b) in blocks) {
            if (table[q] != null)
                throw ExceptionHandling.dieInternal(tc, "unit record: two blocks with qbid $q")
            table[q] = b
        }

        val programs = strList(jc.programs, tc)
        for ((q, b) in blocks)
            if (b.programIndex >= programs.size)
                throw ExceptionHandling.dieInternal(tc, "unit record: block qbid $q names program ${b.programIndex} of ${programs.size}")
        val callSites = ArrayList<CallSiteRec>()
        jc.callsites?.let { cs ->
            val csIter = Ops.iter(cs, tc)
            while (Ops.istrue(csIter, tc) != 0L) {
                val row = csIter.shift_boxed(tc)!!
                val flagsObj = row.at_pos_boxed(tc, 0)!!
                val flags = ByteArray(Ops.elems(flagsObj, tc).toInt()) {
                    flagsObj.at_pos_boxed(tc, it.toLong())!!.get_int(tc).toByte()
                }
                val names = strList(row.at_pos_boxed(tc, 1), tc)
                callSites.add(CallSiteRec(flags, if (names.isEmpty()) null else names))
            }
        }
        val lexValues = ArrayList<LexValueRec>()
        jc.blockvalues?.let { bv ->
            val bvIter = Ops.iter(bv, tc)
            while (Ops.istrue(bvIter, tc) != 0L) {
                val row = bvIter.shift_boxed(tc)!!
                lexValues.add(LexValueRec(
                    row.at_pos_boxed(tc, 0)!!.get_int(tc).toInt(),
                    row.at_pos_boxed(tc, 1)!!.get_str(tc)!!,
                    row.at_pos_boxed(tc, 2)!!.get_str(tc)!!,
                    row.at_pos_boxed(tc, 3)!!.get_int(tc).toInt(),
                    row.at_pos_boxed(tc, 4)!!.get_int(tc).toInt()))
            }
        }
        val meta = UnitMeta(
            jc.className!!, jc.hll?.ifEmpty { null } ?: "nqp",
            jc.scHandle?.ifEmpty { null }, jc.scDesc?.ifEmpty { null },
            jc.serializedCount, jc.mainlineQbid, jc.entryQbid, jc.deserializeQbid, jc.loadQbid,
            callSites, table, lexValues, nested.keys.toList())
        return UnitRecord(meta, programs, jc.serialized, nested)
    }

    /** The artifact writer: the record, zipped to a file. */
    @JvmStatic
    fun write(jast: SixModelObject?, jastNodes: SixModelObject?, filename: String?, tc: ThreadContext) {
        if (filename == null)
            throw ExceptionHandling.dieInternal(tc, "jvm-write-unit: needs a filename")
        val record = record(jast, jastNodes, tc)
        try {
            FileOutputStream(filename).use { UnitZip.write(record, it) }
        } catch (e: java.io.IOException) {
            throw ExceptionHandling.dieInternal(tc, e)
        }
        if (System.getenv("NQP_CODE_WHY") != null)
            System.err.println("unit artifact ${record.meta.unitId} -> $filename " +
                "(${record.programs.size} programs, ${record.meta.blocks.size} qbids, " +
                "${record.meta.callSites.size} call sites, ${record.nested.size} nested)")
    }
```

(The program-index upper-bound check is milestone 1's deferred minor 1, folded in here since the loop is being rewritten anyway.)

- [ ] **Step 6: The syscall and loadcompunit**

In `Syscalls.kt`, directly after the `jvm-write-unit` definition:

```kotlin
        /* Builds the compiling unit's record in memory -- the record road
         * for a script, an EVAL, a BEGIN-time unit, or a --target=jar with
         * no --output under NQP_UNIT -- for nqp::loadcompunit to turn into
         * a ProgramUnit: no zip, no class. */
        define("jvm-build-unit", OBJ, OBJ) { args ->
            val res = org.raku.nqp.runtime.EvalResult()
            res.record = org.raku.nqp.runtime.unit.UnitWriter.record(args.obj(0), args.obj(1), args.tc)
            obj(res)
        }
```

In `Ops.kt`, replace `loadcompunit` (lines 9000-9034):

```kotlin
    /** Turns a runtime compile's output into a live unit: on the class
     *  road by defining the class and instantiating it, on the record
     *  road (NQP_UNIT) by building a ProgramUnit from the record. Either
     *  way the unit is initialized under the compilee's HLL config when
     *  asked, and retained for nested embedding while a compilation is
     *  under way. */
    @JvmStatic
    fun loadcompunit(obj: SixModelObject?, compileeHLL: Long, tc: ThreadContext): SixModelObject? {
        try {
            val res = obj as EvalResult
            val rec = res.record
            val unitName: String
            if (rec != null) {
                val u = org.raku.nqp.runtime.unit.ProgramUnit(rec)
                u.shared = false
                res.cu = u
                unitName = rec.meta.unitId
                if (System.getenv("NQP_CODE_WHY") != null)
                    System.err.println("unit record $unitName (${rec.programs.size} programs, ${rec.meta.blocks.size} qbids)")
            }
            else {
                val cuClass = tc.gc.byteClassLoader.defineClass(res.jc!!.name, res.jc!!.bytes!!)
                res.cu = cuClass.newInstance() as CompilationUnit
                unitName = res.jc!!.name!!
            }
            if (compileeHLL != 0L)
                usecompileehllconfig(tc)
            res.cu!!.initializeCompilationUnit(tc)
            if (compileeHLL != 0L)
                usecompilerhllconfig(tc)
            /* A unit compiled while a compilation is under way may be a
             * nested unit whose code refs the enclosing serialization
             * points into; retain what embedding it later needs, on the
             * road it was compiled on. */
            if (!tc.compilingSCs.isNullOrEmpty()) {
                if (rec != null)
                    tc.gc.inMemoryUnitRecords[unitName] = rec
                else
                    tc.gc.inMemoryUnitBytes[unitName] = res.jc!!.bytes!!
                res.cu!!.codeRefs?.let { crs ->
                    for (cr in crs) {
                        val cuid = cr.staticInfo.uniqueId
                        if (!cuid.isNullOrEmpty())
                            tc.gc.inMemoryUnitOfCuid[cuid] = unitName
                    }
                }
            }
            res.jc = null
            res.record = null
            return obj
        }
        catch (e: ControlException) {
            throw e
        }
        catch (e: Exception) {
            throw RuntimeException(e)
        }
    }
```

Update the doc comment of `jvmclassofcuid` (line 8929-8930) to: "The unit an in-memory compiled block belongs to (a class name on the class road, a unit id on the record road), when one was retained for nested-unit persistence; empty string otherwise."

- [ ] **Step 7: materialize through the programs map**

In `CodeEngine.kt`, `materialize`, replace the line `val program = engine.compile(sci.compUnit.engineProgram(sci.programIndex))` with:

```kotlin
            val program = programs.computeIfAbsent(sci.compUnit.engineProgram(sci.programIndex)) { engine.compile(it) }
```

and add to its doc comment: "Compiles through the same per-string cache as codeRun, so a program reached first by a stub and later by the direct road (or the reverse) compiles once."

- [ ] **Step 8: Build the runtime jars and run the Kotlin tests**

Run from the rakudo worktree root: `./nqp/gradlew -p nqp :nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars 2>&1 | tail -20`
Expected: `BUILD SUCCESSFUL`, all tests in `ProgramUnitTest` (now 5) and `UnitFormatTest` (10) pass. If `:nqp-runtime:test` reports the test count, expect 15.

- [ ] **Step 9: Smoke both roads on the existing stage2 artifacts**

The stage2 jars are artifacts (milestone 1); the runtime jar changed, so a load and a runtime compile on each road must still work. From the rakudo worktree root:

```
RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'say(6*7)'
```
Expected: `42` (class-road runtime compile of the `-e` unit: `jvm-build-unit` is not yet called, Compiler.nqp still decides the road with the milestone-1 rule).

```
RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle nqp/t/nqp/123-unit-artifact.t
```
Expected: `1..8` and eight `ok` lines (the writer still writes; the record split changed no output).

- [ ] **Step 10: Commit (nqp tree)**

```
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git add src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitWriter.kt src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitRecord.kt src/vm/jvm/runtime/org/raku/nqp/runtime/EvalResult.kt src/vm/jvm/runtime/org/raku/nqp/runtime/GlobalContext.kt src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt src/vm/jvm/runtime/org/raku/nqp/dispatch/Syscalls.kt src/vm/jvm/runtime/org/raku/nqp/runtime/CodeEngine.kt nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/ProgramUnitTest.kt && git commit -m "unit artifact: the record road in the runtime -- jvm-build-unit, loadcompunit builds a ProgramUnit from the record, nested records retained and embedded

Milestone 2 of docs/superpowers/specs/2026-09-09-jvm-unit-artifact-design.md
(rakudo tree). UnitWriter.record() is the reading half of the writer;
write() zips it. A runtime compile under NQP_UNIT hands its JAST to
jvm-build-unit and gets an EvalResult carrying the record; loadcompunit
makes a ProgramUnit of it where the class road defines a class. A record
compiled while a compilation is under way is kept in
GlobalContext.inMemoryUnitRecords, from which the parent's writer fills
nested/ (the milestone-1 refusal is gone) and a record parent claims it.
ProgramUnit answers lookupCodeRef(cuid) from its block table (runtime
units write cuids; jvm-repoint-dynamic-code needs them). materialize
compiles through the programs map (milestone-1 review minor 4).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011k7PcwZi8KjqW3yLn4GNvi"
```

---

