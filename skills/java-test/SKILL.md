---
name: test
description: >
  Run Java tests, debug tests, analyze coverage for changed files.
  Trigger phrases: "run test", "test class", "run unit tests",
  "debug test", "test coverage", "coverage report", "rerun failed",
  "test method", "run tests for".
---

# Java Test — Test Runner & Coverage Analyzer

Runs tests, debugs test execution, and analyzes coverage for changed files.

## Execution Instructions

### 1. Run Specific Tests

Map user intent to Maven command:

| Intent | Command |
|---|---|
| Run test class | `./mvnw test -pl module -Dtest=MyClassTest` |
| Run single method | `./mvnw test -pl module -Dtest=MyClassTest#methodName` |
| Run by tag/category | `./mvnw test -pl module -Dgroups=unit` |
| Run all tests in module | `./mvnw test -pl module` |
| Rerun failures | `./mvnw test -pl module -Dsurefire.rerunFailingTestsCount=2` |

To find which module a test belongs to:
```bash
find . -path "*/src/test/java/*" -name "MyClassTest.java" | head -1
```
Extract module from path (first directory component after `./`).

### 2. Debug Test

Start test JVM with JDWP suspended, then attach jdb-debug:

```bash
# Step 1: Run test with debug agent (suspend=y waits for debugger)
./mvnw test -pl module -Dtest=MyClassTest \
  -Dmaven.surefire.debug="-agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=*:5005" &

# Step 2: Wait for JVM to start listening
sleep 3

# Step 3: Attach debugger
bash ${CLAUDE_PLUGIN_ROOT}/skills/jdb-debug/scripts/jdb-debug.sh attach 5005
```

After attaching:
- Set breakpoints in the class under test or test class itself
- `cont` to start test execution (JVM is suspended until first `cont`)
- Inspect state at breakpoints
- `cont` to finish test

### 3. Coverage for Changed Files

Analyze test coverage focused on recently modified source files:

```bash
# Step 1: Find changed source files
git diff --name-only HEAD~1 -- '*.java' | grep 'src/main/java' > /tmp/changed-sources.txt
# Or for uncommitted changes:
git diff --name-only -- '*.java' | grep 'src/main/java' > /tmp/changed-sources.txt
```

```bash
# Step 2: Map source files to test classes
# Convention: src/main/java/com/example/Foo.java -> FooTest.java
# Find matching tests:
while IFS= read -r src; do
  base=$(basename "$src" .java)
  find . -path "*/src/test/java/*" -name "${base}Test.java"
done < /tmp/changed-sources.txt
```

```bash
# Step 3: Run those tests with coverage
./mvnw test -pl module -Dtest=FooTest,BarTest jacoco:report
```

```bash
# Step 4: Parse Jacoco report for changed classes only
# Jacoco XML report location: target/site/jacoco/jacoco.xml
# Or per-module: module/target/site/jacoco/jacoco.xml
```

**Parsing Jacoco XML:**
- Find `<class>` elements matching changed class names
- Extract `LINE` and `BRANCH` counters: `<counter type="LINE" missed="X" covered="Y"/>`
- Calculate: coverage % = covered / (covered + missed) * 100

**Report format:**
```
Coverage for changed files:
  com.example.Foo       — Line: 85% (34/40)  Branch: 72% (13/18)
  com.example.Bar       — Line: 92% (46/50)  Branch: 88% (7/8)

Uncovered lines in Foo.java: 45-48, 62, 71-73
```

**To find uncovered lines**, parse Jacoco XML `<sourcefile>` elements:
- `<line nr="45" mi="1" ci="0"/>` means line 45 is missed (mi > 0, ci = 0)

### 4. On Failure

When tests fail:
- Show the failure message and assertion error
- Show the relevant test method source
- Show the source code at the failing line
- Suggest fix or offer to debug the failing test

## Notes

- Always use `./mvnw` over system `mvn`
- For multi-module projects, always specify `-pl module`
- Default debug port: 5005 (standard Maven Surefire debug port)
- `suspend=y` is critical for debugging — without it, test may finish before debugger attaches
- Jacoco must be configured in the project POM for coverage to work
