# SDD ledger — plan: docs/superpowers/plans/2026-09-15-jvm-milestone-7-first-execution-phase-c.md

Spec: docs/superpowers/specs/2026-09-13-jvm-milestone-7-first-execution-design.md
(rakudo 83375a77ae), "Phase C: the persisted miss", "The close", Gates item 6.

BASE before Task 1: rakudo 9bfa3fe86c, nqp b51c1a0db (Phase B's close; the nine
v2 stage0 jars are an uncommitted working-tree change in nqp/, user rule). Row
`b` is the baseline: cold rakudo-e 2.461 s, cold nqp-e 1.160 s, misses 5667,
hits 100711, warm t/01-sanity 50 s.

Claude-Session trailer: the writing session's URL is not known to it; commits
carry the Co-Authored-By trailer only until the executing session records its
URL here (user rule: never fabricate).

Model policy (user rule 2026-09-11): subagents on Opus; Fable only after
erroneous output; escalations logged here.

The plan's fifteen rulings (open to the user's veto until Task 3 writes the schema):
1. No site identity and no descriptor index in the slot; the address is the identity, the descriptor travels inline per program.
2. References are PRef(handle, index, kind 0 obj / 1 code / 2 STable); HLL by name, syscall by name, dispatcher by id; unresolvable -> not persisted / dropped.
3. kotlinx sealed hierarchies with short @SerialNames through UnitCodec (+ Double as raw long bits).
4. The training process rewrites the artifacts itself at exit (UnitDispatchWriter, tmp + atomic rename); NQP_DISPATCH_RECORD=all or store-name prefixes.
5. Rakudo's training run rewrites nqp's lib jars too (a third of the cold run's sites are there); slots merge (restored + new).
6. Gradle trains a COPY (build/jvm/stage2-trained) and syncLib takes it; jBootstrapFiles keeps the untrained stage2, so stage0 stays empty-tabled.
7. Programs merge per slot, deduplicated by DispatchDump text, capped at MAX_PROGRAMS.
8. Restore at first miss (fallback, before record); `misses` keeps its meaning; the claim is on `recorded=` (C0 predicts ~5023 -> <500), with restored=/restoredSites=/dropped=.
9. Verify compares applicable persisted programs only (same shape, guards pass); unseen is not a mismatch; the gate is zero mismatches over the nqp suite + t/01-sanity.
10. The five `perl6` units need nothing (namespace = store name + unit id).
11. Compression of records/programs is presented with numbers at the close, not built (clock-negative by construction; runtime-first rule).
12. Bounds hardening lands with the writer (absolute slot vs dispatchSlotCount, negative offsets, per-program windows at open).
13. Runtime-made sites counted: DispatchBootstrap.created -> `sitesAll=`.
14. The deferred rakudo rebase is Task 2, gated by make + t/01-sanity, before any Phase C build.
15. The whole-t/ close run goes through watched-run as a plain background job with a 6 GB heap; a second kill by the low-memory guard = not gathered, user decides.

## C0 (2026-09-15, before Task 1)

Instrument NQP_DISPATCH_DUMP (DispatchDump.kt) + tools/build/dispatch-dump-diff.raku.
Two cold `rakudo-j -e ''` on rakudo 9bfa3fe86c / nqp b51c1a0db: 4604 programs at
4297 sites (2135 parsed-never-dispatched, 4 anonymous), 4554 persistable (98.9 %),
dumps byte-identical across the runs, misses 5023 (stats: hits 79758, sites 6427,
anon 5). Unpersistable: 40 CodeRef-nosc (35 raku-assign outcomes, 5 KnowHOW
meta-methods), 5 RakuObject4-nosc, 4 VMHashInstance-nosc (a runtime method cache
as a lookup table), 1 VMArrayInstance-notroot (@!dispatchees). Five identities
shared by two live sites each. Per-jar split in the plan. Dumps and table:
~/.claude/jobs/ba3ab3a7/tmp/c0/.

## Rig rows

| tag | rakudo hash | nqp hash | cold rakudo-e (s) | cold nqp-e (s) | misses | hits | warm (s) | new red | verdict |
|---|---|---|---|---|---|---|---|---|---|
| b | 107eca63a3 | 318558c2d | 2.461 | 1.160 | 5667 | 100711 | 50/sanity | none | Phase B close, the baseline |

## Log
