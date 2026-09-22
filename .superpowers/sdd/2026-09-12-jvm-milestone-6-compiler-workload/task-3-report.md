# Task 3 report — the traced CORE.c baseline

**Status: DONE_WITH_CONCERNS.**

Everything the brief asked for is done, `EXIT=0`, and the STOP condition
did NOT fire: `min-too-large-size=2070`, not `none`. The concern is a
result, not a failure — the 114-root "code is too large" cluster that
Task 4's entire lever is aimed at has collapsed to **2 roots and 6.9 s**.
Task 4 is not blocked, but its ceiling is now ~0.3 % of the compiler
time it was sized against, and the controller should know that before
the sweep spends compiles on it.

- rakudo HEAD at start: **`3db3362101`** (worktree
  `jesp-direct-lazy-records`)
- nqp HEAD: **`41c294b02`** (the nested, gitignored nqp.git tree)
- Commit created: rakudo **`dd561dd58a`**. No nqp commit. No source file
  changed in either tree.
- `java`: Oracle GraalVM 25.2.4 (`25.0.4+7-LTS-jvmci-25.2-b20`).
  Confirmed before the run; the numbers stand.

## Step 1 — the traced compile

Run exactly as the brief gives it, with every path under
`$CLAUDE_JOB_DIR/tmp` (`/home/longwalker/.claude/jobs/804818e2/tmp`):

```
JDK_JAVA_OPTIONS='-Dpolyglot.engine.TraceCompilation=true -Dpolyglot.engine.CompilationStatistics=true' \
NQP_CODE_CLOSE_AT_EXIT=1 RAKUDO_RAKUAST=1 \
raku tools/build/watched-run.raku \
  --log=…/m6-corec-baseline.log --show-file=…/m6-corec-baseline.markers \
  --show='Stage' \
  -- perl rakudo-j-build --setting=NULL.c --ll-exception --optimize=3 \
       --target=jar --stagestats --output=…/m6-corec.jar gen/jvm/CORE.c.setting
```

`=== EXIT=0 verdict=ok elapsed=434s ===`

**`blib` is untouched.** `blib/CORE.c.setting.jar` still carries its
12:28 timestamp from Task 1's build; the new 5 865 125-byte jar is at
`…/tmp/m6-corec.jar`. Task 1's baseline state is intact.

### Stage table

```
Stage start      :   0.001
Stage parse      : 333.841
Stage syntaxcheck:   0.000
Stage ast        :   0.001
Stage optimize   :  36.584
Stage qast       :  34.266
Stage unit       :  27.539
Stage jar        :   0.000
```

Stages sum to 432.2 s against 434 s wall.

**Against Task 1 (asked for explicitly).** They agree, and where they
differ it is explained rather than assumed:

| clock | Task 1 (inside `make`) | Task 3 (standalone) |
|---|---|---|
| CORE.c wall | 457 s (marker-to-marker) | **434 s** |
| stage sum | 439.9 s | **432.2 s** |
| `Stage parse` | 344.091 | **333.841** |
| `Stage optimize` | 36.588 | **36.584** |

`Stage optimize` is the same number to three decimals, which is the
strongest evidence the two compiles are the same work. `Stage parse` is
10.3 s (3.0 %) faster here, *with tracing on*. That direction is not
suspicious: `TraceCompilation` and `CompilationStatistics` load the
background compiler threads, not the interpreter thread that `parse`
runs on, so the tracing cost lands in `total-compiler-ms` and not in
`Stage parse`. 3 % is ordinary run-to-run variance. The 457-vs-434 wall
gap is mostly measurement shape: Task 1's figure was marker-to-marker
between two `make` recipes (17 s of JVM start plus jar write between the
markers), mine is one process's own wall clock with a 1.8 s gap over the
stage sum. **Nothing here voids Task 1's baseline**, and the two are
comparable enough that later tasks can be judged against either.

## Step 2 — the summary

```
events=10759
deopt=3249
done=5656
failed=444
inval.=1267
reprof=143
unparsed=0
non-trace-lines=464803
reasons-parsed=4960

--- failures by reason ---
  count=442  mean=54ms    PermanentBailoutException: Too deep inlining, probably caused by recursive inlining.
  count=2    mean=3474ms  BailoutException: Code installation failed: code is too large

min-too-large-size=2070
  too-large roots: 2 (2 sized, 0 unsized)
  by size: IMPL-FOLD-CONSTANT[2070], IMPL-OPTIMIZE-EXPRESSION[4030]
  unclassified failure reasons (not matched as a size bailout):
    count=442  sizes: 27, 43, 43, … 12418, 17545, no-size ×5
                PermanentBailoutException: Too deep inlining, …

total-compiler-ms=2143944
nqp-root-ms=1937603
```

Top roots by compile time: `IMPL-SHOULD-PRIME[989]` 11.0 s,
`IMPL-ADD-QAST-ARGS[1477]` 9.4 s, `IMPL-TO-QAST[1858]` 7.1 s,
`encode_var[6418]` 5.8 s, `IMPL-CALCULATE-TYPES[1845]` 5.6 s — all
`done`, all tier 2. The expensive compilations succeed; they are not
the failure population.

`total-compiler-ms=2143944` (2144 s) exceeds the 434 s wall because
compilation runs on background threads — `Compilation Utilization :
5.224919` in the statistics block says ~5.2 compiler threads busy on
average. `nqp-root-ms=1937603` is 90 % of it, i.e. nine tenths of all
compiler time goes to roots carrying a wire-word count (nqp/Raku roots)
rather than to the runtime's own Java.

## The three checks the controller asked for

### (a) `none` with failures — did NOT fire

`min-too-large-size=2070`. The tool's `(failed=N, reasons-parsed=0)`
alarm did not appear, and could not have: `reasons-parsed=4960`,
`unparsed=0`. **Not BLOCKED.** Task 4 has a number to work from, and by
the plan's inclusive-comparison rule the threshold it should use is
**2069**.

### (b) Is the minimum plausible against its neighbours? — yes

`by size:` has exactly two entries, 2070 and 4030. A factor of 1.95, not
orders of magnitude. Neither is a spuriously tiny root, and the reason
that matched both is the real one:
`jdk.vm.ci.code.BailoutException: Code installation failed: code is too
large` — the code-installation limit, verbatim, on
`IMPL-FOLD-CONSTANT[2070]` (**3861 ms**, id 12556) and
`IMPL-OPTIMIZE-EXPRESSION[4030]` (**3086 ms**, id 2765). [Corrected in
fix round 1; these two were originally written the other way round. The
6.9 s total is unaffected.] No unsized too-large root, so nothing was excluded from the
minimum and it does not read high for that reason.

### (c) Did anything size-related land unclassified? — no, and this matters

One group, 442 failures:

```
jdk.graal.compiler.core.common.PermanentBailoutException:
  Too deep inlining, probably caused by recursive inlining.
```

**It is not a size bailout and must not be added to the selector's
spellings.** Two independent reasons:

1. **Its sizes do not behave like a size limit.** They run from **27**
   wire words to 17545, plus 5 roots with no size at all. A limit that
   refuses a 27-word root and admits a 989-word root that compiles
   successfully in 11 s is not a limit on size. Adding this spelling
   would set `min-too-large-size=27`, and `NQP_CODE_MAX_COMPILE=26`
   would refuse essentially every compilation in the run — precisely the
   destroyed measurement the ledger's ruling on the `exceeds` guess
   anticipated. The unclassified block behaved exactly as designed.

2. **The bailout names its own cause.** *(Superseded by fix round 1
   below: there are TWO recursions, not one, and both are entered from
   our own operation nodes — `NqpTypeOps.create` and the sited
   `NqpOps.getattr`/`bindattr` road — not from the JDK alone. Read the
   fix-round section for the corrected account.)* Each such
   failure carries an inlined-method dump (which is why the reason text
   contains newlines). The recursion is:

   ```
   java.lang.Throwable.printStackTrace()
   org.raku.nqp.runtime.ExceptionHandling.dieInternal(ThreadContext, String, Throwable)
     -> sun.reflect.generics.repository.ClassRepository.parse(String)      [33]
     -> sun.reflect.generics.parser.SignatureParser.parseClassSignature()  [32]
     -> ClassRepository.parse -> AbstractRepository.<init> -> Class.getGenericInfo() …
   ```

   The JDK's generics-signature parser, reached through the exception
   reporting path, inlined 33 frames deep. It has nothing to do with the
   nqp root's size; the root is merely whatever happened to be compiling
   when the inliner walked into it.

At 23.7 s of 2144 s this is not a large clock by itself, but it is **442
compilations thrown away**, 442 of the 444 permanent bailouts, and the
cause is one Java call chain rather than anything in the generated code.
Recorded in the findings doc as a milestone 7 candidate.

## The result the controller most needs: the 2026-09-07 cluster is gone

| | 2026-09-07 trace | this trace |
|---|---|---|
| total compiler time | 1880 s | 2144 s |
| roots failing `code is too large` | **114** | **2** |
| mean per failed root | 6.4 s | 3.47 s |
| compiler time on them | **733 s** | **6.9 s** |

733 s → 6.9 s, 0.9 % of the earlier figure and 0.3 % of this run's
compiler time. This is a change in the tree, not in the instrument: the
instrument is new, but it reads `unparsed=0` and finds both spellings it
knows, and the two roots it does find are real and named. Nothing in
milestone 6 caused it; milestone 5's RakuObject layout work and the
engine merge are the two unexamined candidates, and neither was measured
against this cluster.

**What that implies for Task 4.** The knob is still worth its one
compile — it has never been measured, the arithmetic is trivial
(2070 − 1 = 2069) and a null result is itself a recorded fact. But its
ceiling on CORE.c is now ~7 s of *background* compiler time and
approximately **0 s of the 434 s wall clock**, because both roots
compiled on background threads while `Stage parse` ran. It should be
judged as a runtime-side decision (skipping a root that will fail to
install saves the JIT work and leaves the root in the interpreter) and
not as a build-side win, and the sweep should not expect the wall clock
to move. If Task 4's compile lands within noise of 434 s, that is the
expected outcome, not a measurement error.

## Step 4 — the failure-line format: CONFIRMED, no repair needed

```
$ grep -m2 'opt failed' …/m6-corec-baseline.log
[engine] opt failed engine=1  id=346   classlib_record[394]   |Tier 1|Time   241( 241+0   )ms|Reason: jdk.graal.compiler.core.common.PermanentBailoutException: Too deep inlining, probably caused by recursive inlining.
[engine] opt failed engine=1  id=98    search_path[583]       |Tier 1|Time   116( 116+0   )ms|Reason: …
```

`|Reason: ` with the colon, exactly as Task 2's decompilation of
`TraceCompilationListener.FAILED_FORMAT` predicted, and the parser reads
it: `unparsed=0`, both reason groups non-empty, `reasons-parsed=4960`.
The `code is too large` line shows the full format including the
trailing fields:

```
[engine] opt failed engine=1  id=2765  IMPL-OPTIMIZE-EXPRESSION[4030]  |Tier 1|Time  3086(1501+1585)ms|Reason: jdk.vm.ci.code.BailoutException: Code installation failed: code is too large|UTC 2026-09-12T11:33:17.720|Src n/a
```

One wrinkle worth recording, which the brief could not have known: the
`Too deep inlining` reason text **contains newlines** — the exception
message embeds the inlined-method dump — so each of those 442 failures
spills roughly a thousand continuation lines that do not begin with
`[engine] opt `. They are counted in `non-trace-lines=464803` (which is
why that tally is 465 k against 10 759 events) and the reason parses
correctly from the first line. Nothing was lost silently; the tool's
own tallies account for it.

## Step 5 — named Sources do NOT reach the statistics

**Answer: no.** Two findings, both from this log:

1. **Every trace line reports `Src n/a`.** 10 763 lines carry a `|Src `
   field; 10 763 of them read `|Src n/a`. Not one exception, across
   `done`, `failed`, `deopt`, `inval.` and `reprof`. The root nodes have
   no `SourceSection`, so the engine has no Source to attribute.

2. **The `CompilationStatistics` block has no per-Source grouping at
   all.** It identifies targets by root *name*:
   `maxTarget=IMPL-FOLD-CONSTANT[2070]`, `maxTarget=walk[7260]`,
   `maxTarget=parse[351]`, `maxTarget=submethod_table[54]`,
   `maxTarget=IMPL-SHOULD-PRIME[989]`. Its breakdowns are by bailout
   reason and by invalidation reason, never by source file.

What the engine merge's per-block naming actually delivers is
`NqpRootNode.getName()` — and it delivers it well: the names are
per-block, distinguishing, and carry the wire-word count in brackets,
which is the only reason `min-too-large-size` is computable at all.
There is **no** single `nqp-code` blob; attribution works. It just works
through names, not through Truffle Sources. Anything wanting file/line
attribution out of the engine's own reporting needs a real
`SourceSection` on the root node first. The follow-up the engine merge
deferred is answered: closed, negative.

## Step 3 / Step 6 — ledger and findings doc

Ledger entry **appended at the very end**; nothing already present was
edited, in particular no `Ruling`, `Task 1:` or `Task 2:` line. The
ledger carried one uncommitted modification before I started (the
controller's "Task 3: implementer dispatched" paragraph); it is included
in the commit, unaltered.

`docs/jvm-perf-findings-2026-09.md` did not exist and was created as the
skeleton Task 11 will fill: the configuration table with the baseline
row and four empty rows, the baseline failure population, the
cluster-collapse finding, the recursive-inlining finding, placeholder
sections for the three clocks and the ranked lever list, the pre-rebase
statement, the BOOTSTRAP v6c 398 s clock named and explicitly left
unmeasured, the build-graph statement, and the Step 5 answer.

Commit rakudo **`dd561dd58a`**, `2026-09-12 19:50:00 +0200` on both
`GIT_AUTHOR_DATE` and `GIT_COMMITTER_DATE`, with the trailer verbatim.
Two files, 208 insertions, nothing else staged — the untracked
`engine-merge-*.log`, `sweep-logs/` and `tools/build/t3b-*.raku` that
predate this task are left exactly as found, and no log was committed.

## Constraints observed

No subagents. `tools/build/truffle-trace-summary.raku` not modified and
not found wanting — it produced every block the controller named, its
`unparsed=0` and its unclassified block are what make check (c)
answerable, and its refusal to guess a third size spelling is the reason
`min-too-large-size` is 2070 and not 27. No build, no nqp suite, no `t/`
test: one compile, then its trace.

## Concerns

1. **Task 4's lever has collapsed since 2026-09-07** — 733 s → 6.9 s,
   2 roots, and both on background threads. Run it, but expect a null
   result on the wall clock and do not read that as a broken
   measurement.
2. **442 compilations are discarded to a JDK-side inlining recursion**
   (`Throwable.printStackTrace` → generics `SignatureParser`), unrelated
   to root size and therefore untouched by any knob in this milestone.
   23.7 s of compiler time, and a plausible milestone 7 item.
3. **Four trace events were swallowed by stdout interleaving.**
   `--stagestats` prints its label before the stage runs, and a
   compiler-thread trace line landed on the same output line for
   optimize/qast/unit/jar; those four events (2 `done`, 1 `inval.`,
   1 `reprof`) do not begin with `[engine] opt ` and were counted as
   non-trace lines. This is the whole of the `done=5656` vs statistics
   `Success: 5658` gap. The stage *times* survived on the following line
   and were read from there. Every later compile in the sweep will lose
   the same four lines identically, so it cannot move a comparison —
   but a reader diffing `done` against the statistics block should know
   why they differ by two.
4. **`total-compiler-ms` is 2144 s against the reference's 1880 s**,
   +14 %, while wall clock fell. Not investigated; with
   `Compilation Utilization 5.22` this is background work that the wall
   clock does not pay for directly, and the two traces are from
   different trees. Flagged only so the sweep does not read a change in
   this figure as a change in build time.

---

# Fix round 1 — the bailout diagnosis, re-derived from the log

Commit rakudo **`<second commit>`**, stamp `2026-09-12 19:55:00 +0200`.
No re-run; everything below is read out of the log Task 3 already
produced. All counts are mine, computed over the trace **excluding the
statistics block**, because that block reprints 6 representative bailout
messages with their dumps (448 dumps in the file, 442 in the trace —
which is exactly the 442 failures, so the census closes).

## Correction 1 — there are two recursions, not one

I named one chain. The 442 in-trace dumps split into two, and they add
up with no remainder:

| chain | dumps | top frequency entry | independent cross-check |
|---|---|---|---|
| A, generics parser | **238** | `ClassRepository.parse(String)` 236 + `AbstractRepository.<init>` 2 | `ExceptionHandling.dieInternal` 476 = 238 x 2 |
| B, `getSimpleName` | **204** | `Class.getSimpleName()` 204 (201 of them at `[495]`) | `newWrongMethodTypeException` 408 = 204 x 2 |
| | **442** | | = `failed` minus the 2 size bailouts |

The reviewer's figures were taken over the whole file (237 / 203 / 416 /
480 / 448); mine exclude the six statistics-block reprints. Both are
right about the same thing; the in-trace numbers are the ones that
correspond one-to-one with failures, so those are what the findings doc
now carries.

## Correction 2 — the entry point is ours, in both chains

This is the correction that matters, and my phrase "one Java call chain
rather than anything in the generated code" was wrong in exactly the way
that hides a lever. Read bottom-up, both graphs start in our own
operation nodes:

**Chain B** (the one the reviewer named):
`NqpRootNodeGen.execute` -> `handleBindAttrOp_` ->
`NqpRootNode$BindAttrOp.doBind` -> **`NqpOps.bindattr(NqpOps.java:1517)`**
(39) / **`NqpOps.getattr(NqpOps.java:1482)`** (165) ->
`Invokers.newWrongMethodTypeException(Invokers.java:522)` ->
`String.valueOf` -> `MethodType.toString(MethodType.java:936)` ->
`Class.getSimpleName` x 495. 39 + 165 = 204 = the chain-B dumps exactly.
This is milestone 5's sited MethodHandle attribute road; the current
worktree source has those `invokeExact` calls at `NqpOps.java:1500`
(getter) and `:1536` (setter), a few lines off the built jar's numbering.

**Chain A** (which the reviewer did not trace to its entry, and which I
did): every one of its 238 dumps bottoms out identically —
`NqpRootNodeGen.execute` -> `handleCreateOp_` ->
`NqpRootNode$CreateOp.doCreate` -> **`NqpTypeOps.create`** ->
**`VMArray.allocate(ThreadContext, STable)`** ->
**`ExceptionHandling.dieInternal(ExceptionHandling.kt:47)`** ->
`Throwable.printStackTrace()` -> `ClassRepository.parse` x 33. I checked
the source line: `ExceptionHandling.kt:47` is
`if (tc.gc.noisyExceptions) (t ?: Throwable(msg)).printStackTrace()` — a
debug branch behind a mutable runtime flag Graal cannot fold. The
grep is unambiguous: the frame directly under `dieInternal` is
`VMArray.allocate` in 238 of 238 dumps, and directly under that,
`NqpTypeOps.create` in 238 of 238.

So both chains are our sited-op roads walking into a Java error branch,
not the JDK misbehaving on its own.

## Correction 3 — speculation, not throwing; say so

Stated explicitly now in the doc. My evidence, independent of the
reviewer's: zero lines in the 30 MB log match `Unhandled exception` or
`at org.raku`; all 476 `dieInternal` occurrences are dump entries (240
in frequency lists, 240 in stack traces, counting the statistics
reprints); and `non-trace-lines=464803` is ~442 x ~1000, which accounts
for the dumps and leaves no room for printed traces. Nothing is failing.

## Correction 4 — it is a lever, not a candidate

Rewritten as such. The clock that matters is not the 23.7 s of compiler
time; it is **442 roots that bail and stay interpreted for the whole
compile**, on a workload that is 90 % interpretation (`Stage parse`
333.8 s of 434 s). Two one-sided fixes named in the doc:
`@TruffleBoundary` on `dieInternal` / the `noisyExceptions` branch
(238 roots), and an `asType`/guard at the `invokeExact` sites so the
`WrongMethodTypeException` construction branch is provably dead
(204 roots). Both are code, not knobs, so they are milestone 7's, not
this sweep's.

## Correction 5 — the selector refusal, written down

The reasoning is now in the doc rather than only in this report: sizes
run 27 to 17545, so adding the spelling sets `min-too-large-size=27` and
`NQP_CODE_MAX_COMPILE=26` refuses essentially every compilation in every
later measurement. Not a close call.

## Correction 6 — the two wrong numbers

- **Findings doc, the cluster-collapse ratio.** "0.3 % of the compiler
  time that cluster once cost" was wrong; 6.9 / 733 = **0.9 %**. The doc
  now gives both ratios with their arithmetic so they cannot be
  conflated again (6.9/733 = 0.9 %, 6.9/2144 = 0.3 %).
- **This report, section (b).** The two roots' times were swapped. The
  log has `IMPL-OPTIMIZE-EXPRESSION[4030]` at **3086 ms** (id 2765) and
  `IMPL-FOLD-CONSTANT[2070]` at **3861 ms** (id 12556). Fixed in place
  with a note. The 6.9 s total, the mean of 3474 ms and the Step 4
  quotation were all already correct.

Also added to the doc while I was in it: the independent confirmation
that there are exactly two size bailouts — Graal's own
`CompilationStatistics` tally reads `Code installation failed: code is
too large: 2`, a count the summarizer never touches, and `too large`
occurs three times in the whole log.

**Deferred as instructed, not fixed:** the Task 1 wall-clock citation of
457 s where the markers file says 460 s.
