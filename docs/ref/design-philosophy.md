## Core Design Philosophy

### Unix Philosophy Foundations
- **Do one thing well** - Each utility should have a single, clear purpose
- **Composability** - Design for chaining with other tools via pipes
- **Text streams as universal interface** - With structured output options for machines
- **Silence is golden** - No output on success unless explicitly requested
- **Fail fast and explicitly** - Clear, immediate errors with proper exit codes
- **Idempotency** - Operations should be idempotent where possible

### AI Agent Design Principles
- **Predictable, deterministic behavior** - Same inputs always produce same outputs
- **Structured output modes** - JSON/TSV/CSV options via flags
- **Machine-readable errors** - Parseable error formats, not just human prose
- **Explicit verbosity control** - Clear separation of operational output vs diagnostic info
- **No interactive prompts in non-interactive mode** - Fail fast instead

