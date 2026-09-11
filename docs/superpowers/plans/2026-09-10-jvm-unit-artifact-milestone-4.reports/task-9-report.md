# Task 9 — the resume value (gap 5b), time-boxed

Status: **DONE_WITH_CONCERNS** (the design landed and fixes a real
instance of the gap; the brief's Probe A turned out not to be an instance
of it, and one adjacent instance lives at a site outside this task's
three ops).

nqp `d8116d7c9` + this change; rakudo `09f349adda` (rakudo tree
untouched).

## 1. What the change is, per file

All five files are in the nested **nqp** tree.

### `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpCont.java`

`Suspend` gains a third field, `java.util.function.Function<Object,
Object> finish` — the suspended op's tail as a function of the inner
call's value, `null` when the inner value IS the op's result. The
two-argument constructor delegates to a new three-argument one, so every
existing token construction (`NqpOps.java:176`, `:855`, `:963`, the two
`suspendToken` overloads) is unchanged and carries a null finisher.

### `NqpOps.java`

A third `suspendToken` overload beside the existing two:

    static Object suspendToken(SaveStackException sse,
                               java.util.function.Function<Object, Object> finish)

It fixes `rtype` at `NqpWire.T_OBJ` — with a finisher the register read is
always the INNER call's value, and that call is user code, whose result
register is an object. `readResult` is untouched.

### `NqpCodeEngine.java`

- `suspend` and the re-suspend tail of `resumeEngine` push
  `new Object[] { cr, token.rtype, token.finish }` (was two elements).
  `resumeEngine` is the only reader of that array (grep-verified), so the
  widening is local.
- `resumeEngine` reads `finish` from `saveSpace[2]` and, when it is
  non-null, reads the inner value as `T_OBJ` and injects
  `finish.apply(inner)` instead of `readResult(rtype, cf)`.
- A `finishing` flag guards the finisher against the save-stack catch:
  once `resumeNextSave()` has returned, this frame is NOT re-saved, so a
  `SaveStackException` thrown by the finisher itself (a capture the tail
  provoked) must not take the "re-suspending frame" road — it is turned
  into `NqpCont.Rethrow` like any other throw from the tail. That matches
  the controller's ruling 3: a finisher that throws is delivered as
  `Rethrow` through the existing path.

### `NqpRootNode.java`

`IsConcreteOp`, `IsTypeOp` and `P6TypeCheckRvOp` each gain, before their
existing `SaveStackException` catch:

    } catch (NqpTypeOps.SuspendedIn s) {
        return NqpOps.suspendToken(s.sse, s.finish);

The existing typed-token catch stays as the fallback for a capture the
Kotlin did not wrap (for instance the type operand's decont in `istype`).
`DecontOp`, `P6SinkOp` and `HllizeOp` are untouched — for those the inner
value IS the op's result.

### `NqpTypeOps.kt`

- New nested carrier `NqpTypeOps.SuspendedIn` (a `RuntimeException` with
  no message, no cause, no suppression and no writable stack trace),
  carrying `sse` and `finish`, plus a `@TruffleBoundary` factory
  `suspendedIn(...)` so the allocation stays off the compiled path. Only
  the exceptional path allocates; the hot path is untouched (ruling 5).
- `isconcrete`: the operand's decont is wrapped; the finisher is the op's
  tail on the fetched value, factored out as `concreteness(v)`.
- `istype`: the OBJECT operand's decont is wrapped, finisher `{ fetched ->
  istype(site, fetched, type, tc) }` — a re-run on the fetched value,
  which is no longer a container so that decont cannot suspend twice; and
  the `istypeSlow` call (`Ops.istype_nd` → `accepts_type` → a subset's
  `where`) is wrapped, finisher `truthy(checked, tc)` = `1`/`0` from the
  check's value.
- `p6typecheckrv`: both `rvCheckSlow` call sites (the direct one and the
  one inside `resolveRvCheck`) now go through a new `rvCheckRun`, whose
  finisher is `rvFinish(checked, rv, tc)`: `rv` when the check's value is
  true, otherwise the failure.
- Only `NqpRootNode` calls these three functions (grep-verified), so
  `SuspendedIn` cannot escape to a caller that would not know it.

No wire change (`NqpWire.java` untouched); no `nqp clean`, no Rakudo
`make`.

## 2. Probes

### The brief's Probe A — value correctness

    RAKUDO_RAKUAST=1 ./rakudo-j -e 'my $p := Proxy.new(FETCH => { take 7; 1 }, STORE => -> $, $ {}); my @a = gather { say ?$p }; say @a'

| | output |
|---|---|
| before | `True` then `[7 7 7 7]` |
| after  | `True` then `[7 7 7 7]` |

**Probe A does not exhibit the gap on these jars.** It already printed
`True` (the brief expected the FETCH value). The four `7`s are not a
suspension artefact either: with the take removed and the fetches
counted,

    my $n = 0; my $p := Proxy.new(FETCH => { $n++; 1 }, STORE => -> $, $ {}); say ?$p; say $n

answers `True` and `4` — `?$p` simply performs four FETCHes, so a taking
FETCH takes four times. Both before and after.

### The brief's Probe B — the type-correct case must stay

    RAKUDO_RAKUAST=1 ./rakudo-j -e 'subset S of Int where { take $_; True }; my @a = gather { 5 ~~ S }; say @a'

`[5]` before, `[5]` after. Unchanged, as required.

### The probe that DOES exhibit the gap (p6typecheckrv)

    RAKUDO_RAKUAST=1 ./rakudo-j -e 'subset S of Int where { take $_; True }; sub f(--> S) { 5 }; my @a = gather { say f() }; say @a'

| | output |
|---|---|
| before | `True` then `[5]` — the routine returned the **where block's** value |
| after  | `5` then `[5]` — correct |

This is exactly gap 5b: the op's result was the inner call's value.

### The fused type ops, after

    use nqp; my $p := Proxy.new(FETCH => { take 7; 1 }, STORE => -> $, $ {});
    my @a = gather { say nqp::istype($p, Int) }; say @a      # 1  then [7]
    my @a = gather { say nqp::isconcrete($p) }; say @a       # 1  then [7]

Both answer the op's own value (`1`) and take once. Without the finisher
these sites answer the fetched `7`.

### The adjacent instance NOT fixed (out of this task's three ops)

    RAKUDO_RAKUAST=1 ./rakudo-j -e 'my $p := Proxy.new(FETCH => { take 7; 1 }, STORE => -> $, $ {}); my @a = gather { say ($p ~~ Int) }; say @a'

fails identically before and after:

    No such method 'BOOLIFY-ACCEPTS' for invocant of type 'Int'

The chosen candidate is `infix:<~~>(Junction:D \topic, Mu \matcher)` —
i.e. a `Junction:D` bind check on the Proxy answered true. That check is
in the multi-dispatch bind road (`NqpOps.java:176`/`:963` build suspend
tokens for the dispatch sites), not in `IsConcreteOp`/`IsTypeOp`/
`P6TypeCheckRvOp`, so ruling 2's list does not cover it. Same class of
bug, different site; no regression from this change.

## 3. nqp continuation coverage

`ls nqp/t/nqp | grep -i 'cont\|gather\|coro'` →

| file | result |
|---|---|
| `112-continuations.t` | 26/26 ok (includes "gather example works", "take from handler works") |
| `047-loop-control.t` | 11/11 ok |
| `121-for-controls.t` | 16/16, no `not ok` |
| `067-container.t` | 41 planned, 39 ok, 2 `not ok # TODO on the jvm nqp::with needs more work` (pre-existing TODO) |
| `021-contextual.t` | 33 planned, 27 ok, 6 `not ok` (tests 2, 5, 6, 9, 32, 33 — `$*VAR` caller lookup and `bindlexdyn`). Pre-existing: nothing in the diff touches lexicals, dynamics or frames, and the file captures no continuations. |

## 4. `t/01-sanity`

    RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=t/01-sanity --jobs=2 \
      --log-dir=.../t9-sanity-logs --show-file=.../t9-sanity.markers -- ./rakudo-j

**25 of 25 ok in 136 s.** No failures, no skips.
Markers: `/home/longwalker/.claude/jobs/25fa1a35/tmp/t9-sanity.markers`;
logs: `/home/longwalker/.claude/jobs/25fa1a35/tmp/t9-sanity-logs/`.

## 5. Rebuilds used

Both of the two allowed rebuilds were used, and both succeeded:

    ./nqp/gradlew -p nqp :nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars

1. **Rebuild 1** — the whole change. `BUILD SUCCESSFUL in 2s`
   (`:nqp-runtime:test` UP-TO-DATE, Kotlin + the Bytecode-DSL processor
   recompiled, no new warnings from the changed code). All probes,
   the nqp continuation files and `t/01-sanity` ran on these jars.
2. **Rebuild 2** — a comment/indentation reindent inside the new `else`
   block in `resumeEngine` only, no behaviour change.
   `BUILD SUCCESSFUL in 2s`; the three probes were re-run on the final
   jars and answer exactly as after rebuild 1 (`True`/`[7 7 7 7]`,
   `[5]`, `5`/`[5]`).

No third rebuild; no `nqp clean`; no Rakudo `make`.

Eval servers: none were running; a `pkill` for `eval-server`/`EvalServer`
was issued before the rebuild.

## 6. Self-review

- **The array widening is safe.** `frame.saveSpace` for this RESUME
  handle is written in exactly two places and read in exactly one; all
  three are in `NqpCodeEngine` and all three moved together.
- **No hot-path cost.** The finisher is allocated only inside a `catch`
  of a `SaveStackException` — the path where a `SaveStackException` was
  already allocated and the frame is already going to be packed away. The
  `SuspendedIn` allocation is behind a `@TruffleBoundary`. `isconcrete`'s
  tail moved into `concreteness(v)`, a private one-expression function
  Graal inlines; the two `try` blocks are exception edges, not work.
- **Old tokens still work.** Every token without a finisher takes the
  `finish == null` road, which is byte-for-byte the previous behaviour
  (`readResult(rtype, cf)`), including the `T_INT` typing of the
  `isconcrete`/`istype` fallback catches.
- **The finisher can throw.** Ruling 3 is implemented explicitly: a throw
  from the tail — including a `SaveStackException` it provoked — becomes
  `NqpCont.Rethrow` and reaches the program's handler regions as the op's
  own throw. A capture provoked by a finisher is therefore reported (as a
  non-suspendable site) rather than silently dropped.
- **Re-suspension inside `istype`'s finisher** (`istype(site, fetched,
  type, tc)`) is possible if the fetched value's type check itself takes.
  That is the ruling-3 road above, not corruption.

## 7. Concerns

1. **The brief's Probe A is not an instance of gap 5b on these jars** —
   it was already correct before the change, and its `[7 7 7 7]` is a
   plain four-FETCH count, not a resume artefact. The time box's stop
   condition ("if the first probe still answers the inner value") never
   applied. The gap is real and is demonstrated by the `sub f(--> S)`
   probe above, which the change fixes.
2. **The p6typecheckrv failure tail is not faithful.** When the resumed
   `where` block answers false, `rvFinish` raises
   `ExceptionHandling.dieInternal(tc, "Type check failed for return
   value")` — the message RakOps uses when no thrower is registered —
   rather than `X::TypeCheck::Return`. The typed thrower needs the
   check's instantiated return type and the deconted value, both local to
   `RakOps.p6typecheckrv` (rakudo tree, `src/vm/jvm/runtime/org/raku/
   rakudo/RakOps.kt`, a separate jar). Ruling 2 asked for that tail to be
   factored into a private function first; doing it faithfully means
   editing RakOps and rebuilding `rakudo-runtime.jar`, which is outside
   "all your edits and your commit live in the nqp tree". Before this
   change the same case returned the where block's value as the routine's
   return value, so the current behaviour is strictly closer to correct.
   Follow-up: factor `RakOps.p6typecheckrv`'s tail into a `@JvmStatic`
   entry point and bind it in `NqpTypeOps.Rak`.
3. **The bind-check site still has the gap** (the `$p ~~ Int`
   BOOLIFY-ACCEPTS failure in §2). It is the same mechanism at the
   multi-dispatch bind road, which ruling 2 did not list; it needs the
   same treatment at `NqpOps.java:176`/`:963`.
4. **`021-contextual.t`'s 6 failures were not measured before the
   change** (the jars had already been rebuilt when the file was first
   run). They are argued pre-existing by inspection: dynamic-variable and
   `bindlexdyn` tests, no continuation capture in the file, and nothing
   in the diff touches lexicals or frames.

## 8. Files changed

    nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpCont.java
    nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java
    nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpCodeEngine.java
    nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java
    nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt

## 9. Commit

nqp `929f73b11` — "engine: a suspended fused op resumes through its
finisher -- the op's tail runs on the inner call's value instead of
taking that value as the op's result". The rakudo worktree is untouched
(no rakudo commit).
