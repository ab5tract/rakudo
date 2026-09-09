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
| 4 compiler workload | not started; the CORE.c parse regression (206 -> 389 s) lives here and is accepted as compile-time cost |
| **5 reflection-free unit** | **starting now** (design in progress) |
| **6 unit artifact, no class file** | **starting now**, with 5; bilingual loader first, stage0 flips last; milestone 1 = nqp stage2 as artifacts with t/nqp green |
| 7 encoder takes the refused shapes | nqp DONE (strict-green, nqp `ca71c19cb`); Rakudo census 2026-09-09: 10 op refusals (p6trialbind/p6setbinder, fixed, unbuilt), CORE.c 0; two shapes left, both design items: `custom_args` routine bodies (bind through Binder.kt inside the program) and exit-handler blocks (14 in CORE.c). The raw/immediate unit wrappers are item 6's, not 7's. Census table: `docs/jvm-strict-campaign-handoff.md` |
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
