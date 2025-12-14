# frozen_string_literal: true

desc "Run tests"

long_desc <<~DESC
  Auto-detects and runs your test suite.

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

include Devex::Exec

def run
  framework = detect_framework
  unless framework
    $stderr.puts "No test framework detected."
    $stderr.puts "Expected: test/ (minitest) or spec/ (rspec)"
    exit 1
  end

  env = coverage ? { "COVERAGE" => "1" } : {}

  case framework
  when :minitest then run_minitest(env)
  when :rspec    then run_rspec(env)
  end
end

def detect_framework
  return :rspec if File.exist?(".rspec") || File.directory?("spec")
  return :minitest if File.directory?("test")

  nil
end

def run_minitest(env)
  if files.empty?
    # Use rake test if Rakefile exists with test task
    if File.exist?("Rakefile") && rake_has_test_task?
      cmd("rake", "test", env: env).exit_on_failure!
    else
      # Run all tests directly
      test_files = Dir.glob("test/**/*_test.rb")
      if test_files.empty?
        $stderr.puts "No test files found in test/"
        exit 1
      end

      cmd("ruby", "-Itest", "-Ilib", "-e",
          test_files.map { |f| "require './#{f}'" }.join("; "),
          env: env).exit_on_failure!
    end
  else
    # Run specific files
    files.each do |file|
      cmd("ruby", "-Itest", "-Ilib", file, env: env).exit_on_failure!
    end
  end
end

def run_rspec(env)
  args = ["rspec"]
  args << "--fail-fast" if fail_fast
  args += files unless files.empty?

  cmd(*args, env: env).exit_on_failure!
end

def rake_has_test_task?
  return false unless File.exist?("Rakefile")

  content = File.read("Rakefile")
  content.include?("TestTask") || content.include?("task :test") || content.include?("task 'test'")
rescue StandardError
  false
end
