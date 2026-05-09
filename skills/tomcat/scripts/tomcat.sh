#!/usr/bin/env bash
# tomcat.sh — Generic Tomcat dev server manager
#
# Usage:
#   tomcat.sh start              Start Tomcat with JDWP debug
#   tomcat.sh stop               Graceful shutdown
#   tomcat.sh restart            Stop + start
#   tomcat.sh status             Check running state + health
#   tomcat.sh log [-f name] [N]  Tail log (default: primary, 100 lines)
#   tomcat.sh grep [-f name] <kw> [N]  Search log (default: 20 matches)
#   tomcat.sh build-start        Build + start
#   tomcat.sh deploy             Copy WAR to webapps
#   tomcat.sh kill-all           Force-kill stale Tomcat processes
#   tomcat.sh prereqs            Check prerequisites
#   tomcat.sh diagnose           Parse startup failure
#
# Config: reads .tomcat-dev.conf from project root (or working directory)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
source "${PLUGIN_ROOT}/scripts/common.sh"

# ── Defaults ──

HTTP_PORT=8080
SHUTDOWN_PORT=8005
DEBUG_PORT=8089
CATALINA_BASE=""
CONTEXT_PATH="/"
WAR_MODULE="."
HEALTH_PATH="/"
BUILD_CMD="./mvnw package -DskipTests"
JDK_VERSION=""
LOG_FILES="catalina:logs/catalina.out"
DOCKER_DEPS=""
STARTUP_TIMEOUT=120
KILL_TIMEOUT=10

# ── Load project config ──

CONFIG_FILE=".tomcat-dev.conf"
if [[ -f "${CONFIG_FILE}" ]]; then
    source "${CONFIG_FILE}"
    info "Loaded config: ${CONFIG_FILE}"
fi

# ── Derived paths ──

[[ -n "${CATALINA_HOME:-}" ]] || die "CATALINA_HOME not set. Export it or define in .tomcat-dev.conf"
[[ -x "${CATALINA_HOME}/bin/catalina.sh" ]] || die "CATALINA_HOME '${CATALINA_HOME}' missing bin/catalina.sh"

if [[ -z "${CATALINA_BASE}" ]]; then
    CATALINA_BASE="${CATALINA_HOME}"
fi

PID_FILE="${CATALINA_BASE}/tomcat.pid"
CATALINA_LOG="${CATALINA_BASE}/logs/catalina.out"

# ── Helpers ──

get_pid() {
    if [[ -f "${PID_FILE}" ]]; then
        local pid
        pid=$(cat "${PID_FILE}")
        if kill -0 "${pid}" 2>/dev/null; then
            echo "${pid}"
            return 0
        fi
    fi
    # Fallback: find by port
    lsof -ti :${HTTP_PORT} -sTCP:LISTEN 2>/dev/null | head -1 || true
}

is_running() {
    local pid
    pid=$(get_pid)
    [[ -n "${pid}" ]]
}

resolve_log_file() {
    local name="${1:-catalina}"
    local entry
    for entry in ${LOG_FILES}; do
        local key="${entry%%:*}"
        local path="${entry#*:}"
        if [[ "${key}" == "${name}" ]]; then
            echo "${CATALINA_BASE}/${path}"
            return 0
        fi
    done
    # Default: first log in list
    local first="${LOG_FILES%% *}"
    echo "${CATALINA_BASE}/${first#*:}"
}

health_check() {
    local url="http://localhost:${HTTP_PORT}${HEALTH_PATH}"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" "${url}" 2>/dev/null || echo "000")
    echo "${code}"
}

# ── Docker dependency management ──

check_docker_deps() {
    [[ -n "${DOCKER_DEPS}" ]] || return 0

    local missing=()
    for dep in ${DOCKER_DEPS}; do
        local image="${dep%%:*}"
        local port="${dep#*:}"
        if ! lsof -ti :${port} -sTCP:LISTEN &>/dev/null; then
            missing+=("${dep}")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        info "All Docker dependencies running"
        return 0
    fi

    echo "Missing Docker dependencies:"
    for dep in "${missing[@]}"; do
        local image="${dep%%:*}"
        local port="${dep#*:}"
        echo "  ✗ ${image} (port ${port} not listening)"
    done
    echo ""
    return 1
}

start_docker_deps() {
    [[ -n "${DOCKER_DEPS}" ]] || return 0

    for dep in ${DOCKER_DEPS}; do
        local image="${dep%%:*}"
        local port="${dep#*:}"
        if ! lsof -ti :${port} -sTCP:LISTEN &>/dev/null; then
            echo "Starting ${image} on port ${port}..."
            case "${image}" in
                mysql)
                    docker run -d --name "${image}-dev" -p "${port}:3306" \
                        -e MYSQL_ROOT_PASSWORD=root \
                        "${image}:8" 2>/dev/null || \
                    docker start "${image}-dev" 2>/dev/null || true
                    ;;
                redis)
                    docker run -d --name "${image}-dev" -p "${port}:6379" \
                        "${image}:7-alpine" 2>/dev/null || \
                    docker start "${image}-dev" 2>/dev/null || true
                    ;;
                *)
                    docker run -d --name "${image}-dev" -p "${port}:${port}" \
                        "${image}" 2>/dev/null || \
                    docker start "${image}-dev" 2>/dev/null || true
                    ;;
            esac
            info "${image} started on port ${port}"
        fi
    done
}

# ── Commands ──

cmd_start() {
    if is_running; then
        local pid
        pid=$(get_pid)
        echo "Tomcat already running (PID ${pid})"
        return 0
    fi

    # Start Docker deps
    if [[ -n "${DOCKER_DEPS}" ]]; then
        if ! check_docker_deps 2>/dev/null; then
            start_docker_deps
            sleep 3
        fi
    fi

    # Bootstrap CATALINA_BASE dirs
    mkdir -p "${CATALINA_BASE}"/{conf,logs,work,temp,webapps}
    if [[ ! -f "${CATALINA_BASE}/conf/server.xml" ]]; then
        cp -n "${CATALINA_HOME}/conf/"* "${CATALINA_BASE}/conf/" 2>/dev/null || true
    fi

    # Set up JDWP
    export CATALINA_OPTS="${CATALINA_OPTS:-} -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:${DEBUG_PORT}"
    export CATALINA_BASE="${CATALINA_BASE}"
    export CATALINA_PID="${PID_FILE}"

    # Clear old log
    : > "${CATALINA_LOG}" 2>/dev/null || true

    echo "Starting Tomcat..."
    echo "  HTTP:  http://localhost:${HTTP_PORT}${CONTEXT_PATH}"
    echo "  Debug: localhost:${DEBUG_PORT}"

    "${CATALINA_HOME}/bin/catalina.sh" start > /dev/null 2>&1

    # Poll for startup
    local elapsed=0
    while [[ ${elapsed} -lt ${STARTUP_TIMEOUT} ]]; do
        local code
        code=$(health_check)
        if [[ "${code}" =~ ^[23] ]]; then
            echo ""
            info "Tomcat started in ${elapsed}s (HTTP ${code})"
            info "  URL:   http://localhost:${HTTP_PORT}${CONTEXT_PATH}"
            info "  Debug: localhost:${DEBUG_PORT}"
            info "  PID:   $(get_pid)"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        printf "."
    done

    echo ""
    echo "⚠️  Tomcat did not respond within ${STARTUP_TIMEOUT}s"
    echo "  Run: tomcat.sh diagnose"
    return 1
}

cmd_stop() {
    if ! is_running; then
        echo "Tomcat not running."
        return 0
    fi

    local pid
    pid=$(get_pid)
    echo "Stopping Tomcat (PID ${pid})..."

    export CATALINA_BASE="${CATALINA_BASE}"
    export CATALINA_PID="${PID_FILE}"
    "${CATALINA_HOME}/bin/catalina.sh" stop ${KILL_TIMEOUT} > /dev/null 2>&1 || true

    # Wait
    local elapsed=0
    while kill -0 "${pid}" 2>/dev/null && [[ ${elapsed} -lt ${KILL_TIMEOUT} ]]; do
        sleep 1
        elapsed=$((elapsed + 1))
    done

    if kill -0 "${pid}" 2>/dev/null; then
        echo "Force-killing PID ${pid}..."
        kill -9 "${pid}" 2>/dev/null || true
    fi

    rm -f "${PID_FILE}"
    info "Tomcat stopped."
}

cmd_restart() {
    cmd_stop
    sleep 2
    cmd_start
}

cmd_status() {
    echo "═══ Tomcat Status ═══"
    echo ""

    if is_running; then
        local pid
        pid=$(get_pid)
        info "Process: running (PID ${pid})"
    else
        echo "  ✗ Process: not running"
    fi

    # Debug port
    if lsof -ti :${DEBUG_PORT} -sTCP:LISTEN &>/dev/null; then
        info "Debug port: ${DEBUG_PORT} listening"
    else
        echo "  ✗ Debug port: ${DEBUG_PORT} not listening"
    fi

    # Health check
    local code
    code=$(health_check)
    if [[ "${code}" =~ ^[23] ]]; then
        info "Health: HTTP ${code} (http://localhost:${HTTP_PORT}${HEALTH_PATH})"
    else
        echo "  ✗ Health: HTTP ${code} (http://localhost:${HTTP_PORT}${HEALTH_PATH})"
    fi

    # Docker deps
    if [[ -n "${DOCKER_DEPS}" ]]; then
        echo ""
        check_docker_deps || true
    fi
}

cmd_log() {
    local log_name=""
    local lines=100
    shift 2>/dev/null || true  # consume "log" command

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f) log_name="$2"; shift 2 ;;
            *)  lines="$1"; shift ;;
        esac
    done

    local log_file
    log_file=$(resolve_log_file "${log_name}")

    if [[ ! -f "${log_file}" ]]; then
        die "Log file not found: ${log_file}"
    fi

    echo "═══ Last ${lines} lines: $(basename "${log_file}") ═══"
    tail -n "${lines}" "${log_file}"
}

cmd_grep() {
    local log_name=""
    local keyword=""
    local max_matches=20
    shift 2>/dev/null || true  # consume "grep" command

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f) log_name="$2"; shift 2 ;;
            *)
                if [[ -z "${keyword}" ]]; then
                    keyword="$1"
                else
                    max_matches="$1"
                fi
                shift
                ;;
        esac
    done

    [[ -n "${keyword}" ]] || die "Usage: tomcat.sh grep [-f name] <keyword> [max_matches]"

    local log_file
    log_file=$(resolve_log_file "${log_name}")

    if [[ ! -f "${log_file}" ]]; then
        die "Log file not found: ${log_file}"
    fi

    echo "═══ Searching '${keyword}' in $(basename "${log_file}") (max ${max_matches}) ═══"
    grep -n -A 5 "${keyword}" "${log_file}" | head -$((max_matches * 7)) || echo "No matches found."
}

cmd_build_start() {
    echo "Building with: ${BUILD_CMD}"
    eval "${BUILD_CMD}" || die "Build failed"
    echo ""
    cmd_start
}

cmd_deploy() {
    local war_dir
    war_dir=$(find "${WAR_MODULE}/target" -maxdepth 1 -name "*.war" 2>/dev/null | head -1)

    if [[ -z "${war_dir}" ]]; then
        # Try exploded WAR
        war_dir=$(find "${WAR_MODULE}/target" -maxdepth 1 -type d -name "*SNAPSHOT*" 2>/dev/null | head -1)
    fi

    [[ -n "${war_dir}" ]] || die "No WAR found in ${WAR_MODULE}/target/"

    echo "Deploying: ${war_dir}"
    # Link or copy to webapps
    mkdir -p "${CATALINA_BASE}/webapps"
    ln -sf "$(cd "$(dirname "${war_dir}")" && pwd)/$(basename "${war_dir}")" \
        "${CATALINA_BASE}/webapps/" 2>/dev/null || \
        cp -r "${war_dir}" "${CATALINA_BASE}/webapps/"

    info "Deployed to ${CATALINA_BASE}/webapps/"
}

cmd_kill_all() {
    echo "Killing all Tomcat processes..."
    local pids
    pids=$(ps aux | grep "[c]atalina" | awk '{print $2}' || true)

    if [[ -z "${pids}" ]]; then
        echo "No Tomcat processes found."
        return 0
    fi

    echo "${pids}" | while read -r pid; do
        echo "  Killing PID ${pid}"
        kill -9 "${pid}" 2>/dev/null || true
    done

    rm -f "${PID_FILE}"
    info "All Tomcat processes killed."
}

cmd_prereqs() {
    echo "═══ Prerequisites Check ═══"
    echo ""

    # CATALINA_HOME
    if [[ -x "${CATALINA_HOME}/bin/catalina.sh" ]]; then
        info "CATALINA_HOME: ${CATALINA_HOME}"
    else
        echo "  ✗ CATALINA_HOME: not set or invalid"
    fi

    # JDK
    local java_ver
    java_ver=$(java -version 2>&1 | head -1 | grep -oE '[0-9]+' | head -1)
    if [[ -n "${JDK_VERSION}" && "${java_ver}" != "${JDK_VERSION}" ]]; then
        echo "  ⚠️  JDK: active=${java_ver}, required=${JDK_VERSION}"
    else
        info "JDK: ${java_ver}"
    fi

    # WAR
    local war
    war=$(find "${WAR_MODULE}/target" -maxdepth 1 \( -name "*.war" -o -type d -name "*SNAPSHOT*" \) 2>/dev/null | head -1)
    if [[ -n "${war}" ]]; then
        info "WAR: ${war}"
    else
        echo "  ✗ WAR: not found in ${WAR_MODULE}/target/ (run build first)"
    fi

    # Docker deps
    if [[ -n "${DOCKER_DEPS}" ]]; then
        echo ""
        check_docker_deps || true
    fi
}

cmd_diagnose() {
    echo "═══ Startup Diagnosis ═══"
    echo ""

    if [[ ! -f "${CATALINA_LOG}" ]]; then
        die "No catalina.out found at ${CATALINA_LOG}"
    fi

    # Check for SEVERE
    local severes
    severes=$(grep -c "SEVERE\|FATAL\|Error" "${CATALINA_LOG}" 2>/dev/null || echo "0")
    echo "Errors in catalina.out: ${severes}"
    echo ""

    if [[ ${severes} -gt 0 ]]; then
        echo "Root cause (last SEVERE/Exception):"
        echo "───────────────────────────────────────"
        grep -B 2 -A 10 "SEVERE\|Exception\|FATAL" "${CATALINA_LOG}" | tail -30
    fi

    echo ""
    echo "Possible issues:"

    # Port conflict
    if grep -q "Address already in use" "${CATALINA_LOG}" 2>/dev/null; then
        echo "  → Port conflict: run 'tomcat.sh kill-all' then retry"
    fi

    # Missing deps
    if grep -q "ConnectionException\|Unable to connect" "${CATALINA_LOG}" 2>/dev/null; then
        echo "  → Missing dependency (DB/Redis): run 'tomcat.sh prereqs'"
    fi

    # OOM
    if grep -q "OutOfMemoryError" "${CATALINA_LOG}" 2>/dev/null; then
        echo "  → Out of memory: increase -Xmx in CATALINA_OPTS"
    fi

    # ClassNotFound
    if grep -q "ClassNotFoundException\|NoClassDefFoundError" "${CATALINA_LOG}" 2>/dev/null; then
        echo "  → Missing class: rebuild WAR with 'tomcat.sh build-start'"
    fi
}

# ── Dispatch ──

COMMAND="${1:-help}"

case "${COMMAND}" in
    start)       cmd_start ;;
    stop)        cmd_stop ;;
    restart)     cmd_restart ;;
    status)      cmd_status ;;
    log)         shift; cmd_log "$@" ;;
    grep)        shift; cmd_grep "$@" ;;
    build-start) cmd_build_start ;;
    deploy)      cmd_deploy ;;
    kill-all)    cmd_kill_all ;;
    prereqs)     cmd_prereqs ;;
    diagnose)    cmd_diagnose ;;
    help|*)
        echo "tomcat.sh — Local Tomcat dev server manager"
        echo ""
        echo "Lifecycle:    start | stop | restart | status | kill-all"
        echo "Logs:         log [-f name] [N] | grep [-f name] <keyword> [N]"
        echo "Build:        build-start | deploy"
        echo "Diagnostics:  prereqs | diagnose"
        echo ""
        echo "Config: .tomcat-dev.conf in project root"
        ;;
esac
