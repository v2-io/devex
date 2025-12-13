# ADR-003: Directory Context Model

**Status:** Draft
**Date:** 2025-12-13
**Related:** ADR-001 (External Command Execution)

## Summary

This ADR defines the directory context model for devex - how tools understand their location within a project and access conventional paths. The design prioritizes:

1. **Deterministic behavior** - Tools behave the same regardless of where `dx` was invoked
2. **Fail-fast with feedback** - Missing paths are configuration errors, not silent failures
3. **Immutable contexts** - Child tools can't corrupt parent state
4. **Convention over configuration** - Sensible defaults, explicit overrides

---

## Local dx Delegation

### The Problem

User has global `dx` installed, but project specifies a different version in its Gemfile:

```
Global dx: 1.5.0
Project Gemfile: gem "devex", "~> 2.0"
```

Running `dx test` would use the wrong version.

### Solution: `.dx-use-local`

Create an empty file `.dx-use-local` in project root to opt into delegation:

```bash
touch .dx-use-local
```

When present, global `dx` will:
1. Change to project root directory
2. Execute `bundle exec dx "$@"` (replacing itself)

### Implementation

```ruby
# Early in dx startup, after project root discovery
def maybe_delegate_to_local
  return if ENV['DX_DELEGATED']  # Prevent infinite loop

  use_local = project_dir / '.dx-use-local'
  return unless use_local.exist?

  ENV['DX_DELEGATED'] = '1'
  Dir.chdir(project_dir)
  exec 'bundle', 'exec', 'dx', *ARGV
end
```

### When to Use

- Project pins a specific devex version in Gemfile
- Team needs consistent dx behavior across machines
- Testing dx changes locally before release

### Files

```
project/
  .dx-use-local     # Empty file - triggers delegation
  .dx.yml           # or .dx/
  Gemfile           # gem "devex", "~> 2.0"
```

The file can be empty (presence is the signal) or could contain future configuration.

---

## Core Directories

### Immutable Global Context

These are set once at dx startup and never change:

```ruby
invoked_dir     # Where user actually ran `dx` (real cwd at startup)
dest_dir        # = invoked_dir, or --dx-from-dir override
project_dir     # Discovered project root (has .git, .devex.yml, etc.)
dx_src_dir      # Devex gem installation (for templates, builtins)
```

### The `--dx-from-dir` Flag

```bash
# Show in --help (not hidden)
dx --dx-from-dir=PATH command

# Use case: Agent working on project from temp directory
$ dx --dx-from-dir=/home/user/myproject test
```

This allows `dx` to operate on a project without being invoked from within it. Affects `dest_dir` and therefore `project_dir` discovery.

### Discovery Rules

```
dest_dir
  └── Look for .devex.yml, .git, Gemfile, etc.
      └── Found? → project_dir = that directory
      └── Not found? → Check parent directory
          └── Reached filesystem root? → FFF error
```

---

## Project Paths (`prj`)

Access conventional project locations via the `prj` object:

```ruby
prj.root        # Project root directory
prj.git         # .git/
prj.config      # .devex.yml
prj.tools       # tools/ (dx tool definitions)
prj.lib         # lib/
prj.src         # src/
prj.test        # test/ or spec/ (discovered)
prj.docs        # docs/
# ... etc
```

### All Conventional Paths

| Path | Convention(s) | Description |
|------|---------------|-------------|
| `prj.root` | (project root) | Base directory |
| `prj.git` | `.git` | Git repository |
| `prj.config` | `.dx.yml` or `.dx/config.yml` | Devex configuration |
| `prj.tools` | `tools` or `.dx/tools` | dx tool definitions |
| `prj.dx` | `.dx` | Organized mode directory (if exists) |
| `prj.lib` | `lib` | Library code |
| `prj.src` | `src` | Source code (if separate from lib) |
| `prj.bin` | `bin` | Development scripts (not installed) |
| `prj.exe` | `exe` | Gem executables (installed with gem) |
| `prj.test` | `test`, `spec`, `tests` | Unit/integration tests |
| `prj.features` | `features` | BDD/Cucumber features |
| `prj.property_tests` | `property_tests` | Property-based tests |
| `prj.simulations` | `simulations` | Simulation tests |
| `prj.spec_tests` | `specification_tests` | Specification tests |
| `prj.types` | `sig` | RBS type signatures |
| `prj.docs` | `docs`, `doc` | Documentation |
| `prj.system_docs` | `system_docs` | System documentation |
| `prj.version` | `VERSION`, `version.rb`, etc. | Version file (discovered) |
| `prj.gemfile` | `Gemfile` | Bundler config |
| `prj.gemspec` | `*.gemspec` | Gem specification |
| `prj.mise` | `.mise.toml`, `.tool-versions` | Version manager config |
| `prj.env` | `.env` | Environment variables |
| `prj.tmp` | `tmp` | Temporary files |
| `prj.log` | `log` | Log files |
| `prj.vendor` | `vendor` | Vendored dependencies |
| `prj.db` | `db` | Database files/migrations |
| `prj.config_dir` | `config` | Configuration files |
| `prj.scripts` | `scripts` | Standalone scripts |

### `bin` vs `exe` Clarification

These are **orthogonal directories** with different purposes:

| Directory | Purpose | Installed with gem? | Example contents |
|-----------|---------|---------------------|------------------|
| `bin/` | Development scripts | No | `bin/setup`, `bin/console`, `bin/ci` |
| `exe/` | Gem executables | Yes | `exe/mycommand` (becomes `$ mycommand`) |

A project may have both, either, or neither. They should not be conflated.

```ruby
# bin/ - for developers working on this project
prj.bin / "setup"      # bin/setup - run to set up dev environment
prj.bin / "console"    # bin/console - interactive REPL

# exe/ - for users who install this gem
prj.exe / "mytool"     # exe/mytool - becomes `mytool` command after gem install
```

### Lazy Discovery

Paths are resolved lazily on first access:

```ruby
# Not evaluated until accessed
prj.test  # Now discovers test/, spec/, or tests/
```

This allows:
- Projects to evolve structure without breaking dx
- Only accessed paths to require existence
- Fast startup (no full project scan)

### Fail-Fast with Feedback (FFF)

When an accessed path doesn't exist:

```ruby
prj.test["**/*_test.rb"]  # Access prj.test

# If no test directory found:
```

```
ERROR: Project test directory not found

  Looked for: test/, spec/, tests/
  Project root: /Users/joseph/src/myproject

  To configure a custom location, add to .devex.yml:
    paths:
      test: your/test/dir/

Exit code: 78 (EX_CONFIG)
```

**Not:** Silent nil. **Not:** Stack trace. **Clear, actionable feedback.**

### Configuration Override

In `.devex.yml`:

```yaml
paths:
  # Override conventions
  test: tests/unit/
  docs: documentation/
  tools: .dx/tools/

  # Add custom paths (accessible as prj.whatever)
  fixtures: test/fixtures/
  migrations: db/migrate/
  protos: proto/
```

---

## Working Directory

### The Problem

```ruby
# Parent tool
def run
  within "packages/web" do
    tool "test"  # What directory does child see?
  end
end
```

If child could modify the working directory, parent would be corrupted.

### Solution: Immutable Stack

`working_dir` is passed through the call tree but cannot be mutated:

```ruby
working_dir  # => /project (starts at project_dir)

within "packages/core" do
  working_dir  # => /project/packages/core

  tool "lint"  # Child inherits /project/packages/core

  within "src" do
    working_dir  # => /project/packages/core/src
  end

  working_dir  # => /project/packages/core (unchanged by nested block)
end

working_dir  # => /project (unchanged by within block)
```

### `within` Block

```ruby
within path do
  # working_dir is path (relative to current working_dir)
  # Commands run from here
  run "make"  # Runs in path
end
# working_dir restored (actually, never changed - new context was created)
```

Accepts:
- String: `within "subdir"`
- Path object: `within prj.test`
- Absolute path: `within Path["/tmp/build"]`

### Commands and Working Directory

All commands from ADR-001 use `working_dir`:

```ruby
within prj.packages / "web" do
  run "npm", "test"      # Runs from packages/web/
  capture "npm", "version"
  spawn "npm", "run", "dev"
end
```

The `chdir:` option overrides for a single command:

```ruby
run "make", chdir: "other/"  # Ignores working_dir for this command
```

### For Complete Reset

If a tool truly needs to operate from a different project:

```ruby
# This spawns a new dx process with different dest_dir
shell "dx --dx-from-dir=/other/project test"
```

This is the escape hatch for crossing project boundaries.

---

## XDG Base Directories

*Status: Open question - depth of integration TBD*

Standard locations for user-level devex data:

```ruby
xdg.config      # ~/.config/devex (or $XDG_CONFIG_HOME/devex)
xdg.data        # ~/.local/share/devex
xdg.cache       # ~/.cache/devex
xdg.state       # ~/.local/state/devex
```

Potential uses:
- Global devex configuration
- Cached data across projects
- Completion scripts
- Telemetry/history

**Decision deferred** - implement when needed, following XDG spec properly.

---

## API Summary

### Global (Immutable)

```ruby
invoked_dir     # Path - where dx was actually run
dest_dir        # Path - effective start (invoked_dir or --dx-from-dir)
project_dir     # Path - discovered project root
dx_src_dir      # Path - devex gem root
```

### Project Paths

```ruby
prj.root        # Path - project root
prj.{name}      # Path - conventional/configured location (lazy, FFF)
prj["pattern"]  # Array[Path] - glob from project root
```

### Working Directory

```ruby
working_dir     # Path - current effective directory

within path do
  # working_dir is now path
  # Restored after block (immutable)
end
```

### In Commands (ADR-001)

```ruby
run "cmd"                    # Runs from working_dir
run "cmd", chdir: "other/"   # Override for this command
```

---

## Implementation Notes

### Project Path Discovery

```ruby
class ProjectPaths
  CONVENTIONS = {
    git:            '.git',
    dx:             '.dx',  # Organized mode directory
    config:         :detect_config,  # Special: .dx.yml or .dx/config.yml
    tools:          :detect_tools,   # Special: tools/ or .dx/tools/
    lib:            'lib',
    src:            'src',
    bin:            'bin',
    exe:            'exe',
    test:           %w[test spec tests],
    features:       'features',
    property_tests: 'property_tests',
    simulations:    'simulations',
    spec_tests:     'specification_tests',
    types:          'sig',
    docs:           %w[docs doc documentation],
    system_docs:    'system_docs',
    version:        %w[VERSION lib/*/version.rb],  # Special discovery
    gemfile:        'Gemfile',
    gemspec:        '*.gemspec',  # Glob pattern
    mise:           %w[.mise.toml .tool-versions],
    env:            '.env',
    tmp:            'tmp',
    log:            'log',
    vendor:         'vendor',
    db:             'db',
    config_dir:     'config',
    scripts:        'scripts',
  }.freeze

  def organized_mode?
    @organized ||= (@root / '.dx').directory?
  end

  def method_missing(name, *)
    @cache[name] ||= resolve(name)
  end

  private

  def resolve(name)
    # Handle mode-dependent paths
    case CONVENTIONS[name]
    when :detect_config
      return detect_config
    when :detect_tools
      return detect_tools
    end
    return @root / @overrides[name] if @overrides[name]

    convention = CONVENTIONS[name] or return super

    case convention
    when Array
      found = convention.map { |p| @root / p }.find(&:exist?)
      found or fail_missing!(name, convention)
    when String
      if convention.include?('*')
        # Glob pattern
        matches = @root.glob(convention)
        matches.first or fail_missing!(name, convention)
      else
        path = @root / convention
        path.exist? ? path : fail_missing!(name, convention)
      end
    end
  end

  def fail_missing!(name, tried)
    # FFF error with actionable message
  end

  def detect_config
    dx_dir = @root / '.dx'
    dx_yml = @root / '.dx.yml'

    if dx_dir.exist? && dx_yml.exist?
      fail_config_conflict!(dx_dir, dx_yml)
    elsif dx_dir.exist?
      dx_dir / 'config.yml'
    else
      dx_yml  # May or may not exist
    end
  end

  def detect_tools
    if organized_mode?
      @root / '.dx' / 'tools'
    else
      @root / 'tools'
    end
  end

  def fail_config_conflict!(dx_dir, dx_yml)
    dx_dir_time = dx_dir.birthtime rescue dx_dir.mtime
    dx_yml_time = dx_yml.birthtime rescue dx_yml.mtime

    message = <<~ERR
      Conflicting dx configuration

        Found both:
          .dx.yml      (created: #{dx_yml_time.strftime('%Y-%m-%d %H:%M:%S')})
          .dx/         (created: #{dx_dir_time.strftime('%Y-%m-%d %H:%M:%S')})

        Please use one or the other:
          • Simple:    .dx.yml + tools/
          • Organized: .dx/config.yml + .dx/tools/

        To migrate from simple to organized:
          mkdir -p .dx
          mv .dx.yml .dx/config.yml
          mv tools/ .dx/tools/
    ERR

    Devex.fail! message, exit_code: 78
  end
end
```

### Execution Context

```ruby
class ExecutionContext
  attr_reader :working_dir

  def initialize(working_dir:)
    @working_dir = working_dir.freeze
  end

  def within(subdir)
    new_wd = case subdir
             when Path then subdir
             when String then working_dir / subdir
             else raise ArgumentError
             end

    child = self.class.new(working_dir: new_wd)
    yield child
  end
end
```

---

## Open Questions

1. **`working_dir` default**: Start at `project_dir` or `dest_dir`?
   - Recommendation: `project_dir` (deterministic)

2. **XDG integration**: Full spec compliance or just the basics?
   - Deferred until needed

3. **Custom path types**: Should `prj.custom_thing` work if defined in config?
   - Recommendation: Yes, extensible

4. **Path existence caching**: Cache discovery results? Invalidation?
   - Recommendation: Cache per-session, no invalidation needed

5. **`tasks` → `tools` rename**: More consistent with devex terminology?
   - See discussion below

---

## Decision: Configuration Layout

### Two Modes: Simple and Organized

**Simple mode** (most projects):
```
myproject/
  .dx.yml           # Configuration
  tools/            # Tool definitions
  lib/
  ...
```

**Organized mode** (complex projects):
```
myproject/
  .dx/
    config.yml      # Configuration
    tools/          # Tool definitions
    templates/      # Project templates
    hooks/          # Git hooks, etc.
  lib/
  ...
```

### Detection Rules

1. Look for `.dx/` directory
2. Look for `.dx.yml` file
3. If **both** exist → FFF error (configuration conflict)
4. If `.dx/` exists → organized mode
5. If `.dx.yml` exists → simple mode
6. If neither → simple mode defaults (no config, `tools/` if exists)

### Conflict Error

If both `.dx/` and `.dx.yml` exist:

```
ERROR: Conflicting dx configuration

  Found both:
    .dx.yml      (created: 2025-01-15 10:23:45)
    .dx/         (created: 2025-02-20 14:30:12)

  Please use one or the other:
    • Simple:    .dx.yml + tools/
    • Organized: .dx/config.yml + .dx/tools/

  To migrate from simple to organized:
    mkdir -p .dx
    mv .dx.yml .dx/config.yml
    mv tools/ .dx/tools/

Exit code: 78 (EX_CONFIG)
```

### Path Resolution

| Path | Simple mode | Organized mode |
|------|-------------|----------------|
| `prj.config` | `.dx.yml` | `.dx/config.yml` |
| `prj.tools` | `tools/` | `.dx/tools/` |
| `prj.templates` | N/A (or `templates/`) | `.dx/templates/` |
| `prj.hooks` | N/A | `.dx/hooks/` |

### Naming Rationale

**`tools/`** instead of `tasks/`:
- Consistent with "dx tool" terminology
- A tool definition lives in `tools/`
- Clearer mental model: you're building tools, not tasks

**`.dx/`** instead of `.devex/`:
- Shorter, matches the command name
- `.dx.yml` is easy to type
- Familiar pattern (`.git/`, `.github/`, `.vscode/`)

---

## References

- ADR-001: External Command Execution
- ADR-002: Support Library (Path class)
- XDG Base Directory Specification: https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html
- Bundler's `bin/` conventions: https://bundler.io/guides/creating_gem.html
