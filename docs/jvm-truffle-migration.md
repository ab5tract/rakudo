# Migrating general code from JVM bytecode to Truffle

Status: Phase 1 DONE 2026-09-01 (skeleton live, survey landed, coverage
measured -- results below). The grammar engine already made this journey
for regexes; this plan generalizes that playbook to all code.

## Why, and why we believe it

The rx engine is the existence proof: `RxVmNode` is a Truffle
interpreter — one plain loop over a `@CompilationFinal` program that
partial evaluation specializes per-pattern — and it replaced the
bytecode matcher outright (the whole-engine toggle is deleted). The
same architecture, applied to QAST at large, buys:

- **Inlining across dispatch.** PE inlines through guard chains that
  the invokedynamic/MethodHandle world cannot see through. Everything
  past the `$INDY_SITE_BUDGET` (48,000) cap runs today's *uncached*
  `Dispatch.dispatchWide` path — a cliff Truffle does not have.
- **The 64K walls disappear.** All three that have bitten this branch:
  the 64KB method limit (AutosplitMethodWriter exists solely for it,
  and its transposed-stack-effect bug hid for years), the silently
  aliasing 65,535-entry resolved-references array (the nondeterministic
  newdisp failure), and the classfile constant pool (the HTML entity
  table overflowed it by 45 entries). Truffle programs are data, not
  classfiles.
- **Simpler control flow.** Unwind/bind-failure/bind-return all become
  `ControlFlowException` (PE-transparent); the handler codegen shapes
  that exposed the autosplit bug are deleted rather than ported.

Honest costs: warmup (PE compilation is expensive — CORE-compile and
cold starts may regress before steady-state wins), per-code-object
memory (the setting is one CU with tens of thousands of routines), and
the engineering of a second serialization story. Every phase gate
below is a measurement for exactly this reason.

## Architecture target

- **Representation: Truffle Bytecode DSL** (`com.oracle.truffle.api.bytecode`,
  present in the shipped truffle-api 25.2.4). A generated interpreter
  from an operation spec: cached/uncached tiers, OSR, and a
  serializable bytecode form — which solves node-memory for the giant
  setting AND gives the precompilation story (the analog of the rx
  descriptor traveling as a string constant in the jar).
- **Encoder where `rx_descriptor` sits**: QAST → Bytecode-DSL program,
  per code object, at the same decision point in
  `src/vm/jvm/QAST/Compiler.nqp`. Coverage is a compile-time decision
  with a loud `bail()` reason, exactly like `QAST::RxDescriptor`, plus
  the same bisection knobs (`NQP_QT_SKIP`, `NQP_QT_SKIP_ANON`,
  `NQP_QT_ONLY`, `NQP_QT_ENCODED`) — those knobs found real engine
  bugs and will again.
- **Frames**: lexicals map to Truffle `FrameDescriptor` slots;
  `CallFrame` stays as a materialized shim for interop (the
  lazyviv/frameops work maps directly onto frame-slot semantics).
- **Dispatch**: the newdisp dispatch programs translate ~1:1 into
  guard nodes + `Assumption`s; `DispatchBootstrap.resetAll()`'s
  per-eval-server-run contract becomes assumption invalidation,
  registered through the same `registerResettable` road every cache
  already uses.
- **Interop**: cross-world calls funnel through `Ops.invokeDirect`
  (every invocation already does — that is what made the junction
  bind-return fix a one-catch-site change). Precedent for
  Truffle-calls-bytecode: `NqpCursor.runCallback`.

## Phases and gates

**Phase 0 — Baselines (DONE, this doc).** See table below. Every
later gate is "beats or holds these".

**Phase 1 — Encoder + interpreter skeleton. DONE 2026-09-01.**
Bytecode-DSL root node with the op set from the census below (~40 ops
covers typical user code); encoder with bail-reasons; coverage
REPORTING before coverage (a probe that says what % of each compile
would encode, and the top bail reasons). Gate: coverage numbers over
roast + CORE, no behavior change (nothing runs on Truffle yet).
  - Delivered as: `QtLanguage`/`QtRootNode`/`QtCheck` in nqp-truffle
    (nqp d316956ff -- `gradlew qtcheck` proves both tiers and a
    serialize/deserialize round trip on the Oracle GraalVM runtime),
    and `QAST::QtEncoder` at the CompUnit decision point (nqp
    76b87c2d2 -- `NQP_QT_REPORT`/`NQP_QT_SURVEY` report,
    `NQP_QT_ALSO`/`NQP_QT_NO` re-measure per run). Results in the
    "Phase 1 results" section below.
  - NOTE (scheduling): touching `src/vm/jvm/QAST/*.nqp` rebuilds
    stage2, which invalidates every rakudo jar ("Missing or wrong
    version of dependency"); each iteration costs
    `gradlew clean buildJvm` + `make j-clean && make` (~12 min; the
    `clean` is not optional -- NQPP5QRegex only rebuilds via its own
    task and goes stale against a fresh NQPHLL without it). Batch the
    encoder work accordingly.

**Phase 2 — Runtime-compiled code first.** EVAL, `-e`, REPL blocks run
on Truffle when fully encodable; everything else stays bytecode. No
serialization needed, trivial A/B (`NQP_QT_ONLY`). Gate: t/01-sanity +
t/02-rakudo green both ways; warm micro-suite ≥ bytecode; cold `-e`
regression bounded (<2x).

**Phase 3 — Control flow + resume.** Unwind/labels/handlers as
`ControlFlowException`s; continuations/`resume` on materialized
frames. Gate: S17/S04 roast sections green on Truffle.

**Phase 4 — Precompiled modules, then the setting.** Serialize
programs into jars beside (then instead of) bytecode; the setting
last, leaf modules first. Gate at each step: full spectest on one warm
server, wall time and the leak signature (2 live GlobalContexts after
GC — the eval-server discipline applies to every Truffle cache: no
static may hold run-owned objects, thrice-learned).

**Phase 5 — Deletion.** At 100% coverage per tier, delete jast2bc,
AutosplitMethodWriter, the indy budget, and the JAST layer for that
tier. This is the payoff beyond speed: three of the five bugs fixed in
the 2026-08-31..09-01 session lived in code this phase retires.

## Phase 0 baselines (2026-09-01, GraalVM 25.2.4, one warm 8g server)

- Full spectest: 1306 files / 73,273 tests / **8449s wall** (pre-fix
  run; the post-fix run v5 was in flight when this was written —
  update from `goal-spectest5.log`).
- CORE.c.setting compile: **~200s**; full `make j-clean && make`:
  **~10 min**; nqp `gradlew buildJvm` (warm caches): **~2 min**.
- Warm per-file cost through the eval server: ~2-6s/file, throughput
  rising ~3→8 files/min as the JIT warms over a run.
- Leak signature: 2 live GlobalContexts after forced GC, flat live
  heap (~340MB) across runs.

## Phase 1 op census (what the encoder must cover first)

Corpus: `--target=qast` over t/spec/S02-types/mixhash.t,
t/spec/S04-statements/for.t, and a mixed-construct `-e`. 65 distinct
ops; the head of the histogram:

    1340 callmethod   960 bind        764 callstatic  614 p6sink
     578 hllize       536 call        355 p6capturelex 347 bindattr
     191 if           175 getlexouter 168 decont       149 p6assign
     103 iscont        93 null         73 getattr       70 until
      70 eqaddr        52 create       48 clone_nd      47 p6bindattrinvres
      47 chainstatic   45 p6store      37 isconcrete    27 istype

Node kinds: Op 7125, Var 4277, WVal 3786, Stmts 1761, SVal 1431,
Want 1225, Stmt 1153, IVal 552, BVal 348, Block 342, Regex 98.
Regenerate: `rakudo-j --target=qast FILE | grep -oE 'QAST::Op\([a-z0-9_]+'
| sort | uniq -c | sort -rn`.

## Phase 1 results (2026-09-01)

Coverage of the committed first-tranche op set (the census heads plus
the structural/primitive/rakudo ops that travel with them; the list
lives in `QAST::QtEncoder`), measured with `NQP_QT_REPORT=1`:

- **CORE.c, whole compile**: 490 CUs, 22,044 blocks, **7,496 (34.0%)
  encodable**; 1,141,862 nodes, 12.8% in encodable blocks. The
  mainline unit alone: 19,343 blocks, 34.1%.
- **Spec-test corpus** (compile of the file's own code): mixhash.t
  24.6% of 150 blocks, for.t 38.8% of 126, split.t 74.8% of 211 and
  52.4% of 82.

Top bail tags over CORE.c (blocks blocked / blocked by this alone):

    10466/632  node:QAST::ParamTypeCheck    3244/1  op:getcodeobj
     8666/63   op:p6decontrv                3239/0  op:curcode
     5394/50   op:bindcomplete              2785/0  op:p6typecheckrv
     1840/190  op:dispatch                  1809/181 var:lexicalref
     1389/0    op:assign_i                   816/17  op:stmts
      770/52   var:attributeref              701/215 op:p6callmethodhow
      681/0    op:handlepayload              680/0   op:lastexpayload

The reading: **the routine calling convention is the whole game.** The
six head tags are one family -- signature binding (ParamTypeCheck,
bindcomplete), return conventions (p6decontrv, p6typecheckrv), and the
prelude (getcodeobj, curcode) -- and their low "sole" counts mean they
cluster in the same blocks: covering any one buys little, covering the
family buys the block. Measured directly (`NQP_QT_ALSO` with the family
plus op:dispatch and op:stmts): coverage goes 34.0% -> **67.8%**
of CORE.c blocks (nodes in encodable blocks 12.8% -> 50.2%). That family is therefore Phase 2's op set, and it is
also the semantically deep end -- binding and return checking sit
exactly where the ControlFlowException design (Phase 3) and the Binder
interop shim meet. The exception family (handle/handlepayload/
lastexpayload/exception, ~700 blocks each) is Phase 3 as planned.
op:time and op:stmts are freebies for the committed list.

The survey's own cost is noise: CORE.c parse 159.8s with the knob on
vs the 161.2s Phase 0 baseline, and the walk only runs when a knob
asks for it.

Found by this phase's first `make j-clean` build (recorded here
because the migration inherits the acceptance test): the rx engine's
LOOP_SPLIT opcode collided with POS_EQ_REG (both 30), breaking every
conjunction and `<?before>` -- invisible until gen/jvm/ast.nqp was
regenerated for the first time since the engine went feature-complete.
Fixed in nqp 9202acdd2 with an init-time opcode-distinctness check;
`.DELETE_ON_ERROR` added to the Makefile so a failed recipe cannot
leave a fresh-looking partial target again.

## Lessons already paid for (write them into the code)

- No `@ExplodeLoop` over a cyclic program — RxVmNode's comment says
  why; keep the plain loop and let `@CompilationFinal` do the work.
- Lazily-materialized state must be flushed before foreign code can
  observe it (the pending-captures/!BACKREF bug generalizes: frame
  slots vs CallFrame shim will have the same shape).
- Backtrack-style state must live where the control stack lives (the
  LOOP_SPLIT stale-mark lesson): registers/locals that guards compare
  against must travel with choice/continuation frames.
- Every cache keyed by or holding run-owned objects registers its
  clear via `DispatchBootstrap.registerResettable`, and the
  leak-check command (`tools/build/evalserver-leak-check.sh`) is the
  acceptance test.
