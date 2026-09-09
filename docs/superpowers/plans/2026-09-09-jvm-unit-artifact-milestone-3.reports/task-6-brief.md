### Task 6: Docs, ledger, memory, push, handoff rebase

**Files:**
- Modify: rakudo `docs/jvm-truffle-only-plan.md:30-33` (items 5, 6, 7, 8 rows: milestone 3 DONE; item 7 Rakudo shapes done; item 8 "compiler-side deletions done, runtime writer waits for stage0")
- Modify: rakudo `docs/superpowers/specs/2026-09-09-jvm-unit-artifact-design.md` "Milestones" item 3 (DONE line: what shipped, deviations 1-4, the two sweeps' wall clocks, no t/spec) and item 4 (gains the runtime-side writer deletion explicitly)
- Modify: rakudo `CLAUDE.md` (the `RAKUDO_RAKUAST=1 on every build` paragraph: the `NQP_CODE_RUN`/`NQP_CODE_PRECOMP` sentence becomes "on by default since 2026-09-09; `=0` opts out")
- Create/modify: this plan's `.ledger.md` and `.reports/` (the controller keeps them as it goes)
- Memory: `/home/longwalker/.claude/projects/-home-longwalker-code-raku-x-core-rakudo/memory/unit-artifact-milestones.md` (milestone 3 state, the deviations, milestone 4's entry list), `truffle-plan-position.md` (one line), `strict-refusal-campaign.md` (item 7 Rakudo shapes DONE), MEMORY.md hooks

- [ ] **Step 1: Update the plan doc, the spec, CLAUDE.md** (text per the file list above; keep the rows' existing milestone-1/2 text and append the milestone-3 sentence).
- [ ] **Step 2: Commit the rakudo tree** (docs only): `git add docs/ CLAUDE.md && git commit -m "docs: unit artifact milestone 3 -- Rakudo on the unit road (plan, ledger, reports, spec and position updates)"` with the trailer.
- [ ] **Step 3: Handoff rebase** (user rule, every handoff): `git fetch origin` in the rakudo worktree and `git rebase origin/main`; `cd .../nqp && git fetch upstream && git rebase upstream/main`. Conflicts are expected to be few. No gate after the rebase (user: "don't worry about that").
- [ ] **Step 4: Push both trees with --force-with-lease to ab5tract** (`git push --force-with-lease ab5tract worktree-jesp-direct-lazy-records` from the rakudo worktree; `cd .../nqp && git push --force-with-lease ab5tract jesp-direct-lazy-records && git push --force-with-lease origin jesp-direct-lazy-records`). Never push main; no PR (user: not until finished).
- [ ] **Step 5: Remind the user to leave the session rather than /clear** (user request, every handoff).

---

## Self-review notes

- Spec coverage: milestone-3 line, "Rakudo units as artifacts, after custom_args bodies and exit-handler blocks encode" = Task 1 (exit handlers; custom_args landed in the campaign) + Task 2 (the flip); "the eval server serves artifact units" = Task 2 Step 11 (harness5 `-app ./rakudo.jar` on an artifact) + Tasks 3 and 5; "the suites run through it" = Tasks 3 and 5 for t/, Task 2/4 Step 9 for t/nqp, t/spec excluded by user decision 2. Section 4 "The generated runner scripts change the main class token and gain the unit path argument" = Task 2 Step 4. Section 4 "Identity: the unit id string" = deviation 4 (verified not load-bearing). Milestone-2 line's deletions = Task 4, narrowed by deviation 1. Open item "backtrace ... a fallback to the block's start line when no Java frame correlates" = Task 2 Step 5.
- Types and names: `FORLOOPL = 35` in NqpWire.java and `$W_FORLOOPL := 35` in the encoder (Task 1 Steps 5-6); `emitForBody(redoL, preAt, bodyAt, nrId, lastId, labelLocal)` used by both the FORLOOP (null) and FORLOOPL cases; the knob die substring `needs the encoder on` in Compiler.nqp (Task 2 Step 2, Task 4 Step 1) and in t/nqp/124 (Task 2 Step 3); `is_compunit` exists on the jvm, moar and js backends (Task 2 Step 6); `$main` in create-jvm-runner.pl is built after `$rakudo_jars` and before the `install` calls.
- Placeholders: none; every code step carries the edit. The one conditional instruction (Task 1 Step 5's "if the builder has a header-length table") names what to search for.
- Ordering: Task 1 runs on the class road for Rakudo (knob still opt-in) so an exit-handler bug shows up with the class road's fallbacks still available for everything else; Task 2 flips only after 118/118 and sanity are green on Task 1's nqp.

---

