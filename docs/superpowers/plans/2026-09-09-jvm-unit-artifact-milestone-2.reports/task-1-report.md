# Task 1 report: The record road in the runtime

Status: DONE

## What was implemented

Followed the brief step by step (Steps 1-10), transcribing its code verbatim
into the nqp working tree (`.claude/worktrees/jesp-direct-lazy-records/nqp`):

1. **Test (RED then GREEN)**: `nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/ProgramUnitTest.kt`
   — `block()` helper gained a `cuid: String? = null` parameter, and a new
   test `cuidLookupFollowsTheBlockTable` asserts `ProgramUnit.lookupCodeRef(cuid)`
   resolves against the block table, including the "no cuid" and "unknown
   cuid" and empty-string cases.

2. **`ProgramUnit.kt`**: added a private `byCuid: HashMap<String, CodeRef>`
   field; `buildTable` now populates it (`b.cuid?.let { if (it.isNotEmpty())
   byCuid[it] = cr }`); added `override fun lookupCodeRef(uniqueId: String):
   CodeRef? = byCuid[uniqueId]`; `claimNested` now falls back to
   `tc.gc.inMemoryUnitRecords[name]` when the unit's own `record.nested` map
   doesn't carry the name (a record-road parent can now claim a
   runtime-compiled nested unit).

3. **`UnitRecord.kt`**: updated the `cuid` field's comment to reflect that a
   runtime-compiled unit writes it too, not only a nested unit.

4. **`EvalResult.kt`**: rewritten to add `@JvmField var record: UnitRecord?
   = null` alongside the existing `jc` and `cu` fields, with a new class doc
   comment explaining the two-road relationship.

5. **`GlobalContext.kt`**: added `inMemoryUnitRecords`, a
   `ConcurrentHashMap<String, UnitRecord>`, directly after
   `inMemoryUnitOfCuid` — the record road's twin of `inMemoryUnitBytes`.

6. **`UnitWriter.kt`**: split into `record()` (the reading half — refuses a
   non-unit-road tree, bytecode fallbacks, a qbid-less or program-less
   block, a duplicate qbid, and a nested id with no retained record; also
   now resolves `jc.nestedClasses` against `tc.gc.inMemoryUnitRecords`
   instead of refusing any nested class, which was milestone 1's
   restriction) and a thin `write()` that calls `record()` and zips the
   result. Folded in the program-index upper-bound check (milestone 1's
   deferred minor 1).

7. **`Syscalls.kt`**: added `jvm-build-unit` (OBJ, OBJ) directly after
   `jvm-write-unit`, building an `EvalResult` whose `record` is set from
   `UnitWriter.record(...)`.

8. **`Ops.kt`**: replaced `loadcompunit` to branch on `res.record`: when
   set, builds a `ProgramUnit(rec)` (unshared) instead of defining a class;
   either way it initializes under the compilee's HLL config and, when a
   compilation is under way, retains the result on the road it was
   compiled on (`inMemoryUnitRecords` for a record, `inMemoryUnitBytes` for
   class bytes) and indexes `inMemoryUnitOfCuid` from its code refs. Both
   `res.jc` and `res.record` are cleared at the end. Updated the doc
   comment on `jvmclassofcuid` to describe both roads.

9. **`CodeEngine.kt`**: `materialize` now compiles through the same
   `programs` cache `codeRun` uses
   (`programs.computeIfAbsent(sci.compUnit.engineProgram(sci.programIndex))
   { engine.compile(it) }`), with a doc-comment sentence added (milestone-1
   review minor 4).

Every diagnostic print already in this code (`NQP_CODE_WHY`) stayed
env-gated; the one new print added (in `loadcompunit`'s record branch) is
gated the same way. No bare prints were introduced.

## TDD evidence

**RED** — `./nqp/gradlew -p nqp :nqp-runtime:test --tests
'org.raku.nqp.runtime.unit.ProgramUnitTest' 2>&1 | tail -15`, run before any
production-code edits (only the test file had been changed at that point):

```
> Task :nqp-runtime:test FAILED

ProgramUnitTest > cuidLookupFollowsTheBlockTable() FAILED
    org.opentest4j.AssertionFailedError at ProgramUnitTest.kt:79

5 tests completed, 1 failed

FAILURE: Build failed with an exception.
...
BUILD FAILED in 1s
```

**GREEN** — same command, after Steps 3-7 were implemented:

```
> Task :nqp-runtime:test

BUILD SUCCESSFUL in 4s
```

(Gradle's default test task prints no per-test summary on success; the
absence of `FAILED`/`FAILURE` and the `BUILD SUCCESSFUL` line is the
pass evidence there, corroborated by the full-suite run below.)

Full suite before commit — `./nqp/gradlew -p nqp :nqp-runtime:test
:nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars`: `BUILD SUCCESSFUL`.
Test-result XML confirms both suites and the expected counts:

```
TEST-org.raku.nqp.runtime.unit.ProgramUnitTest.xml: tests="5" skipped="0" failures="0" errors="0"
TEST-org.raku.nqp.runtime.unit.UnitFormatTest.xml:  tests="10" skipped="0" failures="0" errors="0"
```

15 tests total, all passing, matching the brief's Step 8 expectation.

## Smoke commands (Step 9)

```
$ RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'say(6*7)'
42
```

```
$ RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle nqp/t/nqp/123-unit-artifact.t
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

Both match the brief's expected output exactly.

## Files changed

- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitWriter.kt`
- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt`
- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitRecord.kt`
- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/EvalResult.kt`
- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/GlobalContext.kt`
- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt`
- `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/Syscalls.kt`
- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CodeEngine.kt`
- `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/ProgramUnitTest.kt`

Commit: nqp tree `6d0af267d` "unit artifact: the record road in the
runtime -- jvm-build-unit, loadcompunit builds a ProgramUnit from the
record, nested records retained and embedded". Uses this session's
attribution trailers (per the system-provided override), not the brief's
literal `Claude Fable 5.1` trailer.

## Self-review findings

- **Completeness**: every step (1-10) done; every file in the brief's file
  list touched, no others.
- **Quality**: names and doc comments transcribed as given; no bare
  `System.err.println` — the one new print in `loadcompunit`'s record
  branch is gated on `NQP_CODE_WHY`, matching the sibling print already in
  `UnitWriter.write`.
- **Discipline**: nothing beyond the brief was added. `git diff` of each
  file matches the brief's code blocks essentially verbatim (only the
  necessary surrounding context — e.g. leaving `serializedBlob`/`hllName`
  etc. in place — was left untouched).
- **Testing**: the new test exercises real behaviour (positive lookups by
  cuid returning the exact `CodeRef` instances from the built table,
  negative lookups for an absent cuid and for a block with no cuid, and
  the empty-string case) rather than a placeholder assertion. Test output
  is pristine — no stray stdout/stderr, no flaky ordering.

## Concerns

None. Nothing in this task reaches the new `jvm-build-unit` syscall or the
`record`-branch of `loadcompunit` yet except the Kotlin unit test and the
two smoke commands (which still take the class road / artifact-file road,
per the milestone-1 rule) — exactly as the brief specifies for Task 1.
Task 2 (the NQP compiler side) is what will start exercising the new
syscall end-to-end.
