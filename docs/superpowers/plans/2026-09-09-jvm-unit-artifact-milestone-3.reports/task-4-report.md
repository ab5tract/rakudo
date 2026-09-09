# Task 4 report: the deletions (compiler-side class road; the knob; the stale recipes)

Status: **DONE**. Commits: nqp `30e849e3c`, rakudo `a22eb40b73`.

Every gate in the brief is green. Two gate lines need a sentence of context (both
pre-existing, both named in the brief or in Task 2's report): `nqp/t/qast/01-qast.t`
and `t/02-rakudo/rakuast-suspend-precomp-deps.t`.

---

## Steps 1-6: what was deleted, site by site

### Step 1 -- `nqp/src/vm/jvm/QAST/Compiler.nqp` (the road is the only road)

* `as_jast` prologue (was `:4098-4131`): the `@*ENGINE_PROGRAMS` comment now says the
  block table references the programs (no sidecar); the road paragraph is the brief's
  milestone-3 wording; **deleted** `$*UNIT_ROAD`, `$*UNIT_FALLBACKS`, the `if $*UNIT_ROAD {`
  wrapper and the `NQP_UNIT` sentence. `%env` stays (the encoder-off die reads it). The
  encoder-off die and the `--target=classfile` refusal are now unconditional and their
  messages lost the `(NQP_UNIT)` tag: `unit artifact: the road needs the encoder on; ...`
  and `unit artifact: --target=classfile has no artifact form; use --target=jar`.
* the deserialize-wrapper junction (was `:4160-4173`): **deleted** the
  `if %*BLOCK_LEX_VALUES && !$*UNIT_ROAD { ... setup_blv ... }` push and its comment; the
  wrapper condition is now `... || %*BLOCK_LEX_VALUES {`.
* the static-lexical rows (was `:4260`): `if %*BLOCK_LEX_VALUES {`, comment reworded (no
  "where the class road's setup_blv ran").
* the programs hand-off (was `:4305-4328`): the `if $*UNIT_ROAD { ... } elsif
  nqp::elems(@*ENGINE_PROGRAMS) { ... codeprograms ... }` is now the unconditional record
  hand-off exactly as the brief wrote it: `programs`, `callsites`, the `NQP_CODE_WHY` line.
  **Deleted** `$*JCLASS.fallbacks(...)`, `$*JCLASS.unit_road(1)` and the whole joined
  `codeprograms` arm.
* `deserialization_code` comment (was `:4345`): "as class entries on the class road, under
  nested/ in an artifact" -> "under nested/ in the parent's artifact".
* the block junction (was `:4683-4749`): **deleted** the sidecar paragraph, `my int
  $as_index := ...`, the `:sidecar`/`:unit_road` arguments, the `PushSVal` else arm, the
  `codeRun`/`$TYPE_STR` ternaries, and the string-constant `else` arm's
  `compile_all_the_stmts` fallback. Every encoded block now records its program by index
  and emits `codeRunIdx`; a block that does not encode is an unconditional
  `nqp::die('unit artifact: block ... has no engine program ...')`. The body comment above
  it lost the "bakes into the class file as a string constant" sentence.

### Step 2 -- `nqp/src/vm/jvm/QAST/TruffleEncoder.nqp` (no gates, no roads)

* `method encode_block($node, $block, $comp, :$comp_mode) {` (the `:$sidecar` and
  `:$unit_road` named parameters are gone).
* **deleted** the `raw` blocktype refusal and its comment (raw wrappers always encode).
* **deleted** the pre-commit size gate: the whole comment paragraph, `my int $est := ...`,
  the two accumulation loops and `if $est > 60000 && !$sidecar { ... }`.
* **deleted** the post-commit `nqp::die('... grew past the size gate after commit ...')`
  invariant and its two-line comment.
* `grep -n 'sidecar\|unit_road\|\$est'` over the file: **zero hits**.

### Step 3 -- `nqp/src/vm/jvm/HLL/Backend.nqp` (one junction)

`:79-106` is the brief's block verbatim: the `jvm-write-unit` / `jvm-build-unit` pair with
no `$jast.unit_road` test, no `compilejasttofile` arm and no `compilejast` arm.

### Step 4 -- the JAST carrier fields

* `nqp/src/vm/jvm/QAST/JASTNodes.nqp`: **deleted** `has str $!codeprograms;`, `has int
  $!fallbacks;`, `has int $!unit_road;`, the two BUILD inits, the `codeprograms` accessor
  and its four-line comment, and the `fallbacks`/`unit_road` accessors with the
  `NQP_UNIT road` comment. `@!nested_classes`, `@!programs`, `@!callsites`,
  `@!blockvalues` and every `cr_*` setter untouched.
* `.../jast2bc/JastClass.kt`: **deleted** the `codePrograms`, `fallbacks` and `unitRoad`
  fields, their guarded reads (the whole `try { codePrograms = ... }` block and the two
  `Ops.getattr_i` lines inside the unit-fields `try`), and the three `*Hint` fields with
  their `hint_for` lines in `setup()`.
* `.../jast2bc/JASTCompiler.kt:238`: `c.codePrograms = null` with the comment "No compiler
  emits a sidecar since milestone 3; the reader stays for stage0's jars."
* `.../runtime/unit/UnitWriter.kt`: **deleted** the `!jc.unitRoad` and `jc.fallbacks != 0`
  throws and the doc sentence naming them; the per-block refusals (no qbid, no program,
  duplicate qbid, missing nested record) are unchanged.

### Step 5 -- `CodeEngines.codeRun(String, ...)` is private

`.../runtime/CodeEngine.kt:86`: `@JvmStatic fun codeRun(` -> `private fun codeRun(` with the
brief's comment. `@JvmStatic` was dropped (a private static entry has no caller outside the
object; Kotlin compiled it without complaint either way, and nothing needs the static form).
The only caller is `codeRunIdx`. Evidence it is safe, beyond the brief's javap note:
`unzip -p nqp/src/vm/jvm/stage0/nqp.jar nqp.class | strings | grep codeRun` prints
**`codeRunIdx`** and nothing else -- stage0's bodies take the index road and read their
programs through the sidecar reader (`CompilationUnit.engineProgram`), which stays.

### Step 6 -- the Rakudo build's exports and the stale recipes

* `tools/templates/jvm/Makefile.in`: **deleted** `export NQP_CODE_RUN = 1`,
  `export NQP_CODE_PRECOMP = 1` and their comment paragraph; `export RAKUDO_RAKUAST = 1`
  keeps its paragraph and gains the one line "# The engine build is the build: the encoder
  and the unit road are on by default (nqp, 2026-09-09)."
* `tools/build/jvm-build.sh` and `tools/build/jvm-build-resume.sh`: all **5 + 5** recipes
  of the form `... -cp '<cp>' nqp --module-path=blib ... --javaclass=perl6 ...` now read
  `... -cp '<cp>' org.raku.nqp.runtime.unit.UnitMain
  /home/longwalker/code/raku/x.core/rakudo/nqp/build/jvm/share/lib/nqp.jar --module-path=blib ...`
  (the nqp.jar path already on each recipe's classpath). `rakudo-j-build` lines needed
  nothing (Task 2 changed the template). CLAUDE.md needed no edit: the scripts are still
  "the same commands written down".

## What I kept, and why

* Everything on the brief's "What STAYS" list, verified after the fact:
  `Ops.compilejast`/`compilejasttofile` and their two `map_classlib_core_op` lines at
  `Compiler.nqp:3442-3443`; `JASTCompiler.writeClass` and the rest of jast2bc;
  `AutosplitMethodWriter`; `loadcompunit`'s define branch, `inMemoryUnitBytes`, nested
  `.class` embedding, `MemoryClassLoader`, `loadJar(ByteBuffer)`, `EvalResult.jc`;
  the sidecar reader (`CompilationUnit.engineProgram`/`loadEnginePrograms`);
  `JarFileClassLoader`; `ByteClassLoader.defineClass` (line 56, still there -- and
  `t/03-jvm/01-interop.t` passes, which is what exercises it); `nested_classes` +
  `jvm-class-of-cuid`; every `cr_*` setter; the `--target=classfile` refusal.
* `JavaClass.codePrograms` and `JASTCompiler`'s sidecar-writing block stay (the field is
  simply always null now) -- they are the class road's writer, milestone 4's to delete.
* The `setup_blv` op and its handler stay in the compiler: nothing pushes it any more, but
  it is an op mapping, not road scaffolding, and the brief did not list it.
* Four *comments* in the runtime still say "NQP_UNIT" (`GlobalContext.kt:237`,
  `EvalResult.kt:8`, `Ops.kt:9046`, `dispatch/Syscalls.kt:488`). Deliberately kept: they
  are outside the brief's grep scope, and touching a `.kt` file invalidates
  `:nqp-runtime:jar`, which every stage compile task takes as an input -- i.e. it would
  have cost a second full nqp build, against the forward-only rule. Cheap follow-up for
  milestone 4.
* `nqp/t/nqp/123-unit-artifact.t` and `124-unit-record.t` still set `NQP_UNIT=1` in their
  spawned commands. Now a no-op; both pass. 124's knob assertion greps `needs the encoder
  on`, which the new (untagged) message still contains.

---

## Gates

### Step 7 -- runtime jars compile (foreground, <30 s)

```
RAKUDO_RAKUAST=1 ./nqp/gradlew -p nqp :nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars
=> BUILD SUCCESSFUL in 1s   (14 actionable tasks: 6 executed, 8 up-to-date; :nqp-runtime:test ran)
```

### Step 8 -- nqp clean build, then t/nqp + t/qast

```
RAKUDO_RAKUAST=1 NQP_CODE_STRICT=1 raku tools/build/watched-run.raku \
  --log=.../t4-build.log --show-file=.../t4-build.markers \
  --show='> Task :stage' --show='code-bail' --show='BUILD' --show='rror' \
  -- ./nqp/gradlew -p nqp clean buildJvm
[222s] BUILD SUCCESSFUL in 3m 42s
=== EXIT=0 verdict=ok elapsed=222s ===         (milestone-2 baseline 296 s; Task 2 285 s)
```

nqp jar census (`raku tools/build/jar-census.raku --nested nqp/build/jvm/share/lib/*.jar`):

```
ARTIFACT meta=1 class=0 nested=0  JASTNodes.jar ModuleLoader.jar NQPCORE.setting.jar
                                  NQPHLL.jar nqp.jar nqpmo.jar NQPP5QRegex.jar
                                  NQPP6QRegex.jar QAST.jar QASTNode.jar QRegex.jar
CENSUS: all 11 jars are unit artifacts
```

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=nqp/t/nqp -t=nqp/t/qast --jobs=3 \
  --log=.../t4-sweep.log --show-file=.../t4-sweep.markers -- nqp/nqp-j-gradle
SUMMARY: 117 of 120 ok in 364s        (exit 1 from the three FAILs below)
FAIL nqp/t/nqp/019-file-ops.t   -- cwd-relative, as in every earlier milestone
FAIL nqp/t/nqp/063-slurp.t      -- cwd-relative
FAIL nqp/t/qast/01-qast.t       -- pre-existing, moar-only (below)
```

From the nqp directory, both cwd-relative files pass:
`cd nqp && RAKUDO_RAKUAST=1 ./nqp-j-gradle t/nqp/019-file-ops.t` -> 112/112 ok;
`t/nqp/063-slurp.t` -> 1/1 ok. **t/nqp = 118/118. t/qast = 1/2**, as the brief expects.

`01-qast.t` detail (checked, not assumed): the first failure is test 10, `ok(nqp::index($error,
'has not appeared') >= 0)` -- that string is **MoarVM's** message
(`src/vm/moar/QAST/QASTCompilerMAST.nqp:420`); on JVM the same orphan-BVal compile fails with
the unit-road die, so test 9 ("a BVal for a block the unit never compiles fails to compile")
passes and test 10 cannot. The run then dies at `$backend.start(NQPMu)` --
`method start` exists only in `src/vm/moar/HLL/Backend.nqp:768`, and
`git show 8bab02391:src/vm/jvm/HLL/Backend.nqp | grep 'method start'` is empty, i.e. the JVM
backend never had it, before or after this task. Neither half is a deletion regression.

### Step 9 -- Configure, make, census, sanity, precomp, interop

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=.../t4-configure.log \
  --show-file=.../t4-configure.markers -- perl Configure.pl --backends=jvm --gen-nqp
=== EXIT=0 verdict=ok elapsed=3s ===
grep -c NQP_CODE_RUN Makefile => 0    (Makefile:209-210 = RAKUDO_RAKUAST + the new comment)
```
The Configure did clean the jvm products (`rakudo.jar` and `blib/Perl6/BOOTSTRAP/v6c.jar`
were both absent afterwards), so the make below is a full build, not a no-op.

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=.../t4-make.log \
  --show-file=.../t4-make.markers --show='Compiling' --show='Generating' --show='rror' \
  --stall=1500 -- make
=== EXIT=0 verdict=ok elapsed=1154s ===        (milestone-2 baseline 1274 s; Task 2 1173 s)
```

The five marker times (elapsed seconds from the start of `make`):

| marker | at |
| --- | --- |
| `Compiling rakudo.jar` | 171 s |
| `Compiling blib/Perl6/BOOTSTRAP/v6c.jar` | 200 s |
| `Compiling blib/CORE.c.setting.jar` | 594 s (next marker 1062 s => CORE.c ~468 s) |
| `Compiling blib/CORE.d.setting.jar` | 1069 s |
| `Compiling blib/CORE.e.setting.jar` | 1096 s |

Rakudo jar census (`raku tools/build/jar-census.raku --nested rakudo.jar blib/*.jar
blib/Perl6/*.jar blib/Perl6/BOOTSTRAP/*.jar blib/Raku/*.jar`):

```
ARTIFACT meta=1 class=0 nested=0  rakudo.jar
ARTIFACT meta=1 class=0 nested=8  blib/CORE.c.setting.jar
ARTIFACT meta=1 class=0 nested=0  CORE.d, CORE.e, Perl6/{Compiler,Metamodel,ModuleLoader,
                                  Ops,Optimizer,Pod,SysConfig}, BOOTSTRAP/{v6c,v6d,v6e},
                                  Raku/{Actions,Grammar}
CENSUS: all 16 jars are unit artifacts
```
CORE.c's `nested/` count is **8 entries = 4 nested units** (`.meta` + `.programs` each),
matching Task 2's "CORE.c's four".

Stale precomp stores cleared before any test: `rm -rf lib/.precomp t/packages/Test-Helpers/.precomp`.

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=t/01-sanity --jobs=2 \
  --log=.../t4-sanity.log --show-file=.../t4-sanity.markers -- ./rakudo-j
SUMMARY: 25 of 25 ok in 161s                    (baseline 214 s / Task 2 ~210 s)
```

The 14 precomp files (`--jobs=2`, log `t4-precomp.log`):

```
SUMMARY: 13 of 14 ok in 422s
FAIL t/02-rakudo/rakuast-suspend-precomp-deps.t (exit 255)
```
Same single FAIL Task 2 recorded, same cause and same resolution: the test spawns
`$*EXECUTABLE` without `-Ilib`, so the spawned child cannot find `Test`
(reproduced by hand: "Could not find Test in: ..."). With the environment the child needs,
it is green:
```
RAKUDO_RAKUAST=1 RAKUDOLIB=lib ./rakudo-j -Ilib t/02-rakudo/rakuast-suspend-precomp-deps.t
1..3 / ok 1 subprocess exited cleanly / ok 2 consumer module ran through the custom CUR chain
     / ok 3 SuspendTestCUR is absent from consumer precomp dep header
```
=> **14/14**.

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=t/03-jvm -t=t/10-qast --jobs=1 \
  --log=.../t4-jvm.log --show-file=.../t4-jvm.markers -- ./rakudo-j -Ilib
ok t/03-jvm/01-interop.t ; ok t/10-qast/00-misc.t ; SUMMARY: 2 of 2 ok in 33s
```
(01-interop.t passing is the direct evidence that `ByteClassLoader.defineClass` and the
interop adaptors were correctly left alone.)

### Item-5 log greps (regression watch)

```
t4-build.log : 'code-bail' 0, 'has no engine program' 0, 'bval to a block the unit never compiles' 0
t4-make.log  : 'code-bail' 0, 'has no engine program' 0, 'bval to a block the unit never compiles' 0
```
The only place that string appears at all is `nqp/t/qast/01-qast.t`'s deliberate
orphan-BVal test (and the encoder's own `cbail` text at `TruffleEncoder.nqp:1276`).

### Leftover-reference grep (self-review item 3)

```
grep -rn 'sidecar\|unit_road\|UNIT_ROAD\|UNIT_FALLBACKS\|codeprograms\|NQP_UNIT' \
     nqp/src/vm/jvm/QAST nqp/src/vm/jvm/HLL
=> no output
```

---

## Files changed

nqp (`30e849e3c`, 8 files, +68 -207):
`src/vm/jvm/QAST/Compiler.nqp`, `src/vm/jvm/QAST/TruffleEncoder.nqp`,
`src/vm/jvm/HLL/Backend.nqp`, `src/vm/jvm/QAST/JASTNodes.nqp`,
`src/vm/jvm/runtime/org/raku/nqp/jast2bc/JastClass.kt`,
`src/vm/jvm/runtime/org/raku/nqp/jast2bc/JASTCompiler.kt`,
`src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitWriter.kt`,
`src/vm/jvm/runtime/org/raku/nqp/runtime/CodeEngine.kt`.

rakudo (`a22eb40b73`, 3 files, +11 -18):
`tools/templates/jvm/Makefile.in`, `tools/build/jvm-build.sh`,
`tools/build/jvm-build-resume.sh`.

## Self-review

* `git diff 8bab02391..HEAD` (nqp) and `git diff 99d7b97d5d..HEAD` (rakudo) read end to end.
  Nothing from the "What STAYS" list is deleted (each item re-grepped, listed above).
  No accidental behaviour change rode along: every hunk is a deletion or the brief's
  replacement text.
* The one judgement call the brief left open (Step 5's `@JvmStatic`) is recorded above.
* Task 2's leftover minor for this task -- the `JASTCompiler.kt:238` comment -- is taken.
  The `create-jvm-runner.pl` minor was not mine to take (no change needed).

## Concerns

1. **The brief's Step 8 note is inaccurate, harmlessly.** It says stage1's jars "DO contain
   classes and sidecars". They contain classes but **no** sidecars: no
   `nqp/build/jvm/stage1/*.jar` has a `.codeprograms.lz4` entry, and stage1's `nqp.class`
   references neither `codeRun` nor `codeRunIdx`. That is why `c.codePrograms = null` is
   safe -- stage0's compiler does not encode when it builds stage1. (stage0's *own* jars do
   carry sidecars and do call `codeRunIdx`; that is what the reader stays for.) Nothing to
   fix; recorded so milestone 4 does not plan around a sidecar that is not written.
2. **Four stale `NQP_UNIT` mentions in runtime comments** (listed under "What I kept").
   Comment-only; deferred rather than pay a second full build.
3. `nqp/t/qast/01-qast.t` stays red for the two moar-only reasons above. If someone wants it
   green on JVM, tests 10/176/205 need a JVM-side expectation (the unit-road die text) and
   the `$backend.start` block needs a JVM `start`; that is not this milestone's work.
