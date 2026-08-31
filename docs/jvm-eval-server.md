# The JVM eval server

Starting a JVM Rakudo takes ~26 seconds, almost all of it loading and
initializing the compiler. The eval server
(`org.raku.nqp.tools.EvalServer`, from nqp) pays that cost once: it keeps
one warm JVM and runs each program handed to it inside that process. A
test file that costs ~26s cold runs in well under a second warm.

## Running tests against it

    make j-test          # if wired up; otherwise:
    perl t/harness5 --jvm --evalserver t/01-sanity

`t/harness5 --evalserver` starts a server, waits for it to write its
token file, and runs every test file through it. The token file (default
`TESTTOKEN`, override with `RAKUDO_EVALSERVER_TOKEN`) names one server;
concurrent harnesses each need their own token. The harness drives the
server with `tools/build/eval-client.raku`, executed by whatever `raku`
is on `PATH` (override with `RAKUDO_HOST_RAKU`).

By hand:

    ./rakudo-eval-server -cookie mytoken -app ./rakudo.jar &
    # wait for mytoken to appear, then:
    raku tools/build/eval-client.raku mytoken run t/01-sanity/15-sub.t
    raku tools/build/eval-client.raku mytoken exit

The protocol is one request per connection: the client sends
`cookie\0command\0arg...\0` and streams back whatever the run printed.
The server reads the request until EOF before parsing, so the client
half-closes its write side after sending — Raku sockets do not expose
`shutdown(2)`, which is why the client carries one NativeCall.

## Runs are serialized; pools restore parallelism

A server takes its runs strictly one at a time (`RUN_LOCK`):
`System.out`/`System.err` and the dispatch caches on the shared
compilation unit are process-wide, so overlapping runs would redirect
each other's output and trade cold caches mid-run. One server therefore
has no parallelism at all — over a whole suite it merely breaks even
with the cold harness, which ran files in parallel.

`tools/build/evalserver-sweep.raku` runs a pool of servers, each serial
inside, taking chunks of the suite. The pool is sized by **memory, not
cores**: every server may grow to its `-Xmx` ceiling, so `jobs × heap`
is a real reservation, and on a machine without swap an over-committed
pool ends with the kernel's OOM killer — which shoots whatever shares a
cgroup with the JVMs, your terminal included. The sweep reads
`MemAvailable`, budgets 75% of it, derives `jobs × heap` to fit, and
refuses an explicit over-budget combination without `--force`. The
per-server ceiling reaches the launcher through `RAKUDO_EVALSERVER_HEAP`
(default 8g).

## What the server must forget between runs

The compilation unit is loaded once and shared; each run builds a fresh
`GlobalContext` and with it a fresh type universe. Anything recorded
against one run's types can never match the next run's, and anything
that *holds* one run's objects past the run's end pins that run's entire
setting copy (~180MB) for the life of the process. Before each run the
server calls `DispatchBootstrap.resetAll()` (nqp), which:

- resets every linked `DispatchCallSite` to cold,
- clears the helper dispatch sites and the grammar engine's program
  cache,
- runs every action registered through
  `DispatchBootstrap.registerResettable(Runnable)`.

That last hook exists for layers nqp cannot see: rakudo's runtime keeps
dispatch state of its own — `RakOps.rvDecontSites` caches a dispatch
site per *routine object* — and registers its clearing at class-init.
If you add a cache keyed by or holding run-owned objects (routines,
STables, SCs, anything reachable from a `GlobalContext`), register its
clear the same way.

## Post-mortem: the ~180MB-per-run leak (fixed 2026-08-26)

For a while every run retained ~180MB that survived GC, capping a server
at roughly 30 files before its heap filled and runs silently produced no
TAP ("No subtests run" — a passing file looking broken). The holder was
found with Eclipse MAT's dominator analysis on a `jmap -dump:live`
snapshot, and it was not where the first suspicion pointed:

**`java.lang.ApplicationShutdownHooks` held 85% of the heap.**
`FileHandle` registered a JVM shutdown hook *per opened file* whose
closure captured the opening run's `ThreadContext` — and through it the
run's `GlobalContext`, i.e. everything. `SerializationWriter` registered
a debug-leftover hook per writer. Shutdown hooks are only released when
the JVM actually exits, so every finished run's universe stayed pinned.

The fixes, and the rules they imply:

- `FileHandle` now has **one** static shutdown hook iterating a weak
  collection of open handles; dead runs' handles are collected with
  their run, and whatever is genuinely open at JVM exit still gets
  flushed. Never register a shutdown hook per object, and never let a
  hook's closure capture a `ThreadContext`.
- The `SerializationWriter` hook is deleted.
- `IOOps.signal` had the same shape (a hook per call) plus a twist: the
  handler state lived in statics, so each registration overwrote every
  earlier one globally. It now keeps per-registration state in a
  registry served by one hook, cleared between runs through
  `registerResettable` like the dispatch caches.

Measured effect (15 sanity files through one server, live heap after
full GC): 2.87GB → 455MB; SerializationContexts 436 → 59; a further 15
files add ~15MB total. Residual growth is ~1MB/run, so the old
~30-file-per-server ceiling — and the sweep's aggressive
chunk-replacement — are no longer load-bearing.

## Post-mortem: two more ~200MB pins (fixed 2026-08-31, nqp 249159ecb)

A single-server `make j-spectest` OOM'd its 8g heap 38 files in — the
same shape as the shutdown-hook leak, chased the same way, except with
`tools/build/hprof_extract.py` + `hprof_paths.py` (a jcmd heap dump,
reference-graph extraction with weak referents excluded, backward BFS
to GC roots) standing in for MAT. Two holders:

- **`VMNullInstance`** — the process-wide null singleton borrowed its
  STable from the first run's `gc.VMNull` type, pinning run 1's whole
  universe in a static forever. It now builds a self-contained STable;
  nothing looks through the null's STable (serializer and `isnull()`
  go by identity).
- **`TruffleGrammarEngine.STATES`** — weak keys, but the EngineState
  values strongly hold pending captures, and a WeakHashMap only
  expunges on access; between runs each finished run stayed reachable.
  Cleared per run via `registerResettable`, like every other cache.

`tools/build/evalserver-leak-check.sh` re-measures in one command: a
healthy server holds exactly 2 GlobalContexts (its own + the last
run's, released by the next run's resetAll) with live heap flat as
rounds are added. After the fixes, the full 1306-file spectest runs on
one 8g server — 73,273 tests, ~2h20m, RSS sawtoothing under the
ceiling.

The follow-up stall was not a leak: `nqp::cas` compares by object
identity, and the RakuAST frontend was unboxing literal nqp-op
arguments into fresh boxes, so ParallelSequence's consumed-guard never
fired and a second `.iterator` hung in the hyper pipeline holding
RUN_LOCK — one wedged file freezing the whole serialized suite. Fixed
in the frontend (cas exempted from literal unboxing) and the setting
(the guard now uses Bool singletons + eqaddr).
