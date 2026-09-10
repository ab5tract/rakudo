# JVM Unit Artifact, Milestone 3: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rakudo builds and runs as unit artifacts: the unit road is the default for every compile, every jar Rakudo produces is `unit.meta`-only, the runners enter through `UnitMain`, the suites in t/ (not t/spec) run through the eval server on artifact units, and the class road's compiler-side writer is deleted.

**Architecture:** Three encoder refusals go first (exit handlers, `withy general`, `labeled control` plus its `for :label` twin), so every Rakudo and t/nqp block encodes. Then the knobs flip on the nqp side (`NQP_UNIT`, `NQP_CODE_RUN`, `NQP_CODE_PRECOMP` default on, `=0` opts out), Rakudo's runner generator and build runner enter through `org.raku.nqp.runtime.unit.UnitMain <rakudo.jar>`, and the booked minors land in the same build (record-road backtrace filename, `--target=jar` dumper death). A t/ sweep through the eval server gates the flip. The closing task deletes what the new compiler sources still carry of the class road (string-constant road, size gates, sidecar writer, `$*UNIT_FALLBACKS`, the knob, the `raw` refusal); the runtime's class-road writer and loaders stay for stage0 until milestone 4. A second t/ sweep gates the deletions.

**Tech Stack:** NQP (Compiler.nqp, TruffleEncoder.nqp, HLL/Backend.nqp, HLL/Compiler.nqp, JASTNodes.nqp), Kotlin 2.4 (nqp-runtime, nqp-truffle dispatcher), Java (NqpProgramBuilder, NqpWire: one additive wire op), Perl 5 (create-jvm-runner.pl), gradle, Raku tooling (watched-run.raku, evalserver-sweep.raku).

**Spec:** `docs/superpowers/specs/2026-09-09-jvm-unit-artifact-design.md` (rakudo worktree), section "Milestones" item 3, section 2 ("A runtime compile constructs the same ProgramUnit ... no class definition"), section 4 (runners, eval server, identity), section 6 (gates). Milestone 1 and 2 plans and ledgers sit beside this file; this plan starts where milestone 2's ledger stopped (`2026-09-09-jvm-unit-artifact-milestone-2.ledger.md`, FINAL REVIEW deferred minors).

## Global Constraints

- Two git trees: rakudo worktree root `/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records` (docs, Rakudo runners, gate) and the nested `nqp/` tree (compiler and runtime). Every nqp path below is under `nqp/`; nqp git commands run as `cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git ...` in their own shell call (the worktree guard refuses `git -C nqp`, `/usr/bin/time`, heredocs and shell loops over computed values). Label hashes by tree. Start of this plan: rakudo `5ae25a8d3c` (branch `worktree-jesp-direct-lazy-records`), nqp `da1f5088a` (branch `jesp-direct-lazy-records`).
- Kotlin, never Java, for new code (user rule). The one Java edit here (`NqpProgramBuilder.java`, `NqpWire.java`: the FORLOOPL wire op) extends an existing Java file that the Truffle DSL processor owns; it is the stated deal-breaker case.
- Every diagnostic print is env-gated (`System.getenv(...)` / `nqp::getenvhash()`); never a bare print.
- Wire-program changes must be additive (stage0 ships old programs): this plan adds ONE wire op, `FORLOOPL = 35`, and changes no existing layout.
- Framing is by byte, never by grapheme. The unit meta format version stays 1.
- Runtime-jar-only changes rebuild with `./nqp/gradlew -p nqp :nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars` (~10-20 s) from the rakudo worktree root; a Compiler.nqp / TruffleEncoder.nqp / Backend.nqp / HLL change needs `./nqp/gradlew -p nqp clean buildJvm` (~5 min) through `raku tools/build/watched-run.raku` as a plain background job (`run_in_background`, never `setsid`/`nohup`) with a log under `/home/longwalker/.claude/jobs/288cfddd/tmp/`. Restart eval servers after any runtime jar rebuild.
- Until Task 2 flips the defaults, every build and run carries `RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1`, and the unit road needs `NQP_UNIT=1`. From Task 2 on, only `RAKUDO_RAKUAST=1` is needed (the Makefile exports it; the sweep sets it itself). Task 2's nqp build and Rakudo make run WITHOUT the three knobs in the environment, on purpose: that is the test of the defaults.
- `java` is Oracle GraalVM 25.2.4.
- One compile per change (forward only): no A/B builds, no knob-off comparison make (user, 2026-09-09). Baseline at the start of this plan (milestone 2 gate, 2026-09-09): `NQP_UNIT=1 clean buildJvm` 296 s; t/nqp on the record road 115/118 in 381 s at 3 jobs (059, 067, 084 refuse; 019, 063 pass from the nqp dir); Rakudo `make` 1274 s; `t/01-sanity` 25/25 in 214 s at 2 jobs.
- Runs longer than 30 s go through `raku tools/build/watched-run.raku` (`--log=`, `--show=` literals, `--max=SECONDS` for a hard ceiling, `-t=DIR --jobs=N` for test sweeps); look for its `=== EXIT=<n> verdict=<v> elapsed=<s>s ===` line. Tooling is Raku, never Python or shell scripts. Progress is reported at least every 90 s during a build or sweep (Monitor on the log, cadence >= 90 s).
- Debug knobs for triage: `NQP_CODE_WHY=1` (per-block verdicts and `unit record`/`unit artifact` markers; floods stdout, never mix with an output check), `NQP_CODE_BAIL=1` (the refusal reason), `NQP_UNWIND_TRACE=1` (loop unwind categories).
- Commit trailer on every commit:
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01FyzDsYsbo1z8DspSvLpx5B`

## User decisions (2026-09-09, brainstorm)

1. The six-part shape stands: encoder shapes, the flip with the booked minors, a t/ sweep, the deletions, a second t/ sweep, docs/ledger/push.
2. **No t/spec in this milestone** ("holding off on t/spec until it doesn't take hours to run t/"). The gate is the make-driven t/ directories plus t/03-jvm, and t/nqp, through the eval server. Each t/ sweep runs under a **two-hour ceiling** (`--max=7200`).
3. No knob-off `make` before the deletions: forward only. The flip build's timings are the next baseline.
4. Anonymous-block naming for backtraces (RakuAST, `#?if jvm`) is deferred to a later milestone; recorded below under known gaps.
5. RakuAST edits under `#?if jvm` are allowed; where RakuAST keeps a behaviour moar-only, prefer flipping the guard to `#?if !js`. (No such edit turned out to be needed here: see deviation 3.)

## Deviations from the spec, stated up front

1. **The runtime's class-road writer stays until milestone 4.** The spec's milestone-2 line (as amended) lists "`ByteClassLoader`'s define road" and "the nested `.class` embedding" among this milestone's deletions. They cannot go: nqp's stage0 compiler is a class-road compiler baked into `nqp/src/vm/jvm/stage0/*.jar`, it runs on THIS runtime to build stage1 as class files with program sidecars, and it reaches `Ops.compilejast`/`compilejasttofile`, `JASTCompiler`, `AutosplitMethodWriter`, `loadcompunit`'s define branch, `inMemoryUnitBytes` and the nested `.class` embedding for any BEGIN-time compile during that build. `BootJavaInterop` and `RakudoJavaInterop` also define adaptor classes through `ByteClassLoader.defineClass` (spec item 9). So this milestone deletes what the NEW compiler sources (stage1 and later, and Rakudo) still carry of the class road, plus the two runtime pieces provably unreachable from stage0 (`UnitWriter`'s fallbacks/unit-road refusals; `CodeEngines.codeRun(String)` as a public entry, which no stage0 bytecode calls: `javap` over stage0's jars shows only `codeRunIdx`). The runtime-side class road (jast2bc, `MemoryClassLoader`, `loadJar(ByteBuffer)`, `EvalResult.jc`, the define branch) is milestone 4's deletion, with stage0's regeneration, exactly where the spec's milestone-4 line already puts "the class road, jast2bc, JAST, the class loaders".
2. **t/spec does not run** (user decision 2). The spec's milestone-3 line says "the suites (t/nqp, t/01-sanity, t/spec) run through it here"; t/spec waits for a faster t/.
3. **No RakuAST change for `ModuleLoader.class`.** `src/Raku/ast/compunit.rakumod:787-791` emits `loadbytecode('ModuleLoader.class')` on the jvm; `LibraryLoader.load` (`nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/LibraryLoader.java:38-53`) special-cases exactly that name, probes each classpath entry for `ModuleLoader.class` then `ModuleLoader.jar`, and sniffs the file for `unit.meta`. nqp's `ModuleLoader.jar` has been an artifact since milestone 1 and Rakudo already runs on it. Verified by reading; nothing to change.
4. **`--javaclass=perl6` stays.** `tools/templates/jvm/Makefile.in:90` passes it to `rakudo.jar` and the three BOOTSTRAP jars. On the unit road it only names the unit (`unit.meta` unit id = `perl6` for all four); nothing keys on the unit id (sharing and dedupe are by path: `UnitLoader.kt:28-35`, `LibraryLoader.java:34`; `invokeMain` uses it as an error prefix). Dropping it would change nothing but the id string.

## Booked from milestone 2's ledger (all land here)

- Record-road backtrace filename (FINAL REVIEW: "mandatory first item of milestone 3 after the flip probe"): Task 2 Step 5. Root cause found in advance: the `<mainline>` block never had a block-level file on EITHER road (its `QAST::Block` is built from the unmatched `comp_unit` cursor, so both `cr_file` branches in Compiler.nqp are skipped); the class road backfilled it from the class-level `SourceFile` attribute through the Java stack trace, which a `ProgramUnit` never correlates with.
- `--target=jar` without `--output` dies in HLL::Compiler's dumper on either road (`lateinit st`: the `EvalResult` carrier has no STable and `nqp::can` deconts it): Task 2 Step 6.
- `$*UNIT_FALLBACKS` constant-0 scaffold: Task 4.
- t/qast under the defaults: Task 2 Step 11 (`nqp/t/qast`, 2 files).
- `record()` maps hll `""` to `"nqp"` where the class road kept `""` (minor 4): observed by the t/qast run above; no change planned unless it fails.
- Double `nqp::getenvhash()` at the road decision (minor 6): folded into Task 2 Step 2 (the road decision loses its env reads).
- Marker prints in `loadcompunit`/`UnitWriter` go to `System.err`, not `tc.gc.err` (minor 5): left as is; t/nqp/124 reads them from the child's stderr.

## Known gaps recorded, not worked

- **Torn-frame LEAVE:** on the JVM a frame torn past by an exception never runs its exit handler, on either road (`CallFrame.countLeft`, `ExceptionHandling.giveBackTornFrames`); Raku runs LEAVE on exceptional exit. Pre-existing, shared, spectest-visible (S04-phasers). Ledger note.
- **Interop adaptor units** (`RakudoJavaInterop.kt:930-937`, `BootJavaInterop.kt:204-209`) still subclass a generated `CompilationUnit` through `ByteClassLoader`; t/03-jvm/01-interop.t is their coverage. Spec item 9.
- **Anonymous block names in backtraces** (`<anon>` -> `anon_N`): deferred (user decision 4).
- `t/12-rakuast` (46 files) is not in `tools/templates/common_test_dirs`, so it is not part of the make-driven gate; not swept here.

## File structure

| file | change | task |
|---|---|---|
| `nqp/src/vm/jvm/QAST/TruffleEncoder.nqp` | exit-handler refusal removed + frame-forcing; `withy general` branch; `labeled control` desugar; `encode_for` label support via `W_FORLOOPL`; (Task 4) `:sidecar`/`:unit_road` params, size gates, `raw` refusal removed; `NQP_CODE_RUN`/`NQP_CODE_PRECOMP` default on | 1, 2, 4 |
| `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt` | `frameFreeEntryOk` refuses a block with an exit handler | 1 |
| `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpWire.java` | `FORLOOPL = 35` documented | 1 |
| `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java` | `FORLOOPL` case; `emitForBody`/`emitForPass` take a label local | 1 |
| `nqp/src/vm/jvm/QAST/Compiler.nqp` | road decision default; env check; mainline `cr_file` from `$?FILES`; (Task 4) string-constant arm, `$as_index`, sidecar join, `$*UNIT_FALLBACKS`, `$*UNIT_ROAD` folded | 2, 4 |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/ExceptionHandling.kt` | `mappedLine` falls back to the block's start line | 2 |
| `nqp/src/HLL/Compiler.nqp` | `dumper` refuses a compilation-unit carrier with a message | 2 |
| `nqp/t/nqp/124-unit-record.t` | knob assertion for the new default (`NQP_CODE_RUN=0`) | 2 |
| `nqp/src/vm/jvm/HLL/Backend.nqp` | (Task 4) the class-road arms of `classfile` go | 4 |
| `nqp/src/vm/jvm/QAST/JASTNodes.nqp` | (Task 4) `codeprograms`, `fallbacks`, `unit_road` attributes go | 4 |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/jast2bc/JastClass.kt` | (Task 4) the three matching reads go | 4 |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitWriter.kt` | (Task 4) fallbacks/unit-road refusals go | 4 |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CodeEngine.kt` | (Task 4) `codeRun(String)` becomes private, reached only through `codeRunIdx` | 4 |
| rakudo `tools/build/create-jvm-runner.pl` | six runner lines enter through `UnitMain <app jar>` | 2 |
| rakudo `tools/templates/jvm/rakudo-j-build.in` | the build runner enters through `UnitMain rakudo.jar` | 2 |
| rakudo `tools/templates/jvm/Makefile.in` | (Task 4) the `NQP_CODE_RUN`/`NQP_CODE_PRECOMP` exports and their comment go | 4 |
| rakudo `tools/build/jvm-build.sh`, `tools/build/jvm-build-resume.sh` | (Task 4) stale `nqp` main-class recipes rewritten to `UnitMain` | 4 |
| rakudo `docs/jvm-eval-server.md` | knob sentence updated | 2 |
| rakudo `docs/jvm-truffle-only-plan.md`, the spec, this plan's `.ledger.md`, `.reports/`, memory | Task 6 |

---

### Task 1: The three encoder shapes (exit handlers, `withy general`, `labeled control` + `for :label`)

**Files:**
- Modify: `nqp/src/vm/jvm/QAST/TruffleEncoder.nqp:694` (refusal), `:719` (`%e` init), `:1783-1790` (`encode_for` head), `:1836-1860` (`encode_for` handled arm), `:2207-2209` (`control`), `:2560` (`withy general`), `:332` (wire constants)
- Modify: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt:961`
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpWire.java:142-149` (doc + constant)
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java:330-362` (FORLOOP case), `:944-990` (`emitForBody`, `emitForPass`)
- Test: `nqp/t/nqp/059-nqpop.t`, `nqp/t/nqp/067-container.t`, `nqp/t/nqp/084-loop-labels.t` (existing; they are the coverage), plus the probes below

**Interfaces:**
- Consumes: `%e<frame_op>` (TruffleEncoder.nqp:793, the frame decision), `emit_defined_test(%e, int $tmp)` (:2366), `new_elocal(%e, type)`, `encode_child($node, %e, type)`, `encode_node($node, %e, type)`, `&*REGISTER_UNWIND_HANDLER`, `QAST::Node.unique(str)`, `$EX_CAT_NEXT/REDO/LAST/LABELED` (:339-348), `epush`, `epool`; runtime: `NqpProgramBuilder.emitForBody(redoL, preAt, bodyAt, nrId, lastId)`, `emitLoophBody(..., labelLocal)` (the label pattern to copy), `b.beginLoopLastUnwind`/`beginLoopBodyUnwind` taking `where` then the exception.
- Produces: wire op `FORLOOPL = 35` with layout `FORLOOPL condType lastId nrId outerIdx labelLocal labelExpr cond pre body`; the encoder emits it for a labeled `nqp::for` and nothing else changes on the wire.

- [ ] **Step 1: Exit handlers encode, frame-forced**

In `nqp/src/vm/jvm/QAST/TruffleEncoder.nqp` delete line 694:

```
        if $node.has_exit_handler { trace('no: exit handler'); return '' }
```

and in the `%e` hash literal (line 719) change `'frame_op', 0,` to read the flag:

```
            'frame_op', ($node.has_exit_handler ?? 1 !! 0), 'uses_hll', 0, 'hidx', 0,
```

with this comment on the line above it:

```
            # An exit-handler block (Raku LEAVE/KEEP/UNDO/POST, Lock.protect)
            # runs its handler from CallFrame.leave(): it needs a frame, since
            # a frame-free entry builds none and would skip the handler
            # silently. The value is already on the caller's registers when
            # leave() runs (StoreRet wraps the program; NqpDispatch and
            # ProgramEntry leave after the call), as the stub's postlude did.
```

- [ ] **Step 2: The dispatcher never enters such a block frame-free**

In `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt`, `frameFreeEntryOk` (line 961), add as its first statement:

```kotlin
        /* A block with an exit handler must leave through CallFrame.leave();
         * the wire says framed already, this keeps it so whatever road asks. */
        if (NqpRaw.staticInfo(cr).hasExitHandler) return false
```

- [ ] **Step 3: `withy general`**

In `TruffleEncoder.nqp` replace line 2560 (`cbail('withy general') if $withy;`) with:

```
        if $withy {
            # with/without whose then-arm takes no condition: the condition
            # into an obj local, the same `defined` dispatch the cond-passing
            # branches make (Compiler.nqp: coerce to obj, findmethod
            # 'defined', lang-call, istrue), then the plain IFS/IFV layout
            # with an obj condition. Value context with two children never
            # reaches here (the branch above owns it).
            my int $rt := $void ?? $T_VOID !! ($want == $T_ANY ?? $T_OBJ !! $want);
            epush(%e, $W_STMTS); epush(%e, 2);
            my int $tmp := new_elocal(%e, $T_OBJ);
            epush(%e, $W_LOCBIND); epush(%e, $T_OBJ); epush(%e, $tmp);
            self.encode_child($op[0], %e, $T_OBJ);
            epush(%e, $void ?? $W_IFS !! $W_IFV);
            epush(%e, $T_OBJ); epush(%e, $negate); epush(%e, $n == 3 ?? 1 !! 0);
            self.emit_defined_test(%e, $tmp);
            self.encode_child($op[1], %e, $rt);
            self.encode_child($op[2], %e, $rt) if $n == 3;
            return $void ?? $T_OBJ !! $rt;
        }
```

Also delete the dead `my int $mark := nqp::elems(%e<code>);` at line 2568.

- [ ] **Step 4: `labeled control`**

In `TruffleEncoder.nqp` replace lines 2207-2209:

```
            for @($op) {
                cbail('labeled control') if $_.named eq 'label';
            }
```

with the desugar (Compiler.nqp:2110-2144: newexception, setpayload label, setextype category|LABELED, _throw_c; every piece is an op the encoder already reaches -- newexception/setpayload/setextype through the classlib registry, throw through wire 181 which answers `result_o(cf)` like control does, and every OPCALL/CLASSLIB site is a suspension point, so the class road's savesite needs no twin):

```
            my $label;
            for @($op) { $label := $_ if $_.named eq 'label' }
            if $label {
                my int $lcat := $kind eq 'next' ?? $EX_CAT_NEXT +| $EX_CAT_LABELED
                             !! $kind eq 'redo' ?? $EX_CAT_REDO +| $EX_CAT_LABELED
                             !! $kind eq 'last' ?? $EX_CAT_LAST +| $EX_CAT_LABELED
                             !! 0;
                cbail('labeled control ' ~ $kind) unless $lcat;
                my str $tmp := QAST::Node.unique('ctrl_ex');
                my sub lv() { QAST::Var.new( :name($tmp), :scope('local') ) }
                return self.encode_node(QAST::Stmts.new(
                    QAST::Op.new( :op('bind'),
                        QAST::Var.new( :name($tmp), :scope('local'), :decl('var') ),
                        QAST::Op.new( :op('newexception') ) ),
                    QAST::Op.new( :op('setpayload'), lv(), $label ),
                    QAST::Op.new( :op('setextype'), lv(), QAST::IVal.new( :value($lcat) ) ),
                    QAST::Op.new( :op('throw'), lv() )), %e, $want);
            }
```

(`$label` is the `QAST::WVal` of the Label, reused unmutated as the fresh-tree contract at :2292-2300 allows; Compiler.nqp passes it straight to `setpayload` too.)

- [ ] **Step 5: The `FORLOOPL` wire op (runtime side)**

`nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpWire.java`, after the `FORLOOP` constant (line 149):

```java
    /** 35 FORLOOPL condType lastId nrId outerIdx labelLocal labelExpr cond pre body:
     *  FORLOOP with a label (nqp::for :label). labelExpr's value is bound into
     *  block local labelLocal at loop entry and read by both unwind arms as the
     *  `where` for _is_same_label, exactly as LOOPH's hasLabel form. Additive. */
    public static final int FORLOOPL = 35;
```

`nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java`: give `emitForBody` and `emitForPass` a trailing `BytecodeLocal labelLocal` parameter; in `emitForPass` the catch arm's `b.emitLoadNull();` (the `where` before `b.emitLoadException()`) becomes

```java
            if (labelLocal != null) b.emitLoadLocal(labelLocal); else b.emitLoadNull();
```

and `emitForBody` passes `labelLocal` through on both `emitForPass` calls. The existing `FORLOOP` case passes `null`. Then add the new case right after `case NqpWire.FORLOOP`:

```java
            case NqpWire.FORLOOPL: {
                // FORLOOP with a label: the label expression is bound into a
                // block local at entry and both unwind arms read it (LOOPH's
                // hasLabel form over the for-loop's fetch/call split).
                int condType = code[at + 1];
                int lastId = code[at + 2];
                int nrId = code[at + 3];
                int outerIdx = code[at + 4];
                int labelLocalIdx = code[at + 5];
                int labelAt = at + 6;
                int condAt = walk(labelAt, false);
                int preAt = walk(condAt, false);
                int bodyAt = walk(preAt, false);
                int endAt = walk(bodyAt, false);
                if (!emit) return endAt;

                BytecodeLocal labelLocal = locals[labelLocalIdx];
                BytecodeLocal redoL = b.createLocal();
                b.beginBlock();
                b.beginStoreLocal(labelLocal);
                walk(labelAt, true);
                b.endStoreLocal();
                b.beginTryCatch();
                {   // try: the loop itself, cond and all, under lastId.
                    b.beginBlock();
                    b.emitSetCurHandler(lastId);
                    b.beginWhile();
                    walkCond(condAt, condType, 0, true);
                    emitForBody(redoL, preAt, bodyAt, nrId, lastId, labelLocal);
                    b.endWhile();
                    b.emitSetCurHandler(outerIdx);
                    b.endBlock();
                }
                {   // catch: a LAST aimed at this label (or unlabeled) ends the loop.
                    b.beginBlock();
                    b.emitSetCurHandler(outerIdx);
                    b.beginLoopLastUnwind(lastId, outerIdx);
                    b.emitLoadLocal(labelLocal);
                    b.emitLoadException();
                    b.endLoopLastUnwind();
                    b.endBlock();
                }
                b.endTryCatch();
                b.emitLoadNull();
                b.endBlock();
                return endAt;
            }
```

If the builder's `walk` has a size/skip table keyed by op (search the file for `case NqpWire.FORLOOP` in any second switch, e.g. a header-length table), add `FORLOOPL` there with the same treatment as `FORLOOP` plus one header word and one extra child.

- [ ] **Step 6: `for :label` in the encoder**

In `TruffleEncoder.nqp` add the constant next to `$W_FORLOOP` (line 332): `my int $W_FORLOOPL := 35;`. Replace the `encode_for` head (lines 1783-1790) so the comment is true and the label is captured:

```
    # that cannot see this block's locals -- and would have taken a closure
    # per iteration besides. :nohandler is the plain W_LOOP over fetch+call.
    # Value context answers the iterated list; void answers nothing. The
    # labelled form (NQP's Actions push :label onto nqp::for, t/nqp/084)
    # is W_FORLOOPL: the same shape with a label local the unwind arms read.
    method encode_for($op, %e, int $want) {
        my int $nohandler := 0;
        my $label_node;
        my @ops;
        for @($op) {
            if $_.named eq 'nohandler' { $nohandler := 1 }
            elsif $_.named eq 'label' { $label_node := $_ }
            elsif $_.named ne '' { cbail('for :' ~ $_.named) }
            else { nqp::push(@ops, $_) }
        }
        my int $has_label := nqp::defined($label_node) ?? 1 !! 0;
        cbail('labeled nohandler for') if $has_label && $nohandler;
```

and in the handled arm (the `else` at line 1836) emit the labeled form when a label is present:

```
        else {
            # The same rows a handled while registers; the runtime's handler
            # walk reads them from this block's StaticCodeInfo.
            my int $outer := %e<hidx>;
            my int $lid := &*REGISTER_UNWIND_HANDLER($outer, $EX_CAT_LAST, :ex_obj(1));
            my int $nrid := &*REGISTER_UNWIND_HANDLER($lid, $EX_CAT_NEXT +| $EX_CAT_REDO, :ex_obj(1));
            %e<frame_op> := 1;
            my int $lbl_local := $has_label ?? new_elocal(%e, $T_OBJ) !! 0;
            epush(%e, $has_label ?? $W_FORLOOPL !! $W_FORLOOP);
            my int $ct_at := nqp::elems(%e<code>);
            epush(%e, 0);
            epush(%e, $lid);
            epush(%e, $nrid);
            epush(%e, $outer);
            if $has_label {
                # The label value, bound into $lbl_local by the builder before
                # the loop's try; evaluated in the outer handler context.
                epush(%e, $lbl_local);
                %e<hidx> := $outer;
                self.encode_child($label_node, %e, $T_OBJ);
            }
            %e<hidx> := $lid;
            nqp::bindpos(%e<code>, $ct_at, self.encode_node($cond, %e, $T_ANY));
            %e<hidx> := $nrid;
            self.encode_node($pre, %e, $T_VOID);
            self.encode_node($call, %e, $T_VOID);
            %e<hidx> := $outer;
        }
```

- [ ] **Step 7: Runtime jars compile and the unit tests pass**

Run from the rakudo worktree root:

```
./nqp/gradlew -p nqp :nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars
```

Expected: BUILD SUCCESSFUL. (This proves the Kotlin/Java edits compile before the 5-minute stage build.)

- [ ] **Step 8: nqp clean build on the unit road, strict**

Background job, then Monitor its log at >= 90 s cadence:

```
NQP_UNIT=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 NQP_CODE_STRICT=1 RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t1-build.log --show='> Task :stage' --show='code-bail' --show='BUILD' --show='rror' -- ./nqp/gradlew -p nqp clean buildJvm
```

Expected: `=== EXIT=0 verdict=ok` around 300 s. Then confirm the artifacts: for each jar in `nqp/build/jvm/share/lib/` (11 of them), `unzip -l <jar> | grep -c unit.meta` is 1 and `unzip -l <jar> | grep -c '\.class'` is 0 (run as plain per-file commands, or the Raku one-liner from milestone 2's Task 4 Step 1).

- [ ] **Step 9: t/nqp on the record road: 118/118 is the target**

```
NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 raku tools/build/watched-run.raku -t=nqp/t/nqp --jobs=3 --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t1-sweep.log -- nqp/nqp-j-gradle
```

Expected: SUMMARY `116 of 118 ok` from the rakudo root (019-file-ops and 063-slurp are cwd-relative), then those two from the nqp directory (`cd .../nqp && NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp-j-gradle t/nqp/019-file-ops.t`, same for 063) all ok: **118/118**. 059, 067 and 084 must now pass; if one still refuses, run it alone with `NQP_CODE_BAIL=1` and fix the shape in this task (the three shapes above are the only known refusals in those files). For 084 also run once with `NQP_UNWIND_TRACE=1` and confirm a labeled `next` shows `loopBodyUnwind cat=4100`.

Hand probes for the withy branches the tests do not cover (all through `nqp/nqp-j-gradle -e`, same env):

```
nqp::with(nqp::null(), nqp::say("t"), nqp::say("f"))           # void, 3 children -> f
my $x := "a"; nqp::with($x, nqp::say("has"))                    # void, 2 children -> has
nqp::say(nqp::with(NQPMu, "t", "f"))                            # value, 3 children -> f
nqp::say(nqp::with(3, "t"))                                     # value, 2 children (unchanged branch) -> t
```

- [ ] **Step 10: Rakudo make and sanity on this nqp (class road, knob off) and the exit-handler probes**

CORE.c's 14 exit-handler routines (`Lock.protect`, `spurt`, `slurp-rest`, `unlock`, `compile-rakuast-comp-unit`, `run-with-updated-recursion-list` among them) become engine programs with this build even on Rakudo's class road, so Rakudo is the coverage. From the rakudo worktree root, background jobs one after the other:

```
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t1-make.log --show='Compiling' --show='Generating' --show='rror' --stall=1500 -- make
raku tools/build/watched-run.raku -t=t/01-sanity --jobs=2 --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t1-sanity.log -- ./rakudo-j
```

Expected: make EXIT=0 (baseline 1274 s), t/01-sanity 25/25. Then the probes, each `RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./rakudo-j -e '...'`, with the expected output:

```
sub f() { LEAVE say "leave"; 42 }; say f()                                  # leave / 42
sub f() { LEAVE say "leave"; return 7; 42 }; say f()                        # leave / 7
sub f($x) { KEEP say "keep"; UNDO say "undo"; $x ?? 1 !! Nil }; f(1); f(0)   # keep / undo
for ^3 { LEAVE say "L$_"; next if $_ == 1; say "body $_" }                  # body 0 L0 L1 body 2 L2
for ^3 { LEAVE say "L$_"; last if $_ == 1 }                                 # L0 L1
my $l = Lock.new; $l.protect({ say "in" }); say "out"                       # in / out
sub f(--> Int) { POST { $_ > 0 }; 5 }; say f()                              # 5
sub f() { my $x = 1 will leave { say "wl" }; 9 }; say f()                   # wl / 9
sub f() { LEAVE say "l"; g() }; sub g() { 3 }; say f()                      # l / 3
```

Run the first one also with `NQP_CODE_WHY=1 2>&1 | grep 'code frame f '` and confirm `-> framed`. Any probe that differs from the class-road answer (compare with `NQP_CODE_RUN=0`? NO: forward only; compare with MoarVM semantics as listed) is fixed in this task.

- [ ] **Step 11: Commit (nqp tree)**

```
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git add src/vm/jvm/QAST/TruffleEncoder.nqp nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpWire.java nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java && git commit -m "encoder: exit-handler blocks encode (frame-forced), with/without general form, labeled control and for :label (wire op FORLOOPL 35)" -m "The last item-7 shapes. An exit-handler block runs its handler from CallFrame.leave(), so it is framed; the dispatcher refuses a frame-free entry for one besides. withy general hoists the condition into an obj local and reuses the defined dispatch. Labeled control desugars to newexception/setpayload/setextype/throw. nqp::for with a label was refused on a wrong premise (NQP's Actions do push :label); FORLOOPL is FORLOOP with a label local both unwind arms read. t/nqp 118/118 on the record road." -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01FyzDsYsbo1z8DspSvLpx5B"
```

---

### Task 2: The flip: defaults on, runners through UnitMain, the booked minors

**Files:**
- Modify: `nqp/src/vm/jvm/QAST/TruffleEncoder.nqp:400` and `:424` (`$code_run`, `$code_precomp` defaults)
- Modify: `nqp/src/vm/jvm/QAST/Compiler.nqp:4102-4126` (road decision), after `:4689` (mainline `cr_file`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/ExceptionHandling.kt:372-385` (`mappedLine`)
- Modify: `nqp/src/HLL/Compiler.nqp:619` (`dumper`)
- Modify: `nqp/t/nqp/124-unit-record.t:87-90`
- Modify: rakudo `tools/build/create-jvm-runner.pl:233-240` (six `install` lines)
- Modify: rakudo `tools/templates/jvm/rakudo-j-build.in:3-4`
- Modify: rakudo `docs/jvm-eval-server.md:57-60`
- Test: `nqp/t/nqp/124-unit-record.t`, `nqp/t/nqp/123-unit-artifact.t` (unchanged; still pass `NQP_UNIT=1` explicitly), rakudo `t/01-sanity`, `t/02-rakudo/*-precomp.t` (14 files), `t/03-jvm`, `t/10-qast`, `nqp/t/qast`

**Interfaces:**
- Consumes: Task 1's nqp build (encoder shapes); `org.raku.nqp.runtime.unit.UnitMain <unit jar> args...` (milestone 1); `LibraryLoader.load`'s `ModuleLoader.class` special case; `HLL::Backend::JVM.is_compunit` (`nqp/src/vm/jvm/HLL/Backend.nqp:117`).
- Produces: the knob semantics every later task and every runner relies on: unset = on, `NQP_UNIT=0` / `NQP_CODE_RUN=0` / `NQP_CODE_PRECOMP=0` = off; the runner scripts `rakudo-j`, `perl6-j`, `rakudo-jdb-server`, `perl6-jdb-server`, `rakudo-debug-j`, `perl6-debug-j` ending in `org.raku.nqp.runtime.unit.UnitMain <jardir>/rakudo.jar "$@"` (debug variants `rakudo-debug.jar`); `rakudo-j-build` likewise.

- [ ] **Step 1: Encoder switches default on**

`nqp/src/vm/jvm/QAST/TruffleEncoder.nqp:400`:

```
        # ON by default since milestone 3 (2026-09-09): the engine build is
        # the build. NQP_CODE_RUN=0 turns the encoder off (class road only;
        # meaningless on the unit road, where Compiler.nqp dies on it).
        $code_run := nqp::existskey(%env, 'NQP_CODE_RUN')
            ?? (nqp::atkey(%env, 'NQP_CODE_RUN') ne '0' ?? 1 !! 0)
            !! 1;
```

and `:424`:

```
        $code_precomp  := nqp::existskey(%env, 'NQP_CODE_PRECOMP')
            ?? (nqp::atkey(%env, 'NQP_CODE_PRECOMP') ne '0' ?? 1 !! 0)
            !! 1;
```

Update the knob table comment at lines 288-294 ("NQP_CODE_RUN=1 master switch" -> "on by default; =0 off"; same for PRECOMP).

- [ ] **Step 2: The road decision defaults to the unit road**

`nqp/src/vm/jvm/QAST/Compiler.nqp:4114-4122` becomes (one `%env` read; the comment above it gains the milestone-3 sentence "The unit road is the default since milestone 3; NQP_UNIT=0 is the transitional opt-out and goes with the deletions."):

```
        my %env := nqp::getenvhash();
        my $*UNIT_ROAD := nqp::existskey(%env, 'NQP_UNIT')
            ?? (nqp::atkey(%env, 'NQP_UNIT') ne '0' ?? 1 !! 0)
            !! 1;
        my $*UNIT_FALLBACKS := 0;
        if $*UNIT_ROAD {
            # Every block must encode, so the encoder's own switches must
            # be on; said once here rather than once per block at the
            # fallback junction.
            nqp::die('unit artifact (NQP_UNIT): the road needs the encoder on; NQP_CODE_RUN=0 or NQP_CODE_PRECOMP=0 is set, every block must encode')
                if (nqp::existskey(%env, 'NQP_CODE_RUN') && nqp::atkey(%env, 'NQP_CODE_RUN') eq '0')
                || (nqp::existskey(%env, 'NQP_CODE_PRECOMP') && nqp::atkey(%env, 'NQP_CODE_PRECOMP') eq '0');
```

(the `--target=classfile` refusal at :4124-4125 stays as it is).

- [ ] **Step 3: t/nqp/124's knob assertion follows the new default**

`nqp/t/nqp/124-unit-record.t:87-90` becomes:

```
    my @knob := sh("NQP_CODE_RUN=0 NQP_CODE_PRECOMP=1 NQP_UNIT=1 $runner -e 'say(1)'");
    ok(nqp::index(@knob[2], 'needs the encoder on') >= 0,
        'the road refuses to run with the encoder switched off, once');
    ok(nqp::index(@knob[1], '1') < 0, 'and runs nothing');
```

- [ ] **Step 4: Rakudo runners enter through UnitMain**

`tools/build/create-jvm-runner.pl`: after line 52 (`$rakudo_jars` built) add

```perl
# The app unit: a unit artifact since milestone 3 (no generated main class),
# entered through the runtime's UnitMain with the unit path as first argument.
my $app  = File::Spec->catfile($jardir, $debugger ? 'rakudo-debug.jar' : 'rakudo.jar');
my $main = "org.raku.nqp.runtime.unit.UnitMain $app";
```

and change the six `install` lines (233-240) to use `$main` in place of `perl6` / `rakudo-debug`:

```perl
if ($debugger) {
    install "rakudo-debug-j", "java $jopts $main";
    install "perl6-debug-j", "java $jopts $main";
}
else {
    install "rakudo-j", "java$userjvm $jopts $main";
    install "perl6-j", "java$userjvm $jopts $main";
    install "rakudo-jdb-server", "java $jdbopts $jopts $main";
    install "perl6-jdb-server", "java $jdbopts $jopts $main";
```

(`$postamble` appends `"$@"` after `$command`, so the app path precedes the user's arguments, as `UnitMain` expects. The eval-server lines 330-331 are unchanged: `EvalServer` is a real class and takes the app as `-app <path>`.)

`tools/templates/jvm/rakudo-j-build.in`: in both the unix line 3 and the windows line 4 replace `'perl6', @ARGV` with `'org.raku.nqp.runtime.unit.UnitMain', 'rakudo.jar', @ARGV` (the build runner runs from the rakudo root where `rakudo.jar` is written).

- [ ] **Step 5: Backtrace filename on the record road**

`nqp/src/vm/jvm/QAST/Compiler.nqp`, right after the `elsif $node.node && nqp::can($node.node, 'orig')` block ends (after line 4689, before `$*CODEREFS.register_method($*JMETH, $node.cuid);`):

```
            # The mainline (built from the comp_unit cursor before it
            # matched) and the compiler's own raw wrappers have no node to
            # take a file from. The class road backfilled them from the
            # class-level SourceFile attribute through the Java stack; a
            # ProgramUnit has no such class, so the block record carries
            # the unit's file itself (milestone 3, 2026-09-09).
            unless $*JMETH.cr_file {
                my $unit-file := nqp::ifnull(nqp::getlexdyn('$?FILES'), '');
                $*JMETH.cr_file(~$unit-file) if $unit-file;
            }
```

`nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/ExceptionHandling.kt`, `mappedLine` (line 381-383): when no native frame correlated, answer the block's declared start line instead of -1:

```kotlin
                return if (si.sourceFile != null && line >= 0)
                    line - si.sourceLineDelta
                else if (line < 0 && si.sourceFile != null && si.sourceLine > 0)
                    si.sourceLine
                else line
```

(`StaticCodeInfo.sourceLine`, `StaticCodeInfo.kt:136`, defaults to -1; `ProgramUnit.kt:45-53` fills it from `BlockRec.sourceLine` when the block has a file, which after the Compiler.nqp change above the mainline has, with `cr_line` 0. So the mainline answers `(-e)` without a line and a named sub answers `(-e:N)`.)

- [ ] **Step 6: The dumper refuses a compilation-unit carrier**

`nqp/src/HLL/Compiler.nqp:619`:

```
    method dumper($obj, $name, *%options) {
        # A compilation unit (the jar/classfile targets without --output)
        # has no textual dump; say so instead of dying inside nqp::can on
        # a carrier object that has no STable.
        if $!backend.is_compunit($obj) {
            nqp::die("--target=$name produces no dumpable output; use --output=<file>");
        }
        if nqp::can($obj, 'dump') {
```

- [ ] **Step 7: Docs sentence**

`docs/jvm-eval-server.md:57-60`: replace the sentence saying `NQP_CODE_RUN`/`NQP_CODE_PRECOMP` "come from the caller" with: "Since milestone 3 of the unit artifact (2026-09-09) the encoder and the unit road are on by default; nothing needs exporting beyond `RAKUDO_RAKUAST=1`, which the script exports itself. `NQP_UNIT=0`, `NQP_CODE_RUN=0`, `NQP_CODE_PRECOMP=0` opt out."

- [ ] **Step 8: nqp clean build WITHOUT the knobs (the test of the defaults)**

```
RAKUDO_RAKUAST=1 NQP_CODE_STRICT=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t2-build.log --show='> Task :stage' --show='code-bail' --show='BUILD' --show='rror' -- ./nqp/gradlew -p nqp clean buildJvm
```

Expected: EXIT=0; all 11 `nqp/build/jvm/share/lib/*.jar` are `unit.meta`=1, `.class`=0. If a jar comes out as a class-road jar, the gradle daemon's environment still carried `NQP_UNIT`/`NQP_CODE_*` from an earlier shell OR the default did not take: `./nqp/gradlew --stop` and rerun once; then read `run_init`.

- [ ] **Step 9: t/nqp, t/qast, 123 and 124 under the defaults**

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=nqp/t/nqp -t=nqp/t/qast --jobs=3 --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t2-sweep.log -- nqp/nqp-j-gradle
```

Expected: 118/118 t/nqp (with 019/063 from the nqp dir) and t/qast 2/2. A t/qast failure mentioning hll `nqp` vs `""` is milestone-2 minor 4 (`record()` maps `""` to `"nqp"`): fix in `UnitWriter.record` by keeping the JAST class's hll string verbatim, and note it in the ledger.

- [ ] **Step 10: Rakudo configure + make, no knobs in the environment**

`Configure.pl --gen-nqp` regenerates the runners through `create-jvm-runner.pl` and cleans the jvm products (a full ~20 min make follows either way):

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t2-configure.log -- perl Configure.pl --backends=jvm --gen-nqp
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t2-make.log --show='Compiling' --show='Generating' --show='rror' --stall=1500 -- make
```

Expected: configure EXIT=0 and `nqp/build/jvm/share/lib/nqp.jar` still `unit.meta`-only afterwards (if `--gen-nqp` rebuilt nqp it did so under the defaults, so the check must still hold); make EXIT=0. Record the make elapsed and the marker times (rakudo.jar, BOOTSTRAP v6c, CORE.c, CORE.d, CORE.e) as the next baseline. Then the artifact census, all from the rakudo root, one plain command per jar: `rakudo.jar`, `blib/CORE.c.setting.jar`, `blib/CORE.d.setting.jar`, `blib/CORE.e.setting.jar`, every `blib/Perl6/*.jar`, `blib/Perl6/BOOTSTRAP/*.jar`, `blib/Raku/*.jar`: `unzip -l <jar> | grep -c unit.meta` = 1 and `| grep -c '\.class'` = 0. Then the nested units: `unzip -l blib/CORE.c.setting.jar | grep -c 'nested/'` = 8 (four units, `.meta` + `.programs` each), the milestone-2 prediction. Then `grep -c UnitMain rakudo-j` = 1 and `grep -c "'perl6'" rakudo-j-build` = 0.

- [ ] **Step 11: The Rakudo gate on artifact units**

```
RAKUDO_RAKUAST=1 ./rakudo-j -e 'BEGIN { say 1 }; say EVAL "2"; say 3'
```
Expected `1 2 3` (each on its line) and, with `NQP_CODE_WHY=1 2>&1 | grep -c '^unit record '`, 3.

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=t/01-sanity --jobs=2 --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t2-sanity.log -- ./rakudo-j
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=t/03-jvm -t=t/10-qast --jobs=1 --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t2-jvm.log -- ./rakudo-j -Ilib
```
Expected: 25/25; t/03-jvm/01-interop.t and t/10-qast pass (the 2026-09-05 record has both passing).

The precomp round trip (the store slurps the artifact as bytes, prepends its header, loads it back through `nqp::loadbytecodebuffer` from an offset; `LibraryLoader.load(tc, ByteBuffer)` sniffs it):

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=t/02-rakudo/begin-closure-doc-precomp.t -t=t/02-rakudo/begin-regex-precomp.t -t=t/02-rakudo/begin-value-container-precomp.t -t=t/02-rakudo/compose-added-method-precomp.t -t=t/02-rakudo/constant-from-gather-precomp.t -t=t/02-rakudo/core-pseudo-package-precomp.t -t=t/02-rakudo/generic-native-precomp.t -t=t/02-rakudo/grammar-named-as-core-type-precomp.t -t=t/02-rakudo/precomp-declarator-block-or-hash.t -t=t/02-rakudo/rakuast-suspend-precomp-deps.t -t=t/02-rakudo/role-whatever-param-precomp.t -t=t/02-rakudo/trait-whatever-arg-precomp.t -t=t/02-rakudo/unit-lexical-precomp-repossess.t -t=t/02-rakudo/whatever-default-precomp.t --jobs=2 --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t2-precomp.log -- ./rakudo-j -Ilib
```
Expected: all pass, or fail exactly as the 2026-09-05 record lists (none of these 14 is in that record's failing list for t/02-rakudo). A failure whose diagnostic names `unit.meta`, `UnitZip`, `loadbytecodebuffer` or `ProgramUnit` is a flip regression to fix here; anything else is reported.

The two minors:

```
RAKUDO_RAKUAST=1 ./rakudo-j -e 'sub f() { die "x" }; f()' 2>&1 | grep -E 'in (sub f|block <unit>|<mainline>)'
```
Expected: every frame line carries `(-e:N)` or `(-e)`; none is a bare `in <mainline>` without a file.

```
RAKUDO_RAKUAST=1 ./rakudo-j --target=jar -e 'say 1' 2>&1 | head -2
```
Expected: `--target=jar produces no dumpable output; use --output=<file>`, no `lateinit`.

- [ ] **Step 12: Commit both trees**

nqp:
```
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git add src/vm/jvm/QAST/TruffleEncoder.nqp src/vm/jvm/QAST/Compiler.nqp src/vm/jvm/runtime/org/raku/nqp/runtime/ExceptionHandling.kt src/HLL/Compiler.nqp t/nqp/124-unit-record.t && git commit -m "unit artifact: the unit road and the encoder are the defaults (NQP_UNIT=0 / NQP_CODE_RUN=0 / NQP_CODE_PRECOMP=0 opt out); the mainline block carries the unit's file; --target=jar without --output says so" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01FyzDsYsbo1z8DspSvLpx5B"
```
rakudo (from the worktree root):
```
git add tools/build/create-jvm-runner.pl tools/templates/jvm/rakudo-j-build.in docs/jvm-eval-server.md && git commit -m "JVM: Rakudo runs as unit artifacts -- runners and the build runner enter through UnitMain <rakudo.jar>" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01FyzDsYsbo1z8DspSvLpx5B"
```

---

### Task 3: t/ through the eval server on artifact units (sweep 1)

**Files:** none modified; report `docs/superpowers/plans/2026-09-09-jvm-unit-artifact-milestone-3.reports/task-3-report.md` (controller-written).

**Interfaces:**
- Consumes: Task 2's build (`rakudo.jar` artifact, `rakudo-eval-server` runner unchanged, `t/harness5 --jvm --evalserver` passing `-app ./rakudo.jar`, `tools/build/evalserver-sweep.raku` sizing its pool from MemAvailable).
- Produces: the failing-file list and wall clock per directory, the baseline for Task 5's diff.

- [ ] **Step 1: Memory check**

`grep MemAvailable /proc/meminfo`; the sweep budgets `jobs x (heap + 3g)` against it and refuses an over-commit. Kill any stale server first: `pgrep -f org.raku.nqp.tools.EvalServer` must be empty (the runner's own guard also refuses to start over a live one).

- [ ] **Step 2: The sweep, two-hour ceiling**

Background job from the rakudo worktree root; Monitor the log at >= 90 s cadence and report progress every 90 s:

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --max=7200 --stall=1500 --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t3-sweep.log --show='chunk' --show='files in' --show='FAIL' -- raku tools/build/evalserver-sweep.raku t/01-sanity t/02-rakudo t/03-jvm t/04-nativecall t/05-messages t/06-telemetry t/07-pod-to-text t/08-performance t/10-qast t/13-experimental t/14-smoke
```

Expected: `N files in S s across C servers` and a chunk-failure list. The 2026-09-05 record (one warm server, `/home/longwalker/code/raku/x.core/rakudo/docs/jvm-full-suite-run-2026-09-05.md`, table at lines 9-21) is the comparison: 01-sanity 0 fail (1m04), 02-rakudo 20 fail (46m33, 290 files), 03-jvm 0 (0m17), 04-nativecall 2 (5m46), 05-messages 4 (8m59), 06-telemetry 0 (2m25), 07-pod-to-text 0 (0m20), 08-performance 2 (10m06), 10-qast 0 (0m11); 13-experimental and 14-smoke have no record. If the ceiling fires (`over the 7200s ceiling, giving up`), the report says which chunks finished, and the remaining directories run in a second invocation under their own `--max` only if the user asks; the wall clock IS the finding.

- [ ] **Step 3: Triage the diff**

For every failing file NOT in the 2026-09-05 list: rerun it alone (`RAKUDO_RAKUAST=1 ./rakudo-j -Ilib <file>`), then with `NQP_CODE_WHY=1 2>&1 | grep -E 'unit record|unit artifact|no engine program|code-bail'`. A die naming a block with "has no engine program" is an encoder refusal in that test (a shape the class road hid): report the block and the `NQP_CODE_BAIL=1` reason; a shape that recurs across files is fixed in an amend to Task 1's commit, followed by a runtime-only rebuild if it is Kotlin, or a stage build (Task 1 Step 8) if it is the encoder. Anything else is a Rakudo-level regression: reported with its first differing line, not fixed here unless one-line.

- [ ] **Step 4: Report**

`task-3-report.md`: the per-directory table (files, result, fails, wall) in the 2026-09-05 layout, the new-vs-known failing lists, the total wall clock (the number the user is waiting for before t/spec), and whether the ceiling fired.

---

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

### Task 5: t/ through the eval server after the deletions (sweep 2)

**Files:** none modified; report `task-5-report.md`.

**Interfaces:**
- Consumes: Task 4's build; Task 3's report (the baseline lists and wall clock).
- Produces: the diff sweep 2 minus sweep 1.

- [ ] **Step 1: The sweep, same recipe, two-hour ceiling**

Kill stale servers (`pgrep -f org.raku.nqp.tools.EvalServer` empty), then:

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --max=7200 --stall=1500 --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t5-sweep.log --show='chunk' --show='files in' --show='FAIL' -- raku tools/build/evalserver-sweep.raku t/01-sanity t/02-rakudo t/03-jvm t/04-nativecall t/05-messages t/06-telemetry t/07-pod-to-text t/08-performance t/10-qast t/13-experimental t/14-smoke
```

- [ ] **Step 2: Diff against sweep 1**

Expected: the failing-file set is identical to Task 3's. Any file failing here and not there is a deletion regression: rerun it alone with `NQP_CODE_WHY=1`; the likeliest shapes are a `raw` wrapper that never encoded before (the refusal hid it) or a block the size gate used to refuse (large BEGIN bodies). Fix in an amend to Task 4's nqp commit, runtime-only rebuild or stage build as the file dictates, and rerun that file. A file passing here and failing in sweep 1 is recorded as fixed-by-deletion.

- [ ] **Step 3: Report**

`task-5-report.md`: the table, the diff, the wall clock against Task 3's.

---

### Task 6: Docs, ledger, memory, push, handoff rebase

**Files:**
- Modify: rakudo `docs/jvm-truffle-only-plan.md:30-33` (items 5, 6, 7, 8 rows: milestone 3 DONE; item 7 Rakudo shapes done; item 8 "compiler-side deletions done, runtime writer waits for stage0")
- Modify: rakudo `docs/superpowers/specs/2026-09-09-jvm-unit-artifact-design.md` "Milestones" item 3 (DONE line: what shipped, deviations 1-4, the two sweeps' wall clocks, no t/spec) and item 4 (gains the runtime-side writer deletion explicitly)
- Modify: rakudo `CLAUDE.md` (the `RAKUDO_RAKUAST=1 on every build` paragraph: the `NQP_CODE_RUN`/`NQP_CODE_PRECOMP` sentence becomes "on by default since 2026-09-09; `=0` opts out")
- Create/modify: this plan's `.ledger.md` and `.reports/` (the controller keeps them as it goes)
- Memory: `/home/longwalker/.claude/projects/-home-longwalker-code-raku-x-core-rakudo/memory/unit-artifact-milestones.md` (milestone 3 state, the deviations, milestone 4's entry list), `truffle-plan-position.md` (one line), `strict-refusal-campaign.md` (item 7 Rakudo shapes DONE), MEMORY.md hooks

- [ ] **Step 1: Update the plan doc, the spec, CLAUDE.md** (text per the file list above; keep the rows' existing milestone-1/2 text and append the milestone-3 sentence).
- [ ] **Step 2: Commit the rakudo tree** (docs only): `git add docs/ CLAUDE.md && git commit -m "docs: unit artifact milestone 3 -- Rakudo on the unit road (plan, ledger, reports, spec and position updates)"` with the trailer.
- [ ] **Step 3: Handoff rebase** (user rule, every handoff): `git fetch origin` in the rakudo worktree and `git rebase origin/main`; `cd .../nqp && git fetch upstream && git rebase upstream/main`. Conflicts are expected to be few. No gate after the rebase (user: "don't worry about that").
- [ ] **Step 4: Push both trees with --force-with-lease to ab5tract** (`git push --force-with-lease ab5tract worktree-jesp-direct-lazy-records` from the rakudo worktree; `cd .../nqp && git push --force-with-lease ab5tract jesp-direct-lazy-records && git push --force-with-lease origin jesp-direct-lazy-records`). Never push main; no PR (user: not until finished).
- [ ] **Step 5: Remind the user to leave the session rather than /clear** (user request, every handoff).

---

## Self-review notes

- Spec coverage: milestone-3 line, "Rakudo units as artifacts, after custom_args bodies and exit-handler blocks encode" = Task 1 (exit handlers; custom_args landed in the campaign) + Task 2 (the flip); "the eval server serves artifact units" = Task 2 Step 11 (harness5 `-app ./rakudo.jar` on an artifact) + Tasks 3 and 5; "the suites run through it" = Tasks 3 and 5 for t/, Task 2/4 Step 9 for t/nqp, t/spec excluded by user decision 2. Section 4 "The generated runner scripts change the main class token and gain the unit path argument" = Task 2 Step 4. Section 4 "Identity: the unit id string" = deviation 4 (verified not load-bearing). Milestone-2 line's deletions = Task 4, narrowed by deviation 1. Open item "backtrace ... a fallback to the block's start line when no Java frame correlates" = Task 2 Step 5.
- Types and names: `FORLOOPL = 35` in NqpWire.java and `$W_FORLOOPL := 35` in the encoder (Task 1 Steps 5-6); `emitForBody(redoL, preAt, bodyAt, nrId, lastId, labelLocal)` used by both the FORLOOP (null) and FORLOOPL cases; the knob die substring `needs the encoder on` in Compiler.nqp (Task 2 Step 2, Task 4 Step 1) and in t/nqp/124 (Task 2 Step 3); `is_compunit` exists on the jvm, moar and js backends (Task 2 Step 6); `$main` in create-jvm-runner.pl is built after `$rakudo_jars` and before the `install` calls.
- Placeholders: none; every code step carries the edit. The one conditional instruction (Task 1 Step 5's "if the builder has a header-length table") names what to search for.
- Ordering: Task 1 runs on the class road for Rakudo (knob still opt-in) so an exit-handler bug shows up with the class road's fallbacks still available for everything else; Task 2 flips only after 118/118 and sanity are green on Task 1's nqp.

---

### Task 3b: Unit-road gaps from the t/ sweep (inserted by controller ruling, 2026-09-10)

**Why this task exists:** Task 3's sweep of t/ on artifact units found failures that are not in the 2026-09-05 record and that trace to the unit road having no bytecode fallback: encoder refusals (a hard error on the unit road) and engine-correctness gaps in blocks that used to fall back to bytecode. Task 4 (the deletions) builds nqp and Rakudo from the top; that build must carry these fixes so Task 5's sweep measures the deletions and not these. The full evidence is in `.superpowers/sdd/2026-09-09-jvm-unit-artifact-milestone-3/task-3-report.md`, section "NEW failures".

**Files:**
- Modify (as the fixes need): `nqp/src/vm/jvm/QAST/TruffleEncoder.nqp` (the refusals; narrow-native semantics), `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java` / `NqpOps.java` / `nqp/nqp-truffle/src/main/kotlin/**` (engine semantics), `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/**` (unit loader, nested records), `nqp/src/vm/jvm/QAST/Compiler.nqp` if a nested-unit shape needs it
- Do NOT modify Rakudo sources (`src/**`) or tests in this task; a Rakudo-side cause is reported, not fixed.
- Test: the files below, rerun cold with `RAKUDO_RAKUAST=1 ./rakudo-j -Ilib <file>` from the rakudo worktree root; `nqp/t/nqp` (the sweep); `t/01-sanity`.

**Interfaces:**
- Consumes: nqp at `e5f2b3840` (Task 2's fix commit, its encoder edit NOT yet built into the jars: your first nqp build builds it -- grep the build log for `bval to a block the unit never compiles` and `has no engine program`; a hit is a Task 2 regression to report, not to work around). Rakudo at `7e1a66552e` built jars from `08a997dc2b` (rakudo.jar and blib are the flip build; they stay as they are: this task needs NO Rakudo make, because a test file's blocks are runtime compiles through the nqp jars, and CORE's encoded blocks are re-made by Task 4's make).
- Produces: nqp commits; every wire change additive (new op numbers only, documented in NqpWire.java); no knob semantics change.

**The failures to work, in priority order** (file; the block/cuid and reason from the report; the expected shape of the fix):

1. **`code-bail sized typed param`** -- t/04-nativecall/00-misc.t (block `abs`, cuid 18), t/04-nativecall/02-simple-args.t (`TakeInt`, cuid 1), t/08-performance/32-rakuast-native-param-bind.t (`t`, cuid 17). A parameter with a sized native type (`int8`/`int16`/`int32`/`uint8`... in a NativeCall signature or a native-param sub). Find the encoder's param encoding (`patch_params` / the PARAMS record, `TruffleEncoder.nqp` around the `:returns` / `sized` handling) and the class road's treatment in Compiler.nqp (how it binds a sized param: the `param` ops with a `_i` sized variant, wrapping or truncation on bind); encode the same. If the wire's PARAMS record has no sized-width field, add an additive one (a new flag bit or a new op), never a layout change.
2. **`code-bail sized uint attributeref`** -- t/08-performance/30-rakuast-native-attr-lvalues.t (`wrap`, cuid 99). `getattrref_u` (or `_i` sized) on a sized attribute; same family as 1: the encoder's attributeref coverage (`getattrref_*` in `%hll_ops`) refuses a sized unsigned width. Match Compiler.nqp's sized attribute ref.
3. **`code-bail unnamed chain link`** -- t/08-performance/28-rakuast-metaop-hoist.t (`<unit>`, cuid 71), t/08-performance/39-rakuast-native-arg-value.t (`<anon 48>`, cuid 48). A `chain` QAST op whose link has no `name` (a chained comparison whose operator is a code object or a metaop rather than a named `&infix:<...>`). Find `encode_chain` (or the `chain` branch of `encode_op`) and the class road's `chain` in Compiler.nqp: the unnamed form calls the link's first child as a code object. Encode it the same way the encoder already encodes an unnamed `call` (callee expression, then args).
4. **int8 pre-increment wraparound** -- t/08-performance/14-rakuast-native-incdec.t subtest 7: `my int8 $x = 127; ++$x` must give -128, got 128. The encoder's `preinc`/`postinc` desugar (`add_i` on the variable) ignores the variable's sized width; the class road's `preinc` on a sized native wraps (find how Compiler.nqp / the `assign_i` to a sized lexical truncates: likely `bindlex` of a sized native goes through a width-aware store, or the QAST `Var` carries `:returns(int8)` and the bytecode path emits `i2b`). Fix at the point where the encoder stores into a sized native variable (a width-aware coerce after arithmetic: an additive `W_COERCE` kind or a dedicated op), so every `++`/`--`/`+=` on `int8/int16/int32/uint*` wraps as bytecode did. Probe: `RAKUDO_RAKUAST=1 ./rakudo-j -e 'my int8 $x = 127; ++$x; say $x; my uint8 $y = 255; ++$y; say $y; my int16 $z = 32767; $z++; say $z'` expects `-128`, `0`, `-32768`.
5. **EVAL inside BEGIN: NPE** -- t/02-rakudo/begin-time-eval-caller-context.t (`java.lang.NullPointerException at EVAL_0:18` in `BEGIN { $class-package = EVAL Q[$?PACKAGE...] }`; planned 8 ran 0), plus t/02-rakudo/begin-native-var.t (planned 10 ran 6) and t/02-rakudo/begin-time-attributive-param-method.t (planned 5 ran 2), presumed the same family. This is the flip's own shape: an EVAL compiled while the enclosing unit compiles is a nested record (`loadcompunit` retains it in `inMemoryUnitRecords`, the parent's writer embeds it under `nested/`, `ProgramUnit.claimNested` re-installs it at load). Reproduce cold first with a minimal file (`BEGIN { my $p = EVAL Q[$?PACKAGE]; say $p }; say 1`), then with `NQP_CODE_WHY=1` to see the `unit record` lines and where the NPE is thrown (get the Java stack: `RAKUDO_JVM_XOPTS=-Dnqp.debug.stacktrace=1` if such a knob exists in ExceptionHandling.dieInternal, else read `ExceptionHandling.kt`'s dieInternal to find how to print the host stack -- an env-gated print you add is fine, `NQP_HOST_STACK=1`). Likely suspects: the EVAL's outer context (`$?PACKAGE` is a lexical of the compiling unit: a record-road nested unit resolving its outer through `CallFrame.outerFor` / `jvm-repoint-dynamic-code`), or `claimNested` at run time for a unit that never got embedded because the class was loaded from memory. Fix in the runtime or Compiler.nqp; add the minimal reproducer as a probe in your report.
6. **`java.lang.ClassCastException: Long cannot be cast to SixModelObject` in method `u`** -- t/02-rakudo/generated-populate.t (planned 56 ran 23). An encoded block reads a native int register where an object was expected (a typed-local or return-register mismatch). Reproduce cold, find the block `u` in the file, `NQP_CODE_WHY=1` for its verdict, and bisect the QAST shape (a `nqp::bind` of an `int` into an obj lexical, or a `W_COERCE` missing on a branch). Fix in the encoder.
7. **`continuation captured at a non-suspendable site in an engine-run block`** -- t/02-rakudo/xx-sink-lazy.t (planned 3 ran 0). `gather`/`take` (a continuation) inside a block the engine entered on a non-suspendable road (a frame-free entry, or a `W_CLASSLIB`/direct call site that is not wrapped for suspension). Find where that message is thrown (`grep -rn 'non-suspendable' nqp/nqp-truffle nqp/src/vm/jvm/runtime`), which site kind it names, and make that site suspendable or force the block framed (the encoder's `%frame_forcing_ops` / `frame_op`), whichever the class road's equivalent implies (the bytecode road's `savesite` around the same call).
8. **`Too many positionals passed; expected 0 arguments but got 1`** at compile time for `is replace-method` / `is replace-sub` traits -- t/02-rakudo/yada-trait-timing.t lines 17/19 (SORRY). A `trait_mod:<is>` candidate whose signature is all named (`:$replace-method!`) being called with one positional: the arity check of an encoded PARAMS header that declares 0 positionals while the class road accepted the call (the invocant/positional was consumed by the multi dispatcher, or the candidate is `custom_args` and the header should be the empty `0 -1` custom_args header). Reproduce cold with a two-line file declaring `multi trait_mod:<is>(Routine $r, :$replace-method!) { }` and `sub f() is replace-method { }`; find whether the candidate block's `custom_args` flag reached `patch_params` (Compiler.nqp passes `$node.custom_args` into the encoder; RakuAST sets it in `src/Raku/ast/code.rakumod` when the signature needs the full binder). Fix in the encoder/Compiler.nqp; if the cause is RakuAST-side, report it (do not edit `src/`).

**Out of this task (report only, no work):** the corekeys/settingkeys cluster (NFC/NFD/NFKC/NFKD/Uni now in CORE::v6c: the NFG work of 2026-09-06 outran the tests' expected symbol lists; a Rakudo test expectation); the three chunks that pass on rerun (server heap growth; sweep infrastructure); t/qast/01-qast.t (moar-only API).

- [ ] **Step 1: Reproduce every item cold, before any edit**, one command each, from the rakudo worktree root, e.g. `RAKUDO_RAKUAST=1 ./rakudo-j -Ilib t/04-nativecall/00-misc.t 2>&1 | tail -5`, and for the refusals `NQP_CODE_BAIL=1 RAKUDO_RAKUAST=1 ./rakudo-j -Ilib <file> 2>&1 | grep -m1 code-bail`. Record each reproduction line in the report. An item that does not reproduce cold is reported as such and skipped.
- [ ] **Step 2: Fix items 1-8 in the order given**, each as its own nqp commit (message naming the file and the shape; both trailer lines). Kotlin for new runtime code; Java only where extending an existing Java file. Every new wire op additive and documented in NqpWire.java. Every diagnostic env-gated.
- [ ] **Step 3: Runtime jars compile**: `./nqp/gradlew -p nqp :nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars` after any Kotlin/Java edit (~20 s).
- [ ] **Step 4: ONE nqp clean build** at the end (not per item; forward only): `RAKUDO_RAKUAST=1 NQP_CODE_STRICT=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t3b-build.log --show-file=/home/longwalker/.claude/jobs/288cfddd/tmp/t3b-build.markers --show='> Task :stage' --show='code-bail' --show='BUILD' --show='rror' -- ./nqp/gradlew -p nqp clean buildJvm`. Expected EXIT=0; 11 jars `unit.meta`-only (`raku tools/build/jar-census.raku nqp/build/jvm/share/lib/*.jar` or per-jar unzip counts); grep the log for `bval to a block the unit never compiles` (Task 2's unbuilt edit: a hit is reported as a Task 2 regression, and this task then does NOT work around it -- report BLOCKED with the block named). If a fix needs a second build because the first showed a compile error in the encoder itself, that is allowed; two builds for one item is not.
- [ ] **Step 5: Rerun the 13 files** of items 1-8 cold (each `RAKUDO_RAKUAST=1 ./rakudo-j -Ilib <file>`), record pass/fail with the last TAP line; plus item 4's probe.
- [ ] **Step 6: t/nqp + t/qast**: `RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=nqp/t/nqp -t=nqp/t/qast --jobs=3 --log-dir=/home/longwalker/.claude/jobs/288cfddd/tmp/t3b-sweep-logs --show-file=/home/longwalker/.claude/jobs/288cfddd/tmp/t3b-sweep.markers -- nqp/nqp-j-gradle`; expected 118/118 (019/063 from the nqp dir) and t/qast 1/2 as in Task 2.
- [ ] **Step 7: t/01-sanity**: `RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=t/01-sanity --jobs=2 --log-dir=/home/longwalker/.claude/jobs/288cfddd/tmp/t3b-sanity-logs --show-file=/home/longwalker/.claude/jobs/288cfddd/tmp/t3b-sanity.markers -- ./rakudo-j`; expected 25/25 (the CORE jars are unchanged; this checks the runtime jars).
- [ ] **Step 8: Report.** Per item: reproduced (yes/no, line), root cause, the fix (files, mechanism, wire additions), the rerun result. Items not fixed: the analysis so far and what a fix would take. Then the short status contract.
