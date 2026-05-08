# ai-java-developer-skill

Claude Code plugin for Java development: debugging, profiling, testing, heap analysis, building, and dependency management.

## Prerequisites

- **JDK 8+** with `jcmd`, `jstack`, `jstat`, `jdb` on PATH (or `JAVA_HOME` set)
- **Maven** wrapper (`./mvnw`) in project root, or system `mvn`
- **curl** + **jq** (for maven-central skill)
- **async-profiler** (optional, for profiler skill — falls back to JFR)

## Install

```bash
# Add marketplace
claude plugin marketplace add caitsithx/ai-java-developer-skill

# Install plugin
claude plugin install ai-java-developer-skill@ai-java-developer

# Or load directly during development
claude --plugin-dir /path/to/ai-java-developer-skill
```

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
| heap-dump | `/ai-java-developer-skill:heap-dump` | Heap dumps, class histograms, leak detection |

## Skill Details

### jdb-debug
Attach to any running JVM with JDWP enabled. Set breakpoints, inspect variables, step through code.
```
"attach debugger to port 8089"
"set breakpoint on UserService.createUser"
"print orderId"
```

### java-test
Run specific tests, debug failing tests with JDWP, analyze coverage for changed files.
```
"run tests for UserService"
"check coverage for my changes"
"debug the failing test"
```

### java-heap-dump
Class histograms, full heap dumps, diff two snapshots to find memory leaks.
```
"what is consuming heap on PID 12345?"
"take a heap dump"
"find the memory leak — diff histograms 30s apart"
```

### java-thread-dump
Take thread dumps, correlate OS PIDs from `top` to JVM threads, find deadlocks.
```
"my app is hanging, PID 12345"
"thread 54321 is using 99% CPU, what is it doing?"
"check for deadlocks"
```

### java-profiler
CPU, memory allocation, lock contention profiling. Flame graphs via async-profiler or JFR.
```
"profile PID 12345 for 10 seconds"
"generate a flame graph"
"where is the bottleneck?"
```

### jmx-connector
Query live JVM metrics: heap, GC stats, threads, CPU, custom MBeans.
```
"how much heap is my app using?"
"show GC stats for PID 12345"
"check HikariCP connection pool"
```

### maven-central
Search artifacts, find latest versions, generate POM snippets.
```
"find latest version of jackson-databind"
"add guava to my pom"
"search for a JSON library"
```

### java-dependency
Analyze unused/undeclared deps, detect cycles, find version conflicts.
```
"check for unused dependencies"
"why am I getting NoClassDefFoundError?"
"show dependency tree for billing-core"
```

### java-build
Maven build commands with correct flags.
```
"build the project"
"compile billing-core module only"
"clean build with tests"
```

### java-format
Run Spotless formatter on Java files.
```
"fix formatting"
"spotless check is failing"
```

## Hooks

| Hook | Event | Description |
|---|---|---|
| check-java-version | PostToolUse (Write/Edit) | Warn on JDK version mismatch |
| auto-format-java | PostToolUse (Write/Edit) | Auto-format .java files via Spotless |

## Architecture

```
.claude-plugin/
  plugin.json              # Plugin manifest (name, version, metadata)
  marketplace.json         # Distribution config
scripts/
  common.sh                # Shared utilities (die, resolve_jdk_tool, check_pid, etc.)
  auto-format-java.sh      # PostToolUse hook (lightweight, no common.sh)
  check-java-version.sh    # PostToolUse hook
skills/
  <skill-name>/
    SKILL.md               # Skill instructions + trigger description
    scripts/<script>.sh    # Executable scripts (source common.sh)
hooks/
  hooks.json               # Hook event definitions
evals/
  evals.json               # Test prompts for skill evaluation
```

## Development

```bash
# Test locally
claude --plugin-dir .

# Reload after changes (inside session)
/reload-plugins

# Validate
claude plugin validate .

# Test scripts directly
bash skills/maven-central/scripts/maven-central.sh search guava
bash skills/jmx-connector/scripts/jmx-query.sh health <pid>
bash skills/java-heap-dump/scripts/heap-dump.sh histogram <pid>
```

## Version History

- **0.2.0** — Add java-heap-dump skill, extract shared utilities, improve triggering
- **0.1.0** — Initial release: 9 skills, 2 hooks
