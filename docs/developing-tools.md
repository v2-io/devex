# Developing Tools for Devex

This guide covers how to create tools (commands) for devex, including all available interfaces, best practices, and patterns.

## Quick Start

Create a file in `tools/` (or `lib/devex/builtins/` for built-ins):

```ruby
# tools/hello.rb
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
# tools/db.rb
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

## External Command Execution

The `Devex::Exec` module provides methods for running external commands with automatic environment handling.

### Quick Reference

| Method | Purpose | stdout | Returns |
|--------|---------|--------|---------|
| `run(*cmd)` | Run command, wait | streams | `Result` |
| `run?(*cmd)` | Test if command succeeds | silent | `bool` |
| `capture(*cmd)` | Run and capture output | captured | `Result` |
| `spawn(*cmd)` | Run in background | configurable | `Controller` |
| `exec!(*cmd)` | Replace this process | N/A | never returns |
| `shell(str)` | Run via shell | streams | `Result` |
| `shell?(str)` | Test shell command | silent | `bool` |
| `ruby(*args)` | Run Ruby subprocess | streams | `Result` |
| `tool(name, *args)` | Run another dx tool | streams | `Result` |

### Basic Usage

```ruby
# In your tool's run method:
include Devex::Exec

def run
  # Run a command, streaming output
  run "bundle", "install"

  # Check if command succeeded
  result = run "make", "test"
  if result.failed?
    Output.error "Tests failed"
    exit result.exit_code
  end

  # Exit immediately on failure
  run("bundle", "install").exit_on_failure!

  # Chain commands (short-circuit on failure)
  run("lint").then { run("test") }.then { run("build") }.exit_on_failure!
end
```

### `run` - Run Command

The workhorse method. Runs a command, streams output, waits for completion.

```ruby
run "bundle", "install"

# With options
run "make", "test", env: { CI: "1" }, chdir: "subproject/"

# With timeout (seconds)
run "slow_task", timeout: 30
```

**Behavior:**
- Streams stdout/stderr to terminal
- Applies environment stack (cleans bundler pollution)
- Returns `Result` object
- Never raises on non-zero exit

### `run?` - Test Command Success

Silent execution, returns boolean. Perfect for conditionals.

```ruby
if run? "which", "rubocop"
  run "rubocop", "--autocorrect"
end

unless run? "git", "diff", "--quiet"
  Output.warn "Uncommitted changes"
end
```

### `capture` - Capture Output

When you need the output as a string.

```ruby
result = capture "git", "rev-parse", "HEAD"
commit = result.stdout.strip

result = capture "git", "status", "--porcelain"
if result.success? && result.stdout.empty?
  Output.success "Working directory clean"
end
```

### `spawn` - Background Execution

Start a process without waiting. Returns immediately with a Controller.

```ruby
# Start server in background
server = spawn "rails", "server", "-p", "3000"

# Do other work...
run "curl", "http://localhost:3000/health"

# Clean up
server.kill(:TERM)
result = server.result  # Wait for exit
```

### `exec!` - Replace Process

Replaces the current process. Use sparingly.

```ruby
exec! "vim", filename
# This line never executes
```

### `shell` / `shell?` - Shell Execution

When you need shell features (pipes, globs, variable expansion).

```ruby
# Pipes and variables
shell "grep TODO **/*.rb | wc -l"
shell "echo $HOME"

# Test with shell
if shell? "command -v docker"
  shell "docker compose up -d"
end
```

**Security note:** Never interpolate untrusted input into shell commands.

### `ruby` - Ruby Subprocess

Run Ruby with clean environment.

```ruby
ruby "-e", "puts RUBY_VERSION"
ruby "script.rb", "--verbose"
```

### `tool` - Run Another dx Tool

Invoke another devex tool programmatically.

```ruby
tool "lint", "--fix"

if tool?("test")
  tool "deploy"
end

# Capture tool output
result = tool "version", capture: true
```

Propagates call tree so child tool knows it was invoked from parent.

### The Result Object

All commands (except `run?`/`shell?`/`exec!`) return a `Result`:

```ruby
result = run "make", "test"

# Status
result.success?     # exit_code == 0
result.failed?      # exit_code != 0 or didn't start
result.signaled?    # killed by signal
result.timed_out?   # killed due to timeout

# Info
result.command      # ["make", "test"]
result.exit_code    # 0-255 or nil if signaled
result.pid          # Process ID
result.duration     # Seconds elapsed

# Output (if captured)
result.stdout       # String or nil
result.stderr       # String or nil
result.stdout_lines # Array of lines

# Monad operations
result.exit_on_failure!           # Exit process if failed
result.then { run("next") }       # Chain if successful
result.map { |out| out.strip }    # Transform stdout
```

### The Controller Object

`spawn` returns a `Controller` for managing background processes:

```ruby
ctrl = spawn "server"

ctrl.pid          # Process ID
ctrl.executing?   # Still running?
ctrl.elapsed      # Seconds since start

ctrl.kill(:TERM)  # Send signal
ctrl.terminate    # TERM + wait

ctrl.result       # Wait and get Result
ctrl.result(timeout: 30)  # With timeout
```

### Common Options

```ruby
run "command",
  env: { KEY: "value" },    # Additional environment variables
  chdir: "subdir/",         # Working directory
  timeout: 30,              # Seconds before killing
  raw: true,                # Skip environment stack
  bundle: false,            # Skip bundle exec wrapping
  clean_env: true           # Clean bundler pollution (default)
```

---

## Directory Context

Devex provides a rich directory context system for tools that need to work with project paths.

### Core Directories (`Devex::Dirs`)

```ruby
# Where dx was invoked from
Devex::Dirs.invoked_dir    # => Path

# The destination directory (usually same as invoked_dir)
Devex::Dirs.dest_dir       # => Path

# Project root (found by walking up looking for markers)
Devex::Dirs.project_dir    # => Path

# Where devex gem itself lives
Devex::Dirs.dx_src_dir     # => Path

# Is this inside a project?
Devex::Dirs.in_project?    # => true/false
```

Project markers searched (in order): `.dx.yml`, `.dx/`, `.git`, `Gemfile`, `Rakefile`

### Project Paths (`Devex::ProjectPaths`)

Lazy path resolution with fail-fast feedback:

```ruby
prj = Devex::ProjectPaths.new(root: Devex::Dirs.project_dir)

# Standard paths (raises if not found)
prj.root      # => /path/to/project
prj.lib       # => /path/to/project/lib
prj.src       # => /path/to/project/src
prj.bin       # => /path/to/project/bin
prj.exe       # => /path/to/project/exe

# Paths with alternatives (tries each in order)
prj.test      # => finds test/, spec/, or tests/
prj.docs      # => finds docs/ or doc/

# Glob from root
prj["*.rb"]           # => Array of Path objects
prj["lib/**/*.rb"]    # => Array of Path objects

# Config detection (simple vs organized mode)
prj.config    # => .dx.yml or .dx/config.yml
prj.tools     # => tools/ or .dx/tools/

# Version file detection
prj.version   # => VERSION, version.rb, or similar

# Check mode
prj.organized_mode?  # => true if .dx/ directory exists
```

### Working Directory Context

Immutable working directory for command execution:

```ruby
include Devex::WorkingDirMixin

def run
  # Current working directory
  working_dir  # => Path to current context

  # Execute block in different directory
  within "packages/core" do
    working_dir  # => /project/packages/core
    run "npm", "test"  # Runs from packages/core
  end

  working_dir  # => /project (unchanged)

  # Nest as deep as needed
  within "apps" do
    within "web" do
      run "yarn", "build"
    end
  end

  # Use with project paths
  within prj.test do
    run "rspec"
  end
end
```

The `within` block:
- Takes relative or absolute paths
- Restores directory on block exit (even if exception)
- Thread-safe via mutex
- Passes directory to spawned commands via `chdir:`

### The Path Class

All directory methods return `Devex::Support::Path` objects:

```ruby
path = Devex::Support::Path["/some/path"]
path = Devex::Support::Path.pwd

# Navigation (returns new Path, immutable)
path / "subdir"           # => Path to /some/path/subdir
path.parent               # => Path to /some
path.join("a", "b")       # => Path to /some/path/a/b

# Queries
path.exist?
path.file?
path.directory?
path.readable?
path.writable?
path.executable?
path.absolute?
path.relative?
path.empty?               # Empty file or empty directory

# File operations
path.read                 # => String contents
path.write("content")
path.append("more")
path.touch
path.mkdir
path.mkdir_p
path.rm
path.rm_rf
path.cp(dest)
path.mv(dest)

# Metadata
path.basename             # => "path"
path.extname              # => ".rb"
path.dirname              # => Path to parent
path.expand               # => Expanded Path
path.realpath             # => Resolved symlinks

# Enumeration
path.children             # => Array of Paths
path.glob("**/*.rb")      # => Array of Paths
path.find { |p| ... }     # Recursive find

# Conversion
path.to_s                 # => "/some/path"
path.to_str               # => "/some/path" (implicit)
```

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

### Command Execution Errors

Commands return `Result` objects instead of raising exceptions:

```ruby
result = run "might_fail"

if result.failed?
  if result.exception
    # Command failed to start (not found, permission denied)
    Output.error "Command failed to start: #{result.exception.message}"
  else
    # Command ran but returned non-zero
    Output.error "Command failed with exit code #{result.exit_code}"
  end
  exit 1
end
```

---

## Support Library

### Core Extensions (Refinements)

Enable Ruby refinements for cleaner code:

```ruby
using Devex::Support::CoreExt

# String
"hello".present?      # => true
"".blank?             # => true
"HELLO".underscore    # => "hello"
"hello".titleize      # => "Hello"

# Array/Hash
[].blank?             # => true
{ a: 1 }.present?     # => true

# Enumerable
[1, 2, 3].average     # => 2.0
[1, 2, 3].sum_by { |x| x * 2 }  # => 12

# Numeric
5.clamp(1, 3)         # => 3
5.positive?           # => true
```

Or load globally (for tools that prefer it):

```ruby
Devex::Support::Global.load!
```

### ANSI Colors

Direct access to terminal colors:

```ruby
Devex::Support::ANSI["Hello", :green]
Devex::Support::ANSI["Error", :red, :bold]
Devex::Support::ANSI["Text", :white, bg: :blue]

# Check if colors enabled
Devex::Support::ANSI.enabled?
Devex::Support::ANSI.disable!
Devex::Support::ANSI.enable!
```

---

## Accessing CLI State

```ruby
def run
  cli.project_root      # Path to project root (where .dx.yml or .git is)
  cli.executable_name   # "dx"
end
```

---

## Invoking Other Tools

```ruby
def run
  # Via the tool() method (recommended - tracks call tree)
  tool "test"
  tool "lint", "--fix"

  # Legacy method
  run_tool("test")
  run_tool("lint", "--fix")
end
```

---

## Overriding Built-ins

Project tasks override built-ins of the same name:

```ruby
# tools/version.rb - overrides built-in version command
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
# tools/check.rb
desc "Run project health checks"

long_desc <<~DESC
  Runs various health checks on the project and reports status.
  Use --fix to automatically fix issues where possible.
DESC

flag :fix, "--fix", desc: "Automatically fix issues"
flag :strict, "--strict", desc: "Fail on warnings"

include Devex::Exec
include Devex::WorkingDirMixin

def run
  results = {
    checks: [],
    passed: 0,
    failed: 0,
    warnings: 0
  }

  # Run tests
  within prj.test do
    result = capture "rspec", "--format", "json"
    if result.success?
      results[:passed] += 1
      results[:checks] << { name: "tests", status: "passed" }
    else
      results[:failed] += 1
      results[:checks] << { name: "tests", status: "failed" }
    end
  end

  # Run linter
  if run? "which", "rubocop"
    result = run "rubocop", *(fix ? ["--autocorrect"] : [])
    status = result.success? ? "passed" : "failed"
    results[:checks] << { name: "lint", status: status }
    result.success? ? results[:passed] += 1 : results[:failed] += 1
  end

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
| **Context** | |
| `Devex::Context.*` | Runtime detection (agent, CI, env, call tree) |
| `Devex::Dirs.*` | Core directories (invoked, project, dest) |
| `Devex::ProjectPaths` | Lazy project path resolution |
| `Devex::WorkingDirMixin` | Working directory context |
| **Execution** | |
| `Devex::Exec` | Command execution (run, capture, spawn, etc.) |
| `Devex::Exec::Result` | Command result with monad operations |
| `Devex::Exec::Controller` | Background process management |
| **Output** | |
| `Devex::Output.*` | Styled output, structured data |
| `Devex.render_template(name, locals)` | Render ERB template |
| **Support** | |
| `Devex::Support::Path` | Immutable path operations |
| `Devex::Support::ANSI` | Terminal colors |
| `Devex::Support::CoreExt` | Ruby refinements |
| **Tool Runtime** | |
| `output_format` | Effective format (:text, :json, :yaml) |
| `verbose?`, `quiet?` | Global verbosity flags |
| `cli.project_root` | Project root path |
| `tool(name, *args)` | Invoke another tool |
| `builtin` | Access overridden built-in |
| `options` | Tool-specific flag/arg values |
| `global_options` | Global flag values |
