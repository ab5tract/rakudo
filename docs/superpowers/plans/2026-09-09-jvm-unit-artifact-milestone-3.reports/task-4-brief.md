### Task 4: The deletions (compiler-side class road; the knob; the stale recipes)

**Files:**
- Modify: `nqp/src/vm/jvm/QAST/Compiler.nqp` (`:4102-4126`, `:4158-4168`, `:4253`, `:4334-4352`, `:4727-4766`, `:4770-4774`)
- Modify: `nqp/src/vm/jvm/QAST/TruffleEncoder.nqp` (`:683`, `:695-698`, `:818-837`, `:882-885`)
- Modify: `nqp/src/vm/jvm/HLL/Backend.nqp:79-106`
- Modify: `nqp/src/vm/jvm/QAST/JASTNodes.nqp` (`:9`, `:21-22`, `:42-43`, `:60-66`, `:77-79`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/jast2bc/JastClass.kt` (`:13`, `:30-31`, `:54-59`, `:82-83`, `:103`, `:115-116`, `:127`, `:139-140`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitWriter.kt:22-36`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CodeEngine.kt:86-106`
- Modify: rakudo `tools/templates/jvm/Makefile.in:12-18`, `tools/build/jvm-build.sh:83-114`, `tools/build/jvm-build-resume.sh:149-247`
- Test: `nqp/t/nqp` (the sweep), t/01-sanity, the 14 precomp files, t/03-jvm

**Interfaces:**
- Consumes: Task 2's defaults (there is no `NQP_UNIT` after this task; `$*UNIT_ROAD` is gone), `UnitWriter.record` reading `jc.programs`, `jc.callsites`, `jc.blockvalues`, `jc.nestedClasses`, `jc.className`, `jc.hll`, the `cr_*` method fields (unchanged).
- Produces: a compiler that emits only unit records; `CodeEngines.codeRunIdx` as the sole public entry for stage0's bodies; `CodeEngines.codeRunUnit` unchanged.

What STAYS, by rule (deviation 1): everything the stage0 jars execute on this runtime (`Ops.compilejast`, `compilejasttofile`, `JASTCompiler.*`, `AutosplitMethodWriter`, `loadcompunit`'s define branch, `inMemoryUnitBytes`, nested `.class` embedding, `MemoryClassLoader`, `loadJar(ByteBuffer)`, `EvalResult.jc`, the sidecar reader `CompilationUnit.engineProgram/loadEnginePrograms`, `JarFileClassLoader`, `ByteClassLoader.defineClass`), the Compiler.nqp op mappings `compilejast`/`compilejasttofile` (`:3442-3443`; ops the runtime still owns), the JAST method carrier and every `cr_*` setter (UnitWriter's input), `nested_classes`/`jvm-class-of-cuid` (both roads' nested scan), the `--target=classfile` refusal.

- [ ] **Step 1: Compiler.nqp: the road is the only road**

`:4102-4126`: delete the `$*UNIT_ROAD`/`$*UNIT_FALLBACKS` declarations and the knob comment; keep the encoder-off die and the classfile refusal unconditionally:

```
        # The unit road (rakudo docs/superpowers/specs/2026-09-09-jvm-
        # unit-artifact-design.md) is the only road since milestone 3: every
        # unit is a record -- programs + block table (+ serialized context
        # for a comp-mode unit), no class file. A jar-bound unit with an
        # output file is written as a zip; any other unit is built in memory
        # and loaded as a ProgramUnit. A block that cannot encode is a
        # compile error at the junction below, never a fallback.
        my %env := nqp::getenvhash();
        nqp::die('unit artifact: the road needs the encoder on; NQP_CODE_RUN=0 or NQP_CODE_PRECOMP=0 is set, every block must encode')
            if (nqp::existskey(%env, 'NQP_CODE_RUN') && nqp::atkey(%env, 'NQP_CODE_RUN') eq '0')
            || (nqp::existskey(%env, 'NQP_CODE_PRECOMP') && nqp::atkey(%env, 'NQP_CODE_PRECOMP') eq '0');
        nqp::die('unit artifact: --target=classfile has no artifact form; use --target=jar')
            if %*COMPILING<%?OPTIONS><target> eq 'classfile';
```

`:4158-4163`: delete the `if %*BLOCK_LEX_VALUES && !$*UNIT_ROAD { ... setup_blv ... }` block and its comment. `:4167-4168`: the wrapper condition becomes `if $*COMP_MODE || @pre_des || @post_des || need_set_code_object($cu) || %*BLOCK_LEX_VALUES {`. `:4253`: `if %*BLOCK_LEX_VALUES {`. `:4334-4352`: the `if $*UNIT_ROAD { ... } elsif nqp::elems(@*ENGINE_PROGRAMS) { ... codeprograms ... }` becomes the unconditional record hand-off, without `fallbacks` and `unit_road`:

```
        # The programs go to the writer as a boxed list (@*ENGINE_PROGRAMS
        # is a native str list; the writer reads through at_pos_boxed),
        # byte-framed by it, last, so every block -- the deserialize and
        # load methods included -- has had its say.
        my @progs;
        for @*ENGINE_PROGRAMS -> str $p { nqp::push(@progs, $p) }
        $*JCLASS.programs(@progs);
        $*JCLASS.callsites($*CODEREFS.callsite_data);
        nqp::say('code unit ' ~ $*JCLASS.name ~ ' -> unit road')
            if nqp::existskey(nqp::getenvhash(), 'NQP_CODE_WHY');
```

`:4727-4766` (the block junction): delete the `$as_index` computation and comment, the `:sidecar`/`:unit_road` arguments, and the string-constant `else` arm; every encoded block records its program by index:

```
                $engine_prog := QAST::TruffleEncoder.encode_block($node, $block, self,
                    :comp_mode($*COMP_MODE));
                if $engine_prog ne '' {
                    $engine_body := 1;
                    my int $pidx := nqp::elems(@*ENGINE_PROGRAMS);
                    nqp::push_s(@*ENGINE_PROGRAMS, $engine_prog);
                    $*JMETH.cr_program($pidx);
                    my $il := JAST::InstructionList.new();
                    $il.append(JAST::PushIndex.new( :value($pidx) ));
                    $il.append($ALOAD_0);
                    $il.append($ALOAD_1);
                    $il.append(JAST::Instruction.new( :op('aload'), 'cf' ));
                    $il.append(JAST::Instruction.new( :op('aload'), 'csd' ));
                    $il.append(JAST::Instruction.new( :op('aload'), '__args' ));
                    $il.append(JAST::Instruction.new( :op('invokestatic'),
                        'Lorg/raku/nqp/runtime/CodeEngines;',
                        'codeRunIdx', 'Void', 'Integer',
                        $TYPE_CU, $TYPE_TC, $TYPE_CF, $TYPE_CSD, "[$TYPE_OBJ" ));
                    $body := result($il, $RT_VOID);
                    $*STACK.obtain(NQPMu, $body);
                }
                else {
                    nqp::die('unit artifact: block '
                        ~ ($node.name eq '' ?? '<anon ' ~ $node.cuid ~ '>' !! $node.name)
                        ~ ' (cuid ' ~ $node.cuid ~ ') has no engine program and would need bytecode;'
                        ~ ' run with NQP_CODE_BAIL=1 or NQP_CODE_WHY=1 for the reason');
                }
```

(The JAST instruction list is dead weight the writer never reads, kept until milestone 4 deletes JAST; deleting the surrounding stub emission -- arity check, locals, postlude, save sites, `getCallSites`, `entryQbid` methods -- is milestone 4's JAST deletion, not this task.) Also update the comment at `:4368-4370` ("as class entries on the class road" -> "under nested/ in the parent's artifact").

- [ ] **Step 2: TruffleEncoder.nqp: no gates, no roads**

`:683`: `method encode_block($node, $block, $comp, :$comp_mode) {`. `:695-698`: delete the `raw` refusal and its comment (raw wrappers always encode). `:818-837`: delete the size-estimate comment, the `$est` computation and the `if $est > 60000 && !$sidecar { ... }` gate. `:882-885`: delete the post-commit `nqp::die(... grew past the size gate ...) if ... !$sidecar` invariant. Grep the file for `sidecar` and `unit_road` afterwards: zero hits.

- [ ] **Step 3: Backend.nqp: one junction**

`:79-106` of `nqp/src/vm/jvm/HLL/Backend.nqp` becomes:

```
        # The unit road: a jar-bound unit with an output file is written as
        # a zip; every other unit -- a script, an EVAL, a BEGIN-time unit,
        # a --target=jar with no --output -- is built in memory as a
        # record, which the jvm stage (nqp::loadcompunit) turns into a
        # ProgramUnit. No class file either way; Compiler.nqp refuses
        # --target=classfile.
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
```

- [ ] **Step 4: JAST::Class loses `codeprograms`, `fallbacks`, `unit_road`; JastClass.kt stops reading them; UnitWriter stops checking them**

`nqp/src/vm/jvm/QAST/JASTNodes.nqp`: delete `has str $!codeprograms;` (:9), `$!fallbacks` and `$!unit_road` (:21-22), their BUILD inits (:42-43), the `codeprograms` accessor and comment (:60-64), the `fallbacks` and `unit_road` accessors and comments (:77-79). `nqp/src/vm/jvm/runtime/org/raku/nqp/jast2bc/JastClass.kt`: delete the `codePrograms` field and its guarded read and hint (:13, :54-59, :103, :127), and the `fallbacks`/`unitRoad` fields, reads and hints (:30-31, :82-83, :115-116, :139-140); `JASTCompiler.kt:238` (`c.codePrograms = jastClass.codePrograms?...`) becomes `c.codePrograms = null` with the comment "no compiler emits a sidecar since milestone 3; the reader stays for stage0's jars". `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitWriter.kt:33-36`: delete the two `throw`s (`!jc.unitRoad`, `jc.fallbacks != 0`) and the doc sentence about fallbacks (:22-25); the writer's refusals are the per-block ones (a block without a program, an unassigned index, missing call-site data).

- [ ] **Step 5: `CodeEngines.codeRun(String)` becomes the index entry's private half**

`nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CodeEngine.kt:86-106`: mark `codeRun(String, ...)` `private` (it is `@JvmStatic`; keep the annotation) with the comment "Reached only through codeRunIdx: no compiler emits a string-constant program since milestone 3, and no stage0 body ever called this directly (javap over stage0's jars, 2026-09-09)". If Kotlin complains that `@JvmStatic` on a private member of an object is disallowed in this Kotlin version, drop `@JvmStatic` from it.

- [ ] **Step 6: The Rakudo build's exports and the stale recipes**

`tools/templates/jvm/Makefile.in:12-18`: delete the `export NQP_CODE_RUN = 1` / `export NQP_CODE_PRECOMP = 1` lines and their comment paragraph; leave `export RAKUDO_RAKUAST = 1` (line 10) and add one comment line: `# The engine build is the build: the encoder and the unit road are on by default (nqp, 2026-09-09).` `tools/build/jvm-build.sh` and `tools/build/jvm-build-resume.sh`: every recipe of the form `java ... -cp '<cp>' nqp --target=jar --javaclass=perl6 ...` becomes `java ... -cp '<cp>' org.raku.nqp.runtime.unit.UnitMain <the nqp.jar path already in that recipe's classpath> --target=jar --javaclass=perl6 ...` (lines 83, 85, 94, 103, 114 and 149, 160, 187, 214, 247 respectively; the `rakudo-j-build` lines need nothing, the template changed in Task 2). Also update CLAUDE.md's mention if any of those lines changed meaning (they did not: the scripts remain "the same commands written down").

- [ ] **Step 7: Runtime jars compile**

```
./nqp/gradlew -p nqp :nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars
```
Expected: BUILD SUCCESSFUL (the Kotlin deletions compile; the unit tests in `nqp-runtime/src/test` still pass -- `UnitFormatTest`, `ProgramUnitTest` do not touch the deleted fields).

- [ ] **Step 8: nqp clean build, then t/nqp**

```
RAKUDO_RAKUAST=1 NQP_CODE_STRICT=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t4-build.log --show='> Task :stage' --show='code-bail' --show='BUILD' --show='rror' -- ./nqp/gradlew -p nqp clean buildJvm
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=nqp/t/nqp -t=nqp/t/qast --jobs=3 --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t4-sweep.log -- nqp/nqp-j-gradle
```
Expected: EXIT=0, 11 jars `unit.meta`-only, 118/118 + 2/2. Note: stage1 is still built by stage0's class-road compiler, so `nqp/build/jvm/stage1/*.jar` DO contain classes and sidecars; only stage2 and `share/lib` are checked.

- [ ] **Step 9: Rakudo make, sanity, precomp, interop**

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t4-configure.log -- perl Configure.pl --backends=jvm --gen-nqp
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t4-make.log --show='Compiling' --show='Generating' --show='rror' --stall=1500 -- make
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=t/01-sanity --jobs=2 --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t4-sanity.log -- ./rakudo-j
```
then the 14 precomp files and t/03-jvm + t/10-qast exactly as Task 2 Step 11 (logs `t4-precomp.log`, `t4-jvm.log`). Expected: as in Task 2. Confirm the generated `Makefile` no longer exports `NQP_CODE_RUN` (`grep -c NQP_CODE_RUN Makefile` = 0).

- [ ] **Step 10: Commit both trees**

nqp:
```
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git add src/vm/jvm/QAST/Compiler.nqp src/vm/jvm/QAST/TruffleEncoder.nqp src/vm/jvm/HLL/Backend.nqp src/vm/jvm/QAST/JASTNodes.nqp src/vm/jvm/runtime/org/raku/nqp/jast2bc/JastClass.kt src/vm/jvm/runtime/org/raku/nqp/jast2bc/JASTCompiler.kt src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitWriter.kt src/vm/jvm/runtime/org/raku/nqp/runtime/CodeEngine.kt && git commit -m "unit artifact: the compiler emits only unit records -- the string-constant road, its size gates, the sidecar writer, \$*UNIT_FALLBACKS, the NQP_UNIT knob and the raw-block refusal are gone" -m "The runtime keeps the class road's writer and loaders for stage0 (a class-road compiler that runs on this runtime until milestone 4 regenerates it) and for the interop adaptors; codeRun(String) is codeRunIdx's private half." -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01FyzDsYsbo1z8DspSvLpx5B"
```
rakudo:
```
git add tools/templates/jvm/Makefile.in tools/build/jvm-build.sh tools/build/jvm-build-resume.sh && git commit -m "Build: the encoder knobs are defaults now; the written-down build recipes enter nqp through UnitMain" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01FyzDsYsbo1z8DspSvLpx5B"
```

---

