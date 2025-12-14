# Changelog

All notable changes to devex will be documented in this file.

## [0.3.4] - 2025-12-13

### Added
- `prj.linter` convention in ProjectPaths - finds .standard.yml or .rubocop.yml
- `Path#rm`, `Path#delete`, `Path#unlink` - delete a file
- `Path#rm_rf` - delete directory recursively

### Changed
- Built-ins now fully trust ProjectPaths fail-fast behavior - no more rescue/re-error patterns
- `dx lint` and `dx format` use `prj.linter` instead of manual detection
- `dx test` uses `prj.test`, `dx gem` uses `prj.gemspec` - all with clean fail-fast

## [0.3.3] - 2025-12-13

### Fixed
- **Built-in tools now run from project root** - `dx test`, `dx lint`, `dx format`, `dx gem` now properly discover project root via `Devex::Dirs.project_dir` and run commands from there, regardless of current directory
- Built-ins now use `ProjectPaths` (`prj.test`, `prj.gemspec`, etc.) for conventional path discovery instead of manual File.exist? checks

## [0.3.2] - 2025-12-13

### Fixed
- ExecutionContext now includes Devex::Exec automatically, so nested tools (inside `tool "name" do ... end` blocks) have access to `cmd`, `capture`, etc. without explicit include
- Moved exec.rb require before tool.rb to ensure proper load order

## [0.3.1] - 2025-12-13

### Added
- `--no-verbose` flag to reset verbosity level (useful in subtools)
- `--no-quiet` flag to unset quiet mode
- `default:` option for flags to specify non-nil defaults

### Changed
- Built-in tools (`test`, `lint`, `format`, `gem`) now use `Devex::Exec` module with `cmd` pattern
- `lint.rb` uses `capture()` with `.stdout_lines` for git diff (demonstrates capture API)
- `gem.rb` uses `.then { }` chaining for sequential build/install operations
- Documentation updated with comprehensive Exec examples showing result objects, chaining, capture

### Fixed
- Documentation examples now consistently use `cmd`/`cmd?` inside `def run` blocks

## [0.3.0] - 2025-12-13

### Added
- **Built-in `dx test`**: Auto-detects minitest or RSpec, runs with coverage flag
- **Built-in `dx lint`**: Auto-detects RuboCop or StandardRB, with `--fix` and `--diff` options
- **Built-in `dx format`**: Auto-formats code (equivalent to `dx lint --fix`)
- **Built-in `dx gem`**: Subcommands for `build`, `install`, and `clean`
- **`cmd` and `cmd?` aliases**: Use these in tools to avoid `def run` collision with `Devex::Exec.run`
- **Reserved flag validation**: Tools that define flags conflicting with global flags (`-v`, `-f`, `-q`, etc.) now fail fast with a helpful error message

### Fixed
- Boolean flags now default to `false` instead of `nil`, fixing method access in tools
- Fixed missing requires for `Devex::Exec`, `Devex::ProjectPaths`, and `Devex::WorkingDir` modules
- Tools can now use `run`, `capture`, `spawn`, and other Exec methods without errors

## [0.2.0] - 2025-12-13

### Added
- **Environment wrapper chain**: `[dotenv] [mise exec --] [bundle exec] command`
  - `mise` auto-detected from `.mise.toml` or `.tool-versions`
  - `bundle exec` auto-detected from `Gemfile` for gem commands
  - `dotenv` requires explicit opt-in (`dotenv: true`)
- **Auto-require for project lib/**: Tools can `require "myproject/foo"` without `require_relative`
- **String case transforms**: `snake_case`, `kebab_case`, `camel_case`, `pascal_case`, `title_case`, `scream_case`, `up_case`, `down_case` with aliases
- `--dx-from-dir` flag for operating on projects remotely
- `.dx-use-local` delegation for version consistency
- `prj.hooks` and `prj.templates` path conventions

### Changed
- ADRs updated from Draft to Accepted status

## [0.1.0] - 2025-12-13

### Added
- Initial release
- CLI framework with tool routing and nested subcommands
- Help system (`dx help`, `dx tool --help`, `dx tool help`)
- DSL for defining tools: `desc`, `long_desc`, `flag`, `required_arg`, `optional_arg`, `remaining_args`, `tool`
- Agent mode detection (non-tty, CI, explicit env var)
- Environment detection (development, test, staging, production)
- Output helpers with color support
- Built-in `dx version` command with bump support
- Support library: Path class, ANSI colors, core extensions
- Directory context: `Dirs`, `ProjectPaths`, `WorkingDir`
- Command execution: `run`, `capture`, `spawn`, `shell`, `ruby`, `tool`
- Result monad with `then`, `map`, `exit_on_failure!`
