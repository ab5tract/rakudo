# Task 5 report: dispatchers materialize a target on demand

## Summary

All three sites in `nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt`
now go through `CodeEngines.materialize(sci)` instead of reading
`StaticCodeInfo.engineTarget` directly, so an artifact block's engine
target is available (compiled from the unit's program index) on first
dispatch, instead of only after a first run through a bytecode stub.
Class-road blocks (`programIndex == -1`) are unaffected: `materialize`
returns null immediately for them, same as the old direct
`engineTarget` read.

Line numbers below are from the file as found (slightly different from
the brief's approximate `:673-683` / `:773-777` / `:1090-1098`, but the
surrounding code matched verbatim).

## Changes, before/after

### Imports (new, ~line 34-42)

Added:
```kotlin
import org.raku.nqp.runtime.CodeEngines
...
import org.raku.nqp.runtime.StaticCodeInfo
```

### Site 1: `realize` (was line 683, now 685)

Before:
```kotlin
            if (cn == null) {
                if (NqpRaw.staticInfo(lit).engineTarget != null) {
```

After:
```kotlin
            if (cn == null) {
                if (hasTarget(NqpRaw.staticInfo(lit))) {
```

`realize` itself is not a `@TruffleBoundary` function (it's the PE-hot
outcome-execution path), so the check had to stay decomposed: `hasTarget`
does the volatile `engineTarget` read directly (PE-visible, no boundary
crossing when a target already exists), and only calls the boundary
helper `materializeBoundary` when `programIndex >= 0` and no target is
set yet.

### New helpers, next to `adoptCallNode` (~line 1091-1097)

```kotlin
    /** A target exists or can be made from the unit (artifact road): the
     *  volatile read stays PE-visible, the compile goes behind a boundary. */
    private fun hasTarget(sci: StaticCodeInfo): Boolean =
        sci.engineTarget != null || (sci.programIndex >= 0 && materializeBoundary(sci) != null)

    @TruffleBoundary
    private fun materializeBoundary(sci: StaticCodeInfo): Any? = CodeEngines.materialize(sci)
```

### Site 2: `invoke` (was line 773, now 775)

Before:
```kotlin
            val target = callee.staticInfo.engineTarget
```

After:
```kotlin
            val target = CodeEngines.materialize(callee.staticInfo)
```

`invoke` is already annotated `@TruffleBoundary`, so no new boundary
wrapper was needed here.

### Site 3: `adoptCallNode` (was line 1093, now 1103)

Before:
```kotlin
    private fun adoptCallNode(p: Program, cr: CodeRef, node: Node): DirectCallNode? {
        val target = cr.staticInfo.engineTarget
```

After:
```kotlin
    private fun adoptCallNode(p: Program, cr: CodeRef, node: Node): DirectCallNode? {
        val target = CodeEngines.materialize(cr.staticInfo)
```

`adoptCallNode` is also already `@TruffleBoundary`.

Full diff (13 insertions, 3 deletions, 1 file):
```
diff --git a/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt b/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt
index 7e31f73be..d7c79322a 100644
--- a/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt
+++ b/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt
@@ -34,12 +34,14 @@ import org.raku.nqp.dispatch.ValueSource
 import org.raku.nqp.runtime.ArgsExpectation
 import org.raku.nqp.runtime.CallFrame
 import org.raku.nqp.runtime.CallSiteDescriptor
+import org.raku.nqp.runtime.CodeEngines
 import org.raku.nqp.runtime.CodeRef
 import org.raku.nqp.runtime.ControlException
 import org.raku.nqp.runtime.ExceptionHandling
 import org.raku.nqp.runtime.HLLConfig
 import org.raku.nqp.runtime.Ops
 import org.raku.nqp.runtime.SaveStackException
+import org.raku.nqp.runtime.StaticCodeInfo
 import org.raku.nqp.runtime.ThreadContext
 import org.raku.nqp.sixmodel.STable
 import org.raku.nqp.sixmodel.SixModelObject
@@ -680,7 +682,7 @@ object NqpDispatch {
              * cycle. Re-adopt when the instruction's node changed, a few
              * times at most. */
             if (cn == null) {
-                if (NqpRaw.staticInfo(lit).engineTarget != null) {
+                if (hasTarget(NqpRaw.staticInfo(lit))) {
                     CompilerDirectives.transferToInterpreterAndInvalidate()
                     cn = adoptCallNode(p, lit, node)
                 }
@@ -770,7 +772,7 @@ object NqpDispatch {
                        descriptor: CallSiteDescriptor?, out: Array<Any?>) {
         if (STATS) count(invokes)
         if (callee is CodeRef) {
-            val target = callee.staticInfo.engineTarget
+            val target = CodeEngines.materialize(callee.staticInfo)
             if (target != null && callee.staticInfo.argsExpectation == ArgsExpectation.USE_BINDER) {
                 if (STATS) count(directs)
                 enterEngine(tc, callee, target as CallTarget, descriptor, out)
@@ -1086,11 +1088,19 @@ object NqpDispatch {
         }
     }
 
+    /** A target exists or can be made from the unit (artifact road): the
+     *  volatile read stays PE-visible, the compile goes behind a boundary. */
+    private fun hasTarget(sci: StaticCodeInfo): Boolean =
+        sci.engineTarget != null || (sci.programIndex >= 0 && materializeBoundary(sci) != null)
+
+    @TruffleBoundary
+    private fun materializeBoundary(sci: StaticCodeInfo): Any? = CodeEngines.materialize(sci)
+
     /** Adopts a call node for the callee's engine target, or null if the
      *  callee has no registered target yet (it has not run once). */
     @TruffleBoundary
     private fun adoptCallNode(p: Program, cr: CodeRef, node: Node): DirectCallNode? {
-        val target = cr.staticInfo.engineTarget
+        val target = CodeEngines.materialize(cr.staticInfo)
         if (target !is CallTarget || cr.staticInfo.argsExpectation != ArgsExpectation.USE_BINDER)
             return null
         val cn = node.insert(DirectCallNode.create(target))
```

## Commands run and output

1. Located the three sites and confirmed surrounding code matched the
   brief (`grep -n "engineTarget\|fun realize\|fun invoke\|fun adoptCallNode\|programIndex"`),
   and confirmed `invoke` and `adoptCallNode` already carry
   `@TruffleBoundary`.

2. Checked `StaticCodeInfo` (`src/vm/jvm/runtime/org/raku/nqp/runtime/StaticCodeInfo.kt`)
   and `CodeEngines.materialize` (`src/vm/jvm/runtime/org/raku/nqp/runtime/CodeEngine.kt:116`,
   Task 2's implementation) to confirm the contract: returns
   `sci.engineTarget` if set, else compiles from `sci.compUnit.engineProgram(sci.programIndex)`
   when `programIndex >= 0` (synchronized on `sci`), else null.

3. Build:
```
./nqp/gradlew -p nqp :nqp-truffle:jar syncRuntimeJars 2>&1 | tail -60
...
> Task :nqp-truffle:compileKotlin
w: .../NqpDispatch.kt:422:33 Condition is always 'true'.
w: .../NqpDispatch.kt:430:17 'when' is exhaustive so 'else' is redundant here.
w: .../NqpDispatch.kt:995:29 Elvis operator (?:) always returns the left operand of non-nullable type 'CodeRef'.
...
BUILD SUCCESSFUL in 1s
12 actionable tasks: 4 executed, 8 up-to-date
```
   The three Kotlin warnings are pre-existing (unrelated lines, 422/430/995 —
   none touched by this change) and did not fail the build.

4. Smoke:
```
RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'sub f($x) { $x * 2 }; my $s := 0; my int $i := 0; while $i < 100000 { $s := $s + f($i); $i++ }; say($s)'
9999900000
```
   Matches expected output exactly.

5. Commit (nqp tree, single file):
```
cd .../jesp-direct-lazy-records/nqp && git add nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt && git commit -F - <<'EOF'
jesp/dispatch: materialize an artifact block's target on demand instead of waiting for a stub run

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRn8gLyZjirBAKS6urb3n4
EOF
```
   Result: commit `816001582`, "1 file changed, 13 insertions(+), 3 deletions(-)".

   `git status` before staging showed only `NqpDispatch.kt` modified in
   the nqp tree — the other session's uncommitted Java/QAST files
   (mentioned in the task context) are not present as unstaged changes
   in this nqp checkout at this time, so there was nothing to avoid
   touching beyond staying scoped to the one file, which `git add
   nqp-truffle/.../NqpDispatch.kt` (not `-A`) guaranteed regardless.

## Files changed

- `/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt`
  (nqp tree, committed at `816001582`)

## Self-review

- All three sites changed, matching the brief's intent verbatim (the
  brief's own kotlin snippets were used as-is).
- `realize` is the PE-visible hot path: `hasTarget` performs the
  `sci.engineTarget != null` check as a plain (non-boundary) volatile
  read first via short-circuit `||`; the boundary (`materializeBoundary`,
  which calls `CodeEngines.materialize`, which does the synchronized
  compile) is only reached when that read misses AND
  `programIndex >= 0` — i.e. only on the artifact road, and only until
  the target is cached. A bytecode-bodied callee (`programIndex == -1`)
  or a not-yet-materialized class-road callee never crosses the
  boundary from this check.
- `invoke` and `adoptCallNode` were already `@TruffleBoundary`
  functions, so swapping the field read for `CodeEngines.materialize(...)`
  needed no new annotation — confirmed by reading both function
  signatures before editing.
- Class-road behaviour is unchanged: for `programIndex == -1`,
  `CodeEngines.materialize` returns `sci.engineTarget` (possibly null)
  without ever reaching the `programIndex < 0` early-return's sibling
  branch — identical semantics to the old direct field read. The smoke
  test (a plain, non-artifact `-e` program) printing the expected
  `9999900000` confirms this empirically.
- Did not touch any file outside `NqpDispatch.kt`; did not use
  `git add -A`; did not stash or restore anything.
- Every new code path here calls into pre-existing, already-reviewed
  `CodeEngines.materialize` (Task 2) rather than adding new logic of
  its own beyond the boundary-splitting `hasTarget`/`materializeBoundary`
  pair — no new bare prints or diagnostics were added, so nothing
  needed env-gating.

## Concerns

None. The build was clean (only pre-existing, unrelated warnings), the
smoke test matched exactly, and the diff is a minimal, mechanical
substitution as specified by the brief.
