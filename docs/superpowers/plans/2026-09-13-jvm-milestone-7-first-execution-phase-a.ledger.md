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
| base | bc00863fef | c17d93d27 | 2.502 | 1.135 | 6815 | 125055 | 3204 | none | base |
| a1 | 76b62a0b4f | cb654e4bf | 2.518 | 1.125 | 6815 | 125055 | 3232 | none | struck (kept: harmless) |
| a2 | b5c559de25 | 793161369 | 2.509 | 1.085 | 6815 | 125055 | 3193 | none | diagnostics |
| a3 | ee460e4775 | 7602b2254 | 2.543 | 1.100 | 6815 | 125055 | 3209 | none | struck (kept) |
| a4 | e6a29ddc9e | 39688c263 | 2.496 | 1.116 | 6815 | 125055 | 3179 | none | struck (kept) |
| a5 | 7287e64a60 | 942ff0a5f | 2.516 | 1.145 | 6815 | 125055 | 3153 | none | struck (kept) |
| a7 | e965a90438 | f36509da7 | 2.611 | 1.151 | 6815 | 125055 | 3165 | none | struck (kept) |
| a7b | b3daa412c1 | 9f0417c5d | 2.604 | 1.165 | 6815 | 125055 | - | none | landed (marker true) |
| a8 | 56e78028bf | 4736905d0 | 2.597 | 1.148 | 6815 | 125055 | 3202 | t/02-rakudo/compose-added-method-precomp.t (stale .precomp, not the change - see ruling) | landed (compile shape) |
| a6 | 96f643b334 | 4736905d0 | 2.504 | 1.192 | 5661 | 100697 | 3735 | none | landed (counters); warm UNVERIFIED, re-taken as a6r |

## Rulings and deferred minors

Ruling (base row, new red): the base row's `new-red` names three files, so
by the plan's own rule they are pre-existing, not any lever's. In detail:

- `t/02-rakudo/99-misc.t` is **not** a failure — `Wstat: 0 Tests: 14
  Failed: 0`, listed by the harness only for `TODO passed: 6`. The rig's
  `parse-sweep` treats every `(Wstat` summary line as red, so this is a
  parser false positive. Left as is: it is constant across every row, so
  it cancels in a row-to-row comparison, and narrowing the regex would
  also drop the "no TAP / parse error" cases, which are real reds. Task
  2..9 compare their `new-red` against *this* set, not against the
  milestone-5 baseline alone.
- `t/02-rakudo/regex-interpolation-fold-length.t` (18/21 failed) and
  `t/02-rakudo/str-raku-prepend.t` (7/9 failed) are genuine reds in
  upstream tests that landed 2026-09-11 and 2026-09-10 (rakudo
  `00feb606ab`, `3feb5e7075`) — NFG case-folding and `.raku` grapheme
  escaping. Pre-existing engine gaps, out of milestone 7's scope.

Three files on the milestone-5 list are green at base — `15-gh_1202.t`,
`16-begin-time-eval.t`, `native-argument-snapshot.t` — which is why the
red count is 22 in both places. They stay listed (the 2026-09-12 flicker
ruling). Costs if wrong: a lever's regression in one of those three would
not be flagged as new red; the row's `red=` count still moves.

Ruling (rig, `Proc` exit codes): the first base run died after 54 minutes
without writing anything — Raku's `Proc` throws `X::Proc::Unsuccessful`
when the child's handle is closed, and the sweep exits non-zero whenever
any file is red, which is always. The rig now captures a child's output
before closing the handle and takes the exit code off the exception
(`capture`). Costs if wrong: nothing; the cold benchmarks still die on a
non-zero exit, as they must.

Deferred minor: the brief's rig source had three Raku bugs, fixed as
written — a missing `my` on `%*SUB-MAIN-OPTS`, `$*PROGRAM.parent(2)` for
the repo root (it is `parent(3)`; `parent(N)` goes N levels up), and
`"$tag-sweep.log"`, where `-` is an identifier character so the whole
`$tag-sweep` parsed as one variable.

Task 1 review (rakudo 5066de7070..325054757c): spec ❌ on one contract
point, quality "needs fixes": Important #1 the red parser counts a
TODO-passed file (`Failed: 0` + `  TODO passed:`) as red (origin: the
brief's regex); Important #2 the warm phase has no positive-marker check
and drops the sweep's exit code, so a sweep that never ran records "no
new red". ⚠️ items checked by the controller: both commits carry the
trailers and evening stamps (bc00863fef 2026-09-13 19:00, 325054757c
2026-09-13 22:00); `306 files in 3204s across 1 server(s)` is in
base-sweep.log.

Ruling (Important #1, plan-mandated origin): the spec's gate is "no red
outside the baseline file", so the parser is fixed (skip a `Failed: 0`
summary line followed by `  TODO passed:`) AND the two upstream tests
that were already red in the 2026-09-13 whole-t/ run
(`regex-interpolation-fold-length.t`, `str-raku-prepend.t`) join
`docs/jvm-t02-rakudo-red-baseline.txt` under a dated note; the base row's
new-red column is re-derived offline from base-sweep.log with
`--parse-sweep`, no re-run. Costs if wrong: a real regression in one of
those two files would hide behind the baseline (mitigated: their test
counts, 21 and 9, are in the sweep log, so a later count change is
visible).

Ruling (minor promoted): the `.t`-only file count for `--chunk` is a
latent violation of the never-replace-a-server rule if a `.rakutest`
lands in t/02-rakudo; it joins fix round 1 as `--chunk=*` (the sweep's own
one-chunk default), one line. Costs if wrong: nothing.

Task 1: minor (deferred): no unit test for `capture`; `--parse-sweep`'s
default baseline resolves against cwd, the measuring multi against
`$ROOT`; `new-red=` printed twice on the warm marker line (brief-inherited
shape); fixture header line does not match the sweep's real format;
assertion 8 is a negated `contains` (vacuous in RED).

Ruling (process): the implementer used a python3 heredoc once to splice
the ledger row (self-disclosed); nothing landed in the tree; the
tooling-in-Raku rule is restated in the fix dispatch. Costs if wrong:
nothing.

Task 1: fix round 1 — base row new-red re-derived offline: none.

Task 1: fix round 1/5 (4 findings dispatched: TODO-passed parser + fixture, two upstream reds into the baseline with the base row re-derived offline, warm marker + exit code, --chunk=*; commit 325054757c..76b62a0b4f; re-review pending)
Task 1: fix round 1/5 (4 addressed, 0 open; commits 325054757c..76b62a0b4f)
Task 1: minor (deferred): m7-rig.raku:9 header comment still says "chunk = file count" (now --chunk=*); jvm-t02-rakudo-red-baseline.txt:2 header says "22 files" while the file lists 24.
Task 1: complete (commits 5066de7070..76b62a0b4f, review clean after 1 fix round)

Ruling (row a1): cold rakudo-e 2.518 s (base 2.502, five-run spread
2.50-2.64), cold nqp-e 1.125 s (base 1.135, spread 1.13-1.19), warm
3232 s (base 3204), misses/hits bit-identical: every clock inside the
base row's own spread, so A1 is **struck (kept: harmless)** per the
plan's rule; it cannot regress and stays in. Costs if wrong: nothing.
The reader's rehash share was 17 % of the SC read, which is about 1.7 %
of the cold run: below the rig's resolution by construction. Recorded so
Phase B does not re-derive it.

Note (process): the Task 2 implementer made about 1860 tool calls in 62
minutes while waiting on the rig, against the "no more often than every
90 s" rule; later dispatches say so explicitly and name the Monitor
until-condition form.

Task 2 review (nqp c17d93d27..cb654e4bf, rakudo 76b62a0b4f..d7530adf3a):
spec ✅, quality approved; both named risks cleared on inspection
(stableIndex's three uses all follow checkAndDisectInput; VMHash
untouched). ⚠️ stamps/trailers checked by the controller: nqp cb654e4bf
2026-09-14 19:30, rakudo d7530adf3a 2026-09-14 19:45, both trailers.
Task 2: minor (deferred): `lateinit stableIndex` turns a hypothetical
pre-deserialize `forceSTable`/`peekAttributeShape` call into an
UninitializedPropertyAccessException (unreachable today; ruling: the
throw is the better failure mode, keep); only `initCodeRefList` has a
test, the two siblings do not; the rig's warm line prints `new-red=`
twice (already deferred under Task 1).
Task 2: complete (commits nqp c17d93d27..cb654e4bf + rakudo 76b62a0b4f..d7530adf3a, review clean; row a1 struck (kept: harmless))

Task 3: a2 misses histogram (cold rakudo-e best run):

      misses 4626 lang-meth-call
      misses 1947 lang-call
      misses 206 boot-syscall
      misses 35 raku-assign
      misses 1 raku-meth-call-qualified

The dispatcher list is five long, not eight: those five account for all
6815 misses. `lang-meth-call` alone is 68% of them -- the number A6 must
move.

Ruling (Task 3, root names): the cuid suffix never appears on a
jar-bound comp-mode block (`UnitRecord.cuid` is null there by design,
`ProgramUnit.kt:24`), so `<name>@<cuid>[<size>]` leaves every setting
root — the roots inherited item 7 is about — merged as before. The
plan's Step 5 is amended: `blockId` = the cuid when present, else
`<unitId>:<methodName>` (`sci.compUnit.unitId()` + `sci.methodName`,
"qb_N", unique within a unit), so every root is disambiguated. Goes
into Task 3's fix round. Costs if wrong: longer root names in traces;
the trace-summary regex anchors the size on the trailing `[N]`, so
nothing parses differently.

Task 3 review (nqp cb654e4bf..793161369, rakudo 8d2e795761..c74a25bb9a):
spec ✅ (one forced deviation: `nqp::shell` is an encoder bail, the test
spawns through `run-command` + /bin/sh, verified to set the env and read
stderr), quality approved; all four named risks cleared. ⚠️
stamps/trailers checked by the controller: nqp 793161369 20:15, rakudo
b5c559de25 20:30, c74a25bb9a 20:45 (2026-09-14), trailers on all three.
Ruling (minor promoted): `decont`'s new `else miss(site)` also fires for
a RakuObject whose `layout` is null (a deserialization stub before its
finish), spending a miss on a good site and pinning it after four; the
fix round tightens it to `o.layout != null && o.layout !== layout`
(a null layout falls to decontSlow with no miss, as before). Costs if
wrong: a stub-layout site that IS a real mismatch stays unpinned one
call longer.
Task 3: minor (deferred): `distinct-ids=` asserted by presence only;
`count`/`countBy` are boundary calls inside an already-boundary `miss`;
the decont layout-miss path has no test and did not fire at a2.

Task 3: fix round 1/5 (2 rulings dispatched: root-name fallback unit:qb_N, decont null-layout guard; nqp 793161369..f5be515e3; re-review pending)
Task 3: fix round 1/5 (2 addressed, 0 open; nqp 793161369..f5be515e3). Root names are now `<name>@<cuid>[N]` or `<name>@<unit-sha>:qb_N[N]`; trace summary parses them (distinct-ids=26 distinct-names=26 on a cold -e).
Task 3: minor (deferred): `NqpTypeOps.create` still misses unconditionally on a layout/REPRData mismatch (not the stub shape); trace summary reads no size from an OSR name (`[N]<OSR@...>`), pre-existing; `o.layout` read twice in decont (stat-only race).
Task 3: complete (commits nqp cb654e4bf..f5be515e3 + rakudo 8d2e795761..c74a25bb9a, review clean after 1 fix round; row a2 diagnostics: misses 4626 lang-meth-call / 1947 lang-call / 206 boot-syscall of 6815)

Task 4: a3 misses histogram (cold rakudo-e best run):

      misses 4626 lang-meth-call
      misses 1947 lang-call
      misses 206 boot-syscall

Ruling (row a3): cold rakudo-e 2.543 s (base spread 2.50-2.64), cold
nqp-e 1.100 s (a2 already read 1.085 on a diagnostics-only change, so
the sub-spread nqp reading is variance, not A3), warm 3209 s (base
3204), counters identical: **struck (kept)** — the callback road is
simpler than what it replaced and nothing regressed. Costs if wrong:
nothing. The sweep's `red=21` matches the base row as re-derived in
Task 1's fix round (the "22" in the base ruling text is history).

Task 4 review (nqp f5be515e3..7602b2254, rakudo ee460e4775..160dd68bf1):
spec ✅, quality approved; all three named risks cleared (catches are
invokeDirect's verbatim; enterUnit is call-for-call the bound handle's
road; the flag is written once and shared by clones). ⚠️ checked by the
controller: trailers + stamps on both commits (2026-09-14 21:30/21:45);
the nqp suite's 155th file is `t/nqp/125-dispatch-stats.t` from Task 3
(nqp 793161369), so the gate count is 155 from here on.
Task 4: minor (deferred): the flag test asserts slot 0 only and has no
negative case; `enterUnit` itself has no unit test (covered by the
suites on every miss).
Task 4: complete (commits nqp f5be515e3..7602b2254 + rakudo ee460e4775..160dd68bf1, review clean; row a3 struck (kept))

Task 5: a4 misses histogram (cold rakudo-e best run):

      misses 4626 lang-meth-call
      misses 1947 lang-call
      misses 206 boot-syscall

Ruling (row a4): cold rakudo-e 2.496 s, cold nqp-e 1.116 s, warm 3179 s
(base 2.502 / 1.135 / 3204; spreads 2.50-2.64 / 1.13-1.19), counters
identical: every clock improved by less than the spread, so **struck
(kept)**; the hunk is three lines and removes a switch on the hot path.
Costs if wrong: nothing. Four rows in (a1-a4), the cumulative warm
drift is 3204 -> 3179 s (-0.8 %), below the spread of one row; the
findings will report the four together, not one by one.

Note (process): the Task 5 implementer made about 1500 tool calls while
waiting on the rig despite the explicit 90 s rule in its dispatch; the
rule is restated with a concrete Monitor invocation from Task 6 on.

Task 5 review (nqp 7602b2254..39688c263, rakudo e6a29ddc9e..9c507020f9):
spec ✅ verbatim, quality approved; the equivalence (unitEntry ⟹
USE_BINDER by construction, the handle is enter(tc,cr,csd,null,args))
was verified from the sources. ⚠️ checked by the controller: trailers +
evening stamps on both commits.
Task 5: minor (deferred): widen `everyTableCodeRefIsAUnitEntry` to
loop the table and assert `unitEntry && argsExpectation == USE_BINDER`
for every entry (pins the shortcut's precondition; the same deferred
minor as Task 4, now with two consumers).
Task 5: complete (commits nqp 7602b2254..39688c263 + rakudo e6a29ddc9e..9c507020f9, review clean; row a4 struck (kept))

Task 6: a5 misses histogram (cold rakudo-e best run):

      misses 4626 lang-meth-call
      misses 1947 lang-call
      misses 206 boot-syscall

Ruling (row a5): cold rakudo-e 2.516 s, cold nqp-e 1.145 s, warm 3153 s
(base 2.502 / 1.135 / 3204), counters identical: no single clock beyond
the spread, **struck (kept)**. The warm clock's run of rows (3204, 3232,
3193, 3209, 3179, 3153) trends down 1.6 % across a2-a5, which no one
row can claim; the findings report the five runtime levers as one
cumulative delta, taken from the a6 row against base. Costs if wrong:
nothing.

Task 6 review (nqp 39688c263..942ff0a5f, rakudo 7287e64a60..ce851a2aae):
spec ✅ verbatim, quality approved; reset coverage of the new site fields
and the nested computeIfAbsent both verified against the whole site
population. ⚠️ checked by the controller: trailers + evening stamps on
both commits.
Task 6: minor (deferred): `DispatchCallSite.dispatcher`/`dispatcherEpoch`
are plain fields (a torn read pairs a fresh epoch with a stale
Dispatcher; bounded by pre-existing semantics since `register` runs at
load scope only) — `@Volatile` or an immutable pair if a language ever
registers mid-run; the identity-keyed inner helper map is unbounded for
a hypothetical per-call-descriptor caller (all callers pass singletons;
one KDoc sentence would warn); the `invokeMethodViaDispatch` prose
comment now sits above `HelperSite`; `dispatchWithDescriptor` still
`find`s per record (Dispatch.kt:193).
Task 6: complete (commits nqp 39688c263..942ff0a5f + rakudo 7287e64a60..ce851a2aae, review clean; row a5 struck (kept))

Task 7: a7 misses histogram (cold rakudo-e best run):

      misses 4626 lang-meth-call
      misses 1947 lang-call
      misses 206 boot-syscall

Task 7: boundary-check rakudo-j=true nqp-j-gradle=false

Ruling (Task 7, Step 1): `nqp-j-gradle` prints
`boundary-check: dieInternal TruffleBoundary=false (3 overloads)` while
`./rakudo-j` prints `true` — the runner puts the runtime jars on
`-Xbootclasspath/a`, so the boot loader loads `ExceptionHandling` without
being able to resolve `com.oracle.truffle.api.CompilerDirectives$TruffleBoundary`
and the annotation is silently dropped. Per the brief: runtime-tree
boundaries hold for `rakudo-j` only; moving the runner's runtime jars from
`-Xbootclasspath/a` to `-cp`
(`nqp/buildSrc/src/main/kotlin/GenerateRunnerTask.kt:153-155`) is a
follow-up task in this plan, re-measured by the nqp cold row only. The
nqp-truffle-tree boundaries of this task (`classlib`, `NFGString.of`) are
unaffected: nqp-truffle is on the module path under both runners. Costs
if wrong: the a7 cold nqp-e number carries no dieInternal boundary, so
the nqp clock under-reports this lever.

Task 7: promotion list: none (a7 not slower than a5)

Ruling (Task 7, Step 8 skipped): the trigger is cold rakudo-e above
2.64 s or warm above about 3210 s. a7 is 2.611 s and 3165 s — both inside
the base row's spread (cold 2.50-2.64, warm 3153-3232 across a1..a5), so
Step 8 did not run and no op was promoted. Nominally a7 is 0.095 s / 12 s
"slower" than a5, but a5 is itself the fastest warm row of the series and
the cold best-of-5 varies by 0.15 s run to run; the honest reading is
that the classlib boundary is **inside the noise on both clocks** — the
lever the spec expected to move the warm clock did not move it either
way. Costs if wrong: a real few-percent classlib regression is carried
forward unnoticed; `NQP_CLASSLIB_INLINE=1` restores the old road for a
one-command A/B whenever Phase B wants it.

Task 7: getattr/bindattr chain: not the prescribed cut — the
`attrHandleFailed` fix was written, measured and reverted; deferred to
Phase B.

Ruling (Task 7, Step 9): the chain IS reproduced on a cold `./rakudo-j -e
'say 1'`: three `PermanentBailoutException: Too deep inlining` roots, one
of them `mro@...:qb_187[204]`, whose inlined-method list is
`java.lang.Class.getSimpleName() [495]` under
`java.lang.invoke.Invokers.newWrongMethodTypeException(MethodType,
MethodType)` -> `MethodType.toString()` -> `NqpOps.getattr(...)` ->
`GetAttrOp.doGet` (2973 of the trace's 3277 lines are `getSimpleName`).
The brief's second branch (a `@TruffleBoundary static RuntimeException
attrHandleFailed(Throwable)` replacing both `catch (Throwable t) { throw
shouldNotReachHere(t); }` bodies at `:1503`/`:1539`) was implemented, the
jars rebuilt, and the trace re-taken: **bit-identical** — 3 bailouts,
2973 `getSimpleName` lines, before and after. It cannot work: the message
construction is inside `invokeExact`'s own wrong-method-type throw arm,
*upstream* of the catch, so a boundary on the catch body never sees it.
The change was reverted (the nqp tree is at `f36509da7`, no second
commit). Real diagnosis for Phase B: `getter`/`setter` is a phi merged
from `site.e1` and `site.e2`, so the handle is not a PE constant, so
`invokeExact`'s type guard does not fold and the JDK's exception path
stays in the graph. The fix is to make each entry's `invokeExact` see a
constant handle (split the two-entry road into two guarded call sites, or
bind through a `@Cached` node per entry) — a structural change, out of
Step 9's ten-minute bound. Costs if wrong: the 204-root bailout persists
into Phase B, where it is the same three roots to re-measure.

Ruling (row a7): cold rakudo-e 2.611 s (base spread 2.50-2.64, at its
high end), cold nqp-e 1.151 s, warm 3165 s (a5 3153, base 3204),
counters identical: inside the spread on every clock, so **struck
(kept)** — the classlib boundary matches the table road and the
targeted boundaries stand; no A/B run is taken (forward-only
directive). The high cold reading stays in the chain: if the a6 row
repeats it, the findings name the classlib boundary as the suspect and
Phase B's first rows decide. Costs if wrong: ~0.1 s of cold start
carried until then.

Ruling (Task 7, nqp runner): `NQP_BOUNDARY_CHECK` prints `false` under
`nqp-j-gradle` because its runtime jars are on `-Xbootclasspath/a`
(the boot loader cannot resolve the Truffle annotation type), and
`true` under `./rakudo-j` (`-cp`). Runtime-tree boundaries therefore
hold for every rakudo clock and NOT for the nqp cold row. Per the
plan's Step 1 text a follow-up task, Task 7b, moves the nqp runner's
runtime jars from `-Xbootclasspath/a` to `-cp`
(`nqp/buildSrc/src/main/kotlin/GenerateRunnerTask.kt`), verified by the
marker and measured by the cold nqp row only (`m7-rig --/warm`). It
runs after Task 8 and before Task 9. Costs if wrong: nqp cold start
could slow by app-loader class loading, which the row would show.

Ruling (Task 7, Step 9): the 204-root chain is reproduced on a cold -e
(3 "Too deep inlining" roots; `getSimpleName` x495 under
`newWrongMethodTypeException` under `NqpOps.getattr`); the catch-arm
boundary the plan offered was implemented, measured bit-identical and
reverted (the message construction is inside `invokeExact`, upstream of
the catch). Real cause: `getter` is a phi of `site.e1.getter` /
`site.e2.getter`, so the handle is not a PE constant and the exact-type
check cannot fold. The fix is structural (invoke each entry's handle on
its own branch so each call site sees one constant handle) and is
deferred to Phase B's inbox with this note. Costs if wrong: nothing
now.

Task 7 review (nqp 942ff0a5f..f36509da7, rakudo e965a90438..5361381aba):
spec ✅ verbatim (the classlib rename is +11/-0, provably
body-preserving), quality approved; all four named risks cleared against
the source and the built class (all three dieInternal overloads carry
the annotation in the jar). ⚠️ checked by the controller: trailers +
evening stamps on both commits.
Note for Phase B (from the review): `@TruffleBoundary` on `classlib`
(and on the table road's `run()`, unchanged) uses the default
`transferToInterpreterOnException = true`, so every exception leaving a
classlib op — NQP's control-flow categories included (`EX_CAT_NEXT`,
`LAST`, `RETURN`...) — deoptimizes the enclosing compiled root instead
of propagating inside compiled code. Behaviour-preserving, performance-
relevant, and a plausible reason the lever moved neither clock; the
`NQP_CLASSLIB_INLINE=1` knob is the A/B if Phase B measures it.
Task 7: minor (deferred): the `NFGString.of` boundary also hides the
`isEmpty` short-circuit and the interned-hit read (a miss-path-only
boundary would keep the hit path PE-visible); the marker uses `any`
where `all` would be unambiguous (verified all three in the jar).
Task 7: complete (commits nqp 942ff0a5f..f36509da7 + rakudo e965a90438..5361381aba, review clean; row a7 struck (kept); Task 7b ruled; getattr chain deferred to Phase B with its cause)

Task 8: A8 spike (no code; recommendation only). Runner `./rakudo-j -e 'say 1'`,
`RAKUDO_RAKUAST=1`, stock runner (no eval server), nqp `f36509da7` / rakudo
`114175eaa8`. Logs, all under `$CLAUDE_JOB_DIR/tmp/` (= `/home/longwalker/.claude/jobs/50ad8d62/tmp/`):
`a8-trace.log` (`NQP_CODE_TRACE=1`, 18415 lines), `a8-compile.log`
(`RAKUDO_JVM_XOPTS=-Dpolyglot.engine.TraceCompilation=true`, 3132 lines),
`a8-both.log` (both at once, 21547 lines — this is what gives the "entry N"
column, since trace lines and opt events interleave in one stderr), and
`a8-thresholds.log` (28 lines, the Step 4 threshold experiment; see (d)).
**Join key**: `cuid=` prints `?` for every jar-bound block, so the key used
throughout is `unit=<unit> + method=qb_N`, which is exactly the `@<unit>:qb_N[`
form the Task 3 root names carry (`<anon>@perl6:qb_4626[2838]`). Not the
brief's `@$c[` cuid form.

(a) Step 1 — which blocks are the dispatchers, and how often they run
(`grep dispatchers.nqp a8-trace.log | ... | sort | uniq -c`; 11130 dispatcher
entries of 18415 traced block entries; 45 distinct blocks, top 20 shown):

| entries | key (unit:qb_N) | file:line | dispatcher |
|--------:|-----------------|-----------|------------|
| 2546 | perl6:qb_4626 | src/vm/moar/dispatchers.nqp:3524 | `raku-invoke` |
| 2500 | perl6:qb_4604 | src/vm/moar/dispatchers.nqp:1466 | `raku-meth-call-resolved` initial dispatch |
| 2479 | perl6:qb_4597 | src/vm/moar/dispatchers.nqp:1126 | `raku-meth-call` |
| 1637 | 26A3F645…074C:qb_167 | NQP::src/core/dispatchers.nqp:273 | `nqp-call` |
| 1574 | 26A3F645…074C:qb_161 | NQP::src/core/dispatchers.nqp:5 | `nqp-meth-call` |
| 74 | perl6:qb_4617 | src/vm/moar/dispatchers.nqp:2982 | `raku-multi-core` initial dispatch |
| 74 | perl6:qb_4608 | src/vm/moar/dispatchers.nqp:1887 | `raku-multi` initial dispatch |
| 65 | perl6:qb_4595 | src/vm/moar/dispatchers.nqp:1041 | `raku-call` |
| 57 | perl6:qb_4561 | src/vm/moar/dispatchers.nqp:94 | `raku-rv-decont` |
| 35 | perl6:qb_4583 | src/vm/moar/dispatchers.nqp:657 | `raku-assign` |
| 34 | perl6:qb_4566 | src/vm/moar/dispatchers.nqp:227 | assign-scalar-no-whence-no-typecheck |
| 5 | perl6:qb_4619 | src/vm/moar/dispatchers.nqp:3164 | (raku-multi-core arm) |
| 5 | perl6:qb_4032 | src/vm/moar/dispatchers.nqp:2069 | (raku-multi arm) |
| 4 | perl6:qb_4027 | src/vm/moar/dispatchers.nqp:2057 | (raku-multi arm) |
| 4 | 26A3F645…074C:qb_162 | NQP::src/core/dispatchers.nqp:57 | `nqp-meth-call-mega-name` |
| 3 | perl6:qb_4046 | src/vm/moar/dispatchers.nqp:55 | (raku-rv-decont arm) |
| 3 | 26A3F645…074C:qb_168 | NQP::src/core/dispatchers.nqp:386 | `nqp-multi` initial dispatch |
| 2 | perl6:qb_4060 | src/vm/moar/dispatchers.nqp:3298 | (raku-invoke arm) |
| 2 | perl6:qb_4028 | src/vm/moar/dispatchers.nqp:2058 | (raku-multi arm) |
| 2 | perl6:qb_4026 | src/vm/moar/dispatchers.nqp:2052 | (raku-multi arm) |

Matches the spec Revision 2 estimate (top three ~1400 each; measured 2479-2546
after the six Phase-A levers). Everything below entry 74 is noise for this
question; the top five are 96% of all dispatcher entries.

(b) Step 2 — whether they ever compile during the cold run. The whole cold run
produces only **71 Truffle compilation events over 25 distinct ids**
(`truffle-trace-summary.raku`: done=40, failed=3, inval=10, deopt=18,
distinct-ids=25, unparsed=0); the 40 `opt done` events fall on **22 distinct
roots**. Per dispatcher root (opt events naming it in `a8-compile.log`; "first
compiled at traced entry N" from the interleaved `a8-both.log`):

| key | traced entries | done | failed | inval | deopt | first `opt done` at traced entry | reached compiled code? |
|-----|--------:|-----:|-------:|------:|------:|--------------------------:|------------------------|
| perl6:qb_4626 `raku-invoke` | 2546 | **0** | **1** | 0 | 0 | never (submitted at 609, bailed) | **NO — permanent bailout** |
| perl6:qb_4604 `raku-meth-call-resolved` | 2500 | 3 | 0 | **1** | 2 | 626 (25% in) | yes; inval@1010, deopt@1010/1292, recompiled 1134 / 1470 |
| perl6:qb_4597 `raku-meth-call` | 2479 | 4 | 0 | **1** | 3 | 548 (22% in) | yes; inval@1296, deopt@1296/1465/1952, recompiled 1459 / 1558 / 2266 |
| 26A3F645…074C:qb_167 `nqp-call` | 1637 | 2 | 0 | **1** | 1 | 660 (40% in) | yes; inval/deopt@778, recompiled 899 |
| 26A3F645…074C:qb_161 `nqp-meth-call` | 1574 | 2 | 0 | **1** | 1 | 660 (42% in) | yes; inval/deopt@777, recompiled 827 |
| perl6:qb_4062 `pass-decontainerized` (dispatchers.nqp:3799) | 1 | 1 | 0 | 0 | 0 | `a8-compile.log:3113` | yes — compiled despite 1 traced entry |
| the other 39 dispatcher blocks | ≤74 each | 0 | 0 | 0 | 0 | never | no — never submitted |

Correction, and it matters for how the percentages read: a *traced block entry*
(`NQP_CODE_TRACE`) is NOT the counter the first-tier threshold reads. Truffle
counts invocations plus loop back-edges, and OSR has its own counter, so a root
can cross 400 with one traced entry (`pass-decontainerized`, above) or run
thousands of traced entries without crossing it. "22-42% in" therefore means
"after 22-42% of that root's traced entries", a position in the cold run's
timeline — not "after N/400ths of the threshold". The earlier phrasing "never
reach the 400-entry threshold" for the tail was wrong on the mechanism as well
as falsified by `qb_4062`; the accurate statement is that 39 of the 45
dispatcher blocks were never submitted for compilation at all.

The `raku-invoke` failure is deterministic — identical in both independent runs,
same id, same size, submitted exactly once (a `PermanentBailout` is not
retried). Quoted from `a8-both.log:7584` (the interleaved run); `a8-compile.log:2091`
is the same event in the other run, differing only in `Time 109( 109+0 )ms`:

    [engine] opt failed engine=1 id=928 <anon>@perl6:qb_4626[2838] |Tier 1|Time 80( 80+0 )ms|
      Reason: jdk.graal.compiler.core.common.PermanentBailoutException:
              Too deep inlining, probably caused by recursive inlining.

So the honest answer to "do the dispatcher roots reach compiled code in a cold
run" is **four of the top five do, 22-42% of the way through their traced
entries; the single busiest one never does, and not for a threshold reason.**

(c) Step 3 — what the engine offers per root. There is no public per-root
"compile now" for a Bytecode DSL root; the levers are engine options. Present in
this GraalVM (`javap -cp nqp/build/jvm/share/truffle/truffle-runtime-25.2.4.jar
-p -c com.oracle.truffle.runtime.OptimizedRuntimeOptions`, defaults read out of
`<clinit>` — `javap -constants` does not print `OptionKey` defaults):

| option (`polyglot.engine.*`) | type | default |
|---|---|---|
| `FirstTierCompilationThreshold` | Integer | **400** |
| `FirstTierMinInvokeThreshold` | Integer | 1 |
| `FirstTierBackedgeCounts` | Boolean | true |
| `LastTierCompilationThreshold` | Integer | 10000 |
| `SingleTierCompilationThreshold` | Integer | 1000 |
| `MinInvokeThreshold` | Integer | 3 |
| `MultiTier` | Boolean | true |
| `Mode` | EngineMode | `DEFAULT` (`latency` / `throughput` also accepted) |
| `CompileImmediately` | Boolean | false |
| `CompileAOTOnCreate` | Boolean | false |
| `BackgroundCompilation` | Boolean | true |
| `Compilation` | Boolean | true |
| `CompilerThreads` | Integer | -1 (auto) |
| `DynamicCompilationThresholds` | Boolean | true |
| `MaximumCompilations` | Integer | 100 |
| `OSR` / `OSRCompilationThreshold` | Boolean / Integer | true / 100352 |
| `CompileOnly` | String | (unset) |

`./rakudo-j` sets none of these today (its only polyglot flag is
`engine.WarnVirtualThreadSupport=false`); milestone 6's tier policy was
build-side only. So every default above is what a cold Rakudo run actually gets.

(d) Recommendation — **shape 1, struck**: *four of the five hot dispatcher roots
reach compiled code 22-42% of the way through their traced entries, and lowering
the first-tier threshold cannot help — it costs +455 ms at 50 and +691 ms at 10
on the median cold run.*

Measurement, logged this time: `$CLAUDE_JOB_DIR/tmp/a8-thresholds.log`, 28 lines
of `round=<r> threshold=<base|150|50|10> ms=<n>`. 7 interleaved rounds; each
round runs base / 150 / 50 / 10 back to back so the box's drift hits all four
equally. Wall clock measured identically for all 28 runs: shell `date +%s%N`
immediately before and after the `./rakudo-j` invocation, `ms = (end-start)/1e6`
— process wall time including JVM startup, which is the cold clock in question.
Command per run: `RAKUDO_RAKUAST=1 RAKUDO_JVM_XOPTS="-Dpolyglot.engine.FirstTierCompilationThreshold=<N>"
./rakudo-j -e 'say 1'` (empty `RAKUDO_JVM_XOPTS` for `base`), stdout+stderr to
/dev/null. Raw 28 values (ms):

| round | base (400) | 150 | 50 | 10 |
|------:|-----------:|----:|---:|---:|
| 1 | 2466 | 2627 | 2882 | 3222 |
| 2 | 2531 | 2714 | 2986 | 3165 |
| 3 | 2394 | 2756 | 3171 | 3319 |
| 4 | 2498 | 2831 | 3058 | 3165 |
| 5 | 2650 | 2641 | 2917 | 3187 |
| 6 | 2533 | 2643 | 2941 | 3372 |
| 7 | 3638 | 3266 | 3788 | 3988 |

True medians (4th of 7 sorted) and deltas from the base median:

| `FirstTierCompilationThreshold` | median | vs base median | min of 7 | vs base min |
|---|---:|---:|---:|---:|
| 400 (default) | 2531 | — | 2394 | — |
| 150 | 2714 | +183 | 2627 | +233 |
| 50 | 2986 | +455 | 2882 | +488 |
| 10 | 3222 | +691 | 3165 | +771 |

What holds round by round, stated exactly:
* **50 is slower than base in all 7 rounds** (+416 +455 +777 +560 +267 +408 +150 ms).
* **10 is slower than base in all 7 rounds** (+756 +634 +925 +667 +537 +839 +350 ms).
* **10 is slower than 50 in all 7 rounds**, and **50 is slower than 150 in all 7 rounds**.
* 150 is slower than base in **5 of 7** rounds — round 5 it was 9 ms faster (inside
  the noise) and round 7 it was 372 ms faster, against a base run of 3638 ms that
  is the single outlier of the 28. 150 is not the claim the ruling rests on.

The claim that carries the ruling is the first two bullets: **every threshold
below the default is worse than the default in every round measured.** The
mechanism is that the cold run's bottleneck is compilation *capacity*, not
compilation *latency* — only 22 roots finish a compilation in the ~2.5 s a cold
run lasts, and submitting more roots earlier steals CPU from the interpreter that
is doing the actual work. `DynamicCompilationThresholds=false` alongside 50 was
worse again in a preliminary unlogged pass (3519-3761 ms); it is not part of the
logged experiment and is recorded only as a direction, not a number to quote.
**No Task 8b; no option goes into the runner defaults.**

Task 8: not a recommendation, a finding for the controller / Phase B inbox: the
busiest root in the whole cold run, `raku-invoke` (2546 traced entries, AST size
2838), is permanently un-compilable in this build ("Too deep inlining, probably
caused by recursive inlining"). It is the one dispatcher that provably runs 100%
interpreted, and no engine option addresses it — the lever would be structural
(shrink the root, or break the recursive inline), which is A-list Phase B work,
not an A8 runner flag. Recording it here so the A8 "struck" ruling is not read
as "the dispatchers are fine".

Task 8: complete (ledger only; no source file touched; row a8 struck, Task 8b
not ruled)

Task 8 review (rakudo 114175eaa8..72fa0d191b, ledger only): tables (a), (b)-entry-N and (c) reproduce exactly from the logs; spec ❌ on traceability: the Step 4 threshold table has no captured log, its "median of 7" is the 3rd of 7 in all four rows (true medians 3044/3280/3547/3874 -> deltas +236/+503/+830), "ordering holds in all 7 rounds" is false (5 of 7; the weaker true claim still carries the struck ruling), table (b) inval column all-zero against the log (4 roots have 1 inval each), the catch-all row is falsified by pass-decontainerized@perl6:qb_4062[373] (1 entry, compiled). Ruling: the struck verdict stands (50 and 10 are worse than base in every round); the numbers are corrected in a fix round with the threshold runs re-taken under a saved log. Fix round 1 dispatched.
Task 8: fix round 1/5 (5 findings dispatched; rakudo 72fa0d191b..4a6bd26cd2; re-review pending)
Task 8: fix round 1/5 (5 addressed, 0 open; rakudo 72fa0d191b..4a6bd26cd2). The medians quoted in the review line above (3044/3280/3547/3874) belong to the DISCARDED first dataset; the block's own numbers (2531/2714/2986/3222, +183/+455/+691) are current.
Task 8: minor (deferred): qb_161's second `opt done` is at traced entry 828, not 827; "single outlier of the 28" should read "of the base column" (round 7's 3788/3988 are larger).
Ruling (A8): struck — the dispatcher roots that matter compile after 22-42 % of their traced entries and a lower first-tier threshold costs +455 ms (50) / +691 ms (10) of cold start in every round; no Task 8b threshold change. The `raku-invoke` permanent bailout ("Too deep inlining", root perl6:qb_4626[2838], 2546 entries, never compiled) is the milestone's most concrete inherited-pattern finding and gets its own bounded task, 8b (brief in the workspace), before Task 9. Costs if wrong: 45 minutes.
Task 8: complete (commits rakudo 114175eaa8..4a6bd26cd2, ledger only, review clean after 1 fix round; A8 struck)
Task 7b: marker nqp-j-gradle=true; cold nqp-e 1.165 s vs a7 1.151 s (flat, inside the base spread 1.13-1.19; the row's warm cell is `-`, only the two cold rows were run). Gates: nqp suite 155 files in 191 s, chunk ok; t/01-sanity 25 files / 303 tests PASS. Collateral worth knowing: editing `nqp/buildSrc` invalidates gradle's whole nqp stage graph, so `generateRunner` rebuilt stage1/stage2 and every share/lib jar; the fresh serialization-context handles broke `./rakudo-j` ("Missing or wrong version of dependency '.../stage2/NQPHLL.nqp'") until a full rakudo `make` (797 s, EXIT=0) re-linked it. Rakudo's own hash is unchanged (b3daa412c1) but its artifacts are a new build, so a7b's cold rakudo-e 2.604 s is a rebuilt-artifact number, not a like-for-like delta against a7's 2.611 s.

Ruling (row a7b): the marker reads `true` under nqp-j-gradle; cold
nqp-e 1.165 s (a7 1.151, base spread 1.13-1.19): **landed** — the
change is correctness of the boundaries under every nqp runner, not a
clock. Costs if wrong: nothing measured.
Ruling (Task 7b side effect): editing `nqp/buildSrc` invalidated
gradle's stage graph, `generateRunner` rebuilt stage1/stage2 and every
share/lib jar, and the fresh SC handles required a full rakudo `make`
(797 s, green) before `./rakudo-j` ran. The tree is therefore freshly
built at a7b; a7b's cold rakudo-e (2.604 s) is a rebuilt-artifact
reading and the a6 row is the next like-for-like point. Task 9's own
`make` is now incremental on top of this one. Costs if wrong: nothing.
Task 7b: minor (deferred): `nqp/build.gradle.kts:232-241`, the
in-build stage JavaExec tasks, still put the runtime jars on
`-Xbootclasspath/a` (its comment now stale), so runtime-tree boundaries
stay invisible to the JVM that compiles nqp's own stages — compile-time
only; Phase B inbox.

Task 7b review (nqp f36509da7..9f0417c5d, rakudo b3daa412c1..569014921e):
spec ✅ verbatim, quality approved; all three generated runners verified
free of -Xbootclasspath with every former boot entry ahead of $CP;
trailers + evening stamps on both commits (verified by the reviewer).
Task 7b: minor (deferred): stale comments in GenerateRunnerTask.kt
(:26 "bootclasspath order", :31-37 the loader-split rationale, :74-75
the emitted comment) and the name `bootEntries`; `build.gradle.kts:236`
comment now false (the deferred in-build stage tasks).
Task 7b: complete (commits nqp f36509da7..9f0417c5d + rakudo b3daa412c1..569014921e, review clean; row a7b landed (marker true))

Task 8b: raku-invoke bailout. Runner `./rakudo-j -e 'say 1'`,
`RAKUDO_RAKUAST=1`, stock runner, nqp `9f0417c5d` / rakudo `157695f982`,
Oracle GraalVM 25.2.4. Logs under
`/home/longwalker/.claude/jobs/50ad8d62/tmp/`: `a8b-inlining.log`
(`TraceCompilation`+`TraceInlining`+`TraceCompilationDetails`, 3402 lines) and
`a8b-failure.log` (`TraceCompilation`+`CompilationFailureAction=Print`, 6282
lines). Step 1: TraceInlining prints **no** guest-level inlining tree for the
root — `a8b-inlining.log:1195/1196/1224` are the whole story (`opt start` at
Tier 1 with `Count/Thres 400/400`, then `opt failed ... Time 61(61+0)ms |
Reason: ... PermanentBailoutException: Too deep inlining, probably caused by
recursive inlining`) — so the second road was taken, exactly as the brief
anticipated: the chain is Java, not guest.

The frames, condensed from `a8b-failure.log:4205-5207` (the "Complete stack
trace of inlined methods" block printed under
`[engine] opt failed ... id=928 <anon>@perl6:qb_4626[2838]`, `:4188`). Three
things are condensed and nothing else: (i) the block's own first three lines
above the recursion are dropped (`:4206` `java.lang.ref.SoftReference.get`,
`:4207` `java.lang.Class.reflectionData`, `:4208`
`java.lang.Class.getSimpleName(Class.java:1669)` — the entry into it); (ii) the
`getSimpleName`/`getSimpleName0` pair then repeats to `:5196` (988 lines over
`:4205-5195`) and is elided to the bracketed `...` line; (iii) the trailing
`|UTC 2026-09-14T07:20:10.313|Src n/a` the log appends to the `profiledPERoot`
line is dropped. Lines `:5196-5207` are verbatim below the elision:

```
java.lang.Class.getSimpleName(Class.java:1672)
java.lang.Class.getSimpleName0(Class.java:1679)
    ... (the pair repeats; `getSimpleName() [495]` / `getSimpleName0() [494]`
        in the frequency list at :4190-4191)
java.lang.Class.getSimpleName(Class.java:1672)
java.lang.invoke.MethodType.toString(MethodType.java:936)
java.lang.String.valueOf(String.java:4530)
java.lang.invoke.Invokers.newWrongMethodTypeException(Invokers.java:522)
org.raku.nqp.truffle.NqpOps.getattr(NqpOps.java:1496)
org.raku.nqp.truffle.NqpRootNode$GetAttrOp.doGet(NqpRootNode.java:487)
org.raku.nqp.truffle.NqpRootNodeGen$CachedBytecodeNode.handleGetAttrOp_(NqpRootNodeGen.java:4856)
org.raku.nqp.truffle.NqpRootNodeGen$CachedBytecodeNode.continueAt(NqpRootNodeGen.java:3745)
org.raku.nqp.truffle.NqpRootNodeGen.continueAt(NqpRootNodeGen.java:996)
org.raku.nqp.truffle.NqpRootNodeGen.execute(NqpRootNodeGen.java:988)
com.oracle.truffle.runtime.OptimizedCallTarget.executeRootNode(OptimizedCallTarget.java:808)
com.oracle.truffle.runtime.OptimizedCallTarget.profiledPERoot(OptimizedCallTarget.java:722)
```

Step 2 — the cycle. The recursion is **entirely inside the JDK**:
`java.lang.Class.getSimpleName()` (`Class.java:1672`) calls
`java.lang.Class.getSimpleName0()` (`Class.java:1679`) which calls
`getSimpleName()` again — the array-component arm — and Graal's host inliner,
having no bound on it, throws the permanent bailout. **No `org.raku.nqp` method
recurses.** Six `org.raku` frames appear in the stack above, but exactly one of
them is on the **exception-construction path** — the frame directly under
`Invokers.newWrongMethodTypeException`, i.e. the method whose call into the JDK
drags the cycle into the graph — and it is the same one under every bailout in
the run: verified by
`grep -A1 'Invokers.newWrongMethodTypeException' a8b-failure.log | grep org.raku
| sort | uniq -c` → 6/6 occurrences are
`org.raku.nqp.truffle.NqpOps.getattr(...)` (3 failing roots x the two printings
each). The other five are the frames *below* it, which carry the cycle but
cannot cut it and are not annotatable cut points in any case:
`NqpRootNode$GetAttrOp.doGet` is a Truffle DSL `@Specialization` body and
`NqpRootNodeGen`'s `handleGetAttrOp_`/`continueAt`/`execute` are
processor-generated. The reachability from `raku-invoke`'s program is not a dispatch op at
all: it is the sited `nqp::getattr` in the dispatcher's body —
`GetAttrOp.doGet` (`nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java:485`,
confirmed by `grep -n 'doGet'`) calls
`NqpOps.getattr` (`.../NqpOps.java:1495`, confirmed by
`grep -n 'static Object getattr('`), whose only `invokeExact` is at
`NqpOps.java:1514`, `v = (SixModelObject) getter.invokeExact((SixModelObject) o);`
(`grep -n 'invokeExact'` → `:966`, `:1514`, `:1550`). The log itself attributes
the throw to `NqpOps.getattr(NqpOps.java:1496)` — the method's `instanceof`
line, not the call — so pinning it to `:1514` is an inference from the frame
plus the fact that `:1514` is `getattr`'s *only* `invokeExact` (`:1550` is
`bindattr`'s, `:966` another op's), not something the printed line number
states. `getter` is a local merged
from three assignments (`site.e1.getter`, `site.e2.getter`, `resolveAttr(...)`,
`:1500-1508`), so it is a phi, not a PE constant; a non-constant
`MethodHandle` forces `invokeExact`'s exact-type check into the graph, and its
throw arm builds the message — `newWrongMethodTypeException` ->
`MethodType.toString()` -> `Class.getSimpleName()` — which is the cycle. This
is **the same chain Task 7's Step 9 already named on `mro@...:qb_187[204]`**
(see the two Task 7 Step 9 rulings above), not a separate one: the A8 spike's
`raku-invoke` bailout and Task 7's 204-root bailout are one bug. All three
failing roots in this run share it: `<anon>@perl6:qb_4626[2838]` (raku-invoke),
`<anon>@perl6:qb_126[349]`, `mro@FD5A9459...:qb_187[204]`.

Ruling (Task 8b, Step 3): **3b — no source change.** The cycle's only cut point
inside our code is `NqpOps.getattr`, and `getattr` is the hot sited
attribute read itself (it is what the AttrSite cache exists to make a field
access after PE); a `@TruffleBoundary` there would trade one root's bailout for
an un-PE'd attribute read everywhere, which the controller's ruling puts on
this side of the fork. The one slow-path boundary that the chain does offer —
the `catch (Throwable t)` arm — was already implemented, measured
**bit-identical** and reverted by Task 7 Step 9, because the message
construction is upstream of the catch, inside `invokeExact`. No jar was rebuilt
and no rig row was taken for a8; nqp stays at `9f0417c5d`. What a fix would
take: a restructure of `NqpOps.getattr`/`bindattr` so each cache entry's handle
is invoked on its own branch (or through a per-entry `@Cached` node), giving
every `invokeExact` one constant `MethodHandle` so the exact-type check folds
and the JDK's exception path leaves the graph — the same structural fix Task 7
deferred, now with a second, bigger beneficiary attached to it (2546 traced
entries per cold run, 100 % interpreted). Costs if wrong: `raku-invoke`, the
busiest dispatcher root, keeps running interpreted for the whole cold process,
and Phase B inherits three bailing roots instead of one. Phase B inbox: this
restructure, ranked above the other getattr minors.

Task 8b review (rakudo 157695f982..7787c1c871, ledger only): spec ✅ (frames verbatim from a8b-failure.log, cycle named per method, 3b fork correct: the only cut in our code is the hot sited read), quality approved; one Important: the sentence "exactly one org.raku method anywhere in the chain" contradicts the six org.raku frames listed above it (the supported claim is one org.raku method on the exception-construction path). Fix round 1 dispatched. Ruling: Task 8c (brief in the workspace) implements the fix the block names — one constant handle per branch in getattr/bindattr — before Task 9. Costs if wrong: one implementer run and a rig row.
Task 8b: fix round 1/5 (3 findings dispatched; rakudo 7787c1c871..b4ff53d361; re-review pending)
Task 8b: fix round 1/5 (3 addressed, 0 open; rakudo 7787c1c871..b4ff53d361)
Task 8b: minor (deferred): the condensation parenthetical says "988 lines over :4205-5195" where the repeat region is :4209-5195 = 987 lines; the review record at the end of the ledger says "verbatim" of a block now labelled "condensed from" (a faithful record of the review as given).
Task 8b: complete (commits rakudo 157695f982..b4ff53d361, ledger only, review clean after 1 fix round; fork 3b; the fix is Task 8c)

Task 8c: before failed=3 (raku-invoke bailed) / after failed=0
(raku-invoke done at entry ~400). The three "Too deep inlining" roots of
the a8b block -- `<anon>@perl6:qb_4626[2838]` (raku-invoke),
`<anon>@perl6:qb_126[349]`, `mro@FD5A9459...:qb_187[204]` -- all compile
now: `grep -c 'Too deep inlining'` 3 -> 0, `opt failed` 3 -> 0,
`opt done .*perl6:qb_4626[` 0 -> 1 (Tier 1, 202 ms, IR 3463/8175,
CodeSize 41157), and a `TraceCompilationDetails` run puts the queue at
`Count/Thres 400/400`, so raku-invoke runs compiled for roughly the last
2100 of its 2546 cold entries instead of none of them. The fix is the
one the Task 8b block named: each cache entry invokes its own handle on
its own branch (`readSlot`/`writeSlot`, plain private statics so PE
inlines them with the branch's constant handle), no phi, so
invokeExact's exact-type check folds and the JDK's
`newWrongMethodTypeException` -> `MethodType.toString` ->
`Class.getSimpleName` cycle leaves every getattr/bindattr graph. The
brief's fallback (hand-inlining the two invokeExact calls) was not
needed. Inherited item 1 (the 204-root half) closes with it.

Task 8c: a8 misses histogram (cold rakudo-e best run):

      misses 4626 lang-meth-call
      misses 1947 lang-call
      misses 206 boot-syscall

Ruling (row a8, new red): the sweep's `new-red=1`
(`t/02-rakudo/compose-added-method-precomp.t`, "No plan found in TAP
output") is **not this change**. The failure is
`Missing or wrong version of dependency '.../nqp/build/jvm/stage2/NQPHLL.nqp'`
raised by the stale `t/02-rakudo/test-packages/.precomp` store written
by the Task 7b build (13 Sep 19:44/21:08), which any runtime-jar
rebuild invalidates. Verified by reverting `NqpOps.java` to HEAD~1,
rebuilding the jars and re-running: the test fails identically on the
pre-change jar; with `.precomp` removed it passes on the new jar
(2/2, harness PASS). A rig row taken right after a `syncRuntimeJars`
will show this class of red for any lever; clearing the test-packages
`.precomp` before the warm sweep would remove it. Costs if wrong: a red
attributed to the cache that was really the change -- excluded by the
revert run above.

Ruling (row a8): cold rakudo-e 2.597 s, cold nqp-e 1.148 s, warm 3202 s,
counters identical — every clock inside the spread; but the after-log
is the measurement that matters: failed=3 -> 0, `raku-invoke` compiled
at its 400th entry instead of interpreted for the process lifetime, and
the 204-root half of inherited item 1 (the getattr chain) is closed by
the same change. **Landed (compile shape).** Costs if wrong: nothing;
the clocks say it is at worst neutral.
Ruling (a8 new red): `t/02-rakudo/compose-added-method-precomp.t` went
red because `t/02-rakudo/test-packages/.precomp` was stale after the
jar rebuild (fails identically on the previous jar, passes 2/2 on the
new one once cleared) — the rig must clear that cache before the warm
sweep, since every lever rebuilds the jars. Task 9's implementer adds
one line to `m7-rig.raku`'s warm phase (rmtree of that directory) before
its own run; no fixture change. Costs if wrong: nothing.

Task 8c review (nqp 9f0417c5d..4736905d0, rakudo 56e78028bf..015417b972):
spec ✅ byte-identical to the brief; quality approved; every road's
behaviour preserved (the one dropped null-handle guard is provably
unreachable: layoutHandles returns null wholesale or two non-null
handles); all three log counts reproduce (before failed=3 / after 0;
raku-invoke, qb_126 and mro:qb_187 all compile). ⚠️ checked by the
controller: trailers + evening stamps on both commits.
Task 8c: minor (deferred): the helper doc comments name the handle
types as `(SixModelObject)Object` / `(SixModelObject,Object)void` where
the exact descriptors are `(SixModelObject)SixModelObject` /
`(SixModelObject,SixModelObject)void`; `readSlot` could take the
narrowed `RakuObject`; the null-read-falls-to-slow policy is in three
copies (deliberate) and wants a one-line comment; "compiled for roughly
the last 2100 entries" is an inference from the 400/400 queue line.
Task 8c: complete (commits nqp 9f0417c5d..4736905d0 + rakudo 56e78028bf..015417b972, review clean; row a8 landed (compile shape); inherited item 1's 204-root half CLOSED)

User decision (2026-09-14, during Task 9): **milestone 8 = an Assumption per STable** (the object model on Truffle: method cache / type check / container-spec test fold to constants in compiled code, invalidated on change), or at least a piece of milestone 8, after milestone 7 Phases B and C. Recorded in the plan doc and memory; no plan yet.

Ruling (Task 9, A6 as specified is STRUCK — false premise): the 2026-09-13
survey looked for `method clone` only under src/core.c; BOOTSTRAP.nqp
defines `Code.clone` (:3099) and `Block.clone` (:3165), which Routine/
Sub/Method inherit, so `findmethod($code-obj,'clone') =:= Mu's` is false
for every closure and the emitted road never fired (misses 4627, not
-1148). Had it fired, a REPR clone would have aliased `$!do` between
clones of one site. Replacement A6' (same spec intent, "fewer misses"):
`p6clonecode` mirrors `Block.clone`'s mandatory half natively — REPR
clone, clone of the `$!do` CodeRef, `setcodeobj`, rebind — and the three
optional tails are handled as: phasers hash and `$!why` are static
properties of the code object, checked by the COMPILER (the static road
is emitted only when the object has neither, and its `clone` resolves to
Block's or Code's, and it is not a regex); `@!compstuff` exists only
while a unit compiles, so the OP checks it at run time and takes the
method road (`findmethod` + `invokeDirect`) when it is non-null. Task 9
re-dispatched with this design; the make already taken (823 s, CORE.c
parse 215.4 s) is repeated once. Costs if wrong: a semantic slip in the
fast path shows in `begin-clone-wrap.t`, the phaser test, and the two
suites.

User decision (2026-09-14, during Task 9): the rig's per-lever row is
revised — warm proxy = t/01-sanity on one server (about 56 s),
t/02-rakudo per lever = a red-list GATE on three parallel servers
(about 20 min), the single-server t/02-rakudo CLOCK only at phase
closes (a6 stays full). Spec Task 0 amended; the rig change is Task 9b
(brief in the workspace), after Task 9, before Task 10. Costs if wrong:
a warm regression that only t/02-rakudo's clock would show is caught
at the phase close instead of per lever.

Task 9: a6 misses histogram (cold rakudo-e best run, run1 2.504 s;
a8's beside it): `3472 lang-meth-call` (a8 4626, **-1154**) /
`1947 lang-call` (a8 1947) / `206 boot-syscall` (a8 206). Total misses
5661 (a8 6815, the same -1154); hits 100697 (a8 125055), the method-road
clone's own dispatches going with it. Every setting closure that can take
the road does: the predicted drop was about 1148.

Task 9: CORE.c stagestats: parse 213.806 s / optimize 22.152 s /
qast 16.977 s / unit 22.619 s (the A6' make, 723 s,
$CLAUDE_JOB_DIR/tmp/a6p-make.log). The struck-A6 make earlier the same
day read 215.383 / 22.369 / 16.790 / 22.839, so the guard's three
tryfindmethods and two getattrs per closure site cost nothing measurable
on the compile side.

Ruling (row a6, after the power failure): the lever LANDED on the
evidence that matters — cold rakudo-e 2.504 s (a8 2.597), misses
6815 -> 5661 (-1154 lang-meth-call, the 1148 closure sites plus a few),
hits 125055 -> 100697 (the per-creation method road gone), gates green.
Its warm 3735 s (a8 3202) is UNVERIFIED, for two independent reasons:
the session's machine was on battery when it died and is on battery at
recovery (a laptop's firmware power limits cap sustained clocks
regardless of the `performance` governor), and this was the first sweep
after the rig's precomp-cache clear (1f4678a7b2), so 120 modules
re-precompiled inside it; the client CPU rose only 12 s while wall rose
531 s, the shape of a throttled machine. The single-server t/02-rakudo
clock is repeated ONCE on mains as row `a6r` before Phase A closes (an
invalidated measurement repeated, not a re-measurement for a different
answer); base..a8 warm numbers remain comparable among themselves, and
a6r starts the basis that includes the cache clear. Costs if wrong: one
55-minute sweep.

Task 9 review (rakudo fab6f87110..dab1c6caea, A6'): spec ✅ against the
ruled design (the op is a line-by-line match for Block.clone's mandatory
half, setcodeobj order verified, the guard istype-wrapped and timed
against the point existing consumers read `$!phasers`/`$!why`, regex
closures keep the method road); quality approved. ⚠️ checked by the
controller: trailers + evening stamps on all three commits (2026-09-14
18:15 / 22:30 / 22:45).
Task 9: minor (deferred): the rig's `rmtree` follows a symlinked
directory (`.d` is stat-based; `.d && !.l` closes it — folded into Task
9b); test 6 of closure-static-clone.t no longer pins non-aliasing of a
method-road Code clone; the twelve-line guard is duplicated at the two
closure sites; `signature.rakumod:1918` (a Code default value in a
signature) stays on the method road — recorded here as the brief asked.
Task 9: complete (commits rakudo fab6f87110..dab1c6caea, review clean; row a6 landed (counters); warm re-taken as a6r on mains)

User rule (2026-09-15, "stop measuring everything to such a low
granularity"): NO additional gating of any kind. The 2026-09-14 rig
revision is superseded: a lever's row = cold rakudo-e + cold nqp-e +
warm t/01-sanity; gates = nqp suite + t/01-sanity; no per-lever
t/02-rakudo clock or gate; row a6r is CANCELLED (a6's warm number stays
recorded as unverified and that is the end of it); the whole t/ clock
runs once at the milestone close. Task 9b's proxy mode drops the
t/02-rakudo gate. Recorded in the spec (Task 0) and memory
([[no-fine-grained-gating]]).

User rule amendment (2026-09-15): a failure to gather a benchmark does not mean run it again — a failed, cut-off or throttled run is recorded as not gathered with its reason, and the number is taken at the next point the plan already measures.

Task 9b: rig proxy mode landed (3e214b5a18): cold rows + t/01-sanity warm; no per-lever t/02-rakudo (user rule 2026-09-15); proxy-smoke sanity 51s (unplugged, not a row)
