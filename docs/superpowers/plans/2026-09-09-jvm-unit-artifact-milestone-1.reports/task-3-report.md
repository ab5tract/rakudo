# Task 3 report: ProgramUnit, the reflection-free unit

## What was implemented

Created `ProgramUnit`, a `CompilationUnit` subclass built entirely from a
`UnitRecord` (Task 1's format) with no reflection: `buildTable(bootSt)` walks
`meta.blocks` and builds one `CodeRef` per non-null `BlockRec`, using
`ProgramEntry.ENTER` (Task 2) as every block's method handle and
`ArgsExpectation.USE_BINDER` as the args expectation; a second pass wires
`outerStaticInfo` from `outerQbid`. All the `CompilationUnit` hooks
(`getCallSites`, `hllName`, `deserializeQbid`, `loadQbid`, `mainlineQbid`,
`entryQbid`, `serializedCodeRefCount`, `unitId`, `engineProgram`,
`serializedBlob`, `claimNested`, `initializeCompilationUnit`,
`runDeserializeIfAvailable`) are overridden to answer from the record/meta
instead of class reflection. `applyStaticLexValues(tc)` installs static
lexical values by reading `tc.gc.scs.get(handle)!!.getObject(idx)`, matching
the pattern already used in `CompilationUnit.setLexValuesBulk`.

Before writing, I read the real sources for every dependency the brief
names — `UnitRecord.kt` (Task 1), `CompilationUnit.kt`, `StaticCodeInfo.kt`,
`CodeRef.kt`, `CallSiteDescriptor.kt`, `ProgramEntry.kt` (Task 2) — and
confirmed every signature the brief's Step 3 code uses matches exactly,
including the subtle bit flagged in Step 4: `ProgramEntry.ENTER`'s type is
`(ThreadContext, CodeRef, CallSiteDescriptor, ResumeStatus.Frame, Object[])
-> void`, so `StaticCodeInfo`'s init block takes the "new way" branch
(`parameterType(3) == ResumeStatus.Frame`) and the `ArgsExpectation.USE_BINDER`
case in its `when` populates `mhResume` without hitting the "Unhandled
ArgsExpectation" branch. No adaptation was needed — the brief's code (Step 3)
was used verbatim.

## Files changed

- Created `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt`
- Created `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/ProgramUnitTest.kt`

Both taken verbatim from the brief.

## TDD evidence

RED (before `ProgramUnit.kt` existed):

```
cd nqp && ./gradlew :nqp-runtime:test --tests 'org.raku.nqp.runtime.unit.ProgramUnitTest' 2>&1 | tail -40
```

```
e: .../ProgramUnitTest.kt:45:45 Cannot infer type for type parameter 'V'. Specify it explicitly.
e: .../ProgramUnitTest.kt:45:52 Unresolved reference 'staticInfo'.
...
e: .../ProgramUnitTest.kt:53:11 Unresolved reference 'buildTable'.
...
BUILD FAILED in 894ms
```

(The test file references `ProgramUnit`, `BlockRec`, `UnitMeta`, etc.
directly — the compiler reports the cascading unresolved-reference errors
above rather than a single "Unresolved reference: ProgramUnit" line, since
`ProgramUnit` and its members don't exist yet. This is the equivalent
failure the brief's Step 2 describes.)

Note: the brief's run command (`./nqp/gradlew -p nqp ...`) is written for
invocation from the rakudo root; run directly inside the nqp tree it is
`./gradlew :nqp-runtime:test ...` (no `-p nqp`, since gradle is already
rooted there). Used that form throughout.

GREEN (after implementing `ProgramUnit.kt`):

```
cd nqp && ./gradlew :nqp-runtime:test --tests 'org.raku.nqp.runtime.unit.ProgramUnitTest' 2>&1 | tail -10
```

```
> Task :nqp-runtime:test

BUILD SUCCESSFUL in 1s
10 actionable tasks: 5 executed, 5 up-to-date
```

Full suite before committing:

```
cd nqp && ./gradlew :nqp-runtime:test --rerun 2>&1 | tail -10
```

```
BUILD SUCCESSFUL in 864ms
10 actionable tasks: 1 executed, 9 up-to-date
```

Test-result XML counts (forced rerun, both suites):

```
TEST-org.raku.nqp.runtime.unit.UnitFormatTest.xml:  tests="5" skipped="0" failures="0" errors="0"
TEST-org.raku.nqp.runtime.unit.ProgramUnitTest.xml: tests="4" skipped="0" failures="0" errors="0"
```

All 9 tests green, no failures, no errors, no skips.

## Commit

`7a2be3832` — "unit artifact: ProgramUnit, a CompilationUnit built from the
block table without reflection" (nqp tree). Only the two brief-listed files
staged and committed (`git status --short` showed only those two paths
before add; verified clean working tree after commit — nothing from the
other session's unrelated uncommitted work touched).

Commit trailer: the active session-wide attribution override (system
reminder "Attribution for git commits... replaces any earlier attribution
guidance") takes precedence over the brief's literal trailer text, so the
commit carries:

```
Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRn8gLyZjirBAKS6urb3n4
```

(brief's literal draft said "Claude Fable 5.1"; the override supersedes it).
The commit message subject/body otherwise matches the brief verbatim.

## Self-review

- **Completeness against the brief**: all four required pieces present —
  `buildTable(bootSt: STable?)` (pure, tested without a ThreadContext),
  overrides of every generated hook (`getCallSites`, `hllName`,
  `deserializeQbid`, `loadQbid`, `mainlineQbid`, `entryQbid`,
  `serializedCodeRefCount`, `unitId`, `engineProgram`, `serializedBlob`,
  `claimNested`, `initializeCompilationUnit`, `runDeserializeIfAvailable`),
  and `applyStaticLexValues(tc)`.
- **Names/signatures verbatim**: class is `ProgramUnit(record: UnitRecord) :
  CompilationUnit()`; every override signature matches the `open`/`abstract`
  declarations in `CompilationUnit.kt` exactly (checked side by side).
  `CodeRef` and `CallSiteDescriptor` constructor calls match their real
  constructors. `ProgramEntry.ENTER`'s type checked against
  `StaticCodeInfo`'s init-block dispatch, confirmed it lands on the
  `USE_BINDER` path without throwing.
  This class does not touch `StaticCodeInfo.materialize`/`CodeEngines` beyond
  what the brief specifies — those hooks arrive fully wired via
  `programIndex`/`engineProgram`, ready for Task 4's `CodeEngines.materialize`
  callers, not exercised by this task's own code.
- **Tests assert real behaviour**: `tableFollowsTheBlockTable` checks table
  size, the null gap at qbid 2, outer wiring across a gap, and `codeRefs`
  excluding the gap; `blocksAreRawArgsEngineBlocksWithDistinctHandles`
  checks `argsExpectation`, `programIndex`, per-block distinct `mh`
  identity, non-null `mhResume`, and the post-`insertArguments` parameter
  count; `handlersUnflatten` checks the flat-to-`Array<LongArray>`
  conversion; `hooksAnswerFromTheMeta` checks every meta-derived hook. None
  are tautological — each reads a real field computed by `buildTable` or a
  hook method.
- **Pristine test output**: `BUILD SUCCESSFUL`, 9/9 tests, 0
  failures/errors/skips, no stray stdout/stderr in the reports.
- **Env-gating**: `ProgramUnit.kt` has no diagnostic prints, so nothing to
  gate.
- **Scope discipline**: touched only the two files named in the brief; did
  not run `git add -A`; did not touch the other session's in-flight files
  under `nqp-truffle/`, `Compiler.nqp`, or `TruffleEncoder.nqp`.

## Concerns

None. The brief's Step 3 code compiled and passed unmodified; the only
deviation from the brief's literal text is the mandated attribution-trailer
override (documented above), which is a session-wide instruction, not a
design change.
