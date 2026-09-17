# Milestone 8: the type state (an Assumption per STable, and the promotion campaign)

Design, 2026-09-16. Approved in chat the same day, section by section.

Position: `docs/jvm-truffle-only-plan.md`, "Position (2026-09-13)" and
the milestone-7 close note below it. Milestone 7 (first execution)
closed 2026-09-16 on rakudo `6217a89e61` / nqp `a837bf1bb` (after the
close's rebase: rakudo `dad727461c` / nqp `8ea35ba95` on ab5tract; the
worktree tip at design time is rakudo `8fc895069c`). It left the empty
A7 promotion list and named this milestone as next
(`docs/jvm-perf-findings-2026-09.md`, "Milestone 7: the close"). The
idea has been on the list since 2026-09-07 ("cheap win = Assumption per
STable", `docs/jvm-jesp.md`, "Object model: the RakuObject layout") and
was made milestone 8 by user decision on 2026-09-14.

## Goal

Give compiled code type facts it can fold to constants, guarded by an
`Assumption` that a change to the type invalidates, and then use that
licence to move the hot ops that still cross the classlib and table
boundaries into sited nodes.

The survey of 2026-09-16 (this session, Opus subagent; file:line
references are as of rakudo `8fc895069c` / nqp `8ea35ba95`) establishes
the starting point:

- `STable` (`nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/STable.kt`)
  is a Kotlin class of plain mutable `@JvmField var`s: method cache,
  type-check cache, mode flags, container/boolification/invocation
  specs, HLL owner and role, REPR data, parametricity, v-table.
- Compiled code folds facts derived from it in three places: the
  diamond-3 sites in `nqp/nqp-truffle/.../NqpTypeOps.kt` (istype,
  p6typecheckrv, create, decont, p6sink, hllize, bigint arithmetic),
  the attribute sites in `NqpOps.java`, and the folded dispatch
  programs in `NqpDispatch.kt`, where a resolved method is baked in as
  a literal behind one STable identity compare
  (`BootDispatchers.langMethCall` records it from `st.MethodCache`
  once, at recording time).
- **Not one of those folds is invalidated when the type changes.** A
  `setmethcache`, `settypecache`, `setmethcacheauth`,
  `settypecheckmode`, `setboolspec`, `setcontspec`, `setinvokespec`,
  `settypehll`, a compose, or a P6opaque layout install leaves the
  constant stale and unguarded. The only reset is the per-eval-server
  run reset (`DispatchBootstrap.resetAll`).
- Two writers bypass STable field assignment entirely: KnowHOW's
  `add_method` mutates the very map `compose` published as the method
  cache (`KnowHOWMethods.kt:73` vs `:127`), and the P6opaque REPR fills
  `RakuObjectREPRData.layout` in place (`RakuObjectREPR.kt:39`).
- Three guard evaluators are live: the interpreted `Guard.check`
  (`DispatchModel.kt`), the MethodHandle chain the runtime's own
  dispatch sites compile once hot (`DispatchCompiler.kt`, still reached
  from `DispatchBootstrap.kt:122-132`), and the engine's folded replay
  (`NqpDispatch.kt`). A type guard is one STable identity compare on
  each.
- `Assumption` has exactly one precedent in the tree:
  `NqpDispatch.Cache.stable`, per dispatch instruction, with a
  publish-then-invalidate ordering (`NqpDispatch.kt:533-539`) and a
  documented refold-storm cost (`REFOLD_AFTER = 16`, `:640-652`).
- `findmethod`, `tryfindmethod`, `can`, `istrue`, `isfalse` and
  `iscont` have **no site at all**: they are table ops (ids 245, 254,
  89, 54, 175, 71) behind the `@TruffleBoundary` `run()` switch, and
  re-read the STable on every call.
- `nqp-runtime` already needs `truffle-api` at run time (the NFG string
  is a `TruffleString`); the dependency is `compileOnly` and the jar
  does not bundle it. Only the runtime's own gradle test task lacks it.

## Baselines (milestone 7's close row, same tree, not re-measured)

| clock | baseline |
|---|---|
| cold `rakudo-j -e 'say 1'`, best of 5 | 2.247 s |
| cold `nqp-j -e 'say(1)'` | 1.198 s |
| dispatch misses / hits, cold rakudo | 4931 / 35512 |
| `recorded=` on the trained `-e ''` | 195 |
| warm `t/01-sanity` proxy (one server) | 59 s |
| CORE.c compile inside `make` | 296 s |
| `make` from the top | 888 s |
| whole `t/` | NOT GATHERED (server OOM-killed by its own MemoryMax cage) |

## User decisions (2026-09-16)

1. **Milestone 8 is the Assumption per STable plus the full promotion
   campaign** (not the Assumption alone, not a bounded first batch):
   classlib and table ops are promoted to sited nodes until the census
   says nothing hot and foldable is left.
2. **Approach C, immutable type-state snapshots**, over A (one coarse
   Assumption as a field) and B (per-facet assumptions): the STable
   points at an immutable facts object that carries its own Assumption;
   a writer publishes a new one.
3. **Auxiliary engine caching is not in this milestone.** It needs a
   Native Image (the Truffle docs: "storing partial heaps on HotSpot is
   not supported"; Oracle GraalVM 25.2.4 ships it only as
   `truffle-enterprise-svm.jar` in the native-image builder; the
   2026-09-10 research and milestone 6's ruling 54 said the same). A
   Rakudo image needs NativeCall to stop building FFM downcall handles
   from run-time signatures (`NativeCallOps.kt:96`, `:1111`). **The
   Native Image road is milestone 9** with its own spec: the nqp image
   first, a fixed-signature libffi trampoline for NativeCall (about
   five downcall and one upcall signature, all known at image build
   time; the JVM keeps its direct handles), a launcher policy, then the
   engine cache measured on rakudo cold start. The user's question of
   whether a launcher can choose image or JVM by whether the program
   `use`s NativeCall is answered in the milestone-9 spec's inbox: the
   decision point is the hard part (pre-scan misses dependencies and
   `require`/EVAL; a mid-run switch is impossible; an early re-exec
   re-runs already-loaded module mainlines), which is why the
   trampoline is the road.
4. **Phases, as milestone 7 had them.** Phase A the type state and its
   consumers (runtime-jar rebuilds only), Phase B the campaign, then
   the close.
5. **Done criterion as milestone 7's**: every lever landed or struck,
   both clocks re-measured, no numeric gate; whole `t/` once at the
   close.
6. Standing rules carried over: forward-only, one compile per change,
   amend rather than wait (2026-09-08); per-lever rows = cold rows +
   warm `t/01-sanity`, no per-lever `t/02-rakudo`, a failed benchmark
   run is never re-run (2026-09-15); every gate reported with its wall
   time (2026-09-15); subagents on Opus, Fable only after erroneous
   output (2026-09-11); runtime performance outweighs compile time
   (2026-09-07); every debug print env-gated; Kotlin, never Java; no
   jar commits until told (2026-09-15); no `t/spec` until whole `t/`
   is under 30 minutes; the worktree is the source of truth and both
   trees rebase onto their upstream mains at every handoff.

7. **Revision 1 (2026-09-16, user decision): lazy-loading phase 2 is
   milestone 8's Phase C, after Phase B.** The user asked why lazy
   loading had bought so little cold start; the honest answer is that
   phase 1 (artifact v2, lazy bodies) was clock-neutral because the
   setting's load-time execution dominates and the serialization context
   is still read eagerly in full (28 MB raw for CORE.c), and that phase 2
   (SC demand deserialization, `docs/superpowers/specs/2026-09-13-jvm-lazy-unit-loading-design.md`)
   had been left unscheduled by milestone 7's close and by this spec's
   first revision. The lazy spec's estimate for phases 1 and 2 together
   was about 21 % of the cold run, none of it delivered by phase 1. Phase
   C's first task measures phase 2's own share on the current build
   (`NQP_UNIT_LOAD_STATS=1`) before anything is designed; its plan is
   brainstormed after Phase B closes. Sections 5 and 6 are amended below.

## Section 1: the type state

`STable` splits in two. What stays on it is identity and structure:
`REPR`, `HOW`, `WHAT`, `WHO`, `sc`, `debugName`, `REPRData`
(REPR-owned, section 2) and `parametricity` (a growing lookup table, a
cache rather than a fact). Everything compiled code folds moves into
one immutable Kotlin class, `TypeState`, reached through a single
`@Volatile var state` on the STable:

- `methodCache: Map<String, SixModelObject?>?` and
  `methodCacheAuthoritative: Boolean`;
- `typeCheckCache: Array<SixModelObject?>?` and `typeCheckMode: Int`
  (the two halves of today's `ModeFlags`; the serializer still reads
  and writes them as the one `modeFlags` int);
- `containerSpec`, `boolificationSpec`, `invocationSpec`, each
  constructed complete before the state is built;
- `hllOwner`, `hllRole`;
- `vTable` (serialized only, never read at run time; carried so the
  writer keeps working);
- `assumption: Assumption`, created with the state and named after the
  type's debug name, so the Truffle assumption trace names the type.

Two invariants. **A state object belongs to exactly one STable and is
never mutated.** **A state is replaced only through one method on
STable, `publish(next)`**, which stores the new state and then
invalidates the old state's assumption, in that order, the ordering
`NqpDispatch.Cache.publish` already uses: a thread that reads a valid
assumption and then the state always sees a state at least as new as
the assumption. A fresh STable, the serializer's stubs included, starts
with an empty state whose assumption is valid, so no reader checks for
"no state yet".

Consequence for consumers: `o.st.state === capturedState` implies
`o.st === capturedSt`, because states are never shared. A guard on
state identity subsumes today's type-identity guard, and in compiled
code it collapses to a type-identity compare plus an assumption that
folds away.

Cost: one dependent load on every runtime read that used to be a field
read (about 130 reads over some 20 files, REPR data excluded). That is
the price of approach C, and it is one load next to a hash lookup or an
array scan; the cold rows of row `a` are where it shows if it shows.

## Section 2: the writers, REPR data, and the serializer

**Writers become publishes.** Every place that assigns a fact field
today becomes `st.publish(st.state.withMethodCache(...))` and its siblings, one copy-with per
fact, and keeps its existing serialization write barrier
(`Ops.scwbSTable`). By tree: the set/publish ops in `Ops.kt`
(`setmethcache` :3239, `setmethcacheauth` :3250, `settypecache` :3261,
`settypecheckmode` :3271, `setinvokespec` :3293, `setcontspec` :4526,
`setboolspec` :4778, `settypehll` :7987 and the role setter :7993); the KnowHOW
bootstrap (`KnowHOWBootstrapper.kt:33-38`, `:102-105`, `:145-146`,
`:166-167`) and KnowHOW's `compose` (`KnowHOWMethods.kt:127-131`); the
two container configurers in nqp and the one in the rakudo runtime;
both Java interop bootstraps (`BootJavaInterop.kt:156-157`,
`RakudoJavaInterop.kt:823-824`); the serialization reader. About
fifteen sites, all mechanical.

**The two in-place writers are fixed, not hooked.** KnowHOW's
`compose` publishes a *copy* of its live methods map, so a later
`add_method` on the meta-object no longer edits a published cache;
`add_method` republishes for the types the meta-object composed only
when there are any, which after boot there are not, so that branch
exists for correctness and is expected never to fire. The container
spec is built complete before publish: the configurer constructs the
spec, the reader deserializes into it, and only then is the state
published. Boolification and invocation specs become
constructed-complete objects (today the reader assigns them and then
fills their fields, `SerializationReader.kt:540-568`).

**REPR data stays on the STable and republishes.** `REPRData` is
written by every REPR at type creation, compose and deserialize, and
the P6opaque layout is filled in place. It does not move: 91 reads
across 24 files are REPR internals reading their own data. Instead the
two roads that can change it after a type object exists republish the
state afterwards: `Ops.composetype` (after `REPR.compose` returns,
`Ops.kt:3234`) and the serialization reader (once, at the end of the
STable read). A republish with the same facts and a fresh assumption is
exactly what a folded layout needs: the assumption invalidates, the
site refolds and reads the new layout. The P6opaque `variants` map is a
cache of per-storage-class layouts for reblessed objects and does not
republish; sites keep their per-object layout compare for those, which
is a shape check, not a type-fact check.

**The serializer builds once.** `deserializeSTableInner` assembles all
facts into one state and publishes it once per STable instead of eleven
field writes; `SerializationWriter` reads from `st.state`. **The
on-disk format does not change**, so stage0 and every artifact stay as
they are.

**A counter and a trace.** Publishes are counted under the existing
dispatch stats knob (`NQP_DISPATCH_STATS`), and the split between "no
dependents" and "invalidated compiled code" is read from Truffle's
assumption trace (`engine.TraceAssumptions`) on a cold run, so the
storm question is answered by row `a`, and the fallback to per-facet
states is a measured decision.

## Section 3: the consumers, on all three guard roads

**Sites in `NqpTypeOps.kt`.** A site captures the STable and its state
at resolve time and holds the state's assumption in a
compilation-final field. The fast path is the identity compare it has
today plus `assumption.isValid()`, which partial evaluation folds to
nothing and the interpreter reads as one boolean. An invalid assumption
clears the site and re-resolves *without* counting toward the pin
threshold (`MAX_MISSES = 4`): a republish is not polymorphism. Two
concrete changes fall out: `create` drops its per-call REPR-data
re-read and layout compare (`NqpTypeOps.kt:643-644`; the captured
layout is valid as long as the assumption is), and `istype`'s
documented "trust the type-check cache once published" becomes a
checked trust. Sites keep their per-object layout compare (`decont`,
bigint, the attribute sites): that guards reblessed objects on a
variant storage class. The attribute sites (`NqpOps.AttrSite`) need
nothing else: a layout is immutable once installed and a reblessed
object carries its own. `NqpTypeOps.muSinkCache` (Mu's `sink`, cached
process-wide) is keyed under Mu's state assumption.

**The dispatch folder.** `Guard.OfType` gains a transient `state`
captured at recording time; the STable reference stays for the
persisted slot codec. On the interpreted road (`Guard.check`) and the
MethodHandle chain (`DispatchCompiler.testTypeArg`) the check becomes
state identity, which subsumes type identity. On the engine road the
folded `TypeChk` keeps the STable compare and the folded `Program`
carries a `@CompilationFinal(dimensions = 1)` array of the assumptions
of every STable it fixed, which the `Folder` already tracks in its
`known` map (`NqpDispatch.kt:396-424`); the method literal, the
`AttrSrc` getters and the `UnboxSrc` sources all derive from those
types. `replay` tests the assumptions first, exploded, so they cost
nothing compiled. A stale program is one whose guard can never match
again: the next `refresh` drops it from the site's list, and a refold
triggered this way does not count toward `REFOLD_AFTER`. This closes
the survey's method-literal hole: a method-cache republish after
recording now misses, re-records, and the persisted-miss counters show
it.

**Persisted slots (milestone 7 Phase C).** A restored program captures
the state current at restore time. If the type changes later the
program goes stale exactly like a recorded one; verify mode is
unaffected because it compares evaluated outcomes.

**Tests, written first.**
- nqp level (`nqp/t/jvm/`): republish a method cache and a type-check
  cache after a sited op and a dispatch program have resolved on the
  type; the next call observes the new fact.
- Rakudo level (`t/02-rakudo/`): hot-loop a method call, `augment` the
  class with a method that shadows the one called, and see the new
  method on the next call; the same through `istype` after a role is
  mixed in.
- The assumption-trace count on a cold `rakudo -e ''` recorded as the
  storm baseline in the ledger.

## Section 4: the promotion campaign

**Two roads, one census.** Ops reach the runtime over two boundaries:
table ops by id through `NqpOps.run()`, and classlib ops by name
through a per-site `ClassLibSite` method handle (`NqpOps.classlib`).
A census knob, `NQP_OP_CENSUS=1`, counts calls per table op id and per
classlib method name (`LongAdder`s, env-gated, printed at exit next to
the dispatch stats). Counts alone mislead, so each census pairs with a
JFR profile through `tools/build/jfr-attribute.raku --innermost`,
giving exclusive time per op. Workloads: the two cold rows and the warm
sanity proxy, with a CORE.c compile as a third view of the compiler's
own ops (compile time is the lower priority; its census is free).

**What a site may fold.** A promoted op folds only two kinds of thing:
a type fact read from the captured state under its assumption (the
method a name resolves to, the boolification mode, whether the type is
a container), and per-object shape through the layout compare. An op
with nothing foldable in its body (I/O, hash and string ops) is not
promoted. If such an op shows up hot, the remedy is a narrower boundary
around its slow path, and the ledger lists those as **boundary trims**,
separately from promotions, so the two are never confused.

**Recipe and batching.**
- A **table op** promotes engine-side only: one line in
  `NqpProgramBuilder.beginOp`/`endOp`/`dedicatedOp`, an `@Operation`
  class in `NqpRootNode.java` modelled on `IsConcreteOp`, a site class
  in `NqpTypeOps.kt` (or a new `NqpClassLibOps.kt` when the file
  outgrows itself); then the runtime-jar rebuild
  (`./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar
  syncRuntimeJars`, seconds) and a rig row the same day.
- A **classlib op** needs, in addition, an op id constant in
  `NqpOps.java` and an `op3(...)` row in `TruffleEncoder.nqp`'s
  `emit_init()`, so it is an encoder change: `clean buildJvm` plus
  `make`, about twenty minutes. Classlib ops promote in batches, one
  full build per batch, amended rather than waited on. The classlib
  road stays for code compiled before the row existed, so stage0 is
  not regenerated for a promotion.
- **Batch 1 is fixed by design and needs no census:** `findmethod` and
  `tryfindmethod`, `can`, `istrue` and `isfalse`, `iscont`. All are
  table ops. Every batch after it is chosen by the census.

**Stop rule.** An op is hot when it holds at least 1 % of exclusive
samples on any of the three workloads. After each batch the census
re-runs. The campaign ends when no hot op has a foldable body, or when
two consecutive batches move neither cold clock nor the warm proxy
outside the series' own spread. The ledger records, per op, its census
share before and the rig row after, so the close can say what each
promotion bought.

## Section 5: phases, measurement, gates, the close

**Phase A: the type state.**
- **A1, runtime only:** `TypeState`, `publish`, every writer, the
  serializer, the nqp-runtime tests (`truffle-api` added to that gradle
  module's test runtime path; `Truffle.getRuntime()` there is the
  default interpreter runtime, whose assumptions work), the publish
  counter.
- **A2, the engine consumers:** the sites, the folder and program
  assumptions, the transient state on the type guard across all three
  roads, the persisted-slot restore, the two correctness tests.
- Neither touches the wire, so both rebuild as runtime jars in seconds
  plus one dispatch retrain (`rakudo-runtime.jar` is a prerequisite of
  the training stamp only, `tools/templates/jvm/Makefile.in:193`), and
  the setting jars never recompile.
- Gate: nqp suite and warm `t/01-sanity`; then **rig row `a`**. The
  storm answer is read off row `a`'s assumption trace. If compiled code
  is being invalidated by republishes in numbers, the per-facet split
  is designed then, as an A2' with its own row, not assumed now.

**Phase B: the campaign.**
- **B0:** the census knob and the baseline census on the three
  workloads, plus the JFR profiles.
- **B1:** batch 1, engine-only, one rig row.
- **B2..Bn:** census-chosen batches, one full build when a batch
  carries encoder rows, one rig row, one ledger entry per op; boundary
  trims ride along in the same build. Phase B ends by the stop rule.

**Phase C (Revision 1): lazy-loading phase 2, SC demand deserialization.**
- **C0:** measure the SC read's share of the cold run on the Phase B
  close tree (`NQP_UNIT_LOAD_STATS=1` per stage, `tools/build/unit-load-profile.raku`),
  so the 21 % estimate becomes a number before any design.
- **C1..Cn:** the lazy-loading spec's phase 2 as designed there
  (`docs/superpowers/specs/2026-09-13-jvm-lazy-unit-loading-design.md`,
  "Phase 2"), planned with its own brainstorm after Phase B closes; the
  rig row is `c`; the format may change once (stage0 regenerates once,
  still uncommitted under the jar rule).
- **Revision 2 (2026-09-16, user instruction): Phase C integrates the
  MoarVM startup analysis** (`docs/moarvm-startup-analysis.md`, a
  read-only investigation the user asked for the same day). Its findings
  bind Phase C's brainstorm and plan:
  1. **No up-front stubbing.** The lazy spec's "stays eager: stubbing
     every STable and object" is dropped. As MoarVM does
     (`serialization.c`, `MVM_serialization_deserialize` then
     `demand_object`), the root arrays are allocated empty and an entry
     is stubbed on first demand; the `stableIndex` map goes with it (the
     index lives on the object, as MoarVM's `idx_in_sc`).
  2. **Lazy string heap.** The lazy spec's "stays eager: string heap" is
     dropped: an offset table at load, a string decoded on first use
     (MoarVM's `MVM_cu_obtain_string`).
  3. **Lazy HOW at the STable level**: a type touched by `istype` must
     not pull its metaclass and method tables (MoarVM's
     `deserialize_how_lazy`).
  4. **A `working` guard during a drain** (MoarVM's `sc_working`) so no
     stub escapes mid-worklist; this is what the lazy spec's "user code
     never sees a stub" rests on.
  5. **Locking** stays one global lock (lazy spec); MoarVM's per-SC
     reentrant mutex is noted as the alternative, not adopted.
  6. **C0 also measures the blob gap**: CORE.c's serialized SC is
     28.17 MB here against MoarVM's 7.83 MB for the same objects (3.6x;
     likely reference packing, MoarVM packs SC id and index in one
     varint). The writer fix comes BEFORE the demand reader if C0
     confirms it, since the format is not frozen by stage0 (one regen,
     uncommitted).
  7. **The bodies row is not Phase C's.** MoarVM executes the same 1207
     package bodies, capturelex prologues, 1148 clones and ~4600 cold
     dispatcher runs at load, in 0.08 s total; ours is per-unit cost.
     Phase C's expected share is the SC-read row only (~10 % of
     main-thread samples), and the close says so. A static-clone road and
     a non-dispatching capturelex fast path are recorded as the bodies
     row's own levers, ranked at the milestone close against M9.
  8. **Persisted dispatch slots keep priority** over Phase C if the two
     clocks disagree: MoarVM cannot persist dispatch programs, we can.
  The analysis doc holds the file:line evidence for each point.
- **Revision 5 (2026-09-18): Phase C brainstormed and specified** in
  `docs/superpowers/specs/2026-09-18-jvm-milestone-8-phase-c-sc-demand-design.md`,
  which carries out the eight items above. User decisions there: the
  format changes once in full (packed references, varint ints, a string
  offset table, eight-byte table rows, the index on the object; version
  12, stage0 regenerated once and still uncommitted), before the demand
  reader; rows c0, c1, c2; the fixups are not chased below a stated
  threshold. **Phase B is parked at row b2b, not closed**: plan B (rows
  b2c, b2d) and its open items wait for Phase C's close (user, 2026-09-17,
  "let's proceed to milestone 8 phase c").

**Rig:** `tools/build/m7-rig.raku` as it stands (cold rakudo-e, cold
nqp-e, dispatch counters, warm `t/01-sanity` proxy), with the publish
and census counters added to its parse.

**Done criterion:** as milestone 7's. **Compile clock:** Phase A is
expected neutral on CORE.c; anything Phase B buys there is reported as
a side effect, not chased.

**The close.** Whole `t/` once on one warm server, after raising the
eval server's off-heap allowance in `tools/build/evalserver-sweep.raku`
(the 9 GiB `MemoryMax` cage = 6 GB heap + allowance is what killed
milestone 7's run at file 310 of 482); a milestone summary in
`docs/jvm-perf-findings-2026-09.md`; the position in
`docs/jvm-truffle-only-plan.md`; memory; rebase both trees onto their
upstream mains and force-with-lease to ab5tract. The no-jar rule
stands: nothing in this milestone changes the artifact format, so
stage0 is not regenerated and remains the nine uncommitted v2 jars.

## Section 6: out of scope, open items, risks

**Out of scope, by decision.** The Native Image road and the auxiliary
engine cache (milestone 9, decision 3). Lazy-loading phase 2 is IN scope
since Revision 1 (Phase C); the compression decision stays where
milestone 7 left it, to be re-taken with Phase C's numbers. Java interop is
untouched. The `DynamicObject`/`Shape` migration stays rejected:
milestone 5's layout is the shape fact, the type state is the type
fact.

**Open items inherited, listed, not promised.** The
`t/02-rakudo/closure-static-clone.t` red (not Phase C's doing,
unbisected); the warm proxy question (50, 63, 59 s single samples),
which the close's whole-`t/` run is the first real chance to settle;
the in-build stage `JavaExec` tasks still on the boot class path;
training's ~1 % run-to-run variation. Each gets its state at the close
in the ledger.

**Risks, each with its check.**
1. *Invalidation storms.* Check: row `a`'s assumption trace. Fallback:
   the per-facet split (approach B), designed only then.
2. *The extra dependent load on every runtime fact read.* Check: the
   cold rows of row `a`, taken before any promotion so the cost stands
   alone.
3. *Persisted slots going stale in numbers* if types republish after
   restore. Check: `recorded=` on the trained program, baseline 195.
4. *A promotion changing behaviour.* Check: the nqp suite plus sanity
   every batch; verify mode (`NQP_DISPATCH_PERSIST=verify`) stays
   available.
5. *A classlib batch costs a full build.* Batches are sized so a build
   carries several promotions, never one.

## What the next session does

`superpowers:writing-plans` for Phase A (A1 and A2 as one plan, A1's
tests first), from the worktree at rakudo `8fc895069c` / nqp
`8ea35ba95`. Phase B's plan is written after row `a` is in the ledger.
