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
| `sp_add_I`/`sub_I`/`mul_I` with the small-int cache | a specialized `add_I` for two small Ints returning through the cached Int allocation | **next (diamond 4)**: the last generic-road op in the `+` loop, 18% of samples |
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

## Where the code is

- `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt`
  -- the fold, the replay, the direct roads (Kotlin since 2026-09-07; the
  no-assertion Kotlin flags are set in `nqp/nqp-truffle/build.gradle.kts`
  because the file is on every dispatch instruction's compiled path).
- `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt`
  (the sites and fast paths of diamond 3), `NqpNativeOps.kt` (the native
  arithmetic), `NqpRaw.java` (raw reads of `lateinit` fields);
  `NqpRootNode.java` (the operations; Java for the DSL processor),
  `NqpProgramBuilder.java` (`dedicatedOp`: the op-id to operation map;
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
