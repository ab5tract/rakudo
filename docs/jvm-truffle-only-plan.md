# The Truffle-only plan, ranked (2026-09-08)

The direction is settled: everything in both the runtime and the
compiler becomes Truffle-based, no JAST-to-bytecode machinery remains,
and the engine toolchain is the only build. This is the ordered list of
what stands between here and there, with what each item unblocks. The
inventory it ranks is under Phase 5 in `docs/jvm-truffle-migration.md`;
the measurements are in `docs/jvm-jesp.md`.

Rules of the road (user directives, 2026-09-07/08): one compile per
change on the engine toolchain (check the artifacts: `raku
tools/build/jar-census.raku nqp/build/jvm/share/lib/*.jar` must report
every jar `unit.meta`-only, zero `.class`; the old sidecar check
`unzip -l ... | grep -c codeprograms` is history — there is no sidecar
since milestone 4, 2026-09-10), its
timings are the baseline for the next change; no bytecode-vs-engine
comparisons, no A/B arms; runtime-jar-only changes need no setting
compile at all. Baseline at the directive: CORE.c parse 270.5 s
standalone, `+` loop 82 ns, cold `t/01-sanity` 139 s at 4 jobs, warm
67-81 s.

## Position (2026-09-10)

Where each item stands with milestone 4 of the unit-artifact plan code
complete (2026-09-10) but **not closed** -- its t/ gate found eleven red
files that milestone 3's sweep did not list, two of them with named
mechanisms (see item 6). Item 4, the compiler's own workload, is next
once those are ruled on:

| item | state |
|---|---|
| 1 plain call | partial, paused: sited sink and frame-free outer reads landed; the per-call `Object[]` and the mainline OSR shape open |
| 2 language id | partial, paused: HLL-simplification slice 1 landed (hllize off `%hll_ops`); slice 2 (hllbool, box types, hlllist/hllhash) open; diamond 7 re-validation deferred behind it |
| 3 calling convention | partial, paused: frame-free blocks (phase A) landed knob-gated, `NQP_CODE_NOFRAME` off (it breaks the CORE.d compile); dispatch blocks deferred |
| 4 compiler workload | not started; the CORE.c parse regression (206 -> 389 s) lives here. Mechanism (profile 2026-09-07, census 2026-09-09): the compiler's own blocks now run as engine programs, so run-once code pays the DSL interpreter (2% -> 18% of samples) and Truffle compiles it on ~5 cores (61% + 14% JVMCI). Levers, cheapest first: tier policy for compile-time units; Oracle GraalVM's auxiliary engine cache (the artifact road makes units stable); per-node interpreter overhead; items 1-3; the JAST stage is gone as of milestone 4. **Milestone 4's fix wave landed 2026-09-11 and both its gate regressions are fixed; item 4 is next (user, 2026-09-09), starting with the perf measurement session in `docs/superpowers/plans/2026-09-10-perf-measurement-session.md`. The `is_inlinable` regression that would have invalidated every runtime number is repaired (nqp `47697ca29` + rakudo `548dc2544d`), so the measurement session must run on a build made at or after those -- anything measured on the milestone-4 jars was measured on a setting that never lowered native arithmetic**; the revised rule: a compile-time cost is acceptable only paired with a measured, significant runtime win |
| **5 reflection-free unit** | milestone 1 DONE 2026-09-09: nqp stage2 as artifacts (nqp `e2628a882` after the final-review fix wave; gate ran at `57460ccd7`), all 21 stage2/share-lib jars `unit.meta`-only (zero `.class`), t/nqp 115/115 through `nqp-j-gradle` (113/115 from the rakudo root: 019-file-ops and 063-slurp are cwd-relative); clean build 273 s, suite 487 s at 3 jobs; post-completion gate GREEN 2026-09-09 (Rakudo builds and runs on the artifact nqp, `t/01-sanity` 25/25): see item 6. **Milestone 2 DONE 2026-09-09** (nqp `da1f5088a`): a runtime compile under `NQP_UNIT` (script, `-e`, EVAL, BEGIN-time unit) is a record built in memory and loaded as a `ProgramUnit` with no class definition; `ProgramUnit` answers `lookupCodeRef(cuid)`; see item 6. **Milestone 3 DONE 2026-09-10** (nqp `30e849e3c`, rakudo `a22eb40b73`): the encoder and the record road are the defaults, the knob is gone from the compiler, and every jar Rakudo builds is a `unit.meta`-only artifact entered through `UnitMain` -- 16 Rakudo jars and 11 nqp jars, zero `.class`; see item 6 for the numbers. **Milestone 4 code complete 2026-09-10, gate open** (nqp `55bdee5b7`..`e270f070d`, rakudo `670c3645b0`..`09f349adda`): the reflective road is gone from the runtime, not merely unused -- `CompilationUnit` no longer reflects over `@CodeRefAnnotation` methods into method handles, `getCodeRefs()` is non-null `Array<CodeRef>` for every unit, and the only `CompilationUnit` subclasses left are `ProgramUnit`, the hand-written `KnowHOWMethods`, and `AdaptorUnit` for Java interop; see item 6 for the numbers |
| **6 unit artifact, no class file** | milestone 1 DONE 2026-09-09: nqp stage2 as artifacts (nqp `e2628a882` after the final-review fix wave; gate ran at `57460ccd7`), all 21 stage2/share-lib jars `unit.meta`-only (zero `.class`), t/nqp 115/115 through `nqp-j-gradle` (113/115 from the rakudo root: 019-file-ops and 063-slurp are cwd-relative); clean build 273 s, suite 487 s at 3 jobs; milestone 2 DONE (below), milestones 3-4 (Rakudo units + the deletions, stage0) open. **Post-completion gate (2026-09-09): GREEN.** Rakudo builds and runs on the artifact nqp; `t/01-sanity` **25/25** at 2 jobs in 210 s. Two blockers were found and fixed, neither of them an artifact/class-road crossing. (a) *Build entry point*, rakudo `a5f9ef3d80`: the Makefile's `J_NQP_RR` (`tools/templates/jvm/Makefile.in`) starts a JVM directly and ended on main class `nqp`, which an artifact `nqp.jar` no longer has (`Could not find or load main class nqp`); it now enters through `org.raku.nqp.runtime.unit.UnitMain <nqp.jar>`, nqp `15c20930c`'s entry, correct on either road. (b) *custom_args*, nqp `e1c29714e` + `2035d43e2`: the four `use`-ing sanity files died in one CORE.c program with `nqpp: unknown tag 11142 at 79 of 1060 words` (reproducer `./rakudo-j -e 'say("abc".subst(/b/,"x"))'`). Wire layout was innocent -- encoder, `NqpWire.java` and reader agree word for word on P6BINDSIG/P6TRYBINDSIG (1 word each) and on the `PARAMS 0 -1 0` header (4 words). `patch_params` spliced that four-word header OVER the one-word placeholder without shifting the positions recorded in `%e<nested>`, so every deferred qbid was written three cells early, onto a neighbouring tag (11142..11145 sat on a STMTS tag and three CODEREF tags whose real slots 82/84/86/88 were still 0). Behind it, a second one: the PARAMS reader re-made the extra-named rejection for a header that declares no parameters, so a custom_args block refused every named argument its Binder exists to bind (`Unexpected named argument 'g'`); `n == 0 && accepted == -1` now suppresses it. Both fixes keep the wire additive and unchanged. Timings for the full build on the fixed toolchain (from the top, after `Configure.pl` cleaned the jvm products): `make` 1173 s; nqp `clean buildJvm` 285 s. **Milestone 2 DONE 2026-09-09** (nqp `da1f5088a`, plan `docs/superpowers/plans/2026-09-09-jvm-unit-artifact-milestone-2.md`): under `NQP_UNIT` every unit takes the road -- a jar-bound unit with an output is written, anything else is built in memory by the `jvm-build-unit` syscall (`UnitWriter.record()`) and loaded by `loadcompunit` as a `ProgramUnit`; a record compiled while a compilation is under way is retained in `GlobalContext.inMemoryUnitRecords` and embedded under `nested/` by the parent's writer (the milestone-1 refusal is gone); the encoder's four splice-and-shift sites are one `splice_code`. **Deviation from the spec (user, 2026-09-09):** the record road stays behind the knob, because Rakudo builds and runs on the class road until milestone 3; the spec's deletions (string-constant road, its size gate, `ByteClassLoader`'s define road, nested `.class` embedding) are milestone 3's closing item. Gate: `NQP_UNIT=1 clean buildJvm` 296 s, 11/11 share-lib jars `unit.meta`-only; t/nqp on the record road **115/118 in 381 s** (baseline 487 s) -- the three FAILs are encoder refusals the class road hid behind per-block fallback (059/067 `withy general`, 084 `labeled control`; strict-campaign items, runtime-compile side); Rakudo `make` EXIT=0 1274 s, `t/01-sanity` **25/25** in 214 s; Rakudo `-e` with BEGIN and EVAL runs as three records under the knob; a Rakudo module precompiles as an artifact under the knob (its BEGIN closure is re-pointed, so no nested unit: CORE.c's four come from another shape). Open for milestone 3: the record-road mainline frame loses its filename in backtraces; `$*UNIT_FALLBACKS` is a constant 0 scaffold; `--target=jar` without `--output` dies in HLL::Compiler's result dumper on either road (pre-existing). **Milestone 3 DONE 2026-09-10** (nqp `da1f5088a`..`30e849e3c`, rakudo `5ae25a8d3c`..`a22eb40b73`; plan `docs/superpowers/plans/2026-09-09-jvm-unit-artifact-milestone-3.md`, its ledger and reports beside it). Four pieces. (a) *The last refused shapes*, nqp `c872c83af`: exit-handler blocks, `withy` general, labeled control, and `for :label` on the additive wire op `FORLOOPL = 35`. (b) *The flip*, nqp `388173781`..`e5f2b3840` + rakudo `08a997dc2b`: the encoder and the unit road are on by default (`NQP_UNIT` is gone), the generated runners and the eval server enter through `UnitMain <unit jar>`, and a record-road mainline frame carries its file in backtraces again; two flip regressions were fixed in the encoder (a `BVal` naming a block of the same tree; `with`/`without` over a native condition, which broke every `use Test`). (c) *The gaps the first t/ sweep found*, nqp `171d37508`..`8bab02391`: sized and unsigned natives, the unnamed chain link, suspendable dedicated ops with typed tokens (additive wire op `OPCALLT = 36`), an empty-message NPE, a sized `uint` attribute -- 7 of 8, the eighth parked below. (d) *The compiler-side deletions*, nqp `30e849e3c` + rakudo `a22eb40b73`: item 8. Gate on that toolchain, sleep suppressed (this is the timing baseline): nqp clean build 222 s; `make` 1154 s from the top (rakudo.jar 171 s, BOOTSTRAP v6c starts 200 s, CORE.c 594 s to 1069 s = 475 s, CORE.d 1069 s, CORE.e 1096 s); t/nqp 118/118 on the unit road; t/01-sanity 25/25 in 161 s; precomp 14/14; t/03-jvm + t/10-qast 2/2; all 16 Rakudo jars and all 11 nqp jars `unit.meta`-only; CORE.c carries 4 nested units (8 `nested/` entries). t/ ran twice through the eval server: sweep 1 (after the flip) 7858 s over two invocations on two 6 GB servers; sweep 2 (after the deletions) 7270 s -- the 7200 s ceiling after 59 of 60 chunks on three 4 GB servers, plus a 70 s tail -- with no new failures and 26 files fixed since sweep 1. t/spec did not run (user, 2026-09-09: not until t/ takes under two hours). Parked, real, narrow: a where-constrained parameter of a routine declared *and* called inside one `BEGIN` (two t/02-rakudo files red; evidence and the next lead in the milestone's `task-3b-report.md`). Carried into milestone 4: a suspended typed op resumes with the inner call's value instead of re-running the op (a `take` inside a `Proxy` `FETCH` inside a typed op); torn-frame `LEAVE` never runs on the JVM (both roads, pre-existing); the interop adaptors (item 9). **Milestone 4 CODE COMPLETE 2026-09-10, milestone NOT CLOSED** (nqp `55bdee5b7`..`e270f070d`, rakudo `670c3645b0`..`09f349adda`; plan `docs/superpowers/plans/2026-09-10-jvm-unit-artifact-milestone-4.md`, its ledger twin and eleven task reports beside it). Everything the milestone set out to build landed: the JAST-free driver (`Compiler.nqp` 6363 -> 1948 lines), `JASTNodes.nqp` and both `Ops.nqp` op tables deleted, **stage0 regenerated as 9 `unit.meta`-only artifact jars**, the whole runtime class road deleted (jast2bc, the sidecar and its `$!codeprograms` pass-through, `LibraryLoader`, `MemoryClassLoader`, `JarFileClassLoader`, `IndyBootstrap`, the indy budget, `setup_blv`, the per-block stub emission, `CompilationUnit`'s reflective half), the interop adaptors moved onto `AdaptorUnit` (item 9's adaptor half), and all three carried gaps fixed (torn-frame `LEAVE`, the resume value of a suspended typed op, and the parked where-in-`BEGIN` shape, which closed both parked t/02-rakudo files). Numbers: nqp clean build 214-263 s (baseline 222 s); `make` from the top 1185 s at Task 7 and 1103 s at Task 10 (baseline 1154 s), CORE.c 472-511 s (baseline 475 s); t/nqp 118/118; `t/01-sanity` 25/25; precomp 13/14, 14/14 with `RAKUDOLIB=lib`; t/03-jvm + t/10-qast 2/2; interop 30/30; **census 35/35 jars `unit.meta`-only, zero `.class`** (10 nqp share-lib, 9 stage0, 16 Rakudo). **What holds the milestone open is the t/ gate** (2026-09-10/11, on the final jars, 2 servers x 4g -- 3 x 4g exceeds the sweep's own budget at 20 g MemAvailable): eleven files are red that milestone 3's sweep 2 did not list, with two mechanisms named. (a) **`QAST::OperationsJVM.is_inlinable` lost its table.** `%core_inlinability` is now filled only by `map_classlib_core_op`; the ops that used to arrive through `add_core_op`/`map_jvm_core_op` -- `add_i`, `sub_i`, `mul_i`, `add_n`, `mul_n`, `if`, `while`, `list` -- answer 0, so RakuAST's `IMPL-INLINE-INFO` refuses to inline any routine that uses them and native arithmetic stops lowering. This is the mirror of the `supports_op` finding Task 1's review caught and fixed; `core_op_supported` was repaired, `is_inlinable` was not. Red because of it: `t/08-performance/22-rakuast-ct-dispatch.t`, `29-rakuast-attr-self-types.t`, `32-rakuast-native-param-bind.t` (all three green in milestone 3) and `t/02-rakudo/native-return-coercion.t`. It is a **runtime-performance** regression baked into the built setting, not a test-content failure. (b) **A multi-character `Str` range never terminates**: `("aa".."ac").elems` hangs (`"a".."e"` is fine, `"aa".succ` is fine), which hangs `t/02-rakudo/sort-element-kinds.t` and stalled both sweeps. Six more are red and not yet root-caused: `21-begin-time-compile-sub.t` ("Failed to deserialize lexical `$?PACKAGE`"), `custom-declarator-naming.t` ("Method 'find_method' not found for invocant of class 'MetamodelX::RakuLevelNameHOW'"), `make-regex-frame.t` (engine refusal: "qastnode walks the caller chain (curcode)"), `try-statement-backtrace-frame.t`, `regex-interpolation-backtrack.t`, `m-flag-module-spec.t`. Caveat on the comparison: milestone 3's list of 13 came from a chunk-attributed verify sweep whose infrastructure-attributed FAIL chunks were never resolved per file, so some of the six may have been red then too. Expected red, unchanged: the corekeys/settingkeys cluster (7 files), `t/05-messages/02-errors.t`, `t/08-performance/15-rakuast-native-metaop.t` and `36-rakuast-begin-compiled-remark.t`, `begin-called-block-routine.t`, `compiler-frontend-id.t`, `constant-anon-var-value.t`, `parse-target-match-tree.t`. The item-8 pair (`yada-trait-timing.t`, `begin-time-attributive-param-method.t`) is green, as Task 10 promised. **FIX WAVE 2026-09-11 -- both named mechanisms are fixed** (nqp `908134f3f`, `47697ca29`, `3b9615f4b`, `b3d75f993`; rakudo `548dc2544d`, `cd5799df09`). (a) `is_inlinable` now answers HLL override, then the classlib registry, then an explicit twelve-name `%core_noninlinable` table (the ops that carried `:!inlinable` on their deleted `add_core_op` call), and otherwise the same "the encoder has a row for it" rule `core_op_supported` uses; the five Raku ops that said `:!inlinable` through `add_hll_op` say it again through `set_hll_op_inlinability` in `src/vm/jvm/Raku/Ops.nqp`, which is correctness rather than speed (an inlined `p6return` or signature binder acts on the inliner's frame). Probed before the make and pinned by a new test, `nqp/t/jvm/16-op-registry.t`: `add_i`/`if`/`while`/`list`/`callmethod`/`defor`/`control`/`getlexouter` = 1, `call`/`callstatic`/`dispatch`/`syscall`/`handle`/`handlepayload`/`usecapture`/`savecapture`/`ctx`/`curlexpad`/`p6return`/`p6bindsig` = 0. `t/08-performance/22`, `29` and `32` are **green**. (b) The `Str` range hang was **not** CORE.c's build of `SEQUENCE` and not the compiler at all: the gather block's record and its wire program are structurally identical to a working precompiled module copy (879 wire words each, differing at 44 operand positions, every one a string-table, SC-handle, handler or qbid index), and the pre-Task-8 runtime hangs identically. The cause is `CallFrame`: the continuation save road called `leave()`, giving the frame's live-invocation count back and pointing `priorInvocation` at the frame being packed away, so a **second invocation of the same static frame** -- which `SEQUENCE`'s multi-character branch creates, because it builds each character position's range with the sequence operator, i.e. with `SEQUENCE` -- resolved its blocks' outer to the suspended outer invocation. The inner `$stop = 1` landed in the wrong frame's lexicals and its `until $stop` never saw it. `leaveSuspended()` now restores `tc.curFrame` and nothing else; the real exit still gives the count back exactly once. `("aa".."ac").elems` = 3, `sort-element-kinds.t` **green**, regression test `t/02-rakudo/nested-invocation-continuation.t` 6/6. (c) Also in the wave: a continuation-captured frame keeps its exit handler for its real exit (`gather { LEAVE ...; take 1; take 2 }` fires once, after the block ends, not at the first `take`), `UnitLoader` records a unit as loaded only after the load succeeds, the `$extra_ops` list names its three consumers, and the stale JAST/`add_core_op`/stage0-`NQP_CODE_RUN` comments are gone. **New timings, and these are the milestone's baseline** (the earlier 1103-1185 s / 472-511 s were taken with the inliner idle and are not comparable to anything): nqp `clean buildJvm` 253 s; `make` from the top **1142 s** (rakudo.jar 163 s, BOOTSTRAP v6c 193 s, CORE.c 585 s to 1052 s = **467 s**, CORE.d 1058 s, CORE.e 1084 s) against milestone 3's 1154 s / 475 s. Still open from the gate's eleven: `native-return-coercion.t` is **unchanged at 19/23**, so its four `dies-ok` failures were never the `is_inlinable` regression and need their own session; the other six were not root-caused in this wave |
| 7 encoder takes the refused shapes | nqp DONE (strict-green, nqp `ca71c19cb`); Rakudo census 2026-09-09: 10 op refusals (p6trialbind/p6setbinder, fixed, unbuilt), CORE.c 0; two shapes left: `custom_args` routine bodies (IN PROGRESS in the campaign session as of 2026-09-09 10:40, uncommitted in the worktree: wire ops P6BINDSIG 33 / P6TRYBINDSIG 34 bind the frame's own csd/args through Binder.kt inside the program, plus a custom_args header flag in the encoder) and exit-handler blocks (14 in CORE.c, not started). The raw/immediate unit wrappers are item 6's, not 7's. Census table: `docs/jvm-strict-campaign-handoff.md`. **Rakudo shapes DONE 2026-09-10**: `custom_args` routine bodies landed in the campaign (P6BINDSIG/P6TRYBINDSIG); exit-handler blocks landed with `withy` general, labeled control and `for :label` in milestone 3 (nqp `c872c83af`), and the milestone's first t/ sweep found and closed seven more runtime-compile refusals (nqp `171d37508`..`8bab02391`). One shape was parked, not fixed: a where-constrained parameter of a routine declared and called inside one `BEGIN`, a code-ref pairing fault in a dynamically compiled unit rather than an encoder refusal (two t/02-rakudo files red). **FIXED 2026-09-10** in milestone 4 (nqp `e270f070d`): `patch_params` was overwriting the parameter prologue's deferred code-ref slots, so a `BVal` in a parameter default or a `where` constraint resolved to the mainline (qbid 0); `yada-trait-timing.t` and `begin-time-attributive-param-method.t` are green. Item 7 is closed |
| 8 deletion | **DONE 2026-09-10** (compiler side nqp `30e849e3c` + rakudo `a22eb40b73` in milestone 3; runtime side nqp `55bdee5b7`..`e270f070d` + rakudo `670c3645b0`..`09f349adda` in milestone 4). Nothing in either tree is JAST-named any more and there is no class road: `Compiler.nqp` is a 1950-line unit driver over the QAST tree (was 6363), `JASTNodes.nqp` and `nqp/src/vm/jvm/NQP/Ops.nqp` are deleted, and with them the whole `jast2bc` package (`JASTCompiler.kt`, `JastClass.kt`, `JavaClass.kt`, `AutosplitMethodWriter`), `Ops.compilejast`, `loadcompunit`'s define branch, `MemoryClassLoader`, `JarFileClassLoader`, `LibraryLoader.java`, the `.codeprograms.lz4` sidecar with its reader and its `$!codeprograms` pass-through, the JAST method carrier and `@CodeRefAnnotation`'s reflective half, `IndyBootstrap` and the indy budget, the per-block stub emission (arity check, locals, postlude, save sites, `getCallSites`/`entryQbid`), `setup_blv`, and the class-file build plumbing including `JASTNodes.jar` from stage0 (9 bootstrap jars now, all `unit.meta`-only). What deliberately stays: **ASM**, for `P6Opaque`'s generated attribute-storage classes and for the interop adaptors (item 9), and `ByteClassLoader`, now defining only the adaptors' plain generated class. The `NQP_CODE_RUN`-presence caveat this row used to carry died with stage0's class-road compiler |
| 9 ASM outside jast2bc | **adaptor half DONE 2026-09-10** (nqp `14df06863`): the interop adaptors no longer subclass a generated `CompilationUnit`. `BootJavaInterop`/`RakudoJavaInterop` generate a plain class with ASM and hand it to `AdaptorUnit(cls, descriptors, target)`, a hand-written `CompilationUnit` subclass that owns the code refs; `ByteClassLoader` defines only that plain class. Gate: `t/03-jvm/01-interop.t` 30/30 (8 in-source skips). **P6Opaque half OPEN**: `P6Opaque` still generates attribute-storage classes at run time with ASM (the engine's fastest attribute read depends on them), and ASM stays in the build for it and for the adaptors. That is now the only ASM left |

Item 7 ran ahead of 5-6 because the 2026-09-08 directive (all QAST via
Truffle) made zero refusals layer 1; it stops here because its last two
shapes and the wrappers all want the unit artifact to exist first.

**The sidecar, placed (side-run 2026-09-09) — HISTORY, gone 2026-09-10.**
Everything in this paragraph is written in the present tense of
2026-09-09. None of it exists any more: milestone 4 deleted the sidecar,
its writer, its readers and the whole class road with them; the unit
artifact carries the programs, byte-framed, inside `unit.meta`. Kept
because it explains why the artifact format frames by byte.
`<class>.codeprograms.lz4`
came in with nqp `404d9f898` (2026-09-02) when CORE.c overflowed the
class-file constant pool (71010 program strings against 65535, on top
of the 65535-byte cap per constant that the encoder's 60000-char gate
guards). It is held up by six sites: `Compiler.nqp` (`@*ENGINE_PROGRAMS`,
the index stub), `JASTNodes.nqp` (`JAST::Class.codeprograms`), the
jast2bc writer (`JASTCompiler.kt`, `JastClass.kt`, `JavaClass.kt`) and
the runtime readers (`CompilationUnit.loadEnginePrograms`,
`LibraryLoader`, `CodeEngine.codeRunIdx`). Its framing is by grapheme
count, an NFG accident that cost a reader bug and an O(n^2) first fix;
the artifact format must frame by byte. It is not removed on its own: it
is the seed of item 6, and the 2026-09-09 gate lift (`:sidecar`) already
treats it as the primary road, confining the class-file limits to the
runtime-compile string road, which item 6 retires too.

## The list

1. **Arguments in registers, which turned out to mean the plain call.**
   The loop bench's `+` and assign run on special roads and had hidden
   what an ordinary sub call costs: 462 ns and ~1 KB per call, none of
   it the argument arrays. Landed so far: the sink of a statement's
   value as a sited op (the value's `sink` was called through the
   generic method-dispatch road, building a descriptor, a string key and
   a frame per call: sub loop 462 → 239-249 ns), and outer lexical reads
   that no longer force a frame (the program gets its code ref; a block
   whose only lexical traffic is with its outers runs frame-free). Still
   open on this item: the `+` loop's own `Object[]` (~200 B/iter, not the
   thread-context store, not the catch handlers -- both tried), with the
   call node's own frame-arguments array and its argument profiling as
   the remaining suspect; and the mainline shape of the bench, which
   only ever compiles by on-stack replacement onto the interpreter's
   real frame. Measure by JFR allocation rate, never by the expansion
   tree's allocation count.

2. **A two-valued language id instead of `HLLConfig` identity.** The
   only languages that exist are `nqp` and `Raku`; NQP cannot go
   (RakuAST, the metamodel, the dispatchers and the bootstrap are NQP
   code). What diamond 7 tripped over was not a third language but a
   third config object: a bootstrap holds the compiler's and the
   compilee's `nqp` configs as distinct objects. Carry a two-valued id
   on each block in the wire header and on each STable as its owner,
   compare ids, and let the encoder hand the id as a constant to every
   op that today reads the language off `tc.frame` (`hllbool`, the box
   types, `hlllist`/`hllhash`, getattr's native boxing, the `hllize`
   site). Every same-language decision moves to encode time; the
   runtime check and the config-identity trap go; `%hll_ops` shrinks to
   the genuinely dynamic few; a whole class of "needs a frame" reasons
   disappears. It does not shorten the class-file inventory, which is
   why it sits here and not at the top: it is a prerequisite for
   retiring the frame, not the class file. `HLLConfig` stays as the
   per-language table.

3. **The calling convention.** `ArgsExpectation` (the engine's direct
   road is gated on `USE_BINDER`), `StaticCodeInfo.mh`/`mhResume`, and
   `CallFrame`'s argument storage. With arguments in registers (1) and
   the language static (2), what still forces a frame is a short list
   the docs already keep (`docs/jvm-truffle-calling-convention.md`);
   retire the method-handle invoke road and leave `CallFrame` as the
   reified-frame shim for introspection only.

4. **The compiler's own workload.** The last profile of a CORE.c
   compile: Truffle compiler threads 61% and JVMCI 14% of all CPU
   samples, the main thread 17%. The engine JIT-compiles run-once
   compiler code on about five cores for the whole compile. That is the
   compile-time problem, and it is a tier-policy problem, not a diamond:
   compilation thresholds and budget for code that runs a handful of
   times, plus the per-node interpreter overhead the sites added. It is
   parallel to 1-3 and can start any time; it is placed here because it
   is the largest lever on the number the user watches most, and because
   items 1-3 do not touch it.

5. **A `CompilationUnit` that maps block ids to code objects without
   reflection — DONE (milestones 1-4).** Every code object used to be a
   JVM method: the unit reflected over `@CodeRefAnnotation` methods into
   method handles and CodeRefs, and the engine's nested-block operation
   resolved through that table. All of it is gone; `getCodeRefs()` is a
   plain non-null array.

6. **A program-and-serialized-context artifact per unit, no class
   file — DONE (milestones 1-4).** The sidecar became the unit, and then
   the sidecar itself went. `--target=classfile` has no artifact form,
   every `blib/*.jar` and every stage jar is `unit.meta`-only,
   `LibraryLoader` is deleted, `ByteClassLoader` defines only the interop
   adaptors' plain class, stage0 is serialized programs + SC, and every
   runner enters through `UnitMain <unit jar>` rather than
   `CompilationUnit.enterFromMain`.

7. **The encoder takes over the refused shapes.** CORE.c 6% and
   BOOTSTRAP 11% of blocks still fall back to full bytecode: exit
   handlers, `raw`/`immediate` blocks, `custom_args`, the
   60,000-character program gate, ~90 bail sites. At zero refusals the
   QAST-to-JAST compiler has nothing left to emit but stubs.

8. **Deletion — DONE 2026-09-10.** As planned, in this order: the JAST
   layer (`Compiler.nqp` 6363 lines down to a 1948-line unit driver,
   `JASTNodes.nqp` and both `Ops.nqp` op tables deleted outright),
   `jast2bc` in full including `JASTCompiler.kt` and
   `AutosplitMethodWriter`, the program sidecar with its writer and its
   readers, `IndyBootstrap` and the indy budget, `LibraryLoader`,
   `MemoryClassLoader` and `JarFileClassLoader`, the build plumbing that
   assumed class-file output, and the stage jars — stage0 included, now
   nine `unit.meta`-only artifacts. Two things this entry named do NOT
   go: **the ASM dependency**, which item 9's remaining half still needs,
   and `ByteClassLoader`, which now defines only the interop adaptors'
   plain generated class.

9. **ASM outside jast2bc — adaptor half DONE 2026-09-10, P6Opaque half
   open.** The two Java-interop layers no longer generate a
   `CompilationUnit`: they generate a plain class and hand it to
   `AdaptorUnit`. What is left is `P6Opaque` generating attribute-storage
   classes at run time (the engine's fastest attribute read depends on
   them), and it is the only reason ASM is still a dependency.

## Smaller, any time

- The small-int cache knob (`JESP_INTCACHE`), worth re-measuring now
  that the surrounding costs are lower.
- Mainline natives: a `my int` at file scope is a lexical and boxes on
  every read and write; lowering mainline natives helps any loop
  written at file scope.
- A classlib histogram by op name, to attribute the remaining
  method-handle road.
- The never-null `curFrame` lockdown.
