#!/usr/bin/env raku
# Cold-start load profile (phase 0 of the lazy unit loading design,
# docs/superpowers/specs/2026-09-13-jvm-lazy-unit-loading-design.md).
#
# Runs each benchmark cold, --runs times in sequence (never overlapping, so the
# wall clocks do not compete) with NQP_UNIT_LOAD_STATS=1, saving each run's
# per-stage lines; reports best-of-N; then, with --jfr, one JFR recording per
# benchmark (after the timed runs, so its overhead touches none of them).
# Rank a recording with `jfr view --width 170 hot-methods <file>.jfr`, and
# break a saved run down with tools/build/unit-load-exclusive.raku.
#
# Children get a CLOSED stdin and one MERGED output stream: with an inherited
# stdin and separate :out/:err, rakudo-j hung under watched-run (2026-09-13).
#
#     RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=prof.log \
#         --show=best-of-5 --stall=600 -- raku tools/build/unit-load-profile.raku --out=prof

sub MAIN(
    Str  :$out = 'unit-load-profile',   #= directory for the per-run stats and JFR files
    Int  :$runs = 5,                    #= timed runs per benchmark
    Bool :$jfr = True,                  #= one JFR recording per benchmark after the timed runs
) {
    my $root = $*PROGRAM.IO.absolute.IO.parent.parent.parent;   # tools/build/ -> repo root
    my $dir  = $out.IO.absolute.IO;
    mkdir $dir;

    my $sanity = $root.add('t/01-sanity').dir(test => *.ends-with('.t')).sort.head.relative($root);
    my @bench =
        %( :name<nqp-e>,    :cwd($root.add('nqp')), :cmd(['./nqp-j-gradle', '-e', 'say(1)']) ),
        %( :name<rakudo-e>, :cwd($root),            :cmd(['./rakudo-j', '-e', 'say 1']) ),
        %( :name<sanity>,   :cwd($root),            :cmd(['./rakudo-j', $sanity]) );
    my %base = %*ENV, RAKUDO_RAKUAST => '1';

    sub run-once(%b, $tag, %env) {
        my $t0 = now;
        my $p = run |%b<cmd>, :cwd(%b<cwd>), :in, :out, :merge, :env(%env);
        $p.in.close;
        my $text = $p.out.slurp(:close);
        my $wall = now - $t0;
        $dir.add("%b<name>-$tag.err").spurt($text);
        note sprintf("%-9s %-6s exit=%d wall=%.3fs stage-lines=%d", %b<name>, $tag, $p.exitcode, $wall,
                     +$text.lines.grep(*.starts-with('unit-load ')));
        die "%b<name> $tag: no stats marker (is UnitLoadStats in the runtime jar?)"
            unless $tag.starts-with('jfr') || $text.contains('unit-load: stats on');
        $wall
    }

    note "sanity file: $sanity";
    for @bench -> %b {
        my @walls = (1..$runs).map: -> $i { run-once(%b, "run$i", %(|%base, NQP_UNIT_LOAD_STATS => '1')) };
        my $best  = @walls.min;
        my $besti = @walls.first(* == $best, :k) + 1;
        say sprintf("%-9s best-of-%d wall=%.3fs (run%d)  all: %s", %b<name>, $runs, $best, $besti,
                    @walls.map({ sprintf '%.2f', $_ }).join(' '));
        $dir.add("%b<name>-best").spurt("run$besti\n");
    }
    if $jfr {
        for @bench -> %b {
            my $file = $dir.add("%b<name>.jfr");
            run-once(%b, 'jfr', %(|%base, JAVA_TOOL_OPTIONS => "-XX:StartFlightRecording=filename=$file,settings=profile"));
            say "%b<name> jfr: $file ({ $file.e ?? $file.s !! 'MISSING' } bytes)";
        }
    }
    say "UNIT-LOAD-PROFILE-DONE";
}
