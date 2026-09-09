# The Truffle-only plan, ranked (2026-09-08)

The direction is settled: everything in both the runtime and the
compiler becomes Truffle-based, no JAST-to-bytecode machinery remains,
and the engine toolchain is the only build. This is the ordered list of
what stands between here and there, with what each item unblocks. The
inventory it ranks is under Phase 5 in `docs/jvm-truffle-migration.md`;
the measurements are in `docs/jvm-jesp.md`.

Rules of the road (user directives, 2026-09-07/08): one compile per
change on the engine toolchain (check the sidecars: `unzip -l
nqp/build/jvm/share/lib/nqp.jar | grep -c codeprograms` must be 1), its
timings are the baseline for the next change; no bytecode-vs-engine
comparisons, no A/B arms; runtime-jar-only changes need no setting
compile at all. Baseline at the directive: CORE.c parse 270.5 s
standalone, `+` loop 82 ns, cold `t/01-sanity` 139 s at 4 jobs, warm
67-81 s.

## Position (2026-09-09)

Where each item stands as the strict campaign pauses and the work
refocuses on 5 and 6 (user decision, 2026-09-09):

| item | state |
|---|---|
| 1 plain call | partial, paused: sited sink and frame-free outer reads landed; the per-call `Object[]` and the mainline OSR shape open |
| 2 language id | partial, paused: HLL-simplification slice 1 landed (hllize off `%hll_ops`); slice 2 (hllbool, box types, hlllist/hllhash) open; diamond 7 re-validation deferred behind it |
| 3 calling convention | partial, paused: frame-free blocks (phase A) landed knob-gated, `NQP_CODE_NOFRAME` off (it breaks the CORE.d compile); dispatch blocks deferred |
| 4 compiler workload | not started; the CORE.c parse regression (206 -> 389 s) lives here. Mechanism (profile 2026-09-07, census 2026-09-09): the compiler's own blocks now run as engine programs, so run-once code pays the DSL interpreter (2% -> 18% of samples) and Truffle compiles it on ~5 cores (61% + 14% JVMCI). Levers, cheapest first: tier policy for compile-time units; Oracle GraalVM's auxiliary engine cache (the artifact road makes units stable); per-node interpreter overhead; items 1-3; milestone 4 drops the JAST stage. **Scheduled after milestone 3 of the unit-artifact plan (user, 2026-09-09)**; the revised rule: a compile-time cost is acceptable only paired with a measured, significant runtime win |
| **5 reflection-free unit** | milestone 1 DONE 2026-09-09: nqp stage2 as artifacts (nqp `e2628a882` after the final-review fix wave; gate ran at `57460ccd7`), all 21 stage2/share-lib jars `unit.meta`-only (zero `.class`), t/nqp 115/115 through `nqp-j-gradle` (113/115 from the rakudo root: 019-file-ops and 063-slurp are cwd-relative); clean build 273 s, suite 487 s at 3 jobs; post-completion gate GREEN 2026-09-09 (Rakudo builds and runs on the artifact nqp, `t/01-sanity` 25/25): see item 6. **Milestone 2 DONE 2026-09-09** (nqp `02f6fd00e`): a runtime compile under `NQP_UNIT` (script, `-e`, EVAL, BEGIN-time unit) is a record built in memory and loaded as a `ProgramUnit` with no class definition; `ProgramUnit` answers `lookupCodeRef(cuid)`; see item 6 |
| **6 unit artifact, no class file** | milestone 1 DONE 2026-09-09: nqp stage2 as artifacts (nqp `e2628a882` after the final-review fix wave; gate ran at `57460ccd7`), all 21 stage2/share-lib jars `unit.meta`-only (zero `.class`), t/nqp 115/115 through `nqp-j-gradle` (113/115 from the rakudo root: 019-file-ops and 063-slurp are cwd-relative); clean build 273 s, suite 487 s at 3 jobs; milestone 2 DONE (below), milestones 3-4 (Rakudo units + the deletions, stage0) open. **Post-completion gate (2026-09-09): GREEN.** Rakudo builds and runs on the artifact nqp; `t/01-sanity` **25/25** at 2 jobs in 210 s. Two blockers were found and fixed, neither of them an artifact/class-road crossing. (a) *Build entry point*, rakudo `a5f9ef3d80`: the Makefile's `J_NQP_RR` (`tools/templates/jvm/Makefile.in`) starts a JVM directly and ended on main class `nqp`, which an artifact `nqp.jar` no longer has (`Could not find or load main class nqp`); it now enters through `org.raku.nqp.runtime.unit.UnitMain <nqp.jar>`, nqp `15c20930c`'s entry, correct on either road. (b) *custom_args*, nqp `e1c29714e` + `2035d43e2`: the four `use`-ing sanity files died in one CORE.c program with `nqpp: unknown tag 11142 at 79 of 1060 words` (reproducer `./rakudo-j -e 'say("abc".subst(/b/,"x"))'`). Wire layout was innocent -- encoder, `NqpWire.java` and reader agree word for word on P6BINDSIG/P6TRYBINDSIG (1 word each) and on the `PARAMS 0 -1 0` header (4 words). `patch_params` spliced that four-word header OVER the one-word placeholder without shifting the positions recorded in `%e<nested>`, so every deferred qbid was written three cells early, onto a neighbouring tag (11142..11145 sat on a STMTS tag and three CODEREF tags whose real slots 82/84/86/88 were still 0). Behind it, a second one: the PARAMS reader re-made the extra-named rejection for a header that declares no parameters, so a custom_args block refused every named argument its Binder exists to bind (`Unexpected named argument 'g'`); `n == 0 && accepted == -1` now suppresses it. Both fixes keep the wire additive and unchanged. Timings for the full build on the fixed toolchain (from the top, after `Configure.pl` cleaned the jvm products): `make` 1173 s; nqp `clean buildJvm` 285 s. **Milestone 2 DONE 2026-09-09** (nqp `02f6fd00e`, plan `docs/superpowers/plans/2026-09-09-jvm-unit-artifact-milestone-2.md`): under `NQP_UNIT` every unit takes the road -- a jar-bound unit with an output is written, anything else is built in memory by the `jvm-build-unit` syscall (`UnitWriter.record()`) and loaded by `loadcompunit` as a `ProgramUnit`; a record compiled while a compilation is under way is retained in `GlobalContext.inMemoryUnitRecords` and embedded under `nested/` by the parent's writer (the milestone-1 refusal is gone); the encoder's four splice-and-shift sites are one `splice_code`. **Deviation from the spec (user, 2026-09-09):** the record road stays behind the knob, because Rakudo builds and runs on the class road until milestone 3; the spec's deletions (string-constant road, its size gate, `ByteClassLoader`'s define road, nested `.class` embedding) are milestone 3's closing item. Gate: `NQP_UNIT=1 clean buildJvm` 296 s, 11/11 share-lib jars `unit.meta`-only; t/nqp on the record road **115/118 in 381 s** (baseline 487 s) -- the three FAILs are encoder refusals the class road hid behind per-block fallback (059/067 `withy general`, 084 `labeled control`; strict-campaign items, runtime-compile side); Rakudo `make` EXIT=0 1274 s, `t/01-sanity` **25/25** in 214 s; Rakudo `-e` with BEGIN and EVAL runs as three records under the knob; a Rakudo module precompiles as an artifact under the knob (its BEGIN closure is re-pointed, so no nested unit: CORE.c's four come from another shape). Open for milestone 3: the record-road mainline frame loses its filename in backtraces; `$*UNIT_FALLBACKS` is a constant 0 scaffold; `--target=jar` without `--output` dies in HLL::Compiler's result dumper on either road (pre-existing). |
| 7 encoder takes the refused shapes | nqp DONE (strict-green, nqp `ca71c19cb`); Rakudo census 2026-09-09: 10 op refusals (p6trialbind/p6setbinder, fixed, unbuilt), CORE.c 0; two shapes left: `custom_args` routine bodies (IN PROGRESS in the campaign session as of 2026-09-09 10:40, uncommitted in the worktree: wire ops P6BINDSIG 33 / P6TRYBINDSIG 34 bind the frame's own csd/args through Binder.kt inside the program, plus a custom_args header flag in the encoder) and exit-handler blocks (14 in CORE.c, not started). The raw/immediate unit wrappers are item 6's, not 7's. Census table: `docs/jvm-strict-campaign-handoff.md` |
| 8 deletion | not started; the "move the sidecar writer first" step dissolves into 6 (the artifact writer becomes the sole writer) |
| 9 ASM outside jast2bc | untouched; note the interop adaptor units (`BootJavaInterop`, `RakudoJavaInterop`) are runtime-generated CompilationUnits and must keep a class road or be rewritten |

Item 7 ran ahead of 5-6 because the 2026-09-08 directive (all QAST via
Truffle) made zero refusals layer 1; it stops here because its last two
shapes and the wrappers all want the unit artifact to exist first.

**The sidecar, placed (side-run 2026-09-09).** `<class>.codeprograms.lz4`
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
   reflection.** Today every code object is a JVM method: the unit
   reflects over `@CodeRefAnnotation` methods into method handles and
   CodeRefs, and the engine's nested-block operation resolves through
   that table. Nothing in 6-8 can go until this does.

6. **A program-and-serialized-context artifact per unit, no class
   file.** The sidecar becomes the unit. Needs 5; then `--target=jar`,
   `--javaclass`, `blib/*.jar` of `.class` files, `LibraryLoader` and
   `ByteClassLoader` change meaning. The bootstrap (stage0) becomes
   serialized programs + SC, and the runner enters through something
   other than `CompilationUnit.enterFromMain`.

7. **The encoder takes over the refused shapes.** CORE.c 6% and
   BOOTSTRAP 11% of blocks still fall back to full bytecode: exit
   handlers, `raw`/`immediate` blocks, `custom_args`, the
   60,000-character program gate, ~90 bail sites. At zero refusals the
   QAST-to-JAST compiler has nothing left to emit but stubs.

8. **Deletion, in this order:** the JAST layer (`Compiler.nqp` 6317
   lines, `JASTNodes.nqp` 679), `jast2bc` (3078, `JASTCompiler.kt` is
   today the only writer of the program sidecar -- move that first),
   `AutosplitMethodWriter`, `IndyBootstrap` (dead today, deletable any
   time), the class loaders, the ASM dependency, the indy budget, the
   build plumbing that assumes class-file output, and the stage jars.

9. **ASM outside jast2bc, on no plan yet:** `P6Opaque` generates
   attribute-storage classes at run time (the engine's fastest attribute
   read depends on them) and the two Java-interop layers generate
   interop classes. A separate workstream once 8 is done.

## Smaller, any time

- The small-int cache knob (`JESP_INTCACHE`), worth re-measuring now
  that the surrounding costs are lower.
- Mainline natives: a `my int` at file scope is a lexical and boxes on
  every read and write; lowering mainline natives helps any loop
  written at file scope.
- A classlib histogram by op name, to attribute the remaining
  method-handle road.
- The never-null `curFrame` lockdown.
