# Milestone 6: the compiler's own workload — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking. Keep a ledger twin at
> `docs/superpowers/plans/2026-09-12-jvm-milestone-6-compiler-workload.ledger.md`
> (project convention: every ruling, every deferred minor, every task
> verdict goes in it as it happens, not at the end).

**Goal:** Rank and adopt the levers on the compiler's own workload
(truffle-only plan item 4), then decide on ahead-of-time compilation
from measured numbers.

**Architecture:** Three phases. Phase A rebuilds at HEAD, builds two
Raku log summarizers, takes a traced CORE.c baseline, then sweeps four
knobs one compile at a time, cheapest first, keeping every winner in for
the next compile. Phase B spikes a Native Image of nqp alone. Phase C
rebases both trees onto their upstream mains and pushes. There is no
confirmation build: the last measurement is already a measurement of the
shipping configuration.

**Tech Stack:** NQP and Raku on the JVM; Oracle GraalVM 25.2.4 with
Truffle; Kotlin and Java for runtime code; Raku for all tooling; Gradle
for the nqp side; GNU make for the Rakudo side.

**Spec:** `docs/superpowers/specs/2026-09-12-jvm-milestone-6-compiler-workload-design.md`

## Global Constraints

Every task's requirements implicitly include this section.

- **Two git working trees.** This directory is rakudo.git; `nqp/` is the
  nqp.git working tree nested inside it, gitignored, NOT a submodule.
  `git -C nqp ...` for that tree. Label every hash with its tree ("nqp
  `8f8b2909d`" vs "rakudo `e6ca966f4a`"). Write nqp paths with the
  `nqp/` prefix. Run gradle from the root: `./nqp/gradlew -p nqp ...`,
  never via `cd`.
- **`RAKUDO_RAKUAST=1` on every build, test and run.** The Makefile
  exports it into its own recipes; nothing sets it for your own
  invocations.
- **`NQP_CODE_RUN` and `NQP_CODE_PRECOMP` must not be set at all.** The
  compiler dies on `=0`. There is no class road to opt out to.
- **`java` must be Oracle GraalVM 25.2.4.** Verify with `java -version`
  before any measurement; a plain JDK voids every number.
- **Long builds and test runs go through `tools/build/watched-run.raku`**
  with `--log` and `--show-file`. Do not hand-roll timestamp wrappers or
  tail-based monitors.
- **Never replace an eval server mid-sweep.** Pass the total file count
  as `--chunk` to `tools/build/evalserver-sweep.raku`. The script's own
  default (`max(3, $h * 15 div 8)`) and its "lower `--chunk`" message
  are stale, from the leak fixed in nqp `4c7f652ea`.
- **One compile per change. No A/B arms.** A configuration is never
  re-run. Forward only.
- **Runtime performance outranks compile time** when a change trades one
  for the other; every adopted knob reports which clock moved.
- **Tooling in Raku**, never Python or shell.
- **Every diagnostic env-gated**: `nqp::say(...) if
  nqp::getenvhash()<AN_ENVVAR>;` in NQP/Raku sources,
  `System.getenv(...)` in runtime code. Never a bare print.
- **Smoke-test every instrument on a short workload and require a
  positive marker** before any long run. Abort a long run whose marker
  never appears.
- **Subagents default to Opus.** Re-run on Fable only after erroneous
  output; log the escalation in the ledger.
- **Commits stamped in the evening**: `GIT_AUTHOR_DATE` and
  `GIT_COMMITTER_DATE` between 18:00 and 23:00 of the working date.
- **Commit trailer on every commit:**
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_01T8zpD6QrhN6Pmp5TePheq6`.
- **The in-tree runners have no installed module repo**: anything with a
  `use` needs `-Ilib`.
- **No `t/spec`** in this milestone. It is gated on `t/` under 30
  minutes; the last measured sweep was 420 files in 6039 s.

## File Structure

Created:

| path | responsibility |
|---|---|
| `tools/build/truffle-trace-summary.raku` | parse a Truffle compilation trace; report compiles by verb, failures by reason, top roots by compile time, and the smallest program size among roots that failed to install |
| `tools/build/t/truffle-trace-summary.rakutest` | its tests, run by system `raku` |
| `tools/build/t/fixtures/trace-sample.log` | real trace lines captured from this tree 2026-09-12 |
| `tools/build/jfr-summary.raku` | parse `jfr print --events jdk.ExecutionSample` output; report samples per thread, per load-path stage, and the top leaf frames |
| `tools/build/t/jfr-summary.rakutest` | its tests |
| `tools/build/t/fixtures/jfr-sample.txt` | real `jfr print` blocks captured from this tree 2026-09-12 |
| `docs/jvm-perf-findings-2026-09.md` | the findings doc: configuration table, three clocks, ranked lever list |
| `docs/superpowers/plans/2026-09-12-jvm-milestone-6-compiler-workload.ledger.md` | the ledger twin |

Modified:

| path | change |
|---|---|
| `tools/lib/NQP/Config/Rakudo.pm:400-407` | adopted polyglot options appended to `j_truffle_opts` (perl list form) and `j_truffle_args` (shell string form) |
| `tools/templates/jvm/rakudo-j-build.in` | adopted env knobs exported for the build |
| `tools/build/create-jvm-runner.pl:215` | adopted runtime options appended to `$jopts` |
| `tools/build/evalserver-sweep.raku:34,67,111` | the `--chunk` default and the "lower --chunk" message rewritten |
| `docs/jvm-truffle-only-plan.md:35` | the item 4 position row |
| `docs/jvm-pr-stack.md` | rows for milestone 5, the engine merge, milestone 6 |

Scratch (never committed): use `$CLAUDE_JOB_DIR/tmp` for logs, traces,
recordings and scratch compile outputs.

---

## Phase A: baseline and knob sweep

### Task 1: The clean build at HEAD

The tree's build products do not match HEAD. The stage and compiler jars
are from 2026-09-11 21:16 and the settings from 21:17-21:34, while nqp
`7e7aaca61` and `df564ddbb` both change the encoder, which needs a
`clean buildJvm` because the stage graph misses that edge. Evidence that
the runners are stale too: the generated `rakudo-j-build` still lists
`asm-9.10.1.jar` and `asm-tree-9.10.1.jar` on its classpath, and
milestone 5 deleted both.

Measuring on this state would repeat the trap that voided milestone 4's
numbers, where every runtime figure came from a setting that never
lowered native arithmetic.

**Files:**
- Modify: none (build only)
- Ledger: record every timing in the ledger twin

**Interfaces:**
- Produces: the milestone baseline — nqp clean build seconds, `make`
  seconds from the top, and the CORE.c stage times (parse, optimize).
  Every later task compares against these, not against milestone 5's.

- [ ] **Step 1: Confirm the toolchain**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records
java -version 2>&1 | head -2
```

Expected: `Oracle GraalVM 25.2.4`. If it is anything else, stop and say
so; every number in this milestone is void otherwise.

- [ ] **Step 2: Record the pre-build state in the ledger**

```bash
git log --oneline -1
git -C nqp log --oneline -1
stat -c '%y  %n' blib/CORE.c.setting.jar nqp/build/jvm/share/lib/nqp.jar
```

Write both hashes and both timestamps into the ledger. This is the
evidence for why the rebuild happens.

- [ ] **Step 3: Clean-build nqp**

```bash
raku tools/build/watched-run.raku \
  --log=$CLAUDE_JOB_DIR/tmp/m6-nqp-build.log \
  --show-file=$CLAUDE_JOB_DIR/tmp/m6-nqp-build.markers \
  --show='Stage' --show='BUILD' \
  -- ./nqp/gradlew -p nqp clean buildJvm
```

Expected: `EXIT=0`. Baseline to compare: 256 s at milestone 5. Record
the seconds in the ledger.

- [ ] **Step 4: Build Rakudo from the top**

```bash
raku tools/build/watched-run.raku \
  --log=$CLAUDE_JOB_DIR/tmp/m6-make.log \
  --show-file=$CLAUDE_JOB_DIR/tmp/m6-make.markers \
  --show='Compiling' --show='Stage' \
  -- make
```

Expected: `EXIT=0`. Baselines to compare: CORE.c 464 s, parse 352.4 s,
optimize 36.6 s.

**Which `make` figure you compare against depends on what you ran.**
Milestone 5 recorded two: **1054 s** for `make` after a clean nqp build
(incremental), and **1133 s** for `make clean && make`, measured twice,
with an identical CORE.c parse of 352 s. Compare clean to clean and
incremental to incremental. Record in the ledger WHICH you ran, in
words, next to the number.

If the build fails, the two unbuilt encoder commits are the first
suspects. Repairing that is inside this task; record the diagnosis and
the fix in the ledger and amend rather than opening a new task.

- [ ] **Step 5: Record the baseline numbers**

From `m6-make.log`, extract the `Stage parse`, `Stage optimize` and
total lines for CORE.c, plus the whole-make wall clock. Write a table
into the ledger:

| clock | milestone 5 | milestone 6 baseline |
|---|---|---|
| nqp clean buildJvm | 256 s | |
| make, `make clean && make` | 1133 s | |
| make, incremental after a clean nqp | 1054 s | n/a this milestone |
| CORE.c total | 464 s | |
| CORE.c parse | 352.4 s | |
| CORE.c optimize | 36.6 s | |

- [ ] **Step 6: Gate — sanity**

```bash
RAKUDO_RAKUAST=1 raku tools/build/evalserver-sweep.raku --chunk=25 --jobs=1 --heap=8 t/01-sanity
```

Expected: 25 files, 0 failures. `--chunk=25` is the total file count, so
no server is replaced mid-run.

- [ ] **Step 7: Gate — the nqp suite**

```bash
raku tools/build/watched-run.raku \
  --log=$CLAUDE_JOB_DIR/tmp/m6-nqp-suite.log \
  --show-file=$CLAUDE_JOB_DIR/tmp/m6-nqp-suite.markers \
  --show='Failed' \
  -- ./nqp/gradlew -p nqp testNqp
```

`testNqp` is the task that runs the 151-file nqp suite (t/nqp, t/hll,
t/qregex, t/p5regex, t/qast, t/jvm, t/serialization, t/nativecall).
Plain `test` is Gradle's Java and Kotlin unit-test task and is NOT this
gate.

Expected: the nine known reds and no others — `t/jvm/01-continuations`
3/22, `t/jvm/11-dispatch` 20/160, `t/nqp/021` 6/33, `t/nqp/022` 1/7,
`t/nqp/044` 1/62, `t/nqp/112` 2/26, `t/p5regex` 3/182, `t/qast`
175/184, `t/qregex` 21/845. Any tenth red stops the milestone; diagnose
before continuing.

- [ ] **Step 8: Gate — the jar census**

```bash
raku tools/build/jar-census.raku nqp/build/jvm/share/lib/*.jar
```

Expected: every jar reported `unit.meta`-only, zero `.class`.

- [ ] **Step 9: Commit the ledger**

```bash
git add docs/superpowers/plans/2026-09-12-jvm-milestone-6-compiler-workload.ledger.md
GIT_AUTHOR_DATE="2026-09-12 19:00:00 +0200" GIT_COMMITTER_DATE="2026-09-12 19:00:00 +0200" \
  git commit -m "M6 Task 1: the clean build at HEAD is the milestone baseline

The tree's build products predated two encoder commits (nqp 7e7aaca61,
df564ddbb), which need a clean buildJvm because the stage graph misses
that edge. Numbers in the ledger; they replace milestone 5's.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01T8zpD6QrhN6Pmp5TePheq6"
```

---

### Task 2: The compilation-trace summarizer

**Files:**
- Create: `tools/build/truffle-trace-summary.raku`
- Create: `tools/build/t/truffle-trace-summary.rakutest`
- Create: `tools/build/t/fixtures/trace-sample.log`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `raku tools/build/truffle-trace-summary.raku <log>` printing
  a report, and the line `min-too-large-size=<N>` which Task 4 reads to
  choose `NQP_CODE_MAX_COMPILE`. If no root failed with "code is too
  large", it prints `min-too-large-size=none`.

**Background on the format.** `-Dpolyglot.engine.TraceCompilation=true`
emits one line per compilation event. These two lines are verbatim from
this tree on 2026-09-12:

```
[engine] opt done   engine=1  id=34    org.graalvm.polyglot.Value<Program>.execute        |Tier 1|Time    72(  63+9   )ms|AST    3|Inlined   0Y   0N|IR    309/   639|CodeSize    3948|Addr 0x7f0412473f00|CompId 2010   |UTC 2026-09-12T09:47:49.972|Src n/a
[engine] opt done   engine=1  id=2     <anon>[0]                                          |Tier 1|Time    37(  31+6   )ms|AST    2|Inlined   0Y   0N|IR    103/   184|CodeSize     711|Addr 0x7f041246c280|CompId 2011   |UTC 2026-09-12T09:47:49.972|Src n/a
```

Note `<anon>[0]`: `NqpRootNode.getName()` returns the block name with
the program's wire-word count appended in brackets
(`nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java:91-93`),
so every trace line already carries the size. A root with no bracket
(the polyglot entry above) is not an NQP program.

**Parse field-driven, not position-driven.** Split the tail on `|` and
match each field by its leading word (`Tier`, `Time`, `Reason`, ...).
The `opt failed` line's exact field order is NOT verified here — only
the `Reason ` field name is relied on — and Task 3 Step 4 confirms it
against a real failing trace.

- [ ] **Step 1: Write the fixture**

Create `tools/build/t/fixtures/trace-sample.log` with exactly these six
lines (the first two verbatim from a real run, the third and fourth
exercising failure and deoptimization, the fifth and sixth noise the
parser must ignore):

```
NOTE: Picked up JDK_JAVA_OPTIONS: -Dpolyglot.engine.TraceCompilation=true
[engine] opt done   engine=1  id=34    org.graalvm.polyglot.Value<Program>.execute        |Tier 1|Time    72(  63+9   )ms|AST    3|Inlined   0Y   0N|IR    309/   639|CodeSize    3948|Addr 0x7f0412473f00|CompId 2010   |UTC 2026-09-12T09:47:49.972|Src n/a
[engine] opt done   engine=1  id=2     <anon>[0]                                          |Tier 1|Time    37(  31+6   )ms|AST    2|Inlined   0Y   0N|IR    103/   184|CodeSize     711|Addr 0x7f041246c280|CompId 2011   |UTC 2026-09-12T09:47:49.972|Src n/a
[engine] opt failed engine=1  id=77    parse_stmt[48213]                                  |Tier 2|Time  6400(6100+300 )ms|Reason code installation failed: code is too large|UTC 2026-09-12T09:47:56.100|Src n/a
[engine] opt failed engine=1  id=78    parse_expr[91002]                                  |Tier 2|Time  6600(6300+300 )ms|Reason code installation failed: code is too large|UTC 2026-09-12T09:47:57.100|Src n/a
ok - warm add
```

- [ ] **Step 2: Write the failing tests**

Create `tools/build/t/truffle-trace-summary.rakutest`:

```raku
use Test;

my $tool = $*PROGRAM.parent(2).add('truffle-trace-summary.raku');
my $fix  = $*PROGRAM.parent.add('fixtures/trace-sample.log');

plan 8;

my $out = run($*EXECUTABLE, $tool, $fix, :out).out.slurp(:close);

ok  $out.contains('done=2'),   'counts the two successful compilations';
ok  $out.contains('failed=2'), 'counts the two failed compilations';
nok $out.contains('ok - warm add'),
    'ignores lines that are not engine trace lines';
ok  $out.contains('code installation failed: code is too large'),
    'groups failures by their reason text';
ok  $out ~~ / 'min-too-large-size=48213' /,
    'reports the smallest wire size among too-large roots';
ok  $out.contains('parse_expr'),
    'names the roots in the top-roots table';
ok  $out ~~ / 'mean=6500' /,
    'reports the mean time of a reason group in ms';

my $empty = $*PROGRAM.parent.add('fixtures/empty.log');
$empty.spurt('');
my $out2 = run($*EXECUTABLE, $tool, $empty, :out).out.slurp(:close);
ok $out2.contains('min-too-large-size=none'),
   'says none when no root failed for size';
$empty.unlink;
```

- [ ] **Step 3: Run the tests to verify they fail**

```bash
raku tools/build/t/truffle-trace-summary.rakutest
```

Expected: FAIL, because `truffle-trace-summary.raku` does not exist yet.

- [ ] **Step 4: Write the summarizer**

Create `tools/build/truffle-trace-summary.raku`:

```raku
#!/usr/bin/env raku

# Summarizes a Truffle compilation trace (-Dpolyglot.engine.TraceCompilation=true).
#
# A trace line looks like:
#   [engine] opt done   engine=1  id=2  <anon>[0]  |Tier 1|Time  37(  31+6 )ms|...
# The root name carries the program's wire-word count in brackets, because
# NqpRootNode.getName() appends it. Fields after the name are split on '|'
# and matched by their leading word, never by position, so a field order
# change in a future GraalVM does not silently mis-parse.

sub MAIN($log, Int :$top = 20) {
    my @events;
    for $log.IO.lines -> $line {
        next unless $line.starts-with('[engine] opt ');
        my ($head, @fields) = $line.split('|');
        $head ~~ / ^ '[engine] opt ' $<verb>=(\S+) \s+ 'engine=' \d+ \s+ 'id=' \d+ \s+ $<name>=(.+?) \s* $ /
            or next;
        # Read both captures BEFORE any further match: the next ~~ replaces
        # $/, and $<verb> would then resolve against the wrong match.
        my $verb = ~$<verb>;
        my $name = ~$<name>;
        my $size = $name ~~ / '[' $<n>=(\d+) ']' $ / ?? +$<n> !! Int;
        my %f;
        for @fields -> $f {
            my $t = $f.trim;
            %f<tier>   = +$0 if $t ~~ / ^ 'Tier' \s+ (\d+) /;
            %f<ms>     = +$0 if $t ~~ / ^ 'Time' \s+ (\d+) /;
            %f<reason> = ~$0 if $t ~~ / ^ 'Reason' \s+ (.+) $ /;
        }
        @events.push: {
            :$verb, :$name, :$size,
            tier => %f<tier> // 0, ms => %f<ms> // 0,
            reason => %f<reason> // '',
        };
    }

    my %by-verb = @events.classify(*<verb>);
    say "events=@events.elems()";
    say "$_=%by-verb{$_}.elems()" for %by-verb.keys.sort;

    my @failed = @events.grep(*<verb> eq 'failed');
    if @failed {
        say "\n--- failures by reason ---";
        for @failed.classify(*<reason>).sort(-*.value.elems) -> $g {
            my $mean = ($g.value.map(*<ms>).sum / $g.value.elems).round;
            say "  count={ $g.value.elems }  mean={ $mean }ms  { $g.key }";
        }
    }

    my @too-large = @failed.grep({ .<reason>.contains('code is too large') && .<size>.defined });
    say "\nmin-too-large-size={ @too-large ?? @too-large.map(*<size>).min !! 'none' }";

    say "\n--- top $top roots by compile time ---";
    for @events.sort(-*<ms>).head($top) -> $e {
        say sprintf('  %7dms  %-6s  tier %d  %s', $e<ms>, $e<verb>, $e<tier>, $e<name>);
    }

    say "\ntotal-compiler-ms={ @events.map(*<ms>).sum }";
}
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
raku tools/build/t/truffle-trace-summary.rakutest
```

Expected: PASS, 8/8.

- [ ] **Step 6: Smoke it on a real short workload with a positive marker**

```bash
JDK_JAVA_OPTIONS='-Dpolyglot.engine.TraceCompilation=true' \
java --module-path nqp/build/jvm/share/truffle \
  --add-modules org.graalvm.truffle,org.graalvm.truffle.runtime \
  --enable-native-access=org.graalvm.truffle --sun-misc-unsafe-memory-access=allow \
  -cp "nqp/build/jvm/share/runtime/nqp-runtime.jar:nqp/build/jvm/share/runtime/nqp-truffle.jar:nqp/build/jvm/share/runtime/kotlin-stdlib-2.4.10.jar:nqp/build/jvm/share/runtime/fastutil-8.5.19.jar:nqp/build/jvm/share/runtime/annotations-13.0.jar:nqp/build/jvm/share/runtime/lz4-java-1.8.0.jar" \
  org.raku.nqp.truffle.NqpCheck > $CLAUDE_JOB_DIR/tmp/m6-smoke-trace.log 2>&1
raku tools/build/truffle-trace-summary.raku $CLAUDE_JOB_DIR/tmp/m6-smoke-trace.log
```

Required positive marker: `done=` with a count above zero. If the
summarizer reports `events=0`, the instrument is broken; fix it before
Task 3, and never start a long run behind a silent instrument.

- [ ] **Step 7: Commit**

```bash
git add tools/build/truffle-trace-summary.raku tools/build/t/
GIT_AUTHOR_DATE="2026-09-12 19:20:00 +0200" GIT_COMMITTER_DATE="2026-09-12 19:20:00 +0200" \
  git commit -m "Tools: summarize a Truffle compilation trace

Field-driven parse (split on '|', match each field by its leading word)
so a field-order change in a later GraalVM cannot mis-parse silently.
Reports min-too-large-size, which is what chooses NQP_CODE_MAX_COMPILE.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01T8zpD6QrhN6Pmp5TePheq6"
```

---

### Task 3: The traced CORE.c baseline

**Files:**
- Modify: none
- Ledger: the baseline row of the configuration table

**Interfaces:**
- Consumes: `truffle-trace-summary.raku` from Task 2.
- Produces: the reference wall clock, stage times, failed-root count and
  `min-too-large-size` that Tasks 4 to 7 are judged against.

**The standalone compile.** Taken from the Makefile's own recipe
(`Makefile:1312`), with `--output` redirected so `blib` keeps the built
state:

```bash
RAKUDO_RAKUAST=1 perl rakudo-j-build \
  --setting=NULL.c --ll-exception --optimize=3 --target=jar --stagestats \
  --output=$CLAUDE_JOB_DIR/tmp/m6-corec.jar \
  gen/jvm/CORE.c.setting
```

- [ ] **Step 1: Run the traced baseline compile**

```bash
JDK_JAVA_OPTIONS='-Dpolyglot.engine.TraceCompilation=true -Dpolyglot.engine.CompilationStatistics=true' \
NQP_CODE_CLOSE_AT_EXIT=1 RAKUDO_RAKUAST=1 \
raku tools/build/watched-run.raku \
  --log=$CLAUDE_JOB_DIR/tmp/m6-corec-baseline.log \
  --show-file=$CLAUDE_JOB_DIR/tmp/m6-corec-baseline.markers \
  --show='Stage' \
  -- perl rakudo-j-build --setting=NULL.c --ll-exception --optimize=3 \
       --target=jar --stagestats \
       --output=$CLAUDE_JOB_DIR/tmp/m6-corec.jar gen/jvm/CORE.c.setting
```

`CompilationStatistics` prints only with `NQP_CODE_CLOSE_AT_EXIT=1`.
Expected: `EXIT=0`, roughly 464 s.

- [ ] **Step 2: Summarize the trace**

```bash
raku tools/build/truffle-trace-summary.raku $CLAUDE_JOB_DIR/tmp/m6-corec-baseline.log
```

- [ ] **Step 3: Record the baseline row**

Write into the ledger and into the findings doc's table: wall clock,
`Stage parse` and `Stage optimize` seconds, `events`, `done`, `failed`,
the failure groups with counts and means, `min-too-large-size`, and
`total-compiler-ms`. Reference figures from the 2026-09-07 trace: 1880 s
of compiler time, 114 roots failing "code is too large" at a mean 6.4 s
each, 733 s wasted on them.

- [ ] **Step 4: Confirm the failure-line format**

**The real format is now known, not assumed.** Task 2's review
decompiled `TraceCompilationListener` from this tree's own
`nqp/build/jvm/share/truffle/truffle-runtime-25.2.4.jar`. Its
`FAILED_FORMAT` is verbatim:

```
opt failed engine=%-2d id=%-5d %-50s |Tier %d|Time %18s|Reason: %s|UTC %s|Src %s
```

Note `|Reason: %s|` **with a colon**, where `DEOPT_FORMAT`, `INV_FORMAT`
and `UNQUEUED_FORMAT` use `|Reason %s` without one. The colon falls on
exactly the verb this milestone depends on. Task 2's parser was
corrected to accept both, and its fixture now carries a real-format
line.

This step is therefore a confirmation, not a repair:

```bash
grep -m2 'opt failed' $CLAUDE_JOB_DIR/tmp/m6-corec-baseline.log
```

Confirm the reason text parses — the summarizer must report a non-empty
reason group, not an empty one. **If `min-too-large-size` prints `none`
while the failed count is above zero, STOP.** That combination is the
signature of a parse miss, not of a compile without oversized roots, and
the tool now prints `(failed=N, reasons-parsed=0)` beside it to say so.
Do not proceed to Task 4 behind it; a `none` read as "nothing was too
large" would silently skip the milestone's largest lever. Record the
outcome either way.

- [ ] **Step 5: Confirm named Sources reach the statistics**

The engine merge named Sources per block. Confirm the statistics block
shows real names rather than a single `nqp-code`:

```bash
grep -A20 'Compilation Statistics' $CLAUDE_JOB_DIR/tmp/m6-corec-baseline.log | head -30
```

Record the answer in the ledger. This closes a follow-up the engine
merge deferred to the perf session.

- [ ] **Step 6: Commit the ledger and the findings doc skeleton**

```bash
git add docs/jvm-perf-findings-2026-09.md docs/superpowers/plans/2026-09-12-jvm-milestone-6-compiler-workload.ledger.md
GIT_AUTHOR_DATE="2026-09-12 19:40:00 +0200" GIT_COMMITTER_DATE="2026-09-12 19:40:00 +0200" \
  git commit -m "M6 Task 3: the traced CORE.c baseline

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01T8zpD6QrhN6Pmp5TePheq6"
```

---

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

> **Carried into Tasks 5, 6 and 7 from Task 4's review — read before
> measuring.** Every remaining sweep compile inherits
> `NQP_CODE_MAX_COMPILE=2069`, and therefore inherits what it does to the
> engine's own statistics. `prepareForCompilation` answering false is a
> RETRYABLE bailout, not a permanent one, so a refused root is
> resubmitted indefinitely. Task 4's run recorded
> `RetryableBailoutException: Compilable not ready for compilation` at
> **1456361**, against **144** in the baseline, and `Compilations` at
> **1462534** against **6358**.
>
> Two working rules follow:
>
> - **Never compare `Compilations` or `Compilation Accuracy` across
>   configurations.** Those fields are dominated by resubmissions in
>   every run from Task 4 onward and measure nothing you want.
> - **Use `total-compiler-ms`, `nqp-root-ms`, `done` and `failed`
>   instead**, which count real compilations and are unaffected.
>
> The knob still won on the quantities that matter, so it is carried;
> but a later task reading a freed-capacity story into its own result
> should remember that capacity here is churned, not freed. The proper
> fix — marking a size-refused root permanently non-compilable — is a
> runtime change and belongs to milestone 7.

### Task 5: Knob 2 — `engine.PartialBlockCompilation`

Where Task 4 refuses a big root outright, this splits it. The two are
alternatives, so this compile runs with Task 4's threshold **removed**.
If both help, Task 11 combines them.

**Interfaces:**
- Consumes: Task 4's verdict.
- Produces: a keep-or-drop verdict for partial block compilation.

- [ ] **Step 1: Probe the option set**

```bash
JDK_JAVA_OPTIONS='-Dpolyglot.engine.PartialBlockCompilation=true' \
java --module-path nqp/build/jvm/share/truffle \
  --add-modules org.graalvm.truffle,org.graalvm.truffle.runtime \
  --enable-native-access=org.graalvm.truffle --sun-misc-unsafe-memory-access=allow \
  -cp "nqp/build/jvm/share/runtime/nqp-runtime.jar:nqp/build/jvm/share/runtime/nqp-truffle.jar:nqp/build/jvm/share/runtime/kotlin-stdlib-2.4.10.jar:nqp/build/jvm/share/runtime/fastutil-8.5.19.jar:nqp/build/jvm/share/runtime/annotations-13.0.jar:nqp/build/jvm/share/runtime/lz4-java-1.8.0.jar" \
  org.raku.nqp.truffle.NqpCheck
```

Required positive marker: `nqp-code check passed`. A rejected option
prints a `PolyglotImpl.buildEngine` stack trace instead; that is the
whole point of probing.

- [ ] **Step 2: One compile**

`NQP_CODE_MAX_COMPILE` is deliberately **not set** here, so the big
roots are split rather than refused:

```bash
JDK_JAVA_OPTIONS='-Dpolyglot.engine.TraceCompilation=true -Dpolyglot.engine.CompilationStatistics=true -Dpolyglot.engine.PartialBlockCompilation=true' \
NQP_CODE_CLOSE_AT_EXIT=1 RAKUDO_RAKUAST=1 \
raku tools/build/watched-run.raku \
  --log=$CLAUDE_JOB_DIR/tmp/m6-corec-partialblock.log \
  --show-file=$CLAUDE_JOB_DIR/tmp/m6-corec-partialblock.markers \
  --show='Stage' \
  -- perl rakudo-j-build --setting=NULL.c --ll-exception --optimize=3 \
       --target=jar --stagestats \
       --output=$CLAUDE_JOB_DIR/tmp/m6-corec.jar gen/jvm/CORE.c.setting
```

- [ ] **Step 3: Summarize and decide**

```bash
raku tools/build/truffle-trace-summary.raku $CLAUDE_JOB_DIR/tmp/m6-corec-partialblock.log
```

Record the row. Keep whichever of Task 4 and Task 5 gave the lower wall
clock; if both beat the baseline, carry both forward and say so.

- [ ] **Step 4: Commit the ledger**

```bash
git add docs/superpowers/plans/2026-09-12-jvm-milestone-6-compiler-workload.ledger.md
GIT_AUTHOR_DATE="2026-09-12 20:20:00 +0200" GIT_COMMITTER_DATE="2026-09-12 20:20:00 +0200" \
  git commit -m "M6 Task 5: PartialBlockCompilation measured

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01T8zpD6QrhN6Pmp5TePheq6"
```

---

### Task 6: Knob 3 — tier policy

Four options, measured as one configuration because they express a
single policy: compile run-once code less eagerly.

```
-Dpolyglot.engine.Mode=latency
-Dpolyglot.engine.MultiTier=true
-Dpolyglot.engine.FirstTierCompilationThreshold=<default x 4>
-Dpolyglot.engine.LastTierCompilationThreshold=<default x 4>
```

There is no `engine.CompilationThreshold`; naming it is the usual
mistake.

**Interfaces:**
- Consumes: the winning configuration from Tasks 4 and 5.
- Produces: a keep-or-drop verdict for tier policy.

- [ ] **Step 1: Read the defaults**

```bash
java --module-path nqp/build/jvm/share/truffle \
  --add-modules org.graalvm.truffle,org.graalvm.truffle.runtime \
  -XX:+UseJVMCICompiler -Dpolyglot.engine.Help=true -version 2>&1 | grep -i 'TierCompilationThreshold'
```

Record the printed defaults in the ledger, then use four times each. If
the help output does not name them, use 1000 and 10000 and record that
these are chosen values, not multiples of an observed default.

- [ ] **Step 2: Probe the option set**

Run the NqpCheck probe from Task 5 Step 1 with all four options in
`JDK_JAVA_OPTIONS`. Required positive marker: `nqp-code check passed`.

- [ ] **Step 3: One compile**

Carry every knob Tasks 4 and 5 kept, and add the four tier options.
Written out with a kept `NQP_CODE_MAX_COMPILE`; drop that prefix if Task
4 dropped it, and drop `PartialBlockCompilation` if Task 5 dropped it:

```bash
NQP_CODE_MAX_COMPILE=<N-1> \
JDK_JAVA_OPTIONS='-Dpolyglot.engine.TraceCompilation=true -Dpolyglot.engine.CompilationStatistics=true -Dpolyglot.engine.PartialBlockCompilation=true -Dpolyglot.engine.Mode=latency -Dpolyglot.engine.MultiTier=true -Dpolyglot.engine.FirstTierCompilationThreshold=<value> -Dpolyglot.engine.LastTierCompilationThreshold=<value>' \
NQP_CODE_CLOSE_AT_EXIT=1 RAKUDO_RAKUAST=1 \
raku tools/build/watched-run.raku \
  --log=$CLAUDE_JOB_DIR/tmp/m6-corec-tier.log \
  --show-file=$CLAUDE_JOB_DIR/tmp/m6-corec-tier.markers \
  --show='Stage' \
  -- perl rakudo-j-build --setting=NULL.c --ll-exception --optimize=3 \
       --target=jar --stagestats \
       --output=$CLAUDE_JOB_DIR/tmp/m6-corec.jar gen/jvm/CORE.c.setting
```

Write the exact command you ran into the ledger, since the carried set
is what makes this configuration reproducible.

- [ ] **Step 4: Summarize and decide**

```bash
raku tools/build/truffle-trace-summary.raku $CLAUDE_JOB_DIR/tmp/m6-corec-tier.log
```

Record the row and the verdict. Expect the `done` count to fall and
`total-compiler-ms` with it; the wall clock is what decides.

- [ ] **Step 5: Commit the ledger**

```bash
git add docs/superpowers/plans/2026-09-12-jvm-milestone-6-compiler-workload.ledger.md
GIT_AUTHOR_DATE="2026-09-12 20:40:00 +0200" GIT_COMMITTER_DATE="2026-09-12 20:40:00 +0200" \
  git commit -m "M6 Task 6: tier policy measured

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01T8zpD6QrhN6Pmp5TePheq6"
```

---

### Task 7: Knob 4 — `engine.CompilerThreads`

The 2026-09-07 profile found Truffle compiler threads at 61 % of all CPU
samples and JVMCI at 14 %, against the main thread's 17 %. This box has
16 cores.

**Interfaces:**
- Consumes: the winning configuration from Tasks 4 to 6.
- Produces: the final shipping configuration, which Task 11 adopts.

- [ ] **Step 1: Confirm the core count**

```bash
nproc
```

Use half of it. Record both numbers.

- [ ] **Step 2: Probe the option set**

NqpCheck probe with `-Dpolyglot.engine.CompilerThreads=<cores/2>` added
to the winning set. Required positive marker: `nqp-code check passed`.

- [ ] **Step 3: One compile**

Carry every knob Tasks 4 to 6 kept and add the thread count. Written out
with all of them kept; drop whichever their tasks dropped:

```bash
NQP_CODE_MAX_COMPILE=<N-1> \
JDK_JAVA_OPTIONS='-Dpolyglot.engine.TraceCompilation=true -Dpolyglot.engine.CompilationStatistics=true -Dpolyglot.engine.PartialBlockCompilation=true -Dpolyglot.engine.Mode=latency -Dpolyglot.engine.MultiTier=true -Dpolyglot.engine.FirstTierCompilationThreshold=<value> -Dpolyglot.engine.LastTierCompilationThreshold=<value> -Dpolyglot.engine.CompilerThreads=<cores/2>' \
NQP_CODE_CLOSE_AT_EXIT=1 RAKUDO_RAKUAST=1 \
raku tools/build/watched-run.raku \
  --log=$CLAUDE_JOB_DIR/tmp/m6-corec-threads.log \
  --show-file=$CLAUDE_JOB_DIR/tmp/m6-corec-threads.markers \
  --show='Stage' \
  -- perl rakudo-j-build --setting=NULL.c --ll-exception --optimize=3 \
       --target=jar --stagestats \
       --output=$CLAUDE_JOB_DIR/tmp/m6-corec.jar gen/jvm/CORE.c.setting
```

- [ ] **Step 4: Summarize and decide**

```bash
raku tools/build/truffle-trace-summary.raku $CLAUDE_JOB_DIR/tmp/m6-corec-threads.log
```

Record the row and the verdict.

**This is the last compile of the sweep.** Per the user's rule, the
configuration in force here is the shipping configuration and there is
no confirmation build. State explicitly in the ledger which knobs are in
force at this point, as a single copy-pastable line; Task 11 adopts
exactly that.

- [ ] **Step 5: Commit the ledger**

```bash
git add docs/superpowers/plans/2026-09-12-jvm-milestone-6-compiler-workload.ledger.md
GIT_AUTHOR_DATE="2026-09-12 21:00:00 +0200" GIT_COMMITTER_DATE="2026-09-12 21:00:00 +0200" \
  git commit -m "M6 Task 7: CompilerThreads measured; the sweep's final configuration

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01T8zpD6QrhN6Pmp5TePheq6"
```

---

### Task 8: The cold-start profiler and profile

**Files:**
- Create: `tools/build/jfr-summary.raku`
- Create: `tools/build/t/jfr-summary.rakutest`
- Create: `tools/build/t/fixtures/jfr-sample.txt`

**Interfaces:**
- Consumes: the adopted configuration from Task 7.
- Produces: `raku tools/build/jfr-summary.raku <printed jfr text>`
  printing samples per thread, samples per load-path stage with
  percentages, and the top leaf frames.

**Background on the format.** `jfr print --events jdk.ExecutionSample
--stack-depth N` emits blocks. These are verbatim from this tree on
2026-09-12:

```
jdk.ExecutionSample {
  startTime = 11:48:43.157 (2026-09-12)
  sampledThread = "main" (javaThreadId = 3)
  state = "STATE_RUNNABLE"
  stackTrace = [
    java.lang.invoke.LambdaForm.prepare() line: 761
    java.lang.invoke.MethodHandle.<init>(MethodType, LambdaForm) line: 484
    java.lang.invoke.BoundMethodHandle.<init>(MethodType, LambdaForm) line: 52
    ...
  ]
}
```

The first frame inside `stackTrace = [` is the leaf.

- [ ] **Step 1: Write the fixture**

Create `tools/build/t/fixtures/jfr-sample.txt` with three blocks, all in
the shape above, all on `sampledThread = "main"`, differing only in
their leaf frame. The three leaves exercise the three outcomes of
`stage-of`:

| block | leaf frame | expected stage |
|---|---|---|
| 1 | `java.lang.invoke.LambdaForm.prepare() line: 761` (verbatim, with the two frames below it from the capture above) | `jvm-warmup` |
| 2 | `org.raku.nqp.runtime.unit.UnitFormat.readMeta(ByteBuffer) line: 210` | `meta-decode` |
| 3 | `org.raku.nqp.runtime.Ops.hllize(Object) line: 42` | `other` |

Block 3 is what proves an unrecognised frame is filed rather than
dropped. Without it the `other` assertion below passes or fails by
accident, since block 1's leaf matches `jvm-warmup`.

- [ ] **Step 2: Write the failing tests**

Create `tools/build/t/jfr-summary.rakutest`:

```raku
use Test;

my $tool = $*PROGRAM.parent(2).add('jfr-summary.raku');
my $fix  = $*PROGRAM.parent.add('fixtures/jfr-sample.txt');

plan 6;

my $out = run($*EXECUTABLE, $tool, $fix, :out).out.slurp(:close);

ok $out.contains('samples=3'),        'counts all three sample blocks';
ok $out.contains('main'),             'names the sampled thread';
ok $out.contains('UnitFormat.readMeta'),
   'keeps the leaf frame of the second sample';
ok $out.contains('meta-decode'),
   'maps UnitFormat.readMeta to the meta-decode stage';
ok $out.contains('jvm-warmup'),
   'maps a java.lang.invoke leaf to the jvm-warmup stage';
ok $out.contains('other'),
   'files an unrecognised leaf under other';
```

- [ ] **Step 3: Run the tests to verify they fail**

```bash
raku tools/build/t/jfr-summary.rakutest
```

Expected: FAIL, the tool does not exist.

- [ ] **Step 4: Write the summarizer**

Create `tools/build/jfr-summary.raku`:

```raku
#!/usr/bin/env raku

# Summarizes `jfr print --events jdk.ExecutionSample --stack-depth N` output.
#
# A block looks like:
#   jdk.ExecutionSample {
#     sampledThread = "main" (javaThreadId = 3)
#     stackTrace = [
#       <leaf frame>
#       ...
#     ]
#   }
# The first frame after `stackTrace = [` is the leaf, which is what a
# flat profile attributes the sample to.

# Order matters: the first match wins, so the specific patterns come
# before the broad ones. nfg-grapheme and engine-run sit above
# jvm-warmup deliberately -- Grapheme.nextBoundary lives under
# jdk.internal, and would otherwise be filed as JVM warm-up when it is
# nothing of the kind.
my @STAGES =
    'zip-read'      => / 'UnitZip' | 'ZipFile' | 'Inflater' /,
    'lz4'           => / 'LZ4' | 'lz4' /,
    'meta-decode'   => / 'UnitFormat.readMeta' | 'UnitFormat' /,
    'unit-tables'   => / 'ProgramUnit.buildTable' | 'ProgramUnit' /,
    'deserialize'   => / 'SerializationReader' | 'deserialize' /,
    'cu-init'       => / 'initializeCompilationUnit' | 'CompilationUnit' /,
    'engine-parse'  => / 'NqpLanguage.parse' | 'CodeEngine' /,
    'nfg-grapheme'  => / 'Grapheme' | 'BreakIterator' | 'Normalizer' /,
    'engine-run'    => / 'NqpRootNode' | 'continueAt' | 'BytecodeNode' /,
    'truffle-jit'   => / 'OptimizedCallTarget' | 'TruffleCompiler' | 'jdk.graal' /,
    'jvm-warmup'    => / 'java.lang.invoke' | 'jdk.internal' /,
    ;

sub stage-of($frame) {
    for @STAGES -> $p { return $p.key if $frame ~~ $p.value }
    'other'
}

sub MAIN($printed, Int :$top = 20) {
    my (@samples, $thread, $in-stack, $leaf);
    for $printed.IO.lines -> $line {
        if $line.trim.starts-with('jdk.ExecutionSample') {
            $thread = '?'; $in-stack = False; $leaf = Str;
        }
        elsif $line ~~ / 'sampledThread = "' $<t>=(<-["]>+) '"' / {
            $thread = ~$<t>;
        }
        elsif $line ~~ / 'stackTrace = [' / { $in-stack = True }
        elsif $in-stack && !$leaf.defined && $line.trim ne ']' {
            $leaf = $line.trim;
            @samples.push: { :$thread, :$leaf, stage => stage-of($leaf) };
            $in-stack = False;
        }
    }

    say "samples={ @samples.elems }";
    return unless @samples;

    say "\n--- by thread ---";
    for @samples.classify(*<thread>).sort(-*.value.elems) -> $g {
        say sprintf('  %6d  %5.1f%%  %s', $g.value.elems,
                    100 * $g.value.elems / @samples.elems, $g.key);
    }

    say "\n--- by stage ---";
    for @samples.classify(*<stage>).sort(-*.value.elems) -> $g {
        say sprintf('  %6d  %5.1f%%  %s', $g.value.elems,
                    100 * $g.value.elems / @samples.elems, $g.key);
    }

    say "\n--- top $top leaf frames ---";
    for @samples.classify(*<leaf>).sort(-*.value.elems).head($top) -> $g {
        say sprintf('  %6d  %s', $g.value.elems, $g.key);
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
raku tools/build/t/jfr-summary.rakutest
```

Expected: PASS, 5/5.

- [ ] **Step 6: Smoke it on a real recording with a positive marker**

```bash
RAKUDO_RAKUAST=1 RAKUDO_JVM_XOPTS="-XX:StartFlightRecording=filename=$CLAUDE_JOB_DIR/tmp/m6-smoke.jfr,settings=profile" \
  ./rakudo-j -e 'say 1'
jfr print --events jdk.ExecutionSample --stack-depth 8 $CLAUDE_JOB_DIR/tmp/m6-smoke.jfr \
  > $CLAUDE_JOB_DIR/tmp/m6-smoke-jfr.txt
raku tools/build/jfr-summary.raku $CLAUDE_JOB_DIR/tmp/m6-smoke-jfr.txt
```

Required positive marker: `samples=` with a count above zero. If it
reports zero, fix the parser before profiling for real.

- [ ] **Step 7: Profile cold start under the adopted configuration**

Re-run Step 6's recording with Task 7's winning options in
`RAKUDO_JVM_XOPTS` alongside the recording option, writing to
`$CLAUDE_JOB_DIR/tmp/m6-cold.jfr`, then print and summarize to
`$CLAUDE_JOB_DIR/tmp/m6-cold-summary.txt`. Also time it:

```bash
RAKUDO_RAKUAST=1 time ./rakudo-j -e 'say 1'
```

Reference: 4.10 s cold, 3.77 s with compilation off.

- [ ] **Step 8: Check the attribution before trusting it**

If the `other` stage exceeds 40 % of samples, the stage table is missing
whatever actually dominates and the ranking built on it would be
fiction. Read the top leaf frames, add the missing patterns to
`@STAGES`, re-run the summarizer on the same recording (no new run
needed), and commit the extended table. Only then rank.

**A preview, from validating the summarizer against a real 4-second
recording of `./rakudo-j -e 'say 1'` on 2026-09-12 (252 samples, so
indicative only):**

| stage | share |
|---|---|
| other | 33.3 % |
| nfg-grapheme | 29.4 % |
| engine-run | 22.2 % |
| jvm-warmup | 6.0 % |
| deserialize | 4.0 % |
| lz4 | 2.0 % |
| cu-init | 1.6 % |
| truffle-jit | 0.8 % |
| zip-read, meta-decode | 0.4 % each |

The top leaf was `jdk.internal.util.regex.Grapheme.nextBoundary` at 46
samples, with `GraphemeBreakIterator.setText` at 17 more. If the real
profile confirms it, the cold-start story is the grapheme layer and the
engine's own interpretation, NOT the artifact load path the spec
expected to find. Treat the artifact-load levers as a hypothesis this
step tests rather than one it confirms.

- [ ] **Step 9: Rank the load-path levers**

From the stage table, write a ranked list into the findings doc: lazy
meta decode per block, lazy `CodeRef` and `StaticCodeInfo` tables,
memory-mapped or streamed `unit.programs`, a smaller serialized context,
and class-data sharing. For each, name the stage share that justifies
its rank, and say plainly if a lever's stage turned out to be
negligible. If the grapheme finding above holds, add the levers it
implies and rank them where the numbers put them. **No code changes in
this task.**

- [ ] **Step 10: Commit**

```bash
git add tools/build/jfr-summary.raku tools/build/t/ docs/jvm-perf-findings-2026-09.md docs/superpowers/plans/2026-09-12-jvm-milestone-6-compiler-workload.ledger.md
GIT_AUTHOR_DATE="2026-09-12 21:20:00 +0200" GIT_COMMITTER_DATE="2026-09-12 21:20:00 +0200" \
  git commit -m "Tools, M6 Task 8: a JFR execution-sample summarizer, and the cold-start profile

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01T8zpD6QrhN6Pmp5TePheq6"
```

---

### Task 9: The green t/ subset, warm and cold

Subset: `t/01-sanity` (25 files), `t/06-telemetry` (4),
`t/13-experimental` (9, `.rakutest` extension), `t/07-pod-to-text` (2).
40 files, all green in milestone 3's sweep 2.

**Interfaces:**
- Consumes: the adopted configuration from Task 7.
- Produces: the start-up share of the test clock, and the milestone's
  first data point against the 30-minute `t/` gate.

- [ ] **Step 1: Warm, through one eval server**

```bash
RAKUDO_RAKUAST=1 raku tools/build/evalserver-sweep.raku \
  --chunk=40 --jobs=1 --heap=8 \
  t/01-sanity t/06-telemetry t/13-experimental t/07-pod-to-text \
  2>&1 | tee $CLAUDE_JOB_DIR/tmp/m6-subset-warm.log
```

`--chunk=40` is the total file count, so one server runs all 40 and none
is replaced. Record the total seconds and the five slowest files.

- [ ] **Step 2: Cold**

```bash
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku \
  --log=$CLAUDE_JOB_DIR/tmp/m6-subset-cold.log \
  --log-dir=$CLAUDE_JOB_DIR/tmp/m6-subset-cold-logs \
  --show-file=$CLAUDE_JOB_DIR/tmp/m6-subset-cold.markers \
  -t=t/01-sanity -t=t/06-telemetry -t=t/13-experimental -t=t/07-pod-to-text \
  --jobs=3 -- ./rakudo-j -Ilib
```

Per-file elapsed comes from the per-file logs' `=== EXIT ... elapsed=Ns
===` lines. Record the total.

- [ ] **Step 3: Compute and record the split**

`(cold total - warm total) / 40`, against the cold-start figure from
Task 8 Step 7. That quotient is the share of the test clock that is
start-up. Record it in the findings doc, and state what it implies for
the 30-minute gate: the last full `t/` sweep was 420 files in 6039 s and
the target is 1800 s, so a 3.3x reduction is needed.

- [ ] **Step 4: Commit the ledger and findings**

```bash
git add docs/jvm-perf-findings-2026-09.md docs/superpowers/plans/2026-09-12-jvm-milestone-6-compiler-workload.ledger.md
GIT_AUTHOR_DATE="2026-09-12 21:40:00 +0200" GIT_COMMITTER_DATE="2026-09-12 21:40:00 +0200" \
  git commit -m "M6 Task 9: the green subset, warm and cold; the start-up share of the test clock

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01T8zpD6QrhN6Pmp5TePheq6"
```

---

### Task 10: The loop baseline and the slowEvals question

Milestone 5 left one unexplained number: on the plusquick road
`slowEvals` went 364 to 976 with every other dispatch counter identical,
and plusquick went 82.625 to 85.525 ns/op, a 3.5 % regression. The
milestone 5 spec assigned it to this session.

**Interfaces:**
- Consumes: the adopted configuration from Task 7.
- Produces: the hot-loop baseline, and either an explanation of the
  `slowEvals` jump or a written statement that it was not found and what
  was ruled out.

- [ ] **Step 1: The loop bench**

```bash
RAKUDO_RAKUAST=1 NQP_DISPATCH_STATS=1 ./rakudo-j docs/bench/jesp/plusquick.raku
```

Record ns/op and the dispatch-stats line (folded hits, misses, boundary
invokes, `slowEvals`). Reference: 85.525 ns/op, `hits=90247539
misses=11614 slowEvals=976`.

- [ ] **Step 2: The correctness smoke**

```bash
RAKUDO_RAKUAST=1 ./rakudo-j docs/bench/jesp/resume-smoke.raku
```

Its output must not change. This is a correctness check, not a
benchmark.

- [ ] **Step 3: Chase the slowEvals jump**

`slowEvals` counts dispatch evaluations that fell off the folded road.
The counter tripled while hits and misses held, so the suspects are the
milestone 5 layout sites rather than dispatch itself. Two concrete
leads, both recorded as open in the milestone 5 ledger:

1. `DecontSite` never calls `miss()` on a layout mismatch, so a
   mismatching site may be re-evaluating slowly without registering a
   miss. Read `DecontSite` and check whether a mismatch path reaches the
   slow evaluator without incrementing `misses`.
2. `BigIntSite` does not re-verify `rd.layout === layout`.

Time-box this to one hour of investigation. If neither lead explains it,
write what was ruled out and leave it open; an unexplained 3.5 % is a
finding, not a blocker.

- [ ] **Step 4: Record and commit**

Write the numbers and the `slowEvals` verdict into the findings doc.
```bash
git add docs/jvm-perf-findings-2026-09.md docs/superpowers/plans/2026-09-12-jvm-milestone-6-compiler-workload.ledger.md
GIT_AUTHOR_DATE="2026-09-12 22:00:00 +0200" GIT_COMMITTER_DATE="2026-09-12 22:00:00 +0200" \
  git commit -m "M6 Task 10: the loop baseline, and the slowEvals question

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01T8zpD6QrhN6Pmp5TePheq6"
```

---

### Task 11: Adopt the configuration and write the findings

**Files:**
- Modify: `tools/lib/NQP/Config/Rakudo.pm:400-407`
- Modify: `tools/templates/jvm/rakudo-j-build.in`
- Modify: `tools/build/create-jvm-runner.pl:215`
- Modify: `tools/build/evalserver-sweep.raku:34,67,111`
- Modify: `docs/jvm-perf-findings-2026-09.md`

**Interfaces:**
- Consumes: the shipping configuration line from Task 7 Step 4.
- Produces: the adopted defaults and the ranked lever list that
  milestone 7 inherits.

**Two adoption mechanisms, not one.** Polyglot options are system
properties and travel in the `j_truffle_*` config strings and `$jopts`.
`NQP_CODE_MAX_COMPILE` is an environment variable read once by
`NqpRootNode`'s static initializer, so it travels as an `$ENV{...}`
assignment or an exported variable instead.

- [ ] **Step 1: Adopt the build-side polyglot options**

In `tools/lib/NQP/Config/Rakudo.pm`, append each adopted
`-Dpolyglot.engine.X=Y` to both strings, keeping the two forms in step:

```perl
            my $perf_opts = "'-Dpolyglot.engine.X=Y', ";
            my $perf_args = "-Dpolyglot.engine.X=Y";
            $config->{'j_truffle_opts'} =
              "'--module-path', '$truffle_mp', '--add-modules', '$truffle_am', $quiet_opts$perf_opts";
            $config->{'j_truffle_args'} =
              "--module-path $truffle_mp --add-modules $truffle_am $quiet_args $perf_args";
```

Above the assignment, write a comment naming the measurement that
justified it: the wall clock before, the wall clock after, and the task
number.

- [ ] **Step 2: Adopt the build-side environment knob**

Only if Task 4 kept it. In `tools/templates/jvm/rakudo-j-build.in`,
beside the existing `RAKUDO_HOME` assignment:

```perl
$ENV{NQP_CODE_MAX_COMPILE} = '<N-1>';
```

With a comment naming Task 4's numbers.

- [ ] **Step 3: Decide the runtime side separately**

For each adopted knob, state in the findings doc whether it is adopted
for the runtime too. The rule: a knob that skips compiling a root helps
the build and costs runtime, because a root that never compiles never
speeds up. Only add to `$jopts` in
`tools/build/create-jvm-runner.pl:215` what the runtime should carry,
and say in a comment why.

- [ ] **Step 4: Fix the sweep script's stale guidance**

In `tools/build/evalserver-sweep.raku`, rewrite the `--chunk` help text
(line 34), the default (line 67) and the "lower --chunk" message (line
111). The leak that motivated server replacement was fixed in nqp
`4c7f652ea`; every replacement now costs a warm JIT state for nothing.
Make the default the total file count and keep `--chunk` available for
someone who wants N servers. Update the file-head comment block that
explains the old reasoning.

- [ ] **Step 5: Verify the adoption took**

```bash
perl Configure.pl --backends=jvm --gen-nqp
grep -n 'polyglot.engine' Makefile rakudo-j-build rakudo-j
```

Expected: the adopted options appear in the regenerated runners. This is
a regeneration, not a rebuild; it does not invalidate any measurement.

- [ ] **Step 6: Write the findings doc**

`docs/jvm-perf-findings-2026-09.md` must contain:

1. The configuration table: one row per compile (baseline, Tasks 4-7)
   with wall clock, `Stage parse`, `Stage optimize`, `done`, `failed`,
   `total-compiler-ms`, and the verdict.
1a. **The measurement caveats, stated once and prominently**, because
   every row inherits them:
   - **There is no noise floor.** Forward-only means one sample per
     configuration and no repeats, so a small wall-clock delta cannot be
     distinguished from run-to-run drift. Task 1's and Task 3's figures
     do not supply one either, being different configurations. Where a
     verdict rests on something other than the clock, say what.
   - **`total-compiler-ms` and `nqp-root-ms` are the trustworthy
     quantities.** They are wall-clock-independent and, in Task 4, moved
     an order of magnitude further than the wall did.
   - **"The delta lives in Stage parse" is not evidence.** Parse is 77 %
     of the wall and is where essentially all compilation happens, so any
     wall change lands there a priori.
   - **A knob may redistribute rather than remove work.** Task 4
     suppressed 178 compiles and the total compile count barely moved
     (`done`+`failed` 6100 to 6078), so treating a later knob as pure
     subtraction would be wrong.
   - **Task 4's threshold is sensitive, not merely arbitrary.** 2069 sits
     directly beneath `PERFORM-BEGIN[2085]`, the second-largest
     contributor at 43 s over 26 compiles; a threshold of 2100 brings it
     back. The gated population is only 29 unique roots, dominated by
     recompilation churn.
2. The three clocks: CORE.c, cold start with its stage table, the green
   subset warm and cold with the start-up split, and the loop bench.
3. The ranked lever list milestone 7 inherits. For each lever: which
   clock it moves, the measured or estimated gain, and its cost
   (configuration, runtime-only code, stage build, or RakuAST).
4. A statement that these numbers describe the **pre-rebase** tree.
5. **The BOOTSTRAP v6c clock, named and left unmeasured on purpose.**
   Task 1 found it at 398 s of the 1122 s build, 35 %, second only to
   CORE.c's parse and not on this milestone's measurement list. The
   sweep's knobs are build-wide, so BOOTSTRAP receives them without
   being measured, and no adopted knob was chosen against it. Record the
   number, say plainly that it was not measured, and name it as
   milestone 7's leading candidate.
6. **A statement of what the build graph does not express.** No rakudo
   target lists an nqp artifact as a prerequisite, so a rebuilt nqp is
   invisible to `make`. Any future measurement that changes nqp must run
   `Configure.pl` and `make clean` first, or it measures the old nqp.
7. **Milestone 7's lead lever, framed correctly.** Task 3 found 442 of
   444 compilation bailouts are one phenomenon: Graal inlining slow paths
   that never execute, until it gives up on inlining depth, leaving those
   roots interpreted for the whole compile. Chain A (238 roots) enters at
   `NqpTypeOps.create` -> `VMArray.allocate` ->
   `ExceptionHandling.dieInternal`, whose `printStackTrace` sits behind an
   environment flag. Chain B (204 roots) enters at `NqpOps.getattr:1482`
   and `bindattr:1517`, where the JDK constructs a wrong-method-type
   exception message. Nothing throws; this is speculation.

   Three corrections that must travel with it, all established by Task
   3's review and all easy to get wrong:

   - **Frame it as "slow paths visible to the inliner", NOT as "env-gated
     debug prints".** Chain B, the larger per-root cost, has no env gate
     at all. The env-gating rule is not the culprit and must not be
     softened: a survey of all 35 `System.getenv` sites in the runtime
     found every one except `GlobalContext.kt:287` is already a `val` or
     `static final`, hence foldable. That one mutable instance flag is an
     outlier, not a pattern.
   - **The fix is `@TruffleBoundary`, not a constant.** Folding the flag
     removes only the print branch; the rest of `dieInternal`, its
     40-frame `StringBuilder` walk and its `VMExceptionInstance`
     construction, stays inlinable. A boundary removes the whole slow
     path regardless of receiver constancy. Hoisting the flag to
     `static final` is a cheap complement, not an alternative — and note
     that `@CompilationFinal` on the instance field would be a no-op,
     because `tc` comes off the frame so `tc.gc` is never a
     partial-evaluation constant.
   - **The survey worth running:** `nqp/src/vm/jvm/runtime` contains
     **zero** `@TruffleBoundary` annotations, against 113 in
     `nqp/nqp-truffle/src`. That entire older tree is called from Truffle
     nodes with every slow path fully visible to the inliner. Chain A is
     simply the first one anyone measured. Six inline `System.getenv()`
     calls on runtime paths are worse in kind, since a `getenv` in a
     compiled graph cannot fold at all: `Ops.kt:6834`, `Ops.kt:9026`,
     `UnitWriter.kt:33`, `NqpPolyglot.kt:54`, `NqpCodeEngine.java:93`.

- [ ] **Step 7: Commit**

```bash
git add tools/ docs/jvm-perf-findings-2026-09.md docs/superpowers/plans/2026-09-12-jvm-milestone-6-compiler-workload.ledger.md
GIT_AUTHOR_DATE="2026-09-12 22:20:00 +0200" GIT_COMMITTER_DATE="2026-09-12 22:20:00 +0200" \
  git commit -m "M6 Task 11: adopt the sweep's configuration; the findings doc

Adoption is per-site: a knob that skips compiling a huge root helps the
build and costs runtime, so build-side and runtime-side are separate
decisions and the findings doc says which clock each moved.

Also rewrites evalserver-sweep.raku's --chunk guidance, which dated from
the leak fixed in nqp 4c7f652ea; a replaced server discards a warm JIT
state for nothing.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01T8zpD6QrhN6Pmp5TePheq6"
```

---

## Phase B: the ahead-of-time spike

### Task 12: Native Image of nqp alone

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

### Task 13: The tabled question on `native`-trait signature immutability

Your question from 2026-09-11, never answered: would a rule that a
callable with the `native` trait cannot have its signature rewritten
dynamically, raising a runtime error if tried, give the closed set of
foreign-function descriptor shapes that an image needs at build time?

**Interfaces:**
- Consumes: Task 12's findings about what the image build demands.
- Produces: a written answer in the findings doc and an update to the
  `native-image-aot-direction` memory.

- [ ] **Step 1: Read the two call sites**

```bash
grep -n 'downcallHandle\|upcallStub\|FunctionDescriptor' nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/NativeCallOps.kt | head -20
sed -n '330,350p' lib/NativeCall.rakumod
```

The known shape: handles are built at run time at `NativeCallOps.kt:96`,
`:418` and `:669` from a `FunctionDescriptor` assembled at `:662`, with
an upcall stub at `:1111`, and `lib/NativeCall.rakumod`'s `!setup`
(:338) computes the call lazily at first call.

- [ ] **Step 2: Answer the question in writing**

The answer must address three things explicitly, and say which are
settled by evidence and which remain judgement:

1. Whether the descriptor shapes are derivable at compile time given the
   immutability rule, or whether something else still makes them
   runtime-valued.
2. What the rule would forbid that people do today, and whether any
   in-tree use would break.
3. Whether a fixed shape set plus trampolines, or a libffi-style
   universal path, is the better fallback for shapes that stay dynamic.

Write it into the findings doc under its own heading.

- [ ] **Step 3: Update memory**

Update
`/home/longwalker/.claude/projects/-home-longwalker-code-raku-x-core-rakudo/memory/native-image-aot-direction.md`:
replace the "Tabled question" paragraph with the answer and the
recommendation, and update its `description` line.

- [ ] **Step 4: Commit**

The memory file lives outside the repository, so only the findings doc
and the ledger are committed here:

```bash
git add docs/jvm-perf-findings-2026-09.md docs/superpowers/plans/2026-09-12-jvm-milestone-6-compiler-workload.ledger.md
GIT_AUTHOR_DATE="2026-09-12 22:50:00 +0200" GIT_COMMITTER_DATE="2026-09-12 22:50:00 +0200" \
  git commit -m "M6 Task 13: the answer on native-trait signature immutability

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01T8zpD6QrhN6Pmp5TePheq6"
```

---

## Phase C: the close

### Task 14: Rebase, re-gate, push, record

**Files:**
- Modify: `docs/jvm-truffle-only-plan.md:35` (the item 4 row)
- Modify: `docs/jvm-pr-stack.md`
- Modify: the memory files named below

**Interfaces:**
- Consumes: everything above.
- Produces: both trees on their upstream mains, pushed, with the plan
  position and the pull-request stack current.

- [ ] **Step 1: Record the pre-rebase heads**

```bash
git log --oneline -1
git -C nqp log --oneline -1
git rev-list --count HEAD..origin/main
```

Write all three into the ledger. Every Phase A number describes this
state and must be labelled so in the findings doc.

- [ ] **Step 2: Rebase nqp first**

```bash
git -C nqp fetch upstream
git -C nqp rebase upstream/main
```

nqp is the dependency, so it goes first. Resolve conflicts; record each
non-trivial one in the ledger.

- [ ] **Step 3: Rebase rakudo**

```bash
git fetch origin main
git rebase origin/main
```

57 commits behind as of 2026-09-12, up from 21 at the engine-merge
close. Expect conflicts in `src/Raku/ast/` and the CORE setting sources.

- [ ] **Step 4: Rebuild and re-gate**

**`make` alone is not enough, and this is not a precaution.** Task 1
established that **no rakudo target lists any nqp artifact as a
prerequisite**, so a rebuilt nqp is invisible to make and a plain `make`
after an nqp change is a no-op that silently leaves the old nqp in
place. Task 1's own first attempt was exactly that: a 0-second `make`
that would have produced a baseline built against the previous nqp. The
rebase changes both trees, so the full sequence is required:

```bash
./nqp/gradlew -p nqp clean buildJvm
perl Configure.pl --backends=jvm --gen-nqp
make clean
raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/m6-rebase-build.log \
  --show-file=$CLAUDE_JOB_DIR/tmp/m6-rebase-build.markers --show='Compiling' -- make
RAKUDO_RAKUAST=1 raku tools/build/evalserver-sweep.raku --chunk=25 --jobs=1 --heap=8 t/01-sanity
./nqp/gradlew -p nqp testNqp
```

`Configure.pl` matters beyond the Makefile's own freshness: Task 1 found
the generated Makefile still listed the two ASM jars milestone 5 deleted
and omitted `nqp-truffle.jar`, which is the source of the stale
`rakudo-j-build` classpath. Regenerating fixes both.

Expected: `t/01-sanity` 25/25 and the nqp suite at its nine known reds.
A new red is a rebase regression; diagnose before pushing.

- [ ] **Step 5: Push both trees**

```bash
git -C nqp push --force-with-lease ab5tract jesp-direct-lazy-records
git push --force-with-lease ab5tract worktree-jesp-direct-lazy-records
```

Never push to main, never merge.

- [ ] **Step 6: Update the plan position**

In `docs/jvm-truffle-only-plan.md`, rewrite the item 4 row: what was
measured, which knobs were adopted, the CORE.c number before and after,
the spike's verdict, and what milestone 7 inherits. Follow the row style
of the other items, which carry their own history.

- [ ] **Step 7: Add the missing pull-request rows**

In `docs/jvm-pr-stack.md`, add rows for milestone 5, the engine merge
and milestone 6. The table currently stops at milestone 4. The going
rule is one pull request per milestone in each tree, nqp first.

- [ ] **Step 8: Update memory**

- `truffle-plan-position.md`: item 4 done, what remains.
- `perf-measure-first-plan.md`: the session ran; point at the findings
  doc.
- `native-image-aot-direction.md`: already updated in Task 13; add the
  spike's verdict.
- `engine-merge-one-language.md`: the not-rebased caveat is discharged.
- `MEMORY.md`: a new index line for milestone 6.

- [ ] **Step 9: Final commit and push**

```bash
git add docs/ 
GIT_AUTHOR_DATE="2026-09-12 23:00:00 +0200" GIT_COMMITTER_DATE="2026-09-12 23:00:00 +0200" \
  git commit -m "M6 closed: the compiler's own workload measured and adopted

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01T8zpD6QrhN6Pmp5TePheq6"
git push --force-with-lease ab5tract worktree-jesp-direct-lazy-records
```

---

## Done

Milestone 6 is closeable when a clean build at HEAD exists with recorded
numbers; the knob sweep has run and its winning configuration is adopted
at the sites that should carry it; `docs/jvm-perf-findings-2026-09.md`
carries the configuration table, the three clocks and the ranked lever
list; the spike has produced its recipe, its numbers or its reason, the
written answer on `native`-trait signature immutability, and a
recommendation; and both trees are rebased, re-gated, pushed, with the
pull-request stack current.
