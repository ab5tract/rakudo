# Task 3 report: the schema and the codec (`DispatchSlot`, `DispatchSlotCodec`)

Commit (nqp): `e27a795d8` (was `18310f0a2` before fix round 1 amended it) --
*Dispatch: the persisted program -- DispatchSlot schema and DispatchSlotCodec
(Phase C)*. Nothing pushed; no jars staged.

## What I implemented

1. **Double in the unit codec.**
   `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitCodec.kt`:
   `encodeDouble` is now `encodeLong(value.toRawBits())` and `decodeDouble`
   `Double.fromBits(buf.getLong())` (the two were `UnsupportedOperationException`
   throwers). The object's KDoc layout sentence names the new case ("a Double
   as its raw bits"); `Short`, `Char` and `Float` still throw.

2. **`DispatchSlot.kt`** (new, `org.raku.nqp.dispatch`): the persisted twin of
   the model -- `PRef` (handle, index, kind with `OBJ`/`CODE`/`STABLE`),
   `PDescriptor`, the `PSource` sealed family, the `PGuard` sealed family,
   `PShape`, the `POutcome` sealed family, `PResumption`, `PLevel`, `PBind`,
   `PProgram` and `DispatchSlot(programs)`. Verbatim from the brief: every
   class name, field name, order and `@SerialName` tag is as written.
   `ArgKind` and `ResumeKind` ride along as plain (non-`@Serializable`) enums;
   kotlinx serializes an enum by its declaration index, which our writer
   encodes as an Int.

3. **`DispatchSlotCodec.kt`** (new, same package): `persist(p: DispatchProgram):
   PProgram?` and `realise(tc: ThreadContext, p: PProgram): DispatchProgram?`,
   plus the public `ref(SixModelObject?)` / `ref(STable?)` overloads and the
   `Unpersistable` exception, verbatim from the brief. Both entry points catch
   `Unpersistable` and answer null; everything below them is a total recursion
   over the tree with no state and no caching.

4. **`DispatchDump.kt`**: its three private addressing helpers (`objectIndex`,
   `codeIndex` and the two `ref` bodies' index validation) are gone; the two
   `ref` overloads now call `DispatchSlotCodec.ref` and render the returned
   `PRef` as `obj:`/`code:`/`st:` `handle:index`, mapping `Unpersistable` back
   to the same `NP(obj:<class>:<type>:nosc|notroot)` /
   `NP(st:<name>:nosc|notroot)` text as before. Two now-unused imports
   (`CodeRef`, `SerializationContext`) dropped. `describe(p: DispatchProgram):
   String` stays public and unchanged. A three-line comment says why the
   addressing is shared: a dump names a reference exactly when the program
   carrying it persists.

Deliberately not done (YAGNI, and later tasks own them): no writer, no
consumer, no `unit.dispatch` plumbing, no env-gated logging (there is nothing
to log here).

## What I tested, and the results

New: `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchSlotCodecTest.kt`
(3 tests, as the brief specifies):

- `aProgramOverScObjectsRoundTripsToTheSameText` -- a program over the
  bootstrap's KnowHOW (type guard on its STable, a concreteness guard, a STR
  literal guard, an HLL guard, an `InvokeCode` outcome over an OBJ literal
  callee and a two-source capture shape carrying an INT literal) persists,
  encodes through `UnitCodec`, decodes, realises, and `DispatchDump.describe`
  of the original and of the realised program are equal. This is the real
  road: the sealed-class polymorphic serializers, the recursive `PProgram`,
  `ByteArray`, nullable strings and the enums all go through our codec.
- `anObjectInNoScMakesTheProgramUnpersistable` -- a fresh type object from
  `KnowHOW.st.REPR.type_object_for(tc, null)` (so `sc == null`) inside an OBJ
  literal guard makes `persist` answer null.
- `aReferenceThatDoesNotResolveDropsTheProgram` -- a hand-built `PProgram`
  naming SC `"no-such-sc"` makes `realise` answer null.

Amended: `UnitCodecTest.kt` gains the nested `@Serializable class WithDouble`
and `doublesRoundTripAsRawBits` (12 bytes; `-0.0` survives bit for bit, so the
test would catch a `==`-based round trip that collapsed it onto `0.0`).

The `tc.gc.KnowHOW` field exists with that spelling (`GlobalContext.kt:30`), so
neither of the brief's fallbacks was needed; `REPR.type_object_for(tc, HOW)` is
the REPR API's spelling (`REPR.kt:36`).

## TDD evidence

**RED (a), the dispatch test against nothing:**

```
$ ./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.dispatch.DispatchSlotCodecTest' -q
e: .../DispatchSlotCodecTest.kt:36:39 Unresolved reference 'DispatchSlotCodec'.
e: .../DispatchSlotCodecTest.kt:37:38 Unresolved reference 'DispatchSlot'.
e: .../DispatchSlotCodecTest.kt:53:21 Unresolved reference 'PProgram'.
e: .../DispatchSlotCodecTest.kt:53:30 Unresolved reference 'PDescriptor'.
e: .../DispatchSlotCodecTest.kt:54:20 Unresolved reference 'PGuardType'.
e: .../DispatchSlotCodecTest.kt:54:31 Unresolved reference 'PArg'.
e: .../DispatchSlotCodecTest.kt:54:40 Unresolved reference 'PRef'.
e: .../DispatchSlotCodecTest.kt:55:13 Unresolved reference 'POutcomeValue'.
(24 errors)
* What went wrong:
Execution failed for task ':nqp-runtime:compileTestKotlin' ...
BUILD FAILED in 2s
```

**RED (b), the Double test.** The compile failure above hides it, so I moved
`DispatchSlotCodecTest.kt` aside for one run to see the Double case fail on its
own merits, then restored it:

```
$ ./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.runtime.unit.UnitCodecTest' -q
5 tests completed, 1 failed
BUILD FAILED in 1s
$ grep -o 'message="[^"]*"' .../TEST-org.raku.nqp.runtime.unit.UnitCodecTest.xml | head -1
message="java.lang.UnsupportedOperationException: unit codec: no Double"
```

**GREEN, the focused pair:**

```
$ ./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.dispatch.DispatchSlotCodecTest' --tests 'org.raku.nqp.runtime.unit.UnitCodecTest' -q
(no output -- no errors, no warnings)
$ ... TEST-org.raku.nqp.dispatch.DispatchSlotCodecTest.xml
name="org.raku.nqp.dispatch.DispatchSlotCodecTest" tests="3" skipped="0" failures="0" errors="0"
  aProgramOverScObjectsRoundTripsToTheSameText()
  anObjectInNoScMakesTheProgramUnpersistable()
  aReferenceThatDoesNotResolveDropsTheProgram()
```

**GREEN, the whole module (before committing):**

```
$ ./nqp/gradlew -p nqp :nqp-runtime:test
BUILD SUCCESSFUL in 1s

org.raku.nqp.dispatch.DispatchSlotCodecTest   tests=3  failures=0 errors=0
org.raku.nqp.runtime.GraphemeCursorTest       tests=7  failures=0 errors=0
org.raku.nqp.runtime.SerializationContextTest tests=1  failures=0 errors=0
org.raku.nqp.runtime.StaticCodeInfoLazyTest   tests=5  failures=0 errors=0
org.raku.nqp.runtime.unit.ProgramUnitTest     tests=12 failures=0 errors=0
org.raku.nqp.runtime.unit.UnitCodecTest       tests=5  failures=0 errors=0
org.raku.nqp.runtime.unit.UnitStoreTest       tests=7  failures=0 errors=0
                                              total 40, 0 failures
```

36 -> 40 as the brief predicted (3 new dispatch tests + 1 new codec test).
Wall time: every gradle invocation in this task ran in 1-3 s (the focused runs
and the full `:nqp-runtime:test` alike); no long-running task, so no
`watched-run.raku`. No `syncRuntimeJars`, `buildJvm`, `clean`, `:nqp-truffle:jar`
or Rakudo `make` was run -- the concurrent gate build was left alone.

## Files changed

- `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlot.kt` (new, 55 lines)
- `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlotCodec.kt` (new, 175 lines)
- `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchDump.kt` (modified)
- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitCodec.kt` (modified)
- `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchSlotCodecTest.kt` (new)
- `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitCodecTest.kt` (modified)

## Self-review findings (all fixed before the commit)

- I first wrote the realise-side `outcome()` with a stray `is Outcome.Value ->`
  branch copied from the persist side; caught on re-reading the file, removed
  before the first compile.
- `DispatchDump` at first carried the `PRef` -> text rendering inline in both
  `ref` overloads, with a `!!` inside a `catch`-scoped expression that relied on
  a smart cast. Rewritten as an early `null` return plus two small helpers
  (`kindName`, `address`), which also puts the `st:` spelling in the same table
  as `obj:`/`code:`.
- The two imports `DispatchDump` no longer uses (`CodeRef`,
  `SerializationContext`) were left behind by the deletion; removed.
- My first KDoc edit to `UnitCodec` left a ragged re-wrap ("no field tags. A" on
  its own line); refilled.
- Output is pristine: the GREEN focused run under `-q` printed nothing at all,
  so the Kotlin compile emitted no `w:` warnings for any of the new or amended
  files.

## Issues and concerns

1. **Commit trailer.** The task instructions gave the trailer as an example
   ("e.g. ... `Co-Authored-By: Claude Fable 5.1`"), but this session ran on
   Opus 5 and the session's own attribution reminder names
   `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`. I used
   the accurate one. Say the word and I will amend.

2. **`Unpersistable` captures a stack trace.** As the brief specifies it, it is
   a plain `RuntimeException`, so every unpersistable reference pays a
   `fillInStackTrace` -- on the C0 numbers, ~1.1 % of programs, once each per
   persist attempt, at artifact-write time only. Not measurable at that rate,
   but if the writer ever calls `persist` in a loop over every site of a large
   unit, `RuntimeException(what, null, false, false)` is the one-line fix. Left
   as the brief has it; flagging for the writer task.

3. **Enum stability.** `ArgKind` and `ResumeKind` persist by declaration index
   (kotlinx's default for an enum without `@SerialName`s). Reordering either
   enum silently reinterprets old artifacts. That is the same contract the rest
   of the artifact has (the unit format is versioned, not tagged), so I did not
   add names; worth a line in the artifact-version note whenever those enums
   change.

4. **`realise` trusts the recorded `descriptor`.** A `PDescriptor` whose flags
   are nonsense (a truncated or corrupted artifact) reaches
   `CallSiteDescriptor`'s constructor, which will throw something that is not
   `Unpersistable` and so will not be swallowed into "record as you always
   did". That is the right behaviour for a corrupt artifact (fail loudly rather
   than silently mis-dispatch), but it means the consumer task should decide
   whether a malformed slot is a hard error or a skip.

---

# Fix report -- round 1

Both findings fixed and folded into the single (amended) commit
**nqp `e27a795d8`**; still unpushed, still no jars staged. The author date
stayed `2026-09-15T20:40:00+02:00`; the committer date is
`2026-09-15T21:10:00+02:00` (both evening).

## Finding 1 (Important): HLL guards realised against the wrong registry

Implemented the controller's ruling exactly, in four places.

1. **`HLLConfig.kt`** -- `@JvmField var compilerSide: Boolean = false`, with a
   KDoc saying why a name alone does not identify a config.
2. **`GlobalContext.kt`** --
   - `getHLLConfigFor` now stamps the config it *creates*:
     `config.compilerSide = hllConfiguration === compilerHLLConfiguration`,
     inside the `synchronized` block, before the `put`.
   - The init block used to assign `compileeHLLConfiguration`, point
     `hllConfiguration` at it and create the `""` config *before*
     `compilerHLLConfiguration` existed, so that first stamp would have read a
     not-yet-assigned field. I hoisted `compilerHLLConfiguration = HashMap()`
     up two lines, so both registries exist before either config is made; the
     order of the two `getHLLConfigFor("")` calls and the registry
     `hllConfiguration` ends up pointing at (the compiler one) are unchanged.
     A three-line comment records why the order matters. I checked the
     reviewer's alternative: the two `""` configs at what is now
     GlobalContext.kt:287-288 are only `setupConfig`'d there, not created --
     `grep -rn 'HLLConfig()' nqp/src/vm/jvm/runtime` finds exactly one
     construction, the one in `getHLLConfigFor` -- so no config escapes the
     stamp.
   - New non-creating lookup, synchronizing on the chosen registry rather than
     on `hllConfiguration`:
     `fun findHLLConfig(language: String, compilerSide: Boolean): HLLConfig?`.
3. **`DispatchSlot.kt`** -- `PGuardHll(val on: PSource, val hll: String?, val compilerSide: Boolean)`.
4. **`DispatchSlotCodec.kt`** -- persist:
   `PGuardHll(source(g.on), g.hll?.name, g.hll?.compilerSide ?: false)`;
   realise: `tc.gc.findHLLConfig(it, g.compilerSide) ?: throw Unpersistable("no HLL config $it (compilerSide=${g.compilerSide})")`,
   with a comment saying why it is not `getHLLConfigFor`.

### Covering tests

`DispatchSlotCodecTest` goes 3 -> 4 tests:

- **`anHllGuardRealisesInTheRegistryItWasRecordedIn`** (new) -- makes a
  compilee-side `"nqp"` config and a compiler-side one, asserts they are
  distinct instances, then round-trips a program guarding on the *compilee*
  one while the *compiler* registry is current (the state `Ops.loadcompunit`
  puts the process in) and asserts the realised guard holds the same instance
  it started with.
- **`aReferenceThatDoesNotResolveDropsTheProgram`** (extended) -- a second
  ghost, `PGuardHll(PArg(0), "no-such-hll", false)`, must also realise to null.
- **`aProgramOverScObjectsRoundTripsToTheSameText`** (extended) -- now asserts
  `assertSame` on the round-tripped `Guard.OfHll`'s config, since `describe()`
  prints only the name. Its HLL guard had to change: the review suggested
  asserting on `knowhow.st.hllOwner`, but `KnowHOWBootstrapper` never sets
  `hllOwner` (it stays the `STable.kt:135` default `null`), so that guard was
  vacuous and the identity assertion would have compared `null` to `null`. The
  fixture now guards on `tc.gc.getHLLConfigFor("nqp")`. Neither test asserts
  the flag's *value*, so both follow whichever registry the fresh runtime is in
  rather than assuming one (it is the compiler registry: GlobalContext's init
  leaves `hllConfiguration` pointing there).

A round-trip helper `roundTrip(tc, p)` (persist -> encode -> decode -> realise)
now serves both round-trip tests instead of the steps being inlined once.

### RED / GREEN for the fix

I reverted just the realise line to the old `tc.gc.getHLLConfigFor(it)` to
check that the new tests actually catch the bug:

```
$ ./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.dispatch.DispatchSlotCodecTest' -q
4 tests completed, 2 failed
BUILD FAILED in 2s

aReferenceThatDoesNotResolveDropsTheProgram()
  AssertionFailedError: actual value is not null ==> expected: <null> but was: <...DispatchProgram@1338fb5>
anHllGuardRealisesInTheRegistryItWasRecordedIn()
  AssertionFailedError: expected: <...HLLConfig@7e7b159b> but was: <...HLLConfig@7e5d9a50>
```

-- i.e. the old lookup both fabricates a config for an unknown name and hands
back the wrong instance. Restoring `findHLLConfig`:

```
$ ./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.dispatch.DispatchSlotCodecTest' -q
(no output -- passes, no warnings)
```

### Whole module, before the amend

```
$ ./nqp/gradlew -p nqp :nqp-runtime:test
BUILD SUCCESSFUL in 1s

org.raku.nqp.dispatch.DispatchSlotCodecTest   tests=4  failures=0 errors=0
org.raku.nqp.runtime.GraphemeCursorTest       tests=7  failures=0 errors=0
org.raku.nqp.runtime.SerializationContextTest tests=1  failures=0 errors=0
org.raku.nqp.runtime.StaticCodeInfoLazyTest   tests=5  failures=0 errors=0
org.raku.nqp.runtime.unit.ProgramUnitTest     tests=12 failures=0 errors=0
org.raku.nqp.runtime.unit.UnitCodecTest       tests=5  failures=0 errors=0
org.raku.nqp.runtime.unit.UnitStoreTest       tests=7  failures=0 errors=0
                                              total 41, 0 failures
```

36 -> 41 now (4 dispatch + 1 codec). Every gradle run in this round took 1-3 s;
no `syncRuntimeJars`, `buildJvm`, `clean`, `:nqp-truffle:jar` or Rakudo `make`
was run.

## Finding 2 (spec deviation): the commit trailer

Amended: the trailer now reads exactly
`Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. Understood for
future rounds -- the trailer names the directing session, not the implementing
model. The commit body also gained a paragraph on the HLL registry fix.

## Files changed in this round

- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/HLLConfig.kt` (modified, new field)
- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/GlobalContext.kt` (modified: the
  stamp, the init hoist, `findHLLConfig`)
- `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlot.kt` (modified: `PGuardHll`)
- `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlotCodec.kt` (modified: both HLL sides)
- `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchSlotCodecTest.kt` (modified)

## Concerns after this round

1. **`findHLLConfig` is public API on `GlobalContext`.** It is only called by
   the codec today. If a later task wants the same "resolve, do not create"
   behaviour elsewhere (a persisted `hllboxtype`, say), it is ready; nothing
   else changed about how `getHLLConfigFor` behaves for existing callers.
2. **The `compilerSide` stamp is set at creation only.** A config never moves
   registries (`useCompilee/CompilerHLLConfig` swap which map is current, they
   do not move entries), so the flag cannot go stale. Worth knowing if anyone
   ever adds a way to re-register a config under the other side.
3. Concerns 2-4 of the original report (the `Unpersistable` stack trace, enum
   ordinal stability, and `realise` trusting a recorded `PDescriptor`) are
   unchanged and still stand.
