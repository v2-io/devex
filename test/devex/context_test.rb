# frozen_string_literal: true

require "test_helper"

class ContextTest < Minitest::Test
  include EnvHelper

  def setup
    clear_dx_env
  end

  # --- Environment variable detection ---

  def test_agent_mode_env_with_dx_agent_mode
    with_env("DX_AGENT_MODE" => "1") do
      assert Devex::Context.agent_mode_env?
      assert Devex::Context.agent_mode?
    end
  end

  def test_agent_mode_env_with_devex_agent_mode
    with_env("DEVEX_AGENT_MODE" => "true") do
      assert Devex::Context.agent_mode_env?
      assert Devex::Context.agent_mode?
    end
  end

  def test_agent_mode_env_false_when_not_set
    refute Devex::Context.agent_mode_env?
  end

  def test_agent_mode_env_ignores_falsy_values
    with_env("DX_AGENT_MODE" => "0") do
      refute Devex::Context.agent_mode_env?
    end

    with_env("DX_AGENT_MODE" => "false") do
      refute Devex::Context.agent_mode_env?
    end

    with_env("DX_AGENT_MODE" => "") do
      refute Devex::Context.agent_mode_env?
    end
  end

  def test_batch_mode_env
    with_env("DX_BATCH" => "1") do
      assert Devex::Context.batch_mode_env?
    end

    with_env("DEVEX_BATCH" => "yes") do
      assert Devex::Context.batch_mode_env?
    end

    refute Devex::Context.batch_mode_env?
  end

  def test_interactive_forced
    with_env("DX_INTERACTIVE" => "1") do
      assert Devex::Context.interactive_forced?
    end

    refute Devex::Context.interactive_forced?
  end

  # --- CI detection ---

  def test_ci_detection_with_ci_var
    with_env("CI" => "true") do
      assert Devex::Context.ci?
    end
  end

  def test_ci_detection_with_github_actions
    with_env("GITHUB_ACTIONS" => "true") do
      assert Devex::Context.ci?
    end
  end

  def test_ci_detection_with_gitlab_ci
    with_env("GITLAB_CI" => "true") do
      assert Devex::Context.ci?
    end
  end

  def test_ci_detection_false_when_empty
    with_env("CI" => "") do
      refute Devex::Context.ci?
    end
  end

  def test_ci_detection_false_when_not_set
    refute Devex::Context.ci?
  end

  # --- Color detection ---

  def test_no_color_with_no_color_env
    with_env("NO_COLOR" => "1") do
      assert Devex::Context.no_color?
      refute Devex::Context.color?
    end
  end

  def test_force_color_overrides_agent_mode
    # In agent mode, color would normally be off
    # But FORCE_COLOR should override
    with_env("DX_AGENT_MODE" => "1", "FORCE_COLOR" => "1") do
      assert Devex::Context.agent_mode?
      assert Devex::Context.force_color?
      assert Devex::Context.color?
    end
  end

  def test_no_color_takes_precedence_over_force_color
    # NO_COLOR is checked first
    with_env("NO_COLOR" => "1", "FORCE_COLOR" => "1") do
      refute Devex::Context.color?
    end
  end

  # --- TTY detection ---
  # Note: These tests run in whatever environment the test suite is in.
  # We test the methods exist and return booleans, but actual TTY behavior
  # depends on how the tests are run.

  def test_stdout_tty_returns_boolean
    result = Devex::Context.stdout_tty?
    assert [true, false].include?(result), "stdout_tty? should return boolean"
  end

  def test_stderr_tty_returns_boolean
    result = Devex::Context.stderr_tty?
    assert [true, false].include?(result), "stderr_tty? should return boolean"
  end

  def test_stdin_tty_returns_boolean
    result = Devex::Context.stdin_tty?
    assert [true, false].include?(result), "stdin_tty? should return boolean"
  end

  def test_terminal_returns_boolean
    result = Devex::Context.terminal?
    assert [true, false].include?(result), "terminal? should return boolean"
  end

  def test_streams_merged_returns_boolean
    result = Devex::Context.streams_merged?
    assert [true, false].include?(result), "streams_merged? should return boolean"
  end

  def test_piped_returns_boolean
    result = Devex::Context.piped?
    assert [true, false].include?(result), "piped? should return boolean"
  end

  # --- Composite detection ---

  def test_interactive_false_when_agent_mode_env
    with_env("DX_AGENT_MODE" => "1") do
      refute Devex::Context.interactive?
    end
  end

  def test_interactive_false_when_batch_mode_env
    with_env("DX_BATCH" => "1") do
      refute Devex::Context.interactive?
    end
  end

  def test_interactive_false_when_ci
    with_env("CI" => "true") do
      refute Devex::Context.interactive?
    end
  end

  def test_interactive_true_when_forced
    # Even in CI, interactive_forced should enable interactive
    with_env("CI" => "true", "DX_INTERACTIVE" => "1") do
      assert Devex::Context.interactive?
    end
  end

  # --- Summary and to_env ---

  def test_summary_returns_hash
    summary = Devex::Context.summary
    assert_kind_of Hash, summary

    expected_keys = %i[
      terminal stdin_tty stdout_tty stderr_tty
      streams_merged ci piped agent_mode interactive color
    ]
    expected_keys.each do |key|
      assert summary.key?(key), "summary should include #{key}"
    end
  end

  def test_to_env_returns_string_hash
    env = Devex::Context.to_env
    assert_kind_of Hash, env

    %w[DX_AGENT_MODE DX_INTERACTIVE DX_CI].each do |key|
      assert env.key?(key), "to_env should include #{key}"
      assert %w[0 1].include?(env[key]), "#{key} should be '0' or '1'"
    end
  end

  def test_to_env_reflects_current_state
    with_env("CI" => "true") do
      env = Devex::Context.to_env
      assert_equal "1", env["DX_CI"]
    end
  end

  # --- Environment detection ---

  def test_env_defaults_to_development
    Devex::Context.reset_env!
    assert_equal "development", Devex::Context.env
    assert Devex::Context.development?
  end

  def test_env_from_dx_env
    Devex::Context.reset_env!
    with_env("DX_ENV" => "production") do
      Devex::Context.reset_env!
      assert_equal "production", Devex::Context.env
      assert Devex::Context.production?
      refute Devex::Context.development?
    end
  end

  def test_env_normalizes_aliases
    Devex::Context.reset_env!
    with_env("DX_ENV" => "prod") do
      Devex::Context.reset_env!
      assert_equal "production", Devex::Context.env
    end

    with_env("DX_ENV" => "dev") do
      Devex::Context.reset_env!
      assert_equal "development", Devex::Context.env
    end

    with_env("DX_ENV" => "stg") do
      Devex::Context.reset_env!
      assert_equal "staging", Devex::Context.env
    end
  end

  def test_env_falls_back_to_rails_env
    Devex::Context.reset_env!
    with_env("RAILS_ENV" => "test") do
      Devex::Context.reset_env!
      assert_equal "test", Devex::Context.env
      assert Devex::Context.test?
    end
  end

  def test_dx_env_takes_precedence_over_rails_env
    Devex::Context.reset_env!
    with_env("DX_ENV" => "staging", "RAILS_ENV" => "production") do
      Devex::Context.reset_env!
      assert_equal "staging", Devex::Context.env
    end
  end

  def test_safe_env
    Devex::Context.reset_env!
    with_env("DX_ENV" => "development") do
      Devex::Context.reset_env!
      assert Devex::Context.safe_env?
    end

    with_env("DX_ENV" => "test") do
      Devex::Context.reset_env!
      assert Devex::Context.safe_env?
    end

    with_env("DX_ENV" => "production") do
      Devex::Context.reset_env!
      refute Devex::Context.safe_env?
    end

    with_env("DX_ENV" => "staging") do
      Devex::Context.reset_env!
      refute Devex::Context.safe_env?
    end
  end

  # --- Call tree tracking ---

  def test_call_tree_empty_by_default
    Devex::Context.reset_call_stack!
    assert_empty Devex::Context.call_tree
    refute Devex::Context.invoked_from_task?
  end

  def test_push_and_pop_task
    Devex::Context.reset_call_stack!

    Devex::Context.push_task("test")
    assert_equal ["test"], Devex::Context.call_tree
    assert Devex::Context.invoked_from_task?
    assert_equal "test", Devex::Context.invoking_task
    assert_equal "test", Devex::Context.root_task

    Devex::Context.push_task("lint")
    assert_equal ["test", "lint"], Devex::Context.call_tree
    assert_equal "lint", Devex::Context.invoking_task
    assert_equal "test", Devex::Context.root_task

    Devex::Context.pop_task
    assert_equal ["test"], Devex::Context.call_tree

    Devex::Context.pop_task
    assert_empty Devex::Context.call_tree
  end

  def test_with_task_block
    Devex::Context.reset_call_stack!

    result = Devex::Context.with_task("pre-commit") do
      assert_equal ["pre-commit"], Devex::Context.call_tree
      "done"
    end

    assert_equal "done", result
    assert_empty Devex::Context.call_tree
  end

  def test_with_task_cleans_up_on_exception
    Devex::Context.reset_call_stack!

    assert_raises(RuntimeError) do
      Devex::Context.with_task("failing") do
        raise "boom"
      end
    end

    assert_empty Devex::Context.call_tree
  end

  def test_inherited_tree_from_env
    Devex::Context.reset_call_stack!
    with_env("DX_CALL_TREE" => "pre-commit:test") do
      assert_equal ["pre-commit", "test"], Devex::Context.inherited_tree
      assert_equal ["pre-commit", "test"], Devex::Context.call_tree
      assert_equal "pre-commit", Devex::Context.root_task
      assert_equal "test", Devex::Context.invoking_task
    end
  end

  def test_call_tree_combines_inherited_and_current
    Devex::Context.reset_call_stack!
    with_env("DX_CALL_TREE" => "pre-commit") do
      Devex::Context.push_task("lint")
      assert_equal ["pre-commit", "lint"], Devex::Context.call_tree
      Devex::Context.pop_task
    end
  end

  def test_to_env_includes_call_tree
    Devex::Context.reset_call_stack!
    Devex::Context.push_task("test")
    Devex::Context.push_task("lint")

    env = Devex::Context.to_env
    assert_equal "test:lint", env["DX_CALL_TREE"]

    Devex::Context.reset_call_stack!
  end

  def test_to_env_omits_empty_call_tree
    Devex::Context.reset_call_stack!
    env = Devex::Context.to_env
    refute env.key?("DX_CALL_TREE")
  end

  def test_summary_includes_new_fields
    Devex::Context.reset_call_stack!
    Devex::Context.reset_env!

    summary = Devex::Context.summary
    assert summary.key?(:env)
    assert summary.key?(:call_tree)
    assert summary.key?(:invoked_from_task)
  end
end
