# Task 2 report: Runtime hooks and the shared block entry

## Summary

Implemented all six steps of the brief verbatim, in nqp tree
`/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp`.
No adaptations were needed — every line number, signature, and helper
(`LibraryLoader.readToHeapBufferLz4`/`readToHeapBuffer`, `CallFrame(tc, cr: CodeRef)`,
`ExceptionHandling.dieInternal(tc, Throwable)`, `ResumeStatus.Frame`, `CodeRef.staticInfo`,
`StaticCodeInfo.compUnit`) matched the brief exactly against the real code as of
nqp commit `f3df464e9` (post Task 1, `47f7db168`).

## What was implemented

1. **CompilationUnit.kt**
   - `fun runDeserializeIfAvailable` → `open fun runDeserializeIfAvailable` (line 185, unchanged position).
   - `fun engineProgram(idx: Int): String` → `open fun engineProgram(idx: Int): String` (line 392, unchanged position).
   - Added after `serializedCodeRefCount()` (line 380): `open fun unitId(): String`,
     `open fun serializedBlob(): java.nio.ByteBuffer?`, `open fun claimNested(tc, name): CompilationUnit`,
     verbatim from the brief.

2. **Ops.kt**
   - `deserialize` (was lines 6512-6532): replaced the class-resource-lookup block with
     `binaryBlob = cu.serializedBlob() ?: throw ExceptionHandling.dieInternal(tc, "unit ${cu.unitId()} has no serialized context to deserialize")`,
     keeping the existing `Base64.decode(blob)` else-arm untouched.
   - `jvmclaimnested` (was lines 8959-9001): replaced the manual `Class.forName` +
     `newInstance` + `shared` + `initializeCompilationUnit` sequence with
     `val nested = cu.claimNested(tc, className!!)`; widened the catch from
     `ReflectiveOperationException` to `Exception`.
   - `IOException` import left in place — still used elsewhere in Ops.kt (line 822 and
     the `IOExceptionMessages` call sites).

3. **StaticCodeInfo.kt**: added `@JvmField var programIndex: Int = -1` immediately after
   `engineTarget` (was line 72).

4. **CodeEngine.kt**: added `CodeEngines.materialize(sci)` and `CodeEngines.codeRunUnit(sci, cu, tc, cf, csd, args)`
   after `codeRun`, verbatim from the brief.

5. **unit/ProgramEntry.kt**: new file, verbatim from the brief — `object ProgramEntry` with
   `fun enter(tc, cr, csd, resume, args)` (builds a `CallFrame`, calls `CodeEngines.codeRunUnit`,
   handles `ControlException` vs. other `Throwable` the same way the emitted stub's
   prelude/postlude would) and `val ENTER: MethodHandle` bound via `MethodHandles.lookup().findStatic(...)`.

## Commands run and output

- Build: `./gradlew :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars` → `BUILD SUCCESSFUL in 9s`.
  Only pre-existing warnings (unrelated `!!` redundancy, `ThreadDeath` deprecation, etc.); nothing
  new from the touched files or `ProgramEntry.kt`.
- Class-road smoke (from the rakudo worktree root):
  `RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'say(1+2)'` → `3`.
- Tests: `./gradlew :nqp-runtime:test` → `BUILD SUCCESSFUL in 1s`. Test XML
  (`nqp-runtime/build/test-results/test/TEST-org.raku.nqp.runtime.unit.UnitFormatTest.xml`)
  shows `tests="5" skipped="0" failures="0" errors="0"`.

## Files changed (nqp tree)

- `src/vm/jvm/runtime/org/raku/nqp/runtime/CompilationUnit.kt`
- `src/vm/jvm/runtime/org/raku/nqp/runtime/StaticCodeInfo.kt`
- `src/vm/jvm/runtime/org/raku/nqp/runtime/CodeEngine.kt`
- `src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt`
- `src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramEntry.kt` (new)

Committed as `96f0ca37d` with the brief's message and trailer verbatim. `git status --short`
in the nqp tree is clean after the commit — no files from the other session's in-progress
work (`nqp-truffle/src/main/java/org/raku/nqp/truffle/*.java`, `src/vm/jvm/QAST/Compiler.nqp`,
`src/vm/jvm/QAST/TruffleEncoder.nqp`) were touched, staged, or added.

## Self-review

- Completeness: all 6 steps done in order; Interfaces block names/signatures match exactly:
  `open fun engineProgram(idx: Int): String`, `open fun serializedBlob(): ByteBuffer?`,
  `open fun claimNested(tc: ThreadContext, name: String): CompilationUnit`,
  `open fun unitId(): String`, `open fun runDeserializeIfAvailable(tc)` on `CompilationUnit`;
  `@JvmField var programIndex: Int = -1` on `StaticCodeInfo`;
  `@JvmStatic fun materialize(sci): Any?` and `@JvmStatic fun codeRunUnit(sci, cu, tc, cf, csd, args)`
  on `CodeEngines`; `ProgramEntry.ENTER: MethodHandle` of the specified shape.
- No behaviour change on the class road: `programIndex` defaults to -1 and nothing in this
  task sets it to anything else (Task 3 is expected to do that); `materialize` returns `null`
  whenever `programIndex < 0`, so `codeRunUnit`/`ProgramEntry.enter` are unreachable dead code
  on the class road until something wires them in (nothing in this task does — `ProgramEntry`
  is not referenced from any existing code path). The class-road smoke printing `3` confirms
  `codeRunIdx`/`codeRun` (the pre-existing entry points) are untouched in behavior.
  `deserialize` and `jvmclaimnested` now route through `serializedBlob()`/`claimNested()`,
  which reproduce the prior resource-lookup and reflective-construction logic exactly (same
  method bodies, just relocated onto `CompilationUnit` as `open` methods) — confirmed by the
  passing smoke test, which exercises `deserialize` via BOOTSTRAP/CORE.c loading.
- Build output: `BUILD SUCCESSFUL`, no new warnings or errors attributable to the changed files.

## Concerns

- **Minor, brief-directed behavior change**: widening `jvmclaimnested`'s catch from
  `ReflectiveOperationException` to `Exception` also now catches the pre-existing internal
  `dieInternal` `RuntimeException` thrown inside the same try block for "Nested unit ...
  carries no block with cuid ...", double-wrapping that message inside
  "Could not load nested compilation unit ...: <original message>". This is an
  internal-consistency error path that should never trigger in practice (block-table
  corruption), and the brief explicitly directs this exact widening ("so a missing nested
  artifact reports through the same ... message"), so I made the change as specified rather
  than deviating. Flagging for visibility, not treating as a blocker.
- No other concerns. Build, smoke, and unit tests are all green; diff is scoped to exactly
  the 5 files the brief names.

## Fix round 1 (review finding, Important)

Review (via agent `im-curious-as`) confirmed the concern above and ruled it a real bug, not
just a benign edge case: `ControlException` extends `RuntimeException`, so the original
`catch (e: Exception)` around the whole `jvmclaimnested` body could catch and re-wrap a
legitimate NQP-level control unwind coming out of `claimNested`'s
`initializeCompilationUnit(tc, false)`, in addition to double-wrapping the function's own
cuid-mismatch `dieInternal`. Controller ruling (overriding the brief's literal instruction):
wrap only the `cu.claimNested(tc, className!!)` call itself, re-throwing `ControlException`
unchanged and only re-wrapping other `Exception`s; move everything else (claimedNestedUnits
registration, byCuid map, the idx/cuid loop and its own dieInternal, table growth) outside the
try.

**Change made** (`src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt`, `jvmclaimnested`):

```kotlin
        val nested = try {
            cu.claimNested(tc, className!!)
        } catch (e: ControlException) {
            throw e
        } catch (e: Exception) {
            throw ExceptionHandling.dieInternal(tc, "Could not load nested compilation unit $className: $e")
        }
        tc.gc.claimedNestedUnits[className!!] = nested
        val byCuid = HashMap<String, CodeRef>()
        // ... unchanged body, no longer inside any try ...
```

`ControlException` needed no new import — already used elsewhere in `Ops.kt` (same package,
`org.raku.nqp.runtime`).

**Commands run:**

- Rebuild: `./gradlew :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars` → `BUILD SUCCESSFUL in 2s`.
  Only pre-existing warnings (the `className!!` non-null-assertion warning shifted line
  number but is the same pre-existing warning as before the fix).
- Class-road smoke: `RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'say(1+2)'`
  (run from the rakudo worktree root) → `3`.
- Nested-unit exercise: `RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'my $x := 42; class Foo { method bar() { $x } }; say(Foo.bar)'`
  → `42`.
- `./gradlew :nqp-runtime:test` → `BUILD SUCCESSFUL in 958ms`; `UnitFormatTest` XML still
  `tests="5" skipped="0" failures="0" errors="0"`.

**Commit:** `6d3d7d8c4` "unit artifact: claimNested wraps only the load; control unwinds and
internal dies pass through", `Ops.kt` only (verified via `git status --short` before and
after — no other file touched). `git status --short` is clean after the commit.
