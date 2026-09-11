# JVM Unit Artifact, Milestone 4: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The class road and JAST are gone from nqp and Rakudo on the JVM: a QAST-only driver hands the artifact writer a unit record, stage0 is regenerated as artifacts, the runtime's class-road writer and loaders and the JAST layer are deleted, the interop adaptors run on plain method handles, and the three runtime gaps carried from milestone 3 are worked, time-boxed.

**Architecture:** The driver goes first (Tasks 1-3) so that one stage0 regeneration (Task 4) yields a JAST-free bootstrap compiler; the runtime deletions (Tasks 5-6) follow with nothing left to serve; the adaptors (Task 7) move off the reflective code-ref road onto the `getCodeRefs()` hook KnowHOWMethods already uses; the three gaps (Tasks 8-10) are runtime work with targeted gates; Task 11 is the milestone gate, docs, ledger and handoff. Every step is gated by the cheapest build that proves it, forward only.

**Tech Stack:** NQP (Compiler.nqp, TruffleEncoder.nqp, HLL/Backend.nqp, NQP/Ops.nqp, Raku/Ops.nqp), Kotlin 2.4 (nqp-runtime, nqp-truffle), Java (NqpCodeEngine, NqpRootNode, NqpCont: the engine's DSL-owned files), gradle (build.gradle.kts, buildSrc), RakuAST (`#?if jvm` only), Raku tooling (watched-run.raku, evalserver-sweep.raku, jar-census.raku).

**Spec:** `docs/superpowers/specs/2026-09-10-jvm-unit-artifact-milestone-4-design.md` (rakudo worktree, committed as `e4a1811207`). Sections 1-7 map onto the tasks below; the spec's "Open at plan time" list is settled in "Plan rulings" here.

## Global Constraints

- Two git trees: rakudo worktree root `/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records` (branch `worktree-jesp-direct-lazy-records`) and the nested `nqp/` tree (branch `jesp-direct-lazy-records`). Every nqp path below is under `nqp/`; nqp git commands run as `cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git ...` in their own shell call. The worktree guard refuses `git -C nqp`, `/usr/bin/time`, heredocs, shell loops over computed values, and a computed variable standing where an option could be: spell paths out. Label every hash by tree. Start of this plan: rakudo `e4a1811207`, nqp `55bdee5b7`.
- Kotlin, never Java, for new code. The Java edits here (`NqpCodeEngine.java`, `NqpRootNode.java`, `NqpCont.java`, `NqpOps.java` in Task 9) extend files the Truffle DSL processor owns: the stated deal-breaker case. `LibraryLoader.java` is deleted and its survivors ported to Kotlin (Task 6); `EvalServer.java` keeps its language (an edit, not new code).
- Every diagnostic print is env-gated (`System.getenv(...)` / `nqp::getenvhash()`); never a bare print.
- Wire changes stay additive; this plan adds NO wire op. The unit meta format version stays 1 (Task 1 changes no field of `UnitRecord.kt`).
- Framing is by byte, never by grapheme.
- Runtime-jar-only changes rebuild with `./nqp/gradlew -p nqp :nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars` (~10-30 s) from the rakudo worktree root; a change under `nqp/src/vm/jvm/QAST`, `nqp/src/vm/jvm/HLL`, `nqp/src/vm/jvm/NQP` or `nqp/src/HLL` needs `./nqp/gradlew -p nqp clean buildJvm` (~4 min). Restart eval servers after any runtime jar rebuild.
- Runs longer than 30 s go through `raku tools/build/watched-run.raku` (`--log=`, `--show=` literals, `--show-file=PATH` for the markers file, `--max=SECONDS`, `-t=DIR --jobs=N`), as a plain background job (`run_in_background`, never `setsid`/`nohup`); look for its `=== EXIT=<n> verdict=<v> elapsed=<s>s ===` line. Progress reported every 90 s during a build or sweep. Logs go under the executing session's job dir; this plan writes `/home/longwalker/.claude/jobs/25fa1a35/tmp/` and an executor in another session substitutes its own `$CLAUDE_JOB_DIR/tmp`.
- `RAKUDO_RAKUAST=1` on every build, test and run. `NQP_CODE_RUN` / `NQP_CODE_PRECOMP` are NOT set anywhere (not knobs; the compiler dies on `=0`). `NQP_CODE_STRICT=1` on nqp builds (a refusal is a build failure).
- `java` is Oracle GraalVM 25.2.4.
- One compile per change (forward only): no A/B builds, no knob-off comparison. A build that breaks is fixed by amending the same commit, not by an extra "isolation" build. Baseline at the start (milestone 3, sleep suppressed): nqp `clean buildJvm` 222 s; t/nqp 118/118 (019/063 from the nqp dir); Rakudo `make` 1154 s (CORE.c 475 s); `t/01-sanity` 25/25 in 161 s at 2 jobs; precomp 14/14.
- The in-tree runners have no installed module repo: any Raku test with a `use` runs as `./rakudo-j -Ilib`.
- Tooling in Raku, never Python or shell scripts.
- No t/spec (user rule: not until t/ runs under two hours). The two S04-phasers files in Task 8 run by path from the main checkout's `/home/longwalker/code/raku/x.core/rakudo/t/spec/`, read-only there.

## User decisions (2026-09-10, brainstorm)

1. Milestone gate = milestone 3's gate (t/nqp, `t/01-sanity`, precomp, t/03-jvm, one make-driven t/ sweep); no t/spec.
2. The interop adaptors are rewritten here (item 9's adaptor half).
3. All three carried gaps are worked, gated by `t/01-sanity` plus a handful of named test files, never directories.
4. QAST-only driver first, so nothing JAST-named survives; one stage0 regeneration.

## Plan rulings (the spec's open items, settled)

- Names: `QAST::UnitCompiler` (was `QAST::CompilerJAST`), `QAST::OperationsJVM` (was `QAST::OperationsJAST`), `QAST::UnitRecord`, `QAST::BlockRecord`; Kotlin `org.raku.nqp.runtime.unit.RecordReader`, `org.raku.nqp.runtime.AdaptorUnit`, `org.raku.nqp.runtime.BytecodeVersion`.
- `add_hll_op` / `add_core_op` / `add_hll_box` / `add_hll_unbox` have no non-JAST consumer: deleted. `is_inlinable` HAS one (`src/Raku/ast/code.rakumod:3301`): the inlinability tables stay in `QAST::OperationsJVM`, fed by `map_classlib_*_op(:inlinable)` and by `register_op_desugar(:inlinable)` calling `set_hll_op_inlinability` directly.
- The regex callback grouping (`rx_callback_block_for`, `$GROUP := 12`) stays as a plain size limit; its comment loses the 64 KB reason.
- The adaptors' `constants` handoff stays a reflective static field write on the plain generated class (`finishClass`, unchanged).
- The resume-value fix needs no wire field: the suspend token carries a finisher (Task 9).
- The write/build syscalls get NEW names (`jvm-write-unit-record`, `jvm-build-unit-record`) in Task 1; the old names keep serving stage0's JAST tree until Task 5 deletes them. No syscall changes shape.
- The nqp Makefile road (`nqp/tools/templates/jvm/Makefile.in`) is edited for consistency (JASTNodes, jast2bc lines) but NOT verified: gradle is the build.

## Known gaps recorded, not worked (unless a task below names them)

- Anonymous-block naming in backtraces (deferred since milestone 3).
- `t/12-rakuast` is not in `tools/templates/common_test_dirs`; not swept.
- `nqp/t/qast/01-qast.t` is moar-only (known red); `t/nqp/019`, `063` pass only from the nqp dir.
- The corekeys/settingkeys cluster in t/02-rakudo (NFG expectation) stays red.

## File structure

nqp compiler (`nqp/src/vm/jvm/`):
- `QAST/Compiler.nqp` (6363 lines, `use JASTNodes` + `QAST::OperationsJAST` + `QAST::CompilerJAST`) becomes: the two record classes, `QAST::OperationsJVM` (registries only), `QAST::UnitCompiler` (the driver). Expected size ~1400 lines.
- `QAST/JASTNodes.nqp`: deleted (Task 2).
- `QAST/TruffleEncoder.nqp`: two hook edits (the nested-block deferral; the `run_init`-independent `supports_op`).
- `HLL/Backend.nqp`: stages `unit jar jvm`; no `use JASTNodes`.
- `NQP/Ops.nqp`: JAST closures gone.

nqp runtime (`nqp/src/vm/jvm/runtime/org/raku/nqp/`):
- `runtime/unit/RecordReader.kt` (new, Task 1): reads a `QAST::UnitRecord` object into `UnitRecord`.
- `runtime/unit/UnitWriter.kt`: takes the record object (Task 1); the JAST entry deleted (Task 5).
- `dispatch/Syscalls.kt`: two new syscalls (Task 1); two old ones deleted (Task 5).
- `jast2bc/*` deleted, `BytecodeVersion` moved to `runtime/` (Task 5).
- `runtime/Ops.kt`, `runtime/EvalResult.kt`, `runtime/CompilationUnit.kt`, `runtime/IndyBootstrap.kt`, `runtime/CodeRefAnnotation.kt`, `runtime/GlobalContext.kt`, `tools/EvalServer.java` (Task 5).
- `runtime/LibraryLoader.java` deleted; `runtime/unit/UnitLoader.kt` grows the loader API (Task 6).
- `runtime/AdaptorUnit.kt` (new), `runtime/BootJavaInterop.kt` (Task 7); rakudo `src/vm/jvm/runtime/org/raku/rakudo/RakudoJavaInterop.kt` (Task 7).
- `runtime/CallFrame.kt`, `runtime/ExceptionHandling.kt` (Task 8).

engine (`nqp/nqp-truffle/src/main/`): `java/.../NqpCont.java`, `NqpOps.java`, `NqpCodeEngine.java`, `NqpRootNode.java`, `kotlin/.../NqpTypeOps.kt` (Task 9).

build: `nqp/build.gradle.kts` (stage list, stage compile entry, `jBootstrapFiles`), `nqp/buildSrc/src/main/kotlin/NqpSources.kt`, `nqp/tools/templates/jvm/Makefile.in`, `nqp/src/vm/jvm/stage0/*.jar` (Task 4), `nqp/docs/gradle-jvm-build.md`.

rakudo: `src/vm/jvm/Raku/Ops.nqp` (Task 3), `src/Raku/ast/code.rakumod` (Task 10, `#?if jvm`), docs (Task 11).

tests: `nqp/t/jvm/09-autosplit.t` deleted (Task 5); `t/03-jvm/01-interop.t` (Task 7); the two S04-phasers files and the probe (Tasks 8-9); the two t/02-rakudo files (Task 10).

---

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

### Task 2: The JASTNodes module, the stage lists, nqp's own JAST closures

**Files:**
- Delete: `nqp/src/vm/jvm/QAST/JASTNodes.nqp`
- Modify: `nqp/build.gradle.kts:56` (the gen-cat `lists` map), `:148-149` (`JastNodes` stage target), `:150-156` (the `Hll` and `Qast` `deps` lists), `:434-442` (`jBootstrapFiles` copies whatever `stageTargets` lists: unchanged, but see Task 4)
- Modify: `nqp/buildSrc/src/main/kotlin/NqpSources.kt:84` (`JASTNODES`)
- Modify: `nqp/tools/templates/jvm/Makefile.in:41` (`ASTNODES_SOURCES`)
- Modify: `nqp/src/vm/jvm/NQP/Ops.nqp` (177 lines; the 8 `add_hll_op` and 4 `add_hll_unbox` closures and their helpers)
- Test: `./nqp/gradlew -p nqp checkSourceLists genCatParityCheck`; `clean buildJvm`; t/nqp

**Interfaces:**
- Consumes: Task 1's compiler (nothing `use`s JASTNodes any more).
- Produces: `stageTargets` without `JastNodes`; nine stage jars (`JASTNodes.jar` gone from `build/jvm/stage1`, `stage2`, `share/lib`); `nqp/src/vm/jvm/NQP/Ops.nqp` with no `JAST::` construction.

- [ ] **Step 1**: `grep -rn 'JASTNodes\|JAST::' nqp/src nqp/t nqp/tools nqp/buildSrc nqp/build.gradle.kts nqp/docs src/vm/jvm src/Raku src/main.nqp tools` and record the hits: the expected ones are the six files above plus rakudo's `src/vm/jvm/Raku/Ops.nqp` (Task 3) and docs (Task 11). Anything else is a finding for the report.

- [ ] **Step 2**: delete the module and its build entries: `git rm nqp/src/vm/jvm/QAST/JASTNodes.nqp` (from the nqp dir); in `build.gradle.kts` remove the `"JASTNodes" to NqpSources.JASTNODES,` line and the `StageTarget("JastNodes", ...)` entry, and change `deps = listOf("Qregex", "JastNodes")` to `deps = listOf("Qregex")` (Hll) and `deps = listOf("Hll", "JastNodes", "Qregex", "QastNode")` to `deps = listOf("Hll", "Qregex", "QastNode")` (Qast); in `NqpSources.kt` delete `val JASTNODES = ...`; in `jvm/Makefile.in` delete the `ASTNODES_SOURCES` line (Makefile road unverified; ruling above).

- [ ] **Step 3**: `nqp/src/vm/jvm/NQP/Ops.nqp`: delete every `$ops.add_hll_op('nqp', ...)` block (`preinc`, `predec`, `postinc`, `postdec`, `intify`, `numify`, `stringify`, `falsey`: the encoder has rows for all eight at `TruffleEncoder.nqp:1689-1979`) and every `QAST::OperationsJAST.add_hll_unbox('nqp', ...)` block (`:150-177`), plus the JAST type constants they used. If nothing but comments remains, delete the file, drop `"src/vm/jvm/NQP/Ops.nqp"` from `NqpSources.NQP` and `NQP_SOURCES_EXTRA` from `jvm/Makefile.in:43`, and check `checkSourceLists` still passes (`COMMON_NQP_SOURCES` is `NQP.drop(1)`: when the file goes, change the map entry to `NQP` itself). Any `map_classlib_hll_op('nqp', ...)` calls stay.

- [ ] **Step 4**: drift guards: `./nqp/gradlew -p nqp checkSourceLists genCatParityCheck`. Expected: both OK.

- [ ] **Step 5**: nqp clean build (same command as Task 1 Step 10, log `t2-build.log`). Expected EXIT=0; census: 10 jars in `share/lib` (no `JASTNodes.jar`), all `unit.meta`-only.

- [ ] **Step 6**: t/nqp + t/qast (Task 1 Step 11's command, `t2-sweep`). Expected 118/118, 1/2.

- [ ] **Step 7**: Commit (nqp): `git add -A` on the five files plus the deletion; message `unit compiler: the JASTNodes module and nqp's JAST op closures are gone; nine stage targets`.

---

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

### Task 4: stage0 regenerated as artifacts; stage compiles enter through UnitMain

**Files:**
- Modify: `nqp/build.gradle.kts:214-224` (`mainClass`, `classpath`, the boot classpath, the args), `:434-442` (`jBootstrapFiles`: unchanged code; run it)
- Modify: `nqp/src/vm/jvm/stage0/*.jar` (nine regenerated; `JASTNodes.jar` removed)
- Modify: `nqp/docs/gradle-jvm-build.md:64-70` (how the bootstrap is modeled), `:114-117` (the regeneration note)
- Test: two clean builds; t/nqp

**Interfaces:**
- Consumes: Task 2's stage2 (`nqp/build/jvm/stage2/*.jar`, artifacts, nine targets); `org.raku.nqp.runtime.unit.UnitMain <unit.jar> args...` (either road; the loader sniffs).
- Produces: stage0 = nine `unit.meta`-only jars built by the Task 1-2 compiler; stage compiles that never touch a class file.

- [ ] **Step 1: The stage compile enters through UnitMain.** In `registerStage` (`build.gradle.kts:214-261`):

```kotlin
            workingDir = projectDir
            mainClass = "org.raku.nqp.runtime.unit.UnitMain"
            classpath = files(compilerDir, engineJarFile)

            doFirst {
                // The compiler's own units resolve against the module
                // search path the classpath yields (compilerDir); the
                // runtime and its third-party jars ride on the boot
                // classpath as the runner's do (GenerateRunnerTask).
                val bootcp = (
                    listOf(compilerDir.absolutePath, runtimeJarFile.absolutePath) +
                        thirdPartySorted().map { it.absolutePath }
                    ).joinToString(File.pathSeparator)
                jvmArgs("--enable-native-access=ALL-UNNAMED", "-Xmx$nqpStageMaxHeap", "-XX:+AllowParallelDefineClass", "-Xbootclasspath/a:$bootcp")
                jvmArgs("--module-path", shareTruffleDir.asFile.absolutePath,
                    "--add-modules", "org.graalvm.truffle,org.graalvm.truffle.runtime")
            }

            val compilerUnit = listOf("${compilerDir.absolutePath}/nqp.jar")
            val stableSc = if (stage == 1) listOf("--stable-sc=stage1") else emptyList()
            args = if (t.isNqp) {
                compilerUnit + listOf("--bootstrap", "--module-path=$stageDirPath", "--setting-path=$stageDirPath",
                    "--setting=${t.setting}", "--target=jar", "--no-regex-lib") +
                    stableSc + listOf("--javaclass=nqp", "--output=$outputJar", inputFile.absolutePath)
            } else {
                compilerUnit + listOf("--bootstrap") +
                    (if (t.settingPath) listOf("--setting-path=$stageDirPath") else emptyList()) +
                    (if (t.modulePath) listOf("--module-path=$stageDirPath") else emptyList()) +
                    listOf("--no-regex-lib", "--target=jar", "--setting=${t.setting}") +
                    stableSc + listOf("--output=$outputJar", inputFile.absolutePath)
            }
```

(The only differences from today: `mainClass`, the boot classpath losing its trailing `<compilerDir>/nqp.jar`, and `compilerUnit` as the first argument.)

- [ ] **Step 2: Build from the class-road stage0 through UnitMain** (proves the entry on the old road): Task 1 Step 10's command with log `t4-build-a.log`. Expected EXIT=0. If `UnitMain` cannot find the compiler's modules (`Could not find ... QAST.jar` or a `loadbytecode` failure), the classpath-derived module search path is the suspect: compare with `nqp-j-gradle`'s `CP`.

- [ ] **Step 3: Regenerate**: `raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/25fa1a35/tmp/t4-bootstrap.log -- ./nqp/gradlew -p nqp jBootstrapFiles`; then from the nqp dir `git rm src/vm/jvm/stage0/JASTNodes.jar`. `ls -la nqp/src/vm/jvm/stage0/`: nine jars, dated now; `raku tools/build/jar-census.raku nqp/src/vm/jvm/stage0/*.jar`: all `unit.meta`-only, zero `.class`, zero `.codeprograms.lz4`.

- [ ] **Step 4: Build from the new stage0**: the clean build again, log `t4-build-b.log`. Expected EXIT=0; stage1 is now compiled by an artifact compiler. Record the build time (the first stage0-as-artifact number).

- [ ] **Step 5**: t/nqp + t/qast (`t4-sweep`). Expected 118/118, 1/2.

- [ ] **Step 6: Docs**: `nqp/docs/gradle-jvm-build.md`: the "How the bootstrap is modeled" paragraph names `org.raku.nqp.runtime.unit.UnitMain <stageDir>/nqp.jar --bootstrap ...` and says stage0 is a set of unit artifacts; add under the regeneration note: "stage0 regenerated 2026-09 as unit artifacts (`./gradlew jBootstrapFiles` after the JAST-free driver landed). Rule: a change that an OLD stage0 could not read (an incompatible wire change, a meta format bump, a syscall shape change) is preceded by a regeneration from the LAST compiler that still speaks the old shape; additive wire changes need none."

- [ ] **Step 7: Commit (nqp)**: `git add -A src/vm/jvm/stage0 build.gradle.kts docs/gradle-jvm-build.md && git commit -m "stage0: regenerated as unit artifacts from the JAST-free compiler; stage compiles enter through UnitMain"` (binary jars: label the hash in the report).

---

### Task 5: The runtime class road deleted

**Files:**
- Delete: `nqp/src/vm/jvm/runtime/org/raku/nqp/jast2bc/JASTCompiler.kt`, `AutosplitMethodWriter.kt`, `JastClass.kt`, `JastMethod.kt`, `JastField.kt`, `JavaClass.kt`; move `BytecodeVersion.kt` to `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/BytecodeVersion.kt` (package `org.raku.nqp.runtime`)
- Delete: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/IndyBootstrap.kt`, `CodeRefAnnotation.kt`
- Delete: `nqp/t/jvm/09-autosplit.t`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt:76` (import), `:8966-8972` (`compilejast`), `:9038-9043` (`compilejasttofile`), `:9044-9100` (`loadcompunit`), `:3269` (comment)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/EvalResult.kt`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CompilationUnit.kt:1-200`, `:201-244`, `:265-345`, `:347`, `:385-470`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/GlobalContext.kt:234-241`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitWriter.kt` (the JAST-typed `record`/`write` pair and the three jast2bc imports), `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/Syscalls.kt:477-491` (`jvm-write-unit`, `jvm-build-unit`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/BootJavaInterop.kt:20`, `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/reprs/P6Opaque.kt:15` (the `BytecodeVersion` import)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/KnowHOWMethods.kt:314` (`getCodeRefs` stays; its return type becomes non-null)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CodeEngine.kt:72` (comment), `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitFormat.kt:13` (comment)
- Modify: `nqp/tools/templates/jvm/Makefile.in:21` (the `jast2bc/*.java` line)
- Test: runtime jars + `:nqp-runtime:test`; t/nqp; `t/01-sanity`

**Interfaces:**
- Consumes: Task 4's stage0 (no gradle build reaches `compilejast`, `loadcompunit`'s define branch, the sidecar reader, `setLexValuesBulk` or `enterFromMain` any more); the adaptors still generate a `CompilationUnit` subclass through the reflective initializer until Task 7 -- so THIS task keeps `getCodeInfo`, `codeInfoStash`, `ReflectiveCodeInfo`, `CodeRefAnnotation` and the reflective half of `initializeCompilationUnit` (they go in Task 7, with their last client). Everything else on the list goes here.
- Produces: `CompilationUnit` with `getCodeRefs(): Array<CodeRef>` as the non-reflective hook; `EvalResult` with `record` and `cu` only; `Ops.loadcompunit` on the record road only; `org.raku.nqp.runtime.BytecodeVersion`.

- [ ] **Step 1: jast2bc.** `git mv nqp/src/vm/jvm/runtime/org/raku/nqp/jast2bc/BytecodeVersion.kt nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/BytecodeVersion.kt` (from the nqp dir, paths relative to it), change its package line to `package org.raku.nqp.runtime`, fix the two imports (`BootJavaInterop.kt:20` becomes unnecessary in the same package: delete the line; `P6Opaque.kt:15` becomes `import org.raku.nqp.runtime.BytecodeVersion`). `git rm -r src/vm/jvm/runtime/org/raku/nqp/jast2bc`. In `UnitWriter.kt` delete the three `org.raku.nqp.jast2bc` imports and the `record(jast, jastNodes, tc)` / `write(jast, jastNodes, filename, tc)` pair; in `Syscalls.kt` delete `jvm-write-unit` and `jvm-build-unit` (the `-record` pair from Task 1 stays).

- [ ] **Step 2: Ops and EvalResult.** Delete `compilejast`, `compilejasttofile` and the `JASTCompiler` import; `loadcompunit` becomes:

```kotlin
    /** Turns a runtime compile's record into a live unit: a ProgramUnit
     *  built from the record, initialized under the compilee's HLL config
     *  when asked, and retained for nested embedding while a compilation
     *  is under way. */
    @JvmStatic
    fun loadcompunit(obj: SixModelObject?, compileeHLL: Long, tc: ThreadContext): SixModelObject? {
        try {
            val res = obj as EvalResult
            val rec = res.record
                ?: throw ExceptionHandling.dieInternal(tc, "loadcompunit: no unit record to load")
            val u = org.raku.nqp.runtime.unit.ProgramUnit(rec)
            u.shared = false
            res.cu = u
            val unitName = rec.meta.unitId
            if (System.getenv("NQP_CODE_WHY") != null)
                System.err.println("unit record $unitName (${rec.programs.size} programs, ${rec.meta.blocks.size} qbids)")
            if (compileeHLL != 0L)
                usecompileehllconfig(tc)
            u.initializeCompilationUnit(tc)
            if (compileeHLL != 0L)
                usecompilerhllconfig(tc)
            /* A unit compiled while a compilation is under way may be a
             * nested unit whose code refs the enclosing serialization
             * points into; retain what embedding it later needs. */
            if (!tc.compilingSCs.isNullOrEmpty()) {
                tc.gc.inMemoryUnitRecords[unitName] = rec
                u.codeRefs?.let { crs ->
                    for (cr in crs) {
                        val cuid = cr.staticInfo.uniqueId
                        if (!cuid.isNullOrEmpty())
                            tc.gc.inMemoryUnitOfCuid[cuid] = unitName
                    }
                }
            }
            res.record = null
            return obj
        }
        catch (e: ControlException) {
            throw e
        }
        catch (e: Exception) {
            throw RuntimeException(e)
        }
    }
```

`EvalResult.kt`: delete the `JavaClass` import and the `jc` field; reword the doc comment ("a runtime compile's record before and after loadcompunit"). `GlobalContext.kt`: delete `inMemoryUnitBytes` and its comment; keep `inMemoryUnitOfCuid` and `inMemoryUnitRecords` (reword the comment at `:236-240`). `Ops.kt:3269`: drop the indy-budget sentence. Check `Ops.jvmclassofcuid` (near `:8975`) reads only `inMemoryUnitOfCuid`.

- [ ] **Step 3: CompilationUnit.** Delete `enterFromMain` and `setupCompilationUnit` (`:20-43`); `setLexValues`/`setLexValuesBulk`/the private `setLexValues` (`:281-345`); the class bodies of `serializedBlob` and `claimNested` (`:390-409`), which become `abstract`; `engineProgram`'s class body and `loadEnginePrograms` with the `enginePrograms` field (`:410-470`): `engineProgram(idx: Int): String` becomes `abstract`; `lookupCodeRef(uniqueId: String)` keeps its map body (the `getCodeRefs()` units need it: KnowHOWMethods, the adaptors after Task 7) and loses the `/*FOR_STAGE0*/` mark; `unitId()`'s body becomes `abstract`. `getCodeRefs()` becomes `open fun getCodeRefs(): Array<CodeRef> = arrayOf()` and the fallback branch in `initializeCompilationUnit` (`:158-166`) keeps using it. `IndyBootstrap.kt` deleted (`grep -rn IndyBootstrap nqp/src src` must show only comments in `SixModelObject.kt:17,29`: reword them). `KnowHOWMethods.kt:314`: `override fun getCodeRefs(): Array<CodeRef>` (drop the `?`). `ProgramUnit.kt` gains `override fun engineProgram`, `serializedBlob`, `claimNested`, `unitId` as it already has them (only the `override` modifiers may need the abstract base's signatures: check they compile).

- [ ] **Step 4: Tests and templates.** `git rm t/jvm/09-autosplit.t` (nqp dir); `jvm/Makefile.in:21` delete the `jast2bc/*.java` line. Comments: `CodeEngine.kt:72` and `UnitFormat.kt:13` lose the sidecar sentence.

- [ ] **Step 5: Runtime jars**: `./nqp/gradlew -p nqp :nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars`. Expected BUILD SUCCESSFUL. Compile errors here name every reference the inventory missed: fix them in this task (report each).

- [ ] **Step 6: t/nqp + t/qast** (`t5-sweep`) and `t/01-sanity` (`t5-sanity`, Task 3 Step 4's command). Expected 118/118, 1/2, 25/25. Restart any eval server.

- [ ] **Step 7: Leftover grep**: `grep -rn 'jast2bc\|JASTCompiler\|compilejast\|MemoryClassLoader\|codeprograms\|setup_blv\|setLexValues\|enterFromMain\|IndyBootstrap\|inMemoryUnitBytes' nqp/src src tools nqp/tools nqp/t t` must be empty (docs excepted until Task 11).

- [ ] **Step 8: Commit (nqp)**: `git add -A src/vm/jvm/runtime src/vm/jvm/runtime/org/raku/nqp/runtime/BytecodeVersion.kt t/jvm tools/templates/jvm/Makefile.in && git commit -m "runtime: the class road's writer and loaders are gone -- jast2bc, compilejast, loadcompunit's define branch, the sidecar reader, setLexValues, enterFromMain, IndyBootstrap; BytecodeVersion moves to runtime/"`.

---

### Task 6: The loader in Kotlin (LibraryLoader.java deleted)

**Files:**
- Delete: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/LibraryLoader.java` (590 lines)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitLoader.kt` (grows `load`, `loadApp`, `prime`, `readToHeapBuffer`, `readToHeapBufferLz4`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/GlobalContext.kt` (a `loadedUnits` set replacing `ByteClassLoader.addRef` for unit paths), `ByteClassLoader.kt` (`addRef`/`refs` deleted; `getMade`/`setMade`/`getRead`/`setRead` deleted if only `LibraryLoader` used them: grep)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt:7942-7955` (`loadbytecode`, `loadbytecodebuffer`), `CompilationUnit.kt` (no `LibraryLoader.readToHeapBuffer*` left after Task 5: verify), `unit/UnitMain.kt:4,15`, `unit/ProgramUnit.kt` (unchanged), `tools/EvalServer.java:33,75,126,238`
- Modify: rakudo `src/vm/jvm/runtime/org/raku/rakudo/RakudoEvalServer.java` (42 lines; its `LibraryLoader` references, if any)
- Test: runtime jars; t/nqp; `t/01-sanity`; one eval-server smoke (`t/harness5 --jvm --evalserver` on `t/01-sanity/01-tap.t`)

**Interfaces:**
- Consumes: Task 5's `CompilationUnit`; `UnitZip.isUnit`, `UnitLoader.isUnitFile`, `loadUnit`, `loadAndRun`, `record` (existing).
- Produces: `UnitLoader.load(tc, filename: String)`, `load(tc, bytes: ByteArray)`, `load(tc, buffer: ByteBuffer)`, `loadApp(tc, path, shared): CompilationUnit`, `prime(path)`, `readToHeapBuffer(InputStream)`, `readToHeapBufferLz4(InputStream)`; `GlobalContext.loadedUnits: MutableSet<String>`.

- [ ] **Step 1**: port into `UnitLoader` (object) the road-agnostic survivors of `LibraryLoader.java:32-112`, `:198-233`, `:235-250`, without the class branches:

```kotlin
    /** nqp::loadbytecode: a unit by path, once per GlobalContext. The
     *  ModuleLoader.class name is special-cased as it always was: the
     *  first unit is probed for on the classpath as ModuleLoader.class,
     *  then ModuleLoader.jar (an artifact since milestone 1). */
    @JvmStatic
    fun load(tc: ThreadContext, filename0: String) {
        var filename = filename0
        if (!tc.gc.loadedUnits.add(filename)) return
        try {
            var file = File(filename)
            if (!file.isFile && filename == "ModuleLoader.class") {
                for (cp in System.getProperty("java.class.path").split(Regex("[:;]"))) {
                    file = File("$cp/$filename")
                    if (file.isFile) { filename = "$cp/$filename"; break }
                    file = File("$cp/ModuleLoader.jar")
                    if (file.isFile) { filename = "$cp/ModuleLoader.jar"; break }
                }
            }
            if (!isUnitFile(filename))
                throw ExceptionHandling.dieInternal(tc, "loadbytecode: $filename is not a unit artifact")
            loadAndRun(tc, filename, tc.gc.sharingHint)
        } catch (e: ControlException) {
            throw e
        } catch (e: Exception) {
            if (e is RuntimeException && e.javaClass.name.startsWith("org.raku.nqp")) throw e
            throw ExceptionHandling.dieInternal(tc, e)
        }
    }

    @JvmStatic
    fun load(tc: ThreadContext, buffer: ByteArray) {
        if (!UnitZip.isUnit(ByteBuffer.wrap(buffer)))
            throw ExceptionHandling.dieInternal(tc, "loadbytecodebuffer: the buffer is not a unit artifact")
        loadAndRun(tc, buffer)
    }

    @JvmStatic
    fun load(tc: ThreadContext, buffer: ByteBuffer) {
        val bytes = if (buffer.hasArray() && buffer.arrayOffset() == 0 && buffer.position() == 0
                        && buffer.array().size == buffer.remaining()) buffer.array()
                    else ByteArray(buffer.remaining()).also { buffer.duplicate().get(it) }
        load(tc, bytes)
    }

    /** Road-agnostic app load for entry points (runner main, eval server):
     *  initialized (deserialized) but its load block not run; an entry
     *  block does that itself. */
    @JvmStatic
    fun loadApp(tc: ThreadContext, path: String, shared: Boolean): CompilationUnit {
        if (!isUnitFile(path, shared))
            throw ExceptionHandling.dieInternal(tc, "$path is not a unit artifact")
        return loadUnit(tc, path, shared)
    }

    /** Warms the shared record cache, so a server pays for parsing once. */
    @JvmStatic
    @Throws(IOException::class)
    fun prime(path: String) { record(path, true) }

    @JvmStatic
    @Throws(IOException::class)
    fun readToHeapBuffer(input: InputStream): ByteBuffer = ByteBuffer.wrap(input.readAllBytes())

    /* safeInstance(), not fastestInstance(): the Unsafe fast path is
     * deprecated for removal (JEP 498). */
    private val lz4 = LZ4DecompressorWithLength(LZ4Factory.safeInstance().fastDecompressor())

    @JvmStatic
    @Throws(IOException::class)
    fun readToHeapBufferLz4(input: InputStream): ByteBuffer = ByteBuffer.wrap(lz4.decompress(input.readAllBytes()))
```

Keep whatever error-wrapping `LibraryLoader.load` did for `IllegalStateException`/`IllegalArgumentException` from `UnitZip.read` (they become `dieInternal`); check who reads `readToHeapBuffer*` after Task 5 (`UnitZip`, `ProgramUnit`?) and repoint the callers. `GlobalContext.kt`: `@JvmField val loadedUnits: MutableSet<String> = java.util.concurrent.ConcurrentHashMap.newKeySet()` beside `inMemoryUnitOfCuid`. `ByteClassLoader.kt`: delete `refs`/`addRef`; delete `read`/`made`/`getMade`/`setMade`/`getRead`/`setRead` only if `grep -rn 'getMade\|setMade\|getRead\|setRead' nqp/src src` is empty after `LibraryLoader` goes (keep `defineClass`, which P6Opaque and the adaptors use, and the memoization it needs).

- [ ] **Step 2**: repoint: `Ops.loadbytecode` / `loadbytecodebuffer` -> `org.raku.nqp.runtime.unit.UnitLoader.load(...)`; `UnitMain.kt` -> `UnitLoader.loadApp`; `EvalServer.java:75,238` -> `UnitLoader.loadApp(...)`, `:126` -> `UnitLoader.prime(mainPath)` (the `gc.byteClassLoader` argument goes; the surrounding comment about "loading needs a class loader" is rewritten: the server holds a GlobalContext for its shared record cache); `RakudoEvalServer.java` likewise if it names `LibraryLoader`. `git rm src/vm/jvm/runtime/org/raku/nqp/runtime/LibraryLoader.java` (nqp dir).

- [ ] **Step 3**: runtime jars (`:nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars`). Expected BUILD SUCCESSFUL. Note: rakudo's `RakudoEvalServer.java` compiles in rakudo's make, not here; if it changed, `make` in Task 11 covers it, and a quick `javac` check is `./nqp/gradlew`-independent: skip, the make is the gate.

- [ ] **Step 4**: t/nqp + t/qast (`t6-sweep`); `t/01-sanity` (`t6-sanity`); the eval-server smoke: `RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/25fa1a35/tmp/t6-evalserver.log -- perl t/harness5 --jvm --evalserver t/01-sanity/01-tap.t t/01-sanity/02-counter.t` (restart/kill any running server first; `docs/jvm-eval-server.md` has the server lifecycle). Expected 118/118, 1/2, 25/25, 2/2 files.

- [ ] **Step 5**: leftover grep: `grep -rn 'LibraryLoader\|byteClassLoader.addRef\|JarFileClassLoader\|FileClassLoader\|StreamClassLoader\|SerialClassLoader' nqp/src src` empty.

- [ ] **Step 6**: Commit (nqp): `git add -A src/vm/jvm/runtime && git commit -m "runtime: the loader is Kotlin and knows one road -- LibraryLoader.java and its four class loaders are gone; UnitLoader loads, primes and reads"`; rakudo, if `RakudoEvalServer.java` changed: `git add src/vm/jvm/runtime/org/raku/rakudo/RakudoEvalServer.java && git commit -m "JVM eval server: enters through UnitLoader"`.

---

### Task 7: The interop adaptors on plain method handles

**Files:**
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/AdaptorUnit.kt`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/BootJavaInterop.kt:224-234` (`computeInterop`), `:276-297` (`createAdaptor`: superclass, no `compunitMethods`), `:299-323` (`compunitMethods` deleted), `:810-818` (`startCallout`: no annotation), and the second `startVarArityCallout`-like site if any (`grep -n visitAnnotation`)
- Modify: `src/vm/jvm/runtime/org/raku/rakudo/RakudoJavaInterop.kt:828-889` (`createAdaptor`), `:722-732` (`startVarArityCallout`: no annotation), `:928-936` (`computeInterop`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CompilationUnit.kt` (the reflective half goes: `getCodeInfo`, `codeInfoStash`, `ReflectiveCodeInfo`, the annotation loop in `initializeCompilationUnit`), delete `CodeRefAnnotation.kt`
- Test: `t/03-jvm/01-interop.t`; `t/01-sanity`

**Interfaces:**
- Consumes: `CompilationUnit.getCodeRefs()` hook, `lookupCodeRef(Int)` = position in `getCodeRefs()`'s array (Task 5); `StaticCodeInfo`'s acceptance of a four-parameter bound handle `(ThreadContext, CodeRef, CallSiteDescriptor, Object[])` (`StaticCodeInfo.kt:249-272`: neither branch fires, the handle is used as is, exactly KnowHOWMethods' shape); `ByteClassLoader.defineClass` for the plain class.
- Produces: `AdaptorUnit(cls: Class<*>, descriptors: List<String>, target: String)`; generated adaptor classes with superclass `java/lang/Object`, static `qb_N(CompilationUnit, ThreadContext, CodeRef, CallSiteDescriptor, Object[])` methods, no annotation; `CompilationUnit.initializeCompilationUnit` non-reflective.

- [ ] **Step 1: AdaptorUnit**:

```kotlin
package org.raku.nqp.runtime

import java.lang.invoke.MethodHandles
import java.lang.invoke.MethodType

/**
 * The unit behind a generated Java-interop adaptor class: one code ref
 * per static qb_N callout, built from a method handle bound to this unit
 * (the callouts take the unit as their first argument, as every block
 * entry does). No reflection over annotations, no generated subclass of
 * CompilationUnit: the same road KnowHOWMethods takes.
 */
class AdaptorUnit(
    private val cls: Class<*>,
    private val descriptors: List<String>,
    private val target: String,
) : CompilationUnit() {
    override fun getCodeRefs(): Array<CodeRef> {
        val l = MethodHandles.lookup()
        val mt = MethodType.methodType(Void.TYPE, CompilationUnit::class.java, ThreadContext::class.java,
            CodeRef::class.java, CallSiteDescriptor::class.java, Array<Any?>::class.java)
        return Array(descriptors.size) { i ->
            val name = "callout $target ${descriptors[i]}"
            val mh = l.findStatic(cls, "qb_$i", mt).bindTo(this)
            CodeRef(this, mh, name, name, null, null, null, null, arrayOf(), 0.toShort())
        }
    }
    override fun getCallSites(): Array<CallSiteDescriptor> = arrayOf()
    override fun hllName(): String = ""
    override fun unitId(): String = cls.name
    override fun engineProgram(idx: Int): String =
        throw IllegalStateException("adaptor unit ${cls.name} has no engine programs")
    override fun serializedBlob(): java.nio.ByteBuffer? = null
    override fun claimNested(tc: ThreadContext, name: String): CompilationUnit =
        throw IllegalStateException("adaptor unit ${cls.name} carries no nested unit $name")
}
```

(Match the abstract members Task 5 left on `CompilationUnit`; if `unitId`/`engineProgram`/`serializedBlob`/`claimNested` stayed `open` with bodies, drop the overrides that are not needed.)

- [ ] **Step 2: BootJavaInterop.** `createAdaptor`: `cw.visit(BytecodeVersion.EMITTED, Opcodes.ACC_PUBLIC or Opcodes.ACC_SUPER, className, null, "java/lang/Object", null)`; delete the `compunitMethods(cc)` call and the method; in `startCallout` delete the three `visitAnnotation` lines; in `computeInterop`:

```kotlin
        val adaptor = createAdaptor(klass)
        val adaptorUnit = AdaptorUnit(adaptor.constructed!!, adaptor.descriptors, klass.getName())
        adaptorUnit.initializeCompilationUnit(tc)
```

(the `try { newInstance() } catch` block goes). `finishClass` is unchanged (the plain class's `constants` static is still set reflectively). Check `TYPE_CU` is still used (the callout descriptor names it): yes.

- [ ] **Step 3: RakudoJavaInterop.** `createAdaptor:830`: superclass `"java/lang/Object"` (and `BytecodeVersion.EMITTED` instead of `Opcodes.V1_7`, since the boot side already emits that); delete `compunitMethods(cc)`; `startVarArityCallout` loses its `visitAnnotation` lines (and any other `qb_` site: `grep -n 'visitAnnotation\|CodeRefAnnotation' src/vm/jvm/runtime/org/raku/rakudo/RakudoJavaInterop.kt` must be empty after); `computeInterop:928-936` as in Step 2 (`AdaptorUnit(adaptor.constructed!!, adaptor.descriptors, klass.name)`).

- [ ] **Step 4: CompilationUnit loses the reflective half.** Delete `getCodeInfo`, `codeInfoStash`, `ReflectiveCodeInfo`, the `Method`/`MethodHandles` imports that only they used, and rewrite `initializeCompilationUnit(tc, runDeserialize)` as the `getCodeRefs()` road only:

```kotlin
    /** Fills the code-ref tables from getCodeRefs() (a hand-written unit:
     *  KnowHOWMethods, AdaptorUnit); a ProgramUnit overrides this with its
     *  block table. */
    open fun initializeCompilationUnit(tc: ThreadContext, runDeserialize: Boolean) {
        val bootSt = tc.gc.BOOTCode?.st
        val refs = getCodeRefs()
        codeRefs = refs
        qbidToCodeRef = arrayOfNulls<CodeRef>(refs.size).also { t -> for (i in refs.indices) t[i] = refs[i] }
        for (c in refs) {
            if (bootSt != null) c.st = bootSt
            c.staticInfo.uniqueId?.let { cuidToCodeRef[it] = c }
        }
        callSites = getCallSites()
        hllConfig = tc.gc.getHLLConfigFor(hllName())
        if (runDeserialize) runDeserializeIfAvailable(tc)
    }
```

`git rm src/vm/jvm/runtime/org/raku/nqp/runtime/CodeRefAnnotation.kt` (nqp dir); `grep -rn CodeRefAnnotation nqp/src src` empty (the `UnitRecord.kt:1-2` comment names it: reword).

- [ ] **Step 5**: runtime jars (nqp). Rakudo's `RakudoJavaInterop.kt` compiles in the make: run `make` now? No -- `make` rebuilds only what changed; rakudo's runtime jar target (`rakudo-runtime.jar` via the Makefile's kotlin step) is what changed. Run: `RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/25fa1a35/tmp/t7-make.log --show='Compiling' --show='rror' -- make` and confirm from the log that only the runtime jar step ran (no `Compiling ... CORE.c`); if the Makefile's dependency graph recompiles settings because the runtime jar is newer, let it (forward only) and record the time.

- [ ] **Step 6**: `RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=t/03-jvm --jobs=1 --log-dir=/home/longwalker/.claude/jobs/25fa1a35/tmp/t7-interop-logs -- ./rakudo-j -Ilib` (expected: `01-interop.t` 30 planned, its 3 known skips, no failures) and `t/01-sanity` (`t7-sanity`, 25/25). Restart eval servers.

- [ ] **Step 7**: Commit (nqp): `git add -A src/vm/jvm/runtime && git commit -m "interop: adaptor classes are plain classes; AdaptorUnit builds their code refs from bound method handles; the reflective code-ref road and CodeRefAnnotation are gone"`; (rakudo): `git add src/vm/jvm/runtime/org/raku/rakudo/RakudoJavaInterop.kt && git commit -m "JVM interop: the Rakudo adaptor is a plain class behind an AdaptorUnit"`.

---

### Task 8: Torn-frame LEAVE (gap 5a), time-boxed

**Files:**
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CallFrame.kt:424-458` (`countLeft`, `leave`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/ExceptionHandling.kt:223-232` (`giveBackTornFrames`)
- Test: `/home/longwalker/code/raku/x.core/rakudo/t/spec/S04-phasers/leave.t` and `enter-leave.t` (by path, `./rakudo-j -Ilib`); `t/01-sanity`; a one-liner probe

**Time box:** two runtime-jar rebuilds. If the second still leaves `leave.t` red, stop, record the failing subtests and the state of the change, and rule (revert the runtime edit and ledger the gap, or keep it if it fixes more than it breaks and sanity is green).

**Interfaces:**
- Consumes: `StaticCodeInfo.hasExitHandler`, `CallFrame.left`, `CallFrame.exitHandlerCallSite`, `HLLConfig.exitHandler`, `HLLConfig.nullValue` (Raku sets it to `Mu`; MoarVM hands the exit handler `VMNull`, which its hllize maps to the same), Rakudo's exit handler (`src/Perl6/bootstrap.c/BOOTSTRAP.nqp:5940`: `.defined` of the hllized result decides KEEP vs UNDO; an undefined result = exceptional exit).
- Produces: `CallFrame.leaveTorn()`.

- [ ] **Step 1: The probe, before the change** (expected today: no `LEAVE` line):

```
RAKUDO_RAKUAST=1 ./rakudo-j -e 'sub f() { LEAVE say "LEAVE"; die "boom" }; try f(); say "after"'
```

- [ ] **Step 2: `CallFrame.leaveTorn`**, replacing `countLeft` (rename every caller; `grep -rn countLeft nqp/src`):

```kotlin
    /**
     * The unwinder tears this frame past without running its postlude (an
     * exception's target is a handler further out). Raku runs LEAVE, UNDO
     * and POST on an exceptional exit, so the exit handler runs here with
     * the result ABSENT -- the HLL's null value, which is what MoarVM's
     * unwind hands it (VMNull, hllized) -- and then the live-invocation
     * count is given back. Idempotent with leave() via `left`. tc.curFrame
     * is restored after the handler: the unwind continues to its target.
     * An exception the handler throws replaces the in-flight one (the
     * phaser's exception wins, as on MoarVM).
     */
    fun leaveTorn() {
        if (left) return
        left = true
        val sci = codeRef.staticInfo
        sci.liveInvocations.decrementAndGet()
        if (sci.hasExitHandler) {
            val origUnwinder = tc.unwinder
            val origCur = tc.curFrame
            tc.curFrame = this
            try {
                tc.unwinder = UnwindException()
                val hll = sci.compUnit.hllConfig
                Ops.invokeDirect(tc, hll.exitHandler, exitHandlerCallSite,
                    arrayOf<Any?>(this.codeRef, hll.nullValue))
            } finally {
                tc.unwinder = origUnwinder
                tc.curFrame = origCur
            }
        }
    }
```

`giveBackTornFrames` calls `f.leaveTorn()` in place of `f.countLeft()` (it already walks innermost first). `leave()` keeps its own shape (a normal exit hands the real result).

- [ ] **Step 3**: runtime jars; the probe prints `LEAVE` then `after`. If the exit handler dies on the null result (`Cannot look up method 'defined' on a null`), `hll.nullValue` is null for this unit's HLL config: pass `tc.gc.getHLLConfigFor("Raku").nullValue`? No -- read `HLLConfig.nullValue`'s setter (`sethllconfig` in Ops) and confirm Rakudo sets `null_value`; if it does not on the JVM, that is the finding, and the fix is one `nqp::sethllconfig` key in Rakudo's JVM prologue (`src/Raku/ast/rakuast-prologue.nqp`, `#?if jvm`), not a runtime special case.

- [ ] **Step 4**: the two spec files: `RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=/home/longwalker/code/raku/x.core/rakudo/t/spec/S04-phasers/leave.t -t=/home/longwalker/code/raku/x.core/rakudo/t/spec/S04-phasers/enter-leave.t --jobs=1 --log-dir=/home/longwalker/.claude/jobs/25fa1a35/tmp/t8-phasers-logs -- ./rakudo-j -Ilib`; then `t/01-sanity` (`t8-sanity`). Expected: the subtests that exercise exceptional exit pass (compare against a run of the same two files BEFORE Step 2 -- run that first and keep its log as `t8-phasers-before`); sanity 25/25. `t/spec` fudge: the `.rakudo.jvm` twins beside the files are fudged versions; run the plain `.t` and read the fudge file to know which subtests were already skipped on the JVM.

- [ ] **Step 5**: Commit (nqp): `git add src/vm/jvm/runtime/org/raku/nqp/runtime/CallFrame.kt src/vm/jvm/runtime/org/raku/nqp/runtime/ExceptionHandling.kt && git commit -m "runtime: a torn frame runs its exit handler with the result absent, then gives back its count (LEAVE on exceptional exit)"`.

---

### Task 9: The resume value (gap 5b), time-boxed

**Files:**
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpCont.java:20-27` (`Suspend`)
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java:1043-1057` (`suspendToken` overloads), `:1068-1090` (`readResult`, unchanged)
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpCodeEngine.java:122-126` (`suspend`), `:156-176` (`resumeEngine`), `:203-209` (the re-suspend tail)
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java:512-523` (`DecontOp`), `:539-548` (`IsConcreteOp`), `:554-575` (`IsTypeOp`), `:580-592` (`P6SinkOp`), `:596-608` (`HllizeOp`), `:632-644` (`P6TypeCheckRvOp`)
- Modify: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt:233-300` (`decont`/`decontSlow`), `:334-345` (`isconcrete`), `:360-410` (`istype`/`istypeSlow`), `:448-` (`p6typecheckrv`)
- Test: the probe from the report; `t/01-sanity`; `nqp/t/nqp/*continuation*` and `*gather*` files if present (`ls nqp/t/nqp | grep -i 'cont\|gather'`)

**Time box:** two runtime-jar rebuilds (the engine jar rebuilds in the same command). If the probe still answers the inner value after the second, stop, record, rule (revert or keep), ledger.

**Mechanism (from milestone 3's task-3b report and the code):** a fused op (`isconcrete` = decont + concreteness test; `istype` = decont + type check; `p6typecheckrv` = a `where` call + the pass/fail decision) catches the `SaveStackException` thrown from user code it called (a Proxy FETCH, a `where` block) and answers a suspend token; `emitSuspendCheck` yields it; on resume, `resumeEngine` reads the INNER call's value off the return registers and `UnpackResumed` stores it as the OP's result. The tail of the op after the inner call never runs. The class road composed these ops from smaller pieces (decont was its own classlib call), so the suspended piece's result WAS the inner value.

**Design:** the token carries a finisher: the op's tail as a function of the inner call's value. `resumeEngine` applies it to the inner value (read as an object) and injects the finisher's answer. No wire change; the engine's yield/resume shape is unchanged.

- [ ] **Step 1: The probe, before** (expected today: `7`):

```
RAKUDO_RAKUAST=1 ./rakudo-j -e 'my $p := Proxy.new(FETCH => { take 7; 1 }, STORE => -> $, $ {}); my @a = gather { say ?$p }; say @a'
```

(Expected after: `True` then `[7]`; today `say ?$p` prints the FETCH value.) Also the report's own probe: `RAKUDO_RAKUAST=1 ./rakudo-j -e 'subset S of Int where { take $_; True }; my @a = gather { 5 ~~ S }; say @a'` answers `[5]` today and after (it is the type-correct case).

- [ ] **Step 2: The token and its finisher** (`NqpCont.java`):

```java
    static final class Suspend {
        final SaveStackException sse;
        final int rtype;
        /** The suspended op's tail, applied on resume to the inner call's
         *  (object) value; null when the inner value IS the op's result. */
        final java.util.function.Function<Object, Object> finish;
        Suspend(SaveStackException sse, int rtype) { this(sse, rtype, null); }
        Suspend(SaveStackException sse, int rtype, java.util.function.Function<Object, Object> finish) {
            this.sse = sse;
            this.rtype = rtype;
            this.finish = finish;
        }
    }
```

`NqpOps.java`: `static Object suspendToken(SaveStackException sse, java.util.function.Function<Object, Object> finish) { return new NqpCont.Suspend(sse, NqpWire.T_OBJ, finish); }` beside the two existing overloads (the inner call's value is read as an object; the finisher answers the op's own type: a `Long` for the int-typed ops, which the consumers already take as `Object`).

`NqpCodeEngine.java`: `suspend(...)` and the re-suspend tail push `new Object[] { cr, token.rtype, token.finish }`; `resumeEngine`:

```java
        ContinuationResult cr = (ContinuationResult) frame.saveSpace[0];
        int rtype = (Integer) frame.saveSpace[1];
        @SuppressWarnings("unchecked")
        java.util.function.Function<Object, Object> finish =
            (java.util.function.Function<Object, Object>) frame.saveSpace[2];
        ...
        try {
            frame.resumeNextSave();
            inject = finish == null ? NqpOps.readResult(rtype, cf)
                                    : finish.apply(NqpOps.readResult(NqpWire.T_OBJ, cf));
        } catch (SaveStackException sse) { ... unchanged ... }
        catch (Throwable t) { inject = new NqpCont.Rethrow(t); }
```

(a finisher that throws -- a failed type check -- is delivered through the yield as the op's own throw, exactly the existing `Rethrow` road).

- [ ] **Step 3: Where the inner calls are** (`NqpTypeOps.kt`). Introduce one exception type:

```kotlin
/** Thrown by a fused op at the user-code call that captured a
 *  continuation: the capture plus the op's tail, for the suspend token. */
class SuspendedIn(@JvmField val sse: org.raku.nqp.runtime.SaveStackException,
                  @JvmField val finish: java.util.function.Function<Any?, Any?>)
    : RuntimeException(null, null, false, false)
```

and wrap the user-code calls: in `isconcrete(site, o, tc)`, the decont of `o` (`try { ...decont... } catch (sse: SaveStackException) { throw SuspendedIn(sse) { v -> isconcreteOf(v, tc) } }` where `isconcreteOf` is the existing tail on an already-deconted value: read the function to name it); in `istype`, the decont of `o` (finisher: `{ v -> istype(site, v, type, tc) }`, a re-run on the fetched value, no Proxy left to re-suspend) and the `accepts_type` call in `istypeSlow` (finisher: `{ v -> if (Ops.istrue(v as SixModelObject, tc) != 0L) 1L else 0L }`); in `p6typecheckrv`, the `where`/`accepts_type` call (finisher: the pass/fail tail on the check's value: `rv` when true, the same failure the Kotlin code raises when false -- factor that tail into a private function first). `decont`, `p6sink`, `hllize`: the inner value is the result; no change.

- [ ] **Step 4: The ops** (`NqpRootNode.java`): in `IsConcreteOp`, `IsTypeOp`, `P6TypeCheckRvOp` add before the `SaveStackException` catch:

```java
            } catch (NqpTypeOps.SuspendedIn s) {
                return NqpOps.suspendToken(s.sse, s.finish);
```

(the existing typed-token catch stays as the fallback for a capture the Kotlin did not wrap).

- [ ] **Step 5**: `./nqp/gradlew -p nqp :nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars`; the two probes (`True`/`[7]` and `[5]`); `t/01-sanity` (`t9-sanity`); the nqp continuation/gather tests (`t9-cont`). Expected 25/25 and green.

- [ ] **Step 6**: Commit (nqp): `git add -A nqp-truffle/src/main src/vm/jvm/runtime && git commit -m "engine: a suspended fused op resumes through its finisher -- the op's tail runs on the inner call's value instead of taking that value as the op's result"`.

---

### Task 10: The BEGIN + where code-ref pairing (gap 5c), time-boxed

**Files:**
- Modify (if the lead pans out): `src/Raku/ast/code.rakumod:376-440` (`IMPL-STUB-CODE`, `#?if jvm` only) or `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/Syscalls.kt:512-` (`jvm-repoint-dynamic-code`) or `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt:30-80` (`buildTable`)
- Test: `t/02-rakudo/yada-trait-timing.t`, `t/02-rakudo/begin-time-attributive-param-method.t`; `t/01-sanity`; the reproducer

**Time box:** one working session of investigation plus at most ONE Rakudo make (a RakuAST fix needs CORE.c). If the reproducer still fails after that make, stop, write the findings into the report, rule (revert or keep), and the pair stays ledgered.

**Evidence so far** (milestone 3, `task-3b-report.md`, sections 3-4): the tie is `Code.clone` of a `$!do` already bound to the dynamic unit's mainline code ref; `jvm-repoint-dynamic-code` never runs for the reproducer; `IMPL-FIXUP-COMPILED-CODEREFS` runs after the failure; `$!do` is written in five places and the compile-time stub is `code.rakumod:428` (`nqp::bindattr($code-obj, Code, '$!do', $stub)` where `$stub := nqp::freshcoderef(sub (*@pos, *%named) {...})`). The next lead: which unit's block that anonymous sub belongs to when the routine is stubbed during a BEGIN, and whether `nqp::freshcoderef` / `nqp::getstaticcode` on a ProgramUnit code ref answers the sub's own code ref or the mainline's.

- [ ] **Step 1: Reproduce**: `RAKUDO_RAKUAST=1 ./rakudo-j -e 'BEGIN { sub f(Int $x where * > 2) { $x }; say f(5) }'` (expected today: a failure; expected after: `5`).

- [ ] **Step 2: Trace the stub**: `RAKUDO_DEBUG_STUB=1 NQP_REPOINT_TRACE=1 NQP_REPOINT_STACK=5 RAKUDO_RAKUAST=1 ./rakudo-j -e '...'` and answer three questions from the output and the code: (a) is the `$stub` closure's static code ref (`staticInfo.staticCode`) the anonymous sub's block or the mainline's (`nqp::getstaticcode` reads `staticInfo.staticCode`, set to `this` in `CodeRef`'s constructor; `Ops.freshcoderef` clones -- read `Ops.freshcoderef` and `Ops.markcodestatic`); (b) does the WhateverCode `* > 2` get its `$!do` through `IMPL-STUB-CODE` (a BEGIN-time compile of the where thunk) or through `impl.rakumod:203/330/350`; (c) in the dynamic unit's `buildTable` trace (`NQP_REPOINT_TRACE`), is the `WhateverCode`'s cuid present, and does `qbidToCodeRef` for its qbid name the mainline (a qbid collision) or the right block?

- [ ] **Step 3: Test the hypothesis** that emerges with the cheapest probe (a `nqp::say` behind `RAKUDO_DEBUG_STUB`, or an `-e` variant that isolates the where-thunk from the routine), then fix at the cause: a wrong static code ref (runtime: `Ops.freshcoderef`/`getstaticcode` on the unit road), a qbid collision between a nested unit's block and the parent's (runtime: `buildTable`, `claimNested`, `jvm-claim-nested`), or a RakuAST stub fetched from the wrong context (`code.rakumod`, `#?if jvm`).

- [ ] **Step 4**: the gate for a runtime fix: runtime jars + reproducer + the two t/02-rakudo files (`RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=t/02-rakudo/yada-trait-timing.t -t=t/02-rakudo/begin-time-attributive-param-method.t --jobs=1 --log-dir=/home/longwalker/.claude/jobs/25fa1a35/tmp/t10-pair-logs -- ./rakudo-j -Ilib`) + `t/01-sanity`; for a RakuAST fix: `make` (Task 3 Step 3's command, `t10-make`) first, then the same files. Expected: `yada-trait-timing.t` produces TAP and passes; `begin-time-attributive-param-method.t` 5/5; sanity 25/25.

- [ ] **Step 5**: Commit in the tree the fix lives in, message naming the cause (e.g. `unit road: a BEGIN-time stub's static code ref is the stub's own block, not the dynamic unit's mainline`), or the ruling in the report if parked.

---

### Task 11: The milestone gate, docs, ledger, memory, handoff

**Files:**
- Modify: `docs/jvm-truffle-only-plan.md` (position rows 5, 6, 8, 9; "The sidecar, placed" paragraph becomes history), `docs/superpowers/specs/2026-09-09-jvm-unit-artifact-design.md` (Milestones item 4: DONE line), `docs/superpowers/specs/2026-09-10-jvm-unit-artifact-milestone-4-design.md` (a "Done" note with hashes and numbers), `AGENTS.md` and `CLAUDE.md` (any sentence naming JAST, jast2bc, the sidecar, `NQP_CODE_RUN` presence, or the class road as live), `docs/jvm-eval-server.md` (if it names `LibraryLoader`), `docs/jvm-strict-campaign-handoff.md` (a closing line), `nqp/docs/gradle-jvm-build.md` (Task 4 did the substantive edit)
- Create: `docs/superpowers/plans/2026-09-10-jvm-unit-artifact-milestone-4.ledger.md` (the ledger twin, kept from Task 1 on by the controller; this task syncs it)
- Test: the milestone gate

- [ ] **Step 1: The make** (needed if Task 10 touched RakuAST or Task 7's Step 5 did not run a full make; otherwise the Task 3/7 makes stand): Task 3 Step 3's command (`t11-make`). Record the time as the milestone's baseline.

- [ ] **Step 2: The gate**: t/nqp + t/qast (`t11-nqp`); `t/01-sanity` (`t11-sanity`); precomp (Task 3 Step 4's list, `t11-precomp`); t/03-jvm + t/10-qast (`t11-jvm`); the census (`raku tools/build/jar-census.raku` over nqp's `share/lib`, `stage0`, and rakudo's jars); then the sweep, sized as milestone 3's sweep 2:

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --max=7200 --stall=1500 --log=/home/longwalker/.claude/jobs/25fa1a35/tmp/t11-sweep.log --show-file=/home/longwalker/.claude/jobs/25fa1a35/tmp/t11-sweep.markers --show='chunk' --show='files in' --show='FAIL' -- raku tools/build/evalserver-sweep.raku --jobs=3 --heap=4 t/01-sanity t/02-rakudo t/03-jvm t/04-nativecall t/05-messages t/06-telemetry t/07-pod-to-text t/08-performance t/10-qast t/13-experimental t/14-smoke
```

with a second invocation for the directories the ceiling cut off. Expected red: the corekeys/settingkeys cluster; the 2026-09-05 known list minus what milestones 3-4 fixed; the item-8 pair only if Task 10 was parked. Any NEW failure against milestone 3's sweep 2 is triaged: a unit-road or runtime regression is fixed in this task (runtime jars, amend), a test-content failure is recorded.

- [ ] **Step 3: Docs**: the files listed above; `grep -rn 'JAST\|jast2bc\|codeprograms\|class road\|LibraryLoader\|NQP_CODE_RUN' AGENTS.md CLAUDE.md docs/*.md nqp/docs/*.md` and rewrite every sentence that presents them as live (history stays history, marked as such). The plan's position table: item 5 and 6 "milestone 4 DONE (hashes, numbers)"; item 8 "DONE: nothing JAST-named, no class road; ASM stays for P6Opaque and the adaptors"; item 9 "adaptor half DONE (AdaptorUnit); P6Opaque half open".

- [ ] **Step 4: Ledger, memory, commit**: sync the ledger twin; commit rakudo docs (`git add docs AGENTS.md CLAUDE.md && git commit -m "docs: unit artifact milestone 4 done -- ..."`); the controller updates memory (`unit-artifact-milestones`, `truffle-plan-position`, `all-qast-via-truffle` marked DONE, `MEMORY.md`).

- [ ] **Step 5: Handoff rebase and push** (user rule): rakudo `git fetch origin && git rebase origin/main` on the worktree branch; nqp `git fetch upstream && git rebase upstream/main`; then `git push --force-with-lease ab5tract worktree-jesp-direct-lazy-records` (rakudo) and `git push --force-with-lease ab5tract jesp-direct-lazy-records` plus `git push --force-with-lease origin jesp-direct-lazy-records` (nqp). No gate after the rebase (user, 2026-09-09).

---

## Self-review notes

- Spec coverage: section 1 (driver, records, reader, registries, Backend, stage lists, nqp and Rakudo Ops.nqp) = Tasks 1-3; section 2 (stage0) = Task 4; section 3 (runtime deletions, loader port, BytecodeVersion, CompilationUnit reshaped, IndyBootstrap, EvalServer, autosplit test, Makefile.in) = Tasks 5-6 (the reflective half of CompilationUnit and CodeRefAnnotation deliberately move to Task 7, with their last client); section 4 (adaptors) = Task 7; section 5 (5a/5b/5c) = Tasks 8-10; section 6 (guard rails) = Task 1 Step 3's target check, Task 4 Step 6's rule; section 7 (gates) = each task's test steps and Task 11; "Sequence" = the task order; docs/ledger/handoff = Task 11.
- Placeholder scan: none of the forbidden phrases; every code step shows the code; Tasks 8-10 carry explicit time boxes and rulings because they are investigations, and each names its probe, its files and its gate.
- Type consistency: `QAST::UnitCompiler.unit(:$unit_id)` / `compile_block` (Task 1) are what Task 1's Backend and encoder call; `RecordReader.read` is what `UnitWriter.record(unit, tc)` calls and the two `-record` syscalls use; `AdaptorUnit(cls, descriptors, target)` (Task 7) matches both `computeInterop` edits; `getCodeRefs(): Array<CodeRef>` non-null from Task 5 on (KnowHOWMethods updated in Task 5, AdaptorUnit in Task 7); `leaveTorn` replaces `countLeft` everywhere (Task 8); `NqpCont.Suspend.finish` / `NqpOps.suspendToken(sse, finish)` / `NqpTypeOps.SuspendedIn` (Task 9) agree across the four files.
