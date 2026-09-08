# Strict-refusal campaign — context transfer (2026-09-08)

Resume point for the zero-refusals campaign. Read the "Don't relearn these"
section first — it is the stuff that keeps getting re-explained.

## Don't relearn these (facts, not opinions)

- **There is a Truffle regex engine, and it already works.** `QAST::Regex`
  compiles via `QAST::RxDescriptor.encode` (`nqp/src/vm/jvm/QAST/RxDescriptor.nqp`,
  ~21 rxtypes) to a wire string, run at runtime by
  `GrammarEngines.rxmatch` → `TruffleGrammarEngine`
  (`nqp/nqp-truffle/.../TruffleGrammarEngine.kt`, wire codec `RxWire.kt`).
  The encoder does NOT encode regex internals — it emits a `rxmatch` op
  (`TruffleEncoder.nqp:583`) referencing the descriptor. **Regex is NOT a
  refusal** (the honest census below has only 6). The survey's "regex 466"
  is an upper-bound artifact (`walk_rx` tags every regex block).
- **watched-run.raku, streamed so the user can follow it.** Long builds/tests
  go through `raku tools/build/watched-run.raku`. Run it as a plain
  background job whose stdout IS the task output — do NOT wrap the whole
  thing in `> file 2>&1`, which buries the `[Ns]` markers where the user
  can't see them.
- **Two git trees.** rakudo root + nested `nqp/` (gitignored, NOT a
  submodule). nqp changes: `git -C <abs>/nqp ...`; run gradle as
  `./nqp/gradlew -p nqp` from the root. Label hashes by tree.
- **Every build/run needs `RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1`.**
- **Env-gate every debug print** (`nqp::getenvhash()<VAR>` / `System.getenv`).
  A stray stdout print corrupts gen-cat recipes and `JvmConfigPropertiesTask`.
- **Controlled census, not full-build knobs.** Stage compiles use `--output`
  (stdout free), so a controlled `nqp-j-gradle --target=jar --output=... <mod>`
  with `NQP_CODE_BAIL=1`/`NQP_CODE_REPORT=1` is safe; a global knob on
  `buildJvm` is not (the config-probe task parses nqp stdout).

## Where we are

Committed resume point: **nqp `7b54c37f6`** (pushed). NOT green — deliberately
mid-campaign. rakudo tree was rebased onto latest `origin/main` (200 commits,
local; force-push is the user's).

`NQP_CODE_STRICT=1` makes an encoder refusal a HARD ERROR (no bytecode
fallback), naming the block+op. It is the campaign tool and it dissolves the
"commit-before-refusal" trap (a committing op like preinc's `bind`, encoded
into a block that then refuses for another op, corrupts the bytecode
fallback → `obtain` NPE at `Compiler.nqp:3994`). Off by default.

**Loop:** `tmp/strict-build.sh` = `NQP_CODE_STRICT=1` clean `buildJvm`.
stage1 builds via old stage0 (ignores the knob); stage2's strict encoder
hard-errors at the first uncovered op (~2.5 min). Cover, rebuild, repeat.

**Covered (11 ops; each validated by the build advancing past it):**
`falsey` (`not_i(istrue)`), `stringify`/`intify` (`encode_child` → smart_*
coercion), `numify` (pre-existing, reconciled), `preinc`/`predec`
(bind+add_i/sub_i, object-var null→0 auto-viv, fresh-tree clones),
`register`/`delegate`/`track`/`guard` (desugar to `dispatch('boot-syscall',
'dispatcher-<kind>', …)`), `savecapture` (new wire op W_SAVECAPTURE=31,
mirrors usecapture across NqpWire/NqpProgramBuilder/NqpOps/NqpRootNode).

## The exact next step

`for` (`encode_for` in `TruffleEncoder.nqp`) is the current blocker. It
desugars to `iterator`+`while` (last/next ride the while's own regions) with
a redo-loop around only the `call` so `redo` re-runs the call, not the fetch.
Strict build currently hard-errors:

    code-bail unknown local for_redo_1   (in encode_var)

The redo-flag local (`for_redo_*`) is not registering where the inner `while`
condition / `handle` handler read it, whereas the `for_v` temps (read only in
the `call`) register fine. **First job: find why a local read inside a
while-condition or handle-handler doesn't see an enclosing-scope local decl,
and fix it** (candidates: declare all for-locals at the top Stmts; make the
redo flag a native-int local; or the while-cond/handle-handler encode path
loses the local). Then runtime-verify redo/next/last (the semantics are not
yet tested), then cover `postinc`/`postdec` (~29, old-value temp with the same
null→0 auto-viv) and any `indexingoptimized`. Then strict should go green,
and jast2bc's fallback becomes deletable (its stub + sidecar hats stay for
plan items 5-6).

## Honest census (the real worklist)

`tmp/hc-bail.out` (NQP_CODE_BAIL per module): ~374 ACTUAL refusals. Ranked by
true reason: stringify 116, preinc 95, falsey 61, postinc 28, for 24, intify
22, predec 10, then guard/track/savecapture/delegate/register/postdec/
indexingoptimized (~18), regex 6. The op cluster IS the campaign; the survey's
~42% and its `sole` ranking wildly over-count (hand-branch ops missing from
`$extra_ops` show as bailing; regex counted per-block).

## Artifacts

- `tmp/strict-build.sh` — the strict loop.
- `tmp/strict-campaign-wip.patch` — full WIP diff (== the committed 7b54c37f6).
- `tmp/preinc-attempt.patch` — preinc/predec standalone (superseded).
- `tmp/hc-bail.out`, `tmp/honest-census.sh` — the actual-refusal census.
- Deeper background: `docs/jvm-jesp.md`, `docs/jvm-truffle-only-plan.md`,
  `docs/jvm-truffle-migration.md`.
