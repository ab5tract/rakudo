### Task 4: Knob 1 — `NQP_CODE_MAX_COMPILE`

The knob already exists
(`nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java:113-123`):
it reads the environment variable once into `MAX_COMPILE_SIZE`
(default `Integer.MAX_VALUE`) and `prepareForCompilation` answers
`programSize <= MAX_COMPILE_SIZE`. The unit is **wire words**. It has
never been measured.

> **REFRAMED after Task 3 (controller ruling 11, 2026-09-12). Read this
> before Step 1.** This task was written to reclaim a specific waste: a
> 2026-09-07 trace found 114 roots failing "code is too large" after a
> mean 6.4 s each, 733 s of compiler time spent on roots that end up
> interpreted anyway. Task 3 re-measured and **that cluster is gone**:
> 2 roots, 6.9 s total, verified by an independent grep and by Graal's
> own `CompilationStatistics` bailout tally.
>
> The knob's original rationale — quoted in `NqpRootNode`'s own comment,
> that "such a root runs interpreted afterwards regardless, so refusing
> up front costs it nothing" — held only for roots that were going to
> fail. With two such roots, it is now **false for almost everything the
> threshold touches**. `prepareForCompilation` gates EVERY root, so a
> threshold of 2069 refuses compilation of every root above 2069 wire
> words, the overwhelming majority of which compile successfully today.
>
> So this is no longer a free-reclamation experiment. It is a crude test
> of the milestone's actual thesis: that the compiler's own run-once code
> is being over-compiled. Task 3 measured 2144 s of compiler-thread work
> across a 434 s wall compile, about five cores, with 90 % of it on NQP
> roots. Refusing the large roots outright is the bluntest possible probe
> of whether that work buys anything.
>
> Run it anyway — it is one compile and the effect will be large in one
> direction or the other — but judge it on the right quantities and
> record the reframing in the ledger. **Runtime-side adoption is off the
> table regardless**: refusing to compile large roots at run time would
> cost Rakudo's own runtime performance, which outranks compile time.

**Files:**
- Modify: none yet (adoption is Task 11)
- Ledger: one configuration row

**Interfaces:**
- Consumes: `min-too-large-size` from Task 3.
- Produces: a keep-or-drop verdict and, if kept, the value that every
  later compile carries.

- [ ] **Step 1: Choose the threshold**

Take `min-too-large-size=N` from Task 3 and use `N - 1`. Rationale: a
root at or above the smallest size that actually failed to install will
also fail, so refusing it up front costs nothing. Record the arithmetic
in the ledger.

**The minus one is load-bearing, not caution.**
`NqpRootNode.prepareForCompilation` answers `programSize <=
MAX_COMPILE_SIZE`, which is INCLUSIVE
(`nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java:119-123`).
Setting the knob to `N` therefore still admits the very root the number
came from, and the compile would spend its 6.4 s failing to install
exactly as before. The result would look like a plausible non-result:
the knob apparently did nothing. `N - 1` is the exclusive threshold.

**Do not read the number alone.** Read the `--- failures by reason ---`
block, the `by size:` list and the `unclassified failure reasons` block
beside it, and record in the ledger what you saw there. Two checks, both
cheap:

- **Is the minimum plausible against its neighbours?** If the smallest
  root is orders of magnitude below the next entry in `by size:`, find
  out which reason matched it before trusting it. A threshold set from a
  spuriously tiny root would refuse nearly every compilation on this
  run, which does not bias the measurement, it destroys it.
- **Did anything land in the unclassified block?** That block exists to
  make an unrecognised size-bailout spelling loud. If it names a reason
  that is plainly about size, the selector needs that spelling and the
  minimum currently reads high.

Task 2's review established the selector matches only the two spellings
verified to exist in this tree: `code is too large` from the trace, and
`too big to safely compile` from `libjvmcicompiler.so`. Anything else is
deliberately left to the unclassified block and a human, because a
guessed-at loose substring converts a loud unknown into a silent wrong
answer.

If Task 3 reported `min-too-large-size=none`, this knob has nothing to
act on: record that, skip to Task 5, and note in the findings doc that
the 2026-09-07 observation did not reproduce.

- [ ] **Step 2: Probe the configuration**

This knob is an environment variable, not a polyglot option, so it
cannot be rejected by the engine builder. Confirm it parses:

```bash
NQP_CODE_MAX_COMPILE=<N-1> java --module-path nqp/build/jvm/share/truffle \
  --add-modules org.graalvm.truffle,org.graalvm.truffle.runtime \
  --enable-native-access=org.graalvm.truffle --sun-misc-unsafe-memory-access=allow \
  -cp "nqp/build/jvm/share/runtime/nqp-runtime.jar:nqp/build/jvm/share/runtime/nqp-truffle.jar:nqp/build/jvm/share/runtime/kotlin-stdlib-2.4.10.jar:nqp/build/jvm/share/runtime/fastutil-8.5.19.jar:nqp/build/jvm/share/runtime/annotations-13.0.jar:nqp/build/jvm/share/runtime/lz4-java-1.8.0.jar" \
  org.raku.nqp.truffle.NqpCheck
```

Required positive marker: the literal line `nqp-code check passed`. A
non-numeric value would throw `NumberFormatException` here instead of
eight minutes into a compile.

- [ ] **Step 3: One compile**

```bash
NQP_CODE_MAX_COMPILE=<N-1> \
JDK_JAVA_OPTIONS='-Dpolyglot.engine.TraceCompilation=true -Dpolyglot.engine.CompilationStatistics=true' \
NQP_CODE_CLOSE_AT_EXIT=1 RAKUDO_RAKUAST=1 \
raku tools/build/watched-run.raku \
  --log=$CLAUDE_JOB_DIR/tmp/m6-corec-maxcompile.log \
  --show-file=$CLAUDE_JOB_DIR/tmp/m6-corec-maxcompile.markers \
  --show='Stage' \
  -- perl rakudo-j-build --setting=NULL.c --ll-exception --optimize=3 \
       --target=jar --stagestats \
       --output=$CLAUDE_JOB_DIR/tmp/m6-corec.jar gen/jvm/CORE.c.setting
```

- [ ] **Step 4: Summarize and decide**

```bash
raku tools/build/truffle-trace-summary.raku $CLAUDE_JOB_DIR/tmp/m6-corec-maxcompile.log
```

**Judge it on the mechanism, not only the wall clock.** Under the
reframing above, the interesting question is whether suppressing
compilation of large roots reduces the compiler's work at all, and
whether that reduction reaches the wall clock. Record all four, against
Task 3's baseline of wall 434 s, done 5656, failed 444,
`total-compiler-ms` 2143944 and `nqp-root-ms` 1937603:

| quantity | what it tells you |
|---|---|
| wall clock | the number the user watches; the verdict rests here |
| `total-compiler-ms` | whether the knob actually removed compiler work |
| `done` count | how many roots it suppressed; a large drop with no wall-clock gain means the compilation was not on the critical path |
| `failed` count | the two "too large" roots should vanish; if they do not, the threshold is wrong or inclusive-off-by-one |

Keep the knob if the wall clock drops. Record the verdict KEEP or DROP
with the number that justifies it. A large fall in `total-compiler-ms`
with a flat wall clock is a real and reportable result, not a failure:
it says the compiler threads were not contending with the compile, which
would in turn demote Task 7's thread-count knob before it runs.

**Both clocks.** A root that is never compiled never speeds up at
runtime either. Note explicitly in the ledger that this knob is a
candidate for build-side adoption only, and that Task 11 decides the
runtime side separately.

- [ ] **Step 5: Commit the ledger**

```bash
git add docs/superpowers/plans/2026-09-12-jvm-milestone-6-compiler-workload.ledger.md
GIT_AUTHOR_DATE="2026-09-12 20:00:00 +0200" GIT_COMMITTER_DATE="2026-09-12 20:00:00 +0200" \
  git commit -m "M6 Task 4: NQP_CODE_MAX_COMPILE measured

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01T8zpD6QrhN6Pmp5TePheq6"
```

---

