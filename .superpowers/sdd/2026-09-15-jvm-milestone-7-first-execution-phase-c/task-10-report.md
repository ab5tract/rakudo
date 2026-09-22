# Task 10 — the milestone 7 close

ROOT = `/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records`;
nqp tree = `ROOT/nqp`. Measured tree: rakudo `6217a89e61` / nqp `a837bf1bb`.
Final pushed tips: rakudo `dad727461c` / nqp `8ea35ba95`.

**Two things did not go to plan and are recorded, not smoothed over:**
the whole-`t/` clock is **not gathered** (the sweep's single server
stopped producing TAP at file 310 of 482), and the 310 files that did run
turned up **one new red**, `t/02-rakudo/closure-static-clone.t`, which is
**not** Phase C's doing. Both are in the docs, the ledger and the memory.

> This task was stopped once, mid-`make`, for the fix wave (that stop's
> own report is superseded by this file; the interrupted run's only
> datum was v6c at 370 s). Everything below is the fixed tree.

## Steps 1-2 on the fixed tree (rakudo 6217a89e61 / nqp a837bf1bb)

| gate | result | wall |
|---|---|---|
| `Configure.pl --backends=jvm --gen-nqp` | exit 0; `dispatch-record: done 9 paths, 1683 slots, 1711 programs, 41 unpersistable, 0 failed` | **4.253 s** |
| `make` (full, watched-run) | exit 0, `+++ Training dispatch slots` ONCE, `+++ Setting up` x4 | **888 s** |
| v6c inside it | 165 s -> 540 s | 375 s |
| CORE.c inside it | 540 s -> 836 s; parse 223.037 / optimize 22.040 / qast 16.729 / unit 20.701 | 296 s (stage sum 282.5) |
| `blib/.dispatch-train.log` | ends `dispatch-record: done 21 paths, 4282 slots, 4584 programs, 50 unpersistable, 0 failed`; **0 FAILED**; `blib/.dispatch-trained` present | - |
| `t/01-sanity` default | 25/25, 303 tests, PASS | **57 s** |
| cold `-e ''` stats | `restored=4475 restoredSites=4193 dropped=37 **staleSchema=0** recorded=195` (hits 13324, misses 4306, sitesAll 6511) | - |
| nqp suite, verify | 155/155, 11 processes, matched 271378 byOutcome 1309 **mismatched=0** unseen 116617, 0 MISMATCH blocks | **208 s** |
| `t/01-sanity`, verify | 25/25, 303 tests, PASS; matched 117438 byOutcome 327 **mismatched=0** unseen 73949, 0 MISMATCH | **51 s** |

Rig row `close` (marker `m7-rig: DONE tag=close`):

| tag | rakudo | nqp | cold rakudo-e | cold nqp-e | misses | hits | warm |
|---|---|---|---|---|---|---|---|
| close | 6217a89e61 | a837bf1bb | **2.247 s** | **1.198 s** | 4931 | 35512 | 59 s/sanity |

Walls: rakudo 2.36 2.25 2.28 2.41 2.43; nqp 1.24 1.25 1.20 1.23 1.23.
Best cold rakudo-e: `hits=35512 misses=4931 sites=7463 anon=6 sitesAll=7569 restored=4470 restoredSites=4188 dropped=37 staleSchema=0 recorded=849`.
Best cold nqp-e: `hits=9998 misses=1829 sites=3012 anon=4 sitesAll=3059 restored=1644 restoredSites=1634 dropped=30 staleSchema=0 recorded=257`.
Histogram unchanged from `c`: lang-meth-call 2747, lang-call 1950, boot-syscall 197, raku-assign 35, raku-coercion 1, raku-meth-call-qualified 1.
Every counter is identical to row `c`; only the wall clocks moved (2.272 -> 2.247, 1.203 -> 1.198) and `staleSchema=0` is new. Warm proxy 59 s against c's 63 s and b's 50 s.

## Step 3: the whole `t/` run — NOT GATHERED

Command (plain background job, ruling 15):

    RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku \
        --log=.../t-all.log --stall=7200 --max=14400 \
        --show='red=' --show='green=' --show='chunk' \
        --show='Killed' --show='OutOfMemory' -- \
      raku tools/build/evalserver-sweep.raku \
        t/01-sanity t/02-rakudo t/03-jvm t/04-nativecall t/05-messages \
        t/06-telemetry t/07-pod-to-text t/08-performance t/09-moar \
        t/10-qast t/12-rakuast t/13-experimental t/14-smoke \
        --jobs=1 --heap=6 '--chunk=*'

(`t/spec` out by the standing rule; `t/11-js` out as the JS backend's, as
in the 2026-09-05 run. `--chunk=*` is one chunk on one never-replaced
server, which is what "one warm server" means here.)

Log verbatim:

    rakudo: 482 files, 1 chunk(s) of 482, 1 server(s) x 6g heap + 3g off-heap (9g of a 19g budget, 22g available)
    [3360s] chunk 1/1: FAIL  *** a file produced no TAP ***
    482 files in 3360s across 1 server(s)
    1 of 1 chunks failed
    Files=482, Tests=3080, 3361 wallclock secs
    Result: FAIL
    === EXIT=1 verdict=ok elapsed=3361s ===

**Why the 3361 s is not a clock.** The server stopped producing TAP at
file **310** of 482. The last green file is
`t/02-rakudo/test-assign-metaop-mu.t`; from
`t/02-rakudo/thread-unhandled-exception.t` on, **every one of the
remaining 172 files** reported `(Wstat: 256 (exited 1) Tests: 0 Failed:
0)`, `Non-zero exit status: 1`, `Parse errors: No plan found in TAP
output`. Whole directories (`t/04-nativecall`, `t/06-telemetry`,
`t/07-pod-to-text`, `t/08-performance`, `t/09-moar`, `t/10-qast`,
`t/12-rakuast`, `t/13-experimental`, `t/14-smoke`) contributed **zero
green files**. Tests=3080 against the 2026-09-05 run's 2652 from
`t/02-rakudo` alone is the same story from the other side.

Rate check: 3360 s / 310 files = **10.8 s per file**, against 5078 s /
427 = 11.9 s per file on 2026-09-13. Same order. The run is truncated,
not fast, and **not comparable to 5078 s**.

**Ruling out the two obvious causes.**

- *Not the low-memory guard* (the ruling-15 scenario, which killed four
  Phase B sweeps at 25-27 GB): the server printed its banner and ran 310
  files; `MemAvailable` went 24.4 -> 15.6 GB and recovered to 24.4 GB;
  no `Killed`, no `OutOfMemory` in the log; `dmesg` empty; watched-run
  exited 0-with-child-1, not 124/137; the harness printed its own
  summary.
- *Not any single file*: the four around the break run green together on
  a fresh server —
  `perl t/harness5 --jvm --evalserver --jobs=1 test-assign-metaop-mu.t
  thread-unhandled-exception.t topic-call-bind.t t/03-jvm/01-interop.t`
  -> **4 files, 81 tests, PASS, 66 s**. Files from the dead stretch pass
  directly too: `t/12-rakuast/block.rakutest` prints its plan and its
  `ok`s, `t/04-nativecall/01-argless.t` likewise.

So the cause is the **single-server sweep wedging after ~285 files of
`t/02-rakudo`** — cumulative server state. The 2026-09-05 run used one
server *per directory* and so could not see it; the 2026-09-13 427-file
run used one server and did not report it.

**Per the user rule of 2026-09-15 the run was NOT re-taken.** Recorded as
not gathered, with the evidence, in
`docs/jvm-full-suite-run-2026-09-16.md`.

## The red diff, over the 310 files that did run

Baseline: `docs/jvm-t02-rakudo-red-baseline.txt` (24 files).

- **20 of the baseline's reds are red here.**
- **4 are green**: `15-gh_1202.t`, `16-begin-time-eval.t`,
  `native-argument-snapshot.t`, `try-statement-backtrace-frame.t`.
- The remaining baseline entries sit after the break and were not
  reached.
- **1 new red: `t/02-rakudo/closure-static-clone.t`** (Tests: 8,
  Failed: 1 — test 5).

The 172 post-break files are NOT a red list.

### The new red, run down as far as is cheap

    $ RAKUDO_RAKUAST=1 ./rakudo-j -Ilib t/02-rakudo/closure-static-clone.t
    ok 1 - each closure captures its own outer
    ...
    not ok 5 - .clone through the method road still works
    # expected: 'documented'
    #      got: ''
    # You failed 1 test of 8

- Reproduces outside any harness, so it is not a sweep artefact.
- **Still fails with `NQP_DISPATCH_PERSIST=off`** — so **Phase C's
  persisted miss is not the cause.**
- The test was added by A6' itself (rakudo `d6d5a2ea7e`, 2026-09-14,
  "RakuAST: closures take a static clone road on the JVM") and passed
  then. The regression therefore sits between that commit and the close:
  Phase B's artifact rework, or one of the two upstream rebases.
- **Not bisected**: each step is a ~900 s build, and no rebuild was
  spent on speculation. Left open and named in the findings, the plan
  doc, the spec, the ledger and the memory.

## Steps 4-6: docs, commit, rebase, push

**Docs written** (all committed):

| file | what |
|---|---|
| `docs/jvm-perf-findings-2026-09.md` | rulings **23-28** + the fix wave folded into Phase C item (b), naming nqp `a837bf1bb` / rakudo `6217a89e61` as part of the phase; new section **"Milestone 7: the close (2026-09-16)"** — the 15-row per-lever table (base, A1-A8c, A6', b, c, close) with both hashes and four numbers each, the A7 promotion list carried over as empty, the two-programs/two-`recorded`-figures note, the close's own gate table, the two milestone clocks, "The suite clock, and one new red", and a 15-item "What milestone 7 left" |
| `docs/jvm-truffle-only-plan.md` | the milestone-7 position paragraph rewritten as closed; item 4's row and the cold-start row restated with what the milestone closed and what it left |
| `docs/jvm-full-suite-run-2026-09-16.md` | **new**, in the 2026-09-05 file's shape: the not-gathered verdict, the evidence, what it was not, and the red diff |
| the spec | **"Milestone 7: closed 2026-09-16"** after "Done" |
| the Phase C ledger | rig row `close`; the fix wave; the close's gates with clocks; the whole-`t/` not-gathered entry with its evidence; the red diff; the before/after hash mapping for **both** trees |
| memory (not committed) | `milestone-7-first-execution.md` frontmatter + a "Status (2026-09-16): MILESTONE 7 CLOSED" block; the `MEMORY.md` pointer line |

Also appended: rig row `close` to the SDD `progress.md`.

**Commits** (`docs/` only — no jar, no `Makefile`, no `blib/`, no
`.superpowers/`, no memory file):

    5c3a4a38d1  Docs: milestone 7 closed -- first execution, measured
    (after the rebase: b4cb5c8344)
    83fa58e42c  Docs: record the milestone-7 close hashes before and after the rebase
    dad727461c  Docs: the close's nqp hash mapping too -- both trees were rebased

The third exists because the first mapping commit said nqp had not been
rebased; the nqp fetch afterwards found one upstream commit, so the claim
was wrong and was corrected rather than left standing.

**Rebases**, both clean, no conflict:

- rakudo onto `origin/main` `67f2e3bcff` — **two** upstream commits, 219
  replayed.
- nqp onto `upstream/main` `06f61ec6a` — **one** upstream commit, 178
  replayed. The nine v2 stage0 jars were set aside under the tag
  `stage0-v2-close` (entry `b81dbeb8dfffe593ecf2f536b9ddbf2309f4c463`),
  restored by applying that entry, **md5-verified byte for byte (9/9
  OK)**, and the entry dropped. They remain uncommitted (user rule), and
  `git status --short | grep -v stage0` in the nqp tree is empty.

**Pushes, verbatim:**

    To github.com:ab5tract/rakudo.git
     + a896b743e0...83fa58e42c worktree-jesp-direct-lazy-records -> worktree-jesp-direct-lazy-records (forced update)

    To github.com:ab5tract/nqp.git
     + e3c800371...8ea35ba95 jesp-direct-lazy-records -> jesp-direct-lazy-records (forced update)

    To github.com:ab5tract/rakudo.git
       83fa58e42c..dad727461c  worktree-jesp-direct-lazy-records -> worktree-jesp-direct-lazy-records

**Final tips: rakudo `dad727461c`, nqp `8ea35ba95`.** Both trees clean
apart from the nine stage0 jars.

## Concerns, in order

1. **The new red is the one that matters.**
   `t/02-rakudo/closure-static-clone.t` is a real regression on the
   branch, in the clone road A6' built, and it is unbisected. Phase C is
   ruled out; Phase B and the two upstream rebases are not.
2. **The suite clock is still unmeasured**, and now there is a known
   reason why the measurement fails: the single-server sweep wedges after
   ~285 `t/02-rakudo` files. Whatever measures the suite next has to fix
   or work around that first (per-directory servers would, at the cost of
   the warm state the number is supposed to capture).
3. **The warm-clock question the close was meant to settle** (proxy 50 ->
   63 -> 59 s) is still open, because the run that would have settled it
   did not complete.
4. **Stage0 is still nine uncommitted jars**, so the pushed branch does
   not build from a fresh clone. Unchanged, and the user's call.
5. The ledger's "branch tips" line names `83fa58e42c`; the true final tip
   is the mapping-correction commit `dad727461c` one past it. Noted in
   the memory rather than chased with a fourth commit.
