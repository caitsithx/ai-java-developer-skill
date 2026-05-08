---
name: format
description: >
  Format Java code using Spotless with project code style.
  Trigger phrases: "format java", "spotless", "fix formatting",
  "code style", "reformat", "format file", "java formatter".
---

# Java Format — Spotless Code Formatter

Formats Java source files using the project's Spotless configuration.

## Usage

When the user asks to format Java code:

1. **Check for maven wrapper** in the project root:
   ```bash
   ls ./mvnw
   ```

2. **Run Spotless apply** on the target:
   ```bash
   # Format all files
   ./mvnw spotless:apply

   # Format specific module
   ./mvnw spotless:apply -pl module-name

   # Check without modifying (dry run)
   ./mvnw spotless:check
   ```

3. **If no mvnw exists**, try system maven:
   ```bash
   mvn spotless:apply
   ```

4. **Report results** — show which files changed.

## Notes

- Spotless config lives in project `pom.xml` under `<plugin>` section
- If Spotless is not configured, inform user and suggest alternatives
- Always run from project root (where `pom.xml` lives)
- For multi-module projects, `-pl` targets specific modules
