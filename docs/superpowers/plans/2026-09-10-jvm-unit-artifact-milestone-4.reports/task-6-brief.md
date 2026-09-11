### Task 6: The loader in Kotlin (LibraryLoader.java deleted)

**Files:**
- Delete: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/LibraryLoader.java` (590 lines)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitLoader.kt` (grows `load`, `loadApp`, `prime`, `readToHeapBuffer`, `readToHeapBufferLz4`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/GlobalContext.kt` (a `loadedUnits` set replacing `ByteClassLoader.addRef` for unit paths), `ByteClassLoader.kt` (`addRef`/`refs` deleted; `getMade`/`setMade`/`getRead`/`setRead` deleted if only `LibraryLoader` used them: grep)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt:7942-7955` (`loadbytecode`, `loadbytecodebuffer`), `CompilationUnit.kt` (no `LibraryLoader.readToHeapBuffer*` left after Task 5: verify), `unit/UnitMain.kt:4,15`, `unit/ProgramUnit.kt` (unchanged), `tools/EvalServer.java:33,75,126,238`
- Modify: rakudo `src/vm/jvm/runtime/org/raku/rakudo/RakudoEvalServer.java` (42 lines; its `LibraryLoader` references, if any)
- Test: runtime jars; t/nqp; `t/01-sanity`; one eval-server smoke (`t/harness5 --jvm --evalserver` on `t/01-sanity/01-tap.t`)

**Interfaces:**
- Consumes: Task 5's `CompilationUnit`; `UnitZip.isUnit`, `UnitLoader.isUnitFile`, `loadUnit`, `loadAndRun`, `record` (existing).
- Produces: `UnitLoader.load(tc, filename: String)`, `load(tc, bytes: ByteArray)`, `load(tc, buffer: ByteBuffer)`, `loadApp(tc, path, shared): CompilationUnit`, `prime(path)`, `readToHeapBuffer(InputStream)`, `readToHeapBufferLz4(InputStream)`; `GlobalContext.loadedUnits: MutableSet<String>`.

- [ ] **Step 1**: port into `UnitLoader` (object) the road-agnostic survivors of `LibraryLoader.java:32-112`, `:198-233`, `:235-250`, without the class branches:

```kotlin
    /** nqp::loadbytecode: a unit by path, once per GlobalContext. The
     *  ModuleLoader.class name is special-cased as it always was: the
     *  first unit is probed for on the classpath as ModuleLoader.class,
     *  then ModuleLoader.jar (an artifact since milestone 1). */
    @JvmStatic
    fun load(tc: ThreadContext, filename0: String) {
        var filename = filename0
        if (!tc.gc.loadedUnits.add(filename)) return
        try {
            var file = File(filename)
            if (!file.isFile && filename == "ModuleLoader.class") {
                for (cp in System.getProperty("java.class.path").split(Regex("[:;]"))) {
                    file = File("$cp/$filename")
                    if (file.isFile) { filename = "$cp/$filename"; break }
                    file = File("$cp/ModuleLoader.jar")
                    if (file.isFile) { filename = "$cp/ModuleLoader.jar"; break }
                }
            }
            if (!isUnitFile(filename))
                throw ExceptionHandling.dieInternal(tc, "loadbytecode: $filename is not a unit artifact")
            loadAndRun(tc, filename, tc.gc.sharingHint)
        } catch (e: ControlException) {
            throw e
        } catch (e: Exception) {
            if (e is RuntimeException && e.javaClass.name.startsWith("org.raku.nqp")) throw e
            throw ExceptionHandling.dieInternal(tc, e)
        }
    }

    @JvmStatic
    fun load(tc: ThreadContext, buffer: ByteArray) {
        if (!UnitZip.isUnit(ByteBuffer.wrap(buffer)))
            throw ExceptionHandling.dieInternal(tc, "loadbytecodebuffer: the buffer is not a unit artifact")
        loadAndRun(tc, buffer)
    }

    @JvmStatic
    fun load(tc: ThreadContext, buffer: ByteBuffer) {
        val bytes = if (buffer.hasArray() && buffer.arrayOffset() == 0 && buffer.position() == 0
                        && buffer.array().size == buffer.remaining()) buffer.array()
                    else ByteArray(buffer.remaining()).also { buffer.duplicate().get(it) }
        load(tc, bytes)
    }

    /** Road-agnostic app load for entry points (runner main, eval server):
     *  initialized (deserialized) but its load block not run; an entry
     *  block does that itself. */
    @JvmStatic
    fun loadApp(tc: ThreadContext, path: String, shared: Boolean): CompilationUnit {
        if (!isUnitFile(path, shared))
            throw ExceptionHandling.dieInternal(tc, "$path is not a unit artifact")
        return loadUnit(tc, path, shared)
    }

    /** Warms the shared record cache, so a server pays for parsing once. */
    @JvmStatic
    @Throws(IOException::class)
    fun prime(path: String) { record(path, true) }

    @JvmStatic
    @Throws(IOException::class)
    fun readToHeapBuffer(input: InputStream): ByteBuffer = ByteBuffer.wrap(input.readAllBytes())

    /* safeInstance(), not fastestInstance(): the Unsafe fast path is
     * deprecated for removal (JEP 498). */
    private val lz4 = LZ4DecompressorWithLength(LZ4Factory.safeInstance().fastDecompressor())

    @JvmStatic
    @Throws(IOException::class)
    fun readToHeapBufferLz4(input: InputStream): ByteBuffer = ByteBuffer.wrap(lz4.decompress(input.readAllBytes()))
```

Keep whatever error-wrapping `LibraryLoader.load` did for `IllegalStateException`/`IllegalArgumentException` from `UnitZip.read` (they become `dieInternal`); check who reads `readToHeapBuffer*` after Task 5 (`UnitZip`, `ProgramUnit`?) and repoint the callers. `GlobalContext.kt`: `@JvmField val loadedUnits: MutableSet<String> = java.util.concurrent.ConcurrentHashMap.newKeySet()` beside `inMemoryUnitOfCuid`. `ByteClassLoader.kt`: delete `refs`/`addRef`; delete `read`/`made`/`getMade`/`setMade`/`getRead`/`setRead` only if `grep -rn 'getMade\|setMade\|getRead\|setRead' nqp/src src` is empty after `LibraryLoader` goes (keep `defineClass`, which P6Opaque and the adaptors use, and the memoization it needs).

- [ ] **Step 2**: repoint: `Ops.loadbytecode` / `loadbytecodebuffer` -> `org.raku.nqp.runtime.unit.UnitLoader.load(...)`; `UnitMain.kt` -> `UnitLoader.loadApp`; `EvalServer.java:75,238` -> `UnitLoader.loadApp(...)`, `:126` -> `UnitLoader.prime(mainPath)` (the `gc.byteClassLoader` argument goes; the surrounding comment about "loading needs a class loader" is rewritten: the server holds a GlobalContext for its shared record cache); `RakudoEvalServer.java` likewise if it names `LibraryLoader`. `git rm src/vm/jvm/runtime/org/raku/nqp/runtime/LibraryLoader.java` (nqp dir).

- [ ] **Step 3**: runtime jars (`:nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars`). Expected BUILD SUCCESSFUL. Note: rakudo's `RakudoEvalServer.java` compiles in rakudo's make, not here; if it changed, `make` in Task 11 covers it, and a quick `javac` check is `./nqp/gradlew`-independent: skip, the make is the gate.

- [ ] **Step 4**: t/nqp + t/qast (`t6-sweep`); `t/01-sanity` (`t6-sanity`); the eval-server smoke: `RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/25fa1a35/tmp/t6-evalserver.log -- perl t/harness5 --jvm --evalserver t/01-sanity/01-tap.t t/01-sanity/02-counter.t` (restart/kill any running server first; `docs/jvm-eval-server.md` has the server lifecycle). Expected 118/118, 1/2, 25/25, 2/2 files.

- [ ] **Step 5**: leftover grep: `grep -rn 'LibraryLoader\|byteClassLoader.addRef\|JarFileClassLoader\|FileClassLoader\|StreamClassLoader\|SerialClassLoader' nqp/src src` empty.

- [ ] **Step 6**: Commit (nqp): `git add -A src/vm/jvm/runtime && git commit -m "runtime: the loader is Kotlin and knows one road -- LibraryLoader.java and its four class loaders are gone; UnitLoader loads, primes and reads"`; rakudo, if `RakudoEvalServer.java` changed: `git add src/vm/jvm/runtime/org/raku/rakudo/RakudoEvalServer.java && git commit -m "JVM eval server: enters through UnitLoader"`.

---

