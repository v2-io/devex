# frozen_string_literal: true

require "test_helper"
require "stringio"

class CLITest < Minitest::Test
  include EnvHelper

  def setup
    clear_dx_env
    Devex::Context.clear_all_overrides!
    Devex::Context.reset_call_stack!
    @cli = Devex::CLI.new
    @cli.load_builtins
    @cli.merge_builtins
  end

  def teardown
    Devex::Context.clear_all_overrides!
    Devex::Context.reset_call_stack!
  end

  # --- Global options extraction ---

  def test_extract_format_flag_long
    argv, = @cli.send(:extract_global_flags, ["--format=json", "version"])
    assert_equal "json", @cli.global_options[:format]
    assert_equal ["version"], argv
  end

  def test_extract_format_flag_short
    argv, = @cli.send(:extract_global_flags, ["-f", "yaml", "version"])
    assert_equal "yaml", @cli.global_options[:format]
    assert_equal ["version"], argv
  end

  def test_extract_verbose_flag
    argv, = @cli.send(:extract_global_flags, ["-v", "version"])
    assert_equal 1, @cli.global_options[:verbose]
    assert_equal ["version"], argv
  end

  def test_extract_verbose_stacks
    argv, = @cli.send(:extract_global_flags, ["-v", "-v", "-v", "version"])
    assert_equal 3, @cli.global_options[:verbose]
    assert_equal ["version"], argv
  end

  def test_extract_no_verbose_resets
    # First set verbose
    @cli.send(:extract_global_flags, ["-v", "-v", "version"])
    assert_equal 2, @cli.global_options[:verbose]

    # Reset and use --no-verbose
    @cli = Devex::CLI.new
    argv, = @cli.send(:extract_global_flags, ["-v", "-v", "--no-verbose", "version"])
    assert_equal 0, @cli.global_options[:verbose]
    assert_equal ["version"], argv
  end

  def test_extract_quiet_flag
    argv, = @cli.send(:extract_global_flags, ["-q", "version"])
    assert @cli.global_options[:quiet]
    assert_equal ["version"], argv
  end

  def test_extract_no_quiet_unsets
    argv, = @cli.send(:extract_global_flags, ["-q", "--no-quiet", "version"])
    refute @cli.global_options[:quiet]
    assert_equal ["version"], argv
  end

  def test_extract_no_color_sets_context_override
    @cli.send(:extract_global_flags, ["--no-color", "version"])
    refute_predicate Devex::Context, :color?
  end

  def test_extract_color_always_sets_context_override
    @cli.send(:extract_global_flags, ["--color=always", "version"])
    assert_predicate Devex::Context, :color?
  end

  def test_extract_dx_version_returns_flag
    _, show_version = @cli.send(:extract_global_flags, ["--dx-version"])
    assert show_version
  end

  # --- Hidden debug flags ---

  def test_dx_agent_mode_sets_context
    @cli.send(:extract_global_flags, ["--dx-agent-mode", "version"])
    assert_predicate Devex::Context, :agent_mode?
  end

  def test_dx_no_agent_mode_sets_context
    @cli.send(:extract_global_flags, ["--dx-no-agent-mode", "version"])
    refute_predicate Devex::Context, :agent_mode?
  end

  def test_dx_interactive_sets_context
    @cli.send(:extract_global_flags, ["--dx-interactive", "version"])
    assert_predicate Devex::Context, :interactive?
  end

  def test_dx_env_sets_context
    @cli.send(:extract_global_flags, ["--dx-env=production", "version"])
    Devex::Context.reset_env!
    assert_equal "production", Devex::Context.env
  end

  def test_dx_terminal_sets_context
    @cli.send(:extract_global_flags, ["--dx-terminal", "version"])
    assert_predicate Devex::Context, :terminal?
  end

  def test_dx_ci_sets_context
    @cli.send(:extract_global_flags, ["--dx-ci", "version"])
    assert_predicate Devex::Context, :ci?
  end

  # --- Help extraction ---

  def test_extract_help_word
    argv, show_help = @cli.send(:extract_help, %w[help version])
    assert show_help
    assert_equal ["version"], argv
  end

  def test_extract_help_flag
    argv, show_help = @cli.send(:extract_help, ["version", "--help"])
    assert show_help
    assert_equal ["version"], argv
  end

  def test_extract_help_short_h
    argv, show_help = @cli.send(:extract_help, ["-h", "version"])
    assert show_help
    assert_equal ["version"], argv
  end

  def test_extract_help_question
    argv, show_help = @cli.send(:extract_help, ["-?"])
    assert show_help
    assert_empty argv
  end

  # --- Tool resolution ---

  def test_resolve_tool_finds_version
    tool, remaining = @cli.send(:resolve_tool, ["version"])
    assert_equal "version", tool.name
    assert_empty remaining
  end

  def test_resolve_tool_finds_nested
    tool, remaining = @cli.send(:resolve_tool, %w[version bump patch])
    assert_equal "bump", tool.name
    assert_equal ["patch"], remaining
  end

  def test_resolve_tool_stops_at_flag
    tool, remaining = @cli.send(:resolve_tool, ["version", "--format=json"])
    assert_equal "version", tool.name
    assert_equal ["--format=json"], remaining
  end

  # --- Global options help ---

  def test_global_options_help_includes_format
    help = @cli.send(:global_options_help)
    assert_includes help, "--format=FORMAT"
  end

  def test_global_options_help_includes_dx_version
    help = @cli.send(:global_options_help)
    assert_includes help, "--dx-version"
  end

  def test_global_options_help_does_not_include_hidden_flags
    help = @cli.send(:global_options_help)
    refute_includes help, "--dx-agent-mode"
    refute_includes help, "--dx-no-agent-mode"
    refute_includes help, "--dx-interactive"
  end

  # --- LoadError diagnostic hint (additive; never swallows the error) ------
  #
  # See CHANGELOG 0.3.8. The hint fires only when the situation matches
  # ADR-003's .dx-use-local affordance: in a project with a Gemfile but
  # NO delegation marker and NOT already delegated. Otherwise nil (the
  # bare LoadError stands on its own).

  def with_project_dir(gemfile:, marker:)
    Dir.mktmpdir do |tmp|
      Dir.chdir(tmp) do
        File.write("Gemfile", "source 'https://rubygems.org'") if gemfile
        FileUtils.touch(".dx-use-local") if marker
        yield tmp
      end
    end
  end

  def test_bundle_setup_hint_fires_when_situation_matches
    cli = Devex::CLI.new(config: Devex::DX_CONFIG)
    with_project_dir(gemfile: true, marker: false) do
      hint = cli.send(:bundle_setup_hint, LoadError.new("cannot load such file -- chiridion"))
      refute_nil hint
      assert_includes hint, "chiridion"
      assert_includes hint, ".dx-use-local"
      assert_includes hint, "touch"
    end
  end

  def test_bundle_setup_hint_nil_when_marker_already_present
    cli = Devex::CLI.new(config: Devex::DX_CONFIG)
    with_project_dir(gemfile: true, marker: true) do
      assert_nil cli.send(:bundle_setup_hint, LoadError.new("cannot load such file -- chiridion")),
                 "should not suggest creating the marker that already exists"
    end
  end

  def test_bundle_setup_hint_nil_when_no_gemfile
    cli = Devex::CLI.new(config: Devex::DX_CONFIG)
    with_project_dir(gemfile: false, marker: false) do
      assert_nil cli.send(:bundle_setup_hint, LoadError.new("cannot load such file -- chiridion")),
                 "no Gemfile = not a bundle-using project; hint would be wrong"
    end
  end

  def test_bundle_setup_hint_nil_when_already_delegated
    cli = Devex::CLI.new(config: Devex::DX_CONFIG)
    with_project_dir(gemfile: true, marker: false) do
      ENV[Devex::DX_CONFIG.env_var(:delegated)] = "1"
      begin
        assert_nil cli.send(:bundle_setup_hint, LoadError.new("cannot load such file -- chiridion")),
                   "already delegated = bundle IS active; the LoadError is a different problem"
      ensure
        ENV.delete(Devex::DX_CONFIG.env_var(:delegated))
      end
    end
  end

  def test_bundle_setup_hint_carries_missing_gem_name
    cli = Devex::CLI.new(config: Devex::DX_CONFIG)
    with_project_dir(gemfile: true, marker: false) do
      hint = cli.send(:bundle_setup_hint, LoadError.new("cannot load such file -- some-other-gem"))
      assert_includes hint, "some-other-gem", "hint must name the actually-missing gem, not a fixed string"
    end
  end
end
