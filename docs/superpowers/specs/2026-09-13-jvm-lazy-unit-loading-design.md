# Lazy unit loading: artifact v2, lazy tables, SC demand deserialization

Design, 2026-09-13. Approved in chat the same day, section by section.

Position: milestones 1-6 of the unit-artifact road are closed. Milestone 6
established that the JVM backend's cold start is artifact decoding, not class
loading: a Native Image removed class loading and still started 1.46x slower
(`docs/jvm-perf-findings-2026-09.md`). The milestone-6 design named a per-stage
load profile as a later task (its Task 7) and it was never run. This design
starts there.

Measured starting points (recorded 2026-09-10 to 2026-09-12, not re-measured
here): cold `nqp-j -e 'say(1)'` 1.93 s wall / 9.8 s CPU, of which JVM boot is
about 0.1 s; cold `rakudo-j -e 'say 1'` 3.66-4.10 s.

## Goal

Make loading a unit artifact lazy, so that a program pays only for the parts of
`nqp.jar`, `rakudo.jar` and the CORE settings it actually touches. Small-program
cold start is the design centre; build throughput gains whatever falls out of
it.

## Today's load path (what is eager)

Every load step is eager except engine program parsing, which already happens
on a block's first call (`CodeEngines.materialize`). Paths are relative to
`nqp/src/vm/jvm/runtime/org/raku/nqp/`.

- **Envelope.** The jar is opened twice (`runtime/unit/UnitLoader.kt:22-26`,
  `:37-39`), read whole, and every entry inflated in sequence
  (`runtime/unit/UnitZip.kt:88-104`).
- **`unit.meta`.** Hand-rolled little-endian binary with no per-block index
  (`runtime/unit/UnitFormat.kt:16-101`), so every block record, call site and
  static lexical row is decoded up front. About 6 MB for CORE.c.
- **`unit.programs`.** One LZ4 blob; every program becomes a `String` at load
  (`UnitFormat.kt:112-116`) although each is parsed only when first called.
- **Nested units.** Meta and programs decoded whether or not they are claimed
  (`UnitZip.kt:96-112`).
- **Block table.** `ProgramUnit.buildTable` builds a `CodeRef` + `StaticCodeInfo`
  per block, about three `MethodHandles.insertArguments` bindings each, plus a
  `CallSiteDescriptor` per call site (`runtime/unit/ProgramUnit.kt:28-109`,
  `runtime/StaticCodeInfo.kt:~246-275`).
- **SC.** `SerializationReader.deserialize()` stubs and then finishes every
  STable, object, closure and context (`sixmodel/SerializationReader.kt:92-153`).
  There is no demand hook: `SerializationContext.getObject` is an array read.
- **Dependencies.** Each dependency unit repeats all of the above, recursively.
- **Eval server.** `UnitLoader.prime` caches parsed records only; every request
  rebuilds tables and deserializes in full.

MoarVM, for comparison, keeps the SC reader alive and finishes objects on first
touch (`MVM_serialization_demand_object`/`_stable`/`_code`,
`src/6model/serialization.c`), and finishes a static frame's bytecode only on
first invoke (`MVM_bytecode_finish_frame`, `src/core/bytecode.c`).

## User decisions (2026-09-13)

1. **Design centre: small-program cold start first**, build throughput second
   (option C).
2. **kotlinx.serialization, lazy-friendly.** Metadata is split into small
   records, each serialized on its own with kotlinx, behind an index of our own
   that gives random access (option C).
3. **One spec, two phases.** SC demand deserialization is phase 2 of this
   design, so the phase-1 format and tables already leave room for it (option B).
4. **Transition window, then v1 is removed.** One build reads v1 and v2 and
   writes v2; stage0 is regenerated from it; the v1 reader is deleted (option A).
5. **Absolute clocks as the done-criterion** (option B): cold
   `nqp-j -e 'say(1)'` under 1.0 s and cold `rakudo-j -e 'say 1'` under 2.0 s
   once both phases have landed.
6. **Approach 2: lazy tables inside today's runtime classes plus a
   memory-mapped store.** The mapping is part of the design, not a phase-0
   decision.
7. **Measure first, then rank** (standing rule, 2026-09-10): phase 0 profiles
   the current path before any format change and ranks the work inside phases
   1 and 2.

## Phase 0: measure

### Task 0.1 — per-stage timers

Timers gated by `NQP_UNIT_LOAD_STATS=1` (off by default, per the logging rule) around
each step of the current load path: envelope open and read, `unit.meta` decode,
program text decode, `buildTable`, SC deserialize (split into stub and finish),
each dependency load, and the unit's load blocks. Output goes to stderr, one
line per stage per unit, with unit id, elapsed time and item counts (blocks,
programs, STables, objects).

Per the fail-fast rule, the timers are first smoke-tested on a sub-30 s run and
must print a positive marker before any longer run relies on them.

### Task 0.2 — the profile

For each of cold `nqp-j -e 'say(1)'`, cold `rakudo-j -e 'say 1'`, and one
ordinary `t/01-sanity` file run cold:

- the per-stage timer lines, best of 5 runs;
- one JFR recording, to catch cost outside the instrumented stages;
- per unit: artifact size today (compressed) and projected size with every
  entry stored uncompressed.

Runs use the stock runners, never the eval server (it disables Truffle
compilation for its children).

### Task 0.3 — rank and record

A short findings section in the implementation plan's ledger: the share of each
cold-start clock taken by each stage, and the resulting order of work inside
phases 1 and 2. Phase 0 does not reopen the decisions above.

## Phase 1: artifact v2 and lazy tables

### Task 1.1 — direct-field survey

List every direct read of `StaticCodeInfo` and `CodeRef` fields
(`@JvmField` and Kotlin properties without getters) across
`nqp/src/vm/jvm/runtime`, `nqp/nqp-truffle/src` and rakudo's
`src/vm/jvm/runtime` (`RakOps`, `Binder`). For each field, record whether
every read is already dominated by one of the barrier call sites in Task 1.4.
The survey decides which fields stay raw fields and which become accessors
that call `ensureBody()`.

### Task 1.2 — the store

Jar entries are written **stored** (uncompressed), still inside a zip, so
`isUnit` sniffing and jar tooling keep working. `UnitStore` opens the file once
through a `FileChannel`, reads the zip central directory, finds each entry's
data offset from its local header (30 bytes plus name and extra lengths), and
maps each entry as a read-only `MappedByteBuffer` slice.

| Entry | Contents | Encoding |
|---|---|---|
| `unit.index` | Header record, then fixed-width offset tables | Header via kotlinx; tables as little-endian `(offset, length)` pairs, so lookup by index is O(1) without decoding |
| `unit.records` | One `BlockRecord` per block (name, cuid, outer, lexical name arrays, handlers, flags, source and `#line` sections, program index, its own static lexical values); one `CallSites` record; one `NestedUnit` header per nested unit | kotlinx, each record decodable on its own |
| `unit.programs` | Program texts back to back | Raw UTF-8, addressed through `unit.index`; no kotlinx |
| `unit.serialized` | The SC bytes, today's 6model format, not LZ4-compressed | Unchanged format, mapped for phase 2 |

The header holds magic `NQPU`, version 2, unit id, HLL, SC handle and
description, `serializedCodeRefCount`, the mainline, entry, deserialize and load
block ids, and the record counts.

Nested units use the same layout under `nested/<id>.index`,
`nested/<id>.records` and `nested/<id>.programs`, mapped only when claimed.
They carry no SC, as today.

### Task 1.3 — the codec

kotlinx.serialization core with a custom binary `Encoder`/`Decoder` pair, not
the ProtoBuf or CBOR modules:

- primitives match today's `unit.meta` (little-endian fixed-width ints,
  length-prefixed UTF-8, -1 for null);
- the decoder reads directly from a `ByteBuffer` slice, with no copy into a
  `ByteArray`;
- only kotlinx's stable core API is used.

Build changes: the `plugin.serialization` compiler plugin on `nqp-runtime`, and
`kotlinx-serialization-core` as a runtime jar, added to `NqpDeps`' allowlist
(`nqp/buildSrc/src/main/kotlin/NqpDeps.kt`, which rejects unknown runtime jars)
and to the generated runner classpaths.

### Task 1.4 — lazy runtime tables

Three layers, each built on first need.

1. **Shells.** A `CodeRef` + `StaticCodeInfo` shell holds identity only: qbid,
   unit, name, program index. `lookupCodeRef(qbid)` builds it. Each table slot is
   filled with compare-and-set; a thread that loses the race adopts the winner's
   object, so shell construction must have no side effects. The first
   `serializedCodeRefCount` shells are built before SC deserialization, because
   the reader installs them.
2. **Bodies.** A `StaticCodeInfo` body (lexical name tables, handlers, source
   info, outer link, the `MethodHandle` bindings, static lexical values) is
   decoded from its `BlockRecord` by one `ensureBody()`, synchronized on the
   static info as `CodeEngines.materialize` is. It is called at the entry points
   that need a body: frame creation; invocation entry (`ProgramEntry`, and the
   dispatcher's direct and engine roads); lexical lookup by name; and the
   reflection ops (`getstaticcode`, `ctxlexpad`, backtraces). The fast path is
   one volatile read. Outer links resolve inside `ensureBody()`, so no chain is
   forced up front.
3. **Unit-level tables.** A `CallSiteDescriptor` is built per index on first
   use. Programs are decoded from `unit.programs` by index. The engine's
   `programs` cache in `CodeEngines` is keyed by (unit, program index), so a
   lookup never builds the program text. Nested units are mapped and indexed
   when claimed.

**Static lexical values** reference SC objects. A body filled after
deserialization applies its values at once. A body filled during
deserialization (closure and context fixups can force one) is queued, and the
queue is applied when deserialization completes, which preserves today's
`applyStaticLexValues` ordering.

`nqp/src/vm/jvm/runtime` has no `@TruffleBoundary` (milestone 6), so the slow
path of `ensureBody()` stays outside compiled engine code: its call sites are
the existing boundary-marked entry points, and the runtime gains no Truffle
dependency.

### Task 1.5 — eval server

The mapped `UnitStore` is immutable and shared process-wide, replacing the
parsed-record cache (`UnitLoader.kt:16`). Each run still builds its own shells
and bodies on demand.

### Task 1.6 — the transition

Following the stage0 rule in the worktree's `CLAUDE.md`:

1. **Window build.** The reader dispatches on magic and version: v1 to today's
   `UnitFormat`, v2 to `UnitStore`. The writer emits v2 only. Full gate.
2. **Stage0 regeneration.** `./nqp/gradlew -p nqp jBootstrapFiles` from the
   window build, the last compiler that reads v1 and writes v2. Clean nqp build
   from the new stage0. Full gate.
3. **v1 removal.** `UnitFormat` and `UnitZip`'s v1 path are deleted. Clean build.
   Full gate.

## Phase 2: SC demand deserialization

No format change and no stage0 step; the SC reader and runtime only.

**Stays eager** in `SerializationReader.deserialize()`: header and string heap;
dependency resolution; installing the phase-1 code-ref shells; repossession
(it replaces objects in other SCs and cannot wait); stubbing every STable and
object, which gives each its identity but no contents.

**Becomes demand-driven:** finishing STables and objects, closures, and the
contexts and outer links they need. The reader stays alive on its
`SerializationContext`, holding the mapped `unit.serialized` slice, the string
heap, and per-index state (stub, finishing, finished) for STables, objects and
code refs.

**The barrier.** `SerializationContext.getObject`, `getSTable` and `getCodeRef`,
and so `wval`, check a volatile finished state and otherwise call
`reader.demand(kind, index)`. A demand drains a worklist: finishing an object
forces its STable first, and every object reference read while finishing
(`readObjRef`) enqueues its target instead of returning a stub. When control
returns to user code, everything reachable from what was touched is finished
and nothing unreachable has been read; user code never sees a stub. Closures and
their contexts are demanded with their code ref.

**Locking.** One global deserialization lock, not one per SC. A worklist crosses
SCs (an object in CORE.c's SC can reference one in a dependency's), and per-SC
locks would need an ordering across threads. The fast path takes no lock.

**Engine.** A `WvalSite` resolves through `getObject` once and caches the
finished object, so compiled code never reaches the barrier.

**Diagnostic.** `NQP_SC_EAGER=1` drains every SC at load, as today, for
bisecting a demand-order bug. It is removed once phase 2 has passed a full gate.

## Out of scope

- Eval-server sharing of decoded records or bodies across runs (a later cache
  on top of `UnitStore`).
- Rakudo module precompilation beyond what unit loading already covers.
- Making setting compilation idempotent (milestone 7's "one JVM for several
  compiles" probe).
- Compression of stored entries. Phase 0 records the size cost; reducing it is a
  later decision.

## Errors

- A malformed or truncated v2 entry is a hard error naming the unit, entry and
  index. There is no fallback to eager or to v1 after the window build.
- A demand reached in the middle of repossession, or into a dependency SC that
  is not loaded, dies naming the SC handle and object index. As today, a demand
  never triggers a load.

## Gates

Before any task lands, in cost order:

1. The nqp suite through `tools/build/evalserver-sweep.raku --suite=nqp
   '--chunk=*'`, fully green (154 files, green 2026-09-13).
2. Rakudo `make`, only after step 1 is green.
3. `t/01-sanity`, 25/25.
4. A named subset of `t/` chosen from the milestone-5 baselines, recorded in the
   plan. No `t/spec` (30-minute `t/` rule).
5. Phase 2 only: the whole gate once more with `NQP_SC_EAGER=1`, with identical
   results.

The two cold-start benchmarks (best of 5, stock runners) are re-run at every
phase close and recorded with the per-stage timers. After phase 1 the numbers
are reported without pass/fail; the targets are checked at phase 2 close.

## Risks

- **Direct field reads.** A read that bypasses `ensureBody()` sees a shell and
  fails far from the cause. Task 1.1 exists for this; any field whose readers
  cannot all be dominated becomes an accessor.
- **Stored entries inflate artifacts.** CORE.c grows most. Measured in phase 0;
  accepted by decision 6.
- **Demand order changes behaviour.** Deserialization side effects in REPR
  finishing, closure fixups or repossession may assume the eager order. The
  `NQP_SC_EAGER` gate run is the check.
- **Memory-mapped files and deletion.** A mapped jar replaced during a build
  while a long-lived process maps it can fault. The eval server is the exposed
  case; it must be restarted after a rebuild, which it already requires.
- **Stage0 regeneration.** A v2 writer bug would be baked into stage0. The
  window build's full gate runs before regeneration, and the clean build from
  the new stage0 is gated again.

## Documentation

- New `docs/jvm-unit-lazy-loading.md`: the v2 format, the three laziness layers,
  the SC barrier, and the diagnostic.
- `docs/jvm-eval-server.md`: a note that mapped stores are shared across runs.

## Done

- Phase 2 has landed and every gate passes, including the `NQP_SC_EAGER` run.
- Cold `nqp-j -e 'say(1)'` best of 5 is under 1.0 s and cold
  `rakudo-j -e 'say 1'` best of 5 is under 2.0 s.
- The v1 reader and the `NQP_SC_EAGER` diagnostic are gone.
- The documentation above is written.
