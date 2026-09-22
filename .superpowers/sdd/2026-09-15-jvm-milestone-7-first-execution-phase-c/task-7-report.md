# Task 7 report: the build hooks and the default-mode gate

Status: **DONE_WITH_CONCERNS** (gate fully green; one deviation from the brief,
described and validated below).

Commits:
- nqp `f5c5bc8fa` — *Build: train the dispatch slots of the stage2 copy before syncLib (Phase C)*
- rakudo `72417e05e1` — *Build: one dispatch-training run of the trivial program after the settings; the runner depends on its stamp (Phase C)*

Files changed: `nqp/build.gradle.kts`, `tools/templates/jvm/Makefile.in`. Nothing
else was staged (no jars, no generated `Makefile`, no `blib/`, nothing under
`.superpowers/`).

---

## 1. The two diffs

### nqp/build.gradle.kts (+72 / -2)

Three additions, all after `val stage2 = registerStage(2, ...)`:

1. `stage2TrainedDir` = `build/jvm/stage2-trained`, plus a `Sync` task
   `stage2Trained` that copies the nine stage2 jars into it. Training a copy
   keeps the stage2 compile tasks' own outputs untouched, so no later Gradle
   run recompiles stage2, and `jBootstrapFiles` goes on copying the *untrained*
   jars into `src/vm/jvm/stage0`.
2. A `JavaExec` task `trainDispatch` that runs
   `UnitMain stage2-trained/nqp.jar --module-path=… --setting-path=… -e ""`
   with `NQP_DISPATCH_RECORD=all`, the same class path / jvmArgs shape the
   stage compiles use. `doLast` asserts the output contains
   `dispatch-record: wrote` (a positive marker: a run that recorded nothing
   fails the build) and writes the `dispatch-record:` lines to
   `build/jvm/stage2-trained/dispatch-trained.txt`.
3. `syncLib` now does `from(stage2TrainedDir.file(it.jar))` and
   `dependsOn(trainDispatch)` instead of the stage2 tasks, so the lib jars are
   the trained ones.

**Adaptations to the brief's snippet (both required, both noted here):**

- `org.apache.commons.io.output.TeeOutputStream` is **not** on the build
  script's class path in Gradle 9.7 (`Unresolved reference`). Used the brief's
  stated fallback: `trainDispatchTee`, an anonymous `OutputStream` subclass
  (10 lines) writing to both `System.err` and a `ByteArrayOutputStream`. No new
  dependency.
- `java.io.ByteArrayOutputStream` cannot be written fully-qualified in a
  `build.gradle.kts` script: the Kotlin DSL's `java` extension
  (`JavaPluginExtension`) shadows the `java` package, so `java.io` fails to
  resolve. Added `import java.io.ByteArrayOutputStream` / `import
  java.io.OutputStream` next to the file's existing `import java.io.StringWriter`.

Everything else (task names, `stageTargets`, `jvmDir`, `runtimeJarFile`,
`engineJarFile`, `thirdPartySorted()`, `nqpStageMaxHeap`, `shareTruffleDir`,
`toolchainVersion`, `stage2`, `syncLib`) existed under the names the brief used.

**Incremental behaviour** (checked, not assumed): the training run mutates
`stage2Trained`'s output directory, so Gradle sees that task's outputs as
changed and re-runs the `Sync` on the next build — fresh *untrained* jars are
copied in and retrained from scratch, rather than an already-trained jar being
trained again. A no-change `buildJvm` therefore executes exactly
`stage2Trained`, `trainDispatch`, `syncLib` (3 of 55 tasks) and no stage
recompiles, in ~1 s. Verified:

```
> Task :stage2CompileNqp UP-TO-DATE     (all 18 stage compiles UP-TO-DATE)
> Task :stage2Trained
> Task :trainDispatch
> Task :syncLib
BUILD SUCCESSFUL in 1s
55 actionable tasks: 3 executed, 52 up-to-date
```

### tools/templates/jvm/Makefile.in (+25 / -1)

Adds `@bpv(TRAIN_STAMP)@ = @nfp(@bpm(BLIB)@/.dispatch-trained)@`, the stamp rule,
and `@bpm(TRAIN_STAMP)@` as a new prerequisite of `$(J_RUNNER)`.

**Adaptations to the brief's snippet:**

- The brief wrote the variable *definition* as `@bpm(TRAIN_STAMP)@ = …`.
  `@bpm(NAME)@` is the *reference* macro (`$(J_NAME)`); the definition macro,
  per every surrounding line, is `@bpv(NAME)@`. Used `@bpv` on the assignment
  and `@bpm` on the rule's target — which is what the brief's own generated
  form implies.
- `@echo '+++ Training\tdispatch slots'` written in the template's macro form
  `@echo(+++ Training<TAB>dispatch slots)@`, and `$(J_RUN_RAKUDO)` written as
  `@bpm(RUN_RAKUDO)@`, matching the neighbouring lines. Both expand to exactly
  the text the brief specified.
- **One added recipe step, not in the brief** — see section 3.

Expansion in the generated `Makefile` (verified by regenerating with
`perl Configure.pl --backends=jvm --gen-nqp` and diffing against a hand-applied
copy: identical apart from the comment text):

```make
J_TRAIN_STAMP = $(J_BLIB)/.dispatch-trained

$(J_TRAIN_STAMP): $(RAKUDO_JVM) $(SETTING_C_JVM) $(SETTING_D_JVM) $(SETTING_E_JVM)
	@echo '+++ Training	dispatch slots'
	$(NOECHO)NQP_DISPATCH_RECORD=all $(J_RUN_RAKUDO) -e '' 2>&1 | tee '$(J_BLIB)/.dispatch-train.log'
	$(NOECHO)grep -q 'dispatch-record: wrote' '$(J_BLIB)/.dispatch-train.log'
	$(NOECHO)sed -n 's|^dispatch-record: wrote .* to ||p' '$(J_BLIB)/.dispatch-train.log' | xargs touch -r '$(J_BLIB)/.dispatch-train.log'
	$(NOECHO)touch -r '$(J_BLIB)/.dispatch-train.log' $(RAKUDO_JVM) $(SETTING_C_JVM) $(SETTING_D_JVM) $(SETTING_E_JVM) $(J_RAKUDO_BOOTSTRAP_PRECOMPS)
	$(NOECHO)touch $@

$(J_RUNNER): …/create-jvm-runner.pl $(SETTING_C_JVM) $(SETTING_D_JVM) $(SETTING_E_JVM) $(J_TRAIN_STAMP)
```

---

## 2. The gate, default mode — every clock

### Step 1 — `./nqp/gradlew -p nqp clean buildJvm` — **elapsed=218 s**, PASS

```
raku tools/build/watched-run.raku --log=…/task7/buildjvm.log \
  --show='trainDispatch' --show='dispatch-record' --show='BUILD' --stall=1500 \
  -- ./nqp/gradlew -p nqp clean buildJvm
```

`BUILD SUCCESSFUL in 3m 38s` / `58 actionable tasks: 35 executed, 19 from cache, 4 up-to-date`
/ `=== EXIT=0 verdict=ok elapsed=218s ===`.

`nqp/build/jvm/stage2-trained/dispatch-trained.txt` exists and holds (paths
abbreviated to `<dir>` = `…/nqp/build/jvm/stage2-trained`):

```
dispatch-record: wrote 142 slots (144 programs, 0 unpersistable) to <dir>/nqpmo.jar
dispatch-record: wrote 18 slots (18 programs, 0 unpersistable) to <dir>/NQPP6QRegex.jar
dispatch-record: wrote 38 slots (38 programs, 1 unpersistable) to <dir>/QASTNode.jar
dispatch-record: wrote 117 slots (125 programs, 1 unpersistable) to <dir>/NQPHLL.jar
dispatch-record: wrote 11 slots (11 programs, 5 unpersistable) to <dir>/ModuleLoader.jar
dispatch-record: wrote 1049 slots (1051 programs, 21 unpersistable) to <dir>/QAST.jar
dispatch-record: wrote 34 slots (34 programs, 0 unpersistable) to <dir>/QRegex.jar
dispatch-record: wrote 171 slots (176 programs, 4 unpersistable) to <dir>/nqp.jar
dispatch-record: wrote 103 slots (114 programs, 9 unpersistable) to <dir>/NQPCORE.setting.jar
```

Lib jars carry non-empty `unit.dispatch`:

```
$ unzip -lv nqp/build/jvm/share/lib/QAST.jar | grep dispatch
  466835  Stored   466835   0% 2026-09-16 00:41 7feea438  unit.dispatch
$ unzip -lv nqp/build/jvm/share/lib/nqp.jar | grep dispatch
   75150  Stored    75150   0% 2026-09-16 00:41 b674299f  unit.dispatch
```

### Step 2 — nqp suite sweep — **elapsed=196 s**, PASS (155/155, 0 red)

```
raku tools/build/watched-run.raku --log=…/task7/nqp-suite.log \
  --show='red=' --show='green=' --show='FAIL' --stall=7200 --max=10800 \
  -- raku tools/build/evalserver-sweep.raku --suite=nqp '--chunk=*' --jobs=1
```

```
nqp: 155 files, 1 chunk(s) of 155, 1 server(s) x 6g heap + 3g off-heap (9g of a 20g budget, 23g available)
[196s] chunk 1/1: ok

155 files in 196s across 1 server(s)
=== EXIT=0 verdict=ok elapsed=196s ===
```

The sweep prints per-chunk detail only for failing chunks and exits non-zero if
any chunk fails (`exit @failed ?? 1 !! 0`); `chunk 1/1: ok` with exit 0 and no
`*** a file produced no TAP ***` marker means all 155 files green, 0 red.

### Step 3 — `perl Configure.pl --backends=jvm --gen-nqp` then `make clean && make` — **elapsed=883 s**, PASS

```
raku tools/build/watched-run.raku --log=…/task7/make.log \
  --show='Compiling' --show='Training' --show='dispatch-record' --show='Setting up' \
  --show='Error' --show='error:' --stall=1500 -- sh -c 'make clean && make'
```

`=== EXIT=0 verdict=ok elapsed=883s ===`. `+++ Training	dispatch slots` appears
**exactly once** (log line 108; line 109 is watched-run's own `[880s]` echo of
it). `blib/.dispatch-trained` and `blib/.dispatch-train.log` both present.

The training run's `dispatch-record: wrote` lines (23 artifacts):

```
dispatch-record: wrote 22 slots (22 programs, 0 unpersistable) to blib/CORE.d.setting.jar
dispatch-record: wrote 35 slots (35 programs, 0 unpersistable) to rakudo.jar
dispatch-record: wrote 38 slots (38 programs, 0 unpersistable) to nqp/build/jvm/share/lib/nqpmo.jar
dispatch-record: wrote 59 slots (59 programs, 0 unpersistable) to blib/Raku/Grammar.jar
dispatch-record: wrote 1486 slots (1487 programs, 40 unpersistable) to blib/CORE.c.setting.jar
dispatch-record: wrote 10 slots (10 programs, 0 unpersistable) to nqp/build/jvm/share/lib/ModuleLoader.jar
dispatch-record: wrote 33 slots (33 programs, 0 unpersistable) to blib/Perl6/Compiler.jar
dispatch-record: wrote 18 slots (18 programs, 0 unpersistable) to nqp/build/jvm/share/lib/NQPP6QRegex.jar
dispatch-record: wrote 34 slots (34 programs, 1 unpersistable) to blib/Perl6/ModuleLoader.jar
dispatch-record: wrote 78 slots (78 programs, 0 unpersistable) to blib/Perl6/Ops.jar
dispatch-record: wrote 99 slots (108 programs, 1 unpersistable) to nqp/build/jvm/share/lib/NQPHLL.jar
dispatch-record: wrote 1111 slots (1113 programs, 0 unpersistable) to nqp/build/jvm/share/lib/QAST.jar
dispatch-record: wrote 7 slots (7 programs, 0 unpersistable) to blib/Perl6/BOOTSTRAP/v6d.jar
dispatch-record: wrote 92 slots (104 programs, 0 unpersistable) to blib/Perl6/Metamodel.jar
dispatch-record: wrote 14 slots (14 programs, 0 unpersistable) to blib/Perl6/SysConfig.jar
dispatch-record: wrote 101 slots (110 programs, 5 unpersistable) to nqp/build/jvm/share/lib/NQPCORE.setting.jar
dispatch-record: wrote 110 slots (114 programs, 0 unpersistable) to blib/Raku/Actions.jar
dispatch-record: wrote 35 slots (35 programs, 0 unpersistable) to nqp/build/jvm/share/lib/QASTNode.jar
dispatch-record: wrote 841 slots (1105 programs, 3 unpersistable) to blib/Perl6/BOOTSTRAP/v6c.jar
dispatch-record: wrote 39 slots (40 programs, 0 unpersistable) to nqp/build/jvm/share/lib/QRegex.jar
dispatch-record: wrote 20 slots (20 programs, 0 unpersistable) to blib/Perl6/Optimizer.jar
```

`blib/CORE.c.setting.jar` and `rakudo.jar` are both in the list, as required.

**CORE.c compile time** (`+++ Compiling blib/CORE.c.setting.jar` at `[537s]`,
next target at `[833s]` → ~296 s wall including JVM start and artifact load):

```
Stage start      :   0.001
Stage parse      : 221.078
Stage syntaxcheck:   0.000
Stage ast        :   0.000
Stage optimize   :  22.381
Stage qast       :  16.843
Stage unit       :  21.332
Stage jar        :   0.000
                   ------- sum of stages: 281.635 s   (parse 221.078 s)
```

### Step 4 — `t/01-sanity` on the eval server — **55 s wall**, PASS

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=…/task7/sanity.log \
  --show='Files=' --show='Result' --show='not ok' \
  -- perl t/harness5 --jvm --evalserver t/01-sanity
```

```
Files=25, Tests=303, 55 wallclock secs ( 0.09 usr  0.03 sys + 18.33 cusr  1.02 csys = 19.47 CPU)
Result: PASS
```

### Step 5 — cold stats run, build-trained artifacts consumed

```
cd ROOT && NQP_DISPATCH_STATS=1 RAKUDO_RAKUAST=1 ./rakudo-j -e '' </dev/null 2>&1 | grep 'dispatch stats:'
```

```
dispatch stats: hits=13324 misses=4306 sites=6438 anon=5 sitesAll=6511 restored=4475 restoredSites=4193 dropped=37 recorded=195 slowEvals=83 invokes=5985 directs=5983 noTarget=2 badExpectation=0 notCodeRef=0 slowLayout=32 slowNull=27 byKind[value,syscall,mapped,invoke,resumable]=[0, 2205, 3787, 5967, 1365]
```

`restored=4475` (thousands), `recorded=195` (low hundreds) — matching Task 6's
hand-trained 193 to within run-to-run noise. The build now does the training.

---

## 3. The deviation: the graph-honesty step (and why)

**What I found.** Immediately after the gate's green `make`, a second `make`
was **not** a no-op — it wanted to recompile the entire frontend and all three
settings (~900 s):

```
$ make -n | grep "^echo '+++"
… Compiling blib/Perl6/ModuleLoader.jar … blib/Raku/Actions.jar … blib/Raku/Grammar.jar
… Compiling rakudo.jar … blib/CORE.c.setting.jar … blib/CORE.d.setting.jar … blib/CORE.e.setting.jar
```

Root cause, from `make -d blib/Raku/Grammar.jar`:

```
 Prerequisite 'blib/Raku/Actions.jar' is newer than target 'blib/Raku/Grammar.jar'.
 Must remake target 'blib/Raku/Grammar.jar'.
```

The training run rewrites the artifacts it loaded in *its* order, which is not
make's build order, so a prerequisite routinely ends up a fraction of a second
newer than its dependent. The brief's recipe (`touch $@` only) keeps the stamp
newest but leaves that inversion behind — the comment the brief itself writes,
"the stamp keeps make's graph honest", was not actually true. This is a defect
of my own Makefile edit, which the brief puts in scope, so I fixed it rather
than shipping a build where every `make` is a full rebuild.

**The fix** (two recipe lines before `touch $@`):

```make
	$(NOECHO)sed -n 's|^dispatch-record: wrote .* to ||p' '$(J_BLIB)/.dispatch-train.log' | xargs touch -r '$(J_BLIB)/.dispatch-train.log'
	$(NOECHO)touch -r '$(J_BLIB)/.dispatch-train.log' $(RAKUDO_JVM) $(SETTING_C_JVM) $(SETTING_D_JVM) $(SETTING_E_JVM) $(J_RAKUDO_BOOTSTRAP_PRECOMPS)
```

Every rewritten artifact gets one and the same mtime (the train log's), and the
stamp alone is newer. Make only remakes on a *strictly* newer prerequisite, so
equal timestamps settle the whole layer. This is honest rather than a
suppression: the training is the last build step, so everything the build
produced really is current as of it — the content changed, but nothing went
stale.

The second line is needed because the trivial program is a 6.c program: it
never loads `blib/CORE.e.setting.jar` or `blib/Perl6/BOOTSTRAP/v6e.jar`, so
those two stay at their compile time while `CORE.d.setting.jar` (which *is*
loaded) moves forward — and `SETTING_E` depends on `SETTING_D`. With only the
first line, `make -n` still wanted `v6e.jar` + `CORE.e.setting.jar` (≈35 s);
with both, it is clean.

**How it was verified** (three clocks, all recorded):

| what | result |
| --- | --- |
| first line only, full `make` (`make2.log`) | `elapsed=882 s`, exit 0; second `make -n` down from 30+ targets to 2 (`v6e.jar`, `CORE.e.setting.jar`) |
| second line applied, stamp removed, `make` run for real (`make3.log`) | exit 0 in **2 s** — exercised the real generated recipe end-to-end; `make -n` afterwards showed **no compiles and no retraining** |
| template regenerated, final full `make` (`make4.log`) | `elapsed=881 s`, exit 0, `+++ Training` once; `make -n` afterwards → only the two phony targets `Setting up JVM runner` / `j-runner-default` |

The template's expansion was confirmed by regenerating the `Makefile` with
`perl Configure.pl --backends=jvm --gen-nqp` and diffing it against a
hand-applied copy: the recipe bytes are identical (the only diff was the extra
explanatory comment I put in the template).

Final state re-verified on the tree as committed:

- `make -n` after a full build: only `+++ Setting up JVM runner` and
  `+++ Setting up j-runner-default`, both phony targets that existed before
  this change.
- CORE.c on the final build: `Stage parse : 223.841`, stage sum **283.287 s**
  (start 0.001, parse 223.841, syntaxcheck 0.000, ast 0.000, optimize 21.726,
  qast 16.547, unit 21.172, jar 0.000) — i.e. unchanged from the gate run
  (281.635 s), within noise.
- `t/01-sanity` re-run on the final tree (`sanity2.log`): `Files=25, Tests=303,
  56 wallclock secs`, `Result: PASS`.
- `dispatch stats:` on the final tree: byte-identical to the gate line above
  (`restored=4475 … recorded=195`).

---

## 4. Self-review findings

- **Not an A/B compile.** The extra `make` runs were forward-only validation of
  a build-graph fix, not a benchmark re-run of a failed measurement. The gate's
  official CORE.c and make clocks are the step-3 ones (883 s / parse 221.078 s);
  the later ones are quoted only as "unchanged".
- **`trainDispatch` re-runs on every Gradle build (~1 s).** Its declared inputs
  are the jars it itself rewrites, so it is never UP-TO-DATE. Benign and in
  fact necessary: `stage2Trained` is likewise never UP-TO-DATE (its outputs
  were mutated), so each build retrains from *fresh untrained* copies rather
  than compounding training onto an already-trained jar. No stage recompiles.
  Confirmed by task-by-task output, not assumed.
- **Training is mildly nondeterministic.** Across three `buildJvm` runs the
  counts were identical for eight of the nine stage2 jars;
  `NQPCORE.setting.jar` moved between `103 slots (114 programs, 9
  unpersistable)` and `102 slots (112 programs, 8 unpersistable)`. It does not
  degrade run over run (the third run was back at 103), consistent with timing
  noise in what the trivial program happens to reach, not with table shrinkage.
- **`xargs touch` cannot get an empty argument list**, because the preceding
  `grep -q 'dispatch-record: wrote'` already failed the build if the log had no
  such line. Paths in the log are relative to the base dir (the run's cwd) and
  contain no spaces.
- **nqp's lib jars are never make prerequisites** — they appear only inside
  `$(NQP_JARS)` / `$(BLD_NQP_JARS)` class-path strings — so the training
  rewriting them does not perturb rakudo's graph. Checked explicitly before
  choosing the single-mtime approach.
- **Ordering between the two builds.** A `gradlew buildJvm` after a rakudo
  `make` re-syncs `share/lib` from `stage2-trained`, replacing the
  rakudo-level training of those jars with the nqp-level training. That is the
  intended layering (gradle trains for nqp, make trains for rakudo on top), but
  it means the nqp lib jars' rakudo-trained slots are transient. Worth a line
  in the Phase C docs.
- **Two new untracked files** appear in `git status`: `blib/.dispatch-trained`
  and `blib/.dispatch-train.log`. `.gitignore` has no `blib/` rule (only
  `blib/Perl6/**/*.js`), and the tree already carries a lot of untracked build
  noise, so I left `.gitignore` alone rather than touch a third file. Neither
  file is removed by `make clean`; that is harmless (a surviving stamp is older
  than the artifacts a rebuild produces, so the rule re-runs), but adding both
  to the backend `CLEANUPS` list would be tidier and is a one-liner in
  `tools/templates/Makefile-backend-common.in` — deliberately not done here.
- **`$(J_RUNNER)` regenerates whenever the stamp is newer than it.** After a
  real `make` the runner is written after the stamp, so this settles; it only
  showed up in my hand-made intermediate state. One perl invocation, no cost.

## 5. Concerns / open items

1. The deviation in section 3 is a real design addition the brief did not
   specify. It is small, commented, and validated end-to-end, but the directing
   session should confirm it is wanted — the alternative it rules out is a
   per-file mtime snapshot/restore (strictly more faithful, but needs a third
   file, a `tools/build/` helper).
2. `Configure.pl` invalidates the whole build every time it runs (it re-expands
   `gen/jvm/main-version.nqp` and removes the runner scripts). Pre-existing,
   unrelated to this change, but it means "regenerate the Makefile" always
   costs a full `make`. Noted because it shaped how this task was validated.
3. Training on the nqp side is guarded by a positive marker; on the rakudo side
   by `grep -q`. Neither asserts a *quantity*. If some future change made the
   trivial program record only a handful of programs, both gates would still
   pass. A floor (e.g. "at least N slots") would be a cheap hardening.

## 6. Logs

All under `/home/longwalker/.claude/jobs/ba3ab3a7/tmp/task7/`:
`buildjvm.log`, `nqp-suite.log`, `make.log` (the gate's `make clean && make`),
`sanity.log`, `make2.log` / `make3.log` / `make4.log` (fix validation),
`sanity2.log`, `Makefile.handedit` (the expansion diff reference).

---

# Fix round 1 — exit status masked by the `tee` pipeline (Important)

Amended rakudo commit: **`79829d402e`** (was `72417e05e1`; nothing was pushed).
Only `tools/templates/jvm/Makefile.in` staged. The nqp commit `f5c5bc8fa` is
untouched.

## The finding, confirmed

`... $(J_RUN_RAKUDO) -e '' 2>&1 | tee <log>` reports **tee's** status, not the
runner's — make gives each recipe line its own `sh` with no `pipefail`. A
trainer that dies *after* rewriting some artifacts still emits
`dispatch-record: wrote` lines, so the following `grep -q` also passes and the
build continues on a half-trained artifact set. The grep cannot distinguish a
part-way run from a whole one; only the exit status can.

## What changed in the template

```diff
-	$(NOECHO)NQP_DISPATCH_RECORD=all @bpm(RUN_RAKUDO)@ -e '' 2>&1 | tee @nfpq(@bpm(BLIB)@/.dispatch-train.log)@
+	$(NOECHO)NQP_DISPATCH_RECORD=all @bpm(RUN_RAKUDO)@ -e '' > @nfpq(@bpm(BLIB)@/.dispatch-train.log)@ 2>&1 || { cat @nfpq(@bpm(BLIB)@/.dispatch-train.log)@; exit 1; }
+	$(NOECHO)cat @nfpq(@bpm(BLIB)@/.dispatch-train.log)@
 	$(NOECHO)grep -q 'dispatch-record: wrote' @nfpq(@bpm(BLIB)@/.dispatch-train.log)@
```

POSIX sh only — a redirect, `||`, a brace group and `exit`; no `pipefail`, no
bashism. On failure the log is shown before the recipe line exits 1, so the
build output still carries the diagnostic. On success the log is shown by the
`cat` line, keeping the training output visible under watched-run exactly as
`tee` did. The `touch -r` normalisation, the `grep -q` marker and the stamp are
unchanged.

The template comment now explains the shape instead of mentioning `tee`:

```
# nqp's lib jars). The stamp keeps make's graph honest; the grep is the
# positive marker (a run that wrote nothing fails the build). The run writes
# to the log and the log is shown afterwards, rather than piped through tee:
# make gives each recipe line a plain sh with no pipefail, so a pipeline
# would report tee's status and a trainer that died PART WAY -- after some
# artifacts were rewritten, which the grep cannot tell apart from a whole
# run -- would leave a half-trained build behind, green.
```

Whitespace checked with `cat -A`: all six recipe lines are TAB-indented, the
`@echo(+++ Training<TAB>dispatch slots)@` tab intact.

## Validation

### Failure path, proved by hand (touches no build artifact)

Run as `/home/longwalker/.claude/jobs/ba3ab3a7/tmp/task7/pipefail-proof.sh`,
with a stand-in trainer that prints a `dispatch-record: wrote` line and then
exits 3 — the part-way failure the finding describes. Both shapes, plus the
new shape's happy path:

```
=== OLD SHAPE (tee pipeline, what shipped) ===
dispatch-record: wrote 1 slots (1 programs, 0 unpersistable) to blib/CORE.c.setting.jar
old shape: recipe line exit = 0   <-- 0 means make CONTINUES
old shape: following grep -q exit = 0   <-- 0, the positive marker passes

=== NEW SHAPE (redirect + || { cat; exit 1; }) ===
dispatch-record: wrote 1 slots (1 programs, 0 unpersistable) to blib/CORE.c.setting.jar
new shape: recipe line exit = 1   <-- 1 means make STOPS

=== NEW SHAPE, happy path (trainer exits 0) ===
dispatch-record: wrote 7 slots (7 programs, 0 unpersistable) to rakudo.jar
new shape happy path: exit = 0   <-- 0, and the log was shown
```

The old shape is green on a part-way death and the grep does not catch it; the
new shape exits 1 with the log shown; the happy path is unchanged. (`/bin/sh`
here is bash, but the construct is POSIX and behaves identically under dash —
it uses no shell option.)

I chose the by-hand shape over `make J_RUN_RAKUDO='...'` because the make
override would have had to run the real stamp target, which retrains `blib/`
and `nqp/build/jvm/share/lib/*.jar` — see below.

### Configure + make validation: **PENDING, deliberately not run**

The coordinator put the build validation on hold while Task 8's gates run on
the lib jars: `perl Configure.pl --backends=jvm --gen-nqp` re-runs the nqp
build and re-syncs `nqp/build/jvm/share/lib`, and `make` retrains `blib/` and
those same jars — either would move the artifacts under a running gate. **I
have run no `Configure.pl` and no `make` since the review arrived**; the only
things done in this round are the two template edits, the by-hand proof above
(which writes only to the job tmp dir), and the commit amend. The generated
`ROOT/Makefile` in the tree is therefore still the pre-fix one.

Still to run, when released:

1. `perl Configure.pl --backends=jvm --gen-nqp` (from ROOT) — record its wall
   time; gradle should be mostly up to date.
2. `cat -A` the regenerated `Makefile` around `$(J_TRAIN_STAMP)` to confirm the
   expansion (expect the redirect + `|| { cat '...'; exit 1; }` line, then the
   `cat` line, then the unchanged `grep -q`).
3. `rm -f blib/.dispatch-trained && RAKUDO_RAKUAST=1 make` — expect only the
   stamp target and the runner to run, a few seconds, the `dispatch-record:
   wrote` lines visible, exit 0.
4. A second bare `make` — expect a no-op (only the two phony `Setting up`
   targets).

### Expansion, as far as it can be checked without regenerating

Every macro on the two changed lines is already proven elsewhere in this same
rule: `@nfpq(@bpm(BLIB)@/.dispatch-train.log)@` appears unchanged on the
`grep -q`, `sed`/`xargs` and `touch -r` lines, which expanded correctly in the
gate's generated `Makefile` (`'$(J_BLIB)/.dispatch-train.log'`). The only new
text is plain shell, which the macro expander passes through. Expected
expansion:

```make
	$(NOECHO)NQP_DISPATCH_RECORD=all $(J_RUN_RAKUDO) -e '' > '$(J_BLIB)/.dispatch-train.log' 2>&1 || { cat '$(J_BLIB)/.dispatch-train.log'; exit 1; }
	$(NOECHO)cat '$(J_BLIB)/.dispatch-train.log'
	$(NOECHO)grep -q 'dispatch-record: wrote' '$(J_BLIB)/.dispatch-train.log'
```

To be confirmed by step 2 above before this fix is considered closed.

## Rulings noted

- **Ruling 21** — training is reproduced by any clean build up to the run's own
  nondeterminism (§4: ~1 % of slots, `NQPCORE.setting.jar` moving between
  103/114/9 and 102/112/8 across runs, non-degrading); the plan's
  "deterministically" is relaxed to that, with the verify gate as the
  correctness net.
- **Ruling 22** — the default-mode nqp suite on the post-`make` lib jars is
  Task 8's, which closes the ordering gap noted in §4 ("the nqp lib jars'
  rakudo-trained slots are transient").

## Fix round 1 — held validation, now run

Released by the coordinator after Task 8's gates finished. No commit change was
needed: the recipe behaved as designed at every step. rakudo `79829d402e`
stands.

### (1) `perl Configure.pl --backends=jvm --gen-nqp` — **elapsed=5 s**

```
raku tools/build/watched-run.raku --log=…/task7/configure-fix1.log \
  --show='trainDispatch' --show='dispatch-record' --show='BUILD' --stall=900 \
  -- perl Configure.pl --backends=jvm --gen-nqp
=== EXIT=0 verdict=ok elapsed=5s ===
```

Gradle re-ran `stage2Trained` / `trainDispatch` / `syncLib` and re-synced the
lib jars, as expected (`BUILD SUCCESSFUL in 2s`), with the nine stage2 jars
retrained — `NQPCORE.setting.jar` back at `103 slots (114 programs, 9
unpersistable)`, the other eight identical to every previous run.

### (2) The regenerated recipe, `cat -A` (`$` line-ends stripped, `^I` = TAB)

```
$(J_TRAIN_STAMP): $(RAKUDO_JVM) $(SETTING_C_JVM) $(SETTING_D_JVM) $(SETTING_E_JVM)
^I@echo '+++ Training^Idispatch slots'
^I$(NOECHO)NQP_DISPATCH_RECORD=all $(J_RUN_RAKUDO) -e '' > '$(J_BLIB)/.dispatch-train.log' 2>&1 || { cat '$(J_BLIB)/.dispatch-train.log'; exit 1; }
^I$(NOECHO)cat '$(J_BLIB)/.dispatch-train.log'
^I$(NOECHO)grep -q 'dispatch-record: wrote' '$(J_BLIB)/.dispatch-train.log'
^I$(NOECHO)sed -n 's|^dispatch-record: wrote .* to ||p' '$(J_BLIB)/.dispatch-train.log' | xargs touch -r '$(J_BLIB)/.dispatch-train.log'
^I$(NOECHO)touch -r '$(J_BLIB)/.dispatch-train.log' $(RAKUDO_JVM) $(SETTING_C_JVM) $(SETTING_D_JVM) $(SETTING_E_JVM) $(J_RAKUDO_BOOTSTRAP_PRECOMPS)
^I$(NOECHO)touch $@
```

Byte-for-byte the expansion predicted in the section above. All seven recipe
lines TAB-indented; no `tee`, no pipeline on the training line.

### (3) `rm -f blib/.dispatch-trained && make` — **elapsed=880 s**, exit 0

**Not "a few seconds", and not because of this fix.** `Configure.pl` re-expands
`gen/jvm/main-version.nqp`, which every generated source depends on, so *any*
`Configure.pl` run invalidates the whole build — the §5.2 concern, pre-existing
and unrelated. `make -n` immediately after step (1), with the stamp removed,
already listed the full frontend + all three settings. I ran the full build
rather than skip the validation.

```
raku tools/build/watched-run.raku --log=…/task7/make-fix1.log \
  --show='Compiling' --show='Training' --show='dispatch-record' --show='Setting up' \
  --show='Error' --show='error:' --stall=1500 -- make
=== EXIT=0 verdict=ok elapsed=880s ===
```

`+++ Training	dispatch slots` appears **exactly once** (log line 95; line 96 is
watched-run's `[877s]` echo). The new `cat` line showed the training output in
the build log — **21** `dispatch-record: wrote` lines, the same 21 artifacts as
the gate run, e.g.:

```
dispatch-record: wrote 1486 slots (1487 programs, 40 unpersistable) to blib/CORE.c.setting.jar
dispatch-record: wrote 35 slots (35 programs, 0 unpersistable) to rakudo.jar
dispatch-record: wrote 841 slots (1105 programs, 3 unpersistable) to blib/Perl6/BOOTSTRAP/v6c.jar
dispatch-record: wrote 1111 slots (1113 programs, 0 unpersistable) to nqp/build/jvm/share/lib/QAST.jar
…
```

`blib/.dispatch-trained` recreated. CORE.c on this build: `Stage parse
223.523`, stage sum **284.013 s** (start 0.001, parse 223.523, syntaxcheck
0.000, ast 0.000, optimize 22.097, qast 16.831, unit 21.561, jar 0.000) —
unchanged from the gate's 281.635 s, within noise.

### (4) Second bare `make` — **no-op**

```
$ make
+++ Setting up JVM runner
+++ Setting up	j-runner-default
```

Only the two phony targets that predate this change. No compiles, no
retraining: the `touch -r` normalisation still holds with the new recipe shape.

### (5) Cold stats on the retrained tree

```
$ NQP_DISPATCH_STATS=1 RAKUDO_RAKUAST=1 ./rakudo-j -e '' </dev/null 2>&1 | grep 'dispatch stats:'
dispatch stats: hits=13324 misses=4306 sites=6438 anon=5 sitesAll=6511 restored=4475 restoredSites=4193 dropped=37 recorded=195 slowEvals=83 invokes=5985 directs=5983 noTarget=2 badExpectation=0 notCodeRef=0 slowLayout=32 slowNull=27 byKind[value,syscall,mapped,invoke,resumable]=[0, 2205, 3787, 5967, 1365]
```

`restored=4475`, `recorded=195` — byte-identical to the gate's line. The
retrained tree restores exactly as before.

### Verdict

No defect exposed; no amend needed. Logs: `configure-fix1.log`,
`make-fix1.log`, `pipefail-proof.sh` (all under
`/home/longwalker/.claude/jobs/ba3ab3a7/tmp/task7/`).
