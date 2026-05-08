#!/usr/bin/env bash
# check-java-version.sh — Warn if editing Java files with wrong JDK active
# Runs as PostToolUse hook on Write/Edit

set -euo pipefail

# Only check if a .java-version file exists in the project
JAVA_VERSION_FILE=".java-version"
if [[ ! -f "${JAVA_VERSION_FILE}" ]]; then
    exit 0
fi

REQUIRED_VERSION=$(cat "${JAVA_VERSION_FILE}" | tr -d '[:space:]')
CURRENT_VERSION=$(java -version 2>&1 | head -1 | grep -oE '[0-9]+' | head -1)

if [[ "${CURRENT_VERSION}" != "${REQUIRED_VERSION}" ]]; then
    echo "⚠️  Java version mismatch: project requires ${REQUIRED_VERSION}, active JDK is ${CURRENT_VERSION}"
fi
