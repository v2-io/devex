# CLAUDE.md - Devex Architecture & Status Overview

This document provides context for AI agents working on devex. Read this first to understand the landscape.

**IMPORTANT:** Before working on devex, read [docs/developing-tools.md](docs/developing-tools.md) - the authoritative guide on creating tools, available interfaces, and best practices. **You must keep this document current as part of your work.** If you add, change, or remove interfaces, update developing-tools.md accordingly.

## What Is Devex?

Devex is a **lightweight Ruby CLI framework** providing a unified `dx` command for development tasks. Think of it as a simpler, cleaner alternative to toys-core (~35k lines) that we fully understand and control.

**Three purposes:**
1. **CLI framework** - Run dev tasks (`dx test`, `dx lint`, `dx version bump patch`)
2. **Project templating** - `dx config` for setting up new projects (planned)
3. **Conventions reference** - Embody best practices for CLI design and agent interaction

## Current State (v0.1.0)

### What Works

**Core CLI Framework** (~800 lines total in `lib/devex/`):
- `cli.rb` - Main dispatcher, help system, tool resolution
- `tool.rb` - Tool/command representation with flags, args, subtools
- `dsl.rb` - DSL for declaring tools
- `loader.rb` - Loads task files from disk
- `context.rb` - Runtime detection (terminal, agent, CI, environment, call tree)
- `output.rb` - Styled output helpers (colors via paint gem)

**Features working:**
- Command routing with arbitrary nesting (`dx version bump patch`)
- Help anywhere in command path (`dx help version`, `dx version --help`, `dx version help bump`)
- Task loading from `tasks/` directory
- DSL: `desc`, `long_desc`, `flag`, `required_arg`, `optional_arg`, `remaining_args`, nested `tool`
- Project tasks override built-ins (with `builtin.run` access to original)
- Agent mode detection (non-tty, merged streams, CI, explicit env var)
- Environment detection (dev/test/staging/prod, Rails-compatible)
- Task invocation call tree tracking
- Output helpers that adapt to context (colors in terminal, plain in agent mode)
- Global flags (`--format`, `-v`, `-q`, `--no-color`, `--dx-version`)
- Hidden debug flags for testing (`--dx-agent-mode`, `--dx-env=`, etc.)
- Context overrides via programmatic API and CLI flags

**Built-in commands:**
- `dx version` - Show project or devex version
- `dx version bump <major|minor|patch>` - Semantic version bumping
- `dx version set <version>` - Set explicit version

### What's Missing

**Immediate priorities:**
- Exec helpers mixin (`bundle_exec`, `sh`, `clear_ruby_env!`)

**Built-in tasks to implement:**
- `dx test` - Auto-detect and run test suite
- `dx lint` / `dx format` - RuboCop/StandardRB integration
- `dx types` - Steep/RBS type checking
- `dx pre-commit` - Orchestrated checks
- `dx gem` - Build/install gem
- `dx config` - Project setup wizard/questionnaire

**Advanced features (see OUTLINE.md):**
- Tab completion generation
- Middleware system
- Template system for generating tools
- Task dependencies (Rake-style, if needed)

## Global Flags

**Universal flags** (shown in help):
- `-f, --format=FORMAT` - Output format (text, json, yaml)
- `-v, --verbose` - Increase verbosity (stackable: -vvv)
- `-q, --quiet` - Suppress non-error output
- `--no-color` - Disable colored output
- `--color=MODE` - Color mode: auto, always, never
- `--dx-version` - Show devex gem version (not project version)

**Hidden debug flags** (not in help, for testing/reproduction):
- `--dx-agent-mode` / `--dx-no-agent-mode` - Force agent mode on/off
- `--dx-interactive` / `--dx-no-interactive` - Force interactive mode
- `--dx-terminal` / `--dx-no-terminal` - Force terminal detection
- `--dx-ci` / `--dx-no-ci` - Force CI detection
- `--dx-env=ENV` - Force environment (development, test, staging, production)
- `--dx-force-color` / `--dx-no-color` - Force color on/off

These are useful for reproducing issues: `dx --dx-no-agent-mode version` forces text output.

## Two Root Paths

Devex distinguishes between:

1. **Gem root** (`Devex.gem_root`) - Where devex itself lives
   - `lib/devex/` - Core code
   - `lib/devex/templates/` - ERB templates for output
   - `lib/devex/builtins/` - Built-in commands

2. **Project root** (`cli.project_root`) - The user's project
   - Detected by `.devex.yml`, `.git`, or `tasks/` directory
   - `tasks/` - User's custom commands

Templates are always loaded from the gem; tasks can be loaded from both.

## Key Files

```
lib/devex/
├── cli.rb          # Entry point, dispatch, global flags, help extraction
├── tool.rb         # Tool class, Flag, Arg, ExecutionContext
├── dsl.rb          # DSL and DSLContext for parsing task files
├── loader.rb       # Directory scanning, file loading
├── context.rb      # Runtime detection (IMPORTANT - read this)
├── output.rb       # Styled output with paint gem
├── templates/      # ERB templates for text output
│   └── debug.erb   # Debug command template
└── builtins/
    ├── .index.rb   # Root tool config
    ├── debug.rb    # Context debugging (hidden)
    └── version.rb  # Version management

docs/ref/           # CLI conventions reference (copied from sapientia)
├── agent-mode.md   # How to detect and behave for AI agents
├── cli-interface.md # Universal flags, exit codes
├── io-handling.md  # Stream usage, pipeline safety
├── error-handling.md
├── configuration.md
├── signals.md
├── design-philosophy.md
└── temporal-software-theory.md  # TST theorems for decision-making

test/
├── test_helper.rb
└── devex/
    ├── context_test.rb  # 42 tests for context detection
    └── output_test.rb   # Output helper tests
```

## Architecture Decisions

### Why Clean-Room Instead of toys-core?
- toys-core is 35k lines; we use maybe 1k lines of functionality
- Zero external dependencies in core (our goal)
- Full understanding and control
- See QUESTIONS.md for detailed analysis

### DSL Execution Model
Task files are evaluated **twice**:
1. **Parse time**: DSL methods (`desc`, `flag`, etc.) capture metadata into Tool objects
2. **Run time**: Source re-evaluated in ExecutionContext so `def run` has access to `cli`, `options`, etc.

This is why helper methods in task files work - they're re-defined at execution time.

### Context Detection Hierarchy
1. Programmatic overrides (for testing)
2. Explicit env vars (`DX_AGENT_MODE`, `DX_INTERACTIVE`)
3. CI detection (`CI`, `GITHUB_ACTIONS`, etc.)
4. Terminal auto-detection (`isatty`, streams merged)

See `lib/devex/context.rb` for full logic.

### Output Adaptation
- **Terminal**: Colors via paint gem, unicode symbols, progress indicators
- **Agent mode**: Plain ASCII, JSON structured output, no progress
- **Piped**: Clean stdout for pipelines, status to stderr

## Testing

```bash
bundle exec rake test  # Run all tests (59 tests currently)
```

Tests use:
- minitest + minitest-reporters
- climate_control for safe env var manipulation
- StringIO capture for output testing

## Dependencies

**Runtime** (declared in gemspec):
- `paint ~> 2.3` - Terminal colors (truecolor support)
- `tty-prompt ~> 0.23` - Interactive prompts (for dx config, etc.)

**Development**:
- minitest, minitest-reporters, climate_control, aruba, prop_check

## Key Concepts

### Agent Mode
Devex auto-detects when invoked by an AI agent and adapts:
- No colors, no progress indicators
- JSON output by default
- No interactive prompts (fail instead)
- Deterministic output ordering

Detection triggers: non-tty, merged streams, `DX_AGENT_MODE=1`, CI environment

### Environment (Rails-style)
```ruby
Devex::Context.env          # => "development"
Devex::Context.production?  # => false
Devex::Context.safe_env?    # => true (dev/test are safe)
```

Set via `DX_ENV`, `DEVEX_ENV`, `RAILS_ENV`, or `RACK_ENV`.

### Call Tree
Tasks can know if they were invoked from another task:
```ruby
Devex::Context.invoked_from_task?  # => true/false
Devex::Context.invoking_task       # => "pre-commit" (parent)
Devex::Context.call_tree           # => ["pre-commit", "test", "lint"]
```

Propagated to subprocesses via `DX_CALL_TREE` env var.

## Output Patterns

**Never use stacked `puts` calls.** Instead:

1. **Structured data (JSON/YAML)**: Use `Output.data(hash, format: fmt)`
2. **Text output**: Use ERB templates via `Devex.render_template("name", locals_hash)`
3. **Final output**: Single `$stdout.print rendered_text`

```ruby
# Good pattern for a command:
def run
  data = { name: "foo", count: 42 }

  case output_format
  when :json, :yaml
    Devex::Output.data(data, format: output_format)
  else
    $stdout.print Devex.render_template("my_template", data)
  end
end
```

Templates live in `lib/devex/templates/*.erb`.

### Template Helpers

Templates have access to color helpers that auto-respect `--no-color`:

```erb
<%= heading "Section Title" %>           <%# Styled heading with underline %>
<%= c :success, "green text" %>          <%# Named color %>
<%= c :bold, :white, "bold white" %>     <%# Multiple styles %>
<%= sym :success %>                      <%# ✓ or [OK] based on color %>
<%= csym :error %>                       <%# Colored symbol %>
<%= muted "secondary info" %>            <%# Gray text %>
<%= hr %>                                <%# Horizontal rule %>
```

Available colors: `:success`, `:error`, `:warning`, `:info`, `:header`, `:muted`, `:emphasis`

Symbols (always unicode - basic unicode works everywhere):
`:success` (✓), `:error` (✗), `:warning` (⚠), `:info` (ℹ), `:arrow` (→), `:bullet` (•), `:dot` (·)

Note: Only colors are stripped with `--no-color`, not symbols. Basic unicode like ✓ ✗ → works in all terminals and agent outputs. Avoid nerdfont glyphs or emoji that render as images.

## Common Tasks for Future Sessions

1. **Add a new built-in task**: See [docs/developing-tools.md](docs/developing-tools.md) for patterns
2. **Add exec helpers**: Create `lib/devex/mixins/exec.rb` with `bundle_exec`, `sh`, etc.
3. **Implement dx config**: Interactive questionnaire using tty-prompt
4. **Hide dx debug from help**: Currently visible, should be hidden

## Reference Documents

- **[docs/developing-tools.md](docs/developing-tools.md)** - Tool development guide (always current)
- **OUTLINE.md** - Comprehensive toys-core vs Rake feature comparison
- **MAP.md** - Original requirements and vision
- **QUESTIONS.md** - Architecture decisions and rationale
- **CHECKLIST.md** - Implementation checklist (incomplete)
- **docs/ref/*.md** - CLI conventions reference

## Philosophy

From the system prompt and temporal software theory:

> You are not optimizing for completing this task quickly—you are optimizing for the total time across all future agents who will work with what you create.

Devex code should be:
- **Comprehensible** - A fresh instance should understand quickly
- **Explicit** - Prefer clarity over cleverness
- **Well-commented** - Explain *why*, not *what*
- **Tested** - Every feature should have tests
- **Minimal** - Don't add features beyond what's needed

When in doubt: **is this worthy?** Not just "does it work?" but worthy of future beings who will depend on it.
