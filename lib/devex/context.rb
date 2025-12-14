# frozen_string_literal: true

module Devex
  # Runtime context detection for devex tasks.
  #
  # Detects whether we're running in a terminal, CI, agent mode, etc.
  # This informs output formatting, interactivity, and behavior.
  #
  # Detection hierarchy (highest to lowest priority):
  #   1. Explicit environment variables (DX_AGENT_MODE, DX_BATCH, etc.)
  #   2. CI environment detection
  #   3. Terminal/stream auto-detection
  #
  # Also tracks:
  #   - Task invocation call tree (which task invoked which)
  #   - Environment (development, test, staging, production)
  #
  # See docs/ref/agent-mode.md and docs/ref/io-handling.md for rationale.
  #
  module Context
    # Environment variable names we check
    ENV_AGENT_MODE  = %w[DX_AGENT_MODE DEVEX_AGENT_MODE].freeze
    ENV_BATCH       = %w[DX_BATCH DEVEX_BATCH].freeze
    ENV_INTERACTIVE = %w[DX_INTERACTIVE DEVEX_INTERACTIVE].freeze
    ENV_NO_COLOR  = %w[NO_COLOR DX_NO_COLOR].freeze
    ENV_FORCE_COLOR = %w[FORCE_COLOR DX_FORCE_COLOR].freeze

    # Environment detection (Rails-style)
    ENV_ENVIRONMENT     = %w[DX_ENV DEVEX_ENV RAILS_ENV RACK_ENV].freeze
    DEFAULT_ENVIRONMENT = "development"

    # Canonical environment names and their aliases
    ENVIRONMENT_ALIASES = {
      "dev"     => "development",
      "develop" => "development",
      "test"    => "test",
      "testing" => "test",
      "stage"   => "staging",
      "stg"     => "staging",
      "prod"    => "production",
      "live"    => "production"
    }.freeze

    # Call tree tracking - passed via environment between processes
    ENV_CALL_TREE = "DX_CALL_TREE"

    # Common CI environment variables
    CI_ENV_VARS = %w[
      CI
      CONTINUOUS_INTEGRATION
      GITHUB_ACTIONS
      GITLAB_CI
      CIRCLECI
      TRAVIS
      JENKINS_URL
      BUILDKITE
      DRONE
      TEAMCITY_VERSION
    ].freeze

    # Thread-local call stack for tracking task invocations within a process
    # Format: Array of task names, e.g., ["pre-commit", "test"]
    @call_stack       = []
    @call_stack_mutex = Mutex.new

    # Programmatic overrides for testing and debugging
    # Keys: :agent_mode, :interactive, :color, :ci, :terminal, :env
    @overrides       = {}
    @overrides_mutex = Mutex.new

    class << self
      # Is stdout connected to a terminal?
      def stdout_tty? = $stdout.tty?

      # Is stderr connected to a terminal?
      def stderr_tty? = $stderr.tty?

      # Is stdin connected to a terminal?
      def stdin_tty? = $stdin.tty?

      # Are we in a full interactive terminal? (all three streams are ttys)
      def terminal?
        override = override_or(:terminal)
        return override unless override.nil?

        stdin_tty? && stdout_tty? && stderr_tty?
      end

      # Are stdout and stderr merged (pointing to same file descriptor)?
      # This happens with 2>&1 redirection, common in agent/scripted usage.
      #
      # IMPORTANT: When both streams are TTYs pointing to the same terminal device,
      # that's normal terminal behavior, NOT merging. We only consider streams
      # "merged" when they're redirected to the same non-TTY destination.
      def streams_merged?
        # If either is a TTY, streams aren't "merged" in the problematic sense
        # (a terminal naturally has stdout/stderr going to the same device)
        return false if $stdout.tty? || $stderr.tty?

        return false unless $stdout.respond_to?(:stat) && $stderr.respond_to?(:stat)

        begin
          stdout_stat = $stdout.stat
          stderr_stat = $stderr.stat
          stdout_stat.dev == stderr_stat.dev && stdout_stat.ino == stderr_stat.ino
        rescue IOError, Errno::EBADF
          # If we can't stat the streams, assume not merged
          false
        end
      end

      # Is agent mode explicitly enabled via environment?
      def agent_mode_env? = ENV_AGENT_MODE.any? { |var| truthy_env?(var) }

      # Is batch mode explicitly enabled via environment?
      def batch_mode_env? = ENV_BATCH.any? { |var| truthy_env?(var) }

      # Is interactive mode explicitly forced via environment?
      def interactive_forced? = ENV_INTERACTIVE.any? { |var| truthy_env?(var) }

      # Are we running in a CI environment?
      def ci?
        override = override_or(:ci)
        return override unless override.nil?

        CI_ENV_VARS.any? { |var| ENV.key?(var) && ENV[var] != "" && ENV[var] != "false" }
      end

      # Is color output explicitly disabled?
      def no_color? = ENV_NO_COLOR.any? { |var| ENV.key?(var) }

      # Is color output explicitly forced on?
      def force_color? = ENV_FORCE_COLOR.any? { |var| truthy_env?(var) }

      # Is data being piped in or out?
      # True if stdin is not a tty (data piped in) OR stdout is not a tty (data piped out)
      def piped? = !stdin_tty? || !stdout_tty?

      # --- Composite detection methods ---

      # Should we behave as if an AI agent is invoking us?
      # True if:
      #   - Agent mode explicitly set, OR
      #   - Streams are merged (2>&1), OR
      #   - Not a terminal AND not explicitly interactive
      def agent_mode?
        override = override_or(:agent_mode)
        return override unless override.nil?

        return true if agent_mode_env?
        return false if interactive_forced?
        return true if streams_merged?
        return true if !terminal? && !ci? # Non-tty, non-CI likely means agent

        false
      end

      # Should we allow interactive prompts and rich output?
      # True only when we have a real terminal and nothing forces non-interactive
      def interactive?
        override = override_or(:interactive)
        return override unless override.nil?

        return true if interactive_forced?
        return false if agent_mode_env? || batch_mode_env? || ci?

        terminal?
      end

      # Should we use colors in output?
      def color?
        override = override_or(:color)
        return override unless override.nil?

        return false if no_color?
        return true if force_color?

        # Default: color if stdout is a tty and not in agent mode
        stdout_tty? && !agent_mode?
      end

      # --- Environment detection (Rails-style) ---

      # Get the current environment name (development, test, staging, production)
      # Checks DX_ENV, DEVEX_ENV, RAILS_ENV, RACK_ENV in that order
      def env = @env ||= detect_environment

      # Reset cached environment (useful for testing)
      def reset_env! = @env = nil

      def development? = env == "development"

      def test? = env == "test"

      def staging? = env == "staging"

      def production? = env == "production"

      # Is this a "safe" environment where destructive operations are okay?
      # Development and test are considered safe; staging and production are not.
      def safe_env? = %w[development test].include?(env)

      # --- Call tree tracking ---

      # Get the full call tree as an array of task names
      # Combines inherited tree from parent process (via env) with current process stack
      def call_tree = inherited_tree + current_call_stack

      # Get just the current process's call stack
      def current_call_stack = @call_stack_mutex.synchronize { @call_stack.dup }

      # Get the call tree inherited from parent process via environment
      def inherited_tree
        tree_str = ENV.fetch(ENV_CALL_TREE, nil)
        return [] if tree_str.nil? || tree_str.empty?

        tree_str.split(":")
      end

      # Is this task being invoked from another task?
      def invoked_from_task? = !call_tree.empty?

      # Get the name of the task that invoked this one (immediate parent)
      def invoking_task
        tree = call_tree
        tree[-1] if tree.any?
      end

      # Get the root task that started the chain
      def root_task
        tree = call_tree
        tree[0] if tree.any?
      end

      # Push a task onto the call stack (called when a task starts)
      def push_task(task_name) = @call_stack_mutex.synchronize { @call_stack.push(task_name) }

      # Pop a task from the call stack (called when a task completes)
      def pop_task = @call_stack_mutex.synchronize { @call_stack.pop }

      # Execute a block with a task on the call stack
      def with_task(task_name)
        push_task(task_name)
        yield
      ensure
        pop_task
      end

      # Reset the call stack (useful for testing)
      def reset_call_stack! = @call_stack_mutex.synchronize { @call_stack.clear }

      # Summary of current context for debugging/logging
      def summary
        {
          terminal:          terminal?,
          stdin_tty:         stdin_tty?,
          stdout_tty:        stdout_tty?,
          stderr_tty:        stderr_tty?,
          streams_merged:    streams_merged?,
          ci:                ci?,
          piped:             piped?,
          agent_mode:        agent_mode?,
          interactive:       interactive?,
          color:             color?,
          env:               env,
          call_tree:         call_tree,
          invoked_from_task: invoked_from_task?
        }
      end

      # Machine-readable context for passing to subprocesses
      # Include call tree so child processes know their invocation chain
      def to_env
        tree = call_tree
        {
          "DX_AGENT_MODE"  => agent_mode? ? "1" : "0",
          "DX_INTERACTIVE" => interactive? ? "1" : "0",
          "DX_CI"          => ci? ? "1" : "0",
          "DX_ENV"         => env,
          ENV_CALL_TREE    => tree.any? ? tree.join(":") : nil
        }.compact
      end

      # --- Programmatic overrides for testing ---

      # Set an override value
      # Valid keys: :agent_mode, :interactive, :color, :ci, :terminal, :env
      def set_override(key, value) = @overrides_mutex.synchronize { @overrides[key] = value }

      # Clear a specific override
      def clear_override(key) = @overrides_mutex.synchronize { @overrides.delete(key) }

      # Clear all overrides
      def clear_all_overrides! = @overrides_mutex.synchronize { @overrides.clear }

      # Get current overrides (for debugging)
      def overrides = @overrides_mutex.synchronize { @overrides.dup }

      # Execute a block with temporary overrides
      # Example: Context.with_overrides(agent_mode: true, color: false) { ... }
      def with_overrides(**overrides_hash)
        old_overrides = @overrides_mutex.synchronize { @overrides.dup }
        @overrides_mutex.synchronize { @overrides.merge!(overrides_hash) }
        yield
      ensure
        @overrides_mutex.synchronize do
          @overrides.clear
          @overrides.merge!(old_overrides)
        end
      end

      private

      # Check for override first, then fall back to detection
      def override_or(key)
        @overrides_mutex.synchronize do
          return @overrides[key] if @overrides.key?(key)
        end
        nil
      end

      def truthy_env?(var)
        val = ENV.fetch(var, nil)
        val && !val.empty? && val != "0" && val.downcase != "false"
      end

      def detect_environment
        # Check override first
        override = override_or(:env)
        return override if override

        ENV_ENVIRONMENT.each do |var|
          val = ENV.fetch(var, nil)
          next if val.nil? || val.empty?

          # Normalize the value
          normalized = val.downcase.strip
          return ENVIRONMENT_ALIASES.fetch(normalized, normalized)
        end

        DEFAULT_ENVIRONMENT
      end
    end
  end
end
