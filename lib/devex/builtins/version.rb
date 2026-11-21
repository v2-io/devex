# frozen_string_literal: true

# Shared helpers - these are defined at the top level and available to all tools
# when the file is re-evaluated in the execution context

VERSION_FILE_PATTERNS = [
  "lib/*/version.rb",
  "VERSION",
  "version.rb"
].freeze

VERSION_REGEX = /VERSION\s*=\s*(["'])([^"']+)\1/

# What `dx version set` accepts: MAJOR.MINOR.PATCH, optionally followed by a
# prerelease tail in either RubyGems style (2.0.0.pre, 2.0.0.rc.1) or SemVer
# style (2.0.0-rc.1), and optionally SemVer build metadata (+build.5).
# Deliberately neutral between the two conventions: which one a project uses
# is the project's choice, not ours.
SETTABLE_VERSION = /\A\d+\.\d+\.\d+(?:[.-][0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?(?:\+[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?\z/

# What `dx version bump` can act on: exactly MAJOR.MINOR.PATCH.
BUMPABLE_VERSION = /\A(\d+)\.(\d+)\.(\d+)\z/

def find_version_file(root)
  VERSION_FILE_PATTERNS.each do |pattern|
    matches = Dir.glob(File.join(root, pattern))
    return matches.first if matches.any?
  end
  nil
end

# Extract the version from a version file's content. Two shapes are
# understood: a Ruby source file with a `VERSION = "x"` constant, and a bare
# file whose whole content is the version (e.g. a top-level VERSION file).
def parse_version(content)
  if content =~ VERSION_REGEX
    Regexp.last_match(2)
  else
    content.strip
  end
end

def read_version(file) = parse_version(File.read(file))

# Content of the version file with old_version replaced by new_version, or nil
# if this content isn't in a shape we know how to rewrite.
def replace_version(content, old_version, new_version)
  if content =~ VERSION_REGEX
    # Ruby constant: keep the file's own spacing and quote style.
    content.sub(/(VERSION\s*=\s*)(["'])#{Regexp.escape(old_version)}\2/) do
      "#{Regexp.last_match(1)}#{Regexp.last_match(2)}#{new_version}#{Regexp.last_match(2)}"
    end
  elsif content.strip == old_version && !old_version.empty? && old_version !~ /\s/
    # Bare file: swap the version, keep surrounding whitespace (trailing newline).
    content.sub(old_version) { new_version }
  end
end

# Write new_version into file. The new content is checked *before* it is
# written: if it would not read back as new_version, nothing is written and the
# command fails. A version command must never report a change it did not make.
def write_version(file, old_version, new_version)
  content     = File.read(file)
  new_content = replace_version(content, old_version, new_version)

  unless new_content && parse_version(new_content) == new_version
    version_error("Don't know how to write a version into #{file}. " \
                  "Expected a `VERSION = \"x.y.z\"` constant, or a file containing only the version. " \
                  "Nothing was changed.")
  end

  File.write(file, new_content)
end

# A prerelease version whose tail ends in a numeric counter, in either
# spelling: 2.0.0-alpha.0 (SemVer) or 2.0.0.alpha.0 (RubyGems). The stage
# label must contain a letter, so 1.2.3.4 is not mistaken for one.
PRERELEASE_COUNTER = /\A(\d+\.\d+\.\d+[.-](?:[0-9A-Za-z]+[.-])*?[0-9A-Za-z]*[A-Za-z][0-9A-Za-z]*[.-])(\d+)\z/

# Returns the bumped version string, or nil if this kind of bump doesn't
# apply to this version.
#
# major/minor/patch apply only to plain MAJOR.MINOR.PATCH: what they should do
# to a prerelease (release it? skip past it?) depends on a convention we don't
# assume. "pre" applies only to a prerelease ending in a numeric counter, and
# increments that counter; this means the same thing in both spellings.
# Moving between stages (alpha → beta → release) is `dx version set`.
def bump_version(version, type)
  if type == "pre"
    match = PRERELEASE_COUNTER.match(version)
    return match && "#{match[1]}#{match[2].to_i + 1}"
  end

  match = BUMPABLE_VERSION.match(version)
  return nil unless match

  major, minor, patch = match.captures.map(&:to_i)

  case type
  when "major" then "#{major + 1}.0.0"
  when "minor" then "#{major}.#{minor + 1}.0"
  when "patch" then "#{major}.#{minor}.#{patch + 1}"
  end
end

def version_error(message)
  Devex::Output.error(message)
  exit(1)
end

def version_output(data)
  # Use output_format from ExecutionContext (handles global + tool flags + context default)
  fmt = respond_to?(:output_format) ? output_format : :text

  case fmt
  when :json, :yaml then Devex::Output.data(data, format: fmt)
  else
    text = if data[:old_version] && data[:new_version]
             "#{data[:old_version]} → #{data[:new_version]}"
           else
             data[:version].to_s
           end
    $stdout.print text, "\n"
  end
end

# --- Main tool ---

desc "Show or manage version"

def run
  # Try project root first, then fall back to effective working directory.
  # This handles cases where a project exists but isn't yet recognized
  # (e.g., no .git, Gemfile, or other project markers).
  fallback_dir = Devex::Dirs.dest_dir.to_s
  search_roots = [cli.project_root, fallback_dir].compact.uniq

  version_data = nil
  search_roots.each do |root|
    version_file = find_version_file(root)
    if version_file
      version_data = { version: read_version(version_file), source: "project", file: version_file }
      break
    end
  end

  version_data ||= { version: Devex::VERSION, source: "devex" }

  version_output(version_data)
end

# --- Subtools ---

tool "bump" do
  desc "Bump version (major, minor, patch, or pre)"
  long_desc <<~DESC
    Bump the project version following semantic versioning.

    MAJOR version for incompatible API changes
    MINOR version for backwards-compatible new functionality
    PATCH version for backwards-compatible bug fixes
    PRE   the counter of a prerelease: 2.0.0-alpha.0 -> 2.0.0-alpha.1
          (RubyGems spelling works too: 2.0.0.alpha.0 -> 2.0.0.alpha.1)

    major, minor and patch apply only to a plain MAJOR.MINOR.PATCH version;
    pre applies only to a prerelease that ends in a numeric counter. Anything
    else is refused rather than guessed at. To move between stages or to
    release (2.0.0-alpha.3 -> 2.0.0-beta.0 -> 2.0.0), use `dx version set`.
  DESC

  required_arg :type, desc: "Version component: major, minor, patch, or pre"

  def run
    version_error("Invalid version type '#{type}'. Use: major, minor, patch, or pre") unless %w[major minor patch pre].include?(type)

    version_error("Not in a project directory") unless cli.project_root

    version_file = find_version_file(cli.project_root)
    version_error("Could not find version file") unless version_file

    old_version = read_version(version_file)
    new_version = bump_version(old_version, type)
    unless new_version
      reason = if type == "pre"
                 "'pre' needs a prerelease version ending in a numeric counter (e.g. 2.0.0-alpha.0)"
               else
                 "'#{type}' only applies to a plain MAJOR.MINOR.PATCH version"
               end
      version_error("Can't bump '#{old_version}': #{reason}. " \
                    "Use `dx version set <version>` to choose the next version explicitly. Nothing was changed.")
    end

    write_version(version_file, old_version, new_version)

    version_output(
      { old_version: old_version, new_version: new_version, type: type, file: version_file }
    )
  end
end

tool "set" do
  desc "Set version to a specific value"

  required_arg :version, desc: "Version string (e.g., 1.0.0, 2.0.0.pre, 2.0.0-rc.1)"

  def run
    unless version.match?(SETTABLE_VERSION)
      version_error("Invalid version format '#{version}'. " \
                    "Use MAJOR.MINOR.PATCH, optionally with a prerelease tail (e.g. 2.0.0.pre or 2.0.0-rc.1)")
    end

    version_error("Not in a project directory") unless cli.project_root

    version_file = find_version_file(cli.project_root)
    version_error("Could not find version file") unless version_file

    old_version = read_version(version_file)
    write_version(version_file, old_version, version)

    version_output(
      { old_version: old_version, new_version: version, file: version_file }
    )
  end
end
