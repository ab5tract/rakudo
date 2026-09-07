# jesp: mining MoarVM's spesh for the Truffle engine

jesp is the port of MoarVM's specializer (`nqp/MoarVM/src/spesh/`, the C
source is in-tree) to the JVM/Truffle backend. It is not a separate pass:
the engine has no facts pass and no IR of its own to rewrite. Each spesh
optimization is ported as the mechanism that gets Graal to do the same
thing after partial evaluation -- an inline cache on a Truffle operation,
a PE-visible guard, a direct call node -- and each is measured before the
next. The strategy is the user's (2026-09-06): PE-time, lean on Graal, no
encode-time IR inliner.

The gate is `t/01-sanity` (cold runners and the warm eval-server sweep)
plus the `+` microbenchmark below. Everything here is measured on the
engine build; a script mainline must be run with
`RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1`, or it compiles to
bytecode and never touches the engine's replay (dispatch stats show it at
once: 20k folded hits instead of 90M).

## The benchmark and what it says

`$s = $a + $b` in a `while` loop of 40M iterations after 5M of warmup
(`docs/bench/jesp/plusquick.raku`; `nqp::time` around the loop). The
resumption smoke test beside it, `docs/bench/jesp/resume-smoke.raku`,
exercises callsame, nextsame, callwith, wrap, a `where`-clause bind
failure falling through to the next candidate, and the bind-error
message; its output must not change:

| state | ns per `+` | folded hits | boundary invokes |
|---|---|---|---|
| 2026-09-07 morning, engine build | 798 | 90M (2 per op) | 45M |
| diamonds 1 and 2 | 777 | 90M | 8k |
| diamond 3, the type-check family as sited operations | 409 | 90M | 8k |
| diamond 3, plus the native int/num ops | ~300 | 90M | 8k |
| diamond 3, plus raw `lateinit` reads (`NqpRaw`) | 285-290 | 90M | 8k |
| diamond 4, `add_I` as a sited operation (small-int cache off) | 189-191 | 90M | 8k |
| diamond 4 with `JESP_INTCACHE=1` (shared boxed small Ints) | 186-195 | 90M | 8k |
| diamond 5, frame-free callees on, `+` candidate still framed by its implicit magicals | 195-198 | 90M | 8k |
| diamond 5 with bare implicit magicals not forcing a frame: the `+` candidate runs frame-free (quiet machine; 169-215 while other JVMs were exiting) | 142 | 90M | 8k |
| diamond 6, `hllize` as a sited operation, `checkarity`/`flatArgs` off the boundary (quiet machine) | 123-124 | 90M | 8k |
| diamond 7, frame-free across languages for blocks that read no current language: the `raku-assign` handler runs frame-free from Raku (quiet machine) | 83-92 | 90M | 8k |

The cold-runner `t/01-sanity` (4 jobs) went from 167 s to 119 s over the
same steps: the compiler runs on the same engine, so the diamonds speed up
compilation as well as the loop.

JFR of the loop before the change (3320 samples, top of stack):

| frame | share |
|---|---|
| `NqpOps.run0` (the generic `RunOp` boundary switch) | 54% |
| `CallFrame.<init>` + `leave` | 9% |
| `RunOp.doOp` | 6% |
| everything else (add_I 0.8%) | rest |

Two things the profile overturned. The proto and the multi are already one
folded program (raku-call plus raku-multi, guards on the literal callee,
the argument types and concreteness, a decont of one argument, then the
candidate as a literal): there is no proto frame to kill. And the
candidate call was not taking the direct call-node road at all: its
program is the resumable kind, and `Program` only filled `calleeLiteral`
for the mapped kind, so the resumable-literal branch of `realize` was
dead code and every `+` went through the `invoke` boundary, a fresh
`DispatchRecord` and an ArrayList push.

The remaining 777 ns is the candidate body's ops crossing the generic
boundary road one by one: `decont`, `isnull`, `istype`,
`assertparamcheck`, `p6typecheckrv`, `add_I` all run through
`NqpOps.run0`, a `@TruffleBoundary` switch over a boxed `Object[]`. That
is diamond 3.

## The spesh catalog, mapped

What spesh does (file, mechanism) and what the same win is here.

| spesh | ours | status |
|---|---|---|
| `disp.c`: translate a dispatch program's guards into `sp_guard*` ops, its value sources into `sp_p6oget_*`/`unbox`, its outcome into `sp_runbytecode` | `NqpDispatch`: guards fold to `Chk` objects PE explodes; attribute sources read through constant MethodHandle getters; outcome is a register store or a call | done 2026-09-04 |
| `optimize_runbytecode`: a constant callee (or a 99%-stable logged one) selects a candidate and inlines it | the adopted `DirectCallNode` per program with a literal engine callee, so Truffle's inliner sees the call | mapped kind 2026-09-04; **resumable kind 2026-09-07 (diamond 1)** |
| `sp_resumption` + `frame_walker.c`: resume-init values stay live in the frame; a record is built only when a resumption happens | the callee `CallFrame` carries `dispatchProgram`/`dispatchArgs`/`dispatchSite`; `CallFrame.invokingDispatch()` materializes the record on first need; `findResumption` walks frames | **done 2026-09-07 (diamond 2)** |
| `optimize_istype`/`isconcrete`/`isnull`/`decont`/`assertparamcheck`, `sp_fastcreate`: facts from guards fold the op to a constant or a field load | dedicated Truffle operations with a per-instruction STable inline cache, so PE folds the answer under the guard already taken (`NqpTypeOps`) | **done 2026-09-07 (diamond 3)** |
| the interpreter's native `add_i`/`islt_i`/... (no spesh work needed: MoarVM's interpreter already runs them as one instruction) | `IntBinOp`/`IntUnOp`/`NumBinOp`/`NumCmpOp`/`NumNegOp` keyed by op id, the `when` over the constant folds (`NqpNativeOps`); before, they crossed the generic boundary switch with boxed operands | **done 2026-09-07 (diamond 3)** |
| `sp_add_I`/`sub_I`/`mul_I` with the small-int cache | `BigIntArithOp` with a site on the three STables: both `BigInteger` slots read through a constant getter, the arithmetic in a `long` when both fit 63 bits, the result a prototype clone (`NqpTypeOps.bigintArith`); the intcache exists behind `JESP_INTCACHE=1` and measured as worthless (see below) | **done 2026-09-07 (diamond 4)** |
| `args.c`: `sp_getarg_*`, deleted `checkarity`, optionals resolved at spec time | the frame-free prologue (`CheckArity`/`PosParam` cf-free) is the equivalent; full value needs lexicals in Truffle slots | calling-convention project |
| `pea.c`: scalar replacement of `sp_fastcreate` P6opaques and boxes | Graal's escape analysis, once the callee is inlined and the value does not escape into a heap `CallFrame` register | blocked on the frame |
| `optimize_getlexstatic`: a setting lexical to a constant | `WvalGet`/`LexGet` per-instruction caches | done 2026-09-04 |
| `osr.c` | Bytecode DSL OSR | present |
| `deopt.c` | Truffle deoptimization | native |
| `log.c`/`stats.c`: type logging to pick stable specializations | the recorded dispatch programs are the logging; polymorphic sites keep up to 8 folded programs | done |

## Diamond 2 in detail: lazy dispatch records

A resumable dispatch (one whose program set up resumptions or bind
control; every `raku-multi` candidate call is one) used to allocate a
`DispatchRecord` per call, push it on `tc.dispatchRecords`, set
`tc.pendingDispatch` for the callee's frame to claim, and pop it after.
Now:

- The replay roads (`NqpDispatch.enterResumableDirect`,
  `invokeResumableBoundary`, `DispatchCompiler.invokeResumable`) set
  `tc.pendingProgram`, `tc.pendingArgs`, `tc.pendingSite`. Plain field
  stores, PE-visible, no boundary.
- `CallFrame`'s constructor moves them onto the frame. Nothing is
  allocated for the dispatch.
- `CallFrame.invokingProgram()` answers the bind-control questions asked
  in every full-binder prologue (`bindWillResumeOnFailure`, the
  `bind-will-resume-on-failure` syscall, `BindFailure.complete`) from the
  program alone.
- `CallFrame.invokingDispatch()` materializes the record on first need
  (`BindFailure.failed`, a found resumption) and keeps it, so the resume
  states a resumption creates survive for the next one.
- `Dispatch.findResumption` walks frames outward. Arriving at frame F from
  frame C it first visits C's carried dispatch (the innermost dispatch
  made from F), then the listed records with `callerFrame === F`,
  skipping the one identical to the carried record: the recording road
  still lists its records, and a callback frame or the callee frame
  carries the same object.
- A bind failure is owned by the replaying dispatch when the failing
  frame's materialized record names the same argument array and program.
- A frame-free callee (knob-gated, off) has no frame to carry a dispatch;
  the direct road leaves nothing for it, so no nested frame can claim the
  dispatch by mistake. It also cannot bind-fail or resume into its
  dispatch -- see the calling-convention doc's known bug.

## Diamond 3 in detail: the type-check family as sited operations

The choice between a dedicated operation and the generic `RunOp` is made
in `NqpProgramBuilder` when a wire program is loaded (`dedicatedOp`), so
this is a runtime-only change: no wire format, no encoder, no setting
recompile. Each op gets a site object as a constant operand, resolved on
first execution under a deoptimization (the `NqpOps.AttrSite` pattern),
speculating monomorphically on STable identity; a miss re-speculates up to
`MAX_MISSES` times, then the site pins itself to the generic road.

- **decont** (`DecontSite`): a non-container's value is itself; a container
  whose spec says its fetch is a plain attribute read
  (`ContainerSpec.fetchAttribute`, which `RakudoContainerSpec` answers with
  Scalar's `$!value`) reads the slot's field through a constant getter,
  exactly as the dispatch fold's `AttrSrc` does. Proxy and friends answer
  null and stay generic.
- **isnull**: a pointer compare, no site.
- **isconcrete**: the decont fast path plus the type-object test.
- **istype** (`IsTypeSite`): decont sites on both operands, then the pair
  of STables and the answer -- cached only when `STable.TypeCheckCache`
  answered definitively (a hit; or a miss of an authoritative cache with
  a type that needs no `accepts_type`). A metamodel-answered check pins
  generic. Same trust in the type-check cache as spesh's `optimize_istype`.
- **assertparamcheck**: the flag test inline, `BindFailure.failed` behind
  a boundary.
- **p6typecheckrv** (`RvCheckSite`): per routine identity, the accepted
  deconted STable and concreteness, so a settled routine's return check
  is two compares and returns its input. Only when
  `RakOps.p6typecheckrvCacheable` says the return type is non-generic.
- **create** (`CreateSite`): a P6opaque's prototype instance cached, so
  `instClone()` is a call on a constant receiver and the allocation is
  one Graal sees; other REPRs allocate through their constant REPR.
- **native int/num ops** (`NqpNativeOps`): the op id is the operation's
  constant operand and the `when` folds; div/mod stay generic (they need
  the thread context).

Two lessons the method-expansion trace taught, both now rules:

- **The builder stays Java.** It consumes `NqpRootNodeGen.Builder`, which
  the Truffle DSL processor generates during the Java compile; Kotlin
  compiles before that, and the root node's operations call Kotlin, so the
  cycle cannot be split. (The port was made and reverted.)
- **A Kotlin `lateinit` read is not a field read.** `SixModelObject.st` and
  `CodeRef.staticInfo` are `lateinit`; from Kotlin every read carries an
  uninitialized-property check whose failure path PE inlines in full
  (ten copies in the `+` root). `NqpRaw.java` reads those fields raw, and
  every PE-visible Kotlin read of them goes through it: trace size 932 to
  591 lines, zero intrinsic failure paths, ~300 to ~287 ns.

## Diamond 4 in detail: `add_I` as a sited operation

`Ops.add_I` read each operand's bigint through the generated accessor and
a thread-context side channel (`tc.nativeJ`), computed in `BigInteger`,
allocated the result through the REPR and wrote it back through the same
accessor: the last generic-road op left in the `+` loop, 18% of its
samples. `BigIntArithOp` (add, sub, mul; op id as constant operand)
carries a `BigIntSite` that speculates on the three STables (both operands
and the result type) being one P6opaque type whose box target is a
flattened bigint, resolving the storage class, the `BigInteger` slot's
getter and setter as constant MethodHandles (`NqpRaw.getBig`/`setBig`, the
void `invokeExact` kept in Java), and the prototype instance to clone.
The fast path reads both slots, and if both fit in 63 bits does the
arithmetic in a `long` with an explicit overflow test; the result is one
prototype clone plus `BigInteger.valueOf`. Overflow, a large value, a
`P6bigintInstance`, a mixed type: `Ops.add_I` behind a boundary.

Two things the site had to learn:

- **Deserialized constants are delegating wrappers.** The `1` and `2` of
  `my $a = 1; my $b = 2` arrive as `P6OpaqueDelegateInstance`s whose
  STable is the type's but whose class is not the storage class; the
  site (and the decont site, same fix) looks through to the delegate,
  as the dispatch fold's `AttrSrc` always did. Until it did, every call
  missed and the site pinned generic while still measuring faster than
  before -- the boundary switch's boxing was gone -- which is why a
  fast path is verified by its miss count (`JESP_DEBUG=1` narrates site
  resolution and misses), never by its timing alone.
- **A plain value needs no speculation to decont.** The decont site now
  answers a non-container structurally (`STable.ContainerSpec == null`, a
  field load) and speculates only on the container it sees; before, a
  site alternating between a Scalar and a plain value missed four times
  and pinned generic.

**The intcache is not worth having here.** MoarVM's `sp_add_I` boxes a
small result from a per-type cache of shared Ints. Behind
`JESP_INTCACHE=1` this exists (`P6OpaqueREPRData.intCache`, -16..255,
filled on demand) and engages (two `1 + 2` results are one object), and
the loop measures the same with it as without (189 vs 190 ns), and so
does the warm `t/01-sanity` sweep run back to back (70 s on, 74 s off,
inside the run-to-run noise): a TLAB allocation of two small objects
costs what the bounds check and array load cost, and the GC pressure
does not show at this size. Off by default; the knob stays
for a workload that might show otherwise (allocation-heavy Int code with
a live-set large enough to make young collections expensive).

## Diamond 5: no frame for an inlined leaf (spesh's `inline.c`)

After diamond 4 the `+` loop's profile has no generic-road op left; its
cost is the two `CallFrame`s each `+` still builds -- the `infix:<+>`
candidate's and the `raku-assign` handler's -- construction, leave, the
live-invocation atomic, and the calling convention around them (about
42% of samples). Both bodies are inlined into the loop's compiled root by
the DirectCallNode; only the heap frame survives, and it cannot be
scalar-replaced: it is built behind a boundary, stored into `tc.curFrame`,
and holds the callee's lexical arrays. spesh's inlining never builds it.

The engine's frame-free mechanism (`docs/jvm-truffle-calling-convention.md`,
`NQP_CODE_NOFRAME`) is exactly that: a block that declares no live
lexical, makes no dispatch, has no nested block, reads no frame op, runs no
handler and takes only positional local-scope parameters runs with no
`CallFrame` at all. It stayed off because a frame-free CORE.c broke the
CORE.d compile with "Bind check failed".

**The tools.** `NqpFrameFree.kt` applies runtime overrides the first time
a block runs (through its stub, when its name is known): `NQP_FRAMEFREE=0`
runs every block framed, `NQP_FRAMEFREE_ONLY=a,b` / `NQP_FRAMEFREE_SKIP=a,b`
by name, `NQP_FRAMEFREE_TRACE=1` narrates each decision. The encoding is
otherwise identical, so a frame-free misbehaviour bisects in seconds
against one set of jars instead of a setting rebuild per hypothesis.
`NQP_CODE_WHY=1` at compile time prints each block's frame verdict with
its inputs (`code frame NAME -> framed|free frame_op= fdecls= dispatches=
nested=`).

**Bug 1: language.** Every "current HLL" the runtime reads -- `hllbool`,
`hllize`, `hllhash`, `hlllist`, `newexception`, `getcurhllsym`, the box
types `getattr` uses for a native slot, ... -- comes from `tc.curFrame`'s
compilation unit, which for a frame-free callee is the *caller's*. A Raku
accessor like `Parameter.named` (`nqp::hllbool(...)`, `--> Bool:D`)
entered from NQP dispatcher code built NQP's Bool, which is null, and the
return-type check dereferenced it; in the CORE.d compile the same
confusion surfaced as a bare `Died` out of a role specialization. This is
the rule spesh's `inline.c` enforces as "no `:useshll` op across HLLs".
**Fix:** at the call site. `NqpDispatch` enters a callee frame-free only
when its unit's HLL is the caller's (the caller's unit is now an operand
of the dispatch op; both are constants of the call node, so PE folds the
compare); the invoke road compares against `tc.curFrame`'s. With that
invariant every frame-derived HLL read is right, and no op needs to be
told which language it is in. Verified: the frame-free CORE.c loads and
runs, and CORE.d and CORE.e compile (parse 5.3 s and 26.7 s).

**Bug 2: self-introspection.** Ops that ask the current frame for the
block's *own* code ref, caller or phaser flags (`curcode`, `callercode`,
`getlexcaller`, `ctxcaller`, `backtrace`, `p6bindsig`, `p6capturelex`,
`p6setpre`/`p6clearpre`/`p6inpre`, `p6stateinit`, `p6takefirstflag`, ...)
have no answer without a frame; the encoder's `%frame_forcing_ops` makes
such a block framed, as does `p6typecheckrv` on a generic return type
(it instantiates the type against the routine's own frame). Dynamic
lookups (`getlexdyn`) are fine: a frame-free block declares no lexicals,
so skipping its frame is exact.

**Bug 3: bind failure.** A frame-free callee's `assertparamcheck` ran
`BindFailure.failed`, which reads `tc.frame` and found the caller's
dispatch there. With `cf == null` the check now throws
`NqpFrameFreeBindFailure`, and the direct road that entered the callee,
which *is* the dispatch and holds its program, arguments and callee, owns
it: a program with bind control resumes itself with the failure flag (a
record materialized on the spot); otherwise `BindFailure.reportFrameFree`
runs the language's `bind_error` handler with the callee's code object,
callsite and arguments.

The encoder now marks eligible blocks frame-free by default;
`NQP_CODE_NOFRAME=0` turns it off.

**Gates for the rebuilt setting (both at the same parallelism, 4).**
Cold `t/01-sanity` with 4 runners: 25 of 25 in 135 s. Warm eval-server
sweep with 4 servers at 2 GB: 25 of 25 in 79 s. (With 4 servers at 3 GB
one chunk failed with no TAP at all: the launcher's memory guard refused
the fourth server against the 21 GB available. Size the pool by memory
before reading a chunk failure as a test failure.) The smoke script is
unchanged. From here on the two gates are always run and labelled with
the same job count.

**Compile time.** The frame-free setting build's CORE.c parse is 228-230 s.
The right comparison is not `NQP_CODE_NOFRAME=0` (that changes only how
the *output* is encoded; both arms 224-230 s) but the runtime knob
`NQP_FRAMEFREE=0`, which runs the compiler's own blocks framed: 231.6 s.
Frame-free changes the compiler's speed by nothing measurable. The gap
to the morning's 206 s predates this diamond and needs its own
bisection across diamonds 3 and 4. CORE.d parse 6.8 s, CORE.e 32.5 s;
the whole `make` 845 s with BOOTSTRAP at about 4.5 minutes.

After the parameter-lowering round the same measurement reads 241.9 s
inside `make` and 246.9 s standing alone, against 257.7 s standing
alone with `NQP_FRAMEFREE=0` on the same build (both on a machine with
no other JVM). So the frame-free callees still cost the compiler
nothing -- if anything they save a few seconds -- and the drift from
228-232 s is something else: the encoder change, the sentinel cache, or
the machine. The bisection across diamonds 3 and 4 is still owed.

**Coverage, measured on the first frame-free setting build.** The
setting's 21082 encoded blocks split 4691 frame-free / 16391 framed
(`NQP_CODE_WHY` on a manual CORE.c compile). Framed because they make a
dispatch: over half (the return-register class the calling-convention
doc defers); because of a frame-forcing op: about a third; because of
un-lowered lexicals: the rest.

**The `+` candidate is in the last class, and the reason took three
traces to name.** The lowering pass (`RAKUDO_LOWERING_DEBUG=1`, which now
names the routine of each decision and reports a decided lowering that
mints no local) approves `$a` and `$b` in all 26 `infix:<+>` candidates.
Read in source order within Int.rakumod, the three consecutive `+`
verdicts are: `framed frame_op=0 fdecls=4 lex:$/ lex:$! lex:$_ lex:$¢`
for `(Int:D $a, Int:D $b --> Int:D)` -- its parameters *were* lowered,
and only the four unused implicit magicals remain declared -- then two
`framed fdecls=2 lex:$a lex:$b` for the `int` and `uint` candidates,
whose native parameters correctly cannot become locals. The `*` trio
right after reads `free`, `framed`, `framed`. Why `+` keeps its
implicits and `*` does not: the setting uses `+` while compiling itself,
so its block is formed at BEGIN time and later re-formed, and the
re-formation keeps unused implicits as bare slots because a context the
early compilation serialized rebinds them by name at load. That
rebinding writes the static lexical table, which a frame-free block
keeps; the body never names the slots, and none of `$/ $! $_ $¢` is
dynamic. **Fix (nqp 00f54cdbc):** bare implicit magicals no longer count
as live declarations in the encoder's predicate. A second, smaller leak
showed in the same trace: 337 approved lowerings minted nothing because
a BEGIN-time analyzer could not resolve the sentinel class
`Rakudo::Internals::LoweredAwayLexical`; the pass now keeps the last
resolved sentinel in the HLL symbol table for such analyzers. The
`raku-assign` handler `-> $cont, $value { nqp::bindattr(...) }` is NQP
code whose parameters are lexicals by construction and stays framed.

**Result of the round (2026-09-07 evening, full engine rebuild).**
`NQP_FRAMEFREE_TRACE=1` now reports `infix:<+>` as free. The loop
measures 141.7 and 141.8 ns per iteration on a quiet machine; the
169-215 ns readings taken while the sweep's servers were still exiting
show how much a loaded machine inflates this number -- check
`pgrep -c java` and the load average before trusting a timing. JFR on
the loop confirms where the last frame is: of 168 samples inside the
CallFrame constructor, 166 arrive through the mapped direct road (the
`raku-assign` handler) and one through the resumable road that `+`
takes. Frame construction is now one eighth of the loop's samples; the
handler is the next target (either the encoder learns that an NQP
leaf's parameters need no frame, or the assign outcome gets sited).

## Diamond 6: `hllize` as a sited operation, `checkarity` off the boundary

**Where it came from.** With `+` frame-free, a JFR recording of the loop
(quiet machine, `settings=profile`) put the remaining visible samples at:
frame construction and leave 19% (the `raku-assign` handler), `hllize`
through the generic classlib road 13%, `checkarity` 7%, and a grapheme
break iterator inside the engine-program loader 12% (start-up, not the
loop). One caveat learned on the way: JFR shows no Truffle-compiled root
at all here, so those shares are of the interpreter tier plus the Java
runtime -- the warm-up and everything the setting compiler runs -- not of
the steady-state loop. Frame construction is visible from both tiers.

**Who hllizes.** Not `+`'s body: the signature binder. A parameter with
no specific nominal type gets `hllize` around its argument before the
type check (`src/Raku/ast/signature.rakumod`, "HLLize before type
checking"), and the candidate's two sigilless parameters take that road.
`JESP_TRACE_CLASSLIB=hllize` names the block running any classlib
`hllize` once per frame (the caller's frame for a frame-free callee) and
showed exactly one in the loop: the frame-free callee of the mainline.

**The site (nqp `NqpTypeOps.HllizeSite`).** `Ops.hllize` answers the
object itself whenever the STable's owner is the wanted language, or the
STable plays a role that language does not transform. Every one of those
branches reads only the STable and the language's configuration, never
the object, so the verdict is a function of (STable, language): one
STable compare stands in for the frame chase, the method-handle call and
the role switch. That is spesh's `optimize_hllize`, which deletes the op
under known type facts. The wanted language is the block's own unit
(`cu(f)`), which the same-HLL rule of diamond 5 makes equal to the frame's.
Non-identity cases (a foreign type to box, a transform to invoke) pin
the site and stay on `Ops.hllize`. The routing lives in the builder's
classlib case: the JVM compiler maps `hllize` by name onto `Ops`, so the
choice is by name (`Lorg/raku/nqp/runtime/Ops;` -- descriptor form, the
first cut compared the bare class name and matched nothing).

**`checkarity` and `flatArgs`.** Both were `@TruffleBoundary` calls on
every entry. The arity verdict is two field compares on the callsite
descriptor and three field writes; only flattening and the failure need
the runtime. They are plain inlinable code now, the slow road behind the
boundary. spesh drops the check outright once the callsite is known;
here the fields are frame arguments, so the compares stay but the call
goes.

**Verification.** `JESP_DEBUG=1` on the loop: 510 hllize sites resolved,
34 missed at least once, 4 pinned; the classlib trace no longer fires in
the loop. The loop: 142 ns → 123-124 ns (quiet machine, both changes
together). Gates at 4: cold `t/01-sanity` 25 of 25 in 98 s (was 135 s
on the diamond 5b build), warm sweep on 4 servers at 2 GB 25 of 25 in
81 s; the smoke script's output is unchanged. A runtime-jar change only:
no setting was rebuilt for this diamond.

**Compile time, A/B'd.** After the stage0 refresh that followed (nqp
eec893edb) and a `make clean && make`, CORE.c parsed in 270 s inside
`make` and 268.6 s standing alone. The same setting build with the
engine and runtime sources checked out at diamond 5b and the jars
rebuilt from them: 264.8 s. So diamond 6 costs the compiler nothing;
the step from 247 s to 265-270 s came with the bootstrap refresh, and
the cold `t/01-sanity` gate on the same diamond 6 jars went from 98 s to
131 s across that refresh too. Since stage0 only compiles stage1, the
stage2 output ought to be identical either way -- and it is: the same
sources built from the old stage0 in a scratch clone give stage2 jars
whose class files differ by a constant 31 bytes and whose sidecars by
about 30, the build path embedded as each unit's description (the
scratch path is shorter). No code changed between 247 s and 268 s; the
machine's state did (the desktop's file indexer was holding 2 GB and
churning at the time). Two numbers on identical code an hour apart can
disagree by 8%, so compare arms built and measured back to back, as the
diamond 6 A/B and the diamond 7 make were.

## Diamond 7: frame-free across languages (spesh's `:useshll` rule)

**The handler's frame was never about its declarations.** The last
frame per iteration of the `+` loop is the `raku-assign` handler
`-> $cont, $value { nqp::bindattr($cont, Scalar, '$!value', $value) }`
(`src/vm/moar/dispatchers.nqp`, shared with the JVM). NQP's own QAST
optimizer already lowers a leaf block's parameters to locals
(`nqp/src/NQP/Optimizer.nqp`, `lexicals_to_locals`: params and vars
alike, unless a nested block uses them), and a handler-shaped probe
encodes as `free frame_op=0 fdecls=0`. What framed it at run time was
diamond 5's same-language rule: the handler is NQP-language code called
from Raku code, and `NqpDispatch` enters a callee frame-free only in its
caller's language, because an op that reads the current language off
`tc`'s frame would otherwise read the caller's.

**spesh's rule is per op, not per block.** `inline.c` refuses to inline
across HLLs only when the candidate contains a `:useshll` op. The engine
now does the same, folded to one bit at encode time: the encoder keeps
`%hll_ops` (the union of MoarVM's oplist marks and every JVM `Ops`
function that reaches `hllConfig` through the frame, mapped back to op
names through the classlib table) and records per block whether any
appears; the wire's frame word carries it as bit 1, chosen so a program
encoded before the bit reads as "not free" (`NqpWire.Program.hllFree`);
`NqpRootNode.hllFree` holds it; and the three entry decisions in
`NqpDispatch` become `needsFrame || (!hllFree && !sameHll)`. `getattr` is
deliberately not on the list: it is too common to blacklist, and its
only language use is boxing a native slot read in object context, so the
engine's getattr road now boxes with the block's own unit
(`NqpOps.getattrSlow` -> `Ops.getattrIn(..., hll)`) instead of the
frame's. Ops naming their language (`hllizefor`, `hllboolfor`) read no
frame and are not on the list either. An internal die inside a
cross-language frame-free callee surfaces as the caller language's
exception, as it already did within one language.

`NQP_CODE_WHY` now prints `uses_hll=` with the verdict.

**The bootstrap it broke, and why.** The first cut of the getattr change
made the runtime's `Ops.getattr` read `tc.frame.codeRef` eagerly, on
every call, to hand its language to the new `getattrIn`. The nqp
bootstrap then failed in stage2 with "Missing or wrong version of
dependency .../stage1/NQPCORE.setting": while a compiler loads a
module's setting the current frame is a dummy without a code ref, the
eager read threw inside the loader, and the module ended up bound to
the compiler's own (stage1) setting instead of the stage2 one -- whose
handle differs by design (`--stable-sc=stage1` is spliced into stage1
handles precisely so the two can coexist). The language is resolved
lazily now, on the native-slot boxing branch only. The dead end on the
way is worth recording: after the fix I re-ran the runner against the
stage2 artifacts already on disk, saw the same error, and concluded the
fix was wrong; the artifacts were the broken ones, and only a stage2
rebuild could test the fix. Two runtime knobs came out of the hunt:
`JESP_HLLFREE=0` keeps diamond 5's same-language rule, and
`JESP_HLLFREE_TRACE=1` names each callee entered frame-free across
languages. An NQP-only bootstrap has none: the rule only ever fires
for Raku code calling NQP code, which is its target.

**Result (nqp 56b905fcf, full engine rebuild).** `JESP_HLLFREE_TRACE=1`
on the loop names exactly one callee entered frame-free across
languages: the anonymous NQP handler, from Raku. The loop: 123-124 ns →
83-92 ns (quiet machine, two runs). JFR: one CallFrame-constructor
sample in the whole run, against 168 on diamond 6 -- the loop builds no
frame any more. And the compiler pays too, the other way round from
what one might fear: the RakuAST frontend and the setting's BEGIN-time
code are Raku-language callers of NQP-language helpers all day, so
inside `make` CORE.c parsed in 224.7 s (270 s on the same nqp sources
before this diamond, 247 s before the stage0 refresh), BOOTSTRAP
compiled in 263 s (325 s), and the whole `make` took 727 s (935 s).
Gates at 4: cold `t/01-sanity` 25 of 25 in 126 s (131 s on the previous
build; the cold gate has sat at 126-135 s since the stage0 refresh
against 98 s once before it, which is the refresh's still-open
question, not this diamond's); warm sweep on 4 servers at 2 GB 25 of 25
in 74 s (81 s). One operational note: the harness's low-memory watchdog
killed two gate chains at the seam between steps, after each step's
result was already in the log; four cold runners exiting while four
servers start is the peak to avoid, so let one settle before the other.

## Where the code is

- `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt`
  -- the fold, the replay, the direct roads (Kotlin since 2026-09-07; the
  no-assertion Kotlin flags are set in `nqp/nqp-truffle/build.gradle.kts`
  because the file is on every dispatch instruction's compiled path).
- `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt`
  (the sites and fast paths of diamond 3, `HllizeSite` of diamond 6),
  `NqpNativeOps.kt` (the native arithmetic), `NqpRaw.java` (raw reads of
  `lateinit` fields); `NqpOps.java` (`checkarity`/`flatArgs` fast paths;
  `JESP_TRACE_CLASSLIB=meth` names the block running a classlib op);
  `NqpRootNode.java` (the operations; Java for the DSL processor),
  `NqpProgramBuilder.java` (`dedicatedOp`: the op-id to operation map,
  `dedicatedClasslib`: the same by name for classlib ops;
  Java because it consumes the generated builder).
- `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/ContainerSpec.kt`
  (`fetchAttribute`), rakudo's `RakudoContainerSpec.kt` (Scalar answers
  `$!value`) and `RakOps.kt` (`p6typecheckrvCacheable`).
- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CallFrame.kt`
  (`dispatchProgram`, `invokingDispatch`), `ThreadContext.kt`
  (`pendingProgram`), `dispatch/Dispatch.kt` (`findResumption`),
  `dispatch/DispatchCompiler.kt` (`invokeResumable`).
- Measurement: `NQP_DISPATCH_STATS=1` prints folded hits, misses, boundary
  invokes and the per-kind split at exit; the boundary-invoke count is
  the direct-road check. JFR with `RAKUDO_JVM_XOPTS=-XX:StartFlightRecording=...`
  and `jfr print --events jdk.ExecutionSample --stack-depth 1`.

Runtime-only change: `./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars`
(seconds), restart eval servers; no setting recompile.

## Object model: not RootNode, maybe DynamicObject, probably an Assumption

Asked 2026-09-07: could a P6opaque instance descend from `NqpRootNode`?
No. A REPR instance roots in `SixModelObject` (single inheritance; every
op, REPR, serializer and container spec dispatches on it), and a
`RootNode` is the executable root behind a `CallTarget` with its own
frame descriptor and DSL interpreter state, never a value in a frame
slot and never scalar-replaced. Objects do not need a Truffle base class
to be visible to PE: Graal reads plain fields, which is what `AttrSrc`
and the diamond-3 decont and create sites exploit.

Three related options, in order of cost:

- **An `Assumption` per STable**, invalidated on compose, mixin and
  rebless, so the istype and p6typecheckrv sites' trust in
  `TypeCheckCache` and the create site's trust in `REPRData.instance`
  become checked rather than assumed. Needs nqp-runtime to see
  truffle-api at compile time (annotations and Assumption only); verify
  that this does not put a second Truffle copy on the classpath. Small;
  do it if the sweep ever shows a stale type-check cache.
- **Truffle `DynamicObject` + `Shape`** as the object model: shape-guarded
  field loads, shape transitions as the invalidation story, per-node
  property caches. STable would map to the shape's type slot, attribute
  slots to properties, mixins to transitions. A full migration of every
  REPR, the serializer and the generated storage classes, duplicating what
  STable plus `field_N` already give PE. Recorded as an idea; not planned.
- **Not `RootNode`.**

The real bound on object cost is escape: the `+` result travels through
the heap `CallFrame`'s return registers, so no scalar replacement happens
regardless of the object's class. That is the calling-convention project.
