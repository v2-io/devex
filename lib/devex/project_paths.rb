# frozen_string_literal: true

require_relative "support/path"
require_relative "dirs"

module Devex
  # Project path resolution with lazy discovery and fail-fast feedback.
  #
  # Access conventional project locations via the `prj` object:
  #
  #   prj.root        # Project root directory
  #   prj.lib         # lib/
  #   prj.test        # test/ or spec/ (discovered)
  #   prj.config      # .dx.yml or .dx/config.yml
  #   prj["**/*.rb"]  # Glob from project root
  #
  # Paths are resolved lazily on first access. If a conventional path
  # doesn't exist, you get a clear error with remediation steps.
  #
  # See ADR-003 for full specification.
  #
  class ProjectPaths
    Path = Support::Path

    # Conventional path mappings
    # Values can be:
    #   - String: exact path relative to root
    #   - Array: list of alternatives (first existing wins)
    #   - Symbol: special handler method
    #   - String with *: glob pattern
    CONVENTIONS = {
      root:           nil,                # Always project_dir
      git:            ".git",
      dx:             ".dx",
      config:         :detect_config,
      tools:          :detect_tools,
      lib:            "lib",
      src:            "src",
      bin:            "bin",
      exe:            "exe",
      test:           %w[test spec tests],
      features:       "features",
      property_tests: "property_tests",
      simulations:    "simulations",
      spec_tests:     "specification_tests",
      types:          "sig",
      docs:           %w[docs doc documentation],
      system_docs:    "system_docs",
      version:        :detect_version,
      gemfile:        "Gemfile",
      gemspec:        "*.gemspec",
      mise:           %w[.mise.toml .tool-versions],
      env:            ".env",
      tmp:            "tmp",
      log:            "log",
      vendor:         "vendor",
      db:             "db",
      config_dir:     "config",
      scripts:        "scripts",
    }.freeze

    def initialize(root: nil, overrides: {})
      @root = root ? Path[root] : Dirs.project_dir
      @overrides = overrides.transform_keys(&:to_sym)
      @cache = {}
    end

    # Project root directory
    def root
      @root
    end

    # Glob from project root
    def [](pattern, **opts)
      @root[pattern, **opts]
    end

    # Is this project in organized mode? (.dx/ directory exists)
    def organized_mode?
      @organized ||= (@root / ".dx").directory?
    end

    # Dynamic path resolution
    def method_missing(name, *args, &block)
      return super unless CONVENTIONS.key?(name) || @overrides.key?(name)
      @cache[name] ||= resolve(name)
    end

    def respond_to_missing?(name, include_private = false)
      CONVENTIONS.key?(name) || @overrides.key?(name) || super
    end

    private

    def resolve(name)
      # Check overrides first
      if @overrides.key?(name)
        path = @root / @overrides[name]
        return path if path.exist?
        return fail_missing!(name, [@overrides[name]])
      end

      # Special handlers
      convention = CONVENTIONS[name]
      case convention
      when nil
        @root  # root returns the root
      when Symbol
        send(convention)
      when Array
        found = convention.map { |p| @root / p }.find(&:exist?)
        found || fail_missing!(name, convention)
      when String
        if convention.include?("*")
          # Glob pattern
          matches = @root.glob(convention)
          matches.first || fail_missing!(name, [convention])
        else
          path = @root / convention
          path.exist? ? path : fail_missing!(name, [convention])
        end
      else
        fail_missing!(name, [convention.to_s])
      end
    end

    # ─────────────────────────────────────────────────────────────
    # Special Detection Methods
    # ─────────────────────────────────────────────────────────────

    def detect_config
      dx_dir = @root / ".dx"
      dx_yml = @root / ".dx.yml"

      if dx_dir.exist? && dx_yml.exist?
        fail_config_conflict!(dx_dir, dx_yml)
      elsif dx_dir.exist?
        dx_dir / "config.yml"
      else
        dx_yml  # May or may not exist
      end
    end

    def detect_tools
      if organized_mode?
        @root / ".dx" / "tools"
      else
        @root / "tools"
      end
    end

    def detect_version
      # Check common version file locations
      candidates = [
        @root / "VERSION",
        @root / "version",
      ]

      # Also check lib/*/version.rb patterns
      version_rbs = @root.glob("lib/*/version.rb")
      candidates.concat(version_rbs)

      found = candidates.find(&:exist?)
      found || fail_missing!(:version, ["VERSION", "lib/*/version.rb"])
    end

    # ─────────────────────────────────────────────────────────────
    # Fail-Fast with Feedback
    # ─────────────────────────────────────────────────────────────

    def fail_missing!(name, tried)
      message = <<~ERR
        ERROR: Project #{name} directory not found

          Looked for: #{tried.join(", ")}
          Project root: #{@root}

          To configure a custom location, add to .dx.yml:
            paths:
              #{name}: your/#{name}/dir/

        Exit code: 78 (EX_CONFIG)
      ERR

      if Devex.respond_to?(:fail!)
        Devex.fail!(message, exit_code: 78)
      else
        raise message
      end
    end

    def fail_config_conflict!(dx_dir, dx_yml)
      dx_dir_time = dx_dir.mtime rescue Time.now
      dx_yml_time = dx_yml.mtime rescue Time.now

      message = <<~ERR
        ERROR: Conflicting dx configuration

          Found both:
            .dx.yml      (modified: #{dx_yml_time.strftime('%Y-%m-%d %H:%M:%S')})
            .dx/         (modified: #{dx_dir_time.strftime('%Y-%m-%d %H:%M:%S')})

          Please use one or the other:
            - Simple:    .dx.yml + tools/
            - Organized: .dx/config.yml + .dx/tools/

          To migrate from simple to organized:
            mkdir -p .dx
            mv .dx.yml .dx/config.yml
            mv tools/ .dx/tools/

        Exit code: 78 (EX_CONFIG)
      ERR

      if Devex.respond_to?(:fail!)
        Devex.fail!(message, exit_code: 78)
      else
        raise message
      end
    end
  end
end
