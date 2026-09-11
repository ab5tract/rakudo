# Working on this branch (truffle-grammar-engine)

Session-start facts that keep getting relearned the hard way:

- **`RAKUDO_RAKUAST=1` on every build, test, and run.** The generated
  Makefile exports it into its own recipes (2026-08-29), but nothing sets
  it for your own runs and test invocations, and `src/main.nqp` silently
  falls back to the legacy frontend without it. The legacy frontend
  (`src/Perl6/`) is off limits — don't read it, reason from it, or measure
  against it.
- **Long builds and test runs go through `tools/build/watched-run.raku`.**
  It tees to a log, streams progress markers (`--show=REGEX`, elapsed-
  seconds prefixed), and watchdogs stalls (`--stall`, default 900s;
  exit 124). Don't hand-roll timestamp wrappers, tail-based monitors, or
  buffering fixes — it already handles piped-handle buffering.

      raku tools/build/watched-run.raku --log=build.log \
          --show='Compiling|Generating' -- sh tools/build/jvm-build.sh jars
      raku tools/build/watched-run.raku -t=t/02-rakudo --jobs=5 -- ./rakudo-j

- **`make` builds everything, nqp bootstrap included.**
  `perl Configure.pl --backends=jvm --gen-nqp` builds the nested nqp
  checkout in place via `gradlew buildJvm` (never git-moving it, never
  cloning upstream — upstream nqp has no Truffle engine) and writes the
  Makefile; a bare `make` then builds through to `rakudo-j`, exporting
  RAKUDO_RAKUAST=1 into its recipes itself. `tools/build/jvm-build.sh`
  stays as the same commands written down (`gen` / `jars` / both). The
  nqp side alone: `cd nqp && ./gradlew buildJvm` (add `clean` first
  when `src/vm/jvm/QAST/*.nqp` changed — the stage graph misses that
  edge). If the harness keeps stopping a heavy build task, run it
  detached (`setsid nohup raku tools/build/watched-run.raku
  --log=build.log -- make > /dev/null 2>&1 &`) and watch the log.

- **JVM test runs use the eval server** (`t/harness5 --jvm --evalserver`,
  ~20x faster than cold). Whole-suite sweeps:
  `raku tools/build/evalserver-sweep.raku t/01-sanity ...` — it budgets
  `jobs x heap` against MemAvailable itself; never launch N servers
  without doing the `N x Xmx` vs free-RAM arithmetic.
- **`java` must be Oracle GraalVM 25.2.4** (a plain JDK voids all perf
  numbers).
- **Runtime jars rebuild in seconds, without a setting recompile.** Edits
  under `nqp/src/vm/jvm/runtime/` or `nqp/nqp-truffle/`:
  `cd nqp && ./gradlew :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars`
  (~5s) — bytecode does not depend on the runtime that executes it, so
  nothing cascades. Either way, restart any eval servers afterwards —
  they keep the old jar loaded.
- Long-form docs: `docs/jvm-eval-server.md` (server, sweep, memory
  post-mortem), `docs/jvm-newdisp-port.md` (dispatch port status, plan,
  timings).
- **Debug prints in NQP/Rakudo sources are env-gated, always**:
  `nqp::say(...) if nqp::getenvhash()<AN_ENVVAR>;` — never a bare say.
  A bare print bakes into the stage jars, leaks into build output and
  TAP, and forces a rebuild to silence; the gated form ships harmlessly
  and turns on with the envvar when the hunt resumes.
- **The in-tree runners have no installed module repo**: anything with a
  `use` (Test included) needs `-Ilib` — `./rakudo-j -Ilib t/02-.../x.t`.
  A "Bind check failed … INDIRECT_NAME_LOOKUP … not-found" cascade on a
  file whose regexes are innocent is THIS, not a regex regression.
