# Task 10 report: the BEGIN + `where` code-ref pairing (gap 5c)

**Outcome: FIXED at the cause.** The bug is in the encoder, not in
RakuAST and not in the code-object fixup: `QAST::TruffleEncoder`'s
`patch_params` threw away the deferred code-ref slots that the parameter
prologue itself recorded, so every `QAST::BVal` inside a parameter
default or a param task kept its placeholder qbid **0** -- which is the
unit's **mainline**. A BEGIN-time `where` constraint is exactly such a
BVal, so its `WhateverCode`'s `$!do` was bound to the dynamic unit's
mainline and calling the constraint ran the whole unit ("Too many
positionals passed; expected 0 arguments but got 1").

Trees and heads at the start: rakudo `09f349adda`, nqp `929f73b11`.
All three changed files are in the **nqp** tree.

---

## 1. Reproduction (Step 1)

```
RAKUDO_RAKUAST=1 ./rakudo-j -e 'BEGIN { sub f(Int $x where * > 2) { $x }; say f(5) }'
===SORRY!=== Error while compiling -e
An exception X::Comp::AdHoc occurred while evaluating a BEGIN:
Too many positionals passed; expected 0 arguments but got 1
```

Reproduced exactly as milestone 3's task-3b described it.

## 2. The traces, and what each established

### 2.1 `RAKUDO_DEBUG_STUB=1` -- the stubbing order

```
[stub] RakuAST::PrimeThunk '<anon>' cuid=1        <- the `* > 2` WhateverCode
[stub] RakuAST::Sub 'f'            cuid=2
[stub] RakuAST::Block '<anon>'     cuid=3         <- the BEGIN block's body
[stub] RakuAST::StatementPrefix::Phaser::Begin cuid=4
[link] cuid=1 ; [link] cuid=2 ; [link] cuid=3
```

Established: the where-thunk is a normal stubbed/linked code object with
its own cuid; nothing about the stub itself is unusual, and the failure
happens after all three links.

### 2.2 `NQP_REPOINT_TRACE=1` -- the dynamic unit's table

```
nqp buildTable: unit 567DA8B3... blocks=6 live=6 mainlineQbid=0
  qbid 0 -> cuid=5 ''      <- the DYN_COMP_WRAPPER mainline
  qbid 1 -> cuid=3 ''
  qbid 2 -> cuid=2 'f'
  qbid 3 -> cuid=1 ''      <- the where-thunk, present and distinct
  qbid 4 -> cuid=6 '' ; qbid 5 -> cuid=7 ''
nqp compunitcodes: ... (same six, same order)
```

Established: **no qbid or cuid collision**. `qbidToCodeRef` is correct,
`byCuid` is correct, `lookupCodeRef('1')` would answer the right code
ref. This rules out the brief's question (c) and the `claimNested` /
`jvm-claim-nested` road entirely (the trace shows no `nqp repoint:` line
at all -- `jvm-repoint-dynamic-code` never runs for this reproducer,
because the enclosing `-e` unit never gets to its post-deserialize
fixups: the failure is *inside* the BEGIN).

### 2.3 `NQP_ARITY_TRACE=1` -- who is called with what

```
nqp arity: refused in '' uid=5 at -e:0 ... required=0 accepted=0
nqp arity:   args: null csd=1 caller='ACCEPTS' at SETTING::src/core.c/WhateverCode.rakumod:22
nqp arity:   unit EBFB8C3C... mainlineQbid=0 coderefs: [5 ''] [3 ''] [2 'f'] [1 ''] [6 ''] [7 '']
```

Established: `WhateverCode::ACCEPTS`'s `nqp::call(nqp::getattr(self,Code,'$!do'), value)`
is invoking **uid 5 = qbid 0 = the mainline**. `$!do` is the wrong code
ref; the `null` argument is a downstream consequence (the mainline takes
no parameters, so the refusal happens before any binding).

### 2.4 The decisive trace: a new `NQP_DO_TRACE` knob

The existing knobs could not see the *write* of `$!do` -- `setcodeobj`
is traced, a `bindattr` of `Code.$!do` was not. Added (kept, env-gated,
`nqp/src/vm/jvm/runtime/.../Ops.kt` `DO_TRACE` / `traceDoBind`, called
from both `Ops.bindattr` overloads and the sited
`NqpOps.bindattr(AttrSite, ...)`): every bind of `Code.$!do`, with the
target object's identity, the bound code ref's cuid/unit, and eight nqp
frames. Runtime-jar-only, ~30 s to rebuild.

```
nqp $!do: obj null@72b7b24b <- coderef cuid=1 ...   (IMPL-FIXUP-COMPILED-CODEREFS: correct)
...
nqp $!do: obj null@72b7b24b <- coderef cuid=5 ...   <- THE BUG
    'f' -e:1
    '' -e:0
    'PERFORM-BEGIN' src/Raku/ast/statementprefixes.rakumod:709
nqp $!do: obj null@17b11033 <- coderef cuid=5 ...
    '' src/Perl6/bootstrap.c/BOOTSTRAP.nqp:3100     <- Code.clone of the already-wrong $!do
    'f' -e:1
```

Established, and this is the whole answer:

- The same object (`72b7b24b`, the `WhateverCode`) is first bound
  **correctly** to cuid 1 by `IMPL-FIXUP-COMPILED-CODEREFS`
  (`src/Raku/ast/impl.rakumod:330`), and then **re-bound to cuid 5** by a
  `bindattr` executed *inside `f`'s own compiled code* -- the immediate
  frame is `'f'`, with no BOOTSTRAP frame above it, so this is an emitted
  op, not a method.
- That op is `RakuAST::Code::IMPL-DYNAMIC-DO-REBIND-QAST`
  (`src/Raku/ast/code.rakumod:252-265`), which
  `IMPL-CLOSURE-QAST` (`:214-238`) prepends whenever the code node is
  `$!dynamically-compiled` and we are not precompiling:
  `bindattr($code-obj, Code, '$!do', QAST::BVal.new(:value($block)))`.
- Milestone 3's "the tie is `Code.clone` of an already-wrong `$!do`" is
  confirmed and now explained: the clone at BOOTSTRAP:3100 is one step
  *downstream* of the wrong bind.

### 2.5 Where that BVal sits, and why it resolved to the mainline

`RakuAST::Parameter`'s where-clause emission
(`src/Raku/ast/signature.rakumod:2104-2118`) pushes

```
QAST::ParamTypeCheck.new(QAST::Op.new(:op<istrue>,
    QAST::Op.new(:op('callmethod'), :name('ACCEPTS'),
        $!where.IMPL-TO-QAST($context),   # <- IMPL-CLOSURE-QAST -> the BVal
        $temp-qast-var)))
```

onto `$param-qast` -- i.e. it is a **param task**, a child of the
`QAST::Var :decl<param>`. In the encoder, param tasks are encoded inside
`patch_params` (`nqp/src/vm/jvm/QAST/TruffleEncoder.nqp`), which builds
the whole prologue into a scratch array and, deliberately, hides
`%e<nested>` -- the list of deferred code-ref slots -- behind a fresh
list while it does so, because `splice_code`'s "shift every slot at or
past the mark" rule would otherwise corrupt main-program slots with
scratch-array marks (the "unknown tag 17041" bug of 2026-09-04).

The tail of the method then did:

```
%e<code> := @save;
%e<nested> := @nested_save;     # <- the scratch list, and everything in it, is DROPPED
splice_code(%e, @p, $params_at + 1);
```

Every slot the prologue recorded was discarded, so the deferred patch
loop in `encode_block` never wrote a qbid into those CODEREF cells and
they kept the placeholder `epush(%e, 0)`. **Qbid 0 is the mainline.**
The comment above the swap said "a nested block inside the prologue
bails anyway" -- true (`cbail('nested block in a parameter default')`
fires on `%e<inparams>`), but a `QAST::BVal` does *not* bail; it pushes
to `%e<nested>` like any nested block (`:1321-1327`).

## 3. Answers to the brief's three questions

**(a) Is the `$stub` closure's static code ref the anonymous sub's block
or the mainline's?** The sub's own block, correctly. `Ops.freshcoderef`
clones the code ref *and* its `StaticCodeInfo` and points
`staticInfo.staticCode` at the clone, so `nqp::getstaticcode` on the stub
answers the stub. The stub is not implicated at all: the `$!do` the
failure runs was written long after the stub was replaced, by an emitted
`bindattr`, not by `IMPL-STUB-CODE`.

**(b) Does the `WhateverCode` get its `$!do` through `IMPL-STUB-CODE` or
through `impl.rakumod:203/330/350`?** Through `impl.rakumod:330`
(`IMPL-FIXUP-COMPILED-CODEREFS`) -- and that bind is **correct**
(cuid 1). The wrong value comes from a *fourth* site the brief's list did
not name: the emitted `bindattr` of
`IMPL-DYNAMIC-DO-REBIND-QAST` (`code.rakumod:262`), executed at runtime
inside `f`.

**(c) In `buildTable`, is the `WhateverCode`'s cuid present, and does
`qbidToCodeRef` name the mainline or the right block?** Present, and
correct: qbid 3 -> cuid 1. There is no qbid collision. The mainline was
reached because the *emitted program word* was 0, not because the table
was wrong.

Also checked, as the brief asked: `jvm-claim-nested`/`claimNested` and
`jvm-repoint-dynamic-code` are innocent here -- `jvm-repoint-dynamic-code`
never runs for this reproducer because the failure happens during the
BEGIN, before the enclosing unit has any post-deserialize fixups to run.
Milestone 3's candidate (c) ("a capture bug in `NqpDispatch`") is ruled
out too: the dispatch was faithfully calling the code ref it was handed.

## 4. The probe

Two one-liners separated the parameter prologue from everything else,
before any rebuild:

```
RAKUDO_RAKUAST=1 ./rakudo-j -e 'BEGIN { my $w = * > 2; sub f(Int $x) { $x }; say f(5); say $w.(5) }'
5
True                       # a WhateverCode in a BEGIN body: fine
RAKUDO_RAKUAST=1 ./rakudo-j -e 'BEGIN { my Int $x where * > 2 = 5; say $x }'
5                          # the same thunk on a `my` declaration: fine
```

A `where` thunk is only broken when it rides in a **parameter**, which is
the only place `patch_params`' scratch list applies. That, plus the
`$!do <- cuid=5` trace, is the hypothesis fully cornered.

## 5. The fix

`nqp/src/vm/jvm/QAST/TruffleEncoder.nqp`, `patch_params`: keep the
prologue's own deferred slots and translate them from the scratch array
to where that array lands.

```
%e<code> := @save;
my @nested_params := %e<nested>;
%e<nested> := @nested_save;
nqp::bindkey(%e, 'inparams', 0);
splice_code(%e, @p, $params_at + 1);
for @nested_params -> $nb {
    nqp::bindpos($nb, 0, $nb[0] + $params_at + 1);
    nqp::push(%e<nested>, $nb);
}
```

Why this is at the cause and why it is safe:

- The scratch list still does its original job: while the prologue is
  built, a coercion `splice_code` inside it shifts only prologue slots,
  by prologue marks -- which is now *correct* rather than merely
  harmless, because the slots it shifts are the prologue's own.
- The translation `+ $params_at + 1` is exactly the splice offset used
  one line above, so a scratch index `i` becomes the final index of the
  same word.
- The entries are appended **after** `splice_code`, so that call's
  "shift everything at or past the mark" does not double-count them.
- The later local-types header is compensated for uniformly by the
  patch loop's existing `+ nqp::elems(@ltypes)`.
- Everything downstream is unchanged: the deferred loop compiles the
  block if the unit does not know its cuid yet, exactly as it does for a
  BVal in a body.

Also kept: the `NQP_DO_TRACE` diagnostic described in 2.4 (env-gated,
behind a static-final flag so partial evaluation folds it away).

## 6. Gates

**Reproducer.** Run fresh against the built engine (no rebuild since the
fix landed):

```
RAKUDO_RAKUAST=1 ./rakudo-j -e 'BEGIN { sub f(Int $x where * > 2) { $x }; say f(5) }'
5
```

**The two pair tests** (`./rakudo-j -Ilib`, the in-tree runner needs
`-Ilib` for anything with a `use`, Test included):

- `t/02-rakudo/begin-time-attributive-param-method.t`: `1..5`, all 5 ok
  (including the nested subtest "an undeclared attribute in a
  BEGIN-built method is still rejected", 2/2), `EXIT=0`, 11 s.
- `t/02-rakudo/yada-trait-timing.t`: `1..2`, both ok, `EXIT=0`, 31 s.
- Logs: `/home/longwalker/.claude/jobs/25fa1a35/tmp/t10-pair-logs/`.

**Builds already on this fix (not repeated here):** nqp `clean
buildJvm` EXIT=0 in 258 s; Rakudo `make` from the top EXIT=0 in 1103 s.
The CORE.c compile window from `t10-make.markers`: `[533s] +++
Compiling blib/CORE.c.setting.jar` to `[1019s] +++ Compiling
blib/Perl6/BOOTSTRAP/v6d.jar` -- 486 s, i.e. the fix's translated-slot
loop runs across the whole of CORE.c, CORE.d and CORE.e (and the three
BOOTSTRAPs) without corrupting a neighbouring CODEREF cell, which is
exactly the failure mode an off-by-one in the translation would produce
(loud, not silent -- see section 8).

**`t/01-sanity`** (`RAKUDO_RAKUAST=1`, `--jobs=2`, runner `./rakudo-j`):
`25 of 25 ok in 312s`. Logs:
`/home/longwalker/.claude/jobs/25fa1a35/tmp/t10-sanity-logs`.

**`nqp/t/nqp`** (`RAKUDO_RAKUAST=1`, `--jobs=3`, runner
`nqp/nqp-j-gradle`, run from the rakudo worktree root): `116 of 118 ok
in 481s`. The 2 non-passing files are the known pair,
`019-file-ops.t` and `063-slurp.t`, both failing only on a relative
test-fixture path (`NoSuchFileException: t/nqp/019-setinputlinesep.txt`
/ `t/nqp/063-slurp.t`) that resolves correctly only when the process's
cwd is the nqp tree, not the rakudo root the sweep runs from. Rerun
individually from `nqp/`:
`cd .../nqp && ./nqp-j-gradle t/nqp/019-file-ops.t` -> `112/112 ok`;
`cd .../nqp && ./nqp-j-gradle t/nqp/063-slurp.t` -> `1/1 ok`. So the
suite is 118/118 modulo that cwd artifact, unrelated to the fix. Logs:
`/home/longwalker/.claude/jobs/25fa1a35/tmp/t10-nqp-sweep-logs`.
(Five other files -- `044-try-catch.t`, `112-continuations.t`,
`067-container.t`, `021-contextual.t`, `022-optional-args.t` -- contain
scattered `not ok` TAP lines from pre-existing, unrelated gaps
(dynamic-scope `$*VAR`/`getlexdyn` visibility, continuation control
flow, an exception-message wording, a TODO-marked `nqp::with` case);
none of these touch parameter prologues or `where`/default-value code
refs, all exited `0`, and the sweep's own pass/fail tally (which is
process-exit-code based, matching `019`/`063`'s `EXIT=1`) does not
count them -- they are not this fix's concern and are unchanged by it.)

**Does stage0 need regenerating?** No. `nqp/src/vm/jvm/stage0/` is the
committed bootstrap compiler that compiles stage1 from nqp's own
sources; the fix lives in `TruffleEncoder.nqp`, which stage0 runs as
*code*, not as *data* it was generated from -- so the question is
whether nqp's own sources (compiled by stage0, through stage1, to
produce the stage2 compiler that then encodes Rakudo) contain a
parameter default or `where`-shaped constraint whose deferred code-ref
slot the old `patch_params` was dropping. Grepping nqp/src for
`where`-like constructs is meaningless here: NQP signatures have no
`where` clause at all, and the bug's shape is general (any `QAST::BVal`
sitting in a param task), not textually tied to `where`. The evidence
that stage0 is unaffected is behavioural, not textual: the nqp suite
above is nqp's own compiler compiling and running nqp's own test
corpus through the *fixed* stage1/stage2 built by `clean buildJvm`,
and it comes back 118/118 modulo the unrelated cwd artifact -- no
regression, no new "unknown tag"/placeholder-mainline symptom anywhere
in nqp's bootstrap path. And structurally, the fix only ever fills a
cell that previously held the placeholder `0`; a stage0 build that never
exercised a param-task `BVal` never depended on that cell holding
anything else, so there is nothing for a stage0 regeneration to pick up
that isn't already exercised by rebuilding stage1/stage2 from the fixed
encoder, which `clean buildJvm` already did.

## 7. Files changed (all in the nqp tree)

- `nqp/src/vm/jvm/QAST/TruffleEncoder.nqp` -- the fix in `patch_params`,
  plus the corrected comment above the scratch-list swap.
- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt` -- `DO_TRACE` /
  `traceDoBind`, and the two `Ops.bindattr` call sites.
- `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java` -- the
  same gate on the sited `bindattr`.

No Rakudo source changed; no wire-format change; no new op.

## 8. Self-review

- **Is the diagnosis load-bearing or coincidental?** Load-bearing: three
  independent facts agree (the code ref invoked is qbid 0 = the
  placeholder value; the bind happens from an op inside `f`, which is
  where `IMPL-DYNAMIC-DO-REBIND-QAST` puts it; and moving the same thunk
  out of a parameter makes the failure vanish).
- **Could the fix mis-place a slot?** The only risk is an off-by-one in
  the translation, which would corrupt a neighbouring tag and fail loudly
  (that is how the 2026-09-04 bug presented). The build and the gates
  below exercise it across all of CORE.c, CORE.d, CORE.e, three
  BOOTSTRAPs and the whole compiler.
- **Does it change anything that previously worked?** Only cells that
  previously held the placeholder 0 now hold a real qbid. Nothing that
  worked relied on 0 -- a BVal that resolved to the mainline was always
  wrong.
- **Was the milestone-3 evidence contradicted?** No; it is refined. Its
  candidates (a) `jvm-repoint-dynamic-code`, (b) `IMPL-FIXUP-COMPILED-CODEREFS`
  and (c) a dispatch capture bug are all exonerated, and the "next lead"
  it named (`nqp::getstaticcode`/`IMPL-STUB-CODE`) turned out not to be
  the site either -- the site was one layer below RakuAST, in the encoder.

## 9. Concerns

- **`NQP_DO_TRACE` is a hunt aid, kept per the project's env-gate rule.**
  All three call sites are behind the flag: `Ops.kt`'s two `bindattr`
  overloads do `if (DO_TRACE) traceDoBind(...)` before their existing
  body (unchanged below that line), and `NqpOps.java`'s sited
  `bindattr(AttrSite, ...)` does `if (Ops.DO_TRACE)
  Ops.traceDoBind(smo(o), name, smo(value), tc)` as its first
  statement, also ahead of the existing body. `DO_TRACE` is a
  `@JvmField val` read once from `System.getenv("NQP_DO_TRACE")` at
  class init, so the check is a boolean field read, not a per-call
  environment lookup, and `traceDoBind` itself early-returns unless
  `name == "$!do"` -- with the env var unset (the default, and true for
  every build and gate run in this report) all three sites cost one
  boolean branch and print nothing. This matches milestone 3's other
  trace knobs (`RAKUDO_DEBUG_STUB`, `NQP_REPOINT_TRACE`,
  `NQP_ARITY_TRACE`) in shape and is left in for the next time a
  `$!do` bind needs to be seen, per this project's rule that debug
  prints stay in the tree, env-gated, rather than being stripped after
  the hunt.
- **The two `Ops.bindattr` call-site edits are trace-only.** Diffed
  above (section 6 build note aside): each site adds exactly one guarded line
  immediately before its pre-existing body; no existing statement,
  argument, or return value changed. The sited `NqpOps.bindattr` is the
  same shape. None of the three can change program behaviour when
  `NQP_DO_TRACE` is unset.
- **Scope of the fix is narrow but the failure mode of a mistake would
  be loud, not silent.** `patch_params`' translation is a single `+
  $params_at + 1` applied to every scratch-list entry; the comment this
  report quotes in section 5 explains why entries are appended after
  `splice_code` rather than shifted by it. An off-by-one here would
  point a CODEREF cell at the wrong tag and manifest as the same
  "unknown tag" class of failure the 2026-09-04 bug produced -- which
  the CORE.c/CORE.d/CORE.e build (section 6) and the full gate suite already
  exercise clean, but it is worth flagging as the one place a future
  regression in this area would most likely resurface.
- **Nothing outstanding blocks the commit.** No Rakudo source changed,
  no wire-format change, no new op; the five nqp-suite files with
  unrelated pre-existing `not ok` TAP lines (section 6) are untouched by this
  fix and exited `0` before and after it -- this report does not claim
  to have re-verified their pre-fix state via a second build (the
  no-A/B-compiles rule means there is no bytecode-build comparison
  point to check them against), so they are noted here rather than
  silently passed over.

---

Finished by a second implementer: sanity and the nqp suite gates run
clean, the two placeholder sections above filled in, committed as nqp
`e270f070d`.
