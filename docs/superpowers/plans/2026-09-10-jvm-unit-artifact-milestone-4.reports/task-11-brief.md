### Task 11: The milestone gate, docs, ledger, memory, handoff

**Files:**
- Modify: `docs/jvm-truffle-only-plan.md` (position rows 5, 6, 8, 9; "The sidecar, placed" paragraph becomes history), `docs/superpowers/specs/2026-09-09-jvm-unit-artifact-design.md` (Milestones item 4: DONE line), `docs/superpowers/specs/2026-09-10-jvm-unit-artifact-milestone-4-design.md` (a "Done" note with hashes and numbers), `AGENTS.md` and `CLAUDE.md` (any sentence naming JAST, jast2bc, the sidecar, `NQP_CODE_RUN` presence, or the class road as live), `docs/jvm-eval-server.md` (if it names `LibraryLoader`), `docs/jvm-strict-campaign-handoff.md` (a closing line), `nqp/docs/gradle-jvm-build.md` (Task 4 did the substantive edit)
- Create: `docs/superpowers/plans/2026-09-10-jvm-unit-artifact-milestone-4.ledger.md` (the ledger twin, kept from Task 1 on by the controller; this task syncs it)
- Test: the milestone gate

- [ ] **Step 1: The make** (needed if Task 10 touched RakuAST or Task 7's Step 5 did not run a full make; otherwise the Task 3/7 makes stand): Task 3 Step 3's command (`t11-make`). Record the time as the milestone's baseline.

- [ ] **Step 2: The gate**: t/nqp + t/qast (`t11-nqp`); `t/01-sanity` (`t11-sanity`); precomp (Task 3 Step 4's list, `t11-precomp`); t/03-jvm + t/10-qast (`t11-jvm`); the census (`raku tools/build/jar-census.raku` over nqp's `share/lib`, `stage0`, and rakudo's jars); then the sweep, sized as milestone 3's sweep 2:

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --max=7200 --stall=1500 --log=/home/longwalker/.claude/jobs/25fa1a35/tmp/t11-sweep.log --show-file=/home/longwalker/.claude/jobs/25fa1a35/tmp/t11-sweep.markers --show='chunk' --show='files in' --show='FAIL' -- raku tools/build/evalserver-sweep.raku --jobs=3 --heap=4 t/01-sanity t/02-rakudo t/03-jvm t/04-nativecall t/05-messages t/06-telemetry t/07-pod-to-text t/08-performance t/10-qast t/13-experimental t/14-smoke
```

with a second invocation for the directories the ceiling cut off. Expected red: the corekeys/settingkeys cluster; the 2026-09-05 known list minus what milestones 3-4 fixed; the item-8 pair only if Task 10 was parked. Any NEW failure against milestone 3's sweep 2 is triaged: a unit-road or runtime regression is fixed in this task (runtime jars, amend), a test-content failure is recorded.

- [ ] **Step 3: Docs**: the files listed above; `grep -rn 'JAST\|jast2bc\|codeprograms\|class road\|LibraryLoader\|NQP_CODE_RUN' AGENTS.md CLAUDE.md docs/*.md nqp/docs/*.md` and rewrite every sentence that presents them as live (history stays history, marked as such). The plan's position table: item 5 and 6 "milestone 4 DONE (hashes, numbers)"; item 8 "DONE: nothing JAST-named, no class road; ASM stays for P6Opaque and the adaptors"; item 9 "adaptor half DONE (AdaptorUnit); P6Opaque half open".

- [ ] **Step 4: Ledger, memory, commit**: sync the ledger twin; commit rakudo docs (`git add docs AGENTS.md CLAUDE.md && git commit -m "docs: unit artifact milestone 4 done -- ..."`); the controller updates memory (`unit-artifact-milestones`, `truffle-plan-position`, `all-qast-via-truffle` marked DONE, `MEMORY.md`).

- [ ] **Step 5: Handoff rebase and push** (user rule): rakudo `git fetch origin && git rebase origin/main` on the worktree branch; nqp `git fetch upstream && git rebase upstream/main`; then `git push --force-with-lease ab5tract worktree-jesp-direct-lazy-records` (rakudo) and `git push --force-with-lease ab5tract jesp-direct-lazy-records` plus `git push --force-with-lease origin jesp-direct-lazy-records` (nqp). No gate after the rebase (user, 2026-09-09).

---

## Self-review notes

- Spec coverage: section 1 (driver, records, reader, registries, Backend, stage lists, nqp and Rakudo Ops.nqp) = Tasks 1-3; section 2 (stage0) = Task 4; section 3 (runtime deletions, loader port, BytecodeVersion, CompilationUnit reshaped, IndyBootstrap, EvalServer, autosplit test, Makefile.in) = Tasks 5-6 (the reflective half of CompilationUnit and CodeRefAnnotation deliberately move to Task 7, with their last client); section 4 (adaptors) = Task 7; section 5 (5a/5b/5c) = Tasks 8-10; section 6 (guard rails) = Task 1 Step 3's target check, Task 4 Step 6's rule; section 7 (gates) = each task's test steps and Task 11; "Sequence" = the task order; docs/ledger/handoff = Task 11.
- Placeholder scan: none of the forbidden phrases; every code step shows the code; Tasks 8-10 carry explicit time boxes and rulings because they are investigations, and each names its probe, its files and its gate.
- Type consistency: `QAST::UnitCompiler.unit(:$unit_id)` / `compile_block` (Task 1) are what Task 1's Backend and encoder call; `RecordReader.read` is what `UnitWriter.record(unit, tc)` calls and the two `-record` syscalls use; `AdaptorUnit(cls, descriptors, target)` (Task 7) matches both `computeInterop` edits; `getCodeRefs(): Array<CodeRef>` non-null from Task 5 on (KnowHOWMethods updated in Task 5, AdaptorUnit in Task 7); `leaveTorn` replaces `countLeft` everywhere (Task 8); `NqpCont.Suspend.finish` / `NqpOps.suspendToken(sse, finish)` / `NqpTypeOps.SuspendedIn` (Task 9) agree across the four files.
