# Milestone 5 (RakuObject layout) — ledger

Running record for the plan
`docs/superpowers/plans/2026-09-11-jvm-milestone-5-rakuobject-layout.md`.

## Task 1 — baseline numbers, pinning tests, attribute bench

All numbers below were taken on the untouched milestone 4 build in the
worktree `.claude/worktrees/jesp-direct-lazy-records` (rakudo
`worktree-jesp-direct-lazy-records`, nqp `jesp-direct-lazy-records`), Oracle
GraalVM, one run each, before any milestone 5 change.

### plusquick before

`RAKUDO_RAKUAST=1 NQP_DISPATCH_STATS=1 ./rakudo-j docs/bench/jesp/plusquick.raku`

| road | before (ns/op) |
| --- | --- |
| `$a + $b` (plusquick) | 82.625 |

Dispatch stats from the same run: `hits=90247539 misses=11614 slowEvals=364
invokes=13845 directs=13826 noTarget=19 badExpectation=0 notCodeRef=0`,
`byKind[value,syscall,mapped,invoke,resumable]=[0, 95661, 45117402, 13446,
45021030]`.

### attrquick before

`RAKUDO_RAKUAST=1 ./rakudo-j docs/bench/jesp/attrquick.raku`

| road | before (ns/op) |
| --- | --- |
| getattr | 68.75 |
| bindattr | 57.05 |
| getattr_i | 107.3 |
| decont | 78.35 |
| bigint+ | 172.4 |
| create | 573.25 |

No road is above 1000 ns/op, so all six are fair regression targets.
`create` is the slowest by a wide margin and is the one the storage-class
family is meant to move.

### Adjustments made to the brief's code (milestone 4 is the truth)

1. **`docs/bench/jesp/attrquick.raku`** — the brief's `my $p = P.new(...)` /
   `my $n = N.new(...)` made the bench die at line 1 with

   ```
   No such attribute '$!a' for this object (looked in P; has [null: $!value,$!descriptor])
   ```

   because `=` puts the object in a `Scalar` and `nqp::getattr` then looks at
   the container. Both are bound with `:=` instead; the `$scalar` used by the
   `decont` road stays assigned, since that road wants the container.

2. **`nqp/t/jvm/17-object-layout.t`, the multiple-inheritance type** — NQP's
   `class` declaration accepts only one `is`, so `class MAB is MA is MB`
   fails to parse (`Malformed package declaration`). The two-parent type is
   built through the HOW (`NQPClassHOW.new_type` + two `add_parent` calls +
   `compose`), the way `t/nqp/058-attrs.t` builds its types. The assertion is
   unchanged: attributes of both parents and of the child resolve by name.

3. **`nqp/t/jvm/17-object-layout.t`, the type-object error text** — the brief
   expected `does not support attributes`; milestone 4 says
   `Cannot look up attributes in a type object`. Expectation changed to the
   runtime's wording.

4. **`nqp/t/jvm/17-object-layout.t`, the unbound `$` attribute** — the brief
   expected `nqp::isnull(nqp::getattr($av, AV, '$!s'))`. Milestone 4 hands
   back the `NQPMu` type object, not a null. Probed behaviour:

   | probe | milestone 4 |
   | --- | --- |
   | `attrinited($av, AV, '$!s')` before any read | 0 |
   | `attrinited($av, AV, '@!a')` before any read | 1 (auto-vivified at creation) |
   | `getattr($av, AV, '$!s')` | `NQPMu`, `isconcrete` 0, `isnull` 0 |
   | `attrinited($av, AV, '$!s')` after that read | 1 (the read initializes the slot) |

   The one line became two: `attrinited` is 0 until the slot is read or
   bound, and the read hands back `NQPMu`. `plan()` therefore went from the
   brief's 46 to **47**.

Everything else in the brief's three test files ran green on milestone 4 as
written — including the four error texts (`No such attribute '$!nope'`,
`Cannot access a reference attribute as a native attribute` twice,
`Incompatible MROs`), the sized-native truncation (int8/uint8 both 44 from
300), hints (`attrhintfor` is the slot number, parents first, `-1` unknown),
clone of inline plus both overflow arrays, and the delegates.

### Test files and their pinned counts (milestone 4, all green)

| file | plan | result |
| --- | --- | --- |
| `nqp/t/jvm/17-object-layout.t` | 47 | 47/47 |
| `nqp/t/jvm/18-rebless-layout.t` | 14 | 14/14 (no adjustment needed) |
| `t/02-rakudo/mixin-identity.t` | 8 | 8/8 (no adjustment needed) |

`t/02-rakudo/mixin-identity.t` needed no drop: on the JVM `does` keeps both
identity and `WHICH`, and `but` leaves the original's `WHICH` and type alone.

Commands:

```
RAKUDO_RAKUAST=1 NQP_DISPATCH_STATS=1 ./rakudo-j docs/bench/jesp/plusquick.raku
RAKUDO_RAKUAST=1 ./rakudo-j docs/bench/jesp/attrquick.raku
cd nqp && ./nqp-j-gradle t/jvm/17-object-layout.t
cd nqp && ./nqp-j-gradle t/jvm/18-rebless-layout.t
RAKUDO_RAKUAST=1 ./rakudo-j -Ilib t/02-rakudo/mixin-identity.t
```

## Task 4 — the Rakudo runtime consumers, the make, the first Rakudo gate

Two Rakudo runtime files stopped naming the generated storage classes:

- `src/vm/jvm/runtime/org/raku/rakudo/Binder.kt` — the private
  attributive-parameter road asks the STable's `RakuObjectREPRData.layout`
  for the slot (`slotFor(attrPackage, varName)`) and switches on
  `layout.kinds[slot]` (`SlotKind.INT/NUM/STR`, everything else boxed),
  in place of the `nameToHintMap` loop plus the `flattenedSTables[hint]`
  REPR test. Imports `P6OpaqueREPRData`, `P6int`, `P6num`, `P6str` gone,
  `RakuObjectREPRData` and `SlotKind` in.
- `src/vm/jvm/runtime/org/raku/rakudo/RakudoContainerSpec.kt` —
  `atomic_load` reads `layout.getVolatile(o, slot)` with the `$!value`
  slot resolved once by `slotForName` and cached in a `@Volatile Int`,
  in place of the reflected `VarHandle` on the generated class's value
  field. `MethodHandles`/`VarHandle`/`Field` imports gone.
- `t/02-rakudo/10-nqp-ops.t:10` — the `todo` text keeps the message and
  drops the deleted exception class's name.

`grep -rn 'P6Opaque\|field_1' src/vm/jvm t/02-rakudo` is empty (exit 1).
The brief's comment text for `scalarValueSlot` said "formerly a VarHandle
on the generated class's field_1"; that literal would have kept the grep
non-empty, so the comment says "value field" instead — the only wording
departure from the brief's verbatim Kotlin.

### The make (Step 4)

`RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=... --show='Compiling'
--show='rror' --show='Stage' --max=2400 -- make`

`=== EXIT=0 verdict=ok elapsed=528s ===`. All three settings recompiled
(the runtime jar is newer than them): `rakudo.jar` at 2 s, `CORE.c` 5 s →
455 s, `CORE.d` 455 s → 473 s, `CORE.e` 473 s → 528 s.

| CORE.c stage | milestone 5 task 4 |
| --- | --- |
| start | 0.001 |
| parse | 341.307 |
| syntaxcheck | 0.000 |
| ast | 0.001 |
| optimize | 36.275 |
| qast | 32.958 |
| unit | 26.940 |
| jar | 0.000 |
| **sum** | **437.48** (milestone 4 baseline 467) |

### The variant gate (Step 5)

`RAKUDO_RAKUAST=1 NQP_LAYOUT_STATS=1 ./rakudo-j -e 'say 1'`:

```
1
layout stats: layouts=2120 variants=0 reblesses=0
```

`variants=0 <= reblesses=0`; under `NQP_LAYOUT_TRACE=1` the same program
prints 0 `layout: variant` lines and 0 `rebless:` lines, so no variant is
unaccounted for.

### Gate files

| file | count | note |
| --- | --- | --- |
| `t/01-sanity` (2 jobs) | 25 of 25 ok in 198 s | |
| `t/02-rakudo/mixin-identity.t` | 8/8 | unchanged from task 1 |
| `t/08-performance/22-rakuast-ct-dispatch.t` | 30/30 | green |
| `t/08-performance/29-rakuast-attr-self-types.t` | 21/21 | green |
| `t/08-performance/32-rakuast-native-param-bind.t` | 26/26 | green (the Binder road) |
| `t/02-rakudo/native-return-coercion.t` | 19/23 | unchanged; reds 7, 17, 18, 19 |
| `t/02-rakudo/sort-element-kinds.t` | 63/63 | green |
| `t/02-rakudo/nested-invocation-continuation.t` | 6/6 | green |
| `t/spec/S04-phasers/keep-undo.t` | 16/16 | run from the main checkout's path (no `t/spec` in the worktree) |
| `t/02-rakudo/begin-time-attributive-param-method.t` | 6/6 | green |
| `t/02-rakudo/yada-trait-timing.t` | 2/2 | green |
| `t/02-rakudo/21-begin-time-compile-sub.t` | RED (compile) | unchanged known red: `Failed to deserialize lexical $?PACKAGE` at line 6 |

The four `native-return-coercion.t` reds: #7 "boxed Int operand keeps the
result boxed", #17 "boxed Int to native num still requires explicit
coercion", #18 "boxed Int return to native num still requires coercion",
#19 "subset return to native num still requires coercion".

### Benches, before and after

`RAKUDO_RAKUAST=1 NQP_DISPATCH_STATS=1 ./rakudo-j docs/bench/jesp/plusquick.raku`
and `RAKUDO_RAKUAST=1 ./rakudo-j docs/bench/jesp/attrquick.raku`, one run
each on the task 4 build.

| road | before (ns/op) | after (ns/op) | delta |
| --- | --- | --- | --- |
| `$a + $b` (plusquick) | 82.625 | 85.525 | +3.5 % |
| getattr | 68.75 | 71.65 | +4.2 % |
| bindattr | 57.05 | 57.65 | +1.1 % |
| getattr_i | 107.3 | 85.95 | −19.9 % |
| decont | 78.35 | 77.25 | −1.4 % |
| bigint+ | 172.4 | 133 | −22.9 % |
| create | 573.25 | 463.25 | −19.2 % |

No road regressed above the brief's 10 % bar, so nothing is investigated
before task 5. `create`, `getattr_i` and `bigint+` — the three the storage
family was meant to move — are all about 20 % faster.

Dispatch stats from the plusquick run:
`hits=90247539 misses=11614 slowEvals=976 invokes=13845 directs=13826
noTarget=19 badExpectation=0 notCodeRef=0`,
`byKind[value,syscall,mapped,invoke,resumable]=[0, 95661, 45117402, 13446,
45021030]` — identical to the "before" run except `slowEvals` 364 → 976.

## Rulings made during execution

Every ruling the SDD ledger
(`.superpowers/sdd/2026-09-11-jvm-milestone-5-rakuobject-layout/progress.md`)
recorded, in order, with the cost-if-wrong each was taken against.

**Pre-flight scan.** `deserialize_stub(tc, st)` has exactly one caller
(`SerializationReader.kt:386`, the line task 2 switches to the three-arg
form); no other REPR is affected by the signature change.

**Task 2 — the runtime.** Five findings from the review were ruled on
rather than simply applied:

1. *`is_attribute_initialized` auto-vivifies* (the plan's code said so):
   the plan was wrong. The old generated method answered 0 on a null slot
   without vivifying. **FIX** — drop the auto-viv term. Tests 17 and
   `t/nqp/058-attrs.t` pin the old answer.
2. *num32 rounding dropped on a native bind*: **FIX** — a
   `P6num.sizedValue(spec, v)` mirror of `P6int.sizedValue`
   (`bits == 32` → `v.toFloat().toDouble()`) applied in
   `bind_attribute_native`'s NUM arm only, as the old `inlineBind` did;
   `set_num` stays raw, as the old generated `set_num` was.
3. *A UINT box target routes to `unboxIntSlot`, not `unboxObjSlot`*:
   **KEEP**, intentional. The old fall-through was a commented-out line,
   `StorageSpec.integer(unsigned)` marks UINT as an integer, and no type
   in stage0 or CORE.c has a UINT box target. Cost if wrong: an
   out-of-tree type with a uint box target reads its serialized unbox
   slots differently.
4. *`set_int`/`set_uint` mask through `sizedValue`*: **KEEP** — MoarVM
   stores into the sized slot and truncates, and no sized box target
   exists in CORE.c.
5. *The `getBI`/`makeBI` nested-boxed fallback was removed*: **KEEP** —
   the old fallback indexed `flattenedSTables[hint]!!`, which is null for
   a REF slot (an NPE), so it was unreachable; the reviewer could not
   construct a case either. Gates: `t/nqp/060-bigint.t`, `t/01-sanity`.

Minors 6 (a hint range check on the hinted `Ops.getattr`) and 7 (an
atomics kind guard) went to the fix round as cheap; minor 8 (`!!` on the
slow-road helpers) was parked as provably non-null; 9 (a box-failure
message naming the type rather than the REPR) was accepted; 10 (peek-seek
documentation) was deferred.

**Task 3 — the sites.**

- A pre-milestone-5 runtime may be built **once**, in a throwaway nqp
  worktree at `a60cad516~1` under the job directory, to classify the ten
  red suite files as pre-existing or regression. This is correctness
  triage, not a perf A/B (which the "no A/B compiles" rule forbids); the
  worktree is deleted afterwards. Outcome: all nine remaining reds are
  pre-existing, and `t/serialization/04-repossession.t` was *worse*
  before (it died at line 18 on a delegate cast; it now runs to 20/22).
- The stats gate is **`variants <= reblesses`**, not `variants == 0`: a
  real compiler mixin (`QAST::Var+{QAST::SpecialArg}`) legitimately makes
  one variant. Task 4 reads the CORE.c gate the same way. `NQP_LAYOUT_TRACE`
  names each variant, so a mis-classed stub cannot hide behind a rebless
  count.
- `t/serialization/04-repossession.t` narrows its JVM skip to the tests
  that fail for the *reader* reason (`stubObjects` reuses a live object
  already in the SC), with that reason written into the skip text, per
  spec §3.

**Task 5 — interop.** Fix round 1 is trailers plus minors 1 and 3
(test cases that actually hit the plan cache; `ConcurrentHashMap` for the
multi exact map). Minor 2 (boolean widening: `LongArg` tests all 64 bits
where the old road tested the low 32) is accepted as the saner semantics.
Minors 4 and 6 (an `unreflect` failure on a non-public declaring class
failing the whole class rather than the first call; a `dispatchName()`
accessor) go to the final review. The dead `storageForType` and
`JavaCallinException.kt` go in task 6 with the other deletions.

**Task 6 — ASM.** `BytecodeVersion.kt` was already deleted in task 5, so
step 2's `git rm` of it is skipped (ruling a); `storageForType` and
`JavaCallinException.kt` are deleted here (ruling b).

**Task 7 — this task.** The rakudo-side build scripts drop the asm jar
names, and the dead `nqp/src/vm/jvm/runners/nqp-j{,.bat}` are deleted.
The generated rakudo `Makefile` is not committed and is not edited: a
fresh `Configure.pl` regenerates `NQP_JARS` from the nqp build directory,
which task 6 already cleaned (`tools/lib/NQP/Config/NQP.pm`'s
`configure_jars`).

Ruling (controller, 2026-09-12): the unsigned-native-attribute
regression found by the sweep is load-bearing; one fix dispatch before
the final review; gate = native-argument-snapshot.t 9/9, nqp/t/jvm/17,
t/01-sanity, the sensitive slice; fix lands as new commits on top,
pushed force-with-lease.

The fix (2026-09-12, nqp `7e7aaca61`, rakudo: this commit): the root
cause is not in `RakuObject` at all — `TruffleEncoder`'s `encode_args`
wrote each argument's wire RESULT type straight into the callsite
argument flag, and `$T_UINT` is 4, which is that flag's NAMED bit, so
any call taking an unsigned native attribute decoded as "a named object
argument" and the reader then read the following program word as a
constant-pool index (the `ArrayIndexOutOfBoundsException`) or, once the
stream had slipped by a word, hit `nqpp: unknown tag` further down; a
uint ARGUMENT now travels in the int slot, as `classlib_t` already says
and as a uint lexical already did. Gates: `native-argument-snapshot.t`
**9/9**, new `t/02-rakudo/native-uint-attribute.t` **7/7**,
`nqp/t/jvm/17-object-layout.t` **50/50** (three added uint32 cases),
`18-rebless-layout.t` **14/14**, `mixin-identity.t` **8/8**,
`t/01-sanity` **25/25**, `22-rakuast-ct-dispatch.t` **30/30**,
`29-rakuast-attr-self-types.t` **21/21**,
`32-rakuast-native-param-bind.t` **26/26**,
`native-return-coercion.t` **19/23** (reds 7 and 17-19, unchanged),
`sort-element-kinds.t` **63/63**,
`nested-invocation-continuation.t` **6/6**, `keep-undo.t` **16/16**.
The encoder is byte-identical between nqp `739ce7517` (the milestone-4
head) and this milestone's head, so the failure predates milestone 5:
milestone 4's task 11 saw the file red and cleared it as a
`$*EXECUTABLE`-spawn cold-only artifact, which was a mis-attribution.
Neither of task 2's two kept UINT rulings is implicated.

## Deferred minors (carried past the milestone)

None of these blocked a task; each is recorded so it is not rediscovered.

- **Task 1.** `t/02-rakudo/mixin-identity.t` binds `$w2` without
  asserting on it; `docs/bench/jesp/attrquick.raku` binds `$s` without
  reading it; `nqp/t/jvm/17-object-layout.t` has no labelled "0 longs"
  case (it is implicit in the ref-only classes).
- **Task 2.** Minor 8 (the `!!` assertions on the slow-road helpers,
  provably non-null) and minor 10 (documenting the raw table seek in
  `peekAttributeShape`).
- **Task 3.** Stale comments in `NqpDispatch.kt:70-75` and `:297-301`
  ("generated accessor", "storage class"); `DecontSite` never `miss()`es
  on a layout mismatch (a perf nit, not a correctness one);
  `NqpTypeOps.resolveBigInt` indexes `kinds[unboxIntSlot]` unchecked;
  `BigIntSite` does not re-verify `rd.layout === layout`; `AttrSite`'s
  triple publication is unfenced (an inherited shape, not new) — *this
  last one was fixed in the final review's wave, 2026-09-12: one
  immutable `AttrEntry` per resolution.*
- **Task 4.** A dead `RakuObjectREPRData`-era import in `Binder.kt` (left
  deliberately: a settings rebuild is not worth one import, and task 6
  rebuilt anyway); the `variants <= reblesses` gate was measured on
  `say 1` only (`mixin-identity.t` exercises rebless separately);
  `slowEvals` on the plusquick road went 364 → 976 with every other
  dispatch counter identical — unexplained, and the plusquick bench is
  +3.5 %.
- **Task 5.** Added interop test cases fall to the casting road and never
  read the exact cache; `MultiPlan`'s exact map was unsynchronized (fixed
  in the fix round); an `unreflect` failure on a public method of a
  non-public declaring class fails the whole class at plan-build time
  where the old road failed at the first call (probed clean over 12
  classes / ~600 members) — *fixed in the final review's wave,
  2026-09-12: such a member gets an `UnusablePlan` that dies at call
  time*; a `dispatchName()` accessor.
- **Task 6.** The rakudo-side asm jar names and the dead nqp-j runners —
  both closed in task 7, above.

## Close (2026-09-12)

Heads: nqp `739ce7517` → `df564ddbb`, rakudo `b64c52cb1c` → this
commit. (The task-7 close read `a927b5fa1` / the docs commit below; the
uint fix, nqp `7e7aaca61` + rakudo `edfd05c484`, and then the final
review's fix wave landed on top, none of them rewriting anything.)

The closing t/ sweep: 420 files, 6039 s, `EXIT=1 verdict=ok`, 22 files
red — **2 fixed** since milestone 4 (`04-settingkeys-6d.t`,
`36-rakuast-begin-compiled-remark.t`) and **3 new**, each confirmed by a
solo re-run. One of the three read as a milestone-5 regression —
**unsigned native attributes** (`uint`, `uint32`) throwing
`ArrayIndexOutOfBoundsException` when boxed and dying with
`nqpp: unknown tag 51` when written, `int` and `int32` unaffected — and
the suspects named here were task 2's two kept UINT rulings (findings 3
and 4). **That attribution was wrong, and the milestone has no open
regression.** The cause was a pre-existing `TruffleEncoder` bug:
`encode_args` patched the callsite argument flag with the wire RESULT
type, and `$T_UINT` is 4, which is that flag's NAMED bit, so a
positional uint decoded as a named object argument and the reader ate
the following word as a pool index. The encoder is byte-identical
between the milestone-4 head (nqp `739ce7517`) and this milestone's, so
the bug is older than the layout work; milestone 4's task 11 had seen
the file red and cleared it as a cold-run artifact. Fixed in nqp
`7e7aaca61` (uint arguments travel in the int slot; only a uint RESULT
stays `$T_UINT`), with `t/02-rakudo/native-argument-snapshot.t` back at
**9/9** and a new `native-uint-attribute.t` at **7/7**. Neither of task
2's UINT rulings is implicated.

**Final review (2026-09-12) and its fix wave.** The whole-branch review
came back "with fixes": five Important findings and one
fix-before-merge, all landed as new commits on top of the heads above
(nothing rewritten). (1) `RakuObjectREPRData.layoutFor` built its
variant map lazily in a plain `HashMap` on the rebless road, so two
threads reblessing into one type could each build a variant layout for
the same storage class and lose one of the maps — it is an eagerly
initialised `ConcurrentHashMap` with `computeIfAbsent` now. (2) An
`AttrSite` published its key (`resolved`, `ch`, `name`) and its handles
as separate fields, so a reader could see a new key beside the old
handles; each resolution is now one immutable `AttrEntry`
(layout + handles + key) stored into one `@CompilationFinal` reference,
which also makes the BUILDALL guard implicit and retires `sameKey` /
`sameKeyOrUnset`. (3) `createPlans` failed a whole class's interop when
`unreflect` refused one member; such a member now gets an
`UnusablePlan` that dies at call time naming it. (4) `encode_args`
refuses an argument flag outside 0..3, so the next flag/type confusion
cannot slip a stream silently. (5) These records were corrected (this
paragraph, the spec's `## Done`, and `docs/jvm-truffle-only-plan.md`
row 9). Fix-before-merge: `t/02-rakudo/mixin-identity.t` now carries the
`does` keeps `WHICH` assertion the review asked for — and it is red,
**as it is on MoarVM too**: `.WHICH` is `.^name ~ '|' ~ nqp::objectid`,
`does` changes the type in place, and stock `raku` answers
`Foo+{Modified}|<id>` against `Foo|<id>` for exactly this program
(checked 2026-09-12). The object-id half *is* preserved, which is what
the `===` test beside it pins. Rather than weaken the assertion to the
id half, it stands as a `todo` naming that reason, so the file is 9/9
with one todo and the expectation stays visible. Everything else the
review raised is parked for the perf session or the next milestone.

The gate numbers, the bench table and the full sweep diff are
written up in the spec's "Done (2026-09-12)" section
(`docs/superpowers/specs/2026-09-11-jvm-unit-artifact-milestone-5-design.md`);
the plan's position rows are `docs/jvm-truffle-only-plan.md` item 9 and
the Position table. Next: the perf measurement session (plan item 4),
then the engine merge (one Truffle language).
