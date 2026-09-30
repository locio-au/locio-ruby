# frozen_string_literal: true

module Locio
  # A value that says [REDACTED] however it is printed, inspected or
  # interpolated, so a key held in one never reaches a log line or an error
  # tracker's dump of instance variables. Only +reveal+ gives it back.
  class Secret
    def initialize(value) = @value = value.dup.freeze
    def reveal = @value
    def inspect = "[REDACTED]"
    alias to_s inspect
    def instance_variables = []
  end

  # What came back: the status, the headers with lower case names, and the body.
  Response = Data.define(:status, :headers, :body) do
    def header(name) = headers[name.downcase]
  end

  # The allowance a key's account has left, as the service reported it.
  Quota = Data.define(:limit, :remaining, :reset)

  # The answer to a validation call. +matched+ false is an answer, not an
  # error: the address as written is not in the register.
  Resolution = Data.define(:matched, :address)

  # Addresses, and what the service said about the country it searched. A
  # country the service holds no addresses for answers none and a note saying
  # why, as an ordinary answer that costs nothing.
  ScopedAddresses = Data.define(:addresses, :country_code, :note)

  # One resolved address, from whichever register covers it.
  #
  # The G-NAF fields are Australian: another country's register publishes no
  # pid, mesh block or parcel, so they are nil outside Australia and
  # +country_code+ says which case you are in. Component and G-NAF values are
  # carried as the register publishes them, upper case included.
  Address = Data.define(
    :id, :formatted, :lat, :lng, :country_code, :address_detail_pid, :mesh_block,
    :components, :gnaf, :country, :region, :locality, :raw
  ) do
    def self.from_hash(row)
      text = lambda do |key|
        value = row[key]
        value.nil? || value.is_a?(Hash) || value.is_a?(Array) || value.to_s.empty? ? nil : value.to_s
      end
      strings = lambda do |key|
        value = row[key]
        value.is_a?(Hash) ? value.to_h { |k, v| [k.to_s, v.to_s] }.freeze : {}.freeze
      end
      number = ->(key) { row[key].is_a?(Numeric) ? row[key].to_f : 0.0 }

      new(
        # Every address carries id; a service too old to send it carried the
        # Australian pid instead, under one name or the other.
        id: text["id"] || text["address_detail_pid"] || text["gnaf_pid"] || "",
        formatted: text["formatted"] || "",
        lat: number["lat"],
        lng: number["lng"],
        country_code: text["country_code"],
        address_detail_pid: text["address_detail_pid"] || text["gnaf_pid"],
        mesh_block: text["mesh_block"],
        components: strings["components"],
        gnaf: strings["gnaf"],
        country: text["country"],
        region: text["region"],
        locality: text["locality"],
        raw: row.dup.freeze
      )
    end

    def australian? = country_code.nil? || country_code == "AU"

    # Whether this is a unit under a parcel, in which case gnaf["primary_pid"]
    # names the parcel rather than this address. Storing that instead of +id+
    # stores the building rather than the door.
    def unit? = gnaf["primary_secondary"].to_s.upcase == "SECONDARY"
  end
end
