# Task 10 fix — unblocking the Rakudo post-completion gate

Both blockers were fixable. Neither is a unit-artifact bug: one is a build
template that was never updated for the artifact entry point, the other a
position-bookkeeping bug in the custom_args encoder that the first Rakudo
build on that nqp exposed.

---

## Blocker 1 — the Makefile entered nqp through the `nqp` main class

`tools/templates/jvm/Makefile.in` builds `J_NQP_RR` as a hand-rolled `java`
command line (it is the only place in the build that does not go through
`nqp/nqp-j-gradle`, because BOOTSTRAP/CORE need `-Xmx14G`). It ended on the
main class `nqp`, which does not exist in a unit-artifact `nqp.jar`.

Change (rakudo tree, `tools/templates/jvm/Makefile.in`), the trailing
` nqp` replaced by:

```
org.raku.nqp.runtime.unit.UnitMain @q(@nop($(SYSROOT))@@nfp(@abs2rel(@nqp_classpath@)@/nqp.jar)@)@
```

`@nqp_classpath@` is nqp's `jvm::runtime.classpath`, a single directory
(`runtime.classpath=${libdir}` in `JvmConfigPropertiesTask.kt`), and the
same spelling the line already used for its `-cp` entry — so the unit path
is written exactly like the lib dir next to it, and Configure substitutes
both. This is nqp `15c20930c`'s entry point; `UnitMain` reads a class-road
`nqp.jar` just as happily, so the line is correct either road.

### The generated line (NOT hand-edited)

```
NQP_UNIT=1 RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 \
  raku tools/build/watched-run.raku \
    --log=/home/longwalker/.claude/jobs/b945970f/tmp/configure-gate-2.log \
    --show='BUILD' --show='rror' --show='Makefile' \
    -- perl Configure.pl --backends=jvm --gen-nqp
```

```
=== EXIT=0 verdict=ok elapsed=3s ===
```

`Makefile:235`:

```
J_NQP_RR    = $(JAVA) -Xmx$(J_NQP_MAXHEAP) --module-path .../nqp/build/jvm/share/truffle \
  --add-modules org.graalvm.truffle,org.graalvm.truffle.runtime \
  --enable-native-access=org.graalvm.truffle --sun-misc-unsafe-memory-access=allow \
  -cp 'blib:$(BLD_NQP_JARS):rakudo-runtime.jar:$(SYSROOT)nqp/build/jvm/share/lib:.../nqp-truffle.jar' \
  org.raku.nqp.runtime.unit.UnitMain '$(SYSROOT)nqp/build/jvm/share/lib/nqp.jar'
```

Smoke-tested by running that very variable out of the generated Makefile
(`$(J_NQP_RR) -e 'say("J_NQP_RR_OK")'` → `J_NQP_RR_OK`).

Note: this `Configure.pl` run cleaned the jvm build products (blib jars,
`gen/jvm`, `rakudo-j`), so the gate `make` below is a build from the top,
not the incremental one the previous agent measured.

---

## Blocker 2 — DIAGNOSIS: a missing position shift in the custom_args prologue

It is **not** a wire-layout mismatch. Producer and consumer agree word for
word on every op involved:

| op | encoder (`TruffleEncoder.nqp`) | `NqpWire.java` doc | reader (`NqpProgramBuilder.java`) |
|---|---|---|---|
| `P6BINDSIG` (33) | `epush($W_P6BINDSIG)` — 1 word, 0 operands (line ~2023, arity cbail'd) | "Value null (a statement, like LOOP)" — no operands | `case P6BINDSIG: … return at + 1;` (line 118) |
| `P6TRYBINDSIG` (34) | `epush($W_P6TRYBINDSIG)` — 1 word, 0 operands (line ~2026) | "answers int 1/0" — no operands | `case P6TRYBINDSIG: … return at + 1;` (line 135) |
| `PARAMS` (17) custom_args header | `[$W_PARAMS, 0, -1, 0]` — 4 words | required/accepted/n, then n param records | `params()`: `required=code[at+1]`, `accepted=code[at+2]`, `n=code[at+3]`, `at += 4`, then 0 records — 4 words |

All three match. The `PARAMS 0 -1 0` header decodes cleanly.

### What actually corrupted the program

`patch_params`, custom_args branch (before the fix):

```
my @hdr := nqp::list($W_PARAMS, 0, -1, 0);
nqp::splice(%e<code>, @hdr, $params_at, 1);
return 0;
```

It replaces the **one-word** `$W_PARAMS` placeholder with **four** words, so
the whole encoded body moves right by three. Every nested block recorded its
qbid slot by absolute position during the walk
(`nqp::push(%e<nested>, [nqp::elems(%e<code>), $blk])`, four sites), and those
positions are used much later, after the block's deferred compile:

```
nqp::bindpos(@code, $nb[0] + nqp::elems(@ltypes), $comp.cuid_to_qbid($blk.cuid));
```

The non-custom_args branch does the shift (`nqp::splice(…, $params_at + 1, 0)`
keeps the placeholder in place, then `$nb[0] + nqp::elems(@p)`), and so do
`encode_child` / `coerce_at` for their 2-word coercion splices. The
custom_args branch does neither — it returns immediately. So **every deferred
qbid was written three cells too early**, each landing on another node's tag.

### The failing program, decoded word by word

From `sanity-gate-logs/t_01-sanity_99-test-basic_t.log`
(`unknown tag 11142 at 79 of 1060 words`). Header `2 0 32 3` + 32 local
types, tree at 36.

| at | words | node |
|---|---|---|
| 36 | `1 4` | STMTS, 4 children |
| 38 | `17 0 -1 0` | PARAMS (custom_args header) — 4 words, decodes fine |
| 42 | `1 19` | STMTS, 19 children |
| 44,45,46 | `21 21 21` | JNULL x3 (children 1-3) |
| 47 | `8 0 0` + child | LEXBIND type 0, name pool[0] (child 4) |
| 50 | `27 0 1 2 3 1 1` + 1 arg | CLASSLIB, 1 arg -> arg at 58 |
| 58 | `27 0 1 4 5 1 0` | CLASSLIB, 0 args -> ends at 65 |
| 65…78 | `21` x14 | JNULL x14 (children 5-18) |
| **79** | **`11142`** | child 19 — **should be `1` (STMTS)** |
| 80 | `4` | …its child count, 4 |
| 81,83,85 | **`11143 11144 11145`** | **should be `19` (CODEREF) x3** |
| 82,84,86 | `0 0 0` | those CODEREFs' qbid slots — still unpatched |
| 87,88 | `19 0` | the 4th CODEREF, tag intact, slot still 0 |

The arithmetic pins the mechanism exactly: the four nested blocks' qbid slots
sit at 82, 84, 86, 88. Three words early is 79, 81, 83, 85 — precisely the
four cells holding 11142…11145, and precisely the four cells that should hold
`1` (the STMTS tag of the last statement of the body) and three `19`s. All
four real slots (82/84/86/88) are still 0, and the one CODEREF tag no stray
write reached (87) is still `19`. Nothing else in the program is disturbed.
The qbids themselves are consecutive (11142-11145), as four sibling blocks of
one CORE.c statement would be.

Blame: nqp `d13dcbf69` ("jesp/encoder+engine: custom_args blocks on the
engine") — the branch was added there and never validated on a Rakudo build.
nqp `57460ccd7` (`QAST::VM` encoding) is exonerated: it moves no positions.

### The fix (nqp tree, `src/vm/jvm/QAST/TruffleEncoder.nqp`)

Written exactly as the full prologue below it is — the placeholder stays put,
the three header words go in after it, and the recorded slots are shifted:

```
my @hdr := nqp::list(0, -1, 0);
nqp::splice(%e<code>, @hdr, $params_at + 1, 0);
for %e<nested> -> $nb {
    nqp::bindpos($nb, 0, $nb[0] + nqp::elems(@hdr)) if $nb[0] > $params_at;
}
```

The wire is untouched: same tags, same header, same word counts, nothing
renumbered. Only the encoder's bookkeeping changes. Because the corrupt
programs are baked into `blib`, validating it needs the nqp stage build plus
a full Rakudo `make`.

---

## Blocker 2, second layer — a custom_args block refused named arguments

With the encoder fix in and the whole toolchain rebuilt, the reproducer no
longer failed to decode — it failed differently:

```
$ RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./rakudo-j -e 'say("abc".subst(/b/,"x"))'
Unexpected named argument 'g' passed
```

Same feature, second bug, and this one *is* on the reader. `params()` ends
with

```java
if (emit && !namedSlurpy) {
    // The invoker's expectation check would have rejected extra
    // named arguments before the call; re-make it here.
    b.beginCheckNamedAllowed(namedAllowed.toArray(new String[0]));
    …
}
```

A custom_args header declares **no** parameters, so `namedAllowed` is empty
and `namedSlurpy` is false — the check then rejects every named argument,
which is exactly the set the runtime Binder in the body exists to bind. The
encoder's own comment states the intent ("the header declares none and
accepts any arity … it is what puts csd/args on the frame for the binder to
read"), and `NqpWire.java`'s PARAMS doc says nothing about the named check —
it is a reader-side detail. Doc and encoder agree, so the reader was fixed.

Fix (`NqpProgramBuilder.java`, reader only, wire untouched):

```java
boolean customArgs = n == 0 && accepted == -1;
…
if (emit && !namedSlurpy && !customArgs) { … }
```

`n == 0 && accepted == -1` identifies the shape uniquely: a block that
declares no parameters accepts 0 (`patch_params`: `accepted = $pos_slurpy ??
-1 !! $pos_required + $pos_optional`, and `$pos_slurpy` implies at least one
param record), so nothing else can encode it. Reader-only, so this needed
just `:nqp-truffle:jar syncRuntimeJars` and no CORE rebuild.

After it:

```
$ ./rakudo-j -e 'say("abc".subst(/b/,"x")); say("aba".subst(/a/,"z",:g))'
axc
zbz
```

---

## Runs (verdict lines)

| run | command | verdict |
|---|---|---|
| Configure (after the template fix) | `perl Configure.pl --backends=jvm --gen-nqp` | `=== EXIT=0 verdict=ok elapsed=3s ===` |
| nqp stages (encoder fix) | `./nqp/gradlew -p nqp clean buildJvm` | `=== EXIT=0 verdict=ok elapsed=285s ===` |
| Rakudo build | `make` | `=== EXIT=0 verdict=ok elapsed=1173s ===` |
| nqp-truffle jar (reader fix) | `./nqp/gradlew -p nqp :nqp-truffle:jar syncRuntimeJars` | `=== EXIT=0 verdict=ok elapsed=4s ===` |
| sanity gate | `-t=t/01-sanity --jobs=2 -- ./rakudo-j` | 25 of 25 ok in 210s |

All through `raku tools/build/watched-run.raku`. Logs under
`/home/longwalker/.claude/jobs/b945970f/tmp/`: `configure-gate-2.log`,
`build-task10-fix.log`, `rakudo-gate-2.log`, `truffle-jar.log`,
`sanity-gate-2-logs/`.

The `make` was a build from the top (1173 s), not the previous agent's
981 s incremental one — `Configure.pl` had cleaned the jvm products. It
passed `rakudo.jar`, the recipe that failed before at 182 s, without
an override of any kind: blocker 1 is fixed in the real build.

### Gate SUMMARY (`sanity-gate-2-logs/SUMMARY`)

```
ok 25 of 25
elapsed 210s
runner ./rakudo-j
finished 2026-09-09T14:58:59.903027+02:00
```

25/25, up from the previous agent's 21/25. The four `use`-ing files
(53-transpose, 55-use-trace, 56-use-isms, 99-test-basic) all pass.

---

## Commits and pushes

nqp tree (`nqp/`, branch `jesp-direct-lazy-records`):

- `e1c29714e` — *jesp/encoder: the custom_args header must shift the
  nested-block slots* (`src/vm/jvm/QAST/TruffleEncoder.nqp`)
- `2035d43e2` — *jesp/engine: a custom_args block takes named arguments (the
  Binder binds them)* (`nqp-truffle/…/NqpProgramBuilder.java`)

rakudo tree (branch `worktree-jesp-direct-lazy-records`):

- `a5f9ef3d80` — *Build: the Makefile enters nqp through UnitMain (an
  artifact nqp.jar has no `nqp` class)* (`tools/templates/jvm/Makefile.in`)
- `5d31a79f3c` — *docs: unit artifact milestone 1 post-completion gate green
  — Rakudo builds on the artifact nqp, t/01-sanity 25/25*
  (`docs/jvm-truffle-only-plan.md`, Position rows 5 and 6)

Pushes:

```
rakudo  ab5tract  2133c15a5e..5d31a79f3c  worktree-jesp-direct-lazy-records
nqp     ab5tract  57460ccd7..2035d43e2    jesp-direct-lazy-records
nqp     origin    57460ccd7..2035d43e2    jesp-direct-lazy-records
```

---

## Concerns

- The custom_args feature (nqp `d13dcbf69`) had two independent bugs, both
  found by the first Rakudo build and the first 25 sanity files to touch it.
  Nothing broader than `t/01-sanity` has run on it. A spectest sweep is the
  next honest check of that feature, not this gate.
- `Configure.pl --gen-nqp` cleans the jvm build products (blib jars,
  `gen/jvm`, `rakudo-j`). Re-running it costs a full `make`, ~20 min.
