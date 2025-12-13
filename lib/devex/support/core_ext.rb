# frozen_string_literal: true

module Devex
  module Support
    # Core extensions as refinements.
    #
    # Usage:
    #   using Devex::Support::CoreExt
    #
    # Or load globally (for CLI tools):
    #   require "devex/support/core_ext/global"
    #
    module CoreExt
      # ─────────────────────────────────────────────────────────────
      # Object Extensions
      # ─────────────────────────────────────────────────────────────

      refine Object do
        # Returns true if object is nil, false, empty, or whitespace-only string
        def blank?
          respond_to?(:empty?) ? empty? : !self
        end

        # Opposite of blank?
        def present?
          !blank?
        end

        # Returns self if present?, otherwise nil
        def presence
          self if present?
        end

        # Returns true if object can be converted to a number
        def numeric?
          true if Float(self) rescue false
        end

        # Returns true if object is contained in the given collection
        # Cleaner than collection.include?(item)
        def in?(collection)
          collection.include?(self)
        end
      end

      refine NilClass do
        def blank? = true
        def present? = false
        def presence = nil
      end

      refine FalseClass do
        def blank? = true
        def present? = false
        def presence = nil
      end

      refine TrueClass do
        def blank? = false
        def present? = true
        def presence = self
      end

      refine Numeric do
        def blank? = false
        def present? = true
        def presence = self
        def numeric? = true
      end

      refine Array do
        def blank? = empty?
      end

      refine Hash do
        def blank? = empty?
      end

      refine String do
        def blank?
          empty? || !match?(/[^[:space:]]/)
        end

        # Convert string to Path
        def to_p
          Devex::Support::Path.new(self)
        end
      end

      # ─────────────────────────────────────────────────────────────
      # String Extensions
      # ─────────────────────────────────────────────────────────────

      refine String do
        # Word-wrap text preserving paragraphs
        # @param indent [:first, String, Integer] - indentation style
        # @param width [Integer] - line width (default 90)
        def wrap(indent = :first, width = 90)
          ind = case indent
                when :first  then self[/^[[:space:]]*/] || ""
                when ::String  then indent
                when ::Integer then " " * indent.abs
                else ""
                end

          ind_size = ind.count("\t") * 8 + ind.length - ind.count("\t")
          effective_width = [width - ind_size, 1].max

          paragraphs = strip.split(/\n[ \t]*\n/m)
          paragraphs.map { |p|
            p.gsub(/[[:space:]]+/, " ")
             .strip
             .scan(/.{1,#{effective_width}}(?: |$)/)
             .map { |row| ind + row.strip }
             .join("\n")
          }.join("\n\n")
        end

        # Split text into sentences
        def sentences
          gsub(/\s+/, " ")
            .scan(/[^.!?]+[.!?]+(?:\s+|$)|[^.!?]+$/)
            .map(&:strip)
            .reject(&:empty?)
        end

        # Escape for shell (POSIX)
        def to_sh
          return "''" if empty?
          gsub(/([^A-Za-z0-9_\-.,:\/@\n])/, '\\\\\\1').gsub("\n", "'\n'")
        end

        # Collapse whitespace and strip
        def squish
          gsub(/[[:space:]]+/, " ").strip
        end

        # FNV-1a 32-bit hash (fast, non-cryptographic)
        def fnv32
          bytes.reduce(0x811c9dc5) { |h, b| ((h ^ b) * 0x01000193) % (1 << 32) }
        end

        # FNV-1a 64-bit hash (fast, non-cryptographic)
        def fnv64
          bytes.reduce(0xcbf29ce484222325) { |h, b| ((h ^ b) * 0x100000001b3) % (1 << 64) }
        end

        # URL-safe Base64 encoding
        def base64url
          require "base64"
          Base64.urlsafe_encode64(self, padding: false)
        end

        # Truncate to length with omission
        def truncate(length, omission: "...")
          return self if self.length <= length
          stop = length - omission.length
          stop = 0 if stop < 0
          self[0, stop] + omission
        end

        # Truncate to word boundary
        def truncate_words(count, omission: "...")
          words = split
          return self if words.length <= count
          words.first(count).join(" ") + omission
        end

        # Indent each line
        def indent(amount, indent_char = " ")
          prefix = indent_char * amount
          gsub(/^/, prefix)
        end

        # Remove pattern from string
        def remove(pattern)
          gsub(pattern, "")
        end
      end

      # ─────────────────────────────────────────────────────────────
      # Enumerable Extensions
      # ─────────────────────────────────────────────────────────────

      refine Enumerable do
        # Arithmetic mean
        def average
          return 0.0 if respond_to?(:empty?) && empty?
          arr = to_a
          return 0.0 if arr.empty?
          arr.sum.to_f / arr.size
        end
        alias_method :mean, :average

        # Median value
        def median
          arr = to_a.sort
          return nil if arr.empty?
          mid = arr.size / 2
          arr.size.odd? ? arr[mid] : (arr[mid - 1] + arr[mid]) / 2.0
        end

        # Sample variance
        def sample_variance
          arr = to_a
          return 0.0 if arr.size < 2
          avg = arr.sum.to_f / arr.size
          arr.sum { |x| (x - avg) ** 2 } / (arr.size - 1).to_f
        end
        alias_method :variance, :sample_variance

        # Standard deviation
        def standard_deviation
          Math.sqrt(sample_variance)
        end
        alias_method :stddev, :standard_deviation

        # Percentile calculation
        def percentile(p)
          arr = to_a.sort
          return nil if arr.empty?
          k = (p / 100.0) * (arr.size - 1)
          f = k.floor
          c = k.ceil
          return arr[f] if f == c
          arr[f] * (c - k) + arr[c] * (k - f)
        end

        # 20th percentile (first quintile)
        def q20 = percentile(20)

        # 80th percentile (fourth quintile)
        def q80 = percentile(80)

        # Trimmed mean (average of q20, median, q80)
        def robust_average
          arr = to_a
          return nil if arr.empty?
          (q20.to_f + median.to_f + q80.to_f) / 3.0
        end

        # Map by sending method to each element
        # @example ["foo", "bar"].amap(:upcase) => ["FOO", "BAR"]
        def amap(method, *args, &block)
          map { |item| item.send(method, *args, &block) }
        end

        # Run-length encoding
        # @example [1,1,1,2,2,3].summarize_runs => [[3,1], [2,2], [1,3]]
        def summarize_runs
          arr = to_a
          return [] if arr.empty?
          arr.chunk_while { |a, b| a == b }.map { |run| [run.size, run.first] }
        end

        # Test if collection has more than one element
        def many?
          count = 0
          if block_given?
            each { |e| count += 1 if yield(e); return true if count > 1 }
          else
            each { count += 1; return true if count > 1 }
          end
          false
        end

        # Create hash indexed by block result
        # @example users.index_by(&:id) => { 1 => user1, 2 => user2 }
        def index_by
          each_with_object({}) { |e, h| h[yield(e)] = e }
        end

        # Create hash with elements as keys
        # @example [:a, :b].index_with(0) => { a: 0, b: 0 }
        def index_with(default = nil)
          if block_given?
            each_with_object({}) { |e, h| h[e] = yield(e) }
          else
            each_with_object({}) { |e, h| h[e] = default }
          end
        end

        # Exclude elements (opposite of select)
        def excluding(*elements)
          reject { |e| elements.include?(e) }
        end
        alias_method :without, :excluding

        # Include additional elements
        def including(*elements)
          to_a + elements
        end

        # Extract values for given keys from elements
        def pluck(*keys)
          if keys.one?
            key = keys.first
            map { |e| e.respond_to?(key) ? e.send(key) : e[key] }
          else
            map { |e| keys.map { |k| e.respond_to?(k) ? e.send(k) : e[k] } }
          end
        end
      end

      # ─────────────────────────────────────────────────────────────
      # Array Extensions
      # ─────────────────────────────────────────────────────────────

      refine Array do
        # Positional accessors
        def second = self[1]
        def third = self[2]
        def fourth = self[3]
        def fifth = self[4]
        def second_to_last = self[-2]
        def third_to_last = self[-3]

        # Convert to sentence: ["a", "b", "c"] => "a, b, and c"
        def to_sentence(connector: ", ", last_connector: ", and ")
          case size
          when 0 then ""
          when 1 then first.to_s
          when 2 then "#{first}#{last_connector.sub(/^, /, " ")}#{second}"
          else
            "#{self[0..-2].join(connector)}#{last_connector}#{last}"
          end
        end

        # Split into groups of n
        def in_groups_of(n, fill_with = nil)
          arr = dup
          if fill_with && (remainder = arr.size % n) > 0
            arr.concat(Array.new(n - remainder, fill_with))
          end
          arr.each_slice(n).to_a
        end

        # Split into n groups
        def in_groups(n, fill_with = nil)
          division = size.div(n)
          modulo = size % n
          groups = []
          start = 0

          n.times do |i|
            length = division + (modulo > 0 && modulo > i ? 1 : 0)
            groups << slice(start, length)
            groups.last << fill_with if fill_with && groups.last.size < division + 1
            start += length
          end

          groups
        end

        # Extract options hash from end of array
        def extract_options!
          last.is_a?(Hash) ? pop : {}
        end

        # Deep duplicate
        def deep_dup
          map { |e| e.respond_to?(:deep_dup) ? e.deep_dup : e.dup rescue e }
        end
      end

      # ─────────────────────────────────────────────────────────────
      # Hash Extensions
      # ─────────────────────────────────────────────────────────────

      refine Hash do
        # Deep duplicate
        def deep_dup
          each_with_object({}) do |(k, v), h|
            h[k.respond_to?(:deep_dup) ? k.deep_dup : (k.dup rescue k)] =
              v.respond_to?(:deep_dup) ? v.deep_dup : (v.dup rescue v)
          end
        end

        # Deep merge
        def deep_merge(other, &block)
          dup.deep_merge!(other, &block)
        end

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

        # Recursively stringify keys
        def deep_stringify_keys
          transform_keys_recursive(&:to_s)
        end

        # Recursively symbolize keys
        def deep_symbolize_keys
          transform_keys_recursive { |k| k.respond_to?(:to_sym) ? k.to_sym : k }
        end

        # Assert only allowed keys are present
        def assert_valid_keys(*valid_keys)
          valid_keys = valid_keys.flatten
          each_key do |k|
            unless valid_keys.include?(k)
              raise ArgumentError, "Unknown key: #{k.inspect}. Valid keys are: #{valid_keys.map(&:inspect).join(', ')}"
            end
          end
          self
        end

        # Deep compact with stable sorting for signatures
        def stable_compact
          compact
            .transform_values { |v|
              case v
              when Hash then v.stable_compact
              when Array then v.map { |e| e.respond_to?(:stable_compact) ? e.stable_compact : e }
              else v
              end
            }
            .sort_by { |k, _| k.to_s }
            .to_h
        end

        # Content-based signature (SHA1 of stable representation)
        def to_sig
          require "digest"
          Digest::SHA1.hexdigest(stable_compact.inspect)
        end

        # Helper for deep key transformation (not marked private - refinement scoping is sufficient)
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

      # ─────────────────────────────────────────────────────────────
      # Integer Extensions
      # ─────────────────────────────────────────────────────────────

      # Ordinal suffixes (defined outside refinement to avoid warning)
      ORDINALS = { 1 => "st", 2 => "nd", 3 => "rd" }.freeze

      refine Integer do
        # Returns ordinal suffix (st, nd, rd, th)
        def ordinal
          abs_mod_100 = abs % 100
          if (11..13).cover?(abs_mod_100)
            "th"
          else
            CoreExt::ORDINALS.fetch(abs % 10, "th")
          end
        end

        # Returns number with ordinal suffix (1st, 2nd, 3rd)
        def ordinalize
          "#{self}#{ordinal}"
        end
      end
    end
  end
end
