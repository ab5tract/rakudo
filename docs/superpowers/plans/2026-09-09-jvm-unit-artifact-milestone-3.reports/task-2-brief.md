### Task 2: The flip: defaults on, runners through UnitMain, the booked minors

**Files:**
- Modify: `nqp/src/vm/jvm/QAST/TruffleEncoder.nqp:400` and `:424` (`$code_run`, `$code_precomp` defaults)
- Modify: `nqp/src/vm/jvm/QAST/Compiler.nqp:4102-4126` (road decision), after `:4689` (mainline `cr_file`)
- Modify: `nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/ExceptionHandling.kt:372-385` (`mappedLine`)
- Modify: `nqp/src/HLL/Compiler.nqp:619` (`dumper`)
- Modify: `nqp/t/nqp/124-unit-record.t:87-90`
- Modify: rakudo `tools/build/create-jvm-runner.pl:233-240` (six `install` lines)
- Modify: rakudo `tools/templates/jvm/rakudo-j-build.in:3-4`
- Modify: rakudo `docs/jvm-eval-server.md:57-60`
- Test: `nqp/t/nqp/124-unit-record.t`, `nqp/t/nqp/123-unit-artifact.t` (unchanged; still pass `NQP_UNIT=1` explicitly), rakudo `t/01-sanity`, `t/02-rakudo/*-precomp.t` (14 files), `t/03-jvm`, `t/10-qast`, `nqp/t/qast`

**Interfaces:**
- Consumes: Task 1's nqp build (encoder shapes); `org.raku.nqp.runtime.unit.UnitMain <unit jar> args...` (milestone 1); `LibraryLoader.load`'s `ModuleLoader.class` special case; `HLL::Backend::JVM.is_compunit` (`nqp/src/vm/jvm/HLL/Backend.nqp:117`).
- Produces: the knob semantics every later task and every runner relies on: unset = on, `NQP_UNIT=0` / `NQP_CODE_RUN=0` / `NQP_CODE_PRECOMP=0` = off; the runner scripts `rakudo-j`, `perl6-j`, `rakudo-jdb-server`, `perl6-jdb-server`, `rakudo-debug-j`, `perl6-debug-j` ending in `org.raku.nqp.runtime.unit.UnitMain <jardir>/rakudo.jar "$@"` (debug variants `rakudo-debug.jar`); `rakudo-j-build` likewise.

- [ ] **Step 1: Encoder switches default on**

`nqp/src/vm/jvm/QAST/TruffleEncoder.nqp:400`:

```
        # ON by default since milestone 3 (2026-09-09): the engine build is
        # the build. NQP_CODE_RUN=0 turns the encoder off (class road only;
        # meaningless on the unit road, where Compiler.nqp dies on it).
        $code_run := nqp::existskey(%env, 'NQP_CODE_RUN')
            ?? (nqp::atkey(%env, 'NQP_CODE_RUN') ne '0' ?? 1 !! 0)
            !! 1;
```

and `:424`:

```
        $code_precomp  := nqp::existskey(%env, 'NQP_CODE_PRECOMP')
            ?? (nqp::atkey(%env, 'NQP_CODE_PRECOMP') ne '0' ?? 1 !! 0)
            !! 1;
```

Update the knob table comment at lines 288-294 ("NQP_CODE_RUN=1 master switch" -> "on by default; =0 off"; same for PRECOMP).

- [ ] **Step 2: The road decision defaults to the unit road**

`nqp/src/vm/jvm/QAST/Compiler.nqp:4114-4122` becomes (one `%env` read; the comment above it gains the milestone-3 sentence "The unit road is the default since milestone 3; NQP_UNIT=0 is the transitional opt-out and goes with the deletions."):

```
        my %env := nqp::getenvhash();
        my $*UNIT_ROAD := nqp::existskey(%env, 'NQP_UNIT')
            ?? (nqp::atkey(%env, 'NQP_UNIT') ne '0' ?? 1 !! 0)
            !! 1;
        my $*UNIT_FALLBACKS := 0;
        if $*UNIT_ROAD {
            # Every block must encode, so the encoder's own switches must
            # be on; said once here rather than once per block at the
            # fallback junction.
            nqp::die('unit artifact (NQP_UNIT): the road needs the encoder on; NQP_CODE_RUN=0 or NQP_CODE_PRECOMP=0 is set, every block must encode')
                if (nqp::existskey(%env, 'NQP_CODE_RUN') && nqp::atkey(%env, 'NQP_CODE_RUN') eq '0')
                || (nqp::existskey(%env, 'NQP_CODE_PRECOMP') && nqp::atkey(%env, 'NQP_CODE_PRECOMP') eq '0');
```

(the `--target=classfile` refusal at :4124-4125 stays as it is).

- [ ] **Step 3: t/nqp/124's knob assertion follows the new default**

`nqp/t/nqp/124-unit-record.t:87-90` becomes:

```
    my @knob := sh("NQP_CODE_RUN=0 NQP_CODE_PRECOMP=1 NQP_UNIT=1 $runner -e 'say(1)'");
    ok(nqp::index(@knob[2], 'needs the encoder on') >= 0,
        'the road refuses to run with the encoder switched off, once');
    ok(nqp::index(@knob[1], '1') < 0, 'and runs nothing');
```

- [ ] **Step 4: Rakudo runners enter through UnitMain**

`tools/build/create-jvm-runner.pl`: after line 52 (`$rakudo_jars` built) add

```perl
# The app unit: a unit artifact since milestone 3 (no generated main class),
# entered through the runtime's UnitMain with the unit path as first argument.
my $app  = File::Spec->catfile($jardir, $debugger ? 'rakudo-debug.jar' : 'rakudo.jar');
my $main = "org.raku.nqp.runtime.unit.UnitMain $app";
```

and change the six `install` lines (233-240) to use `$main` in place of `perl6` / `rakudo-debug`:

```perl
if ($debugger) {
    install "rakudo-debug-j", "java $jopts $main";
    install "perl6-debug-j", "java $jopts $main";
}
else {
    install "rakudo-j", "java$userjvm $jopts $main";
    install "perl6-j", "java$userjvm $jopts $main";
    install "rakudo-jdb-server", "java $jdbopts $jopts $main";
    install "perl6-jdb-server", "java $jdbopts $jopts $main";
```

(`$postamble` appends `"$@"` after `$command`, so the app path precedes the user's arguments, as `UnitMain` expects. The eval-server lines 330-331 are unchanged: `EvalServer` is a real class and takes the app as `-app <path>`.)

`tools/templates/jvm/rakudo-j-build.in`: in both the unix line 3 and the windows line 4 replace `'perl6', @ARGV` with `'org.raku.nqp.runtime.unit.UnitMain', 'rakudo.jar', @ARGV` (the build runner runs from the rakudo root where `rakudo.jar` is written).

- [ ] **Step 5: Backtrace filename on the record road**

`nqp/src/vm/jvm/QAST/Compiler.nqp`, right after the `elsif $node.node && nqp::can($node.node, 'orig')` block ends (after line 4689, before `$*CODEREFS.register_method($*JMETH, $node.cuid);`):

```
            # The mainline (built from the comp_unit cursor before it
            # matched) and the compiler's own raw wrappers have no node to
            # take a file from. The class road backfilled them from the
            # class-level SourceFile attribute through the Java stack; a
            # ProgramUnit has no such class, so the block record carries
            # the unit's file itself (milestone 3, 2026-09-09).
            unless $*JMETH.cr_file {
                my $unit-file := nqp::ifnull(nqp::getlexdyn('$?FILES'), '');
                $*JMETH.cr_file(~$unit-file) if $unit-file;
            }
```

`nqp/src/vm/jvm/runtime/org/raku/nqp/runtime/ExceptionHandling.kt`, `mappedLine` (line 381-383): when no native frame correlated, answer the block's declared start line instead of -1:

```kotlin
                return if (si.sourceFile != null && line >= 0)
                    line - si.sourceLineDelta
                else if (line < 0 && si.sourceFile != null && si.sourceLine > 0)
                    si.sourceLine
                else line
```

(`StaticCodeInfo.sourceLine`, `StaticCodeInfo.kt:136`, defaults to -1; `ProgramUnit.kt:45-53` fills it from `BlockRec.sourceLine` when the block has a file, which after the Compiler.nqp change above the mainline has, with `cr_line` 0. So the mainline answers `(-e)` without a line and a named sub answers `(-e:N)`.)

- [ ] **Step 6: The dumper refuses a compilation-unit carrier**

`nqp/src/HLL/Compiler.nqp:619`:

```
    method dumper($obj, $name, *%options) {
        # A compilation unit (the jar/classfile targets without --output)
        # has no textual dump; say so instead of dying inside nqp::can on
        # a carrier object that has no STable.
        if $!backend.is_compunit($obj) {
            nqp::die("--target=$name produces no dumpable output; use --output=<file>");
        }
        if nqp::can($obj, 'dump') {
```

- [ ] **Step 7: Docs sentence**

`docs/jvm-eval-server.md:57-60`: replace the sentence saying `NQP_CODE_RUN`/`NQP_CODE_PRECOMP` "come from the caller" with: "Since milestone 3 of the unit artifact (2026-09-09) the encoder and the unit road are on by default; nothing needs exporting beyond `RAKUDO_RAKUAST=1`, which the script exports itself. `NQP_UNIT=0`, `NQP_CODE_RUN=0`, `NQP_CODE_PRECOMP=0` opt out."

- [ ] **Step 8: nqp clean build WITHOUT the knobs (the test of the defaults)**

```
RAKUDO_RAKUAST=1 NQP_CODE_STRICT=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t2-build.log --show='> Task :stage' --show='code-bail' --show='BUILD' --show='rror' -- ./nqp/gradlew -p nqp clean buildJvm
```

Expected: EXIT=0; all 11 `nqp/build/jvm/share/lib/*.jar` are `unit.meta`=1, `.class`=0. If a jar comes out as a class-road jar, the gradle daemon's environment still carried `NQP_UNIT`/`NQP_CODE_*` from an earlier shell OR the default did not take: `./nqp/gradlew --stop` and rerun once; then read `run_init`.

- [ ] **Step 9: t/nqp, t/qast, 123 and 124 under the defaults**

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=nqp/t/nqp -t=nqp/t/qast --jobs=3 --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t2-sweep.log -- nqp/nqp-j-gradle
```

Expected: 118/118 t/nqp (with 019/063 from the nqp dir) and t/qast 2/2. A t/qast failure mentioning hll `nqp` vs `""` is milestone-2 minor 4 (`record()` maps `""` to `"nqp"`): fix in `UnitWriter.record` by keeping the JAST class's hll string verbatim, and note it in the ledger.

- [ ] **Step 10: Rakudo configure + make, no knobs in the environment**

`Configure.pl --gen-nqp` regenerates the runners through `create-jvm-runner.pl` and cleans the jvm products (a full ~20 min make follows either way):

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t2-configure.log -- perl Configure.pl --backends=jvm --gen-nqp
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t2-make.log --show='Compiling' --show='Generating' --show='rror' --stall=1500 -- make
```

Expected: configure EXIT=0 and `nqp/build/jvm/share/lib/nqp.jar` still `unit.meta`-only afterwards (if `--gen-nqp` rebuilt nqp it did so under the defaults, so the check must still hold); make EXIT=0. Record the make elapsed and the marker times (rakudo.jar, BOOTSTRAP v6c, CORE.c, CORE.d, CORE.e) as the next baseline. Then the artifact census, all from the rakudo root, one plain command per jar: `rakudo.jar`, `blib/CORE.c.setting.jar`, `blib/CORE.d.setting.jar`, `blib/CORE.e.setting.jar`, every `blib/Perl6/*.jar`, `blib/Perl6/BOOTSTRAP/*.jar`, `blib/Raku/*.jar`: `unzip -l <jar> | grep -c unit.meta` = 1 and `| grep -c '\.class'` = 0. Then the nested units: `unzip -l blib/CORE.c.setting.jar | grep -c 'nested/'` = 8 (four units, `.meta` + `.programs` each), the milestone-2 prediction. Then `grep -c UnitMain rakudo-j` = 1 and `grep -c "'perl6'" rakudo-j-build` = 0.

- [ ] **Step 11: The Rakudo gate on artifact units**

```
RAKUDO_RAKUAST=1 ./rakudo-j -e 'BEGIN { say 1 }; say EVAL "2"; say 3'
```
Expected `1 2 3` (each on its line) and, with `NQP_CODE_WHY=1 2>&1 | grep -c '^unit record '`, 3.

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=t/01-sanity --jobs=2 --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t2-sanity.log -- ./rakudo-j
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=t/03-jvm -t=t/10-qast --jobs=1 --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t2-jvm.log -- ./rakudo-j -Ilib
```
Expected: 25/25; t/03-jvm/01-interop.t and t/10-qast pass (the 2026-09-05 record has both passing).

The precomp round trip (the store slurps the artifact as bytes, prepends its header, loads it back through `nqp::loadbytecodebuffer` from an offset; `LibraryLoader.load(tc, ByteBuffer)` sniffs it):

```
RAKUDO_RAKUAST=1 raku tools/build/watched-run.raku -t=t/02-rakudo/begin-closure-doc-precomp.t -t=t/02-rakudo/begin-regex-precomp.t -t=t/02-rakudo/begin-value-container-precomp.t -t=t/02-rakudo/compose-added-method-precomp.t -t=t/02-rakudo/constant-from-gather-precomp.t -t=t/02-rakudo/core-pseudo-package-precomp.t -t=t/02-rakudo/generic-native-precomp.t -t=t/02-rakudo/grammar-named-as-core-type-precomp.t -t=t/02-rakudo/precomp-declarator-block-or-hash.t -t=t/02-rakudo/rakuast-suspend-precomp-deps.t -t=t/02-rakudo/role-whatever-param-precomp.t -t=t/02-rakudo/trait-whatever-arg-precomp.t -t=t/02-rakudo/unit-lexical-precomp-repossess.t -t=t/02-rakudo/whatever-default-precomp.t --jobs=2 --log=/home/longwalker/.claude/jobs/288cfddd/tmp/t2-precomp.log -- ./rakudo-j -Ilib
```
Expected: all pass, or fail exactly as the 2026-09-05 record lists (none of these 14 is in that record's failing list for t/02-rakudo). A failure whose diagnostic names `unit.meta`, `UnitZip`, `loadbytecodebuffer` or `ProgramUnit` is a flip regression to fix here; anything else is reported.

The two minors:

```
RAKUDO_RAKUAST=1 ./rakudo-j -e 'sub f() { die "x" }; f()' 2>&1 | grep -E 'in (sub f|block <unit>|<mainline>)'
```
Expected: every frame line carries `(-e:N)` or `(-e)`; none is a bare `in <mainline>` without a file.

```
RAKUDO_RAKUAST=1 ./rakudo-j --target=jar -e 'say 1' 2>&1 | head -2
```
Expected: `--target=jar produces no dumpable output; use --output=<file>`, no `lateinit`.

- [ ] **Step 12: Commit both trees**

nqp:
```
cd /home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp && git add src/vm/jvm/QAST/TruffleEncoder.nqp src/vm/jvm/QAST/Compiler.nqp src/vm/jvm/runtime/org/raku/nqp/runtime/ExceptionHandling.kt src/HLL/Compiler.nqp t/nqp/124-unit-record.t && git commit -m "unit artifact: the unit road and the encoder are the defaults (NQP_UNIT=0 / NQP_CODE_RUN=0 / NQP_CODE_PRECOMP=0 opt out); the mainline block carries the unit's file; --target=jar without --output says so" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01FyzDsYsbo1z8DspSvLpx5B"
```
rakudo (from the worktree root):
```
git add tools/build/create-jvm-runner.pl tools/templates/jvm/rakudo-j-build.in docs/jvm-eval-server.md && git commit -m "JVM: Rakudo runs as unit artifacts -- runners and the build runner enter through UnitMain <rakudo.jar>" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01FyzDsYsbo1z8DspSvLpx5B"
```

---

