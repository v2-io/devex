# frozen_string_literal: true

require_relative "result"

module Devex
  module Exec
    # Controller for managing background (spawned) processes.
    #
    # Returned by `spawn` to provide control over the child process.
    # Use this to monitor, signal, or wait for completion.
    #
    # @example Basic usage
    #   ctrl = spawn "rails", "server"
    #   sleep 5
    #   ctrl.kill(:TERM)
    #   result = ctrl.result
    #
    # @example With IO access
    #   ctrl = spawn "cat", stdin: :pipe, stdout: :pipe
    #   ctrl.stdin.puts "hello"
    #   ctrl.stdin.close
    #   output = ctrl.stdout.read
    #   ctrl.result
    #
    class Controller
      # @return [Integer] Process ID
      attr_reader :pid

      # @return [String, nil] Optional name/identifier
      attr_reader :name

      # @return [Array<String>] The command being executed
      attr_reader :command

      # @return [Time] When the process was started
      attr_reader :started_at

      # @return [IO, nil] Stdin pipe (if configured)
      attr_reader :stdin

      # @return [IO, nil] Stdout pipe (if configured)
      attr_reader :stdout

      # @return [IO, nil] Stderr pipe (if configured)
      attr_reader :stderr

      # @return [Hash] Options passed when spawning
      attr_reader :options

      def initialize(
        pid:,
        command:,
        name: nil,
        stdin: nil,
        stdout: nil,
        stderr: nil,
        options: {}
      )
        @pid = pid
        @command = Array(command)
        @name = name
        @stdin = stdin
        @stdout = stdout
        @stderr = stderr
        @options = options
        @started_at = Time.now
        @result = nil
        @mutex = Mutex.new
      end

      # ─────────────────────────────────────────────────────────────
      # Status
      # ─────────────────────────────────────────────────────────────

      # @return [Boolean] true if process is still running
      def executing?
        return false if @result

        # Non-blocking check
        pid_result, _status = Process.wait2(pid, Process::WNOHANG)
        pid_result.nil?
      rescue Errno::ECHILD
        false
      end

      alias running? executing?

      # @return [Boolean] true if process has finished
      def finished?
        !executing?
      end

      # @return [Float] Seconds since process started
      def elapsed
        Time.now - @started_at
      end

      # ─────────────────────────────────────────────────────────────
      # Signals
      # ─────────────────────────────────────────────────────────────

      # Send a signal to the process.
      #
      # @param signal [Symbol, String, Integer] Signal to send
      # @return [Boolean] true if signal was sent successfully
      #
      # @example
      #   ctrl.kill(:TERM)
      #   ctrl.kill(:INT)
      #   ctrl.kill(:KILL)
      #   ctrl.kill(9)
      #   ctrl.kill("SIGTERM")
      #
      def kill(signal = :TERM)
        Process.kill(signal, pid)
        true
      rescue Errno::ESRCH, Errno::EPERM
        # Process already gone or we don't have permission
        false
      end

      alias signal kill

      # Send SIGTERM and wait for graceful shutdown.
      #
      # @param timeout [Float] Seconds to wait before SIGKILL
      # @return [Result] Final result
      def terminate(timeout: 5)
        kill(:TERM)
        result(timeout: timeout)
      rescue Timeout::Error
        kill(:KILL)
        result(timeout: 1)
      end

      # ─────────────────────────────────────────────────────────────
      # Wait for Completion
      # ─────────────────────────────────────────────────────────────

      # Wait for process to complete and return Result.
      #
      # @param timeout [Float, nil] Maximum seconds to wait (nil = forever)
      # @return [Result] Final result with exit status
      # @raise [Timeout::Error] if timeout exceeded
      #
      # @example
      #   result = ctrl.result
      #   result = ctrl.result(timeout: 30)
      #
      def result(timeout: nil)
        @mutex.synchronize do
          return @result if @result
        end

        status = if timeout
                   wait_with_timeout(timeout)
                 else
                   Process.wait2(pid)[1]
                 end

        duration = Time.now - @started_at
        close_pipes

        @mutex.synchronize do
          @result = Result.from_status(
            status,
            command: @command,
            duration: duration,
            options: @options
          )
        end
      end

      alias wait result

      # ─────────────────────────────────────────────────────────────
      # IO Helpers
      # ─────────────────────────────────────────────────────────────

      # Write to stdin and optionally close.
      #
      # @param data [String] Data to write
      # @param close_after [Boolean] Close stdin after writing
      # @return [Integer] Bytes written
      def write(data, close_after: false)
        raise "No stdin pipe available" unless @stdin

        bytes = @stdin.write(data)
        @stdin.close if close_after
        bytes
      end

      # Read all available stdout.
      #
      # @return [String, nil] Stdout content or nil if no pipe
      def read_stdout
        @stdout&.read
      end

      # Read all available stderr.
      #
      # @return [String, nil] Stderr content or nil if no pipe
      def read_stderr
        @stderr&.read
      end

      # ─────────────────────────────────────────────────────────────
      # Inspection
      # ─────────────────────────────────────────────────────────────

      def to_s
        status = if @result
                   @result.success? ? "exited" : "failed"
                 else
                   "running"
                 end
        "#<Controller #{command.first} pid=#{pid} #{status}>"
      end

      def inspect
        parts = ["#<Controller"]
        parts << "name=#{name.inspect}" if name
        parts << "command=#{command.inspect}"
        parts << "pid=#{pid}"
        parts << "elapsed=#{"%.2f" % elapsed}s"
        parts << "status=#{@result ? "finished" : "running"}"
        parts << ">"
        parts.join(" ")
      end

      private

      def wait_with_timeout(timeout)
        deadline = Time.now + timeout
        loop do
          pid_result, status = Process.wait2(pid, Process::WNOHANG)
          return status if pid_result

          remaining = deadline - Time.now
          raise Timeout::Error, "Process #{pid} did not exit within #{timeout}s" if remaining <= 0

          sleep([0.1, remaining].min)
        end
      end

      def close_pipes
        @stdin&.close unless @stdin&.closed?
        @stdout&.close unless @stdout&.closed?
        @stderr&.close unless @stderr&.closed?
      end
    end
  end
end
