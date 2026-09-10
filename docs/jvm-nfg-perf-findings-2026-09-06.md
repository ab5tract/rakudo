# NFG perf investigation + calling-convention findings (2026-09-06)

Handoff note for a fresh session. Written after a long session that (1) put
NFG on the JVM through the Truffle regex engine and (2) then chased whether any
of it — or TruffleString generally — was worth it for *speed*. Short answer: the
correctness work is done and committed; the *speed* lever is elsewhere, and it
is the migration already planned in **`docs/jvm-truffle-migration.md`**. This
doc records the measurements so nobody re-derives them.

## TL;DR

1. **NFG / TruffleString is a performance dead-end.** It is 0.0% of a CORE
   compile and 1.1% of a deliberately NFG-heavy Raku string workload. The
   NFGString caching and the engine-only regex path are correct and committed
   but do **not** change build/run speed. Do not optimize NFG further for perf.
2. **`TruffleString in the runtime is NOT slower` — my earlier assertion was
   wrong.** A fair bench (per-call lookup on both sides) has interpreted,
   cached TruffleString `NFGString` **on par** with the truffle-free `NFG`
   (~15 ns/op, both dominated by the by-string hash lookup). It is 3–5× faster
   only if the *string representation itself* carried the value (greenfield) —
   moot while NFG is 1%.
3. **The dominant cost everywhere is the calling convention.**
   `CallFrame.<init>` is ~13% of on-CPU samples in *every* workload profiled.
   Measured per-call overhead: ~**47 ns/call** (frame + lexical-array
   allocation, `ArgsExpectation`, dispatch, arity). JVM JIT ceiling for the
   same loop is ~0.04–2 ns → **~25–50× headroom**.
4. **That validates the jast2bc→Truffle migration** (`docs/jvm-truffle-migration.md`).
   PE inlines calls (no frame/lexical allocation) and specializes ops (unbox,
   no dispatch). That is the lever for real speedups; NFG was never it.

## What this session shipped (nqp branch `truffle-grammar-engine`)

| commit | what |
|---|---|
| `f8c0e1570` | NFG: cache grapheme segmentation per source (fix O(n²) parse hang) |
| `dbcddc2e2` | grapheme-index the classic regex codegen + optimizer keeps engine-callback lexicals |
| `8ba832355` | nibbler `getlexdyn` encodes to the engine (last of 38 bails) |
| `1f7b81476` | `NQP_RX_STRICT` made the classic fallback a hard error |
| `cb7881cce` | **deleted** the classic per-node regex codegen (~1660 lines); engine is the only regex path |
| `b70d8ed4b` | NFGString caching (intern per source + per-instance chars/atoms) |

Full context in memory `nfg-grammar-engine-bail-elimination` and
`docs/jvm-nfg-representation.md`. `NQP_RX_STRICT=1 make` builds all of Rakudo
(frontend + BOOTSTRAP v6c/d/e + CORE.c/d/e) with zero rules failing to encode.

## Measurements (all reproducible)

Environment: Oracle GraalVM 25.2.4 (`/usr/lib/jvm/java-25-graalvm`), the
truffle module-path + nqp jars from `nqp/build/jvm/share/{runtime,truffle}`.

### NFG's share of real workloads — JFR, not micro-benchmarks

Attach JFR to a running compile and read execution samples:

```
P=$(jcmd -l | grep -i <workload> | awk '{print $1}')
jcmd $P JFR.start name=p settings=profile
# ...let it run...
jcmd $P JFR.dump name=p filename=out.jfr
jfr print --events jdk.ExecutionSample --stack-depth 1 out.jfr \
  | grep -E '^\s+[a-zA-Z].*\(' | sed -E 's/\(.*//; s/^\s+//' \
  | sort | uniq -c | sort -rn | head
```

- **CORE.c setting compile**: NFG/atoms/NFGString/TruffleString = **0.0%**.
  Top frames: `CallFrame.<init>` (~13%), compiled `qb_*` code (~18%),
  `invokeDirect`/`ArgsExpectation` (calling convention), dispatch
  (`guardsMatch`/`testGuard`/`resolveAttribute`/`wval`) (~5%).
- **NFG-heavy Raku string workload** (`flip`/`substr`/`comb`/`ords` on
  combining+astral text): NFG = **1.1%**. Top frame again `CallFrame.<init>`
  (~13%). combining-vs-ascii twin: 1.93s vs 1.81s (~7%).

Lesson (paid for the hard way this session): **profile the real workload before
optimizing.** A micro-benchmark ratio is meaningless without the operation's
share of the workload — a "5–30× faster atoms()" number was both the wrong
baseline (the engine already cached) and 0% of the workload.

### Would routing the runtime through TruffleString be slower? — No, on par

`NfgRuntimeBench2` (below): the runtime holds raw Java Strings, so an
`Ops.chars(s)` call must look the value up by string every time —
`NFGString.of(s)` hashes `s` exactly as `NFG.graphemeClusters(s)` does. Fair
result, ns/op on a reused pool (both cached):

| op | TS-held | TS-lookup (fair) | NFG |
|---|---|---|---|
| chars | 3–4 | ~16–18 | ~15 |
| ords  | 3–6 | ~16–26 | ~15 |

TS-lookup ≈ NFG (both hash-lookup-dominated; TS marginally slower from
indirection). TS-held (3–6 ns) is the ceiling **only if the string type itself
carried the NFGString** — a representation change, not a routing change.

### The real bottleneck — calling convention, ~47 ns/call

```
# callbench.nqp: trivial call in a tight loop
sub f($x) { $x + 1 }
my $N := 50000000; my $w := 0; while $w < 5000000 { f($w); $w := $w + 1 }
my $t0 := nqp::time(); my $acc := 0; my $i := 0;
while $i < $N { $acc := f($acc); $i := $i + 1 }
nqp::say("total_ns=" ~ (nqp::time() - $t0));
# loopbench.nqp: same loop, body `$acc := $acc + 1` (no call)
```

Run with `nqp/nqp-j` (in 2026-09-06 terms, `NQP_CODE_RUN=1 nqp/nqp-j`;
that variable must not be set at all since the encoder became the only
road, and the class road it selected between is gone as of 2026-09-10):

- trivial nqp call: **78 ns**
- loop-only (boxed-int arith through dispatch): **32 ns/iter**
- **pure call overhead: ~47 ns/call**
- plain-Java JIT ceiling (same loop): ~0.04–2 ns → **~25–50× headroom**

`CallFrame.<init>` (nqp-runtime) allocates the frame **plus** lexical arrays
(`arrayOfNulls<SixModelObject>(numoLex)`) and resolves `outer` (sometimes
walking the caller chain). All of it is what PE inlining removes.

## The lever: the Truffle runtime call stack (already planned)

**Read `docs/jvm-truffle-migration.md` first — it is the plan of record.** The
regex engine (`RxVmNode`/`RxLanguage`) is the existence proof; the general-code
analog is **already scaffolded**:

- `NqpLanguage` — the Truffle language general NQP/Raku code runs in (target of
  the jast2bc→Truffle migration). Today it only accepts `code-test:` skeleton
  input via `NqpCheck`; real code joins when "Phase 2 puts real code on this
  road."
- `NqpRootNode` — a **Truffle Bytecode DSL** root node (generates
  `NqpRootNodeGen`, cached/uncached tiers, OSR, serializable bytecode). Ops in
  `NqpOps`.
- `NqpCodeEngine` / `NqpProgramBuilder` — the general-code analog of
  `TruffleGrammarEngine`; builder walks a decoded `NqpWire` program into DSL
  calls.
- "Dispatch on Truffle" started 2026-09-04 (doc §"Dispatch on Truffle"): folded
  replay + direct engine entry landed; measured on a 300k method-call loop.

The migration doc's "Why" already argues exactly what these measurements show
(PE inlines across dispatch; the 64K walls disappear; control flow simplifies)
and states the honest costs (warmup/PE-compile regression, per-code-object
memory, a second serialization story). Every phase gate there is a measurement.

### Measurement the migration still wants (the deferred prototype)

To put a number on "what a Truffle call stack buys" *before* committing to more
of the migration, a fresh session could build a **minimal PE prototype** and
compare to the 78 ns baseline:

- A hand-written `RootNode` for the `callbench` loop: a specialized `+` node
  (boxed and, via `@Specialization`, unboxed `long`) and a `DirectCallNode` to
  a trivial callee `RootNode`, run through the same `RxLanguage`-style context
  so PE actually fires (a RootNode outside a polyglot context is never queued
  for compilation — see `RxLanguage`'s comment).
- Report ns/call warm. Expectation from the ceiling: single-digit ns, i.e. the
  ~47 ns call overhead largely gone. If it lands there, it quantifies the
  addressable ~13%+ of every workload.
- This is throwaway measurement code, distinct from `NqpRootNode` (which is the
  real Bytecode-DSL road). Its only job is the number.

Then the real work is the migration's own phases: get real code onto
`NqpLanguage` (Phase 2), gate on CORE-compile wall time and t/ + spectest, and
watch the honest costs (warmup, memory).

## Reproduction: benchmark harnesses

The harnesses are saved under **`docs/bench/nfg/`**. Compile/run pattern for the
Java NFG benches (run from the rakudo root):

```
JH=/usr/lib/jvm/java-25-graalvm
RT=nqp/build/jvm/share/runtime; TR=nqp/build/jvm/share/truffle
CP="$RT/nqp-runtime.jar:$RT/nqp-truffle.jar:$RT/kotlin-stdlib-2.4.10.jar:$TR/truffle-api-25.2.4.jar"
$JH/bin/javac -cp "$CP" NfgRuntimeBench2.java
$JH/bin/java --module-path "$TR" --add-modules org.graalvm.truffle,org.graalvm.truffle.runtime \
  --enable-native-access=org.graalvm.truffle --sun-misc-unsafe-memory-access=allow -cp "$CP:." NfgRuntimeBench2
```

- `NfgRuntimeBench2.java` — fair runtime-op comparison (chars/ords: TS-held /
  TS-lookup / NFG). The `-lookup` columns are the honest ones; `-held` is the
  representation-change ceiling.
- `NfgBench2.java` / `NfgBench3.java` — build cost (on par) and cached hot
  access.
- `callbench.nqp` / `loopbench.nqp` — per-call overhead (above).
- `CallCeiling.java` — plain-Java JIT ceiling for the same loop.

Key API: `NFG.graphemeClusters(s)` / `NFG.baseCodepoints(s)` (truffle-free,
`nqp-runtime`); `NFGString.of(s)` / `.chars()` / `.atoms()` / `.substr()`
(TruffleString, `nqp-truffle`). `NFGString` uses `getUncached()` nodes =
interpreted TruffleString, so the benches measure the interpreted (not PE) case.

## Bottom line for the next session

- Leave NFG alone for perf. It is correct and 1% of the workload.
- The speedup lever is the calling convention → the jast2bc→Truffle migration in
  `docs/jvm-truffle-migration.md`. These measurements are the evidence it is the
  right priority; continue from that doc's phases, optionally starting with the
  minimal PE prototype above to size the win.
