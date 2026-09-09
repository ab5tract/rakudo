### Task 10: Post-completion gate, once on the green changeset

Run only after Task 9 is green in full (user rule: not per change).

- [ ] **Step 1: Rakudo on the artifact nqp, class road**

From the rakudo worktree root:

```bash
perl Configure.pl --backends=jvm --gen-nqp 2>&1 | tail -3
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/b945970f/tmp/rakudo-gate.log --show='Compiling' --show='Generating' --show='rror' -- make
```

Expected: `rakudo-j` built (the Makefile exports the knobs; `NQP_UNIT` is NOT set here, so Rakudo's units take the class road while the nqp they load are artifacts). `Configure.pl --gen-nqp` re-runs gradle `buildJvm`; export `NQP_UNIT=1` for that step so nqp stays on artifacts.

- [ ] **Step 2: t/01-sanity**

```bash
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/b945970f/tmp/sanity-gate.log -t=t/01-sanity --jobs=2 -- ./rakudo-j
```

Expected: 25/25. A failure here is a class-road unit loading an artifact unit's code refs across the boundary (Rakudo's `Perl6::*` class-file units call into nqp's artifact units); triage from the first failing file with `NQP_CODE_WHY=1` on that file's compile and `NQP_CODE_TRACE=1` on its run.

- [ ] **Step 3: Baseline and report**

Record BOOTSTRAP v6c, CORE.c stage timings from the make log and the sanity wall time next to the milestone line in `docs/jvm-truffle-only-plan.md` (forward-only rule: these are the next baseline). Commit and push as in Task 9 step 4.
