use Test;

plan 6;

# A frame packed into a continuation has not exited: it is coming back.
# The save road must therefore leave its live-invocation count alone, or a
# SECOND invocation of the same static frame -- one running while the first
# is suspended -- resolves its blocks' outer to the suspended frame instead
# of its own, and the two invocations share lexicals.
#
# SEQUENCE is where that bites in the setting: its multi-character branch
# builds each character position's range with the sequence operator, which
# is SEQUENCE, so the inner call runs inside the outer call's suspended
# gather. The inner loop's `$stop = 1` landed in the outer frame and its
# `until $stop` never saw it, so every multi-character Str range hung.

is ("aa" .. "ac").elems, 3, 'a two-character Str range terminates';

is ("aa" .. "ac").List.join(','), 'aa,ab,ac',
    'and yields each of its values once';

is ("aa" ... "ac").List.join(','), 'aa,ab,ac',
    'the sequence operator agrees with the range';

is ("zzz00" .. "zzz20").List.join(','), 'zzz00,zzz10,zzz20',
    'a five-character range with a varying tail terminates';

is ("a" .. "e").elems, 5, 'the single-character case is unchanged';

# The shape on its own, without the setting: one routine whose gather body
# calls itself while suspended at a `take`.
{
    sub nest($depth) {
        gather {
            my $stop = 0;
            if $depth > 0 {
                my $ = .take for nest($depth - 1).List;
            }
            my $n = 0;
            until $stop {
                $n = $n + 1;
                my $ = "d$depth.$n".take;
                $stop = 1 if $n >= 2;
            }
        }
    }
    is nest(2).List.join(','), 'd0.1,d0.2,d1.1,d1.2,d2.1,d2.2',
        'a gather that calls its own routine while suspended keeps its own lexicals';
}
