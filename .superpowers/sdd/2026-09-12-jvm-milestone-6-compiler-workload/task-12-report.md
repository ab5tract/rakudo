# Task 12 — the Native Image spike on nqp alone (and, as it turned out, on Rakudo)

Worktree: `/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records`
Trees at start: rakudo `c3d7d5800d`, nqp `41c294b02`. No source file in either
tree was touched; everything below is configuration, and every artifact lives
under `$CLAUDE_JOB_DIR/tmp` (`/home/longwalker/.claude/jobs/804818e2/tmp`).

Toolchain: `native-image 25.0.4`, Oracle GraalVM 25.2.4+7.1, Substrate VM
serial GC, 16 cores / ~32 GB, otherwise idle.

---

## 0. Headline

**The image builds, it runs nqp, and — the thing nobody had tested — it runs
Rakudo, compiling Raku source, from `rakudo.jar` as pure data.** The unit
artifact road delivered exactly what it promised: an image of the *nqp*
runtime, built with no knowledge of Rakudo's compiler whatsoever, loads
`rakudo.jar` at run time and executes it.

**And it is slower than the JVM on every workload measured, by a wide margin
in wall clock and by a wide margin the other way in CPU.** The JVM wins
because HotSpot throws five to six cores of JIT at the interpreter; the image
runs one thread's worth of AOT code and cannot make that back.

---

## 1. The JVM baselines (measured first, as instructed)

`nqp-j -e 'say(1)'`, three consecutive runs, warm page cache:

| run | wall | user CPU | CPU load |
|-----|------|----------|----------|
| 1 | 1.935 s | 9.92 s | 544 % |
| 2 | 1.998 s | 9.80 s | 523 % |
| 3 | 1.853 s | 9.74 s | 560 % |

**JVM baseline: ~1.93 s wall, ~9.8 s CPU.**

For the Rakudo comparison, `./rakudo-j -e 'say(1)'`: **3.663 s wall, 22.77 s
CPU, 646 % load.**

Note the shape: over five cores busy for under two seconds. That is HotSpot
compiling the interpreter's own bytecode, which is milestone finding 3 showing
up on the clock. It also means "startup" here is not JVM boot — JVM boot is
~0.1 s of it. The rest is real work: artifact load, LZ4, meta decode,
deserialize, and running the setting's load blocks through an interpreter that
is being compiled underneath it.

---

## 2. Which kind of image was built (Question 1)

**Built: an image WITH the optimising Truffle runtime** — `--macro:truffle-svm`,
which pulls `truffle-runtime-svm.jar` in and registers `TruffleBaseFeature`,
`TruffleFeature`, `EnterpriseTruffleFeature` and
`EnterpriseTruffleCompilerFeature`. The build output names all seven features.
The image is 67.6 MiB for nqp alone (32.7 MiB code, 30.7 MiB heap) and
77.5 MiB with Rakudo's runtime added, against 28.9 MiB for a build where the
Truffle features do not activate — the difference is the Graal compiler
compiled into the binary.

**But it behaves as an interpreter-only image in practice, and that is a
finding, not a configuration choice.** With `engine.TraceCompilation` on, every
single guest compilation fails:

```
[engine] opt failed engine=1 id=349 jdesc[84] |Tier 1|Time 3( 3+0 )ms|Reason:
  SourceStackTraceBailoutException: Object of type
  Lcom/oracle/truffle/api/impl/FrameWithoutBoxing; should not be materialized
  (must not pass virtual object into an invoke that cannot be inlined)
```

Every root — `jdesc`, `jtype`, `classlib_record`, `method_table`,
`find_method`, `set_core_op_inlinability`, anonymous blocks — bails at Tier 1
with the same reason. `CompilationStatistics` on the CORE.c run confirms it:
compilations attempted, **successes 0**.

The cause is identified precisely, and it is the blocklist violation the build
told me about before I suppressed the check:

```
=== Found 1 compilation blocklist violations ===
Blocklisted method
   java.util.WeakHashMap.get(Object)
trace:
  at org.raku.nqp.truffle.NFGString$Companion.atomsOf(NFGString.kt:155)
  at org.raku.nqp.truffle.RxMatchRootNode.execute(RxMatchRootNode.kt:28)
```

`NFGString.atomsOf` consults a `WeakHashMap` from inside a partial-evaluation
root. On HotSpot Graal tolerates this (it materialises the frame and carries
on); Native Image's Truffle feature refuses it at build time, and when the
refusal is overridden with `-H:-TruffleCheckBlockListMethods` the compiler
bails at run time instead, on *every* root, because the materialised frame
poisons the whole compilation.

**So: one `@TruffleBoundary` (or a PE-safe grapheme cache) on one method
separates "an image with a working optimising runtime" from what was measured
here.** That is the single most actionable finding in this report and it is a
one-line source change — which this task was forbidden to make.

**What the other kind would look like.** A deliberately interpreter-only image
(no `--macro:truffle-svm`) would be ~29 MiB instead of ~68 MiB, would start
marginally faster (no Graal in the heap to relocate), and would have exactly
the performance the numbers below show, minus the wasted compiler thread. In
other words the measurements here ARE the interpreter-only shape; the
optimising runtime is present but contributes nothing except a thread that
fails 3 compilations and gives up.

---

## 3. What the build demanded, in order

Each of these was a failed build or a failed run. This list is the real
deliverable — it is the measure of how far Rakudo is from an image.

1. **`net.jpountz.lz4.LZ4JavaSafe*` reflective registration.** First run died
   in `UnitFormat.<clinit>` → `LZ4Factory.safeInstance()` →
   `ClassNotFoundException: LZ4JavaSafeCompressor`. lz4-java loads its
   implementation classes by name. Four classes, `INSTANCE` field each.

2. **Do not register bare primitive types for reflection.** The tracing agent
   emits `{"type":"double"}` and `{"type":"long"}` entries (NQP looks up
   `Double.TYPE` etc.). Feeding those to the builder makes it resolve
   `CEntryPointLiteral.create`, which is platform-restricted, and the build dies
   with `UnsupportedPlatformException`. This cost the most time of anything in
   the spike because the error names no class; I bisected it with a Raku driver
   (`probe-config.raku`) that built the image once per metadata entry.

3. **`--initialize-at-build-time` for four Truffle/polyglot symbol holders:**
   `org.graalvm.home.impl.VmLocatorSymbol`,
   `com.oracle.truffle.polyglot.InternalResourceCacheSymbol`,
   `org.graalvm.home.impl.DefaultHomeFinder`,
   `com.oracle.truffle.polyglot.InternalResourceRoots`. Their static
   initialisers call `CEntryPointLiteral.create`, which is legal only at build
   time. Without this, *any* non-empty reflection metadata fails the build.

4. **Truffle jars must be on the image CLASS path, not the module path.** With
   them on `--module-path` the build succeeds but no Truffle feature is
   registered at all, and the image dies at run time with `No language and
   polyglot implementation was found on the module-path`. Making everything an
   automatic module (`--add-modules ALL-MODULE-PATH`, `--module
   nqp.runtime/...UnitMain`) did not help. On the class path, all seven
   Truffle features load. This is the opposite of the JVM runner's arrangement
   and is worth writing down.

5. **`--initialize-at-build-time` for the language's own classes**, found by an
   automatic iteration driver (`iterate-initbt.raku`, one class per round):
   `NqpLanguageProvider`, `ProgramGen$InteropLibraryExports`,
   `MatcherGen$InteropLibraryExports` and their `$Cached` / `$Uncached` inner
   classes. Blanket `--initialize-at-build-time=org.raku.nqp.truffle` is what a
   language would normally ship, but here it makes the builder crash with an
   internal `NullPointerException` in `RuntimeCompiledMethodSupport`
   (`hostedConstant is null`) on `NFGString$Companion.fromJavaString` — a
   build-time-initialised companion object reachable from a PE root. The
   narrow six-class list avoids it.

6. **`-H:-TruffleCheckBlockListMethods`** to get past the `WeakHashMap` finding
   in §2. This is a suppression, not a fix.

7. **`-Djava.class.path=<share/lib>` at run time.** `UnitLoader.load` resolves
   the special name `ModuleLoader.class` by walking
   `System.getProperty("java.class.path")`, which is empty in an image.
   Symptom: `loadbytecode: ModuleLoader.class is not a unit artifact`. Setting
   the property on the image command line fixes it with no source change.

8. **(Rakudo only) `rakudo-runtime.jar` on the image class path.** Without it:
   `classlib op Lorg/raku/rakudo/RakOps;.p6init(...): ClassNotFoundException:
   org.raku.rakudo.RakOps`. `rakudo.jar` really is data — `unit.meta`,
   `unit.programs`, `unit.serialized.lz4`, nothing else — but its classlib ops
   name Rakudo's Java runtime by descriptor.

9. **(Rakudo only) the entire op surface registered reflectively.** A trace of
   `say(1)` is not enough: the first CORE.c attempt died on
   `MissingReflectionRegistrationError: Ops.exception(ThreadContext)`. Unit
   artifacts name classlib ops as strings, so the resolution is reflective and
   open-world. I registered every class in `nqp-runtime.jar`,
   `nqp-truffle.jar` and `rakudo-runtime.jar` — 734 types, all members.

10. **(Rakudo only) the three JDK classes the classlib road can name.** The
    second CORE.c attempt died on `classlib op Ljava/lang/Math;.abs(J)J:
    ClassNotFoundException`. The set is closed and tiny — grepping both trees
    for quoted JVM descriptors yields exactly eight classes, of which
    `java.lang.Math`, `java.lang.String` and `java.lang.Object` are the JDK
    ones (the rest are `Ops`, `NativeCallOps`, `IOOps`, `ThreadContext`,
    `SixModelObject`, `RakOps`). A build step could emit this list
    mechanically.

Notably **absent** from the list: nothing demanded a source change to make the
image *build or run*. Item 6 is the one place where a source change would
change the *result* rather than the feasibility.

---

## 3a. The four images — what each one is, and which ones work

All four survive in `$CLAUDE_JOB_DIR/tmp` as the controller asked. Two work,
two are dead ends kept as evidence.

| binary | built by | on disk | build wall | Truffle features | works? |
|---|---|---|---|---|---|
| `nqp-image-opt` | `iterate-initbt.raku` (drives the `build-image-cp.sh` flag set) | 67.6 MiB (64.0 MiB file) | **1 m 30 s** | all 7 | **YES** — runs nqp |
| `rakudo-image` | `build-image-rakudo.sh` | 77.5 MiB (73.3 MiB file) | **1 m 27 s** | all 7 | **YES** — runs nqp *and* Rakudo |
| `nqp-image` | `build-image-mod.sh` (and earlier `build-image.sh`) | 28.9 MiB (27.4 MiB file) | 42 s | **none** | no — dies with `No language and polyglot implementation was found on the module-path` |
| `nqp-image-empty` | `bi-empty.sh` (a `build-image.sh` variant with empty metadata) | 19.7 MiB (18.6 MiB file) | 35 s | none | no — control only; dies in `LZ4Factory` |

Reading the table: the 19.7 → 28.9 → 67.6 MiB progression is the whole story
of the spike. The 19.7 MiB build is what you get with no metadata at all; the
28.9 MiB one has the metadata but the Truffle jars on the **module** path, so
the builder never registers a Truffle feature and the binary has no polyglot
engine in it; the 67.6 MiB one has them on the **class** path, and the 39 MiB
difference is the Graal compiler compiled into the binary. `rakudo-image` adds
another 10 MiB for `rakudo-runtime.jar` and the 734-type reflection surface.

The other scripts in the job dir were steps, not products: `build-image.sh` is
the module-path recipe (dead end), `build-image-cp.sh` the class-path recipe
that `iterate-initbt.raku` finished, `build-image-diag.sh` a `--parallelism=1`
copy used to get an unmangled stack trace, and `probe-config.raku` /
`bisect-config.raku` the drivers that isolated demand 2 below by rebuilding the
image once per metadata entry.

---

## 3b. The headline: an image loads Rakudo as data

This had never been tested and it is the most important structural result of
the evening.

`rakudo-image` is an image of the **nqp** runtime. Rakudo's *compiler* was not
present at image-build time in any form — no Raku sources, no `rakudo.jar` on
the image class path, nothing. The only Rakudo thing in the image is
`rakudo-runtime.jar`, which is Rakudo's *Java* runtime (`RakOps`, `Binder`,
`RakudoContainerSpec` — the ops the guest calls), not its compiler.

At run time it is handed `rakudo.jar`, which contains exactly three entries:

```
unit.meta    unit.programs    unit.serialized.lz4
```

No `.class` files at all. The image reads it as data, deserialises the context,
finds the entry block, and runs Rakudo's `src/main.nqp`. Verified end to end:

- `-e 'say(1)'` → `1`
- `-e 'say(1); my @a = 1,2,3; say @a.map(* * 2).join(",")'` → `1` / `2,4,6`
- the CORE.c compile, which got through startup, the setting, the compiler
  frontend and into the parse stage before being killed on time grounds.

**What it proves:** the milestone-4 unit-artifact road does what it was built
to do. Units are data, so the host can be frozen ahead of time and the guest
supplied afterwards. A *single* nqp image can, in principle, run any NQP-based
compiler whose Java runtime it carries. The remaining coupling to Rakudo is
`rakudo-runtime.jar` and the reflective op surface (demands 8–10), and both are
packaging, not language.

**What it does not prove:** nothing here says the image is a good way to *run*
Rakudo. See §5 and §6.

---

## 4. The recipe

Two scripts, both under `$CLAUDE_JOB_DIR/tmp`:
`build-image-cp.sh` / `iterate-initbt.raku` (nqp), `build-image-rakudo.sh`
(Rakudo). The Rakudo one, which is a superset:

```sh
CP="$R/nqp-runtime.jar:$R/nqp-truffle.jar:$R/kotlin-stdlib-2.4.10.jar:\
$R/fastutil-8.5.19.jar:$R/annotations-13.0.jar:$R/lz4-java-1.8.0.jar:$R/jline-4.3.1.jar"
CP="$CP:$T/truffle-api-25.2.4.jar:$T/truffle-runtime-25.2.4.jar:\
$T/truffle-compiler-25.2.4.jar:$T/polyglot-25.2.4.jar:$T/collections-25.2.4.jar:\
$T/nativeimage-25.2.4.jar:$T/word-25.2.4.jar:$T/jniutils-25.2.4.jar"
CP="$CP:$W/rakudo-runtime.jar"

native-image \
  -J-Xmx20g \
  --macro:truffle-svm \
  -cp "$CP" \
  --no-fallback \
  -H:-TruffleCheckBlockListMethods \
  --initialize-at-build-time=org.graalvm.home.impl.VmLocatorSymbol,\
com.oracle.truffle.polyglot.InternalResourceCacheSymbol,\
org.graalvm.home.impl.DefaultHomeFinder,\
com.oracle.truffle.polyglot.InternalResourceRoots,\
org.raku.nqp.truffle.NqpLanguageProvider,\
org.raku.nqp.truffle.ProgramGen\$InteropLibraryExports,\
org.raku.nqp.truffle.MatcherGen\$InteropLibraryExports,\
org.raku.nqp.truffle.ProgramGen\$InteropLibraryExports\$Cached,\
org.raku.nqp.truffle.MatcherGen\$InteropLibraryExports\$Uncached,\
org.raku.nqp.truffle.ProgramGen\$InteropLibraryExports\$Uncached,\
org.raku.nqp.truffle.MatcherGen\$InteropLibraryExports\$Cached \
  -H:ConfigurationFileDirectories="$OUT/config-rakudo2" \
  -o "$OUT/rakudo-image" \
  org.raku.nqp.runtime.unit.UnitMain
```

The metadata directory is produced by `mkrakuconfig2.raku`, which merges two
tracing-agent runs (`-agentlib:native-image-agent=config-output-dir=...`
around the ordinary JVM runner) with a mechanical registration of every class
in the three runtime jars, drops primitive-type entries, and adds
`java.lang.{Math,String,Object}`.

Running it:

```sh
env RAKUDO_HOME=$W/gen/build_rakudo_home RAKUDO_RAKUAST=1 \
  $OUT/rakudo-image -Xmx14g \
    -Djava.class.path=blib:$W/nqp/build/jvm/share/lib \
    -Dpolyglot.engine.Mode=latency \
    -Dpolyglot.engine.FirstTierCompilationThreshold=1600 \
    -Dpolyglot.engine.CompilerThreads=1 \
    rakudo.jar <rakudo args>
```

Build wall times: nqp image **1 m 30 s**, Rakudo image **1 m 26 s**. The whole
successful build, once the flags are known, is under two minutes — which is
worth noting, because it means an image is not an expensive thing to
regenerate when the runtime changes. (It is still invalidated by every runtime
change, which is why no binary is committed.)

**How the polyglot options are passed (asked explicitly):** plain `-D` system
properties on the image's own command line, read when the engine is
constructed, which happens at run time inside the image exactly as on the JVM.
Verified rather than assumed: `-Dpolyglot.engine.TraceCompilation=true` on the
image produced compilation traces, and
`-Dpolyglot.engine.CompilationStatistics=true` produced a statistics dump at
close. `JDK_JAVA_OPTIONS`, which the JVM drivers used, is ignored by an image;
the properties must go on the command line.

---

## 5. Numbers

### nqp, `say(1)`

| | wall | user CPU |
|---|---|---|
| JVM (`nqp-j`) | **1.93 s** | 9.8 s |
| native image | **2.82 s** (2.841, 2.818) | 2.3 s |

The image is **1.46× slower in wall clock** and **4.3× cheaper in CPU**.

### Rakudo, `say(1)`

| | wall | user CPU |
|---|---|---|
| JVM (`rakudo-j`) | **3.66 s** | 22.8 s |
| native image | **5.45 s** | 4.7 s |

**1.49× slower in wall clock, 4.8× cheaper in CPU.** The ratio is remarkably
stable across the two workloads.

### CORE.c

See §6: started correctly, still in the parse stage at 785 s, killed. The JVM
finishes the whole compile in 297 s.

---

## 6. CORE.c through the image — started, reached `Stage start`, killed at 785 s

The run went in with the adopted tier policy plus one compiler thread, exactly
as asked:

```
-Dpolyglot.engine.Mode=latency
-Dpolyglot.engine.FirstTierCompilationThreshold=1600
-Dpolyglot.engine.LastTierCompilationThreshold=40000
-Dpolyglot.engine.CompilerThreads=1
-Dpolyglot.engine.CompilationStatistics=true
```

passed as plain `-D` arguments on the image's own command line (see §4 on the
mechanism).

**What happened.** The image loaded `rakudo.jar`, ran `src/main.nqp`, entered
`HLL::Compiler.command_line` and printed `Stage start : 0.000` at 3 s. It then
sat in the parse stage. At **785 s it was still in parse** — one process,
100 % of one core, 690 MB RSS, no second stage marker — and the user killed it
as not worth finishing.

Against the JVM stage breakdowns measured tonight on the same input:

| configuration | parse | total |
|---|---|---|
| JVM, `CompilerThreads=1` (adopted policy) | 226 s | **297 s** |
| JVM, default 6 threads | — | 337 s |
| JVM, guest compilation disabled entirely | 278 s | **360 s** |
| **native image, `CompilerThreads=1`** | **> 785 s, unfinished** | killed |

So the image's parse stage alone had already spent **3.5× the JVM's whole
parse at the best thread setting**, and **2.8× the parse of the JVM run with
guest compilation switched off entirely** — the fairest comparison, since §2
established that the image compiles no guest code at all. Extrapolating the
JVM's parse-to-total ratio it was heading for roughly nine minutes against
297 s. **The image loses this workload by something like 1.8× even against the
JVM's own worst configuration.**

That the compile was *correct* as far as it went matters more than the clock:
no missing class, no missing op, no reflection error, no deserialization
failure. It was simply slow.

---

## 6a. Why it was slow — hypothesis, labelled as such

**Stated as a hypothesis: the dominant cause is that AOT-compiled interpreter
code is slower than the same interpreter after HotSpot has finished with it,
and a several-minute compile gives HotSpot all the warm-up it could want.**
This is the obvious candidate and the evidence is consistent with it, but the
run was killed before it could be isolated, so it is not established.

What the logs actually support, in descending order of confidence:

1. **Guest compilation contributed nothing, and this is measured, not
   inferred.** `CompilationStatistics` on the first (short) CORE.c attempt
   reports `Compilations: 3, Success: 0`, and the `TraceCompilation` dump on
   nqp shows every root bailing with the `FrameWithoutBoxing` materialisation
   reason (§2). So the image was running the guest purely interpreted. The
   correct JVM comparison is therefore the 360 s "compilation disabled" run,
   and the image is still ~2.8× behind on parse. **Whatever is wrong is in the
   host, not in the tier policy.**
2. **The image used one core; the JVM used five to six.** Every image
   measurement in this report sits at ~100 % CPU while the JVM sits at
   520–650 %. On the short workloads that costs the image a factor of 1.5 in
   wall clock while saving a factor of 4–5 in CPU. On CORE.c the same
   single-threadedness is present, but the factor is much worse than 1.5,
   which says the parallelism argument does **not** explain CORE.c on its own.
3. **Therefore something is disproportionately slow in the image on this
   workload specifically.** Candidates I did not get to test: the AOT code for
   the deserialisation and `sixmodel` hot paths being compiled without
   profiles (a plain image has no PGO, and `nqp.sixmodel.reprs` was the
   largest non-JDK contributor to the code area at 463 KiB); the serial GC the
   image defaults to, against the JVM's parallel collector on a compile that
   allocates heavily; and `-H:-TruffleCheckBlockListMethods` leaving a
   materialised-frame path live in the interpreter. **Ranking these needs a
   profile of the image, which was out of scope and out of time.**

The honest summary is: the image is much more CPU-efficient and much slower in
wall clock on everything measured, and CORE.c is worse than the 1.5× the short
workloads would predict, for reasons this spike did not isolate.

---

## 7. The auxiliary engine cache (Question 2)

**Answer in one line: on today's evidence it would hold nothing, and even
fixed it would be caching a prize that milestone finding 2 has already capped
at 17.5 %.**

Longer: the auxiliary engine cache persists compiled guest code across
processes, and it is a Native Image feature — it needs an image to exist at
all. Three things have changed since it was listed as one of the three reasons
this direction was attractive:

- **It has nothing to store right now.** Guest compilation in this image fails
  100 % of the time (§2). `CompilationStatistics` reports successes 0. A cache
  over zero compiled roots is empty.
- **Once the `WeakHashMap` boundary is fixed, it would store first-tier code
  under the adopted policy.** `engine.Mode=latency` with
  `FirstTierCompilationThreshold=1600` is deliberately a policy that keeps
  compiler work small and rarely promotes to last tier on a compile-once
  workload. So the cache would hold mostly Tier 1 code — useful, cheaper than
  recompiling, but not the "fully optimised code, free" prize the original
  estimate assumed.
- **The prize is bounded by 17.5 % regardless.** Task 7 measured the entire
  guest-compilation contribution to a real CORE.c compile: 360 s with
  compilation off, 297 s at the best thread setting. Everything the engine
  cache could ever save is a fraction of that 63 s, because the cache removes
  compilation *time*, not interpretation time. If the cache eliminated every
  compiler microsecond and lost nothing in code quality, the ceiling is the
  compile-time half of that 63 s — and the image's own AOT penalty is larger
  than the whole of it.

So the honest revision is: the engine cache is no longer a reason to pursue
imaging. It is a nice-to-have that becomes available if imaging is pursued for
other reasons.

---

## 8. Why the image loses, and what it would take to win

The image removes exactly what it promised to remove — JVM boot, class
loading, and JIT warm-up — and it shows: CPU drops by a factor of four to
five, and the process is a single busy thread instead of six. What it cannot
do is replace what HotSpot buys with those extra five cores. On a two-second
workload HotSpot is already ahead; on a three-hundred-second one it has all
the time in the world.

Three things would have to change before an image beats the JVM here:

1. **Fix the PE blocklist violation** so guest compilation works at all. One
   `@TruffleBoundary` on `NFGString.atomsOf`, or a PE-safe grapheme cache.
   Until then the image is an interpreter with a Graal-shaped 39 MiB of dead
   weight.
2. **Profile-guided optimisation.** A plain AOT image is compiled without
   profiles; `--pgo-instrument` / `--pgo` on a CORE.c-shaped training run is
   the standard answer to "AOT peak is lower than JIT peak", and the interpreter
   loop is precisely the kind of code PGO helps most.
3. **Give the image the parallelism.** Nothing in the AOT binary uses the other
   fifteen cores. The JVM's advantage here is not code quality, it is that it
   is running a compiler on five threads while the application runs on one.

Item 1 is a one-line change. Items 2 and 3 are projects.

---

## 9. Did the nqp suite run through the image?

Not attempted as a suite. `t/harness5` and the nqp test harness invoke
`nqp-j`, a generated shell script with a fixed `java` command line; pointing
them at a binary that takes `-Djava.class.path=` and a unit-jar argument means
writing a shim that impersonates `nqp-j`. That is contorting the harness, and
the brief said to say so rather than do it. What *was* verified end to end:
`nqp -e 'say(1)'`, Rakudo `-e 'say(1)'`, Rakudo
`-e 'my @a = 1,2,3; say @a.map(* * 2).join(",")'` (correct output `2,4,6`),
and the CORE.c compile in §6. That exercises artifact load, deserialisation,
the setting, the grammar engine, the code engine and the whole compiler
frontend.

---

## 10. Hygiene

- `git status --porcelain --ignore-submodules=all` in the rakudo tree shows
  only the pre-existing untracked logs and `tools/build/t3b-*.raku` that were
  there at session start; the nqp tree is clean.
- `blib/` and `nqp/build/` untouched — the CORE.c output went to
  `$CLAUDE_JOB_DIR/tmp/m6-corec-image.jar`, never to `blib`.
- No file was written into either tree except this report and the ledger entry.
- The binaries (`nqp-image`, `nqp-image-opt`, `rakudo-image`), the metadata
  directories and every build log stay under `$CLAUDE_JOB_DIR/tmp` as the
  controller asked; none is committed.

## 11. Recommendation

**PARK — do not pursue, do not drop.** The number that justifies it: the image
was still in CORE.c's parse stage at **785 s** against a **297 s** whole-compile
on the JVM, and its parse alone had spent 2.8× the parse of the JVM run with
guest compilation disabled entirely — which is the like-for-like comparison,
because guest compilation in the image succeeds zero times. On the compiler
workload this milestone is about, an image is not close.

Not *drop*, for three reasons:

- **The structural result stands regardless of the clock.** An nqp image runs
  Rakudo from a data artifact (§3b). That is a permanent property of the
  unit-artifact road and it was unproven before tonight. Whatever we do with
  imaging, that fact is now banked.
- **The recipe is cheap to re-run.** Ninety seconds of build once the flags are
  known, and the flags are written down in §4. Re-testing after the
  `@TruffleBoundary` fix, or after PGO, costs minutes, not a day.
- **One known one-line source change is in the way.** Guest compilation fails
  100 % because of a `WeakHashMap` lookup inside a PE root (§2). Nobody should
  form a view about "Truffle in an image" from a measurement taken with the
  compiler switched off by accident.

**Short-lived versus long-lived workloads — asked separately, and the answer is
that they do NOT look different, which is the surprise.** The expectation going
in was that an image wins on short workloads and loses on long ones. What the
numbers say:

| workload | length | image vs JVM, wall |
|---|---|---|
| `nqp -e 'say(1)'` | ~2 s | 1.46× slower |
| `rakudo -e 'say(1)'` | ~4 s | 1.49× slower |
| CORE.c | ~300 s | ≥ 2.6× slower, unfinished |

**The image loses even on the two-second workload.** That is the finding that
should change how this direction is valued. The reason cold start is 1.9 s and
not 0.2 s is that almost none of it is JVM boot — it is artifact load, LZ4,
meta decode and running the setting's load blocks, which is *work*, and the
image has to do all of that too, with worse code and one core. An image removes
JVM boot and class loading, and JVM boot and class loading are roughly 0.1 s of
the 1.9 s. Finding 1's premise — "cold start is dominated by the serial
artifact load path, and an image heap removes exactly that" — is **half wrong**:
an image removes the *class* loading, not the *artifact* loading. The artifact
path still runs at run time, from the same jars, through the same LZ4 and the
same deserializer. To remove it you would have to put the loaded units into the
image heap at build time, which is a different and much larger project than
this spike, and which would re-couple the image to a specific Rakudo build.

So: park, with the recipe, the demand list and the `@TruffleBoundary` finding
written down. Revisit if and only if (a) the PE blocklist violation is fixed
so an image can actually compile guest code, and (b) somebody wants
`raku -e` startup badly enough to try PGO, in which case measure the
two-second workload first, because it is the best case and today it still
loses.
