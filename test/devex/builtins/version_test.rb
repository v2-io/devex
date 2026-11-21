# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "tmpdir"

# End-to-end tests for the `dx version` builtin: each test runs the real
# executable in a scratch project and then reads the version file back.
#
# They go through the executable on purpose. The defect these were written
# for was a command that printed "2.0.0 → 2.1.0" and exited 0 while leaving
# the file untouched, so the thing worth asserting is always the pair
# (what the command said, what is on disk).
class VersionBuiltinTest < Minitest::Test
  DX = File.expand_path("../../../exe/dx", __dir__)

  def setup
    @dir = Dir.mktmpdir("dx-version-test")
    Dir.mkdir(File.join(@dir, ".git")) # project marker
  end

  def teardown = FileUtils.remove_entry(@dir)

  # Run dx in the scratch project. Captured output is not a tty, so dx is in
  # agent mode and prints JSON on success.
  def dx(*)
    env = ENV.keys.grep(/\A(DX_|DEVEX_)/).to_h { |k| [k, nil] }
    out, err, status = Open3.capture3(env, RbConfig.ruby, DX, *, chdir: @dir)
    [out, err, status.exitstatus]
  end

  def write(relative, content)
    path = File.join(@dir, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def content(relative) = File.read(File.join(@dir, relative))

  # ─────────────────────────────────────────────────────────────
  # Bare VERSION file
  # ─────────────────────────────────────────────────────────────

  def test_show_reads_bare_file
    write("VERSION", "2.0.0.pre\n")
    out, _, code = dx("version")

    assert_equal 0, code
    assert_equal "2.0.0.pre", JSON.parse(out)["version"]
  end

  def test_bump_writes_bare_file
    write("VERSION", "1.2.3\n")
    out, _, code = dx("version", "bump", "patch")

    assert_equal 0, code
    assert_equal "1.2.4", JSON.parse(out)["new_version"]
    assert_equal "1.2.4\n", content("VERSION")
  end

  def test_bump_minor_and_major_reset_lower_segments
    write("VERSION", "1.2.3\n")
    dx("version", "bump", "minor")
    assert_equal "1.3.0\n", content("VERSION")

    dx("version", "bump", "major")
    assert_equal "2.0.0\n", content("VERSION")
  end

  def test_set_writes_bare_file
    write("VERSION", "2.0.0\n")
    out, _, code = dx("version", "set", "2.1.0")

    assert_equal 0, code
    assert_equal "2.1.0", JSON.parse(out)["new_version"]
    assert_equal "2.1.0\n", content("VERSION")
  end

  def test_bare_file_without_trailing_newline_stays_that_way
    write("VERSION", "1.0.0")
    dx("version", "set", "1.0.1")

    assert_equal "1.0.1", content("VERSION")
  end

  # ─────────────────────────────────────────────────────────────
  # Ruby constant
  # ─────────────────────────────────────────────────────────────

  def test_bump_writes_ruby_constant
    write("lib/foo/version.rb", %(module Foo\n  VERSION = "0.3.7"\nend\n))
    _, _, code = dx("version", "bump", "patch")

    assert_equal 0, code
    assert_equal %(module Foo\n  VERSION = "0.3.8"\nend\n), content("lib/foo/version.rb")
  end

  def test_ruby_constant_keeps_its_quote_style_and_spacing
    write("lib/foo/version.rb", "module Foo\n  VERSION  = '0.3.7'.freeze\nend\n")
    dx("version", "set", "1.0.0")

    assert_equal "module Foo\n  VERSION  = '1.0.0'.freeze\nend\n", content("lib/foo/version.rb")
  end

  # ─────────────────────────────────────────────────────────────
  # Prerelease versions
  # ─────────────────────────────────────────────────────────────

  def test_bump_refuses_prerelease_and_changes_nothing
    write("VERSION", "2.0.0.pre\n")
    out, err, code = dx("version", "bump", "patch")

    assert_equal 1, code
    assert_empty out
    assert_match(/Can't bump '2\.0\.0\.pre'/, err)
    assert_equal "2.0.0.pre\n", content("VERSION")
  end

  def test_bump_refuses_semver_style_prerelease
    write("VERSION", "2.0.0-rc.1\n")
    _, _, code = dx("version", "bump", "minor")

    assert_equal 1, code
    assert_equal "2.0.0-rc.1\n", content("VERSION")
  end

  def test_bump_refuses_versions_that_are_not_three_segments
    %w[1.2 1.2.3.4].each do |version|
      write("VERSION", "#{version}\n")
      _, _, code = dx("version", "bump", "patch")

      assert_equal 1, code, "bump of #{version} should be refused"
      assert_equal "#{version}\n", content("VERSION")
    end
  end

  def test_bump_pre_increments_the_counter_in_either_spelling
    { "2.0.0-alpha.0" => "2.0.0-alpha.1", "2.0.0-rc.9" => "2.0.0-rc.10",
      "2.0.0.alpha.0" => "2.0.0.alpha.1", "2.0.0.pre.1" => "2.0.0.pre.2",
      "2.0.0-alpha1.3" => "2.0.0-alpha1.4" }.each do |from, to|
      write("VERSION", "#{from}\n")
      out, _, code = dx("version", "bump", "pre")

      assert_equal 0, code, "bump pre of #{from}"
      assert_equal to, JSON.parse(out)["new_version"]
      assert_equal "#{to}\n", content("VERSION")
    end
  end

  def test_bump_pre_refuses_versions_without_a_prerelease_counter
    %w[2.0.0 2.0.0.pre 2.0.0-alpha 1.2.3.4 2.0.0-alpha.1+build.5].each do |version|
      write("VERSION", "#{version}\n")
      _, err, code = dx("version", "bump", "pre")

      assert_equal 1, code, "bump pre of #{version} should be refused"
      assert_match(/Nothing was changed/, err)
      assert_equal "#{version}\n", content("VERSION")
    end
  end

  def test_bump_patch_refuses_a_counted_prerelease
    write("VERSION", "2.0.0-alpha.0\n")
    _, _, code = dx("version", "bump", "patch")

    assert_equal 1, code
    assert_equal "2.0.0-alpha.0\n", content("VERSION")
  end

  def test_set_moves_into_and_out_of_prerelease
    write("VERSION", "2.0.0.pre\n")

    _, _, code = dx("version", "set", "2.0.0.pre.2")
    assert_equal 0, code
    assert_equal "2.0.0.pre.2\n", content("VERSION")

    _, _, code = dx("version", "set", "2.0.0-rc.1+build.5")
    assert_equal 0, code
    assert_equal "2.0.0-rc.1+build.5\n", content("VERSION")

    _, _, code = dx("version", "set", "2.0.0")
    assert_equal 0, code
    assert_equal "2.0.0\n", content("VERSION")
  end

  def test_set_rejects_malformed_versions
    write("VERSION", "1.0.0\n")

    ["1.0", "1.0.0garbage", "1.0.0.", "1.0.0-", "v1.0.0", "1.0.0 beta"].each do |bad|
      _, _, code = dx("version", "set", bad)

      assert_equal 1, code, "set #{bad.inspect} should be rejected"
      assert_equal "1.0.0\n", content("VERSION")
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Named version files (versions: in the dx config)
  # ─────────────────────────────────────────────────────────────

  def named_project(default: nil)
    write(".dx.yml", "versions:\n  spec: VERSION.SPEC\n  impl: impl/version.rb\n")
    write("VERSION.SPEC", "2.0.0-alpha.0\n")
    write("impl/version.rb", %(VERSION = "0.1.0"\n))
    write("VERSION", "#{default}\n") if default
  end

  def test_named_show
    named_project
    out, _, code = dx("version", "spec")
    data = JSON.parse(out)

    assert_equal 0, code
    assert_equal "2.0.0-alpha.0", data["version"]
    assert_equal "spec", data["name"]
    assert data["file"].end_with?("VERSION.SPEC")
  end

  def test_named_bump_and_set_touch_only_the_named_file
    named_project(default: "9.9.9")

    out, _, code = dx("version", "spec", "bump", "pre")
    assert_equal 0, code
    assert_equal "2.0.0-alpha.1", JSON.parse(out)["new_version"]
    assert_equal "2.0.0-alpha.1\n", content("VERSION.SPEC")

    _, _, code = dx("version", "impl", "bump", "minor")
    assert_equal 0, code
    assert_equal %(VERSION = "0.2.0"\n), content("impl/version.rb")

    _, _, code = dx("version", "spec", "set", "2.0.0-beta.0")
    assert_equal 0, code
    assert_equal "2.0.0-beta.0\n", content("VERSION.SPEC")

    assert_equal "9.9.9\n", content("VERSION")
  end

  def test_unnamed_commands_keep_using_the_default_file
    named_project(default: "1.0.0")

    out, = dx("version")
    assert_equal "1.0.0", JSON.parse(out)["version"]

    dx("version", "bump", "patch")
    assert_equal "1.0.1\n", content("VERSION")
    assert_equal "2.0.0-alpha.0\n", content("VERSION.SPEC")
  end

  def test_show_without_default_file_lists_named_versions
    named_project
    out, _, code = dx("version")
    data = JSON.parse(out)

    assert_equal 0, code
    assert_equal "project", data["source"]
    assert_equal "2.0.0-alpha.0", data["versions"]["spec"]["version"]
    assert_equal "0.1.0", data["versions"]["impl"]["version"]
  end

  def test_unnamed_bump_without_default_file_points_at_the_names
    named_project
    _, err, code = dx("version", "bump", "patch")

    assert_equal 1, code
    assert_match(/dx version <name>/, err)
    assert_match(/spec/, err)
  end

  def test_named_refusals_change_nothing
    named_project

    [%w[spec bump patch], %w[spec bump], %w[spec frob], %w[spec set], %w[spec set nope],
     %w[spec bump pre extra], %w[nope], %w[nope bump pre]].each do |args|
      _, err, code = dx("version", *args)

      assert_equal 1, code, "dx version #{args.join(' ')} should fail"
      refute_empty err
      assert_equal "2.0.0-alpha.0\n", content("VERSION.SPEC")
    end
  end

  def test_named_file_missing_is_an_error
    write(".dx.yml", "versions:\n  spec: VERSION.SPEC\n")
    _, err, code = dx("version", "spec")

    assert_equal 1, code
    assert_match(/not found/, err)
  end

  def test_reserved_and_malformed_names_in_config_are_rejected
    write("VERSION.SPEC", "1.0.0\n")

    ["versions:\n  bump: VERSION.SPEC\n", "versions:\n  'a b': VERSION.SPEC\n",
     "versions: VERSION.SPEC\n", "versions:\n  spec:\n"].each do |config|
      write(".dx.yml", config)
      _, err, code = dx("version", "spec")

      assert_equal 1, code, "config #{config.inspect} should be rejected"
      refute_empty err
    end
  end

  def test_names_work_in_organized_mode_config
    Dir.mkdir(File.join(@dir, ".dx"))
    write(".dx/config.yml", "versions:\n  spec: VERSION.SPEC\n")
    write("VERSION.SPEC", "1.0.0\n")
    dx("version", "spec", "bump", "major")

    assert_equal "2.0.0\n", content("VERSION.SPEC")
  end

  def test_unknown_word_after_version_is_an_error_not_a_show
    write("VERSION", "1.0.0\n")
    out, _, code = dx("version", "bmup", "patch")

    assert_equal 1, code
    assert_empty out
    assert_equal "1.0.0\n", content("VERSION")
  end

  # ─────────────────────────────────────────────────────────────
  # A file we can't rewrite
  # ─────────────────────────────────────────────────────────────

  def test_unwritable_shape_fails_instead_of_reporting_success
    original = "1.0.0\n# released 2026-01-01\n"
    write("VERSION", original)
    out, err, code = dx("version", "set", "1.1.0")

    assert_equal 1, code
    assert_empty out
    assert_match(/Nothing was changed/, err)
    assert_equal original, content("VERSION")
  end
end
