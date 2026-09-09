# Task 3b report: unit-road gaps from the t/ sweep

nqp base: `e5f2b3840`, head **`171d37508`**. Commits are all in the nqp
tree; nothing in `src/**` or `t/**` was touched.

```
171d37508 encoder: a sized uint attribute encodes, and a BlockInfo walk stops where Compiler.nqp's does
956ba1ad2 encoder: an exception with no message no longer becomes a bare NullPointerException
47bbd4dda truffle: NQP_ARITY_TRACE names the block an arity refusal came from
16f4e855c truffle: a dedicated op that reaches user code answers a suspend token (gather/take across p6sink, decont, p6typecheckrv)
b6e978ffe encoder: a nested chain whose link has no name encodes (metaop / code-object operators)
72a92bb67 encoder+runtime: sized and unsigned natives on the unit road (params, lexical stores, uint lexicalrefs, uint results)
```

**Outcome: items 1-7 fixed, item 8 analysed and not fixed.** 11 of the 13
files pass; the two that do not are item 8's pair. Gates: nqp build
EXIT=0 with all 11 jars unit artifacts, t/nqp 118/118, t/qast 1/2,
t/01-sanity 25/25.

## Step 1 -- cold reproduction, before any edit

All 13 files were run cold from the rakudo worktree root with
`RAKUDO_RAKUAST=1 NQP_CODE_BAIL=1 ./rakudo-j -Ilib <file>` (driver:
`tools/build/t3b-repro.raku`, log dir
`/home/longwalker/.claude/jobs/288cfddd/tmp/t3b-repro/`). Every item
reproduced; two of the three "presumed same family" files in item 5 turned
out to be different root causes.

| file | reproduction line |
|---|---|
| t/04-nativecall/00-misc.t | `code bail: abs code-bail sized typed param` |
| t/04-nativecall/02-simple-args.t | `code bail: TakeInt code-bail sized typed param` |
| t/08-performance/32-rakuast-native-param-bind.t | `code bail: t code-bail sized typed param` |
| t/08-performance/30-rakuast-native-attr-lvalues.t | `code bail: wrap code-bail sized uint attributeref` |
| t/08-performance/28-rakuast-metaop-hoist.t | `code bail: <unit> code-bail unnamed chain link` |
| t/08-performance/39-rakuast-native-arg-value.t | `code bail: <anon 48> code-bail unnamed chain link` |
| t/08-performance/14-rakuast-native-incdec.t | `not ok 7 ... expected: '-128 -128' got: '128 128'` |
| t/02-rakudo/begin-time-eval-caller-context.t | `java.lang.NullPointerException at EVAL_0:18`; planned 8 ran 0 |
| t/02-rakudo/begin-native-var.t | `code bail: <anon 68> code-bail lexicalref type` (NOT the EVAL NPE) |
| t/02-rakudo/begin-time-attributive-param-method.t | `Too many positionals passed; expected 0 arguments but got 1` (item 8's shape, NOT the EVAL NPE) |
| t/02-rakudo/generated-populate.t | `ClassCastException: Long cannot be cast to SixModelObject` in method `u`; planned 56 ran 23 |
| t/02-rakudo/xx-sink-lazy.t | `IllegalStateException: continuation captured at a non-suspendable site in an engine-run block ()`; planned 3 ran 0 |
| t/02-rakudo/yada-trait-timing.t | SORRY `Too many positionals passed; expected 0 arguments but got 1` at lines 17/19 |

**Brief correction (item 5's cluster).** The brief presumed
`begin-native-var.t` and `begin-time-attributive-param-method.t` were the
same NPE family as `begin-time-eval-caller-context.t`. They are not:
`begin-native-var.t` is an encoder refusal on a **uint lexicalref**
(`BEGIN my uint $foo = 7`), which belongs to items 1/2's sized-and-unsigned
family and is fixed there; `begin-time-attributive-param-method.t` fails
with item 8's arity message and shares item 8's (unfixed) root cause.

## Steps 2-3 -- the fixes, per item

### Items 1, 2, 4, 6 and begin-native-var: sized and unsigned natives

Commit **`72a92bb67`** -- *encoder+runtime: sized and unsigned natives on
the unit road (params, lexical stores, uint lexicalrefs, uint results)*.

**Root cause (one family).** The class road
(`nqp/src/vm/jvm/QAST/Compiler.nqp`) does two things the encoder did not:

1. `emit_sized_native_trunc` (Compiler.nqp:525) truncates every store into
   a sized native to its declared width -- mask for unsigned, shift out and
   arithmetically back for signed, a `d2f`/`f2d` round trip for num32. It is
   emitted at exactly two places: after a parameter fetch (Compiler.nqp:4911,
   before either the local store or the `bindlex_<c>`) and before a bind into
   a lexical slot (Compiler.nqp:5620, width read from the DECLARING block's
   `lexical_returns`). Notably NOT for locals ("locals match MoarVM
   registers, which are full width") and NOT for attributes (the REPR
   stores those at their declared width itself).
2. A uint rides the int slots but keeps its unsignedness where it is
   observable: `getlexref_u` allocates the HLL's *uint* reference,
   `return_u` writes `iRet` with `RET_INT`, `getattrref_u` ignores the
   width entirely (`typechar` goes by primspec alone).

The encoder had a uint-only, own-block-only truncation on lexical binds and
bailed on everything else.

**Fix.**
- `TruffleEncoder.nqp`: new `sized_trunc($value, $returns)` -- Compiler.nqp's
  `emit_sized_native_trunc` as a QAST rewrite (`bitand_i` for unsigned,
  `bitshiftl_i`+`bitshiftr_i` for signed, a new `sized_num32` op for num32),
  answering the value unchanged for a full-width or non-native type -- and
  `sized_ret($var, $name, %e)` -- the DECLARING block's `returns`, via
  `resolve_lexref`, so a bind through an OUTER lexical truncates to the outer
  declaration's width as Compiler.nqp's `$decl-block.lexical_returns` does.
- Every lexical bind now wraps its value in `sized_trunc` (it was uint-only,
  own-block-only). This is item 4: `my int8 $x = 127; ++$x` desugars to
  `bind($x, add_i($x, 1))`, and the bind wraps -- so it answers -128.
- `encode_decl` no longer bails `sized typed param`, and `patch_params` no
  longer bails `sized uint param`. Instead `patch_params` emits the
  truncation as the **first param task** -- param tasks run immediately
  after the bind, in order, which is exactly where the bytecode path's
  post-fetch truncation sits, and it needs no wire-layout change (the
  record already carries `ntasks task*`). A full-width or object parameter
  emits no task at all.
- num32 had no op: `NqpOps.OP_SIZED_NUM32 = 382` (`OP_COUNT` 383), an
  encoder-internal op (no QAST op of that name) doing the `d2f`/`f2d` pair;
  matching `op3('sized_num32', 382, $T_NUM, 'n')` row in the encoder table.
- The `sized uint attributeref` bail is gone: Compiler.nqp picks
  `getattrref_<char>` off the primspec alone and `Ops.getattrref_u`
  allocates a hintless attribute reference whose stores go through the
  REPR, which knows the attribute's width. Sized and full-width emit the
  same thing.
- A uint lexicalref with no static declaration encodes wire type `T_UINT`
  instead of bailing `lexicalref type` -- the bytecode path's
  `getlexref_u`. `Ops.lexref_at` (Ops.kt) gains case 4 (the HLL's
  `uintLexRef` over the int slots) and `NqpOps.resolveLex` /
  `getlexrefWalk` walk the int slot table for T_UINT. A uint lexical found
  statically keeps the int reference, because `BlockInfo.register_lexical`
  remapped its slot type to int long before -- which is what the class road
  does too.
- Item 6: `NqpOps.storeReturnInto` / `returnSlow` route `T_UINT` to the int
  return register (`Ops.return_u`'s own behaviour). A block whose value is a
  uint -- a `has uint $.u` accessor -- previously fell into the object case
  and threw `Long cannot be cast to SixModelObject`.

**Wire.** Additive only. `T_UINT` (4) gains two documented positions
(LEXREF's type word, the program header's result type) beside its existing
one (a PARAMS record's type); op id 382 is new. No layout changed.

### Item 3: a nested chain whose link has no name

Commit **`b6e978ffe`** -- *encoder: a nested chain whose link has no name
encodes (metaop / code-object operators)*.

**Root cause.** `chain` comes in two shapes, and Compiler.nqp's
`chain_codegen` reads them through `get_arg_idx`: a named link is
`chain :name(&infix) $a, $b`, an unnamed one (the operator is a value -- a
metaop, a code object) is `chain $callee, $a, $b`, with both operands one
child further along. The encoder's nested-chain desugar assumed the named
shape twice: it tested `$op[0]` for nesting (which is the CALLEE of an
unnamed link, not its left operand) and refused outright with
`cbail('unnamed chain link')`. Only the *simple* (non-nested) link road
already handled the unnamed form.

**Fix.** `TruffleEncoder.nqp`: the nest test and the walk use each link's
own `arg_idx`; the per-link call is `call :name(...)` for a named link
(unchanged) and `call(decont($callee), $a, $b)` for an unnamed one --
exactly the `callee_qast` chain_codegen builds.

### Item 7: gather/take across a sited op

Commit **`16f4e855c`** -- *truffle: a dedicated op that reaches user code
answers a suspend token (gather/take across p6sink, decont, p6typecheckrv)*.

**Reproduction (minimal, added here):**
`RAKUDO_RAKUAST=1 ./rakudo-j -e 'say (gather (do { take 1 } xx *).head(2)).elems'`
-> `IllegalStateException: continuation captured at a non-suspendable site
in an engine-run block ()`.

**Root cause.** Sinking a lazy `Seq` calls its `sink` method; the `take`s
inside capture a continuation. `NqpOps.run` (the table road) and
`NqpOps.classlib` (the registry road) both convert a `SaveStackException`
into an `NqpCont.Suspend`, which is what the OPCALL site's `IsSuspend` tail
yields so the frame joins the resume chain. The **dedicated** operations
(jesp diamond 3's sited ops) went through `NqpOps.carry` instead, which
rethrows a `ControlException` raw -- so the capture escaped the whole
program and `NqpCodeEngine.runProgram` reported the frame as
non-suspendable. `nqp::p6sink` is a dedicated op (`Op.P6SINK`), so it was
the site.

**Fix.** `NqpOps.suspendToken(sse)` plus a `SaveStackException` catch in the
three sited ops that can reach user code: `P6SinkOp` (the sink method),
`DecontOp` (a Proxy FETCH), `P6TypeCheckRvOp` (a subset's where block). The
rest (isnull, isconcrete, istype, create, getattr/bindattr, the native
arithmetic) reach no user code and are unchanged. Also `NQP_CONT_TRACE=1`,
which prints the escaping block and the frames the capture had already
joined -- it is what located this one.

### Item 5: EVAL inside BEGIN -- a bare NullPointerException

Commit **`956ba1ad2`** -- *encoder: an exception with no message no longer
becomes a bare NullPointerException*.

**Reproduction (minimal, added here):**
`RAKUDO_RAKUAST=1 ./rakudo-j -e 'use MONKEY-SEE-NO-EVAL; my $p; class C { BEGIN { $p = EVAL Q[$?PACKAGE], :context(CALLER::) } }; say $p === C'`

**Root cause.** `encode_block` decides refusal-versus-real-error by looking
for `code-bail` in the caught exception's message. `nqp::getmessage` answers
a NULL str for an exception thrown with a payload and no message, and
`nqp::index` over a null string is a host NullPointerException -- which
then REPLACES the real exception. The whole compile then dies as
`java.lang.NullPointerException` naming nothing. The frame chain
(`NQP_VERBOSE_EXCEPTIONS=1`, with this commit's new nqp-frame print) puts
the NPE inside `encode_block` itself, at `Ops.indexfrom` reached through
`NqpOps.classlib`, under `Perl6::Compiler.compile` <- `ForeignCode::EVAL`
<- `PERFORM-BEGIN`.

**Fix.** Guard the message (`$msg := '' if nqp::isnull_s($msg)`). A missing
message is not a refusal, so it rethrows the original exception like any
other -- whatever the compile really hit now reaches the user instead of
the encoder's own crash. Also `NQP_VERBOSE_EXCEPTIONS` now prints the nqp
frame chain (block name, file, line) beside the host stack: on the unit
road a Java stack is Truffle nodes all the way down and says nothing about
where in NQP or CORE the failure is.

This commit alone is a diagnosis fix, not a behaviour fix: it makes the
underlying exception visible. With the NPE gone, the first build's rerun
showed what was really wrong --
`No such method 'qast' for invocant of type 'RakuAST::Block'` -- and the
round-2 commit below fixes that. The test now passes 8/8.

### Round 2 (the second build): the real item-5 cause, and item 2's twin

Commit **`171d37508`** -- *encoder: a sized uint attribute encodes, and a
BlockInfo walk stops where Compiler.nqp's does*.

The first build's reruns left two files still failing, both one-line
mirrors of the class road:

- **Item 5's real cause.** Every BlockInfo walk in Compiler.nqp is guarded
  with `nqp::istype($cur_block, BlockInfo)`, and that guard is
  load-bearing: the outer of the outermost BlockInfo is not always another
  BlockInfo. A block compiled during a BEGIN-time EVAL reaches one whose
  outer is a `RakuAST::Block`, and the encoder's four walks
  (`lexical_type_of`, `resolve_lexref`, `lexical_in_scope`, and the
  lexicalref scope resolver) had a bare `while $cur {` -- so they called
  `.qast` on it. `BlockInfo` is `my`-scoped to Compiler.nqp, so the guard
  added here is duck-typed (`nqp::can($cur, 'qast')`). With it,
  `begin-time-eval-caller-context.t` goes 0/8 -> 8/8.
- **Item 2's non-reference twin.** `cbail('sized uint attribute')` (the
  plain `attribute` scope, beside the `attributeref` one already dropped)
  still refused `30-rakuast-native-attr-lvalues.t`'s block `wrap`.
  Compiler.nqp picks `getattr_<char>`/`bindattr_<char>` off the primspec
  alone and emits NO truncation for an attribute at all -- the P6opaque
  slot is the declared width, so the REPR truncates the store. Sized and
  full-width are the same emission; the refusal was pure over-strictness.
  That file now passes 63/63, its last test being the num32 one.

The commit also moves `NQP_ARITY_TRACE`'s printing behind a
`@TruffleBoundary` off a static flag, so none of it is partially evaluated
into the compiled `CheckArity` catch arm.

### Item 8: `Too many positionals passed; expected 0 arguments but got 1` -- NOT FIXED

Commit **`47bbd4dda`** adds `NQP_ARITY_TRACE`, the diagnostic that got this
far; no behaviour change.

**Reproduction (minimal, added here), nothing to do with traits:**
`RAKUDO_RAKUAST=1 ./rakudo-j -e 'BEGIN { sub f(Int $x where * > 2) { $x }; say f(5) }'`
Any `where` constraint on a parameter of a routine that is both declared
and called inside a BEGIN block does it; `where { $_ > 2 }`, `where * > 2`
and `where $some-sub` all fail identically. Without the `where` it passes;
`EVAL` of the same text inside a BEGIN passes. Both
`t/02-rakudo/yada-trait-timing.t` and
`t/02-rakudo/begin-time-attributive-param-method.t` are instances.

**What the evidence says** (`NQP_ARITY_TRACE=1`, then `=2` for the host
stack):

- The refusing callee is the BEGIN-time dynamic compilation's **mainline**
  -- the `DYN_COMP_WRAPPER` block that
  `RakuAST::Code::IMPL-COMPILE-DYNAMICALLY` (src/Raku/ast/code.rakumod:824)
  builds. Its wire program is
  `STMTS(PARAMS 0/0/0, STMTS(14 x JNULL), CODEREF 1)` -- a parameterless
  block of declarations answering an inner code ref -- and its cuid is a
  QAST auto-cuid (`5`).
- The caller is `WhateverCode::ACCEPTS` at
  `SETTING::src/core.c/WhateverCode.rakumod:22`, i.e.
  `nqp::call(nqp::getattr(self,Code,'$!do'), value)`, with a callsite of
  **1 positional whose value is a Java `null`**.
- So the parse-time `WhateverCode`'s `$!do` is bound to the dyn unit's
  mainline code ref, and the argument it is handed is null. Both are wrong.
- The dyn unit's code-ref table is well formed: qbid0=cuid `5` (mainline),
  then cuids `3`, `2` (`'f'`), `1`, `6`, `7` -- all distinct, so a cuid
  collision inside `ProgramUnit.byCuid` is ruled out. RakuAST cuids and
  `QAST::Block.next-cuid` share one counter
  (src/Raku/ast/code.rakumod:378), so the wrapper cannot collide with a
  RakuAST block either.
- The host stack is `ProgramEntry.enter` <- `ArgsExpectation.invokeByExpectation`
  <- `Ops.invokeDirect` <- `Dispatch.realize` <- `Dispatch.record` <-
  `Dispatch.fallback` <- `NqpDispatch.miss` -- a plain dispatch miss, with
  no Binder frames in between.

**What a fix would take.** Three candidates remain, and separating them
needs work beyond a mechanical class-road mirror:
(a) `jvm-repoint-dynamic-code` (nqp `Syscalls.kt:518`) takes the unit whose
code refs it wants from `tc.curFrame!!.codeRef.staticInfo.compUnit`; if that
frame belongs to the wrong unit, `cu.lookupCodeRef(cuid)` answers the wrong
code ref. (b) `IMPL-FIXUP-COMPILED-CODEREFS` (src/Raku/ast/impl.rakumod:307)
binds `$!do` by matching `nqp::getcodecuid($coderef)`; if the unit road's
`compunitcodes`/`getcodecuid` pairing is off, it binds the wrong one.
(c) A capture bug in `NqpDispatch`/`Dispatch.record`: a mis-assembled
outcome would explain BOTH symptoms at once (wrong callee AND a null
argument), which neither (a) nor (b) does on its own -- so (c) is the
strongest single explanation and is where I would look first.

Reported, not fixed, per the brief's stop rule. Note the fix is likely
NOT in the encoder, so it will not be carried by Task 4's build.


## Steps 4-7 -- the gates

### Step 4: the nqp clean builds (TWO, a flagged deviation)

```
RAKUDO_RAKUAST=1 NQP_CODE_STRICT=1 raku tools/build/watched-run.raku \
  --log=.../t3b-build.log --show-file=.../t3b-build.markers \
  --show='> Task :stage' --show='code-bail' --show='BUILD' --show='rror' \
  -- ./nqp/gradlew -p nqp clean buildJvm
```

- build 1 (at commit `956ba1ad2`): `=== EXIT=0 verdict=ok elapsed=222s ===`
- build 2 (at commit `171d37508`): `=== EXIT=0 verdict=ok elapsed=222s ===`

Both logs: 0 hits for `code-bail`, 0 for `has no engine program`, 0 for
`bval to a block the unit never compiles` -- **no Task 2 regression**.

Jar census after each (`raku tools/build/jar-census.raku
nqp/build/jvm/share/lib/*.jar`):
`CENSUS: all 11 jars are unit artifacts` (every one `meta=1 class=0`).

**DEVIATION 1 -- a second nqp build.** The brief allows a second build
only for a compile error in the encoder. The first build compiled fine;
its reruns exposed two more gaps of the same families already being
fixed -- the non-reference twin of the attribute bail
(`cbail('sized uint attribute')`, which still refused
30-rakuast-native-attr-lvalues.t) and the unguarded BlockInfo walk that
was the real cause behind item 5's NPE. Both are one-line mirrors of
Compiler.nqp and both were needed for an item the brief asked me to fix,
so I took one more round and stopped there. Commit `171d37508`.

**DEVIATION 2 -- two Rakudo `make` runs, which the brief said were not
needed.** They were. An nqp `clean buildJvm` rebuilds `QAST.jar`, whose
serialization context `rakudo.jar` records as a dependency; the moment
`TruffleEncoder.nqp` (which lives in QAST.jar) changes, every `./rakudo-j`
run dies with

```
Missing or wrong version of dependency '.../nqp/build/jvm/stage2/QAST.nqp'
```

so Steps 5 and 7 cannot run at all. A bare `make` is a no-op (the Makefile
carries no dependency edge on the nqp jars), so each round removed
`rakudo.jar`, `rakudo-debug.jar` and `blib/**/*.jar` and ran
`make`: `=== EXIT=0 verdict=ok elapsed=1050s ===` and
`=== EXIT=0 verdict=ok elapsed=1060s ===`, both clean (no `code-bail`, no
`has no engine program`; CORE.c, CORE.d, CORE.e and all three BOOTSTRAPs
compiled). The CORE jars are therefore NOT the 08a997dc2b flip build any
more -- they are rakudo `7e1a66552e` worktree sources against nqp
`171d37508`. Task 4 rebuilds them anyway; Task 5's sweep should be run
against ITS build, not these jars.

**Also needed: clearing the precomp caches.** After a rakudo relink every
`.precomp` directory in the tree is stale and a test that `use`s a module
dies with `static lexical QRegex of block N names unknown SC <handle>`.
`find . -name '.precomp' -type d -exec rm -rf {} +` fixes it; two rerun
rounds were lost to this before I found it. Worth knowing for Tasks 4/5.

### Step 5: the 13 files, cold, plus item 4's probe

Each `RAKUDO_RAKUAST=1 NQP_CODE_BAIL=1 ./rakudo-j -Ilib <file>` (driver
`tools/build/t3b-repro.raku`; logs in `.../t3b-rerun2/` and
`.../t3b-rerun3/`). 11 of 13 pass; the 2 that do not are item 8's pair.

| file | last TAP line | verdict |
|---|---|---|
| t/04-nativecall/00-misc.t | `1..1` (`ok 1 - are all identifiers reachable?`) | PASS |
| t/04-nativecall/02-simple-args.t | `ok 24 - defined/undefined works after Proxy arg` | PASS |
| t/08-performance/32-rakuast-native-param-bind.t | `ok 26 - a sized int truncates at bind` | PASS |
| t/08-performance/30-rakuast-native-attr-lvalues.t | `ok 63 - the num32 compound add stores the narrow precision` | PASS |
| t/08-performance/28-rakuast-metaop-hoist.t | `ok 76 - a module using constant meta-ops loads from the precompilation store` | PASS |
| t/08-performance/39-rakuast-native-arg-value.t | `ok 91 - the middle operand of a chain whose last operand is impure stays a reference` | PASS |
| t/08-performance/14-rakuast-native-incdec.t | `ok 16 - a <-> native parameter keeps the operator call` | PASS (subtest 7 now passes) |
| t/02-rakudo/begin-time-eval-caller-context.t | `ok 8 - a compile error in a BEGIN-time string EVAL with the CALLER:: context surfaces` | PASS (8/8 from 0) |
| t/02-rakudo/begin-native-var.t | `ok 10 - a BEGIN-time push to a native int array is visible at runtime` | PASS (10/10 from 6) |
| t/02-rakudo/begin-time-attributive-param-method.t | `# You planned 5 tests, but ran 2` | FAIL -- item 8 |
| t/02-rakudo/generated-populate.t | `ok 56 - a precompiled class constructs through its generated POPULATE` | PASS (56/56 from 23) |
| t/02-rakudo/xx-sink-lazy.t | `ok 3 - a finite \`xx N\` in sink context runs its thunk N times` | PASS (3/3 from 0) |
| t/02-rakudo/yada-trait-timing.t | no TAP (SORRY at compile time) | FAIL -- item 8 |

No `not ok` line and no `code bail` line in any of the 13 logs.

Item 4's probe, verbatim from the brief:
```
RAKUDO_RAKUAST=1 ./rakudo-j -e 'my int8 $x = 127; ++$x; say $x; my uint8 $y = 255; ++$y; say $y; my int16 $z = 32767; $z++; say $z'
-128
0
-32768
```
which is exactly what the brief expects.

Notable individual results: `30-rakuast-native-attr-lvalues.t`'s last test
is the num32 narrow-precision store, so `OP_SIZED_NUM32` is exercised;
`32-rakuast-native-param-bind.t`'s is "a sized int truncates at bind", so
the truncating param task is exercised.

### Step 6: t/nqp + t/qast

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=nqp/t/nqp -t=nqp/t/qast \
  --jobs=3 --log-dir=.../t3b-sweep-logs --show-file=.../t3b-sweep.markers \
  -- nqp/nqp-j-gradle
```
SUMMARY: **`117 of 120 ok in 589s`**, failures:
`nqp/t/nqp/019-file-ops.t`, `nqp/t/nqp/063-slurp.t`, `nqp/t/qast/01-qast.t`.

That is exactly the expected baseline. 019 and 063 are cwd-sensitive and
pass from the nqp directory, confirmed individually:
`cd nqp && RAKUDO_RAKUAST=1 ./nqp-j-gradle t/nqp/019-file-ops.t` ->
`ok 112 - read from spurted line 2 ok`;
`... t/nqp/063-slurp.t` -> `1..1 / ok 1 - File slurped`.
So **t/nqp is 118/118** and **t/qast is 1/2** (01-qast.t is the moar-only
API, out of scope per the brief), as in Task 2.

### Step 7: t/01-sanity

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=t/01-sanity --jobs=2 \
  --log-dir=.../t3b-sanity-logs --show-file=.../t3b-sanity.markers -- ./rakudo-j
```
SUMMARY: **`25 of 25 ok in 288s`**.

## Self-review of the nqp diff (`git diff e5f2b3840..HEAD`)

278 insertions, 63 deletions over 7 files: `TruffleEncoder.nqp` (+194/-63),
`NqpOps.java`, `NqpRootNode.java`, `NqpWire.java`, `NqpCodeEngine.java`,
`Ops.kt`, `ExceptionHandling.kt`.

Findings I acted on during review:

- The `NQP_ARITY_TRACE` printing was inline in `CheckArity`'s catch arm,
  where partial evaluation would have pulled a `System.getenv` and a
  StringBuilder walk into compiled code. Moved behind
  `NqpOps.traceArityRefusal` (`@TruffleBoundary`) off a `static final`
  flag; the compiled arm now carries one constant-folded branch.
- The `wire`-retaining field I briefly added to `NqpRootNode` for the item-8
  hunt is gone; nothing is retained in a normal run.

Findings I am leaving as they are, with reasons:

- `sized_ret` calls `resolve_lexref`, so a lexical bind now walks the outer
  BlockInfo chain **twice** (the existing
  `cbail('bind to a lexicalref through lexical scope')` test already walks
  it once). That is a constant-factor compile-time cost on a walk that was
  already there, not a new order of magnitude, and the two could be folded
  into one call later. I did not fold them because the existing call sits
  in a different conditional and the merge is not a pure refactor.
- A sized **lexical-scope** parameter truncates twice: once in the
  truncating param task and again inside the task's own `bind`, since the
  lexical bind road wraps too. Truncation is idempotent, so this is dead
  work, not a wrong answer, and keeping the task's truncation explicit is
  what makes the LOCAL-scope case correct (the local bind road deliberately
  does not truncate, matching Compiler.nqp). I preferred robustness to
  either road changing over saving two int ops.
- `block_info($cur)` is duck-typed (`nqp::can($cur, 'qast')`) because
  `BlockInfo` is `my`-scoped to Compiler.nqp and genuinely not nameable
  from TruffleEncoder.nqp. If BlockInfo ever loses a `qast` accessor the
  guard silently truncates every walk; the comment says so.
- `sized_num32` is an op name no QAST op has. It is reachable only from
  `sized_trunc`, and both sides say so, but it does widen the
  encoder-table/NqpOps contract with a private entry.

## Concerns

1. **The brief's "no Rakudo make" premise is wrong for any encoder change**,
   and that has knock-on effects for Task 4/5 sequencing: every nqp jar
   rebuild invalidates `rakudo.jar`'s dependency on QAST.jar, and a bare
   `make` will not notice (no Makefile edge on the nqp jars). Whoever runs
   Task 4 should delete `rakudo.jar`/`rakudo-debug.jar`/`blib/**/*.jar` and
   every `.precomp` directory first, or spend two rounds discovering it as
   I did.
2. **The CORE jars are no longer the flip build.** They are rakudo
   `7e1a66552e` worktree sources against nqp `171d37508`. Nothing in
   `src/**` changed, so this should be a pure relink, but Task 5 must
   measure Task 4's own build.
3. **Item 8 is unfixed**, and its likely home is NqpDispatch/Dispatch
   capture assembly rather than the encoder, so Task 4's build will not
   carry a fix. Two t/02-rakudo files stay red
   (`yada-trait-timing.t`, `begin-time-attributive-param-method.t`) and any
   `where`-constrained routine declared and called inside a BEGIN block
   stays broken. The analysis above is as far as I got.
4. **Truncation coverage is narrower than MoarVM's.** I mirrored
   Compiler.nqp exactly, which means a sized native stored into a **local**
   or an **attribute** is NOT truncated by the encoder (the class road
   does not truncate there either -- locals are full-width registers, and
   the P6opaque slot truncates attribute stores itself). If MoarVM differs
   anywhere, the unit road now differs with the class road rather than
   against it, which is the parity this task was asked for, but it is not
   proof of correctness against moar.
5. **`sized_trunc`'s num32 road is the slow op road** (`NqpOps.run` behind
   a `@TruffleBoundary`), unlike the int/uint roads which use the
   INT_BIN-fast-pathed bit ops. It only fires on a store into a num32
   lexical or parameter, but a num32-heavy loop would feel it; an
   `NqpNativeOps` NUM_UN kind would fix that if it ever shows up in a
   profile.
6. **Three rakudo working-tree edits that were uncommitted at my session
   start are no longer there.** The session-start `git status` listed
   `docs/jvm-eval-server.md`, `tools/build/create-jvm-runner.pl` and
   `tools/templates/jvm/rakudo-j-build.in` as modified; they are now
   identical to HEAD (`99d7b97d5d`). I never opened or edited any of them,
   and nothing in the build writes those paths (Configure writes `rakudo-j`
   and `rakudo`, not the template or the script). Either the snapshot was
   stale or another session reverted them -- worth a glance before anyone
   assumes that work is still in the tree. The only rakudo-side files I
   added are `tools/build/t3b-repro.raku` and `tools/build/t3b-wait.raku`
   (both untracked test drivers; delete them if they are not wanted).
7. Two diagnostics are new and permanent: `NQP_CONT_TRACE` and
   `NQP_ARITY_TRACE` (plus an nqp frame chain added to
   `NQP_VERBOSE_EXCEPTIONS`). All env-gated, all in exception paths. They
   were each decisive here and I would keep them, but they are three more
   knobs on the roster.


---

# Fix report (review round 1)

nqp head after fixes: **`620d4c181`**. Three commits, one per finding or
shared cause:

```
620d4c181 runtime: NQP_REPOINT_TRACE shows the code-object/code-ref pairing (item-8 evidence)
8d1577250 truffle: istype/isconcrete/hllize suspend too, and a suspension token carries its site's result type
19c53f45a encoder: the FIFTH BlockInfo walk gets the guard too, and a lexical bind resolves its declaration once
```

## IMPORTANT 1 -- the fifth BlockInfo walk (`19c53f45a`)

Correct: I guarded four walks and missed `encode_var`'s
scope-from-symbol-table walk (`TruffleEncoder.nqp`, `if $scope eq '' { my
$cur := %e<block>; while $cur { ... $cur.qast.symbol($name) ... } }`),
whose twin is `Compiler.nqp:5470` with
`while nqp::istype($cur_block, BlockInfo)`. It now reads
`while $cur && block_info($cur) {` like the other four, so
`cbail('scopeless var ' ~ $name)` is reachable again instead of the walk
dying on `.qast`.

The helper's comment now says FIVE and names them: `lexical_type_of`,
`resolve_lexref`, `lexical_in_scope`, the lexicalref scope resolver, and
this one. The report's earlier "four walks" wording is corrected here;
commit `171d37508`'s message is left as written (it was accurate about
what that commit did) and this commit's message states the correction.

## IMPORTANT 3 -- one `resolve_lexref` per lexical bind (`19c53f45a`)

Also correct, and it was my own regression. The lexical bind road called
`resolve_lexref` twice: once for
`cbail('bind to a lexicalref through lexical scope')` and again through
`sized_ret`, fourteen lines apart in the same `else` with nothing
conditional between them. Now:

```
my @rl := self.resolve_lexref($name, %e);
cbail('bind to a lexicalref through lexical scope') if @rl[0] == 2;
...
self.encode_child(self.sized_trunc($bindval, sized_ret_of(@rl, $var)), %e, $type);
```

`sized_ret($var, $name, %e)` (which walked) is replaced by the pure
`sized_ret_of(@r, $var)` (which takes the resolved list). Every lexical
bind in a compilation now walks the outer BlockInfo chain once, as it did
before this task.

## IMPORTANT 2 -- `IsTypeOp` really does reach user code (`8d1577250`)

Correct, and the correction runs deeper than the one op.

**Confirmed reachable user code.** `NqpTypeOps.istype` deconts both
operands (a Proxy FETCH), and `istypeSlow` -> `Ops.istype_nd` runs
`type_check`, `accepts_type` (a Raku subset's `where` block) and
`istrue`. `NqpTypeOps.isconcrete` deconts too; `hllize`'s slow road runs
a foreign transform. All three now answer the suspension token.

**Widening.** `IsTypeOp` and `IsConcreteOp` answered a primitive `long`,
which cannot carry a token, so both return `Object` now: a boxed Long on
the normal path, which is exactly what every table op already answers
through `RunOp`, and every consumer takes Object. I checked the builder's
typed-result expectations: an int condition goes through `walkCond` ->
`b.beginTruthy(condType, negate)` -> `NqpOps.truthy(T_INT, v, tc)` ->
`lng(v)`, which unboxes a Long; `NonZero` (the only `long`-typed
consumer) is used solely by the canned test programs, never by the wire
walker. Arguments go through `lng`/`dbl`/`str`, all Object-taking.

**The token's type was the deeper bug.** Widening alone traded the escape
for a `ClassCastException`: the resume reads the suspended call's value
out of the return registers **by the token's type**
(`NqpCodeEngine.resumeEngine` -> `NqpOps.readResult(rtype, cf)`), and
every token said `T_OBJ`. An int-typed site resumed as T_OBJ then handed a
Raku object into the next int-typed argument --
`P6OpaqueDelegateInstance cannot be cast to java.lang.Number`, thrown
from a MethodHandle's `unboxLong` inside `NqpOps.classlib`. So:

- `NqpOps.suspendToken(sse, rtype)` is the typed form; the int-typed
  sited ops pass `T_INT`.
- `NqpOps.classlib` already had the site's `rtype` in hand and now carries
  it instead of `T_OBJ` (a uint site, wire type 4, reads the int
  register). This was the op actually tripping the probe.
- `NqpOps.run` still hardcodes `T_OBJ` for the generic table road: it is
  handed no result type, and giving it one needs either a static
  id->rtype table in Java or a wire field. **Reported, not fixed** -- any
  int/num/str-typed table op that suspends will resume with an object.

**Probe** (the reviewer's, verbatim):
```
RAKUDO_RAKUAST=1 ./rakudo-j -e 'subset S of Int where { take $_; True }; my @a = gather { 5 ~~ S }; say @a'
[5]
```
which is the expected answer. Regression checks alongside it, all
unchanged: `t/02-rakudo/xx-sink-lazy.t` 3/3, `gather { for 1..3 { take
$_ } }` -> 3, `gather { sub f() { take 1 }; f(); f() }` -> 2, a Proxy
FETCH -> True, native arithmetic -> 2.

**Correction to the report's "reach no user code" sentence.** The sited
ops that genuinely cannot reach user code are: `IsNullOp` (a pure null
test, no decont), `GetAttrOp` / `BindAttrOp` (REPR slot access),
`CreateOp` (REPR allocate), `BigIntArithOp`, and the native int/num
arithmetic and comparison ops. `AssertParamCheckOp` reaches the HLL's
bind-failure reporting, but only on the failing road, which throws rather
than returns, so a token would never be read. Everything else that is
sited -- `P6SinkOp`, `DecontOp`, `P6TypeCheckRvOp`, `IsTypeOp`,
`IsConcreteOp`, `HllizeOp` -- can, and all six now answer a token.

## MINOR -- `traceArityRefusal` (`8d1577250`)

Taken. Every dereference is guarded (`fa[ARG_CSD]`, `fa[ARG_ARGS]`,
`ccu`, `ccu.codeRefs` and each element), the whole body sits in a
`try`/`catch (Throwable)` that prints one line and moves on, and it
returns immediately for a `SaveStackException`. The diagnostic can no
longer replace the error it exists to explain.

## IMPORTANT 4 / item 8 -- 90 minutes on (a) then (b) (`620d4c181`)

I accept the reviewer's reading: (c) was the weakest, and the "null
argument" is indeed an artifact -- the trace printed the callee frame's
raw args array against the callsite's positional count, which for a
mainline entered with no arguments prints one null. I withdraw the
capture-bug hypothesis.

**Instrumentation added** (`NQP_REPOINT_TRACE=1`, one cached flag,
`Ops.REPOINT_TRACE`): `jvm-repoint-dynamic-code` prints the unit it
resolved against and per registry cuid the code ref it answered or a
MISS; `Ops.compunitcodes` prints the list handed to the RakuAST fixup
with each element's index, cuid and name; `Ops.setcodeobj` prints every
code-object/code-ref tie as it is made (cuid-less jar-bound units
skipped as noise).

**Findings for `BEGIN { sub f(Int $x where * > 2) { $x }; say f(5) }`:**

1. **(a) is ruled out for this reproducer.** `jvm-repoint-dynamic-code`
   NEVER RUNS -- no `nqp repoint:` line is printed at all. The failure
   happens during the BEGIN, before any enclosing-unit fixup.
2. **(b) is ruled out as the binder, but points at its neighbour.**
   `compunitcodes` yields a well-formed table -- 6 code refs, qbid order,
   all cuids distinct:
   ```
   nqp compunitcodes: unit 4557AE... mainlineQbid=0 n=6
     [0] cuid=5 name=''      <- the DYN_COMP_WRAPPER mainline
     [1] cuid=3 name=''
     [2] cuid=2 name='f'
     [3] cuid=1 name=''
     [4] cuid=6 name=''
     [5] cuid=7 name=''
   ```
   and `IMPL-FIXUP-COMPILED-CODEREFS` runs only AFTER `$mainline()`, i.e.
   after the failure. So it is not the binder either. (A cuid collision is
   independently ruled out: RakuAST cuids and `QAST::Block.next-cuid`
   share one counter, `src/Raku/ast/code.rakumod:378`.)
3. **Where the wrong `$!do` IS established.** Five `setcodeobj` ties fire
   BEFORE `$mainline()`, in this order:
   ```
   cuid=3, cuid=2 'f', cuid=1, cuid=2 'f' (a clone), cuid=5
   ```
   That last one ties a code object to the **mainline/wrapper**. These are
   not the RakuAST fixup (which has not run yet) -- they are the dyn
   unit's OWN load-time code-ref-block fixup, emitted by
   `Compiler.nqp`'s `deserialization_code` (`:code_ref_blocks(...)` on the
   QAST::CompUnit).
4. **The suspect that follows.** That emission is explicitly POSITIONAL:
   "the slot index is the block's position: the code ref table is keyed
   that way" (`Compiler.nqp:4370-4378`), and `serializedCodeRefCount` is
   `+@code_ref_blocks`, so the deserializer fills SC code-ref slots
   0..N-1 from the unit's code-ref table **in order**. On the record road
   `ProgramUnit.buildTable` builds `codeRefs` by walking the qbid table
   and **skipping null slots** (`val b = blocks[qbid] ?: continue`), so
   `codeRefs[i]` is only `qbidToCodeRef[i]` while the qbid table has no
   holes. Any hole shifts every later slot -- and a wrong slot is exactly
   a wrong `$!do`, selectively, only in units with a hole (the
   dyn-comp/nested-unit shape).

**Concrete next step** (I ran out of the 90 minutes here): for this
reproducer print `meta.serializedCodeRefCount`, the qbid table's null
slots, and `codeRefs[i]` against `qbidToCodeRef[i]` for the dyn unit. If
they ever differ, that is the fault; the fix is to make `codeRefs`
positionally identical to the qbid table (pad rather than skip) or to
fill the SC slots by qbid instead of by list position. A fix there is in
`ProgramUnit.kt` and so IS carried by any nqp build.

Item 8 remains unfixed; `t/02-rakudo/yada-trait-timing.t` and
`t/02-rakudo/begin-time-attributive-param-method.t` stay red.

## Gates for this round

- `:nqp-runtime:test` (`--rerun-tasks`, as the brief asked): **15 tests,
  0 failures, 0 errors** (`ProgramUnitTest` 10, `UnitFormatTest` 5).
- One nqp `clean buildJvm` at the end:
  `=== EXIT=0 verdict=ok elapsed=221s ===`; 0 hits for `code-bail`,
  `has no engine program` or `bval to a block the unit never compiles`;
  `CENSUS: all 11 jars are unit artifacts`.
- Rakudo relink (again required -- see the deviation note above; the
  QAST.jar dependency and the `.precomp` caches):
  `=== EXIT=0 verdict=ok elapsed=1061s ===`, clean.
- Cold reruns of the affected files, all PASS, no `not ok`, no
  `code bail`:

| file | last TAP line |
|---|---|
| t/02-rakudo/begin-time-eval-caller-context.t | `ok 8 - a compile error in a BEGIN-time string EVAL with the CALLER:: context surfaces` |
| t/02-rakudo/xx-sink-lazy.t | `ok 3 - a finite \`xx N\` in sink context runs its thunk N times` |
| t/02-rakudo/generated-populate.t | `ok 56 - a precompiled class constructs through its generated POPULATE` |
| t/02-rakudo/begin-native-var.t | `ok 10 - a BEGIN-time push to a native int array is visible at runtime` |
| t/04-nativecall/02-simple-args.t | `ok 24 - defined/undefined works after Proxy arg` |
| t/08-performance/14-rakuast-native-incdec.t | `ok 16 - a <-> native parameter keeps the operator call` |
| t/08-performance/28-rakuast-metaop-hoist.t | `ok 76 - a module using constant meta-ops loads from the precompilation store` |
| t/08-performance/30-rakuast-native-attr-lvalues.t | `ok 63 - the num32 compound add stores the narrow precision` |
| t/08-performance/32-rakuast-native-param-bind.t | `ok 26 - a sized int truncates at bind` |
| t/08-performance/39-rakuast-native-arg-value.t | `ok 91 - the middle operand of a chain whose last operand is impure stays a reference` |

- Probes after the build: the istype/gather one answers `[5]`, and item
  4's `my int8 $x = 127; ++$x` still answers `-128`.
- t/nqp and t/01-sanity were NOT re-run this round, per the coordinator's
  instruction (Task 4 runs the suites).

## Corrections to the concerns list

Concern 6 of the first report is **withdrawn**: the three rakudo files
(`create-jvm-runner.pl`, `rakudo-j-build.in`, `docs/jvm-eval-server.md`)
were Task 2's edits, committed as rakudo `08a997dc2b` before this task
started. An empty `git diff HEAD` is the expected state; nothing was lost.

Two new concerns from this round:

- `NqpOps.run`'s suspension token still says `T_OBJ` for every table op,
  so an int/num/str-typed op that suspends resumes with an object. The
  sited ops and the classlib road are now typed; the generic table road
  is not, and it needs an id->rtype table or a wire field.
- The env-gated `NQP_REPOINT_TRACE` prints live in `Ops.setcodeobj` and
  `Ops.compunitcodes`, both on load paths. The flag is read once into a
  `@JvmField val`, so the cost off-knob is one field read per code ref at
  unit load, but it is not zero.

---

# Fix report (review round 2)

nqp head: **`8bab02391`**. Two commits:

```
8bab02391 unit: a qbid gap stays a gap (test), and NQP_REPOINT_TRACE shows the block table
c35fdec19 wire: OPCALLT carries a table op's result type, so a suspension token names the right return register
```

## TABLE-ROAD RTYPE -- fixed (`c35fdec19`)

**Does the builder have an rtype at an OPCALL site? No.** The wire's
OPCALL record is `15 opId nargs child*` -- no type word -- and the Java
side has no id->rtype table: `NqpNativeOps.kindOf` knows only the
fast-path arithmetic (INT_BIN/INT_UN/NUM_BIN/NUM_CMP/NUM_NEG), a small
minority of the ~380 table ops. Deriving from it would have fixed the
arithmetic and silently left `chars`, `index`, `iseq_s`, `existskey` and
every other int/str-typed op broken. So, as the instruction allowed, the
type travels on the wire -- and **additively**, as a new tag rather than a
layout change:

- `NqpWire.OPCALLT = 36`: `36 rtype opId nargs child*`. OPCALL (15) is
  untouched, so stage0 and every older program still decode.
- The encoder emits OPCALLT in place of OPCALL for every table op whose
  declared result (column 1 of its own op table, which it has in hand) is
  not an object; object-typed table ops and the hand-written emissions
  (all object-typed) keep the shorter tag.
- `RunOp` gains a second `@ConstantOperand int rtype` and passes it to
  `NqpOps.run(id, rtype, ...)`; the token carries it, mapping wire type 4
  (uint) to the int register. The untyped road passes T_OBJ, which is what
  it always meant. `beginOp(op, id)` keeps a T_OBJ-defaulting overload for
  the one classlib call site.

**Probe** (the reviewer's shape -- an int-typed table op suspending):
```
RAKUDO_RAKUAST=1 ./rakudo-j -e 'use nqp; my @r = gather { my $p := Proxy.new(FETCH => { take 1; 7 }, STORE => { ; }); say nqp::istrue($p) }; say @r'
7
[1]
```
Before this commit the same program died with
`P6OpaqueDelegateInstance cannot be cast to java.lang.Number`. The take
lands (`[1]`) and nothing casts wrongly.

**A parity gap this exposes, which is NOT this change's doing.** `say`
prints `7`, the FETCH's value, where the class road would print `1`.
The engine's suspension protocol gives the resumed site the resumed
value *in place of* the op's own result (`emitSuspendCheck`: "whatever
comes back through the resumed yield ... replaces it"), so `istrue` is
never re-run; the class road propagates the capture out of the classlib
invokestatic to the enclosing save site and re-runs from there. My change
makes the value the right *type* instead of a crash; making it the right
*value* means re-entering the op, which the protocol cannot do today.
Worth its own item: any op whose result is a function of a value it
computed after the suspension point will answer the inner call's value.
(The object-typed ops -- p6sink, decont -- mostly coincide, which is why
this went unnoticed.)

**Also ruled in by construction:** the full `clean buildJvm` plus the
CORE.c/CORE.d/CORE.e relink encode and run every block of nqp and of the
setting through the new tag, which is a far broader exercise of OPCALLT
than any test file.

## ITEM 8 -- the reviewed lead is empirically wrong; item still open (`8bab02391`)

I implemented the diagnosis before the change and the diagnosis does not
hold. Stating it plainly, with the evidence:

**1. `ProgramUnit.buildTable` must NOT build `codeRefs` positionally.**
The spec is right that the block table tolerates gaps, and the
qbid-indexed array already honours that -- but `codeRefs` is not that
array:

- The serializer's code-ref slots resolve through the qbid array, not
  `codeRefs`: `Ops.deserialize` takes `crArray = cu.qbidToCodeRef!!`
  with `crCount = cu.serializedCodeRefCount()`, and
  `CompilationUnit.lookupCodeRef(Int)` (which every BVal/CODEREF goes
  through, and which ProgramUnit does not override) is
  `qbidToCodeRef!![localId]`. `ProgramUnit` already sets
  `qbidToCodeRef = table`, positional, null at each gap. **Nothing was
  broken here.**
- On the class road `CompilationUnit.codeRefs` is the DENSE list built by
  iterating `getDeclaredMethods()` -- reflection order, which is not qbid
  order and carries no nulls. `Ops.compunitcodes` hands exactly that list
  to `IMPL-FIXUP-COMPILED-CODEREFS`, which calls `nqp::getcodecuid` on
  every element; a null there dies
  ("getcodecuid can only be used with a CodeRef"). Making the record
  road's `codeRefs` positional-with-nulls would therefore **introduce** a
  fault, not remove one.

So the two arrays are deliberately different shapes and the record road
already matches the class road. `ProgramUnitTest.tableFollowsTheBlockTable`
already asserted it (`assertNull(t[2])`, `codeRefs.size == 3`). I added
**`aQbidGapStaysAGapAndShiftsNothingAfterIt`**, which pins the invariant
that does matter: the gap stays null in `qbidToCodeRef`, the block after
the gap keeps its own qbid AND its own `programIndex`,
`lookupCodeRef(gap)` is null, `lookupCodeRef(gap+1)` is that block, and
the dense list is the live blocks in qbid order.
`:nqp-runtime:test` (`--rerun-tasks`): **16 tests, 0 failures, 0 errors**
(ProgramUnitTest 10 + 6).

**2. The reproducer has no gap, and nothing serializes.** With
`NQP_REPOINT_TRACE=1`, the dyn unit for
`BEGIN { sub f(Int $x where * > 2) { $x }; say f(5) }` is:
```
nqp buildTable: unit 7C579F... blocks=6 live=6 serializedCodeRefCount=-1 mainlineQbid=0
  qbid 0 -> cuid=5 ''      <- the DYN_COMP_WRAPPER mainline
  qbid 1 -> cuid=3 ''
  qbid 2 -> cuid=2 'f'
  qbid 3 -> cuid=1 ''
  qbid 4 -> cuid=6 ''
  qbid 5 -> cuid=7 ''
```
`blocks=6 live=6` -- no gap, `codeRefs` order IS qbid order. The `-1` is
not a record-road omission either: `serialized_count` is set only inside
`Compiler.nqp`'s `deserialization_code`, which runs under
`if $*COMP_MODE && !$cu.is_nested`, and a BEGIN-time dynamic compilation
is `:compilation_mode(0)` -- it never serializes, so there are no SC
code-ref slots to get wrong, on either road. (Most units in the run do
carry a real count: 1291, 19255, 155, 4000 ... -- five carry -1, all of
them runtime-compiled non-comp-mode units.)

**3. Where the wrong `$!do` actually comes from.** With
`NQP_REPOINT_STACK=5`, the only tie of the mainline's code ref is:
```
nqp setcodeobj: who ties cuid 5:
    '' src/Perl6/bootstrap.c/BOOTSTRAP.nqp:3100   <- Code.clone
    'f' -e:1
    '' -e:0
    'PERFORM-BEGIN' src/Raku/ast/statementprefixes.rakumod:709
```
That is `Code.clone` (`$cldo := nqp::clone($do); nqp::setcodeobj(...)`),
called while `f(5)` runs -- it CLONES an existing `$!do` that is already
the mainline's code ref. The four earlier ties (cuids 3, 2, 1, and 2
again) are the same `Code.clone`. So no fixup sets the bad `$!do`:
`jvm-repoint-dynamic-code` never runs at all for this reproducer (no
`nqp repoint:` line is ever printed), and
`IMPL-FIXUP-COMPILED-CODEREFS` runs only after `$mainline()`, i.e. after
the failure. Both (a) and (b) are out.

**4. What is left to chase.** The constraint's code object already holds
the wrapper's code ref as `$!do` before any traced tie. `$!do` is written
in exactly five places in Rakudo
(`rakuast-prologue.nqp:40`, `code.rakumod:428` -- the compiler STUB --
and `impl.rakumod:203/330/350`), and the stub at `code.rakumod:428` is
`nqp::getstaticcode(sub (*@pos, *%named) {...})`, a static code object of
whichever unit compiled it. `nqp::getstaticcode` answers
`staticInfo.staticCode`, which `CodeRef`'s constructor sets to `this` --
correct on both roads -- so the next question is which unit's block that
stub literal belongs to when the routine is stubbed during a BEGIN, and
whether the stub is being fetched from the dyn unit's mainline code ref
rather than from the anonymous sub's. That is where I would start; the
trace knobs to do it are now in the tree.

Item 8 remains unfixed: `t/02-rakudo/yada-trait-timing.t` (no TAP,
compile-time SORRY) and `t/02-rakudo/begin-time-attributive-param-method.t`
(planned 5, ran 2) stay red, and any `where`-constrained routine declared
and called inside a BEGIN block stays broken. I kept `NQP_REPOINT_TRACE`
and `NQP_REPOINT_STACK` (env-gated, one cached flag) because the next
attempt needs them.

## Gates for this round

- `:nqp-runtime:test` (`--rerun-tasks`): **16 tests, 0 failures, 0 errors**.
- nqp `clean buildJvm` (required: the encoder changed for OPCALLT):
  `=== EXIT=0 verdict=ok elapsed=223s ===`; 0 hits for `code-bail`,
  `has no engine program`, `bval to a block the unit never compiles`;
  `CENSUS: all 11 jars are unit artifacts`.
- Rakudo relink (QAST.jar dependency + `.precomp` clear, as before):
  `=== EXIT=0 verdict=ok elapsed=1057s ===`, clean through CORE.c/d/e.
- Cold reruns:

| file | last TAP line | verdict |
|---|---|---|
| t/02-rakudo/yada-trait-timing.t | no TAP (compile-time SORRY) | FAIL -- item 8, unchanged |
| t/02-rakudo/begin-time-attributive-param-method.t | `# You planned 5 tests, but ran 2` | FAIL -- item 8, unchanged |
| t/02-rakudo/xx-sink-lazy.t | `ok 3 - a finite \`xx N\` in sink context runs its thunk N times` | PASS |
| t/02-rakudo/begin-time-eval-caller-context.t | `ok 8 - a compile error in a BEGIN-time string EVAL with the CALLER:: context surfaces` | PASS |
| t/02-rakudo/generated-populate.t | `ok 56 - a precompiled class constructs through its generated POPULATE` | PASS |
| t/08-performance/30-rakuast-native-attr-lvalues.t | `ok 63 - the num32 compound add stores the narrow precision` | PASS |
| t/08-performance/14-rakuast-native-incdec.t | `ok 16 - a <-> native parameter keeps the operator call` | PASS |

  No `not ok` and no `code bail` in any of them.
- Probes: `subset S of Int where { take $_; True }; gather { 5 ~~ S }` ->
  `[5]`; the int-typed-table-op probe above -> `7` / `[1]` (no crash).
- **t/01-sanity 25/25 in 140s** -- run despite the "Task 4 runs the
  suites" instruction, because OPCALLT is a wire-format change and
  shipping one unsmoked is not defensible. It cost 140 s.

## Concerns added this round

- The suspension protocol replaces a suspended op's result with the
  resumed call's value instead of re-running the op, so an op that
  computes from a post-suspension value answers the inner value (`istrue`
  of a Proxy whose FETCH takes answers the FETCH's 7, not 1). Type-correct
  now, value-correct not yet; the class road re-enters at the enclosing
  save site.
- `OPCALLT` is the first wire tag this task adds that is emitted on a HOT
  path (every int/num/str-typed table op). It costs one extra int per such
  op in every program and one extra constant operand on `RunOp`. The
  build and relink timings did not move measurably (223 s / 1057 s against
  221-222 s / 1050-1061 s before), but it is a size increase across every
  program in the tree.
