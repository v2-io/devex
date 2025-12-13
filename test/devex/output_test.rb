# frozen_string_literal: true

require "test_helper"
require "stringio"

class OutputTest < Minitest::Test
  include EnvHelper

  def setup
    clear_dx_env
    Devex::Context.reset_env!
    @output = StringIO.new
  end

  # --- Symbol selection ---
  # Symbols are always unicode (basic unicode works everywhere)

  def test_symbol_returns_unicode
    assert_equal "✓", Devex::Output.symbol(:success)
    assert_equal "✗", Devex::Output.symbol(:error)
    assert_equal "⚠", Devex::Output.symbol(:warning)
    assert_equal "ℹ", Devex::Output.symbol(:info)
  end

  def test_symbol_returns_unicode_even_in_agent_mode
    with_env("DX_AGENT_MODE" => "1") do
      assert_equal "✓", Devex::Output.symbol(:success)
      assert_equal "✗", Devex::Output.symbol(:error)
    end
  end

  # --- Output methods ---

  def test_header_in_agent_mode
    with_env("DX_AGENT_MODE" => "1") do
      Devex::Output.header("Test Section", io: @output)
      assert_includes @output.string, "=== Test Section ==="
    end
  end

  def test_success_outputs_message
    Devex::Output.success("All tests passed", io: @output)
    assert_includes @output.string, "✓"
    assert_includes @output.string, "All tests passed"
  end

  def test_error_outputs_message
    Devex::Output.error("Build failed", io: @output)
    assert_includes @output.string, "✗"
    assert_includes @output.string, "Build failed"
  end

  def test_warn_outputs_message
    Devex::Output.warn("Deprecated API", io: @output)
    assert_includes @output.string, "⚠"
    assert_includes @output.string, "Deprecated API"
  end

  def test_info_outputs_message
    Devex::Output.info("Processing files", io: @output)
    assert_includes @output.string, "ℹ"
    assert_includes @output.string, "Processing files"
  end

  def test_bullet_outputs_indented_item
    Devex::Output.bullet("Item one", io: @output)
    # Should have some indentation and the text
    assert_includes @output.string, "Item one"
  end

  def test_indent_adds_spaces
    Devex::Output.indent("Nested content", level: 2, io: @output)
    assert_match(/^ {4}Nested content/, @output.string)
  end

  # --- Structured output ---

  def test_data_outputs_json_in_agent_mode
    with_env("DX_AGENT_MODE" => "1") do
      Devex::Output.data({ name: "test", value: 42 }, io: @output)
      assert_includes @output.string, '"name"'
      assert_includes @output.string, '"test"'
      assert_includes @output.string, "42"
    end
  end

  def test_data_outputs_json_when_format_specified
    Devex::Output.data({ key: "value" }, format: :json, io: @output)
    assert_includes @output.string, '"key"'
    assert_includes @output.string, '"value"'
  end

  def test_data_outputs_yaml_when_format_specified
    Devex::Output.data({ key: "value" }, format: :yaml, io: @output)
    assert_includes @output.string, "key:"
    assert_includes @output.string, "value"
  end

  # --- Template rendering ---

  def test_render_template_basic
    template = "Hello, <%= name %>!"
    result = Devex::Output.render_template(template, binding)
    # Need a local variable for the template
    name = "World"
    result = Devex::Output.render_template(template, binding)
    assert_equal "Hello, World!", result
  end

  def test_render_template_with_conditionals
    template = <<~ERB
      Status: <%= status %>
      <% if success -%>
      All good!
      <% else -%>
      Something went wrong.
      <% end -%>
    ERB

    status = "complete"
    success = true
    result = Devex::Output.render_template(template, binding)
    assert_includes result, "Status: complete"
    assert_includes result, "All good!"
    refute_includes result, "Something went wrong"
  end

  # --- Module inclusion ---

  def test_output_can_be_included_as_mixin
    klass = Class.new do
      include Devex::Output

      def test_output(io)
        # Capture to custom IO - need to use class methods directly
        Devex::Output.success("Included!", io: io)
      end
    end

    obj = klass.new
    io = StringIO.new

    with_env("DX_AGENT_MODE" => "1") do
      obj.test_output(io)
    end

    assert_includes io.string, "Included!"
  end

  # --- Color handling ---

  def test_colorize_returns_plain_text_when_no_color
    with_env("NO_COLOR" => "1") do
      result = Devex::Output.colorize("test", :success)
      assert_equal "test", result
    end
  end

  def test_colorize_applies_color_when_enabled
    with_env("FORCE_COLOR" => "1") do
      result = Devex::Output.colorize("test", :success)
      # ANSI wraps text with escape codes
      refute_equal "test", result
      assert_includes result, "test"
    end
  end
end
