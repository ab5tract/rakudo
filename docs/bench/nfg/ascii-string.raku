my @pool = (^500).map({ ("abc" x 10) ~ $_ });
my int $acc = 0;
my $t0 = now;
for ^200 {
  for @pool -> $s {
    $acc += $s.chars;
    $acc += $s.flip.chars;
    $acc += $s.substr(3, 15).comb.elems;
    $acc += $s.ords.elems;
  }
}
say "ascii-string acc=$acc elapsed={ (now - $t0).round(0.01) }s";
