# frozen_string_literal: true

require_relative "devex/version"
require_relative "devex/tool"
require_relative "devex/dsl"
require_relative "devex/loader"
require_relative "devex/cli"

module Devex
  class Error < StandardError; end

  # Project root markers, checked in order
  ROOT_MARKERS = %w[.devex.yml .git tasks].freeze

  # Default tasks directory name
  DEFAULT_TASKS_DIR = "tasks"

  class << self
    # Find the project root by walking up from the given directory
    # looking for root markers (.devex.yml, .git, tasks/)
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

    # Get the tasks directory for a project root
    # Reads from .devex.yml if present, otherwise uses default
    def tasks_dir(project_root)
      return nil unless project_root

      config_file = File.join(project_root, ".devex.yml")
      if File.exist?(config_file)
        require "yaml"
        config = YAML.safe_load(File.read(config_file)) || {}
        tasks_dir_name = config["tasks_dir"] || DEFAULT_TASKS_DIR
      else
        tasks_dir_name = DEFAULT_TASKS_DIR
      end

      dir = File.join(project_root, tasks_dir_name)
      File.directory?(dir) ? dir : nil
    end
  end
end
