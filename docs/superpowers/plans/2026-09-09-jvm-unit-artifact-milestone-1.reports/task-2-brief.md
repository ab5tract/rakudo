### Task 2: Runtime hooks and the shared block entry

**Files:**
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CompilationUnit.kt` (lines 185-199 `runDeserializeIfAvailable`, 392-404 `engineProgram`; add hooks)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/StaticCodeInfo.kt` (add `programIndex`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CodeEngine.kt` (add `materialize`, `codeRunUnit`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt:6512-6532` (deserialize reads `cu.serializedBlob()`), `:8959-9001` (claim through `cu.claimNested`)
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramEntry.kt`

**Interfaces:**
- Produces on `CompilationUnit`: `open fun engineProgram(idx: Int): String`, `open fun serializedBlob(): ByteBuffer?`, `open fun claimNested(tc: ThreadContext, name: String): CompilationUnit`, `open fun unitId(): String`, `open fun runDeserializeIfAvailable(tc)`.
- Produces on `StaticCodeInfo`: `@JvmField var programIndex: Int = -1`.
- Produces on `CodeEngines`: `@JvmStatic fun materialize(sci: StaticCodeInfo): Any?`, `@JvmStatic fun codeRunUnit(sci, cu, tc, cf, csd, args)`.
- Produces `ProgramEntry.ENTER: MethodHandle` of type `(ThreadContext, CodeRef, CallSiteDescriptor, ResumeStatus.Frame, Array<Any?>) -> Unit`.

- [ ] **Step 1: Hooks on CompilationUnit**

In `CompilationUnit.kt`, change `fun runDeserializeIfAvailable` (line 185) to `open fun runDeserializeIfAvailable`, change `fun engineProgram(idx: Int): String` (line 392) to `open fun engineProgram(idx: Int): String`, and add after `serializedCodeRefCount()` (line 380):

```kotlin
    /** The unit's identity string: the class's simple name on the class
     *  road, the artifact's unit id on the artifact road. Replaces the
     *  Class object wherever a unit was named. */
    open fun unitId(): String = javaClass.simpleName

    /** The serialized context, decompressed, or null when the unit has
     *  none. The class road reads it as a class resource; the artifact
     *  road holds it. */
    open fun serializedBlob(): java.nio.ByteBuffer? {
        val cuName = javaClass.simpleName
        var stream = javaClass.getResourceAsStream("$cuName.serialized.lz4")
        if (stream != null)
            return stream.use { LibraryLoader.readToHeapBufferLz4(it) }
        stream = javaClass.getResourceAsStream("$cuName.serialized") ?: return null
        return stream.use { LibraryLoader.readToHeapBuffer(it) }
    }

    /** Instantiates and initializes (without deserializing) the nested
     *  unit of the given name that rides in this unit. The class road
     *  loads it by class name through this unit's class loader. */
    open fun claimNested(tc: ThreadContext, name: String): CompilationUnit {
        val klass = Class.forName(name, true, javaClass.classLoader)
        @Suppress("DEPRECATION")
        val nested = klass.getDeclaredConstructor().newInstance() as CompilationUnit
        nested.shared = tc.gc.sharingHint
        nested.initializeCompilationUnit(tc, false)
        return nested
    }
```

- [ ] **Step 2: Route deserialize and claim through the hooks**

In `Ops.kt`, replace lines 6512-6532 (the `val binaryBlob: ByteBuffer` ... `catch (e: IOException)` block for `blob == null`) with:

```kotlin
        val binaryBlob: ByteBuffer
        if (blob == null)
            binaryBlob = cu.serializedBlob()
                ?: throw ExceptionHandling.dieInternal(tc, "unit ${cu.unitId()} has no serialized context to deserialize")
        else
```

keeping the existing `try { binaryBlob = Base64.decode(blob) } ... ` else-arm as it is. In `jvmclaimnested` (8959-9001) replace the three lines

```kotlin
            val klass = Class.forName(className, true, cu.javaClass.classLoader)
            val nested = klass.getDeclaredConstructor().newInstance() as CompilationUnit
            nested.shared = tc.gc.sharingHint
```

and the following `nested.initializeCompilationUnit(tc, false)` line with

```kotlin
            val nested = cu.claimNested(tc, className!!)
```

and widen the catch from `ReflectiveOperationException` to `Exception` so a missing nested artifact reports through the same `Could not load nested compilation unit` message. Also change the `IOException` import usage only if the compiler now flags it unused.

- [ ] **Step 3: programIndex and the materializing engine road**

In `StaticCodeInfo.kt` after `engineTarget` (line 72) add:

```kotlin
    /** On the artifact road: the block's program index in its unit, so
     *  the target can be materialized on demand (see CodeEngines.materialize)
     *  instead of waiting for a first run through a stub. -1 on the class road. */
    @JvmField var programIndex: Int = -1
```

In `CodeEngine.kt`, inside `object CodeEngines` after `codeRun` add:

```kotlin
    /**
     * The block's engine target, compiling its program from the unit on
     * first need. Null for a class-road block that has not run yet (no
     * program index) or when there is no engine. Synchronized on the
     * static info so two threads racing on the first call agree on one
     * target.
     */
    @JvmStatic
    fun materialize(sci: StaticCodeInfo): Any? {
        sci.engineTarget?.let { return it }
        if (sci.programIndex < 0) return null
        val engine = engine ?: return null
        synchronized(sci) {
            sci.engineTarget?.let { return it }
            val program = engine.compile(sci.compUnit.engineProgram(sci.programIndex))
            sci.engineTarget = program
            return program
        }
    }

    /** The artifact road's block body: what codeRunIdx is for a stub. */
    @JvmStatic
    fun codeRunUnit(
        sci: StaticCodeInfo,
        cu: CompilationUnit,
        tc: ThreadContext,
        cf: CallFrame,
        csd: CallSiteDescriptor,
        args: Array<Any?>?,
    ) {
        val engine = engine ?: throw IllegalStateException(
            "this unit was compiled with the code engine, which is not available at run time:" +
            " the truffle module is missing from the class path.")
        val program = materialize(sci) ?: throw IllegalStateException(
            "block ${cf.codeRef?.name ?: "<anon>"} of unit ${cu.unitId()} has no program")
        if (trace) System.err.println("code> " + (cf.codeRef?.name ?: "<anon>"))
        engine.run(program, cu, tc, cf, csd, args ?: emptyArray())
    }
```

- [ ] **Step 4: The entry function**

`ProgramEntry.kt`:

```kotlin
package org.raku.nqp.runtime.unit

import java.lang.invoke.MethodHandle
import java.lang.invoke.MethodHandles
import java.lang.invoke.MethodType
import org.raku.nqp.runtime.CallFrame
import org.raku.nqp.runtime.CallSiteDescriptor
import org.raku.nqp.runtime.CodeEngines
import org.raku.nqp.runtime.CodeRef
import org.raku.nqp.runtime.ControlException
import org.raku.nqp.runtime.ExceptionHandling
import org.raku.nqp.runtime.ResumeStatus
import org.raku.nqp.runtime.ThreadContext

/**
 * The one body every artifact block has: what Compiler.nqp's emitted
 * stub did around codeRunIdx (Compiler.nqp as_jast(QAST::Block),
 * prelude and postlude), as a function. Its handle has the shape
 * StaticCodeInfo's init expects of a bound stub, (tc, cr, csd, resume,
 * args), so the invoke road and the resume surgery are untouched;
 * `resume` is unused because an engine program resumes through its own
 * handle (NqpCodeEngine.RESUME).
 */
object ProgramEntry {
    @JvmStatic
    fun enter(tc: ThreadContext, cr: CodeRef, csd: CallSiteDescriptor,
              @Suppress("UNUSED_PARAMETER") resume: ResumeStatus.Frame?, args: Array<Any?>?) {
        val sci = cr.staticInfo
        val cf = CallFrame(tc, cr)
        try {
            CodeEngines.codeRunUnit(sci, sci.compUnit, tc, cf, csd, args)
        } catch (e: ControlException) {
            cf.leave()
            throw e
        } catch (e: Throwable) {
            throw ExceptionHandling.dieInternal(tc, e)
        }
        cf.leave()
    }

    @JvmField
    val ENTER: MethodHandle = MethodHandles.lookup().findStatic(
        ProgramEntry::class.java, "enter",
        MethodType.methodType(Void.TYPE, ThreadContext::class.java, CodeRef::class.java,
            CallSiteDescriptor::class.java, ResumeStatus.Frame::class.java, Array<Any?>::class.java))
}
```

Note: `StaticCodeInfo.init` rebinds `mh` per instance with `insertArguments`, so every block's `staticInfo.mh` is a distinct object even though all share `ENTER`; `CallFrame.outerFor`'s identity test (`CallFrame.kt:40`) therefore keeps working.

- [ ] **Step 5: Build the runtime jar**

Run: `./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars 2>&1 | tail -5`
Expected: `BUILD SUCCESSFUL`. Then a class-road smoke, since the class road must be untouched: `RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle -e 'say(1+2)'`
Expected: `3`.

- [ ] **Step 6: Commit (nqp tree)**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git add src/vm/jvm/runtime/org/raku/nqp/runtime/CompilationUnit.kt src/vm/jvm/runtime/org/raku/nqp/runtime/StaticCodeInfo.kt src/vm/jvm/runtime/org/raku/nqp/runtime/CodeEngine.kt src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramEntry.kt && git commit -F - <<'EOF'
unit artifact: unit hooks (serializedBlob, claimNested, engineProgram, unitId), materialized targets, the shared block entry

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRn8gLyZjirBAKS6urb3n4
EOF
```

---

