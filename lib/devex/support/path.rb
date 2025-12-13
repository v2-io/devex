# frozen_string_literal: true

require "pathname"
require "fileutils"
require "tmpdir"

module Devex
  module Support
    # Enhanced Pathname with ergonomic shortcuts for CLI development.
    #
    # Usage:
    #   path = Path["~/src/project"]
    #   path = "~/src/project".to_p  # With String refinement
    #   path = Path.pwd
    #
    #   # Joining with / operator
    #   path / "lib" / "foo.rb"
    #
    #   # Permission checks
    #   path.r?   # readable?
    #   path.w?   # writable?
    #   path.rw?  # readable and writable?
    #
    #   # Existence
    #   path.exist?
    #   path.missing?
    #   path.existence  # Returns self or nil
    #
    #   # Relative paths
    #   path.rel                      # Relative to pwd with ~/
    #   path.rel(from: project_root)  # Relative to specific dir
    #   path.short                    # Shortest representation
    #
    #   # Globbing
    #   path["**/*.rb"]
    #
    #   # Safe directory creation
    #   path.dir!   # Creates parent dirs, returns self
    #
    #   # File I/O
    #   path.read
    #   path.write(content)
    #   path.append(content)
    #   path.atomic_write(content)
    #
    class Path < Pathname
      class << self
        # Construct from string: Path["~/src/project"]
        def [](path)
          new(expand_user(path.to_s))
        end

        # Current working directory
        def pwd
          new(Dir.pwd)
        end
        alias_method :cwd, :pwd
        alias_method :getwd, :pwd

        # Home directory
        def home
          new(Dir.home)
        end

        # Temporary directory
        def tmp
          new(Dir.tmpdir)
        end
        alias_method :tmpdir, :tmp

        private

        # Expand ~ and ~user in path strings
        def expand_user(path)
          return path unless path.start_with?("~")
          File.expand_path(path)
        end
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
        return self if args.empty?
        self.class.new(super(*args.map(&:to_s)))
      end

      # ─────────────────────────────────────────────────────────────
      # Permission Checks
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
      # Memoized Expansions
      # ─────────────────────────────────────────────────────────────

      # Expanded path (memoized)
      def exp
        @exp ||= self.class.new(expand_path)
      end

      # Real path with fallback to expanded (memoized, safe)
      def real
        @real ||= begin
          self.class.new(realpath)
        rescue Errno::ENOENT
          exp
        end
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
        from = self.class.new(from&.to_s || Dir.pwd)
        result = exp.relative_path_from(from.exp)
        result = self.class.new(result)

        if home && Dir.home && result.to_s.start_with?(Dir.home)
          result = self.class.new(result.to_s.sub(Dir.home, "~"))
        end
        result
      rescue ArgumentError
        # Can't compute relative path (different drives on Windows, etc.)
        if home && Dir.home
          self.class.new(to_s.sub(Dir.home, "~"))
        else
          self
        end
      end

      # Shortest representation of path
      def short(from: nil)
        from = self.class.new(from&.to_s || Dir.pwd)
        candidates = []

        # Try relative from base
        begin
          candidates << exp.relative_path_from(from.exp)
        rescue ArgumentError
          # Ignore - can't compute relative
        end

        # Try with ~ substitution
        if Dir.home
          home_sub = to_s.sub(Dir.home, "~")
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
        base = directory? ? self : dirname
        flags = include_dotfiles ? File::FNM_DOTMATCH : 0
        Pathname.glob((base / pattern).to_s, flags).map { |p| self.class.new(p) }
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
        directory? ? exp : self.class.new(dirname)
      end

      # Create directory (and parents) if missing, return self
      # Safe - returns nil on error instead of raising
      def dir!
        target = directory? ? self : dir
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
        File.read(to_s, **opts)
      end
      alias_method :contents, :read

      # Read as lines
      def lines(chomp: true)
        File.readlines(to_s, chomp: chomp)
      end

      # Write contents (creates parent directories)
      def write(content, encoding: nil)
        dir!
        opts = encoding ? { encoding: encoding } : {}
        File.write(to_s, content, **opts)
        self
      end

      # Append to file
      def append(content)
        dir!
        File.write(to_s, content, mode: "a")
        self
      end

      # Atomic write (write to temp, then rename)
      def atomic_write(content)
        dir!
        require "tempfile"
        Tempfile.create([basename.to_s, extname], dirname.to_s) do |temp|
          temp.binmode
          temp.write(content)
          temp.close
          FileUtils.mv(temp.path, to_s)
        end
        self
      end

      # ─────────────────────────────────────────────────────────────
      # Modification Time Comparisons
      # ─────────────────────────────────────────────────────────────

      def newer_than?(other)
        other = self.class[other] unless other.is_a?(Pathname)
        return true unless other.exist?
        return false unless exist?
        mtime > other.mtime
      end

      def older_than?(other)
        other = self.class[other] unless other.is_a?(Pathname)
        return false unless other.exist?
        return true unless exist?
        mtime < other.mtime
      end

      # ─────────────────────────────────────────────────────────────
      # Extension Manipulation
      # ─────────────────────────────────────────────────────────────

      # Replace extension: path.with_ext(".md")
      def with_ext(new_ext)
        new_ext = ".#{new_ext}" unless new_ext.to_s.start_with?(".")
        self.class.new(sub_ext(new_ext.to_s))
      end

      # Remove extension
      def without_ext
        self.class.new(to_s.sub(/#{Regexp.escape(extname)}$/, ""))
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
      # Inspection
      # ─────────────────────────────────────────────────────────────

      def inspect
        "#<Path:#{to_s}>"
      end

      # ─────────────────────────────────────────────────────────────
      # String-like Behavior
      # ─────────────────────────────────────────────────────────────

      # Delegate string methods to to_s
      def method_missing(method, *args, &block)
        if to_s.respond_to?(method)
          result = to_s.send(method, *args, &block)
          # Return Path if result looks like a path
          if result.is_a?(String) && result.include?("/")
            self.class.new(result)
          else
            result
          end
        else
          super
        end
      end

      def respond_to_missing?(method, include_private = false)
        to_s.respond_to?(method, include_private) || super
      end
    end
  end
end
