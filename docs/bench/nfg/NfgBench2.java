import org.raku.nqp.runtime.NFG;
import org.raku.nqp.truffle.NFGString;

/** Cleaner: cold build over a big fresh pool (single touch each -> NFG's
 *  per-source cache always misses, so both sides pay the real segment cost),
 *  plus warm access on prebuilt forms. Interpreted (uncached) TruffleString. */
public class NfgBench2 {
    static String mk(String kind, int idx, int len, java.util.Random r) {
        StringBuilder sb = new StringBuilder();
        sb.append(idx).append(':');
        for (int j = 0; j < len; j++) switch (kind) {
            case "ascii":     sb.append((char)('a' + r.nextInt(26))); break;
            case "bmp":       sb.appendCodePoint(0x3040 + r.nextInt(96)); break;
            case "astral":    sb.appendCodePoint(0x1F600 + r.nextInt(48)); break;
            case "combining": sb.append((char)('a'+r.nextInt(26))).append('́'); break;
        }
        return sb.toString();
    }
    static String[] pool(String kind, int n, int len, long seed) {
        java.util.Random r = new java.util.Random(seed);
        String[] a = new String[n];
        for (int i = 0; i < n; i++) a[i] = mk(kind, i, len, r);
        return a;
    }
    static long sink;

    public static void main(String[] a) {
        String[] kinds = {"ascii","bmp","astral","combining"};
        int len = 64, N = 20000;
        System.out.println("interpreted TruffleString (NFGString) vs truffle-free NFG   [ns/op, "+N+" distinct strings, len~"+len+" cp]");
        System.out.printf("%-10s %-6s | %14s %11s %6s | %14s %11s %6s%n",
            "kind","graphs","NFGStr build","NFG build","x","NFGStr chars","NFG chars","x");
        for (String kind : kinds) {
            // Warm the JIT on a SEPARATE pool so the timed strings stay cache-cold.
            String[] warm = pool(kind, 4000, len, 1);
            for (int w=0; w<4; w++) for (String s: warm){ sink+=NFGString.fromJavaString(s).chars(); sink+=NFG.baseCodepoints(s).length; }

            // Cold build: fresh pool, single touch each.
            String[] ts = pool(kind, N, len, 100);
            long t0=System.nanoTime();
            for (String s: ts) sink += NFGString.fromJavaString(s).chars();
            double tsB=(double)(System.nanoTime()-t0)/N;
            String[] ng = pool(kind, N, len, 200);
            t0=System.nanoTime();
            for (String s: ng) sink += NFG.baseCodepoints(s).length;
            double nfB=(double)(System.nanoTime()-t0)/N;

            int graphs = NFGString.fromJavaString(ts[0]).chars();

            // Warm access on prebuilt forms.
            NFGString[] pb = new NFGString[2000];
            String[][] gc = new String[2000][];
            for (int i=0;i<2000;i++){ pb[i]=NFGString.fromJavaString(warm[i]); gc[i]=NFG.graphemeClusters(warm[i]); }
            t0=System.nanoTime(); long n=0;
            for(int it=0;it<300;it++) for(NFGString x:pb){ sink+=x.chars(); n++; }
            double tsC=(double)(System.nanoTime()-t0)/n;
            t0=System.nanoTime(); n=0;
            for(int it=0;it<300;it++) for(String[] x:gc){ sink+=x.length; n++; }
            double nfC=(double)(System.nanoTime()-t0)/n;

            System.out.printf("%-10s %-6d | %14.1f %11.1f %6.1f | %14.1f %11.1f %6.2f%n",
                kind, graphs, tsB, nfB, tsB/nfB, tsC, nfC, tsC/nfC);
        }
        System.out.println("(sink="+sink+")");
    }
}
