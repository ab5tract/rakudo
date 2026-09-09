### Task 8: Runners enter through UnitMain

**Files:**
- Modify: `nqp/buildSrc/src/main/kotlin/GenerateRunnerTask.kt:140` (main class)
- Modify: `nqp/tools/templates/jvm/nqp-j.in` (last line)

**Interfaces:**
- Produces: `nqp/nqp-j-gradle` entering through `org.raku.nqp.runtime.unit.UnitMain "$LIB_DIR/nqp.jar"`.

- [ ] **Step 1: The runner's main class**

In `GenerateRunnerTask.kt` line 140 change the tail of the exec line from `-cp "${'$'}CP" nqp "${'$'}@"` to `-cp "${'$'}CP" org.raku.nqp.runtime.unit.UnitMain "${'$'}{LIB_DIR}/nqp.jar" "${'$'}@"`. `UnitMain` takes either road, so this is correct before and after the stage2 flip.

In `tools/templates/jvm/nqp-j.in`, the last line: replace `-cp "@cur_dir@@envvar(LIB_DIR)@" nqp "@sh_allparams@"` with `-cp "@cur_dir@@envvar(LIB_DIR)@" org.raku.nqp.runtime.unit.UnitMain "@cur_dir@@envvar(LIB_DIR)@/nqp.jar" "@sh_allparams@"`.

- [ ] **Step 2: Regenerate and smoke**

Run: `./nqp/gradlew -p nqp generateRunner 2>&1 | tail -3`, then `RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'say(nqp::x("ab", 3))'`
Expected: `ababab`.

- [ ] **Step 3: Commit (nqp tree)**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git add buildSrc/src/main/kotlin/GenerateRunnerTask.kt tools/templates/jvm/nqp-j.in && git commit -F - <<'EOF'
runners enter through UnitMain (either road)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRn8gLyZjirBAKS6urb3n4
EOF
```

---

