---
name: jmx
description: >
  Query JVM runtime metrics via JMX (jcmd/jstat). Read heap memory, GC stats,
  thread counts, CPU load, class loading, and custom MBeans from running JVMs.
  Use this skill whenever the user asks about JVM health, memory usage, whether
  there's a memory leak, GC pressure, or wants to check connection pool stats.
  Trigger phrases: "heap usage", "gc stats", "jmx", "memory usage",
  "how much heap", "connection pool", "jvm health", "thread count",
  "gc pauses", "class loading", "jstat", "jcmd", "is my app healthy",
  "memory leak", "how much memory", "out of memory".
---

# JMX Connector — JVM Runtime Metrics

Queries JVM operational metrics using `jcmd` and `jstat`. Spot-check heap,
GC, threads, CPU, class loading, and custom MBeans without opening JConsole.

## Execution Instructions

### 1. JVM Health Overview

Quick health check — heap, threads, GC, CPU:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/jmx-connector/scripts/jmx-query.sh health <pid>
```

### 2. Heap Memory

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/jmx-connector/scripts/jmx-query.sh heap <pid>
```

Shows: used, committed, max heap. Young/Old gen breakdown.

### 3. GC Statistics

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/jmx-connector/scripts/jmx-query.sh gc <pid>
```

Shows: GC counts, total pause time, last GC cause, collector names.

### 4. Thread Info

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/jmx-connector/scripts/jmx-query.sh threads <pid>
```

Shows: live count, daemon count, peak, threads started total.

### 5. CPU Load

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/jmx-connector/scripts/jmx-query.sh cpu <pid>
```

Shows: process CPU load, system CPU load, available processors.

### 6. Class Loading

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/jmx-connector/scripts/jmx-query.sh classes <pid>
```

Shows: loaded, unloaded, total loaded since start.

### 7. Custom MBean Query

Read any MBean attribute:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/jmx-connector/scripts/jmx-query.sh mbean <pid> <object-name> <attribute>
```

Example:
```bash
jmx-query.sh mbean 12345 "com.zaxxer.hikari:type=Pool (HikariPool-1)" ActiveConnections
```

### 8. List MBeans

Find available MBeans matching a pattern:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/jmx-connector/scripts/jmx-query.sh list <pid> [pattern]
```

## Report Format

```
═══ JVM Health (PID: 12345) ═══

Heap Memory:
  Used:      1.2 GB / 4.0 GB max (30%)
  Committed: 2.0 GB
  Young Gen: 400 MB used
  Old Gen:   800 MB used

GC:
  Young GC (G1 Young): 142 collections, 3.2s total pause
  Old GC (G1 Old):     2 collections, 1.8s total pause
  Last cause: G1 Evacuation Pause

Threads:
  Live: 87 (daemon: 72)
  Peak: 104

CPU:
  Process: 12.4%
  System:  34.2%
  Cores:   8
```

## Notes

- `jcmd` requires same user or root as target JVM
- `jstat` works without special access but provides less detail
- For containerized JVMs: `docker exec <container> jcmd 1 <command>`
- Custom MBeans depend on what the app registers (Spring Boot Actuator, HikariCP, etc.)
- JMX remote access (`-Dcom.sun.management.jmxremote`) not required — `jcmd` uses local attach
