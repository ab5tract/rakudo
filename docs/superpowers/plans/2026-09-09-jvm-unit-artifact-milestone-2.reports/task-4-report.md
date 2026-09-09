# Task 4 report: the milestone-2 gate (controller-run, 2026-09-09)

The gate subagent stalled on a monitor after Step 1 (user report); the controller stopped it and ran Steps 2-4 as plain background watched-run jobs. Step 1 evidence is the agent's (`/home/longwalker/.claude/jobs/3420e344/tmp/step1-jars.txt`).

## Step 1: artifacts of the standing build (Task 2 build, nqp 0b149eaeb, elapsed 296 s)
All 11 jars in `nqp/build/jvm/share/lib/`: `unit.meta`=1, `.class`=0 (JASTNodes, ModuleLoader, NQPCORE.setting, NQPHLL, NQPP5QRegex, NQPP6QRegex, QAST, QASTNode, QRegex, nqp, nqpmo).

## Step 2: t/nqp on the record road
Command: `NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 raku tools/build/watched-run.raku -t=nqp/t/nqp --jobs=3 --log=/home/longwalker/.claude/jobs/3420e344/tmp/sweep-record.log -- nqp/nqp-j-gradle` (logs: `sweep-logs/`, SUMMARY there).
Result: `113 of 118 ok in 381s` (baseline 487 s, class-road test compiles on the same artifact jars).
FAIL: 019-file-ops.t, 063-slurp.t (cwd-relative, as milestone 1) — from the nqp directory under the knob: 019 `1..112` all ok, 063 `1..1` ok. => 115/118.
FAIL: 059-nqpop.t, 067-container.t, 084-loop-labels.t — each `unit artifact (NQP_UNIT): block ... has no engine program and would need bytecode`; with NQP_CODE_BAIL=1: 059 `<mainline> code-bail withy general`, 067 `<anon 24> code-bail withy general`, 084 `<mainline> code-bail labeled control`. Encoder refusals in the test scripts themselves (non-comp-mode units), hidden on the class road by per-block fallback; hard errors on the record road. Not milestone-2 regressions: item-7 shapes for the strict campaign (runtime-compile side).

## Step 3: Rakudo gate (class road) and probes
- `perl Configure.pl --backends=jvm --gen-nqp`: EXIT=0, 4 s, no nqp rebuild; artifact jars intact afterwards (nqp.jar meta=1 class=0). Log: `/home/longwalker/.claude/jobs/3420e344/tmp/rakudo-configure.log`.
- `make`: `=== EXIT=0 verdict=ok elapsed=1274s ===` (milestone 1: 1173 s). Markers: rakudo.jar 195 s; BOOTSTRAP v6c 229 s -> CORE.c 657 s (428 s; m1 339 s); CORE.c 657 s -> v6d 1172 s (515 s; m1 509 s); CORE.d 1175 s; v6e 1204 s; CORE.e 1207 s. Log: `/home/longwalker/.claude/jobs/3420e344/tmp/rakudo-make.log`. (User: no compile-time investigation now.)
- `t/01-sanity` at 2 jobs: `25 of 25 ok in 214s` (m1 210 s). Log: `/home/longwalker/.claude/jobs/3420e344/tmp/sanity.log`.
- Probe 1: `NQP_UNIT=1 ... NQP_CODE_WHY=1 ./rakudo-j -e 'BEGIN { say 1 }; say EVAL "2"; say 3'` -> `unit record A1F6... (4 programs)`, `1`, `unit record 4F80... (6 programs)`, `unit record 32C8... (5 programs)`, `2`, `3`. Rakudo's mainline, BEGIN block and EVAL all compile as records; no die.
- Probe 2: `NQP_UNIT=1 ... ./rakudo-j --target=jar --output=.../BeginMod.jar BeginMod.rakumod` (unit module with `my &kept = BEGIN { my $n = 41; -> { $n + 1 } }`) -> `unit record FDFD... (5 programs)` for the BEGIN compile, `unit artifact FB3B... (10 programs, 10 qbids, 0 call sites, 0 nested)`; listing: unit.meta, unit.programs, unit.serialized.lz4, no .class. The BEGIN closure was re-pointed at the module's own emission (jvm-repoint-dynamic-code), so no nested unit was embedded: this shape does not exercise nested/ (plan deviation 2 stands; CORE.c's four nested units come from another shape, milestone 3's business).

## Step 4: timings (next baseline, forward only)
| what | this gate | milestone 1 |
|---|---|---|
| NQP_UNIT=1 clean buildJvm | 296 s (Task 2) | 273-299 s |
| t/nqp sweep, 3 jobs | 381 s (record road) | 487 s (class-road test compiles) |
| Configure | 4 s | 3 s |
| make | 1274 s | 1173 s |
| t/01-sanity, 2 jobs | 214 s | 210 s |
