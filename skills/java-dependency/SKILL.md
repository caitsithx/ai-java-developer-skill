---
name: dependency
description: >
  Analyze Java/Maven dependency issues: cyclic dependencies, unused declared,
  used undeclared, version conflicts, and dependency tree inspection.
  Trigger phrases: "dependency issue", "dependency tree", "unused dependency",
  "cyclic dependency", "dependency conflict", "dependency analyze",
  "used undeclared", "unused declared", "check dependencies".
---

# Java Dependency — Dependency Issue Analyzer

Identifies dependency problems in Maven projects: cycles, unused declarations,
undeclared usages, and version conflicts.

## Execution Instructions

### 1. Dependency Analysis (Primary)

Run Maven dependency analysis to find issues:

```bash
./mvnw dependency:analyze -pl module
```

This reports:
- **Used undeclared** — classes used in code but dependency not explicitly declared in POM (transitive only)
- **Unused declared** — dependency declared in POM but no classes used from it

Parse output for these sections:
```
[WARNING] Used undeclared dependencies found:
[WARNING]    groupId:artifactId:type:version:scope
[WARNING] Unused declared dependencies found:
[WARNING]    groupId:artifactId:type:version:scope
```

**Report format:**
```
Dependency Analysis for module-name:

Used undeclared (add to POM):
  - com.google.guava:guava:32.1.3-jre (used but only available transitively)

Unused declared (consider removing):
  - org.apache.commons:commons-lang3:3.14.0 (declared but no usage found)
```

### 2. Cyclic Dependencies

Detect circular module dependencies:

```bash
./mvnw dependency:tree -DoutputType=dot -pl module
```

Or for full reactor cycle detection:
```bash
./mvnw validate -pl module 2>&1 | grep -i "cycle"
```

For inter-module cycles, build the dependency graph:
```bash
# Get all module dependencies as dot format
./mvnw dependency:tree -DoutputType=dot -DoutputFile=/tmp/deps.dot
```

Parse the dot output to find cycles. Report:
```
Cyclic dependency detected:
  module-a → module-b → module-c → module-a
```

### 3. Dependency Tree

Show dependency tree for inspection:

```bash
# Full tree
./mvnw dependency:tree -pl module

# Filter by artifact
./mvnw dependency:tree -pl module -Dincludes=groupId:artifactId

# Show conflicts (verbose)
./mvnw dependency:tree -pl module -Dverbose
```

`-Dverbose` shows omitted duplicates and conflicts — essential for version conflict diagnosis.

### 4. Version Conflicts

Find dependency version conflicts:

```bash
./mvnw dependency:tree -pl module -Dverbose 2>&1 | grep "omitted for conflict"
```

Report format:
```
Version conflicts:
  com.fasterxml.jackson.core:jackson-databind
    - 2.15.3 (selected, from module-a)
    - 2.14.1 (omitted, from module-b)
```

### 5. Check for Updates

```bash
./mvnw versions:display-dependency-updates -pl module
```

## Command Summary

| Intent | Command |
|---|---|
| Analyze unused/undeclared | `./mvnw dependency:analyze -pl module` |
| Detect cycles | `./mvnw dependency:tree -DoutputType=dot` |
| Show tree | `./mvnw dependency:tree -pl module` |
| Find conflicts | `./mvnw dependency:tree -pl module -Dverbose` |
| Check updates | `./mvnw versions:display-dependency-updates -pl module` |

## Notes

- Always use `./mvnw` over system `mvn`
- `dependency:analyze` only checks compile/runtime scope by default
- Some "unused declared" may be runtime-only deps (JDBC drivers, SPI) — flag but don't auto-remove
- For multi-module projects, run per-module with `-pl` for targeted analysis
- Cycle detection at reactor level fails the build — Maven won't build cyclic modules
