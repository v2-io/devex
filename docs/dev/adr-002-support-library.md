# ADR-002: Ruby Support Library (dx-support)

**Status:** Draft
**Date:** 2025-12-13
**Context:** Devex needs ergonomic Ruby utilities. Should be usable as standalone gem by projects using dx.

## Summary

This ADR defines a lightweight support library providing ergonomic Ruby extensions for CLI and general Ruby development. The library should be:

1. **Standalone** - Usable independently of devex (like ActiveSupport is to Rails)
2. **Lightweight** - No heavy dependencies, minimal overhead
3. **Modern** - Leverage Ruby 3.3+ features, avoid obsolete patterns
4. **Opt-in** - Use refinements where possible, explicit activation elsewhere

The library takes inspiration from:
- Joseph's battle-tested shorthand scripts (~800 lines of accumulated wisdom)
- ActiveSupport's most valuable patterns (cherry-picked, not wholesale)
- Ruby 3.3+ native capabilities

---

## Comprehensive ActiveSupport Analysis

ActiveSupport provides extensive core extensions. Here's what's valuable for a CLI-focused library vs. what's Rails-specific or unnecessary:

### High Value (Include)

| Class | Method | Why Valuable |
|-------|--------|--------------|
| **Object** | `blank?`, `present?`, `presence` | Universal nil/empty checking |
| **Object** | `try`, `try!` | Safe method calls (though `&.` handles most cases) |
| **Object** | `in?` | Cleaner than `collection.include?(item)` |
| **Object** | `deep_dup` | Essential for nested structures |
| **String** | `squish` | Normalize whitespace |
| **String** | `truncate`, `truncate_words` | Display formatting |
| **String** | `indent` | Code/output formatting |
| **String** | `underscore`, `camelize`, `dasherize` | Name transformations |
| **String** | `parameterize` | URL slugs |
| **String** | `humanize`, `titleize` | Display formatting |
| **String** | `constantize`, `safe_constantize` | Dynamic class loading |
| **String** | `pluralize`, `singularize` | Grammar (if we include inflector) |
| **Array** | `second`, `third`, `fourth`, `fifth` | Positional accessors |
| **Array** | `second_to_last`, `third_to_last` | Reverse positional |
| **Array** | `to_sentence` | "a, b, and c" formatting |
| **Array** | `in_groups`, `in_groups_of` | Chunking |
| **Array** | `extract_options!` | Options hash pattern |
| **Hash** | `deep_merge`, `deep_merge!` | Nested hash operations |
| **Hash** | `deep_stringify_keys`, `deep_symbolize_keys` | Key normalization |
| **Hash** | `except`, `slice` | Key filtering (native in 3.0+, but `except` is useful) |
| **Hash** | `with_indifferent_access` | String/symbol key flexibility |
| **Hash** | `assert_valid_keys` | Options validation |
| **Enumerable** | `index_by`, `index_with` | Hash construction |
| **Enumerable** | `pluck`, `pick` | Attribute extraction |
| **Enumerable** | `many?` | Size > 1 check |
| **Enumerable** | `excluding`, `including` | Set-like operations |
| **Numeric** | `bytes`, `kilobytes`, etc. | File size constants |
| **Numeric** | `seconds`, `minutes`, `hours`, `days` | Duration DSL |
| **Integer** | `ordinalize` | "1st", "2nd", "3rd" |
| **Module** | `delegate`, `delegate_missing_to` | Clean delegation |
| **Module** | `mattr_accessor` | Module attributes |
| **Class** | `class_attribute` | Inheritable attributes |
| **File** | `atomic_write` | Safe file updates |
| **Pathname** | `existence` | Returns self or nil |

### Medium Value (Consider)

| Class | Method | Notes |
|-------|--------|-------|
| **Object** | `with_options` | Useful for DSLs |
| **Object** | `to_param`, `to_query` | URL building |
| **String** | `remove` | Cleaner than `gsub(pattern, '')` |
| **String** | `at`, `from`, `to`, `first`, `last` | Already have native equivalents |
| **Array** | `wrap` | `Array()` works similarly |
| **Hash** | `reverse_merge` | Useful for defaults |
| **Module** | `alias_attribute` | Model-specific |
| **Module** | `concerning` | Organization pattern |
| **Time/Date** | All calculations | Very useful but adds complexity |

### Low Value for CLI (Skip)

| Category | Why Skip |
|----------|----------|
| `html_safe`, `html_escape` | Web-specific |
| `HashWithIndifferentAccess` | Can be heavy; `symbolize_keys` often enough |
| `Callbacks`, `Concerns` | Rails patterns |
| `Caching` | Too heavy for CLI |
| `Encryption`, `MessageVerifier` | Specialized |
| `CurrentAttributes` | Web request context |
| `Deprecation` | Framework concern |
| `Inflector` (full) | Most apps need just a few methods |
| Most Time/Date calculations | Keep simple; full version is complex |

---

## Analysis of shorthand_*.rb Scripts

Joseph's scripts (~800 lines across 3 files) contain utilities accumulated over years. Here's what's still valuable vs. what Ruby now provides natively:

### Now Native in Ruby 3.3+

| Feature | Ruby Version | Notes |
|---------|--------------|-------|
| Ordered Hash | 1.9+ | `Hash` preserves insertion order |
| Safe navigation | 2.3+ | `&.` operator replaces most `Nilish` usage |
| `Array#sum` | 2.4+ | Built into Enumerable |
| `Hash#transform_values` | 2.4+ | Replaces `map_vals` |
| `Hash#compact` | 2.4+ | Removes nil values |
| `Range#overlap?` | 3.3+ | New in 3.3 |
| `Data` class | 3.2+ | Immutable value objects |
| Pattern matching | 3.0+ | `case`/`in` patterns |
| `it` block param | 3.4+ | Cleaner than `_1` |
| Prism parser | 3.3+ | Better tooling |
| YJIT | 3.1+ | Much faster |

### Still Valuable (No Native Equivalent)

**Object Extensions:**
- `blank?` / `present?` / `presence` - ActiveSupport-style, but lightweight
- `numeric?` - Check if something is numeric

**Pathname Extensions:**
- `r?`, `w?`, `x?`, `rw?`, `rwx?` - Permission shortcuts
- `dir?` - Alias for `directory?`
- `exp` / `real` - Memoized `expand_path` / `realpath`
- `rel` / `short` - Relative path with `~` substitution
- `/` operator - Path joining (`path / "subdir"`)
- `[]` - Glob from directory
- `dir!` - Create directory if missing

**String Extensions:**
- `wrap(indent, width)` - Word wrapping with paragraph handling
- `sentences` - Split into sentences
- `to_sh` - Shell escaping
- `fnv32` / `fnv64` - Fast non-cryptographic hashes
- `base64url` - URL-safe base64

**Enumerable Statistics:**
- `average` / `mean` - Arithmetic mean
- `median` / `mid` - Median value
- `sample_variance` / `stddev` - Statistical measures
- `q20` / `q80` - Quintile bounds
- `robust_avg` - Trimmed mean
- `summarize_runs` - Run-length encoding

**Hash Extensions:**
- `stable_compact` - Deep compact with sorting for signatures
- `to_sig` - Content signature (SHA1 of stable representation)

**ANSI Colors:**
- `color(r, g, b)` - Truecolor foreground
- `background(r, g, b)` - Truecolor background
- `bold`, `italic`, `underline`, `strike` - Text styles

**Subprocess Execution:**
- `os(command)` - Execute with exit-on-failure (aligns with ADR-001!)

---

## Design Principles

### 1. Minimal Core Extensions

Only extend core classes when the utility is:
- Frequently used in CLI contexts
- Significantly more ergonomic than alternatives
- Non-controversial (won't surprise users)

### 2. Refinements Over Monkey-Patching

Use Ruby refinements where possible to limit scope:

```ruby
module Devex::Support
  module StringExtensions
    refine String do
      def blank?
        self !~ /[^[:space:]]/
      end
    end
  end
end

# Usage: explicit opt-in
using Devex::Support::StringExtensions
```

### 3. Leverage Ruby 3.3+ Features

- Use `Data` class for simple immutable results
- Use pattern matching in implementations
- Rely on native `&.` instead of `Nilish`
- Use `Array#sum` not custom implementation

### 4. Integration with Devex Context

Color methods should respect `Devex::Context.color?`:

```ruby
def color(r, g, b)
  return self unless Devex::Context.color?
  "\e[38;2;#{r};#{g};#{b}m#{self}\e[0m"
end
```

---

## Proposed Module Structure

```
lib/devex/support/
├── core_ext/
│   ├── object.rb       # blank?, present?, presence, numeric?
│   ├── string.rb       # wrap, sentences, to_sh, fnv*, base64url
│   ├── enumerable.rb   # Statistics: average, median, stddev, etc.
│   └── hash.rb         # stable_compact, to_sig
├── path.rb             # Enhanced Pathname (Path alias)
├── ansi.rb             # Truecolor and styles
├── result.rb           # Result monad for exec (from ADR-001)
└── support.rb          # Main entry point, loads all
```

---

## Detailed Specifications

### Object Extensions

```ruby
module Devex::Support::CoreExt::Object
  refine Object do
    # Returns true if object is nil, false, empty, or whitespace-only string
    def blank?
      respond_to?(:empty?) ? empty? : !self
    end

    # Opposite of blank?
    def present?
      !blank?
    end

    # Returns self if present?, otherwise nil
    def presence
      self if present?
    end

    # Returns true if object can be converted to a number
    def numeric?
      true if Float(self) rescue false
    end
  end

  refine NilClass do
    def blank? = true
  end

  refine FalseClass do
    def blank? = true
  end

  refine TrueClass do
    def blank? = false
  end

  refine Numeric do
    def blank? = false
    def numeric? = true
  end

  refine String do
    def blank?
      self !~ /[^[:space:]]/
    end
  end

  refine Array do
    def blank? = empty?
  end

  refine Hash do
    def blank? = empty?
  end
end
```

### String Extensions

```ruby
module Devex::Support::CoreExt::String
  refine String do
    # Word-wrap text preserving paragraphs
    # @param indent [:first, String, Integer] - indentation style
    # @param width [Integer] - line width (default 90)
    def wrap(indent = :first, width = 90)
      ind = case indent
            when :first  then self[/^[[:space:]]*/]
            when String  then indent
            when Integer then ' ' * indent.abs
            else ''
            end

      ind_size = ind.count("\t") * 8 + ind.count("^\t")
      effective_width = [width - ind_size, 1].max

      paragraphs = strip.split(/\n[ \t]*\n/m)
      paragraphs.map { |p|
        p.gsub(/[[:space:]]+/, ' ')
         .strip
         .scan(/.{1,#{effective_width}}(?: |$)/)
         .map { |row| ind + row.strip }
         .join("\n")
      }.join("\n\n")
    end

    # Split text into sentences
    def sentences
      gsub(/\s+/, ' ')
        .scan(/[^.!?]+[.!?]+(?:\s+|$)|[^.!?]+$/)
        .map(&:strip)
        .reject(&:empty?)
    end

    # Escape for shell (POSIX)
    def to_sh
      return "''" if empty?
      gsub(/([^A-Za-z0-9_\-.,:\/@\n])/, '\\\\\\1').gsub("\n", "'\n'")
    end

    # FNV-1a 32-bit hash (fast, non-cryptographic)
    def fnv32
      bytes.reduce(0x811c9dc5) { |h, b| ((h ^ b) * 0x01000193) % (1 << 32) }
    end

    # FNV-1a 64-bit hash (fast, non-cryptographic)
    def fnv64
      bytes.reduce(0xcbf29ce484222325) { |h, b| ((h ^ b) * 0x100000001b3) % (1 << 64) }
    end

    # URL-safe Base64 encoding
    def base64url
      require 'base64'
      Base64.urlsafe_encode64(self, padding: false)
    end
  end
end
```

### Enumerable Statistics

```ruby
module Devex::Support::CoreExt::Enumerable
  refine Enumerable do
    # Arithmetic mean
    def average
      return 0.0 if empty?
      sum.to_f / size
    end
    alias_method :mean, :average

    # Median value
    def median
      return nil if empty?
      sorted = sort
      mid = size / 2
      size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
    end

    # Sample variance
    def sample_variance
      return 0.0 if size < 2
      avg = average
      sum { |x| (x - avg) ** 2 } / (size - 1).to_f
    end
    alias_method :variance, :sample_variance

    # Standard deviation
    def standard_deviation
      Math.sqrt(sample_variance)
    end
    alias_method :stddev, :standard_deviation

    # 20th percentile (first quintile)
    def q20
      percentile(20)
    end

    # 80th percentile (fourth quintile)
    def q80
      percentile(80)
    end

    # General percentile calculation
    def percentile(p)
      return nil if empty?
      sorted = sort
      k = (p / 100.0) * (size - 1)
      f = k.floor
      c = k.ceil
      return sorted[f] if f == c
      sorted[f] * (c - k) + sorted[c] * (k - f)
    end

    # Trimmed mean (average of q20, median, q80)
    def robust_average
      return nil if empty?
      (q20 + median + q80) / 3.0
    end

    # Map by sending method to each element
    # @example ["foo", "bar"].amap(:upcase) => ["FOO", "BAR"]
    def amap(method, *args, &block)
      map { |item| item.send(method, *args, &block) }
    end

    # Run-length encoding
    # @example [1,1,1,2,2,3].summarize_runs => [[3,1], [2,2], [1,3]]
    def summarize_runs
      return [] if empty?
      chunk_while { |a, b| a == b }.map { |run| [run.size, run.first] }
    end
  end
end
```

### Hash Extensions

```ruby
module Devex::Support::CoreExt::Hash
  refine Hash do
    # Deep compact with stable sorting for signatures
    def stable_compact
      compact
        .transform_values { |v|
          case v
          when Hash then v.stable_compact
          when Array then v.map { |e| e.respond_to?(:stable_compact) ? e.stable_compact : e }
          else v
          end
        }
        .sort
        .to_h
    end

    # Content-based signature (SHA1 of stable representation)
    def to_sig
      require 'digest'
      Digest::SHA1.hexdigest(stable_compact.inspect)
    end
  end
end
```

### Enhanced Pathname (Path)

This is the crown jewel - ergonomic path manipulation that makes working with files a pleasure.

**Design Goals:**
- Feels like string manipulation but with path semantics
- Clean relative-to-project-root patterns
- Safe operations that don't throw on missing paths
- Chainable operations

```ruby
module Devex::Support
  # Enhanced Pathname with ergonomic shortcuts
  #
  # Usage patterns:
  #
  #   # Construction
  #   path = Path["~/src/project"]           # From string with [] syntax
  #   path = "~/src/project".to_p            # From string with to_p
  #   path = Path.pwd                        # Current directory
  #   path = Path.home                       # Home directory
  #
  #   # Joining
  #   path / "lib" / "foo.rb"                # Division operator
  #   path.join("lib", "foo.rb")             # Explicit join
  #
  #   # Relative to project root
  #   project = Path[cli.project_root]
  #   template = project / "templates" / "default.erb"
  #
  #   # Permission checks (short and memorable)
  #   path.r?                                # readable?
  #   path.w?                                # writable?
  #   path.x?                                # executable?
  #   path.rw?                               # readable AND writable?
  #
  #   # Existence and type
  #   path.exist?                            # native
  #   path.exists?                           # alias (both work)
  #   path.missing?                          # opposite of exist?
  #   path.dir?                              # is directory?
  #   path.file?                             # native
  #
  #   # Expansion (memoized for performance)
  #   path.exp                               # expand_path (memoized)
  #   path.real                              # realpath with fallback (memoized)
  #
  #   # Relative paths
  #   path.rel                               # relative to pwd, with ~/
  #   path.rel(from: project_root)           # relative to specific dir
  #   path.short                             # shortest representation
  #
  #   # Globbing
  #   path["**/*.rb"]                        # all Ruby files recursively
  #   path["*.erb"]                          # ERB files in this directory
  #
  #   # Safe directory creation
  #   path.dir!                              # mkpath, returns self
  #   (project / "output" / "reports").dir!  # creates full hierarchy
  #
  #   # File I/O
  #   content = path.read                    # read entire file
  #   path.write(content)                    # write (creates dirs)
  #   path.append(content)                   # append to file
  #   path.atomic_write(content)             # safe atomic write
  #
  #   # Inspection
  #   path.contents                          # alias for read
  #   path.lines                             # readlines
  #   path.mtime                             # modification time
  #   path.size                              # file size
  #   path.newer_than?(other)                # modification comparison
  #   path.older_than?(other)                # modification comparison
  #
  class Path < Pathname
    class << self
      # Construct from string: Path["~/src/project"]
      def [](path)
        new(path.to_s)
      end

      # Current working directory
      def pwd
        new(Dir.pwd)
      end
      alias_method :cwd, :pwd
      alias_method :getwd, :pwd

      # Home directory
      def home
        new(ENV['HOME'] || Dir.home)
      end

      # Temporary directory
      def tmp
        new(Dir.tmpdir)
      end
      alias_method :tmpdir, :tmp
    end

    # ─────────────────────────────────────────────────────────────
    # Path Joining
    # ─────────────────────────────────────────────────────────────

    # Division operator for path joining: path / "subdir" / "file.rb"
    def /(other)
      self.class.new(join(other.to_s))
    end

    # Override join to return Path
    def join(*args)
      self.class.new(super(*args.map(&:to_s)))
    end

    # ─────────────────────────────────────────────────────────────
    # Permission Checks (terse but memorable)
    # ─────────────────────────────────────────────────────────────

    def r?   = readable_real?
    def w?   = writable_real?
    def x?   = executable_real?
    def rw?  = r? && w?
    def rx?  = r? && x?
    def wx?  = w? && x?
    def rwx? = r? && w? && x?

    # ─────────────────────────────────────────────────────────────
    # Type Checks
    # ─────────────────────────────────────────────────────────────

    def dir?     = directory?
    def missing? = !exist?
    alias_method :exists?, :exist?

    # ActiveSupport-style: returns self if exists, nil otherwise
    def existence
      exist? ? self : nil
    end

    # ─────────────────────────────────────────────────────────────
    # Memoized Expansions (performance optimization)
    # ─────────────────────────────────────────────────────────────

    # Expanded path (memoized)
    def exp
      @exp ||= self.class.new(expand_path)
    end

    # Real path with fallback to expanded (memoized, safe)
    def real
      @real ||= self.class.new(realpath) rescue exp
    end

    # Clear memoization (if path might have changed)
    def reload!
      @exp = @real = @rc = nil
      self
    end

    # ─────────────────────────────────────────────────────────────
    # Relative Paths
    # ─────────────────────────────────────────────────────────────

    # Relative path with ~ substitution for home directory
    # @param from [Path, String] Base directory (default: pwd)
    # @param home [Boolean] Substitute ~ for home directory
    def rel(from: nil, home: true)
      from = self.class.new(from || Dir.pwd)
      result = exp.relative_path_from(from.exp)
      if home && ENV['HOME'] && result.to_s.start_with?(ENV['HOME'])
        result = self.class.new(result.to_s.sub(ENV['HOME'], '~'))
      end
      result
    rescue ArgumentError
      # Can't compute relative path (different drives on Windows, etc.)
      home ? self.class.new(to_s.sub(ENV['HOME'].to_s, '~')) : self
    end

    # Shortest representation of path
    def short(from: nil)
      from = self.class.new(from || Dir.pwd)
      candidates = []

      # Try relative from base
      begin
        candidates << exp.relative_path_from(from.exp)
      rescue ArgumentError
      end

      # Try with ~ substitution
      if ENV['HOME']
        home_sub = to_s.sub(ENV['HOME'], '~')
        candidates << self.class.new(home_sub) if home_sub != to_s
      end

      # Original as fallback
      candidates << self

      candidates.compact.min_by { |c| c.to_s.length }
    end

    # Cache for relative path calculations (expensive operation)
    def relative_path_from(base)
      @rc ||= {}
      @rc[base.to_s] ||= self.class.new(super(base))
    end

    # ─────────────────────────────────────────────────────────────
    # Globbing
    # ─────────────────────────────────────────────────────────────

    # Glob from this directory: path["**/*.rb"]
    def [](pattern, include_dotfiles: true)
      base = dir? ? self : dirname
      flags = include_dotfiles ? File::FNM_DOTMATCH : 0
      Pathname.glob((base + pattern.to_s).to_s, flags).map { |p| self.class.new(p) }
    end

    # Alias for more explicit calls
    def glob(pattern, **opts)
      self[pattern, **opts]
    end

    # ─────────────────────────────────────────────────────────────
    # Directory Operations
    # ─────────────────────────────────────────────────────────────

    # Get directory (dirname, but returns self if already a directory)
    def dir
      dir? ? exp : self.class.new(dirname)
    end

    # Create directory (and parents) if missing, return self
    # Safe - returns nil on error instead of raising
    def dir!
      target = dir? ? self : dir
      target.mkpath unless target.exist?
      self
    rescue SystemCallError
      nil
    end

    # Create this directory (and parents) if missing
    def mkdir!
      mkpath unless exist?
      self
    rescue SystemCallError
      nil
    end

    # ─────────────────────────────────────────────────────────────
    # File I/O
    # ─────────────────────────────────────────────────────────────

    # Read entire file contents
    def read(encoding: nil)
      opts = encoding ? { encoding: encoding } : {}
      File.read(self, **opts)
    end
    alias_method :contents, :read

    # Read as lines
    def lines(chomp: true)
      File.readlines(self, chomp: chomp)
    end

    # Write contents (creates parent directories)
    def write(content, encoding: nil)
      dir!
      opts = encoding ? { encoding: encoding } : {}
      File.write(self, content, **opts)
      self
    end

    # Append to file
    def append(content)
      dir!
      File.write(self, content, mode: 'a')
      self
    end

    # Atomic write (write to temp, then rename)
    def atomic_write(content)
      dir!
      require 'tempfile'
      Tempfile.create(basename.to_s, dirname) do |temp|
        temp.write(content)
        temp.close
        File.rename(temp.path, self)
      end
      self
    end

    # ─────────────────────────────────────────────────────────────
    # Modification Time Comparisons
    # ─────────────────────────────────────────────────────────────

    def newer_than?(other)
      other = self.class.new(other) unless other.is_a?(Pathname)
      return true unless other.exist?
      return false unless exist?
      mtime > other.mtime
    end

    def older_than?(other)
      other = self.class.new(other) unless other.is_a?(Pathname)
      return false unless other.exist?
      return true unless exist?
      mtime < other.mtime
    end

    # ─────────────────────────────────────────────────────────────
    # Extension Manipulation
    # ─────────────────────────────────────────────────────────────

    # Replace extension: path.with_ext(".md")
    def with_ext(new_ext)
      new_ext = ".#{new_ext}" unless new_ext.start_with?('.')
      self.class.new(sub_ext(new_ext))
    end

    # Remove extension
    def without_ext
      self.class.new(to_s.sub(/#{Regexp.escape(extname)}$/, ''))
    end

    # ─────────────────────────────────────────────────────────────
    # Siblings and Relatives
    # ─────────────────────────────────────────────────────────────

    # Sibling with same directory but different name
    def sibling(name)
      dir / name.to_s
    end

    # Override parent to return Path
    def parent
      self.class.new(super)
    end

    # Override dirname to return Path
    def dirname
      self.class.new(super)
    end

    # Override basename to return Path
    def basename(*args)
      self.class.new(super)
    end

    # ─────────────────────────────────────────────────────────────
    # String-like Behavior
    # ─────────────────────────────────────────────────────────────

    # Delegate string methods to to_s
    def method_missing(method, *args, &block)
      if to_s.respond_to?(method)
        result = to_s.send(method, *args, &block)
        # Return Path if result is a path-like string
        result.is_a?(String) && result.include?('/') ? self.class.new(result) : result
      else
        super
      end
    end

    def respond_to_missing?(method, include_private = false)
      to_s.respond_to?(method, include_private) || super
    end
  end
end
```

**String#to_p refinement:**

```ruby
module Devex::Support::CoreExt::String
  refine String do
    # Convert string to Path
    def to_p
      Devex::Support::Path.new(self)
    end
  end
end
```

**Global Path alias (optional, for convenience):**

```ruby
# In dx-support/global.rb
Path = Devex::Support::Path unless defined?(Path)
```

**Usage Examples:**

```ruby
# Setup
using Devex::Support::CoreExt::String
project = Path[cli.project_root]

# Finding templates relative to project
template_dir = project / "templates"
default_template = template_dir / "default.erb"

# Or more concisely
template = project / "templates" / "default.erb"

# Checking existence before use
if template.exist?
  content = template.read
else
  content = (project / "templates" / "fallback.erb").read
end

# Creating output directories safely
output = project / "output" / "reports" / Date.today.to_s
output.dir!  # Creates full hierarchy if needed
(output / "summary.md").write(report_content)

# Globbing for files
project["**/*.rb"].each do |ruby_file|
  puts ruby_file.rel  # Relative path with ~/
end

# Conditional existence (ActiveSupport-style)
config = (project / "config.yml").existence || (project / "config.default.yml")
```

### ANSI Colors

```ruby
module Devex::Support
  module ANSI
    module_function

    # Check if colors should be used
    def enabled?
      Devex::Context.color?
    end

    # Apply ANSI escape code
    def escape(code, text)
      return text unless enabled?
      "\e[#{code}m#{text}\e[0m"
    end

    # Truecolor foreground
    def color(text, r, g, b)
      escape("38;2;#{r};#{g};#{b}", text)
    end

    # Truecolor background
    def background(text, r, g, b)
      escape("48;2;#{r};#{g};#{b}", text)
    end

    # Text styles
    def bold(text)      = escape(1, text)
    def dim(text)       = escape(2, text)
    def italic(text)    = escape(3, text)
    def underline(text) = escape(4, text)
    def blink(text)     = escape(5, text)
    def reverse(text)   = escape(7, text)
    def strike(text)    = escape(9, text)

    # Named colors (from Devex::Output::COLORS)
    NAMED_COLORS = {
      success: [0x5A, 0xF7, 0x8E],
      error:   [0xFF, 0x6B, 0x6B],
      warning: [0xFF, 0xE6, 0x6D],
      info:    [0x6B, 0xC5, 0xFF],
      header:  [0xC4, 0xB5, 0xFD],
      muted:   [0x88, 0x88, 0x88],
      emphasis:[0xFF, 0xFF, 0xFF],
    }.freeze

    def named_color(text, name)
      rgb = NAMED_COLORS[name]
      rgb ? color(text, *rgb) : text
    end
  end
end

# String refinements for ANSI
module Devex::Support::CoreExt::String
  refine String do
    def color(r, g, b)
      Devex::Support::ANSI.color(self, r, g, b)
    end

    def background(r, g, b)
      Devex::Support::ANSI.background(self, r, g, b)
    end

    def bold      = Devex::Support::ANSI.bold(self)
    def dim       = Devex::Support::ANSI.dim(self)
    def italic    = Devex::Support::ANSI.italic(self)
    def underline = Devex::Support::ANSI.underline(self)
    def strike    = Devex::Support::ANSI.strike(self)
  end
end
```

### Result Monad (from ADR-001)

```ruby
module Devex::Support
  # Immutable result object for subprocess execution
  # Acts as a Result monad (Success | Failure)
  class Result
    attr_reader :command, :exit_code, :signal_code, :stdout, :stderr,
                :pid, :duration, :exception

    def initialize(
      command:,
      exit_code: nil,
      signal_code: nil,
      stdout: nil,
      stderr: nil,
      pid: nil,
      duration: nil,
      exception: nil
    )
      @command = command.freeze
      @exit_code = exit_code
      @signal_code = signal_code
      @stdout = stdout&.freeze
      @stderr = stderr&.freeze
      @pid = pid
      @duration = duration
      @exception = exception
      freeze
    end

    # Status checks
    def success?  = exit_code == 0
    def failed?   = exception || exit_code.nil?
    def error?    = exit_code && exit_code != 0
    def signaled? = !signal_code.nil?
    def timed_out? = @timed_out

    # Convenience accessors
    def output
      [stdout, stderr].compact.join("\n")
    end

    alias_method :captured_out, :stdout
    alias_method :captured_err, :stderr

    # Monad operations

    # Exit process if this result represents a failure
    def exit_on_failure!
      return self if success?
      exit(exit_code || 1)
    end

    # Chain operations (railway pattern)
    def then
      return self unless success?
      yield
    end

    # Transform success value
    def map
      return self unless success?
      yield stdout
    end

    # Human-readable representation
    def to_s
      if success?
        "Success: #{command.join(' ')}"
      elsif signaled?
        "Killed by signal #{signal_code}: #{command.join(' ')}"
      elsif failed?
        "Failed to start: #{command.join(' ')} (#{exception&.message})"
      else
        "Failed (exit #{exit_code}): #{command.join(' ')}"
      end
    end

    def inspect
      "#<Result #{success? ? 'success' : "exit=#{exit_code}"} cmd=#{command.inspect}>"
    end
  end
end
```

---

## Usage Examples

### With Refinements (Recommended)

```ruby
require 'devex/support'

using Devex::Support::CoreExt::Object
using Devex::Support::CoreExt::String
using Devex::Support::CoreExt::Enumerable

# Now available in this file only
"  ".blank?           # => true
[1,2,3,4,5].median    # => 3
"hello world".wrap(4, 20)
```

### Global Activation (For CLI Tools)

```ruby
require 'devex/support/global'

# All extensions now globally available
# Use sparingly - mainly for CLI entry points
```

### Path Usage

```ruby
path = Path["~/src/project"]
path.r?                    # readable?
path.dir!                  # create if missing
path["**/*.rb"]            # glob
path / "lib" / "foo.rb"    # join

config = Path["config.yml"]
config.read                # file contents
```

### Result Monad

```ruby
result = sh("bundle", "install")

# Pattern 1: Exit on failure
result.exit_on_failure!

# Pattern 2: Check and handle
if result.success?
  puts result.stdout
else
  warn "Failed: #{result.stderr}"
end

# Pattern 3: Railway
sh("lint")
  .then { sh("test") }
  .then { sh("build") }
  .exit_on_failure!
```

---

## What We're NOT Including

### 1. Nilish / Maybe

Ruby's safe navigation (`&.`) handles most cases:

```ruby
# Old way
user.maybe.profile.maybe.avatar_url

# Ruby 2.3+ way
user&.profile&.avatar_url
```

### 2. OrderedHash

Native `Hash` is ordered since Ruby 1.9.

### 3. OStruct Enhancements

Consider using Ruby 3.2+ `Data` class instead:

```ruby
# Ruby 3.2+
Config = Data.define(:name, :version, :debug)
config = Config.new(name: "app", version: "1.0", debug: false)
config.name  # => "app"
```

### 4. Project Root Detection

This is handled by `Devex::CLI#project_root` which is more context-aware.

### 5. Unix Permission Parsing

Rarely needed; use `File::Stat` methods directly.

---

## Open Questions

1. **Refinements vs Global?** Refinements are cleaner but require `using` in each file. For CLI tools, global might be more practical.

2. **Separate gem?** Should this be `devex-support` gem usable independently?

3. **ActiveSupport compatibility?** If ActiveSupport is loaded, should we defer to its implementations?

4. **Statistics in Enumerable?** Or a separate `Devex::Stats` module?

---

## References

- Joseph's shorthand_*.rb scripts: ~/src/tmp/shorthand_{01,02,03}.rb
- [Ruby 3.3 Release Notes](https://www.ruby-lang.org/en/news/2023/12/25/ruby-3-3-0-released/)
- [Ruby 3.4 Release Notes](https://www.ruby-lang.org/en/news/2024/12/25/ruby-3-4-0-released/)
- [Ruby Standard Gems](https://stdgems.org/)
- [What's New in Ruby 3.3](https://blog.saeloun.com/2024/02/12/what-is-new-in-ruby-3-3/)
- ActiveSupport core extensions
- ADR-001: External Command Execution
