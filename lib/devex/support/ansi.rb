# frozen_string_literal: true

module Devex
  module Support
    # ANSI terminal color and style support with truecolor (24-bit) capability.
    # Zero dependencies - inspired by the paint gem but self-contained.
    #
    # ## Modes
    #
    #   ANSI.mode = 0xFFFFFF  # Truecolor (default)
    #   ANSI.mode = 256       # 256-color palette
    #   ANSI.mode = 16        # 16 ANSI colors
    #   ANSI.mode = 0         # Disabled
    #
    # ## Basic Usage
    #
    #   ANSI["text", :bold, :success]           # Styled text
    #   ANSI["text", [0x5A, 0xF7, 0x8E]]        # RGB foreground
    #   ANSI["text", "#5AF78E"]                 # Hex foreground
    #   ANSI["text", :bold, :success, bg: :error]  # With background
    #
    # ## Nested Colors (relative to parent)
    #
    # When you need nested colored spans that reset back to their parent's
    # color rather than to default, use the `%` method with substitutions:
    #
    #   ANSI % ["Outer %{inner} text", :yellow, inner: ["nested", :blue]]
    #   # => Yellow text, with "nested" in blue, then back to yellow
    #
    # This is essential for building complex colorized output where inner
    # spans shouldn't break the outer context.
    #
    # ## Direct Methods
    #
    #   ANSI.bold("text")
    #   ANSI.color("text", 0x5A, 0xF7, 0x8E)
    #
    # ## String Refinements
    #
    #   using Devex::Support::ANSI::StringMethods
    #   "text".ansi(:bold, :success)
    #   "text".bold
    #
    module ANSI
      # Reset sequence - clears all formatting
      RESET = "\e[0m"

      # Semantic colors (truecolor RGB values)
      # These are the primary colors for CLI output
      COLORS = {
        success:  [0x5A, 0xF7, 0x8E],  # Green
        error:    [0xFF, 0x6B, 0x6B],  # Red
        warning:  [0xFF, 0xE6, 0x6D],  # Yellow
        info:     [0x6B, 0xC5, 0xFF],  # Blue
        header:   [0xC4, 0xB5, 0xFD],  # Purple
        muted:    [0x88, 0x88, 0x88],  # Gray
        emphasis: [0xFF, 0xFF, 0xFF],  # White
      }.freeze

      # Basic ANSI colors (for 16-color mode fallback)
      BASIC_COLORS = {
        black:   30, red:     31, green:   32, yellow:  33,
        blue:    34, magenta: 35, cyan:    36, white:   37,
        default: 39,
        # Bright variants
        bright_black: 90,  bright_red:     91, bright_green: 92,
        bright_yellow: 93, bright_blue:    94, bright_magenta: 95,
        bright_cyan:   96, bright_white:   97,
      }.freeze

      # Style codes
      STYLES = {
        bold:      1,  bright:    1,  # bright is alias for bold
        dim:       2,  faint:     2,
        italic:    3,
        underline: 4,
        blink:     5,
        reverse:   7,  inverse:   7,
        hidden:    8,  conceal:   8,
        strike:    9,  crossed:   9,
      }.freeze

      # Map semantic colors to basic ANSI for 16-color mode
      SEMANTIC_TO_BASIC = {
        success:  :bright_green,
        error:    :bright_red,
        warning:  :bright_yellow,
        info:     :bright_blue,
        header:   :bright_magenta,
        muted:    :white,
        emphasis: :bright_white,
      }.freeze

      class << self
        # Color mode: 0xFFFFFF (truecolor), 256, 16, or 0 (disabled)
        # nil means auto-detect
        def mode=(value)
          @mode = value
          @cache = {} # Clear cache on mode change
        end

        def mode
          return @mode if defined?(@mode) && @mode
          detect_mode
        end

        # Detect appropriate color mode from environment
        def detect_mode
          return 0 if ENV["NO_COLOR"]
          return 0xFFFFFF if ENV["FORCE_COLOR"]

          # Check if Context is available for more sophisticated detection
          if defined?(Devex::Context) && Devex::Context.respond_to?(:color?)
            return 0 unless Devex::Context.color?
          else
            return 0 unless $stdout.tty?
          end

          # Default to truecolor - modern terminals support it
          0xFFFFFF
        end

        # Check if colors are enabled
        def enabled?
          mode > 0
        end

        # ─────────────────────────────────────────────────────────────
        # Main API: ANSI["text", :bold, :success]
        # ─────────────────────────────────────────────────────────────

        # Primary interface - apply styles and colors to text.
        # Text is FIRST argument, followed by styles/colors (matches Paint API).
        # Uses caching for compiled escape sequences.
        #
        # @example
        #   ANSI["hello", :bold]
        #   ANSI["hello", :success]
        #   ANSI["hello", :bold, :success]
        #   ANSI["hello", [0x5A, 0xF7, 0x8E]]
        #   ANSI["hello", "#5AF78E"]
        #   ANSI["hello", :bold, bg: :error]
        #
        def [](*args, bg: nil)
          return "" if args.empty?

          text = args.shift.to_s
          return text unless enabled?
          return text if args.empty? && bg.nil?
          return text if text.empty?  # Don't wrap empty strings

          # Build cache key from options (include bg in key for caching, pass separately for processing)
          cache_key = bg ? [args, bg].freeze : args.freeze
          prefix = cached_prefix(args, bg, cache_key)

          return text if prefix.empty?
          "#{prefix}#{text}#{RESET}"
        end

        # ─────────────────────────────────────────────────────────────
        # Nested Colors: ANSI % ["text %{key}", :style, key: [...]]
        # ─────────────────────────────────────────────────────────────

        # Apply colors with nested substitutions that reset to parent context.
        #
        # The key feature: when a nested span ends, it resets back to the
        # parent's colors, not to default. This allows building complex
        # colorized strings without breaking the outer context.
        #
        # @param paint_args [Array] [text, *styles, substitutions_hash]
        # @param clear_color [String] ANSI sequence to reset to (internal use)
        #
        # @example Simple nested color
        #   ANSI % ["Hello %{name}!", :yellow, name: ["World", :blue]]
        #   # => Yellow "Hello ", blue "World", yellow "!"
        #
        # @example Multiple substitutions
        #   ANSI % ["%{status}: %{msg}", :muted,
        #           status: ["OK", :success],
        #           msg: ["All tests passed", :emphasis]]
        #
        # @example Deeply nested
        #   ANSI % ["Outer %{mid} end", :yellow,
        #           mid: ["middle %{inner} more", :blue,
        #                 inner: ["deep", :red]]]
        #
        def %(paint_args, clear_color = RESET)
          args = paint_args.dup
          text = args.shift.to_s

          # Extract substitution hash if present
          substitutions = args.last.is_a?(Hash) ? args.pop : nil

          # Get the color sequence for this level
          cache_key = args.freeze
          current_color = cached_prefix(args, nil, cache_key)

          # Process substitutions recursively
          if substitutions
            substitutions.each do |key, value|
              placeholder = "%{#{key}}"
              replacement = if value.is_a?(Array)
                              # Recursive call - nested span resets to current_color, not RESET
                              self.%(value, clear_color + current_color)
                            else
                              value.to_s
                            end
              text = text.gsub(placeholder, replacement)
            end
          end

          return text unless enabled?

          if current_color.empty?
            text
          else
            "#{current_color}#{text}#{clear_color}"
          end
        end

        # ─────────────────────────────────────────────────────────────
        # Direct Color Methods
        # ─────────────────────────────────────────────────────────────

        # Truecolor (24-bit) foreground
        def color(text, r, g, b)
          self[text, [r, g, b]]
        end

        # Truecolor (24-bit) background
        def background(text, r, g, b)
          self[text, bg: [r, g, b]]
        end

        # Hex color foreground: ANSI.hex("text", "#5AF78E")
        def hex(text, hex_color)
          self[text, hex_color]
        end

        # Named semantic color
        def named(text, name)
          self[text, name]
        end

        # ─────────────────────────────────────────────────────────────
        # Style Methods
        # ─────────────────────────────────────────────────────────────

        def bold(text)      = self[text, :bold]
        def dim(text)       = self[text, :dim]
        def italic(text)    = self[text, :italic]
        def underline(text) = self[text, :underline]
        def blink(text)     = self[text, :blink]
        def reverse(text)   = self[text, :reverse]
        def hidden(text)    = self[text, :hidden]
        def strike(text)    = self[text, :strike]

        # ─────────────────────────────────────────────────────────────
        # Utility Methods
        # ─────────────────────────────────────────────────────────────

        # Strip ANSI codes from text
        def strip(text)
          text.to_s.gsub(/\e\[[0-9;]*m/, "")
        end

        # Calculate visible length (without ANSI codes)
        def visible_length(text)
          strip(text).length
        end

        # Raw escape sequence without text wrapping.
        # Useful for building custom sequences or streaming output.
        def esc(*args)
          cached_prefix(args, nil, args.freeze)
        end

        # Reset sequence
        def reset
          RESET
        end

        # Clear the escape sequence cache
        def clear_cache!
          @cache = {}
        end

        private

        # Get or compute cached escape sequence prefix
        # @param fg_args [Array] foreground styles/colors
        # @param bg [Symbol, Array, String, nil] background color
        # @param cache_key [Object] key for caching (includes both fg and bg)
        def cached_prefix(fg_args, bg, cache_key)
          @cache ||= {}

          @cache[cache_key] ||= begin
            codes = []

            # Process foreground styles and colors
            fg_args.each do |arg|
              code = resolve_code(arg, foreground: true)
              codes << code if code
            end

            # Process background
            if bg
              code = resolve_code(bg, foreground: false)
              codes << code if code
            end

            codes.empty? ? "" : "\e[#{codes.join(";")}m"
          end
        end

        # Resolve an argument to ANSI code(s)
        def resolve_code(arg, foreground:)
          case arg
          when Symbol
            resolve_symbol(arg, foreground)
          when Array
            # RGB array
            rgb_code(*arg, foreground: foreground)
          when String
            # Hex string like "#5AF78E" or "5AF78E"
            resolve_hex(arg, foreground)
          when Integer
            # Direct ANSI code
            arg
          end
        end

        def resolve_symbol(sym, foreground)
          # Check styles first
          if STYLES.key?(sym)
            STYLES[sym]
          # Then semantic colors
          elsif COLORS.key?(sym)
            rgb = COLORS[sym]
            rgb_code(*rgb, foreground: foreground)
          # Then basic ANSI colors
          elsif BASIC_COLORS.key?(sym)
            code = BASIC_COLORS[sym]
            foreground ? code : code + 10
          end
        end

        def resolve_hex(hex_str, foreground)
          hex_str = hex_str.delete_prefix("#")

          # Expand 3-char hex: "FFF" -> "FFFFFF"
          if hex_str.length == 3
            hex_str = hex_str.chars.map { |c| c * 2 }.join
          end

          return nil unless hex_str.length == 6

          r = hex_str[0, 2].to_i(16)
          g = hex_str[2, 2].to_i(16)
          b = hex_str[4, 2].to_i(16)

          rgb_code(r, g, b, foreground: foreground)
        end

        def rgb_code(r, g, b, foreground:)
          case mode
          when 0xFFFFFF, (257..)
            # Truecolor
            foreground ? "38;2;#{r};#{g};#{b}" : "48;2;#{r};#{g};#{b}"
          when 256
            # 256-color: convert RGB to nearest color cube index
            index = rgb_to_256(r, g, b)
            foreground ? "38;5;#{index}" : "48;5;#{index}"
          when 16
            # 16-color: find nearest basic color
            basic = rgb_to_basic(r, g, b)
            foreground ? basic : basic + 10
          else
            nil
          end
        end

        # Convert RGB to 256-color palette index
        def rgb_to_256(r, g, b)
          # Check if it's a grayscale
          if r == g && g == b
            return 16 if r < 8
            return 231 if r > 248
            return ((r - 8) / 10.0).round + 232
          end

          # Color cube: 6x6x6 starting at index 16
          16 + (36 * (r / 51.0).round) + (6 * (g / 51.0).round) + (b / 51.0).round
        end

        # Convert RGB to nearest basic ANSI color code
        def rgb_to_basic(r, g, b)
          # Simple brightness-based mapping
          bright = (r + g + b) > 382
          base = 30

          # Determine primary color
          if r > g && r > b
            base += 1  # red
          elsif g > r && g > b
            base += 2  # green
          elsif b > r && b > g
            base += 4  # blue
          elsif r > b
            base += 3  # yellow (r+g)
          elsif g > r
            base += 6  # cyan (g+b)
          elsif r > g
            base += 5  # magenta (r+b)
          else
            base += 7  # white/gray
          end

          bright ? base + 60 : base
        end
      end

      # String refinements for ANSI colors
      module StringMethods
        refine String do
          # Primary interface: "text".ansi(:bold, :success)
          def ansi(*styles, bg: nil)
            ANSI[self, *styles, bg: bg]
          end

          # RGB colors
          def color(r, g, b)
            ANSI.color(self, r, g, b)
          end

          def background(r, g, b)
            ANSI.background(self, r, g, b)
          end

          # Hex color: "text".hex("#5AF78E")
          def hex(hex_color)
            ANSI.hex(self, hex_color)
          end

          # Named semantic color: "text".named(:success)
          def named(name)
            ANSI.named(self, name)
          end

          # Style shortcuts
          def bold      = ANSI.bold(self)
          def dim       = ANSI.dim(self)
          def italic    = ANSI.italic(self)
          def underline = ANSI.underline(self)
          def blink     = ANSI.blink(self)
          def reverse   = ANSI.reverse(self)
          def hidden    = ANSI.hidden(self)
          def strike    = ANSI.strike(self)

          # Strip ANSI codes
          def strip_ansi
            ANSI.strip(self)
          end

          # Visible length without ANSI codes
          def visible_length
            ANSI.visible_length(self)
          end
        end
      end
    end
  end
end
