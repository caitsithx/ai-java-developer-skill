---
name: heap-dump
description: >
  Take and analyze Java heap dumps. Class histograms, heap dump capture,
  histogram diffing to find memory leaks. Uses jcmd/jmap (built-in JDK tools).
  Use this skill whenever the user suspects a memory leak, wants to know what
  is consuming heap, needs a heap dump, or sees OutOfMemoryError.
  Trigger phrases: "heap dump", "memory leak", "what is using memory",
  "OutOfMemoryError", "OOM", "class histogram", "hprof", "object count",
  "heap analysis", "growing memory", "memory consumption", "dump heap",
  "which objects", "retained size".
---

# Java Heap Dump — Memory Analysis

Take heap dumps, class histograms, and diff snapshots to find memory leaks.
Uses built-in JDK tools (jcmd, jmap) — no external dependencies.

## Execution Instructions

### 1. Class Histogram (Fast, No Pause)

Show top memory-consuming classes without taking a full dump:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/java-heap-dump/scripts/heap-dump.sh histogram <pid> [--limit 20]
```

### 2. Live Histogram (Triggers GC First)

Same as histogram but forces GC before snapshot — shows only reachable objects:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/java-heap-dump/scripts/heap-dump.sh histogram-live <pid> [--limit 20]
```

### 3. Take Heap Dump

Capture full heap dump (.hprof) for deep analysis:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/java-heap-dump/scripts/heap-dump.sh dump <pid> [--output /path/to/file.hprof]
```

**Note:** This briefly pauses the JVM while writing the dump.

### 4. Diff Histograms (Leak Detection)

Take two histograms N seconds apart, show what grew:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/java-heap-dump/scripts/heap-dump.sh diff <pid> [--interval 30] [--limit 20]
```

Classes with significant instance/byte growth between snapshots = likely leak candidates.

### 5. Native Memory (Requires NMT)

If JVM started with `-XX:NativeMemoryTracking=summary`:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/java-heap-dump/scripts/heap-dump.sh native <pid>
```

## Report Format

```
═══ Class Histogram (PID: 12345, top 20) ═══

 #instances  #bytes  class name
─────────────────────────────────────────
   1,234,567  98,765,360  [B (byte[])
     456,789  43,851,744  java.lang.String
     234,567  18,765,360  java.util.HashMap$Node
     ...

═══ Histogram Diff (30s apart) ═══

Growing classes (sorted by byte increase):
  +12,345 instances  +987,600 bytes  com.example.CachedEntry
  +5,678 instances   +454,240 bytes  java.lang.String
  +1,234 instances   +148,080 bytes  java.util.HashMap$Node

Shrinking classes:
  -500 instances     -40,000 bytes   java.lang.ref.WeakReference
```

## Leak Detection Workflow

1. Run `histogram` — see current top consumers
2. Wait for suspected leak activity (or trigger load)
3. Run `diff --interval 30` — see what's growing
4. If clear growth pattern → take full `dump` for MAT analysis
5. Open .hprof in Eclipse MAT for dominator tree / retained size

## Notes

- `histogram` is safe to run in production (no pause)
- `histogram-live` triggers full GC — may cause brief pause
- `dump` pauses JVM for duration of write — file can be large (proportional to heap)
- For individual object sizes / dominator tree → open .hprof in Eclipse MAT
- Default dump location: `/tmp/heap-dump/heap-<pid>-<timestamp>.hprof`
