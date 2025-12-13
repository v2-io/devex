# OUTLINE.md - Comprehensive Feature Analysis: Toys-Core vs Rake for Devex

## Executive Summary

This document provides a thorough analysis of toys-core (Ruby CLI framework) and Rake (Ruby build tool) to guide devex's feature roadmap. Both are mature, production-ready tools for CLI and automation tasks. Toys-core is optimized for modern CLI applications with Unix conventions, while Rake excels at file-based dependency management. Devex, as a lightweight zero-heavy-dependency CLI tool, should selectively adopt features from both, emphasizing simplicity and minimal dependencies.

---

## 1. TOYS-CORE FEATURE SET

### 1.1 Core Architecture

**Tools and Nested Structure**
- Single executable with multiple subcommands (like git, kubectl)
- Tools can be defined in `.toys.rb` files or `.toys/` directories
- Hierarchical tool organization with namespace support
- Supports colon or period as namespace delimiters

**Tool Discovery and Loading**
- Recursive directory hierarchy search for `.toys.rb` files
- Special `.toys/` directory structure support with:
  - `.preload.rb` or `.preload/` for preloading code
  - `.data/` directories for tool data files
  - `.lib/` directories automatically added to load path
- Programmatic configuration via `CLI.add_config_path()`
- Directory-scoped tool definitions similar to Rake's structure

**CLI Object**
- Central `Toys::CLI` object manages tool registration and execution
- Supports customization via constructor options
- Executes tools with full argument parsing and error handling

### 1.2 DSL and Tool Definition

**Core DSL Methods**
- `tool(name)` - Define a named tool
- `desc(description)` - Set tool descriptions for help
- `def run` - Implement tool functionality
- `flag(name, opts)` - Define command-line flags
- `optional_arg(name, opts)` - Optional positional arguments (alias: `optional`)
- `required_arg(name, opts)` - Required positional arguments (alias: `required`)
- `remaining_args(name, opts)` - Capture remaining arguments (alias: `remaining`)
- `include(mixin_name, opts)` - Include mixins
- `mixin(name) { ... }` - Define custom mixins
- `template(name) { ... }` - Define tool templates
- `subtool_middleware_stack` - Customize middleware for subtools

### 1.3 Flag and Argument Handling

**Acceptors**
- Validates and/or converts argument values
- Function-based acceptors for custom validation
- Range-based acceptors for numeric ranges
- Built-in acceptors provided by toys-core
- Accepts string parameter and returns converted object or raises exception
- Decoupled from tab completion (separate concern)

**Completions**
- Shell tab completion support for flag values
- Three completion strategies:
  - Static array of completion candidates
  - `:file_system` symbol for file path completion
  - Proc/lambda for dynamic completion generation
- Each flag can have independent completion configuration

**Flag Handlers**
- Optional handler proc for custom value processing
- Takes given value and previous value as arguments
- Predefined handlers:
  - `:set` (default) - Replace previous value
  - `:push` - Push onto array (multi-valued flags)
- Common pattern: combine `:push` handler with `default: []`

**Grouping and Organization**
- Flags can be organized into groups for help display
- Helps structure complex tools with many options

### 1.4 Built-In Mixins

**Standard Mixins** (part of toys-core and toys gem)

- **`:exec`** - Execute external commands and manage subprocesses
  - Methods for running shell commands
  - Stream capture and redirection
  - Process signaling and control
  - Exit status handling (`exit_on_nonzero_status` option)

- **`:fileutils`** - Ruby FileUtils library integration
  - File operations: `mkdir`, `cd`, `rm`, `cp`, etc.
  - Shorthand for `require "fileutils"; include ::FileUtils`

- **`:terminal`** - Terminal output and interaction
  - Styled output with color codes
  - User interaction: `ask`, spinners, other controls
  - Terminal capabilities detection

- **`:gems`** - Gem dependency management
  - Configurable missing gem and conflict handling
  - Automatic gem installation support
  - Note: Deprecated `suppress_confirm` and `default_confirm` options

- **`:highline`** - Advanced CLI interaction (requires highline gem 2.x+)
  - Integrates HighLine library for enhanced prompts
  - Automatic gem installation if missing
  - Mixin initializer for setup

- **`:bundler`** - Bundler integration
  - Automatic `Bundler.setup` on tool execution
  - Loads gems from Gemfile at runtime
  - Recommended pattern for tool dependencies

- **`:git`** - Git integration (via examples)
  - Works with `:exec` mixin for git commands
  - Can be used for repo initialization, commits, etc.

- **`:pager`** - Pager support
  - Automatically uses `less` for help display if available
  - Not a formal mixin but built-in feature

**Custom Mixins**
- Define custom mixins using `mixin` directive
- Modules can be mixed in with `include` directive
- Mixins can provide methods or invoke behavior
- Mixins can include initializers for setup code

### 1.5 Middleware and Interceptor System

**Middleware Architecture**
- Middleware classes customize base behavior for all tools
- Built-in middleware includes:
  - Help generation and display
  - `--help` flag support
  - `--verbose` and `--quiet` flags
  - Default descriptions
  - Error handling and reporting

**Middleware Features**
- `Toys::Middleware::Stack` represents middleware stack
- Distinguishes default vs. added middleware
- Middleware methods are optional (nop if not implemented)
- `Tool#subtool_middleware_stack` allows tool-specific overrides

**Customization**
- `Toys::CLI` constructor provides default middleware
- Can customize and replace entire middleware stack
- Custom middleware can be written for specialized behavior
- Useful for logging, metrics, error recovery, etc.

### 1.6 Help Generation and Customization

**Automatic Help System**
- Auto-generated help text from descriptions
- Tab completion generation
- Usage information automatically displayed
- Shell integration for completion

**Help Features**
- `desc` method provides help text
- Help shown with `--help` flag
- Help search functionality
- Tool discovery by name and description
- Pager support (less) for long help

**Customization Points**
- Middleware can customize help generation
- Show help middleware includes fallback execution
- Help formatting controlled by middleware

### 1.7 Templates System

**Purpose**
- Generate tools programmatically
- Reduce repetition in tool definitions
- Define reusable tool patterns

**Built-In Templates**
- `:rake` template - Reads Rakefile and generates Toys tools for Rake tasks
- Can convert Rake task ecosystem into Toys interface

**Template Definition**
- `template` directive for custom templates
- Templates receive parameters for configuration
- Can generate multiple tools from single template

### 1.8 Settings System

Research did not reveal extensive details about a dedicated "settings system" in toys-core. Configuration appears to be primarily through:
- Constructor options on `Toys::CLI`
- DSL directives in tool definitions
- Environment variables via `ENV`
- Mixin-specific configuration

### 1.9 CLI Structure and Execution

**Command Structure**
- Single entry point with subcommands
- Tools represent commands
- Can be deeply nested (tool.subtool.action)
- Similar to: `git`, `docker`, `kubectl`

**Execution Flow**
- CLI parses arguments
- Matches against defined tools
- Invokes tool with parsed arguments
- Returns exit code

**Context and API Access**
- Tools access context via block parameters
- `cli` method/key to access CLI object
- Can invoke other tools from within a tool
- Full access to Ruby runtime

### 1.10 Special Flags and Options

**Built-In Flags**
- `--help` - Show help for tool
- `--verbose` / `-v` - Verbose output
- `--quiet` / `-q` - Suppress output
- Standard Unix conventions

**Custom Flags**
- Any number of custom flags via DSL
- Support for flags with values (`--flag=value`)
- Support for boolean flags
- Support for multi-valued flags with `:push` handler

### 1.11 Zero-Dependency Philosophy

**Lightweight Implementation**
- `toys-core` has no dependency on rubygems
- Enables `ruby --disable=gems` execution
- Improves startup time
- Pure Ruby implementation where possible
- Optional mixins pull in dependencies (highline, bundler, etc.)

---

## 2. RAKE FEATURE SET

### 2.1 Core Architecture

**Task-Based Build System**
- Rakefile as main configuration (make-like)
- Tasks as core concept (vs. tools in toys-core)
- Task dependencies and prerequisites
- File-based dependency tracking

**File and Directory Organization**
- Primary file: `Rakefile` in project root
- Additional task files: `.rake` files
- Rails convention: `lib/tasks/*.rake` files
- `import` statement for including partial Rakefiles

**Namespace System**
- `namespace` blocks organize tasks
- Hierarchical task names: `namespace:task`
- Name resolution starts in current namespace, searches parents
- Implicit root namespace `^rake` for toplevel references
- File-based tasks are NOT scoped by namespace

### 2.2 Task DSL

**Core DSL Methods**
- `task(name, prerequisites)` - Define a basic task
- `desc(description)` - Describe next task
- `namespace(name)` - Create namespace
- `file(name, prerequisites)` - Define file-based task
- `directory(name)` - Create directory task
- `multitask(name, prerequisites)` - Parallel task execution
- `rule(pattern)` - Rule-based auto-tasks
- `import(files)` - Include other Rakefiles

**Task Definition**
- Task name as first argument
- Dependencies as second argument (symbol, string, or array)
- Block contains task actions
- Multiple definitions can add prerequisites and actions to same task

**Basic Example**
```ruby
task :hello do
  puts "Hello"
end

task :default => [:hello, :goodbye]
```

### 2.3 Task Dependencies and Prerequisites

**Dependency Specification**
- Prerequisites passed as symbol, string, or array
- Task waits for all prerequisites to complete
- `:default` task commonly used as entry point

**Dependency Execution**
- Each prerequisite task runs before dependent task
- Allows building task graphs
- Tasks can have multiple prerequisites

**Prerequisite Name Resolution**
- Lookup starts in current namespace
- Searches parent namespaces
- Special handling with `^` prefix for parent scope

**Phony Tasks**
- `phony` task type (via `require 'rake/phony'`)
- Allows file-based tasks to depend on non-file tasks
- Prevents rebuilds when dependencies haven't changed

### 2.4 Task Arguments

**Argument Declaration**
- Second parameter to `task` method as array: `task :name, [:arg1, :arg2]`
- Accessible via block parameter: `|task, args|`
- Values from command line: `rake name[value1,value2]`

**Hash-Based Declaration**
- Hash with arguments as key, prerequisites as value
- `task :build, [:release] => [:compile, :package]`
- Supports both arguments and prerequisites

**Argument Defaults**
- `args.with_defaults(key: 'default_value')`
- Provides defaults for unprovided arguments
- Useful for optional parameters

**Passing to Prerequisites**
- Arguments passed to prerequisite tasks
- Enables data flow through task chain

### 2.5 Invocation Tracking and Control

**Invocation State**
- `@already_invoked` flag on each task
- Tasks execute only once unless re-enabled
- Prevents redundant task execution

**Invocation Methods**

- **`invoke`** - Execute task if needed (respects already_invoked)
  - Prerequisite tasks invoked first
  - Task marked as invoked
  - Fails if task already invoked with exception

- **`execute`** - Execute task actions directly
  - Does not invoke prerequisites
  - Does not check already_invoked
  - Used for forced re-execution

**Re-enabling Tasks**
- `Rake::Task[name].reenable` - Reset invocation flag
- Sets `@already_invoked = false` and `@invocation_exception = nil`
- Allows task to be invoked again

**Programmatic Invocation**
- `Rake::Task[:task_name].invoke` in another task
- Direct task invocation with arguments
- Can set `Rake::Task[:name].reenable` to re-run

### 2.6 File Tasks and File Lists

**File Tasks**
- `file "target" => "source"` syntax
- Tracks file modification times
- Only rebuilds if source newer than target
- Supports glob patterns for prerequisites

**FileList**
- Array-like object for managing file lists
- Lazy evaluation of glob patterns
- Supports `each` iterator
- Built-in array operations (map, select, etc.)

**FileList Methods**
- `.exclude` / `.exclude?` - Filter files
- `.include` / `.include?` - Add to list
- `.pathmap(format)` - Transform file paths
- Pattern templates: `%x` (extension), `%X` (no extension), etc.
- Flexible file matching and transformation

**Pathmap System**
- Template-based path transformation
- Printf-style format specifiers
- `%x` = extension, `%X` = filename without extension
- `%d` = directory, `%f` = filename
- Powerful for build pipelines (source → compiled mappings)

### 2.7 Rule-Based Tasks

**Rule Definition**
- `rule(pattern)` defines transformation rules
- Pattern-based task generation
- Implicit task creation for matching files

**Pathmap in Rules**
- Pathmap format in rule dependencies (begins with `%`)
- Applied to target name to determine prerequisites
- Enables automatic dependency inference

**Use Cases**
- C compilation: `.o` from `.c` transformation
- Preprocessing: compiled files from source
- Code generation: generated files from templates

### 2.8 Task Organization (Namespaces and Directories)

**Namespaces**
- `namespace :name do ... end` - Organize related tasks
- Nested namespaces: `namespace :a { namespace :b { task :c } }`
- Accessed as: `rake a:b:c`

**Directory Tasks**
- `directory "path/to/dir"` - Create directory if missing
- Multiple directory calls create all needed paths
- Treated as file tasks (not affected by namespaces)

**Multi-Level Organization**
- Can nest namespaces arbitrary depth
- Mixed file and namespace tasks
- Parent namespace context available

### 2.9 Multitask (Parallel Execution)

**Parallel Prerequisites**
- `multitask :name => [:task1, :task2]`
- Prerequisites execute in parallel threads
- Each prerequisite in own Ruby thread

**Synchronization**
- Common prerequisites wait for completion
- All parallel tasks synchronize on common deps
- Shared prerequisites run only once

**Benefits**
- Faster overall execution on multi-core systems
- Useful for independent tasks (copy_src, copy_bin, copy_doc)
- Automatic thread safety for independent operations

### 2.10 Clean and Clobber Tasks

**Clean Task**
- `require 'rake/clean'`
- `CLEAN` FileList for files to remove on `rake clean`
- Default patterns: `**/*~`, `**/*.bak`, `**/core`
- Removes generated files that can be recreated

**Clobber Task**
- `CLOBBER` FileList for files to remove on `rake clobber`
- Depends on `clean` task
- Removes all generated and non-source files
- Returns project to pristine state

**Configuration**
```ruby
require 'rake/clean'
CLEAN.include('**/*.o', '**/*~')
CLOBBER.include('pkg/')
```

### 2.11 Packaging Tasks

**PackageTask**
- `Rake::PackageTask.new(name, version) { |pkg| ... }`
- Creates package files in multiple formats
- Automatically added to clobber target

**Supported Formats**
- Gzipped tar (if `need_tar_gz` = true)
- Bzip2'd tar (if `need_tar_bz2` = true)
- Plain tar (if `need_tar` = true)
- ZIP archive (if `need_zip` = true)

**Features**
- Delete package files
- Rebuild packages from scratch
- Useful for distribution packaging

**GemPackageTask** (Deprecated)
- Historically provided in rake
- Now handled by Gem package managers directly
- Removed from recent Rake versions

### 2.12 Test Tasks

**TestTask**
- `Rake::TestTask.new(name) { |t| ... }`
- Runs test suites defined in Rakefiles
- Integrates with various test frameworks

**Configuration Options**
- `t.libs` - Add to load path
- `t.warning` - Enable warnings
- `t.verbose` - Verbose output
- `t.test_files` - Test file patterns

**Test File Patterns**
- Default: `test/**/*_test.rb`
- Can be customized: `FileList['test/*_test.rb']`
- Framework-specific patterns (TestUnit, RSpec, etc.)

**Named Test Tasks**
- Multiple test tasks in different namespaces
- Example: `test:unit`, `test:integration`
- Each runs different test subset

**Historical Integration**
- RDocTask and GemPackageTask removed from Rake
- Now handled by respective libraries (RDoc, Gem)
- TestTask remains for test runner integration

### 2.13 Environment Variables and Configuration

**Passing Environment Variables**
- Command line: `rake VARIABLE=value task_name`
- Access in task: `ENV['VARIABLE']`
- Variables added to ENV object

**Rails-Specific Conventions**
- `RAILS_ENV` - Specify environment (development, test, production)
- Example: `rake RAILS_ENV=production db:migrate`

**The `:environment` Dependency**
- `task :name => :environment`
- Loads Rails application environment
- Enables access to models, helpers, database
- Omit for tasks that don't need full environment

**Programmatic Execution**
- `Rails.env = "production"` before task
- `Rake::Task[:name].invoke` to invoke programmatically
- `Rake::Task[:name].reenable` to re-run

**Environment Detection Issues**
- Switching between environments (dev → test) can cause issues
- Rails.env and DatabaseTasks.env may not sync
- Dotenv initialization may fail without explicit RAILS_ENV

### 2.14 Import and Inclusion

**Import Statement**
- `import 'path/to/rakefile.rake'`
- Loads partial Rakefiles
- Can appear anywhere in file
- Allows Rakefile modularization

**Import Semantics**
- Imported files loaded after current file parsed
- Imported files can depend on current file's definitions
- Useful for separating concerns (database, assets, etc.)

---

## 3. RAILS INTEGRATION

### 3.1 Rails Environment Detection

**Rails.env**
- Instance of `ActiveSupport::StringInquirer` (String subclass)
- Represents current environment: development, test, production
- Predicate methods: `Rails.env.production?`, `.development?`, `.test?`
- Can be set: `Rails.env = "production"`

**Environment-Specific Behavior**
- Control execution flow based on environment
- Conditional task execution in rake tasks
- Different config per environment

### 3.2 Rails Rake Integration

**Task Organization**
- Rails projects place rake tasks in `lib/tasks/*.rake`
- Convention for app-specific tasks
- Gems can include their own tasks

**Environment Loading**
- `:environment` dependency loads Rails app
- Enables access to models, database, configurations
- Database tasks automatically include `:environment`

**Built-In Task Categories**

**Database Tasks** (ActiveRecord::Tasks::DatabaseTasks)
- Configured via ActiveRecord config:
  - `env` - Current environment
  - `database_configuration` - Database config
  - `db_dir` - Database directory
  - `migrations_paths` - Migration directories
  - `seed_loader` - Seed loading
  - `root` - Application root
- Tasks: `db:migrate`, `db:create`, `db:drop`, `db:seed`, etc.
- Database-specific SQL execution
- Tracks migration status

**Asset Tasks** (sprockets-rails)
- `assets:precompile` - Compile assets for production
- `assets:clean` - Clean compiled assets
- `assets:clobber` - Completely remove assets
- Invokes `assets:environment` first (loads Rails)
- Customizable compressor configuration
- View helpers depend on precompiled assets

### 3.3 Known Issues with Rails Rake Tasks

**Environment Switching Problems**
- Running DB tasks in development also affects test env
- Environment initialization doesn't account for dynamic changes
- Rails.env and DatabaseTasks.env get out of sync
- Solution: Explicitly set `RAILS_ENV` before running tasks

**Dotenv Issues**
- May default to development environment
- Set `RAILS_ENV` explicitly when using dotenv
- Foreman with `.env` file may have blank values in tasks

---

## 4. FEATURE COMPARISON MATRIX

| Feature | Toys-Core | Rake | Notes |
|---------|-----------|------|-------|
| **Primary Purpose** | CLI tool framework | Build/task automation | Different design goals |
| **Configuration** | `.toys.rb` or `.toys/` dir | Rakefile | File-based definition |
| **Task/Tool Hierarchy** | Tool namespaces | Task namespaces | Both support nesting |
| **Argument Handling** | Flags + positional args | Task arguments | Toys more CLI-native |
| **Unix Conventions** | Yes (--flag, positional) | Limited (rake syntax) | Toys more standard |
| **Help Generation** | Auto, with search | Manual via `desc` | Toys more automated |
| **Tab Completion** | Built-in support | Not standard | Toys more modern |
| **File Dependencies** | Not primary | Core strength | Rake's specialty |
| **Parallel Execution** | Via shell/threads | multitask support | Both available |
| **Built-in Mixins** | exec, fileutils, terminal, gems, highline, bundler, git | clean, clobber, PackageTask, TestTask | Toys more extensible |
| **Middleware System** | Yes (customizable) | Limited | Toys more flexible |
| **Dependencies** | None (optional mixins) | None | Both lightweight |
| **Template System** | Yes (template DSL) | Implicit (rule patterns) | Toys more explicit |
| **Import/Modular** | .toys/ directory structure | `import` statement | Different approaches |
| **Environment Variables** | ENV access | ENV + conventions | Rails integration stronger in Rake |
| **Rails Integration** | Could work | Built-in expectations | Rake more mature here |

---

## 5. DEVEX RECOMMENDATIONS

### 5.1 Executive Recommendation

Devex should adopt a **hybrid approach**:
- **Core CLI framework from toys-core**: Modern DSL, auto-generated help, zero dependencies
- **Selective Rake patterns**: For file-based tasks where dependencies matter
- **Simplified middleware**: Custom middleware for devex-specific needs (logging, error handling)
- **Optional mixins**: Make advanced features optional via configuration

**Rationale for Zero-Heavy-Dependency Goal**: Both toys-core and Rake have no heavy dependencies. Devex should follow this pattern, making advanced features like `:exec`, `:terminal`, `:highline` opt-in rather than default.

### 5.2 Feature-by-Feature Recommendations

#### DSL and Tool Definition
- **ADOPT from toys-core**: Tool definition style with `tool` blocks
- **Rationale**: More modern, supports Unix conventions, better for CLI apps
- **Implementation**: Lightweight DSL in pure Ruby

#### Help Generation
- **ADOPT from toys-core**: Auto-generated help, `desc` method
- **Enhancement**: Add optional categories/grouping for complex CLIs
- **Rationale**: Reduces boilerplate, helps discovery, modern UX

#### Flag and Argument Handling
- **ADOPT from toys-core**: Flag definitions with acceptors and completions
- **Simplification**: Start with simple flags, add acceptors as optional enhancement
- **Rationale**: Matches user expectations from modern CLIs (git, docker, etc.)

#### Built-In Mixins
- **ADOPT Selectively**:
  - `:exec` - Core capability for CLI tool (include by default)
  - `:fileutils` - Useful for automation tasks (include by default)
  - `:terminal` - Optional, for fancy output
  - `:highline` / `:gems` / `:bundler` - Optional, pull in dependencies
- **Rationale**: Keep base lightweight, offer advanced features opt-in

#### Middleware System
- **ADOPT**: Basic middleware architecture from toys-core
- **Scope**: Start with help middleware, error handling
- **Future**: Allow custom middleware for user extensions
- **Rationale**: Enables clean separation of concerns without bloat

#### Template System
- **CONDITIONAL**: Low priority for MVP, but good future addition
- **Use Case**: Generate multiple similar tools from pattern
- **Rationale**: Valuable for complex projects, not essential for basic CLI

#### Settings/Configuration
- **NEW**: Design simple configuration system
- **Approach**: YAML file + env variable override pattern
- **Rationale**: Both toys-core and Rake delegate to external config; devex could offer lightweight alternative

#### Namespace/Organization
- **ADOPT from toys-core**: Directory-based organization with `.devex/` or similar
- **Simplification**: Don't require `.toys/` complexity initially
- **Future**: Support directory-based tool separation if needed
- **Rationale**: Matches user mental models, easy to understand

#### Task Dependencies (from Rake)
- **CONDITIONAL**: Only if devex supports build-like tasks
- **Approach**: Simple prerequisites array, not file-based tracking
- **Rationale**: Overkill for pure CLI, useful for hybrid workflows

#### File-Based Dependency Tracking
- **SKIP for MVP**: This is Rake's strength, not essential for CLI tool
- **Rationale**: Adds complexity; devex focus is CLI, not builds

#### Environment Variables
- **ADOPT**: Simple ENV access and conventions
- **Pattern**: Support `DEVEX_ENV`, `DEVEX_DEBUG`, etc.
- **Rationale**: Standard practice for CLIs, minimal implementation

#### Import/Modularization
- **ADOPT**: Support splitting tool definitions across files
- **Approach**: Directory-based discovery rather than import statement
- **Rationale**: More intuitive for CLI tools

#### Testing
- **OUT OF SCOPE for framework**: Not included in toys-core or Rake
- **Recommendation**: Design for testability, provide examples
- **Rationale**: Users will integrate with their test framework

### 5.3 Feature Roadmap Phases

#### Phase 1: MVP (Core CLI Framework)
- Tool definition DSL
- Basic flags and arguments
- Help generation
- Simple error handling
- `:exec` mixin (subprocess control)
- `:fileutils` mixin (common file operations)
- Directory-based tool discovery

#### Phase 2: Enhanced UX
- Tab completion support
- Better error messages
- Optional `:terminal` mixin
- Middleware basic system
- Tool grouping/categorization in help

#### Phase 3: Advanced Features
- Template system for generating tools
- Custom acceptors for arguments
- Advanced middleware (logging, metrics)
- Configuration system (YAML + env)
- Import/include for shared code

#### Phase 4: Optional Extensions
- Task dependencies (if build tool support desired)
- Package tasks (if distribution needed)
- File task support (if asset pipelines desired)
- Optional `:highline` for advanced prompts
- Optional `:bundler` for gem isolation

### 5.4 Features to Intentionally Exclude

**In the Core Framework:**
1. File-based dependency tracking (Rake's strong suit, not needed for CLI)
2. Heavy OOP structure (keep simple)
3. Multiple test framework integrations (use adapters if needed)
4. RDoc/documentation generation (not CLI's job)
5. Automatic gem packaging (not primary use case)

**Reasoning**: Keep framework lightweight, focused, and extensible. Users can add these via plugins/middlewares if needed.

### 5.5 Design Principles for Devex

1. **Zero Base Dependencies**: Like toys-core, depend on nothing
2. **Opt-In Advanced Features**: Complex features via mixins/plugins
3. **Unix Conventions**: Align with standard CLI practices
4. **Progressive Enhancement**: Start simple, add features as needed
5. **Discoverability**: Auto-generate help, support search/filtering
6. **Composability**: Tools can call other tools, mixins can be combined
7. **Pure Ruby**: No external processes unless explicitly requested
8. **Lightweight Execution**: Fast startup, minimal overhead

### 5.6 When to Reference Each Tool

**Look to toys-core for:**
- Modern CLI patterns and UX
- Help system implementation
- Flag/argument parsing design
- Mixin architecture pattern
- Middleware concepts
- Zero-dependency approach

**Look to Rake for:**
- File task patterns (if implementing later)
- Namespace organization ideas
- Environment integration (Rails patterns)
- Rule-based automation (if needed)
- Task dependency inference

---

## 6. SOURCES AND REFERENCES

Key research sources for this document:

- [Toys-Core on GitHub](https://github.com/dazuma/toys)
- [Toys-Core Documentation](https://dazuma.github.io/toys/gems/toys-core/v0.15.6/)
- [Toys-Core RubyDoc](https://www.rubydoc.info/gems/toys-core)
- [Toys User Guide](https://dazuma.github.io/toys/gems/toys/v0.10.3/file.guide.html)
- [Rake on GitHub](https://github.com/ruby/rake)
- [Rake Official Documentation](https://ruby.github.io/rake/)
- [Using the Rake Build Language](https://martinfowler.com/articles/rake.html)
- [Rails ActiveRecord Task Documentation](https://api.rubyonrails.org/classes/ActiveRecord/Tasks/DatabaseTasks.html)
- [Rails Command Line Guide](https://guides.rubyonrails.org/command_line.html)
- ["Is it time to replace Rake?"](https://daniel-azuma.com/blog/2019/11/06/is-it-time-to-replace-rake) by Daniel Azuma (toys author)

---

## 7. CONCLUSION

Both toys-core and Rake are mature, well-designed tools solving different problems:
- **Toys-core** optimizes for modern CLI applications with Unix conventions and great UX
- **Rake** excels at file-based dependency management and build automation

For devex, a lightweight zero-heavy-dependency CLI tool, the recommendation is to adopt toys-core's architecture and design philosophy as the primary foundation, selectively borrow Rake patterns for features that support build-like tasks, and maintain a laser focus on simplicity and composability.

The key to success is keeping the base framework minimal and extensible, allowing advanced features to be added via optional mixins and middleware without burdening users who only need basic CLI functionality.

---

## Notes for Future Research

- Profile startup time difference between toys-core and Rake
- Explore community adoption rates and plugin ecosystems
- Investigate how other modern Ruby CLI tools (Thor, GLI) compare
- Research tab completion implementation details
- Document real-world devex use cases to validate feature priorities
