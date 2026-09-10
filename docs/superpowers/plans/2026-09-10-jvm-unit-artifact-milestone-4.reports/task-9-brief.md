### Task 9: The resume value (gap 5b), time-boxed

**Files:**
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpCont.java:20-27` (`Suspend`)
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java:1043-1057` (`suspendToken` overloads), `:1068-1090` (`readResult`, unchanged)
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpCodeEngine.java:122-126` (`suspend`), `:156-176` (`resumeEngine`), `:203-209` (the re-suspend tail)
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java:512-523` (`DecontOp`), `:539-548` (`IsConcreteOp`), `:554-575` (`IsTypeOp`), `:580-592` (`P6SinkOp`), `:596-608` (`HllizeOp`), `:632-644` (`P6TypeCheckRvOp`)
- Modify: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt:233-300` (`decont`/`decontSlow`), `:334-345` (`isconcrete`), `:360-410` (`istype`/`istypeSlow`), `:448-` (`p6typecheckrv`)
- Test: the probe from the report; `t/01-sanity`; `nqp/t/nqp/*continuation*` and `*gather*` files if present (`ls nqp/t/nqp | grep -i 'cont\|gather'`)

**Time box:** two runtime-jar rebuilds (the engine jar rebuilds in the same command). If the probe still answers the inner value after the second, stop, record, rule (revert or keep), ledger.

**Mechanism (from milestone 3's task-3b report and the code):** a fused op (`isconcrete` = decont + concreteness test; `istype` = decont + type check; `p6typecheckrv` = a `where` call + the pass/fail decision) catches the `SaveStackException` thrown from user code it called (a Proxy FETCH, a `where` block) and answers a suspend token; `emitSuspendCheck` yields it; on resume, `resumeEngine` reads the INNER call's value off the return registers and `UnpackResumed` stores it as the OP's result. The tail of the op after the inner call never runs. The class road composed these ops from smaller pieces (decont was its own classlib call), so the suspended piece's result WAS the inner value.

**Design:** the token carries a finisher: the op's tail as a function of the inner call's value. `resumeEngine` applies it to the inner value (read as an object) and injects the finisher's answer. No wire change; the engine's yield/resume shape is unchanged.

- [ ] **Step 1: The probe, before** (expected today: `7`):

```
RAKUDO_RAKUAST=1 ./rakudo-j -e 'my $p := Proxy.new(FETCH => { take 7; 1 }, STORE => -> $, $ {}); my @a = gather { say ?$p }; say @a'
```

(Expected after: `True` then `[7]`; today `say ?$p` prints the FETCH value.) Also the report's own probe: `RAKUDO_RAKUAST=1 ./rakudo-j -e 'subset S of Int where { take $_; True }; my @a = gather { 5 ~~ S }; say @a'` answers `[5]` today and after (it is the type-correct case).

- [ ] **Step 2: The token and its finisher** (`NqpCont.java`):

```java
    static final class Suspend {
        final SaveStackException sse;
        final int rtype;
        /** The suspended op's tail, applied on resume to the inner call's
         *  (object) value; null when the inner value IS the op's result. */
        final java.util.function.Function<Object, Object> finish;
        Suspend(SaveStackException sse, int rtype) { this(sse, rtype, null); }
        Suspend(SaveStackException sse, int rtype, java.util.function.Function<Object, Object> finish) {
            this.sse = sse;
            this.rtype = rtype;
            this.finish = finish;
        }
    }
```

`NqpOps.java`: `static Object suspendToken(SaveStackException sse, java.util.function.Function<Object, Object> finish) { return new NqpCont.Suspend(sse, NqpWire.T_OBJ, finish); }` beside the two existing overloads (the inner call's value is read as an object; the finisher answers the op's own type: a `Long` for the int-typed ops, which the consumers already take as `Object`).

`NqpCodeEngine.java`: `suspend(...)` and the re-suspend tail push `new Object[] { cr, token.rtype, token.finish }`; `resumeEngine`:

```java
        ContinuationResult cr = (ContinuationResult) frame.saveSpace[0];
        int rtype = (Integer) frame.saveSpace[1];
        @SuppressWarnings("unchecked")
        java.util.function.Function<Object, Object> finish =
            (java.util.function.Function<Object, Object>) frame.saveSpace[2];
        ...
        try {
            frame.resumeNextSave();
            inject = finish == null ? NqpOps.readResult(rtype, cf)
                                    : finish.apply(NqpOps.readResult(NqpWire.T_OBJ, cf));
        } catch (SaveStackException sse) { ... unchanged ... }
        catch (Throwable t) { inject = new NqpCont.Rethrow(t); }
```

(a finisher that throws -- a failed type check -- is delivered through the yield as the op's own throw, exactly the existing `Rethrow` road).

- [ ] **Step 3: Where the inner calls are** (`NqpTypeOps.kt`). Introduce one exception type:

```kotlin
/** Thrown by a fused op at the user-code call that captured a
 *  continuation: the capture plus the op's tail, for the suspend token. */
class SuspendedIn(@JvmField val sse: org.raku.nqp.runtime.SaveStackException,
                  @JvmField val finish: java.util.function.Function<Any?, Any?>)
    : RuntimeException(null, null, false, false)
```

and wrap the user-code calls: in `isconcrete(site, o, tc)`, the decont of `o` (`try { ...decont... } catch (sse: SaveStackException) { throw SuspendedIn(sse) { v -> isconcreteOf(v, tc) } }` where `isconcreteOf` is the existing tail on an already-deconted value: read the function to name it); in `istype`, the decont of `o` (finisher: `{ v -> istype(site, v, type, tc) }`, a re-run on the fetched value, no Proxy left to re-suspend) and the `accepts_type` call in `istypeSlow` (finisher: `{ v -> if (Ops.istrue(v as SixModelObject, tc) != 0L) 1L else 0L }`); in `p6typecheckrv`, the `where`/`accepts_type` call (finisher: the pass/fail tail on the check's value: `rv` when true, the same failure the Kotlin code raises when false -- factor that tail into a private function first). `decont`, `p6sink`, `hllize`: the inner value is the result; no change.

- [ ] **Step 4: The ops** (`NqpRootNode.java`): in `IsConcreteOp`, `IsTypeOp`, `P6TypeCheckRvOp` add before the `SaveStackException` catch:

```java
            } catch (NqpTypeOps.SuspendedIn s) {
                return NqpOps.suspendToken(s.sse, s.finish);
```

(the existing typed-token catch stays as the fallback for a capture the Kotlin did not wrap).

- [ ] **Step 5**: `./nqp/gradlew -p nqp :nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars`; the two probes (`True`/`[7]` and `[5]`); `t/01-sanity` (`t9-sanity`); the nqp continuation/gather tests (`t9-cont`). Expected 25/25 and green.

- [ ] **Step 6**: Commit (nqp): `git add -A nqp-truffle/src/main src/vm/jvm/runtime && git commit -m "engine: a suspended fused op resumes through its finisher -- the op's tail runs on the inner call's value instead of taking that value as the op's result"`.

---

