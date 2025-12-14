# frozen_string_literal: true

require_relative "support/ansi"

module Devex
  # Helper methods available in ERB templates.
  # Automatically respects Context.color? for all styling.
  #
  # Usage in templates:
  #   <%= c :green, "success" %>
  #   <%= c :bold, :white, "header" %>
  #   <%= sym :success %> All tests passed
  #   <%= hr %>
  #   <%= heading "Section" %>
  #
  module TemplateHelpers
    # Color definitions (truecolor RGB) - matches Output::COLORS
    COLORS = {
      success:  [0x5A, 0xF7, 0x8E],
      error:    [0xFF, 0x6B, 0x6B],
      warning:  [0xFF, 0xE6, 0x6D],
      info:     [0x6B, 0xC5, 0xFF],
      header:   [0xC4, 0xB5, 0xFD],
      muted:    [0x88, 0x88, 0x88],
      emphasis: [0xFF, 0xFF, 0xFF]
    }.freeze

    # Symbols - basic unicode that works everywhere
    # (Not nerdfont glyphs or emoji that render as images)
    SYMBOLS = {
      success: "✓",
      error:   "✗",
      warning: "⚠",
      info:    "ℹ",
      arrow:   "→",
      bullet:  "•",
      check:   "✓",
      cross:   "✗",
      dot:     "·"
    }.freeze

    module_function

    # Colorize text - the main helper
    # Last argument is the text, preceding arguments are colors/styles
    #
    # Examples:
    #   c(:green, "text")
    #   c(:bold, :white, "text")
    #   c(:success, "text")      # uses named color
    #   c([0x5A, 0xF7, 0x8E], "text")  # RGB array
    #
    def c(*args)
      text = args.pop.to_s
      return text unless Context.color?
      return text if args.empty?

      # Expand named colors to RGB
      colors = args.map do |color|
        if color.is_a?(Symbol) && COLORS.key?(color)
          COLORS[color]
        else
          color
        end
      end

      Support::ANSI[text, *colors]
    end

    # Get symbol - always unicode (basic unicode works everywhere)
    def sym(name) = SYMBOLS.fetch(name, name.to_s)

    # Colored symbol - combines sym() and c()
    def csym(name, color = nil)
      color ||= name # Default: use symbol name as color name
      s     = sym(name)
      c(color, s)
    end

    # Horizontal rule
    def hr(char: "─", width: 40)
      line = char * width
      Context.color? ? c(:muted, line) : line
    end

    # Styled heading
    def heading(text, char: "=", width: nil)
      width ||= text.length
      line  = char * width
      if Context.color?
        "#{c(:header, text)}\n#{c(:muted, line)}"
      else
        "#{text}\n#{line}"
      end
    end

    # Muted/secondary text
    def muted(text) = c(:muted, text)

    # Bold text
    def bold(text) = c(:bold, text)

    # Create a binding with all helpers and locals available
    def template_binding(locals = {}) = TemplateContext.new(locals).get_binding
  end

  # Context object for template rendering
  # Includes all helper methods directly so templates can use clean syntax:
  #   <%= c :green, "text" %>
  #   <%= heading "Title" %>
  #
  class TemplateContext
    include TemplateHelpers

    def initialize(locals = {})
      @locals = locals
      # Define accessor methods for each local variable
      locals.each do |name, value|
        define_singleton_method(name) { value }
      end
    end

    def get_binding = binding

    # Allow accessing locals as methods or via method_missing
    def method_missing(name, *args, &)
      if @locals.key?(name)
        @locals[name]
      else
        super
      end
    end

    def respond_to_missing?(name, include_private = false) = @locals.key?(name) || super
  end
end
