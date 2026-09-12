# SDD ledger — plan: docs/superpowers/plans/2026-09-12-jvm-milestone-6-compiler-workload.md

Spec: `docs/superpowers/specs/2026-09-12-jvm-milestone-6-compiler-workload-design.md`
(committed rakudo `e6ca966f4a`). Plan committed rakudo `975a3bd927`.

BASE before Task 1: rakudo `975a3bd927`, nqp `41c294b02`.

Model policy (user rule 2026-09-11): subagents on Opus; Fable only after
erroneous output.

Ruling: this committed ledger twin IS the ledger, not
`.superpowers/sdd/<plan>/progress.md` — the project's own convention
(milestones 4 and 5, the engine merge) keeps a committed ledger, and a
git-ignored one dies with `git clean -fdx`. The SDD workspace holds only
briefs, reports and review packages. Costs if wrong: nothing; the
workspace ledger would have held the same lines.

Ruling: the plan's per-task commit stamps (2026-09-12 19:00-23:00) are
defaults. If execution crosses midnight, stamp the evening of the date
the work actually happened, keeping the 18:00-23:00 window
([[after-hours-commit-stamps]]). Costs if wrong: commit dates drift from
wall-clock, which is already this project's accepted practice.

## Pre-flight scan

| Pair / task | Produces vs consumes | Finding |
|---|---|---|
| T1 -> T3..T7 | T1: built jars at HEAD, plus `gen/jvm/CORE.c.setting`; T3-T7: standalone compiles reading that file, writing to scratch | consistent (`blib` untouched by the redirected `--output`) |
| T2 -> T3 | T2: `truffle-trace-summary.raku`; T3 runs it on the baseline trace | consistent |
| T2 -> T4 | T2: the line `min-too-large-size=<N>`; T4 Step 1 consumes it | consistent (verified by running the tool, below) |
| T3 -> T4 | T3: the measured `min-too-large-size`; T4: threshold `N-1` | consistent |
| T3 Step 4 -> T2 | T3 may correct T2's parser if the real `opt failed` line differs | **CONFLICT** — see ruling 1 |
| T4/T5 -> T6 -> T7 | each carries the previous winners in `JDK_JAVA_OPTIONS` | consistent; each task writes its exact command to the ledger |
| T7 -> T8, T9, T10 | the adopted configuration | consistent |
| T7 -> T11 | the shipping configuration line | consistent |
| T2, T8 -> `tools/build/t/` | both create files there; both `git add tools/build/t/` | consistent; T2's files are already committed when T8 runs. T2's test writes and unlinks `fixtures/empty.log`, so a mid-run failure could leave a stray file for T8 to stage — noted, not blocking |
| T8 -> T9 | the cold-start figure, for the warm/cold split | consistent |
| T11 -> T14 | T11 writes adopted knobs into the templates; T14 rebuilds after the rebase | consistent, and desirable: the post-rebase build carries the adopted configuration |
| T12 -> T13 | what the image build demanded feeds the FFI answer | consistent |
| T13 -> T14 | both touch `native-image-aot-direction.md` | consistent; T14 Step 8 says explicitly "already updated in Task 13; add the spike's verdict" |
| T1 internal | gates named vs commands given | **DEFECT** — see ruling 2 |
| T2 internal | the tests it specifies vs the code it specifies | clean — both were written and RUN before the plan was committed; the tool reproduces every asserted value |
| T8 internal | same | clean — same method; the stage table was additionally validated against a real 252-sample recording |
| T11 internal | the four files it modifies | clean — all four paths verified to exist, with the line numbers cited |
| T14 internal | rebase, gate, push order | clean — nqp first, then rakudo, matching the dependency direction |
| Rubric | no test that asserts nothing; no verbatim duplication of a logic block | clean |

**Ruling 1 (T3 Step 4).** If the real `opt failed` line does not carry
its reason in a `Reason ` field, the parser fix lands as a NEW commit
inside Task 3, never as an amend of Task 2's reviewed commit. A reviewed
commit is not rewritten under SDD. Costs if wrong: one extra small commit
in the history instead of a tidy amend.

**Ruling 2 (T1 Step 7, T14 Step 4) — a real plan defect, corrected before
dispatch.** The plan said `./nqp/gradlew -p nqp test`. That is Gradle's
Java and Kotlin unit-test task. The 151-file nqp suite is **`testNqp`**
(t/nqp, t/hll, t/qregex, t/p5regex, t/qast, t/jvm, t/serialization,
t/nativecall). Left alone, both gates would have passed while running
nothing that could see the nine known reds. Plan corrected at both sites.
Costs if wrong: none — `testNqp` is the task whose 151-file / 614 s run
the engine-merge ledger recorded as the baseline.

## Task loop

Task 1: implementer dispatched (opus); BASE rakudo `0a43dbed1e`, nqp `41c294b02`.
Ruling: the implementer writes its own numbers into this ledger, so controller
lines for a task go in AFTER its report arrives, to avoid a concurrent-write
race on one file. Costs if wrong: nothing; the ordering of lines within a task
block is cosmetic.

### Task 1 — the clean build at HEAD (implementer)

**Toolchain (Step 1).** `Oracle GraalVM 25.2.4+7.1 (build 25.0.4+7-LTS-jvmci-25.2-b20)`. Confirmed; the numbers below stand.

**Pre-build state (Step 2).**

| | value |
|---|---|
| rakudo HEAD | `0a43dbed1e` |
| nqp HEAD | `41c294b02` |
| `blib/CORE.c.setting.jar` | 2026-09-11 21:34:27 |
| `nqp/build/jvm/share/lib/nqp.jar` | 2026-09-11 21:16:33 |

The brief's diagnosis held, and the tree was staler than the brief knew.

**Finding — `make` at HEAD was a no-op, and the Makefile itself predated
milestone 5.** Step 4's `make` finished in **0 s**, printing only
`+++ Setting up JVM runner`. Two independent causes:

1. *make's graph never sees nqp.* No rakudo target lists
   `nqp/build/jvm/share/lib/nqp.jar` (or any nqp artifact) as a
   prerequisite, and the three commits between the last build and HEAD
   are rakudo docs-only. So the freshly clean-built nqp of Step 3 left
   every rakudo target looking up to date, and a plain `make` would have
   measured nothing and handed milestone 6 a baseline built against the
   *previous* nqp — the exact trap the task exists to avoid.
2. *The generated Makefile was from 2026-09-11 02:19*, before milestone 5.
   Its `NQP_JARS` / `BLD_NQP_JARS` still listed `asm-9.10.1.jar` and
   `asm-tree-9.10.1.jar` (both deleted from nqp; the paths no longer
   exist, and a missing classpath entry is silently ignored by the JVM)
   and did **not** list `nqp-truffle.jar`. This is the same staleness the
   brief spotted in `rakudo-j-build`; the runner inherits it from here,
   which is why the no-op `make`'s "Setting up JVM runner" step did not
   clear it.

**Repair (inside the task, per Step 4's instruction).** No source
changed. Three generated-state commands, in order:

```
perl Configure.pl --backends=jvm --prefix=<worktree>/install --silent-build
make clean
make        # via watched-run
```

Configure regenerated the Makefile from the current
`nqp/build/jvm/share/lib/jvmconfig.properties`: `grep -c asm Makefile`
went 2 -> **0** and `nqp-truffle.jar` is now on the classpath.
`make clean` removed `blib/*.jar` and all of `gen/` except
`gen/jvm/BOOTSTRAP`, so the rebuild is a true clean build at HEAD. After
it, `grep -c asm rakudo-j-build` is **0** and the runner carries
`nqp-truffle.jar` — the brief's staleness evidence is gone.

One benign line in `m6-make.log` (line 80) will look like an error to a
future reader and is not one: `cp: cannot stat
'<worktree>/nqp/bin/eval-client.pl': No such file or directory`. The
`eval-client.pl` recipe at `Makefile:1424` has a `|| $(CP) …
tools/jvm/eval-client.pl .` fallback, and the sweep uses
`tools/build/eval-client.raku` regardless.

**Baseline numbers (Steps 3-5).**

| clock | milestone 5 | milestone 6 baseline |
|---|---|---|
| nqp clean buildJvm | 256 s | **244 s** |
| make from the top (`make clean && make`) | 1133 s | **1122 s** |
| CORE.c total | 464 s | **457 s** |
| CORE.c parse | 352.4 s | **344.1 s** |
| CORE.c optimize | 36.6 s | **36.6 s** |

Milestone 5 recorded **two** `make` figures with two methods
([[milestone-5-rakuobject-layout]]:122-124): 1054 s for an incremental
`make` after a clean nqp build, and 1133 s for `make clean && make`. The
row above compares like with like — both sides are `make clean && make`,
and milestone 6 is 11 s **faster**. There is no build-time regression;
1054 s is not this row's comparator.

`CORE.c total` is recipe wall clock, marker `[583s] +++ Compiling
blib/CORE.c.setting.jar` to `[1040s] +++ Compiling
blib/Perl6/BOOTSTRAP/v6d.jar`; the stage lines themselves sum to 439.9 s,
the difference being JVM start and jar write. The other CORE.c stages:
qast 32.6 s, unit 26.6 s, syntaxcheck/ast/jar 0.0 s. CORE.d 8.8 s,
CORE.e 41.2 s. `v6c` BOOTSTRAP alone took 398 s of the build
([185s] -> [583s]).

**What 1122 s is, in words.** It is the wall clock of `make` alone, run
after two preceding commands in this exact order: `perl Configure.pl
--backends=jvm --prefix=<worktree>/install --silent-build`, then
`make clean`, then the measured `make` — i.e. a full cold build of every
rakudo artifact against an already-clean-built nqp. A later task that
times a **plain incremental `make`** and sets it beside 1122 s is not
comparing the same thing, and on this tree an incremental `make` can be
a 0 s no-op besides (see Ruling above). Reproduce the method before
citing the number.

**Gates.**

- **Sanity (Step 6):** `evalserver-sweep --chunk=25 --jobs=1 --heap=8
  t/01-sanity` — 25 files, 1 chunk, **ok**, 97 s. Zero failures.
- **nqp suite (Step 7):** `./nqp/gradlew -p nqp testNqp` — 151 files,
  13185 tests, 599 s (engine-merge baseline 614 s). Exactly the **nine
  known reds and no tenth**: `t/nqp/021` 6/33, `t/nqp/022` 1/7,
  `t/nqp/044` 1/62, `t/nqp/112` 2/26, `t/qregex` 21/845, `t/p5regex`
  3/182, `t/qast` bad plan at test 10 of 184, `t/jvm/01-continuations`
  3/22, `t/jvm/11-dispatch` 140 of 160 planned. Gradle exits 1 on the
  reds, as it did at the engine merge; the file list is the gate.
- **Jar census (Step 8):** `CENSUS: all 10 jars are unit artifacts` —
  every jar `meta=1 class=0`.

**Ruling (Task 1).** A plain `make` is not sufficient to build this tree
at HEAD after an nqp rebuild, and any later task that rebuilds (T14's
post-rebase build in particular) must run Configure + `make clean` +
`make`, not `make` alone. Costs if wrong: a wasted clean build, ~19 min.
Costs if ignored: a measurement against the previous nqp, silently.

Task 1: implementer DONE_WITH_CONCERNS — rakudo `aa0169ed5a` (ledger only; no
source change in either tree). Gates: t/01-sanity 25/0 in 97 s; `testNqp` 151
files / 13185 tests / 599 s at exactly the nine known reds, no tenth; jar census
10/10 unit artifacts, zero `.class`. Baseline: nqp clean buildJvm 244 s (M5 256),
make 1122 s (M5 1054), CORE.c 457 s (M5 464), parse 344.1 s (M5 352.4), optimize
36.6 s (M5 36.6). Report: task-1-report.md.

**Ruling 3 — the build graph does not express the nqp dependency.** The
implementer found the brief's plain `make` was a 0 s no-op: no rakudo target
lists any nqp artifact as a prerequisite, so the freshly cleaned nqp was
invisible and the baseline would have been built against the PREVIOUS nqp. It
also found the generated Makefile itself predated milestone 5 — `NQP_JARS` still
listed the deleted `asm-9.10.1.jar` and `asm-tree-9.10.1.jar` and omitted
`nqp-truffle.jar`, which is the source of the stale `rakudo-j-build` classpath
the brief had noticed. Repaired in generated state only (`Configure.pl`,
`make clean`, `make`); asm count 2 -> 0 in both Makefile and runner. The two
encoder commits (nqp `7e7aaca61`, `df564ddbb`) were NOT at fault; they built
clean. Plan corrected at Task 14 Step 4, which now runs the full
gradle-clean + Configure + make-clean + make sequence with the reason written
out. Costs if wrong: none — the correction only adds steps that were already
necessary.

**Ruling 4 — BOOTSTRAP v6c stays unmeasured, but named.** The implementer
observed BOOTSTRAP v6c at 398 s of the 1122 s build (35 %), second only to
CORE.c parse and absent from this milestone's measurement list. The sweep stays
on the standalone CORE.c compile: it is the larger single clock, it carries the
named "code is too large" defect, and adding BOOTSTRAP would roughly double the
sweep's compiles. Because the adopted options are build-wide
(`JDK_JAVA_OPTIONS` / `j_truffle_args`), BOOTSTRAP receives every adopted knob
without being measured. Task 11's findings doc now must record the number, say
plainly it was not measured, and name it milestone 7's leading candidate.
Costs if wrong: a knob tuned on CORE.c could be neutral or negative on
BOOTSTRAP, and we would not see it until the next full build — which Task 14's
post-rebase build provides.

Task 1: concern held open for the reviewer — `make` 1122 s is +6.5 % on M5's
1054 s while EVERY component clock came in faster (nqp 244 vs 256, CORE.c 457
vs 464, parse 344.1 vs 352.4). Either the two totals measure different things
or something outside the measured components grew. The task reviewer was asked
to rule on this specifically, because every later task inherits this reference.

Task 1: review (opus) — Spec ✅, Task quality Approved, 0 Critical, 2 Important,
3 Minor. The reviewer verified every recorded number independently against the
job-dir logs and markers, confirmed the toolchain, and confirmed by artifact
mtimes that every rakudo artifact postdates the clean nqp (nqp.jar 12:09:40 ->
Makefile 12:11:01 -> v6c.jar 12:20:56 -> CORE.c.setting.jar 12:28:33 ->
CORE.e.setting.jar 12:29:59), with asm count 0 in both Makefile and runner and
nqp-truffle.jar present.

**Ruling 5 — the +6.5 % make regression DOES NOT EXIST; the plan and the spec
carried the wrong comparator.** Milestone 5 recorded TWO make figures and its
own record says to baseline against both: **1054 s** for `make` after a clean
nqp build (incremental, its Task 6) and **1133 s** for `make clean && make`,
measured twice, with an identical CORE.c parse of 352 s
(memory/milestone-5-rakuobject-layout.md:122-124, verified by the controller).
Milestone 6's 1122 s is a `make clean && make`, so its comparator is 1133 s and
it is **11 s FASTER**, which is what every component clock already said
(nqp 244 vs 256, CORE.c 457 vs 464, parse 344.1 vs 352.4). Two corroborations
from the reviewer: the M6 marker timeline beats milestone 4's clean-build
timeline at every marker (rakudo.jar 185 vs 193, CORE.c start 583 vs 585, end
1040 vs 1052, total 1122 vs 1142); and the M6 components sum to the total with
no slack (150 + 29 + 398 + 457 + 82 = 1116 ~ 1122), which a 1054 s total cannot
contain. The defect was mine, in the spec and the plan, not the implementer's.
Both corrected at the source, with the two-figure rule and the reason written
out. Costs if wrong: none — the correction replaces one recorded M5 number with
the other recorded M5 number, matched to method.

Task 1: minor (deferred): `m6-make.log` carries an unreported
`cp: cannot stat '.../nqp/bin/eval-client.pl'`. Benign — `Makefile:1424` has a
`||` fallback and the sweep uses `tools/build/eval-client.raku` — but a
non-zero-looking line in a baseline build log deserved a sentence.
Task 1: minor (deferred): no sanity-sweep log was kept in the job dir, so that
one gate rests on inference (its 97 s fits the 12:30:00-12:32:25 gap) rather
than on a log. Future gates tee.
Task 1: minor (deferred, for the final review): the implementer speculated that
the 1122 s gap was "the Configure regeneration plus a fully cold gen/" without
checking the M5 record for a second figure; the diligence it applied to CORE.c
was not applied one row up, where it mattered most.

Task 1: fix round 1/5 (2 addressed, 0 open — comparator swapped to M5's 1133 s
clean figure with the method in the row label; "What 1122 s is, in words"
subsection naming Configure.pl + `make clean` + `make`; plus the
gen/jvm/BOOTSTRAP accuracy correction and the benign-cp sentence; commit rakudo
`aa0169ed5a` amended to `1477806f7b`).
Task 1: re-review (opus) — FINDING 1 ADDRESSED, FINDING 2 ADDRESSED, accuracy
sub-item PRESENT, benign-cp sentence PRESENT, NEW BREAKAGE NONE. Diff was 110
insertions / 9 deletions in one file; all nine deletions inside the implementer's
own entry and exactly the passages the findings required removing. Controller
blocks verified intact and consistent with the same correction now in the plan
and the spec. Ruling 5's arithmetic re-checked independently (150+29+398+457+82
= 1116).

**Controller annotation (re-review Minor, closed here rather than in a fix
round).** The implementer's status line above still reads `make 1122 s (M5
1054)` with an unqualified comparator. That comparison is RETRACTED: read it as
**M5 1133 s clean; 1054 s was incremental**, per Ruling 5. The line stays as the
historical record of what was first reported. Minor findings do not enter the
fix loop, and curating this ledger is the controller's job, not the
implementer's.

Task 1: minor (deferred): the deferred-minor line about the unreported `cp`
message is now stale — the fix added exactly that sentence. Left standing
because it is a controller line and the record of what the review found.
Task 1: minor (deferred): the baseline table's column header is a bare
"milestone 5"; it is unambiguous only because the make row carries its method in
the row label. Other rows state no method. A future table should put the method
in the header.

Task 1: complete (commits `0a43dbed1e`..`1477806f7b`, review clean; plus
controller commit `98f2db7132` correcting the plan and the spec at source).

Task 2: implementer dispatched (opus); BASE rakudo `32f3800ee0`. Test-first:
fixture, failing test, tool, passing test, then a real short-workload smoke whose
required positive marker is a `done=` count above zero.

Task 2: complete (commit rakudo `d92d405b80`). Test-first order honoured:
fixture (6 lines, verbatim from the brief) → test (8 assertions, verbatim) → RUN
AND SEE IT FAIL (7 of 8 failed; only the `nok` "ignores non-trace lines"
assertion passed, vacuously, against the empty output of a missing tool) → tool
(verbatim from the brief) → 8/8 pass. Nothing in the brief was altered; both
files and the fixture were transcribed straight out of it by line range rather
than retyped, so the asserted values (`done=2`, `failed=2`, `mean=6500`,
`min-too-large-size=48213`, `min-too-large-size=none` on an empty log) all
reproduced on the first run of the finished tool.

Task 2: the field-driven property is intact. The parser splits the tail on `|`
and matches `Tier`/`Time`/`Reason` by each field's leading word, so the two
unverified `opt failed` fixture lines commit the tool to nothing but the
presence of a field named `Reason` — which is what Task 3 Step 4 goes and
confirms against a real failing trace.

Task 2: smoke test PASSED the required positive marker. `NqpCheck` under
`-Dpolyglot.engine.TraceCompilation=true` (java exit 0, "# Truffle runtime:
Oracle GraalVM", `ok - add` / `ok - fib`) produced
`events=2 / done=2 / min-too-large-size=none / total-compiler-ms=93`, the two
roots being `org.graalvm.polyglot.Value<Program>.execute` (60ms) and
`<anon>[0]` (33ms). `done=` above zero: the instrument sees real data.

Task 2: notes for Task 3, none of them defects. (a) The brief's Step 6 command
is one shell statement mixing `$CLAUDE_JOB_DIR` into a `raku` invocation, which
this worktree-isolated harness refuses to run; it works split into two plain
commands with the job path written out. (b) `total-compiler-ms` and the
top-roots table count non-NQP roots too — the polyglot entry point is half of
the smoke run's two events — so a Task 3 reading of "compiler time" should say
whether it means all roots or only the bracketed (NQP program) ones. (c) `Time`
is read as the total, not the `(a+b)` split. (d) `getName()` is at
`nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java:90-94`; the
brief cites 91-93, off by one line at each end and immaterial.

Task 2: the entry above was first written against the pre-amend hash
`4d9012b443`; `d92d405b80` is the same tree after one amend that only filled in
that hash, and this follow-up commit corrects the citation. The tool commit to
quote is `d92d405b80`.

Task 2: implementer DONE — rakudo `d92d405b80` (tool, tests, fixture, ledger) and
`da7b413cca` (ledger-only, fixing a self-citation: a ledger cannot cite its own
pre-amend hash). 8/8 tests pass, red stage verified first at 7/8 failing. Smoke
on a real short workload: events=2, done=2, marker met. Controller provenance
check: the committed tool is byte-identical to the copy validated before the plan
was committed, apart from its comment block; the fixture is byte-identical.
Report: task-2-report.md.

Task 2: review (opus) — Spec ✅, quality NEEDS WORK, **1 Critical**, 3 Important,
4 Minor. Two commits ruled correct; explicitly do NOT squash, as squashing
re-breaks the self-citation the second commit exists to fix.

**Ruling 6 — the Critical defect is MINE, in the fixture, and it would have
silently skipped the milestone's largest lever.** I wrote the two `opt failed`
fixture lines from Truffle's documented layout rather than from this tree, and
recorded in the plan that Task 3 would verify them. The reviewer did better than
verify: it decompiled `TraceCompilationListener` out of this tree's own
`nqp/build/jvm/share/truffle/truffle-runtime-25.2.4.jar` and read the format
string. `FAILED_FORMAT` is `... |Tier %d|Time %18s|Reason: %s|UTC %s|Src %s` —
**with a colon** — while `DEOPT_FORMAT`, `INV_FORMAT` and `UNQUEUED_FORMAT` use
`|Reason %s` without one. The colon falls on exactly the verb that matters. The
parser required whitespace after `Reason`, so against a real trace it would have
parsed no reason at all and printed `min-too-large-size=none`. Task 4 would have
read that as "no root was too large" and set no threshold, on a compile carrying
roughly 114 of them — a plausible number, not a crash, which is the worst
failure mode an instrument has. The field-by-leading-word property protected
against field RE-ORDERING but not against a field NAME carrying punctuation.
Fixed in the loop: optional colon, a real-format fixture line, and a loud
`(failed=N, reasons-parsed=0)` annotation so a silent `none` can never again be
mistaken for "nothing was too large". Plan Task 3 Step 4 rewritten from a repair
step into a confirmation step that says STOP on that signature. Costs if wrong:
none — the parser now accepts both spellings, which is strictly wider than
either alone.

Task 2: minor (deferred): `tier 0` / `ms 0` defaults make deopt and invalidation
lines (which legitimately carry no Tier or Time) indistinguishable from a parse
miss.
Task 2: minor (deferred): the test writes `fixtures/empty.log` into the repo and
unlinks it at the end; a mid-test failure leaves it behind. `$*TMPDIR` is the fix.
Task 2: minor (deferred): report and ledger cite `NqpRootNode.java:91-93`; the
method is 91-94. Immaterial, self-noted by the implementer.

Task 2: fix round 1/5 (4 addressed, 0 open — commit stamped 19:25, the third on
top of `d92d405b80` / `da7b413cca`). CRITICAL 1: the colon is now optional
(`^ 'Reason' ':'? \s+ (.+) $`); fixture lines 4-5 rewritten into the real
`|Reason: %s|` spelling and a new `opt deopt` line carries the colon-free
spelling so both stay covered; and a failed-but-unreasoned run now prints
`min-too-large-size=none  (failed=N, reasons-parsed=0)`, with a second fixture
`fixtures/trace-noreason.log` pinning exactly that string. The red run is on the
record: against the shipped tool, assertions 4 and 5 failed with the reason lost
and `none` printed — the defect reproduced live before it was fixed, it was not
taken on faith. IMPORTANT 2: the head is cut at the first whitespace-then-`|`
(the format's `%-50s |` separator; a `|` inside a root name is never preceded by
whitespace), so `infix:<+|>[12345]` survives whole, and both discard paths are
tallied — `unparsed=` for `[engine] opt ` lines that fail the head match,
`non-trace-lines=` for the rest. IMPORTANT 3: the minimum now prints its
population — `too-large roots: N (S sized, U unsized)`, the sized names in size
order, and an explicit `UNSIZED (excluded, so the minimum above reads high)`
line when U > 0. IMPORTANT 4: `nqp-root-ms=` added alongside an unchanged
`total-compiler-ms=`. Test gap closed: `events=5` pins the accepted-line count,
which is structurally why the colon got through.

Task 2: fix round 1/5 verified against reality, not only against the fixture.
16/16 pass. The Step 6 smoke log still parses (`events=2 done=2 unparsed=0
non-trace-lines=11 nqp-root-ms=33` of `total-compiler-ms=93`). And a line built
by `sprintf` from the reviewer's verbatim `FAILED_FORMAT` — not hand-padded —
now yields `reasons-parsed=1`, the full reason text, and
`min-too-large-size=31337`: a number, where the shipped tool gave `none`.

Task 2: fix round 1/5 note. This commit also carries the controller's own
uncommitted ledger additions (the Critical 1 write-up and the three deferred
minors), because the ledger is one blob and the fix entry had to append to it.
Nothing above the appended lines was touched. The plan file
`2026-09-12-jvm-milestone-6-compiler-workload.md` has uncommitted controller
edits too and was deliberately LEFT uncommitted, being outside the
implementer's commit scope.

Task 2: fix round 1/5 (4 addressed + the test gap, 0 open — optional colon in the
Reason match; real-format fixture lines with a colon-free `opt deopt` line keeping
the other spelling covered; loud `(failed=N, reasons-parsed=0)`; head cut at the
first whitespace-then-pipe so `infix:<+|>[12345]` survives whole; `unparsed=` and
`non-trace-lines=` tallies; too-large roots listed by size with an explicit
UNSIZED-excluded warning; `nqp-root-ms=` beside `total-compiler-ms`; assertions
for `events=5`, `unparsed=0`, `reasons-parsed=3`; suite 8 -> 16. Commit rakudo
`3f14c9c6ed`). The implementer reproduced the bug against the shipped tool before
fixing it, and noted why it was survivable: the unparsed failures grouped under an
EMPTY key rather than vanishing, so the mean-time assertion kept passing.
Task 2: re-review round 1 (opus) — all four ADDRESSED plus the test gap,
independently verified: the re-reviewer decompiled the same jar and confirmed all
eight trace formats, built its own real-format line and OBSERVED
`min-too-large-size=31337`, confirmed the colon-free deopt reason parses, ran the
suite at 16/16, and confirmed by `git show --numstat` that the ledger hunk is
77 insertions / 0 deletions, so the controller's rulings are provably
byte-unaltered rather than merely present. New breakage: none; the head cut is
strictly wider than the old split, since all eight formats write `%-50s` followed
by whitespace before the first pipe.

**Ruling 7 — the adversarial pass found Critical 1's failure mode by a second
route; that is a fix round, not a deferral.** `min-too-large-size` selected only
on `code is too large`, but this tree's own
`/usr/lib/jvm/java-25-graalvm/lib/libjvmcicompiler.so` also carries
`too big to safely compile. Node count: ...`, the PermanentBailoutException on the
graph-size limit — a different spelling of the same phenomenon. Observed on a
mixed trace: the graph-size root was silently dropped, leaving a plausible
TOO-HIGH minimum, and on a trace carrying only that spelling, a bare `none` with
NO annotation, because the reasons-parsed guard correctly does not fire (the
reason parsed; it simply was not recognised). Too-high is the dangerous direction:
Task 4 sets the threshold above the offender and the knob misses the roots it
exists to skip. Also found: the round-1 head fix was not mirrored on the tail, so
a reason text containing a pipe is truncated — realistic, because Rakudo operator
names appear in inlining-failure reasons, and it defeats any spelling alternation
because a truncated reason matches nothing. Both are load-bearing for Tasks 3 and
4, so round 2 was dispatched rather than parking them. The durable part of the fix
is not the list of spellings but the requirement to PRINT unclassified failure
reasons with their sizes, so a future GraalVM inventing a fourth spelling is loud
instead of silently absent. Costs if wrong: a wider selector could in principle
classify a non-size bailout as one, which would push the minimum DOWN and make the
threshold conservative — the safe direction, and visible in the printed list.

Task 2: fix round 2/5 (2 addressed, 0 open — commit stamped 19:35, the fourth;
nothing squashed). FINDING A: `min-too-large-size` no longer selects on one
spelling. `@SIZE-BAILOUT-SPELLINGS` is a substring alternation over `code is too
large`, `too big to safely compile` and `exceeds`, so the graph-size
PermanentBailoutException joins the population instead of vanishing from it. The
half that outlives the list is the new **unclassified failure reasons** report:
every parsed failure reason that matched no spelling is printed beneath the
minimum, named, with the sizes of the roots carrying it. In the fixture that
reads `count=1  sizes: 700  inlining budget exhausted` directly under
`min-too-large-size=900` — a size BELOW the minimum, which is exactly the alarm
shape: a fourth spelling now shows up as a line to read rather than as an
absence. FINDING B: the head fix is mirrored on the tail. A tail piece that does
not look like a field start (`^ <[A..Z]> \w* ':'? \s`) is rejoined to the piece
before it, so `inlining of infix:<+|> failed: code is too large` survives whole
and matches the spelling it was cut off from. The rejoin rule is a SHAPE test,
not a list of known field names, so an unfamiliar future field still reads as a
field and the worst misfire is an over-long value, never a truncated one.

Task 2: fix round 2/5 red run, on the record. Fixture grew by three
`FAILED_FORMAT`-generated lines (`graph_bail[900]` on the graph-size spelling,
`inline_pipe[1500]` with a pipe inside its reason, `misc_fail[700]` on an
unclassifiable reason) plus a `trace-unknown-bailout.log` where every failure is
an unknown spelling. Against the round-1 tool, six assertions failed and the two
symptoms printed verbatim: `min-too-large-size=48213` — the plausible too-high
number, with the 900- and 1500-word roots silently absent — and the reason
`inlining of infix:<+` truncated at the pipe. After the fix, 21/21, and the same
mixed-spelling trace reports **min-too-large-size=900**.

Task 2: fix round 2/5 reality checks unchanged from round 1. The Step 6 smoke
log still parses (`events=2 done=2 unparsed=0`), and the round-1 line built by
`sprintf` from the verbatim `FAILED_FORMAT` still gives `min-too-large-size=31337`.
The new `trace-unknown-bailout.log` prints an honest `min-too-large-size=none`
with `count=1  sizes: 555  graph too chunky for the backend` underneath it.
The plan file is no longer modified in the working tree; this commit carries
the controller's round-2 ledger additions, appended-to and otherwise untouched.

Task 2: fix round 2/5 (2 addressed, 0 open — `@SIZE-BAILOUT-SPELLINGS` alternation
plus an `unclassified failure reasons` block printing count, sizes and reason
text; tail pieces that do not look like a field start rejoined with their pipe,
tested by SHAPE rather than by a name list, so the worst misfire is an over-long
value and never a truncated one. Suite 16 -> 21. Commit rakudo `d9a77d1fb5`.)
Both symptoms were reproduced against the round-1 tool first: `min-too-large-size`
48213 with the 900- and 1500-word roots absent, and the reason truncated at the
pipe; six assertions failed.
Task 2: re-review round 2 (opus) — both ADDRESSED, verified on the reviewer's own
five-event mixed trace (`min-too-large-size=900`, all four roots listed), no
regression on the lone real-format line (31337), suite OBSERVED 21/21, ledger
hunk 78 insertions / 0 deletions so controller content is provably unaltered.
The field-start shape rule was probed against all eight formats decompiled from
`TraceCompilationListener`: exactly one legitimate field fails it, `Count/Thres`
(`\w*` stops at the slash), and that is harmless because the tier match is
anchored and nothing reads Count/Thres. A reason containing `|Foo ` still
truncates, but then matches no spelling and surfaces in the unclassified block
with its size, so it is visible rather than absent.

**Ruling 8 — `exceeds` was my guess and it is worse than no guess at all.** I
supplied three spellings in the round-2 brief; only two were ever verified to
exist in this tree. The re-reviewer observed a small root failing with
`inlining of foo exceeds the inlining budget` being classified as a size bailout,
giving `min-too-large-size=40` with `by size: tiny[40], big[48213]`. A threshold
of 40 wire words would refuse essentially every compilation on the 460 s run,
which does not bias Task 4's measurement but destroys it. Worse, the misfire is
invisible to the tool's own alarm BY CONSTRUCTION: a reason that matched a
spelling is by definition not unclassified. Round 3 removes `exceeds`, keeping
only `code is too large` (the trace) and `too big to safely compile`
(libjvmcicompiler.so). The general lesson is recorded beside the list in the
code: the unclassified block IS the mechanism for unknown spellings, and it
works; a guessed-at loose substring does not extend the tool's reach, it
bypasses that mechanism and turns a loud unknown into a silent wrong answer.
Plan Task 4 Step 1 now requires reading the failures-by-reason, `by size:` and
unclassified blocks beside the number, with two named plausibility checks.
Costs if wrong: a genuine size bailout under a third spelling now lands in the
unclassified block instead of the population, so the minimum reads high — but
loudly, with the reason and its size printed for a human to act on.

Task 2: PARKED residual — a partial reason-parse leaves a silent too-high
minimum. With one failure whose reason parses and one whose does not, the
`(failed=N, reasons-parsed=0)` note does not fire (it requires zero parsed) and
`@unclassified` skips empty reasons, so the unparsed group appears in
failures-by-reason with a count but without its sizes. Ruling: park. It needs two
different shapes among `opt failed` lines, and `FAILED_FORMAT` is a single
constant in `TraceCompilationListener`, so every such line shares one shape.
Costs if wrong: a too-high threshold on a trace whose failure lines are somehow
heterogeneous — which Task 4 Step 1's new plausibility checks would surface.

Task 2: fix round 3/5 (1 addressed, 0 open — commit stamped 19:40, the fifth;
nothing squashed). `exceeds` is deleted from `@SIZE-BAILOUT-SPELLINGS`, which
now holds only the two spellings verified to exist in this tree: `code is too
large` from the compilation trace and `too big to safely compile` from
libjvmcicompiler.so. The reasoning is in a comment beside the list, in the
controller's own terms: a guessed spelling does not extend the tool's reach, it
BYPASSES the mechanism that already covers the unknown. The unclassified block
prints an unmatched reason with its count and sizes, loudly, for a human. A
loose entry converts that loud unknown into a silent wrong answer — and the
wrong answer is invisible to the tool's own alarm by construction, since a
reason that matched a spelling is by definition not unclassified. The comment
ends with the rule for next time: when a real trace shows a bailout this list
does not know, it lands in that block; add it here THEN, with the trace that
proves it.

Task 2: fix round 3/5 red run. A `tiny[40]` line was added to the fixture in the
`FAILED_FORMAT`, reason `inlining of foo exceeds the inlining budget`. Against
the round-2 tool, four assertions failed and the misfire printed exactly as the
re-reviewer described it: `min-too-large-size=40` over
`by size: tiny[40], graph_bail[900], inline_pipe[1500], parse_stmt[48213],
parse_expr[91002]`. After the deletion, 22/22 and
**min-too-large-size=900**, with `count=1  sizes: 40  inlining of foo exceeds
the inlining budget` in the unclassified block where a human will read it. Only
one assertion was added, as directed; the "must NOT enter the population" half
is carried by the three assertions that already existed (min=900, the by-size
membership line, and `too-large roots: 4`), all three of which failed in the red
run and pass now.

Task 2: NEW OBSERVATION from round 3, NOT fixed, controller's call. Round 3's
fixture created the first tie in a `.classify(...).sort(-*.value.elems)` group,
and tied groups reorder between runs: five consecutive runs of the same trace
printed the two count=1 unclassified reasons in a different order twice.
`classify` returns a Hash and the sort is stable, so ties inherit MoarVM's hash
iteration order. It affects the `failures by reason` block equally. No assertion
is at risk (all use `contains`) and no number is wrong, but two runs of one
trace produce textually different reports, which will be a nuisance the moment
Task 3 diffs them. The fix is a tiebreak key on the sorts, roughly
`.sort({ (-.value.elems, .key) })`. Left alone because this round was scoped to
one line plus a test, and scope is the controller's to set.
