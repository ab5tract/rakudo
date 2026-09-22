### Task 10: The loop baseline and the slowEvals question

Milestone 5 left one unexplained number: on the plusquick road
`slowEvals` went 364 to 976 with every other dispatch counter identical,
and plusquick went 82.625 to 85.525 ns/op, a 3.5 % regression. The
milestone 5 spec assigned it to this session.

**Interfaces:**
- Consumes: the adopted configuration from Task 7.
- Produces: the hot-loop baseline, and either an explanation of the
  `slowEvals` jump or a written statement that it was not found and what
  was ruled out.

- [ ] **Step 1: The loop bench**

```bash
RAKUDO_RAKUAST=1 NQP_DISPATCH_STATS=1 ./rakudo-j docs/bench/jesp/plusquick.raku
```

Record ns/op and the dispatch-stats line (folded hits, misses, boundary
invokes, `slowEvals`). Reference: 85.525 ns/op, `hits=90247539
misses=11614 slowEvals=976`.

- [ ] **Step 2: The correctness smoke**

```bash
RAKUDO_RAKUAST=1 ./rakudo-j docs/bench/jesp/resume-smoke.raku
```

Its output must not change. This is a correctness check, not a
benchmark.

- [ ] **Step 3: Chase the slowEvals jump**

`slowEvals` counts dispatch evaluations that fell off the folded road.
The counter tripled while hits and misses held, so the suspects are the
milestone 5 layout sites rather than dispatch itself. Two concrete
leads, both recorded as open in the milestone 5 ledger:

1. `DecontSite` never calls `miss()` on a layout mismatch, so a
   mismatching site may be re-evaluating slowly without registering a
   miss. Read `DecontSite` and check whether a mismatch path reaches the
   slow evaluator without incrementing `misses`.
2. `BigIntSite` does not re-verify `rd.layout === layout`.

Time-box this to one hour of investigation. If neither lead explains it,
write what was ruled out and leave it open; an unexplained 3.5 % is a
finding, not a blocker.

- [ ] **Step 4: Record and commit**

Write the numbers and the `slowEvals` verdict into the findings doc.
```bash
git add docs/jvm-perf-findings-2026-09.md docs/superpowers/plans/2026-09-12-jvm-milestone-6-compiler-workload.ledger.md
GIT_AUTHOR_DATE="2026-09-12 22:00:00 +0200" GIT_COMMITTER_DATE="2026-09-12 22:00:00 +0200" \
  git commit -m "M6 Task 10: the loop baseline, and the slowEvals question

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01T8zpD6QrhN6Pmp5TePheq6"
```

---

