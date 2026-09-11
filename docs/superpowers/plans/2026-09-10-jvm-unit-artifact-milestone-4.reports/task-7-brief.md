### Task 7: The interop adaptors on plain method handles

**Files:**
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/AdaptorUnit.kt`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/BootJavaInterop.kt:224-234` (`computeInterop`), `:276-297` (`createAdaptor`: superclass, no `compunitMethods`), `:299-323` (`compunitMethods` deleted), `:810-818` (`startCallout`: no annotation), and the second `startVarArityCallout`-like site if any (`grep -n visitAnnotation`)
- Modify: `src/vm/jvm/runtime/org/raku/rakudo/RakudoJavaInterop.kt:828-889` (`createAdaptor`), `:722-732` (`startVarArityCallout`: no annotation), `:928-936` (`computeInterop`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CompilationUnit.kt` (the reflective half goes: `getCodeInfo`, `codeInfoStash`, `ReflectiveCodeInfo`, the annotation loop in `initializeCompilationUnit`), delete `CodeRefAnnotation.kt`
- Test: `t/03-jvm/01-interop.t`; `t/01-sanity`

**Interfaces:**
- Consumes: `CompilationUnit.getCodeRefs()` hook, `lookupCodeRef(Int)` = position in `getCodeRefs()`'s array (Task 5); `StaticCodeInfo`'s acceptance of a four-parameter bound handle `(ThreadContext, CodeRef, CallSiteDescriptor, Object[])` (`StaticCodeInfo.kt:249-272`: neither branch fires, the handle is used as is, exactly KnowHOWMethods' shape); `ByteClassLoader.defineClass` for the plain class.
- Produces: `AdaptorUnit(cls: Class<*>, descriptors: List<String>, target: String)`; generated adaptor classes with superclass `java/lang/Object`, static `qb_N(CompilationUnit, ThreadContext, CodeRef, CallSiteDescriptor, Object[])` methods, no annotation; `CompilationUnit.initializeCompilationUnit` non-reflective.

- [ ] **Step 1: AdaptorUnit**:

```kotlin
package org.raku.nqp.runtime

import java.lang.invoke.MethodHandles
import java.lang.invoke.MethodType

/**
 * The unit behind a generated Java-interop adaptor class: one code ref
 * per static qb_N callout, built from a method handle bound to this unit
 * (the callouts take the unit as their first argument, as every block
 * entry does). No reflection over annotations, no generated subclass of
 * CompilationUnit: the same road KnowHOWMethods takes.
 */
class AdaptorUnit(
    private val cls: Class<*>,
    private val descriptors: List<String>,
    private val target: String,
) : CompilationUnit() {
    override fun getCodeRefs(): Array<CodeRef> {
        val l = MethodHandles.lookup()
        val mt = MethodType.methodType(Void.TYPE, CompilationUnit::class.java, ThreadContext::class.java,
            CodeRef::class.java, CallSiteDescriptor::class.java, Array<Any?>::class.java)
        return Array(descriptors.size) { i ->
            val name = "callout $target ${descriptors[i]}"
            val mh = l.findStatic(cls, "qb_$i", mt).bindTo(this)
            CodeRef(this, mh, name, name, null, null, null, null, arrayOf(), 0.toShort())
        }
    }
    override fun getCallSites(): Array<CallSiteDescriptor> = arrayOf()
    override fun hllName(): String = ""
    override fun unitId(): String = cls.name
    override fun engineProgram(idx: Int): String =
        throw IllegalStateException("adaptor unit ${cls.name} has no engine programs")
    override fun serializedBlob(): java.nio.ByteBuffer? = null
    override fun claimNested(tc: ThreadContext, name: String): CompilationUnit =
        throw IllegalStateException("adaptor unit ${cls.name} carries no nested unit $name")
}
```

(Match the abstract members Task 5 left on `CompilationUnit`; if `unitId`/`engineProgram`/`serializedBlob`/`claimNested` stayed `open` with bodies, drop the overrides that are not needed.)

- [ ] **Step 2: BootJavaInterop.** `createAdaptor`: `cw.visit(BytecodeVersion.EMITTED, Opcodes.ACC_PUBLIC or Opcodes.ACC_SUPER, className, null, "java/lang/Object", null)`; delete the `compunitMethods(cc)` call and the method; in `startCallout` delete the three `visitAnnotation` lines; in `computeInterop`:

```kotlin
        val adaptor = createAdaptor(klass)
        val adaptorUnit = AdaptorUnit(adaptor.constructed!!, adaptor.descriptors, klass.getName())
        adaptorUnit.initializeCompilationUnit(tc)
```

(the `try { newInstance() } catch` block goes). `finishClass` is unchanged (the plain class's `constants` static is still set reflectively). Check `TYPE_CU` is still used (the callout descriptor names it): yes.

- [ ] **Step 3: RakudoJavaInterop.** `createAdaptor:830`: superclass `"java/lang/Object"` (and `BytecodeVersion.EMITTED` instead of `Opcodes.V1_7`, since the boot side already emits that); delete `compunitMethods(cc)`; `startVarArityCallout` loses its `visitAnnotation` lines (and any other `qb_` site: `grep -n 'visitAnnotation\|CodeRefAnnotation' src/vm/jvm/runtime/org/raku/rakudo/RakudoJavaInterop.kt` must be empty after); `computeInterop:928-936` as in Step 2 (`AdaptorUnit(adaptor.constructed!!, adaptor.descriptors, klass.name)`).

- [ ] **Step 4: CompilationUnit loses the reflective half.** Delete `getCodeInfo`, `codeInfoStash`, `ReflectiveCodeInfo`, the `Method`/`MethodHandles` imports that only they used, and rewrite `initializeCompilationUnit(tc, runDeserialize)` as the `getCodeRefs()` road only:

```kotlin
    /** Fills the code-ref tables from getCodeRefs() (a hand-written unit:
     *  KnowHOWMethods, AdaptorUnit); a ProgramUnit overrides this with its
     *  block table. */
    open fun initializeCompilationUnit(tc: ThreadContext, runDeserialize: Boolean) {
        val bootSt = tc.gc.BOOTCode?.st
        val refs = getCodeRefs()
        codeRefs = refs
        qbidToCodeRef = arrayOfNulls<CodeRef>(refs.size).also { t -> for (i in refs.indices) t[i] = refs[i] }
        for (c in refs) {
            if (bootSt != null) c.st = bootSt
            c.staticInfo.uniqueId?.let { cuidToCodeRef[it] = c }
        }
        callSites = getCallSites()
        hllConfig = tc.gc.getHLLConfigFor(hllName())
        if (runDeserialize) runDeserializeIfAvailable(tc)
    }
```

`git rm src/vm/jvm/runtime/org/raku/nqp/runtime/CodeRefAnnotation.kt` (nqp dir); `grep -rn CodeRefAnnotation nqp/src src` empty (the `UnitRecord.kt:1-2` comment names it: reword).

- [ ] **Step 5**: runtime jars (nqp). Rakudo's `RakudoJavaInterop.kt` compiles in the make: run `make` now? No -- `make` rebuilds only what changed; rakudo's runtime jar target (`rakudo-runtime.jar` via the Makefile's kotlin step) is what changed. Run: `RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/25fa1a35/tmp/t7-make.log --show='Compiling' --show='rror' -- make` and confirm from the log that only the runtime jar step ran (no `Compiling ... CORE.c`); if the Makefile's dependency graph recompiles settings because the runtime jar is newer, let it (forward only) and record the time.

- [ ] **Step 6**: `RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=t/03-jvm --jobs=1 --log-dir=/home/longwalker/.claude/jobs/25fa1a35/tmp/t7-interop-logs -- ./rakudo-j -Ilib` (expected: `01-interop.t` 30 planned, its 3 known skips, no failures) and `t/01-sanity` (`t7-sanity`, 25/25). Restart eval servers.

- [ ] **Step 7**: Commit (nqp): `git add -A src/vm/jvm/runtime && git commit -m "interop: adaptor classes are plain classes; AdaptorUnit builds their code refs from bound method handles; the reflective code-ref road and CodeRefAnnotation are gone"`; (rakudo): `git add src/vm/jvm/runtime/org/raku/rakudo/RakudoJavaInterop.kt && git commit -m "JVM interop: the Rakudo adaptor is a plain class behind an AdaptorUnit"`.

---

