# Milestone 1 final-review fix wave -- report

nqp tree: `/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp`
Base: `2035d43e2` (jesp-direct-lazy-records) -> after this commit: `e2628a882`

## Fix 1: the backend's artifact road must not route around the writer's refusal

File: `src/vm/jvm/HLL/Backend.nqp`, `method classfile`.

Before:
```
if %adverbs<target> eq 'jar' && $jast.unit_road && !$jast.fallbacks {
    nqp::syscall('jvm-write-unit', $jast, %jastnodes, $unit_output);
}
else {
    nqp::compilejasttofile($jast, %jastnodes, %adverbs<output>);
}
```

After:
```nqp
            # The artifact road (NQP_UNIT): a jar-bound unit whose every
            # block encoded is written as programs + serialized context +
            # block table, no class file; any fallback body keeps the
            # class road. Compiler.nqp already dies at the fallback
            # junction when a unit-road unit has fallbacks, so that case
            # should never reach here -- but this must not be the place
            # that silently routes it to compilejasttofile anyway (that
            # class file would carry no program sidecar and no static
            # lexical values: a silently broken jar). Route every
            # unit-road unit to the writer regardless of fallbacks; the
            # writer's own fallbacks check is the refusal point, this is
            # defense.
            if %adverbs<target> eq 'jar' && $jast.unit_road {
                # The syscall's argument kinds are checked at the call
                # site; %adverbs<output> arrives boxed.
                my str $unit_output := %adverbs<output>;
                nqp::syscall('jvm-write-unit', $jast, %jastnodes, $unit_output);
            }
            else {
                nqp::compilejasttofile($jast, %jastnodes, %adverbs<output>);
            }
```

Verified the writer's refusal point still exists: `src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitWriter.kt`:
```
if (jc.fallbacks != 0)
    throw ExceptionHandling.dieInternal(tc, "jvm-write-unit: ${jc.className} has ${jc.fallbacks} bytecode fallback bodies")
```
so a unit-road unit with fallbacks now reaches the writer and dies with a named error, instead of silently falling to `compilejasttofile`.

## Fix 2: the end-to-end test must not pass on a stale jar

File: `t/nqp/123-unit-artifact.t`. Added, right after `$jar` is defined and the source module file (`spew($src, [...])`) is written, before the driver file is written and before the compile shell-out:

```nqp
    # A stale jar from a previous run must not let this test pass on old
    # output: the compile below must be the thing that produces it.
    nqp::unlink($jar) if nqp::stat($jar, nqp::const::STAT_EXISTS);
```

## Fix 3: document the custom_args sentinel in the wire doc

File: `nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpWire.java`, the `PARAMS` doc comment. Added:

```
 *    A header with n == 0 and accepted == -1 is the custom_args shape:
 *    the block binds its own arguments through the runtime Binder
 *    (P6BINDSIG/P6TRYBINDSIG) rather than declared params, so the reader
 *    skips the arity and extra-named checks on it. No other block shape
 *    produces this header, since accepted == -1 otherwise requires a
 *    positional slurpy, which is itself a param record (n >= 1).
```

Cross-checked against `nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java` (`params()`, around line 715-724 and 800), which already carries the same reasoning in its own comment and defines
`boolean customArgs = n == 0 && accepted == -1;`, used at line 800 to skip the extra-named rejection (`if (emit && !namedSlurpy && !customArgs) { ... }`). Doc-only change, no code touched.

## Fix 4: the in-memory unit sniff must be cheap on the class road

### (a)/(b) `src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitZip.kt`

- `write()` got a doc comment: "unit.meta is always the first entry written -- isUnit's sniff depends on this and reads only the first local file header."
- `isUnit(bytes: ByteArray)` rewritten to read only the first local file header: bytes 0-3 must be the local-header signature `0x50 0x4B 0x03 0x04`, file-name length is the little-endian u16 at offset 26, name starts at offset 30, and it answers `name == "unit.meta"`; any input shorter than 30+namelen bytes, or a bad signature, answers false. No `ZipInputStream`/`ZipEntry` walk.
- New overload `isUnit(buffer: ByteBuffer): Boolean` does the same 30+9-byte sniff via absolute `get(index)` calls on `buffer.duplicate()` -- no array copy, and the original buffer's position/limit/mark are untouched.
- Both share four `private const val LOCAL_SIG_0..3: Byte` constants for the signature bytes.

```kotlin
    @JvmStatic
    fun isUnit(bytes: ByteArray): Boolean {
        if (bytes.size < 30) return false
        if (bytes[0] != LOCAL_SIG_0 || bytes[1] != LOCAL_SIG_1 ||
            bytes[2] != LOCAL_SIG_2 || bytes[3] != LOCAL_SIG_3) return false
        val nameLen = (bytes[26].toInt() and 0xFF) or ((bytes[27].toInt() and 0xFF) shl 8)
        if (nameLen != META.length || bytes.size < 30 + nameLen) return false
        for (i in 0 until nameLen)
            if ((bytes[30 + i].toInt() and 0xFF) != META[i].code) return false
        return true
    }

    @JvmStatic
    fun isUnit(buffer: ByteBuffer): Boolean {
        val dup = buffer.duplicate()
        val base = dup.position()
        val remaining = dup.remaining()
        if (remaining < 30) return false
        if (dup.get(base) != LOCAL_SIG_0 || dup.get(base + 1) != LOCAL_SIG_1 ||
            dup.get(base + 2) != LOCAL_SIG_2 || dup.get(base + 3) != LOCAL_SIG_3) return false
        val nameLen = (dup.get(base + 26).toInt() and 0xFF) or ((dup.get(base + 27).toInt() and 0xFF) shl 8)
        if (nameLen != META.length || remaining < 30 + nameLen) return false
        for (i in 0 until nameLen)
            if ((dup.get(base + 30 + i).toInt() and 0xFF) != META[i].code) return false
        return true
    }
```

### (c) `src/vm/jvm/runtime/org/raku/nqp/runtime/LibraryLoader.java`, `load(ThreadContext, ByteBuffer)`

```java
    public static void load(ThreadContext tc, ByteBuffer buffer) {
        try {
            // The sniff reads the buffer directly (no copy): it is only the
            // first local file header's worth of bytes either way. Only the
            // artifact road needs a byte[] -- for loadJar (the class road)
            // the JarInputStream reads the buffer itself.
            if (org.raku.nqp.runtime.unit.UnitZip.isUnit(buffer)) {
                byte[] bytes;
                if (buffer.hasArray() && buffer.arrayOffset() == 0 && buffer.position() == 0
                        && buffer.array().length == buffer.remaining())
                    bytes = buffer.array();
                else {
                    bytes = new byte[buffer.remaining()];
                    buffer.duplicate().get(bytes);
                }
                try {
                    org.raku.nqp.runtime.unit.UnitLoader.loadAndRun(tc, bytes);
                }
                catch (ControlException e) { throw e; }
                catch (IllegalStateException | IllegalArgumentException e) {
                    throw ExceptionHandling.dieInternal(tc, e);
                }
            }
            else
                resolveClass(tc, loadJar(buffer, tc.gc.byteClassLoader));
        }
        catch (IOException | IllegalArgumentException | ClassNotFoundException e) {
            throw ExceptionHandling.dieInternal(tc, e);
        }
    }
```

Deliberate addition beyond the letter of the spec: the fast path also requires `buffer.array().length == buffer.remaining()`, not just offset==0/position==0. Without it, a hypothetical caller that hands in a buffer whose limit is short of its backing array's length would leak trailing garbage bytes into `UnitLoader.loadAndRun`, which wraps the array whole in a `ByteArrayInputStream`. Traced every caller of `LibraryLoader.load(tc, ByteBuffer)` (only `load(tc, byte[])`, called from `Ops.loadbytecodebuffer` via `VMArrayInstance_{i,u}8.slots`); that path always does `ByteBuffer.allocate(len); put(buffer); rewind()`, so `array().length == remaining()` always holds there today -- the extra check is inert on the only current caller and is a correctness guard against a future one.

### (d) New tests in `nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitFormatTest.kt`

Added five `@Test` methods:
- `writtenUnitSniffsTrue` -- a unit produced by `UnitZip.write` sniffs true.
- `unitMetaNotFirstIsNotSniffed` -- a hand-built zip (`ZipOutputStream`) whose first entry is `other.txt` and second is `unit.meta` sniffs **false**, documenting the first-entry rule.
- `classFileShapedBytesAreNotAUnit` -- a class-file-shaped byte array (magic + minor/major version + constant-pool-ish bytes, not just the bare 4-byte magic) sniffs false.
- `shortBytesAreNotAUnit` -- a 10-byte array sniffs false.
- `byteBufferSniffAgreesWithByteArraySniff` -- the `ByteBuffer` overload agrees with the `ByteArray` overload on a written unit, and leaves the buffer's position at 0 afterwards.

## Build and verify

### 1. Runtime + engine jars

```
cd nqp && ./gradlew :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars
```
`BUILD SUCCESSFUL in 7s` (12 actionable tasks: 7 executed, 5 up-to-date).

```
./gradlew :nqp-runtime:test
```
`BUILD SUCCESSFUL in 1s`. `nqp-runtime/build/test-results/test/TEST-org.raku.nqp.runtime.unit.UnitFormatTest.xml`:
`tests="10" skipped="0" failures="0" errors="0"` (5 pre-existing + 5 new, all green).

### 2. Stage build (Backend.nqp is NQP source -> `clean buildJvm`)

From the rakudo worktree root:
```
NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 NQP_CODE_STRICT=1 \
  raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/b945970f/tmp/build-fixwave.log \
  --show='> Task :stage' --show='BUILD' --show='rror' -- ./nqp/gradlew -p nqp clean buildJvm
```
Ran to completion in the foreground. Tail of the log:
```
[288s] BUILD SUCCESSFUL in 4m 48s
62 actionable tasks: 36 executed, 22 from cache, 4 up-to-date
=== EXIT=0 verdict=ok elapsed=288s ===
```

### 3. Per-jar check

Every jar under `nqp/build/jvm/stage2/` (10 jars) and `nqp/build/jvm/share/lib/` (11 jars, including `NQPP5QRegex.jar` which stage2 doesn't have): `unzip -l $j | awk '/unit.meta/{n++} END{print n+0}'` = **1**, and `.class`-entry count = **0**, for all 21 jars. Confirmed for: `ModuleLoader.jar`, `nqpmo.jar`, `NQPCORE.setting.jar`, `JASTNodes.jar`, `QASTNode.jar`, `QRegex.jar`, `NQPHLL.jar`, `QAST.jar`, `NQPP6QRegex.jar`, `nqp.jar` (both locations), plus `NQPP5QRegex.jar` (share/lib only).

`unzip -l nqp/build/jvm/share/lib/nqp.jar | head`:
```
Archive:  nqp/build/jvm/share/lib/nqp.jar
  Length      Date    Time    Name
---------  ---------- -----   ----
    67516  2026-09-09 15:35   unit.meta
    90877  2026-09-09 15:35   unit.programs
    74921  2026-09-09 15:35   unit.serialized.lz4
```
`unit.meta` is listed FIRST, as required.

### 4. Smoke + covering tests

```
RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'say(6*7)'
```
-> `42`

```
cd nqp && RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp-j-gradle t/nqp/123-unit-artifact.t
```
```
1..8
ok 1 - compiled the module on the artifact road
ok 2 - the jar carries unit.meta
ok 3 - the jar carries no class entry
ok 4 - a sub from the artifact runs
ok 5 - a closure over the mainline keeps its outer
ok 6 - a handler in an artifact block catches
ok 7 - a regex from the artifact matches
ok 8 - and fails to match
```
8/8.

```
cd nqp && RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp-j-gradle t/nqp/019-file-ops.t
```
112/112 `ok`, exit 0 (a cheap regression check on file/buffer ops around the LibraryLoader change; it does not exercise the class-road `ByteBuffer` load path).

`awk '/loadbytecodebuffer/{print FILENAME":"NR": "$0}' t/nqp/*.t` -> **no matches**. No `t/nqp/*.t` test drives `nqp::loadbytecodebuffer` / the class-road `LibraryLoader.load(tc, ByteBuffer)` path. That path (fix 4c) is exercised only indirectly (via the sniff being called on every module load, unit or class road) and directly only by the new Kotlin unit tests (fix 4d); it is **unverified at the Rakudo level**, per step 5 below.

### 5. Rakudo `make` -- deliberately not run

Per instructions: fixes 1-3 don't touch the class road's Rakudo build; fix 4's class-road path (the `ByteBuffer` ->`byte[]` fast path in `LibraryLoader.load`) has no covering `t/nqp/*.t` test (confirmed above), so it remains unverified on Rakudo. The Kotlin unit tests (fix 4d) and the nqp-level smoke/covering tests above are the extent of verification for this fix wave.

## Commit and push

```
commit e2628a8827c55dec1219c8bd2bf2022c9f787101 (jesp-direct-lazy-records)
Author: ab5tract <lonwalker@hey.com>

unit artifact: final-review fixes -- writer is the only refusal point on the unit road; first-entry sniff; stale-jar guard; PARAMS sentinel documented

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRn8gLyZjirBAKS6urb3n4

 nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitFormatTest.kt | 55 +++++++++++++
 nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpWire.java             |  6 ++
 src/vm/jvm/HLL/Backend.nqp                                              | 13 ++--
 src/vm/jvm/runtime/org/raku/nqp/runtime/LibraryLoader.java              | 16 +++--
 src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitZip.kt                 | 50 +++++++++++--
 t/nqp/123-unit-artifact.t                                               |  4 ++
 6 files changed, 128 insertions(+), 16 deletions(-)
```

Pushed:
```
git push ab5tract jesp-direct-lazy-records
   2035d43e2..e2628a882  jesp-direct-lazy-records -> jesp-direct-lazy-records
git push origin jesp-direct-lazy-records
   2035d43e2..e2628a882  jesp-direct-lazy-records -> jesp-direct-lazy-records
```
Both remotes updated, no force.

## Concerns

- The class-road `ByteBuffer`->`byte[]` fast path in fix 4c is covered only by Kotlin unit tests, not by any nqp/Rakudo-level test (no `t/nqp/*.t` uses `nqp::loadbytecodebuffer`), and the Rakudo `make` build was intentionally not run per the task's step 5.
- Fix 4c's array-reuse fast path adds one extra condition (`buffer.array().length == buffer.remaining()`) beyond the literal spec, for correctness against a future caller with a short-limit buffer; documented above and inert on the current single caller.
