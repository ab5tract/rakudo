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

Task 5: implementer DONE_WITH_CONCERNS, verdict DROP — rakudo `a59bc7a70a`
(ledger only). Wall 433 s, total-compiler-ms 2129872, nqp-root-ms 1921970,
Success 5617, Permanent Bailouts 448, min-too-large-size unchanged at 2070.
It OVERRODE the brief's BLOCKED-on-missing-marker instruction and said so in the
report header, the ledger and section 1.
Task 5: review (opus) — Spec ✅ with a declared override, quality Approved, DROP
stands, **1 Critical (a new finding, not a defect)**.

**Ruling 22 — the override was correct and the probe was the thing at fault.**
`NqpCheck.java:31` builds `Context.newBuilder(NqpLanguage.ID).build()` with no
`allowExperimentalOptions(true)`, while `NqpPolyglot.kt:49-51` — the context the
compiler actually uses — enables them. Verified by the controller directly. So
the probe false-rejects any experimental option, and `engine.Mode`,
`engine.MultiTier`, both tier thresholds and `engine.CompilerThreads` are all
experimental: Tasks 6 and 7 would each have reported BLOCKED on a working
option. The implementer verified acceptance on the real engine path in ~20 s and
disclosed the override in three places rather than burying it, which is exactly
the discipline this loop wants. All four probe sites in the plan now say a
missing marker means the probe cannot judge, not that the option is bad, and
carry the 20-second real-path verification plus a warning that ACCEPTED is not
the same as IN FORCE. Costs if wrong: none — the real-path check is strictly
better evidence than the probe it replaces.

**Ruling 23 — the one-line `NqpCheck` fix is NOT made during the sweep.** Adding
`allowExperimentalOptions(true)` to `NqpCheck.java:31` is obviously right and
obviously cheap, and I am deliberately not doing it. `NqpCheck` lives in
`nqp-truffle/src`, so the fix rebuilds `nqp-truffle.jar` and changes the runtime
under Tasks 6 and 7. Comparability across the sweep outranks a harness
convenience. Recorded as a post-sweep item. Costs if wrong: the probe stays
useless for two more tasks, which the plan already routes around.

**Ruling 24 — Task 5 was a REPLICATE, not an experiment, and that is the most
valuable thing it produced.** The reviewer read `OptimizedRuntimeOptions.<clinit>`
out of `truffle-runtime-25.2.4.jar`: it pushes `iconst_1` into the
`PartialBlockCompilation` `OptionKey`, and the descriptor reads "Enable partial
compilation for BlockNode (default: true)". That flag was the ONLY difference
between the Task 3 and Task 5 command lines, so **Task 5 is byte-equivalent to
Task 3**. Three consequences. (a) The milestone now has a measured NOISE FLOOR at
n=2, which forward-only had otherwise denied us entirely: wall 0.2 %,
`total-compiler-ms` 0.7 %, `Success` 0.7 % (41 compiles), `Permanent Bailouts`
0.9 % (4). (b) Task 5's fall in `Success` is noise, fully explained, with nothing
to attribute. (c) It retroactively strengthens Task 4: its -11.4 % on
`total-compiler-ms` is an order of magnitude outside the floor, so what ruling 15
recorded as "unproven at n=1" now stands clear of measured variance. The plan's
"there is no noise floor" caveat was FALSE and has been replaced with the
measured figures. Costs if wrong: it is one pair, so it is an order-of-magnitude
guide rather than a confidence interval, and the plan says so.

**Ruling 25 — DROP is right, but the reason had to change.** The implementer
justified DROP on +12.2 % `total-compiler-ms` against Task 4. That is
arithmetically correct and says nothing about the knob: since Task 5 IS Task 3,
it is Task 3-versus-Task 4 restated. The load-bearing reasons are that the option
defaults to true, hence was already in force in every earlier run, and that the
mechanism it controls does not exist on our path — `OptimizedBlockNode` only,
zero `BlockNode` hits across `nqp/nqp-truffle/src` and
`nqp/src/vm/jvm/runtime` (word-boundary grep, to rule out `RootNode` masking),
and `NqpRootNode.java:47-53` being a `@GenerateBytecode` `BytecodeRootNode`.
Costs if wrong: a later reader would otherwise believe partial-block compilation
was tried and cost 12 %.

Task 5: screening rules added to the plan for Tasks 6 and 7 — (1) does the
mechanism exist in this language, and (2) is the value already the DEFAULT. The
second is one `javap` on `OptimizedRuntimeOptions` and would have killed this
knob on its own, without spending 433 s.
Task 5: minor (deferred): the report's failure counts come from the summarizer
(446 + 2) while raw trace greps give 452 + 3 (retry lines) and the statistics
block gives 448 permanent. Three channels now disagree slightly; a future brief
must say which channel a count comes from.
Task 5: minor (deferred): `TraceCompilation` destroys four of eight `Stage` lines
in every run including Task 3's baseline, so it is a standing harness property
rather than a Task 5 regression. `Stage parse` survives in all runs and is the
only cross-run stage comparison anyone should make.
Task 5: Task 11's "if both help, combine" step now has nothing to combine; it
must be re-aimed or dropped when Task 11 runs.

Task 5 fix round 1: **the run was not a new configuration at all.**
`engine.PartialBlockCompilation` **DEFAULTS TO TRUE** -- verified independently
by the implementer out of the same jar the compile loaded: `OptimizedRuntimeOptions.<clinit>`
does `494: iconst_1 -> Boolean.valueOf -> 501: putstatic PartialBlockCompilation`,
and the generated descriptor reads "Enable partial compilation for BlockNode
(default: true)."; both logs' own `Picked up JDK_JAVA_OPTIONS` lines confirm the
flag was the ONLY difference between the T3 and T5 command lines. **Task 5 is
therefore a byte-equivalent REPLICATE of Task 3**, and its real product is the
milestone's **FIRST MEASURED NOISE FLOOR, at n=2: wall 0.2 %, total-compiler-ms
0.7 %, Success 0.7 % (41 compiles), Permanent Bailouts 0.9 % (4)** (exactly
0.230 / 0.656 / 0.725 / 0.901 %; nqp-root-ms 0.807 %, Compilations 0.6 %).
**Working rule for every later task and the findings doc: under ~1 % on these
counters is not a result at n=1** -- one replicate is a weak variance estimate,
but it is the only empirical one the milestone has.
Three consequences. (1) The Success fall of 41 is NOISE; the hedged mechanism
guess was deleted, there is nothing to explain. (2) **Task 4 is retroactively
strengthened**: its -11.45 % on total-compiler-ms is **17.4x the 0.66 % floor**
(nqp-root-ms -12.3 %, failed -8.1 % comparable; wall -3.5 % is ~15x the wall
floor), so what it booked as "unproven at n=1" now stands well outside measured
variance. (3) The DROP verdict is unchanged but **re-argued**: "+12.2 % vs Task 4"
is demoted from evidence to restatement (Task 5 IS Task 3, so it is T3-vs-T4 said
again); the load-bearing reasons are that the option was already in force
everywhere, and that its mechanism (OptimizedBlockNode / zero BlockNode hits /
NqpRootNode being a @GenerateBytecode BytecodeRootNode) does not exist on our path.
**TWO pre-compile screens now required on every remaining knob, cheapest first:
Screen A -- is the value already the DEFAULT? (one `javap -p -c` on
OptimizedRuntimeOptions.class, ~30 s; would have saved this entire 433 s compile).
Screen B -- does the mechanism EXIST on our path? (~2 min).**
Channel correction for failure counts: summarizer 446+2, raw `grep -c` 452+3,
engine statistics block 448 permanent bailouts. The gap is **NOT retry lines** --
it is the statistics block's per-reason breakdown subsections repeating each
reason string (6 for deep-inlining, 1 for too-large; the T3 log shows the same
6 and 1). 446+6=452, 2+1=3, 446+2=448: all three channels reconcile exactly.
Rule: anchor greps to `opt failed` or quote the statistics block, never a bare
`grep -c`. No re-run was made; all figures come from the existing logs.
Recorded as deliberately NOT fixed: `allowExperimentalOptions(true)` on
NqpCheck.java lives in nqp-truffle/src, so it would rebuild nqp-truffle.jar and
change the runtime under the remaining sweep compiles -- comparability outranks
harness convenience; it waits until after the sweep, Tasks 6-7 route around the probe.

Task 5: fix round 1/5 (4 items addressed, 0 open — the replicate finding is the
report's headline, the noise floor has its own section, the Success fall is
retired as noise, Task 4 is retroactively strengthened, DROP now leads with the
load-bearing reasons and demotes +12.2 % to "restatement, not evidence", the
default-value screen is added, and every count is sourced to its channel. Commit
rakudo `3561039d55`.) The implementer verified default-true ITSELF by `javap` on
`OptimizedRuntimeOptions` rather than taking it from the controller.
Task 5: re-review round 1 (opus) — all four ADDRESSED. Noise floor independently
recomputed by an awk pass over the `[engine] opt` lines rather than from the
summarizer: wall 0.230 %, total-compiler-ms 0.656 %, Success 0.725 %, Permanent
Bailouts 0.901 %, plus nqp-root-ms 0.807 % and Compilations 0.598 % — the
reported 0.2/0.7/0.7/0.9 confirmed exactly. Default-true independently confirmed
in the same jar the compile loaded (`<clinit>` offsets 490-501, `iconst_1` into
the `OptionKey`; the generated descriptors carrying "(default: true)"). Ledger
append-only, 115 insertions / 0 deletions.

**Ruling 26 — I was wrong about the channel discrepancy and the implementer was
right.** I told it the raw-grep excess over the summarizer's failure counts was
retry lines. It is not: the excess is the statistics block's own per-reason
breakdown repeating each reason string. The re-reviewer located every line —
six deep-inlining at 473383, 474437, 475457, 476478, 477533, 478555 and one
too-large at 476477, all AFTER the statistics block opens at 473375, one of them
reading literally `code is too large: 2` — and confirmed the identical structure
in the Task 3 log. So 446+6 = 452, 2+1 = 3, and 446+2 = 448 = Permanent Bailouts:
all three channels reconcile exactly rather than approximately. Costs if wrong:
none; this replaced a guess with a located, verified structure.

**Ruling 27 — the floor establishes the compiler-work gain and does NOT establish
the wall-clock gain; the findings doc will under-claim accordingly.** Arithmetic
confirmed from Task 4's own log: total-compiler-ms -11.45 % = **17.45x** the
0.656 % floor, nqp-root-ms -12.31 % = 15.3x, wall -3.46 % = 15.0x. But a single
pair yields one difference and ZERO degrees of freedom: it bounds nothing, and
two draws are on average closer together than the true spread, so it likely
UNDERSTATES noise. 17x survives a several-fold underestimate, so "Task 4's
compiler-work gain is not drift" is safe to state flatly. The wall figure is
weaker than its 15x suggests, for two reasons the reviewer named: the wall floor
is a single one-second difference at the measurement's own whole-second quantum,
making 0.2 % a RESOLUTION LIMIT rather than a variance estimate; and Task 4's
configuration churns the compile queue with its own retry storm, so the baseline
pair's spread is not guaranteed transferable to it. Task 11 will therefore state
the compiler-work gains as established and the -3.5 % wall as consistent and
directionally supported but not independently established, with the floor's
limitations in one sentence. This supersedes the unqualified half of ruling 24(c).
Costs if wrong: the milestone under-claims a real wall-clock win, which is the
direction I chose deliberately.

Task 5: controller slip, recorded — the re-review range I scoped ended at
`3561039d55` while HEAD was already `0117bdbc34`, because I committed the plan
edit after generating the package. The reviewer read the extra commit anyway and
found it legitimate (plan-only, 37/5, the five deletions being exactly the
now-false "there is no noise floor" caveat). Generate the package AFTER all
commits for the round, not before.
Task 5: the reviewer's second note is FIXED, not deferred — Tasks 6 and 7 carried
`-Dpolyglot.engine.PartialBlockCompilation=true` literally in their example
command lines, which is the precise habit the new default-value screen warns
against. Removed from both, with a note saying why it is absent.

Task 6: implementer dispatched (opus); BASE rakudo `04ed5e38da`. Tier policy as
four options. Dispatched with BOTH screens mandatory before any compile, the
probe-false-rejection routing, the noise floor with its limits, and the four
lessons from Tasks 3-5 (poisoned fields, the Stage-parse tautology, the
summarizer undercount, the three disagreeing count channels). Instructed that if
all four options prove to be defaults, report the finding and do NOT compile.

**Ruling 28 — USER DECISION 2026-09-12: the sweep stops being greedy-sequential.
Tasks 6 and 7 do NOT carry Task 4's knob.** The user asked whether we were still
spinning millions of refuse-and-retry submissions. We were, and Task 6's compile
was doing it as the question was asked. The waste was known (ruling 18); what had
not been named is that it is CONFOUNDING. Tier policy works by raising the call
counts at which a target submits for compilation, which directly changes how
often a size-refused root resubmits — so measured on top of Task 4's knob, part
of any tier-policy result would be "the retry storm shrank", a property of the
carried knob rather than of tier policy. Tasks 6 and 7 would have measured tier
policy on a system already thrashing at roughly one useful compilation per 258
submissions.

Decision taken: Task 4's knob is adopted on its own merits (Task 11 still takes
it, build-side only) and is NOT carried forward. Tasks 6 and 7 are measured
against Task 3's clean baseline and answer "what does tier policy do to a clean
compile". The permanent-refusal fix becomes milestone 7's first item beside the
inlining lever, both being small runtime changes in the same area. Recorded in
the plan at the carried-forward block, both task command lines, and the findings
doc's milestone 7 section. Costs if wrong: the milestone never measures the
combination of the two knobs, which Task 11 would otherwise have shipped
together — mitigated below.

Task 6: the in-flight run is KEPT as the combination data point rather than
killed. It was already mid-compile when the decision landed, so stopping it
would have produced nothing and discarded the only measurement of "tier policy
ON TOP OF the size knob" — the configuration Task 11 would have shipped under
the old design. It is recorded as confounded and NOT used to judge tier policy.
A clean Task 6, without `NQP_CODE_MAX_COMPILE`, is dispatched after it. Costs if
wrong: one extra ~7-minute compile, against a data point that cannot be
recovered later without another.

### Task 6 configuration row: tier policy (CONFOUNDED — carries `NQP_CODE_MAX_COMPILE=2069`)

Per ruling 28 this run is the record of *tier policy ON TOP OF the size knob*,
not the milestone's tier-policy verdict. Its baseline is Task 4, which carries
the same knob. Full report:
`.superpowers/sdd/2026-09-12-jvm-milestone-6-compiler-workload/task-6-report.md`.

**SCREEN A (defaults, ~2 min, no compile spent).** Read out of
`nqp/build/jvm/share/truffle/truffle-runtime-25.2.4.jar` in both places a
default is written: the `OptionKey` constructions in
`OptimizedRuntimeOptions.<clinit>` and the generated
`OptimizedRuntimeOptionsOptionDescriptors` prose.

| option | default | evidence | changed? |
|---|---|---|---|
| `engine.Mode` | `default` (`EngineModeEnum.DEFAULT`) | `getstatic EngineModeEnum.DEFAULT` -> `putstatic Mode` | YES -> `latency` |
| `engine.MultiTier` | **`true`** | `iconst_1` -> `putstatic MultiTier` | **NO — screened out, omitted from the command** |
| `engine.FirstTierCompilationThreshold` | `400` | `sipush 400` | YES -> `1600` (4x) |
| `engine.LastTierCompilationThreshold` | `10000` | `sipush 10000` | YES -> `40000` (4x) |

`engine.MultiTier=true` was dropped for the same reason ruling 27 dropped
`PartialBlockCompilation` from the briefs: setting a value the option already
holds sets nothing. It is inert twice over — `EngineData.<init>` computes
`multiTier = !compileImmediately && MultiTier`, and `compileImmediately` is
false. **The measured configuration is therefore THREE options, not four**, and
the row does not reproduce as written if `MultiTier` is added back.

**SCREEN B (structural): PASSES.** Unlike Task 5's option, tier policy is not
node-class-specific. All three options are read in
`com.oracle.truffle.runtime.EngineData.<init>` into fields consumed by
`com.oracle.truffle.runtime.OptimizedCallTarget` — the one call-target class
every guest root gets on the optimizing runtime, Bytecode DSL or AST.
`EngineData` computes `firstTierOnly = (Mode == LATENCY)` and
`callAndLoopThresholdInInterpreter = FirstTierCompilationThreshold`;
`OptimizedCallTarget` reads both. `NqpRootNode` is a `@GenerateBytecode`
`BytecodeRootNode` and gets an `OptimizedCallTarget` like anything else.

Screen B also found a **side effect not in the knob's name**: `EngineData`
computes `splitting = Splitting && (Mode != LATENCY)`, so `Mode=latency` **also
switches Truffle splitting off**. The measurement cannot separate that from the
tier effect.

**Probe: false-rejected as ruling 26 predicted. NOT BLOCKED.** `NqpCheck` never
printed `nqp-code check passed`; it threw `Option
'engine.FirstTierCompilationThreshold' is experimental and must be enabled with
allowExperimentalOptions(boolean)` at `NqpCheck.java:31`, while
`NqpPolyglot.kt:49-51` — the real compiler context — sets
`allowExperimentalOptions(true)`.

**Real-path verification: accepted AND in force**, three ways.
`./nqp/nqp-j-gradle -e 'say("engine-ok")'` with the three options printed
`engine-ok`. Negative controls prove the values are parsed rather than ignored:
`Mode=bogus` -> `Mode can be: 'default', 'latency' or 'throughput'.`;
`FirstTierCompilationThreshold=notanint` -> `For input string: "notanint"`. And
`Mode=latency` is visible in the run's own trace: `opt done ... Tier 2` lines go
**1394 -> 0** (the one `Tier 2` string left in the log is the statistics block's
histogram label), while tier-1 successes fall 4277 -> 3203, which is the raised
first-tier bar showing as the residual.

`LastTierCompilationThreshold=40000` is accepted and parsed but **structurally
inert under `latency`**: with `firstTierOnly` the target never promotes, so
`callAndLoopThresholdInFirstTier` is never the gate; its one surviving use is
`traversingFirstTierBonus = TraversingQueueFirstTierBonus * LastTier / FirstTier`,
and multiplying both thresholds by 4 leaves that ratio at its default. Task 11
and the clean Task 6 should drop it rather than carry cargo.

Exact command run (driver script kept at `$CLAUDE_JOB_DIR/tmp/run-task6.sh`):

```bash
NQP_CODE_MAX_COMPILE=2069 \
JDK_JAVA_OPTIONS='-Dpolyglot.engine.TraceCompilation=true -Dpolyglot.engine.CompilationStatistics=true -Dpolyglot.engine.Mode=latency -Dpolyglot.engine.FirstTierCompilationThreshold=1600 -Dpolyglot.engine.LastTierCompilationThreshold=40000' \
NQP_CODE_CLOSE_AT_EXIT=1 RAKUDO_RAKUAST=1 \
raku tools/build/watched-run.raku \
  --log=$CLAUDE_JOB_DIR/tmp/m6-corec-tier.log \
  --show-file=$CLAUDE_JOB_DIR/tmp/m6-corec-tier.markers \
  --show='Stage' \
  -- perl rakudo-j-build --setting=NULL.c --ll-exception --optimize=3 \
       --target=jar --stagestats \
       --output=$CLAUDE_JOB_DIR/tmp/m6-corec.jar gen/jvm/CORE.c.setting
```

| quantity | T3 (clean) | T4 (incumbent) | **T6 combination** | vs T4 | vs T3 | floor |
|---|---|---|---|---|---|---|
| wall clock | 434 s | 419 s | **329 s** | **-90 s (-21.5 %)** | -105 s (-24.2 %) | 0.2 % |
| `total-compiler-ms` | 2 143 944 | 1 898 458 | **644 314** | **-66.1 %** | -69.9 % | 0.7 % |
| `nqp-root-ms` | 1 937 603 | 1 699 179 | **590 650** | **-65.2 %** | -69.5 % | — |
| `Success` (stats block) | 5 658 | 5 671 | **3 203** | **-2 468 (-43.5 %)** | -43.4 % | 0.7 % |
| `Permanent Bailouts` (stats block) | 444 | 408 | **331** | **-77 (-18.9 %)** | -25.5 % | 0.9 % |

`unparsed=0`; `min-too-large-size=none` (the carried gate still holds). Count
channels, kept apart per ruling 25: statistics block `Permanent Bailouts` 331,
summarizer `failed=` 330, raw grep 336.

**Mechanism — a reduction in compilations, which is what the knob was supposed
to do.** Where Task 4 refused big roots and the compiler re-spent the freed
capacity on the queue behind them (`done` went UP), tier policy removes
compilations outright: 5671 -> 3203. Summing the `Time` field of Task 4's
tier-2 `opt done` lines gives **1 019 837 ms over 1394 compilations — 54 % of
its entire compiler work**, and this run spends zero there. The remaining
~234 000 ms is 1074 fewer tier-1 successes plus 72 fewer tier-1 failures.
Second-tier recompilation of roots a one-shot build runs a handful of times was
more than half of all compiler work.

**Not the Stage-parse tautology (lesson 2).** Every stage fell, by
marker-to-marker deltas: parse 320 -> 246 s (-74), optimize+qast 36 -> 31 (-5),
qast->unit 34 -> 25 (-9), unit->jar 29 -> 27 (-2).

**The deep-inlining cluster MOVED: 442-447 across Tasks 3/4/5 -> 330-331 here.**
Not fixed — there are simply 43 % fewer compilations in which to hit it.
`failures by reason` holds exactly one reason (deep inlining), no new reason
appeared, and the summarizer's unclassified block holds that same single reason
with sizes 43..2042 plus three `no-size` host roots. Milestone 7's inlining
lever should be re-stated as ~330 under tier policy.

**Ruling 28's premise, tested against this run — it runs the OTHER WAY.** Ruling
28 expected tier policy to shrink the retry storm and thereby inflate a result
measured on top of the size knob. It grew: `Compilations` 1 462 534 -> 2 080 000
(+42.2 %), `Compilable not ready for compilation` 1 456 361 -> 2 076 384
(+42.6 %), useful compilations per submission 1-in-258 -> 1-in-649. (Ruling 25
forbids comparing `Compilations` across runs *as a measure of compiler work*;
here it is not a proxy for anything, it IS the quantity ruling 28 is about.)
Mechanism: higher thresholds keep a root ineligible longer, and a size-refused
root resubmits for the whole of that longer window. Two consequences — the
confound's sign is against tier policy, so -90 s is a floor rather than an
inflated figure; and the clean Task 6, having no size refusals to resubmit,
should show a SMALLER `Compilations` figure than this run, not a larger one. If
it does not, something else drives resubmissions and ruling 28's model needs
revisiting. None of this reopens ruling 28: removing a confound whose sign you
cannot predict in advance is right either way, and a clean baseline is worth
having on its own.

**Verdict: KEEP for the combination.** It decides that tier policy is worth
-90 s and -66 % compiler work ON TOP OF the size knob — the configuration Task
11 would have shipped under the old design, now measured once and not needing a
re-run. It does NOT decide tier policy; the clean Task 6 does. Recorded
expectation, before that run exists so it can be wrong: the clean run should
show a LARGER absolute tier-policy gain than -90 s, because Task 4's knob has
already removed 178 of the largest compilations that tier policy would also have
removed — the two knobs overlap in what they suppress. Against Task 3's 434 s, a
clean tier policy landing near or below 329 s would confirm that.

**Build-side adoption only, and more sharply than Task 4.** `Mode=latency` pins
every root to tier 1 for the life of the process and switches splitting off.
That is right for a compiler that runs once and exits and is the opposite of
what Rakudo's runtime wants, where runtime performance outranks compile time by
standing user priority.

Task 6 concerns (implementer, for review): (1) three options moved at once — the
trace decomposes the effect (tier-2 abolition 1 019 837 ms, raised first-tier
bar ~234 000 ms) but isolating `Mode=latency` alone would be another compile;
(2) `Mode=latency` smuggles in splitting=off, so it is not purely tier policy
and a reviewer modelling it as such will be wrong; (3) `Success` falling 43 % is
eligibility, not suppression-by-size — nothing was refused
(`min-too-large-size=none`, one reason, no new reason); (4) `NQP_CODE_MAX_COMPILE=2069`
was tuned on a run whose largest compiles included tier-2 work that no
longer exists, so if it is ever recombined with tier policy the threshold should
be re-derived rather than assumed; (5) one sample, and the floor is still n=2
with a whole-second wall quantum — a formality at 100x, but stated; (6) the
commit stamp is 20:40:00 as briefed, which is four minutes BEFORE its parent
`64860c451a` (20:44:00) — the briefed value was fixed before ruling 28 landed,
and I kept it rather than silently substituting my own.

Task 6 (COMBINATION run): implementer DONE, verdict KEEP — rakudo `5aed763460`
(ledger only). Ruling 28 landed mid-compile, so this run still carries
`NQP_CODE_MAX_COMPILE=2069` and is the COMBINATION data point; the clean run
decides tier policy itself.
SCREEN A caught one: `engine.MultiTier` already defaults to **true**, so it was
omitted and the configuration is THREE options, not four — `engine.Mode=latency`,
`FirstTierCompilationThreshold` 400 -> 1600, `LastTierCompilationThreshold`
10000 -> 40000 (the last accepted but structurally inert under latency).
SCREEN B passes: all three live in `EngineData` -> `OptimizedCallTarget`, the
universal call-target class, unlike Task 5's node-class-specific option.
In force by three proofs, not merely accepted: negative controls reject
`Mode=bogus` and `notanint`; `opt done ... Tier 2` goes 1394 -> **0**; tier-1
successes 4277 -> 3203 as the raised-bar residual.

| quantity | T3 clean | T4 size knob | T6 combination |
|---|---|---|---|
| wall | 434 s | 419 s | **329 s** |
| total-compiler-ms | 2143944 | 1898458 | **644314** |
| nqp-root-ms | 1937603 | 1699179 | **590650** |
| Success | 5658 | 5671 | **3203** |
| Permanent Bailouts | 444 | 408 | **331** |

Mechanism: Task 4's tier-2 work was 1019837 ms over 1394 compiles, 54 % of its
compiler time, and is now ZERO. Every stage fell (parse -74 s, others -16 s), so
this is not the Stage-parse tautology. Deep-inlining cluster 442-447 -> 330-331.

**Ruling 29 — RULING 28'S REASONING WAS WRONG IN DIRECTION, though its decision
stands.** I argued that carrying Task 4's knob would INFLATE a tier-policy result,
because raising submission thresholds would shrink the retry storm. The opposite
happened: the storm GREW from 1.456 M to 2.076 M, +43 %. So the confound runs
backwards and the measured -90 s is a FLOOR, not an inflation — tier policy on a
clean system should look at least this good. The decision to measure cleanly
remains right for attribution, and the clean run is still worth its seven
minutes, but for a different reason than I gave: not to strip away an inflated
gain, but to find out whether the size knob still adds anything once tier-2 work
no longer exists. Costs if wrong: none; the correction makes the pending clean
run a marginal-value question rather than a correction.

**Ruling 30 — `Mode=latency` is BUILD-SIDE ONLY, and this is the single most
important sentence for Task 11.** Latency mode pins every root to tier 1 forever.
For a compile that runs each block a handful of times that is exactly right; for
Rakudo's own runtime it would cap every hot loop at first-tier code and cripple
the performance the user ranks ABOVE compile time. Task 11 must adopt it in
`j_truffle_opts` / `j_truffle_args` (build) and must NOT add it to
`create-jvm-runner.pl`'s `$jopts` (runtime). Costs if wrong: adopting it at
runtime would be the worst regression this milestone could ship, which is why it
is recorded as a ruling rather than a concern.

Task 6: concern carried to Task 11 — `Mode=latency` also switches SPLITTING off,
so the configuration is not purely tier policy and the three options moved
together. Isolating `Mode` alone would need another compile; not spent.
Task 6: concern carried to Task 11 — `NQP_CODE_MAX_COMPILE=2069` was derived on a
run containing tier-2 work that no longer exists under latency, so the threshold
may no longer mean anything; re-derive before ever recombining them.
Task 6: the implementer used the briefed stamp 20:40:00, four minutes BEFORE its
parent commit at 20:44:00, and flagged it rather than silently substituting a
different time. Correct call: a brief's literal value is followed and the
anomaly reported, not quietly "fixed".

Task 6: review (opus) — Spec ✅ (the `MultiTier` omission accepted as a correct,
argued deviation), quality Approved, KEEP stands, 0 Critical, 1 Important,
3 Minor. The reviewer re-parsed the log with its OWN script rather than the
summarizer and reproduced every figure exactly, then closed the mechanism
arithmetically: 1394 tier-2 compiles at 1019837 ms (53.7 % of Task 4's compiler
time) plus tier-1 done 857951 -> 626710 and tier-1 failed 20444 -> 17604 at
234147 ms sum to the full 1254144 ms drop. The effect is two orders of magnitude
outside the noise floor.

**Ruling 31 — the retry storm grew for a CONGESTION reason, not a threshold
reason; both the implementer's explanation and mine were wrong.** I predicted the
storm would shrink (ruling 28) and the implementer explained its growth as higher
thresholds keeping a root ineligible for longer. Both are wrong in the same
direction: a root ineligible longer submits LESS, and pure threshold-gating
predicts roughly 4x FEWER resubmissions, not the observed 1.4x more
(1456361 -> 2076384, +42.6 %). The fit that matches the data is the reviewer's:
`prepareForCompilation` returning false is a RETRYABLE bailout that does not mark
the target failed, so a refused root becomes re-submittable as soon as no task is
pending — resubmission is congestion-bound, not threshold-bound. Task 6's queue
carries 66 % less real work, so refused tasks turn around faster: 3476
resubmissions/s against 6311/s. It is a fit to observed rates, not something the
trace proves, since the trace records no enqueue events. Costs if wrong: the
mechanism is descriptive only; no decision in this milestone rests on it.

**Ruling 32 — the splitting worry is CLOSED by the runs' own data, not carried
to Task 11.** The implementer flagged that `Mode=latency` also disables splitting,
so the configuration is not purely tier policy. Both runs print `Splits : 0`:
splitting produced nothing on this workload even with splitting ENABLED, so the
side effect contributed exactly zero here. The reviewer also derived the
attribution split — roughly 81 % of the drop is `Mode=latency` abolishing tier 2,
roughly 19 % the raised first-tier bar, both genuinely tier policy — and
confirmed `LastTierCompilationThreshold` is inert for a verified reason:
`OptimizedCallTarget.compile(boolean, SubmissionReason)` has `firstTierOnly`
force the last-tier flag false, so that threshold is never the gate. Costs if
wrong: none; this closes an open question with evidence already in hand.

**Ruling 30 CONFIRMED from bytecode.** `EngineData.<init>` computes
`firstTierOnly = (Mode == LATENCY)` and `splitting = Splitting && (Mode !=
LATENCY)`, and `OptimizedCallTarget.compile` uses `firstTierOnly` to force every
submission to first tier, so no root reaches the top tier for the life of the
process — corroborated by 0 tier-2 compiles in 3203. Reviewer confidence: very
high. Task 11 must adopt `Mode=latency` build-side ONLY.

Task 6 fix round 1 (no re-run; everything below is from the two logs already on
disk). Verdict, headline and the §5 table unchanged.

**IMPORTANT 1 — my retry-storm mechanism was wrong and inverted; withdrawn.** I
wrote that higher thresholds keep a root ineligible longer so it resubmits for
the whole of that longer window. A root that is ineligible longer submits LESS;
pure threshold-gating predicts ~4x FEWER resubmissions (400 -> 1600), not the
1.43x more measured. Replacement: `prepareForCompilation` returning false is a
RETRYABLE bailout that does not set `compilationFailed`, so a refused target is
re-submittable as soon as no task is pending for it — resubmission is
CONGESTION-bound, not threshold-bound, and this run's queue carries 66 % less
real work so refused tasks turn around faster. Verified rates: Task 4
1 456 361 / 419 s = **3 475.8 resubmissions/s**; Task 6 2 076 384 / 329 s =
**6 311.2 resubmissions/s** (count 1.43x, rate 1.82x). **This is a fit to two
observed rates, NOT something the trace proves**: `TraceCompilation` records
done/failed/inval/deopt/reprof and no enqueue events at all, so the submission
period is never directly observed. Label it as a fit wherever it is reused.
**Prediction deleted:** I had predicted the clean Task 6 would show a smaller
`Compilations` figure. It cannot test anything — the clean run drops
`NQP_CODE_MAX_COMPILE`, so `prepareForCompilation` is always true, nothing is
refused, and there is no storm to count (Task 3 recorded 144). Struck, not
rephrased.

**Task 6 concern 2 CLOSED, not carried to Task 11.** The `Mode=latency`
splitting side effect contributed exactly zero here: BOTH statistics blocks
print `Splits : 0`. Task 4 had splitting ENABLED and split nothing, so switching
it off removed no work. The bytecode finding (`splitting = Splitting && (Mode !=
LATENCY)`) stays on the record for a workload where splitting fires; it is not a
caveat on this measurement.

**Attribution split, derived from the `Time` fields over the summarizer's own
line population.** Both column totals reproduce `total-compiler-ms` exactly and
the four drops sum exactly to the 1 254 144 ms fall:

| | Task 4 | Task 6 | drop |
|---|---|---|---|
| tier-2 `done` | 1 019 837 ms (1394) | 0 | 1 019 837 |
| tier-2 `failed` | 226 ms (5) | 0 | 226 |
| tier-1 `done` | 857 951 ms (4276) | 626 710 ms (3203) | 231 241 |
| tier-1 `failed` | 20 444 ms (402) | 17 604 ms (330) | 2 840 |
| **total** | **1 898 458** | **644 314** | **1 254 144** |

**`Mode=latency` abolishing tier 2 = 1 020 063 ms (81.3 %); the raised
first-tier bar = 234 081 ms (18.7 %).** Both halves are genuinely tier policy
and neither is an artifact of the carried size knob, which strengthens the KEEP.

**`LastTierCompilationThreshold` is inert for a CONFIRMED reason, not a
suspected one.** At the top of `OptimizedCallTarget.compile(boolean,
CompilationTask$SubmissionReason)`: `getfield EngineData.firstTierOnly` / `ifne`
-> `iconst_0` / `istore_3`, i.e. `lastTierCompilation := !firstTierOnly && arg`.
`firstTierOnly` forces the flag false on every entry whatever the caller asked,
so a last-tier compilation is never submitted and the threshold is never the
gate. Drop it from any carried set.

**MINOR — channel reconciliation corrected, and now exact.** 336 raw
`grep -c PermanentBailoutException` = **330** clean `^[engine] opt failed` lines
+ **1** `opt failed` line carrying a watched-run `Stage unit       : ` prefix
(log line 343573) + **5** repetitions inside the statistics block's own
per-reason breakdown (lines 349945, 350999, 352019, 353039, 354061). So the
331-vs-330 gap is that single Stage-prefixed line: the engine counts it
(`Permanent Bailouts : 331`), the summarizer's starts-with filter drops it
(`failed=330`) — lesson 3's undercount caught in the act. The same filter
reconciles the ms totals to the millisecond: Task 6's dropped `opt failed` is
31 ms (raw 644 345 - 31 = 644 314) and Task 4's are an `opt failed` at 28 ms
plus a `Stage start`-prefixed `opt done` at 59 ms (raw 1 898 545 - 87 =
1 898 458). No residual in either channel.

Task 6 (combination): re-review round 1 (opus) — APPROVED, all four items
ADDRESSED, no Critical, no new findings, ledger hunk 169/0. Rates confirmed
(3475.8/s vs 6311.2/s; count 1.4257x, rate 1.8158x). Attribution reproduced
independently by the reviewer's own awk: T4 tier-2 done 1019837 (1394) + tier-2
failed 226 (5) + tier-1 done 857951 (4276) + tier-1 failed 20444 (402) = 1898458;
T6 tier-1 done 626710 (3203) + tier-1 failed 17604 (330) = 644314; drops sum to
exactly 1254144, and both totals equal `total-compiler-ms`. The 1019837-vs-1020063
difference is NOT a discrepancy: the first review quoted tier-2 DONE only, the fix
adds tier-2 FAILED (226 ms, 0.018 % of the drop, no effect on 81.3/18.7).
Channels reconcile with named line numbers, and the millisecond channels too
(T6 644345-31, T4 1898545-87).
Reviewer's residual, recorded not fixed: the congestion model is DIRECTIONAL
ONLY — real work fell 2.95x while the refusal rate rose only 1.82x, so a strictly
proportional congestion model over-predicts; "a fit to two observed rates" is
compatible with that, a quantitative claim would not be. Weak corroboration it
noticed: `Compilation cancelled` 77 -> 71 and assumption-invalidated 15 -> 11 stay
flat while the storm grows 43 %, which is what congestion-bound predicts and
threshold-gating does not explain.

Task 6 (combination): complete (commits `64860c451a`..`b0ad6ef40c`, review clean
after one fix round).

**Ruling 33 — USER DECISION 2026-09-12: the size knob is NOT adopted in milestone
6, and its comparisons are postponed to milestone 7.** The user observed that the
size knob is itself the sole cause of the reject-but-retry storm, and therefore
that "does the size knob still add anything" cannot be answered while it remains
broken. That is right, and sharper than the plan I was about to execute: a clean
tier-policy run compared against the combination would have measured the knob's
marginal value IN ITS BROKEN FORM — informative only in one direction, since a
positive result would be a lower bound on the fixed version while a null or
negative result would say nothing about it at all.

Decision: keep the numbers clean. The clean Task 6 measures tier policy against
Task 3's clean baseline, full stop. No marginal-value comparison is drawn.
**Task 11 adopts tier policy (build-side only, ruling 30) and does NOT adopt
`NQP_CODE_MAX_COMPILE`**; the knob is recorded as measured-but-not-adopted with
its reasons. Milestone 7 makes the refusal permanent and re-evaluates it properly,
at which point the question becomes answerable.

Three reasons this is the right call beyond the measurement argument. (a) The
knob's own case has weakened: its -11.5 % came from suppressing large roots, and
large roots are overwhelmingly where tier-2 compilation happened — which tier
policy now abolishes entirely, so the work it reclaimed is already reclaimed. (b)
Its threshold of 2069 was derived from a cost profile (6.4 s mean, tier-2
inclusive) that no longer exists. (c) Adopting it would ship a build default that
fires ~2 M wasted submissions per compile. Tier policy alone is 81 % of the total
saving and carries no such defect.

Nothing measured so far is wasted: the permanent-refusal fix is
behaviour-preserving whenever the knob is UNSET (`MAX_COMPILE_SIZE` stays
`Integer.MAX_VALUE` and `prepareForCompilation` always returns true), so a future
fixed measurement remains comparable to today's clean baseline. Costs if wrong:
milestone 6 ships without a knob worth up to 11.5 % on compiler time — recoverable
in milestone 7, and preferable to shipping it in a form nobody can evaluate.

---

## Task 6 (CLEAN) — tier policy measured by itself. KEEP.

The configuration ruling 33 asks for, and the one milestone 6 adopts: three
polyglot options, **no `NQP_CODE_MAX_COMPILE`**, against Task 3's clean traced
baseline. Per ruling 33 no comparison is drawn against the combination run.

```
-Dpolyglot.engine.Mode=latency
-Dpolyglot.engine.FirstTierCompilationThreshold=1600
-Dpolyglot.engine.LastTierCompilationThreshold=40000
```

plus `TraceCompilation` and `CompilationStatistics`. `engine.MultiTier` omitted
(default-true, screened earlier). rakudo HEAD `b01f00ce02`; nqp `41c294b02`,
clean. No source changed in either tree. One compile, exit 0, 337 s.

**The knob was unset**, three ways: `env | grep -i nqp_code` empty before the
run; an explicit `unset NQP_CODE_MAX_COMPILE` in the driver script; and the
statistics block shows `RetryableBailoutException: Compilable not ready for
compilation.` = **44**, against 144 in Task 3. No storm. `Compilations` 3853 and
`Compilation Accuracy` 0.755775 are therefore comparable figures here, unlike in
any run carrying the knob.

**Real path accepted** (`nqp-j-gradle -e 'say("engine-ok")'` → `engine-ok`); the
`NqpCheck` probe false-rejected as predicted (experimental options, no
`allowExperimentalOptions` at `NqpCheck.java:31`) — not BLOCKED.

**IN FORCE**, against the clean T3 control rather than T4: `opt done ... |Tier 2|`
**1372 → 0**; tier-1 done 4286 → 3334 (-952), which is the raised first-tier bar
as residual. All 20 top roots by compile time are tier 1.

| quantity | T3 clean | **T6 clean** | delta | floor |
|---|---|---|---|---|
| wall | 434 s | **337 s** | **-97 s (-22.4 %)** | 0.2 % |
| `Stage start` | 0.001 | 0.001 | 0.000 | |
| `Stage parse` | 333.841 | **253.998** | -79.843 (-23.9 %) | |
| `Stage syntaxcheck` | 0.000 | 0.000 | 0.000 | |
| `Stage ast` | 0.001 | 0.000 | -0.001 | |
| `Stage optimize` | 36.584 | **32.017** | -4.567 (-12.5 %) | |
| `Stage qast` | 34.266 | **25.389** | -8.877 (-25.9 %) | |
| `Stage unit` | 27.539 | **23.476** | -4.063 (-14.8 %) | |
| `Stage jar` | 0.000 | 0.000 | 0.000 | |
| stage sum | 432.2 | **334.881** | -97.3 (-22.5 %) | |
| `total-compiler-ms` | 2 143 944 | **783 440** | **-1 360 504 (-63.5 %)** | 0.7 % |
| `nqp-root-ms` | 1 937 603 | **727 228** | -1 210 375 (-62.5 %) | |
| `Success` | 5 658 | **3 334** | -2 324 (-41.1 %) | 0.7 % |
| `Permanent Bailouts` | 444 | **372** | -72 (-16.2 %) | 0.9 % |
| `Compilation Utilization` | 5.224919 | 2.501061 | -52.1 % | |

`unparsed=0`, `reasons-parsed=5077`, `min-too-large-size=2070` with the same two
roots as T3 — evidence the two compiles are the same work. Three stage times
collided with trace lines on their output line (the known T3 `--stagestats`
artifact) and were read from the following log line; the baseline loses the same
lines identically.

Failure channels kept apart: statistics block `Permanent Bailouts` **372**;
summarizer `failed=` **371**; raw `grep -c PermanentBailoutException` **376**
(T3: 444 / 444 / 448). Same spread shape in both runs; moves nothing.

**KEEP**, on the wall clock: -97 s is ~112x the floor's wall component and
-63.5 % compiler time is ~91x its `total-compiler-ms` component. Every non-zero
stage moved in the same direction, which is what separates a real fall in
background compiler pressure from a parse-only artifact. Build-side only
(ruling 30): `Mode=latency` also disables splitting, a second mechanism riding
the same option; this run cannot separate the two, and neither belongs in a
long-lived Rakudo process.

Concerns: `LastTierCompilationThreshold` contributed nothing measurable and is
inert under latency (Task 11 already drops it); the splitting side effect is
unseparated; one compile per configuration; CORE.c only, so magnitude may differ
on BOOTSTRAP though the mechanism fixes the sign.

Task 6 (clean): complete. This supersedes the combination run as the milestone's
tier-policy verdict and confirms Task 11's adoption decision on clean numbers.

Task 6 (CLEAN — tier policy alone, the configuration that ships): implementer
DONE, verdict KEEP — rakudo `0c620fde62` (ledger only). `NQP_CODE_MAX_COMPILE`
unset, verified four ways. In force: tier-2 compiles **1372 -> 0** against Task 3's
own control (the implementer correctly used 1372, Task 3's figure, not the
combination run's 1394).

| quantity | T3 clean | **T6 clean (tier policy alone)** |
|---|---|---|
| wall | 434 s | **337 s (-22.4 %)** |
| Stage parse | 333.841 | 253.998 (-23.9 %) |
| Stage optimize | 36.584 | 32.017 (-12.5 %) |
| Stage qast | 34.266 | 25.389 (-25.9 %) |
| Stage unit | 27.539 | 23.476 (-14.8 %) |
| total-compiler-ms | 2143944 | **783440 (-63.5 %)** |
| nqp-root-ms | 1937603 | 727228 (-62.5 %) |
| Success | 5658 | 3334 |
| Permanent Bailouts | 444 | 372 |
| tier-2 compiles | 1372 | **0** |
| retryable "not ready" | 144 | 44 |

-97 s is ~112x the floor's wall component and -63.5 % is ~91x its
total-compiler-ms component. EVERY non-zero stage moved the same way, so this is
not the parse-only artifact.

Task 6 (clean): review (opus) — **KEEP stands, ship it.** Every number verified
independently, with an EXACT reconciliation rather than an approximation: summing
the trace's own time fields gives 783461 against the reported 783440, the 21 ms
gap being precisely the one `Stage unit`-prefixed `opt failed` line the
summarizer's anchor drops; the baseline reconciles identically (2144056 vs
2143944). Wall confirmed twice, from epoch stamps and the marker footer.

**Ruling 34 — the controller's pre-registered prediction was CONFIRMED at the
mechanism level, and the magnitude correction is recorded.** Before the run I
predicted that without the size knob the previously suppressed large roots would
compile at first tier, so Success and compiler time would both rise against the
combination run, and said that if they did not my account of the knob was wrong.
The reviewer checked the mechanism rather than the totals: diffing per-compile
root multisets, **149 compiles occur in the clean run that do not occur in the
combination run, 131 of them with root size >= 2069** — exactly the Success delta
(3334 - 3203 = 131) and exactly the population the knob refused.
`encode_var[6418]` is compiled **13 times here and 0 times in the combination
run**, taking 13 of the top-20 slots by compile time. The 139126 ms rise over 131
compiles is ~1062 ms each, coherent for roots of that size. My "roughly 184"
OVERSHOT: 131 were restored, same order and on the low side, because some refused
roots never re-reach the raised threshold. Costs if wrong: none; this is a
prediction that was registered before the measurement and then checked against
it, which is the strongest form of evidence this milestone has produced.

**Ruling 35 — the splitting confound is closed for the clean run too, by its own
data.** The implementer carried it as unresolved, saying this run cannot separate
`Mode=latency`'s tier effect from its splitting side effect. It can: `Splits : 0`
at line 398325 of its own log, at 475496 of the baseline, and in both earlier
combination logs. Splitting produced nothing on this workload even when ENABLED,
so disabling it cannot contribute to a 97-second fall. Ruling 32 already settled
this on the combination run. The -22.4 % is attributable to tier policy. Costs if
wrong: carrying it would have understated a result the log itself settles.

Task 6 (clean): the retry count FALLING (144 -> 44) is a fourth proof the knob was
absent, not an anomaly. "Not ready" fires when a submission races an
invalidation, and tier-2 PROMOTION submissions are its classic source; submissions
fell 39 % (6358 -> 3853) and tier-2 promotions fell to zero, which over-explains a
69 % drop.
Task 6 (clean): conditions travelling to Tasks 7 and 11 — (1) Task 11 MUST DROP
`LastTierCompilationThreshold=40000`, structurally inert under latency and present
here only for option-set parity; shipping it would be the exact
"writes a default and sets nothing" habit the screening rule forbids. (2)
Build-side only (ruling 30); Task 7 must not let it leak into a runtime default.
(3) Measured on CORE.c alone — the mechanism fixes the sign on BOOTSTRAP but not
the magnitude. (4) One compile per configuration, but at 112x and 91x the floor
with four independent corroborations, the floor's weakness is not load-bearing
here.

Task 6 (clean) fix round 1: verdict unchanged (KEEP, -22.4 % wall); no re-run.
Review reconciled `total-compiler-ms` independently — trace time fields sum to
783461 against 783440, the 21 ms gap being the single `Stage unit`-prefixed
`opt failed` line (`<anon>[27]`, log 382860) the summarizer's anchor drops; the
baseline reconciles identically. Using T3's own 1372 tier-2 count rather than the
combination run's 1394 was ruled correct.
**Concern 2 (the splitting confound) is STRUCK, not softened.** `Splits : 0` in
this run's statistics block (line 398325) AND in the T3 baseline's (line 475496),
verified directly: splitting produced nothing on this workload even when ENABLED,
so disabling it cannot contribute to a 97 s fall. Ruling 32 had already closed
this on the combination run. Attribution is now plain: **the -22.4 % wall and
-63.5 % compiler time are tier policy.**
Retry drop 144 -> 44 now explained rather than merely reported: "not ready" fires
when a submission races an invalidation, and tier-2 PROMOTION submissions are its
classic source; submissions fell 39 % (6358 -> 3853) and tier-2 promotions fell to
zero, which together over-explain a 69 % fall (volume alone predicts ~87). It is a
fourth proof the knob was absent, beside the empty `env`, the explicit `unset`,
and the absent storm.
Phrasing corrected twice: the three collided stage times are flushed ~9k-17k lines
after their label, just before the NEXT `Stage` marker (optimize 355977->365919,
qast 365920->382859, unit 382860->392103), not "on the following line"; and the
channel decomposition is exact — 372 `opt failed` lines = statistics-block
Permanent Bailouts 372, of which 370 name `PermanentBailoutException`, +6
statistics-block repetitions = raw grep 376, and 372 minus the 1 `Stage`-prefixed
line = summarizer 371.
**Ruling 33 held, and one review item was declined on it.** The review asked me to
record a cross-run root-multiset check (149 compiles unique to this run, 131 of
size >= 2069 equal to the Success delta, `encode_var[6418]` 13x here vs 0x there,
139126 ms over 131 compiles ~ 1062 ms each, with "roughly 184" honestly noted as
having overshot). That is a decomposition of what the size knob suppressed,
measured against the run where the knob is broken — the comparison ruling 33
forbids, on the run ruling 18 called meaningless for cross-configuration use. It
is recorded in the report as reviewer-supplied, NOT adopted, and filed for
milestone 7; the objection is jurisdictional, not technical. This run's verdict
rests on Task 3 alone. Relaxing ruling 33 is a user decision.
Also noted: the report never had a "prediction section" to strengthen — ruling 33
had directed the clean run be measured against Task 3 alone, so none was written.

Task 6 (clean): fix round 1/5 (4 items, 3 adopted, 1 REFUSED WITH REASON — commit
rakudo `3b216f6311`). The implementer verified `Splits : 0` in both logs itself
rather than taking it from the controller, struck concern 2, explained the retry
drop (volume alone predicts ~87 against 44 observed, so promotions-to-zero
accounts for the rest), and corrected both phrasing nits with measured distances
(the collided stage values flush 9942 / 16939 / 9243 lines after their labels,
not on the following line).

**Ruling 36 — the implementer was RIGHT to refuse the prediction item into its
report, and I am narrowing ruling 34 rather than overriding it.** It objected
that the root-multiset check is a cross-run comparison against the
broken-knob run — the comparison ruling 33 postponed, on the run ruling 18 called
meaningless for cross-configuration use — and that relaxing a user ruling is not
a controller's call to make inside a task report. It recorded the check as
reviewer-supplied, did not adopt it, filed it for milestone 7, and flagged it in
two places so the user can reverse it in one. That is the correct handling of a
boundary it could not itself move, and better than quietly complying.

My narrowing, with the distinction that matters: **the refusal SET is
defect-independent.** Which roots the knob refuses is decided entirely by
`programSize <= MAX_COMPILE_SIZE`; whether the refusal is retryable or permanent
changes how much waste it causes, not which roots are affected. So the
set-membership half of the check — 131 roots at or above 2069 compiling here and
not there, `encode_var[6418]` 13 times against 0 — is admissible and does not
reopen what the user closed. The millisecond aggregate (+139126 ms) IS a
cross-run performance figure and stays out of any marginal-value claim; it is
retained only as an internal coherence check (~1062 ms per compile, consistent
with roots of that size).

Where it lives, therefore: in THIS ledger as a controller record of a
pre-registered prediction, explicitly NOT as a marginal-value claim, and NOT in
the findings doc's tier-policy row, which stands against Task 3 alone as ruling
33 directs. The clean run's own report correctly carries none of it. The scoped
re-review is asked to adjudicate this independently, since it is my own
prediction being verified and I should not be the only judge of whether its
evidence is admissible.

**Milestone 7 lever #3, found by a user question (2026-09-12): deoptimisation
churn.** The user asked why `encode_var[6418]` is compiled 13 times in a single
process. Checked directly in the clean run's trace rather than reasoned about:

- **One call-target id** (`id=3067`), so it is not distinct roots sharing a
  name[size] label. It is the same target compiled and discarded repeatedly.
- Its event counts: **13 `done`, 11 `deopt`, 8 `inval.`**
- Its reasons: **10 `uncommon trap`**, **6 `validRootAssumption local tags
  updated`**, 1 `Profiled Return Type`, 1 `JVMCI invalidate`, 1 `dispatch site`.

Two distinct causes, and the second is specific to how this interpreter is built.
Uncommon traps are ordinary speculation failures: Graal optimises away paths not
yet seen, the code meets one, and it falls back. `validRootAssumption local tags
updated` is the **Bytecode DSL's** per-local type-tag guard: it tracks a tag per
local to keep values unboxed, guarded by a per-root assumption, and observing a
local hold a type outside its tag set invalidates the whole root's code.

`encode_var` is the worst case for both: it handles every variable form the
encoder meets — lexical, local, contextual, attribute, across value types — so
each new shape can widen a tag or break a speculation, and each costs a full
recompile of a 6418-word root. On a run-once compile it never reaches the stable
state it is converging towards.

Whole-run reason counts (clean run): `Unknown` 2030, `uncommon trap` 1192,
`dispatch site` 580, `JVMCI invalidate` 539, `validRootAssumption local tags
updated` 245, `Profiled Return Type` 113, `missing exception handler` 6,
`Profiled Argument Types` 1. **Caveat: the largest bucket is `Unknown`, so the
aggregate is suggestive; the per-root figures above are exact.**

This is independent of milestone 7's other two levers (the permanent-refusal fix
and the 442-root inlining bailout) and shares their theme: a compiler that runs
each block a handful of times pays warm-up costs it never amortises. Candidate
directions, none investigated: pre-seeding local tags for known-polymorphic
roots; widening tags eagerly rather than on first violation; or accepting boxed
locals in the encoder's own hot roots to trade peak speed for stability.

**Ruling 37 — SUPERSEDES RULING 34. My defect-independence argument was half
sound, and I drew the line generously toward myself.** I asked the re-review to
adjudicate my own narrowing and to say bluntly if I was rationalising. It did,
and it was right on both counts.

What is sound: the refusal PREDICATE is size-only, so which roots the knob
*refuses* is genuinely defect-independent.

What I over-read: the check does not diff the refusal set. It diffs the set of
roots **actually compiled**, which is downstream of queue dynamics the defect
demonstrably perturbed — 2.08 M resubmissions, Utilization 5.22 against 2.50,
Dequeues 389 against 343. Compilation counts are threshold- and time-driven, so
`encode_var[6418]` at 13x against 0x is precisely the quantity MOST exposed to
that perturbation, not a function of the size predicate at all.

The leak my own figures contained: 149 unique-to-clean minus 131 over-threshold
leaves **18 sub-threshold compiles** the size predicate does not explain and the
defect does — and the "exactly the Success delta" equality holds only because
those 18 are silently offset by 18 unique-to-combination compiles. I quoted the
equality as though it were a clean identity.

So the defensible claim is narrower than ruling 34 states: **direction and rough
population size are robust; the exact equality and the 13x multiplicity are
not.** Ruling 34 is therefore reworded here rather than deleted, since it remains
a good hypothesis for milestone 7:

- "CONFIRMED at the mechanism level" -> **CONSISTENT, pending milestone 7**.
- "exactly the Success delta (3334 - 3203 = 131)" -> 131 over-threshold roots
  against a Success delta of 131, an equality that depends on an 18-compile churn
  term cancelling, not on the size predicate.
- "the strongest form of evidence this milestone has produced" -> **struck**. It
  is not. The strongest evidence this milestone produced is the replicate pair's
  noise floor and the tier-2 elimination verified to the millisecond.
- The +139126 ms aggregate (~1062 ms per compile) -> **struck entirely**, as
  ruling 36 said it would be and as the committed text did not do.

Recorded process failure, not just a content one: ruling 36 described a narrowing
that the already-committed ruling 34 did not implement, and I did not check the
committed text against the narrowing I had just written. The reviewer caught the
inconsistency, rated it Major rather than Critical because no number, verdict or
shipping claim depends on it, and it does not. Costs if wrong: nothing now; had
it gone unfixed, milestone 7 would have inherited an overstated prior about its
own third lever.

Task 6 (clean): re-review round 1 (opus) — items 1-3 ADDRESSED and independently
re-verified (`Splits : 0` read at the cited lines; the retry explanation checked
rather than accepted, with volume arithmetic 144 x 3853/6358 = 87.3 against 44
observed and `Tier 2` trace lines 1379 -> 1; both phrasing fixes reproduce, flush
distances 9942/16939/9243 confirmed). Item 4 refusal upheld. One Major finding,
the ruling-34 inconsistency, resolved by ruling 37 rather than a further fix
round, at the reviewer's own recommendation. Ledger hunk 110/0, prior content
byte-unaltered.
Two nits it recorded as immaterial: "submissions fell 39 %" uses `Compilations`
while `Queues` fell 75 % (16196 -> 4098), so the stated figure is the conservative
one; and "tier-2 promotions are its classic source" is a mechanism assertion the
aggregate count cannot prove, appropriately hedged, with the quantitative claim
resting on volume.

Task 6 (clean): complete (commits `09f52a45b0`..`3b216f6311`, review clean after
one fix round; plus controller commits `c4a7ab4197` and `b4dfe0a4de`).
**This is the milestone's shipping number: wall 434 -> 337 s (-22.4 %),
total-compiler-ms 2143944 -> 783440 (-63.5 %), from tier policy alone,
build-side only.**

Task 7: implementer dispatched (opus); BASE rakudo `b4dfe0a4de`. Baseline is Task
6 CLEAN (not Task 3, not the combination run): the thread knob is layered on the
adopted tier policy. Both screens mandatory first. Note that Task 4's review
predicted a flat wall clock would demote this knob before it ran; that did not
happen — wall tracked compiler work in both Task 4 and Task 6, so contention is
real and the knob is worth its compile. At 783 s of compiler work across a 337 s
wall the engine is still running about 2.3 cores.

Task 7: KEEP. `engine.CompilerThreads=3` layered on the adopted tier policy.
Wall 337 -> 327 s (-10 s, -2.97 %); total-compiler-ms 783440 -> 619075
(-164365, -21.0 %); nqp-root-ms 727228 -> 565834 (-22.2 %); Success 3334 -> 3000
(-334); Permanent Bailouts 372 -> 366 (statistics channel; summarizer 366, raw
grep 370); Utilization 2.501061 -> 1.996044; Splits 0 -> 0; tier-2 compiles 0 on
both sides. Stages: parse 253.998 -> 248.832, optimize 32.017 -> 27.217, qast
25.389 -> 25.524, unit 23.476 -> 24.030, stage sum 334.881 -> 325.604 (-9.277);
optimize/qast/unit again recovered from their flushed value lines (356808,
374643, 383918) per the Task 3 --stagestats artifact. One compile, EXIT=0,
elapsed=327s, blib untouched, NQP_CODE_MAX_COMPILE unset (empty `env` grep plus
an explicit `unset` in the driver).

Task 7 SCREEN A: the declared default is -1 (`OptimizedRuntimeOptions.<clinit>`,
`iconst_m1`), not 0 and not a literal count; the option is STABLE, not
experimental (its descriptor says so — only the tier options it rides with are).
`BackgroundCompileQueue`'s constructor resolves -1 as
`max(1, min(procs/4 + log2(max(log2(procs),1)), 16))`, which at procs=16 is
**6**, and 6 was then OBSERVED at runtime on this box in a control run with no
CompilerThreads option (`/proc/<pid>/task/*/comm`, 5 consecutive samples). The
brief's `cores/2` = 8 would therefore have been a 33 % INCREASE over the real
default and would have probed the opposite direction; 3 was chosen instead as a
clean halving of the true default that still sits just above the baseline's
measured average demand (Utilization 2.50), so bursts queue but steady state
does not starve. 2 was rejected as below average demand.

Task 7 SCREEN B: implemented in `com.oracle.truffle.runtime.BackgroundCompileQueue`,
read once at pool construction via `OptimizedCallTarget.getOptionValue` and used
as both core and max size of `BackgroundCompileQueue$TruffleThreadPoolExecutor`
(threads named `TruffleCompilerThread`). On our path: that same class emits the
Queues/Dequeues/Time-waiting-in-queue lines present in both this run's and the
baseline's statistics blocks. Only three classes in the jar reference the option.

Task 7 IN FORCE, three channels, one direct: (a) 14 `/proc` samples spanning the
whole 327 s compile, every one showing exactly 3 `TruffleCompiler` threads
against the 6 observed under the default — a plain file read, no JVMCI attach,
so it cannot perturb the wall it sits beside; (b) Utilization 2.501061 ->
1.996044, structurally bounded by 3; (c) `Time waiting in queue` average
54 184.82 -> 1 900 656.61 ns, a 35x rise. The probe's missing
`nqp-code check passed` marker was NOT treated as a signal; real-path acceptance
was verified with `nqp-j-gradle -e 'say("engine-ok")'`.

Task 7 mechanism, labelled a FIT to observed quantities and not asserted (ruling
5 — the trace records no enqueue events; every number below is a statistics-block
counter, not an inference): Queues 4098 -> 4726, Dequeues 343 -> 1343 of which
`Stale compilation task` 190 -> 1137, Compilations 3853 -> 3422, Queue Accuracy
0.916301 -> 0.715827, retryable "not ready" 44 -> 2. Capacity halved, each task
waits ~35x longer, far more tasks are stale when a thread reaches them and are
dropped rather than compiled. Consequence for how the win is described: a large
share of the -21 % is **compilation never performed**, not contention relieved —
clean for a run-once 327 s build whose dropped compiles were servicing
superseded targets, and NOT transferable to a long-lived Rakudo process. Neither
of the dispatch's two predicted outcomes occurred in pure form: wall fell
modestly AND less compilation was done, with no wall penalty from the drop.

Task 7 caveat carried forward: `CompilerThreads=3` is hardware-specific. The
default formula gives 6 at 16 cores but only 2 at 4 cores, so a literal 3 would
RAISE the thread count on a small machine. Task 11 should adopt it as a value
measured on this box, or guard it by core count.

**Knobs in force at the end of the sweep (this run's exact set):**

    -Dpolyglot.engine.Mode=latency -Dpolyglot.engine.FirstTierCompilationThreshold=1600 -Dpolyglot.engine.LastTierCompilationThreshold=40000 -Dpolyglot.engine.CompilerThreads=3

**The line Task 11 adopts** — identical minus `LastTierCompilationThreshold`,
which Task 6 established is parsed but structurally inert under `Mode=latency`
(`firstTierOnly` forces its gate false) and which this run re-confirms inert by
producing zero tier-2 compiles:

    -Dpolyglot.engine.Mode=latency -Dpolyglot.engine.FirstTierCompilationThreshold=1600 -Dpolyglot.engine.CompilerThreads=3

`NQP_CODE_MAX_COMPILE` is not in the shipping configuration; it was dropped from
the milestone entirely. Per the user's rule this is the sweep's last compile and
there is no confirmation build. Full report:
.superpowers/sdd/2026-09-12-jvm-milestone-6-compiler-workload/task-7-report.md

**Provenance check (user question, 2026-09-12): are Task 7's thread numbers ours
or Truffle's, and why does thread count matter at all under Loom?** The user
instructed that any figure originating in OUR codebase rather than in external
Truffle defaults be removed immediately. Checked directly rather than defended.
**Nothing is removed: every figure is Truffle's.**

- `CompilerThreads` default **-1**: `iconst_m1` at offset 185 into
  `putstatic CompilerThreads` in `OptimizedRuntimeOptions`, inside
  `truffle-runtime-25.2.4.jar`. External.
- The resolution to a thread count: `BackgroundCompileQueue` calls
  `Runtime.availableProcessors()` and builds a `TruffleThreadPoolExecutor` with
  a `TruffleCompilerThreadFactory`. Same jar. External.
- **Our tree sets no compiler-thread count anywhere.** The sole match for the
  option name across `nqp/src`, `nqp/nqp-truffle/src`, `tools` and `src` is a
  COMMENT at `NqpPolyglot.kt:19`, a historical note from the engine merge saying
  the option used to apply twice when each engine built its own context.

**Why the count still matters under Java 25 / Loom, two independent reasons.**
(1) Truffle does not use virtual threads for this pool:
`BackgroundCompileQueue$TruffleCompilerThreadFactory` constructs a plain
`Thread` subclass and calls `setDaemon`; there is no `ofVirtual` on that path.
That is Truffle's construction inside its own jar, not a choice we make or can
flag. (2) Even if it did, virtual threads would not change the result. They
solve BLOCKING — few carrier threads servicing many waiting tasks. Graal
compilation does not wait, it burns CPU, so N virtual compilations still need N
cores. Task 7 measured CPU contention between the single-threaded compile driver
and the compilation pool on a 16-core box, which is a scheduling-capacity
question virtual threads are not about.

Where this tree DOES use virtual threads is guest-level concurrency only:
`Ops.kt:1125` (`Thread.ofVirtual().start`) and `Ops.kt:7182`
(`Thread.ofVirtual().unstarted`), i.e. NQP-level thread creation. A separate
axis from how the engine schedules its own compilations.

**Ruling 39 — `CompilerThreads` IS adopted, as a configure-time halving of
Truffle's own default, build-path only. This supersedes the draft ruling 38 that
was never committed.** I had drafted a ruling against adoption, reading the
user's "a four-core box will have a sad time" as a concern to protect small
machines. **That was a misreading.** The user's point was the opposite: a
four-core profile is IRRELEVANT to this project, because nobody with that
hardware would choose to run rakudo-j. The commit was interrupted before it
landed.

Inverting the premise inverts the conclusion. Our hardware profile is mid-to-large
machines, so the real hazard is UNDER-provisioning, not over-provisioning.
Running Truffle's formula upward: 32 cores gives 10 threads, 64 gives 16 (its
cap). A literal `CompilerThreads=3` would cut a large CI machine from 10 or 16 to
3 — a drastic, unmeasured reduction on exactly the hardware that matters. The
computed halving stays proportionate at any host size: 16 cores 6 -> 3, 32 cores
10 -> 5, 64 cores 16 -> 8.

So the computed form is right, but NOT for the portability reason the Task 7
review gave and not for the small-machine reason I gave. It is right because it
scales with the host.

Adopted form, per the review's Recommendation E: reproduce the engine's own
formula in `tools/build/create-jvm-runner.pl` (Perl, already assembles
`$truffle_opts` conditionally at :202-205, where it already emits
`-Dpolyglot.engine.WarnVirtualThreadSupport=false`) and halve it —
`my $d = max(1, min(int($p/4) + log2(max(log2($p),1)), 16)); my $t = max(1, int($d/2));`

**HAZARD Task 11 MUST handle, flagged by the review as Important:** that same
generator emits the shipped `rakudo-j` runner, which already carries a
`polyglot.engine` flag. Task 7's own evidence says the win is NOT transferable to
a long-lived process. The knob must be gated to the build/compile path — or to an
env var the Makefile sets — and must NOT reach `rakudo-j` unconditionally. The
same gate already applies to `Mode=latency` (ruling 30).

Caveat recorded with the adoption: **one point measured, 6 -> 3 on a 16-core
box.** The halving extrapolates from it. Costs if wrong: a proportionate but
unmeasured thread count on hosts unlike this one, visible in any later full build
and revertible by deleting four lines.

**Ruling 39 is PROVISIONAL pending a high-end measurement (user, 2026-09-12).**
The user's position moved again, and usefully: measure the MAXIMUM practical
compiler-thread count and see what it does to compile and parse times, rather
than adopting a halving extrapolated from a single point.

That is the right call and it dissolves ruling 39's own caveat. We currently have
one measured point (3, Task 7) against an unknobbed control (6, Task 6 clean). A
high-end run gives a **three-point curve on this box** — 3 / 6 / max — which
shows the SHAPE rather than a direction, and tells us whether Task 7's -10 s came
from relieving contention (in which case the curve has a minimum somewhere and
going higher is worse) or from something monotone.

Note the tension the curve will resolve: Task 7 found FEWER threads better, with
its mechanism being fewer stale compiles (stale dequeues 190 -> 1137, demand
rising +628 enqueues, queue fully drained on both sides). A naive
"more cores, more compilation throughput" expectation predicts the opposite. One
of those is wrong and a third point will say which.

No adoption is written into any file until the curve exists. Task 11 does not run
before then.

**Curve plan agreed (user, 2026-09-12).** After the 16-thread run lands, ONE
BATCHED dispatch measures **2, 8 and 12**, giving a six-point curve at 2 / 3 / 6 /
8 / 12 / 16. Batching is the skill's same-shape rule: three compiles, one report,
one review, roughly a third of the overhead of three separate task cycles.

Two choices recorded with their reasons. (a) **2 rather than 4.** We already have
3, so 4 sits one thread away and would mostly measure noise; 2 tests the boundary
Task 7 explicitly flagged as untested — whether going below 3 keeps helping or
falls off the starvation knee. (b) **The curve is read on
`total-compiler-ms`.** The wall floor is a single whole-second quantum at ~337 s,
so adjacent points will differ by less than the resolution, while compiler work
has a 0.7 % floor and moved 21 % between 3 and 6.

Stated up front so it cannot be forgotten at interpretation time: one workload,
one machine, one sample per point. The curve can honestly deliver the SHAPE —
flat middle, U with a real optimum, or monotone — not a minimum located to within
a thread or two. A plateau means pick anything inside it and stop measuring.

## Task 7 MAX — the high end measured: 16 threads, wall 346 s

Third curve point landed. rakudo `37f3a76be6`, nqp `41c294b029`, one compile,
`EXIT=0 verdict=ok elapsed=346s`, `NQP_CODE_MAX_COMPILE` not set, blib untouched.
Full report: `.superpowers/sdd/2026-09-12-jvm-milestone-6-compiler-workload/task-7-max-report.md`.

**Screen A.** An EXPLICIT `engine.CompilerThreads` may exceed 16 and nothing
validates it. In `BackgroundCompileQueue.getExecutorService` the `bipush 16 /
Math.min` sits inside the `threads < 0` branch; an explicit positive value hits
`ifge 163` first and meets only `Math.max(1, threads)`, a floor. The key is built
with the single-argument `OptionKey.<init>(Object)` — the default Integer
OptionType, no range check — so the descriptor's `[1, inf)` is literally what is
implemented. The option is STABLE, not experimental (its neighbour
`CompilerThreadStackSize` is EXPERIMENTAL in the same method). A 24-thread engine
probe was accepted and grew the pool to 8 (above the default 6); it did not reach
24 because core threads are created on demand — no `prestartAllCoreThreads`
anywhere in the class. **16 chosen**: one per core is the hardware ceiling and the
engine's own ceiling for its default computation, and anything past it is pure
oversubscription that would confound the point with scheduler thrash.

**In force**: 20 `/proc/<pid>/task/*/comm` samples, 19 at exactly
`trufflecompiler=16` (the 20th, 12, during wind-down). Corroborated by
`Compilation Utilization` 2.501061 -> 2.730003 and `Time waiting in queue`
average 54 184.82 -> 732.25 ns (a 74x FALL, inverting the 3-thread run's 35x rise).

**Result vs the 6-thread control**: wall **337 -> 346 s (+9, +2.67 %)**,
`Stage parse` **253.998 -> 262.367 (+8.369, +3.29 %)`, optimize 32.017 -> 31.926,
qast 25.389 -> 25.988, unit 23.476 -> 24.370, stage sum 334.881 -> 344.657
(+9.776). `total-compiler-ms` 783 440 -> **893 381 (+14.0 %)**, `nqp-root-ms`
727 228 -> **832 026**. `Success` 3 334 -> 3 355, `Permanent Bailouts` 372 -> 372,
`Splits` 0, `Queues` 4 098 -> 3 920, `Dequeues` 343 -> 127, stale dequeues
190 -> **2**, `Remaining Compilation Queue` 0 (nothing truncated at exit).
Tier-2 compiles 0, as on both other points.

**THE THREE-POINT CURVE (3 / 6 / 16 threads):**
wall **327 / 337 / 346 s**; `total-compiler-ms` **619 075 / 783 440 / 893 381`;
stale dequeues **1 137 / 190 / 2**; `Success` **3 000 / 3 334 / 3 355**.
Both wall and compiler time are **monotone increasing**. There is no interior
minimum: the optimum lies at or below 3 threads, roughly 1 s of wall per thread
across the whole measured range.

**Ruling 40: the tension in ruling 39's note is resolved, and both stories were
describing different axes.** More threads DO do more compilation — stale dequeues
fall to 2, the queue stops constraining anything — so the naive throughput
expectation is confirmed on throughput. It is refuted on wall, because that
compilation is not on the critical path while the CPU it burns is. Decisive
detail: 3 -> 6 threads gained +334 `Success`; 6 -> 16 gained **+21 (+0.63 %),
below the 0.7 % `Success` noise floor** — unbuyable at any price, for 110 s of
extra compiler CPU, 101 cancellations and 54 retryables. Contention dominates;
Task 7's -10 s was contention relief.

Caveats carried forward, not smoothed: one sample per point; +9 s is nine
one-second quanta corroborated only by the stage sum (same run, finer
resolution); 16 threads on 16 cores starves the main parse thread, GC and JVMCI,
so the ratio may not travel; `Queues` is NON-monotone across the curve
(4 726 / 4 098 / 3 920), so arrivals are shaped by service rate and any queue
story stays a fit to counters, never an established mechanism; >16 is accepted
but unmeasured, and on-demand growth means a bigger request may not manifest more
threads anyway. The batched 2 / 8 / 12 dispatch still stands, and this point
tells it where to look: the interesting half of the curve is BELOW 3.

Task 7-max (16 threads): implementer DONE — rakudo `c219ab648e`. SCREEN A found an
explicit value MAY exceed 16 (the `bipush 16`/`Math.min` cap sits inside the
`threads<0` branch; an explicit positive meets only `Math.max(1,threads)`, and the
key is built with the single-arg `OptionKey(Object)` so there is no validator).
A 24-thread probe was accepted. It chose **16** — one per core, the engine's own
default ceiling — on the grounds that beyond it is pure oversubscription that
would confound the measurement with scheduler thrash. IN FORCE: 20 `/proc` samples,
19 at exactly 16. Utilization 2.501 -> 2.730; queue wait 54184.82 -> **732.25 ns**,
a 74x FALL inverting the 3-thread run's 35x rise.

**THE CURVE, 3 / 6 / 16 threads, tier policy throughout:**

| threads | wall | Stage parse | total-compiler-ms | Success | stale dequeues |
|---|---|---|---|---|---|
| 3 | **327 s** | 248.832 | **619075** | 3000 | 1137 |
| 6 (default) | 337 s | 253.998 | 783440 | 3334 | 190 |
| 16 | 346 s | 262.367 | 893381 | 3355 | 2 |

**Both axes monotone INCREASING. No interior minimum. ~1 s of wall per added
thread. The optimum is at or below 3.**

**Ruling 40 — the contradiction is resolved: both stories were true, on different
axes, and contention dominates.** Task 7 found fewer threads faster (mechanism:
fewer stale compilations); the naive expectation said more threads should mean
more throughput. The 16-thread run shows the throughput expectation is CORRECT ON
THROUGHPUT — stale dequeues collapse 1137 -> 190 -> 2 as the queue stops
constraining — and REFUTED ON WALL, because that extra compilation is off the
critical path while its CPU cost is not. The decisive comparison: 3 -> 6 bought
**+334** Success; 6 -> 16 bought **+21**, which is +0.63 % and **below the 0.7 %
Success floor**, for 110 s of extra compiler CPU. So Task 7's -10 s was contention
relief, as it claimed, and the high end buys nothing measurable. Costs if wrong:
none; this is three points agreeing on two axes.

**Batch redirected (controller, on the implementer's own closing note that "the
interesting half of the curve is below 3").** The agreed batch was 2 / 8 / 12.
8 and 12 now sit inside a region measured monotone increasing and would only
confirm a line. Replaced with **1 / 2 / 4**: 1 and 2 explore the unmeasured
territory where the optimum lies, including the starvation knee Task 7 flagged,
and 4 brackets 3 so we learn whether 3 is a genuine local minimum or a point on a
slope. Final curve: 1 / 2 / 3 / 4 / 6 / 16. Costs if wrong: two points of the
upward slope go unmeasured, recoverable in one batched run.

Task 7-max: review (opus) — spec compliance full, hygiene clean, **every number in
section A verified independently and NO numeric error found**. The reviewer summed
the trace's own time fields itself: 893412 against the reported 893381, the 31 ms
gap being the single stage-collided `opt failed` line the summarizer cannot see,
with the same structure at the control (783461/783440) and at 3 threads. Screen A
re-verified in the jar by its own `javap`: the `bipush 16 / Math.min` clamp sits
only in the `threads < 0` arm (branch `ifge 163` at 118 skips it), the key is
built with single-arg `OptionKey(Object)`, stability is STABLE with usageSyntax
`[1, inf)`, and there is no `prestartAllCoreThreads`. It endorsed the choice of 16
for a STRONGER reason than the implementer gave: **the pool is demand-driven and
this workload never averaged more than 2.73 busy threads, so a request above 16
could not have manifested anything to measure.**

**Ruling 41 — SUPERSEDES THE CAUSAL HALF OF RULING 40. "Contention dominates" is
NOT established, and the run's own utilization contradicts it.** I recorded it as
settled. It is not, and the evidence against it was in the same statistics block I
quoted from.

893381 ms of compiler CPU over a 346 s wall is **2.58 core-equivalents out of 16**,
matching the engine's own `Utilization 2.730003`. Across the three points the
occupancy is 1.89 / 2.32 / 2.58 cores (Utilization 2.501 at the control). **The
machine was ~16 % busy. The extra capacity sat idle.** So 6 -> 16 is roughly
**+0.25 cores of average occupancy buying +9 s of wall**, which is not a
contention story at face value, and the implementer's concern that 16 threads
starve the parse thread, GC and JVMCI is **not supported by this run** and should
be withdrawn rather than carried.

What survives: more threads cause more compiler CPU and a longer wall, monotone
across the measured points. What does NOT survive: the causal account. "Off the
critical path" was reached by SUBTRACTION — background compilation can touch the
wall through contention or through when compiled code lands, the report showed
the latter bought little, and inferred the former. Candidates not eliminated:
burst contention that an average hides, code-cache or GC pressure from more
installed code, or something unlooked-for. What would settle it is process-CPU
accounting or a box-idle record, and neither was taken. Labelled a FIT, exactly as
ruling 7 labels the queue chain. Costs if wrong: the direction is unaffected; only
the explanation is.

**Ruling 42 — two of my own sentences in ruling 40 were wrong and are corrected.**
(a) "~1 s of wall per added thread" is arithmetically false across the range:
3 -> 6 is **3.33 s/thread**, 6 -> 16 is **0.90 s/thread**, a **3.7x flattening**.
The flattening is the real finding and it STRENGTHENS the redirect below 3; as
written the sentence invited the opposite extrapolation. (b) "No interior minimum"
is over-read from three points with uneven gaps (3 threads, then 10). The
defensible statement is **"no dip AT the measured points, and both endpoints are
worse than 3"**; a dip anywhere in 7-15 is untested and, given the redirect, will
stay untested.

Task 7-max: minor (deferred to the implementer's report, not the ledger):
`Compilation cancelled` is tabled as "—" for the control and cited as a cost of
the high end; the control had **87** (rising to 101, +16 %), so the high end's
cost is overstated. Also a false aside that the neighbouring
`CompilerThreadStackSize` is EXPERIMENTAL — it is STABLE; the experimental
neighbour is `CompilerIdleDelay`. Neither moves the STABLE claim for
`CompilerThreads`, which is correct.
Task 7-max: minor — the floor argument used the WEAKER reading. The 0.7 % floor
came from Success 5658 vs 5617, i.e. **41 compiles**; transferred as a percentage
onto a base of 3334 it is ~23, so +21 is **at** the floor rather than comfortably
below, while transferred as an absolute count (21 against 41) it is clearly below.
The conclusion survives either way, but the report asserted the marginal version
as settled and never made the robust one.

**Reviewer's verdict, adopted: the curve's SHAPE is safe to build an adoption
decision on; its MECHANISM is not.** Both axes monotone increasing, every number
reproducing from raw logs, the configuration proven in force by direct thread
sampling, and +9 s is 13x the wall floor. Adopt the direction — fewer threads, the
steep slope is near 3, measure 1 and 2 next — and not ruling 40's causal half.

**Ruling 43 — what the extra compilations ARE, found by a user question: they are
re-compiles, not coverage. The thread knob is a workaround for deoptimisation
churn.** The user asked whether the extra compilations were failing to "lift back
into use". Checked directly across the three logs rather than reasoned about:

| threads | compiles | **unique roots** | compiles/root | deopt | inval |
|---|---|---|---|---|---|
| 3 | 2998 | **1479** | 2.03 | 3522 | 754 |
| 6 | 3334 | **1515** | 2.20 | 3767 | 939 |
| 16 | 3355 | **1515** | 2.21 | 3808 | 952 |

**6 -> 16 threads bought 21 extra compilations and ZERO new unique roots.** Not
one additional part of the compiler got compiled; every one of the 21 was a
recompile of a root already compiled. Even 3 -> 6 added 336 compilations for only
36 unique roots, so ~300 were repeats. Coverage saturates at 1515; three threads
loses 36 of them, 2.4 %.

So the compiled code DOES land and run. It is then invalidated and compiled
again. More threads buy more ITERATIONS OF THAT CYCLE, not more of the compiler
running compiled — and the deopt counts rise in step (3522 / 3767 / 3808).

**The fit (labelled a fit, not a proof): the compile queue is a DEBOUNCER.** When
a root deoptimises and re-requests compilation several times in quick succession,
a slow queue lets those requests supersede one another and collapse into one —
which is exactly what stale dequeues show (1137 discarded at 3 threads, 190 at 6,
2 at 16). A fast queue faithfully services every redundant request. This fits
every counter we have, and unlike ruling 40's withdrawn "contention dominates" it
is supported by a positive observation (coverage saturation) rather than reached
by subtraction. It still does not prove the WALL causation, which ruling 41 leaves
open.

**Consequence, and it reframes the knob: reducing compiler threads is not a
scheduling optimisation, it is a crude workaround for deoptimisation churn** —
the same churn the `encode_var[6418]` investigation named as milestone 7's third
lever (13 compiles of one root, 6 of them from the Bytecode DSL's per-local
type-tag assumption). This is that phenomenon at scale: 1515 roots averaging over
two compilations each.

**Testable prediction for milestone 7, recorded now so it can be checked later:
fix the churn and this knob's benefit should shrink or vanish.** If it does not,
the debounce fit is wrong.

Caveat: unique roots are counted by `name[size]`, a label already known to merge
distinct call-target ids (the `PERFORM-BEGIN` case). The 6-vs-16 comparison is
unaffected — both 1515 — but the absolute counts are approximate.

**Ruling 44 — ruling 43's counts were taken with the WRONG identity, recounted by
`id`, conclusion survives.** The user pointed out that `name[size]` was already
established as inferior — **ruling 20** settled that the engine's `id=`
call-target identity is primary, because that is what the queue and the size
predicate act on, and that `name[size]` merges distinct targets. I then ran
ruling 43's analysis on the label I had myself recorded as wrong. That is the
SECOND time in this milestone I have used a convention already ruled against, and
both times someone else caught it.

Recounted by `id=`:

| threads | compiles | unique by **id** | unique by name[size] | compiles/target |
|---|---|---|---|---|
| 3 | 2998 | **1626** | 1479 | 1.84 |
| 6 | 3334 | **1672** | 1515 | 1.99 |
| 16 | 3355 | **1672** | 1515 | 2.01 |

The label under-counted by ~147-157 targets per run, about 10 %. **Every claim in
ruling 43 survives**, with corrected figures: 6 -> 16 still buys 21 compilations
and **ZERO** new targets; coverage still saturates, at **1672** not 1515; three
threads loses **46 targets, 2.8 %** (not 36, 2.4 %); compiles per target is
1.84 / 1.99 / 2.01 (not 2.03 / 2.20 / 2.21). The debounce fit is unaffected and
so is the reframing of the knob as a churn workaround.

**Sweep-back required, recorded as a milestone-7 hand-off item:** any other
analysis in this milestone that used `name[size]` where `id` was available must
be redone before it is relied on. Known candidate: the per-compile root multiset
diff behind rulings 34/37 (the "131 roots at or above 2069" claim) — already
downgraded by ruling 37 to "consistent, pending milestone 7" for a different
reason, and now also owing an identity recount. The `encode_var[6418]` analysis is
SAFE: it was explicitly checked to carry a single `id=3067`, so no merging was
possible there.

**Process note, and the more useful half of this.** The user asked whether
insisting "we cannot go further while this is the case" was an overreaction. On
the principle, no — the identity was already settled and I ignored it. On the
blanket rule, the recount was one command answering in seconds, so the right
response to a known-bad identity surfacing is to REDO the analysis, not to halt;
and had the conclusion moved, that is precisely when you want to know before
spending more compiles. What deserves attention is the pattern rather than the
instance: rulings in this ledger are not being consulted by the controller that
wrote them.

**Ruling 45 — the name ambiguity is a DISPLAY-LABEL defect, not a compiler
identity defect. Not stop-the-world; the user's rule is right and its condition is
not met.** The user asked the sharper version of the question I had answered: if
the compiler itself cannot distinguish two compilation targets, that is
stop-the-world; if it is only log analysis, different story. Checked rather than
reasoned:

- `NqpRootNode.getName()` (`:91-94`) is OURS and its own comment says it is
  "What TraceCompilation prints for the call target" — a display string.
- `blockName` is touched in exactly two places in that file, `getName()` and
  `toString()`. Nowhere semantic, in that file or in the Kotlin engine sources.
- `OptimizedCallTarget`'s compilation path does not reference `getName` at all
  (javap over the class: no hits).
- No name-based compilation filtering (`CompileOnly` or equivalent) exists
  anywhere in `com/oracle/truffle/runtime` in this jar.
- Positive evidence: the trace prints `id=` as its own field and those ids ARE
  distinct — **1672 against 1515 labels**. The engine tracked every target
  separately and reported it in a column I failed to read.

**So compilation identity is the call target object and is unaffected.** The
engine never merges two targets; only name-keyed VIEWS do.

**It is still a real defect worth fixing, and broader than my greps.** ~150
targets per run, about 10 %, are indistinguishable in any name-keyed view — and
that includes **the engine's own `CompilationStatistics` grouping**, which reports
`maxTarget=<name>` counts. A target reported as compiled 13 times could in
principle be two targets at 7 and 6. Flame graphs and external profilers merge
them identically. I had not considered the statistics-grouping consequence until
the user pushed on it.

**Deferred to milestone 7, NOT fixed now:** adding a discriminator to `getName()`
lives in `nqp-truffle` sources, so doing it mid-sweep rebuilds the runtime jar and
breaks comparability across every measurement in this milestone, in exchange for a
diagnostics improvement. It joins the other runtime work. Costs if wrong: one more
milestone of name-keyed views merging ~10 % of targets, with `id=` available in
the trace as the correct identity in the meantime.

Task 7-curve (1 / 2 / 4 threads, one batch): implementer DONE — rakudo
`f766603dce` at run time (HEAD moved to `ab0ecd81d4` mid-batch as this ledger was
being committed concurrently; the diff is this file only, +194 lines, so all
three compiles ran against an identical source tree), nqp `41c294b029`. All three
values ACCEPTED on the real engine path, and IN FORCE by direct `/proc` sampling
with **no deviation in 78 samples**: 24/24 at exactly 1, 26/26 at exactly 2, 28/28
at exactly 4. Corroborated by `Compilation Utilization` 0.958300 / 1.603661 /
2.256520 and by average queue wait 11 261 151.57 / 5 180 716.12 / 843 631.41 ns —
the 1-thread run's 11.3 ms average wait is the largest recorded in this milestone.
`NQP_CODE_MAX_COMPILE` unset throughout, `blib` untouched, three distinct output
jars, one compile per point, no re-runs, summarizer not edited.

**THE SIX-POINT CURVE, tier policy throughout:**

| threads | wall | Stage parse | total-compiler-ms | Success | stale dequeues |
|---|---|---|---|---|---|
| **1** | **297 s** | **225.941** | **277 722** | **1 578** | **972** |
| **2** | **323 s** | **249.839** | **503 022** | **2 653** | **2 103** |
| 3 | 327 s | 248.832 | 619 075 | 3 000 | 1 137 |
| **4** | **341 s** | **260.621** | **728 428** | **3 156** | **622** |
| 6 (default) | 337 s | 253.998 | 783 440 | 3 334 | 190 |
| 16 | 346 s | 262.367 | 893 381 | 3 355 | 2 |

**Ruling-grade finding: 3 WAS NOT A MINIMUM. It was a point on a slope that keeps
falling to the hard floor.** `total-compiler-ms` is **strictly monotone increasing
across all six points**, smallest step +14.0 % (6→16), largest **+81.1 % (1→2 —
the second thread nearly doubles compiler CPU)**. Wall is monotone increasing
across 1 / 2 / 3 / 4, with a 4 s inversion at 6 and a rise at 16. **The minimum is
at 1, the `Math.max(1, threads)` floor, and the knob's answer on this workload is
"as few as possible".** Not a plateau, by the dispatch's own test: 1-4 span 44 s
and a factor of 2.6 in compiler CPU; 1→2 alone is 26 s, ~44x the 0.2 % wall floor.

**The per-thread slope is the real shape and it flattens ~29x:** +26.0 s for the
second thread, +4.0 (2→3), +14.0 (3→4), -2.0 (4→6), **+0.9 s** for each of the
last ten. Ruling 42 measured a 3.7x flattening over 3→16; the low end extends it
to ~29x over the full range. The cost of threads is concentrated in the first few.

**Ruling 43's debounce fit SURVIVES and gains a boundary, found by extending the
`id=` count (ruling 44's identity, validated by reproducing the 16-thread row
3 355 / 1 672 / 1 515 / 2.01 exactly).** Unique targets by `id=` across the curve:
**1 033 / 1 552 / 1 626 / 1 649 / 1 672 / 1 672**. Saturation at 1 672 holds from 4
upward (4 threads is within 23 targets, 1.4 %). **Below 3 it breaks: 2 threads is
120 targets short (7.2 %) and 1 thread is 639 short — 38.2 % of the compiler's
call targets never compiled at all.** So the knob debounces above 3 and genuinely
STARVES coverage below it. `compiles/target` falls monotonically 2.01 → 1.53 and
`opt deopt` falls 3 808 → 2 355 in step, confirming the churn picture from the
other end.

**So the starvation knee EXISTS, sits between 2 and 1, and is on COMPILATION, not
on wall.** Three counters place it there and nowhere else: coverage falls off a
cliff, `Remaining Compilation Queue` goes **non-zero (7) for the first and only
time in this milestone**, and queue wait reaches 11.3 ms. Wall does not rise at
that knee. On a run-once compile, 38 % of the coverage and 1 777 of 3 355
compilations are not worth what they cost to produce.

**Ruling 41 is NOT revived and the low end makes its puzzle SHARPER.** Core-
equivalent occupancy (`total-compiler-ms` / wall) across the six points is **0.94
/ 1.56 / 1.89 / 2.14 / 2.32 / 2.58 cores of 16** — the fastest run kept the box
~6 % busy, the slowest ~16 %, and 49 s separates them with fourteen cores idle in
every run. One compiler thread on a 16-core box cannot be starving the parse
thread. Labelled a fit to counters; settling it still needs process-CPU accounting
or a box-idle record, which this batch did not take either.

`Queues` is non-monotone across the low end too and more violently than above —
2 921 / 5 329 / 4 726 / 4 349 / 4 098 / 3 920, **peaking at 2** — and `Queue
Accuracy` bottoms at 0.564083 at 2 rather than at an endpoint. Ruling 7 stands.
Tier-2 compiles 0 in all three, `Splits` 0, summarizer hygiene clean
(`unparsed=0`). Failure channels kept apart per ruling 4: statistics-block
`Permanent Bailouts` 235 / 351 / 373, summarizer `failed=` 235 / 351 / 372, raw
grep 240 / 355 / 376.

Caveats carried forward, not smoothed: one sample per point; the 2→3 step (4 s)
and the 4→6 inversion (-4 s) are each ~1.2 % and cannot be separated from the wall
resolution, so the shape rests on 1→2 and 1→16 and not on those; the 4→6 inversion
breaks strict monotonicity on wall and one sample cannot say whether it is noise
or a real shallow dip at 6; **1 thread wins this build while leaving 38.2 % of
targets uncompiled, which is the opposite of what a long-lived Rakudo process
wants, and nothing in this milestone measures that case**; the 1-thread counters
are marginally truncated (queue did not drain); `Success` and the statistics
block's `maxTarget` groupings remain name-keyed and merge ~10 % of targets;
CORE.c only, one machine, and the box was not idle (a concurrent ledger-committing
session).

Task 7-curve (batched 1 / 2 / 4): implementer DONE — rakudo `a71c11a6b7`, three
compiles, `EXIT=0` each, one commit. In force by **78 `/proc` samples with zero
deviation**: 24/24 at exactly 1, 26/26 at 2, 28/28 at 4. Corroborated by
Utilization 0.958 / 1.604 / 2.257 and queue wait 11261152 / 5180716 / 843631 ns.

**THE SIX-POINT CURVE, tier policy throughout, unique targets by `id=` (ruling
44's correct identity):**

| threads | wall | Stage parse | total-compiler-ms | unique targets | coverage |
|---|---|---|---|---|---|
| **1** | **297 s** | 225.941 | **277722** | **1033** | 61.8 % |
| 2 | 323 s | 249.839 | 503022 | 1552 | 92.8 % |
| 3 | 327 s | 248.832 | 619075 | 1626 | 97.2 % |
| 4 | 341 s | 260.621 | 728428 | 1649 | 98.6 % |
| 6 (default) | 337 s | 253.998 | 783440 | 1672 | 100 % |
| 16 | 346 s | 262.367 | 893381 | 1672 | 100 % |

Compiler time is **strictly monotone increasing, no exception**; the second thread
alone costs **+81 %**.

**Ruling 46 — 3 was never a minimum; the minimum is at the hard floor of 1, and
compilation is NET-NEGATIVE at every level measurable on this workload.** Wall
falls monotonically as compilation falls, 346 -> 297 s, and the per-thread slope
flattens ~29x (+26 s for the second thread, +0.9 s for each of the last ten). The
redirect below 3 was right and Task 7's "3 is better than 6" was a point on a
slope, not an optimum.

**How that is possible without being absurd: the queue is a HOTNESS FILTER.**
Compilation is ordered by call count, so one thread still compiles the 1033
hottest targets and never reaches the tail; the 639 it skips were not paying for
themselves inside a run-once compile. This is ruling 43's debounce fit generalised
— and it now has a measured boundary: **coverage saturates from 4 threads up, and
1 thread leaves 38.2 % of call targets never compiled** while still being the
fastest.

**Ruling 41's puzzle SHARPENS rather than resolving.** Occupancy across the curve
is 0.94-2.58 cores of 16. The FASTEST run used under one core and left ~14 idle.
No contention account fits that. A candidate nobody has tested, recorded as a
candidate only: installation and invalidation are not free to the mutator even
when the compilation itself is off-thread — each costs a handshake or safepoint
against the single-threaded compile driver, and deopts (3522 / 3767 / 3808) each
return control to the interpreter. That would make the cost proportional to
compilation COUNT rather than to CPU, which is what the curve shows. Untested.

Caveats recorded: at 1 thread `Remaining Compilation Queue` is **7**, non-zero for
the only time in this milestone, so its counters are marginally truncated; the
2->3 step (4 s) and the 4->6 inversion (-4 s) are ~1.2 % each and inside the wall
resolution, so the SHAPE rests on 1->2 (26 s, ~44x the floor) and 1->16; `Queues`
is non-monotone and peaks at 2 (2921/5329/4726/4349/4098/3920), so any queue story
stays a fit to counters; CORE.c only, one machine, and the box was not idle (this
controller session was committing concurrently).

**Correctness note: build OUTPUT is unaffected.** How much of the compiler runs
compiled changes only speed, not what it emits.

**Subagent failure logged (model policy, 2026-09-11 rule).** The zero-point
implementer (opus) returned MALFORMED OUTPUT: instead of its report contract it
emitted a fragment of a Monitor progress event, which the harness flagged as
instruction-shaped and neutralised. It terminated after ~140 s having written no
report file and made no commit.

**The work itself is intact and was NOT re-dispatched.** Inspection shows it had
correctly started the compile before failing: `watched-run.raku` pid 1284762 and
the compile JVM pid 1284769 are alive with the right command line
(`--stall=1560 --max=1560`, output to `m6-corec-nocomp.jar`, tier policy set,
`Compilation=false`, no `NQP_CODE_MAX_COMPILE`). So the failure was in REPORTING,
not in setup or execution.

Verified in force while it runs, which is the evidence the lost report owed:
**0 `[engine] opt done` lines** in the log and **0 `trufflecompiler` threads** in
the live JVM's `/proc/1284769/task/*/comm`. Compilation is genuinely off.

Ruling: collect the result directly rather than re-dispatch. The remaining work is
reading a log for wall clock and stage times, which needs no agent, and
re-dispatching would either duplicate a running compile or waste the one in
flight. The user rule permits escalating an erroneous subagent to Fable; not
invoked, because the error was output handling rather than reasoning and there is
nothing left for a subagent to reason about. Costs if wrong: the controller reads
one log.

**ZERO POINT: wall 360 s, Stage parse 278.213, ZERO `opt done` lines, zero
Truffle compiler threads.** Collected by the controller from the log the failed
subagent had correctly started (`EXIT=0 verdict=ok elapsed=360s`).

**THE COMPLETE SEVEN-POINT CURVE, tier policy throughout:**

| threads | wall | Stage parse | total-compiler-ms | unique targets |
|---|---|---|---|---|
| **none** | **360 s** | 278.213 | 0 | 0 |
| **1** | **297 s** | 225.941 | 277722 | 1033 |
| 2 | 323 s | 249.839 | 503022 | 1552 |
| 3 | 327 s | 248.832 | 619075 | 1626 |
| 4 | 341 s | 260.621 | 728428 | 1649 |
| 6 (default) | 337 s | 253.998 | 783440 | 1672 |
| 16 | 346 s | 262.367 | 893381 | 1672 |

**Ruling 47 — the registered prediction is CONFIRMED in direction and REFUTED in
magnitude, and the refutation is the more valuable half.** Before the run I
predicted compilation-off would be "sharply slower", reasoning that interpreted
execution is typically an order of magnitude worse. Direction: right — 360 s is
the SLOWEST of all seven points, 63 s worse than 1 thread and 14 s worse even than
16. The curve is a genuine U with its minimum at the hard floor of 1, so ruling
46's "minimum at the floor" stands and is not an endpoint artefact. The
hotness-filter account (ruling 46) is validated: compilation ordered by call count
means 1 thread gets the targets that repay it and skips the tail that does not.

But the magnitude refutes my reasoning. Had "an order of magnitude worse
interpretation" been the operative effect, removing compilation would have cost
far more than 21 %. Inverting it gives the milestone's real headline:

**Truffle's ENTIRE JIT contribution to a CORE.c compile is at most 63 s of 360,
i.e. 17.5 % — and the default configuration captures only ~37 % of it** (337 s
against the 297 available; 16 threads captures 22 %). Tier policy and thread count
are not tuning a large effect. They are recovering most of a SMALL one that the
default was mostly throwing away. Every adoption in this milestone should be read
against that ceiling.

Where the loss sits: `Stage parse` 225.941 -> 278.213 is +52.3 s, **83 % of the
63 s total**, which is where the hot loops (grapheme scanning, regex matching,
bytecode dispatch) live — consistent with the prediction's reasoning even though
its magnitude was wrong.

**Ruling 48 — the adoption simplifies radically: `CompilerThreads=1`, literal, no
formula.** The minimum is the engine's HARD FLOOR (`Math.max(1, threads)`), and 1
is 1 on every machine. All of rulings 38/39's agonising over a hardware-dependent
computed halving is moot — there is nothing to scale. Still build-path only
(ruling 30's gate), and still not into `create-jvm-runner.pl`'s `$jopts` for the
shipped runtime, where 38.2 % of targets left uncompiled is exactly wrong for a
long-lived process.

Caveats carried: one sample per point; 1 thread leaves 38.2 % of call targets
never compiled and was the only run whose queue did not drain (`Remaining
Compilation Queue` 7); CORE.c on one machine; and the 2->3 step and 4->6 inversion
remain inside the wall resolution, so the SHAPE rests on none->1 (63 s), 1->2
(26 s) and 1->16 (49 s), all far outside it.

**ZERO-POINT IMPLEMENTER'S EVIDENCE, appended after the fact.** The implementer's
report did reach disk: `.superpowers/sdd/2026-09-12-jvm-milestone-6-compiler-workload/task-7-zero-report.md`.
It agrees with rulings 47 and 48 on every number already recorded above (wall
360 s, `Stage parse` 278.213, zero `opt done`) and adds four things the
controller's direct collection did not cover. Nothing above is amended.

**SCREEN of `engine.Compilation`, by `javap` on `OptimizedRuntimeOptions` and its
`...OptionDescriptors` in `nqp/build/jvm/share/truffle/truffle-runtime-25.2.4.jar`:**
the key **exists** (`OptionKey<Boolean> Compilation`, option name
`engine.Compilation`); its **default is `true`** (`<clinit>` builds it with
`iconst_1`); its **stability is EXPERIMENTAL**, category EXPERT, **not
deprecated**; help text "Enable or disable Truffle compilation." EXPERIMENTAL is
the same class as `CompilerThreads`, which ruling 30's gate already accepts on the
real engine path. It was accepted here with no warning of any kind.

**IN FORCE, third channel — the `/proc` thread count, sampled to completion.**
The controller checked the live process once mid-run; the implementer sampled
`/proc/<pid>/task/*/comm` every 12 s for the whole compile: **0 `TruffleCompiler`
threads in 30 of 30 samples, maximum 0.** Not an idle pool — the pool is never
created. Corroborated by the statistics block, which printed in full with
`Compilations 0`, `Queues 0`, `Compilation Utilization 0.000000` and
`Compilation Accuracy`/`Queue Accuracy` both **`NaN`** (0/0), and by the
summarizer reporting `events=0 total-compiler-ms=0` with **`unparsed=0`**, so the
zero is not a parse failure in disguise. `tools/build/truffle-trace-summary.raku`
was not edited.

**THE FULL STAGE BREAKDOWN, which qualifies ruling 47's "83 % sits in parse".**
With no trace output to interleave, every stagestats line printed clean — no
marker collisions to work around, so these are read directly:

| stage | none | 1 thread | Δ | Δ % |
|---|---|---|---|---|
| `Stage parse` | 278.213 | 225.941 | **+52.272** | **+23.1 %** |
| `Stage optimize` | 33.406 | 23.680 | **+9.726** | **+41.1 %** |
| `Stage qast` | 21.751 | 21.169 | +0.582 | +2.7 % |
| `Stage unit` | 25.644 | 24.352 | +1.292 | +5.3 % |
| start/syntaxcheck/ast/jar | ~0 | ~0 | — | — |
| **stage sum** | **359.016** | 295.143 | **+63.873** | — |

Parse takes 82 % of the penalty while being 77 % of the run — over-represented,
but only mildly, so "the hot loops live in parse" is supported rather than
demonstrated. **`Stage optimize` is proportionally the worst-hit stage at +41 %,
three times parse's relative penalty**, and it rises monotonically across the
whole curve too (23.680 / 24.975 / 28.803 / 31.926 at 1/2/4/16 threads, 33.406 at
none). No task in this milestone has examined optimize; neither the thread story
nor the tier story currently explains it. Recorded as an open thread, not a claim.
**`Stage qast` and `Stage unit` are essentially unaffected** (+2.7 %, +5.3 %) and
are in fact FASTER here than in the 4- and 16-thread compiled runs (qast 21.751
against 25.920 and 25.988) — they were getting nothing from guest compilation and
were paying for it at high thread counts.

**CAVEAT THAT BOUNDS RULING 47'S HEADLINE: the host JIT was never off.**
`engine.Compilation=false` disables *Truffle* compilation of guest programs only.
HotSpot's own JVMCI/Graal compiler kept compiling the Java bytecode of the Truffle
interpreter throughout — the sampler counted 1-5 `jvmci`-named threads alive in
every sample. So "interpreted" in this run means *AST-interpreted by a fully
JIT-compiled Java interpreter*, not interpretation all the way down. This is
almost certainly why the penalty is 21 % rather than the predicted order of
magnitude, and it means ruling 47's "Truffle's entire JIT contribution is 17.5 %"
should be read as **the guest-compilation layer's contribution on top of a host
JIT that is already doing most of the work** — not as a statement about Truffle
versus interpretation in general. The ceiling ruling 47 sets on this milestone's
adoptions still holds; its causal reading needs that qualifier.

Implementer's own caveats: one replicate (the effect is ~100x the 0.2 % wall noise
floor, so direction is safe, the exact 63 s is one sample); the box was not idle
(HEAD moved from `ac4980f905` to `37c5e465c3` mid-run, ledger prose only, `git
diff --stat` one file +25 lines, no source change); `--stall`/`--max` were raised
to 1560 s because the watchdog keys on output silence and a run with no trace
output is silent for all of parse — the run finished in 360 s and never
approached either; output jar 5 865 111 bytes, inside the same +/-20-byte band as
all seven prior runs, so byte-identity is unavailable as a check and size band
plus `EXIT=0` is what can be claimed; `blib` untouched;
`NQP_CODE_MAX_COMPILE` unset before and after; `CompilerThreads` correctly not
set, since its floor of 1 cannot express zero.

**CORRECTION — the zero-point subagent did NOT fail.** It was still running. The
"completed" notification carrying a malformed monitor fragment was PREMATURE, and
I treated it as a failure, logged it as one, and collected the log myself. The
agent then finished properly with a full report (rakudo `4d9594b3fe`, ledger
append only) and handled the collision correctly, adding only what my collection
lacked and amending nothing. My earlier entry is wrong on the diagnosis and right
only on "the work survives". Cost: one duplicated log read and a false failure
record, now corrected here rather than by rewriting it.

Its screen adds a fact I did not have: **`engine.Compilation` defaults to `true`
and is EXPERIMENTAL stability** (unlike `CompilerThreads`, which is STABLE).
In force beyond what I checked: 0 `opt done`, 0 queued, 0 failed, 0 `id=` in an
86-line log; **0 TruffleCompiler threads in 30 of 30 `/proc` samples** — the pool
was never created; statistics printed with every counter 0, Utilization 0.000000,
both accuracy figures NaN.

**Ruling 49 — ruling 47's headline needs a QUALIFIER that changes what it means.**
I wrote that Truffle's entire JIT contribution is at most 17.5 %, and inferred
that my "interpretation is an order of magnitude worse" reasoning was simply
wrong about magnitude. The implementer found the actual reason, and it is not a
magnitude error but a **category error**:

**The host JIT was never off.** HotSpot kept compiling the interpreter's own
bytecode throughout — 1-5 JVMCI threads in every sample. So `Compilation=false`
does not mean "everything interpreted". It means **guest code runs in a Truffle
interpreter that is ITSELF JIT-compiled by HotSpot**. My order-of-magnitude
reasoning invoked a mechanism that never applied, because the interpreter is not
interpreted.

The corrected claim: **guest-level Truffle compilation, given a HotSpot-compiled
interpreter, is worth at most 63 s of 360 (17.5 %) on this workload** — barely
more than the 49 s that a 1-vs-16-thread misconfiguration throws away. The ceiling
stands; what it is a ceiling ON is narrower than I said.

**This strengthens the Native Image spike (Task 12) again.** If HotSpot's
compilation of the interpreter is doing this much of the work, an image that
precompiles that interpreter delivers the same benefit without warm-up. Recorded
there as a third reason, beside the two already in its brief.

Two observations from the report that nothing in this milestone explains, carried
to the findings doc and milestone 7:
- **`Stage optimize` is proportionally the worst-hit stage (+41 % with
  compilation off) and rises MONOTONICALLY across the entire thread curve.**
  Unexplained. It is also the second-largest stage.
- **`Stage qast` and `Stage unit` are untouched by guest compilation** — they were
  FASTER here than in the 4- and 16-thread runs. They gain nothing from it and pay
  for it at high thread counts, which is a clean small-scale instance of the
  whole curve's shape.

Operational note recorded: `--stall`/`--max` were raised to 1560 s because
watched-run's watchdog keys on output SILENCE, and this run is silent through all
of parse. It finished in 360 s and approached neither.

**Task 12 PULLED FORWARD to next (user, 2026-09-12), out of plan order.** It sat
at position 12 of 14, behind the cold-start profile, the green subset, the loop
bench and the adoption edits. The user asked whether nqp-j had been imaged yet;
it had not, and the plan's ordering is now wrong, because three findings from
this milestone all point at imaging and the third is hours old:

1. Cold start is ~4.1 s and dominated by the serial artifact load path — exactly
   what an image heap removes.
2. Guest-level Truffle compilation is worth **at most 17.5 %** on a real CORE.c
   compile (360 s with compilation off against 297 s at the best setting). The JIT
   this milestone spent its whole sweep tuning is a small prize.
3. **Ruling 49:** the reason that penalty is 21 % rather than an order of
   magnitude is that HotSpot never stopped compiling the INTERPRETER's own
   bytecode, 1-5 JVMCI threads throughout. The host JIT is doing much of the
   heavy lifting — and precompiling the interpreter is precisely what an image
   does, without warm-up.

We have spent the evening tuning guest compilation while host compilation was
quietly doing the heavier work. That is the ranking change.

Controller pre-verified so the spike does not spend time on it: `native-image` is
present at `/usr/lib/jvm/default/bin/native-image`, `java` is Oracle GraalVM
25.2.4, and **no image exists anywhere** in the tree or the job scratch — Task 12
had never been dispatched (briefs ran only to task 7).

Dispatched (opus) with: no-source-changes as a HARD constraint (a demanded source
change is a finding, not an edit, because rebuilding the runtime would invalidate
every measurement this milestone has taken); config files to scratch only; the two
questions the brief requires answered explicitly (which kind of image, and what
the auxiliary engine cache would actually hold given finding 2); a JVM baseline
measured first; and a ~90-minute working time-box inside the plan's four-hour
ceiling, on the grounds that "it would not build, and here is what it demanded" is
a valid close.

Tasks 8, 9, 10 and 11 are unaffected and still owed; none of them blocks this.

**Task 12 SCOPE EXTENDED mid-task (user, 2026-09-12): keep the image, and compile
CORE.c with it at `CompilerThreads=1`.** Two parts, sent to the running agent.
(a) The binary must NOT be deleted — it survives inside the job for part (b),
though the "no kept binary" rule still holds for the tree and anything durable.
(b) **The new headline measurement: CORE.c compiled by the native image with the
adopted tier policy and one compiler thread**, ranked ahead of the nqp startup
numbers.

**Why this is even possible, and why nobody has tested it.** CORE.c is Rakudo's
setting, compiled by `rakudo.jar`, and the spike images nqp alone. But since
unit-artifact milestone 4 **every unit jar is `unit.meta`-only with zero `.class`
files** — units are DATA (wire programs plus a serialized context), and runners
enter through `org.raku.nqp.runtime.unit.UnitMain <unit jar>`. So an image
containing the nqp RUNTIME, engine and language may load `rakudo.jar` as data at
run time and compile CORE.c without Rakudo having existed at image-build time.
**That is exactly what the artifact road was built for, and it has never been
tried.**

Baselines to beat, all measured tonight on the JVM with the same tier policy:
**297 s at 1 thread**, 337 s at the default 6, 360 s with compilation off.

**Controller expectation, registered before the result and genuinely uncertain in
BOTH directions.** The image removes HotSpot's warm-up of the interpreter, which
ruling 49 says is doing much of the heavy lifting. But AOT-compiled code is
typically slower at peak than fully-warmed JIT code, and a 300-second compile
gives HotSpot enormous time to warm. **The image could plausibly LOSE on a
workload this long while winning handsomely on short ones.** The agent was told
not to smooth the result toward either story.

If the image cannot run Rakudo at all, that is a first-class finding and was
demanded precisely — which class, reflection registration, resource, service
loader, FFM downcall or serialization-reader feature it refuses on. **That list is
the real measure of how far a full Rakudo image is, and we have never had it.**
The no-source-changes constraint is NOT relaxed for this; a demanded source change
remains a finding.

Time-box extended to ~2.5 hours of working time for the added scope.

**Ruling 50 — USER DECISION 2026-09-12: pin Truffle compiler threads to 1 for the
CORE setting compiles. ADOPTED and implemented.** The user's own reasoning for
wanting the AOT experiment, stated after the fact, is sharper than mine was: the
background compiler threads exist because the interpreter needs warming, so an
image removes the NEED rather than tuning it. The thread pin and the image attack
the same cost from opposite ends.

Implemented in `tools/templates/jvm/rakudo-j-build.in`, both platform branches:

    '-Dpolyglot.engine.Mode=latency',
    '-Dpolyglot.engine.FirstTierCompilationThreshold=1600',
    '-Dpolyglot.engine.CompilerThreads=1',

**The scope is exact, not approximate.** `J_RUN_RAKUDO` — which is this driver —
appears in the Makefile exactly three times: CORE.c (`:1312`), CORE.d (`:1331`)
and CORE.e (`:1350`). Nothing else uses it. So the pin covers the CORE settings
and nothing else. BOOTSTRAP goes through `J_NQP_RR` and is untouched, matching the
user's "at least to start, the CORE settings". And it is structurally impossible
for these to reach `rakudo-j`, which `create-jvm-runner.pl` generates separately —
ruling 30's gate is satisfied by construction rather than by discipline.

Not set, with reasons in the file: `MultiTier` (already default true, screened out
in Task 6) and `LastTierCompilationThreshold` (inert under latency because
`firstTierOnly` forces its gate false, confirmed in bytecode).

The template carries a comment block with the measurements, both mechanisms, and
the bounds — including that disabling guest compilation entirely costs 360 s, so
all of it is worth at most 17.5 % and the stock default captured about a third of
that. Anyone changing these later needs the ceiling, not just the wins.

**NOT regenerated.** The edit is inert until `Configure.pl` runs, and running it
now would rewrite the runners underneath the native-image spike currently using
the tree. The adoption takes effect on the next configure-and-build, which is
Task 14's post-rebase build at the latest.

**Task 12 — the Native Image spike. DONE 2026-09-12. It builds, it runs nqp,
and it runs RAKUDO.** Report: `task-12-report.md`.

The result nobody had tested: an image of the **nqp** runtime, built with no
knowledge of Rakudo's compiler, loads `rakudo.jar` at run time and compiles
Raku. The unit-artifact road from milestone 4 paid off exactly as designed —
`rakudo.jar` is three files (`unit.meta`, `unit.programs`,
`unit.serialized.lz4`) and nothing else, and an nqp image plus
`rakudo-runtime.jar` on the image class path executes it. `-e 'say(1)'` and
`@a.map(* * 2).join(",")` give correct output; the CORE.c compile started
correctly and reached `Stage start`, then was killed on time grounds (below).

**Four images, two of them working**, all kept in `$CLAUDE_JOB_DIR/tmp`:

| binary | built by | size | build wall | Truffle features | works |
|---|---|---|---|---|---|
| `nqp-image-opt` | `iterate-initbt.raku` | 67.6 MiB | 1 m 30 s | all 7 | YES, runs nqp |
| `rakudo-image` | `build-image-rakudo.sh` | 77.5 MiB | 1 m 27 s | all 7 | YES, runs Rakudo |
| `nqp-image` | `build-image-mod.sh` | 28.9 MiB | 42 s | none | no: "No language and polyglot implementation was found" |
| `nqp-image-empty` | `bi-empty.sh` | 19.7 MiB | 35 s | none | no: control, dies in `LZ4Factory` |

The 19.7 -> 28.9 -> 67.6 MiB progression is the whole spike: no metadata, then
metadata but Truffle on the MODULE path (no feature registers, no engine in the
binary), then Truffle on the CLASS path -- and the 39 MiB difference is the
Graal compiler compiled in.

**And the image loses on wall clock, consistently, by about 1.5x:**

| workload | JVM wall | image wall | JVM CPU | image CPU |
|---|---|---|---|---|
| `nqp -e 'say(1)'` | 1.93 s | 2.82 s | 9.8 s | 2.3 s |
| `rakudo -e 'say(1)'` | 3.66 s | 5.45 s | 22.8 s | 4.7 s |
| CORE.c | 297 s (whole compile) | **still in parse at 785 s, killed** | — | — |

Four to five times cheaper in CPU, half again slower on the clock. The JVM
wins because HotSpot spends five to six cores compiling the interpreter while
the interpreter runs; the image runs one thread of AOT code and cannot make
that back. Milestone finding 3 was right about the mechanism and the sign of
the effect is the opposite of what we hoped.

**The single most actionable finding: guest compilation FAILS 100 % in the
image, and one line of Kotlin is why.** `NFGString.atomsOf` consults a
`WeakHashMap` from inside `RxMatchRootNode.execute`, a partial-evaluation
root. Native Image's Truffle feature refuses that at build time
(`Found 1 compilation blocklist violations`); with the check suppressed the
compiler bails at run time on *every* root with
"Object of type FrameWithoutBoxing should not be materialized".
`CompilationStatistics` reports successes 0. A `@TruffleBoundary` or a PE-safe
grapheme cache separates "an image with a working optimising runtime" from
what was measured. The no-source-changes constraint held, so it stays a
finding.

**What the build demanded, in order** (full detail in the report): lz4 impl
classes registered reflectively; NO bare primitive-type entries in the agent
metadata (they make the builder resolve the platform-restricted
`CEntryPointLiteral.create` — this cost the most time and was bisected with a
per-entry probe driver); four Truffle/polyglot symbol holders at build-time
init; **Truffle jars on the image CLASS path, not the module path** (on the
module path no Truffle feature registers at all and the image dies with "No
language and polyglot implementation was found"); six language classes at
build-time init, found by an auto-iterating driver (blanket
`--initialize-at-build-time=org.raku.nqp.truffle` crashes the builder with an
internal NPE); `-Djava.class.path=` at run time so `UnitLoader` can find
`ModuleLoader.jar`; and for Rakudo, `rakudo-runtime.jar` on the class path,
the whole op surface registered (734 types — classlib ops are named as
strings, so resolution is open-world reflection), and the three JDK classes
the classlib road can name. That last set is closed and tiny: grepping both
trees for quoted JVM descriptors yields exactly eight classes, so a build step
could emit the metadata mechanically.

**Nothing demanded a source change to build or run.** The only source change
worth making is the `@TruffleBoundary`, and it changes the result rather than
the feasibility.

**Question 1 — which kind of image:** built WITH the optimising Truffle runtime
(`--macro:truffle-svm`, all seven Truffle features register, 67.6 MiB for nqp
vs 28.9 MiB without), but it BEHAVES as interpreter-only because every guest
compilation bails. So these numbers are the interpreter-only shape with 39 MiB
of dead Graal in the binary.

**Question 2 — the auxiliary engine cache:** on today's evidence it would hold
nothing (successes 0); once the boundary is fixed it would hold mostly
first-tier code, because `Mode=latency` rarely promotes on a compile-once
workload; and the whole prize is bounded by Task 7's 17.5 % ceiling regardless,
since a cache removes compilation time, not interpretation time. **It is no
longer a reason to pursue imaging.**

Build wall time, once the flags are known: **~90 s**. Options reach the image
as plain `-D` properties on its own command line, read at engine construction
at run time — verified, not assumed (`TraceCompilation` and
`CompilationStatistics` both took effect). `JDK_JAVA_OPTIONS`, which the JVM
drivers use, is ignored by an image.

The nqp suite was NOT run through the image: the harness invokes the generated
`nqp-j` shell script with a fixed `java` command line, and pointing it at a
binary with a different argument shape means writing a shim that impersonates
`nqp-j`. Said rather than contorted, per the brief.

**RECOMMENDATION: PARK.** Not drop — the structural result is permanent, the
recipe rebuilds in 90 s, and a one-line `@TruffleBoundary` stands between this
measurement and a real one. Not pursue — the image was still in CORE.c's parse
stage at 785 s against a 297 s whole compile, 2.8x the parse of the JVM run
with guest compilation disabled (the like-for-like comparison).

**The surprise, and the thing that should change how this direction is valued:
short workloads do NOT look different from long ones. The image loses on the
two-second workload too** (1.46x on nqp `say(1)`, 1.49x on Rakudo `say(1)`).
Finding 1's premise is half wrong: cold start is 1.9 s not because of JVM boot
(~0.1 s of it) but because artifact load, LZ4, meta decode and the setting's
load blocks are real work, and the image does all of it too, with unprofiled
AOT code on one core while the JVM throws five. An image removes CLASS loading,
not ARTIFACT loading. Putting loaded units in the image heap would remove the
rest, but that re-couples the image to one Rakudo build and is a different
project.

Revisit only if (a) the PE blocklist violation is fixed so guest compilation
works, and (b) somebody wants `raku -e` startup enough to try PGO — and then
measure the two-second case first, because it is the best case and today it
still loses.

Binaries, metadata and logs stay in `$CLAUDE_JOB_DIR/tmp` and are not
committed — every runtime change invalidates an image. `blib/` and
`nqp/build/` untouched; CORE.c output went to the job dir.

Task 12 (Native Image spike): implementer DONE_WITH_CONCERNS — rakudo
`28cc3ea11b`, nqp untouched. **Recommendation: PARK.** Four images built, two
working: `nqp-image-opt` 67.6 MiB in 90 s and `rakudo-image` 77.5 MiB in 87 s;
two dead ends (`nqp-image`, `nqp-image-empty`) where Truffle on the MODULE path
registers no feature. JVM baseline `nqp-j -e 'say(1)'` 1.93 s wall / 9.8 s CPU.

**Ruling 51 — THE ARTIFACT ROAD IS VALIDATED END TO END, and this is the spike's
durable result.** An image built from nqp alone **loaded `rakudo.jar` as DATA and
ran it correctly** — `unit.meta` + `unit.programs` + `unit.serialized.lz4`, zero
`.class` — with `say(1)` and `@a.map(* * 2).join(",")` both right. Rakudo did not
exist at image-build time and did not need to. That is precisely what
unit-artifact milestones 1-4 were built to make possible and nobody had ever
tested it. It stands regardless of the performance verdict.

**Ruling 52 — PARK, on numbers, not impressions.** Image startup is **2.82 s
against the JVM's 1.93 s, 1.46x SLOWER on the clock** (though 4.3x cheaper in CPU:
2.3 s against 9.8 s); Rakudo 5.45 s against 3.66 s. CORE.c through the image
reached `Stage start` correctly and was **still in parse at 785 s against 297 s
for the JVM's entire compile** — 2.8x the parse of the compilation-disabled JVM
run, which is the like-for-like comparison. Killed by the controller on the user's
instruction, not retried. Not DROPPED: the recipe rebuilds in 90 s and the
structural result is permanent.

**Ruling 53 — MY COLD-START PREMISE WAS HALF WRONG, and this milestone repeated
it several times.** I justified the imaging direction partly on "cold start is
~4.1 s and dominated by the serial artifact load path; an image heap removes
exactly that". **An image removes CLASS loading, not ARTIFACT loading.** JVM boot
is only ~0.1 s of the 1.9 s baseline. Our cold start is dominated by reading and
decoding unit artifacts, which an image does not touch at all. So finding 1 of
the three that justified pulling this task forward does not support it. Findings 2
and 3 (guest compilation worth at most 17.5 %; HotSpot carrying the interpreter)
stand, but 2 now cuts AGAINST imaging rather than for it — see ruling 54.

**Ruling 54 — the engine cache is no longer a reason to pursue imaging.** It would
hold **nothing today** (zero successful compilations), first-tier code at best
once the bailout below is fixed, and the entire prize is capped by the 17.5 %
ceiling. One of the three original reasons for this direction is therefore
retired.

**MILESTONE 7 LEVER #6, and it is the fourth instance of one pattern: guest
compilation fails 100 % in the image** because `NFGString.atomsOf` reads a
`WeakHashMap` from inside `RxMatchRootNode.execute`, illegal on a compiled path,
so every compilation bails and 39 MiB of Graal sits dead in the binary. **One
`@TruffleBoundary` fixes it**; the implementer correctly did not make the change,
holding the no-source-changes constraint. Note the pattern: this, the 442-root
inlining bailout, the `dieInternal` print branch and the deopt churn are all
**slow paths visible to the compiler** — the survey ruling 14 called for.

What the builds demanded, most blocking first, recorded as the real measure of how
far a full image is: Truffle jars on the CLASS path not the module path; no bare
primitive-type entries in agent metadata (they pull in platform-restricted
`CEntryPointLiteral.create`); 4 polyglot symbol holders and 6 language classes at
build-time init (blanket package init crashes the builder); lz4 impl classes;
`-Djava.class.path=` at run time for `ModuleLoader.jar`; `rakudo-runtime.jar` plus
a 734-type reflective op surface plus `java.lang.{Math,String,Object}`.

Open and honest: the implementer could not isolate why CORE.c was slower than the
1.5x short-run penalty predicts, naming absent PGO, serial GC and the suppressed
blocklist path as untested candidates. The nqp suite was NOT run because the
harness hardcodes a `java` command line — said rather than contorted, and now
dispatched to a separate agent with its own driver.

---

**Task 12b — the nqp suite through the Native Image. DONE 2026-09-12. The image's
runtime behaves like the JVM's.** Report:
`.superpowers/sdd/2026-09-12-jvm-milestone-6-compiler-workload/task-12b-nqp-suite-report.md`.

All 151 `testNqp` files, driven by stock `prove --exec` against a three-line shim
under the job tmp that impersonates `nqp-j-gradle` (the tree's harness was neither
read into the run nor modified). Invocation:

```
<image> -Xmx4g -Dnqp.execname=<self> -Djava.class.path=<share/lib> <share/lib>/nqp.jar <file>
```

`-Xss64m` was not needed: nothing overflowed the image's stack, qregex included.

**The nine known reds came back nine for nine, down to the individual test
numbers** — 021-contextual (2,5-6,9,32-33), 022-optional-args (7), 044-try-catch
(57), 112-continuations (15-16), qregex 21/845 (572-589,591,594,601), p5regex
(78,159-160), qast exits at test 10 of 184, jvm/01-continuations (16-17,19),
jvm/11-dispatch exits after 140 of 160. Nothing moved in either direction.
13144 tests, not one different answer.

**Three new red files, all missing metadata, none a wrong answer.**
`t/nqp/082-decode.t`: `UnsupportedCharsetException: windows-1252` — Native Image
ships only the default charsets; a build flag, and Rakudo would hit it too.
`t/nativecall/02-libc.t`: `MissingForeignRegistrationError: Cannot perform
downcall with leaf type (long,long,long)long`, thrown inside **buildnativecall**,
i.e. at symbol lookup, before any user function is called.
`t/nativecall/01-basic.t`: same cause wearing a `NullPointerException` at
`NativeCallOps.kt:116` (`call.argTypes!!`), because the test's `try`/`CATCH`
swallowed the real error; `NQP_VERBOSE_EXCEPTIONS=1` found it and a probe without
the `try` reproduces the identical FFM error.

**Which image, and the finding that came with it.** Only `rakudo-image` runs.
`nqp-image` cannot start ("No language and polyglot implementation was found" —
the module-path build). **`nqp-image-opt` dies during the first parse** on
`MissingReflectionRegistrationError: … org.raku.nqp.runtime.Ops.exception(ThreadContext)`
— `say(1+1)` is enough. Cause: its `config7` metadata registers `Ops` as an
*enumerated* method list (whatever the tracing agent saw), where `config-rakudo2`
registers 722 types with `allDeclaredMethods`. Classlib ops resolve by name at
run time, so **tracing-agent metadata is structurally insufficient and will
under-register silently, failing at a random op arbitrarily late.** The op
surface must be emitted whole by the build.

**Wall clock: 648 s against the 599 s baseline, +8 %, for 717 CPU-seconds against
roughly 3000.** The per-file penalty is worst on the smallest file and shrinks
with weight: `001-literals` 3.41 s vs 2.10 s (1.62x, and 3.4 CPU-s vs 12.4),
`qregex` 18.2 s vs 14.6 s (1.24x, 18.5 CPU-s vs 121). The image never wins, it
converges: the JVM buys its clock with 6-8 cores of JIT, the image runs one core
throughout. The coordinator's correction holds — an image removes class loading,
not artifact loading, and every one of the 151 processes paid full artifact load.

Guest compilation bailed 100 % throughout (the known `NFGString.atomsOf`
blocklist violation), so this is an interpreter-only runtime. That makes the
correctness result stronger — the whole suite ran the uncompiled path, where no
miscompile could hide or create a bug — and means the suite has **not** been run
through an image with a working optimising runtime. If the `@TruffleBoundary`
ever lands, repeat this run: a compiler is exactly where a divergence would
appear, and this run could not have seen one.

Trap for whoever repeats it: `grep -c '^not ok'` reports 60 for qregex, of which
39 are `# TODO`. Diff against the baseline's per-test numbers or invent
regressions.

No source change in either tree, no image rebuilt or deleted, no build script
touched. `blib/` and `nqp/build/` verified untouched; the nqp tree is clean and
rakudo shows only the untracked files that predate the task.

Task 12b (nqp suite through the image): COMPLETE — rakudo `78e2d2344f`, nqp
untouched, `blib/` and `nqp/build/` byte-identical, no image rebuilt or deleted.
Invocation: `<image> -Xmx4g -Dnqp.execname=<self> -Djava.class.path=<nqp>/build/jvm/share/lib <...>/share/lib/nqp.jar <file>`,
wrapped in a 3-line shim under the job tmp and driven by stock `prove -r --timer
--exec`; the tree harness was left untouched, as the previous agent's report
required. Only `rakudo-image` runs: `nqp-image` cannot start at all ("No language
and polyglot implementation was found") and **`nqp-image-opt` dies during the
first parse** on `MissingReflectionRegistrationError: Ops.exception(ThreadContext)`
— `say(1+1)` suffices, because its metadata registers `Ops` as an enumerated
method list while the Rakudo config registers 722 types `allDeclaredMethods`.

**Ruling 55 — the image's runtime is SEMANTICALLY IDENTICAL to the JVM's. This is
the strongest correctness statement the milestone has produced.** 151 files,
13144 tests, 139 passed, 12 red. **The nine known reds are nine for nine
identical down to individual test numbers** — 021-contextual (2, 5-6, 9, 32-33),
022-optional-args (7), 044-try-catch (57), 112-continuations (15-16), qregex
21/845 (572-589, 591, 594, 601), p5regex (78, 159-160), qast exiting at test 10 of
184, jvm/01-continuations (16-17, 19), jvm/11-dispatch exiting after 140 of 160.
**Nothing moved either way.** The 41 "missing" tests are exactly the three new
reds' unrun tests. Combined with ruling 51 (an image loading `rakudo.jar` as
data), the artifact road and the image runtime are both validated.

Three NEW reds, all metadata gaps at the runtime's edge, none semantic:
- `t/nqp/082-decode.t`: `UnsupportedCharsetException: windows-1252` — charsets not
  compiled in. A build flag, and **Rakudo would hit it too. This was on nobody's
  list.**
- `t/nativecall/02-libc.t`: `MissingForeignRegistrationError: Cannot perform
  downcall with leaf type (long,long,long)long`, thrown inside **`buildnativecall`
  — symbol lookup is ITSELF an FFM downcall**, so it fails before any user
  signature is reached.
- `t/nativecall/01-basic.t`: same cause disguised as `NullPointerException` at
  `NativeCallOps.kt:116`, swallowed by the test's own `try`/`CATCH`; a probe
  without the `try` reproduces the identical FFM error.

**Ruling 56 — the park verdict stands, but the trade is CPU for clock, not simply
"slower".** Suite wall **648 s against 599 s, +8 %**, for **717 CPU-seconds
against roughly 3000**. The per-file penalty is worst on small files and shrinks
with size (001-literals 3.41 s vs 2.10 s, 1.62x; qregex 18.2 s vs 14.6 s, 1.24x).
**The image never wins, it CONVERGES — the JVM buys its clock with 6-8 cores of
JIT.** Worth recording because on a loaded box, a shared CI runner, or anywhere
CPU is the scarce resource rather than wall time, that 4x arithmetic inverts. Not
a reason to unpark, but a reason the park is about THIS machine's idle cores.

**Ruling 57 — NativeCall is the real AOT blocker, and it is an OPEN set. This
largely answers Task 13's tabled question before Task 13 runs.** The user asked
(2026-09-11) whether a rule that a `native`-trait callable cannot have its
signature rewritten dynamically would give the closed set of descriptor shapes an
image needs. The evidence says such a rule would fix the wrong axis: **signatures
are built at run time from user `is native` declarations**, so for a Rakudo
DISTRIBUTION image the shape set is open no matter how immutable each individual
signature is. It would only close for an image of one specific Raku program, which
is Native Image's normal model but not what "ship rakudo-j as a binary" means.
`nqp::decode` with a named encoding is the same open-world problem. Task 13 should
start from this rather than re-derive it.

Carried concerns, two of which outlive the task:
- **The tracing agent that generates image metadata is STRUCTURALLY insufficient
  here**: classlib ops resolve BY NAME, so it under-registers silently and fails
  at an arbitrary op, arbitrarily late. Not a gap to fill but a method that cannot
  work for this codebase.
- **`try` hides missing-registration errors as nonsense NPEs**;
  `NQP_VERBOSE_EXCEPTIONS=1` should be the first triage step on any image.
- Guest compilation bailed 100 % throughout, so this is an interpreter-only
  correctness result — trustworthy as such, but **the suite has never run through
  an image with a working optimising runtime; repeat it if the `@TruffleBoundary`
  of milestone 7 lever #6 lands.**
- Methodological note worth keeping: `grep -c '^not ok'` gives 60 for qregex, 39
  of them `# TODO`. Diff against the baseline's per-test numbers or invent
  regressions.

**Ruling 58 — SUPERSEDES RULING 57. I mis-stated the user's proposal and repeated
a subagent's claim without checking it. The proposal is well-aimed.** The user
corrected me: their proposal was to REJECT ANY RUNTIME USE OF THE `native` TRAIT,
and signatures are built at compile time by the Rakudo compiler. Checked in the
code rather than argued:

- `lib/NativeCall.rakumod`'s `!setup` reads **`$routine.signature`** and derives
  `$arg_info` via `param_list_for($signature, ...)` and `$!rettype` via
  `map_return_type($returns)`. The signature is fixed when the routine is
  DECLARED.
- `NativeCallOps.kt`'s `descriptorFor(ret, args)` maps `ArgType` values — a
  **finite enum** — through `layoutFor` onto `ValueLayout`s, roughly seven
  carriers plus `ADDRESS` for pointer types, dying on anything else.

**So a descriptor shape is a pure function of a compile-time signature over a
small fixed alphabet.** What `!setup` does lazily is HANDLE CONSTRUCTION, not
shape determination. Ruling 57 said "signatures are built at run time"; that was
the subagent's phrasing about WHEN the handle is built, and I repeated it as
though it were about when the shape is decided. Wrong, and the second time this
milestone I have relayed an agent's claim without verifying it.

**What the proposal actually buys, stated properly:**
- **An image of a specific Raku program: the proposal CLOSES the set completely.**
  Every `is native` is in compiled source at image-build time, and the rule
  guarantees nothing can invent a shape afterwards. Register every derived
  descriptor at build time and NativeCall works.
- **An image of the Rakudo DISTRIBUTION: still open, but for a different reason
  than I gave — the image ships a COMPILER.** User source compiled inside the
  running image introduces declarations the image never saw. That is a property of
  distributing a compiler, not a flaw in the proposal, and the same is true of
  `nqp::decode` with a named encoding.
- **The proposal's real value is that it makes a covering-set or trampoline design
  SOUND.** Because the alphabet is small and every shape is statically derivable
  from a signature, a bounded pre-registered set (or a few universal descriptors
  with marshalling) can be proven to cover everything. Without the rule, a shape
  could in principle appear that no signature describes, and no covering argument
  would hold.

Task 13's job shrinks accordingly: confirm this against the trait-application
sites (`lib/NativeCall.rakumod:680-712`), decide covering-set versus trampolines,
and write the recommendation. It should NOT re-derive the question.

**Ruling 59 — EXTENDS 58 with the user's specification of the rule, and one
consequence runs OPPOSITE to what ruling 58 said.** The user specified the two
prohibitions: for any routine declared with the `native` trait, (i) **no adding
arguments to a signature at run time** and (ii) **no replacing the SIGNATURE OF A
ROUTINE at run time**.

**Ruling 58 understated this.** I wrote that an image of a specific Raku program
is closed because every `is native` is in compiled source at build time. **That is
only true if the signature captured at declaration is the signature forever.** If
a native routine's signature can gain an argument, or have its routine replaced,
then a program can demand a descriptor shape appearing NOWHERE in its own source,
and an image that registered shapes from source fails on it. **So the rule is not
a tightening of case (a); it is what makes case (a) provable at all.**

**Second consequence, which is a better mechanism than anything proposed so far:
the rule enables PRECOMPUTATION.** If a descriptor is fixed at declaration and
immutable thereafter, a module's descriptor set can be emitted when the module is
PRECOMPILED, and an image registers the union of everything installed. That is
staged and mechanical. It replaces registration-by-tracing, which Task 12b showed
to be **structurally unsound for this codebase** — classlib ops resolve by NAME,
so the tracing agent under-registers silently and dies at an arbitrary op,
arbitrarily late.

**A third vector the two prohibitions do NOT cover, needing its own decision:**
`EVAL` of source containing `is native` is not mutation, it is COMPILATION at run
time. It introduces a genuinely new declaration with a genuinely new shape inside
an already-imaged program — **case (b) reappearing inside case (a)**. Either such
declarations are refused under `EVAL`, or any image shipping the compiler needs a
COVERING set rather than an exact one. Not resolved here; named so Task 13 does
not miss it.

Hedge recorded on both sides: whether signature mutation is currently REACHABLE in
Rakudo is a separate question from whether the rule should forbid it. The rule is
sound either way and reachability is cheap to check at implementation time.

**Correction to ruling 59's transcription (user, 2026-09-12).** I wrote
prohibition (ii) as "no replacing the routine of a signature". The user's rule is
**"no replacing the SIGNATURE OF A ROUTINE"** -- the reverse, and the only one
that makes sense. The two vectors are therefore (i) mutating a `Signature` object
IN PLACE by adding parameters, and (ii) SWAPPING a different `Signature` onto the
same `Routine`. Together they state that **the signature bound at declaration is
the signature permanently**, which is exactly the property the descriptor argument
needs. Every consequence drawn in rulings 58 and 59 stands; only my wording of the
rule was wrong.

**Ruling 60 — "surgery to avoid NativeCall" is NOT NEEDED for an AOT rakudo-j
image, because an image without NativeCall ALREADY EXISTS and already runs Raku.**
The user, accepting that AOT is not the right option on the numbers, asked whether
the surgery to avoid NativeCall entirely could be done so that a rakudo-j image
could be tried. Checked before proposing any surgery:

**The CORE setting does not use NativeCall.** Its only three references are inert:
- `src/core.c/Exception.rakumod:1216-1219` — a trait-name-to-module STRING table
  (`cpp-const`, `cpp-ref`, `encoded`, `mangled` => 'NativeCall') for error messages.
- `src/core.c/traits.rakumod:189` — an error-message hint, "or did you forget to
  'use NativeCall'?".
- `src/core.c/VM.rakumod:90` — a config-key lookup, `self.config<nativecall.so>`,
  for library naming.
None of them performs a downcall or reaches FFM. NativeCall is a separate module
loaded only on `use NativeCall`, and only `t/04-nativecall` (30 files), 2 files in
`t/02-rakudo` and 1 in `t/packages` use it — 33 of roughly 450.

And the images BUILT with `NativeCallOps` present; Task 12b showed it fails only
at RUN time, when actually called. **So `rakudo-image` IS an AOT rakudo-j without
NativeCall.** It has already run `say(1)` and `@a.map(* * 2).join(",")` correctly
(ruling 51). Nothing was ever excised because nothing needed to be.

What was missing is not surgery but a CORRECTNESS measurement, exactly analogous
to Task 12b's for nqp. Dispatched: `t/01-sanity` (25 files, JVM baseline 25/25,
none using NativeCall) through `rakudo-image`, extending to `t/06-telemetry`,
`t/13-experimental` and `t/07-pod-to-text` if it goes well — which also serves the
green-subset measurement Task 9 still owes.

Carried into the dispatch so it is not rediscovered: `-Ilib` is mandatory (the
in-tree runners have no module repo, and its absence produces an
INDIRECT_NAME_LOOKUP cascade that looks like a real failure); guest compilation
bails 100 % so this is an interpreter-only correctness result and slowness is
expected, not news; and `try`/`CATCH` can swallow a missing-registration error and
re-surface it as a nonsense NPE, so `NQP_VERBOSE_EXCEPTIONS=1` is the first triage
step.

**Ruling 61 — USER DECISION 2026-09-12: the AOT direction is CLOSED. The 9-minute
CORE.c compile disproves its utility, and no further measurement is warranted.**
The correctness run dispatched under ruling 60 was stopped (TaskStop) before it
did any work. I had argued the correctness check had independent value; the user's
point outranks it, and the evidence is one-sided:

| workload | JVM | image |
|---|---|---|
| CORE.c compile | 297 s complete | **785 s and still in parse** |
| `nqp -e 'say(1)'` | 1.93 s | 2.82 s (1.46x) |
| `rakudo -e` | 3.66 s | 5.45 s |
| nqp suite, 151 files | 599 s | 648 s (+8 %) |

**It loses on every wall clock measured, at every workload size.** The single
favourable axis is CPU — 4.3x cheaper on startup, roughly 4x across the suite —
which matters only where CPU rather than wall time is the scarce resource, and
that is not what this project optimises. Continuing to validate a thing we will
not use is not a good use of the machine.

**What is BANKED and survives the closure**, none of it contingent on pursuing
imaging:
1. **The artifact road is validated end to end** (ruling 51): an image built from
   nqp alone loaded `rakudo.jar` as pure data and ran Raku. That is what
   unit-artifact milestones 1-4 were for and it had never been tested.
2. **The nqp runtime is semantically identical under a different execution model**
   (ruling 55): nine known reds, nine identical reds, down to test numbers.
3. **The FFI question is answered** (rulings 58, 59), with the user's rule
   specified and recorded in `native-image-aot-direction.md`.
4. **The recipe exists** and rebuilds in ~90 s, with the full list of what the
   build demands — the real measure of the distance, should anyone revisit.
5. **Milestone 7 lever #6**: guest compilation bails 100 % in an image on one
   `WeakHashMap` read inside a PE root; one `@TruffleBoundary`.
6. Two codebase findings that have nothing to do with imaging: charsets are not
   compiled in (Rakudo would hit it too, and it was on nobody's list), and
   `try`/`CATCH` masks missing-registration errors as nonsense NPEs.

Task 12 closes as PARK-then-CLOSED. Task 13 is largely discharged by rulings 58/59
and needs only its write-up into the findings doc. The four images stay in the job
scratch until the job is deleted; nothing durable depends on them.
