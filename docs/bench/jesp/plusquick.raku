use nqp;
my $a = 1; my $b = 2; my $s = 0;
my int $w = 0; while $w < 5000000 { $s = $a + $b; $w = $w + 1; }
my $t0 = nqp::time(); my int $i = 0;
while $i < 40000000 { $s = $a + $b; $i = $i + 1; }
nqp::say("ns/op=" ~ (nqp::sub_i(nqp::time(),$t0) / 40000000) ~ " s=" ~ $s);
