# Developing Tools for Devex

This guide covers how to create tools (commands) for devex, including all available interfaces, best practices, and patterns.

## Quick Start

Create a file in `tasks/` (or `lib/devex/builtins/` for built-ins):

```ruby
# tasks/hello.rb
desc "Say hello"

def run
  $stdout.print "Hello, world!\n"
end
```

Run with: `dx hello`

---

## Tool Definition DSL

### Basic Metadata

```ruby
desc "Short description (shown in help listing)"

long_desc <<~DESC
  Longer description shown when running `dx help <tool>`.
  Can span multiple lines and include examples.
DESC
```

### Flags (Options)

```ruby
flag :verbose, "-v", "--verbose", desc: "Enable verbose output"
flag :count, "-n COUNT", "--count=COUNT", desc: "Number of times"
flag :format, "-f FORMAT", "--format=FORMAT", desc: "Output format"
```

Access in `run`: `verbose`, `count`, `format` (as methods) or `options[:verbose]`

### Positional Arguments

```ruby
required_arg :filename, desc: "File to process"
optional_arg :output, desc: "Output file (default: stdout)"
remaining_args :files, desc: "Additional files"
```

Access in `run`: `filename`, `output`, `files` (as methods)

### Nested Tools (Subcommands)

```ruby
# tasks/db.rb
desc "Database operations"

tool "migrate" do
  desc "Run migrations"
  def run
    # ...
  end
end

tool "seed" do
  desc "Seed the database"
  flag :env, "-e ENV", desc: "Environment"
  def run
    # ...
  end
end
```

Access as: `dx db migrate`, `dx db seed --env=test`

---

## Runtime Context

### Detecting Environment

```ruby
def run
  # What environment are we in?
  Devex::Context.env           # => "development", "test", "staging", "production"
  Devex::Context.development?  # => true/false
  Devex::Context.production?   # => true/false
  Devex::Context.safe_env?     # => true for dev/test, false for staging/prod
end
```

Set via `DX_ENV`, `DEVEX_ENV`, `RAILS_ENV`, or `RACK_ENV`.

### Detecting Agent Mode

When invoked by an AI agent (Claude, etc.), output should be structured and machine-readable:

```ruby
def run
  if Devex::Context.agent_mode?
    # Output JSON, avoid colors, no interactive prompts
  else
    # Rich terminal output okay
  end
end
```

Agent mode is detected when:
- `DX_AGENT_MODE=1` environment variable is set
- stdout/stderr are merged (`2>&1` redirection)
- Not a TTY and not CI

### Detecting Interactive Mode

```ruby
def run
  if Devex::Context.interactive?
    # Can prompt user, show progress bars, etc.
  else
    # Non-interactive: fail or use defaults, no prompts
  end
end
```

### Detecting CI

```ruby
def run
  if Devex::Context.ci?
    # Running in GitHub Actions, GitLab CI, etc.
  end
end
```

### Call Tree (Task Invocation Chain)

Tools can know if they were invoked from another tool:

```ruby
def run
  Devex::Context.invoked_from_task?  # => true if called by another tool
  Devex::Context.invoking_task       # => "pre-commit" (immediate parent)
  Devex::Context.root_task           # => "pre-commit" (first in chain)
  Devex::Context.call_tree           # => ["pre-commit", "lint", "rubocop"]
end
```

Use case: A `lint` tool might skip certain checks when invoked from `pre-commit` vs directly.

### Terminal Detection

```ruby
Devex::Context.terminal?      # All three streams are TTYs
Devex::Context.stdout_tty?    # stdout specifically
Devex::Context.piped?         # Data being piped in or out
Devex::Context.color?         # Should we use colors?
```

---

## Global Options

Tools have access to global flags set by the user:

```ruby
def run
  # Access global options
  global_options[:format]   # --format value
  global_options[:verbose]  # -v count (0, 1, 2, ...)
  global_options[:quiet]    # -q was set

  # Convenience methods
  verbose?                  # true if -v was passed
  verbose                   # verbosity level (0, 1, 2, ...)
  quiet?                    # true if -q was passed

  # Effective output format (considers global + tool flags + context)
  output_format             # => :text, :json, or :yaml
end
```

---

## Output Patterns

### Rule: Never Stack `puts` Calls

Bad:
```ruby
puts "Header"
puts "Line 1"
puts "Line 2"
```

Good:
```ruby
$stdout.print Devex.render_template("my_template", data)
```

### Structured Output (JSON/YAML)

```ruby
def run
  data = { status: "ok", count: 42 }

  case output_format
  when :json, :yaml
    Devex::Output.data(data, format: output_format)
  else
    $stdout.print Devex.render_template("my_template", data)
  end
end
```

### Using Templates

Templates live in `lib/devex/templates/*.erb`:

```ruby
# In your tool:
$stdout.print Devex.render_template("status", {
  name: "myproject",
  version: "1.0.0",
  healthy: true
})
```

```erb
<%# lib/devex/templates/status.erb %>
<%= heading "Status" %>
  Project: <%= c :emphasis, name %>
  Version: <%= version %>
  Health:  <%= healthy ? csym(:success) : csym(:error) %> <%= healthy ? "OK" : "FAILING" %>
```

### Template Helpers

Available in all templates:

| Helper | Description | Example |
|--------|-------------|---------|
| `c(color, text)` | Colorize text | `<%= c :success, "done" %>` |
| `c(style, color, text)` | Multiple styles | `<%= c :bold, :white, "HEADER" %>` |
| `sym(name)` | Unicode symbol | `<%= sym :success %>` → ✓ |
| `csym(name)` | Colored symbol | `<%= csym :error %>` → red ✗ |
| `heading(text)` | Section heading | `<%= heading "Results" %>` |
| `muted(text)` | Gray/secondary | `<%= muted "optional info" %>` |
| `bold(text)` | Bold text | `<%= bold "important" %>` |
| `hr` | Horizontal rule | `<%= hr %>` |

**Colors:** `:success`, `:error`, `:warning`, `:info`, `:header`, `:muted`, `:emphasis`

**Symbols:** `:success` (✓), `:error` (✗), `:warning` (⚠), `:info` (ℹ), `:arrow` (→), `:bullet` (•), `:dot` (·)

Colors automatically respect `--no-color`. Symbols are always unicode (basic unicode works everywhere).

### Streaming Multiple Documents

For composed tools outputting multiple results:

```ruby
# YAML stream with proper separators
Devex::Output.yaml_stream([result1, result2, result3])
# Outputs: doc1, ---, doc2, ---, doc3, ...

# JSON Lines (one object per line)
Devex::Output.jsonl_stream([result1, result2, result3])
```

---

## Error Handling

### User Errors

```ruby
def run
  unless File.exist?(filename)
    Devex::Output.error("File not found: #{filename}")
    exit(1)
  end
end
```

### Structured Errors (Agent Mode)

The `Output.error` method automatically adapts to context.

### Exit Codes

- `0` - Success
- `1` - General error
- `2` - Usage/argument error

---

## Accessing CLI State

```ruby
def run
  cli.project_root      # Path to project root (where .devex.yml or .git is)
  cli.executable_name   # "dx"
end
```

---

## Invoking Other Tools

```ruby
def run
  # Run another tool programmatically
  run_tool("test")
  run_tool("lint", "--fix")
end
```

---

## Overriding Built-ins

Project tasks override built-ins of the same name:

```ruby
# tasks/version.rb - overrides built-in version command
desc "Custom version display"

def run
  # Your custom implementation

  # Optionally call the built-in:
  builtin.run if builtin
end
```

---

## Testing Considerations

### Debug Flags

For reproducing issues, users can force context detection:

```bash
dx --dx-agent-mode version      # Force agent mode
dx --dx-no-agent-mode version   # Force non-agent mode
dx --dx-env=production version  # Force environment
dx --dx-force-color version     # Force colors on
dx --dx-no-color version        # Force colors off
```

### Programmatic Overrides

In tests, use `Context.with_overrides`:

```ruby
Devex::Context.with_overrides(agent_mode: true, color: false) do
  # Test code here
end
```

---

## Complete Example

```ruby
# tasks/check.rb
desc "Run project health checks"

long_desc <<~DESC
  Runs various health checks on the project and reports status.
  Use --fix to automatically fix issues where possible.
DESC

flag :fix, "--fix", desc: "Automatically fix issues"
flag :strict, "--strict", desc: "Fail on warnings"

def run
  results = {
    checks: [],
    passed: 0,
    failed: 0,
    warnings: 0
  }

  # Run checks...
  results[:checks] << { name: "syntax", status: "passed" }
  results[:passed] += 1

  # Output based on format
  case output_format
  when :json, :yaml
    Devex::Output.data(results, format: output_format)
  else
    $stdout.print Devex.render_template("check_results", results)
  end

  # Exit code
  exit(1) if results[:failed] > 0
  exit(1) if strict && results[:warnings] > 0
end
```

```erb
<%# lib/devex/templates/check_results.erb %>
<%= heading "Health Check Results" %>

<% checks.each do |check| -%>
  <%= csym(check[:status] == "passed" ? :success : :error) %> <%= check[:name] %>
<% end -%>

<%= muted "#{passed} passed, #{failed} failed, #{warnings} warnings" %>
```

---

## Summary of Available Interfaces

| Interface | Purpose |
|-----------|---------|
| `Devex::Context.*` | Runtime detection (agent, CI, env, call tree) |
| `Devex::Output.*` | Styled output, structured data |
| `Devex.render_template(name, locals)` | Render ERB template |
| `output_format` | Effective format (:text, :json, :yaml) |
| `verbose?`, `quiet?` | Global verbosity flags |
| `cli.project_root` | Project root path |
| `run_tool(name, *args)` | Invoke another tool |
| `builtin` | Access overridden built-in |
| `options` | Tool-specific flag/arg values |
| `global_options` | Global flag values |
