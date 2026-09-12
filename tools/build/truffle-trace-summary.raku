#!/usr/bin/env raku

# Summarizes a Truffle compilation trace (-Dpolyglot.engine.TraceCompilation=true).
#
# A trace line looks like:
#   [engine] opt done   engine=1  id=2  <anon>[0]  |Tier 1|Time  37(  31+6 )ms|...
# The root name carries the program's wire-word count in brackets, because
# NqpRootNode.getName() appends it. Fields after the name are split on '|'
# and matched by their leading word, never by position, so a field order
# change in a future GraalVM does not silently mis-parse.
#
# Two shapes of the real format bite, and both are guarded here:
#
#   * TraceCompilationListener.FAILED_FORMAT (decompiled from the
#     truffle-runtime jar this tree runs) is
#       opt failed engine=%-2d id=%-5d %-50s |Tier %d|Time %18s|Reason: %s|UTC %s|Src %s
#     with a COLON after Reason, while DEOPT/INV/UNQUEUED write "|Reason %s|"
#     without one. The colon therefore lands on exactly the verb whose reason
#     decides NQP_CODE_MAX_COMPILE, so the field match treats it as optional.
#
#   * A root name can itself contain '|': infix:<|> and infix:<+|> are real
#     Rakudo operators. Splitting the whole line on '|' cuts such a name in
#     half and loses its size. The head is cut instead at the first
#     whitespace-then-'|', which is how the format separates the %-50s name
#     from the fields (a '|' inside a name is never preceded by whitespace),
#     and only the tail is split.
#
# Nothing is discarded silently: every [engine] opt line that fails the head
# match is counted in unparsed=, and a failure whose reason did not parse is
# announced on the min-too-large-size line itself rather than passing for
# "nothing was too large".

sub MAIN($log, Int :$top = 20) {
    my @events;
    my $unparsed  = 0;
    my $non-trace = 0;
    for $log.IO.lines -> $line {
        unless $line.starts-with('[engine] opt ') {
            $non-trace++;
            next;
        }
        # Cut the head at the first whitespace-then-'|' so that a '|' inside
        # the root name stays with the name.
        my $head = $line;
        my $tail = '';
        if $line ~~ / ^ .+? \s '|' / {
            $head = $line.substr(0, $/.to - 1);
            $tail = $line.substr($/.to);
        }
        $head ~~ / ^ '[engine] opt ' $<verb>=(\S+) \s+ 'engine=' \d+ \s+ 'id=' \d+ \s+ $<name>=(.+?) \s* $ /
            or do { $unparsed++; next };
        # Read both captures BEFORE any further match: the next ~~ replaces
        # $/, and $<verb> would then resolve against the wrong match.
        my $verb = ~$<verb>;
        my $name = ~$<name>;
        my $size = $name ~~ / '[' $<n>=(\d+) ']' $ / ?? +$<n> !! Int;
        my %f;
        for $tail.split('|') -> $f {
            my $t = $f.trim;
            %f<tier>   = +$0 if $t ~~ / ^ 'Tier' \s+ (\d+) /;
            %f<ms>     = +$0 if $t ~~ / ^ 'Time' \s+ (\d+) /;
            %f<reason> = ~$0 if $t ~~ / ^ 'Reason' ':'? \s+ (.+) $ /;
        }
        @events.push: {
            :$verb, :$name, :$size,
            tier => %f<tier> // 0, ms => %f<ms> // 0,
            reason => %f<reason> // '',
        };
    }

    my @reasoned = @events.grep({ .<reason>.chars });
    my %by-verb  = @events.classify(*<verb>);
    say "events=@events.elems()";
    say "$_=%by-verb{$_}.elems()" for %by-verb.keys.sort;
    say "unparsed=$unparsed";
    say "non-trace-lines=$non-trace";
    say "reasons-parsed={ @reasoned.elems }";

    my @failed = @events.grep(*<verb> eq 'failed');
    if @failed {
        say "\n--- failures by reason ---";
        for @failed.classify(*<reason>).sort(-*.value.elems) -> $g {
            my $mean = ($g.value.map(*<ms>).sum / $g.value.elems).round;
            my $what = $g.key.chars ?? $g.key !! '(no Reason field parsed)';
            say "  count={ $g.value.elems }  mean={ $mean }ms  { $what }";
        }
    }

    my @too-large = @failed.grep({ .<reason>.contains('code is too large') });
    my @sized     = @too-large.grep({ .<size>.defined });
    my @unsized   = @too-large.grep({ !.<size>.defined });
    # A bare "none" must never be mistakable for "nothing was too large" when
    # the real story is that the reason field itself stopped parsing.
    my $note = @failed && !@reasoned
        ?? "  (failed={ @failed.elems }, reasons-parsed=0)" !! '';
    say "\nmin-too-large-size={ @sized ?? @sized.map(*<size>).min !! 'none' }$note";
    if @too-large {
        say "  too-large roots: { @too-large.elems } ({ @sized.elems } sized, { @unsized.elems } unsized)";
        say "  by size: { @sized.sort(*<size>).map(*<name>).join(', ') }" if @sized;
        # An unsized too-large root is EXCLUDED from the minimum, which pushes
        # the threshold UP and makes the knob miss the roots it exists to skip.
        say "  UNSIZED (excluded, so the minimum above reads high): { @unsized.map(*<name>).join(', ') }"
            if @unsized;
    }

    say "\n--- top $top roots by compile time ---";
    for @events.sort(-*<ms>).head($top) -> $e {
        say sprintf('  %7dms  %-6s  tier %d  %s', $e<ms>, $e<verb>, $e<tier>, $e<name>);
    }

    say "\ntotal-compiler-ms={ @events.map(*<ms>).sum }";
    say "nqp-root-ms={ @events.grep({ .<size>.defined }).map(*<ms>).sum }";
}
