### Task 3: Rakudo's op file, the milestone's first make

**Files:**
- Modify: `src/vm/jvm/Raku/Ops.nqp` (782 lines: `:27` `$ALOAD_1`; `:44-52` `register_op_desugar`; `:58-107` `p6bindsig`/`p6trybindsig` closures; `:138-140` `p6box`; `:141-167` `decontrv_op` + the two `p6decontrv` registrations; `:178-196` `p6return`; `:198-206` `p6argvmarray`; `:213-225` `p6invokehandler`/`p6invokeflat`; `:245-266` `defor`; `:268-323` the four `add_hll_box` and four `add_hll_unbox`)
- Test: `perl Configure.pl --backends=jvm --gen-nqp`; `make`; `t/01-sanity`; precomp; t/03-jvm + t/10-qast

**Interfaces:**
- Consumes: `QAST::OperationsJVM.map_classlib_hll_op`, `set_hll_op_inlinability` (Task 1).
- Produces: `src/vm/jvm/Raku/Ops.nqp` = classlib mappings + desugars only; `CODE_OP_DESUGARS` hllsym unchanged; a Rakudo built on the JAST-free nqp (rakudo.jar, the three BOOTSTRAP jars, CORE.c/d/e as artifacts).

- [ ] **Step 1**: `register_op_desugar` keeps the hllsym publication and records inlinability directly:

```
my %code_op_desugars;
sub register_op_desugar($name, $desugar, :$inlinable = 1, :$compiler = 'Raku') is export {
    %code_op_desugars{$name} := $desugar;
    nqp::bindhllsym('nqp', 'CODE_OP_DESUGARS', %code_op_desugars);
    nqp::getcomp('QAST').operations.set_hll_op_inlinability($compiler, $name, $inlinable);
}
```

Delete `$ALOAD_1` and every JAST type constant no `map_classlib_hll_op` call uses (`$TYPE_P6OPS`, `$TYPE_OPS` stay: the classlib mappings name them). Delete the closures listed under Files: `p6bindsig`/`p6trybindsig` (wire ops P6BINDSIG/P6TRYBINDSIG, `TruffleEncoder.nqp:1379`), `p6box` and `p6invokehandler` (emitted by nothing in RakuAST; grep `src/Raku/ast` to confirm again), `p6decontrv`/`_6c` (`:1572`), `p6return` (`:2185`), `p6argvmarray` (`:2133`), `p6invokeflat` (`:1760`), `defor` (`:2364`), the box/unbox registrations (the encoder boxes through `hllboxtype_*`, `%hll_ops` rows at `:1398`). Keep `$trial_bind` and every `register_op_desugar(...)` call, every `map_classlib_hll_op(...)` call, `my $ops := nqp::getcomp('QAST').operations;`.

- [ ] **Step 2**: `grep -n 'JAST\|as_jast\|add_hll_op\|add_hll_box\|add_hll_unbox' src/vm/jvm/Raku/Ops.nqp` must be empty.

- [ ] **Step 3**: Configure (regenerates the runners and cleans the jvm products) then the make, as background jobs through watched-run:

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/25fa1a35/tmp/t3-configure.log -- perl Configure.pl --backends=jvm --gen-nqp
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/25fa1a35/tmp/t3-make.log --show-file=/home/longwalker/.claude/jobs/25fa1a35/tmp/t3-make.markers --show='Compiling' --show='Generating' --show='rror' --stall=1500 -- make
```

Expected: EXIT=0 both; record the make's total and CORE.c's window (the milestone's first timing point; the jast stage's ~33 s should be gone from CORE.c). `raku tools/build/jar-census.raku` over `rakudo.jar`, `blib/Perl6/BOOTSTRAP/v6c.jar` and siblings, `CORE.c.jar` and its siblings under `blib/`: all `unit.meta`-only, CORE.c with its 4 nested units.

- [ ] **Step 4**: sanity, precomp, jvm dirs:

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=t/01-sanity --jobs=2 --log-dir=/home/longwalker/.claude/jobs/25fa1a35/tmp/t3-sanity-logs --show-file=/home/longwalker/.claude/jobs/25fa1a35/tmp/t3-sanity.markers -- ./rakudo-j
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=t/03-jvm -t=t/10-qast --jobs=1 --log-dir=/home/longwalker/.claude/jobs/25fa1a35/tmp/t3-jvm-logs -- ./rakudo-j -Ilib
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=t/02-rakudo/begin-closure-doc-precomp.t -t=t/02-rakudo/begin-regex-precomp.t -t=t/02-rakudo/begin-value-container-precomp.t -t=t/02-rakudo/compose-added-method-precomp.t -t=t/02-rakudo/constant-from-gather-precomp.t -t=t/02-rakudo/core-pseudo-package-precomp.t -t=t/02-rakudo/generic-native-precomp.t -t=t/02-rakudo/grammar-named-as-core-type-precomp.t -t=t/02-rakudo/precomp-declarator-block-or-hash.t -t=t/02-rakudo/rakuast-suspend-precomp-deps.t -t=t/02-rakudo/role-whatever-param-precomp.t -t=t/02-rakudo/trait-whatever-arg-precomp.t -t=t/02-rakudo/unit-lexical-precomp-repossess.t -t=t/02-rakudo/whatever-default-precomp.t --jobs=2 --log-dir=/home/longwalker/.claude/jobs/25fa1a35/tmp/t3-precomp-logs -- ./rakudo-j -Ilib
```

Expected: 25/25; 2/2; 14/14 (clear `lib/.precomp` and `t/packages/Test-Helpers/.precomp` before the precomp run, as milestone 3 did).

- [ ] **Step 5**: Commit (rakudo): `git add src/vm/jvm/Raku/Ops.nqp && git commit -m "JVM ops: the Raku op file registers classlib mappings and desugars only; the JAST closures are gone"`.

---

