# frozen_string_literal: true

require_relative "support/path"
require_relative "dirs"

module Devex
  # Immutable working directory context for tool execution.
  #
  # The working directory is passed through the call tree but cannot be
  # mutated. Child contexts see a new directory but parent is unaffected.
  #
  # Usage:
  #   working_dir  # => current working directory (Path)
  #
  #   within "packages/core" do
  #     working_dir  # => /project/packages/core
  #     run "npm", "test"  # Runs from packages/core
  #   end
  #
  #   working_dir  # => /project (unchanged)
  #
  # See ADR-003 for full specification.
  #
  module WorkingDir
    Path = Support::Path

    # Thread-local working directory stack
    # Each entry is an immutable Path
    @stack       = []
    @stack_mutex = Mutex.new

    class << self
      # Get current working directory
      # Defaults to project_dir if no context has been pushed
      def current = @stack_mutex.synchronize { @stack.last || Dirs.project_dir }

      # Execute a block with a different working directory
      # The working directory is restored after the block completes.
      #
      # @param subdir [String, Path] Directory to change to
      # @yield Block to execute in the new context
      # @return Result of the block
      #
      # @example Relative path
      #   within "packages/web" do
      #     run "npm", "test"
      #   end
      #
      # @example Absolute path
      #   within Path["/tmp/build"] do
      #     run "make"
      #   end
      #
      # @example Using project paths
      #   within prj.test do
      #     run "rake"
      #   end
      #
      def within(subdir)
        new_wd = case subdir
                 when Path     then subdir.absolute? ? subdir : current / subdir
                 when Pathname then subdir.absolute? ? Path.new(subdir) : current / subdir.to_s
                 when String   then subdir.start_with?("/") ? Path[subdir] : current / subdir
                 else
                   raise ArgumentError, "Expected String or Path, got #{subdir.class}"
                 end

        push(new_wd)
        yield
      ensure
        pop
      end

      # Reset the working directory stack (for testing)
      def reset! = @stack_mutex.synchronize { @stack.clear }

      # Get the full stack (for debugging)
      def stack = @stack_mutex.synchronize { @stack.dup }

      # Get the depth of the current context
      def depth = @stack_mutex.synchronize { @stack.size }

      private

      def push(path) = @stack_mutex.synchronize { @stack.push(path.freeze) }

      def pop = @stack_mutex.synchronize { @stack.pop }
    end
  end

  # Mixin module for tools that need working directory support
  module WorkingDirMixin
    # Get current working directory
    def working_dir = WorkingDir.current

    # Execute block in a different working directory
    def within(subdir, &) = WorkingDir.within(subdir, &)
  end
end
