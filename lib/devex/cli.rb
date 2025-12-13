# frozen_string_literal: true

module Devex
  # Main CLI class - entry point for dx command
  class CLI
    HELP_FLAGS = %w[-h -? --help].freeze
    HELP_WORD = "help"

    attr_reader :root_tool, :executable_name, :project_root

    def initialize(executable_name: "dx")
      @executable_name = executable_name
      @root_tool = Tool.new(nil) # root has no name
      @builtin_root = Tool.new(nil)
      @mixins = {}
      @project_root = nil
    end

    # Main entry point
    def run(argv = ARGV)
      # Transform help anywhere in args to --help at the right place
      argv, show_help = extract_help(argv.dup)

      # Handle version flag at root level
      if argv.empty? || argv == ["--version"] || argv == ["-v"]
        if argv.include?("--version") || argv.include?("-v")
          puts "devex #{VERSION}"
          return 0
        end
      end

      # Find the tool to execute
      tool, remaining_argv = resolve_tool(argv)

      if show_help
        show_help(tool)
        return 0
      end

      if tool.nil?
        show_help(@root_tool)
        return 1
      end

      begin
        tool.execute(remaining_argv, self)
        0
      rescue Error => e
        $stderr.puts "Error: #{e.message}"
        1
      rescue OptionParser::ParseError => e
        $stderr.puts "Error: #{e.message}"
        1
      end
    end

    # Load built-in tools from gem
    def load_builtins
      builtin_dir = File.join(__dir__, "builtins")
      Loader.load_directory(builtin_dir, @builtin_root, @mixins)
    end

    # Load project-specific tools
    def load_project_tasks(project_root)
      @project_root = project_root
      tasks_dir = Devex.tasks_dir(project_root)
      Loader.load_directory(tasks_dir, @root_tool, @mixins) if tasks_dir
    end

    # Merge builtin tools (project tools take precedence)
    def merge_builtins
      @builtin_root.subtools.each do |name, builtin_tool|
        if @root_tool.subtools[name]
          # Project overrides builtin - store reference for super-like behavior
          @root_tool.subtools[name].builtin = builtin_tool
        else
          # No override - use builtin directly
          @root_tool.add_subtool(builtin_tool)
        end
      end
    end

    # Display help for a tool
    def show_help(tool)
      puts tool.help_text(@executable_name)
    end

    private

    # Extract help indicators from argv, return [cleaned_argv, show_help]
    #
    # Handles:
    #   dx help           -> [], true (help for root)
    #   dx help foo       -> [foo], true
    #   dx foo help       -> [foo], true
    #   dx foo --help     -> [foo], true
    #   dx foo -h         -> [foo], true
    #   dx -?             -> [], true
    #
    def extract_help(argv)
      show_help = false

      # Check for help flags
      HELP_FLAGS.each do |flag|
        if argv.include?(flag)
          argv.delete(flag)
          show_help = true
        end
      end

      # Check for 'help' as a word (not a flag)
      if argv.include?(HELP_WORD)
        argv.delete(HELP_WORD)
        show_help = true
      end

      [argv, show_help]
    end

    # Resolve a tool from argv
    # Returns [tool, remaining_argv]
    def resolve_tool(argv)
      tool = @root_tool
      remaining = argv.dup

      while remaining.any?
        candidate = remaining.first

        # Stop if it looks like a flag
        break if candidate.start_with?("-")

        # Try to find subtool
        subtool = tool.subtool(candidate)
        break unless subtool

        tool = subtool
        remaining.shift
      end

      [tool, remaining]
    end
  end
end
