# ai-java-developer-skill

Claude Code plugin for Java development: debugging, formatting, and building.

## Skills

| Skill | Invocation | Description |
|---|---|---|
| jdb-debug | `/ai-java-developer-skill:jdb-debug` | Interactive Java debugger via named pipes |
| format | `/ai-java-developer-skill:format` | Spotless code formatting |
| build | `/ai-java-developer-skill:build` | Maven build management |

## Install

```bash
# Add marketplace
claude plugin marketplace add xili-zuora/ai-java-developer-skill

# Install plugin
claude plugin install ai-java-developer-skill@ai-java-developer

# Or load directly during development
claude --plugin-dir /path/to/ai-java-developer-skill
```

## Development

```bash
# Test locally
claude --plugin-dir .

# Reload after changes (inside session)
/reload-plugins

# Validate
claude plugin validate .
```
