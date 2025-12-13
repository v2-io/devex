# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "devex"

require "minitest/autorun"
require "minitest/reporters"
require "climate_control"

# Configure reporters for nicer output
Minitest::Reporters.use! [
  Minitest::Reporters::DefaultReporter.new(color: true)
]

# Helper module for tests that need to manipulate environment
module EnvHelper
  # Run a block with modified environment variables, restoring them after.
  # Uses climate_control for safe manipulation.
  def with_env(env_vars, &block)
    ClimateControl.modify(env_vars, &block)
  end

  # Clear all DX/DEVEX environment variables before a test
  def clear_dx_env
    dx_vars = ENV.keys.select { |k| k.start_with?("DX_", "DEVEX_") }
    dx_vars.each { |k| ENV.delete(k) }
  end
end
