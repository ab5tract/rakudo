### Task 12: Native Image of nqp alone

> **Does adopting `Mode=latency` conflict with imaging? No — they are on
> different axes, and they are complementary (user question,
> 2026-09-12).**
>
> Native Image compiles the HOST: our interpreter, the Java and Kotlin,
> into a native binary. Truffle's tiers compile the GUEST: the encoded
> NQP that interpreter runs. Both still exist inside an image, provided
> it is built with the optimising Truffle runtime, and a root can still
> climb interpreted to first tier to last tier there exactly as on the
> JVM. `engine.Mode` is read when the engine is constructed, which
> happens at runtime even inside an image, so it is a per-process option
> and not a structural property. This milestone adopts it for the BUILD
> JVM only and never for `rakudo-j`, so the image is unaffected either
> way.
>
> They pull in the same direction. Latency mode stops us paying Graal to
> optimise guest code that runs a handful of times; an image stops us
> paying HotSpot to interpret the interpreter before it warms up. Both
> address the same underlying fact, that a compiler's own code is
> run-once work being treated as hot. Under latency we lean harder on
> the interpreter loop, which is precisely what an image precompiles, so
> today's tier-policy result RAISES the value of this spike rather than
> lowering it.
>
> **Two things this task must therefore state explicitly:**
>
> - **Which kind of image it built.** An image without the optimising
>   runtime is interpreter-only: no tiers, no guest compilation ever.
>   That is a legitimate fast-startup configuration, but it is a choice,
>   and the two kinds have very different performance shapes. Say which,
>   and why.
> - **What the auxiliary engine cache would actually hold.** It persists
>   compiled guest code across runs and was one of the three reasons this
>   direction was attractive. If the build pins everything to first tier,
>   the cache stores first-tier code — still useful, but a smaller prize
>   than caching fully optimised code. Note the interaction rather than
>   assuming the original estimate still stands.

A spike. The output is an answer and a recipe, never a kept binary:
every runtime change invalidates an image.

**Scope:** nqp only. No Rakudo, no NativeCall, no interop. Those are the
remaining blockers and none of them is in this path.

**Interfaces:**
- Consumes: Task 1's nqp baseline numbers.
- Produces: a recipe, startup and suite numbers or a reason there are
  none, and a pursue/park/drop recommendation.

- [ ] **Step 1: Confirm the tool exists**

```bash
native-image --version
```

If it is absent, install it via `gu install native-image` or record that
this GraalVM distribution does not carry it. That answer closes the
phase honestly; do not spend the milestone installing a toolchain.

- [ ] **Step 2: Attempt the image**

Build an image whose entry point is `org.raku.nqp.runtime.unit.UnitMain`
over the nqp unit jars, with the Truffle modules on the module path.
Truffle languages need `--language:nqp` style registration or the
`TruffleBaseFeature`; start from:

```bash
native-image \
  --module-path nqp/build/jvm/share/truffle \
  --add-modules org.graalvm.truffle,org.graalvm.truffle.runtime \
  -cp "nqp/build/jvm/share/runtime/nqp-runtime.jar:nqp/build/jvm/share/runtime/nqp-truffle.jar:nqp/build/jvm/share/runtime/kotlin-stdlib-2.4.10.jar:nqp/build/jvm/share/runtime/fastutil-8.5.19.jar:nqp/build/jvm/share/runtime/annotations-13.0.jar:nqp/build/jvm/share/runtime/lz4-java-1.8.0.jar:nqp/build/jvm/share/lib/nqp.jar" \
  --no-fallback \
  -o $CLAUDE_JOB_DIR/tmp/nqp-image \
  org.raku.nqp.runtime.unit.UnitMain \
  2>&1 | tee $CLAUDE_JOB_DIR/tmp/m6-native-image.log
```

Expect reflection and resource failures on the first attempt. Each one
is data: record what the image build demands, because that list is the
real answer to "how far is Rakudo from an image".

**Time-box: four hours.** If the image will not build by then, stop.
"It would not build, and here is the list of what it demanded" is a
valid and useful close.

- [ ] **Step 3: If it builds, measure**

```bash
time $CLAUDE_JOB_DIR/tmp/nqp-image -e 'say(1)'
```

Against Task 1's baseline for the same program on the JVM. Then run the
nqp suite through the image if the harness can be pointed at it, and
record the red set against Task 1 Step 7's nine known reds.

- [ ] **Step 4: Record the recipe and the numbers**

Into the findings doc, a section with the exact command, the flags the
build demanded, the numbers or the failure list, and the JVM comparison.

- [ ] **Step 5: Commit**

```bash
git add docs/jvm-perf-findings-2026-09.md docs/superpowers/plans/2026-09-12-jvm-milestone-6-compiler-workload.ledger.md
GIT_AUTHOR_DATE="2026-09-12 22:40:00 +0200" GIT_COMMITTER_DATE="2026-09-12 22:40:00 +0200" \
  git commit -m "M6 Task 12: the Native Image spike on nqp alone

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01T8zpD6QrhN6Pmp5TePheq6"
```

The image binary itself is never committed. It lives in
`$CLAUDE_JOB_DIR/tmp` and dies with the job, because every runtime
change invalidates it.

---

