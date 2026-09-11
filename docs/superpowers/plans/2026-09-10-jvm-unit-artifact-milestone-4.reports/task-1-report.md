# Task 1 report: the QAST-only driver, the unit record, the record reader

Milestone 4, task 1. All edits are in the nested **nqp** tree
(`.claude/worktrees/jesp-direct-lazy-records/nqp`).

Commit: **nqp `db4fc150e`** — "unit compiler: a QAST-only driver hands the
writer a unit record -- no JAST tree, no operand stack, no per-block stub;
the registries stay as data" (7 files, +1900 / -6309).

## What was implemented

**Step 1 — the record classes.** `QAST::UnitRecord` and `QAST::BlockRecord`
declared at the top of `nqp/src/vm/jvm/QAST/Compiler.nqp`, verbatim from the
brief (attribute names are the reader's contract). `use JASTNodes;` is gone
from the file.

**Step 2 — the registries.** `QAST::OperationsJAST` is now
`QAST::OperationsJVM`, holding only data: the two inlinability tables with
`set_core_op_inlinability` / `set_hll_op_inlinability` / `is_inlinable`,
registry-only `map_classlib_core_op` / `map_classlib_hll_op`, and the new
`core_op_supported` (classlib registry OR `QAST::TruffleEncoder.supports_op`).
Deleted: `compile_op`, `add_core_op`, `add_hll_op`, `add_hll_box`,
`add_hll_unbox`, `box`, `unbox`, `op_mapper`, `result`, the result-type
tables and their setters (`attach_result_type` included — the encoder reads
none of them), `map_jvm_core_op`/`map_jvm_hll_op`, the `Result` class,
`result`/`result_from_cf`, `%WANTMAP`, the JAST instruction constants,
`$INDY_SITE_BUDGET`, `@store_ins`/`@load_ins`/`@dup_ins`/`@pop_ins` and their
subs, `fresh`/`bfresh`, the `$ARG_*` flag table, and all 52 `add_core_op`
closures plus every `map_jvm_*` call. All 625 `map_classlib_core_op` calls are
kept verbatim (with their section comments), renamed to the new class.

`%const_map` and its `nqp::bindhllsym('nqp', 'CODE_CONST_MAP', ...)` are kept
— the encoder reads that hllsym for `nqp::const`. (Dropping it was the one
mistake of the first build; see "Builds" below.)

In `TruffleEncoder.nqp`, a knob-independent `supports_op(str $name)` was added
beside `covered_from_table` (it needs `%emit_ops`, so it sits after that
declaration): it calls `emit_init()`, folds `name/arity` keys to bare names,
adds `$extra_ops` and the `CODE_OP_DESUGARS` registry, and caches the set.

**Step 3 — driver entry and unit walk.** `QAST::CompilerJAST` →
`QAST::UnitCompiler`. `method jast($source, :$classname!)` →
`method unit($source, :$unit_id!)` building `$*UNIT`/`$*CODEREFS` and calling
`compile_unit`. `multi method as_jast(QAST::CompUnit)` → `method
compile_unit($cu)`: every `$*JCLASS.<field>` became `$*UNIT.<field>`, every
`JAST::Method` emission group (deserializeQbid, loadQbid, main, entryQbid,
hllName, mainlineQbid) was deleted keeping only the record field it also set,
and the `--target=classfile` die became the brief's `classfile`/`jast`
message. `deserialization_code` keeps its QAST building; its four `$*JCLASS`
writes are now `$*UNIT` writes (`nested_units`, `serialized`,
`serialized_count`, `sc_handle`, `sc_desc`) and the `serializedCodeRefCount`
JAST method is gone. `need_set_code_object`, `cuid_to_qbid`, `unique`,
`source_for_node` kept; `emit_param_tasks`, `param_can_bind_fail`,
`try_setup_args_expectation` and the `$ARG_EXP_*` constants deleted (JAST-only).

**Step 4 — the block walk.** `multi method as_jast(QAST::Block)` → the
brief's `method compile_block($node)`, verbatim. `CodeRefBuilder` keeps
`register_block` (was `register_method`), `know_cuid`, `cuid_to_idx`,
`get_callsite_idx`, `callsite_data`; `take_indy_site`, `indy_sites`,
`cuid_to_jastmethname`, `cuid_to_args_expectation`, `jastify`, `callsites`
deleted. `BlockInfo` keeps exactly what the encoder and the driver call
(ruling 4: grep of `$block.` / `$*BLOCK.` in the encoder shows only
`add_lexical` and `add_lexicalref`; the driver calls `new`, `qast`,
`lexical_names_by_type`, and `nqp::istype($outer, BlockInfo)`): `new`,
`BUILD`, `add_lexical`, `add_lexicalref`, `register_lexical`,
`register_lexicalref`, `qast`, `outer`, the lexical type/returns/ref/idx
accessors and `lexical_names_by_type`. Deleted: `add_param`, `add_local`,
`tempify`/`untempify`, `register_local`, `locals`/`local_info`/`params`, the
local tables, `alloc_save_site`/`num_save_sites`. Also deleted: `StackState`,
`BlockTempAlloc`, `StmtTempAlloc`, `new_temp_allocator`,
`compile_all_the_stmts`, `compile_var`, every remaining `multi method
as_jast`, the `proto`/`want` pair, `coerce`/`coercion`, `unwind_check`,
`delimit_handler`, `engine_jast`, `savesite`, and the 20000-char refusal in
`rx_descriptor` (which is now just `QAST::RxDescriptor.encode($node)`; the
encoder already bails on a null descriptor). `rx_callback_block_for`'s group
comment now reads as a plain size limit. `$*EH_IDX`,
`&*REGISTER_UNWIND_HANDLER`, `&*REGISTER_BLOCK_HANDLER` kept live (ruling 5).

**Step 5 — the encoder's deferral.** `$comp.as_jast($blk)` + `$*STACK.obtain`
→ `$comp.compile_block($blk)`; the comments naming `as_jast`, `JAST`,
`jast2bc` are reworded throughout. The Step 12 grep over
Compiler.nqp/TruffleEncoder.nqp/Backend.nqp is empty.

**Step 6 — `RecordReader.kt`**, new, verbatim from the brief. Checked against
`JastMethod.kt:112-130`: `BlockRec.sourceLineDelta = rawline - line` and the
`file.isEmpty() -> null` handling are identical; `$!serialized` reads back
null (`nqp::null_s`) when the unit has no serialized context, which is what
`JAST::Class` did by leaving the attribute unset.

**Step 7 — writer + syscalls.** `UnitWriter.record(SixModelObject,
ThreadContext)` and `UnitWriter.write(SixModelObject, String, ThreadContext)`
added beside the JAST-typed pair; syscalls `jvm-write-unit-record` (OBJ, STR)
and `jvm-build-unit-record` (OBJ) added beside `jvm-write-unit`/`jvm-build-unit`.

**Step 8 — Backend.** `use JASTNodes;` gone; `stages()` is `'unit jar jvm'`;
`is_precomp_stage` is `unit`/`jar`; `jast`+`classfile` replaced by the
brief's `unit`; `jar` is the pass-through. `classname` KEPT under its own name
— `nqp/src/NQP/Compiler.nqp:33` registers it as a stage (`addstage('classname',
:after<start>)`), so renaming it would need an edit outside this task's files;
the name is not JAST-named, so it costs nothing.

**Controller ruling 1 — `nqp/src/vm/jvm/NQP/Ops.nqp`.** The 8 `add_hll_op`
blocks and the 4 `add_hll_unbox` blocks, plus the constants only they used and
the `QAST::CompilerJAST.operations()` line, are gone; the file is now a
comment explaining what left and where a classlib-mapped NQP op would go.
There were no `map_classlib_hll_op` calls in it.

## Testing

| step | command | result |
|---|---|---|
| 9 runtime jars | `./nqp/gradlew -p nqp :nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars` | BUILD SUCCESSFUL in 10s, tests green |
| 10 clean build | `RAKUDO_RAKUAST=1 NQP_CODE_STRICT=1 raku tools/build/watched-run.raku ... -- ./nqp/gradlew -p nqp clean buildJvm` | `=== EXIT=0 verdict=ok elapsed=214s ===` (3m 34s) |
| 10 jar census | `raku tools/build/jar-census.raku nqp/build/jvm/share/lib/*.jar` | `CENSUS: all 11 jars are unit artifacts` (meta=1 class=0 each) |
| 11 t/nqp + t/qast | `RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=nqp/t/nqp -t=nqp/t/qast --jobs=3 ... -- nqp/nqp-j-gradle` | `117 of 120 ok in 345s` |
| 11 the two cwd-relative files, rerun from `nqp/` | `RAKUDO_RAKUAST=1 ./nqp-j-gradle t/nqp/019-file-ops.t` / `t/nqp/063-slurp.t` | both green (112 and 1 tests) |
| 12 leftover grep | `grep -n 'JAST\|as_jast\|$*JCLASS\|$*JMETH\|$*STACK\|jastify\|INDY_SITE' <the three files>` | empty |

The sweep's three reds are exactly the brief's expected set: **t/nqp
118/118** (116 green in the sweep; `019-file-ops.t` and `063-slurp.t` are
cwd-relative and pass when run from `nqp/`, shown above) and **t/qast 1/2**
(`02-manipulation.t` green; `01-qast.t` is moar-only — it fails test 10 on a
message string that only `src/vm/moar/QAST/QASTCompilerMAST.nqp` produces
("has not appeared"), then dies calling `$backend.start`, a method
`HLL::Backend::JVM` has never had). `123-unit-artifact.t` and
`124-unit-record.t`, the road's own tests, are green.

Logs: `/home/longwalker/.claude/jobs/25fa1a35/tmp/t1-build2.log`,
`.../t1-sweep-logs/`.

### The one failed build

The first `clean buildJvm` failed at `stage2CompileCoreSetting` with
`code-bail const map unpublished`: my first cut of the trimmed Compiler.nqp
kept only the `map_classlib_core_op` calls out of the old op region and so
dropped `%const_map` and its `nqp::bindhllsym('nqp', 'CODE_CONST_MAP', ...)`,
which `TruffleEncoder.encode_op_tail` reads for `nqp::const`. Restored
verbatim, plus an audit of every other top-level statement in the deleted
region (only `%const_map` had an effect outside the JAST closures: the other
file-scope `my`s were `%handler_names`/`%control_map`/the three codegen
closures, and the subs were all JAST emitters; the encoder carries its own
copies of `needs_cond_passed` and `native_assign_bind_scope`). The second
build is the one reported above; no comparison build was run.

## Files changed (all under `nqp/`)

- `src/vm/jvm/QAST/Compiler.nqp` — **6363 → 1950 lines**
- `src/vm/jvm/QAST/TruffleEncoder.nqp` — `supports_op` added, deferral
  rewritten, comments reworded
- `src/vm/jvm/HLL/Backend.nqp` — stages, `unit`, `jar`
- `src/vm/jvm/NQP/Ops.nqp` — 177 → 9 lines (comment only)
- `src/vm/jvm/runtime/org/raku/nqp/runtime/unit/RecordReader.kt` — new, 138 lines
- `src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitWriter.kt` — two overloads
- `src/vm/jvm/runtime/org/raku/nqp/dispatch/Syscalls.kt` — two syscalls

`UnitRecord.kt` untouched; no wire-format change; every new diagnostic is
env-gated (`NQP_CODE_WHY`).

## Self-review findings

- Every brief step is done and the Step 12 grep is empty.
- **`callsite_data` is empty by construction on this road.** Nothing calls
  `get_callsite_idx` any more (only JAST op closures did), so
  `$*UNIT.callsites` is always `[]` and `UnitMeta.callSites` is empty. That
  was already true before this task (every block body has been one engine
  program since milestone 3), so the record is unchanged in content; the brief
  says to keep both methods and I did. If a later task wants the field gone,
  it is dead weight, not a regression.
- `@!sections` is never fed (as the brief's comment says); `add_section` is
  present so the reader's section fields have a source.
- The block record's file backfill now comes from `$*UNIT.file` (captured from
  `$?FILES` at `unit()` time) instead of re-reading `$?FILES` per block, as the
  brief specifies. Same value in every case the old code hit.

## Concerns

1. **Rakudo will not build until Task 2.** `src/vm/jvm/Raku/Ops.nqp` calls
   `$ops.add_hll_op` (19 sites, `register_op_desugar` included) and
   `$qastcomp.as_jast` / `$qastcomp.result`, all of which this task deleted.
   That is exactly what the spec assigns to the Rakudo half; nothing in this
   task's gate (nqp only) touches it, and no Rakudo `make` was run.
2. **`QAST::TruffleEncoder.supports_op` calls `emit_init()`** — the brief's
   sketch iterated `%emit_ops` without it, but the table is populated only by
   `emit_init` (which `covered_from_table` also calls first). Added; the shape
   is otherwise the brief's.
3. `nqp/t/jvm/09-autosplit.t` and the stale `jast2bc` comment in
   `nqp/tools/templates/jvm/Makefile.in` are untouched (Task 3's list).
4. `TruffleEncoder.nqp:1324` still says a `QAST::VM` without a `jvm`
   alternative "would not compile on the class road either" — a class-road
   mention the spec assigns to Task 3's comment sweep, and outside the Step 12
   grep.

---

# Fix round 1 — `supports_op` under-reported the encoder's hand rows

Review finding (Important): `supports-op` answered false for ops the encoder
does compile, because `supports_op` saw only `%emit_ops`, `$extra_ops` and the
desugar registry — not the hand rows in `encode_op`'s `$name eq '…'` chain.
Controller ruling: the spec's rule is "the classlib registry maps it OR the
encoder has a row for it", and a hand row IS a row.

## What changed (`nqp/src/vm/jvm/QAST/TruffleEncoder.nqp`, one file)

**The data.** I audited the whole if-chain rather than taking the reviewer's
list as final: extracted every `$name eq '…'` name in the file (69 distinct),
extracted every `op3('…')` key folded to its bare name (105), and diffed both
against `$extra_ops`. That left **14** hand-row names covered by neither table
nor list, and they are now in `$extra_ops`:

    indexingoptimized  p6invokeflat  p6return  postdec  postinc  rindex
    settypefinalize    sprintf       sprintfdirectives  sprintfaddargumenthandler
    syscall            with          without   xor

Seven of those the reviewer's list did not name (`p6invokeflat`, `p6return`,
`postinc`, `postdec`, `syscall`, `with`, `without`); two it did name (`index`,
`ord`) were already in `%emit_ops`, and I added them to the list anyway so the
list reads as "every hand row" rather than "every hand row that happened to be
missing". Re-running the diff after the edit leaves **no** hand row uncovered.

I checked the dispatch shape too: `$name eq` is the only op-name dispatch in
`encode_op`/`encode_op_tail` (the only prefix test is `nqp::eqat($name,
'repeat_', 0)` inside the already-listed while/until group; every other
`{$name}` in the file indexes the locals/lexicals tables, not an op table), so
the audit is complete and stays complete by the same two greps.

The six ops with no row on either side — `takedispatcher`,
`takenextdispatcher`, `cleardispatcher`, `clearnextdispatcher`, `wantdecont`,
`setup_blv` (verified: zero occurrences in TruffleEncoder.nqp and in
Compiler.nqp's classlib registry) — are named in a comment above `$extra_ops`
as deliberately absent, with the reason `supports-op` must say no for them.
The comment also states the rule for the next person: a new hand row goes in
this list, and it is derived by diffing `$name eq '…'` against the op3 table.

**The function.** `supports_op` now caches only the table + `$extra_ops` half
and consults `CODE_OP_DESUGARS` on every call (the related minor): Rakudo
publishes that registry and then keeps growing it through
`register_op_desugar`, so the old single snapshot could cache a false "no" for
a desugar registered after the first probe.

## Covering tests

| what | command | output |
|---|---|---|
| clean build | `RAKUDO_RAKUAST=1 NQP_CODE_STRICT=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/25fa1a35/tmp/t1-fix1-build.log ... -- ./nqp/gradlew -p nqp clean buildJvm` (background) | `BUILD SUCCESSFUL in 3m 33s` / `=== EXIT=0 verdict=ok elapsed=213s ===` |
| the probe | `RAKUDO_RAKUAST=1 nqp/nqp-j-gradle -e 'say(nqp::getcomp("nqp").supports-op("index")); say(nqp::getcomp("nqp").supports-op("sprintf")); say(nqp::getcomp("nqp").supports-op("dispatch_v")); say(nqp::getcomp("nqp").supports-op("nosuchop"))'` | `1` `1` `1` `0` — exactly as expected |
| road tests | `RAKUDO_RAKUAST=1 nqp/nqp-j-gradle nqp/t/nqp/123-unit-artifact.t` | 8 ok, 0 not ok |
| road tests | `RAKUDO_RAKUAST=1 nqp/nqp-j-gradle nqp/t/nqp/124-unit-record.t` | 11 ok, 0 not ok |

No full sweep was rerun (not required for this fix). Forward only: one build.

Commit amended in place — nqp **`c6af33aa3`** (was `db4fc150e`), same message,
7 files, +1920 / -6311.

## Concerns after the fix

- Unchanged from above: **Rakudo still will not build until Task 2**
  (`src/vm/jvm/Raku/Ops.nqp` uses the deleted `add_hll_op` / `as_jast` /
  `result`).
- `$extra_ops` now carries two jobs — the survey's coverage tags and
  `supports-op`'s answer. They want the same set today and the comment says so,
  but if they ever diverge this list is where the divergence will bite.
