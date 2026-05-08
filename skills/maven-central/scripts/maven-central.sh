#!/usr/bin/env bash
# maven-central.sh — Search Maven Central and get artifact info
#
# Usage:
#   maven-central.sh search <query>
#   maven-central.sh latest <groupId>:<artifactId>
#   maven-central.sh versions <groupId>:<artifactId> [--limit N]
#   maven-central.sh pom <groupId>:<artifactId> [version]
#   maven-central.sh info <groupId>:<artifactId>

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

BASE_URL="https://search.maven.org/solrsearch/select"
LIMIT=10
COMMAND=""
QUERY=""
VERSION=""

# ── Parse args ──

while [[ $# -gt 0 ]]; do
    case "$1" in
        --limit) LIMIT="$2"; shift 2 ;;
        -*)      die "Unknown flag: $1" ;;
        *)
            if [[ -z "${COMMAND}" ]]; then
                COMMAND="$1"
            elif [[ -z "${QUERY}" ]]; then
                QUERY="$1"
            elif [[ -z "${VERSION}" ]]; then
                VERSION="$1"
            fi
            shift
            ;;
    esac
done

[[ -n "${COMMAND}" ]] || die "Usage: maven-central.sh <search|latest|versions|pom|info> <query>"
[[ -n "${QUERY}" ]] || die "Missing query/coordinates"

command -v curl &>/dev/null || die "curl required"
command -v jq &>/dev/null || die "jq required"

# ── Helpers ──

parse_coords() {
    local coords="$1"
    GROUP_ID="${coords%%:*}"
    ARTIFACT_ID="${coords##*:}"
    [[ -n "${GROUP_ID}" && -n "${ARTIFACT_ID}" ]] || die "Invalid coordinates: ${coords}. Use groupId:artifactId"
}

fetch() {
    local url="$1"
    curl -s --fail "${url}" || die "Failed to fetch from Maven Central"
}

# ── Commands ──

cmd_search() {
    local encoded_query
    encoded_query=$(printf '%s' "${QUERY}" | sed 's/ /+/g')
    local response
    response=$(fetch "${BASE_URL}?q=${encoded_query}&rows=${LIMIT}&wt=json")

    local num_found
    num_found=$(echo "${response}" | jq '.response.numFound')

    echo "Search: \"${QUERY}\" (${num_found} results, showing ${LIMIT})"
    echo "───────────────────────────────────────"

    echo "${response}" | jq -r '.response.docs[] | "\(.g):\(.a)  \(.latestVersion)  (\(.timestamp / 1000 | strftime("%Y-%m-%d")))"' 2>/dev/null || \
    echo "${response}" | jq -r '.response.docs[] | "\(.g):\(.a)  \(.latestVersion)"'
}

cmd_latest() {
    parse_coords "${QUERY}"
    local response
    response=$(fetch "${BASE_URL}?q=g:${GROUP_ID}+AND+a:${ARTIFACT_ID}&rows=1&wt=json")

    local version
    version=$(echo "${response}" | jq -r '.response.docs[0].latestVersion // empty')

    if [[ -z "${version}" ]]; then
        die "Artifact not found: ${GROUP_ID}:${ARTIFACT_ID}"
    fi

    echo "${GROUP_ID}:${ARTIFACT_ID}:${version}"
}

cmd_versions() {
    parse_coords "${QUERY}"
    local response
    response=$(fetch "${BASE_URL}?q=g:${GROUP_ID}+AND+a:${ARTIFACT_ID}&core=gav&rows=${LIMIT}&wt=json")

    local num_found
    num_found=$(echo "${response}" | jq '.response.numFound')

    echo "Versions for ${GROUP_ID}:${ARTIFACT_ID} (${num_found} total, showing ${LIMIT}):"
    echo "───────────────────────────────────────"

    echo "${response}" | jq -r '.response.docs[] | "  \(.v)  (\(.timestamp / 1000 | strftime("%Y-%m-%d")))"' 2>/dev/null || \
    echo "${response}" | jq -r '.response.docs[] | "  \(.v)"'
}

cmd_pom() {
    parse_coords "${QUERY}"

    if [[ -z "${VERSION}" ]]; then
        # Fetch latest
        local response
        response=$(fetch "${BASE_URL}?q=g:${GROUP_ID}+AND+a:${ARTIFACT_ID}&rows=1&wt=json")
        VERSION=$(echo "${response}" | jq -r '.response.docs[0].latestVersion // empty')
        [[ -n "${VERSION}" ]] || die "Artifact not found: ${GROUP_ID}:${ARTIFACT_ID}"
    fi

    echo "<dependency>"
    echo "    <groupId>${GROUP_ID}</groupId>"
    echo "    <artifactId>${ARTIFACT_ID}</artifactId>"
    echo "    <version>${VERSION}</version>"
    echo "</dependency>"
}

cmd_info() {
    parse_coords "${QUERY}"
    local response
    response=$(fetch "${BASE_URL}?q=g:${GROUP_ID}+AND+a:${ARTIFACT_ID}&rows=1&wt=json")

    local doc
    doc=$(echo "${response}" | jq '.response.docs[0] // empty')
    [[ -n "${doc}" && "${doc}" != "null" ]] || die "Artifact not found: ${GROUP_ID}:${ARTIFACT_ID}"

    echo "Artifact: ${GROUP_ID}:${ARTIFACT_ID}"
    echo "───────────────────────────────────────"
    echo "${doc}" | jq -r '"  Latest version: \(.latestVersion)"'
    echo "${doc}" | jq -r '"  Packaging: \(.p // "jar")"'
    echo "${doc}" | jq -r '"  Last updated: \((.timestamp // 0) / 1000 | strftime("%Y-%m-%d"))"' 2>/dev/null || true
    echo "${doc}" | jq -r '"  Version count: \(.versionCount // "unknown")"'

    # Tags/ec
    local tags
    tags=$(echo "${doc}" | jq -r '.tags // [] | join(", ")' 2>/dev/null || true)
    if [[ -n "${tags}" && "${tags}" != "null" ]]; then
        echo "  Tags: ${tags}"
    fi
}

# ── Dispatch ──

case "${COMMAND}" in
    search)   cmd_search ;;
    latest)   cmd_latest ;;
    versions) cmd_versions ;;
    pom)      cmd_pom ;;
    info)     cmd_info ;;
    *)
        echo "maven-central.sh — Search Maven Central"
        echo ""
        echo "Commands:"
        echo "  search <query>                  Search artifacts"
        echo "  latest <group>:<artifact>       Get latest version"
        echo "  versions <group>:<artifact>     List versions"
        echo "  pom <group>:<artifact> [ver]    Generate POM snippet"
        echo "  info <group>:<artifact>         Show artifact metadata"
        ;;
esac
