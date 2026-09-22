# Phase C fix wave — report

Commits: **nqp `a837bf1bb`** (BASE `e3c800371`), **rakudo `6217a89e61`** (BASE `a896b743e0`).
Tests: **50/50** `:nqp-runtime:test` (was 46). Not pushed.

## Per finding

### F1 — Schema version (ruling 25)

- `nqp/src/vm/jvm/runtime/org/raku/nqp/dispatch/DispatchSlot.kt:56-76`:
  `DispatchSlot(val schema: Int, val programs: List<PProgram>)` with a
  `companion object { const val SCHEMA = 1 }`. The KDoc says to bump it on any
  change to the P-types, their field order, their `@SerialName`s, or the
  declaration order of `ArgKind`/`ResumeKind` (persisted by index), and why the
  field is first: `UnitCodec` writes fields in order, fixed-width and untagged,
  so the version is the slot's first four little-endian bytes. The kotlinx
  plugin adds `serializer()` to the user-written companion, so
  `DispatchSlot.serializer()` is unchanged.
- `DispatchPersist.kt:117-127` (restore): before any decode,
  `val schema = if (bytes.remaining() >= 4) bytes.getInt(bytes.position()) else -1`
  (the slice already carries `LITTLE_ENDIAN`); on a mismatch the slot is EMPTY —
  `staleSchema.incrementAndGet()`, a `dispatch-persist: stale schema <n> at
  <identity>` line only under `NQP_DISPATCH_PERSIST_TRACE`, and `emptyList()`.
  The `remaining() >= 4` guard is mine: a truncated slot would otherwise throw
  out of the hand-read rather than be treated as stale.
- `DispatchPersist.kt:64-65`: `@JvmField val staleSchema = AtomicLong()`.
- `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt:596`:
  `" staleSchema=" + DispatchPersist.staleSchema`, directly after `dropped=`.
- Recorder encodes `DispatchSlot(DispatchSlot.SCHEMA, persisted)`
  (`DispatchPersist.kt:283`).
- Makefile half: `tools/templates/jvm/Makefile.in:193` —
  `@bpm(TRAIN_STAMP)@: @bsm(RAKUDO)@@for_specs(...)@ $(RUNTIME_JAR) $(NQP_RUNTIME_JAR)`.
  Both are plain make variables in this template (`RUNTIME_JAR = rakudo-runtime.jar`
  at :77, `NQP_RUNTIME_JAR = @nfp(nqp/build/jvm/share/runtime/nqp-runtime.jar)@`
  at :90), so the same `$(...)` form is used; they are ORDINARY prerequisites,
  unlike `RAKUDO_DEPS_EXTRA`'s order-only `| $(NQP_RUNTIME_JAR)` — retraining is
  one `rakudo -e ''`, not a setting recompile, so the cascade is wanted here.
  The template comment (:160-183) says so.
- Docs: `docs/jvm-unit-lazy-loading.md`, "The slot schema" — the schema int, why
  it is first, the empty-slot behaviour, `staleSchema=`, and that nothing
  migrates because the build that reads a slot wrote it.

### F2 — Error containment in the recorder (rulings 24, 26)

`DispatchPersist.kt:225-310`.

- `recordAtExit()` (`@JvmStatic`, the hook's entry) is now
  `recordAtExit(recordSelector ?: return)` — silent and inert when unarmed. The
  old `selected()` dereferenced `recordSelector!!`, which was the deferred
  minor from Task 5.
- `internal fun recordAtExit(selector: List<String>)` is what the hook and the
  test call; `selected(selector, storeName)` takes the selector as a parameter.
- Per program: `try { DispatchSlotCodec.persist(p) } catch (t: Throwable)` →
  `failed++`, `dispatch-record: FAILED program <path>!<prefix>#<slot>: <class: message>`,
  and the program counts as unpersistable. (The grouping has already lost the
  site identity, so the slot's address is the identity printed.)
- Per path: the whole per-path body — the encode loop and
  `UnitDispatchWriter.rewrite` — is inside `try { } catch (t: Throwable)` →
  `failed++`, `dispatch-record: FAILED <path>: <class: message>`, next path.
  (The encode is inside the same try, so a throwing `UnitCodec.encode` cannot
  kill the run either.) Totals are added only after a successful rewrite.
- Whole body: `try { } catch (t: Throwable)` → `dispatch-record: FAILED: <...>`.
- `finally`: `dispatch-record: done <P> paths, <S> slots, <N> programs, <U> unpersistable, <F> failed`.
- Finding 3 / ruling 26: `dispatch-record: rewriting <path>` per selected path
  before it is touched; `isStage0(path)` (`path.contains("/src/vm/jvm/stage0/") ||
  path.startsWith("src/vm/jvm/stage0/")`) prints
  `dispatch-record: refused <path> (stage0 is never trained)` and skips. `all`
  is unchanged as the builds' selector.
- Markers: `nqp/build.gradle.kts:346-352` —
  `check(text.contains("dispatch-record: done") && !text.contains("dispatch-record: FAILED"))`.
  `Makefile.in:196-197` — `grep -q 'dispatch-record: done' <log>` and, on its own
  TAB-indented `$(NOECHO)` line,
  `if grep -q 'dispatch-record: FAILED' <log>; then exit 1; fi`. The template
  comment above the target explains both.

### F4 — The moved-slot test (ruling 23)

`nqp/nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitDispatchWriterTest.kt:41-64`,
`aGrowingNamedSlotMovesTheUnnamedOnesAndTheyStillReadBack`: the image starts with
`dispatchSlots = mapOf(0 to byteArrayOf(1,2,3), 2 to byteArrayOf(7,7))` (slot 2 is
program 2 ordinal 0 in the shared fixture, whose `dispatchCounts` are `[2,0,1]`),
`rewrite` names only `"unit" to mapOf(0 to ByteArray(8) { 9 })`, and the
assertions are that slot 0 is the eight nines and `dispatchSlot(2, 0)` is still
`7,7` — the unnamed slot had to move from offset 3 to offset 8 and be repointed.

### F5 — Gradle outputs (ruling 27)

`nqp/build.gradle.kts:308-352` (`trainDispatch`):

- marker moved to `jvmDir.file("dispatch-trained.txt")` →
  `nqp/build/jvm/dispatch-trained.txt`, outside `stage2TrainedDir`;
- `inputs.files(<the copied jars>)` and `inputs.file(runtimeJarFile)` kept,
  `outputs.file(marker)` kept;
- `outputs.upToDateWhen { false }` with the comment that this is intentional;
- `classpath = files(engineJarFile)` at configuration time (was
  `files(stage2TrainedDir, engineJarFile)`), so the input snapshot no longer
  includes the directory the task modifies; `doFirst` still builds the real
  class path.
- `syncLib` and `jBootstrapFiles` untouched.

**Deviation, deliberate, please review.** The brief's comment text says "the Sync
restores the untrained jars every build and the training rewrites them, so each
build trains from fresh jars rather than compounding", and the brief's expected
task list for the second build named `stage2Trained`. Neither held once the
marker left the directory: I measured it (buildjvm2.log) — `stage2Trained` was
`UP-TO-DATE`, `stage2-trained/nqp.jar` was still 1221554 bytes against
`stage2/nqp.jar`'s 1145720, and `trainDispatch` therefore retrained ALREADY
trained jars. The always-retrain was emergent in a second way nobody had named:
the marker file sitting inside the Sync's destination made the Sync perpetually
out of date. Removing it removed that too. So `stage2Trained` also got
`outputs.upToDateWhen { false }` (`build.gradle.kts:286-294`) with a comment
saying why. After that the invariant the brief states is true and measured
(build 4 below). If the controller prefers the opposite — leave `stage2Trained`
up-to-date and let training compound (it converges: the second training of
trained jars read 1682 slots against 1683, because the recorder merges restored
∪ new and dedupes by text) — the one-line revert is that `outputs.upToDateWhen`.

### Tests the review asked for

(a) `DispatchSlotCodecTest.everyPersistedFormRoundTrips`
(`nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/DispatchSlotCodecTest.kt:71-131`):
one `DispatchProgram` carrying `PResumeInitArg`, `PAttribute`, `PHow`, `PUnbox`,
`PLookup`, `PResumeState`, `PGuardNotLiteralObj`, `POutcomeSyscall`
(`Syscalls.find(tc, "dispatcher-drop-arg")`), `PResumption` (`boot-value`),
`PLevel` (`lang-call`), `PBind`, a `bindFailure` nested program whose outcome is
`POutcomeValue`, a NUM literal, an OBJ literal, a named descriptor
(`csd[0,10|epsilon]`) and `resumeKind = CALLER`; persisted → encoded → decoded →
realised → compared by `DispatchDump.describe`, plus `assertSame` on the syscall,
both dispatchers and the HLL config (the text names all three by name, so text
equality alone would not catch a wrong object).

(b) `DispatchPersistTest.recordAtExitWritesTheInstalledProgramsIntoTheArtifact`
(`DispatchPersistTest.kt:82-131`): the fixture image written to a temp file with
empty slots, `UnitStore.open(path)`, a unique namespace registered, a
`DispatchCallSite` with `unitNamespace / programIndex=0 / ordinal=1` and one
`site.install(p)`, `DispatchBootstrap.registerSite(site)`, then
`recordAtExit(listOf("all"))` with stderr captured. Asserts: the reopened file's
`dispatchSlot(0, 1)` is non-null, decodes with `schema == SCHEMA` to one program
whose `describe` text matches, and the captured output holds
`dispatch-record: rewriting <path>`, `dispatch-record: wrote 1 slots`,
`dispatch-record: done 1 paths, 1 slots` and no `FAILED`. It also asserts that
the unarmed `recordAtExit()` prints nothing (the review's "no test pins the hook"
minor, in the form this JVM can actually check).

(c) Extra, not in the brief: `DispatchPersistTest.aSlotOfAnotherSchemaIsTreatedAsEmpty`
(`:52-79`) — a slot encoded with `SCHEMA + 1` restores empty, bumps
`staleSchema` and does not bump `restored`.

### Small ones

- `.gitignore:31-32`: `/blib/.dispatch-trained`, `/blib/.dispatch-train.log`.
  (The file mixes both spellings — `blib/Perl6/**/*.js` unanchored, `/gen/*` and
  `/perl6` anchored; I used the anchored form the brief spelled out.)
- `Makefile.in:112-114`: both files appended to the JVM `CLEANUPS` list in its
  existing `\`-continued form, as `@nfp(@bpm(BLIB)@/.dispatch-trained)@` (the same
  macro form `TRAIN_STAMP` itself uses).
- `DispatchSlotCodec.kt:190`: `catch (e: Exception)` → `catch (_: Exception)`.
- `DispatchDump.kt:60,69`: `address(DispatchSlotCodec.ref(x)!!)` →
  `DispatchSlotCodec.ref(x)?.let(::address) ?: "null"` in both `ref` overloads;
  the outer null check already answers `"null"` for a null input, so the two
  agree.

## RED / GREEN evidence

**F4 (a characterisation test — it passes on the code as it stands, which is the
point).** To show it is not vacuous I mutated `UnitDispatchWriter.patch` so an
unnamed slot kept its OLD offset while the named one grew
(`if (newSlots[s] == null) { idx.putInt(row, idx.getInt(row)); ... }`):

```
3 tests completed, 1 failed
aGrowingNamedSlotMovesTheUnnamedOnesAndTheyStillReadBack():
  the unnamed slot moved and still reads back. Array elements differ at index 0.
  Expected element <7>, actual element <9>. Expected <[7, 7]>, actual <[9, 9]>.
```

The mis-repointed slot hands out the grown slot's bytes — exactly the corruption
the review named — and the two pre-existing cases stayed green, so only the new
test sees it. Mutation reverted; `UnitDispatchWriterTest` 3/3.

**The new API tests — RED by compile failure**, before the implementation:

```
e: DispatchPersistTest.kt:37:39 Unresolved reference 'SCHEMA'.
e: DispatchPersistTest.kt:69:37 Unresolved reference 'staleSchema'.
e: DispatchPersistTest.kt:105:67 Too many arguments for 'fun recordAtExit(): Unit'.
e: DispatchPersistTest.kt:110:51 Unresolved reference 'schema'.
e: DispatchSlotCodecTest.kt:21:91 Unresolved reference 'SCHEMA'.
FAILURE: Execution failed for task ':nqp-runtime:compileTestKotlin'
```

After the implementation: `DispatchSlotCodecTest` 5/5, `DispatchPersistTest` 5/5.

**Kitchen sink — proved non-vacuous too.** With `persist` mutated to drop
`bindFailure` (`p.bindFailureProgram?.let { program(it) }` → `null`), the test
failed with the two texts, which incidentally is the coverage evidence:

```
csd[0,10|epsilon] guards=[type(arg(0),st:__6MODEL_CORE__:0);conc(arg(0),true);
lit(arg(1),num:2.5);notlit(arg(0),obj:__6MODEL_CORE__:0);hll(arg(0),nqp)]
outcome=syscall(dispatcher-drop-arg,shape(arg(0),rinit(1,2),lit(num:2.5),
lit(obj:__6MODEL_CORE__:0),attr(arg(0),obj:__6MODEL_CORE__:0,$!count,INT),
how(arg(0)),unbox(arg(0),STR),lookup(lit(obj:__6MODEL_CORE__:0),rstate(0));
csd[0,0,0,0,0,0,0,0])) resumptions=[boot-value:shape(...)] resume=CALLER
levels=[lang-call:csd[0,10|epsilon]:[conc(rinit(0,0),false)]:rstate(0):true]
bind=(3,5,true) bindfail=(... outcome=value(rstate(1)) resume=BIND_FAILURE ...)
```

— every P-type the ruling listed is in that one string. Mutation reverted.

**Whole suite.** `./nqp/gradlew -p nqp :nqp-runtime:test --rerun-tasks`, 18 s,
BUILD SUCCESSFUL; summed over the nine result XMLs: **tests=50 failures=0
errors=0** (was 46). Re-run after the builds: 50/50, green.

## buildJvm

Logs in `/home/longwalker/.claude/jobs/ba3ab3a7/tmp/fixwave/`.

| run | command | wall | executed |
|---|---|---|---|
| 1 | `clean buildJvm` (watched-run) | **223 s** (`BUILD SUCCESSFUL in 3m 43s`) | everything |
| 2 | `buildJvm` | **1 s** | `trainDispatch`, `syncLib` — **`stage2Trained` UP-TO-DATE**, i.e. it retrained already-trained jars (this is what prompted the F5 deviation) |
| 3 | `buildJvm` after the `stage2Trained` fix | 222 s | stage1+stage2 recompiled: `stage1GenVersion`/`stage2GenVersion` re-ran because the build script changed. Pre-existing — any `build.gradle.kts` edit does this, and run 4 (same code, no edit) did not |
| 4 | `buildJvm`, nothing edited since | **1 s** | **`stage2Trained`, `trainDispatch`** and nothing else (`syncLib` UP-TO-DATE, because this retraining came out byte-identical to run 3's) |

Run 1 training: `done 9 paths, 1683 slots, 1711 programs, 41 unpersistable, 0 failed`
(nqpmo 142, NQPP6QRegex 18, QASTNode 38, NQPHLL 117, ModuleLoader 11, QAST 1049,
QRegex 34, nqp 171, NQPCORE.setting 103). Run 4: the same 1683/1711/41.
Run 2 (compounding, before the fix): 1682/1709/40 — the merge converges rather
than growing, which is why nothing had noticed.

Marker `nqp/build/jvm/dispatch-trained.txt` (outside `stage2-trained/`, which now
holds exactly the nine jars) ends:

```
dispatch-record: wrote 103 slots (114 programs, 9 unpersistable) to .../NQPCORE.setting.jar
dispatch-record: done 9 paths, 1683 slots, 1711 programs, 41 unpersistable, 0 failed
```

No `FAILED` line anywhere in it. `share/lib/nqp.jar` == `stage2-trained/nqp.jar`
(1221554 bytes), so `syncLib` took the trained copy.

**nqp stats on the freshly trained lib jars**
(`NQP_DISPATCH_STATS=1 ./nqp-j-gradle -e ''`):

```
dispatch stats: hits=7458 misses=1725 sites=2851 anon=3 sitesAll=2867 restored=1677
restoredSites=1667 dropped=9 staleSchema=0 recorded=87 slowEvals=55 invokes=4924
directs=4915 noTarget=9 badExpectation=0 notCodeRef=0 slowLayout=0 slowNull=25
byKind[value,syscall,mapped,invoke,resumable]=[0, 864, 1679, 4915, 0]
```

`restored=1677` (thousands, as expected), `staleSchema=0`.

No rakudo `make` and no `./rakudo-j` run, per the brief.

## Files changed

nqp (`a837bf1bb`):
`build.gradle.kts`,
`src/vm/jvm/runtime/org/raku/nqp/dispatch/{DispatchSlot,DispatchPersist,DispatchSlotCodec,DispatchDump}.kt`,
`nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt`,
`nqp-runtime/src/test/kotlin/org/raku/nqp/dispatch/{DispatchPersistTest,DispatchSlotCodecTest}.kt`,
`nqp-runtime/src/test/kotlin/org/raku/nqp/runtime/unit/UnitDispatchWriterTest.kt`.

rakudo (`6217a89e61`): `tools/templates/jvm/Makefile.in`, `.gitignore`,
`docs/jvm-unit-lazy-loading.md`.

The nine `src/vm/jvm/stage0/*.jar` stay modified and UNSTAGED, as instructed; no
jar, no generated `Makefile`, no `blib/`, no `.superpowers/` in either commit.
Neither is pushed.

## Self-review

- Kotlin only; no `com.oracle.truffle` import added to nqp-runtime (the only
  nqp-truffle edit is the one stats string).
- Every new print is either env-gated (`dispatch-persist: stale schema` under
  `NQP_DISPATCH_PERSIST_TRACE`) or a `dispatch-record:` line, which is reachable
  only from `recordAtExit`, which the hook enters only when
  `NQP_DISPATCH_RECORD` is set — and the no-arg entry now returns before printing
  anything when it is not. A test asserts that silence.
- `internal fun recordAtExit(List<String>)` is visible to the test because the
  test compilation is associated with main in the same Gradle module; it is not
  public API.
- The `finally` cannot throw: it only formats Ints.
- `continue` inside the per-path `try` is legal Kotlin and lands on the outer
  `for`.
- `Makefile.in` recipe lines are TAB-indented `$(NOECHO)` lines, verified with
  `cat -A`; the `if ...; then exit 1; fi` is POSIX sh, not a pipeline, so no
  `pipefail` question arises.
- The `sed | xargs touch -r` line still matches `dispatch-record: wrote ... to `,
  which the recorder still prints per artifact — the `done` line does not replace
  it.

## Concerns / open items

1. **The F5 deviation above** (`stage2Trained` made explicitly always out of
   date) is the one place I went past the brief's letter to keep its stated
   invariant true. It costs a 25 MB copy per build; it is one line to revert.
2. **`staleSchema` is process-wide and not cleared by `resetAll`**, like every
   other counter here (already recorded as a Task 4 minor). In the eval server a
   figure covers the whole process.
3. **A stale slot is silent by default.** `staleSchema=` only appears with
   `NQP_DISPATCH_STATS`; a build whose jars were trained by another schema simply
   restores nothing and is slow, not wrong. If that should be loud, the
   `trainDispatch`/stamp markers are where a floor would go — neither gate
   asserts a QUANTITY of slots yet (the Task 7 minor, still open).
4. **The recorder's `unpersistable` count now also absorbs contained
   throwables** (a program whose `persist` threw counts once as `failed` and once
   as `unpersistable`). Deliberate — the slot lost a program either way — but the
   two numbers on the `done` line are not disjoint.
5. **`dispatch-record: FAILED` is grepped as a substring.** A path containing
   that literal text would fail the build; no path does.
6. Run 3's full stage recompile after a `build.gradle.kts` edit is pre-existing
   (`stageNGenVersion` re-runs), not caused by this wave, but it does mean every
   build-script edit on this branch costs ~4 minutes.
7. `UnitDispatchWriter`'s fixed `<path>.tmp` (a Task 5 minor) is untouched; two
   concurrent training runs on one artifact would still race. The builds have
   none.
