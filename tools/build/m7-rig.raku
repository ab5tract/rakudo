#!/usr/bin/env raku
# Milestone 7's measurement rig (spec Task 0): one row per lever.
#
#   raku tools/build/m7-rig.raku --tag=a1 --out=$CLAUDE_JOB_DIR/tmp/m7-rig
#
# Cold rows: best-of-N wall of ./rakudo-j -e 'say 1' (cwd root) and
# ./nqp-j-gradle -e 'say(1)' (cwd nqp/), stock runners, NQP_UNIT_LOAD_STATS
# and NQP_DISPATCH_STATS on, each run's merged output saved. Warm row: the
# whole t/02-rakudo directory on ONE eval server (chunk = file count), the
# red list diffed against docs/jvm-t02-rakudo-red-baseline.txt. Children get
# /dev/null on stdin and merged output (inherited stdin hung under
# watched-run, 2026-09-13). Refuses to start with NQP_DISPATCH_RECORD set:
# a training run is never a measured run (spec, Phase C).
#
# Positive markers: 'unit-load: stats on' and 'dispatch stats:' in every
# cold run, 'm7-rig: DONE' at the end. A run without them dies.
use v6.d;
my %*SUB-MAIN-OPTS = :named-anywhere;

subset Tag of Str where /^ <[\w-]>+ $/;

my $ROOT = $*PROGRAM.parent(3).absolute.IO;

# A non-zero child makes Proc's handle close throw, and the sweep exits
# non-zero whenever any test file is red -- the normal case, 22 of them at
# base. So slurp the output first and take the code off the exception; the
# caller judges it. Losing a 54-minute sweep to an expected exit code was
# the 2026-09-13 lesson.
sub capture(@cmd, IO() :$cwd!, :%env!) {
    my $devnull = '/dev/null'.IO.open(:r);
    my $p = run |@cmd, :$cwd, :in($devnull), :out, :merge, :%env;
    my $text = $p.out.slurp;
    my $code;
    {
        $p.out.close;
        $code = $p.exitcode;
        CATCH { when X::Proc::Unsuccessful { $code = .proc.exitcode } }
    }
    $devnull.close;
    ($text, $code)
}

sub parse-cold(Str $text) {
    my %r = :stage-lines(+$text.lines.grep(*.starts-with('unit-load '))), :by{};
    if $text ~~ / 'dispatch stats: hits=' (\d+) ' misses=' (\d+) / {
        %r<hits> = +$0; %r<misses> = +$1;
    }
    for $text.lines {
        %r<by>{$1} = +$0 if / ^ '  misses ' (\d+) ' ' (\S+) /;
    }
    %r
}

sub cold-summary(%r) {
    my @top = %r<by>.sort(-*.value).head(8).map({ .key ~ '=' ~ .value });
    "hits={%r<hits> // '-'} misses={%r<misses> // '-'} stage-lines={%r<stage-lines>} top: @top.join(' ')"
}

sub parse-sweep(Str $text, IO() $baseline) {
    my %base = $baseline.lines.grep(*.starts-with('t/')).map(* => True);
    my $warm = $text ~~ / (\d+) ' files in ' (\d+) 's across' / ?? +$1 !! Int;
    # t/harness5's Test Summary Report also lists a file that merely had TODO
    # passes -- 'Failed: 0' with a '  TODO passed:' line under it. That is not
    # a red. A 'Failed: 0' under '  Parse errors:' (a file that produced no
    # TAP) IS one, so the TODO line, not the count, is what disqualifies.
    my @lines = $text.lines;
    my @red = gather for @lines.kv -> $i, $line {
        if $line ~~ / ^ (t\/\S+) \s+ '(Wstat' / {
            take ~$0 unless (@lines[$i + 1] // '').starts-with('  TODO passed:');
        }
    }
    @red .= unique;
    my @new  = @red.grep({ !%base{$_} });
    %( :$warm, :@red, :@new )
}

sub sweep-summary(%s) {
    "warm={%s<warm> // '-'} red={+%s<red>} new-red={%s<new>.join(',') || '-'}"
}

multi sub MAIN(Str :$parse-cold!) {
    say cold-summary(parse-cold($parse-cold.IO.slurp));
}

multi sub MAIN(Str :$parse-sweep!, Str :$baseline = 'docs/jvm-t02-rakudo-red-baseline.txt') {
    say sweep-summary(parse-sweep($parse-sweep.IO.slurp, $baseline));
}

multi sub MAIN(
    Tag  :$tag!,                #= row name: base, a1, a3 ...
    Str  :$out = 'm7-rig',      #= output directory
    Int  :$runs = 5,            #= cold runs per benchmark; best wall wins
    Bool :$warm = True,         #= also run warm t/02-rakudo (about 90 min)
    Int  :$heap = 8,            #= eval-server heap in GB
    Str  :$baseline = 'docs/jvm-t02-rakudo-red-baseline.txt',
) {
    die "m7-rig: NQP_DISPATCH_RECORD is set; a training run is never a measured run"
        if %*ENV<NQP_DISPATCH_RECORD>:exists;
    $*OUT.out-buffer = False;
    my $dir = $out.IO; $dir.mkdir;
    my %base = %*ENV, RAKUDO_RAKUAST => '1';
    my %cold = %base, NQP_UNIT_LOAD_STATS => '1', NQP_DISPATCH_STATS => '1';
    my @bench =
        %( :name<rakudo-e>, :cwd($ROOT),            :cmd(['./rakudo-j', '-e', 'say 1']) ),
        %( :name<nqp-e>,    :cwd($ROOT.add('nqp')), :cmd(['./nqp-j-gradle', '-e', 'say(1)']) );

    sub run-once(%b, $i) {
        my $t0 = now;
        my ($text, $code) = capture(%b<cmd>, :cwd(%b<cwd>), :env(%cold));
        my $wall = now - $t0;
        $dir.add("$tag-%b<name>-run$i.err").spurt($text);
        die "%b<name> run$i: exit $code" unless $code == 0;
        die "%b<name> run$i: no 'unit-load: stats on' marker" unless $text.contains('unit-load: stats on');
        die "%b<name> run$i: no 'dispatch stats:' marker" unless $text.contains('dispatch stats:');
        note sprintf("m7-rig: %-9s run%d wall=%.3fs", %b<name>, $i, $wall);
        ($wall, $text)
    }

    my %row = :$tag, :hash-r(run('git', 'rev-parse', '--short=10', 'HEAD', :cwd($ROOT), :out).out.slurp(:close).trim),
              :hash-n(run('git', 'rev-parse', '--short=9', 'HEAD', :cwd($ROOT.add('nqp')), :out).out.slurp(:close).trim);
    for @bench -> %b {
        my @runs = (1..$runs).map: { run-once(%b, $_) };
        my $best = @runs.min(*[0]);
        %row{%b<name>} = $best[0];
        %row{%b<name> ~ '-stats'} = parse-cold($best[1]);
        say sprintf("m7-rig: cold %s best=%.3fs  all: %s  %s", %b<name>, $best[0],
                    @runs.map({ sprintf '%.2f', $_[0] }).join(' '), cold-summary(%row{%b<name> ~ '-stats'}));
    }

    my %sweep = :warm(Int), :red([]), :new([]);
    if $warm {
        # --chunk=* is the sweep's own "one chunk, one server" default. Counting
        # the files here instead would count .t only, while the sweep counts
        # .t and .rakutest, and one added .rakutest would silently replace a
        # server mid-sweep -- which the eval-server rules forbid.
        my ($text, $code) = capture(['raku', 'tools/build/evalserver-sweep.raku', '--chunk=*',
                                     '--jobs=1', "--heap=$heap", 't/02-rakudo'],
                                    :cwd($ROOT), :env(%base));
        $dir.add("{$tag}-sweep.log").spurt($text);
        %sweep = parse-sweep($text, $ROOT.add($baseline));
        # A non-zero exit is normal here (any red file causes it). A sweep that
        # never ran -- heap budget refused, server never up -- is not, and
        # without this would read as a clean row: warm=-, new-red=0, DONE.
        die "m7-rig: sweep produced no 'files in ...s across' line (sweep exit $code)"
            unless %sweep<warm>.defined;
        say "m7-rig: warm t/02-rakudo {%sweep<warm> // '?'}s new-red={+%sweep<new>} " ~ sweep-summary(%sweep);
    }

    my $st = %row<rakudo-e-stats>;
    my $line = "| $tag | %row<hash-r> | %row<hash-n> | {sprintf '%.3f', %row<rakudo-e>} | {sprintf '%.3f', %row<nqp-e>} | "
             ~ "{$st<misses> // '-'} | {$st<hits> // '-'} | {%sweep<warm> // '-'} | {%sweep<new>.join(' ') || 'none'} | |";
    $dir.add("$tag.md").spurt($line ~ "\n");
    $dir.add('rows.md').spurt($line ~ "\n", :append);
    say $line;
    say "m7-rig: DONE tag=$tag";
}
