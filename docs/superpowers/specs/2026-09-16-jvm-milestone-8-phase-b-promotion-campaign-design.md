# Milestone 8, Phase B: the promotion campaign

Design, 2026-09-16. Approved in chat the same day, section by section.
Parent: `docs/superpowers/specs/2026-09-16-jvm-milestone-8-type-state-design.md`
(sections 4 and 5 of that spec are superseded by this one where they
differ). Designed from the worktree at rakudo `4d75dbce84` / nqp
`2b627034f`, the Phase A close.

## Goal

Move the hot generic-boundary ops onto sited Truffle nodes that fold
type facts under the Phase A type state, until the census says nothing
hot and foldable is left. Every promotion is engine-module code; Phase B
adds no encoder row, changes no wire format, and regenerates no jar.

Both clocks of the milestone (cold rakudo -e, cold nqp -e) and the warm
sanity proxy are the measure. The compile clock is reported as a side
effect. (Revision 3, 2026-09-17, user decision: **from batch 2 on the
CORE.c compile is a first-class clock of the campaign**, next to the warm
proxy; the cold rows are reported on every row but no longer decide the
stop rule. Reason: the generic roads' share is only measurable on CORE.c,
at ~13,000 samples against ~100 on a cold row.)

## Baselines

Milestone 7's close row, unchanged by Phase A within the spread: cold
rakudo-e 2.247 s, nqp-e 1.198 s, misses 4931, hits 35512, sanity 25/25
59 s, CORE.c 296 s, make 888 s. Phase A's rig row `a` sits inside the
spread (2.290 s). Storm baseline after the Phase A wave: publishes=14858,
4 installed-code invalidations, 0 TypeState.

## What the survey changed (2026-09-16)

The parent spec assumed batch 1's ops were table ops and that a classlib
promotion needs an encoder row and a full build. The source says
otherwise:

- Of `findmethod`, `tryfindmethod`, `can`, `istrue`, `isfalse`, `iscont`
  only `tryfindmethod` has an `op3` row in `TruffleEncoder.nqp` (id 254).
  The other five are `map_classlib_core_op` entries in
  `nqp/src/vm/jvm/QAST/Compiler.nqp` and arrive at the engine as
  `W_CLASSLIB` by class and method name, through the generic
  `ClassLibOp` (a `@TruffleBoundary`, an `Object[]` copy and a spread
  method-handle call per execution). Their table ids in `NqpOps.java`
  exist but are dead from the encoder's point of view.
- Phase A's `NqpProgramBuilder.dedicatedClasslib(cls, meth, nargs)` is
  the third promotion road: a classlib op promotes engine-only, by name,
  with no encoder change. Today it routes `hllize` and `istype` only.
- `decont`, `isconcrete` and `create` are half-reachable: their sites
  exist (`DecontSite`, `IsConcreteSite`, `CreateSite`) but only the
  encoder's hand-emitted ids 51/53/58 reach them; a source-level
  `nqp::decont` takes the generic classlib road.
- The `Truthy` condition node (every `if`/`while` on an object operand)
  is not sited; it calls the same boolification code `istrue` does.
- `NQP_OP_CENSUS` exists nowhere in code. The dispatch stats print from
  a shutdown hook in `NqpDispatch.kt` under `NQP_DISPATCH_STATS`; the
  rig parses that line.
- The engine module has no JUnit source set; every site is tested only
  through `t/jvm/*.t`.

## User decisions (2026-09-16)

1. **The stale-slot hazard gets the SC stamp hotfix** as Phase B's first
   commit (over a Makefile retrain, or leaving the
   `NQP_DISPATCH_PERSIST=off make` workaround).
2. **Rakudo's runtime jar becomes an order-only prerequisite** of
   `rakudo.jar` in the Makefile, matching nqp's side: bytecode does not
   depend on the runtime that executes it. A Rakudo runtime edit then
   costs a jar rebuild and a retrain, not a setting recompile.
3. **Approach 1, the engine-only campaign** (over the parent spec's
   encoder-row road, and over a multi-state findmethod site). No encoder
   rows in Phase B; the multi-state guard is census-gated, see section
   3.

## Section 1: the opening commit (B-pre)

Four items, all runtime-jar rebuilds, before any promotion.

**The SC stamp.** `ZipDirectory.Entry` gains the entry's CRC32, read
from the central-directory record it already parses (offset, size).
`UnitStore` exposes the CRC of its `unit.serialized` entry, and the
loader sets it on the `SerializationContext` it deserializes as that
SC's stamp (an int; 0 = unstamped). On record, `DispatchSlotCodec`
collects one stamp per SC handle its `PRef`s name and writes them into
the slot as a handle-to-stamp map; `DispatchSlot.SCHEMA` goes from 1 to
2. On restore, `DispatchPersist.restore` compares every stamp against
the loaded SC's; a slot with any mismatch is dropped, counted as
`staleStamp=` on the dispatch-stats line, and named under the existing
trace knob. A reference into an in-process SC (the bootstrap
`__6MODEL_CORE__`, a compile in progress) records stamp 0 and matches
only a stamp 0 under the same handle; bootstrap drift across a
runtime-jar rebuild stays covered by the training stamp's hard
dependency on both runtime jars. The hazard this leaves is therefore a
mis-restore and not a miss -- two in-process SCs sharing a
deterministic handle would match each other's stamp 0 -- and
`__6MODEL_CORE__` is the only stamp-0 handle in the trained artifacts.
(Revision 1, 2026-09-16: the first wording would have dropped every
program guarding on a bootstrap type.) Old-schema slots are dropped by the schema check that already
exists, which is how the schema bump retrains every slot once. The
stamp costs nothing at cold start (no hashing; the CRC is in the zip
directory) and changes no artifact format.

**Makefile.** `$(RUNTIME_JAR)` moves after the `|` in
`J_RAKUDO_DEPS_EXTRA` (`tools/templates/jvm/Makefile.in`). The training
stamp keeps its hard dependency on the runtime jar.

**The two Phase A parkings.** `DispatchRecord.emitGuards`' Literal
branch assigns `guards.state` only when it is non-null (today it
overwrites the constructor capture with null and silently disables the
state check). `DispatchCallSite.install` writes the freshness-filtered
array back to `programs` even when the site is at `MAX_PROGRAMS`.

**Tests and gate.** `DispatchSlotCodecTest` gets a stamp round-trip
case; `DispatchPersistTest` gets a mismatch-drops case and an
unstamped-is-unpersistable case. Gate: runtime JUnit, nqp suite, and
one `make` with `NQP_DISPATCH_PERSIST` at its default, which is the
cross-build scenario that died in Phase A. `NQP_DISPATCH_PERSIST=verify`
once, since the schema changed. Then rig row `b0`, so the stamp and the
parking fixes are measured before any promotion.

## Section 2: the census (B0)

**Knob.** `NQP_OP_CENSUS=1`, read once into a `static final` boolean in
the engine module, so compiled code carries no counters when it is off.
Three counter families, `LongAdder`s bumped behind a `@TruffleBoundary`,
the shape `NqpDispatch`'s `count` helpers already use:

- per table op id, at the generic `RunOp` entry;
- per classlib class-and-method name, at the generic `ClassLibOp` entry;
- per site class: hits, misses, pins, republish refolds, and the
  slow-path calls a pinned or unfoldable site makes (named per path,
  e.g. `istrue.method`, `findmethod.nonauth`).

The site counters are what a `t/jvm` test asserts on. That closes the
Phase A ruling that the istype routing test could not detect loss of
its routing.

**Output.** At exit, on the dispatch-stats shutdown hook: one
`op census:` line with totals (table calls, classlib calls, site hits,
site misses), then the top 30 table ops by count with their names, the
top 30 classlib names, and one line per site class. Table-op names come
from the encoder's own `%emit_ops` table, exported once at build time
into a resource on the engine jar, so the census prints `findmethod`
rather than `245`.

**Time, not only counts.** Every census run pairs with a JFR recording
read through `tools/build/jfr-attribute.raku --innermost`, whose "entry
from interpreter" table already attributes the runtime entry an op makes
from engine code. It gains `--ops`, which sets the containers to the
two generic entries and the site package, so that table is the
exclusive-time view per op.

**Workloads.** The two cold rows, the warm sanity proxy on one eval
server, and one CORE.c compile. `tools/build/m7-rig.raku` gains
`--census`: it sets the knob on the cold rows, saves each `op census:`
block next to the row, and parses the totals into the row summary but
not the row line, the way the publish counter was added.

**Baseline.** The census on the B-pre tree, recorded in the ledger as
the reference column of every later row.

**The hot rule** is the parent spec's: an op is hot at one percent of
exclusive samples on any workload. Counts rank candidates; the JFR share
decides.

## Section 3: batch 1, the sites

All engine-module code modelled on the Phase A sites in
`nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt`:
one `@Operation` node in `NqpRootNode.java`, one site object per
instruction built in `NqpProgramBuilder.beginOp`, `state` captured under
its assumption, guard = `valid()` plus STable identity, monomorphic with
the existing `MAX_MISSES` pin, `republished` refolds without spending a
miss.

**`IsContSite`** for `iscont`. Arm: `Lorg/raku/nqp/runtime/Ops;`,
`iscont`, one arg, no thread-context (its classlib registration has no
`:tc`, unlike the rest of the batch). Folds to a constant 0 or 1 read
from the captured state's `containerSpec`. Null answers 0 inline. The
cheapest site in the batch and the reference for the pattern.

**`IsTrueSite`** for `istrue`, `isfalse`, and `Truthy`'s object arm.
Deconts first through an inner `DecontSite` with the `SuspendedIn`
tail `IsConcreteSite` already has (a Proxy FETCH may suspend). Then a
switch on the captured boolification mode, a compilation-final
constant, so the compiled site is one REPR read. (Revision 2,
2026-09-17: **modes 1-5, 7 and 8 fold; 0 pins (`method`); 6 stays on
the runtime road** -- the BIGINT read goes through the bigint cache
behind a boundary, so it is left generic by ruling, a named B2
candidate at `mode6=19,485` on sanity.) Mode 0 (call a method) is not
folded: the site takes the runtime's slow path and the census counts
it as `istrue.method`. A negate flag serves `isfalse` and `Truthy`'s
negated form. `Truthy` keeps its native-int and num arms and gains the
site for its object arm only.

**`FindMethodSite`** for `findmethod`, `tryfindmethod` and `can`, one
node with a constant kind operand (find, try, can). `tryfindmethod`
reaches it by a `dedicatedOp` arm on `OP_TRYFINDMETHOD` with two args;
the other two by classlib arms. Deconts through an inner `DecontSite`.
The guard adds the name string's identity (names arrive from the
constant pool; a different name is a miss). (Revision 2, 2026-09-17: **Ruling 7's rule**, which is
weaker than this paragraph's first wording.) Under a valid state, a
cache **HIT folds under any authority** -- the runtime answers a hit
before it ever consults the flag -- while a cache **MISS folds to null
only under an AUTHORITATIVE cache**, since under an advisory one the HOW
may still find the method. `findmethod` throws through the runtime's
slow path on null (the type-name guest call lives there), `can` returns
0 or 1, `tryfindmethod` returns the answer. An unfoldable miss is **not**
a site miss: the site pins, calls the HOW-walk slow path every time, and
the census names which of the two it met -- `findmethod.advisory` (a
miss under a non-authoritative cache) or `findmethod.nocache` (no method
cache at all). This is the "fold only published facts" ruling of the
Phase A ledger; the multi-state guard is designed only if those keys are
hot.

**Reachability arms.** Three lines in `dedicatedClasslib` route
source-level `decont`, `isconcrete` and `create` (one arg each) to
`Op.DECONT`, `Op.ISCONCRETE`, `Op.CREATE`. Result-type handling follows
the Phase A istype precedent: both roads answer a boxed object, the
untyped sink is unchanged.

**The batch kill-switch.** (Revision 2, 2026-09-17.) Every batch gets a
name in `NQP_SITES_OFF=name,...` (or `all`), read once in
`NqpProgramBuilder`: with a name off the dedicated road is not built and
the generic table/classlib road runs instead, so a suspect batch can be
bisected in a child process without a rebuild.

**Commits and gate.** One commit per site, the arms last. One
runtime-jar rebuild (`./nqp/gradlew -p nqp :nqp-runtime:jar
:nqp-truffle:jar syncRuntimeJars`), retrain, nqp suite, warm sanity,
then rig row `b1` with the census on, compared against the B0 baseline
per op.

**Tests.** `nqp/t/jvm/21-op-sites.t` (Revision 2, 2026-09-17: the file
landed as 21, next to the census's 20): each site folds the right answer;
refolds after the writer op republishes the type (`setcontspec`,
`setboolspec`, `setmethcache`, `setmethcacheauth`); its census hit
counter moves, which proves the routing is live.

## Section 4: the census batches (B2 to Bn) and the stop rule

**Choosing a batch.** After each rig row the census re-runs on the
three workloads and the CORE.c compile. Every op at or above one
percent of exclusive samples on any workload is a candidate. (Revision
3, 2026-09-17: three amendments from batch 1's ledger. **The retake
rule** -- a batch's "before" column is a census and a JFR profile taken
on the previous batch's tree, on every workload including CORE.c; B1
skipped the CORE.c compile, so B2 opens with that retake. **The hot rule
reads roads**: the JFR resolves a sample to its road, not to the op
(ledger Ruling 10), so an op's share is its road's exclusive share times
its count share of that road. **A road may hold a verdict itself**: when
a road's own leaf dominates the road -- `classlibInline` was 18.3 % of
CORE.c on its own, with 692 M sited calls costing 2.3 % -- the road gets a
**trim** verdict and its own row, before the heads inside it.) Each
candidate gets one of three verdicts, written in the ledger before any
code:

- **promote**: its body reads a type fact or a per-object shape a site
  can fold;
- **trim**: no foldable fact, but a wide boundary; the fix is a narrower
  boundary around the slow path;
- **leave**: neither.

Promotions and trims never share a ledger row.

**Batch size.** A batch takes every promote and trim verdict from one
census, never a single op. Batches are engine-module rebuilds; a trim
inside Rakudo's runtime is a jar rebuild plus retrain under the
order-only Makefile.

**New site kinds.** A promotion that needs a fact no site reads today
gets its own site class in `NqpTypeOps.kt`, or a sibling file once that
file passes about a thousand lines. Two-entry polymorphism (as
`NqpOps.AttrSite` has) is added to a site only when its census pin
count says monomorphism is losing, and is recorded as its own row.

**Ledger, per op.** Census share on each workload before, the verdict
with its one-line reason, the commit, the rig row after. The B0 census
is the first column of every row (Revision 3: from B2 on, the retake's
column stands beside it and is the one a row is read against).

**Stop rule.** The campaign ends when no hot op has a promote or trim
verdict, or when two consecutive batches move neither cold clock nor
the warm proxy outside the series' own spread. The ledger records which
condition fired. (Revision 3, 2026-09-17: a batch **moves** when the
CORE.c clock or the warm proxy leaves the series' spread; the cold rows
are reported and no longer decide. Under this reading batch 1 counts as
a moving batch: 5-10 % on the warm proxy in its same-session A/B.)

**Confounds.** Row `b1` also carries the reachability arms and
`Truthy`, so its per-op census, not the clock alone, attributes the
gain. Any batch that lands alongside a Rakudo rebuild reports that.

## Section 5: gates, measurement, the close

**Per-commit gate.** Runtime JUnit where the commit touches the runtime
module, `t/jvm/20-op-sites.t`, the nqp suite, warm `t/01-sanity`. Per
the standing rules: no per-lever `t/02-rakudo`; every gate reported
with its wall time; a failed benchmark run is recorded as not gathered
and never re-run.

**Rig rows.** `b0` after the opening commit, with the census knob off;
the baseline census is a separate `--census` run of the same tree.
`b1` after batch 1; one row per census batch, each a knob-off row plus
a `--census` run. The rig's summary carries
the census totals and the publish counter; the row line stays as it is
so the series stays comparable with milestone 7's close row.

**Verify mode.** `NQP_DISPATCH_PERSIST=verify` once after the opening
commit and once at the close.

**The close.** Whole `t/` on one warm server, after
`tools/build/evalserver-sweep.raku`'s off-heap allowance is raised above
the 9 GiB `MemoryMax` cage that killed milestone 7's run at file 310 of
482; diffed against `docs/jvm-spectest-known-failing.txt` and the
`t/02-rakudo` red baseline. Then the milestone summary in
`docs/jvm-perf-findings-2026-09.md`, the position in
`docs/jvm-truffle-only-plan.md`, memory, and the rebase of both trees
onto their upstream mains with force-with-lease to ab5tract. The no-jar
rule stands: nothing in Phase B changes an artifact format; stage0 is
not regenerated and remains the nine uncommitted v2 jars.

**Out of scope.** Encoder rows for promoted ops. The multi-state
findmethod guard, unless `findmethod.nonauth` is hot. The auxiliary
engine cache and the Native Image road (milestone 9). Lazy-loading
phase 2 is Phase C, planned after this phase closes, C0 measuring
first.

**Risks, each with its check.**
1. A site folding a fact its state did not publish: the refold tests in
   `20-op-sites.t` plus verify mode.
2. Counter cost leaking into compiled code: row `b0` is taken with the
   knob off and compared with a knob-on run of the same tree.
3. A stamp drop storm on every run: `staleStamp=` must be 0 on the
   second run after any build.
4. A dedicated result type disagreeing with the classlib registry's
   (`istrue`/`isfalse`/`can`/`iscont` are INT in the registry): the
   Phase A precedent, both roads answer a boxed object into an untyped
   sink; the nqp suite shows a mismatch at once.

## Section 6: batch 2, the roads and the heads (Revision 3, 2026-09-17)

Designed from the worktree at rakudo `e4210e80ff` / nqp `76d88cf32`, the
batch 1 close, after an Opus survey of the two generic roads. Approved in
chat, section by section, the same day. Two user decisions precede it:
CORE.c is a first-class clock from here (Goal, above), and B2 takes the
**roads-first** approach over heads-only and over defaulting the
PE-visible road (`NQP_CLASSLIB_INLINE`), which keeps both `Object[]`
copies and the boxing adapter and whose compile-capacity cost is
unmeasured.

### What the survey found

- **The generic classlib road** (`ClassLibOp` -> `NqpOps.classlib` ->
  `classlibInline`) does, per call: a variadic `Object[]` from the
  Bytecode DSL, a second `Object[]` copy to append the thread context
  (about 85 % of the 624 registrations are `:tc`), an `invokeExact` on a
  per-instruction handle adapted with `asSpreader` and `asType` to
  `(Object[])Object` -- so every INT/STR result is boxed by the adapter --
  and one megamorphic call site shared by every classlib op in the
  process, all behind a `@TruffleBoundary` (milestone 7's lever A7; the
  knob restores PE visibility). That is the 18.3 % leaf. Milestone 7
  measured the boundary placement only, on the cold rows and the warm
  proxy, never on CORE.c.
- **The table road** (`RunOp` -> `NqpOps.run` boundary -> a ~1300-arm
  `switch` over a boxed `Object[]`) has the same shape; `iseq_s`
  (44.7 M on CORE.c, the top table op), `throwpayloadlex`, `hlllist`,
  `hllhash` and the native attribute ops all take it.
- **Native attribute access is unsited on both roads.** The encoder has
  rows for `getattr`/`bindattr` (81/82, the object case, `AttrSite`) and
  none for `getattr_i/_n/_s/_u` or `bindattr_*`: a `QAST::Var` with
  attribute scope and a native primspec emits table ops 116-123 (uint
  291/312) into the generic switch, and a source-level `nqp::getattr_i`
  becomes a classlib call. Both use the thread-context scratch-register
  protocol (`tc.nativeI`, `tc.nativeType`) and decont the class handle
  per call. On CORE.c: `getattr_i` 28 M table + 37 M classlib,
  `bindattr_i` 36 M classlib. `RakuObjectLayout` already exposes
  `longGetter`/`longSetter`/`refGetter` handles per slot.
- `isnull` has a dedicated node on the table road and no encoder row, so
  its 32 M CORE.c calls all take the classlib road. `how`/`who` read
  mutable STable fields (`HOW` has no writer op; `setwho` is a bare field
  write, no republish), so neither is a published fact. `iter` folds
  strongly (REPR class, storage spec, HLL iterator type) but is
  frame-dependent. Boolification mode 6 materialises a `BigInteger` per
  truth test on the runtime road.
- The registry by arity: 0-4 args cover about 600 of 624 registrations;
  arity 5-6 is 20. Results: OBJ and INT dominate; STR, NUM, UINT are the
  tail. Boxing elimination is enabled for `long` only.
- `NqpTypeOps.kt` is at 1231 lines, past section 4's split point.
- The triple census block in `b1-sanity-census.log` is the sweep's: one
  block per chunk selected by line prefix, and the rig reads the first
  `op census:` header only. The engine prints once.

### 6.1 The opening: the retake and the housekeeping (no rig row)

1. **The retake.** On the batch 1 tree, jars rebuilt and retrained: one
   CORE.c compile with the census on, one with JFR and the census off,
   and the three cheap workloads' censuses. This is the "before" column
   of every B2 row (the retake rule, section 4).
2. **The spike.** One further CORE.c compile under `NQP_CLASSLIB_INLINE=1`
   with JFR. Recorded, not acted on: it sizes the trim's ceiling and says
   whether the trimmed road should default PE-visible or boundary.
3. **The settle plan for batch 1's non-reproducing red** runs as the
   ledger wrote it: `t/nqp/023-named-args.t` 50 times, the 2x2 of
   `NQP_DISPATCH_PERSIST` on/off by `NQP_SITES_OFF` unset/`all`, one nqp
   suite under `NQP_DISPATCH_PERSIST=verify`. Ledgered before any B2 code.
4. **Tooling.** `evalserver-sweep.raku` anchors `census-block` at the
   `op census:` header; `m7-rig.raku` reads every header. Closes the
   parked residual and the triple-block artefact.
5. **The split.** `NqpTypeOps.kt` keeps `Site`, the registry and the
   shared helpers; the batch 1 sites move to a sibling file; B2's sites
   go in a third. A pure move, checked by `21-op-sites.t` and the census
   counters.

### 6.2 The classlib road trim (rig row b2a)

The generic road stays one mechanism and stops doing per-call work the
instruction knows at build time.

- **Five arity nodes** for arity 0-4 replace the variadic `ClassLibOp`
  there; arity 5-6 keep the variadic node. Each node has two
  specialisations selected by the constant result type: `long` for
  INT/UINT (boxing elimination makes `getattr_i`, `elems`, `existskey`
  allocation-free on the result side) and `Object` for OBJ/STR/NUM.
- **One exact handle per site, resolved once**, adapted to a uniform
  type per arity and flavour, `(Object, ..., ThreadContext) long|Object`;
  a non-`:tc` op has the context argument dropped by the adapter. No
  spreader, no `asType` to Object, no `Object[]` on either side. The
  declared residual: INT/NUM *operands* stay boxed (the operand stack is
  Object for mixed signatures).
- **The boundary stays, typed**: one `@TruffleBoundary` static per arity
  and flavour doing `site.mh.invokeExact(...)`. `NQP_CLASSLIB_INLINE`
  keeps its meaning on the new road (call the compilation-final handle
  without the boundary), so `t/nqp/125`'s child and the spike still run.
- Suspension and errors unchanged: same catch shapes, same store-local
  plus suspend-check wrapper, same census bump.
- **Kill-switch `classlib`**: off, the builder emits the old variadic
  node for everything -- row b2a's same-session A/B.
- **Tests**: `nqp/t/jvm/22-classlib-road.t` -- one op per arity and
  flavour, a `:tc` and a non-`:tc` op at one arity, a suspending op, a
  throwing op, an arity-5 op still on the variadic node, the knob. The
  nqp suite is the integration test: every bootstrap classlib op crosses
  the road.
- One commit, engine-only; runtime jar rebuild plus retrain.

### 6.3 The heads (rig row b2b)

The table road gets no generic trim: its switch already receives typed
arguments per arm, an arity node would save one array, and its heads are
few and named. Verdicts from the B0 census; the retake may reorder them
and may gate the last line in, but adds nothing without a foldable fact.

| op | verdict | design |
| --- | --- | --- |
| `getattr_i/_n/_s/_u`, `bindattr_i/_n/_s/_u` | **promote** | `NativeAttrSite` on the `AttrSite` pattern: two entries, layout identity, class-handle identity, name identity; the layout's `longGetter`/`longSetter`/`refGetter` handles; NUM through the long bits. Reached from table ids 116-123 (+ the uint ids) via `dedicatedOp` and by name via `dedicatedClasslib`. Replaces the scratch-register protocol and the per-call handle decont. Kill-switch `nativeattr`. ~100 M CORE.c calls, the batch's largest head |
| `iseq_s` | **trim** | a dedicated string-equality node, PE-visible like the native arithmetic nodes, no boundary |
| `isnull` | **promote** (reachability) | one `dedicatedClasslib` arm to the existing `Op.ISNULL` |
| `isconcrete_nd` | **promote** | a no-decont flag on the `IsConcreteSite` road, arm by name |
| boolification mode 6 | **promote** | `IsTrueSite` folds mode 6 under the state: type object 0, else the bigint body's sign; no boundary, no cache lookup |
| `how`, `who` | **trim** | dedicated nodes: decont, read the STable field, no fold (no published fact) |
| `atpos`, `atkey`, `push`, `elems`, `shift`, `existskey`, `bindkey`, `concat`, `setcodeobj` | **leave** | per-object REPR calls or pure functions; served by 6.2 |
| `iter`, `hlllist`, `hllhash` | **census-gated** | foldable but frame-dependent; designed only if the retake puts them over the line, as their own row |

Tests in `21-op-sites.t` per new site: fold, refold after the writer op,
the counter moves. One commit per head; row b2b after them, same-session
off/on per switch name.

### 6.4 Polymorphism and the multi-state question

- **Two-entry polymorphism is census-gated, per site.** After row b2b's
  census a batch 1 site (`IsContSite`, `IsTrueSite`, `FindMethodSite`)
  gets a second entry only if its `pinned=` slow-path calls are at least
  10 % of its own calls on CORE.c or the warm proxy (B1's sanity numbers:
  iscont 43 k of 47 k, istrue 226 k of 2.4 M, findmethod 89 k of 405 k).
  The shape is `AttrSite`'s: two captured states, two answers, the third
  distinct state pins. Each is its own commit and its own row line.
- **The advisory findmethod probes stay unfolded** (Ruling 7). If the
  retake shows them hot on CORE.c the remedy is an authoritative method
  cache for those types on the Rakudo side, outside this batch.

### 6.5 Gates, rows, artefacts

- **Gate per commit**: `22-classlib-road.t`, `21-op-sites.t`, the nqp
  suite, warm `t/01-sanity`, each with its wall time. No runtime-module
  change in the batch, so runtime JUnit is up to date by construction.
  Verify mode once after b2b.
- **Rows** b2a and b2b, each: the two cold rows, the warm proxy, one
  knob-off CORE.c compile with JFR, one census run, and the same-session
  off/on pair under the batch's switch names.
- **Artefacts**: this revision; the ledger's B2 section; the two tool
  fixes. Rakudo side untouched otherwise. No jar commits; stage0 stays
  the nine uncommitted v2 jars.
- **Out of scope for B2**: operand-side boxing on the trimmed road, the
  arity 5-6 tail, `iter`/`hlllist`/`hllhash` unless gated in, Phase C.

## What the next session does

`superpowers:writing-plans` for batch 2 from section 6, from the worktree
at rakudo `e4210e80ff` / nqp `76d88cf32`: 6.1 and 6.2 as one plan (the
retake first, tests first), 6.3 as its own plan after row b2a is in the
ledger; 6.4's rows only if their gate fires.
