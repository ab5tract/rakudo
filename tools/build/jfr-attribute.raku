#!/usr/bin/env raku
# Attribute JFR execution samples to the load stages that contain them.
#
# `jfr print --events jdk.ExecutionSample --stack-depth N` lists each sample's
# frames leaf-first. A sample belongs to a container when one of its frames
# matches the container's pattern; inside each container the report shows the
# hottest leaf frames and the hottest project frames (org.raku.*, excluding
# the generated interpreter classes), counted once per sample (inclusive).
#
#     raku tools/build/jfr-attribute.raku prof/rakudo-e.jfr
#     raku tools/build/jfr-attribute.raku --container='load-block=runLoadIfAvailable' \
#         --container='deserialize=runDeserializeIfAvailable' --top=15 file.jfr

sub MAIN(
    Str  $jfr,                        #= the recording
    Int  :$depth = 64,                #= frames per sample to print
    Int  :$top = 12,                  #= rows per table
    Str  :$thread,                    #= only samples on this thread name
    Bool :$innermost = False,         #= match only the Java frames between the leaf and the nearest interpreter frame (exclusive shares)
    *@container,                      #= name=frame-substring pairs; default: the unit load stages
) {
    @container ||= <load-block=runLoadIfAvailable deserialize=runDeserializeIfAvailable
                    build-table=ProgramUnit.buildTable sc=SerializationReader.deserialize
                    decode=UnitLoader.readRecord parse-program=NqpWire.decode>;
    my @c = @container.map({ my ($n, $p) = .split('=', 2); %( :name($n), :pat($p) ) });
    my $p = run 'jfr', 'print', '--events', 'jdk.ExecutionSample', '--stack-depth', $depth, $jfr, :out;
    my (@samples, $cur, $thr, $in-stack);
    my %threads;
    for $p.out.lines -> $l {
        if $l ~~ /^ 'jdk.ExecutionSample' / { $cur = []; $in-stack = False; $thr = ''; next }
        next without $cur;
        if $l ~~ /'sampledThread = "' (<-["]>+) '"'/ { $thr = ~$0; next }
        if $l ~~ /'stackTrace = ['/ { $in-stack = True; next }
        if $in-stack {
            if $l ~~ /^ \s* ']' / {
                $in-stack = False;
                %threads{$thr}++;
                @samples.push: %( :thr($thr), :frames($cur) ) if !$thread || $thr eq $thread;
                $cur = Nil;
            }
            elsif $l ~~ /^ \s+ (\S+) / {
                my $f = ~$0;                 # "pkg.Class.method(Args)" -> drop the argument list
                $f = $f.subst(/ '(' .* $/, '');
                $cur.push: $f;
            }
        }
    }
    say sprintf "%d samples (%s)", +@samples, %threads.sort(-*.value).map({ "{.key} {.value}" }).join(', ');
    say "";
    sub region(@f) {
        # the frames above the innermost generated interpreter frame; the whole stack otherwise
        my $i = @f.first({ .contains('NqpRootNodeGen') }, :k);
        $innermost && $i.defined ?? @f[^$i] !! @f
    }
    if $innermost {
        my @self = @samples.grep({ .<frames>[0].contains('NqpRootNodeGen') });
        say sprintf "interpreter self (leaf is a generated frame): %d samples %.1f%%", +@self, 100 * @self / (@samples || 1);
        my %h; %h{.<frames>[0].subst(/^ .* '$' /, '')}++ for @self;
        say sprintf "   %5d  %5.1f%%  %s", .value, 100 * .value / (@self || 1), .key for %h.sort(-*.value).head($top);
        say "";
    }
    my %seen-in;
    for @c -> %c {
        my @in = @samples.grep({ region(.<frames>.list).first(*.contains(%c<pat>)) });
        my $n = +@in;
        say sprintf "== %-14s %5d samples  %5.1f%%   (frame contains '%s')", %c<name>, $n, 100 * $n / (@samples || 1), %c<pat>;
        next unless $n;
        my (%leaf, %incl, %top-op);
        for @in -> %s {
            my @f = %s<frames>.list;
            %leaf{@f[0]}++;
            my %once;
            for @f -> $f {
                next unless $f.starts-with('org.raku');
                next if $f.contains('NqpRootNodeGen') || $f.contains('BytecodeNode');
                %incl{$f}++ unless %once{$f}++;
            }
            # the op the interpreter called: the outermost project frame above the
            # first generated interpreter frame, i.e. the runtime entry from engine code
            my $i = @f.first(*.contains('NqpRootNodeGen'), :k);
            if $i.defined && $i > 0 {
                my $entry = @f[^$i].reverse.first(*.starts-with('org.raku'));
                %top-op{$entry}++ if $entry;
            }
        }
        say "   leaf frames:";
        say sprintf "   %5d  %5.1f%%  %s", .value, 100 * .value / $n, .key for %leaf.sort(-*.value).head($top);
        say "   entry from interpreter (outermost project frame above the first generated frame):";
        say sprintf "   %5d  %5.1f%%  %s", .value, 100 * .value / $n, .key for %top-op.sort(-*.value).head($top);
        say "   inclusive project frames:";
        say sprintf "   %5d  %5.1f%%  %s", .value, 100 * .value / $n, .key for %incl.sort(-*.value).head($top);
        say "";
    }
    my @none = @samples.grep(-> %s { !%s<frames>[0].contains('NqpRootNodeGen') && !@c.first({ region(%s<frames>.list).first(*.contains(.<pat>)) }) });
    say sprintf "== %-14s %5d samples  %5.1f%%", 'outside all', +@none, 100 * @none / (@samples || 1);
    my %leaf; %leaf{.<frames>[0]}++ for @none;
    say sprintf "   %5d  %5.1f%%  %s", .value, 100 * .value / (@none || 1), .key for %leaf.sort(-*.value).head($top);
}
