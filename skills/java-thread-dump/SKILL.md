---
name: thread-dump
description: >
  Take and analyze Java thread dumps from running JVMs. Accepts OS-level PID
  from top, converts to JVM nid, finds deadlocks, blocked threads, and CPU hogs.
  Trigger phrases: "thread dump", "jstack", "deadlock", "thread blocked",
  "high cpu thread", "why is java hanging", "cpu hog", "thread analysis",
  "what is pid doing", "blocked thread".
---

# Java Thread Dump — Live JVM Thread Analysis

Takes thread dumps from running JVMs and analyzes for deadlocks, blocked threads,
and CPU-hogging threads. Correlates OS-level PIDs from `top` with JVM threads.

## Execution Instructions

### 1. CPU Hog — Find What a Thread Is Doing

When user provides an OS thread PID from `top -H`:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/java-thread-dump/scripts/thread-dump.sh <jvm-pid> --tid <os-thread-pid>
```

### 2. Full Dump with Analysis

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/java-thread-dump/scripts/thread-dump.sh <jvm-pid>
```

Auto-reports: deadlocks, blocked threads, RUNNABLE threads.

### 3. Repeated Dumps (Confirm CPU Hog)

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/java-thread-dump/scripts/thread-dump.sh <jvm-pid> --repeat 3
```

Takes 3 dumps 2s apart. If same thread stays RUNNABLE at same code location → confirmed CPU hog.

### 4. Determine JVM PID

If user only knows the OS thread PID:
```bash
# Find parent Java process
ps -o ppid= -p <os-thread-pid>
# Or find all Java processes
jps -l
# Or
ps aux | grep java
```

## How OS PID Maps to JVM Thread

- `top -H` shows Linux LWP (lightweight process) IDs in decimal
- JVM thread dump shows `nid=0x...` in hexadecimal
- Conversion: `printf '0x%x' <decimal-pid>` → hex nid
- Match hex nid in thread dump → that's your thread's stack trace

## Report Format

The script outputs a structured analysis:

```
═══ Thread Dump Analysis ═══

CPU Hog (nid=0xd431, OS PID 54321):
  Thread: "pool-1-thread-42" daemon prio=5
  State: RUNNABLE
  Stack:
    at com.example.HeavyProcessor.calculate(HeavyProcessor.java:89)
    at com.example.Worker.run(Worker.java:34)

Deadlocks: 1 found
  "http-nio-8080-exec-3" → waiting on lock 0x00007f1a held by "exec-7"
  "http-nio-8080-exec-7" → waiting on lock 0x00007f2b held by "exec-3"

Blocked Threads: 4
  "exec-1" BLOCKED on 0x00007f3c (held by "batch-processor-1")
  "exec-2" BLOCKED on 0x00007f3c (held by "batch-processor-1")

Summary: 142 threads total, 4 blocked, 12 runnable, 126 waiting
```

## Notes

- `jstack` requires same user or root as target JVM
- For containers: `docker exec <container> jstack 1`
- Multiple dumps confirm whether a thread is stuck or just happened to be there
- JVM must not have `-XX:+DisableAttachMechanism`
- If `jstack` hangs, try `jstack -F <pid>` (forced, less detail)
