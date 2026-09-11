import org.raku.nqp.runtime.NFG;
import org.raku.nqp.truffle.NFGString;

/** Stable cached-access measurement: a small hot working set hammered many
 *  times, so the per-op cost dominates over memory/GC noise. Shows the effect
 *  of NFGString's new per-instance chars()/atoms() caches. */
public class NfgBench3 {
    static long sink;
    static String mk(String kind, int idx, int len, java.util.Random r) {
        StringBuilder sb = new StringBuilder(); sb.append(idx).append(':');
        for (int j=0;j<len;j++) switch(kind){
            case "ascii": sb.append((char)('a'+r.nextInt(26))); break;
            case "astral": sb.appendCodePoint(0x1F600+r.nextInt(48)); break;
            case "combining": sb.append((char)('a'+r.nextInt(26))).append('́'); break;
        }
        return sb.toString();
    }
    public static void main(String[] a){
        String[] kinds={"ascii","astral","combining"};
        int HOT=128, len=64;
        long ITERS=3000;
        System.out.println("cached access, hot set of "+HOT+" strings, "+ITERS+" iters  [ns/op]");
        System.out.printf("%-10s | %10s %10s %6s | %10s %10s %6s%n",
            "kind","TS chars","NFG chars","x","TS atoms","NFG baseCP","x");
        for (String kind: kinds){
            java.util.Random r=new java.util.Random(7);
            NFGString[] ts=new NFGString[HOT]; String[] src=new String[HOT];
            String[][] gc=new String[HOT][]; int[][] bc=new int[HOT][];
            for(int i=0;i<HOT;i++){ src[i]=mk(kind,i,len,r); ts[i]=NFGString.of(src[i]);
                gc[i]=NFG.graphemeClusters(src[i]); bc[i]=NFG.baseCodepoints(src[i]); }
            // warm (also primes NFGString instance caches + NFG source cache)
            for(int w=0;w<1000;w++) for(int i=0;i<HOT;i++){ sink+=ts[i].chars(); sink+=ts[i].atoms().length; sink+=gc[i].length; sink+=NFG.baseCodepoints(src[i]).length; }

            long t0=System.nanoTime(); long n=0;
            for(long it=0;it<ITERS;it++) for(int i=0;i<HOT;i++){ sink+=ts[i].chars(); n++; }
            double tsC=(double)(System.nanoTime()-t0)/n;
            t0=System.nanoTime(); n=0;
            for(long it=0;it<ITERS;it++) for(int i=0;i<HOT;i++){ sink+=gc[i].length; n++; }
            double nfC=(double)(System.nanoTime()-t0)/n;
            t0=System.nanoTime(); n=0;
            for(long it=0;it<ITERS;it++) for(int i=0;i<HOT;i++){ sink+=ts[i].atoms().length; n++; }
            double tsA=(double)(System.nanoTime()-t0)/n;
            t0=System.nanoTime(); n=0;                              // NFG cached baseCodepoints (source-cache hit)
            for(long it=0;it<ITERS;it++) for(int i=0;i<HOT;i++){ sink+=NFG.baseCodepoints(src[i]).length; n++; }
            double nfA=(double)(System.nanoTime()-t0)/n;

            System.out.printf("%-10s | %10.2f %10.2f %6.2f | %10.2f %10.2f %6.2f%n",
                kind, tsC, nfC, tsC/nfC, tsA, nfA, tsA/nfA);
        }
        System.out.println("(sink="+sink+")");
    }
}
