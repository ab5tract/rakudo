#!/usr/bin/env raku
# List JVM methods whose bytecode runs past HotSpot's HugeMethodLimit
# (8000 bytes). With DontCompileHugeMethods at its default (true) such a
# method is never JIT-compiled: NqpOps.run0, the table road's switch,
# was one (milestone 8, B2, spec 6.6). Reads `javap -c -p` for every
# .class under the given directories; only instruction lines count
# (a switch table's case labels are indented deeper and are skipped).
#
#   raku tools/build/huge-methods.raku nqp/nqp-truffle/build/classes/java/main \
#       nqp/nqp-truffle/build/classes/kotlin/main nqp/nqp-runtime/build/classes/kotlin/main
sub MAIN(*@dirs) {
    my @hits;
    for @dirs -> $dir {
        for classes-under($dir.IO) -> $class {
            my $p = run 'javap', '-c', '-p', $class.Str, :out, :err;
            my $name = '';
            for $p.out.lines -> $l {
                # A method header: two-space indent, a signature ending in ');'
                if $l ~~ / ^ '  ' \S .* '(' .* ')' ';' $ / { $name = $l.trim; next }
                # An instruction line: 1-7 spaces, offset, colon, an opcode name.
                if $l ~~ / ^ \s ** 1..7 (\d+) ':' \s+ <[a..z]> / {
                    if +$0 > 8000 && $name ne '' {
                        @hits.push([+$0, $class.Str, $name]);
                        $name = '';
                    }
                }
            }
        }
    }
    for @hits.sort(-*[0]) -> $h { say "$h[0]\t$h[1]\t$h[2]" }
    say "huge methods: { +@hits }";
}

sub classes-under(IO::Path $d) {
    $d.dir.map({ .d ?? classes-under($_).Slip !! (.extension eq 'class' ?? $_ !! Empty) })
}
