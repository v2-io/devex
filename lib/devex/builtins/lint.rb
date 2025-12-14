# frozen_string_literal: true

desc "Run linter"

long_desc <<~DESC
  Auto-detects and runs your linter.

  Supports:
    - RuboCop (.rubocop.yml)
    - StandardRB (.standard.yml)

  Pass additional arguments after -- to forward to the linter:
    dx lint -- --only=Style/StringLiterals
DESC

flag :fix, "-a", "--fix", desc: "Auto-fix correctable offenses"
flag :unsafe, "-A", "--unsafe-fix", desc: "Auto-fix including unsafe corrections"
flag :diff, "-d", "--diff", desc: "Only lint changed files (git diff)"
remaining_args :files, desc: "Specific files or patterns to lint"

include Devex::Exec

def run
  linter = detect_linter
  unless linter
    $stderr.puts "No linter detected."
    $stderr.puts "Expected: .rubocop.yml (rubocop) or .standard.yml (standardrb)"
    exit 1
  end

  case linter
  when :rubocop   then run_rubocop
  when :standardrb then run_standardrb
  end
end

def detect_linter
  return :standardrb if File.exist?(".standard.yml")
  return :rubocop if File.exist?(".rubocop.yml")

  # Check Gemfile for linter gems
  if File.exist?("Gemfile")
    content = File.read("Gemfile")
    return :standardrb if content.include?("standard")
    return :rubocop if content.include?("rubocop")
  end

  nil
end

def run_rubocop
  args = ["rubocop"]
  args << "-a" if fix && !unsafe
  args << "-A" if unsafe
  args += changed_files if diff && files.empty?
  args += files unless files.empty?

  cmd(*args).exit_on_failure!
end

def run_standardrb
  args = ["standardrb"]
  args << "--fix" if fix || unsafe
  args += changed_files if diff && files.empty?
  args += files unless files.empty?

  cmd(*args).exit_on_failure!
end

# Use capture() to get git output, then .stdout_lines for clean line splitting
def changed_files
  result = capture("git", "diff", "--name-only", "--diff-filter=ACMR", "HEAD")
  return [] if result.failed?

  result.stdout_lines
        .select { |f| f.end_with?(".rb") }
        .select { |f| File.exist?(f) }
end
