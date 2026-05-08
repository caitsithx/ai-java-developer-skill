#!/usr/bin/env bash
# heap-dump.sh — Java heap dump and histogram analysis
#
# Usage:
#   heap-dump.sh histogram <pid> [--limit N]
#   heap-dump.sh histogram-live <pid> [--limit N]
#   heap-dump.sh dump <pid> [--output /path/file.hprof]
#   heap-dump.sh diff <pid> [--interval 30] [--limit N]
#   heap-dump.sh native <pid>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
source "${PLUGIN_ROOT}/scripts/common.sh"

COMMAND=""
PID=""
LIMIT=20
INTERVAL=30
OUTPUT=""
DUMP_DIR="/tmp/heap-dump"

# ── Parse args ──

while [[ $# -gt 0 ]]; do
    case "$1" in
        --limit)    LIMIT="$2"; shift 2 ;;
        --interval) INTERVAL="$2"; shift 2 ;;
        --output)   OUTPUT="$2"; shift 2 ;;
        -*)         die "Unknown flag: $1" ;;
        *)
            if [[ -z "${COMMAND}" ]]; then
                COMMAND="$1"
            elif [[ -z "${PID}" ]]; then
                PID="$1"
            fi
            shift
            ;;
    esac
done

[[ -n "${COMMAND}" ]] || die "Usage: heap-dump.sh <histogram|histogram-live|dump|diff|native> <pid> [options]"

mkdir -p "${DUMP_DIR}"

# ── Commands ──

cmd_histogram() {
    check_pid "${PID}" "heap-dump.sh histogram <pid>"
    local jcmd
    jcmd=$(resolve_jdk_tool jcmd)

    echo "═══ Class Histogram (PID: ${PID}, top ${LIMIT}) ═══"
    echo ""
    ${jcmd} "${PID}" GC.class_histogram 2>&1 | head -$((LIMIT + 3))
    echo ""

    local total_instances total_bytes
    total_instances=$(${jcmd} "${PID}" GC.class_histogram 2>&1 | tail -1)
    echo "Total: ${total_instances}"
}

cmd_histogram_live() {
    check_pid "${PID}" "heap-dump.sh histogram-live <pid>"
    local jcmd
    jcmd=$(resolve_jdk_tool jcmd)

    echo "═══ Class Histogram - Live (PID: ${PID}, GC triggered, top ${LIMIT}) ═══"
    echo ""
    ${jcmd} "${PID}" GC.class_histogram -all=false 2>&1 | head -$((LIMIT + 3))
}

cmd_dump() {
    check_pid "${PID}" "heap-dump.sh dump <pid>"
    local jcmd
    jcmd=$(resolve_jdk_tool jcmd)

    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local dump_file="${OUTPUT:-${DUMP_DIR}/heap-${PID}-${timestamp}.hprof}"

    echo "Taking heap dump of PID ${PID}..."
    echo "  Output: ${dump_file}"
    echo "  (JVM will pause briefly)"
    echo ""

    ${jcmd} "${PID}" GC.heap_dump "${dump_file}" 2>&1

    if [[ -f "${dump_file}" ]]; then
        local size
        size=$(du -h "${dump_file}" | cut -f1)
        echo ""
        echo "✅ Heap dump saved: ${dump_file} (${size})"
        echo ""
        echo "Next steps:"
        echo "  - Open in Eclipse MAT: mat ${dump_file}"
        echo "  - Open in VisualVM: visualvm --openfile ${dump_file}"
    else
        die "Heap dump failed — file not created"
    fi
}

cmd_diff() {
    check_pid "${PID}" "heap-dump.sh diff <pid>"
    local jcmd
    jcmd=$(resolve_jdk_tool jcmd)

    local snap1="${DUMP_DIR}/histo-${PID}-before.txt"
    local snap2="${DUMP_DIR}/histo-${PID}-after.txt"

    echo "═══ Histogram Diff (PID: ${PID}, ${INTERVAL}s interval) ═══"
    echo ""
    echo "Taking snapshot 1..."
    ${jcmd} "${PID}" GC.class_histogram 2>&1 | grep -v "^$" > "${snap1}"

    echo "Waiting ${INTERVAL}s..."
    sleep "${INTERVAL}"

    echo "Taking snapshot 2..."
    ${jcmd} "${PID}" GC.class_histogram 2>&1 | grep -v "^$" > "${snap2}"

    echo ""
    echo "Growing classes (sorted by byte increase):"
    echo "───────────────────────────────────────"

    # Parse and diff: extract class, instances, bytes from both snapshots
    # Format: num: instances bytes class_name
    awk '
        NR==FNR && /^ *[0-9]+:/ {
            gsub(/^ *[0-9]+: */, "")
            split($0, a, /[[:space:]]+/)
            instances_before[a[3]] = a[1]
            bytes_before[a[3]] = a[2]
            next
        }
        FNR!=NR && /^ *[0-9]+:/ {
            gsub(/^ *[0-9]+: */, "")
            split($0, a, /[[:space:]]+/)
            class = a[3]
            inst_diff = a[1] - (instances_before[class]+0)
            byte_diff = a[2] - (bytes_before[class]+0)
            if (byte_diff > 0) {
                printf "%12d instances  %12d bytes  %s\n", inst_diff, byte_diff, class
            }
        }
    ' "${snap1}" "${snap2}" | sort -t'b' -k2 -rn | head -"${LIMIT}"

    echo ""
    echo "Shrinking classes:"
    echo "───────────────────────────────────────"

    awk '
        NR==FNR && /^ *[0-9]+:/ {
            gsub(/^ *[0-9]+: */, "")
            split($0, a, /[[:space:]]+/)
            instances_before[a[3]] = a[1]
            bytes_before[a[3]] = a[2]
            next
        }
        FNR!=NR && /^ *[0-9]+:/ {
            gsub(/^ *[0-9]+: */, "")
            split($0, a, /[[:space:]]+/)
            class = a[3]
            inst_diff = a[1] - (instances_before[class]+0)
            byte_diff = a[2] - (bytes_before[class]+0)
            if (byte_diff < -1000) {
                printf "%12d instances  %12d bytes  %s\n", inst_diff, byte_diff, class
            }
        }
    ' "${snap1}" "${snap2}" | sort -t'b' -k2 -n | head -10
}

cmd_native() {
    check_pid "${PID}" "heap-dump.sh native <pid>"
    local jcmd
    jcmd=$(resolve_jdk_tool jcmd)

    echo "═══ Native Memory (PID: ${PID}) ═══"
    echo ""

    local output
    output=$(${jcmd} "${PID}" VM.native_memory summary 2>&1)

    if echo "${output}" | grep -q "not enabled"; then
        echo "❌ Native Memory Tracking not enabled."
        echo ""
        echo "Start JVM with: -XX:NativeMemoryTracking=summary"
        echo "Then retry this command."
    else
        echo "${output}"
    fi
}

# ── Dispatch ──

case "${COMMAND}" in
    histogram)      cmd_histogram ;;
    histogram-live) cmd_histogram_live ;;
    dump)           cmd_dump ;;
    diff)           cmd_diff ;;
    native)         cmd_native ;;
    help|*)
        echo "heap-dump.sh — Java heap dump and histogram analysis"
        echo ""
        echo "Commands:"
        echo "  histogram <pid> [--limit N]          Class histogram (no GC)"
        echo "  histogram-live <pid> [--limit N]     Class histogram (GC first)"
        echo "  dump <pid> [--output path.hprof]     Full heap dump"
        echo "  diff <pid> [--interval 30] [--limit N]  Diff two histograms"
        echo "  native <pid>                         Native memory (needs NMT)"
        ;;
esac
