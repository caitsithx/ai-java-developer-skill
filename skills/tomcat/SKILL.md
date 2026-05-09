---
name: tomcat
description: >
  Manage local Tomcat dev server: start/stop with JDWP debug, tail/grep logs,
  health checks, build-and-deploy, prerequisite checks, Docker dependency management.
  Reads project-specific config from .tomcat-dev.conf if present.
  Use this skill whenever the user wants to start/stop a local Tomcat, check server
  status, view or search app logs, deploy a WAR, or troubleshoot startup failures.
  Trigger phrases: "start tomcat", "stop tomcat", "restart server", "tomcat status",
  "show logs", "grep logs", "build and deploy", "deploy war", "is server running",
  "tomcat log", "startup failed", "debug port", "kill tomcat", "check prereqs",
  "why did tomcat fail", "diagnose startup".
---

# Tomcat — Local Dev Server Management

Manages a local Tomcat instance for development: lifecycle, logging, builds, and diagnostics.
Reads `.tomcat-dev.conf` from project root for project-specific configuration.

## Commands

All commands run via:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/tomcat/scripts/tomcat.sh <command> [args]
```

### Lifecycle

| Command | Description |
|---|---|
| `start` | Start Tomcat with JDWP debug port, poll health endpoint |
| `stop` | Graceful shutdown, force-kill after timeout |
| `restart` | Stop + start |
| `status` | Process alive? Debug port? Health endpoint? |
| `kill-all` | Force-kill all stale Tomcat processes |

### Logs

| Command | Description |
|---|---|
| `log [-f name] [N]` | Tail last N lines of a log (default: primary log, 100 lines) |
| `grep [-f name] <keyword> [N]` | Search log for keyword with context (default: 20 matches) |

Log file names are defined in `.tomcat-dev.conf`. Without config, uses `catalina.out`.

### Build & Deploy

| Command | Description |
|---|---|
| `build-start` | Run build command from config, then start Tomcat |
| `deploy` | Link/copy WAR to Tomcat webapps without rebuild |

### Diagnostics

| Command | Description |
|---|---|
| `prereqs` | Check CATALINA_HOME, JDK, Docker deps, WAR exists |
| `diagnose` | Parse logs for root cause of startup failure |

## Configuration

Place `.tomcat-dev.conf` in project root. If absent, defaults apply.

```bash
# .tomcat-dev.conf — Project-specific Tomcat dev config

# Ports
HTTP_PORT=8080
SHUTDOWN_PORT=8005
DEBUG_PORT=8089

# Paths
CATALINA_BASE="build/tomcat-base"
CONTEXT_PATH="/"
WAR_MODULE="."
HEALTH_PATH="/"

# Build
BUILD_CMD="./mvnw package -DskipTests"

# JDK
JDK_VERSION=17

# Logs (name:relative-path pairs, space-separated)
LOG_FILES="catalina:logs/catalina.out"

# Docker dependencies (image:port pairs, space-separated)
DOCKER_DEPS=""
# Example: DOCKER_DEPS="mysql:3306 redis:6379"
```

## Execution Instructions

When the user invokes this skill:

1. **Determine the subcommand** from the user's request:
   - "start" / "run" / "deploy locally" → `start`
   - "stop" / "kill" / "shutdown" → `stop`
   - "restart" → `restart`
   - "status" / "is it running" / "health" → `status`
   - "logs" / "show log" / "what's happening" → `log`
   - "search logs" / "grep" / "find in log" → `grep <keyword>`
   - "build and start" / "rebuild" → `build-start`
   - "deploy" / "redeploy" → `deploy`
   - "kill all" / "force kill" → `kill-all`
   - "check prereqs" / "what's missing" → `prereqs`
   - "diagnose" / "why did it fail" → `diagnose`

2. **Run the script** from the project root:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/tomcat/scripts/tomcat.sh <command> [args]
   ```

3. **Interpret the output** and relay to the user.

4. **On failure**: run `diagnose` to parse root cause, suggest fix.

## Integration with Other Skills

- **jdb-debug**: After `start`, attach debugger to the debug port
- **jmx-connector**: Query Tomcat MBeans (sessions, connectors, pools)
- **java-thread-dump**: Take thread dump of Tomcat PID
- **java-profiler**: Profile Tomcat under load
