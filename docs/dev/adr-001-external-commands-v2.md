# ADR-001: External Command Execution (v2)

**Status:** Draft
**Date:** 2025-12-13
**Supersedes:** adr-001-external-commands.md (original draft)

## Summary

This ADR defines the interfaces for executing external commands from devex tools. The design prioritizes:

1. **Ergonomic defaults** - Commands "just work" in the project's environment
2. **Principled naming** - Aligned with POSIX/Ruby semantics
3. **Explicit control** - Easy escape hatches when defaults don't fit
4. **Result-oriented** - All commands return inspectable Result objects

---

## Core Principle: The Environment Stack

The most valuable thing devex provides is **automatic environment orchestration**. When a tool runs a command, devex handles the wrapper stack:

```
dotenv → mise → bundle → command
```

This means `run "rspec"` in a dx tool automatically:
1. Loads `.env` if present
2. Activates mise (correct Ruby/Node/Python version)
3. Runs through `bundle exec` (correct gem versions)
4. Cleans `RUBYOPT`/`BUNDLE_*` from devex's own bundler context

**No more agent churning** trying to figure out why `rspec` can't be found or why Ruby is the wrong version.

---

## Command API

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

### `run` - Run Command

The workhorse. Runs a command, streams output, waits for completion.

```ruby
# Simple
run "bundle", "install"

# Check result
result = run "make", "test"
if result.failed?
  Output.error "Tests failed"
  exit result.exit_code
end

# Chain with early exit
run("lint").then { run("test") }.then { run("build") }.exit_on_failure!

# Common pattern: exit on failure
run("bundle", "install").exit_on_failure!
```

**Behavior:**
- Streams stdout/stderr to terminal (adapts in agent mode)
- Applies environment stack (dotenv → mise → bundle)
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

**Behavior:**
- Output discarded (like `>/dev/null 2>&1`)
- Returns `true` if exit code is 0, `false` otherwise
- Never raises

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

**Behavior:**
- stdout and stderr captured to strings
- Does not stream to terminal
- Returns `Result` with `.stdout`, `.stderr`

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

**Behavior:**
- Returns `Controller` immediately
- stdout/stderr go to `/dev/null` by default (configurable)
- Process runs independently
- Use `controller.result` to wait and get final `Result`

### `exec!` - Replace Process

Replaces the current process. Use sparingly.

```ruby
# Hand off to another program
exec! "vim", filename

# This line never executes
```

**Behavior:**
- Current process is replaced
- Never returns
- Bang (`!`) signals destructive/irreversible

### `shell` / `shell?` - Shell Execution

When you need shell features (pipes, globs, variable expansion).

```ruby
# Pipes, globs, variables
shell "grep TODO **/*.rb | wc -l"
shell "echo $HOME"
shell "cat file.txt | sort | uniq"

# Test with shell
if shell? "command -v docker"
  shell "docker compose up -d"
end
```

**Behavior:**
- Passed to `/bin/sh -c "..."`
- Shell interprets pipes, globs, variables
- **Security note:** Never interpolate untrusted input

### `ruby` - Ruby Subprocess

Run Ruby with the project's Ruby version, clean environment.

```ruby
ruby "-e", "puts RUBY_VERSION"
ruby "script.rb", "--verbose"
ruby "-r", "json", "-e", "puts JSON.pretty_generate(data)"
```

**Behavior:**
- Uses mise's Ruby version (if configured)
- Cleans `RUBYOPT` and bundler pollution
- Otherwise same as `run`

### `tool` - Run Another dx Tool

Invoke another devex tool programmatically.

```ruby
# Run lint tool
tool "lint", "--fix"

# Check if tests pass
if tool?("test")
  tool "deploy"
end

# Capture tool output
result = tool "version", capture: true
```

**Behavior:**
- Propagates call tree (`DX_CALL_TREE`)
- Child tool knows it was invoked from parent
- Inherits verbosity, format settings

---

## The Result Object

All commands (except `run?`/`shell?`/`exec!`) return a `Result`:

```ruby
class Result
  # Command info
  def command      # Array: ["bundle", "exec", "rspec"]
  def pid          # Integer: process ID
  def duration     # Float: seconds elapsed

  # Exit status
  def exit_code    # Integer: 0-255 (nil if signaled)
  def signal_code  # Integer: signal number (nil if exited normally)

  # Status predicates
  def success?     # exit_code == 0
  def failed?      # exit_code != 0 or didn't start
  def signaled?    # killed by signal
  def timed_out?   # killed due to timeout

  # Captured output (if applicable)
  def stdout       # String or nil
  def stderr       # String or nil
  def output       # Combined stdout + stderr

  # Monad operations
  def exit_on_failure!  # Exit process if failed
  def then(&block)      # Chain if successful
  def map(&block)       # Transform stdout if successful
end
```

### Why Result, Not Exceptions

A non-zero exit code is **expected communication**, not a bug:

```ruby
# "3 tests failed" is exit code 1 - not an exception
result = run "rspec"
if result.failed?
  Output.error "#{result.stdout.scan(/\d+ failures/).first}"
end
```

Exceptions are for **unexpected errors** (bugs in devex code). Exit codes are the **designed communication channel** for subprocesses.

See "Error Handling Philosophy" section for full rationale.

---

## The Controller Object

`spawn` returns a `Controller` for managing background processes:

```ruby
class Controller
  # Process info
  def pid          # Integer: available immediately
  def executing?   # Boolean: still running?
  def name         # String: identifier (if set)

  # Signals
  def kill(signal) # Send signal (:TERM, :INT, :KILL, etc.)

  # Streams (if configured)
  def stdin        # IO: write to process
  def stdout       # IO: read from process
  def stderr       # IO: read from process

  # Wait for completion
  def result                  # Block until done, return Result
  def result(timeout: 30)     # With timeout
end
```

---

## Environment Stack

### How It Works

When you call `run "rspec"`, devex builds a wrapper chain:

```ruby
# What you write:
run "rspec", "--format", "progress"

# What actually executes (conceptually):
with_dotenv do
  with_mise do
    with_bundle_exec do
      system("rspec", "--format", "progress")
    end
  end
end
```

### Stack Components

| Layer | Trigger | What it does |
|-------|---------|--------------|
| **dotenv** | `.env` exists | Loads environment variables |
| **mise** | `.mise.toml` or `.tool-versions` | Activates correct language versions |
| **bundle** | `Gemfile` + command is gem | Runs through `bundle exec` |
| **clean_ruby** | Always (for Ruby projects) | Clears `RUBYOPT`, `BUNDLE_*` from devex's context |

### Configuration

In `.dx.yml`:

```yaml
exec:
  # Control the stack (all default to auto-detect)
  dotenv: true              # Load .env files
  mise: true                # Use mise for version management
  bundle: auto              # auto | true | false

  # Custom wrapper (for direnv, nix, asdf, etc.)
  wrapper: "direnv exec ."

  # Default environment additions
  env:
    RAILS_ENV: test
```

### Opting Out

```ruby
# Skip entire stack (raw system call)
run "ls", "-la", raw: true

# Skip specific layers
run "node", "script.js", bundle: false
run "python", "script.py", mise: false

# Skip bundler cleanup (keep devex's bundler context)
run "gem", "list", clean_env: false
```

### Local dx Delegation

If a project has `.dx-use-local` file, the global `dx` will delegate to the project's bundled version via `bundle exec dx`. This ensures version consistency. See ADR-003 for details.

### The Bundler Problem

When devex is invoked via `bundle exec dx`, the parent bundler pollutes the environment:

```
BUNDLE_GEMFILE=/path/to/devex/Gemfile
BUNDLE_BIN_PATH=...
RUBYOPT=-rbundler/setup
GEM_HOME=...
GEM_PATH=...
```

This breaks child processes that need the **project's** bundler context, not devex's.

Solution: devex automatically uses `Bundler.with_unbundled_env` before running commands, then applies the project's bundler if needed.

---

## Common Options

All `run`-family methods accept these options:

```ruby
run "command",
  # Environment
  env: { KEY: "value" },    # Add environment variables
  chdir: "subdir/",         # Working directory

  # Stack control
  raw: false,               # Skip entire environment stack
  bundle: :auto,            # :auto, true, false
  mise: :auto,              # :auto, true, false
  dotenv: true,             # Load .env
  clean_env: true,          # Clean devex's bundler pollution

  # Streams
  out: :inherit,            # :inherit, :capture, :null, IO, [:file, path]
  err: :inherit,            # same options
  in: :inherit,             # :inherit, :null, :close, [:string, "data"]

  # Timing
  timeout: nil,             # Seconds before killing

  # Callbacks
  result_callback: nil      # Proc called with Result on completion
```

### Stream Options

| Value | Meaning |
|-------|---------|
| `:inherit` | Connect to parent's stream (default for foreground) |
| `:capture` | Collect in Result object |
| `:null` | Redirect to `/dev/null` (default for background) |
| `IO` | Redirect to IO object |
| `[:file, path]` | Redirect to file |
| `[:string, "data"]` | Provide as input (`:in` only) |
| `[:child, :out]` | Merge stderr into stdout (`:err` only) |

---

## Error Handling Philosophy

### The Problem with Raising

Rake's `sh` raises `RuntimeError` on non-zero exit. This conflates:

1. **Subprocess communication** (expected): "Tests found 3 failures" → exit 1
2. **Code bugs** (unexpected): `nil.foo` → NoMethodError

Problems with raising:
- Stack trace points to `sh` call, not the actual failure (which was in subprocess)
- Composability breaks (RSpec's `fail_on_error` issue)
- Recovery requires wrapping everything in `begin/rescue`

### Our Approach: Result Monad

All commands return `Result`. Caller decides what to do:

```ruby
# Pattern 1: Exit on failure (most common)
run("bundle", "install").exit_on_failure!

# Pattern 2: Check and handle
result = run("rspec")
if result.failed?
  notify_slack("Tests failed")
  exit 1
end

# Pattern 3: Chain operations
run("lint")
  .then { run("test") }
  .then { run("build") }
  .exit_on_failure!

# Pattern 4: Callback
run("build", result_callback: ->(r) {
  r.success? ? deploy : rollback
})
```

### When Exceptions ARE Appropriate

- Process failed to start (command not found)
- Invalid arguments to `run` itself
- Bugs in devex code

```ruby
# This might raise - command doesn't exist
result = run("nonexistent_command")
if result.failed? && result.exception
  # Failed to start, not a normal exit
end
```

---

## Timeouts and Signals

### Timeouts

```ruby
# Kill after 30 seconds
result = run "slow_command", timeout: 30

if result.timed_out?
  Output.warn "Command exceeded timeout"
end
```

### Signal Handling

For background processes:

```ruby
ctrl = spawn "server"

# Graceful shutdown
ctrl.kill(:TERM)

# Force kill
ctrl.kill(:KILL)

# Interrupt (like Ctrl-C)
ctrl.kill(:INT)
```

### Progressive Interruption

When user presses Ctrl-C during a streaming command:

1. **First Ctrl-C**: Forward SIGINT to child, keep waiting
2. **Second Ctrl-C**: Send SIGTERM, short grace period
3. **Third Ctrl-C**: Send SIGKILL, return immediately

---

## Naming Rationale

### Comparison with Prior Art

| devex | Ruby | POSIX | Rake | toys |
|-------|------|-------|------|------|
| `run` | `system` | `fork+exec+wait` | `sh` | `sh`, `exec` |
| `run?` | `system`+`$?` | same | — | — |
| `capture` | backticks | `popen` | backticks | `capture` |
| `spawn` | `spawn` | `fork+exec` | `spawn` | `exec(background:)` |
| `exec!` | `exec` | `execve` | `exec` | — |
| `shell` | `system(str)` | `system(3)` | `sh` | `sh` |

### Why These Names

**`run`** - Neutral, common verb. Doesn't imply shell (unlike `sh`) or process replacement (unlike `exec`).

**`run?`** - Ruby predicate convention. Clear that it returns boolean.

**`capture`** - Explicit intent: "I want the output."

**`spawn`** - Aligns with Ruby's `spawn` and POSIX `posix_spawn`. Non-blocking.

**`exec!`** - Bang indicates irreversible. Aligns with POSIX `exec` semantics.

**`shell`** - Explicit that shell interpretation happens. Not hidden behind an option.

**`ruby`** / **`tool`** - Self-explanatory domain-specific helpers.

---

## Implementation Notes

### Ruby Facilities

```ruby
# Core
Process.spawn    # Create child process
Process.wait2    # Wait and get status
Process.kill     # Send signals

# Open3 (for stream control)
Open3.popen3     # Full stream access
Open3.capture3   # Capture all streams

# Bundler
Bundler.with_unbundled_env  # Clean bundler pollution
```

### Mixin Structure

```ruby
module Devex
  module Exec
    def run(*cmd, **opts)
      # ...
    end

    def run?(*cmd, **opts)
      run(*cmd, **opts, out: :null, err: :null).success?
    end

    def capture(*cmd, **opts)
      run(*cmd, **opts, out: :capture, err: :capture)
    end

    def spawn(*cmd, **opts)
      run(*cmd, **opts, background: true)
    end

    # etc.
  end
end
```

---

## Open Questions

1. **mise detection**: Should we shell out to `mise` or read `.mise.toml` directly?

2. **dotenv loading**: Use `dotenv` gem or simple parser? Handle `.env.local`?

3. **Windows support**: Mark as unsupported for MVP? Different shell, no signals.

4. **PTY allocation**: Some commands behave differently without a TTY. Support `pty: true`?

5. **Streaming callbacks**: Support line-by-line processing of output?

---

## Appendix: Full Comparison Table

| Method | ADR v1 | Ruby/POSIX/toys | stdout | stderr | env | exit | pid |
|--------|--------|-----------------|--------|--------|-----|------|-----|
| `run` | `sh`/`exec` | `system`/`fork+exec+wait`/`sh` | inherit | inherit | stack | `Result` | `Result` |
| `run?` | `sh?` | `system`+`$?`/same/— | null | null | stack | `bool` | hidden |
| `capture` | `capture` | backticks/`popen`/`capture` | capture | capture | stack | `Result` | `Result` |
| `spawn` | `exec(bg:)` | `spawn`/`fork+exec`/`exec(bg:)` | null | null | stack | `Controller` | `Controller` |
| `exec!` | — | `exec`/`execve`/— | replaced | replaced | explicit | — | same |
| `shell` | `sh(shell:)` | `system(str)`/`system(3)`/`sh` | inherit | inherit | shell+stack | `Result` | `Result` |
| `shell?` | — | same/same/— | null | null | shell+stack | `bool` | hidden |
| `ruby` | `exec_ruby` | —/—/`ruby` | inherit | inherit | stack+clean | `Result` | `Result` |
| `tool` | `exec_tool` | —/—/`exec_tool` | inherit | inherit | stack+DX_* | `Result` | `Result` |

**Legend:**
- `stack` = dotenv → mise → bundle (auto-detected)
- `inherit` = passes through to parent
- `capture` = collected in Result
- `null` = discarded
- `Controller` = available immediately
- `Result` = available after completion

---

## References

- Original ADR: `docs/dev/adr-001-external-commands.md`
- Ruby Process docs: https://ruby-doc.org/core/Process.html
- Ruby Open3 docs: https://ruby-doc.org/stdlib/libdoc/open3/rdoc/Open3.html
- POSIX exec family: `man 3 exec`
- mise: https://mise.jdx.dev/
- Bundler environment: https://bundler.io/v2.4/man/bundle-exec.1.html
