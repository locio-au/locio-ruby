# frozen_string_literal: true

require_relative "test_helper"

# Used with ActiveModel's validates_with, which needs only new(options) and
# validate(record); tested here with a record that has what ActiveModel gives.
class AddressValidatorTest < Minitest::Test
  MATCH = { "data" => { "matched" => true, "address" => { "id" => "GANSW1", "formatted" => "1 GEORGE ST", "lat" => 1, "lng" => 2 } } }.freeze

  class Errors
    attr_reader :added

    def initialize = @added = []
    def add(attribute, message, **) = @added << [attribute, message]
  end

  class Order
    attr_accessor :shipping_address, :address_id
    attr_reader :errors

    def initialize(address)
      @shipping_address = address
      @errors = Errors.new
    end
  end

  def validate(order, transport, **options)
    client = Locio::Client.new("lc_live_abc", transport: transport)
    Locio::AddressValidator.new({ attribute: :shipping_address, client: client }.merge(options)).validate(order)
    order.errors.added
  end

  def test_an_address_that_resolves_passes_and_its_id_is_stored
    t = FakeTransport.new(MATCH)
    order = Order.new("1 george st sydney")
    assert_equal [], validate(order, t, store: :address_id)
    assert_equal "1 george st sydney", t.query["q"]
    assert_equal "GANSW1", order.address_id
  end

  def test_an_address_that_does_not_resolve_fails
    added = validate(Order.new("1 nowhere st"), FakeTransport.new({ "data" => { "matched" => false, "address" => nil } }))
    assert_equal [[:shipping_address, "is not an address we can find"]], added
  end

  def test_nothing_is_spent_on_a_blank_address
    t = FakeTransport.new
    assert_equal 1, validate(Order.new("  "), t).size
    assert_equal 1, validate(Order.new(nil), t).size
    assert_empty t.calls
  end

  def test_an_outage_lets_the_record_through
    added = validate(Order.new("1 george st"), FakeTransport.new({ "title" => "too many requests" }, 429))
    assert_equal [], added
  end

  def test_strict_fails_on_an_outage
    added = validate(Order.new("1 george st"), FakeTransport.new({ "title" => "too many requests" }, 429), strict: true)
    assert_equal 1, added.size
  end

  def test_the_attribute_is_required
    assert_raises(ArgumentError) { Locio::AddressValidator.new({}) }
  end
end
