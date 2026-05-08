#!/usr/bin/env bash
# auto-format-java.sh — Auto-format Java files after Write/Edit via Spotless
# Runs as PostToolUse hook

set -euo pipefail

# Hook script — intentionally lightweight (no common.sh sourcing to avoid overhead)

# Only act on .java files
FILE_PATH="${CLAUDE_FILE_PATH:-}"
if [[ -z "${FILE_PATH}" || "${FILE_PATH}" != *.java ]]; then
    exit 0
fi

# Need mvnw to run spotless
if [[ ! -x "./mvnw" ]]; then
    exit 0
fi

# Check if spotless plugin is configured
if ! grep -q "spotless-maven-plugin" pom.xml 2>/dev/null; then
    exit 0
fi

# Run spotless on the specific file
./mvnw spotless:apply -DspotlessFiles="${FILE_PATH}" -q 2>/dev/null || true
