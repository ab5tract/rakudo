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

