use nqp;
# Five attribute roads, ns/op each, single run. 2M warmup + 20M timed.
class P { has $.a; has $.b }
my class N { has int $.i; has num $.n }
my $p := P.new(a => 1, b => 2);   # bound, not assigned: nqp::getattr needs the object, not a Scalar
my $n := N.new(i => 3, n => 4e0);   # likewise
my $s := my $scalar = 42;        # a Scalar container: decont road
my $big = 2 ** 70;               # bigint road (never fits a long)
my $sum = 0;

sub timed(Str $name, &code) {
    my int $w = 0; while $w < 2000000 { code(); $w = $w + 1; }
    my $t0 = nqp::time(); my int $i = 0;
    while $i < 20000000 { code(); $i = $i + 1; }
    nqp::say($name ~ " ns/op=" ~ (nqp::sub_i(nqp::time(), $t0) / 20000000));
}
timed("getattr",  { $sum = nqp::getattr($p, P, '$!a') });
timed("bindattr", { nqp::bindattr($p, P, '$!b', $sum) });
timed("getattr_i",{ $sum = nqp::getattr_i($n, N, '$!i') });
timed("decont",   { $sum = nqp::decont($scalar) });
timed("bigint+",  { $sum = $big + $big });
timed("create",   { $sum = P.new });
nqp::say("check " ~ $sum.^name);
