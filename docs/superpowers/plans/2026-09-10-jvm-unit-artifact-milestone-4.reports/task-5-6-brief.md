### Task 5: The runtime class road deleted

**Files:**
- Delete: `nqp/src/vm/jvm/runtime/org/raku/nqp/jast2bc/JASTCompiler.kt`, `AutosplitMethodWriter.kt`, `JastClass.kt`, `JastMethod.kt`, `JastField.kt`, `JavaClass.kt`; move `BytecodeVersion.kt` to `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/BytecodeVersion.kt` (package `org.raku.nqp.runtime`)
- Delete: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/IndyBootstrap.kt`, `CodeRefAnnotation.kt`
- Delete: `nqp/t/jvm/09-autosplit.t`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt:76` (import), `:8966-8972` (`compilejast`), `:9038-9043` (`compilejasttofile`), `:9044-9100` (`loadcompunit`), `:3269` (comment)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/EvalResult.kt`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CompilationUnit.kt:1-200`, `:201-244`, `:265-345`, `:347`, `:385-470`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/GlobalContext.kt:234-241`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitWriter.kt` (the JAST-typed `record`/`write` pair and the three jast2bc imports), `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/Syscalls.kt:477-491` (`jvm-write-unit`, `jvm-build-unit`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/BootJavaInterop.kt:20`, `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/reprs/P6Opaque.kt:15` (the `BytecodeVersion` import)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/KnowHOWMethods.kt:314` (`getCodeRefs` stays; its return type becomes non-null)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CodeEngine.kt:72` (comment), `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitFormat.kt:13` (comment)
- Modify: `nqp/tools/templates/jvm/Makefile.in:21` (the `jast2bc/*.java` line)
- Test: runtime jars + `:nqp-runtime:test`; t/nqp; `t/01-sanity`

**Interfaces:**
- Consumes: Task 4's stage0 (no gradle build reaches `compilejast`, `loadcompunit`'s define branch, the sidecar reader, `setLexValuesBulk` or `enterFromMain` any more); the adaptors still generate a `CompilationUnit` subclass through the reflective initializer until Task 7 -- so THIS task keeps `getCodeInfo`, `codeInfoStash`, `ReflectiveCodeInfo`, `CodeRefAnnotation` and the reflective half of `initializeCompilationUnit` (they go in Task 7, with their last client). Everything else on the list goes here.
- Produces: `CompilationUnit` with `getCodeRefs(): Array<CodeRef>` as the non-reflective hook; `EvalResult` with `record` and `cu` only; `Ops.loadcompunit` on the record road only; `org.raku.nqp.runtime.BytecodeVersion`.

- [ ] **Step 1: jast2bc.** `git mv nqp/src/vm/jvm/runtime/org/raku/nqp/jast2bc/BytecodeVersion.kt nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/BytecodeVersion.kt` (from the nqp dir, paths relative to it), change its package line to `package org.raku.nqp.runtime`, fix the two imports (`BootJavaInterop.kt:20` becomes unnecessary in the same package: delete the line; `P6Opaque.kt:15` becomes `import org.raku.nqp.runtime.BytecodeVersion`). `git rm -r src/vm/jvm/runtime/org/raku/nqp/jast2bc`. In `UnitWriter.kt` delete the three `org.raku.nqp.jast2bc` imports and the `record(jast, jastNodes, tc)` / `write(jast, jastNodes, filename, tc)` pair; in `Syscalls.kt` delete `jvm-write-unit` and `jvm-build-unit` (the `-record` pair from Task 1 stays).

- [ ] **Step 2: Ops and EvalResult.** Delete `compilejast`, `compilejasttofile` and the `JASTCompiler` import; `loadcompunit` becomes:

```kotlin
    /** Turns a runtime compile's record into a live unit: a ProgramUnit
     *  built from the record, initialized under the compilee's HLL config
     *  when asked, and retained for nested embedding while a compilation
     *  is under way. */
    @JvmStatic
    fun loadcompunit(obj: SixModelObject?, compileeHLL: Long, tc: ThreadContext): SixModelObject? {
        try {
            val res = obj as EvalResult
            val rec = res.record
                ?: throw ExceptionHandling.dieInternal(tc, "loadcompunit: no unit record to load")
            val u = org.raku.nqp.runtime.unit.ProgramUnit(rec)
            u.shared = false
            res.cu = u
            val unitName = rec.meta.unitId
            if (System.getenv("NQP_CODE_WHY") != null)
                System.err.println("unit record $unitName (${rec.programs.size} programs, ${rec.meta.blocks.size} qbids)")
            if (compileeHLL != 0L)
                usecompileehllconfig(tc)
            u.initializeCompilationUnit(tc)
            if (compileeHLL != 0L)
                usecompilerhllconfig(tc)
            /* A unit compiled while a compilation is under way may be a
             * nested unit whose code refs the enclosing serialization
             * points into; retain what embedding it later needs. */
            if (!tc.compilingSCs.isNullOrEmpty()) {
                tc.gc.inMemoryUnitRecords[unitName] = rec
                u.codeRefs?.let { crs ->
                    for (cr in crs) {
                        val cuid = cr.staticInfo.uniqueId
                        if (!cuid.isNullOrEmpty())
                            tc.gc.inMemoryUnitOfCuid[cuid] = unitName
                    }
                }
            }
            res.record = null
            return obj
        }
        catch (e: ControlException) {
            throw e
        }
        catch (e: Exception) {
            throw RuntimeException(e)
        }
    }
```

`EvalResult.kt`: delete the `JavaClass` import and the `jc` field; reword the doc comment ("a runtime compile's record before and after loadcompunit"). `GlobalContext.kt`: delete `inMemoryUnitBytes` and its comment; keep `inMemoryUnitOfCuid` and `inMemoryUnitRecords` (reword the comment at `:236-240`). `Ops.kt:3269`: drop the indy-budget sentence. Check `Ops.jvmclassofcuid` (near `:8975`) reads only `inMemoryUnitOfCuid`.

- [ ] **Step 3: CompilationUnit.** Delete `enterFromMain` and `setupCompilationUnit` (`:20-43`); `setLexValues`/`setLexValuesBulk`/the private `setLexValues` (`:281-345`); the class bodies of `serializedBlob` and `claimNested` (`:390-409`), which become `abstract`; `engineProgram`'s class body and `loadEnginePrograms` with the `enginePrograms` field (`:410-470`): `engineProgram(idx: Int): String` becomes `abstract`; `lookupCodeRef(uniqueId: String)` keeps its map body (the `getCodeRefs()` units need it: KnowHOWMethods, the adaptors after Task 7) and loses the `/*FOR_STAGE0*/` mark; `unitId()`'s body becomes `abstract`. `getCodeRefs()` becomes `open fun getCodeRefs(): Array<CodeRef> = arrayOf()` and the fallback branch in `initializeCompilationUnit` (`:158-166`) keeps using it. `IndyBootstrap.kt` deleted (`grep -rn IndyBootstrap nqp/src src` must show only comments in `SixModelObject.kt:17,29`: reword them). `KnowHOWMethods.kt:314`: `override fun getCodeRefs(): Array<CodeRef>` (drop the `?`). `ProgramUnit.kt` gains `override fun engineProgram`, `serializedBlob`, `claimNested`, `unitId` as it already has them (only the `override` modifiers may need the abstract base's signatures: check they compile).

- [ ] **Step 4: Tests and templates.** `git rm t/jvm/09-autosplit.t` (nqp dir); `jvm/Makefile.in:21` delete the `jast2bc/*.java` line. Comments: `CodeEngine.kt:72` and `UnitFormat.kt:13` lose the sidecar sentence.

- [ ] **Step 5: Runtime jars**: `./nqp/gradlew -p nqp :nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars`. Expected BUILD SUCCESSFUL. Compile errors here name every reference the inventory missed: fix them in this task (report each).

- [ ] **Step 6: t/nqp + t/qast** (`t5-sweep`) and `t/01-sanity` (`t5-sanity`, Task 3 Step 4's command). Expected 118/118, 1/2, 25/25. Restart any eval server.

- [ ] **Step 7: Leftover grep**: `grep -rn 'jast2bc\|JASTCompiler\|compilejast\|MemoryClassLoader\|codeprograms\|setup_blv\|setLexValues\|enterFromMain\|IndyBootstrap\|inMemoryUnitBytes' nqp/src src tools nqp/tools nqp/t t` must be empty (docs excepted until Task 11).

- [ ] **Step 8: Commit (nqp)**: `git add -A src/vm/jvm/runtime src/vm/jvm/runtime/org/raku/nqp/runtime/BytecodeVersion.kt t/jvm tools/templates/jvm/Makefile.in && git commit -m "runtime: the class road's writer and loaders are gone -- jast2bc, compilejast, loadcompunit's define branch, the sidecar reader, setLexValues, enterFromMain, IndyBootstrap; BytecodeVersion moves to runtime/"`.

---

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

