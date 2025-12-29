# frozen_string_literal: true

# Shared helpers - these are defined at the top level and available to all tools
# when the file is re-evaluated in the execution context

VERSION_FILE_PATTERNS = [
  "lib/*/version.rb",
  "VERSION",
  "version.rb"
].freeze

VERSION_REGEX = /VERSION\s*=\s*["']([^"']+)["']/

def find_version_file(root)
  VERSION_FILE_PATTERNS.each do |pattern|
    matches = Dir.glob(File.join(root, pattern))
    return matches.first if matches.any?
  end
  nil
end

def read_version(file)
  content = File.read(file)
  if content =~ VERSION_REGEX
    Regexp.last_match(1)
  else
    content.strip
  end
end

def write_version(file, old_version, new_version)
  content = File.read(file)
  new_content = content.gsub(
    /VERSION\s*=\s*["']#{Regexp.escape(old_version)}["']/,
    %(VERSION = "#{new_version}")
  )
  File.write(file, new_content)
end

def bump_version(version, type)
  parts = version.split(".").map(&:to_i)
  parts = [0, 0, 0] if parts.length < 3

  case type
  when "major"
    parts[0] += 1
    parts[1] = 0
    parts[2] = 0
  when "minor"
    parts[1] += 1
    parts[2] = 0
  when "patch" then parts[2] += 1
  end

  parts.join(".")
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
  desc "Bump version (major, minor, or patch)"
  long_desc <<~DESC
    Bump the project version following semantic versioning.

    MAJOR version for incompatible API changes
    MINOR version for backwards-compatible new functionality
    PATCH version for backwards-compatible bug fixes
  DESC

  required_arg :type, desc: "Version component: major, minor, or patch"

  def run
    version_error("Invalid version type '#{type}'. Use: major, minor, or patch") unless %w[major minor patch].include?(type)

    version_error("Not in a project directory") unless cli.project_root

    version_file = find_version_file(cli.project_root)
    version_error("Could not find version file") unless version_file

    old_version = read_version(version_file)
    new_version = bump_version(old_version, type)
    write_version(version_file, old_version, new_version)

    version_output(
      { old_version: old_version, new_version: new_version, type: type, file: version_file }
    )
  end
end

tool "set" do
  desc "Set version to a specific value"

  required_arg :version, desc: "Version string (e.g., 1.0.0)"

  def run
    version_error("Invalid version format '#{version}'. Use semantic versioning: MAJOR.MINOR.PATCH") unless version.match?(/^\d+\.\d+\.\d+/)

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
