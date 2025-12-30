# frozen_string_literal: true

# Uses prj.linter if present, falls back to bundled rubocop-dx.yml config.

desc "Run linter"

long_desc <<~DESC
  Auto-detects and runs your linter from the project root.

  Supports:
    - RuboCop (.rubocop.yml)
    - StandardRB (.standard.yml)

  If no linter config is found, uses the bundled rubocop-dx.yml conventions.
  Create a .rubocop.yml to customize:

    inherit_gem:
      devex: config/rubocop-dx.yml

    # Project-specific overrides...

  Pass additional arguments after -- to forward to the linter:
    dx lint -- --only=Style/StringLiterals
DESC

flag :fix, "-a", "--fix", desc: "Auto-fix correctable offenses"
flag :unsafe, "-A", "--unsafe-fix", desc: "Auto-fix including unsafe corrections"
flag :diff, "-d", "--diff", desc: "Only lint changed files (git diff)"
remaining_args :files, desc: "Specific files or patterns to lint"

def run
  linter_config = detect_linter

  case linter_config
  when :bundled  then run_rubocop_bundled
  when :standard then run_standardrb
  else                run_rubocop
  end
end

def prj = @prj ||= Devex::ProjectPaths.new

# Detect which linter to use without failing if none found
def detect_linter
  standard_yml = prj.root / ".standard.yml"
  rubocop_yml  = prj.root / ".rubocop.yml"

  if standard_yml.exist?
    :standard
  elsif rubocop_yml.exist?
    :rubocop
  else
    :bundled
  end
end

def run_rubocop
  args = ["rubocop"]
  args << "-a" if fix && !unsafe
  args << "-A" if unsafe
  args += changed_files if diff && files.empty?
  args += files unless files.empty?

  cmd(*args, chdir: prj.root).exit_on_failure!
end

def run_rubocop_bundled
  bundled_config = File.join(Devex.gem_root, "config", "rubocop-dx.yml")

  warn "Using bundled rubocop-dx.yml (no .rubocop.yml found)"
  warn "  Create .rubocop.yml to customize conventions."
  warn ""

  args = ["rubocop", "--config", bundled_config.to_s]
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
