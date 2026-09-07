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
(`plusquick.raku`; `nqp::time` around the loop):

| state | ns per `+` | folded hits | boundary invokes |
|---|---|---|---|
| 2026-09-07 morning, engine build | 798 | 90M (2 per op) | 45M |
| diamonds 1 and 2 | 777 | 90M | 8k |

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
| `optimize_istype`/`isconcrete`/`isnull`/`decont`/`assertparamcheck`, `sp_fastcreate`: facts from guards fold the op to a constant or a field load | dedicated Truffle operations with a per-instruction STable inline cache, so PE folds the answer under the guard already taken | **next (diamond 3)** |
| `sp_add_I`/`sub_I`/`mul_I` with the small-int cache | a specialized `add_I` for two small Ints returning through the cached Int allocation | after 3 |
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

## Where the code is

- `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt`
  -- the fold, the replay, the direct roads (Kotlin since 2026-09-07; the
  no-assertion Kotlin flags are set in `nqp/nqp-truffle/build.gradle.kts`
  because the file is on every dispatch instruction's compiled path).
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
