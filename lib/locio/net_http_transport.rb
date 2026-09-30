# frozen_string_literal: true

require "net/http"
require "openssl"
require "uri"

module Locio
  # The default transport, on net/http.
  #
  # Never follows a redirect, since a redirect would carry the Authorization
  # header to wherever it points. Speaks only http and https, verifies TLS,
  # and stops reading at 8 MiB: a client should not be talked into reading an
  # unbounded body by whatever is on the other end of the socket.
  #
  # Any object with call(url, headers) returning a Locio::Response can stand
  # in for this one: Faraday, HTTPX, or a test double.
  class NetHTTPTransport
    MAX_BODY = 8 * 1024 * 1024

    def initialize(timeout: 15, open_timeout: 5)
      @timeout = timeout
      @open_timeout = open_timeout
    end

    def call(url, headers)
      uri = URI(url)
      raise TransportError, "locio: refusing to fetch a #{uri.scheme || "relative"} URL" unless uri.is_a?(URI::HTTP)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.open_timeout = @open_timeout
      http.read_timeout = @timeout
      http.write_timeout = @timeout

      request = Net::HTTP::Get.new(uri)
      headers.each { |name, value| request[name] = value }

      http.start do
        http.request(request) do |response|
          return Response.new(status: response.code.to_i, headers: headers_of(response), body: read(response))
        end
      end
    rescue TransportError
      raise
    rescue StandardError => e
      raise TransportError, "locio: request failed: #{e.class}: #{e.message}"
    end

    private

    def headers_of(response)
      response.each_header.to_h { |name, value| [name.downcase, value] }
    end

    def read(response)
      body = +""
      response.read_body do |chunk|
        body << chunk
        raise TransportError, "locio: the response was larger than 8 MiB, and was not read" if body.bytesize > MAX_BODY
      end
      body
    end
  end
end
