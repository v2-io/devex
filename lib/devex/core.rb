# frozen_string_literal: true

# Devex::Core - The CLI framework without dx-specific configuration.
#
# Use this entry point to build your own CLI application using the devex
# framework. This loads all framework components but does NOT load:
#   - dx-specific builtins (version, test, lint, etc.)
#   - dx-specific configuration (.dx.yml, .dx/ directory conventions)
#
# @example Building a custom CLI
#   require "devex/core"
#
#   config = Devex::Core::Configuration.new(
#     executable_name: "mycli",
#     flag_prefix: "mycli",
#     project_markers: %w[.mycli.yml .git Gemfile],
#     env_prefix: "MYCLI"
#   )
#
#   cli = Devex::Core::CLI.new(config: config)
#   cli.load_tools("/path/to/my/tools")
#   exit cli.run(ARGV)
#
# For the full dx CLI with builtins, use: require "devex"

# Load support library first (no dependencies)
require_relative "support/path"
require_relative "support/ansi"
require_relative "support/core_ext"

# Load version
require_relative "version"

# Load configuration class
require_relative "core/configuration"

# Load framework components in dependency order
require_relative "context"
require_relative "output"
require_relative "template_helpers"
require_relative "exec"       # Must be before tool.rb (ExecutionContext includes Exec)
require_relative "tool"
require_relative "dsl"
require_relative "loader"
require_relative "cli"
require_relative "dirs"
require_relative "project_paths"
require_relative "working_dir"

module Devex
  # Core module - re-exports framework classes for convenient access.
  #
  # All classes are also available directly under Devex:: namespace.
  # The Core module provides a clean namespace for users who want to
  # be explicit about using the framework vs the dx application.
  #
  # Note: Configuration is already defined in core/configuration.rb
  # and is available as Devex::Core::Configuration.
  #
  module Core
    # Re-export key classes at Core level for convenience
    # (Configuration is already defined in core/configuration.rb)
    CLI          = Devex::CLI
    Tool         = Devex::Tool
    Dirs         = Devex::Dirs
    ProjectPaths = Devex::ProjectPaths
    WorkingDir   = Devex::WorkingDir
    Context      = Devex::Context
    Output       = Devex::Output
    Exec         = Devex::Exec

    # Support library
    Path = Devex::Support::Path
    ANSI = Devex::Support::ANSI

    # Version
    VERSION = Devex::VERSION
  end
end
