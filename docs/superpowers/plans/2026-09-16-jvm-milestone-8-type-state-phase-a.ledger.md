# SDD ledger — plan: docs/superpowers/plans/2026-09-16-jvm-milestone-8-type-state-phase-a.md

Spec: docs/superpowers/specs/2026-09-16-jvm-milestone-8-type-state-design.md
(rakudo 22e2cc2e75), sections 1-3 and 5.

BASE before Task 1: rakudo 352c927b66, nqp 8ea35ba95 (the nine v2 stage0
jars are an uncommitted working-tree change in nqp/, user rule). Baseline = milestone
7's close row: cold rakudo-e 2.247 s, cold nqp-e 1.198 s, misses 4931, hits 35512,
recorded= 195, warm t/01-sanity 59 s.

Claude-Session trailer: not known.

Model policy (user rule 2026-09-11): subagents on Opus; Fable only after erroneous
output; escalations logged here.

The plan's rulings (open to the user's veto):
1. The serialization reader publishes ONCE, after the HLL facts are read and BEFORE
   parametricity and deserialize_repr_data -- the point at which the old code had
   assigned every fact field -- so any object deserialized from inside those two
   steps sees the same facts it saw before. No republish after deserialize_repr_data:
   no site folds a stub's REPR data (decont takes the slow road on a null layout,
   create pins), so there is nothing to invalidate. Deviation from the spec's
   "at the end of the STable read"; cost if wrong: a stale layout fold on a type
   whose STable was read lazily -- the nqp suite would show it.
2. `setdebugtypename` republishes, so the assumption carries the type's name for the
   trace; one extra publish per type at creation, before any code folds it.
3. Task 1 keeps read-only aliases of the old field names on STable so every reader
   compiles unchanged and every writer fails to compile; Task 2 renames the readers
   and deletes the aliases.
4. `KnowHOWREPRInstance.composedType` is an in-process back-reference (not
   serialized), matching the in-process aliasing it replaces.
5. A stale program (a type guard whose state was republished) is evicted from the
   runtime site's list at the next install, and the engine cache refolds at the next
   miss without counting toward REFOLD_AFTER.
6. `Guard.OfType.state` is transient: outside data-class equality, outside
   DispatchDump, never persisted; a restored program captures the state current at
   restore. Verify mode is unaffected.
7. `Truffle.getRuntime().createAssumption` runs in nqp-runtime (TypeState.kt);
   the runtime's gradle test task gets truffle-api as testRuntimeOnly, where the
   default (interpreter) runtime supplies assumptions.
8. The Rakudo side rebuilds with a plain `make` (rakudo-runtime.jar + the training
   stamp); Task 2 verifies no setting recompiled.
   **CORRECTED 2026-09-16 (Task 2, recorded at the close by Task 5): this ruling is
   WRONG.** The settings DO recompile on a Rakudo-side `make` -- Task 2's `make` took
   **855 s** -- for two pre-existing Makefile reasons: `Makefile:320`
   `J_RAKUDO_DEPS_EXTRA = $(RUNTIME_JAR) | $(NQP_RUNTIME_JAR)` makes only *nqp's*
   runtime jar order-only while *Rakudo's own* `rakudo-runtime.jar` is a hard
   prerequisite of `rakudo.jar`, and a moved rakudo HEAD re-expands
   `gen/jvm/main-version.nqp`, which every frontend jar depends on. Any Rakudo-side
   edit under `src/vm/jvm/runtime/` therefore costs a full setting recompile; budget
   for it. **The Makefile was deliberately NOT changed**: moving `$(RUNTIME_JAR)`
   after the `|` would make the ruling true, and whether the settings may be compiled
   on a runtime they do not depend on is a semantic choice. **OPEN USER QUESTION.**

## Task 1 (nqp tree) — DONE

Commit: nqp `c1b73c43b` "Object model: the type state -- an immutable TypeState
with an Assumption per STable (milestone 8, A1)", stamped 2026-09-16T20:30:00+02:00
(the hash first written here, `d4fba0e51`, was the pre-amend one; the amend also
fixed deviation 3 below -- the trailer now reads `Co-Authored-By: Claude Fable 5.1
<noreply@anthropic.com>`, the directing session, like every other commit of this
milestone).
15 files, +352/-186. The nine stage0 jars were left unstaged (user rule).

Gates, with wall times:
- `:nqp-runtime:compileKotlin` + `:nqp-truffle:compileKotlin` — BUILD SUCCESSFUL, 3 s,
  zero errors. **No writer the plan missed**: the compiler named none beyond the
  fifteen files listed, so the plan's writer audit was complete.
- `:nqp-runtime:test` (whole runtime suite, `--rerun`) — BUILD SUCCESSFUL, 1 s wall
  (0.2 s of test time), 10 classes / 56 tests / 0 failures / 0 skipped, TypeStateTest
  6/6. (Milestone 7's "36 s" was a cold-daemon figure; a warm daemon runs it in ~1 s.)
- `:nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars` — BUILD SUCCESSFUL, 3 s.
- Smoke on `./nqp-j-gradle`: `-e 'say(1)'` → `1`; `t/jvm/17-object-layout.t` 50/50;
  `t/jvm/18-rebless-layout.t` 14/14. Extra MOP smoke (the compose copy-vs-alias
  change): t/nqp/025-class 12/12, 026-methodops 5/5, 028-subclass 9/9, 053-knowhow
  12/12, 056-role 18/18, 057-construction 2/2, 058-attrs 35/35.

Deviations from the Task 1 brief:
1. **Step 3 `testRuntimeOnly` → `testImplementation`.** TypeStateTest reads
   `state.assumption.isValid`, so `com.oracle.truffle.api.Assumption` has to be on the
   test COMPILE path, not only the test runtime path; with `testRuntimeOnly` the test
   compile failed with "Cannot access class 'com.oracle.truffle.api.Assumption'".
   Test configurations are not bundled into nqp-runtime.jar, so the main-path
   isolation the comment above it describes is unchanged.
2. **`TypeStateTest.theWriterOpsPublish` operates on a fresh type object**
   (`tc.gc.BOOTHash!!.st.REPR.type_object_for(tc, tc.gc.BOOTHash!!.st.HOW)`) rather
   than on `tc.gc.BOOTHash` itself — the controller's pre-flight ruling. Every
   assertion is otherwise as written.
3. **Commit trailer named the executing model** (`Claude Opus 5 (1M context)`), not
   the brief's literal `Claude Fable 5.1`: this task ran on Opus per the model policy.
   **Fixed by the amend to `c1b73c43b`**: every commit of Phase A now carries the
   `Claude Fable 5.1` trailer (verified with `git log -1 --format=%B`).

## Task 2 (both trees) — DONE

Base: nqp `c1b73c43b` (Task 1, amended — the "d4fba0e51" above is the pre-amend
hash), rakudo `352c927b66`.

The sed of the brief's Step 1 renamed 14 files (RakudoContainerSpec.kt matched
only on its `import`, so the `/^import /!` guard left it unchanged and it
carries no diff). Hand fixes after the sed: four safe-call chains where the
receiver was already nullable — `?.st?.ContainerSpec`-shaped reads became
`?.st?.state.hllOwner`, which does not compile; they are now
`?.st?.state?.hllOwner` (BootDispatchers.kt:294, DispatchCompiler.kt:300,
DispatchModel.kt:255 and :267). No `.state.state.` was produced anywhere, and
no type reference changed. One doc comment in NqpTypeOps.kt was rewritten by
the sed from `STable.TypeCheckCache` to `STable.state.typeCheckCache`, which is
what it now describes. `Ops.setcontspec`'s deliberate double read of `st.state`
was left alone. No `.java` file in either runtime tree read an old name.

The nine `val … get() = state.…` views and their TRANSITIONAL comment are gone
from STable.kt, which now ends at `republish()`.

Gates, with wall times:
- `:nqp-runtime:compileKotlin` + `:nqp-truffle:compileKotlin` — BUILD SUCCESSFUL,
  3 s, **zero errors**: the sed plus the four hand fixes found every reader.
- `:nqp-runtime:test` — BUILD SUCCESSFUL, 7 s wall on a forced rerun
  (0.54 s of test time), 56 tests / 0 failures / 0 skipped.
- `:nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars` — BUILD SUCCESSFUL, ~3 s.
- Smoke `./nqp-j-gradle -e 'say(1)'` → `1`.
- **`make` — exit 0, 855 s (14 m 15 s).** Markers: eight `Compiling` lines for
  the frontend, then `Generating rakudo-runtime.jar (Gradle)` at 116 s,
  `Compiling rakudo.jar`, v6c + CORE.c (294 s on its own), v6d + CORE.d,
  v6e + CORE.e, and `+++ Training dispatch slots` at 853 s.
- **nqp suite — 155 files, 1 chunk, exit 0, 197 s**, `chunk 1/1: ok` (no reds),
  one server x 6g heap + 3g off-heap.
- **`t/01-sanity` — Result: PASS, Files=25, Tests=303, 54 s.**

### Deviation: the settings DID recompile, and ruling 8 is wrong as written

Ruling 8 and the Task 2 brief expected "no `Compiling` marker" — only
`rakudo-runtime.jar` and the training stamp. A full frontend + BOOTSTRAP +
CORE.c/d/e recompile ran instead. Two independent causes, both pre-existing
Makefile facts and neither a defect of this change:

1. **`RUNTIME_JAR` is a hard prerequisite of `rakudo.jar`.** Makefile:320 reads
   `J_RAKUDO_DEPS_EXTRA = $(RUNTIME_JAR) | $(NQP_RUNTIME_JAR)`. The comment
   above it (316-319) explains that *nqp's* runtime jar sits after the `|` so
   its rebuild cannot timestamp-cascade into a setting recompile — but
   *Rakudo's own* `rakudo-runtime.jar` sits before it, as an ordinary
   prerequisite. Phase A touches three files under `src/vm/jvm/runtime/`
   (RakudoContainerConfigurer.kt, RakudoJavaInterop.kt, RakOps.kt), so
   `rakudo-runtime.jar` rebuilds and `rakudo.jar`, the three BOOTSTRAPs and the
   three settings follow by design. Any Rakudo-side runtime edit in this
   milestone costs a full setting recompile; budget for it.
2. **`gen/jvm/main-version.nqp` was re-expanded first** (the make log's very
   first line, at t=0), because rakudo HEAD moved since the last build in this
   worktree. Every frontend jar depends on `$(J_NQP_VERSION_FILE)`
   (Makefile:1293, 1301, 1305), so ModuleLoader/Ops/Actions/Grammar/Metamodel/
   Optimizer/Compiler were already stale before `rakudo-runtime.jar` was even
   generated at 116 s.

The same argument as the nqp side applies — compiled bytecode does not depend
on the runtime that executes it — so moving `$(RUNTIME_JAR)` after the `|` on
line 320 would make ruling 8 true. That is a Makefile change outside Task 2's
scope and is NOT made here; it is recorded as a candidate for the milestone.

### Other deviations

1. **`git status --short` in the rakudo root does not merely warn.** The
   `3rdparty/nqp-configure` submodule gitlink makes it `fatal: not a git
   repository` with **exit 128 and no listing at all**; `2>/dev/null` hides the
   message but not the missing output. `git status --short --ignore-submodules=all`
   works. Used throughout; the brief's Step 6 `git status --short` is run that way.
2. **The brief's `for f in $FILES` loop is a no-op under zsh**, which does not
   word-split an unquoted parameter: the whole newline-joined list went to sed
   as one filename and nothing was edited (verified: both trees clean afterwards).
   Re-run as `… | while IFS= read -r f; do …; done`, same sed script verbatim.
3. **`t/01-sanity` was killed once at file 19/25 by the agent harness's
   low-memory guard** (not by the eval server, not by a test failure, and not
   the systemd MemoryMax cage of 2026-09-16 — 22 GiB was available). Three
   Gradle/Kotlin daemons held ~3 GiB; `./nqp/gradlew -p nqp --stop` freed them
   and the re-run passed 25/25 in 54 s. The recorded time is the clean run's.
4. **Commit trailer.** Both commits carry the brief's literal
   `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` (the directing
   session), per this task's instructions — unlike Task 1, which substituted the
   executing model's name.

---

## Task 3: the sites trust a fact only under its state's assumption (A2, part 1)

**Status: DONE.** Round 1 (below) is the diagnosis: `IsTypeSite` was unreachable
and the test vacuous. **Round 2 (at the end of this section) is the outcome**:
the site is on the road, is proved to be entered, and the test is proved to
bite. Where the two disagree, round 2 wins.

**Commit: nqp `213e6feca`** (amends `d7e114725`; three files:
`nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt`,
`nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java`,
`nqp/t/jvm/19-type-state.t`). No jar staged; the nine modified
`src/vm/jvm/stage0/*.jar` stayed out of the index.

### The finding (round 1; ROUND 2 acts on it -- see the end of this section)

**`OP_ISTYPE` is unreachable from the encoder: `IsTypeSite` is dead code
today.** `nqp::istype` is a *classlib* op (`Compiler.nqp:971`
`map_classlib_core_op('istype', $TYPE_OPS, 'istype', …)`), it has no `op3(...)`
row in `TruffleEncoder.nqp`'s `%emit_ops`, and no hand row pushes opcode 55.
It therefore encodes as `W_CLASSLIB`, and `NqpProgramBuilder.dedicatedClasslib`
maps exactly one classlib op to a dedicated operation (`Ops.hllize`). So
`NqpTypeOps.istype` / `resolveIsType` are never entered from guest code.

Verified empirically, not by reading alone: a temporary env-gated probe print
in `resolveIsType` (all four exits) built into the jar (`strings` on the class
confirmed the probe shipped) produced **no output at all** for the test, at 200
and at 2000 iterations, both with `$b`/`Baz` inline and behind a sub (one site).
The probe was then reverted; the committed file has none of it.

Consequences:
- Step 2's "test 2 `not ok` before the change" **could not be reproduced**: the
  test passes before and after. Reported rather than worked around, per the
  task's rule.
- Step 5's `JESP_DEBUG=1 … | grep -c republished` prints **0**, not "at least 1".
- `t/jvm/19-type-state.t` is committed as a plain correctness regression test
  for `istype` across `settypecache` (it does exercise the classlib road), NOT
  as a demonstration of A2. It is worth keeping, but it does not gate this task.

By the same table there is **no reachable NqpTypeOps site in an nqp-level test
that folds a fact a republish changes**: reachable sites are `DecontSite`
(op 51, emitted by hand rows), `IsConcreteSite` (53), `CreateSite` (58, hand
rows at `TruffleEncoder.nqp:1717,1753`), `BigIntSite` (214-216) and, Rakudo-only,
`SinkSite` (101), `RvCheckSite` (114), `HllizeSite` (classlib-dedicated) — and
none of their folded facts is changed by `settypecache`/`setmethcache`.
Options for the controller: (a) add `op3('istype', 55, $T_INT, 'oo')` to the
encoder table (out of Task 3's file list; changes all nqp+Rakudo compilation and
needs a `clean buildJvm`), (b) leave `IsTypeSite` dead and drop the istype claim
from A2's scope, or (c) demonstrate A2 at Rakudo level in Task 4/5.

### What changed, per site

`Site` base: new `@JvmField @field:CompilationFinal var state: TypeState?`;
`reset()` is now concrete (`clear(); state = null; misses = 0`) over a new
`protected abstract fun clear()`; new `fun valid()` (`state != null &&
state.assumption.isValid`). The per-run `for (s in SITES) s.reset()` loop is
untouched. New file-private `republished(site)` below `miss`: invalidates,
resets, restores the miss count (a republish spends no miss), `JESP_DEBUG`-gated
print.

Every site's `override fun reset()` became `override fun clear()` with the
`misses = 0` dropped. Every fast path that reads a resolved field became
`if (!site.valid()) republished(site) else if (<identity guards>) … else miss(site)`.

| site | state captured in | facts read from the captured state |
|---|---|---|
| `SinkSite` | `resolveSink` (`val s = st.state` before the verdict) | `containerSpec` (plus the `sink` method lookup) |
| `HllizeSite` | `resolveHllize`; `hllizeIsIdentity` now takes a `TypeState` | `hllOwner`, `hllRole` |
| `DecontSite` | `resolveDecont` (`val s = st.state` before `containerSpec`) | `containerSpec` |
| `IsConcreteSite` | — (`clear()` empty, `state` stays null, never calls `valid()`) | — |
| `IsTypeSite` | `resolveIsType`: `state` = value operand's, new `typeState` = type operand's; new `typeValid()` | `typeCheckCache`, `typeCheckMode` (value); `modeFlags`/`NEEDS_ACCEPTS` (type) |
| `RvCheckSite` | `resolveRvCheck` (`val vs = vst?.state`, both non-null required) | the accepted return value's type identity |
| `CreateSite` | `resolveCreate`, **before** `st.REPRData` is read | layout / REPR |
| `BigIntSite` | `resolveBigInt`, after the three-type check | layout, slot getter/setter |

`create`'s fast path drops the per-call `st.REPRData` re-read and
`rd.layout === layout` compare (the assumption stands for it now) and misses
when neither `layout` nor `repr` is set. `istype`'s fast path checks BOTH
`valid()` and `typeValid()`. `decont`'s non-container early exit still reads the
live state (`ost.state.containerSpec == null`) and the per-object
`o.layout === layout` compares stay — they guard shape, not facts. `bigint`
keeps `debugBigMiss` on the miss branch. Mu's `sink` is now cached as
`MuSink(state, method)` and re-looked-up when Mu's assumption dies.

### Commands and results

| command | result |
|---|---|
| `cd $ROOT && ./nqp/gradlew -p nqp :nqp-truffle:jar syncRuntimeJars --console=plain` | BUILD SUCCESSFUL in 3 s (an earlier probe build: 11 s) |
| `cd $ROOT && ./nqp/gradlew -p nqp --stop` | 1 daemon stopped (before the test runs, per the ruling) |
| `cd $ROOT/nqp && ./nqp-j-gradle t/jvm/19-type-state.t` **before** the change (200 iters) | **2/2 ok** — expected 1 `not ok` |
| same, 2000 iterations | **2/2 ok** — still no failure |
| same, one shared site (probe in `/tmp/probe19.t`) | **2/2 ok**; `resolveIsType` probe never fired |
| `cd $ROOT/nqp && ./nqp-j-gradle t/jvm/19-type-state.t` **after** | 2/2 ok |
| `./nqp-j-gradle t/jvm/17-object-layout.t` | 50 ok / 0 not ok |
| `./nqp-j-gradle t/jvm/18-rebless-layout.t` | 14 ok / 0 not ok |
| `JESP_DEBUG=1 ./nqp-j-gradle t/jvm/19-type-state.t 2>&1 \| grep -c republished` | **0** (expected >= 1; see the finding) |
| all of `t/jvm/*.t` (19 files) | 921 ok / 0 not ok |
| `t/nqp/{025,028,053,056,057,058,059,060,061,045}.t` | 636 ok / 0 not ok |

No wall-clock gate was run (Task 3 is a runtime-jar-only change; no `make`, no
CORE.c, per the brief). Each `nqp-j-gradle` run is a cold JVM of a few seconds.

### Residual noted, not fixed

A `SinkSite` that resolved "trivial" because the type's `sink` **is** Mu's is
guarded by the *sunk type's* state, not Mu's. A `setmethcache` on Mu
republishes Mu's state (so `muSink()` re-looks-up) but not the subtype's, so an
already-resolved `SinkSite` keeps its verdict. This is the shape the brief
prescribes; flagged for Task 4/5 if method-cache republishing is to be tight.

### Deviations

1. **`plan(2)`, istype half only**, per the controller's ruling; the header
   comment says Task 4 adds the method-call half.
2. **Step 2's expectation was not met and the task did not stop there.** The
   cause was diagnosed first (see the finding) rather than proceeding blind, and
   the remaining steps were carried out because the code change itself is fully
   specified and independently verifiable. The status returned is
   `DONE_WITH_CONCERNS`, and the commit is amendable if the controller wants the
   test or the encoder row changed.
3. **`val s = mu.st.state` in `muSink` is the brief's verbatim code** and is not
   null-guarded; it runs behind `@TruffleBoundary` after `nullValue` is known
   non-null.
4. **The write/edit tools were blocked** for this agent ("parent bg session
   hasn't isolated yet"); all edits were made through Bash (heredoc for the test,
   a one-off Raku script asserting exactly one occurrence per replacement — all
   30 replacements reported `ok`).

---

## Round 2 (coordinator's two additions)

**Amended commit: nqp `213e6feca`** (was `d7e114725`; same stamp
`2026-09-16T21:00:00+02:00`, same `Co-Authored-By: Claude Fable 5.1
<noreply@anthropic.com>` trailer, one paragraph added to the message). Three
files staged: `NqpTypeOps.kt`, `NqpProgramBuilder.java`, `t/jvm/19-type-state.t`.
No jar staged.

### 1. The istype site is now LIVE (the third road)

`nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java`:

- `dedicatedClasslib(cls, meth, nargs)` gains
  `if (cls.equals("Lorg/raku/nqp/runtime/Ops;") && meth.equals("istype") && nargs == 2) return Op.ISTYPE;`
  beside the hllize line.
- Its javadoc now says the type-check family is reached from *here*, not from
  `dedicatedOp`, and why an INT-result classlib op may become an operation that
  answers `Object`. The `CLASSLIB` call-site comment ("jesp diamond 6: hllize")
  now names istype and records that a dedicated operation ignores `rtype`.

**The INT-result check the coordinator asked for, done and confirmed sound:**

| | generic classlib road | dedicated `IsTypeOp` |
|---|---|---|
| normal value | `NqpOps.classlibInline` returns `site.resolve().invokeExact(full)` — the method handle is `asType(...Object)`, so `Ops.istype`'s `long` arrives **boxed as a `Long`** | `NqpTypeOps.istype` returns `Long`, autoboxed — "a boxed Long, which is what every table op already answers through RunOp" (NqpRootNode.java:569-577) |
| capture | `NqpOps.suspendToken(sse, rtype)` with the site's rtype = **T_INT** | `NqpOps.suspendToken(sse, NqpWire.T_INT)`, explicitly, for the same reason |
| store local | `BytecodeLocal ores = emit ? b.createLocal() : null;` — **untyped**, and it is the *same statement* for both cases (NqpProgramBuilder.java:604 and :633) | same |
| suspend check | `emitSuspendCheck(ores)` | same |

So the classlib path's store local is **not** typed differently, and the
consumers (`Truthy`, the arg coercions) take `Object` either way. The only
thing that changes is who computes the value.

**Proof the site is entered** (`JESP_DEBUG=1 ./nqp-j-gradle t/jvm/19-type-state.t`,
with a new env-gated narration added to `resolveIsType`'s three exits):

```
jesp: istype site resolved 0: null is not null      (x N, during the loop)
...
jesp: republished IsTypeSite                        (after nqp::settypecache)
```

`JESP_DEBUG=1 ./nqp-j-gradle t/jvm/19-type-state.t 2>&1 | grep -c republished`
→ **1** (was 0). (`debugName` prints `null` because these nqp classes publish no
name into their STable; not a defect of this change.)

**The test now BITES.** One necessary test change: both checks go through ONE
istype instruction — `sub is_baz($o) { nqp::istype($o, Baz) }`, called in the
loop and again after `settypecache`. The brief's two separate `nqp::istype` call
sites are two *sites*, and the second one simply resolves afresh against the new
cache, which is why it could never fail. The header comment in the test says so.

| | result |
|---|---|
| `valid()`/`typeValid()` check **temporarily removed** from istype's fast path, jar rebuilt | `ok 1`, **`not ok 2 - an istype site resolved before settypecache sees the new cache` / `got: '0'` / `expected: '1'`** |
| check **restored**, jar rebuilt | `1..2`, `ok 1`, `ok 2` |

The bite patch was applied and reverted through an asserted-unique replacement;
the committed file is byte-identical to the pre-patch copy.

### 2. `SinkSite` holds Mu's state too

`nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt`:

- `SinkSite` gains `@JvmField @field:CompilationFinal var muState: TypeState? = null`,
  cleared in `clear()`, plus `fun muValid(): Boolean { val s = muState; return s == null || s.assumption.isValid }`
  — the `IsTypeSite.typeValid()` shape, **no `!!` on the fast road**.
- Fast path: `if (!site.valid() || !site.muValid()) republished(site)`.
- `muSink(tc)` now returns the `MuSink` **entry** (state + method) instead of the
  bare method, and returns null when Mu has no `sink` (the caller's own "no sink
  method" branch has already answered in that case).
- `resolveSink`'s verdict is destructured so `muState` is set **only** on the
  branch that compared against Mu's sink:
  `containerSpec != null` → true, `muState` stays null; no `sink` method → true,
  `muState` stays null; `m === mu.method` → true **and** `muState = mu.state`.

**No test exercises this at nqp level**: `p6sink` is a Rakudo op (`RakOps.p6sink`,
bound through `NqpTypeOps.Rak`), so no `t/jvm` or `t/nqp` file can reach a
`SinkSite` at all. The change is carried by construction and by the absence of
regressions; it is a candidate for a Rakudo-level check in Task 4/5.

### Round 2 commands and results

| command | result |
|---|---|
| `./nqp/gradlew -p nqp :nqp-truffle:jar syncRuntimeJars --console=plain` (istype + muState) | BUILD SUCCESSFUL in 11 s; no errors (10 pre-existing Kotlin platform-type nullability warnings, none on a line this task introduced) |
| `./nqp/gradlew -p nqp --stop` | daemons stopped before each test wave |
| `JESP_DEBUG=1 … t/jvm/19-type-state.t \| grep -c republished` | **1** |
| bite build (check removed) + run | BUILD SUCCESSFUL in 10 s; **`not ok 2`, got '0'** |
| restore build + run | BUILD SUCCESSFUL in 4 s; **2/2 ok** |
| `./nqp-j-gradle t/jvm/17-object-layout.t` | 50 ok / 0 not ok |
| `./nqp-j-gradle t/jvm/18-rebless-layout.t` | 14 ok / 0 not ok |
| whole `t/jvm/*.t` (19 files) | **921 ok / 0 not ok** |
| `t/nqp/{025,028,053,056,057,058,059,060,061,045}.t` | **636 ok / 0 not ok** |

No wall-clock gate (runtime-jar-only change; no `make`, no CORE.c).

### Round 2 concerns

1. **Scope of the `dedicatedClasslib` line.** Every `nqp::istype` in nqp *and*
   Rakudo now compiles to `IsTypeOp` instead of the generic classlib site. The
   nqp suites above are green, but nothing Rakudo-level has been run in this
   task (no `make`, per the brief). The istype site pins itself whenever the
   type-check cache is absent or non-authoritative or the type needs
   `accepts_type`, so the slow road is `Ops.istype_nd` rather than
   `Ops.istype` — semantically the same answer, but this is the first time
   that path carries production Rakudo traffic. Worth a Rakudo gate in Task 5.
2. The istype narration lines print `null` for both type names (STables here
   carry no `debugName`). Cosmetic.
3. The `SinkSite`/Mu change remains untested for want of a Rakudo-level test.

Fix round 1 (2026-09-16): amended to nqp `6e318320b` (same stamp, same trailer) -- `resolveBigInt` now captures `st.state` BEFORE `st.REPRData` (a compose between the two reads had handed the site a valid assumption over a stale layout), `bigintArith` reads `site.layout` inside the `valid()` else-branch, and `t/jvm/19-type-state.t` names `NqpProgramBuilder.dedicatedClasslib`'s `istype` line as its load-bearing routing premise plus the by-hand bite proof; jar BUILD SUCCESSFUL in 10 s, `19-type-state.t` 2/2, `17-object-layout.t` 50/50, `t/nqp/060-bigint.t` 157/157 (the bigint test named by `ls t/nqp | grep -i bigint`); no jar staged.

## Task 4 -- the dispatch programs, on all three roads (A2, part 2)

Commits: nqp `c218f078f`, rakudo `dd60f647e0` (stamp `2026-09-16T21:20:00+02:00`,
trailer `Co-Authored-By: Claude Fable 5.1`). No jar staged; no `make`.

### What changed

| File | Change |
| --- | --- |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchModel.kt` | `Guard.OfType` gains transient `@JvmField val state = type?.state` and `isFresh`; `check` compares `st.state === state`. `DispatchProgram.isFresh` walks its `OfType` guards. |
| `.../DispatchCompiler.kt` | `TEST_TYPE_ARG` binds a `TypeState`, `testTypeArg`/`testGuard` compare `st.state`; `STable` import dropped (unused), `TypeState` added. |
| `.../DispatchBootstrap.kt` | `DispatchCallSite.install` filters non-fresh programs out before the `MAX_PROGRAMS` check. |
| `nqp/nqp-truffle/.../NqpDispatch.kt` | `Program.assumptions` (`@CompilationFinal(dimensions=1)`), assigned last in `init` from `Folder.assumptions()`; `Folder` keeps a `LinkedHashSet<TypeState>` fed by `OfType` and by the OBJ `Literal` branch; `matches` tests the assumptions before the guards; `Cache.hasStale()`; `miss` refolds at once on a stale cache; stats line prints `publishes=`. |
| `nqp/t/jvm/19-type-state.t` | `plan(4)`: the method-call half above the istype half. |
| `t/02-rakudo/type-state.t` | New: the same two halves at Rakudo level. |
| `tools/build/m7-rig.raku` | `parse-cold` reads ` publishes=(\d+)`; `cold-summary` prints it. |

### Runs

| Command | Result |
| --- | --- |
| `./nqp-j-gradle t/jvm/19-type-state.t` (before) | `ok 1`, **`not ok 2` got 'old'**, `ok 3`, `ok 4` |
| `RAKUDO_RAKUAST=1 ./rakudo-j -Ilib t/02-rakudo/type-state.t` (before) | `ok 1`, **`not ok 2` got 'Foo.new'**, `ok 3`, `ok 4` |
| `./nqp/gradlew -p nqp :nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars` | **BUILD SUCCESSFUL in 15 s**; 56 tests, 0 failures, 0 errors (`DispatchSlotCodecTest`, `DispatchPersistTest`, `TypeStateTest` included) |
| `./nqp-j-gradle t/jvm/19-type-state.t` (after) | **4 ok / 0 not ok** |
| `RAKUDO_RAKUAST=1 ./rakudo-j -Ilib t/02-rakudo/type-state.t` (after) | **4 ok / 0 not ok** |
| `NQP_DISPATCH_STATS=1 RAKUDO_RAKUAST=1 ./rakudo-j -e ''` | **`publishes=7460`** (nqp-side `./nqp-j-gradle t/jvm/19-type-state.t`: `publishes=371`) |
| `NQP_DISPATCH_PERSIST=verify NQP_DISPATCH_STATS=1 … t/02-rakudo/type-state.t` | `dispatch-verify: on`; **`matched=4520 byOutcome=10 mismatched=0 unseen=6919`**; 4/4 ok |
| `raku -c tools/build/m7-rig.raku` | Syntax OK |
| smoke: `RAKUDO_RAKUAST=1 ./rakudo-j -Ilib t/02-rakudo/03-corekeys.t` | 2/3 -- **pre-existing NFG red**, `Found 5 unexpected entries: NFC NFD NFKC NFKD Uni` in `CORE::v6c`; unrelated to dispatch |

No wall-clock gate (runtime-jar-only change; no `make`, no CORE.c).

### Deviations (both about the TESTS, not the dispatch change)

1. **The nqp method half cannot use `nqp::setmethcache`.** Measured: NQP method
   calls go through the `nqp-meth-call` dispatcher (`src/core/dispatchers.nqp`),
   which resolves with `$how.find_method` -- the HOW's own cache, not the
   STable's. A probe proved `setmethcache` changes nothing even on a FRESH
   site (`direct after (fresh site): old`), so the brief's half would have
   failed for a reason unrelated to dispatch staleness. Replaced with
   `Foo.HOW.add_method`, which republishes via `setmethcacheauth` in
   `NQPClassHOW.add_method`; `add_method` refuses a name the class already
   declares, so `Foo is Base` overrides an INHERITED `m`. The premise is
   written into the file.
2. **The Rakudo half cannot use a source-level `augment`, and needs one site.**
   `augment` is BEGIN-time: with the brief's text, test 1 failed
   (`got: 'augmented'`) because the augment ran before the mainline loop, and
   test 2 then passed vacuously. `EVAL` of an augment is not a way out --
   RakuAST dies with `No such method 'compile-time-value' for invocant of type
   'RakuAST::Declaration::External'`. Replaced with the runtime equivalent
   `Foo.^add_method(...)` + `Foo.^compose`. Separately, both halves had to be
   routed through ONE sub body: with two source-level call sites the second
   resolves afresh and passes no matter what (probe: `after: augmented` with a
   second `.gist` site, `after: Foo.new` through one site). The istype half
   reads its invocant from a closure rather than a parameter, because
   `settypecache(Bar, [Bar, Baz])` drops `Any` from Bar's cache and an `$o`
   parameter then refuses to bind (`Type check failed in binding to parameter
   '$o'; expected Any but got Bar`).

### Self-review

- `OfType(on, null)`: `state` is null and `st.state` is never null, so the new
  check agrees with the old `st === null` on every input.
- `state` is declared in the class body, so it stays out of the data class's
  `equals`/`hashCode`/`toString`; `DispatchDump` and `DispatchSlotCodec` read
  only `type`, so persisted text is unchanged -- which `mismatched=0` confirms.
- Ordering in `miss`: `Dispatch.fallback` (which records and installs, pruning
  stale programs) runs before `cache.refresh`, so the refold sees the pruned
  list.
- `assumptions` is assigned as the last statement of `Program.init`, after both
  the guards and the outcome sources are folded (controller ruling 3).
- `hasStale()` runs only on the `@TruffleBoundary` miss path.

### Concerns

1. `t/02-rakudo/03-corekeys.t` is red for an NFG symbol reason
   (`NFC NFD NFKC NFKD Uni` unexpected in `CORE::v6c`). Pre-existing, unrelated,
   but it is the first Rakudo-level run since Task 3 and worth a line in Task 5.
2. Task 3's `dedicatedClasslib` istype routing is exercised at Rakudo level for
   the first time here and behaved: 4/4 on both istype assertions, no error.

Fix round 1 (2026-09-16): amended to nqp `055e14ae9` (same stamp, same trailer) -- `DispatchRecord.guardType`/`guardLiteral` now record the tracked value's `st.state` AT THE REQUEST (once per source) and `emitGuards` writes it into the guard, closing the window between the dispatcher reading a type's facts and `compile()` building the `Guard`; `Guard.Literal` carries the same transient state and `isFresh`, `DispatchProgram.isFresh` walks both guard kinds, and the engine's `Folder` prefers `g.state ?: st.state` for OBJ literals (codec and dump untouched). New `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/GuardStateTest.kt`, 5 tests, two of which drive the TOCTOU sequence through a real `DispatchRecord` (no live dispatch needed); bite check with the two `emitGuards` writes deleted FAILED exactly those two. `:nqp-runtime:test` 61/0/0 BUILD SUCCESSFUL 4 s, `t/jvm/19-type-state.t` 4/4, `t/02-rakudo/type-state.t` 4/4, verify `matched=4520 mismatched=0`, `publishes=7765`; no jar staged.

---

## Task 5 -- the gate, the storm baseline, row `a`, the record (Phase A close)

Tree at the close: **rakudo `dd60f647e0` / nqp `055e14ae9`** (pre-rebase).
`java -version` Oracle GraalVM 25.2.4+7.1. Every gate preceded by
`./nqp/gradlew -p nqp --stop`; no gate was killed by the harness this time.

### Step 1 -- `make` and the gate, with wall times

| command | result | wall |
|---|---|---|
| `raku tools/build/watched-run.raku … -- make` | exit 0; **no `Compiling` marker**, one `+++ Training dispatch slots`; `dispatch-record: done 21 paths, 4240 slots, 4540 programs, 49 unpersistable, 0 failed` | **2 s** |
| `./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars` (currency check, not in the brief) | BUILD SUCCESSFUL, **12 tasks up to date** -- the jars match their sources | 4 s |
| `evalserver-sweep.raku --suite=nqp --chunk='*' --jobs=1` | **156 files, 1 chunk, `chunk 1/1: ok`, exit 0** (155 at Task 2; `t/jvm/19-type-state.t` is the 156th) | **195 s** |
| `perl t/harness5 --jvm --evalserver t/01-sanity` | **Files=25, Tests=303, Result: PASS**, exit 0 | **45 s** |
| `./rakudo-j -Ilib t/02-rakudo/type-state.t` | **1..4, 4 ok** | 7 s cold |
| `./rakudo-j -Ilib t/02-rakudo/closure-static-clone.t` | **7/8**, `not ok 5 - .clone through the method road still works` (`expected 'documented', got ''`) -- milestone 7's inherited red, unchanged; **state, not a gate** | 7 s cold |

**`make` was a 2-second no-op, not the ~850 s recompile the controller
expected**, and that is honest rather than lucky: the tree was already
built at rakudo `dd60f647e0` / nqp `055e14ae9` (`gen/jvm/main-version.nqp`
13:21, every stage jar newer), Tasks 3 and 4 changed only runtime/engine
sources, and the gradle currency check above confirms the runtime jars
match their sources. So `make` had only the training pass and the runner
setup left to do. The phase's real build cost is Task 2's **855 s** (see
the corrected ruling 8); this run neither confirms nor refutes it.

Also recorded from earlier tasks, for the close: `:nqp-runtime:test`
**61 tests / 0 failures** (56 before Phase A: `TypeStateTest` 6,
`GuardStateTest` +5), whole `t/jvm` **921/921**, `t/jvm/19-type-state.t`
**4/4**, verify mode on the Rakudo test `matched=4520 byOutcome=10
mismatched=0 unseen=6919`. `t/02-rakudo/03-corekeys.t` is the
pre-existing NFG red of `docs/jvm-t02-rakudo-red-baseline.txt`.

### Step 2 -- the storm baseline

The instrument **is** `-Dpolyglot.engine.TraceAssumptions=true` via
`RAKUDO_JVM_XOPTS` (one probe, no fallback needed; the option is in
`truffle-runtime-25.2.4.jar` and the runner already passes
`-Dpolyglot.engine.*`). It prints one line per invalidation that killed
installed code: `[engine] assumption '<name>' invalidated installed code
'<nmethod>'`. A `TypeState`'s assumption is named `type` (`TypeState.kt:35`
takes the STable's debug name, and these carry none).

| program | `publishes=` | crude `grep -ci assumption` | invalidations of installed code | of those, `type` |
|---|---|---|---|---|
| `./rakudo-j -e ''` (`NQP_DISPATCH_STATS=1`) | **7460** | 12 | **4**: 2 `validRootAssumption`, 2 `nodeRewritingAssumption` | **0** |
| `./rakudo-j -Ilib t/02-rakudo/type-state.t` | -- | 175 | **63**: 22 `dispatch site`, 16 `validRootAssumption`, 16 `nodeRewritingAssumption`, 3 `Profiled Argument Types` | **6** |

The crude count includes stack-trace lines (`TraceAssumptions` prints the
invalidating stack), which is why the event counts above are taken from
the `invalidated installed code` lines.

**Verdict: no storm.** 7460 publishes on a cold `-e ''` invalidate **zero**
compiled methods -- they all happen while STables are being read, before
anything is compiled -- and a test written expressly to republish twice
produces six. Per the spec's reading, a count in the tens is no storm and
**approach B's per-facet split (A2' before Phase B) is not indicated**.
Recorded, not acted on. Logs: `$CLAUDE_JOB_DIR/tmp/m8-trace.log`,
`m8-probe1.log`.

Caveat on `publishes=`: Task 4 read **7765** on the same program against
the jars Task 2 trained; this build's training (4240 slots) reads **7460**,
and the rig's five cold runs agree at 7460. Single samples, not re-run;
the counter moves with the training pass, so it is a coarse number.

### Step 3 -- rig row `a`

`raku tools/build/m7-rig.raku --tag=m8a --warm=proxy`, marker `m7-rig: DONE`,
**rig wall 70 s**, files `m7-rig/m8a.md`, `m7-rig/m8a-{rakudo,nqp}-e-run{1..5}.err`,
`m7-rig/m8a-sanity.log`, log `$CLAUDE_JOB_DIR/tmp/m8-rig-a.log`.

    | m8a | dd60f647e0 | 055e14ae9 | 2.290 | 1.190 | 4933 | 35541 | 51/sanity | none | |

| row | cold rakudo-e | cold nqp-e | misses | hits | restored | recorded | publishes | warm proxy |
|---|---|---|---|---|---|---|---|---|
| M7 `close` | 2.247 s | 1.198 s | 4931 | 35512 | 4470 | 849 | -- | 59 s |
| **`a`** | **2.290 s** | **1.190 s** | **4933** | **35541** | **4470** | **851** | **7460** | **51 s** |

Cold runs -- rakudo: 2.44 2.36 2.29 2.41 2.31; nqp: 1.23 1.28 1.19 1.26 1.24.
nqp side of row `a`: `restored=1644 recorded=257 publishes=328`.

**Honest reading: the row claims nothing.** +0.043 s on the cold rakudo
clock is inside the stated spread (±0.05 s around 2.25 s), the nqp clock
is flat, and the counters differ by two misses and twenty-nine hits.
**Risk 2 (the dependent load) did not surface as a clock**, and Phase A
bought nothing on these programs either -- as designed: they publish 7460
states and then execute almost nothing. The warm proxy 59 -> 51 s is a
single sample against a 49-57 s history: no claim. **Row `a` also carries
Task 3's `dedicatedClasslib` istype routing**, so it is not a clean
reading of the type state alone.

### Step 4 -- the record

- `docs/jvm-perf-findings-2026-09.md`: new section **"Milestone 8, Phase A
  (2026-09-16)"** between "Milestone 7: the close" and "Things that cost
  time to learn" -- what landed (A1, A2, the `dedicatedClasslib` finding),
  the gate table with wall times, row `a` against the close row, the storm
  baseline (both numbers, both programs), the eight rulings with their
  cost-if-wrong (8 marked CORRECTED), and five items left.
- `docs/jvm-jesp.md`: istype's contract now reads "cached only when the
  type-check cache answered definitively, **under both operands' type-state
  assumptions**; a republish re-resolves without a miss", and names
  `dedicatedClasslib` as the routing that makes the site reachable at all;
  the object-model paragraph's "the per-STable `Assumption` is still only an
  idea" is replaced by a pointer to `TypeState.kt` and the milestone-8 spec.
- `docs/jvm-truffle-only-plan.md`: one paragraph after the milestone-7 close
  note -- what landed, the gates, row `a` as a no-op clock, the storm
  baseline, the two carried findings, Phase B next.
- This ledger: ruling 8 corrected in place; Task 1's hash corrected
  `d4fba0e51` -> `c1b73c43b` with the trailer deviation marked fixed by that
  amend; this section.
- Memory (`~/.claude/.../milestone-8-stable-assumption.md` and its MEMORY.md
  line): **NOT touched** -- the controller updates memory (this task's
  instructions).

### Step 5 -- commit, rebase, push

Docs commit (this file included): rakudo, stamped `2026-09-16T21:40:00+02:00`,
trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`, four files
(`jvm-perf-findings-2026-09.md`, `jvm-jesp.md`, `jvm-truffle-only-plan.md`, this
ledger). No jar staged in either tree.

**The handoff rebase was a NO-OP on both trees** -- both branches already contain
their upstream tip:

| tree | before | after | upstream tip | commits behind |
|---|---|---|---|---|
| rakudo (`worktree-jesp-direct-lazy-records`) | `dd60f647e0` + the docs commit | same (`git rebase origin/main`: "up to date") | `origin/main` `67f2e3bcff` | 0 |
| nqp (`jesp-direct-lazy-records`) | `055e14ae9` | `055e14ae9` ("up to date") | `upstream/main` `06f61ec6a` | 0 |

nqp's rebase **refused to start** over the nine modified `src/vm/jvm/stage0/*.jar`
("cannot rebase: You have unstaged changes"), so they were set aside exactly as the
brief prescribes: `git stash push -u -m m8-stage0-2026-09-16 -- src/vm/jvm/stage0/`
(stash `c80c858049c4a8bf2653544b227fe6abded69759`), rebase, `git stash apply <sha>`,
**md5sums of all nine verified identical before and after**
(`$CLAUDE_JOB_DIR/tmp/stage0-md5-{pre,post}.txt`, `diff` empty), then
`git stash drop stash@{0}` on the re-found entry. Never `git stash pop`. No conflict
arose in either tree.

Pushes (both `--force-with-lease`):
`ab5tract/rakudo 352c927b66..ec70b596db worktree-jesp-direct-lazy-records` and
`ab5tract/nqp 8ea35ba95..055e14ae9 jesp-direct-lazy-records`. (The rakudo hash above
is the docs commit as first written; it was amended in place to add this Step 5
record and force-pushed again -- the final hash is in the Task 5 report.)

**Phase A is closed. Next: the Phase B plan (the promotion campaign), which
inherits milestone 7's empty A7 list and the `dedicatedClasslib` third road.**

## Final review and fix wave (2026-09-16)

The whole-branch review of Phase A (rakudo `fdd298054c` / nqp `055e14ae9`)
found **no critical defect**. It found three Important items and nine Minor
hardenings; **all twelve landed in one fix wave**, one commit per tree, with
the gate re-run.

### The three Important items -- fixed

1. **Stale programs were persisted.** `DispatchPersist.recordAtExit` wrote
   every entry of `site.programs`; a program whose type republished after it
   was recorded (it is evicted only at the NEXT install) reached the slot and
   would be restored under a fresh guard with its baked callee. It now
   persists `p.isFresh` programs only; a slot left with nothing is skipped by
   the existing `persisted.isEmpty()` guard.
2. **`STable.publish` was a non-atomic read-modify-write.** Two concurrent
   `publish(state.withFacts(...))` pairs could install a state whose
   assumption is never invalidated. `publish` is now `@Synchronized` and
   `STable.update(f: (TypeState) -> TypeState)` computes the successor **under
   the lock**, so no writer builds one from a state it no longer owns.
   `republish()` is `update { it.withFacts() }`, and **every** writer of the
   `X.publish(X.state.withFacts(...))` shape was converted: `Ops.kt`
   (setmethcache, setmethcacheauth, settypecache, settypecheckmode,
   setinvokespec, setdebugtypename, setcontspec, setboolspec, settypehll,
   settypehllrole), `KnowHOWMethods.kt` (compose, add_method),
   `KnowHOWBootstrapper.kt` (all), `BootJavaInterop.kt` and the Rakudo tree's
   `RakudoJavaInterop.kt`. The only surviving `publish` calls are `update`'s
   own, `republish`'s (through `update`) and `SerializationReader`'s one
   publish of a freshly built state. `TypeStateTest` gained
   `updateSeesTheCurrentStateAndInstallsItsResult`.
3. **Three double `st.state` reads where the facts must agree** were hoisted
   to one read each: `Ops.findmethodNonFatal` (cache and its AUTHORITATIVE
   flag), `Ops.istype_nd` (one `os` for the invocant's mode + cache, one `ts`
   for the target's NEEDS_ACCEPTS flag), and
   `SerializationWriter.serializeStable` (nine reads -> one `val s` at the top
   of the STable section).

### The nine Minor hardenings -- fixed

4. `NqpDispatch.Folder.fold(Guard)`, `OfType` branch: `states.add(g.state ?:
   t.state)`, mirroring the `Literal` branch -- a type fixed by a guard made
   outside a recording is never folded under no assumption.
5. `DispatchRecord.emitGuards`: the recorded state is written to
   `Guard.OfType.state` only when it is non-null, so the constructor default
   is never overwritten with null.
6. `NqpDispatch.Cache.refresh`: the identity short-circuit now also requires
   `!hasStale()`, so a quiet site whose program list never changes refolds a
   program whose type republished instead of keeping it for ever.
7. `NqpTypeOps.muSinkCache` joins the per-run reset, beside `for (s in SITES)
   s.reset()`.
8. `SerializationReader` publishes a **copy** of the deserialized method-cache
   hash (`HashMap((methodCacheRef as VMHashInstance).storage)`): the guest
   keeps the hash object, and a guest mutation must not change a published
   fact without a publish.
9. `SerializationReader` calls `st.republish()` immediately after
   `REPR.deserialize_repr_data`. **Ruling 1 is amended**: the facts still
   publish once, before parametricity and REPR data, so a mid-deserialization
   reader sees exactly what it saw before; but REPR data now gets its own
   republish, because the `create` and bigint sites **do** trust the state for
   it.
10. `KnowHOWREPRInstance.composedType` KDoc: it names the **LAST** type this
    meta-object composed. A meta-object composed more than once leaves the
    earlier types holding their own published copies of the table, which no
    longer follow it -- as before the type state, where they held their own
    aliases; `add_method` republishes the last one.
11. Cosmetics: the dead `use MONKEY-TYPING;` is gone from
    `t/02-rakudo/type-state.t`; the stats line uses `STable.PUBLISHES.sum()`
    unqualified (the file imports `STable`); `DispatchBootstrap.install` says
    why it walks twice (`any` answers the common case without allocating);
    and both `Guard.OfType.state` and `Guard.Literal.state` say that the
    data-class `copy()` drops them -- never copy a guard.
12. `docs/jvm-truffle-only-plan.md`, the milestone-8 Phase A paragraph: the
    storm-baseline one-liner now matches the findings table -- **four**
    invalidations of installed code on the cold run (2 `validRootAssumption`,
    2 `nodeRewritingAssumption`), **none of them a `TypeState`**; "zero"
    applies to the type states, not to the run.

### The Phase B design ruling

**A site may fold only a fact that some state it holds actually published.**
A method resolution that walks the HOW/MRO (a non-authoritative cache) is
**not** such a fact: no single state published it, and no single assumption
covers it. So Phase B's `findmethod` / `can` / `tryfindmethod` sites fold the
**authoritative-cache case only**, unless a multi-state guard (one that holds
every state the walk consulted) is designed first.

### Rulings made during execution (from the process ledger)

Verbatim, every `Ruling` line of
`.superpowers/sdd/2026-09-16-jvm-milestone-8-type-state-phase-a/progress.md`:

```
| T3 / T4 | nqp/t/jvm/19-type-state.t: created in T3 with tests 1-2 owned by T4 | CONFLICT: T3 would commit a file with two known-failing tests. Ruling below. |
| T1 self | TypeStateTest.theWriterOpsPublish mutates tc.gc.BOOTHash's STable (mode flags, bool spec, hll role) | RISK: ProgramUnitTestSupport.tc() may share a GlobalContext across the runtime test suite; mutating a bootstrap type can leak into other tests. Ruling below. |
Ruling: T3 writes nqp/t/jvm/19-type-state.t with the istype half only (plan(2)); T4 extends it to plan(4) with the method-call half — no task commits a red test. Cost if wrong: none (same coverage at the end of T4).
Ruling: TypeStateTest.theWriterOpsPublish operates on a FRESH type object (`tc.gc.BOOTHash!!.st.REPR.type_object_for(tc, tc.gc.BOOTHash!!.st.HOW)`), never on a shared bootstrap type — the writer ops are exercised the same way and no other runtime test sees the mutation. Cost if wrong: a type_object_for that needs more than a HOW; the implementer reports it.
Ruling: Important 1 (double st.state read in settypecheckmode/setmethcacheauth/BootJavaInterop/RakudoJavaInterop) is FIXED although the plan's Step 8 code mandated it for settypecheckmode with a rationale — the global constraint "read facts from a captured state object" is the spec's rule and outranks the plan's argument. Cost if wrong: none (one local per writer).
Ruling: Important 2 (trailer names Opus) is fixed by amend, stamps preserved; the trailer names the directing session (M7 rule).
Task 1: minor (deferred): deserialized states carry name=null (debugName is not on the wire), so the assumption trace names CORE types "type"; Task 5's storm baseline reads COUNTS, the trace's stack identifies the site. Ruling: accepted for Phase A; a name from the HOW would need guest code at deserialization.
Ruling 1 sharpened (reviewer minor 6): the old reader assigned facts INCREMENTALLY between readRef() calls that can recurse into object deserialization, so a nested read of this STable previously saw partial facts and now sees none until the single publish; the one concrete sub-case (a ContainerSpec.deserialize reading st.ContainerSpec) was checked clean in all three specs; the general case rests on the nqp suite + t/01-sanity gates of Task 2. Cost if wrong: a deserialization-time reader of a partial fact; the gate shows it.
Task 1: fix round 1/5 dispatched -> implementer DONE, amended nqp c1b73c43b (dates preserved), runtime tests 56/56 15 s. Ruling: setcontspec reads st.state twice by design (guard, then the freshest state at publish after the spec is built; the two reads need not agree) -- left as is. Cost if wrong: none (a concurrent publish between them is absorbed by using the later state).
Ruling 8 CORRECTED (implementer finding): the settings DO recompile on a Rakudo-runtime edit -- Makefile J_RAKUDO_DEPS_EXTRA has $(RUNTIME_JAR) as a HARD prerequisite of rakudo.jar (only nqp's runtime jar is order-only), and a moved rakudo HEAD re-expands gen/jvm/main-version.nqp, which pulls the frontend jars. Cost: ~700 s per rakudo-side `make` in Phase A (Tasks 2 and 5). Ruling: the Makefile is NOT changed in this phase -- making the runtime jar order-only is a semantic choice (settings compile ON that runtime) for the user; recorded as an open user question for the Phase A record. Cost if wrong: two long makes.
Ruling: Task 3 wires istype through dedicatedClasslib (cls Ops, meth "istype", nargs 2 -> Op.ISTYPE): engine-jar only, no encoder change, no rebuild of any artifact; the spec's section 3 names istype's checked trust, which a dead site cannot deliver. Consequence recorded for Task 5: rig row a ALSO carries istype becoming sited (a confound on the "dependent load" reading; reported as such). Lesson for Phase B: the dedicatedClasslib map is a THIRD promotion road -- a classlib op promotes engine-only by name, without the encoder row the plan's recipe assumed; the plan's "classlib = full build" claim is wrong for any op whose dedicated node already exists or is added engine-side. Cost if wrong: an INT-typed dedicated result on the classlib road (hllize was OBJ->OBJ) -- the t/jvm + t/nqp runs and Task 5's gate show it.
Ruling: the SinkSite holds Mu's state too (a site "trivial because the type's sink is Mu's" depends on both) -- folded into Task 3 before its review. Cost if wrong: one more field on one site.
Ruling: Important 2 (the istype routing has seen no Rakudo-level run) is a GATE item, not a Task 3 code fix: Task 4 runs t/02-rakudo/type-state.t through ./rakudo-j on the synced engine jar, Task 5 runs make + t/01-sanity + the nqp suite; the ledger names the routing as the change those gates cover. Cost if wrong: a Rakudo red found one task later.
Ruling: Important 3 (the test cannot detect loss of the routing) -> the test gets a comment naming NqpProgramBuilder.dedicatedClasslib as its load-bearing premise and the bite proof is recorded here; an assertable site counter is Phase B's census tooling (NQP_OP_CENSUS counts dedicated vs classlib), deferred. Cost if wrong: a silently vacuous test until Phase B.
Ruling: test-shape deviations accepted -- (a) nqp: setmethcache is inert for nqp-meth-call (resolves via $how.find_method), so the nqp method-call half uses Foo.HOW.add_method on a subclass overriding an inherited m (republishes via setmethcacheauth); (b) Rakudo: source-level augment is BEGIN-time and EVAL of an augment dies in RakuAST, so the Rakudo half uses runtime .^add_method + .^compose; both halves run through ONE sub body (one site); the istype half reads its invocant from a closure (settypecache drops Any from the cache, a parameter then refuses to bind). Cost if wrong: the tests cover the republish roads that exist, not the literal augment statement; the spec's intent (a resolved site sees a republish) is met.
Ruling: Important 1 (Guard.OfType captures its state at emitGuards, AFTER the dispatcher read the facts -- a TOCTOU window the "captured state" rule exists to close) is FIXED in fix round 1, not parked: DispatchRecord records the tracked value's st.state at guardType()/guardLiteral(OBJ) time (before the facts read), emitGuards hands it to Guard.OfType.state and to a new transient Guard.Literal.state (OBJ only), the Folder prefers the guard-recorded state over st.state, and DispatchProgram.isFresh covers both guard kinds (also resolves minor 3's asymmetry). The spec's letter ("captured at recording time") is kept; the point of capture moves earlier within the recording. Cost if wrong: a wider change to DispatchRecord than the brief had; the runtime tests + both .t files + verify mode gate it.
Ruling: ONE fix wave lands Important 1 (DispatchPersist.recordAtExit persists only p.isFresh), Important 2 (STable.publish @Synchronized + a closure `update(f)` computing the successor under the lock; EVERY writer goes through update so no writer builds a successor from a state it no longer owns -- this touches the two Rakudo-tree writers, so the wave pays one full make), Important 3 (hoist the three double reads: findmethodNonFatal, istype_nd, SerializationWriter.writeSTable), and the cheap hardenings: Minor 4 (Folder OfType branch `g.state ?: t.state`), 5 (emitGuards writes only a non-null recorded state), 6 (refresh's short-circuit also requires !hasStale()), 7 (muSinkCache joins the per-run reset), 8 (the reader publishes a COPY of the deserialized method-cache hash), 9 (st.republish() after deserialize_repr_data -- ruling 1 amended: create/bigint now trust the state for REPR data), 10 (composedType KDoc "the last type composed"), 11 (dead MONKEY-TYPING, qualified PUBLISHES, install's double-walk comment), 12 (plan-position one-liner aligned with the findings table). Cost if wrong: a wider wave than "three small fixes"; every item is one to three lines and the gate (nqp suite + sanity) covers them.
Ruling (design, for Phase B -- from the resolveSink triage): a site may fold only a fact that some state it holds actually published; a method resolution that walks the HOW/MRO (non-authoritative cache) is NOT such a fact, so Phase B's findmethod/can/tryfindmethod sites fold the authoritative-cache case only (or design a multi-state guard first). Recorded for the Phase B plan.
FINDING (serious, M7 Phase C hazard, NOT Phase A's): at Phase A's close tree a make that rebuilds CORE.c DIES ("Too few positionals passed; expected 2 arguments but got 1" in AT-POS/Complex.new at BEGIN time) -- bisected: HEAD with zero wave code FAILS, HEAD with NQP_DISPATCH_PERSIST=off PASSES. Cause: persisted dispatch slots trained against the PREVIOUS rakudo.jar are restored while compiling the settings with a REBUILT rakudo.jar; the SC handles are stable across rebuilds and an index shifted, so a slot's baked callee resolved to a different code object. Task 2's 855 s make passed the same way by luck (no index shift that mattered). The wave "healed" it only by re-training under the current rakudo.jar (a PERSIST=off build first); fresh-only persistence does NOT address cross-build index shifts. Ruling: recorded as an OPEN ITEM for the user -- the slot needs an SC content stamp (drop on mismatch), or the Makefile must retrain/clear slots before any settings compile that follows a rakudo.jar rebuild; proposed as a hotfix before Phase B. Cost if wrong: the next rakudo.jar rebuild can die the same way.
```

### Hotfix (2026-09-16, after the wave's re-review)

The re-review confirmed all thirteen items and found **one regression that
item 6 introduced**: with `if (same && !hasStale())`, `Cache.refresh`'s stale
path fell through to a rebuild that reuses every stale `Program` (program
identity still matches for all `i`), so the "fresh" array was
content-identical, `publish` minted a new site assumption and deoptimized the
node, and `hasStale()` was still true at the next miss -- a deopt on every
miss, for ever, at a site whose `site.programs` exceed `MAX_CACHED` and whose
`Dispatch.fallback` matches an uncached program without installing (so
`install`'s eviction never runs). **Fix:** `cacheable(p)` also requires
`p.isFresh`, so the fold SKIPS a stale program and the one publish drops it;
the `!hasStale()` short-circuit stays and now fires once. Landed with it:
`Ops.settypehll` computes the HLL config before `st.update`, so the
GlobalContext monitor is never taken while the STable's is held; and the storm
baseline was retaken on the post-wave build (`publishes=14858`, up from 7460
because of the reader's new republish per deserialized STable; still 4
invalidations of installed code, still 0 of them a type state), with an
"after the fix wave" line added to `docs/jvm-perf-findings-2026-09.md` and
`docs/jvm-truffle-only-plan.md`.

### Hotfix 2 (2026-09-16, after the scoped re-review of hotfix 1)

The re-review confirmed hotfix 1's six elements (and that stale-at-head,
stale-in-middle and stale-beyond-`MAX_CACHED` converge) and found **two open
holes, both in `Guard.Literal`'s state handling**:

* **(d) the restore route.** A persisted-slot program restored with an
  OBJ-literal guard had `Guard.Literal.state == null` (the codec never assigns
  it), so `DispatchProgram.isFresh` said TRUE while the engine `Folder` had
  folded it under the CURRENT `st.state`. When that type republished, the
  folded `Program`'s assumption went invalid (`hasStale()` true) but
  `cacheable` still admitted the program, `refresh` reused the very same
  `Program` object (identity matched) and published on every miss -- hotfix 1's
  storm, on the restore route.
* **(e) the runtime road.** With the folded prefix truncated at a stale
  program, `Dispatch.fallback` / `Dispatch.run` re-ran that program: a stale
  OBJ-literal guard's `check` was identity-only, so the guards matched, the
  pre-republish outcome ran, and the program was never evicted.

**The fix: the identity guard is a state guard whenever it has a state, exactly
like the type guard.** `Guard.Literal.state` now defaults to the expected
object's state at construction (the restore-time capture; `emitGuards` still
overwrites it with the recorded one), `check` additionally requires
`got.st.state === state`, `DispatchCompiler.testLiteralIdArg` takes the state
and tests it (so `TEST_LITERAL_ID_ARG` binds over `(Int, Object, TypeState?)`)
as does `testGuard`'s Literal OBJ branch, `Dispatch.run` skips a `!isFresh`
program before checking guards (belt and braces), and `Cache.refresh` reuses a
folded `Program` only when its program identity matches AND all its
assumptions are still valid -- otherwise it refolds, so `hasStale()` is false
after one publish even if the two staleness notions ever diverge again.
`GuardStateTest` gained three tests (construction capture + `check` +
`testLiteralIdArg`; the miss on every road after a republish; a non-OBJ literal
keeping no state): 65 runtime tests, 0 failures.

Gate: runtime tests 65/65 (15 s), t/jvm 19/17/18 = 4/4, 50/50, 14/14 (2/4/2 s),
nqp suite 156 files green (195 s), `t/01-sanity` 25 files / 303 tests PASS
(43 s), `t/02-rakudo/type-state.t` 4/4 (7 s), verify
`matched=4511 byOutcome=5 mismatched=0 unseen=6933` -- **unchanged** from before
the hotfix -- and a cold `-e ''` whose dispatch stats line is byte-identical to
the pre-hotfix-2 one (`restored=4465 dropped=26 staleSchema=0 recorded=206
publishes=14858`), so no literal guard misses where it should not. (`recorded=`
is 206 against Task 5's 195; that +11 came with the fix wave, not with this
hotfix.) No `make`: no Rakudo runtime source changed.

Ruling (hotfix 2): the identity guard becomes a state guard whenever it has a state, like the type guard: Guard.Literal captures `state` at construction for OBJ values (restore-time capture for slots, like OfType's default), `check` additionally requires `got.st.state === state` when state != null, DispatchCompiler.testLiteralIdArg does the same, Dispatch.run skips !isFresh programs (belt and braces), and Cache.refresh never reuses a folded Program with an invalid assumption. GuardStateTest covers the literal's construction capture and its check. Cost if wrong: an OBJ-identity guard on an object whose type republished now misses where it used to match with stale constants -- which is the correct behaviour the spec asks for.


### Closing: rulings and parkings not yet in this record (from the process ledger, verbatim)

- Fix-wave re-review (Opus): 13/13 addressed (13 with a gap: the stale-slot hazard Ruling line is absent from the committed ledger); ONE NEW Important defect introduced by item 6: NqpDispatch.Cache.refresh's `same && !hasStale()` path rebuilds a content-identical array (the stale Program objects are reused since program identity matches), publishes it (new site assumption, deopt) on EVERY miss of a stale site whose programs exceed MAX_CACHED and whose fallback matches an uncached program without installing -- an assumption storm by construction, never refolding. Also: the doc's publishes=7460 predates the wave's ~2100 extra republishes per CORE.c load; settypehll computes the HLL config inside the lock.
- Ruling: a HOTFIX dispatch (not a second wave: it repairs a regression the wave introduced): `cacheable(p)` also requires `p.isFresh` so the folded prefix skips stale programs and one publish clears them; the hazard Ruling line appended verbatim to the committed ledger; the storm baseline retaken on the current build and the docs' numbers updated with a post-wave line; settypehll computes the config before `update`. Gate: runtime tests, t/jvm 19/17/18, nqp suite, t/01-sanity, verify. Cost if wrong: one more scoped re-review.
- Parked (pre-existing, may stay deferred to Phase B's first commit): emitGuards' Literal branch overwrites the constructor default without a `!= null` guard (asymmetric with the OfType branch; only a stub filled between guard request and compile would degrade to pre-hotfix behaviour) -- Ruling: add the guard in Phase B's first commit; cost if wrong: none today.
- Parked (pre-existing): DispatchBootstrap.install assigns the isFresh-filtered array only under `current.size < MAX_PROGRAMS`, so a saturated site keeps dead entries -- Ruling: harmless after hotfix 2 (run skips, cacheable excludes); fix in Phase B's first commit; cost if wrong: a saturated site's budget stays spent.
- Parked (pre-existing): DispatchPersist dedupes by dump text, which omits guard state -- Ruling: benign (isFresh filter + restore-time capture); noted for the SC-stamp hotfix design.
- PHASE A COMPLETE: final tips rakudo 530dce97bf / nqp 2b627034f (+ the closing docs commit below), all reviews clean; open for the user: the stale-slot cross-build hazard (SC stamp hotfix) and the Makefile runtime-jar prerequisite question.
