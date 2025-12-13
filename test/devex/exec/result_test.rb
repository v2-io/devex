# frozen_string_literal: true

require "test_helper"
require "devex/exec/result"

class ResultTest < Minitest::Test
  def test_success_when_exit_code_zero
    result = Devex::Exec::Result.new(command: "ls", exit_code: 0)
    assert result.success?
    refute result.failed?
  end

  def test_failed_when_exit_code_nonzero
    result = Devex::Exec::Result.new(command: "ls", exit_code: 1)
    refute result.success?
    assert result.failed?
  end

  def test_failed_when_exception_present
    result = Devex::Exec::Result.new(
      command: "nonexistent",
      exit_code: 0,
      exception: RuntimeError.new("command not found")
    )
    refute result.success?
    assert result.failed?
  end

  def test_signaled_when_signal_code_present
    result = Devex::Exec::Result.new(command: "sleep", signal_code: 9)
    assert result.signaled?
  end

  def test_not_signaled_when_normal_exit
    result = Devex::Exec::Result.new(command: "ls", exit_code: 0)
    refute result.signaled?
  end

  def test_timed_out_when_option_set
    result = Devex::Exec::Result.new(
      command: "sleep",
      exit_code: nil,
      signal_code: 9,
      options: { timed_out: true }
    )
    assert result.timed_out?
  end

  def test_running_when_pid_but_no_exit
    result = Devex::Exec::Result.new(command: "sleep", pid: 12345)
    assert result.running?
  end

  def test_not_running_when_exit_code_present
    result = Devex::Exec::Result.new(command: "ls", pid: 12345, exit_code: 0)
    refute result.running?
  end

  # ─────────────────────────────────────────────────────────────
  # Output Access
  # ─────────────────────────────────────────────────────────────

  def test_stdout_lines_splits_output
    result = Devex::Exec::Result.new(command: "echo", stdout: "line1\nline2\nline3")
    assert_equal %w[line1 line2 line3], result.stdout_lines
  end

  def test_stdout_lines_empty_array_when_nil
    result = Devex::Exec::Result.new(command: "echo")
    assert_equal [], result.stdout_lines
  end

  def test_stderr_lines_splits_output
    result = Devex::Exec::Result.new(command: "ls", stderr: "error1\nerror2")
    assert_equal %w[error1 error2], result.stderr_lines
  end

  def test_output_combines_stdout_and_stderr
    result = Devex::Exec::Result.new(command: "cmd", stdout: "out", stderr: "err")
    assert_equal "outerr", result.output
  end

  def test_output_nil_when_both_nil
    result = Devex::Exec::Result.new(command: "cmd")
    assert_nil result.output
  end

  # ─────────────────────────────────────────────────────────────
  # Monad Operations
  # ─────────────────────────────────────────────────────────────

  def test_then_yields_on_success
    result = Devex::Exec::Result.new(command: "ls", exit_code: 0)
    called = false
    result.then { called = true }
    assert called
  end

  def test_then_short_circuits_on_failure
    result = Devex::Exec::Result.new(command: "ls", exit_code: 1)
    called = false
    result.then { called = true }
    refute called
  end

  def test_then_returns_self_on_failure
    result = Devex::Exec::Result.new(command: "ls", exit_code: 1)
    returned = result.then { "other" }
    assert_same result, returned
  end

  def test_then_returns_block_result_on_success
    result = Devex::Exec::Result.new(command: "ls", exit_code: 0)
    returned = result.then { "block_value" }
    assert_equal "block_value", returned
  end

  def test_map_transforms_stdout_on_success
    result = Devex::Exec::Result.new(command: "echo", exit_code: 0, stdout: "hello")
    mapped = result.map(&:upcase)
    assert_equal "HELLO", mapped
  end

  def test_map_returns_nil_on_failure
    result = Devex::Exec::Result.new(command: "echo", exit_code: 1, stdout: "hello")
    mapped = result.map(&:upcase)
    assert_nil mapped
  end

  def test_exit_on_failure_returns_self_on_success
    result = Devex::Exec::Result.new(command: "ls", exit_code: 0)
    assert_same result, result.exit_on_failure!
  end

  # ─────────────────────────────────────────────────────────────
  # Inspection
  # ─────────────────────────────────────────────────────────────

  def test_to_s_shows_success
    result = Devex::Exec::Result.new(command: "ls", exit_code: 0)
    assert_includes result.to_s, "success"
    assert_includes result.to_s, "ls"
  end

  def test_to_s_shows_exit_code_on_failure
    result = Devex::Exec::Result.new(command: "ls", exit_code: 42)
    assert_includes result.to_s, "exit 42"
  end

  def test_to_s_shows_signal_when_signaled
    result = Devex::Exec::Result.new(command: "sleep", signal_code: 9)
    assert_includes result.to_s, "signal 9"
  end

  def test_to_s_shows_exception_class
    result = Devex::Exec::Result.new(
      command: "cmd",
      exception: Errno::ENOENT.new("no such file")
    )
    assert_includes result.to_s, "exception"
    assert_includes result.to_s, "ENOENT"
  end

  def test_inspect_shows_details
    result = Devex::Exec::Result.new(
      command: ["ls", "-la"],
      pid: 12345,
      exit_code: 0,
      duration: 0.123,
      stdout: "output"
    )
    inspected = result.inspect
    assert_includes inspected, "command="
    assert_includes inspected, "pid=12345"
    assert_includes inspected, "exit_code=0"
    assert_includes inspected, "duration=0.123s"
    assert_includes inspected, "stdout=6b"
  end

  def test_to_h_returns_hash
    result = Devex::Exec::Result.new(
      command: "ls",
      exit_code: 0,
      stdout: "output"
    )
    h = result.to_h
    assert_equal ["ls"], h[:command]
    assert_equal 0, h[:exit_code]
    assert_equal true, h[:success]
    assert_equal "output", h[:stdout]
  end

  # ─────────────────────────────────────────────────────────────
  # Factory Methods
  # ─────────────────────────────────────────────────────────────

  def test_from_exception_sets_exit_code_127
    error = Errno::ENOENT.new("no such file")
    result = Devex::Exec::Result.from_exception(error, command: "nonexistent")

    assert_equal 127, result.exit_code
    assert_equal error, result.exception
    assert result.failed?
  end

  # Note: from_status requires a real Process::Status object,
  # which is hard to mock. We test it indirectly via integration tests.
end
