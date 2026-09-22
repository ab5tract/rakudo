### Task 3: The traced CORE.c baseline

**Files:**
- Modify: none
- Ledger: the baseline row of the configuration table

**Interfaces:**
- Consumes: `truffle-trace-summary.raku` from Task 2.
- Produces: the reference wall clock, stage times, failed-root count and
  `min-too-large-size` that Tasks 4 to 7 are judged against.

**The standalone compile.** Taken from the Makefile's own recipe
(`Makefile:1312`), with `--output` redirected so `blib` keeps the built
state:

```bash
RAKUDO_RAKUAST=1 perl rakudo-j-build \
  --setting=NULL.c --ll-exception --optimize=3 --target=jar --stagestats \
  --output=$CLAUDE_JOB_DIR/tmp/m6-corec.jar \
  gen/jvm/CORE.c.setting
```

- [ ] **Step 1: Run the traced baseline compile**

```bash
JDK_JAVA_OPTIONS='-Dpolyglot.engine.TraceCompilation=true -Dpolyglot.engine.CompilationStatistics=true' \
NQP_CODE_CLOSE_AT_EXIT=1 RAKUDO_RAKUAST=1 \
raku tools/build/watched-run.raku \
  --log=$CLAUDE_JOB_DIR/tmp/m6-corec-baseline.log \
  --show-file=$CLAUDE_JOB_DIR/tmp/m6-corec-baseline.markers \
  --show='Stage' \
  -- perl rakudo-j-build --setting=NULL.c --ll-exception --optimize=3 \
       --target=jar --stagestats \
       --output=$CLAUDE_JOB_DIR/tmp/m6-corec.jar gen/jvm/CORE.c.setting
```

`CompilationStatistics` prints only with `NQP_CODE_CLOSE_AT_EXIT=1`.
Expected: `EXIT=0`, roughly 464 s.

- [ ] **Step 2: Summarize the trace**

```bash
raku tools/build/truffle-trace-summary.raku $CLAUDE_JOB_DIR/tmp/m6-corec-baseline.log
```

- [ ] **Step 3: Record the baseline row**

Write into the ledger and into the findings doc's table: wall clock,
`Stage parse` and `Stage optimize` seconds, `events`, `done`, `failed`,
the failure groups with counts and means, `min-too-large-size`, and
`total-compiler-ms`. Reference figures from the 2026-09-07 trace: 1880 s
of compiler time, 114 roots failing "code is too large" at a mean 6.4 s
each, 733 s wasted on them.

- [ ] **Step 4: Confirm the failure-line format**

**The real format is now known, not assumed.** Task 2's review
decompiled `TraceCompilationListener` from this tree's own
`nqp/build/jvm/share/truffle/truffle-runtime-25.2.4.jar`. Its
`FAILED_FORMAT` is verbatim:

```
opt failed engine=%-2d id=%-5d %-50s |Tier %d|Time %18s|Reason: %s|UTC %s|Src %s
```

Note `|Reason: %s|` **with a colon**, where `DEOPT_FORMAT`, `INV_FORMAT`
and `UNQUEUED_FORMAT` use `|Reason %s` without one. The colon falls on
exactly the verb this milestone depends on. Task 2's parser was
corrected to accept both, and its fixture now carries a real-format
line.

This step is therefore a confirmation, not a repair:

```bash
grep -m2 'opt failed' $CLAUDE_JOB_DIR/tmp/m6-corec-baseline.log
```

Confirm the reason text parses — the summarizer must report a non-empty
reason group, not an empty one. **If `min-too-large-size` prints `none`
while the failed count is above zero, STOP.** That combination is the
signature of a parse miss, not of a compile without oversized roots, and
the tool now prints `(failed=N, reasons-parsed=0)` beside it to say so.
Do not proceed to Task 4 behind it; a `none` read as "nothing was too
large" would silently skip the milestone's largest lever. Record the
outcome either way.

- [ ] **Step 5: Confirm named Sources reach the statistics**

The engine merge named Sources per block. Confirm the statistics block
shows real names rather than a single `nqp-code`:

```bash
grep -A20 'Compilation Statistics' $CLAUDE_JOB_DIR/tmp/m6-corec-baseline.log | head -30
```

Record the answer in the ledger. This closes a follow-up the engine
merge deferred to the perf session.

- [ ] **Step 6: Commit the ledger and the findings doc skeleton**

```bash
git add docs/jvm-perf-findings-2026-09.md docs/superpowers/plans/2026-09-12-jvm-milestone-6-compiler-workload.ledger.md
GIT_AUTHOR_DATE="2026-09-12 19:40:00 +0200" GIT_COMMITTER_DATE="2026-09-12 19:40:00 +0200" \
  git commit -m "M6 Task 3: the traced CORE.c baseline

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01T8zpD6QrhN6Pmp5TePheq6"
```

---

