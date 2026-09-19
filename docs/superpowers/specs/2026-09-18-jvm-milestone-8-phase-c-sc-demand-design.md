# Milestone 8, Phase C: SC demand deserialization (lazy-loading phase 2)

Design, 2026-09-18 (brainstormed in the night of 2026-09-17, approved in
chat section by section). Parent:
`docs/superpowers/specs/2026-09-16-jvm-milestone-8-type-state-design.md`
(section 5, "Phase C", Revisions 1 and 2, whose eight binding items this
spec carries out). Grandparent:
`docs/superpowers/specs/2026-09-13-jvm-lazy-unit-loading-design.md`
("Phase 2", superseded here where the two differ). Evidence:
`docs/moarvm-startup-analysis.md`. Designed from the worktree at rakudo
`2338bc426c` / nqp `62fa7ea9f`, the Phase B row b2b tree.

Phase B is **parked, not closed**, at row b2b: plan B (rows b2c and b2d)
and Phase B's three open items (the verify-mode nqp suite after b2b, a
third identical CORE.c compile, the `t/jvm` partition test) wait for
Phase C's close, when the user decides whether plan B runs or the
milestone closes. User decision 2026-09-17: "let's proceed to milestone
8 phase c".

## Goal

Make the serialization context (SC) of every unit demand-deserialized:
an STable, object, closure or context is read from the mapped
`unit.serialized` slice on first reference, not at load; the string heap
decodes per string on first use; a type's metaclass and stash are pulled
only when asked for. Before that, fix the writer so the blob is a third
its size, in the one format change this milestone allows.

The row Phase C attacks is the SC read: 304 ms of a 1382 ms exclusive
load, 14 % of the 2.2 s cold `rakudo-j -e 'say 1'`. It is bounded from
below by what the unit's deserialize program forces (Section 3). The
bodies row (the load block's guest execution, 526 ms) is not Phase C's,
by the parent's Revision 2 item 7.

## Baselines (C0-lite, 2026-09-17, the b2b tree, single cold runs)

Three cold runs of `RAKUDO_RAKUAST=1 NQP_UNIT_LOAD_STATS=1 ./rakudo-j -e
'say 1'`: 2.20, 2.24, 2.16 s wall. One run through
`tools/build/unit-load-exclusive.raku`:

| stage (exclusive) | ms | share of load |
|---|---|---|
| load-block | 525.7 | 38.0 % |
| deserialize-program | 451.4 | 32.7 % |
| sc-finish | 194.8 | 14.1 % |
| sc-stub | 109.4 | 7.9 % |
| shells | 79.5 | 5.8 % |
| open-store | 21.0 | 1.5 % |
| static-lex-drain | 0.3 | 0.0 % |
| total | 1382.1 | |

CORE.c's SC alone: `sc-stub` 69.4 ms + `sc-finish` 122.7 ms = 192 ms for
5558 STables, 276157 objects, 19331 code refs. BOOTSTRAP's: 17.2 + 38.6 ms
for 1164 STables, 40864 objects, 4070 code refs. The stub and finish
lines are keyed by SC handle, not jar name.

CORE.c's `unit.serialized` (version 11, 28,167,619 bytes), by the header:

| segment | bytes | share |
|---|---|---|
| object data | 14,610,612 | 51.9 % |
| STable data | 4,842,170 | 17.2 % |
| object table (16 B x 276157) | 4,418,512 | 15.7 % |
| string heap (13407 strings) | 3,723,901 | 13.2 % |
| closures table (24 B x 11800) | 283,200 | 1.0 % |
| context data + table (2575) | 217,408 | 0.8 % |
| STable table (12 B x 5558) | 66,696 | 0.2 % |
| repossessions (310), deps (11) | 5,048 | 0.0 % |

MoarVM's SC data for the same setting is 7.83 MB (5247 STables, 234322
objects, 11020 closures, 2311 contexts, 152 repossessions), its string
heap separate at 3.98 MB. The mechanism of the 3.6x is confirmed in the
writer: an object reference is a two-byte tag plus two four-byte ints
(SC id, index), ten bytes where MoarVM writes one varint; every `writeInt`
is eight bytes, nearly all of them counts and flags; a string index is
four bytes; an object-table row is sixteen bytes.

One census (`NQP_OP_CENSUS=1`) of the same cold run: `Ops.setcodeobj`
27116 calls, `Ops.getcodeobj` 76, `Ops.scsetcode` 2. Each `setcodeobj`
attaches a code object the demand reader will have to finish at load.

Row c0, the rig's best-of-N on this tree, is the phase's first task; the
numbers above frame the design and are not the baseline row.

## User decisions (2026-09-17/18)

1. **Format scope: the full writer fix, first.** Packed references,
   varint ints, a string offset table, eight-byte table rows and the
   index-on-object, in one regen, done before the demand reader so the
   reader is written once against the final format. (Offered: minimal
   = the string offset table only; none = a load-time scan of the heap.)
2. **Section 2 as written**: barrier on the three context getters,
   publication per drain rather than per entry, one global reentrant
   lock, lazy HOW through a property getter, lazy strings, the eager
   knob and the exit stats line. (Offered: HOW eager; per-entry publish.)
3. **The fixups are not chased**; a C3 is designed only if row c2's exit
   stats show the deserialize program forcing more than half of
   CORE.c's objects. (Offered: plan the C3 now; no threshold at all.)
4. **Rows c0, c1, c2; one plan** for all three with a ledger checkpoint
   after c1; one CORE.c compile per row. (Offered: two plans; no compile
   at c2.)
5. Standing rules apply unchanged: RAKUDO_RAKUAST=1 everywhere; the
   engine build is the build; Kotlin, never Java; every debug print
   env-gated; no jar commits until told (the regenerated stage0 stays an
   uncommitted working-tree change, as the v2 jars are); no fine-grained
   gating; every gate reported with its wall time; Raku for tooling;
   evening commit stamps; the worktree is the source of truth.

## Section 1: the format (version 12) and the writer fix -- row c1

Paths relative to `nqp/src/vm/jvm/runtime/org/raku/nqp/`.

**A varint codec.** New in `sixmodel/` (there is none in the runtime):
unsigned LEB128 for indexes, counts and offsets; zigzag LEB128 for
`writeInt`'s signed longs. Reads and writes on the `ByteBuffer` the
reader and writer already hold.

**Packed references.** One encoding for object, STable and code
references: varint `(index << 1)` for the current SC, varint
`(index << 1) | 1` followed by varint `scId` for a dependency. The
`REFVAR_*` tag becomes one byte and keeps its twelve values; a
`REFVAR_OBJECT` is tag plus packed reference, four bytes for CORE.c's
largest index instead of ten. `writeObjRef`, `writeSTableRef`,
`writeCodeRef` and their readers change; nothing above them does.

**Integers and strings.** `writeInt` / `readLong` become the zigzag
varint (one byte for the counts and flags that are almost all of its
calls). `writeStr` / `readStr` write the heap index as a varint.
`writeInt32` stays fixed-width where a table row needs it.

**The string heap.** The writer emits an offset table, `entries + 1`
uint32 offsets into the string data, and drops the per-string length
prefix (length is the next offset minus this one). The header gains the
offset table's position; `stringHeapEntries` stays. Index 0 is the null
string, as now.

**Table rows.** The object row shrinks from sixteen to eight bytes:
`(stableIndex << 12) | stableScId` in one uint32 (the writer throws a
format-limit error past 4095 dependencies or 2^20 STables, neither
reachable), and the data offset with the type-object flag in bit 31. The
STable row shrinks from twelve to eight (REPR-name string index, data
offset). Closure and context rows stay (24 and 16 bytes): they are 1 %
of the blob and are read once per entry either way.

**Index on the object.** `SixModelObject` gets `scIdx: Int` (-1 when in
no SC; MoarVM's `idx_in_sc`), `STable` gets `scIdx`, and `CodeRef` gets
a separate `scCodeIdx` because a code ref lives in the code root set
and may also be in the object root set. `SerializationContext` drops its
three `Object2IntOpenHashMap` caches; `getObjectIndex` / `getSTableIndex`
/ `getCodeIndex` read the field and validate by reading the root slot
back, as `DispatchSlotCodec` already does. `repossessObject`'s linear
`indexOf` scan becomes that check. The reader's `stableIndex`
`IdentityHashMap` goes with them. The writer, which called the caches
for every reference it wrote, reads a field instead.

**Version.** `CURRENT_VERSION` 12. The reader reads 11 and 12 across the
regen build only (the new runtime runs the version-11 stage0 to compile
stage1; stage2 writes version 12; `./nqp/gradlew -p nqp jBootstrapFiles`
copies stage2 over `src/vm/jvm/stage0`, about 216 s at milestone 7).
The commit after the regen deletes the version-11 road and every
`version >= N` branch below it, so the reader is one format again. From
then on the branch builds only with the uncommitted version-12 stage0,
the same caveat the v2 artifact already carries under the jar rule.

**Row c1** is the format alone: the reader still finishes everything at
load. Expected: blob 28 MB to roughly 12 MB (object data 14.6 to about
6, STable data 4.8 to about 2, object table 4.4 to 2.2, strings
unchanged plus 54 KB of offsets), the jar 56 MB to roughly 40 MB; the
cold clock flat to a few tens of ms (the buffer is a mapped slice, so
fewer bytes per finished object is the only mechanism); the writer
inside the CORE.c compile faster, reported as a side effect. The
persisted dispatch slots retrain once: every SC stamp (the CRC of
`unit.serialized`) changes with the format, and Phase B's stamp check
drops the stale slots.

## Section 2: the demand reader -- row c2

Runtime-only: `./nqp/gradlew -p nqp :nqp-runtime:jar syncRuntimeJars`
and an eval-server restart; no setting recompiles.

**Reader lifetime.** `SerializationReader` stays alive on its
`SerializationContext` (`sc.reader`), holding the mapped slice
(`UnitStore` maps the jar read-only and the unit hands the SC its slice,
so nothing is copied and untouched pages are never read), the parsed
header, the string offset table, the lazily filled `Array<String?>`,
and one state byte per STable, object, closure and context: unread,
stubbed, read. The root arrays are allocated to their counts and left
null. No stub pass, no index map. The reader is dropped when the SC is
disclaimed (a compile's own SC) and otherwise lives as long as the SC.

**Eager at load.** `deserialize()` keeps: header dissection and its
corruption checks, dependency resolution, the static code-ref shells
(`sc.addCodeRef` for the `crCount` refs the unit's block table already
provides lazily), and the repossessions: each repossessed STable or
object is stubbed, placed in this SC's root set, queued and finished
before `deserialize()` returns, as MoarVM's `repossess` does, since it
replaces an object other SCs already hold. CORE.c has 310. The
`sc-stub` and `sc-finish` stat lines become one `sc-load` line (the
eager part) and the exit line below.

**The barrier.** `SerializationContext.getObject`, `getSTable` and
`getCodeRef` take the fast path when the root slot, read with acquire
semantics, is non-null, and otherwise call `reader.demand(kind, index)`.
A root slot holds only finished entries. During a drain, stubs live in
the reader's pending table; a demand from inside the drain (a reference
read while finishing something) stubs the entry if needed, queues it,
and returns the stub, which is right because the outermost drain
finishes everything queued before control returns to guest code. A
demand from outside a drain takes the lock, stubs and queues the entry,
drains the worklist to empty, and returns the finished entry. The
worklist takes pending STables first, then objects, closures and
contexts. The worklist belongs to the drain, not to a reader: a
reference into another SC's entry queues that entry on the same
worklist and it is finished by the same outermost drain (one lock, so
nothing across SCs needs an ordering).

**Publication.** When the outermost drain completes, every entry it
finished moves from the pending table into its root slot with release
stores, in one batch. A concurrent reader therefore never obtains an
entry whose reachable graph still holds a stub, the race a per-entry
flag leaves open (a finished object's Java fields may point at a stub
finished later in the same drain). While a drain runs, every reader
whose slot is null takes the slow road and waits on the lock. Guest
code on other threads at load time is the eval server's case, whose
runs are serialized; the design is correct without relying on that.

**Locking.** One global `ReentrantLock` on the reader's companion; the
`working` depth is the lock's hold count. The fast path takes no lock.
MoarVM's per-SC reentrant mutex is the noted alternative, not adopted.

**Finishing.** An object's stub needs its STable finished (the
RakuObject stub reads its layout from finished REPR data; the
`peekAttributeShape` road and its shape cache are deleted), so demanding
an object demands its STable first, which is what "STables first" gives.
An STable finishes as `deserializeSTableInner` does today, one publish
of its `TypeState` and a republish after REPR data, with the HOW and WHO
changes below. A closure (code index at or past `crCount`) clones its
static code ref, attaches its code object through the barrier, and
attaches its outer context by demanding the context. A context builds
its `CallFrame`, reads its lexicals through the barrier, demands its
outer, and resolves a missing outer (`resolveDeserializedOuter`) as part
of its own finish rather than in a pass over all contexts.

**Lazy HOW and WHO.** An STable's finish reads the HOW and WHO references
as (SC, index) pairs into two private fields and leaves `HOW` and `WHO`
null. `STable.HOW` and `STable.WHO` become Kotlin properties whose getter
demands on first read and whose setter clears the pending pair, so
all 29 call sites are Kotlin and keep their syntax; the KnowHOW
bootstrap's null-then-set sequence is unchanged. A type reached by a
type check (the `TypeState` cache) never pulls its metaclass, method
tables or stash. WHO is included because a stash's hash reaches every
symbol under it, which for a setting package is a large share of the
SC; it costs the same getter.

**Lazy strings.** `lookupString(i)` returns `sh[i]` or decodes it from
the offset table into `sh[i]` first. `String` is immutable and safely
published, so a racing decode is benign.

**Consumers.** Everything that reads root sets goes through the barrier
or the index field already: the engine's `WvalSite` (caches the object
per `GlobalContext` after one `Ops.wval`), `Ops.wval`, `scgetobj` and
friends, `ProgramUnit.applyLexValues` (static lexicals), the persisted
dispatch slots (`DispatchSlotCodec.obj`/`stable`, resolved at a site's
first miss, so nothing is forced at load), `NqpCodeEngine`'s frame
clone (a Truffle frame, not an SC), and the writer (`writeObjRef` needs
`ref.sc` and `ref.scIdx`; a repossessed entry's SC and index are both
rewritten). `disclaim*` walks a root array whose unread slots are null.

**Diagnostics.** `NQP_SC_EAGER=1` drains every SC in full at the end of
`deserialize()`, the old behaviour, for bisecting a demand-order bug
(as built it finishes in demand order, not the old one: Revision 1).
`NQP_SC_VERIFY=1` makes a top-level demand assert that nothing it
returns is a stub and the fast path assert the slot it returns is not
pending (as built it checks less: Revision 1 states exactly what).
Under `NQP_UNIT_LOAD_STATS=1`, a shutdown hook prints one line
per SC: `sc-demand <handle> stables=<finished>/<total>
objects=<f>/<t> closures=<f>/<t> contexts=<f>/<t> drains=<n>
ms=<demand time>`, the row's core evidence. All three are env-gated,
never bare, and the eager and verify knobs are removed at the milestone
close once the whole-`t/` gate has passed.

**Expected.** The 304 ms of stub and finish leave the load; the demand
time the fixups and the load block force comes back on the exit line;
the row's gain is the difference. The honest ceiling is the 304 ms.

## Section 3: what stays forced, tests, errors

**What the load still forces.** The unit's deserialize program calls
`setcodeobj` 27116 times in a cold run, each attaching a code object the
reader must finish then (a P6opaque with its signature, parameters and
their types); the load block's 1207 package bodies demand whatever they
touch. Phase C does not chase the fixups. **The threshold:** if row c2's
exit line shows CORE.c with more than half its objects finished after
`-e 'say 1'`, a C3 is designed then, with one candidate already known:
carry the code object in the serialized code-ref table so it attaches on
first `getcodeobj`, as MoarVM's table does, a compiler-side change to
the fixup emission and a full build. Below the threshold the fixup row
goes to the milestone close's ranking beside the bodies row.

**Persisted slots keep priority** (parent item 8) and compose without a
rule: their references resolve at a site's first miss through the
barrier.

**Tests.** `nqp/t/jvm/23-sc-demand.t`, in the style of
`22-classlib-road.t`: varint round trips at the boundaries (0, 127, 128,
-1, -64, -65, `Long.MIN_VALUE`, `Long.MAX_VALUE`), packed references for
both SC cases including an index past 2^20 in the dependency form,
strings empty and non-ASCII, the offset table's last entry; a child
process loading a precompiled module and asserting through the exit line
that only touched objects are finished, and that under `NQP_SC_EAGER=1`
every count reads total/total with the same output. The
`:nqp-runtime:test` suite keeps its serialization tests, adjusted for
the format.

**Errors.** The failure mode is a stub reaching guest code; the verify
knob is the detector, the eager knob the bisector. A REPR finish that
throws mid-drain propagates, fatal as a deserialization failure is
today; the entries it touched stay pending (never published), so a
later demand retries from the stub, never from a half-read state. A
demand for an index outside the table throws the corruption error the
eager reader throws now. A packed reference into a dependency the SC
did not declare throws as `locateSC` does now.

## Section 4: rows, gates, documents, the close

**Rows,** in `docs/superpowers/plans/2026-09-18-jvm-milestone-8-phase-c.ledger.md`,
each with its wall times:

| row | what | build | gates |
|---|---|---|---|
| c0 | the baseline on the b2b tree | none | rig (cold rakudo-e, cold nqp-e, dispatch counters, warm sanity proxy); `tools/build/sc-blob-sizes.raku` on CORE.c and BOOTSTRAP |
| c1 | the format | window `make` on the version-11 stage0, `jBootstrapFiles`, the version-11 removal commit, clean `make` | nqp suite through the eval-server sweep, rig, one CORE.c compile, blob and jar sizes |
| c2 | the demand reader | runtime jars, eval servers restarted | nqp suite, rig, one CORE.c compile, the exit line, the same nqp suite once more under `NQP_SC_EAGER=1` with identical results |

**Tools.** `tools/build/sc-blob-sizes.raku` (Raku, per the tooling rule):
the segment table above from a jar's `unit.serialized` header, versions
11 and 12. `tools/build/m7-rig.raku` parses the `sc-demand` line into
optional columns (finished/total for CORE.c, demand ms), as it learned
the census fields; its `NQP_UNIT_LOAD_STATS` positive marker stands.
`tools/build/unit-load-exclusive.raku` learns the `sc-load` stage in
place of `sc-stub` and `sc-finish` (it subtracts children by stage
name) and reports the `sc-demand` line separately, since demand time is
charged to whichever stage triggered it.

**Gates** follow the parent's section 5: the nqp suite before any
rakudo build, warm `t/01-sanity` as the proxy, no per-row `t/02-rakudo`,
`t/spec` never; the whole `t/` once at the milestone close, after the
sweep's off-heap allowance is raised. A failed benchmark run is recorded
as not gathered, never re-run.

**Documents.** This spec. One implementation plan for C0 to C2 with the
ledger checkpoint after row c1. The parent spec gets Revision 5 (Phase C
brainstormed; format scope decided; Phase B parked). The lazy-loading
spec gets Revision 6 (a pointer here; its "no format change" and
"stays eager" paragraphs are superseded in full). `docs/jvm-unit-lazy-loading.md`
gains the version-12 format, the barrier and the three knobs at the
phase close. `docs/jvm-perf-findings-2026-09.md` gets the two rows.

**The close of Phase C.** Rows c1 and c2 and the exit finding in the
ledger; the C3 decision by Section 3's threshold; the position paragraph
in `docs/jvm-truffle-only-plan.md`; memory; both trees rebased onto
their upstream mains and force-with-lease pushed to ab5tract. Then the
user decides: Phase B's parked plan B, or the milestone close.

## Risks, each with its check

1. *The fixups force most of the SC.* Check: the exit line at c2.
   Response: the Section 3 threshold, never a silent widening.
2. *Demand order changes behaviour* (a REPR finish, a closure fixup or a
   repossession assuming the eager order). Check: the nqp suite under
   `NQP_SC_EAGER=1` against the same suite without it, identical.
3. *A stub escapes* through a road that reads a root array without the
   barrier. Check: the consumer list in Section 2 was taken from a grep
   of every `getObject`/`getSTable`/`getCodeRef` caller; the verify knob
   catches what the list missed.
4. *A writer bug baked into stage0.* Check: the window build's nqp suite
   and warm sanity pass before `jBootstrapFiles`; the clean build from
   the new stage0 is gated again (milestone 7's transition rule).
5. *The lazy HOW getter on a hot road.* A null check per read. Check:
   the cold rows and the warm proxy at c2; the CORE.c compile clock.
6. *Cross-SC drains and the eval server.* One process, one lock, runs
   serialized. Check: the sweep at c2 is the multi-run case.
7. *Mapped slice lifetime.* The reader keeps the slice alive as long as
   the SC; a jar replaced under a long-lived process was already the
   eval server's restart rule.

## Done

- Rows c0, c1, c2 in the ledger with wall times; the exit line's
  finding stated, the C3 decision taken by the threshold.
- Version 12 is the only format the reader reads; stage0 regenerated
  once, uncommitted.
- `23-sc-demand.t` green; the nqp suite green with and without
  `NQP_SC_EAGER=1`; warm sanity 25/25; one CORE.c compile per row.
- The documents in Section 4 written; memory updated.

## What the next session does

`superpowers:writing-plans` for C0 to C2 as one plan, from the worktree
at rakudo `2338bc426c` / nqp `62fa7ea9f` plus this spec's commit; the
plan's tasks in this order: tools and row c0; the varint codec and
packed references in the writer; the version-12 reader (still eager) and
the index-on-object; the window build, regen, version-11 removal and
row c1; the demand reader with the barrier and batch publication; lazy
HOW, WHO and strings; the knobs, the exit line, the test and the rig
parse; row c2 and the ledger.

## Revision 1 (as built, 2026-09-19)

Phase C closed at rakudo `ebffa026a4` / nqp `dd159b2a7` (ledger:
`docs/superpowers/plans/2026-09-18-jvm-milestone-8-phase-c.ledger.md`,
rows c0-c2). Where the implementation departs from the text above:

- **The STable table row stays 12 bytes**, not the 8 Section 1 names: the
  third int (the REPR-data offset) serves `peekAttributeShape`. 22 KB of
  CORE.c's 13.5 MB; ledger ruling at C1.
- **The header stays 18 ints**; there is no new header field for the
  string offset table: `stringHeapOffset` points at the offset table,
  and the string bytes follow it.
- **Counts on the wire are zigzag varints** (`writeCount` =
  `writeInt32`), not unsigned: `writeRef` delegates container bodies to
  the REPRs, which read their counts through the signed readers, so one
  encoding serves both.
- **`peekAttributeShape` and the three-argument RakuObject
  `deserialize_stub` are kept**, where Section 2 deleted them: a
  self-referential STable (its HOW, WHAT, WHO or method cache names an
  instance of itself) is still reading when its own stash instance is
  stubbed, so the layout is not yet in hand and the shape comes from the
  serialized REPR-data header.
- **`repossess` is one drain for both kinds, and registration decides
  identity** (rewritten in the final-review fix wave, nqp tree; the
  first cut ran two passes, STables then objects, each its own drain, and
  a repossessed STable whose data named a repossessed object of the same
  SC -- a precompiled `augment class Int { multi method ... }` -- stubbed
  a fresh copy of that object from the row and published it before the
  object pass ran, so the SC's slot held a copy and the original never
  got the new data). In one `topLevel`: (1) demand every original and
  run the drain, so an original its own SC had not finished yet is
  finished whole, under its original layout, before anything is swapped
  (the pre-Phase-C order); (2) register every row of both kinds -- the
  original installed into this SC (`sc`, `scIdx`) and into the pending
  tables, concrete objects held on the drain (rolled back on a throw, not
  run); (3) finish the repossessed STables; (4) give each repossessed
  object its row's STable (a mixin may have changed it) and queue it. The
  root-slot peek stays as a defensive guard only. `nqp/t/jvm/24-sc-repossess.t`
  covers both shapes (the split, and a mixin original never read before
  the repossession).
- **A drain runs on the demanding thread's context**: `topLevel`
  resolves `gc.getCurrentThreadContext()` once (the loader's context when
  that is null) and the drain carries it; every stub and finish road, of
  any reader the drain crosses, reads its `tc` through the drain, so a
  demand from another thread never writes the loader's `nativeI/N/S`,
  builds frames on it, or raises against its frame chain. `deserialize()`
  itself (repossession, the eager drain) runs on the loader's context.
- **Closure and context outers resolve at first demand, not at load.**
  A context without a serialized outer (`resolveDeserializedOuter`) and
  a closure whose static code falls back to
  `outerStaticInfo.priorInvocation` in `clone` now resolve against the
  invocation live when the entry is first demanded rather than the one
  live at load. `NQP_SC_EAGER=1` restores load-time resolution for
  bisecting; warm `t/01-sanity` under it was run once as the check
  (ledger, "Final-review fix wave").
- **`NQP_SC_VERIFY=1` checks one thing**: that the entry a TOP-LEVEL
  demand (`demandObject`, `demandSTable`, `demandCodeRef`) returns is the
  entry now published in that root slot, i.e. that the drain published
  what it handed out. It does not test a stub for being finished, and it
  is blind to a stub a getter hands out INSIDE a drain that a caller then
  stores somewhere else (the drain publishes the same entry later, but
  nothing checks where the caller put it).
- **The demand roads and the HOW/WHO pending resolve are Truffle
  boundaries** (`demandObject`/`demandSTable`/`demandCodeRef`,
  `STable.resolvePendingHow`/`resolvePendingWho`): `NqpDispatch.HowSrc`
  reads `st.HOW` inside partially evaluated code, and the lock and the
  deserializer must stay out of it; the getters' `howField ?: ...` fast
  path stays inlineable. `setPendingHow`/`setPendingWho` write the index,
  then the SC, and only then clear the field: on the repossess road the
  STable is already published, so a concurrent getter sees either the old
  HOW or the pending pair, never null for a live type.
- **`deserialize()` drains under the global lock**, and a drain that
  throws rolls its entries back (stubs dropped, never published), so a
  later demand starts from an unread slot.
- **The eager drain and the stub roads peek the root slot first.** The
  eager-mode failure found in Task 6 was a second identity for a
  repossessed slot: stubbing an entry already published built a new
  object and published it over the first.
- **HOW/WHO resolution uses volatile pairs and never caches inside a
  drain**: the field and the pending SC are volatile (the index is
  written before the SC is set, the field before the SC is cleared; on
  the way in the field is cleared last, see the boundary bullet above), and
  a getter reached from inside a drain returns the stub without caching
  it or clearing the pair -- a rolled-back stub would otherwise stay
  cached -- so the first read outside a drain caches the published
  object.
- **The Makefile's `nqp-runtime.jar` -> `rakudo-runtime.jar` edge is a
  real prerequisite** (rakudo `ebffa026a4`): a plain `make` after an nqp
  runtime change rebuilds the Rakudo runtime jar, without a setting
  recompile.
- **`Configure.pl --no-clean` does not prevent the clean**: the option is
  stored as `no-clean` and tested as `clean` (`Configure.pl` lines 100 and
  158), so the clean always runs. Found, not fixed in this phase.

Row c2's finding (ledger, "The C3 decision"): CORE.c's exit line reads
`objects=150176/276157` (54.4 %) after `-e 'say 1'`, above the Section 3
threshold; the C3 is proposed for the user's decision, not scheduled.
