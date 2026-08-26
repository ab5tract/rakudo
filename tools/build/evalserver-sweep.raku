#!/usr/bin/env raku
# Runs a test sweep across a pool of JVM eval servers.
#
# One server keeps a warm JVM, which takes a test file from ~26s to well under
# a second -- but it takes its runs one at a time, because System.out/System.err
# and the dispatch caches on the shared compilation unit are process-wide. A
# single server therefore loses exactly the parallelism the cold harness already
# had, and over a whole suite the two come out level. Several servers at once
# get both: each is serial inside, and the pool is as parallel as the machine.
#
# "As parallel as the machine" means its memory, not its cores. Every server
# may grow to its full heap before its chunk ends, so jobs x heap is a real
# reservation, and on a box without swap an over-committed pool ends with the
# kernel's OOM killer shooting JVMs -- and whatever shares their cgroup, the
# terminal session included. The pool is therefore sized against what the
# machine actually has free, and an explicit over-budget override has to say
# --force.
#
# Chunking is the other half. Each run retains a couple of hundred megabytes
# that nothing releases, so a server that has taken too many files sits at
# its heap ceiling and its runs quietly produce no TAP at all -- which reads as
# "No subtests run", a passing file looking broken. A chunk is one server's
# whole life, so it must stay well inside the heap: at 8g, 15 files left room
# and 20 did not, and the default scales down from there with the heap.

# Without this, an option after the first target lands in the slurpy and is
# silently taken for a test file name.
my %*SUB-MAIN-OPTS = :named-anywhere;

sub MAIN(
    *@targets,
    Int  :$heap,               #= GB of heap per server (default 6, less on a tight box)
    Int  :$jobs,               #= servers running at once (default: what the memory budget fits, capped at 6)
    Int  :$chunk,              #= files per server before it is replaced (default scales with heap)
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
    my $budget = max(4, $avail-gb * 3 div 4);

    my $h = $heap // ($budget >= 12 ?? 6 !! max(3, $budget div 2));
    my $j = $jobs // max(1, min(6, $budget div $h));
    if $h * $j > $budget && !$force {
        die "jobs ($j) x heap ({$h}g) = { $h * $j }g exceeds the {$budget}g budget"
          ~ " ({$avail-gb}g available); lower one, or pass --force to overcommit\n";
    }
    my $c = $chunk // max(3, $h * 15 div 8);

    my @files = @targets.map({
        .IO.d ?? .IO.dir(test => *.ends-with('.t')).sort.map(*.relative).Slip !! $_
    });
    die "no test files found\n" unless @files;

    my @chunks = @files.batch($c);
    note "{ +@files } files, { +@chunks } chunks of $c, "
       ~ "$j servers x {$h}g heap ({ $h * $j }g of a {$budget}g budget, {$avail-gb}g available)";

    my $started = now;
    my $done = 0;
    my @results = @chunks.pairs.race(:batch(1), :degree($j)).map: -> $pair {
        my $i      = $pair.key;
        my @batch := $pair.value;
        # Each chunk gets its own server, named by its own token file; without
        # that the pool would share one server and serialise right back.
        my $token = ".evalserver-token-$i";
        my $proc = run 'perl', '-I', 'tools/lib', '-I', '3rdparty/nqp-configure/lib',
                       $harness, '--jvm', '--evalserver', '--jobs=1', |@batch,
                       :out, :err,
                       :env(%*ENV, RAKUDO_EVALSERVER_TOKEN => $token,
                                   RAKUDO_EVALSERVER_HEAP  => "{$h}g",
                                   # This branch is RakuAST-only; a shell that
                                   # forgot the export must not silently sweep
                                   # the legacy frontend instead.
                                   RAKUDO_RAKUAST          => '1');
        my $out = $proc.out.slurp(:close) ~ $proc.err.slurp(:close);
        unlink $token if $token.IO.e;
        note "[{ (now - $started).Int }s] chunk { ++$done }/{ +@chunks }: "
             ~ ($proc.exitcode == 0 ?? 'ok' !! 'FAIL')
             ~ ($out ~~ /'No subtests run'/ ?? '  *** a file produced no TAP ***' !! '');
        %( :i($i), :files(@batch), :code($proc.exitcode), :$out )
    };

    my @failed = @results.grep(*<code> != 0);
    my $silent = +@results.grep(*<out>.contains('No subtests run'));
    say "";
    say "{ +@files } files in { (now - $started).Int }s across { +@chunks } servers";
    say "{ +@failed } of { +@chunks } chunks failed" if @failed;
    say "*** $silent chunk(s) contained a file with no TAP -- lower --chunk ***" if $silent;
    for @failed -> $f {
        say "--- chunk { $f<i> } ---";
        say $f<out>.lines.grep({ /^ 't/' | 'Result:' | 'No subtests' | 'Failed ' /}).join("\n");
    }
    exit @failed ?? 1 !! 0;
}
