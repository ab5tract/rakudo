# Task 8 report: the verify gate and the off gate

Root for every command: `/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records`
(ROOT below). `RAKUDO_RAKUAST=1` exported on every command. No build, no source
edit, no commit, no tooling change. Logs under
`/home/longwalker/.claude/jobs/ba3ab3a7/tmp/task8/`.

**Verdict: DONE.** Verify gate green with 0 mismatches in both runs; off gate
identical to the default-mode reference; the extra default-mode nqp suite
(coordinator ruling 22, on the post-`make` lib jars) green as well.

---

## Step 1: smoke the mode through a server

Command (from ROOT, env `RAKUDO_RAKUAST=1 NQP_DISPATCH_PERSIST=verify
NQP_DISPATCH_VERIFY_LOG=/home/longwalker/.claude/jobs/ba3ab3a7/tmp/task8/smoke-verify.log`):

    raku tools/build/evalserver-sweep.raku --suite=nqp --jobs=1 '--chunk=*' nqp/t/nqp/001-literals.t

Wall time 2.5 s (sweep's own clock: `1 files in 2s across 1 server(s)`, chunk `ok`).

`smoke-verify.log` verbatim:

    [289217] dispatch-verify: on
    [289217] dispatch-verify: matched=1637 byOutcome=8 mismatched=0 unseen=249

Both lines come from the eval-server process the sweep starts, i.e. the pass-through
works with no change: `run-nqp-chunk` starts the server with `:ENV(%*ENV, ...)` and
`run-rakudo-chunk`/`t/harness5` likewise inherit the ambient environment, so
`NQP_DISPATCH_PERSIST` and `NQP_DISPATCH_VERIFY_LOG` reach every server and child.
**No `tools/build/evalserver-sweep.raku` change was needed; no file was edited in this task.**

Note (my error, not a defect in the tree): the first two smoke attempts named
`nqp/t/nqp/01-literals.t`, which does not exist (nqp's files are `001-literals.t`).
The sweep passes an explicit non-directory target through without an existence check,
so the run reported `No plan found in TAP output` / chunk FAIL rather than "no such
file". A control run of the same bogus name in DEFAULT mode failed identically, which
is how it was identified as a naming mistake rather than a verify-mode regression.
(Optional future hardening, not done here: `die` on an explicit target that is not an
existing file.)

## Step 2: the verify gate

### nqp suite

    raku tools/build/watched-run.raku --log=.../verify-nqp-suite.log \
        --show='red=' --show='green=' --show='FAIL' --stall=7200 --max=10800 -- \
        raku tools/build/evalserver-sweep.raku --suite=nqp '--chunk=*' --jobs=1

env: `RAKUDO_RAKUAST=1 NQP_DISPATCH_PERSIST=verify NQP_DISPATCH_VERIFY_LOG=.../verify-nqp-suite.verifylog`

Log verbatim:

    nqp: 155 files, 1 chunk(s) of 155, 1 server(s) x 6g heap + 3g off-heap (9g of a 22g budget, 25g available)
    [204s] chunk 1/1: ok

    155 files in 204s across 1 server(s)
    === EXIT=0 verdict=ok elapsed=204s ===

**Wall time 204 s** (reference, Task 7 default mode: 196 s). Red list: empty
(exit 0; the sweep prints a per-chunk failure block and file lines only for
failing chunks, and there are none).

`grep -c 'dispatch-verify: MISMATCH' verify-nqp-suite.verifylog` -> **0**

11 processes wrote to the log (11 `dispatch-verify: on` lines, 11 summary lines).
Per-process summaries verbatim:

    [290170] dispatch-verify: matched=1009 byOutcome=4 mismatched=0 unseen=73
    [290314] dispatch-verify: matched=1708 byOutcome=8 mismatched=0 unseen=1135
    [290384] dispatch-verify: matched=1655 byOutcome=8 mismatched=0 unseen=399
    [290456] dispatch-verify: matched=1706 byOutcome=8 mismatched=0 unseen=1131
    [290526] dispatch-verify: matched=1706 byOutcome=8 mismatched=0 unseen=1143
    [290592] dispatch-verify: matched=1232 byOutcome=8 mismatched=0 unseen=140
    [290661] dispatch-verify: matched=1644 byOutcome=8 mismatched=0 unseen=180
    [290729] dispatch-verify: matched=1644 byOutcome=8 mismatched=0 unseen=180
    [289345] dispatch-verify: matched=255709 byOutcome=1233 mismatched=0 unseen=110682
    [291140] dispatch-verify: matched=1682 byOutcome=8 mismatched=0 unseen=772
    [291209] dispatch-verify: matched=1683 byOutcome=8 mismatched=0 unseen=782

(pid 289345 is the long-lived eval server; the other ten are children some tests spawn.)

**Summed over the 11 processes: matched=271378 byOutcome=1309 mismatched=0 unseen=116617.**

### t/01-sanity

    raku tools/build/watched-run.raku --log=.../verify-sanity.log \
        --show='Files=' --show='Result' --show='not ok' -- \
        perl t/harness5 --jvm --evalserver t/01-sanity

env: `RAKUDO_RAKUAST=1 NQP_DISPATCH_PERSIST=verify NQP_DISPATCH_VERIFY_LOG=.../verify-sanity.verifylog`

Log verbatim (tail):

    Files=25, Tests=303, 50 wallclock secs ( 0.10 usr  0.03 sys + 16.94 cusr  0.81 csys = 17.88 CPU)
    Result: PASS
    === EXIT=0 verdict=ok elapsed=51s ===

**25/25 files, 303 tests, PASS, wall time 51 s** (reference, Task 7: 25/25, 303 tests, 55-56 s).
No `not ok` line in the log. Red list: empty.

`grep -c 'dispatch-verify: MISMATCH' verify-sanity.verifylog` -> **0**

2 processes wrote to the log. Summaries verbatim:

    [291590] dispatch-verify: matched=4425 byOutcome=14 mismatched=0 unseen=2756
    [291323] dispatch-verify: matched=113016 byOutcome=313 mismatched=0 unseen=71185

**Summed over the 2 processes: matched=117441 byOutcome=327 mismatched=0 unseen=73941.**

### Reading the counters

`matched` = the fresh recording's text equals an applicable persisted program's text;
`byOutcome` = the texts differ but the outcomes evaluate the same on the call's own
arguments (the polymorphic-site case the codec documents); `mismatched` = a real
divergence (none); `unseen` = a fresh recording for which no persisted program applied
(an untrained site, or none whose guards matched this call) -- expected to be large,
because verify keeps the restored programs aside so every site keeps recording,
including the many sites the trivial training program never reached.

**Grand total across both verify gates (13 processes):
matched=388819 byOutcome=1636 mismatched=0 unseen=190558. Zero MISMATCH blocks anywhere.**

## Step 3: the off gate

Same two commands with `NQP_DISPATCH_PERSIST=off` exported and no verify log
(`NQP_DISPATCH_VERIFY_LOG` unset).

nqp suite (`off-nqp-suite.log`):

    nqp: 155 files, 1 chunk(s) of 155, 1 server(s) x 6g heap + 3g off-heap (9g of a 22g budget, 25g available)
    [201s] chunk 1/1: ok

    155 files in 201s across 1 server(s)
    === EXIT=0 verdict=ok elapsed=201s ===

**155 files, chunk ok, exit 0, wall time 201 s.** Red list: empty.

t/01-sanity (`off-sanity.log`):

    Files=25, Tests=303, 48 wallclock secs ( 0.09 usr  0.04 sys + 19.22 cusr  0.91 csys = 20.26 CPU)
    Result: PASS
    === EXIT=0 verdict=ok elapsed=49s ===

**25/25 files, 303 tests, PASS, wall time 49 s.** Red list: empty; all 25 per-file
lines are `ok`, the same 25 file names as the verify run and as Task 7's reference.

Comparison with the default-mode reference of Task 7
(`/home/longwalker/.claude/jobs/ba3ab3a7/tmp/task7/nqp-suite.log`, `.../sanity2.log`):
the sweep keeps no per-file result listing beyond its chunk line (failures only), so
the comparable artifacts are the chunk verdict and exit code -- identical
(`155 files, 1 chunk(s)`, `chunk 1/1: ok`, `EXIT=0`) -- and for sanity the full 25-line
`ok` listing plus `Files=25, Tests=303, Result: PASS` -- identical. **Off gate: pass.**

## Step 3b: default mode on the post-`make` lib jars (coordinator ruling 22)

Task 7's default-mode nqp suite ran before `make` retrained the lib jars with
Rakudo-context recordings, so the suite was re-run in DEFAULT mode (no
`NQP_DISPATCH_PERSIST`, no log knob) against the jars as they stand now
(`nqp-suite-default.log`):

    nqp: 155 files, 1 chunk(s) of 155, 1 server(s) x 6g heap + 3g off-heap (9g of a 21g budget, 24g available)
    [205s] chunk 1/1: ok

    155 files in 205s across 1 server(s)
    === EXIT=0 verdict=ok elapsed=206s ===

**155 files, chunk ok, exit 0, wall time 206 s.** Red list: empty. The post-`make`,
Rakudo-trained lib jars consume their persisted slots with no test regression.

## Clocks, side by side

| run | mode | result | wall |
|---|---|---|---|
| nqp suite | verify | 155 files, chunk ok, exit 0 | 204 s |
| t/01-sanity | verify | 25/25, 303 tests, PASS | 51 s |
| nqp suite | off | 155 files, chunk ok, exit 0 | 201 s |
| t/01-sanity | off | 25/25, 303 tests, PASS | 49 s |
| nqp suite | default (post-make jars) | 155 files, chunk ok, exit 0 | 206 s |
| nqp suite | default (Task 7 reference) | 155 files, chunk ok, exit 0 | 196 s |
| t/01-sanity | default (Task 7 reference) | 25/25, 303 tests, PASS | 56 s |

The three nqp-suite clocks (204 / 201 / 206 s) and the three sanity clocks
(51 / 49 / 56 s) sit inside each other's run-to-run noise; verify mode's extra
recording and comparison work is not visible at this resolution, and the off mode
is not measurably slower than consuming the slots on these two workloads (neither
workload is a cold-start benchmark -- both run on a warm server).

## Tooling change

**None.** The environment pass-through already worked (verified in step 1), so
`tools/build/evalserver-sweep.raku` and every other file in the tree are unmodified
by this task. The only new files are the logs, which live outside the repository.

## Log files

    /home/longwalker/.claude/jobs/ba3ab3a7/tmp/task8/smoke-verify.log
    /home/longwalker/.claude/jobs/ba3ab3a7/tmp/task8/smoke-control-full.log   (the mis-named-file control)
    /home/longwalker/.claude/jobs/ba3ab3a7/tmp/task8/verify-nqp-suite.log     + .verifylog
    /home/longwalker/.claude/jobs/ba3ab3a7/tmp/task8/verify-sanity.log        + .verifylog
    /home/longwalker/.claude/jobs/ba3ab3a7/tmp/task8/off-nqp-suite.log
    /home/longwalker/.claude/jobs/ba3ab3a7/tmp/task8/off-sanity.log
    /home/longwalker/.claude/jobs/ba3ab3a7/tmp/task8/nqp-suite-default.log
