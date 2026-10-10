# frozen_string_literal: true

require 'test_helper'

class OptionsTest < Minitest::Test
  Options = KisHttp::Options

  # --- construction ---------------------------------------------------------

  def test_empty_by_default
    options = Options.new
    assert_equal '', options.opts
    assert_equal '', options.to_s
    assert_equal '', options.query
    assert_equal({}, options.to_h)
    assert_predicate options, :empty?
    assert_equal 0, options.size
  end

  def test_nil_args_is_a_no_op
    assert_equal '', Options.new(nil).opts
    assert_equal '?a=1', Options.new(a: 1).build(nil).opts
  end

  def test_builds_from_hash_with_symbol_and_string_keys
    options = Options.new(a: 1, 'b' => 'two')
    assert_equal '?a=1&b=two', options.opts
    assert_equal({ 'a' => '1', 'b' => 'two' }, options.to_h)
  end

  def test_builds_from_array_of_pairs
    assert_equal '?a=1&b=2', Options.new([[:a, 1], ['b', 2]]).opts
  end

  def test_builds_from_query_string
    assert_equal({ 'a' => '1', 'b' => 'x y' }, Options.new('a=1&b=x+y').to_h)
  end

  def test_builds_from_query_string_with_leading_question_mark
    assert_equal({ 'a' => '1' }, Options.new('?a=1').to_h)
    assert_equal({}, Options.new('?').to_h)
    assert_equal({}, Options.new('').to_h)
  end

  def test_query_string_with_repeated_keys_collects_into_array
    assert_equal({ 'a' => %w[1 2 3] }, Options.new('a=1&a=2&a=3').to_h)
  end

  def test_query_string_decodes_percent_encoding
    assert_equal({ 'q' => 'a&b=c?d#e', 'ü' => 'ß' }, Options.new('q=a%26b%3Dc%3Fd%23e&%C3%BC=%C3%9F').to_h)
  end

  def test_builds_from_another_options
    original = Options.new(a: 1)
    copy = Options.new(original)
    copy.build(b: 2)
    assert_equal '?a=1', original.opts
    assert_equal '?a=1&b=2', copy.opts
  end

  def test_builds_from_object_responding_to_to_hash
    hashlike = Object.new
    def hashlike.to_hash
      { 'a' => 1 }
    end
    assert_equal '?a=1', Options.new(hashlike).opts
  end

  def test_rejects_unconvertible_args
    error = assert_raises(TypeError) { Options.new(42) }
    assert_match(/Integer given/, error.message)
    assert_raises(TypeError) { Options.new(:sym) }
    assert_raises(TypeError) { Options.new(Object.new) }
  end

  def test_rejects_malformed_pairs
    error = assert_raises(TypeError) { Options.new(['a']) }
    assert_match(/index 0/, error.message)
    assert_raises(TypeError) { Options.new([[:a, 1, 2]]) }
    assert_raises(TypeError) { Options.new(['a=1']) }
  end

  def test_rejects_empty_keys
    assert_raises(ArgumentError) { Options.new('' => 1) }
    assert_raises(ArgumentError) { Options.new(:"" => 1) }
  end

  def test_non_string_keys_are_stringified
    assert_equal({ '1' => 'x', '2.5' => 'y' }, Options.new(1 => 'x', 2.5 => 'y').to_h)
  end

  # --- rendering ------------------------------------------------------------

  def test_url_encodes_reserved_characters_in_values
    options = Options.new(q: 'a b&c=d?e#f/g', r: 'ü')
    assert_equal '?q=a+b%26c%3Dd%3Fe%23f%2Fg&r=%C3%BC', options.opts
  end

  def test_url_encodes_reserved_characters_in_keys
    assert_equal '?a+b%26c=1', Options.new('a b&c' => 1).opts
  end

  def test_rendered_query_is_a_valid_uri
    options = Options.new(q: 'a b&c=d?e#f')
    uri = URI("http://example.com/path#{options}")
    assert_equal 'q=a+b%26c%3Dd%3Fe%23f', uri.query
    assert_nil uri.fragment
  end

  def test_rendering_round_trips_through_parsing
    original = Options.new(q: 'a b&c=d?e#f', ids: [1, 2], empty: '', n: 'ü')
    assert_equal original.to_h, Options.new(original.to_s).to_h
  end

  def test_values_are_stringified
    assert_equal({ 'a' => '1', 'b' => '2.5', 'c' => 'sym', 'd' => 'true' },
                 Options.new(a: 1, b: 2.5, c: :sym, d: true).to_h)
  end

  def test_empty_string_value_renders_key_with_equals
    options = Options.new(a: '')
    assert_equal '?a=', options.opts
    assert_equal({ 'a' => '' }, options.to_h)
  end

  def test_nil_value_renders_bare_key
    options = Options.new(flag: nil, a: 1)
    assert_equal '?flag&a=1', options.opts
    assert_equal({ 'flag' => nil, 'a' => '1' }, options.to_h)
  end

  def test_value_containing_equals_sign_survives
    options = Options.new(token: 'abc==', filter: 'a=b')
    assert_equal({ 'token' => 'abc==', 'filter' => 'a=b' }, options.to_h)
    assert_equal 'token=abc%3D%3D', options.fetch(:token)
    assert_equal 'a=b', options.remove(:filter)
  end

  def test_array_value_renders_repeated_keys
    options = Options.new(id: [1, 'two', :three])
    assert_equal '?id=1&id=two&id=three', options.opts
    assert_equal({ 'id' => %w[1 two three] }, options.to_h)
    assert_equal 'id=1&id=two&id=three', options.fetch(:id)
  end

  def test_nested_array_value_is_flattened
    assert_equal '?id=1&id=2&id=3', Options.new(id: [1, [2, [3]]]).opts
  end

  def test_nil_inside_array_renders_bare_key
    options = Options.new(id: [1, nil, 2], b: 3)
    assert_equal '?id=1&id&id=2&b=3', options.opts
    assert_equal({ 'id' => ['1', nil, '2'], 'b' => '3' }, options.to_h)
  end

  def test_empty_array_value_renders_nothing_but_is_kept
    options = Options.new(id: [], a: 1)
    assert_equal '?a=1', options.opts
    assert_equal({ 'id' => [], 'a' => '1' }, options.to_h)
    assert options.key?(:id)
    assert_equal '', options.fetch(:id)
    assert_equal '', Options.new(id: []).opts
    assert_equal '?a=1', Options.new(a: 1, id: []).opts
  end

  def test_array_elements_are_url_encoded
    assert_equal '?q=a+b&q=c%26d', Options.new(q: ['a b', 'c&d']).opts
  end

  def test_stored_values_are_frozen_copies
    value = +'mutable'
    options = Options.new(a: value, b: [value])
    value << '!'
    assert_equal({ 'a' => 'mutable', 'b' => ['mutable'] }, options.to_h)
    assert_predicate options['a'], :frozen?
    assert_predicate options['b'], :frozen?
    assert_predicate options['b'].first, :frozen?
  end

  def test_inspect
    assert_equal '#<KisHttp::Options "?a=1">', Options.new(a: 1).inspect
    assert_equal '#<KisHttp::Options "">', Options.new.inspect
  end

  # --- build / update -------------------------------------------------------

  def test_build_returns_self
    options = Options.new
    assert_same options, options.build(a: 1)
  end

  def test_build_replaces_existing_key_and_moves_it_to_the_end
    options = Options.new(a: 1, b: 2)
    options.build(a: 3)
    assert_equal '?b=2&a=3', options.opts
    assert_equal 2, options.size
  end

  def test_symbol_and_string_keys_refer_to_the_same_option
    options = Options.new(a: 1)
    options.build('a' => 2)
    assert_equal '?a=2', options.opts
    options.build(a: 3)
    assert_equal '?a=3', options.opts
  end

  def test_rebuilding_a_key_with_empty_value_does_not_duplicate_it
    options = Options.new(a: '')
    options.build(a: 'x')
    assert_equal '?a=x', options.opts
    options.build(a: nil)
    options.build(a: 'y')
    assert_equal '?a=y', options.opts
  end

  def test_build_with_duplicate_keys_in_one_hash_keeps_last
    options = Options.new(a: 1, 'a' => 2)
    assert_equal '?a=2', options.opts
  end

  def test_build_accepts_query_strings_and_arrays
    options = Options.new(a: 1)
    options.build('b=2&c=3').build([[:d, 4]])
    assert_equal '?a=1&b=2&c=3&d=4', options.opts
  end

  # --- fetch ----------------------------------------------------------------

  def test_fetch_returns_encoded_pair
    options = Options.new(q: 'a b')
    assert_equal 'q=a+b', options.fetch(:q)
    assert_equal 'q=a+b', options.fetch('q')
  end

  def test_fetch_of_nil_value_returns_bare_key
    assert_equal 'flag', Options.new(flag: nil).fetch(:flag)
  end

  def test_fetch_of_empty_value_returns_key_with_equals
    assert_equal 'a=', Options.new(a: '').fetch(:a)
  end

  def test_fetch_missing_key_raises_key_error
    options = Options.new(a: 1)
    error = assert_raises(KeyError) { options.fetch(:b) }
    assert_equal 'b', error.key
    assert_same options, error.receiver
    assert_match(/"b"/, error.message)
  end

  def test_fetch_missing_key_yields_key_to_block
    yielded = nil
    result = Options.new.fetch(:b) do |key|
      yielded = key
      'default'
    end
    assert_equal 'b', yielded
    assert_equal 'default', result
  end

  def test_fetch_present_key_ignores_block
    assert_equal 'a=1', Options.new(a: 1).fetch(:a) { flunk 'block should not run' }
  end

  def test_fetch_bang_returns_pair_and_removes_it
    options = Options.new(a: 1, b: 2)
    assert_equal 'a=1', options.fetch!(:a)
    assert_equal '?b=2', options.opts
    refute options.key?(:a)
  end

  def test_fetch_bang_missing_key_raises_and_leaves_options_untouched
    options = Options.new(a: 1)
    assert_raises(KeyError) { options.fetch!(:b) }
    assert_equal '?a=1', options.opts
  end

  def test_fetch_bang_missing_key_uses_block
    options = Options.new(a: 1)
    assert_equal 'fallback', options.fetch!(:b) { 'fallback' }
    assert_equal '?a=1', options.opts
  end

  def test_square_brackets_returns_raw_value_or_nil
    options = Options.new(q: 'a b', ids: [1, 2], flag: nil)
    assert_equal 'a b', options[:q]
    assert_equal %w[1 2], options['ids']
    assert_nil options[:flag]
    assert_nil options[:missing]
  end

  def test_key_predicates
    options = Options.new(a: 1, flag: nil)
    assert options.key?(:a)
    assert options.key?('a')
    assert options.key?(:flag)
    refute options.key?(:b)
    assert options.include?(:a)
    assert options.has_key?(:a) # rubocop:disable Style/PreferredHashMethods
  end

  # --- remove / reset -------------------------------------------------------

  def test_remove_returns_value_and_removes_pair
    options = Options.new(a: 1, b: 'x y')
    assert_equal 'x y', options.remove(:b)
    assert_equal '?a=1', options.opts
    assert_equal '1', options.remove('a')
    assert_equal '', options.opts
  end

  def test_remove_missing_key_returns_nil
    options = Options.new(a: 1)
    assert_nil options.remove(:b)
    assert_equal '?a=1', options.opts
  end

  def test_remove_key_with_empty_or_nil_value
    options = Options.new(a: '', b: nil, c: 1)
    assert_equal '', options.remove(:a)
    assert_nil options.remove(:b)
    assert_equal '?c=1', options.opts
  end

  def test_remove_array_value_returns_array
    assert_equal %w[1 2], Options.new(a: [1, 2]).remove(:a)
  end

  def test_reset_bang_purges_everything_and_returns_self
    options = Options.new(a: 1, b: 2)
    assert_same options, options.reset!
    assert_equal '', options.opts
    assert_predicate options, :empty?
  end

  # --- immutable ------------------------------------------------------------

  def test_immutable_restores_state_after_build
    options = Options.new(a: 1)
    options.immutable { |o| o.build(b: 2) }
    assert_equal '?a=1', options.opts
  end

  def test_immutable_restores_state_after_remove_and_reset
    options = Options.new(a: 1, b: 2)
    options.immutable do |o|
      o.remove(:a)
      o.reset!
      assert_equal '', o.opts
    end
    assert_equal '?a=1&b=2', options.opts
  end

  def test_immutable_restores_state_after_fetch_bang
    options = Options.new(a: 1)
    assert_equal 'a=1', options.immutable { |o| o.fetch!(:a) }
    assert_equal '?a=1', options.opts
  end

  def test_immutable_yields_self_and_returns_block_result
    options = Options.new(a: 1)
    result = options.immutable do |o|
      assert_same options, o
      o.build(b: 2).opts
    end
    assert_equal '?a=1&b=2', result
  end

  def test_immutable_restores_state_when_block_raises
    options = Options.new(a: 1)
    assert_raises(RuntimeError) do
      options.immutable do |o|
        o.build(b: 2)
        raise 'boom'
      end
    end
    assert_equal '?a=1', options.opts
  end

  def test_immutable_can_be_nested
    options = Options.new(a: 1)
    options.immutable do |o|
      o.build(b: 2)
      o.immutable { |i| i.build(c: 3) }
      assert_equal '?a=1&b=2', o.opts
    end
    assert_equal '?a=1', options.opts
  end

  # --- plus -----------------------------------------------------------------

  def test_plus_merges_options_and_returns_self
    left = Options.new(a: 1, b: 2)
    right = Options.new(b: 3, c: 4)
    assert_same left, left + right
    assert_equal '?a=1&b=3&c=4', left.opts
    assert_equal '?b=3&c=4', right.opts
  end

  def test_plus_accepts_hash_array_and_string
    options = Options.new(a: 1)
    assert_same options, options + { b: 2 }
    assert_same options, options + [[:c, 3]]
    assert_same options, options + 'd=4&e=x+y'
    assert_equal({ 'a' => '1', 'b' => '2', 'c' => '3', 'd' => '4', 'e' => 'x y' }, options.to_h)
  end

  def test_plus_rejects_unconvertible_types
    error = assert_raises(TypeError) { Options.new + 42 }
    assert_match(/Integer given/, error.message)
  end

  def test_plus_with_empty_options_is_a_no_op
    options = Options.new(a: 1)
    assert_same options, options + Options.new
    assert_equal '?a=1', options.opts
  end

  # --- copying and equality -------------------------------------------------

  def test_dup_does_not_share_state
    original = Options.new(a: 1)
    copy = original.dup
    copy.build(b: 2)
    copy.remove(:a)
    assert_equal '?a=1', original.opts
    assert_equal '?b=2', copy.opts
  end

  def test_clone_does_not_share_state
    original = Options.new(a: 1)
    original.clone.build(b: 2)
    assert_equal '?a=1', original.opts
  end

  def test_to_h_returns_a_copy
    options = Options.new(a: 1)
    options.to_h['b'] = '2'
    assert_equal '?a=1', options.opts
  end

  def test_equality
    assert_equal Options.new(a: 1, b: 2), Options.new('a' => '1', 'b' => '2')
    refute_equal Options.new(a: 1), Options.new(a: 2)
    refute_equal Options.new(a: 1), Options.new(a: 1, b: 2)
    refute_equal Options.new(a: 1), { 'a' => '1' }
    refute_equal Options.new(a: 1), 'a=1'
  end

  def test_equality_is_order_insensitive
    assert_equal Options.new(a: 1, b: 2), Options.new(b: 2, a: 1)
  end

  def test_usable_as_hash_key
    hash = { Options.new(a: 1) => :found }
    assert_equal :found, hash[Options.new(a: 1)]
    assert_nil hash[Options.new(a: 2)]
  end

  def test_each_pair
    pairs = []
    options = Options.new(a: 1, b: [2, 3])
    assert_same options, options.each_pair { |key, value| pairs << [key, value] }
    assert_equal [['a', '1'], ['b', %w[2 3]]], pairs
    assert_kind_of Enumerator, options.each_pair
    assert_equal 2, options.each_pair.count
  end

  # --- KisHttp.Options() ----------------------------------------------------

  def test_conversion_function_returns_same_options_instance
    options = Options.new(a: 1)
    assert_same options, KisHttp.Options(options)
  end

  def test_conversion_function_converts_hash_array_string_and_nil
    assert_equal '?a=1', KisHttp.Options(a: 1).opts
    assert_equal '?a=1', KisHttp.Options('a' => 1).opts
    assert_equal '?a=1', KisHttp.Options([[:a, 1]]).opts
    assert_equal '?a=1', KisHttp.Options('a=1').opts
    assert_equal '', KisHttp.Options(nil).opts
    assert_equal '', KisHttp.Options({}).opts
  end

  def test_conversion_function_rejects_other_types
    assert_raises(TypeError) { KisHttp.Options(42) }
    assert_raises(TypeError) { KisHttp.Options(Object.new) }
  end
end
