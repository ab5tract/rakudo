#!/bin/sh
# Leak check for the JVM eval server: boot one server, run the given test
# files through it (default: a mixed handful of roast files, three times
# each), force full GCs, and report live GlobalContext/ThreadContext
# counts and live heap. A healthy server shows 2 GlobalContexts: its own
# and the last run's (released by the next run's resetAll). More than
# that, or live heap growing with every added run, is a leak — take a
# heap dump and chase reference paths (see docs/jvm-eval-server.md).
set -e
cd "$(dirname "$0")/../.."

TOKEN=LEAKCHECKTOK
rm -f "$TOKEN"
tail -f /dev/null | RAKUDO_RAKUAST=1 ./rakudo-eval-server -bind-stdin \
    -cookie "$TOKEN" -app ./rakudo.jar > leak-check-server.log 2>&1 &
i=0
while [ ! -s "$TOKEN" ]; do
    i=$((i+1)); [ $i -gt 60 ] && { echo "server never wrote $TOKEN"; exit 1; }
    sleep 2
done

PID=$(pgrep -f 'EvalServer -bind-stdin -cookie LEAKCHECKTOK' | while read -r p; do
    case "$(readlink /proc/$p/exe 2>/dev/null)" in *java*) echo "$p"; break;; esac
done)
[ -n "$PID" ] || { echo "no server java process found"; exit 1; }
echo "server pid $PID"

FILES="${*:-t/spec/S02-types/bool.t t/spec/S03-operators/comparison.t t/spec/S02-literals/string-interpolation.t}"
for round in 1 2 3; do
    for f in $FILES; do
        raku tools/build/eval-client.raku "$TOKEN" run "$f" > /dev/null 2>&1 || true
    done
    jcmd "$PID" GC.run > /dev/null
    jcmd "$PID" GC.run > /dev/null
    echo "--- after round $round ($(echo $FILES | wc -w) files/round)"
    jcmd "$PID" GC.class_histogram 2>/dev/null \
        | grep -E 'GlobalContext$|ThreadContext$|^Total'
done

kill "$PID"
rm -f "$TOKEN"
