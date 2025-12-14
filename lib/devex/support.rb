# frozen_string_literal: true

# Devex Support Library
#
# A zero-dependency collection of Ruby utilities optimized for CLI development.
# Provides Path manipulation, ANSI colors, and core extensions as refinements.
#
# ## Quick Start
#
#   require "devex/support"
#
#   # Use refinements (scoped to current file)
#   using Devex::Support::CoreExt
#   using Devex::Support::ANSI::StringMethods
#
#   # Or for CLI tools, load globally:
#   require "devex/support/global"
#
# ## Components
#
# ### Path - Enhanced Pathname for CLI tools
#
#   path = Path["~/src/project"]
#   path = Path.pwd / "lib" / "foo.rb"
#
#   path.r?          # readable?
#   path.w?          # writable?
#   path.exist?      # exists?
#   path.dir!        # ensure parent dirs exist
#   path.rel         # relative path with ~ for home
#   path.short       # shortest representation
#
# ### ANSI - Terminal colors (truecolor, zero deps)
#
#   ANSI["text", :bold, :success]
#   ANSI["text", "#5AF78E"]
#   ANSI % ["Outer %{inner}", :yellow, inner: ["nested", :blue]]
#
# ### CoreExt - Refinements for common operations
#
#   "".blank?                    # => true
#   nil.present?                 # => false
#   [1,2,3].average              # => 2.0
#   {a: 1}.deep_merge(b: 2)      # => {a: 1, b: 2}
#   "hello world".truncate(8)    # => "hello..."
#

module Devex
  module Support
    # Autoload support modules
    autoload :Path,    "devex/support/path"
    autoload :ANSI,    "devex/support/ansi"
    autoload :CoreExt, "devex/support/core_ext"

    # Convenience: expose Path at module level
    # Allows: Devex::Support::Path["~/foo"]
    # Or after `include Devex::Support`: Path["~/foo"]

    class << self
      # Version of the support library
      def version = "0.1.0"
    end
  end
end

# Also expose Path at Devex level for convenience
# Allows: Devex::Path["~/foo"]
module Devex
  Path = Support::Path
  ANSI = Support::ANSI
end
