public class CallCeiling {
    static long f(long x){ return x + 1; }
    public static void main(String[] a){
        long N=50_000_000L, acc=0;
        for(long w=0;w<200_000_000L;w++) acc=f(acc);   // warm/JIT
        long t0=System.nanoTime();
        acc=0; for(long i=0;i<N;i++) acc=f(acc);
        double call=(double)(System.nanoTime()-t0)/N;
        t0=System.nanoTime();
        acc=0; for(long i=0;i<N;i++) acc=acc+1;
        double loop=(double)(System.nanoTime()-t0)/N;
        System.out.printf("Java (JIT ceiling): loop=%.3f ns/iter  with-call=%.3f ns/iter  (acc=%d)%n", loop, call, acc);
    }
}
