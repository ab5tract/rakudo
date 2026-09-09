### Task 2: The compiler takes every unit down the road under the knob

**Files:**
- Modify: `nqp/src/vm/jvm/QAST/Compiler.nqp:4101-4113` (road decision), `:4152` (wrapper condition), `:4349-4356` (comment), `:4699-4709` (`$as_index`), `:4317-4327` (census line)
- Modify: `nqp/src/vm/jvm/HLL/Backend.nqp:79-106` (`classfile`)
- Modify: `nqp/src/vm/jvm/QAST/TruffleEncoder.nqp:919-943, 1044-1050, 1053-1072, 2601-2612` (splice sites)
- Modify: `nqp/src/vm/jvm/QAST/JASTNodes.nqp:65` (comment)

**Interfaces:**
- Consumes (Task 1): syscall `jvm-build-unit` (OBJ, OBJ) -> `EvalResult`; `nqp::loadcompunit` on a record-bearing `EvalResult`; `NQP_CODE_WHY` line `unit record <id> ...` on stderr.
- Produces: `$*UNIT_ROAD` = 1 for every unit when `NQP_UNIT` is set; `HLL::Backend::JVM.classfile` returns an `EvalResult` for a unit-road unit without `--target=jar --output`; the encoder's `splice_code(%e, @words, int $at)`.

- [ ] **Step 1: Compiler.nqp, the road decision and the knob checks**

Replace lines 4101-4113 (the comment block and the `$*UNIT_ROAD` / `$*UNIT_FALLBACKS` declarations) with:

```nqp
        # The artifact road (rakudo docs/superpowers/specs/2026-09-09-jvm-
        # unit-artifact-design.md): under NQP_UNIT every unit is a record --
        # programs + block table (+ serialized context for a comp-mode
        # unit), no class file. A jar-bound unit with an output file is
        # written as a zip (milestone 1); any other unit -- a script, an
        # EVAL, a BEGIN-time unit, a --target=jar with no --output -- is
        # built in memory and loaded as a ProgramUnit (milestone 2). The
        # knob is all-or-nothing: the road is chosen before any block
        # compiles, so a block that cannot encode is a compile error, not
        # a quiet fallback to a class file that this road no longer emits
        # the pieces for. $*UNIT_FALLBACKS therefore stays 0 and travels
        # as the writer's defense. Off, the class road runs as before.
        my $*UNIT_ROAD := nqp::existskey(nqp::getenvhash(), 'NQP_UNIT') ?? 1 !! 0;
        my $*UNIT_FALLBACKS := 0;
        if $*UNIT_ROAD {
            # Every block must encode, so the encoder's own switches must
            # be on; said once here rather than once per block at the
            # fallback junction.
            my %env := nqp::getenvhash();
            nqp::die('unit artifact (NQP_UNIT): the road needs NQP_CODE_RUN=1 and NQP_CODE_PRECOMP=1 set, every block must encode')
                unless nqp::existskey(%env, 'NQP_CODE_RUN') && nqp::existskey(%env, 'NQP_CODE_PRECOMP');
            # A class file is the one output the road does not have.
            nqp::die('unit artifact (NQP_UNIT): --target=classfile has no artifact form; use --target=jar')
                if %*COMPILING<%?OPTIONS><target> eq 'classfile';
        }
```

- [ ] **Step 2: Compiler.nqp, the wrapper condition**

At line 4152, `if $*COMP_MODE || @pre_des || @post_des || need_set_code_object($cu) {`, change to:

```nqp
        # On the class road setup_blv sat in @post_des and made this true
        # by itself; the record road builds its static-lexical-value rows
        # inside this wrapper, so the wrapper must exist for them.
        if $*COMP_MODE || @pre_des || @post_des || need_set_code_object($cu)
            || ($*UNIT_ROAD && %*BLOCK_LEX_VALUES) {
```

- [ ] **Step 3: Compiler.nqp, `$as_index` and comments**

At lines 4699-4709 replace the comment and the `$as_index` declaration with:

```nqp
                # A jar-bound unit's programs travel in one sidecar,
                # referenced by index -- one string constant per
                # program overflowed CORE.c's constant pool (71010
                # entries against the 65535 limit) -- and on the unit
                # road every program is a byte-framed entry of the
                # record, on either output, with no constant and no cap.
                # Everything else keeps the string road. The encoder is
                # told which, so its per-program size gate (the string
                # constant's own 65535-byte cap) applies only where that
                # cap exists.
                my int $as_index := $*UNIT_ROAD
                    || ($*COMP_MODE && %*COMPILING<%?OPTIONS><target> eq 'jar');
```

At lines 4349-4356 (the opening comment of `deserialization_code`), change "Their classfiles ride along in the jar" to "Their units ride along in the jar (as class entries on the class road, under nested/ in an artifact)". At line 4326, change the census text to `' -> unit road'` (the writer and loadcompunit each say which output they produced).

In `JASTNodes.nqp` line 65 add above `method nested_classes`: `# Unit ids (class names on the class road) of nested in-memory units this unit's serialization points into.`

- [ ] **Step 4: Backend.nqp, route the record road**

Replace lines 79-106 of `classfile` (from `if (%adverbs<target> eq 'classfile' ...` through the closing `else { nqp::compilejast(...) }`) with:

```nqp
        if $jast.unit_road {
            # The artifact road (NQP_UNIT). A jar-bound unit with an
            # output file is written as a zip; every other unit -- a
            # script, an EVAL, a BEGIN-time unit, a --target=jar with no
            # --output -- is built in memory as a record, which the jvm
            # stage (nqp::loadcompunit) turns into a ProgramUnit. No class
            # file either way; Compiler.nqp refuses --target=classfile on
            # this road, and it is the writer, not this junction, that
            # refuses a unit with fallbacks (there are none: the compiler
            # died first).
            if %adverbs<target> eq 'jar' && %adverbs<output> {
                # The syscall's argument kinds are checked at the call
                # site; %adverbs<output> arrives boxed.
                my str $unit_output := %adverbs<output>;
                nqp::syscall('jvm-write-unit', $jast, %jastnodes, $unit_output);
                nqp::null()
            }
            else {
                nqp::syscall('jvm-build-unit', $jast, %jastnodes)
            }
        }
        elsif (%adverbs<target> eq 'classfile' || %adverbs<target> eq 'jar') && %adverbs<output> {
            nqp::compilejasttofile($jast, %jastnodes, %adverbs<output>);
            nqp::null()
        }
        else {
            nqp::compilejast($jast, %jastnodes);
        }
```

- [ ] **Step 5: TruffleEncoder.nqp, the splice_code helper**

Add, directly above `method patch_params` (line 919):

```nqp
    # Splices @words into the program at $at and moves every nested-block
    # slot the walk recorded by position at or after $at right by the
    # same amount, so the deferred qbid patch still lands on its CODEREF
    # cell. One rule serves both callers: a prologue goes in after its
    # placeholder ($at is the placeholder's index + 1, so the placeholder
    # itself stays put), a coercion goes in at the mark of the subtree it
    # wraps. Splicing without the shift wrote every deferred qbid over
    # the tag of a neighbouring node ("unknown tag 11142", 2026-09-09).
    sub splice_code(%e, @words, int $at) {
        nqp::splice(%e<code>, @words, $at, 0);
        my int $n := nqp::elems(@words);
        for %e<nested> -> $nb {
            nqp::bindpos($nb, 0, $nb[0] + $n) if $nb[0] >= $at;
        }
    }
```

Then replace the four sites:

1. `patch_params`, custom_args (lines 937-941): the `my @hdr := nqp::list(0, -1, 0);` line stays; replace the `nqp::splice(...)` line and the following `for %e<nested>` loop (three lines) with `splice_code(%e, @hdr, $params_at + 1);`. Trim the comment above (lines 928-936) to its first sentence plus "(splice_code moves the slots)".
2. `patch_params`, full prologue (lines 1044-1050): replace `nqp::splice(%e<code>, @p, $params_at + 1, 0);`, the two comment lines, and the `for` loop (three lines) with `splice_code(%e, @p, $params_at + 1);`.
3. `encode_child` (lines 1064-1070): replace the `nqp::splice(...)` line, the three comment lines and the `for` loop with `splice_code(%e, [$W_COERCE, $kind], $mark);`.
4. `coerce_at` (lines 2606-2609): replace the `nqp::splice(...)` line and the `for` loop with `splice_code(%e, [$W_COERCE, $kind], $mark);`.

Equivalence, for the reviewer: sites 1 and 2 shifted when `$nb[0] > $params_at`, which is `$nb[0] >= $params_at + 1`, the helper's rule at `$at = $params_at + 1`; sites 3 and 4 shifted when `$nb[0] >= $mark`, the helper's rule at `$at = $mark`.

- [ ] **Step 6: Clean stage build under the knob**

From the rakudo worktree root, as a background job:

```
NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 NQP_CODE_STRICT=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/3420e344/tmp/build-task2.log --show='> Task :stage' --show='BUILD' --show='rror' -- ./nqp/gradlew -p nqp clean buildJvm
```

Expected: `=== EXIT=0 verdict=ok elapsed=<about 300>s ===`. Then every stage2 jar is an artifact: for `nqp/build/jvm/share/lib/*.jar`, `unzip -l <jar> | grep -c unit.meta` is 1 and `unzip -l <jar> | grep -c '\.class'` is 0 (12 jars; write the loop as plain separate commands or a Raku one-liner, the worktree guard refuses shell loops over computed names). If the build fails inside a stage, read the log's first `rror` context: a die from Step 1's knob check means the gradle stage task lacks one of the three env vars; an "unknown tag" in a t/nqp file after the build means a splice_code site got the wrong `$at`.

- [ ] **Step 7: Smoke the record road**

From the rakudo worktree root:

```
NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 NQP_CODE_WHY=1 ./nqp/nqp-j-gradle -e 'say(6*7)' 2>&1 | grep -E '^42$|^unit record '
```
Expected: one `unit record <sha1> (...)` line and `42`.

```
NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'say(nqp::getcomp("nqp").eval("my $y := 5; $y * 3"))'
```
Expected: `15`.

```
NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'say(1)' 2>&1 | head -2
```
Expected: the die from Step 1 naming `NQP_CODE_RUN=1` (the knob check fires once, before any block).

```
RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle nqp/t/nqp/123-unit-artifact.t
```
Expected: `1..8`, eight `ok`.

- [ ] **Step 8: Commit (nqp tree)**

```
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git add src/vm/jvm/QAST/Compiler.nqp src/vm/jvm/HLL/Backend.nqp src/vm/jvm/QAST/TruffleEncoder.nqp src/vm/jvm/QAST/JASTNodes.nqp && git commit -m "unit artifact: under NQP_UNIT every unit takes the road -- runtime compiles become records in memory

Compiler.nqp decides the road from the knob alone: a jar-bound unit with
an output is written (milestone 1), anything else is built in memory by
jvm-build-unit and loaded as a ProgramUnit (milestone 2); every unit-road
program is index-framed (no string constant, no size gate); the wrapper
block exists whenever static lexical values need their rows; the knob
checks NQP_CODE_RUN/NQP_CODE_PRECOMP once and refuses --target=classfile.
HLL::Backend::JVM routes accordingly. The encoder's four splice-and-shift
sites are one splice_code helper (milestone-1 ledger item a).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011k7PcwZi8KjqW3yLn4GNvi"
```

---

