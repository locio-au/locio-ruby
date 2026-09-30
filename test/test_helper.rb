# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "locio"
require "minitest/autorun"
require "json"
require "uri"

# Answers every request with one canned response, and remembers what was asked.
class FakeTransport
  attr_reader :calls

  def initialize(body = { "data" => [] }, status = 200, headers = {})
    @calls = []
    answer(body, status, headers)
  end

  def answer(body, status = 200, headers = {})
    @body = body
    @status = status
    @headers = headers.transform_keys(&:downcase)
  end

  def call(url, headers)
    @calls << { url: url, headers: headers }
    text = @body.is_a?(String) ? @body : JSON.generate(@body)
    Locio::Response.new(status: @status, headers: @headers, body: text)
  end

  def url = @calls.last[:url]
  def path = URI(url).path
  def headers = @calls.last[:headers]

  def query
    q = URI(url).query
    q ? URI.decode_www_form(q).to_h : {}
  end
end
