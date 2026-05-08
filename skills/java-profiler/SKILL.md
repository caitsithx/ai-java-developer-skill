---
name: profiler
description: >
  Profile running Java applications for CPU, memory, and lock contention.
  Uses async-profiler or JDK Flight Recorder. Generates flame graphs.
  Trigger phrases: "profile java", "flame graph", "cpu profile",
  "memory profiling", "allocation profiler", "what is slow",
  "performance profile", "JFR", "async-profiler", "hot methods".
---

# Java Profiler — CPU, Memory & Lock Profiling

Profiles running JVMs using async-profiler or JDK Flight Recorder (JFR).
Generates flame graphs and identifies hot methods, heavy allocators, and lock contention.

## Execution Instructions

### 1. CPU Profiling (Default)

Record which methods consume CPU time:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/java-profiler/scripts/profiler.sh start <pid> --event cpu --duration 30
```

### 2. Memory Allocation Profiling

Track which code paths allocate most objects:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/java-profiler/scripts/profiler.sh start <pid> --event alloc --duration 30
```

### 3. Lock Contention Profiling

Find where threads spend time waiting on locks:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/java-profiler/scripts/profiler.sh start <pid> --event lock --duration 30
```

### 4. Wall-Clock Profiling

Capture all time spent including I/O, sleep, park (not just CPU):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/java-profiler/scripts/profiler.sh start <pid> --event wall --duration 30
```

### 5. Generate Flame Graph

After profiling, convert to flame graph SVG:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/java-profiler/scripts/profiler.sh flamegraph <pid>
```

Opens or outputs path to SVG file.

### 6. Diff Profiles

Compare two profiles (before/after a change):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/java-profiler/scripts/profiler.sh diff <file1.jfr> <file2.jfr>
```

### 7. List Hot Methods

Show top N methods by sample count:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/java-profiler/scripts/profiler.sh top <pid> --limit 20
```

## Tool Selection

Script auto-selects profiler:

| Tool | When |
|---|---|
| async-profiler | Preferred. If `asprof` or `ASYNC_PROFILER_HOME` available |
| JFR (jcmd) | Fallback. Built into JDK 11+. No extra install needed |

async-profiler advantages: lower overhead, no safepoint bias, alloc/lock profiling.
JFR advantages: always available, broader event types, integrates with JMC.

## Report Format

```
═══ Profile Results (CPU, 30s) ═══

Top 10 hot methods:
  38.2%  com.example.JsonParser.parseObject (JsonParser.java:142)
  12.7%  com.example.DB.executeQuery (DB.java:89)
   8.4%  java.util.HashMap.resize (HashMap.java:701)
   6.1%  com.example.Serializer.write (Serializer.java:55)
   ...

Flame graph: /tmp/java-profiler/flame-12345-cpu.svg
Raw data: /tmp/java-profiler/profile-12345-cpu.jfr
```

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `ASYNC_PROFILER_HOME` | (auto-detect) | Path to async-profiler installation |
| `PROFILE_DURATION` | `30` | Default profiling duration in seconds |
| `PROFILE_OUTPUT` | `/tmp/java-profiler` | Output directory for profiles and flame graphs |

## Notes

- async-profiler requires same user or root as target JVM
- On macOS: async-profiler needs SIP disabled or `dtrace` permissions
- On Linux: may need `echo 1 > /proc/sys/kernel/perf_event_paranoid`
- JFR works everywhere JDK 11+ is installed, no extra setup
- Short duration (10-30s) usually sufficient — profile during representative load
- Flame graphs are SVGs — viewable in any browser
