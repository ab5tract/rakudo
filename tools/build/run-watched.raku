#!/usr/bin/env raku
# Run a long build or test, tee its output to a log, and give up gracefully if
# it stops producing output.
#
#   run-watched.raku [--log=PATH] [--stall=SECONDS] [--max=SECONDS] [--show=REGEX ...] -- cmd args...
#
# --stall  how long a silence is allowed before we call it wedged (default 900)
# --max    overall ceiling, 0 for none (default 0)
# --show   echo lines matching this regex to stderr as they arrive, prefixed
#          with elapsed seconds; repeatable. This replaces tailing the log
#          from outside just to see progress markers.
#
# All the timing lives in here, as timer events on the react block, so the
# caller just starts this and waits for it to exit; no polling on the outside.
#
# On a stall, on the ceiling, or on Ctrl-C, the child gets SIGINT, then SIGTERM,
# then SIGKILL, so that whatever it spawned gets a chance to unwind first.
# Exits with the child's exit code, or 124 on a stall/timeout, 130 on Ctrl-C.

sub MAIN(
    *@cmd,
    Str  :$log   = 'run-watched.log',
    Int  :$stall = 900,
    Int  :$max   = 0,
    :@show,
) {
    @cmd or die "nothing to run: pass the command after --\n";

    my $fh = open $log, :w, :out-buffer(0);
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
        if @show {
            my $lines = Supply.merge($proc.stdout.lines, $proc.stderr.lines);
            for @show -> $pat {
                whenever $lines.grep(/<$pat>/) -> $l {
                    note "[{(now - $started).Int}s] $l";
                }
            }
        }

        sub give-up($why) {
            $verdict = $why;
            done;
        }

        # Ctrl-C should stop the child, not orphan it.
        whenever signal(SIGINT) {
            note "\ninterrupted, stopping child";
            give-up 'interrupt';
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
    note "$verdict, exit $code, log: $log";
    exit $code;
}
