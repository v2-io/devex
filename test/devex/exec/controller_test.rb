# frozen_string_literal: true

require "test_helper"
require "timeout"
require "devex/exec/controller"

class ControllerTest < Minitest::Test
  def test_pid_available_immediately
    ctrl = start_sleep(10)
    assert_kind_of Integer, ctrl.pid
    assert_operator ctrl.pid, :>, 0
  ensure
    cleanup(ctrl)
  end

  def test_executing_true_while_running
    ctrl = start_sleep(10)
    assert_predicate ctrl, :executing?
    assert_predicate ctrl, :running?
  ensure
    cleanup(ctrl)
  end

  def test_finished_after_completion
    ctrl = start_true
    ctrl.result
    assert_predicate ctrl, :finished?
    refute_predicate ctrl, :executing?
  end

  def test_elapsed_increases
    ctrl    = start_sleep(10)
    initial = ctrl.elapsed
    sleep 0.05
    assert_operator ctrl.elapsed, :>, initial
  ensure
    cleanup(ctrl)
  end

  def test_kill_stops_process
    ctrl = start_sleep(10)
    assert_predicate ctrl, :executing?

    killed = ctrl.kill(:TERM)
    assert killed

    result = ctrl.result(timeout: 2)
    refute_predicate result, :success?
    assert result.signaled? || result.exit_code
  end

  def test_kill_returns_false_for_dead_process
    ctrl = start_true
    ctrl.result

    killed = ctrl.kill(:TERM)
    refute killed
  end

  def test_terminate_sends_term_then_waits
    ctrl   = start_sleep(10)
    result = ctrl.terminate(timeout: 2)
    assert_kind_of Devex::Exec::Result, result
    refute_predicate ctrl, :executing?
  end

  def test_result_returns_result_object
    ctrl   = start_true
    result = ctrl.result

    assert_kind_of Devex::Exec::Result, result
    assert_predicate result, :success?
  end

  def test_result_with_exit_code
    ctrl   = start_false
    result = ctrl.result

    assert_kind_of Devex::Exec::Result, result
    refute_predicate result, :success?
    assert_equal 1, result.exit_code
  end

  def test_result_cached_after_first_call
    ctrl   = start_true
    first  = ctrl.result
    second = ctrl.result

    assert_same first, second
  end

  def test_result_timeout_raises
    ctrl = start_sleep(100)

    assert_raises(Timeout::Error) do
      ctrl.result(timeout: 0.1)
    end
  ensure
    cleanup(ctrl)
  end

  def test_command_stored
    ctrl = start_true
    assert_equal %w[true], ctrl.command
  ensure
    cleanup(ctrl)
  end

  def test_name_optional
    ctrl = Devex::Exec::Controller.new(
      pid:     12_345,
      command: "test",
      name:    "my-test"
    )
    assert_equal "my-test", ctrl.name
  end

  def test_to_s_shows_status
    ctrl = start_true
    assert_includes ctrl.to_s, "running"

    ctrl.result
    assert_includes ctrl.to_s, "exited"
  end

  def test_inspect_shows_details
    ctrl      = start_true
    inspected = ctrl.inspect

    assert_includes inspected, "Controller"
    assert_includes inspected, "pid="
    assert_includes inspected, "command="
    assert_includes inspected, "elapsed="
    assert_includes inspected, "status="
  ensure
    cleanup(ctrl)
  end

  # ─────────────────────────────────────────────────────────────
  # IO Tests
  # ─────────────────────────────────────────────────────────────

  def test_stdin_pipe_allows_writing
    # Create a process that reads from stdin and echoes
    pid = Process.spawn(
      "cat",
      in:  (stdin_r = IO.pipe[0]),
      out: "/dev/null",
      err: "/dev/null"
    )
    stdin_w = IO.pipe[1]

    ctrl = Devex::Exec::Controller.new(
      pid:     pid,
      command: "cat",
      stdin:   stdin_w
    )

    # Verify we can write (even though we won't read it back in this test)
    bytes = ctrl.write("hello\n")
    assert_equal 6, bytes
  ensure
    stdin_r&.close
    stdin_w&.close
    cleanup_pid(pid)
  end

  def test_write_raises_without_stdin_pipe
    ctrl = Devex::Exec::Controller.new(
      pid:     12_345,
      command: "test"
    )

    assert_raises(RuntimeError) do
      ctrl.write("data")
    end
  end

  private

  def start_sleep(seconds)
    pid = Process.spawn("sleep", seconds.to_s, out: "/dev/null", err: "/dev/null")
    Devex::Exec::Controller.new(pid: pid, command: ["sleep", seconds.to_s])
  end

  def start_true
    pid = Process.spawn("true", out: "/dev/null", err: "/dev/null")
    Devex::Exec::Controller.new(pid: pid, command: ["true"])
  end

  def start_false
    pid = Process.spawn("false", out: "/dev/null", err: "/dev/null")
    Devex::Exec::Controller.new(pid: pid, command: ["false"])
  end

  def cleanup(ctrl)
    return unless ctrl

    return unless ctrl.executing?

    begin
      ctrl.kill(:KILL)
    rescue StandardError
      nil
    end
    begin
      ctrl.result(timeout: 1)
    rescue StandardError
      nil
    end
  end

  def cleanup_pid(pid)
    return unless pid

    begin
      Process.kill(:KILL, pid)
    rescue StandardError
      nil
    end
    begin
      Process.wait(pid)
    rescue StandardError
      nil
    end
  end
end
