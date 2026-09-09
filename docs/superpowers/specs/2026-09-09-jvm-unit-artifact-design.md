# JVM unit artifact: a compilation unit without a class file

Design for items 5 and 6 of `docs/jvm-truffle-only-plan.md` (2026-09-09).
Item 5: a `CompilationUnit` that maps block ids to code objects without
reflection. Item 6: a per-unit artifact of engine programs plus serialized
context, with no class file. Approved section by section on 2026-09-09.

## Why now

The strict campaign (plan item 7) reached zero encoder refusals in nqp and
zero in CORE.c. What remains non-encoded is not coverage: Compiler.nqp's
per-unit wrapper blocks (deserialize, load, main, and their immediate
children), and the two Raku shapes (custom_args routine bodies, exit
handlers) whose clean answer wants the artifact to exist. Every remaining
piece of the class-file road (the program sidecar and its grapheme framing,
the string-constant road and its size gate, the reflected block table, the
per-block JVM stub, the class loaders) exists only because a unit is still a
JVM class. This design replaces the unit; deletion (item 8) follows.

## Decisions taken

| decision | choice |
|---|---|
| sequencing | bilingual loader first: the class road keeps working while the artifact road is built; stage0 flips last, once a stage2 compiler can regenerate it |
| container | a zip with fixed entry names (`unit.meta`, `unit.programs`, `unit.serialized.lz4`, `nested/<id>.*`), no class entries; the `.jar` extension and every jar consumer stay as they are |
| milestone 1 | nqp stage2 as artifacts, t/nqp green through the runner (the eval server is milestone 3's vehicle) |
| approach | artifact-native unit; Compiler.nqp remains the driver for milestone 1 and the JAST tree is read as a record; a direct QAST walk and the JAST deletion are a later step |
| language | Kotlin for everything new (user rule) |
| framing | by byte, never by grapheme (the sidecar lesson) |

## 1. The artifact format

A unit is a zip. Entries, by fixed name, and `unit.meta` is always the
FIRST entry: an in-memory sniff reads only the first local file header to
tell an artifact from a class-road jar (final review, 2026-09-09):

- `unit.meta`: a binary record, little-endian, with a magic and a format
  version. Fields: the unit id (the sha1 or `--javaclass` name; the unit's
  identity string everywhere a Class object was); the HLL name; the SC
  handle, its description and the serialized code-ref count; the mainline,
  entry, deserialize and load qbids (-1 when absent); the call-site table
  (per descriptor: argument flags, named-argument names); the block table;
  the static lexical values (per block: name, SC handle, SC index, flags;
  this replaces the `setup_blv` string program); the nested unit ids.
- `unit.programs`: the wire programs. A count, then per program a byte
  length and UTF-8 bytes. The whole entry is LZ4-compressed with the same
  length-prefixed framing the serialized blob uses.
- `unit.serialized.lz4`: the serialized context, format unchanged.
- `nested/<id>.meta`, `nested/<id>.programs`: one pair per BEGIN-time nested
  unit. A nested unit carries no SC of its own; its objects live in the
  enclosing unit's SC, as today.

The block table is indexed by qbid and tolerates gaps (a qbid with no block
exists today for a block that registered static lexical values but was not
compiled into the unit). A present block records: name; cuid (only when the
unit is nested, matching today's `$*EMIT_CUIDS` rule); outer qbid; the four
lexical-name lists; the flat handler table; the exit-handler and thunk
flags; source file, line and the section tables; and the index of its
program in `unit.programs`.

Strings are UTF-8 with byte-length prefixes; integers are fixed-width.
One Kotlin file (`UnitFormat.kt`, in nqp-runtime) owns reading and writing
and carries the single version constant. An unknown version is a hard
error, never a fallback. The wire-program format keeps its own version in
the program header; the two evolve independently.

## 2. The unit object and the loader (item 5)

### ProgramUnit

A Kotlin class subclassing the existing `CompilationUnit`, so the engine's
frame argument 0, every `cu.` call in the runtime, and `lookupCodeRef(qbid)`
(the engine's single hard dependency on the unit, wire op CODEREF) keep
their types and behaviour. Its initialization does no reflection: it walks
the block table and builds one `StaticCodeInfo` and one `CodeRef` per
present qbid, resolves outers by qbid inside the table exactly as
`initializeCompilationUnit` does today, and installs the call-site table,
HLL config, and entry ids from the meta record. The abstract hooks that
used to be generated methods (`getCallSites`, `hllName`, `mainlineQbid`,
`entryQbid`, `deserializeQbid`, `loadQbid`, `serializedCodeRefCount`)
become plain overrides.

### Entering a block

The JVM stub's prologue and postlude (create the CallFrame when the
program needs one, run, leave, control exceptions propagate, anything else
is the internal-error report) become one Kotlin entry function shared by
every artifact block. Each block gets its own method handle bound to that
function and to its own `StaticCodeInfo`, so:

- the existing invoke road (`ArgsExpectation.invokeByExpectation` on
  `staticInfo.mh`) works unchanged;
- `CallFrame.outerFor`'s identity test (method-handle identity plus unit
  identity) keeps working, because every block's handle is distinct;
- every artifact block reports the raw-args expectation (an engine program
  binds its own parameters from the raw capture), which is the shape the
  dispatchers' direct road already requires.

The engine call target is parsed lazily on first entry, but
`StaticCodeInfo` can materialize it on demand from the unit and program
index, so the dispatchers' direct road opens at load time rather than after
a first run through the stub. The continuation resume road does NOT go
through the entry function: an engine program that suspends pushes the
engine's own resume handle (`NqpCodeEngine.RESUME`) onto the save stack,
so the block's `mhResume` is never invoked; `ProgramEntry`'s doc is the
accurate description (final review, 2026-09-09).

### Deserialize, load and main are ordinary programs

The generated deserialize QAST stays exactly as Compiler.nqp generates it:
dependency-load tasks, SC creation and description, nested-unit claims,
the deserialize op, the orphan code-ref blocks, code-object fixups, the
HLL's fixup tasks, static lexical values, and the HLL's repossession
conflict resolver. What changes: on the artifact road these wrapper blocks
are declaration blocks that the encoder takes like any other, and their
qbids are recorded in the meta as the deserialize, load and entry ids. The
loader invokes them through the entry function. Nothing about
deserialization is reimplemented in Kotlin. The `deserialize` op reads the
blob from the unit object instead of a class resource. The ops those blocks use (`createsc`, `scsetdesc`, `deserialize`,
`jvm-claim-nested`, `jvm-finish-nested`, `setcodeobj`) turned out to need
no new encoding: the encoder's generic classlib road covers them; the one
addition the build forced was `QAST::VM` nodes (the `jvm` alternative, as
`as_jast` takes it). `setup_blv` is not emitted on the artifact road; its
rows go to the meta table, built right after the deserialize wrapper
compiles (after `nqp::serialize`).

### The loader

`LibraryLoader` recognizes a `unit.meta` entry in a jar and takes the
artifact road (`UnitLoader.kt`); any other jar or class file takes the
class road unchanged. That check is the whole bilingual switch. A file
with a `unit.meta` never falls back to the class road. Nested units are
built from their `nested/<id>` entries and claimed by cuid exactly as
`jvmclaimnested` does now, asking the parent unit for the nested unit by
id instead of `Class.forName`. The eval server's shared-unit map keys on
the unit id string. A runtime compile constructs the same `ProgramUnit` in
memory from the same record, with no zip and no class definition
(milestone 2).

## 3. The writer (milestone 1 shape)

Compiler.nqp remains the driver: qbid assignment, the per-block walk that
calls the encoder, the serialization of the SC, the code-ref table order,
the call-site table. At the end of a unit, instead of handing the JAST
tree to the bytecode assembler, `HLL::Backend::JVM` hands it to a Kotlin
`UnitWriter` (nqp-runtime, beside the jast2bc writer it replaces) that
reads the tree as a record and writes the zip. It reads:

- each method's code-ref fields (name, cuid, outer, the lexical-name
  lists, handlers, flags, source info) plus one new field, the block's
  program index;
- the programs as a list (`@*ENGINE_PROGRAMS`); the joined, grapheme-counted
  sidecar string is no longer built;
- the serialized blob;
- the call-site data, kept as data on the class record instead of being
  emitted as bytecode that builds the descriptor array.

Instruction lists are ignored. The wrapper blocks are emitted as
declaration blocks on this road.

Eligibility: the knob (`NQP_UNIT=1` during the bilingual period) is
all-or-nothing. With it on, a jar-bound comp-mode unit is written as an
artifact, and a block that would fall back to bytecode is a compile error
at Compiler.nqp's fallback junction, naming the block and cuid and
pointing at `NQP_CODE_BAIL`/`NQP_CODE_WHY` for the reason (the same rule
`NQP_CODE_STRICT` applies). The class road is chosen by leaving the knob
off, which is how Rakudo builds in milestone 1. There is no per-unit
fallback from the artifact road to the class road: the road is decided
before the unit's blocks compile, and a class file produced after the
artifact-road decisions (no sidecar string, no `setup_blv`) would be a
silently broken jar (review finding, 2026-09-09). The road taken is
reported by the existing env-gated census verdict line, which gains one
verdict, `artifact`.

A BEGIN-time nested unit compiled while its parent compiles is held in
memory as a record (meta plus programs) and written under `nested/` in the
parent's zip, replacing the nested class bytes that ride in the parent jar.

Unchanged in milestone 1: `--target=jar`, `--javaclass`, the `.jar`
extension, the `blib/` layout, the Makefile, the gradle stage tasks (bar
the exported knob), and the class road for runtime compiles of scripts and
EVALs.

## 4. Entry, runners and runtime plumbing

Entry: a fixed Kotlin main (`org.raku.nqp.runtime.UnitMain`) takes the unit
path as its first argument, loads it through the loader (which picks the
road), and invokes the unit's entry block through `invokeMain` as today.
The generated runner scripts (`nqp-j-gradle`, `rakudo-j`) change the main
class token and gain the unit path argument. The eval server loads the app
unit through the same road-agnostic call. `java -jar` convenience is not a
goal.

Finding units: ModuleLoader's `<prefix>/<name>.jar` probing,
`loadbytecode`, and the search path derived from the classpath are
untouched. Artifact units need no classpath entry; only the runtime jars
stay on the classpath.

Stage pipeline for milestone 1: stage0 stays class files. stage1 (built by
the stage0 compiler from the new sources) is class-file units that contain
the writer. stage2 (built by the stage1 compiler with the knob on) is all
ten targets as artifacts. The runner generation task emits the new main
class.

Backtraces: NOT delivered by milestone 1, on either road (final review,
2026-09-09): an engine-bodied block prints `in <name> (<file>)` with no
line on the class road too, and the Java-stack correlation in
`ExceptionHandling.backtrace` never fires for a `ProgramUnit`. The block
record carries `sourceFile`/`sourceLine`; a fallback to the block's start
line when no Java frame correlates would improve both roads. Open item.

Identity: the unit id string replaces the Class object in the eval server's
shared map, load dedupe, and debug and stats keys.

## 5. Error handling

Loading: an unknown meta version, a missing or truncated entry, a program
index out of range, an outer qbid naming no block, a serialized code-ref
count exceeding the table, or a nested id with no entry is a hard error
naming the unit and the field. Never a fallback to a class-file twin.

Writing: the writer refuses if any block lacks a program, a program index
is unassigned, or the call-site data is missing. On the bilingual road that
refusal sends the unit down the class road with the census line saying
why; under strict it is a compile error.

Running: the entry function reproduces the stub's postlude exactly.
Deserialization errors surface from the generated deserialize program as
now.

Guard rails: wire changes stay additive (stage0 ships old programs); the
meta format is versioned independently; every diagnostic is env-gated.

## 6. Testing and gates

Unit-level (gradle's nqp-runtime test task):

- `UnitFormat` round trip on a synthetic record: qbid gaps, a nested entry,
  multi-byte strings in names and programs, a program over 65535 bytes.
- `ProgramUnit` built from that record: code-ref table, outer resolution,
  call sites, entry handles; no program executed.

Encoder-side: a t/nqp file compiled with `--target=jar` under the knob
that asserts the output has `unit.meta` and no `.class` entry, then loads
it with `use` and runs a sub, a closure over an outer, a block with a
handler, and a regex from it.

Per-change gate (every change on the artifact road, through watched-run):

1. `NQP_UNIT=1 clean buildJvm`: stage1 class files, stage2 all ten targets
   as artifacts. Check: every stage2 jar lists `unit.meta` and zero
   `.class` entries (replaces the old sidecar count as the one-compile
   sanity check).
2. `nqp-j-gradle -e` smoke through the new entry main.
3. Full t/nqp on the artifact units through the runner (the campaign's
   `watched-run.raku -t=nqp/t/nqp --jobs=3 -- nqp/nqp-j-gradle`), against
   the strict-green baseline (113/113 from the nqp directory). Anything
   below the baseline is a runtime regression to triage the way the
   campaign did. The eval server is not a milestone-1 vehicle (user,
   2026-09-09): it serves artifact units from milestone 3 on, where
   Rakudo's harness already drives it.

Post-completion gate (once, on the whole green milestone-1 changeset, not
per change): Rakudo `make` on that nqp and `t/01-sanity` 25/25, proving
the class road still works for Rakudo's units. Timings of the stage2 build
and the t/nqp sweep are recorded as the new baseline (forward only).

## Milestones

1. nqp stage2 as artifacts; t/nqp green on the eval server; Rakudo still
   green on the class road (this spec).
2. Runtime compiles in memory: scripts, EVAL, BEGIN-time units build a
   `ProgramUnit` from the record with no class definition; the
   string-constant road, its size gate, and `ByteClassLoader`'s define
   road go.
3. Rakudo units as artifacts, after custom_args bodies and exit-handler
   blocks encode (item 7's last two shapes); the eval server serves
   artifact units and the suites (t/nqp, t/01-sanity, t/spec) run through
   it here.
4. stage0 regenerated as artifacts; the class road, jast2bc, JAST, the
   class loaders, the indy budget and the class-file build plumbing
   deleted (item 8), with the direct QAST walk replacing Compiler.nqp as
   the driver.

## Open questions from the unit map, resolved

- Method-handle identity in `CallFrame.outerFor`: preserved, one bound
  handle per block.
- `argsExpectation` without a method signature: every artifact block is
  raw-args; the dispatchers' direct-road gate becomes universal.
- Eval-server sharing: keyed by unit id string.
- Nested units and `$*EMIT_CUIDS`: mechanism kept, cuids written only for
  nested units, class lookup replaced by the parent's nested table.
- `getCodeRefs()` fallback road and `lookupCodeRef(String)`: class-road
  only; untouched until item 8.
- Interop adaptor units (`BootJavaInterop`, `RakudoJavaInterop`): remain
  runtime-generated class-file units on the class road; item 9's problem.
- Sidecar framing: byte-framed in the new format.
- `serializedCodeRefCount`: carried in the meta.
- Line attribution: block record plus engine source sections.

## Out of scope

Deleting anything (item 8); the interop adaptors (item 9); the direct
QAST walk replacing Compiler.nqp; `java -jar`; the calling-convention
items 1 to 3 and the tier policy (item 4).
