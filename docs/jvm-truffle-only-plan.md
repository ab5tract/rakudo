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

## The list

1. **Arguments in registers** (in progress). Truffle already inlines
   the direct-road callees into the caller's compilation, but every
   argument array still materializes: the prologue parked it on the
   thread context, and a heap store defeats escape analysis. The
   thread-context store is gone (FlatArgs reads the frame's own array),
   and it was not enough: JFR still shows ~200 bytes of `Object[]` per
   iteration and the loop is unchanged at 80-82 ns, so another path
   forces the arrays to materialize. Remaining suspects, in order: the
   call itself (`DirectCallNode.call` hands the callee a fresh frame
   arguments array and profiles it -- `profileArguments` was an
   allocation site in the JFR), the dispatch's variadic argument array
   flowing into the slow-road boundary, and the bind-failure boundary
   that takes `args` on the exception path. Measure by JFR allocation
   rate (bytes per iteration), never by the expansion tree's allocation
   count, which keeps a node for any slow-path materialization. Payoff
   when it lands: ~13 arrays and ~200 bytes per call gone, the GC share
   with them.

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
