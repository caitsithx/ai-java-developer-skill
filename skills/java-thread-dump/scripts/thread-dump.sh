#!/usr/bin/env bash
# thread-dump.sh — Take and analyze Java thread dumps
#
# Usage:
#   thread-dump.sh <jvm-pid>                    Full dump + analysis
#   thread-dump.sh <jvm-pid> --tid <os-pid>     Find specific OS thread
#   thread-dump.sh <jvm-pid> --repeat <N>       N dumps 2s apart (CPU hog confirmation)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
source "${PLUGIN_ROOT}/scripts/common.sh"

JVM_PID=""
OS_TID=""
REPEAT=1
DUMP_DIR="/tmp/thread-dump"

# ── Parse args ──

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tid)    OS_TID="$2"; shift 2 ;;
        --repeat) REPEAT="$2"; shift 2 ;;
        -*)       die "Unknown flag: $1" ;;
        *)
            if [[ -z "${JVM_PID}" ]]; then
                JVM_PID="$1"
            fi
            shift
            ;;
    esac
done

[[ -n "${JVM_PID}" ]] || die "Usage: thread-dump.sh <jvm-pid> [--tid <os-pid>] [--repeat N]"

check_pid "${JVM_PID}" "thread-dump.sh <jvm-pid> [--tid <os-pid>] [--repeat N]"
check_java_process "${JVM_PID}"

JSTACK=$(resolve_jdk_tool jstack)
mkdir -p "${DUMP_DIR}"

# ── Take dump(s) ──

DUMP_FILES=()
for i in $(seq 1 "${REPEAT}"); do
    DUMP_FILE="${DUMP_DIR}/dump-${JVM_PID}-${i}.txt"
    ${JSTACK} "${JVM_PID}" > "${DUMP_FILE}" 2>&1 || die "jstack failed. Try: jstack -F ${JVM_PID}"
    DUMP_FILES+=("${DUMP_FILE}")
    if [[ ${i} -lt ${REPEAT} ]]; then
        sleep 2
    fi
done

DUMP_FILE="${DUMP_FILES[0]}"

echo "═══ Thread Dump Analysis (PID: ${JVM_PID}) ═══"
echo ""

# ── CPU Hog: Find specific OS thread ──

if [[ -n "${OS_TID}" ]]; then
    NID=$(printf '0x%x' "${OS_TID}")
    echo "CPU Hog Lookup: OS PID ${OS_TID} → nid=${NID}"
    echo "───────────────────────────────────────"

    # Extract thread block matching this nid
    THREAD_BLOCK=$(awk -v nid="${NID}" '
        /nid=/ && index($0, "nid=" nid) {found=1; print; next}
        found && /^$/ {found=0; next}
        found {print}
    ' "${DUMP_FILE}")

    if [[ -n "${THREAD_BLOCK}" ]]; then
        echo "${THREAD_BLOCK}"
    else
        echo "Thread with nid=${NID} not found in dump."
        echo "Verify: is PID ${OS_TID} a thread of JVM ${JVM_PID}?"
    fi
    echo ""

    # If repeated dumps, check if thread is stuck
    if [[ ${REPEAT} -gt 1 ]]; then
        echo "Repeat analysis (${REPEAT} dumps, 2s apart):"
        echo "───────────────────────────────────────"
        PREV_LOCATION=""
        for df in "${DUMP_FILES[@]}"; do
            LOCATION=$(awk -v nid="${NID}" '
                /nid=/ && index($0, "nid=" nid) {found=1; next}
                found && /^\tat / {print; found=0}
            ' "${df}")
            if [[ "${LOCATION}" == "${PREV_LOCATION}" && -n "${LOCATION}" ]]; then
                echo "  STUCK → ${LOCATION}"
            else
                echo "  ${LOCATION:-<not found>}"
            fi
            PREV_LOCATION="${LOCATION}"
        done
        echo ""
    fi
fi

# ── Deadlock Detection ──

echo "Deadlocks:"
echo "───────────────────────────────────────"
DEADLOCKS=$(grep -A 20 "Found one Java-level deadlock" "${DUMP_FILE}" 2>/dev/null || true)
if [[ -n "${DEADLOCKS}" ]]; then
    echo "❌ ${DEADLOCKS}"
else
    echo "✅ None detected"
fi
echo ""

# ── Blocked Threads ──

echo "Blocked Threads:"
echo "───────────────────────────────────────"
BLOCKED=$(grep -B 1 "java.lang.Thread.State: BLOCKED" "${DUMP_FILE}" | grep "^\"" || true)
if [[ -n "${BLOCKED}" ]]; then
    BLOCKED_COUNT=$(echo "${BLOCKED}" | wc -l | tr -d ' ')
    echo "⚠️  ${BLOCKED_COUNT} blocked thread(s):"
    echo "${BLOCKED}" | while IFS= read -r line; do
        THREAD_NAME=$(echo "${line}" | grep -oE '^"[^"]+"')
        echo "  ${THREAD_NAME}"
    done

    # Show what they're waiting on
    echo ""
    echo "  Lock details:"
    grep -A 2 "java.lang.Thread.State: BLOCKED" "${DUMP_FILE}" | grep "waiting to lock\|locked" | sed 's/^/    /' | head -20
else
    echo "✅ None"
fi
echo ""

# ── Summary ──

TOTAL=$(grep -c "^\"" "${DUMP_FILE}" || echo "0")
RUNNABLE=$(grep -c "java.lang.Thread.State: RUNNABLE" "${DUMP_FILE}" || echo "0")
WAITING=$(grep -c "java.lang.Thread.State: WAITING\|TIMED_WAITING" "${DUMP_FILE}" || echo "0")
BLOCKED_N=$(grep -c "java.lang.Thread.State: BLOCKED" "${DUMP_FILE}" || echo "0")

echo "Summary:"
echo "  Total: ${TOTAL} threads | Runnable: ${RUNNABLE} | Waiting: ${WAITING} | Blocked: ${BLOCKED_N}"
echo ""
echo "Full dump: ${DUMP_FILE}"
