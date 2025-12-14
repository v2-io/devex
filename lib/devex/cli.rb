# frozen_string_literal: true

module Devex
  # Main CLI class - entry point for dx command
  class CLI
    HELP_FLAGS = %w[-h -? --help].freeze
    HELP_WORD  = "help"

    # Universal flags available to all commands
    UNIVERSAL_FLAGS = {
      format:   ["-f", "--format=FORMAT"],
      verbose:  ["-v", "--verbose"],
      quiet:    ["-q", "--quiet"],
      no_color: ["--no-color"],
      color:    ["--color=MODE"]
    }.freeze

    # Project operation flag (shown in help)
    PROJECT_FLAGS = {
      dx_from_dir: ["--dx-from-dir=PATH"]
    }.freeze

    # Hidden debug flags for testing/reproduction (not shown in help)
    # These set Context overrides directly
    DEBUG_FLAGS = {
      dx_force_color:    ["--dx-force-color"],
      dx_no_color:       ["--dx-no-color"],
      dx_agent_mode:     ["--dx-agent-mode"],
      dx_no_agent_mode:  ["--dx-no-agent-mode"],
      dx_interactive:    ["--dx-interactive"],
      dx_no_interactive: ["--dx-no-interactive"],
      dx_env:            ["--dx-env=ENV"]
    }.freeze

    attr_reader :root_tool, :executable_name, :project_root, :global_options

    def initialize(executable_name: "dx")
      @executable_name = executable_name
      @root_tool       = Tool.new(nil) # root has no name
      @builtin_root    = Tool.new(nil)
      @mixins          = {}
      @project_root    = nil
      @global_options = {
        format:  nil,
        verbose: 0,
        quiet:   false
      }
    end

    # Main entry point
    def run(argv = ARGV)
      argv = argv.dup

      # Extract and apply global flags first (before help or tool resolution)
      argv, show_dx_version = extract_global_flags(argv)

      # --dx-version shows devex gem version and exits
      if show_dx_version
        output_dx_version
        return 0
      end

      # Transform help anywhere in args to --help at the right place
      argv, show_help = extract_help(argv)

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
        # Track task invocation in context
        task_name = tool.full_name.empty? ? "root" : tool.full_name
        Context.with_task(task_name) do
          tool.execute(remaining_argv, self)
        end
        0
      rescue Error => e
        Output.error(e.message)
        1
      rescue OptionParser::ParseError => e
        Output.error(e.message)
        1
      end
    end

    # Load built-in tools from gem
    def load_builtins
      builtin_dir = File.join(__dir__, "builtins")
      Loader.load_directory(builtin_dir, @builtin_root, @mixins)
    end

    # Load project-specific tools
    def load_project_tools(project_root)
      @project_root = project_root

      # Add project lib/ to load path so tools can `require` without `require_relative`
      add_project_lib_to_load_path(project_root)

      tools_dir = Devex.tools_dir(project_root)
      Loader.load_directory(tools_dir, @root_tool, @mixins) if tools_dir
    end

    # Add project's lib/ directory to $LOAD_PATH if it exists.
    # This allows tools to use `require "myproject/foo"` instead of require_relative.
    def add_project_lib_to_load_path(project_root)
      return unless project_root

      lib_dir = File.join(project_root, "lib")
      return unless File.directory?(lib_dir)
      return if $LOAD_PATH.include?(lib_dir)

      $LOAD_PATH.unshift(lib_dir)
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
      help_text = tool.help_text(@executable_name)

      # Append global options section if showing root help
      help_text += global_options_help if tool == @root_tool

      puts help_text
    end

    private

    # Extract global flags from argv, apply Context overrides
    # Returns [remaining_argv, show_dx_version]
    def extract_global_flags(argv)
      remaining       = []
      show_dx_version = false

      i = 0
      while i < argv.length
        arg      = argv[i]
        consumed = false

        # Check universal flags
        case arg
        when "--dx-version"
          show_dx_version = true
          consumed        = true
        when "-f", "--format"
          # -f FORMAT (two args)
          @global_options[:format] = argv[i + 1]
          i        += 1
          consumed = true
        when /^--format=(.+)$/
          @global_options[:format] = ::Regexp.last_match(1)
          consumed = true
        when "-v", "--verbose"
          @global_options[:verbose] += 1
          consumed                  = true
        when "--no-verbose"
          @global_options[:verbose] = 0
          consumed                  = true
        when "-q", "--quiet"
          @global_options[:quiet] = true
          consumed                 = true
        when "--no-quiet"
          @global_options[:quiet] = false
          consumed                 = true
        when "--no-color"
          Context.set_override(:color, false)
          consumed = true
        when "--color=always"
          Context.set_override(:color, true)
          consumed = true
        when "--color=never"
          Context.set_override(:color, false)
          consumed = true
        when "--color=auto"
          Context.clear_override(:color)
          consumed = true
        when /^--color=(.+)$/
          # Unknown color mode, ignore
          consumed = true
        end

        # Check hidden debug flags (not in help)
        unless consumed
          case arg
          when "--dx-force-color"
            Context.set_override(:color, true)
            consumed = true
          when "--dx-no-color"
            Context.set_override(:color, false)
            consumed = true
          when "--dx-agent-mode"
            Context.set_override(:agent_mode, true)
            consumed = true
          when "--dx-no-agent-mode"
            Context.set_override(:agent_mode, false)
            consumed = true
          when "--dx-interactive"
            Context.set_override(:interactive, true)
            consumed = true
          when "--dx-no-interactive"
            Context.set_override(:interactive, false)
            consumed = true
          when /^--dx-env=(.+)$/
            Context.set_override(:env, ::Regexp.last_match(1))
            consumed = true
          when "--dx-ci"
            Context.set_override(:ci, true)
            consumed = true
          when "--dx-no-ci"
            Context.set_override(:ci, false)
            consumed = true
          when "--dx-terminal"
            Context.set_override(:terminal, true)
            consumed = true
          when "--dx-no-terminal"
            Context.set_override(:terminal, false)
            consumed = true
          end
        end

        remaining << arg unless consumed
        i += 1
      end

      [remaining, show_dx_version]
    end

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
      tool      = @root_tool
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

    # Generate help text for global options
    def global_options_help
      <<~HELP

        Global Options:
          -f, --format=FORMAT   Output format (text, json, yaml)
          -v, --verbose         Increase verbosity (can be repeated)
          -q, --quiet           Suppress non-error output
          --no-color            Disable colored output
          --color=MODE          Color mode: auto, always, never
          --dx-version          Show devex gem version
          --dx-from-dir=PATH    Operate on project at PATH
      HELP
    end

    # Output devex gem version (not project version)
    def output_dx_version
      if @global_options[:format] == "json"
        require "json"
        puts JSON.generate({ name: "devex", version: VERSION })
      else
        puts "devex #{VERSION}"
      end
    end
  end
end
