# frozen_string_literal: true

require 'test_helper'

class HeadersTest < Minitest::Test
  Headers = KisHttp::Headers

  # --- construction ---------------------------------------------------------

  def test_empty_by_default
    headers = Headers.new
    assert_equal({}, headers.to_h)
    assert_predicate headers, :empty?
    assert_equal 0, headers.size
  end

  def test_nil_args_is_a_no_op
    assert_equal({}, Headers.new(nil).to_h)
    assert_equal({ 'A' => '1' }, Headers.new('A' => 1).build(nil).to_h)
  end

  def test_builds_from_hash_array_and_headers
    assert_equal({ 'A' => '1' }, Headers.new('A' => 1).to_h)
    assert_equal({ 'A' => '1' }, Headers.new([['A', 1]]).to_h)
    assert_equal({ 'A' => '1' }, Headers.new(Headers.new('A' => 1)).to_h)
  end

  def test_builds_from_object_responding_to_to_hash
    hashlike = Object.new
    def hashlike.to_hash
      { 'A' => 1 }
    end
    assert_equal({ 'A' => '1' }, Headers.new(hashlike).to_h)
  end

  def test_building_from_headers_copies_state
    original = Headers.new('A' => 1)
    Headers.new(original).build('B' => 2)
    assert_equal({ 'A' => '1' }, original.to_h)
  end

  def test_rejects_unconvertible_args
    error = assert_raises(TypeError) { Headers.new(42) }
    assert_match(/Integer given/, error.message)
    assert_raises(TypeError) { Headers.new('Content-Type: x') }
    assert_raises(TypeError) { Headers.new(['Content-Type: x']) }
    assert_raises(TypeError) { Headers.new([['A', 1, 2]]) }
  end

  # --- header names ---------------------------------------------------------

  def test_string_names_are_canonicalized
    headers = Headers.new('content-type' => 'a', 'X-API-KEY' => 'b', 'accept' => 'c')
    assert_equal({ 'Content-Type' => 'a', 'X-Api-Key' => 'b', 'Accept' => 'c' }, headers.to_h)
  end

  def test_symbol_names_translate_underscores_to_dashes
    headers = Headers.new(content_type: 'a', x_api_key: 'b', accept: 'c')
    assert_equal({ 'Content-Type' => 'a', 'X-Api-Key' => 'b', 'Accept' => 'c' }, headers.to_h)
  end

  def test_string_names_keep_underscores
    assert_equal({ 'X_custom' => '1' }, Headers.new('x_custom' => 1).to_h)
  end

  def test_names_differing_only_in_case_are_the_same_header
    headers = Headers.new('Content-Type' => 'a')
    headers.build('content-type' => 'b')
    headers.build(CONTENT_TYPE: 'c')
    assert_equal({ 'Content-Type' => 'c' }, headers.to_h)
    assert_equal 1, headers.size
  end

  def test_duplicate_names_in_one_hash_keep_last
    assert_equal({ 'A' => '2' }, Headers.new('a' => 1, 'A' => 2).to_h)
  end

  def test_rejects_empty_name
    assert_raises(ArgumentError) { Headers.new('' => 1) }
    assert_raises(ArgumentError) { Headers.new(:"" => 1) }
  end

  def test_rejects_names_with_invalid_characters
    ['Bad Name', 'Bad:Name', "Bad\r\nName", 'Bäd', 'Bad/Name', 'Bad(Name)', "Bad\tName"].each do |name|
      error = assert_raises(ArgumentError, name.inspect) { Headers.new(name => 1) }
      assert_match(/invalid header name/, error.message)
    end
  end

  def test_rejects_symbol_names_that_are_invalid_after_translation
    assert_raises(ArgumentError) { Headers.new(:'bad name' => 1) }
  end

  def test_accepts_all_token_characters_in_names
    name = "!#$%&'*+-.^_`|~09AZaz"
    assert Headers.new(name => 1).key?(name)
  end

  def test_non_string_names_are_stringified
    assert_equal({ '1' => 'x' }, Headers.new(1 => 'x').to_h)
  end

  # --- header values --------------------------------------------------------

  def test_values_are_stringified
    headers = Headers.new('A' => 1, 'B' => 2.5, 'C' => :sym, 'D' => true)
    assert_equal({ 'A' => '1', 'B' => '2.5', 'C' => 'sym', 'D' => 'true' }, headers.to_h)
  end

  def test_array_values_are_joined_with_comma_space
    assert_equal({ 'Accept' => 'text/html, application/json' },
                 Headers.new('Accept' => ['text/html', 'application/json']).to_h)
    assert_equal({ 'A' => '1, 2, 3' }, Headers.new('A' => [1, [2, 3]]).to_h)
  end

  def test_empty_string_value_is_kept
    assert_equal({ 'A' => '' }, Headers.new('A' => '').to_h)
  end

  def test_nil_value_removes_header
    headers = Headers.new('A' => 1, 'B' => 2)
    headers.build('a' => nil)
    assert_equal({ 'B' => '2' }, headers.to_h)
  end

  def test_nil_value_for_missing_header_is_a_no_op
    assert_equal({}, Headers.new('A' => nil).to_h)
  end

  def test_rejects_values_containing_cr_or_lf
    ["a\r\nX-Injected: 1", "a\n", "a\r", "\n"].each do |value|
      error = assert_raises(ArgumentError, value.inspect) { Headers.new('A' => value) }
      assert_match(/header A value must not contain CR or LF/, error.message)
    end
  end

  def test_rejects_array_values_containing_cr_or_lf
    assert_raises(ArgumentError) { Headers.new('A' => ['ok', "bad\n"]) }
  end

  def test_allows_tabs_and_non_ascii_in_values
    assert_equal({ 'A' => "x\ty", 'B' => 'ü' }, Headers.new('A' => "x\ty", 'B' => 'ü').to_h)
  end

  def test_stored_values_are_frozen_copies
    value = +'mutable'
    headers = Headers.new('A' => value)
    value << '!'
    assert_equal 'mutable', headers['A']
    assert_predicate headers['A'], :frozen?
  end

  def test_inspect
    assert_equal '#<KisHttp::Headers A: "1", Content-Type: "x">', Headers.new('A' => 1, content_type: 'x').inspect
    assert_equal '#<KisHttp::Headers>', Headers.new.inspect
  end

  # --- lookup ---------------------------------------------------------------

  def test_fetch_is_case_insensitive
    headers = Headers.new('Content-Type' => 'a')
    assert_equal 'a', headers.fetch('content-type')
    assert_equal 'a', headers.fetch('CONTENT-TYPE')
    assert_equal 'a', headers.fetch(:content_type)
  end

  def test_fetch_missing_header_raises_key_error
    headers = Headers.new
    error = assert_raises(KeyError) { headers.fetch(:x_missing) }
    assert_equal 'X-Missing', error.key
    assert_same headers, error.receiver
  end

  def test_fetch_missing_header_yields_canonical_name
    yielded = nil
    result = Headers.new.fetch(:x_missing) do |name|
      yielded = name
      'default'
    end
    assert_equal 'X-Missing', yielded
    assert_equal 'default', result
  end

  def test_fetch_with_invalid_name_does_not_raise_argument_error
    assert_raises(KeyError) { Headers.new.fetch('bad name') }
    assert_equal 'd', Headers.new.fetch('') { 'd' }
  end

  def test_square_brackets_and_key_predicates
    headers = Headers.new('Content-Type' => 'a')
    assert_equal 'a', headers[:content_type]
    assert_equal 'a', headers['CONTENT-TYPE']
    assert_nil headers['X-Missing']
    assert_nil headers['bad name']
    assert headers.key?(:content_type)
    assert headers.include?('content-type')
    assert headers.has_key?('Content-Type') # rubocop:disable Style/PreferredHashMethods
    refute headers.key?(:accept)
    refute headers.key?('')
  end

  # --- remove ---------------------------------------------------------------

  def test_remove_is_case_insensitive_and_returns_value
    headers = Headers.new('Content-Type' => 'a', 'Accept' => 'b')
    assert_equal 'a', headers.remove(:content_type)
    assert_equal({ 'Accept' => 'b' }, headers.to_h)
    assert_equal 'b', headers.remove('ACCEPT')
    assert_predicate headers, :empty?
  end

  def test_remove_missing_header_returns_nil
    headers = Headers.new('A' => 1)
    assert_nil headers.remove('B')
    assert_nil headers.remove('bad name')
    assert_equal({ 'A' => '1' }, headers.to_h)
  end

  # --- plus -----------------------------------------------------------------

  def test_plus_merges_headers_into_self
    left = Headers.new('A' => 1, 'B' => 2)
    right = Headers.new('b' => 3, 'C' => 4)
    assert_same left, left + right
    assert_equal({ 'A' => '1', 'B' => '3', 'C' => '4' }, left.to_h)
    assert_equal({ 'B' => '3', 'C' => '4' }, right.to_h)
  end

  def test_plus_accepts_hash_and_array
    headers = Headers.new('A' => 1)
    assert_same headers, headers + { b: 2 }
    assert_same headers, headers + [['C', 3]]
    assert_equal({ 'A' => '1', 'B' => '2', 'C' => '3' }, headers.to_h)
  end

  def test_plus_rejects_unconvertible_types
    error = assert_raises(TypeError) { Headers.new + 42 }
    assert_match(/Integer given/, error.message)
    assert_raises(TypeError) { Headers.new + 'A: 1' }
  end

  # --- assign_each_to -------------------------------------------------------

  def test_assign_each_to_a_net_http_request
    request = Net::HTTP::Get.new('/')
    headers = Headers.new(content_type: 'application/json', 'X-Api-Key' => 123, accept: %w[a b])
    assert_same request, headers.assign_each_to(request)
    assert_equal 'application/json', request['Content-Type']
    assert_equal '123', request['x-api-key']
    assert_equal 'a, b', request['Accept']
  end

  def test_assign_each_to_anything_responding_to_index_assignment
    target = {}
    Headers.new('A' => 1, b: 2).assign_each_to(target)
    assert_equal({ 'A' => '1', 'B' => '2' }, target)
  end

  def test_assign_each_to_with_no_headers_leaves_target_untouched
    request = Net::HTTP::Get.new('/')
    before = request.to_hash
    Headers.new.assign_each_to(request)
    assert_equal before, request.to_hash
  end

  # --- copying and equality -------------------------------------------------

  def test_dup_and_clone_do_not_share_state
    original = Headers.new('A' => 1)
    original.dup.build('B' => 2)
    original.clone.remove('A')
    assert_equal({ 'A' => '1' }, original.to_h)
  end

  def test_to_h_returns_a_copy
    headers = Headers.new('A' => 1)
    headers.to_h['B'] = '2'
    assert_equal({ 'A' => '1' }, headers.to_h)
  end

  def test_equality
    assert_equal Headers.new('content-type' => 'a'), Headers.new(content_type: 'a')
    refute_equal Headers.new('A' => 1), Headers.new('A' => 2)
    refute_equal Headers.new('A' => 1), Headers.new('A' => 1, 'B' => 2)
    refute_equal Headers.new('A' => 1), { 'A' => '1' }
  end

  def test_usable_as_hash_key
    hash = { Headers.new(a: 1) => :found }
    assert_equal :found, hash[Headers.new('A' => '1')]
    assert_nil hash[Headers.new('A' => '2')]
  end

  def test_each_pair
    pairs = []
    headers = Headers.new(a: 1, b: 2)
    assert_same headers, headers.each_pair { |name, value| pairs << [name, value] }
    assert_equal [%w[A 1], %w[B 2]], pairs
    assert_kind_of Enumerator, headers.each_pair
    assert_equal 2, headers.each_pair.count
  end

  # --- KisHttp.Headers() ----------------------------------------------------

  def test_conversion_function_returns_same_headers_instance
    headers = Headers.new('A' => 1)
    assert_same headers, KisHttp.Headers(headers)
  end

  def test_conversion_function_converts_hash_array_and_nil
    assert_equal({ 'A' => '1' }, KisHttp.Headers(a: 1).to_h)
    assert_equal({ 'A' => '1' }, KisHttp.Headers('A' => 1).to_h)
    assert_equal({ 'A' => '1' }, KisHttp.Headers([['A', 1]]).to_h)
    assert_equal({}, KisHttp.Headers(nil).to_h)
    assert_equal({}, KisHttp.Headers({}).to_h)
  end

  def test_conversion_function_rejects_other_types
    assert_raises(TypeError) { KisHttp.Headers(42) }
    assert_raises(TypeError) { KisHttp.Headers('A: 1') }
  end
end
