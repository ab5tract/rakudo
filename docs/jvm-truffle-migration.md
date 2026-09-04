# Migrating general code from JVM bytecode to Truffle

Status: Phase 2 landed 2026-09-01 -- runtime-compiled blocks run on the
engine behind NQP_CODE_RUN=1; gates and the two documented exclusions
below. The grammar engine already made this journey for regexes; this
plan generalizes that playbook to all code.

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
  the same bisection knobs (`NQP_CODE_SKIP`, `NQP_CODE_SKIP_ANON`,
  `NQP_CODE_ONLY`, `NQP_CODE_ENCODED`) — those knobs found real engine
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
  - Delivered as: `NqpLanguage`/`NqpRootNode`/`NqpCheck` in nqp-truffle
    (nqp d316956ff -- `gradlew nqpcheck` proves both tiers and a
    serialize/deserialize round trip on the Oracle GraalVM runtime),
    and `QAST::TruffleEncoder` at the CompUnit decision point (nqp
    76b87c2d2 -- `NQP_CODE_REPORT`/`NQP_CODE_SURVEY` report,
    `NQP_CODE_ALSO`/`NQP_CODE_NO` re-measure per run). Results in the
    "Phase 1 results" section below.
  - NOTE (scheduling): touching `src/vm/jvm/QAST/*.nqp` rebuilds
    stage2, which invalidates every rakudo jar ("Missing or wrong
    version of dependency"); each iteration costs
    `gradlew clean buildJvm` + `make j-clean && make` (~12 min; the
    `clean` is not optional -- NQPP5QRegex only rebuilds via its own
    task and goes stale against a fresh NQPHLL without it). Batch the
    encoder work accordingly.

**Phase 2 — Runtime-compiled code first. LANDED 2026-09-01.** EVAL,
`-e`, REPL blocks run on Truffle when fully encodable; everything else
stays bytecode. No serialization needed, trivial A/B (`NQP_CODE_ONLY`).
Gate: t/01-sanity + t/02-rakudo green both ways; warm micro-suite ≥
bytecode; cold `-e` regression bounded (<2x).
  - Delivered: `QAST::TruffleEncoder.encode_block` at the block decision
    point (runtime units only), emitting the nqpp wire form NqpWire.java
    mirrors; the emitted method body is one `CodeEngines.codeRun` call
    (the GrammarEngine classloader bridge, reused); NqpProgramBuilder
    drives the Bytecode DSL builder; params (arity, optionals, slurpies,
    named rejection, param tasks) bind in-program; calls take
    lang-call/lang-meth-call through `Dispatch.dispatchUncached` with
    naturally-typed, positionals-first captures; results return typed.
    Knobs: NQP_CODE_RUN (master), ENCODED/BAIL, SKIP/SKIP_ANON/ONLY,
    LEAF, NQP_CODE_TRACE at run time.
  - Gate results: t/01-sanity 303/303 both ways. t/02-rakudo: engine-on
    matches the engine-off baseline except two documented classes:
    (1) files whose closures are captured in continuations
    (gather/take, lazy sequences) die to the engine's LOUD refusal --
    an engine frame has no resume machinery, and a silent replay would
    drop the block's work; Phase 3's materialized-frame/enableYield work
    owns this, and the refusal names the block so NQP_CODE_SKIP can
    bisect. (2) backtrace line numbers inside an engine-run block
    report the block, not the statement (no per-node source sections
    yet) -- try-statement-backtrace-frame.t asserts exact lines.
    Cold `-e`: 4206ms engine vs 4244ms bytecode -- no regression at
    all, gate bound was 2x. Warm 3M-iteration int-loop micro: 26ms
    engine vs 28ms bytecode -- the engine BEATS the bytecode path once
    Want selection picks the native variants; every gate holds. (The
    first measurement was 69ms: the typed-want fix that repaired enum
    composition also unboxed the loop.)
  - Semantics mirrored the hard way (each was a wrong answer first):
    resultchild on Stmt/Stmts (topicalization restores $_ after the
    real result); void-context variable reads compile to NOTHING
    (an emitted read clones a contvar early and severs lazyviv
    first-toucher sharing); param declarations carry emit_param_tasks
    children; loops without :nohandler stay on bytecode (an engine
    frame registers no unwind handlers, and a callee's `last` would
    silently target an outer loop).

**Phase 3 — Control flow + resume.** Unwind/labels/handlers as
`ControlFlowException`s; continuations/`resume` on materialized
frames. Gate: S17/S04 roast sections green on Truffle.

**Status: COMPLETE 2026-09-01** (nqp 026ecccb5, 9946a5fce, 4359fc76a).
All three pillars landed the same day:

- *Loops + control* (026ecccb5): while/until with last/next/redo
  handlers and the `control` op run on-engine, riding the bytecode
  world's own rows/curHandler/UnwindException machinery through the
  DSL's TryCatch (NqpUnwind carries the host unwind past the dispatch
  loop's host-exception rethrow; REDO is a flag-driven inner loop).
- *handle/handlepayload* (9946a5fce): try/CATCH/CONTROL and the RETURN
  road encode; the encoder synthesizes the bytecode path's dispatcher
  closure verbatim and mirrors its region nesting, host-error
  conversion (NqpHostError → dieInternal), exitAfterUnwind included.
  The deep fix underneath: engine lexical ops anchor at the program's
  own CallFrame, never tc.curFrame — the postlude-dieInternal wart
  leaves tc.curFrame stale in ways bytecode never observes.
- *Continuations* (4359fc76a): the LOUD refusal became participation.
  Every dispatch and table-op site yields a suspend token on
  SaveStackException (enableYield); codeRun turns the yield into a
  ResumeStatus.Frame; the resume handle follows the bytecode saver
  contract (deeper frames first, typed result off the return registers,
  exceptions injected through the yield so handler regions see them at
  the suspension point).

Gate results: the FULL nqp suite green on-engine (12,069 tests,
t/nqp/112-continuations.t included). t/01+t/02 match the bytecode
baseline except one documented backtrace-line assertion
(try-statement-backtrace-frame.t — per-node source sections are future
work). S04+S17 roast (the 170 curated spectest files): 137 files /
2,854 tests run on-engine with the only failing file
(S04-phasers/enter-leave, test 35) failing identically engine-off —
parity, not regression. Warm 3M int-loop: engine ~1ms once PE folds the
loop vs bytecode's steady ~12ms; cold -e at parity.

Design (2026-09-01, after surveying both worlds — note the rx engine
turned out to carry NO ControlFlowException precedent; its backtracking
is explicit data (choice-point stacks), and the plan's earlier claim was
design intent, not code):

- *Handlers/unwind (part A).* Reuse the bytecode world's machinery
  wholesale rather than inventing an engine-private protocol: an engine
  block's `handle`/`handlepayload` registers the same
  `[id, outer, category, kind(, lexidx)]` rows in
  `StaticCodeInfo.handlers` (the engine's `CallFrame` is fully live as
  frame arg `ARG_CF`, so `ExceptionHandling.handlerDynamic`'s walk works
  unmodified), delimits regions by setting `cf.curHandler` from new
  engine ops, and catches `UnwindException` with the Bytecode DSL's
  `beginTryCatch`, checking `unwindTarget == cf` and honoring
  `exitAfterUnwind` exactly as `Compiler.nqp`'s emitted catch does.
  A callee's `last` then finds the engine frame's NEXT/REDO/LAST rows
  through the same dynamic walk, and the UnwindException propagates
  through the dispatch's Java frames into the engine's TryCatch. Loops
  with handlers stop bailing at that point.
- *Continuations (part B).* `enableYield = true` on the DSL spec. Every
  dispatch site becomes a suspension point: `DispatchOp` catches
  `SaveStackException` and returns a suspend token; the program yields
  the token; `codeRun`'s wrapper sees the `ContinuationResult`, does
  `sse.pushFrame(resume-handle, [continuation, cf, callsite-type], cf)`
  and rethrows — the engine frame now participates in the standard
  `ResumeStatus` chain. On resume, the handle re-enters: run
  `resumeNextSave()` (deeper frames first, per the bytecode saver
  contract; a re-suspension there pushes our frame again), read the
  callee's result off the `CallFrame` return register by the site's
  static type, and `continuation.resume(result)` — the yield expression
  evaluates to the dispatch result and the program continues. The LOUD
  refusal in `NqpCodeEngine.run` is then replaced by this participation.
  `continuationreset/control/invoke` themselves stay bytecode-side
  (blocks containing them keep bailing); what must participate is the
  frame *between* reset and control, which is exactly the gather-body
  mainline shape that refuses today.

**Phase 4 — Precompiled modules, then the setting.** Serialize
programs into jars beside (then instead of) bytecode; the setting
last, leaf modules first. Gate at each step: full spectest on one warm
server, wall time and the leak signature (2 live GlobalContexts after
GC — the eval-server discipline applies to every Truffle cache: no
static may hold run-owned objects, thrice-learned).

**Status: landed 2026-09-02** (nqp 7364c91e1, 32e29b60a, 3accf527f).
The serialization story turned out to be the rx descriptor's, almost
verbatim — the audit found the wire format already stable across a jar
round trip (WVals as (SC handle, index) resolved through Ops.wval at
run time; nested blocks as qbids against the frame's own CompilationUnit;
static lexical values riding %*BLOCK_LEX_VALUES identically either way) —
so the phase was one gate plus what turning it loose exposed:

- *The gate* (7364c91e1): with `NQP_CODE_PRECOMP=1` at compile time
  (NQP_CODE_RUN=1 still the master; default builds unchanged),
  comp-mode units take the same codeRun road as runtime units, and the
  jar runs its encoded blocks with no knob set at run time. The build
  applies the knobs selectively: the ten compiler modules
  (SysConfig/ModuleLoader/Ops/Metamodel/World/Pod/Compiler/Optimizer,
  Raku Grammar/Actions), the three BOOTSTRAP jars, the three settings.
- *Thread access* (7364c91e1): the first threaded test over
  engine-carrying precompiled modules found that neither Truffle
  language overrode isThreadAccessAllowed — programs compile lazily on
  whichever thread first runs a block, routinely a worker thread once
  modules are precompiled. Both languages allow shared access now (no
  mutable context state; matcher call targets were always shared).
- *Typed value slots* (32e29b60a): the first engine-carrying BOOTSTRAP
  broke a three-line shape the whole nqp suite never exercises — a
  block mixing `return` with a native-int fall-through result. The
  handle/handlepayload encodings demanded T_OBJ through encode_node,
  which never coerces; StoreRet then cast the raw long. encode_child
  boxes on the way in — and fixing that exposed encode_child's own
  latent bug: its coercion splice moved recorded nested-block qbid
  slots without shifting them (patch_params always shifted for its
  splice; now both do).
- *The sidecar* (3accf527f): CORE.c with the knobs on overflowed the
  classfile constant pool — 71,010 entries against 65,535 — the wall
  the HTML-entity table had already mapped. Engine programs of a
  jar-bound unit now travel as one `<class>.codeprograms.lz4` sidecar
  beside `.serialized.lz4` (joined length-prefixed, lengths in Java
  chars, which nqp::chars agrees with on this backend); emitted bodies
  push an index and call CodeEngines.codeRunIdx, which reads the table
  lazily off the CompilationUnit — strings only, nothing run-owned to
  pin. Runtime-compiled units keep the string road.

Operational lesson re-paid during the climb: after stage/BOOTSTRAP
rebuilds, stale `lib/.precomp` entries deserialize into NPEs and
what look like brand-new engine bugs (two t/02 files "regressed" that
way); rm -rf the .precomp dirs before believing a failure.

**What the first race/hyper workload over an engine-carrying setting
found (2026-09-02, nqp f7ba5ab73, 9467d57b3):** four distinct defects,
peeled in order of visibility, each masked by the one above it:

1. *Descriptor skew.* `Dispatch.descriptorFor` trusted tc.curFrame to
   name the unit whose callsite table csIdx indexes; the frame register
   is stale after the dieInternal-in-the-catch-arm wart and around
   continuation traffic. Descriptor tables now resolve from the
   emitting class (indy bootstrap curries its lookup class; dispatchWide
   grew a trailing-Class overload; a ClassValue caches the per-class
   table -- CallSiteDescriptor is pure shape, nothing run-owned).
2. *Frames left in continuations.* resumeEngine dropped tc.curFrame on
   both re-suspension paths where a bytecode frame leaves through its
   postlude; it leaves now.
3. *Recording on every engine dispatch.* Engine DISPATCH instructions
   were dispatchUncached -- a recording per call, where bytecode replays
   settled per-instruction programs. The per-instruction constant now
   carries a DispatchCallSite beside the descriptor (NqpOps.EngineSite),
   registered for the per-run reset; a capture that crosses a live
   recording is refused loudly instead of corrupting dispatcher
   syscalls far away.
4. *The root cause: resumed frames kept the suspending thread's tc.*
   The DSL's continueWith re-enters the program with its original frame
   arguments, so a continuation resumed on another thread ran every op
   against the first thread's ThreadContext -- dispatch records pushed
   onto the wrong thread's list, curFrame written across threads, and
   capture/tracked validation dying in dispatcher syscalls. The
   bytecode resume road has reloaded tc from the resume status since
   forever ("restored separately since we can change threads");
   resumeEngine now writes the resuming tc into the materialized
   frame's ARG_TC before re-entering. With this, the race repro and
   t/02's hyper files behave identically to the all-bytecode baseline.

Also landed alongside (9d940560d): nqp threads are virtual by default
(daemon/app-lifetime ones; non-daemon threads must hold the JVM open
and stay platform; NQP_JVM_PLATFORM_THREADS=1 is the kill switch).
Truffle 25 runs guest code on virtual threads, with an experimental
warning and carrier pinning during execution.

**Gate policy from here on (user decision, 2026-09-02): the engine
build is the only build.** Spectest results are recorded against the
previous engine run, not re-measured against a knobs-off bytecode
rebuild — there is no going back to a non-Truffle configuration, so
bytecode A/B comparisons are reserved for debugging individual
divergences, not for gates. For the record, the post-rebase tree
carries ~45 spectest files failing for reasons independent of the
engine (verified on an all-bytecode build and against the moar
worktree; goal-spectest5.log is the last such measurement), plus
S32-io/out-buffering.t which hangs any single-server sweep, and a
tail of unimplemented-on-JVM feature gaps (Blob.read-int16 and kin)
in sections no recent run had reached.

**Phase 4 final gates (2026-09-02, engine build: ten compiler modules
+ BOOTSTRAP v6c/d/e + CORE.c/d/e all carrying engine programs; nqp
threads virtual):**

- *Spectest*: 1430 files / ~104k tests over three passes on warm 8g
  servers; **123 files failing**, recorded per-file in
  `docs/jvm-spectest-known-failing.txt` — the reference every later
  engine run diffs against. Of these, ~45 are the pre-rebase-verified
  baseline failures, the bulk of the rest are unimplemented-JVM
  feature gaps and uninstalled-tree spawn artifacts in sections no
  recent run had reached, and the engine-attributable divergences
  are small and named: S32-exceptions/misc2 (2/266),
  S32-temporal/DateTime (6/86), S32-io/io-path (dies at 36/43), the
  documented backtrace-line class, and the S17-procasync +
  out-buffering hang family (hangs identically on platform threads).
  Eleven files that failed at baseline PASS on the engine build.
- *Leak signature*: exactly 2 live GlobalContexts after every round,
  live heap flat (305.8 → 309.0 MB across three added rounds) — no
  engine cache pins anything run-owned.
- *Sanity*: t/01 303/303; t/02 matches its baseline except the three
  pre-existing files; the full nqp suite on-engine 9187/9187.

**Phase 5 — Deletion. IN PROGRESS (2026-09-02).** At 100% coverage per
tier, delete jast2bc, AutosplitMethodWriter, the indy budget, and the
JAST layer for that tier. This is the payoff beyond speed: three of the
five bugs fixed in the 2026-08-31..09-01 session lived in code this
phase retires.

*What this phase found first: the coverage number was wrong.* The
survey's covered-tag set was a hand-written op list, and it had drifted
from the encoder in both directions -- still claiming
`for`/`repeat_while`/`repeat_until`, which the encoder has never
encoded, while missing every op added since Phase 1. It reported 34.0%
of blocks where the encoder was in fact covering 89%. A deletion gate
cannot run on a number like that, so `%covered` is now derived from the
encoder's own `%emit_ops` table plus the names `encode_op`
special-cases (nqp eca47a5d4). Being in the table means an op has an
encoding, not that every use of it encodes -- arity and shape still
bail -- so the survey remains an upper bound and the honest yield of a
tag group still wants an `NQP_CODE_ALSO` run.

*Coverage, measured on the whole CORE.c mainline (19141 blocks) with
`NQP_CODE_REPORT=1`.* This is the number the deletion gate waits on, so
it gets measured after every batch, never estimated:

| after                          | blocks         | nodes in encodable blocks |
|--------------------------------|----------------|---------------------------|
| Phase 1 baseline (2026-09-01)  | 6512  (34.0%)  | 126120  (12.8%)           |
| survey fix + calling convention| 13534 (70.7%)  | 516299  (52.3%)           |
| first sole-blocker batch       | 14054 (73.4%)  | 556526  (56.4%)           |
| second sole-blocker batch      | 14221 (74.2%)  | 568197  (57.6%)           |
| via 2 registered desugars      | 14811 (77.3%)  | 621174  (63.0%)           |
| via all 19 registered desugars | 14893 (77.8%)  | 627256  (63.6%)           |
| + the list constructors        | 15441 (80.6%)  | 670378  (68.0%)           |
| + native attribute references  | 15658 (81.7%)  | 683485  (69.3%)           |
| + the typed assigns            | 15892 (83.0%)  | 700842  (71.1%)           |

(The last row was measured after the 2026-09-04 rebase onto upstream,
where the mainline is 19146 blocks; the earlier rows are over 19141.)

Batches are chosen by **sole-blocker count** -- how many blocks a tag
blocks *alone* -- which the report prints for free. What is left after the
typed-assign batch, in that order: `var:lexicalref` (976 sole, 1470
blocks -- the object-wanted reference form, `getlexref_*`; the typed
assigns used to co-block most of these, which is why its sole count
jumped from 172); `regex` (171), the rx engine's by design;
`op:curlexpad` (150); `op:exception` (115); `op:const` (35);
`op:isfalse` (28); `op:atposref_i`/`_u` (24/20); `op:p6argvmarray` (13);
`op:isbig_I` (13). `hash` stays out until the binder interaction below is
understood.

*The typed assigns (2026-09-04).* `assign_i`/`assign_u`/`assign_n`/
`assign_s` were excluded because nqp's own desugar rewrites the node it is
handed (`op('bind')`, `scope(...)`); the encoder now performs that rewrite
on a shallow copy of the target, with `native_assign_bind_scope` mirrored
over its own view of the block chain, and the container road is four
engine ops (`Ops.assign_*`). `my int $i; $i++` -- every benchmark loop --
encodes with this.

*Native attribute references (2026-09-04).* `var:attributeref` was 197
sole-blocked blocks and is gone from the top twenty. Two pieces, both
mirroring Compiler.nqp: a reference wanted as an OBJECT encodes as
`getattrref_<t>(object, class-handle, name)` (engine ops 159-161, native
types only -- an object attribute has no reference form, and binding
through a reference is not a thing the bytecode path allows either); and a
`lexicalref`/`attributeref` read wanted as a NATIVE devolves to the plain
`lexical`/`attribute` read, because the caller would only dereference it
immediately ("we'd only de-ref right away anyway"). The second piece is
what makes the common `my int $i; $i = ...` shapes encodable, and it is
why `var:lexicalref`'s remaining blocks are the object-wanted ones.

*Coverage landed this round.* The routine calling-convention family
(ops 112-115: assertparamcheck, bindcomplete, p6typecheckrv,
p6decontrv_rt, plus QAST::ParamTypeCheck as a param task) -- the family
Phase 1's census named as the biggest single lever, measured then at
34.0% -> 67.8% of CORE.c blocks. Plus the 23 ops the old list falsely
claimed: getattr/bindattr in all four types, the typed
atpos/bindpos/atkey/bindkey accessors, and iscont_i/_n/_s.

*The `hash`/`list` constructors and the binder bug (bisected 2026-09-03).*
These are the largest remaining win (`op:list_s` alone is 423 sole-blocked
blocks) and they are blocked on a bug that is now localised, not mysterious:

  - `hash` ALONE reproduces it; the list family is not implicated -- and
    that is now load-bearing, not a footnote: list/list_i/list_n/list_s
    are IN (nqp, 80.6%), hash stays out, and the reproducer is clean.
  - The locus is **BOOTSTRAP v6c**: rebuilding just that jar engine-free
    makes the failure vanish while everything else stays engine-built.
  - Within v6c, `NQP_CODE_SKIP` bisection over the 856 encoded block names
    lands on exactly one: **`new`**. `NQP_CODE_SKIP=new` alone is enough to
    make the failure disappear with the desugar fully active.
  - It needs the real Raku signature binder: an nqp-level equivalent (a
    class whose `new` takes named parameters, builds a hash, and is called
    with `|%args`) behaves identically engine-on and engine-off.
  - The type source was NOT the cause. `hlllist`/`hllhash` were reading
    `cu.hllConfig` instead of the running frame's config the way
    `Ops.hlllist`/`Ops.hllhash` do; that is a real discrepancy and is fixed
    in NqpOps.java, but fixing it did not change the symptom.

Bisected the rest of the way (2026-09-03) after teaching `NQP_CODE_SKIP`
to match a **cuid** as well as a name -- 190 blocks in v6c are called
`new`, so a name was not selective enough. The culprit is exactly one
block: **cuid 1262, `OperatorProperties`'s own `new`** (generated
BOOTSTRAP line ~21957, from `src/Raku/ast/operator-properties.rakumod`),
the very method the error names. `NQP_CODE_SKIP=1262` alone fixes it.

**It is an interaction, not one broken thing.** Both of these are needed:

  1. the `hash` constructor encoded (the caller's `PROPERTIES` hash is
     then built by the engine), and
  2. that callee block encoded.

Skipping *either* makes the failure vanish. The callee contains no hash
of its own -- the five hash-emitting `new` blocks (cuids 328, 345, 377,
3447, 4452) were skipped as a set and the failure persisted -- and it is
a twelve-optional-named-parameter routine whose body is `bindattr_s` /
`bindattr_i` / `getattr_*` / `//`, all of which have been encodable and
gated since the 23-op batch. **Committed HEAD is clean: the reproducer
passes there**, so this is not a latent bug in shipped work; it needs the
uncommitted constructor to appear at all.

So the suspicion now falls on the *engine-built hash meeting an
engine-bound named-parameter prologue*: each is fine against a bytecode
counterpart, and only the pair fails. The next probe is the flattening
step (`explodeFlattening` on the caller's callsite) with an engine-built
hash, versus the parameter prologue `patch_params` emits for many
optional nameds.

Reproducer, ~30s once the jars exist: compile a small `.raku` holding a
`my constant` hash-of-hashes inside a method with
`perl rakudo-j-build --setting=NULL.c --target=jar --output=/tmp/x.jar FILE`.
The experiment itself (hash desugar + the cuid-matching skip knob) is in
an nqp `git stash`.

*The op-desugar wall, and a way through it (2026-09-03).* The two biggest
unblocked-looking levers left, `op:p6callmethodhow` (366 sole) and
`op:p6attrinited` (224 sole), are both `register_op_desugar` entries in
`src/Perl6/Actions.nqp` -- the legacy frontend this branch does not read.
That is ~590 sole-blocked blocks walled off by policy, and more behind
them.

They need not stay walled off. `register_op_desugar` itself lives in
`src/vm/jvm/Raku/Ops.nqp`, which is fair game, and it currently buries the
desugar inside the closure it hands to `add_hll_op`:

    sub register_op_desugar($name, $desugar, ...) {
        nqp::getcomp('QAST').operations.add_hll_op($compiler, $name, ...,
            -> $qastcomp, $op { $qastcomp.as_jast($desugar($op)) });
    }

If it also recorded `$desugar` in a table the encoder can consult, then on
meeting an unknown op the encoder could apply the registered desugar and
encode the RESULT -- reproducing no logic and reading no forbidden file,
since the desugar is applied blindly as a value. Anything it produces that
is still unencodable bails as usual.

**Built and gated (nqp cba978931, rakudo 38aefcc46).** The encoder now
applies published desugars, opt-in per op via `NQP_CODE_DESUGAR=a,b` and
inert without it. Enabling the two that matter took CORE.c from 74.2% to
77.3% of blocks; enabling all 19 adds only 0.5 more, because the other 17
sit inside blocks that something else already blocks -- their sole counts
were near zero, and the sole-blocker ranking predicted exactly that. Gate
with all 19 on: t/01-sanity + 70 of t/02-rakudo, 95/95, on a build whose
BOOTSTRAP and settings were compiled that way.

**The hazard designed around:** a desugar may MUTATE the node it is
given rather than return a fresh tree -- nqp's own `assign_i` desugar does
exactly that (`$op.op('bind'); $target.scope(...)`), which is why the typed
assigns are excluded from the encoder. An encoder that ran a mutating
desugar and then bailed would hand the bytecode path a rewritten tree. So
this wants either a clone before applying, or a registry that marks which
desugars are pure.

*Still not encodable, the next batch:* `list`/`list_i`/`list_n`/
`list_s`/`list_b` and `hash` (variadic, so they need shape handling
rather than a table row), and the `for`/`repeat_while`/`repeat_until`
loop forms.

*Gate for this phase (user decision, 2026-09-02/03): no full spectest
runs; **`t/` is the gate**.*

    raku tools/build/watched-run.raku -t=t/01-sanity -t=t/02-rakudo \
        --jobs=4 --log-dir=sweep-logs --max=900 -- ./rakudo-j -Ilib

309 files, cold runner per file, ~42 min. `--max` must stay above 600:
t/02-rakudo/15-gh_1202.t spawns 50 JVMs under its own 600s budget and a
tighter ceiling kills it. **Standing result: 307/309.** The two failures
are pre-existing and NOT engine-related -- both reproduce identically on
a fully engine-free build, and both fail at compile time:

  - `constant-anon-var-value.t` -- "Cannot call method 'is_composed' on a
    null object"; minimally `sub f($x = (my uint32 $ = 9)) { $x }`.
  - `parse-target-match-tree.t` -- "This type does not support positional
    operations".

Note that `t/` normally runs through the eval server
(`t/harness5 --jvm --evalserver`, what the Makefile's HARNESS5 uses); the
cold-runner form above is deliberate for now, because **the eval server
dies after ~43 files** and every run past that returns instantly with no
TAP, which a harness scores as failure. That regression is unexplained
and is the reason the earlier dice-roll gate reported 40 bogus new
failures. Fix it before trusting any warm-server sweep again.

`tools/build/dice-spectest.raku` remains for spectest spot checks: steady
set plus a random roll through one warm server, aborting loudly on a slow
or hung file. It inherits the server-death problem above.

## Dispatch on Truffle (started 2026-09-04)

The architecture target above says dispatch programs become guard nodes
and assumptions. The first two steps landed in nqp (commit "Code engine:
dispatch programs replay as PE-visible code, and enter engine callees
directly"):

- *Folded replay.* Each engine dispatch instruction keeps the replayable
  prefix of its site's recorded programs as a compilation-final array
  (`NqpDispatch`), and the guards and outcomes are evaluated by plain Java
  that partial evaluation folds. Value sources fold too: an attribute read
  is only recorded behind a type guard on the object it reads (the
  tracked-attribute contract), so its storage class and slot hint resolve
  once and the read is an exact-class speculation plus a switch on a
  constant. Recording is untouched; a miss is `Dispatch.fallback` and a
  refold; refolds and the per-run reset swap the array under a fresh
  Assumption.
- *Direct engine entry.* `codeRun` notes the compiled program on the
  block's StaticCodeInfo; an invoke outcome that resolves to such a code
  ref builds the frame and runs the program as the stub would, skipping
  the MethodHandle, the stub, and `codeRun`.
- *What measuring it found first (rakudo, RakOps.p6typecheckrv):* every
  return of a routine with a declared return type looked up and invoked
  `archetypes` and `generic` through the metamodel -- two `find_method`
  walks per return in the steady state. MoarVM's raku-rv-typecheck
  dispatcher records that once; the JVM op now caches it per signature
  (`rvChecks`, reset with the dispatch caches). On the 30k-iteration
  probe this removed ~61k engine block entries (`archetype`) per run.

Measured on a 300k method-call loop: guard-side boundary crossings went
from three per dispatch to zero; wall time sits at parity with the old
road (`NQP_CODE_DISPATCH_OLD=1` is the A/B), because that benchmark's hot
callee `infix:<+>` has no engine body and its caller is the bailing
mainline block -- neither end reaches the direct road. The
engine-to-engine measurement and the t/ gate wait on the rebuild that
also carries the typed-assign encoding (the `op:assign_i` sole-blocker).

*What the CORE.c compile then taught (2026-09-04, afternoon).* The
compile's parse stage had gone from 164s (the post-rebase build) to
289-323s, and the four-way A/B cleared the dispatch road of all but ~15s
of it. Truffle's compilation trace found the real cost: 114 of 1650
compilations failed with "code installation failed: code is too large"
after a mean 6.4s each -- 733s of the 1880s the run compiled at all --
and such a root runs interpreted afterwards. Program size was not the
reason (the failing roots were 94-836 wire words); partial evaluation
inflated every root to ~1.5KB of machine code per wire word.
`compiler.TraceMethodExpansion` with `engine.NodeSourcePositions` on a
48-word accessor that compiled to 44KB named the mass: 70% of its IR
under one lexical read, in Kotlin's `lateinit` and `!!` checks, whose
failure paths (stack-trace sanitizing and StackTraceElement formatting)
PE inlines in full, ~330 IR nodes per check; `Ops.createNull` alone was
~700 nodes per `nqp::null()`. The dispatch fold added its own: the direct
engine entry inlined per folded program, ~3000 nodes per site, for a call
that ends in an indirect `CallTarget.call` PE cannot see through.

The fixes (nqp "keep Kotlin's null and lateinit checks out of compiled
code"): hot paths read the frame's fields from Java (lexical get/bind,
typed result read and return store, the null constant as a compilation
constant); nqp-runtime compiles with the Java-interop null assertions
off; the fold's invoke road is a boundary, only its guard tests stay in
compiled code. Roots are named `<block>[<wire words>]` in traces, and
`NQP_CODE_MAX_COMPILE` guards against the next such wall. Result: the
identity method 103KB -> 8KB, `IMPL-OPTIMIZE` 252KB -> 58KB, mean root
36KB -> 11KB, size failures 114 -> 0, total JIT time 1880s -> 224s, the
method-call loop 30% faster, and **CORE.c's parse stage 145s** -- below
the pre-migration 164s for the first time.

Two other per-call costs found on the way and fixed: `CallFrame`
construction searched the whole dynamic caller chain for a live outer on
every invocation of a code ref with no outer (~1.1M searches per module
compile, zero successes; now gated on a live-invocation count, since
taking the prior invocation outright as MoarVM does breaks static code
refs invoked inside a recursive outer), and `p6typecheckrv` re-derived a
return type's genericness through the metamodel on every return (cached
per signature in rakudo's RakOps), with the `Int:D` parameter check
lowered to base type plus concreteness so the type-check cache answers it.

Rule written into the code: nothing Kotlin on a PE-visible path unless it
is a plain field access, and every new fast path gets checked with the
expansion trace.

*The deopt cycle (same afternoon).* Thirteen roots, the parse driver
`PERFORM-PARSE` among them, were abandoned by Graal with "deopt taken too
many times"; with cycle detection off they recompiled a hundred times
each. `engine.TraceTransferToInterpreter` put the transfers at the
generated interpreter's `resolveThrowable`: the Bytecode DSL treats any
non-Truffle exception as an internal error and invalidates the compiled
root BEFORE the language's `interceptInternalException` gets to wrap it,
and this runtime uses host exceptions as ordinary control flow (an
`UnwindException` for every return, next, last and handled die). Every
operation now converts at its boundary (`NqpOps.carry`) into the same
carriers the interception produced; bailouts 13 -> 0, deopts 549 -> 385,
parse time unchanged -- those roots were not the remaining bottleneck.
Rule: never let a host exception reach the DSL loop.

The fold's per-install republish (~290 invalidations against 38 on the
old road) now refolds lazily -- immediately the first time, then only
after sixteen misses since the last fold -- for 219 invalidations and a
144.6s parse. The `DirectCallNode` step landed last (nqp "engine callees inline across
a dispatch through adopted call nodes"): a folded program with a literal
engine-bodied callee calls it through a call node adopted under the
dispatch instruction's node, so the inliner sees it -- 1.408s -> 1.229s
on the engine-to-engine loop, neutral on the compile, where only 37
callees inlined: most of what the compiler calls is still bytecode-bodied
or has not run before its caller compiles. Still open: the remaining 38
invalidations the old road also has, and more of the compiler on-engine.

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
lives in `QAST::TruffleEncoder`), measured with `NQP_CODE_REPORT=1`:

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
family buys the block. Measured directly (`NQP_CODE_ALSO` with the family
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

Found by the first post-rebase build (2026-09-01): upstream's RakuAST
growth pushed gen/jvm/ast.nqp's single whole-tree BEGIN block to a
~500k-instruction mainline, and compiling it OOM'd a 14GB heap —
AutosplitMethodWriter keeps a Frame (a String[] of nlocal+stack slots)
per instruction, and ASM's COMPUTE_FRAMES adds its own per-label
tables; the heap dump showed ~513k autosplit Frames, 1.76M asm Edges,
1M Labels. Fixed in tools/build/raku-ast-compiler.nqp: one BEGIN block
per 16 packages (identical semantics — BEGIN blocks run in parse
order, the prologue subs are lexical to each block), dropping the
compile to ~1.6GB RSS. One more entry for Phase 5's ledger: the whole
failure class is jast2bc-sized, and Truffle programs are data. (The
sibling lesson — the retry with a 24G heap on the 30G swapless box got
the SESSION shot by the kernel OOM killer — is written into AGENTS.md:
cage heavy builds with systemd-run --scope -p MemoryMax.)

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
