# devex - Developer Experience CLI

## Vision

A lightweight, zero-dependency Ruby gem providing a `dx` command for common
development tasks. Projects can extend with local tasks. Clean-room
implementation inspired by toys-core patterns but without the 35k line
dependency.

## Requirements

### CLI Behavior

**R1: Flexible help invocation**

`help` anywhere in the command path (with or without dashes) triggers help for
that tool. Also `-h` and `-?` work as shorthand:

```
dx help                      == dx --help == dx -h == dx -?
dx help docs                 == dx docs --help == dx docs help == dx --help docs
dx help docs regenerate      == dx docs help regenerate
                             == dx docs regenerate help
                             == dx docs regenerate --help
                             == dx docs --help regenerate
                             == ...
```

The word `help` is extracted from wherever it appears, and `--help` is
effectively appended to the remaining command path.

**R2: Subcommand structure**

Tools can be nested arbitrarily:
- `dx test` - top-level tool
- `dx test integration` - subtool
- `dx version bump patch` - deeper nesting

**R3: Project-local tasks**

dx looks for project-specific tools in a configurable directory (default:
`tools/`). Project tools can add new commands or override built-in ones.

**Priority:** Project tasks win over built-ins of the same name. A project task
can call the built-in it overrides (like `super`):

```ruby
desc "Project-specific test runner"

def run
  # do project-specific setup
  builtin.run  # call the built-in test task
  # do project-specific teardown
end
```

**R4: Built-in common tasks**

The gem provides common development tasks out of the box:
- `test` - run test suite
- `lint` / `format` - code linting
- `types` - type checking (if project uses it)
- `pre-commit` - orchestrated checks
- `version` - version management
- `gem` - gem building

(Exact set TBD based on what's truly universal)

### DSL

**R5: Minimal, familiar DSL**

Task files use a simple DSL similar to toys:

```ruby
desc "Run the test suite"
flag :verbose, "-v", "--verbose", desc: "Verbose output"
flag :file, "-f FILE", desc: "Specific test file"
optional_arg :pattern, desc: "Test name pattern"

def run
  # implementation
end
```

**R6: Nested tool blocks**

```ruby
desc "Top-level tool"

def run
  # default behavior
end

tool "subtool" do
  desc "A subtool"

  def run
    # subtool behavior
  end
end
```

**R7: Mixins**

Reusable functionality via mixins:

```ruby
# Define a mixin (in .index.rb or similar)
mixin "project" do
  def project_root = ...
  def bundle_exec(*args) = ...
end

# Use in a tool
include "project"
```

### Exec Layer

**R8: Simple exec helpers**

Based on archema's proven patterns:
- `bundle_exec(*args)` - run through bundler
- `gem_exec(*args)` - run gem commands
- `run_tests(pattern, ...)` - test runner helper
- `clear_ruby_env!` - handle RUBYOPT pollution
- `ensure_project_root!` - directory management

**R9: Output helpers**

- `header(text)` - styled section header
- `success(text)` - green success message
- `error(text)` - red error message
- `warn(text)` - yellow warning

### Architecture

**R10: Zero external dependencies**

The core gem should have no runtime dependencies beyond Ruby stdlib.
OptionParser for flag parsing. No toys, thor, dry-cli, etc.

**R11: Single entry point**

`exe/dx` is the entry point. It:
1. Finds project root by walking up from cwd looking for (in order):
   - `.devex.yml` (config file, can specify custom tools dir)
   - `.git` (git repository root)
   - `tools/` directory
2. Loads built-in tools from gem
3. Loads project tools from `tools/` (or configured dir from `.devex.yml`)
4. Parses ARGV and dispatches

If no project root found, still runs with just built-in tasks.

**R12: Task file loading**

Task files are Ruby files that are `instance_eval`'d in a DSL context.
File structure maps to command structure:
- `tools/test.rb` → `dx test`
- `tools/version.rb` with nested `tool "bump"` → `dx version bump`

## Open Questions

- Should there be a `.devex.yml` config file? Or just conventions?
- How to handle task file naming collisions (built-in vs project)?
- Version flag: `-v` or `--version` at root level?

## Non-Goals

- Shell completion (maybe later)
- Complex process orchestration (background, stream teeing, etc.)
- Plugin system beyond local task files
- Anything that adds dependencies
