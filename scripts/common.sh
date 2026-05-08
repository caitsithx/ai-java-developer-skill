#!/usr/bin/env bash
# common.sh — Shared utilities for ai-java-developer-skill plugin
#
# Source this file from any script:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
#   source "${PLUGIN_ROOT}/scripts/common.sh"

# ── Output ──

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "  $*"; }

# ── JDK Tool Resolution ──

resolve_jdk_tool() {
    local tool="$1"
    local optional="${2:-}"
    if command -v "${tool}" &>/dev/null; then
        echo "${tool}"
    elif [[ -n "${JAVA_HOME:-}" ]] && [[ -x "${JAVA_HOME}/bin/${tool}" ]]; then
        echo "${JAVA_HOME}/bin/${tool}"
    elif [[ "${optional}" == "--optional" ]]; then
        return 1
    else
        die "${tool} not found. Ensure a JDK is installed and ${tool} is on PATH or JAVA_HOME is set."
    fi
}

# ── Maven Wrapper Resolution ──

resolve_mvnw() {
    if [[ -x "./mvnw" ]]; then
        echo "./mvnw"
    elif command -v mvn &>/dev/null; then
        echo "mvn"
    else
        die "No Maven wrapper (./mvnw) or system mvn found."
    fi
}

# ── Process Validation ──

check_pid() {
    local pid="$1"
    local usage="${2:-}"
    [[ -n "${pid}" ]] || die "PID required.${usage:+ Usage: ${usage}}"
    kill -0 "${pid}" 2>/dev/null || die "Process ${pid} not found"
}

check_java_process() {
    local pid="$1"
    local proc_cmd
    proc_cmd=$(ps -o comm= -p "${pid}" 2>/dev/null || true)
    if [[ "${proc_cmd}" != *"java"* ]]; then
        echo "⚠️  PID ${pid} is '${proc_cmd}', may not be a Java process" >&2
    fi
}

# ── Formatting ──

bytes_to_human() {
    local bytes=$1
    if [[ ${bytes} -ge 1073741824 ]]; then
        awk "BEGIN {printf \"%.1f GB\", ${bytes}/1073741824}"
    elif [[ ${bytes} -ge 1048576 ]]; then
        awk "BEGIN {printf \"%.0f MB\", ${bytes}/1048576}"
    else
        awk "BEGIN {printf \"%.0f KB\", ${bytes}/1024}"
    fi
}
