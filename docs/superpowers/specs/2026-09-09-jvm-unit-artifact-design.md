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
(Milestone 1's writer refused such a unit, runtime compiles being class
files then; since milestone 2 the record is retained by `loadcompunit` in
`GlobalContext.inMemoryUnitRecords` and the writer embeds it. Nothing in
nqp's own sources produces one: an NQP `BEGIN`'s dynamic compile is
re-pointed at the unit's own emission of the same cuids. Rakudo's BEGIN
blocks do, and exercise this road from milestone 3.)

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
   `ProgramUnit` from the record with no class definition. DONE
   2026-09-09 behind the knob (plan
   `docs/superpowers/plans/2026-09-09-jvm-unit-artifact-milestone-2.md`):
   under `NQP_UNIT` every unit takes the road; with the knob unset the
   class road is untouched, because Rakudo builds and runs on it until
   milestone 3. The deletions this line used to end with (the
   string-constant road, its size gate, `ByteClassLoader`'s define
   road, and with them the nested `.class` embedding) are milestone 3's
   closing item, when Rakudo flips and the knob becomes the default.
3. Rakudo units as artifacts, after custom_args bodies and exit-handler
   blocks encode (item 7's last two shapes); the eval server serves
   artifact units and the suites (t/nqp, t/01-sanity, t/spec) run through
   it here.

   DONE 2026-09-10 (plan
   `docs/superpowers/plans/2026-09-09-jvm-unit-artifact-milestone-3.md`;
   nqp `da1f5088a`..`30e849e3c`, rakudo `5ae25a8d3c`..`a22eb40b73`).
   What shipped: exit-handler blocks, `withy` general, labeled control
   and `for :label` encode (nqp `c872c83af`, additive wire op
   `FORLOOPL = 35`); the encoder and the unit road became the defaults
   and `NQP_UNIT` went away, the generated runners and the eval server
   entering every unit through `UnitMain <unit jar>`, with the
   record-road mainline frame carrying its file in backtraces again (nqp
   `388173781`..`e5f2b3840`, rakudo `08a997dc2b`); seven gaps the first
   t/ sweep found, closed (nqp `171d37508`..`8bab02391`: sized and
   unsigned natives, the unnamed chain link, suspendable dedicated ops
   with typed tokens on the additive wire op `OPCALLT = 36`, an
   empty-message NPE, a sized `uint` attribute); and the compiler-side
   deletions of milestone 4's list (nqp `30e849e3c`, rakudo
   `a22eb40b73`). The gate on that toolchain, sleep suppressed:

   - nqp clean build 222 s; `make` 1154 s from the top (rakudo.jar
     171 s, BOOTSTRAP v6c starts 200 s, CORE.c 594 s to 1069 s = 475 s,
     CORE.d 1069 s, CORE.e 1096 s)
   - t/nqp 118/118 on the unit road; t/01-sanity 25/25 in 161 s;
     precomp 14/14; t/03-jvm + t/10-qast 2/2
   - all 16 Rakudo jars and all 11 nqp jars `unit.meta`-only; CORE.c
     carries 4 nested units (8 `nested/` entries)

   The four deviations the plan states, kept: (1) the runtime's
   class-road writer and loaders stay, because stage0 is still a
   class-road compiler running on this runtime -- they go with stage0 in
   milestone 4; (2) t/spec did not run (user, 2026-09-09: not until t/
   takes under two hours), so this line's t/spec clause moves to
   milestone 4; (3) no RakuAST change for `ModuleLoader.class`, since
   `LibraryLoader` already special-cases the name and sniffs for
   `unit.meta`; (4) `--javaclass=perl6` stays, naming the unit id only,
   which nothing keys on.

   t/ ran twice through the eval server: sweep 1, after the flip,
   7858 s over two invocations on two 6 GB servers; sweep 2, after the
   deletions, 7270 s (the 7200 s ceiling after 59 of 60 chunks on three
   4 GB servers, plus a 70 s tail), with no new failures and 26 files
   fixed since sweep 1.

   Parked, real and narrow: a where-constrained parameter of a routine
   declared *and* called inside one `BEGIN` binds its `WhateverCode`
   `$!do` to the dynamic unit's mainline code ref, leaving two
   t/02-rakudo files red (evidence and the next lead in the milestone's
   `task-3b-report.md`). Carried with it: a suspended typed op resumes
   with the inner call's value instead of re-running the op (a `take`
   inside a `Proxy` `FETCH` inside a typed op).
4. stage0 regenerated as artifacts; the class road, jast2bc, JAST, the
   class loaders, the indy budget and the class-file build plumbing
   deleted (item 8), with the direct QAST walk replacing Compiler.nqp as
   the driver. After milestone 3 this is the whole remaining list, and
   it is runtime-side: stage0 regenerated as artifacts; the runtime's
   class-road writer and loaders deleted -- jast2bc, `Ops.compilejast`,
   `loadcompunit`'s define branch, `MemoryClassLoader`, the sidecar
   reader and `JarFileClassLoader` -- together with the JAST method
   carrier; the per-block stub emission in `Compiler.nqp` (arity check,
   locals, postlude, save sites, the `getCallSites`/`entryQbid`
   methods) deleted with JAST; the `setup_blv` op; and the interop adaptors
   (`BootJavaInterop`, `RakudoJavaInterop`), which still subclass a
   generated `CompilationUnit` through `ByteClassLoader` (item 9).
   t/spec runs here (deviation 2 of milestone 3). Two items this list
   carried are done in milestone 3's final-review fix wave: the four
   `NQP_UNIT` comments in the runtime's `.kt` sources and the `NQP_UNIT`
   headers of `t/nqp/123` and `t/nqp/124`. One thing milestone 4 must NOT
   forget: the runtime's `$!codeprograms` pass-through (`JastClass` ->
   `JASTCompiler` -> the `.codeprograms.lz4` sidecar) is what stage0's
   class-road compiler needs, so it is deleted only with stage0 itself,
   and no gradle build may carry `NQP_CODE_RUN`/`NQP_CODE_PRECOMP` until
   then (stage0 encodes on their mere presence).

   CODE COMPLETE 2026-09-10; its t/ gate found eleven red files
   milestone 3's sweep 2 did not list, two with named mechanisms (an
   `is_inlinable` regression that stops RakuAST inlining and native
   lowering, and a multi-character `Str` range that never terminates).
   **Both were fixed in the fix wave of 2026-09-11** (nqp `908134f3f`,
   `47697ca29`, `3b9615f4b`, `b3d75f993`; rakudo `548dc2544d`,
   `cd5799df09`): `is_inlinable` answers from the classlib registry, an
   explicit twelve-name non-inlinable table and the encoder's own rows,
   with the five Raku ops recorded again on the Rakudo side and both
   answers pinned by `nqp/t/jvm/16-op-registry.t`; and the range hang
   turned out to be neither CORE.c nor the compiler but `CallFrame` —
   the continuation save road gave a still-live frame's invocation count
   back, so a second invocation of the same static frame (which
   `SEQUENCE` makes of itself) resolved its outer to the suspended one.
   The milestone-4 spec's "Done" section carries the gate in full and
   the wave's analysis after it. Nine of the eleven are green or
   expected; `native-return-coercion.t` (19/23) and five others remain
   open, none of them with a named mechanism. **The timings below were
   taken with the inliner idle and are not a baseline; the wave's are:
   nqp clean build 253 s, `make` 1142 s, CORE.c 467 s.** (plan
   `docs/superpowers/plans/2026-09-10-jvm-unit-artifact-milestone-4.md`,
   spec
   `docs/superpowers/specs/2026-09-10-jvm-unit-artifact-milestone-4-design.md`,
   ledger twin and eleven task reports beside the plan; nqp
   `55bdee5b7`..`e270f070d`, rakudo `670c3645b0`..`09f349adda`). What
   shipped, in the order it landed: the JAST-free driver (nqp
   `c6af33aa3`: `QAST::Compiler` 6363 -> 1948 lines, `NQP/Ops.nqp` 177 ->
   9, unit records + `RecordReader` + the `jvm-*-unit-record` syscalls,
   `QAST::OperationsJAST` -> `QAST::OperationsJVM`); the compiler-side
   file deletions (nqp `5cf759de6`: `NQP/Ops.nqp` and `JASTNodes.nqp`);
   Rakudo's `Raku/Ops.nqp` (rakudo `2e66c36b3d`); **stage0 regenerated as
   9 `unit.meta`-only artifact jars** (nqp `9844a0de9`, `JASTNodes.jar`
   gone); the runtime deletions and the loader port (nqp `1a658daa1`,
   `4b261b3b2`: the whole `jast2bc` package, `Ops.compilejast`,
   `loadcompunit`'s define branch, `MemoryClassLoader`,
   `JarFileClassLoader`, `LibraryLoader.java`, the sidecar reader **and
   the `$!codeprograms` pass-through the paragraph above told milestone 4
   not to forget** -- it went with stage0, exactly as that paragraph
   requires -- `IndyBootstrap`, the indy budget, `setup_blv`, the
   per-block stub emission, and `CompilationUnit` reshaped around a
   non-null `getCodeRefs(): Array<CodeRef>`); the interop adaptors (nqp
   `14df06863`, rakudo `09f349adda`: `AdaptorUnit` over a plain
   ASM-generated class, item 9's adaptor half); and the three carried
   gaps -- torn-frame `LEAVE` (nqp `d8116d7c9`, `keep-undo.t` 15/16 ->
   16/16), the resume value of a suspended typed op (nqp `929f73b11`),
   and the parked where-in-`BEGIN` shape (nqp `e270f070d`:
   `patch_params` keeps the parameter prologue's deferred code-ref
   slots), which closed both parked t/02-rakudo files. ASM stays, for
   `P6Opaque`'s generated attribute-storage classes and for the
   adaptors; that is item 9's remaining half.

   Timings on this toolchain: nqp clean build 214-263 s (milestone-3
   baseline 222 s); `make` from the top 1185 s at Task 7 and 1103 s at
   Task 10 (baseline 1154 s), CORE.c 472-511 s (baseline 475 s). Gate:
   t/nqp 118/118; `t/01-sanity` 25/25; precomp 13/14 plain and 14/14
   with `RAKUDOLIB=lib` (the harness gap known since milestone 3, not a
   compiler fault); t/03-jvm + t/10-qast 2/2; interop 30/30; **all 35
   jars `unit.meta`-only, zero `.class`** -- 10 nqp share-lib, 9 stage0,
   16 Rakudo. The t/ sweep is the gate that is **not** green: 418 files
   at 2 servers x 4g (3 x 4g exceeds the sweep's own budget at 20 g
   MemAvailable), 59 of 60 chunks inside the 7200 s ceiling, and eleven
   files red that milestone 3's sweep 2 did not list. The item-8 pair is
   green, as Task 10 promised.

   Six deviations, all ledgered: Tasks 5 and 6 ran as one dispatch
   (`LibraryLoader.java` calls what Task 5 deletes, so the runtime jar
   does not compile between them); `serializedBlob`/`claimNested`/
   `engineProgram` stayed `open` with throwing bodies rather than
   `abstract`, because the hand-written `KnowHOWMethods` subclass
   implements none of them; `readToHeapBuffer*` was not ported (no
   callers left after Task 5); `t/spec/S04-phasers/leave.t` does not
   exist, so `keep-undo.t` was the torn-frame gate; the resume-value
   probe in the plan was not an instance of the gap, and the real
   reproducer is `subset S of Int where { take $_; True }; sub f(--> S)
   { 5 }; gather { say f() }`; and Task 4's nqp rebuild left the Rakudo
   jars stale, so the 5+6 sanity gate moved to Task 7's make from the
   top. t/spec still did not run (milestone 3's deviation 2 stands:
   user, not until t/ takes under two hours).

## Open questions from the unit map, resolved

- Method-handle identity in `CallFrame.outerFor`: preserved, one bound
  handle per block.
- `argsExpectation` without a method signature: every artifact block is
  raw-args; the dispatchers' direct-road gate becomes universal.
- Eval-server sharing: keyed by unit id string.
- Nested units and `$*EMIT_CUIDS`: mechanism kept, cuids written only for
  nested units, class lookup replaced by the parent's nested table.
- `getCodeRefs()` fallback road and `lookupCodeRef(String)`: class-road
  only; untouched until item 8. (Closed by milestone 4: both are gone,
  and `getCodeRefs()` is a non-null `Array<CodeRef>` on every unit.)
- Interop adaptor units (`BootJavaInterop`, `RakudoJavaInterop`): remain
  runtime-generated class-file units on the class road; item 9's problem.
  (Closed by milestone 4: they generate a plain class with ASM and hand
  it to `AdaptorUnit`, a hand-written `CompilationUnit` subclass; no
  generated `CompilationUnit`, no class road. `P6Opaque`'s generated
  attribute-storage classes are item 9's remaining half.)
- Sidecar framing: byte-framed in the new format.
- `serializedCodeRefCount`: carried in the meta.
- Line attribution: block record plus engine source sections.

## Out of scope

Deleting anything (item 8); the interop adaptors (item 9); the direct
QAST walk replacing Compiler.nqp; `java -jar`; the calling-convention
items 1 to 3 and the tier policy (item 4).
