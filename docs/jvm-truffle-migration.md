# Migrating general code from JVM bytecode to Truffle

Status: DRAFT, execution begun 2026-09-01 (Phase 0 baselines recorded,
Phase 1 op census below). The grammar engine already made this journey
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

**Phase 1 — Encoder + interpreter skeleton.** Bytecode-DSL root node
with the op set from the census below (~40 ops covers typical user
code); encoder with bail-reasons; coverage REPORTING before coverage
(a probe that says what % of each compile would encode, and the top
bail reasons). Gate: coverage numbers over roast + CORE, no behavior
change (nothing runs on Truffle yet).
  - NOTE (scheduling): touching `src/vm/jvm/QAST/*.nqp` rebuilds
    stage2, which invalidates every rakudo jar ("Missing or wrong
    version of dependency"); each iteration costs
    `gradlew buildJvm` + `make j-clean && make` (~12 min). Batch the
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
