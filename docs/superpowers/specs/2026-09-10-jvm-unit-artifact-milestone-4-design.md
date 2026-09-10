# JVM unit artifact, milestone 4: the class road and JAST deleted

Design for the last milestone of items 5 and 6 of
`docs/jvm-truffle-only-plan.md`, which is also item 8 (deletion) and the
adaptor half of item 9. It closes the spec
`2026-09-09-jvm-unit-artifact-design.md` (section "Milestones", item 4).
Approved in conversation on 2026-09-10 after one revision: the QAST-only
driver moves to the front so that a single stage0 regeneration yields a
JAST-free compiler and nothing JAST-named survives.

## Where the tree stands (2026-09-10, rakudo `b4e5e65c3c`, nqp `55bdee5b7`)

Milestone 3 made the unit road the only road in the compiler: every jar
nqp and Rakudo build is `unit.meta`-only, runners enter through
`UnitMain`, and the compiler has no bytecode fallback. The class road is
alive in exactly one place: the ten committed jars under
`nqp/src/vm/jvm/stage0/` are class-road jars (`nqp.class` plus
`.serialized.lz4` and `.codeprograms.lz4` sidecars), and
`nqp/build.gradle.kts`'s `registerStage` runs them with `mainClass =
"nqp"` on a boot classpath ending in stage0's `nqp.jar`. Everything on the
runtime deletion list exists to serve that compiler: `Ops.compilejast`
and `compilejasttofile`, `loadcompunit`'s define branch and
`inMemoryUnitBytes`, the four class loaders in `LibraryLoader.java`, the
`.codeprograms.lz4` reader in `CompilationUnit.loadEnginePrograms`, the
`$!codeprograms` pass-through in `JastClass`/`JASTCompiler`, the
`setup_blv` op and its `setLexValues*` landing pads, `enterFromMain`,
`IndyBootstrap`, `AutosplitMethodWriter`.

Two facts the milestone-4 list did not spell out:

- **The unit writer reads the JAST tree.** `UnitWriter.kt` takes its input
  through the jast2bc readers (`JastClass`, `JastMethod`,
  `JASTCompiler.ensureSetup`/`processType`), and `JASTNodes.nqp`'s
  `JAST::Class` and `JAST::Method` carry the unit-record fields (`$!hll`,
  `$!mainline_qbid`, `@!programs`, `@!callsites`, `@!blockvalues`,
  `@!nested_classes`, the `cr_*` setters). Deleting JAST means giving the
  writer a new record and a new reader.
- **The encoder needs none of the JAST op code.** `TruffleEncoder.nqp`
  never names `QAST::OperationsJAST` or `QAST::CompilerJAST`. It reads
  the classlib registries as hllsyms (`CODE_CLASSLIB_OPS`,
  `CODE_CLASSLIB_HLL_OPS`) and the desugar registry; it reads five dynamic
  variables (`$*CODEREFS`, `$*HLL`, `$*BLOCK`, `$*MISSING`, `$*STACK`) and
  calls five compiler methods (`as_jast` twice in the nested-block
  deferral, `coercion`, `rx_descriptor`, `rx_callback_block`,
  `cuid_to_qbid`). Only the deferral and the coercion lookup are JAST.

Of `Compiler.nqp`'s 6363 lines, the driver is what survives: the CompUnit
walk, the per-block walk that calls the encoder, `BlockInfo`,
`CodeRefBuilder` minus its JAST `callsites()` method, `deserialization_code`
and `emit_param_tasks` (QAST builders), `cuid_to_qbid` and the qbid
seeding, `$*COMP_MODE`/`$*EMIT_CUIDS`, `rx_descriptor` and the callback
block builders, and the registry data of `QAST::OperationsJAST`. The
~3200 lines of op-to-bytecode mappings, `StackState`, the temp
allocators, `compile_all_the_stmts`, `compile_var`, the save sites, the
arity stubs, preludes and postludes, `engine_jast`, the indy budget and the
`setup_blv` registration go. Rakudo's `src/vm/jvm/Raku/Ops.nqp` keeps its
24 `register_op_desugar` entries and loses 19 JAST closures
(`add_hll_op`, `add_hll_box`, `add_hll_unbox`); nqp's
`src/vm/jvm/NQP/Ops.nqp` is treated the same way.

The interop adaptors are the one client of `CompilationUnit`'s reflective
road (`CodeRefAnnotation`, `getCodeInfo`, `ReflectiveCodeInfo`'s `qb_N`
parsing, the non-overridden `initializeCompilationUnit`), and they define
a generated `CompilationUnit` subclass through `ByteClassLoader`.
`KnowHOWMethods.kt` is the precedent for the replacement: a hand-written
Kotlin `CompilationUnit` whose `getCodeRefs()` builds `CodeRef`s from bound
method handles; `StaticCodeInfo` already accepts both the four-argument
bound shape and the five-argument static shape the adaptors emit.

## Decisions taken

| decision | choice |
|---|---|
| order | driver first, then one stage0 regeneration, then the runtime deletions, adaptors, the three gaps, the milestone gate (user, 2026-09-10) |
| driver | a QAST-only walk in `Compiler.nqp`, trimmed in place and renamed; no JAST name, attribute or file survives (user: "literally no traces of JAST") |
| record | new unit and block record classes with their own names, declared beside the driver in the QAST module; the `JASTNodes` module and jar are deleted from every stage list |
| transition | the runtime carries both readers (jast2bc's for stage0's tree, the new record reader) for exactly one build, until stage0 is regenerated; the write/build syscalls accept stage0's old call shape for the same window |
| stage0 | regenerated once, from the stage2 the new driver builds; gradle's stage compiles enter through `UnitMain`; a second regeneration only if a later step changes compiler sources |
| adaptors | rewritten in this milestone (item 9's adaptor half): a plain generated class plus a Kotlin `AdaptorUnit`; the reflective road dies with the class road; ASM and `ByteClassLoader.defineClass` stay for plain classes (P6Opaque, adaptors) |
| gaps | all three carried gaps are worked, time-boxed, gated by `t/01-sanity` plus targeted test files, never directories (user, 2026-09-10) |
| gate | milestone 3's gate: t/nqp, `t/01-sanity`, precomp, t/03-jvm, one make-driven t/ sweep through the eval server; no t/spec (user rule: not until t/ runs under two hours) |
| language | Kotlin for everything new; the surviving loader is ported from Java |
| wire | additive only; the meta format version stays 1 unless a record field changes shape |
| builds | forward only, one compile per change, amend on breakage; the driver step's Rakudo make is the milestone's first timing point |

## 1. The driver (QAST-only walk)

`QAST::CompilerJAST` becomes `QAST::UnitCompiler` (the name is the plan's
to settle; nothing JAST). Its entry, replacing `jast($source,
:$classname)`, walks a `QAST::CompUnit` and answers a **unit record**:

- qbid assignment in tree order, `%*CUID_TO_QBID` seeding and
  `cuid_to_qbid`, exactly as today;
- per block: `BlockInfo` (params, lexicals by type, locals), the
  `%*BLOCK_LEX_VALUES` rows, then `QAST::TruffleEncoder.encode_block`; the
  program index is stored on the block record; a block that yields no
  program is a compile error naming the block (the milestone-3 die stays);
- the deserialize and load blocks are generated by `deserialization_code`
  and encoded like any other block; the mainline, entry, deserialize and
  load qbids, the HLL name, the SC handle and description, the serialized
  code-ref count, the programs list, the call-site data
  (`CodeRefBuilder.callsite_data`), the static lexical rows, the nested
  unit ids and the serialized blob are the record's fields;
- nested-block deferral: the encoder's two `as_jast` calls become one
  driver call (`compile_block($blk)`) that returns nothing; `$*STACK` and
  the operand-stack `obtain` disappear from the encoder; the coercion
  lookup moves to the encoder or a registry helper, whichever the plan
  finds cleaner;
- regexes: `rx_descriptor` and `rx_callback_block(_for)` stay as QAST
  builders; the 20000-character class-file refusal in `rx_descriptor`
  goes; the callback grouping cap loses its bytecode reason and stays as
  a plain size limit or goes, the plan decides.

**Records.** Two NQP classes declared in the QAST module beside the
driver (the plan names them; e.g. `QAST::UnitRecord`,
`QAST::BlockRecord`), with attributes for exactly the fields the writer
reads today. The block record carries what `JAST::Method`'s `cr_*`
setters carried: name, cuid, outer qbid, the four lexical-name lists,
handlers, flags (frame-forced, custom_args, exit handler), source file and
line, program index. The unit record carries the fields listed above.
No instruction list, no locals, no labels.

**Reader.** A Kotlin `RecordReader` in `org.raku.nqp.runtime.unit`
replaces `JastClass`/`JastMethod` as `UnitWriter`'s input. It reads by
attribute name through cached hints on the record's own type, so the
syscall no longer needs the `%jastnodes` type map; for the transition
build the syscalls still accept the map argument (ignored) and the old
readers still serve a `JAST::Class` (sniffed by type), both deleted in
step 3.

**Registries.** `QAST::OperationsJAST` shrinks to the data the encoder
consumes, renamed (e.g. `QAST::OperationsJVM`): the classlib maps
(`map_classlib_core_op`, `map_classlib_hll_op` and their hllsym
publication), `register_op_desugar` and its registry, the HLL box/unbox
type tables if the encoder reads them (the plan verifies; today it has its
own rows), `add_hll_op` retained only if a non-JAST consumer exists,
otherwise deleted with its callers.

**Backend.** `HLL::Backend::JVM.stages` becomes `unit jar jvm`: `unit`
runs the driver and then writes (`jvm-write-unit`, jar-bound with an
output) or builds in memory (`jvm-build-unit`); `jar` is the pass-through
it already is, kept because the Makefile, `jvm-build-resume.sh` and the
eval server pass `--target=jar`; `jvm` is `loadcompunit`. `use JASTNodes`
goes; `--target=classfile` and `--target=jast` are unknown targets.

**Stage lists.** `JASTNodes.jar` leaves `stageTargets` (and the `Hll` and
`Qast` dependency lists), `NqpSources.JASTNODES`, the gen-cat map, and
`nqp/tools/templates/jvm/Makefile.in`'s `ASTNODES_SOURCES`; the stage0
directory loses the jar at regeneration.

**Rakudo.** `src/vm/jvm/Raku/Ops.nqp` keeps `register_op_desugar` and the
`$ops` helpers those need; every `JAST::` construction goes. The
`#?if jvm` parts of RakuAST are untouched (no RakuAST edit is expected in
this step).

Gate: `clean buildJvm`, t/nqp 118/118 (the two cwd-relative files from the
nqp dir), t/qast, then the milestone's first Rakudo `make`, `t/01-sanity`
25/25, precomp 14/14. This make is the first timing point (CORE.c is
expected to lose the ~33 s jast stage).

## 2. stage0 regenerated

Procedure, on the driver step's toolchain:

1. `./nqp/gradlew -p nqp clean buildJvm` (stage2 from the new driver, all
   artifacts, no `JASTNodes.jar`);
2. `./nqp/gradlew -p nqp jBootstrapFiles` (the existing copy task:
   stage2 over `src/vm/jvm/stage0`, `NQPP5QRegex.jar` excluded); delete
   the stale `JASTNodes.jar` from the directory;
3. `registerStage` enters through `org.raku.nqp.runtime.unit.UnitMain
   <compilerDir>/nqp.jar` with the runtime jars alone on the classpath;
   the boot-classpath list assembled around stage0's `nqp.jar` goes, the
   `--module-path`/`--setting-path` arguments stay (they name directories
   ModuleLoader probes);
4. `clean buildJvm` again, from the new stage0; t/nqp 118/118;
5. commit the nine jars in nqp (binary; label the hash).

Documented in `nqp/docs/gradle-jvm-build.md` beside the Java 25 note: when
the wire, the meta format or a syscall shape changes incompatibly, stage0
is regenerated by the LAST compiler that still speaks the old shape,
before the change lands; additive wire changes need no regeneration.

Gate: the two clean builds and t/nqp.

## 3. The runtime class road deleted

Deleted, by file (all under `nqp/src/vm/jvm/runtime/org/raku/nqp/` unless
noted):

- `jast2bc/` entirely (3157 lines): `JASTCompiler`, `AutosplitMethodWriter`,
  `JastClass`, `JastMethod`, `JastField`, `JavaClass`; `BytecodeVersion`
  moves to `runtime/` (P6Opaque and the adaptors read it).
- `runtime/Ops.kt`: `compilejast`, `compilejasttofile`; `loadcompunit`'s
  define branch, `inMemoryUnitBytes` and the `res.jc` handling.
- `runtime/EvalResult.kt`: the `jc` field.
- `runtime/LibraryLoader.java` (590 lines): deleted; its road-agnostic
  survivors (`load` by path/bytes/buffer with the unit sniff, `loadApp`,
  `prime`, `readToHeapBuffer`, `readToHeapBufferLz4`,
  `ByteBufferedInputStream` if still needed) are ported into Kotlin in
  `unit/` (`UnitLoader` or a sibling); `SerialClassLoader`,
  `StreamClassLoader`, `FileClassLoader`, `JarFileClassLoader`,
  `MemoryClassLoader`, `loadFile`, `loadClass`, `loadJar`, `resolveClass`
  and the class branches of `loadApp`/`prime` go. `ModuleLoader.class`
  special-casing stays (it names an artifact).
- `runtime/CompilationUnit.kt`: `enterFromMain`, `setupCompilationUnit`,
  `getCodeInfo`, `codeInfoStash`, `ReflectiveCodeInfo`, the reflective
  half of `initializeCompilationUnit(tc, runDeserialize)` (what remains
  of it fills the tables from `getCodeRefs()`, the path `KnowHOWMethods`
  takes today and the adaptors take after step 4), `lookupCodeRef
  (String)`'s `/*FOR_STAGE0*/` body (abstract from here; `ProgramUnit`
  overrides it), `setLexValues`/`setLexValuesBulk`, the class bodies of
  `serializedBlob` and `claimNested` (abstract), `engineProgram`'s class
  body and `loadEnginePrograms`. What remains is an abstract base:
  the code-ref tables, `runDeserializeIfAvailable`,
  `runLoadIfAvailable`, `lookupCodeRef(Int)`, `getCodeRefs()` as the
  non-reflective hook (`KnowHOWMethods`, the adaptors), the abstract
  `getCallSites`/`hllName`, the qbid accessors, `unitId()`.
- `runtime/CodeRefAnnotation` and every `@CodeRefAnnotation` site.
- `runtime/IndyBootstrap.kt` (587 lines, reachable only from JAST
  `invokedynamic`).
- `tools/EvalServer.java` and rakudo's `RakudoEvalServer.java`: the class
  branches; they keep `loadApp`/`prime` through the Kotlin loader.
- `GlobalContext.inMemoryUnitBytes`; `byteClassLoader` stays.
- `nqp/t/jvm/09-autosplit.t` (20013 lines, tests the autosplitter);
  `nqp/tools/templates/jvm/Makefile.in:21` (the stale jast2bc line); the
  `NQP_DEBUG_DUMP_CLASSFILES` knob if nothing but the deleted writer read
  it.
- Comments and docs that name jast2bc, the sidecar or the class road as
  live (`TruffleEncoder.nqp:1`, `UnitFormat.kt:13`, `CodeEngine.kt:72`,
  `Backend.nqp:98`, `docs/jvm-*.md`): reworded or removed.

Kept, deliberately: `ByteClassLoader.defineClass` (plain ASM classes:
P6Opaque, adaptors), ASM itself, `engineProgram(idx)` as the unit road's
accessor, `UnitZip`'s sniff, the `NQP_CODE_WHY` marker.

Gate: `:nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar
syncRuntimeJars`, t/nqp, `t/01-sanity`; restart eval servers. No setting
recompile: bytecode does not depend on the runtime that executes it, and
Rakudo's jars are artifacts.

## 4. The interop adaptors (item 9, adaptor half)

`BootJavaInterop.createAdaptor` and `RakudoJavaInterop.createAdaptor`
generate a plain class (superclass `java/lang/Object`) with the same
`public static qb_N(CompilationUnit, ThreadContext, CodeRef,
CallSiteDescriptor, Object[])` bodies, no annotation, and the static
`constants` field. `compunitMethods` goes. A Kotlin `AdaptorUnit(gc,
cls, descriptors) : CompilationUnit` in `runtime/` overrides
`getCodeRefs()` to look up `qb_0 .. qb_N-1` with `MethodHandles.lookup().
findStatic` and build a `CodeRef` per handle (name `callout <target>
<desc>`, cuid = the name, no lexicals, no handlers, args expectation 0),
answers `getCallSites() = null` and `hllName() = ""`, and is initialized
through the surviving `initializeCompilationUnit(tc)`; `computeInterop`
instantiates it instead of `constructed.newInstance()`. The `cu`
argument of `qb_N` receives the `AdaptorUnit`. The `constants` field is
set through the class's own static setter or a plain reflective field
write on a non-`CompilationUnit` class (the plan picks; neither needs
the reflective code-ref road). `computeProxyClass` is untouched (plain
classes already).

Gate: `t/03-jvm/01-interop.t` (its `Foo.class` fixture), `t/01-sanity`.

## 5. The three carried gaps (time-boxed)

Each gets one task with a time box and a ruling if it does not close; a
gap that stays open is ledgered with its evidence, exactly as milestone 3
parked item 8. Their gates are `t/01-sanity` plus the named files, never a
directory.

**5a. Torn-frame LEAVE.** `ExceptionHandling.giveBackTornFrames` walks the
frames between `tc.curFrame` and the handler frame and calls
`CallFrame.countLeft()`, which by design runs no exit handler. Raku runs
LEAVE (and the other exit phasers) on exceptional exit. Design: the torn
walk, innermost first, runs each frame's exit handler when
`staticInfo.hasExitHandler` is set, with the same unwinder swap `leave()`
performs and the frame's result treated as absent (the handler receives
the frame and a null result), then gives back the count; a handler that
throws replaces the in-flight exception (Raku semantics: the phaser's
exception wins). `left` stays the idempotence guard. Gate:
`t/spec/S04-phasers/leave.t` and `enter-leave.t`, run by path from the
main checkout's `t/spec` (the worktree has none) with the worktree's
`rakudo-j -Ilib`; `t/01-sanity`.

**5b. Resume value.** The engine's suspension protocol hands the resumed
site the resumed call's value in place of the op's own result
(`emitSuspendCheck`: "whatever comes back through the resumed yield ...
replaces it"), so an op that computes from a post-suspension value
answers the inner value (`istrue` of a Proxy whose FETCH takes answers 7,
not 1; the class road re-entered at the enclosing save site and re-ran
the op). Design: the resume re-enters the op with the inner call's value
in the call's own result register and recomputes the op; concretely the
suspension token records the op and the position of the suspended call
within it, and `resumeEngine` re-runs the op's node with that call
answered from the token instead of storing the value as the op's result.
Any wire change is additive. Gate: the report's probe (`subset S of Int
where { take $_; True }; my @a = gather { 5 ~~ S }; say @a` answers `[5]`,
and `istrue` of a taking Proxy answers 1), a t/nqp file if one covers
suspension inside typed ops, `t/01-sanity`.

**5c. BEGIN + where code-ref pairing (item 8 of milestone 3).** A
where-constrained parameter of a routine declared and called inside one
BEGIN binds its `WhateverCode`'s `$!do` to the dynamic unit's mainline
code ref; the tie is `Code.clone` of an already-wrong `$!do`, and the next
lead is the `nqp::getstaticcode` stub at `src/Raku/ast/code.rakumod:428`:
which unit's block that stub literal belongs to when the routine is
stubbed during a BEGIN, and whether it is fetched from the dynamic unit's
mainline code ref instead of the anonymous sub's. Evidence and trace knobs
(`NQP_REPOINT_TRACE`, `NQP_REPOINT_STACK`) in milestone 3's
`task-3b-report.md`. Gate: `t/02-rakudo/yada-trait-timing.t`,
`t/02-rakudo/begin-time-attributive-param-method.t`, `t/01-sanity`. A fix
in RakuAST (`#?if jvm`) needs the closing Rakudo make.

## 6. Error handling and guard rails

- The driver dies on a block with no program, an unassigned program
  index, or missing call-site data, naming the block; there is no
  fallback road to send anything down.
- The reader dies on a record missing a field, naming the field.
- A stage compile that finds a class-road jar in stage0 (a `.class`
  entry) dies at `UnitMain`'s sniff, as today.
- Wire changes additive; the meta format versioned independently; every
  diagnostic env-gated.
- No gradle build reads `NQP_CODE_RUN`/`NQP_CODE_PRECOMP`; after step 2 the
  "encodes on mere presence" caveat is history and the comment at
  `Compiler.nqp:4110` and `TruffleEncoder.nqp:409` goes with it.

## 7. Testing and gates

| step | gate |
|---|---|
| 1 driver | `clean buildJvm`; t/nqp 118/118; t/qast (02 green; 01 is moar-only, known red); Rakudo `make`; `t/01-sanity` 25/25; precomp 14/14 |
| 2 stage0 | `clean buildJvm`, `jBootstrapFiles`, `clean buildJvm` from the new stage0; t/nqp |
| 3 runtime deletions | runtime jars + `:nqp-runtime:test`; t/nqp; `t/01-sanity`; `grep` for every deleted name empty across nqp and rakudo sources, docs excepted |
| 4 adaptors | `t/03-jvm/01-interop.t`; `t/01-sanity` |
| 5 gaps | per gap, section 5 |
| 6 milestone | Rakudo `make` (needed if 5c touches RakuAST; otherwise the step-1 make stands); t/nqp; `t/01-sanity`; precomp; t/03-jvm + t/10-qast; one make-driven t/ sweep through the eval server (`--jobs=3 --heap=4`, `--max=7200`, a second invocation for unreached dirs); `tools/build/jar-census.raku` all artifacts |

Runs over 30 s go through `tools/build/watched-run.raku`; progress
reported every 90 s; eval servers restarted after any runtime jar
rebuild. The t/ sweep's expected red: the corekeys/settingkeys cluster
(NFG expectation), the 2026-09-05 known list minus what milestone 3
fixed, and 5c's pair if 5c stays open.

## Sequence

1. Driver (section 1). 2. stage0 (section 2). 3. Runtime deletions
(section 3). 4. Adaptors (section 4). 5. Gaps 5a, 5b, 5c. 6. Milestone
gate, docs (plan position rows for items 5, 6, 8, 9; this spec's parent
"Milestones" item 4; `nqp/docs/gradle-jvm-build.md`; `AGENTS.md`;
`CLAUDE.md`), ledger, memory, then the handoff rebase onto both upstream
mains and the force-with-lease push to `ab5tract`.

## Out of scope

The tier policy and the perf measurement session (item 4; next after
this milestone); P6Opaque's generated attribute classes (item 9's other
half); anonymous-block naming; t/spec; `java -jar`; items 1 to 3.

## Open at plan time (the plan settles these, not the spec)

- The record and driver class names.
- Whether `add_hll_op` keeps a non-JAST consumer.
- Whether the regex callback grouping cap stays as a plain limit.
- The `constants` handoff in the adaptors (static setter vs field write).
- Whether the resume-value fix needs a wire field or a static table.

## Done (2026-09-10) — code complete, gate open

Everything this spec asked for is built and committed, and the milestone
is **not closed**: the t/ gate (below) found eleven red files that
milestone 3's sweep 2 did not list, two of them with named mechanisms,
and the controller rules on them.

Ranges: nqp `55bdee5b7`..`e270f070d` (branch
`jesp-direct-lazy-records`), rakudo `670c3645b0`..`09f349adda` (branch
`worktree-jesp-direct-lazy-records`). Plan
`docs/superpowers/plans/2026-09-10-jvm-unit-artifact-milestone-4.md`, its
ledger twin and the eleven task briefs/reports beside it.

What shipped, task by task:

1. **The driver** (nqp `c6af33aa3`). `QAST::Compiler` stopped emitting
   JAST and became a unit driver over the QAST tree: 6363 lines to 1948,
   `nqp/src/vm/jvm/NQP/Ops.nqp` 177 lines to 9, the record classes and
   `RecordReader` in place, `jvm-*-unit-record` syscalls added,
   `QAST::OperationsJAST` renamed `QAST::OperationsJVM` and
   `supports_op` answering the encoder's rows plus the hand rows.
   Build 214 s, 11 artifact jars, t/nqp 118/118.
2. **The deletions on the compiler side** (nqp `5cf759de6`):
   `NQP/Ops.nqp` and `JASTNodes.nqp` gone with the source lists. Build
   221 s, 10 share-lib jars.
3. **Rakudo's `Raku/Ops.nqp`** (rakudo `2e66c36b3d`): the same treatment
   on the Rakudo side. Make (resumed, not from the top) 955 s, CORE.c
   ~462 s, `t/01-sanity` 25/25, t/03-jvm + t/10-qast 2/2, precomp 13/14.
4. **stage0 as unit artifacts** (nqp `9844a0de9`): `jBootstrapFiles` run
   from the JAST-free driver; stage0 is 9 `unit.meta`-only jars
   (`JASTNodes.jar` gone). Build A (old stage0) 206 s, build B (the new
   stage0 compiling stage1) 263 s, t/nqp 118/118.
5. **The runtime deletions and the loader port** (nqp `1a658daa1`,
   `4b261b3b2`): the whole `jast2bc` package, `Ops.compilejast`,
   `loadcompunit`'s define branch, `MemoryClassLoader`,
   `JarFileClassLoader`, `LibraryLoader.java`, the `.codeprograms.lz4`
   sidecar reader and its `$!codeprograms` pass-through, `IndyBootstrap`
   and the indy budget, `setup_blv`; `CompilationUnit` reshaped around
   `getCodeRefs(): Array<CodeRef>`; `UnitLoader` took over what
   `LibraryLoader` did. Runtime jars and `:nqp-runtime:test` green,
   t/nqp 118/118, eval-server smoke 2/2.
6. **The Java-interop adaptors** (nqp `14df06863`, rakudo `09f349adda`):
   `BootJavaInterop`/`RakudoJavaInterop` generate a plain class with ASM
   and hand it to `AdaptorUnit(cls, descriptors, target)`, a hand-written
   `CompilationUnit` subclass; `ByteClassLoader` defines only that plain
   class. `perl Configure.pl --backends=jvm --gen-nqp` 3 s, `make` FROM
   THE TOP 1185 s (milestone-3 baseline 1154 s), CORE.c 472 s (baseline
   475 s), `t/03-jvm/01-interop.t` 30/30 with 8 in-source skips,
   `t/01-sanity` 25/25.
7. **Gap 5a, torn-frame `LEAVE`** (nqp `d8116d7c9`): a torn frame runs
   its exit handler once, on whichever road reaches it first
   (`runExitHandler` with a `left` guard and a `try`/`finally` in both
   roads). `t/spec/S04-phasers/keep-undo.t` 15/16 -> 16/16.
8. **Gap 5b, the resume value of a suspended typed op** (nqp
   `929f73b11`): a suspension inside a typed op finishes by re-running
   the op instead of answering the inner call's value
   (`NqpCont.Suspend.finish`, `NqpOps.suspendToken`,
   `NqpTypeOps.SuspendedIn`). nqp 112-continuations 26/26, 047 11/11,
   121 16/16.
9. **Gap 5c, the parked item-8 shape** (nqp `e270f070d`): the encoder's
   `patch_params` now keeps the parameter prologue's deferred code-ref
   slots, so a `BVal` in a parameter default or a `where` constraint no
   longer resolves to the mainline (qbid 0). This closed both parked
   t/02-rakudo files, `yada-trait-timing.t` and
   `begin-time-attributive-param-method.t`. nqp clean build 258 s,
   `make` FROM THE TOP 1103 s, `t/01-sanity` 25/25 (312 s on a loaded
   box), t/nqp 118/118. Stage0 needed no regeneration: the change fills
   wire cells the old encoder left at 0.

Deviations from this spec and from the plan, all ledgered:

- **Tasks 5 and 6 ran as one dispatch.** `LibraryLoader.java`'s class
  branches call what Task 5 deletes, so the runtime jar does not compile
  between them.
- **`serializedBlob`, `claimNested` and `engineProgram` stayed `open`
  with throwing bodies instead of becoming `abstract`.**
  `KnowHOWMethods` is a hand-written `CompilationUnit` subclass and
  implements none of them, so `abstract` does not compile. `unitId()`
  kept its non-throwing default.
- **`readToHeapBuffer` / `readToHeapBufferLz4` were not ported.** After
  Task 5 they had no callers.
- **`t/spec/S04-phasers/leave.t` does not exist** (a plan defect), so
  `keep-undo.t` was gap 5a's gate.
- **Gap 5b's Probe A was not an instance of the gap** (`Truthy` coerces
  an already-computed value; the `FETCH` is a separate `DecontOp`). The
  real reproducer is `subset S of Int where { take $_; True }; sub f(-->
  S) { 5 }; gather { say f() }`, which answered `True` and now answers
  `5`.
- **A remake after Task 4.** Task 4 rebuilt nqp stage2 after Task 3's
  make, so the Rakudo jars on disk were stale and `t/01-sanity` read
  0/25 with a `SerializationReader` dependency-version error. The 5+6
  sanity gate moved to Task 7, which had to `Configure --gen-nqp` and
  make from the top anyway.

Known gaps carried out of the milestone, none of them the unit road: the
`p6typecheckrv` failed-check tail after a suspension raises
`dieInternal` rather than `X::TypeCheck::Return`; the same bug class at
the multi-dispatch bind site (`NqpOps.java:176`/`:963`); a finisher that
suspends again reaches the guest as a raw exception; `enter-leave.t` #35
(a `LEAVE` value clobbers a do-block return); and the P6Opaque half of
item 9. The deferred minors are listed per task in the ledger twin.

### The milestone gate (Task 11, 2026-09-10/11)

Run on the final jars — Task 10's nqp build (258 s) and Rakudo `make`
from the top (1103 s, CORE.c window 533 -> 1044 s), log
`/home/longwalker/.claude/jobs/25fa1a35/tmp/t10-make.log`. Nothing was
rebuilt for the gate.

| gate | result |
|---|---|
| t/nqp (Task 10) | 118/118 |
| `t/01-sanity` (Task 10) | 25/25, 312 s on a loaded box |
| precomp, 14 files | 13/14; `rakuast-suspend-precomp-deps.t` is the `RAKUDOLIB=lib` harness gap known since milestone 3 and is green with it, so 14/14 |
| t/03-jvm + t/10-qast | 2/2, 62 s |
| jar census | **35/35 `unit.meta`-only, zero `.class`** — 10 nqp share-lib, 9 stage0, 16 Rakudo |
| t/ sweep | see below: **eleven files red that milestone 3 did not list** |

The sweep ran at **2 servers x 4g, not 3**: `MemAvailable` was 20 g, the
sweep budgets `heap + 3g` off-heap per server against `MemAvailable - 3`,
and 3 x 7 g = 21 g over a 17 g budget would have had the server's own
guard decline the third mid-run. 418 files, 59 of 60 chunks inside the
7200 s ceiling; the kill lost the per-chunk detail, which the sweep only
prints at the end, and its chunk counter is a completion counter, not an
index, so nothing in the log attributes a file. Attribution came from two
reruns: the ten non-`t/02-rakudo` directories as one sweep that completed
(120 files, 1546 s), and `t/02-rakudo` file by file through
`watched-run -t --jobs=3` (298 files, 23 red), with every red file not on
milestone 3's list re-confirmed through the eval server.

Two mechanisms are named:

- **`QAST::OperationsJVM.is_inlinable` lost its table.**
  `%core_inlinability` is now populated only by `map_classlib_core_op`;
  every op that used to arrive through `add_core_op` / `map_jvm_core_op`
  answers 0. Probed: `add_i`, `sub_i`, `mul_i`, `add_n`, `mul_n`, `if`,
  `while`, `list` are all 0, while classlib ops (`add_I`, `concat`,
  `box_i`, `atpos_i`) are 1. RakuAST's `IMPL-INLINE-INFO`
  (`src/Raku/ast/code.rakumod:3301`) dies "Non-inlinable op encountered"
  on any of them, so routine inlining and native-arithmetic lowering
  stop. This is the exact mirror of the `supports_op` finding Task 1's
  review caught: `core_op_supported` was repaired then, `is_inlinable`
  was not. Red because of it:
  `t/08-performance/22-rakuast-ct-dispatch.t`,
  `29-rakuast-attr-self-types.t`, `32-rakuast-native-param-bind.t` (all
  three green in milestone 3, `32` explicitly noted as passing there) and
  `t/02-rakudo/native-return-coercion.t`. It is a runtime-performance
  regression baked into the built setting.
- **A multi-character `Str` range never terminates.**
  `("aa".."ac").elems` hangs; `("a".."e").elems` is 5 and `"aa".succ` is
  `ab`, so the fault is in the range's iteration, not in `succ`. It hangs
  `t/02-rakudo/sort-element-kinds.t` at test 2 and stalled both sweeps in
  that neighbourhood.

Six more are red and not root-caused here:
`t/02-rakudo/21-begin-time-compile-sub.t` ("Failed to deserialize lexical
`$?PACKAGE`"), `custom-declarator-naming.t` ("Method 'find_method' not
found for invocant of class 'MetamodelX::RakuLevelNameHOW'"),
`make-regex-frame.t` (engine refusal: "qastnode walks the caller chain
(curcode)"), `try-statement-backtrace-frame.t` (1/4),
`regex-interpolation-backtrack.t` (3/8), `m-flag-module-spec.t` (1/19).
Caveat: milestone 3's list of 13 came from a chunk-attributed verify
sweep whose infrastructure-attributed FAIL chunks were never resolved per
file, so some of these six may have been red then too.

Expected red, unchanged from milestone 3: the corekeys/settingkeys
cluster (`03-cmp-ok.t`, `03-corekeys*.t` x4, `04-settingkeys-6c.t`,
`04-settingkeys-6e.t`), `begin-called-block-routine.t`,
`compiler-frontend-id.t`, `constant-anon-var-value.t`,
`parse-target-match-tree.t`, `t/05-messages/02-errors.t`,
`t/08-performance/15-rakuast-native-metaop.t` and
`36-rakuast-begin-compiled-remark.t`. The item-8 pair
(`yada-trait-timing.t`, `begin-time-attributive-param-method.t`) is
**green**, confirming Task 10's fix. Two files that fail only cold and
pass through the eval server (`long-int-literal.t`,
`native-argument-snapshot.t`), plus `15-gh_1202.t`, are the cold-run
`$*EXECUTABLE`-spawn gap, not failures.
