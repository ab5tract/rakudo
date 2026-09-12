use Test;
plan 9;

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
# The whole .WHICH is NOT kept, and that is not a JVM gap: .WHICH is
# .^name ~ '|' ~ nqp::objectid, `does` changes the type in place, and
# MoarVM answers 'Foo+{Modified}|<id>' against 'Foo|<id>' for exactly
# this program (checked 2026-09-12). The object-id half IS preserved --
# that is what test 5's `===` pins. Left standing as a todo rather than
# weakened to the id half, so the expectation stays visible.
todo 'does replaces the type half of .WHICH on MoarVM too; only the object id survives';
is $obj2.WHICH, $w2, 'does keeps WHICH';
is $obj2.x, 7, 'does keeps the attribute values';
is $obj2.shout, 'modified', 'does adds the role method';
is $obj2.^name, 'Foo+{Modified}', 'does changes the type in place';
