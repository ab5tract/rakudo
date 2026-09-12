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
#   * A '|' turns up inside the data on BOTH sides of the fields. A root NAME
#     can contain one (infix:<|> and infix:<+|> are real Rakudo operators),
#     and so can a REASON text, because those operator names appear in
#     inlining-failure messages. Splitting the whole line on '|' cuts both in
#     half. So the head is cut at the first whitespace-then-'|', which is how
#     the format separates the %-50s name from the fields (a '|' inside a name
#     is never preceded by whitespace); and within the tail, a piece that does
#     not look like the start of a field is rejoined to the piece before it.
#
# Nothing is discarded silently: every [engine] opt line that fails the head
# match is counted in unparsed=, a failure whose reason did not parse is
# announced on the min-too-large-size line itself rather than passing for
# "nothing was too large", and a failure reason that parsed but matched no
# known size-bailout spelling is printed with the sizes behind it rather than
# quietly leaving the population.

# The spellings of "this root was too large to compile". They are not one
# message: "code is too large" is the code-installation limit, while "too big
# to safely compile. Node count: N" is the PermanentBailoutException on graph
# size in libjvmcicompiler.so. Substring matches, never exact ones.
#
# ONLY SPELLINGS VERIFIED TO EXIST IN THIS TREE BELONG HERE. Nothing guessed,
# and in particular nothing as loose as a bare 'exceeds': "inlining of foo
# exceeds the inlining budget" is an inlining decision about a 40-word root,
# not a size bailout, and classifying it sets min-too-large-size=40 -- a
# threshold that would refuse essentially every compilation and destroy the
# measurement rather than merely bias it.
#
# A guessed spelling does not extend this tool's reach; it bypasses the
# mechanism that already covers the unknown. The unclassified-reasons report
# below prints any unmatched failure reason with its count and its sizes,
# loudly, for a human to read. A too-loose entry here converts that loud
# unknown into a silent wrong answer, and a wrong threshold is invisible to
# the tool's own alarm by construction: a reason that matched a spelling is,
# by definition, not unclassified. When a real trace shows a size bailout this
# list does not know, it will appear in that block -- add it here THEN, with
# the trace that proves it.
my @SIZE-BAILOUT-SPELLINGS = 'code is too large', 'too big to safely compile';

sub size-bailout($reason --> Bool) {
    so @SIZE-BAILOUT-SPELLINGS.first({ $reason.contains($_) });
}

# A field starts with a capitalised word then whitespace, optionally with a
# colon: Tier, Time, AST, Inlined, IR, CodeSize, Addr, CompId, UTC, Src,
# "Reason:". Anything else is the continuation of a value that contained a
# '|'. This is deliberately a SHAPE test and not a list of known field names,
# so an unfamiliar future field still reads as a field; and if it ever guesses
# wrong the result is an over-long value, never a truncated one.
sub field-start($piece --> Bool) {
    so $piece ~~ / ^ <[A..Z]> \w* ':'? \s /;
}

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
        # Rejoin the pieces of a field value that itself contained a '|'.
        my @fields;
        for $tail.split('|') -> $piece {
            if @fields && !field-start($piece) {
                @fields[*-1] ~= '|' ~ $piece;
            }
            else {
                @fields.push: $piece;
            }
        }
        my %f;
        for @fields -> $f {
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

    my @too-large    = @failed.grep({ size-bailout(.<reason>) });
    my @sized        = @too-large.grep({ .<size>.defined });
    my @unsized      = @too-large.grep({ !.<size>.defined });
    my @unclassified = @failed.grep({ .<reason>.chars && !size-bailout(.<reason>) });
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
    # The spelling list above will go stale. Every other failure reason is
    # named here WITH its sizes, so a root that belongs in the population but
    # was not recognised shows up as a line to read rather than as an absence.
    # A size here smaller than the minimum above is the alarm: the minimum is
    # reading high, and a threshold set from it would miss that root.
    if @unclassified {
        say "  unclassified failure reasons (not matched as a size bailout):";
        for @unclassified.classify(*<reason>).sort(-*.value.elems) -> $g {
            my $sizes = $g.value.sort({ .<size> // Inf })
                              .map({ .<size>.defined ?? ~.<size> !! 'no-size' }).join(', ');
            say "    count={ $g.value.elems }  sizes: $sizes  { $g.key }";
        }
    }

    say "\n--- top $top roots by compile time ---";
    for @events.sort(-*<ms>).head($top) -> $e {
        say sprintf('  %7dms  %-6s  tier %d  %s', $e<ms>, $e<verb>, $e<tier>, $e<name>);
    }

    say "\ntotal-compiler-ms={ @events.map(*<ms>).sum }";
    say "nqp-root-ms={ @events.grep({ .<size>.defined }).map(*<ms>).sum }";
}
