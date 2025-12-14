# frozen_string_literal: true

# Uses prj.linter - fails fast with helpful message if not found.

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
  # prj.linter fails fast if no .rubocop.yml or .standard.yml found
  linter_config = prj.linter

  case linter_config.basename.to_s
  when ".standard.yml" then run_standardrb
  when ".rubocop.yml"  then run_rubocop
  end
end

def prj = @prj ||= Devex::ProjectPaths.new

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
