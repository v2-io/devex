# ADR-001: External Command Execution

**Status:** Draft
**Date:** 2025-12-13
**Context:** Devex tools need to run external commands (shell commands, ruby scripts, bundler-managed tools)

## Summary

This ADR defines the interfaces and behavior for executing external commands from devex tools. The design aims for parity with toys-core's exec mixin while integrating with devex's context system (agent mode, verbosity, call tree).

---

## Motivation

Almost every useful devex tool needs to run external commands:
- `dx test` runs `bundle exec rake test` or `bundle exec rspec`
- `dx lint` runs `bundle exec rubocop`
- `dx format` runs `bundle exec rubocop -a`
- `dx gem build` runs `gem build`

We need a consistent, well-designed set of helpers that:
1. Handle common patterns (bundler, environment, working directory)
2. Integrate with devex's context system (agent mode, verbosity, call tree)
3. Provide good error handling and debugging experience
4. Are simple to use for common cases, flexible for complex ones
5. Support both foreground (blocking) and background (async) execution
6. Provide rich stream control (capture, redirect, tee)

---

## Core Execution Methods

### `exec` - Full-Featured Process Execution

The primary method for spawning processes with full control.

```ruby
# Simple foreground execution (blocks until complete)
result = exec("bundle", "install")

# Background execution (returns immediately)
controller = exec("npm", "run", "watch", background: true)
# ... do other work ...
result = controller.result  # wait for completion

# With block for Controller access
exec("long_command") do |controller|
  # Can interact with streams while running
  output = controller.capture_out
end
```

**Returns:**
- Foreground: `Result` object
- Background: `Controller` object
- With block: yields `Controller`, returns `Result`

### `sh` - Simple Shell Execution

Run a command, stream output, return Result object.

```ruby
sh "bundle", "install"
sh "rake", "test"
sh "make", "-j4", "all"

# Shell string (interpreted by shell)
sh "echo $HOME && ls -la", shell: true
```

**Behavior:**
- stdout/stderr flow through to terminal (or adapt in agent mode)
- Returns `Result` object (never raises on non-zero exit)
- Caller decides what to do with failures

```ruby
# Common pattern: exit on failure
sh("bundle", "install").exit_on_failure!

# Or check and handle
result = sh("rspec")
puts "Tests failed" if result.failed?
```

### `sh?` - Test Command Success

Run a command, return true/false based on exit code. Silent.

```ruby
if sh? "which", "rubocop"
  # rubocop is available
end

unless sh? "git", "diff", "--quiet"
  # there are uncommitted changes
end
```

**Behavior:**
- Output is discarded (equivalent to `>/dev/null 2>&1`)
- Returns `true` if exit code is 0, `false` otherwise
- Never raises

### `capture` - Run and Capture Output

Run a command, capture output, return result object.

```ruby
result = capture("git", "status", "--porcelain")
result.stdout       # String: captured stdout
result.stderr       # String: captured stderr
result.output       # String: combined stdout + stderr
result.success?     # Boolean: exit code == 0
result.exit_code    # Integer: raw exit code
```

**Behavior:**
- Output is captured, not displayed
- Does NOT raise on non-zero exit (caller checks `result.success?`)
- Returns `Result` object always

---

## Ruby-Specific Execution

### `exec_ruby` / `ruby` - Run Ruby Subprocess

Spawn a Ruby process with the current Ruby interpreter.

```ruby
# Run a Ruby script
exec_ruby "scripts/migrate.rb", "--verbose"

# Run Ruby code directly
exec_ruby "-e", "puts RUBY_VERSION"

# Capture Ruby output
version = capture_ruby("-e", "puts RUBY_VERSION").stdout.strip
```

**Behavior:**
- Uses same Ruby as devex is running under
- Properly handles `RUBYOPT` and other Ruby environment
- All standard options apply

### `exec_proc` - Fork and Execute Proc

Fork a process to execute a Ruby Proc. (Not available on JRuby or Windows.)

```ruby
exec_proc(-> { heavy_computation }) do |controller|
  # Parent continues while child computes
end
```

**Behavior:**
- Forks current process
- Child executes the Proc
- Full stream control available
- Raises `Devex::UnsupportedError` on platforms without fork

---

## Tool Invocation

### `exec_tool` - Run Another dx Tool

Run another devex tool, optionally in a subprocess.

```ruby
# Run in-process (shares context)
exec_tool "lint", "--fix"

# Run in subprocess (isolated)
exec_tool "test", subprocess: true do |controller|
  # Can capture output, etc.
end
```

**Behavior:**
- In-process: direct invocation, shared context
- Subprocess: forked execution, can capture output
- Propagates call tree automatically

### `capture_tool` - Capture Tool Output

```ruby
result = capture_tool("version")
puts result.stdout  # "1.2.3"
```

---

## Bundler/Ruby Environment

### Problem: Environment Pollution

When devex is run via `bundle exec dx`, the parent bundler sets environment variables that interfere with subprocesses:
- `RUBYOPT` - may include bundler setup
- `BUNDLE_*` - bundler configuration
- `GEM_HOME`, `GEM_PATH` - gem locations

### Solution: Environment Modes

```ruby
# Run through the PROJECT's bundler (most common for tools)
bundle_exec "rake", "test"
bundle_exec "rspec", "--format", "json"
```

**`bundle_exec` behavior:**
- Uses `Bundler.with_unbundled_env` to clear devex's bundler
- Then runs `bundle exec <command>` for the project's bundler
- Inherits project's Gemfile context

```ruby
# Run gem commands with clean environment
gem_exec "build", "myproject.gemspec"
gem_exec "install", "foo"
```

**`gem_exec` behavior:**
- Clears bundler environment
- Runs `gem <command>` with system gems visible
- Useful for gem building/installation

```ruby
# Run with completely clean Ruby environment
with_clean_env do
  sh "gem", "install", "foo"
  sh "ruby", "-e", "puts Gem.path"
end
```

**`with_clean_env` behavior:**
- Clears all bundler/ruby environment variables
- Subprocess sees system ruby/gems only
- Useful for: gem install, running system ruby, isolation

```ruby
# Run with the environment BEFORE bundler modified it
with_original_env do
  sh "some_system_tool"
end
```

**`with_original_env` behavior:**
- Restores environment to pre-bundler state
- Uses `Bundler.with_original_env` under the hood

```ruby
# Explicit environment manipulation
with_env(RAILS_ENV: "test", DATABASE_URL: "...") do
  sh "rake", "db:migrate"
end
```

---

## Stream Handling

### Stream Options

The `:in`, `:out`, `:err` options control stream behavior:

| Option | Description |
|--------|-------------|
| `:inherit` | Connect to parent process stream (default for foreground) |
| `:null` | Redirect to /dev/null (default for background) |
| `:close` | Close the stream entirely |
| `:capture` | Collect output in Result object |
| `:controller` | Access via Controller object |
| `IO` object | Redirect to existing IO |
| `StringIO` | Redirect to StringIO |
| `[:file, path, mode, perms]` | Read/write file |
| `[:string, "data"]` | Provide input string (`:in` only) |
| `[:child, :out]` | Merge stderr into stdout |
| `[:tee, dest1, dest2, ...]` | Duplicate to multiple destinations |

### Examples

```ruby
# Capture stdout, let stderr through
result = exec("cmd", out: :capture, err: :inherit)
puts result.captured_out

# Send input from string
exec("cat", in: [:string, "hello world"])

# Write output to file
exec("make", out: [:file, "build.log", "w"])

# Tee output to both terminal and file
exec("test", out: [:tee, :inherit, [:file, "test.log", "w"]])

# Merge stderr into stdout
exec("cmd", err: [:child, :out], out: :capture)
```

### Controller Stream Access

For background processes or block form:

```ruby
exec("cmd", background: true, out: :controller, err: :controller) do |ctrl|
  ctrl.out           # IO: read stdout
  ctrl.err           # IO: read stderr
  ctrl.in            # IO: write to stdin

  ctrl.capture_out   # String: read remaining stdout
  ctrl.capture_err   # String: read remaining stderr

  ctrl.redirect_out(file_io)  # Redirect remaining output
end
```

---

## Process Control

### Controller Object

For background processes or when using block form:

```ruby
controller = exec("server", background: true)

controller.pid          # Integer: process ID
controller.executing?   # Boolean: still running?
controller.name         # String: identifier

# Send signals
controller.kill(:TERM)  # or controller.signal(:TERM)
controller.kill(:INT)

# Wait for completion
result = controller.result              # Block until done
result = controller.result(timeout: 30) # With timeout

# Stream access (if configured)
controller.out          # IO for stdout
controller.err          # IO for stderr
controller.in           # IO for stdin
```

### Timeouts

```ruby
# Kill process after 30 seconds
result = exec("slow_command", timeout: 30)

# Check if timed out
if result.timed_out?
  puts "Command exceeded timeout"
end
```

### Signal Handling

```ruby
# Custom termination sequence
exec("cmd",
  timeout: 30,
  timeout_signal: :TERM,    # First signal
  timeout_grace: 5,         # Seconds before...
  timeout_kill: :KILL       # Final signal
)
```

### Progressive Interruption

When the user sends SIGINT (Ctrl-C) during a streaming command:

1. **First SIGINT**: Forward to child, continue waiting
2. **Second SIGINT**: Send SIGTERM to child, short grace period
3. **Third SIGINT**: Send SIGKILL, return immediately

```ruby
# Opt out of progressive handling
exec("cmd", forward_signals: false)
```

---

## Result Object

All execution methods return a `Result` object:

```ruby
class Devex::CommandResult
  # Command info
  attr_reader :command      # Array: ["bundle", "exec", "rake"]
  attr_reader :name         # String: identifier (if set)

  # Exit status
  attr_reader :exit_code    # Integer: 0-255 (nil if signaled/failed)
  attr_reader :signal_code  # Integer: signal number (nil if exited normally)
  attr_reader :status       # Process::Status object

  # Captured output (if configured)
  attr_reader :captured_out # String or nil
  attr_reader :captured_err # String or nil

  # Timing
  attr_reader :pid          # Integer: process ID
  attr_reader :duration     # Float: seconds

  # Status checks
  def success?              # exit_code == 0
  def error?                # exit_code != 0
  def signaled?             # Terminated by signal
  def failed?               # Process failed to start
  def timed_out?            # Killed due to timeout

  # Convenience
  def output                # captured_out + captured_err combined
  alias_method :stdout, :captured_out
  alias_method :stderr, :captured_err
end
```

### Error Handling

```ruby
# Check for startup failure
result = exec("nonexistent_command")
if result.failed?
  puts "Failed to start: #{result.exception}"
end

# Check for signal termination
if result.signaled?
  puts "Killed by signal #{result.signal_code}"
end
```

---

## Configuration and Defaults

### `configure_exec` - Set Default Options

Set default options for all subsequent exec calls within the tool:

```ruby
# In tool setup
configure_exec(
  env: { RAILS_ENV: "test" },
  chdir: cli.project_root,
  logger: Devex.logger,
  log_level: :debug
)

# Later calls inherit these defaults
sh "rake", "test"  # Uses RAILS_ENV=test, logs command
```

### Per-Call Options Override Defaults

```ruby
configure_exec(env: { FOO: "default" })
sh "cmd"                           # FOO=default
sh "cmd", env: { FOO: "override" } # FOO=override
```

---

## Logging Integration

```ruby
# Log executed commands
exec("bundle", "install",
  logger: Logger.new($stderr),
  log_level: :info,         # false to disable
  log_cmd: "Installing deps" # Custom log message
)
# Logs: "Installing deps: bundle install"

# Name for identification in logs and results
exec("npm", "run", "build", name: "frontend-build")
```

---

## Context Integration

### Automatic Context Propagation

When running subprocesses, devex automatically includes context in environment:

```ruby
# Subprocess receives:
DX_CALL_TREE=parent:child    # Task invocation chain
DX_AGENT_MODE=1              # If in agent mode
DX_ENV=production            # Current environment
DX_CI=1                      # If in CI
DX_VERBOSITY=2               # Current verbosity level
```

This allows:
- Nested `dx` invocations to know their call tree
- Child processes to detect agent mode
- Consistent environment across the tool chain

### Opting Out

```ruby
sh "command", propagate_context: false
```

### Verbosity Propagation

Helper to generate verbosity flags for subprocesses:

```ruby
# Pass current verbosity to subprocess
sh "dx", "test", *verbosity_flags
# If -vv was passed to parent: ["dx", "test", "-v", "-v"]

# Short form
sh "dx", "test", *verbosity_flags(short: true)
# Produces: ["-vv"] instead of ["-v", "-v"]
```

---

## Output Behavior

### Context-Aware Defaults

Output behavior adapts to runtime context:

| Context | Default Behavior |
|---------|------------------|
| Interactive terminal | Stream output in real-time |
| Agent mode | Capture output, include in structured response |
| Verbose (`-v`) | Print command before running |
| Debug (`-vvv`) | Print command, env, chdir, timing |
| Quiet (`-q`) | Suppress stdout unless error |
| CI | Stream output (CI systems capture it) |

### Verbose Mode Details

```ruby
# With -v (verbose)
sh "bundle", "exec", "rspec"
# Prints: $ bundle exec rspec
# Then streams output

# With -vvv (debug)
sh "bundle", "exec", "rspec", env: { RAILS_ENV: "test" }
# Prints:
#   $ bundle exec rspec
#   ENV: RAILS_ENV=test
#   DIR: /path/to/project
# Then streams output
# After completion:
#   Completed in 4.23s (exit 0)
```

---

## Error Handling Philosophy

### The Problem with Raising on Non-Zero Exit

Rake's `sh` raises `RuntimeError` when a subprocess returns non-zero. This pattern, while familiar, conflates two fundamentally different things:

1. **Subprocess communication** (expected): "The test suite found 3 failing tests" → exit code 1
2. **Code bugs** (unexpected): "NullPointerException in our Ruby code" → exception

When these are treated identically, problems emerge:

- **Misleading diagnostics**: A stack trace points to where `sh` was called, not where the actual failure occurred (which was in the subprocess, not our Ruby code)
- **Composability breaks**: RSpec's [`fail_on_error = false` doesn't work](https://github.com/rspec/rspec-core/issues/127) because `sh` raises before the option is checked
- **Semantic confusion**: CI systems see "rake aborted!" instead of "tests failed"
- **Recovery is awkward**: Must wrap every `sh` in begin/rescue to handle expected failures

### First Principles: What Should Each Mechanism Communicate?

| Mechanism | Should Indicate | Example |
|-----------|-----------------|---------|
| **Exception** | Bug in devex/tool code (unexpected) | `nil.foo`, missing file we should have created |
| **Exit code** | Subprocess result (expected) | Test failures, lint warnings, compilation errors |
| **Result object** | Structured outcome for inspection | stdout, stderr, timing, exit code |

A test suite returning exit code 1 is **not exceptional** - it's the designed communication channel. The test framework is correctly reporting "some tests failed." Treating this as a Ruby exception misrepresents the situation.

### The Result Object as a Monad

The `Result` object is effectively a Result monad (Success | Failure):

```ruby
result = capture("rspec")

# Pattern match on outcome
if result.success?
  # Success path
else
  # Failure path - but NOT a bug, just a failed subprocess
end
```

This provides:
- **Explicit handling**: Caller decides what to do with failures
- **No hidden control flow**: Unlike exceptions, no surprise stack unwinding
- **Composability**: Can chain, transform, aggregate results
- **Full information**: Exit code, signal, output all preserved

### Why `capture` Returns Result (vs toys-core returning String)

toys-core's `capture` returns just the stdout string. We return a full `Result` object because:

1. **Exit code matters**: `git status --porcelain` returns empty string for both "clean repo" (exit 0) and "not a git repo" (exit 128)
2. **Stderr is often important**: Warnings, progress, error details
3. **Consistent API**: All exec methods return the same type
4. **Chaining works**: `result.stdout` is trivial if you just want the string

```ruby
# toys-core pattern (loses information)
output = capture("git", "status")  # Just a string - what was the exit code?

# devex pattern (preserves everything)
result = capture("git", "status")
result.stdout      # The string
result.exit_code   # Did it succeed?
result.stderr      # Any warnings?
```

### Recommended Patterns

**Pattern 1: Check and decide**
```ruby
result = sh("rspec")
if result.failed?
  Output.error("Tests failed")
  exit(result.exit_code)
end
```

**Pattern 2: Exit immediately on failure**
```ruby
sh("bundle", "install").exit_on_failure!
# Equivalent to: exits with subprocess exit code if non-zero
```

**Pattern 3: Callback on completion**
```ruby
sh("long_build", result_callback: ->(r) {
  if r.success?
    Output.success("Build complete")
  else
    notify_slack("Build failed: #{r.stderr}")
  end
})
```

**Pattern 4: Chained operations (railway pattern)**
```ruby
# Stop at first failure
sh("lint").then { sh("test") }.then { sh("build") }.exit_on_failure!
```

**Pattern 5: Aggregate multiple results**
```ruby
results = ["lint", "test", "typecheck"].map { |cmd| sh(cmd) }
failures = results.reject(&:success?)
exit(1) if failures.any?
```

### When Exceptions ARE Appropriate

Exceptions should occur for actual bugs or truly unexpected conditions:

```ruby
# Good - truly unexpected
raise Devex::CommandError.new(result) if result.failed? && result.exit_code > 128

# Good - programmer error
raise ArgumentError, "command cannot be empty" if cmd.empty?

# Bad - expected subprocess failure
raise "Tests failed!" if result.exit_code == 1  # Don't do this
```

### The `result_callback` Option

For async workflows or consistent handling:

```ruby
# Define once, use everywhere
FAIL_FAST = ->(result) { exit(result.exit_code) if result.failed? }

sh("bundle", "install", result_callback: FAIL_FAST)
sh("rake", "test", result_callback: FAIL_FAST)
```

Or as a symbol referencing a method:

```ruby
def handle_result(result)
  if result.failed?
    Output.error("Command failed: #{result.command.join(' ')}")
    Output.indent(result.stderr, level: 1) if result.stderr
    exit(result.exit_code)
  end
end

sh("compile", result_callback: :handle_result)
```

### Exit Code Helpers

```ruby
# Exit the tool with the subprocess exit code
result.exit_on_failure!

# Exit if any result failed
exit_on_any_failure(result1, result2, result3)

# Conditional exit
exit_on_nonzero_status(result) unless ENV["IGNORE_FAILURES"]
```

### Exit Code Categories

For tools that want to propagate meaningful exit codes:

```ruby
module Devex::ExitCodes
  SUCCESS       = 0
  GENERAL_ERROR = 1
  USAGE_ERROR   = 2   # Invalid options, missing arguments

  # BSD sysexits.h conventions (optional, for precision)
  EX_USAGE      = 64  # Command line usage error
  EX_DATAERR    = 65  # Data format error
  EX_NOINPUT    = 66  # Cannot open input
  EX_SOFTWARE   = 70  # Internal software error
  EX_OSERR      = 71  # System error
  EX_TEMPFAIL   = 75  # Temporary failure
  EX_NOPERM     = 77  # Permission denied
  EX_CONFIG     = 78  # Configuration error

  # Signal termination
  SIGINT        = 130 # 128 + 2
  SIGTERM       = 143 # 128 + 15
end
```

### CommandError Class

For cases where you DO want to raise (e.g., in library code, or truly unexpected failures):

```ruby
class Devex::CommandError < Devex::Error
  attr_reader :command     # Array: the command that failed
  attr_reader :exit_code   # Integer: exit status
  attr_reader :signal_code # Integer: signal (if signaled)
  attr_reader :stderr      # String: captured stderr (if available)
  attr_reader :chdir       # String: working directory
  attr_reader :result      # Result: full result object

  def message
    if result.signaled?
      "Command killed by signal #{signal_code}: #{command.join(' ')}"
    else
      "Command failed (exit #{exit_code}): #{command.join(' ')}"
    end
  end
end

# Usage - explicit raise when you want exception semantics
result = sh("critical_operation")
raise Devex::CommandError.new(result) if result.failed?
```

---

## Working Directory

### Project Root Default

By default, commands run in `cli.project_root` (where `.devex.yml` or `.git` is).

### Explicit Directory

```ruby
# Inline option
sh "make", chdir: "subproject/"

# Block form
in_dir("subproject/") do
  sh "make"
  sh "make", "install"
end

# Assertion helper
ensure_project_root!  # Raises if not in project root
```

---

## Shell Interpretation

### Direct Execution (Default)

Arguments are passed directly to the kernel, no shell interpretation:

```ruby
sh "echo", "$HOME"
# Literally prints: $HOME (no expansion)
```

### Shell Execution

When you need shell features (pipes, redirects, globbing):

```ruby
sh "grep foo *.txt | wc -l", shell: true

# Or use explicit shell method
shell "grep foo *.txt | wc -l"
```

**Security Note:** Shell execution has security implications with untrusted input. Prefer direct execution where possible.

---

## Complete Options Reference

Options accepted by all exec methods:

```ruby
exec("command",
  # Process behavior
  background: false,          # Run asynchronously
  env: { KEY: "value" },      # Environment variables
  chdir: "/path",             # Working directory

  # Stream handling
  in: :inherit,               # stdin handling
  out: :inherit,              # stdout handling
  err: :inherit,              # stderr handling

  # Result handling
  result_callback: nil,       # Proc or Symbol called with Result on completion

  # Timeouts
  timeout: nil,               # Seconds before killing
  timeout_signal: :TERM,      # First signal on timeout
  timeout_grace: 5,           # Grace period before kill
  timeout_kill: :KILL,        # Final signal

  # Signals
  forward_signals: true,      # Forward SIGINT/SIGTERM to child

  # Logging
  logger: nil,                # Logger instance
  log_level: :info,           # Log level (false to disable)
  log_cmd: nil,               # Custom log message
  name: nil,                  # Identifier for logs/results

  # Context
  propagate_context: true,    # Include DX_* env vars

  # Process.spawn passthrough
  pgroup: nil,                # Process group
  umask: nil,                 # File creation mask
  close_others: true,         # Close non-redirected FDs
  unsetenv_others: false,     # Clear env except explicit vars
)
```

---

## Design Decisions

### Decision 1: Default Error Behavior

**Options:**
- A) Raise on failure (like Rake's `sh`)
- B) Return result, caller checks (functional/monad style)
- C) Configurable default

**Decision:** B - All methods return Result objects, never raise on non-zero exit.

**Rationale:** See "Error Handling Philosophy" section above. Subprocess exit codes are *expected communication*, not exceptional conditions. Raising conflates "subprocess reported failure" with "bug in our code," leading to misleading diagnostics, composability problems (see [RSpec fail_on_error issue](https://github.com/rspec/rspec-core/issues/127)), and awkward error recovery.

The Result object is a monad - callers explicitly handle success/failure. For the common "exit on failure" case, use `.exit_on_failure!`:

```ruby
sh("bundle", "install").exit_on_failure!  # Exit with subprocess exit code if failed
```

**Note:** This differs from both Rake (raises by default) and the original ADR draft. We believe this is the principled approach for a CLI tool.

### Decision 2: Bundler Strategy

**Options:**
- A) Always clean environment, require explicit `bundle_exec`
- B) Auto-detect if in bundler context, be smart
- C) Provide all options, no magic

**Decision:** C - Provide `bundle_exec`, `gem_exec`, `with_clean_env`, `with_original_env`. No magic auto-detection that could surprise users.

### Decision 3: Output in Agent Mode

**Options:**
- A) Always capture in agent mode, never stream
- B) Stream by default, agent captures the stream
- C) Configurable per-command

**Decision:** B - Stream by default. Agent tooling (Claude Code, etc.) already captures subprocess output. If a tool needs to include command output in its structured response, it can explicitly `capture`.

### Decision 4: Shell vs Direct Exec

**Options:**
- A) Always use shell (convenient but security risk)
- B) Always direct exec (safe but no shell features)
- C) Direct by default, `shell: true` option

**Decision:** C - Direct exec by default for safety. Explicit `shell: true` or `shell()` method when needed.

### Decision 5: Background Process API

**Options:**
- A) Simple spawn returning pid
- B) Controller object with rich API
- C) Both, with Controller as default

**Decision:** B - Controller object provides consistent API for stream access, signals, and result retrieval.

### Decision 6: toys-core Parity

**Decision:** Aim for full parity with toys-core's exec mixin capabilities. This includes:
- All stream handling options (capture, tee, file, etc.)
- Controller object for background processes
- Rich Result object with signal handling
- Ruby subprocess helpers
- Tool invocation helpers
- Configuration defaults

---

## Implementation Notes

### Ruby Facilities

- `Open3.capture3` - capture stdout, stderr, status
- `Open3.popen3` - streaming with full control
- `Process.spawn` - low-level process creation
- `Process.wait2` - wait with status
- `Process.kill` - send signals
- `Bundler.with_unbundled_env` - clean bundler environment
- `Bundler.with_original_env` - pre-bundler environment
- `IO.pipe` - create pipe pairs
- `IO.select` - multiplex IO

### Mixin Structure

```ruby
module Devex
  module Mixins
    module Exec
      def configure_exec(**opts)
        @exec_defaults = (@exec_defaults || {}).merge(opts)
      end

      def exec(*args, **opts, &block)
        # implementation
      end

      def sh(*args, **opts)
        # implementation
      end

      def capture(*args, **opts)
        # implementation
      end

      # ... etc
    end
  end
end
```

Included in `ExecutionContext` so all tools have access.

---

## Open Questions

1. **Should `bundle_exec` verify a Gemfile exists?** Or silently fail/warn if not in a bundler project?

2. **How to handle interactive commands?** (e.g., `git commit` opening an editor) - PTY allocation?

3. **Windows support scope?** Different shell escaping, no POSIX signals, no fork. Mark as unsupported for MVP?

4. **Should we support `:tee` to Logger?** Log output while also displaying it?

5. **Integration with structured output?** When a tool captures command output, how does it best integrate with `Output.data()`?

---

## Appendix: Comparison with Rake and toys-core

### Rake's Approach

**Key innovation:** Block-based opt-in to error handling.

```ruby
# Without block: raises RuntimeError on non-zero exit
sh "might_fail"  # Raises!

# With block: you handle the status
sh "might_fail" do |ok, status|
  puts "Exit code: #{status.exitstatus}"
end
```

**Pros:**
- Familiar pattern for Rubyists
- Fail-fast is the default (good for build scripts)

**Cons:**
- No block = exception (problematic for composability)
- [RSpec `fail_on_error` issue](https://github.com/rspec/rspec-core/issues/127) - `sh` raises before options are checked
- Returns exit code (Integer), not a rich result object
- Stack traces are misleading - point to `sh` call, not subprocess

**Also provides:**
- `ruby` helper for running Ruby scripts
- `safe_ln` with fallback to copy
- `:verbose` and `:noop` options

### toys-core's Approach

**Key innovation:** Rich Result object, Controller for background processes, comprehensive stream handling.

```ruby
# Returns Result object
result = exec(["git", "init"])
result.exit_code   # Integer
result.captured_out  # String (if captured)

# Or with exit_on_nonzero_status option
exec(["git", "init"], exit_on_nonzero_status: true)
```

**Pros:**
- Result object preserves all information
- Controller provides async process management
- Stream handling is very flexible (tee, capture, redirect)
- `:result_callback` for async handling

**Cons:**
- `capture` returns String, not Result (loses exit code!)
- `exit_on_nonzero_status` option calls `exit()` which is a bit hidden
- `sh` returns Integer (exit code), not Result

**Also provides:**
- `exec_ruby`, `exec_proc`, `exec_tool`
- `verbosity_flags` helper
- `configure_exec` for defaults

### devex's Approach (This ADR)

**Key innovation:** All methods return Result (monad pattern), explicit failure handling.

```ruby
# Returns Result object, never raises
result = sh("might_fail")
result.success?  # Check outcome
result.exit_on_failure!  # Explicit exit if failed

# Chaining with early exit
sh("lint").then { sh("test") }.exit_on_failure!
```

**Design principles:**
1. Subprocess exit codes are *expected communication*, not exceptions
2. All exec methods return the same Result type (consistency)
3. `capture` returns Result (not String) - exit code matters
4. Failure handling is always explicit - no hidden control flow
5. `.exit_on_failure!` for common pattern

**Also provides:**
- Everything from toys-core (Controller, streams, etc.)
- Context propagation (DX_* env vars)
- Devex output system integration
- `result_callback` for async handling

### Summary Table

| Feature | Rake | toys-core | devex |
|---------|------|-----------|-------|
| `sh` returns | Integer (exit code) | Integer (exit code) | Result |
| `capture` returns | N/A | String | Result |
| `exec` returns | N/A | Result | Result |
| Error handling | Raises by default | `:exit_on_nonzero_status` option | `.exit_on_failure!` method |
| Block gives | `ok, status` | Controller | Controller |
| Stream options | Basic | Comprehensive | Comprehensive |
| Background support | No | Yes (Controller) | Yes (Controller) |
| Ruby subprocess | `ruby` helper | `exec_ruby` | `exec_ruby` |
| Tool invocation | N/A | `exec_tool` | `exec_tool` |
| Verbosity flags | N/A | `verbosity_flags` | `verbosity_flags` |
| Result callback | N/A | Yes | Yes |
| Bundler handling | Manual | Manual | `bundle_exec`, `with_clean_env` |

---

## References

- Rake's `sh` implementation: https://github.com/ruby/rake/blob/master/lib/rake/file_utils.rb
- toys-core exec mixin: https://github.com/dazuma/toys/blob/main/toys-core/lib/toys/standard_mixins/exec.rb
- toys-core exec utils: https://github.com/dazuma/toys/blob/main/toys-core/lib/toys/utils/exec.rb
- Open3 documentation: https://ruby-doc.org/stdlib/libdoc/open3/rdoc/Open3.html
- Bundler environment methods: https://bundler.io/v2.4/man/bundle-exec.1.html
- BSD sysexits.h: https://man.freebsd.org/cgi/man.cgi?query=sysexits
- RSpec `fail_on_error` issue: https://github.com/rspec/rspec-core/issues/127
