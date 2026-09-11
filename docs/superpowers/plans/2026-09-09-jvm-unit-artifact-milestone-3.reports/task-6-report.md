# Task 6 report: the docs and their commit (Steps 1-2)

Status: **DONE**. One commit in the rakudo tree: `5d1a3845f0` (docs only;
no nqp edits, no code, no builds). Steps 3-5 (rebase, push, handoff
reminder) are the controller's, untouched.

## Files changed

| file | change |
|---|---|
| `docs/jvm-truffle-only-plan.md` | Position table: item 4's "Scheduled after milestone 3" sentence becomes "milestone 3 done 2026-09-10; item 4 is next after milestone 4"; item 5 gains a compact milestone-3 DONE clause (defaults, knob gone, 16 Rakudo + 11 nqp jars `unit.meta`-only); item 6 gains the full milestone-3 DONE paragraph (four pieces a-d with their nqp/rakudo hashes, the gate numbers, both sweeps, the parked shape, the carried gaps, no t/spec); item 7 gains "Rakudo shapes DONE 2026-09-10" with the parked BEGIN+where shape; item 8 becomes "compiler-side DONE" with the runtime writer/loaders named as milestone 4. Other rows untouched |
| `docs/superpowers/specs/2026-09-09-jvm-unit-artifact-design.md` | Milestones: item 3 gains a DONE section (what shipped, the gate as three bullet lines, the four deviations one clause each by number, the two sweeps' wall clocks, no t/spec, the parked item 8 and the resume-value gap); item 4 gains the runtime-side writer/loader deletion list and milestone 4's full entry list (stage0, jast2bc/`compilejast`/define branch/`MemoryClassLoader`/sidecar reader/`JarFileClassLoader`, the JAST method carrier, the per-block stub emission, `setup_blv`, the four `NQP_UNIT` comments, the t/nqp/123+124 headers, the interop adaptors), plus t/spec inherited from deviation 2 |
| `AGENTS.md` | the `RAKUDO_RAKUAST=1` paragraph: the Makefile-exports-the-knobs sentence becomes "on by default since 2026-09-10 (`NQP_CODE_RUN=0` / `NQP_CODE_PRECOMP=0` opt out; no class road left in the compiler), a bare `make` IS the engine build, every jar a unit artifact entered through `UnitMain`". Rest of the paragraph kept. `CLAUDE.md` itself untouched (symlink) |
| `docs/superpowers/plans/2026-09-09-jvm-unit-artifact-milestone-3.ledger.md` | the `## Task log` section of `progress.md` appended verbatim (43 lines), after the existing header, pre-flight table and rulings bullets |
| `docs/superpowers/plans/2026-09-09-jvm-unit-artifact-milestone-3.reports/` | created; `task-1..5-report.md`, `task-3b-report.md` and `task-1..6-brief.md` + `task-3b-brief.md` copied (13 files). Review packages and diffs deliberately not copied |
| `docs/jvm-eval-server.md` | one block under the sweep section: the t/ wall clocks (7270 s on 3 x 4 GB, 7858 s on 2 x 6 GB, ~418 files, both ceilings + their second invocations), the `chunk = heap x 15 / 8` rule with its 7-vs-11 consequence, `--jobs=3 --heap=4` as the pool this box fits, and why no-TAP chunks are the tail cost (dying file loses the chunk's per-file report; declined server burns the 120 s token wait) plus the lost-attribution consequence of a timed-out sweep |

## Disagreements resolved (both toward the reports, both stated in the commit message)

1. **The 120 s token timeout is not a per-file cost.** The task framing
   said "no-TAP files cost the 120 s token timeout each and were the main
   tail cost". No report measures that. The 120 s is `t/harness5:165`
   waiting for its server's token file, and it fires when the server
   guard declines a server (documented at `tools/build/evalserver-sweep.raku:58`,
   2026-09-08). A file that dies before emitting TAP costs its chunk's
   per-file detail, not 120 s. The eval-server paragraph states the two
   mechanisms separately rather than merging them.
2. **The ledger twin keeps its rulings bullets.** The instruction was to
   replace the twin's body after the pre-flight table with the task log.
   Its `## Rulings, deviations, deferred minors` bullets (torn-frame
   LEAVE, the interop adaptors, deferred anonymous-block naming) appear
   nowhere in the task log, so they were kept and the task log appended
   after them; the twin is a superset of what was asked for, not a
   replacement that loses record.

## Numbers used, and where each came from

- Gate and timing baseline (nqp clean 222 s; make 1154 s from the top
  with rakudo.jar 171 s / v6c 200 s / CORE.c 594-1069 s = 475 s / CORE.d
  1069 s / CORE.e 1096 s; t/nqp 118/118; sanity 25/25 in 161 s; precomp
  14/14; t/03-jvm + t/10-qast 2/2; 16 + 11 jars meta-only; CORE.c 4
  nested units / 8 `nested/` entries): `task-4-report.md`, matching the
  ledger line for Task 4.
- Sweep 1 7858 s over two invocations on two 6 GB servers, 11-file
  chunks, 385 files inside the ceiling: `task-3-report.md`.
- Sweep 2 7270 s (7200 s ceiling after 59 of 60 chunks on three 4 GB
  servers + a 70 s tail), 7-file chunks, 413 files inside the ceiling,
  no new failures, 26 fixed since sweep 1: `task-5-report.md`.
- ~418 files in t/: the per-directory table in `task-5-report.md`
  (25+298+1+30+5+4+2+42+1+9+1), consistent with Task 3's "all 418 files".
- Chunk rule `max(3, heap x 15 / 8)`: read from
  `tools/build/evalserver-sweep.raku:67`, and it reproduces both sweeps'
  observed 7- and 11-file chunks.
- Hashes: rakudo `5ae25a8d3c`..`a22eb40b73` (+ this commit `5d1a3845f0`),
  nqp `da1f5088a`..`30e849e3c`, per-task heads `c872c83af`,
  `388173781`..`e5f2b3840`, `171d37508`..`8bab02391`, rakudo
  `08a997dc2b`; both tree HEADs verified with `git log` in each tree.

## Concerns

- The plan-doc rows 6 and 7 are now long even by this table's standards;
  row 6 is a paragraph inside a table cell. It matches the existing
  milestone-1/2 style, so it was left as prose rather than promoted to a
  section.
- The eval-server block's "no-TAP chunks are the tail cost" is a
  mechanism statement, not a measurement: no report separates the
  wall-clock share. It is written as a mechanism for that reason.
- Milestone 4's entry list now lives in three places (the spec's item 4,
  the plan doc's item 8, this ledger); they were written from the same
  list but will drift if one is edited alone.
