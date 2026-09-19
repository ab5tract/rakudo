# Milestone 8, Phase C: SC demand deserialization -- ledger

Spec: docs/superpowers/specs/2026-09-18-jvm-milestone-8-phase-c-sc-demand-design.md
Plan: docs/superpowers/plans/2026-09-18-jvm-milestone-8-phase-c-sc-demand.md

## C0: the baseline (Task 1)

Tree: rakudo 2338bc426c / nqp 62fa7ea9f (row b2b's tree, Phase B parked there).

| row | rakudo | nqp | cold rakudo-e | cold nqp-e | misses | hits | warm proxy | notes |
|---|---|---|---|---|---|---|---|---|
| c0 | 2338bc426c | 62fa7ea9f | 2.361 | 1.264 | 4933 | 35843 | 42/sanity | rig wall 63 s |

Row c0 was measured twice. The first rig run shared the box with an IntelliJ
indexing burst (load average 11.6, ~6.5 cores taken) and read 4.436 / 1.909 /
74 s; it is discarded, evidence kept outside the tree. The row above is the
re-run on the idle box, whose five cold walls are 2.54 2.37 2.36 2.46 2.41
(rakudo-e) and 1.31 1.34 1.31 1.35 1.26 (nqp-e), and whose warm proxy line is
`m7-rig: warm t/01-sanity 42s warm=42 red=0 new-red=-` (the TAP is
`m7-rig/c0-sanity.log`). The rig prints the rakudo SHA it sees, `beef32d2a3`
(HEAD: this plan and the spec, docs only); the code tree is 2338bc426c's.

**The 42 s warm proxy is machine state, not a move.** The same proxy on the same
shape (one 8 GB eval server, `t/01-sanity`) read 57 s at the M7 close and 73 s at
B-pre, and nothing in this tree changed between them, so no Phase C row takes
credit against the 42 s: warm-proxy comparisons are only meaningful against a
proxy measured in the same session.

Blob (tools/build/sc-blob-sizes.raku), CORE.c:

```
version=11 len=28167619
deps               88    0.0 %
stTable         66696    0.2 %
stData        4842170   17.2 %
objTable      4418512   15.7 %
objData      14610612   51.9 %
closures       283200    1.0 %
ctxTable        41200    0.1 %
ctxData        176208    0.6 %
repos            4960    0.0 %
strOffsets          0    0.0 %
strings       3723901   13.2 %
counts: stables=5558 objects=276157 closures=11800 contexts=2575 repos=310 strings=13407 deps=11
```

BOOTSTRAP:

```
version=11 len=4216191
deps               72    0.0 %
stTable         13968    0.3 %
stData        1598674   37.9 %
objTable       653824   15.5 %
objData       1827242   43.3 %
closures        14256    0.3 %
ctxTable         9104    0.2 %
ctxData         12770    0.3 %
repos               0    0.0 %
strOffsets          0    0.0 %
strings         86209    2.0 %
counts: stables=1164 objects=40864 closures=594 contexts=569 repos=0 strings=4610 deps=9
```

C0-lite (single runs, 2026-09-17, spec "Baselines"): SC read 304 ms of 1382 ms exclusive load; CORE.c's SC 192 ms; setcodeobj 27116 calls per cold run.

## C1: the format (Task 5)

Tree: rakudo 8ef36555eb (worktree branch, ledger commit on top) / nqp 5f0f54c6e.
Every artifact on disk -- the nine stage0 jars, every built jar -- is format 12;
`MIN_VERSION` is 12 and the reader is one format again.

**Evidence.** Every wall below is named with the `watched-run` log it came from.
The nine logs live in `m7-rig/c1-logs/` -- the same untracked evidence directory
C0 cites, never committed -- and each one ends in its own
`=== EXIT=<n> verdict=<v> elapsed=<s>s ===` line:

```
m7-rig/c1-logs/nqp-c1-window.log    m7-rig/c1-logs/regen-c1.log
m7-rig/c1-logs/make-c1-window.log   m7-rig/c1-logs/configure-c1.log
m7-rig/c1-logs/nqp-suite-c1.log     m7-rig/c1-logs/make-c1.log
m7-rig/c1-logs/sanity-c1.log        m7-rig/c1-logs/rig-c1.log
                                    m7-rig/c1-logs/corec-c1.log
```

Two caveats on that set. `make-c1-window.log` holds only the third, successful
`make` of the window build: `watched-run` truncates its log per run, so the two
one-second failures quoted under "A note on the window build" were overwritten
and survive only as the quotations there. And the two *window* gate logs
(`nqp-suite-c1-window`, `sanity-c1-window`) were not copied across; the window
gate walls below are reported without a log to point at, while the clean-build
gate walls all have one.

| row | rakudo | nqp | cold rakudo-e | cold nqp-e | misses | hits | warm proxy | notes |
|---|---|---|---|---|---|---|---|---|
| c1 | 8ef36555eb | 5f0f54c6e | 2.301 | 1.220 | 4933 | 35843 | 41/sanity | rig wall 60 s |

Against c0 (2.361 / 1.264 / 4933 / 35843 / 42 s): cold rakudo-e -0.060 s
(-2.5 %), cold nqp-e -0.044 s (-3.5 %). Misses and hits are identical to the
digit -- the format change moves bytes, not programs. The rig's five cold walls
are 2.30 2.46 2.31 2.32 2.35 (rakudo-e) and 1.28 1.32 1.27 1.30 1.22 (nqp-e).
The first cold run's dispatch line reads `staleSchema=0 staleStamp=0` (the make
retrained the persisted slots itself: `dispatch-record: done 21 paths, 4228
slots, 4527 programs, 14 unpersistable, 0 failed`). The 41 s warm proxy is
inside c0's 42 s and, per the C0 note, takes no credit. The rig's own log is
`m7-rig/c1-logs/rig-c1.log` (60 s wall) and its per-run files are the
`m7-rig/c1-*` set, where the `staleSchema=0 staleStamp=0` dispatch lines are.

### The two builds

| step | wall | result | log |
|---|---|---|---|
| window: `./nqp/gradlew -p nqp clean` | 1 s | ok | -- (run bare) |
| window: `./nqp/gradlew -p nqp buildJvm` (version-11 stage0, dual reader) | 186 s | BUILD SUCCESSFUL | `m7-rig/c1-logs/nqp-c1-window.log` |
| window: `make clean` + `make` | 803 s | EXIT=0, `dispatch-record: done ... 0 failed` | `m7-rig/c1-logs/make-c1-window.log` |
| window gate: nqp suite (sweep, 160 files) | 190 s | EXIT=0 verdict=ok | not copied (see Evidence) |
| window gate: warm `t/01-sanity` (25 files) | 62 s | 0 FAIL | not copied (see Evidence) |
| window gate: `nqp/t/jvm/23-sc-demand.t` | 3 s | 24/24 PASS | -- (prove, on the terminal) |
| regen: `./nqp/gradlew -p nqp jBootstrapFiles` | 1 s | BUILD SUCCESSFUL, nine stage0 jars modified, all `version=12` | `m7-rig/c1-logs/regen-c1.log` |
| clean: `perl Configure.pl --backends=jvm --gen-nqp` | 188 s | BUILD SUCCESSFUL (bootstrapped from the version-12 stage0 under the one-format reader) | `m7-rig/c1-logs/configure-c1.log` |
| clean: `make` | 800 s | EXIT=0, `dispatch-record: done 21 paths, 4228 slots, 4527 programs, 14 unpersistable, 0 failed` | `m7-rig/c1-logs/make-c1.log` |

**A note on the window build.** The brief expected `gradlew clean` + `make` to
rebuild the nqp bootstrap; it does not. The Makefile's only gradle edge is
`nqp-runtime.jar` -- nothing there rebuilds stage1/stage2 -- so the bare `make`
died in one second on a missing `org.graalvm.truffle` module. The window build
is therefore the two commands above: `gradlew -p nqp buildJvm` (this is the step
that reads the version-11 stage0 through the dual reader) and then, because the
rakudo blib jars still carried the old nqp SC handles ("Missing or wrong version
of dependency .../stage2/NQPHLL.nqp"), `make clean` + `make`.

### Gates on the clean build

| gate | wall | result | log |
|---|---|---|---|
| `./nqp/gradlew -p nqp :nqp-runtime:test` | 3 s | BUILD SUCCESSFUL | -- (run bare) |
| `nqp/t/jvm/23-sc-demand.t` | 3 s | 24/24, Result: PASS | -- (prove, on the terminal) |
| nqp suite (sweep, 160 files) | 188 s | EXIT=0 verdict=ok | `m7-rig/c1-logs/nqp-suite-c1.log` |
| warm `t/01-sanity` (25 files) | 60 s | 0 FAIL | `m7-rig/c1-logs/sanity-c1.log` |
| the rig | 60 s | `m7-rig: DONE tag=c1` | `m7-rig/c1-logs/rig-c1.log` |

### CORE.c

**One** compile on the idle box (load average 0.95 before it), 226 s wall
(`m7-rig/c1-logs/corec-c1.log`), against row b2b's 243-245 s: **-17 to -19 s,
-7.0 to -7.8 %**.

| stagestat | b2b (census run) | c1 | delta |
|---|---|---|---|
| parse | 187.7 | 173.667 | -14.0 |
| optimize | 22.2 | 20.370 | -1.8 |
| qast | 15.7 | 15.211 | -0.5 |
| unit | 17.2 | 16.027 | -1.2 |

**How much weight this table carries.** One compile is one compile: it was not
re-run (the no-re-run rule), so there is no c1 spread to put beside it, and
b2b's column is a **cross-session** census figure -- the 2 s same-session spread
B2 measured is the floor on what a difference has to clear before it means
anything, and these deltas are read across sessions, where the floor is higher
still and unmeasured. So:

* **No mechanism is claimed for `parse`'s -14 s.** It is the largest delta in
  the table and it is unexplained. The plausible story -- that stage loads
  BOOTSTRAP and the settings CORE.c depends on, and those blobs are 52-63 %
  smaller -- is a hypothesis this row does not test, and -14 s is far more than
  Phase C has any business moving in a parse. It wants a second compile, or a
  profile, before anyone builds on it.
* `unit` is the stage the format-12 writer demonstrably runs inside, so its
  -1.2 s is the delta with a known mechanism available. Even there, one compile
  against a cross-session number supports "the new writer is not a compile-time
  regression" and not a claimed -7 %.

What this row does establish is the negative: **format 12 did not make the
compile slower**, and it did that while writing 52 % fewer bytes.

The in-build CORE.c of the clean `make` is a second, differently-conditioned
data point in the same direction (`m7-rig/c1-logs/make-c1.log`, lines 71-76 --
read from that log, not carried over from the standalone compile, which read
16.027): parse 183.435 / optimize 20.591 / qast 15.688 / unit 16.026.

### The blob

CORE.c, `tools/build/sc-blob-sizes.raku`, before (c0, format 11) -> after (c1,
format 12): **28,167,619 -> 13,488,797 bytes, -14,678,822 (-52.1 %)**.

```
version=12 len=13488797
deps               88    0.0 %
stTable         66696    0.5 %
stData        1759036   13.0 %
objTable      2209256   16.4 %
objData       5335709   39.6 %
closures       283200    2.1 %
ctxTable        41200    0.3 %
ctxData         64674    0.5 %
repos            4960    0.0 %
strOffsets      53632    0.4 %
strings       3670274   27.2 %
counts: stables=5558 objects=276157 closures=11800 contexts=2575 repos=310 strings=13407 deps=11
```

Per segment, CORE.c: stData 4,842,170 -> 1,759,036 (-63.7 %), objTable
4,418,512 -> 2,209,256 (-50.0 %, exactly: 16-byte rows became 8-byte rows),
objData 14,610,612 -> 5,335,709 (-63.5 %), ctxData 176,208 -> 64,674 (-63.3 %),
strings 3,723,901 -> 3,670,274 + 53,632 strOffsets (+0.0 % together: the
length prefix became an offset table, same bytes). stTable, closures, ctxTable,
repos and deps are unchanged fixed-width rows, and every count is identical.

BOOTSTRAP: **4,216,191 -> 1,563,293 bytes, -62.9 %**.

```
version=12 len=1563293
deps               72    0.0 %
stTable         13968    0.9 %
stData         513077   32.8 %
objTable       326912   20.9 %
objData        596154   38.1 %
closures        14256    0.9 %
ctxTable         9104    0.6 %
ctxData          3465    0.2 %
repos               0    0.0 %
strOffsets      18444    1.2 %
strings         67769    4.3 %
counts: stables=1164 objects=40864 closures=594 contexts=569 repos=0 strings=4610 deps=9
```

Jars on disk:

| artifact | before | after | delta |
|---|---|---|---|
| `blib/CORE.c.setting.jar` | 56,412,944 (remembered, pre-c1 jar overwritten) | 41,737,626 | -26.0 % |
| `blib/Perl6/BOOTSTRAP/v6c.jar` | -- | 9,121,372 | -- |

The CORE.c "before" is carried in from the Task 5 brief, not measured in this
tree: the c0 jar was overwritten by the window build before anyone ran `ls -l`
on it. The blob figures above it are the ones with provenance on both sides
(C0's section records 28,167,619 from its own run of the tool).

The nine regenerated stage0 jars (working-tree change, never committed):
ModuleLoader 24,770 / NQPCORE.setting 190,367 / NQPHLL 496,963 / nqp 903,548 /
nqpmo 203,302 / NQPP6QRegex 485,901 / QAST 730,590 / QASTNode 198,422 /
QRegex 259,762 -- 3,493,625 bytes in total, every one `version=12`.

### Ruling

**The STable row stays 12 bytes in format 12.** The third int is the REPR-data
offset `peekAttributeShape` needs until Task 6 makes the shape reachable another
way; at 5558 STables that is 22 KB of CORE.c's 13.5 MB (0.16 %), so it buys
nothing to pack it now and it would cost the Task 6 road its only cheap entry
into an STable's REPR data.

### Two reader items from Task 4's review, folded in

`P6int`, `P6num` and `VMArray` dropped their `version >= 7` / `>= 8` guards in
`deserialize_repr_data` (dead since `MIN_VERSION` passed 8; the reads are
unchanged), and `checkAndDisectInput` now rejects a blob whose
`(entries + 1) * 4` string offset table overruns the data. Self-review of the
version-11 removal: the only `version` comparison left in the whole runtime is
the header's `if (version < MIN_VERSION || version > CURRENT_VERSION)`.

## C2: the demand reader (Task 8)

Tree: rakudo ebffa026a4 / nqp dd159b2a7. Runtime jars current (the last
Task 7 round rebuilt `nqp-runtime.jar`, `nqp-truffle.jar` and
`rakudo-runtime.jar` and retrained); no setting recompile, no eval server
left running before the gates.

**Evidence.** Every wall below is named with the log it came from. The
logs live in `m7-rig/c2-logs/` (untracked, never committed), each ending
in its own `=== EXIT=<n> verdict=<v> elapsed=<s>s ===` line; the rig's
per-run files are the `m7-rig/c2-*` set.

```
m7-rig/c2-logs/nqp-suite-c2.log        m7-rig/c2-logs/rig-c2.log
m7-rig/c2-logs/nqp-suite-c2-eager.log  m7-rig/c2-logs/corec-c2.log
m7-rig/c2-logs/sanity-c2.log           m7-rig/c2-logs/sc-demand-eager-verbose.log
```

| row | rakudo | nqp | cold rakudo-e | cold nqp-e | misses | hits | warm proxy | notes |
|---|---|---|---|---|---|---|---|---|
| c2 | ebffa026a4 | dd159b2a7 | 2.273 | 1.183 | 4933 | 35843 | 43/sanity | rig wall 63 s |

Against c0 (2.361 / 1.264): cold rakudo-e **-0.088 s (-3.7 %)**, cold
nqp-e -0.081 s (-6.4 %). Against c1 (2.301 / 1.220): cold rakudo-e
-0.028 s (-1.2 %), cold nqp-e -0.037 s (-3.0 %) -- both inside c1's own
five-run spread (2.30-2.46 and 1.22-1.32), so this row claims no move
against c1 on the cold clock. Misses and hits are identical to the digit
across all three rows. The rig's five cold walls are 2.27 2.34 2.38 2.29
2.31 (rakudo-e) and 1.24 1.22 1.27 1.18 1.33 (nqp-e); best runs
`m7-rig/c2-rakudo-e-run1.err` and `m7-rig/c2-nqp-e-run4.err`. The first
cold run's dispatch line reads `staleSchema=0 staleStamp=0`. `publishes=`
fell 14858 (c1) -> 10280, which is the STables not finished (3901 of
5558 read) no longer republishing. The 43 s warm proxy is inside c0's
42 s and c1's 41 s and, per the C0 note, takes no credit.

Load before each timed step (1-min average): rig 0.95; CORE.c compile
**2.33** (still decaying from the rig, which had finished about 90 s
earlier; `vmstat` showed 0 runnable and 75 % idle). Throughout the session
the box showed about 25 % iowait with four blocked tasks that no process
of this user accounts for (no D-state process visible); it was present
under both timed steps and is named here rather than silently re-run.

### Gates

| gate | wall | result | log |
|---|---|---|---|
| `./nqp/gradlew -p nqp :nqp-runtime:test` | 1 s | BUILD SUCCESSFUL (up to date: nothing changed since Task 7's green run) | -- (run bare) |
| `nqp/t/jvm/23-sc-demand.t` | 7 s | 31/31, Result: PASS | -- (prove, on the terminal) |
| nqp suite (sweep, 160 files) | 197 s | `160 files in 197s`, EXIT=0 verdict=ok, no `not ok` | `m7-rig/c2-logs/nqp-suite-c2.log` |
| nqp suite, `NQP_SC_EAGER=1` (sweep, 160 files) | 199 s | **EXIT=1**: 159 of 160 files green (Files=158 + 2, Tests=13343 + 16); `t/jvm/23-sc-demand.t` fails test 28 | `m7-rig/c2-logs/nqp-suite-c2-eager.log` |
| warm `t/01-sanity` (25 files) | 45 s | `25 files in 45s`, 0 FAIL | `m7-rig/c2-logs/sanity-c2.log` |
| the rig | 63 s | `m7-rig: DONE tag=c2` | `m7-rig/c2-logs/rig-c2.log` |

**The eager gate's one red is the test's construction, not the reader.**
Test 28 is `and fewer than all of them`: the test's "lazy" child takes
`nqp::getenvhash()` and adds `NQP_UNIT_LOAD_STATS`, so under a suite-wide
`NQP_SC_EAGER=1` the child inherits the eager knob and finishes everything,
`not ok 28 - and fewer than all of them (2989 of 2989)`
(`m7-rig/c2-logs/sc-demand-eager-verbose.log`). Test 30 (`every object is
finished` under the knob) passes in the same run. The other 159 files --
`t/serialization/*` included -- are green under both modes, which is what
the gate exists to show (spec risk 2, demand order changing behaviour).
The spec's gate reads "no `not ok` in either", so as written it is red by
this one test; the fix is one line in the test (drop `NQP_SC_EAGER` from
the lazy child's environment) and is not made in this task. A green sweep
prints no `Files=`/`Tests=` totals, so the plain run's test count is not
on record to compare against the eager run's 13359.

### The exit finding

CORE.c's line after `-e 'say 1'` (best run, `m7-rig/c2-rakudo-e-run1.err`):

```
sc-demand 6DDBA3D53BF6003AAC5A4C4904CCCCC0E610ECAB stables=3901/5558 objects=150176/276157 closures=9059/11800 contexts=1354/2575 drains=9644 ms=138.59
```

Identical counts in all five rakudo-e runs and in Task 7's single
measurement; the demand time ranges 129.13-171.70 ms across the five.
Shares: objects **54.4 %**, STables 70.2 %, closures 76.8 %, contexts
52.6 %. nqp-e's largest SC (the `nqp` unit's, `m7-rig/c2-nqp-e-run4.err`):

```
sc-demand 77E5C598B379703C6F8BD42379F3E73FBCAB095F-0 stables=21/23 objects=2722/2989 closures=6/8 contexts=6/8 drains=401 ms=5.57
```

(91.1 % of its objects). Over every SC in the rakudo-e run the exit lines
sum to 195291 of 341899 objects and 211.89 ms of demand time; in the nqp-e
run, 6692 of 8011 and 28.08 ms.

### Exclusive load time (`tools/build/unit-load-exclusive.raku`, each row's best rig run)

| stage | c0 (`c0-rakudo-e-run3`) | c1 (`c1-rakudo-e-run1`) | c2 (`c2-rakudo-e-run1`) |
|---|---|---|---|
| deserialize-program | 811.3 | 733.8 | **593.3** |
| load-block | 612.0 | 637.4 | 706.0 |
| sc-stub + sc-finish | 101.5 + 228.4 = 329.9 | 43.1 + 222.5 = 265.6 | -- |
| sc-load | -- | -- | **54.9** |
| open-store | 37.0 | 25.3 | 24.4 |
| shells | 11.7 | 16.6 | 14.9 |
| static-lex-drain | 0.3 | 0.4 | 0.3 |
| total | 1802.1 | 1679.0 | 1393.8 |

CORE.c's own SC: c0 `sc-stub` 70.71 + `sc-finish` 158.49 = 229.2 ms; c1
22.06 + 141.48 = 163.5 ms; c2 `sc-load` 50.20 ms plus 138.59 ms of demand at
exit. The demand time is charged to whichever stage triggered it
(`deserialize-program` and `load-block` above), so the c2 column is not
"the SC read went away": the SC work of the run is the 54.9 ms `sc-load`
plus the 211.89 ms on the exit lines, **266.8 ms, against c1's 265.6 ms
and c0's 329.9 ms**. The spec's C0-lite table (single run, 1382.1 ms
total, `deserialize-program` 451.4) was taken under different conditions
from the rig rows and is not put in this column. No mechanism is claimed
for the load-block's rise or the gap between the exclusive total's fall
(-408 ms against c0) and the wall's (-88 ms).

nqp-e, the same tool: c0 629.6 ms (sc-stub 6.8 + sc-finish 17.0), c1 583.4
(4.1 + 15.1), c2 553.5 (`sc-load` 1.2, plus 28.08 ms of demand).

### CORE.c

**One** compile (load 2.33 before it, see above), **231 s** wall
(`m7-rig/c2-logs/corec-c2.log`), against c1's 226 s: +5 s (+2.2 %). The
brief expected it near c1's; it is, within what one compile against one
compile can tell apart. Not re-run (the no-re-run rule), so no spread and
no mechanism.

| stagestat | c1 | c2 | delta |
|---|---|---|---|
| parse | 173.667 | 177.844 | +4.2 |
| optimize | 20.370 | 20.680 | +0.3 |
| qast | 15.211 | 15.119 | -0.1 |
| unit | 16.027 | 16.216 | +0.2 |

Sizes, unchanged by this row as they should be (the writer did not change):
the built `blib/CORE.c.setting.jar` blob `version=12 len=13488796`, the jar
41,737,625 bytes (c1: 13,488,797 / 41,737,626 -- the one byte is the
retrain's rebuild at the end of Task 7); BOOTSTRAP `len=1563293`, v6c.jar
9,121,372; the compile's own output jar 41,403,871.

### The C3 decision

**The threshold fired: `150176 / 276157 = 0.544 > 0.5`.** The fixups force
150176 of CORE.c's 276157 objects (54.4 %) after `-e 'say 1'`. By the
spec's Section 3 a C3 is designed; it is **proposed for the user's
decision**, a brainstorm the user starts, not scheduled. The known
candidate: carry the code object in the serialized code-ref table so it
attaches on first `getcodeobj` (as MoarVM's table does) -- compiler-side,
a change to the fixup emission, one full build. The census fact behind it
(spec, Baselines): `Ops.setcodeobj` 27116 calls per cold run against
`getcodeobj` 76, each attaching a code object the reader must finish at
load. Row c2 is its baseline.

What this row gained on the cold clock, best-of-5: rakudo-e **-88 ms against
c0** (60 of them already c1's, the format) and **-28 ms against c1**, the
latter inside c1's run-to-run spread; against the **304 ms honest ceiling**
the row took well under a third, and on this row's own rig numbers the SC
work of a cold run (sc-load 54.9 + demand 211.89 = 266.8 ms) is level with
c1's eager read (265.6 ms). The `deserialize-program` row's exclusive time
is **593.3 ms** (c0 811.3, c1 733.8), with the demand it triggers counted
inside it. CORE.c compile 231 s, one compile, against c1's 226 s, also one
compile: no mechanism claimed either way.

## The close of Phase C (2026-09-19)

Rows c0, c1, c2 are in; the exit finding is stated and the C3 decision
taken by the threshold (proposed, the user's call). Version 12 is the only
format the reader reads; stage0 was regenerated once and stays an
uncommitted working-tree change (the jar rule). Documents written:
`docs/jvm-unit-lazy-loading.md` ("Format 12 and the demand reader"),
`docs/jvm-perf-findings-2026-09.md` ("Milestone 8, Phase C"),
`docs/jvm-truffle-only-plan.md` (the position paragraph) and the spec's
"Revision 1 (as built)".

Open at the close: the eager-gate red above (one line in
`23-sc-demand.t`); the `sh` parameter of `Ops.deserialize` /
`SerializationReader`, now unused (a cleanup); the eager and verify knobs,
removed at the milestone close after the whole-`t/` gate (spec Section 2).
Phase B stays parked at row b2b with plan B (b2c, b2d) and its three items
open. **The two decisions that are the user's:** the C3 brainstorm, and
Phase B's plan B against the milestone close.
