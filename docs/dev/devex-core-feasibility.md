# Devex-Core Feasibility Analysis

*2024-12-14 - Initial investigation*
*2024-12-14 - **IMPLEMENTED** - See lib/devex/core.rb*

## Executive Summary

**Verdict: Highly feasible with minimal effort.**

**Status: COMPLETE** - The `Devex::Core` module is now available via `require "devex/core"`.

The devex architecture is already well-structured for extraction. There are no circular dependencies, the code is cleanly layered, and the coupling between "framework" and "application" concerns is remarkably loose. Extraction would require mostly parameterization of currently-hardcoded values, not structural changes.

## What Would "Devex-Core" Mean?

Similar to how `toys-core` provides the CLI framework while `toys` provides the actual commands and UX:

| toys-core                          | devex-core (proposed)                |
|------------------------------------|--------------------------------------|
| CLI dispatcher, tool resolution    | `CLI`, `Loader`, tool resolution     |
| Tool/Flag/Arg classes              | `Tool`, `Flag`, `Arg`, `DSL`         |
| Execution context                  | `ExecutionContext`, `Exec`, `Result` |
| Output/template helpers            | `Output`, `TemplateHelpers`, `ANSI`  |
| Context detection                  | `Context` (agent mode, CI, env)      |
| Not included: built-in tools       | Not included: `builtins/`            |

A consumer would use devex-core to build their own CLI tool (e.g., `mycli`) with their own commands, but benefit from all the infrastructure: tool DSL, help generation, context detection, exec helpers, etc.

## Current Architecture Assessment

### Dependency Layers (Clean!)

```
Layer 0: Ruby stdlib only
├── support/path.rb      (Pathname, FileUtils)
├── support/ansi.rb      (pure Ruby)
├── support/core_ext.rb  (Set from stdlib)
└── version.rb

Layer 1: Depends on Layer 0
├── context.rb           (standalone, uses ENV)
├── template_helpers.rb  (depends on ansi)
└── output.rb            (depends on context, ansi, ERB)

Layer 2: Execution framework
├── exec.rb              (Open3 from stdlib)
├── exec/result.rb       (pure Ruby)
└── exec/controller.rb   (process management)

Layer 3: CLI framework
├── tool.rb              (depends on exec, optparse)
├── dsl.rb               (depends on tool)
├── loader.rb            (depends on tool, dsl)
└── cli.rb               (depends on tool, loader, context, output)

Layer 4: Directory context
├── dirs.rb              (depends on path)
├── project_paths.rb     (depends on dirs, path)
└── working_dir.rb       (depends on dirs, path)

Application layer (NOT in core)
├── lib/devex.rb         (configuration, wiring)
├── builtins/            (actual commands)
└── exe/dx               (executable)
```

**No circular dependencies.** Load order is explicit in `lib/devex.rb`.

### What's Generic vs Application-Specific

| File / Module | Generic? | Notes |
|---------------|----------|-------|
| `support/*` | 100% | Zero-dependency utilities |
| `context.rb` | 100% | Runtime detection, no dx-isms |
| `output.rb` | 100% | Output helpers |
| `template_helpers.rb` | 100% | ERB helpers |
| `exec.rb`, `exec/*` | 100% | Command execution |
| `tool.rb` | 100% | Tool/command model |
| `dsl.rb` | 100% | DSL for declaring tools |
| `loader.rb` | 100% | Directory scanning |
| `cli.rb` | ~95% | Only `--dx-*` flag names are dx-specific |
| `dirs.rb` | ~90% | `PROJECT_MARKERS` constant is dx-specific |
| `project_paths.rb` | ~85% | `CONVENTIONS` hash is dx-specific |
| `working_dir.rb` | 100% | Generic context manager |
| `lib/devex.rb` | 0% | This IS the application wiring |
| `builtins/*` | 0% | These ARE the dx commands |

### Coupling Points (All Easily Parameterized)

1. **Project markers** (`Dirs::PROJECT_MARKERS`)
   - Currently: `.dx.yml`, `.dx`, `.git`, `Gemfile`, `Rakefile`
   - Solution: Make configurable via CLI constructor

2. **Path conventions** (`ProjectPaths::CONVENTIONS`)
   - Currently: Hardcoded hash of `lib`, `test`, `docs`, etc.
   - Solution: Accept as constructor argument or inherit + override

3. **Debug flag prefix** (`--dx-*`)
   - Currently: All hidden flags start with `--dx-`
   - Solution: Make prefix configurable (e.g., `--mycli-agent-mode`)

4. **Config file names** (`.dx.yml`, `.dx/config.yml`)
   - Currently: Hardcoded in `Devex.load_config`
   - Solution: Make configurable

5. **Template location** (`Devex.templates_path`)
   - Already abstracted, just needs to not assume "devex" directory

## Proposed Gem Structure

### Option A: Two Gems (Recommended)

```
devex-core/
├── lib/
│   ├── devex_core.rb           # Entry point
│   └── devex_core/
│       ├── version.rb
│       ├── context.rb
│       ├── output.rb
│       ├── template_helpers.rb
│       ├── exec.rb
│       ├── exec/
│       ├── tool.rb
│       ├── dsl.rb
│       ├── loader.rb
│       ├── cli.rb
│       ├── dirs.rb
│       ├── project_paths.rb
│       ├── working_dir.rb
│       └── support/
│           ├── path.rb
│           ├── ansi.rb
│           └── core_ext.rb

devex/                          # Depends on devex-core
├── lib/
│   ├── devex.rb
│   └── devex/
│       ├── version.rb
│       ├── builtins/
│       └── templates/
└── exe/dx
```

### Option B: Three Gems (Maximum Reuse)

```
devex-support/                  # Zero dependencies, broadly useful
├── lib/
│   └── devex_support/
│       ├── path.rb
│       ├── ansi.rb
│       └── core_ext.rb

devex-core/                     # Depends on devex-support
├── ...

devex/                          # Depends on devex-core
├── ...
```

Option B would let projects use just `devex-support` for Path/ANSI without the CLI framework.

### Option C: Single Gem with Load Paths

Keep one gem but allow partial requires:

```ruby
# Full dx CLI
require "devex"

# Just the framework (no builtins)
require "devex/core"

# Just support utilities
require "devex/support"
```

This is simpler but doesn't give version independence.

## Required Changes for Extraction

### High Priority (Core Framework)

1. **Parameterize CLI constructor**
   ```ruby
   CLI.new(
     executable_name: "mycli",
     flag_prefix: "mycli",          # for --mycli-agent-mode etc.
     project_markers: [...],
     config_files: [...],
     tools_dir_name: "commands"
   )
   ```

2. **Make ProjectPaths conventions injectable**
   ```ruby
   class MyProjectPaths < DevexCore::ProjectPaths
     CONVENTIONS = {
       # my custom conventions
     }.freeze
   end
   ```

3. **Module renaming**
   - `Devex::*` → `DevexCore::*` (or `DX::Core::*`)
   - Keep `Devex::*` as thin wrapper in the `devex` gem

### Medium Priority (Nice to Have)

4. **Extract error class**
   - Currently `Devex::Error` is in main module
   - Should be `DevexCore::Error`

5. **Template loading**
   - Make `templates_path` a configurable attribute
   - Allow multiple template search paths

6. **Documentation**
   - API docs for building custom CLIs
   - Migration guide for existing dx users (should be seamless)

### Low Priority (Future)

7. **Plugin architecture**
   - Allow registering custom DSL methods
   - Hook points for tool lifecycle

## Consumer Usage Example

```ruby
# mycli.gemspec
spec.add_dependency "devex-core", "~> 0.4"

# lib/mycli.rb
require "devex_core"

module MyCLI
  class CLI < DevexCore::CLI
    def initialize
      super(
        executable_name: "mycli",
        project_markers: %w[.mycli.yml .git Gemfile],
        tools_dir_name: "commands"
      )
    end
  end
end

# exe/mycli
#!/usr/bin/env ruby
require "mycli"

cli = MyCLI::CLI.new
cli.load_project_tools(MyCLI.find_project_root)
exit cli.run(ARGV)

# commands/deploy.rb (user's project)
desc "Deploy the application"
flag :env, "-e", "--env=ENV", default: "staging"

def run
  puts "Deploying to #{options[:env]}..."
end
```

## Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Breaking changes to devex users | Low | Thin wrapper maintains API |
| Maintenance burden of two gems | Medium | Core is stable; builtins change more |
| API surface area expansion | Medium | Keep core minimal, add via plugins |
| Version coordination | Low | Semantic versioning, careful deps |

## Recommendation

**Proceed with Option A (Two Gems)** for these reasons:

1. **Clean separation** - Framework vs application is already natural
2. **Low effort** - Mostly parameterization, not restructuring
3. **High value** - Other projects could build on solid CLI foundation
4. **Testing benefit** - Core can have its own focused test suite

### Suggested Timeline

1. **Phase 1**: Parameterize hardcoded values (can be done now, no gem split)
2. **Phase 2**: Extract to separate gem structure in monorepo
3. **Phase 3**: Publish as separate gems when API stabilizes

Phase 1 is valuable even without splitting - it makes the code more flexible and testable.

## Comparison with toys-core

For reference, toys-core (~35k LOC) provides:

| toys-core concept | devex-core equivalent | Notes |
|-------------------|----------------------|-------|
| `Toys::DSL::Tool` module | `Devex::DSL` module | Our DSL is simpler |
| `Toys::ToolDefinition` | `Devex::Tool` | Similar purpose |
| `Toys::CLI` | `Devex::CLI` | Similar but ours is lighter |
| `Toys::Context` | `Devex::ExecutionContext` | Runtime context |
| `Toys::Loader` | `Devex::Loader` | File discovery |
| `Toys::StandardMiddleware` | N/A | We don't have middleware yet |
| `Toys::StandardMixins` | `@mixins` in Loader | Similar concept |
| `Toys::Utils` namespace | `Devex::Support` | Utility classes |

**Key difference**: toys-core uses explicit lazy loading (`Utils` must be required manually). We currently load everything eagerly. Consider lazy loading for devex-core to minimize startup time for tools that don't need all features.

## Open Questions

1. **Naming**: `devex-core` vs `dx-core` vs `cli-builder`?
2. **Namespace**: `DevexCore` vs `DX::Core` vs `CLIBuilder`?
3. **Support gem**: Worth splitting out? (`devex-support`)
4. **tty-prompt dependency**: Keep or make optional?
5. **Lazy loading**: Worth implementing to reduce startup overhead?

---

*This document captures initial exploration. Update as decisions are made.*
