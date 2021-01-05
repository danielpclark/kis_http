# frozen_string_literal: true

require 'net/http'
require 'kis_http/version'
require 'kis_http/headers'
require 'kis_http/options'

# All the HTTP things
module KisHttp
  class Error < StandardError; end

  class << self
    def get(url, **kwargs)
      request(url, **kwargs) do |uri|
        Net::HTTP::Get.new(uri)
      end
    end

    def post(url, **kwargs)
      request(url, **kwargs) do |uri|
        Net::HTTP::Post.new(uri)
      end
    end

    def put(url, **kwargs)
      request(url, **kwargs) do |uri|
        Net::HTTP::Put.new(uri)
      end
    end

    private

    def request(url, body: nil, headers: nil, options: nil)
      options = KisHttp.Options(options) if options

      uri = URI("#{url}#{options}")

      request = yield uri.request_uri

      KisHttp.Headers(headers).assign_each_to(request) if headers

      request.body = body

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')

      http.request(request)
    end
  end
end
