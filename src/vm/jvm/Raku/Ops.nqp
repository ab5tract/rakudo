# Type containing Raku specific ops.
my $TYPE_P6OPS := 'Lorg/raku/rakudo/RakOps;';

# Other types we'll refer to.
my $TYPE_OPS   := 'Lorg/raku/nqp/runtime/Ops;';

# Exception categories.
my $EX_CAT_NEXT    := 4;
my $EX_CAT_REDO    := 8;
my $EX_CAT_LAST    := 16;

# Opcode types.
my $RT_OBJ  := 0;
my $RT_INT  := 1;
my $RT_NUM  := 2;
my $RT_STR  := 3;
my $RT_UINT := 10;
my $RT_VOID := -1;

# Register a de-sugar from one QAST tree to another.
#
# The desugar is also published, keyed by op name, so the code engine's
# encoder can reach it: an op it has no encoding for may still be
# encodable AFTER desugaring, and the desugars that matter most to
# coverage (p6callmethodhow, p6attrinited) are registered from the legacy
# frontend, which this branch does not read. Publishing the closure means
# the encoder applies it as an opaque value -- it reproduces no logic and
# reads no source.
#
# CAUTION for any consumer: a desugar is not guaranteed pure. nqp's own
# assign_i desugar REWRITES the node it is handed ($op.op('bind'),
# $target.scope(...)) rather than returning a fresh tree, so anything that
# applies one speculatively and might then discard the result has to
# assume the original node was modified.
my %code_op_desugars;
sub register_op_desugar($name, $desugar, :$inlinable = 1, :$compiler = 'Raku') is export {
    %code_op_desugars{$name} := $desugar;
    nqp::bindhllsym('nqp', 'CODE_OP_DESUGARS', %code_op_desugars);
    nqp::getcomp('QAST').operations.set_hll_op_inlinability($compiler, $name, $inlinable);
}

# Raku opcode specific mappings.
my $ops := nqp::getcomp('QAST').operations;
$ops.map_classlib_hll_op('Raku', 'p6configposbindfailover', $TYPE_P6OPS, 'p6configposbindfailover', [$RT_OBJ, $RT_OBJ], $RT_OBJ, :tc);
$ops.map_classlib_hll_op('Raku', 'p6store', $TYPE_P6OPS, 'p6store', [$RT_OBJ, $RT_OBJ], $RT_OBJ, :tc);
$ops.map_classlib_hll_op('Raku', 'p6definite', $TYPE_P6OPS, 'p6definite', [$RT_OBJ], $RT_OBJ, :tc);
our $Binder;
proto sub trial_bind(*@args) {
    $Binder.trial_bind(|@args);
}
# A trial bind is a plain call of the &trial_bind proto above; published
# as a desugar so the code engine's encoder reaches it too (it was the
# one refusal left in the Optimizer's optimize_call, 2026-09-09).
my $trial_bind := -> $op {
    QAST::Op.new(
        :op('call'),
        QAST::WVal.new( :value(&trial_bind) ),
        |@($op)
    )
};
proto sub set_binder($b) { $Binder := $b; }
proto sub get_binder()   { $Binder }
register_op_desugar('p6setbinder', -> $op {
    QAST::Op.new(
        :op('call'),
        QAST::WVal.new( :value(&set_binder) ),
        |@($op)
    )
}, :compiler('nqp'));
register_op_desugar('p6trialbind', $trial_bind, :!inlinable, :compiler('Raku'));
register_op_desugar('p6trialbind', $trial_bind, :!inlinable, :compiler('nqp'));
$ops.map_classlib_hll_op('Raku', 'p6setitertype', $TYPE_P6OPS, 'p6setitertype', [$RT_OBJ], $RT_OBJ, :tc);
$ops.map_classlib_hll_op('Raku', 'p6setassociativetype', $TYPE_P6OPS, 'p6setassociativetype', [$RT_OBJ], $RT_OBJ, :tc);
$ops.map_classlib_hll_op('Raku', 'p6setiterbuftype', $TYPE_P6OPS, 'p6setiterbuftype', [$RT_OBJ], $RT_OBJ, :tc);
$ops.map_classlib_hll_op('Raku', 'p6isbindable', $TYPE_P6OPS, 'p6isbindable', [$RT_OBJ, $RT_OBJ], $RT_INT, :tc);
$ops.map_classlib_hll_op('Raku', 'p6bindcaptosig', $TYPE_P6OPS, 'p6bindcaptosig', [$RT_OBJ, $RT_OBJ], $RT_OBJ, :tc);
$ops.map_classlib_hll_op('Raku', 'p6typecheckrv', $TYPE_P6OPS, 'p6typecheckrv', [$RT_OBJ, $RT_OBJ, $RT_OBJ], $RT_OBJ, :tc);
$ops.map_classlib_hll_op('Raku', 'p6decontrv_rt', $TYPE_P6OPS, 'p6decontrv_rt', [$RT_OBJ, $RT_OBJ, $RT_INT], $RT_OBJ, :tc);
$ops.map_classlib_hll_op('Raku', 'p6bindwillresume', $TYPE_OPS, 'bindWillResumeOnFailure', [], $RT_INT, :tc);
$ops.map_classlib_hll_op('Raku', 'p6capturelex', $TYPE_P6OPS, 'p6capturelex', [$RT_OBJ], $RT_OBJ, :tc, :!inlinable);
$ops.map_classlib_hll_op('Raku', 'p6capturelexwhere', $TYPE_P6OPS, 'p6capturelexwhere', [$RT_OBJ], $RT_OBJ, :tc, :!inlinable);
$ops.map_classlib_hll_op('nqp', 'p6capturelexwhere', $TYPE_P6OPS, 'p6capturelexwhere', [$RT_OBJ], $RT_OBJ, :tc, :!inlinable);
$ops.map_classlib_hll_op('Raku', 'p6bindassert', $TYPE_P6OPS, 'p6bindassert', [$RT_OBJ, $RT_OBJ], $RT_OBJ, :tc);
$ops.map_classlib_hll_op('Raku', 'p6stateinit', $TYPE_P6OPS, 'p6stateinit', [], $RT_INT, :tc, :!inlinable);
$ops.map_classlib_hll_op('Raku', 'p6setpre', $TYPE_P6OPS, 'p6setpre', [], $RT_OBJ, :tc);
$ops.map_classlib_hll_op('Raku', 'p6clearpre', $TYPE_P6OPS, 'p6clearpre', [], $RT_OBJ, :tc);
$ops.map_classlib_hll_op('Raku', 'p6inpre', $TYPE_P6OPS, 'p6inpre', [], $RT_INT, :tc);
$ops.map_classlib_hll_op('Raku', 'p6setfirstflag', $TYPE_P6OPS, 'p6setfirstflag', [$RT_OBJ], $RT_OBJ, :tc);
$ops.map_classlib_hll_op('Raku', 'p6takefirstflag', $TYPE_P6OPS, 'p6takefirstflag', [], $RT_INT, :tc);
$ops.map_classlib_hll_op('Raku', 'p6getouterctx', $TYPE_P6OPS, 'p6getouterctx', [$RT_OBJ], $RT_OBJ, :tc, :!inlinable);
$ops.map_classlib_hll_op('Raku', 'p6bindattrinvres', $TYPE_P6OPS, 'p6bindattrinvres', [$RT_OBJ, $RT_OBJ, $RT_STR, $RT_OBJ], $RT_OBJ, :tc);
$ops.map_classlib_hll_op('Raku', 'p6finddispatcher', $TYPE_P6OPS, 'p6finddispatcher', [$RT_STR], $RT_OBJ, :tc);
$ops.map_classlib_hll_op('Raku', 'p6argsfordispatcher', $TYPE_P6OPS, 'p6argsfordispatcher', [$RT_OBJ], $RT_OBJ, :tc);
$ops.map_classlib_hll_op('Raku', 'p6setautothreader', $TYPE_P6OPS, 'p6setautothreader', [$RT_OBJ], $RT_OBJ, :tc);
$ops.map_classlib_hll_op('Raku', 'tclc', $TYPE_P6OPS, 'tclc', [$RT_STR], $RT_STR, :tc);
$ops.map_classlib_hll_op('Raku', 'p6staticouter', $TYPE_P6OPS, 'p6staticouter', [$RT_OBJ], $RT_OBJ, :tc);
# Sinking is a runtime helper rather than an inline `can`/`callmethod sink`
# pair: the inline form costs one invokedynamic call site per sunk statement,
# and the core setting has more of those than a class may hold. Like MoarVM's,
# it yields the sinkee, which emitters rely on -- a `for` statement modifier
# hands the sunk thunk on to the loop, which reaches into it for `$!do`.
$ops.map_classlib_hll_op('Raku', 'p6sink', $TYPE_P6OPS, 'p6sink', [$RT_OBJ], $RT_OBJ, :tc);

# Make some of them also available from NQP land, since we use them in the
# metamodel and bootstrap.
$ops.map_classlib_hll_op('nqp', 'p6init', $TYPE_P6OPS, 'p6init', [], $RT_OBJ, :tc);
$ops.map_classlib_hll_op('nqp', 'p6settypes', $TYPE_P6OPS, 'p6settypes', [$RT_OBJ], $RT_OBJ, :tc);
$ops.map_classlib_hll_op('nqp', 'p6setitertype', $TYPE_P6OPS, 'p6setitertype', [$RT_OBJ], $RT_OBJ, :tc);
$ops.map_classlib_hll_op('nqp', 'p6setiterbuftype', $TYPE_P6OPS, 'p6setiterbuftype', [$RT_OBJ], $RT_OBJ, :tc);
$ops.map_classlib_hll_op('nqp', 'p6isbindable', $TYPE_P6OPS, 'p6isbindable', [$RT_OBJ, $RT_OBJ], $RT_INT, :tc);
# The bind_error handler the HLL config registers is bootstrap code, so it
# needs this under the nqp HLL as well as the Raku one.
$ops.map_classlib_hll_op('nqp', 'p6bindfailerror', $TYPE_P6OPS, 'p6bindfailerror', [$RT_OBJ, $RT_OBJ], $RT_OBJ, :tc);
$ops.map_classlib_hll_op('Raku', 'p6bindfailerror', $TYPE_P6OPS, 'p6bindfailerror', [$RT_OBJ, $RT_OBJ], $RT_OBJ, :tc);
$ops.map_classlib_hll_op('nqp', 'p6inpre', $TYPE_P6OPS, 'p6inpre', [], $RT_INT, :tc);
$ops.map_classlib_hll_op('nqp', 'jvmrakudointerop', $TYPE_P6OPS, 'jvmrakudointerop', [], $RT_OBJ, :tc);
$ops.map_classlib_hll_op('Raku', 'jvmrakudointerop', $TYPE_P6OPS, 'jvmrakudointerop', [], $RT_OBJ, :tc);
$ops.map_classlib_hll_op('nqp', 'p6captureouters2', $TYPE_P6OPS, 'p6captureouters2', [$RT_OBJ, $RT_OBJ], $RT_OBJ, :tc, :!inlinable);
# --- BEGIN op desugars moved from the legacy Perl6::Actions (batch 27) ---
# Self-contained QAST desugars the RakuAST frontend emits; they lived
# in Perl6::Actions (no longer compiled). register_op_desugar (above)
# stores each for the encoder AND records its HLL inlinability.
register_op_desugar('p6box_i', -> $qast {
    QAST::Op.new( :op('box_i'), $qast[0], QAST::Op.new( :op('hllboxtype_i') ) )
});
register_op_desugar('p6box_n', -> $qast {
    QAST::Op.new( :op('box_n'), $qast[0], QAST::Op.new( :op('hllboxtype_n') ) )
});
register_op_desugar('p6box_s', -> $qast {
    QAST::Op.new( :op('box_s'), $qast[0], QAST::Op.new( :op('hllboxtype_s') ) )
});
register_op_desugar('p6box_u', -> $qast {
    QAST::Op.new( :op('box_u'), $qast[0], QAST::Op.new( :op('hllboxtype_i') ) )
});
register_op_desugar('p6reprname', -> $qast {
    QAST::Op.new( :op('box_s'), QAST::Op.new( :op('reprname'), $qast[0]), QAST::Op.new( :op('hllboxtype_s') ) )
});
register_op_desugar('p6callmethodhow', -> $qast {
    $qast   := QAST::Op.new(:op<callmethod>, :name($qast.name), |$qast.list);
    my $inv := $qast.shift;
    my $tmp := QAST::Node.unique('how_invocant');
    $qast.unshift(QAST::Var.new( :name($tmp), :scope('local') ));
    $qast.unshift(QAST::Op.new(
        :op('how'),
        QAST::Var.new( :name($tmp), :scope('local') )
    ));
    QAST::Stmts.new(
        QAST::Op.new(
            :op('bind'),
            QAST::Var.new( :name($tmp), :scope('local'), :decl('var') ),
            $inv
        ),
        QAST::Op.new( :op('hllize'), $qast )
    )
});
register_op_desugar('p6fatalize', -> $qast {
    my $tmp := QAST::Node.unique('fatalizee');
    QAST::Stmts.new(
        :resultchild(0),
        QAST::Op.new(
            :op('bind'),
            QAST::Var.new( :name($tmp), :scope('local'), :decl('var') ),
            $qast[0]
        ),
        QAST::Op.new(
            :op('if'),
            QAST::Op.new(
                :op('istype'),
                QAST::Var.new( :name($tmp), :scope('local') ),
                $qast[1],
            ),
            QAST::Op.new(
                :op('callmethod'), :name('sink'),
                QAST::Var.new( :name($tmp), :scope('local') )
            )
        ))
});
register_op_desugar('p6for', -> $qast {
    # Figure out the execution mode.
    my $mode := $qast.ann('mode') || 'serial';
    my $after-mode;
    if $mode eq 'lazy' {
        $after-mode := 'lazy';
        $mode := 'serial';
    }
    else {
        $after-mode := $qast.sunk ?? 'sink' !! 'eager';
    }

    my $cond := $qast[0];
    my $block := $qast[1];
    my $label := $qast[2];
    my $for-list-name := QAST::Node.unique('for-list');
    my $call := QAST::Op.new(
        :op('if'),
        QAST::Op.new( :op('iscont'), QAST::Var.new( :name($for-list-name), :scope('local') ) ),
        QAST::Op.new(
            :op<callmethod>, :name<map>, :node($qast),
            QAST::Var.new( :name($for-list-name), :scope('local') ),
            $block,
            QAST::IVal.new( :value(1), :named('item') )
        ),
        QAST::Op.new(
            :op<callmethod>, :name<map>, :node($qast),
            QAST::Op.new(
                :op<callmethod>, :name($mode), :node($qast),
                QAST::Var.new( :name($for-list-name), :scope('local') )
            ),
            $block
        )
    );
    if $label {
        $call[1].push($label);
        $call[2].push($label);
    }
    my $bind := QAST::Op.new(
        :op('bind'),
        QAST::Var.new( :name($for-list-name), :scope('local'), :decl('var') ),
        $cond,
    );
    QAST::Stmts.new(
        $bind,
        QAST::Op.new( :op<callmethod>, :name($after-mode), $call )
    );
});
register_op_desugar('p6forstmt', -> $qast {
    my $for-target-name := QAST::Node.unique('for_target');
    my $for-target := QAST::Op.new(
        :op('bind'),
        QAST::Var.new( :name($for-target-name), :scope('local'), :decl('var') ),
        $qast[0]
    );

    my $iterator-name := QAST::Node.unique('for_iterator');
    my $iterator := QAST::Op.new(
        :op('bind'),
        QAST::Var.new( :name($iterator-name), :scope('local'), :decl('var') ),
        QAST::Op.new(
            :op('callmethod'), :name('iterator'),
            QAST::Op.new(
                :op('if'),
                QAST::Op.new(
                    :op('iscont'),
                    QAST::Var.new( :name($for-target-name), :scope('local') )
                ),
                QAST::Op.new(
                    :op('callstatic'), :name('&infix:<,>'),
                    QAST::Var.new( :name($for-target-name), :scope('local') )
                ),
                QAST::Var.new( :name($for-target-name), :scope('local') )
            )));

    my $iteration-end-name := QAST::Node.unique('for_iterationend');
    my $iteration-end := QAST::Op.new(
        :op('bind'),
        QAST::Var.new( :name($iteration-end-name), :scope('local'), :decl('var') ),
        QAST::WVal.new( :value($qast.ann('IterationEnd')) )
    );

    my $block-name := QAST::Node.unique('for_block');
    my $block := QAST::Op.new(
        :op('bind'),
        QAST::Var.new( :name($block-name), :scope('local'), :decl('var') ),
        QAST::Op.new(
            :op('getattr'),
            $qast[1],
            QAST::WVal.new( :value($qast.ann('Code')) ),
            QAST::SVal.new( :value('$!do') )
        )
    );

    my $iter-val-name := QAST::Node.unique('for_iterval');
    my $loop := QAST::Op.new(
        :op('until'),
        QAST::Op.new(
            :op('eqaddr'),
            QAST::Op.new(
                :op('decont'),
                QAST::Op.new(
                    :op('bind'),
                    QAST::Var.new( :name($iter-val-name), :scope('local'), :decl('var') ),
                    QAST::Op.new(
                        :op('callmethod'), :name('pull-one'),
                        QAST::Var.new( :name($iterator-name), :scope('local') )
                    )
                )
            ),
            QAST::Var.new( :name($iteration-end-name), :scope('local') )
        ),
        QAST::Op.new(
            :op('call'),
            QAST::Var.new( :name($block-name), :scope('local') ),
            QAST::Var.new( :name($iter-val-name), :scope('local') )
        ));
    if $qast[2] {
        $loop.push($qast[2]);
    }

    QAST::Stmts.new(
        $for-target,
        $iterator,
        $iteration-end,
        $block,
        $loop,
        QAST::WVal.new( :value($qast.ann('Nil')) )
    )
});
register_op_desugar('p6scalarfromdesc', -> $qast {
    my $desc := QAST::Node.unique('descriptor');
    my $Scalar := QAST::WVal.new( :value(nqp::gethllsym('Raku', 'Scalar')) );
    my $default_cont_spec := nqp::gethllsym('Raku', 'default_cont_spec');
    QAST::Stmt.new(
        QAST::Op.new(
            :op('bind'),
            QAST::Var.new( :name($desc), :scope('local'), :decl('var') ),
            $qast[0]
        ),
        QAST::Op.new(
            :op('unless'),
            QAST::Op.new(
                :op('isconcrete'),
                QAST::Var.new( :name($desc), :scope('local') ),
            ),
            QAST::Op.new(
                :op('bind'),
                QAST::Var.new( :name($desc), :scope('local') ),
                QAST::WVal.new( :value($default_cont_spec) )
            )
        ),
        QAST::Op.new(
            :op('p6bindattrinvres'),
            QAST::Op.new(
                :op('p6bindattrinvres'),
                QAST::Op.new( :op('create'), $Scalar ),
                $Scalar,
                QAST::SVal.new( :value('$!descriptor') ),
                QAST::Var.new( :name($desc), :scope('local') )
            ),
            $Scalar,
            QAST::SVal.new( :value('$!value') ),
            QAST::Op.new(
                :op('callmethod'), :name('default'),
                QAST::Var.new( :name($desc), :scope('local') )
            )
        )
    )
});
# The "certain" variant is allowed to assume the container descriptor is
# reliably provided, so need not map it to the default one. Ideally, we'll
# eventually have everything using this version of the op.
register_op_desugar('p6scalarfromcertaindesc', -> $qast {
    my $desc := QAST::Node.unique('descriptor');
    my $Scalar := QAST::WVal.new( :value(nqp::gethllsym('Raku', 'Scalar')) );
    QAST::Stmt.new(
        QAST::Op.new(
            :op('bind'),
            QAST::Var.new( :name($desc), :scope('local'), :decl('var') ),
            $qast[0]
        ),
        QAST::Op.new(
            :op('p6bindattrinvres'),
            QAST::Op.new(
                :op('p6bindattrinvres'),
                QAST::Op.new( :op('create'), $Scalar ),
                $Scalar,
                QAST::SVal.new( :value('$!descriptor') ),
                QAST::Var.new( :name($desc), :scope('local') )
            ),
            $Scalar,
            QAST::SVal.new( :value('$!value') ),
            QAST::Op.new(
                :op('callmethod'), :name('default'),
                QAST::Var.new( :name($desc), :scope('local') )
            )
        )
    )
});
register_op_desugar('p6scalarwithvalue', -> $qast {
    my $Scalar := QAST::WVal.new( :value(nqp::gethllsym('Raku', 'Scalar')) );
    QAST::Op.new(
        :op('p6assign'),
        QAST::Op.new(
            :op('p6bindattrinvres'),
            QAST::Op.new( :op('create'), $Scalar ),
            $Scalar,
            QAST::SVal.new( :value('$!descriptor') ),
            $qast[0]
        ),
        $qast[1]
    )
});
register_op_desugar('p6recont_ro', -> $qast {
    my $result := QAST::Node.unique('result');
    my $Scalar := QAST::WVal.new( :value(nqp::gethllsym('Raku', 'Scalar')) );
    QAST::Stmt.new(
        QAST::Op.new(
            :op('bind'),
            QAST::Var.new( :name($result), :scope('local'), :decl('var') ),
            $qast[0]
        ),
        QAST::Op.new(
            :op('if'),
            QAST::Op.new(
                :op('if'),
                QAST::Op.new(
                    :op('isconcrete_nd'),
                    QAST::Var.new( :name($result), :scope('local') )
                ),
                QAST::Op.new(
                    :op('isrwcont'),
                    QAST::Var.new( :name($result), :scope('local') )
                )
            ),
            QAST::Op.new(
                :op('p6bindattrinvres'),
                QAST::Op.new( :op('create'), $Scalar ),
                $Scalar,
                QAST::SVal.new( :value('$!value') ),
                QAST::Op.new(
                    :op('decont'),
                    QAST::Var.new( :name($result), :scope('local') )
                )
            ),
            QAST::Var.new( :name($result), :scope('local') )
        )
    )
});
register_op_desugar('p6var', -> $qast {
    my $result := QAST::Node.unique('result');
    my $Scalar := QAST::WVal.new( :value(nqp::gethllsym('Raku', 'Scalar')) );
    my $ScalarVAR := QAST::WVal.new( :value(nqp::gethllsym('Raku', 'ScalarVAR')) );
    QAST::Stmt.new(
        QAST::Op.new(
            :op('bind'),
            QAST::Var.new( :name($result), :scope('local'), :decl('var') ),
            $qast[0]
        ),
        QAST::Op.new(
            :op('if'),
            QAST::Op.new(
                :op('if'),
                QAST::Op.new(
                    :op('isconcrete_nd'),
                    QAST::Var.new( :name($result), :scope('local') )
                ),
                QAST::Op.new(
                    :op('iscont'),
                    QAST::Var.new( :name($result), :scope('local') )
                )
            ),
            QAST::Op.new(
                :op('p6bindattrinvres'),
                QAST::Op.new( :op('create'), $ScalarVAR ),
                $Scalar,
                QAST::SVal.new( :value('$!value') ),
                QAST::Var.new( :name($result), :scope('local') )
            ),
            QAST::Var.new( :name($result), :scope('local') )
        )
    )
});
register_op_desugar('time_i', -> $qast {
    QAST::Op.new( :op('div_i'), QAST::Op.new( :op('time' ) ), QAST::IVal.new( :value(1000000000) ) )
});
register_op_desugar('time_n', -> $qast {
    QAST::Op.new( :op('div_n'), QAST::Op.new( :op('time' ) ), QAST::NVal.new( :value(1000000000e0) ) )
});
    register_op_desugar('p6decontrv_internal', -> $qast {
#?if !js
        QAST::Op.new(:op('dispatch'),
          QAST::SVal.new(
            :value($qast[1] eq '6c' ?? 'raku-rv-decont-6c' !! 'raku-rv-decont')
          ),
          QAST::Op.new(:op('p6box'),
            QAST::Op.new(:op('wantdecont'), $qast[0])
          )
        )
#?endif
#?if js
        my $result   := QAST::Node.unique('result');
        my $Scalar   := QAST::WVal.new(:value(nqp::gethllsym('Raku','Scalar')));
        my $Iterable := QAST::WVal.new(:value(nqp::gethllsym('Raku','Iterable')));
        QAST::Stmt.new(
          QAST::Op.new(:op('bind'),
            QAST::Var.new( :name($result), :scope('local'), :decl('var') ),
            QAST::Op.new( :op('wantdecont'), $qast[0] )
          ),
          QAST::Op.new(:op('if'),
            # If it's a container...
            QAST::Op.new(:op('if'),
              QAST::Op.new(:op('isconcrete_nd'),
                QAST::Var.new(:name($result),:scope('local'))
              ),
              QAST::Op.new(:op('iscont'),
                QAST::Var.new(:name($result),:scope('local'))
              )
            ),
            # It's a container; is it an rw one?
            QAST::Op.new(:op('if'),
              QAST::Op.new(:op('isrwcont'),
                QAST::Var.new(:name($result),:scope('local'))
              ),
              # Yes; does it contain an Iterable? If so, rewrap it. If
              # not, strip it.
              QAST::Op.new(:op('if'),
                QAST::Op.new(:op('istype'),
                  QAST::Var.new(:name($result),:scope('local')),
                  $Iterable
                ),
                QAST::Op.new(:op('p6bindattrinvres'),
                  QAST::Op.new(:op('create'),$Scalar),
                  $Scalar,
                  QAST::SVal.new(:value('$!value')),
                  QAST::Op.new(:op('decont'),
                    QAST::Var.new( :name($result),:scope('local'))
                  )
                ),
                QAST::Op.new(:op('decont'),
                  QAST::Var.new(:name($result),:scope('local'))
                )
              ),
              # Not rw, so leave container in place.
              QAST::Var.new(:name($result),:scope('local'))
            ),
            # Not a container, so just hand back value
            QAST::Var.new(:name($result),:scope('local'))
          )
        )
#?endif
    });
    register_op_desugar('p6assign', -> $qast {
#?if !js
        my $cont := QAST::Node.unique('assign_cont');
        QAST::Stmts.new(
          QAST::Op.new(
            :op('bind'),
            QAST::Var.new( :name($cont), :scope('local'), :decl('var') ),
            $qast[0]
          ),
          QAST::Op.new(
            :op('dispatch'),
            QAST::SVal.new( :value('raku-assign') ),
            QAST::Var.new( :name($cont), :scope('local') ),
            QAST::Op.new( :op('decont'), $qast[1] )
          ),
          QAST::Var.new( :name($cont), :scope('local') )
        )
#?endif
#?if js
        QAST::Op.new( :op('assign'), $qast[0], $qast[1] )
#?endif
    });
    register_op_desugar('p6attrinited', -> $qast {
#?if !js
        QAST::Op.new(
          :op('dispatch'), :returns(int),
          QAST::SVal.new( :value('raku-is-attr-inited') ),
          $qast[0]
        );
#?endif
#?if js
        QAST::Op.new(
          :op('callmethod'), :name('check'),
          QAST::WVal.new(
            :value(nqp::gethllsym('Raku', 'UninitializedAttributeChecker'))
          ),
          $qast[0]
        )
#?endif
    });
# --- END op desugars moved from the legacy Perl6::Actions ---

# vim: expandtab sw=4
