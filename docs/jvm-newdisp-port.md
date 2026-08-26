# The JVM new-dispatch port: status and plan

Assessed 2026-08-27 on the truffle-grammar-engine branch, by feature probe
against MoarVM-RakuAST as the reference. The port is much further along
than its reputation: the infrastructure is complete, all dispatchers are
registered, and nearly every user-visible dispatch behavior already works.

## What exists and works

**Infrastructure** (`org.raku.nqp.dispatch`): dispatch program recording,
replay, guard compilation (`DispatchCompiler`), resumption state
(`DispatchRecord` on `CallFrame`), megamorphic lookup tables, and the
complete `dispatcher-*` / `capture-*` syscall suite -- every syscall the
shared dispatchers file uses, plus JVM-specific extras
(`dispatcher-guard-hll`, `jvm-claim-nested`, `jvm-class-of-cuid`,
`jvm-finish-nested`).

**Registration**: all 33 Raku dispatchers from `src/vm/moar/dispatchers.nqp`
compile into the JVM bootstrap (the file is shared; its single `#?if jvm`
divergence is a reprname string in `raku-invoke`). The JVM adds one of its
own, `raku-hllize`.

**Verified working by probe** (identical results to MoarVM-RakuAST):
method calls, multi dispatch (including Proxy-stripping), method deferral
(`callsame`, `nextsame`, `callwith` in methods), `samewith`, `nextcallee`,
`lastcall`, `.wrap` with wrapper deferral, `CALL-ME` (compiled call
sites dispatched already; runtime-internal invocations since the
`invokeDirect` routing), private methods,
qualified calls (`$obj.Parent::meth`), `.?maybe` calls, smartmatch,
boolification, assignment, sink, return-value decont (per-routine cached
sites), return-value typechecks, coercion types (`Int(Str)`).

**Shared upstream bugs** (fail the same way on MoarVM-RakuAST, so they are
RakuAST issues, not port gaps): `callwith` in multi *subs* (Nil on JVM, an
escaped exception on Moar), and `nextwith` continuation semantics.

**Routing added 2026-08-27**: `Ops.invokeDirect` now sends any non-CodeRef
invokee whose HLL registers a `call_dispatcher` through `lang-call` -- so
`raku-invoke` (custom dispatchers, CALL-ME, wrapper and revision-gate
handling) finally runs for every code-object invocation on the JVM instead
of the legacy `InvocationSpec` attribute extraction. Sites are cached per
(code object, callsite shape) and clear with the rest of the dispatch
state between eval-server runs.

## Gaps

1. **Per-callsite inline caching for plain calls.** MoarVM records a
   dispatch program per call instruction; the JVM routes plain calls
   through a runtime map keyed by (object, shape). Semantics match; the
   per-callsite monomorphic fast path is lost. The constraint is the
   JVM's 65535 indy-plus-constants budget per class, which the core
   setting overflows -- the same limit that forced `RakOps.rvDecontSites`
   to cache per routine rather than per instruction.
2. **Missing syscalls** (Moar has them; the current dispatchers file does
   not call them, so nothing breaks today): the `boolify-*` family,
   `coerce-boxed-*`, `can-unbox-to-*`, `code-bytecode-size`,
   `get-code-outer-ctx`, `try-capture-lex`, `try-capture-lex-callers`.
   The JVM covers the last three through direct RakOps ops instead.
3. **Frame-semantics divergence, not dispatch**: a closure created at
   BEGIN time over a mainline lexical resolves the compile-time frame's
   container where MoarVM's resolves the runtime one (fails
   t/02-rakudo/22-traited-variable-by-name.t). MoarVM's autoclose
   vivifies would-be-cloned lexicals from the serialization context
   precisely to prevent the clone; the JVM's normal-invocation eager
   contvar cloning defeats the unification. Tracked separately -- it is
   older than newdisp.

## Corrections from the deeper audit (2026-08-27, second pass)

- **Call-site dispatch emission already exists.** The JVM QAST compiler's
  call codegen routes every plain `call` through `lang-call` with a
  per-instruction invokedynamic site, inside a 48000-site budget (the
  65535 resolved-references ceiling, minus room for constants), falling
  back to an uncached `dispatchWide` invokestatic past the budget.
  `NQP_JVM_NO_LANG_CALL=1` compiles the old paths for debugging. What
  the `invokeDirect` routing added is the complementary half: the
  runtime-internal invocations (binder, phaser firing, metamodel,
  exit handlers) that never pass through a compiled site.
- **The five "unread" hllconfig dispatchers are all semantically
  covered** by existing JVM paths: resume errors produce X::NoDispatcher
  identically (probed), hllize applies the same transform table the
  config carries, findmethod/istype/isinvokable direct paths agree with
  their dispatcher counterparts on everything the test suite exercises.
  Wiring them through dispatch is uniformity/perf work, not correctness.
- **The nqp-\*ify coercion dispatchers** (registered from Moar's nqp
  ModuleLoader) are reached only through Moar's op lowering; the JVM
  carries those semantics in its direct smart-coercion ops. The
  `coerce-boxed-*`/`can-unbox-to-*` syscalls only matter if that op
  lowering is ever ported; an explicit parity audit of the direct ops
  against the dispatcher programs is the honest outstanding item.

  First audit result (stringify): the case analysis and ordering agree
  (null→'', concrete str-unbox, Str method, type object→'', boxed
  int/num coercion, exception message, die). One real divergence: the
  dispatcher resolves `Str` through full `HOW.find_method` (so HOW
  fallbacks apply) where `Ops.smart_stringify` consults the published
  MethodCache only -- a type whose Str comes from a find_method override
  coerces differently. Error text also differs cosmetically.

  Second audit result (intify/numify): same MethodCache-vs-find_method
  divergence, plus one ordering divergence left in place and documented:
  the JVM unboxes a num BEFORE looking for an Int method where the
  dispatcher prefers the method, so a num-boxed object with an Int
  method truncates on the JVM and method-calls on MoarVM. Two hazards
  were fixed on the spot: `smart_intify` invoked a found Int method
  raw (`invokeDirect`) instead of through the dispatcher -- the
  onlystar-proto resumption hazard `invokeMethodViaDispatch`'s own
  comment warns about -- and both intify and numify dereferenced
  `MethodCache!!` where a cacheless type NPEs (stringify already
  guarded).

## Plan

- **Phase 1 (done)**: `raku-invoke` routing via `invokeDirect`, validated
  by the sanity and t/02/t/10 sweeps.
- **Phase 2 (done in source)**: `try-capture-lex`,
  `try-capture-lex-callers`, and `get-code-outer-ctx` syscalls
  implemented in `Syscalls.kt`, so the `raku-capture-lex(-callers)` and
  `raku-get-code-outer-ctx` dispatchers work when dispatched.
  `code-bytecode-size` stays unimplemented: its only caller is
  `#?if moar` in Code.rakumod. The boolify/coerce syscall families are
  documented non-ports (see above).
- **Phase 3 -- audits over machinery**: parity-audit the direct
  smart-coercion ops against nqp-\*ify's programs; decide per case
  whether findmethod/istype/isinvokable gain anything from dispatch
  routing on the JVM (each is a guarded cache the JVM already has by
  other means).
- **Phase 4 -- frame/container unification** (pre-newdisp bug): give the
  JVM MoarVM's autoclose semantics end to end (bind
  serialization-context originals in auto-closed frames AND make the
  runtime invocation of a BEGIN-reached block agree), which unfudges
  t/02-rakudo/22-traited-variable-by-name.t.
- **Phase 5 -- upstream**: reduce and report the shared `callwith`
  in-multi-sub and `nextwith` RakuAST resumption bugs; they reproduce on
  MoarVM and belong to the frontend.

## Timings

Tracked per the working agreement; environment: 16-core Intel Ultra 9
285H, 30GB, Oracle GraalVM 25.2.4, warm page cache.

| What | When | Time |
|---|---|---|
| Full `make` (legacy-frontend settings) | pre-rebase baseline | ~25 min wall (unmeasured precisely) |
| Full `RAKUDO_RAKUAST=1 make` | post-rebase | ~25 min wall (unmeasured precisely) |
| Sanity sweep (25 files, 1 server) | pre-invokeDirect routing | 44s (2 servers) |
| Sanity sweep (25 files, 1 server) | post-routing | 41s |
| t/01+t/02+t/10 sweep (289 files, 3 servers) | pre-routing | 1861s |
| t/02+t/10 sweep (264 files, 2 servers) | post-routing | 2130s, 3 known failures, 0 regressions |
| Sanity sweep, `--jobs=1` (25 files, 3 serial chunks) | post-routing + Phase 2 | 52s |
| nqp-runtime incremental rebuild + sync | -- | 5s |

Note: sweep runs with different server counts are not directly
comparable; the standard benchmark going forward is the sanity sweep at
`--jobs=1` plus the wall time of one `CORE.c.setting.jar` compile.
