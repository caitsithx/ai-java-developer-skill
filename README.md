# ai-java-developer-skill

Claude Code plugin for Java development: debugging, profiling, testing, building, and dependency management.

## Skills

| Skill | Invocation | Description |
|---|---|---|
| jdb-debug | `/ai-java-developer-skill:jdb-debug` | Interactive Java debugger via named pipes |
| format | `/ai-java-developer-skill:format` | Spotless code formatting |
| build | `/ai-java-developer-skill:build` | Maven build management |
| test | `/ai-java-developer-skill:test` | Run tests, debug tests, coverage analysis |
| dependency | `/ai-java-developer-skill:dependency` | Dependency analysis (unused, undeclared, cycles, conflicts) |
| thread-dump | `/ai-java-developer-skill:thread-dump` | Live thread analysis, deadlock/CPU hog detection |
| profiler | `/ai-java-developer-skill:profiler` | CPU/memory/lock profiling with flame graphs |
| maven-central | `/ai-java-developer-skill:maven-central` | Search artifacts, get versions, POM snippets |
| jmx | `/ai-java-developer-skill:jmx` | JVM runtime metrics (heap, GC, threads, MBeans) |

## Hooks

| Hook | Event | Description |
|---|---|---|
| check-java-version | PostToolUse (Write/Edit) | Warn on JDK version mismatch |
| auto-format-java | PostToolUse (Write/Edit) | Auto-format .java files via Spotless |

## Install

```bash
# Add marketplace
claude plugin marketplace add caitsithx/ai-java-developer-skill

# Install plugin
claude plugin install ai-java-developer-skill@ai-java-developer

# Or load directly during development
claude --plugin-dir /path/to/ai-java-developer-skill
```

## Development

```bash
# Test locally
claude --plugin-dir .

# Reload after changes (inside session)
/reload-plugins

# Validate
claude plugin validate .
```

## Architecture

```
scripts/common.sh          # Shared utilities (die, resolve_jdk_tool, check_pid, etc.)
skills/*/scripts/*.sh      # Skill-specific scripts (source common.sh)
hooks/hooks.json           # Hook definitions
scripts/auto-format-java.sh  # Lightweight hook (no common.sh for speed)
scripts/check-java-version.sh
```
