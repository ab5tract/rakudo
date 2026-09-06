my $N := 50000000;
my $w := 0; while $w < 5000000 { $w := $w + 1 }
my $t0 := nqp::time();
my $acc := 0; my $i := 0;
while $i < $N { $acc := $acc + 1; $i := $i + 1 }
my $dt := nqp::time() - $t0;
nqp::say("calls=" ~ $N ~ " total_ns=" ~ $dt);
