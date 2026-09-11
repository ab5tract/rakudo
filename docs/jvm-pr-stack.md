# The JVM/Truffle PR stack (2026-09-11)

The two work branches -- rakudo `worktree-jesp-direct-lazy-records` (252
commits over rakudo/rakudo main) and the nested nqp `jesp-direct-lazy-records`
(373 over Raku/nqp main) -- were rewritten on 2026-09-11 into a stack of 21
pull requests against the `main` branch of the ab5tract forks
(github.com/ab5tract/rakudo, github.com/ab5tract/nqp). Both fork mains were
fast-forwarded to their upstreams first, so every PR diff is our work only.
The pre-rewrite branches are kept as `backup/pre-pr-stack-2026-09-11` on
both forks. The rewrite is tree-identical: the tip of each rebuilt branch
has exactly the tree of the backup.

Rulings behind the shape (user, 2026-09-10): pre-superpowers work in
thematic PRs (Kotlin+Gradle, newdisp, regex engine, code engine, Phase 5,
NFG, jesp, frontend trim), one PR per unit-artifact milestone with
milestone 2 folded into milestone 1; net-zero experiments squashed away
where they start and end inside one PR (the ones spanning PRs are named in
the plan files as `# spans:`); lab-notebook docs collapsed to their final
conclusions; process artifacts (`docs/superpowers/`) stay in the milestone
PRs; landing order is the interleaved stack below, each rakudo PR naming
the nqp PR it needs. Rewritten commits carry the first source commit's
author and calendar day, stamped after work hours (18:00-23:00; user,
2026-09-11).

## Landing order

Each PR's base is the previous PR's branch in the same tree (`main` for the
first); merge top to bottom. A rakudo PR builds only against the nqp PR in
its `needs` column, merged first.

| # | tree | branch | needs | commits | title |
|---|------|--------|-------|---------|-------|
| 1 | nqp | `pr/01-gradle-kotlin-runtime` | – | 20 | Gradle build, ASM 9, Java 25, and the runtime in Kotlin |
| 2 | rakudo | `pr/01-gradle-kotlin-runtime` | nqp 1 | 4 | Gradle build and the runtime layer in Kotlin |
| 3 | nqp | `pr/02-newdisp-port` | – | 16 | The newdisp dispatch port, diagnostics and parity |
| 4 | rakudo | `pr/02-rakudo-on-newdisp` | nqp 3 | 17 | Rakudo on newdisp: scaffolding, the flip, semantics parity |
| 5 | nqp | `pr/03-truffle-regex-engine` | – | 16 | The Truffle regex engine, to feature-complete |
| 6 | rakudo | `pr/03-grammar-engine-eval-server` | nqp 5 | 12 | The grammar engine adopted; eval server, sweep tooling, static-code identity, Perl6 -> Raku |
| 7 | nqp | `pr/04-truffle-code-engine` | – | 12 | The Truffle code engine, phases 1-4 |
| 8 | rakudo | `pr/04-truffle-code-engine` | nqp 7 | 3 | The Truffle code engine phases 1-4, Rakudo side |
| 9 | nqp | `pr/05-phase5-encode-coverage` | – | 15 | Phase 5: encode coverage to 96.5% and the classlib registry |
| 10 | rakudo | `pr/05-phase5-fixes` | nqp 9 | 11 | Phase 5: Rakudo-side fixes and the coverage campaign's conclusions |
| 11 | rakudo | `pr/06-legacy-frontend-trimmed` | nqp 9 | 3 | The legacy Perl6 frontend trimmed: RakuAST is the only frontend |
| 12 | nqp | `pr/06-nfg-trufflestring` | – | 5 | NFG on TruffleString, and the engine as the only regex road |
| 13 | rakudo | `pr/07-nfg` | nqp 12 | 2 | NFG on the JVM |
| 14 | nqp | `pr/07-jesp-calling-convention` | – | 15 | jesp: the calling convention, sited ops, and strict encoding |
| 15 | rakudo | `pr/08-jesp-calling-convention` | nqp 14 | 11 | Calling convention, jesp diamonds, and the strict-refusal campaign, Rakudo side |
| 16 | nqp | `pr/08-unit-artifact-m1-m2` | – | 8 | Unit artifact: the format, the loader, UnitMain and the record road (milestones 1+2) |
| 17 | rakudo | `pr/09-unit-artifact-m1-m2` | nqp 16 | 4 | Unit artifact milestones 1+2: the Makefile enters nqp through UnitMain; spec, plans, ledgers |
| 18 | nqp | `pr/09-unit-artifact-m3` | – | 8 | Unit artifact: the unit road and the encoder as the defaults; the compiler-side class road removed (milestone 3) |
| 19 | rakudo | `pr/10-unit-artifact-m3` | nqp 18 | 3 | Unit artifact milestone 3: Rakudo on the unit road |
| 20 | nqp | `pr/10-unit-artifact-m4` | – | 13 | Unit artifact: QAST-only compiler, stage0 as unit artifacts, the class road deleted (milestone 4) |
| 21 | rakudo | `pr/11-unit-artifact-m4` | nqp 20 | 7 | Unit artifact milestone 4: the Raku op file, AdaptorUnit, the fix wave; docs |

PR URLs: see `docs/superpowers/plans/2026-09-11-pr-stack/prs.tsv` (written
when the PRs were opened).

Hazards that shaped the boundaries (from the survey in
`docs/superpowers/plans/2026-09-10-jvm-unit-artifact-milestone-4.reports/pr-sections-survey.md`):
stage0 jars stay in the PR whose compiler produced them (nqp 1, 3, 14, 20);
`UnitMain` (nqp 16) is the entry contract every rakudo PR from 17 on needs;
NFG spans both trees on one day (12 + 13); nqp 18 ends with the sidecar
crutch that nqp 20 removes. Doc *contents* still cite pre-rewrite hashes
(hazard H5); the backup branches keep those hashes resolvable.

## How it was built: `tools/build/pr-stack.raku`

One `*.plan` file per PR (format in
`docs/superpowers/plans/2026-09-11-pr-stack/FORMAT.md`; the 21 plans used
are next to it) lists groups of source commits; each group becomes one
commit, cherry-picked `--no-commit` in the listed order and committed with
the group's message (`= keep` reuses the source message verbatim). Squash-
only groups in history order cannot conflict; the curated reorders were
proved file-disjoint first and are marked `# moved:` in the plans.

    raku tools/build/pr-stack.raku check PLANDIR --tree=SCRATCH --base=upstream/main --head=HEAD
    raku tools/build/pr-stack.raku build PLANDIR --tree=SCRATCH --base=upstream/main --head=HEAD \
        --trailer='Co-Authored-By: ...'

`check` proves the plans cover `base..head` exactly once; `build` runs in a
scratch `git worktree`, puts each PR's branch at its last group, records
progress for `--resume` after a conflict, and refuses to succeed unless the
final tree equals `head`. Both trees rebuilt in about ten seconds each.

## Going forward

Each milestone is one PR (or a small stack) on top of the previous one, in
both trees, nqp first; rebase onto upstream main at every handoff as
before. The work branches now ARE the rewritten history: rakudo
`worktree-jesp-direct-lazy-records` = `pr/11-unit-artifact-m4`, nqp
`jesp-direct-lazy-records` = `pr/10-unit-artifact-m4`.
