# frozen_string_literal: true

require_relative "test_helper"

class ClientTest < Minitest::Test
  KEY = "lc_live_0123456789abcdef"

  ADDRESS = {
    "id" => "GANSW705023327",
    "country_code" => "AU",
    "address_detail_pid" => "GANSW705023327",
    "formatted" => "1 GEORGE STREET, SYDNEY NSW 2000",
    "lat" => -33.8612,
    "lng" => 151.2104,
    "mesh_block" => "11205258900",
    "components" => { "number_first" => "1", "street_name" => "GEORGE", "street_type" => "STREET", "postcode" => "2000" },
    "gnaf" => { "primary_secondary" => "PRINCIPAL", "geocode_type" => "PROPERTY CENTROID" },
    "region" => "New South Wales",
    "locality" => "Sydney"
  }.freeze

  def client(transport, country: nil)
    Locio::Client.new(KEY, country: country, transport: transport)
  end

  def test_search_asks_for_the_term_and_returns_addresses
    t = FakeTransport.new({ "data" => [ADDRESS] })
    found = client(t).search("1 george st sydney")
    assert_equal "/v1/addresses", t.path
    assert_equal "1 george st sydney", t.query["q"]
    assert_equal 1, found.size
    assert_kind_of Locio::Address, found.first
    assert_equal "GANSW705023327", found.first.id
  end

  def test_the_limit_is_sent_and_a_zero_is_left_off
    t = FakeTransport.new
    client(t).search("1 george", limit: 5)
    assert_equal "5", t.query["limit"]
    client(t).search("1 george", limit: 0)
    refute t.query.key?("limit")
  end

  def test_an_empty_term_spends_nothing
    t = FakeTransport.new
    assert_equal [], client(t).search("   ")
    assert_equal [], client(t).similar("")
    assert_empty t.calls
  end

  def test_scoped_search_carries_the_country_and_the_note
    t = FakeTransport.new({ "data" => [], "country_code" => "NZ", "note" => "We hold no addresses for New Zealand yet." })
    scoped = client(t).search_scoped("1 queen st auckland")
    assert_equal [], scoped.addresses
    assert_equal "NZ", scoped.country_code
    assert_equal "We hold no addresses for New Zealand yet.", scoped.note
  end

  def test_the_chosen_country_is_sent_on_every_call
    t = FakeTransport.new({ "data" => [] })
    locio = client(t, country: "au")
    locio.search("1 george")
    assert_equal "AU", t.query["country"]
    locio.resolve("1 george st sydney")
    assert_equal "AU", t.query["country"]
  end

  def test_no_country_is_sent_when_none_was_chosen
    t = FakeTransport.new
    client(t).search("1 george")
    refute t.query.key?("country")
  end

  def test_a_country_must_be_two_letters
    %w[AUS Australia a A1].each do |country|
      err = assert_raises(ArgumentError) { client(FakeTransport.new, country: country) }
      assert_match(/two letter/, err.message)
    end
  end

  def test_get_reads_one_address
    t = FakeTransport.new({ "data" => ADDRESS })
    address = client(t).get("GANSW705023327")
    assert_equal "/v1/addresses/GANSW705023327", t.path
    assert_equal "1 GEORGE STREET, SYDNEY NSW 2000", address.formatted
  end

  def test_a_retired_id_is_nil_not_an_error
    assert_nil client(FakeTransport.new({ "title" => "not found" }, 404)).get("GANSW700000000")
  end

  def test_get_still_raises_for_any_other_failure
    assert_raises(Locio::Error) { client(FakeTransport.new({ "title" => "server error" }, 500)).get("GANSW705023327") }
  end

  def test_resolve_says_whether_it_matched
    t = FakeTransport.new({ "data" => { "matched" => true, "address" => ADDRESS } })
    res = client(t).resolve("1 george st sydney nsw 2000")
    assert_equal "/v1/addresses/resolve", t.path
    assert res.matched
    assert_equal "GANSW705023327", res.address.id
  end

  def test_resolve_without_data_is_not_matched
    res = client(FakeTransport.new({})).resolve("nowhere")
    refute res.matched
    assert_nil res.address
  end

  def test_similar_sends_the_limit
    t = FakeTransport.new({ "data" => [ADDRESS] })
    found = client(t).similar("1 gorge st sydnee", limit: 3)
    assert_equal "/v1/addresses/similar", t.path
    assert_equal "3", t.query["limit"]
    assert_equal 1, found.size
  end

  def test_the_address_carries_every_field
    a = Locio::Address.from_hash(ADDRESS)
    assert_equal "GANSW705023327", a.id
    assert_equal "AU", a.country_code
    assert_equal "GANSW705023327", a.address_detail_pid
    assert_equal(-33.8612, a.lat)
    assert_equal 151.2104, a.lng
    assert_equal "11205258900", a.mesh_block
    assert_equal "2000", a.components["postcode"]
    assert_equal "PROPERTY CENTROID", a.gnaf["geocode_type"]
    assert_equal "Sydney", a.locality
    assert_equal ADDRESS, a.raw
    refute a.unit?
    assert a.australian?
    assert a.frozen?
  end

  def test_the_id_falls_back_to_the_pid_for_an_older_service
    a = Locio::Address.from_hash({ "formatted" => "x", "lat" => 0, "lng" => 0, "gnaf_pid" => "GAVIC1" })
    assert_equal "GAVIC1", a.id
  end

  def test_a_unit_is_said_to_be_one
    a = Locio::Address.from_hash(ADDRESS.merge("gnaf" => { "primary_secondary" => "SECONDARY", "primary_pid" => "GAVIC9" }))
    assert a.unit?
  end

  def test_an_address_outside_australia_has_no_gnaf_fields
    a = Locio::Address.from_hash({ "id" => "us-123", "country_code" => "US", "formatted" => "1 Main St", "lat" => 40.0, "lng" => -74.0 })
    refute a.australian?
    assert_nil a.address_detail_pid
    assert_nil a.mesh_block
  end

  def test_errors_keep_the_services_own_words
    t = FakeTransport.new({ "title" => "bad key", "detail" => "That key was revoked on 3 September." }, 401)
    err = assert_raises(Locio::Unauthorized) { client(t).search("1 george") }
    assert_equal 401, err.status
    assert_equal "bad key", err.title
    assert_equal "That key was revoked on 3 September.", err.detail
    assert_equal "bad key: That key was revoked on 3 September.", err.message
  end

  def test_forbidden_is_a_key_problem_too
    assert_raises(Locio::Unauthorized) { client(FakeTransport.new({ "title" => "origin not allowed" }, 403)).search("1 george") }
  end

  def test_a_spent_quota_says_when_it_resets
    t = FakeTransport.new({ "title" => "quota exhausted" }, 402,
                          "X-Quota-Limit" => "10000", "X-Quota-Remaining" => "0", "X-Quota-Reset" => "2026-10-01T00:00:00Z")
    err = assert_raises(Locio::QuotaExhausted) { client(t).search("1 george") }
    assert_equal Time.utc(2026, 10, 1), err.reset
    assert_equal 10_000, err.quota.limit
    assert_equal 0, err.quota.remaining
  end

  def test_a_rate_limit_says_how_long_to_wait
    t = FakeTransport.new({ "title" => "too many requests" }, 429, "Retry-After" => "1")
    err = assert_raises(Locio::RateLimited) { client(t).search("1 george") }
    assert_equal 1, err.retry_after
    refute_kind_of Locio::QuotaExhausted, err
  end

  def test_retry_after_is_nil_when_not_said
    err = assert_raises(Locio::RateLimited) { client(FakeTransport.new({}, 429)).search("1 george") }
    assert_nil err.retry_after
  end

  def test_other_statuses_are_named
    assert_raises(Locio::NotFound) { client(FakeTransport.new({}, 404)).search("1 george") }
    assert_raises(Locio::BadRequest) { client(FakeTransport.new({}, 400)).search("1 george") }
  end

  def test_the_status_stands_when_the_body_is_not_a_problem_document
    err = assert_raises(Locio::Error) { client(FakeTransport.new("<html>bad gateway</html>", 502)).search("1 george") }
    assert_equal 502, err.status
    assert_equal "HTTP 502", err.message
  end

  def test_quota_is_unknown_until_a_call_answers
    assert_nil client(FakeTransport.new).quota
  end

  def test_quota_holds_the_latest_answer
    t = FakeTransport.new({ "data" => [] }, 200,
                          "X-Quota-Limit" => "10000", "X-Quota-Remaining" => "9876", "X-Quota-Reset" => "2026-10-01T00:00:00Z")
    locio = client(t)
    locio.search("1 george")
    assert_equal Locio::Quota.new(limit: 10_000, remaining: 9876, reset: Time.utc(2026, 10, 1)), locio.quota
  end

  def test_quota_is_kept_when_an_answer_carries_none
    t = FakeTransport.new({ "data" => [] }, 200,
                          "X-Quota-Limit" => "100", "X-Quota-Remaining" => "40", "X-Quota-Reset" => "2026-10-01T00:00:00Z")
    locio = client(t)
    locio.search("1 george")
    t.answer({ "data" => [] })
    locio.search("1 george")
    assert_equal 40, locio.quota.remaining
  end

  def test_quota_headers_that_do_not_parse_are_ignored
    t = FakeTransport.new({ "data" => [] }, 200, "X-Quota-Limit" => "lots", "X-Quota-Remaining" => "1", "X-Quota-Reset" => "soon")
    locio = client(t)
    locio.search("1 george")
    assert_nil locio.quota
  end

  def test_requests_identify_the_library
    t = FakeTransport.new
    client(t).search("1 george")
    assert_equal "locio-ruby/#{Locio::VERSION}", t.headers["User-Agent"]
    assert_equal "application/json", t.headers["Accept"]
  end
end
