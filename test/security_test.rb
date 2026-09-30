# frozen_string_literal: true

require_relative "test_helper"
require "socket"

# The controls that stop this client leaking the key it carries.
#
# A secret key is a bearer credential: whoever holds it spends its quota. So
# the key travels only over https to the host the caller named, never in a
# URL, never through a redirect, never into a log line or an inspect, and
# nothing a caller hands in can reach a header or walk out of its path.
class SecurityTest < Minitest::Test
  KEY = "lc_live_0123456789abcdef"

  def test_a_key_is_required
    ["", "   ", nil].each do |key|
      err = assert_raises(ArgumentError) { Locio::Client.new(key, transport: FakeTransport.new) }
      assert_match(/no key/, err.message)
    end
  end

  def test_a_key_with_whitespace_or_a_control_character_is_refused
    ["lc_live_abc\r\nX-Evil: 1", "lc_live_abc\n", "lc_live abc", "lc_live_abc\0"].each do |key|
      err = assert_raises(ArgumentError) { Locio::Client.new(key, transport: FakeTransport.new) }
      assert_match(/key/, err.message)
      refute_includes err.message, "lc_live_abc"
    end
  end

  def test_the_key_does_not_show_when_the_client_is_inspected
    client = Locio::Client.new(KEY, transport: FakeTransport.new)
    refute_includes client.inspect, KEY
    refute_includes client.to_s, KEY
    refute_includes client.instance_variables.map { client.instance_variable_get(_1).inspect }.join, KEY
  end

  def test_the_default_is_https
    assert_equal "https://api.locio.com.au", Locio::DEFAULT_BASE_URL
  end

  def test_plaintext_http_to_a_public_host_is_refused
    err = assert_raises(ArgumentError) { Locio::Client.new(KEY, base_url: "http://api.locio.com.au") }
    assert_match(/clear/, err.message)
  end

  def test_loopback_over_http_is_allowed
    %w[http://localhost:8080 http://127.0.0.1:8080 http://[::1]:8080].each do |base_url|
      Locio::Client.new(KEY, base_url: base_url, transport: FakeTransport.new)
    end
    pass
  end

  def test_a_host_that_only_starts_like_loopback_is_refused
    %w[http://localhost.evil.example http://127.0.0.1.evil.example].each do |base_url|
      assert_raises(ArgumentError) { Locio::Client.new(KEY, base_url: base_url) }
    end
  end

  def test_bad_base_urls_are_refused
    [
      "ftp://api.locio.com.au", "file:///etc/passwd", "javascript:alert(1)", "", "api.locio.com.au", "/v1",
      "https://api.locio.com.au@evil.example", "https://user:pass@api.locio.com.au",
      "https://api.locio.com.au?x=1", "https://api.locio.com.au#x"
    ].each do |base_url|
      assert_raises(ArgumentError, base_url) { Locio::Client.new(KEY, base_url: base_url) }
    end
  end

  def test_every_request_goes_to_the_host_it_was_given
    t = FakeTransport.new({ "data" => nil })
    locio = Locio::Client.new(KEY, base_url: "https://proxy.example.com/locio/", transport: t)
    locio.search("1 george")
    locio.get("GANSW705023327")
    locio.resolve("1 george st")
    locio.similar("1 gorge st")
    t.calls.each do |call|
      assert_equal "proxy.example.com", URI(call[:url]).host
      assert URI(call[:url]).path.start_with?("/locio/v1/addresses"), call[:url]
    end
  end

  def test_the_key_travels_as_a_bearer_credential_and_nowhere_else
    t = FakeTransport.new
    Locio::Client.new(KEY, transport: t).search("1 george")
    assert_equal "Bearer #{KEY}", t.headers["Authorization"]
    refute_includes t.url, KEY
    refute t.headers.key?("Cookie")
  end

  def test_an_id_cannot_walk_out_of_its_path
    t = FakeTransport.new({ "data" => nil })
    locio = Locio::Client.new(KEY, transport: t)
    ["../keys", "..%2Fkeys", "a/b", "x?limit=1000", "x#frag"].each do |id|
      locio.get(id)
      uri = URI(t.url)
      segments = uri.path.split("/", -1)
      assert_equal ["", "v1", "addresses"], segments.first(3)
      assert_equal 4, segments.size, uri.path
      assert_nil uri.query
      assert_nil uri.fragment
    end
  end

  def test_an_id_naming_the_collection_or_its_parent_is_refused
    locio = Locio::Client.new(KEY, transport: FakeTransport.new)
    ["", "  ", ".", ".."].each do |id|
      err = assert_raises(ArgumentError) { locio.get(id) }
      assert_match(/id/, err.message)
    end
  end

  def test_a_term_cannot_inject_another_parameter
    t = FakeTransport.new
    Locio::Client.new(KEY, transport: t).search("1 george&country=NZ&limit=1000")
    assert_equal "1 george&country=NZ&limit=1000", t.query["q"]
    refute t.query.key?("country")
    refute t.query.key?("limit")
  end

  def test_a_negative_limit_is_refused
    err = assert_raises(ArgumentError) { Locio::Client.new(KEY, transport: FakeTransport.new).search("1 george", limit: -1) }
    assert_match(/limit/, err.message)
  end

  def test_a_body_that_is_not_an_object_survives
    ["null", "42", '"text"', "[1,2]", ""].each do |body|
      assert_equal [], Locio::Client.new(KEY, transport: FakeTransport.new(body)).search("1 george")
    end
  end

  def test_a_problem_document_does_not_decide_whether_it_failed
    t = FakeTransport.new({ "data" => [], "title" => "error", "status" => 500 }, 200)
    assert_equal [], Locio::Client.new(KEY, transport: t).search("1 george")
  end

  def test_an_error_does_not_repeat_the_key
    t = FakeTransport.new({ "title" => "bad key" }, 401)
    err = assert_raises(Locio::Error) { Locio::Client.new(KEY, transport: t).search("1 george") }
    refute_includes err.message, KEY
    refute_includes err.inspect, KEY
  end

  # The transport, against a real socket.

  class TinyServer
    attr_reader :port, :seen

    def initialize
      @server = TCPServer.new("127.0.0.1", 0)
      @port = @server.addr[1]
      @seen = []
      @thread = Thread.new { loop { handle(@server.accept) } rescue nil }
    end

    def stop
      @thread.kill
      @server.close
    end

    private

    def handle(socket)
      line = socket.gets.to_s
      headers = {}
      while (h = socket.gets) && h != "\r\n"
        name, value = h.split(":", 2)
        headers[name.downcase] = value.to_s.strip
      end
      path = line.split(" ")[1].to_s
      @seen << path
      case path
      when %r{\A/redirect/} then reply(socket, 302, "", "Location" => "/target")
      when %r{\A/huge/} then reply(socket, 200, %({"data":[],"pad":"#{"x" * (9 * 1024 * 1024)}"}))
      when %r{\A/echo/} then reply(socket, 200, JSON.generate({ "data" => [], "note" => headers["authorization"] }))
      else reply(socket, 200, '{"data":[]}')
      end
    ensure
      socket.close
    end

    def reply(socket, status, body, extra = {})
      socket.write "HTTP/1.1 #{status} X\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n"
      extra.each { |k, v| socket.write "#{k}: #{v}\r\n" }
      socket.write "\r\n#{body}"
    rescue Errno::EPIPE, Errno::ECONNRESET
      nil
    end
  end

  def setup
    @server = TinyServer.new
    @origin = "http://127.0.0.1:#{@server.port}"
  end

  def teardown
    @server.stop
  end

  def transport = Locio::NetHTTPTransport.new(timeout: 5)

  def test_the_transport_does_not_follow_a_redirect
    locio = Locio::Client.new(KEY, base_url: "#{@origin}/redirect", transport: transport)
    err = assert_raises(Locio::Error) { locio.search("1 george") }
    assert_equal 302, err.status
    refute_includes @server.seen, "/target"
  end

  def test_the_transport_caps_the_body
    locio = Locio::Client.new(KEY, base_url: "#{@origin}/huge", transport: transport)
    assert_raises(Locio::TransportError) { locio.search("1 george") }
  end

  def test_the_transport_speaks_only_http
    assert_raises(Locio::TransportError) { transport.call("file:///etc/passwd", {}) }
    assert_raises(Locio::TransportError) { transport.call("ftp://example.com/x", {}) }
  end

  def test_the_transport_sends_the_headers_it_was_given
    locio = Locio::Client.new(KEY, base_url: "#{@origin}/echo", transport: transport)
    assert_equal "Bearer #{KEY}", locio.search_scoped("1 george").note
  end

  def test_the_transport_reports_a_connection_that_fails
    probe = TCPServer.new("127.0.0.1", 0)
    port = probe.addr[1]
    probe.close
    assert_raises(Locio::TransportError) { transport.call("http://127.0.0.1:#{port}/v1/addresses", {}) }
  end
end
