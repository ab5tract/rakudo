# Task 1 report — the three encoder shapes

Status: **DONE_WITH_CONCERNS** (all gates green; concerns are about two of the brief's
probes being unrunnable/mis-typed as written, and about `make` needing a forced clean)

Commit: nqp **c872c83af** — "encoder: exit-handler blocks encode (frame-forced),
with/without general form, labeled control and for :label (wire op FORLOOPL 35)"
(range reviewed: nqp `da1f5088a..HEAD`, 4 files, +122/-15)

---

## What I implemented, per step

**Step 1 — exit handlers encode, frame-forced.** Deleted the
`if $node.has_exit_handler { trace('no: exit handler'); return '' }` refusal in
`encode_block`, and changed the `%e` hash literal from `'frame_op', 0,` to
`'frame_op', ($node.has_exit_handler ?? 1 !! 0),` with the brief's six-line comment
above it. Verbatim from the brief.

**Step 2 — the dispatcher never enters such a block frame-free.** Added the brief's
three lines as the first statement of `frameFreeEntryOk`. I verified the field exists
before using it: `hasExitHandler` is a real `@JvmField` on
`nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/StaticCodeInfo.kt:126`
("Does this code object have a block exit handler?"), reached through the existing
`NqpRaw.staticInfo(cr)` helper. No invented names.

**Step 3 — `withy general`.** Replaced `cbail('withy general') if $withy;` with the
brief's block verbatim, and deleted the dead `my int $mark := nqp::elems(%e<code>);`
below it (confirmed dead: the code after it uses `$m1`/`$m2`, never `$mark`).
`emit_defined_test(%e, int $tmp)` exists at `TruffleEncoder.nqp:2371` with that exact
signature.

**Step 4 — `labeled control`.** Replaced the three-line `cbail('labeled control')` loop
with the brief's desugar verbatim. Before writing it I confirmed against
`Compiler.nqp:2102-2144` that the bytecode path builds exactly
newexception → setpayload(label) → setextype(cat|LABELED) → `_throw_c`, and that the
category constants are `%control_map`'s `*_label` entries. I also confirmed the three
constructor ops are reachable: `newexception`/`setpayload`/`setextype` resolve through
the classlib registry (`CODE_CLASSLIB_OPS`, encoder :2322-2360 — that path walks
`@($op)` positionally and ignores `.named`, so reusing the `:label`-named node as
setpayload's second child is fine), and `throw` is a hand row, `op3('throw', 181, …)`
at :569.

**Step 5 — the `FORLOOPL` wire op (runtime).** Added `FORLOOPL = 35` with the brief's
doc comment to `NqpWire.java`; gave `emitForBody` and `emitForPass` a trailing
`BytecodeLocal labelLocal` parameter; changed `emitForPass`'s catch-arm
`b.emitLoadNull();` to `if (labelLocal != null) b.emitLoadLocal(labelLocal); else
b.emitLoadNull();`; `emitForBody` passes it through on both `emitForPass` calls; the
existing `FORLOOP` case passes `null`; added the new `case NqpWire.FORLOOPL` right
after `case NqpWire.FORLOOP`, verbatim from the brief.
I searched for a second op-keyed size/skip table as the brief instructed — there is
none. `FORLOOP` appears only in the one switch, which computes `endAt` by walking
children under `emit=false`; the new case does the same, so no other table needs a row.

**Step 6 — `for :label` in the encoder.** Added `my int $W_FORLOOPL := 35;` next to
`$W_FORLOOP`; replaced the `encode_for` head (comment now true, `:label` captured,
`cbail('labeled nohandler for')` guard); the handled arm allocates the obj label local,
emits `$W_FORLOOPL` vs `$W_FORLOOP`, and pushes `$lbl_local` + the label child in the
outer handler context before the condition. Verbatim from the brief.

Wire order emitted vs. read, checked by hand:
`[FORLOOPL][condType][lid][nrid][outer][lblLocal][labelExpr][cond][pre][body]`
against the builder's `at+1..at+5` header and `labelAt = at + 6`. They match.

Everything in the brief existed as named. **No substitutions were needed** — the one
thing I had to go find rather than take on faith (`hasExitHandler`) turned out to be
real.

---

## Gates, with their verdict lines

**Step 7 — runtime jars compile**
`./nqp/gradlew -p nqp :nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars`
→ `BUILD SUCCESSFUL in 3s`, 14 actionable tasks. (Only pre-existing Kotlin warnings.)

**Step 8 — nqp clean build, unit road, strict**
```
NQP_UNIT=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 NQP_CODE_STRICT=1 RAKUDO_RAKUAST=1 \
  raku tools/build/watched-run.raku --log=.../t1-build.log \
  --show='> Task :stage' --show='code-bail' --show='BUILD' --show='rror' \
  -- ./nqp/gradlew -p nqp clean buildJvm
```
→ `BUILD SUCCESSFUL in 4m 47s` / **`=== EXIT=0 verdict=ok elapsed=287s ===`**
`grep -c code-bail t1-build.log` → **0** (strict mode, so a single refusal would have
failed the build).

Artifacts — all 11 jars in `nqp/build/jvm/share/lib/`, each `meta=1 class=0`:
JASTNodes, ModuleLoader, NQPCORE.setting, NQPHLL, NQPP5QRegex, NQPP6QRegex, QAST,
QASTNode, QRegex, nqp, nqpmo → `ALL JARS OK`. Re-checked *after* the Rakudo build:
still `ALL JARS OK`.

**Step 9 — t/nqp on the record road: 118/118**
```
NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 \
  raku tools/build/watched-run.raku -t=nqp/t/nqp --jobs=3 -- nqp/nqp-j-gradle
```
→ SUMMARY **`116 of 118 ok in 384s`**, the only two FAILs being the predicted
cwd-relative pair: `nqp/t/nqp/019-file-ops.t`, `nqp/t/nqp/063-slurp.t`.
Both re-run from the nqp directory with the same env:
- `019-file-ops.t` → `ok 112 - read from spurted line 2 ok` (all pass)
- `063-slurp.t` → `1..1 / ok 1 - File slurped`

**Result: 118 of 118.**

The three target files all pass: `059-nqpop.t`, `067-container.t`,
`084-loop-labels.t` (and `121-for-controls.t`) — all `exit 0, ok`.

**084 unwind trace** (`NQP_UNWIND_TRACE=1`), categories seen:
```
loopBodyUnwind cat=4100 …  -> redo=0      (NEXT|LABELED  = 4 + 4096)   x11
loopBodyUnwind cat=4104 …  -> redo=1      (REDO|LABELED  = 8 + 4096)   x2
loopBodyUnwind cat=4    …  -> redo=0      (plain NEXT)
loopBodyUnwind cat=8    …  -> redo=1      (plain REDO)
```
The required `loopBodyUnwind cat=4100` is present, and labeled REDO correctly drives
`redo=1`.

**Step 10 — Rakudo make + sanity**
First `make` returned **`=== EXIT=0 verdict=ok elapsed=0s ===`** — a no-op: Rakudo's
rules do not depend on the nqp stage jars, so nothing rebuilt. I caught this, ran
`make clean` (which is `j-clean` + rakudo products only — it does **not** touch
`nqp/build/`), and re-ran:
```
raku tools/build/watched-run.raku --log=.../t1-make2.log \
  --show='Compiling' --show='Generating' --show='rror' --stall=1800 -- make
```
→ **`=== EXIT=0 verdict=ok elapsed=1233s ===`** (brief's baseline 1274 s), with the full
marker sequence (rakudo.jar, BOOTSTRAP v6c/v6d/v6e, CORE.c/CORE.d/CORE.e settings).
`grep -c 'exit handler' t1-make2.log` → **0**; `grep -c code-bail` → **0**.

```
raku tools/build/watched-run.raku -t=t/01-sanity --jobs=2 -- ./rakudo-j
```
→ **`25 of 25 ok in 207s`**.

---

## Probe table

Rakudo exit-handler probes, each `RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./rakudo-j -e '…'`:

| # | Probe | Expected | Got | |
|---|---|---|---|---|
| A | `sub f() { LEAVE say "leave"; 42 }; say f()` | leave / 42 | `leave` `42` | PASS |
| B | `sub f() { LEAVE say "leave"; return 7; 42 }; say f()` | leave / 7 | `leave` `7` | PASS |
| C | `sub f($x) { KEEP …; UNDO …; $x ?? 1 !! Nil }; f(1); f(0)` | keep / undo | `keep` `undo` | PASS |
| D | `for ^3 { LEAVE say "L$_"; next if $_ == 1; say "body $_" }` | body 0 L0 L1 body 2 L2 | exactly that | PASS |
| E | `for ^3 { LEAVE say "L$_"; last if $_ == 1 }` | L0 L1 | `L0` `L1` | PASS |
| F | `my $l = Lock.new; $l.protect({ say "in" }); say "out"` | in / out | `in` `out` | PASS |
| G | `sub f(--> Int) { POST { $_ > 0 }; 5 }; say f()` | 5 | `5` | PASS |
| H | `sub f() { my $x will leave { say "wl" } = 1; 9 }; say f()` | wl / 9 | `wl` `9` | PASS* |
| I | `sub f() { LEAVE say "l"; g() }; sub g() { 3 }; say f()` | l / 3 | `l` `3` | PASS |

\* H as written in the brief (`my $x = 1 will leave { … }`) is not valid Raku — a `will`
trait precedes the initializer. It failed to **parse** (`Confused … my $x = 1<HERE> will`).
Corrected to `my $x will leave { say "wl" } = 1;`, which is the same construct, and it
passes. This is a brief typo, not a code defect.

**Framing check:**
```
NQP_CODE_WHY=1 … -e 'sub f() { LEAVE say "leave"; 42 }; say f()' 2>&1 | grep 'code frame f '
→ code frame f -> framed frame_op=1 fdecls=0 dispatches=0 nested=1 uses_hll=0
```
`-> framed` with `frame_op=1`, as designed. The same run greps **0** occurrences of
`exit handler` — the refusal is gone, not merely bypassed.

**withy probes.** The brief's four `nqp::with` probes are **not runnable in bare NQP**,
for a reason that is not my change: `emit_defined_test` dispatches the `.defined`
*method*, and NQP's own objects have none. Probes 1 and 2 encoded fine (no `code-bail`)
and then died at runtime with `Cannot find method 'defined' on object of type BOOTStr`
/ `Cannot call method 'name' on a null object`; probe 4 (`nqp::with(3, "t")`) bails
`withy cond not obj` in the **pre-existing** value/2-child branch, because the literal
`3` types as int.

I verified this is inherent rather than mine: the pre-existing cond-passing withy branch,
on the identical input (`nqp::with($x, -> $y { … })` with `$x := "a"`), produces the
*identical* error. So my branch reproduces the established `defined` dispatch exactly.

I therefore built runnable NQP equivalents that do exercise the new branch, using a class
that defines `defined`:

| Probe | Expected | Got | |
|---|---|---|---|
| `nqp::with(D.new, say "t", say "f")` / `U.new` — void, 3 children | t / f | `t` `f2` | PASS |
| `nqp::with(D.new, say "has")` / `U.new`, then `say "end"` — void, 2 children | has, (nothing), end | `has` `end` | PASS |
| `say(nqp::with(D.new,"t","f"))` / `U.new` — value, 3 children | t / f | `t` `f` | PASS |
| `nqp::without(D.new, say "wD", say "eD")` / `U.new` — negate | eD / wU | `eD` `wU` | PASS |

(`D.defined` → 1, `U.defined` → 0.) All four withy shapes — void/value, 2/3 children,
`with`/`without` — behave correctly. The real production coverage is Rakudo's own
`with`/`without`, which the 1233 s CORE build compiled without a single bail.

---

## Files changed

nqp tree (all in commit c872c83af):
- `nqp/src/vm/jvm/QAST/TruffleEncoder.nqp` (+68/-15 region): steps 1, 3, 4, 6
- `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt` (+3): step 2
- `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpWire.java` (+5): step 5
- `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java` (+61/-8): step 5

Rakudo tree: **no source changes**. (Build products and `sweep-logs/` are untracked, as
before. A one-off Raku waiter and a jar-checker script live under
`/home/longwalker/.claude/jobs/288cfddd/tmp/`, deliberately outside the repo.)

---

## Self-review findings

- Diff contains only the four intended files; `git status` in the nqp tree is clean.
- No stray prints, no debug code, no commented-out leftovers. Every diagnostic used
  during the task was an existing env-gated knob (`NQP_CODE_BAIL`, `NQP_CODE_WHY`,
  `NQP_UNWIND_TRACE`); I added none.
- Wire change is strictly additive: one new constant, one new `case`. No existing
  layout, constant, or code path changed meaning. `FORLOOP` still passes `null` and
  emits byte-identical output to before.
- The `labelLocal` threading is null-safe on both arms; `FORLOOPL` loads the local
  unconditionally (it always has one), `FORLOOP` always passes `null`.
- **Nit (not fixed):** `my int $W_FORLOOPL := 35;` sits between `$W_FORLOOP := 32` and
  `$W_P6BINDSIG := 33`, so the constant block is no longer in numeric order — the brief
  said to put it next to `$W_FORLOOP`, and the same is true of `FORLOOPL` in
  `NqpWire.java`. Purely cosmetic; I did not spend a 5-min nqp + 20-min Rakudo rebuild
  cycle on comment ordering. Worth folding into the next encoder change.
- **Reviewed and deliberately kept:** `for @($op) { $label := $_ if $_.named eq 'label' }`
  takes the *last* `:label` child, not the first. The user raised this mid-task. It is a
  verbatim transcription of `Compiler.nqp:2103-2106`, which is also last-wins, and
  matches the existing while/until capture at `TruffleEncoder.nqp:1400`, so the engine
  road and class road agree on every input. The user confirmed ("got it, thanks") to
  leave it as Compiler-parity rather than switch to first-wins or add a
  `cbail('multiple control labels')`.

## Concerns

1. **`make` does not depend on the nqp stage jars.** A bare `make` after an nqp encoder
   change is a silent no-op (`elapsed=0s`), leaving `rakudo-j` built by the *old*
   encoder. I forced it with `make clean` + `make`. The next task (flipping Rakudo onto
   the unit road) must not trust a bare `make` either. I chose `make clean` over the
   controller's suggested `Configure.pl --gen-nqp` precisely because `--gen-nqp`
   re-bootstraps nqp *without* `NQP_UNIT=1` and would likely overwrite the unit-meta-only
   jars; `make clean` is `j-clean` and provably left them intact (re-verified after).
2. **Two of the brief's probes were unrunnable as written** — the four `nqp::with` probes
   (NQP objects have no `.defined`) and probe H (`will` trait placement). Neither traces
   to this task's code; both are covered by substitutes documented above. Flagging so the
   next brief does not inherit them.
3. Nothing observed traced to a shape outside the three this task owns. No fallback to
   bytecode occurred anywhere: the strict nqp build and the Rakudo build both report zero
   `code-bail` and zero `exit handler` lines.
