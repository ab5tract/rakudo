# Strict-refusal campaign — context transfer (2026-09-08, evening)

Resume point for the zero-refusals campaign. Read the "Don't relearn these"
section first — it is the stuff that keeps getting re-explained.

## Don't relearn these (facts, not opinions)

- **Two engines, two names.** The *Truffle compiler* is the QAST encoder
  (`nqp/src/vm/jvm/QAST/TruffleEncoder.nqp`) plus the wire consumer
  (`nqp/nqp-truffle/.../NqpProgramBuilder.java`, `NqpWire.java`,
  `NqpOps.java`, `NqpRootNode.java`). The *Truffle regex engine* is
  `QAST::RxDescriptor` → `RxWire.kt` → `NqpGrammarEngine.kt`; it already
  works and the compiler only emits an `rxmatch` op referencing the
  descriptor. Regex is NOT a refusal.
- **watched-run.raku, streamed so the user can follow it.** Long builds/tests
  go through `raku tools/build/watched-run.raku` as a plain background job.
  Do NOT arm a Monitor per gradle task: monitors are for precise signals
  and must never fire more often than every 90s (user rule, 2026-09-08).
- **Two git trees.** rakudo root + nested `nqp/` (gitignored, NOT a
  submodule). nqp changes: `cd <abs>/nqp && git ...` in its own call (the
  worktree guard refuses `git -C`); gradle as `./nqp/gradlew -p nqp` from the
  root. Label hashes by tree.
- **Every build/run needs `RAKUDO_RAKUAST=1`.** (As written in 2026-09-08
  this line also said `NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1`. Since milestone 3
  of the unit artifact those two are not knobs and must NOT be set at all.)
- **Env-gate every debug print** (`nqp::getenvhash()<VAR>` / `System.getenv`).
- **Stage0 jars carry wire programs**, so a wire change must be ADDITIVE:
  new op numbers only, never a changed layout of an existing op. (In
  2026-09-08 terms that meant an `nqp.codeprograms.lz4` sidecar inside each
  class-road bootstrap jar; since milestone 4, 2026-09-10, stage0 is nine
  `unit.meta`-only artifact jars and the programs live in the unit. The
  additive rule is unchanged.)
- **Backtraces omit engine closures.** A nested block run by the engine has
  no name (its CodeRef `name` is an uninitialized lateinit on the script
  road, the enclosing routine's name on the jar road) and does not appear
  as an `in <anon>` frame. "in obtain" can mean "in a closure inside
  obtain". Task open: give anonymous blocks names (RakuAST could at least
  number them).
- **Jars from different stages cannot be mixed** (serialization dependency
  versions). To test a stage2-compiled module in isolation, compile the
  module AND its dependencies with the stage1 compiler into one directory
  (the `tmp/mo` recipe below).
- **nqp-m is on this box** (`~/.rakubrew/versions/moar-2026.07/bin/nqp-m`):
  ground truth for NQP semantics. Use it before calling anything a bug.
- **NQP's Test setting speaks TAP**: `plan`/`ok`/`is` from
  `nqp/src/core/testing.nqp`; new coverage goes in `nqp/t/nqp/NNN-*.t`.

## Where we are

**nqp `8f9640095` (this branch, unpushed): the nqp bootstrap builds with
`NQP_CODE_STRICT=1` end to end — zero Truffle-compiler refusals — and the
resulting compiler runs.** `BUILD SUCCESSFUL in 9m54s` (clean, strict).
`t/nqp/121-for-controls.t` passes 16/16 on it under strict.

What closed the campaign today:

- `for` → new wire op **W_FORLOOP (32)**: a handled loop whose per-iteration
  fetch runs OUTSIDE the redo loop and only the block call inside it
  (Compiler.nqp's redo label sits between fetch and call). Zero allocation
  per iteration. The previous desugar through `handle` could never work: a
  handle's handler is a nested block, a separate frame that cannot see the
  enclosing block's locals — hence "unknown local for_redo". `:nohandler`
  is a plain W_LOOP over fetch+call. Labeled `for` still refused (nothing
  emits one: NQP has no loop labels, Raku's `for` is its own loop).
- `postinc`/`postdec`: old value into a scratch local, rebind ±1, answer the
  local; same fresh-tree clones and null→0 auto-viv as preinc.
- `indexingoptimized`: operand wanted as str.
- **The runtime bug the campaign exposed**: `NqpOps.AttrSite` (the getattr/
  bindattr inline cache) guarded on the storage class only. `BUILDALL`
  (NQPMu.nqp) binds every attribute of an object through ONE `bindattr`
  with a computed name; once it encoded (it used to refuse), the site
  resolved for `@!stack` and then wrote `@!spill_locals`'s empty list into
  the `@!stack` field. First symptom: the stage2 compiler's `obtain` died
  with an NPE in `bindpos` on the very first compile. Fix: the site records
  class handle + name and the fast path requires both (two reference
  compares). `bindpos` on a null array now dies with the block name.
- Semantics checked against nqp-m: a `redo` in a `for` body does NOT re-run
  the body on any backend (moar, JVM bytecode, JVM Truffle all answer
  `7,8 n=2`), and a control thrown from a *called sub* has no handler on
  any of them. The new test pins what all three answer.

**Unit artifact milestone 1 DONE 2026-09-09: nqp stage2 as artifacts (nqp `57460ccd7`), all 21 stage2/share-lib jars `unit.meta`-only (zero `.class`), t/nqp 115/115 through `nqp-j-gradle` (113/115 from the rakudo root: 019-file-ops and 063-slurp are cwd-relative); clean build 273 s, suite 487 s at 3 jobs**

## Runtime regressions of the first strict-green build (nqp `c131b8933`)

The first strict-green build passed 85/113 t/nqp files; the stage0
bootstrap runner passes all but 019-file-ops and 063-slurp (cwd-relative
paths). The 26 regressed files had four causes, all fixed in `c131b8933`:

- **numify used `encode_node`** (18 files): the node road only passes the
  want down and answers the child's own type, so `numify(~$/)` answered a
  str and `dec_number` handed `QAST::NVal.new` a P6str. Rule: an op that
  *coerces* goes through `encode_child`, as stringify/intify already did.
- **Frame-free blocks vs frame-reading ops.** `getlexdyn`/`bindlexdyn`
  walked from `tc.frame.caller`; a frame-free block runs on its caller's
  frame, so the declaring frame right above was skipped ("Dynamic variable
  '$*NEXT_QBID' not found" on every runtime compile: roles, regex
  interpolation, build-tweak). The walk now starts at the current frame,
  which is what MoarVM's `MVM_frame_getdynlex` does (interp.c hands it
  `tc->cur_frame`). The throw family and the loop controls read `cf` for a
  resumed handler's result and NPE'd on `cf == null` (044-try-catch,
  112-continuations): `die/die_s/throw/rethrow/throwextype/throwpayloadlex*/
  control/continuation*/ctx` now force a frame (`%frame_forcing_ops`).
- **W_LOOP repeat pre-run emitted outside the loop's Block**: a second,
  void operation where the parent expected one value child ("StoreLocal
  expected a value-producing child", every `repeat {} while` in
  014-while.t). Pre-existing builder bug, exposed because mainlines with
  `repeat` only now encode.
- 114-pod-panic ("Too many positionals passed") went away with the above
  (its `error` callback throws from a frame-free block).

The first Rakudo `make` on that nqp died in CORE.c's very first dispatch:
"Argument 0 to the 'dispatcher-delegate' syscall is a obj, but should be a
str". dispatchers.nqp delegates to `nqp::can($c, 'WRAPPERS') ??
'raku-invoke-wrapped' !! 'raku-invoke'`; the encoder boxed both arms of an
untyped `if` to object, so the callsite's argument flag said obj. Fixed
(nqp `HEAD` after `c131b8933`): an untyped if/ternary takes the arms'
common type (the condition's for the two-arm value form), object only when
they differ -- Compiler.nqp's rule; `coerce_at` retro-fits a COERCE around
an already encoded arm. `t/nqp/122-ternary-typing.t`.

With that, `make` built Rakudo end to end (BOOTSTRAP v6c 325 s; CORE.c
494 s: parse 370, optimize 35, jast 36 -- the parse was 206 s on
2026-09-06, so the ~374 newly encoded compiler blocks cost real compile
time). The first `t/01-sanity` sweep: 21/25, the four `use`-ing files
died in the `List:D` return check of `Parameter.constraint_list` called
from RakuAST's duplicate-multi check. `NQP_RV_TRACE=1` (RakOps) showed
the value was an un-hllized NQPArray: the engine's hllize site is
cu-based on its identity fast path only, and its miss road went to
`Ops.hllize`, which reads the FRAME's language -- the caller's, for a
frame-free callee entered across languages. Fixed runtime-only (nqp
`ca71c19cb`): `Ops.hllizeIn` takes the language, both engine roads pass
`NqpRaw.hll(cu)`. Of all frame-HLL-reading ops in Ops.kt, hllize was the
one missing from the encoder's `%hll_ops`/`%frame_forcing_ops`.

Lesson: "validated by the build advancing past it" is compile-time only.
Every newly covered op turns ~hundreds of blocks from bytecode into engine
programs, and the *runtime* of those blocks is what t/nqp tests. Run the
suite after every coverage step, against the stage0-runner baseline.

## Rakudo-side census (2026-09-09, on nqp `ca71c19cb` + rakudo `ce0418cab5`)

Every compile of the Rakudo build replayed from the Makefile's recipes
into a scratch dir with `NQP_CODE_REPORT=1 NQP_CODE_BAIL=1 NQP_CODE_WHY=1`
(the verdict trace is the honest census: `code bail:` only sees a
`cbail`, while exit handlers, raw/immediate targets and the size gate
return '' silently). Real refusals in the WHOLE build: **10**, two ops:

| unit | verdicts | real bails | other non-encoded |
|---|---|---|---|
| Pod, ModuleLoader, Ops, SysConfig, Metamodel, Compiler, Actions, Grammar, rakudo.nqp | 3770 | 0 | unit wrappers only |
| Optimizer | 238 | 1 (`p6trialbind`) | wrappers |
| BOOTSTRAP v6c | 9330 | 9 (`p6trialbind` 6, `p6setbinder` 3) | 12 size gate (6 BEGIN bodies 67k-134k, each asked twice), wrappers |
| v6d, v6e | 16 | 0 | wrappers |
| CORE.c | 23777 | **0** | 1195 immediate targets (comp_mode 1), 14 exit handlers, 1 size gate, wrappers |
| CORE.d, CORE.e | 770 | 0 | wrappers |

"Wrappers" = Compiler.nqp's own per-unit `raw` blocks (deserialize,
load, main) and the `immediate` blocks under them, three raw + N
immediate per compilation unit including every BEGIN-time runtime
compile (Metamodel: 37 raw / 72 immediate = ~36 runtime compiles).
They are plan layer 2 (the stub shell), not coverage.

What the census CANNOT see (fixed for the next run, unbuilt): a
`custom_args` block (Raku: sub-signatures, generic/coercive params,
capture slurpies -- the routine binds through Binder.kt via
`p6bindsig`) is bypassed by Compiler.nqp before the encoder; it now
reports `-> no: custom_args` through `TruffleEncoder.why`. CORE.c's
1195 immediate targets are children of blocks the encoder never got,
i.e. most likely custom_args routine bodies: the real CORE.c gap is
those bodies (dispatch is unaffected -- the dispatchers are Truffle
programs; only the callee body is bytecode).

Fixes committed but NOT yet built or tested (amend on break): rakudo
`4427bb935e` moves `p6trialbind`/`p6setbinder` onto `register_op_desugar`
(src/vm/jvm/Raku/Ops.nqp); nqp `b6f9e033b` confines the size gate to the
string-constant road (`:sidecar` from Compiler.nqp) and hoists `why` to
a class method with a cached knob, called for the custom_args bypass.

CORE.c timings this run: parse 389 s, qast 32 s, jast (encode) 36 s,
classfile 4 s. Decision on the parse regression (206 -> 370-389 s):
accepted as compile-time cost per the user's runtime-over-compile-time
priority; it is the compiler's own ~374 newly encoded blocks running as
engine programs, i.e. plan item 4 (tier policy), not a coverage item.

**Pivot (user, 2026-09-09): plan items 5-6 (reflection-free
CompilationUnit + unit artifact without a class file) come BEFORE the
rest of the strict work.** Design in progress; see
docs/superpowers/specs/ when written.

## The Rakudo-side census (2026-09-09, morning)

Every unit the Makefile compiles, replayed from its recipe into a scratch
dir with `NQP_CODE_REPORT=1 NQP_CODE_BAIL=1 NQP_CODE_WHY=1` (the driver:
`make -n -B j-all`, one `--output` per unit, blib untouched). NQP_CODE_WHY
is the honest knob: it prints EVERY verdict, including the silent
fallbacks the bail knob and strict mode never saw (exit handler, raw and
immediate blocktype, the size gate). Results:

| unit | verdicts | real bails | other non-encoded |
|---|---|---|---|
| Pod, ModuleLoader, Ops, SysConfig, Metamodel, Compiler, Actions, Grammar, rakudo.nqp | 4,000 | 0 | wrappers only |
| Optimizer | 238 | 1 (`p6trialbind`) | wrappers |
| BOOTSTRAP v6c | 9,330 | 9 (`p6trialbind` 6, `p6setbinder` 3) | 12 size gate, wrappers |
| CORE.c | 23,777 | **0** | 14 exit handler, 1 size gate, 1195 orphaned immediates, wrappers |
| CORE.d / CORE.e | 770 | 0 | wrappers |

"Wrappers" = the class-file scaffolding Compiler.nqp adds per unit (a raw
deserialize/load/main block, their immediate children) and the same for
every runtime compile during BEGIN (comp_mode 0). That is plan item 5-6
territory (the unit artifact), not coverage.

What the census could NOT count: **custom_args blocks**. Compiler.nqp
bypassed the encoder for them without a verdict. A custom_args block is a
Raku routine whose signature needs the full runtime Binder (sub-
signature, generic or coercive parameter, capture slurpy, role
parametric signature): RakuAST emits no lowered parameters, only the
prologue `if p6bindwillresume { assertparamcheck(p6trybindsig) } else
{ p6bindsig }`. Dispatch to such a routine is on the Truffle dispatch
programs like any other; its BODY ran as bytecode. The 1195 orphaned
immediates in CORE.c (immediate blocks whose parent never encoded, so
they could not be inlined) are those routines' loop and conditional
bodies, so the count is in the hundreds at least.

Fixed in this pass (nqp `b6f9e033b` + the custom_args commit, rakudo
`4427bb935e`):

- `p6trialbind`/`p6setbinder`: `register_op_desugar` in src/vm/jvm/Raku/
  Ops.nqp (a call of the module's proto), so the encoder reaches them.
- The size gate is the string road's alone: a jar-bound unit ships
  programs in the LZ4 sidecar by index (Compiler.nqp passes `:sidecar`).
- **custom_args on the engine**: wire ops P6BINDSIG 33 (a statement:
  bind, or return from the program when the binder auto-threaded -- the
  autothreader already stored the result on the caller and the direct
  road ignores a framed program's value) and P6TRYBINDSIG 34 (1/0 for the
  assertparamcheck around it). Both frame-forcing; NqpOps reaches
  RakOps.p6bindsig/p6trybindsig through the same reflective handles as
  p6argvmarray and puts the flattened csd/args back on the frame.
  patch_params emits an empty header (required 0, accepted -1, no
  params) for a custom_args block: the arity check still runs because it
  is what stores csd/args on the frame for the binder. Compiler.nqp no
  longer bypasses the encoder; `TruffleEncoder.why` is a class method so
  a bypass verdict could be printed from there (kept for the census).

**The CORE.c parse regression (206 s -> 370-389 s) is accepted as
compile-time cost** (user priority 2026-09-07: runtime over compile
time). The mechanism is known -- ~374 newly encoded compiler blocks run
as engine programs, interpreted until the JIT takes them -- and it is
plan item 4 (tier policy for run-once compiler code), not a coverage
bug. Warm t/01-sanity sweeps show per-chunk parity, so nothing at runtime
got slower.

## The exact next step

1. **Rakudo `make` on the custom_args nqp** (strict nqp build was green
   before the custom_args commit; rerun it after), then `t/01-sanity`.
   Expect the first failures in routines with full-binder signatures:
   coercive params (`Int() $x`), sub-signatures, `|c` captures. A bind
   failure that used to resume through the bytecode prologue now goes
   through the engine's assertparamcheck.
2. **Rerun the census** (`$CLAUDE_JOB_DIR/tmp/census/census.sh` of the
   2026-09-09 job, or rebuild it from `make -n -B j-all`): the custom_args
   verdict line makes the CORE.c count exact; the 14 exit-handler
   routines (LEAVE-phaser bodies: protect, spurt, slurp-rest, unlock,
   compile-rakuast-comp-unit, run-with-updated-recursion-list) are the
   last real coverage item on the Raku side.
3. Then the bytecode FALLBACK (compile_all_the_stmts for a refused block)
   is deletable; the wrapper shells wait for plan items 5-6.
4. Open task: name anonymous blocks in backtraces (`<anon>` → at least
   `anon_N`, via RakuAST/QAST block naming).

## Recipes (the tmp/ artifacts of the previous session are gone)

- Strict loop (drop the `NQP_CODE_RUN`/`NQP_CODE_PRECOMP` this recipe
  carried in 2026-09-08; they must not be set):
  `NQP_CODE_STRICT=1 RAKUDO_RAKUAST=1
  raku tools/build/watched-run.raku --log=strict.log
  --show='> Task :stage' --show='code-bail' --show='BUILD' --show='rror'
  -- ./nqp/gradlew -p nqp clean buildJvm` (≈5 min to the first stage2
  error, ≈10 min green).
- Stage1 runner (old-encoder compiler, NEW encoder for what it compiles):
  copy `nqp/nqp-j-gradle`, point its lib dir at `nqp/build/jvm/stage1`, add
  `--module-path=<stage1> --setting-path=<stage1>`. Tests a new encoder
  op in seconds without a stage2 build.
- Isolating a stage2 runtime failure: compile `nqp/build/jvm/stage2/nqpmo.nqp`
  and `.../NQPCORE.setting` (the gen-cat'd sources) with the stage1 runner
  (`--bootstrap --no-regex-lib --target=jar --setting=NULL`) into one dir,
  point `--module-path`/`--setting-path` at it, and run probes; that pairs
  new-encoder setting/HOW code with the old compiler.
- Runtime-only rebuild: `./nqp/gradlew -p nqp :nqp-truffle:jar syncRuntimeJars`
  (~10s), then rerun `nqp/nqp-j-gradle` — no stage recompile needed.
- Tracing knobs: `NQP_CODE_TRACE=1` (block entries), `NQP_UNWIND_TRACE=1`
  (loop unwind arms), `NQP_ATTR_TRACE=1` (slow-road @/% attribute reads).

## Honest census (was)

`~374` actual refusals ranked stringify 116, preinc 95, falsey 61, postinc
28, for 24, intify 22, predec 10, tail ~18, regex 6. All of the op cluster
is now covered; the strict build proves the nqp bootstrap has none left.
Deeper background: `docs/jvm-jesp.md`, `docs/jvm-truffle-only-plan.md`,
`docs/jvm-truffle-migration.md`.

## Closed (2026-09-10)

Unit-artifact milestone 4 deleted the runtime class road and JAST;
nothing here is left to hand off. This file is history from this line up.
