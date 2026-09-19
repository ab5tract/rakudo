# The unit artifact, version 2: mapped store, lazy bodies, site identity

Landed as milestone 7 Phase B (2026-09-15; rakudo `107eca63a3`, nqp
`318558c2d`). Plan and ledger:
`docs/superpowers/plans/2026-09-15-jvm-milestone-7-first-execution-phase-b.md`
and its `.ledger.md`. Design:
`docs/superpowers/specs/2026-09-13-jvm-lazy-unit-loading-design.md`
(phase 1) plus the Phase B section of
`docs/superpowers/specs/2026-09-13-jvm-milestone-7-first-execution-design.md`
(the fifth entry and the site identity). Numbers:
`docs/jvm-perf-findings-2026-09.md`, "Milestone 7, Phase B". The
dispatch table it wrote empty was filled by Phase C (2026-09-16; rakudo
`79829d402e`, nqp `f5c5bc8fa`) -- see "The dispatch table" below, its
plan and ledger
(`docs/superpowers/plans/2026-09-15-jvm-milestone-7-first-execution-phase-c*.md`)
and "Milestone 7, Phase C" in the findings.

v1 was one deflated `unit.meta` blob plus an LZ4'd `unit.serialized.lz4`:
opening a unit inflated everything, decoded every block's record and
every program's text, and built a full runtime table before the first
instruction ran. v2 is a **stored** zip -- nothing deflated, every entry
mappable -- read by index, on demand.

## The v2 format

Five entries, written in this order by `UnitImageWriter.write`
(`nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitImageWriter.kt`);
`unit.index` is first because `UnitStore.isUnit` sniffs the first local
file header to recognise an artifact:

| entry | holds |
|---|---|
| `unit.index` | the header and the three fixed-width tables (below) |
| `unit.records` | every `BlockRecord`, kotlinx-encoded, back to back |
| `unit.programs` | every engine program's text, raw UTF-8, back to back |
| `unit.serialized` | the serialization-context blob, raw (v1 LZ4'd it) |
| `unit.dispatch` | the persisted dispatch payloads; empty in Phase B |

`unit.serialized` is the one optional entry (a nested unit has none).
A nested unit rides in the same zip as `nested/<id>.index`,
`.records`, `.programs` and `.dispatch`; `UnitStore.nested(id)` builds a
second `UnitStore` over the same entry map with the prefix changed, so a
nested unit costs one map lookup and no copy. Nesting is one level deep,
as v1 was.

`unit.index` is: magic `NQPU` (4 bytes), version `2` (4), header length
(4), the kotlinx-encoded `UnitHeader`, then

- the **block table**, 4 little-endian ints per qbid: record offset,
  record length, program index, outer qbid. A gap is `(0, 0, -1, -1)`.
- the **program table**, 4 ints per program index: text offset, text
  length, first dispatch slot, slot count.
- the **slot table**, 2 ints per absolute slot: payload offset, payload
  length. `(0, 0)` is an empty slot.

The header carries what a shell needs without touching `unit.records`:
the unit id, HLL, SC handle and description, the serialized code-ref
count, the mainline/entry/deserialize/load qbids, the three counts, the
per-qbid `names` and `cuids` lists and the nested ids. **Every entry is
stored, and the reader keeps one mapping**: `UnitStore.open(path)` maps
the whole file read-only once and slices it per entry; every read after
that is a `ByteBuffer.slice` at an offset the index already knows.
Bounds are checked against the slice, and a violation is an
`IllegalStateException` naming the unit, the entry and the index.

## The load road

`UnitLoader.store(fn, shared)` opens the store (`open-store`), then
`ProgramUnit.initializeCompilationUnit` builds one `CodeRef` shell per
live block from the index alone (`shells`), then the deserialize program
runs (`deserialize-program`), then any static lexical values that were
queued while it ran are applied (`static-lex-drain`). Dependency loads
triggered by the deserialize program print their own stage lines one
level deeper, and their time is inside the parent's
`deserialize-program`.

There is **one** load road. An in-memory unit -- `EVAL`, `BEGIN`, a
script -- goes through the same writer: `UnitWriter.store` encodes the
compiler's record into the same stored-zip bytes on the heap and opens
them as a `UnitStore` named `<memory:<id>>`, so the code that loads a
file and the code that loads an `EVAL` are the same code.
`loadbytecodebuffer` names its store `<buffer>`.

The eval server keeps `UnitLoader.stores`, one `UnitStore` per path,
shared by every run (`prime(path)` opens one ahead of time). A store is
immutable, so nothing about it has to be forgotten between runs. **A jar
replaced on disk while mapped can fault the process**, so the server must
be restarted after a rebuild -- which it already had to be, for the jars
it had loaded.

## Lazy bodies

A shell is `StaticCodeInfo`'s second constructor: it carries the
identity a caller needs before the block is ever entered -- the
compilation unit, the method handle, the cuid, `argsExpectation`,
`staticCode`, the program index, `methodName`, and (wired in a second
pass) `outerStaticInfo` -- and a `StaticBodySource`. Everything else
(the lexical name arrays, handlers, the exit-handler and thunk flags,
source file and line, source sections, and the two bound method handles
`finishBody` spins) is filled by `ensureBody()` on first read, once,
under the instance monitor, published through a `@Volatile bodyReady`.
`argsExpectation` is read on the dispatch path before any body is
needed, which is why it is on the shell.

`ProgramUnit.BodySource.fill` decodes exactly one `BlockRecord` slice.
It writes through the plain setters, which never re-enter the fill, and
applies the block's static lexical values through two `internal` raw
accessors (`rawOLexicalIdx`, `rawSetOLexStatic`) that call no
`ensureBody` -- a body getter inside a fill would recurse unboundedly,
since the monitor is reentrant and `bodyReady` is still false. If the SC
a row names is not installed yet, the rows are queued on the unit and
drained after the deserialize program (`static-lex-drain`). v1 kept one
global static-lexical list and applied all of it at load; v2 keeps the
rows on the block that owns them, so a block that is never entered never
pays for them.

The clone road forces the body ready first and then copies, so a clone
is never a shell. Two places that used to test "same method handle"
(`CallFrame`, `Syscalls`) now test `staticInfo` identity, because `mh`
is what went lazy.

## Site identity

A program of a store-backed unit is compiled under a Source **name**
that is its identity: `"<namespace>#<program index>"`, built by
`CodeEngine.materialize` from `ProgramUnit.identityNamespace()`. The
namespace is the store's name and the unit id joined by `!` -- neither
alone identifies an artifact, because a nested unit inherits its
parent's store name and a unit id is author-supplied (`nqp --javaclass`;
Rakudo's build names `rakudo.jar` and four BOOTSTRAP jars alike
`perl6`, and that collision once ran one unit's block body in place of
another's). `NqpLanguage.parsedKey` keys `PARSED` by that name when it
parses as an identity and by the program text otherwise, so a hit never
decodes the text.

Inside a program, `NqpProgramBuilder` numbers every `DISPATCH` node by
its **wire offset** (`siteOrdinals.computeIfAbsent(at, ...)`), in walk
order of first visit: a repeat/for body is walked twice with emit, and
the offset makes the two emissions one site with one ordinal. The
ordinal rides on `NqpOps.EngineSite` as `identity.siteKey(ordinal)` =
`"<namespace>#<program index>#<ordinal>"`.

An **in-memory unit has no identity**: `isStoreBacked()` is false (its
store name starts with `<`), so its programs keep the text key -- its
unit id is a fresh sha1 per compile, and identical texts must go on
sharing one parsed root. Helper, rv-decont and indy sites are anonymous
too: they are not built from a `DISPATCH` node, so they carry a null
identity, and the schema tolerates it.

The identity string names **this process's path to the store**. It is
not a cross-process key; Phase C resolves a slot through the site's own
unit, program index and ordinal, never through the string.

## The dispatch table

`unit.dispatch` is addressed by (program index, site ordinal):
`UnitStore.dispatchSlot(programIndex, ordinal)` reads the program row's
first slot, adds the ordinal, and returns that slot's slice, or null for
an empty slot -- O(1), no decode. `ProgramUnit.dispatchSlot` is the
runtime's entry point.

The invariant that makes it addressable: **a program's slot count is the
encoder's per-block `DISPATCH` count**, carried on the compiler's
`QAST::BlockRecord` as `$!dispatches`, read by `RecordReader` into
`UnitImage.dispatchCounts` (one entry per program, required by
`UnitImageWriter`). `NQP_SITE_CHECK` is how that is checked against a
real run (below).

**Phase B wrote every slot empty; Phase C fills them** (2026-09-16,
rakudo `79829d402e`, nqp `f5c5bc8fa`). Phase C changed no index and no
other entry, so stage0 did not have to be regenerated again. The
numbers are in `docs/jvm-perf-findings-2026-09.md`, "Milestone 7,
Phase C".

### The slot schema

A filled slot is a kotlinx-serialized `DispatchSlot(schema: Int,
programs: List<PProgram>)` in `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlot.kt`,
written and read through `UnitCodec` -- the same codec the unit records
use -- with short `@SerialName`s (`arg`, `lit`, `attr`, `how`, `unbox`,
`lookup`, `type`, `conc`, `hll`, `invoke`, `syscall`, ...) and `Double`
as raw long bits.

`schema` is `DispatchSlot.SCHEMA` (2 today) and comes first precisely so
that it is the slot's first four little-endian bytes: `UnitCodec` is
untagged and fixed-width, so a slot of an older layout would not fail to
decode but decode into a plausible program, and `DispatchPersist.restore`
therefore reads that int by hand and treats any other value as an **empty
slot** (`staleSchema=` on the `dispatch stats:` line, named per site under
`NQP_DISPATCH_PERSIST_TRACE`). `staleStamp=` on that same line counts the
slots dropped one step later, after the decode: a slot names the stamp --
the CRC32 of that artifact's `unit.serialized` entry -- of every SC it
references, and if a handle this process has loaded carries a different
stamp, the whole slot is dropped, because the same handle under another
build of the artifact indexes other objects entirely (schema 2, milestone
8 Phase B). Nothing migrates: the build that reads a slot is the build
that wrote it, so bumping `SCHEMA` -- required for any change to the
`P`-types, including the declaration order of `ArgKind` or `ResumeKind`,
which persist by index -- costs one retraining run.

A `PProgram` is a `DispatchProgram` with every reference replaced by a
stable name:

- **Objects, code refs and STables** are `PRef(handle, index, kind)` --
  the serialization context's handle, the object's index in it, and the
  kind (0 object, 1 code ref, 2 STable).
- **The HLL config** is (name, `compilerSide`), because a type's
  `hllOwner` comes from whichever of the two config maps was current at
  deserialize and `Guard.OfHll` compares by identity; it realises
  through the non-creating `GlobalContext.findHLLConfig`.
- **A syscall** is its name, **a resumption's dispatcher** its id.
- **The descriptor travels inline** (`PDescriptor(flags, names)`), per
  program and per argument shape. v1's per-unit call-site table is gone
  -- `getCallSites()` returns empty and the engine builds its own
  `CallSiteDescriptor` from the wire -- so a slot cannot reference one
  by index.
- Native literals are inline (`PLiteral`).

A program whose every reference resolves is persistable; one that names
an object no serialization context owns is **not written**, and the site
behaves as it did before. On a cold `rakudo -e ''` that is 50 of 4604
programs (C0), and the 37 that still drop at restore all say `no SC
<handle>` -- an object owned by a context the run itself created.

### Training: the build fills the slots

The compiler never executes what it compiles, so the outcomes come from
running. `NQP_DISPATCH_RECORD=all` (or a comma-separated list of
store-name prefixes) arms `DispatchPersist.recordAtExit`: at exit every
site's installed programs are persisted into their unit's slot and
`UnitDispatchWriter.rewrite` rebuilds each named artifact -- index slot
rows repointed, `unit.dispatch` rebuilt, every other entry copied byte
for byte, through a tmp file and an atomic rename. Programs merge per
slot (restored plus new, deduplicated by their `DispatchDump` text,
capped at `Dispatch.MAX_PROGRAMS`), so training Rakudo after nqp does
not truncate what nqp's run wrote. A path under `src/vm/jvm/stage0` is
**refused**, whatever the selector says: stage0 is what the next build
compiles from, and the gradle build deliberately copies the untrained
stage2 into it.

The recorder runs in a shutdown hook, whose throwable the JVM prints to a
stream nobody greps while the exit status stays 0, so it contains every
failure itself: per program and per artifact, as a `dispatch-record:
FAILED ...` line, and it ends every run with one `dispatch-record: done
<n> paths, <n> slots, <n> programs, <n> unpersistable, <n> failed`. That
pair is the gate -- **both builds require the `done` line and the absence
of any `FAILED` one** -- because a run that rewrote some artifacts and
then threw satisfies the per-artifact `dispatch-record: wrote <n> slots
(<n> programs, <n> unpersistable) to <artifact>` lines just as well as a
whole run does. Each artifact is announced by `dispatch-record: rewriting
<path>` before it is touched.

Both builds train, with the trivial program (`-e ''`), because loading a
setting or a module is itself the first execution under attack:

- **nqp** (`nqp/build.gradle.kts`): a `Sync` task copies the nine stage2
  jars to `build/jvm/stage2-trained`, `trainDispatch` runs the trivial
  program against the copy with `NQP_DISPATCH_RECORD=all`, and `syncLib`
  takes the trained copy. `jBootstrapFiles` goes on copying the
  **untrained** stage2 into `src/vm/jvm/stage0`, so **stage0 stays
  empty-tabled**. `trainDispatch` is INTENTIONALLY always out of date
  (`outputs.upToDateWhen { false }`, marker at
  `build/jvm/dispatch-trained.txt`, outside the synced directory): it
  rewrites the very jars it declares as inputs, so each build's `Sync`
  restores the untrained jars and this run trains them afresh rather than
  compounding one training run onto the last.
- **rakudo** (`tools/templates/jvm/Makefile.in`): a stamp target after
  `rakudo.jar`, the three settings and the two runtime jars (so a
  runtime-only rebuild retrains) runs the trivial program the same way,
  tests the runner's exit status, greps for the markers, and then
  `touch -r`-normalises the rewritten artifacts' mtimes so that a second
  `make` is a no-op. The runner depends on the stamp. Rakudo's run
  rewrites nqp's lib jars too -- about a third of a cold run's sites are
  in them.

Training is reproduced by any clean build only up to the training run's
own execution-order nondeterminism (about 1 % of slots); the verify mode
below is the correctness net, not byte equality.

### The consumer: restore at the first miss

On a site's **first miss**, inside `Dispatch.fallback` and before the
recorder, the site resolves its slot through its own unit, program index
and ordinal (never through the identity string, which embeds this
process's store path), decodes it, realises each persisted program
against the current process's serialization contexts, **drops** any
program with an unresolvable reference, **installs** the rest and
**replays**. If no persisted program's guards pass, the ordinary miss
follows and the recorder, if it is on, sees a fresh record. This rests
on the invariant replay already rests on: a program is valid whenever
its guards pass.

`misses` therefore keeps its meaning -- a restored site's first miss is
still a miss -- and the claim is on `recorded=`. In the eval server
`reset()` empties the sites per run and each site re-arms from its slot
at its next first miss, so the benefit needs no object shared between
runs.

### Modes and verification

`NQP_DISPATCH_PERSIST` selects the mode: unset or `on` consumes slots,
`off` ignores them entirely (the artifacts are unchanged; it is the
control), and `verify` consumes nothing, records fresh at every first
miss, and compares what the site recorded against what the slot holds.

Verify compares only persisted programs that are applicable (same
shape, guards pass); an unseen persisted program is not a mismatch. The
comparison is **first by `DispatchDump` text, then by evaluated
outcome** on the recorded call's own arguments: the same outcome kind,
the same callee object by identity / the same syscall name / the same
value, the same evaluated argument capture, the same resumption
dispatchers and init captures, equal `bindControl`. A program that
matches only that way is counted `byOutcome`; only a program that fails
both is a `MISMATCH`, and the gate is `mismatched=0`.

`byOutcome` is not noise: nqp's `lang-meth-call` records a type-guarded
form before a class publishes its method cache and a cache-lookup form
after, and verify mode, by not installing, makes the site re-record
after the cache exists -- so the form differs while the target is the
same. Over the nqp suite that is 1309 of 272687 comparisons.

## Diagnostics

- `NQP_UNIT_LOAD_STATS=1` prints `unit-load: stats on` and then
  `unit-load <depth> <unit> <stage> <ms> [counts]` for the v2 stages
  `open-store`, `shells`, `sc-load`, `deserialize-program`,
  `static-lex-drain`, `load-block`, `load-total`, and at exit one
  `sc-demand` line per SC (see "Format 12 and the demand reader" below).
  Before milestone 8 Phase C the SC read was two stages, `sc-stub` and
  `sc-finish`; `sc-load` replaces both and holds only the eager part.
- `NQP_CODE_WHY=1` makes `UnitWriter.write` print one line per artifact:
  `unit artifact <id> -> <file> (N programs, N qbids, N dispatch slots,
  N nested)`. It also gates the line that reports static lexical rows
  dropped for a gap qbid.
- `NQP_SITE_CHECK=1` prints, per compiled program,
  `site-check <namespace>#<index> ordinals=N` from the engine, and from
  the runtime both `unit-check <namespace> programs=N slots=N` per
  loaded unit and `unit-check-prog <namespace>#<index> slots=N` per live
  program. All three name the unit by `identityNamespace()`, so the two
  streams join -- by prefix per unit, and exactly per program -- even
  where several loaded artifacts share one unit id.
  `tools/build/site-check.raku <stderr capture>` does that join and
  reports any program whose ordinals exceed its slots (exit 1 if any).
  The per-program line is the one that matters: `UnitStore.dispatchSlot`
  bounds the ordinal by the program's own slot count and returns null
  past it, so an undercount is silent, and the per-unit aggregate cannot
  see it.
- `NQP_DISPATCH_STATS=1` adds `sites=` and `anon=` to the shutdown
  `dispatch stats:` line. **They count WIRE dispatch sites only.** Both
  are incremented in `NqpDispatch.Cache`'s constructor, and a `Cache` is
  built in exactly one place -- `NqpOps.EngineSite`, i.e. once per
  `DISPATCH` instruction of a parsed program -- so the split is "of the
  dispatch instructions this process parsed, how many belonged to a
  program that had an identity". Cold `rakudo-j -e 'say 1'`:
  `sites=7427 anon=6`, and those six are the `-e` script's own: its unit
  is in-memory, so its programs get no identity.

  Dispatch sites that the runtime makes for itself are **not counted by
  either**: `Ops.helperDispatchSites`, Rakudo's rv-decont site in
  `RakOps.kt` and the indy road (`DispatchBootstrap.fromIndy`) each
  construct a `DispatchCallSite` directly, never a `Cache`. They are
  identity-less too. Phase C added **`sitesAll=`** for them
  (`DispatchBootstrap.created`, every `DispatchCallSite` the process
  makes): cold `rakudo -e 'say 1'` reads `sites=7463 anon=6
  sitesAll=7569`, so 106 sites are the runtime's own.

- `NQP_DISPATCH_STATS=1` also carries the Phase C counters on the same
  line: **`restored=`** (persisted programs installed),
  **`restoredSites=`** (sites that installed at least one),
  **`dropped=`** (persisted programs whose references did not resolve)
  and **`recorded=`** (programs the dispatcher had to record itself --
  the phase's headline number). Cold `rakudo -e ''` on a trained build:
  `restored=4477 restoredSites=4195 dropped=37 recorded=193`, against
  `recorded=4723` untrained. `restored=`/`restoredSites=` also count in
  `verify` mode, and all of these are process-wide: `resetAll` does not
  clear them, so a figure must name the population it covers.

- `NQP_DISPATCH_PERSIST=on|off|verify` selects the mode (unset means
  `on`; an unrecognised value also means `on`). `verify` prints a
  `matched=/byOutcome=/mismatched=/unseen=` summary at exit, plus one
  `MISMATCH` block per failure naming the site identity, the dispatcher,
  and both programs' `DispatchDump` text. The `dispatch-verify: on`
  banner is printed only under `NQP_DISPATCH_VERIFY_LOG` (to the log) or
  `NQP_DISPATCH_PERSIST_TRACE` (to stderr), never to a bare stderr by
  default; the exit summary line is unchanged.

- `NQP_DISPATCH_VERIFY_LOG=<path>` sends every verify line to that file
  instead of stderr, appended and prefixed by the writing process's pid.
  Without it, a test that compares a child process's whole stderr
  (`t/01-sanity/55-use-trace.t`) fails under `verify`, and TAP swallows
  the per-run blocks so only the exit summary survives.

- `NQP_DISPATCH_PERSIST_TRACE=1` prints `dispatch-persist: dropped
  <identity> <reason>` for every program a restore drops. On a cold
  `rakudo -e ''` that is 37 lines, all `no SC <handle>`.

- `NQP_DISPATCH_RECORD=all|<prefix>,<prefix>` is the training switch: at
  exit the process persists its installed programs into the artifacts
  whose store names match, and prints `dispatch-record: wrote ...` per
  artifact. **A training run is never a measured run**
  (`tools/build/m7-rig.raku` refuses to start with it set).

- `NQP_DISPATCH_DUMP=<path>` (from Phase C's C0 spike) prints every
  registered site and each installed program in the normalised text form
  that training deduplicates by and verify compares with.
  `tools/build/dispatch-dump-diff.raku` diffs two dumps.

## Format 12 and the demand reader (milestone 8, Phase C)

Landed 2026-09-18/19 (closed at rakudo `ebffa026a4` / nqp `dd159b2a7`).
Spec: `docs/superpowers/specs/2026-09-18-jvm-milestone-8-phase-c-sc-demand-design.md`
and its "Revision 1 (as built)"; plan and ledger:
`docs/superpowers/plans/2026-09-18-jvm-milestone-8-phase-c-sc-demand.md`
and `2026-09-18-jvm-milestone-8-phase-c.ledger.md`. Numbers:
`docs/jvm-perf-findings-2026-09.md`, "Milestone 8, Phase C". This is
phase 2 of the lazy-loading design (SC demand deserialization); the
`unit.serialized` entry is still handed to `SerializationReader` as a
mapped slice, and the reader now keeps it for the SC's life.

### The version-12 layout

Little-endian; header unchanged: 18 ints, `stringHeapOffset` now points at
the offset table (the Task 4 list, verbatim, with the as-built note on the
STable row):

- object reference, STable reference, code reference: varint `(idx << 1)` for the current SC; varint `(idx << 1) | 1` then varint `scId` (1-based dependency index) otherwise;
- `writeRef`: one tag byte (the `REFVAR_*` values 1..12 unchanged), then per tag: NULL/VM_NULL nothing; OBJECT a packed reference; VM_INT zigzag varint; VM_NUM 8-byte double; VM_STR varint heap index; VM_ARR_VAR varint count then refs; VM_ARR_STR varint count then varint heap indexes; VM_ARR_INT varint count then zigzag varints; VM_HASH_STR_VAR varint count then (varint key index, ref) pairs; STATIC_CODEREF/CLONED_CODEREF a packed reference;
- `writeInt` zigzag varint; `writeInt32` zigzag varint; `writeNum` 8 bytes; `writeStr` varint heap index;
- STable row 12 bytes as before (REPR-name index, data offset, REPR-data offset -- the third int serves `peekAttributeShape` until Task 6 deletes it; 22 KB, kept; ledger ruling);
- object row 8 bytes: `(stableIdx << 12) | stableScId`, then `dataOffset` with bit 31 set for a type object;
- closure row 24, context row 16, repossession row 16, dependency row 8: unchanged, raw ints;
- string heap: `entries + 1` uint32 offsets (offsets[0] = 0, offsets[entries] = total bytes) then the UTF-8 bytes back to back; index 0 is the null string and has no offset entry; string `i` (1-based) is bytes `offsets[i-1] until offsets[i]`.

As built, Task 6 did **not** delete `peekAttributeShape`: a
self-referential STable is still reading when its own stash instance is
stubbed, so the STable row stays 12 bytes and the three-argument RakuObject
`deserialize_stub` stays with it. Counts written by `writeCount` are the
same zigzag varint as `writeInt32`, because `writeRef` hands container
bodies to the REPRs, which read them with the signed readers.

The index lives on the entry: `SixModelObject.scIdx`, `STable.scIdx`, and
`CodeRef.scCodeIdx` (a code ref is in the code root set and may also be an
object root); `getObjectIndex` and friends read the field and check it
against the root slot. There are no index caches on the SC any more.

### The barrier, the drain, publication

A null root slot demands: `SerializationContext.getObject`, `getSTable`
and `getCodeRef` return the slot when it is set and otherwise call the
reader's `demandObject`/`demandSTable`/`demandCodeRef`. A demand takes the
one process-wide `SerializationReader.LOCK` and runs a drain that finishes
the transitive closure of what it stubs -- across SCs, on one worklist --
before it returns. Publication is per drain: the entries a drain finished
move into their root slots together when the outermost drain completes, so
no thread sees a published entry whose graph still holds a stub; a drain
that throws rolls its entries back instead, and a later demand starts again
from the unread slot.

**STables are finished immediately, objects are queued.** Stubbing an
STable finishes it on the spot (its REPR data included; a cycle through
its own REPR data gets the partly built STable, as before, with
`peekAttributeShape` supplying a RakuObject stub's shape). An object's stub
needs its STable finished first; a concrete object's body is then queued on
the drain, and a type object is done at its stub. A closure clones its
static code ref at its stub and attaches its code object and outer context
through the barrier; a context's lexicals are queued. Every stub road peeks
the root slot first: stubbing an already-published entry would build a
second identity for it (the eager-mode bug Task 6 found, on a repossessed
slot).

**Eager at load** (`sc-load`): the header and its corruption checks, the
dependency resolution, the static code-ref shells, the root arrays sized
and left null, and the repossessions -- every repossessed slot registered
before any is finished, slots already published skipped -- all under the
lock.

**HOW and WHO pending.** A finished STable holds its HOW and WHO as
(SC, index) pairs; `STable.HOW`/`STable.WHO` are properties whose getter
resolves the pair on first read, so a type reached only by a type check
never pulls its metaclass or stash. The pair and the field are volatile; a
getter reached from inside a drain returns the stub without caching it (a
rolled-back stub would stay cached), and the first read outside a drain
caches the published object.

**Lazy strings.** `deserializeStringHeap` reads nothing; `lookupString(i)`
decodes string `i` from the offset table on its first lookup and keeps it.

### Knobs and the exit line

- `NQP_SC_EAGER=1` drains every SC in full at the end of `deserialize()`,
  the pre-Phase-C order, for bisecting a demand-order bug.
- `NQP_SC_VERIFY=1` makes a top-level demand assert that nothing it
  returns is a stub, and the fast path that the slot it returns is not
  pending.
- Under `NQP_UNIT_LOAD_STATS=1` the SC's load is one `sc-load` stage line
  (the eager part only), and a shutdown hook prints one line per SC:

  ```
  sc-demand <handle> stables=<f>/<t> objects=<f>/<t> closures=<f>/<t> contexts=<f>/<t> drains=<n> ms=<demand time>
  ```

  The demand time is charged to whichever stage triggered it, so
  `tools/build/unit-load-exclusive.raku` prints these lines after its
  table rather than in it, and `tools/build/m7-rig.raku` reports CORE.c's
  as `scObjects= scStables= scDrains= scMs=`. Cold `rakudo-j -e 'say 1'`
  (row c2): `stables=3901/5558 objects=150176/276157 closures=9059/11800
  contexts=1354/2575 drains=9644 ms=138.59` -- 54.4 % of CORE.c's objects
  finished by the time the program exits.

The eager and verify knobs are removed at the milestone close, after the
whole-`t/` gate.

### Sizes before and after

`tools/build/sc-blob-sizes.raku` reads a jar's `unit.serialized` header.

| | format 11 | format 12 | delta |
|---|---|---|---|
| CORE.c `unit.serialized` | 28,167,619 | 13,488,797 | -52.1 % |
| BOOTSTRAP `unit.serialized` | 4,216,191 | 1,563,293 | -62.9 % |
| `blib/CORE.c.setting.jar` | 56,412,944 | 41,737,626 | -26.0 % |

CORE.c by segment: STable data 4.84 -> 1.76 MB, object table 4.42 ->
2.21 MB (16-byte rows became 8), object data 14.61 -> 5.34 MB, context data
176 -> 65 KB, strings unchanged (3.72 MB, the length prefixes became a
53.6 KB offset table). Every count is unchanged.
