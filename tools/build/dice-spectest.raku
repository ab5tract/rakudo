#!/usr/bin/env raku
# The Phase 5 gate: a steady set of every test file that has ever failed
# here, prepended to a fresh roll of N random spectest files, run through
# one warm eval server with per-file wall times. Slowness is a finding,
# not a wait: any file past --slow aborts the run loudly so the cause is
# chased before more time is spent.
#
#   raku tools/build/dice-spectest.raku [--n=150] [--slow=60] [--seed=X]
#       [--steady=tools/build/steady-set.txt] [--heap=8g]
#
# Verdicts, per file, on stdout and into --log (default dice-run.log):
#   ok / FAIL / SLOW(aborts) / HANG(aborts), with seconds elapsed.
# New FAILs are appended to the steady set (deduplicated), so the next
# roll regression-tests them first. Files in tools/build/never-run.txt
# (the known hang family) are never rolled.

my constant $TOKEN = 'DICETOKEN';

sub MAIN(
    Int  :$n = 150,
    Int  :$slow = 60,          # seconds per file before we stop the world
    Int  :$hang = 300,         # seconds before a file counts as hung
    Int  :$seed = now.Int,
    Str  :$steady = 'tools/build/steady-set.txt',
    Str  :$never = 'tools/build/never-run.txt',
    Str  :$log = 'dice-run.log',
    Str  :$heap = '8g',
) {
    srand($seed);
    note "seed: $seed";
    # The server compiles every test in-process; without this it would
    # silently compile them with the legacy frontend.
    %*ENV<RAKUDO_RAKUAST> = '1';

    my @never = $never.IO.e
        ?? $never.IO.lines.grep({ .chars && !.starts-with('#') }) !! ();
    my %never = @never.map(* => 1);

    # never-run means never: the steady set is filtered by it too, not just
    # the roll. A file that can only hang or burn minutes tells the gate
    # nothing it does not already know.
    my @steady = $steady.IO.e
        ?? $steady.IO.lines.grep({ .chars && !.starts-with('#') && !%never{$_} }).unique
        !! ();
    my @pool = 't/spec/spectest.data'.IO.lines
        .grep({ .chars && !.starts-with('#') })
        .map({ .words[0] })
        .grep({ !%never{$_} });
    my %steady = @steady.map(* => 1);
    my @roll = @pool.grep({ !%steady{$_} }).pick($n);

    my @files = |@steady, |@roll;
    note "steady set: {+@steady} files; roll: {+@roll} files";

    # Fudge the whole roll in one go, exactly as the harness does:
    # fudgeall answers the (possibly rewritten) path per input file,
    # positionally.
    my $fudged = run('perl', 't/spec/fudgeall', '--keep-exit-code',
        'rakudo.jvm', |@files.map({ "t/spec/$_" }), :out, :err);
    my @paths = $fudged.out.slurp(:close).words;
    die "fudgeall answered {+@paths} paths for {+@files} files"
        unless @paths == @files;
    my %fudge-path = @files Z=> @paths;

    # One warm server, the harness's road.
    unlink $TOKEN if $TOKEN.IO.e;
    # The server script does the memory arithmetic (its ceiling plus what
    # every live server can still grow into, against MemAvailable) and
    # refuses when it does not fit; --heap is what it budgets for. A
    # refusal must surface as the refusal, not as a token timeout.
    my $server = Proc::Async.new('./rakudo-eval-server',
        '-cookie', $TOKEN, '-app', './rakudo.jar');
    my $server-err = '';
    $server.stderr.tap({ $server-err ~= $_ });
    my %server-env = %*ENV;
    %server-env<RAKUDO_EVALSERVER_HEAP> = $heap;
    my $sp = $server.start(ENV => %server-env);
    my $waited = 0;
    until $TOKEN.IO.e && $TOKEN.IO.s {
        if $sp.status != Planned {
            note $server-err;
            die "eval server exited before writing $TOKEN";
        }
        die "eval server never wrote $TOKEN" if ($waited += 0.5) > 60;
        sleep 0.5;
    }
    note "server up ({$heap} heap)";

    # One untimed warmup so JIT/PE warmup is not misread as a slow test.
    my $w0 = now;
    run($*EXECUTABLE, 'tools/build/eval-client.raku', $TOKEN, 'run',
        't/01-sanity/01-literals.t', :out, :err);
    note "warmup: {(now - $w0).round(0.1)}s";

    my $lh = open $log, :w, :out-buffer(0);
    $lh.say: "=== seed $seed, {+@files} files, slow {$slow}s, hang {$hang}s ===";
    my @failed;
    my $aborted = '';
    my $t0 = now;

    for @files.kv -> $i, $file {
        my $path = %fudge-path{$file} // "t/spec/$file";

        my $started = now;
        my $out = '';
        my $proc = Proc::Async.new($*EXECUTABLE, 'tools/build/eval-client.raku',
            $TOKEN, 'run', $path);
        $proc.stdout.tap({ $out ~= $_ });
        $proc.stderr.tap({ $out ~= $_ });
        my $done = $proc.start;
        my $slept = await Promise.anyof($done, Promise.in($hang));
        my $secs = (now - $started).round(0.1);

        my $verdict;
        if !$done {
            $proc.kill(Signal::SIGKILL);
            $verdict = 'HANG';
        }
        else {
            my $plan = $out ~~ /^^ '1..' (\d+) /;
            my $nots = +$out.lines.grep(*.starts-with('not ok'));
            my $oks  = +$out.lines.grep({ /^ 'ok ' \d/ });
            $verdict = !$plan                     ?? 'FAIL(no-plan)'
                    !! $nots                      ?? "FAIL($nots)"
                    !! $oks < $plan[0]            ?? "FAIL(ran $oks of $plan[0])"
                    !! 'ok';
        }
        my $line = sprintf '%-56s %-16s %6.1fs  [%d/%d]',
            $file, $verdict, $secs, $i + 1, +@files;
        say $line;
        $lh.say: $line;

        @failed.push($file) if $verdict ne 'ok';
        if $verdict eq 'HANG' {
            $aborted = "$file hung past {$hang}s";
            last;
        }
        if $secs > $slow {
            $aborted = "$file took {$secs}s (limit {$slow}s)";
            last;
        }
    }

    # Shutting the server down is best-effort: sinking a failed Proc
    # throws, and an abort that dies in its own cleanup reports the
    # cleanup instead of the finding it aborted on (seen 2026-09-02,
    # where a SLOW abort surfaced as a spawn failure).
    try {
        my $bye = run($*EXECUTABLE, 'tools/build/eval-client.raku',
                      $TOKEN, 'exit', :out, :err);
        $bye.out.close; $bye.err.close;
    }
    try await Promise.anyof($sp, Promise.in(10));

    # New failures join the steady set for every future roll.
    my @new = @failed.grep({ !%steady{$_} });
    if @new {
        $steady.IO.spurt(( |@steady, |@new ).unique.join("\n") ~ "\n");
        note "steady set grew by {+@new}: @new.join(', ')";
    }

    my $total = (now - $t0).round(1);
    $lh.say: "=== {+@failed} failed of {+@files}, {$total}s total ===";
    $lh.close;
    if $aborted {
        note "ABORTED: $aborted -- diagnose before rolling again";
        exit 2;
    }
    say "{+@failed} failed of {+@files} in {$total}s";
    exit @failed ?? 1 !! 0;
}
