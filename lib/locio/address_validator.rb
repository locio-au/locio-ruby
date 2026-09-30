# frozen_string_literal: true

module Locio
  # Fails a model attribute that is not a real address, for ActiveModel:
  #
  #   class Order < ApplicationRecord
  #     validates_with Locio::AddressValidator, attribute: :shipping_address, store: :address_id
  #   end
  #
  # ActiveModel needs only new(options) and validate(record), so this loads
  # without it. One unit per record checked.
  #
  # attribute: - the attribute holding the address as one line (required)
  # store:     - an attribute to write the resolved id to, when it matches
  # strict:    - fail when Locio cannot answer; by default the record passes,
  #              because an outage of ours should not stop somebody checking out
  # client:    - a Locio::Client; by default one built from ENV["LOCIO_KEY"]
  #              and ENV["LOCIO_COUNTRY"]
  class AddressValidator
    NOT_FOUND = "is not an address we can find"
    UNCHECKED = "could not be checked just now, please try again"

    def initialize(options = {})
      @attribute = options[:attribute] or raise ArgumentError, "Locio::AddressValidator needs attribute:"
      @store = options[:store]
      @strict = options.fetch(:strict, false)
      @client = options[:client]
    end

    def validate(record)
      value = record.public_send(@attribute)
      if !value.is_a?(String) || value.strip.empty?
        record.errors.add(@attribute, NOT_FOUND)
        return
      end

      resolution = begin
        client.resolve(value)
      rescue Error
        record.errors.add(@attribute, UNCHECKED) if @strict
        return
      end

      unless resolution.matched && resolution.address
        record.errors.add(@attribute, NOT_FOUND)
        return
      end
      record.public_send(:"#{@store}=", resolution.address.id) if @store && record.respond_to?(:"#{@store}=")
    end

    private

    def client
      @client ||= Client.new(ENV.fetch("LOCIO_KEY", ""), country: ENV["LOCIO_COUNTRY"])
    end
  end
end
