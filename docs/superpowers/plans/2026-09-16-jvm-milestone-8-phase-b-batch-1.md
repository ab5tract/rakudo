# Milestone 8 Phase B, part 2: batch 1, the sites Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote `iscont`, `istrue`/`isfalse` (and the `Truthy` condition node's object arm), `findmethod`/`tryfindmethod`/`can`, and make source-level `decont`/`isconcrete`/`create` reach their existing sites; then rig row `b1` with the census against the `b0` baseline.

**Architecture:** Three new sites in `NqpTypeOps.kt` modelled on `HllizeSite` (one STable, one state, a folded constant), `IsConcreteSite` (an inner `DecontSite` with the `SuspendedIn` tail) and `IsTypeSite` (a folded answer under the state's assumption); three new `@Operation` nodes in `NqpRootNode.java`; arms in `NqpProgramBuilder.dedicatedClasslib` (by class + method + nargs) and `dedicatedOp` (for `tryfindmethod`, the one table op). Every fact folded is one a state the site holds published: the container spec, the boolification mode, the authoritative method cache's answer. Anything else (a mode-0 boolification, a non-authoritative cache) pins the site and is counted by the census under a named slow path.

**Tech Stack:** Kotlin (nqp-truffle), Java Bytecode DSL (`NqpRootNode.java`, `NqpProgramBuilder.java`), nqp `.t` tests under `prove` with child processes for the census counters, Raku rig.

**Spec:** `docs/superpowers/specs/2026-09-16-jvm-milestone-8-phase-b-promotion-campaign-design.md`, section 3 (batch 1) and section 5 (gates, rows). Ledger of record: `docs/superpowers/plans/2026-09-16-jvm-milestone-8-phase-b.ledger.md` (B0 baseline: the numbers every row here is compared against).

## Global Constraints

- **Worktree only:** `/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records` (rakudo, branch `worktree-jesp-direct-lazy-records`, tip `c6aea59876`) and its nested `nqp/` (nqp.git, branch `jesp-direct-lazy-records`, tip `cceb673bb`). Never `cd` in the tool shell except a parenthesised subshell for `prove` (the tests spawn `./nqp-j-gradle` relative to the nqp tree). `git` in the rakudo tree needs `--ignore-submodules=all`. Push to `ab5tract` only, never `origin`.
- **Engine-jar only.** No encoder row, no wire change, no stage0 regen, no `make` until Task 5. Rebuild: `./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars` (seconds) from the rakudo worktree root; restart any eval server afterwards.
- **Kotlin for the sites; Java only for the DSL node classes and the builder arms** (the two Java files are the DSL's, the standing exception).
- **The fold rule (Phase A ledger, Phase B spec §3):** a site folds only a fact a state it holds published; everything else pins with a named reason and the census counts it (`NqpCensus.slow(site.stats, reason)`).
- **Site shape:** `Site` base; `@JvmField @field:CompilationFinal` speculation fields; `valid()` then STable identity on the fast path; `republished(site)` on an invalid assumption, `miss(site)` on a different STable; resolution behind `@TruffleBoundary` after `transferToInterpreterAndInvalidate()`; `if (NqpCensus.ON) NqpCensus.call(site.stats)` first in every entry function.
- **Every debug print env-gated** (`if (DEBUG) debug(...)` in Kotlin; `nqp::getenvhash` in nqp).
- **Op result shape:** each new node answers `Object` (a boxed `Long` or a `SixModelObject`, or a suspension token), as `IsTypeOp` does, so the untyped store local and the consumers are unchanged whichever road computed the value.
- **Tests:** `nqp/t/jvm/21-op-sites.t`, one file grown by Tasks 1-4; semantic fold-then-refold checks in-process, routing checks through a child process with `NQP_OP_CENSUS=1` (the helper copied from `t/jvm/20-op-census.t`). Run: `( cd <worktree>/nqp && prove --exec ./nqp-j-gradle t/jvm/21-op-sites.t t/jvm/19-type-state.t t/jvm/20-op-census.t )`.
- **Gates:** per task the `.t` trio above; Task 5 = nqp suite + warm sanity + rig row `b1` with `--census`; report every run with its wall time; a failed benchmark run is recorded as not gathered, never re-run; `NQP_OP_CENSUS` and `NQP_DISPATCH_RECORD` must be unset in the shell that runs the rig.
- **Commits:** one per task, nqp tree (Task 5 adds one rakudo commit for the ledger); `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE` in the 22:25-22:59 window of 2026-09-16 +0200, increasing; trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- **Census slow-path names used here** (the census prints them as `slow=[name=N ...]`): `generic` (an unresolved or missed site taking the runtime road), `pinned` (a pinned site), `method` (istrue mode 0), `nonauth` (findmethod on a non-authoritative or absent cache).
- Temporary files under `/home/longwalker/.claude/jobs/455b5a91/tmp`.

---

## File structure

nqp tree:
- `nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt` — three new sites + entry functions + resolvers + slow roads (Tasks 1-3), each in its own `/* ----- op ----- */` section after `istype`'s.
- `nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java` — `IsContOp`, `IsTrueOp`, `FindMethodOp`; `Truthy` gains a site operand (Tasks 1-3).
- `nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java` — `Op` enum members, `dedicatedClasslib` / `dedicatedOp` arms, `beginOp` / `endOp` cases, `walkCond` (Tasks 1-4).
- `t/jvm/21-op-sites.t` — NEW (Task 1), grown by Tasks 2-4.

rakudo tree:
- `docs/superpowers/plans/2026-09-16-jvm-milestone-8-phase-b.ledger.md` — the B1 section (Task 5).

---

### Task 1: `IsContSite` (and the test file with its child-process helper)

**Files:**
- Modify: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt` (new section after the `istype` section, i.e. after `istypeSlow`)
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java` (a new `@Operation` after `IsTypeOp`)
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java:700-795` (`Op` enum, `dedicatedClasslib`, `beginOp`, `endOp`)
- Create: `nqp/t/jvm/21-op-sites.t`

**Interfaces:**
- Produces: `NqpTypeOps.IsContSite : Site` (fields `st: STable?`, `result: Long`); `NqpTypeOps.iscont(site: IsContSite, o: Any?): Long`; `NqpRootNode.IsContOp` (constant operand `site`, one dynamic operand); `Op.ISCONT`; `dedicatedClasslib("Lorg/raku/nqp/runtime/Ops;", "iscont", 1) == Op.ISCONT`.
- Consumes: `Site`, `miss`, `republished`, `NqpCensus.call/slow`, `NqpRaw.st`, `Ops.isnull`, `Ops.iscont`, `TypeState.containerSpec`.

- [ ] **Step 1: Write the failing test**

Create `nqp/t/jvm/21-op-sites.t`:
```perl
# Milestone 8 Phase B, batch 1: the promoted sites. Each op has two halves:
# an in-process fold-then-refold check (a loop resolves the site, a writer
# op republishes the type, the same site must answer the new fact), and a
# routing check through a child process under NQP_OP_CENSUS=1 (the site's
# calls move; the classlib name the op used to travel under is absent).
#
# The child-process helper is the one of t/jvm/20-op-census.t, copied: nqp
# test files are standalone, and the two files assert different things.
# This file spawns ./nqp-j-gradle (the gradle-generated runner) relative
# to the nqp tree, so prove must run from there.

plan(6);

my class Queue is repr('ConcBlockingQueue') { }
my class VMDecoder is repr('Decoder') { }
my sub create_buf($type) {
    my $buf := nqp::newtype(nqp::null(), 'VMArray');
    nqp::composetype($buf, nqp::hash('array', nqp::hash('type', $type)));
    $buf
}

# Runs ./nqp-j-gradle -e $code as a child under %env; returns [status, stderr].
sub child-stderr($code, %env) {
    my $queue := nqp::create(Queue);
    my $done := 0; my $out-eof := 0; my $err-eof := 0; my $status := -1;
    my @err;
    my $config := nqp::hash(
        'done', -> $st { $status := $st; $done := 1 },
        'ready', -> $stdin?, $stdout?, $stderr? { },
        'stdout_bytes', -> $seq, $data, $err { $out-eof := 1 unless nqp::isconcrete($data) },
        'stderr_bytes', -> $seq, $data, $err {
            if nqp::isconcrete($data) { @err[$seq] := $data } else { $err-eof := 1 }
        },
        'buf_type', create_buf(uint8));
    my $task := nqp::spawnprocasync($queue, './nqp-j-gradle', nqp::list('./nqp-j-gradle', '-e', $code),
                                    nqp::cwd(), %env, $config);
    nqp::permit($task, 1, -1);
    nqp::permit($task, 2, -1);
    while !$done || !$out-eof || !$err-eof {
        if nqp::shift($queue) -> $t {
            if nqp::islist($t) { my $cb := nqp::shift($t); $cb(|$t) } else { $t() }
        }
    }
    my $dec := nqp::create(VMDecoder);
    nqp::decoderconfigure($dec, 'utf8', nqp::hash());
    for @err -> $bytes { nqp::decoderaddbytes($dec, $bytes) if nqp::isconcrete($bytes) }
    nqp::list($status, nqp::decodertakeallchars($dec))
}

# "  <prefix> <count> <name>" -> count, or -1 when absent.
sub count-of($text, $prefix, $name) {
    for nqp::split("\n", $text) -> $line {
        my $lead := '  ' ~ $prefix ~ ' ';
        if nqp::index($line, $lead) == 0 {
            my @f := nqp::split(' ', nqp::substr($line, nqp::chars($lead)));
            return +@f[0] if @f[1] eq $name;
        }
    }
    -1
}

# "  site <Site> calls=N misses=N ..." -> the field, or -1.
sub site-field($text, $site, $field) {
    for nqp::split("\n", $text) -> $line {
        if nqp::index($line, '  site ' ~ $site ~ ' ') == 0 {
            for nqp::split(' ', $line) -> $kv {
                return +nqp::substr($kv, nqp::chars($field) + 1) if nqp::index($kv, $field ~ '=') == 0;
            }
        }
    }
    -1
}

my %on := nqp::getenvhash();
%on<NQP_OP_CENSUS> := '1';

# ---- iscont ------------------------------------------------------------
# The container spec is a fact of the type's state: a site folds 0 for a
# plain class, and setcontspec republishes the type, so the same site must
# answer 1 afterwards without a fresh site.
class ContFoo { }
sub is_cont($o) { nqp::iscont($o) }
my $cf := ContFoo.new;
my $c := -1;
my $i := 0;
while $i < 200 { $c := is_cont($cf); $i++ }
is($c, 0, 'iscont folds 0 for a plain class');
nqp::setcontspec(ContFoo, 'code_pair', nqp::hash('fetch', -> $cont { 42 }, 'store', -> $cont, $v { }));
is(is_cont($cf), 1, 'an iscont site resolved before setcontspec sees the container spec');

my $cont-child := child-stderr(
    'class Foo { }; my $o := Foo.new; my $i := 0; my $n := 0; while $i < 1000 { $n := $n + nqp::iscont($o); $i++ }; say($n)',
    %on);
is($cont-child[0], 0, 'the iscont child exits 0');
my $cont-err := $cont-child[1];
ok(site-field($cont-err, 'IsContSite', 'calls') >= 1000, 'iscont reaches IsContSite');
ok(count-of($cont-err, 'classlib', 'Ops.iscont') < 0, 'iscont no longer travels the classlib road');
ok(site-field($cont-err, 'IsContSite', 'misses') == 0, 'a monomorphic iscont loop never misses');
```

- [ ] **Step 2: Run it to verify it fails**

Run: `( cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && prove --exec ./nqp-j-gradle t/jvm/21-op-sites.t )`
Expected: tests 1-3 pass (the runtime answers correctly today), tests 4 and 6 FAIL (no `IsContSite` line: `-1`), test 5 FAILS (`Ops.iscont` is on the classlib list).

- [ ] **Step 3: The site**

`NqpTypeOps.kt`, new section after `istypeSlow` (before `/* ----- assertparamcheck ----- */`):
```kotlin
    /* ----- iscont ----- */

    /**
     * nqp::iscont with a site: whether a type's objects are containers is a
     * fact of its state (the container spec), so the answer folds to a
     * constant under one STable compare and the state's assumption.
     * setcontspec publishes a new state, which invalidates the fold.
     */
    class IsContSite : Site() {
        @JvmField @field:CompilationFinal var st: STable? = null
        @JvmField @field:CompilationFinal var result: Long = 0
        override fun clear() { st = null; result = 0 }
    }

    /** nqp::iscont: null is not a container; else the folded fact, else the runtime. */
    @JvmStatic
    fun iscont(site: IsContSite, o: Any?): Long {
        if (NqpCensus.ON) NqpCensus.call(site.stats)
        if (o !is SixModelObject || Ops.isnull(o) == 1L) return 0L
        var st = site.st
        if (st == null && site.mayResolve()) {
            CompilerDirectives.transferToInterpreterAndInvalidate()
            resolveIsCont(site, o)
            st = site.st
        }
        if (st != null) {
            if (!site.valid()) republished(site)
            else if (NqpRaw.st(o) === st) return site.result
            else miss(site)
        }
        if (NqpCensus.ON) NqpCensus.slow(site.stats, if (site.mayResolve()) "generic" else "pinned")
        return Ops.iscont(o)
    }

    @TruffleBoundary
    private fun resolveIsCont(site: IsContSite, o: SixModelObject) {
        if (!o.stInitialized) { site.pin(); return }
        val st = o.st
        val s = st.state
        site.st = st; site.state = s
        site.result = if (s.containerSpec == null) 0L else 1L
        if (DEBUG) debug("iscont site resolved " + site.result + " on " + st.debugName)
    }
```

- [ ] **Step 4: The node and the arms**

`NqpRootNode.java`, after `IsTypeOp`:
```java
    /** nqp::iscont through a site: no decont, no user code, a folded fact.
     *  Answers Object (a boxed Long, cached for 0 and 1) so the store local
     *  the classlib road wrote into is unchanged. */
    @Operation
    @ConstantOperand(type = Object.class, name = "site")
    public static final class IsContOp {
        @Specialization
        static Object doIsCont(VirtualFrame f, Object site, Object o) {
            try {
                return NqpTypeOps.iscont((NqpTypeOps.IsContSite) site, o);
            } catch (Throwable t) {
                throw NqpOps.carry(t);
            }
        }
    }
```
`NqpProgramBuilder.java`: add `ISCONT` to the `Op` enum (after `ISTYPE`); in `dedicatedClasslib` add, after the `istype` line:
```java
        if (cls.equals("Lorg/raku/nqp/runtime/Ops;") && meth.equals("iscont") && nargs == 1) return Op.ISCONT;
```
(`iscont` is registered without `:tc`, `Compiler.nqp:1039`; nargs counts guest args, so 1 either way.) In `beginOp`: `case ISCONT -> b.beginIsContOp(new NqpTypeOps.IsContSite());` in `endOp`: `case ISCONT -> b.endIsContOp();`. Extend the `dedicatedClasslib` doc comment with one sentence: "Batch 1 (milestone 8 Phase B) routes iscont, istrue, isfalse, findmethod, can and the three half-reachable sites from here as well; only tryfindmethod is a table op (dedicatedOp)."

- [ ] **Step 5: Rebuild and run the tests**

```bash
./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars
( cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && prove --exec ./nqp-j-gradle t/jvm/21-op-sites.t t/jvm/19-type-state.t t/jvm/20-op-census.t )
```
Expected: 6/6, 4/4, 8/8. If test 2 fails because `code_pair` is not a registered container spec name on this backend, use the name `nqp::setcontspec` accepts here (grep `ContainerSpec` registrations under `nqp/src/vm/jvm/runtime/org/raku/nqp/sixmodel/`) and record the ruling.

- [ ] **Step 6: Commit (nqp tree)**

```bash
git -C nqp add nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java t/jvm/21-op-sites.t
GIT_AUTHOR_DATE='2026-09-16T22:25:00+0200' GIT_COMMITTER_DATE='2026-09-16T22:25:00+0200' git -C nqp commit -F - <<'EOF'
Engine: nqp::iscont through a site -- the container spec folds to a constant under the type state (milestone 8, B1)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
```

---

### Task 2: `IsTrueSite` for `istrue`, `isfalse` and the `Truthy` object arm

**Files:**
- Modify: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt` (new section after the `iscont` section)
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java` (`Truthy` at lines ~257-270 gains a site; new `IsTrueOp` after `IsContOp`)
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java` (`Op` enum, `dedicatedClasslib`, `beginOp`, `endOp`, `walkCond` at ~line 800)
- Modify: `nqp/t/jvm/21-op-sites.t`

**Interfaces:**
- Produces: `NqpTypeOps.IsTrueSite : Site` (`decont: DecontSite`, `st`, `mode: Int`, `pinReason: String?`); `NqpTypeOps.istrue(site: IsTrueSite, o: Any?, negate: Int, tc: ThreadContext): Long` (may throw `SuspendedIn`); `NqpRootNode.IsTrueOp` (constants `site`, `negate`; one dynamic operand); `Truthy` with constants `type`, `negate`, `site` (null unless `type == T_OBJ`); `Op.ISTRUE`, `Op.ISFALSE`.
- Consumes: `BoolificationSpec.MODE_*`, `TypeObject`, `SixModelObject.get_int/get_num/get_str/elems`, `Ops.istrue`, `suspendedIn`, the Task 1 pattern.

- [ ] **Step 1: Extend the test**

Change `plan(6)` to `plan(15)` and append:
```perl
# ---- istrue / isfalse / a condition on an object -----------------------
# The boolification mode is a fact of the state: a plain class folds to
# "not a type object" (mode 5); setboolspec to mode 0 (call a method) both
# republishes the type and names a road the site must not fold.
class TrueFoo { }
sub is_true($o) { nqp::istrue($o) }
sub is_false($o) { nqp::isfalse($o) }
sub cond_true($o) { if $o { 1 } else { 0 } }
my $tf := TrueFoo.new;
my $t := -1; my $f := -1; my $cd := -1;
$i := 0;
while $i < 200 { $t := is_true($tf); $f := is_false($tf); $cd := cond_true($tf); $i++ }
is($t, 1, 'istrue folds 1 for an instance of a plain class');
is($f, 0, 'isfalse folds 0 for it');
is($cd, 1, 'a condition on it is true');
nqp::setboolspec(TrueFoo, 0, -> $o { 0 });
is(is_true($tf), 0, 'an istrue site resolved before setboolspec sees the method mode');
is(is_false($tf), 1, 'and so does an isfalse site');
is(cond_true($tf), 0, 'and so does a condition');

my $true-child := child-stderr(
    'class Foo { }; my $o := Foo.new; my $i := 0; my $n := 0; while $i < 1000 { $n := $n + nqp::istrue($o) + nqp::isfalse($o); if $o { $n++ }; $i++ }; say($n)',
    %on);
is($true-child[0], 0, 'the istrue child exits 0');
my $true-err := $true-child[1];
ok(site-field($true-err, 'IsTrueSite', 'calls') >= 3000, 'istrue, isfalse and the condition reach IsTrueSite');
ok(count-of($true-err, 'classlib', 'Ops.istrue') < 0 && count-of($true-err, 'classlib', 'Ops.isfalse') < 0, 'istrue/isfalse no longer travel the classlib road');
```

- [ ] **Step 2: Run it to verify it fails**

Run the prove command of Task 1 Step 5 on `21-op-sites.t` only. Expected: 6 earlier tests pass, tests 7-12 pass (runtime semantics), tests 13-15 FAIL (no `IsTrueSite`; classlib names present).

- [ ] **Step 3: The site**

`NqpTypeOps.kt`, new section after the `iscont` section (add `import org.raku.nqp.sixmodel.BoolificationSpec` if the file does not import it):
```kotlin
    /* ----- istrue / isfalse ----- */

    /**
     * nqp::istrue with a site: the boolification mode is a fact of the
     * deconted value's state, so under one STable compare the answer is one
     * REPR read chosen by a compilation-final mode. Mode 0 (call a method)
     * is user code and is not folded: the site pins and the census counts
     * the road as `method`. BIGINT and ITER modes stay on the runtime road
     * too (a boundary either way).
     */
    class IsTrueSite : Site() {
        @JvmField val decont = DecontSite()
        @JvmField @field:CompilationFinal var st: STable? = null
        @JvmField @field:CompilationFinal var mode: Int = -1
        /** Why the site pinned, for the census; null while it may resolve. */
        @JvmField var pinReason: String? = null
        override fun clear() { st = null; mode = -1; pinReason = null }
    }

    /** nqp::istrue (negate == 0) or nqp::isfalse (negate != 0) of a value. */
    @JvmStatic
    fun istrue(site: IsTrueSite, o: Any?, negate: Int, tc: ThreadContext): Long {
        if (NqpCensus.ON) NqpCensus.call(site.stats)
        val v = try {
            decont(site.decont, o, tc)
        } catch (sse: SaveStackException) {
            /* A Proxy FETCH captured; finish by re-running on the fetched
             * value, which is no longer a container (see istype). */
            throw suspendedIn(sse, java.util.function.Function { fetched -> istrue(site, fetched, negate, tc) })
        }
        val truth = truth(site, v, tc)
        return if (negate == 0) truth else 1L - truth
    }

    /** The truth of an already-deconted value: the fold, else the runtime. */
    private fun truth(site: IsTrueSite, v: Any?, tc: ThreadContext): Long {
        if (v !is SixModelObject || Ops.isnull(v) == 1L) return 0L
        var st = site.st
        if (st == null && site.mayResolve()) {
            CompilerDirectives.transferToInterpreterAndInvalidate()
            resolveIsTrue(site, v)
            st = site.st
        }
        if (st != null) {
            if (!site.valid()) republished(site)
            else if (NqpRaw.st(v) === st) return truthByMode(site.mode, v, tc)
            else miss(site)
        }
        if (NqpCensus.ON) NqpCensus.slow(site.stats, site.pinReason ?: if (site.mayResolve()) "generic" else "pinned")
        return istrueSlow(v, tc)
    }

    /** The folded modes, as Ops.istrue answers them; `mode` is compilation-final. */
    private fun truthByMode(mode: Int, o: SixModelObject, tc: ThreadContext): Long = when (mode) {
        BoolificationSpec.MODE_NOT_TYPE_OBJECT -> if (o is TypeObject) 0L else 1L
        BoolificationSpec.MODE_UNBOX_INT -> if (o is TypeObject || o.get_int(tc) == 0L) 0L else 1L
        BoolificationSpec.MODE_UNBOX_NUM -> if (o is TypeObject || o.get_num(tc) == 0.0) 0L else 1L
        BoolificationSpec.MODE_UNBOX_STR_NOT_EMPTY ->
            if (o is TypeObject) 0L else { val s = o.get_str(tc); if (s == null || s.isEmpty()) 0L else 1L }
        BoolificationSpec.MODE_UNBOX_STR_NOT_EMPTY_OR_ZERO ->
            if (o is TypeObject) 0L else { val s = o.get_str(tc); if (s == null || s.isEmpty() || s == "0") 0L else 1L }
        BoolificationSpec.MODE_HAS_ELEMS -> if (o.elems(tc) == 0L) 0L else 1L
        else -> istrueSlow(o, tc)
    }

    @TruffleBoundary
    private fun resolveIsTrue(site: IsTrueSite, o: SixModelObject) {
        if (!o.stInitialized) { site.pin(); return }
        val st = o.st
        val s = st.state
        val bs = s.boolificationSpec
        val mode = if (bs == null) BoolificationSpec.MODE_NOT_TYPE_OBJECT else bs.Mode
        when (mode) {
            BoolificationSpec.MODE_NOT_TYPE_OBJECT, BoolificationSpec.MODE_UNBOX_INT,
            BoolificationSpec.MODE_UNBOX_NUM, BoolificationSpec.MODE_UNBOX_STR_NOT_EMPTY,
            BoolificationSpec.MODE_UNBOX_STR_NOT_EMPTY_OR_ZERO, BoolificationSpec.MODE_HAS_ELEMS -> {
                site.st = st; site.state = s; site.mode = mode
                if (DEBUG) debug("istrue site resolved mode " + mode + " on " + st.debugName)
            }
            else -> {
                site.pinReason = if (mode == BoolificationSpec.MODE_CALL_METHOD) "method" else "mode" + mode
                site.pin()
                if (DEBUG) debug("istrue pin " + site.pinReason + ": " + st.debugName)
            }
        }
    }

    @TruffleBoundary
    private fun istrueSlow(v: Any?, tc: ThreadContext): Long =
        Ops.istrue(v as SixModelObject?, tc)
```

- [ ] **Step 4: The nodes and the arms**

`NqpRootNode.java`: replace `Truthy` with
```java
    /** nqp truthiness, typed by the encoder; negate for until-loops. An
     *  object condition goes through an IsTrueSite (batch 1); natives inline. */
    @Operation
    @ConstantOperand(type = int.class, name = "type")
    @ConstantOperand(type = int.class, name = "negate")
    @ConstantOperand(type = Object.class, name = "site")
    public static final class Truthy {
        @Specialization
        static boolean doTruthy(VirtualFrame f, int type, int negate, Object site, Object v) {
            try {
                if (type == NqpWire.T_OBJ)
                    return (NqpTypeOps.istrue((NqpTypeOps.IsTrueSite) site, v, 0, tc(f)) != 0) == (negate == 0);
                return NqpOps.truthy(type, v, tc(f)) == (negate == 0);
            } catch (NqpTypeOps.SuspendedIn s) {
                /* A condition answers a boolean, not a token: the capture
                 * escapes raw, exactly as it did through truthyObj. */
                throw NqpOps.carry(s.sse);
            } catch (Throwable t) {
                throw NqpOps.carry(t);
            }
        }
    }
```
and add after `IsContOp`:
```java
    /** nqp::istrue (negate 0) / nqp::isfalse (negate 1) through a site.
     *  Object, not long: the decont and a mode-0 boolification are user code. */
    @Operation
    @ConstantOperand(type = Object.class, name = "site")
    @ConstantOperand(type = int.class, name = "negate")
    public static final class IsTrueOp {
        @Specialization
        static Object doIsTrue(VirtualFrame f, Object site, int negate, Object o) {
            try {
                return NqpTypeOps.istrue((NqpTypeOps.IsTrueSite) site, o, negate, tc(f));
            } catch (NqpTypeOps.SuspendedIn s) {
                return NqpOps.suspendToken(s.sse, s.finish);
            } catch (org.raku.nqp.runtime.SaveStackException sse) {
                return NqpOps.suspendToken(sse, NqpWire.T_INT);
            } catch (Throwable t) {
                throw NqpOps.carry(t);
            }
        }
    }
```
`NqpProgramBuilder.java`: `Op` gains `ISTRUE, ISFALSE`; `dedicatedClasslib` gains
```java
        if (cls.equals("Lorg/raku/nqp/runtime/Ops;") && meth.equals("istrue") && nargs == 1) return Op.ISTRUE;
        if (cls.equals("Lorg/raku/nqp/runtime/Ops;") && meth.equals("isfalse") && nargs == 1) return Op.ISFALSE;
```
`dedicatedOp` gains `if (id == NqpOps.OP_ISTRUE && nargs == 1) return Op.ISTRUE;` (dead from the encoder today, like `OP_ISTYPE`'s line; kept for symmetry). `beginOp`: `case ISTRUE -> b.beginIsTrueOp(new NqpTypeOps.IsTrueSite(), 0); case ISFALSE -> b.beginIsTrueOp(new NqpTypeOps.IsTrueSite(), 1);` `endOp`: both `b.endIsTrueOp();`. `walkCond`: `if (emit) b.beginTruthy(condType, negate, condType == NqpWire.T_OBJ ? new NqpTypeOps.IsTrueSite() : null);` (a native-typed condition carries no site).

- [ ] **Step 5: Rebuild and run the tests**

Same commands as Task 1 Step 5. Expected: 15/15, 4/4, 8/8. Then one eyeball: `RAKUDO_RAKUAST=1 NQP_OP_CENSUS=1 ./rakudo-j -e 'say 1' 2>&1 | grep -E '^  site (IsTrueSite|IsContSite)'` shows both sites with calls and their `slow=[...]` (record the line in the report; `method=` under IsTrueSite is expected for Raku's Bool-method types).

- [ ] **Step 6: Commit (nqp tree)**

```bash
git -C nqp add nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java t/jvm/21-op-sites.t
GIT_AUTHOR_DATE='2026-09-16T22:33:00+0200' GIT_COMMITTER_DATE='2026-09-16T22:33:00+0200' git -C nqp commit -F - <<'EOF'
Engine: nqp::istrue, nqp::isfalse and object conditions through a site -- the boolification mode folds under the type state (milestone 8, B1)

Mode 0 (call a method) is user code and pins the site, counted as
`method`; the other REPR-read modes fold to one read under the STable
compare and the state's assumption.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
```

---

### Task 3: `FindMethodSite` for `findmethod`, `tryfindmethod` and `can`

**Files:**
- Modify: `nqp/nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt` (new section after the `istrue` section)
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java` (new `FindMethodOp` after `IsTrueOp`)
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java` (`Op` enum, `dedicatedClasslib`, `dedicatedOp`, `beginOp`, `endOp`)
- Modify: `nqp/t/jvm/21-op-sites.t`

**Interfaces:**
- Produces: `NqpTypeOps.FIND_FATAL = 0`, `FIND_TRY = 1`, `FIND_CAN = 2`; `NqpTypeOps.FindMethodSite : Site` (`decont`, `st`, `name: String?`, `found: SixModelObject?`, `pinReason`); `NqpTypeOps.findmethod(site, o: Any?, name: Any?, kind: Int, tc): Any?`; `NqpRootNode.FindMethodOp` (constants `site`, `kind`; two dynamic operands); `Op.FINDMETHOD`, `Op.FINDMETHOD_TRY`, `Op.CAN`.
- Consumes: `TypeState.methodCache`, `TypeState.methodCacheAuthoritative`, `Ops.findmethod/findmethodNonFatal/can`, `NqpOps.str` (same package).

- [ ] **Step 1: Extend the test**

Change `plan(15)` to `plan(25)` and append:
```perl
# ---- findmethod / tryfindmethod / can ---------------------------------
# NQPClassHOW publishes an AUTHORITATIVE method cache at compose and
# demotes it on add_method (setmethcacheauth 0). A site folds the cache's
# answer only while it is authoritative; the demotion republishes the
# type, and the site must then take the HOW road and see the new method.
class MethBase { method m() { 'old' } }
class MethFoo is MethBase { }
sub has_m($o) { nqp::can($o, 'm') }
sub has_x($o) { nqp::can($o, 'x') }
sub find_m($o) { nqp::findmethod($o, 'm') }
sub try_x($o) { nqp::tryfindmethod($o, 'x') }
my $mo := MethFoo.new;
my $hm := -1; my $hx := -1; my $fm; my $tx;
$i := 0;
while $i < 200 { $hm := has_m($mo); $hx := has_x($mo); $fm := find_m($mo); $tx := try_x($mo); $i++ }
is($hm, 1, 'can folds 1 for an inherited method');
is($hx, 0, 'can folds 0 for a missing method under an authoritative cache');
is($fm($mo), 'old', 'findmethod folds the code object');
ok(nqp::isnull($tx), 'tryfindmethod folds null for a missing method');
MethFoo.HOW.add_method(MethFoo, 'x', sub ($self) { 'new' });
is(has_x($mo), 1, 'a can site resolved before add_method sees the added method');
is(try_x($mo)($mo), 'new', 'and so does a tryfindmethod site');
my $died := 0;
try { nqp::findmethod($mo, 'nope'); CATCH { $died := 1 } }
is($died, 1, 'findmethod of a missing method still dies through the runtime road');

my $meth-child := child-stderr(
    'class Base { method m() { 1 } }; class Foo is Base { }; my $o := Foo.new; my $i := 0; my $n := 0; while $i < 1000 { $n := $n + nqp::can($o, "m"); nqp::findmethod($o, "m"); nqp::tryfindmethod($o, "zz"); $i++ }; say($n)',
    %on);
is($meth-child[0], 0, 'the findmethod child exits 0');
my $meth-err := $meth-child[1];
ok(site-field($meth-err, 'FindMethodSite', 'calls') >= 3000, 'findmethod, tryfindmethod and can reach FindMethodSite');
ok(count-of($meth-err, 'classlib', 'Ops.findmethod') < 0 && count-of($meth-err, 'classlib', 'Ops.can') < 0 && count-of($meth-err, 'table', 'tryfindmethod') < 0,
   'none of the three travels its old road');
```

- [ ] **Step 2: Run it to verify it fails**

Expected: tests 16-22 pass (runtime semantics), 23-25 FAIL.

- [ ] **Step 3: The site**

`NqpTypeOps.kt`, new section after the `istrue` section:
```kotlin
    /* ----- findmethod / tryfindmethod / can ----- */

    const val FIND_FATAL = 0
    const val FIND_TRY = 1
    const val FIND_CAN = 2

    /**
     * The method a name resolves to on a type is a fact of its state ONLY
     * while the state's method cache is authoritative (the Phase B rule: a
     * site folds only a fact some state it holds published; the HOW walk
     * is not one). So the site folds the authoritative cache's answer -- a
     * code object, or "no such method" -- under one STable compare, the
     * name's identity and the state's assumption, and pins (counted as
     * `nonauth`) on a type whose cache is absent or advisory. Three ops
     * share it: findmethod (fatal on null, through the runtime's error
     * road), tryfindmethod (null on null) and can (0/1).
     */
    class FindMethodSite : Site() {
        @JvmField val decont = DecontSite()
        @JvmField @field:CompilationFinal var st: STable? = null
        @JvmField @field:CompilationFinal var name: String? = null
        @JvmField @field:CompilationFinal var found: SixModelObject? = null
        @JvmField var pinReason: String? = null
        override fun clear() { st = null; name = null; found = null; pinReason = null }
    }

    @JvmStatic
    fun findmethod(site: FindMethodSite, o: Any?, name: Any?, kind: Int, tc: ThreadContext): Any? {
        if (NqpCensus.ON) NqpCensus.call(site.stats)
        val v = try {
            decont(site.decont, o, tc)
        } catch (sse: SaveStackException) {
            throw suspendedIn(sse, java.util.function.Function { fetched -> findmethod(site, fetched, name, kind, tc) })
        }
        if (v is SixModelObject && name is String && Ops.isnull(v) == 0L) {
            var st = site.st
            if (st == null && site.mayResolve()) {
                CompilerDirectives.transferToInterpreterAndInvalidate()
                resolveFindMethod(site, v, name)
                st = site.st
            }
            if (st != null) {
                if (!site.valid()) republished(site)
                else if (NqpRaw.st(v) === st && (name === site.name || name == site.name)) {
                    val found = site.found
                    return when (kind) {
                        FIND_CAN -> if (found == null) 0L else 1L
                        FIND_TRY -> found
                        else -> found ?: findmethodSlow(v, name, kind, tc)   /* the runtime raises the error */
                    }
                }
                else miss(site)
            }
        }
        if (NqpCensus.ON) NqpCensus.slow(site.stats, site.pinReason ?: if (site.mayResolve()) "generic" else "pinned")
        return findmethodSlow(v, name, kind, tc)
    }

    @TruffleBoundary
    private fun resolveFindMethod(site: FindMethodSite, v: SixModelObject, name: String) {
        if (!v.stInitialized) { site.pin(); return }
        val st = v.st
        val s = st.state
        val cache = s.methodCache
        if (cache == null || !s.methodCacheAuthoritative) {
            site.pinReason = "nonauth"; site.pin()
            if (DEBUG) debug("findmethod pin nonauth: " + st.debugName + "." + name)
            return
        }
        val found = cache.get(name)
        site.st = st; site.state = s; site.name = name
        site.found = if (found == null || Ops.isnull(found) == 1L) null else found
        if (DEBUG) debug("findmethod site resolved " + st.debugName + "." + name + " found=" + (site.found != null))
    }

    /** The runtime road: the same three entries the table and classlib roads call. */
    @TruffleBoundary
    private fun findmethodSlow(v: Any?, name: Any?, kind: Int, tc: ThreadContext): Any? {
        val o = v as SixModelObject?
        val n = NqpOps.str(name)
        return when (kind) {
            FIND_CAN -> Ops.can(o, n, tc)
            FIND_TRY -> Ops.findmethodNonFatal(o, n, tc)
            else -> Ops.findmethod(o, n, tc)
        }
    }
```
(`NqpOps.str` is the package-private static the table road uses; if it is not accessible from Kotlin, use `name as String` for the `String` case and `name.toString()` otherwise, and record the ruling.)

- [ ] **Step 4: The node and the arms**

`NqpRootNode.java`, after `IsTrueOp`:
```java
    /** findmethod (kind 0, fatal), tryfindmethod (1), can (2) through one
     *  site. Object: the decont and the HOW road are user code; a capture
     *  answers a token typed by the op's value (INT for can). */
    @Operation
    @ConstantOperand(type = Object.class, name = "site")
    @ConstantOperand(type = int.class, name = "kind")
    public static final class FindMethodOp {
        @Specialization
        static Object doFind(VirtualFrame f, Object site, int kind, Object o, Object name) {
            try {
                return NqpTypeOps.findmethod((NqpTypeOps.FindMethodSite) site, o, name, kind, tc(f));
            } catch (NqpTypeOps.SuspendedIn s) {
                return NqpOps.suspendToken(s.sse, s.finish);
            } catch (org.raku.nqp.runtime.SaveStackException sse) {
                return kind == NqpTypeOps.FIND_CAN ? NqpOps.suspendToken(sse, NqpWire.T_INT) : NqpOps.suspendToken(sse);
            } catch (Throwable t) {
                throw NqpOps.carry(t);
            }
        }
    }
```
`NqpProgramBuilder.java`: `Op` gains `FINDMETHOD, FINDMETHOD_TRY, CAN`; `dedicatedClasslib` gains
```java
        if (cls.equals("Lorg/raku/nqp/runtime/Ops;") && meth.equals("findmethod") && nargs == 2) return Op.FINDMETHOD;
        if (cls.equals("Lorg/raku/nqp/runtime/Ops;") && meth.equals("can") && nargs == 2) return Op.CAN;
```
`dedicatedOp` gains
```java
        if (id == NqpOps.OP_TRYFINDMETHOD && nargs == 2) return Op.FINDMETHOD_TRY;
        if (id == NqpOps.OP_FINDMETHOD && nargs == 2) return Op.FINDMETHOD;
        if (id == NqpOps.OP_CAN && nargs == 2) return Op.CAN;
```
`beginOp`: `case FINDMETHOD -> b.beginFindMethodOp(new NqpTypeOps.FindMethodSite(), NqpTypeOps.FIND_FATAL); case FINDMETHOD_TRY -> b.beginFindMethodOp(new NqpTypeOps.FindMethodSite(), NqpTypeOps.FIND_TRY); case CAN -> b.beginFindMethodOp(new NqpTypeOps.FindMethodSite(), NqpTypeOps.FIND_CAN);` `endOp`: all three `b.endFindMethodOp();`. (Kotlin `const val` in an `object` is a static field, reachable from Java as `NqpTypeOps.FIND_TRY`.)

- [ ] **Step 5: Rebuild and run the tests**

Same commands. Expected: 25/25, 4/4, 8/8. Eyeball as in Task 2 for `FindMethodSite` (its `nonauth=` count on `rakudo-j -e 'say 1'` is the number the multi-state question is decided on; record it).

- [ ] **Step 6: Commit (nqp tree)**

```bash
git -C nqp add nqp-truffle/src/main/kotlin/org/raku/nqp/truffle/NqpTypeOps.kt nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpRootNode.java nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java t/jvm/21-op-sites.t
GIT_AUTHOR_DATE='2026-09-16T22:41:00+0200' GIT_COMMITTER_DATE='2026-09-16T22:41:00+0200' git -C nqp commit -F - <<'EOF'
Engine: findmethod, tryfindmethod and can through one site -- the authoritative method cache's answer folds under the type state (milestone 8, B1)

A non-authoritative or absent cache pins the site (counted as nonauth):
the HOW walk is not a published fact of any state the site holds.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
```

---

### Task 4: the reachability arms (`decont`, `isconcrete`, `create` by name)

**Files:**
- Modify: `nqp/nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java` (`dedicatedClasslib`)
- Modify: `nqp/t/jvm/21-op-sites.t`

**Interfaces:** `dedicatedClasslib("Lorg/raku/nqp/runtime/Ops;", "decont"|"isconcrete"|"create", 1)` → `Op.DECONT` | `Op.ISCONCRETE` | `Op.CREATE` (existing members, existing sites).

- [ ] **Step 1: Extend the test**

Change `plan(25)` to `plan(30)` and append:
```perl
# ---- the half-reachable sites --------------------------------------------
# decont, isconcrete and create had sites only for the encoder's hand-emitted
# forms; a source-level nqp::decont/isconcrete/create took the generic
# classlib road. The arms make them reach the sites by name.
my $reach-child := child-stderr(
    'class Foo { }; my $o := Foo.new; my $i := 0; my $n := 0; while $i < 1000 { $n := $n + nqp::isconcrete(nqp::decont($o)); nqp::create(Foo); $i++ }; say($n)',
    %on);
is($reach-child[0], 0, 'the reachability child exits 0');
my $reach-err := $reach-child[1];
ok(site-field($reach-err, 'IsConcreteSite', 'calls') >= 1000, 'a source-level isconcrete reaches IsConcreteSite');
ok(site-field($reach-err, 'CreateSite', 'calls') >= 1000, 'a source-level create reaches CreateSite');
ok(count-of($reach-err, 'classlib', 'Ops.decont') < 0 && count-of($reach-err, 'classlib', 'Ops.isconcrete') < 0 && count-of($reach-err, 'classlib', 'Ops.create') < 0,
   'none of the three travels the classlib road');
ok(site-field($reach-err, 'DecontSite', 'calls') >= 2000, 'the decont (direct and inner) reaches DecontSite');
```

- [ ] **Step 2: Run it to verify it fails**

Expected: tests 26 passes, 27-29 FAIL (the three names are on the classlib list; `IsConcreteSite`/`CreateSite` calls below 1000), 30 may already pass (inner deconts) — that is fine, it guards the routing together with 29.

- [ ] **Step 3: The arms**

`dedicatedClasslib` gains
```java
        if (cls.equals("Lorg/raku/nqp/runtime/Ops;") && meth.equals("decont") && nargs == 1) return Op.DECONT;
        if (cls.equals("Lorg/raku/nqp/runtime/Ops;") && meth.equals("isconcrete") && nargs == 1) return Op.ISCONCRETE;
        if (cls.equals("Lorg/raku/nqp/runtime/Ops;") && meth.equals("create") && nargs == 1) return Op.CREATE;
```

- [ ] **Step 4: Rebuild and run the tests**

Same commands. Expected: 30/30, 4/4, 8/8.

- [ ] **Step 5: Commit (nqp tree)**

```bash
git -C nqp add nqp-truffle/src/main/java/org/raku/nqp/truffle/NqpProgramBuilder.java t/jvm/21-op-sites.t
GIT_AUTHOR_DATE='2026-09-16T22:47:00+0200' GIT_COMMITTER_DATE='2026-09-16T22:47:00+0200' git -C nqp commit -F - <<'EOF'
Engine: source-level decont, isconcrete and create reach their sites by name (milestone 8, B1)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
```

---

### Task 5: the gate, rig row `b1`, the ledger's B1 section

**Files:**
- Modify: `docs/superpowers/plans/2026-09-16-jvm-milestone-8-phase-b.ledger.md` (rakudo tree; new section "B1: batch 1")

**Interfaces:** consumes everything above and the B0 numbers in the ledger.

- [ ] **Step 1: Retrain and gate**

The engine changed, so the persisted slots retrain once (the training stamp depends on the runtime jars): from the rakudo worktree root,
```bash
RAKUDO_RAKUAST=1 NQP_DISPATCH_RECORD=all /usr/bin/perl rakudo-j-build -e '' 2>&1 | grep -E 'dispatch-record: (done|FAILED)'
```
(expect `done ... 0 failed`). Then, sequentially, through the watcher:
```bash
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/455b5a91/tmp/nqp-suite-b1.log --show='Files=' --show='Result' --show='BUILD' --stall=900 -- ./nqp/gradlew -p nqp testNqp
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/455b5a91/tmp/sanity-b1.log --show='files in' --show='FAIL' --stall=600 -- raku tools/build/evalserver-sweep.raku --chunk='*' --jobs=1 --heap=8 t/01-sanity
```
Expected: `Result: PASS` (Files=153, Tests=13216 + this file's 30), sanity 25 files, no reds. Record both wall times. Then `RAKUDO_RAKUAST=1 NQP_DISPATCH_PERSIST=verify ./rakudo-j -e 'say 1' 2>&1 | grep 'dispatch-verify: matched'` → `mismatched=0`.

- [ ] **Step 2: Rig row `b1` with the census**

```bash
raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/455b5a91/tmp/rig-b1.log --show='m7-rig:' --stall=900 -- raku tools/build/m7-rig.raku --tag=b1 --out=m7-rig --census
```
Expected: the row line, two `m7-rig: census` lines, two `m7-rig: jfr` lines, one `m7-rig: census sanity` line, `DONE tag=b1`. Nothing else runs meanwhile.

- [ ] **Step 3: The ledger's B1 section**

Append to the Phase B ledger:
```markdown
## B1: batch 1 (the sites)

Commits: nqp <iscont>, <istrue>, <findmethod>, <arms>.
Gate: retrain (<slots>, 0 failed); nqp suite Result: PASS Files=<n> Tests=<n> <s> s; sanity 25/25 <s> s;
verify mismatched=0.

Rig row b1: `<row line>`. Against b0 (2.460 / 1.334 / misses 4933 / hits 37077 / 64 s): <deltas, and whether inside the spread>.

Per op, B0 -> B1 (rakudo-e / nqp-e / sanity census; CORE.c: b0 bound only):

| op | road before | B0 count | B1 site calls | misses | pins | slow paths | verdict |
| iscont | classlib Ops.iscont | 402 / 0 / 46713 | ... | ... | ... | ... | promoted |
| istrue (+isfalse, +Truthy obj) | classlib Ops.istrue / Ops.isfalse; Truthy unsited | 2628 / 147 / 328821 (+isfalse 1 / 0 / 228) | ... | ... | ... | method=N ... | promoted; method= is the mode-0 share |
| findmethod / tryfindmethod / can | classlib Ops.findmethod, Ops.can; table tryfindmethod | 42+2613 / 19+87 / 7212+367103 (+tryfindmethod table N) | ... | ... | ... | nonauth=N | promoted; nonauth= decides the multi-state question |
| decont / isconcrete / create (by name) | classlib | Ops.decont N / Ops.isconcrete N / Ops.create N | (site calls delta) | | | | reachable |

JFR --ops: the "entry from interpreter" top 12 per workload (m7-rig/b1-*-jfr.txt) next to b0's, with
the classlib share before/after.

Rulings made during batch 1: <from the SDD ledger>.
The multi-state findmethod question: nonauth=<N> on rakudo-e, <N> on sanity -> <decision: designed / not hot>.
```
Fill every field from the files; no `<...>` remains.

- [ ] **Step 4: Commit (rakudo tree), push both trees to ab5tract**

```bash
git add docs/superpowers/plans/2026-09-16-jvm-milestone-8-phase-b.ledger.md
GIT_AUTHOR_DATE='2026-09-16T22:55:00+0200' GIT_COMMITTER_DATE='2026-09-16T22:55:00+0200' git commit -F - <<'EOF'
Docs: milestone 8 Phase B ledger -- batch 1, rig row b1 against b0 (milestone 8, B1)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
git push ab5tract HEAD
git -C nqp push ab5tract HEAD
```

---

## Self-review

**Spec coverage (section 3).** `IsContSite` (Task 1), `IsTrueSite` for istrue/isfalse/Truthy with mode 0 unfolded and counted `method` (Task 2), `FindMethodSite` for the three ops with the authoritative-cache-only fold and `nonauth` counted (Task 3), the three reachability arms (Task 4), one runtime-jar rebuild + retrain + suite + sanity + row `b1` with the census compared per op (Task 5), the test file with fold/refold and routing checks (Tasks 1-4). Section 4's batch selection and section 5's close are later plans.

**Placeholders.** The ledger template in Task 5 is filled from measurements. Two documented fallbacks (the container spec name in Task 1; `NqpOps.str` accessibility in Task 3) name what to do.

**Type consistency.** `iscont(site: IsContSite, o: Any?): Long` ↔ `IsContOp.doIsCont(f, site, o)`; `istrue(site, o, negate: Int, tc): Long` ↔ `IsTrueOp(site, negate)` and `Truthy(type, negate, site)`; `findmethod(site, o, name: Any?, kind: Int, tc): Any?` ↔ `FindMethodOp(site, kind)` with two dynamic operands; `FIND_FATAL/TRY/CAN` used in both files; `Op.ISCONT/ISTRUE/ISFALSE/FINDMETHOD/FINDMETHOD_TRY/CAN` appear in the enum, the arms, `beginOp` and `endOp`; the `.t` parsers match the census output contract (`  site <Name> calls=... slow=[...]`, `  classlib N Cls.meth`, `  table N name`).
