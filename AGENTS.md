# Working on this branch (truffle-grammar-engine)

Session-start facts that keep getting relearned the hard way:

- **`RAKUDO_RAKUAST=1` on every build, test, and run.** Nothing sets it for
  you (not the Makefile, not the harness), and `src/main.nqp` silently falls
  back to the legacy frontend without it. The legacy frontend
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

- **Do NOT run `make` (2026-08-28, user instruction).** The rakudo build
  runs through `tools/build/jvm-build.sh` — every command make would have
  run, written down: `gen` refreshes gen/jvm after frontend edits, `jars`
  rebuilds every jar and runner after an nqp rebuild, no argument does
  both. The nqp side builds with `cd nqp && ./gradlew buildJvm` (add
  `clean` first when `src/vm/jvm/QAST/*.nqp` changed — the stage graph
  misses that edge). If the harness keeps stopping a heavy build task,
  run it detached (`setsid nohup sh tools/build/jvm-build.sh jars
  > build.log 2>&1 &`) and watch the log.

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
