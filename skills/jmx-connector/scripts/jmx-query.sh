#!/usr/bin/env bash
# jmx-query.sh — Query JVM runtime metrics via jcmd/jstat
#
# Usage:
#   jmx-query.sh health <pid>             Full health overview
#   jmx-query.sh heap <pid>               Heap memory details
#   jmx-query.sh gc <pid>                 GC statistics
#   jmx-query.sh threads <pid>            Thread counts
#   jmx-query.sh cpu <pid>                CPU load
#   jmx-query.sh classes <pid>            Class loading stats
#   jmx-query.sh mbean <pid> <name> <attr>  Read custom MBean
#   jmx-query.sh list <pid> [pattern]     List available MBeans

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
source "${PLUGIN_ROOT}/scripts/common.sh"

COMMAND="${1:-help}"
PID="${2:-}"

# ── Resolve tools ──

JCMD=""
JSTAT=""

resolve_tools() {
    JCMD=$(resolve_jdk_tool jcmd)
    JSTAT=$(resolve_jdk_tool jstat --optional) || JSTAT=""
}

_check_pid() {
    check_pid "${PID}" "jmx-query.sh ${COMMAND} <pid>"
}

# ── Commands ──

cmd_heap() {
    _check_pid
    echo "Heap Memory (PID: ${PID}):"
    echo "───────────────────────────────────────"

    # Use jcmd GC.heap_info
    local heap_info
    heap_info=$(${JCMD} "${PID}" GC.heap_info 2>/dev/null || true)

    if [[ -n "${heap_info}" ]]; then
        echo "${heap_info}" | tail -n +2
    fi

    echo ""

    # Also get from jstat for numeric values
    if [[ -n "${JSTAT}" ]]; then
        echo "Capacity (jstat):"
        ${JSTAT} -gc "${PID}" 2>/dev/null | head -2 | \
            awk 'NR==2 {
                printf "  Young: S0=%.0fK S1=%.0fK Eden=%.0fK (used: S0=%.0fK S1=%.0fK Eden=%.0fK)\n", $1, $2, $5, $3, $4, $6
                printf "  Old:   Capacity=%.0fK Used=%.0fK\n", $7, $8
                printf "  Meta:  Capacity=%.0fK Used=%.0fK\n", $9, $10
            }' || true
    fi
}

cmd_gc() {
    _check_pid
    echo "GC Statistics (PID: ${PID}):"
    echo "───────────────────────────────────────"

    if [[ -n "${JSTAT}" ]]; then
        ${JSTAT} -gcutil "${PID}" 2>/dev/null | awk '
            NR==1 {print "  " $0}
            NR==2 {print "  " $0}
        ' || true

        echo ""
        ${JSTAT} -gc "${PID}" 2>/dev/null | awk '
            NR==2 {
                printf "  Young GC count: %.0f, time: %.3fs\n", $13, $14
                printf "  Full GC count:  %.0f, time: %.3fs\n", $15, $16
                printf "  Total GC time:  %.3fs\n", $17
            }
        ' || true
    fi

    echo ""
    echo "Last GC cause:"
    ${JCMD} "${PID}" GC.heap_info 2>/dev/null | grep -i "cause\|reason" | sed 's/^/  /' || \
        ${JSTAT} -gccause "${PID}" 2>/dev/null | awk 'NR==2 {printf "  Last: %s, Current: %s\n", $7, $8}' || \
        echo "  (unable to determine)"
}

cmd_threads() {
    _check_pid
    echo "Thread Info (PID: ${PID}):"
    echo "───────────────────────────────────────"

    local thread_info
    thread_info=$(${JCMD} "${PID}" Thread.print 2>/dev/null | grep -c "^\"" || echo "0")
    echo "  Live threads: ${thread_info}"

    # Get more detail from VM.info if available
    local vm_info
    vm_info=$(${JCMD} "${PID}" VM.info 2>/dev/null || true)
    if [[ -n "${vm_info}" ]]; then
        echo "${vm_info}" | grep -i "thread\|daemon" | grep -v "^$" | head -5 | sed 's/^/  /'
    fi
}

cmd_cpu() {
    _check_pid
    echo "CPU Load (PID: ${PID}):"
    echo "───────────────────────────────────────"

    # Get process CPU from ps
    local cpu_pct
    cpu_pct=$(ps -p "${PID}" -o %cpu= 2>/dev/null | tr -d ' ')
    echo "  Process CPU: ${cpu_pct:-unknown}%"

    # System load
    local load_avg
    load_avg=$(sysctl -n vm.loadavg 2>/dev/null || uptime | grep -oE 'load average[s]?: [0-9., ]+' || true)
    echo "  System load: ${load_avg}"

    # Processors
    local nproc
    nproc=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo "unknown")
    echo "  Available cores: ${nproc}"

    # Process uptime
    local etime
    etime=$(ps -p "${PID}" -o etime= 2>/dev/null | tr -d ' ')
    echo "  Process uptime: ${etime:-unknown}"
}

cmd_classes() {
    _check_pid
    echo "Class Loading (PID: ${PID}):"
    echo "───────────────────────────────────────"

    if [[ -n "${JSTAT}" ]]; then
        ${JSTAT} -class "${PID}" 2>/dev/null | awk '
            NR==1 {print "  " $0}
            NR==2 {
                printf "  Loaded: %.0f classes (%.0f bytes)\n", $1, $2
                printf "  Unloaded: %.0f classes (%.0f bytes)\n", $3, $4
                printf "  Time: %.3fs\n", $5
            }
        ' || true
    else
        ${JCMD} "${PID}" VM.classloader_stats 2>/dev/null | head -20 | sed 's/^/  /' || \
            echo "  (jstat not available)"
    fi
}

cmd_mbean() {
    _check_pid
    local mbean_name="${3:-}"
    local attribute="${4:-}"
    [[ -n "${mbean_name}" ]] || die "Usage: jmx-query.sh mbean <pid> <object-name> <attribute>"
    [[ -n "${attribute}" ]] || die "Usage: jmx-query.sh mbean <pid> <object-name> <attribute>"

    echo "MBean: ${mbean_name}"
    echo "Attribute: ${attribute}"
    echo "───────────────────────────────────────"

    # Use jcmd VM.system_properties or ManagementAgent approach
    # For custom MBeans, use jrunscript if available
    if command -v jrunscript &>/dev/null || [[ -x "${JAVA_HOME:-}/bin/jrunscript" ]]; then
        local jrunscript_bin
        jrunscript_bin=$(command -v jrunscript 2>/dev/null || echo "${JAVA_HOME}/bin/jrunscript")

        ${jrunscript_bin} -e "
            var JMXConnectorFactory = javax.management.remote.JMXConnectorFactory;
            var JMXServiceURL = javax.management.remote.JMXServiceURL;
            var ObjectName = javax.management.ObjectName;

            // Attach locally via PID
            var VirtualMachine = com.sun.tools.attach.VirtualMachine;
            var vm = VirtualMachine.attach('${PID}');
            var addr = vm.startLocalManagementAgent();
            var url = new JMXServiceURL(addr);
            var connector = JMXConnectorFactory.connect(url);
            var mbs = connector.getMBeanServerConnection();
            var name = new ObjectName('${mbean_name}');
            var value = mbs.getAttribute(name, '${attribute}');
            print('  ' + '${attribute}' + ' = ' + value);
            connector.close();
            vm.detach();
        " 2>&1 || echo "  (jrunscript MBean query failed — ensure JVM allows local attach)"
    else
        echo "  (jrunscript not available — cannot query custom MBeans directly)"
        echo "  Try: jcmd ${PID} VM.system_properties | grep <pattern>"
    fi
}

cmd_list() {
    _check_pid
    local pattern="${3:-*:*}"

    echo "MBeans matching '${pattern}' (PID: ${PID}):"
    echo "───────────────────────────────────────"

    if command -v jrunscript &>/dev/null || [[ -x "${JAVA_HOME:-}/bin/jrunscript" ]]; then
        local jrunscript_bin
        jrunscript_bin=$(command -v jrunscript 2>/dev/null || echo "${JAVA_HOME}/bin/jrunscript")

        ${jrunscript_bin} -e "
            var VirtualMachine = com.sun.tools.attach.VirtualMachine;
            var JMXConnectorFactory = javax.management.remote.JMXConnectorFactory;
            var JMXServiceURL = javax.management.remote.JMXServiceURL;
            var ObjectName = javax.management.ObjectName;

            var vm = VirtualMachine.attach('${PID}');
            var addr = vm.startLocalManagementAgent();
            var url = new JMXServiceURL(addr);
            var connector = JMXConnectorFactory.connect(url);
            var mbs = connector.getMBeanServerConnection();
            var names = mbs.queryNames(new ObjectName('${pattern}'), null);
            var it = names.iterator();
            var count = 0;
            while (it.hasNext() && count < 50) {
                print('  ' + it.next());
                count++;
            }
            if (names.size() > 50) print('  ... (' + names.size() + ' total)');
            connector.close();
            vm.detach();
        " 2>&1 || echo "  (failed to list MBeans)"
    else
        echo "  (jrunscript not available)"
        echo "  Available jcmd commands for this JVM:"
        ${JCMD} "${PID}" help 2>/dev/null | sed 's/^/    /' | head -30
    fi
}

cmd_health() {
    _check_pid
    echo "═══ JVM Health (PID: ${PID}) ═══"
    echo ""
    cmd_heap
    echo ""
    cmd_gc
    echo ""
    cmd_threads
    echo ""
    cmd_cpu
}

# ── Dispatch ──

resolve_tools

case "${COMMAND}" in
    health)   cmd_health ;;
    heap)     cmd_heap ;;
    gc)       cmd_gc ;;
    threads)  cmd_threads ;;
    cpu)      cmd_cpu ;;
    classes)  cmd_classes ;;
    mbean)    cmd_mbean "$@" ;;
    list)     cmd_list "$@" ;;
    help|*)
        echo "jmx-query.sh — JVM runtime metrics via jcmd/jstat"
        echo ""
        echo "Commands:"
        echo "  health <pid>                    Full health overview"
        echo "  heap <pid>                      Heap memory"
        echo "  gc <pid>                        GC statistics"
        echo "  threads <pid>                   Thread counts"
        echo "  cpu <pid>                       CPU load"
        echo "  classes <pid>                   Class loading"
        echo "  mbean <pid> <name> <attr>       Read custom MBean"
        echo "  list <pid> [pattern]            List MBeans"
        ;;
esac
