# Upstream merge, 2026-09-22 — UNVALIDATED

`origin/main` (`f890e01c53`, 2026-09-22) merged into the milestone-8 Phase C
work tip (`f2693015b2`). **Nothing here has been built or tested.** It was
prepared on a box that cannot afford the ~800 s build, for validation
elsewhere. Treat every resolution below as a claim to be checked, not a
result.

## Why a merge and not a rebase

The standing handoff rule is to rebase onto upstream main. That rule was
formed while upstream drift stayed clear of our patch surface. It no longer
does: upstream moved the whole begin-time family out of the
`RakuAST::BeginTime` role in `begintime.rakumod` and into `RakuAST::Node` in
`base.rakumod`, and our `#?if jvm` patches live inside those methods.

Rebase cost scales with (conflicting commits x conflicting files): 16 of our
283 commits touch `src/Raku/ast`, and each would re-hit the same relocation
against a base that keeps shifting, resolved without ever seeing the end
state. A rebase attempt was made first and abandoned after two commits had
produced six conflicts, one of them the relocation above.

Merge cost scales with conflicting files alone: 17 files overlap, 10
auto-merged, 7 conflicted, 14 hunks, each resolved once against both sides'
final state. The rebase attempt was aborted cleanly; the work branch was
never moved.

## Resolutions

### Taken from upstream outright

**P5Regex is gone.** `src/Raku/Actions.nqp`, `src/Raku/Grammar.nqp` — upstream
removed Perl 5 regex support entirely: the `use NQPP5QRegex`, the `P5Regex`
slang registration, `Raku::P5RegexGrammar`, `Raku::P5RegexActions`, and the
`$P5` parameter of `method Regex`. We had been doing the same thing for JVM
only, behind `#?if !jvm`. Upstream's removal supersedes ours, so the guards
are dropped and upstream's `method Regex() { self.slang_grammar('Regex') }`
stands. Verified: no `P5Regex`/`NQPP5QRegex` residue under `src/Raku/` or
`tools/build/`, and no caller passes an argument to `.Regex(`.

**`src/Raku/ast/begintime.rakumod`** — took upstream's refactor whole. The
family (`IMPL-BEGIN-TIME-LOOKUP-STATE`, `IMPL-BEGIN-TIME-EVALUATE`,
`IMPL-BOX-VM-VALUE`, `IMPL-BEGIN-TIME-ARGLIST`, `IMPL-BEGIN-TIME-CALL`) now
lives in `base.rakumod`; this file keeps `ensure-begin-performed` and
upstream's newly extracted `IMPL-MARK-BEGIN-PERFORMED`. Diffing our copies
against upstream's relocated ones showed our only substantive change in the
entire family was the `RAKUDO_DEBUG_TRAIT` probe, re-sited below.

**`RakuAST::IMPL::Context` -> `RakuAST::IMPL::QASTContext`** in
`code.rakumod`'s `IMPL-STUB-PHASERS`. `RakuAST::IMPL::Context` is declared
nowhere; it entered in upstream's own `edf67891f4` (2023) and upstream has
since cleaned it up. The merge already took that fix at the file's two
non-conflicted sites, so this only lingered where our commit touched the
line.

### Kept from our side

**`src/Raku/ast/base.rakumod`** (not itself conflicted) — the
`#?if jvm` `RAKUDO_DEBUG_TRAIT` rethrow was re-sited by hand into upstream's
relocated `IMPL-BEGIN-TIME-EVALUATE`, in the `CATCH`'s `CheckTime` branch,
ahead of `self.add-sorry`. **This is the resolution most worth checking.**

**`nqp::isconcrete($!let)`** in `IMPL-STUB-PHASERS`, over upstream's bare
`if $!let`. The adjacent `$!temp` branch auto-merged carrying the same
`isconcrete` treatment, which is the consistency argument for it.

### Both sides kept

- `code.rakumod` `RakuAST::OnlyStar`: our `#?if js` `is
  RakuAST::ImplicitLookups` plus upstream's `does RakuAST::RegexBody`, ours
  grouped with the other `is` traits.
- `code.rakumod`: our `#?if jvm IMPL-STATIC-CLONE-ROAD` (milestone 7 A6')
  plus upstream's new `IMPL-CODE-CARRIER`.
- `code.rakumod` `IMPL-QAST-FORM-BLOCK`: our `$block.custom_args(1)` plus
  upstream's `add_local_debug_mapping` loop. Independent; ours first.
- `traits.rakumod`: our `#?if jvm` `RAKUDO_DEBUG_TRAIT` probe, pushing to
  upstream's renamed `$!trait-sorries` rather than `$!sorries`.
- `variable-declaration.rakumod`: our per-reason
  `IMPL-DECLINE-LOCAL-NAME(...)` diagnostics, with upstream's new
  `$!shares-implicit` condition added as one more decline reason.

### The one that changes generated code

**`tools/build/raku-ast-compiler.nqp`.** Ours splits the RakuAST bootstrap
into a `BEGIN` block per 16 packages (the fix for the ~500k-instruction
mainline that could not compile inside a 14 GB heap). Upstream introduced
`order-packages(@compunits)`, which yields `[$cu, $package]` pairs in
composition order so every role precedes the classes that do it.

Resolved by driving our block-splitting loop from `order-packages` instead of
the nested `for @compunits { for .packages { ... } }`. `BEGIN` blocks run in
parse order, so splitting preserves the composition order upstream now
establishes — **but this is reasoning, not evidence.** It changes the
generated `ast.nqp`, so it is the second thing to check.

## What to validate first

1. Full `make` (`RAKUDO_RAKUAST=1`), which exercises the regenerated
   `ast.nqp` and so the `raku-ast-compiler.nqp` resolution.
2. `t/01-sanity` (25 files).
3. A `RAKUDO_DEBUG_TRAIT=1` run, to confirm the re-sited probe in
   `base.rakumod` still fires from its new home.
4. `docs/jvm-full-suite-run-2026-09-05.md` remains the FAIL checklist.

## Companion state

- nqp rebased cleanly onto `upstream/main` with zero conflicts:
  `jesp-direct-lazy-records-rebased-2026-09-22` (`9e7638226`). 222 commits
  preserved, only upstream's 6 files differ.
- nqp stage0 is now committed at serialization format 12. Before that a fresh
  clone could not bootstrap at all: `SerializationReader` declares
  `MIN_VERSION = CURRENT_VERSION = 12` and the committed stage0 predated the
  format change.
