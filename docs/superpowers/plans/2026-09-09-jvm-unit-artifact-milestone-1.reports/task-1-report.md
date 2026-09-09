# Task 1 report: the artifact format and its round trip

## What I implemented

Transcribed the brief's code verbatim, no adaptations were needed:

1. `nqp/nqp-runtime/build.gradle.kts` — added `testImplementation(kotlin("test"))`
   inside `dependencies { ... }`, and a `tasks.test { useJUnitPlatform() }` block
   after `tasks.jar { ... }`. Test source set is gradle's default
   `nqp-runtime/src/test/kotlin` (created).
2. `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitRecord.kt` — the data
   classes `BlockRec`, `CallSiteRec`, `LexValueRec`, `UnitMeta`, `UnitRecord`.
3. `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitFormat.kt` — the binary
   codec: `writeMeta`/`readMeta` (fixed-width little-endian ints, byte-length-
   framed UTF-8 strings, magic `NQPU` + version guard), `writePrograms`/
   `readPrograms` (LZ4-compressed, byte-framed program text), plus
   `compress`/`decompress` helpers used for the serialized context section.
4. `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitZip.kt` — the zip
   envelope: `write`, `read`, `isUnit` (PK magic + presence of `unit.meta`
   entry), constants `META`, `PROGRAMS`, `SERIALIZED`, `NESTED_DIR`; `read`
   also validates block program-index bounds, outer-qbid bounds, and
   serialized-code-ref-count against the block table, raising
   `IllegalStateException` on any violation.
5. `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitFormatTest.kt`
   — the 5-test round-trip suite from the brief, unmodified.

No design changes and no adaptations to the brief's code were required — it
compiled and ran as given against the real `nqp-runtime` module (lz4-java was
already resolvable via `NqpDeps.thirdParty`).

## What I tested, and results (TDD evidence)

**RED** — before `UnitFormat.kt`/`UnitZip.kt` existed (only `UnitRecord.kt` and
the test were in place):

Command:
```
./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.runtime.unit.UnitFormatTest' 2>&1 | tail -30
```
Output (relevant lines):
```
e: .../UnitFormatTest.kt:87:21 Unresolved reference 'UnitFormat'.
e: .../UnitFormatTest.kt:89:31 Unresolved reference 'UnitFormat'.
e: .../UnitFormatTest.kt:95:21 Unresolved reference 'UnitZip'.
...
Execution failed for task ':nqp-runtime:compileTestKotlin' ...
BUILD FAILED in 6s
```
This is exactly the expected failure mode (compilation error, `Unresolved
reference: UnitFormat`/`UnitZip`) — the test references classes that did not
exist yet.

**GREEN** — after writing `UnitFormat.kt` and `UnitZip.kt`:

Command:
```
./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.runtime.unit.UnitFormatTest' 2>&1 | tail -40
```
Output (relevant lines):
```
> Task :nqp-runtime:test
BUILD SUCCESSFUL in 3s
10 actionable tasks: 4 executed, 6 up-to-date
```
Confirmed via the JUnit XML report
(`nqp-runtime/build/test-results/test/TEST-org.raku.nqp.runtime.unit.UnitFormatTest.xml`):
```xml
<testsuite name="org.raku.nqp.runtime.unit.UnitFormatTest" tests="5" skipped="0" failures="0" errors="0" ...>
  <testcase name="metaRoundTrips()" .../>
  <testcase name="nonUnitBytesAreNotAUnit()" .../>
  <testcase name="unknownVersionIsAHardError()" .../>
  <testcase name="programsRoundTripByByte()" .../>
  <testcase name="zipRoundTrips()" .../>
  <system-out><![CDATA[]]></system-out>
  <system-err><![CDATA[]]></system-err>
</testsuite>
```
5/5 passing, zero stdout/stderr noise.

Then, per the task instructions, ran the whole `:nqp-runtime:test` task once
before committing:
```
./nqp/gradlew -p nqp :nqp-runtime:test 2>&1 | tail -40
```
```
> Task :nqp-runtime:test
BUILD SUCCESSFUL in 970ms
```
(`UnitFormatTest` is currently the only test class in the module, so this
exercises the same 5 tests.)

## Files changed

- `nqp/nqp-runtime/build.gradle.kts` (modified)
- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitRecord.kt` (new)
- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitFormat.kt` (new)
- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitZip.kt` (new)
- `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitFormatTest.kt` (new)

Commit: `47f7db168` "unit artifact: the format (unit.meta, byte-framed
programs, zip envelope) with a round trip" (nqp tree, exactly these 5 paths
staged — verified `git status --short` before commit showed only these
changes, and shows clean after).

## Self-review findings

- All 5 files from the brief present, all 5 interfaces implemented as
  specified (`UnitMeta`, `BlockRec`, `CallSiteRec`, `LexValueRec`,
  `UnitRecord`; `UnitFormat.writeMeta/readMeta/writePrograms/readPrograms`;
  `UnitZip.write/read/isUnit` + the four constants).
- Test file transcribed verbatim; all 5 test methods present and each
  asserts real, specific behaviour (byte-level round trip of meta incl.
  non-ASCII/gap blocks/nulls, program byte-identity round trip including a
  >65535-char string that would overflow a class-file constant pool entry,
  full zip round trip incl. nested unit with no `serialized` section, a
  version-mismatch hard error, and PK-magic rejection of a class file).
- No bare `println`/debug prints added anywhere — codec and zip code has no
  logging at all, consistent with "env-gate any debug print" (nothing to
  gate since nothing prints).
- Kotlin free-compiler-args (`-Xno-param-assertions` etc.) are inherited
  from the module's existing `kotlin { compilerOptions { ... } }` block;
  didn't touch that.
- `git status --short` before staging showed exactly
  `nqp-runtime/build.gradle.kts` (modified) plus the two new directories
  under `src/vm/.../unit/` and `nqp-runtime/src/test/...` — nothing from the
  other session's in-progress work (`nqp-truffle/*.java`, `Compiler.nqp`,
  `TruffleEncoder.nqp`) was touched, staged, or is present in the commit.
  Used `git add <explicit paths>`, never `-A`.
- Test output is pristine: empty `system-out`/`system-err` in the JUnit XML,
  and the only Gradle deprecation warnings present come from the *root*
  `build.gradle.kts` (lines 57 and 93, delegated-property syntax) — verified
  with `--warning-mode all`; unrelated to any file I touched, pre-existing.
- `writePrograms`'s LZ4 compressor construction (`LZ4CompressorWithLength(...highCompressor(8))`)
  matches the brief exactly and mirrors the existing
  `LibraryLoader`/`JASTCompiler` usage pattern per the brief's pointer (did
  not need to consult those files further — the brief's code compiled
  as-is).

## Issues or concerns

None. No adaptations to the brief's code were required (import paths,
visibility, etc. all matched the real runtime as given). No design
questions arose.
