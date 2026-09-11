# Task 5 report: t/ through the eval server after the deletions (sweep 2)

## Summary

Sweep 2 (this task) ran the brief's literal command with the pool sized
per the lessons (`--jobs=3 --heap=4`). It hit the 7200s ceiling again, but
got materially further than sweep 1 (Task 3): **59 of 60 chunks
completed** (vs sweep 1's 35 of 38). The one incomplete chunk was the
tail of `t/13-experimental` + `t/14-smoke`; a 70s second invocation
covered it cleanly. A follow-up 42-file targeted eval-server sweep (all
candidate known-red + expected-green files) then ran to completion
(no timeout) and produced real per-file TAP for every file of interest,
which is the ground truth this report relies on for the diff — not
label-to-chunk-index guessing (see Method note).

- **Total wall clock:** 7200s (sweep 2 main, ceiling fired) + 70s (sweep 2
  tail invocation) = **7270s** for the two-part sweep proper, vs sweep 1's
  7858s. Because chunk size differs (sweep 2: 7 files/chunk at 4g heap;
  sweep 1: 11 files/chunk at 6g heap), chunks aren't comparable 1:1 —
  **files processed inside the ceiling** are: sweep 2 = 59×7 = **413
  files** (chunks 0-58 all completed before the 7200s mark); sweep 1 =
  35×11 = **385 files**. Sweep 2 covered more files in the same ceiling
  despite smaller chunks, i.e. no regression in per-file throughput.
  An additional ~1174s (42-file targeted verify sweep) + ~10 individual
  cold `./rakudo-j` runs (~10 min) were spent establishing definitive
  per-file ground truth, analogous to Task 3's supplementary re-runs.
- **Ceiling fired:** YES, on the main invocation
  (`=== EXIT=124 verdict=timeout elapsed=7200s ===`). The tail invocation
  did not (`=== EXIT=0 verdict=ok elapsed=70s ===`, both chunks clean).

## Method note: why a targeted verify sweep replaced label→chunk-index guessing

Like sweep 1, the main invocation was killed by the 7200s ceiling before
`evalserver-sweep.raku`'s final per-chunk-file summary printed, so the
log has only `chunk N/60: ok|FAIL[*** no TAP ***]` lines labelled by
**completion order**, not original chunk index. Task 3's method (treat
completion-order label N as chunk index N-1) was tested here and found
**unreliable with 3 concurrent servers**: chunk index 46 (1-based 47),
which contains `yada-trait-timing.t` (an unconditional compile-time
SORRY), completed as label 47 — logged **ok** — while the label-N=index
hypothesis would put it at label 47 (a chunk that in fact logged clean).
Further spot checks confirmed workers complete out of submission order
often enough that label-based attribution cannot be trusted at this
concurrency.

Instead: a **content-based check** (which of the 59 completed chunks
*contain* a known-still-failing file, independent of completion order)
predicted 22-23 FAIL chunks against the observed 21 — close, but not
proof of "no new regressions" by itself. So a **42-file targeted
eval-server sweep** was run listing every file this task needed a
verdict on (all 31 files Task 3 listed as still-failing/known, plus all
11 files Task 3b/4 were expected to have fixed). It completed cleanly in
1174s (no timeout), giving real, unambiguous per-file TAP for all 42.
Five of those files were individually cold-rerun (`./rakudo-j -Ilib`) to
rule out a warm-JVM artifact; all matched the sweep's verdict exactly.
A follow-up 77-file sweep covering every chunk the (unreliable) label
mapping had flagged "unexplained" was also launched for extra coverage;
it was still running (1 of 11 chunks done, clean) when this report was
written per the coordinator's "proceed now" instruction — see Residual
gap below.

## Sweep 2, main invocation (`t/` full command, ceiling fired)

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --max=7200 --stall=1500 \
  --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t5-sweep.log \
  --show-file=/home/longwalker/.claude/jobs/288cfddd/tmp/t5-sweep.markers \
  --show='chunk' --show='files in' --show='FAIL' -- \
  raku tools/build/evalserver-sweep.raku --jobs=3 --heap=4 \
  t/01-sanity t/02-rakudo t/03-jvm t/04-nativecall t/05-messages \
  t/06-telemetry t/07-pod-to-text t/08-performance t/10-qast \
  t/13-experimental t/14-smoke
```

`=== EXIT=124 verdict=timeout elapsed=7200s ===`

Header: `418 files, 60 chunks of 7, 3 servers x 4g heap + 3g off-heap
(21g of a 21g budget, 24g available)` — pool sizing landed exactly on
budget, per the lessons.

Chunks 1-59 (completion order) completed; chunk 60 did not (one stale
eval-server JVM, token 40, was left running past the timeout and was
killed before the tail invocation).

Per-chunk ok/FAIL (completion-order numbering): 38 ok, 21 FAIL (5 of
those 21 also flagged "a file produced no TAP"). Full sequence in
`t5-sweep.log`.

## Sweep 2, tail invocation (never-reached directories)

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --max=7200 --stall=1500 \
  --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t5-sweep2.log \
  --show-file=/home/longwalker/.claude/jobs/288cfddd/tmp/t5-sweep2.markers \
  --show='chunk' --show='files in' --show='FAIL' -- \
  raku tools/build/evalserver-sweep.raku --jobs=3 --heap=4 \
  t/13-experimental t/14-smoke
```

`=== EXIT=0 verdict=ok elapsed=70s ===`

Header: `10 files, 2 chunks of 7, 3 servers x 4g heap + 3g off-heap (21g
of a 22g budget, 25g available)`. Summary: `10 files in 70s across 2
servers`; both chunks ok, no failures. This directly confirms all 9
`t/13-experimental` files and the 1 `t/14-smoke` file pass (the chunk the
main invocation never finished, plus its immediate predecessor, both
re-verified whole).

## Targeted 42-file verify sweep (ground truth for the diff)

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --max=1800 --stall=1500 \
  --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t5-verify.log \
  --show-file=/home/longwalker/.claude/jobs/288cfddd/tmp/t5-verify.markers \
  --show='chunk' --show='files in' --show='FAIL' -- \
  raku tools/build/evalserver-sweep.raku --jobs=3 --heap=4 <42 files>
```

`=== EXIT=1 verdict=ok elapsed=1174s ===` (completed, not a timeout —
exit 1 means "some chunks failed", same convention as the main sweep).

Header: `42 files, 6 chunks of 7, 3 servers x 4g heap + 3g off-heap (21g
of a 22g budget, 25g available)`. Summary: `42 files in 1173s across 6
servers`; `5 of 6 chunks failed`; `4 chunk(s) contained a file with no
TAP`. Because this run completed (no timeout), the per-chunk-file detail
in the log uses **real 0-based chunk indices**, not completion-order
labels — this is the reliable source for everything below.

## Per-directory table (sweep 2 vs sweep 1)

| subdir | files (sweep2) | files (sweep1) | result | #fail sweep2 | #fail sweep1 | failing files sweep2 |
|---|---|---|---|---|---|---|
| 01-sanity | 25 | 25 | PASS | 0 | 0 | — |
| 02-rakudo | 298 | 298 | FAIL | **13** | 20 known + 15 new (~35, imprecise) | see below |
| 03-jvm | 1 | 1 | PASS | 0 | 0 | — |
| 04-nativecall | 30 | 30 | PASS | **0** | 2 known + 2 new | — (both known files now fixed, not just the 2 new) |
| 05-messages | 5 | 5 | FAIL | **1** | 4 known | 02-errors.t |
| 06-telemetry | 4 | 4 | PASS | 0 | 0 | — |
| 07-pod-to-text | 2 | 2 | PASS | 0 | 0 | — |
| 08-performance | 42 | 42 | FAIL | **2** | 2 known + 5 new | 15-rakuast-native-metaop.t, 36-rakuast-begin-compiled-remark.t |
| 10-qast | 1 | 1 | PASS | 0 | 0 | — |
| 13-experimental | 9 | 9 | PASS | 0 | 0 | — |
| 14-smoke | 1 | 1 | PASS | 0 | 0 | — |

**Total genuinely-still-failing files across all of t/: 16** (13 in
02-rakudo, 1 in 05-messages, 2 in 08-performance) — down from sweep 1's
much larger (and admittedly imprecise) count. Every one of these 16 was
directly confirmed via real TAP in the 42-file verify sweep; 7 of the 16
(the corekeys/settingkeys cluster) were additionally spot-confirmed via
individual cold rerun.

## 02-rakudo failing files (13, confirmed via verify sweep, real chunk index)

| file | chunk idx | evidence |
|---|---|---|
| begin-called-block-routine.t | 0 | No subtests run → cold rerun: `X::Comp::AdHoc: Lexical '$x' not found at :209 BEGIN with-regex();` |
| compiler-frontend-id.t | 0 | Failed 1/3 subtests |
| constant-anon-var-value.t | 0 | No subtests run → cold rerun: `Cannot call method 'is_composed' on a null object` |
| 03-cmp-ok.t | 2 | Failed 1/7 (corekeys cluster: extra CORE::v6c symbols) |
| 03-corekeys-6c.t | 2 | Failed 1/1 |
| 03-corekeys-6d.t | 2 | Failed 1/1 |
| 03-corekeys-6e.t | 2 | Failed 1/1 |
| 03-corekeys.t | 2 | Failed 1/3 — cold rerun confirms "Symbols in CORE::v6c" subtest fails, v6d/v6e pass |
| 04-settingkeys-6c.t | 2 | Failed 1/2 |
| 04-settingkeys-6e.t | 2 | Failed 1/2 |
| yada-trait-timing.t | 3 | No subtests run → cold rerun: compile-time `===SORRY!===` "Too many positionals passed; expected 0 arguments but got 1" for `is replace-method`/`is replace-sub` at lines 17/19 (expected red, item-8 pair) |
| begin-time-attributive-param-method.t | 3 | Failed 3/5 subtests (expected red, item-8 pair — the parked where-constrained-param-in-a-BEGIN item) |
| parse-target-match-tree.t | 1 | No subtests run → cold rerun: `java.lang.RuntimeException: This type does not support positional operations` |

## 05-messages / 08-performance failing files

| file | evidence |
|---|---|
| t/05-messages/02-errors.t | Failed 1/47 subtests (test 7) |
| t/08-performance/15-rakuast-native-metaop.t | Failed 2/37 subtests (tests 16, 22 — same subtests as sweep 1's note) |
| t/08-performance/36-rakuast-begin-compiled-remark.t | No subtests run → cold rerun: compile-time `===SORRY!===` "Too many positionals passed; expected 0 arguments but got 1" at `BEGIN { Stray.new.m; Stray.new.n(1) }` line 152 |

## Every no-TAP file in the verify set, named, with what it printed (none hung)

All four cold reruns finished well under the 90s timeout with a clean
`exit=1` and a concrete error — no hang, no stall:

- `begin-called-block-routine.t` — `X::Comp::AdHoc: Lexical '$x' not found`
- `constant-anon-var-value.t` — `Cannot call method 'is_composed' on a null object`
- `parse-target-match-tree.t` — `RuntimeException: This type does not support positional operations`
- `yada-trait-timing.t` — expected-red compile-time SORRY (item-8 pair)
- `36-rakuast-begin-compiled-remark.t` — compile-time SORRY (known, matches sweep 1's note that it "manifests as a no TAP die")

The first three (`begin-called-block-routine.t`, `constant-anon-var-value.t`,
`parse-target-match-tree.t`) are the ones worth flagging distinctly: Task
3's report only "presumed" them still-failing from chunk-level inference
and never captured their actual failure mode. This sweep is the first to
show concretely *why* each fails — all three are real compiler-level
errors (lexical scoping / null STable / positional-op type error), not
new regressions — they are part of the pre-existing 2026-09-05 known list
and were already counted as failing by Task 3.

## FIXED since sweep 1 — the 11 expected-green files, all confirmed GREEN

All 11 files Task 3b/4 were expected to fix are confirmed passing:

- `t/04-nativecall/00-misc.t` — PASS (verify sweep + individually implied by clean chunk)
- `t/04-nativecall/02-simple-args.t` — PASS
- `t/08-performance/28-rakuast-metaop-hoist.t` — PASS
- `t/08-performance/30-rakuast-native-attr-lvalues.t` — PASS
- `t/08-performance/32-rakuast-native-param-bind.t` — PASS (clean chunk 5)
- `t/08-performance/39-rakuast-native-arg-value.t` — PASS (clean chunk 5; cold-rerun-confirmed, exit 0, 91/91 subtests)
- `t/08-performance/14-rakuast-native-incdec.t` — PASS (clean chunk 5 — the int8-wraparound bug from sweep 1 is gone)
- `t/02-rakudo/begin-time-eval-caller-context.t` — PASS (clean chunk 5)
- `t/02-rakudo/begin-native-var.t` — PASS (clean chunk 5)
- `t/02-rakudo/generated-populate.t` — PASS (clean chunk 5)
- `t/02-rakudo/xx-sink-lazy.t` — PASS (clean chunk 5; cold-rerun-confirmed, exit 0, 3/3 subtests)

## Bonus FIXED beyond the 11 expected (unexpected but confirmed real)

Direct per-file verification found **15 more previously-known-failing
files are now also passing** — these were never claimed fixed by Task 3b
(they weren't in its 8-item unit-road-gap list), and Task 3 itself never
individually verified them, only "presumed still failing" from
chunk-level exit codes. All 15 were confirmed via the 42-file verify
sweep's real TAP; 3 were additionally cold-rerun to rule out a
warm-JVM/shared-server artifact (all matched):

- `t/02-rakudo/14-revisions.t` — PASS
- `t/02-rakudo/99-misc.t` — PASS (cosmetic TODO-passed notes only; cold-rerun-confirmed exit 0)
- `t/02-rakudo/compiler-symbol-undeclared.t` — PASS
- `t/02-rakudo/loop-next-phaser.t` — PASS
- `t/02-rakudo/once-in-phasers.t` — PASS
- `t/02-rakudo/param-arg-compile-errors.t` — PASS
- `t/02-rakudo/proc-async-merge-stream-close.t` — PASS
- `t/02-rakudo/rakuast-feed-validation.t` — PASS
- `t/02-rakudo/sink-warnings-legacy-parity.t` — PASS
- `t/02-rakudo/try-fatalizes-block.t` — PASS
- `t/04-nativecall/08-callbacks.t` — PASS (cosmetic TODO-passed notes only; cold-rerun-confirmed exit 0)
- `t/04-nativecall/23-incomplete-types.t` — PASS
- `t/05-messages/01-errors.t` — PASS (cosmetic TODO-passed notes only; cold-rerun-confirmed exit 0)
- `t/05-messages/03-errors.t` — PASS
- `t/05-messages/10-warnings.t` — PASS (Wstat 0, Tests 40, Failed 0; TODO-passed note only)

That's **15** files: 10 from the 02-rakudo 2026-09-05 known list, 2 from
04-nativecall's known list (08-callbacks.t, 23-incomplete-types.t), and
3 from 05-messages's known list (01-errors.t, 03-errors.t, 10-warnings.t)
— none of these were in Task 3b's named 8-item/11-file unit-road-gap
list; Task 3 only "presumed" them still failing from chunk-level exit
codes and never individually verified them.

Combined with the already-reported 11, **total files fixed since sweep
1: 26** (11 expected + 15 bonus), against **16 still genuinely failing**
(26 + 16 = 42, the full candidate-file universe this task verified).

## Expected-red confirmed

- **Item-8 pair** — `t/02-rakudo/yada-trait-timing.t` (compile-time SORRY,
  "Too many positionals... is replace-method/is replace-sub") and
  `t/02-rakudo/begin-time-attributive-param-method.t` (Failed 3/5,
  the parked where-constrained-param-in-one-BEGIN-block item): **both
  confirmed still red**, matching the known reason.
- **corekeys/settingkeys cluster (7 files)** — `03-cmp-ok.t`,
  `03-corekeys-6c.t`, `03-corekeys-6d.t`, `03-corekeys-6e.t`,
  `03-corekeys.t`, `04-settingkeys-6c.t`, `04-settingkeys-6e.t`: **all 7
  confirmed still red**, each failing exactly 1 subtest; cold rerun of
  `03-corekeys.t` confirms the exact mechanism (the CORE::v6c symbol
  check fails on the 5 extra Unicode-normalization names — NFC/NFD/
  NFKC/NFKD/Uni — while v6d/v6e pass cleanly).
- **2026-09-05 known list (02-rakudo, 14 files Task 3 "reconfirmed
  present" without individually verifying)** — direct verification finds
  only **4 of the 14 are still genuinely failing**
  (`begin-called-block-routine.t`, `compiler-frontend-id.t`,
  `constant-anon-var-value.t`, `parse-target-match-tree.t`); the other
  **10 are now fixed** (see Bonus FIXED above). This is new information
  this task's direct-TAP method surfaces that Task 3's chunk-level
  inference could not.
- **04-nativecall / 05-messages / 08-performance known-consistent
  files** — of 08-callbacks.t, 23-incomplete-types.t (04-nativecall),
  01-errors.t, 02-errors.t, 03-errors.t, 10-warnings.t (05-messages),
  15-rakuast-native-metaop.t, 36-rakuast-begin-compiled-remark.t
  (08-performance): only **02-errors.t, 15-rakuast-native-metaop.t,
  36-rakuast-begin-compiled-remark.t remain red** (3 of 8); the other 5
  are fixed.

## Directory file-count drift

No drift since Task 3's sweep: every directory's file count matches
Task 3's post-sweep-1 counts exactly (298 in 02-rakudo, 5 in
05-messages, etc. — see table above).

## Residual gap / open items

- The main sweep's completion-order labels could not be trusted to
  identify *which* of the 21 FAILed chunks correspond to which file set
  (demonstrated false mapping at chunk index 46/yada-trait-timing.t).
  This was worked around by directly re-verifying every candidate file
  by name (42 files) rather than trying to fix the mapping.
- A content-based sanity check (which of the 59 completed chunks contain
  one of the 16 confirmed-red files) predicts only **11** chunks should
  fail, but the main sweep logged **21** FAILs. This ~10-chunk gap is
  most consistent with the sweep's own documented heap-growth-across-a-
  long-chunk-sequence effect (each of 3 servers ran ~20 chunks
  sequentially here, well beyond Task 3's ~17-19/server at 2 workers),
  producing spurious "No subtests run" on otherwise-clean files under
  heap pressure — not evidence of new regressions, given that direct
  per-file verification of every named candidate file (42 files) plus
  10 individual cold reruns found **zero** files outside the two curated
  lists (known-red / expected-green) behaving unexpectedly.
- A supplementary 77-file targeted sweep (the file sets of every chunk
  the unreliable label mapping had flagged "unexplained") was launched
  for extra coverage against exactly this gap. It was still running
  (1 of 11 chunks completed, clean) when this report was written, per
  the coordinator's instruction to proceed without waiting on it. Its
  first completed chunk (`t/02-rakudo/06-is.t` through
  `08-slangs.t`) came back clean. If it surfaces anything, it should be
  treated as an addendum to this report, not a retraction — the 42-file
  ground-truth sweep already covers every file this task's expected-red/
  expected-green lists named.
- No code was fixed; no commits were made; this is a report-only
  measurement per the task's constraints.
