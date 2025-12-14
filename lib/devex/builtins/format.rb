# frozen_string_literal: true

# Uses prj paths for all file operations.

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

def run
  linter = detect_linter
  unless linter
    $stderr.puts "No linter detected."
    $stderr.puts "Expected: .rubocop.yml (rubocop) or .standard.yml (standardrb)"
    $stderr.puts "Project root: #{prj.root}"
    exit 1
  end

  case linter
  when :rubocop   then run_rubocop
  when :standardrb then run_standardrb
  end
end

def prj
  @prj ||= Devex::ProjectPaths.new
end

def detect_linter
  return :standardrb if (prj.root / ".standard.yml").exist?
  return :rubocop if (prj.root / ".rubocop.yml").exist?

  gemfile = prj.root / "Gemfile"
  if gemfile.exist?
    content = gemfile.read
    return :standardrb if content.include?("standard")
    return :rubocop if content.include?("rubocop")
  end

  nil
end

def run_rubocop
  args = ["rubocop"]
  args << (unsafe ? "-A" : "-a")
  args += files unless files.empty?

  cmd(*args, chdir: prj.root).exit_on_failure!
end

def run_standardrb
  args = ["standardrb", "--fix"]
  args += files unless files.empty?

  cmd(*args, chdir: prj.root).exit_on_failure!
end
