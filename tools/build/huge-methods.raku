# List JVM methods whose bytecode runs past HotSpot's HugeMethodLimit
# (8000 bytes). With DontCompileHugeMethods at its default (true) such a
# method is never JIT-compiled: NqpOps.run0, the table road's switch,
# was one (milestone 8, B2, spec 6.6). Reads `javap -c -p` for every
# .class under the given directories; only instruction lines count
# (a switch table's case labels are indented deeper and are skipped).
#
# The offset printed is the FIRST instruction offset past the limit, not
# the method's length (run0: 8002, while the method ends at 8541).
#
# HotSpot compares the method's code_length; the tool compares an
# instruction's start offset, so a method of 8001..8004 bytes whose last
# instruction starts at or under 8000 is missed. Every method that
# matters here is far past the limit, so the boundary is not tested.
#
# The last line is a positive marker -- `huge methods: 0` alone cannot be
# told apart from "javap never ran". A zero in `scanned:` means the scan
# did nothing, whatever the tally says.
#
#   raku tools/build/huge-methods.raku nqp/nqp-truffle/build/classes/java/main \
#       nqp/nqp-truffle/build/classes/kotlin/main \
#       nqp/nqp-runtime/build/classes/java/main \
#       nqp/nqp-runtime/build/classes/kotlin/main
sub MAIN(*@dirs) {
    my @hits;
    my ($classes, $methods, $insns) = 0, 0, 0;
    for @dirs -> $dir {
        die "no such directory: $dir" unless $dir.IO.d;
        for classes-under($dir.IO) -> $class {
            $classes++;
            my $p = run 'javap', '-c', '-p', $class.Str, :out, :err;
            my @lines = $p.out.lines.eager;     # read stdout, then drain stderr
            my $err   = $p.err.slurp(:close);
            die "javap failed ({ $p.exitcode }) on { $class.Str }: { $err.trim }"
                if $p.exitcode != 0;
            my $name     = '';
            my $reported = False;   # one hit per method, but never lose the name
            my $counted  = False;   # count a method once its first insn shows up
            for @lines -> $l {
                # A member header: two-space indent, anything, ending in ';'.
                # Fields match too (javap prints them all before any method);
                # they carry no instruction lines, so they are harmless.
                # `static {};` is the class initializer -- javap gives it no
                # signature, so name it <clinit> ourselves.
                if $l ~~ / ^ '  ' \S .* ';' $ / {
                    $name     = $l.trim eq 'static {};' ?? '<clinit>' !! $l.trim;
                    $reported = False;
                    $counted  = False;
                    next;
                }
                # An instruction line: 1-12 spaces, offset, colon, an opcode
                # name. Switch-table case labels start at 22+ spaces.
                if $l ~~ / ^ \s ** 1..12 (\d+) ':' \s+ <[a..z]> / {
                    $insns++;
                    unless $counted { $methods++; $counted = True }
                    if +$0 > 8000 && $name ne '' && !$reported {
                        @hits.push([+$0, $class.Str, $name]);
                        $reported = True;
                    }
                }
            }
        }
    }
    for @hits.sort({ (-$_[0], $_[1], $_[2]) }) -> $h { say "$h[0]\t$h[1]\t$h[2]" }
    say "huge methods: { +@hits }";
    say "scanned: $classes classes, $methods methods, $insns instructions";
}

sub classes-under(IO::Path $d) {
    $d.dir.map({ .d ?? classes-under($_).Slip !! (.extension eq 'class' ?? $_ !! Empty) })
}
