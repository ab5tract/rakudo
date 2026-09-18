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
(rakudo-e) and 1.31 1.34 1.31 1.35 1.26 (nqp-e), warm proxy `t/01-sanity` 25/25
red=0. The rig prints the rakudo SHA it sees, `beef32d2a3` (HEAD: this plan and
the spec, docs only); the code tree is 2338bc426c's.

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
