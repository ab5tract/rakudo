## Task 9: Measure once, document, close the phase

**Files:**
- Modify: `tools/build/m7-rig.raku` (`parse-cold` captures `recorded=(\d+)` and `restored=(\d+)`; `cold-summary` prints them)
- Modify: `docs/jvm-unit-lazy-loading.md` ("The dispatch table": the slot schema, training, the consumer, verify, the knobs and counters)
- Modify: `docs/jvm-perf-findings-2026-09.md` ("Milestone 7, Phase C": (b) the rulings as landed, (c) the numbers, (d) the gates with clocks, (e) sizes and the compression question for the user, (f) deferred minors)
- Modify: the spec (a "Phase C: closed" note after the Phase C section, like Phase B's)
- Modify: `docs/jvm-truffle-only-plan.md` (position)
- Modify: memory `milestone-7-first-execution.md` + `MEMORY.md`

- [ ] **Step 1: Rig row `c`**: `raku tools/build/m7-rig.raku --tag=c --out=$CLAUDE_JOB_DIR/tmp/m7-rig --warm=proxy`
  (no `NQP_DISPATCH_RECORD` in the environment). Append the row to the
  ledger's table under `b`; copy `recorded=`/`restored=` from the best
  cold run's stderr next to it. The claim is on `recorded` (C0: about
  5023 -> under 500) and on the cold clocks; the histogram names what is
  left.
- [ ] **Step 2: Docs** as listed. The findings section gets the per-jar
  `unit.dispatch` sizes and the compression estimate (ruling 11) as a
  question for the user.
- [ ] **Step 3: Commit (rakudo)**: `Docs: milestone 7 Phase C closed -- the persisted miss, measured`.
- [ ] **Step 4: Rebase both trees onto their upstream mains and push**
  `--force-with-lease` to ab5tract (the standing handoff rule).

