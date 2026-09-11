# Task 6 report: The JAST record carries the unit, Compiler.nqp's artifact road

Status: DONE. nqp commit `1517f9cec` (branch jesp-direct-lazy-records, nested nqp tree).

## Edits, with their final locations

All line numbers are post-edit, in the nested nqp working tree
(`/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp`).
Every site was located by the brief's quoted code, not by the (stale) numbers.

### Step 1 — JASTNodes fields (`src/vm/jvm/QAST/JASTNodes.nqp`)

- `JAST::Class`: the 13 attributes added after `has @!nested_classes;` (lines 13-25),
  their BUILD initialisation after `@!nested_classes := [];` (lines 34-44), and the 13
  accessors after `method nested_classes` (lines 64-77), under the brief's two-line
  comment naming the spec.
- `JAST::Method`: `has int $!cr_qbid;` / `has int $!cr_program;` after `has @!cr_sections;`
  (lines 174-175), both set to `-1` at the end of BUILD (lines 196-197), accessors after
  `method cr_rawline` (lines 259-260).

### Step 2 — CodeRefBuilder (`src/vm/jvm/QAST/Compiler.nqp:3568-3570`)

`method callsite_data() { @!callsites }` added after `get_callsite_idx`, before `jastify`.

### Step 3 — unit prologue (`Compiler.nqp:4102-4111`)

`$*UNIT_ROAD` / `$*UNIT_FALLBACKS` declared immediately after
`my @*ENGINE_PROGRAMS := nqp::list_s();`, verbatim from the brief. Note the guard is
short-circuiting: `NQP_UNIT` absent means the `%*COMPILING` target lookup is never made,
and `&&` binds tighter than `?? !!`, so the three conditions are all required.

### Step 4 — static lexical values as data (`Compiler.nqp:4140-4160`)

The `if %*BLOCK_LEX_VALUES` body now branches: `$*UNIT_ROAD` builds the
`[qbid, name, handle, idx, flags]` rows and calls `$*JCLASS.blockvalues(@rows)`; the
`else` keeps the old `setup_blv` immediate block pushed onto `@post_des`, unchanged.
(`$*JCLASS` is declared at 3899 and `$*CODEREFS` at 3907, both well before these sites.)

### Step 5 — the ids (`Compiler.nqp`)

- `4245` `$*JCLASS.deserialize_qbid(...)` next to the deserializeQbid `PushIndex`
- `4260` `$*JCLASS.load_qbid(...)` next to loadQbid
- `4286` `$*JCLASS.entry_qbid(...)` next to entryQbid
- `4294` `$*JCLASS.hll($*HLL);` next to hllName
- `4301` `$*JCLASS.mainline_qbid(...)` next to mainlineQbid
- `4433-4435` `serialized_count` / `sc_handle` / `sc_desc` next to `serializedCodeRefCount`
  in `deserialization_code` (where `$sc` is in scope)
- `4306-4330` the programs block replaced with the brief's `if $*UNIT_ROAD { ... }
  elsif nqp::elems(@*ENGINE_PROGRAMS) { ...old joined sidecar... }`, census line
  env-gated on `NQP_CODE_WHY`.

### Step 6 — per-block record and the encoder (`Compiler.nqp`, `TruffleEncoder.nqp`)

- `Compiler.nqp:4630` `$*JMETH.cr_qbid(self.cuid_to_qbid($node.cuid));` right after the
  `JAST::Method.new( :name('qb_'~...` line.
- `Compiler.nqp:4717` `encode_block(... :comp_mode($*COMP_MODE), :sidecar($as_index),
  :unit_road($*UNIT_ROAD));`
- `Compiler.nqp:4724` `$*JMETH.cr_program($pidx);` after `nqp::push_s(@*ENGINE_PROGRAMS, ...)`.
- `Compiler.nqp:4744` `$*UNIT_FALLBACKS := $*UNIT_FALLBACKS + 1 if $*UNIT_ROAD;` as the
  first statement of the `else` around `compile_all_the_stmts` (the sole fallback junction:
  the `encode_block` call above it is unconditional, so every non-encoding block passes here).
- `TruffleEncoder.nqp:683` signature gains `:$unit_road`; `:698` the raw-blocktype refusal
  becomes `if $node.blocktype eq 'raw' && !$unit_road`, under the brief's three-line comment.

## Build

From the rakudo worktree root:

```
RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 NQP_CODE_STRICT=1 \
  raku tools/build/watched-run.raku \
  --log=/home/longwalker/.claude/jobs/b945970f/tmp/build-task6.log \
  --show='> Task :stage' --show='BUILD' --show='rror' \
  -- ./nqp/gradlew -p nqp clean buildJvm
```

Result: `BUILD SUCCESSFUL in 4m 40s`, watched-run `EXIT=0 verdict=ok elapsed=280s`.
Both stage1 and stage2 ran through CoreSetting/Nqp with no error line. No NQP_UNIT was
set, so this exercised the class road only — as intended for this task.

## Checks

- `unzip -l nqp/build/jvm/share/lib/nqp.jar | awk '/codeprograms/{n++} END{print n+0}'`
  → `1` (the joined sidecar entry is still written; the `grep -c` form was replaced with
  awk per the shell caveat).
- `RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'say("ok")'`
  → `ok`.

## Files changed

- `nqp/src/vm/jvm/QAST/JASTNodes.nqp` (+45)
- `nqp/src/vm/jvm/QAST/Compiler.nqp` (+63 -11)
- `nqp/src/vm/jvm/QAST/TruffleEncoder.nqp` (+6 -3)

115 insertions, 11 deletions over three files; nothing else added to the index.

## Self-review

- **Accessor names verbatim.** `JAST::Class`: hll, mainline_qbid, entry_qbid,
  deserialize_qbid, load_qbid, serialized_count, sc_handle, sc_desc, fallbacks,
  unit_road, programs, callsites, blockvalues. `JAST::Method`: cr_qbid, cr_program.
  Checked against the interface list character for character.
- **Class road untouched with NQP_UNIT unset.** `$*UNIT_ROAD` is 0, so: the joined
  sidecar string is still built and set via `codeprograms` (the `elsif` is the old
  condition and the old body), `setup_blv` is still pushed onto `@post_des`, and the
  encoder still refuses raw blocks (`!$unit_road` is true). The new `$*JCLASS.*` /
  `$*JMETH.*` calls outside the road guard only record values; they emit no bytecode
  and change no existing method. The build and both checks confirm this empirically.
- **All three conditions required** for `$*UNIT_ROAD`: env key, `target eq 'jar'`,
  `$cu.compilation_mode`.
- **`encode_block` gets `:unit_road`** at its single call site.
- **The census line is env-gated** on `NQP_CODE_WHY`; no bare `nqp::say` was added.

## Concerns

- The artifact road itself is untested here by construction — this task's build is the
  class road, and nothing yet reads the new record (Task 7's writer does). Two spots
  are worth a second look when it does:
  - `blockvalues` is set from `%*BLOCK_LEX_VALUES` before the deserialization code runs,
    so `nqp::getobjsc`/`scgetobjidx` are asked about the values at that point; if a value
    is not yet in an SC there, the row would carry a null handle. The class road's
    `setup_blv` resolves the same objects later, through the QAST tree.
  - `sc_handle`/`sc_desc` are recorded inside `deserialization_code`, which only runs for
    a unit that has one; a comp-mode unit always does, so on the artifact road (comp mode
    is required) they are always set, but they stay `''` on the class road.
- The build over the campaign's `custom_args` commit (nqp d13dcbf69) was clean — no
  P6BINDSIG/P6TRYBINDSIG trouble, so the BLOCKED contingency did not arise.

---

# Fix report — review round 1 (im-curious-as)

nqp commit `ac33e510c`, on top of `1517f9cec`. Two files: `Compiler.nqp`, `JASTNodes.nqp`.

## Important 1 — static lexical rows moved to after serialize

The push site (`Compiler.nqp:4139-4149`) now only *skips* `setup_blv` on the unit road:
`if %*BLOCK_LEX_VALUES && !$*UNIT_ROAD { ...unchanged push... }`, with a comment saying
where the rows are built instead. The row-building loop moved verbatim to
`Compiler.nqp:4232-4249`, immediately after `self.as_jast($block)` of the deserialize
wrapper and before the `deserializeQbid` method — i.e. exactly where the class road's
`setup_blv` block was compiled, after serialize/popcompsc and after every block has
registered its static lexicals. Guard: `if $*UNIT_ROAD && %*BLOCK_LEX_VALUES`. The
comment records why (serialization is what first assigns an SC; the hash keeps growing
until the wrapper itself has compiled).

## Important 2 — NQP_UNIT is all-or-nothing

At the fallback junction (`Compiler.nqp:4747-4754`), the `$*UNIT_FALLBACKS` increment is
replaced by the reviewer's `nqp::die(...)`, guarded `if $*UNIT_ROAD`, naming the block
(`<anon cuid>` when unnamed), its cuid, and the NQP_CODE_BAIL / NQP_CODE_WHY knobs.
`$*UNIT_FALLBACKS` and `$*JCLASS.fallbacks(...)` stay (always 0, the writer's defense);
the census line simplifies to `'code unit ' ~ $*JCLASS.name ~ ' -> artifact'`, still
gated on NQP_CODE_WHY. The prologue comment (`:4102-4109`) is rewritten to state the
all-or-nothing rule and why $*UNIT_FALLBACKS stays 0. The class road with the knob unset
is untouched by all of this.

## Minors

- (a) `Compiler.nqp:4110-4112`: conjuncts reordered to
  `existskey(getenvhash(), 'NQP_UNIT') && $cu.compilation_mode &&
  %*COMPILING<%?OPTIONS><target> eq 'jar' ?? 1 !! 0` — a runtime EVAL (no comp mode)
  short-circuits before the option lookup.
- (b) `JASTNodes.nqp:39-40`: `$!fallbacks := 0; $!unit_road := 0;` in `JAST::Class::BUILD`.
- (c) `JASTNodes.nqp:75`: one-line comment above the `unit_road` accessor,
  "1 = compiled on the NQP_UNIT road (every block encoded, or the compile died); the
  writer's input".

## Build and checks (class road, no NQP_UNIT)

```
RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 NQP_CODE_STRICT=1 \
  raku tools/build/watched-run.raku \
  --log=/home/longwalker/.claude/jobs/b945970f/tmp/build-task6-fix1.log \
  --show='> Task :stage' --show='BUILD' --show='rror' \
  -- ./nqp/gradlew -p nqp clean buildJvm
```

`BUILD SUCCESSFUL in 4m 40s`, watched-run `EXIT=0 verdict=ok elapsed=280s` — the same
wall time as the pre-fix build. Checks: sidecar `codeprograms` entries in nqp.jar = 1;
`./nqp/nqp-j-gradle -e 'say("ok")'` → `ok`.

## Remaining note

The "blockvalues rows before serialize" concern from the first report is resolved by
Important 1. The `sc_handle`/`sc_desc` note stands as written (recorded inside
`deserialization_code`, which a comp-mode unit always has; `''` on the class road).
The artifact road itself remains unexercised until Task 7's writer runs.
