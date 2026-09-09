### Task 4: The gate

**Files:** none modified (a report under `docs/superpowers/plans/2026-09-09-jvm-unit-artifact-milestone-2.reports/task-4-report.md`, written by the controller from this task's output).

**Interfaces:**
- Consumes: the Task 2 build (no compiler source changed since; Task 3 added a test only, so no rebuild: forward only).

- [ ] **Step 1: Confirm the artifacts of the standing build**

For each of the 12 jars in `nqp/build/jvm/share/lib/`: `unzip -l nqp/build/jvm/share/lib/nqp.jar | grep -c unit.meta` is 1 and `... | grep -c '\.class'` is 0 (repeat per jar as plain commands, or `raku -e 'for dir("nqp/build/jvm/share/lib", test => /\.jar$/) { say .basename, " ", run(<unzip -l>, $_, :out).out.slurp.lines.grep(/unit\.meta/).elems, " ", run(<unzip -l>, $_, :out).out.slurp.lines.grep(/"." class/).elems }'`).

- [ ] **Step 2: t/nqp on the record road (the milestone's coverage)**

With the knob on, every test file compiles as a record in memory. From the rakudo worktree root, background job:

```
NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 raku tools/build/watched-run.raku -t=nqp/t/nqp --jobs=3 --log=/home/longwalker/.claude/jobs/3420e344/tmp/sweep-record.log -- nqp/nqp-j-gradle
```

Expected: the SUMMARY shows 113 of 115 passing from the rakudo root (019-file-ops and 063-slurp are cwd-relative, milestone-1 baseline), then those two from the nqp directory: `cd .../nqp && NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp-j-gradle t/nqp/019-file-ops.t` and `063-slurp.t`, both all-ok. Anything else failing is a record-road regression: rerun the file alone with `NQP_CODE_WHY=1`, and compare against the knob-off run of the same file; triage the way the campaign did (the block named in the die, `NQP_CODE_BAIL=1` for the reason).

The sweep's elapsed time against milestone 1's 487 s (class-road test compiles on the same artifact stage2 jars) is the record road's compile-cost reading; no separate knob-off sweep (user, 2026-09-09: the Rakudo gate below already covers the class road).

- [ ] **Step 3: Rakudo post-completion gate (class road) and the record-road probes**

Rakudo's units compile through the changed Compiler.nqp and Backend.nqp, so its build is the gate that the class road is untouched. From the rakudo worktree root, background jobs, one after the other:

```
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/3420e344/tmp/rakudo-configure.log -- perl Configure.pl --backends=jvm --gen-nqp
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/3420e344/tmp/rakudo-make.log --show='Compiling' --show='Generating' --show='rror' --stall=1500 -- make
raku tools/build/watched-run.raku -t=t/01-sanity --jobs=2 --log=/home/longwalker/.claude/jobs/3420e344/tmp/sanity.log -- ./rakudo-j
```

Expected: configure EXIT=0; make EXIT=0 (milestone-1 timing: 1173 s from a clean jvm tree; the nqp part is already built so expect less); t/01-sanity 25/25. `--gen-nqp` rebuilds nqp through gradle without `clean`; since the stage2 jars are current it should be a no-op, but if it rebuilds, it rebuilds without `NQP_UNIT` and produces class-road stage2 jars: check Step 1's counts again afterwards and, if they changed, rerun Task 2 Step 6 before the sweeps count.

Then the probes (informative; a failure is reported, not fixed here):

```
NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 NQP_CODE_WHY=1 ./rakudo-j -e 'BEGIN { say 1 }; say EVAL "2"; say 3' 2>&1 | grep -E '^[123]$|^unit record |rror|nqpp:' 
```
Expected if Rakudo's runtime compiles encode fully: `1`, three `unit record` lines (the mainline, the BEGIN block, the EVAL), `2`, `3`. A die naming a block is an item-7 shape and goes in the report.

```
mkdir -p /home/longwalker/.claude/jobs/3420e344/tmp/probe && printf 'unit module BeginMod;\nmy &kept = BEGIN { my $n = 41; -> { $n + 1 } };\nsub answer() is export { kept() }\n' > /home/longwalker/.claude/jobs/3420e344/tmp/probe/BeginMod.rakumod
NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 NQP_CODE_WHY=1 ./rakudo-j --target=jar --output=/home/longwalker/.claude/jobs/3420e344/tmp/probe/BeginMod.jar /home/longwalker/.claude/jobs/3420e344/tmp/probe/BeginMod.rakumod 2>&1 | grep -E 'unit artifact|unit record|rror|nqpp:'
unzip -l /home/longwalker/.claude/jobs/3420e344/tmp/probe/BeginMod.jar
```
Expected if it gets that far: a `unit record` line for the BEGIN block, a `unit artifact ... 1 nested` line, and the listing shows `unit.meta`, `unit.programs`, `unit.serialized.lz4`, `nested/<id>.meta`, `nested/<id>.programs`, no `.class`. Loading it back through `use` needs the precomp store and is milestone 3's business; stop at the listing.

- [ ] **Step 4: Record timings**

Note in the report: Task 2 build elapsed, the sweep elapsed (against 487 s), make elapsed, sanity elapsed. These are the next baseline (forward only).

---

