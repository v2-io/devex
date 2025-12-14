# frozen_string_literal: true

desc "Auto-format code"

long_desc <<~DESC
  Auto-formats code using your linter's fix mode.

  Equivalent to `dx lint --fix`.

  Supports:
    - RuboCop (.rubocop.yml) - runs rubocop -a
    - StandardRB (.standard.yml) - runs standardrb --fix
DESC

flag :unsafe, "-A", "--unsafe", desc: "Include unsafe corrections"
remaining_args :files, desc: "Specific files or patterns to format"

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

  if File.exist?("Gemfile")
    content = File.read("Gemfile")
    return :standardrb if content.include?("standard")
    return :rubocop if content.include?("rubocop")
  end

  nil
end

def run_rubocop
  args = ["rubocop"]
  args << (unsafe ? "-A" : "-a")
  args += files unless files.empty?

  cmd(*args).exit_on_failure!
end

def run_standardrb
  args = ["standardrb", "--fix"]
  args += files unless files.empty?

  cmd(*args).exit_on_failure!
end
