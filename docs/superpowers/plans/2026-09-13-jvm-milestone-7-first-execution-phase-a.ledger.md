# SDD ledger — plan: docs/superpowers/plans/2026-09-13-jvm-milestone-7-first-execution-phase-a.md

Spec: `docs/superpowers/specs/2026-09-13-jvm-milestone-7-first-execution-design.md`
(rakudo `83375a77ae`). Plan committed rakudo `5066de7070`.

BASE before Task 1: rakudo `5066de7070`, nqp `c17d93d27`.

Model policy (user rule 2026-09-11): subagents on Opus; Fable only after
erroneous output.

Ruling: this committed ledger twin IS the ledger (milestones 4-6
convention); `.superpowers/sdd/<plan>/progress.md` mirrors completion
lines only. Rig rows are appended to the table below as they land, copied
from `$CLAUDE_JOB_DIR/tmp/m7-rig/rows.md`. Costs if wrong: nothing.

Ruling: the controller created this ledger before Task 1, so Task 1's
Step 1 (create the ledger) is already done; the implementer appends
its base row here instead. Costs if wrong: nothing.

Ruling: commit stamps are the evening (18:00-23:00) of the date the work
happened ([[after-hours-commit-stamps]]); the plan's example stamps are
defaults.

## Pre-flight scan

| Pair / task | Produces vs consumes | Finding |
|---|---|---|
| T1 -> T2..T9 | T1: `m7-rig.raku` rows + `rows.md`; every later task's measure step calls it with a new `--tag` | consistent |
| T1 -> T3 | T1's parser reads `  misses <n> <name>` lines that only exist after T3; before T3 the histogram is empty and `top:` prints nothing | consistent by design (the parser tolerates absence; the base and a1 rows have no histogram) |
| T3 -> T1 test | T1's fixture `m7-cold.err` carries the histogram lines T3 will produce, with T3's exact format `  misses <count> <name>` | consistent |
| T3 nqp test -> T3 code | `125-dispatch-stats.t` expects `slowLayout=` on the stats line and a `\n  misses ` line; T3 Step 3 prints both | consistent |
| T3 root names -> `truffle-trace-summary.raku` | names become `<name>@<cuid>[<size>]`; the tool's size regex anchors on `'[' \d+ ']' $` and the name capture is `.+?`, so `@cuid` lands inside the name | consistent; T3 Step 6 adds the `id=` capture |
| T3 root names -> T8 spike | T8 greps `@<cuid>[` in TraceCompilation logs | consistent (depends on T3 landing first; order holds) |
| T4 -> T5 | T4 produces `StaticCodeInfo.unitEntry` and `Ops.enterUnit`; T5 consumes `unitEntry` in `invokeDirect` | consistent |
| T4 Ops.kt -> T6 Ops.kt | T4 adds `enterUnit` after `invokeDirect`'s 2-arg overload (:2936); T6 rewrites the helper-site region (:2806-2931) | disjoint regions of one file; sequential tasks, no conflict |
| T4 Dispatch.kt -> T6 Dispatch.kt | T4 edits `invokeCallback` (:368-390); T6 edits `fallback` (:131-141) | disjoint |
| T2 test / T4 test -> `ProgramUnitTest` fixture | both copy or reuse `unit()`'s `UnitMeta`/`BlockRec` argument lists | consistent; T2's test carries its own copy and says to re-copy if the helper changed |
| T7 promotion -> T9 make | a promoted op is an encoder edit that needs `clean buildJvm` plus the Task 9 `make`; T7 Step 8 says it lands WITH Task 9's compile | consistent; if T7 promotes, T9's build step must run `./nqp/gradlew -p nqp clean buildJvm` first (ruling below) |
| T7 marker -> T7 boundaries | `NQP_BOUNDARY_CHECK` reflects `ExceptionHandling.declaredMethods`; `ExceptionHandling` is a Kotlin `object` with 3 `dieInternal` overloads (verified 2026-09-13) | consistent |
| T9 -> rig | T9 changes the compiler, so its rig row follows a `make`; the nqp jars are unchanged | consistent |
| T10 -> all | consumes the ledger's rows | consistent |
| T9 test | `closure-static-clone.t` is declared a regression guard that passes before the change; the rubric flags tests that never go red | plan-mandated and stated; ruling below |
| Global constraints vs T7 | decision 7 (compileOnly truffle-api) is already in the build; T7 adds no dependency | consistent |

Ruling (T7 -> T9): if Task 7 promotes any op (an encoder edit), Task 9's
build step runs `./nqp/gradlew -p nqp clean buildJvm` before `make`;
otherwise the plan's `make` alone. Costs if wrong: one extra nqp build
(about 5 min).

Ruling (T9 test): `t/02-rakudo/closure-static-clone.t` pins behaviour the
new road must preserve and is green before and after by design; that is
the test the spec asks for (semantics unchanged), not a defect. The
lang-meth-call miss count in the a6 rig row is the red/green for the
road itself. Costs if wrong: a semantic slip in p6clonecode caught only
by the suites, not by a targeted red.

## Rig rows

| tag | rakudo hash | nqp hash | cold rakudo-e (s) | cold nqp-e (s) | misses | hits | warm t/02-rakudo (s) | new red | verdict |
|---|---|---|---|---|---|---|---|---|---|

## Rulings and deferred minors

