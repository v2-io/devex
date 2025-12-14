# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in devex.gemspec
gemspec

gem "rake", "~> 13.0"

# Runtime dependencies (also declared in gemspec)
gem "tty-prompt", "~> 0.23"

# Testing
group :development, :test do
  gem "aruba", "~> 2.2"          # CLI integration testing
  gem "climate_control", "~> 1.2" # Safe env var manipulation in tests
  gem "minitest", "~> 5.20"
  gem "minitest-reporters", "~> 1.6"
  gem "prop_check", "~> 1.0"     # Property-based testing
  gem "rubocop", "~> 1.72"
  gem "rubocop-tablecop", "~> 0.2"
end

gem "rubocop-minitest", "~> 0.38.2"
