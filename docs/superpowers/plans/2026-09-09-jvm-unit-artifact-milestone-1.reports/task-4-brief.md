### Task 4: The loader roads, the entry main, the eval server

**Files:**
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitLoader.kt`
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitMain.kt`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/LibraryLoader.java:32-83` (`load` overloads), add `loadApp`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/tools/EvalServer.java:66-91` and `:139-140`

**Interfaces:**
- Produces: `UnitLoader.isUnitFile(fn): Boolean`, `UnitLoader.record(fn, shared): UnitRecord`, `UnitLoader.loadUnit(tc, fn, shared): ProgramUnit` (initialized, load block not run), `UnitLoader.loadAndRun(tc, fn, shared)`, `UnitLoader.loadAndRun(tc, bytes: ByteArray)`; `LibraryLoader.loadApp(tc, path, shared): CompilationUnit` (road-agnostic: initialized, no load block); `LibraryLoader.prime(path)` (warms whichever road); `UnitMain.main(argv)`.

- [ ] **Step 1: UnitLoader**

```kotlin
package org.raku.nqp.runtime.unit

import java.io.File
import java.util.concurrent.ConcurrentHashMap
import org.raku.nqp.runtime.ThreadContext

/** Loads unit artifacts. A shared load (eval server) caches the parsed,
 *  immutable record by path and builds a fresh ProgramUnit per load,
 *  the way the class road shares the Class and instantiates per context. */
object UnitLoader {
    private val sharedRecords = ConcurrentHashMap<String, UnitRecord>()

    @JvmStatic
    fun isUnitFile(fn: String): Boolean {
        val f = File(fn)
        if (!f.isFile) return false
        return try { UnitZip.isUnit(f.readBytes()) } catch (t: Exception) { false }
    }

    @JvmStatic
    fun record(fn: String, shared: Boolean): UnitRecord =
        if (shared) sharedRecords.computeIfAbsent(fn) { UnitZip.read(File(it).readBytes()) }
        else UnitZip.read(File(fn).readBytes())

    @JvmStatic
    fun loadUnit(tc: ThreadContext, fn: String, shared: Boolean): ProgramUnit {
        val u = ProgramUnit(record(fn, shared))
        u.shared = shared
        u.initializeCompilationUnit(tc)
        return u
    }

    @JvmStatic
    fun loadAndRun(tc: ThreadContext, fn: String, shared: Boolean) {
        loadUnit(tc, fn, shared).runLoadIfAvailable(tc)
    }

    @JvmStatic
    fun loadAndRun(tc: ThreadContext, bytes: ByteArray) {
        val u = ProgramUnit(UnitZip.read(bytes))
        u.shared = tc.gc.sharingHint
        u.initializeCompilationUnit(tc)
        u.runLoadIfAvailable(tc)
    }
}
```

- [ ] **Step 2: The bilingual switch in LibraryLoader**

In `LibraryLoader.java`, in `load(ThreadContext tc, String filename)` replace the line `resolveClass(tc, loadFile(filename, tc.gc.byteClassLoader, tc.gc.sharingHint));` with:

```java
            if (org.raku.nqp.runtime.unit.UnitLoader.isUnitFile(filename))
                org.raku.nqp.runtime.unit.UnitLoader.loadAndRun(tc, filename, tc.gc.sharingHint);
            else
                resolveClass(tc, loadFile(filename, tc.gc.byteClassLoader, tc.gc.sharingHint));
```

Replace the body of `load(ThreadContext tc, ByteBuffer buffer)` with:

```java
        try {
            byte[] bytes = new byte[buffer.remaining()];
            buffer.duplicate().get(bytes);
            if (org.raku.nqp.runtime.unit.UnitZip.isUnit(bytes))
                org.raku.nqp.runtime.unit.UnitLoader.loadAndRun(tc, bytes);
            else
                resolveClass(tc, loadJar(buffer, tc.gc.byteClassLoader));
        }
        catch (IOException | IllegalArgumentException | ClassNotFoundException e) {
            throw ExceptionHandling.dieInternal(tc, e);
        }
```

Add after `resolveClass`:

```java
    /* Road-agnostic app load for entry points (runner main, eval server):
     * the unit is initialized (deserialized) but its load block is not run;
     * an entry block does that itself. */
    public static CompilationUnit loadApp(ThreadContext tc, String path, boolean shared) {
        if (org.raku.nqp.runtime.unit.UnitLoader.isUnitFile(path))
            return org.raku.nqp.runtime.unit.UnitLoader.loadUnit(tc, path, shared);
        try {
            return CompilationUnit.setupCompilationUnit(tc, loadFile(path, tc.gc.byteClassLoader, shared), shared);
        }
        catch (IOException | IllegalArgumentException | ClassNotFoundException | ReflectiveOperationException e) {
            throw ExceptionHandling.dieInternal(tc, e);
        }
    }

    /* Warms whichever road the path takes, so a server pays for parsing once. */
    public static void prime(String path, ByteClassLoader loader) throws IOException, ClassNotFoundException {
        if (org.raku.nqp.runtime.unit.UnitLoader.isUnitFile(path))
            org.raku.nqp.runtime.unit.UnitLoader.record(path, true);
        else
            loadFile(path, loader, true);
    }
```

- [ ] **Step 3: UnitMain**

```kotlin
package org.raku.nqp.runtime.unit

import org.raku.nqp.runtime.GlobalContext
import org.raku.nqp.runtime.LibraryLoader
import org.raku.nqp.runtime.Ops

/** The runner scripts' main class: `UnitMain <unit.jar> args...`. Either
 *  road: the loader decides. Replaces the generated `nqp`/`perl6` class
 *  main, which called CompilationUnit.enterFromMain on its own Class. */
object UnitMain {
    @JvmStatic
    fun main(argv: Array<String>) {
        require(argv.isNotEmpty()) { "usage: UnitMain <unit jar> [args...]" }
        val tc = GlobalContext().mainThread!!
        val cu = LibraryLoader.loadApp(tc, argv[0], false)
        val entry = cu.entryQbid()
        check(entry >= 0) { "${argv[0]} is not an entry point (no entry block)" }
        Ops.invokeMain(tc, cu.lookupCodeRef(entry), cu.unitId(), argv.copyOfRange(1, argv.size))
    }
}
```

- [ ] **Step 4: EvalServer through loadApp**

In `EvalServer.java`, in `run(String appPath, String[] argv)` replace the `cuType = LibraryLoader.loadFile(...)` try/catch and the `CompilationUnit cu = ...` / `entryRef` lines so the method reads:

```java
        gc = new GlobalContext();
        gc.in = new ByteArrayInputStream(new byte[0]);
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        gc.out = gc.err = new PrintStream( baos, true, "UTF-8" );
        gc.interceptExit = true;
        gc.sharingHint = true;

        CompilationUnit cu = LibraryLoader.loadApp(gc.mainThread, appPath, true);
        CodeRef entryRef = null;
        if (cu.entryQbid() >= 0) entryRef = cu.lookupCodeRef(cu.entryQbid());
        if (entryRef == null)
            throw new RuntimeException("This unit is not an entry point");
        try {
            Ops.invokeMain(gc.mainThread, entryRef, cu.unitId(), argv);
        } catch (ThreadDeath td) {
            baos.flush();
        }
        return baos.toString("UTF-8");
```

In `run()` (server start, line 140) replace `cuType = LibraryLoader.loadFile(mainPath, gc.byteClassLoader, true);` with `LibraryLoader.prime(mainPath, gc.byteClassLoader);`. Apply the same two-line change (`loadApp` + `cu.unitId()`) at the second `setupCompilationUnit(... cuType ...)` site near line 239-245 (the per-request `ServiceThread`), and delete the now-unused `cuType` field if the compiler flags it.

- [ ] **Step 5: Build and smoke both roads**

Run: `./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars 2>&1 | tail -5`
Then the class road through the new main, from the rakudo worktree root (the paths mirror `nqp/nqp-j-gradle`'s final `exec` line; copy its `-Xbootclasspath/a:` and `-cp` values verbatim):

```bash
RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 java --enable-native-access=ALL-UNNAMED,org.graalvm.truffle --sun-misc-unsafe-memory-access=allow -Xmx4g -Xss64m --module-path nqp/build/jvm/share/truffle --add-modules org.graalvm.truffle,org.graalvm.truffle.runtime -Xbootclasspath/a:"<the runner's boot entries>" -cp "nqp/build/jvm/share/lib:nqp/build/jvm/share/runtime/nqp-truffle.jar" org.raku.nqp.runtime.unit.UnitMain nqp/build/jvm/share/lib/nqp.jar -e 'say(6*7)'
```

Expected: `42` (nqp.jar is still a class-file unit here; this proves `loadApp`'s class road and the entry through `UnitMain`).

- [ ] **Step 6: Commit (nqp tree)**

```bash
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git add src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitLoader.kt src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitMain.kt src/vm/jvm/runtime/org/raku/nqp/runtime/LibraryLoader.java src/vm/jvm/runtime/org/raku/nqp/tools/EvalServer.java && git commit -F - <<'EOF'
unit artifact: the bilingual loader (unit.meta picks the road), UnitMain, eval server through loadApp

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRn8gLyZjirBAKS6urb3n4
EOF
```

---

