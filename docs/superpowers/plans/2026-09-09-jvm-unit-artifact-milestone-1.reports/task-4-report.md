# Task 4 report: the loader roads, the entry main, the eval server

## Fix round 1 (review by im-curious-as)

Review findings and fixes, in the same nqp tree.

### Important 1 — cheap sniff + per-path road cache

- `UnitLoader.isUnitFile(fn)` now does a `ZipFile(f).use { it.getEntry(UnitZip.META) != null }`
  central-directory lookup instead of reading the whole file into memory
  and running it through `UnitZip.isUnit`.
- Added `isUnitFile(fn, shared)`: for a shared load it caches the road
  decision in a new `sharedRoads: ConcurrentHashMap<String, Boolean>`, so
  a repeat (eval-server) request pays one map lookup, not a re-sniff.
- `LibraryLoader.loadApp` and `LibraryLoader.prime` now call the two-arg
  form with the `shared` flag they already have (`prime` always primes
  for sharing, so it passes `true`, matching its existing `record(path,
  true)` / `loadFile(path, loader, true)` calls). `LibraryLoader.load(tc,
  String)` keeps the one-arg form, per the review (it's deduped by
  `addRef` per process already).
- Confirmed minor (2): with the `ZipFile` sniff, `isUnitFile` no longer
  reads the file body at all, so `UnitLoader.record`'s subsequent
  `File(fn).readBytes()` is the only full read — no double read.

### Important 2 — exception translation on the artifact road

Wrapped every artifact-road call site in `LibraryLoader.java`
(`load(tc, String)`, `load(tc, ByteBuffer)`, `loadApp`) with:
```java
catch (ControlException e) { throw e; }
catch (IOException | IllegalStateException | IllegalArgumentException e) {
    throw ExceptionHandling.dieInternal(tc, e);
}
```
(`ControlException` is `org.raku.nqp.runtime.ControlException`, same
package as `LibraryLoader`, confirmed by `find`.) The `load(tc,
ByteBuffer)` site's inner catch drops `IOException` — `loadAndRun(tc,
bytes)` never touches a file, only `UnitZip.read(bytes)` in memory, so
there is nothing for it to throw there (see compile note below).

**Adaptation beyond the review's literal snippet**: the review's catch
list included `IOException`, but Kotlin does not emit checked-exception
declarations by default, so javac saw `UnitLoader.loadAndRun` /
`loadUnit` as declaring no checked exceptions and refused to compile
`catch (IOException | ...)` with "exception IOException is never thrown
in body of corresponding try statement" at all three call sites. Fixed
by adding `@Throws(IOException::class)` to `UnitLoader.record`,
`loadUnit`, and `loadAndRun(tc, fn, shared)` in `UnitLoader.kt` (the ones
that actually call `File(...).readBytes()`), which makes Java's checked-
exception analysis treat them as declaring `IOException` — the standard
Kotlin/Java interop idiom already used elsewhere in this codebase (e.g.
`CompilationUnit.setupCompilationUnit`'s `@Throws(InstantiationException::class,
IllegalAccessException::class)`). `loadAndRun(tc, bytes)` (the in-memory
overload) was left undecorated and its call site's catch list has no
`IOException`, matching that it does no file I/O.

### Minors

1. `EvalServer.java`'s per-request site (`ServiceThread.RunThread.eval()`)
   now says "This unit is not an entry point", matching the other site.
2. Confirmed above (no double read).
3. Restored the `ThreadDeath` guard in `EvalServer.run(String, String[])`
   around the `loadApp` call: `catch (ThreadDeath td) { throw new
   RuntimeException("Couldn't load the app unit. Your CLASSPATH might
   not be set up correctly."); }`.

### Commands run and output

Build (first attempt failed exactly as described above — the `IOException`
"never thrown" compile error at three sites — fixed with `@Throws`, then
clean):
```
$ ./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars 2>&1 | tail -40
...
BUILD SUCCESSFUL in 2s
12 actionable tasks: 5 executed, 7 up-to-date
```

Plain runner smoke:
```
$ RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'say(1+2)'
3
```

`UnitMain` smoke (same command line as the original report):
```
$ RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 java ... org.raku.nqp.runtime.unit.UnitMain nqp/build/jvm/share/lib/nqp.jar -e 'say(6*7)'
42
```

Kotlin tests:
```
$ ./nqp/gradlew -p nqp :nqp-runtime:test 2>&1 | tail -10
...
BUILD SUCCESSFUL in 1s
```
`UnitFormatTest` tests="5" failures="0" errors="0"; `ProgramUnitTest`
tests="4" failures="0" errors="0" — 9/9 green.

### Commit

`cdc444674` — "unit artifact: cheap unit sniff with a per-path road
cache; artifact-road errors translate to dieInternal" (nqp tree, 3 files
changed: `UnitLoader.kt`, `LibraryLoader.java`, `EvalServer.java`;
50 insertions, 10 deletions). Staged by explicit path only.

### Concerns after fix round 1

- None blocking. The `@Throws` addition is a compile-mechanics necessity
  for the review's own intent (catching `IOException` from Kotlin in
  Java) rather than a design change — without it the review's exact
  catch clause does not compile at all.
- Same pre-existing gap as before: no unit artifact exists yet (Tasks
  6-7), so the artifact-road catch branches (`ControlException` passthrough,
  `IllegalStateException`/`IOException` translation, the road cache) are
  exercised by the Kotlin unit tests but not by an end-to-end JVM run in
  this task.

## Summary

Implemented all six steps of the brief in the nqp tree
(`/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp`).
Everything went in verbatim except one Java-compiler-forced tweak (noted
below). Built, ran both required smokes and the Kotlin unit tests, then
committed the four listed files only.

## What was implemented

- **Step 1 — `UnitLoader.kt`** (new):
  `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitLoader.kt`.
  `isUnitFile(fn)`, `record(fn, shared)` (shared-cache by path via
  `ConcurrentHashMap`), `loadUnit(tc, fn, shared)` (builds a `ProgramUnit`,
  initializes, does not run the load block), `loadAndRun(tc, fn, shared)`,
  and the byte-array overload `loadAndRun(tc, bytes)`. Verbatim from the
  brief.

- **Step 2 — bilingual switch in `LibraryLoader.java`**:
  `load(ThreadContext, String)` and `load(ThreadContext, ByteBuffer)` now
  check `UnitLoader.isUnitFile` / `UnitZip.isUnit` first and take the
  artifact road via `UnitLoader.loadAndRun`, falling through to the
  existing `resolveClass(...)` class road unchanged otherwise. Added
  `loadApp(tc, path, shared)` (road-agnostic: initializes without running
  the load block) and `prime(path, loader)` (warms whichever road, for
  the eval server). Verbatim from the brief, with one necessary
  compile-only fix: the brief's `loadApp` catch clause
  `IOException | IllegalArgumentException | ClassNotFoundException |
  ReflectiveOperationException` doesn't compile — `ClassNotFoundException`
  is a subclass of `ReflectiveOperationException`, and javac rejects a
  multi-catch where one alternative subclasses another. Dropped the
  redundant `ClassNotFoundException` alternative (still caught, via
  `ReflectiveOperationException`).

- **Step 3 — `UnitMain.kt`** (new):
  `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitMain.kt`. Verbatim
  from the brief: `main(argv)` builds a `GlobalContext`, loads via
  `LibraryLoader.loadApp(tc, argv[0], false)`, requires an entry qbid, and
  calls `Ops.invokeMain`.

- **Step 4 — `EvalServer.java` through `loadApp`**: `run(String, String[])`
  rewritten per the brief (drops the separate `loadFile` try/catch, loads
  via `LibraryLoader.loadApp(gc.mainThread, appPath, true)`, uses
  `cu.unitId()` in place of `cuType.getName()`). Server-start `run()`
  replaces `cuType = LibraryLoader.loadFile(mainPath, ...)` with
  `LibraryLoader.prime(mainPath, gc.byteClassLoader)`. The per-request
  `ServiceThread.RunThread.eval()` site gets the same two-line change:
  `LibraryLoader.loadApp(gc.mainThread, mainPath, true)` replacing
  `CompilationUnit.setupCompilationUnit(gc.mainThread, cuType, true)`, and
  `cu.unitId()` replacing `cuType.getName()`. The now-unused `cuType`
  field was deleted (the compiler would otherwise have flagged it, per
  the brief's instruction — confirmed unused via grep before removing).

- **Step 5 — build and smoke both roads**: see Commands below.

- **Step 6 — commit**: single commit `bc1c0a881` in the nqp tree, exactly
  the four listed paths staged by name (never `git add -A`).
  Attribution trailer used the one from this session's system-reminder
  ("this replaces any earlier attribution guidance"), not the brief's
  literal placeholder text.

## Commands run and output

Build:
```
$ ./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars 2>&1 | tail -5
...
BUILD SUCCESSFUL in 3s
12 actionable tasks: 6 executed, 6 up-to-date
```
(First attempt failed on the ClassNotFoundException/ReflectiveOperationException
multi-catch subclassing error described above; fixed and rebuilt clean, 4
pre-existing warnings only — deprecation notices for `ThreadDeath` and
unrelated Kotlin `!!` warnings in `Ops.kt`, none from the new code.)

`UnitMain` smoke (from the rakudo worktree root, boot classpath and
classpath copied verbatim from `tail -1 nqp/nqp-j-gradle`, main class
`nqp` replaced with `org.raku.nqp.runtime.unit.UnitMain
nqp/build/jvm/share/lib/nqp.jar`):
```
$ RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 java --enable-native-access=ALL-UNNAMED,org.graalvm.truffle \
    --sun-misc-unsafe-memory-access=allow -Xmx4g -Xss64m \
    --module-path nqp/build/jvm/share/truffle --add-modules org.graalvm.truffle,org.graalvm.truffle.runtime \
    -Xbootclasspath/a:"...nqp-runtime.jar:...asm-9.10.1.jar:...asm-tree-9.10.1.jar:...fastutil-8.5.19.jar:...jline-4.3.1.jar:...lz4-java-1.8.0.jar:...kotlin-stdlib-2.4.10.jar:...annotations-13.0.jar:...nqp.jar" \
    -cp "nqp/build/jvm/share/lib:nqp/build/jvm/share/runtime/nqp-truffle.jar" \
    org.raku.nqp.runtime.unit.UnitMain nqp/build/jvm/share/lib/nqp.jar -e 'say(6*7)'
42
```
Expected `42` — matched. Proves `loadApp`'s class road (nqp.jar is still a
class-file unit) and entry through `UnitMain`.

Plain-runner smoke (class road through `LibraryLoader.load`, untouched):
```
$ RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'say(1+2)'
3
```
Expected `3` — matched.

Kotlin tests:
```
$ ./nqp/gradlew -p nqp :nqp-runtime:test 2>&1 | tail -5
...
BUILD SUCCESSFUL in 1s
```
Test-result XMLs: `UnitFormatTest` tests="5" failures="0" errors="0";
`ProgramUnitTest` tests="4" failures="0" errors="0" — 9/9 green, matching
the brief's expectation.

## Files changed (nqp tree)

- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitLoader.kt` (new)
- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitMain.kt` (new)
- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/LibraryLoader.java` (modified)
- `nqp/src/vm/jvm/runtime/org/raku/nqp/tools/EvalServer.java` (modified)

Commit: `bc1c0a881` — "unit artifact: the bilingual loader (unit.meta
picks the road), UnitMain, eval server through loadApp"
(4 files changed, 103 insertions, 15 deletions).

`git status` in the nqp tree before staging showed only these four paths
modified/untracked (the other session's uncommitted changes to
`nqp-truffle/src/main/java/org/raku/nqp/truffle/*.java`,
`src/vm/jvm/QAST/Compiler.nqp`, `src/vm/jvm/QAST/TruffleEncoder.nqp` were
already committed or otherwise absent from the working tree at the time —
in any case nothing outside the four brief paths was staged; files were
added by explicit path, never `git add -A`).

## Self-review

- **Completeness against every brief step**: all six steps done in order.
- **Class road untouched in behaviour**: `resolveClass` itself is
  unedited; the `load()` overloads only add an `isUnitFile`/`isUnit`
  guard ahead of the existing call, false on every input in this task
  (no unit artifacts exist yet — that's Tasks 6-7), so the fallthrough
  path is byte-identical to before. Both smokes confirm no regression
  (`42` and `3`, exactly as specified).
- **Names/signatures verbatim**: `UnitLoader.isUnitFile/record/loadUnit/
  loadAndRun`, `LibraryLoader.loadApp/prime`, `UnitMain.main` all present
  with the brief's exact signatures. The only signature-level deviation
  is the narrowed catch list in `loadApp` (documented above), which
  changes no runtime behavior — `ReflectiveOperationException` still
  catches every `ClassNotFoundException`.
- **Pristine output**: both smoke runs printed exactly the expected value
  with nothing else on stdout.
- **Env-gating**: no diagnostic prints were added in this task, so
  nothing to gate.

## Concerns

- None blocking. The one adaptation (catch-list narrowing) is a
  mechanical Java-compiler constraint, not a design change — the brief's
  own text elsewhere confirms `ClassNotFoundException extends
  ReflectiveOperationException`, so this is just javac enforcing that.
- No artifact (`unit.meta` jar) exists yet to smoke-test the artifact
  road end-to-end through `UnitMain`/`loadApp`/`prime`; per the task
  context this is expected — Tasks 6-7 produce the compiler side. The
  artifact-road code paths (`UnitLoader.loadUnit/loadAndRun`, the
  `isUnitFile`/`isUnit` branches in `LibraryLoader`) are exercised only
  by the Kotlin unit tests (`ProgramUnitTest`, `UnitFormatTest`) at this
  point, not by an end-to-end JVM run.
