# frozen_string_literal: true

# Uses prj.gemspec - fails fast with helpful message if not found.

desc "Gem packaging tasks"

long_desc <<~DESC
  Build and manage gem packages.

  Subcommands:
    dx gem build    - Build the gem (.gem file)
    dx gem install  - Build and install locally
    dx gem clean    - Remove built gem files
DESC

tool "build" do
  desc "Build the gem"

  def run
    cmd("gem", "build", prj.gemspec.basename, chdir: prj.root).exit_on_failure!
  end

  def prj = @prj ||= Devex::ProjectPaths.new
end

tool "install" do
  desc "Build and install gem locally"

  def run
    $stdout.puts "Building gem..."
    cmd("gem", "build", prj.gemspec.basename, chdir: prj.root)
      .then { install_built_gem }
      .exit_on_failure!
  end

  def install_built_gem
    gem_file = prj.root.glob("*.gem").max_by(&:mtime)
    unless gem_file
      $stderr.puts "Build succeeded but no .gem file found"
      exit 1
    end

    $stdout.puts "Installing #{gem_file.basename}..."
    result = cmd("gem", "install", gem_file.basename, "--local", chdir: prj.root)

    if result.success?
      gem_file.rm
      $stdout.puts "Installed and cleaned up."
    end

    result
  end

  def prj = @prj ||= Devex::ProjectPaths.new
end

tool "clean" do
  desc "Remove built gem files"

  def run
    gem_files = prj.root.glob("*.gem")
    if gem_files.empty?
      $stdout.puts "No .gem files to clean"
    else
      gem_files.each do |f|
        f.rm
        $stdout.puts "Removed #{f.basename}"
      end
    end
  end

  def prj = @prj ||= Devex::ProjectPaths.new
end

def run
  cli.show_help(tool)
end
