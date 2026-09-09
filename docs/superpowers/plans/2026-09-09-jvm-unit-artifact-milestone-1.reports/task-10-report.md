# Task 10 — Post-completion gate: Rakudo on the artifact nqp

**Status: BLOCKED.** Two independent blockers. Neither is a class-road
unit failing to reach an artifact unit's code refs or static lexicals —
the bilingual loader itself is not implicated.

Environment: rakudo worktree
`/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records`,
nested nqp at `57460ccd7` (branch `jesp-direct-lazy-records`), clean tree.
`java` = Oracle GraalVM 25.2.4+7.1 (25.0.4).

---

## Step 1 — `Configure.pl --backends=jvm --gen-nqp`

```
NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 \
  raku tools/build/watched-run.raku \
    --log=/home/longwalker/.claude/jobs/b945970f/tmp/configure-gate.log \
    --show='> Task :stage' --show='BUILD' --show='rror' --show='Makefile' \
    -- perl Configure.pl --backends=jvm --gen-nqp
```

```
=== EXIT=0 verdict=ok elapsed=3s ===
```

3 s, not ~5 min: Configure found the nested checkout's `nqp-j-gradle`
already built ("Using the nested nqp checkout's nqp-j-gradle … version
2026.08-352-g57460ccd7") and did not re-run gradle `buildJvm`. The jars
are the milestone-1 artifact build (all timestamped 13:35), so nqp stayed
on artifacts, which is what the step is for.

Artifact check — every share/lib jar is `unit.meta`-only:

```
unzip -l nqp/build/jvm/share/lib/nqp.jar | grep -c unit.meta   -> 1
  (same for QAST.jar, NQPCORE.setting.jar, NQPHLL.jar, QRegex.jar, ModuleLoader.jar)
```

`Makefile` exports `RAKUDO_RAKUAST=1`, `NQP_CODE_RUN=1`,
`NQP_CODE_PRECOMP=1` (lines 209/216/217) and **not** `NQP_UNIT` — Rakudo's
units take the class road, as the gate requires.

---

## Step 2 — `make`

### 2a. Plain `make` — FAILS

```
raku tools/build/watched-run.raku \
  --log=/home/longwalker/.claude/jobs/b945970f/tmp/rakudo-gate.log \
  --show='Compiling' --show='Generating' --show='rror' --show='Stage' \
  --stall=1500 -- make
```

```
[182s] +++ Compiling	rakudo.jar
Error: Could not find or load main class nqp
Caused by: java.lang.ClassNotFoundException: nqp
make: *** [Makefile:1292: rakudo.jar] Error 1
=== EXIT=2 verdict=ok elapsed=182s ===
```

Everything up to `rakudo.jar` built (blib/Perl6/*.jar, rakudo-runtime.jar
via gradle). The failing recipe is the first that uses `J_NQP_RR`.

**Root cause.** `Makefile:230` (generated from
`tools/templates/jvm/Makefile.in:31`):

```
@bpv(NQP_RR)@ = $(JAVA) -Xmx$(J_NQP_MAXHEAP) @j_truffle_args@ -cp @q(...)@ nqp
                                                                        ^^^^
```

It starts a JVM directly on main class `nqp`. That class only exists in a
class-road `nqp.jar`; an artifact `nqp.jar` holds `unit.meta` and no
`.class` at all. nqp's own runner template took the artifact entry point in
nqp `15c20930c` ("runners enter through UnitMain (either road)") —
`nqp/nqp-j-gradle` now ends

```
... org.raku.nqp.runtime.unit.UnitMain "<...>/nqp/build/jvm/share/lib/nqp.jar" "$@"
```

— but rakudo's `Makefile.in` was not updated with it. Everything else in
the build uses `J_NQP` (= `nqp/nqp-j-gradle`) and is unaffected; only
`J_NQP_RR` (rakudo.jar, BOOTSTRAP v6c/d/e) starts java by hand.

The entry point was verified directly:

```
java ... -cp <same cp> org.raku.nqp.runtime.unit.UnitMain <nqp.jar> -e 'say("UNITMAIN_OK")'
UNITMAIN_OK
```

**The one-line fix** (rakudo tree, NOT applied — outside this task's remit):
in `tools/templates/jvm/Makefile.in:31` replace the trailing main class
`nqp` with `org.raku.nqp.runtime.unit.UnitMain <absolute path to
nqp.jar>` (the same path the `@nqp_classpath@` expansion already knows).
Note the dead fallback at `Makefile:317-318` (`ifndef J_NQP_RR; J_NQP_RR =
$(J_NQP)`) shows the intended equivalence — but `J_NQP` alone is not a
drop-in, it caps the heap at `NQP_JVM_MAXHEAP` (4 g default) where
`J_NQP_RR` needs `-Xmx14G` for BOOTSTRAP/CORE.

### 2b. `make` with the entry point supplied on the command line — PASSES

To find out whether that one line was the only blocker, `make` was re-run
with `J_NQP_RR` overridden (a make variable on the command line; **no
source was edited**) to a stand-in identical to `Makefile:230` except for
the entry point: `/home/longwalker/.claude/jobs/b945970f/tmp/nqp-rr-unit.sh`.

```
raku tools/build/watched-run.raku \
  --log=/home/longwalker/.claude/jobs/b945970f/tmp/rakudo-gate2.log \
  --show='Compiling' --show='Generating' --show='rror' --show='Stage' \
  --stall=1500 -- make J_NQP_RR=/home/longwalker/.claude/jobs/b945970f/tmp/nqp-rr-unit.sh
```

```
=== EXIT=0 verdict=ok elapsed=981s ===
```

981 s incremental (it resumed at `rakudo.jar`); ≈1163 s from the top with
run 2a's 182 s. `rakudo-j` built. So the class road (Rakudo's units) does
compile end to end against artifact nqp units — BOOTSTRAP, CORE.c/d/e all
went through.

Per-target wall times (watched-run's elapsed prefixes):

| target | start | end | wall |
|---|---|---|---|
| rakudo.jar | 0 s | 4 s | 4 s |
| gen/jvm/BOOTSTRAP/v6c.nqp | 21 s | 28 s | 7 s |
| **blib/Perl6/BOOTSTRAP/v6c.jar** | 28 s | 367 s | **339 s** |
| **blib/CORE.c.setting.jar** | 367 s | 876 s | **509 s** |
| blib/Perl6/BOOTSTRAP/v6d.jar | 880 s | 884 s | 4 s |
| blib/CORE.d.setting.jar | 884 s | 906 s | 22 s |
| blib/Perl6/BOOTSTRAP/v6e.jar | 911 s | 914 s | 3 s |
| blib/CORE.e.setting.jar | 914 s | ~975 s | ~61 s |

Stage timings (the BOOTSTRAP v6c compile emits none — only the settings
run with `--stagestats`):

```
CORE.c   Stage start 0.001  parse 386.954  syntaxcheck 0.000  ast 0.000
         optimize 37.123    qast 31.327    jast 33.336
         classfile 2.942    jar 0.000
CORE.d   parse 8.611   optimize 1.025  qast 0.283  jast 0.934  classfile 0.101
CORE.e   parse 39.608  optimize 5.047  qast 3.904  jast 5.026  classfile 0.289
```

CORE.c parse 386.954 s sits inside the 370–389 s band the strict campaign
already recorded and accepted as compile-time cost (plan item 4).

---

## Step 3 — `t/01-sanity`

```
raku tools/build/watched-run.raku \
  --log=/home/longwalker/.claude/jobs/b945970f/tmp/sanity-gate.log \
  -t=t/01-sanity --jobs=2 \
  --log-dir=/home/longwalker/.claude/jobs/b945970f/tmp/sanity-gate-logs -- ./rakudo-j
```

```
21 of 25 ok in 147s, logs: /home/longwalker/.claude/jobs/b945970f/tmp/sanity-gate-logs
```

FAIL: `53-transpose.t`, `55-use-trace.t`, `56-use-isms.t`,
`99-test-basic.t` — the four files that `use` something. All four die with
the **identical** error, at the `use` line:

```
===SORRY!=== Error while compiling t/01-sanity/99-test-basic.t
java.lang.IllegalStateException: nqpp: unknown tag 11142 at 79 of 1060 words; program: 2 0 32 3 0 ... 
at t/01-sanity/99-test-basic.t:2
------> <BOL><HERE>use Test;
```

`-Ilib` makes no difference (checked): this is not the missing-module-repo
cascade, it is an engine program that will not decode.

### Diagnosis

**Not a road crossing.** No `lookupCodeRef(String)` failure, no missing
static lexical, no loader error. It is one CORE.c engine program whose
wire form the decoder rejects.

**Minimal reproducer** (no `use` needed):

```
./rakudo-j -e 'say("abc".subst(/b/,"x"))'      # dies, same program
./rakudo-j -e 'say("abc".subst("b","x"))'      # axc  — the Str matcher multi is fine
./rakudo-j -e 'my $s="abc"; $s ~~ s/b/x/; say $s'   # axc
```

So it is the `Str.subst(Regex …)` multi in CORE.c, reached by the module
loader on every `use`.

**Decoding the dump by hand** (`NqpWire.Program`: `code[0]` VERSION=2,
`code[1]` resultType=0, `code[2]` nlocals=32, `code[3]` needsFrame=3,
32 local types, `treeStart() = 4 + 32 = 36`):

| at | words | node |
|---|---|---|
| 36 | `1 4` | STMTS, 4 children |
| 38 | `17 0 -1 0` | **PARAMS: required 0, accepted -1, 0 params** |
| 42 | `1 19` | STMTS, 19 children |
| 44,45,46 | `21` ×3 | JNULL |
| 47 | `8 0 0` | LEXBIND `&?ROUTINE` … |
| 50 | `27 0 1 2 3 1 1` | CLASSLIB `Ops.getcodeobj`, 1 arg |
| 58 | `27 0 1 4 5 1 0` | CLASSLIB `Ops.curcode`, 0 args → ends at 65 |
| 65…78 | `21` ×14 | JNULL (declarations) |
| **79** | `11142 4 11143 0 11144 0 11145 0 19 0 …` | **no valid tag** |

The 19th child of the body block starts on a word that is not a tag. The
neighbourhood (`<n> 4`, `<n+1> 0`, `<n+2> 0`, `<n+3> 0`, then a valid
`19 0` = CODEREF) reads like an `(id, nargs)` sequence whose leading tags
were never written, i.e. an encoder-side layout bug, not a decoder gap.

**Whose bug.** Two fingerprints put it on the custom_args work, not on the
unit artifact:

1. The header is `PARAMS 0 -1 0` — literally what
   `docs/jvm-strict-campaign-handoff.md` says `patch_params` emits for a
   **custom_args block**: "an empty header (required 0, accepted -1, no
   params) for a custom_args block".
2. The program body contains wire tags 33 and 34 — `P6BINDSIG` /
   `P6TRYBINDSIG`, introduced by nqp `d13dcbf69` ("jesp/encoder+engine:
   custom_args blocks on the engine").

And the handoff doc's "The exact next step" is precisely *"Rakudo `make`
on the custom_args nqp (strict nqp build was green before the custom_args
commit; rerun it after), then `t/01-sanity`"* — that Rakudo-side
validation had never been run. This gate is the first Rakudo build on the
custom_args nqp, and it is what found the bug. Note the same 21/25 with
the same four files was recorded once before (a different cause,
un-hllized `NQPArray`, fixed in nqp `ca71c19cb`) — the `use`-ing files are
simply the ones that reach the most CORE.c code.

Milestone 1's only class-road-visible encoder change is nqp `57460ccd7`
(`QAST::VM` now encodes instead of bailing); it is a second, weaker
candidate and cannot be excluded without a rebuild, but it does not
explain the custom_args fingerprints above. `1517f9cec`'s encoder change
is gated on `:$unit_road` and cannot affect the class road at all.

### Suggested next step for whoever fixes it

Compare `TruffleEncoder.nqp`'s custom_args body emission against
`NqpProgramBuilder.walk`'s arity for whatever node type sits 19th in a
custom_args block body — the encoder writes operands without their tag
word. `NQP_CODE_WHY=1` on a small custom_args Raku routine compiled alone
should reproduce it in seconds without a CORE.c rebuild.

---

## Step 4 — docs + commit + push

`docs/jvm-truffle-only-plan.md`, Position table rows 5 and 6, records the
gate: the `J_NQP_RR` blocker with its verified fix, the v6c/CORE.c stage
timings, and the 21/25 with the custom_args attribution.

- rakudo commit `2133c15a5e` — *docs: unit artifact milestone 1
  post-completion gate -- Rakudo builds on the artifact nqp, t/01-sanity
  21/25*
- pushed: `git push ab5tract worktree-jesp-direct-lazy-records`
  → `8b055903b2..2133c15a5e`

No source was edited in either tree. `J_NQP_RR` was only overridden on the
`make` command line; the stand-in script lives outside the repos, in
`/home/longwalker/.claude/jobs/b945970f/tmp/nqp-rr-unit.sh`.

## Logs

- `/home/longwalker/.claude/jobs/b945970f/tmp/configure-gate.log`
- `/home/longwalker/.claude/jobs/b945970f/tmp/rakudo-gate.log` (plain make, EXIT=2)
- `/home/longwalker/.claude/jobs/b945970f/tmp/rakudo-gate2.log` (with the entry point, EXIT=0)
- `/home/longwalker/.claude/jobs/b945970f/tmp/sanity-gate.log` + `sanity-gate-logs/`
