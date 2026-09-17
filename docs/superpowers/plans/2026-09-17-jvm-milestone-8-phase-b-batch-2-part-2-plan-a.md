# Milestone 8 Phase B, batch 2 part 2, plan A: the table-road switch and row b2b Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `NqpOps.run0`, the table road's 380-arm switch, into four methods under HotSpot's 8000-byte huge-method limit so it is JIT-compiled under default flags on every runner; land the three housekeeping items of spec 6.6 (the verify banner off stderr, a `classlibLong=` census field, a huge-method tool); measure rig row b2b with the CORE.c clock's first same-session repeat.

**Architecture:** `run0` keeps its signature and becomes a three-threshold dispatcher over `run0a`..`run0d`, each a `switch` over a contiguous op-id range of about 95 arms moved verbatim (eight arms reordered into id order first), each ending in the same `default` throw. A Raku tool (`tools/build/huge-methods.raku`) lists methods over the limit from `javap` and is the split's RED/GREEN evidence. The verify banner prints only when a verify log or the persistence trace knob is set. The census gains a `long` counter bumped by the three `ClassLibLong` nodes, printed as ` classlibLong=N` after `classlibTyped=`; the road test asserts it; the rig reads it.

**Tech Stack:** Java (`NqpOps.java`, the table road; a plain static switch, not DSL), Kotlin (`DispatchPersist.kt`, `NqpCensus.kt`), nqp `.t` tests under `prove`, Raku tools (`huge-methods.raku`, `m7-rig.raku`, `jfr-attribute.raku`, `watched-run.raku`).

**Spec:** `docs/superpowers/specs/2026-09-16-jvm-milestone-8-phase-b-promotion-campaign-design.md`, Revision 4, section 6.6 (the finding, the spike, the fix, the housekeeping, the noise floor, the gate), with 6.5 (gates, rows) and the amended sections 4 and 5. Ledger of record: `docs/superpowers/plans/2026-09-16-jvm-milestone-8-phase-b.ledger.md` (the B2a section is the before column; the spike numbers are in 6.6 and in `/home/longwalker/.claude/jobs/584f1b84/tmp/corec-spike-{off,on}*`).

## Global Constraints

- **Worktree only:** `/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records` (rakudo, branch `worktree-jesp-direct-lazy-records`, tip `4ebc08f79f`) and its nested `nqp/` (nqp.git, branch `jesp-direct-lazy-records`, tip `e759c5ed2`). The tool shell refuses `cd`, shell variables in paths, `&&` chains and `find -exec`/`xargs` inside the worktree: spell paths out, one command per call, run from the worktree root; nqp's git is `git -C nqp ...`; rakudo `git status`/`diff` need `--ignore-submodules=all`. Push to `ab5tract` only, never `origin`; never force.
- **Engine and runtime jars only.** No encoder row, no wire change, no stage0 regen, no `make`. Rebuild: `./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars` (seconds); retrain after every rebuild: `RAKUDO_RAKUAST=1 NQP_DISPATCH_RECORD=all /usr/bin/perl rakudo-j-build -e '' 2>&1 | grep -E 'dispatch-record: (done|FAILED)'`; restart any eval server afterwards. The nine modified `nqp/src/vm/jvm/stage0/*.jar` are NEVER committed.
- **Kotlin, never Java, except where the file is already Java** (`NqpOps.java` is the table road's home and stays Java; `NqpRootNode.java` holds the DSL nodes). Tools in Raku. Every debug print env-gated.
- **Ruling 1 (this plan):** the split reorders the eight out-of-id-order arms of `run0` into ascending id order before cutting; a `case` arm is an independent block (the tail's `case OP_THROWPAYLOADLEX: {...}` shape) so reordering is semantically neutral; any `case A: case B:` fall-through group is moved as one unit. The dispatcher's thresholds are the first ids of groups 2-4, computed from the source by the one-liner in Task 2 and recorded in the commit message.
- **Ruling 2 (this plan):** the JVM flag `-XX:-DontCompileHugeMethods` goes in no runner; it is the A/B knob only (spec 6.6, user decision 2026-09-17).
- **Ruling 3 (this plan):** the verify banner `dispatch-verify: on` prints only when `NQP_DISPATCH_VERIFY_LOG` names a log (where it goes pid-prefixed, as today) or `NQP_DISPATCH_PERSIST_TRACE` is set; the exit summary line `dispatch-verify: matched=...` is unchanged (the settle plan reads it).
- **Tests:** `raku -e 'exit run(<prove --exec ./nqp-j-gradle t/jvm/22-classlib-road.t t/jvm/21-op-sites.t t/jvm/20-op-census.t t/jvm/19-type-state.t>, :cwd("nqp")).exitcode'` is the engine trio-plus-one; the nqp suite is `./nqp/gradlew -p nqp testNqp` through `tools/build/watched-run.raku` (8-12 minutes, `run_in_background`, poll every 90 s at most); runtime JUnit `./nqp/gradlew -p nqp :nqp-runtime:test` when the runtime module changes (Task 3).
- **Rows:** every run reported with its wall; a failed benchmark recorded as not gathered, never re-run; `NQP_OP_CENSUS`, `NQP_DISPATCH_RECORD`, `NQP_SITES_OFF`, `NQP_CLASSLIB_INLINE`, `NQP_DISPATCH_PERSIST`, `JAVA_TOOL_OPTIONS` unset for a timed run unless the command sets one; CORE.c compiles on `/usr/bin/perl rakudo-j-build` (B0 Ruling 7), one at a time, nothing else running.
- **Commits:** one per task (Task 4 has two, one per tree); `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE` in the 22:00-22:59 window of 2026-09-17 +0200, increasing (Task 1 22:00, Task 2 22:15, Task 3 22:25, Task 4 22:35 nqp / 22:40 rakudo, Task 5 22:55); the trailer names the model that authored the commit.
- Temporary files under `/home/longwalker/.claude/jobs/584f1b84/tmp` (spelled out in commands).

---

## File structure

rakudo tree:
- `tools/build/huge-methods.raku` — NEW (Task 1): lists JVM methods over 8000 bytecode bytes in class directories, via `javap -c -p`.
- `tools/build/m7-rig.raku` — Task 4: `parse-census` reads `classlibLong=`.
- `docs/superpowers/plans/2026-09-16-jvm-milestone-8-phase-b.ledger.md` — Task 5: the B2b section.
- `m7-rig/` (untracked): the row's files; Task 5 copies the spike attributions there.

nqp tree:
- `nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java` — Task 2: `run0` -> dispatcher + `run0a..run0d`.
- `src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt` — Task 3: the banner condition.
- `nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpCensus.kt` — Task 4: `long` counter, `classlibLong(site)`, the header field.
- `nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java` — Task 4: the three `ClassLibLong` nodes call `classlibLong`.
- `t/jvm/22-classlib-road.t` — Task 4: two asserts, `plan(26)`.

---

### Task 1: the huge-method tool

**Files:**
- Create: `tools/build/huge-methods.raku` (rakudo tree)

**Interfaces:**
- Produces: `raku tools/build/huge-methods.raku DIR [DIR ...]` prints one line per method over the limit (`<last-offset>\t<class file>\t<method signature>`) and a final `huge methods: N`; exit 0 always. Task 2 uses it as RED (`huge methods: 1`, `run0`) and GREEN (`huge methods: 0`).
- Consumes: `javap` on the PATH (Oracle GraalVM 25.2.4).

- [ ] **Step 1: Write the tool**

Create `tools/build/huge-methods.raku`:
```raku
#!/usr/bin/env raku
# List JVM methods whose bytecode runs past HotSpot's HugeMethodLimit
# (8000 bytes). With DontCompileHugeMethods at its default (true) such a
# method is never JIT-compiled: NqpOps.run0, the table road's switch,
# was one (milestone 8, B2, spec 6.6). Reads `javap -c -p` for every
# .class under the given directories; only instruction lines count
# (a switch table's case labels are indented deeper and are skipped).
#
#   raku tools/build/huge-methods.raku nqp/nqp-truffle/build/classes/java/main \
#       nqp/nqp-truffle/build/classes/kotlin/main nqp/nqp-runtime/build/classes/kotlin/main
sub MAIN(*@dirs) {
    my @hits;
    for @dirs -> $dir {
        for classes-under($dir.IO) -> $class {
            my $p = run 'javap', '-c', '-p', $class.Str, :out, :err;
            my $name = '';
            for $p.out.lines -> $l {
                # A method header: two-space indent, a signature ending in ');'
                if $l ~~ / ^ '  ' \S .* '(' .* ')' ';' $ / { $name = $l.trim; next }
                # An instruction line: 1-7 spaces, offset, colon, an opcode name.
                if $l ~~ / ^ \s ** 1..7 (\d+) ':' \s+ <[a..z]> / {
                    if +$0 > 8000 && $name ne '' {
                        @hits.push([+$0, $class.Str, $name]);
                        $name = '';
                    }
                }
            }
        }
    }
    for @hits.sort(-*[0]) -> $h { say "$h[0]\t$h[1]\t$h[2]" }
    say "huge methods: { +@hits }";
}

sub classes-under(IO::Path $d) {
    $d.dir.map({ .d ?? classes-under($_).Slip !! (.extension eq 'class' ?? $_ !! Empty) })
}
```

- [ ] **Step 2: Run it on the three compiled modules**

Run: `raku tools/build/huge-methods.raku nqp/nqp-truffle/build/classes/java/main nqp/nqp-truffle/build/classes/kotlin/main nqp/nqp-runtime/build/classes/kotlin/main`
Expected (the jars are built from nqp `e759c5ed2`): exactly one line, `8002	nqp/nqp-truffle/build/classes/java/main/org/raku/nqp/truffle/NqpOps.class	private static java.lang.Object run0(int, java.lang.Object[], org.raku.nqp.runtime.CompilationUnit, org.raku.nqp.runtime.ThreadContext, org.raku.nqp.runtime.CallFrame);` then `huge methods: 1`. (8002 is the first instruction offset past the limit; the method ends at 8541.) Record the wall (about 60 s for ~500 classes). Copy the output to `/home/longwalker/.claude/jobs/584f1b84/tmp/huge-before.txt` for Task 2's RED.

- [ ] **Step 3: Commit (rakudo tree)**

```bash
git add tools/build/huge-methods.raku
GIT_AUTHOR_DATE='2026-09-17 22:00:00 +0200' GIT_COMMITTER_DATE='2026-09-17 22:00:00 +0200' git commit -m "Tools: huge-methods.raku lists JVM methods past the 8000-byte JIT limit (milestone 8, B2)

NqpOps.run0, the table road's switch, is one: never compiled under
default flags, 7.8 % of a CORE.c compile in its own interpreted self
time (spec 6.6). The tool is the split's before/after evidence.

Co-Authored-By: <your model> <noreply@anthropic.com>"
```

---

### Task 2: the split of `run0`

**Files:**
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java:183-652` (`run0`)
- Test: Task 1's tool (RED `huge methods: 1` -> GREEN `0`), the engine tests, the nqp suite

**Interfaces:**
- Consumes: `run(id, rtype, a, cu, tc, cf)` at `NqpOps.java:163-181` calls `run0(id, a, cu, tc, cf)` unchanged.
- Produces: `private static Object run0(int id, Object[] a, CompilationUnit cu, ThreadContext tc, CallFrame cf)` as a dispatcher; `run0a`, `run0b`, `run0c`, `run0d` with the same signature; thresholds `RUN0_T1`, `RUN0_T2`, `RUN0_T3` as `private static final int`s.

- [ ] **Step 1: The RED evidence**

`/home/longwalker/.claude/jobs/584f1b84/tmp/huge-before.txt` from Task 1 reads `huge methods: 1` with `run0`. If Task 1 was not run on these jars, run the tool again first (its Step 2 command).

- [ ] **Step 2: Compute the arm order and the thresholds**

Run:
```
raku -e 'my $src = "nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java".IO.slurp; my %id; for $src ~~ m:g/ (OP_\w+) \s* "=" \s* (\d+) / -> $m { %id{~$m[0]} = +$m[1] }; my @arms = $src.lines.grep(/ ^ \s* "case " OP_\w+ ":" /).map({ ~$_.match(/ (OP_\w+) /)[0] }); my @ids = @arms.map({ %id{$_} }); for 1..^@ids { say "inversion at arm {$_+1}: {@arms[$_-1]}={@ids[$_-1]} then {@arms[$_]}={@ids[$_]}" if @ids[$_] < @ids[$_-1] }; my @sorted = @ids.sort; my $n = +@sorted; say "arms=$n groups of ", ($n/4).ceiling; say "thresholds: T1={@sorted[($n/4).ceiling]} T2={@sorted[2*($n/4).ceiling]} T3={@sorted[3*($n/4).ceiling]}"'
```
Expected: 380 arms, 8 inversion lines (the arms to move), and three thresholds (the first id of groups 2, 3, 4 once the arms are in id order; with 95 per group they are the 96th, 191st and 286th smallest ids). Record the three numbers: they are `RUN0_T1..T3`.

- [ ] **Step 3: Reorder the eight arms**

In `run0`'s switch, move each arm named by an inversion line to its ascending-id position (cut the whole `case ...: ...` block up to the next `case` and paste it before the first arm whose id is larger). A `case A: case B:` fall-through group moves as one block. Re-run Step 2's one-liner: expected `0` inversion lines, thresholds unchanged.

- [ ] **Step 4: Cut into four methods and write the dispatcher**

Replace the `run0` head (`private static Object run0(...) { switch (id) {`) and tail (`default: throw new IllegalStateException("nqpp: unknown op id " + id); } }`) with:
```java
    /* ----- the table road's switch, in four pieces -----
     * One switch over all 380 arms compiled to 8541 bytes, past HotSpot's
     * 8000-byte HugeMethodLimit, and DontCompileHugeMethods (default
     * true) left it interpreted on every runner: 7.8 % of a CORE.c compile
     * in its own self time, 1007 of 2199 table-road samples (milestone 8,
     * B2, spec 6.6). Four pieces of ~95 arms in ascending id order, about
     * 2 KB each, compile under default flags; the dispatcher below is two
     * compares. tools/build/huge-methods.raku guards the limit. */

    private static final int RUN0_T1 = <T1>, RUN0_T2 = <T2>, RUN0_T3 = <T3>;

    private static Object run0(int id, Object[] a, CompilationUnit cu, ThreadContext tc, CallFrame cf) {
        if (id < RUN0_T2) return id < RUN0_T1 ? run0a(id, a, cu, tc, cf) : run0b(id, a, cu, tc, cf);
        return id < RUN0_T3 ? run0c(id, a, cu, tc, cf) : run0d(id, a, cu, tc, cf);
    }

    private static Object run0a(int id, Object[] a, CompilationUnit cu, ThreadContext tc, CallFrame cf) {
        switch (id) {
            // arms with id < RUN0_T1, verbatim, in ascending id order
            default:
                throw new IllegalStateException("nqpp: unknown op id " + id);
        }
    }
    // run0b: RUN0_T1 <= id < RUN0_T2; run0c: RUN0_T2 <= id < RUN0_T3; run0d: id >= RUN0_T3,
    // each with the same shape and the same default arm.
```
with `<T1>`, `<T2>`, `<T3>` the three numbers from Step 2, and the 380 arms distributed by id into the four switches (group 1 = ids below T1, and so on). Nothing inside an arm changes.

- [ ] **Step 5: Rebuild, retrain, GREEN**

Run: `./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars` — expected `BUILD SUCCESSFUL` (a `case` label appearing twice, or an id landing in the wrong method, is a compile error or an `unknown op id` at the first use). Retrain (Global Constraints). Then:
`raku tools/build/huge-methods.raku nqp/nqp-truffle/build/classes/java/main` — expected `huge methods: 0`. Save the output to `/home/longwalker/.claude/jobs/584f1b84/tmp/huge-after.txt`. Also report the four pieces' sizes: `javap -c -p nqp/nqp-truffle/build/classes/java/main/org/raku/nqp/truffle/NqpOps.class | grep -n 'run0[abcd](' ` gives their headers; the last instruction offset of each (from the same javap output) should be roughly 1900-2400.

- [ ] **Step 6: The engine tests and the nqp suite**

Run the trio-plus-one (Global Constraints) — expected all pass. Then:
```
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/584f1b84/tmp/nqp-suite-split-run0.log --show='Files=' --show='Result' --show='BUILD' --stall=900 -- ./nqp/gradlew -p nqp testNqp
```
Expected: `Result: PASS`, `Files=155`. Record prove and gradle walls. Every table op crosses the dispatcher, so a misplaced arm shows up here as `unknown op id`.

- [ ] **Step 7: The flag no longer matters (one CORE.c compile)**

The A/B that proves the split reaches the flagged number is Task 5's row; here one quick check that the split compiled: run
```
RAKUDO_RAKUAST=1 JAVA_TOOL_OPTIONS='-XX:+PrintCompilation' /usr/bin/perl rakudo-j-build -e 'say(1)' 2>&1 | grep -c 'NqpOps::run0'
```
Expected: a count of at least 1 (`run0a`..`run0d` and the dispatcher appear in the compilation log of even a cold start); on the unsplit tree the same command prints `0` for `run0` (huge, never compiled). Record both numbers if you take the before as well (it needs the old jars; optional).

- [ ] **Step 8: Commit (nqp tree)**

```bash
GIT_AUTHOR_DATE='2026-09-17 22:15:00 +0200' GIT_COMMITTER_DATE='2026-09-17 22:15:00 +0200' git -C nqp commit nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java -m "Engine: the table road's switch in four pieces under the JIT's huge-method limit (milestone 8, B2)

run0 compiled to 8541 bytes, past HotSpot's 8000-byte HugeMethodLimit,
and DontCompileHugeMethods (default true) left it interpreted on every
runner: 1007 of 2199 table-road samples in its own self time on a
CORE.c compile, and -XX:-DontCompileHugeMethods alone took the compile
from 266 s to 246 s (spec 6.6). Four pieces of ~95 arms in ascending
id order (eight arms reordered, no arm changed), thresholds
RUN0_T1=<T1> RUN0_T2=<T2> RUN0_T3=<T3>, a two-compare dispatcher; the
flag goes in no runner. tools/build/huge-methods.raku: 1 -> 0.

Co-Authored-By: <your model> <noreply@anthropic.com>"
```

---

### Task 3: the verify banner off stderr

**Files:**
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt:96-101` (`init`)
- Test: `nqp/t/nqp/114-pod-panic.t` under `NQP_DISPATCH_PERSIST=verify` (RED `not ok 1` -> GREEN `ok 1`); runtime JUnit

**Interfaces:**
- Consumes: `verifySay(text)` (`:91-94`: stderr when `verifyLog == null`, else the pid-prefixed log), `verifyLog` (`:41`), `TRACE` (`:44`, `NQP_DISPATCH_PERSIST_TRACE`).
- Produces: the banner printed only under `verifyLog != null || TRACE`; the exit summary unchanged.

- [ ] **Step 1: RED**

Run: `NQP_DISPATCH_PERSIST=verify raku -e 'my $p = run <prove -v --exec ./nqp-j-gradle t/nqp/114-pod-panic.t>, :cwd("nqp"), :out, :err; print $p.out.slurp; say "exit=", $p.exitcode'`
Expected: `not ok 1` (the child nqp inherits the knob and prints `dispatch-verify: on` first on stderr, breaking the test's `^`-anchored match), `exit=1`. Record the wall (~3 s).

- [ ] **Step 2: The change**

In `DispatchPersist.kt`, replace
```kotlin
        if (mode == Mode.VERIFY) {
            verifySay("dispatch-verify: on")
```
with
```kotlin
        if (mode == Mode.VERIFY) {
            /* The banner goes to the log (pid-prefixed) or, on request, to
             * stderr; never to a child's bare stderr, which a test may
             * anchor a match on (t/nqp/114-pod-panic.t under a verify
             * suite, milestone 8 B2). The exit summary below stays. */
            if (verifyLog != null || TRACE) verifySay("dispatch-verify: on")
```
Nothing else changes; the shutdown hook's summary line is untouched.

- [ ] **Step 3: Rebuild, retrain, GREEN, runtime JUnit**

Run: `./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars`; retrain (Global Constraints). Then Step 1's command — expected `ok 1`, `exit=0`. Then one verify run of the settle plan's file to show the summary still prints: `NQP_DISPATCH_PERSIST=verify raku -e 'my $p = run <./nqp-j-gradle -e 1>, :cwd("nqp"), :out, :err; print $p.err.slurp'` — expected exactly one line, `dispatch-verify: matched=... byOutcome=... mismatched=... unseen=...`, and no `dispatch-verify: on`. Then `./nqp/gradlew -p nqp :nqp-runtime:test` — expected `BUILD SUCCESSFUL` (69 tests; record the wall).

- [ ] **Step 4: Commit (nqp tree)**

```bash
GIT_AUTHOR_DATE='2026-09-17 22:25:00 +0200' GIT_COMMITTER_DATE='2026-09-17 22:25:00 +0200' git -C nqp commit src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchPersist.kt -m "Dispatch: the verify banner prints to the log or under the trace knob, not to a child's stderr (milestone 8, B2)

Under NQP_DISPATCH_PERSIST=verify every child inherited the knob and
printed 'dispatch-verify: on' first on stderr, which t/nqp/114-pod-panic.t
anchors a match on: a whole verify suite failed on an artefact (batch 1's
settle plan). The exit summary line is unchanged.

Co-Authored-By: <your model> <noreply@anthropic.com>"
```

---

### Task 4: the `classlibLong=` census field

**Files:**
- Modify: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpCensus.kt:36,75-81,126`
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java` (the three `ClassLibLong` nodes' census call, lines 332, 347, 362 today)
- Modify: `nqp/t/jvm/22-classlib-road.t:15,111,120`
- Modify: `tools/build/m7-rig.raku:89-106` (rakudo tree)

**Interfaces:**
- Produces: `NqpCensus.classlibLong(site: Any)` (the per-name bump, the typed total AND a long total); header ` classlibLong=N` appended after `classlibTyped=N`; `parse-census` -> `%r<classlib-long>`, `census-summary` prints `classlibLong=`.
- Consumes: `NqpCensus.classlibTyped(site)` (`:78-81`), the header line (`:126`), the road test's `header-field` helper (`:71`).

- [ ] **Step 1: The failing asserts**

In `nqp/t/jvm/22-classlib-road.t`: change `plan(24);` to `plan(26);`; after line 111 (`ok(header-field($typed[1], 'classlibTyped') >= 2000, ...)`) add
```perl
ok(header-field($typed[1], 'classlibLong') >= 1000, 'chars, context-free INT, travels the long flavour (classlibLong=)');
```
and after line 120 (`is(header-field($variadic[1], 'classlibTyped'), 0, ...)`) add
```perl
is(header-field($variadic[1], 'classlibLong'), 0, 'NQP_SITES_OFF=classlib builds no long node either');
```
Run: `raku -e 'exit run(<prove --exec ./nqp-j-gradle t/jvm/22-classlib-road.t>, :cwd("nqp")).exitcode'` — expected 2 failures of 26 (the field is absent, `header-field` answers -1: the first `ok` fails, the `is` gets -1 for 0).

- [ ] **Step 2: The census**

In `NqpCensus.kt`, next to `private val typed = LongAdder()` (line 36) add `private val long = LongAdder()`; after `classlibTyped` (ends line 81) add:
```kotlin
    /** A call through the long flavour (context-free INT/UINT ops of arity
     *  1-3, plan Ruling 1): the typed total above plus the header's
     *  classlibLong= total, so a test can tell the two flavours apart. */
    @JvmStatic @TruffleBoundary fun classlibLong(site: Any) {
        classlibTyped(site)
        long.increment()
    }
```
and change the header line (126) to end `... classlibTyped=${typed.sum()} classlibLong=${long.sum()}")`. In `NqpRootNode.java`, in `ClassLibLong1`, `ClassLibLong2`, `ClassLibLong3` only, change `NqpCensus.classlibTyped(s)` to `NqpCensus.classlibLong(s)` (three lines; the five Object-flavour nodes keep `classlibTyped`).

- [ ] **Step 3: Rebuild, retrain, GREEN**

Run: `./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars`; retrain. Then Step 1's prove command — expected 26/26. Then the trio-plus-one — expected all pass (`20-op-census.t` reads the header by its `op census: table=` prefix only).

- [ ] **Step 4: The rig reads the field**

In `tools/build/m7-rig.raku` `parse-census`, extend the optional group: replace
```raku
                  [ ' classlibTyped=' (\d+) ]? / {
        %r<table> = +$0; %r<classlib> = +$1; %r<site-calls> = +$2; %r<site-misses> = +$3;
        %r<classlib-typed> = +$4 if $4.defined;
```
with
```raku
                  [ ' classlibTyped=' (\d+) ]? [ ' classlibLong=' (\d+) ]? / {
        %r<table> = +$0; %r<classlib> = +$1; %r<site-calls> = +$2; %r<site-misses> = +$3;
        %r<classlib-typed> = +$4 if $4.defined;
        %r<classlib-long> = +$5 if $5.defined;
```
and in `census-summary` change `classlibTyped={%r<classlib-typed> // '-'} ` to `classlibTyped={%r<classlib-typed> // '-'} classlibLong={%r<classlib-long> // '-'} `. Check: `raku tools/build/m7-rig.raku --parse-census=m7-rig/b2a-corec-census.err` prints `classlibTyped=475195846 classlibLong=-` (a pre-field file), and a fresh `NQP_OP_CENSUS=1 ./nqp/nqp-j-gradle -e 'say(nqp::chars("abc"))'` run from the nqp tree (`raku -e 'my $p = run <./nqp-j-gradle -e say(nqp::chars("abc"))>, :cwd("nqp"), :out, :err, :env(%*ENV, NQP_OP_CENSUS => "1"); print $p.err.slurp'`) shows a header with `classlibLong=` at least 1.

- [ ] **Step 5: Commit (both trees)**

```bash
GIT_AUTHOR_DATE='2026-09-17 22:35:00 +0200' GIT_COMMITTER_DATE='2026-09-17 22:35:00 +0200' git -C nqp commit nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpCensus.kt nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java t/jvm/22-classlib-road.t -m "Engine: the census tells the long flavour apart -- classlibLong= on the header (milestone 8, B2)

Batch 2 part 1's review noted no test could distinguish the long
flavour from the Object flavour (both answer the same value). The three
ClassLibLong nodes now bump a long total next to the typed one, and
t/jvm/22-classlib-road.t asserts it moves for chars and is 0 under the
kill-switch.

Co-Authored-By: <your model> <noreply@anthropic.com>"
```
```bash
GIT_AUTHOR_DATE='2026-09-17 22:40:00 +0200' GIT_COMMITTER_DATE='2026-09-17 22:40:00 +0200' git commit tools/build/m7-rig.raku -m "Tools: the rig reads classlibLong= (milestone 8, B2)

Co-Authored-By: <your model> <noreply@anthropic.com>"
```

---

### Task 5: rig row b2b, the CORE.c clock's same-session repeat, the ledger

**Files:**
- Modify: `docs/superpowers/plans/2026-09-16-jvm-milestone-8-phase-b.ledger.md` (new section `## B2b: the table road's switch` after the B2a section)
- Modify: the two memory files (the status one-liner)
- Produces: `m7-rig/b2b-*`, `m7-rig/rows.md` row `b2b`, `m7-rig/spike-{off,on}-corec-jfr.txt` (copied from the job dir)

**Interfaces:**
- Consumes: Tasks 2-4's jars (rebuilt and retrained in Task 4 Step 3); the B2a section's numbers (266 s road-on JFR compile; 15.7 % classlib container; the census totals); the spike files `/home/longwalker/.claude/jobs/584f1b84/tmp/corec-spike-{off,on}.log`, `corec-spike-{off,on}-jfr.txt`.
- Produces: the row, three CORE.c JFR compiles (two identical under default flags = the same-session spread; one under the flag = the A/B that the split is complete), one census compile, the ledger section.

- [ ] **Step 1: Warm sanity, knob off**

Run:
```
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/584f1b84/tmp/sanity-b2b.log --show='files in' --show='FAIL' --stall=600 -- raku tools/build/evalserver-sweep.raku --chunk='*' --jobs=1 --heap=8 t/01-sanity
```
Expected: `25 files in <n>s across 1 server(s)`, no reds. Record the wall.

- [ ] **Step 2: Rig row b2b with the census**

Run (the six knobs unset):
```
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/584f1b84/tmp/rig-b2b.log --show='m7-rig:' --stall=900 -- raku tools/build/m7-rig.raku --tag=b2b --out=m7-rig --census
```
Expected: `m7-rig: DONE tag=b2b`, the row in `m7-rig/rows.md`, the `m7-rig/b2b-*` census and JFR files.

- [ ] **Step 3: Two identical CORE.c JFR compiles under default flags**

Run twice, one after the other, with `b2b-1` then `b2b-2` in the file names:
```
RAKUDO_RAKUAST=1 JAVA_TOOL_OPTIONS='-XX:FlightRecorderOptions=stackdepth=512 -XX:StartFlightRecording=filename=/home/longwalker/.claude/jobs/584f1b84/tmp/corec-b2b-1.jfr,settings=profile' raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/584f1b84/tmp/corec-jfr-b2b-1.log --show='Stage' --stall=900 -- /usr/bin/perl rakudo-j-build --setting=NULL.c --ll-exception --optimize=3 --target=jar --stagestats --output=/home/longwalker/.claude/jobs/584f1b84/tmp/CORE.c.b2b-1.jar gen/jvm/CORE.c.setting
```
then `raku tools/build/jfr-attribute.raku --ops /home/longwalker/.claude/jobs/584f1b84/tmp/corec-b2b-1.jfr > m7-rig/b2b-1-corec-jfr.txt` (and `-2`). Expected: two walls near 246 s (the spike's flagged number), the table container near 10 %, `run0a`..`run0d` as the table road's leaves instead of `run0`. The pair's difference is the clock's same-session spread.

- [ ] **Step 4: The flag A/B and the census compile**

Run Step 3's command once more with `-XX:-DontCompileHugeMethods ` prepended inside `JAVA_TOOL_OPTIONS` and `b2b-flag` in the names; attribute it. Expected: a wall inside the Step 3 pair's spread (the flag has nothing left to compile). Then the census compile:
```
RAKUDO_RAKUAST=1 NQP_OP_CENSUS=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/584f1b84/tmp/corec-census-b2b.log --show='Stage' --show='op census' --stall=900 -- /usr/bin/perl rakudo-j-build --setting=NULL.c --ll-exception --optimize=3 --target=jar --stagestats --output=/home/longwalker/.claude/jobs/584f1b84/tmp/CORE.c.b2b.census.jar gen/jvm/CORE.c.setting
```
then `raku tools/build/evalserver-sweep.raku --census-block=/home/longwalker/.claude/jobs/584f1b84/tmp/corec-census-b2b.log > m7-rig/b2b-corec-census.err` (check non-empty, header first, `classlibLong=` present). Copy the spike attributions: `cp /home/longwalker/.claude/jobs/584f1b84/tmp/corec-spike-off-jfr.txt m7-rig/spike-off-corec-jfr.txt` and the same for `-on`.

- [ ] **Step 5: The ledger section**

Append after the B2a section:
```markdown
## B2b: the table road's switch (plan A of batch 2 part 2)

Commits: rakudo `<tool sha>` (huge-methods.raku), nqp `<split sha>` (run0 in four pieces, thresholds <T1>/<T2>/<T3>), nqp `<banner sha>` (the verify banner), nqp `<census sha>` + rakudo `<rig sha>` (classlibLong=), and this one.

Gate: huge-methods.raku 1 -> 0 (<wall> s); nqp suite after the split Result: PASS Files=155 (prove <s> / gradle <s>); runtime JUnit 69 (<s>); 114-pod-panic.t under verify not ok -> ok; 22-classlib-road.t 26/26; warm t/01-sanity 25 files in <s> s.

### The spike that opened the row (spec 6.6, taken before this plan, on the b2a tree)

| compile | wall | parse | table road | run0 self samples | files |
| --- | --- | --- | --- | --- | --- |
| flag default | 266 s | 205.2 s | 16.1 % (2199) | 1007 | corec-spike-off*, m7-rig/spike-off-corec-jfr.txt |
| -XX:-DontCompileHugeMethods | 246 s | 190.9 s | 10.2 % (1356) | 105 | corec-spike-on*, m7-rig/spike-on-corec-jfr.txt |

The flag-default compile repeated row b2a's 266 s from the earlier session: the CORE.c clock's first same-configuration repeat, cross-session, delta 0 s.

Rig row (rig wall <s>):

`| b2b | <rakudo> | <nqp> | <cold-rakudo> | <cold-nqp> | <misses> | <hits> | <warm>/sanity | <new-red> | run0 split |`

### The CORE.c clock

| compile | wall | parse | optimize | qast | unit |
| --- | --- | --- | --- | --- | --- |
| b2a JFR (before, previous session) | 266 | 205.5 | ... |
| b2b-1 JFR, default flags | <s> | ... |
| b2b-2 JFR, default flags | <s> | ... |
| b2b-flag JFR, -XX:-DontCompileHugeMethods | <s> | ... |
| b2b census | <s> | ... |

**The clock's same-session spread**: b2b-1 vs b2b-2 = <n> s (<pct> %). From here a batch moves on this clock only outside that spread.

### JFR --ops, CORE.c: b2a -> b2b-1 / b2b-2 / b2b-flag

| container | b2a | b2b-1 | b2b-2 | b2b-flag |
| --- | --- | --- | --- | --- |
| table | 16.8 % (2358) | ... |
| classlib | ... |
| classlib-typed | ... |
| sites / sites2 | ... |
| dispatch | ... |
| interpreter self | ... |
| outside all | ... |

Table road leaves at b2b-1: <run0a..run0d samples, run() samples>.

### The census (b2a -> b2b): table <n> -> <n>, classlib, classlibTyped, classlibLong=<n> (new), siteCalls, siteMisses; top table unchanged in order (iseq_s, atkey, push, getattr_i, atpos ...).

Reading against the stop rule: <did the CORE.c clock leave the spread (b2a 266 vs b2b-1/2)? the warm proxy vs b2a's 46 s and its 6 s floor; the cold rows for the record>. The split's effect equals the spike's flagged number if b2b-1/2 sit within the spread of 246 s, and the b2b-flag compile confirms nothing is left for the flag.

Rulings: (1) the eight reordered arms (plan Ruling 1), listed: <names>; (2) the flag in no runner (plan Ruling 2); (3) the banner condition (plan Ruling 3); (4) the census-gated rows of 6.3 Revision 4 re-read from this census: <atkey/push/atpos/shift/elems and iter/hlllist/hllhash shares at b2b, in or out>; (5) <anything else>.
```
Fill every `<...>`.

- [ ] **Step 6: Commit, memory, push**

```bash
GIT_AUTHOR_DATE='2026-09-17 22:55:00 +0200' GIT_COMMITTER_DATE='2026-09-17 22:55:00 +0200' git commit docs/superpowers/plans/2026-09-16-jvm-milestone-8-phase-b.ledger.md -m "Docs: Phase B ledger -- row b2b, the table road's switch compiled, the CORE.c clock's same-session spread (milestone 8, B2)

Co-Authored-By: <your model> <noreply@anthropic.com>"
```
Memory: prefix the `description:` line of `/home/longwalker/.claude/projects/-home-longwalker-code-raku-x-core-rakudo/memory/milestone-8-stable-assumption.md` and the milestone 8 line of `.../MEMORY.md` with "B2 PLAN A (row b2b) LANDED <date>: rakudo <sha> / nqp <sha>; CORE.c <b2b-1>/<b2b-2> s (spread <n> s) vs b2a 266; NEXT = plan B (6.3 b2c + 6.4 b2d) from b2b's census" and append a paragraph with the same facts to the milestone file.
Push: `git push ab5tract HEAD` and `git -C nqp push ab5tract HEAD` — both fast-forward.

---

## Self-review

**Spec coverage (6.6).** The finding and spike: recorded in Task 5's ledger section from the existing files. The fix (split, no runner flag): Task 2 (Rulings 1-2). Acceptance (within noise of 246 s, `run0` self time collapsed): Task 5 Steps 3-4 and the reading. The housekeeping: 6.2 amended = landed in spec Revision 4 (rakudo 4ebc08f79f, no task); the banner = Task 3 (Ruling 3); `classlibLong=` = Task 4; `testNqp` harness = unscheduled by design. The noise floor: Task 5 Step 3's pair. Gate and row: Tasks 2-5 as 6.6 lists them (runtime + engine jars, retrain, engine tests, nqp suite, warm sanity, rig with census, two JFR compiles + one census compile; one commit for the split, one per housekeeping item). Section 4's retake rule for plan B: Task 5's Ruling 4 re-reads the census-gated rows.

**Placeholder scan.** `<T1>`..`<T3>` are computed by Task 2 Step 2's one-liner and carried into Step 4 and the commit message; the ledger template's `<...>` are measurement slots filled from files the task names; `<your model>` is the attribution rule. No code step defers content.

**Type consistency.** `run0a..run0d` share `run0`'s signature and `default` arm; `RUN0_T1..T3` are `private static final int`s used only in `run0`. `NqpCensus.classlibLong(site: Any)` calls `classlibTyped(site)` (existing) and is called from exactly the three `ClassLibLong` nodes. `parse-census`'s fifth capture is `$5`, matching the sixth group in order (`$0`..`$3` the four totals, `$4` typed, `$5` long). The road test's `header-field` returns -1 when absent, which is why the RED is 2 failures.
