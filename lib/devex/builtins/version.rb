# frozen_string_literal: true

desc "Show or manage version"

def run
  # Show version of the project if we can find it, otherwise show devex version
  if cli.project_root
    version_file = find_version_file(cli.project_root)
    if version_file
      puts read_version(version_file)
      return
    end
  end

  # Fall back to devex version
  puts "devex #{Devex::VERSION}"
end

def find_version_file(root)
  # Common locations for version files
  candidates = [
    File.join(root, "lib", "*", "version.rb"),
    File.join(root, "VERSION"),
    File.join(root, "version.rb")
  ]

  candidates.each do |pattern|
    matches = Dir.glob(pattern)
    return matches.first if matches.any?
  end

  nil
end

def read_version(file)
  content = File.read(file)

  # Try to extract VERSION constant
  if content =~ /VERSION\s*=\s*["']([^"']+)["']/
    return $1
  end

  # Plain version file
  content.strip
end

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
    unless %w[major minor patch].include?(type)
      $stderr.puts "Error: Invalid version type '#{type}'"
      $stderr.puts "Use: major, minor, or patch"
      exit(1)
    end

    unless cli.project_root
      $stderr.puts "Error: Not in a project directory"
      exit(1)
    end

    version_file = find_version_file(cli.project_root)
    unless version_file
      $stderr.puts "Error: Could not find version file"
      exit(1)
    end

    old_version = read_version(version_file)
    new_version = bump_version(old_version, type)
    write_version(version_file, old_version, new_version)

    puts "#{old_version} -> #{new_version}"
  end

  def find_version_file(root)
    candidates = [
      File.join(root, "lib", "*", "version.rb"),
      File.join(root, "VERSION"),
      File.join(root, "version.rb")
    ]

    candidates.each do |pattern|
      matches = Dir.glob(pattern)
      return matches.first if matches.any?
    end

    nil
  end

  def read_version(file)
    content = File.read(file)
    if content =~ /VERSION\s*=\s*["']([^"']+)["']/
      return $1
    end
    content.strip
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
    when "patch"
      parts[2] += 1
    end

    parts.join(".")
  end

  def write_version(file, old_version, new_version)
    content = File.read(file)
    new_content = content.gsub(
      /VERSION\s*=\s*["']#{Regexp.escape(old_version)}["']/,
      %(VERSION = "#{new_version}")
    )
    File.write(file, new_content)
  end
end

tool "set" do
  desc "Set version to a specific value"

  required_arg :version, desc: "Version string (e.g., 1.0.0)"

  def run
    unless version.match?(/^\d+\.\d+\.\d+/)
      $stderr.puts "Error: Invalid version format '#{version}'"
      $stderr.puts "Use semantic versioning: MAJOR.MINOR.PATCH"
      exit(1)
    end

    unless cli.project_root
      $stderr.puts "Error: Not in a project directory"
      exit(1)
    end

    version_file = find_version_file(cli.project_root)
    unless version_file
      $stderr.puts "Error: Could not find version file"
      exit(1)
    end

    old_version = read_version(version_file)
    write_version(version_file, old_version, version)

    puts "#{old_version} -> #{version}"
  end

  def find_version_file(root)
    candidates = [
      File.join(root, "lib", "*", "version.rb"),
      File.join(root, "VERSION"),
      File.join(root, "version.rb")
    ]

    candidates.each do |pattern|
      matches = Dir.glob(pattern)
      return matches.first if matches.any?
    end

    nil
  end

  def read_version(file)
    content = File.read(file)
    if content =~ /VERSION\s*=\s*["']([^"']+)["']/
      return $1
    end
    content.strip
  end

  def write_version(file, old_version, new_version)
    content = File.read(file)
    new_content = content.gsub(
      /VERSION\s*=\s*["']#{Regexp.escape(old_version)}["']/,
      %(VERSION = "#{new_version}")
    )
    File.write(file, new_content)
  end
end
