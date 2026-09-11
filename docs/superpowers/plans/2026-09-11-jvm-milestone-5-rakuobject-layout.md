# JVM Milestone 5: RakuObject Layout, ASM Gone — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** P6Opaque's runtime-generated attribute-storage classes become a static family of `RakuObject` classes guarded by an immutable per-STable `RakuObjectLayout`; mixins rebless in place and the delegate road dies; the interop adaptor becomes one hand-written callout over per-member plans; ASM leaves the build; nothing generates a class at run time.

**Architecture:** The layout is the Shape analogue: per abstract slot (the hint) a kind and a physical placement (inline field or overflow array) on one of six hand-written classes; the fast sites guard on layout identity and read a constant handle from static per-class tables. The serialization wire format is untouched, so stage0 and every precompiled jar stay valid; a deserialization stub picks its class by peeking at the serialized attribute header. Tasks: nqp runtime first (the big-bang rename and rewire), Rakudo consumers and the make, the Truffle sites, interop, ASM removal, the milestone gate.

**Tech Stack:** Kotlin 2.4 (nqp-runtime, nqp-truffle, rakudo-runtime), Java only where the Truffle DSL owns the file (`NqpOps.java`, `NqpRootNode.java`: edits in place, no new Java), gradle, NQP tests (`nqp/t/jvm/*.t`), Raku tests and tooling (`watched-run.raku`, `evalserver-sweep.raku`, `jar-census.raku`).

**Spec:** `docs/superpowers/specs/2026-09-11-jvm-unit-artifact-milestone-5-design.md` (rakudo `b1b6bbfe07`). Sections 1-7 map onto Tasks 2-7; the spec's "Open at plan time" list is settled under "Plan rulings".

## Global Constraints

- Two git trees: rakudo worktree root `/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records` (branch `worktree-jesp-direct-lazy-records`) and the nested `nqp/` tree (branch `jesp-direct-lazy-records`). Every nqp path below is under `nqp/`. The worktree guard refuses `git -C nqp`, `/usr/bin/time`, heredocs, shell loops, and a computed variable standing where an option could be: spell paths out in full; nqp git commands run as `cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git ...` in their own shell call. Label every hash by tree. Start of this plan: rakudo `b1b6bbfe07`, nqp `739ce7517`.
- Kotlin, never Java, for new code. `NqpOps.java` and `NqpRootNode.java` are the Truffle DSL's files: edited in place, nothing added that a Kotlin file could hold. `NqpRaw.java` keeps its exact-typed `invokeExact` helpers (package-private, `org.raku.nqp.truffle`).
- PE-visible Kotlin: `@JvmField`s only, no `lateinit` reads on a fast road, no `!!` on a fast road (nqp-truffle compiles without null assertions).
- Every diagnostic print is env-gated (`System.getenv(...)` / `nqp::getenvhash()`); never a bare print.
- The serialization wire format does not change: no byte written or read differently by `SerializationWriter`/`SerializationReader`, the REPR-data record or the per-object slot stream. No stage0 regeneration.
- The REPR's registered name stays `P6opaque` (`REPRRegistry.kt`, ID 2).
- `RakuObject` never overrides `hashCode`/`equals` (`nqp::objectid` is `Object.hashCode()` after decont).
- Runtime-jar-only changes rebuild with `./nqp/gradlew -p nqp :nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars` (~10-30 s) from the rakudo worktree root; restart eval servers after any runtime jar rebuild. Nothing in this plan touches `nqp/src/vm/jvm/QAST`, `HLL`, `NQP` or `nqp/src/HLL`, so no `clean buildJvm` is needed until Task 6's proof build.
- nqp tests: `cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && prove -r --exec ./nqp-j-gradle t/jvm t/serialization` (single file: `./nqp-j-gradle t/jvm/17-object-layout.t`); the whole nqp suite is `./gradlew testNqp` from `nqp/` (t/nqp, t/hll, t/qregex, t/p5regex, t/qast, t/jvm, t/serialization, t/nativecall; 118 files in t/nqp; `t/qast/01-qast.t` is moar-only, known red).
- Rakudo: `RAKUDO_RAKUAST=1` on every build, test and run; the in-tree runners have no module repo, so `./rakudo-j -Ilib t/...`. Runs longer than 30 s go through `raku tools/build/watched-run.raku` (`--log=`, `--show=` literals, `--show-file=PATH`, `--max=SECONDS`, `-t=DIR --jobs=N`, as a plain background job, never `setsid`/`nohup`); look for its `=== EXIT=<n> verdict=<v> elapsed=<s>s ===` line; progress reported every 90 s. Logs go under the executing session's `$CLAUDE_JOB_DIR/tmp` (this plan writes `/home/longwalker/.claude/jobs/5c60252a/tmp/`; another session substitutes its own).
- `java` is Oracle GraalVM 25.2.4.
- One compile per change, forward only; a build that breaks is fixed by amending the same commit. Single benchmark runs. Baseline at the start (milestone 4, inliner restored): nqp `clean buildJvm` 253 s; `make` 1142 s (CORE.c 467 s); t/nqp 118/118; `t/01-sanity` 25/25; interop 30 planned / 22 live / 8 skipped; precomp 14/14.
- Commits carry `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01WCVcQMRewmoK9asUNaQNdw`, with `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE` set to an evening slot (18:00-23:00 +0200) of the commit's calendar day, later than the previous commit on the branch.
- No t/spec. No A/B builds. Tooling in Raku.

## User decisions (2026-09-11, brainstorm)

1. Milestone 5 = item 9's P6Opaque half plus ASM gone entirely; no runtime class generation anywhere, interop included.
2. Approach C (static instance family + per-STable layout); Kotlin classes renamed `RakuObject*`; REPR name string stays.
3. Interop kept, rewritten on method-handle plans, time-boxed; dropped with a clear message if it stalls.
4. Gate: fast gates per task; one t/ sweep at the close diffed against milestone 4's red list.

## Plan rulings (the spec's open items, settled)

- **No `TruffleObject` marker on `RakuObject`.** nqp-runtime sees truffle-api only as `compileOnly`, and a boot-classpath class implementing a module-path interface is a class-loading dependency, not a free marker. Polyglot exports are a later item on their own terms.
- **Polymorphic depth of the attribute sites: 2 layouts**, then the slow road; misses counted with the existing `MAX_MISSES = 4` policy of `NqpTypeOps`. `NqpOps.AttrSite` gets a second entry (`layout2`/`getter2`/`setter2`), nothing more.
- **Stub-time class choice needs no REPR-data forcing.** The STables table entry is 12 bytes: REPR name, STable data offset, REPR-data offset (`SerializationWriter.kt:526-527, 609`; `SerializationReader.kt:31`). The RakuObject REPR-data record begins with the attribute count and, per attribute, a flag plus an STable ref for a flattened type (`serialize_repr_data`). A stub therefore peeks at `stTableOffset + i*12 + 8`, counts reference and long slots from the flattened STables' REPRs (set at STable stub time, `stubSTables`), and picks the class; no object reference is read, no cycle is possible. The variant road stays as the safety net and the CORE.c gate requires zero variants.
- **`RakuObject16L` is kept** (the census cannot see mixin-grown or module-defined types; a class is 20 lines).
- **Interop multi-dispatch cache key:** the list of argument classes (`List<Class<*>?>`), exact matches only (a cast-selected candidate is re-selected per call, as today).
- **`CPointer` is not a slot kind.** Its `get_storage_spec` is the reference default, so it was never a flattened attribute and never a legal box target (`generateJVMClass` refuses a reference box target); its `generateBoxingMethods` was dead and goes with the hook. The spec's "CPointer box target = INT slot" sentence is void.
- **The flattening hooks collapse to one:** `REPR.inlinedKind(): SlotKind?` (P6int INT, P6num NUM, P6str STR, P6bigint BIGINT, NativeCall NCBODY, everything else null). `serialize_inlined`, `inline_description`, `box_description` and the four ASM hooks are deleted; the layout writer and reader serialize by kind, byte-for-byte what the hooks wrote (INT `writeInt`, NUM `writeNum`, STR `writeStr`, BIGINT `writeStr(toString)`, NCBODY nothing).
- **Exception-based native/reference signalling goes.** `RakuObject.get_attribute_boxed` on a native slot dies with the old text "Cannot access a native attribute as a reference attribute"; `get_attribute_native` on a reference slot dies with "Cannot access a reference attribute as a native attribute". Every op that used to catch decides by `layout.kindOf(slot)` first. The `BadReferenceRuntimeException`/`BadNativeRuntimeException` classes are deleted; `t/02-rakudo/10-nqp-ops.t:10`'s todo text is updated to the new class name.
- **`cf.leave()` on the die path of the interop callout** (the spec's ruling); if `t/03-jvm/01-interop.t` shows a difference, the two lines revert to today's shape and the ledger says so.

## File structure

nqp runtime (`nqp/src/vm/jvm/runtime/org/raku/nqp/`):
- `sixmodel/reprs/RakuObjectREPR.kt` (new; replaces `P6Opaque.kt`): the REPR — compose builds a layout; allocate; change_type in place; hint_for; storage spec; REPR-data serialize/deserialize; stub (peek), finish, serialize by kind.
- `sixmodel/reprs/RakuObjectREPRData.kt` (new; replaces `P6OpaqueREPRData.kt`): `layout`, `variants`, `intCache`.
- `sixmodel/reprs/RakuObjectLayout.kt` (new): `SlotKind`, the layout (kinds, placement, handles, maps, unbox slots), static per-class handle tables, allocation, `NQP_LAYOUT_STATS`/`NQP_LAYOUT_TRACE`.
- `sixmodel/reprs/RakuObject.kt` (new; replaces `P6OpaqueBaseInstance.kt` + the generated classes): abstract base with `layout`, `oExt`, `lExt`, the attribute/boxing/atomic/positional API, and the six concrete classes.
- `sixmodel/reprs/P6OpaqueDelegateInstance.kt`: deleted.
- `sixmodel/REPR.kt`: eight hooks out, `inlinedKind()` in, `deserialize_stub(tc, st, reader)` overload in.
- `sixmodel/reprs/P6int.kt`, `P6num.kt`, `P6str.kt`, `P6bigint.kt`, `NativeCall.kt`, `CPointer.kt`: hooks removed, `inlinedKind` added.
- `sixmodel/SerializationReader.kt`: `stubObjects` calls the 3-arg stub; `peekAttributeShape(st)`.
- `runtime/Ops.kt`: the attribute ops, `getBI`/`makeBI`, on the layout.
- `dispatch/DispatchModel.kt`: `attributeKind` on the layout.
- `runtime/NativeCallOps.kt`: no delegate to follow.
- `runtime/JavaCallout.kt` (new, Task 5): `CalloutPlan`, `MemberPlan`, `VarArityPlan`, `ArgMarshal`, `RetMarshal`, `JavaCallout.invoke`.
- `runtime/AdaptorUnit.kt`: code refs from plans.
- `runtime/BootJavaInterop.kt`: plan builder; the ASM, callin and proxy halves deleted.
- `runtime/ByteClassLoader.kt`, `runtime/BytecodeVersion.kt`: deleted (Task 6); `GlobalContext.kt` loses `byteClassLoader`.

nqp engine (`nqp/nqp-truffle/src/main/`): `java/org/raku/nqp/truffle/NqpOps.java` (AttrSite), `kotlin/org/raku/nqp/truffle/NqpDispatch.kt` (AttrSrc, UnboxSrc, fold, `fieldHandles` → `layoutHandles`), `kotlin/org/raku/nqp/truffle/NqpTypeOps.kt` (DecontSite, CreateSite, BigIntSite).

Rakudo runtime (`src/vm/jvm/runtime/org/raku/rakudo/`): `Binder.kt` (kind from the layout), `RakudoContainerSpec.kt` (atomic load through the layout), `RakudoJavaInterop.kt` (plans + `MultiPlan`).

Build: `nqp/buildSrc/src/main/kotlin/NqpDeps.kt`, `nqp/tools/lib/NQP/Config/NQP.pm`, `nqp/tools/templates/jvm/Makefile.in`, `nqp/tools/templates/jvm/nqp-j.in`, `nqp/3rdparty/asm/`.

Tests: `nqp/t/jvm/17-object-layout.t`, `nqp/t/jvm/18-rebless-layout.t` (new), `nqp/t/serialization/04-repossession.t` (skip removed), `t/02-rakudo/mixin-identity.t` (new), `t/03-jvm/01-interop.t` (one case added), `docs/bench/jesp/attrquick.raku` (new).

---

### Task 1: Baseline numbers, the pinning tests, the attribute bench

**Files:**
- Create: `nqp/t/jvm/17-object-layout.t`, `nqp/t/jvm/18-rebless-layout.t`, `t/02-rakudo/mixin-identity.t`, `docs/bench/jesp/attrquick.raku`
- Ledger: `docs/superpowers/plans/2026-09-11-jvm-milestone-5-rakuobject-layout.ledger.md` (new; the numbers land here)

**Interfaces:**
- Consumes: the milestone 4 build in the worktree (`./rakudo-j`, `nqp/nqp-j-gradle`).
- Produces: three test files green on the OLD runtime (behaviour pins; the parts that need the new runtime are marked and added in Task 2), and the "before" rows of the bench table.

- [ ] **Step 1: the "before" numbers.** From the worktree root, one run each:

```
RAKUDO_RAKUAST=1 NQP_DISPATCH_STATS=1 ./rakudo-j docs/bench/jesp/plusquick.raku
```

Record `ns/op` in the ledger under "plusquick before".

- [ ] **Step 2: the attribute bench.** Write `docs/bench/jesp/attrquick.raku`:

```raku
use nqp;
# Five attribute roads, ns/op each, single run. 2M warmup + 20M timed.
class P { has $.a; has $.b }
my class N { has int $.i; has num $.n }
my $p = P.new(a => 1, b => 2);
my $n = N.new(i => 3, n => 4e0);
my $s := my $scalar = 42;        # a Scalar container: decont road
my $big = 2 ** 70;               # bigint road (never fits a long)
my $sum = 0;

sub timed(Str $name, &code) {
    my int $w = 0; while $w < 2000000 { code(); $w = $w + 1; }
    my $t0 = nqp::time(); my int $i = 0;
    while $i < 20000000 { code(); $i = $i + 1; }
    nqp::say($name ~ " ns/op=" ~ (nqp::sub_i(nqp::time(), $t0) / 20000000));
}
timed("getattr",  { $sum = nqp::getattr($p, P, '$!a') });
timed("bindattr", { nqp::bindattr($p, P, '$!b', $sum) });
timed("getattr_i",{ $sum = nqp::getattr_i($n, N, '$!i') });
timed("decont",   { $sum = nqp::decont($scalar) });
timed("bigint+",  { $sum = $big + $big });
timed("create",   { $sum = P.new });
nqp::say("check " ~ $sum.^name);
```

Run `RAKUDO_RAKUAST=1 ./rakudo-j docs/bench/jesp/attrquick.raku` once; record the six `ns/op` lines under "attrquick before". If a line is above 1000 ns/op on the old build, note it: that road was never sited and is not a regression target.

- [ ] **Step 3: `nqp/t/jvm/17-object-layout.t`** (runs green on the OLD runtime; it pins behaviour the layout must keep):

```
use nqpmo;

# The RakuObject layout, pinned: attribute counts across the storage-class
# grid (4, 8, 16 inline references; 0 or 2 inline longs) and past it (the
# overflow arrays), every slot kind through the ops, hints, multiple
# inheritance, the four error texts, clone. Written before milestone 5's
# runtime and green on milestone 4's, so a difference is a regression.

plan(46);

# --- reference slots across the grid boundaries: 3, 4, 5, 8, 9, 16, 17 ---
class R3  { has $!a; has $!b; has $!c; }
class R4  { has $!a; has $!b; has $!c; has $!d; }
class R5  { has $!a; has $!b; has $!c; has $!d; has $!e; }
class R8  { has $!a; has $!b; has $!c; has $!d; has $!e; has $!f; has $!g; has $!h; }
class R9  is R8 { has $!i; }
class R16 is R8 { has $!i; has $!j; has $!k; has $!l; has $!m; has $!n; has $!o; has $!p; }
class R17 is R16 { has $!q; }

sub fill($obj, $type, @names) {
    my int $i := 0;
    for @names { nqp::bindattr($obj, $type, '$!' ~ $_, $i); $i := $i + 1; }
}
sub check($obj, $type, @names, $label) {
    my int $ok := 1; my int $i := 0;
    for @names { $ok := 0 unless nqp::getattr($obj, $type, '$!' ~ $_) == $i; $i := $i + 1; }
    ok($ok, $label);
}
my @r8  := <a b c d e f g h>;
my @r16 := <a b c d e f g h i j k l m n o p>;

my $r3 := R3.new;  fill($r3, R3, <a b c>);        check($r3, R3, <a b c>, '3 refs');
my $r4 := R4.new;  fill($r4, R4, <a b c d>);      check($r4, R4, <a b c d>, '4 refs (boundary)');
my $r5 := R5.new;  fill($r5, R5, <a b c d e>);    check($r5, R5, <a b c d e>, '5 refs');
my $r8 := R8.new;  fill($r8, R8, @r8);            check($r8, R8, @r8, '8 refs (boundary)');
my $r9 := R9.new;  fill($r9, R8, @r8); nqp::bindattr($r9, R9, '$!i', 8);
ok(nqp::getattr($r9, R9, '$!i') == 8 && nqp::getattr($r9, R8, '$!h') == 7, '9 refs across a parent');
my $r16 := R16.new; fill($r16, R8, @r8);
fill($r16, R16, <i j k l m n o p>);
ok(nqp::getattr($r16, R16, '$!p') == 7 && nqp::getattr($r16, R8, '$!a') == 0, '16 refs (boundary)');
my $r17 := R17.new; fill($r17, R8, @r8); fill($r17, R16, <i j k l m n o p>);
nqp::bindattr($r17, R17, '$!q', 99);
ok(nqp::getattr($r17, R17, '$!q') == 99, '17 refs: the slot past the largest class');
ok(nqp::getattr($r17, R16, '$!p') == 7, '17 refs: the last inline slot still reads');

# --- long slots: 0, 1, 2, 3 natives, mixed with references ---
class L1 { has int $!i; has $!o; }
class L2 { has int $!i; has num $!n; has $!o; }
class L3 { has int $!i; has num $!n; has int $!j; has $!o; }
my $l1 := L1.new; nqp::bindattr_i($l1, L1, '$!i', 7); nqp::bindattr($l1, L1, '$!o', 'x');
ok(nqp::getattr_i($l1, L1, '$!i') == 7 && nqp::getattr($l1, L1, '$!o') eq 'x', '1 long + 1 ref');
my $l2 := L2.new; nqp::bindattr_i($l2, L2, '$!i', 1); nqp::bindattr_n($l2, L2, '$!n', 2.5);
ok(nqp::getattr_i($l2, L2, '$!i') == 1 && nqp::getattr_n($l2, L2, '$!n') == 2.5, '2 longs (boundary)');
my $l3 := L3.new; nqp::bindattr_i($l3, L3, '$!i', 1); nqp::bindattr_n($l3, L3, '$!n', 2.5);
nqp::bindattr_i($l3, L3, '$!j', 3);
ok(nqp::getattr_i($l3, L3, '$!j') == 3 && nqp::getattr_n($l3, L3, '$!n') == 2.5, '3 longs: the slot past the inline pair');

# --- every kind through the ops ---
class K { has int $!i; has num $!n; has str $!s; has $!o; }
my $k := K.new;
nqp::bindattr_i($k, K, '$!i', -5); nqp::bindattr_n($k, K, '$!n', 1.5);
nqp::bindattr_s($k, K, '$!s', 'str'); nqp::bindattr($k, K, '$!o', $k);
ok(nqp::getattr_i($k, K, '$!i') == -5, 'int slot');
ok(nqp::getattr_n($k, K, '$!n') == 1.5, 'num slot');
ok(nqp::getattr_s($k, K, '$!s') eq 'str', 'str slot');
ok(nqp::eqaddr(nqp::getattr($k, K, '$!o'), $k), 'ref slot');
ok(nqp::getattr($k, K, '$!i') == -5, 'a native int read boxed');
ok(nqp::getattr($k, K, '$!n') == 1.5, 'a native num read boxed');
ok(nqp::getattr($k, K, '$!s') eq 'str', 'a native str read boxed');

# --- attrinited, hints, MI ---
class I { has $!x; has $!y; }
my $iobj := I.new;
ok(nqp::attrinited($iobj, I, '$!x') == 0, 'attrinited is 0 before a bind');
nqp::bindattr($iobj, I, '$!x', 1);
ok(nqp::attrinited($iobj, I, '$!x') == 1, 'attrinited is 1 after a bind');
ok(nqp::attrhintfor(I, '$!x') == 0 && nqp::attrhintfor(I, '$!y') == 1, 'hints are the slot numbers, parents first');
ok(nqp::attrhintfor(R9, '$!i') == 8, "a subclass's own attribute follows the parent's slots");
ok(nqp::attrhintfor(I, '$!nope') == -1, 'no hint for an unknown attribute');
class MA { has $!a; }
class MB { has $!b; }
class MAB is MA is MB { has $!c; }
my $mab := MAB.new;
nqp::bindattr($mab, MA, '$!a', 'a'); nqp::bindattr($mab, MB, '$!b', 'b'); nqp::bindattr($mab, MAB, '$!c', 'c');
ok(nqp::getattr($mab, MA, '$!a') eq 'a' && nqp::getattr($mab, MB, '$!b') eq 'b'
    && nqp::getattr($mab, MAB, '$!c') eq 'c', 'multiple inheritance resolves by name');

# --- the four error texts ---
sub dies_with($code, $needle, $label) {
    my $msg := '';
    try { $code(); CATCH { $msg := nqp::getmessage($_); } }
    ok(nqp::index($msg, $needle) >= 0, $label ~ " ($msg)");
}
dies_with({ nqp::getattr($iobj, I, '$!nope') }, "No such attribute '\$!nope'", 'unknown attribute');
dies_with({ nqp::getattr_i($iobj, I, '$!x') }, 'Cannot access a reference attribute as a native attribute', 'reference slot read natively');
dies_with({ nqp::getattr_i($k, K, '$!o') }, 'Cannot access a reference attribute as a native attribute', 'reference slot read natively (K)');
dies_with({ nqp::rebless(I.new, K) }, 'Incompatible MROs', 'rebless to an unrelated type');

# --- clone ---
my $c17 := nqp::clone($r17);
ok(nqp::getattr($c17, R17, '$!q') == 99 && nqp::getattr($c17, R8, '$!a') == 0, 'clone copies inline and overflow slots');
nqp::bindattr($c17, R17, '$!q', 1);
ok(nqp::getattr($r17, R17, '$!q') == 99, 'a clone has its own overflow array');
my $cl3 := nqp::clone($l3);
nqp::bindattr_i($cl3, L3, '$!j', 30);
ok(nqp::getattr_i($l3, L3, '$!j') == 3, 'a clone has its own long overflow array');

# --- boxing through the unbox slots (built as t/nqp/098-boxing.t builds them) ---
sub boxer($name, $type) {
    my $t := NQPClassHOW.new_type(:name($name), :repr('P6opaque'));
    $t.HOW.add_attribute($t, NQPAttribute.new(:name('$!value'), :type($type), :box_target(1)));
    $t.HOW.add_parent($t, NQPMu);
    $t.HOW.compose($t);
    $t
}
my $BI := boxer('BI', int); my $BN := boxer('BN', num); my $BS := boxer('BS', str);
ok(nqp::unbox_i(nqp::box_i(42, $BI)) == 42, 'int box target');
ok(nqp::unbox_n(nqp::box_n(4.5, $BN)) == 4.5, 'num box target');
ok(nqp::unbox_s(nqp::box_s('q', $BS)) eq 'q', 'str box target');
ok(nqp::unbox_i(nqp::box_i(-1, $BI)) == -1, 'int box target keeps the sign');

# --- sized natives store truncated, as MoarVM's sized registers do ---
my $S8 := NQPClassHOW.new_type(:name('S8'), :repr('P6opaque'));
$S8.HOW.add_attribute($S8, NQPAttribute.new(:name('$!v'), :type(int8)));
$S8.HOW.add_attribute($S8, NQPAttribute.new(:name('$!u'), :type(uint8)));
$S8.HOW.add_parent($S8, NQPMu);
$S8.HOW.compose($S8);
my $s8 := nqp::create($S8);
nqp::bindattr_i($s8, $S8, '$!v', 300); nqp::bindattr_i($s8, $S8, '$!u', 300);
ok(nqp::getattr_i($s8, $S8, '$!v') == 44, 'int8 wraps to its width');
ok(nqp::getattr_i($s8, $S8, '$!u') == 44, 'uint8 masks to its width');

# --- type objects ---
dies_with({ nqp::getattr(I, I, '$!x') }, 'does not support attributes', 'attribute read on a type object');
ok(nqp::isconcrete(I.new) == 1 && nqp::isconcrete(I) == 0, 'isconcrete');

# --- positional / associative delegates ---
class PD { has @!list is positional_delegate; has %!hash is associative_delegate; }
my $pd := PD.new;
nqp::bindattr($pd, PD, '@!list', nqp::list(1, 2, 3));
nqp::bindattr($pd, PD, '%!hash', nqp::hash('k', 'v'));
ok(nqp::elems($pd) == 3 && nqp::atpos($pd, 1) == 2, 'positional delegate');
ok(nqp::atkey($pd, 'k') eq 'v' && nqp::existskey($pd, 'k'), 'associative delegate');
nqp::push($pd, 4);
ok(nqp::elems($pd) == 4, 'push through the delegate');

# --- 46 planned; the remaining ok()s pin auto-viv ---
class AV { has @!a; has %!h; has $!s; }
my $av := AV.new;
ok(nqp::islist(nqp::getattr($av, AV, '@!a')), 'an @ attribute auto-vivifies a list');
ok(nqp::ishash(nqp::getattr($av, AV, '%!h')), 'a % attribute auto-vivifies a hash');
ok(nqp::isnull(nqp::getattr($av, AV, '$!s')), 'a $ attribute is null until bound');
ok(nqp::attrinited($av, AV, '@!a') == 1, 'auto-viv counts as initialized');
```

Run: `cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && ./nqp-j-gradle t/jvm/17-object-layout.t`. Expected: every test passes on the old runtime except possibly the sized-native or type-object message lines; **if a test fails on the old runtime, the old behaviour is the truth: fix the test's expectation to what milestone 4 does and note the line in the ledger** (the layout must reproduce milestone 4, not improve on it). Adjust `plan()` to the final count.

- [ ] **Step 4: `nqp/t/jvm/18-rebless-layout.t`** (green on the old runtime for identity and values; the layout observations are Task 2's addition):

```
# Rebless (nqp::rebless, the road behind Raku's `does` on an instance) keeps
# the object: same identity, same attribute values, the target's new slots
# readable. Each source class size reblesses into a type one size up, so the
# new runtime's in-place growth is exercised across every grid boundary.

plan(14);

class A4  { has $!a; has $!b; has $!c; has $!d; }
class A5  is A4 { has $!e; }
class A8  is A5 { has $!f; has $!g; has $!h; }
class A9  is A8 { has $!i; }
class A16 is A9 { has $!j; has $!k; has $!l; has $!m; has $!n; has $!o; has $!p; }
class A17 is A16 { has $!q; }
class L0  { has $!x; }
class L1  is L0 { has int $!i; }
class L3  is L1 { has num $!n; has int $!j; }

sub rebless_check($obj, $from, $to, $attr, $label) {
    nqp::bindattr($obj, $from, '$!a', 'kept') if nqp::attrhintfor($from, '$!a') >= 0;
    my $before := $obj;
    my $after := nqp::rebless($obj, $to);
    ok(nqp::eqaddr($before, $after), $label ~ ': identity kept');
    nqp::bindattr($after, $to, $attr, 'new');
    ok(nqp::getattr($after, $to, $attr) eq 'new'
        && (nqp::attrhintfor($from, '$!a') < 0 || nqp::getattr($after, A4, '$!a') eq 'kept'),
        $label ~ ': old values kept, new slot works');
}
rebless_check(A4.new,  A4,  A5,  '$!e', '4 -> 5 (into overflow of a 4-class)');
rebless_check(A8.new,  A8,  A9,  '$!i', '8 -> 9');
rebless_check(A16.new, A16, A17, '$!q', '16 -> 17');
rebless_check(A4.new,  A4,  A16, '$!p', '4 -> 16 (twelve slots past the class)');

my $l := L0.new; nqp::bindattr($l, L0, '$!x', 'x');
nqp::rebless($l, L1); nqp::bindattr_i($l, L1, '$!i', 5);
ok(nqp::getattr_i($l, L1, '$!i') == 5 && nqp::getattr($l, L0, '$!x') eq 'x', 'a long slot appears on rebless');
nqp::rebless($l, L3); nqp::bindattr_n($l, L3, '$!n', 2.5); nqp::bindattr_i($l, L3, '$!j', 9);
ok(nqp::getattr_n($l, L3, '$!n') == 2.5 && nqp::getattr_i($l, L3, '$!j') == 9
    && nqp::getattr_i($l, L1, '$!i') == 5, 'three longs after two reblesses');

# A reblessed object and a fresh one of the target type agree.
my $fresh := A9.new; nqp::bindattr($fresh, A9, '$!i', 'f');
my $grown := nqp::rebless(A8.new, A9); nqp::bindattr($grown, A9, '$!i', 'g');
ok(nqp::getattr($fresh, A9, '$!i') eq 'f' && nqp::getattr($grown, A9, '$!i') eq 'g', 'fresh and grown objects of one type both work');
ok(nqp::eqaddr(nqp::what($grown), A9), 'the grown object is of the target type');

# Rebless of a clone leaves the original alone (Raku's `but`).
my $orig := A4.new; nqp::bindattr($orig, A4, '$!a', 'o');
my $but := nqp::rebless(nqp::clone($orig), A5);
ok(!nqp::eqaddr($orig, $but) && nqp::eqaddr(nqp::what($orig), A4), 'clone-then-rebless keeps the original');

# Errors.
my $msg := '';
try { nqp::rebless(A4.new, L1); CATCH { $msg := nqp::getmessage($_); } }
ok(nqp::index($msg, 'Incompatible MROs') >= 0, 'rebless to an incompatible type dies');
```

Run it the same way; fix expectations to milestone 4's behaviour where they differ, note in the ledger, set `plan()`.

- [ ] **Step 5: `t/02-rakudo/mixin-identity.t`**:

```raku
use Test;
plan 8;

role Modified { has $.tag = "m"; method shout { "modified" } }
class Foo { has $.x = 1 }

my $obj = Foo.new(x => 42);
my $which = $obj.WHICH;
my $butted = $obj but Modified;
nok $obj === $butted, 'but yields a new identity';
is $obj.WHICH, $which, 'but leaves the original WHICH alone';
is $obj.^name, 'Foo', 'but leaves the original type alone';
is $butted.tag, 'm', 'the but-clone has the role attribute';

my $obj2 = Foo.new(x => 7);
my $w2 = $obj2.WHICH;
my $doesd = $obj2 does Modified;
ok $obj2 === $doesd, 'does keeps identity';
is $obj2.x, 7, 'does keeps the attribute values';
is $obj2.shout, 'modified', 'does adds the role method';
is $obj2.^name, 'Foo+{Modified}', 'does changes the type in place';
```

Run: `RAKUDO_RAKUAST=1 ./rakudo-j -Ilib t/02-rakudo/mixin-identity.t` (8/8 on the old build; if `.WHICH` differs after `does` on the JVM, the ledger records it and the test drops that assertion).

- [ ] **Step 6: ledger + commit.** Create the ledger with the "before" tables (plusquick, attrquick, the two nqp tests' plan counts, any expectation adjusted). Commit (rakudo, evening stamp):

```
git add docs/bench/jesp/attrquick.raku t/02-rakudo/mixin-identity.t docs/superpowers/plans/2026-09-11-jvm-milestone-5-rakuobject-layout.md docs/superpowers/plans/2026-09-11-jvm-milestone-5-rakuobject-layout.ledger.md
git commit -m "milestone 5: plan, ledger, the attribute bench and the mixin identity test"
```

and (nqp, from `cd .../nqp`): `git add t/jvm/17-object-layout.t t/jvm/18-rebless-layout.t && git commit -m "tests: the object layout and rebless pins, written against the milestone 4 runtime"`.

---

### Task 2: The RakuObject family, the layout, the REPR, the nqp runtime consumers

One task because nqp-runtime must compile at its end: the old classes are referenced from 41 places and the rename touches all of them. The Truffle engine (`nqp-truffle`, Task 3) and the Rakudo runtime (Task 4) reference the old classes too and do not compile between this task's commit and theirs. Task 2's gate is therefore "nqp-runtime compiles and its unit tests pass"; the NQP-level tests (t/nqp, t/jvm, t/serialization) run at the end of Task 3, once the engine links again. Tasks 2, 3 and 4 are executed back to back.

**Files:**
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/reprs/RakuObjectLayout.kt`, `RakuObject.kt`, `RakuObjectREPRData.kt`, `RakuObjectREPR.kt`
- Delete: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/reprs/P6Opaque.kt`, `P6OpaqueBaseInstance.kt`, `P6OpaqueDelegateInstance.kt`, `P6OpaqueREPRData.kt`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/REPR.kt:118-149` (hooks), `:97-98` (stub overload); `REPRRegistry.kt:56` (`RakuObjectREPR()`); `reprs/P6int.kt`, `P6num.kt`, `P6str.kt`, `P6bigint.kt`, `NativeCall.kt`, `CPointer.kt` (hooks out, `inlinedKind` in); `SerializationReader.kt:366-393` (`stubObjects`) + new `peekAttributeShape`; `runtime/Ops.kt:3478-3820, 8612-8663`; `dispatch/DispatchModel.kt:186-200`; `runtime/NativeCallOps.kt:615-635`
- Test: `nqp/t/jvm/17-object-layout.t`, `18-rebless-layout.t`, `nqp/t/serialization/04-repossession.t` (skip removed), `nqp/t/jvm/04-serialization-types.t`, `06-atomic-attrs.t`

**Interfaces:**
- Consumes: `REPR`, `SixModelObject`, `STable.NO_HINT = -1L`, `ThreadContext.NATIVE_INT/NUM/STR/JVM_OBJ` + `nativeI/N/S/J/Type`, `SerializationReader.readRef/readLong/readDouble/readStr/readSTableRef`, `SerializationWriter.writeRef/writeInt/writeNum/writeStr/writeSTableRef/writeIntHash`, `P6int.sizedValue(StorageSpec?, Long)`, `P6bigint.checkedLongValue/uncheckedLongValue/unsignedValueOf`.
- Produces (used by Tasks 3-5):
  - `enum class SlotKind { REF, INT, NUM, STR, BIGINT, NCBODY }` (`RakuObjectLayout.kt`)
  - `class RakuObjectLayout` with `@JvmField val st: STable`, `storage: Class<out RakuObject>`, `classId: Int`, `refCap: Int`, `longCap: Int`, `kinds: Array<SlotKind>`, `index: IntArray`, `specs: Array<StorageSpec?>`, `slotSTables: Array<STable?>`, `autoViv: Array<SixModelObject?>`, `classHandles: Array<SixModelObject?>`, `nameToSlot: ArrayList<Object2IntOpenHashMap<String>>`, `mi: Boolean`, `unboxIntSlot/unboxNumSlot/unboxStrSlot/unboxObjSlot/posDelSlot/assDelSlot: Int`, `variant: Boolean`; methods `slotFor(classHandle, name): Int` (-1 = none), `resolve(classHandle, name): Int` (dies "No such attribute"), `slotForName(name): Int`, `kindOf(slot)`, `isLongKind(slot)`, `getRef(o, slot): Any?`, `setRef(o, slot, v)`, `getLong(o, slot): Long`, `setLong(o, slot, v)`, `getVolatile(o, slot)`, `setVolatile(o, slot, v)`, `compareAndSet(o, slot, exp, v): Boolean`, `refGetter(slot): MethodHandle` `(SixModelObject)Object`, `refSetter(slot): MethodHandle` `(SixModelObject,Object)void`, `longGetter(slot)/longSetter(slot)`, `newInstance(): RakuObject`, `growExt(o)`; companion `chooseClass(refs, longs): Int`, `STATS`, `TRACE`.
  - `abstract class RakuObject : SixModelObject()` with `@JvmField var layout: RakuObjectLayout?`, `oExt: Array<Any?>?`, `lExt: LongArray?`, abstract `refAt(i)/refSet(i,v)/longAt(i)/longSet(i,v)`, and the six finals `RakuObject4`, `RakuObject8`, `RakuObject16`, `RakuObject4L`, `RakuObject8L`, `RakuObject16L` (fields `o0..oN: Any?`, `l0`, `l1: Long`).
  - `class RakuObjectREPRData` with `@JvmField var layout: RakuObjectLayout?`, `variants: HashMap<Class<*>, RakuObjectLayout>?`, `intCache: Array<SixModelObject?>?`; `fun layoutFor(cls: Class<*>): RakuObjectLayout`.
  - `class RakuObjectREPR : REPR()` registered as `"P6opaque"`.
  - `REPR.inlinedKind(): SlotKind?`; `REPR.deserialize_stub(tc, st, reader)`.
  - `SerializationReader.peekAttributeShape(st): IntArray?` (`[refs, longs]` or null when the STable's REPR data is already read or belongs to another SC).

- [ ] **Step 1: `RakuObjectLayout.kt`.** The layout, the static handle tables, the diagnostics:

```kotlin
package org.raku.nqp.sixmodel.reprs

import it.unimi.dsi.fastutil.objects.Object2IntOpenHashMap
import java.lang.invoke.MethodHandle
import java.lang.invoke.MethodHandles
import java.lang.invoke.MethodType
import java.lang.invoke.VarHandle
import java.util.ArrayList
import org.raku.nqp.sixmodel.STable
import org.raku.nqp.sixmodel.SixModelObject
import org.raku.nqp.sixmodel.StorageSpec

/** What one attribute slot holds. INT and NUM live in long slots (a num as
 *  its raw bits); the rest are references. */
enum class SlotKind { REF, INT, NUM, STR, BIGINT, NCBODY }

/**
 * The layout of a RakuObject type: for every abstract slot (the hint, per
 * STable, parents first) its kind and its placement on one of the six
 * storage classes -- an inline field when the slot number within its
 * family is below the class's capacity, an overflow array element after.
 * Immutable; one per STable from its single REPR composition or from its
 * serialized REPR data, plus a variant per storage class an object was
 * reblessed on while too small for the canonical class. A fast site guards
 * on the layout's identity and reads through a constant handle from the
 * static tables below.
 */
class RakuObjectLayout(
    @JvmField val st: STable,
    @JvmField val classId: Int,
    @JvmField val kinds: Array<SlotKind>,
    @JvmField val specs: Array<StorageSpec?>,
    @JvmField val slotSTables: Array<STable?>,
    @JvmField val autoViv: Array<SixModelObject?>,
    @JvmField val classHandles: Array<SixModelObject?>,
    @JvmField val nameToSlot: ArrayList<Object2IntOpenHashMap<String>>,
    @JvmField val mi: Boolean,
    @JvmField val unboxIntSlot: Int,
    @JvmField val unboxNumSlot: Int,
    @JvmField val unboxStrSlot: Int,
    @JvmField val unboxObjSlot: Int,
    @JvmField val posDelSlot: Int,
    @JvmField val assDelSlot: Int,
    @JvmField val variant: Boolean,
) {
    @JvmField val storage: Class<out RakuObject> = CLASSES[classId]
    @JvmField val refCap: Int = REF_CAPS[classId]
    @JvmField val longCap: Int = LONG_CAPS[classId]
    /** Per slot: the index within its family (reference or long). */
    @JvmField val index: IntArray = IntArray(kinds.size)
    @JvmField val refCount: Int
    @JvmField val longCount: Int
    @JvmField val oExtSize: Int
    @JvmField val lExtSize: Int

    init {
        var r = 0; var l = 0
        for (i in kinds.indices) {
            if (isLongKind(i)) { index[i] = l++ } else { index[i] = r++ }
        }
        refCount = r; longCount = l
        oExtSize = maxOf(0, r - refCap)
        lExtSize = maxOf(0, l - longCap)
        if (unboxIntSlot >= 0 && kinds[unboxIntSlot] != SlotKind.INT && kinds[unboxIntSlot] != SlotKind.BIGINT)
            throw IllegalStateException("RakuObject layout of ${st.debugName}: int box target slot $unboxIntSlot is ${kinds[unboxIntSlot]}")
        if (unboxNumSlot >= 0 && kinds[unboxNumSlot] != SlotKind.NUM)
            throw IllegalStateException("RakuObject layout of ${st.debugName}: num box target slot $unboxNumSlot is ${kinds[unboxNumSlot]}")
        if (unboxStrSlot >= 0 && kinds[unboxStrSlot] != SlotKind.STR)
            throw IllegalStateException("RakuObject layout of ${st.debugName}: str box target slot $unboxStrSlot is ${kinds[unboxStrSlot]}")
        if (STATS) { if (variant) VARIANTS.incrementAndGet() else LAYOUTS.incrementAndGet() }
        if (TRACE) System.err.println("layout: " + (if (variant) "variant " else "") + st.debugName
            + " class=" + storage.simpleName + " slots=" + kinds.joinToString(",") + " refs=$r longs=$l")
    }

    fun kindOf(slot: Int): SlotKind = kinds[slot]
    fun isLongKind(slot: Int): Boolean { val k = kinds[slot]; return k == SlotKind.INT || k == SlotKind.NUM }

    /** The slot of an attribute, or -1. */
    fun slotFor(classHandle: SixModelObject?, name: String?): Int {
        for (i in classHandles.indices) {
            if (classHandles[i] === classHandle)
                return nameToSlot[i].getOrDefault(name, -1)
        }
        return -1
    }

    /** The slot by name alone, searching every class handle; -1 if none. */
    fun slotForName(name: String): Int {
        for (m in nameToSlot) { val s = m.getOrDefault(name, -1); if (s != -1) return s }
        return -1
    }

    /** The slot, or the old "No such attribute" error with the known-attribute dump. */
    fun resolve(classHandle: SixModelObject?, name: String?): Int {
        val slot = slotFor(classHandle, name)
        if (slot >= 0) return slot
        val known = StringBuilder()
        for (i in classHandles.indices) {
            known.append(if (i == 0) " [" else "; ")
            known.append(classHandles[i]?.st?.debugName)
            known.append(": ")
            known.append(nameToSlot[i].keys.joinToString(","))
        }
        if (classHandles.isNotEmpty()) known.append("]")
        throw RuntimeException("No such attribute '$name' for this object" +
            " (looked in ${classHandle?.st?.debugName}; has$known)")
    }

    /* ----- slot access by placement (the slow road; the sites use handles) ----- */

    fun getRef(o: RakuObject, slot: Int): Any? {
        val i = index[slot]
        return if (i < refCap) o.refAt(i) else o.oExt!![i - refCap]
    }
    fun setRef(o: RakuObject, slot: Int, v: Any?) {
        val i = index[slot]
        if (i < refCap) o.refSet(i, v) else o.oExt!![i - refCap] = v
    }
    fun getLong(o: RakuObject, slot: Int): Long {
        val i = index[slot]
        return if (i < longCap) o.longAt(i) else o.lExt!![i - longCap]
    }
    fun setLong(o: RakuObject, slot: Int, v: Long) {
        val i = index[slot]
        if (i < longCap) o.longSet(i, v) else o.lExt!![i - longCap] = v
    }

    /* ----- atomics: a VarHandle per placement ----- */

    fun getVolatile(o: RakuObject, slot: Int): Any? {
        val i = index[slot]
        return if (i < refCap) REF_VH[classId][i].getVolatile(o) else ARRAY_VH.getVolatile(o.oExt, i - refCap)
    }
    fun setVolatile(o: RakuObject, slot: Int, v: Any?) {
        val i = index[slot]
        if (i < refCap) REF_VH[classId][i].setVolatile(o, v) else ARRAY_VH.setVolatile(o.oExt, i - refCap, v)
    }
    fun compareAndSet(o: RakuObject, slot: Int, expected: Any?, v: Any?): Boolean {
        val i = index[slot]
        return if (i < refCap) REF_VH[classId][i].compareAndSet(o, expected, v)
               else ARRAY_VH.compareAndSet(o.oExt, i - refCap, expected, v)
    }

    /* ----- constant handles for the fast sites ----- */

    /** (SixModelObject)Object: the reference slot's field or overflow element. */
    fun refGetter(slot: Int): MethodHandle {
        val i = index[slot]
        return if (i < refCap) REF_GET[classId][i]
               else MethodHandles.filterArguments(MethodHandles.insertArguments(ARRAY_GET, 1, i - refCap), 0, OEXT_GET)
                        .asType(MethodType.methodType(Any::class.java, SixModelObject::class.java))
    }
    /** (SixModelObject,Object)void. */
    fun refSetter(slot: Int): MethodHandle {
        val i = index[slot]
        return if (i < refCap) REF_SET[classId][i]
               else MethodHandles.filterArguments(MethodHandles.insertArguments(ARRAY_SET, 1, i - refCap), 0, OEXT_GET)
                        .asType(MethodType.methodType(Void.TYPE, SixModelObject::class.java, Any::class.java))
    }
    /** (SixModelObject)long. */
    fun longGetter(slot: Int): MethodHandle {
        val i = index[slot]
        return if (i < longCap) LONG_GET[classId][i]
               else MethodHandles.filterArguments(MethodHandles.insertArguments(LARRAY_GET, 1, i - longCap), 0, LEXT_GET)
                        .asType(MethodType.methodType(java.lang.Long.TYPE, SixModelObject::class.java))
    }
    /** (SixModelObject,long)void. */
    fun longSetter(slot: Int): MethodHandle {
        val i = index[slot]
        return if (i < longCap) LONG_SET[classId][i]
               else MethodHandles.filterArguments(MethodHandles.insertArguments(LARRAY_SET, 1, i - longCap), 0, LEXT_GET)
                        .asType(MethodType.methodType(Void.TYPE, SixModelObject::class.java, java.lang.Long.TYPE))
    }

    /* ----- allocation ----- */

    /** A fresh instance of this layout's class, with its layout set and its
     *  overflow arrays sized. A `when` on a constant classId folds under PE
     *  to one allocation. */
    fun newInstance(): RakuObject {
        val o: RakuObject = when (classId) {
            0 -> RakuObject4()
            1 -> RakuObject8()
            2 -> RakuObject16()
            3 -> RakuObject4L()
            4 -> RakuObject8L()
            else -> RakuObject16L()
        }
        o.st = st
        o.layout = this
        if (oExtSize > 0) o.oExt = arrayOfNulls(oExtSize)
        if (lExtSize > 0) o.lExt = LongArray(lExtSize)
        return o
    }

    /** Grow an existing object's overflow arrays to this layout's sizes,
     *  keeping every value in place (rebless). */
    fun growExt(o: RakuObject) {
        if (oExtSize > 0) {
            val old = o.oExt
            if (old == null) o.oExt = arrayOfNulls(oExtSize)
            else if (old.size < oExtSize) o.oExt = old.copyOf(oExtSize)
        }
        if (lExtSize > 0) {
            val old = o.lExt
            if (old == null) o.lExt = LongArray(lExtSize)
            else if (old.size < lExtSize) o.lExt = old.copyOf(lExtSize)
        }
    }

    companion object {
        @JvmField val CLASSES: Array<Class<out RakuObject>> = arrayOf(
            RakuObject4::class.java, RakuObject8::class.java, RakuObject16::class.java,
            RakuObject4L::class.java, RakuObject8L::class.java, RakuObject16L::class.java)
        @JvmField val REF_CAPS = intArrayOf(4, 8, 16, 4, 8, 16)
        @JvmField val LONG_CAPS = intArrayOf(0, 0, 0, 2, 2, 2)

        /** The smallest class holding the counts inline; 16 refs / 2 longs
         *  when nothing does (the rest overflows). */
        @JvmStatic
        fun chooseClass(refs: Int, longs: Int): Int {
            val r = if (refs <= 4) 0 else if (refs <= 8) 1 else 2
            return if (longs == 0) r else r + 3
        }

        @JvmStatic
        fun classIdOf(cls: Class<*>): Int {
            for (i in CLASSES.indices) if (CLASSES[i] == cls) return i
            throw IllegalStateException("not a RakuObject storage class: " + cls.name)
        }

        private val LOOKUP = MethodHandles.lookup()
        private val SMO_GET = MethodType.methodType(Any::class.java, SixModelObject::class.java)
        private val SMO_SET = MethodType.methodType(Void.TYPE, SixModelObject::class.java, Any::class.java)
        private val SMO_LGET = MethodType.methodType(java.lang.Long.TYPE, SixModelObject::class.java)
        private val SMO_LSET = MethodType.methodType(Void.TYPE, SixModelObject::class.java, java.lang.Long.TYPE)

        @JvmField val REF_GET: Array<Array<MethodHandle>> = Array(CLASSES.size) { c ->
            Array(REF_CAPS[c]) { i -> LOOKUP.findGetter(CLASSES[c], "o$i", Any::class.java).asType(SMO_GET) } }
        @JvmField val REF_SET: Array<Array<MethodHandle>> = Array(CLASSES.size) { c ->
            Array(REF_CAPS[c]) { i -> LOOKUP.findSetter(CLASSES[c], "o$i", Any::class.java).asType(SMO_SET) } }
        @JvmField val LONG_GET: Array<Array<MethodHandle>> = Array(CLASSES.size) { c ->
            Array(LONG_CAPS[c]) { i -> LOOKUP.findGetter(CLASSES[c], "l$i", java.lang.Long.TYPE).asType(SMO_LGET) } }
        @JvmField val LONG_SET: Array<Array<MethodHandle>> = Array(CLASSES.size) { c ->
            Array(LONG_CAPS[c]) { i -> LOOKUP.findSetter(CLASSES[c], "l$i", java.lang.Long.TYPE).asType(SMO_LSET) } }
        @JvmField val REF_VH: Array<Array<VarHandle>> = Array(CLASSES.size) { c ->
            Array(REF_CAPS[c]) { i -> LOOKUP.findVarHandle(CLASSES[c], "o$i", Any::class.java) } }
        @JvmField val ARRAY_VH: VarHandle = MethodHandles.arrayElementVarHandle(Array<Any?>::class.java)
        private val OEXT_GET: MethodHandle = LOOKUP.findGetter(RakuObject::class.java, "oExt", Array<Any?>::class.java)
        private val LEXT_GET: MethodHandle = LOOKUP.findGetter(RakuObject::class.java, "lExt", LongArray::class.java)
        private val ARRAY_GET: MethodHandle = MethodHandles.arrayElementGetter(Array<Any?>::class.java)
        private val ARRAY_SET: MethodHandle = MethodHandles.arrayElementSetter(Array<Any?>::class.java)
        private val LARRAY_GET: MethodHandle = MethodHandles.arrayElementGetter(LongArray::class.java)
        private val LARRAY_SET: MethodHandle = MethodHandles.arrayElementSetter(LongArray::class.java)

        /** NQP_LAYOUT_STATS=1: layouts, variants at exit. NQP_LAYOUT_TRACE=1: each creation and rebless. */
        @JvmField val STATS: Boolean = System.getenv("NQP_LAYOUT_STATS") != null
        @JvmField val TRACE: Boolean = System.getenv("NQP_LAYOUT_TRACE") != null
        @JvmField val LAYOUTS = java.util.concurrent.atomic.AtomicLong()
        @JvmField val VARIANTS = java.util.concurrent.atomic.AtomicLong()
        @JvmField val REBLESSES = java.util.concurrent.atomic.AtomicLong()

        init {
            if (STATS) Runtime.getRuntime().addShutdownHook(Thread {
                System.err.println("layout stats: layouts=" + LAYOUTS.get() + " variants=" + VARIANTS.get()
                    + " reblesses=" + REBLESSES.get())
            })
        }
    }
}
```

- [ ] **Step 2: `RakuObject.kt`.** The base and the six classes:

```kotlin
package org.raku.nqp.sixmodel.reprs

import org.raku.nqp.runtime.ExceptionHandling
import org.raku.nqp.runtime.Ops
import org.raku.nqp.runtime.ThreadContext
import org.raku.nqp.sixmodel.SixModelObject
import org.raku.nqp.sixmodel.TypeObject

/**
 * A P6opaque-REPR object: inline reference and long fields on one of six
 * concrete classes, overflow arrays past them, and the layout that says
 * which slot lives where. No delegate: a mixin grows the object in place.
 * Never overrides hashCode/equals (nqp::objectid is Object.hashCode).
 */
abstract class RakuObject : SixModelObject() {
    /** Read raw by the fast sites; null only on a deserialization stub
     *  before its finish. */
    @JvmField var layout: RakuObjectLayout? = null
    @JvmField var oExt: Array<Any?>? = null
    @JvmField var lExt: LongArray? = null

    abstract fun refAt(i: Int): Any?
    abstract fun refSet(i: Int, v: Any?)
    abstract fun longAt(i: Int): Long
    abstract fun longSet(i: Int, v: Long)

    private fun lay(tc: ThreadContext): RakuObjectLayout =
        layout ?: throw ExceptionHandling.dieInternal(tc, "RakuObject of " + st.debugName + " has no layout (a deserialization stub before its finish?)")

    /** The slot for an access: the hint when the caller trusts it, else by name. */
    private fun slot(tc: ThreadContext, l: RakuObjectLayout, classHandle: SixModelObject?, name: String?, hint: Long): Int =
        if (hint >= 0L && hint < l.kinds.size) hint.toInt() else l.resolve(classHandle, name)

    fun autoViv(l: RakuObjectLayout, slot: Int, tc: ThreadContext): SixModelObject? {
        val av = l.autoViv[slot]
        if (av == null || Ops.isnull(av) == 1L) return null
        val v: SixModelObject = if (av is TypeObject) av else av.clone(tc)
        l.setRef(this, slot, v)
        return v
    }

    /* ----- the attribute API ----- */

    override fun get_attribute_boxed(tc: ThreadContext, classHandle: SixModelObject?, name: String?, hint: Long): SixModelObject? {
        val l = lay(tc)
        val s = slot(tc, l, classHandle, name, hint)
        if (l.kinds[s] != SlotKind.REF)
            throw ExceptionHandling.dieInternal(tc, "Cannot access a native attribute as a reference attribute")
        return (l.getRef(this, s) as SixModelObject?) ?: autoViv(l, s, tc)
    }

    override fun get_attribute_native(tc: ThreadContext, classHandle: SixModelObject?, name: String?, hint: Long) {
        val l = lay(tc)
        val s = slot(tc, l, classHandle, name, hint)
        when (l.kinds[s]) {
            SlotKind.INT -> { tc.nativeType = ThreadContext.NATIVE_INT; tc.nativeI = l.getLong(this, s) }
            SlotKind.NUM -> { tc.nativeType = ThreadContext.NATIVE_NUM; tc.nativeN = java.lang.Double.longBitsToDouble(l.getLong(this, s)) }
            SlotKind.STR -> { tc.nativeType = ThreadContext.NATIVE_STR; tc.nativeS = l.getRef(this, s) as String? }
            SlotKind.BIGINT, SlotKind.NCBODY -> { tc.nativeType = ThreadContext.NATIVE_JVM_OBJ; tc.nativeJ = l.getRef(this, s) }
            SlotKind.REF -> throw ExceptionHandling.dieInternal(tc, "Cannot access a reference attribute as a native attribute")
        }
    }

    override fun bind_attribute_boxed(tc: ThreadContext, classHandle: SixModelObject?, name: String?, hint: Long, value: SixModelObject?) {
        val l = lay(tc)
        val s = slot(tc, l, classHandle, name, hint)
        if (l.kinds[s] != SlotKind.REF)
            throw ExceptionHandling.dieInternal(tc, "Cannot access a native attribute as a reference attribute")
        l.setRef(this, s, value)
    }

    override fun bind_attribute_native(tc: ThreadContext, classHandle: SixModelObject?, name: String?, hint: Long) {
        val l = lay(tc)
        val s = slot(tc, l, classHandle, name, hint)
        when (l.kinds[s]) {
            SlotKind.INT -> { tc.nativeType = ThreadContext.NATIVE_INT; l.setLong(this, s, P6int.sizedValue(l.specs[s], tc.nativeI)) }
            SlotKind.NUM -> { tc.nativeType = ThreadContext.NATIVE_NUM; l.setLong(this, s, java.lang.Double.doubleToRawLongBits(tc.nativeN)) }
            SlotKind.STR -> { tc.nativeType = ThreadContext.NATIVE_STR; l.setRef(this, s, tc.nativeS) }
            SlotKind.BIGINT -> { tc.nativeType = ThreadContext.NATIVE_JVM_OBJ; l.setRef(this, s, tc.nativeJ as java.math.BigInteger?) }
            SlotKind.NCBODY -> { tc.nativeType = ThreadContext.NATIVE_JVM_OBJ; l.setRef(this, s, tc.nativeJ as NativeCallBody?) }
            SlotKind.REF -> throw ExceptionHandling.dieInternal(tc, "Cannot access a reference attribute as a native attribute")
        }
    }

    override fun is_attribute_initialized(tc: ThreadContext, classHandle: SixModelObject?, name: String?, hint: Long): Long {
        val l = lay(tc)
        val s = slot(tc, l, classHandle, name, hint)
        return if (l.kinds[s] == SlotKind.REF) (if (l.getRef(this, s) != null || autoViv(l, s, tc) != null) 1L else 0L) else 1L
    }

    /* ----- atomics ----- */

    override fun cas_attribute_boxed(tc: ThreadContext, classHandle: SixModelObject?, name: String?,
                                     expected: SixModelObject?, value: SixModelObject?): SixModelObject? {
        val l = lay(tc)
        val s = l.resolve(classHandle, name)
        return if (l.compareAndSet(this, s, expected, value)) expected else l.getVolatile(this, s) as SixModelObject?
    }

    override fun atomic_bind_attribute_boxed(tc: ThreadContext, classHandle: SixModelObject?, name: String?, value: SixModelObject?) {
        val l = lay(tc)
        l.setVolatile(this, l.resolve(classHandle, name), value)
    }

    /* ----- boxing through the unbox slots (what generateBoxingMethods emitted) ----- */

    private fun unboxSlot(tc: ThreadContext, slot: Int, what: String): Int {
        if (slot < 0) throw ExceptionHandling.dieInternal(tc, "This type (" + st.debugName + ") cannot box a native " + what)
        return slot
    }

    override fun set_int(tc: ThreadContext, value: Long) {
        val l = lay(tc); val s = unboxSlot(tc, l.unboxIntSlot, "integer")
        if (l.kinds[s] == SlotKind.BIGINT) l.setRef(this, s, java.math.BigInteger.valueOf(value))
        else l.setLong(this, s, P6int.sizedValue(l.specs[s], value))
    }
    override fun set_uint(tc: ThreadContext, value: Long) {
        val l = lay(tc); val s = unboxSlot(tc, l.unboxIntSlot, "integer")
        if (l.kinds[s] == SlotKind.BIGINT) l.setRef(this, s, P6bigint.unsignedValueOf(value))
        else l.setLong(this, s, P6int.sizedValue(l.specs[s], value))
    }
    override fun get_int(tc: ThreadContext): Long {
        val l = lay(tc); val s = unboxSlot(tc, l.unboxIntSlot, "integer")
        return if (l.kinds[s] == SlotKind.BIGINT) P6bigint.checkedLongValue(l.getRef(this, s) as java.math.BigInteger)
               else l.getLong(this, s)
    }
    override fun get_uint(tc: ThreadContext): Long {
        val l = lay(tc); val s = unboxSlot(tc, l.unboxIntSlot, "integer")
        return if (l.kinds[s] == SlotKind.BIGINT) P6bigint.uncheckedLongValue(l.getRef(this, s) as java.math.BigInteger)
               else l.getLong(this, s)
    }
    override fun set_num(tc: ThreadContext, value: Double) {
        val l = lay(tc); l.setLong(this, unboxSlot(tc, l.unboxNumSlot, "number"), java.lang.Double.doubleToRawLongBits(value))
    }
    override fun get_num(tc: ThreadContext): Double {
        val l = lay(tc); return java.lang.Double.longBitsToDouble(l.getLong(this, unboxSlot(tc, l.unboxNumSlot, "number")))
    }
    override fun set_str(tc: ThreadContext, value: String?) {
        val l = lay(tc); l.setRef(this, unboxSlot(tc, l.unboxStrSlot, "string"), value)
    }
    override fun get_str(tc: ThreadContext): String? {
        val l = lay(tc); return l.getRef(this, unboxSlot(tc, l.unboxStrSlot, "string")) as String?
    }
    override fun set_boxing_of(tc: ThreadContext, reprId: Long, value: Any?) {
        val l = lay(tc)
        if (l.unboxObjSlot < 0 || l.kinds[l.unboxObjSlot] != SlotKind.NCBODY) super.set_boxing_of(tc, reprId, value)
        else l.setRef(this, l.unboxObjSlot, value as NativeCallBody?)
    }
    override fun get_boxing_of(tc: ThreadContext, reprId: Long): Any? {
        val l = lay(tc)
        if (l.unboxObjSlot < 0 || l.kinds[l.unboxObjSlot] != SlotKind.NCBODY) return super.get_boxing_of(tc, reprId)
        return l.getRef(this, l.unboxObjSlot)
    }

    /* ----- clone ----- */

    override fun clone(tc: ThreadContext): SixModelObject {
        val c = super.clone() as RakuObject
        c.sc = null
        c.oExt = oExt?.clone()
        c.lExt = lExt?.clone()
        return c
    }

    /* ----- positional / associative delegation ----- */

    fun posDelegate(): SixModelObject {
        val l = layout
        if (l != null && l.posDelSlot >= 0) return l.getRef(this, l.posDelSlot) as SixModelObject
        throw RuntimeException("This type does not support positional operations")
    }
    fun assDelegate(): SixModelObject {
        val l = layout
        if (l != null && l.assDelSlot >= 0) return l.getRef(this, l.assDelSlot) as SixModelObject
        throw RuntimeException("This type does not support associative operations")
    }
    override fun elems(tc: ThreadContext): Long = posDelegate().elems(tc)
    override fun at_pos_boxed(tc: ThreadContext, index: Long): SixModelObject? = posDelegate().at_pos_boxed(tc, index)
    override fun at_pos_native(tc: ThreadContext, index: Long) = posDelegate().at_pos_native(tc, index)
    override fun bind_pos_boxed(tc: ThreadContext, index: Long, value: SixModelObject?) = posDelegate().bind_pos_boxed(tc, index, value)
    override fun bind_pos_native(tc: ThreadContext, index: Long) = posDelegate().bind_pos_native(tc, index)
    override fun set_elems(tc: ThreadContext, count: Long) = posDelegate().set_elems(tc, count)
    override fun push_boxed(tc: ThreadContext, value: SixModelObject?) = posDelegate().push_boxed(tc, value)
    override fun push_native(tc: ThreadContext) = posDelegate().push_native(tc)
    override fun pop_boxed(tc: ThreadContext): SixModelObject? = posDelegate().pop_boxed(tc)
    override fun pop_native(tc: ThreadContext) = posDelegate().pop_native(tc)
    override fun unshift_boxed(tc: ThreadContext, value: SixModelObject?) = posDelegate().unshift_boxed(tc, value)
    override fun unshift_native(tc: ThreadContext) = posDelegate().unshift_native(tc)
    override fun shift_boxed(tc: ThreadContext): SixModelObject? = posDelegate().shift_boxed(tc)
    override fun shift_native(tc: ThreadContext) = posDelegate().shift_native(tc)
    override fun slice(tc: ThreadContext, dest: SixModelObject, beginning: Long, end: Long): SixModelObject? = posDelegate().slice(tc, dest, beginning, end)
    override fun splice(tc: ThreadContext, from: SixModelObject, offset: Long, count: Long) = posDelegate().splice(tc, from, offset, count)
    override fun at_key_boxed(tc: ThreadContext, key: String?): SixModelObject? = assDelegate().at_key_boxed(tc, key)
    override fun bind_key_boxed(tc: ThreadContext, key: String?, value: SixModelObject?) = assDelegate().bind_key_boxed(tc, key, value)
    override fun exists_key(tc: ThreadContext, key: String?): Long = assDelegate().exists_key(tc, key)
    override fun delete_key(tc: ThreadContext, key: String?) = assDelegate().delete_key(tc, key)
}

/* The six storage classes. Field declarations only; the when-switches are
 * the slow road (the sites read the fields through constant handles). */

class RakuObject4 : RakuObject() {
    @JvmField var o0: Any? = null; @JvmField var o1: Any? = null; @JvmField var o2: Any? = null; @JvmField var o3: Any? = null
    override fun refAt(i: Int): Any? = when (i) { 0 -> o0; 1 -> o1; 2 -> o2; else -> o3 }
    override fun refSet(i: Int, v: Any?) { when (i) { 0 -> o0 = v; 1 -> o1 = v; 2 -> o2 = v; else -> o3 = v } }
    override fun longAt(i: Int): Long = throw IllegalStateException("RakuObject4 has no long slots")
    override fun longSet(i: Int, v: Long) = throw IllegalStateException("RakuObject4 has no long slots")
}

class RakuObject4L : RakuObject() {
    @JvmField var o0: Any? = null; @JvmField var o1: Any? = null; @JvmField var o2: Any? = null; @JvmField var o3: Any? = null
    @JvmField var l0: Long = 0L; @JvmField var l1: Long = 0L
    override fun refAt(i: Int): Any? = when (i) { 0 -> o0; 1 -> o1; 2 -> o2; else -> o3 }
    override fun refSet(i: Int, v: Any?) { when (i) { 0 -> o0 = v; 1 -> o1 = v; 2 -> o2 = v; else -> o3 = v } }
    override fun longAt(i: Int): Long = if (i == 0) l0 else l1
    override fun longSet(i: Int, v: Long) { if (i == 0) l0 = v else l1 = v }
}

class RakuObject8 : RakuObject() {
    @JvmField var o0: Any? = null; @JvmField var o1: Any? = null; @JvmField var o2: Any? = null; @JvmField var o3: Any? = null
    @JvmField var o4: Any? = null; @JvmField var o5: Any? = null; @JvmField var o6: Any? = null; @JvmField var o7: Any? = null
    override fun refAt(i: Int): Any? = when (i) { 0 -> o0; 1 -> o1; 2 -> o2; 3 -> o3; 4 -> o4; 5 -> o5; 6 -> o6; else -> o7 }
    override fun refSet(i: Int, v: Any?) { when (i) { 0 -> o0 = v; 1 -> o1 = v; 2 -> o2 = v; 3 -> o3 = v; 4 -> o4 = v; 5 -> o5 = v; 6 -> o6 = v; else -> o7 = v } }
    override fun longAt(i: Int): Long = throw IllegalStateException("RakuObject8 has no long slots")
    override fun longSet(i: Int, v: Long) = throw IllegalStateException("RakuObject8 has no long slots")
}

class RakuObject8L : RakuObject() {
    @JvmField var o0: Any? = null; @JvmField var o1: Any? = null; @JvmField var o2: Any? = null; @JvmField var o3: Any? = null
    @JvmField var o4: Any? = null; @JvmField var o5: Any? = null; @JvmField var o6: Any? = null; @JvmField var o7: Any? = null
    @JvmField var l0: Long = 0L; @JvmField var l1: Long = 0L
    override fun refAt(i: Int): Any? = when (i) { 0 -> o0; 1 -> o1; 2 -> o2; 3 -> o3; 4 -> o4; 5 -> o5; 6 -> o6; else -> o7 }
    override fun refSet(i: Int, v: Any?) { when (i) { 0 -> o0 = v; 1 -> o1 = v; 2 -> o2 = v; 3 -> o3 = v; 4 -> o4 = v; 5 -> o5 = v; 6 -> o6 = v; else -> o7 = v } }
    override fun longAt(i: Int): Long = if (i == 0) l0 else l1
    override fun longSet(i: Int, v: Long) { if (i == 0) l0 = v else l1 = v }
}

class RakuObject16 : RakuObject() {
    @JvmField var o0: Any? = null; @JvmField var o1: Any? = null; @JvmField var o2: Any? = null; @JvmField var o3: Any? = null
    @JvmField var o4: Any? = null; @JvmField var o5: Any? = null; @JvmField var o6: Any? = null; @JvmField var o7: Any? = null
    @JvmField var o8: Any? = null; @JvmField var o9: Any? = null; @JvmField var o10: Any? = null; @JvmField var o11: Any? = null
    @JvmField var o12: Any? = null; @JvmField var o13: Any? = null; @JvmField var o14: Any? = null; @JvmField var o15: Any? = null
    override fun refAt(i: Int): Any? = when (i) {
        0 -> o0; 1 -> o1; 2 -> o2; 3 -> o3; 4 -> o4; 5 -> o5; 6 -> o6; 7 -> o7
        8 -> o8; 9 -> o9; 10 -> o10; 11 -> o11; 12 -> o12; 13 -> o13; 14 -> o14; else -> o15 }
    override fun refSet(i: Int, v: Any?) { when (i) {
        0 -> o0 = v; 1 -> o1 = v; 2 -> o2 = v; 3 -> o3 = v; 4 -> o4 = v; 5 -> o5 = v; 6 -> o6 = v; 7 -> o7 = v
        8 -> o8 = v; 9 -> o9 = v; 10 -> o10 = v; 11 -> o11 = v; 12 -> o12 = v; 13 -> o13 = v; 14 -> o14 = v; else -> o15 = v } }
    override fun longAt(i: Int): Long = throw IllegalStateException("RakuObject16 has no long slots")
    override fun longSet(i: Int, v: Long) = throw IllegalStateException("RakuObject16 has no long slots")
}

class RakuObject16L : RakuObject() {
    @JvmField var o0: Any? = null; @JvmField var o1: Any? = null; @JvmField var o2: Any? = null; @JvmField var o3: Any? = null
    @JvmField var o4: Any? = null; @JvmField var o5: Any? = null; @JvmField var o6: Any? = null; @JvmField var o7: Any? = null
    @JvmField var o8: Any? = null; @JvmField var o9: Any? = null; @JvmField var o10: Any? = null; @JvmField var o11: Any? = null
    @JvmField var o12: Any? = null; @JvmField var o13: Any? = null; @JvmField var o14: Any? = null; @JvmField var o15: Any? = null
    @JvmField var l0: Long = 0L; @JvmField var l1: Long = 0L
    override fun refAt(i: Int): Any? = when (i) {
        0 -> o0; 1 -> o1; 2 -> o2; 3 -> o3; 4 -> o4; 5 -> o5; 6 -> o6; 7 -> o7
        8 -> o8; 9 -> o9; 10 -> o10; 11 -> o11; 12 -> o12; 13 -> o13; 14 -> o14; else -> o15 }
    override fun refSet(i: Int, v: Any?) { when (i) {
        0 -> o0 = v; 1 -> o1 = v; 2 -> o2 = v; 3 -> o3 = v; 4 -> o4 = v; 5 -> o5 = v; 6 -> o6 = v; 7 -> o7 = v
        8 -> o8 = v; 9 -> o9 = v; 10 -> o10 = v; 11 -> o11 = v; 12 -> o12 = v; 13 -> o13 = v; 14 -> o14 = v; else -> o15 = v } }
    override fun longAt(i: Int): Long = if (i == 0) l0 else l1
    override fun longSet(i: Int, v: Long) { if (i == 0) l0 = v else l1 = v }
}
```

`SixModelObject.st` is `lateinit`; `RakuObject`'s own reads of `st` here are on slow roads (error messages). The fast sites read `NqpRaw.st(o)` as today.

- [ ] **Step 3: `RakuObjectREPRData.kt`:**

```kotlin
package org.raku.nqp.sixmodel.reprs

import java.util.HashMap
import org.raku.nqp.sixmodel.SixModelObject

class RakuObjectREPRData {
    /** The canonical layout, from compose or from the serialized REPR data;
     *  null until then (an uncomposed type answers NO_HINT). */
    @JvmField var layout: RakuObjectLayout? = null

    /** Layouts for objects reblessed into this type while on a smaller
     *  storage class than the canonical one, by that class. */
    @JvmField var variants: HashMap<Class<*>, RakuObjectLayout>? = null

    /** jesp: shared boxed instances of this type for small integer values,
     *  filled on demand by the engine's bigint arithmetic site when
     *  JESP_INTCACHE is set; null otherwise. */
    @JvmField var intCache: Array<SixModelObject?>? = null

    /** The layout for an object of the given storage class: the canonical
     *  one when the classes match, else the variant for that class (built
     *  once). */
    fun layoutFor(cls: Class<*>): RakuObjectLayout {
        val canonical = layout ?: throw IllegalStateException("type not composed")
        if (canonical.storage == cls) return canonical
        var vs = variants
        if (vs == null) { vs = HashMap(); variants = vs }
        return vs.getOrPut(cls) {
            RakuObjectLayout(canonical.st, RakuObjectLayout.classIdOf(cls), canonical.kinds, canonical.specs,
                canonical.slotSTables, canonical.autoViv, canonical.classHandles, canonical.nameToSlot, canonical.mi,
                canonical.unboxIntSlot, canonical.unboxNumSlot, canonical.unboxStrSlot, canonical.unboxObjSlot,
                canonical.posDelSlot, canonical.assDelSlot, variant = true)
        }
    }
}
```

- [ ] **Step 4: `RakuObjectREPR.kt`** (replaces `P6Opaque.kt`; `compose`, `deserialize_repr_data` and `serialize_repr_data` keep the exact loop structure and wire order of the old code):

```kotlin
package org.raku.nqp.sixmodel.reprs

import it.unimi.dsi.fastutil.objects.Object2IntOpenHashMap
import java.util.ArrayList
import org.raku.nqp.runtime.ExceptionHandling
import org.raku.nqp.runtime.Ops
import org.raku.nqp.runtime.ThreadContext
import org.raku.nqp.sixmodel.Boxable
import org.raku.nqp.sixmodel.BoxedPrimitive
import org.raku.nqp.sixmodel.REPR
import org.raku.nqp.sixmodel.STable
import org.raku.nqp.sixmodel.SerializationReader
import org.raku.nqp.sixmodel.SerializationWriter
import org.raku.nqp.sixmodel.SixModelObject
import org.raku.nqp.sixmodel.StorageSpec
import org.raku.nqp.sixmodel.TypeObject

/** The P6opaque representation on the JVM: objects are RakuObjects laid
 *  out by a RakuObjectLayout. Registered under the name "P6opaque". */
class RakuObjectREPR : REPR() {

    override fun type_object_for(tc: ThreadContext, HOW: SixModelObject?): SixModelObject {
        val st = STable(this, HOW)
        st.REPRData = RakuObjectREPRData()
        val obj = TypeObject()
        obj.st = st
        st.WHAT = obj
        return st.WHAT
    }

    /** Builds the canonical layout from the per-slot lists compose and
     *  deserialize_repr_data both produce. */
    private fun install(st: STable, rd: RakuObjectREPRData, kinds: ArrayList<SlotKind>, specs: ArrayList<StorageSpec?>,
                        slotSTables: ArrayList<STable?>, autoViv: Array<SixModelObject?>, classHandles: Array<SixModelObject?>,
                        nameToSlot: ArrayList<Object2IntOpenHashMap<String>>, mi: Boolean,
                        unboxInt: Int, unboxNum: Int, unboxStr: Int, unboxObj: Int, posDel: Int, assDel: Int) {
        var refs = 0; var longs = 0
        for (k in kinds) if (k == SlotKind.INT || k == SlotKind.NUM) longs++ else refs++
        rd.layout = RakuObjectLayout(st, RakuObjectLayout.chooseClass(refs, longs), kinds.toTypedArray(),
            specs.toTypedArray(), slotSTables.toTypedArray(), autoViv, classHandles, nameToSlot, mi,
            unboxInt, unboxNum, unboxStr, unboxObj, posDel, assDel, variant = false)
    }

    private fun kindOf(tc: ThreadContext, attrSt: STable): SlotKind =
        if (attrSt.REPR.get_storage_spec(tc, attrSt).inlining == org.raku.nqp.sixmodel.Inlining.INLINED)
            attrSt.REPR.inlinedKind() ?: throw ExceptionHandling.dieInternal(tc,
                "Representation " + attrSt.REPR.name + " says it inlines but names no slot kind")
        else SlotKind.REF

    override fun compose(tc: ThreadContext, st: STable, reprInfo: SixModelObject) {
        val rd = st.REPRData as RakuObjectREPRData
        if (rd.layout != null)
            throw ExceptionHandling.dieInternal(tc, "Type " + st.debugName + " is already composed")
        val attrInfo = reprInfo.at_key_boxed(tc, "attribute")!!

        var curAttr = 0
        var mi = false
        val classHandles = ArrayList<SixModelObject?>()
        val nameToSlot = ArrayList<Object2IntOpenHashMap<String>>()
        val autoVivs = ArrayList<SixModelObject?>()
        val kinds = ArrayList<SlotKind>()
        val specs = ArrayList<StorageSpec?>()
        val slotSTables = ArrayList<STable?>()
        var unboxInt = -1; var unboxNum = -1; var unboxStr = -1; var unboxObj = -1; var posDel = -1; var assDel = -1
        val mroLength = attrInfo.elems(tc)
        for (i in mroLength - 1 downTo 0) {
            val entry = attrInfo.at_pos_boxed(tc, i)!!
            val type = entry.at_pos_boxed(tc, 0)!!
            val attrs = entry.at_pos_boxed(tc, 1)!!
            val parents = entry.at_pos_boxed(tc, 2)!!
            val numAttrs = attrs.elems(tc)
            if (numAttrs > 0) {
                val indexes = Object2IntOpenHashMap<String>()
                for (j in 0 until numAttrs) {
                    val attrHash = attrs.at_pos_boxed(tc, j)!!
                    val attrName = attrHash.at_key_boxed(tc, "name")!!.get_str(tc)
                    var attrType = attrHash.at_key_boxed(tc, "type")
                    if (Ops.isnull(attrType) == 1L) attrType = tc.gc.KnowHOW
                    indexes.put(attrName, curAttr)
                    val attrSt = attrType!!.st
                    val kind = kindOf(tc, attrSt)
                    kinds.add(kind)
                    if (kind == SlotKind.REF) { slotSTables.add(null); specs.add(null) }
                    else { slotSTables.add(attrSt); specs.add(attrSt.REPR.get_storage_spec(tc, attrSt)) }
                    autoVivs.add(attrHash.at_key_boxed(tc, "auto_viv_container"))
                    if (attrHash.exists_key(tc, "box_target") != 0L) {
                        if (kind == SlotKind.REF)
                            throw ExceptionHandling.dieInternal(tc, "A box_target must not have a reference type attribute")
                        when (attrSt.REPR.get_storage_spec(tc, attrSt).boxedPrimitive) {
                            BoxedPrimitive.INT, BoxedPrimitive.UINT -> unboxInt = curAttr
                            BoxedPrimitive.NUM -> unboxNum = curAttr
                            BoxedPrimitive.STR -> unboxStr = curAttr
                            else -> unboxObj = curAttr
                        }
                    }
                    if (attrHash.exists_key(tc, "positional_delegate") != 0L) posDel = curAttr
                    if (attrHash.exists_key(tc, "associative_delegate") != 0L) assDel = curAttr
                    curAttr++
                }
                classHandles.add(type)
                nameToSlot.add(indexes)
            }
            if (parents.elems(tc) > 1) mi = true
        }
        install(st, rd, kinds, specs, slotSTables, autoVivs.toTypedArray(), classHandles.toTypedArray(), nameToSlot, mi,
            unboxInt, unboxNum, unboxStr, unboxObj, posDel, assDel)
    }

    override fun allocate(tc: ThreadContext, st: STable): SixModelObject {
        val rd = st.REPRData as RakuObjectREPRData
        val l = rd.layout ?: throw ExceptionHandling.dieInternal(tc, "Cannot allocate an instance of the uncomposed type " + st.debugName)
        return l.newInstance()
    }

    override fun change_type(tc: ThreadContext, Object: SixModelObject, NewType: SixModelObject) {
        if (NewType.st.REPR !is RakuObjectREPR)
            throw ExceptionHandling.dieInternal(tc, "P6opaque can only rebless to another P6opaque-based type")
        val ourLayout = (Object.st.REPRData as RakuObjectREPRData).layout!!
        val targetRd = NewType.st.REPRData as RakuObjectREPRData
        val targetLayout = targetRd.layout
            ?: throw ExceptionHandling.dieInternal(tc, "Cannot rebless to the uncomposed type " + NewType.st.debugName)
        val ours = ourLayout.classHandles
        val theirs = targetLayout.classHandles
        if (ours.size > theirs.size)
            throw ExceptionHandling.dieInternal(tc, "Incompatible MROs in P6opaque rebless")
        for (i in ours.indices)
            if (ours[i] !== theirs[i])
                throw ExceptionHandling.dieInternal(tc, "Incompatible MROs in P6opaque rebless")
        val o = Object as RakuObject
        val newLayout = targetRd.layoutFor(o.javaClass)
        newLayout.growExt(o)
        o.layout = newLayout
        Object.st = NewType.st
        if (RakuObjectLayout.STATS) RakuObjectLayout.REBLESSES.incrementAndGet()
        if (RakuObjectLayout.TRACE) System.err.println("rebless: " + ourLayout.st.debugName + " -> " + NewType.st.debugName
            + " class=" + o.javaClass.simpleName + (if (newLayout.variant) " (variant)" else ""))
    }

    override fun get_storage_spec(tc: ThreadContext, st: STable): StorageSpec {
        val l = (st.REPRData as RakuObjectREPRData).layout ?: return StorageSpec()
        val canBox = buildSet<Boxable> {
            if (l.unboxIntSlot >= 0) add(Boxable.INT)
            if (l.unboxNumSlot >= 0) add(Boxable.NUM)
            if (l.unboxStrSlot >= 0) add(Boxable.STR)
        }
        return StorageSpec(canBox = canBox)
    }

    override fun hint_for(tc: ThreadContext, st: STable, classHandle: SixModelObject?, name: String?): Long {
        val rd = st.REPRData as? RakuObjectREPRData ?: return STable.NO_HINT
        val l = rd.layout ?: return STable.NO_HINT
        val s = l.slotFor(classHandle, name)
        return if (s < 0) STable.NO_HINT else s.toLong()
    }

    /* ----- REPR data: the same bytes as before ----- */

    override fun deserialize_repr_data(tc: ThreadContext, st: STable, reader: SerializationReader) {
        val rd = RakuObjectREPRData()
        st.REPRData = rd
        val numAttributes = reader.readLong().toInt()
        val flattened = arrayOfNulls<STable>(numAttributes)
        for (i in 0 until numAttributes)
            if (reader.readLong() != 0L) flattened[i] = reader.readSTableRef()
        val mi = reader.readLong() != 0L
        val autoViv = arrayOfNulls<SixModelObject>(numAttributes)
        if (reader.readLong() != 0L)
            for (i in 0 until numAttributes) autoViv[i] = reader.readRef()
        val unboxInt = reader.readLong().toInt()
        val unboxNum = reader.readLong().toInt()
        val unboxStr = reader.readLong().toInt()
        var unboxObj = -1
        if (reader.readLong() != 0L) unboxObj = reader.readLong().toInt()
        val numClasses = reader.readLong().toInt()
        val classHandles = ArrayList<SixModelObject?>()
        val nameToSlot = ArrayList<Object2IntOpenHashMap<String>>()
        for (i in 0 until numClasses) {
            val classHandle = reader.readRef()
            val nameToHintObject = reader.readRef()
            if (Ops.isnull(nameToHintObject) == 1L) {
                /* Nothing to do. */
            }
            else if (nameToHintObject is VMHashInstance) {
                val map = Object2IntOpenHashMap<String>()
                val origMap = nameToHintObject.storage
                if (origMap.size > 0) {
                    for (key in origMap.keys) map.put(key, origMap[key]!!.get_int(tc).toInt())
                    classHandles.add(classHandle)
                    nameToSlot.add(map)
                }
            }
            else throw ExceptionHandling.dieInternal(tc, "Unexpected hint map representation in deserialize")
        }
        val posDel = reader.readLong().toInt()
        val assDel = reader.readLong().toInt()

        val kinds = ArrayList<SlotKind>()
        val specs = ArrayList<StorageSpec?>()
        val slotSTables = ArrayList<STable?>()
        for (i in 0 until numAttributes) {
            val f = flattened[i]
            if (f != null) {
                /* A flattened native's storage spec is its own REPR data,
                 * and the STable table is not in dependency order. */
                reader.forceSTable(f)
                kinds.add(kindOf(tc, f)); slotSTables.add(f); specs.add(f.REPR.get_storage_spec(tc, f))
            }
            else { kinds.add(SlotKind.REF); slotSTables.add(null); specs.add(null) }
        }
        install(st, rd, kinds, specs, slotSTables, autoViv, classHandles.toTypedArray(), nameToSlot, mi,
            unboxInt, unboxNum, unboxStr, unboxObj, posDel, assDel)
    }

    override fun serialize_repr_data(tc: ThreadContext, st: STable, writer: SerializationWriter) {
        val l = (st.REPRData as RakuObjectREPRData).layout
            ?: throw ExceptionHandling.dieInternal(tc, "Representation must be composed before it can be serialized")
        val n = l.kinds.size
        writer.writeInt(n.toLong())
        for (i in 0 until n) {
            val f = l.slotSTables[i]
            if (f == null) writer.writeInt(0) else { writer.writeInt(1); writer.writeSTableRef(f) }
        }
        writer.writeInt(if (l.mi) 1 else 0)
        writer.writeInt(1)
        for (i in 0 until n) writer.writeRef(l.autoViv[i])
        writer.writeInt(l.unboxIntSlot.toLong())
        writer.writeInt(l.unboxNumSlot.toLong())
        writer.writeInt(l.unboxStrSlot.toLong())
        if (l.unboxObjSlot != -1) { writer.writeInt(1); writer.writeInt(l.unboxObjSlot.toLong()) } else writer.writeInt(0)
        writer.writeInt(l.classHandles.size.toLong())
        for (i in l.classHandles.indices) {
            writer.writeRef(l.classHandles[i])
            writer.writeIntHash(l.nameToSlot[i])
        }
        writer.writeInt(l.posDelSlot.toLong())
        writer.writeInt(l.assDelSlot.toLong())
    }

    /* ----- objects ----- */

    /** The stub is the final object. Its class comes from the STable's
     *  layout when that is known (a type from another SC, or one whose REPR
     *  data is already read), else from a peek at the serialized attribute
     *  header; the layout itself is installed at finish. */
    override fun deserialize_stub(tc: ThreadContext, st: STable, reader: SerializationReader): SixModelObject {
        val rd = st.REPRData as? RakuObjectREPRData
        val known = rd?.layout
        if (known != null) return known.newInstance()
        val shape = reader.peekAttributeShape(st)
        val classId = if (shape == null) 0 else RakuObjectLayout.chooseClass(shape[0], shape[1])
        val o: RakuObject = when (classId) {
            0 -> RakuObject4(); 1 -> RakuObject8(); 2 -> RakuObject16()
            3 -> RakuObject4L(); 4 -> RakuObject8L(); else -> RakuObject16L()
        }
        o.st = st
        return o
    }

    override fun deserialize_stub(tc: ThreadContext, st: STable): SixModelObject =
        throw ExceptionHandling.dieInternal(tc, "RakuObject stubs need the reader")

    override fun deserialize_finish(tc: ThreadContext, st: STable, reader: SerializationReader, obj: SixModelObject) {
        val rd = st.REPRData as RakuObjectREPRData
        val o = obj as RakuObject
        val l = rd.layoutFor(o.javaClass)
        l.growExt(o)
        o.layout = l
        for (s in l.kinds.indices) {
            when (l.kinds[s]) {
                SlotKind.REF -> l.setRef(o, s, reader.readRef())
                SlotKind.INT -> l.setLong(o, s, reader.readLong())
                SlotKind.NUM -> l.setLong(o, s, java.lang.Double.doubleToRawLongBits(reader.readDouble()))
                SlotKind.STR -> l.setRef(o, s, reader.readStr())
                SlotKind.BIGINT -> l.setRef(o, s, java.math.BigInteger(reader.readStr()))
                SlotKind.NCBODY -> { /* re-configured each run, as NativeCall.inlineDeserialize did */ }
            }
        }
    }

    override fun serialize(tc: ThreadContext, writer: SerializationWriter, obj: SixModelObject) {
        val o = obj as RakuObject
        val l = o.layout ?: throw ExceptionHandling.dieInternal(tc, "Representation must be composed before it can be serialized")
        for (s in l.kinds.indices) {
            when (l.kinds[s]) {
                SlotKind.REF -> writer.writeRef(l.getRef(o, s) as SixModelObject?)
                SlotKind.INT -> writer.writeInt(l.getLong(o, s))
                SlotKind.NUM -> writer.writeNum(java.lang.Double.longBitsToDouble(l.getLong(o, s)))
                SlotKind.STR -> writer.writeStr(l.getRef(o, s) as String?)
                SlotKind.BIGINT -> writer.writeStr((l.getRef(o, s) as java.math.BigInteger?)?.toString() ?: "0")
                SlotKind.NCBODY -> { /* nothing on the wire */ }
            }
        }
    }
}
```

Two wire notes the old code settles: `serialize_repr_data` wrote the auto-viv flag as 1 whenever the array existed (it always did after compose), so writing 1 unconditionally is the same bytes; the old `serialize_inlined` of a BIGINT wrote `field.toString()` on a never-null field (deserialization always made one), and the `?: "0"` only covers a slot never bound, which the old road would have NPE'd on.

- [ ] **Step 5: `REPR.kt`.** Replace lines 118-149 (the eight hooks) with:

```kotlin
    /**
     * The slot kind an object of this representation occupies when flattened
     * into a RakuObject (get_storage_spec says INLINED); null for a
     * reference representation.
     */
    open fun inlinedKind(): SlotKind? = null
```

and add beside the two abstract deserialize members:

```kotlin
    /** The stub with the reader in hand; a representation whose stub's
     *  shape depends on serialized data (RakuObject) overrides this one. */
    open fun deserialize_stub(tc: ThreadContext, st: STable, reader: SerializationReader): SixModelObject? =
        deserialize_stub(tc, st)
```

Add `import org.raku.nqp.sixmodel.reprs.SlotKind`; drop the two ASM imports. In the six flattening REPRs delete `inlineStorage`, `inlineBind`, `inlineGet`, `inlineDeserialize`, `generateBoxingMethods`, `serialize_inlined`, `inline_description`, `box_description` and the `org.objectweb.asm` imports, and add:

| file | add |
|---|---|
| `P6int.kt` | `override fun inlinedKind(): SlotKind = SlotKind.INT` |
| `P6num.kt` | `override fun inlinedKind(): SlotKind = SlotKind.NUM` |
| `P6str.kt` | `override fun inlinedKind(): SlotKind = SlotKind.STR` |
| `P6bigint.kt` | `override fun inlinedKind(): SlotKind = SlotKind.BIGINT` |
| `NativeCall.kt` | `override fun inlinedKind(): SlotKind = SlotKind.NCBODY` |
| `CPointer.kt` | nothing (the dead `generateBoxingMethods` goes; `get_storage_spec` stays the reference default) |

`P6int.sizedValue`, `P6bigint.checkedLongValue/uncheckedLongValue/unsignedValueOf` stay (the layout calls them). `REPRRegistry.kt:56`: `addREPR("P6opaque", RakuObjectREPR())`.

- [ ] **Step 6: `SerializationReader.kt`.** In `stubObjects` (:386) replace `stubObj = st.REPR.deserialize_stub(tc, st)` with `stubObj = st.REPR.deserialize_stub(tc, st, this)`. Add, next to `forceSTable`:

```kotlin
    /** For a RakuObject stub: [references, longs] counted from the STable's
     *  serialized REPR-data header (attribute count, then per attribute a
     *  flag and, when flattened, an STable ref whose REPR names the kind).
     *  Reads no object reference, so it is safe during stubObjects. Null
     *  when the STable is not this SC's (already whole) or its REPR data is
     *  already read (the layout is the better answer). Cached per STable. */
    fun peekAttributeShape(st: STable): IntArray? {
        val idx = stableIndex[st] ?: return null
        if (stableState[idx] == ST_READ) return null
        shapeCache[idx]?.let { return it }
        val saved = orig.position()
        try {
            orig.position(stTableOffset + idx * STABLES_TABLE_ENTRY_SIZE + 8)
            orig.position(stDataOffset + orig.getInt())
            val n = orig.getLong().toInt()
            var refs = 0; var longs = 0
            for (i in 0 until n) {
                if (orig.getLong() != 0L) {
                    val flattened = lookupSTable(orig.getInt(), orig.getInt())
                    val k = flattened.REPR.inlinedKind()
                    if (k == org.raku.nqp.sixmodel.reprs.SlotKind.INT || k == org.raku.nqp.sixmodel.reprs.SlotKind.NUM) longs++ else refs++
                }
                else refs++
            }
            val shape = intArrayOf(refs, longs)
            shapeCache[idx] = shape
            return shape
        }
        finally {
            orig.position(saved)
        }
    }
    private val shapeCache = HashMap<Int, IntArray>()
```

(`stableIndex`, `stableState`, `ST_READ`, `stTableOffset`, `stDataOffset`, `STABLES_TABLE_ENTRY_SIZE`, `lookupSTable`, `orig` all exist in the class; the STables entry is `[reprName:int][dataOffset:int][reprDataOffset:int]`, the third written at `SerializationWriter.kt:609`.) The `HashMap` import exists.

- [ ] **Step 7: `Ops.kt`.** Replace the attribute ops so the kind is decided before any read:

```kotlin
    /* Attribute operations. */
    @JvmStatic
    fun getattr(obj: SixModelObject?, ch: SixModelObject?, name: String?, tc: ThreadContext): SixModelObject? =
        getattrIn(obj, ch, name, tc, null)

    /** A native slot read in object context boxes with the given language,
     *  or the frame's when null (resolved only on that branch: the frame is
     *  a dummy while a unit deserializes). */
    @JvmStatic
    fun getattrIn(obj: SixModelObject?, ch: SixModelObject?, name: String?, tc: ThreadContext, hllIn: HLLConfig?): SixModelObject? {
        val chd = decont(ch, tc)
        if (obj is RakuObject) {
            val l = obj.layout ?: return obj.get_attribute_boxed(tc, chd, name, STable.NO_HINT)
            return getattrSlot(obj, l, l.resolve(chd, name), name, tc, hllIn)
        }
        return obj!!.get_attribute_boxed(tc, chd, name, STable.NO_HINT)
    }

    /** The boxed reading of any slot kind. */
    private fun getattrSlot(obj: RakuObject, l: RakuObjectLayout, slot: Int, name: String?, tc: ThreadContext, hllIn: HLLConfig?): SixModelObject? {
        when (l.kinds[slot]) {
            SlotKind.REF -> return (l.getRef(obj, slot) as SixModelObject?) ?: obj.autoViv(l, slot, tc)
            SlotKind.INT -> {
                val hll = hllIn ?: tc.frame.codeRef.staticInfo.compUnit.hllConfig
                return box_i(l.getLong(obj, slot), hll.intBoxType, tc)
            }
            SlotKind.NUM -> {
                val hll = hllIn ?: tc.frame.codeRef.staticInfo.compUnit.hllConfig
                return box_n(java.lang.Double.longBitsToDouble(l.getLong(obj, slot)), hll.numBoxType, tc)
            }
            SlotKind.STR -> {
                val hll = hllIn ?: tc.frame.codeRef.staticInfo.compUnit.hllConfig
                return box_s(l.getRef(obj, slot) as String?, hll.strBoxType, tc)
            }
            SlotKind.BIGINT -> {
                val attrSt = l.slotSTables[slot]!!
                val res = attrSt.REPR.allocate(tc, attrSt) as P6bigintInstance
                res.value = l.getRef(obj, slot) as java.math.BigInteger?
                return res
            }
            SlotKind.NCBODY -> {
                val attrSt = l.slotSTables[slot]!!
                val res = attrSt.REPR.allocate(tc, attrSt) as NativeCallInstance
                res.body = l.getRef(obj, slot) as NativeCallBody?
                return res
            }
        }
    }

    @JvmStatic
    fun getattr(obj: SixModelObject?, ch: SixModelObject?, name: String?, hint: Long, tc: ThreadContext): SixModelObject? {
        val chd = decont(ch, tc)
        if (obj is RakuObject) {
            val l = obj.layout ?: return obj.get_attribute_boxed(tc, chd, name, STable.NO_HINT)
            /* MI: the hint was computed on the declaring class; resolve by name. */
            val slot = if (hint != STable.NO_HINT && !l.mi) hint.toInt() else l.resolve(chd, name)
            return getattrSlot(obj, l, slot, name, tc, null)
        }
        return obj!!.get_attribute_boxed(tc, chd, name, hint)
    }
```

The four hinted native getters keep their bodies (they already go through `get_attribute_native` and the `mi` check; `RakuObject.get_attribute_native` now dies with the right text on a reference slot instead of throwing `BadNativeRuntimeException`); the class test in them becomes `obj!!.st.REPRData is RakuObjectREPRData && (obj.st.REPRData as RakuObjectREPRData).layout?.mi == true`. The `bindattr` families are unchanged (they never caught anything). `attrinited`, `attrhintfor`, `getattrref_*` unchanged.

`getBI`/`makeBI` (:8612-8663) become:

```kotlin
    private fun getBI(tc: ThreadContext, obj: SixModelObject?): BigInteger {
        if (obj is P6bigintInstance) return obj.value!!
        return getBI(tc, obj, obj!!.st.WHAT)
    }

    private fun getBI(tc: ThreadContext, obj: SixModelObject?, type: SixModelObject?): BigInteger {
        if (obj is P6bigintInstance) return obj.value!!
        val o = obj as? RakuObject
            ?: throw ExceptionHandling.dieInternal(tc, "Cannot unbox a bigint from a " + obj!!.st.REPR.name + " object")
        val l = o.layout ?: throw ExceptionHandling.dieInternal(tc, "Cannot unbox a bigint from an uncomposed type")
        var slot = l.unboxIntSlot
        if (slot < 0) slot = ((type!!.st.REPRData as? RakuObjectREPRData)?.layout?.unboxIntSlot ?: -1)
        if (slot < 0) slot = 0
        return when (l.kinds[slot]) {
            SlotKind.BIGINT -> (l.getRef(o, slot) as BigInteger?) ?: BigInteger.ZERO
            SlotKind.INT -> BigInteger.valueOf(l.getLong(o, slot))
            else -> throw ExceptionHandling.dieInternal(tc, "Attribute slot $slot of " + o.st.debugName + " is not a bigint")
        }
    }

    private fun makeBI(tc: ThreadContext, type: SixModelObject?, value: BigInteger): SixModelObject {
        val res = type!!.st.REPR.allocate(tc, type.st)
        if (res is P6bigintInstance) { res.value = value; return res }
        val o = res as RakuObject
        val l = o.layout!!
        val slot = if (l.unboxIntSlot < 0) 0 else l.unboxIntSlot
        when (l.kinds[slot]) {
            SlotKind.BIGINT -> l.setRef(o, slot, value)
            SlotKind.INT -> l.setLong(o, slot, P6int.sizedValue(l.specs[slot], value.toLong()))
            else -> throw ExceptionHandling.dieInternal(tc, "Attribute slot $slot of " + type.st.debugName + " is not a bigint")
        }
        return res
    }
```

Imports: `org.raku.nqp.sixmodel.reprs.RakuObject`, `RakuObjectLayout`, `RakuObjectREPRData`, `SlotKind`, `NativeCallInstance`, `NativeCallBody`, `P6int`; remove the `P6OpaqueBaseInstance`/`P6OpaqueREPRData` imports. `grep -n 'P6Opaque' nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/Ops.kt` must be empty after.

- [ ] **Step 8: `DispatchModel.kt:186-200`** (`attributeKind`) becomes:

```kotlin
        /** Works out which kind of value an attribute holds, from the layout. */
        fun attributeKind(tc: ThreadContext, obj: SixModelObject,
                          classHandle: SixModelObject?, name: String): ArgKind {
            val l = (obj as? RakuObject)?.layout
            if (l == null) {
                obj.get_attribute_boxed(tc, classHandle, name, STable.NO_HINT)
                return ArgKind.OBJ
            }
            return when (l.kinds[l.resolve(classHandle, name)]) {
                SlotKind.REF -> ArgKind.OBJ
                SlotKind.INT -> ArgKind.INT
                SlotKind.NUM -> ArgKind.NUM
                SlotKind.STR -> ArgKind.STR
                else -> throw ExceptionHandling.dieInternal(tc, "Cannot track an attribute of this kind")
            }
        }
```

`NativeCallOps.kt:624-630`: delete the "Handle mixins by following delegates" block; `resolved` is `target` itself. Remove the `P6OpaqueBaseInstance` import.

- [ ] **Step 9: delete the old files** (nqp dir): `git rm src/vm/jvm/runtime/org/raku/nqp/sixmodel/reprs/P6Opaque.kt src/vm/jvm/runtime/org/raku/nqp/sixmodel/reprs/P6OpaqueBaseInstance.kt src/vm/jvm/runtime/org/raku/nqp/sixmodel/reprs/P6OpaqueDelegateInstance.kt src/vm/jvm/runtime/org/raku/nqp/sixmodel/reprs/P6OpaqueREPRData.kt`. Then `grep -rn 'P6Opaque\|field_\|BadReferenceRuntimeException\|BadNativeRuntimeException' nqp/src/vm/jvm/runtime` must be empty (the engine's hits in `nqp/nqp-truffle/` are Task 4's; the Rakudo runtime's are Task 3's). `GlobalContext.byteClassLoader` stays until Task 6 (interop still defines a class until Task 5).

- [ ] **Step 10: un-skip repossession.** In `nqp/t/serialization/04-repossession.t` delete lines 6-9 (the `if ... eq 'jvm' { skip(...); nqp::exit(0) }` block).

- [ ] **Step 11: build (nqp-runtime only).**

```
./nqp/gradlew -p nqp :nqp-runtime:test :nqp-runtime:jar 2>&1 | tail -15
```

Expected: `BUILD SUCCESSFUL`, the two existing unit test classes green. Do NOT run `:nqp-truffle:jar` or `syncRuntimeJars` yet: the engine's P6Opaque references are Task 3's, and an engine jar compiled against the old classes fails to link on the first attribute site. Compile errors here are fixed in this task's files (the message names the consumer that was missed).

- [ ] **Step 12: commit (nqp):**

```
git add -A src/vm/jvm/runtime t/serialization/04-repossession.t
git commit -m "RakuObject: P6opaque objects on a static class family and a per-STable layout; no generated storage classes, no delegate; rebless grows in place; the wire format is unchanged"
```

---

### Task 3: The Truffle sites on the layout; the nqp gate

**Files:**
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java:761-806` (comment + reset), `:1433-1529` (AttrSite, getattr, bindattr, resolveAttr), `:1541-1546` (the ATTR_TRACE block), and the two comment-only mentions at `:960-962`, `:1052-1053`
- Modify: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt:49-51` (imports), `:129-216` (AttrSrc, UnboxSrc), `:440-464` (fold, storageOf), `:481-488` (getterFor), `:551-578` (fieldHandles)
- Modify: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt:21-23` (imports), `:213-297` (DecontSite), `:610-664` (CreateSite), `:670-826` (BigIntSite)
- Test: `nqp/t/jvm/17-object-layout.t`, `18-rebless-layout.t`, `04-serialization-types.t`, `06-atomic-attrs.t`, `nqp/t/serialization/04-repossession.t`, then t/nqp

**Interfaces:**
- Consumes: `RakuObject.layout` (plain `@JvmField`, read raw), `RakuObjectLayout.kinds/refGetter/refSetter/newInstance/unboxIntSlot/slotFor`, `RakuObjectREPRData.layout/intCache`, `SlotKind`.
- Produces: `NqpDispatch.layoutHandles(layout, slot): Array<MethodHandle>?` (the getter typed `(SixModelObject)SixModelObject`, the setter `(SixModelObject,SixModelObject)void`, null for a non-REF slot) — used by `NqpOps.resolveAttr` and `NqpTypeOps.resolveDecont`.

- [ ] **Step 1: `NqpDispatch.kt`.** Imports: replace the three `P6Opaque*` imports with `org.raku.nqp.sixmodel.reprs.RakuObject`, `RakuObjectLayout`, `RakuObjectREPRData`, `SlotKind`. `AttrSrc` and `UnboxSrc`:

```kotlin
    /**
     * An attribute read whose object's layout is known from the guards: the
     * slot's field (or overflow element) through a constant MethodHandle
     * getter, which PE folds to the load. The layout check is a
     * speculation: an object reblessed while on a smaller class carries a
     * variant layout of the same type and takes the generic road here.
     */
    class AttrSrc(
        @JvmField val from: Src,
        @JvmField val layout: RakuObjectLayout,
        @JvmField val getter: MethodHandle,
        @JvmField val classHandle: SixModelObject?,
        @JvmField val name: String,
        @JvmField val kind: ArgKind,
    ) : Src() {
        override fun eval(tc: ThreadContext, args: Array<Any?>): Any? {
            val o = from.eval(tc, args)
            if (o is RakuObject && o.layout === layout) {
                val v: SixModelObject? = try {
                    getter.invokeExact(o as SixModelObject) as SixModelObject?
                } catch (t: Throwable) {
                    throw CompilerDirectives.shouldNotReachHere(t)
                }
                /* Null: not yet vivified (or genuinely null); the accessor
                 * decides which and vivifies. */
                if (v != null) return v
            }
            return slow(tc, o)
        }

        @TruffleBoundary
        private fun slow(tc: ThreadContext, o: Any?): Any? {
            if (STATS) {
                count(slowEvals)
                val key = "slow attr " + name + " of " + (if (o == null) "null" else o.javaClass.name) +
                    " layout=" + (if (o is RakuObject) o.layout?.st?.debugName else "-") + " vs " + layout.st.debugName
                if (seenSlow.add(key)) System.err.println("dispatch $key")
            }
            if (o == null)
                throw ExceptionHandling.dieInternal(tc,
                    "Dispatch program read an attribute of a null value")
            return ValueSource.readAttribute(tc, o as SixModelObject, classHandle, name, kind)
        }
    }

    /** An unbox of an object whose layout is known, likewise. */
    class UnboxSrc(
        @JvmField val from: Src,
        @JvmField val layout: RakuObjectLayout,
        @JvmField val kind: ArgKind,
    ) : Src() {
        override fun eval(tc: ThreadContext, args: Array<Any?>): Any? {
            val o = from.eval(tc, args)
            if (o is RakuObject && o.layout === layout) {
                val smo = CompilerDirectives.castExact(o, layout.storage) as SixModelObject
                return when (kind) {
                    ArgKind.INT, ArgKind.UINT -> smo.get_int(tc)
                    ArgKind.NUM -> smo.get_num(tc)
                    else -> smo.get_str(tc)
                }
            }
            return slow(tc, o)
        }

        @TruffleBoundary
        private fun slow(tc: ThreadContext, o: Any?): Any? {
            if (STATS) {
                count(slowEvals)
                val key = "slow unbox " + kind + " of " + (if (o == null) "null" else o.javaClass.name) +
                    " vs " + layout.st.debugName
                if (seenSlow.add(key)) System.err.println("dispatch $key")
            }
            return ValueSource.unbox(tc, o as SixModelObject?, kind)
        }
    }
```

`fold` (:440-454) and `storageOf`/`getterFor`:

```kotlin
            if (s is ValueSource.Attribute && s.kind == ArgKind.OBJ) {
                val layout = layoutOf(s.from)
                if (layout != null) {
                    val st = known[s.from]!!
                    val hint = st.REPR.hint_for(tc, st, s.classHandle, s.name)
                    val getter = if (hint == STable.NO_HINT) null else getterFor(layout, hint.toInt())
                    if (getter != null)
                        return AttrSrc(fold(s.from), layout, getter, s.classHandle, s.name, s.kind)
                }
            }
            if (s is ValueSource.Unbox) {
                val layout = layoutOf(s.from)
                if (layout != null && s.kind != ArgKind.OBJ)
                    return UnboxSrc(fold(s.from), layout, s.kind)
            }
```

```kotlin
        /** The canonical layout of a source a type guard has fixed. */
        private fun layoutOf(from: ValueSource): RakuObjectLayout? {
            val st = known[from] ?: return null
            val rd = st.REPRData as? RakuObjectREPRData ?: return null
            return rd.layout
        }
```

```kotlin
            private fun getterFor(layout: RakuObjectLayout, slot: Int): MethodHandle? =
                layoutHandles(layout, slot)?.get(0)
```

`fieldHandles` (:551-578) becomes:

```kotlin
    /**
     * The slot's getter (SixModelObject)SixModelObject and setter
     * (SixModelObject,SixModelObject)void on the layout, or null when the
     * slot is not a reference slot. Auto-vivification (every `$` attribute
     * of a Raku class has a container prototype) only matters when the slot
     * is null -- the accessor clones the prototype in and stores it -- so a
     * caller reads the slot and sends a null to the accessor, and a vivified
     * attribute, the steady state, is a plain load.
     */
    @JvmStatic
    fun layoutHandles(layout: RakuObjectLayout, slot: Int): Array<MethodHandle>? {
        if (slot < 0 || slot >= layout.kinds.size || layout.kinds[slot] != SlotKind.REF) return null
        return arrayOf(
            layout.refGetter(slot).asType(MethodType.methodType(SixModelObject::class.java, SixModelObject::class.java)),
            layout.refSetter(slot).asType(MethodType.methodType(Void.TYPE, SixModelObject::class.java, SixModelObject::class.java)),
        )
    }
```

Any remaining `P6Opaque`/`delegate`/`field_` text in the file is a comment: reword to "layout" (`grep -n 'P6Opaque\|delegate\|field_' nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpDispatch.kt` empty after).

- [ ] **Step 2: `NqpOps.java`.** The `AttrSite` family (:1433-1529):

```java
    /**
     * One getattr/bindattr instruction's cache: up to two layouts and the
     * slot's handles for each, so the read or write is a field access after
     * PE. A type with no plain-slot road (a non-RakuObject, a natively
     * stored slot, an unknown attribute), or a third layout, marks the site
     * unusable and the runtime op is taken.
     */
    static final class AttrSite {
        @CompilationFinal org.raku.nqp.sixmodel.reprs.RakuObjectLayout layout;
        @CompilationFinal java.lang.invoke.MethodHandle getter;
        @CompilationFinal java.lang.invoke.MethodHandle setter;
        @CompilationFinal org.raku.nqp.sixmodel.reprs.RakuObjectLayout layout2;
        @CompilationFinal java.lang.invoke.MethodHandle getter2;
        @CompilationFinal java.lang.invoke.MethodHandle setter2;
        @CompilationFinal boolean resolved;
        @CompilationFinal boolean pinned;
        /* The (class handle, name) the handles were resolved for; see the
         * BUILDALL note in the git history of this comment (2026-09-08). */
        @CompilationFinal Object ch;
        @CompilationFinal String name;
        AttrSite() { ATTR_SITES.add(this); }

        boolean sameKey(Object ch, String name) {
            return ch == this.ch && (name == this.name || name.equals(this.name));
        }
    }

    static Object getattr(AttrSite site, Object o, Object ch, String name, ThreadContext tc, CompilationUnit cu) {
        if (o instanceof org.raku.nqp.sixmodel.reprs.RakuObject r && site.sameKeyOrUnset(ch, name)) {
            org.raku.nqp.sixmodel.reprs.RakuObjectLayout l = r.layout;
            java.lang.invoke.MethodHandle getter = null;
            if (l != null) {
                if (l == site.layout) getter = site.getter;
                else if (l == site.layout2) getter = site.getter2;
                else if (!site.pinned) {
                    CompilerDirectives.transferToInterpreterAndInvalidate();
                    getter = resolveAttr(site, r, l, ch, name, tc, false);
                }
            }
            if (getter != null) {
                SixModelObject v;
                try {
                    v = (SixModelObject) getter.invokeExact((SixModelObject) o);
                } catch (Throwable t) {
                    throw CompilerDirectives.shouldNotReachHere(t);
                }
                /* A null slot may still auto-vivify; the op decides. */
                if (v != null) return v;
            }
        }
        return getattrSlow(o, ch, name, tc, cu);
    }

    static Object bindattr(AttrSite site, Object o, Object ch, String name, Object value,
                           ThreadContext tc) {
        if (o instanceof org.raku.nqp.sixmodel.reprs.RakuObject r && site.sameKeyOrUnset(ch, name)) {
            org.raku.nqp.sixmodel.reprs.RakuObjectLayout l = r.layout;
            java.lang.invoke.MethodHandle setter = null;
            if (l != null) {
                if (l == site.layout) setter = site.setter;
                else if (l == site.layout2) setter = site.setter2;
                else if (!site.pinned) {
                    CompilerDirectives.transferToInterpreterAndInvalidate();
                    setter = resolveAttr(site, r, l, ch, name, tc, true);
                }
            }
            if (setter != null) {
                SixModelObject v = smo(value);
                if (Ops.DO_TRACE) Ops.traceDoBind(r, name, v, tc);
                try {
                    setter.invokeExact((SixModelObject) r, v);
                } catch (Throwable t) {
                    throw CompilerDirectives.shouldNotReachHere(t);
                }
                if (r.sc != null) scwb(tc, r);
                return v;
            }
        }
        return bindattrSlow(o, ch, name, value, tc);
    }

    /** Resolves the slot for this layout into the first free entry; answers
     *  the handle asked for, or null (and pins) when there is no plain road. */
    @TruffleBoundary
    private static java.lang.invoke.MethodHandle resolveAttr(AttrSite site, org.raku.nqp.sixmodel.reprs.RakuObject r,
            org.raku.nqp.sixmodel.reprs.RakuObjectLayout l, Object ch, String name, ThreadContext tc, boolean wantSetter) {
        if (!site.resolved) { site.ch = ch; site.name = name; site.resolved = true; }
        if (site.layout != null && site.layout2 != null) { site.pinned = true; return null; }
        SixModelObject chd = Ops.decont(smo(ch), tc);
        int slot = l.slotFor(chd, name);
        java.lang.invoke.MethodHandle[] hs = slot < 0 ? null : NqpDispatch.layoutHandles(l, slot);
        if (hs == null) { site.pinned = true; return null; }
        if (site.layout == null) { site.layout = l; site.getter = hs[0]; site.setter = hs[1]; }
        else { site.layout2 = l; site.getter2 = hs[0]; site.setter2 = hs[1]; }
        return wantSetter ? hs[1] : hs[0];
    }
```

with, on `AttrSite`:

```java
        /** The key check that also lets the first resolution through. */
        boolean sameKeyOrUnset(Object ch, String name) {
            return !resolved || sameKey(ch, name);
        }
```

The reset (:803-805) becomes `s.layout = null; s.getter = null; s.setter = null; s.layout2 = null; s.getter2 = null; s.setter2 = null; s.resolved = false; s.pinned = false;`. The comment block at :761-785 replaces "a generated P6Opaque class" with "a RakuObject layout (per STable, per run)" and "the run's byte class loader (~180MB)" with "the run's serialization-context graph"; the ATTR_TRACE block (:1541-1546) reads `rd.layout.autoViv` from a `RakuObjectREPRData rd` instead of `rd.autoVivContainers`; the two comment mentions of `P6OpaqueDelegateInstance` become `RakuObject`. `grep -n 'P6Opaque\|delegate' nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpOps.java` empty after.

- [ ] **Step 3: `NqpTypeOps.kt`.** Imports: the three `P6Opaque*` become `RakuObject`, `RakuObjectLayout`, `RakuObjectREPRData`. `DecontSite` (:218-227): `storage: Class<*>?` becomes `layout: RakuObjectLayout?`; `decont` (:249-267):

```kotlin
                if (ost === st) {
                    if (o is TypeObject) return o
                    val layout = site.layout
                    if (o is RakuObject && layout != null && o.layout === layout) {
                        val getter = site.getter
                        if (getter != null) {
                            val v: SixModelObject? = try {
                                getter.invokeExact(o as SixModelObject) as SixModelObject?
                            } catch (t: Throwable) {
                                throw CompilerDirectives.shouldNotReachHere(t)
                            }
                            /* Null: not yet vivified; the accessor decides. */
                            if (v != null) return v
                        }
                    }
                }
                else miss(site)
```

`resolveDecont` (:275-297):

```kotlin
        if (fetch != null && rd is RakuObjectREPRData) {
            val layout = rd.layout
            if (layout != null) {
                val hint = st.REPR.hint_for(tc, st, fetch.classHandle, fetch.name)
                if (hint != STable.NO_HINT) {
                    val hs = NqpDispatch.layoutHandles(layout, hint.toInt())
                    if (hs != null) {
                        site.container = true
                        site.layout = layout
                        site.getter = hs[0]
                        site.st = st
                        return
                    }
                }
            }
        }
        site.pin()
```

`CreateSite` (:618-624): `proto: P6OpaqueBaseInstance?` becomes `layout: RakuObjectLayout?`; `create` (:635-648):

```kotlin
            if (st != null) {
                if (NqpRaw.st(type) === st) {
                    val layout = site.layout
                    if (layout != null) {
                        val rd = st.REPRData
                        if (rd is RakuObjectREPRData && rd.layout === layout) return layout.newInstance()
                    }
                    else {
                        val repr = site.repr
                        if (repr != null) return repr.allocate(tc, st)
                    }
                }
                miss(site)
            }
```

`resolveCreate`: `if (rd is RakuObjectREPRData) { val layout = rd.layout; if (layout == null) { site.pin(); return }; site.layout = layout } else site.repr = st.REPR`. The class comment: "A RakuObject allocates through its layout: with the layout a constant, `newInstance` is one `new` of an exact class."

`BigIntSite` (:681-692): `storage`/`proto` become one `layout: RakuObjectLayout?`; `bigintArith` (:709-742):

```kotlin
            if (st != null) {
                val layout = site.layout
                if (NqpRaw.st(a) === st && NqpRaw.st(b) === st && NqpRaw.st(type) === st
                        && layout != null && a is RakuObject && b is RakuObject
                        && a.layout === layout && b.layout === layout) {
                    val getter = site.getter
                    val setter = site.setter
                    if (getter != null && setter != null) {
                        val x = NqpRaw.getBig(getter, a)
                        val y = NqpRaw.getBig(getter, b)
                        if (x != null && y != null && x.bitLength() < 63 && y.bitLength() < 63) {
                            ... (the arithmetic unchanged) ...
                            if (fits) return boxSmall(site, r, layout, setter)
                        }
                    }
                }
                else {
                    if (DEBUG) debugBigMiss(site, a, b, type, st)
                    miss(site)
                }
            }
```

`boxSmall(site, r, layout, setter)` and `allocateBig(layout, r, setter)` take the layout; `allocateBig` is `val res = layout.newInstance(); NqpRaw.setBig(setter, res, java.math.BigInteger.valueOf(r)); return res`. `resolveBigInt` (:785-826):

```kotlin
        val rd = st.REPRData as? RakuObjectREPRData ?: run { if (DEBUG) debug("bigint pin: not P6opaque"); site.pin(); return }
        val layout = rd.layout
        val slot = layout?.unboxIntSlot ?: -1
        if (layout == null || slot < 0 || layout.kinds[slot] != SlotKind.BIGINT) {
            if (DEBUG) debug("bigint pin: layout=$layout slot=$slot")
            site.pin(); return
        }
        if (DEBUG) debug("bigint resolved: " + layout.st.debugName + " slot=$slot cache=$INT_CACHE")
        site.getter = layout.refGetter(slot)
            .asType(MethodType.methodType(java.math.BigInteger::class.java, SixModelObject::class.java))
        site.setter = layout.refSetter(slot)
            .asType(MethodType.methodType(Void.TYPE, SixModelObject::class.java, java.math.BigInteger::class.java))
        if (INT_CACHE) { ... rd.intCache as before ... }
        site.layout = layout
        site.st = st
```

`debugBigMiss` prints the layouts' `st.debugName` instead of classes. `grep -n 'P6Opaque\|delegate\|instClone\|jvmClass' nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt` empty after. Also `import org.raku.nqp.sixmodel.reprs.SlotKind`.

- [ ] **Step 4: build the runtime jars and the nqp gate.**

```
./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars 2>&1 | tail -8
```

then, from the nqp dir, the fast files first (seconds each):

```
./nqp-j-gradle t/jvm/17-object-layout.t
./nqp-j-gradle t/jvm/18-rebless-layout.t
./nqp-j-gradle t/jvm/04-serialization-types.t
./nqp-j-gradle t/jvm/06-atomic-attrs.t
./nqp-j-gradle t/serialization/04-repossession.t
NQP_LAYOUT_STATS=1 ./nqp-j-gradle -e 'say(1)'
```

Expected: every `ok`, and the stats line `layout stats: layouts=N variants=0 reblesses=0` on stderr. A `variants>0` here means a stub was allocated on the wrong class: check `peekAttributeShape` against `deserialize_repr_data`'s kinds for the type `NQP_LAYOUT_TRACE=1` names. Then the suite, as a background job:

```
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/5c60252a/tmp/t3-nqp.log --show='Result' --show='Failed' --show='not ok' --max=1800 -- ./nqp/gradlew -p nqp testNqp
```

Expected: `Result: PASS` for the eight dirs (118 t/nqp; `t/qast/01-qast.t` is the one known red, moar-only). The layout observations for `18-rebless-layout.t` are shell-side, not in-language: run

```
NQP_LAYOUT_STATS=1 ./nqp-j-gradle t/jvm/18-rebless-layout.t 2>&1 | tail -3
```

and record the `layout stats:` line in the ledger: `reblesses` must equal the number of `nqp::rebless` calls in the file (10) and `variants` must be at least 4 (the four `rebless_check` calls grow past their class). No test line is added for this; `plan()` stays as Task 1 left it.

- [ ] **Step 5: commit (nqp):**

```
git add -A nqp-truffle/src
git commit -m "engine: the attribute, decont, create and bigint sites guard on the RakuObject layout and read its constant handles; a site holds two layouts before it pins"
```

---

### Task 4: The Rakudo runtime consumers, the make, the first Rakudo gate

**Files:**
- Modify: `src/vm/jvm/runtime/org/raku/rakudo/Binder.kt:180-196`, `src/vm/jvm/runtime/org/raku/rakudo/RakudoContainerSpec.kt:108-140`, `t/02-rakudo/10-nqp-ops.t:10`
- Test: `t/01-sanity`, `t/02-rakudo/mixin-identity.t`, the milestone 4 sensitive slice, `docs/bench/jesp/plusquick.raku`, `docs/bench/jesp/attrquick.raku`

**Interfaces:**
- Consumes: `RakuObject`, `RakuObjectLayout.slotFor/slotForName/kinds/getVolatile`, `RakuObjectREPRData.layout`, `SlotKind`.
- Produces: a Rakudo build on the new runtime; the "after" bench rows; the CORE.c variant count.

- [ ] **Step 1: `Binder.kt:180-196`.** Replace the hint loop and the `flattenedSTables` read:

```kotlin
        if ((paramFlags and SIG_ELEM_BIND_PRIVATE_ATTR) != 0) {
            /* A native attribute has no container to fetch; ask the layout
             * for the slot's kind before trying. */
            val layout = (attrPackage.st.REPRData as? RakuObjectREPRData)?.layout
            val slot = layout?.slotFor(attrPackage, varName) ?: -1
            val kind = if (slot >= 0) layout!!.kinds[slot] else SlotKind.REF
            when (kind) {
                SlotKind.INT ->
                    Ops.bindattr_i(self, attrPackage, varName, Ops.unbox_i(value, tc), tc)
                SlotKind.NUM ->
                    Ops.bindattr_n(self, attrPackage, varName, Ops.unbox_n(value, tc), tc)
                SlotKind.STR ->
                    Ops.bindattr_s(self, attrPackage, varName, Ops.unbox_s(value, tc), tc)
                else -> {
                    assignee = self!!.get_attribute_boxed(tc, attrPackage, varName, STable.NO_HINT)
```

(the `else` arm continues exactly as the old `else` did). Imports: `org.raku.nqp.sixmodel.reprs.RakuObjectREPRData`, `SlotKind`; drop `P6OpaqueREPRData`, `P6int`, `P6num`, `P6str` if nothing else uses them.

- [ ] **Step 2: `RakudoContainerSpec.kt:108-140`:**

```kotlin
    /* Atomic operations. */

    /* The slot of Scalar's $!value, resolved from the first container seen
     * (formerly a VarHandle on the generated class's field_1). The slot
     * number is per STable and the same on every layout of the type, so a
     * container on a variant layout (a reblessed Scalar) reads through its
     * own layout's placement. */
    @Volatile private var scalarValueSlot: Int = -1

    private fun valueSlot(cont: RakuObject): Int {
        var slot = scalarValueSlot
        if (slot < 0) {
            slot = cont.layout!!.slotForName("\$!value")
            if (slot < 0) throw RuntimeException("Scalar container has no \$!value slot")
            scalarValueSlot = slot
        }
        return slot
    }

    override fun cas(tc: ThreadContext, cont: SixModelObject,
                     expected: SixModelObject, value: SixModelObject): SixModelObject? {
        Ops.invokeDirect(tc, cas, CAS, arrayOf<Any?>(cont, expected, value))
        return Ops.result_o(tc.curFrame!!)
    }

    override fun atomic_load(tc: ThreadContext, cont: SixModelObject): SixModelObject? {
        val o = cont as RakuObject
        return o.layout!!.getVolatile(o, valueSlot(o)) as SixModelObject?
    }

    override fun atomic_store(tc: ThreadContext, cont: SixModelObject, value: SixModelObject) {
        Ops.invokeDirect(tc, atomicStore, STORE, arrayOf<Any?>(cont, value))
    }
```

Drop the `VarHandle`/`Field`/`MethodHandles` imports; add `org.raku.nqp.sixmodel.reprs.RakuObject`.

- [ ] **Step 3: `t/02-rakudo/10-nqp-ops.t:10`.** The todo text names the old exception class; replace `org.raku.nqp.sixmodel.reprs.P6OpaqueBaseInstance$BadReferenceRuntimeException: Cannot access a native attribute as a reference attribute` with `Cannot access a native attribute as a reference attribute` (the message is unchanged, the class prefix is gone). `grep -rn 'P6Opaque\|field_1' src/vm/jvm t/02-rakudo` must be empty after.

- [ ] **Step 4: the make.** The Rakudo runtime jar is what changed; the settings are unit artifacts that do not depend on it, but the Makefile's dependency graph may recompile them because the jar is newer: let it (forward only) and record the time.

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/5c60252a/tmp/t4-make.log --show='Compiling' --show='rror' --show='Stage' --max=2400 -- make
```

Expected `EXIT=0`. If CORE.c did recompile, its `Stage` times are the milestone's first compile-clock row (baseline 467 s). Restart any eval server.

- [ ] **Step 5: the CORE.c variant count and the fast Rakudo gates.**

```
RAKUDO_RAKUAST=1 NQP_LAYOUT_STATS=1 ./rakudo-j -e 'say 1' 2>&1 | tail -2
```

Expected: `layout stats: layouts=N variants=0 reblesses=0`. `variants>0` after loading CORE.c is a gate failure: `NQP_LAYOUT_TRACE=1` names the type; the fix is in `peekAttributeShape` or in `deserialize_stub`'s class choice, never in the variant road. Then:

```
RAKUDO_RAKUAST=1 ./rakudo-j -Ilib t/02-rakudo/mixin-identity.t
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=t/01-sanity --jobs=2 --log-dir=/home/longwalker/.claude/jobs/5c60252a/tmp/t4-sanity --max=900 -- ./rakudo-j -Ilib
```

(25/25), and the milestone 4 sensitive slice, one file each through `./rakudo-j -Ilib`: `t/08-performance/22-rakuast-ct-dispatch.t`, `29-rakuast-attr-self-types.t`, `32-rakuast-native-param-bind.t` (all green), `t/02-rakudo/native-return-coercion.t` (19/23, unchanged), `t/02-rakudo/sort-element-kinds.t`, `t/02-rakudo/nested-invocation-continuation.t` (6/6), `t/02-rakudo/keep-undo.t` (16/16), and the BEGIN+where pair (`t/02-rakudo/21-begin-time-compile-sub.t` is a known red; the pair from milestone 4's gap 5c is the two files its ledger names under "where-in-BEGIN"). Record every count in the ledger.

- [ ] **Step 6: the "after" bench rows.** `RAKUDO_RAKUAST=1 NQP_DISPATCH_STATS=1 ./rakudo-j docs/bench/jesp/plusquick.raku` and `RAKUDO_RAKUAST=1 ./rakudo-j docs/bench/jesp/attrquick.raku`, one run each; ledger rows beside the "before" ones. A regression above 10 % on any row that was under 1000 ns/op before is investigated before Task 5 (`-Dpolyglot.compiler.TraceMethodExpansion=truffleTier -Dpolyglot.engine.CompileOnly=<root>` via `RAKUDO_JVM_XOPTS`, grep for `Intrinsics`, `StackTraceElement`, `resolve`, `invokeWithArguments` in the expansion: the expected culprits are a Kotlin null assertion or a `!!` on the fast road, or an un-folded `when` in `newInstance`).

- [ ] **Step 7: commit (rakudo):**

```
git add src/vm/jvm/runtime/org/raku/rakudo/Binder.kt src/vm/jvm/runtime/org/raku/rakudo/RakudoContainerSpec.kt t/02-rakudo/10-nqp-ops.t docs/superpowers/plans/2026-09-11-jvm-milestone-5-rakuobject-layout.ledger.md
git commit -m "JVM runtime: the binder and the container spec read the RakuObject layout; no field_1, no P6Opaque names"
```

---

### Task 5: The interop adaptor as one callout over plans (time-boxed)

**Time box:** one working session. If the gate is not green at its end, park: `CompUnit::Repository::JavaRuntime.need` dies with "Java interop is not available on this build" before calling `nqp::jvmrakudointerop`, `RakudoJavaInterop.kt`, `BootJavaInterop.kt`, `AdaptorUnit.kt`, `JavaObjectWrapper.kt`, `RakOps.jvmrakudointerop` and `t/03-jvm/01-interop.t` are deleted, `gcx.rakudoInterop` goes, and the ledger records the point reached. Task 6 proceeds either way.

**Files:**
- Create: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/JavaCallout.kt`
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/AdaptorUnit.kt` (whole), `BootJavaInterop.kt` (the ASM half, callin, proxy deleted; `createPlans` added), `src/vm/jvm/runtime/org/raku/rakudo/RakudoJavaInterop.kt` (`DispatchCallSite` becomes `MultiPlan`; overrides on plans), `src/vm/jvm/runtime/org/raku/rakudo/RakOps.kt` (unchanged unless a name moves), `t/03-jvm/01-interop.t` (one case added)
- Test: `t/03-jvm/01-interop.t`, `t/01-sanity`

**Interfaces:**
- Consumes: `Ops.checkarity/posparam_o/i/n/s/return_o/i/n/s/decont`, `CallFrame(tc, cr)`/`leave()`, `ExceptionHandling.dieInternal(tc, Throwable)`, `ControlException`, `BootJavaInterop.RuntimeSupport.boxJava/unboxJava`, `BootJavaInterop.STableCache`, `BootJavaInterop.marshalOutRecursive` (static, arrays), `RakudoJavaInterop.marshalOutRecursive/parseSingleArg/filterReturnValueMethod` (static, unchanged), `CompilationUnit`, `CodeRef(...)` ten-arg constructor, `ArgsExpectation.USE_BINDER`.
- Produces: `sealed class CalloutPlan(val descriptor: String)`; `class MemberPlan(descriptor, arity: Int, args: Array<ArgMarshal>, target: MethodHandle /*(Object[])Object*/, ret: RetMarshal)`; `abstract class VarArityPlan(descriptor) { abstract fun run(tc, cf, csd, args) }`; `sealed class ArgMarshal { abstract fun read(cf, csd, args, idx, tc): Any? }` with `LongArg(what)`, `NumArg(what)`, `StrArg`, `SmoArg`, `TcArg`, `GcArg`, `ArrayArg(what)`, `ObjectArg(what)`; `sealed class RetMarshal { abstract fun write(v, cf, tc) }` with `VoidRet`, `IntRet`, `NumRet`, `StrRet`, `SmoRet`, `CharRet`, `BoxRet(cache: BootJavaInterop.STableCache)`; `object JavaCallout { @JvmStatic fun invoke(plan, tc, cr, csd, args) }`; `AdaptorUnit(plans: List<CalloutPlan>, target: String)`; `BootJavaInterop.createPlans(target: Class<*>): MutableList<CalloutPlan>` (open; Rakudo overrides), `argMarshalFor(what)`, `retMarshalFor(what)`.

- [ ] **Step 1: `JavaCallout.kt`:**

```kotlin
package org.raku.nqp.runtime

import java.lang.invoke.MethodHandle
import java.lang.invoke.MethodHandles
import java.lang.invoke.MethodType
import org.raku.nqp.sixmodel.SixModelObject
import org.raku.nqp.sixmodel.reprs.JavaObjectWrapper

/**
 * The Java-interop callout: one hand-written entry over a plan per Java
 * member, replacing the ASM-generated qb_N statics. Same convention as
 * before -- USE_BINDER: the raw argument list arrives, the callout opens a
 * CallFrame, checks arity, reads each positional through the binder's
 * reads, converts per parameter, calls the member, converts the result and
 * returns it through the frame.
 */
sealed class CalloutPlan(@JvmField val descriptor: String)

/** A fixed-arity member: method, constructor, field get/set, or a special.
 *  Positional argStart+i is read into Java argument i: 0 for an instance
 *  member (slot 0 is the invocant), 1 for a static, a constructor or a
 *  special (slot 0 is the type object and is skipped, as before). */
class MemberPlan(
    descriptor: String,
    @JvmField val arity: Int,
    @JvmField val argStart: Int,
    @JvmField val args: Array<ArgMarshal>,
    /** (Object[])Object over the marshalled Java values. */
    @JvmField val target: MethodHandle,
    @JvmField val ret: RetMarshal,
) : CalloutPlan(descriptor)

/** A callout that binds its own arguments (the Rakudo multi-dispatchers). */
abstract class VarArityPlan(descriptor: String) : CalloutPlan(descriptor) {
    abstract fun run(tc: ThreadContext, cf: CallFrame, csd: CallSiteDescriptor, args: Array<Any?>)
}

/** How one Java parameter is read out of the Raku argument list. The cases
 *  are BootJavaInterop.marshalOut's, one class each. */
sealed class ArgMarshal {
    abstract fun read(cf: CallFrame, csd: CallSiteDescriptor, args: Array<Any?>, idx: Int, tc: ThreadContext): Any?

    /** long/int/short/byte/boolean from an int positional. */
    class LongArg(private val what: Class<*>) : ArgMarshal() {
        override fun read(cf: CallFrame, csd: CallSiteDescriptor, args: Array<Any?>, idx: Int, tc: ThreadContext): Any? {
            val v = Ops.posparam_i(cf, csd, args, idx)
            return when (what) {
                java.lang.Long.TYPE -> v
                Integer.TYPE -> v.toInt()
                java.lang.Short.TYPE -> v.toShort()
                java.lang.Byte.TYPE -> v.toByte()
                else -> v != 0L    // boolean
            }
        }
    }
    /** double/float from a num positional. */
    class NumArg(private val what: Class<*>) : ArgMarshal() {
        override fun read(cf: CallFrame, csd: CallSiteDescriptor, args: Array<Any?>, idx: Int, tc: ThreadContext): Any? {
            val v = Ops.posparam_n(cf, csd, args, idx)
            return if (what == java.lang.Float.TYPE) v.toFloat() else v
        }
    }
    /** String, or char as the first character. */
    class StrArg(private val asChar: Boolean) : ArgMarshal() {
        override fun read(cf: CallFrame, csd: CallSiteDescriptor, args: Array<Any?>, idx: Int, tc: ThreadContext): Any? {
            val s = Ops.posparam_s(cf, csd, args, idx)
            return if (asChar) s!![0] else s
        }
    }
    /** A SixModelObject parameter: passed through. */
    object SmoArg : ArgMarshal() {
        override fun read(cf: CallFrame, csd: CallSiteDescriptor, args: Array<Any?>, idx: Int, tc: ThreadContext): Any? =
            Ops.posparam_o(cf, csd, args, idx)
    }
    /** ThreadContext / GlobalContext: the current one when null was passed. */
    class ContextArg(private val what: Class<*>) : ArgMarshal() {
        override fun read(cf: CallFrame, csd: CallSiteDescriptor, args: Array<Any?>, idx: Int, tc: ThreadContext): Any? {
            val v = Ops.posparam_o(cf, csd, args, idx)
            if (v == null) return if (what == ThreadContext::class.java) tc else tc.gc
            return what.cast(BootJavaInterop.RuntimeSupport.unboxJava(v))
        }
    }
    /** A Java array (or, in Rakudo, a List/Map) built from a Raku list. */
    class ArrayArg(private val what: Class<*>, private val recurse: (SixModelObject, ThreadContext, Class<*>) -> Any?) : ArgMarshal() {
        override fun read(cf: CallFrame, csd: CallSiteDescriptor, args: Array<Any?>, idx: Int, tc: ThreadContext): Any? {
            val v = Ops.posparam_o(cf, csd, args, idx)!!
            return what.cast(recurse(v, tc, what))
        }
    }
    /** Anything else: a wrapped Java object is unboxed, a Raku object goes
     *  as itself, and the cast to the parameter type fails at run time for
     *  a non-Java object where a Java one is needed (as before). */
    class ObjectArg(private val what: Class<*>) : ArgMarshal() {
        override fun read(cf: CallFrame, csd: CallSiteDescriptor, args: Array<Any?>, idx: Int, tc: ThreadContext): Any? {
            val v = Ops.posparam_o(cf, csd, args, idx)
            val d = Ops.decont(v, tc)
            val out: Any? = if (d is JavaObjectWrapper) BootJavaInterop.RuntimeSupport.unboxJava(d) else v
            return what.cast(out)
        }
    }
}

/** How a Java result goes back through the frame: BootJavaInterop.marshalIn's cases. */
sealed class RetMarshal {
    abstract fun write(v: Any?, cf: CallFrame, tc: ThreadContext)
    object VoidRet : RetMarshal() { override fun write(v: Any?, cf: CallFrame, tc: ThreadContext) = Ops.return_o(null, cf) }
    object IntRet : RetMarshal() {
        override fun write(v: Any?, cf: CallFrame, tc: ThreadContext) = Ops.return_i(
            when (v) { is Long -> v; is Int -> v.toLong(); is Short -> v.toLong(); is Byte -> v.toLong(); is Boolean -> if (v) 1L else 0L
                       else -> throw IllegalStateException("interop: not an int result: $v") }, cf)
    }
    object NumRet : RetMarshal() {
        override fun write(v: Any?, cf: CallFrame, tc: ThreadContext) = Ops.return_n(
            when (v) { is Double -> v; is Float -> v.toDouble(); else -> throw IllegalStateException("interop: not a num result: $v") }, cf)
    }
    object StrRet : RetMarshal() { override fun write(v: Any?, cf: CallFrame, tc: ThreadContext) = Ops.return_s(v as String?, cf) }
    object CharRet : RetMarshal() { override fun write(v: Any?, cf: CallFrame, tc: ThreadContext) = Ops.return_s((v as Char).toString(), cf) }
    object SmoRet : RetMarshal() { override fun write(v: Any?, cf: CallFrame, tc: ThreadContext) = Ops.return_o(v as SixModelObject?, cf) }
    class BoxRet(private val cache: BootJavaInterop.STableCache) : RetMarshal() {
        override fun write(v: Any?, cf: CallFrame, tc: ThreadContext) =
            Ops.return_o(BootJavaInterop.RuntimeSupport.boxJava(v, cache.getSTable()), cf)
    }
}

object JavaCallout {
    /** The handle AdaptorUnit binds a plan into: after insertArguments(0, plan)
     *  its type is (ThreadContext, CodeRef, CallSiteDescriptor, Object[])void,
     *  which is exactly what USE_BINDER invokeExacts. */
    @JvmField val INVOKE: MethodHandle = MethodHandles.lookup().findStatic(JavaCallout::class.java, "invoke",
        MethodType.methodType(Void.TYPE, CalloutPlan::class.java, ThreadContext::class.java, CodeRef::class.java,
            CallSiteDescriptor::class.java, Array<Any?>::class.java))

    @JvmStatic
    fun invoke(plan: CalloutPlan, tc: ThreadContext, cr: CodeRef, csd0: CallSiteDescriptor, args0: Array<Any?>) {
        val cf = CallFrame(tc, cr)
        try {
            when (plan) {
                is MemberPlan -> {
                    val csd = Ops.checkarity(cf, csd0, args0, plan.arity, plan.arity)
                    val args = tc.flatArgs!!
                    val jargs = arrayOfNulls<Any>(plan.args.size)
                    for (i in plan.args.indices) jargs[i] = plan.args[i].read(cf, csd, args, plan.argStart + i, tc)
                    val result = plan.target.invokeExact(jargs)
                    plan.ret.write(result, cf, tc)
                }
                is VarArityPlan -> {
                    val csd = Ops.checkarity(cf, csd0, args0, 1, -1)
                    plan.run(tc, cf, csd, tc.flatArgs!!)
                }
            }
            cf.leave()
        }
        catch (t: Throwable) {
            cf.leave()
            if (t is ControlException) throw t
            throw ExceptionHandling.dieInternal(tc, t)
        }
    }
}
```

(`plan.target.invokeExact(jargs)` needs the target typed exactly `(Object[])Object`: see Step 3's `spread`. Kotlin's `invokeExact` is a polymorphic-signature call; the result is `Any?` and the argument's static type `Array<Any?>` matches `Object[]`.)

- [ ] **Step 2: `AdaptorUnit.kt`:**

```kotlin
package org.raku.nqp.runtime

import java.lang.invoke.MethodHandles

/**
 * The unit behind a Java-interop adaptor: one code ref per plan, built from
 * JavaCallout.INVOKE with the plan bound in. No generated class, no
 * reflection over annotations: the same road KnowHOWMethods takes.
 */
class AdaptorUnit(
    private val plans: List<CalloutPlan>,
    private val target: String,
) : CompilationUnit() {
    override fun getCodeRefs(): Array<CodeRef> {
        val snull: Array<String>? = null
        val hnull = arrayOf<LongArray>()
        return Array(plans.size) { i ->
            val name = "callout $target ${plans[i].descriptor}"
            val mh = MethodHandles.insertArguments(JavaCallout.INVOKE, 0, plans[i])
            CodeRef(this, mh, name, name, snull, snull, snull, snull, hnull, 0.toShort())
        }
    }
    override fun getCallSites(): Array<CallSiteDescriptor> = emptyArray()
    override fun hllName(): String = ""
    override fun unitId(): String = "adaptor:$target"
}
```

- [ ] **Step 3: `BootJavaInterop.kt`.** Delete: the ASM imports; `implementClass`, `matchName`, `methodCallin`, `typeToClass`, `finishClass`, `createAdaptor`, `createAdaptorMethod/Field/Constructor/Specials`, `preMarshalIn`, `marshalIn`, `marshalOut`, `startCallout`, `endCallout`, `startCallin`, `endCallin`, `setupCallback`, `fireCallback`, `emitInteger`, `emitConst`, `emitGetFromNQP`, `preEmitPutToNQP`, `emitPutToNQP`, `ClassContext`, `MethodContext`, the `TYPE_*`/`TYPES`/`TYPE_CHAR`/`TYPE_argflag` constants, `proxyClasses`, `proxy`, `proxyGetMethods`, `computeProxyClass`, `createProxyMethod`, `commonSTable`, `jarClassLoaders`, and the `NQP_DEBUG_DUMP_CLASSFILES` code. Keep: the class header and `gc`, `InteropInfo`, `cache`, `computeSTable`, `getSTableForClass`, `getInteropForClass`, `typeForName`, `currentGC`, `currentTC`, `unboxClass`, `getInterop`, `sixmodelToJavaObject`, `javaObjectToSixmodel`, `computeHOW`, `storageForType`, `castObjectToClass`, `marshalOutRecursive` (companion, static), `RuntimeSupport`, `STableCache`. `computeInterop` (:223-262) changes its first three lines to:

```kotlin
        val plans = createPlans(klass)
        val adaptorUnit = AdaptorUnit(plans, klass.getName())
        adaptorUnit.initializeCompilationUnit(tc)
```

and iterates `plans[i].descriptor` where it iterated `adaptor.descriptors[i]`. Add the plan builders:

```kotlin
    /** One plan per public method, field (get, and set unless final),
     *  constructor, plus the three specials. Rakudo overrides to add its
     *  multi-dispatchers. */
    protected open fun createPlans(target: Class<*>): MutableList<CalloutPlan> {
        val plans = ArrayList<CalloutPlan>()
        for (m in target.getMethods()) plans.add(methodPlan(m))
        for (f in target.getFields()) { plans.add(fieldGetPlan(f)); if (!Modifier.isFinal(f.getModifiers())) plans.add(fieldSetPlan(f)) }
        for (c in target.getConstructors()) plans.add(constructorPlan(c))
        plans.addAll(specialPlans(target))
        return plans
    }

    private val lookup = MethodHandles.lookup()
    private val SPREAD = MethodType.methodType(Any::class.java, Array<Any?>::class.java)

    /** A member handle spread over an Object[] of its arguments, typed (Object[])Object. */
    protected fun spread(mh: MethodHandle): MethodHandle =
        mh.asType(mh.type().generic()).asSpreader(Array<Any?>::class.java, mh.type().parameterCount()).asType(SPREAD)

    /** Descriptor strings are keys the Raku side uses verbatim
     *  ("method/valueOf/(Z)Ljava/lang/String;" in the test), so they stay
     *  byte-identical to what ASM's Type.getMethodDescriptor produced;
     *  Class.descriptorString() (JDK 12+) yields the same text. */
    protected fun jvmDescriptor(m: Method): String =
        m.getParameterTypes().joinToString("", "(", ")") { it.descriptorString() } + m.getReturnType().descriptorString()
    protected fun jvmDescriptor(c: Constructor<*>): String =
        c.getParameterTypes().joinToString("", "(", ")") { it.descriptorString() } + "V"

    protected open fun methodPlan(m: Method): MemberPlan {
        val isStatic = Modifier.isStatic(m.getModifiers())
        val ptypes = m.getParameterTypes()
        val args = ArrayList<ArgMarshal>()
        /* Slot 0 is the invocant even for a static (the type object): the
         * arity counts it; an instance method marshals it, a static skips it. */
        if (!isStatic) args.add(argMarshalFor(m.getDeclaringClass()))
        for (p in ptypes) args.add(argMarshalFor(p))
        return MemberPlan("method/" + m.getName() + "/" + jvmDescriptor(m), ptypes.size + 1, if (isStatic) 1 else 0,
            args.toTypedArray(), spread(lookup.unreflect(m)), retMarshalFor(m.getReturnType()))
    }

```

```kotlin
    protected open fun fieldGetPlan(f: Field): MemberPlan {
        val isStatic = Modifier.isStatic(f.getModifiers())
        val args = if (isStatic) emptyList<ArgMarshal>() else listOf(argMarshalFor(f.getDeclaringClass()))
        var target = lookup.unreflectGetter(f)
        return MemberPlan("field/get_" + f.getName() + "/" + f.getType().descriptorString(), 1, if (isStatic) 1 else 0,
            args.toTypedArray(), spread(target), retMarshalFor(f.getType()))
    }
    protected open fun fieldSetPlan(f: Field): MemberPlan {
        val isStatic = Modifier.isStatic(f.getModifiers())
        val args = (if (isStatic) emptyList() else listOf(argMarshalFor(f.getDeclaringClass()))) + argMarshalFor(f.getType())
        return MemberPlan("field/set_" + f.getName() + "/" + f.getType().descriptorString(), 2, if (isStatic) 1 else 0,
            args.toTypedArray(), spread(lookup.unreflectSetter(f)), RetMarshal.VoidRet)
    }
    protected open fun constructorPlan(k: Constructor<*>): MemberPlan {
        val ptypes = k.getParameterTypes()
        return MemberPlan("constructor/new/" + jvmDescriptor(k), ptypes.size + 1, 1,
            ptypes.map { argMarshalFor(it) }.toTypedArray(), spread(lookup.unreflectConstructor(k)), retMarshalFor(k.getDeclaringClass()))
    }
    protected open fun specialPlans(target: Class<*>): List<CalloutPlan> {
        val box = lookup.findStatic(BootJavaInterop::class.java, "special_box", MethodType.methodType(Any::class.java, Any::class.java))
        val unbox = lookup.findStatic(BootJavaInterop::class.java, "special_unbox", MethodType.methodType(Any::class.java, Class::class.java, Any::class.java))
        val isinst = lookup.findStatic(BootJavaInterop::class.java, "special_isinst", MethodType.methodType(java.lang.Boolean.TYPE, Class::class.java, Any::class.java))
        return listOf(
            MemberPlan("/box/", 2, 1, arrayOf(argMarshalFor(target)), spread(box), RetMarshal.BoxRet(STableCache(Any::class.java))),
            MemberPlan("/unbox/", 2, 1, arrayOf(ArgMarshal.ObjectArg(Any::class.java)), spread(MethodHandles.insertArguments(unbox, 0, target)), RetMarshal.BoxRet(STableCache(target))),
            MemberPlan("/isinst/", 2, 1, arrayOf(ArgMarshal.ObjectArg(Any::class.java)), spread(MethodHandles.insertArguments(isinst, 0, target)), RetMarshal.IntRet),
        )
    }

    companion object {
        @JvmStatic fun special_box(o: Any?): Any? = o
        @JvmStatic fun special_unbox(target: Class<*>, o: Any?): Any? = target.cast(o)
        @JvmStatic fun special_isinst(target: Class<*>, o: Any?): Boolean = target.isInstance(o)
        ...
    }

    /** marshalOut's cases, as data. */
    protected open fun argMarshalFor(what: Class<*>): ArgMarshal = when {
        what == java.lang.Long.TYPE || what == Integer.TYPE || what == java.lang.Short.TYPE
            || what == java.lang.Byte.TYPE || what == java.lang.Boolean.TYPE -> ArgMarshal.LongArg(what)
        what == java.lang.Double.TYPE || what == java.lang.Float.TYPE -> ArgMarshal.NumArg(what)
        what == String::class.java -> ArgMarshal.StrArg(false)
        what == Character.TYPE -> ArgMarshal.StrArg(true)
        what == SixModelObject::class.java -> ArgMarshal.SmoArg
        what == ThreadContext::class.java || what == GlobalContext::class.java -> ArgMarshal.ContextArg(what)
        what.componentType != null -> ArgMarshal.ArrayArg(what) { smo, tc, cls -> marshalOutRecursive(smo, tc, cls) }
        else -> ArgMarshal.ObjectArg(what)
    }

    /** marshalIn's cases, as data. */
    protected open fun retMarshalFor(what: Class<*>): RetMarshal = when {
        what == Void.TYPE -> RetMarshal.VoidRet
        what == Integer.TYPE || what == java.lang.Short.TYPE || what == java.lang.Byte.TYPE
            || what == java.lang.Boolean.TYPE || what == java.lang.Long.TYPE -> RetMarshal.IntRet
        what == java.lang.Double.TYPE || what == java.lang.Float.TYPE -> RetMarshal.NumRet
        what == String::class.java -> RetMarshal.StrRet
        what == Character.TYPE -> RetMarshal.CharRet
        what == SixModelObject::class.java -> RetMarshal.SmoRet
        else -> RetMarshal.BoxRet(STableCache(what))
    }
```

(`special_box`'s `/box/` reads its argument with the target's own marshal and returns it boxed under `Object`'s STable, as the old `/box/` did; the `SPREAD` for a one-argument static handle spreads a one-element array.) Where the old `marshalOut` for `SixModelObject`/long/double/String passed values "already in needed form", `LongArg(Long.TYPE)`, `NumArg(Double.TYPE)`, `StrArg(false)`, `SmoArg` do the same.

- [ ] **Step 4: `RakudoJavaInterop.kt`.** Delete the ASM imports, the `invokedynamic` bootstraps (`multiBootstrap`, `constructorBootstrap`), `marshalOut` (the override), `startVarArityCallout`, `createAdaptorMultiDispatch`, `createConstructorDispatchAdaptor`, the `createAdaptor` override. `DispatchCallSite` becomes:

```kotlin
    /** One overloaded name's dispatcher: today's selection (descriptor
     *  match, then the casting pass) with the chosen candidate cached per
     *  tuple of argument classes for exact matches. */
    class MultiPlan : VarArityPlan {
        private val methname: String
        private val handleList: Array<*>?
        private val forCtors: Boolean
        private val declaringClass: String?
        private var handleDescs: Array<String?>? = null
        private val exact = HashMap<List<Class<*>?>, Int>()

        constructor(descriptor: String, methname: String, handleList: Array<*>) : super(descriptor) {
            this.methname = methname; this.handleList = handleList; this.forCtors = false; this.declaringClass = null
        }
        constructor(descriptor: String, methname: String, declaringClass: String) : super(descriptor) {
            this.methname = methname; this.handleList = null; this.forCtors = true; this.declaringClass = declaringClass
        }

        override fun run(tc: ThreadContext, cf: CallFrame, csd: CallSiteDescriptor, args: Array<Any?>) {
            val parsed = parseArgArray(tc, args)
            val key = parsed.map { it?.javaClass }
            var pos = exact[key] ?: -1
            if (pos < 0) {
                pos = findHandle(tc, parsed)
                if (pos >= 0) exact[key] = pos
                else pos = findHandleWithArgsCasting(tc, parsed)
                if (pos < 0) failDispatch(tc, parsed)
            }
            val result = if (forCtors) ctorList(tc)[pos].newInstance(*parsed)
                         else (handleList!![pos] as MethodHandle).invokeWithArguments(*parsed)
            filterReturnValueMethod(result, tc)
        }
        ...
    }
```

where `parseArgArray`, `findHandle`, `argsMatch`, `deepArrayCast` (both), `castObjectToType`, `findHandleWithArgsCasting`, `failDispatch` are the old bodies with `tc` passed as a parameter instead of read from a field, `offset` a local, `Class.forName(x, false, tc!!.gc.byteClassLoader)` replaced by `Class.forName(x, false, ClassLoader.getSystemClassLoader())`, ASM's `Type` replaced: `Type.getType(arg.javaClass)` by `arg.javaClass.descriptorString()`, `Type.getConstructorDescriptor(c)` by `jvmDescriptor(c)`, `(handle as MethodHandle).type().toMethodDescriptorString()` unchanged (JDK API), and `castObjectToType(obj, type: Type)`'s `when (type.sort)` by a `when` over the descriptor's first character (`'Z'`, `'B'`, `'S'`, `'I'`, `'J'`, `'C'`, `'F'`, `'D'`, `'L'`, `'['`) with the class name for `'L'` taken from the descriptor (`desc.substring(1, desc.length - 1).replace('/', '.')`). `ctorList(tc)` is `Class.forName(declaringClass, false, ClassLoader.getSystemClassLoader()).constructors` as the old `fallback` computed. `filterReturnValueMethod` is unchanged and called directly (no per-call lookup). The `createPlans` override:

```kotlin
    override fun createPlans(target: Class<*>): MutableList<CalloutPlan> {
        val plans = ArrayList<CalloutPlan>()
        val counts = HashMap<String, Int>()
        for (m in target.methods) counts[m.name] = (counts[m.name] ?: 0) + 1
        val multi = HashMap<String, ArrayList<Method>>()
        for (m in target.methods) {
            if (m.isSynthetic) continue
            if (counts[m.name]!! > 1) multi.getOrPut(m.name) { ArrayList() }.add(m)
            plans.add(methodPlan(m))
        }
        for ((name, ms) in multi) {
            val handles = Array<Any?>(ms.size) { MethodHandles.lookup().unreflect(ms[it]) }
            plans.add(MultiPlan("method/mmd+$name/([Ljava/lang/Object;)Ljava/lang/Object;", name, handles))
        }
        for (f in target.fields) { if (f.isSynthetic) continue; plans.add(fieldGetPlan(f)); if (!Modifier.isFinal(f.modifiers)) plans.add(fieldSetPlan(f)) }
        for (c in target.constructors) { if (c.isSynthetic) continue; plans.add(constructorPlan(c)) }
        if (target.constructors.isNotEmpty())
            plans.add(MultiPlan("method/mmd+new/([Ljava/lang/Object;)L" + target.name.replace('.', '/') + ";", "new", target.name))
        plans.addAll(specialPlans(target))
        return plans
    }
```

and `argMarshalFor` override: `if (what.componentType != null || java.util.List::class.java.isAssignableFrom(what) || java.util.Map::class.java.isAssignableFrom(what)) ArgMarshal.ArrayArg(what) { smo, tc, cls -> RakudoJavaInterop.marshalOutRecursive(smo, tc, cls) } else super.argMarshalFor(what)`. `computeInterop`'s first lines become the plan form as in Step 3; the rest (aliases, `mmd+` handling, JavaHOW attributes) is unchanged. Note the old `mmd+` selection relied on the descriptor's `"mmd+"` prefix: keep the descriptors exactly as above.

- [ ] **Step 5: the interop gate.** Runtime jars (nqp) + the Rakudo runtime jar (`make`, which sees only `RakudoJavaInterop.kt` changed):

```
./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars 2>&1 | tail -5
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/5c60252a/tmp/t5-make.log --show='Compiling' --show='rror' --max=2400 -- make
RAKUDO_RAKUAST=1 ./rakudo-j -Ilib t/03-jvm/01-interop.t
```

Expected: 30 planned, 8 skipped, 22 ok, no failures. Add the multi-dispatch caching case to the test (bump `plan 30` to `plan 32`):

```raku
{
    use java::lang::String:from<JavaRuntime>;
    is String.valueOf(True), "true", "first overload selection";
    is String.valueOf(42), "42", "a second argument-class tuple selects a different overload";
}
```

Then `t/01-sanity` (25/25) as in Task 4 Step 5.

- [ ] **Step 6: commit.** nqp: `git add -A src/vm/jvm/runtime/org/raku/nqp/runtime && git commit -m "interop: one hand-written JavaCallout over per-member plans; the ASM adaptor generator, the callin and proxy roads are gone"`; rakudo: `git add src/vm/jvm/runtime/org/raku/rakudo/RakudoJavaInterop.kt t/03-jvm/01-interop.t && git commit -m "JVM interop: Rakudo's multi-dispatchers are plans with a per-argument-class cache; no invokedynamic, no ASM"`.

---

### Task 6: ASM out of the build; the last dynamic pieces deleted

**Files:**
- Delete: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/ByteClassLoader.kt`, `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/BytecodeVersion.kt`, `nqp/3rdparty/asm/` (the whole directory)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/GlobalContext.kt:197-201, 300`; `nqp/buildSrc/src/main/kotlin/NqpDeps.kt:14-15, 27, 39-44`; `nqp/tools/lib/NQP/Config/NQP.pm:247-248`; `nqp/tools/templates/jvm/Makefile.in:13-14`; `nqp/tools/templates/jvm/nqp-j.in:35`; `nqp/docs/gradle-jvm-build.md` (the ASM paragraph)
- Test: a clean nqp build, t/nqp, the ASM census

**Interfaces:**
- Consumes: Tasks 2 and 5 done (no `org.objectweb.asm` import left in either tree).
- Produces: a build without ASM; `nqp/build/jvm/share/runtime/` without `asm*.jar`.

- [ ] **Step 1: the census must already be clean.** `grep -rn 'org.objectweb.asm\|ClassWriter\|MethodVisitor' nqp/src/vm/jvm src/vm/jvm nqp/nqp-truffle/src` empty. If not, the hit is a Task 2 or 5 leftover: fix it there (amend that commit).

- [ ] **Step 2: delete the loader and the version constant.** nqp dir: `git rm src/vm/jvm/runtime/org/raku/nqp/runtime/ByteClassLoader.kt src/vm/jvm/runtime/org/raku/nqp/runtime/BytecodeVersion.kt`. In `GlobalContext.kt` delete the `byteClassLoader` declaration (:197-201) and its initialisation (:300). `grep -rn 'byteClassLoader\|BytecodeVersion\|defineClass' nqp/src src/vm/jvm nqp/nqp-truffle/src` empty.

- [ ] **Step 3: the dependency.** `NqpDeps.kt`: delete the two `org.ow2.asm` lines from `thirdParty`, `"asm", "asm-tree",` from `moduleOrder`, and the comment block at :39-44 about asm-tree; `runnerJars` stays. `nqp/tools/lib/NQP/Config/NQP.pm:247-248`: delete the `asm` and `'asm-tree'` entries. `nqp/tools/templates/jvm/Makefile.in:13-14`: delete `ASM = @asm@` and `ASMTREE = @asmtree@`, then `grep -n 'ASM\|asm' nqp/tools/templates/jvm/Makefile.in` and delete every remaining use (classpath lists). `nqp/tools/templates/jvm/nqp-j.in:35`: delete the `@cpsep@@nfp(@envvar(JAR_DIR)@/@asmfile@)@` fragment. `git rm -r 3rdparty/asm` (nqp dir). `nqp/docs/gradle-jvm-build.md:108-118`: the paragraph saying ASM stays for P6Opaque and the adaptors becomes one sentence: "No runtime class generation remains; ASM is not a dependency (milestone 5, 2026-09)."

- [ ] **Step 4: the proof build.** A clean nqp build is the proof that nothing needed ASM (the stage compiles run the whole compiler on the new runtime):

```
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/5c60252a/tmp/t6-nqp-clean.log --show='Task' --show='rror' --show='BUILD' --max=1200 -- ./nqp/gradlew -p nqp clean buildJvm
```

Expected `BUILD SUCCESSFUL` (baseline 253 s; record the time). Then `ls nqp/build/jvm/share/runtime/` shows no `asm*.jar`; `raku tools/build/jar-census.raku nqp/build/jvm/share/lib/*.jar` (every jar `meta=1 class=0` as before); and the nqp suite as in Task 3 Step 4 (`testNqp`, expect the same result). Rakudo must be remade after an nqp clean build (SC handles change):

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/5c60252a/tmp/t6-make.log --show='Compiling' --show='rror' --show='Stage' --max=2400 -- make
```

Record `make` from the top and the CORE.c `Stage` times (baseline 1142 s / 467 s; the second compile-clock row). `t/01-sanity` 25/25; restart eval servers.

- [ ] **Step 5: commit (nqp):**

```
git add -A src/vm/jvm/runtime buildSrc tools/lib/NQP/Config/NQP.pm tools/templates/jvm docs/gradle-jvm-build.md 3rdparty
git commit -m "build: ASM is gone; ByteClassLoader and BytecodeVersion with it -- nothing generates a class at run time"
```

---

### Task 7: The milestone gate, docs, ledger, memory, handoff

**Files:**
- Modify: `docs/jvm-truffle-only-plan.md` (position rows for items 8 and 9; the "9" entry in "The list"), `docs/jvm-jesp.md:787-818` (the object-model section: DynamicObject is no longer the idea, the layout is the fact), `docs/superpowers/specs/2026-09-11-jvm-unit-artifact-milestone-5-design.md` (a "Done" section), the ledger, `CLAUDE.md` (only if a rule changed: none is expected)
- Test: one t/ sweep

- [ ] **Step 1: the t/ sweep.** Through the eval server, as milestone 4 ran it (two servers at 4 GB when MemAvailable is around 20 GB; the sweep budgets itself):

```
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/5c60252a/tmp/t7-sweep.log --show='FAIL' --show='chunk' --max=7800 -- raku tools/build/evalserver-sweep.raku --jobs=2 --heap=4 --max=7200 t/01-sanity t/02-rakudo t/04-nativecall t/05-messages t/06-telemetry t/07-pod-to-text t/08-performance t/10-qast t/13-experimental t/14-smoke t/03-jvm
```

(check `raku tools/build/evalserver-sweep.raku --help` for the exact flag spellings before launching; a second invocation covers directories the 7200 s ceiling cut off, as in milestone 4). Progress every 90 s. Diff the red list against milestone 4's (the corekeys/settingkeys cluster of 7, `t/05-messages/02-errors.t`, `t/08-performance/15-rakuast-native-metaop.t`, `36-rakuast-begin-compiled-remark.t`, `begin-called-block-routine.t`, `compiler-frontend-id.t`, `constant-anon-var-value.t`, `parse-target-match-tree.t`, `21-begin-time-compile-sub.t`, `custom-declarator-naming.t`, `make-regex-frame.t`, `try-statement-backtrace-frame.t`, `regex-interpolation-backtrack.t`, `m-flag-module-spec.t`, `native-return-coercion.t` at 19/23). Any new red is root-caused before the milestone closes; a fix is a normal commit in the task whose code it touches.

- [ ] **Step 2: docs.** `docs/jvm-truffle-only-plan.md`: item 9's entry becomes "**DONE 2026-09-xx (milestone 5).** P6Opaque objects are `RakuObject`s on a static class family with a per-STable `RakuObjectLayout`; the interop adaptor is `JavaCallout` over plans; ASM is not a dependency and nothing generates a class at run time." Item 8's "ASM stays" sentence is struck. The Position table gets the same row plus the timings. `docs/jvm-jesp.md:787-818`: replace the three bullets with a paragraph pointing at `RakuObjectLayout.kt`'s class comment and the spec. The spec gets a "## Done" section with the numbers (nqp clean build, `make`, CORE.c, both benches before/after, gates, the sweep's diff), the parked residuals, and the plan rulings that mattered in practice.

- [ ] **Step 3: ledger and memory.** The ledger gets every ruling made during execution and every deferred minor. The memory file `milestone-5-rakuobject-layout.md` (in the Claude memory directory) gets a "DONE" line with hashes and numbers; `unit-artifact-milestones.md` and `truffle-plan-position.md` get one-line updates; `MEMORY.md`'s index line for milestone 5 says DONE.

- [ ] **Step 4: commit and handoff.** rakudo: `git add docs && git commit -m "docs: milestone 5 closed -- the RakuObject layout, JavaCallout, ASM gone; numbers and the sweep diff"`. Then the handoff rule: rebase both trees onto their upstream mains (`git fetch upstream` in each; `git rebase upstream/main`), re-run `t/01-sanity` if the rebase touched runtime files, and `git push --force-with-lease ab5tract worktree-jesp-direct-lazy-records` (rakudo) / `git push --force-with-lease ab5tract jesp-direct-lazy-records` (nqp). Remind the user to leave the session rather than `/clear`.

---

## Self-review (run before handing the plan to an executor)

**Spec coverage:** §1 instance model and layout → Task 2 Steps 1-4; §2 fast sites and ops → Task 2 Steps 7-8 (ops), Task 3 (sites), Task 4 Steps 1-2 (Rakudo consumers); §3 mixins/serialization/repossession → Task 2 Steps 4, 6, 10 and Task 3's variant check; §4 interop → Task 5; §5 ASM removal → Task 6; §6 error handling → Task 2 Steps 1-2 (validation, error texts, fail-closed sites), Task 3 (pinning), Task 5 Step 1 (exception split); §7 tests and gates → Task 1 (tests, bench), the per-task gates, Task 7 Step 1. The rename table → Task 2. The "one layout per STable" rule → `compose`'s "already composed" check (Task 2 Step 4).

**Type consistency checked:** `RakuObjectLayout(st, classId, kinds, specs, slotSTables, autoViv, classHandles, nameToSlot, mi, unboxIntSlot, unboxNumSlot, unboxStrSlot, unboxObjSlot, posDelSlot, assDelSlot, variant)` is the constructor used by `install`, `layoutFor` and the class body; `layoutHandles(layout, slot)` is the name used by `NqpOps.resolveAttr`, `NqpTypeOps.resolveDecont` and `NqpDispatch.getterFor`; `MemberPlan(descriptor, arity, argStart, args, target, ret)` is the shape used by `methodPlan`, `fieldGetPlan`, `fieldSetPlan`, `constructorPlan`, `specialPlans` and `JavaCallout.invoke`; `VarArityPlan.run(tc, cf, csd, args)` is what `MultiPlan` overrides and `invoke` calls; `deserialize_stub(tc, st, reader)` is what `stubObjects` calls and `RakuObjectREPR` overrides.
