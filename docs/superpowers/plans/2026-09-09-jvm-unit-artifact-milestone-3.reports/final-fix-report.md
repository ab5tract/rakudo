# Milestone 3 — final-review fix wave

One dispatch, five findings plus the fold-ins. Base: rakudo
`5d1a3845f0` (branch `worktree-jesp-direct-lazy-records`), nqp
`30e849e3c` (branch `jesp-direct-lazy-records`).

Build for the wave: runtime jars only —
`./nqp/gradlew -p nqp :nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars`,
BUILD SUCCESSFUL in 31 s (`:nqp-runtime:test` green; `:buildSrc:jar`
recompiled for the `GenerateRunnerTask` edit). No stage build: the
`.nqp` edits are comment-only (`git diff` on
`nqp/src/vm/jvm/QAST/{TruffleEncoder,Compiler}.nqp` shows only added or
reworded `#` lines).

## CRITICAL 1 — the runtime's `$!codeprograms` pass-through, restored

Task 4 removed the pass-through on the ground that "no compiler emits a
sidecar since milestone 3". False for stage0: `nqp/src/vm/jvm/stage0/`
is a class-road compiler from nqp `48f1e0147`, its encoder is opt-in by
the mere PRESENCE of `NQP_CODE_RUN`, and gradle's stage tasks inherit
the environment — so with `NQP_CODE_RUN` exported, stage1's jars need
`<name>.codeprograms.lz4` and the first engine-bodied call would die in
`CompilationUnit.loadEnginePrograms`.

Restored, byte for byte as at nqp `8bab02391`:

- `nqp/src/vm/jvm/runtime/org/raku/nqp/jast2bc/JastClass.kt:13` — the
  `codePrograms: String?` field.
- `JastClass.kt:52-57` — the guarded
  `Ops.getattr_s(jast, jastClass, "$!codeprograms", codeProgramsHint, tc)`
  in a `try`/`catch (t: Throwable)` ("A version of the node without the
  field").
- `JastClass.kt:99` and `:121` — `codeProgramsHint` and its
  `hint_for(..., "$!codeprograms")` in `setup`. Safe for the new
  compiler's node: `P6Opaque.hint_for` answers `STable.NO_HINT` for an
  unknown attribute (`P6Opaque.kt:722`), it does not throw.
- `nqp/src/vm/jvm/runtime/org/raku/nqp/jast2bc/JASTCompiler.kt:238-242` —
  `c.codePrograms = jastClass.codePrograms?.toByteArray(Charsets.UTF_8)`,
  with the comment replaced by the wording the finding asked for ("The
  NEW compiler (milestone 3) has no `$!codeprograms` … until milestone 4
  regenerates stage0.").

The writer at `JASTCompiler.kt:119-132` was untouched and emits the
`<name>.codeprograms.lz4` entry whenever `c.codePrograms != null`.

### Probe

`/home/longwalker/.claude/jobs/288cfddd/tmp/fixwave/Probe.nqp` — two
blocks (a sub and a mainline calling it) — compiled by STAGE0's compiler
with gradle's `registerStage` command line (main class `nqp`, classpath
`stage0` + `nqp-truffle.jar`, `-Xbootclasspath/a:` = stage0 dir +
`nqp-runtime.jar` + the seven third-party jars + `stage0/nqp.jar`,
`--module-path` at `build/jvm/share/truffle`, `--bootstrap
--module-path=<stage0> --setting-path=<stage0> --setting=NQPCORE
--no-regex-lib --target=jar --output=…`) with `NQP_CODE_RUN=1
NQP_CODE_PRECOMP=1` in the environment. Driver:
`/home/longwalker/.claude/jobs/288cfddd/tmp/fixwave/probe.raku`.

    == stage0 compile (NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1, --target=jar) ==
    compile ok

    == unzip -l ==
    Archive:  /home/longwalker/.claude/jobs/288cfddd/tmp/fixwave/Probe.jar
      Length      Date    Time    Name
    ---------  ---------- -----   ----
           79  2026-09-10 10:34   META-INF/MANIFEST.MF
        10858  2026-09-10 10:34   9FEB1C3BF2C7F1EA6F6C9D7CA3F1223210A0CADC.class
          267  2026-09-10 10:34   9FEB1C3BF2C7F1EA6F6C9D7CA3F1223210A0CADC.serialized.lz4
          546  2026-09-10 10:34   9FEB1C3BF2C7F1EA6F6C9D7CA3F1223210A0CADC.codeprograms.lz4
    ---------                     -------
        11750                     4 files

    == run the jar mainline through the runtime ==
    probe sub says 42
    probe mainline done
    exit 0

The `.codeprograms.lz4` entry is present and the jar's mainline runs
through `org.raku.nqp.runtime.unit.UnitMain` on the fixed runtime. (The
"before" run was not made; the finding did not require it, and the cut
code path made `c.codePrograms` unconditionally null, so no entry could
have been written.)

## IMPORTANT 3 — the per-call exit-handler check leaves the fast path

`nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt`
`frameFreeEntryOk` (was ~962-964): the
`if (NqpRaw.staticInfo(cr).hasExitHandler) return false` line ran per
call on every frame-free candidate and could never fire — the encoder
forces `needsFrame` for an exit-handler block, and `frameFreeEntryOk` is
only reached when `!root.needsFrame`. Removed.

The invariant is now enforced once. There is no pairing point in
`CodeEngine.kt`: `CodeEngines.materialize(sci)` answers an opaque
`Any?` and nqp-runtime cannot name `NqpRootNode` (the engine is loaded
reflectively). The one place a CodeRef DOES meet its program root, once,
is `NqpCodeEngine.runProgram`'s first-run block (`root.blockName == null`,
`nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpCodeEngine.java:53-62`)
— where `NqpFrameFree.apply` already runs. Added there:

- `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpFrameFree.kt:17-33`
  (Kotlin, per the project rule) — `checkExitHandler(root, cr)` throws
  `IllegalStateException("exit-handler block encoded frame-free: <name>")`
  when `sci.hasExitHandler && !root.needsFrame`.
- `NqpCodeEngine.java:57-61` calls it BEFORE `NqpFrameFree.apply`, so
  forcing a block framed with `NQP_FRAMEFREE*` cannot mask an encoder
  disagreement.

Caveat for the record: a root first reached by the frame-free direct
road would skip this, but `NqpFrameFree`'s own contract is that a block's
first run is through the bytecode stub, with a frame, before any direct
road adopts its target.

Gate: `RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=t/01-sanity
--jobs=2 -- ./rakudo-j`

    25 of 25 ok in 145s, logs: /home/longwalker/.claude/jobs/288cfddd/tmp/fixwave/sanity-logs

    ok 25 of 25
    elapsed 145s
    runner ./rakudo-j

## IMPORTANT 4 — `watched-run --follow` ends on a `-t` digest

`tools/build/watched-run.raku`. A `-t` run's digest carries one
file-TAGGED `"<file> === EXIT=…"` line per file and no whole-run EXIT
line, so a `--follow` on it never ended.

- `:322-325` — the `-t` summary verdict line (`N of M ok in Ss, logs: DIR`)
  is now written into the digest as well as `note`d to the terminal.
- `:217-231` (`follow-log`) — the run ends on either an unanchored
  `=== EXIT=` match whose `prematch` is empty (single mode: no file tag),
  or the summary line (`-t` mode), exiting 0 when `N == M` and 1
  otherwise.
- Header `--follow` paragraph (`:13-20`) and `follow-log`'s own comment
  (`:174-178`) say so.

Single mode:

    markers: …/s.markers
    log: …/s.log
    [0s]   hello
    ok, exit 0, log: …/s.log
    --- digest ---
    [0s]   hello
    === EXIT=0 verdict=ok elapsed=0s ===
    --- follow ---
    following: …/s.markers
    [0s]   hello
    === EXIT=0 verdict=ok elapsed=0s ===
    follow exit=0

`-t` mode (two one-`ok` .t files):

    --- digest ---
    [0s]   b.t ok 1 - marker beta
    [0s]   a.t ok 1 - marker alpha
    b.t === EXIT=0 verdict=ok elapsed=0s ===
    a.t === EXIT=0 verdict=ok elapsed=0s ===
    2 of 2 ok in 0s, logs: …/t-logs
    --- follow ---
    following: …/t.markers
    [0s]   b.t ok 1 - marker beta
    [0s]   a.t ok 1 - marker alpha
    2 of 2 ok in 0s, logs: …/t-logs
    follow exit=0

The tagged per-file EXIT lines did not end the follow, and the failing
branch answers non-zero (one file exiting 3):

    following: …/t2.markers
    1 of 2 ok in 0s, logs: …/t2-logs
    follow exit=1

## IMPORTANT 2 — the encoder switches are not opt-outs (docs)

Reworded to: the encoder and the unit road are always on;
`NQP_CODE_RUN`/`NQP_CODE_PRECOMP` must not be set at all (the compiler
dies on `=0`; stage0's bootstrap compiler treats their mere presence as
"encode", so a gradle build exporting them builds stage1 differently);
the surviving knobs are the diagnostics `NQP_CODE_ENCODED`,
`NQP_CODE_BAIL`, `NQP_CODE_WHY`, `NQP_CODE_STRICT`.

- `AGENTS.md:17-25` (the `RAKUDO_RAKUAST=1` paragraph) — and the flip
  date corrected from 2026-09-10 to **2026-09-09** (nqp `388173781`).
- `docs/jvm-eval-server.md:55-62` (the knob sentence). The 2026-09-10 in
  the "what a whole `t/` costs" heading is the sweep's own date and
  stays.
- `nqp/src/vm/jvm/QAST/TruffleEncoder.nqp:408-415` — comment only, code
  unchanged.
- `nqp/src/vm/jvm/QAST/Compiler.nqp:4108-4114` — comment added above the
  road-decision `nqp::die`, code unchanged.

## IMPORTANT 5 — the generated runner's comment

`nqp/buildSrc/src/main/kotlin/GenerateRunnerTask.kt:68-69`: "(with
NQP_CODE_RUN) every block runs on it" → "Every regex and every block runs
on it (the encoder is always on since milestone 3)". buildSrc recompiled
on the next gradle invocation, as expected.

## Fold-ins

The four `NQP_UNIT` comments, reworded to "the unit road" with no knob
named:

- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/EvalResult.kt:8`
- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/GlobalContext.kt:236-237`
- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt:9046`
- `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/Syscalls.kt:486-489`

Tests, `NQP_UNIT=1` dropped from headers and commands and
`NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1` dropped from 124's child commands
(the `NQP_CODE_RUN=0` refusal test stays):

- `nqp/t/nqp/123-unit-artifact.t:1-7`, `:69`
- `nqp/t/nqp/124-unit-record.t:1-5`, `:60`, `:78`, `:87`

Both green through `nqp/nqp-j-gradle`:

    $ RAKUDO_RAKUAST=1 ./nqp-j-gradle t/nqp/123-unit-artifact.t
    1..8
    ok 1 - compiled the module on the artifact road
    ok 2 - the jar carries unit.meta
    ok 3 - the jar carries no class entry
    ok 4 - a sub from the artifact runs
    ok 5 - a closure over the mainline keeps its outer
    ok 6 - a handler in an artifact block catches
    ok 7 - a regex from the artifact matches
    ok 8 - and fails to match

    $ RAKUDO_RAKUAST=1 ./nqp-j-gradle t/nqp/124-unit-record.t
    1..11
    ok 1 - a sub from a record unit runs
    ok 2 - a closure over the mainline keeps its outer
    ok 3 - a handler in a record block catches
    ok 4 - a regex from a record unit matches and fails to match
    ok 5 - an EVAL returns a sub that runs (a record of its own)
    ok 6 - an EVAL of statements answers its value
    ok 7 - a class (a static lexical value) from a record unit resolves
    ok 8 - the script and both EVALs went down the record road (3 records)
    ok 9 - nothing on stderr mentions a class
    ok 10 - the road refuses to run with the encoder switched off, once
    ok 11 - and runs nothing

Documentation, the three copies kept consistent:

- `docs/jvm-truffle-only-plan.md` row 8 — the `$!codeprograms`
  pass-through named as milestone-4 work with the stage0 reason, the
  resume-value gap added, and the two items now done noted as "done in
  milestone 3's final-review fix wave".
- `docs/superpowers/specs/2026-09-09-jvm-unit-artifact-design.md` item 4
  — the two done items removed from the list and recorded as done in the
  fix wave, plus the "must not forget" note about the pass-through and
  `NQP_CODE_*` in gradle builds.
- `docs/superpowers/plans/2026-09-09-jvm-unit-artifact-milestone-3.ledger.md`
  — the "Final review (fable)" line, verbatim as specified.
