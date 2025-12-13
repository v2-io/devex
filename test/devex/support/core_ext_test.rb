# frozen_string_literal: true

require "test_helper"
require "devex/support/core_ext"

class CoreExtTest < Minitest::Test
  using Devex::Support::CoreExt

  # ─────────────────────────────────────────────────────────────
  # Object#blank? / present? / presence
  # ─────────────────────────────────────────────────────────────

  def test_nil_is_blank
    assert nil.blank?
    refute nil.present?
    assert_nil nil.presence
  end

  def test_false_is_blank
    assert false.blank?
    refute false.present?
    assert_nil false.presence
  end

  def test_true_is_not_blank
    refute true.blank?
    assert true.present?
    assert_equal true, true.presence
  end

  def test_empty_string_is_blank
    assert "".blank?
    refute "".present?
    assert_nil "".presence
  end

  def test_whitespace_string_is_blank
    assert "   ".blank?
    assert "\t\n".blank?
    refute "   ".present?
  end

  def test_string_with_content_is_not_blank
    refute "hello".blank?
    assert "hello".present?
    assert_equal "hello", "hello".presence
  end

  def test_empty_array_is_blank
    assert [].blank?
    refute [].present?
  end

  def test_array_with_elements_is_not_blank
    refute [1, 2, 3].blank?
    assert [1, 2, 3].present?
  end

  def test_empty_hash_is_blank
    assert({}.blank?)
    refute({}.present?)
  end

  def test_hash_with_keys_is_not_blank
    refute({ a: 1 }.blank?)
    assert({ a: 1 }.present?)
  end

  def test_numbers_are_never_blank
    refute 0.blank?
    refute 0.0.blank?
    refute(-1.blank?)
    assert 42.present?
  end

  # ─────────────────────────────────────────────────────────────
  # Object#numeric?
  # ─────────────────────────────────────────────────────────────

  def test_numeric_on_integers
    assert 42.numeric?
  end

  def test_numeric_on_strings
    assert "42".numeric?
    assert "3.14".numeric?
    refute "hello".numeric?
    refute "".numeric?
  end

  # ─────────────────────────────────────────────────────────────
  # Object#in?
  # ─────────────────────────────────────────────────────────────

  def test_in_with_array
    assert 2.in?([1, 2, 3])
    refute 4.in?([1, 2, 3])
  end

  def test_in_with_range
    assert 5.in?(1..10)
    refute 15.in?(1..10)
  end

  def test_in_with_string
    assert "o".in?("hello")
    refute "x".in?("hello")
  end

  # ─────────────────────────────────────────────────────────────
  # String extensions
  # ─────────────────────────────────────────────────────────────

  def test_string_to_p_returns_path
    require "devex/support/path"
    path = "/some/path".to_p
    assert_instance_of Devex::Support::Path, path
    assert_equal "/some/path", path.to_s
  end

  def test_squish_collapses_whitespace
    assert_equal "hello world", "  hello   world  ".squish
    assert_equal "a b c", "a\n\t  b\r\n   c".squish
  end

  def test_truncate_with_default_omission
    assert_equal "hello...", "hello world".truncate(8)
    assert_equal "hi", "hi".truncate(8)
  end

  def test_truncate_with_custom_omission
    assert_equal "hello--", "hello world".truncate(7, omission: "--")
  end

  def test_truncate_words
    text = "The quick brown fox jumps over the lazy dog"
    assert_equal "The quick brown...", text.truncate_words(3)
  end

  def test_indent_adds_prefix
    result = "line1\nline2".indent(2)
    assert_equal "  line1\n  line2", result
  end

  def test_indent_with_custom_char
    result = "line".indent(2, "\t")
    assert_equal "\t\tline", result
  end

  def test_remove_pattern
    assert_equal "hllo", "hello".remove(/e/)
    assert_equal "hello", "hello world".remove(" world")
  end

  def test_wrap_preserves_paragraphs
    text = "Short line.\n\nAnother paragraph."
    result = text.wrap(:first, 80)
    assert_includes result, "Short line."
    assert_includes result, "Another paragraph."
  end

  def test_sentences_splits_text
    text = "First sentence. Second one! Third?"
    sentences = text.sentences
    assert_equal 3, sentences.size
    assert_equal "First sentence.", sentences[0]
  end

  def test_to_sh_escapes_shell
    assert_equal "''", "".to_sh
    assert_equal "hello", "hello".to_sh
    # Special chars should be escaped
    result = "hello world".to_sh
    assert result.include?("\\") || result.include?("'")
  end

  def test_fnv32_returns_integer
    hash = "hello".fnv32
    assert_kind_of Integer, hash
    assert hash > 0
    # Same input should give same hash
    assert_equal "hello".fnv32, "hello".fnv32
    # Different input should give different hash
    refute_equal "hello".fnv32, "world".fnv32
  end

  def test_fnv64_returns_integer
    hash = "hello".fnv64
    assert_kind_of Integer, hash
    assert hash > "hello".fnv32 # 64-bit should generally be larger
  end

  def test_base64url_encodes
    encoded = "hello".base64url
    assert_kind_of String, encoded
    refute_includes encoded, "+"
    refute_includes encoded, "/"
    refute_includes encoded, "="
  end

  # ─────────────────────────────────────────────────────────────
  # Enumerable extensions
  # ─────────────────────────────────────────────────────────────

  def test_average
    assert_equal 2.0, [1, 2, 3].average
    assert_equal 0.0, [].average
  end

  def test_median_odd_count
    assert_equal 3, [1, 3, 5].median
  end

  def test_median_even_count
    assert_equal 2.5, [1, 2, 3, 4].median
  end

  def test_median_empty
    assert_nil [].median
  end

  def test_sample_variance
    # Known variance calculation
    arr = [2, 4, 4, 4, 5, 5, 7, 9]
    variance = arr.sample_variance
    assert_in_delta 4.571, variance, 0.01
  end

  def test_standard_deviation
    arr = [2, 4, 4, 4, 5, 5, 7, 9]
    stddev = arr.standard_deviation
    assert_in_delta 2.138, stddev, 0.01
  end

  def test_percentile
    arr = (1..100).to_a
    # Percentile uses linear interpolation
    p50 = arr.percentile(50)
    assert_in_delta 50.5, p50, 1
    p25 = arr.percentile(25)
    assert_in_delta 25.75, p25, 1
  end

  def test_q20_q80
    arr = (1..100).to_a
    assert_in_delta 20, arr.q20, 1
    assert_in_delta 80, arr.q80, 1
  end

  def test_robust_average
    arr = [1, 2, 3, 4, 5]
    result = arr.robust_average
    assert_kind_of Float, result
  end

  def test_amap
    result = ["hello", "world"].amap(:upcase)
    assert_equal ["HELLO", "WORLD"], result
  end

  def test_summarize_runs
    result = [1, 1, 1, 2, 2, 3].summarize_runs
    assert_equal [[3, 1], [2, 2], [1, 3]], result
  end

  def test_many_without_block
    refute [].many?
    refute [1].many?
    assert [1, 2].many?
  end

  def test_many_with_block
    assert [1, 2, 3, 4].many? { |x| x > 2 }
    refute [1, 2, 3, 4].many? { |x| x > 3 }
  end

  def test_index_by
    # Use hashes - index_by can use hash access via pluck semantics
    users = [
      { id: 1, name: "Alice" },
      { id: 2, name: "Bob" }
    ]
    indexed = users.index_by { |u| u[:id] }
    assert_equal "Alice", indexed[1][:name]
    assert_equal "Bob", indexed[2][:name]
  end

  def test_index_with_default
    result = [:a, :b].index_with(0)
    assert_equal({ a: 0, b: 0 }, result)
  end

  def test_index_with_block
    result = [1, 2, 3].index_with { |n| n * 2 }
    assert_equal({ 1 => 2, 2 => 4, 3 => 6 }, result)
  end

  def test_excluding
    assert_equal [1, 3], [1, 2, 3].excluding(2)
    assert_equal [1], [1, 2, 3].without(2, 3)
  end

  def test_including
    assert_equal [1, 2, 3, 4], [1, 2].including(3, 4)
  end

  def test_pluck_single_key
    items = [{ name: "a" }, { name: "b" }]
    assert_equal ["a", "b"], items.pluck(:name)
  end

  def test_pluck_multiple_keys
    items = [{ a: 1, b: 2 }, { a: 3, b: 4 }]
    assert_equal [[1, 2], [3, 4]], items.pluck(:a, :b)
  end

  # ─────────────────────────────────────────────────────────────
  # Array extensions
  # ─────────────────────────────────────────────────────────────

  def test_positional_accessors
    arr = [1, 2, 3, 4, 5, 6, 7]
    assert_equal 2, arr.second
    assert_equal 3, arr.third
    assert_equal 4, arr.fourth
    assert_equal 5, arr.fifth
    assert_equal 6, arr.second_to_last
    assert_equal 5, arr.third_to_last
  end

  def test_to_sentence_empty
    assert_equal "", [].to_sentence
  end

  def test_to_sentence_single
    assert_equal "one", ["one"].to_sentence
  end

  def test_to_sentence_two
    assert_equal "one and two", ["one", "two"].to_sentence
  end

  def test_to_sentence_many
    assert_equal "one, two, and three", ["one", "two", "three"].to_sentence
  end

  def test_in_groups_of
    result = [1, 2, 3, 4, 5].in_groups_of(2)
    assert_equal [[1, 2], [3, 4], [5]], result
  end

  def test_in_groups_of_with_fill
    result = [1, 2, 3, 4, 5].in_groups_of(2, 0)
    assert_equal [[1, 2], [3, 4], [5, 0]], result
  end

  def test_in_groups
    result = [1, 2, 3, 4, 5].in_groups(2)
    assert_equal 2, result.size
    assert_equal 5, result.flatten.size
  end

  def test_extract_options
    args = [1, 2, { option: true }]
    options = args.extract_options!
    assert_equal({ option: true }, options)
    assert_equal [1, 2], args
  end

  def test_extract_options_without_hash
    args = [1, 2, 3]
    options = args.extract_options!
    assert_equal({}, options)
    assert_equal [1, 2, 3], args
  end

  def test_deep_dup
    original = [{ a: 1 }, [2, 3]]
    duped = original.deep_dup
    duped[0][:a] = 999
    duped[1][0] = 999
    assert_equal 1, original[0][:a]
    assert_equal 2, original[1][0]
  end

  # ─────────────────────────────────────────────────────────────
  # Hash extensions
  # ─────────────────────────────────────────────────────────────

  def test_hash_deep_dup
    original = { a: { b: 1 } }
    duped = original.deep_dup
    duped[:a][:b] = 999
    assert_equal 1, original[:a][:b]
  end

  def test_deep_merge
    h1 = { a: { b: 1, c: 2 } }
    h2 = { a: { b: 99, d: 3 } }
    result = h1.deep_merge(h2)
    assert_equal({ a: { b: 99, c: 2, d: 3 } }, result)
    # Original unchanged
    assert_equal 1, h1[:a][:b]
  end

  def test_deep_merge_bang
    h1 = { a: { b: 1 } }
    h2 = { a: { c: 2 } }
    h1.deep_merge!(h2)
    assert_equal({ a: { b: 1, c: 2 } }, h1)
  end

  def test_deep_stringify_keys
    result = { a: { b: 1 } }.deep_stringify_keys
    assert_equal({ "a" => { "b" => 1 } }, result)
  end

  def test_deep_symbolize_keys
    result = { "a" => { "b" => 1 } }.deep_symbolize_keys
    assert_equal({ a: { b: 1 } }, result)
  end

  def test_assert_valid_keys_passes
    { a: 1, b: 2 }.assert_valid_keys(:a, :b, :c)
  end

  def test_assert_valid_keys_raises
    assert_raises(ArgumentError) do
      { a: 1, invalid: 2 }.assert_valid_keys(:a, :b)
    end
  end

  def test_stable_compact
    result = { b: nil, a: { d: nil, c: 1 } }.stable_compact
    # Should remove nils and sort keys
    assert_equal({ "a" => { "c" => 1 } }.inspect, result.inspect.gsub(/:(\w+)=>/, '"\1"=>'))
  end

  def test_to_sig
    h1 = { a: 1, b: 2 }
    h2 = { b: 2, a: 1 }
    # Same content should produce same signature regardless of key order
    assert_equal h1.to_sig, h2.to_sig
  end

  def test_to_sig_different_content
    h1 = { a: 1 }
    h2 = { a: 2 }
    refute_equal h1.to_sig, h2.to_sig
  end

  # ─────────────────────────────────────────────────────────────
  # Integer extensions
  # ─────────────────────────────────────────────────────────────

  def test_ordinal
    assert_equal "st", 1.ordinal
    assert_equal "nd", 2.ordinal
    assert_equal "rd", 3.ordinal
    assert_equal "th", 4.ordinal
    assert_equal "th", 11.ordinal
    assert_equal "th", 12.ordinal
    assert_equal "th", 13.ordinal
    assert_equal "st", 21.ordinal
    assert_equal "nd", 22.ordinal
  end

  def test_ordinalize
    assert_equal "1st", 1.ordinalize
    assert_equal "2nd", 2.ordinalize
    assert_equal "3rd", 3.ordinalize
    assert_equal "4th", 4.ordinalize
    assert_equal "11th", 11.ordinalize
    assert_equal "21st", 21.ordinalize
    assert_equal "100th", 100.ordinalize
    assert_equal "101st", 101.ordinalize
  end
end
