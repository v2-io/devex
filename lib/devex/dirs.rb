# frozen_string_literal: true

require_relative "support/path"

module Devex
  # Directory context for a CLI application.
  #
  # Holds the directory state for a CLI invocation:
  #   - invoked_dir: Where user actually ran the command
  #   - dest_dir: Effective start directory (invoked_dir or overridden)
  #   - project_dir: Discovered project root
  #   - src_dir: Framework gem installation directory
  #
  # Instance-based for Core usage, with module methods for backward compatibility.
  #
  # @example Core usage (recommended)
  #   config = Devex::Core::Configuration.new(project_markers: %w[.mycli.yml .git])
  #   dirs = Devex::Dirs.new(config: config)
  #   dirs.project_dir  # => discovered project root
  #
  # @example Backward-compatible module usage
  #   Devex::Dirs.project_dir  # uses default dx configuration
  #
  class Dirs
    Path = Support::Path

    # Default project markers
    # Includes dx-specific markers since this is the devex gem.
    # Core users can override via Configuration.project_markers.
    DEFAULT_PROJECT_MARKERS = %w[.dx.yml .dx .git Gemfile Rakefile .devex.yml].freeze

    # @param config [Core::Configuration, nil] configuration (uses defaults if nil)
    # @param invoked_from [String] directory where command was invoked (default: pwd)
    # @param dest_dir [String, nil] override for dest_dir (e.g., from --flag-from-dir)
    # @param src_dir [String, nil] framework source directory (defaults to devex gem)
    def initialize(config: nil, invoked_from: Dir.pwd, dest_dir: nil, src_dir: nil)
      @config      = config
      @invoked_dir = Path[invoked_from].exp
      @dest_dir    = dest_dir ? Path[dest_dir].exp : @invoked_dir
      @src_dir     = src_dir ? Path[src_dir] : Path[File.expand_path("../..", __dir__)]
      @project_dir = nil  # lazy
    end

    # Where the user actually ran the command (captured at startup)
    # @return [Path]
    attr_reader :invoked_dir

    # Effective start directory (invoked_dir unless overridden)
    # @return [Path]
    attr_reader :dest_dir

    # Framework source directory (for templates, builtins, etc.)
    # @return [Path]
    attr_reader :src_dir

    # Project markers to search for
    # @return [Array<String>]
    def project_markers
      @config&.project_markers || DEFAULT_PROJECT_MARKERS
    end

    # Discovered project root directory
    # Searched upward from dest_dir using project_markers
    # @param raise_on_missing [Boolean] raise error if not found (default: true)
    # @return [Path, nil]
    def project_dir(raise_on_missing: true)
      @project_dir ||= discover_project_root(raise_on_missing: raise_on_missing)
    end

    # Check if we're inside a project (without raising)
    # @return [Boolean]
    def in_project?
      !!@project_dir || !!discover_project_root(raise_on_missing: false)
    end

    # Reset cached state (for testing)
    def reset!
      @project_dir = nil
    end

    private

    def discover_project_root(raise_on_missing: true)
      current = @dest_dir

      loop do
        project_markers.each do |marker|
          marker_path = current / marker
          return current if marker_path.exist?
        end

        parent = current.parent
        break if parent.to_s == current.to_s  # Reached filesystem root

        current = parent
      end

      return nil unless raise_on_missing

      fail_no_project!
    end

    def fail_no_project!
      exe_name = @config&.executable_name || "cli"
      from_flag = @config ? @config.flag("from_dir") : "--from-dir"

      message = <<~ERR
        ERROR: Not inside a project

          Searched from: #{@dest_dir}
          Looked for: #{project_markers.join(', ')}

          To create a new project:
            #{exe_name} init

          To operate on a different directory:
            #{exe_name} #{from_flag}=/path/to/project command

        Exit code: 78 (EX_CONFIG)
      ERR

      raise message
    end

    # ─────────────────────────────────────────────────────────────
    # Module-Level API (Backward Compatibility)
    # ─────────────────────────────────────────────────────────────
    #
    # These class methods provide backward compatibility with the
    # original module-based API. They delegate to a thread-local
    # default instance.
    #
    class << self
      # Get or create the default Dirs instance for this thread
      # @return [Dirs]
      def default
        Thread.current[:devex_dirs] ||= new_default
      end

      # Set the default Dirs instance (used by devex.rb to configure for dx)
      # @param dirs [Dirs]
      def default=(dirs)
        Thread.current[:devex_dirs] = dirs
      end

      # Reset the default instance (for testing)
      def reset!
        Thread.current[:devex_dirs] = nil
        # Also clear any instance state if there was one
        Thread.current[:devex_dirs_dest_override] = nil
      end

      # Backward-compatible: set dest_dir before project discovery
      # Must be called early, before project_dir is accessed
      def dest_dir=(path)
        if Thread.current[:devex_dirs]&.instance_variable_get(:@project_dir)
          raise "Cannot change dest_dir after project_dir is computed"
        end

        Thread.current[:devex_dirs_dest_override] = path
        # Clear default so it gets recreated with new dest_dir
        Thread.current[:devex_dirs] = nil
      end

      # Delegate instance methods to default
      def invoked_dir = default.invoked_dir
      def dest_dir = default.dest_dir
      def project_dir = default.project_dir
      def src_dir = default.src_dir
      def dx_src_dir = default.src_dir  # Backward-compatible alias
      def in_project? = default.in_project?

      private

      def new_default
        dest_override = Thread.current[:devex_dirs_dest_override]
        new(dest_dir: dest_override)
      end
    end

    # ─────────────────────────────────────────────────────────────
    # Delegation Support
    # ─────────────────────────────────────────────────────────────

    # Check if we should delegate to a bundled/local version of the CLI
    # Call early in startup, before any real work.
    #
    # @param config [Core::Configuration] configuration with delegation settings
    # @param argv [Array<String>] command line arguments to pass through
    # @return [void] (exits process if delegating)
    def self.maybe_delegate_to_local!(config: nil, argv: ARGV)
      delegation_file = config&.delegation_file
      return unless delegation_file

      delegation_env = config.env_var(:delegated)
      return if ENV[delegation_env]

      dirs = config ? new(config: config) : default
      return unless dirs.in_project?

      use_local = dirs.project_dir / delegation_file
      return unless use_local.exist?

      # Delegate: set flag, change to project dir, exec bundled version
      ENV[delegation_env] = "1"
      Dir.chdir(dirs.project_dir.to_s)
      exec "bundle", "exec", config.executable_name, *argv
    end
  end
end
