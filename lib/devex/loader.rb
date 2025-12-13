# frozen_string_literal: true

module Devex
  # Loads tool definitions from task files
  class Loader
    INDEX_FILE = ".index.rb"

    # Load all tools from a directory into a root tool
    #
    # Directory structure maps to tool hierarchy:
    #   tools/test.rb           -> dx test
    #   tools/version.rb        -> dx version (with nested tools defined inside)
    #   tools/docs/             -> dx docs (if .index.rb exists) or namespace
    #   tools/docs/generate.rb  -> dx docs generate
    #
    def self.load_directory(dir, root_tool, mixins = {})
      return unless dir && File.directory?(dir)

      loader = new(dir, root_tool, mixins)
      loader.load
    end

    def initialize(dir, root_tool, mixins = {})
      @dir = dir
      @root_tool = root_tool
      @mixins = mixins
    end

    def load
      # First, load index file if present (defines mixins and root tool config)
      index_file = File.join(@dir, INDEX_FILE)
      load_index(index_file) if File.exist?(index_file)

      # Then load all .rb files (excluding index)
      Dir.glob(File.join(@dir, "*.rb")).sort.each do |file|
        next if File.basename(file) == INDEX_FILE

        load_tool_file(file, @root_tool)
      end

      # Load subdirectories
      Dir.glob(File.join(@dir, "*")).sort.each do |path|
        next unless File.directory?(path)
        next if File.basename(path).start_with?(".")

        load_subdirectory(path, @root_tool)
      end
    end

    private

    def load_index(file)
      code = File.read(file)
      context = IndexDSL.new(@root_tool, @mixins)
      context.instance_eval(code, file)
    end

    def load_tool_file(file, parent)
      name = File.basename(file, ".rb")
      tool = Tool.new(name, parent: parent)

      code = File.read(file)
      TaskFileDSL.evaluate(tool, code, file)

      parent.add_subtool(tool)
    end

    def load_subdirectory(dir, parent)
      name = File.basename(dir)
      tool = Tool.new(name, parent: parent)

      # Check for index file in subdirectory
      index_file = File.join(dir, INDEX_FILE)
      if File.exist?(index_file)
        code = File.read(index_file)
        TaskFileDSL.evaluate(tool, code, index_file)
      end

      # Load .rb files in subdirectory
      Dir.glob(File.join(dir, "*.rb")).sort.each do |file|
        next if File.basename(file) == INDEX_FILE

        load_tool_file(file, tool)
      end

      # Recurse into nested subdirectories
      Dir.glob(File.join(dir, "*")).sort.each do |path|
        next unless File.directory?(path)
        next if File.basename(path).start_with?(".")

        load_subdirectory(path, tool)
      end

      parent.add_subtool(tool) if tool.desc || tool.subtools.any? || tool.run_block
    end
  end

  # DSL for index files - can define mixins
  class IndexDSL
    def initialize(tool, mixins)
      @tool = tool
      @mixins = mixins
      @dsl = DSL.new(tool)
    end

    # Define a mixin
    def mixin(name, &block)
      @mixins[name.to_s] = block
    end

    # Forward to regular DSL
    def desc(text)
      @dsl.desc(text)
    end

    def long_desc(text)
      @dsl.long_desc(text)
    end

    def flag(name, *specs, **kwargs)
      @dsl.flag(name, *specs, **kwargs)
    end

    def required_arg(name, **kwargs)
      @dsl.required_arg(name, **kwargs)
    end

    def optional_arg(name, **kwargs)
      @dsl.optional_arg(name, **kwargs)
    end

    def tool(name, &block)
      @dsl.tool(name, &block)
    end

    def to_run(&block)
      @dsl.to_run(&block)
    end

    # Capture run method
    def run
      # Will be captured by method definition
    end

    # Allow arbitrary methods (for mixin definitions)
    def method_missing(name, *args, &block)
      # Ignore - these are likely mixin method definitions
    end

    def respond_to_missing?(name, include_private = false)
      true
    end
  end
end
