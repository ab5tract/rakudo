# Task 5 report: the recorder and the artifact rewriter

**Status:** DONE
**Commit (nqp):** `3d0b54fa4` — "Unit artifact: UnitDispatchWriter rewrites a unit's dispatch slots in place; NQP_DISPATCH_RECORD trains at exit (Phase C)"

## What I implemented

Exactly the brief, nothing beyond it.

1. **`UnitDispatchWriter.kt` (new)** — `rewrite(path, slots: Map<String, Map<Int, ByteArray>>)`.
   Reads the artifact with `File.readBytes()`, reads its central directory with
   `ZipDirectory.read`, and for every named entry prefix (`"unit"`,
   `"nested/<id>"`) rebuilds that unit's `.dispatch` entry slot by slot: a named
   slot takes its new bytes, every other slot keeps the bytes it had (copied out
   of the old dispatch entry at its old offset/length), and the fixed-width slot
   rows of the matching `.index` are repointed into the rebuilt entry. Every
   other entry is copied byte for byte, in central-directory order, so
   `unit.index` stays first and `UnitStore.isUnit`'s sniff still works. The
   result is written to `<path>.tmp` and renamed over the original with
   `Files.move(..., ATOMIC_MOVE, REPLACE_EXISTING)`, so a process that holds the
   old file mapped keeps reading the old inode. A slot index outside the unit's
   table is an `IllegalArgumentException` (`require`); a stored offset/length
   running past the old dispatch entry is likewise a hard `require` failure.
   A missing `<prefix>.index` / `<prefix>.dispatch` entry is an
   `IllegalArgumentException`.

2. **`UnitImageWriter.put`: `private` -> `internal`**, with a one-line KDoc
   saying why (both writers must store entries the same way).

3. **`UnitStore` init: the per-program slot-window check (ruling 12)**, placed
   directly after the existing `need` check: `first < 0 || count < 0 ||
   first + count > dispatchSlotCount` throws `IllegalStateException`.

4. **`DispatchPersist`: the recorder.** Added `recordSelector` (from
   `NQP_DISPATCH_RECORD`, comma-split, trimmed, empties dropped), `selected()`,
   and `@JvmStatic fun recordAtExit()`; the `init` block gains
   `if (recordSelector != null) Runtime.getRuntime().addShutdownHook(Thread { recordAtExit() })`.
   `recordAtExit` walks `DispatchBootstrap.sites()`, skips anonymous sites,
   sites with no programs, unregistered namespaces, unselected stores and
   out-of-range slots; groups by `store.name` -> `store.entryPrefix` ->
   absolute slot; merges duplicate programs of one slot by `DispatchDump.describe`
   text (`LinkedHashMap.putIfAbsent`, so first-seen order is kept); persists each
   with `DispatchSlotCodec.persist`, counting the `null`s as `unpersistable` and
   capping the kept ones at `Dispatch.MAX_PROGRAMS`; encodes one `DispatchSlot`
   per non-empty slot with `UnitCodec` and calls `UnitDispatchWriter.rewrite`
   once per artifact path. It then prints the build's positive marker
   `dispatch-record: wrote <slots> slots (<n> programs, <n> unpersistable) to <path>`
   on stderr — only reachable when `NQP_DISPATCH_RECORD` is set, so the print is
   env-gated by construction.

   The stale `(recordAtExit, Task 5)` reference in the object's KDoc became
   `(recordAtExit)`.

## TDD evidence

**RED** — the test written first, implementation absent:

```
$ ./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.runtime.unit.UnitDispatchWriterTest' -q
e: .../UnitDispatchWriterTest.kt:26:9 Unresolved reference 'UnitDispatchWriter'.
e: .../UnitDispatchWriterTest.kt:44:53 Unresolved reference 'UnitDispatchWriter'.

FAILURE: Build failed with an exception.
* What went wrong:
Execution failed for task ':nqp-runtime:compileTestKotlin' ...
BUILD FAILED in 613ms
```

**GREEN** — same command after `UnitDispatchWriter.kt`, the `internal put`, the
`UnitStore` check and the recorder:

```
$ ./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.runtime.unit.UnitDispatchWriterTest' -q
(only the 5 pre-existing ThreadDeath deprecation warnings from EvalServer.java)

$ grep -o 'tests="..." skipped="..." failures="..." errors="..."' \
    nqp/nqp-runtime/build/test-results/test/TEST-...UnitDispatchWriterTest.xml
tests="2" skipped="0" failures="0" errors="0"
```

**Whole runtime suite** (once, before committing):

```
$ ./nqp/gradlew -p nqp :nqp-runtime:test -q      # clean, exit 0
$ (sum of all TEST-*.xml)
tests=45 skipped=0 failures=0 errors=0
```

45, i.e. the 43 of before plus the two new ones, as expected.

**Jars rebuilt and synced** (no `clean`, no `buildJvm`, no rakudo `make`, no
training run):

```
$ ./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars -q     # 2.2 s (everything else was already current)
$ unzip -l nqp/build/jvm/share/runtime/nqp-runtime.jar | grep UnitDispatchWriter
    10351  org/raku/nqp/runtime/unit/UnitDispatchWriter.class
```

`nqp/build/jvm/share/runtime/{nqp-runtime,nqp-truffle}.jar` both carry the new
timestamp, so Task 6 starts from a synced build.

## What the tests verify

`UnitDispatchWriterTest` works on a real temp file, not a heap buffer:

- `fillsTheNamedSlotsKeepsTheRestAndCopiesEveryOtherEntry` — writes the shared
  fixture image with one pre-filled slot (0 -> `1,2,3`) and one nested unit
  (`n1`), rewrites slot 2 of `unit` and slot 1 of `nested/n1`, then reopens the
  file and checks: the unnamed filled slot still reads `1,2,3`; the unnamed
  empty slot is still empty; both named slots read their new bytes (through
  `dispatchSlot(program, ordinal)`, so the `.index` rows really were repointed);
  `unit.records` and `unit.serialized` are byte-identical to before;
  `header.dispatchSlotCount` is unchanged; `program(2)` still decodes to the
  non-ASCII fixture text (the `.programs` entry survived intact).
- `refusesASlotOutsideTheTable` — slot 3 of a 3-slot table throws
  `IllegalArgumentException`.

Suite output is pristine (nothing printed beyond the accepted pre-existing
`ThreadDeath` javac warnings).

## Files changed

- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitDispatchWriter.kt` (new)
- `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitDispatchWriterTest.kt` (new)
- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitImageWriter.kt` (`put` internal)
- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitStore.kt` (init window check)
- `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt` (recorder)

No jar is staged or committed (`git diff --name-only --staged` before the commit
listed exactly the five sources; the nine modified `src/vm/jvm/stage0/*.jar`
remain uncommitted working-tree changes).

## Self-review findings

Checked and confirmed:

- The `dispatch-record: wrote` marker keeps its exact prefix and cannot print
  without `NQP_DISPATCH_RECORD`.
- Merge-by-text dedupe (`putIfAbsent` on `DispatchDump.describe`) and the
  `MAX_PROGRAMS` cap are both in the per-slot loop, in that order.
- Unnamed slots keep their old bytes; an unnamed empty slot stays `0/0`.
- Every non-`.index`/`.dispatch` entry, and every `.index`/`.dispatch` of an
  unnamed prefix, is copied byte for byte; the order is the central directory's,
  so `unit.index` stays first.
- Nested prefixes (`nested/<id>.index` / `.dispatch`) resolve through the same
  `removeSuffix` mapping and are patched independently of the outer unit.
- The `require` on slot range fires before anything is written, and the writer
  only touches the file after every prefix has patched successfully (the tmp
  file is written after the whole zip is built in memory), so a refusal leaves
  the artifact untouched.
- The `UnitStore` window check cannot reject anything `UnitImageWriter`
  produces (it lays windows out sequentially summing to `dispatchSlotCount`);
  the 45 green tests include the store and program-unit fixtures.

Nothing found needing a fix. No restructuring was needed.

## Concerns

Two, both inherited from the brief's design rather than deviations, and neither
blocking Task 6:

1. `selected()` uses `recordSelector!!`, so a direct call to the public
   `recordAtExit()` with `NQP_DISPATCH_RECORD` unset would NPE. In practice the
   only caller is the shutdown hook, which is installed only when the selector
   is non-null.
2. `rewrite` uses a fixed `<path>.tmp`, so two training runs recording the same
   artifact concurrently would race. Training is a deliberate, serial step.
