# Task 7 report — the writer, its syscall, the backend road, the end-to-end test

Status: **DONE**. The artifact road ran end to end for the first time: all ten
nqp stage2 targets plus NQPP5QRegex are unit artifacts (`unit.meta`, zero
`.class`), the runner enters them through `UnitMain`, and `t/nqp/123` compiles
a module on the artifact road and runs a sub, a closure, a handler and a regex
back out of it.

Commits (nqp tree, `/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp`):

- `4e136970e` unit artifact: the writer (JAST record -> zip), jvm-write-unit, the backend's artifact road, t/nqp/123
- `57460ccd7` unit artifact: encode QAST::VM (the jvm alternative); a buffered write no longer NUL-pads the file

## What I implemented

**Step 1 — readers for the new fields.**
`src/vm/jvm/runtime/org/raku/nqp/jast2bc/JastClass.kt`: thirteen new fields
(`hll`, `mainlineQbid`, `entryQbid`, `deserializeQbid`, `loadQbid`,
`serializedCount`, `scHandle`, `scDesc`, `fallbacks`, `unitRoad`, `programs`,
`callsites`, `blockvalues`), read in one guarded block after the nested-classes
read, with matching hints in the companion and `setup`.
`JastMethod.kt`: `crQbid` / `crProgram`, likewise guarded, with hints.
`JASTCompiler.kt`: `ensureSetup(jastNodes, tc)` beside the private `setup`, so
the writer can prime the hints without going through `compileClass`.

**Step 2 — `UnitWriter`.**
`src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitWriter.kt`, as the brief
specified. It refuses a unit that is not on the artifact road, one with
fallback bodies, and one carrying nested classes; it builds the qbid-indexed
`BlockRec` table from the JAST methods that are code refs (`crOuter != -2`),
reads `@!programs` / `@!callsites` / `@!blockvalues` as data, and writes the zip
through `UnitZip.write`. Deviations from the brief's literal text, all
mechanical:

- `write` takes nullable `jast` / `jastNodes` / `filename` and rejects nulls,
  because `SyscallArgs.obj()` / `.str()` return nullable types.
- The two inner iterator variables are named `csIter` / `bvIter`; the brief's
  `it` shadowed the lambda parameter used inside the `ByteArray(...)` initializer.
- `m.crSectionFile?.let { f -> Array(f.size) { f[it] ?: "" } }` in place of
  `?.map{}?.toTypedArray()` (the same result, one allocation).
- `jc.hll?.ifEmpty { null } ?: "nqp"` rather than `jc.hll ?: "nqp"`: the JAST
  node initializes `$!hll` to `''`, never null, so a plain elvis would have put
  an empty HLL name in the meta.
- The `Base64` import the brief listed is unused (JastClass already decodes) and
  is not there.
- One env-gated line at the end (`NQP_CODE_WHY`, on stderr) naming the unit,
  the file, and the program / qbid / call-site counts. stderr, not stdout,
  so it cannot corrupt a task that parses a compile's stdout.

**Step 3 — the syscall.** `jvm-write-unit(OBJ, OBJ, STR)` in
`dispatch/Syscalls.kt`, shaped like `jvm-claim-nested`, placed just before it.

**Step 4 — the backend road.** `src/vm/jvm/HLL/Backend.nqp`: on
`--target=jar` with `$jast.unit_road` and no `$jast.fallbacks`, the syscall;
otherwise `nqp::compilejasttofile` unchanged.

**Step 5 — the test.** `t/nqp/123-unit-artifact.t`, 8 tests. It differs from
the brief's sketch in three ways forced by the code as it actually is:

- There is no `nqp::shell` op on this branch and `run-command` (src/core/testing.nqp)
  passes `nqp::getenvhash` rather than a caller-supplied env, so both child
  processes go through `run-command(['/bin/sh', '-c', ...])` and `NQP_UNIT=1` is
  set on the command line. The file skips all 8 on Windows and on a non-JVM backend.
- The jar's entry names are checked by reading the file with `nqp::readfh` into a
  uint8 buffer and `nqp::decode(..., 'iso-8859-1')` — a zip keeps entry names in
  plain bytes — rather than shelling out to `unzip`.
- `use UnitMod` resolves its symbols while the test file itself is compiling,
  long before the jar exists, so the four behaviour assertions run in a second
  child (`./nqp-j-gradle --module-path=<tmp> use-unitmod.nqp`) whose five stdout
  lines are compared. `--module-path` + `ModuleLoader.load_module`'s
  `<prefix>/<name>.jar` probe is the road the spec's loader hooks into, so this
  exercises exactly what it should.
- The test cleans up its temp directory on success.

The runner default follows `NQP_TEST_RUNNER`, else `./nqp-j-gradle` when the cwd
has one (t/nqp runs from the nqp checkout), else `nqp/nqp-j-gradle`.

## Build attempts

All four went through `raku tools/build/watched-run.raku` from the rakudo
worktree root with a fresh log per attempt; the `EXIT=` line is quoted for each.

### Attempt 1 — `build-task7.log` — `=== EXIT=1 verdict=ok elapsed=142s ===`

`clean buildJvm`. Reached the writer on the very first stage2 unit and failed
inside the syscall's own argument check:

```
code unit D066781743C063D84243AC196A05D2511875EC69 -> artifact
Argument 2 to the 'jvm-write-unit' syscall is a obj, but should be a str
  in classfile (NQP::src/vm/jvm/HLL/Backend.nqp:86)
```

`%adverbs<output>` is a boxed string, and `Syscall.checkArgs` compares the
call site's argument flags, not the runtime value. **Fix:** bind it to a
native `my str $unit_output` in `Backend.nqp` and pass that.

### Attempt 2 — `build-task7b.log` — `=== EXIT=1 verdict=ok elapsed=30s ===`

`buildJvm` without `clean`, to save the 2.5 minutes of stage1. Gradle re-ran
`stage1CompileHll` (so the `Backend.nqp` edit *is* tracked) but not the stage1
jars downstream of it, and stage2 died on the dependency-version check:

```
Unhandled exception: java.lang.RuntimeException: Missing or wrong version of
dependency '.../nqp/build/jvm/stage1/NQPHLL.nqp'
```

The stage-graph edge miss CLAUDE.md warns about. **Fix:** none in the source;
`clean` on every subsequent attempt.

### Attempt 3 — `build-task7c.log` — `=== EXIT=1 verdict=ok elapsed=174s ===`

`clean buildJvm`. Three stage2 units were written as artifacts —

```
unit artifact ... -> build/jvm/stage2/ModuleLoader.jar     (16 programs, 16 qbids, 0 call sites)
unit artifact ... -> build/jvm/stage2/nqpmo.jar            (246 programs, 246 qbids, 0 call sites)
unit artifact ... -> build/jvm/stage2/NQPCORE.setting.jar  (196 programs, 196 qbids, 0 call sites)
```

— and, notably, `stage2CompileNqpmo` then *loaded* the artifact `ModuleLoader.jar`
through `--module-path`, so the loader road was already working. `stage2CompileJastNodes`
died under `NQP_CODE_STRICT`:

```
code why <anon 120> cuid 120 blocktype raw comp_mode 1 exith 0 -> no: bail code-bail node QAST::VM
  in cbail (NQP::src/vm/jvm/QAST/TruffleEncoder.nqp)
  ...
  in as_jast (NQP::src/vm/jvm/QAST/Compiler.nqp:4231)   # the deserialize wrapper
```

A genuine encoder gap, and the first one that only the artifact road can hit:
the deserialize wrapper carries `World.nqp`'s load-dependency task, which names
`ModuleLoader.class` inside a `loadbytecode` through a `QAST::VM` node
(`src/NQP/World.nqp:101`). On the class road that node never reached the
encoder because the wrapper blocks were bytecode. **Fix:** a `QAST::VM` branch
in `TruffleEncoder.encode_node`, doing exactly what `as_jast(QAST::VM)`
(`Compiler.nqp:5294`) does — take the `jvm` alternative, bail if there is none.
No change was needed on the loader side: `LibraryLoader` already falls back from
`<cp>/ModuleLoader.class` to `<cp>/ModuleLoader.jar`, which is the artifact.

### Attempt 4 — `build-task7d.log` — `=== EXIT=0 verdict=ok elapsed=292s ===`

`clean buildJvm`, **BUILD SUCCESSFUL in 4m 52s** (wall time 292 s). Every stage2
target came out as an artifact, and the last task (`compileP5qregex`) produced
`NQPP5QRegex.jar` by running the *new* runner — `UnitMain` on the artifact
`nqp.jar` — which is the first end-to-end proof that an artifact unit can host
the compiler.

| unit | programs | qbids | call sites |
|---|---|---|---|
| ModuleLoader.jar | 16 | 16 | 0 |
| nqpmo.jar | 246 | 246 | 0 |
| NQPCORE.setting.jar | 196 | 196 | 0 |
| JASTNodes.jar | 125 | 125 | 0 |
| QASTNode.jar | 220 | 220 | 0 |
| QRegex.jar | 188 | 188 | 0 |
| NQPHLL.jar | 383 | 383 | 0 |
| QAST.jar | 356 | 356 | 0 |
| NQPP6QRegex.jar | 310 | 310 | 0 |
| nqp.jar | 571 | 571 | 0 |

Zero call sites everywhere is expected and not a defect: the call-site table
existed for the bytecode `indy` sites, and on the artifact road every block is
an engine program that carries its own dispatch. Nothing indexes
`cu.callSites` at run time on this road — the whole build and the whole test
file run through it.

### Per-jar check

Every stage2 jar and every share/lib jar: `unit.meta` count 1, `.class` count 0.

| jar | unit.meta | .class |
|---|---|---|
| build/jvm/stage2/JASTNodes.jar | 1 | 0 |
| build/jvm/stage2/ModuleLoader.jar | 1 | 0 |
| build/jvm/stage2/NQPCORE.setting.jar | 1 | 0 |
| build/jvm/stage2/NQPHLL.jar | 1 | 0 |
| build/jvm/stage2/NQPP6QRegex.jar | 1 | 0 |
| build/jvm/stage2/QAST.jar | 1 | 0 |
| build/jvm/stage2/QASTNode.jar | 1 | 0 |
| build/jvm/stage2/QRegex.jar | 1 | 0 |
| build/jvm/stage2/nqp.jar | 1 | 0 |
| build/jvm/stage2/nqpmo.jar | 1 | 0 |
| build/jvm/share/lib/JASTNodes.jar | 1 | 0 |
| build/jvm/share/lib/ModuleLoader.jar | 1 | 0 |
| build/jvm/share/lib/NQPCORE.setting.jar | 1 | 0 |
| build/jvm/share/lib/NQPHLL.jar | 1 | 0 |
| build/jvm/share/lib/NQPP5QRegex.jar | 1 | 0 |
| build/jvm/share/lib/NQPP6QRegex.jar | 1 | 0 |
| build/jvm/share/lib/QAST.jar | 1 | 0 |
| build/jvm/share/lib/QASTNode.jar | 1 | 0 |
| build/jvm/share/lib/QRegex.jar | 1 | 0 |
| build/jvm/share/lib/nqp.jar | 1 | 0 |
| build/jvm/share/lib/nqpmo.jar | 1 | 0 |

21 of 21 conforming, 0 non-conforming.

### Smoke

```
$ RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'say(6*7)'
42
```

## t/nqp/123

First run — `t123-1.log`, `not ok 1`. The generated module source would not
parse: `Confused at line 12`. `cat -A` showed the file ended in a run of NUL
bytes after the last line. A three-line reproduction outside the test confirmed
it was not the test's doing:

```
$ ./nqp/nqp-j-gradle -e 'my $fh := nqp::open("/tmp/wtest.txt","w"); nqp::printfh($fh, "hello\nworld\n"); nqp::closefh($fh);'
$ cat -A /tmp/wtest.txt
hello$
world$
^@
```

`SyncHandle.write` (`src/vm/jvm/runtime/org/raku/nqp/io/SyncHandle.kt:277`) did
`wb.put(buffer.array())` — the *whole backing array* of the encoded buffer. A
`CharsetEncoder`'s output buffer is allocated at `maxBytesPerChar` per char and
only its `limit()` is content, so the slack went into the file as NUL padding.
A pre-existing bug (this code long predates the campaign), invisible until now
because almost nothing in the build writes a file from NQP. **Fix:**
`wb.put(buffer)`, and `toWrite = buffer.remaining()` rather than `limit()` so a
buffer with a position is also handled. Runtime-only rebuild, ~10 s.

Second run — `t123-2.log`, `=== EXIT=0 verdict=ok elapsed=10s ===`:

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

Regression check on the I/O fix — `t123-3.log`, `=== EXIT=0 verdict=ok elapsed=20s ===`:

```
t/nqp/019-file-ops.t ....... ok
t/nqp/123-unit-artifact.t .. ok
t/nqp/113-run-command.t .... ok
All tests successful.
Files=3, Tests=128
```

Kotlin unit tests (`:nqp-runtime:test`), before and after the runtime change:
9 tests, 0 failures (`UnitFormatTest` 5, `ProgramUnitTest` 4).

## Files changed

Commit `4e136970e`:

- `nqp/src/vm/jvm/runtime/org/raku/nqp/jast2bc/JastClass.kt` — 13 record fields, guarded read, hints
- `nqp/src/vm/jvm/runtime/org/raku/nqp/jast2bc/JastMethod.kt` — `crQbid`, `crProgram`, guarded read, hints
- `nqp/src/vm/jvm/runtime/org/raku/nqp/jast2bc/JASTCompiler.kt` — `ensureSetup`
- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitWriter.kt` — new
- `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/Syscalls.kt` — `jvm-write-unit`
- `nqp/src/vm/jvm/HLL/Backend.nqp` — the artifact road
- `nqp/t/nqp/123-unit-artifact.t` — new

Commit `57460ccd7`:

- `nqp/src/vm/jvm/QAST/TruffleEncoder.nqp` — `QAST::VM` encoding
- `nqp/src/vm/jvm/runtime/org/raku/nqp/io/SyncHandle.kt` — the NUL-padding fix

## Self-review

- **Every accessor and signature was checked against the real code before use.**
  `JAST::Class` / `JAST::Method` carry exactly the attributes the brief names
  (`src/vm/jvm/QAST/JASTNodes.nqp:4-105, 155-...`); `UnitMeta` / `BlockRec` /
  `CallSiteRec` / `LexValueRec` / `UnitRecord` take exactly the arguments the
  brief passes; `UnitZip.write(record, out)` matches. No NEEDS_CONTEXT.
- **`crHandlers` framing.** `BlockRec.handlers` is documented as
  `[count, (len, fields...)*]` and `ProgramUnit.unflatten` reads `flat[0]` as a
  count. Compiler.nqp always writes at least `[count]`
  (`Compiler.nqp:4919-4924`, in the per-block `as_jast`), so `unflatten` cannot
  run off an empty array. Verified rather than assumed.
- **`m.crOuter == -2` is the right filter.** The generated non-code-ref methods
  (`hllName`, `mainlineQbid`, `entryQbid`, `deserializeQbid`, `loadQbid`,
  `getCallSites`, `main`) never set `cr_outer`, whose BUILD default is -2. The
  qbid/program guards below it would have fired loudly if any code ref slipped
  past, and none did across 2411 blocks in ten units.
- **The `fallbacks` and `unitRoad` guards are dead by design** (controller
  ruling 1: Compiler.nqp dies at the fallback junction, so `fallbacks` is always
  0). Kept as the brief asks, as defence.
- **Bounded blast radius of the two out-of-brief fixes.** The `QAST::VM` branch
  sits last in `encode_node`, after every existing `istype` test, so no node
  that encoded before changes road; it bails rather than dies when there is no
  `jvm` alternative, matching the campaign's convention. The `SyncHandle` change
  is two lines and strictly narrows what is written; `t/nqp/019-file-ops.t`
  (112 assertions, most of them file writes and reads) passes.
- **Diagnostics are env-gated**, on stderr, per the standing rule.
- **The test cleans up after itself** and skips rather than failing where its
  `/bin/sh` road does not exist.

## Concerns

1. **The build is not idempotent without `clean`.** Attempt 2 proved the stage
   graph misses the edge from `stage1CompileHll` to the stage1 jars that depend
   on it, so a `Backend.nqp`-only edit needs a full `clean buildJvm` (~5 min).
   Known and documented in CLAUDE.md for `src/vm/jvm/QAST/*.nqp`; it applies to
   `src/vm/jvm/HLL/` too. Not fixed here.
2. **Zero call sites in every artifact.** Correct for this road, but it means
   the call-site table is currently untested by anything. If a later shape does
   index `cu.callSites` from an engine program, it will find an empty array and
   fail with an index error rather than something legible. Worth a guard when
   milestone 3 brings Rakudo's units over.
3. **`ProgramEntry.ENTER` is one shared method handle for every block.** The
   spec asks for one bound handle per block so that `CallFrame.outerFor`'s
   `staticInfo.mh === wanted.mh` identity test stays exact. It does hold today,
   because `StaticCodeInfo.init` re-binds with `MethodHandles.insertArguments`
   and so each block ends up with a distinct object — but that is an accident of
   the constructor, not a stated invariant. If `insertArguments` is ever skipped
   for the artifact road, closures will silently capture the wrong frame. Task
   1-4 territory; flagging, not touching.
4. **The NUL-padding write bug was live on the class road too.** Anything that
   ever wrote a file from NQP through a buffered handle produced trailing NULs.
   Worth mentioning to whoever tracks upstream-divergence: this is not
   artifact-specific.
5. **`t/nqp/123` starts two JVMs** and takes ~10 s. Acceptable for one file;
   if the pattern spreads, the suite will feel it.
6. **Not run here:** the full `t/nqp` sweep (the spec's per-change gate item 3)
   and the Rakudo `make` + `t/01-sanity` post-completion gate. Both are outside
   this task's job list; the milestone owner should run them before calling
   milestone 1 done.
