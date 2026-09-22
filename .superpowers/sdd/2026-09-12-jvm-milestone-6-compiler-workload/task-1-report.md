# Task 1 report — the clean build at HEAD is the milestone baseline

**Status: DONE_WITH_CONCERNS.**

Everything the brief asked for is done and green. The concern is not a
failure: the brief's Step 4 (`make`) would have produced a *false*
baseline, and repairing that changed the shape of the work. Details below.

## What was built

- rakudo HEAD `0a43dbed1e` (worktree `jesp-direct-lazy-records`)
- nqp HEAD `41c294b02`
- Commit created: rakudo **`aa0169ed5a`** — the ledger only. No nqp commit.
  No source file changed in either tree.

## Step 1 — toolchain

```
Java(TM) SE Runtime Environment Oracle GraalVM 25.2.4+7.1 (build 25.0.4+7-LTS-jvmci-25.2-b20)
```

Oracle GraalVM 25.2.4. The numbers stand.

## Step 2 — pre-build state

| | value |
|---|---|
| rakudo HEAD | `0a43dbed1e` |
| nqp HEAD | `41c294b02` |
| `blib/CORE.c.setting.jar` | 2026-09-11 21:34:27 +0200 |
| `nqp/build/jvm/share/lib/nqp.jar` | 2026-09-11 21:16:33 +0200 |

## Step 3 — nqp clean build

```
raku tools/build/watched-run.raku --log=… --show='Stage' --show='BUILD' \
  -- ./nqp/gradlew -p nqp clean buildJvm
```

`BUILD SUCCESSFUL in 4m 4s`, `EXIT=0 verdict=ok elapsed=244s`.
Milestone 5 recorded 256 s, so this is 12 s faster — within noise.

## Step 4 — the finding: `make` at HEAD was a no-op

The first `make` finished in **0 s**, printing only `+++ Setting up JVM
runner` and `+++ Setting up j-runner-default`. Two independent causes,
both of which would have voided the milestone's numbers:

**(a) make's dependency graph never sees nqp.** No rakudo target lists
`nqp/build/jvm/share/lib/nqp.jar` — or any nqp artifact — as a
prerequisite. The three rakudo commits since the last build are
docs-only (`e6ca966f4a`, `975a3bd927`, `0a43dbed1e`), so every rakudo
target still looked up to date against sources that had not changed. The
clean nqp of Step 3 was therefore invisible to make. Had Step 4 been
taken at face value, milestone 6 would have measured 0 s of build and
then run every later task against jars compiled by the *previous* nqp —
precisely the trap that voided milestone 4.

**(b) the generated Makefile itself predated milestone 5.** `Makefile`
was stamped 2026-09-11 02:19, while
`nqp/build/jvm/share/lib/jvmconfig.properties` is now 2026-09-12 12:05.
Its `NQP_JARS` and `BLD_NQP_JARS` still began

```
…/nqp/build/jvm/share/runtime/asm-9.10.1.jar:…/asm-tree-9.10.1.jar:…
```

Milestone 5 deleted both; `ls nqp/build/jvm/share/runtime/` shows
neither, and a nonexistent classpath entry is silently ignored by the
JVM, so nothing ever complained. The same stale Makefile omitted
`nqp-truffle.jar`. This is the *source* of the `rakudo-j-build`
staleness the brief cites as evidence: the runner is generated from
these macros, which is why the no-op `make`'s own "Setting up JVM
runner" step did not clear it (`grep -c asm rakudo-j-build` was still 1
afterwards).

**Repair.** Inside the task, as Step 4 directs, and with no source
change — only generated state:

```
perl Configure.pl --backends=jvm \
  --prefix=<worktree>/install --silent-build
make clean
raku tools/build/watched-run.raku --log=… --show='Compiling' --show='Stage' -- make
```

Configure reported `Using the nested nqp checkout's nqp-j-gradle …
(version 2026.08-161-g41c294b02 / Java(TM) 25.0.4)` — i.e. it picked up
the freshly built nqp, not an installed one. After it, `grep -c asm
Makefile` went 2 → **0** and `nqp-truffle.jar` is on the classpath.
`make clean` removed `blib/*.jar` and all of `gen/` except
`gen/jvm/BOOTSTRAP`, so the rebuild is a genuine clean build at HEAD.

The rebuild: `EXIT=0 verdict=ok elapsed=1122s`. Afterwards `grep -c asm
rakudo-j-build` is **0** and the runner carries `nqp-truffle.jar` — the
brief's staleness evidence is gone, from both the Makefile and the
runner.

The two encoder commits the brief named as the first suspects (nqp
`7e7aaca61`, `df564ddbb`) caused no failure: the clean `buildJvm` of
Step 3 built them without incident, and the rakudo build on top was
green. The suspicion was reasonable but the actual defect was upstream
of it, in make's graph.

## Step 5 — the baseline numbers

| clock | milestone 5 | milestone 6 baseline |
|---|---|---|
| nqp clean buildJvm | 256 s | **244 s** |
| make from the top | 1054 s | **1122 s** |
| CORE.c total | 464 s | **457 s** |
| CORE.c parse | 352.4 s | **344.1 s** |
| CORE.c optimize | 36.6 s | **36.6 s** |

Full CORE.c stage line:

```
Stage start      :   0.001
Stage parse      : 344.091
Stage syntaxcheck:   0.000
Stage ast        :   0.000
Stage optimize   :  36.588
Stage qast       :  32.619
Stage unit       :  26.610
Stage jar        :   0.000
```

`CORE.c total` = recipe wall clock from marker `[583s] +++ Compiling
blib/CORE.c.setting.jar` to `[1040s] +++ Compiling
blib/Perl6/BOOTSTRAP/v6d.jar`, i.e. 457 s. The stage lines themselves sum
to 439.9 s; the 17 s difference is JVM start plus the jar write, and
milestone 5's 464 s was measured the same (wall-clock) way, so the two
are comparable.

CORE.d totals 8.8 s of stages (parse 7.1), CORE.e 41.2 s (parse 33.6,
optimize 4.3).

Where the other 665 s of `make` goes, from the marker timeline:
frontend jars (ModuleLoader → SysConfig) 150 s, `rakudo.jar` 29 s,
**`blib/Perl6/BOOTSTRAP/v6c.jar` 398 s** ([185s] → [583s]), then CORE.c,
then v6d/v6e 82 s. BOOTSTRAP v6c is the second-largest single clock in
the build after CORE.c parse and is not currently on the milestone's
measurement list.

## Steps 6-8 — the gates

**Sanity.** `RAKUDO_RAKUAST=1 raku tools/build/evalserver-sweep.raku
--chunk=25 --jobs=1 --heap=8 t/01-sanity`:

```
25 files, 1 chunks of 25, 1 servers x 8g heap + 3g off-heap (11g of a 22g budget, 25g available)
[97s] chunk 1/1: ok
25 files in 97s across 1 servers
```

25 files, zero failures.

**nqp suite.** `./nqp/gradlew -p nqp testNqp` (the corrected task, not
`test`): `Files=151, Tests=13185, 598 wallclock secs`, watched-run
`elapsed=599s` (engine-merge baseline 614 s). Gradle exits 1 because of
the known reds; the file list is the gate, and it is **exactly the nine
expected, with no tenth**:

| file | expected | observed |
|---|---|---|
| `t/nqp/021-contextual.t` | 6/33 | 6/33 (tests 2, 5-6, 9, 32-33) |
| `t/nqp/022-optional-args.t` | 1/7 | 1/7 (test 7) |
| `t/nqp/044-try-catch.t` | 1/62 | 1/62 (test 57) |
| `t/nqp/112-continuations.t` | 2/26 | 2/26 (tests 15-16) |
| `t/qregex/01-qregex.t` | 21/845 | 21/845 (572-589, 591, 594, 601) |
| `t/p5regex/01-p5regex.t` | 3/182 | 3/182 (78, 159-160) |
| `t/qast/01-qast.t` | 175/184 | exits 1 at test 10; bad plan, 10 of 184 ran |
| `t/jvm/01-continuations.t` | 3/22 | 3/22 (16-17, 19) |
| `t/jvm/11-dispatch.t` | 20/160 | exits 1 after 140 of 160 planned |

**Jar census.** `raku tools/build/jar-census.raku
nqp/build/jvm/share/lib/*.jar`:

```
CENSUS: all 10 jars are unit artifacts
```

Every jar `meta=1 class=0`. No `.class` anywhere.

## Step 9 — commit

`git add` on the ledger only; committed as rakudo `aa0169ed5a` with
`GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE` `2026-09-12 19:00:00 +0200` and
the brief's trailer verbatim. Nothing else was staged; the untracked
`engine-merge-*.log`, `sweep-logs/` and the two `tools/build/t3b-*.raku`
files that predate this task are left exactly as found.

## Concerns for the controller

1. **`make` alone cannot rebuild this tree after an nqp change.** Task 14
   rebuilds after the rebase and, as written, would hit the same silent
   no-op. It needs Configure + `make clean` + `make`. A ruling to that
   effect is in the ledger.
2. **`make` is 1122 s against milestone 5's 1054 s (+6.5%).** Not
   investigated — outside this task's scope. Plausibly the Configure
   regeneration plus a fully cold `gen/`, since the component clocks that
   *are* comparable (nqp build, CORE.c total, CORE.c parse) all came in
   slightly *faster*. Later tasks should compare against 1122 s.
3. **The stale Makefile was live for a day.** Every measurement taken in
   this worktree between 2026-09-11 02:19 and now ran with two
   nonexistent classpath entries and without `nqp-truffle.jar` on the
   Makefile-derived classpath. Nothing failed, so the effect was likely
   nil, but any number carried forward from that window should be treated
   as suspect rather than assumed good.
4. **BOOTSTRAP v6c is 398 s of the build** — 35% of `make`, second only
   to CORE.c parse — and the milestone's measurement plan does not name
   it. Worth a look if the levers turn out to help it too.

---

# Fix round 1 — ledger framing of the `make` figure

Two Important findings, both on the ledger's presentation of one number.
No build, no gate and no artifact was touched; nothing was re-run.

**The fact I was missing.** Milestone 5 recorded *two* `make` figures
with two different methods, not one:
`memory/milestone-5-rakuobject-layout.md:122-124` — "make: 1054 s (make
after a clean nqp build, Task 6) vs 1133 s (make clean && make, twice;
CORE.c parse identical 352 s) -> the perf session baselines against
BOTH." My 1122 s is a `make clean && make`, so 1133 s is its comparator
and milestone 6 is **11 s faster**, not 68 s slower. That is consistent
with every component clock I measured coming in faster (nqp 244 vs 256,
CORE.c total 457 vs 464, parse 344.1 vs 352.4), which is what should
have made me doubt the comparator at the time. I took the single figure
the brief handed me and wrote an explanation for a gap instead of
questioning whether the gap was real — the explanation ("Configure
regeneration plus a fully cold `gen/`") was invented to fit a number
that did not need fitting.

**Finding 1 — wrong comparator in the baseline table.** The row read
`| make from the top | 1054 s | 1122 s |`, which showed a Task 11 reader
a 68-second regression that does not exist. The row is now
`| make from the top (`make clean && make`) | 1133 s | 1122 s |`, with
the method stated in the row label so it binds to both sides at once. A
short paragraph under the table records that milestone 5 kept two
figures, names the method of each, cites
`[[milestone-5-rakuobject-layout]]:122-124`, states the 11 s
improvement, and says plainly that 1054 s is not this row's comparator.
The old "up 68 s on milestone 5's" sentence and its invented explanation
are deleted.

**Finding 2 — the number had no method attached.** "Treat 1122 s as the
number to compare against, not 1054 s" is replaced by a paragraph headed
**What 1122 s is, in words**: the wall clock of `make` alone, run after
`perl Configure.pl --backends=jvm --prefix=<worktree>/install
--silent-build` and then `make clean`, in that order — a full cold build
of every rakudo artifact against an already-clean-built nqp. It warns
that timing a plain incremental `make` against it is not the same
measurement, and that on this tree an incremental `make` can be a 0 s
no-op besides, pointing at the Task 1 ruling.

**Accuracy correction, as instructed.** The ledger said `make clean`
removed "`blib/*.jar` and `gen/`". It removed all of `gen/` *except*
`gen/jvm/BOOTSTRAP` — which is what my report said and what
`ls gen/jvm/` showed after the clean. The ledger, being the surviving
record, now says the same.

**Benign log line, now recorded.** A sentence in the repair section
notes that `m6-make.log:80` — `cp: cannot stat
'<worktree>/nqp/bin/eval-client.pl': No such file or directory` — is not
a build error: `Makefile:1424` carries a `|| $(CP) …
tools/jvm/eval-client.pl .` fallback, and the sweep uses
`tools/build/eval-client.raku` regardless. Verified in the log and in
the Makefile before writing it.

**Scope.** Only lines inside my own `### Task 1` entry (ledger lines
71-183) were edited. The controller's Rulings 3-5, review summary and
deferred-minor lines below it are untouched; the two surviving `1054`
mentions inside my entry are the deliberate ones that explain why it is
*not* the comparator.

**Commit.** Amended rakudo `aa0169ed5a` -> `1477806f7b` in place rather than adding a
commit, keeping `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE`
`2026-09-12 19:00:00 +0200` and the same trailers. New hash below.
