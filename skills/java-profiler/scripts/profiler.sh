#!/usr/bin/env bash
# profiler.sh — Java CPU/memory/lock profiler via async-profiler or JFR
#
# Usage:
#   profiler.sh start <pid> [--event cpu|alloc|lock|wall] [--duration 30]
#   profiler.sh stop <pid>
#   profiler.sh status <pid>
#   profiler.sh flamegraph <pid>
#   profiler.sh top <pid> [--limit 20]
#   profiler.sh diff <file1.jfr> <file2.jfr>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
source "${PLUGIN_ROOT}/scripts/common.sh"

OUTPUT_DIR="${PROFILE_OUTPUT:-/tmp/java-profiler}"
DURATION="${PROFILE_DURATION:-30}"
EVENT="cpu"
LIMIT=20
COMMAND=""
PID=""
DIFF_FILE1=""
DIFF_FILE2=""

# ── Parse args ──

while [[ $# -gt 0 ]]; do
    case "$1" in
        --event)    EVENT="$2"; shift 2 ;;
        --duration) DURATION="$2"; shift 2 ;;
        --limit)    LIMIT="$2"; shift 2 ;;
        -*)         die "Unknown flag: $1" ;;
        *)
            if [[ -z "${COMMAND}" ]]; then
                COMMAND="$1"
            elif [[ -z "${PID}" ]]; then
                PID="$1"
            elif [[ "${COMMAND}" == "diff" && -z "${DIFF_FILE1}" ]]; then
                DIFF_FILE1="$1"
            elif [[ "${COMMAND}" == "diff" ]]; then
                DIFF_FILE2="$1"
            fi
            shift
            ;;
    esac
done

[[ -n "${COMMAND}" ]] || die "Usage: profiler.sh <start|stop|status|flamegraph|top|diff> <pid> [options]"

mkdir -p "${OUTPUT_DIR}"

# ── Detect profiler ──

PROFILER=""
ASPROF=""

detect_profiler() {
    if command -v asprof &>/dev/null; then
        PROFILER="async"
        ASPROF="asprof"
    elif [[ -n "${ASYNC_PROFILER_HOME:-}" ]] && [[ -x "${ASYNC_PROFILER_HOME}/bin/asprof" ]]; then
        PROFILER="async"
        ASPROF="${ASYNC_PROFILER_HOME}/bin/asprof"
    elif [[ -x "/opt/async-profiler/bin/asprof" ]]; then
        PROFILER="async"
        ASPROF="/opt/async-profiler/bin/asprof"
    elif command -v jcmd &>/dev/null; then
        PROFILER="jfr"
    elif [[ -n "${JAVA_HOME:-}" ]] && [[ -x "${JAVA_HOME}/bin/jcmd" ]]; then
        PROFILER="jfr"
    else
        die "No profiler found. Install async-profiler or use JDK 11+ (jcmd)."
    fi
    echo "Using: ${PROFILER}" >&2
}

# ── async-profiler commands ──

asprof_start() {
    local output_file="${OUTPUT_DIR}/profile-${PID}-${EVENT}.jfr"
    echo "Starting async-profiler: event=${EVENT}, duration=${DURATION}s"
    ${ASPROF} start -e "${EVENT}" -d "${DURATION}" -f "${output_file}" "${PID}"
    echo ""
    echo "Profiling for ${DURATION}s..."
    echo "Output will be: ${output_file}"
}

asprof_stop() {
    ${ASPROF} stop "${PID}"
    echo "Profiling stopped."
}

asprof_status() {
    ${ASPROF} status "${PID}"
}

asprof_flamegraph() {
    local jfr_file="${OUTPUT_DIR}/profile-${PID}-${EVENT}.jfr"
    local svg_file="${OUTPUT_DIR}/flame-${PID}-${EVENT}.svg"

    if [[ ! -f "${jfr_file}" ]]; then
        # Try to generate inline
        echo "No existing profile. Recording ${DURATION}s..."
        ${ASPROF} -e "${EVENT}" -d "${DURATION}" -f "${svg_file}" "${PID}"
    else
        ${ASPROF} -f "${svg_file}" "${jfr_file}" 2>/dev/null || \
            ${ASPROF} -e "${EVENT}" -d "${DURATION}" -f "${svg_file}" "${PID}"
    fi

    echo "Flame graph: ${svg_file}"
}

asprof_top() {
    local output_file="${OUTPUT_DIR}/profile-${PID}-${EVENT}.txt"
    ${ASPROF} -e "${EVENT}" -d "${DURATION}" --flat "${LIMIT}" -f "${output_file}" "${PID}"
    echo ""
    echo "Top ${LIMIT} hot methods (${EVENT}, ${DURATION}s):"
    echo "───────────────────────────────────────"
    cat "${output_file}"
}

# ── JFR commands ──

JCMD=""
resolve_jcmd() {
    JCMD=$(resolve_jdk_tool jcmd)
}

jfr_event_settings() {
    case "${EVENT}" in
        cpu)   echo "jdk.CPULoad#enabled=true,jdk.ExecutionSample#enabled=true,jdk.ExecutionSample#period=10ms" ;;
        alloc) echo "jdk.ObjectAllocationInNewTLAB#enabled=true,jdk.ObjectAllocationOutsideTLAB#enabled=true" ;;
        lock)  echo "jdk.JavaMonitorEnter#enabled=true,jdk.JavaMonitorEnter#threshold=1ms" ;;
        wall)  echo "jdk.ThreadSleep#enabled=true,jdk.ThreadPark#enabled=true,jdk.ExecutionSample#enabled=true" ;;
        *)     echo "jdk.ExecutionSample#enabled=true" ;;
    esac
}

jfr_start() {
    resolve_jcmd
    local output_file="${OUTPUT_DIR}/profile-${PID}-${EVENT}.jfr"
    local settings
    settings=$(jfr_event_settings)

    echo "Starting JFR: event=${EVENT}, duration=${DURATION}s"
    ${JCMD} "${PID}" JFR.start name=profile duration="${DURATION}s" \
        filename="${output_file}" settings=profile \
        ${settings} 2>&1

    echo ""
    echo "Profiling for ${DURATION}s..."
    echo "Output: ${output_file}"
}

jfr_stop() {
    resolve_jcmd
    ${JCMD} "${PID}" JFR.stop name=profile 2>&1
    echo "JFR stopped."
}

jfr_status() {
    resolve_jcmd
    ${JCMD} "${PID}" JFR.check 2>&1
}

jfr_flamegraph() {
    resolve_jcmd
    local jfr_file="${OUTPUT_DIR}/profile-${PID}-${EVENT}.jfr"

    if [[ ! -f "${jfr_file}" ]]; then
        echo "No existing profile. Recording ${DURATION}s..."
        ${JCMD} "${PID}" JFR.start name=flame duration="${DURATION}s" \
            filename="${jfr_file}" settings=profile 2>&1
        sleep "$((DURATION + 2))"
    fi

    # Convert JFR to flame graph
    if command -v jfr &>/dev/null; then
        local collapsed="${OUTPUT_DIR}/collapsed-${PID}.txt"
        local svg_file="${OUTPUT_DIR}/flame-${PID}-${EVENT}.svg"
        jfr print --events jdk.ExecutionSample --stack-depth 64 "${jfr_file}" | \
            awk '/stackTrace:/{found=1; stack=""} found && /\tat /{gsub(/\tat /,""); stack=stack";"$0} /^$/ && found{print stack" 1"; found=0}' \
            > "${collapsed}" 2>/dev/null || true

        if command -v flamegraph.pl &>/dev/null; then
            flamegraph.pl "${collapsed}" > "${svg_file}"
            echo "Flame graph: ${svg_file}"
        else
            echo "JFR file: ${jfr_file}"
            echo "  (Install flamegraph.pl from github.com/brendangregg/FlameGraph for SVG)"
            echo "  Or open in JDK Mission Control: jmc ${jfr_file}"
        fi
    else
        echo "JFR file: ${jfr_file}"
        echo "  Open with: jmc ${jfr_file}"
    fi
}

jfr_top() {
    resolve_jcmd
    local jfr_file="${OUTPUT_DIR}/profile-${PID}-${EVENT}.jfr"

    if [[ ! -f "${jfr_file}" ]]; then
        echo "No existing profile. Recording ${DURATION}s..."
        ${JCMD} "${PID}" JFR.start name=top duration="${DURATION}s" \
            filename="${jfr_file}" settings=profile 2>&1
        sleep "$((DURATION + 2))"
    fi

    echo "Top ${LIMIT} hot methods (${EVENT}, from JFR):"
    echo "───────────────────────────────────────"

    if command -v jfr &>/dev/null; then
        jfr print --events jdk.ExecutionSample --stack-depth 1 "${jfr_file}" 2>/dev/null | \
            grep "at " | sort | uniq -c | sort -rn | head -"${LIMIT}" | \
            awk '{printf "  %6d  %s\n", $1, $2}'
    else
        echo "  (jfr CLI not available — open ${jfr_file} in JDK Mission Control)"
    fi
}

# ── Diff ──

cmd_diff() {
    [[ -n "${DIFF_FILE1}" && -n "${DIFF_FILE2}" ]] || die "Usage: profiler.sh diff <file1.jfr> <file2.jfr>"
    [[ -f "${DIFF_FILE1}" ]] || die "File not found: ${DIFF_FILE1}"
    [[ -f "${DIFF_FILE2}" ]] || die "File not found: ${DIFF_FILE2}"

    echo "Profile diff:"
    echo "  Before: ${DIFF_FILE1}"
    echo "  After:  ${DIFF_FILE2}"
    echo "───────────────────────────────────────"

    if command -v jfr &>/dev/null; then
        # Extract top methods from each and diff
        local tmp1="/tmp/prof-diff-1.txt"
        local tmp2="/tmp/prof-diff-2.txt"
        jfr print --events jdk.ExecutionSample --stack-depth 1 "${DIFF_FILE1}" 2>/dev/null | \
            grep "at " | sort | uniq -c | sort -rn | head -20 > "${tmp1}"
        jfr print --events jdk.ExecutionSample --stack-depth 1 "${DIFF_FILE2}" 2>/dev/null | \
            grep "at " | sort | uniq -c | sort -rn | head -20 > "${tmp2}"

        echo "Before (top methods):"
        cat "${tmp1}" | sed 's/^/  /'
        echo ""
        echo "After (top methods):"
        cat "${tmp2}" | sed 's/^/  /'
    else
        echo "  (jfr CLI not available — compare in JDK Mission Control)"
    fi
}

# ── Dispatch ──

detect_profiler

case "${COMMAND}" in
    start)
        check_pid "${PID}" "profiler.sh start <pid>"
        if [[ "${PROFILER}" == "async" ]]; then asprof_start; else jfr_start; fi
        ;;
    stop)
        [[ -n "${PID}" ]] || die "Usage: profiler.sh stop <pid>"
        if [[ "${PROFILER}" == "async" ]]; then asprof_stop; else jfr_stop; fi
        ;;
    status)
        [[ -n "${PID}" ]] || die "Usage: profiler.sh status <pid>"
        if [[ "${PROFILER}" == "async" ]]; then asprof_status; else jfr_status; fi
        ;;
    flamegraph|flame)
        check_pid "${PID}" "profiler.sh flamegraph <pid>"
        if [[ "${PROFILER}" == "async" ]]; then asprof_flamegraph; else jfr_flamegraph; fi
        ;;
    top)
        check_pid "${PID}" "profiler.sh top <pid>"
        if [[ "${PROFILER}" == "async" ]]; then asprof_top; else jfr_top; fi
        ;;
    diff)
        cmd_diff
        ;;
    *)
        echo "profiler.sh — Java profiler (async-profiler / JFR)"
        echo ""
        echo "Commands:"
        echo "  start <pid> [--event cpu|alloc|lock|wall] [--duration 30]"
        echo "  stop <pid>"
        echo "  status <pid>"
        echo "  flamegraph <pid>    Generate flame graph SVG"
        echo "  top <pid>           Show top hot methods"
        echo "  diff <f1> <f2>      Compare two profiles"
        ;;
esac
