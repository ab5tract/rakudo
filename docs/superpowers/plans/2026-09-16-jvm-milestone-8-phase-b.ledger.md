# Milestone 8, Phase B: the promotion campaign -- ledger

Spec: docs/superpowers/specs/2026-09-16-jvm-milestone-8-phase-b-promotion-campaign-design.md
Plan (opening + B0): docs/superpowers/plans/2026-09-16-jvm-milestone-8-phase-b-opening-and-census.md

## B-pre: the opening commit

Commits: nqp ef18fd750 (stamp plumbing), nqp 299be6d0f (slot schema 2), nqp **da88da8e6**
(parkings), nqp **0619e6a03** (the op census), rakudo 05edf68871 (spec Revision 1), rakudo
a796c94a48 (Makefile order-only runtime jar), rakudo 4506c7d939 (rig `--census`,
`jfr-attribute --ops`, sweep census), plus the final-review fix wave: nqp **cceb673bb** and the
rakudo commit that carries this ledger update.

**SHA note.** The fix wave rewrote nqp 334c1d3bc's subject (it claimed the shed of a parking that
Ruling 2 had already voided) and rebased the two commits above it, so three nqp SHAs moved:
`334c1d3bc -> da88da8e6` (tree-identical, dates and trailer preserved) and
`122408ad7 -> 0619e6a03` (tree-identical replay). Numbers and rows recorded elsewhere in this
ledger under the OLD SHAs -- the rig row b0's nqp column, the bisect points below -- refer to the
same trees and were not re-measured.

Also on the branch, user-requested and not part of this plan: rakudo b1084467f5
(docs/moarvm-startup-analysis.md), rakudo 1560817ab6 (M8 spec Revision 2 / lazy spec Revision 5).

Gate: runtime JUnit 69/69 (Task 3's full run; Task 4 touched only the engine module and gradle
reported `:nqp-runtime:test` UP-TO-DATE in the gate run); nqp suite `Result: PASS` Files=153
Tests=13214, prove 576 s / whole gradle run 821 s; `make` EXIT=0 in **966 s** (the cross-build
scenario under the default persistence -- and a FULL build, see Ruling 5: Task 3's Configure ran
`make clean`), with the training line `dispatch-record: done 21 paths, 4228 slots, 4527 programs,
14 unpersistable, 0 failed` and zero `Too few positionals`; verify
`matched=4447 byOutcome=4 mismatched=0 unseen=774`; `t/01-sanity` 25/25 in **73 s** (one 8 GB eval
server, `evalserver-sweep --chunk='*' --jobs=1`); first cold run after the build
`staleSchema=0 staleStamp=0` (wall 2.382 s, hits=35843 misses=4933, restored=4451
restoredSites=4169 dropped=15 recorded=870 publishes=14858). `lib/.precomp` removed after the make.
`java` is Oracle GraalVM 25.2.4+7.1 (25.0.4+7-LTS-jvmci-25.2-b20) on all of it.

Gate additions from the final-review fix wave (2026-09-16), all three asked for by the reviewer:

(i) **The in-build CORE.c number, knob off and unprofiled.** From the B-pre `make` log
(`/home/longwalker/.claude/jobs/455b5a91/tmp/make-b0.log`, the `blib/CORE.c.setting.jar`
stagestats): parse 238.044 + optimize 21.499 + qast 19.656 + unit 25.203 = **304.4 s**, against the
M7 close's 296 s: **+2.8 %**. This is the point of record the census (356 s) and JFR (319 s) rows
below could not supply, and it is FLAT. A per-op or per-site cost paid by the B-pre commits would
show up here first and largest -- 257 M table ops and 692 M sited calls in one compile -- so this
number is what excludes that whole cost class from row b0's +0.17 s cold-start question.

(ii) **The stamps are live in the shipped artifacts, not merely implemented.**
`unzip -v blib/CORE.c.setting.jar` reports `unit.serialized` CRC-32 = **`485c5fee`** (28,167,619
bytes, Stored). In that same jar's `unit.dispatch`, the handle
`6DDBA3D53BF6003AAC5A4C4904CCCCC0E610ECAB` occurs 497 times, and **137 of those occurrences are
immediately followed by the four little-endian bytes `ee 5f 5c 48`** -- i.e. `PStamp.stamp`
(an `Int`, DispatchSlot.kt:19) = `0x485c5fee`, the CRC of that jar's own `unit.serialized`. The
remaining 360 are `PRef`s, whose next int is an object index (`f0000000`, `d8010000`, ... in the
tail histogram). So the recorded slots really do carry the artifact's CRC under its SC handle.

(iii) **The order-only prerequisite, observed -- with a FINDING about how to observe it.** The
brief's literal check (`touch rakudo-runtime.jar && make -n`) lists `blib/Raku/Grammar.jar`,
`blib/Perl6/Compiler.jar`, `rakudo.jar`, CORE.c/d/e, BOOTSTRAP v6d/v6e, the training stamp and the
runners -- i.e. rakudo.jar and the settings WOULD rebuild, which by the brief's rule is recorded
here as a finding and the Makefile was not touched. But that reading is confounded, and an A/B on
the one variable settles it: with `rakudo-runtime.jar` dated 20:02 and then `touch`ed to now, and
nothing else changed, `make -n` emits **byte-identical** target lists (`diff` empty). The touch
costs zero rebuilds; the order-only `|` in `J_RAKUDO_DEPS_EXTRA` holds.

  What makes the tree stale independently is a pre-existing sub-second timestamp inversion inside
  `blib/` left by the b0 bisect session's jar restore at 21:01:34 -- `make -n --debug=b` says
  `Prerequisite 'blib/Raku/Actions.jar' is newer than target 'blib/Raku/Grammar.jar'`, and their
  mtimes are 21:01:34.195 vs 21:01:33.946 (0.25 s apart). That cascades Grammar -> rakudo.jar ->
  the settings and has nothing to do with either runtime jar. **The lesson for the next
  verification: an order-only claim can only be read off a tree that is otherwise up to date, or
  off an A/B like the one above; a bare `make -n` on a dirty tree proves nothing either way.**

Rulings:
1. stamp 0 for in-process SCs is recorded and compared, not unpersistable (spec Revision 1). An
   in-process SC has no zip entry to CRC, so it gets stamp 0; 0 is a value like any other, so a
   slot that referenced it is restored only against another stamp-0 SC. Cost if wrong (corrected
   by the final review; the first wording had it backwards): an in-process SC's stamp 0 MATCHES any
   other stamp-0 SC under the same handle, so the residual hazard is a mis-restore across two
   in-process SCs sharing a deterministic handle, not a dropped slot. The only stamp-0 handle in
   the trained artifacts is `__6MODEL_CORE__`, covered by the training stamp's dependency on both
   runtime jars.
2. Task 3's saturated-site test is an invariant guard, not red-first: Phase A parking 2 is VOID by
   the cap invariant (install/reset are the only writers; the add only grows while
   size < MAX_PROGRAMS; a filtered array always fits). The redundant store was removed and the
   comment states the invariant.
3. Parking 1 has no unit test: an object with `stInitialized == false` cannot be built cheaply in
   the test support.
4. `NqpCensus.classlib` takes `Any` and casts -- Kotlin refuses a public signature over the
   package-private Java `NqpOps.ClassLibSite`.
5. The plan's Task 3 Configure step lacked `--no-clean`; `Configure.pl` runs `make clean` by
   default, which deleted the build products, so Task 6's `make` became a full build (966 s)
   instead of a partial one.
6. Task 5 widened to `tools/build/evalserver-sweep.raku` (the sweep discarded the server's stderr
   on green chunks; it now emits the census block per chunk under the knob); the rig refuses an
   ambient `NQP_OP_CENSUS`.
7. **The CORE.c census and its JFR ran on the Makefile recipe's runner, `/usr/bin/perl
   rakudo-j-build`, not on `./rakudo-j` as Step 6's command line spelled it.** Step 6 names the
   Makefile's own recipe (`Makefile:1351`, `$(J_RUN_RAKUDO)` = `perl rakudo-j-build`) and compares
   against the M7-close 296 s, and that number belongs to `rakudo-j-build`: it carries
   `-Xss512m -Xmx14g -Dpolyglot.engine.Mode=latency -Dpolyglot.engine.FirstTierCompilationThreshold=1600
   -Dpolyglot.engine.CompilerThreads=1` (milestone 6's tier policy, 434 s -> 297 s), while
   `./rakudo-j` is the stock 4 GB runner with none of it. Running the stock runner would have
   produced a CORE.c number comparable to nothing in this project. Cost if wrong: the CORE.c row
   is on the build's configuration rather than the plain runner's -- which is the configuration
   every CORE.c timing in this project uses.
8. **`t/01-sanity/55-use-trace.t` test 3 fails under `NQP_OP_CENSUS=1` and only under it**, so the
   rig's census sanity sweep reports `chunk 1/1: FAIL` / `Result: FAIL` with exactly that one file
   red (Files=25, Tests=303, Failed 1/3 subtests). The test spawns a child `$*EXECUTABLE` and
   compares the child's **stderr** byte-for-byte against the expected trace; the child inherits
   `NQP_OP_CENSUS=1` and its shutdown hook prints the census block onto that same stderr. This is
   an env-gated diagnostic behaving as designed, not a regression: the gating run (knob off) was
   25/25 green, twice (73 s standalone, 64 s inside the rig). Cost if wrong: none; if a future
   census sweep is ever wanted green, the sweep must clear the knob for the child, not the server.
9. **The census prints only the top 30 table ops and the top 30 classlib ops** (`take(30)` in
   `NqpCensus.print`), so an op that does not appear has an upper bound, not a zero. Bounds at B0:
   rakudo-e < 24 (table) / < 640 (classlib); nqp-e < 2 / < 143; CORE.c < 49,543 / < 4,700,751.
   Consequence for batch 1: `iscont`, `isfalse` and `findmethod` appear on NO workload's printed
   lists and are therefore bounded, not measured. Cost if wrong: a batch-1 op whose true count sits
   just under the cut is ranked lower than it deserves; raising the cut is a one-character change.
   **RESOLVED in the final-review fix wave (nqp cceb673bb): both `take(30)` cuts are gone.** The
   block now prints every table op with a non-zero count and every classlib name, sorted
   descending, and each reader takes its own top N (the rig's parser 8, the sweep's `census-block`
   all of them). The three bounded ops were re-measured on re-taken censuses -- see "The three
   bounded ops, measured" below -- on the two `-e` rows and the sanity sweep. **CORE.c's entries
   stay bounds** and are marked as such: that compile was not re-run (~6 min under the knob), and
   the standing rule is that a benchmark row is recorded, not re-run.
10. **The JFR `--ops` "entry from interpreter" table resolves to the op CLASS, not the op**: every
    row is an `NqpRootNode$XxxOp` node method (`RunOp.doOp`, `ClassLibOp.doCall`,
    `DispatchOp.doDispatch`, `IsTypeOp.doIsType`, ...), because that is the outermost project frame
    above the first generated frame. A per-op share therefore cannot be read off these tables; the
    candidate list below is derived as *the road's JFR share* crossed with *the op's census share
    of that road*, and says so wherever it does.
11. **The two cold rows' JFR recordings are low-resolution by construction**: a 2.5 s and a 1.3 s
    process yield 144 and 68 execution samples, so one sample is 0.7 % and 1.5 % respectively and
    the 1 % line sits below the noise on both. The CORE.c recording (12,956 samples, 1 sample =
    0.008 %) is the only workload where a 1 % reading is meaningful; the cold rows' shares are
    reported for shape, not for ranking.
12. **`NqpCensus.slow` has no callers yet**, so `slow=[]` on every site of every workload is by
    construction, not a finding. Batch 1 adds the named slow paths (istrue.method,
    findmethod.nonauth) the spec's section 2 describes.
13. **Removing the `take(30)` cuts exposed a latent deadlock in `evalserver-sweep.raku`, fixed in
    the same wave.** `run-rakudo-chunk` slurped the chunk's stdout to EOF and only then its stderr.
    With an uncut census (~713 lines on a sanity sweep) the eval server's stderr buffer fills, the
    server blocks in `write(2)` -- inside its census SHUTDOWN HOOK, so it can never exit -- the
    harness waits on the server, and stdout therefore never reaches EOF, so the sweep never reaches
    the stderr slurp that would unblock everything. Measured: the sweep hung for 20 minutes, jstack
    showing `Thread-9` in `FileOutputStream.writeBytes` under `NqpCensus.print:107` (the classlib
    loop) for 741 s while `main` sat in `accept()`. Both handles are now drained concurrently
    (`start { $proc.err.slurp(:close) }`), in `run-rakudo-chunk` and in `run-nqp-chunk`'s `prove`
    helper, which had the identical shape. After the fix the same sweep ran in **51 s**. The
    defect was always there; only a writer big enough to fill the buffer made it reachable. Cost
    if wrong: none foreseen -- a concurrent drain is what every other `run(:out, :err)` in this
    tree should be doing.

Phase A's two open items are closed here: the cross-build stale-slot hazard (the SC stamp, nqp
ef18fd750 + 299be6d0f, exercised by the 966 s cross-build `make` above with `staleStamp=0` after
it) and the Makefile runtime-jar prerequisite question (rakudo a796c94a48, order-only).

## B0: the census baseline

Rig row b0 (rig wall 162 s, all markers present, `m7-rig: DONE tag=b0`), verbatim:

```
| b0 | 4506c7d939 | 122408ad7 | 2.460 | 1.334 | 4933 | 37077 | 64/sanity | none | |
```

Against M7 close (2.247 / 1.198) and row a / `m8a` (2.290 / 1.190): **outside the spread, slower on
both clocks** -- rakudo-e +7.4 % on row a and +9.5 % on the M7 close, nqp-e +12.1 % / +11.4 %. The
five walls behind each best-of-5 were rakudo-e 2.53 2.57 2.46 2.49 2.56 and nqp-e 1.33 1.34 1.36
1.60 1.52, so row a's 2.290 is not inside this run's own spread. Two caveats belong with that
reading, neither of them an excuse: (a) the same series has ranged 2.247-2.461 across sessions for
functionally comparable builds -- M7 Phase B's row `b` was 2.461 on this very benchmark -- so the
cross-session spread is wider than any single row's; (b) the load is not identical either: b0
carries `hits=37077` against row a's 35541 at the *same* `misses=4933`, i.e. ~1.5 k more dispatch
hits per cold start, which is what the schema-2 slot rewrite and the fresh training produced. Per
the standing rule a benchmark row is recorded, not re-run; the controller decides whether the
+0.17 s is worth a bisect before batch 1.

**OPEN ITEM -- the b0 bisect was run and is INCONCLUSIVE** (controller, 2026-09-16): the machine
was loaded (the final review agent and its checks ran concurrently) and the clocks drifted with
TIME, not with commit order: A=2b627034f 2.345 s (runs 2.35-2.51), D=122408ad7 2.579 s (2.58-3.63),
B=299be6d0f 2.814 s (2.81-3.10), C=334c1d3bc 2.954 s (2.95-3.44); nqp-e 1.251 / 1.392 / 1.321 /
1.393. B and C predate D yet measured slower, and single runs reached 3.6 s, so no commit is
implicated by this data. Point A (the quietest slot) at 2.345 vs row a's 2.290 says today's machine
state is itself ~2-3 % slower. Ruling: **the slowdown of row b0 is NOT attributed**; it is recorded
as an open item for the user (re-run the bisect on an idle machine, or take b0 as the Phase B
baseline with this caveat). Cost if wrong: a real 5-10 % cold-start regression carried into
batch 1's rows -- which batch 1's row b1 against b0 will show again if it is real. The nqp tree was
restored to the branch tip afterwards, jars rebuilt, retrained (4190 slots, 0 failed).

The final review adds two counter-points against reading b0 as a real regression:

(a) **The same build's CORE.c compile was flat** -- 304.4 s against the M7 close's 296 s, +2.8 %
    (gate addition (i) above). A per-op or per-site cost introduced by the B-pre commits would be
    magnified enormously by a compile that runs 257 M table ops and 692 M sited calls, so a flat
    CORE.c **excludes that whole cost class**. Whatever moved the cold row is not paid per op.

(b) **`hits` is not a build invariant.** The controller's own first cold run on the *same jars*
    measured 2.382 s with `hits=35843`, against the rig's 2.460 s / 37,077 in the same session. The
    ~1.5 k hit difference that row b0 was partly explained by is therefore run-to-run, not a
    property of the schema-2 slot rewrite.

Next step (not taken here): a same-session reference row on the base jars, plus the one-line
experiment on `DispatchRecord`'s literal-guard capture (revert it, rebuild the jars, retrain, take
cold rows). Both are the controller's call before batch 1.

Warm proxy: `t/01-sanity` 25/25 in 64 s inside the rig, 73 s standalone (both knob-off, one 8 GB
server). Red list unchanged (`new-red=none`).

### The census, per workload

| workload | table | classlib | siteCalls | siteMisses | top table (8) | top classlib (8) |
| --- | --- | --- | --- | --- | --- | --- |
| rakudo-e | 33,369 | 161,944 | 49,581 | 619 | iseq_s 8337, push 7244, atpos 2862, bindkey 2776, hlllist 2433, atkey 2344, hllhash 1565, throwpayloadlex 1262 | Ops.setcodeobj 27116, Ops.decont 26015, Ops.atkey 15692, Ops.atpos 10611, Ops.isnull 10161, Ops.how 8455, Ops.concat 8247, Ops.isconcrete 5544 |
| nqp-e | 22,186 | 26,300 | 12,603 | 66 | iseq_s 6554, push 6528, atpos 2294, bindkey 2184, hlllist 1739, atkey 1021, getattr_s 423, throwpayloadlex 303 | Ops.decont 4937, Ops.concat 3400, Ops.shift 2260, Ops.setcodeobj 1484, Ops.isconcrete 1097, Ops.push 944, Ops.iter 858, Ops.isnull 848 |
| sanity (server) | 3,217,055 | 22,427,812 | 9,468,973 | 25,595 | push 556755, iseq_s 458947, getattr_i 321786, atkey 289215, hlllist 236077, atpos 182748, hllhash 179432, throwpayloadlex 159848 | Ops.decont 6549084, Ops.atkey 1910110, Ops.atpos 1621360, Ops.isnull 1298882, Ops.isconcrete 1122177, Ops.how 994178, Ops.setcodeobj 682630, Ops.elems 555656 |
| CORE.c | 257,104,670 | 1,084,094,672 | 692,228,289 | 3,965 | iseq_s 44743841, atkey 39182428, push 38842755, getattr_i 28136649, atpos 19723991, hlllist 15893894, throwpayloadlex 13152577, getattr_s 9121975 | Ops.decont 499704638, Ops.isconcrete 73421782, Ops.atpos 40878245, Ops.getattr_i 37062390, Ops.bindattr_i 35763164, Ops.atkey 32043494, Ops.isnull 31766412, Ops.who 26441996 |

Sources: `m7-rig/b0-rakudo-e-census.err`, `m7-rig/b0-nqp-e-census.err`,
`m7-rig/b0-sanity-census.log`, `m7-rig/b0-corec-census.err`. All four lists are truncated at 30
rows (Ruling 9) -- these four are the ORIGINAL, cut censuses; the uncut re-takes are the
`*-census2.*` files used by "The three bounded ops, measured" below.

CORE.c clocks, one standalone compile each on `rakudo-j-build` (Ruling 7), output redirected to the
job dir so the build's jar was untouched:

| run | wall | parse | optimize | qast | unit |
| --- | --- | --- | --- | --- | --- |
| `NQP_OP_CENSUS=1` | **356 s** | 281.26 | 26.32 | 21.99 | 25.76 |
| JFR `settings=profile`, knob off | **319 s** | 252.80 | 22.56 | 18.64 | 23.41 |

Against the M7 close's 296 s: the profiled run is +7.8 % and the census run +20 %, so **the census
knob costs about 28 s (+11 %) on CORE.c parse** and JFR about half that. Both are measurement
overhead on a knob-off baseline, not a regression; no knob-off, unprofiled CORE.c compile was taken
in this task (the build's own, inside the 966 s `make`, is the knob-off point of record).

### JFR `--ops`: the "entry from interpreter" tables

Shares as printed are *of the container*; the global column is the container's own share times the
row (Ruling 10). The 1 % line is marked `<-- 1 %` where it falls; on the two cold rows it sits below
the sampling noise (Ruling 11).

**CORE.c** (`m7-rig/b0-corec-jfr.txt`, 12,956 samples: main 12,872, TruffleCompilerThread-53 80).
Containers: table 1991 = 15.4 %, classlib 3459 = 26.7 %, sites 297 = 2.3 %, dispatch 1988 = 15.3 %,
interpreter self 1082 = 8.4 %, outside all 4139 = 31.9 %.

```
== table        (15.4 % of all samples)
   1991  100.0%  NqpRootNode$RunOp.doOp                       -> 15.4 % global
== classlib     (26.7 %)
   3459  100.0%  NqpRootNode$ClassLibOp.doCall                -> 26.7 % global
== sites        ( 2.3 %)
    149   50.2%  NqpRootNode$IsTypeOp.doIsType                -> 1.15 % global
    121   40.7%  NqpRootNode$DecontOp.doDecont                -> 0.93 % global   <-- 1 %
     16    5.4%  NqpRootNode$CreateOp.doCreate                -> 0.12 %
      7    2.4%  NqpRootNode$IsNullOp.doIsNull                -> 0.05 %
      1    0.3%  NqpRootNode$HllizeOp.doHllize                -> 0.01 %
      1    0.3%  NqpLanguage.lambda$parse$0                   -> 0.01 %
      1    0.3%  NqpRootNode$AssertParamCheckOp.doLong        -> 0.01 %
      1    0.3%  NqpRootNode$P6SinkOp.doSink                  -> 0.01 %
== dispatch     (15.3 %)
   1988  100.0%  NqpRootNode$DispatchOp.doDispatch            -> 15.3 % global
```
(Every container's entry table is shorter than 12 rows; these are complete, not truncated.)

**rakudo-e** (`m7-rig/b0-rakudo-e-jfr.txt`, 144 samples). Containers: table 6 = 4.2 %,
classlib 41 = 28.5 %, sites 2 = 1.4 %, dispatch 34 = 23.6 %, interpreter self 33 = 22.9 %,
outside all 28 = 19.4 %.

```
== table     6  100.0%  NqpRootNode$RunOp.doOp          -> 4.2 % global
== classlib 41  100.0%  NqpRootNode$ClassLibOp.doCall   -> 28.5 % global
== sites     1   50.0%  NqpRootNode$CreateOp.doCreate   -> 0.7 % global (= 1 sample)
             1   50.0%  NqpRootNode$P6SinkOp.doSink     -> 0.7 %
== dispatch 31   91.2%  NqpRootNode$DispatchOp.doDispatch -> 21.5 % global
             1    2.9%  NqpLanguage.lambda$parse$0      -> 0.7 %
```

**nqp-e** (`m7-rig/b0-nqp-e-jfr.txt`, 68 samples). Containers: table 4 = 5.9 %,
classlib 11 = 16.2 %, sites 0 = 0.0 %, dispatch 20 = 29.4 %, interpreter self 17 = 25.0 %,
outside all 16 = 23.5 %.

```
== table     4  100.0%  NqpRootNode$RunOp.doOp            -> 5.9 % global
== classlib 11  100.0%  NqpRootNode$ClassLibOp.doCall     -> 16.2 % global
== sites     0                                            -> 0.0 %
== dispatch 19   95.0%  NqpRootNode$DispatchOp.doDispatch -> 27.9 % global
             1    5.0%  NqpRootNode$GetAttrOp.doGet       -> 1.5 % global (= 1 sample)
```

The leaf frames under each container say where the road's time goes. On CORE.c: classlib's leaf is
`NqpOps.classlibInline` 68.7 % of the container (18.3 % global) and `NqpOps.classlib` a further
4.3 %; table's leaf is `NqpOps.run0` 49.2 % (7.6 % global); sites' leaves are `NqpTypeOps.decont`
53.2 %, `Ops.istype_nd` 17.5 %, `NqpTypeOps.istype` 14.5 %, `NqpTypeOps.istypeSlow` 4.4 %; dispatch
has no single leaf above 8 % (`NqpDispatch.enterDirect` 8.0 %, `.matches` 7.2 %,
`StaticCodeInfo.getOLexStatic` 6.0 %, `DispatchProgram.isFresh` 5.9 %, `CallFrame$Companion.outerFor`
5.5 %). Outside all four containers, `sun.misc.Unsafe.putObject` alone is 43.0 % of that bucket
(13.7 % global) -- the object-model/serialization writes of the unit stage, no promotion's business.

### Per site class on rakudo-e (calls / misses / pins / republished / slow)

| site | calls | misses | pins | republished | slow |
| --- | --- | --- | --- | --- | --- |
| DecontSite | 38,037 | 3 | 0 | 0 | [] |
| IsTypeSite | 5,309 | 589 | 135 | 0 | [] |
| CreateSite | 4,264 | 1 | 0 | 0 | [] |
| HllizeSite | 1,535 | 26 | 2 | 0 | [] |
| RvCheckSite | 186 | 0 | 0 | 0 | [] |
| IsConcreteSite | 175 | 0 | 0 | 0 | [] |
| SinkSite | 70 | 0 | 0 | 0 | [] |
| BigIntSite | 5 | 0 | 0 | 0 | [] |

(`siteCalls` double-counts inner DecontSites by design. `slow=[]` everywhere is Ruling 12.)
For scale, the same table on CORE.c: DecontSite 515,219,479 calls / 0 misses / 2,134 republished;
IsTypeSite 126,941,774 / 3,134 / 746 pins / 1,538 republished; CreateSite 28,787,003 / 9;
IsConcreteSite 18,881,445 / 0; HllizeSite 2,116,973 / 796 / 145 / 6,857; RvCheckSite 276,898 / 12;
SinkSite 4,210 / 14; BigIntSite 507 / 0. **692 M sited calls cost 2.3 % of CORE.c's samples while
1.08 G classlib calls cost 26.7 %** -- that ratio, not any single op, is the campaign's case.

### Candidates at >= 1 % on any workload, before batch 1

Read as roads first (the only thing the JFR resolves, Ruling 10), then the ops inside them:

1. **The classlib road, `ClassLibOp.doCall`** -- 26.7 % CORE.c, 28.5 % rakudo-e, 16.2 % nqp-e.
   The largest single promotion target; `classlibInline` is 18.3 % of CORE.c on its own.
2. **The table road, `RunOp.doOp`** -- 15.4 % CORE.c, 4.2 % rakudo-e, 5.9 % nqp-e.
3. **The dispatch road, `DispatchOp.doDispatch`** -- 15.3 % CORE.c, 21.5 % rakudo-e, 27.9 % nqp-e.
   Not a promotion candidate itself; it is what promotion removes traffic *from*.
4. **`IsTypeOp.doIsType`** -- 1.15 % CORE.c global, the only sited op over the 1 % line, and the
   only site class with a real miss rate (IsTypeSite 3,134 misses / 746 pins on CORE.c, 589/135 on
   rakudo-e). `Ops.istype_nd` + `NqpTypeOps.istypeSlow` are 21.9 % of the sites container.
5. **`DecontOp.doDecont`** -- 0.93 % CORE.c global, just under the line, on 515 M calls with zero
   misses: already the cheapest-per-call road in the census and the model the rest should reach.
6. **`NqpOps.readSlot` 1.19 %, `CheckNamedAllowed.doCheck` 0.93 %, `NqpOps.checkarity` 0.90 %**
   (CORE.c, as leaves of the "outside all" bucket) -- calling-convention work, named here because
   they clear the 1 % line, not because batch 1 touches them.

Batch 1 is fixed by design (iscont, istrue/isfalse/Truthy, findmethod/tryfindmethod/can, the three
arms); their B0 "before" column, as census share of their own road (the JFR cannot separate them
from their road, Ruling 10):

#### The three bounded ops, measured (fix wave, 2026-09-16)

With the `take(30)` cuts gone (Ruling 9) the censuses were re-taken on the three cheap workloads,
untimed, knob on, on the fix-wave jars: `m7-rig/b0-rakudo-e-census2.err` (wall 2.49 s),
`m7-rig/b0-nqp-e-census2.err` (1.45 s), `m7-rig/b0-sanity-census2.log` (sweep wall **51 s**,
`chunk 1/1: FAIL` = Ruling 8's `55-use-trace.t` again, Files=25 Tests=303 Failed 1/3 subtests).
CORE.c was NOT re-run (a ~6 min compile under the knob; a benchmark row is recorded, not re-run),
so its column stays as **bounds**, marked. Shares are of the op's own road total on that workload
(rakudo-e table 33,283 / classlib 159,612; nqp-e 22,200 / 26,655; sanity 3,256,099 / 22,490,277);
these re-takes differ from the first censuses by under 1.5 % on every total, which is cold-start
run-to-run variance, not a change.

| op | road | rakudo-e | nqp-e | sanity | CORE.c |
| --- | --- | --- | --- | --- | --- |
| `Ops.istrue` | classlib (26.7 % of CORE.c) | 2,628 = 1.65 % | 147 = 0.55 % | 328,821 = 1.46 % | 9,350,543 = 0.86 % |
| `Ops.can` | classlib | 2,613 = 1.64 % | 87 = 0.33 % | 367,103 = 1.63 % | 5,066,814 = 0.47 % |
| `tryfindmethod` | table (15.4 % of CORE.c) | 29 = 0.09 % | 30 = 0.14 % | 30,686 = 0.94 % | 3,056,057 = 1.19 % |
| `Ops.iscont` | classlib | **402 = 0.25 %** | **0 (a true zero, not a bound)** | **46,713 = 0.21 %** | *bound: < 4,700,751* |
| `Ops.findmethod` | classlib | **42 = 0.03 %** | **19 = 0.07 %** | **7,212 = 0.03 %** | *bound: < 4,700,751* |
| `Ops.isfalse` | classlib | **1 = 0.00 %** | **0 (a true zero)** | **228 = 0.00 %** | *bound: < 4,700,751* |

(`Ops.iscont_i` 4, `Ops.iscont_u` 4, `Ops.iscont_n` 2 on rakudo-e are the sized arms, listed
separately by the census and not folded into `Ops.iscont` above. `Ops.findmethodNonFatal` appears
once as a CORE.c sites leaf, 0.3 % of that container, 0.008 % global.)

What the measurement changes: the three formerly-bounded ops are **smaller than the cut allowed
them to be**, not larger. `iscont` is the biggest of them at a quarter of a per cent of its road;
`isfalse` is one call on a cold rakudo start and 228 on a whole sanity sweep, i.e. effectively
absent; `findmethod` (the fatal arm) is two orders of magnitude below `can`. So batch 1's ranking
is unchanged and now rests on measurement rather than on bounds: the head is `istrue` and `can` on
the classlib road and `tryfindmethod` on the table road, and `iscont`/`isfalse`/`findmethod` enter
the campaign as design symmetry -- which the numbers now justify calling cheap rather than unknown.
Multiplying road share by census share still puts each measurable op at a few tenths of a per cent
of CORE.c time apiece, which is the honest size of batch 1's ceiling on this workload, and the
reason the road-level numbers above are the ones to watch across the batches.

Artifacts (untracked, in the rakudo worktree, `m7-rig/` is not a tracked directory):
`m7-rig/b0.md`, `m7-rig/rows.md`, `m7-rig/b0-{rakudo-e,nqp-e}-{run1..5,census,jfr}.err`,
`m7-rig/b0-{rakudo-e,nqp-e}.jfr`, `m7-rig/b0-{rakudo-e,nqp-e}-jfr.txt`,
`m7-rig/b0-sanity.log`, `m7-rig/b0-sanity-census.log`, `m7-rig/b0-corec-census.err`,
`m7-rig/b0-corec-jfr.txt`; from the fix wave, the uncut re-takes
`m7-rig/b0-{rakudo-e,nqp-e}-census2.err` and `m7-rig/b0-sanity-census2.log`; logs, the 252 MB
`corec-b0.jfr`, `make-b0.log` and the `make -n` A/B captures (`make-n-old.txt`,
`make-n-touched.txt`) under `/home/longwalker/.claude/jobs/455b5a91/tmp/`.
