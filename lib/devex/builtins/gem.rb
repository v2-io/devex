# frozen_string_literal: true

desc "Gem packaging tasks"

long_desc <<~DESC
  Build and manage gem packages.

  Subcommands:
    dx gem build    - Build the gem (.gem file)
    dx gem install  - Build and install locally
    dx gem clean    - Remove built gem files
DESC

include Devex::Exec

tool "build" do
  desc "Build the gem"
  include Devex::Exec

  def run
    gemspec = find_gemspec
    unless gemspec
      $stderr.puts "No .gemspec file found"
      exit 1
    end

    cmd("gem", "build", gemspec).exit_on_failure!
  end

  def find_gemspec
    Dir.glob("*.gemspec").first
  end
end

tool "install" do
  desc "Build and install gem locally"
  include Devex::Exec

  def run
    gemspec = find_gemspec
    unless gemspec
      $stderr.puts "No .gemspec file found"
      exit 1
    end

    # Chain build -> find gem -> install using .then { }
    $stdout.puts "Building gem..."
    cmd("gem", "build", gemspec)
      .then { install_built_gem }
      .exit_on_failure!
  end

  def install_built_gem
    gem_file = Dir.glob("*.gem").max_by { |f| File.mtime(f) }
    unless gem_file
      $stderr.puts "Build succeeded but no .gem file found"
      exit 1
    end

    $stdout.puts "Installing #{gem_file}..."
    result = cmd("gem", "install", gem_file, "--local")

    # Clean up on success
    if result.success?
      File.delete(gem_file)
      $stdout.puts "Installed and cleaned up."
    end

    result
  end

  def find_gemspec
    Dir.glob("*.gemspec").first
  end
end

tool "clean" do
  desc "Remove built gem files"

  def run
    gem_files = Dir.glob("*.gem")
    if gem_files.empty?
      $stdout.puts "No .gem files to clean"
    else
      gem_files.each do |f|
        File.delete(f)
        $stdout.puts "Removed #{f}"
      end
    end
  end
end

def run
  # Show help if no subcommand given
  cli.show_help(tool)
end
