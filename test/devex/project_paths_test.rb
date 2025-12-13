# frozen_string_literal: true

require "test_helper"
require "devex/project_paths"
require "tmpdir"
require "fileutils"

class ProjectPathsTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("project_paths_test")
    @prj = Devex::ProjectPaths.new(root: @tmpdir)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  # ─────────────────────────────────────────────────────────────
  # Basic Access
  # ─────────────────────────────────────────────────────────────

  def test_root_returns_project_root
    assert_equal @tmpdir, @prj.root.to_s
  end

  def test_glob_from_root
    File.write(File.join(@tmpdir, "a.rb"), "")
    File.write(File.join(@tmpdir, "b.rb"), "")

    results = @prj["*.rb"]
    assert_equal 2, results.size
    assert results.all? { |p| p.to_s.end_with?(".rb") }
  end

  # ─────────────────────────────────────────────────────────────
  # Simple Paths
  # ─────────────────────────────────────────────────────────────

  def test_lib_when_exists
    FileUtils.mkdir_p(File.join(@tmpdir, "lib"))
    assert_equal File.join(@tmpdir, "lib"), @prj.lib.to_s
  end

  def test_lib_raises_when_missing
    error = assert_raises(RuntimeError) { @prj.lib }
    assert_includes error.message, "lib"
    assert_includes error.message, "not found"
  end

  def test_src_when_exists
    FileUtils.mkdir_p(File.join(@tmpdir, "src"))
    assert_equal File.join(@tmpdir, "src"), @prj.src.to_s
  end

  def test_bin_when_exists
    FileUtils.mkdir_p(File.join(@tmpdir, "bin"))
    assert_equal File.join(@tmpdir, "bin"), @prj.bin.to_s
  end

  def test_exe_when_exists
    FileUtils.mkdir_p(File.join(@tmpdir, "exe"))
    assert_equal File.join(@tmpdir, "exe"), @prj.exe.to_s
  end

  # ─────────────────────────────────────────────────────────────
  # Alternative Paths (test/, spec/, tests/)
  # ─────────────────────────────────────────────────────────────

  def test_test_finds_test_directory
    FileUtils.mkdir_p(File.join(@tmpdir, "test"))
    assert_equal File.join(@tmpdir, "test"), @prj.test.to_s
  end

  def test_test_finds_spec_directory
    FileUtils.mkdir_p(File.join(@tmpdir, "spec"))
    assert_equal File.join(@tmpdir, "spec"), @prj.test.to_s
  end

  def test_test_finds_tests_directory
    FileUtils.mkdir_p(File.join(@tmpdir, "tests"))
    assert_equal File.join(@tmpdir, "tests"), @prj.test.to_s
  end

  def test_test_prefers_first_alternative
    # test/ should be preferred over spec/
    FileUtils.mkdir_p(File.join(@tmpdir, "test"))
    FileUtils.mkdir_p(File.join(@tmpdir, "spec"))
    assert_equal File.join(@tmpdir, "test"), @prj.test.to_s
  end

  def test_docs_finds_docs_directory
    FileUtils.mkdir_p(File.join(@tmpdir, "docs"))
    assert_equal File.join(@tmpdir, "docs"), @prj.docs.to_s
  end

  def test_docs_finds_doc_directory
    FileUtils.mkdir_p(File.join(@tmpdir, "doc"))
    assert_equal File.join(@tmpdir, "doc"), @prj.docs.to_s
  end

  # ─────────────────────────────────────────────────────────────
  # Glob Patterns (*.gemspec)
  # ─────────────────────────────────────────────────────────────

  def test_gemspec_finds_gemspec_file
    File.write(File.join(@tmpdir, "myproject.gemspec"), "")
    assert @prj.gemspec.to_s.end_with?(".gemspec")
  end

  def test_gemspec_raises_when_missing
    error = assert_raises(RuntimeError) { @prj.gemspec }
    assert_includes error.message, "gemspec"
  end

  # ─────────────────────────────────────────────────────────────
  # Config Detection
  # ─────────────────────────────────────────────────────────────

  def test_config_returns_dx_yml_in_simple_mode
    File.write(File.join(@tmpdir, ".dx.yml"), "")
    assert_equal File.join(@tmpdir, ".dx.yml"), @prj.config.to_s
  end

  def test_config_returns_dx_config_yml_in_organized_mode
    FileUtils.mkdir_p(File.join(@tmpdir, ".dx"))
    config_path = @prj.config.to_s
    assert_equal File.join(@tmpdir, ".dx", "config.yml"), config_path
  end

  def test_config_raises_on_conflict
    File.write(File.join(@tmpdir, ".dx.yml"), "")
    FileUtils.mkdir_p(File.join(@tmpdir, ".dx"))

    error = assert_raises(RuntimeError) { @prj.config }
    assert_includes error.message, "Conflicting"
    assert_includes error.message, ".dx.yml"
    assert_includes error.message, ".dx/"
  end

  # ─────────────────────────────────────────────────────────────
  # Tools Detection
  # ─────────────────────────────────────────────────────────────

  def test_tools_returns_tools_in_simple_mode
    assert_equal File.join(@tmpdir, "tools"), @prj.tools.to_s
  end

  def test_tools_returns_dx_tools_in_organized_mode
    FileUtils.mkdir_p(File.join(@tmpdir, ".dx"))
    assert_equal File.join(@tmpdir, ".dx", "tools"), @prj.tools.to_s
  end

  # ─────────────────────────────────────────────────────────────
  # Organized Mode Detection
  # ─────────────────────────────────────────────────────────────

  def test_organized_mode_false_without_dx_dir
    refute @prj.organized_mode?
  end

  def test_organized_mode_true_with_dx_dir
    FileUtils.mkdir_p(File.join(@tmpdir, ".dx"))
    assert @prj.organized_mode?
  end

  # ─────────────────────────────────────────────────────────────
  # Path Overrides
  # ─────────────────────────────────────────────────────────────

  def test_override_replaces_convention
    FileUtils.mkdir_p(File.join(@tmpdir, "my_tests"))
    prj = Devex::ProjectPaths.new(root: @tmpdir, overrides: { test: "my_tests" })
    assert_equal File.join(@tmpdir, "my_tests"), prj.test.to_s
  end

  def test_override_raises_if_missing
    prj = Devex::ProjectPaths.new(root: @tmpdir, overrides: { test: "nonexistent" })
    error = assert_raises(RuntimeError) { prj.test }
    assert_includes error.message, "not found"
  end

  # ─────────────────────────────────────────────────────────────
  # Caching
  # ─────────────────────────────────────────────────────────────

  def test_paths_are_cached
    FileUtils.mkdir_p(File.join(@tmpdir, "lib"))
    first = @prj.lib
    second = @prj.lib
    assert_same first, second
  end

  # ─────────────────────────────────────────────────────────────
  # Version Detection
  # ─────────────────────────────────────────────────────────────

  def test_version_finds_VERSION_file
    File.write(File.join(@tmpdir, "VERSION"), "1.0.0")
    assert_equal File.join(@tmpdir, "VERSION"), @prj.version.to_s
  end

  def test_version_finds_version_rb
    lib_dir = File.join(@tmpdir, "lib", "myproject")
    FileUtils.mkdir_p(lib_dir)
    File.write(File.join(lib_dir, "version.rb"), "VERSION = '1.0.0'")
    assert @prj.version.to_s.end_with?("version.rb")
  end
end
