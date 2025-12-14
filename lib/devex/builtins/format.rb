# frozen_string_literal: true

# Uses prj.linter - fails fast with helpful message if not found.

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
  args << (unsafe ? "-A" : "-a")
  args += files unless files.empty?

  cmd(*args, chdir: prj.root).exit_on_failure!
end

def run_standardrb
  args = ["standardrb", "--fix"]
  args += files unless files.empty?

  cmd(*args, chdir: prj.root).exit_on_failure!
end
