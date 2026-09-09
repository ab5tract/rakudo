### Task 6: The JAST record carries the unit, Compiler.nqp's artifact road

**Files:**
- Modify: `nqp/src/vm/jvm/QAST/JASTNodes.nqp:4-40` (JAST::Class), `:113-190` (JAST::Method)
- Modify: `nqp/src/vm/jvm/QAST/Compiler.nqp:3555-3570` (CodeRefBuilder), `:4092-4131` (unit prologue, setup_blv), `:4242-4256` (entry qbid), `:4270-4281` (programs), `:4381-4384` (serialized count), `:4576-4578` (method name), `:4653-4694` (engine body), `:4685` (fallback junction)
- Modify: `nqp/src/vm/jvm/QAST/TruffleEncoder.nqp:660,695` (`:unit_road`, raw accepted)

**Interfaces:**
- Produces on `JAST::Class`: `hll`, `mainline_qbid`, `entry_qbid`, `deserialize_qbid`, `load_qbid`, `serialized_count`, `sc_handle`, `sc_desc`, `fallbacks`, `unit_road`, `programs` (list of str), `callsites` (list of `[@flags, @names]`), `blockvalues` (list of `[qbid, name, handle, idx, flags]`).
- Produces on `JAST::Method`: `cr_qbid`, `cr_program` (both `-1` by default).
- Produces the dynamic `$*UNIT_ROAD` (1 when `NQP_UNIT` is set, `--target=jar`, comp mode) and `$*UNIT_FALLBACKS`.

- [ ] **Step 1: JASTNodes fields**

In `JAST::Class` add attributes after `@!nested_classes;`:

```
    has str $!hll;
    has int $!mainline_qbid;
    has int $!entry_qbid;
    has int $!deserialize_qbid;
    has int $!load_qbid;
    has int $!serialized_count;
    has str $!sc_handle;
    has str $!sc_desc;
    has int $!fallbacks;
    has int $!unit_road;
    has @!programs;
    has @!callsites;
    has @!blockvalues;
```

in `BUILD` add:

```
        $!hll := '';
        $!mainline_qbid := -1;
        $!entry_qbid := -1;
        $!deserialize_qbid := -1;
        $!load_qbid := -1;
        $!serialized_count := -1;
        $!sc_handle := '';
        $!sc_desc := '';
        @!programs := [];
        @!callsites := [];
        @!blockvalues := [];
```

and accessors after `nested_classes`:

```
    # The unit artifact's record (docs/superpowers/specs/2026-09-09-jvm-unit-artifact-design.md):
    # what the writer reads off this class instead of assembling bytecode.
    method hll(*@value) { @value ?? ($!hll := @value[0]) !! $!hll }
    method mainline_qbid(*@value) { @value ?? ($!mainline_qbid := @value[0]) !! $!mainline_qbid }
    method entry_qbid(*@value) { @value ?? ($!entry_qbid := @value[0]) !! $!entry_qbid }
    method deserialize_qbid(*@value) { @value ?? ($!deserialize_qbid := @value[0]) !! $!deserialize_qbid }
    method load_qbid(*@value) { @value ?? ($!load_qbid := @value[0]) !! $!load_qbid }
    method serialized_count(*@value) { @value ?? ($!serialized_count := @value[0]) !! $!serialized_count }
    method sc_handle(*@value) { @value ?? ($!sc_handle := @value[0]) !! $!sc_handle }
    method sc_desc(*@value) { @value ?? ($!sc_desc := @value[0]) !! $!sc_desc }
    method fallbacks(*@value) { @value ?? ($!fallbacks := @value[0]) !! $!fallbacks }
    method unit_road(*@value) { @value ?? ($!unit_road := @value[0]) !! $!unit_road }
    method programs(*@value) { @value ?? (@!programs := @value[0]) !! @!programs }
    method callsites(*@value) { @value ?? (@!callsites := @value[0]) !! @!callsites }
    method blockvalues(*@value) { @value ?? (@!blockvalues := @value[0]) !! @!blockvalues }
```

In `JAST::Method` add `has int $!cr_qbid;` and `has int $!cr_program;`, set both to `-1` in `BUILD`, and add accessors `method cr_qbid(*@value) { @value ?? ($!cr_qbid := @value[0]) !! $!cr_qbid }` and `method cr_program(*@value) { @value ?? ($!cr_program := @value[0]) !! $!cr_program }`.

- [ ] **Step 2: CodeRefBuilder exposes the call-site data**

In Compiler.nqp's `CodeRefBuilder` (after `get_callsite_idx`, line 3566) add:

```
        # The artifact road reads the descriptors as data instead of the
        # getCallSites bytecode: [@arg_types, @arg_names] per site.
        method callsite_data() { @!callsites }
```

- [ ] **Step 3: The unit prologue**

After `my @*ENGINE_PROGRAMS := nqp::list_s();` (line 4097) add:

```
        # The artifact road (rakudo docs/superpowers/specs/2026-09-09-jvm-
        # unit-artifact-design.md): under NQP_UNIT a jar-bound comp-mode
        # unit is written as programs + serialized context + block table,
        # no class file, PROVIDED every block encoded. $*UNIT_FALLBACKS
        # counts the blocks that did not; the backend takes the class road
        # for a unit with any.
        my $*UNIT_ROAD := nqp::existskey(nqp::getenvhash(), 'NQP_UNIT')
            && %*COMPILING<%?OPTIONS><target> eq 'jar'
            && $cu.compilation_mode ?? 1 !! 0;
        my $*UNIT_FALLBACKS := 0;
```

- [ ] **Step 4: Static lexical values as data**

Replace lines 4126-4131

```
        if %*BLOCK_LEX_VALUES {
            nqp::push(@post_des, QAST::Block.new(
                :blocktype('immediate'),
                QAST::Op.new( :op('setup_blv'), %*BLOCK_LEX_VALUES )
            ));
        }
```

with

```
        if %*BLOCK_LEX_VALUES {
            if $*UNIT_ROAD {
                # The artifact's meta carries them; the loader installs them
                # after the deserialize program, where setup_blv ran.
                my @rows;
                for %*BLOCK_LEX_VALUES {
                    my int $qbid := self.cuid_to_qbid($_.key);
                    for $_.value -> @lex {
                        my $sc := nqp::getobjsc(@lex[1]);
                        nqp::push(@rows, [$qbid, @lex[0], nqp::scgethandle($sc),
                            nqp::scgetobjidx($sc, @lex[1]), @lex[2]]);
                    }
                }
                $*JCLASS.blockvalues(@rows);
            }
            else {
                nqp::push(@post_des, QAST::Block.new(
                    :blocktype('immediate'),
                    QAST::Op.new( :op('setup_blv'), %*BLOCK_LEX_VALUES )
                ));
            }
        }
```

- [ ] **Step 5: Record the ids**

Where the deserialize block is registered (line 4213-4216, the `deserializeQbid` method), add `$*JCLASS.deserialize_qbid(self.cuid_to_qbid($block.cuid));` next to the `PushIndex`. Where `loadQbid` is built (4227-4230) add `$*JCLASS.load_qbid(self.cuid_to_qbid($load_block.cuid));`. Where `entryQbid` is built (4252-4255) add `$*JCLASS.entry_qbid(self.cuid_to_qbid($main_block.cuid));`. Next to `hllName` (4259) add `$*JCLASS.hll($*HLL);`, next to `mainlineQbid` (4265) add `$*JCLASS.mainline_qbid(self.cuid_to_qbid($cu[0].cuid));`. In `deserialization_code`, next to `serializedCodeRefCount` (4381-4384) add `$*JCLASS.serialized_count(+@code_ref_blocks); $*JCLASS.sc_handle(nqp::scgethandle($sc)); $*JCLASS.sc_desc(nqp::scgetdesc($sc));`.

Replace the programs block at 4270-4279 with:

```
        # Engine programs collected from jar-bound blocks. On the artifact
        # road they go to the writer as a list (byte-framed by it); on the
        # class road they travel as one sidecar entry, joined here, last,
        # so every block -- the deserialize and load methods included --
        # has had its say.
        if $*UNIT_ROAD {
            # A boxed list: @*ENGINE_PROGRAMS is a native str list, and
            # the writer reads its record through at_pos_boxed.
            my @progs;
            for @*ENGINE_PROGRAMS -> str $p { nqp::push(@progs, $p) }
            $*JCLASS.programs(@progs);
            $*JCLASS.callsites($*CODEREFS.callsite_data);
            $*JCLASS.fallbacks($*UNIT_FALLBACKS);
            $*JCLASS.unit_road(1);
            nqp::say('code unit ' ~ $*JCLASS.name ~ ' -> '
                ~ ($*UNIT_FALLBACKS ?? 'class fallbacks=' ~ $*UNIT_FALLBACKS !! 'artifact'))
                if nqp::existskey(nqp::getenvhash(), 'NQP_CODE_WHY');
        }
        elsif nqp::elems(@*ENGINE_PROGRAMS) {
            my @joined := [~nqp::elems(@*ENGINE_PROGRAMS)];
            for @*ENGINE_PROGRAMS -> str $p {
                nqp::push(@joined, ' ' ~ nqp::chars($p) ~ ':' ~ $p);
            }
            $*JCLASS.codeprograms(nqp::join('', @joined));
        }
```

- [ ] **Step 6: Per-block qbid, program index, fallback count, raw accepted**

At line 4576-4577 (`my $*JMETH := JAST::Method.new( :name('qb_'~...` ) add after it: `$*JMETH.cr_qbid(self.cuid_to_qbid($node.cuid));`.

In the engine-body branch, after `nqp::push_s(@*ENGINE_PROGRAMS, $engine_prog);` (line 4673) add `$*JMETH.cr_program($pidx);`. Change the `encode_block` call (4661-4662) to pass the road: `:comp_mode($*COMP_MODE), :sidecar($as_index), :unit_road($*UNIT_ROAD)`.

At the fallback junction (the `else` at 4684-4687 around `compile_all_the_stmts`) add as its first statement: `$*UNIT_FALLBACKS := $*UNIT_FALLBACKS + 1 if $*UNIT_ROAD;`.

In `TruffleEncoder.nqp`, change the signature at line 660 to `method encode_block($node, $block, $comp, :$comp_mode, :$sidecar, :$unit_road)` and line 695 to:

```
        # A raw block (Compiler.nqp's own deserialize/load/main wrappers)
        # is a parameterless declaration to the engine; on the class road
        # its body stays bytecode, on the artifact road it must encode.
        if $node.blocktype eq 'raw' && !$unit_road { trace('no: raw blocktype'); return '' }
```

- [ ] **Step 7: Stage build (class road), proving nothing regressed**

Run from the rakudo worktree root, without `NQP_UNIT` (the class road must be byte-for-byte the old behaviour):

```bash
RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 NQP_CODE_STRICT=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/b945970f/tmp/build-task6.log --show='> Task :stage' --show='BUILD' --show='rror' -- ./nqp/gradlew -p nqp clean buildJvm
```

Expected: `BUILD SUCCESSFUL` (about 10 min). Then `unzip -l nqp/build/jvm/share/lib/nqp.jar | grep -c codeprograms` prints `1`, and `RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'say("ok")'` prints `ok`.

- [ ] **Step 8: Commit (nqp tree)**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git add src/vm/jvm/QAST/JASTNodes.nqp src/vm/jvm/QAST/Compiler.nqp src/vm/jvm/QAST/TruffleEncoder.nqp && git commit -F - <<'EOF'
unit artifact: the JAST record carries the unit (ids, programs, call sites, static lexical values); NQP_UNIT road in Compiler.nqp

The wrappers (raw blocks) encode on the artifact road; a fallback body is
counted, and the backend takes the class road for a unit with any.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRn8gLyZjirBAKS6urb3n4
EOF
```

---

