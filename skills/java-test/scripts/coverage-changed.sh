#!/usr/bin/env bash
# coverage-changed.sh — Run tests and report coverage for changed files
#
# Usage:
#   coverage-changed.sh [base-ref]
#
# base-ref: git ref to diff against (default: HEAD~1, or unstaged if no commits)

set -euo pipefail

BASE_REF="${1:-}"

# Find changed Java source files
if [[ -n "${BASE_REF}" ]]; then
    CHANGED=$(git diff --name-only "${BASE_REF}" -- '*.java' | grep 'src/main/java' || true)
elif git rev-parse HEAD~1 &>/dev/null; then
    # Try committed changes first, then unstaged
    CHANGED=$(git diff --name-only HEAD~1 -- '*.java' | grep 'src/main/java' || true)
    if [[ -z "${CHANGED}" ]]; then
        CHANGED=$(git diff --name-only -- '*.java' | grep 'src/main/java' || true)
    fi
else
    CHANGED=$(git diff --name-only -- '*.java' | grep 'src/main/java' || true)
fi

if [[ -z "${CHANGED}" ]]; then
    echo "No changed Java source files found."
    exit 0
fi

echo "Changed source files:"
echo "${CHANGED}" | sed 's/^/  /'
echo ""

# Map to test classes
TEST_CLASSES=""
MODULES=""
while IFS= read -r src; do
    base=$(basename "$src" .java)
    test_file=$(find . -path "*/src/test/java/*" -name "${base}Test.java" 2>/dev/null | head -1)
    if [[ -n "${test_file}" ]]; then
        test_class=$(basename "${test_file}" .java)
        TEST_CLASSES="${TEST_CLASSES:+${TEST_CLASSES},}${test_class}"
        # Extract module
        module=$(echo "${test_file}" | sed 's|^\./||' | cut -d'/' -f1)
        if [[ "${module}" != "src" ]]; then
            MODULES="${MODULES:+${MODULES},}${module}"
        fi
    else
        echo "⚠️  No test found for: ${base}.java"
    fi
done <<< "${CHANGED}"

if [[ -z "${TEST_CLASSES}" ]]; then
    echo "No matching test classes found."
    exit 0
fi

echo "Running tests: ${TEST_CLASSES}"
echo ""

# Build maven command
MVN="./mvnw"
if [[ ! -x "${MVN}" ]]; then
    MVN="mvn"
fi

CMD="${MVN} test"
if [[ -n "${MODULES}" ]]; then
    # Deduplicate modules
    UNIQUE_MODULES=$(echo "${MODULES}" | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')
    CMD="${CMD} -pl ${UNIQUE_MODULES}"
fi
CMD="${CMD} -Dtest=${TEST_CLASSES} jacoco:report"

echo "Command: ${CMD}"
echo ""

eval "${CMD}"

EXIT_CODE=$?
if [[ ${EXIT_CODE} -ne 0 ]]; then
    echo ""
    echo "❌ Tests failed (exit ${EXIT_CODE})"
    exit ${EXIT_CODE}
fi

echo ""
echo "✅ Tests passed. Jacoco report generated."
echo ""

# Find and parse jacoco reports
echo "Coverage for changed files:"
echo "─────────────────────────────────────────"

while IFS= read -r src; do
    base=$(basename "$src" .java)
    # Find jacoco.xml
    report=$(find . -path "*/target/site/jacoco/jacoco.xml" 2>/dev/null | head -1)
    if [[ -z "${report}" ]]; then
        continue
    fi

    # Extract coverage for this class using grep/awk (avoid xmllint dependency)
    # Look for the class name in jacoco.xml and extract LINE/BRANCH counters
    class_section=$(grep -A 20 "name=\"${base}\"" "${report}" 2>/dev/null | head -20 || true)
    if [[ -z "${class_section}" ]]; then
        echo "  ${base} — not found in report"
        continue
    fi

    line_covered=$(echo "${class_section}" | grep 'type="LINE"' | grep -oE 'covered="[0-9]+"' | grep -oE '[0-9]+' || echo "0")
    line_missed=$(echo "${class_section}" | grep 'type="LINE"' | grep -oE 'missed="[0-9]+"' | grep -oE '[0-9]+' || echo "0")
    branch_covered=$(echo "${class_section}" | grep 'type="BRANCH"' | grep -oE 'covered="[0-9]+"' | grep -oE '[0-9]+' || echo "0")
    branch_missed=$(echo "${class_section}" | grep 'type="BRANCH"' | grep -oE 'missed="[0-9]+"' | grep -oE '[0-9]+' || echo "0")

    line_total=$((line_covered + line_missed))
    branch_total=$((branch_covered + branch_missed))

    if [[ ${line_total} -gt 0 ]]; then
        line_pct=$((line_covered * 100 / line_total))
    else
        line_pct=0
    fi

    if [[ ${branch_total} -gt 0 ]]; then
        branch_pct=$((branch_covered * 100 / branch_total))
    else
        branch_pct=0
    fi

    printf "  %-40s Line: %3d%% (%d/%d)  Branch: %3d%% (%d/%d)\n" \
        "${base}" "${line_pct}" "${line_covered}" "${line_total}" \
        "${branch_pct}" "${branch_covered}" "${branch_total}"

done <<< "${CHANGED}"
