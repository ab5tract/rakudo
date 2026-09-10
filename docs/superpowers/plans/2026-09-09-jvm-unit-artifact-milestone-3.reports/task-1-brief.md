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

