# frozen_string_literal: true

require "paint"
require "erb"

module Devex
  # Output helpers for tasks that respect runtime context.
  #
  # Provides styled output methods that automatically adapt to the environment:
  # - Full color and unicode in interactive terminals
  # - Plain text in agent mode, CI, or piped output
  # - JSON-structured output when explicitly requested
  #
  # Usage in tasks:
  #   include Devex::Output
  #   header "Running tests"
  #   success "All tests passed"
  #   error "Build failed"
  #   warn "Deprecated API used"
  #
  # See docs/ref/io-handling.md for design rationale.
  #
  module Output
    # Unicode symbols - basic unicode that works everywhere
    # (Not nerdfont glyphs or emoji that render as images)
    SYMBOLS = {
      success: "✓",
      error: "✗",
      warning: "⚠",
      info: "ℹ",
      arrow: "→",
      bullet: "•",
      check: "✓",
      cross: "✗",
      dot: "·"
    }.freeze

    # Color definitions (truecolor RGB values)
    COLORS = {
      success: [0x5A, 0xF7, 0x8E],      # Green
      error: [0xFF, 0x6B, 0x6B],        # Red
      warning: [0xFF, 0xE6, 0x6D],      # Yellow
      info: [0x6B, 0xC5, 0xFF],         # Blue
      header: [0xC4, 0xB5, 0xFD],       # Purple
      muted: [0x88, 0x88, 0x88],        # Gray
      emphasis: [0xFF, 0xFF, 0xFF]      # White
    }.freeze

    class << self
      # Get symbol - always unicode (basic unicode works everywhere)
      def symbol(name)
        SYMBOLS.fetch(name, name.to_s)
      end

      # Apply color to text if colors are enabled
      def colorize(text, color_name)
        return text unless Context.color?

        rgb = COLORS[color_name]
        return text unless rgb

        Paint[text, rgb]
      end

      # --- Primary output methods ---

      # Print a section header
      def header(text, io: $stderr)
        if Context.agent_mode?
          io.puts "=== #{text} ==="
        else
          styled = colorize(text, :header)
          io.puts
          io.puts styled
          io.puts colorize("─" * text.length, :muted)
        end
      end

      # Print a success message
      def success(text, io: $stderr)
        sym = symbol(:success)
        if Context.color?
          io.puts "#{colorize(sym, :success)} #{text}"
        else
          io.puts "#{sym} #{text}"
        end
      end

      # Print an error message
      def error(text, io: $stderr)
        sym = symbol(:error)
        if Context.color?
          io.puts "#{colorize(sym, :error)} #{colorize(text, :error)}"
        else
          io.puts "#{sym} #{text}"
        end
      end

      # Print a warning message
      def warn(text, io: $stderr)
        sym = symbol(:warning)
        if Context.color?
          io.puts "#{colorize(sym, :warning)} #{text}"
        else
          io.puts "#{sym} #{text}"
        end
      end

      # Print an info message
      def info(text, io: $stderr)
        sym = symbol(:info)
        if Context.color?
          io.puts "#{colorize(sym, :info)} #{text}"
        else
          io.puts "#{sym} #{text}"
        end
      end

      # Print muted/secondary text
      def muted(text, io: $stderr)
        io.puts colorize(text, :muted)
      end

      # Print a bullet point
      def bullet(text, io: $stderr)
        sym = symbol(:bullet)
        io.puts "  #{sym} #{text}"
      end

      # Print an indented line
      def indent(text, level: 1, io: $stdout)
        io.puts "#{" " * (level * 2)}#{text}"
      end

      # --- Structured output ---

      # Output data in the requested format
      # Respects --format flag if provided, defaults to text
      #
      # For composed tools outputting multiple documents:
      # - JSON: outputs as JSONL (one JSON object per line)
      # - YAML: uses --- between documents, ... at the end
      def data(obj, format: nil, io: $stdout)
        format ||= Context.agent_mode? ? :json : :text

        case format.to_sym
        when :json
          require "json"
          io.print JSON.generate(obj), "\n"
        when :yaml
          require "yaml"
          # YAML.dump adds --- automatically, we just ensure clean output
          io.print obj.to_yaml
        else
          io.print obj.to_s, "\n"
        end
      end

      # Start a new YAML document (use between multiple outputs)
      # The first document doesn't need this - YAML.dump adds --- automatically
      def yaml_document_separator(io: $stdout)
        io.print "---\n"
      end

      # End the YAML stream (use after all documents are written)
      def yaml_end_stream(io: $stdout)
        io.print "...\n"
      end

      # Output multiple objects as a YAML stream with proper separators
      def yaml_stream(objects, io: $stdout)
        require "yaml"
        objects.each_with_index do |obj, i|
          yaml_document_separator(io: io) if i > 0
          io.print obj.to_yaml.sub(/\A---\n?/, "") # Remove auto-added ---
        end
        yaml_end_stream(io: io)
      end

      # Output multiple objects as JSONL (JSON Lines)
      def jsonl_stream(objects, io: $stdout)
        require "json"
        objects.each do |obj|
          io.print JSON.generate(obj), "\n"
        end
      end

      # --- Template rendering ---

      # Render an ERB template string with the given binding
      def render_template(template_string, bind = nil)
        erb = ERB.new(template_string, trim_mode: "-")
        erb.result(bind || binding)
      end

      # Render an ERB template file
      def render_template_file(path, bind = nil)
        template = File.read(path)
        render_template(template, bind)
      end

      # --- Progress indicators ---

      # Print a progress indicator (only in interactive mode)
      def progress(current, total, label: nil, io: $stderr)
        return if Context.agent_mode?
        return unless Context.interactive?

        pct = (current.to_f / total * 100).round
        bar_width = 20
        filled = (bar_width * current / total).round
        empty = bar_width - filled

        bar = "█" * filled + "░" * empty
        label_text = label ? "#{label}: " : ""

        # Use carriage return to update in place
        io.print "\r#{label_text}[#{bar}] #{pct}% (#{current}/#{total})"
        io.puts if current >= total
      end

      # Clear the current line (for progress updates)
      def clear_line(io: $stderr)
        return unless Context.interactive?

        io.print "\r\e[K"
      end
    end

    # Instance methods that delegate to class methods
    # These are included when a task does `include Devex::Output`

    def header(text)
      Output.header(text)
    end

    def success(text)
      Output.success(text)
    end

    def error(text)
      Output.error(text)
    end

    def warn(text)
      Output.warn(text)
    end

    def info(text)
      Output.info(text)
    end

    def muted(text)
      Output.muted(text)
    end

    def bullet(text)
      Output.bullet(text)
    end

    def indent(text, level: 1)
      Output.indent(text, level: level)
    end

    def data(obj, format: nil)
      Output.data(obj, format: format)
    end

    def yaml_stream(objects)
      Output.yaml_stream(objects)
    end

    def jsonl_stream(objects)
      Output.jsonl_stream(objects)
    end

    def yaml_document_separator
      Output.yaml_document_separator
    end

    def yaml_end_stream
      Output.yaml_end_stream
    end

    def render_template(template_string, bind = nil)
      Output.render_template(template_string, bind)
    end

    def render_template_file(path, bind = nil)
      Output.render_template_file(path, bind)
    end

    def progress(current, total, label: nil)
      Output.progress(current, total, label: label)
    end

    def clear_line
      Output.clear_line
    end
  end
end
