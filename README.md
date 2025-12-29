![Devex](devex-logo.jpg)

# Devex

A lightweight, zero-heavy-dependency Ruby CLI providing a unified `dx` command for common development tasks. Projects can extend with local tasks. Clean-room implementation inspired by toys-core patterns.

## Vision

- **Single entry point**: `dx` command for all dev tasks
- **Zero-dependency core**: Support library uses only Ruby stdlib
- **Project-local tools**: Override or extend built-ins with `tools/*.rb`
- **Agent-aware**: Automatically detects AI agent invocation and adapts output
- **Environment-aware**: Rails-style environment detection (dev/test/staging/prod)
- **Command execution**: Clean subprocess management with environment orchestration

## Installation

```bash
gem install devex
```

Or add to your Gemfile:

```ruby
gem "devex"
```

## Usage

```bash
# Show available commands
dx help

# Show/manage version
dx version
dx version bump patch
dx version set 2.0.0

# With JSON output (auto-detected in agent mode)
dx version --format=json
```

## Project-Local Tools

Create a `tools/` directory in your project root with Ruby files:

```ruby
# tools/build.rb
desc "Build and test the project"

long_desc <<~DESC
  Runs the full build pipeline: install dependencies, run tests,
  and optionally lint the code.
DESC

flag :skip_lint, "-s", "--skip-lint", desc: "Skip linting step"
flag :coverage, "-c", "--coverage", desc: "Run with code coverage"

include Devex::Exec

def run
  # Use `cmd` instead of `run` to avoid conflict with `def run`
  cmd("bundle", "install").exit_on_failure!

  # Access flags as methods (boolean flags default to false)
  env = coverage ? { "COVERAGE" => "1" } : {}
  cmd("bundle", "exec", "rake", "test", env: env).exit_on_failure!

  unless skip_lint
    cmd("bundle", "exec", "rubocop").exit_on_failure!
  end

  # Check global verbose flag
  puts "Build complete!" if verbose?
end
```

Then run:
```bash
dx build                    # Full build
dx build --skip-lint        # Skip linting
dx build --coverage         # With coverage
dx -v build                 # Verbose output
```

### Nested Tools

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
  def run
    # ...
  end
end
```

Access as: `dx db migrate`, `dx db seed`

## Command Execution

Tools have access to smart command execution that automatically handles your environment.
Use `cmd` (not `run`) inside tools to avoid shadowing the `def run` entry point:

```ruby
# tools/deploy.rb
desc "Deploy the application"

flag :skip_tests, "--skip-tests", desc: "Skip test suite"
flag :dry_run, "-n", "--dry-run", desc: "Show what would be done"

include Devex::Exec

def run
  # ─── Basic execution with exit_on_failure! ───
  cmd("bundle", "install").exit_on_failure!

  # ─── Boolean check: cmd? returns true/false ───
  unless skip_tests || cmd?("which", "rspec")
    cmd("rake", "test").exit_on_failure!
  end

  # ─── Capture output into result object ───
  result = capture("git", "rev-parse", "--short", "HEAD")
  commit = result.stdout.strip
  puts "Deploying commit #{commit}..."

  # ─── Chain sequential operations with .then ───
  cmd("docker", "build", "-t", "myapp:#{commit}", ".")
    .then { cmd("docker", "push", "myapp:#{commit}") }
    .exit_on_failure!

  # ─── Transform captured output with .map ───
  tag = capture("git", "describe", "--tags", "--abbrev=0")
          .map { |stdout| stdout.strip }

  # ─── Result object has rich info ───
  result = cmd("kubectl", "apply", "-f", "k8s/")
  if result.failed?
    $stderr.puts "Deploy failed (exit #{result.exit_code})"
    $stderr.puts result.stderr if result.stderr
    exit 1
  end

  puts "Deployed #{tag || commit} successfully!" if verbose?
end
```

### Execution Methods

| Method | Purpose | Returns |
|--------|---------|---------|
| `cmd(*args)` | Run command, stream output | `Result` |
| `cmd?(*args)` | Test if command succeeds | `Boolean` |
| `capture(*args)` | Run command, capture output | `Result` with `.stdout`, `.stderr` |
| `shell(string)` | Run shell command (pipes, globs) | `Result` |
| `shell?(string)` | Test if shell command succeeds | `Boolean` |
| `spawn(*args)` | Start background process | `Controller` |

### Result Object

```ruby
result = cmd("make", "test")

result.success?      # => true if exit code is 0
result.failed?       # => true if non-zero exit
result.exit_code     # => Integer exit code
result.stdout        # => captured stdout (if using capture)
result.stderr        # => captured stderr
result.stdout_lines  # => stdout split into lines
result.duration      # => execution time in seconds

# Chaining
result.exit_on_failure!           # Exit process if failed
result.then { cmd("next") }       # Chain if successful
result.map { |out| out.strip }    # Transform stdout
```

### Environment Wrappers

Commands are automatically wrapped based on your project:

| Wrapper | When Applied |
|---------|--------------|
| `mise exec --` | Auto if `.mise.toml` or `.tool-versions` exists |
| `bundle exec` | Auto if `Gemfile` exists and command looks like a gem |
| `dotenv` | Explicit opt-in only (`dotenv: true`) |

Control wrappers explicitly:

```ruby
cmd "rspec"                      # auto-detect mise + bundle
cmd "rspec", mise: false         # skip mise wrapping
cmd "rspec", bundle: false       # skip bundle exec
cmd "echo", "hi", raw: true      # skip all wrappers
cmd "rails", "s", dotenv: true   # enable dotenv loading
```

## Configuration

Create `.dx.yml` in your project root:

```yaml
# Custom tools directory (default: tools)
tools_dir: dev/tools
```

## Global Options

```bash
dx --help                    # Show help with global options
dx --dx-version              # Show devex gem version
dx -f json version           # Output in JSON format
dx --format=yaml version     # Output in YAML format
dx -v version                # Verbose mode
dx -q version                # Quiet mode
dx --no-color version        # Disable colors
dx --color=always version    # Force colors
```

## Environment Variables

- `DX_ENV` / `DEVEX_ENV` - Set environment (development, test, staging, production)
- `DX_AGENT_MODE=1` - Force agent mode (structured output, no colors)
- `DX_INTERACTIVE=1` - Force interactive mode
- `NO_COLOR=1` - Disable colored output
- `FORCE_COLOR=1` - Force colored output

## Debug Flags

Hidden flags for testing and bug reproduction (not shown in `--help`):

```bash
dx --dx-agent-mode version      # Force agent mode
dx --dx-no-agent-mode version   # Force interactive mode
dx --dx-env=production version  # Force environment
dx --dx-terminal version        # Force terminal detection
```

## Built-in Commands

**Testing & Quality**
- `dx test` - Run tests (auto-detects minitest/RSpec)
- `dx lint` - Run linter (auto-detects RuboCop/StandardRB)
- `dx lint --fix` - Auto-fix linter issues
- `dx format` - Auto-format code (alias for `dx lint --fix`)

**Version Management**
- `dx version` - Show project version
- `dx version bump <major|minor|patch>` - Bump semantic version
- `dx version set <version>` - Set explicit version

**Gem Packaging**
- `dx gem build` - Build the gem
- `dx gem install` - Build and install locally
- `dx gem clean` - Remove built gem files

More built-ins planned: `types`, `pre-commit`, `init`

## Building Custom CLIs with Devex::Core

Devex exposes its CLI framework for building your own command-line tools:

```ruby
require "devex/core"

config = Devex::Core::Configuration.new(
  executable_name: "mycli",
  flag_prefix: "mycli",              # --mycli-version, --mycli-agent-mode
  project_markers: %w[.mycli.yml .git Gemfile],
  env_prefix: "MYCLI"                # MYCLI_AGENT_MODE, MYCLI_ENV
)

cli = Devex::Core::CLI.new(config: config)
cli.load_tools("/path/to/tools")
exit cli.run(ARGV)
```

This gives you:
- Tool routing with nested subcommands
- Automatic help generation
- Agent mode detection (adapts output for AI agents)
- Environment detection (dev/test/staging/prod)
- Command execution with environment wrappers
- Project path conventions
- Zero-dependency support library (Path, ANSI, CoreExt)

See [docs/developing-tools.md](docs/developing-tools.md) for the full API.

## Development

```bash
bundle install
bundle exec rake test
bundle exec exe/dx --help
```

## Documentation

- **[Developing Tools](docs/developing-tools.md)** - How to create tools, available interfaces, best practices
- **[CHANGELOG](CHANGELOG.md)** - Version history and release notes

## License

MIT - see [LICENSE](LICENSE)
