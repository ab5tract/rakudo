# Task 11 report — the milestone gate and the docs

**Status: DONE_WITH_CONCERNS.** Every gate but the t/ sweep is green.
The sweep found **eleven red files that milestone 3's sweep 2 did not
list**, two of them with named mechanisms. I did not fix them (the brief
forbids it) and I did not write "all green" anywhere: the plan position,
both specs and the ledger twin all say the milestone is **code complete,
not closed**.

Base: nqp `e270f070d`, rakudo `09f349adda`. Docs commits: this commit
(rakudo, 33 files) and nqp `d24431b68` (3 files). Both trees clean; no
rebase, no push (the controller's Step 5).

---

## Step 1: the make — not run, and correctly so

Task 10's build is on the final jars and nothing changed after it: nqp
clean build 258 s, Rakudo `make` from the top 1103 s (CORE.c window
533 -> 1044 s = 511 s), log
`/home/longwalker/.claude/jobs/25fa1a35/tmp/t10-make.log`. Milestone-3
baseline: `make` 1154 s, CORE.c 475 s, nqp clean build 222 s.

## Step 1a: eval servers

`pgrep -af EvalServer` before the gate matched nothing but its own shell.
One orphan server survived the first sweep's kill and was killed before
the reruns; its leftover token file (`.evalserver-token-40`) was the only
evidence that identified the sweep's unfinished chunk.

## Step 1b: precomp — 13/14, 14/14 with `RAKUDOLIB=lib`

`lib/.precomp` and `t/packages/Test-Helpers/.precomp` cleared first.
Logs: `/home/longwalker/.claude/jobs/25fa1a35/tmp/t11-precomp-logs/`
(14 files, 2 jobs, 23-141 s each).

Thirteen green. `t/02-rakudo/rakuast-suspend-precomp-deps.t` EXIT=255
("The spawned command … exited unsuccessfully"), which is the harness gap
known since milestone 3: the test spawns `$*EXECUTABLE` without `-Ilib`.
Rerun with `RAKUDOLIB=lib` prefixed: **3/3, EXIT=0, 57 s**, log
`/home/longwalker/.claude/jobs/25fa1a35/tmp/t11-precomp-rakudolib-logs/`.
Not a compiler fault.

## Step 1c: t/03-jvm + t/10-qast — 2/2

`t/03-jvm/01-interop.t` ok, `t/10-qast/00-misc.t` ok, 62 s. Logs:
`/home/longwalker/.claude/jobs/25fa1a35/tmp/t11-jvm-logs/`.

## Step 1d: the census — 35/35 artifacts

`raku tools/build/jar-census.raku` over every jar that exists:

```
CENSUS: all 35 jars are unit artifacts
```

Every row `ARTIFACT meta=1 class=0`. Breakdown:

| group | jars |
|---|---|
| `nqp/build/jvm/share/lib/` | 10 (ModuleLoader, NQPCORE.setting, NQPHLL, nqp, nqpmo, NQPP5QRegex, NQPP6QRegex, QAST, QASTNode, QRegex) |
| `nqp/src/vm/jvm/stage0/` | **9** (the same minus NQPP5QRegex; `JASTNodes.jar` is gone) |
| Rakudo | 16 (`rakudo.jar`, 3 BOOTSTRAP, 3 CORE settings, 7 `blib/Perl6/*`, 2 `blib/Raku/*`) |

## Step 1e: the t/ sweep

### It ran at 2 servers, not 3 — the arithmetic

`MemAvailable` was 20 g. `evalserver-sweep.raku` budgets
`max(4, avail-3)` = **17 g** and charges each server `heap + 3 g`
off-heap, because the eval server's own guard does; 3 x (4+3) = **21 g**
is over budget and the script refuses it without `--force`. Forcing it
would reproduce the 2026-09-08 failure mode the sweep's comments
document: the third server declined mid-run, surfacing as a chunk with no
TAP and a 120 s token timeout. I ran 2 x 4g = 14 g of a 17 g budget.
This is a deviation from the brief's `--jobs=3`, taken deliberately.

### Run 1 (as the brief specifies, minus jobs)

`t11-sweep.log`: 418 files, 60 chunks of 7. **59 of 60 chunks completed
inside the 7200 s ceiling**, then `EXIT=124 verdict=timeout`. Nineteen
chunks reported FAIL, six of them flagged "a file produced no TAP".

**The per-chunk detail was lost.** The sweep prints its failure detail
only after the last chunk, so the kill took it. Worse, the log's
`chunk N/60` is a *completion counter*, not a chunk index, so no file can
be attributed from the log at all — exactly the trap milestone 3's Task 5
hit ("main-sweep chunk attribution unreliable"). The one thing that was
recoverable is the unfinished chunk: the orphan server's token file was
`.evalserver-token-40`, and the token *is* named by the chunk index, so
chunk 40 (files 281-287, `smartmatch-topic-rhs.t` …  `sprintf-6e-e.t`)
is the one that never reported.

### Run 2: attribution

Two reruns, each designed to actually finish:

- **`t11-sweep2b.log`** — the ten non-`t/02-rakudo` directories as one
  sweep. Completed: **120 files in 1546 s**, 5 of 18 chunks failed, full
  per-file detail printed.
- **`t11-sweep2a.log`** — `t/02-rakudo` alone. 42 of 43 chunks in
  4404 s, then `EXIT=124 verdict=stall` at 5905 s: the last chunk hung.
  Its token was `.evalserver-token-36` → chunk index 36, which overlaps
  run 1's unfinished chunk 40. **The same neighbourhood hung twice.**
- **`t11-02-logs/`** — `t/02-rakudo` file by file through
  `watched-run -t --jobs=3` (per-file logs carry the file name, and a
  hanging file is timed out per file instead of killing the run):
  **298 files, 23 red**.
- **`t11-sweep-confirm.log`** — every `t/02-rakudo` red file not on
  milestone 3's list, re-run through the eval server to remove the
  cold-vs-warm oracle mismatch.

## The comparison against milestone 3's sweep 2

| dir | M3 sweep 2 | now | delta |
|---|---|---|---|
| 01-sanity | 0 | 0 | — |
| 02-rakudo | 13 | 18 confirmed red (11 of M3's 13 + 7 new + 1 hang), 2 of M3's 13 FIXED | **+8, -2** |
| 03-jvm | 0 | 0 | — |
| 04-nativecall | 0 | 0 | — |
| 05-messages | 1 | 1 (`02-errors.t`, 1/47) | — |
| 06-telemetry | 0 | 0 | — |
| 07-pod-to-text | 0 | 0 | — |
| 08-performance | 2 | 5 | **+3** |
| 10-qast | 0 | 0 | — |
| 13-experimental | 0 | 0 | — |
| 14-smoke | 0 | 0 | — |

**Fixed since milestone 3 (the item-8 pair, Task 10's fix):**
`t/02-rakudo/yada-trait-timing.t` and
`t/02-rakudo/begin-time-attributive-param-method.t` are green in a full
directory run. Also improved:
`t/08-performance/36-rakuast-begin-compiled-remark.t` now *runs*
(115/117) where milestone 3 had it dying at compile time with "Too many
positionals passed".

## The new failures, triaged

### Regression 1 — `is_inlinable` lost its table (PROVEN, mechanism named)

`QAST::OperationsJVM.is_inlinable` reads `%core_inlinability`
(`nqp/src/vm/jvm/QAST/Compiler.nqp:200,216-223`), which is now populated
**only** by `map_classlib_core_op`. Every op that used to arrive through
`add_core_op` / `map_jvm_core_op` therefore answers 0. Probe on the built
compiler:

```
add_i 0   sub_i 0   mul_i 0   add_n 0   mul_n 0   if 0   while 0   list 0
add_I 1   concat 1  box_i 1   iseq_i 1  atpos_i 1 elems 1
```

Before milestone 4 (nqp `55bdee5b7:src/vm/jvm/QAST/Compiler.nqp`),
`add_core_op` set inlinability to 1 by default (`:295-297`) and
`map_jvm_core_op('add_i', 'ladd', …)` (`:336-340`, `:2628`) went through
it. RakuAST's `IMPL-INLINE-INFO` dies "Non-inlinable op encountered" for
any op that answers 0 (`src/Raku/ast/code.rakumod:3299-3301`), so routine
inlining stops and native arithmetic stops lowering.

This is the exact mirror of the finding Task 1's review caught: the
review fixed `supports_op`/`core_op_supported` for the encoder's hand
rows and nobody carried the same repair into `is_inlinable`.

Red because of it, all four confirmed under the eval server:

| file | evidence |
|---|---|
| `t/08-performance/22-rakuast-ct-dispatch.t` | 6/30 — "native int addition compiles to add_i with no operator call", "native num multiplication compiles to mul_n …", three splice assertions |
| `t/08-performance/29-rakuast-attr-self-types.t` | 2/21 — "arithmetic on a native int/num attribute inlines to the raw op" |
| `t/08-performance/32-rakuast-native-param-bind.t` | 6/26 — "a native int/num/optional/named/sized parameter binds without boxing"; **milestone 3's report explicitly records this file as PASSING** |
| `t/02-rakudo/native-return-coercion.t` | 4/23 — "boxed Int operand keeps the result boxed" and two coercion assertions |

**This is a runtime-performance regression baked into the built setting**,
not a test-content failure, and it lands squarely on the user's stated
priority. The perf measurement session (item 4) must not run before it is
fixed, or every number is measured on a setting that never lowered native
arithmetic. Fix shape (not applied): make `is_inlinable` fall back the
way `core_op_supported` does — an op the encoder has a row for, or the
classlib maps, is inlinable unless something set it otherwise.

### Regression 2 — a multi-character `Str` range never terminates

Minimal reproducer:

```
./rakudo-j -e 'say ("aa".."ac").elems'     # hangs (rc=124 at 90 s)
./rakudo-j -e 'say ("a".."e").elems'       # 5
./rakudo-j -e 'say "aa".succ'              # ab
```

So `succ` is fine; the range's iteration never sees its end. It hangs
`t/02-rakudo/sort-element-kinds.t` at test 2 ("a list of Str sorts by
codepoint", which builds `"zzz00" .. "zzz20"`) and it is what stalled
both sweeps. The test was added 2026-08-30 and was green through
milestone 3.

### Six more, red and not root-caused

All confirmed under the eval server, all files predating 2026-09-06:

| file | evidence |
|---|---|
| `t/02-rakudo/21-begin-time-compile-sub.t` | compile death: `java.lang.RuntimeException: Failed to deserialize lexical $?PACKAGE` at `use CompilerEvalSubAtBegin` |
| `t/02-rakudo/custom-declarator-naming.t` | compile death: `Method 'find_method' not found for invocant of class 'MetamodelX::RakuLevelNameHOW'` |
| `t/02-rakudo/make-regex-frame.t` | compile death: `regex engine cannot encode rule 'TOP': qastnode walks the caller chain (curcode)` (an engine refusal — no fallback exists any more) |
| `t/02-rakudo/try-statement-backtrace-frame.t` | 1/4 — "the frame after the try frame is the caller of the hidden sub" |
| `t/02-rakudo/regex-interpolation-backtrack.t` | 3/8 — interpolated-array longest-match / backtracking |
| `t/02-rakudo/m-flag-module-spec.t` | 1/19 — a quote in a `-M` argument produces a "Confused" error instead of the expected hint |

**Caveat, stated honestly:** milestone 3's list of 13 came from a
chunk-attributed verify sweep, and ~10 of its FAIL chunks were attributed
to heap growth without ever being resolved per file. Some of these six
may have been red then too. Regressions 1 and 2 are not subject to that
caveat — regression 1 has a proven mechanism and a before/after in the
source, and regression 2's file is explicitly absent from milestone 3's
list with a one-line reproducer.

### Cleared as not-failures

`t/02-rakudo/long-int-literal.t`, `native-argument-snapshot.t` and
`15-gh_1202.t` fail only in the cold per-file run and pass through the
eval server / with `RAKUDOLIB=lib`: the `$*EXECUTABLE`-spawn gap, same
family as `rakuast-suspend-precomp-deps.t`.

### Sweep infrastructure

Six chunks in run 1 and three in 2a flagged "a file produced no TAP".
At 2 x 4g this is not the server-refusal shape (only two servers were
ever asked for); it matches milestone 3's heap-growth-across-a-long-chunk-
sequence note. At least one of them was the hanging `Str` range.

---

## Step 2: the docs

Grep run first:
`grep -rn 'JAST\|jast2bc\|codeprograms\|class road\|LibraryLoader\|NQP_CODE_RUN' AGENTS.md CLAUDE.md docs/*.md nqp/docs/*.md`.
Every hit is now either deleted, rewritten, or inside a passage explicitly
marked as history. **`CLAUDE.md` is a symlink to `AGENTS.md`** — one file,
edited once.

### rakudo tree

- **`docs/jvm-truffle-only-plan.md`**
  - "Rules of the road": the sidecar check
    (`unzip -l … | grep -c codeprograms` must be 1) replaced by the jar
    census; the old check named as history.
  - Position heading re-dated 2026-09-10 and rewritten: milestone 4 code
    complete, **not closed**, gate open.
  - Row 4 (compiler workload): the JAST stage is gone; item 4 is next
    *after* the `is_inlinable` regression is fixed, or its numbers are
    meaningless.
  - Row 5: milestone 4 code complete — the reflective road deleted, not
    merely unused; the three surviving `CompilationUnit` subclasses named.
  - Row 6: the long milestone-4 entry — what shipped, the numbers
    (builds, CORE.c, census 35/35), and the full gate including both
    regressions, the six unexplained reds, the caveat, and the item-8
    pair going green.
  - Row 7: the parked where-in-`BEGIN` shape marked **FIXED** (nqp
    `e270f070d`); item 7 closed.
  - Row 8: rewritten as **DONE**, listing what went and naming the two
    things that deliberately stay (ASM, `ByteClassLoader`); the
    `NQP_CODE_RUN`-presence caveat retired with stage0.
  - Row 9: **adaptor half DONE** via `AdaptorUnit` with the interop
    gate; **P6Opaque half open**, and the only reason ASM survives.
  - "The sidecar, placed" paragraph: kept, headed **HISTORY, gone
    2026-09-10**, with a sentence saying what it explains and what no
    longer exists.
  - List entries 5, 6, 8, 9 rewritten to match the rows.
- **`docs/superpowers/specs/2026-09-09-jvm-unit-artifact-design.md`** —
  Milestones item 4 gets a long entry: code complete, not closed, what
  shipped with hashes, the timings, the gate, the six deviations, and an
  explicit note that the `$!codeprograms` pass-through the old paragraph
  told milestone 4 "not to forget" went with stage0 exactly as required.
  Two "Open questions … resolved" entries (`getCodeRefs()` fallback road,
  interop adaptor units) closed.
- **`docs/superpowers/specs/2026-09-10-jvm-unit-artifact-milestone-4-design.md`** —
  a "Done (2026-09-10) — code complete, gate open" section: the nine
  landed pieces with hashes and numbers, the six deviations (Tasks 5+6 as
  one dispatch; `serializedBlob`/`claimNested`/`engineProgram` open with
  throwing bodies because `KnowHOWMethods` is hand-written;
  `readToHeapBuffer*` not ported; `leave.t` does not exist so
  `keep-undo.t` was the gate; Probe A was not an instance, hence the
  `--> S` reproducer; the stale-jars remake after Task 4), the carried
  gaps, and a full "The milestone gate" subsection.
- **`AGENTS.md`** (and so `CLAUDE.md`) — the `NQP_CODE_RUN` /
  `NQP_CODE_PRECOMP` bullet: the stage0-PRESENCE trap moved into a marked
  history parenthesis, and "no class road left to opt out *to*" extended
  to compiler, runtime and stage0. Added to the build bullet: **stage0 is
  unit artifacts** (9 jars, `unit.meta`-only), regenerate with
  `./nqp/gradlew -p nqp jBootstrapFiles` only ahead of an incompatible
  wire/meta/syscall change and from the last compiler that speaks the old
  shape; additive changes need none.
- **`docs/jvm-eval-server.md`** — the same stage0 caveat marked history.
  It names neither `LibraryLoader` nor the class road.
- **`docs/jvm-strict-campaign-handoff.md`** — the "every build needs
  `NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1`" bullet and the strict-loop recipe
  corrected with their own dates; the stage0-sidecar bullet rewritten
  (the additive wire rule stands, the sidecar does not); closing section
  "Closed (2026-09-10) — milestone 4 deleted the runtime class road and
  JAST; nothing here is left to hand off."
- **`docs/jvm-jesp.md`**, **`docs/jvm-truffle-migration.md`**,
  **`docs/jvm-truffle-calling-convention.md`**,
  **`docs/jvm-nfg-perf-findings-2026-09-06.md`** — each had a sentence
  that read as live instruction (`NQP_CODE_RUN=1` recipes, "the default
  setting is bytecode", "Status: Phase 2 landed"). Each is now dated and
  corrected in place; `jvm-truffle-migration.md` is headed "finished.
  This file is history from here down".
- **`docs/superpowers/plans/2026-09-10-jvm-unit-artifact-milestone-4.ledger.md`**
  — created from the SDD ledger, plus eight closing lines covering this
  task's gate, both regressions, the unexplained six, the docs, and the
  MILESTONE 4 verdict.
- **`docs/superpowers/plans/2026-09-10-jvm-unit-artifact-milestone-4.reports/`**
  — 21 briefs and reports copied (this report included).

### nqp tree

- **`nqp/docs/gradle-jvm-build.md`** — Task 4's stage0 bullets were
  already right; two leftovers fixed: `BytecodeVersion` is
  `org.raku.nqp.runtime`, not `org.raku.nqp.jast2bc`, and its readers are
  `BootJavaInterop` and the P6Opaque/C-struct REPRs (verified by grep);
  the ASM-9.10.1 bullet now says its two behavioural fixes were in code
  that no longer exists, and that ASM itself stays.
- **`nqp/docs/kotlin-migration-notes.md`** — history header: the
  "LibraryLoader — keep as Java" ruling and the "Remaining Java" tally are
  settled by deletion, not conversion.
- **`nqp/docs/truffle-grammar-engine.md`** — two passages that reason
  from generated classes (`JAST::Class` as a place to hang a compiled
  program; the >16-piece bytecode-path cap) dated and corrected.

## Files changed

rakudo: `AGENTS.md`, `docs/jvm-eval-server.md`, `docs/jvm-jesp.md`,
`docs/jvm-nfg-perf-findings-2026-09-06.md`,
`docs/jvm-strict-campaign-handoff.md`,
`docs/jvm-truffle-calling-convention.md`, `docs/jvm-truffle-migration.md`,
`docs/jvm-truffle-only-plan.md`,
`docs/superpowers/specs/2026-09-09-jvm-unit-artifact-design.md`,
`docs/superpowers/specs/2026-09-10-jvm-unit-artifact-milestone-4-design.md`,
plus the new ledger twin and the reports directory.

nqp: `docs/gradle-jvm-build.md`, `docs/kotlin-migration-notes.md`,
`docs/truffle-grammar-engine.md`.

No code was touched in either tree.

## Self-review

- **Brief coverage.** Step 1a-1e all run; Step 2's file list all edited
  plus four more the grep exposed; Step 3 committed in both trees. Step 4
  (memory) and Step 5 (rebase/push) left to the controller, as instructed.
- **The two deliberate deviations.** (1) The sweep ran at 2 servers, not
  3, with the arithmetic above — the brief's own rule ("never launch N
  servers without the N x heap vs free-RAM arithmetic") pointed this way.
  (2) When the ceiling and then a stall destroyed the sweep's own
  attribution twice, I reran for attribution rather than report chunk
  counts, using `watched-run -t` for `t/02-rakudo` because it names files
  and survives a hanging one. Both cost wall time; neither changes what
  was measured.
- **Honesty check.** Nothing in the docs claims the milestone is closed
  or the suite green. The plan position, both specs and the ledger all
  say "code complete, not closed", and each carries the two mechanisms.
- **What I did not do.** I did not fix the two regressions (brief:
  report, the controller rules). I did not root-cause the six remaining
  reds. I did not run t/spec (out of scope, user rule).

## Concerns

1. **Regression 1 is the important one.** It is a silent runtime-perf
   regression across the whole setting with a one-line fix shape, and it
   invalidates any perf measurement taken on these jars. It should be a
   fix wave before the milestone closes and certainly before item 4.
2. **Regression 2 hangs a test**, which is why both sweeps died where
   they did; any future sweep on these jars will stall the same way
   unless `sort-element-kinds.t` is excluded or the range is fixed.
3. **The six unexplained reds** need a session each. Three die at compile
   time, which suggests they are worth more than their test counts.
4. **Milestone 3's per-file baseline is not trustworthy** for
   `t/02-rakudo`: its ~10 infrastructure-attributed FAIL chunks were
   never resolved per file. The comparison in this report is the best
   that can be made without re-running milestone 3's toolchain.
5. **The sweep tooling loses its own results when it is killed.** Both
   the ceiling and a stall destroy the per-chunk detail, and the log's
   chunk counter cannot be mapped to files. Two cheap fixes for a later
   task: print each chunk's failure detail as it completes, and label the
   line with the chunk index (the token file already uses it).
6. **Deferred minor, not touched** (code):
   `nqp/src/vm/jvm/QAST/RxDescriptor.nqp:211` still names
   `QAST::Compiler.engine_jast`, deleted in Task 1.
