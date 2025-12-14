# Devex TODO

This document tracks implementation gaps between the ADRs and actual code.
Updated: 2025-12-13

---

## Priority 1: Critical Gaps (Expected behavior not working)

### [x] Add tests for `tool` / `tool?` methods (DONE)
- `exec.rb` defines `tool` and `tool?` but no tests exercise them
- Need tests that verify call tree propagation (`DX_CALL_TREE`)
- File: `test/devex/exec_test.rb`

### [x] Implement `--dx-from-dir` flag (DONE)
- ADR-003 specifies this flag for agents to operate on projects remotely
- `Dirs.dest_dir=` method exists but cli.rb doesn't parse the flag
- Files: `lib/devex/cli.rb`, `exe/dx`

### [x] Wire up `.dx-use-local` delegation (DONE)
- `Dirs.maybe_delegate_to_local!` exists but is never called
- Should be called early in `exe/dx` after project discovery
- File: `exe/dx`

---

## Priority 2: ADR-002 Support Library Gaps

### [x] Implement string case transforms (DONE)
Primary methods (per ADR-002 update):
- `up_case` - ALL UPPER (aliases: upper, uppercase, caps)
- `down_case` - all lower (aliases: lower, lowercase)
- `title_case` - Title Case With Rules (aliases: titlecase)
- `snake_case` - snake_case (aliases: snakecase, var_case, varcase)
- `scream_case` - SCREAM_CASE (aliases: const_case, constcase)
- `kebab_case` - kebab-case (aliases: kebabcase)
- `camel_case` - camelCase (aliases: camelcase)
- `pascal_case` - PascalCase (aliases: pascalcase, mod_case, modcase)

Title case rules:
- Always capitalize first/last word
- Lowercase: a, an, the, for, and, nor, but, or, yet, so, at, by, in, to, of
- Capitalize after hyphens (unless minor word)

File: `lib/devex/support/core_ext.rb`

### [ ] Add Duration DSL (deferred - implement when needed)
```ruby
5.seconds   # => 5
2.minutes   # => 120
1.hour      # => 3600
3.days      # => 259200
```

### [ ] Add Byte Size DSL (deferred - implement when needed)
```ruby
5.kilobytes  # => 5120
1.megabyte   # => 1048576
```

---

## Priority 3: ADR-003 Directory Context Gaps

### [x] Add `prj.hooks` to CONVENTIONS (DONE)
- For organized mode: `.dx/hooks/`
- File: `lib/devex/project_paths.rb`

### [x] Add `prj.templates` to CONVENTIONS (DONE)
- Simple mode: `templates/`
- Organized mode: `.dx/templates/`
- File: `lib/devex/project_paths.rb`

---

## Priority 4: ADR-001 External Commands

### [x] dotenv wrapper (DONE)
- Wraps commands with `dotenv` CLI when `dotenv: true` option passed
- Explicit opt-in only (not automatic)
- File: `lib/devex/exec.rb`

### [x] mise wrapper (DONE)
- Auto-wraps commands with `mise exec --` when `.mise.toml` or `.tool-versions` exists
- Can force with `mise: true` or disable with `mise: false`
- File: `lib/devex/exec.rb`

### [ ] Progressive Ctrl-C handling (deferred)
- 1st Ctrl-C: Forward SIGINT to child, keep waiting
- 2nd Ctrl-C: Send SIGTERM, short grace period
- 3rd Ctrl-C: Send SIGKILL, return immediately

### [ ] Stream input options
- `[:string, "data"]` - Provide string as stdin
- `[:file, path]` - Redirect to/from file

### [ ] result_callback option
```ruby
run("build", result_callback: ->(r) { r.success? ? deploy : rollback })
```

---

## Documentation Updates Needed

### [x] Update ADR status markers (DONE)
- ADR-001: Draft → Accepted
- ADR-002: Draft → Accepted
- ADR-003: Draft → Accepted

### [x] Update developing-tools.md (DONE)
- Documented environment wrapper chain
- Added mise/dotenv options and examples

---

## Test Coverage Gaps

| Area | Status |
|------|--------|
| `exec.rb` | ✓ Tests for `tool`/`tool?` methods added |
| `exec.rb` | ✓ Tests for mise wrapper added |
| `exec.rb` | ✓ Tests for dotenv wrapper added |
| `core_ext.rb` | ✓ Tests for case transforms added |
| `cli.rb` | (parsing is tested indirectly) |
| `dirs.rb` | (delegation tested elsewhere) |

---

## Implementation Notes

### Case Transform Implementation Order
1. `snake_case` - foundation for others
2. `kebab_case` - uses snake_case
3. `scream_case` - uses snake_case
4. `pascal_case` - uses snake_case
5. `camel_case` - uses pascal_case
6. `title_case` - independent, complex rules
7. `up_case` / `down_case` - trivial wrappers
8. All aliases

### Title Case Minor Words (implemented)
```ruby
TITLE_CASE_MINOR = %w[
  a an the
  for and nor but or yet so
  at by in to of on up as
].freeze
```
Note: "is", "it", "if" are NOT minor words (verb, pronoun, conjunction respectively).

---

## Built-in Tools Priority List

### Priority 1: Daily Development (implement first)

| Tool | Purpose | Detection | Notes |
|------|---------|-----------|-------|
| `dx test` | Run test suite | minitest, rspec, test-unit | Most commonly needed |
| `dx lint` | Run linter | rubocop, standardrb | Code quality |

**dx test implementation:**
- Detect test framework: `test/` → minitest, `spec/` → rspec
- Detect runner: `Rakefile` with test task, or direct
- Options: `--watch`, `--fail-fast`, `--coverage`
- Pass-through args after `--`

**dx lint implementation:**
- Detect linter: `.rubocop.yml` → rubocop, `.standard.yml` → standardrb
- Options: `--fix` (autocorrect), `--diff` (changed files only)

### Priority 2: Development Workflow

| Tool | Purpose | Detection | Notes |
|------|---------|-----------|-------|
| `dx format` | Auto-fix formatting | rubocop, standardrb | May alias to `dx lint --fix` |
| `dx pre-commit` | Pre-commit checks | - | Orchestrates lint + test + types |
| `dx types` | Type checking | steep, sorbet | RBS/RBI support |

**dx pre-commit implementation:**
- Run in order: `lint`, `types` (if configured), `test`
- Fail fast by default
- Options: `--all` (ignore changed-files optimization)

### Priority 3: Project Management

| Tool | Purpose | Detection | Notes |
|------|---------|-----------|-------|
| `dx gem build` | Build gem | `.gemspec` | Package for release |
| `dx gem install` | Install locally | `.gemspec` | For testing |
| `dx init` | Initialize devex | - | Create `.dx.yml`, `tools/` |

**dx init implementation:**
- Create `.dx.yml` with sensible defaults
- Create `tools/` directory
- Optionally create sample tool

### Priority 4: Nice to Have

| Tool | Purpose | Notes |
|------|---------|-------|
| `dx docs` | Generate documentation | yard, rdoc |
| `dx release` | Release workflow | bump version, tag, push |
| `dx bench` | Run benchmarks | benchmark-ips |
| `dx console` | Interactive REPL | irb/pry with project loaded |
| `dx ci` | Full CI pipeline locally | Everything pre-commit does + more |

---

## Implementation Patterns for Built-ins

### Framework Detection Pattern
```ruby
def detect_test_framework
  return :rspec   if File.exist?("spec") || File.exist?(".rspec")
  return :minitest if File.exist?("test")
  nil
end
```

### Runner Selection Pattern
```ruby
def run_tests(framework)
  case framework
  when :rspec   then run "rspec"
  when :minitest then run "rake", "test"
  end
end
```

### Pass-through Args Pattern
```ruby
remaining_args :passthrough, desc: "Arguments passed to underlying tool"

def run
  run "rspec", *passthrough
end
```
