# Task 9 report: milestone 1 gate for the JVM unit artifact

**Status: DONE.** No triage rounds were needed: the suite came in at the
campaign baseline on the first run, with only the two known cwd-relative
files failing from the rakudo root, and both pass from the `nqp/` directory.

Trees at the gate:

- nqp: `/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp`,
  branch `jesp-direct-lazy-records`, HEAD **`57460ccd7`** ("unit artifact: encode
  QAST::VM (the jvm alternative); a buffered write no longer NUL-pads the file"),
  clean; no nqp commit was needed by this task.
- rakudo: worktree `.claude/worktrees/jesp-direct-lazy-records`, branch
  `worktree-jesp-direct-lazy-records`, was `b424186d41`, now **`8942ed0bc2`**
  (the docs commit below).
- `java`: Oracle GraalVM 25.2.4+7.1 (25.0.4+7-LTS-jvmci-25.2-b20).

---

## Step 1: clean artifact build

```
NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 NQP_CODE_STRICT=1 \
  raku tools/build/watched-run.raku \
    --log=/home/longwalker/.claude/jobs/b945970f/tmp/build-gate.log \
    --show='> Task :stage' --show='BUILD' --show='rror' \
    -- ./nqp/gradlew -p nqp clean buildJvm
```

Verdict line (from the log):

```
=== EXIT=0 verdict=ok elapsed=273s ===
```

Gradle's own line: `BUILD SUCCESSFUL in 4m 32s`; `62 actionable tasks: 36
executed, 22 from cache, 4 up-to-date`. **Wall time 273 s.** No `rror`
marker fired. Stage progression from the log's elapsed markers: stage1
compiles 2 s -> 114 s (ModuleLoader, nqpmo, CoreSetting, JASTNodes,
QASTNode, QRegex, HLL, QAST, P6QRegex, NQP), stage2 compiles 133 s -> 245 s
in the same order, then P5QRegex and the jar/sync tasks to 273 s.

### Per-jar artifact check

Run as a script (the shell's `grep` function is unreliable on this box, so
the counts are `unzip -l $j | awk '/unit\.meta/{n++} END{print n+0}'` and the
same with `/\.class/`). Script kept at
`/home/longwalker/.claude/jobs/b945970f/tmp/jarcheck.sh`.

| jar | unit.meta | .class |
|---|---|---|
| stage2/JASTNodes.jar | 1 | 0 |
| stage2/ModuleLoader.jar | 1 | 0 |
| stage2/NQPCORE.setting.jar | 1 | 0 |
| stage2/NQPHLL.jar | 1 | 0 |
| stage2/nqp.jar | 1 | 0 |
| stage2/nqpmo.jar | 1 | 0 |
| stage2/NQPP6QRegex.jar | 1 | 0 |
| stage2/QAST.jar | 1 | 0 |
| stage2/QASTNode.jar | 1 | 0 |
| stage2/QRegex.jar | 1 | 0 |
| share/lib/JASTNodes.jar | 1 | 0 |
| share/lib/ModuleLoader.jar | 1 | 0 |
| share/lib/NQPCORE.setting.jar | 1 | 0 |
| share/lib/NQPHLL.jar | 1 | 0 |
| share/lib/nqp.jar | 1 | 0 |
| share/lib/nqpmo.jar | 1 | 0 |
| share/lib/NQPP5QRegex.jar | 1 | 0 |
| share/lib/NQPP6QRegex.jar | 1 | 0 |
| share/lib/QAST.jar | 1 | 0 |
| share/lib/QASTNode.jar | 1 | 0 |
| share/lib/QRegex.jar | 1 | 0 |

**21/21 jars are `meta=1 class=0`** — the ten stage2 targets and all eleven
share/lib jars, `NQPP5QRegex.jar` included (it exists only in share/lib, being
compiled by the stage2 compiler rather than being a stage2 target of its own).
Zero class files anywhere in the artifact set: the spec's one-compile sanity
check passes.

## Step 2: smoke through the new entry main

```
RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'say("artifact ok")'
```

Output: `artifact ok` (exactly one line, no warnings). The runner enters
through `UnitMain`.

## Step 3: full t/nqp through the runner

```
NQP_JVM_MAXHEAP=2g RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 \
  raku tools/build/watched-run.raku \
    --log=/home/longwalker/.claude/jobs/b945970f/tmp/tnqp-gate.log \
    --log-dir=/home/longwalker/.claude/jobs/b945970f/tmp/tnqp-gate-logs \
    -t=nqp/t/nqp --jobs=3 -- nqp/nqp-j-gradle
```

Verdict line: `113 of 115 ok in 487s`. **Wall time 487 s at 3 jobs.** (In
`-t` mode watched-run writes the per-run SUMMARY rather than the single-run
`EXIT=…` log, so that count line is the verdict.)

`/home/longwalker/.claude/jobs/b945970f/tmp/tnqp-gate-logs/SUMMARY`, complete:

```
ok 113 of 115
elapsed 487s
runner nqp/nqp-j-gradle
finished 2026-09-09T13:44:17.126479+02:00
FAIL nqp/t/nqp/019-file-ops.t exit 1 ok
FAIL nqp/t/nqp/063-slurp.t exit 1 ok
```

The only two non-ok files are exactly the two known cwd-relative ones, which
is the campaign's from-the-root baseline shape (111/113 then; 113/115 now,
the suite having grown by `t/nqp/122-ternary-typing.t` and
`t/nqp/123-unit-artifact.t`). Run from the nqp directory, both pass:

```
cd .../nqp && RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp-j-gradle t/nqp/019-file-ops.t
  -> 1..112, zero "not ok", EXIT=0
cd .../nqp && RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp-j-gradle t/nqp/063-slurp.t
  -> 1..1, ok 1 - File slurped, EXIT=0
```

**Honest suite number: t/nqp 115/115 on the artifact units through
`nqp-j-gradle`.** `123-unit-artifact.t` (the encoder-side gate from task 8)
is among the passes.

## Triage rounds

**None.** The suite met the baseline on the first run; no runtime regression
of the artifact road appeared, so no nqp commit, rebuild, or rerun was needed.
No `-2`/`-3` log files exist.

## Step 4: record

Milestone line written into both docs (identical text):

> milestone 1 DONE 2026-09-09: nqp stage2 as artifacts (nqp `57460ccd7`), all
> 21 stage2/share-lib jars `unit.meta`-only (zero `.class`), t/nqp 115/115
> through `nqp-j-gradle` (113/115 from the rakudo root: 019-file-ops and
> 063-slurp are cwd-relative); clean build 273 s, suite 487 s at 3 jobs

- `docs/jvm-truffle-only-plan.md`, "Position (2026-09-09)" table: row 5
  (**5 reflection-free unit**) and row 6 (**6 unit artifact, no class file**)
  each had their `starting now` text replaced by that line; row 6 keeps a
  tail noting milestones 2-4 (in-memory compiles, Rakudo units, stage0 +
  deletion) are open.
- `docs/jvm-strict-campaign-handoff.md`: the same line added in bold at the
  end of "Where we are", immediately before `## Runtime regressions of the
  first strict-green build`.

Commit (rakudo tree, only those two files staged by path):

```
8942ed0bc2 docs: unit artifact milestone 1 landed (nqp stage2 as artifacts, t/nqp through the runner)
 2 files changed, 4 insertions(+), 2 deletions(-)
```

with the two required trailer lines.

## Pushes

Both non-force, both fast-forward:

```
rakudo: git push ab5tract worktree-jesp-direct-lazy-records
  To github.com:ab5tract/rakudo.git
     b424186d41..8942ed0bc2  worktree-jesp-direct-lazy-records -> worktree-jesp-direct-lazy-records

nqp:    git push ab5tract jesp-direct-lazy-records
  To github.com:ab5tract/nqp.git
     d13dcbf69..57460ccd7  jesp-direct-lazy-records -> jesp-direct-lazy-records

nqp:    git push origin jesp-direct-lazy-records
  To /home/longwalker/code/raku/x.core/rakudo/nqp
     d13dcbf69..57460ccd7  jesp-direct-lazy-records -> jesp-direct-lazy-records
```

(nqp's `origin` is the main checkout's nqp working tree at
`/home/longwalker/code/raku/x.core/rakudo/nqp`, so that push also lands the
artifact work in the main checkout's nqp repository.)

## New baseline recorded (forward only)

| number | value |
|---|---|
| clean `NQP_UNIT=1 clean buildJvm` | **273 s** |
| stage2/share-lib jars, all artifact | **21/21 `unit.meta`, 0 `.class`** |
| t/nqp through `nqp-j-gradle` | **115/115** (113/115 from the rakudo root) |
| t/nqp sweep wall time, 3 jobs | **487 s** |

## Note on the remaining spec-section-6 gate

Spec section 6's *post-completion* gate ("once, on the whole green
milestone-1 changeset") also calls for a Rakudo `make` on this nqp plus
`t/01-sanity` 25/25, proving the class road still works for Rakudo's units.
That is not part of this task's four steps and was not run here; it remains
the one outstanding item before milestone 1 is closed end to end.

## Artifacts of this run

- `/home/longwalker/.claude/jobs/b945970f/tmp/build-gate.log` (build)
- `/home/longwalker/.claude/jobs/b945970f/tmp/tnqp-gate-logs/` (suite; `SUMMARY` plus a log per file)
- `/home/longwalker/.claude/jobs/b945970f/tmp/019.out` (019-file-ops from the nqp dir)
- `/home/longwalker/.claude/jobs/b945970f/tmp/jarcheck.sh` (the per-jar check)
