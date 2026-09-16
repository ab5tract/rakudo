# Milestone 8 Phase B, part 1: the opening commit and the census (B-pre + B0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the cross-build stale-slot hazard with an SC stamp, make Rakudo's runtime jar order-only, fix the two Phase A parkings, land the op census knob with its tooling, and take rig row `b0` plus the baseline census that every Phase B batch is compared against.

**Architecture:** Every SC deserialized from a unit artifact carries the CRC32 of its `unit.serialized` zip entry as its stamp; a persisted dispatch slot records one stamp per SC handle it references and is dropped on restore when any stamp disagrees with the loaded SC. The census is one Kotlin object in the engine module with `LongAdder` counters behind `@TruffleBoundary` bumps, guarded by a `static final` knob so compiled code carries nothing when it is off, printed from a shutdown hook next to the dispatch stats. Two Raku tools grow one flag each so the rig and the JFR attribution read the census.

**Tech Stack:** Kotlin (nqp-runtime, nqp-truffle), one Java touch (`NqpRootNode.java`), kotlinx serialization through `UnitCodec`, JUnit via `kotlin.test`, nqp `.t` tests under `prove`, Raku tools, GNU make template.

**Spec:** `docs/superpowers/specs/2026-09-16-jvm-milestone-8-phase-b-promotion-campaign-design.md` (sections 1, 2 and 5). Parent: `docs/superpowers/specs/2026-09-16-jvm-milestone-8-type-state-design.md`.

## Global Constraints

- **Work in the worktree only:** `/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records` (rakudo tree) and its nested `nqp/` (nqp tree, a separate git working tree, NOT a submodule). Label every hash by tree. Never `cd` in the tool shell; use absolute paths or a subshell `( cd ... && ... )`.
- **Push to `ab5tract`, never to `origin`** (origin is upstream rakudo/rakudo): `git push ab5tract HEAD` from the rakudo tree, `git -C nqp push ab5tract HEAD` from the nqp tree. Never push to main/master, never force-push, never merge.
- **Kotlin, never Java**, for new code (user rule). The only Java touch here is two one-line hooks in `NqpRootNode.java`.
- **Every debug/log print env-gated** (`System.getenv`, `nqp::getenvhash`), never bare.
- **`RAKUDO_RAKUAST=1` on every rakudo run** outside `make` (the Makefile exports it itself).
- **No jar commits** (stage0 included). No artifact format change: `UnitStore.VERSION` stays 2, `UnitImageWriter` is untouched.
- **Long builds and test runs go through `tools/build/watched-run.raku`** (`--log=`, `--show=LITERAL` repeated, `--stall=`); report every gate WITH its wall time.
- **Runtime jars rebuild in seconds:** `./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars` from the rakudo tree; restart any eval server afterwards. Runtime JUnit: `./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.dispatch.DispatchPersistTest'` (one class) or without `--tests` (all).
- **Commit stamps:** every commit gets `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE` in the 18:00-23:00 window of 2026-09-16 (`2026-09-16T19:30:00+0200` and later, increasing), and ends with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- **`java` is Oracle GraalVM 25.2.4** (`java -version` shows it); a plain JDK voids every number.
- **Temporary files** go under `/home/longwalker/.claude/jobs/455b5a91/tmp`, never `/tmp`.
- **Ledger:** `docs/superpowers/plans/2026-09-16-jvm-milestone-8-phase-b.ledger.md` (rakudo tree, created in Task 6; earlier tasks append their rulings to the process notes and Task 6 carries them in). Every deviation from this plan is a `Ruling:` line with its reason and its cost-if-wrong.

---

## File structure

nqp tree (`nqp/`):
- `src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ZipDirectory.kt` — `Entry` gains `crc` (Task 1).
- `src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitStore.kt` — keeps the per-entry CRCs; `serializedCrc` (Task 1).
- `src/vm/jvm/runtime/org/raku/nqp/runtime/CompilationUnit.kt` — `serializedStamp()` default 0 (Task 1).
- `src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt` — overrides it with the store's CRC (Task 1).
- `src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationContext.kt` — `stamp` (Task 1).
- `src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt` — `deserialize` sets the stamp on the unit road (Task 1).
- `src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlot.kt` — `PStamp`, `stamps`, `SCHEMA = 2` (Task 2).
- `src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlotCodec.kt` — `persist(p, stamps)` collects stamps through `ref()` (Task 2).
- `src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt` — `staleStamp`, the restore check, the record side (Task 2).
- `src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchRecord.kt` — parking 1 (Task 3).
- `src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchBootstrap.kt` — parking 2 (Task 3).
- `nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpCensus.kt` — NEW: the census (Task 4).
- `nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt` — site counters (Task 4).
- `nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt` — `staleStamp=` on the stats line (Task 2).
- `nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java` — two census hooks (Task 4).
- `t/jvm/20-op-census.t` — NEW (Task 4).
- Tests: `nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitStoreTest.kt`, `.../dispatch/DispatchSlotCodecTest.kt`, `.../dispatch/DispatchPersistTest.kt`, `.../dispatch/GuardStateTest.kt`.

rakudo tree:
- `tools/templates/jvm/Makefile.in` — order-only runtime jar (Task 3).
- `tools/build/jfr-attribute.raku` — `--ops` (Task 5).
- `tools/build/m7-rig.raku` — `--census`, `--parse-census` (Task 5).
- `docs/superpowers/specs/2026-09-16-jvm-milestone-8-phase-b-promotion-campaign-design.md` — Revision 1 note on stamp 0 (Task 2).
- `docs/superpowers/plans/2026-09-16-jvm-milestone-8-phase-b.ledger.md` — NEW (Task 6).

---

### Task 1: the SC stamp, from the zip directory to the SerializationContext

**Files:**
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ZipDirectory.kt:13,49`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitStore.kt:21-24,42-52,164-175`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CompilationUnit.kt:160-163`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt:203`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationContext.kt:12-14`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt:6573-6576` (the `deserialize` op, `if (blob == null)` branch)
- Test: `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitStoreTest.kt`

**Interfaces:**
- Produces: `ZipDirectory.Entry(offset: Int, size: Int, crc: Int)`; `UnitStore.serializedCrc: Int` (0 when the unit has no `unit.serialized` entry); `CompilationUnit.serializedStamp(): Int` (open, default 0); `SerializationContext.stamp: Int` (`@JvmField var`, 0 = in-process SC).
- Consumed by Task 2 (`sc.stamp` on both the record and the restore road).

- [ ] **Step 1: Write the failing test**

Add to `UnitStoreTest.kt` (imports: `java.util.zip.CRC32`, `org.raku.nqp.runtime.unit.ProgramUnitTestSupport`, `org.raku.nqp.runtime.unit.UnitImage`, `org.raku.nqp.runtime.unit.UnitImageWriter`; the file already imports `ByteBuffer`, `Test`, `assertEquals`):

```kotlin
    /** The stamp of a unit's SC is the CRC32 of its unit.serialized entry,
     *  read from the zip central directory: no hashing at load, no format
     *  change (the writer already sets a real CRC on every stored entry). */
    @Test fun theSerializedEntrysCrcIsTheStamp() {
        val base = ProgramUnitTestSupport.image()
        val bytes = byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8)
        val img = UnitImage(base.unitId, base.hll, base.scHandle, base.scDesc, base.serializedCodeRefCount,
            base.mainlineQbid, base.entryQbid, base.deserializeQbid, base.loadQbid, base.blocks, base.programs,
            base.dispatchCounts, bytes, base.nested, emptyMap())
        val store = UnitStore.open(ByteBuffer.wrap(UnitImageWriter.bytes(img)), "/x/stamp.jar")
        assertEquals(CRC32().also { it.update(bytes) }.value.toInt(), store.serializedCrc)
    }
```

- [ ] **Step 2: Run it to verify it fails**

Run (from the rakudo tree): `./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.runtime.unit.UnitStoreTest'`
Expected: compilation FAILS on `store.serializedCrc` (unresolved reference).

- [ ] **Step 3: Thread the CRC through**

`ZipDirectory.kt`: change the class line and the constructor call.

```kotlin
    /** [crc] is the entry's CRC32 as the central directory records it: the
     *  unit loader's stamp for the SC an entry carries (DispatchSlot). */
    class Entry(@JvmField val offset: Int, @JvmField val size: Int, @JvmField val crc: Int)
```
and inside `read`, before `val nameLen`:
```kotlin
            val crc = buf.getInt(cen + 16)
```
and the construction: `out[entryName] = Entry(data, usize, crc)`.

`UnitStore.kt`: the constructor gains the CRC map, `open` fills it, `nested` passes it, and the accessor reads it.

```kotlin
class UnitStore private constructor(
    @JvmField val name: String,
    private val entries: Map<String, ByteBuffer>,      // each slice: position 0, LITTLE_ENDIAN
    private val crcs: Map<String, Int>,                 // the zip directory's CRC32 per entry
    private val prefix: String,                         // "unit" or "nested/<id>"
) {
```
In `open(bytes, name)`:
```kotlin
            val slices = HashMap<String, ByteBuffer>(dir.size * 2)
            val crcs = HashMap<String, Int>(dir.size * 2)
            for ((n, e) in dir) {
                slices[n] = whole.slice(e.offset, e.size).asReadOnlyBuffer().order(ByteOrder.LITTLE_ENDIAN)
                crcs[n] = e.crc
            }
            return UnitStore(name, slices, crcs, "unit")
```
Replace the `entry()` body and add the accessor, next to `val serialized`:
```kotlin
    private fun key(unitEntryName: String): String =
        if (prefix == "unit") unitEntryName else prefix + unitEntryName.removePrefix("unit")

    val serialized: ByteBuffer? get() = entry(SERIALIZED)

    /** The CRC32 of this unit's serialized entry, from the zip directory:
     *  the stamp every SC deserialized from it carries. 0 when the unit has
     *  no serialized entry (a nested unit). */
    val serializedCrc: Int get() = crcs[key(SERIALIZED)] ?: 0

    /** A raw entry of this unit (unit.index ... unit.dispatch), a fresh
     *  duplicate at position 0. */
    fun entry(unitEntryName: String): ByteBuffer? = entries[key(unitEntryName)]?.duplicate()

    fun nested(id: String): UnitStore? {
        if (id !in header.nestedIds) return null
        return nestedStores.computeIfAbsent(id) { UnitStore(name, entries, crcs, NESTED_DIR + it) }
    }
```

`CompilationUnit.kt`, after `serializedBlob()`:
```kotlin
    /** The serialized context's stamp: the artifact's CRC32 of the entry the
     *  blob came from, so a persisted dispatch slot can tell an SC of one
     *  build from the same handle in another. 0 for a unit that is not an
     *  artifact (its SC, if any, is built in this process). */
    open fun serializedStamp(): Int = 0
```

`ProgramUnit.kt`, after `serializedBlob`:
```kotlin
    override fun serializedStamp(): Int = store.serializedCrc
```

`SerializationContext.kt`, after `description`:
```kotlin
    /* The artifact stamp (UnitStore.serializedCrc) this SC was deserialized
     * under; 0 for an SC built in this process (the bootstrap, a compile in
     * progress). DispatchSlot persists it per referenced handle and restore
     * drops a slot whose stamp disagrees. */
    @JvmField var stamp: Int = 0
```

`Ops.kt`, in `deserialize`, the `if (blob == null)` branch becomes:
```kotlin
        if (blob == null) {
            binaryBlob = cu.serializedBlob()
                ?: throw ExceptionHandling.dieInternal(tc, "unit ${cu.unitId()} has no serialized context to deserialize")
            sc.stamp = cu.serializedStamp()
        }
        else
```

- [ ] **Step 4: Run the tests**

Run: `./nqp/gradlew -p nqp :nqp-runtime:test`
Expected: BUILD SUCCESSFUL, the new test passes, all 65 + 1 tests green.

- [ ] **Step 5: Commit (nqp tree)**

```bash
git -C nqp add src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ZipDirectory.kt src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitStore.kt src/vm/jvm/runtime/org/raku/nqp/runtime/CompilationUnit.kt src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationContext.kt src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitStoreTest.kt
GIT_AUTHOR_DATE='2026-09-16T19:30:00+0200' GIT_COMMITTER_DATE='2026-09-16T19:30:00+0200' git -C nqp commit -F - <<'EOF'
Unit loader: an SC deserialized from an artifact carries the entry's CRC32 as its stamp (milestone 8, B-pre)

The zip directory already reads offset and size per entry; the CRC32
sits in the same central-directory record, so the stamp costs no
hashing at load and changes no format. UnitStore exposes it for the
serialized entry, ProgramUnit hands it to the deserialize op, and the
SerializationContext keeps it; an SC built in this process stays 0.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
```

---

### Task 2: stamps in the slot, schema 2, drop on mismatch

**Files:**
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlot.kt:13,56-77`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlotCodec.kt:23-92` (the persist half)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt:62-66,113-140,275-289`
- Modify: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt:648`
- Modify: `docs/superpowers/specs/2026-09-16-jvm-milestone-8-phase-b-promotion-campaign-design.md` (section 1, Revision 1 note)
- Test: `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchSlotCodecTest.kt`, `.../DispatchPersistTest.kt`

**Interfaces:**
- Consumes: `SerializationContext.stamp` (Task 1).
- Produces: `@Serializable class PStamp(val handle: String, val stamp: Int)`; `DispatchSlot(schema: Int, programs: List<PProgram>, stamps: List<PStamp>)` with `SCHEMA = 2`; `DispatchSlotCodec.persist(p: DispatchProgram, stamps: MutableMap<String, Int>? = null): PProgram?`; `DispatchSlotCodec.ref(obj, stamps = null)` / `ref(st, stamps = null)`; `DispatchPersist.staleStamp: AtomicLong`; the token ` staleStamp=N` on the `dispatch stats:` line.

**Design note (spec Revision 1).** The spec's section 1 says a reference into an unstamped SC is unpersistable. That would drop every program that guards on a bootstrap type (`__6MODEL_CORE__` is built in-process, stamp 0), which is most of them. Ruling: stamp 0 is recorded and compared like any other value; an in-process SC matches only an in-process SC of the same handle. Bootstrap drift across runtime-jar rebuilds stays covered by the training stamp's hard dependency on both runtime jars (`Makefile.in:193`). Step 7 writes this into the spec.

- [ ] **Step 1: Write the failing tests**

`DispatchSlotCodecTest.kt`: update the round-trip helper's constructor call and add one test.

```kotlin
        val bytes = UnitCodec.encode(DispatchSlot.serializer(), DispatchSlot(DispatchSlot.SCHEMA, listOf(persisted), emptyList()))
```
```kotlin
    /** The record side names, per SC handle, the stamp the SC was loaded
     *  under; the bootstrap's SC is built in-process, so its stamp is 0 and
     *  it is still named (a 0 matches only another in-process SC). */
    @Test fun persistNamesTheStampOfEverySCItReferences() {
        val tc = ProgramUnitTestSupport.tc()
        val stamps = LinkedHashMap<String, Int>()
        assertNotNull(DispatchSlotCodec.persist(program(tc), stamps))
        val core = assertNotNull(tc.gc.KnowHOW!!.sc)
        assertEquals(0, core.stamp, "an in-process SC is unstamped")
        assertEquals(mapOf(core.handle to 0), stamps)
    }
```

`DispatchPersistTest.kt`: update the two existing constructor calls (lines 37 and 64) to pass `emptyList()` as the third argument, extend the record test, and add the stamp test.

In `recordAtExitWritesTheInstalledProgramsIntoTheArtifact`, after `assertEquals(1, decoded.programs.size)`:
```kotlin
        val core = knowhow.sc!!
        assertEquals(listOf(core.handle to core.stamp), decoded.stamps.map { it.handle to it.stamp },
            "the slot names the stamp of the SC its program references")
```

New test:
```kotlin
    /** A slot's stamps against the loaded SCs: agreeing restores; a
     *  disagreeing one is the cross-build hazard (the same handle, another
     *  content, shifted indexes) and the whole slot is dropped as staleStamp;
     *  a handle this process has not loaded is not a stamp question, its
     *  programs drop one by one in realise as they always did. */
    @Test fun aSlotWhoseStampDisagreesWithTheLoadedScIsTreatedAsEmpty() {
        val tc = ProgramUnitTestSupport.tc()
        val knowhow = tc.gc.KnowHOW!!
        val core = knowhow.sc!!
        val csd = CallSiteDescriptor(byteArrayOf(CallSiteDescriptor.ARG_OBJ), null)
        val p = DispatchProgram(csd, listOf(Guard.OfType(ValueSource.Arg(0), knowhow.st)),
            Outcome.Value(ValueSource.Arg(0)), emptyList(), ResumeKind.NONE, emptyList(), null)
        fun slot(vararg stamps: PStamp) = UnitCodec.encode(DispatchSlot.serializer(),
            DispatchSlot(DispatchSlot.SCHEMA, listOf(DispatchSlotCodec.persist(p)!!), stamps.toList()))
        val site = DispatchCallSite(MethodType.methodType(Void.TYPE))
        site.programIndex = 0; site.ordinal = 1

        DispatchPersist.register("/x/fixture.jar!unit-stamp-ok", storeWith(slot(PStamp(core.handle, core.stamp))))
        site.unitNamespace = "/x/fixture.jar!unit-stamp-ok"
        assertEquals(1, DispatchPersist.restore(tc, site).size, "an agreeing stamp restores")

        val stale = DispatchPersist.staleStamp.get(); val restored = DispatchPersist.restored.get()
        DispatchPersist.register("/x/fixture.jar!unit-stamp-bad", storeWith(slot(PStamp(core.handle, core.stamp + 1))))
        site.unitNamespace = "/x/fixture.jar!unit-stamp-bad"
        assertTrue(DispatchPersist.restore(tc, site).isEmpty(), "a disagreeing stamp drops the slot")
        assertEquals(stale + 1, DispatchPersist.staleStamp.get())
        assertEquals(restored, DispatchPersist.restored.get())

        DispatchPersist.register("/x/fixture.jar!unit-stamp-gone", storeWith(slot(PStamp("no-such-sc", 7))))
        site.unitNamespace = "/x/fixture.jar!unit-stamp-gone"
        assertEquals(1, DispatchPersist.restore(tc, site).size, "an unloaded SC is not a stamp mismatch")
        assertEquals(stale + 1, DispatchPersist.staleStamp.get())
    }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.dispatch.*'`
Expected: compilation FAILS (`PStamp`, three-argument `DispatchSlot`, `persist(p, stamps)`, `staleStamp` unresolved).

- [ ] **Step 3: The slot model**

`DispatchSlot.kt`: add after `PRef`:
```kotlin
/** One SC the slot's programs reference, with the stamp
 *  (SerializationContext.stamp) it was loaded under when recorded. */
@Serializable class PStamp(val handle: String, val stamp: Int)
```
and change the slot class:
```kotlin
@Serializable class DispatchSlot(val schema: Int, val programs: List<PProgram>, val stamps: List<PStamp>) {
```
In the `SCHEMA` KDoc, before `const val SCHEMA`, add a paragraph:
```kotlin
         *
         * Schema 2 (milestone 8, Phase B): [stamps], one per SC handle the
         * programs reference. Restore drops the slot when a stamp disagrees
         * with the SC this process loaded under that handle -- a slot trained
         * against one build of an artifact must not bind into another.
```
and `const val SCHEMA = 2`.

- [ ] **Step 4: The codec collects stamps**

`DispatchSlotCodec.kt`, persist half. Replace `persist`, `program`, both `ref`s, `literal`, `source`, `guard`, `shape`, `outcome` with:

```kotlin
    /** [stamps], when given, collects the stamp of every SC a persisted
     *  reference names (DispatchSlot.stamps); a program that turns out
     *  unpersistable may have added to it, so the caller keeps a map per
     *  program and merges on success. */
    fun persist(p: DispatchProgram, stamps: MutableMap<String, Int>? = null): PProgram? =
        try { program(p, stamps) } catch (_: Unpersistable) { null }

    private fun program(p: DispatchProgram, stamps: MutableMap<String, Int>?): PProgram = PProgram(
        descriptor(p.descriptor), p.guards.map { guard(it, stamps) }, outcome(p.outcome, stamps),
        p.resumptions.map { PResumption(it.dispatcher.id, shape(it.initArgs, stamps)) },
        p.resumeKind,
        p.resumeLevels.map { l ->
            PLevel(l.dispatcher.id, descriptor(l.initDescriptor), l.guards.map { guard(it, stamps) },
                l.newState?.let { source(it, stamps) }, l.requireNoFurther) },
        p.bindControl?.let { PBind(it.failureFlag, it.successFlag, it.onSuccessToo) },
        p.bindFailureProgram?.let { program(it, stamps) })
```
(`descriptor`, `typeName`, `objectIndex`, `codeIndex` unchanged.)
```kotlin
    private fun stamped(sc: SerializationContext, r: PRef, stamps: MutableMap<String, Int>?): PRef {
        stamps?.put(sc.handle, sc.stamp)
        return r
    }

    fun ref(obj: SixModelObject?, stamps: MutableMap<String, Int>? = null): PRef? {
        if (obj == null) return null
        val sc = obj.sc ?: throw Unpersistable("object of ${typeName(obj)} in no SC")
        val oi = objectIndex(sc, obj)
        if (oi >= 0) return stamped(sc, PRef(sc.handle, oi, PRef.OBJ), stamps)
        val ci = codeIndex(sc, obj)
        if (ci >= 0) return stamped(sc, PRef(sc.handle, ci, PRef.CODE), stamps)
        throw Unpersistable("object of ${typeName(obj)} not in the root set of ${sc.handle}")
    }

    fun ref(st: STable?, stamps: MutableMap<String, Int>? = null): PRef? {
        if (st == null) return null
        val sc = st.sc ?: throw Unpersistable("STable ${st.debugName} in no SC")
        val i = try { sc.getSTableIndex(st) } catch (_: NullPointerException) { -1 }
        if (i >= 0 && i < sc.stableCount() && sc.getSTable(i) === st) return stamped(sc, PRef(sc.handle, i, PRef.STABLE), stamps)
        throw Unpersistable("STable ${st.debugName} not in the root set of ${sc.handle}")
    }

    private fun literal(kind: ArgKind, value: Any?, stamps: MutableMap<String, Int>?): PLiteral = when (kind) {
        ArgKind.OBJ -> PLiteral(kind, ref(value as SixModelObject?, stamps), 0, 0.0, null)
        ArgKind.INT, ArgKind.UINT -> PLiteral(kind, null, (value as Number).toLong(), 0.0, null)
        ArgKind.NUM -> PLiteral(kind, null, 0, (value as Number).toDouble(), null)
        ArgKind.STR -> PLiteral(kind, null, 0, 0.0, value as String?)
    }

    private fun source(s: ValueSource, stamps: MutableMap<String, Int>?): PSource = when (s) {
        is ValueSource.Arg -> PArg(s.index)
        is ValueSource.ResumeInitArg -> PResumeInitArg(s.level, s.index)
        is ValueSource.Literal -> literal(s.kind, s.value, stamps)
        is ValueSource.Attribute -> PAttribute(source(s.from, stamps), ref(s.classHandle, stamps), s.name, s.kind)
        is ValueSource.How -> PHow(source(s.from, stamps))
        is ValueSource.Unbox -> PUnbox(source(s.from, stamps), s.kind)
        is ValueSource.Lookup -> PLookup(source(s.table, stamps), source(s.key, stamps))
        is ValueSource.ResumeState -> PResumeState(s.level)
    }

    private fun guard(g: Guard, stamps: MutableMap<String, Int>?): PGuard = when (g) {
        is Guard.OfType -> PGuardType(source(g.on, stamps), ref(g.type, stamps))
        is Guard.Concreteness -> PGuardConcreteness(source(g.on, stamps), g.concrete)
        is Guard.Literal -> PGuardLiteral(source(g.on, stamps), literal(g.expected.kind, g.expected.value, stamps))
        is Guard.NotLiteralObj -> PGuardNotLiteralObj(source(g.on, stamps), ref(g.rejected, stamps))
        is Guard.OfHll -> PGuardHll(source(g.on, stamps), g.hll?.name, g.hll?.compilerSide ?: false)
    }

    private fun shape(c: CaptureShape, stamps: MutableMap<String, Int>?) =
        PShape(c.sources.map { source(it, stamps) }, descriptor(c.descriptor))

    private fun outcome(o: Outcome, stamps: MutableMap<String, Int>?): POutcome = when (o) {
        is Outcome.Value -> POutcomeValue(source(o.source, stamps))
        is Outcome.InvokeCode -> POutcomeInvoke(source(o.callee, stamps), shape(o.args, stamps))
        is Outcome.InvokeSyscall -> POutcomeSyscall(o.syscall.name, shape(o.args, stamps))
    }
```
`DispatchDump.kt:60,69` keep calling `ref(obj)` / `ref(st)` through the default.

- [ ] **Step 5: Restore checks, record collects**

`DispatchPersist.kt`: after `staleSchema`:
```kotlin
    /** Slots dropped because a referenced SC's stamp (SerializationContext.stamp)
     *  is not the one the slot was recorded under: the same handle, another
     *  build of the artifact. */
    @JvmField val staleStamp = AtomicLong()
```
In `restore`, right after the `slot` decode and before `val onDrop`:
```kotlin
        /* Every SC the slot names must be the one it was recorded against.
         * A handle this process has not loaded is not a stamp question: its
         * programs drop one by one in realise, as they always did. */
        for (s in slot.stamps) {
            val sc = tc.gc.scs[s.handle] ?: continue
            if (sc.stamp != s.stamp) {
                staleStamp.incrementAndGet()
                if (TRACE) System.err.println("dispatch-persist: stale stamp ${s.handle} recorded=${s.stamp} loaded=${sc.stamp} at ${site.identity}")
                return emptyList()
            }
        }
```
In `recordAtExit(selector)`, the per-slot loop becomes:
```kotlin
                        for ((slot, byText) in perSlot) {
                            val persisted = ArrayList<PProgram>()
                            val stamps = LinkedHashMap<String, Int>()
                            for (p in byText.values) {
                                val mine = LinkedHashMap<String, Int>()
                                val pp = try { DispatchSlotCodec.persist(p, mine) }
                                         catch (t: Throwable) {
                                             failed++
                                             System.err.println("dispatch-record: FAILED program $path!$prefix#$slot: ${reason(t)}")
                                             null
                                         }
                                if (pp == null) pathUnpersistable++
                                else if (persisted.size < Dispatch.MAX_PROGRAMS) { persisted.add(pp); stamps.putAll(mine) }
                            }
                            if (persisted.isEmpty()) continue
                            m[slot] = UnitCodec.encode(DispatchSlot.serializer(),
                                DispatchSlot(DispatchSlot.SCHEMA, persisted, stamps.map { PStamp(it.key, it.value) }))
                            pathSlots++; pathPrograms += persisted.size
                        }
```
`NqpDispatch.kt:648`: after `" staleSchema=" + DispatchPersist.staleSchema +` add `" staleStamp=" + DispatchPersist.staleStamp +`.

- [ ] **Step 6: Run the tests**

Run: `./nqp/gradlew -p nqp :nqp-runtime:test`
Expected: BUILD SUCCESSFUL, all green (67 + 2 = 69 tests, the two new ones and the extended record test included).

- [ ] **Step 7: Spec Revision 1**

In the Phase B spec, section 1, replace the sentence "A reference into an SC that has no stamp is unpersistable on the record side, so restore never meets an unstamped handle." with:

> A reference into an in-process SC (the bootstrap `__6MODEL_CORE__`, a compile in progress) records stamp 0 and matches only a stamp 0 under the same handle; bootstrap drift across a runtime-jar rebuild stays covered by the training stamp's hard dependency on both runtime jars. (Revision 1, 2026-09-16: the first wording would have dropped every program guarding on a bootstrap type.)

- [ ] **Step 8: Commit (both trees)**

```bash
git -C nqp add src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlot.kt src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlotCodec.kt src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchSlotCodecTest.kt nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchPersistTest.kt
GIT_AUTHOR_DATE='2026-09-16T19:50:00+0200' GIT_COMMITTER_DATE='2026-09-16T19:50:00+0200' git -C nqp commit -F - <<'EOF'
Dispatch: a persisted slot names the stamp of every SC it references; a mismatch drops it (milestone 8, B-pre)

The cross-build hazard from Phase A's close: a slot trained against one
build of rakudo.jar restored while the settings compile on another --
same handles, shifted indexes, a baked callee bound to a different code
object. Slot schema 1 -> 2 (every old slot retrains once); the codec
collects one stamp per handle through its reference helpers; restore
compares against the loaded SC and counts staleStamp= on the stats
line. An in-process SC records stamp 0 and matches only stamp 0.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
git add docs/superpowers/specs/2026-09-16-jvm-milestone-8-phase-b-promotion-campaign-design.md
GIT_AUTHOR_DATE='2026-09-16T19:52:00+0200' GIT_COMMITTER_DATE='2026-09-16T19:52:00+0200' git commit -F - <<'EOF'
Docs: Phase B spec Revision 1 -- an in-process SC stamps as 0, and is still named

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
```

---

### Task 3: the order-only runtime jar and the two Phase A parkings

**Files:**
- Modify: `tools/templates/jvm/Makefile.in:116-121` (rakudo tree)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchRecord.kt:551-556`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchBootstrap.kt:116-132`
- Test: `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/GuardStateTest.kt`

**Interfaces:** none new. `DispatchCallSite.programs` is read by the test; `Dispatch.MAX_PROGRAMS` (= 32) and `STable.republish()` exist.

- [ ] **Step 1: Write the test for parking 2**

Add to `GuardStateTest.kt` (it has `freshType(tc)`, `ProgramUnitTestSupport`, `CallSiteDescriptor` imported; add `import java.lang.invoke.MethodType` and `import kotlin.test.assertEquals`):

```kotlin
    /** A site at its program cap whose programs all went stale sheds them
     *  on the next install, whether or not the install itself fits: the
     *  filtered array is written back, not only used to decide the add. */
    @Test fun aSaturatedSiteShedsItsStaleProgramsOnTheNextInstall() {
        val tc = ProgramUnitTestSupport.tc()
        val stale = freshType(tc)
        val csd = CallSiteDescriptor(byteArrayOf(CallSiteDescriptor.ARG_OBJ), null)
        fun over(t: SixModelObject) = DispatchProgram(csd, listOf(Guard.OfType(ValueSource.Arg(0), t.st)),
            Outcome.Value(ValueSource.Arg(0)), emptyList(), ResumeKind.NONE, emptyList(), null)
        val site = DispatchCallSite(MethodType.methodType(Void.TYPE))
        repeat(Dispatch.MAX_PROGRAMS) { site.install(over(stale)) }
        assertEquals(Dispatch.MAX_PROGRAMS, site.programs.size)
        stale.st.republish()
        assertTrue(site.programs.all { !it.isFresh })
        site.install(over(freshType(tc)))
        assertEquals(1, site.programs.size, "the stale programs were shed and the fresh one installed")
        assertTrue(site.programs.single().isFresh)
    }
```
This test passes on the current code too (the add path already writes the filtered array when the add fits); it pins the invariant the write-back below extends to the case where the add does not fit. Record that in the ledger: it is a guard, not a red-first test.

- [ ] **Step 2: Run it**

Run: `./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.dispatch.GuardStateTest'`
Expected: PASS (see the note above).

- [ ] **Step 3: Parking 2, the write-back**

`DispatchBootstrap.kt`, `install`:
```kotlin
    fun install(program: DispatchProgram) {
        /* A program whose type guard's state was republished can never match
         * again: drop it, so a republish does not spend the site's program
         * budget (MAX_PROGRAMS) on dead entries. The filtered array is written
         * back on its own, so a site at the cap sheds its dead entries even
         * when this install does not fit. */
        var current = programs
        /* `any` first, then `filter`: the common case is that nothing went
         * stale, and the scan answers it without allocating a new array. */
        if (current.any { !it.isFresh }) {
            current = current.filter { it.isFresh }.toTypedArray()
            programs = current
        }
        if (current.size < Dispatch.MAX_PROGRAMS) {
            programs = current + program
            /* A hot site stays compiled as its cache grows; a cold one waits
             * for the dispatch entry to see it cross the threshold. */
            if (chain != null || heat >= DispatchCompiler.threshold)
                recompile()
        }
    }
```

- [ ] **Step 4: Parking 1, never overwrite a capture with null**

`DispatchRecord.kt`, `emitGuards`, the literal branch:
```kotlin
        if (guards.literal) {
            /* A literal guard says everything a type or concreteness guard
             * would have said. Its constructor captured the value's state;
             * a recorded state replaces that only when there is one (the
             * OfType branch has the same rule). */
            val guard = Guard.Literal(source, value)
            if (value.kind == ArgKind.OBJ && value.value is SixModelObject && guards.state != null)
                guard.state = guards.state
            into.add(guard)
        }
```
No red-first test: the null path needs a tracked object whose `stInitialized` is false, which the test support cannot build cheaply. The existing `GuardStateTest` cases on identity guards are the regression check. Record as a ruling.

- [ ] **Step 5: The Makefile template**

`tools/templates/jvm/Makefile.in`, lines 116-121, become:
```make
# Both runtime jars sit after the | : order-only, GNU make syntax. A jar
# must be fresh before any build JVM runs on it, but its rebuild (seconds)
# must not timestamp-cascade into a full setting recompile (many minutes)
# -- compiled bytecode does not depend on the runtime that executes it.
# The training stamp keeps its hard dependency on both (a runtime edit
# retrains), see TRAIN_STAMP below. User decision 2026-09-16 (milestone 8
# Phase B): rakudo-runtime.jar joined nqp-runtime.jar on this side.
@bpv(RAKUDO_DEPS_EXTRA)@ = | $(RUNTIME_JAR) $(NQP_RUNTIME_JAR)
```

- [ ] **Step 6: Regenerate the Makefile and run the runtime tests**

Run (rakudo tree): `perl Configure.pl --backends=jvm --gen-nqp` through the watcher:
```bash
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/455b5a91/tmp/configure-b-pre.log --show='BUILD' --show='Makefile' -- perl Configure.pl --backends=jvm --gen-nqp
```
Expected: the Makefile is rewritten; `grep -n 'RAKUDO_DEPS_EXTRA\|^J_RAKUDO_DEPS_EXTRA' Makefile` shows the `| rakudo-runtime.jar` form. Then `./nqp/gradlew -p nqp :nqp-runtime:test` → all green (70 tests).

- [ ] **Step 7: Commit (both trees)**

```bash
git -C nqp add src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchRecord.kt src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchBootstrap.kt nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/GuardStateTest.kt
GIT_AUTHOR_DATE='2026-09-16T20:05:00+0200' GIT_COMMITTER_DATE='2026-09-16T20:05:00+0200' git -C nqp commit -F - <<'EOF'
Dispatch: the two Phase A parkings -- a literal guard keeps its capture, a saturated site sheds its dead programs (milestone 8, B-pre)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
git add tools/templates/jvm/Makefile.in
GIT_AUTHOR_DATE='2026-09-16T20:07:00+0200' GIT_COMMITTER_DATE='2026-09-16T20:07:00+0200' git commit -F - <<'EOF'
Build: rakudo-runtime.jar is an order-only prerequisite of rakudo.jar (milestone 8, B-pre)

User decision 2026-09-16: bytecode does not depend on the runtime that
executes it, the argument nqp's runtime jar already rests on. A Rakudo
runtime edit now costs a jar rebuild and a retrain, not a setting
recompile; the training stamp keeps its hard dependency on both jars.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
```

---

### Task 4: the op census (`NQP_OP_CENSUS=1`)

**Files:**
- Create: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpCensus.kt`
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java:213-219,230-238`
- Modify: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt:76-104,136,218,292,446,488,608,720,798,370-391`
- Test: `nqp/t/jvm/20-op-census.t` (NEW)

**Interfaces:**
- Consumes: `NqpOps.OP_COUNT`, `NqpOps.ClassLibSite.cls/meth` (same package), the `OP_*` int constants of `NqpOps` by reflection.
- Produces: `object NqpCensus { @JvmField val ON: Boolean; class SiteStats; fun stats(name): SiteStats; fun table(id: Int); fun classlib(site: NqpOps.ClassLibSite); fun call(s: SiteStats); fun miss(s: SiteStats, pinned: Boolean); fun republished(s: SiteStats); fun slow(s: SiteStats, path: String) }`; `NqpTypeOps.Site.stats: NqpCensus.SiteStats`. Batch 1's sites (next plan) call `call`/`slow` with paths such as `"method"` and `"nonauth"`.
- Output contract (parsed by Task 5 and by the `.t`):
  ```
  op census: table=N classlib=N siteCalls=N siteMisses=N
    table <count> <name>
    classlib <count> <Cls.meth>
    site <SiteClass> calls=N misses=N pins=N republished=N slow=[k=N ...]
  ```

- [ ] **Step 1: Write the failing test**

`nqp/t/jvm/20-op-census.t`:
```perl
# Milestone 8 Phase B, B0: the op census. NQP_OP_CENSUS=1 counts every
# table op by id, every classlib op by name and every site's calls and
# misses, printed at exit next to the dispatch stats. The knob is a static
# final read once per JVM, so the test runs CHILD processes with and
# without it and reads their stderr; the routing facts it asserts on are
# the ones batch 1's site tests will assert on the same way.

plan(6);

my class Queue is repr('ConcBlockingQueue') { }
my class VMDecoder is repr('Decoder') { }
my sub create_buf($type) {
    my $buf := nqp::newtype(nqp::null(), 'VMArray');
    nqp::composetype($buf, nqp::hash('array', nqp::hash('type', $type)));
    $buf
}

# Runs ./nqp-j-gradle -e $code as a child under %env; returns its stderr.
# (prove runs this file with cwd = the nqp tree, where ./nqp-j-gradle is.)
sub child-stderr($code, %env) {
    my $queue := nqp::create(Queue);
    my $done := 0; my $out-eof := 0; my $err-eof := 0;
    my @err;
    my $config := nqp::hash(
        'done', -> $status { $done := 1 },
        'ready', -> $stdin?, $stdout?, $stderr? { },
        'stdout_bytes', -> $seq, $data, $err { $out-eof := 1 unless nqp::isconcrete($data) },
        'stderr_bytes', -> $seq, $data, $err {
            if nqp::isconcrete($data) { @err[$seq] := $data } else { $err-eof := 1 }
        },
        'buf_type', create_buf(uint8));
    my $task := nqp::spawnprocasync($queue, './nqp-j-gradle', nqp::list('./nqp-j-gradle', '-e', $code),
                                    nqp::cwd(), %env, $config);
    nqp::permit($task, 1, -1);
    nqp::permit($task, 2, -1);
    while !$done || !$out-eof || !$err-eof {
        if nqp::shift($queue) -> $t {
            if nqp::islist($t) { my $cb := nqp::shift($t); $cb(|$t) } else { $t() }
        }
    }
    my $dec := nqp::create(VMDecoder);
    nqp::decoderconfigure($dec, 'utf8', nqp::hash());
    for @err -> $bytes { nqp::decoderaddbytes($dec, $bytes) if nqp::isconcrete($bytes) }
    nqp::decodertakeallchars($dec)
}

# One program exercising all three roads 1000 times: a table op
# (tryfindmethod is the one batch-1 op with an encoder row), a classlib op
# (findmethod arrives by name), and a site (istype, Phase A's).
my $code := 'my $i := 0; my $n := 0; while $i < 1000 { $n := $n + nqp::istype($i, int); nqp::tryfindmethod(NQPMu, "new"); nqp::findmethod(NQPMu, "new"); $i++ }; say($n)';

my %on := nqp::getenvhash();
%on<NQP_OP_CENSUS> := '1';
my $err := child-stderr($code, %on);

ok(nqp::index($err, 'op census: table=') >= 0, 'the census block prints at exit under NQP_OP_CENSUS=1');

sub count-of($text, $prefix, $name) {
    # "  <prefix> <count> <name>" -> count, or -1
    for nqp::split("\n", $text) -> $line {
        my $lead := '  ' ~ $prefix ~ ' ';
        if nqp::index($line, $lead) == 0 {
            my @f := nqp::split(' ', nqp::substr($line, nqp::chars($lead)));
            return +@f[0] if @f[1] eq $name;
        }
    }
    -1
}
ok(count-of($err, 'table', 'tryfindmethod') >= 1000, 'a table op is counted by id and printed by name');
ok(count-of($err, 'classlib', 'Ops.findmethod') >= 1000, 'a classlib op is counted by class and method name');

sub site-field($text, $site, $field) {
    for nqp::split("\n", $text) -> $line {
        if nqp::index($line, '  site ' ~ $site ~ ' ') == 0 {
            for nqp::split(' ', $line) -> $kv {
                return +nqp::substr($kv, nqp::chars($field) + 1) if nqp::index($kv, $field ~ '=') == 0;
            }
        }
    }
    -1
}
ok(site-field($err, 'IsTypeSite', 'calls') >= 1000, 'a site counts its calls');
ok(site-field($err, 'IsTypeSite', 'misses') >= 0, 'a site reports its misses');

my $quiet := child-stderr($code, nqp::getenvhash());
ok(nqp::index($quiet, 'op census:') < 0, 'without the knob nothing is printed');
```

- [ ] **Step 2: Run it to verify it fails**

Run: `( cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && prove --exec ./nqp-j-gradle t/jvm/20-op-census.t )`
Expected: tests 1-5 FAIL (no `op census:` block yet), test 6 passes.

- [ ] **Step 3: The census object**

`NqpCensus.kt`:
```kotlin
package org.raku.nqp.truffle

import com.oracle.truffle.api.CompilerDirectives.TruffleBoundary
import java.lang.reflect.Modifier
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.LongAdder

/**
 * The op census (milestone 8, Phase B): NQP_OP_CENSUS=1 counts every
 * table op by id, every classlib op by class and method name, and every
 * site's calls, misses, pins, republishes and named slow paths; printed
 * at exit next to the dispatch stats. [ON] is read once into a static
 * final, so a program compiled with it off carries no counter at all;
 * every bump sits behind a boundary, so with it on the counters cost a
 * call and never a deoptimization.
 *
 * Counts rank candidates; the JFR share (tools/build/jfr-attribute.raku
 * --ops) decides what is hot.
 */
object NqpCensus {
    @JvmField val ON: Boolean = System.getenv("NQP_OP_CENSUS") != null

    private val table = Array(NqpOps.OP_COUNT) { LongAdder() }
    private val classlib = ConcurrentHashMap<String, LongAdder>()

    /** One site class's counters. [slow] is keyed by the path a site names
     *  when it takes a slow road it could not fold (istrue.method,
     *  findmethod.nonauth). */
    class SiteStats(@JvmField val name: String) {
        @JvmField val calls = LongAdder()
        @JvmField val misses = LongAdder()
        @JvmField val pins = LongAdder()
        @JvmField val republished = LongAdder()
        @JvmField val slow = ConcurrentHashMap<String, LongAdder>()
    }

    /** The stats of an unrecorded site: counted, never printed. */
    @JvmField val NONE = SiteStats("none")
    private val sites = ConcurrentHashMap<String, SiteStats>()

    /** The counters for a site class, by simple name; [NONE] when off. */
    @JvmStatic fun stats(name: String): SiteStats = if (ON) sites.computeIfAbsent(name) { SiteStats(it) } else NONE

    @JvmStatic @TruffleBoundary fun table(id: Int) { table[id].increment() }

    @JvmStatic @TruffleBoundary fun classlib(site: NqpOps.ClassLibSite) {
        classlib.computeIfAbsent(site.cls.substringAfterLast('/').removeSuffix(";") + "." + site.meth) { LongAdder() }.increment()
    }

    @JvmStatic @TruffleBoundary fun call(s: SiteStats) { s.calls.increment() }
    @JvmStatic @TruffleBoundary fun miss(s: SiteStats, pinned: Boolean) { s.misses.increment(); if (pinned) s.pins.increment() }
    @JvmStatic @TruffleBoundary fun republished(s: SiteStats) { s.republished.increment() }
    @JvmStatic @TruffleBoundary fun slow(s: SiteStats, path: String) { s.slow.computeIfAbsent(path) { LongAdder() }.increment() }

    /** Table op names from NqpOps' own OP_* constants: no build-time
     *  resource, the same names the encoder's table uses (lower-cased,
     *  the arity suffix kept: substr2, substr3). */
    private val names: Map<Int, String> by lazy {
        val out = HashMap<Int, String>()
        for (f in NqpOps::class.java.declaredFields) {
            if (!Modifier.isStatic(f.modifiers) || f.type != Int::class.javaPrimitiveType) continue
            if (!f.name.startsWith("OP_") || f.name == "OP_COUNT") continue
            f.trySetAccessible()
            out[f.getInt(null)] = f.name.removePrefix("OP_").lowercase()
        }
        out
    }

    init {
        if (ON) Runtime.getRuntime().addShutdownHook(Thread { print() })
    }

    private fun print() {
        val tableTotal = table.sumOf { it.sum() }
        val classlibTotal = classlib.values.sumOf { it.sum() }
        val siteCalls = sites.values.sumOf { it.calls.sum() }
        val siteMisses = sites.values.sumOf { it.misses.sum() }
        System.err.println("op census: table=$tableTotal classlib=$classlibTotal siteCalls=$siteCalls siteMisses=$siteMisses")
        table.withIndex().filter { it.value.sum() > 0 }.sortedByDescending { it.value.sum() }.take(30)
            .forEach { System.err.println("  table " + it.value.sum() + " " + (names[it.index] ?: "op#${it.index}")) }
        classlib.entries.sortedByDescending { it.value.sum() }.take(30)
            .forEach { System.err.println("  classlib " + it.value.sum() + " " + it.key) }
        sites.values.sortedByDescending { it.calls.sum() }.forEach { s ->
            val slow = s.slow.entries.sortedByDescending { it.value.sum() }.joinToString(" ") { it.key + "=" + it.value.sum() }
            System.err.println("  site ${s.name} calls=${s.calls.sum()} misses=${s.misses.sum()} pins=${s.pins.sum()} republished=${s.republished.sum()} slow=[$slow]")
        }
    }
}
```

- [ ] **Step 4: The hooks**

`NqpRootNode.java`, `RunOp.doOp`: first statement inside the `try`:
```java
                if (NqpCensus.ON) NqpCensus.table(id);
```
`ClassLibOp.doCall`: first statement inside the `try`:
```java
                if (NqpCensus.ON) NqpCensus.classlib((NqpOps.ClassLibSite) site);
```

`NqpTypeOps.kt`, in `abstract class Site`, after the `state` field:
```kotlin
        /** The census counters of this site's class (NqpCensus.NONE when
         *  the knob is off, so the field is never null on the fast road). */
        @JvmField val stats: NqpCensus.SiteStats = NqpCensus.stats(javaClass.simpleName)
```
At the top of each of the eight site entry functions (`p6sink` :136, `hllize` :218, `decont` :292, `isconcrete` :446, `istype` :488, `p6typecheckrv` :608, `create` :720, `bigintArith` :798), as the first statement:
```kotlin
        if (NqpCensus.ON) NqpCensus.call(site.stats)
```
(`isconcrete` and `istype` delegate to inner `DecontSite`s, whose `decont` entry counts under `DecontSite` as well; the KDoc of `stats` says so.)

In `miss(site)`, after `if (misses >= MAX_MISSES) site.pin()`:
```kotlin
        if (NqpCensus.ON) NqpCensus.miss(site.stats, misses >= MAX_MISSES)
```
In `republished(site)`, after `site.misses = misses`:
```kotlin
        if (NqpCensus.ON) NqpCensus.republished(site.stats)
```

- [ ] **Step 5: Rebuild the runtime jars and run the test**

```bash
./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars
( cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && prove --exec ./nqp-j-gradle t/jvm/20-op-census.t )
```
Expected: 6/6. If test 4 reports fewer than 1000 `IsTypeSite` calls, `istype` on a native int operand may be constant-folded by the encoder; change the loop's `nqp::istype($i, int)` to `nqp::istype(NQPMu, NQPMu)` and record the ruling.

Also run `NQP_OP_CENSUS=1 RAKUDO_RAKUAST=1 ./rakudo-j -e 'say 1' 2>&1 | head -50` from the rakudo tree and eyeball the block; then `RAKUDO_RAKUAST=1 ./rakudo-j -e 'say 1'` prints nothing new.

- [ ] **Step 6: Commit (nqp tree)**

```bash
git -C nqp add nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpCensus.kt nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt t/jvm/20-op-census.t
GIT_AUTHOR_DATE='2026-09-16T20:30:00+0200' GIT_COMMITTER_DATE='2026-09-16T20:30:00+0200' git -C nqp commit -F - <<'EOF'
Engine: the op census -- NQP_OP_CENSUS=1 counts table ops, classlib ops and site traffic (milestone 8, B0)

Table ops by id at RunOp, classlib ops by class and method at
ClassLibOp, and per site class calls, misses, pins, republishes and
named slow paths; LongAdders behind boundaries, a static final knob so
a program compiled without it carries nothing; printed at exit. Names
for table ops come off NqpOps' own OP_* constants. t/jvm/20-op-census.t
reads child processes' stderr and is the assertable site counter the
Phase A ledger deferred to this phase.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
```

---

### Task 5: the tools read the census

**Files:**
- Modify: `tools/build/jfr-attribute.raku:14-24` (rakudo tree)
- Modify: `tools/build/m7-rig.raku:55-80,100-127,142-150` (rakudo tree)

**Interfaces:**
- Produces: `jfr-attribute.raku --ops` (implies `--innermost`, containers = the two generic entries, the sites, dispatch); `m7-rig.raku --census` (after the timed rows: one knob-on run and one JFR run per cold row, plus a second warm proxy with the knob; files `<tag>-<row>-census.err`, `<tag>-<row>.jfr`, `<tag>-<row>-jfr.txt`, `<tag>-sanity-census.log`); `m7-rig.raku --parse-census=FILE` prints the parsed totals.
- Consumes: the `op census:` output contract of Task 4.

- [ ] **Step 1: `--ops` on jfr-attribute**

In `MAIN`'s signature, after `Bool :$innermost = False,`:
```raku
    Bool :$ops = False,               #= per-op exclusive view: containers = the generic op entries, the sites, dispatch; implies --innermost
```
Then, after `@container ||= <...>;`, change it so `--ops` takes precedence:
```raku
    @container = <table=NqpOps.run classlib=NqpOps.classlib sites=NqpTypeOps dispatch=NqpDispatch> if $ops;
    my $inner = $innermost || $ops;
```
and replace the two uses of `$innermost` further down (`region` and `if $innermost`) with `$inner`.

Check: `raku tools/build/jfr-attribute.raku --ops /nonexistent.jfr` fails on the missing file, not on the arguments.

- [ ] **Step 2: `--census` and `--parse-census` on the rig**

`m7-rig.raku`: after `parse-cold`, add:
```raku
sub parse-census(Str $text) {
    my %r;
    if $text ~~ / 'op census: table=' (\d+) ' classlib=' (\d+) ' siteCalls=' (\d+) ' siteMisses=' (\d+) / {
        %r<table> = +$0; %r<classlib> = +$1; %r<site-calls> = +$2; %r<site-misses> = +$3;
    }
    %r<top-table> = $text.lines.grep(*.starts-with('  table ')).head(8).map({ .words[2] ~ '=' ~ .words[1] }).join(' ');
    %r<top-classlib> = $text.lines.grep(*.starts-with('  classlib ')).head(8).map({ .words[2] ~ '=' ~ .words[1] }).join(' ');
    %r
}

sub census-summary(%r) {
    "table={%r<table> // '-'} classlib={%r<classlib> // '-'} siteCalls={%r<site-calls> // '-'} siteMisses={%r<site-misses> // '-'} "
      ~ "top-table: {%r<top-table> || '-'} top-classlib: {%r<top-classlib> || '-'}"
}
```
Next to the other parse-only multis:
```raku
multi sub MAIN(Str :$parse-census!) { say census-summary(parse-census($parse-census.IO.slurp)) }
```
In the main `MAIN` signature, after `Int :$heap = 8,`:
```raku
    Bool :$census = False,      #= after the timed rows: one NQP_OP_CENSUS=1 run and one JFR run per cold row, and a second warm proxy with the knob
```
After the `for @bench` loop that fills `%row`, add:
```raku
    if $census {
        for @bench -> %b {
            my ($ctext, $ccode) = capture(%b<cmd>, :cwd(%b<cwd>), :env(%(|%cold, NQP_OP_CENSUS => '1')));
            $dir.add("$tag-%b<name>-census.err").spurt($ctext);
            die "%b<name> census: exit $ccode" unless $ccode == 0;
            die "%b<name> census: no 'op census:' marker" unless $ctext.contains('op census:');
            %row{%b<name> ~ '-census'} = parse-census($ctext);
            say "m7-rig: census %b<name> " ~ census-summary(%row{%b<name> ~ '-census'});
            my $jfr = $dir.add("$tag-%b<name>.jfr");
            my ($jtext, $jcode) = capture(%b<cmd>, :cwd(%b<cwd>),
                :env(%(|%base, JAVA_TOOL_OPTIONS => "-XX:FlightRecorderOptions=stackdepth=512 -XX:StartFlightRecording=filename=$jfr,settings=profile")));
            die "%b<name> jfr: exit $jcode" unless $jcode == 0;
            die "%b<name> jfr: no recording at $jfr" unless $jfr.e;
            my $attr = run 'raku', 'tools/build/jfr-attribute.raku', '--ops', $jfr, :cwd($ROOT), :out;
            $dir.add("$tag-%b<name>-jfr.txt").spurt($attr.out.slurp(:close));
            say "m7-rig: jfr %b<name> $jfr ({$jfr.s} bytes) -> $tag-%b<name>-jfr.txt";
        }
    }
```
In the warm phase's `'proxy'` arm, after the existing `say`, add:
```raku
            if $census {
                my ($ctext, $ccode) = capture(['raku', 'tools/build/evalserver-sweep.raku', '--chunk=*',
                                               '--jobs=1', "--heap=$heap", 't/01-sanity'],
                                              :cwd($ROOT), :env(%(|%base, NQP_OP_CENSUS => '1')));
                $dir.add("{$tag}-sanity-census.log").spurt($ctext);
                die "m7-rig: sanity census produced no 'op census:' block (exit $ccode)" unless $ctext.contains('op census:');
                say "m7-rig: census sanity " ~ census-summary(parse-census($ctext));
            }
```
(The eval server prints the block when it exits at the end of the sweep; the sweep's log carries the server's stderr. If the block is missing because the sweep discards server stderr, route it: check `tools/build/evalserver-sweep.raku` for where the server's stderr goes and add the file to the ruling.)

- [ ] **Step 3: Check the parser on a fixture**

Write `/home/longwalker/.claude/jobs/455b5a91/tmp/census-fixture.txt`:
```
dispatch stats: hits=1 misses=2
op census: table=1234 classlib=567 siteCalls=89 siteMisses=3
  table 900 tryfindmethod
  table 334 getattr
  classlib 500 Ops.findmethod
  classlib 67 Ops.istrue
  site IsTypeSite calls=89 misses=3 pins=0 republished=1 slow=[]
```
Run: `raku tools/build/m7-rig.raku --parse-census=/home/longwalker/.claude/jobs/455b5a91/tmp/census-fixture.txt`
Expected: `table=1234 classlib=567 siteCalls=89 siteMisses=3 top-table: tryfindmethod=900 getattr=334 top-classlib: Ops.findmethod=500 Ops.istrue=67`

- [ ] **Step 4: Commit (rakudo tree)**

```bash
git add tools/build/jfr-attribute.raku tools/build/m7-rig.raku
GIT_AUTHOR_DATE='2026-09-16T20:45:00+0200' GIT_COMMITTER_DATE='2026-09-16T20:45:00+0200' git commit -F - <<'EOF'
Tools: the rig takes the census and a JFR per cold row; jfr-attribute gets the per-op view (milestone 8, B0)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
```

---

### Task 6: the gate, rig row `b0`, the baseline census, the ledger

**Files:**
- Create: `docs/superpowers/plans/2026-09-16-jvm-milestone-8-phase-b.ledger.md` (rakudo tree)
- Modify: `docs/superpowers/plans/2026-09-16-jvm-milestone-8-type-state-phase-a.ledger.md` (one line: the two open items closed)

**Interfaces:** consumes everything above. Produces the B0 baseline column every batch row is compared against.

- [ ] **Step 1: Runtime jars, runtime JUnit, nqp suite**

```bash
./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars
./nqp/gradlew -p nqp :nqp-runtime:test
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/455b5a91/tmp/nqp-suite-b0.log --show='Files=' --show='Result' --stall=900 -- ./nqp/gradlew -p nqp testNqp
```
Expected: JUnit all green (70); nqp suite `Result: PASS` with the file count and wall time recorded (Phase A close: 156/156, ~200 s).

- [ ] **Step 2: The cross-build `make`**

HEAD moved in both trees, so `make` re-expands `gen/jvm/main-version.nqp`, rebuilds rakudo.jar and every setting on it while the nqp jars' slots (trained against the previous rakudo.jar) are restored: exactly the scenario that died at Phase A's close. Run it with the default `NQP_DISPATCH_PERSIST`:
```bash
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/455b5a91/tmp/make-b0.log --show='Compiling' --show='Generating' --show='dispatch-record' --show='Error' --stall=1200 -- make
```
Expected: the build completes; the training log line `dispatch-record: done` appears; no `Too few positionals`. Record wall time. Then:
```bash
RAKUDO_RAKUAST=1 NQP_DISPATCH_STATS=1 ./rakudo-j -e 'say 1' 2>&1 | grep -o 'staleSchema=[0-9]* staleStamp=[0-9]*'
```
Expected on this first run after the build: `staleStamp=0` (the build trained fresh slots under the current stamps). Note `staleSchema=` is 0 too since every slot was rewritten at schema 2. Also remove the stale precomp: `rm -rf lib/.precomp`.

- [ ] **Step 3: Verify mode, once**

```bash
RAKUDO_RAKUAST=1 NQP_DISPATCH_PERSIST=verify ./rakudo-j -e 'say 1' 2>&1 | grep 'dispatch-verify: matched'
```
Expected: `mismatched=0`. Record the four counters.

- [ ] **Step 4: Warm sanity**

```bash
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/455b5a91/tmp/sanity-b0.log --show='files in' --show='FAIL' --stall=600 -- raku tools/build/evalserver-sweep.raku --chunk='*' --jobs=1 --heap=8 t/01-sanity
```
Expected: 25/25, wall time recorded.

- [ ] **Step 5: Rig row `b0` with the census**

```bash
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/455b5a91/tmp/rig-b0.log --show='m7-rig:' --stall=900 -- raku tools/build/m7-rig.raku --tag=b0 --out=m7-rig --census
```
Expected: the row line (`| b0 | <hash-r> | <hash-n> | rakudo-e | nqp-e | misses | hits | <warm>/sanity | none | |`), two `m7-rig: census` lines, two `m7-rig: jfr` lines, one `m7-rig: census sanity` line, `m7-rig: DONE tag=b0`. The clocks are read against the Phase A row `a` (2.290 s) and the M7 close row (2.247 / 1.198): the stamp and the parking fixes are expected inside the spread.

- [ ] **Step 6: The CORE.c census**

One standalone CORE.c compile with the knob (the Makefile's own recipe, `Makefile:1348`, with the output redirected to the job dir so the build's jar is untouched):
```bash
RAKUDO_RAKUAST=1 NQP_OP_CENSUS=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/455b5a91/tmp/corec-census-b0.log --show='Stage' --show='op census' --stall=900 -- ./rakudo-j --setting=NULL.c --ll-exception --optimize=3 --target=jar --stagestats --output=/home/longwalker/.claude/jobs/455b5a91/tmp/CORE.c.census.jar gen/jvm/CORE.c.setting
```
Expected: the stage stats (record the wall time; M7 close CORE.c 296 s) and the `op census:` block at exit. Then one JFR run of the same command with `JAVA_TOOL_OPTIONS="-XX:FlightRecorderOptions=stackdepth=512 -XX:StartFlightRecording=filename=/home/longwalker/.claude/jobs/455b5a91/tmp/corec-b0.jfr,settings=profile"` (without the census knob) and `raku tools/build/jfr-attribute.raku --ops /home/longwalker/.claude/jobs/455b5a91/tmp/corec-b0.jfr > m7-rig/b0-corec-jfr.txt`. Copy the census block to `m7-rig/b0-corec-census.err`.

- [ ] **Step 7: The ledger**

Create `docs/superpowers/plans/2026-09-16-jvm-milestone-8-phase-b.ledger.md` with these sections, every number filled from the runs above:

```markdown
# Milestone 8, Phase B: the promotion campaign -- ledger

Spec: docs/superpowers/specs/2026-09-16-jvm-milestone-8-phase-b-promotion-campaign-design.md
Plan (opening + B0): docs/superpowers/plans/2026-09-16-jvm-milestone-8-phase-b-opening-and-census.md

## B-pre: the opening commit

Commits: nqp <hash> (stamp plumbing), nqp <hash> (slot schema 2), nqp <hash> (parkings),
rakudo <hash> (Makefile), rakudo <hash> (spec Revision 1).

Gate: runtime JUnit <n>/<n> <s> s; nqp suite <files> <s> s; make <s> s (cross-build scenario,
default persistence, passed); verify matched=<n> byOutcome=<n> mismatched=0 unseen=<n>;
sanity 25/25 <s> s; staleStamp=0 on the first run after the build.

Rulings:
- stamp 0 for in-process SCs is recorded and compared, not unpersistable (spec Revision 1; reason; cost if wrong).
- parking 2's test is a guard, not red-first (reason).
- parking 1 has no unit test (reason).
- <any deviation met during execution>

Phase A's two open items are closed here.

## B0: the census baseline

Rig row b0: <the row line>. Against M7 close (2.247 / 1.198) and row a (2.290): <inside/outside the spread>.

| workload | table | classlib | siteCalls | siteMisses | top table (8) | top classlib (8) |
| rakudo-e | ... |
| nqp-e | ... |
| sanity (server) | ... |
| CORE.c | ... |

JFR --ops exclusive shares, per workload: the "entry from interpreter" top 12 of each
(m7-rig/b0-<row>-jfr.txt, m7-rig/b0-corec-jfr.txt), with the 1 % line marked.

Per site class (calls / misses / pins / republished / slow) on rakudo-e: <table>.

Candidates at >= 1 % on any workload, before batch 1: <list with shares>. Batch 1 is fixed
by design (iscont, istrue/isfalse/Truthy, findmethod/tryfindmethod/can, the three arms); their
B0 shares are the "before" column of their rows.
```
In the Phase A ledger, under the last section, append one line: `Both open items closed in Phase B's opening commit (this ledger: 2026-09-16-jvm-milestone-8-phase-b.ledger.md, "B-pre").`

- [ ] **Step 8: Commit, push both trees to ab5tract**

```bash
git add docs/superpowers/plans/2026-09-16-jvm-milestone-8-phase-b.ledger.md docs/superpowers/plans/2026-09-16-jvm-milestone-8-type-state-phase-a.ledger.md m7-rig/b0.md m7-rig/rows.md
GIT_AUTHOR_DATE='2026-09-16T21:30:00+0200' GIT_COMMITTER_DATE='2026-09-16T21:30:00+0200' git commit -F - <<'EOF'
Docs: milestone 8 Phase B ledger -- the opening commit's gate, rig row b0, the baseline census

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
git push ab5tract HEAD
git -C nqp push ab5tract HEAD
```
(Check first whether `m7-rig/` is tracked: `git ls-files m7-rig | head -3`. If it is not, leave the row files out of the commit and paste the row line into the ledger only.)

---

## Self-review

**Spec coverage.** Section 1: stamp (Tasks 1-2), Makefile (Task 3), parkings (Task 3), tests and gate incl. the cross-build make, verify once, row b0 (Task 6). Section 2: knob and three counter families (Task 4), output with names (Task 4), JFR `--ops` (Task 5), rig `--census` with the warm proxy and the CORE.c census (Tasks 5-6), baseline in the ledger (Task 6). Section 5's per-commit gate and the b0 row (Task 6). Sections 3-4 (batch 1, census batches) are the next plan by design.

**Placeholders.** The ledger template in Task 6 Step 7 has `<...>` fields that are filled from measurements, not written by hand; that is the deliverable's shape, not a gap. Task 5 Step 2 names one conditional (where the eval server's stderr goes) with the file to check.

**Type consistency.** `ZipDirectory.Entry.crc: Int` → `UnitStore.crcs: Map<String, Int>` → `serializedCrc: Int` → `CompilationUnit.serializedStamp(): Int` → `SerializationContext.stamp: Int` → `PStamp.stamp: Int` and `DispatchSlot.stamps: List<PStamp>`; `persist(p, stamps: MutableMap<String, Int>?)` matches every call in Task 2 and the tests; `NqpCensus.SiteStats` is the type of `Site.stats` and the parameter of `call`/`miss`/`republished`/`slow`; the census output lines match `parse-census` and the `.t`'s parsers (`  table N name`, `  classlib N Cls.meth`, `  site Name calls=N ...`).
