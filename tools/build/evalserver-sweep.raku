#!/usr/bin/env raku
# Runs a test sweep across a pool of JVM eval servers, for rakudo's suite or
# nqp's own.
#
# One server keeps a warm JVM, which takes a rakudo test file from ~26s to well
# under a second (an nqp file from ~1s to ~0.3s) -- but it takes its runs one
# at a time, because System.out/System.err and the dispatch caches on the
# shared compilation unit are process-wide. Several servers at once restore
# parallelism: each is serial inside, and the pool is as parallel as the
# machine.
#
# "As parallel as the machine" means its memory, not its cores. Every server
# may grow to its full heap before its chunk ends, so jobs x heap is a real
# reservation, and on a box without swap an over-committed pool ends with the
# kernel's OOM killer shooting JVMs -- and whatever shares their cgroup, the
# terminal session included. The pool is therefore sized against what the
# machine actually has free, and an explicit over-budget override has to say
# --force.
#
# A chunk is one server's whole life. --chunk=* (the default) is ONE chunk
# holding every file: a replaced server throws away the warm JIT state the
# previous chunk paid for, and the per-run leak that once made small chunks
# necessary is fixed (docs/jvm-eval-server.md). For N servers with no mid-run
# replacement, pass --chunk=<total / N>.
#
# --suite=nqp runs nqp's own t/ through nqp/nqp-eval-server-gradle (generated
# next to nqp-j-gradle by `./nqp/gradlew -p nqp buildJvm`), from inside nqp/,
# where the tests expect to run. Targets may be given as nqp/t/... or t/....

# Without this, an option after the first target lands in the slurpy and is
# silently taken for a test file name.
my %*SUB-MAIN-OPTS = :named-anywhere;

# The directories nqp's gradle testNqp runs, plus t/concurrency.
my constant NQP-DIRS = <t/nqp t/hll t/qregex t/qast t/jvm t/serialization
                        t/nativecall t/concurrency>;

subset Suite of Str where 'rakudo' | 'nqp';

# Files per server: a positive count, or * for every file (one server, never
# replaced). The command line hands both over as text, so * stays a string
# until the file list exists to resolve it against.
subset Chunk of Str where { $_ eq '*' || (/^ \d+ $/ && .Int > 0) };

#| Print the census block the sweep would lift out of FILE (the largest block); a test hook.
multi sub MAIN(Str :$census-block!) { say largest-census-block($census-block.IO.slurp) }

multi sub MAIN(
    *@targets,
    Suite :$suite = 'rakudo',  #= rakudo (t/harness5) or nqp (prove inside nqp/)
    Int  :$heap,               #= GB of heap per server (default 6, less on a tight box)
    Int  :$jobs,               #= servers running at once (default: what the memory budget fits, capped at 6)
    Chunk :$chunk = '*',       #= files per server, or * for all of them on one server (the default)
    Str  :$harness = 't/harness5',
    Bool :$force,              #= run a jobs x heap combination that exceeds the memory budget
) {
    $*OUT.out-buffer = False;
    # Progress notes go to stderr, which block-buffers into a pipe -- a
    # backgrounded sweep then looks silent until exit.
    $*ERR.out-buffer = False;

    # MemAvailable is what the kernel could hand out right now without
    # swapping; a quarter of it stays back for the clients, the harness, and
    # everything else alive on the box.
    my $avail-gb = '/proc/meminfo'.IO.lines.first(*.starts-with('MemAvailable')) ~~ /(\d+)/
                       ?? $0 div (1024 * 1024) !! 8;
    # Reserve a fixed 3g for the clients, the harness and the rest of the
    # box, not a quarter: a quarter of 19g refused the three servers the
    # server's own guard (which works from MemAvailable directly) allows.
    my $budget = max(4, $avail-gb - 3);

    # The server's own guard (rakudo-eval-server / nqp-eval-server-gradle:
    # "REFUSING to start") counts a server as heap + 3g of off-heap (the
    # Truffle compiler isolate, code cache, metaspace), and refuses a new
    # server when the live ones' growth allowance plus that would pass
    # MemAvailable. Budget the same way, or the pool this promises is one the
    # guard declines mid-run -- which surfaced as a chunk with no TAP and a
    # 120s token timeout (2026-09-08).
    my constant OFF-HEAP-GB = 3;
    my $h = $heap // ($budget >= 18 ?? 6 !! max(2, $budget div 2 - OFF-HEAP-GB));
    my $per = $h + OFF-HEAP-GB;

    my $root = $suite eq 'nqp' ?? 'nqp'.IO !! '.'.IO;
    @targets = NQP-DIRS if $suite eq 'nqp' && !@targets;
    my @files = @targets.map(-> $t {
        my $rel = $suite eq 'nqp' ?? $t.subst(/^ 'nqp/'/, '') !! $t;
        my $io  = $root.add($rel);
        $io.d
            ?? $io.dir(test => *.ends-with('.t' | '.rakutest'))
                   .sort.map(*.relative($root)).Slip
            !! $rel
    });
    die "no test files found\n" unless @files;

    # Numeric context answers the list's count for * and the number for a count.
    my $c = +($chunk eq '*' ?? @files !! $chunk);
    my @chunks = @files.batch($c);
    my $j = min(+@chunks, $jobs // max(1, min(6, $budget div $per)));
    if $per * $j > $budget && !$force {
        die "jobs ($j) x (heap {$h}g + {OFF-HEAP-GB}g off-heap) = { $per * $j }g exceeds the {$budget}g budget"
          ~ " ({$avail-gb}g available); lower one, or pass --force to overcommit\n";
    }
    note "$suite: { +@files } files, { +@chunks } chunk(s) of $c, "
       ~ "$j server(s) x {$h}g heap + {OFF-HEAP-GB}g off-heap ({ $per * $j }g of a {$budget}g budget, {$avail-gb}g available)";

    my $started = now;
    my $done = 0;
    my @results = @chunks.pairs.race(:batch(1), :degree($j)).map: -> $pair {
        my $i      = $pair.key;
        my @batch := $pair.value;
        # Each chunk gets its own server, named by its own token file; without
        # that the pool would share one server and serialise right back.
        my $token = ".evalserver-token-$i";
        my ($code, $out) = $suite eq 'nqp'
            ?? run-nqp-chunk($root, $token, $h, @batch)
            !! run-rakudo-chunk($harness, $token, $h, @batch);
        note "[{ (now - $started).Int }s] chunk { ++$done }/{ +@chunks }: "
             ~ ($code == 0 ?? 'ok' !! 'FAIL')
             ~ ($out ~~ /'No subtests run'/ ?? '  *** a file produced no TAP ***' !! '');
        if %*ENV<NQP_OP_CENSUS>:exists {
            my $block = largest-census-block($out);
            say $block || "evalserver-sweep: no op census block for chunk $i";
        }
        %( :$i, :files(@batch), :$code, :$out )
    };

    my @failed = @results.grep(*<code> != 0);
    say "";
    say "{ +@files } files in { (now - $started).Int }s across { +@chunks } server(s)";
    say "{ +@failed } of { +@chunks } chunks failed" if @failed;
    for @failed -> $f {
        say "--- chunk { $f<i> } (exit { $f<code> }) ---";
        say $f<out>.lines.grep({ /^ 't/' | 'Result:' | 'No subtests' | 'Failed ' | '  ' \S /}).join("\n");
        # A chunk whose server never came up, or whose harness died, has no
        # test line at all; the raw tail is the only diagnostic there is.
        my @tail = $f<out>.lines.tail(15);
        say "--- raw tail ---\n" ~ @tail.join("\n") if @tail;
    }
    exit @failed ?? 1 !! 0;
}

# The text a census is read from can hold several JVMs' blocks (a sweep
# captures every process started under NQP_OP_CENSUS, helpers included);
# the one to read is the largest by its table total. Blocks are the runs
# of census-shaped lines from one `op census:` header to the next; other
# lines (dispatch stats, TAP) may be interleaved and are dropped.
# Kept identical to m7-rig.raku's copy; the two scripts are standalone.
sub largest-census-block(Str $text --> Str) {
    my @blocks;
    for $text.lines {
        if .starts-with('op census:') { @blocks.push([$_]) }
        elsif @blocks && (.starts-with('  table ') || .starts-with('  classlib ') || .starts-with('  site ')) {
            @blocks.tail.push($_)
        }
    }
    return '' unless @blocks;
    @blocks.max({ .[0] ~~ / 'table=' (\d+) / ?? +$0 !! -1 }).join("\n")
}

# t/harness5 starts and stops its own server.
sub run-rakudo-chunk($harness, $token, $h, @batch) {
    my $proc = run 'perl', '-I', 'tools/lib', '-I', '3rdparty/nqp-configure/lib',
                   $harness, '--jvm', '--evalserver', '--jobs=1', |@batch,
                   :out, :err,
                   :env(%*ENV, RAKUDO_EVALSERVER_TOKEN => $token,
                               RAKUDO_EVALSERVER_HEAP  => "{$h}g",
                               # This branch is RakuAST-only; a shell that
                               # forgot the export must not silently sweep
                               # the legacy frontend instead.
                               RAKUDO_RAKUAST          => '1');
    # BOTH handles drained CONCURRENTLY. Slurping stdout to EOF first and
    # stderr afterwards deadlocks the moment a chunk writes more to stderr
    # than the pipe buffer holds: the writer blocks in write(2), so it never
    # exits, so stdout never reaches EOF, so this process never gets to the
    # stderr slurp that would unblock it. The eval server's uncut op census
    # block (NQP_OP_CENSUS, ~1000 lines on a sanity sweep) is exactly that
    # size, and it is printed from a shutdown hook, which wedges the server's
    # exit and with it the harness that is waiting on it. Measured 2026-09-16:
    # a three-way hang, server stuck in FileOutputStream.writeBytes for 12 min.
    my $errored = start { $proc.err.slurp(:close) };
    my $out = $proc.out.slurp(:close) ~ await $errored;
    unlink $token if $token.IO.e;
    $proc.exitcode, $out
}

# nqp has no harness of its own that knows the server, so the server is
# started here and prove drives it through eval-client.raku.
sub run-nqp-chunk(IO::Path $root, $token, $h, @batch) {
    my $token-io = $root.add($token);
    unlink $token-io if $token-io.e;
    my $launcher = $root.add('nqp-eval-server-gradle');
    die "$launcher is missing; run ./nqp/gradlew -p nqp buildJvm\n" unless $launcher.x;

    # -bind-stdin: the server exits when its stdin closes, so it cannot
    # outlive this sweep however the sweep ends.
    my $server = Proc::Async.new(:w, './nqp-eval-server-gradle', '-bind-stdin',
                                 '-cookie', $token, '-app', 'build/jvm/share/lib/nqp.jar');
    my $server-out = '';
    # One tap on the merged stream: two taps could append concurrently.
    $server.Supply.tap: { $server-out ~= $_ };
    my $exited = $server.start(:cwd($root),
                               :ENV(%*ENV, NQP_EVALSERVER_HEAP => "{$h}g"));

    # The server loads nqp.jar before it writes the token; running the first
    # file before then reads as that file having no plan.
    my $deadline = now + 120;
    until $token-io.e && $token-io.slurp ~~ / \d+ ' ' \S+ / {
        # Exit 75 is the launcher's memory guard refusing; say so, not "no TAP".
        return 1, "nqp eval server exited before writing $token "
                ~ "(code { $exited.result.exitcode }):\n$server-out" if $exited;
        return 1, "nqp eval server did not write $token within 120s\n$server-out"
            if now > $deadline;
        sleep 0.25;
    }

    # Native code writes to the server process's real stdout, which the
    # server's System.setOut redirection cannot see, so a nativecall test's
    # own TAP would vanish into the server log. Those files run cold.
    my @cold = @batch.grep(*.starts-with('t/nativecall/'));
    my @warm = @batch.grep(!*.starts-with('t/nativecall/'));

    # run(:out) returns while the process still runs; only draining its output
    # waits for it, so each prove is drained before anything else happens --
    # above all before the server is told to stop.
    sub prove(*@args) {
        my $proc = run 'prove', '--merge', |@args, :cwd($root), :out, :err;
        # Concurrently, for the reason run-rakudo-chunk spells out above.
        my $errored = start { $proc.err.slurp(:close) };
        my $out = $proc.out.slurp(:close) ~ await $errored;
        $proc.exitcode, $out
    }

    my @runs;
    # --ignore-exit: the eval client's exit code is not the test's.
    @runs.push: prove('--ignore-exit', '-j1',
                      '--exec', "raku ../tools/build/eval-client.raku $token run", |@warm)
        if @warm;

    $server.close-stdin;
    await Promise.anyof($exited, Promise.in(30));
    $server.kill(SIGKILL) unless $exited;
    unlink $token-io if $token-io.e;

    @runs.push: prove('--exec', './nqp-j-gradle', |@cold) if @cold;

    (@runs.map(*[0]).first(* != 0) // 0),
        @runs.map(*[1]).join("\n") ~ ($server-out ?? "\n--- server output ---\n$server-out" !! '')
}
