# frozen_string_literal: true

require "test_helper"
require "devex/support/ansi"

class ANSITest < Minitest::Test
  include EnvHelper

  ANSI = Devex::Support::ANSI

  def setup
    ANSI.mode = 0xFFFFFF # Force truecolor for consistent testing
    ANSI.clear_cache!
  end

  def teardown
    ANSI.mode = nil # Reset to auto-detect
  end

  # ─────────────────────────────────────────────────────────────
  # Mode Control
  # ─────────────────────────────────────────────────────────────

  def test_mode_can_be_set
    ANSI.mode = 256
    assert_equal 256, ANSI.mode
  end

  def test_mode_zero_disables_colors
    ANSI.mode = 0
    refute ANSI.enabled?
    result = ANSI["hello", :bold]
    assert_equal "hello", result
  end

  def test_detect_mode_respects_no_color
    with_env("NO_COLOR" => "1", "FORCE_COLOR" => nil) do
      ANSI.mode = nil
      assert_equal 0, ANSI.detect_mode
    end
  end

  def test_detect_mode_respects_force_color
    with_env("NO_COLOR" => nil, "FORCE_COLOR" => "1") do
      ANSI.mode = nil
      assert_equal 0xFFFFFF, ANSI.detect_mode
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Basic Styling: ANSI["text", :style]
  # ─────────────────────────────────────────────────────────────

  def test_bracket_with_no_styles_returns_text
    assert_equal "hello", ANSI["hello"]
  end

  def test_bracket_with_bold
    result = ANSI["hello", :bold]
    assert_includes result, "\e[1m"
    assert_includes result, "hello"
    assert_includes result, "\e[0m"
  end

  def test_bracket_with_multiple_styles
    result = ANSI["hello", :bold, :underline]
    assert_includes result, "1"  # bold
    assert_includes result, "4"  # underline
  end

  def test_bracket_with_semantic_color
    result = ANSI["hello", :success]
    # Success is RGB [0x5A, 0xF7, 0x8E] = [90, 247, 142]
    assert_includes result, "38;2;90;247;142"
  end

  def test_bracket_with_rgb_array
    result = ANSI["hello", [255, 128, 64]]
    assert_includes result, "38;2;255;128;64"
  end

  def test_bracket_with_hex_color
    result = ANSI["hello", "#FF8040"]
    assert_includes result, "38;2;255;128;64"
  end

  def test_bracket_with_short_hex
    result = ANSI["hello", "#F84"]
    # FF8844
    assert_includes result, "38;2;255;136;68"
  end

  def test_bracket_with_background
    result = ANSI["hello", :bold, bg: :error]
    # Bold should be present
    assert_includes result, "1"
    # Background uses 48 instead of 38
    assert_includes result, "48;2"
  end

  def test_bracket_with_basic_ansi_color
    result = ANSI["hello", :red]
    assert_includes result, "31"  # ANSI red
  end

  def test_bracket_with_bright_color
    result = ANSI["hello", :bright_red]
    assert_includes result, "91"  # Bright red
  end

  # ─────────────────────────────────────────────────────────────
  # Style Aliases
  # ─────────────────────────────────────────────────────────────

  def test_bright_is_alias_for_bold
    bold_result = ANSI["hello", :bold]
    bright_result = ANSI["hello", :bright]
    assert_equal bold_result, bright_result
  end

  def test_faint_is_alias_for_dim
    result = ANSI["hello", :faint]
    assert_includes result, "2"
  end

  def test_inverse_is_alias_for_reverse
    result = ANSI["hello", :inverse]
    assert_includes result, "7"
  end

  # ─────────────────────────────────────────────────────────────
  # Direct Style Methods
  # ─────────────────────────────────────────────────────────────

  def test_bold_method
    result = ANSI.bold("hello")
    assert_includes result, "\e[1m"
  end

  def test_dim_method
    result = ANSI.dim("hello")
    assert_includes result, "\e[2m"
  end

  def test_italic_method
    result = ANSI.italic("hello")
    assert_includes result, "\e[3m"
  end

  def test_underline_method
    result = ANSI.underline("hello")
    assert_includes result, "\e[4m"
  end

  def test_strike_method
    result = ANSI.strike("hello")
    assert_includes result, "\e[9m"
  end

  # ─────────────────────────────────────────────────────────────
  # Color Methods
  # ─────────────────────────────────────────────────────────────

  def test_color_method
    result = ANSI.color("hello", 100, 150, 200)
    assert_includes result, "38;2;100;150;200"
  end

  def test_background_method
    result = ANSI.background("hello", 100, 150, 200)
    assert_includes result, "48;2;100;150;200"
  end

  def test_hex_method
    result = ANSI.hex("hello", "#AABBCC")
    assert_includes result, "38;2;170;187;204"
  end

  def test_named_method
    result = ANSI.named("hello", :warning)
    assert_includes result, "38;2"
  end

  # ─────────────────────────────────────────────────────────────
  # Nested Colors: ANSI % [...]
  # ─────────────────────────────────────────────────────────────

  def test_percent_basic
    result = ANSI % ["hello", :yellow]
    assert_includes result, "hello"
    assert_includes result, "\e[33m"  # yellow
  end

  def test_percent_with_substitution
    result = ANSI % ["Hello %{name}!", :yellow, name: ["World", :blue]]
    assert_includes result, "Hello"
    assert_includes result, "World"
    assert_includes result, "!"
    # Should have blue code for World
    assert_includes result, "\e[34m"  # blue
  end

  def test_percent_nested_resets_to_parent
    result = ANSI % ["Outer %{inner} end", :yellow, inner: ["NESTED", :blue]]

    # The structure should be:
    # \e[33m (yellow) Outer \e[34m (blue) NESTED \e[0m\e[33m (reset+yellow) end \e[0m
    # When inner ends, it should reset back to yellow, not to default

    # Count the yellow codes - should appear twice (once at start, once after inner)
    yellow_count = result.scan(/\e\[33m/).count
    assert_equal 2, yellow_count, "Inner span should reset back to parent (yellow)"
  end

  def test_percent_deeply_nested
    result = ANSI % ["A %{b} Z", :red,
                     b: ["B %{c} Y", :green,
                         c: ["C", :blue]]]

    # All three colors should be present
    assert_includes result, "\e[31m"  # red
    assert_includes result, "\e[32m"  # green
    assert_includes result, "\e[34m"  # blue
  end

  def test_percent_multiple_substitutions
    result = ANSI % ["%{a} and %{b}", :muted,
                     a: ["first", :success],
                     b: ["second", :error]]

    assert_includes result, "first"
    assert_includes result, "second"
    assert_includes result, "and"
  end

  def test_percent_with_plain_text_substitution
    result = ANSI % ["Hello %{name}!", :yellow, name: "World"]
    assert_includes result, "Hello World!"
  end

  # ─────────────────────────────────────────────────────────────
  # Utility Methods
  # ─────────────────────────────────────────────────────────────

  def test_strip_removes_ansi_codes
    colored = ANSI["hello", :bold, :red]
    stripped = ANSI.strip(colored)
    assert_equal "hello", stripped
  end

  def test_visible_length_ignores_ansi
    colored = ANSI["hello", :bold, :red]
    assert_equal 5, ANSI.visible_length(colored)
  end

  def test_esc_returns_raw_escape
    esc = ANSI.esc(:bold, :red)
    assert esc.start_with?("\e[")
    assert esc.end_with?("m")
    refute_includes esc, "\e[0m"  # No reset
  end

  def test_reset_returns_reset_sequence
    assert_equal "\e[0m", ANSI.reset
  end

  # ─────────────────────────────────────────────────────────────
  # Mode Fallback (256 and 16 color)
  # ─────────────────────────────────────────────────────────────

  def test_256_color_mode
    ANSI.mode = 256
    result = ANSI["hello", [100, 150, 200]]
    # Should use 38;5;N format
    assert_match(/38;5;\d+/, result)
  end

  def test_16_color_mode
    ANSI.mode = 16
    result = ANSI["hello", [255, 0, 0]]  # Red
    # Should use basic ANSI code (31 or 91 for red/bright red)
    assert_match(/\e\[\d+m/, result)
    # Should NOT be truecolor format
    refute_includes result, "38;2"
  end

  def test_16_color_mode_with_semantic
    ANSI.mode = 16
    result = ANSI["hello", :success]
    # Should still work, using basic green
    assert_includes result, "hello"
    refute_includes result, "38;2"
  end

  # ─────────────────────────────────────────────────────────────
  # Caching
  # ─────────────────────────────────────────────────────────────

  def test_caching_produces_consistent_results
    result1 = ANSI["hello", :bold, :red]
    result2 = ANSI["hello", :bold, :red]
    assert_equal result1, result2
  end

  def test_clear_cache
    ANSI["hello", :bold]
    ANSI.clear_cache!
    # Should still work after cache clear
    result = ANSI["hello", :bold]
    assert_includes result, "\e[1m"
  end

  def test_mode_change_clears_cache
    ANSI["hello", [100, 150, 200]]
    ANSI.mode = 256
    result = ANSI["hello", [100, 150, 200]]
    # Should now use 256-color format
    assert_match(/38;5;\d+/, result)
  end

  # ─────────────────────────────────────────────────────────────
  # String Refinements
  # ─────────────────────────────────────────────────────────────

  # Helper class that uses the refinement at class scope
  class StringMethodsTester
    using Devex::Support::ANSI::StringMethods

    def self.test_ansi
      "hello".ansi(:bold, :success)
    end

    def self.test_bold
      "hello".bold
    end

    def self.strip_ansi(text)
      text.strip_ansi
    end

    def self.visible_length(text)
      text.visible_length
    end

    def self.test_hex
      "hello".hex("#FF0000")
    end
  end

  def test_string_refinement_ansi
    ANSI.mode = 0xFFFFFF
    result = StringMethodsTester.test_ansi
    # Codes can be combined with ; separator: \e[1;38;2;...m
    assert_includes result, "1"      # bold code
    assert_includes result, "38;2"   # truecolor
    assert_includes result, "hello"
  end

  def test_string_refinement_bold
    ANSI.mode = 0xFFFFFF
    result = StringMethodsTester.test_bold
    assert_includes result, "\e[1m"
  end

  def test_string_refinement_strip_ansi
    colored = ANSI["hello", :bold]
    assert_equal "hello", StringMethodsTester.strip_ansi(colored)
  end

  def test_string_refinement_visible_length
    colored = ANSI["hello", :bold, :red]
    assert_equal 5, StringMethodsTester.visible_length(colored)
  end

  def test_string_refinement_hex
    ANSI.mode = 0xFFFFFF
    result = StringMethodsTester.test_hex
    assert_includes result, "38;2;255;0;0"
  end

  # ─────────────────────────────────────────────────────────────
  # Edge Cases
  # ─────────────────────────────────────────────────────────────

  def test_empty_string
    result = ANSI["", :bold]
    assert_equal "", result
  end

  def test_nil_coerced_to_string
    # nil.to_s is "", which we skip styling for efficiency
    result = ANSI[nil, :bold]
    assert_equal "", result
  end

  def test_number_coerced_to_string
    result = ANSI[42, :bold]
    assert_includes result, "42"
  end

  def test_invalid_symbol_ignored
    result = ANSI["hello", :nonexistent_style]
    # Should still contain text, just without the invalid style
    assert_includes result, "hello"
  end

  def test_invalid_hex_ignored
    result = ANSI["hello", "#GGGGGG"]
    # Invalid hex should be ignored
    assert_includes result, "hello"
  end

  def test_direct_ansi_code_integer
    result = ANSI["hello", 1]  # 1 is bold
    assert_includes result, "\e[1m"
  end
end
