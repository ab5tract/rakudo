### Task 1: The clean build at HEAD

The tree's build products do not match HEAD. The stage and compiler jars
are from 2026-09-11 21:16 and the settings from 21:17-21:34, while nqp
`7e7aaca61` and `df564ddbb` both change the encoder, which needs a
`clean buildJvm` because the stage graph misses that edge. Evidence that
the runners are stale too: the generated `rakudo-j-build` still lists
`asm-9.10.1.jar` and `asm-tree-9.10.1.jar` on its classpath, and
milestone 5 deleted both.

Measuring on this state would repeat the trap that voided milestone 4's
numbers, where every runtime figure came from a setting that never
lowered native arithmetic.

**Files:**
- Modify: none (build only)
- Ledger: record every timing in the ledger twin

**Interfaces:**
- Produces: the milestone baseline — nqp clean build seconds, `make`
  seconds from the top, and the CORE.c stage times (parse, optimize).
  Every later task compares against these, not against milestone 5's.

- [ ] **Step 1: Confirm the toolchain**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records
java -version 2>&1 | head -2
```

Expected: `Oracle GraalVM 25.2.4`. If it is anything else, stop and say
so; every number in this milestone is void otherwise.

- [ ] **Step 2: Record the pre-build state in the ledger**

```bash
git log --oneline -1
git -C nqp log --oneline -1
stat -c '%y  %n' blib/CORE.c.setting.jar nqp/build/jvm/share/lib/nqp.jar
```

Write both hashes and both timestamps into the ledger. This is the
evidence for why the rebuild happens.

- [ ] **Step 3: Clean-build nqp**

```bash
raku tools/build/watched-run.raku \
  --log=$CLAUDE_JOB_DIR/tmp/m6-nqp-build.log \
  --show-file=$CLAUDE_JOB_DIR/tmp/m6-nqp-build.markers \
  --show='Stage' --show='BUILD' \
  -- ./nqp/gradlew -p nqp clean buildJvm
```

Expected: `EXIT=0`. Baseline to compare: 256 s at milestone 5. Record
the seconds in the ledger.

- [ ] **Step 4: Build Rakudo from the top**

```bash
raku tools/build/watched-run.raku \
  --log=$CLAUDE_JOB_DIR/tmp/m6-make.log \
  --show-file=$CLAUDE_JOB_DIR/tmp/m6-make.markers \
  --show='Compiling' --show='Stage' \
  -- make
```

Expected: `EXIT=0`. Baselines to compare: `make` 1054 s from the top,
CORE.c 464 s of it, parse 352.4 s, optimize 36.6 s.

If the build fails, the two unbuilt encoder commits are the first
suspects. Repairing that is inside this task; record the diagnosis and
the fix in the ledger and amend rather than opening a new task.

- [ ] **Step 5: Record the baseline numbers**

From `m6-make.log`, extract the `Stage parse`, `Stage optimize` and
total lines for CORE.c, plus the whole-make wall clock. Write a table
into the ledger:

| clock | milestone 5 | milestone 6 baseline |
|---|---|---|
| nqp clean buildJvm | 256 s | |
| make from the top | 1054 s | |
| CORE.c total | 464 s | |
| CORE.c parse | 352.4 s | |
| CORE.c optimize | 36.6 s | |

- [ ] **Step 6: Gate — sanity**

```bash
RAKUDO_RAKUAST=1 raku tools/build/evalserver-sweep.raku --chunk=25 --jobs=1 --heap=8 t/01-sanity
```

Expected: 25 files, 0 failures. `--chunk=25` is the total file count, so
no server is replaced mid-run.

- [ ] **Step 7: Gate — the nqp suite**

```bash
raku tools/build/watched-run.raku \
  --log=$CLAUDE_JOB_DIR/tmp/m6-nqp-suite.log \
  --show-file=$CLAUDE_JOB_DIR/tmp/m6-nqp-suite.markers \
  --show='Failed' \
  -- ./nqp/gradlew -p nqp testNqp
```

`testNqp` is the task that runs the 151-file nqp suite (t/nqp, t/hll,
t/qregex, t/p5regex, t/qast, t/jvm, t/serialization, t/nativecall).
Plain `test` is Gradle's Java and Kotlin unit-test task and is NOT this
gate.

Expected: the nine known reds and no others — `t/jvm/01-continuations`
3/22, `t/jvm/11-dispatch` 20/160, `t/nqp/021` 6/33, `t/nqp/022` 1/7,
`t/nqp/044` 1/62, `t/nqp/112` 2/26, `t/p5regex` 3/182, `t/qast`
175/184, `t/qregex` 21/845. Any tenth red stops the milestone; diagnose
before continuing.

- [ ] **Step 8: Gate — the jar census**

```bash
raku tools/build/jar-census.raku nqp/build/jvm/share/lib/*.jar
```

Expected: every jar reported `unit.meta`-only, zero `.class`.

- [ ] **Step 9: Commit the ledger**

```bash
git add docs/superpowers/plans/2026-09-12-jvm-milestone-6-compiler-workload.ledger.md
GIT_AUTHOR_DATE="2026-09-12 19:00:00 +0200" GIT_COMMITTER_DATE="2026-09-12 19:00:00 +0200" \
  git commit -m "M6 Task 1: the clean build at HEAD is the milestone baseline

The tree's build products predated two encoder commits (nqp 7e7aaca61,
df564ddbb), which need a clean buildJvm because the stage graph misses
that edge. Numbers in the ledger; they replace milestone 5's.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01T8zpD6QrhN6Pmp5TePheq6"
```

---

