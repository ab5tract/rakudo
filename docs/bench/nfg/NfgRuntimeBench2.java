import org.raku.nqp.runtime.NFG;
import org.raku.nqp.truffle.NFGString;

/** FAIR runtime-op comparison. The runtime holds raw Java Strings, so every
 *  Ops.chars(s)/ords(s)/... call must look the value up by string -- NFGString.of(s)
 *  hashes s exactly as NFG.graphemeClusters(s) does. So the honest question is
 *  of(s).op() vs NFG.op(s), BOTH paying the per-call lookup. TS-held (ts.op(),
 *  no lookup) is shown only to show the ceiling IF the string representation
 *  itself carried the NFGString (a greenfield change, not today's runtime). */
public class NfgRuntimeBench2 {
    static long sink;
    static String mk(String kind,int idx,int len,java.util.Random r){
        StringBuilder sb=new StringBuilder(); sb.append(idx).append(':');
        for(int j=0;j<len;j++) switch(kind){
            case "ascii": sb.append((char)('a'+r.nextInt(26))); break;
            case "combining": sb.append((char)('a'+r.nextInt(26))).append('́'); break;
            case "astral": sb.appendCodePoint(0x1F600+r.nextInt(48)); break;
        } return sb.toString();
    }
    public static void main(String[] a){
        String[] kinds={"ascii","combining","astral"};
        int HOT=1000,len=48; long IT=3000;
        System.out.println("runtime ops, FAIR (per-call lookup on both) [ns/op, reused pool]");
        System.out.printf("%-10s | %-26s | %-26s%n","kind","chars: TSheld/TSlookup/NFG","ords: TSheld/TSlookup/NFG");
        for(String kind:kinds){
            java.util.Random r=new java.util.Random(7);
            String[] src=new String[HOT]; NFGString[] ts=new NFGString[HOT];
            for(int i=0;i<HOT;i++){ src[i]=mk(kind,i,len,r); ts[i]=NFGString.of(src[i]); }
            for(int w=0;w<400;w++) for(int i=0;i<HOT;i++){ sink+=ts[i].chars(); sink+=NFGString.of(src[i]).chars(); sink+=NFG.graphemeClusters(src[i]).length; sink+=NFG.baseCodepoints(src[i]).length; }
            long n,t0;
            t0=System.nanoTime();n=0; for(long it=0;it<IT;it++)for(int i=0;i<HOT;i++){sink+=ts[i].chars();n++;} double cHeld=(double)(System.nanoTime()-t0)/n;
            t0=System.nanoTime();n=0; for(long it=0;it<IT;it++)for(int i=0;i<HOT;i++){sink+=NFGString.of(src[i]).chars();n++;} double cLook=(double)(System.nanoTime()-t0)/n;
            t0=System.nanoTime();n=0; for(long it=0;it<IT;it++)for(int i=0;i<HOT;i++){sink+=NFG.graphemeClusters(src[i]).length;n++;} double cNfg=(double)(System.nanoTime()-t0)/n;
            t0=System.nanoTime();n=0; for(long it=0;it<IT;it++)for(int i=0;i<HOT;i++){sink+=ts[i].atoms().length;n++;} double oHeld=(double)(System.nanoTime()-t0)/n;
            t0=System.nanoTime();n=0; for(long it=0;it<IT;it++)for(int i=0;i<HOT;i++){sink+=NFGString.of(src[i]).atoms().length;n++;} double oLook=(double)(System.nanoTime()-t0)/n;
            t0=System.nanoTime();n=0; for(long it=0;it<IT;it++)for(int i=0;i<HOT;i++){sink+=NFG.baseCodepoints(src[i]).length;n++;} double oNfg=(double)(System.nanoTime()-t0)/n;
            System.out.printf("%-10s | %6.1f /%6.1f /%6.1f | %6.1f /%6.1f /%6.1f%n", kind, cHeld,cLook,cNfg, oHeld,oLook,oNfg);
        }
        System.out.println("(sink="+sink+")");
    }
}
