# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require 'kis_http/version'
require 'kis_http/headers'
require 'kis_http/options'

# All the HTTP things
#
# Every request method takes a url and the keyword arguments:
#
# * `body:` a `String` sent as-is, or a `Hash`/`Array` serialized as JSON
#   (adding a `Content-Type: application/json` header when none is given).
# * `headers:` anything accepted by {KisHttp.Headers}.
# * `options:` anything accepted by {KisHttp.Options}; appended to the url's
#   query string (merging with any query already present in the url).
#
# The url may be a `String` or a `URI`. Only `http` and `https` are supported.
# Userinfo in the url (`https://user:pass@host/`) is sent as HTTP Basic auth.
#
# @return [Net::HTTPResponse]
module KisHttp
  class Error < StandardError; end

  class << self
    def get(url, **kwargs)
      request(Net::HTTP::Get, url, **kwargs)
    end

    def head(url, **kwargs)
      request(Net::HTTP::Head, url, **kwargs)
    end

    def post(url, **kwargs)
      request(Net::HTTP::Post, url, **kwargs)
    end

    def put(url, **kwargs)
      request(Net::HTTP::Put, url, **kwargs)
    end

    def patch(url, **kwargs)
      request(Net::HTTP::Patch, url, **kwargs)
    end

    def delete(url, **kwargs)
      request(Net::HTTP::Delete, url, **kwargs)
    end

    private

    def request(request_class, url, body: nil, headers: nil, options: nil)
      uri = build_uri(url, options)

      request = request_class.new(uri.request_uri)
      request.basic_auth(unescape(uri.user), unescape(uri.password)) if uri.user
      KisHttp.Headers(headers).assign_each_to(request)
      assign_body(request, body)

      http = Net::HTTP.new(uri.hostname, uri.port)
      http.use_ssl = (uri.scheme == 'https')

      http.request(request)
    end

    # @return [URI::HTTP] a copy of the url with `options` merged into its query
    def build_uri(url, options)
      raise ArgumentError, 'url must not be nil or empty' if url.nil? || url.to_s.strip.empty?

      uri = url.is_a?(URI::Generic) ? url.dup : URI(url.to_s.strip)

      unless uri.is_a?(URI::HTTP)
        raise ArgumentError, "only http and https urls are supported, #{url.inspect} given"
      end
      raise ArgumentError, "url has no host, #{url.inspect} given" if uri.host.to_s.empty?

      query = KisHttp.Options(options).query
      uri.query = [uri.query, query].reject { |part| part.nil? || part.empty? }.join('&') unless query.empty?

      uri
    end

    def assign_body(request, body)
      case body
      when nil then nil
      when String then request.body = body
      when Hash, Array
        request.body = JSON.generate(body)
        request['Content-Type'] ||= 'application/json'
      else
        if body.respond_to?(:to_str)
          request.body = body.to_str
        else
          raise TypeError, "body must be a String, Hash or Array, #{body.class} given"
        end
      end
    end

    # Percent-decodes a userinfo component. Ruby 3.4 switched the default
    # parser to RFC 3986, so prefer the RFC 2396 parser that keeps `unescape`.
    def unescape(string)
      return nil unless string

      parser = defined?(URI::RFC2396_PARSER) ? URI::RFC2396_PARSER : URI::DEFAULT_PARSER
      parser.unescape(string)
    end
  end
end
