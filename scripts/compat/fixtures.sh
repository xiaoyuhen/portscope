#!/usr/bin/env bash
# Portable compatibility matrix.
#
# Starts real servers, asks PortScope what each one is, then stops it through
# PortScope and confirms the port is actually free. Unlike scripts/compat/run.sh
# this needs nothing outside this repository and installs nothing: the servers
# are small files written here, run with the Python and Node already on a Mac.
# That is what makes it runnable in CI.
#
# Usage:
#   scripts/compat/fixtures.sh          # every case
#   scripts/compat/fixtures.sh express  # cases whose name matches "express"
#   PORT_SCOPE_BIN=… scripts/compat/fixtures.sh
#
# Exit code is 1 if any case fails.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="${PORT_SCOPE_BIN:-$ROOT/.build/release/PortScope}"
[[ -x "$BIN" ]] || BIN="$ROOT/.build/debug/PortScope"
FILTER="${1:-}"
WORK="${TMPDIR:-/tmp}/portscope-fixtures"
LOG_DIR="$WORK/logs"

# Ports are deliberately high and uncommon, so a case cannot collide with
# whatever the developer already has running.
PORT_EXPRESS=34101
PORT_PYTHON=34102
PORT_NODE=34103
PORT_REDIS=34104

mkdir -p "$WORK" "$LOG_DIR"
trap 'cleanup' EXIT

# `python3` is not guaranteed to be on PATH: a bare macOS install may only have
# `python3.9`, and CI images vary. Find one, or skip the Python case rather than
# failing the suite for a reason unrelated to PortScope.
PYTHON=""
for candidate in python3 python3.13 python3.12 python3.11 python3.10 python3.9; do
    if command -v "$candidate" >/dev/null 2>&1; then PYTHON="$candidate"; break; fi
done

# A `python3` on PATH is not the same as a working one: on macOS it is often a
# stub that checks for Command Line Tools on first run, which can take longer
# than the case's startup timeout. Preflight it once, so a machine without a
# usable interpreter skips the case instead of failing it.
if [[ -n "$PYTHON" ]] && ! "$PYTHON" -c 'import http.server' >/dev/null 2>&1; then
    echo "  note: $PYTHON cannot import http.server; skipping the Python case"
    PYTHON=""
fi

PASS=0
FAIL=0
declare -a FAILURES=()
declare -a STARTED=()

cleanup() {
    for pid in "${STARTED[@]:-}"; do
        [[ -n "$pid" ]] && kill_tree "$pid"
    done
}

# --- helpers ---------------------------------------------------------------

wait_for_port() {
    local port="$1" timeout="${2:-20}" i=0
    while (( i < timeout * 2 )); do
        if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then return 0; fi
        sleep 0.5
        (( i++ ))
    done
    return 1
}

# macOS has no `setsid`; walk the tree with pgrep -P instead of relying on a
# process group the shell may not have created.
kill_tree() {
    local pid="$1"
    [[ -z "$pid" ]] && return
    local child
    for child in $(pgrep -P "$pid" 2>/dev/null); do kill_tree "$child"; done
    kill -TERM "$pid" 2>/dev/null
    sleep 0.2
    kill -KILL "$pid" 2>/dev/null
}

describe() {
    "$BIN" --list --json 2>/dev/null | python3 -c "
import json, sys
port = int(sys.argv[1])
try:
    ports = json.load(sys.stdin)
except Exception:
    print('{}'); sys.exit(0)
for p in ports:
    if p['port'] == port:
        print(json.dumps({
            'title': (p.get('service') or {}).get('title'),
            'kind': (p.get('service') or {}).get('kind'),
            'project': (p.get('service') or {}).get('projectName'),
            'exposure': p.get('exposure'),
            'process': p.get('processName'),
        }))
        sys.exit(0)
print('{}')
" "$1"
}

field_of() {
    python3 -c "
import json, sys
d = json.loads(sys.argv[1])
v = d.get(sys.argv[2])
print('' if v is None else v)
" "$1" "$2"
}

check() {
    local json="$1" field="$2" expected="$3" actual
    actual=$(field_of "$json" "$field")
    [[ "$actual" == "$expected" ]] && return 0
    echo "      expected $field='$expected', got '$actual'"
    return 1
}

check_contains() {
    local json="$1" field="$2" needle="$3" actual actual_lower needle_lower
    actual=$(field_of "$json" "$field")
    # bash 3.2 (macOS) has no ${var,,}.
    actual_lower=$(printf '%s' "$actual" | tr '[:upper:]' '[:lower:]')
    needle_lower=$(printf '%s' "$needle" | tr '[:upper:]' '[:lower:]')
    [[ "$actual_lower" == *"$needle_lower"* ]] && return 0
    echo "      expected $field to contain '$needle', got '$actual'"
    return 1
}

# --- fixtures --------------------------------------------------------------
# Written once, in a temp dir. Each one is the smallest server that produces
# the signal being tested.

write_fixtures() {
    # An Express-shaped HTTP server: sends `X-Powered-By: Express`, which is the
    # header PortScope's HTTP tier keys on. Uses Node's stdlib, so there is no
    # `npm install` and no network access.
    cat > "$WORK/express.js" <<'JS'
const http = require('http');
const port = Number(process.argv[2]);
http.createServer((req, res) => {
  res.setHeader('X-Powered-By', 'Express');
  res.setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify({ ok: true, path: req.url }));
}).listen(port, '127.0.0.1', () => console.log(`listening on ${port}`));
JS

    # A framework-less Node server: no identifying header and nothing in argv,
    # so PortScope must answer honestly rather than invent a framework.
    cat > "$WORK/plain-node.js" <<'JS'
const http = require('http');
const port = Number(process.argv[2]);
http.createServer((req, res) => res.end('hello')).listen(port, '127.0.0.1');
JS

    # A directory with a package.json, so the project directory is detectable.
    mkdir -p "$WORK/project"
    printf '{"name":"fixture-app","version":"1.0.0"}\n' > "$WORK/project/package.json"
}

# --- cases -----------------------------------------------------------------

# Each case: name | directory | command | port | expectations
run_case() {
    local name="$1" dir="$2" cmd="$3" port="$4"; shift 4
    local expectations=("$@")

    if [[ -n "$FILTER" && "$name" != *"$FILTER"* ]]; then return; fi

    echo "  CASE  $name"
    local log="$LOG_DIR/$name.log"
    # `disown` before the job can be reaped keeps the shell from printing
    # "Terminated: 15" for a job it was tracking, which reads like a failure.
    ( cd "$dir" && exec bash -c "$cmd" ) >"$log" 2>&1 &
    local launcher=$!
    STARTED+=("$launcher")
    disown "$launcher" 2>/dev/null

    if ! wait_for_port "$port" 20; then
        echo "  FAIL  $name — nothing listened on :$port"
        # Print the whole log, not a tail: a server that failed to start has
        # usually written one short error, and a tail can miss it entirely.
        if [[ -s "$log" ]]; then
            sed 's/^/        | /' "$log"
        else
            echo "        | (the server wrote nothing before exiting)"
        fi
        kill_tree "$launcher"
        (( FAIL++ )); FAILURES+=("$name: did not start")
        return
    fi

    local json ok=1
    json=$(describe "$port")
    for expectation in "${expectations[@]}"; do
        local field="${expectation%%=*}" value="${expectation#*=}"
        if [[ "$expectation" == *"~"* ]]; then
            field="${expectation%%~*}"; value="${expectation#*~}"
            check_contains "$json" "$field" "$value" || ok=0
        else
            check "$json" "$field" "$value" || ok=0
        fi
    done

    # Stop through PortScope itself, then confirm the port really is free.
    if ! "$BIN" --stop "$port" >/dev/null 2>&1; then
        echo "      PortScope --stop $port failed"
        ok=0
    fi
    sleep 0.8
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
        echo "      port :$port still listening after --stop"
        ok=0
    fi

    kill_tree "$launcher"

    if (( ok )); then
        (( PASS++ )); echo "  PASS  $name — $json"
    else
        (( FAIL++ )); FAILURES+=("$name"); echo "  FAIL  $name"
    fi
}

if [[ ! -x "$BIN" ]]; then
    echo "Building PortScope first…"
    (cd "$ROOT" && swift build -c release) || exit 1
    BIN="$ROOT/.build/release/PortScope"
fi

echo "PortScope portable compatibility matrix"
echo "  binary: $BIN"
echo "  work:   $WORK"
echo "  node:   $(command -v node || echo 'not found')"
echo "  python: ${PYTHON:-not found}"
echo

# Three of the four cases need Node. Without it there is nothing meaningful to
# run, and a silent pass would be worse than a loud skip.
if ! command -v node >/dev/null 2>&1; then
    echo "  node is required for the compatibility matrix; install Node.js first." >&2
    exit 1
fi

write_fixtures

# 1. Express identification from the HTTP tier alone. The process is plain
#    `node`, so only the header can produce "Express".
run_case "express-header" "$WORK" \
    "node express.js $PORT_EXPRESS" "$PORT_EXPRESS" \
    "title=Express" "kind=api" "exposure=loopback"

# 2. A framework-less Node server. PortScope must not invent a framework: the
#    honest answer is a generic web/HTTP label with `node` as the process.
run_case "plain-node" "$WORK" \
    "node plain-node.js $PORT_NODE" "$PORT_NODE" \
    "kind~web" "process=node"

# 3. Python's built-in static server, loopback-bound. Tests the process tier
#    for an interpreter whose argv is the only signal. Skipped when no Python
#    is installed: the point is PortScope, not the machine's toolchain.
if [[ -n "$PYTHON" ]]; then
    run_case "python-http-server" "$WORK" \
        "$PYTHON -m http.server $PORT_PYTHON --bind 127.0.0.1" "$PORT_PYTHON" \
        "title=Python http.server" "kind=web" "exposure=loopback"
else
    echo "  SKIP  python-http-server (no python3 on PATH)"
fi

# 4. Project directory attribution: a server started from a directory with a
#    package.json should report that project. The name is the directory's
#    basename — the manifest is what makes it a project root, not the label
#    inside it, which is often a package name rather than the folder's.
run_case "project-directory" "$WORK/project" \
    "node ../plain-node.js $PORT_REDIS" "$PORT_REDIS" \
    "kind~web" "project=project"

echo
echo "──────────────────────────────────────────"
echo "  $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
    printf '  failed: %s\n' "${FAILURES[@]}"
    exit 1
fi
