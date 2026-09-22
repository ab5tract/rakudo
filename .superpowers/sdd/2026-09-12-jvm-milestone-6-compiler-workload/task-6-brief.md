### Task 6: Knob 3 — tier policy

Four options, measured as one configuration because they express a
single policy: compile run-once code less eagerly.

```
-Dpolyglot.engine.Mode=latency
-Dpolyglot.engine.MultiTier=true
-Dpolyglot.engine.FirstTierCompilationThreshold=<default x 4>
-Dpolyglot.engine.LastTierCompilationThreshold=<default x 4>
```

There is no `engine.CompilationThreshold`; naming it is the usual
mistake.

**Interfaces:**
- Consumes: the winning configuration from Tasks 4 and 5.
- Produces: a keep-or-drop verdict for tier policy.

- [ ] **Step 1: Read the defaults**

```bash
java --module-path nqp/build/jvm/share/truffle \
  --add-modules org.graalvm.truffle,org.graalvm.truffle.runtime \
  -XX:+UseJVMCICompiler -Dpolyglot.engine.Help=true -version 2>&1 | grep -i 'TierCompilationThreshold'
```

Record the printed defaults in the ledger, then use four times each. If
the help output does not name them, use 1000 and 10000 and record that
these are chosen values, not multiples of an observed default.

- [ ] **Step 2: Probe the option set**

Run the NqpCheck probe from Task 5 Step 1 with all four options in
`JDK_JAVA_OPTIONS`. Required positive marker: `nqp-code check passed`.

**This option is experimental, so the probe will reject it even
though the engine accepts it. See the boxed note under Task 4 Step 2:
verify on the real engine path and do NOT report BLOCKED.**

- [ ] **Step 3: One compile**

Carry every knob Tasks 4 and 5 kept, and add the four tier options.
Written out with a kept `NQP_CODE_MAX_COMPILE`; drop that prefix if Task
4 dropped it, and drop `PartialBlockCompilation` if Task 5 dropped it:

```bash
JDK_JAVA_OPTIONS='-Dpolyglot.engine.TraceCompilation=true -Dpolyglot.engine.CompilationStatistics=true -Dpolyglot.engine.Mode=latency -Dpolyglot.engine.MultiTier=true -Dpolyglot.engine.FirstTierCompilationThreshold=<value> -Dpolyglot.engine.LastTierCompilationThreshold=<value>' \
NQP_CODE_CLOSE_AT_EXIT=1 RAKUDO_RAKUAST=1 \
raku tools/build/watched-run.raku \
  --log=$CLAUDE_JOB_DIR/tmp/m6-corec-tier.log \
  --show-file=$CLAUDE_JOB_DIR/tmp/m6-corec-tier.markers \
  --show='Stage' \
  -- perl rakudo-j-build --setting=NULL.c --ll-exception --optimize=3 \
       --target=jar --stagestats \
       --output=$CLAUDE_JOB_DIR/tmp/m6-corec.jar gen/jvm/CORE.c.setting
```

**`PartialBlockCompilation` is deliberately absent from this command.**
Task 5 established it defaults to true, so writing it out sets nothing
and would be the exact habit the screening rule warns against. Task 5
was DROPped, so nothing is carried from it.

Write the exact command you ran into the ledger, since the carried set
is what makes this configuration reproducible.

- [ ] **Step 4: Summarize and decide**

```bash
raku tools/build/truffle-trace-summary.raku $CLAUDE_JOB_DIR/tmp/m6-corec-tier.log
```

Record the row and the verdict. Expect the `done` count to fall and
`total-compiler-ms` with it; the wall clock is what decides.

- [ ] **Step 5: Commit the ledger**

```bash
git add docs/superpowers/plans/2026-09-12-jvm-milestone-6-compiler-workload.ledger.md
GIT_AUTHOR_DATE="2026-09-12 20:40:00 +0200" GIT_COMMITTER_DATE="2026-09-12 20:40:00 +0200" \
  git commit -m "M6 Task 6: tier policy measured

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01T8zpD6QrhN6Pmp5TePheq6"
```

---

