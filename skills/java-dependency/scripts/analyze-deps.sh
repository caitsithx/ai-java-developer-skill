#!/usr/bin/env bash
# analyze-deps.sh — Run dependency analysis and summarize issues
#
# Usage:
#   analyze-deps.sh [module]        Analyze specific module
#   analyze-deps.sh --all           Analyze all modules
#   analyze-deps.sh --cycles        Check for cyclic dependencies

set -euo pipefail

MVN="./mvnw"
if [[ ! -x "${MVN}" ]]; then
    MVN="mvn"
fi

MODULE="${1:-}"
MODE="analyze"

if [[ "${MODULE}" == "--all" ]]; then
    MODULE=""
    MODE="analyze"
elif [[ "${MODULE}" == "--cycles" ]]; then
    MODULE=""
    MODE="cycles"
fi

PL_FLAG=""
if [[ -n "${MODULE}" ]]; then
    PL_FLAG="-pl ${MODULE}"
fi

case "${MODE}" in
    analyze)
        echo "Running dependency analysis..."
        echo "═══════════════════════════════════════"
        echo ""

        OUTPUT=$(${MVN} dependency:analyze ${PL_FLAG} 2>&1 || true)

        # Extract used undeclared
        USED_UNDECLARED=$(echo "${OUTPUT}" | grep -A 100 "Used undeclared dependencies found" | grep "^\[WARNING\]    " | sed 's/\[WARNING\]    //' || true)
        # Extract unused declared
        UNUSED_DECLARED=$(echo "${OUTPUT}" | grep -A 100 "Unused declared dependencies found" | grep "^\[WARNING\]    " | sed 's/\[WARNING\]    //' || true)

        if [[ -n "${USED_UNDECLARED}" ]]; then
            echo "⚠️  Used undeclared (add explicit dependency to POM):"
            echo "${USED_UNDECLARED}" | while IFS= read -r dep; do
                echo "  + ${dep}"
            done
            echo ""
        fi

        if [[ -n "${UNUSED_DECLARED}" ]]; then
            echo "⚠️  Unused declared (consider removing from POM):"
            echo "${UNUSED_DECLARED}" | while IFS= read -r dep; do
                echo "  - ${dep}"
            done
            echo ""
        fi

        if [[ -z "${USED_UNDECLARED}" && -z "${UNUSED_DECLARED}" ]]; then
            echo "✅ No dependency issues found."
        fi
        ;;

    cycles)
        echo "Checking for cyclic dependencies..."
        echo "═══════════════════════════════════════"
        echo ""

        # Maven will fail on reactor cycles
        CYCLE_OUTPUT=$(${MVN} validate 2>&1 || true)
        CYCLES=$(echo "${CYCLE_OUTPUT}" | grep -i "cycle" || true)

        if [[ -n "${CYCLES}" ]]; then
            echo "❌ Cyclic dependencies detected:"
            echo "${CYCLES}" | sed 's/^/  /'
        else
            echo "✅ No cyclic dependencies found."
        fi

        # Also check with dependency:tree dot output for deeper analysis
        echo ""
        echo "Module dependency graph:"
        ${MVN} dependency:tree -DoutputType=dot ${PL_FLAG} 2>/dev/null | grep " -> " | sed 's/^/  /' | head -30
        ;;
esac
