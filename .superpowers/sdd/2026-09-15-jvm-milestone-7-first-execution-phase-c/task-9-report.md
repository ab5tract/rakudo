# Task 9 report: Measure once, document, close the phase

Date: 2026-09-16. ROOT = `/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records`.
Status: **DONE.** The rig ran once, every document listed in the brief was written,
one commit became two (see "One deviation"), both trees were rebased onto their
upstream mains and force-pushed to ab5tract.

---

## Step 1: rig row `c`

Pre-check: `env | grep -c NQP_DISPATCH_RECORD` -> `0`.

```
cd ROOT && RAKUDO_RAKUAST=1 raku tools/build/m7-rig.raku --tag=c \
    --out=/home/longwalker/.claude/jobs/ba3ab3a7/tmp/m7-rig --warm=proxy
```

Full output, verbatim:

```
m7-rig: rakudo-e  run1 wall=2.272s
m7-rig: rakudo-e  run2 wall=2.341s
m7-rig: rakudo-e  run3 wall=2.378s
m7-rig: rakudo-e  run4 wall=2.310s
m7-rig: rakudo-e  run5 wall=2.290s
m7-rig: cold rakudo-e best=2.272s  all: 2.27 2.34 2.38 2.31 2.29  hits=35512 misses=4931 stage-lines=182 top: lang-meth-call=2747 lang-call=1950 boot-syscall=197 raku-assign=35 raku-coercion=1 raku-meth-call-qualified=1
m7-rig: nqp-e     run1 wall=1.290s
m7-rig: nqp-e     run2 wall=1.226s
m7-rig: nqp-e     run3 wall=1.203s
m7-rig: nqp-e     run4 wall=1.224s
m7-rig: nqp-e     run5 wall=1.240s
m7-rig: cold nqp-e best=1.203s  all: 1.29 1.23 1.20 1.22 1.24  hits=9998 misses=1829 stage-lines=74 top: lang-meth-call=1329 lang-call=448 boot-syscall=52
m7-rig: warm t/01-sanity 63s warm=63 red=0 new-red=-
| c | 79829d402e | f5c5bc8fa | 2.272 | 1.203 | 4931 | 35512 | 63/sanity | none | |
m7-rig: DONE tag=c
```

(`m7-rig: DONE` present; the sweep log's own line: `25 files, 1 chunk(s) of 25,
1 server(s) x 8g heap + 3g off-heap (11g of a 21g budget, 24g available)` ->
`25 files in 63s across 1 server(s)`.)

**The row, as appended to both ledgers:**

```
| c | 79829d402e | f5c5bc8fa | 2.272 | 1.203 | 4931 | 35512 | 63/sanity | none | Phase C close, trained build; restored=4470 recorded=849 sitesAll=7569 dropped=37 (best cold rakudo-e); nqp restored=1644 recorded=257 |
```

**`dispatch stats:` from the best cold run of each runner, verbatim:**

`c-rakudo-e-run1.err`:
```
dispatch stats: hits=35512 misses=4931 sites=7463 anon=6 sitesAll=7569 restored=4470 restoredSites=4188 dropped=37 recorded=849 slowEvals=100 invokes=6559 directs=6557 noTarget=2 badExpectation=0 notCodeRef=0 slowLayout=32 slowNull=44 byKind[value,syscall,mapped,invoke,resumable]=[0, 11979, 14866, 6541, 2126]
  noTarget 2 name KnowHOWMethods
  misses 2747 lang-meth-call
  misses 1950 lang-call
  misses 197 boot-syscall
  misses 35 raku-assign
  misses 1 raku-meth-call-qualified
  misses 1 raku-coercion
```

`c-nqp-e-run3.err`:
```
dispatch stats: hits=9998 misses=1829 sites=3012 anon=4 sitesAll=3059 restored=1644 restoredSites=1634 dropped=30 recorded=257 slowEvals=71 invokes=4952 directs=4943 noTarget=9 badExpectation=0 notCodeRef=0 slowLayout=0 slowNull=41 byKind[value,syscall,mapped,invoke,resumable]=[0, 2688, 2367, 4943, 0]
  noTarget 5 name KnowHOWMethods
  noTarget 2 new_type KnowHOWMethods
  noTarget 2 compose KnowHOWMethods
  misses 1329 lang-meth-call
  misses 448 lang-call
  misses 52 boot-syscall
```

**Reading against row `b`** (2.461 / 1.160 / misses 5667 / hits 100711 /
50 s sanity): cold rakudo-e -7.7 %, cold nqp-e +3.7 % (both inside the
series' spread), `misses` -13 % (expected: restore happens *at* the miss),
**`hits` -65 %** (the mechanism: the dispatcher's guest code no longer runs
to record), warm proxy **63 s against 50 s**.

The rig's `recorded=849` is NOT the headline. The rig's program is `say 1`,
the build trains `-e ''`; the untrained extra sites plus the in-memory `-e`
unit's own identity-less sites are the difference. The headline stays the
Task 6/7 `-e ''` figure, `recorded` 4723 -> 193/195. A cold `say 1` on an
untrained build was never gathered, so no rig-level `recorded` delta is
claimed anywhere.

**Open item, recorded in the findings and both ledgers, not re-run** (user
rule): warm proxy 50 s -> 63 s, while `t/harness5 --evalserver` on the same
directory read 55/51/49 s in Tasks 7-8 against Phase B's 58-60 s. Nothing in
the phase predicts a warm regression; the milestone close's whole-`t/` run
is where it shows or does not.

## Step 2: `tools/build/m7-rig.raku`

`parse-cold` gained two optional captures and `cold-summary` prints them;
the row line is untouched, so the whole series stays comparable:

```raku
    # Phase C's two counters. Optional: a capture from before Phase C has
    # neither, and the row line must stay comparable across the whole series,
    # so they are summary-only and never enter the row.
    %r<restored> = +$0 if $text ~~ / ' restored=' (\d+) /;
    %r<recorded> = +$0 if $text ~~ / ' recorded=' (\d+) /;
```

Tested three ways:

```
$ raku tools/build/m7-rig.raku --parse-cold=.../c-rakudo-e-run1.err
hits=35512 misses=4931 restored=4470 recorded=849 stage-lines=182 top: lang-meth-call=2747 ...
$ raku tools/build/m7-rig.raku --parse-cold=.../c-nqp-e-run3.err
hits=9998 misses=1829 restored=1644 recorded=257 stage-lines=74 top: lang-meth-call=1329 ...
$ raku tools/build/m7-rig.raku --parse-cold=/tmp/old-capture.err   # pre-Phase-C shape
hits=100711 misses=5667 restored=- recorded=- stage-lines=0 top: lang-meth-call=3473
```

## Step 3: the documents

| file | what changed |
|---|---|
| `docs/jvm-perf-findings-2026-09.md` | "Milestone 7, Phase C" gains (b) the 22 rulings as landed, one line each with the cost if wrong; (c) the numbers -- row `c` against `b`, the counter table, the residual histogram, the `-e ''` before/after table, the drop cause, the verify totals per gate; (d) the gates with their clocks in one table plus the `Configure.pl`-invalidates-everything fact; (e) the per-jar `unit.dispatch` sizes, jar growth, bytes per program, and the compression question put to the user with its numbers; (f) the open items and every deferred minor from the SDD ledger |
| `docs/jvm-unit-lazy-loading.md` | "The dispatch table" rewritten for a filled table: the slot schema (`DispatchSlot(programs)`, `PRef(handle, index, kind)`, HLL as (name, compilerSide), syscall by name, dispatcher by id, descriptor inline), the training in both builds (the stage2 copy, the Makefile stamp, the mtime normalisation, the marker), the consumer at the first miss, the three modes, verify's comparison by evaluated outcome. Diagnostics gains `sitesAll=`/`restored=`/`restoredSites=`/`dropped=`/`recorded=` and the four Phase C knobs; the intro points at Phase C; "What phase 2 will do" untouched |
| `docs/superpowers/specs/2026-09-13-jvm-milestone-7-first-execution-design.md` | a "**Phase C: closed 2026-09-16**" paragraph after the Phase C section, in Phase B's style: hashes, headline numbers, row `c`, the gate, pointers, and the two corrections to the letter (verify compares by evaluated outcome, not text alone; the slot carries programs only) |
| `docs/jvm-truffle-only-plan.md` | the position paragraph for the persisted miss (three sentences plus the "next"), and the position table's cold-start row now says Phase C is done |
| `docs/superpowers/plans/...-phase-c.ledger.md` | row `c` with its verdict; a "Hashes before and after the handoff rebase" table; a Task 9 log line |
| `tools/build/m7-rig.raku` | Step 2 above |
| `.superpowers/.../progress.md` | a "## Rig rows" section (b and c) plus the Task 9 entry, appended (the file is written concurrently by the controller, so nothing was rewritten in place) |
| memory `milestone-7-first-execution.md` | `description:` rewritten to PHASE C CLOSED with the hashes and the headline; a "**Status (2026-09-16): PHASE C CLOSED**" section added with the commits, the mechanism, the numbers, the gates, the rulings' pointers, the compression question, the open items, Task 10 as what remains, and the standing no-jar rule. Frontmatter shape (`name`, `description`, `metadata.type: project`) preserved |
| memory `MEMORY.md` | the `- [Milestone 7: first execution]` pointer line rewritten, one line, no content |

## Step 4: the commits (rakudo tree)

Two, not one -- see the deviation below.

```
62b2b5b0085dc439bc49992f0ce1e7b63d76e53f  Docs: milestone 7 Phase C closed -- the persisted miss, measured
  (6 files changed, 576 insertions(+), 17 deletions(-))
```
After the rebase that commit is `165c477f2b`, and on top of it:
```
a896b743e02aadb5bb839845e7142fc371879d54  Docs: record the Phase C hashes before and after the handoff rebase
  (2 files changed, 30 insertions(+), 2 deletions(-))
```

Nothing else was staged: no jar, no `Makefile`, no `blib/`, nothing under
`.superpowers/`, and the memory files live outside the repo.

### One deviation, and why

The rebase in Step 5 **rewrote every hash the documents name** (rakudo
`79829d402e` -> `5b51570903`, nqp `f5c5bc8fa` -> `e3c800371`, and the six
others). Rather than rewrite the prose -- the measured build is genuinely
the pre-rebase tree, and that is what a reader of the row needs -- a second
commit records the full nine-row before/after mapping in the ledger and a
one-sentence pointer in the findings. The alternative (editing every hash to
its post-rebase form) would have made the documents disagree with the rig's
own captures and with the two earlier ledgers.

## Step 5: rebase and push

**rakudo.** `git fetch origin main`: `ff41340331..af3df50dba main`, one new
commit (`af3df50dba Bump NQP to remove thread blocking while reading`).

```
$ git -c diff.ignoreSubmodules=all -c status.submoduleSummary=false rebase origin/main
Rebasing (1/216) ... Rebasing (216/216)
Successfully rebased and updated refs/heads/worktree-jesp-direct-lazy-records.
```
No conflict. Then:
```
$ git push --force-with-lease ab5tract worktree-jesp-direct-lazy-records
To github.com:ab5tract/rakudo.git
 + b114238897...165c477f2b worktree-jesp-direct-lazy-records -> worktree-jesp-direct-lazy-records (forced update)
```
and, after the mapping commit:
```
$ git push --force-with-lease ab5tract worktree-jesp-direct-lazy-records
To github.com:ab5tract/rakudo.git
 + 637b468183...a896b743e0 worktree-jesp-direct-lazy-records -> worktree-jesp-direct-lazy-records (forced update)
```
(the intermediate `637b468183` was amended to add the Task 9 ledger line
before the final push).

**Final rakudo hash: `a896b743e02aadb5bb839845e7142fc371879d54`.**

**nqp.** `git fetch upstream main`: `2fc2375fa..e31676e5b`;
`git rev-list --count HEAD..upstream/main` -> `1`
(`e31676e5b Bump MoarVM to remove thread blocking while reading`), so the
rebase was required.

The nine v2 stage0 jars were dirty, so, per the brief and the worktree rule:
```
$ md5sum src/vm/jvm/stage0/*.jar > .../stage0-before.md5
$ git stash push -m "stage0-v2-phase-c-task9" -- src/vm/jvm/stage0
Saved working directory and index state On jesp-direct-lazy-records: stage0-v2-phase-c-task9
$ git stash list --format='%H %gs'
5ae860b5b389db74a2fc4651914654a34b491cbe On jesp-direct-lazy-records: stage0-v2-phase-c-task9
$ git rebase upstream/main
Rebasing (1/177) ... Rebasing (177/177)
Successfully rebased and updated refs/heads/jesp-direct-lazy-records.
$ git stash apply 5ae860b5b389db74a2fc4651914654a34b491cbe   # apply, not pop
$ md5sum -c .../stage0-before.md5
src/vm/jvm/stage0/ModuleLoader.jar: OK      (all nine: OK)
$ git stash drop stash@{0}
Dropped stash@{0} (5ae860b5b389db74a2fc4651914654a34b491cbe)
```
No conflict. The nine jars are back to the exact bytes they had, still
uncommitted, and `git status --short` shows exactly those nine ` M` lines
and nothing else.

```
$ git push --force-with-lease ab5tract jesp-direct-lazy-records
To github.com:ab5tract/nqp.git
 + b51c1a0db...e3c800371 jesp-direct-lazy-records -> jesp-direct-lazy-records (forced update)
```

**Final nqp hash: `e3c800371b11fd2ce82f8ccd756bbdf262fe3269`.**

Note worth carrying: the ab5tract nqp branch was still at **`b51c1a0db`**,
Phase B's close -- **none of Phase C's five nqp commits had been pushed
before this**. They are all on the remote now.

### The hash mapping (also in the ledger)

| commit | before | after |
|---|---|---|
| rakudo: plan, ledger, C0 findings | b114238897 | 8863808d86 |
| rakudo: Makefile training stamp (the measured tree) | 79829d402e | 5b51570903 |
| rakudo: this close's docs | 62b2b5b008 | 165c477f2b |
| nqp: DispatchDump (C0) | 5f46163d2 | 35e4f734a |
| nqp: schema + DispatchSlotCodec | e27a795d8 | 936e57fae |
| nqp: consumer + modes + counters | 5fd74d9b6 | 3a4082327 |
| nqp: recorder + UnitDispatchWriter | 3d0b54fa4 | c17218e16 |
| nqp: verify by outcome + log + drop reasons | d3e602917 | a1bdba778 |
| nqp: gradle training (the measured tree) | f5c5bc8fa | e3c800371 |

## Things not done, and things to watch

- **The tree is now one upstream commit ahead of the measured build on each
  side** (both are "bump the other VM to remove thread blocking while
  reading"). Nothing was rebuilt or re-gated after the rebase -- the brief
  forbade builds, and the standing rule is that the handoff rebase is not
  gated in the same session. **Task 10 must build before it measures
  anything**, and its whole-`t/` run is the gate for both upstream commits.
- **The warm proxy clock** (63 s vs 50 s) is the one number of this task that
  is not explained. Not re-run, by rule; recorded in the findings' open
  items, in both ledgers and in memory.
- `blib/.dispatch-trained` and `blib/.dispatch-train.log` are still untracked
  and in no cleanup or `.gitignore`; left alone (a build-file change is not
  this task's).
- The nine stage0 jars remain an uncommitted working-tree change, by the
  standing user rule; the pushed nqp branch therefore still carries the v1
  stage0 and a fresh clone of it does not build.

Raw artefacts: `/home/longwalker/.claude/jobs/ba3ab3a7/tmp/m7-rig/` (`c.md`,
`rows.md`, ten `.err` captures, `c-sanity.log`) and
`/home/longwalker/.claude/jobs/ba3ab3a7/tmp/stage0-before.md5`.
