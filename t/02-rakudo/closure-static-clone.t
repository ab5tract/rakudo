use lib <lib>;
use Test;
# Closure creation on the JVM takes a static clone road (milestone 7 A6'):
# p6clonecode in place of `callmethod clone` wherever the code object's clone
# is Block's or Code's own and it has neither phasers nor declarator docs.
# The observable semantics of that clone must hold on every backend.
plan 8;

my @closures = (1..3).map: -> $i { -> { $i } };
is @closures.map({ .() }).join(','), '1,2,3', 'each closure captures its own outer';
ok @closures[0] !=== @closures[1], 'each creation is a distinct object';

sub outer { my $x = 42; -> { $x } }
is outer()(), 42, 'a closure returned from a sub still reads its lexical';

my &f = -> Int $a, Str $b { "$a$b" };
is &f.signature.gist, '(Int $a, Str $b)', 'the signature survives the clone';

#| documented
my &g = -> { 1 };
my &h = &g.clone;
is &h.WHY.Str, 'documented', '.clone through the method road still works';

# A clone's containers are its own, whichever road made it.
class Aliasing { has $.x is rw }
my $orig = Aliasing.new(:x(1));
my $copy = $orig.clone;
$copy.x = 2;
is $orig.x, 1, 'a method-road clone does not alias its original';

# The static road must clone $!do per creation: a shared code ref would let
# the second creation's p6capturelex overwrite the first's captured outer.
my @c = (1..2).map: -> $n { -> { $n } };
ok @c[0] !=== @c[1] && @c[0]() == 1 && @c[1]() == 2,
   'two closures from one site have their own code ref (distinct captured outers)';

my $ran = 0;
for 1..2 { LAST { $ran++ } }
is $ran, 1, 'a block with a LAST phaser runs it once (phasers copied by the clone)';
