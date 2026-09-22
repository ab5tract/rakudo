### Task 7: Knob 4 — `engine.CompilerThreads`

The 2026-09-07 profile found Truffle compiler threads at 61 % of all CPU
samples and JVMCI at 14 %, against the main thread's 17 %. This box has
16 cores.

**Interfaces:**
- Consumes: the winning configuration from Tasks 4 to 6.
- Produces: the final shipping configuration, which Task 11 adopts.

- [ ] **Step 1: Confirm the core count**

```bash
nproc
```

Use half of it. Record both numbers.

- [ ] **Step 2: Probe the option set**

NqpCheck probe with `-Dpolyglot.engine.CompilerThreads=<cores/2>` added
to the winning set. Required positive marker: `nqp-code check passed`.

**This option is experimental, so the probe will reject it even
though the engine accepts it. See the boxed note under Task 4 Step 2:
verify on the real engine path and do NOT report BLOCKED.**

- [ ] **Step 3: One compile**

Carry every knob Tasks 4 to 6 kept and add the thread count. Written out
with all of them kept; drop whichever their tasks dropped:

```bash
JDK_JAVA_OPTIONS='-Dpolyglot.engine.TraceCompilation=true -Dpolyglot.engine.CompilationStatistics=true -Dpolyglot.engine.Mode=latency -Dpolyglot.engine.MultiTier=true -Dpolyglot.engine.FirstTierCompilationThreshold=<value> -Dpolyglot.engine.LastTierCompilationThreshold=<value> -Dpolyglot.engine.CompilerThreads=<cores/2>' \
NQP_CODE_CLOSE_AT_EXIT=1 RAKUDO_RAKUAST=1 \
raku tools/build/watched-run.raku \
  --log=$CLAUDE_JOB_DIR/tmp/m6-corec-threads.log \
  --show-file=$CLAUDE_JOB_DIR/tmp/m6-corec-threads.markers \
  --show='Stage' \
  -- perl rakudo-j-build --setting=NULL.c --ll-exception --optimize=3 \
       --target=jar --stagestats \
       --output=$CLAUDE_JOB_DIR/tmp/m6-corec.jar gen/jvm/CORE.c.setting
```

- [ ] **Step 4: Summarize and decide**

```bash
raku tools/build/truffle-trace-summary.raku $CLAUDE_JOB_DIR/tmp/m6-corec-threads.log
```

Record the row and the verdict.

**This is the last compile of the sweep.** Per the user's rule, the
configuration in force here is the shipping configuration and there is
no confirmation build. State explicitly in the ledger which knobs are in
force at this point, as a single copy-pastable line; Task 11 adopts
exactly that.

- [ ] **Step 5: Commit the ledger**

```bash
git add docs/superpowers/plans/2026-09-12-jvm-milestone-6-compiler-workload.ledger.md
GIT_AUTHOR_DATE="2026-09-12 21:00:00 +0200" GIT_COMMITTER_DATE="2026-09-12 21:00:00 +0200" \
  git commit -m "M6 Task 7: CompilerThreads measured; the sweep's final configuration

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01T8zpD6QrhN6Pmp5TePheq6"
```

---

