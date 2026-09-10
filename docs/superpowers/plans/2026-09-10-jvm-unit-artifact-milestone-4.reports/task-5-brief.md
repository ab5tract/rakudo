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

