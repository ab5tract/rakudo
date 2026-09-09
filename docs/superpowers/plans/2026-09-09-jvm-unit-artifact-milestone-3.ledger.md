# SDD ledger — plan: docs/superpowers/plans/2026-09-09-jvm-unit-artifact-milestone-3.md

Spec: docs/superpowers/specs/2026-09-09-jvm-unit-artifact-design.md (reachable, binding; milestone 3 line + sections 2, 4, 6; milestone-2 line's deletions as narrowed by the plan's deviation 1).
Trees: rakudo worktree (docs, runners, gate) at 5ae25a8d3c; nested nqp/ tree (compiler + runtime) at da1f5088a, branch jesp-direct-lazy-records.
User decisions (2026-09-09, brainstorm): six-part shape as proposed; NO t/spec ("until it doesn't take hours to run t/"); two t/ sweeps (after the flip, after the deletions) each under --max=7200; no knob-off make (forward only); anonymous-block naming deferred; RakuAST `#?if jvm` edits allowed (none needed: LibraryLoader already special-cases ModuleLoader.class).
Baseline (milestone-2 gate): NQP_UNIT=1 clean buildJvm 296 s; t/nqp record road 115/118 in 381 s at 3 jobs; make 1274 s; t/01-sanity 25/25 in 214 s at 2 jobs; t/ (2026-09-05, one warm server, class road): 01-sanity 1m04 / 02-rakudo 46m33 (20 fail) / 03-jvm 0m17 / 04-nativecall 5m46 (2) / 05-messages 8m59 (4) / 06-telemetry 2m25 / 07-pod-to-text 0m20 / 08-performance 10m06 (2) / 10-qast 0m11.

## Pre-flight scan (2026-09-09)

| pair / task | produces vs consumes | finding |
|---|---|---|
| T1 encoder -> T1 builder | wire FORLOOPL=35 layout `condType lastId nrId outerIdx labelLocal labelExpr cond pre body`; encoder emits op, ct_at, lid, nrid, outer, lbl_local, label expr, cond, pre, call | consistent |
| T1 exit handlers -> runtime | frame_op=1 -> wire word 3 framed -> NqpDispatch builds a CallFrame -> cf.leave() runs hll.exitHandler over Ops.result_o(caller); StoreRet stored the value inside the call | consistent (explorer verified every road: direct, enterEngine, ProgramEntry, resume) |
| T1 labeled control -> runtime | newexception/setpayload/setextype via W_CLASSLIB (registered in Compiler.nqp:1860-1865, no :cont), throw via wire 181 answering result_o(cf); loop unwind arms mask-match NEXT\|LABELED against NEXT rows; _is_same_label compares payload hashCode | consistent |
| T2 knob default -> T2 test | Compiler.nqp die text contains `needs the encoder on`; t/nqp/124 greps that substring under NQP_CODE_RUN=0 | consistent |
| T2 runners -> UnitMain | `UnitMain <unit jar> args...` (UnitMain.kt:12-19); create-jvm-runner.pl's $postamble appends `"$@"` after $command, so `... UnitMain <app> "$@"` | consistent |
| T2 precomp -> loader | CompUnit::Loader.rakumod:46-48 `nqp::loadbytecodebuffer` -> LibraryLoader.load(tc, ByteBuffer) sniffs UnitZip.isUnit(buffer) -> UnitLoader.loadAndRun(bytes) | consistent (no writer change: Backend.nqp keys on target+output, not extension) |
| T2 dumper -> backends | `$!backend.is_compunit` exists on jvm (Backend.nqp:117), moar (:828), js (:358) | consistent |
| T4 deletions -> stage0 | stage0 jars run on this runtime and are class-road units with codeprograms.lz4 sidecars; javap shows only codeRunIdx call sites | runtime writer/loader stays (deviation 1); codeRun(String) private |
| T4 JASTNodes -> JastClass.kt | attributes deleted on both sides in the same task; UnitWriter reads programs/callsites/blockvalues/nestedClasses/className/hll + cr_* only | consistent |

## Rulings, deviations, deferred minors (filled as tasks run)

- Known gap, not worked: torn-frame LEAVE never runs on the JVM (CallFrame.countLeft / giveBackTornFrames), both roads, pre-existing; S04-phasers will show it when t/spec runs.
- Known gap, not worked: interop adaptors (RakudoJavaInterop.kt:930-937, BootJavaInterop.kt:204-209) subclass a generated CompilationUnit through ByteClassLoader (spec item 9).
- Deferred (user): anonymous block names in backtraces.
