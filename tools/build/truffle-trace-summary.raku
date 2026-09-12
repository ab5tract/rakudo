#!/usr/bin/env raku

# Summarizes a Truffle compilation trace (-Dpolyglot.engine.TraceCompilation=true).
#
# A trace line looks like:
#   [engine] opt done   engine=1  id=2  <anon>[0]  |Tier 1|Time  37(  31+6 )ms|...
# The root name carries the program's wire-word count in brackets, because
# NqpRootNode.getName() appends it. Fields after the name are split on '|'
# and matched by their leading word, never by position, so a field order
# change in a future GraalVM does not silently mis-parse.

sub MAIN($log, Int :$top = 20) {
    my @events;
    for $log.IO.lines -> $line {
        next unless $line.starts-with('[engine] opt ');
        my ($head, @fields) = $line.split('|');
        $head ~~ / ^ '[engine] opt ' $<verb>=(\S+) \s+ 'engine=' \d+ \s+ 'id=' \d+ \s+ $<name>=(.+?) \s* $ /
            or next;
        # Read both captures BEFORE any further match: the next ~~ replaces
        # $/, and $<verb> would then resolve against the wrong match.
        my $verb = ~$<verb>;
        my $name = ~$<name>;
        my $size = $name ~~ / '[' $<n>=(\d+) ']' $ / ?? +$<n> !! Int;
        my %f;
        for @fields -> $f {
            my $t = $f.trim;
            %f<tier>   = +$0 if $t ~~ / ^ 'Tier' \s+ (\d+) /;
            %f<ms>     = +$0 if $t ~~ / ^ 'Time' \s+ (\d+) /;
            %f<reason> = ~$0 if $t ~~ / ^ 'Reason' \s+ (.+) $ /;
        }
        @events.push: {
            :$verb, :$name, :$size,
            tier => %f<tier> // 0, ms => %f<ms> // 0,
            reason => %f<reason> // '',
        };
    }

    my %by-verb = @events.classify(*<verb>);
    say "events=@events.elems()";
    say "$_=%by-verb{$_}.elems()" for %by-verb.keys.sort;

    my @failed = @events.grep(*<verb> eq 'failed');
    if @failed {
        say "\n--- failures by reason ---";
        for @failed.classify(*<reason>).sort(-*.value.elems) -> $g {
            my $mean = ($g.value.map(*<ms>).sum / $g.value.elems).round;
            say "  count={ $g.value.elems }  mean={ $mean }ms  { $g.key }";
        }
    }

    my @too-large = @failed.grep({ .<reason>.contains('code is too large') && .<size>.defined });
    say "\nmin-too-large-size={ @too-large ?? @too-large.map(*<size>).min !! 'none' }";

    say "\n--- top $top roots by compile time ---";
    for @events.sort(-*<ms>).head($top) -> $e {
        say sprintf('  %7dms  %-6s  tier %d  %s', $e<ms>, $e<verb>, $e<tier>, $e<name>);
    }

    say "\ntotal-compiler-ms={ @events.map(*<ms>).sum }";
}
