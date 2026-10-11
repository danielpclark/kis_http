# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'kis_http'
require 'minitest/autorun'
require 'socket'
require 'json'
require 'timeout'

# net/http warns (under -w) whenever a POST/PUT/PATCH is sent without a
# Content-Type header, even when no body was given, because it substitutes an
# empty form-encoded body. That is upstream behaviour, not something this
# library controls, so keep it out of the test output.
module SilenceNetHttpContentTypeWarning
  def warn(message, *args, **kwargs)
    return if message.to_s.include?('net/http: Content-Type did not set')

    super
  end
end
Warning.extend SilenceNetHttpContentTypeWarning if defined?(Warning) && Warning.respond_to?(:warn)

begin
  require 'minitest/reporters'
  require 'color_pound_spec_reporter'
  # color_pound_spec_reporter refers to the `MiniTest` alias that minitest
  # dropped in 5.19, so restore it for the reporter's benefit.
  MiniTest = Minitest unless defined?(MiniTest)
  Minitest::Reporters.use! [ColorPoundSpecReporter.new]
rescue LoadError
  # fall back to the default minitest reporter
end

# A minimal HTTP/1.1 server that records every request it receives and
# answers with a JSON description of it. One request per connection.
#
# A request to `/status/<code>` is answered with that status code.
class EchoServer
  Request = Struct.new(:method, :target, :headers, :body) do
    # @return [String] the request path without the query string
    def path
      target.split('?', 2).first
    end

    # @return [String, nil] the raw query string
    def query
      target.split('?', 2)[1]
    end
  end

  attr_reader :port, :host, :requests

  def initialize(host = '127.0.0.1')
    @host = host
    @server = TCPServer.new(host, 0)
    @port = @server.addr[1]
    @requests = Queue.new
    @thread = Thread.new { serve }
    @thread.abort_on_exception = true
  end

  # @return [String] an absolute http url for `path` on this server
  def url(path = '/')
    authority = host.include?(':') ? "[#{host}]" : host
    "http://#{authority}:#{port}#{path}"
  end

  # @return [Request] the next recorded request (fails if none arrives)
  def last_request
    Timeout.timeout(5) { requests.pop }
  rescue Timeout::Error
    raise 'no request received within 5 seconds'
  end

  def shutdown
    @thread.kill
    @server.close
  end

  private

  def serve
    loop do
      socket = @server.accept
      Thread.new { handle(socket) }
    end
  rescue IOError
    # server closed
  end

  def handle(socket)
    request = read_request(socket) or return
    requests << request

    code = request.path[%r{\A/status/(\d{3})\z}, 1] || '200'
    payload = JSON.generate(
      method: request.method, path: request.path, query: request.query,
      headers: request.headers, body: request.body
    )

    socket.write "HTTP/1.1 #{code} Status\r\n" \
                 "Content-Type: application/json\r\n" \
                 "Content-Length: #{payload.bytesize}\r\n" \
                 "Connection: close\r\n\r\n"
    socket.write payload unless request.method == 'HEAD'
  ensure
    socket.close
  end

  def read_request(socket)
    line = socket.gets or return nil
    method, target, = line.split(' ', 3)

    headers = {}
    while (header = socket.gets) && header != "\r\n"
      name, value = header.chomp.split(':', 2)
      headers[name.downcase] = value.to_s.strip
    end

    length = headers['content-length'].to_i
    # Socket reads come back as binary; tag the bytes as UTF-8 so JSON on
    # older Rubies does not refuse to transcode non-ASCII bodies.
    body = length.positive? ? socket.read(length).force_encoding(Encoding::UTF_8) : ''

    Request.new(method, target, headers, body)
  end
end
