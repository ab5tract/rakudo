use Test;
plan 8;

role Modified { has $.tag = "m"; method shout { "modified" } }
class Foo { has $.x = 1 }

my $obj = Foo.new(x => 42);
my $which = $obj.WHICH;
my $butted = $obj but Modified;
nok $obj === $butted, 'but yields a new identity';
is $obj.WHICH, $which, 'but leaves the original WHICH alone';
is $obj.^name, 'Foo', 'but leaves the original type alone';
is $butted.tag, 'm', 'the but-clone has the role attribute';

my $obj2 = Foo.new(x => 7);
my $w2 = $obj2.WHICH;
my $doesd = $obj2 does Modified;
ok $obj2 === $doesd, 'does keeps identity';
is $obj2.x, 7, 'does keeps the attribute values';
is $obj2.shout, 'modified', 'does adds the role method';
is $obj2.^name, 'Foo+{Modified}', 'does changes the type in place';
