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

