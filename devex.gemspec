# frozen_string_literal: true

require_relative "lib/devex/version"

Gem::Specification.new do |spec|
  spec.name = "devex"
  spec.version = Devex::VERSION
  spec.authors = ["Joseph A Wecker"]
  spec.email = ["joseph@v2.io"]

  spec.summary = "Lightweight Ruby CLI framework with unified dx command for development tasks"
  spec.description = <<~DESC
    Devex provides a unified `dx` command for common development tasks. Features include:
    - CLI framework with automatic help generation and nested subcommands
    - Agent-aware output (detects AI agents and adapts output format)
    - Environment orchestration (mise, bundle exec, dotenv integration)
    - Project path conventions with fail-fast feedback
    - Zero-dependency support library (Path class, ANSI colors, core extensions)
  DESC
  spec.homepage = "https://github.com/v2-io/devex"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/v2-io/devex"
  spec.metadata["changelog_uri"] = "https://github.com/v2-io/devex/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .archive/ docs/dev/ appveyor Gemfile]) ||
        (f.end_with?(".md") && !f.include?("/") && f != "README.md")
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  # Note: tty-prompt will be removed when we implement our own prompts
  spec.add_dependency "tty-prompt", "~> 0.23"
end
