my @pool = (^500).map({ ("e\c[COMBINING ACUTE ACCENT]\c[GRINNING FACE]" x 10) ~ $_ });
my int $acc = 0;
my $t0 = now;
for ^200 {
  for @pool -> $s {
    $acc += $s.chars;
    $acc += $s.flip.chars;                 # fresh string -> NFG segment
    $acc += $s.substr(3, 15).comb.elems;   # substr+comb -> NFG segment
    $acc += $s.ords.elems;                 # -> codepoints
  }
}
say "nfg-string acc=$acc elapsed={ (now - $t0).round(0.01) }s";
