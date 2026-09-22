## Task 6: End to end by hand, before the builds change

**Files:** none (ledger only).

- [ ] **Step 1: Rebuild the runtime jars.** Restart no server (none running).
- [ ] **Step 2: Train nqp's lib jars by hand**:
  `cd <root>/nqp && NQP_DISPATCH_RECORD=all NQP_DISPATCH_STATS=1 ./nqp-j-gradle -e '' 2>&1 | grep -E 'dispatch-record|dispatch stats'`
  Expected: one `dispatch-record: wrote N slots ... to <path>` line per
  loaded jar under `nqp/build/jvm/share/lib` (nqp.jar, NQPCORE,
  NQPHLL, QAST, QASTNode, QRegex, nqpmo, ModuleLoader, NQPP6QRegex as
  loaded), and the stats line with `recorded=` about 1300-1500.
- [ ] **Step 3: The consumer**: the same command WITHOUT
  `NQP_DISPATCH_RECORD`. Expected: `restored=` about the previous
  `recorded`, `recorded=` under 100, `dropped=` small. Record all four.
- [ ] **Step 4: Verify**: `NQP_DISPATCH_PERSIST=verify` on the same
  command, expecting `dispatch-verify: matched=N mismatched=0 unseen=M`.
  Any mismatch is a Task 3/4 bug: fix it (the two texts say what), amend
  the commit, redo Steps 2-4.
- [ ] **Step 5: Rakudo**: `cd <root> && NQP_DISPATCH_RECORD=all NQP_DISPATCH_STATS=1 RAKUDO_RAKUAST=1 ./rakudo-j -e '' 2>&1 | grep -E 'dispatch-record|dispatch stats'`
  (writes `blib/*.jar`, `rakudo.jar` and nqp's lib jars again), then the
  consumer run and the verify run as in Steps 3-4. Expected on the
  consumer run: `recorded=` below 500 (C0's prediction), `mismatched=0`.
- [ ] **Step 6: Sizes**: `ls -l blib/CORE.c.setting.jar nqp/build/jvm/share/lib/QAST.jar` before and after, and
  `unzip -lv blib/CORE.c.setting.jar | grep dispatch`. Record the
  `unit.dispatch` sizes.
- [ ] **Step 7: `t/01-sanity` warm** (a server started AFTER the training):
  `RAKUDO_RAKUAST=1 perl t/harness5 --jvm --evalserver t/01-sanity`, 25/25,
  with the wall time. Then the same with `NQP_DISPATCH_PERSIST=verify`
  exported and the server's stderr captured: zero `MISMATCH` lines.
- [ ] **Step 8: Ledger**: every number above.

