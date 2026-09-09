# Task 3 report: t/nqp/124-unit-record.t

## Status: NEEDS_CONTEXT

## What I wrote

`nqp/t/nqp/124-unit-record.t`, transcribed verbatim from the brief
(task-3-brief.md Step 1), following the runner-discovery / `sh()` /
`run-command` shape of `nqp/t/nqp/123-unit-artifact.t` (matches the
brief's model exactly; no adaptation was needed since 123's shape is
identical to what the brief already specifies).

## Runs (both ways, per Step 2)

### From the rakudo worktree root

```
RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle nqp/t/nqp/124-unit-record.t
```

```
1..11
not ok 1 - a sub from a record unit runs
#      got: 'code frame <mainline> -> framed frame_op=1 fdecls=5 lex:$counter lex:&twice lex:&counter lex:&guarded lex:&matches dispatches=19 nested=5 uses_hll=0'
# expected: '42'
not ok 2 - a closure over the mainline keeps its outer
#      got: 'code why <mainline> cuid 3 blocktype  comp_mode 0 exith 0 -> YES: committing 9 decls'
# expected: '1,2'
not ok 3 - a handler in a record block catches
#      got: 'code decl 3 static GLOBALish'
# expected: 'caught boom x'
not ok 4 - a regex from a record unit matches and fails to match
#      got: 'code decl 3 static $?PACKAGE'
# expected: '10'
not ok 5 - an EVAL returns a sub that runs (a record of its own)
#      got: 'code decl 3 static EXPORT'
# expected: '42'
not ok 6 - an EVAL of statements answers its value
#      got: 'code decl 3 lex $counter'
# expected: '15'
not ok 7 - a class (a static lexical value) from a record unit resolves
#      got: 'code decl 3 lex &twice'
# expected: '42'
ok 8 - the script and both EVALs went down the record road (3 records)
ok 9 - nothing on stderr mentions a class
ok 10 - the road refuses to run without the encoder switches, once
ok 11 - and runs nothing
```

### From the nqp directory (as the suite does)

```
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp-j-gradle t/nqp/124-unit-record.t
```

Byte-for-byte identical TAP output to the run above.

## Diagnosis

Subtests 1-7 fail deterministically, not flakily. Subtests 8-11 pass.

I ran the record script by hand exactly as subtest 1's child does
(`RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 NQP_UNIT=1
NQP_CODE_WHY=1 ./nqp/nqp-j-gradle <script>`), capturing stdout and
stderr to separate files. Findings:

- Stderr is clean and exactly as the brief expects: three
  `unit record <id> (<n> programs, <m> qbids)` lines, one per record
  (the script, and its two `nqp::getcomp('nqp').eval(...)` calls), and
  nothing mentioning `.class` or `defineClass`. This is what subtests
  8-11 check, and they pass for the right reason.

- Stdout is NOT clean. Setting `NQP_CODE_WHY=1` triggers two
  independent, pre-existing trace families inside
  `nqp/src/vm/jvm/QAST/TruffleEncoder.nqp`, unrelated to Tasks 1/2's
  new marker, that print to stdout via `nqp::say` for *every* block
  the encoder handles in the process — not just record-road ones:
  - `method why(...)` (TruffleEncoder.nqp ~L668-679): "code why ..." lines,
    one per encode/refuse verdict.
  - the frame-verdict trace inside `encode_block` (TruffleEncoder.nqp
    ~L800-814, guarded by the same `NQP_CODE_WHY` check): "code frame
    ..." lines, plus "code decl ..." lines for committed lexicals, and
    a further "code unit ... -> unit road" line per compiled unit.

  The code comment right above that block is explicit about the
  design: *"NQP_CODE_WHY: the frame verdict with its inputs, per
  block. On stdout like the encode/refuse trace, so never export it to
  make (the gen-cat recipes pipe stdout into generated sources); run
  the one compile you want traced by hand and capture stdout."*

  So `NQP_CODE_WHY=1` is documented, on purpose, to dump a large
  amount of per-block compiler trace onto stdout, deliberately kept
  off the make pipeline's stdout capture. This predates and is
  independent of Task 1/2's new stderr marker (`UnitWriter.kt` L124-127,
  `Ops.kt` L9016-9018), which happens to reuse the same env var name
  for an unrelated, additive stderr line.

  The real script output (`42`, `1,2`, `caught boom x`, `10`, `42`,
  `15`, `42`, in the correct order) IS present in the child's combined
  stdout — I verified it line-by-line in the hand-run capture — but
  it's interleaved with ~40-60 lines of "code frame/why/decl/unit"
  trace ahead of and inside it, so `@out[0]` through `@out[6]` (the
  first 7 lines of stdout) never line up with the say() output the
  test expects there.

This is not a bug in the test file I wrote (transcribed verbatim from
the brief) or in the script under test (every line of expected script
output is present and correct in the captured stdout, just not at the
expected offsets) or in Tasks 1/2's marker code (the stderr side is
exactly right, subtests 8-11 confirm it). It is a structural conflict
in the brief's Step 1 design: it runs the real-output check and the
positive-marker check in the *same* child process
(`NQP_UNIT=1 NQP_CODE_WHY=1 $runner $script`), but `NQP_CODE_WHY=1` on
that process is documented to also flood the very stdout stream the
real-output check parses positionally.

I did not weaken the assertions or restructure the test to route around
this (e.g. splitting into two child processes, or scanning stdout for
the expected lines instead of indexing by position) because the brief
says to transcribe Step 1's test verbatim and adapt only for
runner/`run-command` shape differences — this isn't one of those, and
changing the marker/output split changes what the test actually proves.
That decision needs the task author's sign-off, hence NEEDS_CONTEXT
rather than a silent fix.

## Files changed

- `nqp/t/nqp/124-unit-record.t` (new, untracked; matches the brief's Step 1
  text verbatim). NOT committed — Step 3 is withheld pending the above.

## Self-review

- Every assertion in the file as written asserts real behaviour (no
  assertion was weakened or removed to chase green).
- The positive marker check (subtest 8, `unit record ` count >= 3) is
  present and passes for the right reason.
- The negative-marker check (subtest 9, no `.class`/`defineClass` on
  stderr) is present and passes.
- The knob-refusal checks (subtests 10-11) are present and pass.
- The file cleans up its temp dir/script in the `else` branch
  (`nqp::unlink`/`nqp::rmdir`), matching 123's pattern; the `if`
  (non-JVM/Windows) branch skips before creating anything.
- No stray files were left behind by my diagnosis: `/tmp/124diag/` is
  outside the repo and not part of the commit.

## Concerns

- The brief's Step 2 "Expected: `1..11`, eleven `ok`" does not match
  actual behaviour with the current stage2 compiler (built from nqp
  cfa0846ac / 0b149eaeb) on either invocation path. Either the brief's
  author validated this against a different (later, unrebuilt) nqp
  state where this stdout interleaving doesn't happen, or the
  interaction described above was not caught during brief-writing.
- Recommend one of: (a) split the single `sh()` call into two child
  processes — one plain (`NQP_UNIT=1 $runner $script`) for the
  positional `@out` checks, one with `NQP_CODE_WHY=1` for the marker
  count, mirroring how the knob test already uses its own separate
  `sh()` call; or (b) keep one process but scan stdout for the expected
  lines by content instead of by fixed index. Both are test-file
  changes I have not made without direction, per the brief's "adapt
  only if the runner discovery or `run-command` shape differs" scope
  and the "do not weaken an assertion to make it pass" instruction.
- Step 3 (commit) was NOT performed. No commit exists yet for this
  file.

## Addendum: coordinator ruling and fix applied

The coordinator ruled: split the child into two runs; do not scan
stdout by content.

- Run A (`@ran`, outputs): `sh("NQP_UNIT=1 $runner $script")`, no
  `NQP_CODE_WHY`. The seven `is(@out[0..6] ...)` assertions stay on
  `@ran[1]` split by newline exactly as the brief had them, including
  the `unless nqp::elems(@out) >= 7` diagnostic dump on `@ran`.
- Run B (`@why`, the marker): `sh("NQP_UNIT=1 NQP_CODE_WHY=1 $runner
  $script")`. The `unit record ` line-count (`ok($records >= 3, ...)`)
  and the "nothing on stderr mentions a class" check both now read
  `@why[2]` (stderr) instead of `@ran[2]`.
- Everything else (the knob run, cleanup, `plan(11)`) unchanged.
- Added one sentence to the file's opening comment: "Two separate runs
  do the output and marker checks: NQP_CODE_WHY also prints the
  encoder's per-block trace on stdout, so the marker run cannot double
  as the output run."

### Re-run, from the rakudo worktree root

```
RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle nqp/t/nqp/124-unit-record.t
```

```
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
ok 10 - the road refuses to run without the encoder switches, once
ok 11 - and runs nothing
```

### Re-run, from the nqp directory

```
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp-j-gradle t/nqp/124-unit-record.t
```

Byte-for-byte identical TAP output to the run above -- all 11 `ok`.

### Commit

```
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git add t/nqp/124-unit-record.t && git commit -m "t/nqp/124: a script, its EVALs and --target=jar without --output on the record road (NQP_UNIT), with the road asserted

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011k7PcwZi8KjqW3yLn4GNvi"
```

Result: nqp commit `3e78a37a9` ("t/nqp/124: a script, its EVALs and
--target=jar without --output on the record road (NQP_UNIT), with the
road asserted"), 1 file changed, 94 insertions. `git status --short`
in the nqp tree is clean afterward.

## Final status: DONE
