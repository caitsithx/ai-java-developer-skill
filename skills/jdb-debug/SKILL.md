---
name: jdb-debug
description: >
  Interactive Java debugger (jdb) controller for Claude Code.
  Attaches to any running JVM with JDWP enabled via named pipes, allowing
  breakpoints, variable inspection, stepping, and execution control — all
  from within Claude Code without an interactive terminal.
  Use this skill whenever the user wants to debug Java code at runtime,
  inspect variable values, understand why a NullPointerException occurs,
  check what value a field has during execution, or step through code logic.
  Trigger phrases: "attach debugger", "set breakpoint", "debug java",
  "inspect variable", "jdb", "breakpoint at", "print variable",
  "stack trace", "detach debugger", "connect debugger to port",
  "step through code", "debug port", "null pointer", "inspect at runtime",
  "why is this value wrong", "what is the value of".
---

# JDB Debug — Java Debugger for Claude Code

Controls `jdb` (Java command-line debugger) through named pipes, enabling
interactive debugging of any running JVM from within Claude Code.

## Prerequisites

| Requirement | Details |
|---|---|
| `jdb` | Any JDK (8, 11, 17, 21+) with `jdb` on PATH or under `JAVA_HOME/bin/` |
| Target JVM | Must be started with JDWP agent: `-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:<port>` |
| Port | JDWP allows only **one** debugger at a time per port |

## Commands

All commands run via:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/jdb-debug/scripts/jdb-debug.sh <command> [args]
```

### Session Management

| Command | Description |
|---|---|
| `attach <port>` | Connect to a JVM debug port. Kills any existing jdb session first. |
| `detach` | Disconnect and clean up the jdb session. |
| `status` | Show connection state, port, PID, and active breakpoints. |

### Breakpoints

| Command | Description |
|---|---|
| `break <class.method>` | Set a breakpoint (e.g., `break com.example.MyClass.myMethod`) |
| `clear <class.method>` | Remove a breakpoint |
| `breaks` | List all active breakpoints |

### Execution Control

| Command | Description |
|---|---|
| `cont` | Continue execution (resume from breakpoint) |
| `step` | Step into the next method call |
| `next` | Step over (execute current line, stop at next) |

### Inspection

| Command | Description |
|---|---|
| `print <expr>` | Evaluate and print an expression (variable, method call, etc.) |
| `locals` | Print all local variables in the current stack frame |
| `where` | Print the current thread's stack trace |
| `threads` | List all JVM threads (capped at 50 lines) |

### Raw Commands

| Command | Description |
|---|---|
| `cmd <anything>` | Send any raw jdb command (escape hatch) |

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `JDB_WAIT` | `2` | Seconds to wait for jdb response after sending a command. Increase for slow operations. |
| `JAVA_HOME` | (auto) | If `jdb` is not on PATH, the script looks for `$JAVA_HOME/bin/jdb`. |

## State Files

All session state lives under `/tmp/jdb-debug/`:

| File | Purpose |
|---|---|
| `in` | Named pipe (FIFO) — jdb stdin |
| `out` | Regular file — jdb stdout/stderr capture |
| `pid` | PID of the `tail -f` feeder process |
| `port` | Port number of the current debug session |

## Execution Instructions

When the user invokes this skill:

1. **Determine the subcommand** from the user's request:
   - "attach" / "connect debugger" / "debug port X" -> `attach <port>`
   - "detach" / "disconnect" / "stop debugging" -> `detach`
   - "status" / "is debugger connected" -> `status`
   - "set breakpoint on X" / "break at X" -> `break <class.method>`
   - "remove breakpoint" / "clear breakpoint" -> `clear <class.method>`
   - "list breakpoints" / "show breakpoints" -> `breaks`
   - "continue" / "resume" -> `cont`
   - "step into" / "step" -> `step`
   - "step over" / "next" -> `next`
   - "print X" / "inspect X" / "what is X" -> `print <expr>`
   - "show locals" / "local variables" -> `locals`
   - "stack trace" / "where am I" -> `where`
   - "show threads" / "list threads" -> `threads`

2. **Run the script**:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/jdb-debug/scripts/jdb-debug.sh <command> [args]
   ```

3. **Interpret the output** and relay it to the user.

4. **Important timing considerations**:
   - When a breakpoint is hit, the **thread is suspended**. HTTP requests served
     by that thread will timeout if you don't `cont` within ~30 seconds.
   - For inspect-and-continue workflows: send `print` commands immediately,
     then `cont` quickly. Don't pause for analysis while the thread is suspended.
   - For long inspections: use `print` to capture the data, then `cont` first,
     and analyze the captured output afterward.
   - The `threads` command can produce large output — it's capped at 50 lines.

5. **If attach fails**:
   - "Connection refused" -> Target JVM is not running or JDWP is not enabled on that port.
   - Check with `lsof -i :<port>` to see if anything is listening.
   - JDWP only allows one debugger — if IntelliJ is attached, jdb can't connect.
