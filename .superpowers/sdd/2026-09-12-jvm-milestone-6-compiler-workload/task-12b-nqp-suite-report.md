# Task 12b — the nqp test suite through a GraalVM Native Image

**Status: COMPLETE.** All 151 `testNqp` files ran through a Native Image of
the nqp runtime. **The image reproduces the JVM's nine known reds exactly —
same files, same individual test numbers — and adds three new red files, all
three of them missing-metadata failures rather than wrong answers.** Total
wall clock 648 s against the 599 s JVM baseline (+8 %), for roughly a quarter
to a fifth of the CPU.

No source file was changed in either tree. No image was rebuilt or deleted.
No build script was touched. `blib/` and `nqp/build/` are byte-for-byte as
found (`nqp.jar` still stamped 2026-09-12 12:09, `blib/CORE.c.setting.jar`
12:28); `git status --porcelain --ignore-submodules=all` in both trees shows
only the untracked files that predate this task, and the nqp tree is clean.

- rakudo HEAD at start: `28cc3ea11b` (worktree `jesp-direct-lazy-records`)
- nqp HEAD: unchanged, working tree clean

---

## 1. The invocation

The other agent was right that the tree's harness hardcodes a `java` command
line, so nothing in the tree was adapted. Instead a **three-line shim under
`$CLAUDE_JOB_DIR/tmp` impersonates `nqp/nqp-j-gradle`** and is handed to
`prove --exec`. `prove` is a stock external TAP runner, not the tree's
harness; `nqp-j-gradle` and `build.gradle.kts` were not read into the run and
not modified.

`$CLAUDE_JOB_DIR/tmp/t12b/nqp-image-j`:

```sh
#!/bin/sh
# Task 12b shim: impersonates nqp/nqp-j-gradle but runs a GraalVM Native Image.
LIB=/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp/build/jvm/share/lib
IMG=${T12B_IMAGE:-/home/longwalker/.claude/jobs/804818e2/tmp/rakudo-image}
exec "$IMG" -Xmx4g -Dnqp.execname="$0" -Djava.class.path="$LIB" "$LIB/nqp.jar" "$@"
```

So the single-line form is

```
<image> -Xmx4g -Dnqp.execname=<self> -Djava.class.path=<share/lib> <share/lib>/nqp.jar <test file>
```

— exactly the shape the brief predicted from the Rakudo run: `-D` system
properties, `java.class.path` so `UnitLoader` can find `ModuleLoader.jar`,
then the unit jar as argv[0] of the program, then the program's own arguments.

Two flags from `nqp-j-gradle` were deliberately dropped and neither was
needed: `-Xss64m` (no image equivalent is required — nothing in the suite,
including `t/qregex/01-qregex.t` with its deep grammar recursion, overflowed
the image's main stack) and the module-path/`--add-modules` block (the image
has Truffle compiled in).

The whole set was then driven by

```
cd nqp && prove -r --timer --exec $CLAUDE_JOB_DIR/tmp/t12b/nqp-image-j \
  t/nqp t/hll t/qregex t/p5regex t/qast t/jvm t/serialization t/nativecall
```

under `raku tools/build/watched-run.raku --log=$CLAUDE_JOB_DIR/tmp/t12b/suite.log`.
That directory list is `registerProveTask("testNqp", …)` from
`nqp/build.gradle.kts:368` copied verbatim, and it yields 151 files — the same
151 as the baseline.

## 2. Which image, and why

Three of the four images were tried. **Only `rakudo-image` can run the suite.**

| image | size | result |
|---|---|---|
| `nqp-image` | 28 MB | **cannot start.** `IllegalStateException: No language and polyglot implementation was found on the module-path.` |
| `nqp-image-opt` | 67 MB | **dies during the first parse**, see below |
| `rakudo-image` | 77 MB | **runs everything** — used for this task |

`nqp-image` is the product of `build-image-mod.sh` (Truffle on the *module*
path). Task 12's report already names this: on the module path no Truffle
feature registers. It is dead on arrival and was not pursued.

`nqp-image-opt` starts, boots the engine and begins parsing, then fails on the
first `nqp::exception`:

```
Unhandled exception: org.graalvm.nativeimage.MissingReflectionRegistrationError:
Cannot reflectively invoke method 'public static final org.raku.nqp.sixmodel.SixModelObject
org.raku.nqp.runtime.Ops.exception(org.raku.nqp.runtime.ThreadContext)'.
  in <anon> (…/nqp/build/jvm/stage2/NQPHLL.nqp)
```

`nqp -e 'say(1+1)'` is enough to trigger it. The cause is in the metadata, not
the image recipe: `config7/reachability-metadata.json` (used by both
`nqp-image` and `nqp-image-opt`) registers `org.raku.nqp.runtime.Ops` as an
**enumerated method list** — whatever the tracing agent happened to observe —
while `config-rakudo2/reachability-metadata.json` (used by `rakudo-image`)
registers 722 types with `allDeclaredMethods: true`.

**This is a structural finding, not an accident of one build.** Classlib ops
are resolved by *name* at run time (`NqpOps.classlib` → `MethodHandle`), so
the op surface is open-world reflection. A tracing agent can only ever record
the ops the traced workload executed; any op the suite reaches and the trace
missed is a hard failure. The whole op surface has to be registered, which is
what `config-rakudo2` does and what a build step should emit mechanically.

`rakudo-image` is `build-image-rakudo.sh`: the same nqp runtime, the same
Truffle-on-the-class-path recipe, plus `rakudo-runtime.jar` on the image class
path and the full-surface metadata. The extra Rakudo runtime is inert when
running `nqp.jar`. So the comparison below is an honest test of the *nqp*
runtime in an image; only its metadata differs from `nqp-image-opt`.

Per the brief's framing and task 12's own diagnosis, **guest compilation bails
100 % in these images** (`NFGString.atomsOf` reads a `WeakHashMap` from inside
`RxMatchRootNode.execute`). Everything below is therefore an *interpreter-only*
runtime. That makes the correctness result stronger, not weaker: the whole
suite ran through the uncompiled path, where a Truffle-level miscompile could
not hide a bug or create one.

## 3. Results

```
Files=151, Tests=13144, 648 wallclock secs ( 0.50 usr  0.11 sys + 624.16 cusr 92.41 csys = 717.18 CPU)
Result: FAIL        (watched-run: EXIT=1 verdict=ok elapsed=647s)
```

| | JVM baseline | image |
|---|---|---|
| files run | 151 | 151 |
| tests run | 13185 | 13144 |
| red files | 9 | **12** |
| wall clock | 599 s | **648 s** |

The 41 missing tests are fully accounted for by the three new reds: 25 from
`082-decode` (5 of 30 ran), 3 from `nativecall/01-basic`, 13 from
`nativecall/02-libc`. Nothing else ran short.

### 3a. The nine known reds — identical, test number for test number

| file | JVM baseline | image | verdict |
|---|---|---|---|
| `t/nqp/021-contextual.t` | 6/33 (2, 5-6, 9, 32-33) | 6/33 (2, 5-6, 9, 32-33) | same |
| `t/nqp/022-optional-args.t` | 1/7 (7) | 1/7 (7) | same |
| `t/nqp/044-try-catch.t` | 1/62 (57) | 1/62 (57) | same |
| `t/nqp/112-continuations.t` | 2/26 (15-16) | 2/26 (15-16) | same |
| `t/qregex/01-qregex.t` | 21/845 (572-589, 591, 594, 601) | 21/845 (572-589, 591, 594, 601) | same |
| `t/p5regex/01-p5regex.t` | 3/182 (78, 159-160) | 3/182 (78, 159-160) | same |
| `t/qast/01-qast.t` | exits 1 at test 10, 10 of 184 ran | exits 1 at test 10, 10 of 184 ran | same |
| `t/jvm/01-continuations.t` | 3/22 (16-17, 19) | 3/22 (16-17, 19) | same |
| `t/jvm/11-dispatch.t` | exits 1 after 140 of 160 | exits 1 after 140 of 160 (`Bind check failed` at `t/jvm/11-dispatch.t:919`) | same |

**Nine for nine, down to the individual test numbers and the exact point at
which the two early-exiting files die.** No file went green on the image that
was red on the JVM; no known red moved.

One caution on a near-miss: `t/qregex/01-qregex.t` prints 60 `not ok` lines on
the image, but 39 of them carry `# TODO`. Counted the way the baseline counts
them — non-TODO only — it is exactly 21, and exactly the same 21. A raw
`grep -c '^not ok'` on either side would have manufactured a false regression
here; the baseline's numbers are the thing to diff against.

The image's summary also lists `TODO passed: 694, 697, 701, 703, 705, 707,
720-721, 723-724` for that file. The baseline report does not record TODO-passed
lines, so this is *not compared*, not a difference — I have no JVM figure to put
beside it.

### 3b. Three new reds — all missing metadata, none a wrong answer

**1. `t/nqp/082-decode.t` — charset not compiled into the image.** Green on
the JVM; on the image it exits 1 after 5 of 30 tests:

```
java.nio.charset.UnsupportedCharsetException: windows-1252
  in <mainline> (t/nqp/082-decode.t)
```

Native Image ships only the default charset set unless told otherwise; the
fix is a build flag (`-H:+AddAllCharsets` / `--add-all-charsets`), not a
source change. **Rakudo would hit this too** — `nqp::decode`/`encode` with a
named encoding is reachable from `IO::Handle` and from `Blob.decode`, and the
set of encodings a Raku program may name is open-world in exactly the way the
op surface is.

**2. `t/nativecall/02-libc.t` — FFM downcalls are not registered.** Green on
the JVM; on the image 0 of 13 tests run:

```
org.graalvm.nativeimage.MissingForeignRegistrationError: Cannot perform downcall
with leaf type (long,long,long)long. To allow this operation, add the following
to the 'foreign' section of 'reachability-metadata.json' and rebuild the native image:

    "downcalls": [
      { "returnType": "void*", "parameterTypes": [ "void*", "void*" ] }
    ]
  in build (t/nativecall/02-libc.t:28)
```

**3. `t/nativecall/01-basic.t` — the same cause, wearing a disguise.** Green
on the JVM; on the image 0 of 3 tests run, reported as a bare

```
java.lang.NullPointerException
  in <mainline> (t/nativecall/01-basic.t)
```

`NQP_VERBOSE_EXCEPTIONS=1` locates it at
`org.raku.nqp.runtime.NativeCallOps.call(NativeCallOps.kt:116)`, which is
`val argTypes = call.argTypes!!` — i.e. the descriptor was never built. The
test wraps its `buildnativecall` in `try { … CATCH { … } }`, which swallows
the real error and leaves a half-built call object. Running the same
`buildnativecall` without the `try` (probe under `$CLAUDE_JOB_DIR/tmp/t12b/`)
reproduces the *identical* `MissingForeignRegistrationError` as 02-libc. So
both nativecall files are one finding, and note that the failing downcall is
raised during **`buildnativecall`, before any user function is called** — the
symbol-lookup path is itself an FFM downcall.

This is the blocker the Native-Image memory note already names ("after M5 only
NativeCall FFM signatures block it"), now confirmed empirically and with its
precise shape. It is also the one finding here that a build step *cannot* fix
mechanically the way the op surface can: NativeCall signatures are constructed
at run time from a user's `is native` declaration, so the set of downcalls is
genuinely unbounded in a way the op set is not. Registering them ahead of time
means either enumerating a fixed repertoire of C signatures or accepting that
`NativeCall` does not work in an image.

### 3c. Nothing else

Every other file in all eight directories passed. No crash, no
`UnsatisfiedLinkError`, no service-loader miss, no resource-not-found, no
hang, no timeout, no file that refused to run. The Truffle language, the
polyglot engine, the unit/artifact loader, LZ4 decode, serialization
(`t/serialization/*` all green), async file and socket I/O (`t/jvm/05`,
`t/jvm/07` green), the object layout tests (`t/jvm/17`, `t/jvm/18` green) and
the whole regex engine all behave identically to the JVM.

## 4. Wall clock

**648 s against the 599 s baseline: the image costs +8 % wall, for about a
quarter to a fifth of the CPU.** Total CPU on the image side was 717 s
(`624 cusr + 92 csys`) across 151 processes.

The brief's premise — 151 short-lived processes should favour the image — is
**half right, and the half that is right only shows up in aggregate**. Spot
measurements on an otherwise idle machine:

| file | JVM wall | JVM CPU | image wall | image CPU | wall ratio |
|---|---|---|---|---|---|
| `t/nqp/001-literals.t` | 2.10 s | 12.4 s (588 %) | 3.41 s | 3.4 s (100 %) | 1.62x slower |
| `t/qregex/01-qregex.t` | 14.65 s | 121.3 s (828 %) | 18.23 s | 18.5 s (101 %) | 1.24x slower |
| **151 files** | **599 s** | ~3000 s (est.) | **648 s** | **717 s** | **1.08x slower** |

The per-file penalty is worst on the *smallest* file (1.62x, consistent with
task 12's 1.46x on `-e 'say(1)'`) and shrinks as the file gets heavier
(1.24x). Across the suite it falls to 1.08x, because the suite's mean file is
heavier than `001-literals.t`. Note what that means: the JVM's advantage is
front-loaded and bounded — it buys its wall clock with five to eight cores of
JIT — while the image runs one core throughout and closes the gap as work
accumulates. The image never actually wins; it converges.

So the coordinator's correction stands and is if anything understated in
direction: **an image removes class loading, not artifact loading**, and every
one of these 151 processes pays full artifact load. But the aggregate number is
better than the per-process number suggests, and the CPU figure (4-5x cheaper)
is the one that would matter on a loaded build machine or a many-job sweep,
where the JVM's 600-800 % is not actually available per process.

## 5. Verdict

**Yes — the image's runtime behaves like the JVM's.** 13144 tests across 151
files, and every single assertion that can be compared agrees, including all
nine known reds at the individual test number and the two files that exit
early doing so at the identical point. Not one test gave a different answer.

Every divergence is a *reachability-metadata* gap at the edge of the runtime —
one charset, one FFM signature class — and each announces itself loudly with
an exact, machine-readable remedy. None is a semantic difference in the
language, the engine, the object model, the dispatcher, the regex engine or
the unit-artifact road.

For the artifact road specifically, this is the stronger of the two results in
the milestone: `nqp.jar` is data, an AOT binary that has never seen it loads
it, and the answers are the same.

## 6. Concerns

1. **Tracing-agent metadata is not sufficient and will silently under-register.**
   `nqp-image-opt` cannot survive `say(1+1)` because `Ops.exception` was not on
   the traced path. Any image recipe that leans on agent output will fail this
   way, at a random op, arbitrarily late. The op surface must be registered
   whole (`allDeclaredMethods` over the classlib types) and generated by the
   build.
2. **NativeCall cannot work in an image without bounding the signature set**,
   and unlike the op surface it is not closed — signatures are built at run
   time from user `is native` declarations. This is the real AOT blocker and
   this run is the first direct measurement of its shape (it fails at
   `buildnativecall`, i.e. at symbol lookup, not at the call).
3. **`nqp::decode` with a named encoding is the same class of problem as ops**
   and was not on anybody's list. `--add-all-charsets` costs image size; the
   alternative is enumerating encodings, which Raku code can name freely.
4. **The image's error reporting hides causes behind `try`.**
   `t/nativecall/01-basic.t` presented as a bare `NullPointerException` a dozen
   frames from the real failure. On a full Rakudo image, where far more code
   runs under `try`, missing-registration errors will routinely surface as
   nonsense NPEs. `NQP_VERBOSE_EXCEPTIONS=1` is the tool; it should be the
   first thing anyone reaches for when triaging an image.
5. **Guest compilation was off for all of this** (the known `atomsOf`
   blocklist violation). The correctness result is if anything *more* trustworthy
   for it, but the performance numbers are an interpreter's and the suite has
   **not** been run through an image with a working optimising runtime. If the
   `@TruffleBoundary` ever lands, this run should be repeated — a compiler is
   exactly where a divergence would appear, and this run could not have seen one.
6. **`grep -c '^not ok'` is a trap on this suite.** 39 of qregex's 60 `not ok`
   lines are TODO. Any future image-vs-JVM diff must compare against the
   baseline's per-test numbers, not raw counts, or it will invent regressions.
