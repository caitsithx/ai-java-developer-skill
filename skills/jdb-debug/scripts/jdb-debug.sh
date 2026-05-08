#!/usr/bin/env bash
# jdb-debug.sh — Interactive jdb controller via named pipes
#
# Usage:
#   jdb-debug.sh attach <port>        Connect to a JVM debug port
#   jdb-debug.sh detach               Disconnect and clean up
#   jdb-debug.sh status               Show connection state and breakpoints
#   jdb-debug.sh break <class.method> Set a breakpoint
#   jdb-debug.sh clear <class.method> Remove a breakpoint
#   jdb-debug.sh breaks               List all breakpoints
#   jdb-debug.sh cont                 Continue execution
#   jdb-debug.sh step                 Step into
#   jdb-debug.sh next                 Step over
#   jdb-debug.sh print <expr>         Evaluate and print an expression
#   jdb-debug.sh locals               Print local variables
#   jdb-debug.sh where                Print stack trace
#   jdb-debug.sh threads              List threads (capped at 50 lines)
#   jdb-debug.sh cmd <anything>       Send raw jdb command
#
# Env:
#   JDB_WAIT    Seconds to wait for jdb response (default: 2)
#   JAVA_HOME   Used to find jdb if not on PATH

set -euo pipefail

STATE_DIR="/tmp/jdb-debug"
FIFO_IN="${STATE_DIR}/in"
OUT_FILE="${STATE_DIR}/out"
PID_FILE="${STATE_DIR}/pid"
PORT_FILE="${STATE_DIR}/port"
JDB_WAIT="${JDB_WAIT:-2}"
MAX_OUTPUT_LINES=50

# ── Helpers ──

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "  $*"; }

resolve_jdb() {
    if command -v jdb &>/dev/null; then
        echo "jdb"
    elif [[ -n "${JAVA_HOME:-}" ]] && [[ -x "${JAVA_HOME}/bin/jdb" ]]; then
        echo "${JAVA_HOME}/bin/jdb"
    else
        die "jdb not found. Ensure a JDK is installed and jdb is on PATH or JAVA_HOME is set."
    fi
}

is_attached() {
    [[ -f "${PID_FILE}" ]] && kill -0 "$(cat "${PID_FILE}")" 2>/dev/null
}

send_cmd() {
    is_attached || die "Not attached. Run: jdb-debug.sh attach <port>"
    local before
    before=$(wc -c < "${OUT_FILE}" | tr -d ' ')
    echo "$*" > "${FIFO_IN}"
    sleep "${JDB_WAIT}"
    tail -c +"$((before + 1))" "${OUT_FILE}"
}

# ── Commands ──

cmd_attach() {
    local port="${1:?Usage: jdb-debug.sh attach <port>}"
    local jdb_bin
    jdb_bin="$(resolve_jdb)"

    # Kill existing session if any
    if is_attached; then
        echo "Detaching existing session first..."
        cmd_detach 2>/dev/null || true
    fi

    # Kill any other jdb attached to this port
    local existing_pid
    existing_pid=$(lsof -ti :"${port}" -sTCP:ESTABLISHED 2>/dev/null | head -1 || true)
    if [[ -n "${existing_pid}" ]]; then
        local existing_cmd
        existing_cmd=$(ps -p "${existing_pid}" -o comm= 2>/dev/null || true)
        if [[ "${existing_cmd}" == *"jdb"* ]]; then
            echo "Killing existing jdb (PID ${existing_pid}) on port ${port}..."
            kill "${existing_pid}" 2>/dev/null || true
            sleep 1
        fi
    fi

    # Set up state
    mkdir -p "${STATE_DIR}"
    rm -f "${FIFO_IN}" "${OUT_FILE}"
    mkfifo "${FIFO_IN}"
    : > "${OUT_FILE}"

    # Launch jdb via named pipe
    tail -f "${FIFO_IN}" | "${jdb_bin}" -attach "${port}" >> "${OUT_FILE}" 2>&1 &
    local tail_pid=$!
    echo "${tail_pid}" > "${PID_FILE}"
    echo "${port}" > "${PORT_FILE}"

    # Wait for connection
    sleep 2
    if grep -q "Unable to attach" "${OUT_FILE}" 2>/dev/null; then
        cat "${OUT_FILE}"
        cmd_detach 2>/dev/null || true
        die "Failed to attach to port ${port}. Is the JVM running with JDWP enabled?"
    fi

    if grep -q "Initializing jdb" "${OUT_FILE}" 2>/dev/null; then
        echo "Attached to JVM on port ${port}"
        echo "  jdb PID : ${tail_pid}"
        echo "  State   : ${STATE_DIR}/"
    else
        cat "${OUT_FILE}"
        cmd_detach 2>/dev/null || true
        die "Unexpected jdb output. Check if port ${port} has JDWP enabled."
    fi
}

cmd_detach() {
    if [[ -p "${FIFO_IN}" ]]; then
        echo "quit" > "${FIFO_IN}" 2>/dev/null || true
    fi
    if [[ -f "${PID_FILE}" ]]; then
        local pid
        pid="$(cat "${PID_FILE}")"
        kill "${pid}" 2>/dev/null || true
        # Also kill the jdb child process
        pkill -P "${pid}" 2>/dev/null || true
    fi
    # Clean up any remaining tail/jdb processes for this session
    pkill -f "tail -f ${FIFO_IN}" 2>/dev/null || true
    rm -f "${FIFO_IN}" "${PID_FILE}" "${PORT_FILE}"
    echo "Detached."
}

cmd_status() {
    if is_attached; then
        local port pid
        port="$(cat "${PORT_FILE}" 2>/dev/null || echo "unknown")"
        pid="$(cat "${PID_FILE}" 2>/dev/null || echo "unknown")"
        echo "Status  : attached"
        echo "Port    : ${port}"
        echo "PID     : ${pid}"
        echo ""
        echo "Breakpoints:"
        send_cmd "clear" 2>/dev/null || echo "  (unable to query)"
    else
        echo "Status  : detached"
    fi
}

cmd_break() {
    local target="${1:?Usage: jdb-debug.sh break <class.method>}"
    send_cmd "stop in ${target}"
}

cmd_clear() {
    local target="${1:?Usage: jdb-debug.sh clear <class.method>}"
    send_cmd "clear ${target}"
}

cmd_breaks() {
    send_cmd "clear"
}

cmd_cont()    { send_cmd "cont"; }
cmd_step()    { send_cmd "step"; }
cmd_next()    { send_cmd "next"; }
cmd_locals()  { send_cmd "locals"; }
cmd_where()   { send_cmd "where"; }

cmd_print() {
    [[ $# -gt 0 ]] || die "Usage: jdb-debug.sh print <expression>"
    send_cmd "print $*"
}

cmd_threads() {
    local output
    output="$(send_cmd "threads")"
    echo "${output}" | head -n "${MAX_OUTPUT_LINES}"
    local total
    total=$(echo "${output}" | wc -l | tr -d ' ')
    if [[ "${total}" -gt "${MAX_OUTPUT_LINES}" ]]; then
        echo "  ... (${total} total lines, showing first ${MAX_OUTPUT_LINES})"
    fi
}

cmd_raw() {
    [[ $# -gt 0 ]] || die "Usage: jdb-debug.sh cmd <jdb-command>"
    send_cmd "$*"
}

# ── Dispatch ──

case "${1:-help}" in
    attach)   shift; cmd_attach "$@" ;;
    detach)   cmd_detach ;;
    status)   cmd_status ;;
    break)    shift; cmd_break "$@" ;;
    clear)    shift; cmd_clear "$@" ;;
    breaks)   cmd_breaks ;;
    cont)     cmd_cont ;;
    step)     cmd_step ;;
    next)     cmd_next ;;
    print)    shift; cmd_print "$@" ;;
    locals)   cmd_locals ;;
    where)    cmd_where ;;
    threads)  cmd_threads ;;
    cmd)      shift; cmd_raw "$@" ;;
    help|*)
        echo "jdb-debug.sh — Interactive jdb controller via named pipes"
        echo ""
        echo "Session:    attach <port> | detach | status"
        echo "Breakpoints: break <class.method> | clear <class.method> | breaks"
        echo "Execution:  cont | step | next"
        echo "Inspection: print <expr> | locals | where | threads"
        echo "Raw:        cmd <jdb-command>"
        ;;
esac
