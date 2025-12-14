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
  #   prj.config      # config file path
  #   prj["**/*.rb"]  # Glob from project root
  #
  # Paths are resolved lazily on first access. If a conventional path
  # doesn't exist, you get a clear error with remediation steps.
  #
  # @example Core usage with custom config
  #   config = Devex::Core::Configuration.new(
  #     organized_dir: ".mycli",
  #     config_file: ".mycli.yml"
  #   )
  #   prj = Devex::ProjectPaths.new(root: project_root, config: config)
  #
  class ProjectPaths
    Path = Support::Path

    # Default conventional path mappings
    # Values can be:
    #   - String: exact path relative to root
    #   - Array: list of alternatives (first existing wins)
    #   - Symbol: special handler method
    #   - String with *: glob pattern
    #   - nil: returns root
    DEFAULT_CONVENTIONS = {
      root:           nil,                # Always project_dir
      git:            ".git",
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
      linter:         %w[.standard.yml .rubocop.yml],
      mise:           %w[.mise.toml .tool-versions],
      env:            ".env",
      tmp:            "tmp",
      log:            "log",
      vendor:         "vendor",
      db:             "db",
      config_dir:     "config",
      scripts:        "scripts"
    }.freeze

    # dx-specific conventions (added when no config provided)
    DX_CONVENTIONS = {
      dx:             ".dx",
      config:         :detect_config,
      tools:          :detect_tools,
      templates:      :detect_templates,
      hooks:          :detect_hooks
    }.freeze

    # @param root [String, Path, nil] project root (defaults to Dirs.project_dir)
    # @param config [Core::Configuration, nil] configuration for customization
    # @param overrides [Hash] explicit path overrides
    def initialize(root: nil, config: nil, overrides: {})
      @root      = root ? Path[root] : Dirs.project_dir
      @config    = config
      @overrides = overrides.transform_keys(&:to_sym)
      @cache     = {}
    end

    # Project root directory
    attr_reader :root

    # Framework configuration (if any)
    # Note: Named `configuration` to avoid shadowing the `config` path accessor
    def configuration
      @config
    end

    # Glob from project root
    def [](pattern, **) = @root[pattern, **]

    # Is this project in organized mode? (organized_dir exists)
    def organized_mode?
      @organized ||= begin
        org_dir = organized_dir_name
        org_dir && (@root / org_dir).directory?
      end
    end

    # Dynamic path resolution
    def method_missing(name, *args, &)
      return super unless conventions.key?(name) || @overrides.key?(name)

      @cache[name] ||= resolve(name)
    end

    def respond_to_missing?(name, include_private = false)
      conventions.key?(name) || @overrides.key?(name) || super
    end

    private

    # Merged conventions (config overrides + defaults)
    def conventions
      @conventions ||= begin
        base = DEFAULT_CONVENTIONS.dup

        # Add dx-specific conventions unless config specifies otherwise
        if @config
          # Add organized_dir convention if configured
          base[:organized_dir] = @config.organized_dir if @config.organized_dir
          # Add config/tools/templates/hooks with detection
          base[:config] = :detect_config if @config.config_file || @config.organized_dir
          base[:tools] = :detect_tools
          base[:templates] = :detect_templates
          base[:hooks] = :detect_hooks
          # Merge custom conventions from config
          base.merge!(@config.path_conventions) if @config.path_conventions
        else
          # No config = dx mode for backward compatibility
          base.merge!(DX_CONVENTIONS)
        end

        base
      end
    end

    # Name of organized mode directory (e.g., ".dx", ".mycli")
    def organized_dir_name
      @config&.organized_dir || ".dx"
    end

    # Name of simple mode config file (e.g., ".dx.yml", ".mycli.yml")
    def config_file_name
      @config&.config_file || ".dx.yml"
    end

    def resolve(name)
      # Check overrides first
      if @overrides.key?(name)
        path = @root / @overrides[name]
        return path if path.exist?

        return fail_missing!(name, [@overrides[name]])
      end

      # Special handlers
      convention = conventions[name]
      case convention
      when nil    then @root  # root returns the root
      when Symbol then send(convention)
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
      org_dir_name = organized_dir_name
      cfg_file_name = config_file_name

      org_dir = org_dir_name ? (@root / org_dir_name) : nil
      cfg_file = cfg_file_name ? (@root / cfg_file_name) : nil

      # Check for conflict (both exist)
      if org_dir&.exist? && cfg_file&.exist?
        fail_config_conflict!(org_dir, cfg_file)
      elsif org_dir&.exist?
        org_dir / "config.yml"
      elsif cfg_file
        cfg_file  # May or may not exist
      else
        @root / "config.yml"  # Fallback
      end
    end

    def detect_tools
      if organized_mode?
        @root / organized_dir_name / "tools"
      else
        @root / (@config&.tools_dir || "tools")
      end
    end

    def detect_templates
      if organized_mode?
        @root / organized_dir_name / "templates"
      else
        @root / "templates"
      end
    end

    def detect_hooks
      if organized_mode?
        @root / organized_dir_name / "hooks"
      else
        @root / "hooks"
      end
    end

    def detect_version
      # Check common version file locations
      candidates = [
        @root / "VERSION",
        @root / "version"
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
      cfg_file = config_file_name || "config file"

      message = <<~ERR
        ERROR: Project #{name} directory not found

          Looked for: #{tried.join(', ')}
          Project root: #{@root}

          To configure a custom location, add to #{cfg_file}:
            paths:
              #{name}: your/#{name}/dir/

        Exit code: 78 (EX_CONFIG)
      ERR

      raise message
    end

    def fail_config_conflict!(org_dir, cfg_file)
      org_dir_time = begin
        org_dir.mtime
      rescue StandardError
        Time.now
      end
      cfg_file_time = begin
        cfg_file.mtime
      rescue StandardError
        Time.now
      end

      org_name = organized_dir_name
      cfg_name = config_file_name

      message = <<~ERR
        ERROR: Conflicting configuration

          Found both:
            #{cfg_name}      (modified: #{cfg_file_time.strftime('%Y-%m-%d %H:%M:%S')})
            #{org_name}/         (modified: #{org_dir_time.strftime('%Y-%m-%d %H:%M:%S')})

          Please use one or the other:
            - Simple:    #{cfg_name} + tools/
            - Organized: #{org_name}/config.yml + #{org_name}/tools/

          To migrate from simple to organized:
            mkdir -p #{org_name}
            mv #{cfg_name} #{org_name}/config.yml
            mv tools/ #{org_name}/tools/

        Exit code: 78 (EX_CONFIG)
      ERR

      raise message
    end
  end

  # Backward compatibility: CONVENTIONS constant
  ProjectPaths::CONVENTIONS = ProjectPaths::DEFAULT_CONVENTIONS.merge(ProjectPaths::DX_CONVENTIONS).freeze
end
