# Tasks 5 + 6 report: the runtime class road deleted, the loader ported to Kotlin

BASE nqp 9844a0de9, rakudo 2e66c36b3d.
Commits (both nqp): `1a658daa1` (Task 5), `4b261b3b2` (Task 6). No rakudo commit
(see "RakudoEvalServer" below).

Diffstat 9844a0de9..4b261b3b2: 31 files, 197 insertions, 24877 deletions.

---

## Task 5: what was deleted, per file

**Deleted outright**

| file | lines |
|---|---|
| `nqp/src/vm/jvm/runtime/org/raku/nqp/jast2bc/JASTCompiler.kt` | 980 |
| `.../jast2bc/AutosplitMethodWriter.kt` | 1772 |
| `.../jast2bc/JastClass.kt` | 138 |
| `.../jast2bc/JastMethod.kt` | 205 |
| `.../jast2bc/JastField.kt` | 35 |
| `.../jast2bc/JavaClass.kt` | 12 |
| `.../runtime/IndyBootstrap.kt` | 587 |
| `nqp/t/jvm/09-autosplit.t` | 20013 |

`jast2bc/BytecodeVersion.kt` was `git mv`'d to
`nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/BytecodeVersion.kt`, package line
changed to `org.raku.nqp.runtime`, doc comment reworded (it no longer claims to
version "compilation units emitted by the JAST compiler"; it versions the plain
generated classes only). The `jast2bc` package directory is gone.

**Modified**

- `runtime/BootJavaInterop.kt:20` — the `org.raku.nqp.jast2bc.BytecodeVersion`
  import deleted (same package now).
- `sixmodel/reprs/P6Opaque.kt:15` — import becomes
  `org.raku.nqp.runtime.BytecodeVersion`.
- `runtime/unit/UnitWriter.kt` — the three `jast2bc` imports and the JAST-typed
  `record(jast, jastNodes, tc)` / `write(jast, jastNodes, filename, tc)` pair
  deleted, together with their private helpers `strs()` and `strList()` (used by
  nothing else) and the now-unused `Ops` import. 157 → 38 lines. This resolves
  Task 1's ledgered minor "duplicated writer body" (ruling 6): the JAST pair was
  the duplicate; no refactor was needed.
- `dispatch/Syscalls.kt` — `jvm-write-unit` and `jvm-build-unit` deleted; the
  `-record` pair kept and its comment rewritten to carry the deleted pair's
  explanation (why a syscall, what "built in memory" is for).
- `runtime/Ops.kt` — `JASTCompiler` import, `compilejast`, `compilejasttofile`
  deleted; `loadcompunit` rewritten to the brief's record-only body verbatim;
  the indy-budget sentence dropped from the `bindWillResumeOnFailure` comment;
  `jvmclassofcuid`'s doc comment no longer names "a class name on the class
  road" (it reads only `inMemoryUnitOfCuid`, as the brief asked me to check —
  confirmed).
- `runtime/EvalResult.kt` — `JavaClass` import and the `jc` field deleted, doc
  comment reworded.
- `runtime/GlobalContext.kt` — `inMemoryUnitBytes` deleted; the surviving
  `inMemoryUnitOfCuid` / `inMemoryUnitRecords` comment rewritten so it no longer
  describes classfiles or "the JAST class name".
- `runtime/CompilationUnit.kt` — 543 → 314 lines. Deleted: `enterFromMain`,
  `setupCompilationUnit`, `setLexValues(tc, localId, toParse)`,
  `setLexValuesBulk`, the private `setLexValues(tc, cr, toParse)`,
  `serializedBlob`'s class-resource body, `claimNested`'s `Class.forName` body,
  `engineProgram`'s memoizing body, `loadEnginePrograms` and its
  `enginePrograms` field, `checkEnginePrograms` (the `NQP_SIDECAR_CHECK`
  verifier — it only checked the deleted sidecar split), and the
  `/*FOR_STAGE0*/` mark on `lookupCodeRef(String)`. `getCodeRefs()` is now
  `open fun getCodeRefs(): Array<CodeRef> = arrayOf()` and the fallback branch
  of `initializeCompilationUnit` uses it without `!!`. Kept per ruling 1: the
  reflective half (`getCodeInfo`, `codeInfoStash`, `ReflectiveCodeInfo`, the
  annotation loop), `CodeRefAnnotation.kt`, `lookupCodeRef(String)`'s map body,
  `lookupCodeRef(Int)`, `runDeserializeIfAvailable`, `runLoadIfAvailable`, the
  abstract `getCallSites`/`hllName`, the qbid accessors.
- `sixmodel/KnowHOWMethods.kt` — **no edit needed**: its override at :314 was
  already `override fun getCodeRefs(): Array<CodeRef>` (non-null, covariant over
  the old nullable base). The brief's "drop the `?`" was already true.
- `runtime/unit/ProgramUnit.kt` — comment only (the `setup_blv` mention in
  `runDeserializeIfAvailable`'s doc). Its four overrides compile unchanged
  against the reshaped base.
- `runtime/CodeEngine.kt:72`, `runtime/unit/UnitFormat.kt:13` — sidecar
  sentences reworded.
- `sixmodel/SixModelObject.kt:17,29` — the two `IndyBootstrap` comment mentions
  reworded (the brief required the `IndyBootstrap` grep to be empty).
- `tools/templates/jvm/Makefile.in:21` — the `jast2bc/*.java` line deleted.

## Ruling 2 outcome: `open` with throwing bodies, not `abstract`

I first made `serializedBlob`, `claimNested`, `engineProgram` and `unitId`
abstract as the brief says. That does not compile: **`KnowHOWMethods` is a
hand-written Kotlin `CompilationUnit` subclass** (`KnowHOWMethods.kt:22`,
`class KnowHOWMethods : CompilationUnit()`) and implements none of the four, so
Kotlin rejects the class. (`ProgramUnit` is the only other subclass and does
override all four.) The generated adaptor subclass would have been the second
casualty at runtime — `BootJavaInterop.compunitMethods` emits only
`getCallSites`, `hllName` and `<init>`.

So, per ruling 2's escape hatch:

- `serializedBlob()`, `claimNested()`, `engineProgram()` stay `open` with bodies
  that throw `IllegalStateException("<method> has no meaning on a
  ${javaClass.simpleName} unit")`. I used the class's own simple name rather
  than the literal phrase "class-road unit", because there is no class road any
  more — the units that hit these are KnowHOWMethods and (until Task 7) the
  adaptors.
- `unitId()` **keeps its old non-throwing default** `javaClass.simpleName`. It
  is not class-road behaviour (no class resource, no `Class.forName`), it is a
  generic identity string, and it is read on diagnostic paths that can carry a
  non-artifact unit: `Ops.kt:6853` (`NQP_REPOINT_TRACE`), `Syscalls.kt:539`,
  `CodeEngine.kt:145`'s "has no program" message. Throwing there would turn a
  trace into a crash. Its doc comment now says which unit gets which answer.

Task 7 finishes the reshape (an `AdaptorUnit` overriding all four makes
`abstract` viable for the three throwers; `unitId()` may reasonably stay `open`).

## Task 6: what was ported, per file

- **Deleted**: `runtime/LibraryLoader.java` (590 lines) — with it
  `SerialClassLoader`, `StreamClassLoader`, `FileClassLoader`,
  `JarFileClassLoader`, `MemoryClassLoader`, `ByteBufferedInputStream`,
  `loadFile`, `loadClass`, `loadJar` (both overloads), `resolveClass`, the
  `sharedClasses` map, and the class branches of `load`/`loadApp`/`prime`.
- **`runtime/unit/UnitLoader.kt`** 59 → 137 lines. Gains `load(tc, String)`,
  `load(tc, ByteArray)`, `load(tc, ByteBuffer)`, `loadApp(tc, path, shared)`,
  `prime(path)`, essentially verbatim from the brief. The `ModuleLoader.class` /
  `ModuleLoader.jar` classpath probe is preserved. Error wrapping preserved: the
  `IOException | IllegalStateException | IllegalArgumentException` that
  `UnitZip.read` and the unit build can raise become `dieInternal`, while a
  `ControlException` and any `org.raku.nqp.*` RuntimeException (i.e. an already
  formed NQP-level exception) pass through untouched. I added the same guard to
  `load(tc, ByteArray)` and `loadApp`, which the brief's snippet left bare —
  without it an `IllegalStateException` from `UnitZip.read` on the buffer/app
  road escapes as a raw Java exception where the Java original produced a
  `dieInternal`.
- **`runtime/GlobalContext.kt`** — `@JvmField val loadedUnits: MutableSet<String>
  = ConcurrentHashMap.newKeySet()`, beside `inMemoryUnitOfCuid` (ruling 4). It
  is per-GlobalContext, exactly as `ByteClassLoader.refs` was.
- **`runtime/ByteClassLoader.kt`** — `refs`/`addRef` deleted; `read`,
  `getRead`, `setRead` deleted (grep after LibraryLoader went: no other caller);
  `made`/`getMade`/`setMade` **kept**, because `defineClass` memoizes through
  them, and `defineClass` stays (ruling 3: P6Opaque `:638` and
  `BootJavaInterop.finishClass` define plain ASM classes through it). Class doc
  added saying what it is for now.
- **`runtime/Ops.kt`** — `loadbytecode` / `loadbytecodebuffer` repointed to
  `UnitLoader.load`.
- **`runtime/unit/UnitMain.kt`** — `LibraryLoader` import gone, `loadApp` via
  `UnitLoader`, doc comment's "Either road: the loader decides" dropped.
- **`tools/EvalServer.java`** — import swapped for
  `org.raku.nqp.runtime.unit.UnitLoader`; `:75` and `:238` call
  `UnitLoader.loadApp`; `:126` is `UnitLoader.prime(mainPath)` with the
  `gc.byteClassLoader` argument gone and the surrounding comment rewritten ("the
  app unit is parsed once here and its record reused ... the server holds a
  GlobalContext of its own"). Edited, not rewritten, per the constraint.

### RakudoEvalServer

`rakudo/src/vm/jvm/runtime/org/raku/rakudo/RakudoEvalServer.java` does **not**
name `LibraryLoader`, `loadApp`, `prime` or `byteClassLoader` (grep is empty);
it subclasses/launches nqp's `EvalServer`. **No rakudo edit and no rakudo commit
was needed** (ruling 5's conditional did not fire).

## References the compile surfaced beyond the briefs' lists

Only one, and it was trivial:

```
Ops.kt:7948:59 Argument type mismatch: actual type is 'ByteArray?', but 'ByteArray' was expected.
Ops.kt:7950:59 (same)
```

`VMArrayInstance_i8.slots` / `_u8.slots` are nullable; Java's `LibraryLoader.load`
took a platform type, the Kotlin `UnitLoader.load(tc, ByteArray)` does not. Fixed
with `buffer.slots!!` (and `filename!!` on the path overload, for the same
reason). No other reference the inventory missed — one compile, two errors, then
BUILD SUCCESSFUL.

Two things the briefs' file lists did not mention, found by their own leftover
greps and fixed here:

1. **`nqp/src/vm/jvm/QAST/Compiler.nqp:1151-1152`** still registered
   `map_classlib_core_op('compilejast', …)` and `('compilejasttofile', …)`.
   Task 5's Step 7 grep names `compilejast`, so these two lines had to go; they
   mapped ops whose `Ops` methods this task deletes, so they were dead either
   way. (Registry data only — no rebuild implied; the next `buildJvm` picks it
   up.)
2. **`nqp/src/vm/jvm/QAST/TruffleEncoder.nqp:60`** named `setup_blv` in the
   "deliberately absent" op list; Step 7 greps `setup_blv`. Comment reworded.

And one stale comment outside the grep list, in a file the briefs did not name:
**`nqp/buildSrc/src/main/kotlin/NqpDeps.kt:41-45`** justified keeping `asm-tree`
on the runner classpath by `AutosplitMethodWriter` and `t/jvm/09-autosplit.t`,
both deleted here. I reworded it to say the entry is now vestigial. I did
**not** remove the `asm-tree` dependency itself — nothing in the tree imports
`org.objectweb.asm.tree` any more, but dropping a classpath jar is beyond these
briefs; it is a free cleanup for a later task.

## Two things deliberately NOT ported (with evidence)

`readToHeapBuffer(InputStream)` / `readToHeapBufferLz4(InputStream)` are in the
Task 6 brief's "Produces" list and ruling 7 asks me to repoint their callers.
**After Task 5 there are no callers.** Ruling 7 names three candidates:

- `CompilationUnit.kt` — its two uses were inside `serializedBlob`'s class-road
  body and `loadEnginePrograms`, both deleted by Task 5.
- `UnitZip.kt`, `ProgramUnit.kt` — never called them (`UnitFormat` has its own
  `LZ4DecompressorWithLength`; `ProgramUnit` holds the blob in the record).

`grep -rn readToHeapBuffer nqp/src src` after the port is empty. Rather than
carry two public helpers no code reaches, I left them out. Say the word and they
are three lines to restore.

## Grep results (self-review)

Task 5 Step 7, over `nqp/src src tools nqp/tools nqp/t t`:

```
grep -rn 'jast2bc\|JASTCompiler\|compilejast\|MemoryClassLoader\|codeprograms\|\
setup_blv\|setLexValues\|enterFromMain\|IndyBootstrap\|inMemoryUnitBytes'
→ (no output)
```

Task 6 Step 5, over `nqp/src src`:

```
grep -rn 'LibraryLoader\|byteClassLoader.addRef\|JarFileClassLoader\|\
FileClassLoader\|StreamClassLoader\|SerialClassLoader'
→ (no output)
```

Also empty: `getMade|setMade|getRead|setRead` outside `ByteClassLoader.kt` (the
two survivors are used only by `defineClass`), and `readToHeapBuffer`.
Docs under `nqp/docs` and `docs/` are untouched, as the briefs allow (Task 11).

## Gate results

| gate | expected | got |
|---|---|---|
| `:nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars` | BUILD SUCCESSFUL | **BUILD SUCCESSFUL** (8 s); `:nqp-runtime:test` green (`UnitFormatTest`, `ProgramUnitTest`) |
| t/nqp + t/qast sweep (`t56-sweep`) | 118/118, 1/2 | **117 of 120** in 377 s: t/nqp 116/118 with FAILs `019-file-ops.t` and `063-slurp.t` — exactly the documented cwd-relative pair that passes from the nqp dir, i.e. **118/118**; t/qast **1/2** (`01-qast.t` is the known moar-only red) |
| eval-server smoke | 2/2 files | **2/2** — see below, run against nqp's server rather than rakudo's |
| `t/01-sanity` (`t56-sanity`) | 25/25 | **0/25 — pre-existing, not caused by this task.** See below. |

### t/01-sanity: a stale Rakudo build, proven

All 25 files die identically before any test runs:

```
Unhandled exception: java.lang.RuntimeException: Missing or wrong version of
dependency '…/nqp/build/jvm/stage2/NQPHLL.nqp'
  in <anon> (gen/jvm/ModuleLoader.nqp:91)
```

That message comes from `SerializationReader.resolveDependencies` (:292), which
this task does not touch: the artifact loaded fine and the deserializer found
that the SC handle it depends on is not registered.

Chronology: Rakudo's artifacts are from Task 3's make — `blib/Perl6/*.jar`
mtimes 14:02–14:04, rakudo `2e66c36b3d` committed 14:38. Task 4 then rebuilt all
of nqp and regenerated stage0 — `nqp/build/jvm/stage2/*.jar` mtimes 14:52–14:53,
nqp `9844a0de9` committed 15:06. A rebuilt `NQPHLL.jar` carries a new SC handle,
so every Rakudo jar compiled against the old one is stale. Task 3's report
recorded sanity 25/25; Task 4 ran only t/nqp and would not have seen this.

Direct proof, independent of `rakudo-j` and of this task's loader: loading a
Rakudo artifact from the **nqp** toolchain (where NQPHLL is loaded at startup
and its SC is definitely registered) fails with the same message:

```
$ RAKUDO_RAKUAST=1 nqp/nqp-j-gradle …/t56-probe.nqp     # nqp::loadbytecode("blib/Perl6/ModuleLoader.jar")
java.lang.RuntimeException: Missing or wrong version of dependency
  '…/nqp/build/jvm/stage2/NQPHLL.nqp'
```

The loader loaded the artifact; the (untouched) deserializer rejected the
handle. The gate needs the Rakudo `make` that Task 7/11 runs; the briefs forbid
one here, so I did not run it.

I could not run the cheaper "rebuild the pre-change runtime jars and re-test"
isolation — `git checkout <sha> -- src/vm/jvm/runtime` was refused by the
permission classifier — so the probe above is the isolation evidence.

### Eval-server smoke

Rakudo's `rakudo-eval-server` loads `rakudo.jar`, which is stale for the reason
above, so the brief's `t/harness5 --jvm --evalserver` smoke could only have
reproduced that. I ran the equivalent smoke against **nqp's** `EvalServer` —
which is the file this task edits — with `nqp.jar` as `-app`:

- server started: `UnitLoader.prime(mainPath)` parsed the app record, cookie
  file written;
- `eval-client.pl … run nqp/t/nqp/001-literals.t` → `1..9`, 9 ok;
- `eval-client.pl … run nqp/t/nqp/024-module.t` → `1..3`, 3 ok (this one drives
  `nqp::loadbytecode` through ModuleLoader, so it exercises `UnitLoader.load`
  and the new `GlobalContext.loadedUnits` set);
- `eval-client.pl … exit` → clean shutdown.

2/2 files. No eval server was running before or after (checked with `pgrep`);
the runtime jars were rebuilt before the smoke.

## Files changed

Task 5 commit `1a658daa1` (24 files): `buildSrc/src/main/kotlin/NqpDeps.kt`,
`src/vm/jvm/QAST/Compiler.nqp`, `src/vm/jvm/QAST/TruffleEncoder.nqp`,
`src/vm/jvm/runtime/org/raku/nqp/dispatch/Syscalls.kt`, the six `jast2bc/*.kt`
deletions, the `BytecodeVersion.kt` move, `runtime/BootJavaInterop.kt`,
`runtime/CodeEngine.kt`, `runtime/CompilationUnit.kt`, `runtime/EvalResult.kt`,
`runtime/GlobalContext.kt`, `runtime/IndyBootstrap.kt` (deleted),
`runtime/Ops.kt`, `runtime/unit/ProgramUnit.kt`, `runtime/unit/UnitFormat.kt`,
`runtime/unit/UnitWriter.kt`, `sixmodel/SixModelObject.kt`,
`sixmodel/reprs/P6Opaque.kt`, `t/jvm/09-autosplit.t` (deleted),
`tools/templates/jvm/Makefile.in`.

Task 6 commit `4b261b3b2` (7 files): `runtime/LibraryLoader.java` (deleted),
`runtime/ByteClassLoader.kt`, `runtime/GlobalContext.kt`, `runtime/Ops.kt`,
`runtime/unit/UnitLoader.kt`, `runtime/unit/UnitMain.kt`,
`tools/EvalServer.java`.

**The split is clean at file level** — `Ops.kt` and `GlobalContext.kt` carry both
tasks' changes, so I staged each file's Task-5 half for the first commit (Ops.kt
still calling `LibraryLoader.load`, GlobalContext without `loadedUnits`) and its
Task-6 half for the second. As the controller warned, the Task 5 commit does not
compile on its own: `LibraryLoader.java` is still present there and calls the
`CompilationUnit.setupCompilationUnit` that commit deletes. That is the reason
the two tasks were one dispatch; the second commit restores a building tree.

## Line counts

| file | before | after |
|---|---|---|
| `runtime/CompilationUnit.kt` | 543 | 314 |
| `runtime/unit/UnitLoader.kt` | 59 | 137 |
| `runtime/unit/UnitWriter.kt` | 157 | 38 |
| `runtime/LibraryLoader.java` | 590 | 0 |
| `runtime/ByteClassLoader.kt` | 59 | 35 |
| `jast2bc/` (7 files) | 3157 | 0 (15 moved to `runtime/BytecodeVersion.kt`) |

## Self-review

- Both leftover greps empty (docs excepted). ✅
- `:nqp-runtime:test` green; runtime + truffle jars built and synced. ✅
- t/nqp 118/118, t/qast 1/2 — at the expected counts. ✅
- eval-server smoke 2/2 (nqp's server; rakudo's is unrunnable, see above). ⚠️
- `t/01-sanity` 0/25 — pre-existing stale Rakudo build, proven independently of
  this task; it needs the Rakudo make of Task 7/11. ⚠️
- Kotlin for all new code; `EvalServer.java` edited, not rewritten. ✅
- No wire change; `UnitRecord.kt` untouched; `RecordReader.kt` untouched. ✅
- No `NQP_CODE_RUN` / `NQP_CODE_PRECOMP` set anywhere; `RAKUDO_RAKUAST=1` on
  every run. ✅
- Every diagnostic in the touched code is env-gated (`NQP_CODE_WHY` in
  `loadcompunit` and `UnitWriter.write`); I added no print. ✅
- No nqp clean build, no Rakudo make. ✅

## Concerns

1. **`t/01-sanity` cannot be green until a Rakudo make.** Task 7 (adaptors) has
   `t/03-jvm/01-interop.t` + `t/01-sanity` as its gate and will hit the same
   wall; whoever runs it should expect to run the make first, or accept the same
   evidence. This is the single most important thing to carry forward.
2. **Ruling 2 came out `open`-with-throws, not `abstract`** (details above),
   because `KnowHOWMethods` is a real Kotlin subclass the brief did not account
   for. Task 7 should revisit: once `AdaptorUnit` exists, only `KnowHOWMethods`
   blocks `abstract` on `serializedBlob`/`claimNested`/`engineProgram`, and
   three one-line overrides there would finish the reshape.
3. **The adaptors were not exercised.** `t/03-jvm/01-interop.t` is Task 7's gate
   and I did not run it, so the claim "the generated subclass still initializes
   through the surviving reflective road" rests on reading, not on a test. The
   reflective half is byte-for-byte unchanged, and `getCodeRefs()`'s new
   non-null empty default is only reached when no annotation was found (the
   adaptors always have annotations), so the risk is low — but it is untested.
4. **`asm-tree` is now dead weight** on the runner classpath and in
   `Makefile.in`'s `THIRDPARTY_JARS`. Comment updated, dependency left alone.
5. `readToHeapBuffer*` not ported (no callers left) — see above.
