# Engine Merge (one Truffle language, one context) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The regex engine and the code engine run in ONE registered Truffle language (`NqpLanguage`, id `nqp`) inside ONE polyglot context, and the grammar engine class is named `NqpGrammarEngine`.

**Architecture:** `RxLanguage` (id `nqp-rx`) is folded into `NqpLanguage`, whose `parse` dispatches on the wire magic: an `nqpp` program builds the Bytecode DSL root as before, anything else takes the regex road (an `rxd` descriptor, or pattern text for the harnesses). A Kotlin object `NqpPolyglot` owns the process's single `Context`; both engines eval through it and read the bare `CallTarget` from the one `NqpLanguage.PARSED` map. The nqp-runtime side keeps its two interfaces (`CodeEngine`, `GrammarEngine`) and by-name loaders — they are a classloader bridge, not a language split — with one addition: `CodeEngine.compile` takes the block name so each `Source` is named.

**Tech Stack:** Kotlin + Java (only annotation-processed classes stay Java), Truffle/GraalVM 25.2.4, Gradle (`./nqp/gradlew -p nqp`), the eval-server sweep for rakudo tests, `prove` for nqp tests.

**Spec:** Approved in chat 2026-09-11 (this plan restates it in full; there is no separate spec file). The design: (1) `NqpLanguage` is the only registered language, id `nqp`, name "NQP"; `RxLanguage.java` deleted. (2) `MatchRootNode`/`ConstantRootNode`/`compileSource` become Kotlin (`RxMatchRootNode.kt`); the `@ExportLibrary` executables `Program` and `Matcher` stay in the Java language file. (3) One process context (`NqpPolyglot.kt`) with the GraalVM-runtime warning and the `NQP_CODE_CLOSE_AT_EXIT` hook; real `Source` names (block name / rule name). (4) `TruffleGrammarEngine` → `NqpGrammarEngine` (class, file, the `IMPL` string in `GrammarEngine.kt`, doc mentions). (5) Harnesses switch to the one id; gradle tasks and runner flags untouched. Scope guard: no merging of the runtime interfaces, no regex ops in the Bytecode DSL, no option tuning; **`TruffleEncoder.nqp` is NOT renamed** (QAST layer → would force a stage2 rebuild and every rakudo jar).

## Global Constraints

- Work in the worktree `/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records` (rakudo branch `worktree-jesp-direct-lazy-records`; nested `nqp/` tree on branch `jesp-direct-lazy-records`). Two git trees: rakudo commands from the worktree root, nqp commands as `git -C nqp ...`. Label every hash with its tree.
- Never `cd` in a tool call except inside a single `sh -c '...'` where a tool needs `cwd` (the nqp `prove` run); gradle always as `./nqp/gradlew -p nqp ...` from the worktree root.
- `RAKUDO_RAKUAST=1` on every rakudo run (the sweep tool sets it itself). `NQP_CODE_RUN` and `NQP_CODE_PRECOMP` must NOT be set at all (worktree CLAUDE.md: the encoder and the unit road are always on; they are not knobs).
- Kotlin, never Java, unless the class is annotation-processed (`@TruffleLanguage.Registration`, `@ExportLibrary`, `@GenerateBytecode`).
- Every debug print env-gated; none are added by this plan.
- Long runs through `raku tools/build/watched-run.raku --log=... --show=... -- <cmd>`; report progress at least every 90 s while they run.
- This is a runtime-only change: NO stage rebuild, NO `make`. The build step is exactly `./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars`. Kill any running eval servers before the sweeps (`pkill -f rakudo-eval-server` — check with `pgrep -af rakudo-eval-server` first; the servers keep the old jars loaded).
- Commits are evening-stamped: `GIT_AUTHOR_DATE="2026-09-12 22:57:00 +0200" GIT_COMMITTER_DATE="2026-09-12 22:57:00 +0200"` for the nqp code commit, `22:59:00` for the rakudo docs commit. Commit messages end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Push both branches to remote `ab5tract` with a plain `git push` (they are strictly ahead; no `--force`, never to main).
- Already on disk before Task 1 starts (do not redo): `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpPolyglot.kt` (new), `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/RxMatchRootNode.kt` (new), `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpGrammarEngine.kt` (renamed from `TruffleGrammarEngine.kt` with `git mv`; class renamed; `compile()` reworked; private `Holder` removed), and `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/RxLanguage.java` (`git rm`'d). `git -C nqp status --short` shows these as `A`/`R`/`D`; read them before editing anything that references them.

---

### Task 1: Merge the languages so nqp-truffle compiles and the three harnesses pass

**Files:**
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpLanguage.java` (header javadoc, registration, `PARSED` doc, `parse`, new nested `Matcher`)
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpCodeEngine.java` (imports, class javadoc, `compile`, delete `Holder`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/CodeEngine.kt` (`compile` signature at line 16-24; the two callers at lines 98 and 124)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/GrammarEngine.kt:68` (`IMPL` string)
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/RxCheck.java:40,43`
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/RxBench.java:17,48,55,75`
- Modify: `nqp/nqp-truffle/build.gradle.kts:19-22` (comment)
- Modify: `nqp/docs/truffle-grammar-engine.md:274-282` (the "Why the engine is Kotlin" paragraph naming `RxLanguage`)
- Read only: `NqpPolyglot.kt`, `RxMatchRootNode.kt`, `NqpGrammarEngine.kt` (already written; the names below come from them)

**Interfaces:**
- Consumes (already on disk): `object NqpPolyglot { @JvmStatic fun compile(encoded: String, name: String): CallTarget }`; `class RxMatchRootNode { companion object { @JvmStatic fun create(language: TruffleLanguage<*>, source: String): CallTarget; @JvmStatic fun compileSource(source: String): RxProgram } }`; `class ConstantRootNode(language: TruffleLanguage<*>, value: Any) : RootNode`; `class NqpGrammarEngine : GrammarEngine` whose `compile(encoded)` calls `NqpPolyglot.compile(encoded, name)`.
- Produces: `NqpLanguage.ID == "nqp"`; `NqpLanguage.PARSED` holds programs AND matchers; `NqpLanguage.Matcher` (interop-executable over a match target); `CodeEngine.compile(encoded: String, name: String): Any`; `GrammarEngines.IMPL == "org.raku.nqp.truffle.NqpGrammarEngine"`.

- [ ] **Step 1: Read the three files already written** (`NqpPolyglot.kt`, `RxMatchRootNode.kt`, `NqpGrammarEngine.kt`) and `NqpLanguage.java` in full, so the names used below are verified against the disk, not this plan.

- [ ] **Step 2: Rewrite the head of `NqpLanguage.java`.** Replace everything from the class javadoc (`/**` before `@TruffleLanguage.Registration`) through `public static final String ID = "nqp-code";` with:

```java
/**
 * The one Truffle language of NQP: general code and regexes both live in
 * it. Code arrives already compiled -- the QAST backend encodes a block
 * into a program at compile time ({@link NqpWire}) and a regex into a
 * descriptor ({@code RxWire}) -- and parse only decodes and builds: a
 * Bytecode DSL root for a program, an {@code RxMatchRootNode} for a
 * descriptor. Nothing parses source text, except the harnesses' pattern
 * road ({@link RxCheck}, {@link RxBench}), which hands a bare pattern to
 * the regex parser.
 *
 * <p>Until 2026-09-11 the regex engine was a second registered language
 * ({@code RxLanguage}, id {@code nqp-rx}) with its own polyglot context,
 * so its matchers and the blocks calling them compiled in separate
 * Engines. One language in one context ({@link NqpPolyglot}) makes the
 * whole program one compilation world -- and is one language fewer for a
 * native image to carry.
 *
 * <p>{@code code-test:} sources are the {@link NqpCheck} harness's canned
 * programs.
 */
@TruffleLanguage.Registration(id = NqpLanguage.ID, name = "NQP", version = "0.1")
public final class NqpLanguage extends TruffleLanguage<NqpLanguage.Ctx> {

    public static final String ID = "nqp";
```

- [ ] **Step 3: Rewrite `PARSED`'s javadoc and `parse`.** Replace from the `/**` above `static final java.util.concurrent.ConcurrentHashMap<String, CallTarget> PARSED` through the closing `}` of `parse` with:

```java
    /**
     * The call target for each source parsed, by source text -- programs
     * and matchers alike; their wire magics never collide. eval answers
     * a polyglot Value, and calling through one boxes everything, so the
     * embedders ({@link NqpCodeEngine}, {@code NqpGrammarEngine}, both
     * through {@link NqpPolyglot}) collect the bare target from here.
     */
    static final java.util.concurrent.ConcurrentHashMap<String, CallTarget> PARSED =
        new java.util.concurrent.ConcurrentHashMap<>();

    @Override protected CallTarget parse(ParsingRequest request) {
        String source = request.getSource().getCharacters().toString();
        if (NqpWire.isProgram(source)) {
            NqpWire.Program p = NqpWire.decode(source);
            BytecodeRootNodes<NqpRootNode> nodes = NqpRootNodeGen.create(
                this, BytecodeConfig.DEFAULT, b -> NqpProgramBuilder.build(b, p));
            NqpRootNode root = nodes.getNode(0);
            root.programSize = p.code().length;
            root.resultType = p.resultType();
            root.needsFrame = p.needsFrame();
            root.hllFree = p.hllFree();
            CallTarget target = root.getCallTarget();
            PARSED.put(source, target);
            return new ConstantRootNode(this, new Program(target)).getCallTarget();
        }
        if (source.startsWith("code-test:")) {
            CallTarget target = canned(source.substring("code-test:".length()));
            return new ConstantRootNode(this, new Program(target)).getCallTarget();
        }
        /* Everything else is a regex: a descriptor the backend flattened,
         * or a pattern for the harnesses (RxMatchRootNode tells them apart). */
        CallTarget match = RxMatchRootNode.create(this, source);
        PARSED.put(source, match);
        return new ConstantRootNode(this, new Matcher(match)).getCallTarget();
    }
```

Keep `canned`, `roundTrip`, `buildAdd`, `buildFib` and `Program` exactly as they are (verify `root.hllFree = p.hllFree();` is present in the current file — it is in the worktree version; do not drop it).

- [ ] **Step 4: Add the `Matcher` executable** (moved verbatim from the deleted `RxLanguage.java`) after the `Program` class, before the file's final `}`; add `import com.oracle.truffle.api.interop.UnsupportedTypeException;` next to the other interop imports:

```java
    /**
     * What eval hands back for a regex source: an executable the harnesses
     * call per target ({@code matcher.execute(input, pos)}). The engines
     * never go through it -- they take the bare target from PARSED.
     */
    @ExportLibrary(InteropLibrary.class)
    public static final class Matcher implements TruffleObject {
        private final CallTarget target;

        Matcher(CallTarget target) { this.target = target; }

        public CallTarget callTarget() { return target; }

        @ExportMessage boolean isExecutable() { return true; }

        @ExportMessage Object execute(Object[] args) throws ArityException, UnsupportedTypeException {
            if (args.length < 1 || args.length > 3) {
                throw ArityException.create(1, 3, args.length);
            }
            if (!(args[0] instanceof String s)) {
                throw UnsupportedTypeException.create(args, "target must be a string");
            }
            return switch (args.length) {
                case 1 -> target.call(s);
                case 2 -> target.call(s, args[1]);
                default -> target.call(s, args[1], args[2]);
            };
        }
    }
```

- [ ] **Step 5: `NqpCodeEngine.java`.** Delete the imports `com.oracle.truffle.api.Truffle`, `org.graalvm.polyglot.Context`, `org.graalvm.polyglot.Source`. Replace the class javadoc and `compile` with:

```java
/**
 * The code engine as the rest of NQP sees it — the general-code analog of
 * {@code NqpGrammarEngine}, looked up by name from {@code CodeEngines}
 * in nqp-runtime; the class name is load-bearing and must not move
 * package. Programs are parsed in the process's one polyglot context
 * ({@link NqpPolyglot}), the same one the grammar engine's matchers live in.
 */
public final class NqpCodeEngine implements CodeEngine {

    @Override
    public Object compile(String encoded, String name) {
        return NqpPolyglot.compile(encoded, name);
    }
```

Then delete the whole `private static final class Holder { ... }` at the end of the file (the `Context CONTEXT` field, the `NQP_CODE_CLOSE_AT_EXIT` shutdown hook and the GraalVM runtime warning — all of it now lives in `NqpPolyglot`). `grep -n "Holder\|Context\.\|Truffle\.getRuntime" NqpCodeEngine.java` must print nothing.

- [ ] **Step 6: `CodeEngine.kt`.** Change the interface method and its doc:

```kotlin
    /**
     * Turns one encoded block program into something runnable. Called once
     * per program; the result is opaque here and handed back to [run].
     * [name] is the block's name -- what the program's Source is called in
     * compilation traces and statistics.
     */
    fun compile(encoded: String, name: String): Any
```

and the two callers in `CodeEngines`:

```kotlin
        // codeRun (was: { engine.compile(it) })
        val program = programs.computeIfAbsent(encoded) { engine.compile(it, cf.codeRef?.name ?: "<anon>") }
```

```kotlin
        // materialize (was: { engine.compile(it) })
            val program = programs.computeIfAbsent(sci.compUnit.engineProgram(sci.programIndex)) {
                engine.compile(it, sci.methodName ?: "<anon>")
            }
```

- [ ] **Step 7: `GrammarEngine.kt:68`:** `private const val IMPL = "org.raku.nqp.truffle.NqpGrammarEngine"`.

- [ ] **Step 8: Harnesses and comments.** In `RxCheck.java` and `RxBench.java` replace every `RxLanguage.ID` with `NqpLanguage.ID` (5 sites). In `RxBench.java:17` change `for MatchRootNode means` to `for RxMatchRootNode means`. In `nqp/nqp-truffle/build.gradle.kts` lines 19-22 replace

```
 * What stays Java is `RxLanguage`, and only because
 * `@TruffleLanguage.Registration` and `@ExportLibrary` genuinely are
 * annotation-processed: the polyglot machinery finds a language through a
 * generated provider, so that one file earns its processor.
```

with

```
 * What stays Java is `NqpLanguage` -- the one registered language, code
 * and regexes alike -- and only because `@TruffleLanguage.Registration`
 * and `@ExportLibrary` genuinely are annotation-processed: the polyglot
 * machinery finds a language through a generated provider, so that one
 * file earns its processor. (`NqpRootNode` is Java for the Bytecode DSL,
 * the same reason.)
```

In `nqp/docs/truffle-grammar-engine.md` replace the sentence beginning "`RxLanguage` stays Java because" (lines ~278-280) with: "The match root (`RxMatchRootNode.kt`) is Kotlin too. The registered language it runs in is `NqpLanguage.java` — since 2026-09-11 the one language for regexes and general code alike, in one polyglot context (`NqpPolyglot.kt`) — and stays Java because `@TruffleLanguage.Registration` and `@ExportLibrary` genuinely are annotation-processed: polyglot finds a language through a generated provider."

- [ ] **Step 9: Grep for leftovers.** Run from the worktree root:

```
grep -rn "RxLanguage\|TruffleGrammarEngine\|nqp-rx\b\|nqp-code\"" nqp/nqp-truffle/src nqp/src/vm/jvm/runtime nqp/nqp-truffle/build.gradle.kts nqp/docs
```

Expected: the only hits are historical mentions inside the new javadoc of `NqpLanguage.java` and `NqpPolyglot.kt` (the "until 2026-09-11" sentences). Anything else is a missed site: fix it.

- [ ] **Step 10: Build the two runtime jars.**

```
raku tools/build/watched-run.raku --log=engine-merge-build.log --show='BUILD' --show='error:' --show='e: ' -- ./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars
```

Expected: `BUILD SUCCESSFUL` in under two minutes, no `e: ` (Kotlin) or `error:` (javac) lines. A Kotlin error about `NqpLanguage.PARSED` visibility means the Java field lost its package-private `static final` — it must stay exactly `static final ... PARSED` (Kotlin in the same package sees it). A javac error `cannot find symbol ConstantRootNode` means the Kotlin class is not top-level in `RxMatchRootNode.kt` — it is, check the import/package line.

- [ ] **Step 11: Run the three engine harnesses.**

```
./nqp/gradlew -p nqp rxcheck nqpcheck rxdesc 2>&1 | grep -E "all correct|check passed|decodes correctly|NOK|not ok|FAILED|Exception|BUILD"
```

Expected three success lines — `all correct` (rxcheck), `nqp-code check passed` (nqpcheck), `descriptor decodes correctly` (rxdesc) — and `BUILD SUCCESSFUL`. `nqpcheck` also prints `# Truffle runtime: Oracle GraalVM ...`; an `Interpreted` runtime there means the module path is wrong, stop and report.

- [ ] **Step 12: Smoke the real runtime** (both engines through the one context, in one process):

```
RAKUDO_RAKUAST=1 NQP_JVM_TRUFFLE=require ./rakudo-j -e 'my $s = "abc123"; say $s ~~ /\d+/; say [+] 1..10'
```

Expected output exactly `｢123｣` then `55`, no `nqp: Truffle runtime is ...` warning, no `grammar engine unavailable`.

- [ ] **Step 13: Commit (nqp tree).**

```
git -C nqp add -A nqp-truffle/src src/vm/jvm/runtime/org/raku/nqp/runtime/CodeEngine.kt src/vm/jvm/runtime/org/raku/nqp/runtime/GrammarEngine.kt nqp-truffle/build.gradle.kts docs/truffle-grammar-engine.md
git -C nqp status --short | grep -v '^??'   # expect only the files above (A/M/R/D), nothing else
GIT_AUTHOR_DATE="2026-09-12 22:57:00 +0200" GIT_COMMITTER_DATE="2026-09-12 22:57:00 +0200" git -C nqp commit -q -F - <<'EOF'
engine: one Truffle language, one polyglot context; TruffleGrammarEngine is NqpGrammarEngine

RxLanguage (id nqp-rx) is folded into NqpLanguage (id nqp): parse dispatches
on the wire magic -- an nqpp program builds the Bytecode DSL root, anything
else takes the regex road (an rxd descriptor, or pattern text for the
harnesses). The match root and the constant root move to Kotlin
(RxMatchRootNode.kt); the @ExportLibrary executables stay in the Java
language file. NqpPolyglot owns the process's single Context -- one Engine,
one compiler-thread pool, one option set -- and both engines eval through
it; CodeEngine.compile takes the block name so every Source is named.

Runtime-only: no stage rebuild, no encoder change. TruffleEncoder.nqp keeps
its name on purpose (QAST layer; renaming it costs a stage2 rebuild).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
git -C nqp log --oneline -1
```

Report the nqp hash.

---

### Task 2: Gate — nqp suite and the rakudo t/01-sanity + t/02-rakudo sweep on warm eval servers

**Files:**
- No source changes. Logs: `engine-merge-nqp-suite.log`, `engine-merge-sweep.log` in the worktree root (untracked; leave them).
- Read: `docs/superpowers/plans/2026-09-11-jvm-milestone-5-rakuobject-layout.ledger.md` for the pre-existing red baseline.

**Interfaces:**
- Consumes: the jars Task 1 built (`nqp/build/...` synced by `syncRuntimeJars`); `./rakudo-j`; `tools/build/evalserver-sweep.raku`; `nqp/nqp-j-gradle`.
- Produces: a pass/fail verdict with the list of red files, each classified as *pre-existing* (named in the milestone-5 ledger or `docs/jvm-spectest-known-failing.txt`) or *new*.

- [ ] **Step 1: Make sure no stale eval server is alive.** `pgrep -af rakudo-eval-server`; if any, `pkill -f rakudo-eval-server` and re-check. Also `rm -f .evalserver-token-*`.

- [ ] **Step 2: nqp suite** (prove needs `cwd` = the nqp tree; this is the one sanctioned `cd`, inside `sh -c`):

```
raku tools/build/watched-run.raku --log=engine-merge-nqp-suite.log --stall=900 --show='Failed' --show='Result' --show='Files=' -- sh -c 'cd nqp && prove -r --exec ./nqp-j-gradle t/nqp t/hll t/qregex t/p5regex t/qast t/jvm t/serialization t/nativecall'
```

Expected (the milestone-5 baseline): every failing file is one of the "nine remaining reds, all pre-existing" the ledger's Task 3 section names (read `docs/superpowers/plans/2026-09-11-jvm-milestone-5-rakuobject-layout.ledger.md`, search `pre-existing` and `04-repossession`; `t/jvm/11-dispatch.t` is one of them). Any other red file is NEW: rerun that single file (`sh -c 'cd nqp && ./nqp-j-gradle t/<dir>/<file>.t'`) with `NQP_RX_TRACE=1` if it is a regex test, capture the first failing line, and stop with the evidence — do not fix in this task.

- [ ] **Step 3: rakudo sweep.** Memory budget: the branch rule (CLAUDE.md, decision 2026-09-08) is three servers at 2g heap; the tool checks `jobs × (heap + 3g)` against MemAvailable; do not pass `--force`.

```
raku tools/build/watched-run.raku --log=engine-merge-sweep.log --stall=900 --show='chunk' --show='files in' --show='chunks failed' --show='no TAP' -- raku tools/build/evalserver-sweep.raku --jobs=3 --heap=2 t/01-sanity t/02-rakudo
```

Expected: `t/01-sanity` all green (25 files). `t/02-rakudo` reds limited to the known set: `native-return-coercion.t` (19/23, reds 7, 17, 18, 19), `21-begin-time-compile-sub.t` (compile red, `Failed to deserialize lexical $?PACKAGE`), `custom-declarator-naming.t` and `03-cmp-ok.t` (`find_method not found for FooHOW`), `long-int-literal.t` (8/33). Extract the red list from the log's `--- chunk` sections. A red outside that set is NEW: rerun it alone with `RAKUDO_RAKUAST=1 ./rakudo-j -Ilib t/02-rakudo/<file>.t`, quote the first failing assertion, and stop with the evidence. ("Bind check failed … INDIRECT_NAME_LOOKUP" on a direct run means `-Ilib` was forgotten, not a regression.)

- [ ] **Step 4: Report.** Table: suite, files, red files, classification. Note wall-clock for each run (from the watched-run elapsed prefixes) as an observation only — the merge is expected to be neutral-to-positive on warm-up and this is not the perf measurement session.

---

### Task 3: Docs in the rakudo tree, commit, push both trees

**Files:**
- Modify: `docs/jvm-eval-server.md:194` (`TruffleGrammarEngine.STATES` → `NqpGrammarEngine.STATES`)
- Modify: `docs/jvm-nfg-representation.md:97` (`TruffleGrammarEngine.STATES` → `NqpGrammarEngine.STATES`)
- Modify: `docs/jvm-strict-campaign-handoff.md:12` (`TruffleGrammarEngine.kt` → `NqpGrammarEngine.kt`)
- Modify: `docs/superpowers/plans/2026-09-10-perf-measurement-session.md:10` (append a DONE note)
- Modify: `docs/jvm-truffle-migration.md` (one bullet after the "Delivered as: `NqpLanguage`/`NqpRootNode`/`NqpCheck`" bullet, line ~84-87)
- Leave alone: `docs/jvm-nfg-perf-findings-2026-09-06.md` and everything under `docs/superpowers/plans/2026-09-11-pr-stack/` (dated records).

**Interfaces:**
- Consumes: Task 1's nqp hash and Task 2's verdict (quoted in the commit message).
- Produces: rakudo commit; both branches pushed to `ab5tract`.

- [ ] **Step 1: The three name fixes.** `sed -i 's/TruffleGrammarEngine/NqpGrammarEngine/g' docs/jvm-eval-server.md docs/jvm-nfg-representation.md docs/jvm-strict-campaign-handoff.md`, then `git diff --stat` must show exactly those three files with 1 line each.

- [ ] **Step 2: Perf plan note.** At the end of line 10 of `docs/superpowers/plans/2026-09-10-perf-measurement-session.md` (the bullet ending `NqpCodeEngine.java:32`).`) append: ` **DONE 2026-09-11 (engine merge):** one language (`NqpLanguage`, id `nqp`) in one context (`NqpPolyglot.kt`); Sources are named by block (`CodeEngine.compile(encoded, name)`) and by rule pass-name.`

- [ ] **Step 3: Migration doc bullet.** After the bullet block that starts `- Delivered as: \`NqpLanguage\`/\`NqpRootNode\`/\`NqpCheck\` in nqp-truffle` (ends with `"Phase 1 results" section below.`), add at the same indentation:

```
  - 2026-09-11: the regex engine's own language (`RxLanguage`, id `nqp-rx`)
    and its second polyglot context are gone -- `NqpLanguage` (id `nqp`)
    parses programs and descriptors alike, `NqpPolyglot.kt` holds the one
    context, and `TruffleGrammarEngine` is `NqpGrammarEngine`
    (nqp/docs/truffle-grammar-engine.md). Runtime-only; `TruffleEncoder.nqp`
    keeps its name (QAST layer).
```

- [ ] **Step 4: Commit (rakudo tree)** — include this plan file:

```
git add docs/jvm-eval-server.md docs/jvm-nfg-representation.md docs/jvm-strict-campaign-handoff.md docs/superpowers/plans/2026-09-10-perf-measurement-session.md docs/jvm-truffle-migration.md docs/superpowers/plans/2026-09-11-engine-merge.md
GIT_AUTHOR_DATE="2026-09-12 22:59:00 +0200" GIT_COMMITTER_DATE="2026-09-12 22:59:00 +0200" git commit -q -F - <<'EOF'
docs: the engine merge -- one Truffle language, one context, NqpGrammarEngine

Records nqp <HASH> (RxLanguage folded into NqpLanguage, NqpPolyglot holds
the single context, TruffleGrammarEngine renamed NqpGrammarEngine) in the
living docs and the perf-session plan, with the plan that drove it.
Gate: nqp suite and t/01-sanity + t/02-rakudo on warm servers, <VERDICT>.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
git log --oneline -1
```

Replace `<HASH>` with Task 1's nqp hash and `<VERDICT>` with Task 2's one-line result (e.g. `no new reds`).

- [ ] **Step 5: Push both trees.**

```
git -C nqp push ab5tract jesp-direct-lazy-records
git push ab5tract worktree-jesp-direct-lazy-records
```

Expected: both fast-forward (`<old>..<new>`). If either is rejected as non-fast-forward, STOP and report — do not force.
