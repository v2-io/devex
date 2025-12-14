# frozen_string_literal: true

module Devex
  # DSL context for defining tools in task files
  class DSL
    attr_reader :tool

    def initialize(tool) = @tool = tool

    def desc(text) = @tool.desc = text

    def long_desc(text) = @tool.long_desc = text

    def flag(name, *specs, desc: nil, default: nil) = @tool.flag(name, *specs, desc: desc, default: default)

    def required_arg(name, desc: nil) = @tool.required_arg(name, desc: desc)

    def optional_arg(name, desc: nil, default: nil) = @tool.optional_arg(name, desc: desc, default: default)

    def remaining_args(name, desc: nil) = @tool.remaining_args(name, desc: desc)

    def include(name) = @tool.include_mixin(name)

    def tool(name, &block)
      subtool = Tool.new(name, parent: @tool)
      if block
        # Capture the block source location for later re-evaluation
        subtool.source_file = block.source_location[0]
        subtool.source_proc = block
      end
      @tool.add_subtool(subtool)
      subtool
    end

    def to_run(&block) = @tool.run_block = block
  end

  # Evaluates task files and captures tool definitions
  module TaskFileDSL
    def self.evaluate(tool, code, filename)
      # Store the source for later execution
      tool.source_code = code
      tool.source_file = filename

      # Parse the DSL parts (desc, flags, etc.) but don't execute run yet
      context = DSLContext.new(tool)
      context.instance_eval(code, filename)

      tool
    end
  end

  # Context for parsing DSL declarations (not execution)
  class DSLContext
    def initialize(tool) = @tool = tool

    def desc(text) = @tool.desc = text

    def long_desc(text) = @tool.long_desc = text

    def flag(name, *specs, desc: nil, default: nil) = @tool.flag(name, *specs, desc: desc, default: default)

    def required_arg(name, desc: nil) = @tool.required_arg(name, desc: desc)

    def optional_arg(name, desc: nil, default: nil) = @tool.optional_arg(name, desc: desc, default: default)

    def remaining_args(name, desc: nil) = @tool.remaining_args(name, desc: desc)

    def include(name) = @tool.include_mixin(name)

    def tool(name, &block)
      subtool = Tool.new(name, parent: @tool)
      if block
        # For nested tools, we need to capture the block's source
        # Since we can't easily get block source, we'll use a different strategy:
        # Evaluate the block in a new DSLContext to get the DSL parts,
        # and mark that it has a run method defined
        nested_context = DSLContext.new(subtool)
        nested_context.instance_eval(&block)
        subtool.source_proc = block
      end
      @tool.add_subtool(subtool)
      subtool
    end

    def to_run(&block) = @tool.run_block = block

    # Capture def statements - they become the tool's methods
    # We use method_missing to collect method names, but can't capture the bodies
    # Instead, we mark that the tool has a run method and will re-eval at runtime
    def method_missing(name, *args, &)
      # Silently ignore - methods will be available at runtime via re-eval
    end

    def respond_to_missing?(_name, _include_private = false) = true
  end
end
