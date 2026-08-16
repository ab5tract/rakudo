#!/usr/bin/env raku
# Run a long build or test, tee its output to a log, and give up gracefully if
# it stops producing output.
#
# Single command:
#   watched-run.raku [--log=PATH] [--stall=SECONDS] [--max=SECONDS] [--show=REGEX ...] -- cmd args...
#
# Many test files, in parallel:
#   watched-run.raku -t=a.t -t=b.t ... [--jobs=N] [--log-dir=DIR] [--stall=..] [--max=..] -- runner args...
#   A -t that names a directory expands to the .t/.rakutest files in it.
#
# --stall    how long a silence is allowed before we call it wedged (default 900)
# --max      overall ceiling per run, 0 for none (default 0)
# --show     echo lines matching this regex to stderr as they arrive, prefixed
#            with elapsed seconds; repeatable. This replaces tailing the log
#            from outside just to see progress markers.
# -t         a test file to run as `cmd args... FILE`; repeatable. Each run
#            gets its own watchdog and its own log under --log-dir.
# --jobs     how many -t runs may be in flight at once (default 5)
# --log-dir  where the per-file logs go in -t mode (default sweep-logs)
#
# All the timing lives in here, as timer events on the react block, so the
# caller just starts this and waits for it to exit; no polling on the outside.
#
# On a stall, on the ceiling, or on Ctrl-C, the child gets SIGINT, then SIGTERM,
# then SIGKILL, so that whatever it spawned gets a chance to unwind first.
# Single mode exits with the child's exit code, or 124 on a stall/timeout, 130
# on Ctrl-C. -t mode exits 0 when every file did, 1 otherwise.

# The terminal output (--show markers, verdicts) must stream even when stdout
# and stderr are pipes, as they are under a supervising tool; piped handles are
# block-buffered by default and hold everything until exit.
$*OUT.out-buffer = False;
$*ERR.out-buffer = False;

my sub run-one(@cmd, Str :$log!, Int :$stall!, Int :$max!, :@pats, Str :$tag,
               Bool :$interruptible) {
    my $fh = open $log, :w, :out-buffer(0);
    # Say so plainly: a bad path otherwise surfaces as a Failure being
    # printed to, several frames away from the cause.
    die "cannot write log '$log': { $fh.exception.message }\n" if $fh ~~ Failure;
    $fh.say: "=== { @cmd.join(' ') } ===";
    $fh.say: "=== started { DateTime.now } ===";

    my $proc = Proc::Async.new(|@cmd, :enc<utf8-c8>);

    my $started = now;
    my $last    = now;   # last time the child said anything, even a partial line
    my $verdict = 'ok';
    my $exited;

    react {
        # Log raw chunks, not lines, so a long line in progress still counts
        # as activity for the stall check.
        sub emit($chunk) {
            $last = now;
            $fh.print: $chunk;
        }
        whenever $proc.stdout { emit $_ }
        whenever $proc.stderr { emit $_ }

        # Progress markers straight to the terminal.
        if @pats {
            my $lines = Supply.merge($proc.stdout.lines, $proc.stderr.lines);
            # In -t mode several runs echo into one terminal, so a marker
            # says which file it came from; a single run needs no tag.
            my $who = $tag ?? " $tag" !! '';
            for @pats -> $pat {
                whenever $lines.grep($pat) -> $l {
                    note "[{(now - $started).Int}s]$who $l";
                }
            }
        }

        sub give-up($why) {
            $verdict = $why;
            done;
        }

        # Ctrl-C should stop the child, not orphan it. Only the single-run
        # mode taps the signal; in -t mode the terminal delivers SIGINT to
        # the whole process group anyway, and one tap per worker would race.
        if $interruptible {
            whenever signal(SIGINT) {
                note "\ninterrupted, stopping child";
                give-up 'interrupt';
            }
        }

        if $max > 0 {
            whenever Promise.in($max) {
                note "over the {$max}s ceiling, giving up";
                give-up 'timeout';
            }
        }

        whenever Supply.interval(5, 5) {
            my $quiet = now - $last;
            if $quiet >= $stall {
                note "no output for {$quiet.Int}s, giving up";
                give-up 'stall';
            }
        }

        $exited = $proc.start;
        whenever $exited { done }
    }

    my $status;
    if $exited {
        $status = (await $exited).exitcode;
    }
    else {
        # Escalate politely. Each step gets a moment to take effect.
        for SIGINT, SIGTERM, SIGKILL -> $sig {
            $proc.kill($sig);
            await Promise.anyof($exited, Promise.in(5));
            last if $exited;
        }
        $status = $exited ?? (await $exited).exitcode !! -1;
    }

    my $code = do given $verdict {
        when 'ok'        { $status }
        when 'interrupt' { 130 }
        default          { 124 }
    };

    $fh.say: "=== EXIT=$code verdict=$verdict elapsed={(now - $started).Int}s ===";
    $fh.say: "=== finished { DateTime.now } ===";
    $fh.close;
    ($code, $verdict)
}

# It must be greater than two slashes. Otherwise treat it as a string search for '//'
subset RegexInput of Str where { .starts-with('/') && .ends-with('/') && 2 < .comb }

sub MAIN(
    *@cmd,
    Str  :$log     = 'watched-run.log',
    Str  :$log-dir = 'sweep-logs',
    Int  :$stall   = 900,
    Int  :$max     = 0,
    Int  :$jobs    = 5,
    :@show,
    :@t
 ) {
    @cmd or die "nothing to run: pass the command after --\n";

    # Compile the patterns before anything starts: a broken regex must fail
    # here, not inside the react block once the child is already running.
    my @pats = @show.map: -> $show {
        my $s = $show ~~ RegexInput ?? $show.substr(1, *-1) !! $show;
        my $rx = try "anon regex \{ $s \}".EVAL;
        $rx // die "bad --show pattern '$s': { $!.message }\n";
    };

    if @t {
        # A -t argument may name a directory; it stands for every test file
        # directly inside it. Only .t and .rakutest count, so the .c sources
        # that sit next to some nativecall tests are never picked up.
        my @files = @t.map(-> $t {
            $t.IO.d
                ?? $t.IO.dir(test => *.ends-with('.t' | '.rakutest'))
                       .sort.map(*.relative).Slip
                !! $t
        });
        mkdir $log-dir unless $log-dir.IO.d;
        # Say where the logs are before anything runs, not only after: a run
        # that has to be interrupted still leaves you knowing where to look.
        note "logs: { $log-dir.IO.absolute }/ ({ +@files } files)";
        my $started = now;
        my @results = @files.race(:batch(1), :degree($jobs)).map: -> $file {
            my $name = $file.trans('/.' => '__');
            my ($code, $verdict) =
                    run-one([|@cmd, $file], :log("$log-dir/$name.log"), :$stall, :$max,
                            :@pats, :tag($file.IO.basename));
            note "{ $code == 0 ?? 'ok  ' !! 'FAIL' } $file (exit $code, $verdict)";
            $file => $code
        };
        my @failed = @results.grep(*.value != 0);
        note "{ @results.elems - @failed.elems } of { @results.elems } ok "
                ~ "in {(now - $started).Int}s, logs: $log-dir";
        exit @failed ?? 1 !! 0;
    }
    else {
        note "log: { $log.IO.absolute }";
        my ($code, $verdict) =
                run-one(@cmd, :$log, :$stall, :$max, :@pats, :interruptible);
        note "$verdict, exit $code, log: $log";
        exit $code;
    }
}
