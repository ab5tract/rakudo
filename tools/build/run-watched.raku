#!/usr/bin/env raku
# Run a long build or test, tee its output to a log, and give up gracefully if
# it stops producing output.
#
#   run-watched.raku [--log=PATH] [--stall=SECONDS] [--max=SECONDS] -- cmd args...
#
# --stall  how long a silence is allowed before we call it wedged (default 900)
# --max    overall ceiling, 0 for none (default 0)
#
# On a stall, on the ceiling, or on Ctrl-C, the child gets SIGINT, then SIGTERM,
# then SIGKILL, so that whatever it spawned gets a chance to unwind first.
# Exits with the child's exit code, or 124 on a stall/timeout, 130 on Ctrl-C.

sub MAIN(
    *@cmd,
    Str  :$log   = 'run-watched.log',
    Int  :$stall = 900,
    Int  :$max   = 0,
) {
    @cmd or die "nothing to run: pass the command after --\n";

    my $fh = open $log, :w, :out-buffer(0);
    $fh.say: "=== { @cmd.join(' ') } ===";
    $fh.say: "=== started { DateTime.now } ===";

    my $proc = Proc::Async.new(|@cmd);

    # Last time the child said anything. The watchdog polls this rather than
    # rescheduling a timer per chunk, which would pile up on chatty output.
    my $last = now;
    my $done = Promise.new;
    my $verdict = 'ok';

    sub emit($chunk) {
        $last = now;
        $fh.print: $chunk;
        $chunk.lines.tail(0);  # keep the chunk from being retained
    }
    $proc.stdout(:bin).tap: -> $b { emit $b.decode('utf8-c8') };
    $proc.stderr(:bin).tap: -> $b { emit $b.decode('utf8-c8') };

    sub finish($why) {
        return if $done;
        $verdict = $why;
        $done.keep(True);
    }

    # Ctrl-C should stop the child, not orphan it.
    signal(SIGINT).tap: { note "\ninterrupted, stopping child"; finish 'interrupt' }

    my $started = now;
    my $exited = $proc.start;

    my $watchdog = start {
        until $done {
            sleep 5;
            last if $done;
            my $quiet = now - $last;
            if $quiet >= $stall {
                note "no output for {$quiet.Int}s, giving up";
                finish 'stall';
            }
            elsif $max > 0 && (now - $started) >= $max {
                note "over the {$max}s ceiling, giving up";
                finish 'timeout';
            }
        }
    }

    # Whichever comes first: the child finishing, or us deciding to stop it.
    await Promise.anyof($exited, $done);

    my $status;
    if $exited {
        $status = (await $exited).exitcode;
    }
    else {
        # Escalate politely. Each step gets a moment to take effect.
        for SIGINT, SIGTERM, SIGKILL -> $sig {
            $proc.kill($sig);
            last if await Promise.anyof($exited, Promise.in(5));
        }
        $status = $exited ?? (await $exited).exitcode !! -1;
    }
    finish 'ok';
    await $watchdog;

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
