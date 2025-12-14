# frozen_string_literal: true

require "test_helper"
require "devex/dirs"
require "tmpdir"
require "fileutils"

class DirsTest < Minitest::Test
  def setup
    @original_pwd = Dir.pwd
    @tmpdir       = Dir.mktmpdir("dirs_test")
    Devex::Dirs.reset!
  end

  def teardown
    Dir.chdir(@original_pwd)
    FileUtils.rm_rf(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
    Devex::Dirs.reset!
  end

  # ─────────────────────────────────────────────────────────────
  # Basic Directory Access
  # ─────────────────────────────────────────────────────────────

  def test_invoked_dir_returns_current_directory
    Dir.chdir(@tmpdir)
    Devex::Dirs.reset!
    # Use realpath to handle /var -> /private/var on macOS
    assert_equal File.realpath(@tmpdir), File.realpath(Devex::Dirs.invoked_dir.to_s)
  end

  def test_invoked_dir_is_memoized
    Dir.chdir(@tmpdir)
    Devex::Dirs.reset!
    first = Devex::Dirs.invoked_dir
    Dir.chdir(@original_pwd)
    second = Devex::Dirs.invoked_dir
    assert_equal first.to_s, second.to_s
  end

  def test_dest_dir_defaults_to_invoked_dir
    Dir.chdir(@tmpdir)
    Devex::Dirs.reset!
    assert_equal Devex::Dirs.invoked_dir.to_s, Devex::Dirs.dest_dir.to_s
  end

  def test_dest_dir_can_be_set
    Devex::Dirs.reset!
    Devex::Dirs.dest_dir = "/some/other/path"
    assert_equal "/some/other/path", Devex::Dirs.dest_dir.to_s
  end

  def test_dest_dir_cannot_be_changed_after_project_dir_computed
    create_project_marker
    Dir.chdir(@tmpdir)
    Devex::Dirs.reset!
    Devex::Dirs.project_dir  # Compute project_dir

    assert_raises(RuntimeError) do
      Devex::Dirs.dest_dir = "/other/path"
    end
  end

  def test_dx_src_dir_points_to_gem_root
    src = Devex::Dirs.dx_src_dir
    assert_predicate src, :exist?
    assert_predicate (src / "lib" / "devex"), :exist?
  end

  # ─────────────────────────────────────────────────────────────
  # Project Discovery
  # ─────────────────────────────────────────────────────────────

  def test_project_dir_finds_dx_yml
    create_project_marker(".dx.yml")
    Dir.chdir(@tmpdir)
    Devex::Dirs.reset!
    assert_paths_equal @tmpdir, Devex::Dirs.project_dir.to_s
  end

  def test_project_dir_finds_git
    create_project_marker(".git")
    Dir.chdir(@tmpdir)
    Devex::Dirs.reset!
    assert_paths_equal @tmpdir, Devex::Dirs.project_dir.to_s
  end

  def test_project_dir_finds_gemfile
    create_project_marker("Gemfile")
    Dir.chdir(@tmpdir)
    Devex::Dirs.reset!
    assert_paths_equal @tmpdir, Devex::Dirs.project_dir.to_s
  end

  def test_project_dir_searches_upward
    create_project_marker(".git")
    subdir = File.join(@tmpdir, "deep", "nested", "dir")
    FileUtils.mkdir_p(subdir)
    Dir.chdir(subdir)
    Devex::Dirs.reset!
    assert_paths_equal @tmpdir, Devex::Dirs.project_dir.to_s
  end

  def test_in_project_returns_true_when_in_project
    create_project_marker
    Dir.chdir(@tmpdir)
    Devex::Dirs.reset!
    assert_predicate Devex::Dirs, :in_project?
  end

  def test_in_project_returns_false_when_not_in_project
    # Use /tmp which shouldn't have project markers going up
    Dir.chdir(Dir.tmpdir)
    Devex::Dirs.reset!
    refute_predicate Devex::Dirs, :in_project?
  end

  private

  # Compare paths using realpath to handle /var -> /private/var on macOS
  def assert_paths_equal(expected, actual, msg = nil) = assert_equal File.realpath(expected), File.realpath(actual), msg

  def create_project_marker(marker = ".git")
    path = File.join(@tmpdir, marker)
    if marker.include?(".")
      File.write(path, "")
    else
      FileUtils.mkdir_p(path)
    end
  end
end
