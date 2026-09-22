# Task 10 report: the loop baseline, and the slowEvals question

Build: rakudo `fa16081af3` (worktree `jesp-direct-lazy-records`), nqp
`41c294b02`. `blib` last written 12:29 by Task 1's build and untouched by
this session (`find blib -newermt 16:00` empty at 19:18). All runs are
direct `./rakudo-j` invocations — no eval server, no polyglot engine
option except the one `./rakudo-j` itself carries
(`WarnVirtualThreadSupport=false`). Scratch under
`$CLAUDE_JOB_DIR/tmp` (`plusquick-stock.log`, `plusquick-trace.log`,
`resume-smoke.log`).

## (a) The loop baseline — STOCK

`RAKUDO_RAKUAST=1 NQP_DISPATCH_STATS=1 ./rakudo-j docs/bench/jesp/plusquick.raku`

```
ns/op=85.825 s=3
dispatch stats: hits=90247946 misses=11623 slowEvals=976 invokes=13867 directs=13848
  noTarget=19 badExpectation=0 notCodeRef=0
  byKind[value,syscall,mapped,invoke,resumable]=[0, 95765, 45117640, 13467, 45021074]
```

Against milestone 5's post-layout run (85.525 ns/op; `hits=90247539
misses=11614 slowEvals=976 invokes=13845 directs=13826 noTarget=19`,
`byKind=[0, 95661, 45117402, 13446, 45021030]`): reproduced. `slowEvals`
is 976 on the nose; the other counters differ only in the low hundreds,
which is the startup jitter the eval-free road carries.

**Three repeat runs, same command, same build:** 89.375, 87.400, 89.175
ns/op. Every one of the three printed a dispatch-stats line *identical to
the first, character for character* (`hits=90247946 misses=11623
slowEvals=976 invokes=13867 directs=13848 …`). Two further runs with
different instrumentation: 75.325 ns/op under `TraceCompilation`, 82.875
ns/op under `NQP_LAYOUT_STATS=1`.

So at one build, on one quiet machine, four identical stock runs span
**85.825 – 89.375 ns/op, a 4.1 % spread**, while the dispatch counters do
not move by a single unit. This is the single most important number in
the report and it is developed in part (c).

## (b) The correctness smoke — UNCHANGED

`RAKUDO_RAKUAST=1 ./rakudo-j docs/bench/jesp/resume-smoke.raku`, exit 0:

```
int:1 any:s
big small
B:A:1 A:2 D:A:4
h-any h-any
wrapped:42
X::Multi::NoMatch
Type check failed in binding to parameter '$x'; expected Int but got Str ("nope")
loop:2000
```

Nine lines, all as the resumption road is documented to answer in
`docs/jvm-jesp.md` (callsame, nextsame, callwith, wrap, the `where`-clause
bind failure falling through to the next candidate, the bind-error
message). **Unchanged: yes.** No literal transcript of the expected output
is stored anywhere in the tree — this is checked against the semantics the
doc describes and against the fact that every line is the correct answer
for its construct, not against a recorded diff; that limit is worth
recording, and a stored `.expected` beside the bench would remove it.

## (c) The slowEvals question

### What the number is, exactly

`slowEvals` is incremented in **exactly three places**, all in
`nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt`:
`AttrSrc.slow` (line ~160), `UnboxSrc.slow` (~194) and `SlowSrc.eval`
(~205). Each of them, under `STATS`, also prints a distinct human key the
first time that key is seen (`seenSlow`), so a stats run tells you *which*
of the three fired and on what.

In this run the stderr carries exactly **three** such lines, and all three
are `AttrSrc`:

```
dispatch slow attr $!dispatchees of org.raku.nqp.sixmodel.reprs.RakuObject8L  layout=null vs null
dispatch slow attr @!dispatchees of org.raku.nqp.sixmodel.reprs.RakuObject16L layout=null vs null
dispatch slow attr $!do          of org.raku.nqp.sixmodel.reprs.RakuObject16L layout=null vs null
```

No `slow unbox` key, no `slow source` key. So **all 976 slow evaluations
are attribute reads, on three shapes, and all three objects are
`RakuObject`s** (the `layout=…` / `vs …` halves both print `null` only
because `st.debugName` is unset for these STables — the print carries no
information about whether the two layouts differ).

They are printed at lines 4596, 4908 and 4909 of a 7725-line stats stream
whose `ns/op` line is 7705: all three shapes are first seen during
start-up, long before the timed loop.

### Ruling 1: slowEvals cannot be the 3.5 %

976 evaluations, in a window in which the same run performs 45 M
dispatches. The claimed regression is 2.9 ns × 40 M = **116 ms**. For 976
boundary crossings to cost that, each would have to cost 119 µs. They are
a `readAttribute` through the generic accessor: nanoseconds to a couple of
microseconds. Three orders of magnitude short.

Stronger, and independent of any cost model: `slowEvals` is **976 in every
one of the four stock runs, exactly**, while ns/op moves 4.1 % across
those same runs. A constant cannot explain a variable.

### Ruling 2: both milestone 5 leads are ruled out *as the cause of this
number*, by code

`DecontSite` and `BigIntSite` live in `NqpTypeOps.kt` and inherit
`NqpTypeOps.Site`, whose miss bookkeeping is a **per-site `misses: Int`
field** (`NqpTypeOps.kt:66`) used only for `mayResolve()`/`pin()`. They
touch neither `NqpDispatch.slowEvals` nor the `misses` printed in the
stats line (that one is `count(misses)` at `NqpDispatch.kt:626`, one call
site). Neither lead could move the reported number at all, in either
direction. The leads were aimed at the wrong counter.

**Lead 1 is nonetheless a real defect, and I confirm it.**
`NqpTypeOps.decont` (`NqpTypeOps.kt:236-271`) calls `miss(site)` *only* on
the `ost !== st` branch (line 267). When the STable matches but any of
these holds — `o !is RakuObject`, `site.layout == null`, `o.layout !==
layout`, `site.getter == null`, or the fetched value is `null` — control
falls out of the `if (ost === st)` block to `return decontSlow(o, tc)` at
line 270 **without** `miss(site)`. Such a site can never accumulate
misses, so it never pins and never re-speculates: it re-runs the same
failing test and re-crosses the same boundary on every execution, and
nothing in the stats shows it. That is a live, invisible slow road. No fix
made — a source change is a finding here, not an action.

**Lead 2 is stale.** The current `bigintArith`
(`NqpTypeOps.kt:697-737`) *does* re-verify the layout: its fast-path
condition is `… && layout != null && a is RakuObject && b is RakuObject &&
a.layout === layout && b.layout === layout`. The milestone 5 note predates
the code as it stands.

### Ruling 3: the documented mismatch cause is ruled out by measurement

`AttrSrc`'s own doc comment names the expected mismatch: "an object
reblessed while on a smaller class carries a variant layout of the same
type and takes the generic road here". That is
`RakuObjectREPRData.layoutFor` minting a **variant** layout
(`RakuObjectREPRData.kt:28-36`), which is `!== rd.layout`, while
`NqpDispatch.layoutOf` (`NqpDispatch.kt:447-451`) only ever yields the
canonical `rd.layout`.

The runtime has a knob for exactly this. `NQP_LAYOUT_STATS=1` on the same
bench:

```
layout stats: layouts=2122 variants=0 reblesses=2
```

**`variants=0`.** No variant layout is created anywhere in this workload.
The documented mismatch never happens here, so it is not what sends these
three attribute reads to the boundary.

### What is left, and which of it I can back

Inside `AttrSrc.eval`, with `o` a `RakuObject` (which the printed keys
prove), there are only two ways to reach `slow()`:

1. `o.layout !== layout`. Variants are out (`variants=0`). What remains is
   an object allocated against one canonical layout while its STable's
   `rd.layout` was later replaced — `rd.layout` is assigned in exactly one
   place, `RakuObjectREPR.install` (`RakuObjectREPR.kt:39`), reached from
   `compose` and from `deserialize_repr_data`, so a type composed *and*
   later deserialized (or composed twice) would leave older instances on a
   stale layout object. I could not confirm this fires: `layouts=2122` is
   consistent with it and also consistent with 2122 distinct types, and
   telling the two apart needs a counter this code does not have.
2. The slot read back `null`: `if (v != null) return v` — **a null,
   not-yet-vivified attribute falls through to `slow()` and is counted as
   a slowEval even though the layout matched perfectly.** The three
   attributes named are precisely ones that are legitimately null —
   `@!dispatchees`/`$!dispatchees` on a routine that is not (yet) a multi
   with a candidate list, `$!do` on a `Code` whose `$!do` has not been
   filled.

**(2) is my best fit and I label it a fit, not a proof.** It explains the
shapes, it explains why `misses` does not move (a null slot is not a guard
failure; the generic accessor returns the right answer), and it explains
why the number is bit-deterministic across runs — a fixed set of
setting objects with a fixed set of unvivified slots. What it does not do
is distinguish itself from (1) with evidence I have, because `AttrSrc.slow`
counts both branches into one counter and prints one key for both.
Separating them is a one-field change to the stats key — a finding, not
something I did.

I also cannot compare against the pre-layout build: milestone 5's 364 was
measured on a build this milestone has forward-only rules against
rebuilding (no A/B compiles), so "which of these branches grew from 364 to
976" is not answerable from here without that build.

### The third hypothesis: deoptimisation churn — confirmed in shape, and
it is the better explanation of the 3.5 %, but not of slowEvals

`RAKUDO_JVM_XOPTS=-Dpolyglot.engine.TraceCompilation=true`, one diagnostic
run (ns/op=75.325 — not the baseline). Totals: **86 `opt done`, 33 `opt
deopt`, 24 `opt inval.` over ~70 distinct roots by `id=`.** That is very
mild next to the CORE.c compile's 1515+ targets at >2 compiles each — the
loop bench is not a churn workload.

Top roots by compile+invalidate, counted by `id=`:

| id | root | done | deopt | inval |
| --- | --- | --- | --- | --- |
| 924 | `<anon>[775]` | 6 | 5 | 4 |
| 182 | `<anon>[1051]` | 4 | 3 | 3 |
| 926 | `find_method[499]` | 4 | 3 | 2 |
| 178 | `find_method[271]` | 4 | 3 | 2 |
| 176 | `<anon>[388]` | 3 | 2 | 2 |
| 934 | `<anon>[345]` | 3 | 3 | 1 |
| 6089 | `<unit>[705]<OSR@137438957392>` | 2 | 1 | 2 |
| 6088 | `<unit>[705]<OSR@137438956296>` | 2 | 1 | 2 |
| 4562 | `all_method_table[576]` | 3 | 1 | 1 |
| 3106 | `infix:<+>[272]` | 2 | 0 | 0 |

`|Reason` tally over the whole run:

| count | reason |
| --- | --- |
| 28 | uncommon trap |
| 14 | `validRootAssumption local tags updated` |
| 6 | dispatch site |
| 5 | JVMCI invalidate |
| 4 | Profiled Return Type |

So the milestone's per-local type-tag signature **is** present — and
squarely on the two roots that matter. But the timeline is the finding,
not the count:

```
17:12:59.930  opt done   id=3106 infix:<+>[272]                Tier 2
17:13:00.063  opt done   id=6088 <unit>[705]<OSR@…956296>      Tier 2
17:13:00.308  opt done   id=6088 <unit>[705]<OSR@…956296>      Tier 2
17:13:00.554  opt deopt  id=6088                               uncommon trap
17:13:00.556  opt inval. id=6088    validRootAssumption local tags updated
17:13:00.557  opt inval. id=6088    validRootAssumption local tags updated
17:13:00.752  opt done   id=6089 <unit>[705]<OSR@…957392>      Tier 2
17:13:01.024  opt done   id=6089 <unit>[705]<OSR@…957392>      Tier 2
17:13:03.564  opt deopt  id=6089                               uncommon trap
17:13:03.566  opt inval. id=6089    validRootAssumption local tags updated
17:13:03.567  opt inval. id=6089    validRootAssumption local tags updated
              ns/op=75.325
```

`<unit>[705]` is plusquick's mainline and it has **two OSR targets,
because it has two `while` loops** — the 5 M warm-up and the 40 M timed
loop. They are *different call targets*. The warm-up loop's target (6088)
is compiled, then invalidated at 00.554 — which is where the timer starts
— and the timed loop enters its own, cold, target (6089), whose two
compilations land at 00.752 and **01.024**. The measured window closes at
03.564: 40 M × 75.325 ns = 3.013 s, and 03.564 − 00.554 = 3.010 s, so the
window is pinned to the millisecond.

**The timed loop therefore spends its first ~470 ms — 15.6 % of the
measured window — not yet in its final compiled code.** plusquick's 5 M
warm-up warms a *different* call target from the one it times.

That is a sufficient, quantified mechanism for several percent of
run-to-run drift, and it is measured, not argued: 4.1 % observed across
four identical runs. It is also the honest answer to the milestone 5
question as posed. **The 82.625 → 85.525 "+3.5 % regression" was one run
per side. It is inside this bench's noise band at a single build, and is
not established as a real effect.**

### Verdict

- **The 3.5 %: not a regression that the evidence supports.** Four stock
  runs at one build span 4.1 %, wider than the delta, with byte-identical
  dispatch counters. Mechanism for the noise found and quantified: the
  timed loop is a separate OSR target that is still compiling for the
  first 15.6 % of the measured window.
- **`slowEvals` = 976: cause narrowed, not pinned.** All of it is
  `AttrSrc`, on three attributes, on `RakuObject`s, deterministic.
  Best fit is the null-slot branch of `AttrSrc.eval` (an unvivified
  attribute is counted as a slow eval although the layout matched);
  labelled a fit. Variant layouts are **ruled out by measurement**
  (`variants=0`); both milestone 5 leads are **ruled out by code** — they
  do not touch this counter.
- **Two real defects found, no source changed.** (i) `NqpTypeOps.decont`
  reaches `decontSlow` on a layout/getter/null mismatch without
  `miss(site)`, so such a site never pins, never repairs, and never shows
  in any counter. (ii) `AttrSrc.slow` merges a layout mismatch and a null
  slot into one counter and one debug key, which is why this question
  could not be closed from the outside.

## Concerns

- No stored expected output for `resume-smoke.raku`; "unchanged" is judged
  against `docs/jvm-jesp.md`'s description, not a recorded transcript.
- plusquick times a loop its warm-up does not warm; any future ns/op
  comparison should be a median of ≥5 runs, or the bench should time one
  loop it has already run.
- `NQP_DISPATCH_STATS=1` runs are the slowest of the six taken here
  (85.8–89.4 vs 75.3 and 82.9 without it). Both milestone 5 sides used it,
  so the comparison is fair, but the counters are not free.
- `slowEvals` cannot be closed without splitting `AttrSrc.slow`'s counter;
  that is a source change and therefore left as a finding.
