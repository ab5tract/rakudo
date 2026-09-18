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
inside c0's 42 s and, per the C0 note, takes no credit.

### The two builds

| step | wall | result |
|---|---|---|
| window: `./nqp/gradlew -p nqp clean` | 1 s | ok |
| window: `./nqp/gradlew -p nqp buildJvm` (version-11 stage0, dual reader) | 186 s | BUILD SUCCESSFUL |
| window: `make clean` + `make` | 803 s | EXIT=0, `dispatch-record: done ... 0 failed` |
| window gate: nqp suite (sweep, 160 files) | 190 s | EXIT=0 verdict=ok |
| window gate: warm `t/01-sanity` (25 files) | 62 s | 0 FAIL |
| window gate: `nqp/t/jvm/23-sc-demand.t` | 3 s | 24/24 PASS |
| regen: `./nqp/gradlew -p nqp jBootstrapFiles` | 1 s | BUILD SUCCESSFUL, nine stage0 jars modified, all `version=12` |
| clean: `perl Configure.pl --backends=jvm --gen-nqp` | 188 s | BUILD SUCCESSFUL (bootstrapped from the version-12 stage0 under the one-format reader) |
| clean: `make` | 800 s | EXIT=0, `dispatch-record: done 21 paths, 4228 slots, 4527 programs, 14 unpersistable, 0 failed` |

**A note on the window build.** The brief expected `gradlew clean` + `make` to
rebuild the nqp bootstrap; it does not. The Makefile's only gradle edge is
`nqp-runtime.jar` -- nothing there rebuilds stage1/stage2 -- so the bare `make`
died in one second on a missing `org.graalvm.truffle` module. The window build
is therefore the two commands above: `gradlew -p nqp buildJvm` (this is the step
that reads the version-11 stage0 through the dual reader) and then, because the
rakudo blib jars still carried the old nqp SC handles ("Missing or wrong version
of dependency .../stage2/NQPHLL.nqp"), `make clean` + `make`.

### Gates on the clean build

| gate | wall | result |
|---|---|---|
| `./nqp/gradlew -p nqp :nqp-runtime:test` | 3 s | BUILD SUCCESSFUL |
| `nqp/t/jvm/23-sc-demand.t` | 3 s | 24/24, Result: PASS |
| nqp suite (sweep, 160 files) | 188 s | EXIT=0 verdict=ok |
| warm `t/01-sanity` (25 files) | 60 s | 0 FAIL |
| the rig | 60 s | `m7-rig: DONE tag=c1` |

### CORE.c

One compile on the idle box (load average 0.95 before it), 226 s wall, against
row b2b's 243-245 s same-session: **-17 to -19 s, -7.0 to -7.8 %**.

| stagestat | b2b (census run) | c1 | delta |
|---|---|---|---|
| parse | 187.7 | 173.7 | -14.0 |
| optimize | 22.2 | 20.4 | -1.8 |
| qast | 15.7 | 15.2 | -0.5 |
| unit | 17.2 | 16.0 | **-1.2** |

`unit` is the stage the writer runs inside: the format-12 writer is 1.2 s (-7 %)
*cheaper* than the format-11 one despite the extra varint encoding, because it
writes 52 % fewer bytes. `parse`'s -14 s is the reading side of the same move
(this stage loads BOOTSTRAP and the settings CORE.c depends on).

The in-build CORE.c of the clean `make` agrees: parse 183.4 / optimize 20.6 /
qast 15.7 / unit 16.0.

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
| `blib/CORE.c.setting.jar` | 56,412,944 | 41,737,626 | -26.0 % |
| `blib/Perl6/BOOTSTRAP/v6c.jar` | -- | 9,121,372 | -- |

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
