### Task 3: t/ through the eval server on artifact units (sweep 1)

**Files:** none modified; report `docs/superpowers/plans/2026-09-09-jvm-unit-artifact-milestone-3.reports/task-3-report.md` (controller-written).

**Interfaces:**
- Consumes: Task 2's build (`rakudo.jar` artifact, `rakudo-eval-server` runner unchanged, `t/harness5 --jvm --evalserver` passing `-app ./rakudo.jar`, `tools/build/evalserver-sweep.raku` sizing its pool from MemAvailable).
- Produces: the failing-file list and wall clock per directory, the baseline for Task 5's diff.

- [ ] **Step 1: Memory check**

`grep MemAvailable /proc/meminfo`; the sweep budgets `jobs x (heap + 3g)` against it and refuses an over-commit. Kill any stale server first: `pgrep -f org.raku.nqp.tools.EvalServer` must be empty (the runner's own guard also refuses to start over a live one).

- [ ] **Step 2: The sweep, two-hour ceiling**

Background job from the rakudo worktree root; Monitor the log at >= 90 s cadence and report progress every 90 s:

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --max=7200 --stall=1500 --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t3-sweep.log --show='chunk' --show='files in' --show='FAIL' -- raku tools/build/evalserver-sweep.raku t/01-sanity t/02-rakudo t/03-jvm t/04-nativecall t/05-messages t/06-telemetry t/07-pod-to-text t/08-performance t/10-qast t/13-experimental t/14-smoke
```

Expected: `N files in S s across C servers` and a chunk-failure list. The 2026-09-05 record (one warm server, `/home/longwalker/code/raku/x.core/rakudo/docs/jvm-full-suite-run-2026-09-05.md`, table at lines 9-21) is the comparison: 01-sanity 0 fail (1m04), 02-rakudo 20 fail (46m33, 290 files), 03-jvm 0 (0m17), 04-nativecall 2 (5m46), 05-messages 4 (8m59), 06-telemetry 0 (2m25), 07-pod-to-text 0 (0m20), 08-performance 2 (10m06), 10-qast 0 (0m11); 13-experimental and 14-smoke have no record. If the ceiling fires (`over the 7200s ceiling, giving up`), the report says which chunks finished, and the remaining directories run in a second invocation under their own `--max` only if the user asks; the wall clock IS the finding.

- [ ] **Step 3: Triage the diff**

For every failing file NOT in the 2026-09-05 list: rerun it alone (`RAKUDO_RAKUAST=1 ./rakudo-j -Ilib <file>`), then with `NQP_CODE_WHY=1 2>&1 | grep -E 'unit record|unit artifact|no engine program|code-bail'`. A die naming a block with "has no engine program" is an encoder refusal in that test (a shape the class road hid): report the block and the `NQP_CODE_BAIL=1` reason; a shape that recurs across files is fixed in an amend to Task 1's commit, followed by a runtime-only rebuild if it is Kotlin, or a stage build (Task 1 Step 8) if it is the encoder. Anything else is a Rakudo-level regression: reported with its first differing line, not fixed here unless one-line.

- [ ] **Step 4: Report**

`task-3-report.md`: the per-directory table (files, result, fails, wall) in the 2026-09-05 layout, the new-vs-known failing lists, the total wall clock (the number the user is waiting for before t/spec), and whether the ceiling fired.

---

