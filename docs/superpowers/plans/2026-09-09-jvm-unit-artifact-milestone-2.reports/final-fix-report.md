# JVM unit-artifact milestone 2 -- final-review fix wave

nqp tree: `/home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp`
Commit: `da1f5088a0fd1e01393950d043c371e88fc5f793`

## Diff summary

Two files, 8 insertions / 7 deletions, one commit.

### `src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt`

`claimNested` dropped the dead `tc.gc.inMemoryUnitRecords[name]` fallback.
`UnitWriter.record()` already resolves a parent's nested records into
`record.nested` before any parent `ProgramUnit` exists, so the fallback
could only fire for a disk-loaded unit missing its `nested/` entry -- a
case the spec says must be a hard error, not a silent substitution. New
doc comment explains why no fallback is needed.

```diff
--- a/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt
+++ b/src/vm/jvm/runtime/org/raku/nqp/runtime/unit/ProgramUnit.kt
@@ -107,11 +107,12 @@ class ProgramUnit(@JvmField val record: UnitRecord) : CompilationUnit() {
     override fun engineProgram(idx: Int): String = record.programs[idx]
     override fun serializedBlob(): ByteBuffer? = record.serialized?.let { ByteBuffer.wrap(it) }
 
-    /** A nested unit rides in the parent's zip (a loaded artifact) or, for
-     *  a parent that is itself a record in memory, in the process's
-     *  retention map -- the same map the writer embeds from. */
+    /** A nested unit rides in the parent's zip (a loaded artifact); a
+     *  parent built in memory had its nested records resolved into the
+     *  record by UnitWriter.record() before this unit existed. A missing
+     *  entry is a hard error, never a lookup elsewhere. */
     override fun claimNested(tc: ThreadContext, name: String): CompilationUnit {
-        val rec = record.nested[name] ?: tc.gc.inMemoryUnitRecords[name]
+        val rec = record.nested[name]
             ?: throw ExceptionHandling.dieInternal(tc, "unit ${unitId()} carries no nested unit named $name")
         val nested = ProgramUnit(rec)
         nested.shared = tc.gc.sharingHint
```

### `t/nqp/124-unit-record.t`

The three `sh(...)` child commands now set `NQP_CODE_RUN=1
NQP_CODE_PRECOMP=1` explicitly instead of relying on inheriting them from
the harness environment, so the test is self-contained under a bare
`prove`.

```diff
--- a/t/nqp/124-unit-record.t
+++ b/t/nqp/124-unit-record.t
@@ -57,7 +57,7 @@ else {
         run-command(nqp::list('/bin/sh', '-c', $command), :stdout, :stderr)
     }
 
-    my @ran := sh("NQP_UNIT=1 $runner $script");
+    my @ran := sh("NQP_UNIT=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 $runner $script");
     my @out := nqp::split("\n", @ran[1]);
     unless nqp::elems(@out) >= 7 {
         say('# ' ~ @ran[1]);
@@ -75,7 +75,7 @@ else {
     # builds it -- the script and its two EVALs. A separate run: NQP_CODE_WHY
     # also prints the encoder's per-block trace on stdout, which would
     # clobber the positional @out checks above.
-    my @why := sh("NQP_UNIT=1 NQP_CODE_WHY=1 $runner $script");
+    my @why := sh("NQP_UNIT=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 NQP_CODE_WHY=1 $runner $script");
     my int $records := 0;
     for nqp::split("\n", @why[2]) {
         $records := $records + 1 if nqp::index($_, 'unit record ') == 0;
@@ -84,7 +84,7 @@ else {
     ok(nqp::index(@why[2], '.class') < 0 && nqp::index(@why[2], 'defineClass') < 0,
         'nothing on stderr mentions a class');
 
-    my @knob := sh("env -u NQP_CODE_RUN NQP_UNIT=1 $runner -e 'say(1)'");
+    my @knob := sh("env -u NQP_CODE_RUN NQP_CODE_PRECOMP=1 NQP_UNIT=1 $runner -e 'say(1)'");
     ok(nqp::index(@knob[2], 'needs NQP_CODE_RUN=1') >= 0,
         'the road refuses to run without the encoder switches, once');
     ok(nqp::index(@knob[1], '1') < 0, 'and runs nothing');
```

## Gradle tail (runtime jar rebuild + Kotlin tests)

Command: `./nqp/gradlew -p nqp :nqp-runtime:test :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars`

```
> Task :nqp-truffle:compileJava UP-TO-DATE
> Task :nqp-truffle:classes UP-TO-DATE
> Task :nqp-truffle:jar UP-TO-DATE
> Task :syncRuntimeJars
> Task :nqp-runtime:test

[Incubating] Problems report is available at: file:///home/longwalker/code/raku/x.core/rakudo/.claude/worktrees/jesp-direct-lazy-records/nqp/build/reports/problems/problems-report.html

BUILD SUCCESSFUL in 2s
14 actionable tasks: 5 executed, 1 from cache, 8 up-to-date
```

Test result XMLs confirm the expected 15 tests, all green:

```
TEST-org.raku.nqp.runtime.unit.ProgramUnitTest.xml: tests="5" skipped="0" failures="0" errors="0"
TEST-org.raku.nqp.runtime.unit.UnitFormatTest.xml:  tests="10" skipped="0" failures="0" errors="0"
```

## Test commands and TAP output

### Run 1: `t/nqp/124-unit-record.t` with switches set explicitly

```
RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle nqp/t/nqp/124-unit-record.t
```

```
1..11
ok 1 - a sub from a record unit runs
ok 2 - a closure over the mainline keeps its outer
ok 3 - a handler in a record block catches
ok 4 - a regex from a record unit matches and fails to match
ok 5 - an EVAL returns a sub that runs (a record of its own)
ok 6 - an EVAL of statements answers its value
ok 7 - a class (a static lexical value) from a record unit resolves
ok 8 - the script and both EVALs went down the record road (3 records)
ok 9 - nothing on stderr mentions a class
ok 10 - the road refuses to run without the encoder switches, once
ok 11 - and runs nothing
```

### Run 2: `t/nqp/124-unit-record.t` with the switches removed from the harness environment (proves the fix)

```
env -u NQP_CODE_RUN -u NQP_CODE_PRECOMP RAKUDO_RAKUAST=1 ./nqp/nqp-j-gradle nqp/t/nqp/124-unit-record.t
```

```
1..11
ok 1 - a sub from a record unit runs
ok 2 - a closure over the mainline keeps its outer
ok 3 - a handler in a record block catches
ok 4 - a regex from a record unit matches and fails to match
ok 5 - an EVAL returns a sub that runs (a record of its own)
ok 6 - an EVAL of statements answers its value
ok 7 - a class (a static lexical value) from a record unit resolves
ok 8 - the script and both EVALs went down the record road (3 records)
ok 9 - nothing on stderr mentions a class
ok 10 - the road refuses to run without the encoder switches, once
ok 11 - and runs nothing
```

The parent `nqp-j-gradle` process (which itself compiles `124-unit-record.t`
on the class road) ran without the encoder switches, and all 11 assertions
still passed -- confirming the three child `sh(...)` invocations now carry
their own `NQP_CODE_RUN`/`NQP_CODE_PRECOMP`, rather than depending on
inheriting them from the harness.

### Run 3: `t/nqp/123-unit-artifact.t` -- artifact-road check after the runtime jar rebuild

```
RAKUDO_RAKUAST=1 NQP_CODE_RUN=1 NQP_CODE_PRECOMP=1 ./nqp/nqp-j-gradle nqp/t/nqp/123-unit-artifact.t
```

```
1..8
ok 1 - compiled the module on the artifact road
ok 2 - the jar carries unit.meta
ok 3 - the jar carries no class entry
ok 4 - a sub from the artifact runs
ok 5 - a closure over the mainline keeps its outer
ok 6 - a handler in an artifact block catches
ok 7 - a regex from the artifact matches
ok 8 - and fails to match
```

## Commit

```
da1f5088a0fd1e01393950d043c371e88fc5f793 unit artifact: final-review fixes -- claimNested has no in-memory fallback (a missing nested/ entry is the hard error); t/nqp/124 sets the encoder switches for its children
```

2 files changed, 8 insertions(+), 7 deletions(-).
