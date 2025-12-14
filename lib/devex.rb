# frozen_string_literal: true

require_relative "devex/version"
require_relative "devex/context"
require_relative "devex/output"
require_relative "devex/template_helpers"
require_relative "devex/exec"  # Must be before tool.rb (ExecutionContext includes Exec)
require_relative "devex/tool"
require_relative "devex/dsl"
require_relative "devex/loader"
require_relative "devex/cli"
require_relative "devex/dirs"
require_relative "devex/project_paths"
require_relative "devex/working_dir"

module Devex
  class Error < StandardError; end

  # Project root markers, checked in order
  ROOT_MARKERS = %w[.dx.yml .dx .git tools].freeze

  # Default tools directory name
  DEFAULT_TOOLS_DIR = "tools"

  # Templates directory name within the gem
  TEMPLATES_DIR = "templates"

  class << self
    # Root directory of the devex gem itself
    # Used for locating built-in templates, builtins, etc.
    def gem_root = @gem_root ||= File.expand_path('..', __dir__)

    # Path to the templates directory within the gem
    def templates_path = @templates_path ||= File.join(File.dirname(__FILE__), "devex", TEMPLATES_DIR)

    # Load and render a template from the gem's templates directory
    # Returns the rendered string
    #
    # If locals hash is provided, creates a binding with TemplateHelpers
    # and all locals available. If a binding is provided directly, uses that.
    def render_template(name, locals_or_binding = nil)
      path = template_path(name)
      raise Error, "Template not found: #{name}" unless File.exist?(path)

      bind = if locals_or_binding.is_a?(Hash)
               TemplateHelpers.template_binding(locals_or_binding)
             elsif locals_or_binding.is_a?(Binding)
               locals_or_binding
             else
               TemplateHelpers.template_binding
             end

      Output.render_template_file(path, bind)
    end

    # Get full path to a template file
    # Adds .erb extension if not present
    def template_path(name)
      name = "#{name}.erb" unless name.end_with?(".erb")
      File.join(templates_path, name)
    end

    # Find the project root by walking up from the given directory
    # looking for root markers (.dx.yml, .git, tools/)
    #
    # Returns [root_path, marker_found] or [nil, nil] if not found
    def find_project_root(from = Dir.pwd)
      dir = File.expand_path(from)

      loop do
        ROOT_MARKERS.each do |marker|
          marker_path = File.join(dir, marker)
          return [dir, marker] if File.exist?(marker_path)
        end

        parent = File.dirname(dir)
        break if parent == dir # reached filesystem root

        dir = parent
      end

      [nil, nil]
    end

    # Get the tools directory for a project root
    # Reads from .dx.yml or .dx/config.yml if present, otherwise uses default
    def tools_dir(project_root)
      return nil unless project_root

      config         = load_config(project_root)
      tools_dir_name = config["tools_dir"] || DEFAULT_TOOLS_DIR

      dir = File.join(project_root, tools_dir_name)
      File.directory?(dir) ? dir : nil
    end

    # Load project configuration from .dx.yml or .dx/config.yml
    # Returns empty hash if no config file exists
    # Raises Error if both .dx.yml and .dx/ directory exist (conflict)
    def load_config(project_root)
      return {} unless project_root

      dx_dir = File.join(project_root, ".dx")
      dx_yml = File.join(project_root, ".dx.yml")

      dx_dir_exists = File.directory?(dx_dir)
      dx_yml_exists = File.exist?(dx_yml)

      # Conflict check: both simple and organized mode markers present
      if dx_dir_exists && dx_yml_exists
        raise Error, <<~ERR.chomp
          Conflicting dx configuration

            Found both:
              .dx.yml   (simple mode config)
              .dx/      (organized mode directory)

            Choose one:
              • Remove .dx.yml to use organized mode (.dx/config.yml)
              • Remove .dx/ directory to use simple mode (.dx.yml)
        ERR
      end

      config_file = if dx_dir_exists
                      File.join(dx_dir, "config.yml")
                    else
                      dx_yml
                    end

      if File.exist?(config_file)
        require "yaml"
        YAML.safe_load_file(config_file) || {}
      else
        {}
      end
    end
  end
end
