# frozen_string_literal: true

# Locio: Australian addresses from G-NAF, as autocomplete, validation and
# geocoding. See Locio::Client.
module Locio
end

require_relative "locio/version"
require_relative "locio/errors"
require_relative "locio/types"
require_relative "locio/net_http_transport"
require_relative "locio/client"
require_relative "locio/address_validator"
