# frozen_string_literal: true

# Global loading of Devex support extensions.
#
# This file monkey-patches core classes with the extensions from CoreExt.
# Use this in CLI tools where you want the extensions available everywhere.
#
# For library code, prefer refinements:
#   using Devex::Support::CoreExt
#
# For CLI tools:
#   require "devex/support/global"
#

require_relative "../support"
require_relative "core_ext"

module Devex
  module Support
    module Global
      class << self
        def load!
          return if @loaded

          # Include the shared implementation modules into core classes
          Object.include CoreExt::ObjectMethods
          NilClass.include CoreExt::NilMethods
          FalseClass.include CoreExt::FalseMethods
          TrueClass.include CoreExt::TrueMethods
          Numeric.include CoreExt::NumericMethods

          Array.include CoreExt::ArrayBlankMethods
          Array.include CoreExt::ArrayMethods

          Hash.include CoreExt::HashBlankMethods
          Hash.include CoreExt::HashMethods

          String.include CoreExt::StringMethods

          # Enumerable goes on the module, affects all including classes
          Enumerable.module_eval { include CoreExt::EnumerableMethods }

          Integer.include CoreExt::IntegerMethods

          # Also add ANSI string methods
          add_ansi_string_methods!

          @loaded = true
        end

        private

        def add_ansi_string_methods!
          String.class_eval do
            def ansi(*styles, bg: nil)
              Devex::Support::ANSI[self, *styles, bg: bg]
            end

            def strip_ansi
              Devex::Support::ANSI.strip(self)
            end

            def visible_length
              Devex::Support::ANSI.visible_length(self)
            end
          end
        end
      end
    end
  end
end

# Auto-load when required
Devex::Support::Global.load!
