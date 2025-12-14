# frozen_string_literal: true

# Uses prj.test to find test directory - no manual path detection needed.

desc "Run tests"

long_desc <<~DESC
  Auto-detects and runs your test suite from the project root.

  Supports:
    - Minitest (test/ directory)
    - RSpec (spec/ directory or .rspec file)

  Pass additional arguments after -- to forward to the test runner:
    dx test -- --seed=12345
    dx test -- spec/models/user_spec.rb
DESC

flag :coverage, "-c", "--coverage", desc: "Run with coverage (sets COVERAGE=1)"
flag :fail_fast, "--fail-fast", desc: "Stop on first failure"
remaining_args :files, desc: "Specific test files or patterns"

def run
  # prj.test finds test/, spec/, or tests/ automatically
  test_dir = begin
    prj.test
  rescue StandardError
    nil
  end

  unless test_dir
    $stderr.puts "No test directory found (test/, spec/, or tests/)"
    $stderr.puts "Project root: #{prj.root}"
    exit 1
  end

  env = coverage ? { "COVERAGE" => "1" } : {}

  # Determine framework from directory name
  case test_dir.basename.to_s
  when "spec"
    run_rspec(env)
  when "test", "tests"
    run_minitest(env)
  else
    $stderr.puts "Unknown test directory: #{test_dir.basename}"
    exit 1
  end
end

def prj
  @prj ||= Devex::ProjectPaths.new
end

def run_minitest(env)
  if files.empty?
    # Use rake test if Rakefile exists with test task
    rakefile = prj.root / "Rakefile"
    if rakefile.exist? && rake_has_test_task?(rakefile)
      cmd("rake", "test", env: env, chdir: prj.root).exit_on_failure!
    else
      # Run all tests directly
      test_files = prj.test.glob("**/*_test.rb")
      if test_files.empty?
        $stderr.puts "No test files found in #{prj.test}"
        exit 1
      end

      relative_files = test_files.map { |f| f.relative_path_from(prj.root) }
      cmd("ruby", "-Itest", "-Ilib", "-e",
          relative_files.map { |f| "require './#{f}'" }.join("; "),
          env: env, chdir: prj.root).exit_on_failure!
    end
  else
    files.each do |file|
      cmd("ruby", "-Itest", "-Ilib", file, env: env, chdir: prj.root).exit_on_failure!
    end
  end
end

def run_rspec(env)
  args = ["rspec"]
  args << "--fail-fast" if fail_fast
  args += files unless files.empty?

  cmd(*args, env: env, chdir: prj.root).exit_on_failure!
end

def rake_has_test_task?(rakefile)
  content = rakefile.read
  content.include?("TestTask") || content.include?("task :test") || content.include?("task 'test'")
rescue StandardError
  false
end
