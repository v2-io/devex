# devex Design Questions

## Architecture Decisions Needed

### 1. CLI Framework: toys-core or clean-room?

**Status:** Analysis complete - leaning toward clean-room

**toys-core stats:**
- 146 Ruby files, ~35k lines
- exec mixin alone: 850 lines (wraps another 1500 line utils class)
- DSL tool.rb: 1886 lines

**What archema actually uses from toys:**
- CLI + subcommand routing
- Tool loading from a directory (eval .rb files)
- DSL: `desc`, `long_desc`, `flag`, `optional_arg`, `required_arg`
- Nested `tool "name" do ... end` blocks
- Custom mixins (`mixin "name" do ... end`, `include "name"`)
- `cli.run()` to invoke other tools
- Help generation (`--help`)

**What archema DOESN'T use currently:**
- The `:exec` mixin functionality (uses plain `system()` instead!)
- Shell completion
- Complex acceptors/validators
- Settings system
- Templates
- Most middleware

**Clean-room estimate:**
- CLI + dispatch: ~100-150 lines
- Tool loading: ~50-100 lines
- DSL: ~200-300 lines
- Mixin support: ~50 lines
- Flag/arg parsing: ~200-400 lines (can leverage OptionParser stdlib)
- Help generation: ~100-200 lines
- **Total: ~700-1200 lines**

**Arguments for clean-room:**
- Zero external dependencies (important for a dev infrastructure gem)
- Exactly what we need, nothing more
- Fully understood, easy to modify
- We're already not using most of toys' functionality
- 35k lines of dependency for ~1k lines of actual use seems excessive

**Arguments for toys-core:**
- Already proven and battle-tested
- Handles edge cases we haven't thought of
- Community maintains it
- Less work upfront

**DECISION: Clean-room implementation**

Start with patterns proven in archema's `tasks/.index.rb`:
- Exec helpers: `bundle_exec`, `gem_exec`, `ruby_script`, `run_tests`
- Environment: `clear_ruby_env!`, `ensure_project_root!`
- Output: `header`, `success`, `error`, `warn`

Build sophistication (capture, background, etc.) only when real use cases demand it.
Zero dependencies. Full understanding. Exactly what we need.

### 2. What should `dx` provide out of the box?

**Candidates for built-in tasks:**
- `test` - Run test suite (minitest/rspec detection?)
- `lint` / `format` - RuboCop or similar
- `types` - Steep/RBS type checking
- `pre-commit` - Orchestrated checks before commit
- `version` - Version management (bump, set)
- `gem` - Gem building/installation

**Open questions:**
- Should these be opinionated (assume minitest, rubocop) or configurable?
- What's the minimum viable set?

### 3. Override/extension model

**Options:**
- Project tasks override built-in tasks of same name
- Built-in tasks are always there, project adds new ones
- Explicit namespacing (e.g., `dx builtin:test` vs `dx test`)

**Likely answer:** Project-local first, then gem defaults (like PATH resolution)

### 4. What happens to autopax's CLI?

**Options:**
- autopax keeps `bin/autopax` separate, uses devex for dev tasks only
- autopax becomes a devex plugin/extension
- autopax's user-facing commands stay separate, dev commands migrate to dx

**Likely answer:** Separate concerns - `autopax` is user-facing product CLI,
`dx` is developer tooling. They coexist.

### 5. Configuration

- Where does devex look for project config? `.devex.yml`? `devex.rb`?
- What's configurable? Task directory name, built-in task behavior, etc.

## Implementation Notes

(To be filled in as we learn more)
