# Milestone 7, Phase A: runtime levers — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking. Keep a ledger twin at
> `docs/superpowers/plans/2026-09-13-jvm-milestone-7-first-execution-phase-a.ledger.md`
> (project convention: every ruling, every deferred minor, every task
> verdict and every rig row goes in it as it happens, not at the end).

**Goal:** Land or strike the eight runtime levers of milestone 7's Phase A
(A1-A8), each with one forward-only measurement on a named rig, so that
Phase B (the format) starts from a measured baseline.

**Architecture:** Task 1 builds the rig (`tools/build/m7-rig.raku`: cold
`rakudo-j -e`, cold `nqp-j-gradle -e`, the dispatch counters, warm
`t/02-rakudo` on one eval server) and takes the base row. Tasks 2-8 are
one lever each, cheapest first, all runtime-jar rebuilds: presized SC
maps, the diagnostics, the dispatcher-callback engine entry, the stub-road
fast path, the record path off its hash maps, the classlib boundary plus
the targeted boundaries, and the dispatcher-compilation spike. Task 9 is
the static clone road, the one lever that needs a setting recompile, so it
goes last. Task 10 closes the phase: findings, plan position, memory,
push. The last rig row is Phase B's baseline; nothing is re-measured.

**Tech Stack:** NQP and Raku on the JVM; Oracle GraalVM 25.2.4 with
Truffle (Bytecode DSL); Kotlin for runtime code, Java only where the DSL
processor requires it (`NqpRootNode.java`, `NqpOps.java`,
`NqpProgramBuilder.java`); Raku for all tooling; Gradle for the nqp side;
GNU make for the Rakudo side.

**Spec:** `docs/superpowers/specs/2026-09-13-jvm-milestone-7-first-execution-design.md`
(rakudo `83375a77ae`). Phases B and C get their own plans, written at this
phase's close from its measurements (spec decision 5).

## Global Constraints

Every task's requirements implicitly include this section.

- **Work in the worktree, never the stale checkout.** The repository root
  for every path and command in this plan is
  `/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records`
  (rakudo branch `worktree-jesp-direct-lazy-records`; nested nqp branch
  `jesp-direct-lazy-records`).
- **Two git working trees.** The root is rakudo.git; `nqp/` is the nqp.git
  working tree nested inside it, gitignored, NOT a submodule.
  `git -C nqp ...` for that tree. Label every hash with its tree ("nqp
  `c17d93d27`" vs "rakudo `83375a77ae`"). Write nqp paths with the `nqp/`
  prefix. Run gradle from the root: `./nqp/gradlew -p nqp ...`, never via
  `cd`.
- **`RAKUDO_RAKUAST=1` on every build, test and run.** The Makefile exports
  it into its own recipes; nothing sets it for your own invocations.
- **`NQP_CODE_RUN` and `NQP_CODE_PRECOMP` must not be set at all.** The
  compiler dies on `=0`.
- **`java` must be Oracle GraalVM 25.2.4.** Verify with `java -version`
  before any measurement.
- **Runtime-jar rebuild** after any edit under `nqp/src/vm/jvm/runtime/` or
  `nqp/nqp-truffle/`: `./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar
  syncRuntimeJars` (about 5 s). No setting recompile. Restart any eval
  server afterwards. A `src/vm/jvm/QAST/*.nqp` edit needs
  `./nqp/gradlew -p nqp clean buildJvm` instead (Task 9 only).
- **Long builds and test runs go through `tools/build/watched-run.raku`**
  with `--log` and `--show`. Never hand-roll timestamp wrappers or
  tail-based monitors. `--show` takes a literal, repeatable; `--show-rx`
  takes a `/.../` regex only.
- **The eval-server sweep is silent until its chunk ends.** Launch it with
  `--stall` past the run (`--stall=7200`) and a `--max` ceiling
  (`--max=10800`), or watched-run's default 900 s watchdog kills it.
- **Never replace an eval server mid-sweep.** Pass the total file count as
  `--chunk` (t/02-rakudo: 306) with `--jobs=1`.
- **Benchmark runs use the stock runners**, `./rakudo-j` from the root and
  `./nqp-j-gradle` with cwd `nqp/`, never the eval server (it exports
  `Compilation=false` to its children). `nqp/nqp-j` does not exist in this
  worktree; `nqp-j-gradle` is the same runner with absolute paths.
- **One measurement per lever, forward only.** A lever's rig row is taken
  once, with every earlier lever in. A lever whose row shows nothing is
  struck and recorded; nothing is reverted to re-measure. A lever that
  regresses either clock is reverted in a follow-up commit and recorded as
  struck with both numbers.
- **A rig row costs about 90 minutes** (the warm `t/02-rakudo` sweep is
  5205 s at the milestone-5 close; the cold parts are under 3 minutes).
  Start it as a plain background job through watched-run and monitor its
  log every 90 s or more, never more often.
- **Runtime performance outranks compile time.** Task 9 reports CORE.c in
  passing; it is never a gate.
- **Tooling in Raku**, never Python or shell. Tests for tools live in
  `tools/build/t/*.rakutest`, run as `raku tools/build/t/<name>.rakutest`,
  locating the tool via `$*PROGRAM.parent(2)` and fixtures via
  `$*PROGRAM.parent.add('fixtures')`, and running the tool as a child with
  `run($*EXECUTABLE, $tool, ..., :out)`.
- **Every diagnostic env-gated**: `nqp::say(...) if
  nqp::getenvhash()<AN_ENVVAR>;` in NQP/Raku sources, `System.getenv(...)`
  in runtime code. Never a bare print. Counters live behind
  `NqpDispatch.STATS` (`NQP_DISPATCH_STATS`).
- **Smoke-test every instrument on a short workload and require a
  positive marker** before any long run (`unit-load: stats on`,
  `dispatch stats:`, `m7-rig: DONE`). Abort a long run whose marker never
  appears.
- **Kotlin, never Java**, for new code, except inside the three DSL-bound
  Java files named above.
- **Subagents default to Opus.** Re-run on Fable only after erroneous
  output; log the escalation in the ledger.
- **Commits stamped in the evening of the date the work happened**,
  18:00-23:00: `STAMP="$(date +%F)T20:30:00+02:00"; GIT_AUTHOR_DATE=$STAMP
  GIT_COMMITTER_DATE=$STAMP git commit ...`; step the minute for a second
  commit the same evening.
- **Commit trailer on every commit, both trees:**
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_01GK4DKrQFQgNaiYirUzjcgJ`.
- **The in-tree runners have no installed module repo**: anything with a
  `use` needs `-Ilib`.
- **No `t/spec`** in this milestone (gated on whole `t/` under 30 minutes;
  last measured 5078 s).
- **Gates before a task lands, in cost order** (spec "Gates"): the nqp
  suite `raku tools/build/evalserver-sweep.raku --suite=nqp '--chunk=*'`
  154 files green; `perl t/harness5 --jvm --evalserver t/01-sanity` 25/25
  (a rakudo `make` first only when a task changed the compiler, Task 9);
  the rig row's warm `t/02-rakudo` red list has no file outside
  `docs/jvm-t02-rakudo-red-baseline.txt`.

## File Structure

Created:

| path | responsibility |
|---|---|
| `tools/build/m7-rig.raku` | the rig: cold rows, counters, warm sweep, baseline diff, one `rows.md` line per tag |
| `tools/build/t/m7-rig.rakutest`, `tools/build/t/fixtures/m7-cold.err`, `tools/build/t/fixtures/m7-sweep.log`, `tools/build/t/fixtures/m7-red-baseline.txt` | tests of the rig's two parsers |
| `docs/jvm-t02-rakudo-red-baseline.txt` | the milestone-5 red list for `t/02-rakudo` (22 files), the rig's reference |
| `docs/superpowers/plans/2026-09-13-jvm-milestone-7-first-execution-phase-a.ledger.md` | the ledger twin |
| `nqp/t/nqp/125-dispatch-stats.t` | the misses-by-dispatcher histogram has a test |
| `t/02-rakudo/closure-static-clone.t` | closure creation semantics under the static clone road |
| `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/SerializationContextTest.kt` | index caches presized from the header counts |

Modified (one line of responsibility each; exact lines in the tasks):

| path | what changes |
|---|---|
| `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationContext.kt` | A1: `initObjectList`/`initSTableList` presize the fastutil caches; new `initCodeRefList` |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationReader.kt` | A1: calls `initCodeRefList`, sizes `stableIndex` |
| `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt` | A2: `missesBy` histogram, `AttrSrc.slow` split counters |
| `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt` | A2: `decont` misses on a layout mismatch |
| `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java`, `NqpCodeEngine.java` | A2: root names carry the cuid |
| `tools/build/truffle-trace-summary.raku` (+ its test) | A2: captures `id=` and reports distinct ids vs names |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/StaticCodeInfo.kt`, `unit/ProgramUnit.kt` | A3: `unitEntry` flag |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt` | A3: `enterUnit`; A4: `invokeDirect` fast path; A5: helper sites keyed by identity |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/Dispatch.kt`, `DispatchBootstrap.kt`, `DispatchRegistry.kt` | A3: callbacks through `enterUnit`; A5: dispatcher cached on the site with a registry epoch |
| `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java`, `NqpRootNode.java` | A7: boundary on the classlib road behind `NQP_CLASSLIB_INLINE` |
| `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/ExceptionHandling.kt` | A7: `@TruffleBoundary` on `dieInternal` |
| `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NFGString.kt`, `NqpPolyglot.kt` | A7: boundary on `of`; the `NQP_BOUNDARY_CHECK` marker |
| `src/vm/jvm/runtime/org/raku/rakudo/RakOps.kt`, `src/vm/jvm/Raku/Ops.nqp` | A6: the `p6clonecode` op |
| `src/Raku/ast/code.rakumod` | A6: `IMPL-CLOSURE-QAST` and the throwaway-block fixup take the static road under `#?if jvm` |
| `docs/jvm-perf-findings-2026-09.md`, `docs/jvm-truffle-only-plan.md` | Task 10: the Phase A findings and position |

Facts every task relies on (from the 2026-09-13 surveys, current at rakudo
`83375a77ae` / nqp `c17d93d27`):

- `nqp-runtime` already has `compileOnly("org.graalvm.truffle:truffle-api:...")`
  (`nqp/nqp-runtime/build.gradle.kts:43`) for TruffleString; spec decision 7
  needs no build change. `NqpDeps.orderKey` only sees `runtimeClasspath`,
  so a compileOnly dependency is never rejected.
- `./rakudo-j` puts the runtime jars on `-cp`; `nqp-j-gradle` puts them on
  `-Xbootclasspath/a`. Whether an annotation in the runtime tree is visible
  to the compiler under each runner is verified by Task 7's marker, not
  assumed.
- `NQP_CODE_CALLSTATS` no longer exists (the spec's A8 wording is stale);
  the spike uses `NQP_CODE_TRACE=1` and `-Dpolyglot.engine.TraceCompilation=true`.
- The milestone-5 `t/02-rakudo` red list lives only in a job directory
  (`~/.claude/jobs/4bfdb802/tmp/base-red.txt`); Task 1 copies it into the
  tree.

---

## Task 1: The ledger, the red baseline, the rig, and the base row

**Files:**
- Create: `docs/superpowers/plans/2026-09-13-jvm-milestone-7-first-execution-phase-a.ledger.md`
- Create: `docs/jvm-t02-rakudo-red-baseline.txt`
- Create: `tools/build/m7-rig.raku`
- Create: `tools/build/t/m7-rig.rakutest`, `tools/build/t/fixtures/m7-cold.err`,
  `tools/build/t/fixtures/m7-sweep.log`, `tools/build/t/fixtures/m7-red-baseline.txt`

**Interfaces:**
- Consumes: `NQP_UNIT_LOAD_STATS=1` (marker `unit-load: stats on`, lines
  `unit-load <depth> <unit> <stage> <ms>`); `NQP_DISPATCH_STATS=1` (one
  stderr line `dispatch stats: hits=N misses=N ...` at exit, plus after
  Task 3 lines `  misses <count> <dispatcher>`); the sweep's stdout lines
  `<N> files in <S>s across <M> server(s)` and, for a failed chunk,
  `t/02-rakudo/<file>.t (Wstat: ...)`.
- Produces: `raku tools/build/m7-rig.raku --tag=T --out=DIR` writing
  `DIR/T-rakudo-e-run<i>.err`, `DIR/T-nqp-e-run<i>.err`, `DIR/T-sweep.log`,
  `DIR/T.md` (the row) and appending the same row to `DIR/rows.md`; stdout
  markers `m7-rig: cold rakudo-e best=<s>`, `m7-rig: cold nqp-e best=<s>`,
  `m7-rig: warm t/02-rakudo <S>s new-red=<n>`, `m7-rig: DONE tag=T`;
  parse modes `--parse-cold=FILE` and `--parse-sweep=FILE --baseline=FILE`
  for the tests. Every later task's "measure" step is
  `raku tools/build/m7-rig.raku --tag=<lever> --out=$CLAUDE_JOB_DIR/tmp/m7-rig`.

- [ ] **Step 1: Record the base in the ledger**

Create the ledger with the two HEAD hashes:

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records
R=$(git rev-parse --short=10 HEAD); N=$(git -C nqp rev-parse --short=9 HEAD)
cat > docs/superpowers/plans/2026-09-13-jvm-milestone-7-first-execution-phase-a.ledger.md <<LEDGER
# SDD ledger — plan: docs/superpowers/plans/2026-09-13-jvm-milestone-7-first-execution-phase-a.md

Spec: docs/superpowers/specs/2026-09-13-jvm-milestone-7-first-execution-design.md
(rakudo 83375a77ae). Plan committed in the same session.

BASE before Task 1: rakudo $R, nqp $N.

Model policy (user rule 2026-09-11): subagents on Opus; Fable only after
erroneous output.

Ruling: this committed ledger twin IS the ledger (milestones 4-6
convention). Rig rows are appended to the "Rig rows" table below as they
land, copied from \$CLAUDE_JOB_DIR/tmp/m7-rig/rows.md.

Ruling: commit stamps are the evening (18:00-23:00) of the date the work
happened ([[after-hours-commit-stamps]]).

## Rig rows

| tag | rakudo hash | nqp hash | cold rakudo-e (s) | cold nqp-e (s) | misses | hits | warm t/02-rakudo (s) | new red | verdict |
|---|---|---|---|---|---|---|---|---|---|

## Rulings and deferred minors

LEDGER
```

- [ ] **Step 2: Copy the milestone-5 red baseline into the tree**

```bash
{ printf '# t/02-rakudo files red at the milestone-5 close (job 4bfdb802 base-red.txt,\n# 22 files, 2026-09-12). The rig reports any red file NOT in this list as new.\n# Ruling 2026-09-12 (engine merge): 15-gh_1202.t and native-argument-snapshot.t\n# went green afterwards; they stay listed so a flicker is not a regression.\n'; cat ~/.claude/jobs/4bfdb802/tmp/base-red.txt; } > docs/jvm-t02-rakudo-red-baseline.txt
grep -c '^t/' docs/jvm-t02-rakudo-red-baseline.txt
```

Expected: `22`.

- [ ] **Step 3: Write the failing test for the rig's parsers**

`tools/build/t/fixtures/m7-cold.err`:

```
unit-load: stats on
unit-load 1 nqp.jar sc-read 210.40
unit-load 0 nqp.jar load-total 412.10
dispatch stats: hits=125055 misses=6815 slowEvals=12 invokes=7733 directs=3 noTarget=0 badExpectation=0 notCodeRef=0 byKind[value,syscall,mapped,invoke,resumable]=[100, 200, 300, 400, 500]
  misses 1473 lang-meth-call
  misses 1432 lang-call
  noTarget 0 nothing
1
```

`tools/build/t/fixtures/m7-sweep.log`:

```
rakudo: 306 files, 1 chunk(s) of 306, 1 server(s) x 8 GB
[5205s] chunk 1/1: FAIL

306 files in 5205s across 1 server(s)
1 of 1 chunks failed
--- chunk 1 (exit 1) ---
t/02-rakudo/03-cmp-ok.t (Wstat: 0 Tests: 7 Failed: 1)
t/02-rakudo/brand-new-red.t (Wstat: 0 Tests: 2 Failed: 1)
  Failed test:  2
```

`tools/build/t/fixtures/m7-red-baseline.txt`:

```
# fixture baseline
t/02-rakudo/03-cmp-ok.t
```

`tools/build/t/m7-rig.rakutest`:

```raku
use Test;

my $tool = $*PROGRAM.parent(2).add('m7-rig.raku');
my $fix  = $*PROGRAM.parent.add('fixtures');

plan 8;

my $cold = run($*EXECUTABLE, $tool, '--parse-cold=' ~ $fix.add('m7-cold.err'), :out).out.slurp(:close);
ok $cold.contains('misses=6815'),               'misses parsed from the stats line';
ok $cold.contains('hits=125055'),               'hits parsed from the stats line';
ok $cold.contains('lang-meth-call=1473'),        'per-dispatcher histogram line parsed';
ok $cold.contains('stage-lines=2'),              'unit-load stage lines counted';

my $sweep = run($*EXECUTABLE, $tool, '--parse-sweep=' ~ $fix.add('m7-sweep.log'),
                '--baseline=' ~ $fix.add('m7-red-baseline.txt'), :out).out.slurp(:close);
ok $sweep.contains('warm=5205'),                 'warm seconds parsed';
ok $sweep.contains('red=2'),                     'two red files found';
ok $sweep.contains('new-red=t/02-rakudo/brand-new-red.t'), 'the file outside the baseline is named';
ok !$sweep.contains('03-cmp-ok'),                'a baseline red is not new';
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `raku tools/build/t/m7-rig.rakutest`
Expected: the `run` fails to find `m7-rig.raku` (all 8 not ok, or a die
naming the missing tool).

- [ ] **Step 5: Write the rig**

`tools/build/m7-rig.raku`:

```raku
#!/usr/bin/env raku
# Milestone 7's measurement rig (spec Task 0): one row per lever.
#
#   raku tools/build/m7-rig.raku --tag=a1 --out=$CLAUDE_JOB_DIR/tmp/m7-rig
#
# Cold rows: best-of-N wall of ./rakudo-j -e 'say 1' (cwd root) and
# ./nqp-j-gradle -e 'say(1)' (cwd nqp/), stock runners, NQP_UNIT_LOAD_STATS
# and NQP_DISPATCH_STATS on, each run's merged output saved. Warm row: the
# whole t/02-rakudo directory on ONE eval server (chunk = file count), the
# red list diffed against docs/jvm-t02-rakudo-red-baseline.txt. Children get
# a closed stdin and merged output (inherited stdin hung under watched-run,
# 2026-09-13). Refuses to start with NQP_DISPATCH_RECORD set: a training run
# is never a measured run (spec, Phase C).
#
# Positive markers: 'unit-load: stats on' and 'dispatch stats:' in every
# cold run, 'm7-rig: DONE' at the end. A run without them dies.
use v6.d;
%*SUB-MAIN-OPTS = :named-anywhere;

subset Tag of Str where /^ <[\w-]>+ $/;

my $ROOT = $*PROGRAM.parent(2).absolute.IO;

sub parse-cold(Str $text) {
    my %r = :stage-lines(+$text.lines.grep(*.starts-with('unit-load '))), :by{};
    if $text ~~ / 'dispatch stats: hits=' (\d+) ' misses=' (\d+) / {
        %r<hits> = +$0; %r<misses> = +$1;
    }
    for $text.lines {
        %r<by>{$1} = +$0 if / ^ '  misses ' (\d+) ' ' (\S+) /;
    }
    %r
}

sub cold-summary(%r) {
    my @top = %r<by>.sort(-*.value).head(8).map({ .key ~ '=' ~ .value });
    "hits={%r<hits> // '-'} misses={%r<misses> // '-'} stage-lines={%r<stage-lines>} top: @top.join(' ')"
}

sub parse-sweep(Str $text, IO() $baseline) {
    my %base = $baseline.lines.grep(*.starts-with('t/')).map(* => True);
    my $warm = $text ~~ / (\d+) ' files in ' (\d+) 's across' / ?? +$1 !! Int;
    my @red  = $text.lines.map({ / ^ (t\/\S+) \s+ '(Wstat' / ?? ~$0 !! Empty }).unique;
    my @new  = @red.grep({ !%base{$_} });
    %( :$warm, :@red, :@new )
}

sub sweep-summary(%s) {
    "warm={%s<warm> // '-'} red={+%s<red>} new-red={%s<new>.join(',') || '-'}"
}

multi sub MAIN(Str :$parse-cold!) {
    say cold-summary(parse-cold($parse-cold.IO.slurp));
}

multi sub MAIN(Str :$parse-sweep!, Str :$baseline = 'docs/jvm-t02-rakudo-red-baseline.txt') {
    say sweep-summary(parse-sweep($parse-sweep.IO.slurp, $baseline));
}

multi sub MAIN(
    Tag  :$tag!,                #= row name: base, a1, a3 ...
    Str  :$out = 'm7-rig',      #= output directory
    Int  :$runs = 5,            #= cold runs per benchmark; best wall wins
    Bool :$warm = True,         #= also run warm t/02-rakudo (about 90 min)
    Int  :$heap = 8,            #= eval-server heap in GB
    Str  :$baseline = 'docs/jvm-t02-rakudo-red-baseline.txt',
) {
    die "m7-rig: NQP_DISPATCH_RECORD is set; a training run is never a measured run"
        if %*ENV<NQP_DISPATCH_RECORD>:exists;
    $*OUT.out-buffer = False;
    my $dir = $out.IO; $dir.mkdir;
    my %base = %*ENV, RAKUDO_RAKUAST => '1';
    my %cold = %base, NQP_UNIT_LOAD_STATS => '1', NQP_DISPATCH_STATS => '1';
    my @bench =
        %( :name<rakudo-e>, :cwd($ROOT),            :cmd(['./rakudo-j', '-e', 'say 1']) ),
        %( :name<nqp-e>,    :cwd($ROOT.add('nqp')), :cmd(['./nqp-j-gradle', '-e', 'say(1)']) );

    sub run-once(%b, $i) {
        my $t0 = now;
        my $p = run |%b<cmd>, :cwd(%b<cwd>), :in, :out, :merge, :env(%cold);
        $p.in.close;
        my $text = $p.out.slurp(:close);
        my $wall = now - $t0;
        $dir.add("$tag-%b<name>-run$i.err").spurt($text);
        die "%b<name> run$i: exit {$p.exitcode}" unless $p.exitcode == 0;
        die "%b<name> run$i: no 'unit-load: stats on' marker" unless $text.contains('unit-load: stats on');
        die "%b<name> run$i: no 'dispatch stats:' marker" unless $text.contains('dispatch stats:');
        note sprintf("m7-rig: %-9s run%d wall=%.3fs", %b<name>, $i, $wall);
        ($wall, $text)
    }

    my %row = :$tag, :hash-r(run('git', 'rev-parse', '--short=10', 'HEAD', :cwd($ROOT), :out).out.slurp(:close).trim),
              :hash-n(run('git', 'rev-parse', '--short=9', 'HEAD', :cwd($ROOT.add('nqp')), :out).out.slurp(:close).trim);
    for @bench -> %b {
        my @runs = (1..$runs).map: { run-once(%b, $_) };
        my $best = @runs.min(*[0]);
        %row{%b<name>} = $best[0];
        %row{%b<name> ~ '-stats'} = parse-cold($best[1]);
        say sprintf("m7-rig: cold %s best=%.3fs  all: %s  %s", %b<name>, $best[0],
                    @runs.map({ sprintf '%.2f', $_[0] }).join(' '), cold-summary(%row{%b<name> ~ '-stats'}));
    }

    my %sweep = :warm(Int), :red([]), :new([]);
    if $warm {
        my $n = +$ROOT.add('t/02-rakudo').dir(test => *.ends-with('.t'));
        my $p = run 'raku', 'tools/build/evalserver-sweep.raku', "--chunk=$n", '--jobs=1', "--heap=$heap",
                    't/02-rakudo', :cwd($ROOT), :in, :out, :merge, :env(%base);
        $p.in.close;
        my $text = $p.out.slurp(:close);
        $dir.add("$tag-sweep.log").spurt($text);
        %sweep = parse-sweep($text, $ROOT.add($baseline));
        say "m7-rig: warm t/02-rakudo {%sweep<warm> // '?'}s new-red={+%sweep<new>} " ~ sweep-summary(%sweep);
    }

    my $st = %row<rakudo-e-stats>;
    my $line = "| $tag | %row<hash-r> | %row<hash-n> | {sprintf '%.3f', %row<rakudo-e>} | {sprintf '%.3f', %row<nqp-e>} | "
             ~ "{$st<misses> // '-'} | {$st<hits> // '-'} | {%sweep<warm> // '-'} | {%sweep<new>.join(' ') || 'none'} | |";
    $dir.add("$tag.md").spurt($line ~ "\n");
    $dir.add('rows.md').spurt($line ~ "\n", :append);
    say $line;
    say "m7-rig: DONE tag=$tag";
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `raku tools/build/t/m7-rig.rakutest`
Expected: `1..8`, all ok.

- [ ] **Step 7: Smoke the rig on the short workload**

Run (cold only, one run each, about 30 s):

```bash
RAKUDO_RAKUAST=1 raku tools/build/m7-rig.raku --tag=smoke --runs=1 --/warm --out=$CLAUDE_JOB_DIR/tmp/m7-rig
```

Expected: two `m7-rig: cold ... best=` lines with `hits=` and `misses=`
non-empty, then `m7-rig: DONE tag=smoke`. If `misses=-`, the runtime jar
in use is not the one with `NqpDispatch.STATS`; stop and fix before any
long run.

- [ ] **Step 8: Commit the rig and the baseline**

```bash
git add tools/build/m7-rig.raku tools/build/t/m7-rig.rakutest tools/build/t/fixtures/m7-cold.err tools/build/t/fixtures/m7-sweep.log tools/build/t/fixtures/m7-red-baseline.txt docs/jvm-t02-rakudo-red-baseline.txt docs/superpowers/plans/2026-09-13-jvm-milestone-7-first-execution-phase-a.ledger.md
STAMP="$(date +%F)T19:00:00+02:00"; GIT_AUTHOR_DATE=$STAMP GIT_COMMITTER_DATE=$STAMP git commit -q -F - <<'MSG'
Tools: m7-rig, milestone 7's measurement rig, and the t/02-rakudo red baseline

Cold rakudo-e and nqp-e best-of-5 with the load and dispatch counters,
warm t/02-rakudo on one eval server diffed against the milestone-5 red
list (now in docs/, it lived only in a job directory), one row per tag.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01GK4DKrQFQgNaiYirUzjcgJ
MSG
```

- [ ] **Step 9: Take the base row (background, about 90 min)**

```bash
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/m7-rig-base.log \
    --show='m7-rig:' --stall=7200 --max=10800 -- \
    raku tools/build/m7-rig.raku --tag=base --out=$CLAUDE_JOB_DIR/tmp/m7-rig
```

Expected: `m7-rig: DONE tag=base` in the log; cold rakudo-e about 2.7 s,
cold nqp-e about 1.1 s, misses about 6815, warm about 5200 s, `new-red=0`.
Copy the `| base | ...` row into the ledger's Rig rows table with verdict
"base". If `new-red` names a file, rule on it in the ledger before Task 2
(a red outside the baseline at base is a pre-existing regression, not a
lever's).

---

## Task 2: A1 — presize the serialization context's index caches

**Files:**
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationContext.kt:66-135`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationReader.kt:62,92-110`
- Test: `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/SerializationContextTest.kt`

**Interfaces:**
- Consumes: `it.unimi.dsi.fastutil.objects.Object2IntOpenHashMap.ensureCapacity(int)`
  (present in fastutil 8.5.19, verified with `javap` 2026-09-13).
- Produces: `SerializationContext.initCodeRefList(entries: Int)`; the existing
  `initObjectList`/`initSTableList` now also presize their index caches.

The profile (spec Revision 2) put `Object2IntOpenHashMap.rehash` at 17 %
of the SC read and `HashMap.resize` at 6 %. The three fastutil caches
(`objectIndexCache`, `stableIndexCache`, `codeIndexCache`) start at the
default 16 slots and rehash their way up to CORE.c's tens of thousands of
entries. The per-STable method-cache `HashMap`s cannot be presized in
place: `deserializeSTableInner` captures the `VMHashInstance.storage`
object before the hash finishes, so replacing the map would strand the
STable. They are left alone and recorded as such.

- [ ] **Step 1: Write the failing test**

`nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/SerializationContextTest.kt`:

```kotlin
package org.raku.nqp.runtime

import org.raku.nqp.runtime.unit.BlockRec
import org.raku.nqp.runtime.unit.CallSiteRec
import org.raku.nqp.runtime.unit.LexValueRec
import org.raku.nqp.runtime.unit.ProgramUnit
import org.raku.nqp.runtime.unit.UnitMeta
import org.raku.nqp.runtime.unit.UnitRecord
import org.raku.nqp.sixmodel.SerializationContext
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertSame

class SerializationContextTest {
    /* The same one-block unit ProgramUnitTest builds: a real code ref needs
     * a real compilation unit. */
    private fun unit(): ProgramUnit {
        val block = BlockRec("<mainline>", null, -1, arrayOf("\$a"), arrayOf(), arrayOf(), arrayOf(),
            longArrayOf(0), false, false, "u.nqp", 1, 0, null, null, null, 0)
        val meta = UnitMeta("U1", "nqp", "h", "d", 1, 0, -1, 0, 0,
            listOf(CallSiteRec(byteArrayOf(1), null)), arrayOf(block),
            listOf(LexValueRec(0, "\$a", "h", 3, 0)), listOf())
        return ProgramUnit(UnitRecord(meta, arrayOf("p0"), byteArrayOf(), mapOf()))
    }

    @Test
    fun `initCodeRefList reserves the code ref slots without adding any`() {
        val u = unit()
        u.buildTable(null)
        val cr = u.qbidToCodeRef!![0]!!
        val sc = SerializationContext("test-sc")
        sc.initCodeRefList(4)
        assertEquals(0, sc.coderefCount())
        sc.addCodeRef(cr)
        assertEquals(1, sc.coderefCount())
        assertSame(cr, sc.getCodeRef(0))
    }
}
```

The `UnitMeta`/`BlockRec` argument lists are copied from
`ProgramUnitTest.unit()`; if that helper has changed, copy its current
form: the assertions are what matter.

- [ ] **Step 2: Run the test to verify it fails**

Run: `./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.runtime.SerializationContextTest' -q`
Expected: compilation error, `initCodeRefList` unresolved.

- [ ] **Step 3: Presize the caches**

In `SerializationContext.kt`, replace the two init methods and add the
third:

```kotlin
    fun initObjectList(entries: Int) {
        rootObjects.ensureCapacity(entries)
        objectIndexCache.ensureCapacity(entries)
        for (i in 0 until entries)
            rootObjects.add(null)
    }
```

```kotlin
    fun initSTableList(entries: Int) {
        rootStables.ensureCapacity(entries)
        stableIndexCache.ensureCapacity(entries)
        for (i in 0 until entries)
            rootStables.add(null)
    }
```

After `codeIndexCache`'s declaration (line 120):

```kotlin
    /** The reader knows the code ref count from the unit before it adds
     *  them one by one; reserving here spares the cache its rehashes. */
    fun initCodeRefList(entries: Int) {
        rootCodes.ensureCapacity(entries)
        codeIndexCache.ensureCapacity(entries)
    }
```

(`rootCodes` is an `ArrayList`; if it is declared otherwise, drop the
`rootCodes.ensureCapacity` line and keep the cache line.)

In `SerializationReader.kt`, before the `for (i in 0 until crCount)` loop
in `deserialize()` (line 106):

```kotlin
        sc.initCodeRefList(crCount)
```

and change line 62 so the reader's own identity map is sized once the
STable count is known:

```kotlin
    private lateinit var stableIndex: java.util.IdentityHashMap<STable, Int>
```

with, at the end of `checkAndDisectInput()` (the method that sets
`stTableEntries`), the line:

```kotlin
        stableIndex = java.util.IdentityHashMap(stTableEntries)
```

Check with `grep -n stableIndex SerializationReader.kt` that no use
precedes `checkAndDisectInput()`; `deserialize()` calls it first.

- [ ] **Step 4: Run the test to verify it passes, then the jar**

Run: `./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.runtime.SerializationContextTest' -q && ./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars -q`
Expected: test green, jars synced.

- [ ] **Step 5: Gates**

```bash
raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/a1-nqp-suite.log --show='files in' --stall=1200 -- \
    raku tools/build/evalserver-sweep.raku --suite=nqp '--chunk=*'
RAKUDO_RAKUAST=1 perl t/harness5 --jvm --evalserver t/01-sanity 2>&1 | tail -3
```

Expected: `154 files in ...` with no failed chunk; `All tests successful` /
25 files.

- [ ] **Step 6: Commit (nqp tree)**

```bash
git -C nqp add src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationContext.kt src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationReader.kt nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/SerializationContextTest.kt
STAMP="$(date +%F)T19:30:00+02:00"; GIT_AUTHOR_DATE=$STAMP GIT_COMMITTER_DATE=$STAMP git -C nqp commit -q -F - <<'MSG'
SC reader: presize the index caches from the header counts

The three fastutil object-to-index caches and the reader's STable
identity map started at default capacity and rehashed up to CORE.c's
counts on every load (rehash was 17 % of the SC read). The per-STable
method-cache HashMaps stay as they are: the STable captures the map
object before the hash finishes, so it cannot be replaced in place.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01GK4DKrQFQgNaiYirUzjcgJ
MSG
```

- [ ] **Step 7: Measure (background, about 90 min)**

```bash
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/m7-rig-a1.log \
    --show='m7-rig:' --stall=7200 --max=10800 -- \
    raku tools/build/m7-rig.raku --tag=a1 --out=$CLAUDE_JOB_DIR/tmp/m7-rig
```

Copy the row into the ledger; verdict "landed" if either cold clock moved
by more than the run-to-run spread of the base row's five runs, else
"struck (kept: harmless)". A1 is never reverted: it cannot regress.

---

## Task 3: A2 — the diagnostics that ride along

**Files:**
- Modify: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt:130-173,554-583,620-630`
- Modify: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt:245-270`
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java:68-100`
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpCodeEngine.java:74-84`
- Modify: `tools/build/truffle-trace-summary.raku:91`, `tools/build/t/truffle-trace-summary.rakutest`
- Create: `nqp/t/nqp/125-dispatch-stats.t`

**Interfaces:**
- Consumes: `NqpDispatch.STATS`, `count(AtomicLong)`; `NqpTypeOps.miss(site)`;
  `StaticCodeInfo.uniqueId` (the cuid); the trace line
  `[engine] opt <verb> engine=N id=N <name>[<size>] ...`.
- Produces: stats lines `  misses <count> <dispatcher>` (top 20) after the
  `dispatch stats:` line, and two new fields on that line,
  `slowLayout=N slowNull=N`; root names of the form `<name>@<cuid>[<size>]`;
  `truffle-trace-summary.raku` prints `distinct-ids=N distinct-names=M`.

No measurement is claimed for this task; its rig row exists so that the
next lever's comparison is against a tree with the new names in it (root
names change what TraceCompilation prints, nothing else).

- [ ] **Step 1: Write the failing nqp test for the histogram**

`nqp/t/nqp/125-dispatch-stats.t`:

```nqp
# NQP_DISPATCH_STATS=1 prints the dispatch counters at exit, with a
# misses-by-dispatcher histogram (milestone 7, A2). JVM only.
plan(4);

if nqp::getcomp('nqp').backend.name ne 'jvm' {
    skip('dispatch stats are a JVM/Truffle counter', 4);
}
else {
    my $err := 'dispatch-stats-125.err';
    my %env := nqp::getenvhash();
    %env<NQP_DISPATCH_STATS> := '1';
    nqp::shell(nqp::execname() ~ " -e 'say(1)' 2>$err", nqp::cwd(), %env);
    my $text := slurp($err);
    nqp::unlink($err);
    ok(nqp::index($text, 'dispatch stats: hits=') >= 0, 'the stats line is printed at exit');
    ok(nqp::index($text, ' misses=') >= 0,               'it carries the miss total');
    ok(nqp::index($text, "\n  misses ") >= 0,            'a per-dispatcher misses line follows it');
    ok(nqp::index($text, ' slowLayout=') >= 0,           'AttrSrc slow evaluations are split by cause');
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `(cd nqp && ./nqp-j-gradle t/nqp/125-dispatch-stats.t)` (a subshell, so the
tool shell's cwd does not drift).
Expected: tests 3 and 4 `not ok`.

- [ ] **Step 3: The histogram and the split counters**

In `NqpDispatch.kt`, in the counters block after `noTargetBy`:

```kotlin
    /** Misses by the dispatcher name the instruction was encoded with. */
    @JvmField val missesBy = ConcurrentHashMap<String, AtomicLong>()
    @JvmField val slowEvalsLayout = AtomicLong()
    @JvmField val slowEvalsNull = AtomicLong()
```

The shutdown hook's first `println` gains `" slowLayout=" + slowEvalsLayout +
" slowNull=" + slowEvalsNull` immediately after `notCodeRef`, and after
the `noTargetBy` loop:

```kotlin
            missesBy.entries.sortedByDescending { it.value.get() }.take(20)
                .forEach { System.err.println("  misses " + it.value + " " + it.key) }
```

Beside `count`:

```kotlin
    @TruffleBoundary
    private fun countBy(map: ConcurrentHashMap<String, AtomicLong>, key: String) {
        map.computeIfAbsent(key) { AtomicLong() }.incrementAndGet()
    }
```

In `miss`, replace `if (STATS) count(misses)` with:

```kotlin
        if (STATS) { count(misses); countBy(missesBy, name) }
```

In `AttrSrc`, replace `eval` and `slow`:

```kotlin
        override fun eval(tc: ThreadContext, args: Array<Any?>): Any? {
            val o = from.eval(tc, args)
            if (o is RakuObject && o.layout === layout) {
                val v: SixModelObject? = try {
                    getter.invokeExact(o as SixModelObject) as SixModelObject?
                } catch (t: Throwable) {
                    throw CompilerDirectives.shouldNotReachHere(t)
                }
                /* Null: not yet vivified (or genuinely null); the accessor
                 * decides which and vivifies. */
                if (v != null) return v
                return slow(tc, o, nullSlot = true)
            }
            return slow(tc, o, nullSlot = false)
        }

        @TruffleBoundary
        private fun slow(tc: ThreadContext, o: Any?, nullSlot: Boolean): Any? {
            if (STATS) {
                count(slowEvals)
                count(if (nullSlot) slowEvalsNull else slowEvalsLayout)
                val key = "slow attr " + name + " of " + (if (o == null) "null" else o.javaClass.name) +
                    " layout=" + (if (o is RakuObject) o.layout?.st?.debugName else "-") + " vs " + layout.st.debugName +
                    (if (nullSlot) " (null slot)" else "")
                if (seenSlow.add(key)) System.err.println("dispatch $key")
            }
            if (o == null)
                throw ExceptionHandling.dieInternal(tc,
                    "Dispatch program read an attribute of a null value")
            return ValueSource.readAttribute(tc, o as SixModelObject, classHandle, name, kind)
        }
```

- [ ] **Step 4: `decont` misses on a layout mismatch**

In `NqpTypeOps.decont`, replace the `if (st != null) { ... }` block:

```kotlin
            if (st != null) {
                if (ost === st) {
                    if (o is TypeObject) return o
                    val layout = site.layout
                    if (o is RakuObject && layout != null) {
                        if (o.layout === layout) {
                            val getter = site.getter
                            if (getter != null) {
                                val v: SixModelObject? = try {
                                    getter.invokeExact(o as SixModelObject) as SixModelObject?
                                } catch (t: Throwable) {
                                    throw CompilerDirectives.shouldNotReachHere(t)
                                }
                                /* Null: not yet vivified; the accessor decides. */
                                if (v != null) return v
                            }
                        }
                        else miss(site)   /* same STable, a variant layout: re-resolve or pin */
                    }
                }
                else miss(site)
            }
```

- [ ] **Step 5: Root names carry the cuid**

`NqpRootNode.java`, next to `blockName`:

```java
    /** The block's compilation-unit id, learned with its name; it keeps
     *  two blocks of one name and size apart in traces and statistics. */
    volatile String blockId;
```

and `getName()`:

```java
    @Override
    public String getName() {
        String n = blockName;
        String id = blockId;
        return (n == null || n.isEmpty() ? "<anon>" : n) + (id == null ? "" : "@" + id) + "[" + programSize + "]";
    }
```

`NqpCodeEngine.java`, inside the `root.blockName == null` block, after the
`root.blockName = ...` line:

```java
            root.blockId = cf.codeRef == null ? null : cf.codeRef.staticInfo.uniqueId;
```

(`uniqueId` is the `@JvmField` cuid on `StaticCodeInfo`; if it is a Kotlin
property without `@JvmField`, use `getUniqueId()`.)

- [ ] **Step 6: The trace summary captures `id=`**

Extend `tools/build/t/truffle-trace-summary.rakutest`: change `plan 22;` to
`plan 23;` and append:

```raku
ok $out.contains('distinct-ids='), 'reports distinct compilation ids beside distinct names';
```

Run: `raku tools/build/t/truffle-trace-summary.rakutest` — expected: test 23 not ok.

In `tools/build/truffle-trace-summary.raku:91`, change `'id=' \d+` to
`'id=' $<id>=(\d+)`, store `id => +$<id>` in the event hash beside `name`
and `verb`, and where the summary prints its `done=`/`failed=` line, add:

```raku
say "distinct-ids={ @events.map(*<id>).unique.elems } distinct-names={ @events.map(*<name>).unique.elems }";
```

Run: `raku tools/build/t/truffle-trace-summary.rakutest` — expected: 23 ok.

- [ ] **Step 7: Rebuild, run the nqp test, gates**

```bash
./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars -q
(cd nqp && ./nqp-j-gradle t/nqp/125-dispatch-stats.t)
```

Expected: `1..4`, all ok. Then the gates, in cost order:

```bash
raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/gate-nqp-suite.log --show='files in' --stall=1200 -- \
    raku tools/build/evalserver-sweep.raku --suite=nqp '--chunk=*'
RAKUDO_RAKUAST=1 perl t/harness5 --jvm --evalserver t/01-sanity 2>&1 | tail -3
```

Expected: `154 files in ...` with no failed chunk; `All tests successful`.

- [ ] **Step 8: Commit (both trees)**

```bash
git -C nqp add nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpCodeEngine.java t/nqp/125-dispatch-stats.t
STAMP="$(date +%F)T20:00:00+02:00"; GIT_AUTHOR_DATE=$STAMP GIT_COMMITTER_DATE=$STAMP git -C nqp commit -q -F - <<'MSG'
Dispatch: misses by dispatcher, AttrSrc slow causes, decont layout misses, roots named by cuid

NQP_DISPATCH_STATS=1 now ends with a misses-by-dispatcher histogram and
splits AttrSrc's slow evaluations into layout mismatches and null slots;
a decont site whose STable matches but whose layout does not now misses
(and pins) instead of taking the slow road forever unseen; a root's
name carries its cuid so compilation traces stop merging targets.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01GK4DKrQFQgNaiYirUzjcgJ
MSG
git add tools/build/truffle-trace-summary.raku tools/build/t/truffle-trace-summary.rakutest
GIT_AUTHOR_DATE=$STAMP GIT_COMMITTER_DATE=$STAMP git commit -q -m "Tools: truffle-trace-summary captures the compilation id

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01GK4DKrQFQgNaiYirUzjcgJ"
```

- [ ] **Step 9: Measure**

```bash
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/m7-rig-a2.log \
    --show='m7-rig:' --stall=7200 --max=10800 -- \
    raku tools/build/m7-rig.raku --tag=a2 --out=$CLAUDE_JOB_DIR/tmp/m7-rig
```

Copy the row (verdict "diagnostics") and, from
`$CLAUDE_JOB_DIR/tmp/m7-rig/a2-rakudo-e-run<best>.err`, the top-8 misses
histogram into the ledger: that histogram is the number A6 must move.

---

## Task 4: A3 — dispatcher callbacks enter through the unit road

**Files:**
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/StaticCodeInfo.kt:79`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt:40-42`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt:2933-2982`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/Dispatch.kt:368-390`
- Test: `nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/ProgramUnitTest.kt`

**Interfaces:**
- Consumes: `ProgramEntry.enter(tc, cr, csd, resume, args)` (the body every
  artifact block has); `Ops.invocantCallSite`; `DispatchCallback.Code.code`.
- Produces: `StaticCodeInfo.unitEntry: Boolean` (true for every code ref
  `ProgramUnit.buildTable` builds); `Ops.enterUnit(tc, cr, csd, args)`.
  Task 5 reuses `unitEntry`.

Today a miss enters each NQP-coded dispatcher through `Ops.invokeDirect`:
the invokee checks, `ArgsExpectation.invokeByExpectation`'s switch, and
the bound method handle, before `ProgramEntry.enter` builds the frame and
runs the program. Every artifact block has that same entry body, so the
callback can go there directly.

- [ ] **Step 1: Write the failing test**

`nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/ProgramUnitTest.kt`
already has a private `unit()` helper building a four-slot table and
reading it back through `qbidToCodeRef`. Add, inside the class:

```kotlin
    @Test
    fun everyTableCodeRefIsAUnitEntry() {
        val u = unit()
        u.buildTable(null)
        val cr = u.qbidToCodeRef!![0]!!
        assertTrue(cr.staticInfo.unitEntry, "buildTable marks the shared entry body")
    }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.runtime.unit.ProgramUnitTest' -q`
Expected: compilation error, `unitEntry` unresolved.

- [ ] **Step 3: The flag**

`StaticCodeInfo.kt`, after `programIndex`:

```kotlin
    /** True when the code ref's body is ProgramEntry.enter (the artifact
     *  road): callers may enter it directly instead of through the handle. */
    @JvmField var unitEntry: Boolean = false
```

`ProgramUnit.kt`, after `sci.programIndex = b.programIndex`:

```kotlin
            sci.unitEntry = true
```

- [ ] **Step 4: `Ops.enterUnit`**

In `Ops.kt`, directly after the two-argument `invokeDirect` overload
(line 2936):

```kotlin
    /**
     * Enters a unit-road block the way its bound handle would, without the
     * handle: every artifact block is USE_BINDER with ProgramEntry.enter as
     * its body, so nothing invokeByExpectation examines varies between
     * them. The catches are invokeDirect's, verbatim.
     */
    @JvmStatic
    fun enterUnit(tc: ThreadContext, cr: CodeRef, csd: CallSiteDescriptor, args: Array<Any?>) {
        val callerFrame = tc.curFrame
        try {
            org.raku.nqp.runtime.unit.ProgramEntry.enter(tc, cr, csd, null, args)
        }
        catch (r: org.raku.nqp.dispatch.BindReturnException) {
            val caller = callerFrame ?: tc.dummyCaller
            caller.oRet = r.value
            caller.retType = CallFrame.RET_OBJ.toByte()
        }
        catch (e: ControlException) {
            throw e
        }
        catch (e: Throwable) {
            ExceptionHandling.dieInternal(tc, e)
        }
    }
```

- [ ] **Step 5: The callback takes it**

`Dispatch.kt`, in `invokeCallback`'s `is DispatchCallback.Code` arm,
replace the `Ops.invokeDirect(...)` call inside the `try`:

```kotlin
                    val code = callback.code
                    if (code is CodeRef && code.staticInfo.unitEntry)
                        Ops.enterUnit(tc, code, Ops.invocantCallSite, arrayOf<Any?>(capture))
                    else
                        Ops.invokeDirect(tc, code, Ops.invocantCallSite, arrayOf<Any?>(capture))
```

(`CodeRef` is `org.raku.nqp.runtime.CodeRef`; add the import if the file
lacks it.)

- [ ] **Step 6: Test, jar, gates**

```bash
./nqp/gradlew -p nqp :nqp-runtime:test --tests 'org.raku.nqp.runtime.unit.ProgramUnitTest' -q
./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars -q
```

Then the gates, in cost order:

```bash
raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/gate-nqp-suite.log --show='files in' --stall=1200 -- \
    raku tools/build/evalserver-sweep.raku --suite=nqp '--chunk=*'
RAKUDO_RAKUAST=1 perl t/harness5 --jvm --evalserver t/01-sanity 2>&1 | tail -3
```

Expected: `154 files in ...` with no failed chunk; `All tests successful`.

- [ ] **Step 7: Commit (nqp tree)**

```bash
git -C nqp add src/vm/jvm/runtime/org/raku/nqp/runtime/StaticCodeInfo.kt src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt src/vm/jvm/runtime/org/raku/nqp/dispatch/Dispatch.kt nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/ProgramUnitTest.kt
STAMP="$(date +%F)T20:30:00+02:00"; GIT_AUTHOR_DATE=$STAMP GIT_COMMITTER_DATE=$STAMP git -C nqp commit -q -F - <<'MSG'
Dispatch: a recorded dispatcher callback enters its block through the unit road

Every artifact block has ProgramEntry.enter as its body; a miss entered
each NQP-coded dispatcher through Ops.invokeDirect, the expectation
switch and the bound handle to reach it. StaticCodeInfo.unitEntry marks
the table's code refs and Ops.enterUnit goes straight to the body, with
invokeDirect's catches.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01GK4DKrQFQgNaiYirUzjcgJ
MSG
```

- [ ] **Step 8: Measure**

```bash
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/m7-rig-a3.log \
    --show='m7-rig:' --stall=7200 --max=10800 -- \
    raku tools/build/m7-rig.raku --tag=a3 --out=$CLAUDE_JOB_DIR/tmp/m7-rig
```

Row into the ledger. Verdict "landed" if cold rakudo-e or the warm clock
moved beyond the base row's spread; "struck (kept)" if neither moved and
nothing regressed (the code is simpler than what it replaces); reverted
in a follow-up commit if either clock regressed.

---

## Task 5: A4 — the stub road's fast path at call time

**Files:**
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt:2963-2966` (inside `invokeDirect`)

**Interfaces:**
- Consumes: `StaticCodeInfo.unitEntry` (Task 4), `ProgramEntry.enter`.
- Produces: nothing new; `invokeDirect` enters unit-road blocks without
  `invokeByExpectation`.

- [ ] **Step 1: The fast path**

In `invokeDirect`'s `try`, replace
`ArgsExpectation.invokeByExpectation(tc, cr, callSite, argList)` with:

```kotlin
            if (cr.staticInfo.unitEntry)
                org.raku.nqp.runtime.unit.ProgramEntry.enter(tc, cr, callSite, null, argList)
            else
                ArgsExpectation.invokeByExpectation(tc, cr, callSite, argList)
```

Nothing else changes: the catches around it are the ones `enterUnit`
copied, and the non-unit road (interop adaptor units, `NO_ARGS`/`OBJ`
expectations) still takes the switch.

- [ ] **Step 2: Jar, gates**

```bash
./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars -q
```

Then the gates, in cost order:

```bash
raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/gate-nqp-suite.log --show='files in' --stall=1200 -- \
    raku tools/build/evalserver-sweep.raku --suite=nqp '--chunk=*'
RAKUDO_RAKUAST=1 perl t/harness5 --jvm --evalserver t/01-sanity 2>&1 | tail -3
```

Expected: `154 files in ...` with no failed chunk; `All tests successful`. The existing test suites are the
test: a wrong entry here breaks every call, so the nqp suite (154 files)
is the red/green.

- [ ] **Step 3: Commit (nqp tree)**

```bash
git -C nqp add src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt
STAMP="$(date +%F)T21:00:00+02:00"; GIT_AUTHOR_DATE=$STAMP GIT_COMMITTER_DATE=$STAMP git -C nqp commit -q -F - <<'MSG'
Ops.invokeDirect: a unit-road block is entered without the expectation switch

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01GK4DKrQFQgNaiYirUzjcgJ
MSG
```

- [ ] **Step 4: Measure**

```bash
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/m7-rig-a4.log \
    --show='m7-rig:' --stall=7200 --max=10800 -- \
    raku tools/build/m7-rig.raku --tag=a4 --out=$CLAUDE_JOB_DIR/tmp/m7-rig
```

Row into the ledger. Verdict "landed" if cold rakudo-e or the warm clock
moved beyond the base row's spread; "struck (kept)" if neither moved and
nothing regressed; reverted in a follow-up commit if either clock
regressed.

---

## Task 6: A5 — the record path off its hash maps

**Files:**
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchRegistry.kt:38-68`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchBootstrap.kt:25-75`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/Dispatch.kt:131-141`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt:2806-2931`

**Interfaces:**
- Consumes: `DispatchRegistry.find(tc, id)`, `register(...)`;
  `DispatchCallSite.reset()`; `Ops.invokeMethodViaDispatch`,
  `Ops.invokeViaCallDispatcher`.
- Produces: `DispatchRegistry.epoch: Int` (bumped by every `register`);
  `DispatchCallSite.dispatcher`/`dispatcherEpoch` (cleared by `reset`);
  `Ops.HelperSite(site, csd)`, the value of both helper maps.

Two hash-map costs on every miss and every helper call: `fallback` looks
the dispatcher up by name in the registry's `ConcurrentHashMap` although
the name is a constant of the instruction, and `invokeMethodViaDispatch`
builds a shape string and a full descriptor per call to key its site.

- [ ] **Step 1: The registry epoch and the site cache**

`DispatchRegistry.kt`, inside the class after `dispatchers`:

```kotlin
    /** Bumped by every register: a site that cached a Dispatcher re-finds
     *  it when the registry has changed under it. */
    @Volatile @JvmField var epoch: Int = 0
```

and at the end of `register(...)`, after the `dispatchers.put(...)` (or
whatever store it does): `epoch++`.

`DispatchBootstrap.kt`, in `DispatchCallSite` after `staticDescriptor`:

```kotlin
    /** The dispatcher this site's instruction names, found once per
     *  registry epoch rather than on every miss. */
    @JvmField var dispatcher: Dispatcher? = null
    @JvmField var dispatcherEpoch: Int = -1
```

and in `reset()`, beside `linkedName = null`:

```kotlin
        dispatcher = null
        dispatcherEpoch = -1
```

`Dispatch.kt`, `fallback`'s last line becomes:

```kotlin
        val registry = tc.gc.dispatchers
        var dispatcher = site.dispatcher
        if (dispatcher == null || site.dispatcherEpoch != registry.epoch) {
            dispatcher = registry.find(tc, name)
            site.dispatcher = dispatcher
            site.dispatcherEpoch = registry.epoch
        }
        record(tc, dispatcher, descriptor, args, site)
```

- [ ] **Step 2: Helper sites keyed by identity, descriptors built once**

In `Ops.kt`, replace the `helperDispatchSites` declaration and
`invokeMethodViaDispatch`'s site lookup:

```kotlin
    /** A helper-made dispatch site with the descriptor it dispatches with,
     *  both built once per (method, caller descriptor). */
    class HelperSite(@JvmField val site: org.raku.nqp.dispatch.DispatchCallSite,
                     @JvmField val csd: CallSiteDescriptor)

    private fun withInvokeeSlot(csd: CallSiteDescriptor): CallSiteDescriptor {
        val flags = ByteArray(csd.argFlags.size + 1)
        flags[0] = CallSiteDescriptor.ARG_OBJ
        csd.argFlags.copyInto(flags, 1)
        return CallSiteDescriptor(flags, csd.names)
    }

    /* Keyed by the method object and the CALLER'S descriptor by identity:
     * a descriptor object has one shape, so the shape string the old key
     * built per call is implied. Two equal-shaped descriptors make two
     * sites, which only costs a second recording. */
    private val helperDispatchSites =
        java.util.concurrent.ConcurrentHashMap<SixModelObject,
            java.util.concurrent.ConcurrentHashMap<CallSiteDescriptor, HelperSite>>()
```

and in `invokeMethodViaDispatch`, everything from `val flags = ...` through
the `dispatchWithDescriptor` call becomes:

```kotlin
        val byShape = helperDispatchSites.computeIfAbsent(method!!) {
            java.util.concurrent.ConcurrentHashMap(4)
        }
        val hs = byShape.computeIfAbsent(csd) {
            HelperSite(org.raku.nqp.dispatch.DispatchCallSite(helperDispatchSiteType), withInvokeeSlot(csd))
        }
        val fullArgs = arrayOfNulls<Any>(args.size + 1)
        fullArgs[0] = method
        args.copyInto(fullArgs, 1)
        org.raku.nqp.dispatch.Dispatch.dispatchWithDescriptor(hs.site, "lang-call",
            hs.csd, tc, fullArgs)
```

`langCallSites` becomes a map to `HelperSite` too, so
`invokeViaCallDispatcher` stops rebuilding its descriptor per call:

```kotlin
    private val langCallSites =
        java.util.concurrent.ConcurrentHashMap<Pair<SixModelObject, CallSiteDescriptor>, HelperSite>()
```

```kotlin
    private fun invokeViaCallDispatcher(tc: ThreadContext, invokee: SixModelObject,
                                        csd: CallSiteDescriptor, args: Array<Any?>) {
        val hs = langCallSites.computeIfAbsent(Pair(invokee, csd)) {
            HelperSite(org.raku.nqp.dispatch.DispatchCallSite(helperDispatchSiteType), withInvokeeSlot(csd))
        }
        val fullArgs = arrayOfNulls<Any>(args.size + 1)
        fullArgs[0] = invokee
        args.copyInto(fullArgs, 1)
        org.raku.nqp.dispatch.Dispatch.dispatchWithDescriptor(hs.site, "lang-call",
            hs.csd, tc, fullArgs)
    }
```

`resetHelperDispatchSites` and `resetLangCallSites` are unchanged
(`clear()` on both maps).

- [ ] **Step 3: Jar, gates**

```bash
./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars -q
```

Then the gates, in cost order:

```bash
raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/gate-nqp-suite.log --show='files in' --stall=1200 -- \
    raku tools/build/evalserver-sweep.raku --suite=nqp '--chunk=*'
RAKUDO_RAKUAST=1 perl t/harness5 --jvm --evalserver t/01-sanity 2>&1 | tail -3
```

Expected: `154 files in ...` with no failed chunk; `All tests successful`.

- [ ] **Step 4: Commit (nqp tree)**

```bash
git -C nqp add src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchRegistry.kt src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchBootstrap.kt src/vm/jvm/runtime/org/raku/nqp/dispatch/Dispatch.kt src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt
STAMP="$(date +%F)T21:30:00+02:00"; GIT_AUTHOR_DATE=$STAMP GIT_COMMITTER_DATE=$STAMP git -C nqp commit -q -F - <<'MSG'
Dispatch: the dispatcher is cached on the site; helper sites keyed by identity

A miss looked its dispatcher up by name in the registry's map every
time; the site now keeps it, re-found when the registry's epoch moves.
The helper roads (boolification, Str/Num/Int coercion, lang-call) keyed
their sites by a shape string built per call and rebuilt the descriptor
per call; both are built once per (method, caller descriptor).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01GK4DKrQFQgNaiYirUzjcgJ
MSG
```

- [ ] **Step 5: Measure**

```bash
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/m7-rig-a5.log \
    --show='m7-rig:' --stall=7200 --max=10800 -- \
    raku tools/build/m7-rig.raku --tag=a5 --out=$CLAUDE_JOB_DIR/tmp/m7-rig
```

Row into the ledger. Verdict "landed" if cold rakudo-e or the warm clock
moved beyond the base row's spread; "struck (kept)" if neither moved and
nothing regressed; reverted in a follow-up commit if either clock
regressed.

---

## Task 7: A7 — the classlib boundary, then the targeted boundaries

**Files:**
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java:946-975`
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java:221-230`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/ExceptionHandling.kt:44` (every `dieInternal` overload)
- Modify: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NFGString.kt:143-152`
- Modify: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpPolyglot.kt:49-69`

**Interfaces:**
- Consumes: `NqpOps.classlib(rtype, site, a, tc, cf)` (no boundary today);
  `NqpOps.run` (has one); `ExceptionHandling.dieInternal`;
  `NFGString.of`; `GlobalContext.noisyExceptions`.
- Produces: `NqpOps.classlib` behind `@TruffleBoundary` by default,
  `NqpOps.classlibInline` (today's body) selected by `NQP_CLASSLIB_INLINE=1`
  at program build; `NQP_BOUNDARY_CHECK=1` printing
  `boundary-check: dieInternal TruffleBoundary=<true|false>` at context
  build (the positive marker for decision 7 under each runner).

The classlib road (624 core ops, 40 Raku ops) invokes `Ops.kt` through a
spread method handle with no boundary, so every op body and everything
it calls is visible to partial evaluation from every call site; the table
road (`NqpOps.run`, 383 ops) already sits behind `@TruffleBoundary`. The
442-root inlining bailout is on sited roads (`create` → `VMArray.allocate`
→ `dieInternal`; `getattr`/`bindattr`), not the classlib road, and gets
its own boundaries.

- [ ] **Step 1: The marker first (decision 7 is verified, not assumed)**

`NqpPolyglot.kt`, in `build()` after `.build()`:

```kotlin
        /* NQP_BOUNDARY_CHECK=1: whether a @TruffleBoundary placed in the
         * RUNTIME tree (compileOnly truffle-api, on -cp for rakudo-j but
         * on -Xbootclasspath/a for nqp-j-gradle) is visible where the
         * compiler reads it. Milestone 7 A7 depends on the answer. */
        if (System.getenv("NQP_BOUNDARY_CHECK") != null) {
            val m = org.raku.nqp.runtime.ExceptionHandling::class.java.declaredMethods
                .filter { it.name == "dieInternal" }
            val seen = m.any { it.getAnnotation(com.oracle.truffle.api.CompilerDirectives.TruffleBoundary::class.java) != null }
            System.err.println("boundary-check: dieInternal TruffleBoundary=$seen (${m.size} overloads)")
        }
```

Smoke: `NQP_BOUNDARY_CHECK=1 RAKUDO_RAKUAST=1 ./rakudo-j -e 'say 1' 2>&1 | grep boundary-check`
after Step 5's jar — expected `TruffleBoundary=true`. Run the same with
`(cd nqp && NQP_BOUNDARY_CHECK=1 ./nqp-j-gradle -e 'say(1)')`. If the
nqp runner prints `false`, the boot-class-path loader cannot see the
annotation class: rule in the ledger that runtime-tree boundaries hold
for `rakudo-j` only, and move the `nqp-j-gradle` runner's runtime jars
from `-Xbootclasspath/a` to `-cp` as a follow-up task in this plan
(`nqp/buildSrc/src/main/kotlin/GenerateRunnerTask.kt:153-155` is where
the line is generated), re-measured by the nqp cold row only.

- [ ] **Step 2: `dieInternal` behind a boundary**

`ExceptionHandling.kt`: add `import com.oracle.truffle.api.CompilerDirectives.TruffleBoundary`
and annotate every `dieInternal` overload (the private one at line 44 and
each public one that delegates to it) with `@TruffleBoundary`. The
40-frame `StringBuilder` walk and the handler search are then never
inlined into a root that merely *may* die. Nothing else in the file
changes. (`VMArray.allocate`'s die arm calls `dieInternal`, so it needs no
annotation of its own: the boundary it reaches is the cut.) The spec's
"static final hoist of the noisy-exceptions flag" is moot behind the
boundary and would change the flag from per-context to per-process;
recorded as a deferred minor, not done.

- [ ] **Step 3: `NFGString.of` behind a boundary**

`NFGString.kt`: annotate `of` (line 145) with `@TruffleBoundary`
(`com.oracle.truffle.api.CompilerDirectives.TruffleBoundary`; nqp-truffle
already imports it elsewhere). `atomsOf` stays as it is: its only work is
the call to `of` and the atom array read. `RxVmNode.literalAtoms` already
carries the annotation and is unchanged.

- [ ] **Step 4: The classlib road behind a boundary, with the knob**

`NqpOps.java`: rename today's `classlib` to `classlibInline` (body
unchanged) and add:

```java
    /** NQP_CLASSLIB_INLINE=1 restores the pre-milestone-7 road (op bodies
     *  visible to PE) for exactly one measurement; the default is the
     *  boundary, matching the table road's run(). Read once: a static
     *  final folds in every program built after it. */
    static final boolean CLASSLIB_INLINE = System.getenv("NQP_CLASSLIB_INLINE") != null;

    @TruffleBoundary
    static Object classlib(int rtype, ClassLibSite site, Object[] a, ThreadContext tc, CallFrame cf) {
        return classlibInline(rtype, site, a, tc, cf);
    }
```

`NqpRootNode.java`, `ClassLibOp.doCall`:

```java
                return NqpOps.CLASSLIB_INLINE
                    ? NqpOps.classlibInline(rtype, (NqpOps.ClassLibSite) site, a, tc(f), cf(f))
                    : NqpOps.classlib(rtype, (NqpOps.ClassLibSite) site, a, tc(f), cf(f));
```

- [ ] **Step 5: Jar, marker, gates**

```bash
./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars -q
NQP_BOUNDARY_CHECK=1 RAKUDO_RAKUAST=1 ./rakudo-j -e 'say 1' 2>&1 | grep boundary-check
(cd nqp && NQP_BOUNDARY_CHECK=1 ./nqp-j-gradle -e 'say(1)' 2>&1 | grep boundary-check)
```

Expected: `boundary-check: dieInternal TruffleBoundary=true (...)` from
both, or the ruling of Step 1. Then the gates, in cost order:

```bash
raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/gate-nqp-suite.log --show='files in' --stall=1200 -- \
    raku tools/build/evalserver-sweep.raku --suite=nqp '--chunk=*'
RAKUDO_RAKUAST=1 perl t/harness5 --jvm --evalserver t/01-sanity 2>&1 | tail -3
```

Expected: `154 files in ...` with no failed chunk; `All tests successful`.

- [ ] **Step 6: Commit (nqp tree)**

```bash
git -C nqp add nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java src/vm/jvm/runtime/org/raku/nqp/runtime/ExceptionHandling.kt nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NFGString.kt nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpPolyglot.kt
STAMP="$(date +%F)T22:00:00+02:00"; GIT_AUTHOR_DATE=$STAMP GIT_COMMITTER_DATE=$STAMP git -C nqp commit -q -F - <<'MSG'
Engine: the classlib road behind a TruffleBoundary; dieInternal and NFGString.of too

The 624+40 registry ops reached Ops.kt through a spread handle with no
boundary, so every op body was partial-evaluation-visible from every
site while the table road's run() already had one. NQP_CLASSLIB_INLINE=1
restores the old road for one measurement. dieInternal (the 442-root
inlining bailout's tail) and NFGString.of (a WeakHashMap under a
compiled root) get their own boundaries; NQP_BOUNDARY_CHECK=1 reports
whether a runtime-tree annotation is visible under the current runner.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01GK4DKrQFQgNaiYirUzjcgJ
MSG
```

- [ ] **Step 7: Measure**

```bash
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/m7-rig-a7.log \
    --show='m7-rig:' --stall=7200 --max=10800 -- \
    raku tools/build/m7-rig.raku --tag=a7 --out=$CLAUDE_JOB_DIR/tmp/m7-rig
```

Row into the ledger. This is the one lever expected to move the WARM
clock as much as the cold one.

- [ ] **Step 8: If a clock regressed: the promotion list**

Only if the a7 row is slower than the a5 row on either clock. Take one
JFR of the cold run and list the classlib ops at the leaf:

```bash
RAKUDO_RAKUAST=1 RAKUDO_JVM_XOPTS="-XX:StartFlightRecording=filename=$CLAUDE_JOB_DIR/tmp/a7.jfr,settings=profile -XX:FlightRecorderOptions:stackdepth=512" ./rakudo-j -e 'say 1'
raku tools/build/jfr-attribute.raku $CLAUDE_JOB_DIR/tmp/a7.jfr --innermost --top=20
```

Every `Ops.<name>` in the top 20 that is a classlib op (its name is in
`%CODE_CLASSLIB_OPS`, `nqp/src/vm/jvm/QAST/Compiler.nqp:169-172`) goes on
the promotion list in the ledger. Promote at most the top five in this
task, each by the sited-op recipe (no wire change):

1. an op id constant in `NqpOps.java` beside `OP_ISCONCRETE`;
2. an `op3('<name>', <id>, $T_OBJ, '<args>')` row in `TruffleEncoder.nqp`'s
   `emit_init()` (this is an encoder edit: it needs
   `./nqp/gradlew -p nqp clean buildJvm` and, for Rakudo to see it, the
   Task 9 `make`; so a promotion lands WITH Task 9's compile, never alone);
3. an `@Operation` class in `NqpRootNode.java` modelled on `IsConcreteOp`
   (`:537-555`), calling a Kotlin body in `NqpTypeOps.kt` or a new
   `NqpClassLibOps.kt`;
4. one line each in `NqpProgramBuilder.dedicatedOp` (`:695`), `beginOp`
   (`:715`) and `endOp` (`:738`).

The rest of the list is recorded, not done. If the regression is on the
warm clock only and the top-20 shows no classlib op above 2 %, the ruling
is "revert the classlib boundary, keep the targeted ones" and a follow-up
commit does exactly that; the row is re-taken as `a7r` (the one
permitted re-measurement, because the tree changed).

- [ ] **Step 9: The getattr/bindattr chain, bounded**

The inherited item 1 names a second chain (204 roots) entering at
`NqpOps.getattr:1503` / `bindattr:1539`, "where the JDK constructs a
wrong-method-type exception message". `AttrSite.e1/e2` are already
`@CompilationFinal` and `AttrEntry.getter` is `final`, so the handle is a
PE constant and the type check should fold. Find out what does not, on a
cold run, in ten minutes:

```bash
RAKUDO_RAKUAST=1 RAKUDO_JVM_XOPTS="-Dpolyglot.engine.TraceCompilation=true -Dpolyglot.engine.TraceInlining=true" ./rakudo-j -e 'say 1' 2> $CLAUDE_JOB_DIR/tmp/a7-inlining.log
grep -n 'getattr\|bindattr' $CLAUDE_JOB_DIR/tmp/a7-inlining.log | grep -i 'exceed\|too deep\|not inlined\|slow' | head -20
```

The trace names the method at the cut. If it is inside `getattrSlow` /
`bindattrSlow` (the fallback road), annotate those two with
`@TruffleBoundary` (they are in `NqpOps.java`, `:1571` and `:1593`). If it
is the `shouldNotReachHere(t)` arm, replace the `catch (Throwable t)`
bodies at `:1503` and `:1539` with a call to a new
`@TruffleBoundary static RuntimeException attrHandleFailed(Throwable t)`
that returns `CompilerDirectives.shouldNotReachHere(t)`. Either is one
runtime rebuild; it rides into the a8/a6 rows (no row of its own) and the
ledger records which it was. If the trace shows neither on a cold `-e`,
record "not reproduced outside a CORE.c compile; deferred to Phase B's
window build, whose setting compile can carry the same trace" and move on.

---

## Task 8: A8 — dispatcher programs compiled early: the spike

**Files:**
- Modify: the ledger only (the spike's output is a recommendation)

**Interfaces:**
- Consumes: `NQP_CODE_TRACE=1` (one `code> <name> cuid=<id> ... at=<file>:<line>`
  line per block entry, `CodeEngine.kt:165`); `-Dpolyglot.engine.TraceCompilation=true`
  with the Task 3 root names (`<name>@<cuid>[<size>]`);
  `tools/build/truffle-trace-summary.raku`.
- Produces: a ledger section "A8 spike" with a table (dispatcher block,
  cuid, entries during the cold run, compiled at entry N or never) and one
  recommendation.

- [ ] **Step 1: Which blocks are the dispatchers, and how often they run**

```bash
NQP_CODE_TRACE=1 RAKUDO_RAKUAST=1 ./rakudo-j -e 'say 1' 2> $CLAUDE_JOB_DIR/tmp/a8-trace.log
grep 'dispatchers.nqp' $CLAUDE_JOB_DIR/tmp/a8-trace.log | sed 's/.*cuid=\([^ ]*\).*at=\([^ ]*\).*/\1 \2/' | sort | uniq -c | sort -rn | head -15
```

Expected: about fifteen (cuid, file:line) pairs, the top three near 1400
entries each (raku-invoke, the method-call initial dispatch,
raku-meth-call, per spec Revision 2).

- [ ] **Step 2: Whether they ever compile during the cold run**

```bash
RAKUDO_RAKUAST=1 RAKUDO_JVM_XOPTS="-Dpolyglot.engine.TraceCompilation=true" ./rakudo-j -e 'say 1' 2> $CLAUDE_JOB_DIR/tmp/a8-compile.log
raku tools/build/truffle-trace-summary.raku $CLAUDE_JOB_DIR/tmp/a8-compile.log | head -20
for c in $(grep 'dispatchers.nqp' $CLAUDE_JOB_DIR/tmp/a8-trace.log | sed 's/.*cuid=\([^ ]*\).*/\1/' | sort -u); do
  printf '%s ' "$c"; grep -c "@$c\[" $CLAUDE_JOB_DIR/tmp/a8-compile.log; done
```

Expected: for each dispatcher cuid, the number of `opt` events naming it
(0 = never submitted, 1+ = compiled or attempted). Record the table.

- [ ] **Step 3: What the engine offers per root**

Truffle has no public per-root "compile now" for a Bytecode DSL root;
the levers are engine options. Check which exist in this GraalVM, as
milestone 6 did, before naming any:

```bash
J=$(ls nqp/build/jvm/share/truffle/truffle-runtime-*.jar | head -1)
javap -cp "$J" -constants com.oracle.truffle.runtime.OptimizedRuntimeOptions 2>/dev/null | grep -i 'threshold\|CompileImmediately\|Mode\b\|BackgroundCompilation' | head
```

- [ ] **Step 4: The recommendation**

Write in the ledger, under "A8 spike": the two tables, and ONE of:

- "Dispatcher roots compile within the first N entries; a lower
  first-tier threshold cannot help more than X ms" (struck), or
- "Dispatcher roots never reach compiled code in a cold run; the
  mechanism is `<option>=<value>` on the stock runners, one measurement,
  cold clocks only" — then this becomes Task 8b by ruling: the option
  goes into `RAKUDO_JVM_XOPTS`-equivalent runner defaults
  (`tools/templates/jvm/rakudo-j.in` and `GenerateRunnerTask.kt`),
  measured as row `a8`, kept if the cold rows moved and the warm row did
  not regress.

No code is committed by this task unless 8b is ruled.

---

## Task 9: A6 — the static clone road (the one setting recompile)

**Files:**
- Modify: `src/vm/jvm/runtime/org/raku/rakudo/RakOps.kt:674-691` (add after `p6capturelex`)
- Modify: `src/vm/jvm/Raku/Ops.nqp:88` (add a row after it)
- Modify: `src/Raku/ast/code.rakumod:215-239` and `:983-990`
- Create: `t/02-rakudo/closure-static-clone.t`

**Interfaces:**
- Consumes: `Ops.clone(obj, tc)`, `Ops.clone_nd(obj, tc)`, `Ops.iscont(obj)`;
  `RakuObject.layout`, `RakuObjectLayout.kinds/getRef/setRef`, `SlotKind.REF`;
  `nqp::findmethod`; the `#?if jvm` preprocessor in `src/Raku/ast`.
- Produces: the Raku HLL op `p6clonecode(obj)` (JVM), semantically
  `Mu.clone(Mu:D:)` with no twiddles: a REPR clone plus `clone_nd` of every
  reference slot holding a container; `IMPL-CLOSURE-QAST` emits it in place
  of `callmethod clone` when the code object's `clone` resolves to Mu's.

Every closure creation is `callmethod clone` on a WVal: a lang-meth-call
miss per site (1148 at setting load), then `Mu.clone`'s proto, its
`Mu:D:` multi, and `!just-clone`, which walks `self.^attributes` through
the MOP and `clone_nd`s each container-holding one, on every creation.
`Code`, `Block`, `Routine`, `Sub`, `Method` define no `clone`; `Regex`
does (with `:topic`/`:slash`), and `$regex` closures keep the method
call. A null reference slot stays null: it auto-vivifies on first access
to a fresh container in either road.

- [ ] **Step 1: Write the failing test**

`t/02-rakudo/closure-static-clone.t`:

```raku
use lib <lib>;
use Test;
# Closure creation on the JVM takes a static clone road (milestone 7 A6);
# the observable semantics of Mu.clone(Mu:D:) must hold on every backend.
plan 7;

my @closures = (1..3).map: -> $i { -> { $i } };
is @closures.map(*.()).join(','), '1,2,3', 'each closure captures its own outer';
ok @closures[0] !=== @closures[1], 'each creation is a distinct object';

sub outer { my $x = 42; -> { $x } }
is outer()(), 42, 'a closure returned from a sub still reads its lexical';

my &f = -> Int $a, Str $b { "$a$b" };
is &f.signature.gist, '(Int $a, Str $b)', 'the signature survives the clone';

my &g = -> { 1 };
&g.set_why('documented');
my &h = &g.clone;
is &h.WHY.Str, 'documented', '.clone through the method road still works';
&h.set_why('changed');
is &g.WHY.Str, 'documented', 'a method-road clone does not alias its original';

my $ran = 0;
for 1..2 { LAST { $ran++ } }
is $ran, 1, 'a block with a LAST phaser runs it once (phasers copied by the clone)';
```

- [ ] **Step 2: Run it to verify it passes today (it is a regression guard)**

Run: `RAKUDO_RAKUAST=1 ./rakudo-j -Ilib t/02-rakudo/closure-static-clone.t`
Expected: `1..7`, all ok. This test does not go red before the change:
the change is a road, not a behaviour, and the test pins the behaviour
the road must keep. Say so in the ledger.

- [ ] **Step 3: The op**

`src/vm/jvm/runtime/org/raku/rakudo/RakOps.kt`, after `p6capturelex`:

```kotlin
    /**
     * Mu.clone(Mu:D:) with no twiddles, natively: the REPR clone, then
     * every reference slot holding a container gets its own clone of it
     * (what the private !just-clone does through the MOP on every closure
     * creation). Native slots hold no container; a null slot vivifies on
     * first access to a fresh container in either road, so it stays null.
     */
    @JvmStatic
    fun p6clonecode(obj: SixModelObject?, tc: ThreadContext): SixModelObject {
        val c = Ops.clone(obj, tc)
        if (c is RakuObject) {
            val l = c.layout
            if (l != null) {
                val kinds = l.kinds
                for (slot in kinds.indices) {
                    if (kinds[slot] != SlotKind.REF) continue
                    val v = l.getRef(c, slot)
                    if (v is SixModelObject && Ops.iscont(v) == 1L)
                        l.setRef(c, slot, Ops.clone_nd(v, tc))
                }
            }
        }
        return c
    }
```

with imports `org.raku.nqp.sixmodel.reprs.RakuObject`,
`org.raku.nqp.sixmodel.reprs.SlotKind` (the enum lives in
`RakuObjectLayout.kt`, package `org.raku.nqp.sixmodel.reprs`).

`src/vm/jvm/Raku/Ops.nqp`, after line 88:

```
$ops.map_classlib_hll_op('Raku', 'p6clonecode', $TYPE_P6OPS, 'p6clonecode', [$RT_OBJ], $RT_OBJ, :tc);
```

- [ ] **Step 4: The closure QAST takes it**

`src/Raku/ast/code.rakumod`, `IMPL-CLOSURE-QAST`: replace the `my $clone
:= QAST::Op.new(...)` statement with:

```
        my $wval := QAST::WVal.new( :value($code-obj) ).annotate_self('past_block', $!qast-block).annotate_self('code_object', $code-obj);
        my int $static-clone := 0;
#?if jvm
        # The static clone road (milestone 7): when the code object's
        # clone is Mu's own, p6clonecode does what Mu.clone(Mu:D:) does
        # without a dispatch miss per site and a MOP walk per creation.
        $static-clone := !$regex && nqp::eqaddr(nqp::findmethod($code-obj, 'clone'), nqp::findmethod(Mu, 'clone'));
#?endif
        my $clone := $static-clone
            ?? QAST::Op.new( :op('p6clonecode'), $wval )
            !! QAST::Op.new( :op('callmethod'), :name('clone'), $wval );
```

The throwaway-block fixup at `:983-990` gets the same shape:

```
        my $throwaway-wval := QAST::WVal.new( :value($throwaway_block) ).annotate_self('past_block', $throwaway_block_past).annotate_self('code_object', $throwaway_block);
        my int $static-throwaway := 0;
#?if jvm
        $static-throwaway := nqp::eqaddr(nqp::findmethod($throwaway_block, 'clone'), nqp::findmethod(Mu, 'clone'));
#?endif
        $fixup.push(QAST::Op.new(
                :op('p6capturelex'),
                $static-throwaway
                    ?? QAST::Op.new( :op('p6clonecode'), $throwaway-wval )
                    !! QAST::Op.new( :op('callmethod'), :name('clone'), $throwaway-wval )));
```

`Mu` is nameable here because `gen/jvm/ast.nqp` is compiled inside
BOOTSTRAP (`signature.rakumod:1918` uses bare `Code` the same way).
`signature.rakumod:1918` (a `Code` default value in a signature) is left
on the method road: recorded as a deferred minor.

- [ ] **Step 5: Build (background, about 20 min) and record CORE.c**

An encoder-adjacent change on the nqp side is NOT involved (the op is a
classlib row in Rakudo's own `Ops.nqp`), so no nqp clean is needed; the
rakudo side rebuilds `rakudo-runtime.jar`, `gen/jvm/ast.nqp`, BOOTSTRAP
v6c and the three settings:

```bash
raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/a6-make.log \
    --show='Compiling' --show='Generating' --show='Stage' --stall=1500 --max=3600 -- make
grep -A6 'CORE.c.setting.jar' $CLAUDE_JOB_DIR/tmp/a6-make.log | grep -i 'parse\|optimize\|qast\|unit' | head
```

Record CORE.c's `--stagestats` lines in the ledger (parse was 232.9 s on
2026-09-13); it is reported, not gated.

- [ ] **Step 6: Test, gates**

```bash
RAKUDO_RAKUAST=1 ./rakudo-j -Ilib t/02-rakudo/closure-static-clone.t
RAKUDO_RAKUAST=1 ./rakudo-j -Ilib t/02-rakudo/begin-clone-wrap.t
RAKUDO_RAKUAST=1 ./rakudo-j -Ilib t/02-rakudo/begin-called-block-routine.t
```

Expected: the first two all ok; the third is in the milestone-5 red
baseline (a pre-existing red), so only "no new failure kind" is checked
against `$CLAUDE_JOB_DIR/tmp/m7-rig/base-sweep.log`. Then the gates, in cost order:

```bash
raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/gate-nqp-suite.log --show='files in' --stall=1200 -- \
    raku tools/build/evalserver-sweep.raku --suite=nqp '--chunk=*'
RAKUDO_RAKUAST=1 perl t/harness5 --jvm --evalserver t/01-sanity 2>&1 | tail -3
```

Expected: `154 files in ...` with no failed chunk; `All tests successful`. (The nqp suite is unaffected by a Rakudo-only change and is run anyway, in cost order.)

- [ ] **Step 7: Commit (rakudo tree)**

```bash
git add src/vm/jvm/runtime/org/raku/rakudo/RakOps.kt src/vm/jvm/Raku/Ops.nqp src/Raku/ast/code.rakumod t/02-rakudo/closure-static-clone.t
STAMP="$(date +%F)T22:30:00+02:00"; GIT_AUTHOR_DATE=$STAMP GIT_COMMITTER_DATE=$STAMP git commit -q -F - <<'MSG'
RakuAST: closures take a static clone road on the JVM

Every closure creation was `callmethod clone` on the code object: a
lang-meth-call miss per site (1148 at setting load), Mu.clone's proto and
multi, and !just-clone walking the attributes through the MOP on every
creation. When the code object's clone resolves to Mu's own at compile
time, the JVM backend emits p6clonecode instead: the REPR clone plus a
clone_nd of every reference slot holding a container, which is what
Mu.clone(Mu:D:) does with no twiddles. Regex closures keep the method
call (Regex overrides clone).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01GK4DKrQFQgNaiYirUzjcgJ
MSG
```

- [ ] **Step 8: Measure**

```bash
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/m7-rig-a6.log \
    --show='m7-rig:' --stall=7200 --max=10800 -- \
    raku tools/build/m7-rig.raku --tag=a6 --out=$CLAUDE_JOB_DIR/tmp/m7-rig
```

Row into the ledger, with the a6 misses histogram beside a2's: the
`lang-meth-call` count must drop by about 1148 on the cold run. Verdict
"landed" if cold rakudo-e or the warm clock moved beyond the base row's
spread; "struck (kept)" if neither moved and nothing regressed; reverted
in a follow-up commit if either clock regressed. This row is Phase A's closing row and Phase B's
baseline.

---

## Task 10: The Phase A close

**Files:**
- Modify: `docs/jvm-perf-findings-2026-09.md` (append a section)
- Modify: `docs/jvm-truffle-only-plan.md` (the Position section)
- Modify: the ledger (final verdicts)
- Modify: `~/.claude/projects/-home-longwalker-code-raku-x-core-rakudo/memory/milestone-7-first-execution.md` and `MEMORY.md`

**Interfaces:**
- Consumes: the ledger's Rig rows table (base, a1, a2, a3, a4, a5, a7,
  [a8], a6), the A8 spike section, the promotion list.
- Produces: the findings section "Milestone 7, Phase A (runtime levers)";
  the plan doc's position update; both branches pushed; the handoff line
  for the Phase B plan.

- [ ] **Step 1: The findings section**

Append to `docs/jvm-perf-findings-2026-09.md`, before "Things that cost
time to learn":

```markdown
## Milestone 7, Phase A: the runtime levers (2026-09-xx)

Spec: `docs/superpowers/specs/2026-09-13-jvm-milestone-7-first-execution-design.md`;
plan and ledger: `docs/superpowers/plans/2026-09-13-jvm-milestone-7-first-execution-phase-a*.md`.
Rig: `tools/build/m7-rig.raku`; rows are cold `rakudo-j -e 'say 1'` and
`nqp-j-gradle -e 'say(1)'` best of 5, the dispatch counters of the best
rakudo run, and warm `t/02-rakudo` (306 files) on one 8 GB eval server.

| lever | rakudo / nqp hash | cold rakudo-e | cold nqp-e | misses | warm t/02-rakudo | verdict |
|---|---|---|---|---|---|---|
| base | ... | 2.68 s | 1.12 s | 6815 | ... s | base |
| A1 presized SC maps | ... | | | | | |
| A2 diagnostics | ... | | | | | diagnostics |
| A3 callback via unit road | ... | | | | | |
| A4 stub fast path | ... | | | | | |
| A5 record off the maps | ... | | | | | |
| A7 boundaries | ... | | | | | |
| A8 dispatcher compilation | spike | | | | | recommendation: ... |
| A6 static clone road | ... | | | | | |

**What moved and why** (one paragraph per landed lever, from the ledger).

**Struck** (one line each, with the numbers).

**The promotion list** (A7 Step 8), done and remaining.

**What Phase B starts from:** the a6 row, verbatim, and the a6 misses
histogram (top 8).
```

Fill every cell from the ledger; no cell stays `...`.

- [ ] **Step 2: The plan doc**

In `docs/jvm-truffle-only-plan.md`, under "Position (2026-09-13)", add a
dated update paragraph in the style of the existing "Update, 2026-09-13
evening" ones: Phase A of milestone 7 closed, the two clocks before and
after, the levers landed and struck, "Phase B (artifact v2 + lazy tables
+ the dispatch entry) is next; its plan is written from the a6 row".

- [ ] **Step 3: The memory**

Update `milestone-7-first-execution.md` (the memory file): status line
becomes "Phase A CLOSED <date>: <clocks before -> after>; landed: ...;
struck: ...; NEXT = write the Phase B plan (lazy-loading tasks 1.1-1.6 +
site identity + empty unit.dispatch) via superpowers:writing-plans, then
subagents on Opus"; update its `MEMORY.md` line to match.

- [ ] **Step 4: Gates once more, commit, push both trees**

On the final tree (green at Task 9; this confirms nothing drifted while the docs were written), the gates, in cost order:

```bash
raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/gate-nqp-suite.log --show='files in' --stall=1200 -- \
    raku tools/build/evalserver-sweep.raku --suite=nqp '--chunk=*'
RAKUDO_RAKUAST=1 perl t/harness5 --jvm --evalserver t/01-sanity 2>&1 | tail -3
```

Expected: `154 files in ...` with no failed chunk; `All tests successful`.

Then:

```bash
git add docs/jvm-perf-findings-2026-09.md docs/jvm-truffle-only-plan.md docs/superpowers/plans/2026-09-13-jvm-milestone-7-first-execution-phase-a.ledger.md docs/superpowers/plans/2026-09-13-jvm-milestone-7-first-execution-phase-a.md
STAMP="$(date +%F)T22:45:00+02:00"; GIT_AUTHOR_DATE=$STAMP GIT_COMMITTER_DATE=$STAMP git commit -q -F - <<'MSG'
Docs: milestone 7 Phase A closed -- the runtime levers, measured

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01GK4DKrQFQgNaiYirUzjcgJ
MSG
git push --force-with-lease ab5tract worktree-jesp-direct-lazy-records
git -C nqp push --force-with-lease ab5tract jesp-direct-lazy-records
```

(`ab5tract` is the fork remote both trees push to; check
`git remote -v` / `git -C nqp remote -v` first and use the name that
points at the ab5tract forks.) The rebase onto upstream main is the
milestone's close (spec "The close" step 6), not the phase's.

- [ ] **Step 5: Handoff**

Report to the user: the findings table, the Phase B baseline row, and
that the next session starts with `superpowers:writing-plans` on the
spec's Phase B section (lazy-loading tasks 1.1-1.6 by reference, site
identity, `unit.dispatch` reserved), then subagents on Opus. Remind the
user to leave the session rather than `/clear`.

## Done

- Rows base, a1, a2, a3, a4, a5, a7, a6 (and a8 if ruled) in the ledger
  and the findings doc, each with both hashes and a verdict.
- Every lever landed or struck; nothing measured twice except a ruled
  `a7r`.
- `tools/build/t/m7-rig.rakutest` and `truffle-trace-summary.rakutest`
  green; `nqp/t/nqp/125-dispatch-stats.t` and
  `t/02-rakudo/closure-static-clone.t` green; the nqp suite 154 green;
  `t/01-sanity` 25/25; warm `t/02-rakudo` with no red outside the
  baseline.
- Both branches pushed; memory updated; the Phase B plan named as next.
