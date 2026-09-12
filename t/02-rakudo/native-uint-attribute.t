use Test;

plan 7;

# An unsigned native attribute read as a call argument.
#
# The JVM Truffle encoder wrote each argument's wire RESULT type straight
# into the callsite argument flag, where the low two bits are the type and
# bit 2 (value 4) is NAMED. The uint wire type is 4, so a uint argument
# came out as "a named object argument" and the reader then took the next
# word of the program as a constant-pool index: an out-of-range pool read,
# or -- once the stream had slipped by a word -- "nqpp: unknown tag" on
# some later word. Either way the program failed to decode at all.
#
# A uint ARGUMENT travels in the int slot (a uint lexical always did);
# only a uint RESULT keeps the unsigned type, where it reaches the box.

{
    my class C { has uint32 $!c = 32; method go { my $p := (7 => $!c); $p.value } }
    is C.new.go, 32, 'a uint32 attribute passes as a pair value';
}

{
    my class C { has uint32 $!c = 32; method go { $!c = $!c + 1; $!c } }
    is C.new.go, 33, 'a uint32 attribute reads, adds and writes back';
}

{
    my class C { has uint $!c = 32; method go { my $p := (7 => $!c); $p.value } }
    is C.new.go, 32, 'a uint attribute passes as a pair value';
}

{
    sub f($a) { $a }
    my class C { has uint32 $!c = 4294967295; method go { f($!c) } }
    is C.new.go, 4294967295, 'a uint32 attribute passes its whole unsigned range';
}

{
    sub g(:$x) { $x }
    my class C { has uint32 $!c = 7; method go { g(x => $!c) } }
    is C.new.go, 7, 'a uint32 attribute passes as a named argument';
}

{
    my class C { has uint32 $!c = 32; has int32 $!i = 5; method go { $!c + $!i } }
    is C.new.go, 37, 'a uint32 and an int32 attribute mix in one call';
}

{
    my class C { has uint32 $!c = 32; method go { $!c.WHAT.^name } }
    is C.new.go, 'Int', 'a uint32 attribute boxes to Int';
}
