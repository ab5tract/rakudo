# SDD ledger — plan: docs/superpowers/plans/2026-09-15-jvm-milestone-7-first-execution-phase-b.md

Spec: docs/superpowers/specs/2026-09-13-jvm-milestone-7-first-execution-design.md
(rakudo 83375a77ae), Phase B, over the lazy-loading spec's tasks 1.1-1.6
(docs/superpowers/specs/2026-09-13-jvm-lazy-unit-loading-design.md, Revision 3).
Plan committed rakudo 36ce45c326 (2026-09-15), pushed to ab5tract.

BASE before Task 1: rakudo 36ce45c326, nqp fdab66706 (Phase A's close; the
a6 rig row: cold rakudo-e 2.504 s, cold nqp-e 1.192 s, misses 5661, hits
100697).

Claude-Session trailer for this phase's commits: not known to the writing
session; Phase A's URL (session_01GK4DKrQFQgNaiYirUzjcgJ) is NOT reused.
Commits carry the Co-Authored-By trailer only until the controller learns
its own URL (user rule: never fabricate).

Model policy (user rule 2026-09-11): subagents on Opus; Fable only after
erroneous output; escalations logged here.

The plan's twelve rulings (open to the user's veto until Task 3 writes the
format):
1. v1 is fully deflated; v2 entries are stored (CORE.c jar ~5.9 -> ~13 MB), sizes recorded not reduced.
2. unit.serialized is LZ4'd today; v2 writes it raw and hands the mapped slice to the reader.
3. The call-site table is dead; v2 drops it; Phase C carries the descriptor inline.
4. Every shell is built eagerly (the reader needs 97 % of them); bodies are what get lazy.
5. Static lexical values live per block and are applied on body fill, queued until the SC is ready.
6. Roots have no unit identity today; the compile key "<unit>#<index>" names the Source for store-backed units; in-memory units keep the text key and get no identity.
7. Loop bodies are emitted twice; the ordinal is keyed by the DISPATCH node's wire offset; the encoder's per-block count sizes the slot table; NQP_SITE_CHECK compares.
8. Helper, rv-decont and indy sites have no identity; the schema tolerates it.
9. In-memory units take the same store road through a heap image; v1 is transcoded into that image during the window.
10. The mh identity test at CallFrame.kt:40,320 and Syscalls.kt:396,409 becomes staticInfo identity before mh goes lazy.
11. kotlinx AbstractEncoder/AbstractDecoder under @OptIn(ExperimentalSerializationApi) (deviation from "stable API only").
12. Gates: window build = nqp suite + make + t/01-sanity + ONE warm t/02-rakudo before stage0 regeneration; steps 2 and 3 = nqp suite + make + t/01-sanity.

## Pre-flight scan (controller, before Task 1)

Pairs sharing a file or an interface:

| tasks | produced / consumed | found |
|---|---|---|
| 2 / 3 | `UnitCodec.encode(serializer, value): ByteArray`, `decode(serializer, ByteBuffer)` | consistent |
| 3 / 5 | `UnitStore` (open/isUnit/programIndex/outerQbid/blockRecord/program/dispatchSlot/serialized/nested/entry), `UnitImage`, `BlockEntry`, `UnitImageWriter.bytes/write` | consistent; `entry()` maps `unit.X` to `nested/<id>.X` for a nested store |
| 3 / 6 | `dispatchCounts` per program from `BlockRecord`'s `dispatches` | consistent (RecordReader maps block count to its program index) |
| 4 / 5 | `CodeRef(compUnit, mh, name, uniqueId, argsExpectation, source)`, `StaticBodySource.fill`, `finishBody()` internal, setters never fill | consistent; `staticCode` is set by the CodeRef shell ctor (`this`) |
| 4 / 6 | none (Task 6 reads only shell fields `programIndex`, `compUnit`, `methodName`) | consistent |
| 5 / 6 | `CodeEngines.materialize` tests `cu is ProgramUnit`; `UnitWriter.store`; `RecordReader.intOr("$!dispatches", 0)` | consistent |
| 5 / 7 | Task 7 Step 5 adds `unit-check` to `ProgramUnit.buildTable` | consistent |
| 5 / 9 | Task 9 deletes `UnitZip`/`UnitRecord`/`UnitFormat` and the transcoder Task 5 added | consistent |
| 2 / 9 | Task 2 adds kotlinx to `NqpDeps`; Task 9 removes lz4 if unused | consistent |
| 1 / 7 | Task 1's gradle/rakumod edits are first compiled by Task 7 | consistent |
| 6 / 7 | `site-check` (engine) and `unit-check` (runtime) lines under `NQP_SITE_CHECK` | consistent |

Each task against itself:

| task | check | found |
|---|---|---|
| 1 | stage classpath set at configuration time with `thirdPartySorted()` | **defect**: resolving the configuration at configuration time; Ruling below |
| 2 | `@Serializable data class N` declared inside a test function | **defect**: the kotlinx plugin does not serialize local classes; Ruling below |
| 2 | layout test bytes vs codec (`2,0,0,0,'a','b',4,3,2,1`; null mark `[0]`, `[1,0,0,0,0]`) | consistent |
| 3 | test expectations vs `UnitStore` messages ("unit.programs index 3", "unit.records index 4", "version 9", name "<cut>") | consistent |
| 3 | `program(0).length == 70006` = "PROG0 " + 70000 | consistent |
| 4 | `cloneFillsFirst` expects distinct `oLexStatic` after clone | consistent with `clone()` |
| 4 | `finishBody` internal, called from the test source set | consistent (same module) |
| 5 | `staticLexValuesWaitForTheSc` needs `deserializeQbid = -1` and an SC "sc-x" with an object at 7 | consistent, fixture built by `unitWithSc()` |
| 6 | Java calls `identity.site(ordinal).getKey()` on a Kotlin value class | **defect**: a value class is its underlying type in Java; Ruling below |
| 6 | `siteOrdinals.computeIfAbsent(at, k -> siteOrdinals.size())` | reads the map inside the mapping function only; allowed |
| 7-9 | commands and gates | consistent with the Global Constraints |
| 10 | rig `--tag=b`, default `--warm=proxy` | consistent with the rig's MAIN |

Rulings from the scan:
- Ruling: Task 1 sets the stage tasks' `classpath` inside `doFirst` (where the old `-Xbootclasspath/a` string was built), not at configuration time — `thirdPartySorted()` resolves the `nqpThirdParty` configuration, which must stay lazy — costs if wrong: a configuration-cache warning, nothing functional.
- Ruling: Task 2's `nullMarkIsOneByte` declares `N` as a nested `@Serializable data class` of the test class, not a local class — the kotlinx compiler plugin rejects local serializable classes — costs if wrong: nothing.
- Ruling: Task 6 exposes `ProgramIdentity.siteKey(ordinal: Int): String` and the Java builder calls that; `SiteIdentity` stays as the Kotlin-side value class — costs if wrong: nothing.
- Ruling: the SDD workspace's `progress.md` is a symlink to this file; this file is the one ledger (Phase A's convention) — costs if wrong: nothing.

## Task log

Task 1: complete (commits nqp fe007f3f8, rakudo = the commit carrying this ledger; built by Task 7)
Task 1 note: this phase's commits carry only the `Co-Authored-By` trailer — the session URL for the `Claude-Session` line was not available to Task 1's session, so no such trailer was written.
