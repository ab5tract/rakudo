# JVM Unit Artifact, Milestone 2: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Under `NQP_UNIT=1`, a runtime compile (a script run directly, `-e`, an EVAL, a BEGIN-time unit compiled while a parent compiles) builds a `ProgramUnit` in memory from the same record the writer uses, with no class definition; a BEGIN-time unit so built is embedded under `nested/` in its parent's artifact, lifting the writer's milestone-1 refusal.

**Architecture:** The writer splits into `UnitWriter.record()` (JAST tree -> `UnitRecord`, no file) and `write()` (record -> zip). A new syscall `jvm-build-unit` returns an `EvalResult` carrying the record; `nqp::loadcompunit` turns it into a `ProgramUnit` where it used to define a class, and retains the record in `GlobalContext.inMemoryUnitRecords` (the record road's twin of `inMemoryUnitBytes`) when a compilation is under way, so the parent's writer can embed it. On the compiler side, `$*UNIT_ROAD` becomes "the knob is set" for every unit, and `HLL::Backend::JVM.classfile` routes a unit-road unit without a jar output to the new syscall.

**Tech Stack:** Kotlin 2.4 (nqp-runtime), NQP (Compiler.nqp, TruffleEncoder.nqp, HLL/Backend.nqp), gradle, java.util.zip, lz4-java.

**Spec:** `docs/superpowers/specs/2026-09-09-jvm-unit-artifact-design.md` (rakudo worktree), section "Milestones" item 2, and section 2's last paragraph ("A runtime compile constructs the same `ProgramUnit` in memory from the same record, with no zip and no class definition"). Milestone 1's plan and ledger sit beside this file (`2026-09-09-jvm-unit-artifact-milestone-1.md`, `.ledger.md`); this plan starts from where they stopped.

## Global Constraints

- Two git trees: rakudo worktree root `/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records` (docs, gate) and the nested `nqp/` tree (all code). Every nqp path below is under `nqp/`; nqp git commands run as `cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git ...` in their own shell call (the worktree guard refuses `git -C nqp`). Label hashes by tree.
- Kotlin, never Java, for new code (user rule). Existing Java files get minimal edits (none are planned here).
- Every diagnostic print is env-gated (`System.getenv(...)` / `nqp::getenvhash()`); never a bare print.
- Wire-program changes must be additive (stage0 ships old programs). This plan adds no wire op and changes no wire layout.
- Framing is by byte, never by grapheme. The meta format version stays 1: nothing in the format changes (nested entries were already defined in milestone 1).
- Runtime-jar-only changes rebuild with `./nqp/gradlew -p nqp :nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars` (~10-20 s) from the rakudo worktree root; a Compiler.nqp / TruffleEncoder.nqp / Backend.nqp change needs `./nqp/gradlew -p nqp clean buildJvm` (~5 min) through `raku tools/build/watched-run.raku` as a background job with a log under `/home/longwalker/.claude/jobs/3420e344/tmp/`.
- Every build and run carries `RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1`; the artifact road additionally needs `NQP_UNIT=1`; stage builds also carry `NQP_CODE_STRICT=1` (the milestone-1 gate did).
- `java` is Oracle GraalVM 25.2.4.
- One compile per change (forward only): no A/B builds. Timings of a green build are the next baseline. Baseline at the start of this plan: `NQP_UNIT=1 clean buildJvm` 299 s (2026-09-09 16:20, this worktree), t/nqp 115/115 (113 from the rakudo root: 019-file-ops and 063-slurp are cwd-relative) in 487 s at 3 jobs.
- Runs longer than 30 s go through `raku tools/build/watched-run.raku` (`--log=`, `--show=` literals, `-t=DIR --jobs=N` for test sweeps); look for its `=== EXIT=<n> verdict=<v> elapsed=<s>s ===` line. Tooling is Raku, never Python or shell scripts.
- Commit trailer on every commit:
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_011k7PcwZi8KjqW3yLn4GNvi`

## Deviations from the spec, stated up front

1. **The record road stays behind `NQP_UNIT`; the deletions move to milestone 3.** The spec's milestone-2 line ends "the string-constant road, its size gate, and `ByteClassLoader`'s define road go". They cannot go yet: Rakudo builds and runs on the class road until milestone 3 (its runtime compiles still need the per-block bytecode fallback for the two item-7 shapes, exit-handler blocks above all), and Rakudo's CORE.c jar carries four BEGIN-time nested units as class entries today, which the class-road parent must keep embedding as classes. So in milestone 2 the road is decided per process by the knob, for every unit alike: knob on = jar-bound units are written as artifacts and everything else is a record in memory; knob off = the class road exactly as before, string constants, define road, nested `.class` entries included. The knob also gates the retention map used for nested embedding, so a class-road parent never meets a record nested unit and vice versa. The three deletions, plus `CodeEngines.codeRun(String)`, `$as_index`'s class-road half, the encoder's `:sidecar` parameter and the 60000-char gate, `inMemoryUnitBytes` and the nested `.class` embedding, are milestone 3's closing item, when Rakudo flips and the knob becomes the default.
2. **No NQP-side nested-unit test exists, by construction.** An NQP `BEGIN` compiles its block through `World.create_code`'s dynamic thunk, but the resulting code refs are re-pointed at the unit's own emission of the same cuids (`jvm-repoint-dynamic-code`), so the serialized graph never points into the nested unit and nothing is embedded (probe 2026-09-09: a module with `class NestFoo { method foo() { 42 } }; BEGIN { NestFoo.foo() }` compiled to one class entry). Nested embedding is exercised by the Kotlin round trip (milestone 1's `UnitFormatTest.zipRoundTrips` already carries a nested entry) and by the Rakudo probe in Task 4, which is informative, not a gate: Rakudo units on the unit road are milestone 3's work and the probe may stop on an item-7 shape.

## Booked from milestone 1's ledger (all land here)

- (a) `splice_code(%e, @words, $at)` in the encoder: the four hand-shift splice sites become one helper (Task 2).
- Final-review minor 4: `CodeEngines.materialize` compiles through the `programs` map, not `engine.compile` directly, so a program reached by both roads compiles once (Task 1).
- Final-review minor 6: `$*UNIT_ROAD` no longer needs `--output`; `--target=jar` without one takes the record road instead of building a unit-road JAST for the class assembler (Task 2).
- Final-review minor 7: the compiler dies once, at the road decision, when `NQP_CODE_RUN`/`NQP_CODE_PRECOMP` are unset under the knob, instead of once per block at the fallback junction (Task 2).

## File structure

All code changes are in the nqp tree. New: none (the road reuses milestone 1's files). Modified:

| file | change |
|---|---|
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitWriter.kt` | `record()` split out of `write()`; nested units filled from `inMemoryUnitRecords` instead of refused |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt` | cuid table + `lookupCodeRef(String)` override; `claimNested` falls back to the in-memory registry |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitRecord.kt` | comment on `BlockRec.cuid` |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/EvalResult.kt` | `record` field |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/GlobalContext.kt` | `inMemoryUnitRecords` |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt` | `loadcompunit`'s record branch and retention |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/Syscalls.kt` | `jvm-build-unit` |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CodeEngine.kt` | `materialize` via the programs map |
| `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/ProgramUnitTest.kt` | cuid lookup test |
| `nqp/src/vm/jvm/QAST/Compiler.nqp` | road decision (knob only), knob checks, `$as_index`, wrapper condition, comments |
| `nqp/src/vm/jvm/HLL/Backend.nqp` | `classfile` routes unit-road units without a jar output to `jvm-build-unit` |
| `nqp/src/vm/jvm/QAST/TruffleEncoder.nqp` | `splice_code` helper replacing four splice+shift sites |
| `nqp/src/vm/jvm/QAST/JASTNodes.nqp` | comment on `@!nested_classes` |
| `nqp/t/nqp/124-unit-record.t` | new test |
| rakudo `docs/jvm-truffle-only-plan.md`, spec, this plan's ledger, memory | Task 5 |

---

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

### Task 2: The compiler takes every unit down the road under the knob

**Files:**
- Modify: `nqp/src/vm/jvm/QAST/Compiler.nqp:4101-4113` (road decision), `:4152` (wrapper condition), `:4349-4356` (comment), `:4699-4709` (`$as_index`), `:4317-4327` (census line)
- Modify: `nqp/src/vm/jvm/HLL/Backend.nqp:79-106` (`classfile`)
- Modify: `nqp/src/vm/jvm/QAST/TruffleEncoder.nqp:919-943, 1044-1050, 1053-1072, 2601-2612` (splice sites)
- Modify: `nqp/src/vm/jvm/QAST/JASTNodes.nqp:65` (comment)

**Interfaces:**
- Consumes (Task 1): syscall `jvm-build-unit` (OBJ, OBJ) -> `EvalResult`; `nqp::loadcompunit` on a record-bearing `EvalResult`; `NQP_CODE_WHY` line `unit record <id> ...` on stderr.
- Produces: `$*UNIT_ROAD` = 1 for every unit when `NQP_UNIT` is set; `HLL::Backend::JVM.classfile` returns an `EvalResult` for a unit-road unit without `--target=jar --output`; the encoder's `splice_code(%e, @words, int $at)`.

- [ ] **Step 1: Compiler.nqp, the road decision and the knob checks**

Replace lines 4101-4113 (the comment block and the `$*UNIT_ROAD` / `$*UNIT_FALLBACKS` declarations) with:

```nqp
        # The artifact road (rakudo docs/superpowers/specs/2026-09-09-jvm-
        # unit-artifact-design.md): under NQP_UNIT every unit is a record --
        # programs + block table (+ serialized context for a comp-mode
        # unit), no class file. A jar-bound unit with an output file is
        # written as a zip (milestone 1); any other unit -- a script, an
        # EVAL, a BEGIN-time unit, a --target=jar with no --output -- is
        # built in memory and loaded as a ProgramUnit (milestone 2). The
        # knob is all-or-nothing: the road is chosen before any block
        # compiles, so a block that cannot encode is a compile error, not
        # a quiet fallback to a class file that this road no longer emits
        # the pieces for. $*UNIT_FALLBACKS therefore stays 0 and travels
        # as the writer's defense. Off, the class road runs as before.
        my $*UNIT_ROAD := nqp::existskey(nqp::getenvhash(), 'NQP_UNIT') ?? 1 !! 0;
        my $*UNIT_FALLBACKS := 0;
        if $*UNIT_ROAD {
            # Every block must encode, so the encoder's own switches must
            # be on; said once here rather than once per block at the
            # fallback junction.
            my %env := nqp::getenvhash();
            nqp::die('unit artifact (NQP_UNIT): the road needs NQP_CODE_RUN=1 and NQP_CODE_PRECOMP=1 set, every block must encode')
                unless nqp::existskey(%env, 'NQP_CODE_RUN') && nqp::existskey(%env, 'NQP_CODE_PRECOMP');
            # A class file is the one output the road does not have.
            nqp::die('unit artifact (NQP_UNIT): --target=classfile has no artifact form; use --target=jar')
                if %*COMPILING<%?OPTIONS><target> eq 'classfile';
        }
```

- [ ] **Step 2: Compiler.nqp, the wrapper condition**

At line 4152, `if $*COMP_MODE || @pre_des || @post_des || need_set_code_object($cu) {`, change to:

```nqp
        # On the class road setup_blv sat in @post_des and made this true
        # by itself; the record road builds its static-lexical-value rows
        # inside this wrapper, so the wrapper must exist for them.
        if $*COMP_MODE || @pre_des || @post_des || need_set_code_object($cu)
            || ($*UNIT_ROAD && %*BLOCK_LEX_VALUES) {
```

- [ ] **Step 3: Compiler.nqp, `$as_index` and comments**

At lines 4699-4709 replace the comment and the `$as_index` declaration with:

```nqp
                # A jar-bound unit's programs travel in one sidecar,
                # referenced by index -- one string constant per
                # program overflowed CORE.c's constant pool (71010
                # entries against the 65535 limit) -- and on the unit
                # road every program is a byte-framed entry of the
                # record, on either output, with no constant and no cap.
                # Everything else keeps the string road. The encoder is
                # told which, so its per-program size gate (the string
                # constant's own 65535-byte cap) applies only where that
                # cap exists.
                my int $as_index := $*UNIT_ROAD
                    || ($*COMP_MODE && %*COMPILING<%?OPTIONS><target> eq 'jar');
```

At lines 4349-4356 (the opening comment of `deserialization_code`), change "Their classfiles ride along in the jar" to "Their units ride along in the jar (as class entries on the class road, under nested/ in an artifact)". At line 4326, change the census text to `' -> unit road'` (the writer and loadcompunit each say which output they produced).

In `JASTNodes.nqp` line 65 add above `method nested_classes`: `# Unit ids (class names on the class road) of nested in-memory units this unit's serialization points into.`

- [ ] **Step 4: Backend.nqp, route the record road**

Replace lines 79-106 of `classfile` (from `if (%adverbs<target> eq 'classfile' ...` through the closing `else { nqp::compilejast(...) }`) with:

```nqp
        if $jast.unit_road {
            # The artifact road (NQP_UNIT). A jar-bound unit with an
            # output file is written as a zip; every other unit -- a
            # script, an EVAL, a BEGIN-time unit, a --target=jar with no
            # --output -- is built in memory as a record, which the jvm
            # stage (nqp::loadcompunit) turns into a ProgramUnit. No class
            # file either way; Compiler.nqp refuses --target=classfile on
            # this road, and it is the writer, not this junction, that
            # refuses a unit with fallbacks (there are none: the compiler
            # died first).
            if %adverbs<target> eq 'jar' && %adverbs<output> {
                # The syscall's argument kinds are checked at the call
                # site; %adverbs<output> arrives boxed.
                my str $unit_output := %adverbs<output>;
                nqp::syscall('jvm-write-unit', $jast, %jastnodes, $unit_output);
                nqp::null()
            }
            else {
                nqp::syscall('jvm-build-unit', $jast, %jastnodes)
            }
        }
        elsif (%adverbs<target> eq 'classfile' || %adverbs<target> eq 'jar') && %adverbs<output> {
            nqp::compilejasttofile($jast, %jastnodes, %adverbs<output>);
            nqp::null()
        }
        else {
            nqp::compilejast($jast, %jastnodes);
        }
```

- [ ] **Step 5: TruffleEncoder.nqp, the splice_code helper**

Add, directly above `method patch_params` (line 919):

```nqp
    # Splices @words into the program at $at and moves every nested-block
    # slot the walk recorded by position at or after $at right by the
    # same amount, so the deferred qbid patch still lands on its CODEREF
    # cell. One rule serves both callers: a prologue goes in after its
    # placeholder ($at is the placeholder's index + 1, so the placeholder
    # itself stays put), a coercion goes in at the mark of the subtree it
    # wraps. Splicing without the shift wrote every deferred qbid over
    # the tag of a neighbouring node ("unknown tag 11142", 2026-09-09).
    sub splice_code(%e, @words, int $at) {
        nqp::splice(%e<code>, @words, $at, 0);
        my int $n := nqp::elems(@words);
        for %e<nested> -> $nb {
            nqp::bindpos($nb, 0, $nb[0] + $n) if $nb[0] >= $at;
        }
    }
```

Then replace the four sites:

1. `patch_params`, custom_args (lines 937-941): the `my @hdr := nqp::list(0, -1, 0);` line stays; replace the `nqp::splice(...)` line and the following `for %e<nested>` loop (three lines) with `splice_code(%e, @hdr, $params_at + 1);`. Trim the comment above (lines 928-936) to its first sentence plus "(splice_code moves the slots)".
2. `patch_params`, full prologue (lines 1044-1050): replace `nqp::splice(%e<code>, @p, $params_at + 1, 0);`, the two comment lines, and the `for` loop (three lines) with `splice_code(%e, @p, $params_at + 1);`.
3. `encode_child` (lines 1064-1070): replace the `nqp::splice(...)` line, the three comment lines and the `for` loop with `splice_code(%e, [$W_COERCE, $kind], $mark);`.
4. `coerce_at` (lines 2606-2609): replace the `nqp::splice(...)` line and the `for` loop with `splice_code(%e, [$W_COERCE, $kind], $mark);`.

Equivalence, for the reviewer: sites 1 and 2 shifted when `$nb[0] > $params_at`, which is `$nb[0] >= $params_at + 1`, the helper's rule at `$at = $params_at + 1`; sites 3 and 4 shifted when `$nb[0] >= $mark`, the helper's rule at `$at = $mark`.

- [ ] **Step 6: Clean stage build under the knob**

From the rakudo worktree root, as a background job:

```
NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 NQP_CODE_STRICT=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/3420e344/tmp/build-task2.log --show='> Task :stage' --show='BUILD' --show='rror' -- ./nqp/gradlew -p nqp clean buildJvm
```

Expected: `=== EXIT=0 verdict=ok elapsed=<about 300>s ===`. Then every stage2 jar is an artifact: for `nqp/build/jvm/share/lib/*.jar`, `unzip -l <jar> | grep -c unit.meta` is 1 and `unzip -l <jar> | grep -c '\.class'` is 0 (11 jars; write the loop as plain separate commands or a Raku one-liner, the worktree guard refuses shell loops over computed names). If the build fails inside a stage, read the log's first `rror` context: a die from Step 1's knob check means the gradle stage task lacks one of the three env vars; an "unknown tag" in a t/nqp file after the build means a splice_code site got the wrong `$at`.

- [ ] **Step 7: Smoke the record road**

From the rakudo worktree root:

```
NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 NQP_CODE_WHY=1 ./nqp/nqp-j-gradle -e 'say(6*7)' 2>&1 | grep -E '^42$|^unit record '
```
Expected: one `unit record <sha1> (...)` line and `42`.

```
NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e "say(nqp::getcomp('nqp').eval('my \$y := 5; \$y * 3'))"
```
Expected: `15`.

```
NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'say(1)' 2>&1 | head -2
```
Expected: the die from Step 1 naming `NQP_CODE_RUN=1` (the knob check fires once, before any block).

```
RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle nqp/t/nqp/123-unit-artifact.t
```
Expected: `1..8`, eight `ok`.

- [ ] **Step 8: Commit (nqp tree)**

```
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git add src/vm/jvm/QAST/Compiler.nqp src/vm/jvm/HLL/Backend.nqp src/vm/jvm/QAST/TruffleEncoder.nqp src/vm/jvm/QAST/JASTNodes.nqp && git commit -m "unit artifact: under NQP_UNIT every unit takes the road -- runtime compiles become records in memory

Compiler.nqp decides the road from the knob alone: a jar-bound unit with
an output is written (milestone 1), anything else is built in memory by
jvm-build-unit and loaded as a ProgramUnit (milestone 2); every unit-road
program is index-framed (no string constant, no size gate); the wrapper
block exists whenever static lexical values need their rows; the knob
checks NQP_CODE_RUN/NQP_CODE_PRECOMP once and refuses --target=classfile.
HLL::Backend::JVM routes accordingly. The encoder's four splice-and-shift
sites are one splice_code helper (milestone-1 ledger item a).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011k7PcwZi8KjqW3yLn4GNvi"
```

---

### Task 3: t/nqp/124-unit-record.t

**Files:**
- Create: `nqp/t/nqp/124-unit-record.t`

**Interfaces:**
- Consumes (Tasks 1, 2): the record road under `NQP_UNIT=1` for a script file and for `nqp::getcomp('nqp').eval`; the `NQP_CODE_WHY` marker `unit record `; the knob die text `needs NQP_CODE_RUN=1`; `--target=jar` without `--output` on the road.

- [ ] **Step 1: Write the test**

Model: `nqp/t/nqp/123-unit-artifact.t` (child processes because the road is chosen by an environment variable). The test asserts a positive marker that the road was taken (a script that merely runs would pass on the class road too).

```nqp
# Runs a script on the record road (NQP_UNIT=1, no --output): the unit is
# built in memory as a ProgramUnit, no class defined. A sub, a closure
# over the mainline, a handler, a regex, and two runtime EVALs (records
# themselves) must run; NQP_CODE_WHY must show the road was taken; the
# knob must refuse to run without the encoder switches; --target=jar with
# no --output must take the road rather than die.

plan(12);

my $is-windows := nqp::backendconfig()<osname> eq 'MSWin32';
if nqp::getcomp('nqp').backend.name ne 'jvm' || $is-windows {
    skip('the unit record road is JVM-only and driven through /bin/sh', 12);
}
else {
    my $dir := nqp::cwd() ~ '/t/nqp/124-unit-record.tmp';
    nqp::mkdir($dir, 0o777) unless nqp::stat($dir, nqp::const::STAT_EXISTS);
    my $script := $dir ~ '/record-script.nqp';

    sub spew($path, @lines) {
        my $fh := nqp::open($path, 'w');
        nqp::printfh($fh, nqp::join("\n", @lines) ~ "\n");
        nqp::closefh($fh);
    }

    spew($script, [
        'my $counter := 0;',
        'sub twice($x) { $x * 2 }',
        'sub counter() { $counter := $counter + 1; $counter }',
        'sub guarded($x) {',
        '    my $r := "no throw";',
        '    try { nqp::die("boom " ~ $x); CATCH { $r := "caught " ~ nqp::getmessage($_) } }',
        '    $r',
        '}',
        'sub matches($s) { $s ~~ /^ \d+ $/ ?? 1 !! 0 }',
        'say(twice(21));',
        'say(counter() ~ "," ~ counter());',
        'say(guarded("x"));',
        'say(matches("123") ~ matches("12a"));',
        'my $evaled := nqp::getcomp("nqp").eval(\'sub ($x) { $x + 1 }\');',
        'say($evaled(41));',
        'say(nqp::getcomp("nqp").eval(\'my $y := 5; $y * 3\'));',
        'class Kept { method answer() { 42 } }',
        'say(Kept.answer());',
    ]);

    # t/nqp runs from the nqp checkout; the rakudo build drives the same
    # files from a directory up.
    my %env := nqp::getenvhash();
    my $runner := nqp::existskey(%env, 'NQP_TEST_RUNNER')
        ?? %env<NQP_TEST_RUNNER>
        !! (nqp::stat(nqp::cwd() ~ '/nqp-j-gradle', nqp::const::STAT_EXISTS)
            ?? './nqp-j-gradle' !! 'nqp/nqp-j-gradle');

    sub sh($command) {
        run-command(nqp::list('/bin/sh', '-c', $command), :stdout, :stderr)
    }

    my @ran := sh("NQP_UNIT=1 NQP_CODE_WHY=1 $runner $script");
    my @out := nqp::split("\n", @ran[1]);
    unless nqp::elems(@out) >= 7 {
        say('# ' ~ @ran[1]);
        say('# ' ~ @ran[2]);
    }
    is(@out[0] // '', '42',            'a sub from a record unit runs');
    is(@out[1] // '', '1,2',           'a closure over the mainline keeps its outer');
    is(@out[2] // '', 'caught boom x', 'a handler in a record block catches');
    is(@out[3] // '', '10',            'a regex from a record unit matches and fails to match');
    is(@out[4] // '', '42',            'an EVAL returns a sub that runs (a record of its own)');
    is(@out[5] // '', '15',            'an EVAL of statements answers its value');
    is(@out[6] // '', '42',            'a class (a static lexical value) from a record unit resolves');

    # The positive marker: NQP_CODE_WHY names each record as loadcompunit
    # builds it -- the script and its two EVALs.
    my int $records := 0;
    for nqp::split("\n", @ran[2]) {
        $records := $records + 1 if nqp::index($_, 'unit record ') == 0;
    }
    ok($records >= 3, 'the script and both EVALs went down the record road (' ~ $records ~ ' records)');
    ok(nqp::index(@ran[2], '.class') < 0 && nqp::index(@ran[2], 'defineClass') < 0,
        'nothing on stderr mentions a class');

    my @knob := sh("env -u NQP_CODE_RUN NQP_UNIT=1 $runner -e 'say(1)'");
    ok(nqp::index(@knob[2], 'needs NQP_CODE_RUN=1') >= 0,
        'the road refuses to run without the encoder switches, once');
    ok(nqp::index(@knob[1], '1') < 0, 'and runs nothing');

    my @jar := sh("NQP_UNIT=1 $runner --target=jar $script");
    ok(nqp::index(@jar[2], 'rror') < 0 && nqp::index(@jar[2], 'nqpp:') < 0,
        '--target=jar without --output takes the record road without complaint');

    nqp::unlink($script) if nqp::stat($script, nqp::const::STAT_EXISTS);
    nqp::rmdir($dir) if nqp::stat($dir, nqp::const::STAT_EXISTS);
}
```

Note on the `--target=jar` case: `run-command` returns `[exit, stdout, stderr]`; a die would put its text on stderr. If `run-command`'s exit status is exposed as `@jar[0]`, prefer `ok(@jar[0] == 0, ...)`; check `nqp/src/core/testing.nqp` for the shape and use the stronger form when it is there.

- [ ] **Step 2: Run it**

From the rakudo worktree root: `RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle nqp/t/nqp/124-unit-record.t`
Expected: `1..12`, twelve `ok`. A `not ok` on the record count means the marker line changed or `NQP_CODE_WHY` did not reach the child; on the knob test it means Task 2 Step 1's message text differs.

Also run it from the nqp directory as the suite does: `cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp-j-gradle t/nqp/124-unit-record.t` -- expected the same.

- [ ] **Step 3: Commit (nqp tree)**

```
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git add t/nqp/124-unit-record.t && git commit -m "t/nqp/124: a script, its EVALs and --target=jar without --output on the record road (NQP_UNIT), with the road asserted

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011k7PcwZi8KjqW3yLn4GNvi"
```

---

### Task 4: The gate

**Files:** none modified (a report under `docs/superpowers/plans/2026-09-09-jvm-unit-artifact-milestone-2.reports/task-4-report.md`, written by the controller from this task's output).

**Interfaces:**
- Consumes: the Task 2 build (no compiler source changed since; Task 3 added a test only, so no rebuild: forward only).

- [ ] **Step 1: Confirm the artifacts of the standing build**

For each of the 11 jars in `nqp/build/jvm/share/lib/`: `unzip -l nqp/build/jvm/share/lib/nqp.jar | grep -c unit.meta` is 1 and `... | grep -c '\.class'` is 0 (repeat per jar as plain commands, or `raku -e 'for dir("nqp/build/jvm/share/lib", test => /\.jar$/) { say .basename, " ", run(<unzip -l>, $_, :out).out.slurp.lines.grep(/unit\.meta/).elems, " ", run(<unzip -l>, $_, :out).out.slurp.lines.grep(/"." class/).elems }'`).

- [ ] **Step 2: t/nqp on the record road (the milestone's coverage)**

With the knob on, every test file compiles as a record in memory. From the rakudo worktree root, background job:

```
NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 raku tools/build/watched-run.raku -t=nqp/t/nqp --jobs=3 --log=/home/longwalker/.claude/jobs/3420e344/tmp/sweep-record.log -- nqp/nqp-j-gradle
```

Expected: the SUMMARY shows 113 of 115 passing from the rakudo root (019-file-ops and 063-slurp are cwd-relative, milestone-1 baseline), then those two from the nqp directory: `cd .../nqp && NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp-j-gradle t/nqp/019-file-ops.t` and `063-slurp.t`, both all-ok. Anything else failing is a record-road regression: rerun the file alone with `NQP_CODE_WHY=1`, and compare against the knob-off run of the same file; triage the way the campaign did (the block named in the die, `NQP_CODE_BAIL=1` for the reason).

The sweep's elapsed time against milestone 1's 487 s (class-road test compiles on the same artifact stage2 jars) is the record road's compile-cost reading; no separate knob-off sweep (user, 2026-09-09: the Rakudo gate below already covers the class road).

- [ ] **Step 3: Rakudo post-completion gate (class road) and the record-road probes**

Rakudo's units compile through the changed Compiler.nqp and Backend.nqp, so its build is the gate that the class road is untouched. From the rakudo worktree root, background jobs, one after the other:

```
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/3420e344/tmp/rakudo-configure.log -- perl Configure.pl --backends=jvm --gen-nqp
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/3420e344/tmp/rakudo-make.log --show='Compiling' --show='Generating' --show='rror' --stall=1500 -- make
raku tools/build/watched-run.raku -t=t/01-sanity --jobs=2 --log=/home/longwalker/.claude/jobs/3420e344/tmp/sanity.log -- ./rakudo-j
```

Expected: configure EXIT=0; make EXIT=0 (milestone-1 timing: 1173 s from a clean jvm tree; the nqp part is already built so expect less); t/01-sanity 25/25. `--gen-nqp` rebuilds nqp through gradle without `clean`; since the stage2 jars are current it should be a no-op, but if it rebuilds, it rebuilds without `NQP_UNIT` and produces class-road stage2 jars: check Step 1's counts again afterwards and, if they changed, rerun Task 2 Step 6 before the sweeps count.

Then the probes (informative; a failure is reported, not fixed here):

```
NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 NQP_CODE_WHY=1 ./rakudo-j -e 'BEGIN { say 1 }; say EVAL "2"; say 3' 2>&1 | grep -E '^[123]$|^unit record |rror|nqpp:' 
```
Expected if Rakudo's runtime compiles encode fully: `1`, three `unit record` lines (the mainline, the BEGIN block, the EVAL), `2`, `3`. A die naming a block is an item-7 shape and goes in the report.

```
mkdir -p /home/longwalker/.claude/jobs/3420e344/tmp/probe && printf 'unit module BeginMod;\nmy &kept = BEGIN { my $n = 41; -> { $n + 1 } };\nsub answer() is export { kept() }\n' > /home/longwalker/.claude/jobs/3420e344/tmp/probe/BeginMod.rakumod
NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 NQP_CODE_WHY=1 ./rakudo-j --target=jar --output=/home/longwalker/.claude/jobs/3420e344/tmp/probe/BeginMod.jar /home/longwalker/.claude/jobs/3420e344/tmp/probe/BeginMod.rakumod 2>&1 | grep -E 'unit artifact|unit record|rror|nqpp:'
unzip -l /home/longwalker/.claude/jobs/3420e344/tmp/probe/BeginMod.jar
```
Expected if it gets that far: a `unit record` line for the BEGIN block, a `unit artifact ... 1 nested` line, and the listing shows `unit.meta`, `unit.programs`, `unit.serialized.lz4`, `nested/<id>.meta`, `nested/<id>.programs`, no `.class`. Loading it back through `use` needs the precomp store and is milestone 3's business; stop at the listing.

- [ ] **Step 4: Record timings**

Note in the report: Task 2 build elapsed, the sweep elapsed (against 487 s), make elapsed, sanity elapsed. These are the next baseline (forward only).

---

### Task 5: Docs, ledger, memory, push

**Files:**
- Modify: rakudo `docs/jvm-truffle-only-plan.md:30-31` (items 5 and 6 rows: milestone 2 DONE, what moved to milestone 3)
- Modify: rakudo `docs/superpowers/specs/2026-09-09-jvm-unit-artifact-design.md` "Milestones" item 2 (one sentence: the deletions moved to milestone 3, with the reason from this plan's deviation 1) and section 3's paragraph on nested units ("held in memory as a record ... written under `nested/`" is now true; the milestone-1 refusal note goes)
- Create/modify: this plan's `.ledger.md` and `.reports/` (the controller keeps them as it goes)
- Memory: `/home/longwalker/.claude/projects/-home-longwalker-code-raku-x-core-rakudo/memory/strict-refusal-campaign.md` or a new `unit-artifact-milestones.md` (milestone 2 state, the deviation, the milestone-3 entry list), plus its MEMORY.md line

- [ ] **Step 1: Update the plan doc and the spec** (text per the file list above; keep the table rows' existing milestone-1 text and append the milestone-2 sentence).
- [ ] **Step 2: Commit the rakudo tree** (docs only): `git add docs/ && git commit -m "docs: unit artifact milestone 2 -- runtime compiles as records in memory (plan, ledger, reports, spec and position updates)"` with the trailer.
- [ ] **Step 3: Push both trees to ab5tract** (`git push ab5tract worktree-jesp-direct-lazy-records` from the rakudo worktree; `cd .../nqp && git push ab5tract jesp-direct-lazy-records`). Never force-push; never push main.

---

## Self-review notes

- Spec coverage: milestone-2 line, first half ("build a ProgramUnit from the record with no class definition") = Tasks 1-3; second half (deletions) = deviation 1, milestone 3. Section 2's nested-unit sentence ("asking the parent unit for the nested unit by id") = `ProgramUnit.claimNested` + `record.nested` (Task 1). Section 3's "held in memory as a record ... written under `nested/`" = `inMemoryUnitRecords` + `UnitWriter.record` (Task 1). Section 5 "never a fallback to a class-file twin" = the writer's missing-record die and the knob-only road decision (Tasks 1, 2).
- Types: `UnitWriter.record(jast: SixModelObject?, jastNodes: SixModelObject?, tc: ThreadContext): UnitRecord` (Task 1) is what `jvm-build-unit` calls (Task 1) and what Backend.nqp reaches (Task 2). `EvalResult.record` is what `loadcompunit` reads (Task 1). `inMemoryUnitRecords` is written in `loadcompunit`, read in `UnitWriter.record` and `ProgramUnit.claimNested` (all Task 1).
- Names: the syscall is `jvm-build-unit` everywhere; the marker is `unit record ` (trailing space) in `loadcompunit` and in the test; the knob die contains `needs NQP_CODE_RUN=1` in Compiler.nqp and in the test.
