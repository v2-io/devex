# frozen_string_literal: true

require "set"

module Devex
  module Support
    # Core extensions as refinements.
    #
    # Usage:
    #   using Devex::Support::CoreExt
    #
    # Or load globally (for CLI tools):
    #   require "devex/support/global"
    #
    module CoreExt
      # ─────────────────────────────────────────────────────────────
      # Implementation Modules
      # These define the actual methods and can be included in both
      # refinements and monkey-patched classes.
      # ─────────────────────────────────────────────────────────────

      module ObjectMethods
        def blank? = respond_to?(:empty?) ? empty? : !self

        def present? = !blank?

        def presence() self if present? end

        def numeric?
          true if Float(self)
        rescue StandardError
          false
        end

        def in?(collection) = collection.include?(self)
      end

      module NilMethods
        def blank?   = true
        def present? = false
        def presence = nil
      end

      module FalseMethods
        def blank?   = true
        def present? = false
        def presence = nil
      end

      module TrueMethods
        def blank?   = false
        def present? = true
        def presence = self
      end

      module NumericMethods
        def blank?   = false
        def present? = true
        def presence = self
        def numeric? = true
      end

      module ArrayBlankMethods
        def blank?   = empty?
        def present? = !blank?

        def presence() self if present? end
      end

      module HashBlankMethods
        def blank?   = empty?
        def present? = !blank?

        def presence() self if present? end
      end

      module StringMethods
        def blank? = empty? || !match?(/[^[:space:]]/)

        # Override present? to use String's blank? (import_methods copies bytecode,
        # so ObjectMethods#present? would call Object's blank?)
        def present? = !blank?

        def presence() self if present? end

        def to_p = Devex::Support::Path.new(self)

        def wrap(indent = :first, width = 90)
          ind = case indent
                when :first then self[/^[[:space:]]*/] || ""
                when ::String  then indent
                when ::Integer then " " * indent.abs
                else ""
                end

          ind_size        = (ind.count("\t") * 8) + ind.length - ind.count("\t")
          effective_width = [width - ind_size, 1].max

          paragraphs = strip.split(/\n[ \t]*\n/m)
          paragraphs.map do |p|
            p.gsub(/[[:space:]]+/, " ")
             .strip
             .scan(/.{1,#{effective_width}}(?: |$)/)
             .map { |row| ind + row.strip }
             .join("\n")
          end.join("\n\n")
        end

        def sentences = gsub(/\s+/, " ").scan(/[^.!?]+[.!?]+(?:\s+|$)|[^.!?]+$/).map(&:strip).reject(&:empty?)

        def to_sh
          return "''" if empty?

          gsub(%r{([^A-Za-z0-9_\-.,:/@\n])}, '\\\\\\\\\\1').gsub("\n", "'\n'")
        end

        def squish = gsub(/[[:space:]]+/, " ").strip

        def fnv32 = bytes.reduce(0x811c9dc5) { |h, b| ((h ^ b) * 0x01000193) % (1 << 32) }

        def fnv64 = bytes.reduce(0xcbf29ce484222325) { |h, b| ((h ^ b) * 0x100000001b3) % (1 << 64) }

        def base64url
          require "base64"
          Base64.urlsafe_encode64(self, padding: false)
        end

        def truncate(length, omission: "...")
          return self if self.length <= length

          stop = length - omission.length
          stop = 0 if stop < 0
          self[0, stop] + omission
        end

        def truncate_words(count, omission: "...")
          words = split
          return self if words.length <= count

          words.first(count).join(" ") + omission
        end

        def indent(amount, indent_char = " ")
          prefix = indent_char * amount
          gsub(/^/, prefix)
        end

        def remove(pattern) = gsub(pattern, "")

        # ─────────────────────────────────────────────────────────────
        # Case Transforms
        # ─────────────────────────────────────────────────────────────

        # ALL UPPER CASE
        def up_case = upcase

        # all lower case
        def down_case = downcase

        # snake_case
        # Converts CamelCase, kebab-case, spaces to snake_case
        def snake_case = gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').gsub(/[\s-]+/, "_").downcase

        # SCREAM_CASE (screaming snake case / constant case)
        def scream_case = snake_case.upcase

        # kebab-case
        def kebab_case = snake_case.tr("_", "-")

        # PascalCase (first letter uppercase)
        def pascal_case = snake_case.split("_").map(&:capitalize).join

        # camelCase (first letter lowercase)
        def camel_case
          result = pascal_case
          return result if result.empty?

          result[0] = result[0].downcase
          result
        end

        # Title Case With Proper Rules
        # - Always capitalize first/last word
        # - Lowercase: articles, coord conjunctions, short prepositions
        # - Capitalize after hyphens (unless minor word)
        def title_case
          # Words that should be lowercase (unless first/last)
          # Articles, coordinating conjunctions, short prepositions
          # Note: verbs (is), pronouns (it), subordinating conj (if) should be capitalized
          minor_words = Set.new(%w[
            a an the
            for and nor but or yet so
            at by in to of on up as
          ])

          # Split keeping delimiters (spaces and hyphens)
          tokens = split(/(\s+|-+)/)
          return "" if tokens.empty?

          # Find actual words (not delimiters)
          word_indices = tokens.each_index.select { |i| !tokens[i].match?(/^[\s-]+$/) }
          return self if word_indices.empty?

          first_word_idx = word_indices.first
          last_word_idx  = word_indices.last

          tokens.each_with_index.map do |token, idx|
            if token.match?(/^[\s-]+$/)
              # Delimiter - keep as-is
              token
            elsif idx == first_word_idx || idx == last_word_idx
              # First or last word - always capitalize
              token.capitalize
            elsif minor_words.include?(token.downcase)
              # Minor word - lowercase
              token.downcase
            else
              # Regular word - capitalize
              token.capitalize
            end
          end.join
        end

        # Aliases without underscores
        # Note: upcase and downcase are Ruby native - don't override
        def snakecase  = snake_case
        def screamcase = scream_case
        def kebabcase  = kebab_case
        def pascalcase = pascal_case
        def camelcase  = camel_case
        def titlecase  = title_case

        # Additional common aliases
        def upper      = up_case
        def uppercase  = up_case
        def upper_case = up_case
        def caps       = up_case

        def lower      = down_case
        def lowercase  = down_case
        def lower_case = down_case

        def var_case = snake_case
        def varcase  = snake_case

        def const_case = scream_case
        def constcase  = scream_case

        def mod_case = pascal_case
        def modcase  = pascal_case
      end

      module EnumerableMethods
        def average
          return 0.0 if respond_to?(:empty?) && empty?

          arr = to_a
          return 0.0 if arr.empty?

          arr.sum.to_f / arr.size
        end

        def mean = average

        def median
          arr = to_a.sort
          return nil if arr.empty?

          mid = arr.size / 2
          arr.size.odd? ? arr[mid] : (arr[mid - 1] + arr[mid]) / 2.0
        end

        def sample_variance
          arr = to_a
          return 0.0 if arr.size < 2

          avg = arr.sum.to_f / arr.size
          arr.sum { |x| (x - avg) ** 2 } / (arr.size - 1).to_f
        end

        def variance = sample_variance

        def standard_deviation = Math.sqrt(sample_variance)

        def stddev = standard_deviation

        def percentile(p)
          arr = to_a.sort
          return nil if arr.empty?

          k = (p / 100.0) * (arr.size - 1)
          f = k.floor
          c = k.ceil
          return arr[f] if f == c

          (arr[f] * (c - k)) + (arr[c] * (k - f))
        end

        def q20 = percentile(20)
        def q80 = percentile(80)

        def robust_average
          arr = to_a
          return nil if arr.empty?

          (q20.to_f + median.to_f + q80.to_f) / 3.0
        end

        def amap(method, *args, &block) = map { |item| item.send(method, *args, &block) }

        def summarize_runs
          arr = to_a
          return [] if arr.empty?

          arr.chunk_while { |a, b| a == b }.map { |run| [run.size, run.first] }
        end

        def many?
          count = 0
          if block_given?
            each do |e|
              count += 1 if yield(e)
              return true if count > 1
            end
          else
            each do
              count += 1
              return true if count > 1
            end
          end
          false
        end

        def index_by = each_with_object({}) { |e, h| h[yield(e)] = e }

        def index_with(default = nil)
          if block_given?
            each_with_object({}) { |e, h| h[e] = yield(e) }
          else
            each_with_object({}) { |e, h| h[e] = default }
          end
        end

        def excluding(*elements) = reject { |e| elements.include?(e) }

        def without(*elements) = excluding(*elements)

        def including(*elements) = to_a + elements

        def pluck(*keys)
          if keys.one?
            key = keys.first
            map { |e| e.respond_to?(key) ? e.send(key) : e[key] }
          else
            map { |e| keys.map { |k| e.respond_to?(k) ? e.send(k) : e[k] } }
          end
        end
      end

      module ArrayMethods
        def second         = self[1]
        def third          = self[2]
        def fourth         = self[3]
        def fifth          = self[4]
        def second_to_last = self[-2]
        def third_to_last  = self[-3]

        def to_sentence(connector: ", ", last_connector: ", and ")
          case size
          when 0 then ""
          when 1 then first.to_s
          when 2 then "#{first}#{last_connector.sub(/^, /, ' ')}#{second}"
          else
            "#{self[0..-2].join(connector)}#{last_connector}#{last}"
          end
        end

        def in_groups_of(n, fill_with = nil)
          arr                        = dup
          if fill_with && (remainder = arr.size % n) > 0
            arr.concat(Array.new(n - remainder, fill_with))
          end
          arr.each_slice(n).to_a
        end

        def in_groups(n, fill_with = nil)
          division = size.div(n)
          modulo   = size % n
          groups   = []
          start    = 0

          n.times do |i|
            length = division + (modulo > 0 && modulo > i ? 1 : 0)
            groups << slice(start, length)
            groups.last << fill_with if fill_with && groups.last.size < division + 1
            start += length
          end

          groups
        end

        def extract_options! = last.is_a?(Hash) ? pop : {}

        def deep_dup
          map do |e|
            e.respond_to?(:deep_dup) ? e.deep_dup : e.dup
          rescue StandardError
            e
          end
        end
      end

      module HashMethods
        def deep_dup
          each_with_object({}) do |(k, v), h|
            h[if k.respond_to?(:deep_dup)
                k.deep_dup
              else
                begin
                  k.dup
                rescue StandardError
                  k
                end
              end] =
              if v.respond_to?(:deep_dup)
                v.deep_dup
              else
                begin
                  v.dup
                rescue StandardError
                  v
                end
              end
          end
        end

        def deep_merge(other, &) = dup.deep_merge!(other, &)

        def deep_merge!(other, &block)
          other.each do |k, v|
            self[k] = if self[k].is_a?(Hash) && v.is_a?(Hash)
                        self[k].deep_merge(v, &block)
                      elsif block_given?
                        yield(k, self[k], v)
                      else
                        v
                      end
          end
          self
        end

        def deep_stringify_keys = transform_keys_recursive(&:to_s)

        def deep_symbolize_keys = transform_keys_recursive { |k| k.respond_to?(:to_sym) ? k.to_sym : k }

        def assert_valid_keys(*valid_keys)
          valid_keys = valid_keys.flatten
          each_key do |k|
            unless valid_keys.include?(k)
              raise ArgumentError, "Unknown key: #{k.inspect}. Valid keys are: #{valid_keys.map(&:inspect).join(', ')}"
            end
          end
          self
        end

        def stable_compact
          compact
            .transform_values do |v|
              case v
              when Hash then v.stable_compact
              when Array then v.map { |e| e.respond_to?(:stable_compact) ? e.stable_compact : e }
              else v
              end
            end
            .sort_by { |k, _| k.to_s }
            .to_h
        end

        def to_sig
          require "digest"
          Digest::SHA1.hexdigest(stable_compact.inspect)
        end

        def transform_keys_recursive(&block)
          each_with_object({}) do |(k, v), h|
            new_key = yield(k)
            h[new_key] = case v
                         when Hash then v.transform_keys_recursive(&block)
                         when Array then v.map { |e| e.is_a?(Hash) ? e.transform_keys_recursive(&block) : e }
                         else v
                         end
          end
        end
      end

      # Ordinal suffixes (defined outside refinement to avoid warning)
      ORDINALS = { 1 => "st", 2 => "nd", 3 => "rd" }.freeze

      module IntegerMethods
        def ordinal
          abs_mod_100 = abs % 100
          if (11..13).cover?(abs_mod_100)
            "th"
          else
            CoreExt::ORDINALS.fetch(abs % 10, "th")
          end
        end

        def ordinalize = "#{self}#{ordinal}"
      end

      # ─────────────────────────────────────────────────────────────
      # Refinements
      # Use import_methods (Ruby 3.1+) instead of include (removed in 3.2)
      # ─────────────────────────────────────────────────────────────

      refine Object do
        import_methods ObjectMethods
      end

      refine NilClass do
        import_methods NilMethods
      end

      refine FalseClass do
        import_methods FalseMethods
      end

      refine TrueClass do
        import_methods TrueMethods
      end

      refine Numeric do
        import_methods NumericMethods
      end

      refine Array do
        import_methods ArrayBlankMethods
        import_methods ArrayMethods
      end

      refine Hash do
        import_methods HashBlankMethods
        import_methods HashMethods
      end

      refine String do
        import_methods StringMethods
      end

      refine Enumerable do
        import_methods EnumerableMethods
      end

      refine Integer do
        import_methods IntegerMethods
      end
    end
  end
end
