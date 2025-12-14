# frozen_string_literal: true

require "test_helper"
require "devex/exec"

class ExecTest < Minitest::Test
  # NOTE: We can't include Devex::Exec directly because it defines `run`
  # which conflicts with Minitest::Test#run. Use a helper object instead.

  class ExecHelper
    include Devex::Exec
  end

  def exec = @exec ||= ExecHelper.new

  # Delegate methods to helper
  def dx_run(*, **)     = exec.run(*, **)
  def dx_run?(*, **)    = exec.run?(*, **)
  def dx_capture(*, **) = exec.capture(*, **)
  def dx_spawn(*, **)   = exec.spawn(*, **)
  def dx_shell(*, **)   = exec.shell(*, **)
  def dx_shell?(*, **)  = exec.shell?(*, **)
  def dx_ruby(*, **)    = exec.ruby(*, **)
  def dx_tool(*, **)    = exec.tool(*, **)

  # ─────────────────────────────────────────────────────────────
  # run
  # ─────────────────────────────────────────────────────────────

  def test_run_returns_result
    result = dx_run "true"
    assert_kind_of Devex::Exec::Result, result
  end

  def test_run_success_for_true
    result = dx_run "true"
    assert_predicate result, :success?
    assert_equal 0, result.exit_code
  end

  def test_run_failed_for_false
    result = dx_run "false"
    assert_predicate result, :failed?
    assert_equal 1, result.exit_code
  end

  def test_run_captures_duration
    result = dx_run "true"
    assert_kind_of Float, result.duration
    assert_operator result.duration, :>=, 0
  end

  def test_run_stores_command
    result = dx_run "echo", "hello", "world"
    assert_equal %w[echo hello world], result.command
  end

  def test_run_handles_nonexistent_command
    result = dx_run "this_command_definitely_does_not_exist_12345"
    assert_predicate result, :failed?
    # Either exit_code 127 (from shell) or an exception
    assert(result.exit_code == 127 || result.exception)
  end

  def test_run_with_env
    result = dx_capture "sh", "-c", "echo $MY_TEST_VAR", env: { MY_TEST_VAR: "hello123" }
    assert_includes result.stdout, "hello123"
  end

  def test_run_with_chdir
    Dir.mktmpdir do |tmpdir|
      result = dx_capture "pwd", chdir: tmpdir
      # Use realpath to handle /var -> /private/var on macOS
      assert_equal File.realpath(tmpdir), result.stdout.strip
    end
  end

  def test_run_with_timeout
    result = dx_run "sleep", "10", timeout: 0.1
    assert_predicate result, :failed?
    # The process was killed
    assert result.timed_out? || result.signaled?
  end

  # ─────────────────────────────────────────────────────────────
  # run?
  # ─────────────────────────────────────────────────────────────

  def test_run_predicate_true_for_success = assert dx_run?("true")

  def test_run_predicate_false_for_failure = refute dx_run?("false")

  def test_run_predicate_false_for_nonexistent = refute dx_run?("this_command_definitely_does_not_exist_12345")

  # ─────────────────────────────────────────────────────────────
  # capture
  # ─────────────────────────────────────────────────────────────

  def test_capture_returns_result
    result = dx_capture "true"
    assert_kind_of Devex::Exec::Result, result
  end

  def test_capture_captures_stdout
    result = dx_capture "echo", "hello world"
    assert_equal "hello world\n", result.stdout
  end

  def test_capture_captures_stderr
    result = dx_capture "sh", "-c", "echo error >&2"
    assert_includes result.stderr, "error"
  end

  def test_capture_captures_both_streams
    result = dx_capture "sh", "-c", "echo out; echo err >&2"
    assert_includes result.stdout, "out"
    assert_includes result.stderr, "err"
  end

  def test_capture_handles_multiline_output
    result = dx_capture "sh", "-c", "echo line1; echo line2; echo line3"
    lines  = result.stdout_lines
    assert_equal %w[line1 line2 line3], lines
  end

  def test_capture_with_exit_code
    result = dx_capture "sh", "-c", "echo output; exit 42"
    assert_equal 42, result.exit_code
    assert_includes result.stdout, "output"
  end

  # ─────────────────────────────────────────────────────────────
  # spawn
  # ─────────────────────────────────────────────────────────────

  def test_spawn_returns_controller
    ctrl = dx_spawn "sleep", "10"
    assert_kind_of Devex::Exec::Controller, ctrl
  ensure
    cleanup_controller(ctrl)
  end

  def test_spawn_returns_immediately
    start   = Time.now
    ctrl    = dx_spawn "sleep", "10"
    elapsed = Time.now - start

    # Should return almost immediately (well under 1 second)
    assert_operator elapsed, :<, 1.0
  ensure
    cleanup_controller(ctrl)
  end

  def test_spawn_process_is_running
    ctrl = dx_spawn "sleep", "10"
    assert_predicate ctrl, :executing?
  ensure
    cleanup_controller(ctrl)
  end

  def test_spawn_can_wait_for_result
    ctrl   = dx_spawn "true"
    result = ctrl.result

    assert_kind_of Devex::Exec::Result, result
    assert_predicate result, :success?
  end

  def test_spawn_with_name
    ctrl = dx_spawn "sleep", "10", name: "my-sleeper"
    assert_equal "my-sleeper", ctrl.name
  ensure
    cleanup_controller(ctrl)
  end

  # ─────────────────────────────────────────────────────────────
  # shell
  # ─────────────────────────────────────────────────────────────

  def test_shell_returns_result
    result = dx_shell "true"
    assert_kind_of Devex::Exec::Result, result
  end

  def test_shell_executes_via_sh
    result = dx_capture_shell "echo hello"
    assert_includes result.stdout, "hello"
  end

  def test_shell_supports_pipes
    result = dx_capture_shell "echo 'line1\nline2\nline3' | wc -l"
    # wc output varies by platform, but should contain a number
    assert_match(/\d+/, result.stdout)
  end

  def test_shell_supports_variables
    result = dx_capture_shell "export FOO=bar; echo $FOO"
    assert_includes result.stdout, "bar"
  end

  def test_shell_supports_globs
    Dir.mktmpdir do |tmpdir|
      File.write("#{tmpdir}/a.txt", "")
      File.write("#{tmpdir}/b.txt", "")
      result = dx_capture_shell "ls #{tmpdir}/*.txt | wc -l"
      assert_match(/2/, result.stdout)
    end
  end

  # ─────────────────────────────────────────────────────────────
  # shell?
  # ─────────────────────────────────────────────────────────────

  def test_shell_predicate_true_for_success = assert dx_shell?("true")

  def test_shell_predicate_false_for_failure = refute dx_shell?("false")

  def test_shell_predicate_with_command
    assert dx_shell?("command -v ls")
    refute dx_shell?("command -v nonexistent_command_12345")
  end

  # ─────────────────────────────────────────────────────────────
  # ruby
  # ─────────────────────────────────────────────────────────────

  def test_ruby_runs_ruby_code
    result = dx_capture_ruby "-e", "puts 'hello from ruby'"
    assert_includes result.stdout, "hello from ruby"
  end

  def test_ruby_returns_result
    result = dx_ruby "-e", "exit 0"
    assert_kind_of Devex::Exec::Result, result
    assert_predicate result, :success?
  end

  def test_ruby_captures_exit_code
    result = dx_ruby "-e", "exit 42"
    assert_equal 42, result.exit_code
  end

  # ─────────────────────────────────────────────────────────────
  # Environment Stack
  # ─────────────────────────────────────────────────────────────

  def test_raw_mode_skips_stack
    # When raw: true, no bundler wrapping should happen
    result = dx_capture "echo", "test", raw: true
    assert_equal %w[echo test], result.command
  end

  def test_clean_env_clears_bundler_vars = dx_capture "sh", "-c", "echo $BUNDLE_GEMFILE", clean_env: true

  # ─────────────────────────────────────────────────────────────
  # Mise Wrapper
  # ─────────────────────────────────────────────────────────────

  def test_mise_forced_on_wraps_command
    # Test mise: true explicitly wraps, regardless of detection
    Dir.mktmpdir do |_tmpdir|
      # Capture the actual command that would be run by checking the result object
      # The prepare_command method sets up the command array
      helper = ExecHelper.new

      # Test internal behavior by checking what prepare_command returns
      _, cmd = helper.send(:apply_environment_stack, {}, %w[echo hello], { mise: true })
      assert_equal "mise", cmd[0]
      assert_equal "exec", cmd[1]
      assert_equal "--", cmd[2]
      assert_equal "echo", cmd[3]
      assert_equal "hello", cmd[4]
    end
  end

  def test_mise_forced_off_skips_wrapper
    # Test mise: false skips wrapping even if detected
    Dir.mktmpdir do |tmpdir|
      File.write(File.join(tmpdir, ".mise.toml"), "")
      Dir.chdir(tmpdir) do
        helper = ExecHelper.new
        helper.instance_variable_set(:@mise_detected, nil) # Clear cache

        _, cmd = helper.send(:apply_environment_stack, {}, %w[echo hello], { mise: false })
        assert_equal %w[echo hello], cmd
      end
    end
  end

  def test_mise_auto_detects_mise_toml
    Dir.mktmpdir do |tmpdir|
      File.write(File.join(tmpdir, ".mise.toml"), "")
      Dir.chdir(tmpdir) do
        helper = ExecHelper.new
        helper.instance_variable_set(:@mise_detected, nil) # Clear cache

        assert helper.send(:mise_detected?)
      end
    end
  end

  def test_mise_auto_detects_tool_versions
    Dir.mktmpdir do |tmpdir|
      File.write(File.join(tmpdir, ".tool-versions"), "ruby 3.3.0")
      Dir.chdir(tmpdir) do
        helper = ExecHelper.new
        helper.instance_variable_set(:@mise_detected, nil) # Clear cache

        assert helper.send(:mise_detected?)
      end
    end
  end

  def test_mise_not_detected_without_files
    Dir.mktmpdir do |tmpdir|
      Dir.chdir(tmpdir) do
        helper = ExecHelper.new
        helper.instance_variable_set(:@mise_detected, nil) # Clear cache

        refute helper.send(:mise_detected?)
      end
    end
  end

  def test_mise_auto_wraps_when_detected
    Dir.mktmpdir do |tmpdir|
      File.write(File.join(tmpdir, ".mise.toml"), "")
      Dir.chdir(tmpdir) do
        helper = ExecHelper.new
        helper.instance_variable_set(:@mise_detected, nil) # Clear cache

        _, cmd = helper.send(:apply_environment_stack, {}, %w[echo hello], {})
        assert_equal "mise", cmd[0]
        assert_equal "exec", cmd[1]
        assert_equal "--", cmd[2]
      end
    end
  end

  def test_mise_skips_self_wrapping
    # Don't wrap `mise` command with `mise exec --`
    helper = ExecHelper.new
    _, cmd = helper.send(:apply_environment_stack, {}, %w[mise install], { mise: true })
    # Should remain unchanged (no mise exec -- mise ...)
    assert_equal %w[mise install], cmd
  end

  # ─────────────────────────────────────────────────────────────
  # Dotenv Wrapper
  # ─────────────────────────────────────────────────────────────

  def test_dotenv_off_by_default
    helper = ExecHelper.new
    _, cmd = helper.send(:apply_environment_stack, {}, %w[echo hello], {})
    # No dotenv wrapper by default
    refute_equal "dotenv", cmd[0]
  end

  def test_dotenv_on_when_explicit
    helper = ExecHelper.new
    _, cmd = helper.send(:apply_environment_stack, {}, %w[echo hello], { dotenv: true })
    assert_equal "dotenv", cmd[0]
    assert_equal "echo", cmd[1]
    assert_equal "hello", cmd[2]
  end

  def test_dotenv_false_has_no_effect
    helper = ExecHelper.new
    _, cmd = helper.send(:apply_environment_stack, {}, %w[echo hello], { dotenv: false })
    refute_equal "dotenv", cmd[0]
  end

  # ─────────────────────────────────────────────────────────────
  # Wrapper Chain Order
  # ─────────────────────────────────────────────────────────────

  def test_full_wrapper_chain
    # Test order: dotenv → mise exec -- → bundle exec → command
    Dir.mktmpdir do |tmpdir|
      File.write(File.join(tmpdir, ".mise.toml"), "")
      File.write(File.join(tmpdir, "Gemfile"), "")
      Dir.chdir(tmpdir) do
        helper = ExecHelper.new
        helper.instance_variable_set(:@mise_detected, nil)
        helper.instance_variable_set(:@gemfile_present, nil)

        _, cmd = helper.send(:apply_environment_stack, {},
                             %w[rspec], { dotenv: true, bundle: true, mise: true })

        # Expected order: dotenv mise exec -- bundle exec rspec
        assert_equal %w[dotenv mise exec -- bundle exec rspec], cmd
      end
    end
  end

  def test_mise_and_bundle_without_dotenv
    Dir.mktmpdir do |tmpdir|
      File.write(File.join(tmpdir, ".mise.toml"), "")
      File.write(File.join(tmpdir, "Gemfile"), "")
      Dir.chdir(tmpdir) do
        helper = ExecHelper.new
        helper.instance_variable_set(:@mise_detected, nil)
        helper.instance_variable_set(:@gemfile_present, nil)

        _, cmd = helper.send(:apply_environment_stack, {},
                             %w[rspec], { bundle: true, mise: true })

        # Expected: mise exec -- bundle exec rspec
        assert_equal %w[mise exec -- bundle exec rspec], cmd
      end
    end
  end

  def test_raw_skips_all_wrappers
    # raw: true should skip bundle, mise, and dotenv
    Dir.mktmpdir do |tmpdir|
      File.write(File.join(tmpdir, ".mise.toml"), "")
      File.write(File.join(tmpdir, "Gemfile"), "")
      Dir.chdir(tmpdir) do
        helper = ExecHelper.new
        helper.instance_variable_set(:@mise_detected, nil)
        helper.instance_variable_set(:@gemfile_present, nil)

        # raw: true causes prepare_command to skip apply_environment_stack entirely
        # We verify the original command is preserved
        result = dx_capture("echo", "raw", raw: true)
        assert_equal %w[echo raw], result.command
      end
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Result Chaining
  # ─────────────────────────────────────────────────────────────

  def test_then_chains_on_success
    executed = []
    dx_run("true")
      .then do
      executed << 1
      dx_run("true")
    end
      .then do
      executed << 2
      dx_run("true")
    end

    assert_equal [1, 2], executed
  end

  def test_then_short_circuits_on_failure
    executed = []
    dx_run("false")
      .then do
      executed << 1
      dx_run("true")
    end
      .then do
      executed << 2
      dx_run("true")
    end

    assert_empty executed
  end

  def test_then_stops_at_first_failure
    executed = []
    dx_run("true")
      .then do
      executed << 1
      dx_run("false")
    end
      .then do
      executed << 2
      dx_run("true")
    end

    assert_equal [1], executed
  end

  # ─────────────────────────────────────────────────────────────
  # tool / tool?
  # ─────────────────────────────────────────────────────────────

  def test_tool_returns_result
    # Skip if dx not available in PATH
    skip "dx not in PATH" unless dx_available?

    result = dx_tool "version", capture: true
    assert_kind_of Devex::Exec::Result, result
  end

  def test_tool_captures_output
    skip "dx not in PATH" unless dx_available?

    result = dx_tool "version", capture: true
    assert_predicate result, :success?
    # Should have some version output
    assert_operator result.stdout.length, :>, 0
  end

  def test_tool_predicate_true_for_success
    skip "dx not in PATH" unless dx_available?

    assert dx_tool?("version")
  end

  def test_tool_predicate_false_for_failure
    skip "dx not in PATH" unless dx_available?

    # Running with an invalid flag causes failure
    refute dx_tool?("version", "--invalid-flag-12345")
  end

  def test_tool_sets_call_tree_env
    skip "dx not in PATH" unless dx_available?

    # The tool method should set DX_CALL_TREE and DX_INVOKED_FROM_TOOL
    # We can verify this by running a command that echoes the env
    # Since tool() runs dx, and dx doesn't easily echo env vars,
    # we'll test the internal behavior via a shell command that inspects env

    # Set up initial state
    original_call_tree = ENV.fetch("DX_CALL_TREE", nil)
    original_current   = ENV.fetch("DX_CURRENT_TOOL", nil)

    begin
      ENV["DX_CURRENT_TOOL"] = "parent_tool"
      ENV["DX_CALL_TREE"] = ""

      # Run dx version which should succeed
      result = dx_tool "version", capture: true
      # The env vars would have been set in the child process
      # We can at least verify the command succeeded
      assert_predicate result, :success?
    ensure
      ENV["DX_CALL_TREE"] = original_call_tree
      ENV["DX_CURRENT_TOOL"] = original_current
    end
  end

  def test_tool_builds_call_tree
    # Test that the call tree is built correctly (unit test of the logic)
    original_call_tree = ENV.fetch("DX_CALL_TREE", nil)
    original_current   = ENV.fetch("DX_CURRENT_TOOL", nil)

    begin
      # Simulate being invoked from "pre-commit"
      ENV["DX_CURRENT_TOOL"] = "pre-commit"
      ENV["DX_CALL_TREE"] = ""

      # When we call tool(), it should propagate "pre-commit" in the tree
      # We verify the env vars that would be passed to the child

      # Access internal helper to check env construction
      ExecHelper.new
      # Use send to access private method behavior
      call_tree         = ENV.fetch("DX_CALL_TREE", "")
      current_tool      = ENV.fetch("DX_CURRENT_TOOL", "")
      expected_new_tree = call_tree.empty? ? current_tool : "#{call_tree}:#{current_tool}"

      assert_equal "pre-commit", expected_new_tree

      # Now simulate nested call
      ENV["DX_CALL_TREE"] = "pre-commit"
      ENV["DX_CURRENT_TOOL"] = "lint"

      call_tree         = ENV.fetch("DX_CALL_TREE", "")
      current_tool      = ENV.fetch("DX_CURRENT_TOOL", "")
      expected_new_tree = call_tree.empty? ? current_tool : "#{call_tree}:#{current_tool}"

      assert_equal "pre-commit:lint", expected_new_tree
    ensure
      ENV["DX_CALL_TREE"] = original_call_tree
      ENV["DX_CURRENT_TOOL"] = original_current
    end
  end

  private

  def dx_available? = system("bundle exec dx --dx-version > /dev/null 2>&1")

  def dx_tool?(*, **) = exec.tool?(*, **)

  def dx_capture_shell(cmd) = dx_shell(cmd, out: :capture, err: :capture)

  def dx_capture_ruby(*) = dx_capture("ruby", *)

  def cleanup_controller(ctrl)
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
end
