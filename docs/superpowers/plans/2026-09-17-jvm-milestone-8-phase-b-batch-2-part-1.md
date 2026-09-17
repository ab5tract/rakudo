# Milestone 8 Phase B, batch 2, part 1: the retake and the classlib road trim Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retake the census and the JFR profile on the batch 1 tree (CORE.c included, which batch 1 skipped), settle batch 1's open red, fix the census tooling, split `NqpTypeOps.kt`, then replace the generic classlib road's per-call work (two `Object[]`s, a spreading and boxing handle adapter) with arity-typed nodes and one exact handle per instruction, measured as rig row `b2a` with CORE.c as a first-class clock.

**Architecture:** A new Kotlin object `NqpClassLibRoad` holds one `TypedSite` per CLASSLIB instruction (the registry row, the result type, one `@CompilationFinal` MethodHandle adapted once to a uniform type per arity and flavour) and the typed `@TruffleBoundary` calls. Eight new Bytecode DSL operations in `NqpRootNode.java` (`ClassLib0`..`ClassLib4` answering `Object`, `ClassLibLong1`..`ClassLibLong3` answering `long`) replace the variadic `ClassLibOp` for arity 0-4; the variadic node stays for arity 5-6 and under `NQP_SITES_OFF=classlib`. The suspension protocol (store local, `emitSuspendCheck`, token typed by the op's result) is unchanged on the Object flavour; the long flavour serves only context-free ops, which cannot reach guest code and so cannot capture, and flows its value on unboxed with no wrapper.

**Tech Stack:** Kotlin (nqp-truffle: the road, the census, the split), Java only for the Bytecode DSL node classes and the builder (`NqpRootNode.java`, `NqpProgramBuilder.java`), nqp `.t` tests under `prove` with child processes reading the census, Raku tools (`m7-rig.raku`, `evalserver-sweep.raku`, `jfr-attribute.raku`, `watched-run.raku`).

**Spec:** `docs/superpowers/specs/2026-09-16-jvm-milestone-8-phase-b-promotion-campaign-design.md`, Revision 3: section 6.1 (the opening), 6.2 (the trim), 6.5 (gates, rows), and the amended section 4 (the retake rule, CORE.c as a clock) and 5 (the stop rule). Ledger of record: `docs/superpowers/plans/2026-09-16-jvm-milestone-8-phase-b.ledger.md` (the B0 baseline and the B1 section every number here is compared against).

## Global Constraints

- **Worktree only:** `/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records` (rakudo, branch `worktree-jesp-direct-lazy-records`, tip `df7c0339e6`) and its nested `nqp/` (nqp.git, branch `jesp-direct-lazy-records`, tip `76d88cf32`). The session's tool shell is worktree-isolated: it refuses `cd`, shell variables in paths and `&&` chains it cannot verify. Write every command with its paths spelled out, one command per call; run `prove` from the nqp tree as `raku -e 'exit run(<prove --exec ./nqp-j-gradle t/jvm/22-classlib-road.t t/jvm/21-op-sites.t t/jvm/20-op-census.t>, :cwd("nqp")).exitcode'` (the tests spawn `./nqp-j-gradle` relative to their cwd). `git` in the rakudo tree needs `--ignore-submodules=all` for `status`/`diff`. Push to `ab5tract` only, never `origin`.
- **Engine-jar only.** No encoder row, no wire change, no stage0 regen, no `make`. Rebuild: `./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars` (seconds) from the rakudo worktree root; retrain after every jar rebuild: `RAKUDO_RAKUAST=1 NQP_DISPATCH_RECORD=all /usr/bin/perl rakudo-j-build -e '' 2>&1 | grep -E 'dispatch-record: (done|FAILED)'`; restart any eval server afterwards.
- **Kotlin for the road, the census and the split; Java only for the DSL node classes and the builder** (the standing exception). Kotlin calls a `MethodHandle` with `invokeExact(...) as Any?` / `as Long` (the `P6TYPECHECKRV_CACHEABLE` precedent in `NqpTypeOps.kt`: a `java.lang.Long.TYPE` handle invoked `as Long` is a primitive `long` call site).
- **Ruling 1 (a deviation from spec 6.2's example list, to be recorded in the ledger):** the `long` flavour serves only classlib ops **without** a thread context (`tcArg == false`) of arity 1-3 with an INT/UINT result. A `:tc` op may run guest code and must answer a suspend token on a capture, which a `long` cannot carry, and a raw capture is an error (`NqpCodeEngine.java:108`, `nonSuspendable`). So `chars`, `eqat`, `iseq_s`'s classlib form are `long`; `elems`, `existskey`, `getattr_i` stay Object-flavoured (a boxed `Long` result, no arrays, no adapter) until 6.3 sites them.
- **Ruling 2:** the typed road lives in Kotlin (`NqpClassLibRoad.kt`); the variadic road and its `NqpOps.ClassLibSite` stay as they are in `NqpOps.java` (arity 5-6 and the kill-switch use them).
- **Ruling 3 (tooling):** the census block a sweep or the rig reads is the LARGEST block by `table=` total among the `op census:` headers in the text, not the first header. A sweep's captured text can hold several JVMs' censuses (helper processes under `NQP_OP_CENSUS` print one each); the server's is the largest.
- **Every debug print env-gated** (`if (TRACE != null)` in Kotlin; `nqp::getenvhash` in nqp).
- **Tests:** `nqp/t/jvm/22-classlib-road.t` (new, Task 5); the trio `22-classlib-road.t 21-op-sites.t 20-op-census.t` is the per-task engine gate; the nqp suite (`./nqp/gradlew -p nqp testNqp`) after Tasks 4 and 5; warm `t/01-sanity` in Task 6.
- **Gates and rows:** every gate and benchmark reported with its wall time; a failed benchmark run is recorded as not gathered and never re-run; `NQP_OP_CENSUS`, `NQP_DISPATCH_RECORD`, `NQP_SITES_OFF`, `NQP_CLASSLIB_INLINE` must be unset in the shell that runs a timed row.
- **Commits:** one per task; nqp commits in the nqp tree, rakudo commits (tools, ledger, memory pointers) in the rakudo tree; `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE` in the 19:20-21:30 window of 2026-09-17 +0200, increasing across tasks (Task 1 19:20, Task 2 19:45, Task 3 20:00, Task 4 20:15, Task 5 20:45, Task 6 21:10); trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Temporary files under `/home/longwalker/.claude/jobs/584f1b84/tmp` (written `$T` below for reading only; spell it out in commands).
- No jar commits (stage0's nine v2 jars stay an uncommitted working-tree change).

---

## File structure

nqp tree (`nqp/`):
- `nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpClassLibRoad.kt` — NEW (Task 5): `TypedSite`, `site(...)`, `resolve`, the Object-flavour calls `obj0..obj4` (boundary) / `call0..call4` (PE-visible, the `NQP_CLASSLIB_INLINE` variant), the long-flavour calls `long1..long3` / `callLong1..callLong3`, the `JESP_TRACE_CLASSLIB` trace.
- `nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpSiteOps.kt` — NEW (Task 4): the batch 1 sites (`iscont`, `istrue`/`isfalse`/`NO_SITE`, `findmethod`/`FIND_*`) moved verbatim out of `NqpTypeOps.kt`.
- `nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt` — Task 4: the three sections removed; `miss`, `republished`, `debug`, `suspendedIn`, `truthy` become `internal`.
- `nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpCensus.kt` — Task 5: `classlib(site)` accepts both site kinds; `classlibTyped(site)`; `classlibTyped=` on the header.
- `nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java` — Task 4: references to the moved sites; Task 5: eight operations after `ClassLibOp`.
- `nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java` — Task 4: references; Task 5: the CLASSLIB case, `beginTyped`/`endTyped`, the `classlib` kill-switch name in the class comment.
- `t/jvm/22-classlib-road.t` — NEW (Task 5).

rakudo tree:
- `tools/build/evalserver-sweep.raku` — Task 1: `census-block` selects the largest block; `--census-block=FILE` for its test.
- `tools/build/m7-rig.raku` — Task 1: `parse-census` selects the largest block.
- `docs/superpowers/plans/2026-09-16-jvm-milestone-8-phase-b.ledger.md` — Tasks 2, 3, 6: the B2 sections.
- `m7-rig/` (untracked) — the rows and census files.

---

### Task 1: the census block selection (tools)

**Files:**
- Modify: `tools/build/evalserver-sweep.raku:139-157` (`census-block`) and its `MAIN` multis
- Modify: `tools/build/m7-rig.raku:72-80` (`parse-census`)
- Test: a fixture `/home/longwalker/.claude/jobs/584f1b84/tmp/census-two-blocks.txt`

**Interfaces:**
- Produces: `sub largest-census-block(Str $text --> Str)` in each script (the same twelve lines, the two scripts are standalone); `evalserver-sweep.raku --census-block=FILE` prints the selected block; `m7-rig.raku --parse-census=FILE` reads the selected block.
- Consumes: the census text shape (`op census: table=N classlib=N siteCalls=N siteMisses=N`, then `  table `, `  classlib `, `  site ` lines).

- [ ] **Step 1: Write the fixture that the current code gets wrong**

Write `/home/longwalker/.claude/jobs/584f1b84/tmp/census-two-blocks.txt`:
```
dispatch stats: hits=1 misses=1
op census: table=12 classlib=3 siteCalls=0 siteMisses=0
  table 12 say
  classlib 3 Ops.decont
  site DecontSite calls=3 misses=0 pins=0 republished=0 slow=[]
t/01-sanity/01-tap.t .. ok
op census: table=5000 classlib=9000 siteCalls=100 siteMisses=2
  table 5000 push
  classlib 9000 Ops.elems
  site DecontSite calls=100 misses=2 pins=0 republished=0 slow=[]
  site IsTrueSite calls=50 misses=0 pins=0 republished=0 slow=[]
```

- [ ] **Step 2: Run the rig's parser on it to see the wrong pick**

Run: `raku tools/build/m7-rig.raku --parse-census=/home/longwalker/.claude/jobs/584f1b84/tmp/census-two-blocks.txt`
Expected today: `table=12 classlib=3 ...` with `top-table: say=12 push=5000` — the first header and both blocks' lines mixed. That is the bug.

- [ ] **Step 3: Add the selector to the rig and use it**

In `tools/build/m7-rig.raku`, add above `parse-census`:
```raku
# The text a census is read from can hold several JVMs' blocks (a sweep
# captures every process started under NQP_OP_CENSUS, helpers included);
# the one to read is the largest by its table total. Blocks are the runs
# of census-shaped lines from one `op census:` header to the next; other
# lines (dispatch stats, TAP) may be interleaved and are dropped.
sub largest-census-block(Str $text --> Str) {
    my @blocks;
    for $text.lines {
        if .starts-with('op census:') { @blocks.push([$_]) }
        elsif @blocks && (.starts-with('  table ') || .starts-with('  classlib ') || .starts-with('  site ')) {
            @blocks.tail.push($_)
        }
    }
    return '' unless @blocks;
    @blocks.max({ .[0] ~~ / 'table=' (\d+) / ?? +$0 !! -1 }).join("\n")
}
```
and change `parse-census` to read from the selected block:
```raku
sub parse-census(Str $raw) {
    my $text = largest-census-block($raw);
    my %r;
    if $text ~~ / 'op census: table=' (\d+) ' classlib=' (\d+) ' siteCalls=' (\d+) ' siteMisses=' (\d+) / {
        %r<table> = +$0; %r<classlib> = +$1; %r<site-calls> = +$2; %r<site-misses> = +$3;
    }
    %r<top-table> = $text.lines.grep(*.starts-with('  table ')).head(8).map({ .words[2] ~ '=' ~ .words[1] }).join(' ');
    %r<top-classlib> = $text.lines.grep(*.starts-with('  classlib ')).head(8).map({ .words[2] ~ '=' ~ .words[1] }).join(' ');
    %r
}
```

- [ ] **Step 4: Run the parser again**

Run: `raku tools/build/m7-rig.raku --parse-census=/home/longwalker/.claude/jobs/584f1b84/tmp/census-two-blocks.txt`
Expected: `table=5000 classlib=9000 siteCalls=100 siteMisses=2 top-table: push=5000 top-classlib: Ops.elems=9000`.

- [ ] **Step 5: The same selector in the sweep, plus a way to run it**

In `tools/build/evalserver-sweep.raku`, replace `census-block` (lines 139-157) with the same `largest-census-block` sub (identical text, the comment included, plus one line: `# Kept identical to m7-rig.raku's copy; the two scripts are standalone.`), rename the one call at line 118 to `largest-census-block($out)`, and add a `MAIN` multi next to the existing ones:
```raku
#| Print the census block the sweep would lift out of FILE (the largest block); a test hook.
multi sub MAIN(Str :$census-block!) { say largest-census-block($census-block.IO.slurp) }
```

- [ ] **Step 6: Run the sweep's hook on the fixture**

Run: `raku tools/build/evalserver-sweep.raku --census-block=/home/longwalker/.claude/jobs/584f1b84/tmp/census-two-blocks.txt`
Expected: exactly the five lines of the second block, nothing from the first, no TAP line.

- [ ] **Step 7: Confirm the real b1 sanity log now reads as one block**

Run: `raku tools/build/m7-rig.raku --parse-census=m7-rig/b1-sanity-census.log`
Expected: one set of totals (the header the B1 ledger section quotes: the sanity totals of row b1) and a `top-table` list without repeats.

- [ ] **Step 8: Commit (rakudo tree)**

```bash
GIT_AUTHOR_DATE='2026-09-17 19:20:00 +0200' GIT_COMMITTER_DATE='2026-09-17 19:20:00 +0200' git commit tools/build/evalserver-sweep.raku tools/build/m7-rig.raku -m "Tools: a census reader takes the largest block, not the first header (milestone 8, B2)

A sweep's captured text holds one op census per JVM started under the
knob, helpers included, and the rig read the first header while the
sweep lifted every census line by prefix -- the triple site block of
row b1's sanity census. Both now select the largest block by its table
total; --census-block=FILE on the sweep is the test hook.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: the retake and the spike (measurements, no code)

**Files:**
- Modify: `docs/superpowers/plans/2026-09-16-jvm-milestone-8-phase-b.ledger.md` (new section `## B2, the opening: the retake` after the B1 section)
- Produces: `m7-rig/b1r-*` files, `m7-rig/rows.md` row `b1r`

**Interfaces:**
- Consumes: Task 1's readers; the rig's `--census` (one knob-on run and one JFR run per cold row, a knob-on warm proxy); `tools/build/jfr-attribute.raku --ops`.
- Produces: the "before" column of every B2 row: per-workload census totals and top names on the batch 1 tree, the CORE.c census, the CORE.c JFR `--ops` container shares, the spike's shares.

- [ ] **Step 1: Make the jars and the training current**

Run, from the worktree root:
```
./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars
```
then
```
RAKUDO_RAKUAST=1 NQP_DISPATCH_RECORD=all /usr/bin/perl rakudo-j-build -e '' 2>&1 | grep -E 'dispatch-record: (done|FAILED)'
```
Expected: `BUILD SUCCESSFUL` (seconds) and `dispatch-record: done ... 0 failed`. Record both walls.

- [ ] **Step 2: The rig with the census (the three cheap workloads)**

Run:
```
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/584f1b84/tmp/rig-b1r.log --show='m7-rig:' --stall=900 -- raku tools/build/m7-rig.raku --tag=b1r --out=m7-rig --census
```
Expected: `m7-rig: DONE tag=b1r`, the row appended to `m7-rig/rows.md`, files `m7-rig/b1r-{rakudo-e,nqp-e}-{census,jfr}.err`, `m7-rig/b1r-{rakudo-e,nqp-e}-jfr.txt`, `m7-rig/b1r-sanity-census.log`. This row is the retake's REFERENCE on today's machine, recorded in the ledger as such and NOT a row of the series (no stop-rule reading from it).

- [ ] **Step 3: The CORE.c census compile**

Run (the Makefile's own recipe shape, output to the job dir so the build's jar is untouched):
```
RAKUDO_RAKUAST=1 NQP_OP_CENSUS=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/584f1b84/tmp/corec-census-b1r.log --show='Stage' --show='op census' --stall=900 -- ./rakudo-j --setting=NULL.c --ll-exception --optimize=3 --target=jar --stagestats --output=/home/longwalker/.claude/jobs/584f1b84/tmp/CORE.c.census.jar gen/jvm/CORE.c.setting
```
Expected: the stage stats (record parse/optimize/qast/unit and the wall; B0's census compile was 356 s) and the `op census:` block. Copy the block: `raku tools/build/evalserver-sweep.raku --census-block=/home/longwalker/.claude/jobs/584f1b84/tmp/corec-census-b1r.log > m7-rig/b1r-corec-census.err`.

- [ ] **Step 4: The CORE.c JFR compile, knob off**

Run:
```
RAKUDO_RAKUAST=1 JAVA_TOOL_OPTIONS='-XX:FlightRecorderOptions=stackdepth=512 -XX:StartFlightRecording=filename=/home/longwalker/.claude/jobs/584f1b84/tmp/corec-b1r.jfr,settings=profile' raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/584f1b84/tmp/corec-jfr-b1r.log --show='Stage' --stall=900 -- ./rakudo-j --setting=NULL.c --ll-exception --optimize=3 --target=jar --stagestats --output=/home/longwalker/.claude/jobs/584f1b84/tmp/CORE.c.jfr.jar gen/jvm/CORE.c.setting
```
then `raku tools/build/jfr-attribute.raku --ops /home/longwalker/.claude/jobs/584f1b84/tmp/corec-b1r.jfr > m7-rig/b1r-corec-jfr.txt`.
Expected: a wall near B0's 319 s; the four container tables (table, classlib, sites, dispatch) with sample counts.

- [ ] **Step 5: The spike: the PE-visible road on CORE.c**

Run the Step 4 command again with `NQP_CLASSLIB_INLINE=1` added to the environment, the JFR file `corec-b1r-inline.jfr`, the log `corec-jfr-b1r-inline.log`, the jar `CORE.c.inline.jar`; then `raku tools/build/jfr-attribute.raku --ops /home/longwalker/.claude/jobs/584f1b84/tmp/corec-b1r-inline.jfr > m7-rig/b1r-corec-inline-jfr.txt`.
Expected: a wall and the container shares. The spike's reading: the classlib container's share and its leaf under PE visibility against Step 4's. Recorded, not acted on (spec 6.1 item 2).

- [ ] **Step 6: Write the ledger section**

Append to the ledger, after the B1 section and before any later section:
```markdown
## B2, the opening: the retake (Task 2 of the batch 2 part 1 plan)

Tree: rakudo `<rakudo tip after Task 1>` / nqp `76d88cf32` (batch 1's engine, Task 1's readers).
Jars rebuilt (<wall> s), retrained (`dispatch-record: done ...`, <wall> s).

Rig row b1r (rig wall <n> s), a reference for today's machine, NOT a series row:

`| b1r | <rakudo> | <nqp> | <cold-rakudo> | <cold-nqp> | <misses> | <hits> | <warm>/sanity | <new-red> | retake reference |`

### The census, per workload (b1 -> b1r)

| workload | table | classlib | siteCalls | siteMisses | top classlib (8) |
| --- | --- | --- | --- | --- | --- |
| rakudo-e | <b1> -> <b1r> | ... | ... | ... | ... |
| nqp-e | ... |
| sanity | ... |
| CORE.c | <b0 bound> -> <b1r> | ... | ... | ... | ... |

CORE.c clocks: census compile <wall> s (parse <p> / optimize / qast / unit), JFR compile <wall> s, spike compile <wall> s.

### JFR `--ops`, CORE.c: b0 -> b1r -> spike

| container | b0 | b1r | spike (NQP_CLASSLIB_INLINE=1) |
| --- | --- | --- | --- |
| table | 15.4 % | ... | ... |
| classlib | 26.7 % (leaf classlibInline 18.3 % global) | ... | ... |
| sites | 2.3 % | ... | ... |
| dispatch | 15.3 % | ... | ... |
| interpreter self | 8.4 % | ... | ... |
| outside all | 31.9 % | ... | ... |

Reading: <two or three sentences: what batch 1 moved on CORE.c (decont/isconcrete off the classlib road), what the classlib share is now, what the spike says about PE visibility -- the trim's ceiling>.

Rulings: (1) Ruling 3 of the plan (largest census block) applied to every file read here. (2) <any surprise>.
```
Fill every `<...>` from the files; no field stays a placeholder.

- [ ] **Step 7: Commit (rakudo tree)**

```bash
GIT_AUTHOR_DATE='2026-09-17 19:45:00 +0200' GIT_COMMITTER_DATE='2026-09-17 19:45:00 +0200' git commit docs/superpowers/plans/2026-09-16-jvm-milestone-8-phase-b.ledger.md -m "Docs: Phase B ledger -- the B2 retake on the batch 1 tree, CORE.c included, and the PE-visible spike (milestone 8, B2)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: the settle plan for batch 1's non-reproducing red

**Files:**
- Modify: `docs/superpowers/plans/2026-09-16-jvm-milestone-8-phase-b.ledger.md` (subsection `### The settle plan for 023-named-args.t` under the B2 opening section)

**Interfaces:**
- Consumes: the batch 1 kill-switch (`NQP_SITES_OFF=all`), `NQP_DISPATCH_PERSIST=off|verify`, the nqp suite task.
- Produces: a ledgered verdict: reproduced under which cell, or not reproduced in N runs.

- [ ] **Step 1: The 50-run loop on the file**

Run (a Raku driver, per the tooling rule):
```
raku -e 'my @bad; for 1..50 { my $p = run <prove -q --exec ./nqp-j-gradle t/nqp/023-named-args.t>, :cwd("nqp"), :out, :err; @bad.push($_) if $p.exitcode; }; say "023 x50: { 50 - @bad } passed, failed runs: @bad[]"'
```
Expected: `023 x50: 50 passed, failed runs:` (or the failing run numbers). Record the wall.

- [ ] **Step 2: The 2x2, ten runs per cell**

Run the same driver four times with the cell's environment set on the command line, ten runs each:
- `NQP_DISPATCH_PERSIST=off raku -e '...'` (persistence off, sites on)
- `NQP_SITES_OFF=all raku -e '...'` (persistence on, sites off)
- `NQP_DISPATCH_PERSIST=off NQP_SITES_OFF=all raku -e '...'` (both off)
- the plain cell is Step 1.
with `for 1..10` and the message `023 <cell> x10: ...`.
Expected: every cell 10 passed. A failure names its cell.

- [ ] **Step 3: One nqp suite run under verify mode**

Run:
```
NQP_DISPATCH_PERSIST=verify raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/584f1b84/tmp/nqp-suite-verify-b2.log --show='Files=' --show='Result' --show='BUILD' --show='mismatched' --stall=900 -- ./nqp/gradlew -p nqp testNqp
```
Expected: `Result: PASS`, `Files=154`, and the verify line `mismatched=0` (grep the log for `mismatched=`). Record the prove and gradle walls.

- [ ] **Step 4: Write the ledger subsection**

Append under the B2 opening section:
```markdown
### The settle plan for `t/nqp/023-named-args.t` (Task 3)

| cell | runs | passed | wall |
| --- | --- | --- | --- |
| persist on, sites on | 50 | <n> | <s> |
| persist off, sites on | 10 | <n> | <s> |
| persist on, sites off (`NQP_SITES_OFF=all`) | 10 | <n> | <s> |
| persist off, sites off | 10 | <n> | <s> |

nqp suite under `NQP_DISPATCH_PERSIST=verify`: Result: <PASS|FAIL>, Files=<n> Tests=<n>, prove <s> / gradle <s>, `mismatched=<n>`.

Verdict: <"not reproduced in 80 file runs and one verify suite; the red stays an open item with no attribution, and B2's suite runs are its next chance" | "reproduced under <cell>: <what the failure said>, which points at <sites|persisted slots>; STOP and report before Task 4">.
```

- [ ] **Step 5: Commit (rakudo tree)**

```bash
GIT_AUTHOR_DATE='2026-09-17 20:00:00 +0200' GIT_COMMITTER_DATE='2026-09-17 20:00:00 +0200' git commit docs/superpowers/plans/2026-09-16-jvm-milestone-8-phase-b.ledger.md -m "Docs: Phase B ledger -- the settle plan for batch 1's non-reproducing red, run (milestone 8, B2)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: the split of `NqpTypeOps.kt`

**Files:**
- Create: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpSiteOps.kt`
- Modify: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt` (remove lines 585-864: from the `/* ----- iscont ----- */` header up to the line before `/* ----- assertparamcheck ----- */`; widen five helpers)
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java` (`IsContOp`, `IsTrueOp`, `FindMethodOp`, `Truthy`: 13 references)
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java` (`beginOp`, `walkCond`)
- Test: `nqp/t/jvm/21-op-sites.t` (unchanged; it proves the move)

**Interfaces:**
- Produces: `object NqpSiteOps` with, verbatim from `NqpTypeOps`: `class IsContSite : NqpTypeOps.Site()`, `fun iscont(site, o): Long`, `class IsTrueSite`, `val NO_SITE`, `fun istrue(site, o, negate, tc): Long`, `const val FIND_FATAL/FIND_TRY/FIND_CAN`, `class FindMethodSite`, `fun findmethod(site, o, name, kind, tc): Any?`, and their private resolvers and slow roads.
- Consumes (now `internal` in `NqpTypeOps`): `miss(site: Site)`, `republished(site: Site)`, `debug(msg: String)`, `suspendedIn(sse, finish)`, `truthy(v, tc): Long`; unchanged public: `NqpTypeOps.Site`, `NqpTypeOps.DecontSite`, `NqpTypeOps.decont(site, o, tc)`, `NqpTypeOps.DEBUG`, `NqpTypeOps.SuspendedIn`.

- [ ] **Step 1: Run the site tests once on the unchanged tree (the baseline for the move)**

Run: `raku -e 'exit run(<prove --exec ./nqp-j-gradle t/jvm/21-op-sites.t t/jvm/20-op-census.t t/jvm/19-type-state.t>, :cwd("nqp")).exitcode'`
Expected: all pass (21-op-sites.t 31 tests). Record the wall.

- [ ] **Step 2: Create `NqpSiteOps.kt` with the three sections moved verbatim**

Create the file with this frame, and paste lines 585-864 of `NqpTypeOps.kt` (the `iscont`, `istrue / isfalse`, `findmethod / tryfindmethod / can` sections, each starting at its `/* ----- ... ----- */` header, the `findmethod` section ending with `findmethodSlow`'s closing brace) inside the object, unchanged:
```kotlin
package org.raku.nqp.truffle

import com.oracle.truffle.api.CompilerDirectives
import com.oracle.truffle.api.CompilerDirectives.CompilationFinal
import com.oracle.truffle.api.CompilerDirectives.TruffleBoundary
import org.raku.nqp.runtime.Ops
import org.raku.nqp.runtime.SaveStackException
import org.raku.nqp.runtime.ThreadContext
import org.raku.nqp.sixmodel.BoolificationSpec
import org.raku.nqp.sixmodel.STable
import org.raku.nqp.sixmodel.SixModelObject
import org.raku.nqp.sixmodel.TypeObject
import org.raku.nqp.sixmodel.TypeState
import org.raku.nqp.truffle.NqpTypeOps.Site
import org.raku.nqp.truffle.NqpTypeOps.DecontSite
import org.raku.nqp.truffle.NqpTypeOps.DEBUG
import org.raku.nqp.truffle.NqpTypeOps.debug
import org.raku.nqp.truffle.NqpTypeOps.decont
import org.raku.nqp.truffle.NqpTypeOps.miss
import org.raku.nqp.truffle.NqpTypeOps.republished
import org.raku.nqp.truffle.NqpTypeOps.suspendedIn
import org.raku.nqp.truffle.NqpTypeOps.truthy

/**
 * The batch 1 sites of milestone 8 Phase B -- iscont, istrue/isfalse (and
 * the Truthy object arm), findmethod/tryfindmethod/can -- moved out of
 * NqpTypeOps.kt when that file passed the spec's thousand-line split point
 * (section 4; 6.1 item 5). The Site base, the registry, DecontSite and the
 * shared helpers stay in NqpTypeOps; batch 2's sites go in a third file.
 * Every body here is the batch 1 text, unchanged.
 */
object NqpSiteOps {

    // <the three sections, verbatim>

}
```
Remove any import the pasted code does not use (the Kotlin compiler warns; `NqpRaw.st` is a call into `NqpRaw`, same package, no import).

- [ ] **Step 3: Remove the sections from `NqpTypeOps.kt` and widen the helpers**

Delete lines 585-864 from `NqpTypeOps.kt`. Change these five declarations from `private` to `internal`: `private fun miss(site: Site)` (line 387), `private fun republished(site: Site)` (403), `private fun debug(msg: String)` (416), `private fun suspendedIn(sse: SaveStackException, ...)` (444), `private fun truthy(v: Any?, tc: ThreadContext): Long` (551). Leave `@TruffleBoundary` where it is.

- [ ] **Step 4: Repoint the Java references**

In `NqpRootNode.java`: `NqpTypeOps.IsContSite` -> `NqpSiteOps.IsContSite`, `NqpTypeOps.iscont(` -> `NqpSiteOps.iscont(`, `NqpTypeOps.IsTrueSite` -> `NqpSiteOps.IsTrueSite`, `NqpTypeOps.istrue(` -> `NqpSiteOps.istrue(`, `NqpTypeOps.FindMethodSite` -> `NqpSiteOps.FindMethodSite`, `NqpTypeOps.findmethod(` -> `NqpSiteOps.findmethod(`, `NqpTypeOps.FIND_CAN` -> `NqpSiteOps.FIND_CAN`. `NqpTypeOps.SuspendedIn` stays. In `NqpProgramBuilder.java` (`beginOp` lines 815-820, `walkCond` line 869): `NqpTypeOps.IsContSite` / `IsTrueSite` / `FindMethodSite` / `FIND_FATAL` / `FIND_TRY` / `FIND_CAN` / `NO_SITE` -> `NqpSiteOps.` the same.
Check: `grep -n 'NqpTypeOps\.\(IsTrueSite\|IsContSite\|FindMethodSite\|NO_SITE\|FIND_\|istrue\|iscont\|findmethod\)' nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/*.java` prints nothing.

- [ ] **Step 5: Rebuild the jars**

Run: `./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars`
Expected: `BUILD SUCCESSFUL`, no Kotlin error (an unresolved reference names a helper that is still private or an import that is missing). Then retrain (the Global Constraints command).

- [ ] **Step 6: Run the site tests**

Run: `raku -e 'exit run(<prove --exec ./nqp-j-gradle t/jvm/21-op-sites.t t/jvm/20-op-census.t t/jvm/19-type-state.t>, :cwd("nqp")).exitcode'`
Expected: identical to Step 1, every census site name unchanged (`site IsTrueSite`, `site IsContSite`, `site FindMethodSite`: the name is `javaClass.simpleName`).

- [ ] **Step 7: The nqp suite**

Run:
```
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/584f1b84/tmp/nqp-suite-split.log --show='Files=' --show='Result' --show='BUILD' --stall=900 -- ./nqp/gradlew -p nqp testNqp
```
Expected: `Result: PASS`, `Files=154`. Record prove and gradle walls. Line counts: `wc -l` of `NqpTypeOps.kt` (about 950) and `NqpSiteOps.kt` (about 310); record both.

- [ ] **Step 8: Commit (nqp tree)**

```bash
GIT_AUTHOR_DATE='2026-09-17 20:15:00 +0200' GIT_COMMITTER_DATE='2026-09-17 20:15:00 +0200' git -C nqp commit nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpSiteOps.kt nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java -m "Engine: the batch 1 sites move to NqpSiteOps.kt; NqpTypeOps.kt keeps the Site base and the shared helpers (milestone 8, B2)

A pure move at the spec's thousand-line split point: iscont, istrue and
findmethod are the batch 1 text unchanged, five helpers go internal, the
DSL nodes and the builder repoint. The census names are the classes'
simple names and do not change.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: the typed classlib road

**Files:**
- Create: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpClassLibRoad.kt`
- Modify: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpCensus.kt:34,59-65,104-110`
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java` (after `ClassLibOp`, line 241)
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java:24-33` (class comment), `:657-696` (the CLASSLIB case), new `beginTyped`/`endTyped` after `endOp`
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java:952-956` (the knob's comment)
- Create: `nqp/t/jvm/22-classlib-road.t`

**Interfaces:**
- Produces: `NqpClassLibRoad.TypedSite(cls, meth, desc, tcArg, nargs, rtype, isLong)` with `name`, `tokenType`, `handle()`; `NqpClassLibRoad.site(cls, meth, desc, tcArg, nargs, rtype): TypedSite?` (null above arity 4); `obj0(s, tc)`..`obj4(s, a0..a3, tc): Any?` and `call0..call4` (no boundary); `long1(s, a0)`..`long3(s, a0, a1, a2): Long` and `callLong1..callLong3`; `NqpCensus.classlibTyped(site: Any)`; the header field `classlibTyped=N`; DSL operations `ClassLib0`..`ClassLib4`, `ClassLibLong1`..`ClassLibLong3`; kill-switch name `classlib`.
- Consumes: `NqpOps.suspendToken(sse, rtype)`, `NqpOps.CLASSLIB_INLINE`, `NqpOps.carry`, `NqpWire.T_INT/T_UINT`, `NqpCensus.ON`.

- [ ] **Step 1: Write the failing test**

Create `nqp/t/jvm/22-classlib-road.t`:
```perl
# Milestone 8 Phase B, batch 2: the typed classlib road (spec section 6.2).
# In-process: one op per arity and flavour answers correctly through the
# new nodes (the process runs with the road on). Child processes under
# NQP_OP_CENSUS=1 prove the routing: the header's classlibTyped= counter
# moves; under NQP_SITES_OFF=classlib it is 0 while the per-name classlib
# count is unchanged; under NQP_CLASSLIB_INLINE=1 the typed road still runs;
# and a continuation captured inside a classlib op's callee (a container
# FETCH under nqp::decont, with the decont sites off) resumes through the
# road's suspend token.
#
# The child-process helper is the one of t/jvm/20-op-census.t, grown to
# return stdout as well. This file spawns ./nqp-j-gradle relative to the
# nqp tree, so prove must run from there.

plan(24);

my class Queue is repr('ConcBlockingQueue') { }
my class VMDecoder is repr('Decoder') { }
my sub create_buf($type) {
    my $buf := nqp::newtype(nqp::null(), 'VMArray');
    nqp::composetype($buf, nqp::hash('array', nqp::hash('type', $type)));
    $buf
}

# Runs ./nqp-j-gradle -e $code as a child under %env; returns [status, stderr, stdout].
sub child-run($code, %env) {
    my $queue := nqp::create(Queue);
    my $done := 0; my $out-eof := 0; my $err-eof := 0; my $status := -1;
    my @err; my @out;
    my $config := nqp::hash(
        'done', -> $st { $status := $st; $done := 1 },
        'ready', -> $stdin?, $stdout?, $stderr? { },
        'stdout_bytes', -> $seq, $data, $err {
            if nqp::isconcrete($data) { @out[$seq] := $data } else { $out-eof := 1 }
        },
        'stderr_bytes', -> $seq, $data, $err {
            if nqp::isconcrete($data) { @err[$seq] := $data } else { $err-eof := 1 }
        },
        'buf_type', create_buf(uint8));
    my $task := nqp::spawnprocasync($queue, './nqp-j-gradle', nqp::list('./nqp-j-gradle', '-e', $code),
                                    nqp::cwd(), %env, $config);
    nqp::permit($task, 1, -1);
    nqp::permit($task, 2, -1);
    while !$done || !$out-eof || !$err-eof {
        if nqp::shift($queue) -> $t {
            if nqp::islist($t) { my $cb := nqp::shift($t); $cb(|$t) } else { $t() }
        }
    }
    sub decode(@bytes) {
        my $dec := nqp::create(VMDecoder);
        nqp::decoderconfigure($dec, 'utf8', nqp::hash());
        for @bytes -> $b { nqp::decoderaddbytes($dec, $b) if nqp::isconcrete($b) }
        nqp::decodertakeallchars($dec)
    }
    nqp::list($status, decode(@err), decode(@out))
}

# "  <prefix> <count> <name>" -> count, or -1 when absent.
sub count-of($text, $prefix, $name) {
    for nqp::split("\n", $text) -> $line {
        my $lead := '  ' ~ $prefix ~ ' ';
        if nqp::index($line, $lead) == 0 {
            my @f := nqp::split(' ', nqp::substr($line, nqp::chars($lead)));
            return +@f[0] if @f[1] eq $name;
        }
    }
    -1
}

# "op census: ... <field>=N" -> N, or -1.
sub header-field($text, $field) {
    for nqp::split("\n", $text) -> $line {
        if nqp::index($line, 'op census:') == 0 {
            for nqp::split(' ', $line) -> $kv {
                return +nqp::substr($kv, nqp::chars($field) + 1) if nqp::index($kv, $field ~ '=') == 0;
            }
        }
    }
    -1
}

# ---- in-process: one op per arity and flavour ---------------------------
ok(nqp::time() > 0, 'arity 0, INT, no context: time');
ok(nqp::chars(nqp::cwd()) > 0, 'arity 0, STR, no context: cwd');
is(nqp::chars('abc'), 3, 'arity 1, INT, no context (long flavour): chars');
is(nqp::elems(nqp::list(1, 2, 3)), 3, 'arity 1, INT, with context (Object flavour): elems');
is(nqp::concat('a', 'b'), 'ab', 'arity 2, STR, no context: concat');
my %h; %h<k> := 1;
is(nqp::existskey(%h, 'k'), 1, 'arity 2, INT, with context: existskey, present');
is(nqp::existskey(%h, 'z'), 0, 'existskey, absent');
is(nqp::atpos(nqp::list(1, 2, 3), 1), 2, 'arity 2, OBJ, with context: atpos');
is(nqp::eqat('hello', 'ell', 1), 1, 'arity 3, INT, no context (long flavour): eqat');
is(nqp::findcclass(nqp::const::CCLASS_WHITESPACE, 'ab cd', 0, 5), 2, 'arity 4, INT, no context (Object flavour by Ruling 1): findcclass');
my $mda := nqp::newtype(nqp::knowhow(), 'MultiDimArray');
nqp::composetype($mda, nqp::hash('array', nqp::hash('dimensions', 3)));
my $cube := nqp::create($mda);
nqp::setdimensions($cube, nqp::list_i(2, 2, 2));
nqp::bindpos3d($cube, 1, 1, 1, 'x');
is(nqp::atpos3d($cube, 1, 1, 1), 'x', 'arity 5 stays on the variadic node: bindpos3d');
class Unboxable { }
my $died := 0;
try { nqp::unbox_i(Unboxable); CATCH { $died := 1 } }
is($died, 1, 'an op that dies through the typed road is caught by try');

# ---- routing: the census header's classlibTyped= counter ----------------
my $loop := 'my $s := 0; my $i := 0; while $i < 1000 { $s := $s + nqp::chars("abc") + nqp::elems(nqp::list(1)); $i++ }; say($s)';
my %on := nqp::getenvhash();
%on<NQP_OP_CENSUS> := '1';
my $typed := child-run($loop, %on);
is($typed[0], 0, 'the typed-road child exits 0');
ok(header-field($typed[1], 'classlibTyped') >= 2000, 'chars and elems travel the typed road');
ok(count-of($typed[1], 'classlib', 'Ops.chars') >= 1000, 'the per-name census still counts chars');
ok(count-of($typed[1], 'classlib', 'Ops.elems') >= 1000, 'and elems');

my %off := nqp::getenvhash();
%off<NQP_OP_CENSUS> := '1';
%off<NQP_SITES_OFF> := 'classlib';
my $variadic := child-run($loop, %off);
is($variadic[0], 0, 'the kill-switch child exits 0');
is(header-field($variadic[1], 'classlibTyped'), 0, 'NQP_SITES_OFF=classlib builds no typed node');
ok(count-of($variadic[1], 'classlib', 'Ops.chars') >= 1000, 'the variadic road still counts chars');

my %inline := nqp::getenvhash();
%inline<NQP_OP_CENSUS> := '1';
%inline<NQP_CLASSLIB_INLINE> := '1';
my $pe := child-run($loop, %inline);
is($pe[0], 0, 'the NQP_CLASSLIB_INLINE=1 child exits 0');
ok(header-field($pe[1], 'classlibTyped') >= 2000, 'the knob keeps the typed road (PE-visible calls)');

# ---- a capture inside a classlib op's callee resumes through the road ----
my $capture := 'class Box { has $!v; method new($v) { my $o := nqp::create(self); nqp::bindattr($o, Box, q<$!v>, $v); $o } }
nqp::setcontspec(Box, q<code_pair>, nqp::hash(
    q<fetch>, -> $c { nqp::continuationcontrol(0, nqp::null(), -> $k { nqp::continuationinvoke($k, { 42 }) }) },
    q<store>, -> $c, $v { }));
my $b := Box.new(1);
say(nqp::continuationreset(nqp::null(), { nqp::decont($b) + 1 }))';
my %reach := nqp::getenvhash();
%reach<NQP_OP_CENSUS> := '1';
%reach<NQP_SITES_OFF> := 'reach,decont';
my $resumed := child-run($capture, %reach);
is($resumed[0], 0, 'the capture child exits 0');
ok(nqp::index($resumed[2], '43') >= 0, 'a FETCH that captures a continuation resumes through the typed road (42 + 1)');
ok(count-of($resumed[1], 'classlib', 'Ops.decont') >= 1, 'and decont travelled the classlib road');
```

- [ ] **Step 2: Establish the capture snippet on the unchanged tree**

Before any road code, run the capture snippet on the current jars to know it is the road under test and not the snippet:
```
NQP_SITES_OFF=reach,decont raku -e 'my $p = run "./nqp-j-gradle", "-e", q:to/END/, :cwd("nqp"), :out, :err; say $p.out.slurp; say $p.err.slurp
class Box { has $!v; method new($v) { my $o := nqp::create(self); nqp::bindattr($o, Box, q<$!v>, $v); $o } }
nqp::setcontspec(Box, q<code_pair>, nqp::hash(
    q<fetch>, -> $c { nqp::continuationcontrol(0, nqp::null(), -> $k { nqp::continuationinvoke($k, { 42 }) }) },
    q<store>, -> $c, $v { }));
my $b := Box.new(1);
say(nqp::continuationreset(nqp::null(), { nqp::decont($b) + 1 }))
END
'
```
Expected: `43` on the variadic road (today's road returns a suspend token, the wrapper yields, the resume replaces it). If it prints anything else, the snippet is not a road test: replace the capture test's three asserts by the same three on `nqp::istrue` with `NQP_SITES_OFF=istrue` and a `nqp::setboolspec(Box, 0, -> $o { nqp::continuationcontrol(...) })` boolification method (`say(nqp::continuationreset(nqp::null(), { nqp::istrue($b) + 1 }))`, expected `43` with the method answering 42); if that also fails on the unchanged tree, cut the three asserts, set `plan(21)`, and record the cut as a ruling in the Task 6 ledger section (a capture through a classlib op is then untested in nqp and covered by Rakudo's take/gather in the suite).

- [ ] **Step 3: Run the test to see it fail**

Run: `raku -e 'exit run(<prove --exec ./nqp-j-gradle t/jvm/22-classlib-road.t>, :cwd("nqp")).exitcode'`
Expected: the in-process asserts pass (the ops answer the same on any road), `classlibTyped` reads -1 (no such header field yet), so tests 14, 18 (expects 0, gets -1), 21 fail; the capture test passes or is cut per Step 2.

- [ ] **Step 4: The road (Kotlin)**

Create `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpClassLibRoad.kt`:
```kotlin
package org.raku.nqp.truffle

import com.oracle.truffle.api.CompilerDirectives
import com.oracle.truffle.api.CompilerDirectives.CompilationFinal
import com.oracle.truffle.api.CompilerDirectives.TruffleBoundary
import java.lang.invoke.MethodHandle
import java.lang.invoke.MethodHandles
import java.lang.invoke.MethodType
import org.raku.nqp.runtime.SaveStackException
import org.raku.nqp.runtime.ThreadContext

/**
 * The typed classlib road (milestone 8, Phase B, batch 2, spec 6.2).
 *
 * A registry-derived classlib op used to reach the runtime through one
 * variadic node: an Object[] from the DSL, a second Object[] to append the
 * thread context, a handle adapted with asSpreader and asType to
 * (Object[])Object -- every INT/STR result boxed by the adapter -- and one
 * megamorphic invokeExact for every classlib op in the process, behind a
 * boundary. That road's own leaf was 18.3 % of a CORE.c compile.
 *
 * Here every CLASSLIB instruction of arity 0-4 gets a [TypedSite]: the
 * registry row, the result type and ONE handle, resolved once and adapted
 * once to the uniform type of its arity and flavour. The Object flavour is
 * `(Object, ..., ThreadContext)Object`: the context is a real argument (an
 * op without `:tc` has it dropped by the adapter), and a capture answers
 * the suspend token typed by the op's result, as the variadic road did.
 * The long flavour is `(Object, ...)long` for context-free INT/UINT ops of
 * arity 1-3 only (plan Ruling 1): without a context an op cannot reach
 * guest code, so it cannot capture, and a long cannot carry a token.
 *
 * The declared residual: operands stay boxed (the operand stack is Object
 * for a mixed signature). Arity 5-6 (twenty registrations) and
 * `NQP_SITES_OFF=classlib` keep the variadic node. `NQP_CLASSLIB_INLINE=1`
 * calls the compilation-final handle without the boundary (the
 * milestone 7 knob, same meaning on this road).
 */
object NqpClassLibRoad {
    const val MAX_ARITY = 4

    /** One CLASSLIB instruction: the registry row plus its handle. */
    class TypedSite(@JvmField val cls: String, @JvmField val meth: String, @JvmField val desc: String,
                    @JvmField val tcArg: Boolean, @JvmField val nargs: Int, @JvmField val rtype: Int,
                    @JvmField val isLong: Boolean) {
        /** The census name, `Ops.meth`, as the variadic road's site prints. */
        @JvmField val name: String = cls.substringAfterLast('/').removeSuffix(";") + "." + meth
        /** The token's register type: a uint site reads from the int register. */
        @JvmField val tokenType: Int = if (rtype == NqpWire.T_UINT) NqpWire.T_INT else rtype
        @JvmField @field:CompilationFinal var mh: MethodHandle? = null

        fun handle(): MethodHandle {
            val h = mh
            if (h != null) return h
            CompilerDirectives.transferToInterpreterAndInvalidate()
            val r = resolve(this)
            mh = r
            return r
        }
    }

    /** The site for one instruction, or null when it stays on the variadic node. */
    @JvmStatic
    fun site(cls: String, meth: String, desc: String, tcArg: Boolean, nargs: Int, rtype: Int): TypedSite? {
        if (nargs > MAX_ARITY) return null
        val isLong = !tcArg && (rtype == NqpWire.T_INT || rtype == NqpWire.T_UINT) && nargs in 1..3
        return TypedSite(cls, meth, desc, tcArg, nargs, rtype, isLong)
    }

    @TruffleBoundary
    private fun resolve(s: TypedSite): MethodHandle {
        val ld = NqpOps::class.java.classLoader
        // The registry stores the class as a JVM type descriptor
        // (Lorg/raku/nqp/runtime/Ops;); Class.forName wants org.raku.nqp.runtime.Ops.
        var bin = s.cls
        if (bin.startsWith("L") && bin.endsWith(";")) bin = bin.substring(1, bin.length - 1)
        bin = bin.replace('/', '.')
        val h0 = try {
            val c = Class.forName(bin, true, ld)
            val mt = MethodType.fromMethodDescriptorString(s.desc, ld)
            MethodHandles.lookup().findStatic(c, s.meth, mt)
        } catch (e: ReflectiveOperationException) {
            throw IllegalStateException("nqpp: classlib op ${s.cls}.${s.meth}${s.desc}: $e", e)
        }
        val obj = Any::class.java
        val params = ArrayList<Class<*>>(s.nargs + 1)
        repeat(s.nargs) { params.add(obj) }
        if (s.isLong) return h0.asType(MethodType.methodType(java.lang.Long.TYPE, params))
        val h = if (s.tcArg) h0 else MethodHandles.dropArguments(h0, s.nargs, ThreadContext::class.java)
        params.add(ThreadContext::class.java)
        return h.asType(MethodType.methodType(obj, params))
    }

    /* ----- JESP_TRACE_CLASSLIB=meth: name the frame running that op, once per frame ----- */

    @JvmField val TRACE: String? = System.getenv("JESP_TRACE_CLASSLIB")
    private val traced = HashSet<String>()

    @TruffleBoundary
    private fun trace(s: TypedSite, tc: ThreadContext) {
        val f = tc.curFrame
        val where = if (f == null) "<no frame>" else f.codeRef.name + " (current frame; a frame-free callee names its caller)"
        synchronized(traced) {
            if (traced.add(s.meth + "@" + where)) System.err.println("classlib " + s.meth + " in " + where)
        }
    }

    /* ----- the Object flavour: a token on a capture ----- */

    @JvmStatic fun call0(s: TypedSite, tc: ThreadContext): Any? {
        if (TRACE != null && TRACE == s.meth) trace(s, tc)
        return try { s.handle().invokeExact(tc) as Any? }
               catch (sse: SaveStackException) { NqpOps.suspendToken(sse, s.tokenType) }
    }
    @JvmStatic fun call1(s: TypedSite, a0: Any?, tc: ThreadContext): Any? {
        if (TRACE != null && TRACE == s.meth) trace(s, tc)
        return try { s.handle().invokeExact(a0, tc) as Any? }
               catch (sse: SaveStackException) { NqpOps.suspendToken(sse, s.tokenType) }
    }
    @JvmStatic fun call2(s: TypedSite, a0: Any?, a1: Any?, tc: ThreadContext): Any? {
        if (TRACE != null && TRACE == s.meth) trace(s, tc)
        return try { s.handle().invokeExact(a0, a1, tc) as Any? }
               catch (sse: SaveStackException) { NqpOps.suspendToken(sse, s.tokenType) }
    }
    @JvmStatic fun call3(s: TypedSite, a0: Any?, a1: Any?, a2: Any?, tc: ThreadContext): Any? {
        if (TRACE != null && TRACE == s.meth) trace(s, tc)
        return try { s.handle().invokeExact(a0, a1, a2, tc) as Any? }
               catch (sse: SaveStackException) { NqpOps.suspendToken(sse, s.tokenType) }
    }
    @JvmStatic fun call4(s: TypedSite, a0: Any?, a1: Any?, a2: Any?, a3: Any?, tc: ThreadContext): Any? {
        if (TRACE != null && TRACE == s.meth) trace(s, tc)
        return try { s.handle().invokeExact(a0, a1, a2, a3, tc) as Any? }
               catch (sse: SaveStackException) { NqpOps.suspendToken(sse, s.tokenType) }
    }

    @JvmStatic @TruffleBoundary fun obj0(s: TypedSite, tc: ThreadContext): Any? = call0(s, tc)
    @JvmStatic @TruffleBoundary fun obj1(s: TypedSite, a0: Any?, tc: ThreadContext): Any? = call1(s, a0, tc)
    @JvmStatic @TruffleBoundary fun obj2(s: TypedSite, a0: Any?, a1: Any?, tc: ThreadContext): Any? = call2(s, a0, a1, tc)
    @JvmStatic @TruffleBoundary fun obj3(s: TypedSite, a0: Any?, a1: Any?, a2: Any?, tc: ThreadContext): Any? = call3(s, a0, a1, a2, tc)
    @JvmStatic @TruffleBoundary fun obj4(s: TypedSite, a0: Any?, a1: Any?, a2: Any?, a3: Any?, tc: ThreadContext): Any? = call4(s, a0, a1, a2, a3, tc)

    /* ----- the long flavour: context-free INT/UINT ops, arity 1-3 (Ruling 1) ----- */

    @JvmStatic fun callLong1(s: TypedSite, a0: Any?): Long = s.handle().invokeExact(a0) as Long
    @JvmStatic fun callLong2(s: TypedSite, a0: Any?, a1: Any?): Long = s.handle().invokeExact(a0, a1) as Long
    @JvmStatic fun callLong3(s: TypedSite, a0: Any?, a1: Any?, a2: Any?): Long = s.handle().invokeExact(a0, a1, a2) as Long

    @JvmStatic @TruffleBoundary fun long1(s: TypedSite, a0: Any?): Long = callLong1(s, a0)
    @JvmStatic @TruffleBoundary fun long2(s: TypedSite, a0: Any?, a1: Any?): Long = callLong2(s, a0, a1)
    @JvmStatic @TruffleBoundary fun long3(s: TypedSite, a0: Any?, a1: Any?, a2: Any?): Long = callLong3(s, a0, a1, a2)
}
```
Note on the polymorphic-signature calls: Kotlin takes the call-site argument types from the parameters' static types (`Any?` -> `Object`, `ThreadContext`) and the return from the cast (`as Any?` -> `Object`, `as Long` -> primitive `long`, the `P6TYPECHECKRV_CACHEABLE` precedent). The adapted handle types in `resolve` match those exactly; a mismatch throws `WrongMethodTypeException` on the first call, which the nqp suite reports at once.

- [ ] **Step 5: The census counts the typed road**

In `NqpCensus.kt`: add a counter next to `classlib` (line 34):
```kotlin
    private val typed = LongAdder()
```
replace `classlib(site: Any)` (lines 59-65) with:
```kotlin
    /** The site is typed Any: NqpOps.ClassLibSite is package-private in
     *  Java and Kotlin refuses it in a public signature; the typed road's
     *  site is the Kotlin TypedSite. Both count under `Ops.meth`. */
    @JvmStatic @TruffleBoundary fun classlib(site: Any) {
        val name = when (site) {
            is NqpOps.ClassLibSite -> site.cls.substringAfterLast('/').removeSuffix(";") + "." + site.meth
            is NqpClassLibRoad.TypedSite -> site.name
            else -> site.toString()
        }
        classlib.computeIfAbsent(name) { LongAdder() }.increment()
    }

    /** A call through the typed road (batch 2): the per-name count above
     *  plus the header's classlibTyped= total, the routing fact
     *  t/jvm/22-classlib-road.t asserts on. */
    @JvmStatic @TruffleBoundary fun classlibTyped(site: Any) {
        classlib(site)
        typed.increment()
    }
```
and change the header line (line 110) to:
```kotlin
            System.err.println("op census: table=$tableTotal classlib=$classlibTotal siteCalls=$siteCalls siteMisses=$siteMisses classlibTyped=${typed.sum()}")
```
Also update the class KDoc's first paragraph: after "every classlib op by class and method name," add "(the typed road's calls also under classlibTyped= on the header)".

- [ ] **Step 6: The eight operations (Java, the DSL)**

In `NqpRootNode.java`, after `ClassLibOp` (after line 241), add:
```java
    /* ----- the typed classlib road (milestone 8, B2): one operation per
     * arity, the site's handle exact-typed, the thread context a real
     * argument, no Object[] on either side (NqpClassLibRoad). ClassLibOp
     * above stays for arity 5-6 and under NQP_SITES_OFF=classlib. The long
     * operations serve context-free INT/UINT ops only: no capture is
     * possible there, so no token and no suspend-check wrapper. ----- */

    @Operation
    @ConstantOperand(type = Object.class, name = "site")
    public static final class ClassLib0 {
        @Specialization
        static Object doCall(VirtualFrame f, Object site) {
            NqpClassLibRoad.TypedSite s = (NqpClassLibRoad.TypedSite) site;
            try {
                if (NqpCensus.ON) NqpCensus.classlibTyped(s);
                return NqpOps.CLASSLIB_INLINE ? NqpClassLibRoad.call0(s, tc(f)) : NqpClassLibRoad.obj0(s, tc(f));
            } catch (Throwable t) {
                throw NqpOps.carry(t);
            }
        }
    }

    @Operation
    @ConstantOperand(type = Object.class, name = "site")
    public static final class ClassLib1 {
        @Specialization
        static Object doCall(VirtualFrame f, Object site, Object a0) {
            NqpClassLibRoad.TypedSite s = (NqpClassLibRoad.TypedSite) site;
            try {
                if (NqpCensus.ON) NqpCensus.classlibTyped(s);
                return NqpOps.CLASSLIB_INLINE ? NqpClassLibRoad.call1(s, a0, tc(f)) : NqpClassLibRoad.obj1(s, a0, tc(f));
            } catch (Throwable t) {
                throw NqpOps.carry(t);
            }
        }
    }

    @Operation
    @ConstantOperand(type = Object.class, name = "site")
    public static final class ClassLib2 {
        @Specialization
        static Object doCall(VirtualFrame f, Object site, Object a0, Object a1) {
            NqpClassLibRoad.TypedSite s = (NqpClassLibRoad.TypedSite) site;
            try {
                if (NqpCensus.ON) NqpCensus.classlibTyped(s);
                return NqpOps.CLASSLIB_INLINE ? NqpClassLibRoad.call2(s, a0, a1, tc(f)) : NqpClassLibRoad.obj2(s, a0, a1, tc(f));
            } catch (Throwable t) {
                throw NqpOps.carry(t);
            }
        }
    }

    @Operation
    @ConstantOperand(type = Object.class, name = "site")
    public static final class ClassLib3 {
        @Specialization
        static Object doCall(VirtualFrame f, Object site, Object a0, Object a1, Object a2) {
            NqpClassLibRoad.TypedSite s = (NqpClassLibRoad.TypedSite) site;
            try {
                if (NqpCensus.ON) NqpCensus.classlibTyped(s);
                return NqpOps.CLASSLIB_INLINE ? NqpClassLibRoad.call3(s, a0, a1, a2, tc(f)) : NqpClassLibRoad.obj3(s, a0, a1, a2, tc(f));
            } catch (Throwable t) {
                throw NqpOps.carry(t);
            }
        }
    }

    @Operation
    @ConstantOperand(type = Object.class, name = "site")
    public static final class ClassLib4 {
        @Specialization
        static Object doCall(VirtualFrame f, Object site, Object a0, Object a1, Object a2, Object a3) {
            NqpClassLibRoad.TypedSite s = (NqpClassLibRoad.TypedSite) site;
            try {
                if (NqpCensus.ON) NqpCensus.classlibTyped(s);
                return NqpOps.CLASSLIB_INLINE ? NqpClassLibRoad.call4(s, a0, a1, a2, a3, tc(f)) : NqpClassLibRoad.obj4(s, a0, a1, a2, a3, tc(f));
            } catch (Throwable t) {
                throw NqpOps.carry(t);
            }
        }
    }

    @Operation
    @ConstantOperand(type = Object.class, name = "site")
    public static final class ClassLibLong1 {
        @Specialization
        static long doCall(Object site, Object a0) {
            NqpClassLibRoad.TypedSite s = (NqpClassLibRoad.TypedSite) site;
            try {
                if (NqpCensus.ON) NqpCensus.classlibTyped(s);
                return NqpOps.CLASSLIB_INLINE ? NqpClassLibRoad.callLong1(s, a0) : NqpClassLibRoad.long1(s, a0);
            } catch (Throwable t) {
                throw NqpOps.carry(t);
            }
        }
    }

    @Operation
    @ConstantOperand(type = Object.class, name = "site")
    public static final class ClassLibLong2 {
        @Specialization
        static long doCall(Object site, Object a0, Object a1) {
            NqpClassLibRoad.TypedSite s = (NqpClassLibRoad.TypedSite) site;
            try {
                if (NqpCensus.ON) NqpCensus.classlibTyped(s);
                return NqpOps.CLASSLIB_INLINE ? NqpClassLibRoad.callLong2(s, a0, a1) : NqpClassLibRoad.long2(s, a0, a1);
            } catch (Throwable t) {
                throw NqpOps.carry(t);
            }
        }
    }

    @Operation
    @ConstantOperand(type = Object.class, name = "site")
    public static final class ClassLibLong3 {
        @Specialization
        static long doCall(Object site, Object a0, Object a1, Object a2) {
            NqpClassLibRoad.TypedSite s = (NqpClassLibRoad.TypedSite) site;
            try {
                if (NqpCensus.ON) NqpCensus.classlibTyped(s);
                return NqpOps.CLASSLIB_INLINE ? NqpClassLibRoad.callLong3(s, a0, a1, a2) : NqpClassLibRoad.long3(s, a0, a1, a2);
            } catch (Throwable t) {
                throw NqpOps.carry(t);
            }
        }
    }
```
In `NqpOps.java` replace the knob's comment (lines 952-955) with:
```java
    /** NQP_CLASSLIB_INLINE=1 restores the pre-milestone-7 road (op bodies
     *  visible to PE) for measurement; the default is the boundary,
     *  matching the table road's run(). Read once: a static final folds in
     *  every program built after it. The same meaning on the typed road
     *  (NqpClassLibRoad: callN without the boundary vs objN/longN). */
```

- [ ] **Step 7: The builder emits the typed nodes**

In `NqpProgramBuilder.java`, replace the CLASSLIB case (lines 657-696) with:
```java
            case NqpWire.CLASSLIB: {
                int rtype = code[at + 1];
                String cls = pool[code[at + 2]];
                String meth = pool[code[at + 3]];
                String desc = pool[code[at + 4]];
                boolean tcArg = code[at + 5] != 0;
                int nargs = code[at + 6];
                at += 7 + nargs;   // the arg types are informational here
                // A classlib op with a per-instruction site (jesp diamond 6:
                // hllize, and istype -- which reaches its IsTypeSite ONLY
                // through this road, since nqp's encoder has no table row for
                // it). The JVM compiler maps these by name onto Ops, so the
                // choice is by name too, again at load. A dedicated operation
                // ignores `rtype`, which is sound here because both roads
                // answer Object: a boxed Long for istype's INT result, or a
                // T_INT suspension token that the emitSuspendCheck below
                // handles identically. See dedicatedClasslib.
                Op cop = dedicatedClasslib(cls, meth, nargs);
                // Everything else of arity 0-4 takes the typed road (batch 2):
                // one exact handle per instruction, the context a real
                // argument. NQP_SITES_OFF=classlib and arity 5-6 keep the
                // variadic ClassLibOp.
                NqpClassLibRoad.TypedSite ts = cop == null && !off("classlib")
                    ? NqpClassLibRoad.site(cls, meth, desc, tcArg, nargs, rtype) : null;
                if (ts != null && ts.isLong) {
                    // A long is neither a suspend token nor a Rethrow: no
                    // store local, no suspend check; the value flows on
                    // unboxed (boxing elimination is on for long).
                    if (emit) beginTyped(ts);
                    for (int i = 0; i < nargs; i++) at = walk(at, emit);
                    if (emit) endTyped(ts);
                    return at;
                }
                BytecodeLocal ores = emit ? b.createLocal() : null;
                if (emit) {
                    b.beginBlock();
                    b.beginStoreLocal(ores);
                }
                if (emit) {
                    if (cop != null) beginOp(cop, -1);
                    else if (ts != null) beginTyped(ts);
                    else b.beginClassLibOp(rtype, new NqpOps.ClassLibSite(cls, meth, desc, tcArg, nargs));
                }
                for (int i = 0; i < nargs; i++) at = walk(at, emit);
                if (emit) {
                    if (cop != null) endOp(cop);
                    else if (ts != null) endTyped(ts);
                    else b.endClassLibOp();
                }
                if (emit) {
                    b.endStoreLocal();
                    emitSuspendCheck(ores);
                    b.emitLoadLocal(ores);
                    b.endBlock();
                }
                return at;
            }
```
After `endOp` (after line 862) add:
```java
    /** The typed classlib node for a site: by arity and flavour. A
     *  zero-operand operation is emitted, not begun (the DSL's emitX). */
    private void beginTyped(NqpClassLibRoad.TypedSite s) {
        if (s.isLong) {
            switch (s.nargs) {
                case 1 -> b.beginClassLibLong1(s);
                case 2 -> b.beginClassLibLong2(s);
                case 3 -> b.beginClassLibLong3(s);
                default -> throw new IllegalStateException("nqpp: long classlib arity " + s.nargs + " for " + s.name);
            }
            return;
        }
        switch (s.nargs) {
            case 0 -> b.emitClassLib0(s);
            case 1 -> b.beginClassLib1(s);
            case 2 -> b.beginClassLib2(s);
            case 3 -> b.beginClassLib3(s);
            case 4 -> b.beginClassLib4(s);
            default -> throw new IllegalStateException("nqpp: typed classlib arity " + s.nargs + " for " + s.name);
        }
    }

    private void endTyped(NqpClassLibRoad.TypedSite s) {
        if (s.isLong) {
            switch (s.nargs) {
                case 1 -> b.endClassLibLong1();
                case 2 -> b.endClassLibLong2();
                case 3 -> b.endClassLibLong3();
                default -> throw new IllegalStateException("nqpp: long classlib arity " + s.nargs + " for " + s.name);
            }
            return;
        }
        switch (s.nargs) {
            case 0 -> { }
            case 1 -> b.endClassLib1();
            case 2 -> b.endClassLib2();
            case 3 -> b.endClassLib3();
            case 4 -> b.endClassLib4();
            default -> throw new IllegalStateException("nqpp: typed classlib arity " + s.nargs + " for " + s.name);
        }
    }
```
In the class comment (lines 24-33) add `classlib` to the list: after `{@code getattr} (getattr and bindattr)` insert `, and {@code classlib} (the typed classlib road of batch 2: off, every registry-derived op takes the variadic ClassLibOp)`.

- [ ] **Step 8: Rebuild, retrain, run the test file**

Run: `./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars`
Expected: `BUILD SUCCESSFUL`. A DSL error here names a generated builder method (`beginClassLib1` etc. come from the operation class names; `emitClassLib0` from the zero-operand one). Then retrain (Global Constraints). Then:
`raku -e 'exit run(<prove --exec ./nqp-j-gradle t/jvm/22-classlib-road.t>, :cwd("nqp")).exitcode'`
Expected: 24/24 (or 21/21 after a Step 2 cut). A `WrongMethodTypeException` on the first classlib call means an adapted type and a call-site type disagree: compare `resolve`'s `MethodType` with the Kotlin call's parameter types.

- [ ] **Step 9: The engine gate and the nqp suite**

Run the trio: `raku -e 'exit run(<prove --exec ./nqp-j-gradle t/jvm/22-classlib-road.t t/jvm/21-op-sites.t t/jvm/20-op-census.t>, :cwd("nqp")).exitcode'` — expected all pass (20-op-census.t's header asserts still match: the new field is appended after `siteMisses=`).
Then the suite:
```
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/584f1b84/tmp/nqp-suite-b2a.log --show='Files=' --show='Result' --show='BUILD' --stall=900 -- ./nqp/gradlew -p nqp testNqp
```
Expected: `Result: PASS`, `Files=155` (one more file: 22). Record the walls. `t/nqp/125-dispatch-stats.t`'s `NQP_CLASSLIB_INLINE=1` child must still pass.

- [ ] **Step 10: Commit (nqp tree)**

```bash
GIT_AUTHOR_DATE='2026-09-17 20:45:00 +0200' GIT_COMMITTER_DATE='2026-09-17 20:45:00 +0200' git -C nqp commit nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpClassLibRoad.kt nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpCensus.kt nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java t/jvm/22-classlib-road.t -m "Engine: the typed classlib road -- one exact handle per instruction, arity nodes, the context a real argument (milestone 8, B2)

The variadic ClassLibOp did per call an Object[] from the DSL, a second
Object[] for the thread context, a spreading and boxing adapter and one
megamorphic invokeExact for every classlib op in the process, behind a
boundary: 18.3 % of a CORE.c compile in its own leaf. Arity 0-4 now
takes ClassLib0..4 (Object, a token on a capture) or ClassLibLong1..3
(context-free INT/UINT ops only: no capture is possible there, and the
value flows on unboxed with no suspend-check wrapper). Arity 5-6 and
NQP_SITES_OFF=classlib keep the variadic node; NQP_CLASSLIB_INLINE=1
means the same on both roads. The census header gains classlibTyped=.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: rig row b2a, the CORE.c clock, the same-session A/B, the ledger

**Files:**
- Modify: `docs/superpowers/plans/2026-09-16-jvm-milestone-8-phase-b.ledger.md` (new section `## B2a: the classlib road trim`)
- Modify: `/home/longwalker/.claude/projects/-home-longwalker-code-raku-x-core-rakudo/memory/milestone-8-stable-assumption.md` and `MEMORY.md` (the status line)
- Produces: `m7-rig/b2a-*`, `m7-rig/b2a-off-*`, `m7-rig/rows.md` rows `b2a` and `b2a-off`

**Interfaces:**
- Consumes: Task 2's `b1r` numbers (the before column), Task 5's jars (already retrained in Task 5 Step 8).
- Produces: the row, the CORE.c clocks on and off, the census per op, the JFR `--ops` shares, the ledger reading against the stop rule.

- [ ] **Step 1: Warm sanity, knob off**

Run:
```
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/584f1b84/tmp/sanity-b2a.log --show='files in' --show='FAIL' --stall=600 -- raku tools/build/evalserver-sweep.raku --chunk='*' --jobs=1 --heap=8 t/01-sanity
```
Expected: `25 files in <n>s across 1 server(s)`, no reds. Record the wall.

- [ ] **Step 2: Rig row b2a with the census**

Run (`NQP_OP_CENSUS`, `NQP_DISPATCH_RECORD`, `NQP_SITES_OFF`, `NQP_CLASSLIB_INLINE` unset):
```
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/584f1b84/tmp/rig-b2a.log --show='m7-rig:' --stall=900 -- raku tools/build/m7-rig.raku --tag=b2a --out=m7-rig --census
```
Expected: `m7-rig: DONE tag=b2a`; the row in `m7-rig/rows.md`; `m7-rig/b2a-*` census and JFR files.

- [ ] **Step 3: The CORE.c clock, knob off with JFR, then the census compile**

Run the Task 2 Step 4 command with `b2a` in the file names (`corec-b2a.jfr`, `corec-jfr-b2a.log`, `CORE.c.b2a.jar`), then `raku tools/build/jfr-attribute.raku --ops /home/longwalker/.claude/jobs/584f1b84/tmp/corec-b2a.jfr > m7-rig/b2a-corec-jfr.txt`. Then the Task 2 Step 3 census compile with `b2a` in the names, the block to `m7-rig/b2a-corec-census.err`.
Expected: two walls (the JFR compile's parse wall is the clock of record against b1r's), the container shares, the census with `classlibTyped=` on the header.

- [ ] **Step 4: The same-session A/B under the kill-switch**

Run, with `NQP_SITES_OFF=classlib` on each command line:
- `NQP_SITES_OFF=classlib raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/584f1b84/tmp/rig-b2a-off.log --show='m7-rig:' --stall=900 -- raku tools/build/m7-rig.raku --tag=b2a-off --out=m7-rig` (no `--census`; the two cold rows and the warm proxy)
- the CORE.c JFR compile (Task 2 Step 4's command) with `NQP_SITES_OFF=classlib` and `b2a-off` in the names, attributed to `m7-rig/b2a-off-corec-jfr.txt`.
Expected: the `b2a-off` row and CORE.c wall. Reading: on/off pairs on the same jars, same training, same session -- the batch 1 lesson (its b0 -> b1 delta was machine state).

- [ ] **Step 5: Write the ledger section**

Append to the ledger:
```markdown
## B2a: the classlib road trim (Tasks 4-6 of the batch 2 part 1 plan)

Commits: nqp `<split sha>` (the NqpTypeOps.kt split), nqp `<road sha>` (the typed road), rakudo `<tools sha>` (Task 1), the ledger commits of Tasks 2-3, and this one.

Gate: Task 4 nqp suite Result: PASS Files=154 (prove <s> / gradle <s>); Task 5 `22-classlib-road.t` <24|21>/<24|21>, trio pass, nqp suite Result: PASS Files=155 (prove <s> / gradle <s>), `t/nqp/125`'s knob child green; warm `t/01-sanity` 25 files in <s> s (Step 1). File sizes after the split: NqpTypeOps.kt <n> lines, NqpSiteOps.kt <n>, NqpClassLibRoad.kt <n>.

Rig rows (rig walls <s> / <s>):

`| b2a | <rakudo> | <nqp> | <cold-rakudo> | <cold-nqp> | <misses> | <hits> | <warm>/sanity | <new-red> | typed classlib road |`
`| b2a-off | <rakudo> | <nqp> | <cold-rakudo> | <cold-nqp> | <misses> | <hits> | <warm>/sanity | <new-red> | NQP_SITES_OFF=classlib, same jars |`

Against b1r (<cold-rakudo> / <cold-nqp> / <warm>): <deltas>. Same-session off/on: cold rakudo-e <off> / <on>, nqp-e <off> / <on>, warm <off> / <on>.

### The CORE.c clock (first-class from B2)

| compile | wall | parse | optimize | qast | unit |
| --- | --- | --- | --- | --- | --- |
| b1r JFR (before) | <s> | ... |
| b2a JFR, road on | <s> | ... |
| b2a-off JFR, road off | <s> | ... |
| b2a census | <s> | ... |

### JFR `--ops`, CORE.c: b1r -> b2a-off -> b2a

| container | b1r | b2a-off | b2a |
| --- | --- | --- | --- |
| table | ... |
| classlib (leaf) | ... (`classlibInline` <n> %) | ... | ... (the new leaf: `NqpClassLibRoad.objN` / `longN` <n> %) |
| sites | ... |
| dispatch | ... |
| interpreter self | ... |
| outside all | ... |

### The census, per workload (b1r -> b2a)

| workload | classlib | classlibTyped | siteCalls | top classlib (8) |
| --- | --- | --- | --- | --- |
| rakudo-e | ... |
| nqp-e | ... |
| sanity | ... |
| CORE.c | ... |

Reading against the stop rule (spec section 4, Revision 3): <did CORE.c or the warm proxy leave the series' spread? which way? the cold rows for the record>.

Rulings:
1. The long flavour serves context-free INT/UINT ops of arity 1-3 only (plan Ruling 1; a deviation from spec 6.2's example list -- `elems`, `existskey` are `:tc` and stay Object-flavoured until 6.3 sites them).
2. The typed road is Kotlin (plan Ruling 2); the variadic road stays in NqpOps.java for arity 5-6 and the kill-switch.
3. A census reader takes the largest block (plan Ruling 3).
4. <the capture test's fate per Task 5 Step 2>
5. <anything the executor ruled>
```
Fill every `<...>`.

- [ ] **Step 6: Commit the ledger (rakudo tree), update memory, push both trees**

```bash
GIT_AUTHOR_DATE='2026-09-17 21:10:00 +0200' GIT_COMMITTER_DATE='2026-09-17 21:10:00 +0200' git commit docs/superpowers/plans/2026-09-16-jvm-milestone-8-phase-b.ledger.md -m "Docs: Phase B ledger -- row b2a, the classlib road trim on three clocks, same-session off/on (milestone 8, B2)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```
Memory: in `milestone-8-stable-assumption.md` append a paragraph "B2 PART 1 LANDED <date>: rakudo <sha> / nqp <sha>; row b2a <numbers>; CORE.c <before> -> <after>; NEXT = the 6.3 plan (the heads)" and prefix the `description:` line and the `MEMORY.md` index line with the same one-liner.
Push: `git push ab5tract HEAD` (rakudo) and `git -C nqp push ab5tract HEAD` (nqp).
Expected: both pushes fast-forward.

---

## Self-review

**Spec coverage.** 6.1 item 1 (the retake) = Task 2 Steps 1-4; item 2 (the spike) = Task 2 Step 5; item 3 (the settle plan) = Task 3; item 4 (tooling) = Task 1; item 5 (the split) = Task 4. 6.2: arity nodes = Task 5 Step 6; one exact handle per site, uniform type, context dropped by the adapter = Step 4 (`resolve`); the boundary stays, typed = `objN`/`longN`; the knob keeps its meaning = `callN`/`callLongN` under `CLASSLIB_INLINE`; suspension and errors unchanged = the CLASSLIB case keeps the wrapper for the Object flavour; kill-switch `classlib` = Step 7; the test file = Step 1 (one op per arity and flavour, a `:tc` and a non-`:tc` op at arity 2, a suspending op, a throwing op, an arity-5 op, the knob); one commit, engine-only = Step 10. 6.5: gate per commit = Tasks 4-5 Steps 6-9; row b2a with a knob-off CORE.c compile, JFR, census, same-session off/on = Task 6; verify mode = Task 3 Step 3 (once, on the batch 1 tree; the spec's "once after b2b" belongs to part 2). Section 4 amended: the retake rule = Task 2; CORE.c as a clock and the stop-rule reading = Task 6 Step 5. **Deviations, recorded as rulings:** the long flavour's scope (Ruling 1) and "the rig reads every header" implemented as "the largest block" (Ruling 3).

**Placeholder scan.** The `<...>` fields in the ledger templates of Tasks 2, 3 and 6 are measurement slots the executor fills from files it produces in the same task; each template names the file the value comes from. No code step defers content.

**Type consistency.** `NqpClassLibRoad.site(...)` returns `TypedSite?` and the builder tests `ts != null` then `ts.isLong` (a `@JvmField`, read as a field from Java). `TypedSite.name` and `tokenType` are `@JvmField`s read by the census and the calls. `NqpCensus.classlibTyped(site: Any)` is called with a `TypedSite` from Java. `NqpOps.suspendToken(SaveStackException, int)` exists at `NqpOps.java:1073`. `NqpWire.T_INT`/`T_UINT` are public statics. The generated builder methods follow the operation class names: `emitClassLib0`, `beginClassLib1..4`/`endClassLib1..4`, `beginClassLibLong1..3`/`endClassLibLong1..3`. Task 4's moved sites keep their names, so Task 5's test asserts on `Ops.chars`/`Ops.elems`/`Ops.decont` counts and the header field only.
