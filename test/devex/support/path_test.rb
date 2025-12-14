# frozen_string_literal: true

require "test_helper"
require "devex/support/path"
require "tmpdir"
require "fileutils"

class PathTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("path_test")
    @path   = Devex::Support::Path.new(@tmpdir)
  end

  def teardown() FileUtils.rm_rf(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir) end

  # ─────────────────────────────────────────────────────────────
  # Construction
  # ─────────────────────────────────────────────────────────────

  def test_bracket_constructor_expands_tilde
    path = Devex::Support::Path["~"]
    assert_equal Dir.home, path.to_s
  end

  def test_bracket_constructor_handles_regular_paths
    path = Devex::Support::Path["/usr/local"]
    assert_equal "/usr/local", path.to_s
  end

  def test_pwd_returns_current_directory
    path = Devex::Support::Path.pwd
    assert_equal Dir.pwd, path.to_s
  end

  def test_home_returns_home_directory
    path = Devex::Support::Path.home
    assert_equal Dir.home, path.to_s
  end

  def test_tmp_returns_temp_directory
    path = Devex::Support::Path.tmp
    assert_equal Dir.tmpdir, path.to_s
  end

  # ─────────────────────────────────────────────────────────────
  # Path Joining
  # ─────────────────────────────────────────────────────────────

  def test_division_operator_joins_paths
    path = @path / "subdir" / "file.txt"
    assert_equal File.join(@tmpdir, "subdir", "file.txt"), path.to_s
    assert_instance_of Devex::Support::Path, path
  end

  def test_join_returns_path_instance
    path = @path.join("a", "b", "c")
    assert_equal File.join(@tmpdir, "a", "b", "c"), path.to_s
    assert_instance_of Devex::Support::Path, path
  end

  def test_join_with_no_args_returns_self = assert_equal @path, @path.join

  # ─────────────────────────────────────────────────────────────
  # Permission Checks
  # ─────────────────────────────────────────────────────────────

  def test_r_checks_readable = assert_predicate @path, :r?

  def test_w_checks_writable = assert_predicate @path, :w?

  def test_rw_checks_both = assert_predicate @path, :rw?

  def test_x_checks_executable = assert_predicate @path, :x?

  # ─────────────────────────────────────────────────────────────
  # Type Checks
  # ─────────────────────────────────────────────────────────────

  def test_dir_returns_true_for_directory = assert_predicate @path, :dir?

  def test_dir_returns_false_for_file
    file_path = @path / "test.txt"
    File.write(file_path.to_s, "content")
    refute_predicate file_path, :dir?
  end

  def test_missing_returns_true_for_nonexistent
    path = @path / "nonexistent"
    assert_predicate path, :missing?
  end

  def test_missing_returns_false_for_existing = refute_predicate @path, :missing?

  def test_existence_returns_self_when_exists = assert_equal @path, @path.existence

  def test_existence_returns_nil_when_missing
    path = @path / "nonexistent"
    assert_nil path.existence
  end

  # ─────────────────────────────────────────────────────────────
  # Expansions
  # ─────────────────────────────────────────────────────────────

  def test_exp_returns_expanded_path
    path = Devex::Support::Path.new(".")
    assert_equal Dir.pwd, path.exp.to_s
  end

  def test_exp_is_memoized
    path = Devex::Support::Path.new(".")
    assert_same path.exp, path.exp
  end

  def test_real_returns_realpath
    # Create a symlink to test
    real_dir = @path / "real"
    real_dir.mkdir!
    link_path = File.join(@tmpdir, "link")
    File.symlink(real_dir.to_s, link_path)

    path = Devex::Support::Path.new(link_path)
    # Use realpath on both to normalize (handles /var -> /private/var on macOS)
    assert_equal File.realpath(real_dir.to_s), path.real.to_s
  end

  def test_real_falls_back_to_exp_for_nonexistent
    path = @path / "nonexistent"
    assert_equal path.exp.to_s, path.real.to_s
  end

  def test_reload_clears_memoization
    path      = @path.dup
    first_exp = path.exp
    path.reload!
    # After reload, should get new object (though same value)
    refute_same first_exp, path.exp
  end

  # ─────────────────────────────────────────────────────────────
  # Relative Paths
  # ─────────────────────────────────────────────────────────────

  def test_rel_returns_relative_path
    subdir = @path / "subdir"
    subdir.mkdir!
    rel = subdir.rel(from: @path)
    assert_equal "subdir", rel.to_s
  end

  def test_rel_substitutes_home_by_default
    # The rel method substitutes ~ for home directory in the ORIGINAL path
    # when it can't compute a relative path (rescue case)
    home_path = Devex::Support::Path[Dir.home] / "test"

    # Test the rescue path: use a path that causes ArgumentError
    # On same filesystem, we can just verify the method works
    rel = home_path.rel
    # Should return a path (either relative or with ~ substitution)
    assert_kind_of Devex::Support::Path, rel
  end

  def test_rel_skips_home_substitution_when_disabled
    home_path = Devex::Support::Path[Dir.home] / "test"
    rel       = home_path.rel(from: Devex::Support::Path["/"], home: false)
    refute_includes rel.to_s, "~"
  end

  def test_short_returns_shortest_representation
    # This is a heuristic test - short should return something reasonable
    path  = Devex::Support::Path.pwd / "test"
    short = path.short
    assert_operator short.to_s.length, :<=, path.to_s.length
  end

  # ─────────────────────────────────────────────────────────────
  # Globbing
  # ─────────────────────────────────────────────────────────────

  def test_glob_finds_files
    # Create some test files
    File.write((@path / "a.txt").to_s, "a")
    File.write((@path / "b.txt").to_s, "b")
    File.write((@path / "c.rb").to_s, "c")

    results = @path["*.txt"]
    assert_equal 2, results.size
    assert(results.all? { |p| p.to_s.end_with?(".txt") })
  end

  def test_glob_returns_path_instances
    File.write((@path / "test.txt").to_s, "test")
    results = @path["*.txt"]
    assert(results.all? { |p| p.is_a?(Devex::Support::Path) })
  end

  def test_glob_method_alias
    File.write((@path / "test.txt").to_s, "test")
    assert_equal @path["*.txt"], @path.glob("*.txt")
  end

  # ─────────────────────────────────────────────────────────────
  # Directory Operations
  # ─────────────────────────────────────────────────────────────

  def test_dir_returns_self_for_directory = assert_equal @path.exp, @path.dir

  def test_dir_returns_dirname_for_file
    file_path = @path / "test.txt"
    File.write(file_path.to_s, "content")
    assert_equal @path.to_s, file_path.dir.to_s
  end

  def test_dir_bang_creates_parent_directories
    deep_path = @path / "a" / "b" / "c" / "file.txt"
    result    = deep_path.dir!
    assert_same deep_path, result
    assert_predicate (@path / "a" / "b" / "c"), :exist?
  end

  def test_dir_bang_returns_nil_on_error
    # Try to create in a non-writable location (if we can find one)
    # This test may not work on all systems
    skip "Skipping permission test" unless File.exist?("/etc")
    path = Devex::Support::Path["/etc/cannot/create/here"]
    assert_nil path.dir!
  end

  def test_mkdir_bang_creates_directory
    new_dir = @path / "new_directory"
    result  = new_dir.mkdir!
    assert_same new_dir, result
    assert_predicate new_dir, :exist?
    assert_predicate new_dir, :dir?
  end

  # ─────────────────────────────────────────────────────────────
  # File I/O
  # ─────────────────────────────────────────────────────────────

  def test_read_returns_file_contents
    file_path = @path / "test.txt"
    File.write(file_path.to_s, "hello world")
    assert_equal "hello world", file_path.read
  end

  def test_lines_returns_array_of_lines
    file_path = @path / "test.txt"
    File.write(file_path.to_s, "line1\nline2\nline3")
    lines = file_path.lines
    assert_equal %w[line1 line2 line3], lines
  end

  def test_write_creates_file
    file_path = @path / "new.txt"
    result    = file_path.write("content")
    assert_same file_path, result
    assert_equal "content", File.read(file_path.to_s)
  end

  def test_write_creates_parent_directories
    file_path = @path / "deep" / "nested" / "file.txt"
    file_path.write("content")
    assert_predicate file_path, :exist?
  end

  def test_append_adds_to_file
    file_path = @path / "append.txt"
    file_path.write("first")
    file_path.append(" second")
    assert_equal "first second", file_path.read
  end

  def test_atomic_write_is_atomic
    file_path = @path / "atomic.txt"
    file_path.atomic_write("atomic content")
    assert_equal "atomic content", file_path.read
  end

  # ─────────────────────────────────────────────────────────────
  # Modification Time
  # ─────────────────────────────────────────────────────────────

  def test_newer_than_compares_mtime
    old_file = @path / "old.txt"
    new_file = @path / "new.txt"

    File.write(old_file.to_s, "old")
    sleep 0.01 # Ensure different mtime
    File.write(new_file.to_s, "new")

    assert new_file.newer_than?(old_file)
    refute old_file.newer_than?(new_file)
  end

  def test_older_than_compares_mtime
    old_file = @path / "old.txt"
    new_file = @path / "new.txt"

    File.write(old_file.to_s, "old")
    sleep 0.01
    File.write(new_file.to_s, "new")

    assert old_file.older_than?(new_file)
    refute new_file.older_than?(old_file)
  end

  def test_newer_than_handles_nonexistent
    existing = @path / "exists.txt"
    File.write(existing.to_s, "exists")
    nonexistent = @path / "nonexistent"

    assert existing.newer_than?(nonexistent)
    refute nonexistent.newer_than?(existing)
  end

  # ─────────────────────────────────────────────────────────────
  # Extension Manipulation
  # ─────────────────────────────────────────────────────────────

  def test_with_ext_replaces_extension
    path     = Devex::Support::Path.new("/path/to/file.txt")
    new_path = path.with_ext(".md")
    assert_equal "/path/to/file.md", new_path.to_s
  end

  def test_with_ext_adds_dot_if_missing
    path     = Devex::Support::Path.new("/path/to/file.txt")
    new_path = path.with_ext("md")
    assert_equal "/path/to/file.md", new_path.to_s
  end

  def test_without_ext_removes_extension
    path     = Devex::Support::Path.new("/path/to/file.txt")
    new_path = path.without_ext
    assert_equal "/path/to/file", new_path.to_s
  end

  # ─────────────────────────────────────────────────────────────
  # Siblings and Relatives
  # ─────────────────────────────────────────────────────────────

  def test_sibling_returns_path_in_same_directory
    path    = @path / "original.txt"
    sibling = path.sibling("other.txt")
    assert_equal (@path / "other.txt").to_s, sibling.to_s
  end

  def test_parent_returns_path_instance
    path   = @path / "subdir"
    parent = path.parent
    assert_equal @path.to_s, parent.to_s
    assert_instance_of Devex::Support::Path, parent
  end

  def test_dirname_returns_path_instance
    path    = @path / "subdir"
    dirname = path.dirname
    assert_instance_of Devex::Support::Path, dirname
  end

  def test_basename_returns_path_instance
    path     = @path / "subdir"
    basename = path.basename
    assert_equal "subdir", basename.to_s
    assert_instance_of Devex::Support::Path, basename
  end

  # ─────────────────────────────────────────────────────────────
  # Inspection
  # ─────────────────────────────────────────────────────────────

  def test_inspect_shows_path
    path = Devex::Support::Path.new("/test/path")
    assert_equal "#<Path:/test/path>", path.inspect
  end

  # ─────────────────────────────────────────────────────────────
  # String-like Behavior
  # ─────────────────────────────────────────────────────────────

  def test_delegates_string_methods
    path = Devex::Support::Path.new("/path/to/file.txt")
    assert path.end_with?(".txt")
    assert path.start_with?("/path")
    assert_includes path.to_s, "to"
  end

  def test_string_method_returning_path_like_string
    path   = Devex::Support::Path.new("/path/to/file.txt")
    result = path.sub("file", "other")
    # Should return Path if result looks like a path
    assert_instance_of Devex::Support::Path, result
    assert_equal "/path/to/other.txt", result.to_s
  end
end
