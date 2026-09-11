# Task 3 Report: Rakudo's op file, the milestone's first make

## Inherited state (Step 1, uncommitted diff on entry)

The prior implementer's edit to `src/vm/jvm/Raku/Ops.nqp` (782 -> 573 lines) matched the
brief's Step 1 exactly. Verified point by point against `git diff -- src/vm/jvm/Raku/Ops.nqp`:

- `register_op_desugar` rewritten to the brief's exact shape: still publishes the hllsym
  (`%code_op_desugars` + `nqp::bindhllsym`), now records inlinability via
  `nqp::getcomp('QAST').operations.set_hll_op_inlinability($compiler, $name, $inlinable)`
  instead of `add_hll_op`.
- `$ALOAD_1` and every now-unused JAST type constant deleted (`$TYPE_CSD`, `$TYPE_SMO`,
  `$TYPE_TC`, `$TYPE_CF`, `$TYPE_STR`, `$TYPE_OBJ`); `$TYPE_P6OPS` and `$TYPE_OPS` kept
  (still named by `map_classlib_hll_op` calls).
- Deleted closures, confirmed all present in the diff and gone from the file:
  `p6bindsig`/`p6trybindsig` add_hll_op registrations, `p6box` add_hll_op, `decontrv_op` sub
  plus the `p6decontrv`/`p6decontrv_6c` add_hll_op registrations, `p6return` add_hll_op,
  `p6argvmarray` add_hll_op, `p6invokehandler`/`p6invokeflat` add_hll_op, the
  `QAST::OperationsJAST.add_hll_op('Raku', 'defor', ...)` override, and all four
  `add_hll_box`/four `add_hll_unbox` registrations.
- Kept: `$trial_bind`, every `register_op_desugar(...)` call (including
  `p6decontrv_internal`, `p6assign`, `p6attrinited`, which are unrelated pre-existing
  desugars, not part of the JAST-closure deletion list), every `map_classlib_hll_op(...)`
  call, and `my $ops := nqp::getcomp('QAST').operations;`.

**No corrections were needed.** The file is internally consistent: e.g. the
`p6decontrv_internal` desugar still constructs a `QAST::Op.new(:op('p6box'), ...)` tree
node (this is unrelated to the deleted `p6box` add_hll_op closure -- the encoder has its
own row for the `p6box` op per the task's Context section), and the deleted TYPE_* constants
have zero remaining references anywhere in the file.

## Step 2: grep verification

```
grep -n 'JAST\|as_jast\|add_hll_op\|add_hll_box\|add_hll_unbox' src/vm/jvm/Raku/Ops.nqp
```
Empty, as required.

Also re-ran the controller's ruling-2 check:
```
grep -rn 'p6box\b\|p6invokehandler\b' src/Raku/ast
```
Empty -- confirms neither op has a RakuAST emitter, matching the brief and the controller
ruling.

## Step 3: Configure + make

Configure had already been run by the prior session (not rerun, per instructions). Launched
the make via watched-run as a background job (it resumed from the killed session's point --
`rakudo.jar` was already built; BOOTSTRAP v6c onward recompiled):

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/25fa1a35/tmp/t3-make.log \
    --show-file=/home/longwalker/.claude/jobs/25fa1a35/tmp/t3-make.markers --show='Compiling' --show='Generating' \
    --show='rror' --stall=1500 -- make
```

**Result: `=== EXIT=0 verdict=ok elapsed=955s ===`** (~15m55s from the BOOTSTRAP v6c resume
point -- in line with the brief's ~17 min estimate).

**CORE.c window** (from the markers file): starts at `[401s] +++ Compiling
blib/CORE.c.setting.jar`, ends at `[863s] +++ Generating gen/jvm/BOOTSTRAP/v6d.nqp` -> **~462s**
total. Internal stage breakdown (from the log): parse 357.885s, syntaxcheck 0s, ast 0s,
optimize 34.348s, qast 29.060s, unit 26.146s, jar 0s (sum 447.439s, difference from the
462s marker window is process-startup/teardown overhead). This is in line with the
milestone-3 baseline of CORE.c 475s (this run measured slightly faster) -- no regression
from dropping the JAST desugar/box/unbox closures.

One benign, unrelated warning appeared during the rakudo-j setup step: `cp: cannot stat
'.../nqp/bin/eval-client.pl': No such file or directory`. It did not affect `EXIT=0` and is
unrelated to the Ops.nqp change (a pre-existing nqp-side setup artifact, not present in the
task-1/task-2 build logs because those logs didn't reach this point verbatim, but the file's
absence is a `nqp/` tree property, outside this task's file scope).

**Jar census** (`raku tools/build/jar-census.raku --nested ...`):

```
ARTIFACT meta=1   class=0     nested=0  rakudo.jar
ARTIFACT meta=1   class=0     nested=0  blib/Perl6/BOOTSTRAP/v6c.jar
ARTIFACT meta=1   class=0     nested=0  blib/Perl6/BOOTSTRAP/v6d.jar
ARTIFACT meta=1   class=0     nested=0  blib/Perl6/BOOTSTRAP/v6e.jar
ARTIFACT meta=1   class=0     nested=8  blib/CORE.c.setting.jar
ARTIFACT meta=1   class=0     nested=0  blib/CORE.d.setting.jar
ARTIFACT meta=1   class=0     nested=0  blib/CORE.e.setting.jar
CENSUS: all 7 jars are unit artifacts
```

All jars are `unit.meta`-only (class=0); CORE.c carries the expected 4 nested units
(nested=8 counts the `.meta`+`.programs` pair per unit).

## Step 4: suites

- **t/01-sanity**: `25 of 25 ok in 160s`.
- **t/03-jvm + t/10-qast**: `2 of 2 ok in 34s`.
- **precomp (14 files)**: cleared `lib/.precomp` and `t/packages/Test-Helpers/.precomp`
  first, as instructed. Result: **13 of 14 ok in 453s**. The one failure,
  `t/02-rakudo/rakuast-suspend-precomp-deps.t` (exit 255), was investigated in depth (see
  Concerns below) and is a pre-existing environment gap unrelated to the Ops.nqp/JAST work.

## Files changed

- `src/vm/jvm/Raku/Ops.nqp` (the only file in scope; committed).

## Commit

`2e66c36b3d` -- "JVM ops: the Raku op file registers classlib mappings and desugars only;
the JAST closures are gone" (rakudo tree). Confirmed only `src/vm/jvm/Raku/Ops.nqp` was
staged (`git diff --cached --stat`: 1 file changed, 2 insertions, 211 deletions) before
committing.

## Self-review findings

- The inherited Step 1 diff required zero corrections; verified line-by-line against the
  brief's exact list of deletions/keeps.
- Confirmed no other tracked files were accidentally modified or staged alongside Ops.nqp.
- Confirmed the make's resume behavior worked as expected (no `Configure` re-run;
  `rakudo.jar` picked up from the killed session, BOOTSTRAP v6c onward rebuilt cleanly).

## Concerns

- **`t/02-rakudo/rakuast-suspend-precomp-deps.t` fails (13/14, not 14/14).** Root-caused by
  direct reproduction: the test spawns a *fresh* `$*EXECUTABLE` subprocess via `run(...)`
  with only its own `-I` CUR/module-store flags -- it does not pass `-Ilib` through to that
  child. The child then fails to compile the fixture module's `use Test;` because this dev
  worktree was built with plain `make` (never `make install`): `install/share/perl6/core`
  has no modules installed, only an empty `short/` subdir. Manually reproducing the test's
  exact inner command:
  `./rakudo-j -I "CompUnit::Repository::SuspendTestCUR#<module-store>" -I <cur-classes> -e
  'use SuspendTestConsumer; say SuspendTestConsumer::greet()'`
  fails identically with `Could not find Test in: ...`, and **succeeds** once
  `RAKUDOLIB=<worktree>/lib` is exported into that same command -- proving the gap is
  environmental (no installed module repo for a child process to inherit), not a code
  regression from removing the JAST closures. This test file is untouched by Task 3's scope
  (`src/vm/jvm/Raku/Ops.nqp` only), so no fix was attempted here; flagging for whoever owns
  the environment/test-harness side (either install a module repo before this suite runs, or
  have the test forward `-Ilib`/`RAKUDOLIB` to its child process).
- The `cp: cannot stat eval-client.pl` warning during make is worth a one-line note upstream
  if it isn't already tracked -- it's silent/harmless here (`EXIT=0`) but could mask a
  missing artifact in `nqp/bin/` for anyone who cares about `eval-client.pl`'s presence.
