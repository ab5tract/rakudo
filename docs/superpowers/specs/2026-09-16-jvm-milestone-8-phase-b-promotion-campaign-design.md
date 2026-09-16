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
effect.

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
constant, so the compiled site is one REPR read: the type-object test
for mode 5, the unbox for modes 1 to 4, the bigint sign for 6, the
iterator or elems test for 7 and 8. Mode 0 (call a method) is not
folded: the site takes the runtime's slow path and the census counts
it as `istrue.method`. A negate flag serves `isfalse` and `Truthy`'s
negated form. `Truthy` keeps its native-int and num arms and gains the
site for its object arm only.

**`FindMethodSite`** for `findmethod`, `tryfindmethod` and `can`, one
node with a constant kind operand (find, try, can). `tryfindmethod`
reaches it by a `dedicatedOp` arm on `OP_TRYFINDMETHOD` with two args;
the other two by classlib arms. Deconts through an inner `DecontSite`.
The guard adds the name string's identity (names arrive from the
constant pool; a different name is a miss). Under a valid state whose
`modeFlags` carry `METHOD_CACHE_AUTHORITATIVE`, the site folds the
cache's answer for the name: a code object, or null. `findmethod`
throws through the runtime's slow path on null (the type-name guest
call lives there), `can` returns 0 or 1, `tryfindmethod` returns the
answer. A non-authoritative or absent cache is **not** a site miss: the
site calls the HOW-walk slow path every time and the census counts it
as `findmethod.nonauth`. This is the "fold only published facts" ruling
of the Phase A ledger; the multi-state guard is designed only if
`findmethod.nonauth` is hot.

**Reachability arms.** Three lines in `dedicatedClasslib` route
source-level `decont`, `isconcrete` and `create` (one arg each) to
`Op.DECONT`, `Op.ISCONCRETE`, `Op.CREATE`. Result-type handling follows
the Phase A istype precedent: both roads answer a boxed object, the
untyped sink is unchanged.

**Commits and gate.** One commit per site, the arms last. One
runtime-jar rebuild (`./nqp/gradlew -p nqp :nqp-runtime:jar
:nqp-truffle:jar syncRuntimeJars`), retrain, nqp suite, warm sanity,
then rig row `b1` with the census on, compared against the B0 baseline
per op.

**Tests.** `nqp/t/jvm/20-op-sites.t`: each site folds the right answer;
refolds after the writer op republishes the type (`setcontspec`,
`setboolspec`, `setmethcache`, `setmethcacheauth`); its census hit
counter moves, which proves the routing is live.

## Section 4: the census batches (B2 to Bn) and the stop rule

**Choosing a batch.** After each rig row the census re-runs on the
three workloads and the CORE.c compile. Every op at or above one
percent of exclusive samples on any workload is a candidate. Each
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
is the first column of every row.

**Stop rule.** The campaign ends when no hot op has a promote or trim
verdict, or when two consecutive batches move neither cold clock nor
the warm proxy outside the series' own spread. The ledger records which
condition fired.

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

## What the next session does

`superpowers:writing-plans` for Phase B, from the worktree at rakudo
`4d75dbce84` / nqp `2b627034f`: the opening commit and B0 as one plan
(tests first), batch 1 as its own plan after row `b0` is in the ledger.
Census batches are planned one at a time from their census.
