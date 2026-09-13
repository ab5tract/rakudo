#!/usr/bin/env raku
# Exclusive time per load stage, from NQP_UNIT_LOAD_STATS output (one saved run
# of tools/build/unit-load-profile.raku, or any stderr capture of it).
#
# Lines are "unit-load <depth> <unit> <stage> <ms> [counts]". A unit's own
# stages print at depth d and its load-total at d-1, so a child's load-total
# shares the depth of its parent's stages. The children (load-total, sc-stub,
# sc-finish) that print at depth d before a container stage
# (deserialize-program, load-block) at depth d ran inside it and are
# subtracted from it. A load-total counts as a child only while a unit's stages
# are open at that depth: a root load (loadApp at depth 0) charges nobody.
# decode-total contains the decode leaves printed before it, so it is skipped.

sub MAIN($file, Int :$top = 12) {
    my constant CONTAINER = set <deserialize-program load-block>;
    my constant CHILD     = set <load-total sc-stub sc-finish>;
    my %acc;              # depth -> ms of children since the last container
    my %open;             # depth -> a unit's stages are open at this depth
    my %stage;            # stage -> exclusive ms
    my @items;            # (ms, unit, stage)
    my $marker = False;
    for $file.IO.lines -> $l {
        $marker = True if $l eq 'unit-load: stats on';
        next unless $l ~~ /^ 'unit-load ' (\d+) ' ' (\S+) ' ' (\S+) ' ' (<[\d.]>+) /;
        my ($d, $unit, $st, $ms) = +$0, ~$1, ~$2, +$3;
        if $st eq 'load-total' {
            %acc{$d} += $ms if %open{$d};
            %open{$d + 1} = False;
            %acc{$d + 1} = 0;
            next;
        }
        %open{$d} = True;
        %acc{$d} += $ms if $st (elem) CHILD;
        next if $st eq 'decode-total';
        my $x = $ms;
        if $st (elem) CONTAINER {
            $x = $ms - (%acc{$d} // 0);
            %acc{$d} = 0;
        }
        %stage{$st} += $x;
        @items.push: ($x, $unit, $st);
    }
    die "no stats marker in $file" unless $marker;
    my $total = [+] %stage.values;
    say sprintf "exclusive load time: %.1f ms", $total;
    for %stage.sort(-*.value) -> $p {
        say sprintf "  %-20s %8.1f ms  %5.1f%%", $p.key, $p.value, 100 * $p.value / $total;
    }
    say "largest single items:";
    for @items.sort(-*[0]).head($top) -> ($x, $unit, $st) {
        say sprintf "  %8.1f ms  %-28s %s", $x, $unit.substr(0, 28), $st;
    }
}
