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

