## Input/Output Handling

### Stream Usage
- **stdin**: Primary input data (when no file specified)
- **stdout**: Primary output, pipeable data only
- **stderr**: Errors, warnings, progress indicators, diagnostics

### Core Principle
`stdout` should be immediately pipeable - never mix status messages with data output.

### Stream Behavior Examples
```bash
# Good - clean separation
$ mytool process data.txt > output.txt
Processing 1000 records...    # to stderr
[progress bar]                # to stderr
Done!                         # to stderr
# output.txt contains only data

# Bad - mixed output
$ mytool process data.txt > output.txt
Processing 1000 records...    # to stdout (contaminating)
{"data": "actual output"}     # to stdout
Done!                         # to stdout (contaminating)
```

### Handling Merged Streams (2>&1)

#### Detection
```python
import os
import sys

streams_merged = os.fstat(sys.stdout.fileno()) == os.fstat(sys.stderr.fileno())
```

#### Adaptation Strategies

1. **Automatic Mode Switching**
   ```bash
   # When streams merged detected:
   - Suppress all progress/status to stderr
   - Switch to structured output if available
   - Use line prefixes for critical messages
   ```

2. **Prefixed Output Pattern**
   ```
   ERROR: Failed to process record 5
   WARNING: Using deprecated format
   DATA: {"actual": "data", "here": true}
   PROGRESS: 50/100 records processed
   ```

3. **Structured Output Mode**
   ```json
   {"type":"progress","current":0,"total":1000}
   {"type":"data","content":{"id":1,"value":"foo"}}
   {"type":"warning","message":"Deprecated field 'bar'"}
   {"type":"data","content":{"id":2,"value":"baz"}}
   {"type":"result","status":"success","records":1000}
   ```

### Interactive vs Non-Interactive

```bash
# Detection
if [ -t 0 ] && [ -t 1 ]; then
    # Interactive: colors, prompts, progress bars OK
else
    # Non-interactive: plain output, no prompts
fi

# Override flags
--interactive     # Force interactive mode
--batch          # Force non-interactive mode
--no-tty         # Assume no terminal
```

### Pipeline Safety
```bash
# Guarantee clean stdout for pipelines
--pipe           # Equivalent to: --quiet --format=text --no-progress

# Usage
mytool process --pipe < input.txt | next-tool
```

