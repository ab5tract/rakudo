## Task 8: The verify gate and the off gate

**Files:** none (ledger; a fix wave if a mismatch appears).

- [ ] **Step 1: Smoke the mode through a server** (fail-fast rule): start
  the sweep on ONE nqp test file with `NQP_DISPATCH_PERSIST=verify`
  exported and find `dispatch-verify: on` in the server's captured
  stderr (the sweep's per-server log under its output directory; if the
  sweep does not capture server stderr, add a `--server-log=<file>`
  option to `tools/build/evalserver-sweep.raku` that redirects it — Raku,
  ten lines — before going on).
- [ ] **Step 2: Verify gate**: the nqp suite and `t/01-sanity` with
  `NQP_DISPATCH_PERSIST=verify`; then `grep -c 'dispatch-verify: MISMATCH'`
  over every server log: expect 0, and the `matched=`/`unseen=` totals
  recorded. A mismatch is a real finding: record the pair of texts in the
  ledger, fix the codec or the guard it names, amend Task 3/4's commits,
  and re-run this step.
- [ ] **Step 3: Off gate**: the same two runs with `NQP_DISPATCH_PERSIST=off`;
  the pass/fail lists must equal the default-mode runs of Task 7 (diff
  the sweep summaries).
- [ ] **Step 4: Ledger**: four wall times, the totals, the verdict.

