---
name: maven-central
description: >
  Search Maven Central for artifacts, find latest versions, get POM snippets.
  Use this skill whenever the user wants to add a library, find the right version
  of a dependency, get Maven coordinates, or needs a POM snippet.
  Trigger phrases: "find artifact", "maven central", "latest version of",
  "search maven", "dependency for", "add dependency", "what version",
  "find library", "maven coordinates", "groupId artifactId",
  "what version should I use", "add library", "find package",
  "which artifact".
---

# Maven Central — Artifact Search & Version Lookup

Searches Maven Central repository for artifacts, retrieves latest versions,
and generates POM dependency snippets.

## Execution Instructions

### 1. Search for Artifacts

Find artifacts by keyword:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/maven-central/scripts/maven-central.sh search <query>
```

Examples:
- `search jackson-databind`
- `search "apache commons lang"`
- `search guava`

### 2. Get Latest Version

Look up latest version of a specific artifact:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/maven-central/scripts/maven-central.sh latest <groupId>:<artifactId>
```

Examples:
- `latest com.google.guava:guava`
- `latest com.fasterxml.jackson.core:jackson-databind`

### 3. List All Versions

Show available versions for an artifact:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/maven-central/scripts/maven-central.sh versions <groupId>:<artifactId> [--limit 10]
```

### 4. Generate POM Snippet

Output ready-to-paste `<dependency>` XML:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/maven-central/scripts/maven-central.sh pom <groupId>:<artifactId> [version]
```

If version omitted, uses latest.

### 5. Get Artifact Info

Show metadata: description, license, latest release date:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/maven-central/scripts/maven-central.sh info <groupId>:<artifactId>
```

## Report Format

```
Search results for "jackson":
  com.fasterxml.jackson.core:jackson-databind  2.17.0  (2024-03-12)
  com.fasterxml.jackson.core:jackson-core      2.17.0  (2024-03-12)
  com.fasterxml.jackson.core:jackson-annotations 2.17.0

POM snippet:
  <dependency>
      <groupId>com.fasterxml.jackson.core</groupId>
      <artifactId>jackson-databind</artifactId>
      <version>2.17.0</version>
  </dependency>
```

## API Used

Maven Central REST API (search.maven.org):
- Search: `https://search.maven.org/solrsearch/select?q=<query>&rows=20&wt=json`
- Coordinates: `https://search.maven.org/solrsearch/select?q=g:<groupId>+AND+a:<artifactId>&core=gav&rows=10&wt=json`

No authentication required.

## Notes

- Results sorted by popularity/relevance by default
- For SNAPSHOT versions, Maven Central won't have them — those live in snapshot repos
- Version "latest" means latest release (non-snapshot, non-RC unless nothing else exists)
- Script requires `curl` and `jq`
