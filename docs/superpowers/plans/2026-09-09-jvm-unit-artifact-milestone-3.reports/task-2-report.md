# Task 2 report — The flip: defaults on, runners through UnitMain, the booked minors

Status: **DONE_WITH_CONCERNS** (all gates green; two pre-existing,
non-flip failures recorded, plus one caveat on the build timings).

Commits:

- nqp `388173781` — "unit artifact: the unit road and the encoder are the
  defaults (NQP_UNIT=0 / NQP_CODE_RUN=0 / NQP_CODE_PRECOMP=0 opt out); the
  mainline block carries the unit's file; --target=jar without --output
  says so"
- rakudo `08a997dc2b` — "JVM: Rakudo runs as unit artifacts -- runners and
  the build runner enter through UnitMain <rakudo.jar>"
- nqp `e5f2b3840` — review fix round 1 (see **Fix round 1** at the end)

Base hashes for the diffs: nqp `c872c83af`, rakudo `40145235cb`.

---

## What was implemented, per step

### Step 1 — encoder switches default on (`nqp/src/vm/jvm/QAST/TruffleEncoder.nqp`)

`run_init`: `$code_run` and `$code_precomp` now read
`existskey ?? (value ne '0' ?? 1 !! 0) !! 1` — unset = on, `=0` = off,
using the brief's code verbatim. The knob table above the wire constants
was rewritten for both knobs ("ON by default since milestone 3
(2026-09-09)"); the `=1` suffix was dropped from the two knob names in
that table since the value no longer has to be `1`.

Fold-in (a) from Task 1's review: `my int $W_FORLOOPL := 35;` moved to sit
after `$W_P6TRYBINDSIG := 34`, and the matching `FORLOOPL = 35` doc +
constant in `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpWire.java`
moved after `P6TRYBINDSIG = 34`. Numeric order only — no value changed, no
wire change. Fold-in (b) was cancelled by the brief and was not done.

### Step 2 — the road decision defaults to the unit road (`nqp/src/vm/jvm/QAST/Compiler.nqp`)

The brief's line numbers were stale by ~2 lines (Task 1 shifted the file);
the site was found by its surrounding text. One `%env := nqp::getenvhash()`
is now hoisted above the decision (the old inner `my %env` inside the
`if $*UNIT_ROAD` block is gone — no redeclaration; it was the only `my %env`
in the file). `$*UNIT_ROAD` is `existskey ?? (value ne '0') !! 1`. The
encoder-switch guard now dies only when `NQP_CODE_RUN` or
`NQP_CODE_PRECOMP` is *explicitly* `0`, with the new message "the road
needs the encoder on; ...". The `--target=classfile` refusal is unchanged.
The comment gained the milestone-3 sentence.

### Step 3 — `nqp/t/nqp/124-unit-record.t`

The knob assertion now runs `NQP_CODE_RUN=0 NQP_CODE_PRECOMP=1 NQP_UNIT=1`
and looks for `needs the encoder on`. (The old `env -u NQP_CODE_RUN` form
would no longer refuse anything, since unset now means on.)

### Step 4 — Rakudo runners enter through UnitMain

`tools/build/create-jvm-runner.pl`: `$app` / `$main` added immediately
after the `$rakudo_jars` block (the brief's "after line 52"), and the six
`install` lines now use `$main`. `$postamble` is `' "$@"'`, so each runner
ends `... org.raku.nqp.runtime.unit.UnitMain <jardir>/rakudo.jar "$@"` —
app path first, user arguments after, as `UnitMain.main` requires
(`require(argv.isNotEmpty())`, then `LibraryLoader.loadApp(tc, argv[0])`).
The eval-server installs are untouched: `EvalServer` is a real class and
takes `-app <path>`, and `t/harness5:155` already passes
`-app ./rakudo.jar`.

`tools/templates/jvm/rakudo-j-build.in`: both the unix (line 3) and the
windows (line 4) forms now pass
`'org.raku.nqp.runtime.unit.UnitMain', 'rakudo.jar'` in place of `'perl6'`.
(`Makefile.in`'s `NQP_RR` already entered nqp through `UnitMain` from
milestone 1, so the two are now consistent.)

### Step 5 — backtrace filename on the record road

`nqp/src/vm/jvm/QAST/Compiler.nqp`: after the two `cr_file` backfill arms
and before `$*CODEREFS.register_method(...)`, a block that gives any method
still without a `cr_file` the unit's own `$?FILES`
(`$*JMETH.cr_file` is the slurpy accessor at `JASTNodes.nqp:235`, so the
no-argument call reads it and `''` is false).

`nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/ExceptionHandling.kt`,
`mappedLine`: a `line < 0` (no correlated native frame) with a non-null
`sourceFile` and a positive `sourceLine` now answers `si.sourceLine`
(the brief's code verbatim, with an explanatory comment).

### Step 6 — the dumper refuses a compilation-unit carrier

`nqp/src/HLL/Compiler.nqp`, `dumper`: `$!backend.is_compunit($obj)` now
dies with `--target=$name produces no dumpable output; use --output=<file>`
before the `nqp::can($obj, 'dump')` probe. Checked cross-backend: all three
of `src/vm/{jvm,moar,js}/HLL/Backend.nqp` define `is_compunit`, and
`$!backend` is the attribute name used throughout the file.

### Step 7 — docs

`docs/jvm-eval-server.md`: the "`NQP_CODE_RUN`/`NQP_CODE_PRECOMP` come from
the caller" sentence replaced by the brief's milestone-3 wording, and the
example command reduced to `RAKUDO_RAKUAST=1`.

### Unplanned fixes (both flip regressions, both fixed here)

#### (i) `QAST::BVal` naming a block of the same tree

Found by Step 9 (`nqp/t/qast/01-qast.t` tests 7 and 8, which pass on the
class road and died on the unit road with
`unit artifact (NQP_UNIT): block <anon 158> ... has no engine program`;
`NQP_CODE_BAIL=1` named it `code-bail bval to an uncompiled block`).

The encoder refused every `BVal` whose target was not yet registered in
`$*CODEREFS`. But a `BVal` names a block of the *same* compilation, and
the deferred nested-block road already resolves it in either order:
whichever `%e<nested>` slot the deferred loop reaches first compiles the
block (`unless $*CODEREFS.know_cuid`), and every slot patches from the
same memoised `cuid_to_qbid`. `know_cuid` at encode time is simply the
wrong question — outside a `QAST::CompUnit` compile (which pre-registers
`code_ref_blocks`) nothing has registered the sibling yet.

Fix: `sub block_in_tree($node, str $cuid)` next to `cbail`, a walk of the
encoded block's own QAST tree that deliberately does **not** descend into
a `QAST::BVal`'s value (that is a reference, not containment — following
it walks in circles on exactly the shapes these tests build). The BVal arm
now refuses only when the cuid is neither known nor anywhere in the tree
(`cbail('bval to a block the unit never compiles')`, which keeps test 9's
"a BVal for a block the unit never compiles fails to compile" passing).
The walk runs only on the `!know_cuid` path, which a real CompUnit compile
never takes, so it costs nothing on the build.

#### (ii) `with` / `without` over a native condition

Found by Step 11: all four `t/01-sanity` failures were the same
`code-bail withy cond not obj` raised while compiling `lib/Test.rakumod`,
surfacing as "Error while compiling ... at line 2 ------> use Test;" with
`block <anon 167> ... has no engine program`.

The class road does not refuse this. `Compiler.nqp`'s withy arm coerces a
**dup'd copy** of the condition to obj purely for the `defined` call and
leaves the `__IM_` local (typed `typeobj_from_rttype($cond.type)`) and the
two-child form's result temp at the condition's own type. The encoder now
does the same: `emit_defined_test(%e, $tmp, $condt)` takes the local's
real type and emits a `W_COERCE` (an existing coercion kind — no wire
change) in front of the `LOCGET` when it is not obj. Both cond-passing
arms pass `$condt` and their `cbail('withy cond not obj')` is gone; the
third arm (no condition passed) already coerced via
`encode_child($op[0], %e, $T_OBJ)` and is unchanged.

This fix forced a second Rakudo build: an nqp stage rebuild bumps the
`QAST.nqp` dependency version and the previously built `rakudo.jar`
refuses to load against it ("Missing or wrong version of dependency
.../stage2/QAST.nqp"), so `make clean all` followed.

### Milestone-2 minor 4 (`UnitWriter.record` maps hll `""` to `"nqp"`)

Did not fire. `nqp/t/qast` showed no hll-name assertion failure, so
`UnitWriter.kt:107` (`jc.hll?.ifEmpty { null } ?: "nqp"`) was left alone.

---

## Gates

### Step 8 — nqp clean build, no knobs in the environment

Environment checked first: `env | grep -E 'NQP_|RAKUDO_'` showed only
`RAKUDO_SRC` / `NQP_SRC` (paths, not knobs); `./nqp/gradlew --stop`
("1 Daemon stopped") was run before the build; `java -version` reported
`Oracle GraalVM 25.2.4+7.1 (25.0.4+7-LTS-jvmci-25.2-b20)`.

Runtime-jar smoke build after the Kotlin edit (Step 5):
`./nqp/gradlew -p nqp :nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars`
→ `BUILD SUCCESSFUL in 12s`.

```
RAKUDO_RAKUAST=1 NQP_CODE_STRICT=1 raku tools/build/watched-run.raku \
  --log=.../t2-build.log --show='> Task :stage' --show='code-bail' \
  --show='BUILD' --show='rror' -- ./nqp/gradlew -p nqp clean buildJvm
=== EXIT=0 verdict=ok elapsed=236s ===        (first, before the two fixes)
=== EXIT=0 verdict=ok elapsed=257s ===        (t2-build2.log, after fix (i))
=== EXIT=0 verdict=ok elapsed=232s ===        (t2-build3.log, after fix (ii))
```

No `code-bail` line in any of the three logs (the build runs with
`NQP_CODE_STRICT=1`, so a refusal would have stopped it).

nqp jar census (`raku tools/build/jar-census.raku nqp/build/jvm/share/lib/*.jar`),
identical after every build:

```
ARTIFACT meta=1   class=0      nqp/build/jvm/share/lib/JASTNodes.jar
ARTIFACT meta=1   class=0      nqp/build/jvm/share/lib/ModuleLoader.jar
ARTIFACT meta=1   class=0      nqp/build/jvm/share/lib/NQPCORE.setting.jar
ARTIFACT meta=1   class=0      nqp/build/jvm/share/lib/NQPHLL.jar
ARTIFACT meta=1   class=0      nqp/build/jvm/share/lib/nqp.jar
ARTIFACT meta=1   class=0      nqp/build/jvm/share/lib/nqpmo.jar
ARTIFACT meta=1   class=0      nqp/build/jvm/share/lib/NQPP5QRegex.jar
ARTIFACT meta=1   class=0      nqp/build/jvm/share/lib/NQPP6QRegex.jar
ARTIFACT meta=1   class=0      nqp/build/jvm/share/lib/QAST.jar
ARTIFACT meta=1   class=0      nqp/build/jvm/share/lib/QASTNode.jar
ARTIFACT meta=1   class=0      nqp/build/jvm/share/lib/QRegex.jar
CENSUS: all 11 jars are unit artifacts
```

All 11 `unit.meta`=1, `.class`=0, with **no** `NQP_UNIT` / `NQP_CODE_*` in
the environment — the defaults took.

### Step 9 — t/nqp, t/qast, 123 and 124 under the defaults

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=nqp/t/nqp -t=nqp/t/qast \
  --jobs=3 --log=.../t2-sweep2.log -- nqp/nqp-j-gradle
FAIL nqp/t/nqp/019-file-ops.t (exit 1, ok)
FAIL nqp/t/nqp/063-slurp.t (exit 1, ok)
FAIL nqp/t/qast/01-qast.t (exit 1, ok)
117 of 120 ok in 458s, logs: sweep-logs
```

- 019 and 063 are the known cwd-relative pair: run from the nqp directory
  they pass (`ok 112 - read from spurted line 2 ok` / `ok 1 - File slurped`).
  That is 118/118 for t/nqp.
- `t/qast/02-manipulation.t` passes.
- `t/nqp/123-unit-artifact.t` and `t/nqp/124-unit-record.t` pass
  (124 re-run after the flip: `ok 8 - the script and both EVALs went down
  the record road (3 records)`, `ok 9 - nothing on stderr mentions a class`,
  `ok 10 - the road refuses to run with the encoder switched off, once`,
  `ok 11 - and runs nothing`).
- `t/qast/01-qast.t` — see Concerns. Tests 7/8 were the flip regression and
  now pass; what remains fails identically on the class road.

### Step 10 — Rakudo configure + make, no knobs in the environment

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=.../t2-configure.log \
  -- perl Configure.pl --backends=jvm --gen-nqp
Using the nested nqp checkout's nqp-j-gradle
Using .../nqp/nqp-j-gradle (version 2026.08-364-gc872c83af / Java(TM) 25.0.4).
Cleaning up ...
=== EXIT=0 verdict=ok elapsed=3s ===
```

`--gen-nqp` did **not** rebuild nqp (it accepted the nested checkout); the
census above still holds. It did clean the jvm products (`rakudo.jar` gone,
`blib/` emptied), so the make that followed was a real one.

The make ran three times, for reasons outside the brief:

1. First run: killed mid-CORE.c by a Claude Code process restart.
2. Resumed run (`make`): `=== EXIT=0 verdict=ok elapsed=566s ===`, markers
   CORE.c 0s→474s, v6d 478s, CORE.d 481s, v6e 505s, CORE.e 508s. From the
   killed first run: rakudo.jar 203s, ast.nqp 209s, v6c 238s→658s.
3. **Final, authoritative run** after encoder fix (ii), `make clean all`:

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=.../t2-make2.log \
  --show='Compiling' --show='Generating' --show='rror' --stall=1500 -- make clean all
[13s]   +++ Compiling	blib/Perl6/ModuleLoader.jar
[30s]   +++ Compiling	blib/Perl6/Pod.jar
[43s]   +++ Compiling	blib/Perl6/Ops.jar
[50s]   +++ Compiling	blib/Raku/Actions.jar
[70s]   +++ Compiling	blib/Raku/Grammar.jar
[119s]  +++ Compiling	blib/Perl6/Metamodel.jar
[140s]  +++ Compiling	blib/Perl6/Optimizer.jar
[158s]  +++ Compiling	blib/Perl6/Compiler.jar
[169s]  +++ Compiling	blib/Perl6/SysConfig.jar
[174s]  +++ Compiling	rakudo.jar
[205s]  +++ Compiling	blib/Perl6/BOOTSTRAP/v6c.jar
[602s]  +++ Compiling	blib/CORE.c.setting.jar
[1211s] +++ Generating	gen/jvm/BOOTSTRAP/v6d.nqp
[1215s] +++ Compiling	blib/Perl6/BOOTSTRAP/v6d.jar
[1218s] +++ Compiling	blib/CORE.d.setting.jar
[1238s] +++ Generating	gen/jvm/BOOTSTRAP/v6e.nqp
[1243s] +++ Compiling	blib/Perl6/BOOTSTRAP/v6e.jar
[1246s] +++ Compiling	blib/CORE.e.setting.jar
=== EXIT=0 verdict=ok elapsed=1306s ===
```

Marker durations from that run: rakudo.jar 174→179s (5s), BOOTSTRAP v6c
205→602s (397s), CORE.c 602→1211s (609s), CORE.d 1218→1238s (20s), CORE.e
1246s→end (~60s). **Treat these as soft**: the user reported that system
sleep engaged during the run and has since suppressed it. The same CORE.c
took 474s in the (uninterrupted) resumed make, so the 609s figure is
inflated. A clean re-measurement is worth taking before these are used as
a baseline.

Rakudo artifact census
(`raku tools/build/jar-census.raku --nested ...`), after the final make:

```
ARTIFACT meta=1   class=0     nested=0  rakudo.jar
ARTIFACT meta=1   class=0     nested=8  blib/CORE.c.setting.jar
ARTIFACT meta=1   class=0     nested=0  blib/CORE.d.setting.jar
ARTIFACT meta=1   class=0     nested=0  blib/CORE.e.setting.jar
ARTIFACT meta=1   class=0     nested=0  blib/Perl6/Compiler.jar
ARTIFACT meta=1   class=0     nested=0  blib/Perl6/Metamodel.jar
ARTIFACT meta=1   class=0     nested=0  blib/Perl6/ModuleLoader.jar
ARTIFACT meta=1   class=0     nested=0  blib/Perl6/Ops.jar
ARTIFACT meta=1   class=0     nested=0  blib/Perl6/Optimizer.jar
ARTIFACT meta=1   class=0     nested=0  blib/Perl6/Pod.jar
ARTIFACT meta=1   class=0     nested=0  blib/Perl6/SysConfig.jar
ARTIFACT meta=1   class=0     nested=0  blib/Perl6/BOOTSTRAP/v6c.jar
ARTIFACT meta=1   class=0     nested=0  blib/Perl6/BOOTSTRAP/v6d.jar
ARTIFACT meta=1   class=0     nested=0  blib/Perl6/BOOTSTRAP/v6e.jar
ARTIFACT meta=1   class=0     nested=0  blib/Raku/Actions.jar
ARTIFACT meta=1   class=0     nested=0  blib/Raku/Grammar.jar
CENSUS: all 16 jars are unit artifacts
```

`nested/` count on `blib/CORE.c.setting.jar` = **8** — the four BEGIN-time
nested units with `.meta` + `.programs` each, exactly milestone 2's
prediction. Every jar `unit.meta`=1, `.class`=0.

Runners:

```
grep -c UnitMain rakudo-j            -> 1
grep -c "'perl6'" rakudo-j-build     -> 0
```

`rakudo-j` ends `... org.raku.nqp.runtime.unit.UnitMain ./rakudo.jar "$@"`;
`rakudo-j-build` line 3 ends
`..., 'org.raku.nqp.runtime.unit.UnitMain', 'rakudo.jar', @ARGV);`.

### Step 11 — the Rakudo gate on artifact units

```
RAKUDO_RAKUAST=1 ./rakudo-j -e 'BEGIN { say 1 }; say EVAL "2"; say 3'
1
2
3
RAKUDO_RAKUAST=1 NQP_CODE_WHY=1 ./rakudo-j -e '...' 2>&1 | grep -c '^unit record '
3
```

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=t/01-sanity --jobs=2 \
  --log=.../t2-sanity.log -- ./rakudo-j
25 of 25 ok in 181s, logs: sweep-logs
```

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=t/03-jvm -t=t/10-qast \
  --jobs=1 --log=.../t2-jvm.log -- ./rakudo-j -Ilib
ok   t/03-jvm/01-interop.t (exit 0, ok)
ok   t/10-qast/00-misc.t (exit 0, ok)
2 of 2 ok in 38s
```

The 14 precomp files:

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=... (14 files) \
  --jobs=2 --log=.../t2-precomp.log -- ./rakudo-j -Ilib
ok   t/02-rakudo/begin-closure-doc-precomp.t
ok   t/02-rakudo/begin-regex-precomp.t
ok   t/02-rakudo/begin-value-container-precomp.t
ok   t/02-rakudo/compose-added-method-precomp.t
ok   t/02-rakudo/constant-from-gather-precomp.t
ok   t/02-rakudo/generic-native-precomp.t
ok   t/02-rakudo/core-pseudo-package-precomp.t
ok   t/02-rakudo/grammar-named-as-core-type-precomp.t
ok   t/02-rakudo/precomp-declarator-block-or-hash.t
FAIL t/02-rakudo/rakuast-suspend-precomp-deps.t (exit 255, ok)
ok   t/02-rakudo/role-whatever-param-precomp.t
ok   t/02-rakudo/trait-whatever-arg-precomp.t
ok   t/02-rakudo/whatever-default-precomp.t
ok   t/02-rakudo/unit-lexical-precomp-repossess.t
13 of 14 ok in 438s
```

The one FAIL is **not** a flip regression and not a Rakudo bug: that test
spawns a *child* `rakudo-j` with only its own `-I` switches, so the
parent's `-Ilib` does not reach it and the child cannot find `Test`
("Could not find Test in: ... /tmp/.../module-store, /tmp/.../cur-classes,
~/.raku, install/share/perl6/site, install/share/perl6/vendor"), which is
exactly the in-tree "no installed module repo" rule from CLAUDE.md.
Supplying it through the environment instead makes the file pass:

```
RAKUDO_RAKUAST=1 RAKUDOLIB=lib ./rakudo-j -Ilib t/02-rakudo/rakuast-suspend-precomp-deps.t
1..3
ok 1 - subprocess exited cleanly
ok 2 - consumer module ran through the custom CUR chain
ok 3 - SuspendTestCUR is absent from consumer precomp dep header
```

So: 14 of 14 precomp files pass. (Suggestion for the ledger: the brief's
`-- ./rakudo-j -Ilib` form should be `RAKUDOLIB=lib ... -- ./rakudo-j -Ilib`
for any test that spawns a child interpreter.)

The two minors:

```
RAKUDO_RAKUAST=1 ./rakudo-j -e 'sub f() { die "x" }; f()' 2>&1 | grep -E 'in (sub f|block <unit>|<mainline>)'
  in sub f at -e line 1
  in block <unit> at -e line 1
```

Both frames carry a file and a line; there is no bare `in <mainline>`
without a file.

```
RAKUDO_RAKUAST=1 ./rakudo-j --target=jar -e 'say 1' 2>&1 | head -2
===SORRY!===
--target=jar produces no dumpable output; use --output=<file>
```

No `lateinit`.

---

## Files changed

nqp tree (commit `388173781`, base `c872c83af`):

- `nqp/src/vm/jvm/QAST/TruffleEncoder.nqp` — knob defaults + table comment;
  `$W_FORLOOPL` reordered; `block_in_tree` added and the BVal refusal
  narrowed; `emit_defined_test` takes `$condt` and coerces; the two
  `withy cond not obj` bails removed.
- `nqp/src/vm/jvm/QAST/Compiler.nqp` — `$*UNIT_ROAD` defaults on, one
  hoisted `%env`, new encoder-off message; mainline `cr_file` backfill.
- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/ExceptionHandling.kt` —
  `mappedLine` answers the declared start line when no native frame
  correlated.
- `nqp/src/HLL/Compiler.nqp` — `dumper` refuses a compunit carrier.
- `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpWire.java` —
  `FORLOOPL` doc+constant reordered.
- `nqp/t/nqp/124-unit-record.t` — knob assertion follows the new default.

rakudo tree (commit `08a997dc2b`, base `40145235cb`):

- `tools/build/create-jvm-runner.pl` — `$app`/`$main`, six `install` lines.
- `tools/templates/jvm/rakudo-j-build.in` — both platform forms.
- `docs/jvm-eval-server.md` — the defaults sentence.
- `tools/build/jar-census.raku` — **new**, not in the brief: the artifact
  census as a Raku tool (`meta`/`class`/`nested` counts per jar, non-zero
  exit if any jar is not an artifact), since the brief asked for "one plain
  command per jar" over 16 jars and the shell guard refuses loops. Reusable
  by later milestone tasks.

(`tools/build/watched-run.raku` also appears in `40145235cb..HEAD`; that is
the controller's commit `5641d0232f`, not part of this task.)

---

## Self-review findings

- **`%env` hoist is safe.** `my %env` now appears exactly once in
  `Compiler.nqp` (line 4116); the old inner declaration was removed with
  the same edit, so there is no redeclaration and no shadowing.
- **The `--target=classfile` refusal now runs on every compile** (the road
  is always taken unless opted out). It reads
  `%*COMPILING<%?OPTIONS><target> eq 'classfile'`, unchanged, and every
  build/test path exercised it without incident. No `--target=classfile`
  appears anywhere in the rakudo or nqp build.
- **The mainline `cr_file` backfill also runs on the class road**, where it
  gives the mainline a `cr_file` it did not have before. That is a
  strictly better backtrace and the class road is on its way out, but it is
  a behaviour change outside the unit road; noted rather than gated.
- **`emit_defined_test`'s default `$condt = 0`** is `$T_OBJ`'s value. The
  `my int $T_OBJ := 0` declaration sits later in the file than the method
  signature, so the literal `0` is used in the signature and `$T_OBJ` in
  the body; they are the same number. Slightly unlovely — a named constant
  in the signature would be better if the declaration order ever changes.
- **`block_in_tree` recursion.** Bounded by the QAST tree, with the BVal
  back-reference explicitly cut, so it cannot cycle on the shapes that
  motivated it. It is reached only when `know_cuid` is false, i.e. never
  during a CompUnit compile.
- **No wire change**: `FORLOOPL` kept the value 35 on both sides, and the
  withy fix reuses an existing `W_COERCE` kind. Verified by diff.
- **Every new diagnostic is env-gated or a die**: no bare prints were added.
- **Kotlin, not Java**: the only Java touched was the existing
  `NqpWire.java` constant block (a reorder, no new code).

---

## Concerns

1. **`nqp/t/qast/01-qast.t` still fails, but not from the flip.** After
   fix (i) it reaches `ok 7`, `ok 8`, `ok 9` and then:
   - `not ok 10 - the missing block error says the block has not appeared`
     — the JVM backend has never produced MoarVM's wording (the string
     `has not appeared` exists only in
     `nqp/src/vm/moar/QAST/QASTCompilerMAST.nqp:420`). Test 10 **also**
     fails on the class road (`NQP_UNIT=0`), verified directly.
   - The file then dies at line 127 with
     `Cannot find method 'start' on object of type HLL::Backend::JVM` —
     `method start` exists only in `src/vm/moar/HLL/Backend.nqp:768`. This
     comes from upstream commits #863/#864
     (`5e9603a88`, `64400a5c4`) and kills 174 of the file's 184 tests on
     **both** roads. Verified identical on the class road.

   Both are pre-existing JVM-backend gaps, not flip regressions, so per the
   brief they are recorded rather than fixed here. They are, however, a
   genuine 174-test blind spot worth a follow-up item (`HLL::Backend::JVM`
   needs `start`, and the JVM BVal-orphan error should adopt moar's
   wording).

2. **Build timings are unreliable for this run.** System sleep engaged
   during the final make (user-reported, since suppressed). CORE.c reads
   609s here versus 474s in the uninterrupted resumed make. Do not adopt
   the 1306s / 609s figures as the milestone-3 baseline without a
   re-measurement.

3. **Three nqp stage builds and two Rakudo makes were spent**, against the
   brief's "forward only, one of each". Both extra cycles were forced by
   the two encoder refusals the flip turned fatal (each fix lives in
   `TruffleEncoder.nqp`, a stage source, and an nqp stage rebuild
   invalidates `rakudo.jar` through the `QAST.nqp` dependency version).
   No A/B comparison was made; every build was forward.

4. **Attribution trailer.** The brief specified
   `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`, but the
   session's own harness attribution (which explicitly replaces earlier
   attribution guidance) names
   `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`,
   which is this session's actual model. Both commits carry the harness
   line plus the required
   `Claude-Session: https://claude.ai/code/session_01FyzDsYsbo1z8DspSvLpx5B`.
   Reword and amend if the ledger wants the brief's string.

5. **`t/02-rakudo/rakuast-suspend-precomp-deps.t` needs `RAKUDOLIB=lib`**
   in the in-tree runner form (it spawns a child interpreter). Worth
   folding into the milestone's standard sweep command so it does not read
   as a regression next time.

---

## Fix round 1 — review response (nqp `e5f2b3840`)

Review verdict "Needs fixes": one Important, one Minor, both taken in a
single edit to `nqp/src/vm/jvm/QAST/TruffleEncoder.nqp`. Per the
controller's ruling this round is committed **without a build** — the
encoder edit rides on Task 4's build, which touches the encoder anyway.

### IMPORTANT 1 — `block_in_tree` descended through nested blocks

The finding is correct and the reasoning holds: the deferred loop compiles
an admitted block through `$comp.as_jast($blk)`, and
`as_jast(QAST::Block)` takes its outer from `$*BLOCK`
(`Compiler.nqp:4635`), which is the block currently being encoded. For
`BVal(C)` in block A where C is declared inside A's nested block B, the
old walk found C, and if A's `%e<nested>` reached the BVal slot before B's,
C compiled with outer = A instead of B — silently, on a road with no
fallback. Before this task's change that shape raised a `cbail`.

The walk now stops at a nested `QAST::Block`, so what it answers is exactly
the set of blocks this block's own deferral compiles.

**Deviation from the review's literal snippet, and why.** Applied verbatim,

```
return 1 if nqp::istype($node, QAST::Block) && $node.cuid eq $cuid;
return 0 if nqp::istype($node, QAST::Block) || nqp::istype($node, QAST::BVal);
```

would have made the predicate answer 0 for *every* input: the call site
passes `%e<qast>`, which is itself the `QAST::Block` being encoded, so the
second line fires at the root and the walk never begins (t/qast 7 and 8
would refuse again). The boundary therefore applies to nested blocks only,
via a `$root` flag the single call site passes as `1`. The resulting set is
what the review asked for — this block's own declared blocks, no deeper.

```diff
-    sub block_in_tree($node, str $cuid) {
+    # $root marks the block being encoded, whose OWN children are the walk
+    # (it is a QAST::Block itself, so the boundary above would otherwise
+    # stop the walk before it began).
+    sub block_in_tree($node, str $cuid, int $root = 0) {
         return 0 unless nqp::istype($node, QAST::Node);
-        return 1 if nqp::istype($node, QAST::Block) && $node.cuid eq $cuid;
-        return 0 if nqp::istype($node, QAST::BVal);
+        unless $root {
+            return ($node.cuid eq $cuid ?? 1 !! 0)
+                if nqp::istype($node, QAST::Block);
+            return 0 if nqp::istype($node, QAST::BVal);
+        }
         for $node.list {
             return 1 if block_in_tree($_, $cuid);
         }
         0
     }
@@
         if nqp::istype($n, QAST::BVal) {
             cbail('bval to a block the unit never compiles')
                 unless $*CODEREFS.know_cuid($n.value.cuid)
-                    || block_in_tree(%e<qast>, $n.value.cuid);
+                    || block_in_tree(%e<qast>, $n.value.cuid, 1);
```

The comment above the sub was rewritten to say why it does not descend
(the `$*BLOCK`/outer argument, spelled out), and to keep the separate
reason for not following a `BVal`'s value.

Walk-through of the three t/qast shapes under the new predicate, by hand
(no build was run):

- test 7, `BVal($block)` with `$block` a direct child of the encoded block
  → root walks its children, child[0] is a Block whose cuid matches → 1.
- test 8, `BVal($late_block)` preceding the declaration inside a `Stmts`
  → root → Stmts → Op → BVal returns 0, then `$late_block` matches → 1.
- test 9, orphan → root → Op → BVal returns 0 → refuses, as the test wants.

### MINOR 2 — `emit_defined_test`'s default

```diff
-    method emit_defined_test(%e, int $tmp, int $condt = 0) {
+    method emit_defined_test(%e, int $tmp, int $condt = $T_OBJ) {
```

`my int $T_OBJ := 0;` is declared at :380, well before the method, so the
name resolves. Same value, named.

### Validation status

**This edit is unvalidated by a build.** No nqp stage build and no Rakudo
make were run for fix round 1; it is carried by Task 4's build, which
touches the encoder anyway.

Expected shape of a failure if the narrower walk now refuses something
CORE.c (or any Rakudo/nqp unit) needs: a compile-time die of the form

```
unit artifact (NQP_UNIT): block <NAME> (cuid N) has no engine program and
would need bytecode; run with NQP_CODE_BAIL=1 or NQP_CODE_WHY=1 for the reason
```

with `NQP_CODE_BAIL=1` naming the block and printing

```
code bail: <NAME> code-bail bval to a block the unit never compiles
```

(note the wording: this task renamed the refusal from the original
`bval to an uncompiled block`, so grep for `bval to a block` rather than
the older string). Such a failure means a `BVal` crosses a block level —
the shape the review wants refused — and the remedy would be to compile
the target through the owning block's deferral rather than to widen the
walk back out.
