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
`114175eaa8`. Logs: `$CLAUDE_JOB_DIR/tmp/a8-trace.log` (`NQP_CODE_TRACE=1`,
18415 lines), `a8-compile.log` (`RAKUDO_JVM_XOPTS=-Dpolyglot.engine.TraceCompilation=true`,
3132 lines), `a8-both.log` (both at once, 21547 lines — this is what gives the
"entry N" column, since trace lines and opt events interleave in one stderr).
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
produces only **71 Truffle compilation events over 25 distinct roots**
(`truffle-trace-summary.raku`: done=40, failed=3, inval=10, deopt=18,
distinct-ids=25, unparsed=0). Per dispatcher root (opt events naming it in
`a8-compile.log`; "first compiled at entry N" from the interleaved
`a8-both.log`):

| key | entries | done | failed | inval | deopt | first `opt done` at entry | reached compiled code? |
|-----|--------:|-----:|-------:|------:|------:|--------------------------:|------------------------|
| perl6:qb_4626 `raku-invoke` | 2546 | **0** | **1** | 0 | 0 | never (submitted at 609, bailed) | **NO — permanent bailout** |
| perl6:qb_4604 `raku-meth-call-resolved` | 2500 | 3 | 0 | 0 | 2 | 626 (25% in) | yes, then 1 inval + 2 deopt, recompiled at 1134 / 1470 |
| perl6:qb_4597 `raku-meth-call` | 2479 | 4 | 0 | 0 | 3 | 548 (22% in) | yes, then 1 inval + 3 deopt, recompiled at 1459 / 1558 / 2266 |
| 26A3F645…074C:qb_167 `nqp-call` | 1637 | 2 | 0 | 0 | 1 | 660 (40% in) | yes, 1 inval/deopt at 778, recompiled at 899 |
| 26A3F645…074C:qb_161 `nqp-meth-call` | 1574 | 2 | 0 | 0 | 1 | 660 (42% in) | yes, 1 inval/deopt at 777, recompiled at 827 |
| all 40 remaining dispatcher blocks | ≤74 each | 0 | 0 | 0 | 0 | never | no (never reach the 400-entry threshold) |

The `raku-invoke` failure is deterministic — identical in both independent
runs, same id, same size, submitted exactly once (a `PermanentBailout` is not
retried):

    [engine] opt failed engine=1 id=928 <anon>@perl6:qb_4626[2838] |Tier 1|Time 80( 80+0 )ms|
      Reason: jdk.graal.compiler.core.common.PermanentBailoutException:
              Too deep inlining, probably caused by recursive inlining.

So the honest answer to "do the dispatcher roots reach compiled code in a cold
run" is **four of the top five do, at 22-42% of the way through their entries;
the single busiest one never does, and not for a threshold reason.**

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

(d) Recommendation — **shape 1, struck**: *dispatcher roots compile within the
first ~550-660 entries (22-42% of their cold-run entries) and a lower first-tier
threshold cannot help at all — it costs 193-452 ms.* Measured directly, 7
interleaved rounds (each round runs base / 150 / 50 / 10 back to back, so the
box's upward drift hits all four equally), medians of 7 in ms:

| `FirstTierCompilationThreshold` | median | vs base | round-1 (least-loaded) | vs base |
|---|---:|---:|---:|---:|
| 400 (default) | 2653 | — | 2653 | — |
| 150 | 3177 | +524 | 2665 | +12 |
| 50 | 3479 | +826 | 2846 | +193 |
| 10 | 3739 | +1086 | 3105 | +452 |

The ordering base ≤ 150 < 50 < 10 holds in **all 7 rounds** — lowering the
threshold is monotonically worse, because the cold run's bottleneck is
compilation *capacity*, not compilation *latency*: only 40 roots finish
compiling in 2.5 s, and submitting more of them earlier steals CPU from the
interpreter that is doing the actual work. `DynamicCompilationThresholds=false`
alongside 50 was worse again (3519-3761 ms). **No Task 8b; no option goes into
the runner defaults.**

Task 8: not a recommendation, a finding for the controller / Phase B inbox: the
busiest root in the whole cold run, `raku-invoke` (2546 entries, AST size 2838),
is permanently un-compilable in this build ("Too deep inlining, probably caused
by recursive inlining"). It is the one dispatcher that provably runs 100%
interpreted, and no engine option addresses it — the lever would be structural
(shrink the root, or break the recursive inline), which is A-list Phase B work,
not an A8 runner flag. Recording it here so the A8 "struck" ruling is not read
as "the dispatchers are fine".

Task 8: complete (ledger only; no source file touched; row a8 struck, Task 8b
not ruled)
