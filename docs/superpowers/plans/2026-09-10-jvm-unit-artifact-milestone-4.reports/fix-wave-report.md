# Milestone 4 final fix wave — report

**Status: DONE.** Every item on the brief is done, both Critical findings
are fixed at the cause with regression tests, and the two headline
regressions the milestone gate found are gone. One gate file is
unchanged and one nqp test is red; both are characterised below and
neither is this wave's doing.

Base: nqp `d24431b68`, rakudo `e9a5b9205a`. Both trees clean at the
start; both clean at the end.

---

## C1 — `is_inlinable` lost its table

**Changed.** `nqp/src/vm/jvm/QAST/Compiler.nqp`: a `%core_noninlinable`
table beside the inlinability tables, seeded with the twelve op names
that carried `:!inlinable` on their deleted `add_core_op` call, and
`is_inlinable($hll, $op)` now answers in order — HLL override;
`%core_inlinability` if the key exists; 0 if `%core_noninlinable`;
otherwise `QAST::TruffleEncoder.supports_op($op) ?? 1 !! 0`, the rule
`core_op_supported` already used. `src/vm/jvm/Raku/Ops.nqp` (rakudo):
five `set_hll_op_inlinability('Raku', ..., 0)` lines for `p6bindsig`,
`p6trybindsig`, `p6decontrv`, `p6decontrv_6c`, `p6return`.

**The twelve names were verified, not copied.** `git show
55bdee5b7:src/vm/jvm/QAST/Compiler.nqp | grep -n ':!inlinable'` gives 26
rows: twelve `add_core_op` (`call` :1731, `callstatic` :1732, `dispatch`
:1819, `syscall` :1822, `register` :1825, `delegate` :1828, `track`
:1831, `guard` :1834, `handle` :1891, `handlepayload` :2044,
`usecapture` :2275, `savecapture` :2285) and fourteen
`map_classlib_core_op`, which survive unchanged in the classlib rows.
The reviewer's list is exactly right — none missed, none invented. The
same check on the old `Raku/Ops.nqp` (`git show
670c3645b0:src/vm/jvm/Raku/Ops.nqp`) gives exactly five
`add_hll_op(:!inlinable)` rows, the five above.

**Why the Rakudo half is correctness, not speed.** All five are in
`TruffleEncoder`'s `$extra_ops`, so the new fallback would answer 1 for
them; an inlined `p6return` or signature binder acts on the inliner's
frame.

**Covering test.** `nqp/t/jvm/16-op-registry.t` (new, 17 assertions):
four ops on each side of the line, the HLL override and that it does not
leak across HLLs, and `supports-op` over `$extra_ops` hand rows plus one
name nothing has a row for.

**Commands and output.** Registry probe after the nqp clean build, before
the make:

    $ RAKUDO_RAKUAST=1 nqp/nqp-j-gradle -e '... is_inlinable("Raku", $_) ...'
    add_i 1  sub_i 1  mul_i 1  add_n 1  mul_n 1  if 1  while 1  list 1
    stmts 1  bind 1  callmethod 1  defor 1  ifnull 1  xor 1  for 1
    control 1  getlexouter 1  concat 1  elems 1

    call 0  callstatic 0  dispatch 0  syscall 0  register 0  delegate 0
    track 0  guard 0  handle 0  handlepayload 0  usecapture 0
    savecapture 0  ctx 0  ctxouter 0  curlexpad 0  curcode 0
    lexprimspec 0  nosuchop 0  p6box 0  p6invokehandler 0

After the make, the Rakudo side:

    $ RAKUDO_RAKUAST=1 ./rakudo-j -e 'use nqp; ... is_inlinable("Raku", $_) ...'
    p6return 0  p6bindsig 0  p6trybindsig 0  p6decontrv 0
    p6decontrv_6c 0  p6capturelex 0  add_i 1  callmethod 1

    $ RAKUDO_RAKUAST=1 nqp/nqp-j-gradle t/jvm/16-op-registry.t
    1..17 … ok 17 - supports-op says no to an op nothing has a row for

Note `p6box` and `p6invokehandler` answer 0 where the old default
answered 1. Neither has an encoder row or a classlib mapping, so the
encoder cannot compile them anyway; refusing to inline an op the backend
would refuse is the right answer.

**The four red files this was supposed to fix:** `t/08-performance/22`,
`29` and `32` are **green**. `t/02-rakudo/native-return-coercion.t` is
**unchanged at 19/23** — see "Still open".

---

## C2 — `("aa".."ac")` hangs

**Fixed, and the review's localisation was wrong.** It is not CORE.c's
build of `SEQUENCE`, not the driver, not the encoder, and not Tasks 8/9.
It is `CallFrame`.

### Experiment 1 — the dump/diff (no build)

A jshell driver over `nqp-runtime.jar` reading `UnitZip.read(bytes)`,
walking the block tree from `SEQUENCE`'s qbid and printing each
`BlockRec` plus its program.

CORE.c (`blib/CORE.c.setting.jar`, unit `2591662D…`, 19861 blocks) and
the reviewer's working precompiled module copy (`MySeq`, 83 blocks). The
gather block — the one that owns the `until $stop` loop — is qbid 8089
in CORE.c and qbid 61 in `MySeq`:

    CORE.c: name='' outer=8104 cuid=null thunk=false exitH=false
            oLex=[$_, lefti, &producer, @tail, @end_tail, value]
            iLex=[$stop, $looped] nLex=[] sLex=[]
            handlers=[2, 4, 470, 0, 16, 1, 4, 471, 470, 12, 1]
            progLen=2907  slv[&producer/1] slv[@tail/1] slv[@end_tail/1]

    MySeq:  name='' outer=76  cuid=null thunk=false exitH=false
            oLex=[$_, lefti, &producer, @tail, @end_tail, value]
            iLex=[$stop, $looped] nLex=[] sLex=[]
            handlers=[2, 4, 1, 0, 16, 1, 4, 2, 1, 12, 1]
            progLen=2927  slv[&producer/1] slv[@tail/1] slv[@end_tail/1]

Identical field for field; only the global handler ids differ. The
programs are **879 wire words each**, differing at exactly **44 operand
positions** — every one a string-table index, an SC handle index, a
handler id or a nested qbid, and **not one opcode**. The `until $stop`
header is `W_LOOPH(20) is_until=1 repeat=0 has_next=0 has_label=0
lbl_local=0 condt=1 lid nrid outer=0` in both.

So by the review's own decision tree the driver and the encoder are both
eliminated: same program, same record, different outcome.

### Experiment 2 — after the C1 make (free)

    $ timeout 90 RAKUDO_RAKUAST=1 ./rakudo-j -e 'say ("aa".."ac").elems'
    rc=124

Still hangs. Not a CORE.c-only consequence of C1.

### Experiment 3 — the runtime bisection

Runtime and truffle sources checked out at nqp `14df06863` (pre-Task 8),
jars rebuilt, reproducer re-run: **rc 124, identical**. Tasks 8 and 9 —
and therefore I1 — are exonerated. (Sources restored and the wave jars
rebuilt and verified immediately afterwards.)

### Experiment 4 — what actually reproduces it

Hand-written reductions of the shape all terminate correctly: nested
gathers; a `for` loop in a gather consuming another gather; an `until
$stop` inner consumed from a `for` loop; arity-2 `for`; `[X~]` cross
products; a native `int` stop flag; the setting's own `("a" ... "c")`
consumed inside a hand-written gather; and a self-recursive hand-written
gather. (One early "reproduction" was a bug in my probe — `inner("a","a")`
whose producer is `succ` never reaches its endpoint. Caught and discarded.)

What does reproduce it: **the real `SEQUENCE` body, compiled as an
ordinary module, with its inner sequence made to call ITSELF.**

    # MySeqRec.rakumod = SEQUENCE.rakumod with
    #   @ranges.push: $($from ... $to);
    # replaced by
    #   @ranges.push: $(Seq.new(MYSEQ($from, $to)));
    $ RAKUDO_RAKUAST=1 ./rakudo-j -I/tmp/claude-1000/m4rec run-rec.raku
    (aa ab ac ac ac ac)

That is the reported symptom exactly. It also explains why the
reviewer's copy passed: its inner `...` reached the **setting's**
`SEQUENCE`, a different routine, so no static frame ever had two live
invocations. A Scalar `$stop` instead of the native `int` behaves the
same, so the native lexical is not the mechanism either.

### Cause

`CallFrame`'s continuation save road called `leave()`. `leave()` gives
the frame's live-invocation count back and points the static frame's
`priorInvocation` at the frame being packed away. With
`liveInvocations` back at 0, `outerFor` skips the caller-chain search
and answers `priorInvocation` — so a **second invocation of the same
static frame, running while the first is suspended**, resolves its
blocks' outer to the suspended one. `SEQUENCE` creates exactly that:
its multi-character branch builds each character position's range with
the sequence operator, which is `SEQUENCE`. The inner gather's `$stop =
1` landed in the outer invocation's lexicals, its `until $stop` never
saw it, and the producer repeated its last value forever.

Invisible while a static frame has one invocation at a time; wrong the
moment it has two.

### Fix

`leaveSuspended()` now does the one thing a save owes — restore
`tc.curFrame`. The real exit (`leave()` on the resume road,
`leaveTorn()` when the unwinder tears the frame past) still gives the
count back exactly once and still sets `priorInvocation`, because by
then it is true.

### Covering tests

    $ RAKUDO_RAKUAST=1 ./rakudo-j -e 'say ("aa".."ac").elems'          # 3
    $ RAKUDO_RAKUAST=1 ./rakudo-j -e 'say ("aa" ... "ac").List'        # (aa ab ac)
    $ RAKUDO_RAKUAST=1 ./rakudo-j -e 'say ("zzz00".."zzz20").elems'    # 3
    $ RAKUDO_RAKUAST=1 ./rakudo-j -Ilib t/02-rakudo/nested-invocation-continuation.t
    1..6 … ok 6 - a gather that calls its own routine while suspended keeps its own lexicals
    $ … t/02-rakudo/sort-element-kinds.t                               # EXIT=0

`t/02-rakudo/nested-invocation-continuation.t` is new: the four range
forms, the single-character control, and the shape on its own (one
routine whose gather body calls itself while suspended at a `take`).

---

## I1 — exit handlers of continuation-captured frames

**Changed.** `CallFrame` splits the two one-shots that `left` was doing
at once: `left` is the live-invocation count, `exitHandlerRun` is the
exit handler. `leaveSuspended()` is the save road. `leaveThrough(ce)`
names the rule the sites that leave a frame on a control throw share —
a `SaveStackException` is a save, anything else is an exit — and is used
at `ProgramEntry.enter`, `NqpDispatch.enterEngine`,
`NqpDispatch.enterDirect` and `NqpCodeEngine.resumeEngine`;
`leaveSuspended()` directly at `resumeEngine`'s two re-suspend sites.

**A correction to the review.** The review named only
`NqpCodeEngine.java:205-207, 215, 227, 241` as the save road. That is
incomplete: `SaveStackException extends ControlException`, so the
**first** capture through a frame leaves it via the `catch
(ControlException)` arms in `NqpDispatch` and `ProgramEntry`, not
through `resumeEngine` at all. Fixing only `resumeEngine` changed
nothing — measured, not assumed:

    before: t1 LEAVE t2 end [1 2]      # handler at the first take
    after the resumeEngine-only fix: t1 LEAVE t2 end [1 2]   # unchanged
    after leaveThrough at all four sites: t1 t2 end LEAVE [1 2]

**Covering tests.**

    $ RAKUDO_RAKUAST=1 ./rakudo-j -e 'my @a = gather { LEAVE say "done"; take 1; take 2 }; say @a'
    done
    [1 2]
    $ … -e 'my @a = gather { LEAVE say "LEAVE"; say "t1"; take 1; say "t2"; take 2; say "end" }; say @a'
    t1 / t2 / end / LEAVE / [1 2]
    $ … t/spec/S04-phasers/keep-undo.t          # 16/16
    $ … t/spec/S04-phasers/enter-leave.t        # 10/10 then dies at line 89
    $ … nqp/t/jvm/01-continuations.t            # 22/22
    $ … nqp/t/nqp/112-continuations.t           # 26/26

`enter-leave.t`'s death is at its `#?rakudo skip 'leave NYI RT #124960'`
line (89), i.e. an artefact of running the file unfudged; the ten tests
before it pass.

---

## I2 — `UnitLoader.load` marks a unit loaded before the load succeeds

**Changed.** `UnitLoader.kt`: the name still goes into `loadedUnits`
before the load (a load block that loads itself must not recurse) and is
taken back out in a `finally` if the load did not complete, keyed by the
name as given, before the `ModuleLoader.class` rewrite. Covered by the
whole build and both suites exercising `nqp::loadbytecode` on every unit.

---

## I3 — `$extra_ops`' three roles

**Changed.** `TruffleEncoder.nqp:38-62`: one comment naming all three
consumers — the coverage survey, `supports_op`/the backend's
`supports-op`, and `is_inlinable`'s last resort — and what a missing
name costs in each; and a second at `supports_op` naming its two
callers. No behaviour change. Pinned by `nqp/t/jvm/16-op-registry.t`.

---

## I5 — the param-default regression test

`t/02-rakudo/begin-time-attributive-param-method.t`: `plan 5` → `plan
6`, plus the default-holding-a-code-object case Task 10's fix also
covered.

    $ RAKUDO_RAKUAST=1 ./rakudo-j -Ilib t/02-rakudo/begin-time-attributive-param-method.t
    1..6 … ok 5 - a BEGIN-time parameter default holding a code object calls that code

---

## Wave-riding comment and dead-code items

- `Compiler.nqp`: `$RT_VOID`, `@typeobjs`/`typeobj_from_rttype`,
  `@typechars`/`typechar` deleted (each had exactly one reader, its own
  definition); `unit(... *%adverbs)` slurpy dropped (its one caller,
  `HLL/Backend.nqp:58`, passes only `:$unit_id`).
- `Raku/Ops.nqp`: `$EX_CAT_NEXT/REDO/LAST`, `$RT_VOID`, `$RT_UINT`
  deleted.
- Stale names retired: `TruffleEncoder.nqp:1946` and `:2166`
  (`add_core_op`), `:428-433` (the stage0 `NQP_CODE_RUN`-presence
  paragraph, which contradicted AGENTS.md), `:1184-1198` (rewritten to
  name the prologue's deferred code-ref slots and to put cause before
  effect); `RxDescriptor.nqp:211` (`engine_jast`) and `:759`
  (`as_jast(QAST::Var)`); `ProgramEntry.kt:17`; `NqpCursor.kt:67`;
  `NqpLanguage.java:16` and `NqpRootNode.java:22` (reworded as history);
  `NqpTypeOps.kt:407-409` (now says the claim covers the object decont
  only, and names the open re-suspension gap).

**One deviation, deliberate.** The brief said to drop the
`NQP_DO_TRACE` gate on the sited `NqpOps.bindattr`. Dropping it outright
would have silenced the trace on the **sited** road, which returns
before ever reaching `bindattrSlow` — so once a site resolves, most
binds would print nothing, which defeats the diagnostic. The gate was
moved into the sited branch instead: exactly one line per bind on either
road, which is what the finding asked for.

---

## Builds, gates and timings

| gate | result |
|---|---|
| nqp `clean buildJvm` (`NQP_CODE_STRICT=1`) | EXIT=0, **253 s** |
| `perl Configure.pl --backends=jvm --gen-nqp` | EXIT=0 |
| `make` from the top | EXIT=0, **1142 s** |
| registry probe (nqp side, then Rakudo side) | as specified, above |
| `nqp/t/jvm/16-op-registry.t` | 17/17 |
| nqp `t/nqp` + `t/jvm`, 3 jobs, from the nqp dir | **133 of 134** in 701 s |
| sensitive slice, cold, `./rakudo-j -Ilib` | **6 of 7** in 357 s |
| `t/01-sanity`, 2 jobs, cold | **25 of 25** in 200 s |
| `t/02-rakudo/nested-invocation-continuation.t` | 6/6 |
| `t/03-jvm/01-interop.t`, `t/10-qast/00-misc.t` | 2/2 |
| C2 reproducer | `3` (was rc 124) |
| I1 gather probe | `done` once, at the real exit |
| `keep-undo.t` / `enter-leave.t` | 16/16 / unchanged |

**Timings — this is the milestone's baseline.** `make` **1142 s** total:
rakudo.jar 163 s, BOOTSTRAP v6c starts 193 s, **CORE.c 585 → 1052 s =
467 s**, CORE.d 1058 s, CORE.e 1084 s. nqp clean build **253 s**.
Against milestone 3's 1154 s / 475 s / 222 s. Milestone 4's own
1103-1185 s / 472-511 s were taken with routine inlining and native
lowering off and are not comparable to anything.

Logs: `/home/longwalker/.claude/jobs/25fa1a35/tmp/fw-build.log`,
`fw-configure.log`, `fw-make.log`, `fw-nqp2-logs/`, `fw-slice-logs/`,
`fw-reds-logs/`, `fw-sanity-logs/`.

---

## Still open (characterised, not fixed)

1. **`t/02-rakudo/native-return-coercion.t`, 19/23 — unchanged by the
   wave.** The review attributed it to C1; it is not. Its four failures
   are `dies-ok` assertions that a boxed operand does **not** auto-coerce
   to a native target (`my Int $two; my num $y; dies-ok { $y = $two * $i }`
   and three coercion twins). They failed before the C1 fix and fail
   after it, in the same places. Whatever is too permissive here is a
   separate mechanism and needs its own session.
2. **The five other un-root-caused gate files**, re-run cold in this
   wave, each unchanged: `21-begin-time-compile-sub.t` (EXIT=1, "Failed
   to deserialize lexical `$?PACKAGE`"), `custom-declarator-naming.t`
   (EXIT=1), `make-regex-frame.t` (EXIT=1, engine refusal "qastnode
   walks the caller chain (curcode)"), `try-statement-backtrace-frame.t`
   (EXIT=1), `regex-interpolation-backtrack.t` (EXIT=3),
   `m-flag-module-spec.t`.
3. **`nqp/t/jvm/11-dispatch.t`, test 141 — pre-existing, proven.**
   "Case where bind check fails runs second function"
   (`nqp::assertparamcheck` → `dispatcher-resume-on-bind-failure`).
   Verified by reverting the wave's runtime sources to `908134f3f~1`,
   rebuilding the jars and re-running: identical failure at the
   identical test. It belongs to the ledgered T9 bind-site suspension
   gap.
4. `t/nqp/019-file-ops.t`, `063-slurp.t` and `t/jvm/05-asyncfile.t` fail
   only when run from the rakudo root (cwd-relative paths); all three
   are green from the nqp dir, which is how the 133/134 above was run.

---

## Commits

**nqp** (`/…/jesp-direct-lazy-records/nqp`), on `d24431b68`:

| sha | subject |
|---|---|
| `908134f3f` | runtime: a continuation-captured frame keeps its exit handler for its real exit; UnitLoader marks a unit loaded only after it loaded |
| `47697ca29` | compiler: is_inlinable answers from the classlib registry, the encoder's rows and an explicit non-inlinable table — the deleted add_core_op closures were the table's source |
| `3b9615f4b` | tests: the op registry (inlinability, supports-op) |
| `b3d75f993` | runtime: a suspended frame is still live — the save road keeps its invocation count, so a second invocation of the same static frame resolves its outer correctly |

**rakudo** (worktree root), on `e9a5b9205a`:

| sha | subject |
|---|---|
| `548dc2544d` | JVM ops: the five non-inlinable Raku ops are recorded again |
| `cd5799df09` | tests: a BEGIN-time parameter default holding a code object |
| `031887789e` | tests: a second invocation of one static frame, while the first is suspended |
| (docs) | docs: milestone 4's two gate regressions are fixed, and the timings are re-taken |

Docs updated: `docs/jvm-truffle-only-plan.md` (row 4 and row 6),
`docs/superpowers/specs/2026-09-10-jvm-unit-artifact-milestone-4-design.md`
(a supersession note on the Done section plus a new "Fix wave" section),
`docs/superpowers/specs/2026-09-09-jvm-unit-artifact-design.md`
(Milestones item 4), the ledger twin
`docs/superpowers/plans/2026-09-10-jvm-unit-artifact-milestone-4.ledger.md`
(nine fix-wave lines), and `final-review.md` + `fix-wave-brief.md`
copied into the reports directory.
