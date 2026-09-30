# frozen_string_literal: true

require "json"
require "time"
require "uri"

module Locio
  DEFAULT_BASE_URL = "https://api.locio.com.au"

  # A client for the Locio address API: G-NAF, as autocomplete, validation and
  # geocoding.
  #
  #   locio = Locio::Client.new(ENV.fetch("LOCIO_KEY"), country: "AU")
  #   res = locio.resolve("1 george st sydney nsw 2000")
  #
  # Takes a secret key (lc_live_...), which belongs on a server. Make one
  # client and keep it; it holds no connection between calls.
  #
  # Addresses come from G-NAF, (c) Geoscape Australia, under CC BY 4.0.
  # Publishing what you get back means carrying that credit: locio.com.au/legal/.
  class Client
    LOOPBACK = %w[localhost 127.0.0.1 ::1 [::1]].freeze

    # The allowance as the most recent answer reported it, or nil until a
    # metered call answers.
    attr_reader :quota

    # key       - a secret key (lc_live_...) from locio.com.au/account/api
    # country:  - the register to search, as a two letter ISO 3166-1 code. A
    #             request from your server says nothing about where the
    #             address is, so say. nil sends nothing and the service's
    #             default applies, which is AU.
    # base_url: - a proxy of your own, or a test server. https, or http to loopback.
    # transport: - your own HTTP stack; anything with call(url, headers).
    def initialize(key, country: nil, base_url: DEFAULT_BASE_URL, transport: nil)
      @key = Secret.new(check_key(key))
      @base_url = check_base_url(base_url.to_s)
      @country = check_country(country)
      @transport = transport || NetHTTPTransport.new
      @quota = nil
    end

    # Never the key: an inspected client ends up in logs and error trackers.
    def inspect = "#<Locio::Client base_url=#{@base_url.inspect} country=#{@country.inspect}>"
    alias to_s inspect

    # Candidate addresses for what somebody has typed: address autocomplete.
    # One unit a call. An empty term answers [] without a request. A limit of
    # 0 takes the service's default.
    def search(term, limit: 0) = search_scoped(term, limit: limit).addresses

    # The same call, with the country it searched and any note about it.
    def search_scoped(term, limit: 0) = list("/v1/addresses", term, limit)

    # One address by its id: the +id+ of a record you stored, which in
    # Australia is the G-NAF Address Detail PID. nil when the id is not in the
    # current release: G-NAF retires ids between quarterly releases.
    def get(id)
      text = id.to_s.strip
      # "." or ".." as a path segment is the collection or its parent.
      raise ArgumentError, "locio: #{id.inspect} is not an address id" if text.empty? || %w[. ..].include?(text)

      body = call("/v1/addresses/#{URI.encode_uri_component(text)}", {})
      body["data"].is_a?(Hash) ? Address.from_hash(body["data"]) : nil
    rescue NotFound
      nil
    end

    # A whole address string to one record: address validation, geocoding and
    # parsing in the same answer. Write the address however you hold it.
    def resolve(address)
      body = call("/v1/addresses/resolve", { "q" => address.to_s })
      data = body["data"].is_a?(Hash) ? body["data"] : {}
      Resolution.new(
        matched: data["matched"] == true,
        address: data["address"].is_a?(Hash) ? Address.from_hash(data["address"]) : nil
      )
    end

    # Near misses for an address that did not resolve. Three units, so call it
    # once on a failed resolve, never on a keystroke.
    def similar(address, limit: 0) = similar_scoped(address, limit: limit).addresses

    # The same call, with the country it searched and any note about it.
    def similar_scoped(address, limit: 0) = list("/v1/addresses/similar", address, limit)

    private

    def list(path, term, limit)
      q = term.to_s.strip
      return ScopedAddresses.new(addresses: [], country_code: nil, note: nil) if q.empty?
      raise ArgumentError, "locio: limit must be a whole number, not #{limit.inspect}" unless limit.is_a?(Integer) && limit >= 0

      params = { "q" => q }
      params["limit"] = limit.to_s if limit.positive?
      body = call(path, params)
      rows = body["data"].is_a?(Array) ? body["data"] : []
      ScopedAddresses.new(
        addresses: rows.grep(Hash).map { Address.from_hash(_1) },
        country_code: body["country_code"].is_a?(String) ? body["country_code"] : nil,
        note: body["note"].is_a?(String) ? body["note"] : nil
      )
    end

    def call(path, params)
      # Every address call is scoped to one country.
      params = params.merge("country" => @country) if @country
      url = @base_url + path
      url += "?#{URI.encode_www_form(params).gsub("+", "%20")}" unless params.empty?

      response = @transport.call(url, {
        "Authorization" => "Bearer #{@key.reveal}",
        "Accept" => "application/json",
        "User-Agent" => "locio-ruby/#{VERSION}"
      })

      quota = read_quota(response)
      @quota = quota if quota

      # A problem document is JSON; a proxy having a bad day is not. Either way
      # the status is the part a caller can act on, so parsing never decides
      # whether an error is raised.
      decoded = begin
        JSON.parse(response.body.to_s)
      rescue JSON::ParserError
        nil
      end
      body = decoded.is_a?(Hash) ? decoded : {}

      raise error_for(response, body, quota) unless (200..299).cover?(response.status)

      body
    end

    def error_for(response, body, quota)
      status = response.status
      title = body["title"].is_a?(String) ? body["title"] : ""
      detail = body["detail"].is_a?(String) ? body["detail"] : ""
      case status
      when 401, 403 then Unauthorized.new(status, title, detail)
      when 402 then QuotaExhausted.new(status, title, detail, quota: quota)
      when 404 then NotFound.new(status, title, detail)
      when 429 then RateLimited.new(status, title, detail, retry_after: retry_after(response))
      when 400..499 then BadRequest.new(status, title, detail)
      else Error.new(status, title, detail)
      end
    end

    def retry_after(response)
      value = response.header("Retry-After").to_s
      value.match?(/\A\d+\z/) && value.to_i.positive? ? value.to_i : nil
    end

    # The allowance from the X-Quota-* headers, or nil when any is missing or malformed.
    def read_quota(response)
      limit = response.header("X-Quota-Limit").to_s
      remaining = response.header("X-Quota-Remaining").to_s
      reset = response.header("X-Quota-Reset").to_s
      return nil unless limit.match?(/\A\d+\z/) && remaining.match?(/\A\d+\z/)

      Quota.new(limit: limit.to_i, remaining: remaining.to_i, reset: Time.iso8601(reset).utc)
    rescue ArgumentError
      nil
    end

    def check_key(key)
      key = key.to_s
      if key.strip.empty?
        raise ArgumentError, "locio: no key. Create a secret key (lc_live_...) at https://locio.com.au/account/api"
      end
      # A header value, so a newline in it would be a header the caller did
      # not write. Keys never contain whitespace, so any is a paste gone wrong.
      # The message never repeats the key: it ends up in logs.
      if key.match?(/[[:space:]]|[[:cntrl:]]/)
        raise ArgumentError, "locio: the key contains whitespace or a control character; check how it was pasted"
      end

      key
    end

    def check_country(country)
      return nil if country.nil?

      code = country.to_s.strip.upcase
      raise ArgumentError, "locio: country #{country} is not a two letter ISO 3166-1 code" unless code.match?(/\A[A-Z]{2}\z/)

      code
    end

    # Refuse a base URL that would send the key somewhere it should not go:
    # https always, and plaintext http only to loopback.
    def check_base_url(raw)
      uri = begin
        URI.parse(raw)
      rescue URI::InvalidURIError
        nil
      end
      raise ArgumentError, "locio: base URL #{raw} is not absolute" unless uri.is_a?(URI::Generic) && uri.scheme && uri.host && !uri.host.empty?
      if uri.userinfo
        raise ArgumentError, "locio: base URL #{raw} carries credentials, and the host it would reach is not the one it reads as"
      end
      raise ArgumentError, "locio: base URL #{raw} has a query or a fragment, which would swallow the path" if raw.match?(/[?#]/)

      scheme = uri.scheme.downcase
      return raw.sub(%r{/+\z}, "") if scheme == "https" || (scheme == "http" && LOOPBACK.include?(uri.host.downcase))
      raise ArgumentError, "locio: base URL #{raw} is plaintext http to a public host, which would send the key in the clear" if scheme == "http"

      raise ArgumentError, "locio: base URL #{raw} has scheme #{scheme}, want https"
    end
  end
end
