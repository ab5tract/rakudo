# The unit artifact, version 2: mapped store, lazy bodies, site identity

Landed as milestone 7 Phase B (2026-09-15; rakudo `107eca63a3`, nqp
`318558c2d`). Plan and ledger:
`docs/superpowers/plans/2026-09-15-jvm-milestone-7-first-execution-phase-b.md`
and its `.ledger.md`. Design:
`docs/superpowers/specs/2026-09-13-jvm-lazy-unit-loading-design.md`
(phase 1) plus the Phase B section of
`docs/superpowers/specs/2026-09-13-jvm-milestone-7-first-execution-design.md`
(the fifth entry and the site identity). Numbers:
`docs/jvm-perf-findings-2026-09.md`, "Milestone 7, Phase B".

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
an empty slot -- O(1), no decode. `ProgramUnit.dispatchSlot` is Phase
C's entry point. **Every slot is empty in Phase B**: the table exists so
that stage0 regenerates once, in Phase B, and never again in this
milestone, since an empty table is valid under any payload schema.

The invariant that makes it addressable: **a program's slot count is the
encoder's per-block `DISPATCH` count**, carried on the compiler's
`QAST::BlockRecord` as `$!dispatches`, read by `RecordReader` into
`UnitImage.dispatchCounts` (one entry per program, required by
`UnitImageWriter`). `NQP_SITE_CHECK` is how that is checked against a
real run (below).

Phase C writes the descriptor **inline in the slot**. v1's per-unit
call-site table is gone (`getCallSites()` returns empty; the engine
builds its own `CallSiteDescriptor` from the wire), so a slot cannot
reference one by index.

## Diagnostics

- `NQP_UNIT_LOAD_STATS=1` prints `unit-load: stats on` and then
  `unit-load <depth> <unit> <stage> <ms> [counts]` for the v2 stages
  `open-store`, `shells`, `sc-stub`, `sc-finish`, `deserialize-program`,
  `static-lex-drain`, `load-block`, `load-total`.
- `NQP_CODE_WHY=1` makes `UnitWriter.write` print one line per artifact:
  `unit artifact <id> -> <file> (N programs, N qbids, N dispatch slots,
  N nested)`. It also gates the line that reports static lexical rows
  dropped for a gap qbid.
- `NQP_SITE_CHECK=1` prints, per compiled program,
  `site-check <namespace>#<index> ordinals=N` from the engine, and per
  loaded unit `unit-check <namespace> programs=N slots=N` from the
  runtime. Both name the unit by `identityNamespace()`, so the two join
  by prefix even where several loaded artifacts share one unit id.
- `NQP_DISPATCH_STATS=1` adds `sites=` and `anon=` to the shutdown
  `dispatch stats:` line: how many dispatch sites carried an identity
  and how many did not. Cold `rakudo-j -e 'say 1'`: `sites=7427 anon=6`.

## What phase 2 will do

Phase 2 of the lazy-loading design is SC demand deserialization: today
the whole `unit.serialized` blob is read at load, and it is the largest
entry of a big artifact (28.2 MB of CORE.c's 56.1 MB). v2 already hands
that entry to `SerializationReader` as a mapped slice
(`ProgramUnit.serializedBlob()` -> `UnitStore.serialized`; the reader
sets its own byte order and never calls `array()`), so the bytes a
demand-driven reader needs are mapped and addressable without another
format change. See
`docs/superpowers/specs/2026-09-13-jvm-lazy-unit-loading-design.md`,
"Phase 2".
