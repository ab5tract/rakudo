# Task 2 report: the compiler takes every unit down the road under the knob

Commit (nqp tree): `0b149eaeb` — "unit artifact: under NQP_UNIT every unit takes the road -- runtime
compiles become records in memory". Parent is Task 1's `cfa0846ac`. One build attempt, one commit.

## What was implemented, per step

**Step 1 — `nqp/src/vm/jvm/QAST/Compiler.nqp`, the road decision and the knob checks.**
The `$*UNIT_ROAD` declaration no longer conjoins `$cu.compilation_mode` and `target eq 'jar'`: it is
now `nqp::existskey(nqp::getenvhash(), 'NQP_UNIT') ?? 1 !! 0`, so every unit — script, EVAL,
BEGIN-time unit, `--target=jar` with no `--output` — takes the road when the knob is set. The
comment block above it was replaced with the brief's text. The `if $*UNIT_ROAD { ... }` guard was
added directly beneath: it dies unless both `NQP_CODE_RUN` and `NQP_CODE_PRECOMP` are in the
environment, and dies on `--target=classfile`. `$*UNIT_FALLBACKS := 0` is unchanged.

**Step 2 — the wrapper condition.** `if $*COMP_MODE || @pre_des || @post_des ||
need_set_code_object($cu) {` gained `|| ($*UNIT_ROAD && %*BLOCK_LEX_VALUES)` and the brief's
three-line comment above it. (The row-building site at what is now line 4255 lives inside that
wrapper body, so without this the record road would silently lose its static-lexical-value rows for a
unit whose only reason to have a wrapper was `setup_blv`.)

**Step 3 — `$as_index` and comments.** `my int $as_index := $*COMP_MODE && ... eq 'jar';` became
`$*UNIT_ROAD || ($*COMP_MODE && %*COMPILING<%?OPTIONS><target> eq 'jar')`, with the brief's expanded
comment. The `deserialization_code` opening comment now reads "Their units ride along in the jar (as
class entries on the class road, under nested/ in an artifact), and the deserialization code loads
them back …" (rewrapped to the file's comment width). The `NQP_CODE_WHY` census line now says
`' -> unit road'` instead of `' -> artifact'`; it remains gated by the pre-existing
`if nqp::existskey(nqp::getenvhash(), 'NQP_CODE_WHY');` on the next line. `JASTNodes.nqp` gained the
one-line comment above `method nested_classes`.

**Step 4 — `nqp/src/vm/jvm/HLL/Backend.nqp`, `classfile`.** The junction now tests `$jast.unit_road`
first: jar + output goes to `jvm-write-unit` and returns `nqp::null()`; anything else on the road
returns `nqp::syscall('jvm-build-unit', $jast, %jastnodes)`. The old classfile/jar-with-output branch
became the `elsif`, and the final `else { nqp::compilejast(...) }` is untouched. `has int
$!unit_road` defaults to 0 (`JASTNodes.nqp:22`, initialised at `:43`), so with the knob unset the
first test is false and the class road is byte-for-byte the old control flow.

**Step 5 — `nqp/src/vm/jvm/QAST/TruffleEncoder.nqp`, `splice_code`.** The helper was added as a
class-body `sub` above `patch_params` (above that method's own doc comment, so the comment stays
attached to the method). All four splice-and-shift sites now call it: `patch_params` custom_args
header, `patch_params` full prologue, `encode_child`, `coerce_at`. No `nqp::splice(%e<code>, …)` call
remains outside the helper (verified by grep: one hit, line 925, inside `splice_code`).

## Step 6 — build

```
NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 NQP_CODE_STRICT=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/3420e344/tmp/build-task2.log --show='> Task :stage' --show='BUILD' --show='rror' -- ./nqp/gradlew -p nqp clean buildJvm
```
run as a background job from `/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records`.

```
BUILD SUCCESSFUL in 4m 55s
62 actionable tasks: 40 executed, 18 from cache, 4 up-to-date
=== EXIT=0 verdict=ok elapsed=296s ===
```

Jar census over `nqp/build/jvm/share/lib/*.jar` (Raku one-liner over `unzip -l`):

| jar | unit.meta | .class |
|---|---|---|
| JASTNodes.jar | 1 | 0 |
| ModuleLoader.jar | 1 | 0 |
| NQPCORE.setting.jar | 1 | 0 |
| NQPHLL.jar | 1 | 0 |
| NQPP5QRegex.jar | 1 | 0 |
| NQPP6QRegex.jar | 1 | 0 |
| QAST.jar | 1 | 0 |
| QASTNode.jar | 1 | 0 |
| QRegex.jar | 1 | 0 |
| nqp.jar | 1 | 0 |
| nqpmo.jar | 1 | 0 |

Every stage2 jar is an artifact. Note: **11 jars, not the 12 the brief predicted** — the lib
directory holds exactly these eleven `.jar` files plus `jvmconfig.properties`. Nothing is missing
relative to the stage2 task list (`stage2Compile{ModuleLoader,Nqpmo,CoreSetting,JastNodes,QastNode,
Qregex,Hll,Qast,P6qregex,Nqp}` plus the P5QRegex jar); the brief's "12" appears to be an off-by-one.

## Step 7 — smokes

1. ```
   NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 NQP_CODE_WHY=1 ./nqp/nqp-j-gradle -e 'say(6*7)' 2>&1 | grep -E '^42$|^unit record '
   ```
   →
   ```
   unit record 445B78202E360446161613121F4B40742141BC19 (5 programs, 5 qbids)
   42
   ```
   As expected: one `unit record` line, then `42`.

2. ```
   NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'say(nqp::getcomp("nqp").eval("my $y := 5; $y * 3"))'
   ```
   → **failed at parse time, on a quoting bug in the brief's command, not in the code**:
   `===SORRY!=== Error while compiling -e / Use of undeclared variable '$y' at line 1, near " := 5; $y "`.
   The inner NQP string is double-quoted, so NQP interpolates `$y` in the *outer* program before the
   EVAL string is ever built. The same command fails identically on any build, with or without the
   knob. Re-run with the inner string single-quoted (semantically the intended test):
   ```
   NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e "say(nqp::getcomp('nqp').eval('my \$y := 5; \$y * 3'))"
   ```
   → `15`. Expected value reached; the runtime EVAL takes the record road and returns correctly.

3. ```
   NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'say(1)' 2>&1 | head -2
   ```
   →
   ```
   unit artifact (NQP_UNIT): the road needs NQP_CODE_RUN=1 and NQP_CODE_PRECOMP=1 set, every block must encode
     in as_jast (NQP::src/vm/jvm/QAST/Compiler.nqp)
   ```
   The knob check fires once, before any block.

4. ```
   RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle nqp/t/nqp/123-unit-artifact.t
   ```
   →
   ```
   1..8
   ok 1 - compiled the module on the artifact road
   ok 2 - the jar carries unit.meta
   ok 3 - the jar carries no class entry
   ok 4 - a sub from the artifact runs
   ok 5 - a closure over the mainline keeps its outer
   ok 6 - a handler in an artifact block catches
   ok 7 - a regex from the artifact matches
   ok 8 - and fails to match
   ```

Extra check (not in the brief) that the knob stays opt-in:
`RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'say(6*7)'` → `42`,
i.e. with `NQP_UNIT` unset the class road still compiles and runs against artifact-built stage jars.

## Files changed

- `nqp/src/vm/jvm/QAST/Compiler.nqp` (+41 −18 net across five hunks)
- `nqp/src/vm/jvm/HLL/Backend.nqp` (the `classfile` junction)
- `nqp/src/vm/jvm/QAST/TruffleEncoder.nqp` (`splice_code` + four call sites)
- `nqp/src/vm/jvm/QAST/JASTNodes.nqp` (one comment line)

Total `git diff cfa0846ac..HEAD --stat`: 4 files, 78 insertions, 60 deletions.

## Self-review

- **Every splice site replaced.** `grep -n 'nqp::splice(%e<code>' TruffleEncoder.nqp` returns exactly
  one line — 925, the body of `splice_code`. No shift loop over `%e<nested>` survives outside it.
- **Shift-rule equivalence holds.** Sites 1 and 2 shifted when `$nb[0] > $params_at`; over integer
  positions that is exactly `$nb[0] >= $params_at + 1`, and both call the helper with
  `$at = $params_at + 1`, whose rule is `$nb[0] >= $at`. Sites 3 and 4 shifted when
  `$nb[0] >= $mark` and call with `$at = $mark`. The amount shifted also matches: sites 1/2 added
  `nqp::elems(@hdr)` / `nqp::elems(@p)`, the helper adds `nqp::elems(@words)` for the same list;
  sites 3/4 added the literal 2 for the two-word `[$W_COERCE, $kind]`, which is `nqp::elems` of that
  list. So the helper is behaviour-preserving at all four sites, not merely equivalent at three.
- **No bare prints.** The one `nqp::say` in the added/changed lines is the pre-existing census line,
  still guarded by `if nqp::existskey(nqp::getenvhash(), 'NQP_CODE_WHY');`.
- **Nothing beyond the brief.** The diff contains only the five steps' edits. The only textual
  latitude taken was rewrapping the `deserialization_code` comment to the file's column width (the
  brief gave the replacement as a sentence fragment spanning a wrapped line) and placing
  `sub splice_code` above `patch_params`'s doc comment rather than between comment and method.
- **Class road untouched when the knob is off.** `$!unit_road` is a native `int` initialised to 0, so
  `if $jast.unit_road` in `Backend.nqp` is false for every non-knob compile, and the two following
  branches are the previous `if`/`else` verbatim. Confirmed empirically by the extra `say(6*7)` run.

## Concerns

1. **The brief's smoke 2 command cannot pass as written** (NQP interpolates `$y` in the outer
   program). I ran the corrected single-quoted form and got the expected `15`. If the controller
   wants the literal command in the record, it will always print the `undeclared variable` SORRY.
   Worth fixing in the brief/spec for milestone 3.
2. **Jar count is 11, not the 12 the brief expected.** All eleven are artifacts. I did not find a
   twelfth jar anywhere under `build/jvm/share/lib`, and the stage2 task list accounts for all of
   them, so I believe the brief miscounted rather than a jar going missing — but a controller who
   knows the intended roster should confirm.
3. **`blockvalues` rows on a non-comp-mode unit.** Step 2 makes the wrapper exist whenever
   `$*UNIT_ROAD && %*BLOCK_LEX_VALUES`, including for a plain script or EVAL. The row builder calls
   `nqp::getobjsc(@lex[1])` and then `nqp::scgethandle($sc)`; for a unit that never serializes, an
   object with no SC would make that null. Nothing in the smokes hit it (no non-comp-mode unit in
   them carried static lexical values), and the row builder is Task 1 code that the brief did not ask
   me to change, so I left it alone — flagging it as the most likely place a milestone-3 Rakudo run
   trips.
4. Only the nqp stage build was exercised. No Rakudo build or spectest was run under `NQP_UNIT`
   (out of scope for this task, and the brief forbade any other clean build).
