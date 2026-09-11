# Squash-plan format (PR-stack rewrite, 2026-09-11)

One plan file per PR. The rebuild tool starts from the tree's upstream main and, for each
group in file order, cherry-picks the listed commits (in the listed order) and squashes them
into ONE new commit with the given message. The last group of a PR file marks that PR's
boundary. The final tree must be byte-identical to the current branch head.

```
pr: n1
title: JVM: Gradle build, ASM 9, Java 25 and the Kotlin runtime

= <subject line of new squashed commit 1>
<optional body line>
<optional body line>
- 52b298a69
- 1a2b3c4d5
- ...

= keep
- 9f8e7d6c5

= <subject line of new squashed commit 3>
- ...
```

Rules:
- `pr:` and `title:` once at the top. Lines starting with `#` are comments (ignored).
- A group starts at a `= ` line. `= keep` (exactly) means the group has exactly ONE commit
  and its original message is reused verbatim.
- Body lines are the non-empty, non-`- ` lines after the subject until the first `- ` line.
  Blank lines are ignored. Keep the body 0-6 lines; state what the commit contains, in
  the branch's own voice. No git hashes of either tree anywhere in subjects or bodies
  (hazard H5: every hash changes in the rewrite).
- `- <hash>` lines: abbreviated hashes exactly as in the log dump. Anything after the hash on
  the line is ignored (you may paste the subject for readability).
- Every commit of the assigned range appears exactly once across the PR's groups.
- ORDER. Commits inside a group and groups inside a file are applied in file order. The
  DEFAULT is the original chronological order (contiguous runs). You may pull a commit
  earlier/later than its neighbours ONLY when `git show --stat` proves the moved commit's
  files are disjoint from every commit it jumps over (docs-only commits jumping over
  src-only commits are the typical safe case). Mark such a group with a `# moved:` comment
  naming the hashes moved and why. If a move is not provably safe, don't move.
- NET-ZERO roads (a knob/road introduced and removed inside the section) must vanish: put the
  introducing and the removing commit in the same group. Use a safe move if needed; if the
  removal is in a LATER section, say so in a `# spans:` comment and leave both in place.
- Subject lines: <= 72 chars, in the style of the branch (lower-case area prefix such as
  `runtime:`, `encoder:`, `JVM:`, `docs:`, `Truffle engine:` -- copy the style the section
  itself uses). Subjects describe what the squashed commit contains, not the wrong turns
  that preceded it.
- Docs lab-notebook commits (running percentages, bisections, retracted diagnoses): squash
  into ONE "findings and final conclusions" docs commit per PR; the body states the final
  conclusions only.
- stage0 jar regenerations (`src/vm/jvm/stage0/*.jar`) stay in the group of the compiler
  change that produced them; never move a stage0 commit across other stage0 commits.
- Revert pairs and WIP commits are squashed into their neighbours so they never appear.
