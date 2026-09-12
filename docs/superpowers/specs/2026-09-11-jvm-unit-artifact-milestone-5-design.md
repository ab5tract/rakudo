# JVM milestone 5: the RakuObject layout, and ASM gone

Design for the P6Opaque half of item 9 of `docs/jvm-truffle-only-plan.md`,
plus the last of item 8's promise: after this milestone nothing in the
nqp or Rakudo JVM runtime generates a class at run time, and ASM is not a
dependency. Approved in conversation on 2026-09-11, section by section,
with two clarifications folded in (mixin identity: `does`/rebless are in
place, `but` clones first; a type's layout is created by its single REPR
composition and never mutated).

## Where the tree stands (2026-09-11, rakudo `7ddf803199`, nqp `739ce7517`)

Milestone 4 deleted the class road: every jar is a `unit.meta`-only
artifact, `ByteClassLoader` defines only plain classes, and ASM is still
in the build for two generators.

**P6Opaque** (`nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/reprs/`,
1325 lines over `P6Opaque.kt`, `P6OpaqueBaseInstance.kt`,
`P6OpaqueDelegateInstance.kt`, `P6OpaqueREPRData.kt`) composes a type
into a JVM class generated with ASM (`generateJVMClass`, `P6Opaque.kt:278-639`):
`__P6opaque__N extends P6OpaqueBaseInstance`, one `public SixModelObject
field_i` per reference attribute, and per flattened native attribute a
field whose type and accessor bytecode the attribute's REPR emits through
six hooks on `REPR.kt:118-149` (`inlineStorage`, `inlineBind`,
`inlineGet`, `inlineDeserialize`, `generateBoxingMethods`,
`serialize_inlined`; implemented by `P6int`, `P6num`, `P6str`,
`P6bigint`, `NativeCall`, `CPointer`). Five tableswitch accessors and a
`deserializeFields` are generated per class, each starting with a
delegation branch. Storage classes are shared across unrelated types by
a structural-signature cache (`P6Opaque.kt:221-262`).

What the generated class actually buys is one thing: a plain JVM field
per attribute, so a Truffle site that resolved `(class, name)` to
`field_7` once hands partial evaluation a constant method handle and the
compiled read is a guard plus one load. The generated accessors are
avoided by every fast site on purpose (their delegation branch is
PE-recursive, `NqpDispatch.kt:136-142`). The five fast roads, all keyed
on the exact generated class plus an unreflected `field_N` handle:
`NqpOps.AttrSite` (`NqpOps.java:1434-1559`), `NqpDispatch.AttrSrc` /
`UnboxSrc` folded from `fieldHandles` (`NqpDispatch.kt:552-577`),
`NqpTypeOps.DecontSite`, `BigIntSite` (`NqpTypeOps.kt:786-829`, requires
`field_$slot` to be a `BigInteger`), `CreateSite` (clones the REPR data's
prototype). The bytecode-side ops (`Ops.kt:3478-3820`, `getBI`/`makeBI`
`:8619-8663`) and `DispatchModel.attributeKind` (`:186-200`) classify a
slot as native or reference by **catching**
`P6OpaqueBaseInstance.BadReferenceRuntimeException`. Atomics unreflect a
`VarHandle` per call (`P6OpaqueBaseInstance.kt:127-137`);
`RakudoContainerSpec.kt:111-129` hardcodes `field_1` as `Scalar`'s value
slot. `change_type` (`P6Opaque.kt:655-710`) copies attribute values by
reflecting over `javaClass.fields` with a `size - 3` fudge and installs a
**delegate**; `deserialize_stub` (`:895-899`) makes every deserialized
object a `P6OpaqueDelegateInstance` wrapper, which is why every fast site
carries a delegate-unwrap prologue and a `delegate == null` guard.
Hints are discarded under multiple inheritance (`Ops.kt:3568` and four
more). `nqp/t/serialization/04-repossession.t` skips itself on the JVM
(`:6-9`), so repossession has no coverage here.

**Interop** (`BootJavaInterop.kt`, `RakudoJavaInterop.kt`) generates,
per Java class, a class of static `qb_N` callouts
(`(CompilationUnit, ThreadContext, CodeRef, CallSiteDescriptor,
Object[])void`, `startCallout` `BootJavaInterop.kt:766-801`): open a
`CallFrame`, `Ops.checkarity`, one `Ops.posparam_{o,i,n,s}` per Java
parameter, per-type conversion (`marshalOut` `:496-585`), the member
call, result conversion (`marshalIn` `:458-494`), `Ops.return_*` into the
frame, one catch-all translating non-control exceptions to
`dieInternal` (`endCallout` `:804-830`, which skips `cf.leave()` on that
path). `AdaptorUnit.kt` binds the statics into CodeRefs under the
`USE_BINDER` convention, i.e. `cr.staticInfo.mh.invokeExact(tc, cr, csd,
args)` (`ArgsExpectation.java:17-22`); newdisp finds the CodeRef through
the STable's authoritative method cache and is otherwise uninvolved.
Rakudo adds a var-arity callout per overloaded name whose
`invokedynamic` site (`DispatchCallSite`, `RakudoJavaInterop.kt:46-404`)
selects a candidate on every call by descriptor-string comparison and
never re-links. `implementClass` (Java implementing interfaces backed by
NQP) has no callers. `constants` is a static field set reflectively after
`defineClass` (`finishClass` `:190-214`).

**Build:** ASM is declared once, `nqp/buildSrc/src/main/kotlin/NqpDeps.kt:14-15`
(`asm`, `asm-tree`; the latter already dead, `:39-45`), vendored under
`nqp/3rdparty/asm`, wired through `nqp/tools/templates/jvm/Makefile.in:13-14`
and `nqp-j.in:35`. `BytecodeVersion.kt` holds `Opcodes.V25` for the two
generators. `com.oracle.truffle.api.object` (Shape, DynamicObject) is on
the module path and unused; nothing exports `InteropLibrary` for values
(only the engines' `Program` and `Matcher` handoff objects).

**Census of CORE.c** (645 classes, run on the milestone 4 build):

| reference attributes per class | classes |
|---|---|
| 0-1 | 458 |
| 2-8 | 25 |
| 9-12 | 4 (Promise, OperatorProperties, CompUnit, Parameter) |
| 14 | 157 (every Routine/Sub/Method type, Cursor, Macro) |
| 16 | 1 (Proc) |

Native (long) slots: 7 classes have any, none more than 2. The
14-attribute cluster is the routine family, the most allocated object
kind (every closure is a clone of one).

## Decisions taken

| decision | choice |
|---|---|
| goal | ASM gone from the build; no runtime class generation anywhere, interop included (user, 2026-09-11) |
| layout | approach C: a static family of instance classes with inline slots and overflow arrays, guarded by a per-STable layout object; not typed arrays only (A), not `DynamicObject`/`Shape` (B: needs `SixModelObject` to extend `DynamicObject`, and its property library needs adopted nodes our Kotlin sites are not) |
| polyglot | orthogonal: interop with other Truffle languages needs `InteropLibrary` exports and one shared context, neither of which the layout choice enables or blocks; the layout API is name-addressable so a later export can read it; the instance class implements `TruffleObject` as a no-op marker only if it costs nothing (plan settles) |
| names | Kotlin classes renamed `RakuObject*`; the REPR's registered name string stays `P6opaque` (metamodel, BOOTSTRAP, serialization and `t/nqp/093-oo-ops.t` refer to it) |
| interop | kept: the adaptor becomes one hand-written callout over per-member plans, time-boxed; if it stalls it is parked and interop dropped with a clear message (user rule 2026-09-10) |
| wire | the serialization format does not change; stage0 and every precompiled jar stay valid |
| immutability | one layout per STable, created by its single REPR composition or by deserialization of its REPR data, never mutated; a second composition dies with MoarVM's message |
| gate | fast gates per task; one t/ sweep at the close diffed against milestone 4's red list; no t/spec (user, 2026-09-11) |
| language | Kotlin for everything new; `NqpRaw.java` keeps the exact-typed `invokeExact` helpers as today |
| builds | forward only, one compile per change, amend on breakage; single benchmark runs |

## 1. The instance model and the layout

### Storage classes, a static family

One abstract Kotlin base `RakuObject : SixModelObject` carrying
`layout: RakuObjectLayout?` (read raw from PE-visible code, never
`lateinit`), `oExt: Array<Any?>?` and `lExt: LongArray?`, and six
concrete final subclasses on a grid of inline capacity: reference fields
4, 8 or 16 crossed with long fields 0 or 2:

| class | inline refs | inline longs |
|---|---|---|
| `RakuObject4` | `o0..o3` | none |
| `RakuObject8` | `o0..o7` | none |
| `RakuObject16` | `o0..o15` | none |
| `RakuObject4L` | `o0..o3` | `l0`, `l1` |
| `RakuObject8L` | `o0..o7` | `l0`, `l1` |
| `RakuObject16L` | `o0..o15` | `l0`, `l1` |

They are field declarations and nothing else, written once by hand.
Compose picks the smallest class that fits; anything beyond the inline
capacity is placed in the overflow arrays. From the census: Scalar,
Pair, Int, Str land in `RakuObject4`; Num in `RakuObject4L`; the routine
family and Cursor in `RakuObject16` with no overflow; only Proc-sized
and mixin-grown objects touch the arrays.

### Slot kinds

Every attribute is one of `REF`, `INT`, `NUM`, `STR`, `BIGINT`,
`NCBODY`. `INT` and `NUM` occupy long slots (a num as raw double bits);
`STR`, `BIGINT` and `NCBODY` are references and share the reference
slots with plain objects. This is what the six flattening REPRs express
today through their ASM hooks; each keeps one hook instead, "the kind of
my inlined slot", plus the two description hooks it already has and the
inlined serialize/deserialize pair retargeted at `(object, slot)`. A
`CPointer` box target is an `INT` slot.

### The layout, our Shape

`RakuObjectLayout` is immutable and holds: the concrete storage class;
per abstract slot its kind and physical placement (inline index or
overflow index), its auto-viv type, and, per placement, a constant
getter and setter `MethodHandle` and a `VarHandle` taken from static
tables built once per concrete class at class init (the mechanism
`NqpDispatch.fieldHandles` uses today, minus the unreflection of a fresh
class); the class-handle list and the name-to-slot maps; the unbox
slots; the positional/associative delegate slots; the MI flag. An
instance points at its layout directly.

**The abstract slot number is the hint**, per STable, exactly as
`hint_for` answers today; the layout owns the placement. Placement is a
deterministic function of (abstract slot, concrete class): slots below
the inline capacity are inline, the rest overflow, for every layout of
that class. An STable's REPR data holds its **canonical** layout (the
class compose chose); an object reblessed into the STable whose class is
too small gets a **variant** layout for `(STable, this class)`, cached on
the target's REPR data. A fast site's guard is `o.layout === L`, one
load and one compare, which implies the concrete class and replaces
today's class compare, key compare and delegate-null test.

### Deleted

`P6OpaqueDelegateInstance`; the tableswitch accessors, `resolveAttribute`'s
linear scan and `attributeVarHandle` on `P6OpaqueBaseInstance`; the
structural-signature class cache; `REPRData.instance` (the prototype)
and `instClone`; the six ASM hooks on `REPR`; `ByteClassLoader`'s
defineClass road (fully, with section 4); the exception-based
native/reference signalling.

### Renames

| today | milestone 5 |
|---|---|
| `P6Opaque.kt` (the REPR) | `RakuObjectREPR.kt`, registered as `P6opaque` |
| `P6OpaqueREPRData` | `RakuObjectREPRData` |
| `P6OpaqueBaseInstance` + generated `__P6opaque__N` | `RakuObject` + the six concrete classes |
| `P6OpaqueDelegateInstance` | deleted |
| (new) | `RakuObjectLayout` |

## 2. The fast sites and the ops

**The five Truffle sites** keep their structure (they are
`@ConstantOperand` objects created fresh per emitted instruction at load,
`NqpProgramBuilder.java:705-729`; the Bytecode DSL declarations in
`NqpRootNode.java` are untouched) and change what they resolve to.
Resolution takes `(layout, classHandle, name)` and produces `(layout,
kind, placement, getter/setter handle)` from the layout's tables. The
compiled shape is the guard `o.layout === L` followed by `invokeExact`
on a constant handle: today's fold minus the delegate prologue. A site
that sees a second layout (a mixin variant; a parent method run on
several subclasses) becomes a small polymorphic cache with the dispatch
sites' existing depth policy, where today it falls to the slow road. The
kind is checked at resolution: a native slot behind a boxed op pins the
site rather than throwing. `CreateSite` allocates the layout's concrete
class directly (a `new` of a constant class, scalar-replaceable) instead
of cloning a prototype; `BigIntSite`'s box allocation does the same.

**The bytecode-side ops** in `Ops.kt` (the `getattr`/`bindattr`
families with and without hint, `attrinited`, `getattrref_*`,
`getBI`/`makeBI`) resolve through the object's layout: hint present and
no MI, use the slot; otherwise name lookup in the layout's maps. The
`NATIVE_JVM_OBJ` branch that reflects over a fresh box's declared fields
(`Ops.kt:3515-3524`) becomes a bind into the box type's unbox slot by
kind. Atomics (`cas_attribute_boxed`, `atomic_bind_attribute_boxed`, the
container spec's `atomic_load`) use the layout's cached `VarHandle`.

**Rakudo runtime:** `Binder.kt:185-196` reads the layout's kind (and
stops at the first hit rather than keeping the last map's answer);
`RakudoContainerSpec` resolves `Scalar`'s value slot once at spec setup;
`NativeCallOps.kt:624-630` reads the `NCBODY` slot on the object itself,
there being no delegate; `DispatchModel.attributeKind` asks the layout;
`RecordReader`'s `hint_for` cache is unchanged.

**Per-run reset** (`NqpOps.resetSites`, `NqpTypeOps.SITES`) stays: the
reason changes from "a site pins a run's byte class loader" to "a layout
is per STable and STables are per run on the eval server". The comment
is rewritten to say so.

## 3. Mixins, serialization and repossession

### Rebless in place

`change_type` keeps its two checks (target is the same REPR; the
target's class-handle list extends the object's) and then, on the same
JVM object: installs the target's layout for this object's concrete
class (canonical if the classes match, else the variant), grows `oExt`
and `lExt` if the new slots need them, sets the STable. No attribute
value moves, because placement depends only on (slot, class) and
compose walks the MRO parents-first, so a mixin type's slots are the base
type's slots plus appended ones.

This is the operation behind `does` on an instance and `nqp::rebless`:
identity and `.WHICH` (from `nqp::objectid`, per object) are preserved
exactly as on MoarVM. `but` is defined as clone-then-mixin and yields a
new identity by Raku's own definition; its clone is of the original's
concrete class and then takes the same road, so it may carry a variant
layout, which is the case the polymorphic site cache exists for.
Verified on MoarVM 2026.07: `$obj === ($obj but R)` is False,
`$obj === ($obj does R)` is True.

### The serialization wire format does not change

The REPR-data record (attribute count, flattened STables, MI flag,
auto-viv types, unbox and delegate slots, class-handle and name-to-slot
pairs) and the per-object slot stream stay byte-for-byte what they are.
The reader builds a layout from the record instead of a class; the
writer iterates the layout's slots by kind. Consequence: stage0, the
setting jars and every `.precomp` stay valid; milestone 5 regenerates
nothing.

### Stubs are final objects

`deserialize_stub` allocates the STable's canonical class with empty
slots, which needs the STable's REPR data at stub time; the reader
already forces STables on demand for flattened slots
(`reader.forceSTable`, `P6Opaque.kt:813-818`) and the stub road uses the
same call. `deserialize_finish` fills the slots in place. If forcing
fails for a type (a dependency cycle the plan probes for), the stub
falls back to the smallest class and gets a variant layout at finish:
correctness never depends on the guess, only speed. A gate check counts
variant layouts after loading CORE.c and requires zero.

### Repossession, clone

Repossession is an in-place refill of an existing object by another SC,
which is what the stub road now does anyway; no special case.
`nqp/t/serialization/04-repossession.t`'s JVM skip is removed and the
file is expected to pass; if it fails for a reason outside the layout,
the ledger records why and the skip narrows to that reason. `clone` is
`Object.clone` plus a copy of the two overflow arrays.

### One layout per STable, never mutated

6model composes a type's REPR exactly once (`ClassHOW.compose` runs
`compose_repr` under `run_if_not_composed`; NQP's ClassHOW guards with
`$!composed`). Everything Raku allows before that point (`BEGIN`,
`CHECK`, traits, `add_attribute`, role application, `EVAL`-built types)
accumulates in the HOW and the layout is built once from the final list,
at whatever phase compose runs. After it, adding attributes "to an
object or a class" means a new type (mixin, anonymous subclass,
reparameterisation): a new STable, a new layout, rebless for existing
objects. Verified on MoarVM 2026.07: `add_attribute` after compose is
accepted by the HOW, a second `.^compose` does not recompose the REPR,
and reading the late attribute dies with `P6opaque: no such attribute`.
A second REPR composition of one STable dies here with MoarVM's message,
"Type %s is already composed", rather than silently rebuilding.

## 4. The interop rewrite

**One hand-written callout, many plans.** A Kotlin `JavaCallout` with a
single entry `invoke(plan, tc, cr, csd, args)`. `AdaptorUnit` keeps its
role as the CompilationUnit owning the CodeRefs; its handles come from
`MethodHandles.insertArguments(INVOKE, 0, plan)`, which has exactly the
type the `USE_BINDER` road already invokes, so `ArgsExpectation`,
`StaticCodeInfo` and `Ops.invokeDirect` see nothing new. "Binder" here
is NQP's positional reads (`checkarity`, `posparam_*` in `Ops.kt`), not
Raku's signature binder (`Binder.kt`, reached only through `p6bindsig`)
and not newdisp, which only resolves the method name to the CodeRef
through the STable's authoritative method cache.

A `CalloutPlan` is data: the member kind (method, static, field get,
field set, constructor, one of the three specials `/box/`, `/unbox/`,
`/isinst/`), the unreflected target handle spread to `(Object[])Object`,
the arity, one `ArgMarshal` per parameter covering exactly today's
`marshalOut` cases (the int-family and char narrowings, float, string,
passthrough, `tc`/`gc` substitution for a null argument, array, Rakudo's
list and map recursion, unbox-or-passthrough-then-cast for everything
else), and one `RetMarshal` covering today's `marshalIn` cases (void, the
int family, num, str, passthrough, char, box with a per-site lazy
`STableCache`). `commonSTable` becomes a field of the plan entry. There
is no `constants` array. `invoke` reproduces today's frame bracketing
and exception split (control exceptions pass through; everything else
becomes `dieInternal` with the Java exception as cause) and calls
`cf.leave()` on both paths.

**Multi-dispatch** becomes a `MultiPlan` holding the candidate plans and
today's selection algorithm (descriptor match, then the casting pass)
lifted out of `DispatchCallSite` into plain Kotlin, with the chosen
candidate cached per tuple of argument classes. The constructor
dispatcher is the same plan with constructors as candidates. Rakudo's
`marshalOutRecursive` and `filterReturnValueMethod` are already ordinary
Kotlin and are called as they are (the latter no longer looked up by
descriptor string per call).

**Deleted:** `ClassContext`, `finishClass`, `implementClass` and the
whole callin side, `startCallout`/`endCallout` and every `emit*`, the
`invokedynamic` bootstraps and `DispatchCallSite`, `ByteClassLoader` and
`GlobalContext.byteClassLoader`, `NQP_DEBUG_DUMP_CLASSFILES`, every
`org.objectweb.asm` import.

**Time-box and fallback.** One plan task, gated by
`t/03-jvm/01-interop.t` at its milestone 4 count (30/30). If it stalls,
interop is dropped rather than holding the milestone:
`CompUnit::Repository::JavaRuntime` dies with "Java interop is not
available on this build", the interop sources and test are deleted, and
the ledger records the point reached.

## 5. ASM removal and build wiring

Once sections 1 and 4 land, no source imports `org.objectweb.asm`. Then:

- `NqpDeps.kt` drops `asm` and `asm-tree`; `nqp-runtime/build.gradle.kts`
  follows through `NqpDeps.thirdParty`.
- `nqp/3rdparty/asm/` is deleted; `nqp/tools/templates/jvm/Makefile.in`
  loses `ASM`/`ASMTREE`, `nqp-j.in` its `@asmfile@` entry; the rakudo
  runner templates and `tools/lib/NQP/Config/Rakudo.pm` are grepped for
  the same names.
- `BytecodeVersion.kt` goes.
- Gate: zero `org.objectweb.asm` references in sources, zero `asm*.jar`
  under `nqp/build/jvm/`, a clean build without the dependency;
  `ByteClassLoader` deleted, so a stray `defineClass` caller fails at
  compile time.
- The Truffle side is untouched: `truffle-api`, the DSL processor and
  `truffle-runtime` stay as declared; the layout classes live in
  `nqp-runtime` (which sees `truffle-api` only as `compileOnly`) and use
  no Truffle API.

Because section 3 keeps the wire format, stage0 is not regenerated. The
milestone is a runtime rebuild plus one Rakudo `make` (for `Binder.kt`,
the container spec and `RakOps`), with eval servers restarted after each
runtime jar rebuild.

## 6. Error handling and guard rails

- **Attribute errors are answers, not exceptions.** The layout answers
  `kindOf(slot)` and `slotFor(classHandle, name)` (a no-slot sentinel);
  every op checks before it reads. The four user-visible errors keep
  their exact text: "no such attribute" with the known-attribute dump,
  native-vs-reference mismatch, `change_type` to an incompatible type,
  attribute access on a type object.
- **The layout is validated at construction:** slot count fits class
  plus overflow, unbox slots have the matching kind, a variant has the
  same abstract slots as its canonical twin. A failure dies internally
  with the type name and both slot lists.
- **Fast sites fail closed.** No layout (another REPR), a native slot
  behind a boxed op, a kind mismatch, or polymorphism beyond the fixed
  depth pins the site to the slow road, as `pin()` after `MAX_MISSES`
  does today. The slow road is always the `Ops.kt` op, the semantic
  reference; the fast road may only ever be faster.
- **Deserialization guard.** The stub road records whether forcing
  succeeded; variant layouts created at finish are counted;
  `NQP_LAYOUT_STATS=1` prints layouts, variants and pinned sites at exit.
- **Interop:** exception translation as today with `cf.leave()` on both
  paths; a member with an unsupported parameter shape refuses at
  plan-build time with the member's descriptor, not at call time.
- **Diagnostics,** all env-gated, never a bare print:
  `NQP_LAYOUT_TRACE=1` (layout creation, each rebless with before/after
  class and slot lists), `NQP_INTEROP_TRACE=1` (multi-dispatch plan
  selection).
- **Ruled out:** any fallback to the old road. There is no generated
  class to fall back to; the milestone is all-or-nothing like the unit
  road was.

## 7. Testing and gates

New tests, written before the code they pin:

| file | pins |
|---|---|
| `nqp/t/jvm/17-object-layout.t` | layouts across the grid boundaries (3, 4, 5, 8, 9, 16, 17 refs; 0, 1, 2, 3 longs), overflow placement, every kind read and written through the ops, `attrhint` stability, MI name resolution, the four error messages verbatim, `clone` with overflow arrays |
| `nqp/t/jvm/18-rebless-layout.t` | rebless from each class size into a larger type: values preserved, `eqaddr`/`objectid` preserved, canonical vs variant observed through `NQP_LAYOUT_STATS`, the incompatible-target error |
| `nqp/t/serialization/04-repossession.t` | JVM skip removed |
| `t/02-rakudo/mixin-identity.t` | the `but` vs `does` table (identity, `.WHICH`, original untouched) |
| `t/03-jvm/01-interop.t` | unchanged gate, plus one multi-dispatch caching case (one overload, two argument-class tuples) |
| `docs/bench/jesp/attrquick.raku` | getattr, bindattr, decont of a Scalar, bigint `+`, `.new` of a 2-attribute class; ns/op each; one run before, one after |

Per-task fast gates: t/nqp 118; `nqp/t/jvm` + `nqp/t/serialization`;
`t/01-sanity` 25; interop 30/30; the milestone 4 sensitive slice
(`t/08-performance` 22/29/32, `native-return-coercion.t` at 19/23,
`sort-element-kinds.t`, the BEGIN+where pair, `keep-undo.t`);
`plusquick.raku` and `attrquick.raku` with no regression; the ASM census
of section 5; the CORE.c variant-layout count of zero.

Milestone close: one t/ sweep through the eval server, diffed against
milestone 4's red list (the corekeys/settingkeys cluster, the six
un-root-caused files, `native-return-coercion.t` at 19/23). Timing rows
for the ledger: nqp clean build, `make` from the top, CORE.c, both
benches. No t/spec. Runs over 30 s go through
`tools/build/watched-run.raku`; progress every 90 s.

## Sequence

1. Layout and instance family with the ops (sections 1, 2 bytecode
   side), tests 17/18 first. 2. Fast sites (section 2 Truffle side).
3. Rebless, serialization, stubs, repossession (section 3). 4. Rakudo
runtime consumers (Binder, container spec, NativeCall) and the Rakudo
`make`. 5. Interop (section 4), time-boxed. 6. ASM removal (section 5).
7. Milestone gate, docs (plan position rows for items 8 and 9; this
spec's parent; `nqp/docs/gradle-jvm-build.md`; `docs/jvm-jesp.md`'s
object-model section; `CLAUDE.md` if a rule changes), ledger, memory,
then the handoff rebase onto both upstream mains and the
force-with-lease push to `ab5tract`.

## Out of scope

The perf measurement session and tier policy (item 4); items 1 to 3;
polyglot interop (`InteropLibrary` exports, one shared context); Native
Image; `DynamicObject`/`Shape`; an `Assumption` per STable; changing the
hint semantics under multiple inheritance; t/spec.

## Open at plan time (the plan settles these, not the spec)

- Whether the `TruffleObject` marker on `RakuObject` costs anything
  (module visibility from `nqp-runtime`'s `compileOnly` truffle-api).
- The exact polymorphic depth for attribute sites (reuse the dispatch
  sites' constant, or its own).
- Whether stub-time forcing of REPR data is cycle-free for CORE.c (probe
  before task 3; the variant fallback covers the answer either way).
- Whether `RakuObject16L` is ever chosen by CORE.c (drop it if not).
- The interop multi-dispatch cache's key (argument classes vs the
  existing descriptor string).

## Done (2026-09-12)

The milestone is closed. `P6Opaque` is gone: a P6opaque instance is a
`RakuObject` on a static family of six storage classes, carrying a
per-STable `RakuObjectLayout`; the interop adaptor is `JavaCallout` over
per-member plans built from method handles; ASM is not a dependency, the
vendored `3rdparty/asm/` is deleted, and **nothing in either tree
generates a class at run time**.

### Heads and commits

Start: rakudo `b64c52cb1c`, nqp `739ce7517`. End: rakudo the docs commit
on top of `a0f96f54b9`, nqp `a927b5fa1`.

| task | nqp | rakudo |
|---|---|---|
| 1 baseline, pinning tests, bench | `8fc53c956` | `9d4c655279` |
| 2 the runtime (layout, REPR, ops) | `a60cad516` | — |
| 3 the Truffle sites | `4acb88fd7` | — |
| 4 Rakudo consumers, the make, first gate | — | `3439a45c60` |
| 5 interop as `JavaCallout` | `5ee98f770` | `a0f96f54b9` |
| 6 ASM out of the build | `08029169a` | — |
| 7 gate, docs, ledger, handoff | `a927b5fa1` | (this docs commit) |

Every task was reviewed; tasks 1, 2, 4 and 5 each took exactly one fix
round, tasks 3 and 6 none beyond it.

### Numbers

Build and compile, all on the engine build (`RAKUDO_RAKUAST=1`, Oracle
GraalVM 25.2.4), one run each, forward only:

| row | milestone 5 | milestone 4 baseline |
|---|---|---|
| nqp `clean buildJvm` | **256 s** | 253 s |
| `make` from the top | **1054 s** | 1142 s |
| CORE.c compile window | **464 s** | 467 s |
| CORE.c `Stage parse` | 352.4 s | — |
| CORE.c `Stage optimize` | 36.6 s | — |

Benches (`docs/bench/jesp/plusquick.raku`, `docs/bench/jesp/attrquick.raku`,
one run each, ns/op):

| road | before | after | delta |
|---|---|---|---|
| `$a + $b` (plusquick) | 82.625 | 85.525 | +3.5 % |
| getattr | 68.75 | 71.65 | +4.2 % |
| bindattr | 57.05 | 57.65 | +1.1 % |
| getattr_i | 107.3 | 85.95 | **−19.9 %** |
| decont | 78.35 | 77.25 | −1.4 % |
| bigint+ | 172.4 | 133.0 | **−22.9 %** |
| create | 573.25 | 463.25 | **−19.2 %** |

The three roads the storage family was meant to move — `create`,
`getattr_i`, `bigint+` — are each about 20 % faster; nothing regressed
past the plan's 10 % bar.

Layout stats after a CORE.c load
(`NQP_LAYOUT_STATS=1 ./rakudo-j -e 'say 1'`):
**`layouts=2120 variants=0 reblesses=0`**, and `NQP_LAYOUT_TRACE=1` on the
same program prints no `layout: variant` and no `rebless:` line. The
spec's "requires zero variants" gate is met outright; the plan's looser
reading (`variants <= reblesses`, for the one legitimate compiler mixin
`QAST::Var+{QAST::SpecialArg}`) was never needed at this gate.

### Gates

| gate | result |
|---|---|
| `t/01-sanity` | **25 of 25** |
| `t/03-jvm/01-interop.t` | **33/33** (8 in-source skips) |
| jar census | 10/10 jars `unit.meta`-only, zero `.class` |
| runtime jar directory | 7 jars, **no `asm*.jar`** |
| ASM / `ByteClassLoader` / `defineClass` greps | all empty in both trees |
| nqp suite (`testNqp`) | 151 files, 13182 tests; **the same nine pre-existing reds** as the pre-milestone-5 runtime |
| `nqp/t/jvm/17-object-layout.t` | 47/47 |
| `nqp/t/jvm/18-rebless-layout.t` | 14/14 |
| `t/02-rakudo/mixin-identity.t` | 8/8 |
| `nqp/t/serialization/04-repossession.t` | **20/22 + 2 reader skips** — it could not run at all before (it died at line 18 on a delegate cast) |

The nine pre-existing nqp reds, classified against a throwaway
pre-milestone-5 build at `a60cad516~1` and identical on it:
`t/nqp/021-contextual.t` (6), `t/nqp/022-optional-args.t` (#7),
`t/nqp/044-try-catch.t` (#57), `t/nqp/112-continuations.t` (#15-16),
`t/qregex/01-qregex.t` (21), `t/p5regex/01-p5regex.t` (3),
`t/qast/01-qast.t` (#10 + bad plan), `t/jvm/01-continuations.t`
(#16-17, 19), `t/jvm/11-dispatch.t` (bad plan, 140 of 160).

### The t/ sweep

One sweep through the eval server, two servers at 4 GB (18 GB
MemAvailable), `RAKUDO_RAKUAST=1`, over `t/01-sanity t/02-rakudo
t/04-nativecall t/05-messages t/06-telemetry t/07-pod-to-text
t/08-performance t/10-qast t/13-experimental t/14-smoke t/03-jvm`:

```
420 files in 6039s across 60 servers
16 of 60 chunks failed
=== EXIT=1 verdict=ok elapsed=6039s ===
```

**22 files red of 420.** Against milestone 4's list: **2 fixed, 3 new.**

*Fixed since milestone 4* — `t/02-rakudo/04-settingkeys-6d.t` (2/2) and
`t/08-performance/36-rakuast-begin-compiled-remark.t` (117/117), both
re-run alone to confirm.

*Still red, exactly as milestone 4 listed them* (19): the
corekeys/settingkeys cluster less 6d — `03-corekeys.t`, `03-corekeys-6c/6d/6e.t`,
`04-settingkeys-6c/6e.t`; `21-begin-time-compile-sub.t`,
`begin-called-block-routine.t`, `compiler-frontend-id.t`,
`constant-anon-var-value.t`, `custom-declarator-naming.t`,
`make-regex-frame.t`, `m-flag-module-spec.t`,
`parse-target-match-tree.t`, `regex-interpolation-backtrack.t`,
`try-statement-backtrace-frame.t`, `native-return-coercion.t`
(**19/23**, reds 7 and 17-19 — unchanged); `t/05-messages/02-errors.t`;
`t/08-performance/15-rakuast-native-metaop.t`.

*New, each confirmed by a solo run* (3):

1. **`t/02-rakudo/native-argument-snapshot.t` 1/9 — a milestone-5
   regression, and the one real finding of this gate.** An **unsigned**
   native attribute throws
   `java.lang.ArrayIndexOutOfBoundsException: Index 15 out of bounds for length 15`.
   `int` and `int32` attributes are fine; `uint` and `uint32` are not.
   Minimal reproducers:

   ```
   # AIOOBE
   my class C { has uint32 $!cc = 32; method go { my $p := (7 => $!cc); $p.value } }; C.new.go
   # a second shape, an encoder/wire refusal rather than a bounds error
   my class C { has uint32 $!cc = 32; method go { $!cc = $!cc + 1; $!cc } }; C.new.go
   #   -> java.lang.IllegalStateException: nqpp: unknown tag 51 at 128 of 160 words
   ```

   The suspect is the pair of UINT rulings task 2 took (a UINT box target
   routed to `unboxIntSlot`; `set_int`/`set_uint` masking through
   `sizedValue`), both of which were kept on the argument that no such
   type exists in stage0 or CORE.c — true of the built setting, but not
   of user code. The test dates from 2026-07-06, so it was green through
   milestone 4. **Not fixed here** (task 7 does not touch runtime code);
   it is the first item for whoever opens the next session.
2. **`t/02-rakudo/long-int-literal.t` 8/33.** Dies compiling `-Ⅼ`
   (U+216C) with `Confused`. A Unicode numeric-literal parse problem with
   no connection to the object layout; the file dates from 2026-09-06,
   so it is new against milestone 4's *sweep list* but may equally have
   regressed in milestone 4's own fix wave, which landed after that
   sweep.
3. **`t/02-rakudo/03-cmp-ok.t` 6/7.** Test 7 fails with
   `Method 'find_method' not found for invocant of class 'FooHOW'` —
   the same mechanism as the known-red `custom-declarator-naming.t`
   (`MetamodelX::RakuLevelNameHOW`), i.e. a second file exposing one
   pre-existing bug rather than a new one.

*Not reds, though the sweep's chunk exit codes suggest otherwise:*
`t/04-nativecall/23-incomplete-types.t` and `t/05-messages/01-errors.t`
are `Failed 0` with TODO tests that passed; `t/02-rakudo/15-gh_1202.t`
passes 2/2 alone (it is simply slow — its chunk took 814 s);
`t/02-rakudo/16-begin-time-eval.t` carries a hardcoded JVM `skip-all`
from 2021 naming this very exception class.

*Sweep hygiene.* Six of sixty chunks reported "a file produced no TAP"
at chunk size 7 and 4 GB of heap. Each was resolved per file by a solo
re-run; the only one that was a genuine no-output file is
`21-begin-time-compile-sub.t`, whose known red *is* a compile failure
with no TAP. A future sweep on this box should pass `--chunk=5`.

### The questions the spec left open at plan time

| question | answer |
|---|---|
| does a `TruffleObject` marker on `RakuObject` cost anything | not taken: `RakuObject` implements no Truffle interface. `nqp-runtime` stays free of a truffle-api compile dependency, and the sites read plain fields anyway |
| the polymorphic depth for attribute sites | its own constant, **2** (`AttrSite` caches two layouts with their handles; a third marks the site unusable and the runtime op is taken) |
| is stub-time forcing of REPR data cycle-free for CORE.c | sidestepped rather than answered: `SerializationReader.peekAttributeShape(st)` reads the attribute shape straight out of the raw table, with a `shapeCache`, so `deserialize_stub` picks the canonical class without forcing the STable. Zero variant layouts after CORE.c is the evidence |
| is `RakuObject16L` ever chosen by CORE.c | kept: it is the `else` arm of both class-choice sites (`RakuObjectREPR.kt:253`, `RakuObjectLayout.kt:192`), i.e. the overflow shape every larger type lands on; not dropped |
| the interop multi-dispatch cache's key | argument classes — `ConcurrentHashMap<List<Class<*>?>, Int>` in `RakudoJavaInterop.MultiPlan`, not the descriptor string |

### Rulings that mattered in practice

Recorded in full, with the cost-if-wrong each was taken against, in
`docs/superpowers/plans/2026-09-11-jvm-milestone-5-rakuobject-layout.ledger.md`
("Rulings made during execution"). The five that changed the shipped
behaviour:

1. `is_attribute_initialized` does **not** auto-vivify — the plan's code
   was wrong and the old generated method's answer is kept.
2. num32 rounding survives a native bind (`P6num.sizedValue`), as the old
   `inlineBind` did; `set_num` stays raw.
3. A UINT box target routes to `unboxIntSlot`, not `unboxObjSlot`
   (intentional; no such type exists in stage0 or CORE.c).
4. `set_int`/`set_uint` mask through `sizedValue`, as MoarVM does.
5. A pre-milestone-5 runtime was built **once** for correctness triage of
   the nqp red list — explicitly not a perf A/B — and deleted afterwards.

Also: `t/serialization/04-repossession.t`'s JVM skip narrowed to the two
tests that fail for the *reader* reason (`stubObjects` reuses a live
object already in the SC), with that reason in the skip text, exactly as
§3 asked.

### Parked residuals

One milestone-5 regression is open — **unsigned native attributes**
(`t/02-rakudo/native-argument-snapshot.t`, above); it is the next
session's first item, not a parked residual. The rest are real, narrow,
and none of them milestone-5 regressions:

- **`t/02-rakudo/native-return-coercion.t` 19/23**, unchanged from
  milestone 4 (reds #7, #17, #18, #19, all `dies-ok` cases about boxed
  Int / subset returns to a native num). It needs its own session.
- **The six milestone-4 reds never root-caused**:
  `21-begin-time-compile-sub.t`, `custom-declarator-naming.t`,
  `make-regex-frame.t`, `try-statement-backtrace-frame.t`,
  `regex-interpolation-backtrack.t`, `m-flag-module-spec.t` — plus the
  expected corekeys/settingkeys cluster and the other known reds.
- **The nine pre-existing nqp suite reds** listed above.
- **`slowEvals` on the plusquick road went 364 → 976** with every other
  dispatch counter identical, and plusquick is +3.5 %. Unexplained; the
  natural place to look is the perf measurement session.
- **A dead import in `Binder.kt`** left rather than pay a settings
  rebuild for it.
- The task-3 site minors (stale `NqpDispatch` comments; `DecontSite`
  never `miss()`ing on a layout mismatch; `resolveBigInt` indexing
  `kinds[unboxIntSlot]` unchecked; `BigIntSite` not re-verifying
  `rd.layout === layout`; `AttrSite`'s unfenced triple publication, an
  inherited shape) and the task-5 interop minors (an `unreflect` failure
  on a public method of a non-public declaring class fails the whole
  class at plan-build time where the old road failed at first call;
  interop test cases that never read the exact cache). The ledger's
  "Deferred minors" section has the whole list.

Out of scope and still out: `DynamicObject`/`Shape`, an `Assumption` per
STable, polyglot `InteropLibrary` exports, Native Image, t/spec.

### Next

First the unsigned-native-attribute regression above (a runtime fix in
task 2's territory, with `native-argument-snapshot.t` as its gate), then
the perf measurement session (truffle-only plan item 4, the compiler's
own workload), then the engine merge — one Truffle language.
