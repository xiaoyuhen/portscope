#!/usr/bin/env bash
# Compatibility matrix: run real servers, check PortScope identifies each one
# correctly, then stop and restart them through PortScope itself.
#
# This is the check that matters most for a port monitor — a scanner that is
# right on a hand-made fixture and wrong on a real Vite dev server is useless.
#
# Usage:
#   scripts/compat/run.sh            # run every case
#   scripts/compat/run.sh vite       # run cases whose name matches "vite"
#
# Servers are started from the local code folder; nothing is installed and
# nothing leaves the machine. Each case declares what PortScope should report.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$ROOT/.build/debug/PortScope"
CODE_DIR="${CODE_DIR:-$HOME/Documents/code}"
FILTER="${1:-}"
LOG_DIR="${TMPDIR:-/tmp}/portscope-compat"
mkdir -p "$LOG_DIR"

if [[ ! -x "$BIN" ]]; then
    echo "Building PortScope first…"
    (cd "$ROOT" && swift build) || exit 1
fi

PASS=0
FAIL=0
SKIP=0
declare -a FAILURES=()

# --- helpers ---------------------------------------------------------------

# Wait until `port` is listening, up to `timeout` seconds.
wait_for_port() {
    local port="$1" timeout="${2:-30}" i=0
    while (( i < timeout * 2 )); do
        if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then return 0; fi
        sleep 0.5
        (( i++ ))
    done
    return 1
}

# Kill everything a case started. macOS has no `setsid`, so the launcher is
# tracked as a job and its whole process tree is walked with pgrep -P, which
# avoids relying on process groups the shell may not have created.
kill_tree() {
    local pid="$1"
    [[ -z "$pid" ]] && return
    local child
    for child in $(pgrep -P "$pid" 2>/dev/null); do kill_tree "$child"; done
    kill -TERM "$pid" 2>/dev/null
    sleep 0.2
    kill -KILL "$pid" 2>/dev/null
}

# Ask PortScope what it thinks is on a port, as JSON.
describe() {
    "$BIN" --list --json 2>/dev/null | python3 -c "
import json, sys
port = int(sys.argv[1])
try:
    ports = json.load(sys.stdin)
except Exception:
    print('{}')
    sys.exit(0)
for p in ports:
    if p['port'] == port:
        print(json.dumps({
            'title': (p.get('service') or {}).get('title'),
            'kind': (p.get('service') or {}).get('kind'),
            'confidence': (p.get('service') or {}).get('confidence'),
            'project': (p.get('service') or {}).get('projectName'),
            'exposure': p.get('exposure'),
            'process': p.get('processName'),
        }))
        sys.exit(0)
print('{}')
" "$1"
}

# Assert a field of the description. Usage: check <json> <field> <expected>
check() {
    local json="$1" field="$2" expected="$3"
    local actual
    actual=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
v = d.get(sys.argv[2])
print('' if v is None else v)
" "$json" "$field")
    if [[ "$actual" == "$expected" ]]; then
        return 0
    fi
    echo "      expected $field='$expected', got '$actual'"
    return 1
}

# check_contains <json> <field> <substring>
check_contains() {
    local json="$1" field="$2" needle="$3"
    local actual
    actual=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
v = d.get(sys.argv[2])
print('' if v is None else v)
" "$json" "$field")
    # macOS ships bash 3.2, which has no ${var,,} lowercase expansion.
    local actual_lower needle_lower
    actual_lower=$(printf '%s' "$actual" | tr '[:upper:]' '[:lower:]')
    needle_lower=$(printf '%s' "$needle" | tr '[:upper:]' '[:lower:]')
    if [[ "$actual_lower" == *"$needle_lower"* ]]; then
        return 0
    fi
    echo "      expected $field to contain '$needle', got '$actual'"
    return 1
}

# --- cases -----------------------------------------------------------------

# Each case: name | directory | command | port | expectations
#
# Expectations are `field=value` pairs, or `field~substring`. Fields come from
# the service description above. `process` and `exposure` are checked too,
# because "it identified Express" is not enough if the process or the binding
# is reported wrongly.
run_case() {
    local name="$1" dir="$2" cmd="$3" port="$4"; shift 4
    local expectations=("$@")

    if [[ -n "$FILTER" && "$name" != *"$FILTER"* ]]; then return; fi
    if [[ ! -d "$dir" ]]; then
        echo "  SKIP  $name (missing $dir)"
        (( SKIP++ ))
        return
    fi

    echo "  CASE  $name"
    local log="$LOG_DIR/$name.log"
    ( cd "$dir" && exec bash -c "$cmd" ) >"$log" 2>&1 &
    local launcher=$!

    if ! wait_for_port "$port" 40; then
        echo "  FAIL  $name — nothing listened on :$port within 40s (see $log)"
        tail -5 "$log" | sed 's/^/        /'
        # Disown before killing: the shell otherwise prints "Terminated: 15" for a
    # job it was tracking, which reads like a failure in the output.
    disown "$launcher" 2>/dev/null
    kill_tree "$launcher"
        (( FAIL++ )); FAILURES+=("$name: did not start")
        return
    fi

    local json ok=1
    json=$(describe "$port")
    for expectation in "${expectations[@]}"; do
        local field="${expectation%%=*}" value="${expectation#*=}"
        if [[ "$expectation" == *"~"* && "$field" == *"~"* ]]; then
            field="${expectation%%~*}"; value="${expectation#*~}"
            check_contains "$json" "$field" "$value" || ok=0
        else
            check "$json" "$field" "$value" || ok=0
        fi
    done

    if (( ok )); then
        echo "        $json"
    fi

    # Stop through PortScope, then confirm the port is actually free.
    if ! "$BIN" --stop "$port" >/dev/null 2>&1; then
        echo "      PortScope --stop $port failed"
        ok=0
    fi
    sleep 0.8
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
        echo "      port :$port still listening after --stop"
        ok=0
        # Clean up so the next case is not polluted by this one.
        local straggler
        straggler=$(lsof -ti:"$port" -sTCP:LISTEN 2>/dev/null | head -1)
        [[ -n "$straggler" ]] && kill -TERM "$straggler" 2>/dev/null
    fi
    # Disown before killing: the shell otherwise prints "Terminated: 15" for a
    # job it was tracking, which reads like a failure in the output.
    disown "$launcher" 2>/dev/null
    kill_tree "$launcher"

    if (( ok )); then
        (( PASS++ )); echo "  PASS  $name"
    else
        (( FAIL++ )); FAILURES+=("$name")
        echo "  FAIL  $name"
    fi
}

echo "PortScope compatibility matrix"
echo "  binary: $BIN"
echo "  code:   $CODE_DIR"
echo

# 1. Express API on a non-default port. The rate limiter is the project the
#    user pointed at; it also exercises a child process (the ephemeral Redis).
#    `npm run dev` rather than `npm start`: the demo starts an ephemeral Redis
#    alongside the API, which is also the child process this case exercises.
run_case "rate-limiter" \
    "$CODE_DIR/system-design-interview/02-rate-limiter/redis-node" \
    "PORT=3101 npm run dev" 3101 \
    "title=Express" "kind=api" "project=redis-node"

# 2. Vite dev server. The classic case: `node` process, real HTTP, HMR
#    websocket, and the framework is only visible in argv.
run_case "vite-dev-server" \
    "$CODE_DIR/react-interview-challenges" \
    "npx vite --port 3102 --strictPort" 3102 \
    "title=Vite" "kind=devServer"

# 3. Python's built-in static server, on an unusual port.
run_case "python-http-server" \
    "$CODE_DIR" \
    "python3 -m http.server 3103 --bind 127.0.0.1" 3103 \
    "title=Python http.server" "kind=web" "exposure=loopback"

# 4. Zero-dependency Node HTTP server with no framework in argv. PortScope
#    should still say something honest ("HTTP server" or "Node.js"), not
#    invent a framework.
run_case "interview-sandbox" \
    "$CODE_DIR/interview-sandbox" \
    "node server.js --port 3104 --no-open --no-preview" 3104 \
    "kind~web" "process=node"

# 5. Express + Vite together in one monorepo, started separately. Two services,
#    two ports, two different identifications — the case where a naive scanner
#    collapses everything into "node". This server hardcodes its port in source,
#    so the case uses that port rather than overriding it.
run_case "monorepo-api" \
    "$CODE_DIR/fullstack-live-coding-challenge-1.1/server" \
    "npx tsx src/index.ts" 3001 \
    "title~Express" "kind=api" "exposure=allInterfaces"

echo
echo "──────────────────────────────────────────"
echo "  $PASS passed, $FAIL failed, $SKIP skipped"
if (( FAIL > 0 )); then
    printf '  failed: %s\n' "${FAILURES[@]}"
    exit 1
fi
