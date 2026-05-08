---
name: build
description: >
  Build Java projects with Maven. Handles compilation, testing, packaging.
  Use this skill whenever the user mentions build errors, compile failures,
  class not found errors, maven problems, or wants to compile/package a project.
  Trigger phrases: "build java", "maven build", "compile", "mvn install",
  "run tests", "package", "mvn clean", "build project", "compile failed",
  "class not found", "build error", "maven error", "cannot find symbol".
---

# Java Build — Maven Build Management

Builds Java projects using Maven wrapper with proper Java version handling.

## Execution Instructions

When the user asks to build:

1. **Check Java version requirement**:
   ```bash
   cat .java-version 2>/dev/null || echo "no .java-version file"
   java -version
   ```

2. **Verify maven wrapper exists**:
   ```bash
   ls ./mvnw
   ```

3. **Run appropriate build command**:

   | User intent | Command |
   |---|---|
   | "build" / "compile" | `./mvnw compile -DskipTests` |
   | "test" / "run tests" | `./mvnw test` |
   | "test specific" | `./mvnw test -pl module -Dtest=ClassName` |
   | "package" / "jar" | `./mvnw package -DskipTests` |
   | "install" | `./mvnw install -DskipTests` |
   | "clean build" | `./mvnw clean install -DskipTests` |
   | "full build with tests" | `./mvnw clean install` |

4. **For multi-module projects**, target specific modules:
   ```bash
   ./mvnw compile -pl module-name -am
   ```
   `-am` (also-make) builds dependencies of target module.

5. **On failure**, parse error output and suggest fixes.

## Common Flags

| Flag | Purpose |
|---|---|
| `-DskipTests` | Skip test execution |
| `-Dmaven.test.skip=true` | Skip test compilation and execution |
| `-pl module` | Build specific module |
| `-am` | Also make dependencies |
| `-T 1C` | Parallel build (1 thread per core) |
| `-o` | Offline mode (use cached deps) |
| `-X` | Debug output |

## Notes

- Always use `./mvnw` over system `mvn`
- Check `.java-version` before building — wrong JDK causes cryptic failures
- For project-specific build profiles, check project CLAUDE.md
