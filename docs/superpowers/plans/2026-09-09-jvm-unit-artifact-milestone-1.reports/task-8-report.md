# Task 8 report: Runners enter through UnitMain

## What changed

Both generated-runner sources now exec `org.raku.nqp.runtime.unit.UnitMain`
with the unit path as its first argument, before `"$@"`, so program
arguments (e.g. `-e ...`) still reach the actual program via `UnitMain`'s
argv-shifting.

### 1. `nqp/buildSrc/src/main/kotlin/GenerateRunnerTask.kt` (Gradle-generated `nqp-j-gradle`)

The brief's literal instruction assumed a shell variable `$LIB_DIR` exists in
the generated script. It does not: this Kotlin task has no `setenv`/export
step. The lib directory only exists as the Kotlin `val lib = libDir.get()`
(line 50), which the existing code already bakes into the script directly via
plain Kotlin interpolation (not `${'$'}`-escaped) — e.g. line 72
`CP="$lib:${engineJar.get()}"` and line 78 `CP="$lib"`. Per the brief's own
fallback instruction ("if it is different, use the one that exists and say so
in the report"), I used that same pattern: `"$lib/nqp.jar"` (Kotlin
interpolation, baked in at generation time as an absolute path), not a
runtime shell variable.

Line 140, before:
```
|exec java ... -cp "${'$'}CP" nqp "${'$'}@"
```
after:
```
|exec java ... -cp "${'$'}CP" org.raku.nqp.runtime.unit.UnitMain "$lib/nqp.jar" "${'$'}@"
```

Generated tail line (from `nqp/nqp-j-gradle`, confirmed after regeneration):
```
... -cp "$CP" org.raku.nqp.runtime.unit.UnitMain "/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp/build/jvm/share/lib/nqp.jar" "$@"
```

### 2. `nqp/tools/templates/jvm/nqp-j.in` (Makefile-road template, generates the installed `nqp-j`)

Here `$LIB_DIR` genuinely exists — line 33 (`@setenv(LIB_DIR)@@q(@lib_dir@)@`)
sets it as a real exported shell variable, and `@envvar(LIB_DIR)@` already
expands to `$LIB_DIR` references elsewhere on the same exec line (e.g. in the
bootclasspath). So this file's edit followed the brief exactly, verbatim.

Last line, before:
```
-cp "@cur_dir@@envvar(LIB_DIR)@" nqp "@sh_allparams@"
```
after:
```
-cp "@cur_dir@@envvar(LIB_DIR)@" org.raku.nqp.runtime.unit.UnitMain "@cur_dir@@envvar(LIB_DIR)@/nqp.jar" "@sh_allparams@"
```

## Commands and output

Regenerate (gradle dir; already up to date from an earlier background run,
re-ran in foreground to confirm):
```
$ cd .../nqp && ./gradlew generateRunner 2>&1 | tail -10
...
> Task :syncLib
> Task :syncRuntimeJars UP-TO-DATE
> Task :generateRunner UP-TO-DATE
BUILD SUCCESSFUL in 30s
```

Tail of generated script (`tail -3 nqp/nqp-j-gradle`) confirmed
`org.raku.nqp.runtime.unit.UnitMain "<lib>/nqp.jar" "$@"` at the end of the
`exec java` line, with the unit path baked in before `"$@"`.

Smoke test (from the rakudo worktree root):
```
$ RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'say(nqp::x("ab", 3))'
ababab
```
Matches the expected output exactly — confirms `UnitMain` loads `nqp.jar`
(class road, since Task 9's artifact writer hasn't landed yet) and that
`-e '...'` still reached the program through argv shifting.

## Verify: argv ordering and variable name

- `UnitMain`'s argv[0] is the unit path; everything after is the program's
  own args. Both edited exec lines place the unit-path argument
  (`"$lib/nqp.jar"` / `"@cur_dir@@envvar(LIB_DIR)@/nqp.jar"`) immediately
  before `"${'$'}@"` / `"@sh_allparams@"`, so `-e '...'` is still passed
  through unchanged — confirmed working by the smoke test above.
- Variable-name check: `nqp-j.in`'s `$LIB_DIR` is real (exported via
  `@setenv(LIB_DIR)@`) — brief's text used as-is. `GenerateRunnerTask.kt` has
  no such shell variable; I used the Kotlin `lib` value already used
  identically elsewhere in the same generator (see above) instead of a
  nonexistent `${'$'}{LIB_DIR}`.

## Files changed

- `nqp/buildSrc/src/main/kotlin/GenerateRunnerTask.kt` (line 140)
- `nqp/tools/templates/jvm/nqp-j.in` (last line)

Both committed in the nqp tree (its own git repo) as commit `15c20930c`:
"runners enter through UnitMain (either road)", with the two required
trailer lines. `git status --short` in the nqp tree is clean after the
commit; only the two brief-named files were staged and committed.

## Self-review

- Diff is minimal and exactly targeted — one line changed per file, nothing
  else touched.
- No debug prints added (none needed).
- No new Kotlin logic beyond string interpolation already present in the
  file's own style — consistent with existing patterns (`$lib` used the same
  way at lines 72/78).
- Deviation from the brief's literal text in file 1 is intentional and
  required by the brief's own contingency instruction; documented above and
  in this report. File 2 followed the brief verbatim since its `$LIB_DIR`
  actually exists.
- Smoke test passed on first try; no rebuild issues, no stale-jar concerns
  (this only touches runner shell-script generation, not any jar contents).
- `nqp-j-gradle`'s regeneration was already current from the background run
  before I re-ran it in the foreground per instruction from teammate
  `im-curious-as`; foreground re-run confirmed UP-TO-DATE / BUILD SUCCESSFUL,
  no drift.

## Concerns

None blocking. Worth flagging for the plan owner: the Makefile-road
`nqp-j.in` template was edited but not regenerated/smoke-tested here (the
brief's Step 2 only names the gradle regeneration + `nqp-j-gradle` smoke);
the Makefile road presumably gets exercised by a full `make` build, which is
out of scope for this task per the brief.
