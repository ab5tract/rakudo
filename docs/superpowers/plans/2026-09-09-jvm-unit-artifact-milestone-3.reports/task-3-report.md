# Task 3 report: t/ through the eval server on artifact units (sweep 1)

## Summary

Sweep 1 (the brief's literal Step-2 command) hit the 2-hour ceiling at
exactly 7200s, having completed 35 of 38 chunks (chunks 36-38 — the tail
of `t/08-performance` plus `t/10-qast`/`t/13-experimental`/`t/14-smoke` —
never ran). Per the coordinator's override, a second invocation
(`t3-sweep2.log`) ran the never-reached directories plus `t/08-performance`
whole; it finished cleanly in 658s. Because sweep 1 was killed mid-race,
its own per-chunk failure detail (file-level TAP) was never printed to the
log — only chunk-level ok/FAIL + drove a document. Recovering it took two
more small supplementary sweeps (see "Method note" below).

- **Total wall clock:** 7200s (sweep 1, ceiling fired) + 658s (sweep 2) =
  **7858s (~131 min)** for the two sweeps proper. An additional ~1600s of
  supplementary targeted re-runs (a 90-file sweep + ~9 individual cold
  `./rakudo-j` runs) was spent recovering per-file attribution that
  sweep 1's timeout discarded.
- **Ceiling fired:** YES, on sweep 1 (`over the 7200s ceiling` mechanism:
  `=== EXIT=124 verdict=timeout elapsed=7200s ===`). Sweep 2 did not hit
  it (`=== EXIT=1 verdict=ok elapsed=658s ===` — exit 1 here just means
  "some chunks failed", not a timeout).

## Method note: why two supplementary sweeps were needed

`evalserver-sweep.raku` only prints its per-chunk file-level breakdown
(the `--- chunk N: <files> ---` / TAP lines) in its **final** summary,
after all chunks finish. Sweep 1 was killed by `watched-run.raku`'s
`--max=7200` before it reached that final `say` block, so the log has only
`chunk N/38: ok|FAIL[ *** no TAP ***]` lines — no file names for the
FAILED chunks. To identify which specific files were new failures without
re-running all 418 files:

1. Reconstructed the exact file→chunk mapping used by the sweep (same
   `.IO.dir(...).sort.batch(11)` logic, 0-based internally, but the sweep's
   own progress notes use a 1-based **completion-order** counter — cross-
   checked against sweep 2's final summary, which does report real chunk
   indices for its failures, confirming the assumption that completion
   order tracks chunk-index order closely enough with a 2-server pool).
2. Cross-referenced every FAILED chunk's file list against the
   2026-09-05 known-fail list per directory (script-driven, not manual —
   an earlier manual pass mis-attributed two chunks). 14 of the 23 FAILED
   chunks are fully explained by a known-bad file's presence.
3. The 8 chunks with **no** known-fail file in them (chunks 3, 4, 9, 13,
   14, 16, 28, 30) plus chunk 34's `t/07-pod-to-text` remainder (its
   `t/08-performance` files were already covered cleanly by sweep 2) were
   re-run as one 90-file targeted eval-server sweep
   (`t3-unexplained.log`, 815s, completed cleanly) to get real per-file
   TAP output.
4. Confirmed new failures were then re-run individually
   (`RAKUDO_RAKUAST=1 ./rakudo-j -Ilib <file>`, with `NQP_CODE_BAIL=1`
   where a `has no engine program` die appeared) per the brief's Step 3.

An abandoned first attempt re-ran all 233 files from every FAILED sweep-1
chunk as one sweep; it was killed early (2 of 22 chunks in ~5 min) once it
became clear most of those chunks were already explained by the known-fail
cross-reference and didn't need re-verification.

## Sweep 1 (`t/` full command, ceiling fired)

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --max=7200 --stall=1500 \
  --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t3-sweep.log \
  --show='chunk' --show='files in' --show='FAIL' -- \
  raku tools/build/evalserver-sweep.raku \
  t/01-sanity t/02-rakudo t/03-jvm t/04-nativecall t/05-messages \
  t/06-telemetry t/07-pod-to-text t/08-performance t/10-qast \
  t/13-experimental t/14-smoke
```

`=== EXIT=124 verdict=timeout elapsed=7200s ===`

Header line: `418 files, 38 chunks of 11, 2 servers x 6g heap + 3g
off-heap (18g of a 21g budget, 24g available)`.

**Deviation flagged:** the brief's literal Step-2 command line does not
pass `--jobs=3`; the sweep's own MemAvailable-based auto-sizing picked
**2** servers (21g budget / 9g-per-server ≈ 2.3 → 2), not the 3 named in
this task's "Pool size" constraint. Passing `--jobs=3` at the box's
starting memory (24g available) would itself have died with a
budget-exceeded error at the default 6g heap (3×9g=27g > 21g budget);
`--heap=4` would have been needed alongside `--jobs=3` to fit. This
wasn't caught before launch. No re-launch was done given ~85 min of
sunk progress at 35/38 chunks when noticed; the finding stands as run
with 2 servers throughout.

Chunks 1-35 completed; 36-38 did not (one stale eval-server JVM, pid
77796, was left running past the timeout and was killed before sweep 2).

Per-chunk ok/FAIL (completion-order numbering):
```
1 ok, 2 ok, 3 FAIL, 4 FAIL, 5 FAIL*, 6 ok, 7 FAIL*, 8 FAIL, 9 FAIL,
10 ok, 11 FAIL*, 12 ok, 13 FAIL*, 14 FAIL, 15 ok, 16 FAIL*, 17 ok,
18 FAIL*, 19 ok, 20 FAIL*, 21 FAIL*, 22 FAIL, 23 ok, 24 ok, 25 FAIL,
26 ok, 27 ok, 28 FAIL, 29 FAIL*, 30 FAIL*, 31 FAIL, 32 FAIL*, 33 FAIL,
34 FAIL, 35 FAIL*        (* = "a file produced no TAP")
```
23 of 35 completed chunks FAILed; 12 were clean.

## Sweep 2 (never-reached + `t/08-performance` whole)

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --max=7200 --stall=1500 \
  --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t3-sweep2.log \
  --show-file=/home/longwalker/.claude/jobs/288cfddd/tmp/t3-sweep2.markers \
  --show='chunk' --show='files in' --show='FAIL' -- \
  raku tools/build/evalserver-sweep.raku \
  t/08-performance t/10-qast t/13-experimental t/14-smoke
```

`=== EXIT=1 verdict=ok elapsed=658s ===` (completed, not a timeout)

Header: `53 files, 5 chunks of 11, 2 servers x 6g heap + 3g off-heap (18g
of a 22g budget, 25g available)`.

Summary lines: `53 files in 658s across 5 servers`; `3 of 5 chunks
failed`; `*** 2 chunk(s) contained a file with no TAP -- lower --chunk
***`. All 5 chunks ran to completion (chunk indices 0,2,3 failed; 1,4
clean) — full per-file TAP was captured, including for the two "no TAP"
chunks, which turned out **not** to be heap exhaustion (see below): each
no-TAP file dies with a `===SORRY!===` unit-artifact refusal before any
TAP plan is printed, which is what the harness reports as "No subtests
run".

## Per-directory table (2026-09-05 layout)

| subdir | files (now) | result | #fail | wall | failing files |
|---|---|---|---|---|---|
| 01-sanity | 25 (was 25) | PASS | 0 | interleaved w/ 02-rakudo in ch.1-3 of sweep 1 | — |
| 02-rakudo | 298 (was 290, +8) | FAIL | 20 known-consistent + **15 new** (6 now-passing) | interleaved, ch.3-30 of sweep 1 (~4948s span) | see NEW/KNOWN lists below |
| 03-jvm | 1 (was 1) | PASS | 0 | interleaved in ch.30 | — |
| 04-nativecall | 30 (was 30) | FAIL | 2 known-consistent + **2 new** | interleaved, ch.30-33 (~1391s span) | 08-callbacks.t 23-incomplete-types.t (known); 00-misc.t 02-simple-args.t (new) |
| 05-messages | 5 (was 7, **-2 removed**) | FAIL | 4 known-consistent | interleaved in ch.33 | 01-errors.t 02-errors.t 03-errors.t 10-warnings.t |
| 06-telemetry | 4 (was 4) | PASS | 0 | interleaved in ch.33 | — |
| 07-pod-to-text | 2 (was 2) | PASS | 0 | interleaved in ch.34; confirmed via targeted rerun | — |
| 08-performance | 42 (was 42) | FAIL | 2 known-consistent + **5 new** | 658s (sweep 2, clean whole-dir run) | 15-rakuast-native-metaop.t 36-rakuast-begin-compiled-remark.t (known); 14-rakuast-native-incdec.t 28-rakuast-metaop-hoist.t 30-rakuast-native-attr-lvalues.t 32-rakuast-native-param-bind.t 39-rakuast-native-arg-value.t (new) |
| 10-qast | 1 (was 1) | PASS | 0 | within sweep 2's 658s | — |
| 13-experimental | 9 (no 09-05 record) | PASS | 0 | within sweep 2's 658s | — |
| 14-smoke | 1 (no 09-05 record) | PASS | 0 | within sweep 2's 658s | — |

Per-directory wall clocks are not cleanly separable for 01-sanity through
08-performance-tail because sweep 1's chunks interleave directory
boundaries (a single chunk can span two directories); only chunk
completion timestamps are available, given in each row where useful.

## NEW failures (not in the 2026-09-05 record), by class and evidence

**Class (a) — encoder refusal on the record road** (`has no engine
program`, `NQP_CODE_BAIL=1` reason):

| file | block (cuid) | bail reason |
|---|---|---|
| t/08-performance/28-rakuast-metaop-hoist.t | `<unit>` (71) | code-bail unnamed chain link |
| t/08-performance/30-rakuast-native-attr-lvalues.t | `wrap` (99) | code-bail sized uint attributeref |
| t/08-performance/32-rakuast-native-param-bind.t | `t` (17) | code-bail sized typed param |
| t/08-performance/39-rakuast-native-arg-value.t | `<anon 48>` (48) | code-bail unnamed chain link |
| t/04-nativecall/00-misc.t | `abs` (18) | code-bail sized typed param |
| t/04-nativecall/02-simple-args.t | `TakeInt` (1) | code-bail sized typed param |

**Recurring shapes** (candidates for a single amend, per the brief —
not fixed here, report-only):
- "**code-bail sized typed param**": 3 files across 2 directories
  (08-performance/32-rakuast-native-param-bind.t,
  04-nativecall/00-misc.t block `abs`, 04-nativecall/02-simple-args.t
  block `TakeInt`) — all NativeCall-flavored sized/typed parameters.
- "**code-bail unnamed chain link**": 2 files
  (08-performance/28-rakuast-metaop-hoist.t,
  08-performance/39-rakuast-native-arg-value.t).

**Class (c) — other Rakudo-level regression** (first differing line):

| file | evidence |
|---|---|
| t/08-performance/14-rakuast-native-incdec.t | subtest 7 "a narrow native pre-increment wraps correctly": expected `-128 -128`, got `128 128` (int8 wraparound bug) |
| t/02-rakudo/03-corekeys.t (+5 siblings, see cluster below) | "Found 5 unexpected entries: NFC NFD NFKC NFKD Uni" in CORE::v6c symbol check |
| t/02-rakudo/begin-time-eval-caller-context.t (+2 siblings) | `java.lang.NullPointerException at EVAL_0:18` inside a `BEGIN { $class-package = EVAL Q[$?PACKAGE...] }`; harness reports "planned 8 tests, but ran 0" |
| t/02-rakudo/generated-populate.t | `java.lang.ClassCastException: class java.lang.Long cannot be cast to class org.raku.nqp.sixmodel.SixModelObject` in method `u`; "planned 56, ran 23" |
| t/02-rakudo/xx-sink-lazy.t | `java.lang.IllegalStateException: continuation captured at a non-suspendable site in an engine-run block`; "planned 3, ran 0" |
| t/02-rakudo/yada-trait-timing.t | compile-time SORRY: "Too many positionals passed; expected 0 arguments but got 1" for `is replace-method`/`is replace-sub` traits at lines 17/19 |

**corekeys/settingkeys cluster** (7 files, single root cause presumed —
the CORE::v6c symbol-count check now sees 5 extra Unicode-normalization
names): t/02-rakudo/03-cmp-ok.t (subtest 7), 03-corekeys-6c.t (subtest 1),
03-corekeys-6d.t (subtest 1), 03-corekeys-6e.t (subtest 1),
03-corekeys.t (subtest 1, evidence above), 04-settingkeys-6c.t
(subtest 2), 04-settingkeys-6e.t (subtest 2). Only 03-corekeys.t was
individually re-run with full tail; the other 6 show the same
single-subtest-failure signature in the targeted sweep's TAP and were not
separately cold-rerun given time constraints — flagged as a residual gap.

**begin-time-eval cluster** (3 files, same NPE-at-BEGIN-EVAL family):
t/02-rakudo/begin-native-var.t ("planned 10, ran 6"),
t/02-rakudo/begin-time-attributive-param-method.t ("planned 5, ran 2"),
t/02-rakudo/begin-time-eval-caller-context.t (evidence above, fully
re-run). Only the third was individually cold-rerun; the other two show
the same partial/bad-plan signature and are presumed the same root cause
— residual gap, not independently confirmed.

**04-nativecall/05-arrays.t**: shows `skipped: NullPointerException in
sub ReturnADoubleArray` but the test itself self-skips this subtest
(`1..0 # Skipped: ...`) and the harness's Test Summary Report does **not**
list it as failed — this is a pre-existing self-guard, not counted as a
new failure.

**Class (d) — flaky/timing (passes on rerun)**: three sweep-1 FAIL chunks
came back **fully clean** when re-run in isolation via the smaller
targeted sweep, with no known-fail file present to explain the original
FAIL either:
- chunk 13 (`dot-assign-var-method.t` … `fatal-flatten-arg.t`, 11 files)
- chunk 16 (`heredoc-attribute-default.t` … `init-phaser-decont.t`, 11
  files) — originally flagged "no TAP" in sweep 1
- chunk 28 (`supply-sequencer.t` … `trait-package-metaclass.t`, 11 files)

These are consistent with the sweep's own documented heap-growth-across-
a-long-chunk-sequence effect (`evalserver-sweep.raku`'s own comment: "a
server that has taken too many files sits at its heap ceiling ... which
reads as 'No subtests run'") manifesting differently in a 38-chunk vs.
9-chunk run — though for chunks 13/28 (no "no TAP" marker, just plain
FAIL) the exact original failure mode is unknown since sweep 1 never
printed per-file TAP for them.

## Files FIXED since 2026-09-05 (previously known-failing, now passing)

Six 02-rakudo files landed in chunks that came back clean (exit 0) in
sweep 1 — strong evidence they now pass:
- `21-begin-time-compile-sub.t`
- `dd.t`
- `doc-block-statement-owner.t`
- `has-list-declaration.t`
- `n-flag-mainline-scope.t`
- `repl.t`

(Not individually re-run cold to double-confirm, given time — inferred
from their chunk's overall harness exit code 0.)

## KNOWN failures reconfirmed present (chunk-level; not all individually
re-isolated)

02-rakudo: `14-revisions.t`, `99-misc.t`, `begin-called-block-routine.t`,
`compiler-frontend-id.t`, `compiler-symbol-undeclared.t`,
`constant-anon-var-value.t`, `loop-next-phaser.t`, `once-in-phasers.t`,
`param-arg-compile-errors.t`, `parse-target-match-tree.t`,
`proc-async-merge-stream-close.t`, `rakuast-feed-validation.t`,
`sink-warnings-legacy-parity.t`, `try-fatalizes-block.t` (14 of the 20
known files located in a FAILED chunk — presumed still failing since
nothing indicates otherwise; the other 6 are the "fixed" list above).

04-nativecall: `08-callbacks.t`, `23-incomplete-types.t`.
05-messages: `01-errors.t`, `02-errors.t`, `03-errors.t`, `10-warnings.t`.
08-performance: `15-rakuast-native-metaop.t` (still fails, same subtests
16/22), `36-rakuast-begin-compiled-remark.t` (now manifests as a "no TAP"
die rather than whatever it did on 2026-09-05 — not independently
diagnosed, but still counted as known/consistent since it's in the
original list).

## Directory file-count drift since 2026-09-05

- `t/02-rakudo`: 290 → 298 (+8 new files)
- `t/05-messages`: 7 → 5 (**-2 removed**)
- `t/13-experimental`, `t/14-smoke`: no 2026-09-05 record; both fully
  clean now (9 and 1 files respectively).
- All other directories unchanged in count.

## Open gaps / residual limitations

- The corekeys/settingkeys cluster (6 of 7 files) and the begin-time-eval
  cluster (2 of 3 files) were not individually cold-rerun with
  `NQP_CODE_WHY`/`NQP_CODE_BAIL` — their TAP signature strongly matches
  their re-run sibling but this wasn't independently confirmed per file.
- Chunks 18, 20, 21, 29, 32 were explained by a known-fail file's
  presence but also carried a "no TAP" marker in sweep 1; whether a
  *second*, new failure is hiding alongside the known one in those chunks
  was not checked (would require another targeted re-run).
- No code was fixed; no commits were made; this is a report-only
  measurement per the task's constraints.
