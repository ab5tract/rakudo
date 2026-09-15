#!/usr/bin/env raku
use v6.d;

# The per-program half of the NQP_SITE_CHECK invariant.
#
# A run with NQP_SITE_CHECK=1 prints two kinds of line to stderr:
#
#   site-check      <namespace>#<programIndex> ordinals=K
#   unit-check-prog <namespace>#<programIndex> slots=N
#
# The first comes from the engine (NqpProgramBuilder), once per program it
# builds: K is how many DISPATCH instructions that program numbered. The
# second comes from the runtime (ProgramUnit.buildTable), once per live
# program of every loaded artifact: N is how many dispatch slots the store
# actually holds for it. Both name the program the same way, so the two
# streams join on the whole token.
#
# The invariant is K <= N. It matters because nothing enforces it at run
# time: UnitStore.dispatchSlot bounds the ordinal by the program's own slot
# count and returns null past it, so a program that numbers more ordinals
# than it stores slots loses Phase C's persisted records in silence. The
# per-unit `unit-check` line is an aggregate and cannot see that; this is
# the per-program check.
#
#   NQP_SITE_CHECK=1 RAKUDO_RAKUAST=1 ./rakudo-j -e 'say 1' 2> run.err
#   raku tools/build/site-check.raku run.err

my %*SUB-MAIN-OPTS = :named-anywhere;

sub MAIN(
    $file,                      #= stderr of a run made with NQP_SITE_CHECK=1
    Bool :$quiet = False,       #= print only the summary line
) {
    my %ordinals;               # program -> the most ordinals any line claimed
    my %slots;                  # program -> the fewest slots any line offered
    my $lines = 0;

    for $file.IO.lines -> $l {
        if $l ~~ / ^ 'site-check ' (\S+) ' ordinals=' (\d+) / {
            my ($prog, $k) = ~$0, +$1;
            $lines++;
            %ordinals{$prog} = ($k, %ordinals{$prog} // 0).max;
        }
        elsif $l ~~ / ^ 'unit-check-prog ' (\S+) ' slots=' (\d+) / {
            my ($prog, $n) = ~$0, +$1;
            $lines++;
            # A store opened twice reports the same count; the minimum is
            # the honest one if two ever disagreed.
            %slots{$prog} = %slots{$prog}:exists ?? (%slots{$prog}, $n).min !! $n;
        }
    }

    die "no site-check or unit-check-prog lines in $file (was NQP_SITE_CHECK=1 set?)"
        unless $lines;

    my @violations;
    my @unmatched;
    for %ordinals.keys.sort -> $prog {
        my $k = %ordinals{$prog};
        if %slots{$prog}:exists {
            @violations.push: ($prog, $k, %slots{$prog}) if $k > %slots{$prog};
        }
        else {
            @unmatched.push: ($prog, $k);
        }
    }

    unless $quiet {
        for @violations -> ($prog, $k, $n) {
            say "$prog ordinals=$k slots=$n";
        }
        for @unmatched -> ($prog, $k) {
            say "$prog ordinals=$k slots=none  (no unit-check-prog line)";
        }
    }
    say "site-check: {+%ordinals.keys} programs, {+@violations} violations";
    say "site-check: {+@unmatched} programs with no unit-check-prog line"
        if @unmatched;

    exit 1 if @violations;
}
