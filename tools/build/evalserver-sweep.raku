#!/usr/bin/env raku
# Runs a test sweep through the JVM eval server in chunks, one server per chunk.
#
# The server keeps a warm JVM, which takes a test file from ~26s to well under a
# second. It also leaks per run -- each run's compilation unit and the objects it
# deserialised stay reachable from a static, so after roughly thirty files the
# heap is at its ceiling and runs quietly produce no TAP at all, which the
# harness reports as "No subtests run": a passing file that looks broken. Until
# that leak is found, take the win and stay inside it: a fresh server per chunk
# costs one JVM start (~22s) per --chunk files instead of one per file.
sub MAIN(
    *@targets,
    Int  :$chunk = 20,      #= test files per server
    Str  :$harness = 't/harness5',
) {
    # Progress must stream: stdout is a pipe under any supervising tool, and a
    # piped handle is block buffered, so the chunk headers would otherwise sit
    # unseen until the whole sweep ended.
    $*OUT.out-buffer = False;

    my @files = @targets.map({ .IO.d ?? .IO.dir(test => *.ends-with('.t')).sort.map(*.relative).Slip !! $_ });
    die "no test files found\n" unless @files;

    my $started = now;
    my (@failed, $ran);
    for @files.batch($chunk).kv -> $i, @batch {
        unlink 'TESTTOKEN' if 'TESTTOKEN'.IO.e;
        say "=== chunk { $i + 1 } of { (@files / $chunk).ceiling }: { +@batch } files ===";
        my $proc = run 'perl', '-I', 'tools/lib', '-I', '3rdparty/nqp-configure/lib',
                       $harness, '--jvm', '--evalserver', |@batch;
        @failed.push: |@batch unless $proc.exitcode == 0;
        $ran += @batch;
    }
    say "";
    say "{ $ran } files in { (now - $started).Int }s"
        ~ (@failed ?? ", { +@failed } in failing chunks" !! ", all chunks passed");
    exit @failed ?? 1 !! 0;
}
