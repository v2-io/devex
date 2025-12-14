# frozen_string_literal: true

# Uses prj paths for all file operations.

desc "Run linter"

long_desc <<~DESC
  Auto-detects and runs your linter from the project root.

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

# Linter detection - checks config files and Gemfile
def detect_linter
  return :standardrb if (prj.root / ".standard.yml").exist?
  return :rubocop if (prj.root / ".rubocop.yml").exist?

  # Check Gemfile for linter gems
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
  args << "-a" if fix && !unsafe
  args << "-A" if unsafe
  args += changed_files if diff && files.empty?
  args += files unless files.empty?

  cmd(*args, chdir: prj.root).exit_on_failure!
end

def run_standardrb
  args = ["standardrb"]
  args << "--fix" if fix || unsafe
  args += changed_files if diff && files.empty?
  args += files unless files.empty?

  cmd(*args, chdir: prj.root).exit_on_failure!
end

def changed_files
  result = capture("git", "diff", "--name-only", "--diff-filter=ACMR", "HEAD", chdir: prj.root)
  return [] if result.failed?

  result.stdout_lines
        .select { |f| f.end_with?(".rb") }
        .select { |f| (prj.root / f).exist? }
end
