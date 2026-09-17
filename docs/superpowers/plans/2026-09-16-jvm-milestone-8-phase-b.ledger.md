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
here as a finding and the Makefile was not touched. But that reading is confounded (below), and an A/B
on the runtime jar's mtime alone cannot discriminate on this tree: the control arm already rebuilds
rakudo.jar and every setting through the inversion below, a superset of anything the runtime jar
could trigger, so its byte-identical target lists (`diff` empty) prove nothing either way. What
establishes the claim is the generated Makefile itself: `Makefile:323` reads
`J_RAKUDO_DEPS_EXTRA = | $(RUNTIME_JAR) $(NQP_RUNTIME_JAR)` and `Makefile:1327` puts that expansion
LAST on the `$(RAKUDO_JVM):` prerequisite line, so GNU make takes both jars as order-only; the only
hard reference to the runtime jar is the intended one, `TRAIN_STAMP` (`Makefile.in:196`). The
order-only `|` holds by that reading (final re-review, 2026-09-16).

  What makes the tree stale independently is a pre-existing sub-second timestamp inversion inside
  `blib/` left by the b0 bisect session's jar restore at 21:01:34 -- `make -n --debug=b` says
  `Prerequisite 'blib/Raku/Actions.jar' is newer than target 'blib/Raku/Grammar.jar'`, and their
  mtimes are 21:01:34.195 vs 21:01:33.946 (0.25 s apart). That cascades Grammar -> rakudo.jar ->
  the settings and has nothing to do with either runtime jar. **The lesson for the next
  verification: an order-only claim is read off the generated Makefile text, or observed on a tree
  that is otherwise up to date; a bare `make -n` on a dirty tree proves nothing either way.**

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

**Final re-review residuals (2026-09-16), parked with rulings:**
- `evalserver-sweep.raku` `census-block` selects by prefix over the whole chunk text, so a TAP line
  beginning `  site `/`  table `/`  classlib ` would be lifted even with no census; knob-on only.
  Ruling: deferred; anchor the selection at the first `op census:` line when the sweep is next
  touched. Cost if wrong: a spurious block line in a census log.
- The concurrent drains leave the stderr promise unawaited if the stdout slurp throws. Ruling:
  deferred (a "Promise broken" nag at worst; the pipe still drains).
- The same sequential-slurp shape survives in `tools/build/pr-stack.raku:93-94` and
  `tools/build/dice-spectest.raku:60` (never drains stderr). Ruling: recorded as open items,
  outside this phase.
- `m7-rig/b0-sanity-census2.log` carries every census line twice (the block and the failed-chunk
  dump); the totals were read from the single header line. Cosmetic.

**Integration gate on the final tree (rakudo 98116748c3 / nqp cceb673bb, 2026-09-16 21:56-22:09):**
runtime JUnit 69/69 (up to date), nqp suite Result: PASS, Files=153, Tests=13216 (two more than the
B0 gate: the census test's two child-status asserts), prove 506 s / gradle 735 s; warm t/01-sanity
knob off 25 files in 57 s on one server, no reds.

## B1: batch 1 (the sites)

Commits: nqp **dbf219374** (`IsContSite`), nqp **cbc10aa3d** (`IsTrueSite`: istrue/isfalse and the
`Truthy` object arm; boolification mode 7 ITER folded too), nqp **b514835cb** (`FindMethodSite`:
findmethod/tryfindmethod/can), nqp **24bfcccac** (the decont / isconcrete / create arms; a
source-level `nqp::defined` also reaches `IsConcreteSite`, since it maps onto `Ops.isconcrete`).

Gate: retrain `dispatch-record: done 21 paths, **4191 slots**, 4490 programs, 14 unpersistable,
**0 failed**` (2 s); nqp suite **Result: FAIL** on the first run, Files=154 Tests=13235, **693 s**
-- one red, see below -- and **Result: PASS**, Files=154 Tests=13246, **486 s** on an immediate
re-run of the same tree and the same jars; `t/01-sanity` 25/25 in **41 s** (wall 43 s), one 8 GB
server, no reds; verify `matched=4337 byOutcome=4 **mismatched=0** unseen=884` (2 s). Rig wall
**130 s**, all markers present, `m7-rig: DONE tag=b1`.

**The one red, and why it is recorded as non-reproducing, not as green.** On the first suite run
`t/nqp/023-named-args.t` died before its plan:
`Cannot find method 'ann' on object of type BOOTInt` at `NQP::src/NQP/Actions.nqp` `statementlist`
(the `my $sunk := $ast.ann('sink');` line), i.e. a statement's `.ast` handed back an integer where
a QAST node belongs -- the method lookup itself was right to fail. Files 001-022 and 024-onwards
passed in that same run. It does **not** reproduce: 6/6 standalone passes on
`./nqp-j-gradle t/nqp/023-named-args.t` after the failure, and the whole suite green on the re-run
(the 13246 - 13235 = 11 test difference is exactly this file's eleven tests). Nothing was rebuilt
or changed between the two suite runs. So batch 1's gate is **PASS with one non-reproducing red**,
and the red is left as an open item rather than attributed: the shape (a wrong *value*, not a wrong
method) points first at the standing persisted-slot misbind hazard (M7 Phase C, carried in M8's
status). But batch 1's sites are **UNBISECTED, not exonerated**. The earlier reading -- "none of the
four site classes can hand a caller an Int" -- is not an alibi: a site does not have to invent an
Int, it need only pick the **wrong branch**, and after batch 1 `IsTrueSite` backs *every*
object-typed condition in the compiler while a source-level `nqp::defined` reaches
`IsConcreteSite`. A wrongly folded condition in `statementlist` is exactly the kind of thing that
leaves a wrong value in a variable.

The three facts the evidence actually gives:

1. the message is the **dispatcher's** `langMethNotFound`, not `findmethod`'s error road -- the
   lookup that failed was a `lang-meth-call` on a value, so `FindMethodSite` is not the reporter;
2. the wrong value came out of `$_.ast`, a **bare accessor** (`$!made`) -- there is no computation
   inside it for a fold to get wrong, so whatever was wrong was wrong *before* the accessor ran;
3. the inputs were identical across the FAIL and the PASS (same tree, same jars, nothing rebuilt),
   and the persisted slots are **read-only** without `NQP_DISPATCH_RECORD`, so no slot was rewritten
   between the two runs.

Ranked candidates: (a) a **misbound persisted `lang-meth-call` slot** at `$_.ast` (the M7 Phase C
hazard, the shape that fits facts 1-3 best); (b) **a fold picking a wrong branch** -- a site whose
guard passed on a fact that had moved; (c) **a half-written site read during partial evaluation**,
which the fix wave's `st`-last publication narrows (it orders the stores, it is not a fence); (d)
**guest-thread sharing** of one site.

Settle plan, now that the batch has a kill-switch: loop `t/nqp/023-named-args.t` 50x on the built
tree; run the 2x2 of `NQP_DISPATCH_PERSIST` on/off x `NQP_SITES_OFF` unset/`all`; and take a suite
run under `NQP_DISPATCH_PERSIST=verify`. Cost if wrong: an intermittent mis-execution in the
compiler, which would resurface on the next whole-suite run.

Rig row b1: `| b1 | e3a9f48ab6 | 24bfcccac | 2.249 | 1.186 | 4933 | 37077 | 50/sanity | none | |`.
Against b0 (2.460 / 1.334 / misses 4933 / hits 37077 / 64 s): rakudo-e **-8.6 %**, nqp-e
**-11.1 %**, warm sanity **-22 %**, with `misses` and `hits` bit-identical to b0 (4933 / 37077).
**Outside the spread on both cold clocks, on the fast side**: the five walls behind b1 were
rakudo-e 2.40 2.32 2.46 2.25 2.38 against b0's 2.53 2.57 2.46 2.49 2.56 (b1's *worst* equals b0's
best), and nqp-e 1.19 1.29 1.26 1.29 1.30 against b0's 1.33 1.34 1.36 1.60 1.52 (no overlap at
all). b1 lands back on the M7 close (2.247 / 1.198, so +0.1 % / -1.0 %) and just under row a /
`m8a` (2.290 / 1.190, -1.8 % / -0.3 %).

That does **not** close B0's open item, and should not be read as "batch 1 bought 8.6 %". Two
readings fit equally: the machine-state reading (b0 was measured on a loaded box, b1 on a quiet one
-- the b0 bisect's own numbers drifted with time, not with commit order) and the promotion reading
(batch 1 removed 35.6 k classlib calls from a cold rakudo start). The census below can separate
them for *traffic* but not for *time*; the only clean discriminator left is a same-session
reference row on the B-pre jars, which remains the controller's call.

Per op, B0 -> B1 (rakudo-e / nqp-e / sanity census; CORE.c: b0 bound only, no CORE.c compile was
run in this task). B0 counts are the uncut re-takes (`b0-*-census2.*`); B1 counts are
`m7-rig/b1-rakudo-e-census.err`, `m7-rig/b1-nqp-e-census.err`, `m7-rig/b1-sanity-census.log`.

| op | road before | B0 count | B1 site calls | misses | pins | slow paths | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- |
| iscont | classlib `Ops.iscont` | 402 / 0 / 46,713 | `IsContSite` 402 / 0 / 46,645 | 12 / 0 / 363 | 3 / 0 / 84 | `[pinned=365 generic=9]` / `[]` / `[pinned=43636 generic=283]` | **promoted**; `Ops.iscont` is 0 on all three roads. The fold fires on ~6 % of calls (rakudo-e 37/402, sanity ~3,000/46,645), the rest take the inlined runtime road: `pinned=` 365 / 0 / 43,636. Two-entry polymorphism is the B2 candidate |
| istrue (+isfalse, +Truthy obj) | classlib `Ops.istrue` / `Ops.isfalse`; `Truthy` unsited (on neither road) | 2,628 / 147 / 328,821 (+isfalse 1 / 0 / 228) | `IsTrueSite` 19,329 / 6,722 / 2,400,527 | 68 / 24 / 4,959 | 8 / 4 / 803 | `[pinned=2820 method=77 generic=60 mode6=4]` / `[pinned=2276 generic=20 method=7]` / `[pinned=226203 method=24184 mode6=19485 generic=4156]` | **promoted**; `method=` is the mode-0 share: 77 / 7 / 24,184, and `pinned=` 2,820 / 2,276 / 226,203 next to it. Site calls far exceed the B0 classlib count because the `Truthy` object arm was counted on neither road before |
| findmethod / tryfindmethod / can | classlib `Ops.findmethod`, `Ops.can`; table `tryfindmethod` | 42+2,613+29 = 2,684 / 19+87+30 = 136 / 7,212+367,103+30,686 = 405,001 | `FindMethodSite` 2,701 / 136 / 405,344 | 26 / 23 / 1,815 | 3 / 3 / 332 | `[nonauth=878 pinned=29 generic=23]` / `[pinned=32 generic=20]` / `[nonauth=102175 pinned=88602 generic=1536]` | **promoted**; `nonauth=` decides the multi-state question (below), and `pinned=` is 29 / 32 / 88,602 next to it. The three B0 counts sum to within 0.6 % of the site's calls on every workload, so nothing leaked |
| decont / isconcrete / create (by name) | classlib | `Ops.decont` 25,717 / 4,991 / 6,577,103; `Ops.isconcrete` 5,263 / 1,170 / 1,124,305; `Ops.create` 640 / 143 / 211,227 | `DecontSite` 37,584 -> 89,750, 10,107 -> 22,524, 6,892,935 -> 17,202,035; `IsConcreteSite` 175 -> 5,719, 30 -> 1,127, 97,685 -> 1,229,682; `CreateSite` 4,252 -> 4,904, 1,989 -> 2,133, 531,440 -> 743,174 | 8 / 0 / 2,322 (Decont); 0 / 0 / 0 (IsConcrete); 15 / 5 / 786 (Create) | 1 / 0 / 434; 0; 2 / 1 / 157 | `[]` on all three | **reachable**; all three names are 0 on the classlib road now. `Ops.isconcrete_nd` (567) and `Ops.createsc` (22) are unchanged between b0 and b1 -- different ops, not batch 1's |

**What `pinned=` is, and what the `pins=` column counted.** `pinned=` is a *slow-path* key, not
the `pins=` column: it counts the CALLS a site takes on the runtime road after it has given up, and
for these three sites that give-up is **miss-pinned** -- the site saw more receiver types than
`MAX_MISSES` = 4 tolerates. Per workload (rakudo-e / nqp-e / sanity): iscont **365 / 0 / 43,636**,
istrue **2,820 / 2,276 / 226,203**, findmethod **29 / 32 / 88,602**. Whether a second entry per site
(or a polymorphic guard) would recover any of them is **OPEN**: batch 1 measured the traffic, it did
not answer the question, and none of the verdicts above should be read as answering it.

The `pins=` column in the table counted **polymorphic pins only** -- a site that pinned at resolve
time (an unfoldable fact: no method cache, boolification mode 0, an uninitialised STable) never
reached the counter. The final-review wave (nqp **76d88cf32**) moves the bump into `Site.pin()`
itself, so **b2's rows count every pin**: the same `rakudo-e` workload re-run after the wave reads
`IsTrueSite pins=25` where b1's row says 8 and `FindMethodSite pins=11` where it says 3, on
identical `calls=` and `misses=`. The same wave splits findmethod's `nonauth=` key into `nocache=`
(the state has no method cache) and `advisory=` (a miss under a non-authoritative one); on rakudo-e
all 878 are `advisory=`, so b1's `nonauth=878` reads as `advisory=878` from b2 on.

Road totals, B0 -> B1:

| workload | table | classlib | siteCalls | siteMisses |
| --- | --- | --- | --- | --- |
| rakudo-e | 33,283 -> 33,340 (+0.2 %, noise; `tryfindmethod`'s 29 left) | 159,612 -> **124,036 (-22.3 %, -35,576)** | 49,032 -> 129,910 | 619 -> 744 |
| nqp-e | 22,200 -> 22,156 | 26,655 -> **19,870 (-25.5 %, -6,785)** | 12,703 -> 33,204 | 66 -> 117 |
| sanity | 3,256,099 -> 3,231,214 | 22,490,277 -> **13,880,310 (-38.3 %, -8,609,967)** | 9,553,355 -> 24,073,100 | 25,585 -> 34,760 |
| CORE.c | *b0 bound only* | *b0 bound only* | *b0 bound only* | *b0 bound only* |

On each workload the classlib drop matches the sum of the eight moved ops to within run-to-run
variance (rakudo-e: 37,306 accounted against 35,576 measured; nqp-e 6,557 against 6,785; sanity
8,662,712 against 8,609,967). `siteCalls` rises by much more than the classlib road loses -- that
is `DecontSite`'s by-design double-count of inner sites plus the `Truthy` and ITER traffic that
used to be on neither road, not new work.

### JFR `--ops`: "entry from interpreter", b0 next to b1

Both cold rows sample in the low hundreds (Ruling 11: the 1 % line is under the sampling noise
there), so these tables are read for *shape*, not for deltas. Every container's entry table is
shorter than 12 rows; these are complete, not truncated.

**rakudo-e** (`m7-rig/b0-rakudo-e-jfr.txt` 144 samples -> `m7-rig/b1-rakudo-e-jfr.txt` 115 samples;
the run is 8.6 % shorter, so the sample count falls with it).

| container | b0 | b1 |
| --- | --- | --- |
| table | 6 = 4.2 % (`RunOp.doOp` 100 %) | 2 = 1.7 % (`RunOp.doOp` 100 %) |
| **classlib** | 41 = **28.5 %** (`ClassLibOp.doCall` 100 %) | 39 = **33.9 %** (`ClassLibOp.doCall` 100 %) |
| sites | 2 = 1.4 % (`CreateOp.doCreate` 1, `P6SinkOp.doSink` 1) | 5 = 4.3 % (**`Truthy.doTruthy` 3 = 60 %**, `IsTrueOp.doIsTrue` 1, `DecontOp.doDecont` 1) |
| dispatch | 34 = 23.6 % (`DispatchOp.doDispatch` 31, `NqpLanguage.lambda$parse$0` 1) | 21 = 18.3 % (`DispatchOp.doDispatch` 100 %) |
| interpreter self | 33 = 22.9 % | 33 = 28.7 % |
| outside all | 28 = 19.4 % | 15 = 13.0 % |

**nqp-e** (`m7-rig/b0-nqp-e-jfr.txt` 68 samples -> `m7-rig/b1-nqp-e-jfr.txt` 48 samples).

| container | b0 | b1 |
| --- | --- | --- |
| table | 4 = 5.9 % (`RunOp.doOp` 100 %) | 3 = 6.3 % (`RunOp.doOp` 100 %) |
| **classlib** | 11 = **16.2 %** (`ClassLibOp.doCall` 100 %) | 8 = **16.7 %** (`ClassLibOp.doCall` 100 %) |
| sites | 0 = 0.0 % | 0 = 0.0 % |
| dispatch | 20 = 29.4 % (`DispatchOp.doDispatch` 19, `GetAttrOp.doGet` 1) | 17 = 35.4 % (`DispatchOp.doDispatch` 100 %) |
| interpreter self | 17 = 25.0 % | 10 = 20.8 % |
| outside all | 16 = 23.5 % | 10 = 20.8 % |

**The classlib share before and after: it did not fall.** 28.5 % -> 33.9 % on rakudo-e, 16.2 % ->
16.7 % on nqp-e, on 41 -> 39 and 11 -> 8 absolute samples. A road whose *call count* dropped 22-26 %
holds the same share of a shorter run, which says the calls batch 1 removed were among the road's
cheapest -- consistent with B0's own reading that the classlib road's cost is dominated by
`classlibInline` on the whole road, not by the eight names moved here. On these sample counts a
5-point move is within noise either way; **CORE.c, at 12,956 samples, is the only workload where
the classlib share can actually be measured, and it was not re-run in this task.** That is the
honest limit on what batch 1's JFR shows.

Rulings made during batch 1:
1. The child-process helper is copied from `20-op-census.t`; there is no shared-library convention
   for it in the test tree.
2. The in-process fold/refold tests pass before each site exists; the RED half of the TDD cycle is
   the routing and counter asserts, not the folding itself.
3. The user's part-1 execution choice was carried into part 2 unchanged.
4. Refold tests use a second 200-iteration loop after the writer op.
5. The DSL refuses a null constant operand, so native conditions carry the `NqpTypeOps.NO_SITE`
   sentinel instead.
6. `MODE_ITER` is folded -- it was the largest single slow path on cold start (5,284 of 19,329
   IsTrueSite calls before the fold; `mode7` does not appear in b1's slow list at all).
7. A method-cache **hit** folds under any authority; a **miss** folds only under an authoritative
   cache.
8. `20-op-census.t`'s example ops were repointed to `sha1` / `reprname`.
9. `NqpOps.str` is private, so `findmethodSlow` writes the str coercion out itself (the final-review
   wave turned the null case into a named `IllegalArgumentException`: all three `Ops` entries take a
   non-null `String`).
10. **Boolification mode 6 (BIGINT) is left generic**: `mode6=19,485` on sanity (4 on rakudo-e) is
    the largest unfolded istrue road after `method=`, and its read goes through the bigint cache
    behind a boundary. A **named B2 candidate**, not an oversight.
11. `Ops.isconcrete_nd` (**567** on rakudo-e, unchanged b0 -> b1) is a *different op* from
    `Ops.isconcrete` and was not in batch 1's scope. A **named B2 candidate**.
12. `m7-rig/b1-sanity-census.log` carries the site block **three times** -- three identical copies
    under a *single* `op census:` header, so they are repeats of one process's counters, not three
    runs to be summed. The totals in this section are read from that header line and the per-site
    rows from one block; why the block repeats is unexplained and left for B2's tooling pass.

The multi-state findmethod question: nonauth=**878** on rakudo-e (32.5 % of that site's 2,701
calls), **102,175** on sanity (25.2 % of 405,344), **0** on nqp-e, with pinned=**29** / **32** /
**88,602** beside it -> **NOT designed.** The two keys are different questions: `nonauth` is a fact
the rule forbids folding, `pinned` is miss-pinning, i.e. **polymorphism**, and that one is left
**OPEN** here -- 88,602 pinned calls on sanity say a second entry is worth *measuring* in B2, not
that batch 1 ruled on it. The 878 cold
calls come from about five *monomorphic* sites probing names that are absent from ADVISORY caches
(`WRAPPERS` x3, `CALL-ME` x2, `REQUIRED-REVISION`, `default`, `body`), not from polymorphism, so a
multi-state guard -- which only helps a site that sees several receiver types -- would not remove
one of them. The only lever that would is a memo of the HOW walk's answer, and Ruling 7's fold rule
forbids exactly that (a miss under a non-authoritative cache must stay unmemoised, or a later
`add_method` goes unseen). Recorded, not designed: the census batch (B2) decides whether these
probe sites are hot enough to deserve a different remedy.

Artifacts (untracked): `m7-rig/b1.md`, `m7-rig/b1-{rakudo-e,nqp-e}-{run1..5,census,jfr}.err`,
`m7-rig/b1-{rakudo-e,nqp-e}.jfr`, `m7-rig/b1-{rakudo-e,nqp-e}-jfr.txt`, `m7-rig/b1-sanity.log`,
`m7-rig/b1-sanity-census.log`, and the row appended to `m7-rig/rows.md`; logs
`nqp-suite-b1.log` (the FAIL), `nqp-suite-b1-rerun.log` (the PASS), `sanity-b1.log`, `rig-b1.log`
under `/home/longwalker/.claude/jobs/455b5a91/tmp/`.

### B1: the same-session A/B (controller, 2026-09-17, after the fix wave; nqp 76d88cf32 / rakudo f6d8941310)

The kill-switch (`NQP_SITES_OFF=iscont,istrue,findmethod,reach`) makes the batch's effect a
same-session measurement on the same jars and the same training, which the b0 -> b1 delta was not
(b0 was taken on a loaded machine; see "the open item" above).

Cold rows, best of 5, off / on / off / on: rakudo-e 2.303 / 2.274 / 2.388 / 2.368 s;
nqp-e 1.232 / 1.255 / 1.168 / 1.506 (the last under a load spike). Reading: batch 1 buys about
0.02-0.03 s on cold rakudo-e (1-2 %), inside the run-to-run noise; nqp-e is inconclusive. The
b0 -> b1 -8.6 % was machine state, not the promotion. This matches the MoarVM analysis: cold start is
per-call cost in the interpreter, and removing 22-38 % of the classlib calls moves it little.

Warm proxy (t/01-sanity on one server), off / on / off / on: 48 / 46 / 59 / 49 s. Reading: the
sites are worth 5-10 % of the warm proxy; the b0 -> b1 -22 % (64 -> 50 s) was inflated the same way.

Integration gate on the final tree (after the fix wave): runtime JUnit up to date (69), nqp suite
Result: PASS, Files=154, Tests=13247, prove 491 s / gradle 904 s including the four warm sweeps'
wait; the one-off `023-named-args.t` red did not recur (its settle plan stands, above).

Consequence for B2: the census ranks candidates by calls, and calls are not seconds; B2's selection
reads the JFR --ops exclusive shares (the CORE.c compile is where the classlib share is measurable)
and takes its rows the same-session way, off/on under the kill-switch.

## B2, the opening: the retake (Task 2 of the batch 2 part 1 plan)

Tree: rakudo `11cdd3856f` / nqp `76d88cf32` (batch 1's engine, Task 1's readers).
Jars rebuilt (6 s, `BUILD SUCCESSFUL`, 12 tasks up to date), retrained
(`dispatch-record: done 21 paths, 4191 slots, 4490 programs, 14 unpersistable, 0 failed`, 2 s).

Rig row b1r (rig wall 125 s, all markers present, `m7-rig: DONE tag=b1r`), a reference for today's
machine, NOT a series row -- no stop rule is read from it:

`| b1r | 11cdd3856f | 76d88cf32 | 2.274 | 1.207 | 4933 | 35843 | 44/sanity | none | |`

The five walls behind it: rakudo-e 2.31 2.27 2.34 2.30 2.39, nqp-e 1.30 1.26 1.27 1.21 1.30.
`hits=35843` (b1's 37077 on the same jars-and-training shape; the A/B already recorded `hits` as
run-to-run, not a build invariant), `misses=4933` unchanged, warm `t/01-sanity` 25 files in 44 s on
one server, `red=0 new-red=-`.

### The census, per workload (b1 -> b1r)

| workload | table | classlib | siteCalls | siteMisses | top classlib (8), b1r |
| --- | --- | --- | --- | --- | --- |
| rakudo-e | 33,340 -> 33,254 | 124,036 -> 122,661 | 129,910 -> 128,512 | 744 -> 741 | Ops.setcodeobj 27116, Ops.atkey 15482, Ops.atpos 10434, Ops.isnull 10041, Ops.concat 8247, Ops.how 8210, Ops.shift 4189, Ops.elems 3137 |
| nqp-e | 22,156 -> 22,170 | 19,870 -> 20,146 | 33,204 -> 33,453 | 117 -> 117 | Ops.concat 3400, Ops.shift 2260, Ops.setcodeobj 1484, Ops.push 944, Ops.isnull 875, Ops.iter 858, Ops.atpos 830, Ops.atkey 750 |
| sanity | 3,231,214 -> 3,225,690 | 13,880,310 -> 13,853,545 | 24,073,100 -> 24,044,622 | 34,760 -> 34,685 | Ops.atkey 1903452, Ops.atpos 1623066, Ops.isnull 1299484, Ops.how 988641, Ops.setcodeobj 683021, Ops.elems 557656, Ops.shift 481389, Ops.eqaddr 421293 |
| CORE.c | *b0 bound* 257,104,670 -> **254,048,524** | *b0 bound* 1,084,094,672 -> **478,104,209 (-55.9 %)** | *b0 bound* 692,228,289 -> **1,610,755,139** | *b0 bound* 3,965 -> 7,745 | Ops.atpos 40878010, Ops.getattr_i 37062384, Ops.bindattr_i 35763164, Ops.atkey 32043232, Ops.isnull 31766260, Ops.who 26441996, Ops.elems 25534673, Ops.shift 25260732 |

Sources: `m7-rig/b1r-rakudo-e-census.err`, `m7-rig/b1r-nqp-e-census.err`,
`m7-rig/b1r-sanity-census.log`, `m7-rig/b1r-corec-census.err` (303 lines, header first), each read
with `raku tools/build/m7-rig.raku --parse-census=<file>`; the b1 column is the "Road totals,
B0 -> B1" table above. The three cheap workloads are flat b1 -> b1r (every total within 1.4 %, i.e.
cold-start run-to-run variance), which is the point of the retake: **the tree did not move, so the
CORE.c column is now measured rather than bounded.**

On CORE.c the eight names batch 1 moved are **0 on the classlib road** (`Ops.decont`,
`Ops.isconcrete`, `Ops.create`, `Ops.istrue`, `Ops.isfalse`, `Ops.iscont`, `Ops.findmethod`,
`Ops.can` all absent); what remains under those stems is `Ops.isconcrete_nd` 703,317,
`Ops.decont_s` 22,883, the sized `iscont` arms (2,493 / 2,070 / 2,013 / 1,836) and `Ops.createsc`
19 -- different ops, as B1's rulings 11 and 4 already recorded. The -606.0 M classlib calls
(1,084,094,672 -> 478,104,209) are accounted for by the five of the eight that clear the 30-row cut
in b0's census file (`m7-rig/b0-corec-census.err`, 69 lines): `Ops.decont` 499,704,638,
`Ops.isconcrete` 73,421,782, `Ops.create` 17,572,121, `Ops.istrue` 9,350,543, `Ops.can` 5,066,814
= **605.1 M**. The remaining 0.9 M is **inference, not measurement**: `iscont`, `findmethod` and
`isfalse` sit below that cut at b0 (bounded there at <= 4,700,751 each -- the last visible classlib
row, `Ops.bindkey`), and cold/compile run-to-run variance is inside the same residual. The moved
calls reappear on the site road: `DecontSite calls=1,213,793,356 misses=1`, `IsTypeSite 126,941,693 / 3,134`,
`IsTrueSite 119,963,760 / 3,157 slow=[pinned=32080302 method=4921532 mode6=210367 generic=4662]`,
`IsConcreteSite 92,302,881 / 0`, `CreateSite 46,359,109 / 171`, `FindMethodSite 8,915,793 / 415
slow=[pinned=4404075 advisory=428529 nocache=89795 generic=404]`, `IsContSite 79,959 / 45`.
(`siteCalls` more than doubles because `DecontSite` double-counts inner sites by design.)

CORE.c clocks, three standalone compiles on `/usr/bin/perl rakudo-j-build` (Ruling 7), output to the
job dir so the build's jar was untouched:

| run | wall | parse | optimize | qast | unit |
| --- | --- | --- | --- | --- | --- |
| `NQP_OP_CENSUS=1` | **294 s** | 226.58 | 24.70 | 18.86 | 23.24 |
| JFR `settings=profile`, knob off | **286 s** | 221.95 | 23.05 | 17.81 | 21.70 |
| JFR + `NQP_CLASSLIB_INLINE=1` (the spike) | **272 s** | 208.68 | 22.56 | 18.09 | 20.97 |

Against B0's same two points (356 s census, 319 s JFR): -17.4 % and -10.3 %. The census knob costs
**8 s here** (294 - 286, +2.8 %) against **37 s at B0** (356 - 319); B0's section also quotes 28 s
for the same knob on the parse stage alone (281.26 vs 252.80, the same pair of runs), and the b1r
parse-stage figure is 4.6 s (226.58 vs 221.95). The fall in that overhead is **not attributed
here**, and in particular not to "fewer counters": the census's total counter work went *up* between the two
trees, not down. `table + classlib + siteCalls` is **2,033,427,631 at b0 against 2,342,907,872 at
b1r (+309 M)** -- the classlib road loses 0.606 G bumps while the site road gains 0.918 G -- so any
explanation would have to argue that a site bump is cheaper than a classlib bump, and nothing
measured here says that. None of these three walls is a knob-off,
unprofiled CORE.c point, and B0's open item (that session's machine state) covers part of the
-17 %; they are recorded as measurement points, not as a compile-time result.

### JFR `--ops`, CORE.c: b0 -> b1r -> spike

`m7-rig/b0-corec-jfr.txt` (12,956 samples) -> `m7-rig/b1r-corec-jfr.txt` (14,181: main 14,071,
TruffleCompilerThread-53 105) -> `m7-rig/b1r-corec-inline-jfr.txt` (13,527: main 13,415,
TruffleCompilerThread-53 100). Shares are of all samples.

| container | b0 | b1r | spike (NQP_CLASSLIB_INLINE=1) |
| --- | --- | --- | --- |
| table | 15.4 % (1991) | 15.6 % (2208) | 16.3 % (2199) |
| classlib | 26.7 % (3459; leaf `classlibInline` 68.7 % = 18.3 % global) | **17.0 %** (2404; leaf `classlibInline` 61.0 % = **10.3 % global**) | **13.8 %** (1861; leaf `classlibInline` 52.7 % = **7.3 % global**) |
| sites | 2.3 % (297) | 2.4 % (344) | 2.6 % (346) |
| dispatch | 15.3 % (1988) | 16.7 % (2371) | 17.0 % (2304) |
| interpreter self | 8.4 % (1082) | 10.5 % (1488) | 12.6 % (1700) |
| outside all | 31.9 % (4139) | 37.8 % (5366) | 37.8 % (5117) |

The sites container's entry table is no longer dominated by two names: b1r reads
`IsTypeOp.doIsType` 137 = 39.8 % of the container (0.97 % global), `Truthy.doTruthy` 86 = 25.0 %
(0.61 %), `CreateOp.doCreate` 35, `DecontOp.doDecont` 30, `FindMethodOp.doFind` 28,
`IsTrueOp.doIsTrue` 15, `IsConcreteOp` 5. **The container is 2.4 % of the compile, of which
batch 1's four new classes are 134 samples = 0.94 % of the compile** (`Truthy` 86 + `FindMethodOp`
28 + `IsTrueOp` 15 + `IsConcreteOp` 5, i.e. 39 % of the container); `IsTypeOp` and `DecontOp` were
already entries at b0 (149 and 121 samples) and `CreateOp` too (16), so the other 1.5 points are
not batch 1's, and `IsContOp` appears nowhere. Outside all four containers the bucket's
*composition* is unchanged -- `sun.misc.Unsafe.putObject` 43.0 % of it at b0, 50.3 % at b1r, the
unit stage's serialization writes -- but its *share* rises **31.9 % -> 37.8 %** and that leaf goes
**13.7 % -> 19.0 % global**, roughly 44 s -> 55 s of the two walls, on an output jar of the same
size to within 4 bytes (56,082,69x both times). **Unexplained** -- cross-session machine state and
the sample budget are the obvious candidates -- and recorded so the next batch looks rather than
skips it.

Reading: on CORE.c batch 1 is **measurable in seconds, not only in calls** -- the classlib road
falls 26.7 % -> 17.0 % of samples (its `classlibInline` leaf 18.3 % -> 10.3 % global) while the
sited road it fed rises only 2.3 % -> 2.4 %, so the eight promoted names were *not* among the road's
cheapest here, unlike on the two cold rows. What the classlib road still holds at 17.0 % is 478 M
calls of generic ops with no site of their own (`atpos`, `getattr_i`, `bindattr_i`, `atkey`,
`isnull`, `who`, `elems`, `shift` are the head), which is exactly what batch 2's trim is aimed at.
The spike says PE visibility is worth part of the rest: making the op bodies visible to partial
evaluation (boundary removed) takes the container 17.0 % -> 13.8 % and its leaf 10.3 % -> 7.3 %
global, on a wall 14 s (-4.9 %) shorter -- **one sample, no repeat** -- and the same 3.2 points
reappear in `interpreter self` (+2.1) and `table` (+0.7), so part of it is re-attribution rather
than saving. **The ceiling on the trim, stated tightly: the classlib road is ~17 % of a CORE.c
compile, and PE visibility moved a fifth of it** -- 3.2 of 17.0 points = 19 %. (The leaf fraction
alone moved 10.3 -> 7.3 = 29 %, a shade under a third; that is the generous reading of the same
run, and it is a leaf share, not the road.) With the re-attribution above, the figure a later batch
should plan against is **below a fifth of the road**, not a third of it. The share comparison spans
two sessions and is the robust half of this section; the wall comparison carries B0's open
machine-state item.

Rulings: (1) Ruling 3 of the plan (a census reader takes the largest block) applied to every file
read here; `m7-rig/b1r-corec-census.err` is 303 lines and begins with `op census:`. (2) **The
brief's Steps 3-5 spelled `./rakudo-j`; all three compiles were run on `/usr/bin/perl
rakudo-j-build`**, applying B0's Ruling 7 unchanged (the stock 4 GB runner carries none of
milestone 6's tier policy, and a CORE.c wall taken on it is comparable to nothing else in this
project). Every other token of the three command lines is the brief's, verbatim. (3) The spike's
-14 s wall and the +2.1 points of `interpreter self` under it are recorded, not explained: a
boundary removal changes where a sample is attributed as well as how long the work takes.

### The settle plan for `t/nqp/023-named-args.t` (Task 3)

The settle plan B1 left open, run on rakudo `74cdc5f495` / nqp `76d88cf32` -- batch 1's engine and
Task 2's jars, nothing rebuilt, retrained or edited for this. Each cell is the same driver
(`prove -q --exec ./nqp-j-gradle t/nqp/023-named-args.t`, `:cwd("nqp")`), with the cell's knob in
front of it and every other knob unset.

| cell | runs | passed | wall |
| --- | --- | --- | --- |
| persist on, sites on | 50 | 50 | 105 s |
| persist off, sites on (`NQP_DISPATCH_PERSIST=off`) | 10 | 10 | 19.0 s |
| persist on, sites off (`NQP_SITES_OFF=all`) | 10 | 10 | 19.9 s |
| persist off, sites off | 10 | 10 | 19.4 s |

The 2x2 is a real 2x2: both knobs are read by name from the process environment
(`NqpProgramBuilder.java:59` `System.getenv("NQP_SITES_OFF")`, `DispatchPersist.kt:34`
`System.getenv("NQP_DISPATCH_PERSIST")`, whose `off` arm ignores persisted slots), so the four
cells are four configurations and not four spellings of one.

nqp suite under `NQP_DISPATCH_PERSIST=verify`: **Result: FAIL**, Files=154 Tests=13247, prove
**528 s** / gradle **530 s** (`BUILD FAILED in 8m 50s`), `mismatched=0` on **every one of the 155
verify lines** the run printed (310 occurrences in the log, counting watched-run's echo; the only
distinct value of `mismatched=` in the whole file is `0`, over 256,728 matched programs).
`t/nqp/023-named-args.t .................. ok` in that same run.

**The FAIL is the knob's own banner, not a red.** The single failing test is
`t/nqp/114-pod-panic.t` (`Wstat: 0 Tests: 1 Failed: 1`), which spawns a child `nqp` and matches its
**stderr** against a `^`-anchored `'===SORRY!=== Error while compiling pod-test.nqp'`. The child
inherits `NQP_DISPATCH_PERSIST=verify` and prints `dispatch-verify: on` to stderr before compiling,
so the anchor cannot match. Confirmed directly and deterministically: `./nqp-j-gradle
t/nqp/114-pod-panic.t` is `ok 1` (2.8 s) and the same command under
`NQP_DISPATCH_PERSIST=verify` is `not ok 1` (3.1 s), and `-e` with the streams separated shows both
`dispatch-verify:` lines going to stderr. So the verify suite is green on everything verify is for
-- it is a property of running a whole suite under a stderr-printing knob, and a note for whoever
takes the next verify suite: that one file will fail under it until the banner moves or the test
filters it.

Verdict: **not reproduced in 80 file runs and one verify suite; the red stays an open item with no
attribution, and B2's suite runs are its next chance.** What the four cells add to B1's ranked
candidates is only negative: 80 runs of the file, including 20 with batch 1's sites off entirely
and 20 with persisted slots ignored, produce no failure, so no cell is implicated and none is
cleared either -- the plan's power against a once-in-hundreds intermittent was never large. The
one thing the verify suite does narrow is candidate (a), the misbound persisted `lang-meth-call`
slot: 256,728 restored programs were re-derived and compared with `mismatched=0`, which is evidence
against a *systematic* misbind on this tree, though not against a racing or one-shot one.
