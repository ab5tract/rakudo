# Task 7 report: the interop adaptors on plain method handles

Status: **COMPLETE**. Commits: nqp `14df06863`, rakudo `09f349adda`.

The generated Java-interop adaptor classes are no longer `CompilationUnit`
subclasses and carry no annotations. A hand-written Kotlin `AdaptorUnit`
supplies their code refs through the `getCodeRefs()` hook, the same road
`KnowHOWMethods` takes, and the reflective code-ref road in
`CompilationUnit.kt` (plus `CodeRefAnnotation.kt`, its last client) is
deleted.

## What changed, per file

### nqp: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/AdaptorUnit.kt` (new, 41 lines)

`class AdaptorUnit(cls: Class<*>, descriptors: List<String>, target: String) :
CompilationUnit()`.

`getCodeRefs()` takes a `MethodHandles.lookup()` and a `MethodType` of
`(CompilationUnit, ThreadContext, CodeRef, CallSiteDescriptor, Object[])void`,
then for each descriptor index `i` does `l.findStatic(cls, "qb_$i",
mt).bindTo(this)` and wraps it in a `CodeRef(this, mh, name, name, null,
null, null, null, arrayOf<LongArray>(), 0.toShort())` with `name = "callout
$target ${descriptors[i]}"` (the exact string the deleted annotation used to
carry, so nothing downstream sees a different name). No lexicals, no
handlers, args expectation 0. `findStatic` is wrapped so a
`ReflectiveOperationException` surfaces as a `RuntimeException` rather than a
checked-exception leak.

`getCallSites()` returns `emptyArray()` (the adaptor bodies build their
`CallSiteDescriptor`s as emitted constants through `emitConst`, never through
the unit's callsite table; the deleted `compunitMethods` returned `null`
there and nothing read it). `hllName()` returns `""`. `unitId()` returns
`cls.name` — more useful on a diagnostic path than the `javaClass.simpleName`
default, which would read "AdaptorUnit" for every adaptor.

**Deviation from the brief, per ruling 4**: the brief's `AdaptorUnit` also
overrode `engineProgram`, `serializedBlob` and `claimNested`. Tasks 5+6 left
all three `open` on `CompilationUnit` with `IllegalStateException` bodies
whose message already names the class (`"engineProgram has no meaning on a
${javaClass.simpleName} unit"`), so the overrides would have been pure churn.
They are dropped. All three are only ever called from unit-artifact
deserialization paths (`Ops.kt:6532`, `Ops.kt:8985`, `CodeEngine.kt:82,124`)
that an adaptor unit never reaches.

### nqp: `runtime/CompilationUnit.kt` (314 -> 172 lines)

- Deleted the companion object (`getCodeInfo`, `codeInfoStash`), the private
  `ReflectiveCodeInfo` class, and the `MethodHandle` / `MethodHandles` /
  `java.lang.reflect.Method` / `sixmodel.STable` imports that only they used.
  `java.util.HashMap` is the only surviving import.
- Rewrote the class doc comment (ruling 3): it no longer claims a block turns
  into a method or that generated subclasses override the open methods. It now
  names the three hand-written units — `ProgramUnit` (a block is a unit record
  plus an engine program), `KnowHOWMethods`, `AdaptorUnit` — and states that
  no generated subclass exists, so nothing here is reflected over.
- Rewrote `initializeCompilationUnit(tc, runDeserialize)` as the
  `getCodeRefs()` road only.

`initializeCompilationUnit` after:

```kotlin
    open fun initializeCompilationUnit(tc: ThreadContext, runDeserialize: Boolean) {
        val bootSt = tc.gc.BOOTCode?.st
        val refs = getCodeRefs()
        codeRefs = refs
        qbidToCodeRef = arrayOfNulls<CodeRef>(refs.size).also { t ->
            for (i in refs.indices) t[i] = refs[i]
        }
        for (c in refs) {
            if (bootSt != null) c.st = bootSt
            c.staticInfo.uniqueId?.let { cuidToCodeRef.put(it, c) }
        }

        /* Build callsite descriptors. */
        callSites = getCallSites()

        /* Get HLL configuration object. */
        hllConfig = tc.gc.getHLLConfigFor(this.hllName())

        /* Run any deserialization code, unless the caller wants to run it
         * later itself: a nested unit claimed while its enclosing unit is
         * mid-deserialization must not touch the still-empty SC. */
        if (runDeserialize)
            runDeserializeIfAvailable(tc)
    }
```

Two behaviour notes: the old fallback branch filled `cuidToCodeRef` but left
`qbidToCodeRef` a zero-length array; the new body fills both, and
`lookupCodeRef(Int)` = position in `getCodeRefs()`'s array is what
`computeInterop` reads back (`adaptorUnit.lookupCodeRef(i)` against
`adaptor.descriptors[i]` — same index space by construction). `ProgramUnit`
overrides this method entirely and is untouched; `KnowHOWMethods` used the
old fallback branch and now uses this body, with `qbidToCodeRef` additionally
populated (nothing regressed: `KnowHOWBootstrapper` looks its refs up by
cuid).

### nqp: `runtime/BootJavaInterop.kt`

- `createAdaptor`: superclass is now `"java/lang/Object"` instead of
  `TYPE_CU.getInternalName()`; the `compunitMethods(cc)` call is gone.
  `BytecodeVersion.EMITTED` was already in place here.
- `compunitMethods` (the generated `getCallSites` / `hllName` / `<init>`)
  deleted. The generated class now has no constructor at all, which is legal
  — nothing instantiates it any more.
- `startCallout`: the three `visitAnnotation` lines are gone.
- `computeInterop`: the `try { newInstance() as CompilationUnit } catch
  (ReflectiveOperationException)` block is replaced by
  `AdaptorUnit(adaptor.constructed!!, adaptor.descriptors, klass.getName())`.
- `finishClass` is unchanged: it still sets the plain class's public static
  `constants` field reflectively, which needs no `CompilationUnit` ancestry.
  `TYPE_CU` survives — the `qb_N` descriptor still names `CompilationUnit` as
  the first parameter type, and the bound handle's first argument is the
  `AdaptorUnit`.

### nqp: `runtime/unit/UnitRecord.kt`

The `BlockRec` doc comment named `CodeRefAnnotation`; reworded to "everything
the old per-method code-ref annotation and the `qb_<n>` method name used to
carry".

### nqp: `runtime/CodeRefAnnotation.kt` — deleted (`git rm`).

### rakudo: `src/vm/jvm/runtime/org/raku/rakudo/RakudoJavaInterop.kt`

- `createAdaptor`: `cw.visit(BytecodeVersion.EMITTED, ...,
  "java/lang/Object", null)` (ruling 5 — was `Opcodes.V1_7` and `TYPE_CU`);
  `compunitMethods(cc)` call removed.
- `startVarArityCallout`: the three `visitAnnotation` lines removed. This was
  the only other `qb_` emission site on the Rakudo side (the multi-dispatch
  and constructor-dispatch adaptors both go through it or through the boot
  `startCallout`).
- `computeInterop`: the `newInstance()` block replaced by
  `AdaptorUnit(adaptor.constructed!!, adaptor.descriptors, klass.name)`.
- Imports: `org.raku.nqp.runtime.CompilationUnit` was left unused (only
  `TYPE_CU`, an inherited companion field, referenced the type) and is
  replaced by `org.raku.nqp.runtime.AdaptorUnit` and
  `org.raku.nqp.runtime.BytecodeVersion`.

## Build and gates

| step | result |
| --- | --- |
| `:nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars` | BUILD SUCCESSFUL, 22 s (tests pass) |
| `perl Configure.pl --backends=jvm --gen-nqp` | EXIT=0, 3 s |
| full `make` (from the top, jvm products cleaned) | **EXIT=0, 1185 s** |
| `t/03-jvm` + `t/10-qast` | 2 of 2 ok in 56 s |
| `t/01-sanity` | **25 of 25 ok** in 139 s |

The controller's step-5 replacement was followed: both Kotlin trees were
edited before the make, so the make compiled `RakudoJavaInterop.kt` itself
(marker `[171s] +++ Generating rakudo-runtime.jar (Gradle)`).

**Make total: 1185 s** against the milestone-3 baseline of 1154 s (+2.7 %,
noise for a from-the-top build). **CORE.c window: 622 s -> 1094 s = 472 s**
(marker `[622s] +++ Compiling blib/CORE.c.setting.jar` to `[1094s] +++
Generating gen/jvm/BOOTSTRAP/v6d.nqp`), against milestone 3's 475 s and Task
3's partial-make 462 s. Flat, as expected: this task touches only the interop
road, which no compile stage enters.

### `t/03-jvm/01-interop.t` exact counts

`plan 30`; **30 of 30 ok, 0 failures**, 8 skips, exit 0, 32 s. The skips are
the test's own unconditional `skip` calls, all pre-existing:

- tests 6-8: `IncompatibleClassChangeError` / `java/util/zip/Checksum` (the
  `skip ..., 3` at line 25 — the "3 known skips" the dispatch mentions)
- test 23: `NullPointerException` (line 122)
- tests 27-30: `IllegalArgumentException: object is not an instance of
  declaring class` (line 166, `skip ..., 4`)

Everything the adaptor road actually exercises passes: explicit and multi
static-method callouts (2, 3), explicit and multi constructors (4, 5),
boxed-primitive marshalling for all eight wrapper types (9-22), a less
visible parent method (24), `X::Method::NotFound` on a missing method (25),
and the lazy-list marshalling die (26). Those are the `qb_N` callouts reached
through `AdaptorUnit`'s bound handles.

`t/10-qast/00-misc.t`: ok, exit 0.

`t/01-sanity`: **25/25**. Per ruling 2 this also closes the sanity gate Tasks
5+6 deferred — those tasks left `t/01-sanity` at 0/25 purely because Rakudo's
jars named a stale NQPHLL serialization handle after Task 4 rebuilt nqp's
stage2, and this task's Configure + full make is the rebuild that clears it.
The class road deleted in Tasks 5+6 is therefore verified green here.

## Files changed

nqp tree (commit `14df06863`, 5 files, +64 / -206):

- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/AdaptorUnit.kt` (new)
- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CompilationUnit.kt`
- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/BootJavaInterop.kt`
- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/UnitRecord.kt`
- `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CodeRefAnnotation.kt` (deleted)

rakudo tree (commit `09f349adda`, 1 file, +4 / -13):

- `src/vm/jvm/runtime/org/raku/rakudo/RakudoJavaInterop.kt`

## Self-review

- `grep -rn 'CodeRefAnnotation\|ReflectiveCodeInfo\|codeInfoStash\|getCodeInfo\|compunitMethods' nqp/src src`
  — **empty** (exit 1). Only `docs/` still names them, as allowed.
- `grep -n 'visitAnnotation\|CodeRefAnnotation' src/vm/jvm/runtime/org/raku/rakudo/RakudoJavaInterop.kt`
  — empty.
- Gates at the expected counts (table above); interop 30/30 with the
  pre-existing skips, sanity 25/25.
- Nothing beyond the brief and the rulings: no `abstract` churn on
  `serializedBlob`/`claimNested`/`engineProgram` (ruling 4), `unitId()`'s
  default untouched on `CompilationUnit`, no wire change, no new logging
  (nothing in this change prints).
- Kotlin only; no Java added.

## Concerns

1. **`CompilationUnit.shared` is now write-only.** Its only reader was the
   `codeInfoStash` branch this task deleted. `UnitLoader.kt:45,59`,
   `ProgramUnit.kt:130` and `Ops.kt:9041` still set it and nothing reads it.
   Deleting the field is outside this task's brief, so it stays; a later
   deletion task should sweep it.
2. **The generated adaptor class has no `<init>`.** Legal, and nothing
   instantiates it, but a future reader of `finishClass` may be surprised that
   `defineClass` returns a class that cannot be constructed. The `constants`
   static write is the only reflective touch that remains.
3. **`AdaptorUnit.getCodeRefs()` is called once**, from
   `initializeCompilationUnit`, so the `findStatic` cost is paid once per
   interop'd Java class, as the reflective `getDeclaredMethods` scan was. No
   caching was added and none is needed; `computeInterop` already caches the
   whole interop hash per class.
4. **The 8 interop skips are hard-coded `if True { skip ... }` blocks in the
   test**, not conditional on the backend, so they cannot regress or improve
   without editing the test. They predate this task and are unrelated to the
   adaptor road (constant-pool and reflection issues in the JDK classes the
   test picks).
