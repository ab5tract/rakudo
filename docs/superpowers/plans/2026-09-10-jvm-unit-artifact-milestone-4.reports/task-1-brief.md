### Task 1: The QAST-only driver, the unit record, the record reader

**Files:**
- Modify: `nqp/src/vm/jvm/QAST/Compiler.nqp` (whole file: `:1-3` uses; `:6-70` JAST constants; `:125-257` helpers; `:258-3490` `QAST::OperationsJAST`; `:3492-6363` `QAST::CompilerJAST`)
- Modify: `nqp/src/vm/jvm/QAST/TruffleEncoder.nqp:905-945` (the deferral), `:1-3` and `:1872` (comments naming jast2bc)
- Modify: `nqp/src/vm/jvm/HLL/Backend.nqp:1-2`, `:37-39` (`stages`), `:42-44` (`is_precomp_stage`), `:57-99` (`jast`/`classfile`/`jar`)
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/RecordReader.kt`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitWriter.kt` (add `record(SixModelObject, ThreadContext)` and `write(SixModelObject, String, ThreadContext)` overloads reading through `RecordReader`; the JAST-typed pair stays until Task 5)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/Syscalls.kt:477-491` (two new syscalls beside the old two)
- Test: `./nqp/gradlew -p nqp clean buildJvm`; `nqp/t/nqp` + `nqp/t/qast`; `tools/build/jar-census.raku`

**Interfaces:**
- Consumes: `QAST::TruffleEncoder.encode_block($node, $block, $comp, :comp_mode)` (unchanged signature; `$comp` must answer `compile_block`, `cuid_to_qbid`, `rx_descriptor`, `rx_callback_block`, `unique`, `source_for_node`); `UnitRecord`/`UnitMeta`/`BlockRec`/`CallSiteRec`/`LexValueRec` (`UnitRecord.kt`, unchanged); `EvalResult.record`.
- Produces: `QAST::UnitCompiler.unit($source, :$unit_id!)` answering a `QAST::UnitRecord`; `QAST::UnitCompiler.compile_block($node)`; NQP classes `QAST::UnitRecord`, `QAST::BlockRecord` (attribute names below are the reader's contract); Kotlin `RecordReader.read(unit: SixModelObject, tc: ThreadContext): UnitRecord`; syscalls `jvm-write-unit-record`(OBJ unit, STR filename) and `jvm-build-unit-record`(OBJ unit) -> EvalResult; Backend stages `unit jar jvm`.

Read first: `Compiler.nqp:3888-3917` (`jast`), `:4076-4330` (the CompUnit walk), `:4592-5100` (the block walk), `:3492-3790` (CodeRefBuilder, BlockInfo), `:4335-4478` (deserialization_code), `:6086-6110` (rx_descriptor), `:6256-6330` (rx_callback_block_for); `TruffleEncoder.nqp:905-945`; `UnitWriter.kt`; `JastClass.kt`, `JastMethod.kt:80-140` (what the reader ports); `Backend.nqp:37-110`.

- [ ] **Step 1: The record classes**, at the top of `Compiler.nqp` after `use QASTNode; use NQPHLL;` (the `use JASTNodes;` line goes). Attribute names are the reader's contract (Step 6); keep them exactly:

```
# The unit record: what the artifact writer reads (RecordReader.kt) --
# a unit's identity, its block table, its programs and its serialized
# context. Built by QAST::UnitCompiler.unit; no instruction list of any
# kind (docs/superpowers/specs/2026-09-10-jvm-unit-artifact-milestone-4-design.md).
class QAST::UnitRecord {
    has str $!unit_id;
    has str $!file;
    has str $!hll;
    has int $!mainline_qbid;
    has int $!entry_qbid;
    has int $!deserialize_qbid;
    has int $!load_qbid;
    has int $!serialized_count;
    has str $!sc_handle;
    has str $!sc_desc;
    has str $!serialized;        # base64 of the serialized context; '' when none
    has @!blocks;                # QAST::BlockRecord, in registration order
    has @!programs;              # engine program text per program index
    has @!callsites;             # [@arg_types, @arg_names] per call site
    has @!blockvalues;           # [qbid, name, sc_handle, sc_idx, flags] rows
    has @!nested_units;          # unit ids of nested in-memory units

    method BUILD(:$unit_id!, :$file) {
        $!unit_id := $unit_id;
        $!file := $file // '';
        $!hll := '';
        $!mainline_qbid := -1;
        $!entry_qbid := -1;
        $!deserialize_qbid := -1;
        $!load_qbid := -1;
        $!serialized_count := -1;
        $!sc_handle := '';
        $!sc_desc := '';
        $!serialized := nqp::null_s();
        @!blocks := [];
        @!programs := [];
        @!callsites := [];
        @!blockvalues := [];
        @!nested_units := [];
    }

    method add_block($b) { nqp::push(@!blocks, $b) }
    method blocks() { @!blocks }
    method unit_id() { $!unit_id }
    method file() { $!file }
    method hll(*@value) { @value ?? ($!hll := @value[0]) !! $!hll }
    method mainline_qbid(*@value) { @value ?? ($!mainline_qbid := @value[0]) !! $!mainline_qbid }
    method entry_qbid(*@value) { @value ?? ($!entry_qbid := @value[0]) !! $!entry_qbid }
    method deserialize_qbid(*@value) { @value ?? ($!deserialize_qbid := @value[0]) !! $!deserialize_qbid }
    method load_qbid(*@value) { @value ?? ($!load_qbid := @value[0]) !! $!load_qbid }
    method serialized_count(*@value) { @value ?? ($!serialized_count := @value[0]) !! $!serialized_count }
    method sc_handle(*@value) { @value ?? ($!sc_handle := @value[0]) !! $!sc_handle }
    method sc_desc(*@value) { @value ?? ($!sc_desc := @value[0]) !! $!sc_desc }
    method serialized(*@value) { @value ?? ($!serialized := @value[0]) !! $!serialized }
    method programs(*@value) { @value ?? (@!programs := @value[0]) !! @!programs }
    method callsites(*@value) { @value ?? (@!callsites := @value[0]) !! @!callsites }
    method blockvalues(*@value) { @value ?? (@!blockvalues := @value[0]) !! @!blockvalues }
    method nested_units(*@value) { @value ?? (@!nested_units := @value[0]) !! @!nested_units }
}

# One block of the unit: everything the loader needs to make its code ref
# (ProgramUnit.buildTable) -- name, cuid, outer, lexical names by type,
# handlers, flags, source position -- plus the index of its program.
class QAST::BlockRecord {
    has int $!qbid;
    has str $!name;
    has str $!cuid;              # '' on a jar-bound comp-mode block
    has int $!outer;             # qbid of the outer block; -1 = none
    has @!olex;
    has @!ilex;
    has @!nlex;
    has @!slex;
    has @!handlers;              # flat: [count, (len, fields...)*]
    has int $!has_exit_handler;
    has int $!is_thunk;
    has str $!file;
    has int $!line;
    has int $!rawline;
    has @!sections;              # [rawline, line, file] rows; empty today
    has int $!program;           # index into the unit's programs; -1 = none

    method BUILD(:$qbid!, :$name, :$cuid) {
        $!qbid := $qbid;
        $!name := $name // '';
        $!cuid := $cuid // '';
        $!outer := -1;
        @!olex := []; @!ilex := []; @!nlex := []; @!slex := [];
        @!handlers := [0];
        $!has_exit_handler := 0;
        $!is_thunk := 0;
        $!file := '';
        $!line := 0;
        $!rawline := 0;
        @!sections := [];
        $!program := -1;
    }

    method qbid() { $!qbid }
    method name() { $!name }
    method cuid() { $!cuid }
    method outer(*@value) { @value ?? ($!outer := @value[0]) !! $!outer }
    method olex(*@value) { @value ?? (@!olex := @value[0]) !! @!olex }
    method ilex(*@value) { @value ?? (@!ilex := @value[0]) !! @!ilex }
    method nlex(*@value) { @value ?? (@!nlex := @value[0]) !! @!nlex }
    method slex(*@value) { @value ?? (@!slex := @value[0]) !! @!slex }
    method handlers(*@value) { @value ?? (@!handlers := @value[0]) !! @!handlers }
    method has_exit_handler(*@value) { @value ?? ($!has_exit_handler := @value[0]) !! $!has_exit_handler }
    method is_thunk(*@value) { @value ?? ($!is_thunk := @value[0]) !! $!is_thunk }
    method file(*@value) { @value ?? ($!file := @value[0]) !! $!file }
    method line(*@value) { @value ?? ($!line := @value[0]) !! $!line }
    method rawline(*@value) { @value ?? ($!rawline := @value[0]) !! $!rawline }
    method sections() { @!sections }
    method program(*@value) { @value ?? ($!program := @value[0]) !! $!program }

    # A #line directive section: source at raw line $rawline reads as line
    # $line of $file. Only a change of mapping adds a row (ported from the
    # method carrier's cr_add_section; nothing feeds it on the engine road
    # today, kept so the reader's section fields have a source).
    method add_section($rawline, $line, $file) {
        my int $n := nqp::elems(@!sections);
        my $cur_file;
        my int $cur_delta;
        if $n {
            my @last := @!sections[$n - 1];
            return 0 if $rawline < @last[0];
            $cur_file  := @last[2];
            $cur_delta := @last[0] - @last[1];
        }
        else {
            $cur_file  := $!file;
            $cur_delta := $!rawline - $!line;
        }
        unless $file eq $cur_file && $rawline - $line == $cur_delta {
            nqp::push(@!sections, [$rawline, $line, $file]);
        }
        1
    }
}
```

- [ ] **Step 2: The registries** (`QAST::OperationsJAST` -> `QAST::OperationsJVM`, `:258-3490`). Keep: `%hll_ops`-free versions of the tables the encoder and RakuAST read -- `%CODE_CLASSLIB_OPS`, `%CODE_CLASSLIB_HLL_OPS` and their hllsym binding (`:125-128`), `classlib_record` and `jdesc` (`:129-136`; `jtype`, `typechar`, `rttype_from_typeobj`, `typeobj_from_rttype`, `@jtypes`/`@rttypes`/`@typeobjs`/`@typechars` stay because `classlib_record` and BlockInfo use them), `%core_inlinability`, `%hll_inlinability`, `set_core_op_inlinability`, `set_hll_op_inlinability`, `is_inlinable`, `%core_result_type`/`%hll_result_type` with their setters only if the encoder reads them (grep `result_type` in TruffleEncoder.nqp: none today, so delete). Rewrite the two mapping methods as registry-only:

```
    method map_classlib_core_op($op, $class, $method, @stack_in, $stack_out, :$tc, :$cont, :$inlinable = 1) {
        self.set_core_op_inlinability($op, $inlinable);
        %CODE_CLASSLIB_OPS{$op} := classlib_record($class, $method, @stack_in, $stack_out, $tc, $cont);
    }

    method map_classlib_hll_op($hll, $op, $class, $method, @stack_in, $stack_out, :$tc, :$cont, :$inlinable = 1) {
        self.set_hll_op_inlinability($hll, $op, $inlinable);
        %CODE_CLASSLIB_HLL_OPS{$hll} := nqp::hash() unless nqp::existskey(%CODE_CLASSLIB_HLL_OPS, $hll);
        %CODE_CLASSLIB_HLL_OPS{$hll}{$op} := classlib_record($class, $method, @stack_in, $stack_out, $tc, $cont);
    }

    # HLL code asks through the backend's supports-op (NativeCall probes
    # 'dispatch_v'). An op is supported when the encoder has a row for it
    # or the classlib registry maps it.
    method core_op_supported($op) {
        nqp::existskey(%CODE_CLASSLIB_OPS, $op) || QAST::TruffleEncoder.supports_op($op)
    }
```

Delete every `add_core_op(...)` call whose body is a JAST closure (50), every `map_jvm_core_op`/`map_jvm_hll_op` call and both methods, `compile_op`, `add_hll_op`, `add_hll_box`, `add_hll_unbox`, `box`, `unbox`, `op_mapper`, the `Result` class and `result`/`result_from_cf`, `%WANTMAP`, the JAST instruction constants (`:6-40`), `$INDY_SITE_BUDGET` and its comment (`:56-68`), `@store_ins`/`@load_ins`/`@dup_ins`/`@pop_ins` and their subs. KEEP every `map_classlib_core_op(...)` call (626) and `map_classlib_hll_op(...)` call: they are the registry the encoder falls back on. An op registered only by a deleted `add_core_op` closure is by construction one the encoder already has a hand row for (zero refusals since milestone 3); the `core_op_supported` change above keeps `supports-op` honest for it.

In `TruffleEncoder.nqp`, add beside `survey_cu` a knob-independent coverage query; `covered_from_table()` and the `$extra_ops` list are what `init()` uses, and `init()` only runs under the report/survey knobs, so build the set once on demand:

```
    my %op_table_covered;
    my int $op_table_built := 0;
    # Does the encoder have a row for this op (a hand row, a table row, a
    # registered desugar)? Knob-independent; the classlib registry is the
    # caller's other half (QAST::OperationsJVM.core_op_supported).
    method supports_op(str $name) {
        unless $op_table_built {
            $op_table_built := 1;
            for %emit_ops {
                my str $k := $_.key;
                my int $slash := nqp::index($k, '/');
                %op_table_covered{$slash >= 0 ?? nqp::substr($k, 0, $slash) !! $k} := 1;
            }
            for nqp::split(' ', subst_ws($extra_ops)) { %op_table_covered{$_} := 1 }
            my $dreg := nqp::gethllsym('nqp', 'CODE_OP_DESUGARS');
            unless nqp::isnull($dreg) {
                my $it := nqp::iterator($dreg);
                while $it { %op_table_covered{nqp::iterkey_s(nqp::shift($it))} := 1 }
            }
        }
        nqp::existskey(%op_table_covered, $name)
    }
```

(If `%emit_ops` is not the table's name in the current source, use the name `covered_from_table()` iterates; the shape is the point.)

- [ ] **Step 3: The driver's entry and unit walk.** Rename `class QAST::CompilerJAST` to `class QAST::UnitCompiler`. Replace `method jast($source, :$classname!, *%adverbs)` (`:3888-3917`) with:

```
    method unit($source, :$unit_id!, *%adverbs) {
        # Wrap $source in a QAST::CompUnit if it's not already a viable root node.
        unless nqp::istype($source, QAST::CompUnit) {
            my $unit := $source;
            $unit := QAST::Block.new($unit) unless nqp::istype($unit, QAST::Block);
            $source := QAST::CompUnit.new(:hll(''), $unit);
        }
        my $file := nqp::ifnull(nqp::getlexdyn('$?FILES'), "");
        my $*UNIT := QAST::UnitRecord.new(:$unit_id, :$file);
        my $*CODEREFS := CodeRefBuilder.new();
        self.compile_unit($source);
        $*UNIT
    }
```

Turn `multi method as_jast(QAST::CompUnit $cu, :$want)` (`:4076-4330`) into `method compile_unit($cu)` with these edits and nothing else changed: `self.as_jast($cu[0])` -> `self.compile_block($cu[0])`; every `self.as_jast($block)` / `($load_block)` / `($main_block)` -> `self.compile_block(...)`; every `$*JCLASS.<field>(...)` -> `$*UNIT.<field>(...)` (`hll`, `mainline_qbid`, `entry_qbid`, `deserialize_qbid`, `load_qbid`, `blockvalues`, `programs`, `callsites`); delete every `JAST::Method.new(...)` / `.append(...)` / `$*JCLASS.add_method(...)` group (the `deserializeQbid`, `loadQbid`, `main`, `entryQbid`, `hllName`, `mainlineQbid` method emissions at `:4250-4311`); `$*JCLASS.name` -> `$*UNIT.unit_id`; keep `$*EH_IDX`, `$*HLL`, `%*CUID_TO_QBID`, `$*NEXT_QBID`, `@*ENGINE_PROGRAMS`, the `NQP_CODE_RUN=0` die, `$*COMP_MODE`, `$*EMIT_CUIDS`, `%*BLOCK_LEX_VALUES`, the deserialize wrapper block construction, the orphans block, the code-object fixups, the post-deserialize tasks, the static-lexical rows, the programs/callsites hand-off and the `NQP_CODE_WHY` line. Replace the `--target=classfile` die (`:4119-4120`) with:

```
        my str $target := %*COMPILING<%?OPTIONS><target> // '';
        nqp::die("unit artifact: --target=$target is not a stage; use --target=jar (with --output) or --target=unit")
            if $target eq 'classfile' || $target eq 'jast';
```

Delete the comment block `:4102-4118` about stage0 reading the variables' presence (Task 4 makes it false) down to the two lines that die on `=0`, which stay. In `deserialization_code` (`:4335-4478`): `$*JCLASS.nested_classes(@nested_class_names)` -> `$*UNIT.nested_units(@nested_class_names)`; `$*JCLASS.serialized($serialized)` -> `$*UNIT.serialized($serialized)`; `serialized_count`/`sc_handle`/`sc_desc` likewise; every `$*JCLASS.name` -> `$*UNIT.unit_id`. `need_set_code_object`, `emit_param_tasks` (delete: JAST-only), `try_setup_args_expectation` (delete: JAST-only), `cuid_to_qbid` (keep), `unique` and `source_for_node` (keep).

- [ ] **Step 4: The block walk.** Replace `multi method as_jast(QAST::Block $node, :$want)` (`:4592-5100`) with:

```
    # Compiles one block: registers it, hands it to the encoder, records
    # what the loader needs. A block already compiled (the encoder's
    # nested-block deferral reaches a block before the tree walk does) is
    # left alone. Answers nothing: the block's program lives in
    # @*ENGINE_PROGRAMS and its record in $*UNIT.
    method compile_block($node) {
        return 0 if $*CODEREFS.know_cuid($node.cuid);
        my $outer := $*BLOCK;
        my $block := BlockInfo.new($node, $outer);

        # Catch/control handlers the block gets; the encoder registers them
        # through these two contextuals while it encodes the body.
        my @handlers;
        my $*HANDLER_IDX := 0;
        my &*REGISTER_UNWIND_HANDLER := sub ($outer, $category, :$ex_obj) {
            my $unwind := $*EH_IDX++;
            nqp::push(@handlers, [$unwind, $outer, $category,
                $ex_obj ?? $EX_UNWIND_OBJECT !! $EX_UNWIND_SIMPLE]);
            $unwind
        }
        my &*REGISTER_BLOCK_HANDLER := sub ($outer, $category, $lexidx) {
            my $unwind := $*EH_IDX++;
            nqp::push(@handlers, [$unwind, $outer, $category,
                $EX_BLOCK, $lexidx]);
            $unwind
        }

        my int $qbid := self.cuid_to_qbid($node.cuid);
        my $*BREC := QAST::BlockRecord.new(:$qbid, :name($node.name),
            :cuid($*COMP_MODE && !$*EMIT_CUIDS ?? '' !! $node.cuid));

        # Source location, so nqp::getcodelocation has something to answer
        # with at runtime. A node that knows its own file and line (RakuAST
        # origins) is believed outright; otherwise the position is computed
        # from the orig, honoring #line directives.
        if $node.node && nqp::can($node.node, 'file') && nqp::can($node.node, 'line') {
            my $loc-file := $node.node.file;
            if $loc-file {
                $*BREC.file(~$loc-file);
                $*BREC.line($node.node.line);
                $*BREC.rawline(nqp::can($node.node, 'orig-line')
                    ?? $node.node.orig-line()
                    !! nqp::can($node.node, 'orig')
                        ?? HLL::Compiler.lineof($node.node.orig(),
                               $node.node.from(), :cache(1), :directives(0))
                        !! $node.node.line);
            }
        }
        elsif $node.node && nqp::can($node.node, 'orig') {
            my $line-file := HLL::Compiler.linefileof(
                $node.node.orig(), $node.node.from(), :cache(1), :directives(1));
            my $loc-file := $line-file[1]
                || nqp::ifnull(nqp::getlexdyn('$?FILES'), '');
            if $loc-file {
                $*BREC.file(~$loc-file);
                $*BREC.line($line-file[0]);
                $*BREC.rawline(HLL::Compiler.lineof(
                    $node.node.orig(), $node.node.from(), :cache(1), :directives(0)));
            }
        }
        # The mainline (built from the comp_unit cursor before it matched)
        # and the compiler's own raw wrappers have no node to take a file
        # from; the block record carries the unit's file itself.
        $*BREC.file($*UNIT.file) if $*BREC.file eq '' && $*UNIT.file ne '';

        $*CODEREFS.register_block($*BREC, $node.cuid);
        $*BREC.outer(nqp::istype($outer, BlockInfo) ?? self.cuid_to_qbid($outer.qast.cuid) !! -1);

        {
            my $*BLOCK := $block;
            my str $prog := QAST::TruffleEncoder.encode_block($node, $block, self,
                :comp_mode($*COMP_MODE));
            if $prog eq '' {
                nqp::die('unit artifact: block '
                    ~ ($node.name eq '' ?? '<anon ' ~ $node.cuid ~ '>' !! $node.name)
                    ~ ' (cuid ' ~ $node.cuid ~ ') has no engine program;'
                    ~ ' run with NQP_CODE_BAIL=1 or NQP_CODE_WHY=1 for the reason');
            }
            my int $pidx := nqp::elems(@*ENGINE_PROGRAMS);
            nqp::push_s(@*ENGINE_PROGRAMS, $prog);
            $*BREC.program($pidx);
        }

        my @lex_names := $block.lexical_names_by_type();
        $*BREC.olex(@lex_names[$RT_OBJ]);
        $*BREC.ilex(@lex_names[$RT_INT]);
        $*BREC.nlex(@lex_names[$RT_NUM]);
        $*BREC.slex(@lex_names[$RT_STR]);

        my @flat_handlers := [nqp::elems(@handlers)];
        for @handlers {
            nqp::push(@flat_handlers, nqp::elems($_));
            for $_ { nqp::push(@flat_handlers, $_) }
        }
        $*BREC.handlers(@flat_handlers);
        $*BREC.has_exit_handler(1) if $node.has_exit_handler;
        $*BREC.is_thunk(1) if $node.is_thunk;
        $*UNIT.add_block($*BREC);
        1
    }
```

`CodeRefBuilder` (`:3492-3630`): rename `register_method($jastmeth, $cuid)` to `register_block($brec, $cuid)` storing the record instead of the method (`@!blocks`), keep `know_cuid`, `cuid_to_idx`, `get_callsite_idx`, `callsite_data`; delete `take_indy_site`, `indy_sites`, `cuid_to_jastmethname`, `cuid_to_args_expectation`, `jastify`, `callsites`. `BlockInfo` (`:3643-3790`): keep everything the encoder and the driver call (`add_param`, `add_lexical`, `add_lexicalref`, `register_lexical*`, `lexical_names_by_type`, `params`, `qast`, `outer`, the lexical type/idx/ref tables, `%*BLOCK_LEX_VALUES` rows); delete `add_local`'s temp road (`%!local2temp`, `local_info`, `locals` if only the JAST walk read them; grep `\$block\.` and `\$\*BLOCK\.` in TruffleEncoder.nqp first: today it calls only `add_lexical`, `add_lexicalref` and `signature`), `alloc_save_site`/`num_save_sites`. Delete `StackState`, `BlockTempAlloc`, `StmtTempAlloc`, `compile_all_the_stmts`, `compile_var`, every remaining `multi method as_jast`, `coerce`/`coercion`, `unwind_check`, `delimit_handler`, `engine_jast`, `savesite`, and the 20000-char refusal in `rx_descriptor` (`:6094-6104`; keep the `QAST::RxDescriptor.encode` call and the null return). In `rx_callback_block_for` (`:6260-6268`) reword the comment: the group of 12 is a plain size limit now.

- [ ] **Step 5: The encoder's deferral** (`TruffleEncoder.nqp:924-938`): the block is compiled through the driver, and there is no operand stack:

```
            unless $*CODEREFS.know_cuid($blk.cuid) {
                # An immediate block is compiled as a declaration: compiled
                # as immediate, the deferred compile would also register a
                # call into the enclosing block that nothing emits.
                my str $bt := $blk.blocktype;
                my int $imm := $bt eq 'immediate' || $bt eq 'immediate_static';
                $blk.blocktype($bt eq 'immediate' ?? 'declaration' !! 'declaration_static')
                    if $imm;
                $comp.compile_block($blk);
                $blk.blocktype($bt) if $imm;
            }
```

Reword `:686-692` (the comment naming `as_jast`) to name `compile_block`. Line 1 and `:1872` comments: drop the jast2bc mentions. Grep the encoder for `as_jast`, `JAST`, `\$\*STACK`: all three must be empty after this step.

- [ ] **Step 6: The Kotlin record reader**, `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/RecordReader.kt`:

```kotlin
package org.raku.nqp.runtime.unit

import org.raku.nqp.runtime.Base64
import org.raku.nqp.runtime.ExceptionHandling
import org.raku.nqp.runtime.Ops
import org.raku.nqp.runtime.ThreadContext
import org.raku.nqp.sixmodel.SixModelObject

/**
 * Reads a QAST::UnitRecord (the driver's output) into a UnitRecord. Reads
 * by attribute name on the object's own type, so the compiler passes no
 * type map; hints are cached per type object for the life of the reader.
 * A missing field is a hard error naming it.
 */
class RecordReader(private val tc: ThreadContext) {
    private val hints = HashMap<Pair<SixModelObject, String>, Long>()

    private fun hint(type: SixModelObject, name: String): Long =
        hints.getOrPut(type to name) { type.st.REPR.hint_for(tc, type.st, type, name) }

    private fun str(o: SixModelObject, name: String): String? =
        Ops.getattr_s(o, o.st.WHAT, name, hint(o.st.WHAT, name), tc)
    private fun int(o: SixModelObject, name: String): Int =
        Ops.getattr_i(o, o.st.WHAT, name, hint(o.st.WHAT, name), tc).toInt()
    private fun list(o: SixModelObject, name: String): SixModelObject? =
        o.get_attribute_boxed(tc, o.st.WHAT, name, hint(o.st.WHAT, name))

    private fun strs(l: SixModelObject?): Array<String> {
        if (l == null) return arrayOf()
        val n = Ops.elems(l, tc).toInt()
        return Array(n) { l.at_pos_boxed(tc, it.toLong())?.get_str(tc) ?: "" }
    }
    private fun longs(l: SixModelObject?): LongArray {
        if (l == null) return LongArray(0)
        val n = Ops.elems(l, tc).toInt()
        return LongArray(n) { l.at_pos_boxed(tc, it.toLong())!!.get_int(tc) }
    }

    fun read(unit: SixModelObject): UnitRecord {
        val unitId = str(unit, "\$!unit_id")
            ?: throw ExceptionHandling.dieInternal(tc, "unit record: no unit id")
        val nested = LinkedHashMap<String, UnitRecord>()
        for (id in strs(list(unit, "@!nested_units"))) {
            nested[id] = tc.gc.inMemoryUnitRecords[id]
                ?: throw ExceptionHandling.dieInternal(tc, "unit record: $unitId names nested unit $id, of which no record was retained")
        }
        val programs = strs(list(unit, "@!programs"))

        val blocks = ArrayList<Pair<Int, BlockRec>>()
        var maxQbid = -1
        val bl = list(unit, "@!blocks")
        val iter = Ops.iter(bl, tc)
        while (Ops.istrue(iter, tc) != 0L) {
            val b = iter.shift_boxed(tc)!!
            val qbid = int(b, "\$!qbid")
            val name = str(b, "\$!name") ?: ""
            val program = int(b, "\$!program")
            if (qbid < 0)
                throw ExceptionHandling.dieInternal(tc, "unit record: block $name has no qbid")
            if (program < 0)
                throw ExceptionHandling.dieInternal(tc, "unit record: block $name (qbid $qbid) has no program")
            if (program >= programs.size)
                throw ExceptionHandling.dieInternal(tc, "unit record: block qbid $qbid names program $program of ${programs.size}")
            val cuid = str(b, "\$!cuid")?.ifEmpty { null }
            val file = str(b, "\$!file")?.ifEmpty { null }
            val line = int(b, "\$!line")
            val rawline = int(b, "\$!rawline")
            // #line sections: [rawline, line, file] rows, split into the
            // three parallel arrays BlockRec carries; null when there are none.
            val sections = list(b, "@!sections")
            val nsec = if (sections == null) 0 else Ops.elems(sections, tc).toInt()
            var secRaw: IntArray? = null; var secLine: IntArray? = null; var secFile: Array<String>? = null
            if (nsec > 0) {
                secRaw = IntArray(nsec); secLine = IntArray(nsec); secFile = Array(nsec) { "" }
                for (i in 0 until nsec) {
                    val row = sections!!.at_pos_boxed(tc, i.toLong())!!
                    secRaw[i] = row.at_pos_boxed(tc, 0)!!.get_int(tc).toInt()
                    secLine[i] = row.at_pos_boxed(tc, 1)!!.get_int(tc).toInt()
                    secFile[i] = row.at_pos_boxed(tc, 2)!!.get_str(tc) ?: ""
                }
            }
            blocks.add(qbid to BlockRec(
                name, cuid, int(b, "\$!outer"),
                strs(list(b, "@!olex")), strs(list(b, "@!ilex")), strs(list(b, "@!nlex")), strs(list(b, "@!slex")),
                longs(list(b, "@!handlers")),
                int(b, "\$!has_exit_handler") != 0, int(b, "\$!is_thunk") != 0,
                file, line, rawline - line,
                secRaw, secLine, secFile,
                program))
            if (qbid > maxQbid) maxQbid = qbid
        }
        val table = arrayOfNulls<BlockRec>(maxQbid + 1)
        for ((q, b) in blocks) {
            if (table[q] != null)
                throw ExceptionHandling.dieInternal(tc, "unit record: two blocks with qbid $q")
            table[q] = b
        }

        val callSites = ArrayList<CallSiteRec>()
        list(unit, "@!callsites")?.let { cs ->
            val it = Ops.iter(cs, tc)
            while (Ops.istrue(it, tc) != 0L) {
                val row = it.shift_boxed(tc)!!
                val flagsObj = row.at_pos_boxed(tc, 0)!!
                val flags = ByteArray(Ops.elems(flagsObj, tc).toInt()) { i ->
                    flagsObj.at_pos_boxed(tc, i.toLong())!!.get_int(tc).toByte()
                }
                val names = strs(row.at_pos_boxed(tc, 1))
                callSites.add(CallSiteRec(flags, if (names.isEmpty()) null else names))
            }
        }
        val lexValues = ArrayList<LexValueRec>()
        list(unit, "@!blockvalues")?.let { bv ->
            val it = Ops.iter(bv, tc)
            while (Ops.istrue(it, tc) != 0L) {
                val row = it.shift_boxed(tc)!!
                lexValues.add(LexValueRec(
                    row.at_pos_boxed(tc, 0)!!.get_int(tc).toInt(),
                    row.at_pos_boxed(tc, 1)!!.get_str(tc)!!,
                    row.at_pos_boxed(tc, 2)!!.get_str(tc)!!,
                    row.at_pos_boxed(tc, 3)!!.get_int(tc).toInt(),
                    row.at_pos_boxed(tc, 4)!!.get_int(tc).toInt()))
            }
        }
        val serializedString = str(unit, "\$!serialized")
        val serialized: ByteArray? = if (serializedString == null) null else {
            val sbuf = Base64.decode(serializedString)
            ByteArray(sbuf.remaining()).also { sbuf.get(it) }
        }
        val meta = UnitMeta(
            unitId, str(unit, "\$!hll")?.ifEmpty { null } ?: "nqp",
            str(unit, "\$!sc_handle")?.ifEmpty { null }, str(unit, "\$!sc_desc")?.ifEmpty { null },
            int(unit, "\$!serialized_count"), int(unit, "\$!mainline_qbid"), int(unit, "\$!entry_qbid"),
            int(unit, "\$!deserialize_qbid"), int(unit, "\$!load_qbid"),
            callSites, table, lexValues, nested.keys.toList())
        return UnitRecord(meta, programs, serialized, nested)
    }
}
```

Check against `JastMethod.kt:112-130` how `crRawLine - crLine` and the sections were read and keep the arithmetic identical (`BlockRec.sourceLineDelta = rawline - line`). `Ops.getattr_s` on a `str` attribute holding `nqp::null_s` answers null: `$!serialized` is null when the unit has no serialized context.

- [ ] **Step 7: The writer's record entry and the two syscalls.** In `UnitWriter.kt` add, beside the JAST-typed pair (which stays until Task 5):

```kotlin
    /** The record road's entry for the driver's QAST::UnitRecord. */
    @JvmStatic
    fun record(unit: SixModelObject?, tc: ThreadContext): UnitRecord {
        if (unit == null)
            throw ExceptionHandling.dieInternal(tc, "unit record: needs a QAST::UnitRecord")
        return RecordReader(tc).read(unit)
    }

    @JvmStatic
    fun write(unit: SixModelObject?, filename: String?, tc: ThreadContext) {
        if (filename == null)
            throw ExceptionHandling.dieInternal(tc, "jvm-write-unit-record: needs a filename")
        val record = record(unit, tc)
        try {
            FileOutputStream(filename).use { UnitZip.write(record, it) }
        } catch (e: java.io.IOException) {
            throw ExceptionHandling.dieInternal(tc, e)
        }
        if (System.getenv("NQP_CODE_WHY") != null)
            System.err.println("unit artifact ${record.meta.unitId} -> $filename " +
                "(${record.programs.size} programs, ${record.meta.blocks.size} qbids, " +
                "${record.meta.callSites.size} call sites, ${record.nested.size} nested)")
    }
```

In `Syscalls.kt` after `jvm-build-unit`:

```kotlin
        /* The driver's record (QAST::UnitRecord): written as a unit
         * artifact, or built in memory for nqp::loadcompunit. The two
         * JAST-tree syscalls above serve stage0's compiler until it is
         * regenerated. */
        define("jvm-write-unit-record", OBJ, STR) { args ->
            org.raku.nqp.runtime.unit.UnitWriter.write(args.obj(0), args.str(1), args.tc)
            void
        }
        define("jvm-build-unit-record", OBJ) { args ->
            val res = org.raku.nqp.runtime.EvalResult()
            res.record = org.raku.nqp.runtime.unit.UnitWriter.record(args.obj(0), args.tc)
            obj(res)
        }
```

- [ ] **Step 8: The Backend.** `Backend.nqp`: delete `use JASTNodes;`; `method stages() { 'unit jar jvm' }`; `method is_precomp_stage($stage) { $stage eq 'unit' || $stage eq 'jar' }`; replace `jast` and `classfile` (`:57-97`) with:

```
    method unit($qast, *%adverbs) {
        my $unit_id := %*COMPILING<%?OPTIONS><javaclass> || nqp::sha1('eval-at-' ~ nqp::time() ~ $compile_count++);
        my $unit := nqp::getcomp('QAST').unit($qast, :$unit_id);
        # A jar-bound unit with an output file is written as a zip; every
        # other unit -- a script, an EVAL, a BEGIN-time unit, a
        # --target=jar with no --output -- is built in memory as a record,
        # which the jvm stage (nqp::loadcompunit) turns into a ProgramUnit.
        if %adverbs<target> eq 'jar' && %adverbs<output> {
            my str $unit_output := %adverbs<output>;
            nqp::syscall('jvm-write-unit-record', $unit, $unit_output);
            nqp::null()
        }
        else {
            nqp::syscall('jvm-build-unit-record', $unit)
        }
    }

    method jar($cu, *%adverbs) {
        $cu   # the unit stage wrote or built it; this stage names the target
    }
```

`classname` (`:50-56`) stays as the `javaclass` default-setter (rename to `unit_id` if nothing else calls it: grep `\.classname(` in nqp/src and src). `supports-op` (`:118-136`) reword its comment ("the jast stage" -> "the unit stage").

- [ ] **Step 9: Runtime jars compile**: `./nqp/gradlew -p nqp :nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars`. Expected: BUILD SUCCESSFUL, tests green.

- [ ] **Step 10: The nqp clean build** (stage0's JAST compiler builds stage1 from the new sources through the OLD syscalls; stage1 builds stage2 through the NEW ones):

```
RAKUDO_RAKUAST=1 NQP_CODE_STRICT=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/25fa1a35/tmp/t1-build.log --show-file=/home/longwalker/.claude/jobs/25fa1a35/tmp/t1-build.markers --show='> Task :stage' --show='code-bail' --show='BUILD' --show='rror' -- ./nqp/gradlew -p nqp clean buildJvm
```

Expected: EXIT=0. `raku tools/build/jar-census.raku nqp/build/jvm/share/lib/*.jar`: 11 jars, all `unit.meta`-only. A stage2 failure that names a record field is Step 1/6 disagreeing; a stage1 failure is the driver (stage0 compiles the driver's SOURCE, so an NQP syntax error shows here).

- [ ] **Step 11: t/nqp + t/qast**:

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=nqp/t/nqp -t=nqp/t/qast --jobs=3 --log-dir=/home/longwalker/.claude/jobs/25fa1a35/tmp/t1-sweep-logs --show-file=/home/longwalker/.claude/jobs/25fa1a35/tmp/t1-sweep.markers -- nqp/nqp-j-gradle
```

Expected: t/nqp 118/118 (019/063 from the nqp dir), t/qast 1/2 (01 moar-only). `t/nqp/123-unit-artifact.t` and `124-unit-record.t` are the road's own tests.

- [ ] **Step 12: Leftover grep**: `grep -n 'JAST\|as_jast\|\$\*JCLASS\|\$\*JMETH\|\$\*STACK\|jastify\|INDY_SITE' nqp/src/vm/jvm/QAST/Compiler.nqp nqp/src/vm/jvm/QAST/TruffleEncoder.nqp nqp/src/vm/jvm/HLL/Backend.nqp` must be empty (comments included: the point is no trace).

- [ ] **Step 13: Commit (nqp)**: `cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git add -A src/vm/jvm/QAST/Compiler.nqp src/vm/jvm/QAST/TruffleEncoder.nqp src/vm/jvm/HLL/Backend.nqp src/vm/jvm/runtime/org/raku/nqp/runtime/unit/RecordReader.kt src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitWriter.kt src/vm/jvm/runtime/org/raku/nqp/dispatch/Syscalls.kt && git commit -m "unit compiler: a QAST-only driver hands the writer a unit record -- no JAST tree, no operand stack, no per-block stub; the registries stay as data"` (attribution lines appended as the session requires).

---

