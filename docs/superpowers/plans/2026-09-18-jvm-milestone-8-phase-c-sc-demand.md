# Milestone 8 Phase C: SC demand deserialization -- implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Shrink the serialized SC blob to a third with format version 12 (row c1), then read every SC on demand instead of at load (row c2), with the fixups left where they are and measured.

**Architecture:** The writer and reader in `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/` change format once (packed varint references, varint ints, a string offset table, an eight-byte object row, the root index carried on the object). Then the reader stays alive on its `SerializationContext`, whose three root-set getters become the barrier: a null root slot demands the entry; a drain finishes the transitive closure under one global lock and publishes every finished entry into its root slot at the drain's end. HOW, WHO and strings decode on first use.

**Tech Stack:** Kotlin (`nqp-runtime`: the codec, the writer, the reader, the context, `STable`), JUnit 5 via `kotlin("test")` for the codec and the context, nqp `.t` tests under `prove` with a child process reading stderr, Raku tools (`sc-blob-sizes.raku` new, `m7-rig.raku`, `unit-load-exclusive.raku`, `evalserver-sweep.raku`, `watched-run.raku`), gradle (`jBootstrapFiles` for the regen), `make`.

**Spec:** `docs/superpowers/specs/2026-09-18-jvm-milestone-8-phase-c-sc-demand-design.md` (Sections 1-4, the user decisions, the risks). Parent: `docs/superpowers/specs/2026-09-16-jvm-milestone-8-type-state-design.md` section 5 Phase C. Ledger of record for this phase: `docs/superpowers/plans/2026-09-18-jvm-milestone-8-phase-c.ledger.md` (Task 1 creates it).

## Global Constraints

- **Worktree only.** Every path below is relative to `/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records` (rakudo branch `worktree-jesp-direct-lazy-records`; nested `nqp/` on `jesp-direct-lazy-records`). Two git trees: `git` for rakudo, `git -C nqp` for nqp; label every hash with its tree. Never `cd`; pin paths. Gradle from the root: `./nqp/gradlew -p nqp ...`.
- **`RAKUDO_RAKUAST=1` on every build, test and run.** The Makefile exports it into its own recipes; nothing else does.
- **Kotlin, never Java**, for every new or rewritten file.
- **Every debug or diagnostic print env-gated** (`System.getenv(...)`, `nqp::getenvhash()`), never bare. The knobs this plan adds: `NQP_SC_EAGER`, `NQP_SC_VERIFY`; the stats line rides `NQP_UNIT_LOAD_STATS`.
- **No jar commits.** `nqp/src/vm/jvm/stage0/*.jar` are modified in the working tree by Task 5's regen and are NEVER committed (`git -C nqp add` only the named source files; check `git -C nqp status --short` before every commit).
- **Runtime-only rebuild** (Tasks 2, 3, 4, 6, 7): `./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars` (about 5 s), then retrain: `RAKUDO_RAKUAST=1 NQP_DISPATCH_RECORD=all /usr/bin/perl rakudo-j-build -e '' 2>&1 | grep -E 'dispatch-record: (done|FAILED)'`, then restart any eval server. Only Task 5 runs `make`.
- **Long runs through `raku tools/build/watched-run.raku --log=... --show=... --stall=...`**, never hand-rolled wrappers; logs under `/home/longwalker/.claude/jobs/a46e5ea6/tmp/` (call it `$T` below; it exists).
- **Gates and rows reported WITH wall times**; a failed benchmark run is recorded as not gathered, never re-run; `NQP_OP_CENSUS`, `NQP_DISPATCH_RECORD`, `NQP_SITES_OFF`, `NQP_DISPATCH_PERSIST`, `JAVA_TOOL_OPTIONS`, `NQP_SC_EAGER`, `NQP_SC_VERIFY` unset for a timed run unless the step sets one. CORE.c compiles on `/usr/bin/perl rakudo-j-build`, one at a time, nothing else running.
- **Tests:** JUnit `./nqp/gradlew -p nqp :nqp-runtime:test --tests '<pattern>'`; the nqp `t/jvm` files `raku -e 'exit run(<prove --exec ./nqp-j-gradle t/jvm/23-sc-demand.t>, :cwd("nqp")).exitcode'`; the nqp suite `raku tools/build/watched-run.raku --log=$T/<name>.log --show='Files=' --show='Result' --show='FAIL' --stall=900 -- raku tools/build/evalserver-sweep.raku --suite=nqp --chunk='*'` (expect `Result: PASS`, `Files=155`, about 200 s warm; record prove and whole walls); warm sanity `raku tools/build/watched-run.raku --log=$T/<name>.log --show='files in' --show='FAIL' --stall=600 -- raku tools/build/evalserver-sweep.raku --chunk='*' --jobs=1 --heap=8 t/01-sanity` (expect 25 files, 0 FAIL).
- **Commit stamps:** every commit gets an evening stamp on the day it is made, monotonic within the tree, between 18:00 and 23:00 local (`GIT_AUTHOR_DATE='2026-09-18 18:10:00 +0200' GIT_COMMITTER_DATE=<same>`), and ends with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. Subjects carry `(milestone 8, Phase C)`.
- **`java` is Oracle GraalVM 25.2.4** (`java -version` shows `Oracle GraalVM 25.2.4+7.1`); anything else voids every number.
- **Format limits are errors, not silent truncation:** the writer throws past 4095 dependencies or 2^20 STables in an object row.

## File structure

New:
- `tools/build/sc-blob-sizes.raku` -- the segment table of a jar's `unit.serialized` (versions 11 and 12). Task 1.
- `docs/superpowers/plans/2026-09-18-jvm-milestone-8-phase-c.ledger.md` -- the rows, gates, rulings. Task 1, then every task.
- `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/Varint.kt` -- the LEB128 codec (unsigned and zigzag) on a `ByteBuffer`. Task 2.
- `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/sixmodel/VarintTest.kt`. Task 2.
- `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/RootSet.kt` -- one growable, release/acquire root set used three times by the context. Task 3.
- `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/Drain.kt` -- the worklist of one outermost demand, across readers. Task 6.
- `nqp/t/jvm/23-sc-demand.t` -- format round trips (Task 4) and the demand counts (Task 7).

Modified:
- `sixmodel/SerializationContext.kt` -- root sets on `RootSet`, index fields instead of maps (Task 3); the barrier and `reader` (Task 6).
- `sixmodel/SixModelObject.kt`, `sixmodel/STable.kt`, `runtime/CodeRef.kt` -- `scIdx` / `scCodeIdx` (Task 3); `HOW`/`WHO` properties (Task 7).
- `sixmodel/SerializationWriter.kt` -- version 12 (Task 4).
- `sixmodel/SerializationReader.kt` -- version 12, dual (Task 4); version 11 removed (Task 5); the demand road (Task 6); lazy HOW/WHO, verify, the exit line (Task 7).
- `sixmodel/reprs/RakuObjectREPR.kt` -- `deserialize_stub` without `peekAttributeShape`, `forceSTable` call removed (Task 6).
- `dispatch/DispatchSlotCodec.kt` -- index lookups on the fields (Task 3).
- `runtime/Ops.kt` -- `deserialize` installs the reader on the SC and passes the stats through (Task 6).
- `runtime/unit/UnitLoadStats.kt` -- the exit hook that prints `sc-demand` lines (Task 7).
- `tools/build/m7-rig.raku`, `tools/build/unit-load-exclusive.raku` (Task 7).
- The spec (Task 1: one wording fix), the ledger (every task), `docs/jvm-unit-lazy-loading.md`, `docs/jvm-perf-findings-2026-09.md`, `docs/jvm-truffle-only-plan.md`, memory (Task 8).

---

### Task 1: The blob tool, the ledger, row c0

**Files:**
- Create: `tools/build/sc-blob-sizes.raku`
- Create: `docs/superpowers/plans/2026-09-18-jvm-milestone-8-phase-c.ledger.md`
- Modify: `docs/superpowers/specs/2026-09-18-jvm-milestone-8-phase-c-sc-demand-design.md` (Section 2, "Lazy HOW and WHO": the sentence "the one Java caller uses the getter" is wrong -- every reader of `st.HOW`/`st.WHO` outside the serializer is Kotlin, 11 files; replace with "all 29 call sites are Kotlin and keep their syntax")

**Interfaces:**
- Produces: `raku tools/build/sc-blob-sizes.raku <jar>` prints `version=<v> len=<bytes>`, one `<segment> <bytes> <share %>` line per segment, and `counts: stables=.. objects=.. closures=.. contexts=.. repos=.. strings=.. deps=..`; Tasks 5 and 8 paste its output into the ledger.

- [ ] **Step 1: Write the tool**

```raku
#!/usr/bin/env raku
# The segment table of a unit's serialized SC, from the header of
# unit.serialized inside a unit jar (milestone 8, Phase C, C0). Versions
# 11 (fixed rows, length-prefixed strings) and 12 (Phase C's: eight-byte
# object rows, a string offset table before the string data).
#
#     raku tools/build/sc-blob-sizes.raku blib/CORE.c.setting.jar
#
# Reads the entry with `unzip -p` (the jar is Stored, so this is a copy,
# not an inflate). Percentages are of the whole entry.
sub MAIN(Str $jar) {
    my $p = run 'unzip', '-p', $jar, 'unit.serialized', :out, :bin;
    my $b = $p.out.slurp(:close, :bin);
    die "$jar: no unit.serialized entry (or unzip failed)" unless $b.elems >= 4 * 18;
    my @h = (0..17).map({ $b.read-uint32($_ * 4, LittleEndian) });
    my ($v, $depO, $depN, $stO, $stN, $stD, $objO, $objN, $objD, $cloO, $cloN,
        $ctxO, $ctxN, $ctxD, $repO, $repN, $shO, $shN) = @h;
    die "$jar: serialization version $v; this tool reads 11 and 12" unless $v == 11 | 12;
    my $len = $b.elems;
    my $objRow = $v == 11 ?? 16 !! 8;
    my @rows =
        deps      => $depN * 8,
        stTable   => $stN * 12,
        stData    => $objO - $stD,
        objTable  => $objN * $objRow,
        objData   => $cloO - $objD,
        closures  => $cloN * 24,
        ctxTable  => $ctxN * 16,
        ctxData   => $repO - $ctxD,
        repos     => $repN * 16,
        strOffsets => ($v == 12 ?? ($shN + 1) * 4 !! 0),
        strings   => $len - $shO - ($v == 12 ?? ($shN + 1) * 4 !! 0);
    say "version=$v len=$len";
    for @rows -> $r {
        printf "%-10s %10d  %5.1f %%\n", $r.key, $r.value, 100 * $r.value / $len;
    }
    say "counts: stables=$stN objects=$objN closures=$cloN contexts=$ctxN repos=$repN strings=$shN deps=$depN";
}
```

- [ ] **Step 2: Run it on CORE.c and on BOOTSTRAP**

Run: `raku tools/build/sc-blob-sizes.raku blib/CORE.c.setting.jar` and `raku tools/build/sc-blob-sizes.raku blib/Perl6/BOOTSTRAP/v6c.jar` (if that path is not the BOOTSTRAP jar, `find blib -name 'v6c.jar'`).
Expected for CORE.c: `version=11 len=28167619`, `objData 14610612 51.9 %`, `objTable 4418512 15.7 %`, `stData 4842170 17.2 %`, `strings 3723901 13.2 %`, `counts: stables=5558 objects=276157 closures=11800 contexts=2575 repos=310 strings=13407 deps=11` (the C0-lite numbers in the spec). Keep both outputs for the ledger.

- [ ] **Step 3: Row c0, the rig**

Nothing else running. Run:
```
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/a46e5ea6/tmp/rig-c0.log --show='m7-rig:' --stall=900 -- raku tools/build/m7-rig.raku --tag=c0 --out=m7-rig
```
Expected: `m7-rig: DONE`; the row line (cold rakudo-e best-of-5 near 2.2 s, cold nqp-e near 1.2 s, misses near 4933, the warm proxy 25 files with 0 new red). Record the row line and the rig's wall.

- [ ] **Step 4: Create the ledger**

```markdown
# Milestone 8, Phase C: SC demand deserialization -- ledger

Spec: docs/superpowers/specs/2026-09-18-jvm-milestone-8-phase-c-sc-demand-design.md
Plan: docs/superpowers/plans/2026-09-18-jvm-milestone-8-phase-c-sc-demand.md

## C0: the baseline (Task 1)

Tree: rakudo 2338bc426c / nqp 62fa7ea9f (row b2b's tree, Phase B parked there).

| row | rakudo | nqp | cold rakudo-e | cold nqp-e | misses | hits | warm proxy | notes |
|---|---|---|---|---|---|---|---|---|
| c0 | 2338bc426c | 62fa7ea9f | <s> | <s> | <n> | <n> | <s>/sanity | rig wall <s> |

Blob (tools/build/sc-blob-sizes.raku), CORE.c: <paste>. BOOTSTRAP: <paste>.

C0-lite (single runs, 2026-09-17, spec "Baselines"): SC read 304 ms of 1382 ms exclusive load; CORE.c's SC 192 ms; setcodeobj 27116 calls per cold run.
```
Fill every `<...>` from Steps 2-3 before committing.

- [ ] **Step 5: Fix the spec sentence, commit (rakudo tree)**

```bash
git add tools/build/sc-blob-sizes.raku docs/superpowers/plans/2026-09-18-jvm-milestone-8-phase-c.ledger.md docs/superpowers/plans/2026-09-18-jvm-milestone-8-phase-c-sc-demand.md docs/superpowers/specs/2026-09-18-jvm-milestone-8-phase-c-sc-demand-design.md
GIT_AUTHOR_DATE='2026-09-18 18:10:00 +0200' GIT_COMMITTER_DATE='2026-09-18 18:10:00 +0200' git commit -m "Tools + docs: sc-blob-sizes, the Phase C plan and ledger, row c0 (milestone 8, Phase C)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: The varint codec

**Files:**
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/Varint.kt`
- Test: `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/sixmodel/VarintTest.kt`

**Interfaces:**
- Produces: `object Varint { const val MAX_BYTES = 10; fun writeUnsigned(b: ByteBuffer, v: Long); fun readUnsigned(b: ByteBuffer): Long; fun writeSigned(b: ByteBuffer, v: Long); fun readSigned(b: ByteBuffer): Long; fun writeUnsigned(b, v: Int) / readUnsignedInt(b): Int }`. Unsigned = LEB128, seven bits per byte, low group first, high bit = continue. Signed = zigzag (`(v shl 1) xor (v shr 63)`) then unsigned. `readUnsigned` throws `RuntimeException("varint longer than 10 bytes")` past the tenth byte (a corruption check, like the header's).

- [ ] **Step 1: Write the failing test**

```kotlin
package org.raku.nqp.sixmodel

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class VarintTest {
    private fun buf() = ByteBuffer.allocate(64).order(ByteOrder.LITTLE_ENDIAN)

    private fun unsignedRoundTrip(v: Long, bytes: Int) {
        val b = buf()
        Varint.writeUnsigned(b, v)
        assertEquals(bytes, b.position(), "size of $v")
        b.flip()
        assertEquals(v, Varint.readUnsigned(b), "value $v")
        assertEquals(bytes, b.position(), "consumed for $v")
    }

    private fun signedRoundTrip(v: Long, bytes: Int) {
        val b = buf()
        Varint.writeSigned(b, v)
        assertEquals(bytes, b.position(), "size of $v")
        b.flip()
        assertEquals(v, Varint.readSigned(b), "value $v")
    }

    @Test fun `unsigned edges`() {
        unsignedRoundTrip(0L, 1)
        unsignedRoundTrip(127L, 1)
        unsignedRoundTrip(128L, 2)
        unsignedRoundTrip(16383L, 2)
        unsignedRoundTrip(16384L, 3)
        unsignedRoundTrip((276157L shl 1) or 1L, 3)   // CORE.c's largest packed own-SC object reference
        unsignedRoundTrip(1L shl 32, 5)
        unsignedRoundTrip(Long.MAX_VALUE, 9)
        unsignedRoundTrip(-1L, 10)                    // all 64 bits set
    }

    @Test fun `signed edges`() {
        signedRoundTrip(0L, 1)
        signedRoundTrip(-1L, 1)
        signedRoundTrip(63L, 1)
        signedRoundTrip(-64L, 1)
        signedRoundTrip(64L, 2)
        signedRoundTrip(-65L, 2)
        signedRoundTrip(Long.MAX_VALUE, 10)
        signedRoundTrip(Long.MIN_VALUE, 10)
    }

    @Test fun `int form`() {
        val b = buf()
        Varint.writeUnsigned(b, 300)
        b.flip()
        assertEquals(300, Varint.readUnsignedInt(b))
    }

    @Test fun `an eleven byte run is corruption`() {
        val b = buf()
        repeat(11) { b.put(0x80.toByte()) }
        b.flip()
        assertFailsWith<RuntimeException> { Varint.readUnsigned(b) }
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.sixmodel.VarintTest'`
Expected: compilation FAILS with `Unresolved reference: Varint`.

- [ ] **Step 3: Write the codec**

```kotlin
package org.raku.nqp.sixmodel

import java.nio.ByteBuffer

/**
 * LEB128 on a ByteBuffer, for serialization format 12 (milestone 8,
 * Phase C): indexes, counts and offsets unsigned; `writeInt`'s longs
 * zigzag-signed so small negatives stay one byte. Ten bytes hold 64
 * bits; an eleventh continuation byte is corruption.
 */
object Varint {
    const val MAX_BYTES = 10

    @JvmStatic
    fun writeUnsigned(b: ByteBuffer, v: Long) {
        var x = v
        while ((x and 0x7FL.inv()) != 0L) {
            b.put(((x and 0x7FL) or 0x80L).toByte())
            x = x ushr 7
        }
        b.put(x.toByte())
    }

    @JvmStatic
    fun writeUnsigned(b: ByteBuffer, v: Int) = writeUnsigned(b, v.toLong() and 0xFFFFFFFFL)

    @JvmStatic
    fun readUnsigned(b: ByteBuffer): Long {
        var result = 0L
        var shift = 0
        while (true) {
            val byte = b.get().toInt()
            result = result or ((byte and 0x7F).toLong() shl shift)
            if ((byte and 0x80) == 0) return result
            shift += 7
            if (shift >= 7 * MAX_BYTES) throw RuntimeException("varint longer than $MAX_BYTES bytes")
        }
    }

    @JvmStatic
    fun readUnsignedInt(b: ByteBuffer): Int {
        val v = readUnsigned(b)
        if (v < 0 || v > 0xFFFFFFFFL) throw RuntimeException("varint does not fit 32 bits: $v")
        return v.toInt()
    }

    @JvmStatic
    fun writeSigned(b: ByteBuffer, v: Long) = writeUnsigned(b, (v shl 1) xor (v shr 63))

    @JvmStatic
    fun readSigned(b: ByteBuffer): Long {
        val u = readUnsigned(b)
        return (u ushr 1) xor -(u and 1L)
    }
}
```

- [ ] **Step 4: Run the test to see it pass**

Run: `./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.sixmodel.VarintTest'`
Expected: BUILD SUCCESSFUL, 4 tests passed.

- [ ] **Step 5: Commit (nqp tree)**

```bash
git -C nqp add src/vm/jvm/runtime/org/raku/nqp/sixmodel/Varint.kt nqp-runtime/src/test/kotlin/org/raku/nqp/sixmodel/VarintTest.kt
GIT_AUTHOR_DATE='2026-09-18 18:20:00 +0200' GIT_COMMITTER_DATE='2026-09-18 18:20:00 +0200' git -C nqp commit -m "Serialization: the varint codec for format 12 (milestone 8, Phase C)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: The root index on the object; RootSet

The context's three `Object2IntOpenHashMap` caches and the reader's `stableIndex` map are replaced by an index field on the thing itself, and the three root lists by one `RootSet` whose reads are acquire and writes release (Task 6's barrier rests on that). No wire change; runtime-only.

**Files:**
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/RootSet.kt`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/SixModelObject.kt:37` (after `sc`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/STable.kt:81` (after `sc`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CodeRef.kt:31` (after `isStaticCodeRef`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationContext.kt` (whole storage section)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationReader.kt:62-63, 379-381, 443-450, 467-469` (`stableIndex`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlotCodec.kt:48-58, 75-79`
- Test: `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/SerializationContextTest.kt`

**Interfaces:**
- Produces: `class RootSet<T : Any>(capacity: Int) { val size: Int; fun get(i: Int): T?; fun set(i: Int, v: T?); fun add(v: T?): Int; fun init(n: Int); fun ensureCapacity(n: Int); fun clear() }` -- `get` is an acquire read, `set` a release write, `add` appends (grows by doubling) and returns the index, `init(n)` makes `size == n` with every slot null (the reader's presize), `clear()` drops to size 0.
- Produces: `SixModelObject.scIdx: Int` (-1 = in no root set), `STable.scIdx: Int`, `CodeRef.scCodeIdx: Int`, all `@JvmField var`.
- Produces on `SerializationContext`: `getObjectIndex(obj): Int` / `getSTableIndex(st): Int` / `getCodeIndex(cr): Int` now return -1 for a thing not in this root set (they threw or answered 0 before); `addObject/addSTable/addCodeRef` set the index field; `disclaim*` reset it to -1. The getters `getObject/getSTable/getCodeRef`, the counts and `init*List` keep their signatures.

- [ ] **Step 1: Write the failing tests** (append to `SerializationContextTest`)

```kotlin
    @Test
    fun `addObject stamps the index on the object and the index reads back`() {
        val sc = SerializationContext("test-sc-idx")
        val a = org.raku.nqp.sixmodel.TypeObject()
        val b = org.raku.nqp.sixmodel.TypeObject()
        assertEquals(-1, a.scIdx)
        sc.addObject(a)
        sc.addObject(b)
        assertEquals(0, a.scIdx)
        assertEquals(1, b.scIdx)
        assertEquals(1, sc.getObjectIndex(b))
        assertSame(b, sc.getObject(1))
    }

    @Test
    fun `a foreign object answers -1, not 0`() {
        val sc = SerializationContext("test-sc-foreign")
        val other = SerializationContext("test-sc-other")
        val a = org.raku.nqp.sixmodel.TypeObject()
        other.addObject(a)
        assertEquals(-1, sc.getObjectIndex(a))
        assertEquals(-1, sc.getSTableIndex(null))
    }

    @Test
    fun `initObjectList presizes with nulls and addObject at an index fills a slot`() {
        val sc = SerializationContext("test-sc-init")
        sc.initObjectList(3)
        assertEquals(3, sc.objectCount())
        assertEquals(null, sc.getObject(2))
        val a = org.raku.nqp.sixmodel.TypeObject()
        sc.addObject(a, 2)
        assertEquals(2, a.scIdx)
        assertSame(a, sc.getObject(2))
        sc.disclaimObjects()
        assertEquals(-1, a.scIdx)
        assertEquals(0, sc.objectCount())
    }
```
`TypeObject` has a no-argument constructor (the reader's `stubObjects` uses it).

- [ ] **Step 2: Run them to see them fail**

Run: `./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.runtime.SerializationContextTest'`
Expected: compilation FAILS on `scIdx`.

- [ ] **Step 3: The fields**

`SixModelObject.kt`, right after the `sc` field:
```kotlin
    /** This object's index in [sc]'s object root set; -1 while in none
     *  (MoarVM's idx_in_sc). Set by SerializationContext.addObject, reset
     *  by disclaim; it replaces the context's object-to-index map. */
    @JvmField var scIdx: Int = -1
```
`STable.kt`, right after `sc`:
```kotlin
    /** This STable's index in [sc]'s STable root set; -1 while in none. */
    @JvmField var scIdx: Int = -1
```
`CodeRef.kt`, right after `isStaticCodeRef`:
```kotlin
    /** This code ref's index in [sc]'s code root set; -1 while in none. A
     *  code ref can sit in the object root set too (scIdx), so this is
     *  its own field. */
    @JvmField var scCodeIdx: Int = -1
```

- [ ] **Step 4: RootSet**

```kotlin
package org.raku.nqp.sixmodel

import java.util.concurrent.atomic.AtomicReferenceArray

/**
 * One root set of a SerializationContext: a growable array whose reads
 * are acquire and whose writes are release, so an entry a demand drain
 * publishes (milestone 8, Phase C) is whole to every thread that reads
 * the slot non-null. A compile's SC grows one by one through [add]; a
 * deserialized SC is presized by [init] and filled by [set].
 */
class RootSet<T : Any>(capacity: Int = 16) {
    private var slots = AtomicReferenceArray<T?>(maxOf(capacity, 1))
    var size: Int = 0
        private set

    fun get(i: Int): T? {
        if (i < 0 || i >= size) throw IndexOutOfBoundsException("root index $i of $size")
        return slots.get(i)
    }

    fun set(i: Int, v: T?) {
        if (i < 0 || i >= size) throw IndexOutOfBoundsException("root index $i of $size")
        slots.lazySet(i, v)
    }

    fun add(v: T?): Int {
        ensureCapacity(size + 1)
        val i = size
        slots.lazySet(i, v)
        size = i + 1
        return i
    }

    /** size becomes [n], every slot null; the reader's presize. */
    fun init(n: Int) {
        ensureCapacity(n)
        for (i in 0 until n) slots.lazySet(i, null)
        size = n
    }

    fun ensureCapacity(n: Int) {
        if (n <= slots.length()) return
        val grown = AtomicReferenceArray<T?>(maxOf(n, slots.length() * 2))
        for (i in 0 until size) grown.lazySet(i, slots.get(i))
        slots = grown
    }

    fun clear() {
        slots = AtomicReferenceArray(16)
        size = 0
    }
}
```

- [ ] **Step 5: The context on RootSet and the fields**

Replace `SerializationContext.kt` from `/* The root set of objects` through the end of the class with:
```kotlin
    /* The three root sets. */
    private val objects = RootSet<SixModelObject>()
    private val stables = RootSet<STable>()
    private val codes = RootSet<CodeRef>()

    /* Repossession info. The following lists have matching indexes, each
     * representing the integer of an object in our root set along with the SC
     * that the object was originally from. */
    @JvmField var repIndexes = IntArrayList()
    @JvmField var repScs = ArrayList<SerializationContext>()

    /* Some things we deserialize are not directly in an SC, root set, but
     * rather are owned by others. This is mostly thanks to Parrot legacy,
     * where not everything was a 6model object. This maps such owned
     * objects to their owner. It is used to determine what object should
     * be repossessed in the case a write barrier is hit. */
    @JvmField var ownedObjects = HashMap<SixModelObject, SixModelObject>()

    /* Takes an object and adds it to this SC's root set, and installs a
     * reposession entry. The caller (Ops.scwbObject) moves obj.sc to this
     * SC afterwards; the index field already points at the new slot. */
    fun repossessObject(origSC: SerializationContext, obj: SixModelObject) {
        /* Check the object really lives in the SC root set. */
        if (obj.sc!!.getObjectIndex(obj) < 0)
            throw RuntimeException("Attempt to repossess object not in this context")

        /* Add to root set. */
        val newSlot = addObject(obj)

        /* Add repossession entry. */
        repIndexes.add(newSlot shl 1)
        repScs.add(origSC)
    }

    /* Takes an STable and adds it to this SC's root set, and installs a
     * reposession entry. */
    fun repossessSTable(origSC: SerializationContext, st: STable) {
        val newSlot = addSTable(st)
        repIndexes.add((newSlot shl 1) or 1)
        repScs.add(origSC)
    }

    /* Objects. The index lives on the object (scIdx); a lookup validates it
     * by reading the slot back, so a stale field answers -1, never a wrong
     * index. */
    fun addObject(obj: SixModelObject?): Int {
        val i = objects.add(obj)
        obj?.scIdx = i
        return i
    }

    fun addObject(obj: SixModelObject?, index: Int) {
        if (index == objects.size) objects.add(obj) else objects.set(index, obj)
        obj?.scIdx = index
    }

    fun getObjectIndex(obj: SixModelObject?): Int {
        val i = obj?.scIdx ?: return -1
        return if (i >= 0 && i < objects.size && objects.get(i) === obj) i else -1
    }

    fun getObject(index: Int): SixModelObject? = objects.get(index)
    fun objectCount(): Int = objects.size
    fun initObjectList(entries: Int) = objects.init(entries)

    /* STables. */
    fun addSTable(stable: STable?): Int {
        val i = stables.add(stable)
        stable?.scIdx = i
        return i
    }

    fun setSTable(index: Int, stable: STable?) {
        stables.set(index, stable)
        stable?.scIdx = index
    }

    fun getSTableIndex(stable: STable?): Int {
        val i = stable?.scIdx ?: return -1
        return if (i >= 0 && i < stables.size && stables.get(i) === stable) i else -1
    }

    fun getSTable(index: Int): STable? = stables.get(index)
    fun stableCount(): Int = stables.size
    fun initSTableList(entries: Int) = stables.init(entries)

    /* Code refs. */
    fun initCodeRefList(entries: Int) = codes.ensureCapacity(entries)

    fun addCodeRef(coderef: CodeRef?): Int {
        val i = codes.add(coderef)
        coderef?.scCodeIdx = i
        return i
    }

    fun addCodeRef(obj: CodeRef?, index: Int) {
        if (index == codes.size) codes.add(obj) else codes.set(index, obj)
        obj?.scCodeIdx = index
    }

    fun getCodeIndex(coderef: SixModelObject?): Int {
        val cr = coderef as? CodeRef ?: return -1
        val i = cr.scCodeIdx
        return if (i >= 0 && i < codes.size && codes.get(i) === cr) i else -1
    }

    fun getCodeRef(index: Int): CodeRef? = codes.get(index)
    fun coderefCount(): Int = codes.size

    fun disclaimObjects() {
        for (i in 0 until objects.size) objects.get(i)?.let { it.sc = null; it.scIdx = -1 }
        objects.clear()
    }

    fun disclaimSTables() {
        for (i in 0 until stables.size) stables.get(i)?.let { it.sc = null; it.scIdx = -1 }
        stables.clear()
    }

    fun disclaimCodes() {
        for (i in 0 until codes.size) codes.get(i)?.let { it.sc = null; it.scCodeIdx = -1 }
        codes.clear()
    }
}
```
Remove the now-unused `Object2IntOpenHashMap` import (keep `IntArrayList`). `addObject`/`addSTable`/`addCodeRef` now return `Int`; every existing caller ignores the result, which Kotlin allows.

- [ ] **Step 6: The reader's `stableIndex` map goes**

In `SerializationReader.kt`: delete the `stableIndex` field (line 63) and its `IdentityHashMap` construction at the end of `checkAndDisectInput`; in `stubSTables` delete the loop that filled it (keep `stableState = IntArray(stTableEntries)`); in `forceSTable` replace `val idx = stableIndex[st] ?: return` with
```kotlin
        if (st.sc !== sc) return
        val idx = st.scIdx
        if (idx < 0) return
```
and in `peekAttributeShape` replace `val idx = stableIndex[st] ?: return null` with
```kotlin
        if (st.sc !== sc) return null
        val idx = st.scIdx
        if (idx < 0) return null
```
(`sc.setSTable(i, st)` in `stubSTables` already stamps `scIdx`.)

- [ ] **Step 7: The codec's lookups**

In `DispatchSlotCodec.kt` replace `objectIndex`, `codeIndex` and the STable lookup in `ref(st)` with the plain calls, since the context validates now:
```kotlin
    private fun objectIndex(sc: SerializationContext, obj: SixModelObject): Int = sc.getObjectIndex(obj)
    private fun codeIndex(sc: SerializationContext, obj: SixModelObject): Int = sc.getCodeIndex(obj)
```
and in `ref(st: STable?, ...)`: `val i = sc.getSTableIndex(st)` followed by the existing `if (i >= 0 && ...) return stamped(...)`. Update the comment above them: "The context validates an index by reading the slot back; -1 means not in the root set."

- [ ] **Step 8: Run the JUnit suite, rebuild, run the nqp suite**

Run: `./nqp/gradlew -p nqp :nqp-runtime:test` -- expected all green (the count was 69 at B2; VarintTest adds 4, this task 3).
Then the runtime rebuild and retrain (Global Constraints), then the nqp suite through the sweep (`$T/nqp-suite-task3.log`). Expected `Result: PASS Files=155`; record prove and whole walls.

- [ ] **Step 9: Commit (nqp tree)**

```bash
git -C nqp add src/vm/jvm/runtime/org/raku/nqp/sixmodel/RootSet.kt src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationContext.kt src/vm/jvm/runtime/org/raku/nqp/sixmodel/SixModelObject.kt src/vm/jvm/runtime/org/raku/nqp/sixmodel/STable.kt src/vm/jvm/runtime/org/raku/nqp/runtime/CodeRef.kt src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationReader.kt src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlotCodec.kt nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/SerializationContextTest.kt
GIT_AUTHOR_DATE='2026-09-18 18:40:00 +0200' GIT_COMMITTER_DATE='2026-09-18 18:40:00 +0200' git -C nqp commit -m "Serialization: the root index lives on the object; RootSet with release/acquire slots (milestone 8, Phase C)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```
Then a ledger line under a new `## Tasks 2-3` heading in the rakudo tree: the JUnit count and wall, the nqp suite walls; commit the ledger (`Docs: Phase C ledger -- tasks 2-3 (milestone 8, Phase C)`, stamp 18:45).

---

### Task 4: Format version 12 -- the writer, the dual reader, lazy strings

The wire changes: one-byte tags, packed varint references, zigzag varint ints, varint string indexes, a string offset table, an eight-byte object row. The reader reads 11 and 12 (Task 5 deletes 11). Strings decode on first lookup from this task on. Runtime-only until Task 5 builds with it.

**Files:**
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationWriter.kt` (constants 29-47; `addStringToHeap` 108-131; `writeInt`/`writeInt32`/`writeStr` 168-191; `writeObjRef` 193-205; `writeList`/`writeHash`/`writeIntHash` 207-236; `writeCodeRef` 238-246; `writeRef` 275-346; `writeSTableRef` 347-354; `concatenateOutputs` 355-475; `serializeObject` 476-496)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationReader.kt` (constants 21-58; `checkAndDisectInput` 173-280; `deserializeStringHeap` 282-296; `repossess` 316-360; `stubObjects` 383-410; `deserializeClosures` 412-430; `deserializeObjects` 627-643; `deserializeContexts` 645-700; `readRef`..`lookupString` 728-864; the `version >= 5/6/9` branches in `deserializeSTableInner` 510-626)
- Test: `nqp/t/jvm/23-sc-demand.t` (new; part A)

**Interfaces:**
- Consumes: `Varint` (Task 2); `SerializationContext.getObjectIndex/getSTableIndex/getCodeIndex` returning -1 for absent (Task 3).
- Produces: format version 12 as laid out below; reader helpers `readPackedRef(): Long` (`(scIdx shl 32) or idx`), `rowRef(): Long` (two raw ints, for fixed-width table rows), `objRowSize`, `lookupString` lazy. Task 6 keeps all of them.

**The version-12 layout** (little-endian; header unchanged: 18 ints, `stringHeapOffset` now points at the offset table):
- object reference, STable reference, code reference: varint `(idx << 1)` for the current SC; varint `(idx << 1) | 1` then varint `scId` (1-based dependency index) otherwise;
- `writeRef`: one tag byte (the `REFVAR_*` values 1..12 unchanged), then per tag: NULL/VM_NULL nothing; OBJECT a packed reference; VM_INT zigzag varint; VM_NUM 8-byte double; VM_STR varint heap index; VM_ARR_VAR varint count then refs; VM_ARR_STR varint count then varint heap indexes; VM_ARR_INT varint count then zigzag varints; VM_HASH_STR_VAR varint count then (varint key index, ref) pairs; STATIC_CODEREF/CLONED_CODEREF a packed reference;
- `writeInt` zigzag varint; `writeInt32` zigzag varint; `writeNum` 8 bytes; `writeStr` varint heap index;
- STable row 12 bytes as before (REPR-name index, data offset, REPR-data offset -- the third int serves `peekAttributeShape` until Task 6 deletes it; 22 KB, kept; ledger ruling);
- object row 8 bytes: `(stableIdx << 12) | stableScId`, then `dataOffset` with bit 31 set for a type object;
- closure row 24, context row 16, repossession row 16, dependency row 8: unchanged, raw ints;
- string heap: `entries + 1` uint32 offsets (offsets[0] = 0, offsets[entries] = total bytes) then the UTF-8 bytes back to back; index 0 is the null string and has no offset entry; string `i` (1-based) is bytes `offsets[i-1] until offsets[i]`.

- [ ] **Step 1: Write the failing test** -- `nqp/t/jvm/23-sc-demand.t`, part A

```nqp
# Milestone 8 Phase C: serialization format 12 and the demand reader.
# Part A (Task 4): round trips of the varint and packed-reference wire --
# integer edges, strings, own-SC and dependency references -- through
# nqp::serialize / nqp::deserialize on fresh SCs. Part B (Task 7) reads a
# child's sc-demand exit lines. The child-process helper is the one of
# t/jvm/20-op-census.t; prove must run from the nqp tree.

plan(24);

my $n := -1;
sub fresh-sc($tag) { $n := $n + 1; nqp::createsc('SC_DEMAND_' ~ $n ~ '_' ~ $tag) }
sub add-to-sc($sc, $idx, $obj) { nqp::scsetobj($sc, $idx, $obj); nqp::setobjsc($obj, $sc) }
sub round-trip($sc) {
    my $sh := nqp::list_s();
    my $blob := nqp::serialize($sc, $sh);
    my $out := fresh-sc('OUT');
    nqp::deserialize($blob, $out, $sh, nqp::list(), nqp::null());
    $out
}

# Integer edges through a VMArray of ints (VM_ARR_INT: varint count, zigzag elements).
{
    my $sc := fresh-sc('IN');
    my $big := nqp::bitshiftl_i(1, 62);
    my @edges := nqp::list_i(0, 1, -1, 63, -64, 64, -65, 127, 128, 16383, 16384,
        $big, nqp::sub_i(nqp::add_i($big, $big), 1), nqp::neg_i(nqp::add_i($big, $big)));
    my $holder := nqp::hash('ints', @edges);
    add-to-sc($sc, 0, $holder);
    my $out := round-trip($sc);
    my @back := nqp::atkey(nqp::scgetobj($out, 0), 'ints');
    is(nqp::elems(@back), nqp::elems(@edges), 'the int list keeps its length');
    my $i := 0;
    my $same := 1;
    while $i < nqp::elems(@edges) { $same := 0 unless nqp::atpos_i(@back, $i) == nqp::atpos_i(@edges, $i); $i++ }
    ok($same, 'every integer edge survives the zigzag varint (0, +-1, +-64/65, 127/128, 16383/16384, 2^62, max, min)');
    is(nqp::atpos_i(@back, 12), nqp::sub_i(nqp::add_i($big, $big), 1), 'Long.MAX_VALUE');
    is(nqp::atpos_i(@back, 13), nqp::neg_i(nqp::add_i($big, $big)), 'Long.MIN_VALUE');
}

# Strings: empty, ASCII, non-ASCII, long; a hash keyed by them (VM_HASH_STR_VAR).
{
    my $sc := fresh-sc('IN');
    my $long := nqp::x('abcdefghij', 30);
    my @strs := nqp::list_s('', 'abc', 'ünïcödé ☃', $long);
    my %h := nqp::hash('', 'empty key', 'ünïcödé ☃', 'unicode key', $long, 'long key');
    add-to-sc($sc, 0, nqp::hash('strs', @strs, 'h', %h));
    my $out := round-trip($sc);
    my $o := nqp::scgetobj($out, 0);
    my @back := nqp::atkey($o, 'strs');
    is(nqp::atpos_s(@back, 0), '', 'the empty string');
    is(nqp::atpos_s(@back, 1), 'abc', 'an ASCII string');
    is(nqp::atpos_s(@back, 2), 'ünïcödé ☃', 'a non-ASCII string');
    is(nqp::atpos_s(@back, 3), $long, 'a 300-char string');
    my %hb := nqp::atkey($o, 'h');
    is(nqp::atkey(%hb, ''), 'empty key', 'the empty string as a hash key');
    is(nqp::atkey(%hb, 'ünïcödé ☃'), 'unicode key', 'a non-ASCII hash key');
    is(nqp::atkey(%hb, $long), 'long key', 'a long hash key');
    is(nqp::elems(%hb), 3, 'the hash keeps its size');
}

# Own-SC references (packed, dependency bit 0) between two objects.
class Pair2 { has $!left; has $!right; method left() { $!left } method right() { $!right } }
{
    my $sc := fresh-sc('IN');
    my $a := Pair2.new; my $b := Pair2.new;
    nqp::bindattr($a, Pair2, '$!left', $b);
    nqp::bindattr($a, Pair2, '$!right', $a);
    nqp::bindattr($b, Pair2, '$!left', nqp::null());
    nqp::bindattr($b, Pair2, '$!right', $a);
    add-to-sc($sc, 0, $a);
    add-to-sc($sc, 1, $b);
    my $out := round-trip($sc);
    my $a2 := nqp::scgetobj($out, 0); my $b2 := nqp::scgetobj($out, 1);
    ok(nqp::eqaddr($a2.left, $b2), 'an own-SC reference to the other root object');
    ok(nqp::eqaddr($a2.right, $a2), 'an own-SC self reference (a cycle)');
    ok(nqp::isnull($b2.left), 'a VM null reference');
    ok(nqp::eqaddr($b2.right, $a2), 'the cycle from the other side');
}

# A dependency reference (packed, bit 1 set, then the SC id): the object
# lives in a first SC; a second SC's object points at it.
{
    my $dep := fresh-sc('DEP');
    my $p := Pair2.new;
    add-to-sc($dep, 0, $p);
    my $sc := fresh-sc('IN');
    my $q := Pair2.new;
    nqp::bindattr($q, Pair2, '$!left', $p);
    nqp::bindattr($q, Pair2, '$!right', nqp::null());
    add-to-sc($sc, 0, $q);
    my $out := round-trip($sc);
    my $q2 := nqp::scgetobj($out, 0);
    ok(nqp::eqaddr($q2.left, $p), 'a reference into a dependency SC resolves to the same object');
    ok(nqp::eqaddr(nqp::getobjsc($q2.left), $dep), 'and that object still belongs to its own SC');
}

# Type objects (an object row with bit 31 set: no data) and an STable
# reference (a type's STable reached through a new type in the SC).
{
    my $sc := fresh-sc('IN');
    my $t := nqp::knowhow().new_type(:name('DemandT'), :repr('P6opaque'));
    $t.HOW.compose($t);
    add-to-sc($sc, 0, $t);
    my $out := round-trip($sc);
    my $t2 := nqp::scgetobj($out, 0);
    ok(!nqp::isconcrete($t2), 'a type object round-trips as a type object');
    is($t2.HOW.name($t2), 'DemandT', 'with its HOW (an own-SC object reference from the STable)');
    ok(nqp::eqaddr($t2.WHAT, $t2), 'and its WHAT');
}

# A boxed int, num and str in a list: the HLL's box types (P6int/P6num/
# P6str objects, own-SC references) or the BOOT boxes inline (VM_INT
# zigzag, VM_NUM 8 bytes, VM_STR index), whichever nqp::list produces;
# both roads are on the wire this file tests.
{
    my $sc := fresh-sc('IN');
    add-to-sc($sc, 0, nqp::list(-9000000000, 2.5e0, 'boxed'));
    my $out := round-trip($sc);
    my @l := nqp::scgetobj($out, 0);
    is(nqp::unbox_i(nqp::atpos(@l, 0)), -9000000000, 'a boxed int past 32 bits');
    is(nqp::unbox_n(nqp::atpos(@l, 1)), 2.5e0, 'a boxed num');
    is(nqp::unbox_s(nqp::atpos(@l, 2)), 'boxed', 'a boxed str');
}
```

- [ ] **Step 2: Run it against the current runtime to see the baseline**

Run: `raku -e 'exit run(<prove -v --exec ./nqp-j-gradle t/jvm/23-sc-demand.t>, :cwd("nqp")).exitcode'`
Expected: 24/24 pass on the version-11 code (the wire is the object under test, not the assertions; a failure here is a test bug to fix first). Then proceed: the same file must pass on the version-12 wire.

- [ ] **Step 3: The writer**

Constants: `CURRENT_VERSION = 12`, `OBJECTS_TABLE_ENTRY_SIZE = 8`. Add near the buffers a `private val stringStarts = it.unimi.dsi.fastutil.ints.IntArrayList()`.

`addStringToHeap`: replace the two lines `growToHold(STRINGS, 4 + bytes.size); outputs[STRINGS].putInt(bytes.size)` with
```kotlin
        stringStarts.add(outputs[STRINGS].position())
        growToHold(STRINGS, bytes.size)
```
(the `put(bytes)` stays).

The primitives:
```kotlin
    /* Writing function for native integers (zigzag varint, format 12). */
    fun writeInt(value: Long) {
        growToHold(currentBuffer, Varint.MAX_BYTES)
        Varint.writeSigned(outputs[currentBuffer], value)
    }

    /* Writing function for 32-bit native integers (the same varint; REPR data counts). */
    fun writeInt32(value: Int) {
        growToHold(currentBuffer, Varint.MAX_BYTES)
        Varint.writeSigned(outputs[currentBuffer], value.toLong())
    }

    /* Writing function for native strings: the heap index as a varint. */
    fun writeStr(value: String?) {
        val heapLoc = addStringToHeap(value)
        growToHold(currentBuffer, Varint.MAX_BYTES)
        Varint.writeUnsigned(outputs[currentBuffer], heapLoc)
    }

    /* A packed reference: (idx << 1) for this SC, (idx << 1) | 1 then the
     * dependency's SC id otherwise (format 12; four bytes for CORE.c's
     * largest own index against ten before). */
    private fun writePackedRef(scId: Int, idx: Int) {
        growToHold(currentBuffer, 2 * Varint.MAX_BYTES)
        val out = outputs[currentBuffer]
        if (scId == 0) {
            Varint.writeUnsigned(out, idx.toLong() shl 1)
        } else {
            Varint.writeUnsigned(out, (idx.toLong() shl 1) or 1L)
            Varint.writeUnsigned(out, scId)
        }
    }

    /* Writes an object reference. */
    fun writeObjRef(ref: SixModelObject) {
        if (ref.sc == null) {
            ref.sc = this.sc
            this.sc.addObject(ref)
        }
        val refSC = ref.sc!!
        writePackedRef(getSCId(refSC), refSC.getObjectIndex(ref))
    }

    private fun writeCodeRef(ref: SixModelObject) {
        val codeSC = ref.sc!!
        writePackedRef(getSCId(codeSC), codeSC.getCodeIndex(ref))
    }

    fun writeSTableRef(st: STable) {
        val ref = getSTableRefInfo(st)
        writePackedRef(ref[0], ref[1])
    }

    private fun writeTag(tag: Short) {
        growToHold(currentBuffer, 1)
        outputs[currentBuffer].put(tag.toByte())
    }

    private fun writeCount(n: Int) {
        growToHold(currentBuffer, Varint.MAX_BYTES)
        Varint.writeUnsigned(outputs[currentBuffer], n)
    }
```
(`writeSTableRef`'s old body wrote the two ints of `getSTableRefInfo`; keep its visibility.)

`writeList`, `writeHash`, `writeIntHash`: each `growToHold(currentBuffer, 6); outputs[currentBuffer].putShort(TAG); outputs[currentBuffer].putInt(size)` becomes `writeTag(TAG); writeCount(size)`; in `writeIntHash` the per-entry `growToHold(currentBuffer, 10); putShort(REFVAR_VM_INT); putLong(v)` becomes `writeTag(REFVAR_VM_INT); writeInt(hash.getInt(key).toLong())`.

`writeRef`: `growToHold(currentBuffer, 2); outputs[currentBuffer].putShort(discrim)` becomes `writeTag(discrim)`. In the `when (discrim)` that follows (lines 330-346), every fixed-width write becomes its varint form so that it mirrors the reader's `readRef` in Step 4 exactly: a `putLong(int value)` becomes `writeInt(...)`, a `putInt(heap index)` becomes `writeStr(...)` (or `Varint.writeUnsigned` of an index already in hand), a `putInt(count)` becomes `writeCount(...)`, `putDouble` stays, and an array's/hash's elements go through `writeRef`/`writeStr`/`writeInt` as they do now. Read the reader's `readRef` in Step 4 first and make each branch the inverse.

`serializeObject`:
```kotlin
        val ref = getSTableRefInfo(obj.st)
        if (ref[0] > 0xFFF || ref[1] >= (1 shl 20))
            throw ExceptionHandling.dieInternal(tc,
                "Serialization Error: object row cannot hold STable ${ref[1]} of dependency ${ref[0]} (limits 2^20 STables, 4095 dependencies)")
        growToHold(OBJECTS, OBJECTS_TABLE_ENTRY_SIZE)
        outputs[OBJECTS].putInt((ref[1] shl 12) or ref[0])
        outputs[OBJECTS].putInt(outputs[OBJECT_DATA].position() or (if (obj is TypeObject) Int.MIN_VALUE else 0))
```
(then `currentBuffer = OBJECT_DATA` and the REPR call as before).

`concatenateOutputs`: `outputSize += 4 * (stringStarts.size + 1)` next to the STRINGS size; the strings section at the end becomes
```kotlin
        /* Put the string offset table, then the string data, in place. */
        output.position(64)
        output.putInt(offset)
        output.putInt(stringMap.size)
        output.position(offset)
        for (i in 0 until stringStarts.size) output.putInt(stringStarts.getInt(i))
        output.putInt(outputs[STRINGS].position())
        offset += 4 * (stringStarts.size + 1)
        outputs[STRINGS].flip()
        output.put(outputs[STRINGS])
        offset += outputs[STRINGS].position()
```
`stringStarts.size == stringMap.size` always (one start per heap string); assert it there with the same `RuntimeException("Serialization sanity check failed: ...")` style.

- [ ] **Step 4: The reader, dual**

Constants: `CURRENT_VERSION = 12`, `MIN_VERSION = 11`; delete `V10_HEADER_SIZE`; add `private const val OBJECTS_TABLE_ENTRY_SIZE_V11 = 16` and set `OBJECTS_TABLE_ENTRY_SIZE = 8`. Add fields `private var stringOffsetsPos = 0`, `private var stringDataPos = 0`, and `private val v12: Boolean get() = version >= 12`, `private val objRowSize: Int get() = if (v12) OBJECTS_TABLE_ENTRY_SIZE else OBJECTS_TABLE_ENTRY_SIZE_V11`.

`checkAndDisectInput`: `val headerSize = HEADER_SIZE` (one size now); the objects-table check uses `objTableEntries * objRowSize`; the string-heap block loses its `if (version >= 11)` (always). Delete the `stableIndex` line if Task 3 left anything.

`deserializeStringHeap`:
```kotlin
    private fun deserializeStringHeap() {
        sh = arrayOfNulls(stringHeapEntries + 1)
        sh[0] = null
        if (v12) {
            /* Format 12: an offset table, then the bytes; a string decodes on
             * its first lookup (lookupString). Nothing is read here. */
            stringOffsetsPos = stringHeapOffset
            stringDataPos = stringHeapOffset + 4 * (stringHeapEntries + 1)
            return
        }
        orig.position(stringHeapOffset)
        for (i in 1..stringHeapEntries) {
            val len = orig.getInt()
            val bytes = ByteArray(len)
            orig.get(bytes, 0, len)
            sh[i] = String(bytes, Charsets.UTF_8)
        }
    }

    private fun lookupString(idx: Int): String? {
        if (idx < 0 || idx >= sh.size)
            throw RuntimeException("Attempt to read past end of string heap (index $idx)")
        if (idx == 0) return null
        return sh[idx] ?: decodeString(idx)
    }

    /* Format 12: bytes offsets[idx-1] until offsets[idx] of the string data.
     * Absolute gets, so the caller's position is untouched. String is
     * immutable and safely published; two threads decoding the same index
     * produce equal strings, so the plain array write is benign. */
    private fun decodeString(idx: Int): String {
        val start = orig.getInt(stringOffsetsPos + 4 * (idx - 1))
        val end = orig.getInt(stringOffsetsPos + 4 * idx)
        if (start < 0 || end < start || stringDataPos + end > orig.limit())
            throw RuntimeException("Corruption detected (string $idx offsets $start..$end)")
        val bytes = ByteArray(end - start)
        orig.get(stringDataPos + start, bytes)
        val s = String(bytes, Charsets.UTF_8)
        sh[idx] = s
        return s
    }
```
(`ByteBuffer.get(int, byte[])` is the absolute bulk read, JDK 13+.)

The primitives and references:
```kotlin
    fun readLong(): Long = if (v12) Varint.readSigned(orig) else orig.getLong()
    fun readInt32(): Int = if (v12) Varint.readSigned(orig).toInt() else orig.getInt()
    fun readDouble(): Double = orig.getDouble()
    fun readStr(): String? = lookupString(if (v12) Varint.readUnsignedInt(orig) else orig.getInt())
    private fun readCount(): Int = if (v12) Varint.readUnsignedInt(orig) else orig.getInt()
    private fun readTag(): Short = if (v12) orig.get().toShort() else orig.getShort()

    /* A packed reference (format 12) or the two ints of format 11, as
     * (scIdx shl 32) or idx. */
    private fun readPackedRef(): Long {
        if (!v12) {
            val scIdx = orig.getInt()
            val idx = orig.getInt()
            return (scIdx.toLong() shl 32) or (idx.toLong() and 0xFFFFFFFFL)
        }
        val p = Varint.readUnsigned(orig)
        val idx = p ushr 1
        val scIdx = if ((p and 1L) == 0L) 0 else Varint.readUnsignedInt(orig)
        return (scIdx.toLong() shl 32) or idx
    }

    /* A reference in a fixed-width table row: always two raw ints. */
    private fun rowRef(): Long {
        val scIdx = orig.getInt()
        val idx = orig.getInt()
        return (scIdx.toLong() shl 32) or (idx.toLong() and 0xFFFFFFFFL)
    }

    private fun objRef(r: Long): SixModelObject {
        val objSC = locateSC((r ushr 32).toInt())
        val idx = r.toInt()
        if (idx < 0 || idx >= objSC.objectCount())
            throw RuntimeException("Invalid SC object index $idx")
        return objSC.getObject(idx)!!
    }

    private fun codeRefOf(r: Long): CodeRef {
        val codeSC = locateSC((r ushr 32).toInt())
        val idx = r.toInt()
        if (idx < 0 || idx >= codeSC.coderefCount())
            throw RuntimeException("Invalid SC code index $idx")
        return codeSC.getCodeRef(idx)!!
    }

    fun readObjRef(): SixModelObject = objRef(readPackedRef())
    fun readCodeRef(): CodeRef = codeRefOf(readPackedRef())
    fun readSTableRef(): STable { val r = readPackedRef(); return lookupSTable((r ushr 32).toInt(), r.toInt()) }
```
`readRef`: `val discrim = readTag()`; then `REFVAR_VM_INT`: `iResult.set_int(tc, readLong())`; `REFVAR_VM_STR`: `sResult.set_str(tc, readStr())`; the four container cases: `val elems = readCount()`; `REFVAR_VM_HASH_STR_VAR` keys: `val key = readStr()`; `REFVAR_VM_ARR_INT` elements already `readLong()`, `REFVAR_VM_ARR_STR` already `readStr()`. Everything else in `readRef` unchanged.

Table rows: in `deserializeClosures` the two `readCodeRef()` / `readObjRef()` calls on the row become `codeRefOf(rowRef())` / `objRef(rowRef())`; in `deserializeContexts` `val staticCode = readCodeRef()` becomes `codeRefOf(rowRef())`. In `stubObjects`, `repossess` (the `origObj.st = lookupSTable(...)` line) and `deserializeObjects`, the row reads go through two helpers:
```kotlin
    /* The STable of object row i. */
    private fun objRowSTable(i: Int): STable {
        orig.position(objTableOffset + i * objRowSize)
        if (!v12) return lookupSTable(orig.getInt(), orig.getInt())
        val packed = orig.getInt()
        return lookupSTable(packed and 0xFFF, packed ushr 12)
    }

    /* Object row i's data offset, or -1 for a type object. */
    private fun objRowDataOffset(i: Int): Int {
        if (!v12) {
            orig.position(objTableOffset + i * objRowSize + 12)
            val flags = orig.getInt()
            if (flags == 0) return -1
            orig.position(objTableOffset + i * objRowSize + 8)
            return orig.getInt()
        }
        orig.position(objTableOffset + i * objRowSize + 4)
        val off = orig.getInt()
        return if (off < 0) -1 else off
    }
```
`stubObjects`: `val st = objRowSTable(i); val stubObj = if (objRowDataOffset(i) < 0) TypeObject().also { it.st = st } else st.REPR.deserialize_stub(tc, st, this)`. `deserializeObjects`: `val off = objRowDataOffset(i); if (off < 0) continue; orig.position(objDataOffset + off)` (drop the `obj is TypeObject` test; the row says it). `repossess`: `origObj.st = objRowSTable(objIdx)`. In `deserializeSTableInner` delete the `version >= 5`, `>= 6`, `>= 9` conditionals (MIN_VERSION is 11): the container-spec branch keeps only its `readStr()` road, the `else throw "old container spec format"` goes, and the invocation-spec and HLL blocks are unconditional. **Every `orig.getLong()` in `deserializeSTableInner` reads a value the writer wrote with `writeInt` and becomes `readLong()`**: the v-table size, the type-check-cache size, `modeFlags`, the boolification flag and mode, the container-spec flag, the invocation-spec flag and hint, `hllRole`, the parametricity flag. The invocation spec's `lookupString(orig.getInt())` becomes `readStr()`. The parameterized type's element count is `VMArray.serialize`'s `writeInt32`, so `val elems = orig.getInt()` becomes `readInt32()`. In `deserializeContexts`, `val syms = orig.getLong()` and `ctx.iLex!![idx] = orig.getLong()` become `readLong()` (the writer's `writeInt(numLexicals)` and `writeInt(iLex[i])`); `orig.getDouble()` stays. Rule of thumb for any read this list misses: `putLong`/`writeInt` on the writer side is `readLong()` here, `writeInt32` is `readInt32()`, `writeStr` is `readStr()`, a hand-written `putInt(count)` in `writeRef` is `readCount()`, `writeNum` is `orig.getDouble()`.

- [ ] **Step 5: Rebuild, run the test on the version-12 wire, run the JUnit suite**

Runtime rebuild and retrain (Global Constraints). Run: `raku -e 'exit run(<prove -v --exec ./nqp-j-gradle t/jvm/23-sc-demand.t>, :cwd("nqp")).exitcode'` -- expected 24/24 (the stage jars are still version 11 and load through the dual road; the test's own SCs go out and back as version 12). Run `./nqp/gradlew -p nqp :nqp-runtime:test` -- all green. Then the nqp suite through the sweep (`$T/nqp-suite-task4.log`): `Result: PASS Files=155`; `t/serialization/*.t` is where a wire mismatch shows first. Then warm sanity (`$T/sanity-task4.log`): 25 files, 0 FAIL. Record all walls.

- [ ] **Step 6: Commit (nqp tree), ledger line (rakudo tree)**

```bash
git -C nqp add src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationWriter.kt src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationReader.kt t/jvm/23-sc-demand.t
GIT_AUTHOR_DATE='2026-09-18 19:10:00 +0200' GIT_COMMITTER_DATE='2026-09-18 19:10:00 +0200' git -C nqp commit -m "Serialization: format 12 -- packed references, varints, a string offset table, eight-byte object rows; the reader reads 11 and 12 (milestone 8, Phase C)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```
Ledger `## Task 4: format 12 on the runtime` with the four gate walls; commit the ledger (stamp 19:15).

---

### Task 5: The window build, the regen, version 11 removed, the clean build, row c1

**Files:**
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationReader.kt` (every `v12` branch collapses to the format-12 arm; `MIN_VERSION = 12`; `OBJECTS_TABLE_ENTRY_SIZE_V11` deleted)
- Working tree only, never committed: `nqp/src/vm/jvm/stage0/*.jar` (nine jars, regenerated)
- Modify: the ledger (`## C1` section with the row)

**Interfaces:**
- Consumes: Task 4's dual reader (the version-11 stage0 must load through it once).
- Produces: a tree whose every artifact is format 12; the reader is one format; row c1 in the ledger; the first-class CORE.c number for c1. **Checkpoint: after this task, report row c1 to the user and wait before Task 6** (user decision 4: one plan, a ledger checkpoint after c1).

- [ ] **Step 1: The window build**

`./nqp/gradlew -p nqp clean` (the stage graph misses the runtime-jar edge for the bootstrap; a clean makes stage1 re-run from the version-11 stage0 under the dual reader). Then:
```
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/a46e5ea6/tmp/make-c1-window.log --show='Compiling' --show='Generating' --show='dispatch-record' --show='Error' --stall=900 -- make
```
Expected: EXIT=0 in about 900-1000 s; a `dispatch-record: done ... 0 failed` line; then `raku tools/build/sc-blob-sizes.raku blib/CORE.c.setting.jar` prints `version=12` with `objTable` at 8 bytes a row and a `len` near 12 MB, and `ls nqp/build/jvm/stage2/` lists the stage jars (`raku tools/build/sc-blob-sizes.raku nqp/build/jvm/stage2/NQPCORE.setting.jar` prints `version=12`). If the window build fails inside the nqp bootstrap, the dual reader has a version-11 regression: fix it under Task 4's test and rebuild; do not touch stage0.

- [ ] **Step 2: Gate the window build**

The nqp suite through the sweep (`$T/nqp-suite-c1-window.log`, `Result: PASS Files=155`), warm sanity (`$T/sanity-c1-window.log`, 25 files, 0 FAIL), `23-sc-demand.t` 24/24. Record walls. Nothing is regenerated until all three are green (spec risk 4).

- [ ] **Step 3: Regenerate stage0**

Run: `raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/a46e5ea6/tmp/regen-c1.log --show='BUILD' --show='jBootstrapFiles' --stall=900 -- ./nqp/gradlew -p nqp jBootstrapFiles`
Expected: BUILD SUCCESSFUL in about 216 s; `git -C nqp status --short` shows exactly the nine `src/vm/jvm/stage0/*.jar` modified; `raku tools/build/sc-blob-sizes.raku nqp/src/vm/jvm/stage0/NQPCORE.setting.jar` prints `version=12`.

- [ ] **Step 4: Delete the version-11 road**

In `SerializationReader.kt`: `MIN_VERSION = 12`; delete `OBJECTS_TABLE_ENTRY_SIZE_V11` and `objRowSize` (use `OBJECTS_TABLE_ENTRY_SIZE`); every `if (v12) A else B` and `if (!v12) { ... }` collapses to its format-12 arm (`readLong`, `readInt32`, `readStr`, `readCount`, `readTag`, `readPackedRef`, `deserializeStringHeap`, `objRowSTable`, `objRowDataOffset`); delete the `v12` property. The `version` field stays (the header check needs it). Read the whole file once after: no `version >=` comparison other than the header's range check remains.

- [ ] **Step 5: The clean build from the new stage0**

```
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/a46e5ea6/tmp/configure-c1.log --show='BUILD' --show='Makefile' --stall=900 -- perl Configure.pl --backends=jvm --gen-nqp
```
(this cleans -- rakudo-j and every jar go -- and gradle-bootstraps the nested nqp from the regenerated stage0 under the one-format reader), then
```
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/a46e5ea6/tmp/make-c1.log --show='Compiling' --show='Generating' --show='dispatch-record' --show='Error' --stall=900 -- make
```
Expected: EXIT=0; record Configure's and make's walls and, from the make log, CORE.c's in-build stagestats (`parse`, `optimize`, `qast`, `unit` for `blib/CORE.c.setting.jar`) for the ledger. `rm -rf lib/.precomp` after the make if it exists (B-pre did).

- [ ] **Step 6: Gates and row c1**

In this order, nothing else running, each wall recorded:
1. `./nqp/gradlew -p nqp :nqp-runtime:test` -- all green.
2. `23-sc-demand.t` -- 24/24.
3. The nqp suite through the sweep (`$T/nqp-suite-c1.log`) -- `Result: PASS Files=155`.
4. Warm sanity (`$T/sanity-c1.log`) -- 25 files, 0 FAIL.
5. The rig: `raku tools/build/watched-run.raku --log=$T/rig-c1.log --show='m7-rig:' --stall=900 -- raku tools/build/m7-rig.raku --tag=c1 --out=m7-rig`. Expected `m7-rig: DONE`; the first cold run's dispatch line reads `staleSchema=0 staleStamp=0` (the stamps retrained inside the make).
6. One CORE.c compile:
```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/a46e5ea6/tmp/corec-c1.log --show='Stage' --stall=900 -- /usr/bin/perl rakudo-j-build --setting=NULL.c --ll-exception --optimize=3 --target=jar --stagestats --output=/home/longwalker/.claude/jobs/a46e5ea6/tmp/CORE.c.c1.jar gen/jvm/CORE.c.setting
```
Expected: a wall near b2b's 243-245 s (the writer runs inside `unit`; report `unit`'s stagestat against b2b's).
7. Sizes: `raku tools/build/sc-blob-sizes.raku blib/CORE.c.setting.jar`, the same for `blib/Perl6/BOOTSTRAP/v6c.jar`, and `ls -l blib/CORE.c.setting.jar blib/Perl6/BOOTSTRAP/v6c.jar nqp/src/vm/jvm/stage0/*.jar`.

- [ ] **Step 7: Commit (nqp tree, source only), the ledger (rakudo tree), push, checkpoint**

```bash
git -C nqp status --short   # the nine stage0 jars are listed as modified: leave them
git -C nqp add src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationReader.kt
GIT_AUTHOR_DATE='2026-09-18 20:30:00 +0200' GIT_COMMITTER_DATE='2026-09-18 20:30:00 +0200' git -C nqp commit -m "Serialization: format 11 read road removed; stage0 is format 12 (regenerated, uncommitted) (milestone 8, Phase C)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```
Ledger `## C1: the format (Task 5)`: the row line `| c1 | <rakudo> | <nqp> | ... |`, the window and clean build walls, every gate wall, the CORE.c wall and stagestats against b2b's, the blob table before/after (28,167,619 -> <n>) and the jar sizes, the `unit` stagestat delta, and the ruling that the STable row stays 12 bytes (the third int serves `peekAttributeShape` until Task 6). Commit (`Docs: Phase C ledger -- row c1, the format (milestone 8, Phase C)`, stamp 20:40). Push both trees: `git push ab5tract HEAD:worktree-jesp-direct-lazy-records` and `git -C nqp push ab5tract HEAD:jesp-direct-lazy-records`.

**CHECKPOINT.** Report row c1 (the cold rows against c0, the blob and jar sizes, the CORE.c wall) to the user and wait for the go-ahead before Task 6.

---

### Task 6: The demand reader -- the barrier, the drain, batch publication

The reader stays on its SC; the three root-set getters demand on a null slot; a drain finishes the transitive closure under one global lock and publishes at its end. No up-front stubbing. Runtime-only; the eager knob keeps the old behaviour reachable.

**Files:**
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/Drain.kt`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/RootSet.kt` (add `extend`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationContext.kt` (the barrier, `reader`, peek/publish/extend)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationReader.kt` (most of it: `deserialize`, `repossess`, the stub/finish/publish roads; `stubSTables`, `stubObjects`, `deserializeClosures`, `deserializeSTables`, `forceSTable`, `peekAttributeShape`, `deserializeObjects`, `deserializeContexts`, `attachClosureOuters`, `attachContextOuters`, `fixupContextOuters` deleted)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/reprs/RakuObjectREPR.kt:205, 245-258`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt:6560-6589` (`deserialize`: nothing but a comment; the reader installs itself)

**Interfaces:**
- Consumes: `RootSet` (Task 3), the format-12 reader helpers `readPackedRef`, `rowRef`, `objRef`, `codeRefOf`, `objRowSTable`, `objRowDataOffset`, `lookupString` (Tasks 4-5).
- Produces: `SerializationContext.reader: SerializationReader?`; `getObject/getSTable/getCodeRef` demand on null; `peekObject/peekSTable/peekCodeRef` (raw), `publishObject/publishSTable/publishCodeRef` (release), `extendCodeRefList(n)`. `SerializationReader.demandObject(i)`, `demandSTable(i)`, `demandCodeRef(i)` (the slow roads), `finish(e: Drain.Entry)`, `publish(e)`, the companion `LOCK`, `current`, `EAGER`, `VERIFY`, and the counters `stablesRead/objectsRead/closuresRead/contextsRead/drains/demandNanos` Task 7 prints. `NQP_SC_EAGER=1` drains every SC in full at the end of `deserialize()`.

- [ ] **Step 1: `RootSet.extend` and the context's barrier**

`RootSet.kt`, after `init`:
```kotlin
    /** size grows by [n] null slots (the closure slots after the static code refs). */
    fun extend(n: Int) {
        ensureCapacity(size + n)
        for (i in size until size + n) slots.lazySet(i, null)
        size += n
    }
```
`SerializationContext.kt`: add after `stamp`
```kotlin
    /* The demand reader of a deserialized SC (milestone 8, Phase C): a null
     * root slot asks it. Null for an SC built in this process. */
    @JvmField var reader: SerializationReader? = null
```
and replace the three getters and add the reader's raw roads:
```kotlin
    fun getObject(index: Int): SixModelObject? = objects.get(index) ?: reader?.demandObject(index)
    fun getSTable(index: Int): STable? = stables.get(index) ?: reader?.demandSTable(index)
    fun getCodeRef(index: Int): CodeRef? = codes.get(index) ?: reader?.demandCodeRef(index)

    /* The reader's own roads: a raw slot read (no demand) and the release
     * store that publishes a finished entry at a drain's end. */
    fun peekObject(index: Int): SixModelObject? = objects.get(index)
    fun peekSTable(index: Int): STable? = stables.get(index)
    fun peekCodeRef(index: Int): CodeRef? = codes.get(index)
    fun publishObject(index: Int, obj: SixModelObject) = objects.set(index, obj)
    fun publishSTable(index: Int, st: STable) = stables.set(index, st)
    fun publishCodeRef(index: Int, cr: CodeRef) = codes.set(index, cr)
    fun extendCodeRefList(n: Int) = codes.extend(n)
```
(`getObjectIndex` and friends read through `objects.get`, which is the raw slot; unchanged.) In `disclaimCodes`, the last of the three the `scdisclaim` op calls, add `reader = null` after `codes.clear()`: a disclaimed SC drops its reader and the mapped slice with it.

- [ ] **Step 2: Drain**

```kotlin
package org.raku.nqp.sixmodel

/**
 * The worklist of one outermost demand (milestone 8, Phase C). It belongs
 * to the drain, not to a reader: entries of any SC's reader queue on it,
 * and everything it finished is published into the root slots when the
 * outermost demand completes, in one batch (an object finished early may
 * hold a stub finished later in the same drain; publishing per drain is
 * what keeps a concurrent reader from seeing it). STables finish the
 * moment they are demanded -- an object stub needs its STable's REPR data
 * -- and closures at their stub; objects and contexts wait on the queue.
 */
class Drain {
    class Entry(@JvmField val reader: SerializationReader, @JvmField val kind: Int, @JvmField val index: Int)

    val queue = ArrayDeque<Entry>()
    val finished = ArrayList<Entry>()

    fun run() {
        while (true) {
            val e = queue.removeFirstOrNull() ?: return
            e.reader.finish(e)
            finished.add(e)
        }
    }

    fun publish() {
        for (e in finished) e.reader.publish(e)
    }

    companion object {
        const val STABLE = 0
        const val OBJECT = 1
        const val CODE = 2
        const val CONTEXT = 3
    }
}
```

- [ ] **Step 3: The reader**

Companion additions:
```kotlin
        /** One lock for every drain in the process: a worklist crosses SCs. */
        @JvmField val LOCK = java.util.concurrent.locks.ReentrantLock()
        /** The drain in progress on the thread holding LOCK; null outside one. */
        @JvmStatic var current: Drain? = null
        @JvmField val EAGER = System.getenv("NQP_SC_EAGER") != null
        @JvmField val VERIFY = System.getenv("NQP_SC_VERIFY") != null
        /** Every reader alive under the stats knob, for the exit line (Task 7). */
        @JvmField val LIVE = java.util.concurrent.ConcurrentLinkedQueue<SerializationReader>()
```
Fields replacing `stableState`/`contexts`/`shapeCache`/`curObject`'s neighbours:
```kotlin
    /* Per-STable progress (ST_UNREAD / ST_READING / ST_READ) and the stubs
     * not yet published, one table per kind; a root slot holds finished
     * entries only. */
    private lateinit var stableState: IntArray
    private lateinit var pendingSTable: Array<STable?>
    private lateinit var pendingObj: Array<SixModelObject?>
    private lateinit var pendingCode: Array<CodeRef?>
    private lateinit var contexts: Array<CallFrame?>
    /* The stats knob's counters (Task 7 prints them). */
    @JvmField var stablesRead = 0
    @JvmField var objectsRead = 0
    @JvmField var closuresRead = 0
    @JvmField var contextsRead = 0
    @JvmField var drains = 0
    @JvmField var demandNanos = 0L
```
`deserialize()`:
```kotlin
    fun deserialize() {
        val stats = org.raku.nqp.runtime.unit.UnitLoadStats.ON
        val t0 = if (stats) System.nanoTime() else 0L
        if (current != null) throw RuntimeException("deserialize called inside a demand drain")
        orig.order(ByteOrder.LITTLE_ENDIAN)
        checkAndDisectInput()
        deserializeStringHeap()
        resolveDependencies()

        /* The static code refs, in place; the closure slots after them stay
         * null until demanded. */
        sc.initCodeRefList(crCount + closureTableEntries)
        for (i in 0 until crCount) {
            ... (the existing null check and its message, unchanged) ...
            cr[i].isStaticCodeRef = true
            cr[i].sc = sc
            sc.addCodeRef(cr[i])
        }
        sc.extendCodeRefList(closureTableEntries)

        /* Root arrays to size, every slot null: nothing is stubbed up front. */
        sc.initSTableList(stTableEntries)
        sc.initObjectList(objTableEntries)
        stableState = IntArray(stTableEntries)
        pendingSTable = arrayOfNulls(stTableEntries)
        pendingObj = arrayOfNulls(objTableEntries)
        pendingCode = arrayOfNulls(closureTableEntries)
        contexts = arrayOfNulls(contextTableEntries)

        /* From here the barrier is live: the repossessions below demand
         * through it, and so does everything after us. */
        sc.reader = this
        if (stats) LIVE.add(this)
        if (reposTableEntries > 0) repossess()
        if (EAGER) drainAll()
        if (stats)
            org.raku.nqp.runtime.unit.UnitLoadStats.report(sc.handle, "sc-load", System.nanoTime() - t0,
                "stables=$stTableEntries objects=$objTableEntries coderefs=$crCount closures=$closureTableEntries contexts=$contextTableEntries")
    }
```
Repossession (replaces `repossess(chosenType)`; the two-pass order is STables then objects, as before):
```kotlin
    /* A repossessed entry replaces an object or STable other SCs already
     * hold, so it cannot wait: it is finished before deserialize() returns,
     * as MoarVM's repossess does. STables first (an object row names its
     * STable), then the objects in one drain. */
    private fun repossess() {
        for (pass in 1 downTo 0) {
            topLevel { d ->
                for (i in 0 until reposTableEntries) {
                    orig.position(reposTableOffset + i * REPOS_TABLE_ENTRY_SIZE)
                    val repoType = orig.getInt()
                    if (repoType != pass) continue
                    val slot = orig.getInt()
                    val origSC = locateSC(orig.getInt())
                    val origIdx = orig.getInt()
                    if (repoType == 1) {
                        val origST = origSC.getSTable(origIdx)!!
                        origST.sc = sc
                        origST.scIdx = slot
                        pendingSTable[slot] = origST
                        stableState[slot] = ST_UNREAD
                        d.finished.add(Drain.Entry(this, Drain.STABLE, slot))
                        finishSTable(slot)
                    } else if (repoType == 0) {
                        val origObj = origSC.getObject(origIdx)!!
                        origObj.sc = sc
                        origObj.scIdx = slot
                        /* Its STable may have changed (a mixin), so take the row's. */
                        origObj.st = objRowSTable(slot)
                        pendingObj[slot] = origObj
                        if (objRowDataOffset(slot) < 0) d.finished.add(Drain.Entry(this, Drain.OBJECT, slot))
                        else d.queue.add(Drain.Entry(this, Drain.OBJECT, slot))
                    } else {
                        throw RuntimeException("Unknown repossession type")
                    }
                }
            }
        }
    }
```
The drain frame and the three slow roads:
```kotlin
    /* One outermost demand: a drain, run to empty, then published. Inside
     * a drain (current != null, same thread -- the lock is held for the
     * drain's whole life) a demand only stubs and queues. */
    private inline fun <T> topLevel(body: (Drain) -> T): T {
        val t0 = System.nanoTime()
        val d = Drain()
        current = d
        try {
            val r = body(d)
            d.run()
            d.publish()
            return r
        } finally {
            current = null
            drains++
            demandNanos += System.nanoTime() - t0
        }
    }

    fun demandObject(index: Int): SixModelObject? {
        if (index < 0 || index >= objTableEntries) throw RuntimeException("Invalid SC object index $index")
        LOCK.lock()
        try {
            sc.peekObject(index)?.let { return it }
            val d = current
            if (d != null) return stubObject(index, d)
            val o = topLevel { stubObject(index, it) }
            if (VERIFY && sc.peekObject(index) !== o)
                throw RuntimeException("sc-verify: object $index of ${sc.handle} left a top-level demand unpublished")
            return o
        } finally {
            LOCK.unlock()
        }
    }

    fun demandSTable(index: Int): STable? {
        if (index < 0 || index >= stTableEntries) throw RuntimeException("Invalid STable index $index")
        LOCK.lock()
        try {
            sc.peekSTable(index)?.let { return it }
            val d = current
            if (d != null) return stubAndFinishSTable(index, d)
            return topLevel { stubAndFinishSTable(index, it) }
        } finally {
            LOCK.unlock()
        }
    }

    fun demandCodeRef(index: Int): CodeRef? {
        if (index < crCount) return null          /* a static ref is installed at load or absent for good */
        val j = index - crCount
        if (j >= closureTableEntries) throw RuntimeException("Invalid SC code index $index")
        LOCK.lock()
        try {
            sc.peekCodeRef(index)?.let { return it }
            val d = current
            if (d != null) return stubCode(j, d)
            return topLevel { stubCode(j, it) }
        } finally {
            LOCK.unlock()
        }
    }
```
Stubs and finishes. Every road that seeks the buffer saves and restores `orig.position()`, because a demand arrives from the middle of another entry's read of the same buffer:
```kotlin
    private fun stubAndFinishSTable(i: Int, d: Drain): STable {
        var st = pendingSTable[i]
        if (st == null) {
            val saved = orig.position()
            try {
                orig.position(stTableOffset + i * STABLES_TABLE_ENTRY_SIZE)
                val repr = REPRRegistry.getByName(lookupString(orig.getInt())!!)
                st = STable(repr, null)
            } finally {
                orig.position(saved)
            }
            st.sc = sc
            st.scIdx = i
            pendingSTable[i] = st
            d.finished.add(Drain.Entry(this, Drain.STABLE, i))
        }
        /* READING: a cycle through this STable's REPR data; the partly built
         * STable is the best on offer, as before. */
        if (stableState[i] == ST_UNREAD) finishSTable(i)
        return st
    }

    private fun finishSTable(i: Int) {
        stableState[i] = ST_READING
        val savedPos = orig.position()
        val savedCur = curObject
        curObject = null          /* an owned array read below belongs to no object */
        try {
            deserializeSTableInner(i)
        } finally {
            stableState[i] = ST_READ
            orig.position(savedPos)
            curObject = savedCur
        }
    }

    private fun stubObject(i: Int, d: Drain): SixModelObject {
        pendingObj[i]?.let { return it }
        val saved = orig.position()
        val obj: SixModelObject
        val concrete: Boolean
        try {
            val st = objRowSTable(i)          /* demands the STable: finished on return */
            concrete = objRowDataOffset(i) >= 0
            obj = if (concrete) st.REPR.deserialize_stub(tc, st, this)!!
                  else TypeObject().also { it.st = st }
        } finally {
            orig.position(saved)
        }
        obj.sc = sc
        obj.scIdx = i
        pendingObj[i] = obj
        val e = Drain.Entry(this, Drain.OBJECT, i)
        if (concrete) d.queue.add(e) else d.finished.add(e)
        return obj
    }

    private fun stubCode(j: Int, d: Drain): CodeRef {
        pendingCode[j]?.let { return it }
        val saved = orig.position()
        try {
            orig.position(closureTableOffset + j * CLOSURES_TABLE_ENTRY_SIZE)
            val staticCode = codeRefOf(rowRef())
            val closure = staticCode.clone(tc) as CodeRef
            closure.sc = sc
            closure.scCodeIdx = crCount + j
            pendingCode[j] = closure
            val ctxIdx = orig.getInt()
            val hasCodeObject = orig.getInt() != 0
            if (hasCodeObject) closure.codeObject = objRef(rowRef())
            if (ctxIdx > 0) closure.outer = contextAt(ctxIdx - 1, d)
            d.finished.add(Drain.Entry(this, Drain.CODE, j))
            return closure
        } finally {
            orig.position(saved)
        }
    }

    private fun contextAt(k: Int, d: Drain): CallFrame {
        contexts[k]?.let { return it }
        val saved = orig.position()
        try {
            orig.position(contextTableOffset + k * CONTEXTS_TABLE_ENTRY_SIZE)
            val staticCode = codeRefOf(rowRef())
            val ctx = CallFrame()
            ctx.tc = tc
            ctx.codeRef = staticCode
            val sci = staticCode.staticInfo
            if (sci.oLexicalNames != null) ctx.oLex = sci.oLexStatic!!.clone()
            if (sci.iLexicalNames != null) ctx.iLex = LongArray(sci.iLexicalNames!!.size)
            if (sci.nLexicalNames != null) ctx.nLex = DoubleArray(sci.nLexicalNames!!.size)
            if (sci.sLexicalNames != null) ctx.sLex = arrayOfNulls(sci.sLexicalNames!!.size)
            contexts[k] = ctx
            d.queue.add(Drain.Entry(this, Drain.CONTEXT, k))
            return ctx
        } finally {
            orig.position(saved)
        }
    }

    /* Drain.run's callback: finish one queued entry. */
    fun finish(e: Drain.Entry) {
        when (e.kind) {
            Drain.OBJECT -> {
                val obj = pendingObj[e.index]!!
                orig.position(objDataOffset + objRowDataOffset(e.index))
                curObject = obj
                try { obj.st.REPR.deserialize_finish(tc, obj.st, this, obj) }
                finally { curObject = null }
            }
            Drain.CONTEXT -> finishContext(e.index)
            else -> throw IllegalStateException("only objects and contexts are queued")
        }
    }

    private fun finishContext(k: Int) {
        val ctx = contexts[k]!!
        val sci = ctx.codeRef.staticInfo
        orig.position(contextTableOffset + k * CONTEXTS_TABLE_ENTRY_SIZE + 8)
        val dataOffset = orig.getInt()
        val outerIdx = orig.getInt()
        orig.position(contextDataOffset + dataOffset)
        val syms = readLong()
        for (j in 0 until syms) {
            ... (the existing lexical loop body, verbatim: readStr, oTryGetLexicalIdx / readRef, iTryGetLexicalIdx / readLong, nTryGetLexicalIdx / orig.getDouble, sTryGetLexicalIdx / readStr, else throw) ...
        }
        if (outerIdx > 0) ctx.outer = contextAt(outerIdx - 1, current!!)
        else ctx.resolveDeserializedOuter()
    }

    /* Drain.publish's callback: the release store into the root slot. */
    fun publish(e: Drain.Entry) {
        when (e.kind) {
            Drain.STABLE -> { sc.publishSTable(e.index, pendingSTable[e.index]!!); pendingSTable[e.index] = null; stablesRead++ }
            Drain.OBJECT -> { sc.publishObject(e.index, pendingObj[e.index]!!); pendingObj[e.index] = null; objectsRead++ }
            Drain.CODE -> { sc.publishCodeRef(crCount + e.index, pendingCode[e.index]!!); pendingCode[e.index] = null; closuresRead++ }
            Drain.CONTEXT -> contextsRead++
        }
    }

    /* NQP_SC_EAGER=1: everything at load, the pre-Phase-C order, for
     * bisecting a demand-order bug. */
    private fun drainAll() {
        topLevel { d ->
            for (i in 0 until stTableEntries) stubAndFinishSTable(i, d)
            for (i in 0 until objTableEntries) stubObject(i, d)
            for (j in 0 until closureTableEntries) stubCode(j, d)
            for (k in 0 until contextTableEntries) contextAt(k, d)
        }
    }
```
`deserializeSTableInner(i)`: `val st = pendingSTable[i]!!` instead of `sc.getSTable(i)!!`; the rest unchanged (its `readObjRef`/`readRef`/`readSTableRef` calls now demand: an object reference stubs and queues, an STable reference finishes). Delete: `stubSTables`, `stubObjects`, `deserializeClosures`, `deserializeSTables`, `deserializeSTable` (its body is `finishSTable`), `forceSTable`, `peekAttributeShape` and `shapeCache`, `deserializeObjects`, `deserializeContexts`, `attachClosureOuters`, `attachContextOuters`, `fixupContextOuters`, the old `repossess(chosenType)`, and the `sc-stub`/`sc-finish` stats block. `lookupSTable(scIdx, idx)` stays as written (its `stSC.getSTable(idx)!!` is the barrier).

`RakuObjectREPR.kt`: delete the three-argument `deserialize_stub` override (lines 245-258; the two-argument one at 259 builds from the layout, which the finished REPR data holds); in `deserialize_repr_data` delete `reader.forceSTable(f)` at line 205 (the `readSTableRef()` that produced `f` finished it) and the loop around it if nothing else is in it. `REPR.kt`'s three-argument default (line 102) stays for the other REPRs.

`Ops.deserialize`: no code change; add above `sr.deserialize()` the comment `/* The reader installs itself on the SC (sc.reader) and lives as long as it: Phase C's demand road. */`.

- [ ] **Step 4: Compile, rebuild, the tests, the suite twice**

`./nqp/gradlew -p nqp :nqp-runtime:test` -- green (the reader has no unit test of its own; the format test and the suites are its tests). Runtime rebuild and retrain. Then:
1. `raku -e 'exit run(<prove -v --exec ./nqp-j-gradle t/jvm/23-sc-demand.t>, :cwd("nqp")).exitcode'` -- 24/24.
2. `RAKUDO_RAKUAST=1 ./rakudo-j -e 'say 1'` prints `1`; with `NQP_UNIT_LOAD_STATS=1` its stderr has `sc-load` lines and no `sc-stub`/`sc-finish`.
3. The nqp suite through the sweep (`$T/nqp-suite-task6.log`) -- `Result: PASS Files=155`.
4. The same with `NQP_SC_EAGER=1` in the environment (`NQP_SC_EAGER=1 raku tools/build/watched-run.raku --log=$T/nqp-suite-task6-eager.log ... --suite=nqp --chunk='*'`) -- identical `Files=` and `Tests=` and the same pass/fail per file (diff the two logs' `not ok` lines: none in either).
5. Warm sanity (`$T/sanity-task6.log`) -- 25 files, 0 FAIL.
A stub reaching guest code shows as a wrong attribute, a null where an object was expected, or `Bind check failed` noise: rerun the failing file with `NQP_SC_EAGER=1`; if it passes, the demand order is the bug, and `NQP_SC_VERIFY=1` names the index.

- [ ] **Step 5: Commit (nqp tree), ledger (rakudo tree)**

```bash
git -C nqp add src/vm/jvm/runtime/org/raku/nqp/sixmodel/Drain.kt src/vm/jvm/runtime/org/raku/nqp/sixmodel/RootSet.kt src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationContext.kt src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationReader.kt src/vm/jvm/runtime/org/raku/nqp/sixmodel/reprs/RakuObjectREPR.kt src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt
GIT_AUTHOR_DATE='2026-09-18 21:20:00 +0200' GIT_COMMITTER_DATE='2026-09-18 21:20:00 +0200' git -C nqp commit -m "Serialization: the demand reader -- a null root slot demands, a drain finishes and publishes, NQP_SC_EAGER/NQP_SC_VERIFY (milestone 8, Phase C)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```
Ledger `## Task 6: the demand reader` with the five gate walls; commit (stamp 21:25).

---

### Task 7: Lazy HOW and WHO, the exit line, the tools, test part B

**Files:**
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/STable.kt:1-20, 78` (`HOW`, `WHO`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationReader.kt` (`deserializeSTableInner`: the HOW and WHO reads; `reportAll`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitLoadStats.kt:23-26` (the exit hook)
- Modify: `tools/build/m7-rig.raku:55-70` (`parse-cold`) and the summary print that shows `restored=`
- Modify: `tools/build/unit-load-exclusive.raku:13-23` (the stage set) and its report
- Test: `nqp/t/jvm/23-sc-demand.t` (part B appended; `plan(31)`)

**Interfaces:**
- Consumes: `SerializationContext.getObject` (the barrier), the reader's counters and `LIVE` (Task 6).
- Produces: `STable.HOW` / `STable.WHO` as properties (`get` demands, `set` clears the pending pair), `STable.setPendingHow(sc, idx)`, `STable.setPendingWho(sc, idx)`; the stderr line `sc-demand <handle> stables=<f>/<t> objects=<f>/<t> closures=<f>/<t> contexts=<f>/<t> drains=<n> ms=<d.dd>` at exit under `NQP_UNIT_LOAD_STATS=1`; `m7-rig.raku`'s summary fields `scObjects=f/t scStables=f/t scDrains= scMs=`.

- [ ] **Step 1: Write the failing test** -- append to `23-sc-demand.t`, and change `plan(24)` to `plan(31)`

```nqp
# Part B: the demand counts of a child `./nqp-j-gradle -e 'say(1)'` under
# NQP_UNIT_LOAD_STATS=1. The child-process helper is the one of
# t/jvm/20-op-census.t (copy child-stderr, create_buf, Queue, VMDecoder
# from there verbatim).

# The sc-demand line with the largest object total (NQPCORE's SC in an
# nqp run): [finished, total] for objects, or [-1, -1].
sub demand-objects($text) {
    my $best-total := -1; my $best := -1;
    for nqp::split("\n", $text) -> $line {
        if nqp::index($line, 'sc-demand ') == 0 {
            for nqp::split(' ', $line) -> $kv {
                if nqp::index($kv, 'objects=') == 0 {
                    my @ft := nqp::split('/', nqp::substr($kv, 8));
                    if +@ft[1] > $best-total { $best-total := +@ft[1]; $best := +@ft[0] }
                }
            }
        }
    }
    nqp::list($best, $best-total)
}

my %stats := nqp::getenvhash();
%stats<NQP_UNIT_LOAD_STATS> := '1';
my @lazy := child-stderr('say(1)', %stats);
is(@lazy[0], 0, 'the child under NQP_UNIT_LOAD_STATS=1 exits clean');
ok(nqp::index(@lazy[1], 'sc-demand ') >= 0, 'sc-demand lines print at exit');
my @lo := demand-objects(@lazy[1]);
ok(@lo[0] > 0, 'the largest SC finished some objects on demand (' ~ @lo[0] ~ ')');
ok(@lo[0] < @lo[1], 'and fewer than all of them (' ~ @lo[0] ~ ' of ' ~ @lo[1] ~ ')');

my %eager := nqp::getenvhash();
%eager<NQP_UNIT_LOAD_STATS> := '1';
%eager<NQP_SC_EAGER> := '1';
my @eager := child-stderr('say(1)', %eager);
is(@eager[0], 0, 'the child under NQP_SC_EAGER=1 exits clean');
my @eo := demand-objects(@eager[1]);
ok(@eo[0] == @eo[1] && @eo[1] == @lo[1], 'under NQP_SC_EAGER=1 every object is finished (' ~ @eo[0] ~ ' of ' ~ @eo[1] ~ ')');

my %verify := nqp::getenvhash();
%verify<NQP_SC_VERIFY> := '1';
my @verify := child-stderr('say(1)', %verify);
is(@verify[0], 0, 'the child under NQP_SC_VERIFY=1 exits clean');
```

- [ ] **Step 2: Run it to see part B fail**

Run: `raku -e 'exit run(<prove -v --exec ./nqp-j-gradle t/jvm/23-sc-demand.t>, :cwd("nqp")).exitcode'`
Expected: 24 ok, then `not ok` on "sc-demand lines print at exit" and the counts (the line does not exist yet).

- [ ] **Step 3: `STable.HOW` and `WHO` as demanding properties**

Replace the constructor's `@JvmField var HOW: SixModelObject?,` with `how: SixModelObject?,` and add in the body (before `REPRData`):
```kotlin
    /**
     * The meta-object. Null while the KnowHOW bootstrap is creating the
     * very first types. Under the demand reader (milestone 8, Phase C) a
     * deserialized STable holds only its HOW's SC and index until the
     * first read: a type reached by a type check never pulls its metaclass
     * and method tables. Every Kotlin reader keeps `st.HOW`; the setter
     * clears the pending pair.
     */
    private var howField: SixModelObject? = how
    private var howSC: SerializationContext? = null
    private var howIdx = -1
    var HOW: SixModelObject?
        get() = howField ?: resolvePendingHow()
        set(v) { howField = v; howSC = null }

    private fun resolvePendingHow(): SixModelObject? {
        val s = howSC ?: return null
        val v = s.getObject(howIdx)
        howField = v
        howSC = null
        return v
    }

    fun setPendingHow(sc: SerializationContext, idx: Int) { howField = null; howSC = sc; howIdx = idx }
```
and replace `@JvmField var WHO: SixModelObject? = null` with the same shape (`whoField`, `whoSC`, `whoIdx`, `WHO` get/set, `resolvePendingWho`, `setPendingWho`), its KDoc: "The stash / package. Pending like HOW: a stash's hash reaches every symbol under it, a large share of a setting's SC." Two threads racing a getter resolve the same object; the plain writes are benign. The constructor's parameter is now `how`, not `HOW`: the 40 construction sites are positional, but check with `grep -rn 'STable(.*HOW *=' nqp/src/vm/jvm/runtime nqp/nqp-truffle/src` that no call names it (none expected).

- [ ] **Step 4: The reader leaves HOW and WHO pending**

In `deserializeSTableInner`, replace
```kotlin
        st.HOW = readObjRef()
        st.WHAT = readObjRef()
        st.WHO = readRef()
```
with
```kotlin
        /* HOW and WHO stay pending (Phase C): the reference is kept, the
         * object demanded on first read. WHAT is the type object itself,
         * a stub with no data, so it is read now. */
        val how = readPackedRef()
        st.setPendingHow(locateSC((how ushr 32).toInt()), how.toInt())
        st.WHAT = readObjRef()
        val whoTag = readTag()
        if (whoTag == REFVAR_OBJECT) {
            val who = readPackedRef()
            st.setPendingWho(locateSC((who ushr 32).toInt()), who.toInt())
        } else {
            orig.position(orig.position() - 1)
            st.WHO = readRef()
        }
```
(`readTag` is one byte after Task 5, so the position steps back by one.)

- [ ] **Step 5: The exit line**

Reader companion:
```kotlin
        /** One line per reader alive under NQP_UNIT_LOAD_STATS=1, at exit. */
        @JvmStatic
        fun reportAll() {
            for (r in LIVE) {
                System.err.println("sc-demand ${r.sc.handle} stables=${r.stablesRead}/${r.stTableEntries}" +
                    " objects=${r.objectsRead}/${r.objTableEntries} closures=${r.closuresRead}/${r.closureTableEntries}" +
                    " contexts=${r.contextsRead}/${r.contextTableEntries} drains=${r.drains}" +
                    " ms=${"%.2f".format(r.demandNanos / 1_000_000.0)}")
            }
        }
```
(the four `*TableEntries` fields become `internal` or get a getter; `sc` is a constructor property already.) `UnitLoadStats.init`:
```kotlin
    init {
        // The positive marker: a run that relies on these lines checks for it.
        if (ON) {
            System.err.println("unit-load: stats on")
            Runtime.getRuntime().addShutdownHook(Thread { org.raku.nqp.sixmodel.SerializationReader.reportAll() })
        }
    }
```

- [ ] **Step 6: The tools**

`tools/build/m7-rig.raku`, in `parse-cold` after the `publishes` line:
```raku
    # Phase C: the demand reader's exit line of the largest SC (CORE.c in a
    # rakudo run, NQPCORE in an nqp run). Summary-only, like restored=.
    my $largest = -1;
    for $text.lines {
        if / ^ 'sc-demand ' (\S+) ' stables=' (\d+) '/' (\d+) ' objects=' (\d+) '/' (\d+)
              ' closures=' (\d+) '/' (\d+) ' contexts=' (\d+) '/' (\d+) ' drains=' (\d+) ' ms=' (\d+ [ '.' \d+ ]?) /
           and +$4 > $largest {
            $largest = +$4;
            %r<sc-objects> = +$3; %r<sc-objects-total> = +$4;
            %r<sc-stables> = +$1; %r<sc-stables-total> = +$2;
            %r<sc-drains> = +$9;  %r<sc-ms> = +$10;
        }
    }
```
and wherever the per-run summary prints `restored=` (one `say`), append ` scObjects={%r<sc-objects> // '-'}/{%r<sc-objects-total> // '-'} scStables={%r<sc-stables> // '-'}/{%r<sc-stables-total> // '-'} scDrains={%r<sc-drains> // '-'} scMs={%r<sc-ms> // '-'}`. Check: `raku tools/build/m7-rig.raku --tag=probe --out=$T/rig-probe --runs=1 --/warm` prints the new fields non-`-` for both cold rows (delete `$T/rig-probe` after).

`tools/build/unit-load-exclusive.raku`: `CHILD = set <load-total sc-load>` (the comment lines 6-8 and 13-14 name `sc-load` in place of `sc-stub`/`sc-finish`, and add: "The `sc-demand` lines are not stages: demand time is charged to whichever stage triggered it; they are printed after the table."), and at the end of `MAIN`:
```raku
    my @demand = $file.IO.lines.grep(*.starts-with('sc-demand '));
    if @demand {
        say "demand at exit (charged above to the stages that triggered it):";
        say "  $_" for @demand;
    }
```

- [ ] **Step 7: Rebuild, tests, suites**

Runtime rebuild and retrain. `./nqp/gradlew -p nqp :nqp-runtime:test` green. `23-sc-demand.t` 31/31. `NQP_UNIT_LOAD_STATS=1 RAKUDO_RAKUAST=1 ./rakudo-j -e 'say 1' 2>$T/stats-task7.txt`: the `sc-demand` line for CORE.c's SC (the one with `objects=.../276157`) -- note its numbers; `raku tools/build/unit-load-exclusive.raku $T/stats-task7.txt` shows `sc-load` in the table and the demand lines after it. The nqp suite through the sweep (`$T/nqp-suite-task7.log`) `Result: PASS Files=155`; warm sanity (`$T/sanity-task7.log`) 25 files, 0 FAIL. Record walls.

- [ ] **Step 8: Commit (nqp tree; rakudo tree for the tools), ledger**

```bash
git -C nqp add src/vm/jvm/runtime/org/raku/nqp/sixmodel/STable.kt src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationReader.kt src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitLoadStats.kt t/jvm/23-sc-demand.t
GIT_AUTHOR_DATE='2026-09-18 22:00:00 +0200' GIT_COMMITTER_DATE='2026-09-18 22:00:00 +0200' git -C nqp commit -m "Serialization: HOW and WHO pending until read; the sc-demand exit line; the demand test (milestone 8, Phase C)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git add tools/build/m7-rig.raku tools/build/unit-load-exclusive.raku docs/superpowers/plans/2026-09-18-jvm-milestone-8-phase-c.ledger.md
GIT_AUTHOR_DATE='2026-09-18 22:05:00 +0200' GIT_COMMITTER_DATE='2026-09-18 22:05:00 +0200' git commit -m "Tools: the rig and the exclusive-time tool read the sc-demand line (milestone 8, Phase C)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```
(the ledger gets `## Task 7` with the walls and the first CORE.c `sc-demand` numbers before that commit).

---

### Task 8: Row c2, the exit finding, the documents, the close of the phase

**Files:**
- Modify: the ledger (`## C2` section, the C3 decision, the close)
- Modify: `docs/jvm-unit-lazy-loading.md` (a "Format 12 and the demand reader" section: the layout of Task 4, the barrier, the drain, the three knobs, the exit line)
- Modify: `docs/jvm-perf-findings-2026-09.md` (a Phase C entry with rows c0, c1, c2 and the finding)
- Modify: `docs/jvm-truffle-only-plan.md` (the position paragraph: Phase C closed, what it moved, what waits)
- Modify: memory `milestone-8-stable-assumption.md` and the `MEMORY.md` index line

**Interfaces:**
- Consumes: everything above at its final commit; the rig's `scObjects=` field (Task 7).
- Produces: the phase's close; the user's decision point (Phase B's plan B or the milestone close).

- [ ] **Step 1: Row c2 and its gates**

Runtime jars are current (Task 7), retrained, eval servers restarted. In this order, nothing else running, walls recorded:
1. `./nqp/gradlew -p nqp :nqp-runtime:test`; `23-sc-demand.t` 31/31.
2. The nqp suite through the sweep (`$T/nqp-suite-c2.log`) -- `Result: PASS Files=155`; then once more with `NQP_SC_EAGER=1` (`$T/nqp-suite-c2-eager.log`) -- identical counts, no `not ok` in either (spec Section 4's c2 gate).
3. Warm sanity (`$T/sanity-c2.log`) -- 25 files, 0 FAIL.
4. The rig: `raku tools/build/watched-run.raku --log=$T/rig-c2.log --show='m7-rig:' --stall=900 -- raku tools/build/m7-rig.raku --tag=c2 --out=m7-rig`. Expected `m7-rig: DONE`; the summary's `scObjects=f/276157` for rakudo-e and `scObjects=f/t` for nqp-e are the exit finding.
5. One CORE.c compile, the Task 5 command with `c2` in the file names. Expected: near c1's wall (the compiler's own loads are lazy now; the writer unchanged).
6. `raku tools/build/unit-load-exclusive.raku m7-rig/c2-rakudo-e-run1.err` (or whichever run file the rig saved as best): the table without `sc-stub`/`sc-finish`, `sc-load` small, the demand lines after it.

- [ ] **Step 2: The exit finding and the C3 decision**

In the ledger's `## C2` section: the row line; every gate wall; the exclusive table of c2 against c0's (load-block, deserialize-program, sc-load vs sc-stub+sc-finish, shells, open-store); CORE.c's `sc-demand` line (`objects=f/276157`, `stables=f/5558`, `drains=n`, `ms=d`); the CORE.c wall against c1's. Then the decision, by the spec's Section 3 threshold, stated as one of:
- `f / 276157 > 0.5`: **C3 is designed** -- "the fixups force <f> of 276157 objects (<pct> %); a C3 (the code object in the code-ref table, compiler-side, one full build) is brainstormed next, with this row as its baseline"; or
- `f / 276157 <= 0.5`: **the fixup row goes to the milestone close's ranking** -- "the fixups force <f> of 276157 (<pct> %); the demand time of <d> ms against the 304 ms the load used to spend is the row's gain; the fixup row is ranked at the close beside the bodies row".
Either way, state the row's gain on the cold clock (c2 against c0, best-of-5 each), the honest ceiling (304 ms), and the `deserialize-program` row's new exclusive time.

- [ ] **Step 3: The documents**

`docs/jvm-unit-lazy-loading.md`: a section "Format 12 and the demand reader (milestone 8, Phase C)" with the Task 4 layout list verbatim, the barrier in three sentences (null root slot demands; a drain finishes the transitive closure under `SerializationReader.LOCK`; publication per drain), the STable-immediate / object-queued rule, HOW and WHO pending, lazy strings, the knobs `NQP_SC_EAGER`, `NQP_SC_VERIFY`, the `sc-load` stage and the `sc-demand` exit line, and the sizes before and after. `docs/jvm-perf-findings-2026-09.md`: a "Milestone 8 Phase C" entry with the three rows, the blob and jar sizes, the exit finding, the C3 decision. `docs/jvm-truffle-only-plan.md`: the position paragraph updated (Phase C closed on <date>; Phase B parked at b2b with plan B open; the next decision is the user's).

- [ ] **Step 4: Commit, push, memory, rebase**

```bash
git add docs/superpowers/plans/2026-09-18-jvm-milestone-8-phase-c.ledger.md docs/jvm-unit-lazy-loading.md docs/jvm-perf-findings-2026-09.md docs/jvm-truffle-only-plan.md
GIT_AUTHOR_DATE='2026-09-18 22:40:00 +0200' GIT_COMMITTER_DATE='2026-09-18 22:40:00 +0200' git commit -m "Docs: Phase C close -- row c2, the exit finding, the C3 decision (milestone 8, Phase C)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push ab5tract HEAD:worktree-jesp-direct-lazy-records
git -C nqp push ab5tract HEAD:jesp-direct-lazy-records
```
Memory: append the close to `milestone-8-stable-assumption.md` (rows, the finding, the decision, the tips of both trees) and rewrite the `MEMORY.md` line's Phase C clause. Then the handoff rebase (the worktree rule): `git fetch origin && git rebase origin/main` in the rakudo tree, `git -C nqp fetch upstream && git -C nqp rebase upstream/main`, and `git push --force-with-lease ab5tract HEAD:worktree-jesp-direct-lazy-records` / `git -C nqp push --force-with-lease ab5tract HEAD:jesp-direct-lazy-records`; record the post-rebase tips in memory. No gate after the rebase (user, 2026-09-09).

- [ ] **Step 5: Report**

Report to the user: the three rows in one table (cold rakudo-e, cold nqp-e, warm proxy, CORE.c wall, blob and jar sizes), the exit finding and the C3 decision, the list of what is parked (Phase B plan B and its three items; the `sh` parameter of `Ops.deserialize`/`SerializationReader` now unused, a cleanup), and the decision that is theirs: plan B or the milestone close.
