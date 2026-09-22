# Task 6 report: End to end by hand, before the builds change

Date: 2026-09-16. ROOT = `/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records`.
Trees: nqp `3d0b54fa4` (Tasks 3-5 committed), rakudo `b114238897`. `java` = Oracle GraalVM 25.2.4 (25.0.4+7-LTS-jvmci-25.2-b20).
No source edited, no build run, no commit. Raw logs: `/home/longwalker/.claude/jobs/ba3ab3a7/tmp/task6/`.

**Status: BLOCKED on the fail-fast rule** — every step ran and every marker appeared, and the headline
predictions (recorded under 500 on the rakudo consumer run) were met, but `mismatched` is NOT zero
(nqp cold 8, rakudo cold 4, warm t/01-sanity 313). Per the task's hard constraints nothing was fixed;
the evidence is below, including the root-cause characterisation (§Findings, item 4).

---

## Step 1: runtime jars

Already rebuilt and synced by Task 5; not rebuilt here. No eval server was running at the start.

## Step 2: train nqp's lib jars

```
cd ROOT/nqp && NQP_DISPATCH_RECORD=all NQP_DISPATCH_STATS=1 ./nqp-j-gradle -e '' </dev/null > step2-nqp-train.log 2>&1
```
Wall: **1.292 s** (9.28 s user, 760 % cpu).

```
dispatch stats: hits=23752 misses=1771 sites=2851 anon=3 sitesAll=2867 restored=0 restoredSites=0 dropped=0 recorded=1766 slowEvals=17 invokes=4919 directs=4910 noTarget=9 badExpectation=0 notCodeRef=0 slowLayout=0 slowNull=17 byKind[value,syscall,mapped,invoke,resumable]=[0, 14902, 3940, 4910, 0]
  noTarget 5 name KnowHOWMethods
  noTarget 2 new_type KnowHOWMethods
  noTarget 2 compose KnowHOWMethods
  misses 1279 lang-meth-call
  misses 440 lang-call
  misses 52 boot-syscall
```

`dispatch-record:` lines (9 jars, 1681 slots / 1709 programs / 41 unpersistable):

```
dispatch-record: wrote 18 slots (18 programs, 0 unpersistable) to .../nqp/build/jvm/share/lib/NQPP6QRegex.jar
dispatch-record: wrote 115 slots (123 programs, 1 unpersistable) to .../nqp/build/jvm/share/lib/NQPHLL.jar
dispatch-record: wrote 171 slots (176 programs, 4 unpersistable) to .../nqp/build/jvm/share/lib/nqp.jar
dispatch-record: wrote 11 slots (11 programs, 5 unpersistable) to .../nqp/build/jvm/share/lib/ModuleLoader.jar
dispatch-record: wrote 103 slots (114 programs, 9 unpersistable) to .../nqp/build/jvm/share/lib/NQPCORE.setting.jar
dispatch-record: wrote 34 slots (34 programs, 0 unpersistable) to .../nqp/build/jvm/share/lib/QRegex.jar
dispatch-record: wrote 38 slots (38 programs, 1 unpersistable) to .../nqp/build/jvm/share/lib/QASTNode.jar
dispatch-record: wrote 142 slots (144 programs, 0 unpersistable) to .../nqp/build/jvm/share/lib/nqpmo.jar
dispatch-record: wrote 1049 slots (1051 programs, 21 unpersistable) to .../nqp/build/jvm/share/lib/QAST.jar
```

`recorded=1766` — above the brief's 1300-1500 estimate but the same order.

## Step 3: the nqp consumer

```
cd ROOT/nqp && NQP_DISPATCH_STATS=1 ./nqp-j-gradle -e '' </dev/null > step3-nqp-consumer.log 2>&1
```
Wall: **1.140 s**.

```
dispatch stats: hits=7458 misses=1725 sites=2851 anon=3 sitesAll=2867 restored=1677 restoredSites=1667 dropped=9 recorded=87 slowEvals=55 invokes=4924 directs=4915 noTarget=9 badExpectation=0 notCodeRef=0 slowLayout=0 slowNull=25 byKind[value,syscall,mapped,invoke,resumable]=[0, 864, 1679, 4915, 0]
  noTarget 5 name KnowHOWMethods
  noTarget 2 new_type KnowHOWMethods
  noTarget 2 compose KnowHOWMethods
  misses 1234 lang-meth-call
  misses 440 lang-call
  misses 51 boot-syscall
```

restored=1677, restoredSites=1667, dropped=9, **recorded=87** (target: under 100). Matches the prediction.

## Step 4: nqp verify — **8 mismatches**

```
cd ROOT/nqp && NQP_DISPATCH_STATS=1 NQP_DISPATCH_PERSIST=verify ./nqp-j-gradle -e '' </dev/null > step4-nqp-verify.log 2>&1
```
Wall: **1.348 s**.

```
dispatch-verify: on
dispatch-verify: matched=1679 mismatched=8 unseen=41
dispatch stats: hits=23752 misses=1771 sites=2851 anon=3 sitesAll=2867 restored=1678 restoredSites=1668 dropped=9 recorded=1766 slowEvals=17 invokes=4919 directs=4910 noTarget=9 badExpectation=0 notCodeRef=0 slowLayout=0 slowNull=17 byKind[value,syscall,mapped,invoke,resumable]=[0, 14902, 3940, 4910, 0]
```

All 8 MISMATCH blocks name **one** identity:
`.../nqp/build/jvm/share/lib/NQPCORE.setting.jar!C2FAD65C9748828B2511CD02A71D59CD9621494F#118#0 lang-meth-call`.
First block verbatim (long guard chains elided in the middle with `…` only where marked):

```
dispatch-verify: MISMATCH .../NQPCORE.setting.jar!C2FAD65C9748828B2511CD02A71D59CD9621494F#118#0 lang-meth-call
  persisted: csd[0,4,0,0] guards=[hll(arg(0),nqp);type(how(arg(0)),st:0A48A58B890F629CB594F9CC43A1B4DE104E58C4-0:9);conc(how(arg(0)),true);type(attr(how(arg(0)),obj:0A48A58B…,$!cached_all_method_table,OBJ),st:__6MODEL_CORE__:4);…;type(attr(lookup(attr(how(arg(0)),…),arg(1)),obj:F4747482…-0:16,$!do,OBJ),st:__6MODEL_CORE__:9);conc(…,true)] outcome=invoke(attr(lookup(attr(how(arg(0)),…),arg(1)),obj:F4747482…-0:16,$!do,OBJ),shape(arg(2),arg(3);csd[0,0]))
  recorded:  csd[0,4,0,0] guards=[type(arg(0),st:77E5C598B379703C6F8BD42379F3E73FBCAB095F-0:10);hll(arg(0),nqp);type(lookup(lit(NP(obj:VMHashInstance:?:nosc)),arg(1)),st:F4747482…-0:16);…] outcome=invoke(attr(lookup(lit(NP(obj:VMHashInstance:?:nosc)),arg(1)),obj:F4747482…-0:16,$!do,OBJ),shape(arg(2),arg(3);csd[0,0]))
```

The other seven differ from this one only in the `type(arg(0),st:…)` STable named on the `recorded:` side
(`77E5C598…-0:10`, `5CD4D746…-0:9`, `77E5C598…-0:3`, `5CD4D746…-0:12`, …) — i.e. eight different receivers
at the same callsite, each recording its own program, all compared against the single persisted program.
The persisted side is byte-identical in all eight blocks.

Per the task constraints this was captured, not fixed (the brief's own instruction to fix and re-run was
superseded by "do NOT try to fix anything … report BLOCKED with the specifics").

## Step 5: Rakudo

### 5a — training

```
cd ROOT && RAKUDO_RAKUAST=1 NQP_DISPATCH_RECORD=all NQP_DISPATCH_STATS=1 ./rakudo-j -e '' </dev/null > step5a-rakudo-train.log 2>&1
```
Wall: **2.683 s**.

```
dispatch stats: hits=67283 misses=5032 sites=6522 anon=5 sitesAll=6596 restored=1329 restoredSites=1326 dropped=30 recorded=3394 slowEvals=83 invokes=7201 directs=7199 noTarget=2 badExpectation=0 notCodeRef=0 slowLayout=32 slowNull=27 byKind[value,syscall,mapped,invoke,resumable]=[0, 26875, 30844, 7183, 2381]
  noTarget 2 name KnowHOWMethods
  misses 2869 lang-meth-call
  misses 1913 lang-call
  misses 213 boot-syscall
  misses 35 raku-assign
  misses 1 raku-meth-call-qualified
  misses 1 raku-coercion
```

(`restored=1329` because nqp's lib jars were already trained in Step 2; 1329 + 3394 = 4723 = the Task 4
baseline `recorded`.)

21 `dispatch-record:` lines, 4284 slots / 4596 programs / 50 unpersistable:

```
dispatch-record: wrote 1486 slots (1487 programs, 40 unpersistable) to blib/CORE.c.setting.jar
dispatch-record: wrote 1111 slots (1113 programs, 0 unpersistable) to .../nqp/build/jvm/share/lib/QAST.jar
dispatch-record: wrote  841 slots (1105 programs, 3 unpersistable) to blib/Perl6/BOOTSTRAP/v6c.jar
dispatch-record: wrote  110 slots (114 programs, 0 unpersistable) to blib/Raku/Actions.jar
dispatch-record: wrote  101 slots (110 programs, 5 unpersistable) to .../nqp/build/jvm/share/lib/NQPCORE.setting.jar
dispatch-record: wrote   99 slots (108 programs, 1 unpersistable) to .../nqp/build/jvm/share/lib/NQPHLL.jar
dispatch-record: wrote   92 slots (104 programs, 0 unpersistable) to blib/Perl6/Metamodel.jar
dispatch-record: wrote   78 slots (78 programs, 0 unpersistable) to blib/Perl6/Ops.jar
dispatch-record: wrote   59 slots (59 programs, 0 unpersistable) to blib/Raku/Grammar.jar
dispatch-record: wrote   39 slots (40 programs, 0 unpersistable) to .../nqp/build/jvm/share/lib/QRegex.jar
dispatch-record: wrote   38 slots (38 programs, 0 unpersistable) to .../nqp/build/jvm/share/lib/nqpmo.jar
dispatch-record: wrote   35 slots (35 programs, 0 unpersistable) to ./rakudo.jar
dispatch-record: wrote   35 slots (35 programs, 0 unpersistable) to .../nqp/build/jvm/share/lib/QASTNode.jar
dispatch-record: wrote   34 slots (34 programs, 1 unpersistable) to blib/Perl6/ModuleLoader.jar
dispatch-record: wrote   33 slots (33 programs, 0 unpersistable) to blib/Perl6/Compiler.jar
dispatch-record: wrote   22 slots (22 programs, 0 unpersistable) to blib/CORE.d.setting.jar
dispatch-record: wrote   20 slots (20 programs, 0 unpersistable) to blib/Perl6/Optimizer.jar
dispatch-record: wrote   18 slots (18 programs, 0 unpersistable) to .../nqp/build/jvm/share/lib/NQPP6QRegex.jar
dispatch-record: wrote   16 slots (16 programs, 0 unpersistable) to blib/Perl6/SysConfig.jar
dispatch-record: wrote   10 slots (10 programs, 0 unpersistable) to .../nqp/build/jvm/share/lib/ModuleLoader.jar
dispatch-record: wrote    7 slots (7 programs, 0 unpersistable) to blib/Perl6/BOOTSTRAP/v6d.jar
```

Every loaded store-backed artifact is present. `blib/CORE.e.setting.jar`, `blib/Perl6/BOOTSTRAP/v6e.jar`,
`blib/Perl6/Pod.jar` and `nqp/.../nqp.jar` are absent because a `rakudo-j -e ''` never loads them.

### 5b — the consumer (the headline)

```
cd ROOT && RAKUDO_RAKUAST=1 NQP_DISPATCH_STATS=1 ./rakudo-j -e '' </dev/null > step5b-rakudo-consumer.log 2>&1
```
Wall: **1.943 s** (vs 2.483 s for the same work with restore off — see 5c).

```
dispatch stats: hits=13292 misses=4306 sites=6438 anon=5 sitesAll=6511 restored=4477 restoredSites=4195 dropped=37 recorded=193 slowEvals=83 invokes=5985 directs=5983 noTarget=2 badExpectation=0 notCodeRef=0 slowLayout=32 slowNull=27 byKind[value,syscall,mapped,invoke,resumable]=[0, 2179, 3781, 5967, 1365]
  noTarget 2 name KnowHOWMethods
  misses 2163 lang-meth-call
  misses 1911 lang-call
  misses 195 boot-syscall
  misses 35 raku-assign
  misses 1 raku-meth-call-qualified
  misses 1 raku-coercion
```

**`recorded=193`** against the Task 4 baseline of 4723 — a 96 % fall, comfortably under C0's "below 500".
`restored=4477` over 4195 sites, `dropped=37`.

### 5c — verify — **4 mismatches**

```
cd ROOT && RAKUDO_RAKUAST=1 NQP_DISPATCH_STATS=1 NQP_DISPATCH_PERSIST=verify ./rakudo-j -e '' </dev/null > step5c-rakudo-verify.log 2>&1
```
Wall: **2.483 s**.

```
dispatch-verify: on
dispatch-verify: matched=4475 mismatched=4 unseen=127
dispatch stats: hits=80298 misses=5056 sites=6522 anon=5 sitesAll=6596 restored=4476 restoredSites=4223 dropped=80 recorded=4723 slowEvals=52 invokes=7197 directs=7195 noTarget=2 badExpectation=0 notCodeRef=0 slowLayout=32 slowNull=20 byKind[value,syscall,mapped,invoke,resumable]=[0, 38151, 32587, 7179, 2381]
  noTarget 2 name KnowHOWMethods
  misses 2893 lang-meth-call
  misses 1913 lang-call
  misses 213 boot-syscall
  misses 35 raku-assign
  misses 1 raku-meth-call-qualified
  misses 1 raku-coercion
```

All 4 MISMATCH blocks are the *same single identity* as the nqp run:
`NQPCORE.setting.jar!C2FAD65C9748828B2511CD02A71D59CD9621494F#118#0 lang-meth-call`. No Rakudo-side
identity mismatched on the cold `-e ''` path.

Note the verify run reproduces the Task 4 baseline exactly (`misses=5056 sites=6522 anon=5 sitesAll=6596
recorded=4723`), which is the intended meaning of verify mode: nothing installed, everything recorded fresh.

### 5d — extra check: does rakudo's training clobber nqp's?

The rakudo training run rewrites nqp's lib jars with a *smaller* slot count than the nqp training run did
(NQPCORE 101 vs 103, nqpmo 38 vs 142, QASTNode 35 vs 38), so the nqp consumer was re-measured afterwards:

```
cd ROOT/nqp && NQP_DISPATCH_STATS=1 ./nqp-j-gradle -e '' </dev/null > step5d-nqp-consumer-after-rakudo.log 2>&1
```
Wall: **1.099 s**.
```
dispatch stats: hits=7807 misses=1725 sites=2851 anon=3 sitesAll=2867 restored=1656 restoredSites=1646 dropped=30 recorded=108 …
```

restored 1677 -> 1656, recorded 87 -> 108, dropped 9 -> 30. So the writer **merges** (restored + recorded)
rather than truncating to what the current run touched — nqp's training survives a rakudo training run — but
there is a small erosion (~21 programs, ~1.3 %) where the rakudo run re-recorded an nqp site with a
Raku-flavoured program and won the slot.

## Step 6: sizes

`ls -l`, before (23:14-23:28 / 20:40 mtimes) -> after (00:08-00:09):

| jar | before | after | delta |
|---|---:|---:|---:|
| blib/CORE.c.setting.jar | 56 077 905 | 56 362 465 | +284 560 (+0.51 %) |
| blib/CORE.d.setting.jar | 212 318 | 219 530 | +7 212 |
| blib/Perl6/BOOTSTRAP/v6c.jar | 11 348 915 | 11 735 401 | +386 486 (+3.4 %) |
| blib/Perl6/BOOTSTRAP/v6d.jar | 8 668 | 10 605 | +1 937 |
| blib/Perl6/Compiler.jar | 66 604 | 79 432 | +12 828 |
| blib/Perl6/Metamodel.jar | 1 001 630 | 1 037 959 | +36 329 |
| blib/Perl6/ModuleLoader.jar | 52 935 | 63 736 | +10 801 |
| blib/Perl6/Ops.jar | 48 942 | 81 723 | +32 781 |
| blib/Perl6/Optimizer.jar | 496 682 | 502 116 | +5 434 |
| blib/Perl6/SysConfig.jar | 18 081 | 23 463 | +5 382 |
| blib/Raku/Actions.jar | 955 667 | 998 281 | +42 614 |
| blib/Raku/Grammar.jar | 8 546 574 | 8 570 222 | +23 648 |
| rakudo.jar | 22 858 | 37 335 | +14 477 |
| nqp .../ModuleLoader.jar | 25 237 | 27 382 | +2 145 |
| nqp .../NQPCORE.setting.jar | 205 064 | 229 773 | +24 709 |
| nqp .../NQPHLL.jar | 572 756 | 627 174 | +54 418 |
| nqp .../nqp.jar | 1 145 720 | 1 220 730 | +75 010 |
| nqp .../nqpmo.jar | 211 969 | 263 205 | +51 236 |
| nqp .../NQPP6QRegex.jar | 598 108 | 603 516 | +5 408 |
| nqp .../QAST.jar | 750 084 | 1 239 373 | **+489 289 (+65 %)** |
| nqp .../QASTNode.jar | 253 443 | 262 657 | +9 214 |
| nqp .../QRegex.jar | 285 754 | 300 392 | +14 638 |

Unchanged (never loaded by `-e ''`): CORE.e.setting.jar, v6e.jar, Perl6/Pod.jar.

`unzip -lv | grep -E 'dispatch|index'` — the `unit.dispatch` entries (all `Stored`, uncompressed):

| jar | entry | before | after |
|---|---|---:|---:|
| blib/CORE.c.setting.jar | unit.index | 1 267 779 | 1 267 779 |
| blib/CORE.c.setting.jar | **unit.dispatch** | **0** | **284 060** |
| blib/CORE.c.setting.jar | nested/…{17FE8463,2DDCE35A,47DC3A1A,D48419DF}.dispatch | 0 each | 125 each (same crc 578ac55e) |
| nqp/…/QAST.jar | unit.index | 31 845 | 31 845 |
| nqp/…/QAST.jar | **unit.dispatch** | **0** | **489 289** |
| blib/Perl6/BOOTSTRAP/v6c.jar | unit.index | 407 760 | 407 760 |
| blib/Perl6/BOOTSTRAP/v6c.jar | **unit.dispatch** | **0** | **386 486** |

`unit.index` sizes are unchanged everywhere (only its crc changed), so the rewrite really is
slot-in-place: the dispatch blob is the whole cost.

Cost per program: CORE.c 284 060 B / 1 487 programs = ~191 B; QAST 489 289 / 1 113 = ~440 B;
v6c 386 486 / 1 105 = ~350 B.

## Step 7: t/01-sanity on a server started after the training

### 7a — default (persist on)

```
cd ROOT && RAKUDO_RAKUAST=1 perl t/harness5 --jvm --evalserver t/01-sanity </dev/null > step7a-sanity-default.log 2>&1
```
```
All tests successful.
Files=25, Tests=303, 40 wallclock secs ( 0.09 usr  0.03 sys + 15.43 cusr  0.78 csys = 16.33 CPU)
Result: PASS
```
**25/25, 303 tests, PASS, 40 s.**

### 7b — verify + stats

```
cd ROOT && RAKUDO_RAKUAST=1 NQP_DISPATCH_PERSIST=verify NQP_DISPATCH_STATS=1 perl t/harness5 --jvm --evalserver t/01-sanity </dev/null > step7b-sanity-verify.log 2>&1
```
```
t/01-sanity/55-use-trace.t       (Wstat: 0 Tests: 3 Failed: 1)
  Failed test:  3
Files=25, Tests=303, 56 wallclock secs ( 6.99 usr  0.45 sys + 17.25 cusr  2.90 csys = 27.59 CPU)
Result: FAIL
dispatch-verify: matched=113068 mismatched=313 unseen=71161
dispatch stats: hits=8638943 misses=362216 sites=102390 anon=1643 sitesAll=109310 restored=113890 restoredSites=107511 dropped=2000 recorded=193540 slowEvals=152707 invokes=939746 directs=939300 noTarget=446 badExpectation=0 notCodeRef=0 slowLayout=136910 slowNull=15797 byKind[value,syscall,mapped,invoke,resumable]=[363, 2056923, 3719513, 744675, 2117469]
  noTarget 396 find_method KnowHOWMethods
  noTarget 50 name KnowHOWMethods
  misses 226051 lang-meth-call
  misses 127123 lang-call
  misses 6155 boot-syscall
  misses 1710 raku-assign
  misses 953 boot-resume
  misses 70 raku-is-attr-inited
```

### 7c — verify only (no stats), the brief's exact variant

```
cd ROOT && RAKUDO_RAKUAST=1 NQP_DISPATCH_PERSIST=verify perl t/harness5 --jvm --evalserver t/01-sanity </dev/null > step7c-sanity-verify-nostats.log 2>&1
```
```
t/01-sanity/55-use-trace.t       (Wstat: 0 Tests: 3 Failed: 1)
  Failed test:  3
Files=25, Tests=303, 45 wallclock secs (...)
Result: FAIL
dispatch-verify: matched=113074 mismatched=313 unseen=71166
```

**Server stderr WAS captured.** harness5 spawns the server with `open JVMSERVER, "| ./rakudo-eval-server …"`
(t/harness5:155), so the server inherits the shell's stderr; redirecting the whole harness command captures
the server's exit-time `dispatch-verify:`/`dispatch stats:` summary — both appear after `Result:` above.
The *per-run* detail (`dispatch-verify: on` and the individual `MISMATCH` blocks) does **not** appear: those
go to the per-run output stream that the eval server pipes to the client, and TAP::Harness at verbosity 0
discards non-TAP lines. So `grep -c MISMATCH` on the harness log is 0 while the summary reports 313.
MISMATCH identities for the warm run are therefore **not** individually captured; the totals are.

**The 55-use-trace.t failure is an instrumentation artifact, not a regression.** That test spawns a child
`$*EXECUTABLE` and compares the child's *entire stderr* against a 4-line expectation
(`is $p.err.lines.join("\n"), …`). With `NQP_DISPATCH_PERSIST=verify` exported, the child prints
`dispatch-verify: on` (+ any MISMATCH blocks, + `dispatch stats:` under 7b) to its stderr, so test 3 fails.
Step 7a, with the same trained jars and persist ON, passes 25/25 — the persisted programs themselves break
nothing.

### 7d — warm-path mismatch identities, captured directly

Because the harness filters them, one sanity file was run straight through `./rakudo-j` under verify:

```
cd ROOT && RAKUDO_RAKUAST=1 NQP_DISPATCH_PERSIST=verify NQP_DISPATCH_STATS=1 ./rakudo-j -Ilib t/01-sanity/99-test-basic.t
```
```
dispatch-verify: on
dispatch-verify: matched=4506 mismatched=13 unseen=5616
```
The 13 mismatches fall on **4** identities:
```
  5  NQPCORE.setting.jar!C2FAD65C9748828B2511CD02A71D59CD9621494F#118#0   lang-meth-call
  4  v6c.jar!perl6#545#1                                                 lang-meth-call
  3  Actions.jar!0EC4B1D9E99EFD818EF47455F75136AAB6C078B0#15#5           lang-meth-call
  1  Actions.jar!0EC4B1D9E99EFD818EF47455F75136AAB6C078B0#14#1           lang-meth-call
```

## Findings

1. **The persisted miss works.** rakudo cold `-e ''` `recorded` falls **4723 -> 193** (-96 %), with
   `restored=4477` across 4195 sites and `dropped=37`. nqp cold `-e ''` falls **1766 -> 87**. Both beat
   C0's predictions (under 500 / under 100). Cold wall time on the same build: rakudo 2.483 s with restore
   off (the verify run) vs **1.943 s** with restore on, i.e. ~0.54 s / ~22 % off a `-e ''` — single-sample,
   not a benchmark, but the direction is right.

2. **What remains in the histogram.** The residual misses are overwhelmingly `lang-meth-call` (2163 of 4306
   on the rakudo consumer) and `lang-call` (1911). Note `misses` barely moves (5056 -> 4306): restore happens
   *at* the miss, so a restored site still counts a miss — the win is that the miss costs a decode instead of
   a dispatcher program run, which is exactly what `hits=80298 -> 13292` and
   `byKind[…syscall]=38151 -> 2179` show (the dispatcher guest code no longer runs).
   `dropped` is small everywhere (9 / 37 / 80 cold; 2000 of 113 890 on the warm suite, 1.8 %).

3. **Sizes are affordable.** CORE.c +0.51 %, v6c +3.4 %, QAST +65 % (QAST is a small jar with an outsized
   number of hot sites: 1111 slots). `unit.index` is untouched in all three, confirming the in-place
   slot rewrite. ~190-440 bytes per persisted program.

4. **The mismatches (the BLOCKED item) look like a verify-mode/one-slot-per-site limitation, not a codec
   bug.** Evidence: dumping the installed programs with `NQP_DISPATCH_DUMP` shows the offending nqp site
   has **17** installed programs —
   `site …/NQPCORE.setting.jar!C2FAD65C9748828B2511CD02A71D59CD9621494F#118#0 lang-meth-call 17` —
   while NQPCORE's whole jar persisted 114 programs over 103 slots, i.e. ~1 program per slot. Verify compares
   *every* fresh record at an identity against *the* persisted program for that identity, so a polymorphic
   site necessarily reports (n-1) or n mismatches. Consistent with that: in all 8 nqp blocks the `persisted:`
   text is identical and only the `recorded:` receiver STable varies; and the two forms are the two legitimate
   shapes of an nqp `lang-meth-call` program — a receiver-type-guarded one (`type(arg(0),st:…)` + literal
   method table) and a HOW/method-cache-generalised one (`type(how(arg(0)),…)` + `cached_all_method_table`).
   In the Rakudo `Actions.jar!…#14#1` case the roles are reversed (persisted = type-guarded,
   recorded = `how()` + `$!cached_all_method_table_epoch`), which says the chosen shape depends on the
   method-cache state at the moment of the miss, not on the codec.
   Rates: 8/1687 (0.47 %) nqp cold, 4/4479 (0.09 %) rakudo cold, 313/113 381 (0.28 %) warm t/01-sanity,
   13/4519 on one file. Nothing was fixed here per the task's constraints; the decision (tighten verify to
   "recorded is a member of the persisted set", or persist all programs per slot, or accept) is Task 3/4's.

5. **Two smaller anomalies worth the ledger.**
   - Training rakudo after nqp erodes ~1.3 % of nqp's persisted programs (restored 1677 -> 1656,
     recorded 87 -> 108): the merge is last-writer-wins per slot, and a Raku-flavoured program can take an
     nqp site's slot. Harmless today; it means "train nqp, then rakudo" leaves nqp very slightly worse.
   - Any run with `NQP_DISPATCH_PERSIST=verify` (with or without STATS) fails `t/01-sanity/55-use-trace.t`,
     because that test compares a child process's whole stderr. If verify mode is ever wanted inside a test
     sweep, its output needs to go somewhere other than stderr (a file via an env var), or that test must be
     excluded. With persist ON (the default) the suite is 25/25 PASS.

Raw logs (all runs, stdin from /dev/null, stderr merged):
`/home/longwalker/.claude/jobs/ba3ab3a7/tmp/task6/{sizes,entries}-{before,after}.txt`,
`step2-nqp-train.log`, `step3-nqp-consumer.log`, `step4-nqp-verify.log`, `step5a-rakudo-train.log`,
`step5b-rakudo-consumer.log`, `step5c-rakudo-verify.log`, `step5d-nqp-consumer-after-rakudo.log`,
`step7a-sanity-default.log`, `step7b-sanity-verify.log`, `step7c-sanity-verify-nostats.log`,
`step7d-99-test-basic.log`, `nqp-consumer.dump`.

---

# Re-run (2026-09-16, nqp `d3e602917`)

After the BLOCKED report, three rulings landed in nqp `d3e602917` ("Dispatch: verify compares by evaluated
outcome; a verify log; drop reasons"), the runtime jars were rebuilt and synced by the coordinator, and the
steps below were re-run **without retraining** — the artifacts trained in Steps 2/5a above are the input.
Same constraints: no build, no edit, no commit, every runner `</dev/null 2>&1` into a file under
`/home/longwalker/.claude/jobs/ba3ab3a7/tmp/task6/rerun/`, `RAKUDO_RAKUAST=1` on every rakudo command.

**Result: DONE.** `mismatched=0` on every run; `t/01-sanity` is 25/25 PASS under verify.

## R1: drop reasons

```
cd ROOT     && RAKUDO_RAKUAST=1 NQP_DISPATCH_PERSIST_TRACE=1 NQP_DISPATCH_STATS=1 ./rakudo-j -e ''
cd ROOT/nqp &&                  NQP_DISPATCH_PERSIST_TRACE=1 NQP_DISPATCH_STATS=1 ./nqp-j-gradle -e ''
```
Wall: rakudo **2.033 s**, nqp **1.056 s**. Both stats lines reproduce the earlier consumer runs exactly
(rakudo `dropped=37 recorded=193 restored=4477`; nqp `dropped=30 recorded=108 restored=1656`), and the trace
emits exactly `dropped` lines: 37 and 30. Marker present on both.

**The 37 rakudo drops are all one reason: `no SC <handle>`** — nothing else appears (no `... is empty`,
no `no HLL config ...`). By distinct SC handle:

| handle | count |
|---|---:|
| `6DDBA3D53BF6003AAC5A4C4904CCCCC0E610ECAB` | 19 |
| `152726231FCE0ED7AB645057F4ACEF583109174B` | 10 |
| `5CD4D74658F13F40F60579ABCBBA8C1AC0476DE7-0` | 5 |
| `282793E4D175F498E2305EE4C5C86304E465C997-0` | 2 |
| `6C32F283435842EE0FB8D450F451E6EB70F387C1-0` | 1 |

By unit (from the identity string): `v6c.jar` 18, `CORE.c.setting.jar` 10, `NQPCORE.setting.jar` 6,
`NQPHLL.jar` 2, `QRegex.jar` 1. By site — 20 of the v6c drops are **one contiguous block of sibling
callsites in a single frame**, `v6c.jar!perl6#4703#20 … #4703#40` (18 of them dropped here), and the
NQPCORE ones are all the already-familiar polymorphic site:

```
      6  NQPCORE.setting.jar!C2FAD65C9748828B2511CD02A71D59CD9621494F#118#0
      2  NQPHLL.jar!47D31BB6AA6B9B7709E8D373B49B998E7CCD88B2#142#0
     18  v6c.jar!perl6#4703#{20..35,38,40}                       (one program each)
     10  CORE.c.setting.jar!F80D4F15…#{6451#0,6456#0,6479#2,6479#3,14266#2,14485#3,14485#4,15744#4,15744#8,15744#13}
      1  QRegex.jar!08CDC1DF…#94#2
```

nqp's 30 drops, same single reason, handles
`2FC302E1…-0` 13, `6C32F283…-0` 9, `5CD4D746…-0` 5, `282793E4…-0` 2, `6DDBA3D5…` 1; units
`NQPHLL.jar` 16, `QRegex.jar` 8, `NQPCORE.setting.jar` 6.

None of the five handles occurs anywhere in `blib/` or `nqp/build/jvm/share/lib/` (`grep -rl` over the jars;
`unit.index` is a `Stored` entry, so a match would be found if it were there). So **"no SC" means the
program's guard or outcome names an object owned by a serialization context created at runtime rather than
by any store-backed artifact** — the process's own SC and the BOOTSTRAP/EXPORTHOW metaobjects built during
this run. Those programs are unpersistable by construction, not by an encoding gap; 37 of 4670 installed
programs (0.8 %) is the floor for this workload.

## R2: cold verify, both runners, log to file

```
cd ROOT/nqp && NQP_DISPATCH_STATS=1 NQP_DISPATCH_PERSIST=verify \
  NQP_DISPATCH_VERIFY_LOG=…/rerun/verify-nqp.log ./nqp-j-gradle -e ''
cd ROOT     && RAKUDO_RAKUAST=1 NQP_DISPATCH_STATS=1 NQP_DISPATCH_PERSIST=verify \
  NQP_DISPATCH_VERIFY_LOG=…/rerun/verify-rakudo.log ./rakudo-j -e ''
```
Wall: nqp **1.297 s**, rakudo **2.627 s**.

**stderr is clean**: `grep -c dispatch-verify` on both captured stderr/stdout files = **0**.
The logs (pid-prefixed, appended) hold both the `on` marker and the totals:

```
[265103] dispatch-verify: on
[265103] dispatch-verify: matched=1658 byOutcome=8 mismatched=0 unseen=62          # nqp
[265182] dispatch-verify: on
[265182] dispatch-verify: matched=4475 byOutcome=4 mismatched=0 unseen=127         # rakudo
```

**`mismatched=0` on both.** `grep -c MISMATCH` = 0 in each log. The counts confirm the diagnosis in
Finding 4 above: the previously reported 8 (nqp) and 4 (rakudo) mismatches are now exactly the `byOutcome`
column — same target on the recorded call's arguments, different guard-tree text — so they were never
wrong programs, only differently-shaped ones. nqp's `matched` moves 1679 → 1658 because those 8 plus 13
others are now classified out of `matched`; `matched + byOutcome` is stable.

Stats lines for the record:
```
nqp:    dispatch stats: hits=23752 misses=1771 sites=2851 anon=3 sitesAll=2867 restored=1657 restoredSites=1647 dropped=30 recorded=1766 …
rakudo: dispatch stats: hits=80298 misses=5056 sites=6522 anon=5 sitesAll=6596 restored=4476 restoredSites=4223 dropped=80 recorded=4723 …
```

## R3: warm `t/01-sanity` under verify

```
cd ROOT && RAKUDO_RAKUAST=1 NQP_DISPATCH_PERSIST=verify \
  NQP_DISPATCH_VERIFY_LOG=…/rerun/verify-sanity.log perl t/harness5 --jvm --evalserver t/01-sanity
```
```
All tests successful.
Files=25, Tests=303, 43 wallclock secs ( 0.10 usr  0.03 sys + 16.19 cusr  0.84 csys = 17.16 CPU)
Result: PASS
```
**25/25 PASS, 43 s** — `55-use-trace.t` passes now that the verify output leaves stderr, which confirms the
earlier failure was purely the instrumentation print in the child's stderr.
`grep -c dispatch-verify` on the harness log = **0** (stderr clean end to end, server included).

The log holds **two** processes (2 `on` lines, 2 distinct pids): the eval server, and one child — the
`$*EXECUTABLE` that `55-use-trace.t` spawns:

```
[265646] dispatch-verify: matched=113063 byOutcome=313 mismatched=0 unseen=71139   # eval server
[265888] dispatch-verify: matched=4427   byOutcome=14  mismatched=0 unseen=2754    # 55-use-trace.t child
```
Summed: **matched=117 490, byOutcome=327, mismatched=0, unseen=73 893**.
**MISMATCH blocks in the log: 0.** The server's 313 byOutcome are exactly the 313 that were reported as
`mismatched` before the ruling.

## R4: control — `t/01-sanity` in default mode (persist on, no verify)

```
cd ROOT && RAKUDO_RAKUAST=1 perl t/harness5 --jvm --evalserver t/01-sanity
```
```
All tests successful.
Files=25, Tests=303, 42 wallclock secs ( 0.09 usr  0.03 sys + 15.64 cusr  0.82 csys = 16.58 CPU)
Result: PASS
```
**25/25 PASS, 42 s** (40 s on the pre-ruling build — same within noise; verify mode costs ~1 s over it).

## Re-run findings

1. Every mismatch the first pass reported was a shape difference, not an outcome difference: 8 + 4 cold and
   313 warm all reclassify to `byOutcome`, and `mismatched` is **0** on all four verify runs. The BLOCKED
   condition is cleared.
2. The verify log keeps stderr clean, which alone fixes `t/01-sanity` under verify (25/25 instead of 24/25),
   and the pid prefix makes the child-process totals separable from the server's.
3. Drops are one cause only — `no SC <handle>`, an object owned by a runtime-created serialization context —
   across 5 handles, concentrated in one v6c frame (`perl6#4703#20..40`, 18 programs) and the known
   polymorphic `NQPCORE …#118#0` site. 37 of ~4670 installed programs on a rakudo `-e ''`.
4. Consumer-side numbers are unchanged by the new build: rakudo `recorded=193` (from a 4723 baseline),
   `restored=4477`, `dropped=37`.

Re-run logs: `/home/longwalker/.claude/jobs/ba3ab3a7/tmp/task6/rerun/` —
`step1-{rakudo,nqp}-drops[-timed].log`, `step2-{nqp,rakudo}-verify[-timed].log`,
`verify-{nqp,rakudo,sanity}.log` (+ `-timed` variants), `step3-sanity-verify.log`, `step4-sanity-default.log`.
