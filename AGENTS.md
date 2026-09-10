# Working on this branch (truffle-grammar-engine)

Session-start facts that keep getting relearned the hard way:

- **Two git working trees.** This directory is rakudo.git; `nqp/` is the
  nqp.git working tree nested inside it (gitignored via `/nqp/`, NOT a
  submodule). Rakudo's `git status`/`log` never show nqp changes: use
  `git -C nqp ...` for that tree. Label every hash with its tree ("nqp
  801fc47b7" vs "rakudo 9e53b303f5"), write nqp paths with the `nqp/`
  prefix (`nqp/src/vm/jvm/QAST/TruffleEncoder.nqp`, `nqp/nqp-truffle/`),
  and run gradle from here (`./nqp/gradlew -p nqp ...`), never via `cd`.
  A worktree/bisect copy needs BOTH trees plus `git submodule update
  --init 3rdparty/nqp-configure`.
- **`RAKUDO_RAKUAST=1` on every build, test, and run.** The generated
  Makefile exports it into its own recipes (2026-08-29), but nothing sets
  it for your own runs and test invocations, and `src/main.nqp` silently
  falls back to the legacy frontend without it. The encoder and the unit
  road need no export at all: they are on by default since 2026-09-10
  (nqp side; `NQP_CODE_RUN=0` / `NQP_CODE_PRECOMP=0` opt out, and there
  is no class road left in the compiler to opt out *to*), so a bare
  `make` IS the Truffle engine build (frontend, BOOTSTRAP, settings all
  encoded) and every jar it writes is a unit artifact entered through
  `UnitMain`; there is no separate "bytecode build" to compare against,
  and any CORE.c timing must come from a build made this way. The legacy frontend
  (`src/Perl6/`) is off limits — don't read it, reason from it, or measure
  against it.
- **Long builds and test runs go through `tools/build/watched-run.raku`.**
  It tees to a log, streams progress markers (`--show=REGEX`, elapsed-
  seconds prefixed), and watchdogs stalls (`--stall`, default 900s;
  exit 124). Don't hand-roll timestamp wrappers, tail-based monitors, or
  buffering fixes — it already handles piped-handle buffering.

      raku tools/build/watched-run.raku --log=build.log \
          --show='Compiling|Generating' -- sh tools/build/jvm-build.sh jars
      raku tools/build/watched-run.raku -t=t/02-rakudo --jobs=3 -- ./rakudo-j
      raku tools/build/evalserver-sweep.raku --jobs=3 --heap=2 t/01-sanity

  `--show-file=PATH` (2026-09-09) keeps the log unfiltered and writes only
  the marker matches plus the EXIT line there; `--follow=LOG` attaches to
  a run somebody else started (a subagent's build) and streams its
  markers until its EXIT line:

      raku tools/build/watched-run.raku --log=build.log --show-file=build.markers \
          --show='Compiling' -- make
      raku tools/build/watched-run.raku --follow=build.markers

  Both gates run at 3 (decision 2026-09-08): the eval server's own guard
  counts a server as heap + 3g off-heap and refuses a 4th on this box,
  which surfaces as a chunk with no TAP and a 120s token timeout.
    
  - **--show and --show-rx**: Use --show="LITERAL" as many times as you need,
    meaning that --show-rx is never used for an alternation of string literals.
    Instead you would use --show="literal1?" --show="literal2!". Note that
    usage of --show-rx follows Raku regex laws, which means spaces are not
    significant (must be within quotes) and reserved characters like "!" or "?"
    must be quoted. Therefore it is usually simpler to just use a sequence of 
    --show flages instead of --show-rx, but the latter is still useful provided
    you are actually writing a regex and not a "match this or this or this literal"
    operation.
  - In order to make this distinction clearer, *only* --show-rx arguments with surrounding
    '/' characters can be used. It will fail when this is not the case as the argument
    is guarded by the RegexInput subset. Ex: --show-rx='/ ^ \d $ /' will match a string
    with a single digit.

- **Prefer git amend over idle waiting for compilation**
  We can literally always amend our commits with a fix when they break.
  Re-compiling after every change is not feasible at this moment -- making
  compilations and tests run faster is the entire point of our perf work.
  It does sometimes make sense to isolate the work with a test compilation,
  but that should not be the default case. Use a looser cohesion level
  for planning the compilations.

- **`make` builds everything, nqp bootstrap included.**
  `perl Configure.pl --backends=jvm --gen-nqp` builds the nested nqp
  checkout in place via `./nqp/gradlew -p nqp buildJvm` (never git-moving it, never
  cloning upstream — upstream nqp has no Truffle engine) and writes the
  Makefile; a bare `make` then builds through to `rakudo-j`, exporting
  RAKUDO_RAKUAST=1 into its recipes itself. `tools/build/jvm-build.sh`
  stays as the same commands written down (`gen` / `jars` / both). The
  nqp side alone: `./nqp/gradlew -p nqp buildJvm` (add `clean` first
  when `src/vm/jvm/QAST/*.nqp` changed — the stage graph misses that
  edge). If the harness keeps stopping a heavy build task, start it as a
  plain background job (`run_in_background`, NO `setsid`/`nohup`) tee'd to
  a log — `raku tools/build/watched-run.raku --log=build.log -- make` —
  and watch the log. A plain background job stays visible, trackable, and
  killable from the shell interface; `setsid nohup … &` detaches it from
  all of that (dropped 2026-09-06).

- **JVM test runs use the eval server** (`t/harness5 --jvm --evalserver`,
  ~20x faster than cold). Whole-suite sweeps:
  `raku tools/build/evalserver-sweep.raku t/01-sanity ...` — it budgets
  `jobs x heap` against MemAvailable itself; never launch N servers
  without doing the `N x Xmx` vs free-RAM arithmetic.
- **`java` must be Oracle GraalVM 25.2.4** (a plain JDK voids all perf
  numbers).
- **Runtime jars rebuild in seconds, without a setting recompile.** Edits
  under `nqp/src/vm/jvm/runtime/` or `nqp/nqp-truffle/`:
  `./nqp/gradlew -p nqp :nqp-runtime:jar :nqp-truffle:jar syncRuntimeJars`
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
