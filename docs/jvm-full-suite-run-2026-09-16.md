# Whole `t/` run — 2026-09-16 (milestone 7 close): NOT GATHERED

Engine build: rakudo `6217a89e61`, nqp `a837bf1bb` (the milestone-7
close's tree). One warm eval server, 6 GB heap, `--jobs=1 --chunk=*`
through `tools/build/watched-run.raku` as a plain background job
(ruling 15). Command:

    raku tools/build/evalserver-sweep.raku \
        t/01-sanity t/02-rakudo t/03-jvm t/04-nativecall t/05-messages \
        t/06-telemetry t/07-pod-to-text t/08-performance t/09-moar \
        t/10-qast t/12-rakuast t/13-experimental t/14-smoke \
        --jobs=1 --heap=6 '--chunk=*'

`t/spec` is out by the standing rule; `t/11-js` is out because it is the
JS backend's, as in the 2026-09-05 run.

## The verdict: the clock is not gathered

**482 files, 3361 s wall, exit 1 — and the number means nothing**, because
the server stopped producing TAP a third of the way in.

| fact | value |
|---|---|
| files listed | 482 (the population was 427 when 5078 s was measured on 2026-09-13) |
| wall | 3361 s |
| files that actually ran | **310** — `t/01-sanity`'s 25 and 285 of `t/02-rakudo` |
| files that produced nothing | **172**, every one of them after the break |
| tests reported | 3080 (the 2026-09-05 run read 2652 from `t/02-rakudo` alone) |
| the break | at `t/02-rakudo/thread-unhandled-exception.t`; the file before it, `test-assign-metaop-mu.t`, is the last green one |
| what the 172 look like | `(Wstat: 256 (exited 1) Tests: 0 Failed: 0)`, `Non-zero exit status: 1`, `Parse errors: No plan found in TAP output` |

So the run is **not comparable to 5078 s**: about 10.8 s per file over the
310 that ran, against 11.9 s per file over the 2026-09-13 run's 427 — the
same order, and the 3361 s is a truncated run, not a faster one.

**Per the user rule of 2026-09-15 a failed benchmark run is not re-run.**
The clock is recorded as not gathered and the next planned point takes it.

## What it was not

- **Not the low-memory guard**, which is what killed four single-server
  sweeps in Phase B. The server started (it printed its banner and ran
  310 files), `MemAvailable` fell from 24.4 GB to 15.6 GB and recovered
  to 24.4 GB, `dmesg` is empty, and neither `Killed` nor
  `OutOfMemory` appears in the log. The sweep ran to completion and the
  harness printed its own summary.
- **Not any single test file.** The four files around the break —
  `test-assign-metaop-mu.t`, `thread-unhandled-exception.t`,
  `topic-call-bind.t`, `t/03-jvm/01-interop.t` — all pass together on a
  fresh server (4 files, 81 tests, PASS, 66 s). Files from the dead
  stretch pass when run directly too:
  `t/12-rakuast/block.rakutest` and `t/04-nativecall/01-argless.t` both
  produce their plan and their `ok`s under `./rakudo-j -Ilib`.
- **Not a build failure.** The same build passes `t/01-sanity` 25/25 and
  the nqp suite 155/155.

What it is, then, is the **single-server sweep wedging after ~285 files
of `t/02-rakudo`** — cumulative server state, not a per-file fault. The
2026-09-05 run used one server *per directory*, which is why it never saw
this; the 2026-09-13 run used one server for 427 files and did not report
it, so either it did not happen there or it was not looked for. This is
the open item the next suite measurement has to settle first.

## The red list, over the 310 files that did run

Compared with `docs/jvm-t02-rakudo-red-baseline.txt` (24 files). Twenty
of the baseline's reds are red here; four are green
(`15-gh_1202.t`, `16-begin-time-eval.t`, `native-argument-snapshot.t`,
`try-statement-backtrace-frame.t`); the rest of the baseline sits after
the break and was not reached.

**One new red:**

    t/02-rakudo/closure-static-clone.t   (Tests: 8 Failed: 1, test 5)

It reproduces outside the harness:

    $ RAKUDO_RAKUAST=1 ./rakudo-j -Ilib t/02-rakudo/closure-static-clone.t
    not ok 5 - .clone through the method road still works
    # expected: 'documented'
    #      got: ''

and it **still fails with `NQP_DISPATCH_PERSIST=off`**, so Phase C's
persisted miss is not the cause. The test was added by A6' itself
(rakudo `d6d5a2ea7e`, 2026-09-14, "RakuAST: closures take a static clone
road on the JVM") and passed then, so the regression is somewhere between
that commit and the close — Phase B's artifact rework or one of the two
upstream rebases are the candidates, and each bisection step costs a
~900 s build. **Open, unbisected, and named here rather than left in a
log.**

The 172 files after the break are NOT a red list and must not be read as
one.
