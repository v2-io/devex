# Changelog

All notable changes to devex will be documented in this file.

## [0.3.9] - unreleased

### Added
- **Named version files.** A project with more than one version (a
  specification and its implementation, say) can name further version files
  in its dx config (`.dx.yml` or `.dx/config.yml`):

  ```yaml
  versions:
    spec: VERSION.SPEC
  ```

  and address one by putting the name first: `dx version spec`,
  `dx version spec bump pre`, `dx version spec set 2.0.0-beta.0`. Paths are
  relative to the project root; a named file may be a bare version file or
  Ruby source with a `VERSION = "…"` constant. `bump`, `set` and `help`
  cannot be used as names.
- The unnamed commands are unchanged and keep finding the default version
  file by convention. One addition: `dx version` in a project that has named
  versions but no default file lists the named versions, where it used to
  fall through to printing devex's own version.

### Fixed
- `dx version <unknown word>` is now an error (exit 1). It used to ignore
  the extra arguments and show the version, so a typo like
  `dx version bmup patch` looked like success.

## [0.3.8] - 2026-11-20

### Fixed
- **`dx version bump` / `dx version set` now write a bare `VERSION` file.**
  Previously only a Ruby `VERSION = "…"` constant was rewritten; for a bare
  file the command printed `old → new`, exited 0, and left the file
  unchanged.
- **A version command can no longer report a change it did not make.** The
  new file content is checked before anything is written; if it would not
  read back as the new version, nothing is written and the command exits 1.
- **`dx version bump` refuses versions that are not plain
  `MAJOR.MINOR.PATCH`** (exit 1, file untouched) instead of mangling them.
  `2.0.0.pre` used to "bump" to `2.0.1.0`, and `1.2` to `0.0.1`. What a
  bump should mean for a prerelease is a convention devex does not assume;
  use `dx version set`.
- **`dx version set` validates the whole string.** It accepts
  `MAJOR.MINOR.PATCH` with an optional prerelease tail in RubyGems style
  (`2.0.0.pre`) or SemVer style (`2.0.0-rc.1`, `+build`); `1.0.0garbage`
  used to pass.
- `test_stable_compact` no longer depends on `Hash#inspect`'s format, which
  changed in Ruby 3.4 (the test had been failing since).
- Rewriting a Ruby constant keeps the file's own quote style and spacing.

### Added
- **`dx version bump pre`** increments the counter of a prerelease version,
  in either spelling: `2.0.0-alpha.0` → `2.0.0-alpha.1`, `2.0.0.pre.1` →
  `2.0.0.pre.2`. Refused when the version has no trailing prerelease
  counter. Moving between stages, or releasing, is `dx version set`.

### Added (2026-05-19)
- **Actionable LoadError hint in `CLI#run`.** When a project tool's
  `require` fails AND the project has a Gemfile but no `.dx-use-local`
  marker (and we aren't already inside a delegated re-exec), the bare
  LoadError is surfaced AND a one-line actionable hint is appended
  pointing at the existing `.dx-use-local` delegation affordance
  (ADR-003). Purely additive: never swallows the underlying error,
  never changes exit codes for the non-matching case. Resolves the
  recurring confusion where a project tool that requires a bundle-only
  path-gem (e.g. relata's `tools/docs.rb` → `chiridion`) raised a raw
  12-line backtrace with no signal that the affordance exists.

## [0.3.5] - 2025-12-29

### Fixed
- **Version detection fallback**: `dx version` now searches effective working directory when no project markers found, handling pre-git-init projects
- **`--dx-from-dir` flag**: Now correctly affects project root discovery (was being ignored)
- **Subtool helper methods**: Nested tools (`tool "name" do...end`) can now access helper methods defined in parent file (fixes `dx version bump` which was broken)

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
