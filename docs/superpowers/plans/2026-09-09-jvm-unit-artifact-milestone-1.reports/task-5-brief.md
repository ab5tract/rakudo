### Task 5: The dispatchers materialize a target on demand

**Files:**
- Modify: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt:673-683` (realize), `:773-777` (invoke), `:1090-1098` (adoptCallNode)

**Interfaces:**
- Consumes: `CodeEngines.materialize(sci)` (Task 2).

- [ ] **Step 1: realize**

At line 678-681, replace

```kotlin
            if (cn == null) {
                if (NqpRaw.staticInfo(lit).engineTarget != null) {
```

with

```kotlin
            if (cn == null) {
                if (hasTarget(NqpRaw.staticInfo(lit))) {
```

and add, next to `adoptCallNode`:

```kotlin
    /** A target exists or can be made from the unit (artifact road): the
     *  volatile read stays PE-visible, the compile goes behind a boundary. */
    private fun hasTarget(sci: StaticCodeInfo): Boolean =
        sci.engineTarget != null || (sci.programIndex >= 0 && materializeBoundary(sci) != null)

    @TruffleBoundary
    private fun materializeBoundary(sci: StaticCodeInfo): Any? = CodeEngines.materialize(sci)
```

(`StaticCodeInfo` and `CodeEngines` are `org.raku.nqp.runtime` imports; add them if the file lacks them.)

- [ ] **Step 2: invoke and adoptCallNode**

In `invoke` (line 774) replace `val target = callee.staticInfo.engineTarget` with `val target = CodeEngines.materialize(callee.staticInfo)`; the function is already a boundary. In `adoptCallNode` (line 1092) replace `val target = cr.staticInfo.engineTarget` with `val target = CodeEngines.materialize(cr.staticInfo)`.

- [ ] **Step 3: Build and smoke**

Run: `./nqp/gradlew -p nqp :nqp-truffle:jar syncRuntimeJars 2>&1 | tail -3` then `RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'sub f($x) { $x * 2 }; my $s := 0; my int $i := 0; while $i < 100000 { $s := $s + f($i); $i++ }; say($s)'`
Expected: `9999900000` (class-road blocks have `programIndex == -1`, so behaviour is unchanged).

- [ ] **Step 4: Commit (nqp tree)**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git add nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt && git commit -F - <<'EOF'
jesp/dispatch: materialize an artifact block's target on demand instead of waiting for a stub run

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRn8gLyZjirBAKS6urb3n4
EOF
```

---

