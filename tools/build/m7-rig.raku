#!/usr/bin/env raku
# Milestone 7's measurement rig (spec Task 0): one row per lever.
#
#   raku tools/build/m7-rig.raku --tag=a1 --out=$CLAUDE_JOB_DIR/tmp/m7-rig
#
# Cold rows: best-of-N wall of ./rakudo-j -e 'say 1' (cwd root) and
# ./nqp-j-gradle -e 'say(1)' (cwd nqp/), stock runners, NQP_UNIT_LOAD_STATS
# and NQP_DISPATCH_STATS on, each run's merged output saved. Warm phase
# (--warm, 2026-09-15): 'proxy' (the default) is t/01-sanity warm on ONE eval
# server and nothing else -- a per-lever row is the two cold rows plus that
# clock, with no t/02-rakudo in any form (user rule 2026-09-15: eight rows of
# the 53-minute single-server clock never left the noise). 'full' runs that
# single-server t/02-rakudo clock, kept for the milestone close; 'none' runs
# neither (also spelled --/warm). The red list of whichever directory ran is
# diffed against docs/jvm-t02-rakudo-red-baseline.txt. Children get
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

# .d is stat-based and so follows a symlinked directory out of the tree; a
# symlink is unlinked, never descended into.
sub rmtree(IO::Path $d) {
    for $d.dir { .d && !.l ?? rmtree($_) !! .unlink }
    $d.rmdir
}

sub parse-cold(Str $text) {
    my %r = :stage-lines(+$text.lines.grep(*.starts-with('unit-load '))), :by{};
    if $text ~~ / 'dispatch stats: hits=' (\d+) ' misses=' (\d+) / {
        %r<hits> = +$0; %r<misses> = +$1;
    }
    # Phase C's two counters. Optional: a capture from before Phase C has
    # neither, and the row line must stay comparable across the whole series,
    # so they are summary-only and never enter the row.
    %r<restored> = +$0 if $text ~~ / ' restored=' (\d+) /;
    %r<recorded> = +$0 if $text ~~ / ' recorded=' (\d+) /;
    %r<publishes> = +$0 if $text ~~ / ' publishes=' (\d+) /;
    for $text.lines {
        %r<by>{$1} = +$0 if / ^ '  misses ' (\d+) ' ' (\S+) /;
    }
    %r
}

sub parse-census(Str $text) {
    my %r;
    if $text ~~ / 'op census: table=' (\d+) ' classlib=' (\d+) ' siteCalls=' (\d+) ' siteMisses=' (\d+) / {
        %r<table> = +$0; %r<classlib> = +$1; %r<site-calls> = +$2; %r<site-misses> = +$3;
    }
    %r<top-table> = $text.lines.grep(*.starts-with('  table ')).head(8).map({ .words[2] ~ '=' ~ .words[1] }).join(' ');
    %r<top-classlib> = $text.lines.grep(*.starts-with('  classlib ')).head(8).map({ .words[2] ~ '=' ~ .words[1] }).join(' ');
    %r
}

sub census-summary(%r) {
    "table={%r<table> // '-'} classlib={%r<classlib> // '-'} siteCalls={%r<site-calls> // '-'} siteMisses={%r<site-misses> // '-'} "
      ~ "top-table: {%r<top-table> || '-'} top-classlib: {%r<top-classlib> || '-'}"
}

sub cold-summary(%r) {
    my @top = %r<by>.sort(-*.value).head(8).map({ .key ~ '=' ~ .value });
    "hits={%r<hits> // '-'} misses={%r<misses> // '-'} restored={%r<restored> // '-'} recorded={%r<recorded> // '-'} publishes={%r<publishes> // '-'} "
      ~ "stage-lines={%r<stage-lines>} top: @top.join(' ')"
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

multi sub MAIN(Str :$parse-census!) { say census-summary(parse-census($parse-census.IO.slurp)) }

multi sub MAIN(
    Tag  :$tag!,                #= row name: base, a1, a3 ...
    Str  :$out = 'm7-rig',      #= output directory
    Int  :$runs = 5,            #= cold runs per benchmark; best wall wins
    # Cool, not Str: --/warm hands over Bool::False, and a Str constraint makes
    # Raku reject that and then swallow the NEXT argument as --warm's value
    # (--/warm --out=DIR silently became --warm='--out=DIR', losing --out).
    Cool :$warm = 'proxy',      #= proxy: the t/01-sanity clock and nothing else; full: the single-server t/02-rakudo clock (milestone close); none: neither (--/warm)
    Int  :$heap = 8,            #= eval-server heap in GB
    Bool :$census = False,      #= after the timed rows: one NQP_OP_CENSUS=1 run and one JFR run per cold row, and a second warm proxy with the knob
    Str  :$baseline = 'docs/jvm-t02-rakudo-red-baseline.txt',
) {
    die "m7-rig: NQP_DISPATCH_RECORD is set; a training run is never a measured run"
        if %*ENV<NQP_DISPATCH_RECORD>:exists;
    die "m7-rig: NQP_OP_CENSUS is set; the timed rows must run with the knob off (use --census)"
        if %*ENV<NQP_OP_CENSUS>:exists;
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

    if $census {
        for @bench -> %b {
            my ($ctext, $ccode) = capture(%b<cmd>, :cwd(%b<cwd>), :env(%(|%cold, NQP_OP_CENSUS => '1')));
            $dir.add("$tag-%b<name>-census.err").spurt($ctext);
            die "%b<name> census: exit $ccode" unless $ccode == 0;
            die "%b<name> census: no 'op census:' marker" unless $ctext.contains('op census:');
            %row{%b<name> ~ '-census'} = parse-census($ctext);
            say "m7-rig: census %b<name> " ~ census-summary(%row{%b<name> ~ '-census'});
            my $jfr = $dir.add("$tag-%b<name>.jfr").absolute.IO;
            my ($jtext, $jcode) = capture(%b<cmd>, :cwd(%b<cwd>),
                :env(%(|%base, JAVA_TOOL_OPTIONS => "-XX:FlightRecorderOptions=stackdepth=512 -XX:StartFlightRecording=filename=$jfr,settings=profile")));
            $dir.add("$tag-%b<name>-jfr.err").spurt($jtext);
            die "%b<name> jfr: exit $jcode (output in $tag-%b<name>-jfr.err)" unless $jcode == 0;
            die "%b<name> jfr: no recording at $jfr" unless $jfr.e;
            my $attr = run 'raku', 'tools/build/jfr-attribute.raku', '--ops', $jfr, :cwd($ROOT), :out;
            $dir.add("$tag-%b<name>-jfr.txt").spurt($attr.out.slurp(:close));
            die "%b<name> jfr-attribute: exit {$attr.exitcode}" if $attr.exitcode != 0;
            say "m7-rig: jfr %b<name> $jfr ({$jfr.s} bytes) -> $tag-%b<name>-jfr.txt";
        }
    }

    # One directory on ONE server, saved as <tag>-<suffix>.log and parsed.
    # --chunk=* is the sweep's own "one chunk, one server" default and the only
    # chunk that needs no file count: counting the files here would count .t
    # only, while the sweep counts .t and .rakutest, and one added .rakutest
    # would silently replace a server mid-sweep -- which the eval-server rules
    # forbid.
    sub sweep(*@dirs, :$tag-suffix!) {
        my ($text, $code) = capture(['raku', 'tools/build/evalserver-sweep.raku', '--chunk=*',
                                     '--jobs=1', "--heap=$heap", |@dirs],
                                    :cwd($ROOT), :env(%base));
        $dir.add("{$tag}-{$tag-suffix}.log").spurt($text);
        my %s = parse-sweep($text, $ROOT.add($baseline));
        # A non-zero exit is normal here (any red file causes it). A sweep that
        # never ran -- heap budget refused, server never up -- is not, and
        # without this would read as a clean row: warm=-, new-red=0, DONE.
        die "m7-rig: sweep $tag-suffix produced no 'files in ...s across' line (sweep exit $code)"
            unless %s<warm>.defined;
        %s
    }

    my %sweep = :warm(Int), :red([]), :new([]);
    my $warm-cell = '-';
    # --/warm hands over a false allomorph, not a string; it means 'none'.
    my $mode = $warm ?? ~$warm !! 'none';
    given $mode {
        when 'full' {
            # A jar rebuild invalidates this precomp cache and one test goes
            # red for it (row a8); clear it before the sweep. Only t/02-rakudo
            # has one, so only this road needs it.
            my $stale = $ROOT.add('t/02-rakudo/test-packages/.precomp');
            rmtree($stale) if $stale.d && !$stale.l;
            %sweep = sweep('t/02-rakudo', :tag-suffix<sweep>);
            $warm-cell = %sweep<warm>;
            say "m7-rig: warm t/02-rakudo {%sweep<warm>}s new-red={+%sweep<new>} " ~ sweep-summary(%sweep);
        }
        when 'proxy' {
            # The whole warm phase of a per-lever row: 25 files on one warm
            # server, about 60s. No t/02-rakudo follows it in any form -- not
            # as a clock, not as a gate (user rule 2026-09-15).
            %sweep = sweep('t/01-sanity', :tag-suffix<sanity>);
            $warm-cell = "{%sweep<warm>}/sanity";
            say "m7-rig: warm t/01-sanity {%sweep<warm>}s " ~ sweep-summary(%sweep);
            if $census {
                my ($ctext, $ccode) = capture(['raku', 'tools/build/evalserver-sweep.raku', '--chunk=*',
                                               '--jobs=1', "--heap=$heap", 't/01-sanity'],
                                              :cwd($ROOT), :env(%(|%base, NQP_OP_CENSUS => '1')));
                $dir.add("{$tag}-sanity-census.log").spurt($ctext);
                die "m7-rig: sanity census produced no 'op census:' block (exit $ccode)" unless $ctext.contains('op census:');
                say "m7-rig: census sanity " ~ census-summary(parse-census($ctext));
            }
        }
        when 'none' { }
        default { die "m7-rig: --warm must be proxy, full or none, not '$warm'" }
    }

    my $st = %row<rakudo-e-stats>;
    my $line = "| $tag | %row<hash-r> | %row<hash-n> | {sprintf '%.3f', %row<rakudo-e>} | {sprintf '%.3f', %row<nqp-e>} | "
             ~ "{$st<misses> // '-'} | {$st<hits> // '-'} | $warm-cell | {%sweep<new>.join(' ') || 'none'} | |";
    $dir.add("$tag.md").spurt($line ~ "\n");
    $dir.add('rows.md').spurt($line ~ "\n", :append);
    say $line;
    say "m7-rig: DONE tag=$tag";
}
