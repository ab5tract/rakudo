# Task 2 report: the compilation-trace summarizer

**Status: DONE.**

Commits (rakudo tree; `nqp/` untouched):

- `d92d405b80` — Tools: summarize a Truffle compilation trace (the three
  deliverables + the ledger entry).
- `da7b413cca` — Ledger: cite the Task 2 tool commit by its final hash
  (ledger only; see "The one process wrinkle" below).

Tests: **8 of 8 pass.** Smoke test: **`events=2 / done=2 / failed` absent /
`min-too-large-size=none` / `total-compiler-ms=93`** — the required positive
marker (`done=` above zero) is met.

---

## What was done, in the brief's order

**Step 1 — the fixture.** `tools/build/t/fixtures/trace-sample.log`, six lines.
Rather than retype them (the lines carry significant interior padding — the root
name is space-padded to a fixed column — and a single collapsed run of spaces
would have changed what the parser sees), I extracted lines 44–49 of the brief
with `sed -n '44,49p'`. `cat -A` confirms the six lines and their trailing
structure. The file is byte-for-byte the brief's block.

**Step 2 — the failing test.** `tools/build/t/truffle-trace-summary.rakutest`,
extracted the same way from the brief's lines 57–84. `plan 8`, eight assertions.

**Step 3 — RUN IT AND SEE IT FAIL.** Run before any tool existed:

```
1..8
Could not open tools/build/truffle-trace-summary.raku. Failed to stat file: no such file or directory
not ok 1 - counts the two successful compilations
not ok 2 - counts the two failed compilations
ok 3 - ignores lines that are not engine trace lines
not ok 4 - groups failures by their reason text
not ok 5 - reports the smallest wire size among too-large roots
not ok 6 - names the roots in the top-roots table
not ok 7 - reports the mean time of a reason group in ms
not ok 8 - says none when no root failed for size
# You failed 7 tests of 8
EXIT=7
```

Seven of eight failed. Test 3 is a `nok` assertion, and it passed against the
empty output of a tool that does not exist — see concern (a).

**Step 4 — the tool.** `tools/build/truffle-trace-summary.raku`, brief lines
100–159, extracted verbatim, `chmod +x`. Not one character was changed.

**Step 5 — the tests pass.** 8 of 8:

```
1..8
ok 1 - counts the two successful compilations
ok 2 - counts the two failed compilations
ok 3 - ignores lines that are not engine trace lines
ok 4 - groups failures by their reason text
ok 5 - reports the smallest wire size among too-large roots
ok 6 - names the roots in the top-roots table
ok 7 - reports the mean time of a reason group in ms
ok 8 - says none when no root failed for size
EXIT=0
```

The tool's own output on the fixture:

```
events=4
done=2
failed=2

--- failures by reason ---
  count=2  mean=6500ms  code installation failed: code is too large

min-too-large-size=48213

--- top 20 roots by compile time ---
     6600ms  failed  tier 2  parse_expr[91002]
     6400ms  failed  tier 2  parse_stmt[48213]
       72ms  done    tier 1  org.graalvm.polyglot.Value<Program>.execute
       37ms  done    tier 1  <anon>[0]

total-compiler-ms=13109
```

Every value the brief asserted came out on the first run of the finished tool.
That is the expected outcome given that the brief's author had already run both
files against the real fixture; it is also the evidence that the transcription
is faithful.

**Step 6 — the smoke test on a real workload.** `NqpCheck` under
`-Dpolyglot.engine.TraceCompilation=true`, java exit 0. The log's first lines:

```
NOTE: Picked up JDK_JAVA_OPTIONS: -Dpolyglot.engine.TraceCompilation=true
# Truffle runtime: Oracle GraalVM
ok - add
ok - fib
```

and the summary of it:

```
events=2
done=2

min-too-large-size=none

--- top 20 roots by compile time ---
       60ms  done    tier 1  org.graalvm.polyglot.Value<Program>.execute
       33ms  done    tier 1  <anon>[0]

total-compiler-ms=93
```

`done=2`, above zero: the instrument reads a real trace, not just the fixture.
The trace log itself is at `$CLAUDE_JOB_DIR/tmp/m6-smoke-trace.log` and is not
committed.

**Step 7 — commit.** Message and `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE`
(`2026-09-12 19:20:00 +0200`) exactly as the brief's final step shows, trailer
included. `git log -1 --format=%ad` reads back
`Sat Sep 12 19:20:00 2026 +0200`. Staged paths were only
`tools/build/truffle-trace-summary.raku`, `tools/build/t/`, and the ledger. The
working tree afterwards shows nothing modified — only the eight untracked
artefacts that were already there when the session opened.

---

## The field-driven property is intact

This is the part of the brief that is load-bearing for Task 3, so it is worth
stating what the committed tool actually guarantees. The parser splits a line on
`|`, takes the head for `verb`/`id`/`name`, and then, for each remaining field,
`.trim`s it and tests `^ 'Tier' \s+ (\d+)`, `^ 'Time' \s+ (\d+)`,
`^ 'Reason' \s+ (.+) $`. No field is read by its index. The consequence is the
one the brief wanted: the two unverified `opt failed` fixture lines commit the
tool to nothing except *that a field named `Reason` exists somewhere in the
tail*. If the real GraalVM failure line puts `Reason` in a different position,
or inserts fields before it, or drops `AST`/`Inlined`/`IR`/`CodeSize` (as the
fixture's failure lines already do relative to the success lines), the parse is
unaffected. Task 3 Step 4 still has to confirm the field *name*; nothing else
about those two lines is relied upon.

Two details of the tool worth recording for whoever reads its numbers:

- `Time  6400(6100+300 )ms` is read as the **total** (6400). The `(a+b)` split
  is discarded. The `mean=6500` assertion is `(6400+6600)/2`, so the test pins
  this reading.
- The `$<verb>` / `$<name>` captures are copied into plain scalars before the
  size regex runs. That is not fussiness: the size match replaces `$/`, and
  reading `$<verb>` afterwards would resolve against the wrong match. The
  brief's comment says so, and the code obeys it.

I verified the brief's claim about where the size comes from.
`nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java`:

```java
    @Override
    public String getName() {
        String n = blockName;
        return (n == null || n.isEmpty() ? "<anon>" : n) + "[" + programSize + "]";
    }
```

So every NQP root's trace line carries its wire-word count, and a root with no
bracket is not an NQP program — exactly as the brief says. The brief cites
lines 91–93; the method spans 90–94. Immaterial, noted only for exactness.

---

## Concerns

**(a) One of the eight assertions is nearly vacuous, and was vacuous at the
red stage.** `nok $out.contains('ok - warm add')` passed in Step 3 against the
empty output of a nonexistent tool. It is not *entirely* vacuous against a
working tool — a parser that wrongly accepted the noise line would print
`ok - warm add` as a root name in the top-roots table, and the assertion would
then catch it — but the guard that actually rejects the line is
`starts-with('[engine] opt ')`, and this assertion cannot distinguish "rejected
by the guard" from "the tool printed nothing at all". A strictly stronger
version would be `ok $out.contains('events=4')`, which pins the count of
accepted lines directly. I did **not** change it: the brief is explicit that
its text is the convention, and the assertion is not wrong, only weak. Flagging
it rather than editing it.

**(b) `total-compiler-ms` and the top-roots table count non-NQP roots.** In the
smoke run, one of the two events is
`org.graalvm.polyglot.Value<Program>.execute` — the polyglot entry point, 60 of
the 93 ms. On a short workload that is most of the "compiler time". On a CORE.c
run it will be noise, but Task 3 should still say, when it quotes a figure,
whether it means all roots or only the bracketed (NQP program) ones. The tool
currently offers no way to ask for the latter. This is an observation about how
to *read* the number, not a defect in the tool, and it needs no change unless
Task 3 wants the split.

**(c) The brief's Step 6 command does not run as one statement in this
harness.** It mixes `$CLAUDE_JOB_DIR` (a value the harness cannot resolve
statically) into a compound statement that ends in a `raku` invocation, and the
worktree-isolation guard refuses it as unverifiable. Split into two plain
commands with the job directory written out in full, it runs exactly as
intended. Not a defect in the brief's intent — worth knowing before Task 3
copies the recipe.

**(d) `min-too-large-size` would accept a size of 0.** A too-large failure on a
root named `foo[0]` would yield `min-too-large-size=0`, and Task 4 would then
set `NQP_CODE_MAX_COMPILE` to something absurd. This cannot happen in practice
(a zero-word program does not blow the code-size limit), so I left it alone;
recording it so that if Task 3's real trace ever prints `min-too-large-size=0`,
that is read as a bug and not as a threshold.

---

## The one process wrinkle

The ledger entry has to cite the commit that contains it, which is impossible in
a single commit: filling in the hash changes the hash. Task 1 hit the same thing
and resolved it in its own prose ("commit `aa0169ed5a` amended to
`1477806f7b`"). I resolved it with a second, ledger-only commit: the deliverable
commit is `d92d405b80` and is final; `da7b413cca` corrects the citation inside
it and says so in the ledger. Both are stamped
`2026-09-12 19:20:00 +0200` and carry the trailer. If the controller would
rather see a single commit, the two squash cleanly.

The ledger entry itself was **appended at the very end of the file**. Nothing
above it was touched — no `Ruling` line, no `Task 1:` line, no controller
annotation. The only edit to existing text was inside my own entry, replacing
the `PLACEHOLDER` hash with the real one.

## Files

- `tools/build/truffle-trace-summary.raku` — the summarizer (60 lines).
- `tools/build/t/truffle-trace-summary.rakutest` — 8 assertions.
- `tools/build/t/fixtures/trace-sample.log` — 6 lines.
- `docs/superpowers/plans/2026-09-12-jvm-milestone-6-compiler-workload.ledger.md`
  — appended.

`tools/build/t/` did not exist before this task; its shape is now the
convention for tool tests in this tree. The tests run under the system `raku`
(Rakudo on MoarVM v2026.07), need no build, and take under two seconds.

---

# Task 2 fix report — round 1 of 5

**Status: DONE.** Commit rakudo `3f14c9c6ed`, stamped
`2026-09-12 19:25:00 +0200`, the third on top of `d92d405b80` and
`da7b413cca` — neither of which was squashed or amended.

**Tests: 16 of 16 pass** (the suite grew from 8 assertions to 16).

```
1..16
ok 1 - counts the two successful compilations
ok 2 - counts the two failed compilations
ok 3 - ignores lines that are not engine trace lines
ok 4 - groups failures by their reason text
ok 5 - reports the smallest wire size among too-large roots
ok 6 - names the roots in the top-roots table
ok 7 - reports the mean time of a reason group in ms
ok 8 - accepts every trace line in the fixture
ok 9 - no [engine] opt line is dropped without a tally
ok 10 - parses Reason with and without the colon
ok 11 - a root name containing | is not split mid-name
ok 12 - shows the population behind the minimum, not just the minimum
ok 13 - totals every root
ok 14 - totals the bracketed (NQP) roots separately
ok 15 - says so loudly when failures parsed but their reasons did not
ok 16 - says none when no root failed for size
```

## CRITICAL 1 — the colon

**I saw it fail before I fixed it.** This matters more than the fix, so it goes
first. I rewrote the fixture into the real `|Reason: %s|` spelling and wrote the
new assertions, then ran the suite against the *shipped* tool:

```
not ok 4 - groups failures by their reason text
not ok 5 - reports the smallest wire size among too-large roots
```

That is the defect reproducing live, in this tree, exactly as described: the
reason parsed as the empty string and `min-too-large-size` printed `none` on a
trace with two too-large roots in it. Note also that assertion 7 (`mean=6500`)
kept passing throughout — the failures still grouped, just under an empty key.
That is precisely why the bug was survivable: the tool went on producing a
well-formed report about nothing.

Three changes, as directed:

(a) The field match is now `^ 'Reason' ':'? \s+ (.+) $`. Strictly wider than
either spelling alone, so it cannot regress the colon-free verbs.

(b) Fixture lines 4 and 5 now carry `|Reason: ...`, differing from the brief's
original text *only* in that colon — I edited them with `sed` on the existing
file rather than retyping, so every column of the `%-50s` padding is unchanged.
A new sixth line, `opt deopt`, carries the colon-free `|Reason ` spelling so
that form stays covered: deopt and invalidation lines genuinely have no colon
and must keep parsing. Assertion 10 (`reasons-parsed=3`) is what proves both
spellings work — three of the five events carry a reason, two colonful and one
colon-free, and all three parse.

(c) The empty case is loud. When there are failed events but zero parsed
reasons, the line reads

```
min-too-large-size=none  (failed=1, reasons-parsed=0)
```

and the reason group prints `(no Reason field parsed)` instead of a blank. A
second fixture, `fixtures/trace-noreason.log`, is a failure line whose field is
named `Why:` instead of `Reason:` — a stand-in for the next format change — and
assertion 15 pins that exact output string. A future rename cannot go quiet
again; it will print a sentence saying it went blind.

I also added `reasons-parsed=` to the header block unconditionally, so the count
is visible on every run and not only in the alarm case.

## IMPORTANT 2 — silent drops, and `|` in root names

The line is no longer split on `|` at all. The head is cut at the **first
whitespace-then-`|`**, which is how every one of these formats separates the
`%-50s` name from the fields (`... %-50s |Tier ...` — the space is literal in
the format string), and only the tail is split into fields. A `|` inside a root
name is never preceded by whitespace: `infix:<|>`, `infix:<+|>`, `infix:<|=>`
all put an operator character immediately before the bar. So the name survives
whole, its bracketed size with it, and it stays in the min-too-large-size
population where it belongs. Assertion 11 feeds `infix:<+|>[12345]` through and
requires the full name back.

Both discard paths are now tallied, and both counts print:

- `unparsed=N` — lines that start with `[engine] opt ` but fail the head match.
  This is the one the reviewer asked for; it is the "I saw something I did not
  understand" counter, and on a real run it should stay 0.
- `non-trace-lines=N` — everything else. Not requested, but it is the other
  `next`, and the finding said *both* discard a line with no tally. It is also
  independently useful: `events=0, non-trace-lines=40000` tells you the trace
  flag never took effect, which `events=0` alone does not.

## IMPORTANT 3 — the population behind the minimum

`min-too-large-size` is now followed by its evidence:

```
min-too-large-size=48213
  too-large roots: 2 (2 sized, 0 unsized)
  by size: parse_stmt[48213], parse_expr[91002]
```

and, when any too-large root lacks a bracket, a line that names the danger
rather than merely reporting a number:

```
  UNSIZED (excluded, so the minimum above reads high): <name>, <name>
```

The unsized roots were previously filtered out by `.defined` with no trace, and
the reviewer is right that this is the worse direction: excluding them raises
the minimum, so Task 4 sets the threshold too high and the knob skips nothing.
Assertion 12 pins the population line. The `unsized` count is 0 in the fixture,
which pins the format but not the message; if Task 3's real trace ever prints a
nonzero `unsized`, that line is the one to read before trusting the threshold.

## IMPORTANT 4 — two populations, two numbers

`total-compiler-ms=` is unchanged, and `nqp-root-ms=` now sits beneath it,
summing only roots whose name carries a bracket. On the fixture: 13109 total,
13037 NQP — the 72 ms difference being the polyglot entry point. Assertions 13
and 14 pin both. Task 3 no longer has to remember a caveat; it can quote
whichever number it means and say which.

## Verification against reality, not just the fixture

Two checks beyond the suite, as instructed.

**The Step 6 smoke log still parses.** Re-run against the same real trace:

```
events=2
done=2
unparsed=0
non-trace-lines=11
reasons-parsed=0

min-too-large-size=none

--- top 20 roots by compile time ---
       60ms  done    tier 1  org.graalvm.polyglot.Value<Program>.execute
       33ms  done    tier 1  <anon>[0]

total-compiler-ms=93
nqp-root-ms=33
```

`events=2`, `unparsed=0` — the head-cut rewrite did not break the real success
lines, and the 11 non-trace lines are the `NOTE:`, the runtime banner and the
`ok - ...` results, all correctly classified as noise.

**A line in the verbatim `FAILED_FORMAT` now parses.** I did not hand-pad this;
I fed the reviewer's format string to `sprintf` so the spacing is whatever the
format produces:

```
[engine] opt failed engine=1  id=77    statement_control[31337]                           |Tier 2|Time  6400(6100+300 )ms|Reason: code installation failed: code is too large|UTC 2026-09-12T09:47:56.100|Src n/a
```

```
events=1
failed=1
unparsed=0
reasons-parsed=1

--- failures by reason ---
  count=1  mean=6400ms  code installation failed: code is too large

min-too-large-size=31337
  too-large roots: 1 (1 sized, 0 unsized)
  by size: statement_control[31337]
```

`min-too-large-size=31337` — a number, where the shipped tool would have printed
`none`. That is the finding closed against the real format rather than against
my transcription of it.

## Notes on what I committed

- The fix commit necessarily carries the controller's own uncommitted ledger
  additions (the Critical 1 write-up and the three deferred minors) — the
  ledger is a single file and my entry had to append to it. Nothing above my
  appended lines was touched.
- `docs/superpowers/plans/2026-09-12-jvm-milestone-6-compiler-workload.md` also
  had uncommitted controller edits (the Task 3 Step 4 rewrite). I left it
  **uncommitted**, being outside the implementer's commit scope. It is still
  sitting modified in the working tree.
- The three deferred minors were left alone as instructed: the `tier 0` / `ms 0`
  defaults, `fixtures/empty.log` in the repo rather than `$*TMPDIR`, and the
  `NqpRootNode.java` line-number nit.

## One residual, recorded not fixed

The tool still splits the field tail on `|` unconditionally, so a reason text
that itself contained a `|` would be truncated at the bar. Field-by-leading-word
matching means the truncation is silent — the reason would simply be short.
`code installation failed: code is too large` has no bar, and no Truffle reason
string I have seen does, so this is theoretical; I mention it because it is the
same shape of bug as Critical 1 (punctuation inside a field rather than a field
reordering), and it is the next place that shape could hide.

---

# Task 2 fix report — round 2 of 5

**Status: DONE.** Commit rakudo `d9a77d1fb5`, stamped
`2026-09-12 19:35:00 +0200`, the fourth. Nothing squashed; `d92d405b80`,
`da7b413cca` and `3f14c9c6ed` stand as they were.

**Tests: 21 of 21 pass** (the suite grew 16 → 21).

**On a trace mixing both bailout spellings: `min-too-large-size=900`.**
Before the fix, the same trace printed `min-too-large-size=48213`.

## The red run, first

Both findings reproduced against the round-1 tool before a line of it changed.
I added the fixture lines and the assertions, ran the suite, and six failed:

```
not ok  5 - reports the smallest wire size among too-large roots
not ok 12 - a reason text containing | is not truncated at the pipe
not ok 13 - every spelling of a size bailout joins the population
not ok 14 - shows the population behind the minimum, not just the minimum
not ok 15 - prints unclassified failure reasons with the sizes behind them
not ok 19 - an unrecognised bailout spelling is named and sized, never silent
```

and the tool printed both symptoms verbatim, which is worth quoting because it
is the reviewer's description reproduced exactly:

```
--- failures by reason ---
  count=2  mean=6500ms  code installation failed: code is too large
  count=1  mean=5100ms  inlining of infix:<+
  count=1  mean=300ms  inlining budget exhausted
  count=1  mean=5200ms  too big to safely compile. Node count: 41234

min-too-large-size=48213
  too-large roots: 2 (2 sized, 0 unsized)
  by size: parse_stmt[48213], parse_expr[91002]
```

`inlining of infix:<+` — the truncation, mid-operator. And
`min-too-large-size=48213` with a 900-word and a 1500-word root sitting two
lines above it in the same report, both of which failed for size and neither of
which made the population. A number, plausible, fifty times too high. Note also
that the round-1 `reasons-parsed` guard correctly did *not* fire: the reasons
parsed fine. This is Critical 1's failure mode reached by a route that every
round-1 defence was blind to, exactly as the finding says.

## FINDING A — "code is too large" is not the only spelling

**(a) The selector.** A named substring alternation:

```raku
my @SIZE-BAILOUT-SPELLINGS = 'code is too large', 'too big to safely compile', 'exceeds';
sub size-bailout($reason --> Bool) {
    so @SIZE-BAILOUT-SPELLINGS.first({ $reason.contains($_) });
}
```

Substrings, not exact matches, so `too big to safely compile. Node count: 41234`
matches on its stem and the node count rides along into the report where a human
can read it.

**(b) The part that matters more.** I agree with the reviewer's framing that any
list I write today goes stale, so the unclassified report is the real fix. Every
parsed failure reason that matched no spelling is now printed beneath the
minimum, named, with the sizes of the roots carrying it:

```
min-too-large-size=900
  too-large roots: 4 (4 sized, 0 unsized)
  by size: graph_bail[900], inline_pipe[1500], parse_stmt[48213], parse_expr[91002]
  unclassified failure reasons (not matched as a size bailout):
    count=1  sizes: 700  inlining budget exhausted
```

The fixture was built so that this report tells the dangerous story on sight:
`sizes: 700` sits directly under `min-too-large-size=900`. A size in the
unclassified block *below* the stated minimum is the alarm — it says the minimum
is reading high and a threshold taken from it would miss that root. The comment
in the source says so, in those terms, so whoever reads the output next does not
have to rediscover it.

The block prints whether or not the population is empty, which is the case the
reviewer specifically flagged: when *only* an unknown spelling occurs, the
minimum is honestly `none` but the evidence is still on screen.
`fixtures/trace-unknown-bailout.log` pins exactly that:

```
min-too-large-size=none
  unclassified failure reasons (not matched as a size bailout):
    count=1  sizes: 555  graph too chunky for the backend
```

## FINDING B — the tail, mirrored on the head

The reviewer is right that round 1 fixed one end of the line and left the other.
A tail piece that does not look like the start of a field is now rejoined to the
piece before it:

```raku
sub field-start($piece --> Bool) {
    so $piece ~~ / ^ <[A..Z]> \w* ':'? \s /;
}
```

`Tier 1`, `Time  6400(...)ms`, `AST    3`, `Inlined   0Y   0N`, `IR  309/ 639`,
`CodeSize  3948`, `Addr 0x...`, `CompId 2010`, `UTC ...`, `Src n/a` and
`Reason: ...` all satisfy it; the continuation `> failed: code is too large`
does not, and is glued back on with its `|` restored.

I chose a shape test over a list of known field names deliberately, and the
reason is the same one that produced both Criticals: a closed list of names is
what breaks when the format moves. With a shape test, an unfamiliar future field
still reads as a field. And the asymmetry of the failure modes matters — if the
heuristic ever guesses wrong, the result is an over-long value (a reason with a
stray field glued to its end, which still *contains* its spelling and still
matches) and never a truncated one (which matches nothing). The tool degrades
toward noise rather than toward silence.

Note the interaction the reviewer flagged, which is why these two are one
commit: a truncated reason cannot match any spelling, so Finding B defeated
Finding A's fix. `inlining of infix:<+|> failed: code is too large` is both a
pipe-in-reason case and a size bailout, and it is in the fixture as one line
carrying both.

## What the fixture and suite gained

Three lines added to `trace-sample.log`, all generated by `sprintf` from the
verbatim `FAILED_FORMAT` rather than hand-padded:

- `graph_bail[900]` — `too big to safely compile. Node count: 41234`
- `inline_pipe[1500]` — `inlining of infix:<+|> failed: code is too large`
- `misc_fail[700]` — `inlining budget exhausted`, classifiable as nothing

plus `fixtures/trace-unknown-bailout.log`, a single failure on an invented
spelling. Five assertions are new (the by-size membership line, the untruncated
pipe reason, the unclassified block, and two on the unknown-spelling fixture);
seven existing ones were re-valued for the grown fixture (`failed=5`,
`events=8`, `reasons-parsed=6`, `min-too-large-size=900`, `too-large roots: 4`,
`total-compiler-ms=23709`, `nqp-root-ms=23637`).

The by-size assertion is worth calling out as the strongest one in the file:

```raku
ok $out.contains('by size: graph_bail[900], inline_pipe[1500], parse_stmt[48213], parse_expr[91002]'),
```

It pins membership, spelling coverage and sort order in a single string, and it
is the assertion that would fail first if a future change quietly dropped a
spelling again.

## Reality checks, re-run

Nothing regressed on real data:

- The Step 6 smoke trace: `events=2 done=2 unparsed=0 non-trace-lines=11`,
  unchanged. The rejoin rule did not mis-handle any real field on the real
  success lines.
- The round-1 line built from the verbatim `FAILED_FORMAT`: still
  `min-too-large-size=31337`, still the full reason text.

## One residual, narrowed

Round 1 recorded that a `|` inside a field value would be truncated; that is now
fixed, and the residual shrinks to its last corner: a reason whose continuation
after a `|` happens to itself begin like a field (`...|Tier one problem`) would
be read as a new field. It cannot lose data — the piece is still parsed, just as
a field nobody matches — and it cannot truncate a spelling match unless the bar
falls inside the spelling itself. I am recording it rather than defending
against it, because defending would mean the closed name list I just argued
against.

---

# Task 2 fix report — round 3 of 5

**Status: DONE.** Commit rakudo `0b8424bd1c`, stamped
`2026-09-12 19:40:00 +0200`, the fifth. Nothing squashed.

**Tests: 22 of 22 pass** (the suite grew 21 → 22).

**On the re-reviewer's trace — `tiny[40]` failing on the inlining budget
alongside a genuine `big[48213]` size bailout — the tool now reports
`min-too-large-size=900`** (900 being the smallest genuine bailout in my
fixture; in a trace containing only `tiny[40]` and `big[48213]` it reports
48213). Before the fix, the same fixture reported `min-too-large-size=40`.

## The red run

I added `tiny[40]` to the fixture in the `FAILED_FORMAT`, reason
`inlining of foo exceeds the inlining budget`, and ran the suite against the
round-2 tool. Four assertions failed, and the misfire printed exactly as
described:

```
min-too-large-size=40
  too-large roots: 5 (5 sized, 0 unsized)
  by size: tiny[40], graph_bail[900], inline_pipe[1500], parse_stmt[48213], parse_expr[91002]
  unclassified failure reasons (not matched as a size bailout):
    count=1  sizes: 700  inlining budget exhausted
```

A 40-word root at the head of the population, and the unclassified block —
the tool's own alarm — silent about it, because `exceeds` had matched. The
report looks entirely healthy. That is the whole problem.

## The fix

One entry deleted:

```raku
my @SIZE-BAILOUT-SPELLINGS = 'code is too large', 'too big to safely compile';
```

The comment beside it is the substance, and I wrote it to carry the reasoning
rather than the rule, because the rule is easy to re-break:

> ONLY SPELLINGS VERIFIED TO EXIST IN THIS TREE BELONG HERE. Nothing guessed,
> and in particular nothing as loose as a bare `exceeds` [...] A guessed
> spelling does not extend this tool's reach; it bypasses the mechanism that
> already covers the unknown. [...] A too-loose entry here converts that loud
> unknown into a silent wrong answer, and a wrong threshold is invisible to the
> tool's own alarm by construction: a reason that matched a spelling is, by
> definition, not unclassified. When a real trace shows a size bailout this list
> does not know, it will appear in that block — add it here THEN, with the
> trace that proves it.

That last sentence is the part I most wanted in the file: it gives the next
person the procedure, so the next spelling arrives with evidence attached
instead of by inference.

## The assertion

One new assertion, as directed:

```raku
ok  $out.contains('sizes: 40  inlining of foo exceeds the inlining budget'),
    'an inlining-budget message is unclassified, never a size bailout';
```

The other half of the requirement — that the root must *not* enter the
population — is already carried by three assertions that existed before this
round: `min-too-large-size=900`, the exact `by size:` membership line, and
`too-large roots: 4 (4 sized, 0 unsized)`. All three failed in the red run and
pass now, which is the coverage working as intended rather than an accident;
the by-size line in particular fails loudly because `tiny[40]` sorts to the
front of it. So the single new assertion is genuinely all that was missing.

Seven existing assertions were re-valued for the grown fixture (`failed=6`,
`events=9`, `reasons-parsed=7`, `total-compiler-ms=23829`,
`nqp-root-ms=23757`, and the two counts above were already correct at 900/4
once `exceeds` was gone).

Result after the fix:

```
min-too-large-size=900
  too-large roots: 4 (4 sized, 0 unsized)
  by size: graph_bail[900], inline_pipe[1500], parse_stmt[48213], parse_expr[91002]
  unclassified failure reasons (not matched as a size bailout):
    count=1  sizes: 40  inlining of foo exceeds the inlining budget
    count=1  sizes: 700  inlining budget exhausted
```

`tiny[40]` is out of the population and on screen, which is precisely the
disposition the finding asked for.

## I agree with the finding, and with its framing

Recording this because it is worth more than the edit. My round-2 report argued
that a shape test beats a name list because "the tool degrades toward noise
rather than toward silence". `exceeds` was the same argument run backwards: it
degraded toward a confident wrong number. I took it from the round-1 brief
without asking what it was for, and a loose substring in a classifier that sets
a threshold is exactly the thing my own reasoning should have caught. The
asymmetry that makes the shape test safe — over-long beats truncated — has no
counterpart here; there is no safe direction for a misclassification that feeds
`NQP_CODE_MAX_COMPILE`.

## New observation, NOT fixed — tied groups reorder between runs

Round 3's fixture created the first tie in a `.classify(...).sort(-*.value.elems)`
group (two unclassified reasons, both `count=1`), and that made a latent
nondeterminism visible. Five consecutive runs of the identical trace:

```
    700 then 40
    40  then 700
    700 then 40
    700 then 40
    40  then 700
```

`classify` returns a Hash, and Raku's sort is stable, so tied groups inherit
MoarVM's hash iteration order, which varies per process. The same applies to the
`--- failures by reason ---` block, which has had ties since round 2 and has
been reordering all along without anyone noticing.

Nothing is *wrong*: no number changes, and no assertion is at risk because they
all use `contains`. But this is a measurement instrument whose output Task 3
will very likely diff between runs, and two runs of one trace currently produce
textually different reports. The fix is a tiebreak key, roughly
`.sort({ (-.value.elems, .key) })` on both blocks.

I have **not** made that change. This round was scoped to one line plus a test,
scope is the controller's to set, and I have just finished writing a report about
the cost of doing a little extra reasoning on my own authority. It is recorded in
the ledger for round 4 to accept or decline.

## Parked residual acknowledged

The partial reason-parse route is noted and left alone: one `opt failed` line's
reason parsing while another's does not would give a silent too-high minimum,
since the `reasons-parsed=0` guard only fires when *no* reason parsed and the
unclassified block skips empty reasons. As the controller says, `FAILED_FORMAT`
is a single constant so all such lines share one shape, which is what makes the
route hard to reach in practice.
