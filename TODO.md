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

### [ ] Wire up `.dx-use-local` delegation
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

### [ ] Add `prj.hooks` to CONVENTIONS
- For organized mode: `.dx/hooks/`
- File: `lib/devex/project_paths.rb`

### [ ] Add `prj.templates` to CONVENTIONS
- Simple mode: `templates/`
- Organized mode: `.dx/templates/`
- File: `lib/devex/project_paths.rb`

---

## Priority 4: ADR-001 External Commands (Deferred)

### [ ] dotenv loading
- Load `.env` files automatically before command execution
- ADR shows it in the environment stack: dotenv → mise → bundle → command
- Consider using simple parser vs dotenv gem dependency

### [ ] mise activation
- Activate mise versions before command execution
- Either shell out to `mise` or read `.mise.toml` directly

### [ ] Progressive Ctrl-C handling
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

### [ ] Update ADR status markers
- ADR-001: Draft → Accepted (core complete, some features deferred)
- ADR-002: Draft → Accepted (core complete, case transforms pending)
- ADR-003: Draft → Accepted (core complete, flags pending)

### [ ] Update developing-tools.md
- Remove references to dotenv/mise (not implemented yet)
- Or mark them as "coming soon"

---

## Test Coverage Gaps

| Area | Gap |
|------|-----|
| `exec.rb` | No tests for `tool`/`tool?` methods |
| `core_ext.rb` | No tests for case transforms (not implemented) |
| `cli.rb` | No tests for `--dx-from-dir` (not implemented) |
| `dirs.rb` | No tests for `.dx-use-local` delegation |

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

### Title Case Minor Words
```ruby
TITLE_CASE_MINOR = %w[
  a an the
  for and nor but or yet so
  at by in to of on up as
  is it if
].freeze
```
