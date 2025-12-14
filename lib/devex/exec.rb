# frozen_string_literal: true

require_relative "exec/result"
require_relative "exec/controller"

module Devex
  # External command execution with automatic environment orchestration.
  #
  # This module provides the primary interface for running external commands
  # from devex tools. All methods handle the environment stack automatically:
  #
  #   [dotenv] [mise exec --] [bundle exec] command
  #
  # This means `run "rspec"` automatically:
  # - Activates mise versions if .mise.toml or .tool-versions present
  # - Runs through bundle exec if Gemfile present and command looks like a gem
  # - Cleans RUBYOPT/BUNDLE_* from devex's own bundler context
  #
  # Dotenv requires explicit opt-in:
  #   run "rspec", dotenv: true
  #
  # Wrapper control:
  #   run "rspec"                 # auto-detect mise and bundle
  #   run "rspec", mise: false    # skip mise wrapping
  #   run "rspec", bundle: false  # skip bundle exec
  #   run "rspec", raw: true      # skip all wrappers
  #   run "rspec", dotenv: true   # explicitly enable dotenv
  #
  # See ADR-001-external-commands-v2.md for full specification.
  #
  # @example Basic usage
  #   include Devex::Exec
  #
  #   run "bundle", "install"
  #   run("test").exit_on_failure!
  #
  #   if run? "which", "rubocop"
  #     run "rubocop", "--autocorrect"
  #   end
  #
  #   result = capture "git", "rev-parse", "HEAD"
  #   puts result.stdout.strip
  #
  module Exec
    # ─────────────────────────────────────────────────────────────
    # Core Commands
    # ─────────────────────────────────────────────────────────────

    # Run a command, streaming output, waiting for completion.
    #
    # This is the workhorse method. Output streams to terminal by default.
    # Returns a Result object for inspection; never raises on non-zero exit.
    #
    # @param cmd [Array<String>] Command and arguments
    # @param env [Hash] Additional environment variables
    # @param chdir [String, Path] Working directory
    # @param raw [Boolean] Skip environment stack entirely (no wrappers)
    # @param bundle [Symbol, Boolean] :auto (default), true, or false
    # @param mise [Symbol, Boolean] :auto (default), true, or false
    # @param dotenv [Boolean] false (default), true to enable dotenv wrapper
    # @param clean_env [Boolean] Clean devex's bundler pollution (default: true)
    # @param timeout [Float, nil] Seconds before killing
    # @param out [Symbol] :inherit (default), :capture, :null
    # @param err [Symbol] :inherit (default), :capture, :null, [:child, :out]
    # @return [Result] Execution result
    #
    # @example Simple
    #   run "bundle", "install"
    #
    # @example Check result
    #   result = run "make", "test"
    #   exit 1 if result.failed?
    #
    # @example Chain with early exit
    #   run("lint").then { run("test") }.exit_on_failure!
    #
    # @note Use `cmd` alias in tools to avoid conflict with `def run` entry point
    #
    def run(*cmd, **) = execute_command(cmd, **)

    # Alias for `run` - use this in tools to avoid conflict with `def run`
    alias cmd run

    # Test if a command succeeds (exit code 0).
    #
    # Output is discarded. Returns boolean directly.
    #
    # @param cmd [Array<String>] Command and arguments
    # @return [Boolean] true if exit code is 0
    #
    # @example
    #   if run? "which", "rubocop"
    #     run "rubocop"
    #   end
    #
    def run?(*cmd, **) = execute_command(cmd, **, out: :null, err: :null).success?

    # Alias for `run?` - use this in tools to avoid conflict with `def run`
    alias cmd? run?

    # Run a command and capture its output.
    #
    # Output is collected into Result.stdout and Result.stderr
    # instead of streaming to terminal.
    #
    # @param cmd [Array<String>] Command and arguments
    # @return [Result] Result with .stdout and .stderr populated
    #
    # @example
    #   result = capture "git", "rev-parse", "HEAD"
    #   commit = result.stdout.strip
    #
    def capture(*cmd, **) = execute_command(cmd, **, out: :capture, err: :capture)

    # Start a command in the background without waiting.
    #
    # Returns immediately with a Controller for managing the process.
    # By default, stdout/stderr go to /dev/null (configurable).
    #
    # @param cmd [Array<String>] Command and arguments
    # @param name [String, nil] Optional identifier
    # @param stdin [Symbol] :null (default), :pipe, :inherit
    # @param stdout [Symbol] :null (default), :pipe, :inherit
    # @param stderr [Symbol] :null (default), :pipe, :inherit
    # @return [Controller] Handle for the background process
    #
    # @example
    #   server = spawn "rails", "server"
    #   # ... do other work ...
    #   server.kill(:TERM)
    #   server.result
    #
    def spawn(*cmd, name: nil, stdin: :null, stdout: :null, stderr: :null, **)
      spawn_command(cmd, name: name, stdin: stdin, stdout: stdout, stderr: stderr, **)
    end

    # Replace the current process with a command.
    #
    # This never returns. The current Ruby process is replaced entirely.
    # The bang (!) indicates this is irreversible.
    #
    # @param cmd [Array<String>] Command and arguments
    # @return [void] Never returns
    #
    # @example
    #   exec! "vim", filename
    #   # This line never executes
    #
    def exec!(*cmd, **)
      prepared = prepare_command(cmd, **)
      Kernel.exec(prepared[:env], *prepared[:command], **prepared[:spawn_opts])
    end

    # ─────────────────────────────────────────────────────────────
    # Shell Commands
    # ─────────────────────────────────────────────────────────────

    # Run a command through the shell.
    #
    # Use this when you need shell features: pipes, globs, variables.
    # The string is passed to /bin/sh -c "...".
    #
    # @param command_string [String] Shell command
    # @return [Result] Execution result
    #
    # @example
    #   shell "grep TODO **/*.rb | wc -l"
    #   shell "echo $HOME"
    #
    # @note Security: Never interpolate untrusted input
    #
    def shell(command_string, **) = execute_command(["/bin/sh", "-c", command_string], **, shell: true)

    # Test if a shell command succeeds.
    #
    # @param command_string [String] Shell command
    # @return [Boolean] true if exit code is 0
    #
    # @example
    #   if shell? "command -v docker"
    #     shell "docker compose up -d"
    #   end
    #
    def shell?(command_string, **) = shell(command_string, **, out: :null, err: :null).success?

    # ─────────────────────────────────────────────────────────────
    # Specialized Commands
    # ─────────────────────────────────────────────────────────────

    # Run Ruby with clean environment.
    #
    # Uses the project's Ruby version (via mise if configured).
    # Cleans RUBYOPT and bundler pollution.
    #
    # @param args [Array<String>] Arguments to ruby
    # @return [Result] Execution result
    #
    # @example
    #   ruby "-e", "puts RUBY_VERSION"
    #   ruby "script.rb", "--verbose"
    #
    def ruby(*args, **) = execute_command(["ruby", *args], **, clean_env: true)

    # Run another dx tool programmatically.
    #
    # Propagates call tree so child tool knows it was invoked from parent.
    # Inherits verbosity and format settings.
    #
    # @param tool_name [String] Name of the tool to run
    # @param args [Array<String>] Arguments for the tool
    # @param capture [Boolean] Capture output instead of streaming
    # @return [Result] Execution result
    #
    # @example
    #   tool "lint", "--fix"
    #   tool "version", capture: true
    #
    def tool(tool_name, *args, capture: false, **opts)
      # Propagate call tree
      call_tree    = ENV.fetch("DX_CALL_TREE", "")
      current_tool = ENV.fetch("DX_CURRENT_TOOL", "")
      new_tree     = call_tree.empty? ? current_tool : "#{call_tree}:#{current_tool}"

      env = opts[:env] || {}
      env = env.merge(
        "DX_CALL_TREE"         => new_tree,
        "DX_INVOKED_FROM_TOOL" => "1"
      )

      cmd = ["dx", tool_name, *args]
      if capture
        execute_command(cmd, **opts, env: env, out: :capture, err: :capture)
      else
        execute_command(cmd, **opts, env: env)
      end
    end

    # Test if a tool succeeds.
    #
    # @param tool_name [String] Name of the tool to run
    # @param args [Array<String>] Arguments for the tool
    # @return [Boolean] true if exit code is 0
    #
    def tool?(tool_name, *, **) = tool(tool_name, *, **, capture: true).success?

    private

    # ─────────────────────────────────────────────────────────────
    # Command Execution Engine
    # ─────────────────────────────────────────────────────────────

    def execute_command(cmd, **opts)
      prepared   = prepare_command(cmd, **opts)
      start_time = Time.now

      begin
        stdout_data, stderr_data, status = run_with_streams(prepared)
        duration = Time.now - start_time

        Result.from_status(
          status,
          command:  prepared[:original_command],
          duration: duration,
          stdout:   stdout_data,
          stderr:   stderr_data,
          options:  opts
        )
      rescue Errno::ENOENT, Errno::EACCES => e
        Result.from_exception(
          e,
          command:  prepared[:original_command],
          duration: Time.now - start_time,
          options:  opts
        )
      end
    end

    def spawn_command(cmd, name:, stdin:, stdout:, stderr:, **opts)
      prepared = prepare_command(cmd, **opts)

      spawn_opts  = prepared[:spawn_opts].dup
      stdin_pipe  = nil
      stdout_pipe = nil
      stderr_pipe = nil

      # Configure stdin
      case stdin
      when :null then spawn_opts[:in] = "/dev/null"
      when :inherit then spawn_opts[:in] = $stdin
      when :pipe
        stdin_read, stdin_write = IO.pipe
        spawn_opts[:in] = stdin_read
        stdin_pipe = stdin_write
      end

      # Configure stdout
      case stdout
      when :null then spawn_opts[:out] = "/dev/null"
      when :inherit then spawn_opts[:out] = $stdout
      when :pipe
        stdout_read, stdout_write = IO.pipe
        spawn_opts[:out] = stdout_write
        stdout_pipe = stdout_read
      end

      # Configure stderr
      case stderr
      when :null then spawn_opts[:err] = "/dev/null"
      when :inherit then spawn_opts[:err] = $stderr
      when :pipe
        stderr_read, stderr_write = IO.pipe
        spawn_opts[:err] = stderr_write
        stderr_pipe = stderr_read
      when Array
        # [:child, :out] merges stderr into stdout
        spawn_opts[:err] = stderr if stderr[0] == :child
      end

      pid = Process.spawn(prepared[:env], *prepared[:command], **spawn_opts)

      # Close parent's copy of write ends
      stdin_read&.close
      stdout_write&.close
      stderr_write&.close

      Controller.new(
        pid:     pid,
        command: prepared[:original_command],
        name:    name,
        stdin:   stdin_pipe,
        stdout:  stdout_pipe,
        stderr:  stderr_pipe,
        options: opts
      )
    end

    def run_with_streams(prepared)
      opts     = prepared[:spawn_opts]
      out_mode = prepared[:out_mode]
      err_mode = prepared[:err_mode]
      timeout  = prepared[:timeout]

      stdout_data = nil
      stderr_data = nil

      case [out_mode, err_mode]
      when [:inherit, :inherit]
        # Simple case: just run the command
        pid    = Process.spawn(prepared[:env], *prepared[:command], **opts)
        status = wait_with_timeout(pid, timeout, prepared[:original_command])

      when [:capture, :capture]
        # Capture both streams
        stdout_data, stderr_data, status = capture_streams(prepared, timeout)

      when [:null, :null]
        # Discard both
        opts   = opts.merge(out: "/dev/null", err: "/dev/null")
        pid    = Process.spawn(prepared[:env], *prepared[:command], **opts)
        status = wait_with_timeout(pid, timeout, prepared[:original_command])

      else
        # Mixed modes - use Open3
        stdout_data, stderr_data, status = capture_streams(prepared, timeout)
        stdout_data = nil if out_mode == :null
        stderr_data = nil if err_mode == :null
      end

      [stdout_data, stderr_data, status]
    end

    def capture_streams(prepared, timeout)
      require "open3"

      stdout_data = +""
      stderr_data = +""

      Open3.popen3(prepared[:env], *prepared[:command], **prepared[:spawn_opts]) do |stdin, stdout, stderr, wait_thr|
        stdin.close

        # Read both streams (could be improved with select for large outputs)
        threads = []
        threads << Thread.new { stdout_data << stdout.read }
        threads << Thread.new { stderr_data << stderr.read }

        if timeout
          deadline = Time.now + timeout
          remaining = timeout
          loop do
            if threads.all?(&:stop?)
              threads.each(&:join)
              break
            end

            remaining = deadline - Time.now
            if remaining <= 0
              begin
                Process.kill(:TERM, wait_thr.pid)
              rescue StandardError
                nil
              end
              sleep 0.1
              begin
                Process.kill(:KILL, wait_thr.pid)
              rescue StandardError
                nil
              end
              threads.each do |t|
                t.kill
              rescue StandardError
                nil
              end
              return [stdout_data, stderr_data, build_timeout_status(wait_thr)]
            end

            sleep 0.05
          end
        else
          threads.each(&:join)
        end

        [stdout_data, stderr_data, wait_thr.value]
      end
    end

    def wait_with_timeout(pid, timeout, _command)
      return Process.wait2(pid)[1] unless timeout

      deadline = Time.now + timeout
      loop do
        result, status = Process.wait2(pid, Process::WNOHANG)
        return status if result

        remaining = deadline - Time.now
        if remaining <= 0
          begin
            Process.kill(:TERM, pid)
          rescue StandardError
            nil
          end
          sleep 0.1
          begin
            Process.kill(:KILL, pid)
          rescue StandardError
            nil
          end
          _, status = Process.wait2(pid)
          return build_timeout_status_from_status(status)
        end

        sleep([0.05, remaining].min)
      end
    end

    def build_timeout_status(wait_thr)
      wait_thr.value
    rescue StandardError
      # Fake a timed-out status
      TimeoutStatus.new
    end

    def build_timeout_status_from_status(_status) = TimeoutStatus.new

    # Minimal status object for timeout cases
    class TimeoutStatus
      def pid;        0; end
      def exited?;    false; end
      def exitstatus; nil; end
      def signaled?;  true; end
      def termsig;    9; end # SIGKILL
    end

    # ─────────────────────────────────────────────────────────────
    # Command Preparation
    # ─────────────────────────────────────────────────────────────

    def prepare_command(cmd, **opts)
      cmd              = cmd.flatten.map(&:to_s)
      original_command = cmd.dup

      env        = (opts[:env] || {}).transform_keys(&:to_s).transform_values(&:to_s)
      spawn_opts = {}

      # Working directory
      if opts[:chdir]
        chdir = opts[:chdir]
        chdir = chdir.to_s if chdir.respond_to?(:to_s) && !chdir.is_a?(String)
        spawn_opts[:chdir] = chdir
      end

      # Environment stack (unless raw mode)
      env, cmd = apply_environment_stack(env, cmd, opts) unless opts[:raw]

      {
        env:              env,
        command:          cmd,
        original_command: original_command,
        spawn_opts:       spawn_opts,
        out_mode:         opts.fetch(:out, :inherit),
        err_mode:         opts.fetch(:err, :inherit),
        timeout:          opts[:timeout]
      }
    end

    # Apply the environment wrapper chain in order:
    #   [dotenv] [mise exec --] [bundle exec] command
    #
    # Each wrapper is applied from inside-out, so we process:
    #   1. bundle exec (innermost, around the command)
    #   2. mise exec -- (wraps bundle exec)
    #   3. dotenv (outermost wrapper)
    #
    def apply_environment_stack(env, cmd, opts)
      # Clean devex's bundler pollution (default: true unless clean_env: false)
      env = clean_bundler_env(env) if opts.fetch(:clean_env, true) && defined?(Bundler)

      # Bundle exec wrapping (if appropriate)
      cmd = maybe_bundle_exec(cmd, opts) unless opts[:shell] || opts[:bundle] == false

      # Mise exec wrapping (if detected, unless disabled)
      cmd = maybe_mise_exec(cmd, opts) unless opts[:shell]

      # Dotenv wrapping (explicit opt-in only)
      cmd = with_dotenv(cmd, opts) if opts[:dotenv] == true

      [env, cmd]
    end

    def clean_bundler_env(env)
      # Keys that bundler sets that we want to clear
      bundler_keys = %w[
        BUNDLE_GEMFILE
        BUNDLE_BIN_PATH
        BUNDLE_PATH
        BUNDLER_VERSION
        BUNDLER_SETUP
        RUBYOPT
        RUBYLIB
        GEM_HOME
        GEM_PATH
      ]

      # Start with current env, remove bundler pollution
      clean = ENV.to_h.dup
      bundler_keys.each { |k| clean.delete(k) }

      # Apply user's env additions
      clean.merge(env)
    end

    def maybe_bundle_exec(cmd, opts)
      return cmd if opts[:bundle] == false
      return cmd if cmd.first == "bundle"
      return cmd unless gemfile_present?

      # Check if this looks like a gem command
      if opts[:bundle] == true || looks_like_gem_command?(cmd.first)
        ["bundle", "exec", *cmd]
      else
        cmd
      end
    end

    def gemfile_present?
      # Cache this for the process lifetime

      # Check in working directory or project root
      @gemfile_present ||= File.exist?("Gemfile") ||
                           (defined?(Devex::Dirs) && Devex::Dirs.in_project? &&
                            File.exist?(File.join(Devex::Dirs.project_dir.to_s, "Gemfile")))
    end

    # Heuristic: is this likely a Ruby gem executable?
    def looks_like_gem_command?(cmd)
      # Common gem commands
      gem_commands = %w[
        rake rspec rubocop standardrb steep rbs
        rails sidekiq puma unicorn thin
        bundler bundle
        erb rdoc ri
        yard
      ]

      return true if gem_commands.include?(cmd)

      # Check if it's in bundle's bin stubs
      # This is a simplification; could check actual Gemfile.lock
      false
    end

    # ─────────────────────────────────────────────────────────────
    # Mise Wrapper
    # ─────────────────────────────────────────────────────────────

    # Wrap command with `mise exec --` if mise is detected and enabled.
    #
    # @param cmd [Array<String>] Command to potentially wrap
    # @param opts [Hash] Options (mise: :auto, true, or false)
    # @return [Array<String>] Command, possibly wrapped
    #
    def maybe_mise_exec(cmd, opts)
      return cmd if opts[:mise] == false
      return cmd if cmd.first == "mise"

      # :auto (default) - detect; true - always use mise
      use_mise = case opts[:mise]
                 when true then true
                 when false then false
                 else mise_detected?  # :auto or nil
                 end

      return cmd unless use_mise

      # Wrap with mise exec --
      ["mise", "exec", "--", *cmd]
    end

    # Check if mise is configured in the project.
    # Caches the result for the process lifetime.
    #
    def mise_detected?
      # Use :unset sentinel since nil is a valid cache value
      @mise_detected = detect_mise_files if @mise_detected.nil?
      @mise_detected
    end

    def detect_mise_files
      # Check in current directory first
      return true if File.exist?(".mise.toml") || File.exist?(".tool-versions")

      # Check in project root if we're in a project
      if defined?(Devex::Dirs) && Devex::Dirs.in_project?
        project_dir = Devex::Dirs.project_dir.to_s
        File.exist?(File.join(project_dir, ".mise.toml")) ||
          File.exist?(File.join(project_dir, ".tool-versions"))
      else
        false
      end
    end

    # ─────────────────────────────────────────────────────────────
    # Dotenv Wrapper
    # ─────────────────────────────────────────────────────────────

    # Wrap command with `dotenv` to load .env files.
    # Only used when explicitly requested (dotenv: true).
    #
    # @param cmd [Array<String>] Command to wrap
    # @param opts [Hash] Options (unused currently, for future .env path override)
    # @return [Array<String>] Command wrapped with dotenv
    #
    def with_dotenv(cmd, _opts) = ["dotenv", *cmd]
  end
end
