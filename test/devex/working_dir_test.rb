# frozen_string_literal: true

require "test_helper"
require "devex/working_dir"
require "devex/dirs"
require "tmpdir"
require "fileutils"

class WorkingDirTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("working_dir_test")
    # Create a project marker so Dirs.project_dir works
    File.write(File.join(@tmpdir, ".dx.yml"), "")
    Dir.chdir(@tmpdir)
    Devex::Dirs.reset!
    Devex::WorkingDir.reset!
  end

  def teardown
    Devex::WorkingDir.reset!
    Devex::Dirs.reset!
    Dir.chdir(File.expand_path("../..", __dir__))
    FileUtils.rm_rf(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  # ─────────────────────────────────────────────────────────────
  # Basic Access
  # ─────────────────────────────────────────────────────────────

  def test_current_defaults_to_project_dir
    assert_equal Devex::Dirs.project_dir.to_s, Devex::WorkingDir.current.to_s
  end

  def test_depth_starts_at_zero
    assert_equal 0, Devex::WorkingDir.depth
  end

  # ─────────────────────────────────────────────────────────────
  # Within Blocks
  # ─────────────────────────────────────────────────────────────

  def test_within_changes_working_dir
    subdir = File.join(@tmpdir, "subdir")
    FileUtils.mkdir_p(subdir)

    Devex::WorkingDir.within("subdir") do
      assert_paths_equal subdir, Devex::WorkingDir.current.to_s
    end
  end

  def test_within_restores_working_dir
    original = Devex::WorkingDir.current.to_s
    subdir = File.join(@tmpdir, "subdir")
    FileUtils.mkdir_p(subdir)

    Devex::WorkingDir.within("subdir") do
      # Inside block, different dir
    end

    assert_equal original, Devex::WorkingDir.current.to_s
  end

  def test_within_restores_on_exception
    original = Devex::WorkingDir.current.to_s
    subdir = File.join(@tmpdir, "subdir")
    FileUtils.mkdir_p(subdir)

    begin
      Devex::WorkingDir.within("subdir") do
        raise "test error"
      end
    rescue RuntimeError
      # Expected
    end

    assert_equal original, Devex::WorkingDir.current.to_s
  end

  def test_within_nests_correctly
    level1 = File.join(@tmpdir, "level1")
    level2 = File.join(level1, "level2")
    FileUtils.mkdir_p(level2)

    Devex::WorkingDir.within("level1") do
      assert_paths_equal level1, Devex::WorkingDir.current.to_s

      Devex::WorkingDir.within("level2") do
        assert_paths_equal level2, Devex::WorkingDir.current.to_s
      end

      assert_paths_equal level1, Devex::WorkingDir.current.to_s
    end

    assert_paths_equal @tmpdir, Devex::WorkingDir.current.to_s
  end

  def test_within_with_absolute_path
    other_dir = Dir.mktmpdir("other")

    begin
      Devex::WorkingDir.within(other_dir) do
        assert_equal other_dir, Devex::WorkingDir.current.to_s
      end
    ensure
      FileUtils.rm_rf(other_dir)
    end
  end

  def test_within_with_path_object
    subdir = File.join(@tmpdir, "subdir")
    FileUtils.mkdir_p(subdir)
    path = Devex::Support::Path[subdir]

    Devex::WorkingDir.within(path) do
      assert_equal subdir, Devex::WorkingDir.current.to_s
    end
  end

  def test_within_returns_block_result
    result = Devex::WorkingDir.within(@tmpdir) do
      42
    end
    assert_equal 42, result
  end

  def test_depth_increases_in_within
    FileUtils.mkdir_p(File.join(@tmpdir, "a"))

    assert_equal 0, Devex::WorkingDir.depth

    Devex::WorkingDir.within("a") do
      assert_equal 1, Devex::WorkingDir.depth
    end

    assert_equal 0, Devex::WorkingDir.depth
  end

  # ─────────────────────────────────────────────────────────────
  # Mixin
  # ─────────────────────────────────────────────────────────────

  def test_mixin_provides_working_dir
    klass = Class.new do
      include Devex::WorkingDirMixin
    end

    obj = klass.new
    assert_equal Devex::WorkingDir.current.to_s, obj.working_dir.to_s
  end

  def test_mixin_provides_within
    FileUtils.mkdir_p(File.join(@tmpdir, "subdir"))

    klass = Class.new do
      include Devex::WorkingDirMixin
    end

    obj = klass.new
    result = obj.within("subdir") do
      obj.working_dir.to_s
    end

    assert_paths_equal File.join(@tmpdir, "subdir"), result
  end

  # ─────────────────────────────────────────────────────────────
  # Edge Cases
  # ─────────────────────────────────────────────────────────────

  def test_within_rejects_invalid_type
    assert_raises(ArgumentError) do
      Devex::WorkingDir.within(123) { }
    end
  end

  def test_stack_returns_copy
    FileUtils.mkdir_p(File.join(@tmpdir, "a"))

    Devex::WorkingDir.within("a") do
      stack = Devex::WorkingDir.stack
      stack.clear  # Modifying the copy
      assert_equal 1, Devex::WorkingDir.depth  # Original unchanged
    end
  end

  private

  # Compare paths using realpath to handle /var -> /private/var on macOS
  def assert_paths_equal(expected, actual, msg = nil)
    assert_equal File.realpath(expected), File.realpath(actual), msg
  end
end
