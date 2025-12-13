## AI Agent Considerations

### Auto-Detection of Agent Mode
Trigger agent mode when:
- Non-interactive terminal (`!isatty()`)
- CI environment variable set
- Streams are merged (stdout==stderr)
- `MYTOOL_AGENT_MODE=1` environment variable
- `--format=json` or other structured format requested

### Agent Mode Behavior
- No progress indicators or spinners
- No colors or text formatting
- Structured output preferred
- No interactive prompts (fail instead)
- Deterministic output ordering
- Include metadata in structured output

### Recommended Agent Invocation
```bash
# Explicit agent-friendly invocation
mytool [command] \
  --format=json \
  --no-progress \
  --no-color \
  --batch

# Or via environment
export MYTOOL_AGENT_MODE=1
mytool [command]
```

### Help for Agents
```bash
# Machine-readable help
mytool --help --format=json

# List available commands/flags
mytool --list-commands
mytool --list-flags
mytool subcommand --list-flags

# Generate shell completions
mytool --generate-completion bash|zsh|fish
```

