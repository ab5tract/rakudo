### Task 5: t/ through the eval server after the deletions (sweep 2)

**Files:** none modified; report `task-5-report.md`.

**Interfaces:**
- Consumes: Task 4's build; Task 3's report (the baseline lists and wall clock).
- Produces: the diff sweep 2 minus sweep 1.

- [ ] **Step 1: The sweep, same recipe, two-hour ceiling**

Kill stale servers (`pgrep -f org.raku.nqp.tools.EvalServer` empty), then:

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --max=7200 --stall=1500 --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t5-sweep.log --show='chunk' --show='files in' --show='FAIL' -- raku tools/build/evalserver-sweep.raku t/01-sanity t/02-rakudo t/03-jvm t/04-nativecall t/05-messages t/06-telemetry t/07-pod-to-text t/08-performance t/10-qast t/13-experimental t/14-smoke
```

- [ ] **Step 2: Diff against sweep 1**

Expected: the failing-file set is identical to Task 3's. Any file failing here and not there is a deletion regression: rerun it alone with `NQP_CODE_WHY=1`; the likeliest shapes are a `raw` wrapper that never encoded before (the refusal hid it) or a block the size gate used to refuse (large BEGIN bodies). Fix in an amend to Task 4's nqp commit, runtime-only rebuild or stage build as the file dictates, and rerun that file. A file passing here and failing in sweep 1 is recorded as fixed-by-deletion.

- [ ] **Step 3: Report**

`task-5-report.md`: the table, the diff, the wall clock against Task 3's.

---

