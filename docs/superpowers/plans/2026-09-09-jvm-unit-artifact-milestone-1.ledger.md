# SDD ledger — plan: docs/superpowers/plans/2026-09-09-jvm-unit-artifact-milestone-1.md

Spec: docs/superpowers/specs/2026-09-09-jvm-unit-artifact-design.md (reachable, binding).
Trees: rakudo worktree (docs, gate) at ebe2f4559; nested nqp/ tree (all code) at d13dcbf69, branch jesp-direct-lazy-records.
Note: review packages for nqp commits are generated with git run in the nqp dir (the skill script assumes one tree).

## Pre-flight scan (2026-09-09)

| pair / task | produces vs consumes | finding |
|---|---|---|
| T1 -> T3 | BlockRec.handlers flat LongArray; ProgramUnit.unflatten | consistent |
| T2 -> T3 | ProgramEntry.ENTER type (tc, cr, csd, Frame, Object[]) vs StaticCodeInfo.init branch 2 (count>=4, param 3 == Frame) | consistent |
| T2 -> T4 | serializedBlob/claimNested/unitId/engineProgram hooks used by ProgramUnit, UnitLoader, EvalServer | consistent |
| T2 -> T5 | CodeEngines.materialize(sci) | consistent |
| T4 -> T8 | UnitMain argv[0] = unit path; runner passes "$LIB_DIR/nqp.jar" first | consistent |
| T6 -> T7 | JAST::Class fields ($!hll .. @!blockvalues), JAST::Method $!cr_qbid/$!cr_program vs JastClass/JastMethod reads; Backend reads unit_road/fallbacks | consistent; programs handed as a BOXED list (Ruling below) |
| T7 vs spec | writer refuses nested units | Ruling below (deviation stated in plan) |
| T7 test | UnitMod symbol road after loadbytecode is unverified; plan gives the fallback (dynamic compile with module-path, follow existing t/nqp module tests) | implementer adapts, reviewer checks the test asserts real behaviour |
| T9/T10 | gate order: per-change gate is T9; Rakudo make once after (user rule) | consistent |
| rubric | JastClass/JastMethod read new fields inside try/catch (mirrors existing codePrograms/isThunk readers) | may be flagged as swallowed errors; ruling deferred to review |

Ruling: @*ENGINE_PROGRAMS is copied to a boxed list before the writer reads it — native str lists have no at_pos_boxed road — costs one copy per unit compile if wrong.
Ruling: nested BEGIN-time units are refused by the writer in milestone 1 (runtime compiles still produce classes until milestone 2); the format/loader support them — if nqp stage2 has any, milestone 2's in-memory road moves ahead of the gate — costs a second build if wrong.

## Tasks
Task 1: implemented (nqp 47f7db168), review dispatched.
Side fix (user request, outside the plan): nqp-truffle/build.gradle.kts delegated-property deprecations removed (controller edit, verified --warning-mode all clean).
Task 1: minor (deferred): UnitZip.write DEFLATEs the already-LZ4 entries (could be STORED per entry)
Task 1: minor (deferred): UnitZip.read outerQbid check only rejects >= size, not values below -1
Task 1: minor (deferred): no test for unexpected-entry / missing-entry hard errors in UnitZip.read
Task 1: minor (deferred): unused catch variable in UnitZip.isUnit
Task 1: complete (nqp commits d13dcbf69..47f7db168, review clean)
Task 2: implemented (nqp 96f0ca37d, DONE_WITH_CONCERNS: widened jvmclaimnested catch double-wraps the cuid-mismatch dieInternal), review dispatched.
Task 2: review -> Needs fixes: Important (plan-mandated) jvmclaimnested catch(Exception) swallows ControlException / re-wraps dieInternal; Minor (deferred): serializedBlob drops the local IOException->dieInternal conversion; Minor (deferred): trace line duplicated in codeRunUnit
Task 2: Ruling: tighten the catch — wrap only cu.claimNested(...) itself, rethrow ControlException first, keep the cuid-loop and its dieInternal outside the try (spec 5: errors surface as they do now, outranks the plan text) — costs one more nested-load failure shape to test if wrong
Ruling (user, 2026-09-09): eval server moved from milestone 1 gate to milestone 3; Task 8 = runners only; Task 9 step 3 = t/nqp via nqp-j-gradle --jobs=3; Task 4 keeps LibraryLoader.loadApp/prime + EvalServer edit (needed by milestone 3, cheap now) -- costs nothing if wrong beyond a later revert of the EvalServer edit
Task 2: fix round 1/5 (1 addressed pending re-review, 0 open — claim catch narrowed; nqp commits 96f0ca37d..6d3d7d8c4)
Task 2: fix round 1/5 re-review: 1 addressed, 0 open, no new breakage
Task 2: complete (nqp commits f3df464e9..6d3d7d8c4, review clean after round 1)
Task 3: implemented (nqp 7a2be3832, 9/9 Kotlin tests), review dispatched.
Task 3: review Approved; Important (plan-mandated): no unit test for applyStaticLexValues / claimNested / runDeserializeIfAvailable ordering
Task 3: Ruling: accepted as deferred — those paths are exercised by Task 7 t/nqp/123 (real module load: deserialize + static lexical values) and by every stage2 unit in the Task 9 gate; a ThreadContext-free unit test would need a fake SC registry (not worth building now) — costs a late discovery in Task 7 if wrong
Task 3: minor (deferred): ProgramUnitTest never exercises empty lexical-name arrays
Task 3: complete (nqp commits 6d3d7d8c4..7a2be3832, review clean with ruling)
Task 4: implemented (nqp bc1c0a881; UnitMain smoke 42, runner smoke 3, 9/9 tests; loadApp catch list narrowed for javac), review dispatched.
Task 4: review -> Needs fixes. Important (plan-mandated) 1: isUnitFile full-file read per load + eval server re-sniffs per request; Important (plan-mandated) 2: no exception translation on the artifact road; Minor: stale "This class is not an entry point" at the per-request site, record() double read, ThreadDeath wrapper dropped
Task 4: Ruling: fix both Importants now (ZipFile central-directory sniff + per-path road cache for shared loads; translate IOException/IllegalStateException to dieInternal, ControlException passes) and the three minors in the same round — costs one extra round if the ZipFile sniff misbehaves on in-memory jars (buffers keep the byte sniff)
Task 4: fix round 1/5 (5 addressed pending re-review, 0 open — ZipFile sniff + per-path road cache, exception translation, entry-point message, ThreadDeath guard; nqp commits bc1c0a881..cdc444674; one adaptation: @Throws(IOException::class) on the Kotlin loaders since Kotlin has no checked exceptions by default)
Task 4: fix round 1/5 re-review: 5 addressed, 0 open, no new breakage (note: ZipException from in-memory bytes is covered by the outer catch; report rationale imprecise, code fine)
Task 4: complete (nqp commits 7a2be3832..cdc444674, review clean after round 1)
Note: the campaign session committed its custom_args work as nqp d13dcbf69 (10:40) = this plan BASE; nqp tree is clean, no other-session WIP; Task 6 clean build is the first full stage build over that commit (if it breaks in P6BINDSIG code, that is the campaign commit, not Task 6).
Task 5: dispatched (nqp base cdc444674).
Task 5: implemented (nqp 816001582, loop smoke 9999900000), review dispatched.
Task 5: minor (deferred): hasTarget re-crosses the boundary on every replay when the engine is absent (pre-existing degenerate case)
Task 5: complete (nqp commits cdc444674..816001582, review clean)
Task 6: dispatched (nqp base 816001582; opus)
Task 6: implemented (nqp 1517f9cec; clean class-road build 280 s, sidecar count 1, smoke ok; concerns: blockvalues computed before deserialization code, sc_handle/desc only inside deserialization_code), review dispatched (opus).
Task 6: review -> Needs fixes. Important 1 (plan-mandated): blockvalues rows built before nqp::serialize (SC may be unassigned -> scgethandle dies; rows for orphan/wrapper blocks missing). Important 2 (plan-mandated): road decided before fallbacks known -> a fallback unit cannot take the class road unchanged (no sidecar string, no setup_blv). Minors: guard order, BUILD inits, unit_road comment, per-block getlexdyn; nested units keep -1/empty SC fields.
Task 6: Ruling 1: build blockvalues rows immediately after self.as_jast($block) of the deserialize wrapper (where setup_blv would have compiled), keep the setup_blv skip where it is — costs nothing if wrong beyond the same ordering bug reappearing.
Task 6: Ruling 2 (spec amendment): NQP_UNIT is all-or-nothing — at the fallback junction on the unit road, nqp::die naming the block/cuid and pointing at NQP_CODE_BAIL/NQP_CODE_WHY; no per-unit class-road fallback; the class road is chosen by not setting the knob (Rakudo builds without it in milestone 1). fallbacks field stays (always 0) as defense for the writer. — costs a build stop on the first refusal under the knob, which is exactly the strict rule.
Task 6: fix round 1/5 (5 addressed pending re-review, 0 open — rows after as_jast of the deserialize wrapper, fallback junction dies, guard order, BUILD inits, accessor comment; nqp 1517f9cec..ac33e510c; class-road build 280 s green, sidecar 1, smoke ok)
Task 6: fix round 1/5 re-review: 5 addressed, 0 open, no new breakage (note: nested unit + unit road untested; writer refuses nested in milestone 1)
Task 6: complete (nqp commits 816001582..ac33e510c, review clean after round 1)
Ruling: Task 8 runs BEFORE Task 7 — compileP5qregex (part of buildJvm) executes nqp-j-gradle, whose main class is still `nqp`; with stage2 nqp.jar an artifact the Task 7 NQP_UNIT build would fail there. UnitMain takes either road, so the runner switch is safe on the class road today — costs nothing if wrong.
Task 8: dispatched (nqp base ac33e510c; sonnet)
Task 8: implemented (nqp 15c20930c; generateRunner regenerated, smoke ababab; used the file's own `lib` interpolation instead of a nonexistent $LIB_DIR), review dispatched.
Task 8: complete (nqp commits ac33e510c..15c20930c, review clean)
Task 7: dispatched (nqp base 15c20930c; opus)
Rule (user, 2026-09-09): subagents run every >30 s build/test through tools/build/watched-run.raku; dispatches carry the command verbatim; reviewers look for the EXIT/verdict/elapsed line. Tooling is written in Raku, never Python/shell (the census.sh driver of this morning should have been Raku).
Task 7: implemented (nqp 4e136970e + 57460ccd7): first artifact build GREEN, 4th attempt, EXIT=0 verdict=ok elapsed=292s; 21/21 stage2+lib jars unit.meta=1 class=0; smoke 42; t/nqp/123 8/8; Kotlin 9/9. Fixes found by the build: native-str bind at the syscall; QAST::VM encoding (jvm alternative); SyncHandle.write NUL-padding (pre-existing runtime bug). Concerns: build needs clean after src/vm/jvm/HLL edits (stage graph); every artifact has 0 call sites; shared ENTER handle identity; full t/nqp + Rakudo gate not run. Review dispatched (opus).
Task 7: review Approved (opus), 8 minors deferred: (1) no upper-bound check on cr_program vs programs.size; (2) 13 record reads share one try/catch, unitRoad read before the lists -> partial failure could write a programless artifact (unreachable today); (3) Backend routes unit_road && fallbacks!=0 to compilejasttofile instead of the writer refusal (unreachable: Compiler.nqp dies first); (4) test 1 asserts jar exists, not compile success (stale jar) -> unlink before compile; (5) test scratch dir anchored on cwd, leaves empty <rakudo>/t/nqp/ when run from the root; (6) multi-line diagnostic dumps break TAP; (7) bare NPE on missing JAST::Class type in UnitWriter; (8) SyncHandle.setInputLineSeparator has the same .array() NUL bug. Verified: zero call sites is correct by construction (W_DISPATCH carries inline descriptors); SyncHandle.write fix correct for both callers; ENTER identity holds via StaticCodeInfo.init rebind.
Task 7: complete (nqp commits 15c20930c..57460ccd7, review clean)
Task 9: dispatched (gate; opus)
Task 9: GATE GREEN — clean NQP_UNIT build EXIT=0 verdict=ok elapsed=273s; 21/21 jars meta=1 class=0; smoke ok; t/nqp 115/115 (113 from root + 019/063 from nqp dir), suite 487 s at 3 jobs; docs rakudo 8942ed0bc2; pushes ab5tract (both) + nqp origin, fast-forward. No triage rounds.
Task 9: review dispatched (docs-only diff, sonnet); Task 10 dispatched in parallel (no code edits; opus)
Task 9: review Approved (evidence corroborated: build log, SUMMARY, jars, remotes); minor (deferred): smoke and 063 rerun not captured to a log
Task 9: complete (rakudo docs b424186d41..8942ed0bc2, review clean)
Task 10: BLOCKED. (1) rakudo tools/templates/jvm/Makefile.in J_NQP_RR enters via main class `nqp` -> with a manual override make succeeded: EXIT=0 elapsed=981s; BOOTSTRAP v6c 339 s; CORE.c 509 s (parse 386.954, optimize 37.123, qast 31.327, jast 33.336, classfile 2.942). (2) t/01-sanity 21/25: the four use-ing files die with "nqpp: unknown tag 11142 at 79 of 1060 words" in a CORE.c custom_args program (tags 33/34 P6BINDSIG/P6TRYBINDSIG, campaign commit d13dcbf69, never validated on Rakudo); reproducer ./rakudo-j -e say("abc".subst(/b/,"x")). Docs commit rakudo 2133c15a5e pushed.
Task 10: Ruling: fix (1) in Makefile.in (milestone-1 scope: the Makefile is a runner entry like nqp-j-gradle); diagnose (2) as encoder-emission vs NqpProgramBuilder-reader layout for tags 33/34 and fix only if it is a layout mismatch (campaign code, but it breaks the shared branch); otherwise report for the user — costs a wasted 20-min make if the diagnosis is wrong.
Task 10: fix agent DONE. rakudo a5f9ef3d80 (Makefile.in enters nqp via UnitMain), 5d31a79f3c (docs). nqp e1c29714e (encoder: custom_args header splice shifts %e<nested> slots by 3 — root cause of "unknown tag 11142": deferred qbids patched 3 cells early), 2035d43e2 (reader: n==0 && accepted==-1 no longer rejects named args on a custom_args block). Gate: configure 3 s, nqp clean build 285 s, make 1173 s, t/01-sanity 25/25 in 210 s. Concern: custom_args exercised only by t/01-sanity; a spectest sweep is the real check. Review dispatched (opus).
Task 10: fix review Approved (opus): patch_params diagnosis confirmed structurally; shift derived from the header list; reader sentinel n==0&&accepted==-1 producible only by custom_args; Makefile substitution + argv parity verified. Important (follow-ups, not defects): (a) four splice sites each shift %e<nested> by hand -> a splice_code(%e,@words,$at) helper; (b) custom_args coverage is only t/01-sanity -> spectest sweep. Minor: NqpWire PARAMS doc lacks the sentinel; sentinel by inference; prog name on the artifact road is meta.unitId.
Task 10: Ruling: (a) splice_code helper is booked as the first item of milestone 2 plan (encoder hygiene, no behaviour change); (b) a spectest sweep is a precondition for milestone 3 and for resuming the strict campaign (custom_args is item 7 work) — not a milestone-1 gate; (c) NqpWire doc sentinel note goes into the final fix wave if the final review keeps it. Costs: a repeat of the splice bug before milestone 2 if (a) waits too long.
Task 10: complete (rakudo 2133c15a5e..5d31a79f3c, nqp 57460ccd7..2035d43e2, review clean)
Final whole-branch review dispatched (fable): nqp d13dcbf69..2035d43e2 (33 files), rakudo ebe2f45594..5d31a79f3c; ledger items handed over for triage.
FINAL REVIEW (fable): With fixes. Fix-before-merge: (1) Backend.nqp routes unit_road && fallbacks!=0 to compilejasttofile -> unconditional writer on unit_road; (2) t/nqp/123 asserts jar exists -> unlink before compile; (3) NqpWire PARAMS doc: the n==0 && accepted==-1 custom_args sentinel. Important-2 (class-road cost): load(tc,ByteBuffer) copies the whole buffer and UnitZip.isUnit walks every entry on Rakudo precomp loads -> first-entry sniff (unit.meta first is now a format rule) + no copy when hasArray. Minors 4-14 recorded in the review; spec corrections: §1 entry order, §2 resume road (engine resumes through RESUME, not the entry function), §2 the wrapper ops needed no encodings (generic road; only QAST::VM did), §4 backtrace attribution is open on both roads. Triage: all other ledger items leave (reasons in the review); Task 10 (b) spectest sweep should run before the branch is built on for unrelated work.
Ruling: the fix wave = items 1, 2, 3 AND the class-road sniff cost (Important 2), one dispatch; items 4, 6, 7 (materialize via programs map; $*UNIT_ROAD requires --output; die once when the run knobs are unset) are the first milestone-2 items; spec corrections done by the controller (docs).
Final fix wave: nqp e2628a882 (Backend unconditional writer on unit_road; t/nqp/123 unlink; NqpWire PARAMS sentinel doc; UnitZip.isUnit first-entry sniff + ByteBuffer overload, load(tc,ByteBuffer) no copy on the class road; new Kotlin sniff tests). Stage build EXIT=0 elapsed=288s; 21/21 jars, unit.meta first; tests 10/10; t/nqp/123 8/8; 019 112/112. Concern: no t/nqp test exercises loadbytecodebuffer, so the class-road buffer fast path is covered by Kotlin tests only. Scoped re-review dispatched.
Final fix wave re-review: 4/4 addressed, no new breakage. MILESTONE 1 COMPLETE: nqp e2628a882, rakudo 0b8dd17591 (docs), both pushed.
