#!/usr/bin/env raku
# Unit-artifact census: for each jar named on the command line, report how
# many `unit.meta` entries and how many `.class` entries it holds, plus the
# count of `nested/` entries. A unit artifact is meta=1 class=0.
sub MAIN(*@jars, Bool :$nested = False) {
    my $bad = 0;
    for @jars -> $jar {
        unless $jar.IO.e { say "MISSING  $jar"; $bad++; next }
        my @lines = run(«unzip -l $jar», :out).out.slurp(:close).lines;
        my $meta   = @lines.grep({ / 'unit.meta' $ / }).elems;
        my $class  = @lines.grep({ / '.class' $ / }).elems;
        my $nest   = @lines.grep({ / 'nested/' / }).elems;
        my $ok     = ($meta == 1 && $class == 0);
        $bad++ unless $ok;
        say sprintf("%-7s meta=%-3d class=%-5d%s  %s",
            ($ok ?? 'ARTIFACT' !! 'CLASS'), $meta, $class,
            ($nested ?? " nested=$nest" !! ''), $jar);
    }
    say $bad ?? "CENSUS: $bad jar(s) not a unit artifact" !! "CENSUS: all { @jars.elems } jars are unit artifacts";
    exit($bad ?? 1 !! 0);
}
