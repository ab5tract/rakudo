# Task 4 report: the site address, the consumer, verify mode, the counters

Commit (nqp): `953251714` — "Dispatch: restore a site's persisted programs at its
first miss; verify mode; the counters (Phase C)". Nothing pushed; no jar staged.

## What I implemented

Exactly the brief's ten steps, no extras.

1. **`UnitStore`** (`nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitStore.kt`):
   `entryPrefix` (the writer's view of `prefix`) and `absoluteSlot(programIndex,
   ordinal)` returning -1 out of bounds, bounded by `header.dispatchSlotCount`.
   `dispatchSlot` now computes its slot through `absoluteSlot` and returns null on
   -1; the `off + len` past-the-entry check gained the `off < 0` rejection (ruling 12).
2. **`DispatchCallSite`** (`.../dispatch/DispatchBootstrap.kt`): the site address
   (`unitNamespace`, `programIndex`, `ordinal`), `restored`, `verifyPrograms`;
   `reset()` clears `restored` and `verifyPrograms` (an eval-server run re-arms
   from the slot); an `init` block counts into the new
   `DispatchBootstrap.created: AtomicLong`.
3. **`DispatchPersist`** (new, `.../dispatch/DispatchPersist.kt`): the
   `NQP_DISPATCH_PERSIST` knob (unset/`on`, `off`, `verify`), the process-wide
   namespace→`UnitStore` registry (`register`/`store`), `restore(tc, site)`
   (anonymous site / unregistered namespace / empty slot → empty list; a
   reference that does not resolve counts `dropped`; a slot that does not decode
   is a hard `IllegalStateException`), `verify(...)`, and the seven counters.
   verify mode prints `dispatch-verify: on` at class init and installs a shutdown
   hook printing `matched=/mismatched=/unseen=`.
4. **`Dispatch`** (`.../dispatch/Dispatch.kt`): the first-miss hook in `fallback`
   (ON installs and tries the restored programs, VERIFY parks them in
   `site.verifyPrograms`, OFF does nothing); in `record`, `recorded` is counted
   and, in verify mode, the fresh program is compared against the parked ones;
   `internal fun guardContext(...)` hands `DispatchPersist.verify` a
   `GuardCheckContext` while the class itself stays private.
5. **`ProgramUnit.initializeCompilationUnit`** registers its store under
   `identityNamespace()` right after `gc = tc.gc`.
6. **`NqpOps.EngineSite`** now takes `(CallSiteDescriptor, ProgramIdentity, int
   ordinal)` and fills the address from the identity (Java reads
   `getNamespace()`/`getProgramIndex()`); `NqpProgramBuilder` passes the identity
   and the ordinal straight through.
7. **The stats line** (`NqpDispatch.kt`) gained `sitesAll=`, `restored=`,
   `restoredSites=`, `dropped=`, `recorded=` after `anon=`.

## TDD evidence

**RED** — `./nqp/gradlew -p nqp :nqp-runtime:test --tests
'org.raku.nqp.dispatch.DispatchPersistTest' -q` with only Steps 1-3 in place:

```
e: .../DispatchPersistTest.kt:34:9 Unresolved reference 'DispatchPersist'.
e: .../DispatchPersistTest.kt:37:22 Unresolved reference 'DispatchPersist'.
...
* What went wrong:
Execution failed for task ':nqp-runtime:compileTestKotlin' ...
BUILD FAILED in 1s
```

**GREEN** — same command after Steps 5-8; quiet build, and the result XML:

```
<testsuite name="org.raku.nqp.dispatch.DispatchPersistTest" tests="1" skipped="0"
           failures="0" errors="0" ... time="0.086">
  <testcase name="restoreRealisesTheSlotsProgramsAndCountsThem()" .../>
```

## Tests

Whole runtime suite, `./nqp/gradlew -p nqp :nqp-runtime:test -q`, run twice (once
before and once after the two cosmetic fixes found in self-review) — 42 tests,
0 failures, 0 errors (41 before this task, +1 new):

```
org.raku.nqp.dispatch.DispatchSlotCodecTest tests=4 fail=0 err=0
org.raku.nqp.runtime.SerializationContextTest tests=1 fail=0 err=0
org.raku.nqp.runtime.GraphemeCursorTest tests=7 fail=0 err=0
org.raku.nqp.runtime.StaticCodeInfoLazyTest tests=5 fail=0 err=0
org.raku.nqp.dispatch.DispatchPersistTest tests=1 fail=0 err=0
org.raku.nqp.runtime.unit.UnitStoreTest tests=7 fail=0 err=0
org.raku.nqp.runtime.unit.ProgramUnitTest tests=12 fail=0 err=0
org.raku.nqp.runtime.unit.UnitCodecTest tests=5 fail=0 err=0
TOTAL tests=42
```

The new test exercises real behaviour: it persists a real `DispatchProgram`
(KnowHOW type guard), encodes it into a `UnitImage`'s slot 1, opens the image as
a store, registers it, restores through a site addressed at (program 0, ordinal 1),
and asserts the realised program's `DispatchDump.describe` text equals the
original's, that the `restored` counter advanced, and that an anonymous site and
an empty slot both restore nothing. Output pristine (no stray prints).

## Smoke (Step 9)

Jars rebuilt with `./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar
syncRuntimeJars -q` (~4 s incremental; only the accepted `ThreadDeath`
deprecation noise).

Default mode, `NQP_DISPATCH_STATS=1 RAKUDO_RAKUAST=1 ./rakudo-j -e ''`:

```
dispatch stats: hits=80298 misses=5056 sites=6522 anon=5 sitesAll=6596 restored=0 restoredSites=0 dropped=0 recorded=4723 slowEvals=52 invokes=7197 directs=7195 noTarget=2 badExpectation=0 notCodeRef=0 slowLayout=32 slowNull=20 byKind[value,syscall,mapped,invoke,resumable]=[0, 38151, 32587, 7179, 2381]
```

`sitesAll - sites` = **6596 - 6522 = 74** (of which 5 are the engine's anonymous
sites, so 69 are runtime-made: the helper sites in `Ops`, the indy road, Rakudo's
rv-decont sites).

verify mode, `NQP_DISPATCH_PERSIST=verify NQP_DISPATCH_STATS=1 RAKUDO_RAKUAST=1
./rakudo-j -e ''`:

```
dispatch-verify: on
dispatch-verify: matched=0 mismatched=0 unseen=4606
```

(The stats line is identical in verify mode, `restored=0 ... recorded=4723`.)

Both match the brief's expectation: no slot is filled yet (Task 5 writes them),
so nothing restores and every recording at an addressed site is "unseen". The
`recorded=4723` is a little under the brief's "close to 5023" — it counts
completed recordings in `Dispatch.record`, while `misses=5056` counts engine-side
misses (which include the sites that replay without recording and the
uncached/bind-failure roads), so the two are not the same population. Nothing
here depends on the exact figure; it is the Task 5 baseline.

## Files changed

- `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt` (new)
- `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/Dispatch.kt`
- `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchBootstrap.kt`
- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt`
- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitStore.kt`
- `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java`
- `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java`
- `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt`
- `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchPersistTest.kt` (new)

No jar staged; the nine modified `src/vm/jvm/stage0/*.jar` remain uncommitted
working-tree changes.

## Self-review findings (fixed before committing)

1. The first placement of `Dispatch.guardContext` landed *between*
   `GuardCheckContext`'s KDoc and the class, orphaning the class's own doc.
   Moved below the class, with its own KDoc.
2. `import org.raku.nqp.dispatch.DispatchBootstrap` was out of alphabetical order
   in `NqpDispatch.kt`. Reordered.

Re-checked against the brief's checklist: the stats line, `reset()` clearing
`restored`/`verifyPrograms`, the registration in `initializeCompilationUnit`, the
`absoluteSlot` bounds and the `off < 0` rejection are all in. `Captures.sameShape`
was already public, so nothing needed widening; `GuardCheckContext` stays private.
No `com.oracle.truffle` import entered nqp-runtime; the only Java edits are the two
DSL-bound files; every new print is gated (verify prints by the mode, stats by
`NqpDispatch.STATS`).

## Issues or concerns

- `DispatchPersist.store(namespace)` and `UnitStore.entryPrefix` have no caller
  yet — they are the interface Task 5's writer consumes. Left in per the brief's
  "Produces" list.
- `DispatchPersist.verify`'s parameter `recorded` shadows the counter of the same
  name inside that function body. Verbatim from the brief and harmless (the
  counter is not read there), but worth a rename if Task 5 touches the function.
- The restore road is untested end to end against a *real* artifact, because no
  slot is written yet; the unit test covers it against a hand-built image. The
  first real exercise comes with Task 5.

---

# Fix round 1 (review finding 1: verify's comparison branches were dead code)

Amended commit (nqp): `5fd74d9b6` (was `953251714`) — same subject, same evening
dates, same trailer. Nothing pushed.

## What changed

Test-only. No production defect was exposed: `DispatchPersist.verify` behaved as
written on the first run of the new test, so `DispatchPersist.kt` is untouched.

`nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchPersistTest.kt`
gains `verifyCountsAMatchAMismatchAndACallItDoesNotApplyTo()`, which builds a site
with `verifyPrograms = [P]` (P guards `Arg(0)` by `knowhow.st`, outcome
`value(arg(0))`) and calls `DispatchPersist.verify` three times, reading each of
the three counters into a `before` value before each call:

- **(a) matched** — a recorded program with the same `DispatchDump.describe` text
  as P, args `arrayOf<Any?>(knowhow)` (the KnowHOW type object, on which P's guard
  holds), descriptor = P's: asserts `verifyMatched` +1, `verifyMismatched` and
  `verifyUnseen` unchanged.
- **(b) mismatched** — same descriptor and guards, outcome
  `Outcome.Value(ValueSource.Literal(ArgKind.INT, 1L))` instead of
  `Outcome.Value(ValueSource.Arg(0))`: asserts `verifyMismatched` +1, the other two
  unchanged, and — capturing `System.err` into a `ByteArrayOutputStream` via
  `System.setErr`, restored in a `finally` — that the captured text contains
  `dispatch-verify: MISMATCH` and both `persisted:` and `recorded:`. This covers the
  MISMATCH line's interpolation (`site.identity`/`site.linkedName` are set on the
  fixture site).
- **(c) unseen** — args `arrayOf<Any?>(tc.gc.BOOTArray)`, whose STable is not
  KnowHOW's, so P's guard rejects the call: asserts `verifyUnseen` +1, the other two
  unchanged.

The test registers nothing, so the process-wide store registry is untouched and
the two tests in the class cannot interfere; the counters are read as deltas, as
the first test already does.

## Covering tests and output

Focused: `./nqp/gradlew -p nqp :nqp-runtime:test --tests
'org.raku.nqp.dispatch.DispatchPersistTest' -q`

```
<testsuite name="org.raku.nqp.dispatch.DispatchPersistTest" tests="2" skipped="0"
           failures="0" errors="0" ... time="0.089">
```

Whole suite: `./nqp/gradlew -p nqp :nqp-runtime:test -q` — 43 tests, 0 failures,
0 errors:

```
org.raku.nqp.runtime.GraphemeCursorTest tests=7 fail=0 err=0
org.raku.nqp.runtime.unit.UnitCodecTest tests=5 fail=0 err=0
org.raku.nqp.dispatch.DispatchSlotCodecTest tests=4 fail=0 err=0
org.raku.nqp.dispatch.DispatchPersistTest tests=2 fail=0 err=0
org.raku.nqp.runtime.unit.ProgramUnitTest tests=12 fail=0 err=0
org.raku.nqp.runtime.unit.UnitStoreTest tests=7 fail=0 err=0
org.raku.nqp.runtime.SerializationContextTest tests=1 fail=0 err=0
org.raku.nqp.runtime.StaticCodeInfoLazyTest tests=5 fail=0 err=0
TOTAL tests=43
```

No jar rebuild and no smoke re-run: the change is test-only, the runtime jars
built for the first report's smokes are unchanged, and no jar is staged.

---

# Fix round 2 (rulings 17, 18, 19)

**Commit: nqp `d3e602917`, a NEW commit, not an amend.** The contract asked for
`--amend`, but `5fd74d9b6` is no longer HEAD: Task 5's commit `3d0b54fa4` landed
on top of it while this round was being prepared, so amending would have rewritten
Task 5's commit, and a hard reset/cherry-pick rewrite would have disturbed a
worktree another session may be using for the end-to-end re-run. The new commit
says in its body that it belongs in `5fd74d9b6`; squash it there at the next
stack rewrite. Evening dates and the exact trailer as required; no jars staged;
nothing pushed.

**Near-miss worth recording:** Task 5 had added the recorder (`recordSelector`,
`selected`, the `NQP_DISPATCH_RECORD` shutdown hook and `recordAtExit`) to
`DispatchPersist.kt` after round 1. My first pass rewrote that file whole and
silently dropped all of it (the build still compiled, since nothing else names
`recordAtExit`). Caught in review of my own `git diff HEAD`; the file was restored
from HEAD and the three rulings re-applied as targeted edits. Task 5's recorder is
verified present (`recordAtExit` at line 207, the hook at line 93).

## What changed

1. **Ruling 17 — compare by evaluated outcome** (`DispatchPersist.kt`). `verify`
   now counts, per applicable kept program: same `DispatchDump.describe` text →
   `verifyMatched`; else `sameOutcome(ctx, p, recorded)` → the new
   `verifyByOutcome`; else `verifyMismatched` plus the MISMATCH block.
   `kept.isEmpty()` short-circuits to `verifyUnseen` before the text is built.
   `sameOutcome` refuses resuming programs and unequal `bindControl`, compares
   resumptions pairwise by dispatcher id and capture, then the outcomes:
   `Value` by the evaluated source, `InvokeCode` by the evaluated callee and the
   capture, `InvokeSyscall` by name and capture; mixed kinds differ. `sameCapture`
   compares shape then the evaluated arrays elementwise; `sameValue` uses identity
   for `SixModelObject` and `==` otherwise. Evaluation is read-only, but a source
   that cannot be evaluated here throws, and the `catch (_: Exception)` counts that
   as a difference (stated in the KDoc). Exit totals now read
   `dispatch-verify: matched=N byOutcome=N mismatched=N unseen=N`.
2. **Ruling 18 — output routing** (`DispatchPersist.kt`). `NQP_DISPATCH_VERIFY_LOG`
   is read once into a `val`; `verifySay` sends every verify line to stderr when it
   is unset (byte for byte as before) and otherwise to a lazily opened, appending,
   autoflush `PrintStream`, each line prefixed `[<pid>] `. The stream is closed in
   the shutdown hook after the totals.
3. **Ruling 19 — drop diagnostics.** `DispatchSlotCodec.realise(tc, p, onDrop =
   null)` invokes `onDrop` with the `Unpersistable` message before returning null
   (every existing two-argument call is unchanged); `DispatchPersist.restore`
   passes one when `NQP_DISPATCH_PERSIST_TRACE` is set, printing
   `dispatch-persist: dropped <site identity> <reason>`.

## Covering tests

New `DispatchPersistTest.verifyAcceptsADifferentFormWithTheSameEvaluatedOutcome()`:
a kept program invoking `Literal(OBJ, knowhow)` versus a recording invoking
`Arg(0)` on args `[knowhow]` — different text, one callee — asserts
`verifyByOutcome` +1, `verifyMatched`/`verifyMismatched`/`verifyUnseen` unchanged,
and that nothing is printed; then a recording invoking `Literal(OBJ, BOOTArray)`
asserts `verifyMismatched` +1, `verifyByOutcome` unchanged, and the MISMATCH line
printed. The round-1 test's inline stderr capture moved into a shared private
`capturingErr { }` helper. No test for the log knob: it reads its env var once at
class init, so exercising it would need a child process — left to the end-to-end
re-run, and smoked by hand below.

`./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.dispatch.DispatchPersistTest' -q`:

```
<testsuite name="org.raku.nqp.dispatch.DispatchPersistTest" tests="3" skipped="0"
           failures="0" errors="0" ... time="0.092">
```

`./nqp/gradlew -p nqp :nqp-runtime:test -q` — 46 tests, 0 failures, 0 errors
(43 after round 1, +2 from Task 5's `UnitDispatchWriterTest`, +1 mine):

```
org.raku.nqp.runtime.GraphemeCursorTest tests=7 fail=0 err=0
org.raku.nqp.runtime.SerializationContextTest tests=1 fail=0 err=0
org.raku.nqp.dispatch.DispatchPersistTest tests=3 fail=0 err=0
org.raku.nqp.dispatch.DispatchSlotCodecTest tests=4 fail=0 err=0
org.raku.nqp.runtime.unit.UnitCodecTest tests=5 fail=0 err=0
org.raku.nqp.runtime.unit.UnitDispatchWriterTest tests=2 fail=0 err=0
org.raku.nqp.runtime.unit.ProgramUnitTest tests=12 fail=0 err=0
org.raku.nqp.runtime.unit.UnitStoreTest tests=7 fail=0 err=0
org.raku.nqp.runtime.StaticCodeInfoLazyTest tests=5 fail=0 err=0
TOTAL tests=46
```

## Jars and smoke (against the artifacts Task 6 trained)

`./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars -q` — clean.

`NQP_DISPATCH_STATS=1 RAKUDO_RAKUAST=1 ./rakudo-j -e ''`:

```
dispatch stats: hits=13292 misses=4306 sites=6438 anon=5 sitesAll=6511 restored=4477 restoredSites=4195 dropped=37 recorded=193 slowEvals=83 invokes=5985 directs=5983 noTarget=2 badExpectation=0 notCodeRef=0 slowLayout=32 slowNull=27 byKind[value,syscall,mapped,invoke,resumable]=[0, 2179, 3781, 5967, 1365]
```

(Recording collapsed from 4723 to 193 now that the slots are filled.)

`NQP_DISPATCH_PERSIST=verify NQP_DISPATCH_VERIFY_LOG=/tmp/dv.log RAKUDO_RAKUAST=1
./rakudo-j -e 'say(42)'` — stdout `42`, **stderr empty**, and the log holds exactly
two pid-prefixed lines:

```
[264466] dispatch-verify: on
[264466] dispatch-verify: matched=4468 byOutcome=4 mismatched=0 unseen=720
```

The 4 cold-rakudo mismatches ruling 17 was written for are now `byOutcome=4`, and
`mismatched=0`.
