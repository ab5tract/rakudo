## Task 10: The milestone 7 close (spec "The close")

- [ ] **Step 1: The rig once more only if the final build differs** from
  row `c`'s (it should not).
- [ ] **Step 2: Whole `t/` once on one warm server**:
  `raku tools/build/watched-run.raku --log=t-all.log --stall=7200 --max=14400 -- raku tools/build/evalserver-sweep.raku t/01-sanity t/02-rakudo t/03-jvm t/04-nativecall t/05-messages t/06-telemetry t/07-pod-to-text t/08-performance t/09-moar t/10-qast t/11-compiler t/12-rakuast --jobs=1 --heap=6 '--chunk=*'`
  (use the directory list `ls t/` actually holds; `--chunk` = the total
  file count if `'*'` is not accepted for multiple directories). Run it
  as a plain background job. If the harness's low-memory guard kills it
  (four attempts died at 25-27 GB MemAvailable in Phase B), record the
  evidence and "not gathered" and hand the decision to the user (ruling
  15). Compare the red list with `docs/jvm-t02-rakudo-red-baseline.txt`
  and the full-suite doc. Baseline: 5078 s.
- [ ] **Step 3: Findings**: the milestone-7 summary section — one row
  per lever with both hashes and the four numbers (A1-A8 from Phase A's
  section, `b`, `c`), the promotion list of A7, the two clocks against
  2.68 s and 5078 s, CORE.c from the last make.
- [ ] **Step 4: Position** in `docs/jvm-truffle-only-plan.md`; the memory
  file; `MEMORY.md`.
- [ ] **Step 5: Rebase, gates once more if the rebase brought commits
  (`make` + `t/01-sanity`), push.** Remind the user to leave the session
  rather than `/clear`.

## Self-review (done at writing time, 2026-09-15)

**Spec coverage.** C0 -> done, recorded in Task 1. Schema -> Task 3
(ruling 1 drops the identity and descriptor index, with the reason).
Producer -> Tasks 5 and 7 (ruling 4 folds the writer into the training
process; both builds train; stage0 stays empty-tabled by ruling 6).
Consumer -> Task 4 (first miss, before `record`, realise-drop-install-
replay; eval server re-arms through `reset()`). Verification -> Task 4
(`off`, `verify`, mismatch printing) and Task 8 (the gate, both modes).
Measurement -> Task 9 (rig row `c`, the counters, the histogram). Gates
item 6 -> Task 8. The close -> Task 10. Out-of-scope items untouched;
compression -> ruling 11 (presented, not built). Risks: "valid in
training, not in the consumer" -> verify gate + `unseen` recorded as the
residual; "training and measured run confused" -> the rig's refusal is
in place and Task 9 says so.

**Placeholder scan.** None. Two places name an alternative if a spelling
differs (`tc.gc.KnowHOW`, the gradle tee) with the concrete fallback
stated.

**Type consistency.** `DispatchSlotCodec.persist/realise`,
`DispatchPersist.register/store/restore/verify/recordAtExit`,
`UnitStore.entryPrefix/absoluteSlot`, `UnitDispatchWriter.rewrite(path,
Map<String, Map<Int, ByteArray>>)`, `DispatchCallSite.unitNamespace/
programIndex/ordinal/restored/verifyPrograms`, `EngineSite(csd,
ProgramIdentity, int)` — used with the same names in every task that
mentions them.
