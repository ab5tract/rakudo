### Task 5: Knob 2 — `engine.PartialBlockCompilation`

Where Task 4 refuses a big root outright, this splits it. The two are
alternatives, so this compile runs with Task 4's threshold **removed**.
If both help, Task 11 combines them.

**Interfaces:**
- Consumes: Task 4's verdict.
- Produces: a keep-or-drop verdict for partial block compilation.

- [ ] **Step 1: Probe the option set**

```bash
JDK_JAVA_OPTIONS='-Dpolyglot.engine.PartialBlockCompilation=true' \
java --module-path nqp/build/jvm/share/truffle \
  --add-modules org.graalvm.truffle,org.graalvm.truffle.runtime \
  --enable-native-access=org.graalvm.truffle --sun-misc-unsafe-memory-access=allow \
  -cp "nqp/build/jvm/share/runtime/nqp-runtime.jar:nqp/build/jvm/share/runtime/nqp-truffle.jar:nqp/build/jvm/share/runtime/kotlin-stdlib-2.4.10.jar:nqp/build/jvm/share/runtime/fastutil-8.5.19.jar:nqp/build/jvm/share/runtime/annotations-13.0.jar:nqp/build/jvm/share/runtime/lz4-java-1.8.0.jar" \
  org.raku.nqp.truffle.NqpCheck
```

Required positive marker: `nqp-code check passed`. A rejected option
prints a `PolyglotImpl.buildEngine` stack trace instead; that is the
whole point of probing.

- [ ] **Step 2: One compile**

`NQP_CODE_MAX_COMPILE` is deliberately **not set** here, so the big
roots are split rather than refused:

```bash
JDK_JAVA_OPTIONS='-Dpolyglot.engine.TraceCompilation=true -Dpolyglot.engine.CompilationStatistics=true -Dpolyglot.engine.PartialBlockCompilation=true' \
NQP_CODE_CLOSE_AT_EXIT=1 RAKUDO_RAKUAST=1 \
raku tools/build/watched-run.raku \
  --log=$CLAUDE_JOB_DIR/tmp/m6-corec-partialblock.log \
  --show-file=$CLAUDE_JOB_DIR/tmp/m6-corec-partialblock.markers \
  --show='Stage' \
  -- perl rakudo-j-build --setting=NULL.c --ll-exception --optimize=3 \
       --target=jar --stagestats \
       --output=$CLAUDE_JOB_DIR/tmp/m6-corec.jar gen/jvm/CORE.c.setting
```

- [ ] **Step 3: Summarize and decide**

```bash
raku tools/build/truffle-trace-summary.raku $CLAUDE_JOB_DIR/tmp/m6-corec-partialblock.log
```

Record the row. Keep whichever of Task 4 and Task 5 gave the lower wall
clock; if both beat the baseline, carry both forward and say so.

- [ ] **Step 4: Commit the ledger**

```bash
git add docs/superpowers/plans/2026-09-12-jvm-milestone-6-compiler-workload.ledger.md
GIT_AUTHOR_DATE="2026-09-12 20:20:00 +0200" GIT_COMMITTER_DATE="2026-09-12 20:20:00 +0200" \
  git commit -m "M6 Task 5: PartialBlockCompilation measured

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01T8zpD6QrhN6Pmp5TePheq6"
```

---

