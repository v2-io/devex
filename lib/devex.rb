# frozen_string_literal: true

require_relative "devex/version"
require_relative "devex/context"
require_relative "devex/output"
require_relative "devex/template_helpers"
require_relative "devex/tool"
require_relative "devex/dsl"
require_relative "devex/loader"
require_relative "devex/cli"

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
    def gem_root
      @gem_root ||= File.expand_path("../..", __FILE__)
    end

    # Path to the templates directory within the gem
    def templates_path
      @templates_path ||= File.join(File.dirname(__FILE__), "devex", TEMPLATES_DIR)
    end

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
          if File.exist?(marker_path)
            return [dir, marker]
          end
        end

        parent = File.dirname(dir)
        break if parent == dir # reached filesystem root

        dir = parent
      end

      [nil, nil]
    end

    # Get the tools directory for a project root
    # Reads from .dx.yml if present, otherwise uses default
    def tools_dir(project_root)
      return nil unless project_root

      config_file = File.join(project_root, ".dx.yml")
      if File.exist?(config_file)
        require "yaml"
        config = YAML.safe_load(File.read(config_file)) || {}
        tools_dir_name = config["tools_dir"] || DEFAULT_TOOLS_DIR
      else
        tools_dir_name = DEFAULT_TOOLS_DIR
      end

      dir = File.join(project_root, tools_dir_name)
      File.directory?(dir) ? dir : nil
    end
  end
end
