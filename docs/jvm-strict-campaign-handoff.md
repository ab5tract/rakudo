# Strict-refusal campaign — context transfer (2026-09-08, evening)

Resume point for the zero-refusals campaign. Read the "Don't relearn these"
section first — it is the stuff that keeps getting re-explained.

## Don't relearn these (facts, not opinions)

- **Two engines, two names.** The *Truffle compiler* is the QAST encoder
  (`nqp/src/vm/jvm/QAST/TruffleEncoder.nqp`) plus the wire consumer
  (`nqp/nqp-truffle/.../NqpProgramBuilder.java`, `NqpWire.java`,
  `NqpOps.java`, `NqpRootNode.java`). The *Truffle regex engine* is
  `QAST::RxDescriptor` → `RxWire.kt` → `TruffleGrammarEngine.kt`; it already
  works and the compiler only emits an `rxmatch` op referencing the
  descriptor. Regex is NOT a refusal.
- **watched-run.raku, streamed so the user can follow it.** Long builds/tests
  go through `raku tools/build/watched-run.raku` as a plain background job.
  Do NOT arm a Monitor per gradle task: monitors are for precise signals
  and must never fire more often than every 90s (user rule, 2026-09-08).
- **Two git trees.** rakudo root + nested `nqp/` (gitignored, NOT a
  submodule). nqp changes: `cd <abs>/nqp && git ...` in its own call (the
  worktree guard refuses `git -C`); gradle as `./nqp/gradlew -p nqp` from the
  root. Label hashes by tree.
- **Every build/run needs `RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1`.**
- **Env-gate every debug print** (`nqp::getenvhash()<VAR>` / `System.getenv`).
- **Stage0 jars carry wire programs** (`nqp.codeprograms.lz4` inside each
  bootstrap jar), so a wire change must be ADDITIVE: new op numbers only,
  never a changed layout of an existing op.
- **Backtraces omit engine closures.** A nested block run by the engine has
  no name (its CodeRef `name` is an uninitialized lateinit on the script
  road, the enclosing routine's name on the jar road) and does not appear
  as an `in <anon>` frame. "in obtain" can mean "in a closure inside
  obtain". Task open: give anonymous blocks names (RakuAST could at least
  number them).
- **Jars from different stages cannot be mixed** (serialization dependency
  versions). To test a stage2-compiled module in isolation, compile the
  module AND its dependencies with the stage1 compiler into one directory
  (the `tmp/mo` recipe below).
- **nqp-m is on this box** (`~/.rakubrew/versions/moar-2026.07/bin/nqp-m`):
  ground truth for NQP semantics. Use it before calling anything a bug.
- **NQP's Test setting speaks TAP**: `plan`/`ok`/`is` from
  `nqp/src/core/testing.nqp`; new coverage goes in `nqp/t/nqp/NNN-*.t`.

## Where we are

**nqp `8f9640095` (this branch, unpushed): the nqp bootstrap builds with
`NQP_CODE_STRICT=1` end to end — zero Truffle-compiler refusals — and the
resulting compiler runs.** `BUILD SUCCESSFUL in 9m54s` (clean, strict).
`t/nqp/121-for-controls.t` passes 16/16 on it under strict.

What closed the campaign today:

- `for` → new wire op **W_FORLOOP (32)**: a handled loop whose per-iteration
  fetch runs OUTSIDE the redo loop and only the block call inside it
  (Compiler.nqp's redo label sits between fetch and call). Zero allocation
  per iteration. The previous desugar through `handle` could never work: a
  handle's handler is a nested block, a separate frame that cannot see the
  enclosing block's locals — hence "unknown local for_redo". `:nohandler`
  is a plain W_LOOP over fetch+call. Labeled `for` still refused (nothing
  emits one: NQP has no loop labels, Raku's `for` is its own loop).
- `postinc`/`postdec`: old value into a scratch local, rebind ±1, answer the
  local; same fresh-tree clones and null→0 auto-viv as preinc.
- `indexingoptimized`: operand wanted as str.
- **The runtime bug the campaign exposed**: `NqpOps.AttrSite` (the getattr/
  bindattr inline cache) guarded on the storage class only. `BUILDALL`
  (NQPMu.nqp) binds every attribute of an object through ONE `bindattr`
  with a computed name; once it encoded (it used to refuse), the site
  resolved for `@!stack` and then wrote `@!spill_locals`'s empty list into
  the `@!stack` field. First symptom: the stage2 compiler's `obtain` died
  with an NPE in `bindpos` on the very first compile. Fix: the site records
  class handle + name and the fast path requires both (two reference
  compares). `bindpos` on a null array now dies with the block name.
- Semantics checked against nqp-m: a `redo` in a `for` body does NOT re-run
  the body on any backend (moar, JVM bytecode, JVM Truffle all answer
  `7,8 n=2`), and a control thrown from a *called sub* has no handler on
  any of them. The new test pins what all three answer.

## The exact next step

1. **Read the t/nqp result** (`$CLAUDE_JOB_DIR/tmp/nqp-tests.log` or rerun:
   `raku tools/build/watched-run.raku -t=nqp/t/nqp --jobs=3 -- nqp/nqp-j-gradle`
   with `NQP_JVM_MAXHEAP=2g`). Every FAIL is either a runtime gap in one of
   the ~374 blocks that now encode for the first time, or a test that needs
   `cd nqp` for relative paths. Compare against nqp-m before calling it a bug.
2. **Rakudo build on the new nqp**: `raku tools/build/watched-run.raku
   --log=build.log --show='Compiling|Generating' -- make` (the Makefile
   exports the knobs), then `t/01-sanity` as the gate. Rakudo's own
   compile (CORE.c etc.) will hit refusals of its own; run it WITHOUT
   strict first, then census with `NQP_CODE_BAIL=1` on a controlled
   `--output` compile.
3. Then `jast2bc`'s bytecode FALLBACK is deletable for nqp (plan items 5-6
   in `docs/jvm-truffle-only-plan.md`).
4. Open task: name anonymous blocks in backtraces (`<anon>` → at least
   `anon_N`, via RakuAST/QAST block naming).

## Recipes (the tmp/ artifacts of the previous session are gone)

- Strict loop: `NQP_CODE_STRICT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1
  NQP_CODE_PRECOMP=1 raku tools/build/watched-run.raku --log=strict.log
  --show='> Task :stage' --show='code-bail' --show='BUILD' --show='rror'
  -- ./nqp/gradlew -p nqp clean buildJvm` (≈5 min to the first stage2
  error, ≈10 min green).
- Stage1 runner (old-encoder compiler, NEW encoder for what it compiles):
  copy `nqp/nqp-j-gradle`, point its lib dir at `nqp/build/jvm/stage1`, add
  `--module-path=<stage1> --setting-path=<stage1>`. Tests a new encoder
  op in seconds without a stage2 build.
- Isolating a stage2 runtime failure: compile `nqp/build/jvm/stage2/nqpmo.nqp`
  and `.../NQPCORE.setting` (the gen-cat'd sources) with the stage1 runner
  (`--bootstrap --no-regex-lib --target=jar --setting=NULL`) into one dir,
  point `--module-path`/`--setting-path` at it, and run probes; that pairs
  new-encoder setting/HOW code with the old compiler.
- Runtime-only rebuild: `./nqp/gradlew -p nqp :nqp-truffle:jar syncRuntimeJars`
  (~10s), then rerun `nqp/nqp-j-gradle` — no stage recompile needed.
- Tracing knobs: `NQP_CODE_TRACE=1` (block entries), `NQP_UNWIND_TRACE=1`
  (loop unwind arms), `NQP_ATTR_TRACE=1` (slow-road @/% attribute reads).

## Honest census (was)

`~374` actual refusals ranked stringify 116, preinc 95, falsey 61, postinc
28, for 24, intify 22, predec 10, tail ~18, regex 6. All of the op cluster
is now covered; the strict build proves the nqp bootstrap has none left.
Deeper background: `docs/jvm-jesp.md`, `docs/jvm-truffle-only-plan.md`,
`docs/jvm-truffle-migration.md`.
