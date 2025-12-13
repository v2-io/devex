# ADR-001: External Command Execution

**Status:** Draft
**Date:** 2024-12-13
**Context:** Devex tools need to run external commands (shell commands, ruby scripts, bundler-managed tools)

## Summary

This ADR defines the interfaces and behavior for executing external commands from devex tools.

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

---

## Core Execution Patterns

### Pattern 1: `sh` - Run and Stream

Run a command, let output flow through to the terminal, raise on failure.

```ruby
sh "bundle", "install"
sh "rake", "test"
sh "make", "-j4", "all"
```

**Behavior:**
- stdout/stderr flow through to terminal (or captured in agent mode)
- Raises `Devex::CommandError` on non-zero exit
- Returns a result object on success

**Options:**
```ruby
sh "command",
  env: { KEY: "value" },     # Additional environment variables
  chdir: "/path",            # Working directory
  raise_on_error: true,      # Default: true. Set false to not raise
  output: :stream            # :stream (default), :capture, :null
```

### Pattern 2: `capture` - Run and Capture

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
- Returns result object always

**Options:**
```ruby
capture "command",
  env: { KEY: "value" },
  chdir: "/path",
  stdin: "input data",       # String to send to stdin
  timeout: 30                # Seconds before killing process
```

### Pattern 3: `sh?` - Run and Test

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
- Output is discarded (like `>/dev/null 2>&1`)
- Returns `true` if exit code is 0, `false` otherwise
- Never raises

---

## Bundler/Ruby Environment

### Problem: Environment Pollution

When devex is run via `bundle exec dx` (common), the parent bundler sets environment variables that can interfere with subprocesses:
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

## Output Behavior

### Context-Aware Defaults

Output behavior should adapt to runtime context:

| Context | Default Behavior |
|---------|------------------|
| Interactive terminal | Stream output in real-time |
| Agent mode | Capture output, include in structured response |
| Verbose (`-v`) | Print command before running |
| Quiet (`-q`) | Suppress stdout unless error |
| CI | Stream output (CI systems capture it) |

### Explicit Control

```ruby
# Always stream, even in agent mode
sh "make", output: :stream

# Always capture
sh "make", output: :capture

# Discard output
sh "make", output: :null

# Capture stderr separately
result = capture("cmd", stderr: :separate)
result.stdout  # just stdout
result.stderr  # just stderr
```

### Verbose Mode Integration

When `verbose?` is true (user passed `-v`):

```ruby
sh "bundle", "exec", "rspec"
# Prints: $ bundle exec rspec
# Then runs command
```

---

## Error Handling

### Default: Raise on Failure

```ruby
sh "false"
# Raises: Devex::CommandError: Command failed with exit code 1: false
```

**CommandError includes:**
- Command that was run
- Exit code
- stderr output (if captured)
- Working directory

### Opt-Out of Raising

```ruby
result = sh "might_fail", raise_on_error: false
if result.success?
  puts "worked"
else
  puts "failed with: #{result.exit_code}"
end
```

### Custom Error Handling

```ruby
begin
  sh "compile"
rescue Devex::CommandError => e
  case e.exit_code
  when 1
    # compilation error - show nice message
  when 2
    # missing dependency
  else
    raise  # re-raise unexpected errors
  end
end
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

# Ensure we're in project root (assertion)
ensure_project_root!
```

---

## Context Propagation

### Automatic Environment Variables

When running subprocesses, automatically include `Context.to_env`:

```ruby
# Subprocess receives:
DX_CALL_TREE=parent:child    # Task invocation chain
DX_AGENT_MODE=1              # If in agent mode
DX_ENV=production            # Current environment
DX_CI=1                      # If in CI
```

This allows:
- Nested `dx` invocations to know their call tree
- Child processes to detect agent mode
- Consistent environment across the tool chain

### Opting Out

```ruby
sh "command", propagate_context: false
```

---

## Process Control

### Timeouts

```ruby
# Kill process after 30 seconds
sh "slow_command", timeout: 30

# Capture with timeout
result = capture("slow", timeout: 10)
result.timed_out?  # => true if killed due to timeout
```

### Signals

```ruby
# Default: SIGTERM, then SIGKILL after grace period
sh "cmd", timeout: 30, kill_signal: :TERM, kill_grace: 5
```

### Background Execution (Future)

Not in initial implementation. Consider for v2:

```ruby
pid = spawn "long_running"
# ... do other work ...
wait pid
```

---

## Result Object

All execution methods return a result object:

```ruby
class Devex::CommandResult
  attr_reader :command      # Array: ["bundle", "exec", "rake"]
  attr_reader :exit_code    # Integer: 0-255
  attr_reader :stdout       # String or nil
  attr_reader :stderr       # String or nil
  attr_reader :pid          # Integer: process ID
  attr_reader :duration     # Float: seconds

  def success?              # exit_code == 0
  def failed?               # exit_code != 0
  def output                # stdout + stderr combined
  def timed_out?            # killed due to timeout
end
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
# Or explicitly:
shell "grep foo *.txt | wc -l"
```

**Caution:** Shell execution has security implications with untrusted input.

---

## Design Decisions

### Decision 1: Default Error Behavior

**Options:**
- A) Raise on failure (like Rake's `sh`)
- B) Return result, caller checks (functional style)
- C) Configurable default

**Recommendation:** A - Raise by default. Most tools want fail-fast behavior. Opt-out with `raise_on_error: false`.

### Decision 2: Bundler Strategy

**Options:**
- A) Always clean environment, require explicit `bundle_exec`
- B) Auto-detect if in bundler context, be smart
- C) Provide all options, no magic

**Recommendation:** C - Provide `bundle_exec`, `with_clean_env`, `with_original_env`. No magic auto-detection that could surprise users.

### Decision 3: Output in Agent Mode

**Options:**
- A) Always capture in agent mode, never stream
- B) Stream by default, agent captures the stream
- C) Configurable per-command

**Recommendation:** B - Stream by default. Agent tooling (Claude Code, etc.) already captures subprocess output. If a tool needs to include command output in its structured response, it can explicitly `capture`.

### Decision 4: Shell vs Direct Exec

**Options:**
- A) Always use shell (convenient but security risk)
- B) Always direct exec (safe but no shell features)
- C) Direct by default, `shell: true` option

**Recommendation:** C - Direct exec by default for safety. Explicit `shell: true` or `shell()` method when needed.

### Decision 5: Streaming with Callbacks

**Options:**
- A) Simple stream (output goes to terminal)
- B) Line-by-line callbacks for processing
- C) Both, callbacks are optional

**Recommendation:** A for MVP. Line-by-line processing can be added later if needed.

---

## Implementation Notes

### Ruby Facilities

- `Open3.capture3` - capture stdout, stderr, status
- `Open3.popen3` - streaming with full control
- `Process.spawn` - low-level process creation
- `Bundler.with_unbundled_env` - clean bundler environment
- `Bundler.with_original_env` - pre-bundler environment

### Error Class

```ruby
module Devex
  class CommandError < Error
    attr_reader :command, :exit_code, :stderr, :chdir

    def message
      "Command failed (exit #{exit_code}): #{command.join(' ')}"
    end
  end
end
```

### Mixin Structure

```ruby
module Devex
  module Mixins
    module Exec
      def sh(*args, **options)
        # implementation
      end

      def capture(*args, **options)
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

1. **Should `bundle_exec` verify a Gemfile exists?** Or silently fail if not in a bundler project?

2. **How to handle interactive commands?** (e.g., `git commit` opening an editor)

3. **Should we support Windows?** Different shell escaping, no POSIX signals, etc.

4. **PTY allocation?** Some commands behave differently without a PTY.

5. **Integration with `dx test` output parsing?** Should exec helpers understand test output formats?

---

## References

- Rake's `sh` implementation: https://github.com/ruby/rake/blob/master/lib/rake/file_utils.rb
- toys-core exec mixin: https://github.com/dazuma/toys/blob/main/toys-core/lib/toys/standard_mixins/exec.rb
- Open3 documentation: https://ruby-doc.org/stdlib/libdoc/open3/rdoc/Open3.html
- Bundler environment methods: https://bundler.io/v2.4/man/bundle-exec.1.html
