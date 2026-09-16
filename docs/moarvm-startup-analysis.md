# The evaluate-at-startup question: MoarVM against our Truffle/JVM road

Investigation 2026-09-16 (Fable subagent, read-only), asked by the user
during milestone 8 Phase B: does MoarVM also evaluate the giant BEGIN at
startup, and how does it make the setting load cheap? Trees: MoarVM C
source at `../rakudo-upstream-main/nqp/MoarVM/src` (`M=`), nqp's MoarVM
backend `../rakudo-upstream-main/nqp/src/vm/moar/`, RakuAST under this
worktree's `src/Raku/ast/` (`W=`), our JVM runtime `nqp/src/vm/jvm/`.

## Headline

1. **The giant BEGIN is not a startup cost on either VM.** Everything
   BEGIN-time (types, STables, code objects, closures with their contexts,
   GLOBAL) is serialized into the SC blob when BOOTSTRAP/CORE.c compile.
   Startup deserializes; it never re-runs the BEGIN blocks. The JVM-only
   pain was compiling the one-block form (the 64 KB method limit), fixed
   by the 33-block split on 2026-09-01.
2. **MoarVM DOES execute the setting's package bodies at load, exactly as
   we do.** The compilation unit's load frame is a call of the mainline
   (`W/compunit.rakumod:760-763`, upstream `compunit.rakumod:699-711`,
   same on both VMs), and a package body is an immediate block in that
   mainline (`W/package.rakumod:590-611`). CORE.c's 1207 bodies, their
   capturelex prologues and the 1148 clones run on MoarVM too, and so do
   the ~4600 cold dispatcher-program runs (`M=src/disp/inline_cache.c:65-78`;
   MoarVM persists no dispatch programs across processes).
3. **The 28x gap is per-unit cost, not structure.** MoarVM `raku -e 'say 1'`:
   0.08 s wall (5 runs, Rakudo v2026.08 / MoarVM 2026.08; spesh and JIT off
   change nothing at this scale). Ours: 2.25 s. Their body is a C frame
   push and a pointer store; ours runs the Truffle DSL interpreter cold and
   spins LambdaForms per miss (interpreter self 35.7 %, java.lang.invoke
   7.6 %, miss/record/realize 9.3 % of our profile).
4. **Their SC read is lazier than our lazy-loading spec, and 3.6x smaller.**
   CORE.c SC data on MoarVM: 7.83 MB (5,247 STables, 234,322 objects,
   11,020 closures, 2,311 contexts, 152 repossessions). Ours:
   `unit.serialized` 28.17 MB for the same SC.

## What MoarVM runs at startup (`raku -e 'say 1'`)

- `ModuleLoader.load_setting` → `nqp::loadbytecode`
  (`nqp/src/vm/moar/ModuleLoader.nqp:462-491`); `$*MAIN_CTX` comes from
  the mainline's ctxsave (:481-483), proof the mainline runs.
- `MVM_load_bytecode` (`M=src/core/loadbytecode.c:112-146`): mmap
  (`MVM_cu_map_from_file` :132), `run_comp_unit` (:18-36) invokes the
  deserialize frame, then `run_load` (:164-176) invokes the load frame,
  which is `call <mainline>`.
- Bytecode unpack (`M=src/core/bytecode.c:960-1026`): header only
  (:140-260); the string heap is allocated but decoded lazily per string
  (:970-978; `MVM_cu_obtain_string`, `compunit.c:217-254`); one
  `MVMStaticFrame` per frame with pointer/counts only (:469-520); a
  frame's lexical names, handlers and static lex values are finished on
  first invoke (`MVM_bytecode_finish_frame` :607-795).
- Deserialize frame (`nqp/src/vm/moar/QAST/QASTCompilerMAST.nqp:809-848`):
  pre-deserialize tasks, `deserialization_code` (:890-965: `createsc`,
  `scsetdesc`, `deserialize` reading the CU's own segment, the code-ref
  list, `repo_conflict_resolver`), post-deserialize tasks. Load frame =
  `$cu.load` (:852-858); mainline = `$cu[0]` (:878).
- `MVM_serialization_deserialize` (`M=src/6model/serialization.c:3082-3196`):
  the reader stays alive on the SC (:3100); header offsets only
  (:1986-2151); `calloc` the root object and STable arrays with NO
  stubbing (:3133-3146); repossessions and their closure are the only
  objects finished up front (:3162-3171); `MVM_SERIALIZATION_LAZY 1` (:9).

## How MoarVM makes the deserialization cheap

- Demand road: `MVM_sc_get_object` (`M=src/6model/sc.c:216-232`) returns
  the root if set and no drain is running (`sc_working` :199-202), else
  `MVM_serialization_demand_object` (`serialization.c:2747-2799`): per-SC
  reentrant mutex (:2752), param-intern short-circuit (:2760-2774),
  `stub_object` (:2270-2289), worklist, `work_loop` (:2723-2745: pending
  STables first, then objects). Every reference read inside an object's
  deserialize goes back through `MVM_sc_get_object` (:1797-1802), so the
  transitive closure is finished before control returns and no stub
  leaks.
- STables: `MVM_sc_get_stable` (`sc.c:289-303`) → `demand_stable`
  (:2801-2856) → `stub_stable` (:2186-2242). Code refs: `MVM_sc_get_code`
  (`sc.c:350-367`) → `demand_code` (:2858-2893) → `deserialize_closure`
  (:2374-2416; the context on demand :2408-2412). HOW is lazier still:
  `deserialize_how_lazy` stores only `(HOW_sc, HOW_idx)` (:2418-2422).
- Unconditionally read for CORE.c: bytecode header, 26,014 frame headers
  and code objects, callsites, SC header + 14 dependencies, 152
  repossessions, the `calloc` of 234,322 object and 5,247 STable slots.
  Not read: the string heap, object/STable/closure/context bodies, frame
  bodies.
- Blob layout (`../rakudo-upstream-main/blib/CORE.c.setting.moarvm`,
  33.9 MB): frames 12.57 MB, strings 3.98 MB (40,056), SC data 7.83 MB
  (STable data 1.87 MB, object data 5.08 MB), bytecode 8.60 MB,
  annotations 0.94 MB.
- Ours (`blib/CORE.c.setting.jar`, 56.4 MB, Stored): `unit.serialized`
  28.17 MB, `unit.programs` 21.2 MB, `unit.records` 5.4 MB, `unit.index`
  1.27 MB, `unit.dispatch` 0.28 MB. The reader is fully eager
  (`nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/SerializationReader.kt:93-171`):
  the string heap decoded to Java Strings in full (:282-296), every STable
  and object stubbed (:133-143, with a `stableIndex` map :379-380), then
  every one finished (:149-150), contexts and outers (:153-156).

## Repossession

Both VMs do it up front and the same way: MoarVM's write barrier
(`sc.c:437-507`, compile time only, moves the object into the compiling
SC's root set), reader `repossess` (:2924-3020, conflicts kept for
`resolve_repossession_conflicts`); ours `SerializationReader.repossess`
(:316-360), the resolver wired at `W/compunit.rakumod:754-757`. CORE.c
has 152 entries; not part of the eager/lazy question.

## What we do that MoarVM does not, and what covers it

| our startup cost | MoarVM | covered by |
|---|---|---|
| finish every SC object/STable/closure/context at load (28 MB) | demand-finish from `wval`/`getlexstatic` | lazy-loading Phase 2 (M8 Phase C): its whole content |
| decode the whole string heap to Java Strings | decode per string on first use | NOT in Phase 2 as specced ("stays eager") |
| stub every object and STable up front, plus the `stableIndex` map | `calloc` the root arrays only, stub on demand | NOT in Phase 2 as specced (it keeps the stub pass) |
| build the whole block table with MethodHandles | frame headers only, finished on first invoke | lazy tables, Phase 1 (landed) |
| execute 1207 bodies + prologues + 1148 clones | the same, ~100x cheaper per unit | not a loading lever: TypeState/dispatch (M8), a static-clone road, or persisting the load block's effects |
| run ~4600 dispatcher programs cold | the same, no persistence at all | M7 Phase C persisted slots: our only edge here |
| JIT warm-up, class loading, LambdaForm spinning | none | M9 Native Image |
| read the whole envelope | mmap | done (Stored jar, mapped, Phase 1) |

## What this means for lazy-loading Phase 2 (M8 Phase C)

1. Phase 2 attacks the SC-read row (~10 % of main-thread samples), real but
   bounded; the ~45 % load-block row is execution MoarVM also performs, so
   Phase 2 cannot close the 28x gap by itself.
2. Copy MoarVM's laziness level, not the spec's: no up-front stubbing;
   root arrays null, stub in `demand`; drop the `stableIndex` map by
   storing the index on the object as MoarVM does.
3. Make the string heap lazy (offset table, decode on first use).
4. Keep HOW lazy at the STable level: a type touched by `istype` must not
   pull its metaclass and method tables.
5. Guard reads during a drain with a `working` flag as `sc_working` does,
   so no stub escapes mid-worklist.
6. A per-SC reentrant lock is what MoarVM uses; one global lock is fine.
7. Measure and fix the 28.2 MB vs 7.8 MB blob gap before Phase 2 (likely
   varint packing: MoarVM packs SC id + index in one varint,
   `serialization.c:1779-1795`); the format is not frozen by stage0.
8. The bodies row needs its own lever: a static clone and a
   non-dispatching capturelex fast path shrink it more than any loading
   change.
9. The cold dispatcher runs are structural on MoarVM too; persisted slots
   stay ahead of Phase 2 if the clocks disagree.
10. After a MoarVM-style Phase 2 the remaining gap is the interpreter and
    java.lang.invoke cost, which only M9 removes.
