### Task 9: Milestone 1 gate

**Files:**
- Modify (docs, rakudo tree): `docs/jvm-truffle-only-plan.md` (Position table rows 5 and 6), `docs/jvm-strict-campaign-handoff.md` (a "milestone 1" note)

- [ ] **Step 1: Clean artifact build**

```bash
NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 NQP_CODE_STRICT=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/b945970f/tmp/build-gate.log --show='> Task :stage' --show='BUILD' --show='rror' -- ./nqp/gradlew -p nqp clean buildJvm
```

Expected: `BUILD SUCCESSFUL`; record the wall time from the log's last elapsed marker. Then:

```bash
for j in nqp/build/jvm/stage2/*.jar nqp/build/jvm/share/lib/*.jar; do echo "$j meta=$(unzip -l $j | grep -c 'unit.meta') class=$(unzip -l $j | grep -c '\.class')"; done
```

Expected: every line `meta=1 class=0` (NQPP5QRegex.jar included, it is compiled by the stage2 compiler).

- [ ] **Step 2: Smoke**

`RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'say("artifact ok")'`
Expected: `artifact ok`.

- [ ] **Step 3: Full t/nqp through the runner**

From the rakudo worktree root, the campaign's own command:

```bash
NQP_JVM_MAXHEAP=2g RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/b945970f/tmp/tnqp-gate.log -t=nqp/t/nqp --jobs=3 -- nqp/nqp-j-gradle
```

Expected: 113 files pass (019-file-ops and 063-slurp are cwd-relative and pass only from the `nqp/` directory; 111/113 from the root is the campaign's baseline). Anything else failing is a runtime regression: triage with `NQP_CODE_WHY=1`/`NQP_CODE_TRACE=1` per the handoff doc's playbook, fix, rebuild (one compile per change), rerun.

- [ ] **Step 4: Record**

In `docs/jvm-truffle-only-plan.md`'s Position table, rows 5 and 6 become `milestone 1 DONE <date>: nqp stage2 as artifacts (nqp <hash>), t/nqp <n>/113 through the runner; build <s> s, suite <s> s`. Append the same line under "Where we are" in `docs/jvm-strict-campaign-handoff.md`. Commit in the rakudo tree:

```bash
git add docs/jvm-truffle-only-plan.md docs/jvm-strict-campaign-handoff.md && git commit -F - <<'EOF'
docs: unit artifact milestone 1 landed (nqp stage2 as artifacts, t/nqp through the runner)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRn8gLyZjirBAKS6urb3n4
EOF
```

Push both trees: `git push ab5tract worktree-jesp-direct-lazy-records` (rakudo) and, in the nqp dir, `git push ab5tract jesp-direct-lazy-records && git push origin jesp-direct-lazy-records`.

---

