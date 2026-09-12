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

Task 2: fix round 3/5 (1 addressed, 0 open — `exceeds` removed; the list holds
only `code is too large` and `too big to safely compile`, the two spellings
verified in this tree; a 16-line comment beside it carries the mechanism argument
and the rule for adding a third later, with the trace that proves it. Suite
21 -> 22. Commit rakudo `0b8424bd1c`.) Seen red first: the same fixture gave
`min-too-large-size=40` before the edit, with the unclassified block silent.
Task 2: re-review round 3 (opus) — ADDRESSED, verified on the reviewer's own
trace: `min-too-large-size=2100` with `tinyroot[37]` out of the population and
named and sized in the unclassified block; no regression (`too big to safely
compile. Node count: 41234` still classified; a sprintf'd real-format line still
gives 31337). Suite OBSERVED 22/22. New breakage: none. Ledger hunk 89
insertions / 0 deletions.

**Ruling 9 — the tie-ordering nondeterminism is COSMETIC; deferred, not fixed.**
The implementer volunteered that tied groups reorder between runs because
`classify` returns a Hash, and correctly declined to fix it unasked. Verified
rather than accepted: ten runs over one trace produced ten distinct texts but a
byte-identical sorted multiset of every integer in the output (one distinct md5),
`min-too-large-size=900` in all ten, each count travelling with its own reason
text, and the top-roots table deterministic because it sorts a stable list in
file order. Tasks 3-7 record NUMBERS into a configuration table; none of them
diffs report text. So this cannot move a result. The one-line cure is a tiebreak
key on the two `classify` sorts if it ever becomes a nuisance. Costs if wrong:
a reader diffing two reports sees transposed lines and no wrong number.

**Ruling 10 — the off-by-one advisory was already right in the plan, and is now
explained there.** `NqpRootNode.prepareForCompilation` answers `programSize <=
MAX_COMPILE_SIZE`, INCLUSIVE (`NqpRootNode.java:119-123`), so setting the knob to
`N` still admits the root the number came from and the compile spends its 6.4 s
failing to install exactly as before. Task 4 Step 1 already said `N - 1`; it now
says WHY, because the failure mode is a plausible non-result — the knob appears
to do nothing — rather than an error. Costs if wrong: none; the arithmetic was
already correct.

Task 2: minor (deferred): `tier 0` / `ms 0` defaults make deopt and invalidation
lines indistinguishable from a parse miss (carried from the first review).
Task 2: minor (deferred): the test writes `fixtures/empty.log` into the repo
rather than `$*TMPDIR`; a mid-test failure leaves it behind.
Task 2: minor (deferred): `NqpRootNode.java:91-93` cited where the method is
91-94.

Task 2: complete (commits `d92d405b80`..`0b8424bd1c`, review clean after three
fix rounds; plus controller commits `975324309f` and `bd0326e223` correcting the
plan at source). Three rounds were spent because each found a defect that would
have corrupted the sweep SILENTLY rather than stopping it: the `Reason:` colon,
the second bailout spelling, and the loose `exceeds` guess. The instrument is the
one Task 4's threshold comes from, so the rounds bought the milestone's central
number.

Task 3: implementer dispatched (opus); BASE rakudo `3db3362101`. One traced
standalone CORE.c compile (~460 s), summarized. Instructed to STOP and report
BLOCKED on the `none`-with-failures signature, and to report explicitly on a
spuriously tiny minimum or anything size-related landing unclassified.

Task 3: the traced CORE.c baseline. One standalone compile at rakudo `3db3362101`
/ nqp `41c294b02`, `EXIT=0 verdict=ok elapsed=434s`, `--output` to the job dir so
`blib` is untouched. Stages: start 0.001, parse **333.841**, syntaxcheck 0.000,
ast 0.001, optimize **36.584**, qast 34.266, unit 27.539, jar 0.000 (sum 432.2 s).
Summarizer: `events=10759 done=5656 failed=444 deopt=3249 inval.=1267 reprof=143
unparsed=0 non-trace-lines=464803 reasons-parsed=4960`,
`total-compiler-ms=2143944`, `nqp-root-ms=1937603`.

Task 3 vs Task 1: comparable, and the difference is explained. Task 1 measured
457 s marker-to-marker inside `make` with stages summing 439.9 s; this is 434 s
wall with stages summing 432.2 s. `Stage optimize` is 36.584 against 36.588 —
the same number. `Stage parse` is 333.8 against 344.1, 3 % faster, with
TraceCompilation ON; tracing loads the compiler threads, not the interpreter, so
3 % is run-to-run variance and not a measurement artefact. Nothing here voids
Task 1's baseline.

**Task 3 — the size-bailout lever has almost nothing left to pull.**
`min-too-large-size=2070`, NOT `none`, so Task 4 is not blocked and the
`(failed=N, reasons-parsed=0)` alarm did not fire (4960 reasons parsed). But the
population behind it is **2 roots**, not 114: `IMPL-FOLD-CONSTANT[2070]` and
`IMPL-OPTIMIZE-EXPRESSION[4030]`, 6.9 s of compiler time between them. The
2026-09-07 trace recorded 114 roots at a mean 6.4 s, 733 s. That cluster is gone
— 0.3 % of what it cost — and nothing in this milestone did it; milestone 5's
layout work and the engine merge are the unexamined candidates. Task 4 should
still run (the knob is unmeasured and the arithmetic is cheap) but its ceiling on
CORE.c is now ~7 s of 2144 s compiler time and ~0 s of the 434 s wall clock, and
it should be judged as a runtime-side decision rather than a build-side win.

**Task 3 — the minimum is plausible, and the unclassified block is doing its
job.** `by size:` has only the two entries above: 2070 then 4030, a factor of 2,
not orders of magnitude, so no spuriously tiny minimum. The unclassified block
holds one group, 442 of the 444 failures: `PermanentBailoutException: Too deep
inlining, probably caused by recursive inlining.`, mean 54 ms, 23.7 s total. It
is **not** a size bailout and must not be added to the selector's spellings: its
sizes run from **27** to 17545 wire words, so classifying it would set
`min-too-large-size=27` and produce a threshold at which essentially nothing
compiles — exactly the failure Ruling on the `exceeds` guess anticipated. The
bailout's own inlined-method dump names the recursion, and it is Java-side:
`Throwable.printStackTrace()` -> `ExceptionHandling.dieInternal` ->
`ClassRepository.parse`/`SignatureParser.parseClassSignature`, 33 frames deep.
Recorded in the findings doc as a milestone 7 candidate; 442 discarded
compilations from one Java call chain.

**Task 3 — Step 4 confirmed, not repaired.** The real `opt failed` lines carry
`|Reason: ` with the colon, as Task 2's decompilation said, and the parser reads
them: `unparsed=0`, both reason groups non-empty. One wrinkle worth recording:
the `Too deep inlining` reason text contains newlines (the inlined-method dump),
so each such failure spills ~1000 lines that do not start with `[engine] opt `.
They land in `non-trace-lines=464803` and the reason parses from the first line.
The tally is loud rather than silent, and no event was lost to it.

**Task 3 — Step 5: named Sources do NOT reach the statistics.** All 10 763 trace
lines carrying a `Src` field report `Src n/a`, without exception, and the
`CompilationStatistics` block has no per-Source grouping: it names targets by
root name (`maxTarget=IMPL-FOLD-CONSTANT[2070]`, `maxTarget=walk[7260]`). The
engine merge's per-block naming reaches the statistics through
`NqpRootNode.getName()` — per-block, distinguishing, with the wire-word count in
brackets — and not through Truffle Sources, which are absent. Attribution works;
it is name-based. A real `SourceSection` on the root node is what file/line
attribution would need. The deferred follow-up is answered: no.

Task 3: minor: four trace lines were swallowed by stdout interleaving — the
`--stagestats` label for optimize/qast/unit/jar is printed before the stage runs,
and a compiler-thread trace line landed on the same line, so those four events
(2 `done`, 1 `inval.`, 1 `reprof`) do not start with `[engine] opt ` and were
counted as non-trace lines. This is why the summarizer reports `done=5656` while
the statistics block reports `Success: 5658`; the stage times themselves survive
on the following line and were read from there. Every later task in the sweep
will see the same four-line loss identically, so it cannot move a comparison.

Task 3: review (opus) — Spec ✅, quality Approved, 0 Critical, 1 Important,
3 Minor. blib verified untouched (`CORE.c.setting.jar` still 12:28 / 5865093 B;
the run's 5865125 B jar is in scratch). Every figure reproduced independently.

**The headline is VERIFIED, two ways.** The reviewer counted the too-large roots
itself: a grep of the trace gives 2 (`IMPL-OPTIMIZE-EXPRESSION[4030]` 3086 ms at
log line 153365, `IMPL-FOLD-CONSTANT[2070]` 3861 ms at line 439164, sum 6947 ms),
and Graal's own `CompilationStatistics` tally at line 472380 independently reads
`BailoutException: Code installation failed: code is too large: 2` — a count the
summarizer never touches. Only three occurrences of "too large" exist in the whole
30 MB log. `reasons-parsed=4960` decomposes exactly as 444+1267+3249.
**114 roots / 733 s -> 2 roots / 6.9 s is real, not a parse artefact.**

**Ruling 11 — Task 4's premise is gone; the task is REFRAMED, not skipped.**
`NQP_CODE_MAX_COMPILE` was placed first in the sweep to reclaim the 733 s that
114 roots spent failing to install. That waste no longer exists. And the knob's
own rationale — `NqpRootNode`'s comment that "such a root runs interpreted
afterwards regardless, so refusing up front costs it nothing" — held ONLY for
roots destined to fail; `prepareForCompilation` gates every root, so a threshold
of 2069 refuses compilation of every root above 2069 wire words, almost all of
which compile successfully today. It is therefore no longer a free-reclamation
experiment but a crude probe of the milestone's real thesis, that the compiler's
run-once code is over-compiled — and Task 3 measured 2144 s of compiler-thread
work across a 434 s wall compile, ~5 cores, 90 % of it on NQP roots. One compile
is cheap and the effect will be large in one direction or the other, so it runs,
judged on four quantities rather than wall clock alone (wall, total-compiler-ms,
done, failed), with a large fall in compiler work at a flat wall clock recorded as
a real result that would demote Task 7's thread knob before it runs. Runtime-side
adoption is off the table regardless: refusing to compile large roots at run time
costs Rakudo's runtime performance, which outranks compile time by standing user
priority. Costs if wrong: one 8-minute compile spent confirming a null.

**Ruling 12 — the 442-root bailout is milestone 7's lead lever, and it is OURS,
not the JDK's. It is NOT implemented in milestone 6.** The reviewer took the
implementer's diagnosis apart and improved it. There are two recursion shapes,
not one: `ClassRepository.parse(String) [33]` tops 237 of the 448 dumps, and
`java.lang.Class.getSimpleName() [495]` tops the other 203. Both are entered
through `java.lang.invoke.Invokers.newWrongMethodTypeException` (416 occurrences)
called from `NqpOps.bindattr(NqpOps.java:1517)` and `NqpOps.getattr` at 334
frames — the sited MethodHandle road added in MILESTONE 5. Graal is inlining the
exception-CONSTRUCTION branch of our own `invokeExact` sites, whose message
formatting drags `MethodType.toString` into `Class.getSimpleName` into the
generics `SignatureParser`. It is speculation, not throwing: `non-trace-lines`
464803 is ~448 dumps x ~1000 lines with no room for 442 printed traces, and all
480 `dieInternal` occurrences are dump entries rather than output. 442 roots bail
and stay interpreted for the whole compile. Candidate fixes named: an `asType` or
explicit guard so the exception branch leaves the graph, or a `@TruffleBoundary`
on the die path. NOT done here: Phase A is configuration-only by the approved
spec, and a runtime change mid-sweep would invalidate every later comparison
under the forward-only rule. Costs if wrong: milestone 6 ships without what may be
its most valuable finding implemented — but it ships it fully diagnosed, which is
what a measurement milestone is for.

Task 3 fix round 1: the bailout diagnosis corrected and promoted, plus two wrong
numbers. Re-derived from the same log; no re-run. (1) There are TWO recursions,
not one. Over the 442 in-trace dumps (448 in the file, 6 of them reprints inside
the statistics block): chain A 238 dumps, chain B 204, 238+204=442 with no
remainder. (2) The entry point is OURS in both, which is what my first account
got wrong. Chain A, in 238 of 238 dumps: `NqpRootNodeGen.execute` ->
`handleCreateOp_` -> `NqpRootNode$CreateOp.doCreate` -> `NqpTypeOps.create` ->
`VMArray.allocate` -> `ExceptionHandling.dieInternal(ExceptionHandling.kt:47)` ->
`Throwable.printStackTrace()` -> `ClassRepository.parse` x33; kt:47 is
`if (tc.gc.noisyExceptions) (t ?: Throwable(msg)).printStackTrace()`, a debug
branch behind a mutable flag Graal cannot fold. Chain B: `handleBindAttrOp_` ->
`doBind` -> `NqpOps.bindattr(NqpOps.java:1517)` (39) / `NqpOps.getattr(:1482)`
(165), 39+165=204 exactly -> `Invokers.newWrongMethodTypeException` (408 = 204x2)
-> `MethodType.toString` -> `Class.getSimpleName` [495] (201 at exactly 495) —
milestone 5's sited MethodHandle road, with Graal inlining the
exception-CONSTRUCTION branch of `invokeExact`. (3) Nothing is throwing: zero
`Unhandled exception` / `at org.raku` lines in 30 MB, all 476 `dieInternal`
occurrences are dump entries, and non-trace-lines=464803 ~ 442 x 1000 leaves no
room for printed traces. Speculation, not failure — said explicitly in the doc so
no reader goes hunting a crash.

**Task 3 fix round 1 — this is a milestone 7 LEVER, not a candidate.** The clock
is not the 23.7 s of compiler time; it is 442 roots that bail and therefore stay
INTERPRETED for the whole compile, on a workload that is 90 % interpretation
(Stage parse 333.8 of 434 s). Two one-sided fixes, both code and neither a knob,
so neither belongs to this sweep: `@TruffleBoundary` on `dieInternal` or on the
`noisyExceptions` branch (238 roots), and an `asType`/guard at the `invokeExact`
sites so the WrongMethodTypeException construction branch is provably dead
(204 roots). Written into the findings doc with both chains, their counts, our
entry points with file and line, the speculation evidence, and the two fixes.

Task 3 fix round 1 — numbers: findings doc said the surviving cluster is "0.3 %
of the compiler time that cluster once cost"; 6.9/733 = **0.9 %**, and the doc now
carries both ratios with their arithmetic (6.9/733 = 0.9 %, 6.9/2144 = 0.3 %).
Report section (b) had the two roots' times swapped: `IMPL-OPTIMIZE-EXPRESSION[4030]`
is 3086 ms (id 2765) and `IMPL-FOLD-CONSTANT[2070]` is 3861 ms (id 12556); fixed
in place with a note, totals unaffected. Also added: the two size bailouts are
confirmed independently of the summarizer by Graal's own statistics tally
(`Code installation failed: code is too large: 2`) and by `too large` occurring
three times in the whole log. The refusal to teach the selector the
`Too deep inlining` spelling is now argued IN THE DOC (sizes 27..17545, so it
would set the threshold to 27 and destroy every later measurement) rather than
only in the report. Deferred as instructed: the Task 1 wall-clock citation of
457 s against the markers file's 460 s.

Task 3: fix round 1/5 (1 Important + 2 Minor addressed, 0 open — both recursion
chains with counts, our entry points named with file and line, speculation stated
explicitly, promotion from candidate to lever with candidate fixes, the
selector-refusal reasoning moved into the doc, 0.3 % -> 0.9 %, the swapped root
times un-swapped. Commit rakudo `0c0521a538`.) The implementer went past the
finding: it traced Chain A, which the review had NOT examined, to
`handleCreateOp_` -> `CreateOp.doCreate` -> `NqpTypeOps.create` ->
`VMArray.allocate` -> `ExceptionHandling.dieInternal(ExceptionHandling.kt:47)` in
238 of 238 dumps.
Task 3: re-review round 1 (opus) — every item ADDRESSED, no new breakage, ledger
hunk +98/-0. It re-derived the decomposition itself by segmenting the 442
in-trace dumps and classifying each: records=442, chainA=238, chainB=204, both=0,
neither=0 — a clean partition, so the identity is real and not two off-by-ones.
Cross-checks all hold (476 = 238x2 for `dieInternal`, `VMArray.allocate`,
`NqpTypeOps.create` and `handleCreateOp_` alike; 408 = 204x2; 165+39 = 204;
`Permanent Bailouts: 444` = 442 + the 2 too-large). **The implementer's counts
are right and the FIRST review's 237/203/448 were wrong** — a whole-file
top-frequency heuristic that summed to 440 with 8 unattributed, missing 2 dumps
led by `AbstractRepository.<init>` and 3 led by `getSimpleName() [494]`, and
counting the 6 statistics-block reprints.

**Ruling 13 — my `@CompilationFinal` suggestion was wrong, and the reviewer
showed why.** I proposed marking `noisyExceptions` `@CompilationFinal` so Graal
would fold the branch away instead of cutting the inlining at a boundary. It
would be a NO-OP: `@CompilationFinal` on an INSTANCE field folds only when the
receiver is a partial-evaluation constant, and `tc` comes off the frame
(`NqpRootNode.java:125`), so `tc.gc` is an ordinary field load and never
constant. Folding would need a `static final` hoist — which is what every other
env flag in the tree already is. And even hoisted it is worse ALONE than the
boundary, because folding the flag removes only the `printStackTrace` branch
while the rest of `dieInternal`, its 40-frame `StringBuilder` walk and its
`VMExceptionInstance` construction, stays inlinable. Recorded conclusion:
**`@TruffleBoundary` is the fix; a `static final` hoist is a cheap complement,
not an alternative.** Costs if wrong: none — this replaced my suggestion with a
better one before anyone spent a milestone on it.

**Ruling 14 — my "env-gated debug prints" framing was also wrong; the milestone 7
item is "slow paths visible to the inliner".** The reviewer surveyed all 35
`System.getenv` sites in `nqp/src/vm/jvm/runtime` and `nqp/nqp-truffle/src`:
every one except `GlobalContext.kt:287` is already a `val` or `static final`,
hence foldable. `noisyExceptions` is the lone mutable instance `var` — an
outlier, not a pattern — so the project's env-gating rule is NOT the culprit and
must not be softened. Decisive counter-example: chain B, the larger per-root
cost at 204 roots, has no env gate at all; it is JDK exception construction. The
two real patterns, both milestone 7 surveys: (1) `nqp/src/vm/jvm/runtime`
contains **zero** `@TruffleBoundary` against 113 in `nqp/nqp-truffle/src`, so
that whole older tree is called from Truffle nodes with every slow path visible
to the inliner, and chain A is merely the first one measured; (2) six inline
`System.getenv()` calls on runtime paths (`Ops.kt:6834`, `Ops.kt:9026`,
`UnitWriter.kt:33`, `NqpPolyglot.kt:54`, `NqpCodeEngine.java:93`), worse in kind
because a `getenv` in a compiled graph cannot fold at all. Plan Task 11's
findings-doc requirements now carry all three corrections. Costs if wrong: a
milestone 7 survey scoped slightly wide, which is the safe direction.

Task 3: minor (deferred): the findings doc renders `ExceptionHandling.kt:46`
(the `if (tc.gc.noisyExceptions)` guard) and `:47` (the `printStackTrace()` call)
as one line; the line cited is the call, not the guard.
Task 3: minor (deferred): the report cites Task 1's CORE.c wall as 457 s where
the markers file gives 460 s.

Task 3: complete (commits `3db3362101`..`0c0521a538`, review clean after one fix
round; plus controller commit `28f06cac14` reframing Task 4).

Task 4: implementer dispatched (opus); BASE rakudo `f72f4be91e`. Threshold 2069
(2070 - 1, exclusive). Dispatched WITH ruling 11's reframing in the brief, and
instructed to judge on four quantities against Task 3's baseline rather than wall
clock alone, and to treat a large fall in compiler work at a flat wall clock as a
real result rather than a failed measurement.

### Task 4 configuration row: `NQP_CODE_MAX_COMPILE=2069`

Threshold arithmetic: Task 3 gave `min-too-large-size=2070`;
`NqpRootNode.prepareForCompilation` answers `programSize <= MAX_COMPILE_SIZE`
(inclusive, `NqpRootNode.java:119-123`), so 2070 would still admit
`IMPL-FOLD-CONSTANT[2070]`. The exclusive threshold is **2070 - 1 = 2069**.

Step 1's two checks, from re-summarizing the Task 3 baseline log: the `by size:`
list is `IMPL-FOLD-CONSTANT[2070], IMPL-OPTIMIZE-EXPRESSION[4030]` — a factor of
1.9 apart, same order of magnitude, so the minimum is plausible against its
neighbour and does not refuse nearly everything. The `unclassified failure
reasons` block holds exactly one reason, `PermanentBailoutException: Too deep
inlining, probably caused by recursive inlining` — an inlining-depth bailout, not
a size bailout, correctly excluded. No evidence of a third size spelling.

Step 2 probe: `NqpCheck` under the knob printed `nqp-code check passed`.

| quantity | baseline (Task 3) | knob=2069 | delta |
|---|---|---|---|
| wall clock | 434 s | **419 s** | **-15 s (-3.5 %)** |
| `total-compiler-ms` | 2 143 944 | **1 898 458** | **-245 486 (-11.5 %)** |
| `done` | 5 656 | **5 670** | **+14 (+0.2 %)** |
| `failed` | 444 | **407** | **-37 (-8.3 %)** |
| `nqp-root-ms` | 1 937 603 | 1 699 179 | -12.3 % |
| Stage parse | 333.841 | **318.561** | -15.3 s |
| `unparsed` | 0 | 0 | — |

The two "too large" failures **vanished**: `min-too-large-size=none`, and the
`code is too large` reason is absent from the run's `failures by reason` block
entirely. The `-1` was load-bearing exactly as ruling 11's brief predicted.

**The gate is airtight but `done` did not fall, and that is the finding.**
Counting `opt done` lines by root size directly off the trace: baseline compiled
**178** roots above 2069 successfully, the knob run **0**. But it compiled **198
more** roots at or below 2069 (5 175 -> 5 373), so the total rose. The compiler
did not go idle; it spent the freed capacity on the roots queued behind the large
ones. Arithmetic checks out: baseline spent 308 797 ms on those 178 compiles plus
~6.9 s on the two too-large failures, ~316 s removed against a 245 s net fall, the
~70 s difference re-spent on the extra small roots.

The whole wall-clock gain sits in Stage parse (-15.3 s); every other stage is flat
to within a second. This is therefore **not** the "large compiler-work fall at a
flat wall clock" case the brief anticipated: work fell 11.5 % and the wall
followed at 3.5 %, a real but heavily damped transfer. Task 7's thread-count knob
is **not** demoted — there is genuine compiler-thread contention here — but its
ceiling looks low: an eighth of the compiler work bought a twenty-ninth of the
wall.

Ruling 11's reframing is confirmed on its own terms. The knob is no longer a
free-reclamation lever (the too-large cluster it was written for is worth 6.9 s,
not 733 s); what it now buys is contention relief, and it buys it by refusing 178
compilations that would otherwise have succeeded.

**Verdict: KEEP**, on the wall clock (419 s vs 434 s), per Step 4's rule. Later
sweep configurations carry `NQP_CODE_MAX_COMPILE=2069`.

**Both clocks — build-side adoption only.** A root that is never compiled never
speeds up at run time either, and runtime performance outranks compile time.
Nothing measured here argues for this knob in Rakudo's own runtime; Task 11
decides the runtime side separately, and ruling 11 already took runtime adoption
off the table.

Task 4 concerns (implementer, for review): (1) one sample per configuration, and
3.5 % is small — the mechanism evidence (whole delta in Stage parse, 178->0 compile
count) is what carries it, not the wall clock alone; `total-compiler-ms` is far
outside any plausible noise band and is wall-clock-independent. (2) the knob
reallocates compiler capacity rather than subtracting it — a later task reasoning
about it as pure subtraction will be wrong. (3) 2069 is tuned to this run's
failure minimum and has no principled meaning; an encoder change that shifts wire
sizes moves it. Artifacts under `$CLAUDE_JOB_DIR/tmp/m6-corec-maxcompile.{log,markers,jar}`;
`blib` untouched. Full report: `.superpowers/sdd/2026-09-12-jvm-milestone-6-compiler-workload/task-4-report.md`.

Task 4: implementer DONE — rakudo `bf4f76ab18` (ledger only). Threshold 2069.
Wall 419 s (baseline 434), total-compiler-ms 1898458 (2143944, -11.5 %), done 5670
(5656), failed 407 (444), too-large failures gone. Verdict KEEP, build-side only.
Task 4: review (opus) — Spec ✅, quality Approved, 0 Critical, 2 Important,
3 Minor. Verdict CONFIRMED as KEEP, with the justification restated: the
-11.5 % compiler work carries it, not the 3.5 % clock. The reviewer reproduced
178 -> 0 and 5175 -> 5373 independently, confirmed the gate catches OSR roots
(6 -> 0), and ruled out all three alternatives I asked about: sizes cannot have
shifted (source and encoder byte-identical), unbracketed roots moved -7 not +198,
tier-up is not inflating either side (Tier1 4286->4277, Tier2 1372->1394). The
arithmetic reconciles exactly: 306833 ms + 1964 ms OSR = the report's 308797.
It also confirmed `min-too-large-size=none` is REAL and not a parse miss —
`reasons-parsed=4784`, the guard did not fire, `code is too large` is absent from
the log, and the unclassified size list tops out at 2042, below the threshold.

**Ruling 15 — the wall-clock gain is unproven at n=1, and the milestone must say
so rather than bank 3.5 %.** Forward-only gives one sample per configuration and
no repeats, so 15 s on 434 is inside plausible drift for a 16-core JIT-heavy
workload, and Tasks 1 and 3 supply no variance estimate because they are
different configurations. The verdict stands on the wall-clock-INDEPENDENT
quantities: `total-compiler-ms` -11.5 %, `nqp-root-ms` -12.3 %, and a
deterministic 178-to-0 on the gated population. The report's "the whole delta
sits in Stage parse" was demoted from evidence to observation: parse is 77 % of
the wall and where essentially all compilation happens, so any wall change lands
there a priori — near-tautological, and it was being presented as a second
independent line. Plan Task 11's findings doc now carries a standing caveats
block so every row inherits it. Costs if wrong: the milestone under-claims a real
gain, which is the safe direction for a measurement whose purpose is to rank
levers rather than to win an argument.

**Ruling 16 — the mechanism is NOT established, and the tidier story is the less
supported one.** The implementer explained the +198 extra small compiles as the
compiler spending freed capacity on a queue behind the large roots. The trace
cannot show that: there are no `opt queued` lines in it. And the evidence favours
a different mechanism — the extra compiles are almost all REPEATS (unique small
roots rose only 1756 -> 1768, twelve), per-root deltas are churn, and total
`Inlined Y` rose 2279 -> 2468, which is what you would see if callees previously
inlined INTO the 178 suppressed compiles now accumulate their own call counts and
compile separately. Both readings are now required in the report, with the
evidence that separates them and an explicit statement that this trace cannot
decide. The cleanest datum was missing entirely and is now required at the front
of the argument: `done` + `failed` is flat, 6100 -> 6078, so the knob
redistributed compile requests rather than removing them. Costs if wrong: a later
task reasoning from the queue story would over-predict what a capacity knob buys
— which is precisely Task 7.

**Ruling 17 — milestone 7's lever estimate stays at ~442, not 407.** The
deep-inlining cluster did not shrink. Among roots at or below 2069 it went
400 -> 405; the entire -37 is the above-2069 population, SUPPRESSED by the knob
rather than fixed, and it returns if the knob is dropped. Costs if wrong: an
estimate built on 407 would understate milestone 7's lead lever by 8 %.

Task 4: observation for later tasks, recorded not acted on — the knob run reports
deopt=3106 and inval=1271, and the gated population is only 29 unique roots with
`PERFORM-BEGIN[2085]` compiling 26 times and `encode_var[6418]` 18 times for 70 s.
A root compiling 26 times is deoptimisation churn; three thousand deoptimisations
during one compile is worth naming even though nothing in this milestone acts on
it.

Task 4 fix round 1: verdict unchanged (KEEP); no measurement re-run (forward-only),
six characterisations corrected from the logs already on disk. (1) The mechanism
claim "freed capacity on the queue behind the large roots" is withdrawn as
asserted: the log contains **zero `opt queued` lines**, so this trace cannot
measure enqueue at all. Both readings now stand side by side — freed capacity vs
inlining redistribution — and the evidence favours **redistribution**: the +198
extra small compiles are almost all repeats (unique roots compiled rose only
1753 -> 1765, +12; per-root deltas are churn) while summed `Inlined Y` rose
2279 -> 2468 (+189). (2) "The whole wall delta sits in Stage parse" is demoted from
evidence to observation — parse is 77 % of the wall and holds essentially all
compilation, so any wall change lands there a priori. The verdict now rests
explicitly on `total-compiler-ms` -11.5 %, `nqp-root-ms` -12.3 % and the
deterministic 178->0, all wall-clock-independent; the **3.5 % wall gain is stated
as unproven at n = 1** (Tasks 1 and 3 are different configurations and supply no
variance estimate). (3) Added the cleanest evidence, now leading the mechanism
argument: **`done` + `failed` is flat, 6100 -> 6077 (-23, -0.4 %)** — 184 compiles
refused, attempts barely moved, so the knob redistributed requests rather than
removing them.

**Correction that milestone 7 must carry: the deep-inlining cluster did NOT
shrink.** Among roots at or below 2069 it went 403 -> 408; the entire -37 is the
above-2069 population, which was *suppressed, not repaired*. Drop the knob and the
37 return. Milestone 7's lever estimate stays at **~442 latent bailouts, not 407**;
an estimate built on 407 understates it.

**Threshold sensitivity, for Task 11 to record.** 2069 is not merely unprincipled:
it sits **directly beneath `PERFORM-BEGIN[2085]`**, 26 compiles / 41 841 ms, the
second-largest single contributor to the saving. A threshold of 2100 hands that
root back and roughly a sixth of the saving with it. The suppressed population is
small and lumpy — 184 compiles across only **29 unique roots**, led by
`encode_var[6418]` 18x / 69 968 ms and `PERFORM-BEGIN[2085]` 26x / 41 841 ms — i.e.
recompilation churn sitting just above the cut, not a broad tail. The knob's value
is a function of where the cut falls relative to a handful of churning roots, so
an encoder change shifting wire sizes a few percent can move roots across it.

Observation for milestone 7, not acted on here: this run reports **deopt = 3106**
and **inval. = 1271**. A root compiling 26 times is invalidation-driven
recompilation; three thousand deoptimisations inside one CORE.c compile is worth
naming. Not investigated.

Small corrections: `Stage unit` **rose 1.46 s** (27.539 -> 28.999), so "every other
stage flat to within a second" was wrong and is withdrawn (optimize -0.54 s, qast
-0.31 s are flat). The "178" label excludes **6 OSR compiles** of
`encode_block[4626]<OSR@...>` while the 308 797 ms figure includes them:
306 833 + 1 964 = 308 797 exactly.

Task 4: fix round 1/5 (2 Important + 5 additions addressed, 1 partial — the
mechanism section now carries both readings with the discriminating evidence and
an explicit statement that the trace cannot decide; Stage parse demoted;
`done`+`failed` leads the argument; the ~442 correction, the threshold
sensitivity, the deopt observation and two small corrections all landed. Commit
rakudo `0ab21c6f36`.)
Task 4: re-review round 1 (opus) — IMPORTANT 1 ADDRESSED, IMPORTANT 2 PARTIAL
(the retracted Stage-parse argument survives as load-bearing in Concern 1), all
five additions ADDRESSED, ledger hunk +105/-0. On the three disputed counts the
re-reviewer took ground truth itself, treating the LAST bracket pair as the size
(three `done` lines per log carry an earlier literal bracket, e.g.
`postcircumfix:sym<[; ]>[249]`, which a first-bracket parse miscounts as >2069):
**the implementer was right on the bailouts (403 -> 408) and the FIRST review was
low by three; the implementer's parenthetical raw count 6102 -> 6079 is exact and
the first review's 6100 -> 6078 was wrong in both absolute and delta.** Deltas
agreed throughout, so no conclusion moved.

**Ruling 18 — the knob does not refuse 184 compiles, it converts them into
1.46 MILLION refused submissions, and that is an adoption caveat, not a
footnote.** The knob run's statistics block (log line 433549) reports
`Compilations : 1462534`, of which `RetryableBailoutException: Compilable not
ready for compilation` = **1456361**, against **144** in the baseline. That is
`prepareForCompilation` answering false and the compilation being re-submitted,
indefinitely. Three consequences, all now required in the report. (a) It argues
against the freed-capacity reading harder than anything the implementer had:
capacity is not freed, it is churned, because a refused root never leaves the
system. (b) The measured -11.5 % compiler work and -3.5 % wall are achieved
DESPITE 1.46 M wasted submissions, which is striking but fragile — that overhead
is workload-shaped and need not behave the same on BOOTSTRAP or another setting.
(c) It renders this run's `Compilations` and `Compilation Accuracy` fields
meaningless for comparison with any other configuration, so a later task diffing
those fields would be comparing nothing. The proper fix is named but NOT
implemented here: a size refusal should mark the root permanently non-compilable
rather than answering false on every submission. That is a runtime change, hence
milestone 7's. Costs if wrong: Task 11 adopts a knob whose win is real but whose
mechanism is uglier than the number suggests — which is exactly why the caveat is
recorded beside the adoption.

**Ruling 19 — the `Inlined Y` evidence was misattributed; the conclusion survives
on different grounds.** The totals (2279 -> 2468, +189) are right, but the split
is not: the suppressed roots contributed only 47 of 2279 inlined callees (their
184 compiles show 47 Y against 4423 N), while small-root inlining rose
2232 -> 2468, +236. So the rise is inlining GROWTH inside small roots, not
callees redistributing out of the suppressed ones — a population of 47 cannot
account for 198 extra compiles. Reading B still beats Reading A, now on the
unique-roots split (+12 roots against +198 compiles) and on the retry storm.
Costs if wrong: none; this replaces a wrong reason for a right conclusion.

Task 4 fix round 2: verdict unchanged (KEEP); no re-run. **A false statement in
round 1 is retracted, and what it hid changes what this knob is.** I wrote that
nothing in the trace measures queue behaviour. The engine's own statistics block
does. Knob run (log line 433549): `Compilations : 1462534`, of which
`RetryableBailoutException: Compilable not ready for compilation.` =
**1 456 361**. Baseline (line 469277): `Compilations : 6358`, the same bailout
**144**. **The knob does not refuse 184 compiles; it converts them into ~1.46
million refused submissions**, ~10 100x the baseline, because
`prepareForCompilation` answering `false` re-submits the root rather than
retiring it. Three consequences now in the report: (a) it argues against the
freed-capacity reading harder than any other evidence -- capacity is *churned*,
not freed; (b) it is a **Task 11 adoption caveat**, not a footnote: the
-11.5 % compiler work / -3.5 % wall is achieved *despite* 1.46 M wasted
submissions, which is fragile because that overhead is workload-shaped and need
not behave the same on BOOTSTRAP or another setting; (c) **the knob run's
`Compilations` and `Compilation Accuracy` statistics are meaningless for
cross-configuration comparison** (~230x baseline for reasons unrelated to
compiler work) -- a later task tabulating those fields per configuration would be
comparing nothing; use `Success`, `Permanent Bailouts` and `total-compiler-ms`.
Named but NOT implemented, and **belonging to milestone 7**: a size refusal ought
to mark the root permanently non-compilable instead of answering `false` on every
submission; that is a runtime compilation-policy change, and it would turn this
knob's measured win into a floor rather than a coincidence.

Task 4 fix round 2, second correction: the `Inlined Y` evidence was misattributed.
The totals were right (2279 -> 2468, +189) but the split is: the suppressed roots
contributed only **47** inlined callees across their 184 compiles (against **4423**
refused, `N`), while small-root inlining rose **2232 -> 2468 = +236**. So the rise
is inlining *growth inside small roots*, not callees redistributing out of the
suppressed ones -- and a donor population of 47 cannot account for ~197 extra
compiles. The conclusion (redistribution over freed capacity) survives and is now
carried by the retry storm and the distinct-root count instead.

Task 4 fix round 2, arithmetic corrections (none change a conclusion): baseline
failures above 2069 are **41 = 2 too-large + 39 deep-inline** (not 39 = 2 + 37),
so the failure delta reconciles exactly as -41 suppressed + 5 growth = **-36**;
`failed` is **444 -> 408** (-36, not -37) and reads 408 throughout; **milestone 7's
deep-inlining lever is 442 baseline / 447 forward**, not 408; `done` + `failed` is
**6102 -> 6079** and `done` is **5658 -> 5671**, taken from the engine's `Success`
and `Permanent Bailouts` counters which the raw line counts match exactly (the
summarizer reads two low on `done`, one low on `failed`, two low on `inval.`;
noted as a concern since the summarizer is closed to edits); `inval.` is
**1273**; the ≤2069 compile counts are **5474 -> 5671 (+197)**, the earlier
5175 -> 5373 having come from a parse that dropped ~300 unlabelled lines, and
-184 + 197 = +13 matches `Success` exactly. Two counts are convention-dependent
and are now reported as conventions rather than as single numbers: distinct roots
≤2069 is 1965 -> 1977 (+12) by `name[size]`, 2206 -> 2221 (+15) by `id=`, 1759 ->
1771 (+12) by the reviewer's parse -- all agreeing on +12-15, which is what the
argument uses; and the gated population is **29 distinct `id=` call targets / 28
distinct `name[size]` labels**, one of them (`encode_block[4626]`) appearing *only*
as OSR compiles, so the gate blocks OSR entry to large roots too. I could not
reproduce the reviewer's count of 30 under either convention and record that
rather than adopting a number I cannot derive.

Task 4 fix round 2, third correction: Concern 1 still rested on the Stage-parse
argument this report had already withdrawn as near-tautological. It now rests on
the same quantities the verdict does -- `total-compiler-ms` -11.5 %, `nqp-root-ms`
-12.3 %, and the 184 -> 0 predicate outcome -- with the 3.5 % wall gain restated as
unproven at n = 1.

Task 4: fix round 2/5 (2 Important + the arithmetic addressed, 0 open — the
retry storm written up with all three consequences and the false
"nothing measures queue behaviour" retracted; the `Inlined Y` evidence withdrawn
explicitly; Concern 1 rewritten off the retracted Stage-parse argument; every
figure corrected. Commit rakudo `013c6ab67c`.)
Task 4: re-review round 2 (opus) — all four ADDRESSED, every number re-derived
from the logs. Retry storm independently confirmed: knob run `Compilations`
1462534, `RetryableBailoutException: Compilable not ready for compilation`
1456361, `Temporary Bailouts` 1456454, Accuracy 0.999130; baseline 6358 / **144**
/ Accuracy 0.800566 — a 10113x ratio. Also reproduced exactly: 184 suppressed
compiles (6 OSR) at 47 Y / 4423 N, small-root 5474 -> 5671 (+197) with Y
2232 -> 2468 (+236), baseline failures >2069 = 41, and <=2069 bailouts 403 -> 408.

**Ruling 20 — I was wrong about the unique-root count and the implementer was
right to record the disagreement rather than adopt my number.** I passed along
"30 unique roots" from an earlier review. The re-reviewer parsed the 184 gated
compiles itself: **29 distinct `id=` call targets, 28 distinct `name[size]`
labels**, the collapsing pair being `PERFORM-BEGIN[3274]` and
`PERFORM-BEGIN[2085]`, which share a name but not an id. No convention yields 30.
It also settled the convention question: the engine's `id=` identity is primary,
because that is what the queue and the size predicate act on, while `name[size]`
merges distinct targets — which the 29-to-28 collapse proves. Costs if wrong:
none; the deltas were identical under every convention and no conclusion moved.

**Ruling 21 — the summarizer's undercount is real, understood, and deliberately
NOT fixed.** The implementer found the tool reads 2 low on `done`, 1 low on
`failed` and 2 low on `inval.` against the engine's counters, and declined to
edit a closed, reviewed artifact. The re-reviewer pinned the cause exactly:
`truffle-trace-summary.raku:79` requires `starts-with('[engine] opt ')`, so a
trace line Truffle wrote INTO a `Stage X :` line is binned as non-trace and
`unparsed` stays 0. Baseline has 3 such lines, the knob run 4, which reproduces
every discrepancy exactly. Declining to edit is correct: Tasks 1 and 3 were
summarized with this tool, and changing it mid-sweep would break comparability
for a 0.03 % error against deltas of +13 and -36. One nuance now carried into the
plan: it is NOT a constant bias (3 versus 4 lines), so no later task may correct
by a fixed offset — read the statistics block instead. Costs if wrong: nothing;
the error is two orders of magnitude below every delta being compared.

Task 4: complete (commits `f72f4be91e`..`013c6ab67c`, review clean after two fix
rounds; plus controller commits `6d68f22697`, `8240de93f5` and this one).
**Three conditions travel with the knob into Tasks 5-7**, per the re-review:
(1) `Compilations` and `Compilation Accuracy` are poisoned for every downstream
run inheriting `NQP_CODE_MAX_COMPILE` — compare `Success`, `Permanent Bailouts`
and `total-compiler-ms` only, and this is the one that will bite if forgotten
because those fields look authoritative; (2) the threshold is sensitive, 2069
sitting directly beneath `PERFORM-BEGIN[2085]` at 26 compiles and 41.8 s, so an
encoder change moves roots across it and no later task may read the knob as pure
subtraction; (3) milestone 7's deep-inlining lever is 442 baseline / 447 forward,
not 408 — the cluster was hidden, not fixed.

Task 5: implementer dispatched (opus); BASE rakudo `369eca5481`.
`engine.PartialBlockCompilation=true` with `NQP_CODE_MAX_COMPILE` NOT set -- it is
the ALTERNATIVE to Task 4's knob, not a companion. Judged against BOTH baselines
(Task 3 no-knob, Task 4 incumbent); it replaces Task 4 only if it beats it.
Briefed with all four lessons from Tasks 3-4: poisoned statistics fields, no noise
floor, the summarizer undercount, and no queue stories.

Task 5: complete. Verdict **DROP** -- `engine.PartialBlockCompilation=true` is
**inert for this workload**, not merely unhelpful. Wall 433 s (T3 434, T4 419),
`total-compiler-ms` 2129872 (T3 2143944, T4 1898458), `nqp-root-ms` 1921970
(T3 1937603, T4 1699179), `Success` 5617 (T3 5658, T4 5671), `Permanent
Bailouts` 448 (T3 444, T4 408). Against the incumbent it does +231414 ms
(+12.2 %) more compiler work with 54 fewer successes and 40 more bailouts, so
Task 4's `NQP_CODE_MAX_COMPILE=2069` carries forward alone. `min-too-large-size`
is still **2070**, the SAME two roots (`IMPL-FOLD-CONSTANT[2070]`,
`IMPL-OPTIMIZE-EXPRESSION[4030]`) failing at the same cost -- the knob's one
advertised effect did not occur. Failures by reason: 446 deep-inlining + 2
too-large; no new reason, and the deep-inlining cluster is 442 -> 446, so
milestone 7's lever is unchanged at ~442-447.
**Mechanism (structural, checked in-tree, not a queue story):** partial block
compilation is implemented solely in `com.oracle.truffle.runtime.OptimizedBlockNode`,
which exists only where a language builds `com.oracle.truffle.api.nodes.BlockNode`;
`grep -rn BlockNode nqp/nqp-truffle/src/ nqp/src/vm/jvm/runtime/` returns ZERO
hits, and `NqpRootNode` is a `@GenerateBytecode ... BytecodeRootNode` whose body
is an interpreted bytecode loop with no statement-node sequence to wrap. **Screen
every remaining knob for this before spending a compile: anything gated on
BlockNode, AST node counts or tree shape cannot apply to a Bytecode DSL language.**
**Two process findings for the controller.** (1) The Step 1 `NqpCheck` probe is
structurally unable to gate EXPERIMENTAL options: `NqpCheck.java:31` builds a
context WITHOUT `allowExperimentalOptions(true)` while `NqpPolyglot.kt:49-51` --
the context the compiler actually runs in -- has it, so the probe rejected the
option as experimental and would false-BLOCK every future experimental knob.
The implementer overrode the stop instruction after verifying acceptance on the
real engine path in ~20 s (`nqp-j-gradle -e` printed `engine-ok` plus a full
statistics block); the controller should confirm that call rather than let it
become precedent, and the durable fix is one line in `NqpCheck.java`, not made
here (measurement-only task). (2) Task 11 has nothing to combine -- only one knob
beat the baseline, and the combination it was reserved for is the configuration
ruled out here; re-aim it or drop it.
Also: the summarizer undercount took a THIRD distinct value (done -2, failed 0,
against 2/0 and 1/1), and `TraceCompilation` destroyed the numbers on four of
eight `Stage` lines, so per-stage attribution after `parse` is marker-derived
only. Report: `.superpowers/sdd/2026-09-12-jvm-milestone-6-compiler-workload/task-5-report.md`.
