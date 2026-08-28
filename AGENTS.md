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
          --show='Compiling|Generating' -- make
      raku tools/build/watched-run.raku -t=t/02-rakudo --jobs=5 -- ./rakudo-j

- **JVM test runs use the eval server** (`t/harness5 --jvm --evalserver`,
  ~20x faster than cold). Whole-suite sweeps:
  `raku tools/build/evalserver-sweep.raku t/01-sanity ...` — it budgets
  `jobs x heap` against MemAvailable itself; never launch N servers
  without doing the `N x Xmx` vs free-RAM arithmetic.
- **`java` must be Oracle GraalVM 25.2.4** (a plain JDK voids all perf
  numbers).
- **`make` rebuilds both runtime jars, order-only.** Edits under
  `nqp/src/vm/jvm/runtime/` regenerate
  `nqp/build/jvm/share/runtime/nqp-runtime.jar` via the nested Gradle
  wrapper (~5s) without cascading into a setting recompile — the jar is
  an order-only prerequisite because bytecode does not depend on the
  runtime that executes it. Standalone:
  `cd nqp && ./gradlew :nqp-runtime:jar syncRuntimeJars`, or
  `make rakudo-runtime.jar` for rakudo's own layer. Either way, restart
  any eval servers afterwards — they keep the old jar loaded.
- Long-form docs: `docs/jvm-eval-server.md` (server, sweep, memory
  post-mortem), `docs/jvm-newdisp-port.md` (dispatch port status, plan,
  timings).
