# frozen_string_literal: true

module Devex
  # Represents a CLI tool/command with its metadata, flags, args, and subtools
  class Tool
    attr_accessor :builtin, :desc, :long_desc, :run_block, :source_code, :source_file, :source_proc
    attr_reader :name, :parent, :subtools, :flags, :args, :mixins

    # Global flag specs that tools cannot override
    # These are handled by CLI before tool flag parsing
    RESERVED_FLAG_SPECS = %w[
      -f --format
      -v --verbose --no-verbose
      -q --quiet --no-quiet
      --color --no-color
      --dx-version --dx-from-dir
    ].freeze

    def initialize(name, parent: nil)
      @name        = name
      @parent      = parent
      @desc        = nil
      @long_desc   = nil
      @flags       = []
      @args        = []
      @subtools    = {}
      @run_block   = nil
      @mixins      = []
      @builtin     = nil # reference to builtin tool if this is an override
      @source_code = nil
      @source_file = nil
      @source_proc = nil
    end

    # Full command path (e.g., ["version", "bump"])
    def full_path
      if parent
        parent.full_path + [name]
      else
        (name ? [name] : [])
      end
    end

    # Full command string (e.g., "version bump")
    def full_name = full_path.join(" ")

    # Define a flag
    # Examples:
    #   flag :verbose, "-v", "--verbose", desc: "Enable verbose output"
    #   flag :file, "-f FILE", "--file=FILE", desc: "Input file"
    def flag(name, *specs, desc: nil, default: nil) = @flags << Flag.new(name, specs, desc: desc, default: default)

    # Check that flag specs don't conflict with global flags (called at execute time)
    def validate_flags!
      @flags.each do |flag|
        flag.specs.each do |spec|
          # Extract the flag part (before space or =)
          flag_part = spec.split(/[\s=]/).first
          if RESERVED_FLAG_SPECS.include?(flag_part)
            raise Error, <<~ERR.chomp
              Tool '#{full_name}': flag '#{flag_part}' conflicts with global flag

              Global flags like #{flag_part} are handled before tool execution.
              Your tool can access the global value via:
                verbose?                 # for -v/--verbose
                global_options[:format]  # for -f/--format
                global_options[:quiet]   # for -q/--quiet

              To fix: remove this flag definition or use a different flag name.
            ERR
          end
        end
      end
    end

    # Define a required positional argument
    def required_arg(name, desc: nil) = @args << Arg.new(name, required: true, desc: desc)

    # Define an optional positional argument
    def optional_arg(name, desc: nil, default: nil) = @args << Arg.new(name, required: false, desc: desc, default: default)

    # Define remaining args (variadic)
    def remaining_args(name, desc: nil) = @args << Arg.new(name, required: false, desc: desc, remaining: true)

    # Add a subtool
    def add_subtool(tool) = @subtools[tool.name] = tool

    # Find a subtool by name
    def subtool(name) = @subtools[name]

    # Include a mixin by name
    def include_mixin(name) = @mixins << name

    # Set builtin reference for override support

    # Parse arguments and execute the tool
    def execute(argv, cli)
      # Check for subcommand first
      if argv.any? && (sub = subtool(argv.first))
        return sub.execute(argv[1..], cli)
      end

      # Validate flags don't conflict with global flags
      validate_flags!

      # Parse flags and args
      context = ExecutionContext.new(self, cli)
      context.parse(argv)

      # Check for required args
      @args.select(&:required).each do |arg|
        raise Error, "Missing required argument: #{arg.name}" unless context.options.key?(arg.name)
      end

      # Execute - re-evaluate source in context so `def run` has access to cli, options, etc.
      if @source_code
        # Re-evaluate the source code in the execution context
        # This makes all def methods available with proper context
        context.instance_eval(@source_code, @source_file || "(tool)")
        if context.respond_to?(:run)
          context.run
        elsif @subtools.any?
          cli.show_help(self)
        else
          raise Error, "Tool '#{full_name}' has no run method"
        end
      elsif @source_proc
        # For nested tools defined with blocks
        context.instance_eval(&@source_proc)
        if context.respond_to?(:run)
          context.run
        elsif @subtools.any?
          cli.show_help(self)
        else
          raise Error, "Tool '#{full_name}' has no run method"
        end
      elsif @run_block
        context.instance_exec(&@run_block)
      elsif @subtools.any?
        cli.show_help(self)
      else
        raise Error, "Tool '#{full_name}' has no implementation"
      end
    end

    # Generate help text
    def help_text(executable_name = "dx")
      lines = []

      # Usage line
      cmd         = [executable_name, *full_path].join(" ")
      usage_parts = [cmd]
      usage_parts << "[OPTIONS]" if @flags.any?
      @args.each do |arg|
        usage_parts << if arg.remaining
                         "[#{arg.name.to_s.upcase}...]"
                       elsif arg.required
                         arg.name.to_s.upcase
                       else
                         "[#{arg.name.to_s.upcase}]"
                       end
      end
      usage_parts << "COMMAND" if @subtools.any?

      lines << "Usage: #{usage_parts.join(' ')}"
      lines << ""

      # Description
      if @desc
        lines << @desc
        lines << ""
      end

      if @long_desc
        lines << @long_desc
        lines << ""
      end

      # Subcommands
      if @subtools.any?
        lines << "Commands:"
        max_name = @subtools.keys.map(&:length).max
        @subtools.sort.each do |name, tool|
          desc_text = tool.desc || ""
          lines << "  #{name.ljust(max_name)}  #{desc_text}"
        end
        lines << ""
      end

      # Flags
      if @flags.any?
        lines << "Options:"
        @flags.each do |flag|
          flag_str = flag.specs.join(", ")
          desc_text = flag.desc || ""
          lines << "  #{flag_str}"
          lines << "      #{desc_text}" if desc_text != ""
        end
        lines << ""
      end

      # Args
      if @args.any?
        lines << "Arguments:"
        @args.each do |arg|
          name_str = arg.name.to_s.upcase
          name_str += "..." if arg.remaining
          req_str = arg.required ? "(required)" : "(optional)"
          desc_text = arg.desc ? " - #{arg.desc}" : ""
          lines << "  #{name_str} #{req_str}#{desc_text}"
        end
        lines << ""
      end

      lines.join("\n")
    end
  end

  # Represents a flag definition
  class Flag
    attr_reader :name, :specs, :desc, :default

    def initialize(name, specs, desc: nil, default: nil)
      @name    = name
      @specs   = specs
      @desc    = desc
      @default = default
    end

    # Does this flag take an argument?
    def takes_argument? = @specs.any? { |s| s.include?(" ") || s.include?("=") }
  end

  # Represents a positional argument definition
  class Arg
    attr_reader :name, :required, :desc, :default, :remaining

    def initialize(name, required:, desc: nil, default: nil, remaining: false)
      @name      = name
      @required  = required
      @desc      = desc
      @default   = default
      @remaining = remaining
    end
  end

  # Execution context - the 'self' when a tool runs
  class ExecutionContext
    include Exec  # All tools have access to cmd, capture, spawn, etc.

    attr_reader :options, :cli

    def initialize(tool, cli)
      @tool    = tool
      @cli     = cli
      @options = {}

      # Set defaults for flags
      tool.flags.each do |flag|
        @options[flag.name] = if !flag.default.nil?
                                flag.default
                              elsif !flag.takes_argument?
                                false  # Boolean flags default to false
                              end
      end
      tool.args.each do |arg|
        @options[arg.name] = arg.default unless arg.default.nil?
      end
    end

    # Parse argv into options, return unparsed remainder
    def parse(argv)
      require "optparse"

      parser = OptionParser.new do |opts|
        tool.flags.each do |flag|
          if flag.takes_argument?
            opts.on(*flag.specs) { |v| @options[flag.name] = v }
          else
            opts.on(*flag.specs) { @options[flag.name] = true }
          end
        end
      end

      # Parse, collecting non-flag args
      remaining = parser.parse(argv)

      # Assign positional args
      tool.args.each do |arg|
        if arg.remaining
          @options[arg.name] = remaining
          remaining = []
        elsif remaining.any?
          @options[arg.name] = remaining.shift
        end
      end

      remaining
    end

    # DSL methods - no-ops during execution (already captured during load)
    def desc(_text)                      = nil
    def long_desc(_text)                 = nil
    def flag(_name, *_specs, **_kwargs)  = nil
    def required_arg(_name, **_kwargs)   = nil
    def optional_arg(_name, **_kwargs)   = nil
    def remaining_args(_name, **_kwargs) = nil
    def include(_name)                   = nil
    def to_run(&)                  = nil

    # We need special handling because `tool` is both an attr_reader
    # and a DSL method. Override the reader to handle both cases.
    def tool(name = nil, &block)
      if name.nil? && block.nil?
        # Called as attr_reader - return the Tool object
        @tool
      else
        # Called as DSL method - no-op during execution (already captured)
        nil
      end
    end

    # Access options as methods
    def method_missing(name, *args, &)
      if @options.key?(name)
        @options[name]
      else
        super
      end
    end

    def respond_to_missing?(name, include_private = false) = @options.key?(name) || super

    # Access to builtin if this is an override
    def builtin = tool.builtin ? ExecutionContext.new(tool.builtin, cli) : nil

    # Run another tool by path
    def run_tool(*path) = cli.run([*path.map(&:to_s)])

    # Exit with code
    def exit(code = 0) = Kernel.exit(code)

    # --- Global options access ---

    # Access CLI's global options
    def global_options = cli.global_options

    # Is verbose mode enabled? Returns verbosity level (0 = off, 1+ = on)
    def verbose = global_options[:verbose]

    def verbose? = verbose > 0

    # Is quiet mode enabled?
    def quiet? = global_options[:quiet]

    # Get the effective output format
    # Tool's --format flag takes precedence, then global --format, then context-based default
    def output_format
      # Tool-specific format (from options[:format]) takes precedence
      return options[:format].to_sym if options[:format]

      # Global format
      return global_options[:format].to_sym if global_options[:format]

      # Context-based default
      Devex::Context.agent_mode? ? :json : :text
    end
  end
end
