# frozen_string_literal: true

module Devex
  module Core
    # Configuration for a CLI application built on Devex::Core.
    #
    # Holds all the customizable values that distinguish one CLI from another:
    # executable name, flag prefixes, project markers, environment variable
    # prefixes, and path conventions.
    #
    # @example Building a custom CLI
    #   config = Devex::Core::Configuration.new(
    #     executable_name: "mycli",
    #     project_markers: %w[.mycli.yml .git Gemfile],
    #     env_prefix: "MYCLI"
    #   )
    #   cli = Devex::Core::CLI.new(config: config)
    #
    class Configuration
      # Name of the executable (used in help text, error messages)
      # @return [String]
      attr_accessor :executable_name

      # Prefix for framework flags (--{prefix}-version, --{prefix}-agent-mode)
      # Defaults to executable_name if not set
      # @return [String]
      attr_writer :flag_prefix

      # Files/directories that indicate project root, checked in order
      # @return [Array<String>]
      attr_accessor :project_markers

      # Primary config file name (e.g., ".dx.yml", ".mycli.yml")
      # Set to nil to disable config file support
      # @return [String, nil]
      attr_accessor :config_file

      # Directory for organized mode (e.g., ".dx", ".mycli")
      # Set to nil to disable organized mode support
      # @return [String, nil]
      attr_accessor :organized_dir

      # Default tools directory name
      # @return [String]
      attr_accessor :tools_dir

      # Prefix for environment variables ({PREFIX}_AGENT_MODE, {PREFIX}_ENV)
      # Defaults to executable_name.upcase if not set
      # @return [String]
      attr_writer :env_prefix

      # Custom path conventions for ProjectPaths
      # Merged with defaults; keys are symbols, values are strings or arrays
      # @return [Hash{Symbol => String, Array<String>}]
      attr_accessor :path_conventions

      # File that triggers delegation to bundled version (e.g., ".dx-use-local")
      # Set to nil to disable delegation support
      # @return [String, nil]
      attr_accessor :delegation_file

      def initialize(
        executable_name: "cli",
        flag_prefix: nil,
        project_markers: %w[.git Gemfile Rakefile],
        config_file: nil,
        organized_dir: nil,
        tools_dir: "tools",
        env_prefix: nil,
        path_conventions: {},
        delegation_file: nil
      )
        @executable_name  = executable_name
        @flag_prefix      = flag_prefix
        @project_markers  = project_markers
        @config_file      = config_file
        @organized_dir    = organized_dir
        @tools_dir        = tools_dir
        @env_prefix       = env_prefix
        @path_conventions = path_conventions
        @delegation_file  = delegation_file
      end

      # Flag prefix, defaulting to executable_name
      # @return [String]
      def flag_prefix
        @flag_prefix || executable_name
      end

      # Environment variable prefix, defaulting to executable_name.upcase
      # @return [String]
      def env_prefix
        @env_prefix || executable_name.upcase.tr("-", "_")
      end

      # Generate an environment variable name with this config's prefix
      # @param name [String, Symbol] variable name (e.g., :agent_mode)
      # @return [String] full env var name (e.g., "DX_AGENT_MODE")
      def env_var(name)
        "#{env_prefix}_#{name.to_s.upcase}"
      end

      # Generate a flag name with this config's prefix
      # @param name [String, Symbol] flag name (e.g., :version)
      # @return [String] full flag name (e.g., "--dx-version")
      def flag(name)
        "--#{flag_prefix}-#{name.to_s.tr('_', '-')}"
      end

      # Duplicate this configuration with overrides
      # @param overrides [Hash] values to override
      # @return [Configuration] new configuration instance
      def with(**overrides)
        self.class.new(
          executable_name:  overrides.fetch(:executable_name, executable_name),
          flag_prefix:      overrides.fetch(:flag_prefix, @flag_prefix),
          project_markers:  overrides.fetch(:project_markers, project_markers.dup),
          config_file:      overrides.fetch(:config_file, config_file),
          organized_dir:    overrides.fetch(:organized_dir, organized_dir),
          tools_dir:        overrides.fetch(:tools_dir, tools_dir),
          env_prefix:       overrides.fetch(:env_prefix, @env_prefix),
          path_conventions: overrides.fetch(:path_conventions, path_conventions.dup),
          delegation_file:  overrides.fetch(:delegation_file, delegation_file)
        )
      end

      # Freeze this configuration (and nested structures)
      # @return [self]
      def freeze
        @project_markers.freeze
        @path_conventions.freeze
        super
      end
    end
  end
end
