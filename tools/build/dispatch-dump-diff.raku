#!/usr/bin/env raku
# Milestone 7 Phase C, C0: size the persisted miss from NQP_DISPATCH_DUMP files.
#
#   raku tools/build/dispatch-dump-diff.raku run1.dump [run2.dump] [--stats=run1.out]
#
# A dump (DispatchDump.kt in nqp-runtime) has one `site <identity|anon>
# <dispatcher> <programs>[ indy]` line per registered callsite and one
# `prog <n> <normalised text>` line per installed program, every reference
# named by its serialization context or marked NP(...) when it has none.
# Reported per dispatcher: sites that recorded, programs, persistable
# programs (no NP), and -- with a second dump -- programs whose text also
# stands at the same site identity in the other run. --stats adds the
# misses-by-dispatcher histogram from a `dispatch stats:` capture so the
# expected remaining recordings can be read off the same table.
use v6.d;
my %*SUB-MAIN-OPTS = :named-anywhere;

class Site {
    has Str $.identity;
    has Str $.dispatcher;
    has Bool $.indy;
    has @.programs;
}

sub parse-dump(IO() $file) {
    my @sites;
    my Site $cur;
    for $file.lines {
        if .starts-with('site ') {
            my @f = .split(' ');
            $cur = Site.new(:identity(@f[1]), :dispatcher(@f[2]),
                :indy(@f.elems > 4 && @f[4] eq 'indy'));
            @sites.push($cur);
        }
        elsif .starts-with('prog ') {
            die "prog line before any site line in $file" without $cur;
            $cur.programs.push(.subst(/^ 'prog ' \d+ ' '/, ''));
        }
    }
    @sites
}

sub parse-stats(IO() $file) {
    my %misses;
    for $file.lines {
        %misses{$1} = +$0 if / ^ '  misses ' (\d+) ' ' (\S+) /;
    }
    %misses
}

sub np-causes(Str $text) {
    $text.comb(/ 'NP(' <-[)]>* ')' /).map({ .subst(/ ':' \d+ $ /, '') }).unique
}

sub MAIN(IO() $a, IO() $b?, Str :$stats) {
    my @a = parse-dump($a);
    my %b-texts;   # identity -> set of program texts, from the second dump
    my %b-count;
    if $b {
        for parse-dump($b) -> $s {
            next if $s.identity eq 'anon';
            %b-texts{$s.identity} = set $s.programs;
            %b-count{$s.dispatcher}<sites>++ if $s.programs;
            %b-count{$s.dispatcher}<programs> += $s.programs.elems;
        }
    }
    my %misses = $stats ?? parse-stats($stats) !! ();

    my %by;         # dispatcher -> counts
    my %causes;     # NP cause -> programs carrying it
    my %cause-by;   # dispatcher -> NP cause -> programs
    my $anon-sites = 0;
    my $anon-programs = 0;
    my $silent = 0; # parsed, never dispatched
    for @a -> $s {
        if !$s.programs { $silent++; next }
        if $s.identity eq 'anon' { $anon-sites++; $anon-programs += $s.programs.elems }
        my $d = %by{$s.dispatcher} //= {};
        $d<sites>++;
        $d<sites-clean>++ unless $s.programs.first(*.contains('NP('));
        for $s.programs -> $p {
            $d<programs>++;
            my @np = np-causes($p);
            if @np {
                $d<np>++;
                for @np { %causes{$_}++; %cause-by{$s.dispatcher}{$_}++ }
            }
            if $b && $s.identity ne 'anon' {
                $d<same>++ if %b-texts{$s.identity} && $p (elem) %b-texts{$s.identity};
            }
        }
    }

    my @cols = <dispatcher sites programs persistable unpersistable>;
    @cols.push('same-in-B') if $b;
    @cols.push('misses') if $stats;
    say '| ' ~ @cols.join(' | ') ~ ' |';
    say '|' ~ ('---|' xx @cols).join;
    my %tot;
    for %by.sort(-*.value<programs>) -> (:key($name), :value($d)) {
        my @row = $name, $d<sites>, $d<programs>, $d<programs> - ($d<np> // 0), $d<np> // 0;
        @row.push($d<same> // 0) if $b;
        @row.push(%misses{$name} // '-') if $stats;
        say '| ' ~ @row.join(' | ') ~ ' |';
        %tot<sites> += $d<sites>; %tot<programs> += $d<programs>;
        %tot<np> += $d<np> // 0; %tot<same> += $d<same> // 0;
        %tot<misses> += %misses{$name} // 0;
    }
    my @row = 'total', %tot<sites>, %tot<programs>, %tot<programs> - %tot<np>, %tot<np>;
    @row.push(%tot<same>) if $b;
    @row.push(%tot<misses>) if $stats;
    say '| ' ~ @row.join(' | ') ~ ' |';
    say '';
    printf "persistable programs: %d of %d (%.1f%%)\n",
        %tot<programs> - %tot<np>, %tot<programs>, 100 * (%tot<programs> - %tot<np>) / %tot<programs>;
    printf "identical at the same site in B: %d of %d (%.1f%%)\n",
        %tot<same>, %tot<programs> - $anon-programs, 100 * %tot<same> / (%tot<programs> - $anon-programs) if $b;
    say "sites parsed but never dispatched: $silent; anonymous sites with programs: $anon-sites ($anon-programs programs)";
    say '';
    say 'unpersistable causes (programs carrying each):';
    for %causes.sort(-*.value) -> (:key($c), :value($n)) {
        say "  $n  $c  [" ~ %cause-by.grep(*.value{$c}).map({ .key ~ '=' ~ .value{$c} }).join(' ') ~ ']';
    }
}
