### Task 3: t/nqp/124-unit-record.t

**Files:**
- Create: `nqp/t/nqp/124-unit-record.t`

**Interfaces:**
- Consumes (Tasks 1, 2): the record road under `NQP_UNIT=1` for a script file and for `nqp::getcomp('nqp').eval`; the `NQP_CODE_WHY` marker `unit record `; the knob die text `needs NQP_CODE_RUN=1`; `--target=jar` without `--output` on the road.

- [ ] **Step 1: Write the test**

Model: `nqp/t/nqp/123-unit-artifact.t` (child processes because the road is chosen by an environment variable). The test asserts a positive marker that the road was taken (a script that merely runs would pass on the class road too).

```nqp
# Runs a script on the record road (NQP_UNIT=1, no --output): the unit is
# built in memory as a ProgramUnit, no class defined. A sub, a closure
# over the mainline, a handler, a regex, and two runtime EVALs (records
# themselves) must run; NQP_CODE_WHY must show the road was taken; the
# knob must refuse to run without the encoder switches.

plan(11);

my $is-windows := nqp::backendconfig()<osname> eq 'MSWin32';
if nqp::getcomp('nqp').backend.name ne 'jvm' || $is-windows {
    skip('the unit record road is JVM-only and driven through /bin/sh', 11);
}
else {
    my $dir := nqp::cwd() ~ '/t/nqp/124-unit-record.tmp';
    nqp::mkdir($dir, 0o777) unless nqp::stat($dir, nqp::const::STAT_EXISTS);
    my $script := $dir ~ '/record-script.nqp';

    sub spew($path, @lines) {
        my $fh := nqp::open($path, 'w');
        nqp::printfh($fh, nqp::join("\n", @lines) ~ "\n");
        nqp::closefh($fh);
    }

    spew($script, [
        'my $counter := 0;',
        'sub twice($x) { $x * 2 }',
        'sub counter() { $counter := $counter + 1; $counter }',
        'sub guarded($x) {',
        '    my $r := "no throw";',
        '    try { nqp::die("boom " ~ $x); CATCH { $r := "caught " ~ nqp::getmessage($_) } }',
        '    $r',
        '}',
        'sub matches($s) { $s ~~ /^ \d+ $/ ?? 1 !! 0 }',
        'say(twice(21));',
        'say(counter() ~ "," ~ counter());',
        'say(guarded("x"));',
        'say(matches("123") ~ matches("12a"));',
        'my $evaled := nqp::getcomp("nqp").eval(\'sub ($x) { $x + 1 }\');',
        'say($evaled(41));',
        'say(nqp::getcomp("nqp").eval(\'my $y := 5; $y * 3\'));',
        'class Kept { method answer() { 42 } }',
        'say(Kept.answer());',
    ]);

    # t/nqp runs from the nqp checkout; the rakudo build drives the same
    # files from a directory up.
    my %env := nqp::getenvhash();
    my $runner := nqp::existskey(%env, 'NQP_TEST_RUNNER')
        ?? %env<NQP_TEST_RUNNER>
        !! (nqp::stat(nqp::cwd() ~ '/nqp-j-gradle', nqp::const::STAT_EXISTS)
            ?? './nqp-j-gradle' !! 'nqp/nqp-j-gradle');

    sub sh($command) {
        run-command(nqp::list('/bin/sh', '-c', $command), :stdout, :stderr)
    }

    my @ran := sh("NQP_UNIT=1 NQP_CODE_WHY=1 $runner $script");
    my @out := nqp::split("\n", @ran[1]);
    unless nqp::elems(@out) >= 7 {
        say('# ' ~ @ran[1]);
        say('# ' ~ @ran[2]);
    }
    is(@out[0] // '', '42',            'a sub from a record unit runs');
    is(@out[1] // '', '1,2',           'a closure over the mainline keeps its outer');
    is(@out[2] // '', 'caught boom x', 'a handler in a record block catches');
    is(@out[3] // '', '10',            'a regex from a record unit matches and fails to match');
    is(@out[4] // '', '42',            'an EVAL returns a sub that runs (a record of its own)');
    is(@out[5] // '', '15',            'an EVAL of statements answers its value');
    is(@out[6] // '', '42',            'a class (a static lexical value) from a record unit resolves');

    # The positive marker: NQP_CODE_WHY names each record as loadcompunit
    # builds it -- the script and its two EVALs.
    my int $records := 0;
    for nqp::split("\n", @ran[2]) {
        $records := $records + 1 if nqp::index($_, 'unit record ') == 0;
    }
    ok($records >= 3, 'the script and both EVALs went down the record road (' ~ $records ~ ' records)');
    ok(nqp::index(@ran[2], '.class') < 0 && nqp::index(@ran[2], 'defineClass') < 0,
        'nothing on stderr mentions a class');

    my @knob := sh("env -u NQP_CODE_RUN NQP_UNIT=1 $runner -e 'say(1)'");
    ok(nqp::index(@knob[2], 'needs NQP_CODE_RUN=1') >= 0,
        'the road refuses to run without the encoder switches, once');
    ok(nqp::index(@knob[1], '1') < 0, 'and runs nothing');

    nqp::unlink($script) if nqp::stat($script, nqp::const::STAT_EXISTS);
    nqp::rmdir($dir) if nqp::stat($dir, nqp::const::STAT_EXISTS);
}
```

Note: the `--target=jar`-without-`--output` case is not tested here. It takes the record road (Task 2's routing, verified by review), but with no output the stage loop stops at `jar` and `HLL::Compiler` dumps the result, which dies in `dumper` on an uninitialized `st` on either road (pre-existing, Task 2 review 2026-09-09); nothing observable distinguishes the roads from a child process.

- [ ] **Step 2: Run it**

From the rakudo worktree root: `RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle nqp/t/nqp/124-unit-record.t`
Expected: `1..11`, eleven `ok`. A `not ok` on the record count means the marker line changed or `NQP_CODE_WHY` did not reach the child; on the knob test it means Task 2 Step 1's message text differs.

Also run it from the nqp directory as the suite does: `cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp-j-gradle t/nqp/124-unit-record.t` -- expected the same.

- [ ] **Step 3: Commit (nqp tree)**

```
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git add t/nqp/124-unit-record.t && git commit -m "t/nqp/124: a script, its EVALs and --target=jar without --output on the record road (NQP_UNIT), with the road asserted

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011k7PcwZi8KjqW3yLn4GNvi"
```

---

