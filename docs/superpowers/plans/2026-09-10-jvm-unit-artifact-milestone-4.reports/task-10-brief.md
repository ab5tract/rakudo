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

