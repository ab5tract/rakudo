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
| c | 79829d402e | f5c5bc8fa | 2.272 | 1.203 | 4931 | 35512 | 63/sanity | none | Phase C close, trained build; restored=4470 recorded=849 sitesAll=7569 dropped=37 (best cold rakudo-e); nqp restored=1644 recorded=257 |
| close | 6217a89e61 | a837bf1bb | 2.247 | 1.198 | 4931 | 35512 | 59/sanity | none | milestone close, fix-wave build; restored=4470 recorded=849 sitesAll=7569 dropped=37 staleSchema=0 (best cold rakudo-e); nqp restored=1644 recorded=257 staleSchema=0 |

## Hashes before and after the handoff rebase (Task 9, 2026-09-16)

The phase was measured on rakudo `79829d402e` / nqp `f5c5bc8fa`, and every
document names those. The handoff rebase at the close (rakudo onto
`origin/main` `af3df50dba`, one upstream commit, no conflict; nqp onto
`upstream/main` `e31676e5b`, one upstream commit, no conflict) rewrote them:

| commit | before | after |
|---|---|---|
| rakudo: plan, ledger, C0 findings | b114238897 | 8863808d86 |
| rakudo: Makefile training stamp (the measured tree) | 79829d402e | 5b51570903 |
| rakudo: this close's docs | 62b2b5b008 | 165c477f2b |
| nqp: DispatchDump (C0) | 5f46163d2 | 35e4f734a |
| nqp: schema + DispatchSlotCodec | e27a795d8 | 936e57fae |
| nqp: consumer + modes + counters | 5fd74d9b6 | 3a4082327 |
| nqp: recorder + UnitDispatchWriter | 3d0b54fa4 | c17218e16 |
| nqp: verify by outcome + log + drop reasons | d3e602917 | a1bdba778 |
| nqp: gradle training (the measured tree) | f5c5bc8fa | e3c800371 |

Trees are identical across the rewrite; only the two upstream commits are
new. The nine v2 stage0 jars were stashed under the tag
`stage0-v2-phase-c-task9` for the nqp rebase and restored byte for byte
(md5 verified, stash dropped); they remain uncommitted (user rule).

## Log
Task 2 (2026-09-15): rakudo rebased onto origin/main -> b114238897 (214 commits over 48 upstream; one conflict, src/Raku/ast/signature.rakumod: upstream's `$definite` derivation (syntactic :D/:U or IMPL-CAPTURE-DEFINITE) kept, our `!$definedness-done &&` added to its condition). Gate: make 869 s wall, t/01-sanity 25/25 in 62 s. Pushed --force-with-lease to ab5tract. nqp upstream/main 0 new commits. Note: the worktree's 3rdparty/nqp-configure has a dangling gitdir pointer; `git rebase --continue` needs `-c diff.ignoreSubmodules=all -c status.submoduleSummary=false`.
Task 3 (2026-09-15): nqp 18310f0a2 (DispatchSlot schema + DispatchSlotCodec + UnitCodec Double + DispatchDump on the codec's addressing), 40/40 runtime tests. Review: approved; one Important finding -> Ruling 16: HLL guards persist as (name, compiler-side) and realise through a non-creating lookup (GlobalContext.findHLLConfig), because a type's hllOwner comes from whichever of the two config maps was current at deserialize, and the guard compares identity. Cost if wrong: a dead/dropped HLL-guarded program, never a wrong answer.
Task 3 close: nqp e27a795d8 (amended: HLL guard as (name, compilerSide), GlobalContext.findHLLConfig, trailer), 41/41; re-review clean.
Task 4 (2026-09-15): nqp 5fd74d9b6 — DispatchCallSite carries unitNamespace/programIndex/ordinal/restored/verifyPrograms; DispatchPersist (NQP_DISPATCH_PERSIST on/off/verify, namespace->store registry, restore, verify, counters); the consumer hook in Dispatch.fallback; EngineSite(csd, ProgramIdentity, ordinal); UnitStore.entryPrefix/absoluteSlot; stats line gains sitesAll= restored= restoredSites= dropped= recorded=. 43/43 tests. Smoke on the rebased build (slots empty): misses 5056, sites 6522, sitesAll 6596 (74 runtime-made sites), recorded 4723; verify: matched 0 mismatched 0 unseen 4606. Review approved; one fix round (a test over verify's three outcomes). Deferred minors in the SDD ledger (.superpowers/sdd/<plan>/progress.md): unknown NQP_DISPATCH_PERSIST values mean on; racing first misses may install duplicates; restored= also counts in verify mode; counters are process-wide (not reset per eval-server run).
Task 5 (2026-09-15): nqp 3d0b54fa4 — UnitDispatchWriter.rewrite (index slot rows repointed, .dispatch rebuilt, every other entry copied byte for byte, tmp + atomic rename); DispatchPersist.recordAtExit (NQP_DISPATCH_RECORD=all|prefixes; merge per slot by describe text, cap MAX_PROGRAMS, all-unpersistable slots untouched; marker `dispatch-record: wrote`); UnitStore init checks every program's slot window; UnitImageWriter.put internal. 45/45 tests. Review approved, no fix round; deferred minors in the SDD ledger (MAGIC/VERSION unchecked in patch, empty named slot silent, fixed .tmp name, cap-dropped programs uncounted on the marker).
Task 6 (2026-09-16, first pass): training by hand works. Cold rakudo -e '' after training (one run, stats on): recorded 4723 -> 193, restored 4477 at 4195 sites, dropped 37, hits 80298 -> 13292 (the dispatcher programs no longer run to record), wall 1.943 s single run. nqp: recorded 1766 -> 87. unit.dispatch sizes: CORE.c 284060 B (+0.5 %), QAST.jar 489289 B (jar 750 KB -> 1.24 MB), v6c 386486 B. t/01-sanity default 25/25 in 40 s. Verify was NOT clean (4 cold rakudo, 8 cold nqp, 313 warm mismatches), all at polymorphic lang-meth-call sites where the dispatcher records a type-guarded form before a class publishes its method cache and a cache-lookup form after, and verify mode itself (not installing) makes the site re-record after the cache exists.
  Ruling 17: verify compares by evaluated outcome after text (same callee object / syscall / value and the same evaluated capture on the recorded call's args); counted `byOutcome`; the gate is mismatched=0. Cost if wrong: a program with the right outcome on the training call but too-weak guards passes verify -- the invariant replay already rests on.
  Ruling 18: NQP_DISPATCH_VERIFY_LOG=<path> routes verify lines to a file ([pid]-prefixed); stderr otherwise. Ruling 19: NQP_DISPATCH_PERSIST_TRACE=1 names each dropped program's reason. Ruling 20: a slot rewrite carries restored ∪ new minus unresolved (the ~1.3 % erosion of nqp's slots under Rakudo's training), accepted pending the drop reasons.
  Landed as nqp d3e602917 (46/46 tests); cold rakudo verify then: matched 4468 byOutcome 4 mismatched 0 unseen 720.
Task 6 close (2026-09-16): re-run on nqp d3e602917 — verify mismatched 0 everywhere (nqp cold matched 1658 byOutcome 8 unseen 62; rakudo cold matched 4475 byOutcome 4 unseen 127; warm t/01-sanity matched 117490 byOutcome 327 unseen 73893 over 2 processes); t/01-sanity 25/25 under verify (43 s) and default (42 s). Drops are all `no SC <handle>` for 5 handles that exist in no jar (SCs made later in the run or per compile), 37 rakudo / 30 nqp, ~0.8 % of installed programs. Ruling 20 confirmed.
Task 7 (2026-09-16): nqp f5c5bc8fa (gradle: stage2Trained Sync -> trainDispatch JavaExec with NQP_DISPATCH_RECORD=all on the copy, marker dispatch-trained.txt, syncLib from the copy; jBootstrapFiles keeps the untrained stage2), rakudo 79829d402e (Makefile.in: stamp target after rakudo.jar + the three settings runs the trivial program with NQP_DISPATCH_RECORD=all, log + exit test + grep marker, `touch -r` normalises the rewritten artifacts' mtimes so a second make is a no-op; the runner depends on the stamp). Gate, default mode: clean buildJvm 218 s; nqp suite 155/155 196 s; make clean+make 883 s (Training once; CORE.c parse 221 s, stages 282 s); t/01-sanity 25/25 55 s; cold stats restored 4475 recorded 195. Review approved; Ruling 21 (training reproduced up to ~1 % run-to-run variation; verify is the net), Ruling 22 (post-make lib jars get the default-mode nqp suite); fix round: the training line no longer masks the runner's exit through tee.
Task 8 (2026-09-16): verify gate nqp suite 155/155 204 s (11 processes: matched 271378 byOutcome 1309 mismatched 0 unseen 116617), t/01-sanity 25/25 51 s (matched 117441 byOutcome 327 mismatched 0 unseen 73941), zero MISMATCH blocks; off gate 155/155 201 s + 25/25 49 s, identical to default; default-mode nqp suite on the post-make lib jars 155/155 206 s.
Task 9 (2026-09-16): rig row `c` above (5 cold runs each, `--warm=proxy`, nothing else running, no NQP_DISPATCH_RECORD in the environment); m7-rig's `parse-cold` now also captures `recorded=`/`restored=` (optional, so older captures still parse) and `cold-summary` prints them, with the row line unchanged so the series stays comparable. Docs written: findings "Milestone 7, Phase C" (b) the 22 rulings as landed, (c) the numbers, (d) the gates with clocks, (e) sizes + the compression question for the user, (f) open items and deferred minors; `docs/jvm-unit-lazy-loading.md` "The dispatch table" rewritten for a filled table + the Diagnostics list; the spec's "Phase C: closed"; the position doc. Commits rakudo 62b2b5b008 (docs) then 637b468183 (the hash mapping above). Handoff rebase: rakudo onto origin/main af3df50dba and nqp onto upstream/main e31676e5b, one upstream commit each, NO conflict; both pushed --force-with-lease to ab5tract (the nqp branch was still at Phase B's b51c1a0db before this push). Open item recorded in the findings: the warm proxy clock reads 63 s against row b's 50 s while the harness5 clock of the same directory read 55/51/49 s in Tasks 7-8 -- single samples, not re-run (user rule). Remaining: Task 10, the milestone close.
Final whole-branch review (2026-09-16): "ready with fixes" — 0 Critical, 5 Important: no slot schema version + the training stamp ignored runtime-jar rebuilds; no error containment in the exit-hook recorder (a half-trained build could stay green); NQP_DISPATCH_RECORD=all could rewrite the uncommitted stage0 jars; the writer's moved-unnamed-slot branch untested; overlapping gradle outputs. Rulings 23-28: the moved-slot test is mandatory; the recorder contains every throwable and ends with `dispatch-record: done ...` (both build markers require it and refuse `FAILED`); DispatchSlot carries a leading SCHEMA int (1), a mismatch reads as an empty slot (`staleSchema=`), and the stamp depends on $(RUNTIME_JAR)/$(NQP_RUNTIME_JAR); paths under src/vm/jvm/stage0 are refused; the gradle marker moved out of the synced dir and both stage2Trained and trainDispatch are explicitly always out of date. Fix wave: nqp a837bf1bb, rakudo 6217a89e61 (50/50 tests; clean buildJvm 223 s, done 9 paths / 1683 slots / 0 failed; repeat build 1 s). Re-review clean. The close (Task 10) measures rakudo 6217a89e61 / nqp a837bf1bb.
Fix wave (2026-09-16, from the final whole-branch review: 0 Critical, 5 Important, 12 Minor): nqp a837bf1bb, rakudo 6217a89e61 -- rulings 23-28 (moved-slot test mandatory; recorder containment + `dispatch-record: FAILED`/`done` with both build markers requiring them; DispatchSlot SCHEMA=1 + staleSchema= counter + TRAIN_STAMP depending on the runtime jars; the recorder refuses src/vm/jvm/stage0; the gradle marker out of the synced dir with the trained jars as declared outputs; stage2Trained also upToDateWhen{false}). 50/50 runtime tests; clean buildJvm 223 s (`done 9 paths, 1683 slots, 1711 programs, 41 unpersistable, 0 failed`); repeat buildJvm 1 s, byte-identical retrain.
Task 10 (2026-09-16), the milestone close, on rakudo 6217a89e61 / nqp a837bf1bb. Gates WITH clocks: Configure --gen-nqp 4.3 s (`done 9 paths, 1683 slots, 1711 programs, 41 unpersistable, 0 failed`); full make 888 s exit 0, `+++ Training` ONCE, blib/.dispatch-train.log ends `done 21 paths, 4282 slots, 4584 programs, 50 unpersistable, 0 failed` with no FAILED and blib/.dispatch-trained present; v6c 375 s; CORE.c 296 s (parse 223.037 / optimize 22.040 / qast 16.729 / unit 20.701, stage sum 282.5); t/01-sanity default 25/25 in 57 s; cold `-e ''` stats restored=4475 restoredSites=4193 dropped=37 staleSchema=0 recorded=195. Verify gate RE-TAKEN (the slot schema changed after Task 8): nqp suite 155/155 208 s over 11 processes (matched 271378, byOutcome 1309, mismatched=0, unseen 116617, zero MISMATCH blocks), t/01-sanity 25/25 51 s (matched 117438, byOutcome 327, mismatched=0). Rig row `close` above (marker `m7-rig: DONE tag=close`); every dispatch counter identical to row `c`, only the walls moved.
Task 10, whole `t/`: **NOT GATHERED** (user rule: a failed benchmark is not re-run). 482 files, one warm 6 GB server, `--jobs=1 --chunk=*` through watched-run as a background job, 3361 s, exit 1 -- but the server stopped producing TAP at file 310 of 482 (`t/02-rakudo/thread-unhandled-exception.t`) and the remaining 172 all reported `Tests: 0` / `Non-zero exit status: 1` / `No plan found in TAP output`. NOT the low-memory guard of ruling 15 (banner printed, 310 files ran, MemAvailable 24.4 -> 15.6 -> 24.4 GB, no Killed, no OutOfMemory, empty dmesg, the sweep ran to completion) and NOT any single file (the four around the break pass together on a fresh server: 4 files, 81 tests, PASS, 66 s; `t/12-rakuast/block.rakutest` and `t/04-nativecall/01-argless.t` pass directly). Cause: the single-server sweep wedging after ~285 files of t/02-rakudo. Evidence written up in docs/jvm-full-suite-run-2026-09-16.md. The 3361 s is a truncated run, not a fast one (10.8 s/file over the 310 that ran, against 11.9 s/file over the 2026-09-13 427-file run), so it is NOT comparable to 5078 s.
Task 10, the red diff over the 310 files that did run: 20 of the 24 baseline reds red, 4 green (15-gh_1202.t, 16-begin-time-eval.t, native-argument-snapshot.t, try-statement-backtrace-frame.t), the remaining baseline entries not reached. **ONE NEW RED: t/02-rakudo/closure-static-clone.t, test 5 (".clone through the method road still works", expected 'documented', got '')**. Reproduces under `./rakudo-j -Ilib` outside any harness AND with `NQP_DISPATCH_PERSIST=off`, so Phase C is exonerated. The test was added by A6' itself (rakudo d6d5a2ea7e, 2026-09-14), so the regression sits between that commit and the close -- Phase B's artifact rework or one of the two upstream rebases. Unbisected (each step is a ~900 s build); recorded as an open item of the close.

## Hashes before and after the close's rebase (Task 10, 2026-09-16)

The close was measured on rakudo `6217a89e61` / nqp `a837bf1bb`, and every
document names those. The close's rebase (rakudo onto `origin/main`
`67f2e3bcff`, **two** upstream commits, 219 replayed, NO conflict) rewrote
the rakudo side once more. nqp was not rebased (`upstream/main` had nothing
new), so **nqp `a837bf1bb` is still the tip and the docs' nqp hashes need no
mapping**.

| rakudo commit | before | after |
|---|---|---|
| Phase C: plan, ledger, C0 findings | 8863808d86 | 661d3390ae |
| Phase C: Makefile training stamp | 5b51570903 | cd10f67fdb |
| Phase C: close docs | 165c477f2b | a42e17fb18 |
| Phase C: the handoff hash mapping | a896b743e0 | 4204a9691c |
| **the fix wave (the MEASURED tree)** | **6217a89e61** | **d7a9257d50** |
| the close's docs | 5c3a4a38d1 | b4cb5c8344 |

Trees are identical across the rewrite; only the two upstream commits are
new. The nine v2 stage0 jars were never touched (the nqp tree was not
rebased) and remain uncommitted (user rule).
