# frozen_string_literal: true

module Devex
  module Exec
    # Result of command execution.
    #
    # All commands (except run?/shell?/exec!) return a Result object.
    # This provides inspectable information about what happened without
    # raising exceptions for non-zero exit codes.
    #
    # @example Basic usage
    #   result = run "bundle", "install"
    #   if result.success?
    #     puts "Installed!"
    #   else
    #     puts "Failed: #{result.stderr}"
    #   end
    #
    # @example Exit on failure
    #   run("bundle", "install").exit_on_failure!
    #
    # @example Chaining
    #   run("lint").then { run("test") }.then { run("build") }.exit_on_failure!
    #
    class Result
      # @return [Array<String>] The command that was executed
      attr_reader :command

      # @return [Integer, nil] Process ID
      attr_reader :pid

      # @return [Float, nil] Execution duration in seconds
      attr_reader :duration

      # @return [Integer, nil] Exit code (0-255), nil if killed by signal
      attr_reader :exit_code

      # @return [Integer, nil] Signal number if killed by signal
      attr_reader :signal_code

      # @return [String, nil] Captured stdout (if applicable)
      attr_reader :stdout

      # @return [String, nil] Captured stderr (if applicable)
      attr_reader :stderr

      # @return [Exception, nil] Exception if command failed to start
      attr_reader :exception

      # @return [Hash] Original options passed to the command
      attr_reader :options

      def initialize(
        command:,
        pid: nil,
        duration: nil,
        exit_code: nil,
        signal_code: nil,
        stdout: nil,
        stderr: nil,
        exception: nil,
        options: {}
      )
        @command     = Array(command)
        @pid         = pid
        @duration    = duration
        @exit_code   = exit_code
        @signal_code = signal_code
        @stdout      = stdout
        @stderr      = stderr
        @exception   = exception
        @options     = options
      end

      # ─────────────────────────────────────────────────────────────
      # Status Predicates
      # ─────────────────────────────────────────────────────────────

      # @return [Boolean] true if exit code is 0
      def success? = exit_code == 0 && !exception

      # @return [Boolean] true if exit code is non-zero or there was an exception
      def failed? = !success?

      # @return [Boolean] true if process was killed by a signal
      def signaled? = !signal_code.nil?

      # @return [Boolean] true if process was killed due to timeout
      def timed_out? = options[:timed_out] == true

      # @return [Boolean] true if the process started but we're still waiting
      def running? = pid && exit_code.nil? && signal_code.nil? && !exception

      # ─────────────────────────────────────────────────────────────
      # Output Access
      # ─────────────────────────────────────────────────────────────

      # Combined stdout and stderr
      # @return [String, nil]
      def output
        return nil unless stdout || stderr

        [stdout, stderr].compact.join
      end

      # @return [Array<String>] stdout split into lines
      def stdout_lines = stdout&.lines(chomp: true) || []

      # @return [Array<String>] stderr split into lines
      def stderr_lines = stderr&.lines(chomp: true) || []

      # ─────────────────────────────────────────────────────────────
      # Monad Operations
      # ─────────────────────────────────────────────────────────────

      # Exit the process if this result represents failure.
      # Uses the command's exit code, or 1 if there was an exception.
      #
      # @param message [String, nil] Optional message to print before exiting
      # @return [Result] self if successful
      def exit_on_failure!(message: nil)
        return self if success?

        if message
          warn message
        elsif exception
          warn "Command failed to start: #{exception.message}"
        end

        exit(exit_code || 1)
      end

      # Execute block if this result is successful.
      # Returns self if failed (short-circuit).
      #
      # @yield Block to execute if successful
      # @return [Result] Block's result or self if failed
      def then
        return self if failed?

        yield
      end

      # Transform stdout if successful.
      #
      # @yield [String] Block receives stdout
      # @return [Object, nil] Block's result or nil if failed
      def map
        return nil if failed?

        yield stdout
      end

      # ─────────────────────────────────────────────────────────────
      # Inspection
      # ─────────────────────────────────────────────────────────────

      def to_s
        status = if success?
                   "success"
                 elsif signaled?
                   "signal #{signal_code}"
                 elsif exception
                   "exception: #{exception.class}"
                 else
                   "exit #{exit_code}"
                 end

        "#<Result #{command.first} #{status}>"
      end

      def inspect
        parts = ["#<Result"]
        parts << "command=#{command.inspect}"
        parts << "pid=#{pid}" if pid
        parts << "exit_code=#{exit_code}" if exit_code
        parts << "signal_code=#{signal_code}" if signal_code
        parts << "duration=#{'%.3f' % duration}s" if duration
        parts << "stdout=#{stdout.bytesize}b" if stdout
        parts << "stderr=#{stderr.bytesize}b" if stderr
        parts << "exception=#{exception.class}" if exception
        parts << ">"
        parts.join(" ")
      end

      # @return [Hash] Result as a hash (for JSON serialization, etc.)
      def to_h
        {
          command:     command,
          pid:         pid,
          exit_code:   exit_code,
          signal_code: signal_code,
          duration:    duration,
          success:     success?,
          stdout:      stdout,
          stderr:      stderr,
          exception:   exception&.message
        }.compact
      end

      # ─────────────────────────────────────────────────────────────
      # Factory Methods
      # ─────────────────────────────────────────────────────────────

      class << self
        # Create a Result from Process::Status
        def from_status(status, command:, **)
          new(
            command:     command,
            pid:         status.pid,
            exit_code:   status.exited? ? status.exitstatus : nil,
            signal_code: status.signaled? ? status.termsig : nil,
            **
          )
        end

        # Create a Result for a failed-to-start command
        def from_exception(exception, command:, **)
          new(
            command:   command,
            exception: exception,
            exit_code: 127,  # Convention for "command not found"
            **
          )
        end
      end
    end
  end
end
