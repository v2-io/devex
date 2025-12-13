# frozen_string_literal: true

require_relative "support/path"

module Devex
  # Directory context for devex - where we are, where the project is.
  #
  # These values are set once at dx startup and never change:
  #
  #   invoked_dir   - Where user actually ran `dx` (real cwd at startup)
  #   dest_dir      - Effective start directory (invoked_dir or --dx-from-dir)
  #   project_dir   - Discovered project root (has .git, .dx.yml, etc.)
  #   dx_src_dir    - Devex gem installation (for templates, builtins)
  #
  # See ADR-003 for full specification.
  #
  module Dirs
    Path = Support::Path

    # Project root markers in priority order
    PROJECT_MARKERS = %w[
      .dx.yml
      .dx
      .git
      Gemfile
      Rakefile
      .devex.yml
    ].freeze

    class << self
      # Where the user actually ran `dx`
      # Captured once at startup, never changes
      def invoked_dir
        @invoked_dir ||= Path.pwd
      end

      # Effective start directory (invoked_dir unless overridden)
      # Used as starting point for project discovery
      def dest_dir
        @dest_dir ||= invoked_dir
      end

      # Override dest_dir (called when --dx-from-dir is used)
      # Must be called early, before project_dir is accessed
      def dest_dir=(path)
        raise "Cannot change dest_dir after project_dir is computed" if @project_dir
        @dest_dir = Path[path]
      end

      # Discovered project root directory
      # Searched upward from dest_dir
      def project_dir
        @project_dir ||= discover_project_root
      end

      # Devex gem installation directory
      # Contains templates, builtins, etc.
      def dx_src_dir
        @dx_src_dir ||= Path[File.expand_path("../..", __dir__)]
      end

      # Reset all cached values (for testing)
      def reset!
        @invoked_dir = nil
        @dest_dir = nil
        @project_dir = nil
        @dx_src_dir = nil
      end

      # Check if we're inside a project
      def in_project?
        !!@project_dir || discover_project_root(raise_on_missing: false)
      end

      private

      def discover_project_root(raise_on_missing: true)
        current = dest_dir.exp

        loop do
          # Check each marker
          PROJECT_MARKERS.each do |marker|
            marker_path = current / marker
            return current if marker_path.exist?
          end

          # Move up
          parent = current.parent
          break if parent.to_s == current.to_s # Reached root

          current = parent
        end

        return nil unless raise_on_missing

        # FFF - Fail-Fast with Feedback
        fail_no_project!
      end

      def fail_no_project!
        message = <<~ERR
          ERROR: Not inside a dx project

            Searched from: #{dest_dir}
            Looked for: #{PROJECT_MARKERS.join(", ")}

            To create a new project:
              dx init

            To operate on a different directory:
              dx --dx-from-dir=/path/to/project command

          Exit code: 78 (EX_CONFIG)
        ERR

        # Use Devex.fail! if available, otherwise raise
        if Devex.respond_to?(:fail!)
          Devex.fail!(message, exit_code: 78)
        else
          raise message
        end
      end
    end

    # ─────────────────────────────────────────────────────────────
    # Local dx Delegation
    # ─────────────────────────────────────────────────────────────

    # Check if we should delegate to bundled dx
    # Call early in startup, before any real work
    def self.maybe_delegate_to_local!
      return if ENV["DX_DELEGATED"]
      return unless in_project?

      use_local = project_dir / ".dx-use-local"
      return unless use_local.exist?

      # Delegate: set flag, change to project dir, exec bundled dx
      ENV["DX_DELEGATED"] = "1"
      Dir.chdir(project_dir.to_s)
      exec "bundle", "exec", "dx", *ARGV
    end
  end
end
