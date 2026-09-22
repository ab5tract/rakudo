# SDD working artifacts (milestones 6 and 7)

This branch carries the per-task working artifacts that the superpowers
SDD workflow writes to `.superpowers/sdd/`, which `.superpowers/sdd/.gitignore`
(a single `*`) keeps out of every normal commit. They are preserved here so
they survive a move to another machine.

These are NOT the authoritative ledgers. Those live on the work branch and
always have:

    docs/superpowers/plans/*.md          the plans
    docs/superpowers/plans/*.ledger.md   the ledgers
    docs/superpowers/specs/*.md          the designs

covering milestones 6, 7 and 8 (all phases). What is here is the layer below
them -- per-task briefs and reports, review packages, and the raw
`review-<base>..<head>.diff` captures -- useful when reconstructing why a
task landed the way it did.

Milestone 8 has no directory here: it was run subagent-driven, and its record
went straight to the tracked ledgers.

To restore in place, check this branch out into a scratch tree and copy
`.superpowers/` next to the work branch's checkout.

Branch cut 2026-09-22 from work-branch state:
  rakudo  f2693015b2  worktree-jesp-direct-lazy-records
  nqp     efee800a3   jesp-direct-lazy-records
