#!/usr/bin/env raku
# The segment table of a unit's serialized SC, from the header of
# unit.serialized inside a unit jar (milestone 8, Phase C, C0). Versions
# 11 (fixed rows, length-prefixed strings) and 12 (Phase C's: eight-byte
# object rows, a string offset table before the string data with
# stringHeapOffset pointing at the table; the STable row stays 12 bytes).
#
#     raku tools/build/sc-blob-sizes.raku blib/CORE.c.setting.jar
#
# Reads the entry with `unzip -p` (the jar is Stored, so this is a copy,
# not an inflate). Percentages are of the whole entry. The rows plus the
# 72-byte header must account for every byte of it: they are checked
# against the entry's length, so a wrong assumption about the format
# fails loudly instead of printing wrong shares.
sub MAIN(Str $jar) {
    my $p = run 'unzip', '-p', $jar, 'unit.serialized', :out, :bin;
    my $b = $p.out.slurp(:close, :bin);
    my $failed = "$jar: no unit.serialized entry (or unzip failed)";
    die $failed unless $p.so;
    die $failed unless $b.elems >= 4 * 18;
    my @h = (0..17).map({ $b.read-uint32($_ * 4, LittleEndian) });
    my ($v, $depO, $depN, $stO, $stN, $stD, $objO, $objN, $objD, $cloO, $cloN,
        $ctxO, $ctxN, $ctxD, $repO, $repN, $shO, $shN) = @h;
    die "$jar: serialization version $v; this tool reads 11 and 12" unless $v == 11 | 12;
    my $len = $b.elems;
    my $objRow = $v == 11 ?? 16 !! 8;
    my $strOff = $v == 12 ?? ($shN + 1) * 4 !! 0;
    my @rows =
        deps      => $depN * 8,
        stTable   => $stN * 12,
        stData    => $objO - $stD,
        objTable  => $objN * $objRow,
        objData   => $cloO - $objD,
        closures  => $cloN * 24,
        ctxTable  => $ctxN * 16,
        ctxData   => $repO - $ctxD,
        repos     => $repN * 16,
        strOffsets => $strOff,
        strings   => $len - $shO - $strOff;
    my $sum = @rows.map(*.value).sum;
    die "$jar: segments sum to $sum, header 72, len $len: format drift"
        unless $sum + 72 == $len;
    say "version=$v len=$len";
    for @rows -> $r {
        printf "%-10s %10d  %5.1f %%\n", $r.key, $r.value, 100 * $r.value / $len;
    }
    say "counts: stables=$stN objects=$objN closures=$cloN contexts=$ctxN repos=$repN strings=$shN deps=$depN";
}
