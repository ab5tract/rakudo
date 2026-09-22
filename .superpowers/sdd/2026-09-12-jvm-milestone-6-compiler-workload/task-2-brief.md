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

