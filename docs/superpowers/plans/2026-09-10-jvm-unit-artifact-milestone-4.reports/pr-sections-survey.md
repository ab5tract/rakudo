# PR sections survey — rakudo + nqp JVM/Truffle branches

Surveyed 2026-09-10 (read-only, by an explorer agent; saved by the controller).

**Controller preface.** The PRs target the `main` branch of the ab5tract
remotes (github.com/ab5tract/rakudo, github.com/ab5tract/nqp), not upstream
(user, 2026-09-10). Both fork mains are currently BEHIND their upstreams
(rakudo ab5tract/main `18abe8c32f28` is an ancestor of origin/main
`00fca760bb90`; nqp ab5tract/main `5776e30dcf33` is an ancestor of
upstream/main `2fc2375fa751`). Recommendation: fast-forward each fork main
to its upstream first, then stack the PRs on it, so the PR diffs show only
our work. Where the survey below says "upstream" in a PR-acceptance sense
(open questions 4 and 6), read "the fork's main": the landing order is ours
to choose, and a rakudo PR may require an unmerged nqp PR by naming it.

- rakudo: worktree `jesp-direct-lazy-records`, branch `worktree-jesp-direct-lazy-records`,
  `origin/main..HEAD` = **246 commits**, `6a1691243d` (2026-08-15) .. `09f349adda` (2026-09-10).
- nqp: nested checkout, branch `jesp-direct-lazy-records`,
  `upstream/main..HEAD` = **367 commits**, `52b298a69` (2026-08-13) .. `e270f070d` (2026-09-10).

The nqp branch leads rakudo by two days at the start (nqp opens 08-13, rakudo 08-15) and the
two converge to same-day lockstep from 2026-09-06 onward.

## Superpowers boundary

First commit adding `docs/superpowers/` in **rakudo**: **`3d193d7cbc`** (2026-09-09),
`docs/superpowers/specs/2026-09-09-jvm-unit-artifact-design.md`.
The next commit `080bcb86fd` adds `docs/superpowers/plans/2026-09-09-jvm-unit-artifact-milestone-1.md`.

**nqp has no `docs/superpowers/` at all** — the whole SDD apparatus (specs, plans, ledgers,
task briefs, implementer reports) lives in the rakudo tree only, and nqp's milestone work is
identified by subject prefix (`unit artifact:`, `unit compiler:`, `stage0:`).

Everything from `3d193d7cbc` onward in rakudo (36 commits, sections R13–R16) is already
milestone-shaped: each milestone has a plan, a set of implementation commits, a "done"
commit, a "closed" ledger commit, and its per-task briefs/reports. Those four sections need
no re-clustering — only squash decisions on their doc churn.

## rakudo sections (16)

| # | Name | Range | N | Dates |
|---|------|-------|---|-------|
| R1 | Gradle build + Kotlin runtime layer | `6a1691243d..d6d6fe7bb8` | 11 | 08-15 |
| R2 | RakuAST non-Moar dispatch scaffolding | `195d01488c..1d59200288` | 20 | 08-16..17 |
| R3 | Rakudo on newdisp — the flip | `a0605f0d7e..88688aaaa7` | 21 | 08-17..18 |
| R4 | JVM semantics parity (generics, natives, uniprop, phasers) | `f1d9fb892c..837844623e` | 22 | 08-19 |
| R5 | Eval server, build/tooling, static-code identity, Perl6→Raku | `b7eeeab9db..62a3c8faf7` | 20 | 08-25..29 |
| R6 | Grammar-engine adoption + spectest infra | `397e2d10ea..c3da65a89f` | 5 | 08-31 |
| R7 | Truffle code-engine phases 1–4 (Rakudo side) | `b92bf4672f..174ea10afb` | 10 | 08-31..09-02 |
| R8 | Phase 5 coverage campaign — fixes + the lab ledger | `8ead5c9baa..ab7e229ad4` | 53 | 09-03..05 |
| R9 | Legacy Perl6 frontend trimmed (RakuAST-only) | `59326c65ae..8f22859438` | 5 | 09-05 |
| R10 | NFG on the JVM | `10e4759917..008c343704` | 3 | 09-06 |
| R11 | Calling convention + jesp diamonds 1–8 | `704aebd3d7..ce5d63419d` | 30 | 09-06..08 |
| R12 | Strict-refusal campaign (Rakudo side) | `794fa17c7f..02fc304897` | 10 | 09-08..09 |
| R13 | **Unit artifact milestone 1** | `3d193d7cbc..87f9956217` | 12 | 09-09 |
| R14 | **Milestone 2** | `fbf990eaf1..5ae25a8d3c` | 10 | 09-09 |
| R15 | **Milestone 3** | `40145235cb..b4e5e65c3c` | 10 | 09-09..10 |
| R16 | **Milestone 4 (in progress)** | `e4a1811207..09f349adda` | 4 | 09-10 |

### R1 — Gradle build + Kotlin runtime layer (11)
Introduces `build.gradle.kts` for `org.raku.rakudo`, converts Binder, RakOps,
RakudoContainerSpec/Configurer and RakudoJavaInterop to Kotlin, moves container atomics from
`Unsafe` to `VarHandle`, drives the runtime jar from Gradle, and adds the dev-runner heap /
native-access / `nqp.library.path` plumbing. **Depends on:** nqp N1, plus `221cd8a03`
(StorageSpec as a value + enum tags, 08-15) which sits in **N2** — `d6d6fe7bb8` ("follow NQP's
StorageSpec to enums") cannot build without it. **PR:** own PR. **Squash to 3:** gradle build,
Kotlin conversion, runner plumbing.

### R2 — RakuAST non-Moar dispatch scaffolding (20)
Gives RakuAST's new-dispatch sites non-moar branches, binds arguments through the runtime
binder, makes the onlystar proto dispatch work, plus a run of JVM frontend fixes (UTF-16
assumptions, `@!compstuff` drain, code-ref table slot per cuid, no lowering where the binder is
needed) and `p6sink` moving into the runtime. Also the first `run-watched` tooling.
**Depends on:** N2, and — see hazard H4 — `f76b11cbee` (08-16, "bind arguments with the runtime
binder") plausibly needs nqp `efd6b5f8f` (QAST::ParamTypeCheck) / `6b7cdaf01` (HLL reports a bind
failure), both **08-17, one day later**. Verify before splitting the PR boundary here.
**PR:** own PR. **Squash to 4:** dispatch scaffolding, binder path, frontend fixes, tooling.

### R3 — Rakudo on newdisp: the flip (21)
Builds the newdisp dispatchers on the JVM backend, routes assign / rv-decont / coercion through
their dispatchers, registers Raku's HLL dispatchers, lowers parameters instead of always using
the binder, then `5c343f58f0` flips the remaining gates — "everything now runs on newdisp".
Ends with atomicint and the integer atomics graduating off the jvm-NYI lists. Contains one
revert pair (`a691c24c81` / `99faeae96d`) that should be squashed away entirely.
**Depends on:** N3, specifically `52cde5811` + `22ba60970` (08-18) for the gate flip — same date.
**PR:** own PR, the flip is the natural review unit. **Squash to 5:** per-dispatcher commits
(assign, rv-decont, coercion, HLL registration), then the flip; drop the revert pair.

### R4 — JVM semantics parity (22)
Generic coercion resolution per call, generics in the binder and return check, backtrace/host
plumbing (`method_not_found_error`, static outer, pool prompt), `uniprop-general`,
`p6capturelexwhere`, native return/inline-info corrections, sized-native narrowing, one
codepoint per `ord`, bounded build heap, and "teach every runner about the grammar engine".
**Depends on:** N4 (same day, 08-19) and — for the last commit — N5a `723c3eecf` ("start every
JVM so that it can run a grammar", also 08-19). **PR:** own PR. **Squash to 4:** generics,
natives/sized, diagnostics/host errors, runner+heap.

### R5 — Eval server, tooling, static-code identity, Perl6→Raku (20)
The eval server is born (heap, pool sizing by memory, sweep, leak-check), the traited-variable
failure is root-caused to static-code identity and fixed for BEGIN-bound code, `make` learns to
rebuild the nqp JVM runtime, `src/vm/jvm/Perl6` becomes `src/vm/jvm/Raku`, `Configure.pl
--gen-nqp` bootstraps the nested nqp via Gradle, and the AGENTS working agreements land.
**Depends on:** N5b (eval-server survivability: `1a4d18377`, `b016312e2`) and N5c.
**PR:** split into two — (a) eval server + sweep tooling, (b) the static-code-identity fix +
the `Perl6`→`Raku` rename + Configure/make. The rename is a large mechanical diff that reviewers
want alone. **Squash to 4** across the two PRs.

### R6 — Grammar-engine adoption + spectest infra (5)
`make j-spectest` on one warm eval server, `nqp::cas` literals staying boxed, the leak-check /
hprof post-mortem tooling, Junction autothreading from the bind_error handler, and real HTML
entities packed to fit the constant pool. **Depends on:** N5c (engine feature-complete, 08-29).
**PR:** not self-contained — **fold into R5** (tooling) except `022996c617` and `de0833a064`,
which are semantics fixes that belong with R4/R11.

### R7 — Truffle code-engine phases 1–4, Rakudo side (10)
The migration plan document ("replace jast2bc, phase by phase"), the phase 1–4 landing records,
the `Qt*` → `Nqp*`/`TruffleEncoder` rename follow-through, `.DELETE_ON_ERROR` in the Makefile,
one BEGIN block per 16 RakuAST packages, and the eval server learning to refuse over-budget
starts and cage itself in a memory-capped scope. **Depends on:** N6 + N7 (phases 1–4 proper).
**PR:** own PR, paired with the nqp N6+N7 PR. **Squash to 3:** the plan doc, the phase records
(one commit), the build/gen/eval-server changes.

### R8 — Phase 5 coverage campaign: fixes + the lab ledger (53) ⚠️
The largest and least PR-shaped section. ~45 of the 53 commits are `Docs:` entries — a running
lab notebook of coverage percentages, bisections, and **several documented wrong diagnoses that
are corrected two or three commits later** (`1f54b9d393` "CORRECTION", `17607c98a7` "diagnosis
flips … a caught red herring", `8b79a73a91` "diamond 7 compile-time claims withdrawn").
The genuine code is only ~8 commits: `fdeb153138` (publish registered op desugars),
`65d3cf553c` (cache the return-type check per signature), `0525b95ae6` (definite parameter type
as base type + concreteness), `16980802f6` (drop stray JVM special-casing), `89918277fd`
(atomicbindattr unconditionally), `0bdde837d9` (`p6box_u` boxes unsigned), plus watched-run
tooling. **Depends on:** N8 (the encoder batches this ledger reports on).
**PR:** the 8 code commits are their own PR. **Squash the 45 docs commits to 1** — a single
"Phase 5 coverage campaign: findings and the final coverage table" that states the *final*
conclusions, not the wrong turns. Publishing the wrong-diagnosis chain is a liability.

### R9 — Legacy Perl6 frontend trimmed (5)
`59326c65ae` removes World/Actions/Grammar + rakudo-debug from the build; `8d9f0c7b35` removes
the now-inert build rules. Plus two eval-server memory-containment commits and one watched-run
change that belong to R5's tooling PR. **Depends on:** nothing new cross-tree.
**PR:** own PR, and a high-value one — this is the "RakuAST is the only frontend" statement.
**Squash to 1** (the two trim commits merge cleanly); move the other 3 to R5.

### R10 — NFG on the JVM (3)
The representation-decision doc, `182a00660b` (Uni and the normalization forms work on JVM), and
the perf-findings/calling-convention handoff doc. **Depends on:** **N9, same day (09-06)** —
`182a00660b` cannot build without nqp `39f10b138` (NFGString value type) and `4fece491a`
(grapheme layer). This is the tightest cross-tree coupling on the branch.
**PR:** own PR, but it *must* be stacked directly on the nqp N9 PR. **Squash to 1 code + 1 doc.**

### R11 — Calling convention + jesp diamonds 1–8 (30)
Frame-free methods (`%_` discard), dispatch-cost profiling, `p6typecheckrv` lowering that kills
`accepts_type`, `JESP_RVGUARD_OFF` dropped, "the engine build is the build", diamonds 1 through
8 with their A/B measurements, RakuAST lowering trace improvements, and the ranked Truffle-only
plan. About half are `Docs:` bench reports. **Depends on:** N10 (the diamonds proper) and N9's
frame-free phase A. **PR:** own PR. **Squash to 5:** frame-free/%_, `p6typecheckrv` +
`JESP_RVGUARD_OFF`, the engine-build switch, the diamonds' Rakudo side, one consolidated
bench/plan doc. Note `c4798711db` defers `dispatching-blocks-frame-free` — an abandoned road.

### R12 — Strict-refusal campaign, Rakudo side (10)
Seven handoff documents plus three code commits: `8b3bf126b0` (`NQP_RV_TRACE=1` explains a
rejected return-value check), `fa31c40cd3` (p6trialbind / p6setbinder as published desugars),
`56aeb044d3` (truffle-only plan position). **Depends on:** N11. ⚠️ The handoff docs cite nqp
hashes (`7b54c37f6`, `8f9640095`, `c131b8933`, `9602cefeb`, `ca71c19cb`) that are **not
ancestors of the current nqp HEAD** — the nqp branch was rewritten after they were written. See
hazard H5. **PR:** the 3 code commits fold into R11's PR; **squash the 7 handoffs to 1** and
rewrite the hashes (or drop them).

### R13 — Unit artifact milestone 1 (12) — superpowers era begins
Design spec, milestone-1 plan, four ruling/correction commits, the "landed" / "gate green" /
"closed" trio, the SDD ledger and the per-task briefs and implementer reports. The one
load-bearing code commit is **`71ef2f4daa`** — "the Makefile enters nqp through UnitMain (an
artifact nqp.jar has no `nqp` class)". **Depends on:** N12, specifically `4e31b8f1d` (the
bilingual loader + UnitMain) and `5ad6fc414` (runners enter through UnitMain). See hazard H2 —
**every rakudo section from R13 onward requires N12.**
**PR:** own PR. **Squash to 3:** spec, plan+ledger (one doc commit), `71ef2f4daa`.

### R14 — Milestone 2 (10)
Ten documentation commits: the milestone-2 plan and seven successive plan refinements about
`t/nqp/124`, then "done", "final hash", "closed + ledger". **No rakudo code at all** — milestone
2 was entirely nqp-side (N13). **PR:** not self-contained; **fold the whole section into the nqp
N13 PR as one doc commit**, or squash to 1 and attach to R15.

### R15 — Milestone 3 (10)
Rakudo moves onto the unit road. Code: `08a997dc2b` (runners and the build runner enter through
`UnitMain <rakudo.jar>`) and `a22eb40b73` (the encoder knobs are defaults; the written-down build
recipes enter nqp through UnitMain). The rest is the plan, Task 3b (6 encoder refusals + 5
engine-correctness causes), the "done" record, the ledger twin, a performance-measurement session
plan, and three `watched-run` features (`--follow=LOG`, `--show-file`, `-t` digest).
**Depends on:** N14 — `a22eb40b73` needs nqp `388173781` ("the unit road and the encoder are the
defaults"). **PR:** own PR. **Squash to 4:** the two code commits, the watched-run features as
one, the plan+ledger as one.

### R16 — Milestone 4, in progress (4 at survey time; Task 11's docs commit joins it)
The milestone-4 design and 11-task implementation plan, then `2e66c36b3d` (the Raku op file
registers classlib mappings and desugars only; the JAST closures are gone) and `09f349adda` (the
Rakudo adaptor is a plain class behind an `AdaptorUnit`). **Depends on:** N15 — `2e66c36b3d`
needs nqp `5cf759de6` (JASTNodes gone) and `9844a0de9` (stage0 regenerated); `09f349adda` needs
nqp `14df06863` (AdaptorUnit). All same day. **PR:** own PR, last in the stack. **Keep as is.**

## nqp sections (17)

| # | Name | Range | N | Dates |
|---|------|-------|---|-------|
| N1 | Gradle build + wholesale Kotlin conversion | `52b298a69..80aa52f36` | 72 | 08-13..15 |
| N2 | Runtime correctness, FFI on `java.lang.foreign`, op gaps | `054d029aa..80e81d34b` | 27 | 08-15..16 |
| N3 | The newdisp dispatch port | `842563809..20cd97c87` | 35 | 08-17..18 |
| N4 | Diagnostics, interop, unicode/regex parity, nested units | `b4066506c..93ca8ae9d` | 25 | 08-19 |
| N5a | Truffle regex engine — first road | `a697a12a4..2b69b9757` | 17 | 08-19..20 |
| N5b | Dispatch / eval-server / runtime hardening interlude | `4423777a0..b1c5f9384` | 14 | 08-24..27 |
| N5c | Grammar engine feature-complete | `efd29f30a..d0578362e` | 15 | 08-28..29 |
| N6 | Code engine phases 1–2 + `Qt*`→`Nqp*` rename | `4f65249a8..343151a29` | 12 | 08-31 |
| N7 | Code engine phases 3–4 (control flow, precomp, sidecar, caches) | `3db74ba80..7f7a680ca` | 15 | 09-01..02 |
| N8 | Phase 5: the encode-coverage campaign to 96.5% | `01649f700..aa7c44f0a` | 53 | 09-02..05 |
| N9 | NFG + TruffleString + engine-regex-only | `39f10b138..2dceb1e0b` | 12 | 09-06 |
| N10 | jesp diamonds 1–8 / calling convention | `712939bb4..908df5c3b` | 16 | 09-07..08 |
| N11 | HLL simplification + strict-refusal campaign | `11d834bba..112b1649c` | 9 | 09-08..09 |
| N12 | **Unit artifact milestone 1** | `4a7eb2925..56adfe211` | 16 | 09-09 |
| N13 | **Milestone 2** | `cfa0846ac..da1f5088a` | 4 | 09-09 |
| N14 | **Milestone 3** | `c872c83af..55bdee5b7` | 16 | 09-09..10 |
| N15 | **Milestone 4** | `c6af33aa3..e270f070d` | 9 | 09-10 |

### N1 (72) — Gradle + Kotlin conversion
ASM 4.1→9.10.1, Java 25 target, and a wave-by-wave conversion of the entire JVM runtime to
Kotlin (reprs, sixmodel, serialization, CallFrame, GlobalContext, CompilationUnit, jast2bc
nodes, Ops, IndyBootstrap, the autosplitter), plus the dependency sweep (jline 4, JNA 5.19,
fastutil 8.5.19, lz4 safeInstance). Contains **two stage0 bootstraps** (`90ab16c81`,
`c37658b8f`) and seven `docs:` round records. **PR:** must be split — 72 commits with binary
jars is unreviewable. Suggest 3 PRs: (a) gradle + ASM + Java 25 + first bootstrap,
(b) the Kotlin conversion waves, (c) dependency modernization + docs.
**Squash to ~12** (one per conversion wave); collapse the two bootstraps into one.

### N2 (27) — Runtime correctness + FFI + op gaps
`java.lang.foreign` replaces JNA for native calls, `nqp::syscall`, the 65535-indy-per-class
cliff, `indexic`/`eqatim` family, batched static lexical setup so the core setting fits a class,
StorageSpec as a value with enum tags, honest nullability, and the two NFG scoping docs.
**PR:** own PR. **Squash to 6.** ⚠️ `221cd8a03` (StorageSpec enums) is the *rakudo R1
prerequisite* — it must not slip behind R1 in the stack.

### N3 (35) — The newdisp dispatch port
The core of the branch's first half: the newdisp mechanism, nqp's own dispatchers, resumable
binds, `QAST::ParamTypeCheck`, `lang-call`/`lang-meth-call` behind `NQP_JVM_LANG_CALL` then
routed by default, flattening exploded at the dispatch entry, programs keyed by shape,
stackless control exceptions, `Object[]` dispatch past MethodType's limit, integer atomics,
sized-native MoarVM semantics. Contains a **stage0 bootstrap** (`d94a608eb`) and one further
stage0-touching commit (`a5223b99b`). **PR:** own PR (or split gate/flip). **Squash to 10.**
The `NQP_JVM_LANG_CALL` gate is introduced and removed inside this section — squash it out.

### N4 (25) — Diagnostics, interop, parity (all 08-19)
Backtraces in declared-source coordinates, escaped-continuation stories, interop marshalling
and method dispatch on Java wrappers, `#line` mid-block, `:m`/`:i:m` regex literals,
`General_Category` uniprops, hot dispatch programs compiled to MethodHandle chains, nested
comp-mode units persisted in the enclosing jar, bigint/sized-native edge semantics.
**PR:** own PR. **Squash to 6.**

### N5a (17) — Truffle regex engine, first road
From `a697a12a4` ("a Truffle regex engine, and the ground it stands on") through parity and
running rakudo's suite under the engine. A visible design-search: parsed text → QAST::Regex →
descriptor. **PR:** own PR. **Squash to 5** — squash the abandoned parsed-text road away
entirely; its net effect is zero.

### N5b (14) — Hardening interlude
Dispatch-site keying by argument shape, corrupt-capture reporting, pending-dispatch restore,
class under the resolved-reference ceiling, eval server surviving more than four runs, shutdown
hooks not pinning runs, lazy object-lexical vivification, smart coercions with the dispatchers'
exact semantics. **PR:** fold into N3's dispatch PR + a small eval-server PR. **Squash to 5.**

### N5c (15) — Grammar engine feature-complete
`f3d300474` removes the whole-engine toggle; then the encode-* series (backtrackable rules,
callback pieces, dynamic quantifiers, conjunctions, ignoremark, uniprop pairs, computed pass
names), callback dispatch split across blocks, cursor re-entry / resumable rules, and
`d0578362e` "the engine is feature-complete and the sweep is green". **PR:** own PR — this is
the cleanest, most self-contained large unit on either branch. **Squash to 6.**

### N6 (12) — Code engine phases 1–2
The Bytecode DSL skeleton proven live, coverage reporting before coverage, the `Qt*` →
`Nqp*`/`TruffleEncoder` rename, the nqpp wire format, blocks running on the engine.
**PR:** own PR. **Squash to 4** (skeleton, coverage tooling, rename, wire+blocks).

### N7 (15) — Code engine phases 3–4
Raku mainline on the engine, param tasks, `want()` selector, loops with last/next/redo,
`handle`/`handlepayload`, continuations across engine frames, precompiled units behind
`NQP_CODE_PRECOMP`, engine programs as a jar sidecar, inline caches, virtual threads by default.
**PR:** own PR. **Squash to 6.** `NQP_DISPATCH_OLDDESC` / `NQP_CODE_UNCACHED` are hunt knobs
removed later in N10 — squash them out.

### N8 (53) — Phase 5 encode-coverage campaign ⚠️
The counterpart to rakudo R8, and the second-largest section. Percentage-by-percentage encoder
batches (70.7% → 96.5%) plus the engine-side machinery each batch needed (PE-visible dispatch
replay, per-instruction caches, lazy refold, inlining across dispatch, Kotlin null/lateinit
checks out of compiled code, Truffle exceptions never host ones). `4f888ab3b` drops 271 hand
op3 rows the classlib registry covers. **PR:** split into 3 — (a) engine machinery,
(b) the encoder op batches, (c) the classlib registry + hand-row deletion.
**Squash to ~12.** Unlike R8, these are real code and the percentages are useful in the log;
keep the coverage numbers in the squashed subjects.

### N9 (12) — NFG + TruffleString + engine-regex-only
Canonical-equivalence string ops and the `NFGString` value type, grapheme-indexing the grammar
engine, per-source segmentation cache (fixes an O(n²) parse), the classic regex path
grapheme-indexed, `NQP_RX_STRICT`, and then **`11d11f514` deletes the classic per-node bytecode
codegen** — a point of no return. Also `ed0a27b81` frame-free blocks phase A and `2dceb1e0b`
desugars by default. **PR:** own PR — and it is the hard dependency of rakudo R10.
**Squash to 5.** Note the section mixes two themes (NFG, engine-regex-only); splitting into
N9a/N9b is defensible but they share the grapheme-indexing commits.

### N10 (16) — jesp diamonds / calling convention
`712939bb4` drops the finished hunts' debug and A/B knobs; then the direct road for resumable
literals, lazy dispatch records, the type-check family and native arithmetic as sited
operations, `add_I`/`sub_I`/`mul_I`, frame-free blocks on by default, `hllize` sited,
`checkarity`/`flatArgs` off the boundary, the prologue and return boundaries, the argument array
read from the frame, `p6sink` sited. Contains the **stage0 refresh `48f1e0147`** ("stage0 from
the current stage2"). **PR:** own PR. **Squash to 8** (one per diamond). See hazard H1: the
stage0 refresh must stay inside this section.

### N11 (9) — HLL simplification + strict-refusal campaign
`hllize` out of `%hll_ops`, `encode_op` split under the 64KB limit, then `NQP_CODE_STRICT` and
the campaign to green (for, postinc/postdec, indexingoptimized, untyped if/ternary typing,
`custom_args` blocks on the engine with P6BINDSIG/P6TRYBINDSIG). Contains a `WIP` commit
(`9d3981e9d`) that must be squashed. **PR:** own PR, paired with rakudo R12.
**Squash to 4.**

### N12 (16) — Unit artifact milestone 1
The artifact format (`unit.meta`, byte-framed programs, zip envelope) with a round trip, the
unit hooks, `claimNested`, `ProgramUnit` (a CompilationUnit built from the block table without
reflection), **the bilingual loader and `UnitMain`**, the cheap unit sniff with a per-path road
cache, the JAST record carrying the unit, `NQP_UNIT` as all-or-nothing, the writer and
`jvm-write-unit`, `t/nqp/123`, and the final-review fixes. **PR:** own PR. **Squash to 6.**
This section provides `UnitMain` — hazard H2.

### N13 (4) — Milestone 2
The record road in the runtime: `jvm-build-unit`, `loadcompunit` building a ProgramUnit from the
record, nested records retained and embedded, every unit taking the road under `NQP_UNIT`,
`t/nqp/124`, and the final-review fix (no in-memory fallback for `claimNested`).
**PR:** small; **merge with N12** into one "unit artifact: format, loader and record road" PR,
or keep separate if the milestone boundary is worth preserving. **Keep as is** (4 commits).

### N14 (16) — Milestone 3
Exit-handler blocks encode, `388173781` makes **the unit road and the encoder the defaults**,
`block_in_tree` correctness, sized/unsigned natives on the unit road, metaop chains, suspension
tokens for gather/take across `p6sink`/`decont`/`p6typecheckrv`, `NQP_ARITY_TRACE`,
`NQP_REPOINT_TRACE`, `OPCALLT` carrying a table op's result type, and finally `30e849e3c`
(the compiler emits only unit records — the string-constant road, size gates, sidecar writer,
`$*UNIT_FALLBACKS` and the `NQP_UNIT` knob are gone) and `55bdee5b7` (the runtime still forwards
a class-road compiler's sidecar because **stage0 needs it until milestone 4**).
**PR:** own PR. **Squash to 7.** ⚠️ `55bdee5b7` is an explicit "this crutch exists only until
the next section" — the N14/N15 boundary is a real, load-bearing boundary.

### N15 (9) — Milestone 4
The QAST-only driver (no JAST tree, no operand stack, no per-block stub), `JASTNodes` and nqp's
JAST op closures gone, **`9844a0de9` stage0 regenerated as unit artifacts from the JAST-free
compiler**, the runtime class road deleted (jast2bc, compilejast, the sidecar reader,
setLexValues, enterFromMain, IndyBootstrap), the loader rewritten in Kotlin (`UnitLoader`),
`AdaptorUnit` on bound method handles, LEAVE on exceptional exit, suspended fused ops resuming
through a finisher, and `patch_params` keeping deferred code-ref slots.
**PR:** own PR, the top of the stack. **Keep as is** — every commit is a distinct deletion or fix.

## Hazards

**H1 — stage0 binary jars, regenerated five times.**
`src/vm/jvm/stage0/*.jar` changes in: `90ab16c81` (N1), `c37658b8f` (N1), `d94a608eb` (N3),
`a5223b99b` (N3, incidental), `48f1e0147` (N10, "stage0 from the current stage2"), and
`9844a0de9` (N15, "regenerated as unit artifacts"). **Each regeneration must land in the section
whose compiler produced it.** In particular:
- `9844a0de9` cannot move earlier than `5cf759de6` (JASTNodes gone) — the jars *are* unit
  artifacts and no earlier runtime can load them.
- `55bdee5b7` (N14) exists precisely because the pre-M4 stage0 still needs the class-road
  sidecar. Any N14/N15 reordering breaks the bootstrap.
- A section boundary that ships a stage0 predating its own compiler will not build, and the
  failure mode is a bootstrap crash, not a test failure — expensive to bisect.
- Squashing across a stage0 boundary silently keeps only the later jar; that is usually correct
  but must be deliberate.

**H2 — `UnitMain` is the rakudo/nqp entry contract.**
nqp N12 (`4e31b8f1d`, `5ad6fc414`) introduces `UnitMain`; rakudo `71ef2f4daa` (R13) then makes
the Makefile enter nqp through it, because an artifact `nqp.jar` has no `nqp` class.
`08a997dc2b` (R15) and `a22eb40b73` (R15) extend that to every runner and the written-down
recipes. **Every rakudo section from R13 onward requires N12 to be merged first**, and R15
additionally requires N14's `388173781`. Landing any of R13–R16 ahead of N12 gives an
unbuildable rakudo.

**H3 — NFG spans both trees on the same day.**
rakudo `182a00660b` (09-06) and nqp `39f10b138`/`4fece491a`/`48f499880`/`a465f1001` (09-06) are
one change split across repos. There is no version of the branch where rakudo R10 builds against
an nqp older than N9. This is the one place where "same date or earlier" is exactly binding
rather than comfortably satisfied.

**H4 — one probable forward dependency in R2.**
rakudo `f76b11cbee` (08-16, "bind arguments with the runtime binder") appears to need nqp
`efd6b5f8f` (`QAST::ParamTypeCheck`) and `6b7cdaf01` (the HLL reports a bind failure), both
**08-17**. If confirmed, R2 must be split at `f76b11cbee` or the whole of R2 stacked on N3.
This is the only date-order violation found from subjects; worth a build check.

**H5 — the rakudo handoff docs cite nqp hashes that no longer exist.**
R12's seven handoff commits reference nqp `7b54c37f6`, `8f9640095`, `c131b8933`, `9602cefeb`,
`ca71c19cb`. `7b54c37f6` and `9602cefeb` resolve (from the object store) to the same *subjects*
as `9d3981e9d` and `5aeb58b15`, but **`git merge-base --is-ancestor 7b54c37f6 HEAD` fails** —
the nqp branch was rewritten after those docs were written. The same pattern applies to the
milestone "final hash" commits (`5dc6517b81` cites `da1f5088a`, which *is* current). Any further
rebase invalidates every such reference. Recommendation: strip nqp hashes from squashed doc
commits, or replace them with subjects.

**H6 — documented wrong diagnoses.**
R8 contains at least three commits that are corrections of earlier commits in the same section
(`1f54b9d393`, `17607c98a7`, `8b79a73a91`), and R3 contains a revert pair. Squashing is not just
tidiness here — the un-squashed history publishes conclusions the branch later disproved.

## Recommended PR stack

Ordered; each PR is mergeable only after everything above it.

| # | Tree | PR | Sections | Commits after squash |
|---|------|----|----------|----------------------|
| 1 | nqp | Gradle build, ASM 9, Java 25, first bootstrap | N1a | ~3 |
| 2 | nqp | Kotlin conversion of the JVM runtime | N1b | ~10 |
| 3 | nqp | Dependency modernization + `java.lang.foreign` FFI + op gaps | N1c + N2 | ~8 |
| 4 | rakudo | Gradle build + Kotlin runtime layer | R1 | 3 |
| 5 | nqp | The newdisp dispatch port | N3 + N5b(dispatch) | ~12 |
| 6 | rakudo | RakuAST non-Moar dispatch scaffolding | R2 | 4 |
| 7 | rakudo | Rakudo on newdisp — the flip | R3 | 5 |
| 8 | nqp | Diagnostics, interop, unicode/regex parity | N4 | 6 |
| 9 | rakudo | JVM semantics parity | R4 | 4 |
| 10 | nqp | Truffle regex engine | N5a | 5 |
| 11 | nqp | Grammar engine feature-complete | N5c | 6 |
| 12 | rakudo | Eval server + sweep tooling | R5a + R6 + R9-tooling | 4 |
| 13 | rakudo | Static-code identity, `Perl6`→`Raku`, Configure/make | R5b | 4 |
| 14 | nqp | Code engine phases 1–2 + rename | N6 | 4 |
| 15 | nqp | Code engine phases 3–4 | N7 + N5b(eval-server) | 7 |
| 16 | rakudo | Truffle code-engine phases 1–4, Rakudo side | R7 | 3 |
| 17 | nqp | Phase 5: engine machinery | N8a | 5 |
| 18 | nqp | Phase 5: the encoder op batches to 96.5% | N8b | 6 |
| 19 | nqp | classlib registry, hand rows deleted | N8c | 2 |
| 20 | rakudo | Phase 5 Rakudo-side fixes + coverage record | R8 | 9 |
| 21 | rakudo | Legacy Perl6 frontend trimmed (RakuAST-only) | R9 | 1 |
| 22 | nqp | NFG + TruffleString + engine-regex-only | N9 | 5 |
| 23 | rakudo | NFG on the JVM | R10 | 2 |
| 24 | nqp | jesp diamonds / calling convention (incl. stage0 refresh) | N10 | 8 |
| 25 | rakudo | Calling convention + jesp diamonds, Rakudo side | R11 + R12-code | 5 |
| 26 | nqp | HLL simplification + strict-refusal campaign | N11 | 4 |
| 27 | rakudo | Strict-refusal campaign record | R12-docs | 1 |
| 28 | nqp | Unit artifact: format, loader, UnitMain, record road | N12 + N13 | 8 |
| 29 | rakudo | Unit artifact milestone 1 (Makefile through UnitMain) | R13 + R14 | 3 |
| 30 | nqp | Unit road and encoder as defaults; class road removed | N14 | 7 |
| 31 | rakudo | Milestone 3: Rakudo on the unit road | R15 | 4 |
| 32 | nqp | Milestone 4: QAST-only driver, stage0 regenerated, class road deleted | N15 | 9 |
| 33 | rakudo | Milestone 4: Raku op file, AdaptorUnit, docs | R16 | 4-5 |

**33 PRs**, ~613 commits squashed to **~190**. A minimal alternative (fold every "docs/record"
PR into its code PR, merge N1a–N1c, merge N8a–N8c) gets to **24 PRs**; a maximal split of N1
and N8 gets to ~40.

## Open questions for the user

1. **Pre-superpowers granularity.** The 12 pre-09-09 rakudo sections and 13 nqp sections can be
   presented as 25 PRs (above), or compressed to 8 thematic PRs (Kotlin+Gradle, newdisp,
   regex engine, code engine, Phase 5, NFG, jesp, frontend trim) — or as few as 3
   (runtime modernization / the Truffle engine / the unit road). Which?
2. **Net-zero experimental work.** Several knobs and roads are introduced and removed inside the
   branch: `NQP_JVM_LANG_CALL` (N3), the whole-engine toggle (N5c), `NQP_DISPATCH_OLDDESC` /
   `NQP_CODE_UNCACHED` (N7, dropped in N10), `JESP_RVGUARD_OFF` (R11), `NQP_UNIT` and
   `$*UNIT_FALLBACKS` (N12, deleted in N14), `NQP_CODE_RUN`/`NQP_CODE_PRECOMP` as knobs, the
   parsed-text regex road (N5a), the deferred `dispatching-blocks-frame-free` road (R11).
   **Squash all of these away so they never appear in the PRs, or keep them as evidence of the
   A/B that justified the default?** Recommendation: squash away, except where the plan
   documents cite the A/B numbers.
3. **The lab-notebook docs.** R8's 45 `Docs:` commits and R11's bench reports contain retracted
   diagnoses. Squash to one final-conclusions commit (recommended), keep verbatim as project
   history in `docs/superpowers/`, or drop from the PRs entirely and keep only on the work branch?
4. **Milestone doc placement.** `docs/superpowers/` (rakudo) and `.superpowers/sdd/` are
   process artifacts. Should they be part of the PRs at all, or stripped from the stack and kept
   on the work branch?
5. **nqp N12/N13 merge.** Milestone 2 is 4 nqp commits and 10 rakudo doc commits. Merge into
   milestone 1's PR, or preserve the milestone boundary for the ledger's sake?
6. **Two-repo landing order.** The stack interleaves 17 nqp and 16 rakudo PRs. Since both
   target the fork's main, a rakudo PR may name the nqp PR it requires (an `NQP_REVISION` bump
   per pair); the alternative — all nqp PRs first — makes the rakudo half harder to review in
   order.
