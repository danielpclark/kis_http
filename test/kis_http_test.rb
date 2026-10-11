# frozen_string_literal: true

require 'test_helper'

class KisHttpTest < Minitest::Test
  def setup
    @server = EchoServer.new
  end

  def teardown
    @server.shutdown
  end

  def url(path = '/')
    @server.url(path)
  end

  def echo(response)
    JSON.parse(response.body)
  end

  # --- verbs ----------------------------------------------------------------

  def test_each_verb_sends_its_method
    { get: 'GET', post: 'POST', put: 'PUT', patch: 'PATCH', delete: 'DELETE', head: 'HEAD' }.each do |verb, method|
      response = KisHttp.public_send(verb, url('/things'))
      assert_kind_of Net::HTTPResponse, response
      assert_equal '200', response.code
      request = @server.last_request
      assert_equal method, request.method, verb.inspect
      assert_equal '/things', request.target
    end
  end

  def test_head_response_has_no_body
    response = KisHttp.head(url('/things'))
    assert_equal '200', response.code
    assert_nil response.body
  end

  def test_response_status_passes_through
    assert_equal '404', KisHttp.get(url('/status/404')).code
    assert_equal '500', KisHttp.post(url('/status/500')).code
    assert_kind_of Net::HTTPNotFound, KisHttp.get(url('/status/404'))
  end

  # --- urls -----------------------------------------------------------------

  def test_url_without_path_requests_root
    KisHttp.get("http://127.0.0.1:#{@server.port}")
    assert_equal '/', @server.last_request.target
  end

  def test_url_as_uri_object
    KisHttp.get(URI(url('/from-uri')), options: { a: 1 })
    assert_equal '/from-uri?a=1', @server.last_request.target
  end

  def test_url_as_uri_object_is_not_mutated
    uri = URI(url('/x'))
    KisHttp.get(uri, options: { a: 1 })
    assert_nil uri.query
  end

  def test_url_with_surrounding_whitespace_is_trimmed
    KisHttp.get("  #{url('/trim')}\n")
    assert_equal '/trim', @server.last_request.target
  end

  def test_url_with_encoded_path_is_preserved
    KisHttp.get(url('/a%20b/c?x=%26'))
    assert_equal '/a%20b/c?x=%26', @server.last_request.target
  end

  def test_rejects_nil_and_blank_urls
    [nil, '', '   '].each do |bad|
      error = assert_raises(ArgumentError, bad.inspect) { KisHttp.get(bad) }
      assert_match(/must not be nil or empty/, error.message)
    end
  end

  def test_rejects_non_http_urls
    ['ftp://example.com/x', 'mailto:a@b.c', '/relative/path', 'example.com/no-scheme'].each do |bad|
      error = assert_raises(ArgumentError, bad.inspect) { KisHttp.get(bad) }
      assert_match(/only http and https urls are supported/, error.message)
    end
    assert_raises(ArgumentError) { KisHttp.get(URI('ftp://example.com/x')) }
  end

  def test_rejects_urls_without_host
    error = assert_raises(ArgumentError) { KisHttp.get('http://') }
    assert_match(/url has no host/, error.message)
    assert_raises(ArgumentError) { KisHttp.get('http:///path') }
  end

  def test_unparseable_url_raises_uri_error
    assert_raises(URI::InvalidURIError) { KisHttp.get('http://exa mple.com/') }
  end

  def test_ipv6_host
    server = begin
      EchoServer.new('::1')
    rescue SystemCallError
      skip 'IPv6 loopback is not available'
    end
    KisHttp.get(server.url('/v6'), options: { a: 1 })
    assert_equal '/v6?a=1', server.last_request.target
  ensure
    server&.shutdown
  end

  # --- options --------------------------------------------------------------

  def test_options_are_appended_as_query_string
    KisHttp.get(url('/search'), options: { q: 'a b&c', page: 2, ids: [1, 2] })
    request = @server.last_request
    assert_equal '/search?q=a+b%26c&page=2&ids=1&ids=2', request.target
    assert_equal 'a+b%26c&page=2&ids=1&ids=2', request.query.sub('q=', '')
  end

  def test_options_merge_with_query_already_in_url
    KisHttp.get(url('/search?a=1&b=2'), options: { c: 3 })
    assert_equal '/search?a=1&b=2&c=3', @server.last_request.target
  end

  def test_options_with_url_ending_in_bare_question_mark
    KisHttp.get(url('/search?'), options: { c: 3 })
    assert_equal '/search?c=3', @server.last_request.target
  end

  def test_url_fragment_is_dropped_and_options_still_apply
    KisHttp.get(url('/page#section'), options: { c: 3 })
    assert_equal '/page?c=3', @server.last_request.target
  end

  def test_options_accept_options_instance_string_and_array
    KisHttp.get(url('/'), options: KisHttp::Options.new(a: 1))
    assert_equal '/?a=1', @server.last_request.target
    KisHttp.get(url('/'), options: 'b=2&c=x+y')
    assert_equal '/?b=2&c=x+y', @server.last_request.target
    KisHttp.get(url('/'), options: [[:d, 4]])
    assert_equal '/?d=4', @server.last_request.target
  end

  def test_empty_or_nil_options_add_no_query
    KisHttp.get(url('/x'), options: nil)
    assert_equal '/x', @server.last_request.target
    KisHttp.get(url('/x'), options: {})
    assert_equal '/x', @server.last_request.target
    KisHttp.get(url('/x'), options: '')
    assert_equal '/x', @server.last_request.target
    KisHttp.get(url('/x?a=1'), options: {})
    assert_equal '/x?a=1', @server.last_request.target
  end

  def test_options_instance_is_not_mutated_by_the_request
    options = KisHttp::Options.new(a: 1)
    KisHttp.get(url('/x?b=2'), options: options)
    assert_equal '?a=1', options.opts
  end

  def test_invalid_options_raise_before_any_request
    assert_raises(TypeError) { KisHttp.get(url('/'), options: 42) }
    assert_raises(ArgumentError) { KisHttp.get(url('/'), options: { '' => 1 }) }
    assert_predicate @server.requests, :empty?
  end

  # --- headers --------------------------------------------------------------

  def test_headers_are_sent
    KisHttp.get(url('/'), headers: { 'X-Custom' => 'yes', accept: 'application/json' })
    headers = @server.last_request.headers
    assert_equal 'yes', headers['x-custom']
    assert_equal 'application/json', headers['accept']
  end

  def test_headers_accept_headers_instance_and_array
    KisHttp.get(url('/'), headers: KisHttp::Headers.new(x_one: 1))
    assert_equal '1', @server.last_request.headers['x-one']
    KisHttp.get(url('/'), headers: [['X-Two', 2]])
    assert_equal '2', @server.last_request.headers['x-two']
  end

  def test_headers_override_net_http_defaults
    KisHttp.get(url('/'), headers: { user_agent: 'kis_http tests' })
    assert_equal 'kis_http tests', @server.last_request.headers['user-agent']
  end

  def test_nil_and_empty_headers_send_only_defaults
    KisHttp.get(url('/'), headers: nil)
    assert_equal 'Ruby', @server.last_request.headers['user-agent']
    KisHttp.get(url('/'), headers: {})
    assert_equal 'Ruby', @server.last_request.headers['user-agent']
  end

  def test_header_injection_is_rejected_before_any_request
    assert_raises(ArgumentError) { KisHttp.get(url('/'), headers: { 'X-A' => "1\r\nX-B: 2" }) }
    assert_raises(ArgumentError) { KisHttp.get(url('/'), headers: { 'X A' => '1' }) }
    assert_raises(TypeError) { KisHttp.get(url('/'), headers: 'X-A: 1') }
    assert_predicate @server.requests, :empty?
  end

  # --- body -----------------------------------------------------------------

  def test_string_body_is_sent_as_is
    KisHttp.post(url('/'), body: 'raw=text', headers: { content_type: 'text/plain' })
    request = @server.last_request
    assert_equal 'raw=text', request.body
    assert_equal '8', request.headers['content-length']
    assert_equal 'text/plain', request.headers['content-type']
  end

  def test_string_body_without_content_type_gets_net_http_default
    KisHttp.post(url('/'), body: 'raw=text')
    assert_equal 'application/x-www-form-urlencoded', @server.last_request.headers['content-type']
  end

  def test_hash_body_is_sent_as_json_with_content_type
    KisHttp.post(url('/'), body: { name: 'ü', tags: [1, 2], nested: { ok: true } })
    request = @server.last_request
    assert_equal({ 'name' => 'ü', 'tags' => [1, 2], 'nested' => { 'ok' => true } }, JSON.parse(request.body))
    assert_equal 'application/json', request.headers['content-type']
    assert_equal request.body.bytesize.to_s, request.headers['content-length']
  end

  def test_array_body_is_sent_as_json
    KisHttp.put(url('/'), body: [1, 'two', nil])
    request = @server.last_request
    assert_equal '[1,"two",null]', request.body
    assert_equal 'application/json', request.headers['content-type']
  end

  def test_json_body_keeps_explicit_content_type
    KisHttp.post(url('/'), body: { a: 1 }, headers: { content_type: 'application/vnd.api+json' })
    assert_equal 'application/vnd.api+json', @server.last_request.headers['content-type']
  end

  def test_empty_hash_body_is_sent_as_empty_json_object
    KisHttp.post(url('/'), body: {})
    assert_equal '{}', @server.last_request.body
  end

  def test_nil_body_sends_nothing
    KisHttp.post(url('/'), body: nil)
    assert_equal '', @server.last_request.body
    KisHttp.get(url('/'))
    request = @server.last_request
    assert_equal '', request.body
    refute request.headers.key?('content-type')
  end

  def test_body_responding_to_to_str_is_sent
    stringlike = Object.new
    def stringlike.to_str
      'from to_str'
    end
    KisHttp.post(url('/'), body: stringlike, headers: { content_type: 'text/plain' })
    assert_equal 'from to_str', @server.last_request.body
  end

  def test_rejects_other_body_types_before_any_request
    [42, :sym, Object.new].each do |bad|
      error = assert_raises(TypeError, bad.inspect) { KisHttp.post(url('/'), body: bad) }
      assert_match(/body must be a String, Hash or Array/, error.message)
    end
    assert_predicate @server.requests, :empty?
  end

  def test_body_can_be_sent_with_delete_and_patch
    KisHttp.delete(url('/'), body: { ids: [1] })
    assert_equal '{"ids":[1]}', @server.last_request.body
    KisHttp.patch(url('/'), body: 'patched', headers: { content_type: 'text/plain' })
    assert_equal 'patched', @server.last_request.body
  end

  # --- basic auth -----------------------------------------------------------

  def test_userinfo_in_url_is_sent_as_basic_auth
    KisHttp.get("http://user:p%40ss%3Aword@127.0.0.1:#{@server.port}/secret")
    request = @server.last_request
    assert_equal "Basic #{['user:p@ss:word'].pack('m0')}", request.headers['authorization']
    assert_equal '/secret', request.target
  end

  def test_userinfo_without_password
    KisHttp.get("http://user@127.0.0.1:#{@server.port}/")
    assert_equal "Basic #{['user:'].pack('m0')}", @server.last_request.headers['authorization']
  end

  def test_explicit_authorization_header_wins_over_userinfo
    KisHttp.get("http://user:pass@127.0.0.1:#{@server.port}/", headers: { authorization: 'Bearer token' })
    assert_equal 'Bearer token', @server.last_request.headers['authorization']
  end

  def test_no_userinfo_sends_no_authorization
    KisHttp.get(url('/'))
    refute @server.last_request.headers.key?('authorization')
  end

  # --- ssl ------------------------------------------------------------------

  class FakeHttp
    attr_reader :host, :port, :sent, :use_ssl

    def initialize(host, port)
      @host = host
      @port = port
    end

    def use_ssl=(value)
      @use_ssl = value
    end

    def request(request)
      @sent = request
      Net::HTTPOK.new('1.1', '200', 'OK')
    end
  end

  def with_fake_http
    fakes = []
    factory = lambda do |host, port|
      fake = FakeHttp.new(host, port)
      fakes << fake
      fake
    end
    Net::HTTP.stub(:new, factory) { yield }
    assert_equal 1, fakes.size
    fakes.first
  end

  def test_https_url_enables_ssl_and_uses_default_port
    fake = with_fake_http { KisHttp.get('https://example.com/secure', options: { a: 1 }) }
    assert_equal true, fake.use_ssl
    assert_equal 'example.com', fake.host
    assert_equal 443, fake.port
    assert_equal '/secure?a=1', fake.sent.path
  end

  def test_http_url_disables_ssl_and_uses_default_port
    fake = with_fake_http { KisHttp.get('http://example.com') }
    assert_equal false, fake.use_ssl
    assert_equal 80, fake.port
    assert_equal '/', fake.sent.path
  end

  def test_explicit_port_is_used
    fake = with_fake_http { KisHttp.get('https://example.com:8443/') }
    assert_equal 8443, fake.port
    assert_equal true, fake.use_ssl
  end

  def test_ipv6_literal_host_is_passed_without_brackets
    fake = with_fake_http { KisHttp.get('http://[::1]:8080/') }
    assert_equal '::1', fake.host
    assert_equal 8080, fake.port
  end

  def test_scheme_is_case_insensitive
    fake = with_fake_http { KisHttp.get('HTTPS://example.com/') }
    assert_equal true, fake.use_ssl
    assert_equal 443, fake.port
  end
end
