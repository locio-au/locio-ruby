# frozen_string_literal: true

module Locio
  # What the API said when it refused.
  #
  # The service answers RFC 7807 problem documents: a title and a detail
  # written for a person to read and act on, such as which key is wrong.
  # Collapsing that into "HTTP 403" throws away the only part of the answer
  # that says what to do about it.
  class Error < StandardError
    attr_reader :status, :title, :detail

    def initialize(status, title = "", detail = "")
      @status = status
      @title = title.to_s
      @detail = detail.to_s
      message = @title.empty? ? "HTTP #{status}" : @title
      message = "#{message}: #{@detail}" unless @detail.empty?
      super(message)
    end
  end

  # The key was refused: missing, revoked, or a public key used from an origin
  # its allow list does not name. The detail says which.
  class Unauthorized < Error; end

  # Nothing is filed under that id.
  class NotFound < Error; end

  # The request could not be served as written.
  class BadRequest < Error; end

  # Too many requests a second. Slow down and try again: nothing is spent.
  # A different problem from QuotaExhausted, with a different fix.
  class RateLimited < Error
    # Seconds the service asked for, when it said.
    attr_reader :retry_after

    def initialize(status, title = "", detail = "", retry_after: nil)
      super(status, title, detail)
      @retry_after = retry_after
    end
  end

  # Every unit in the period is spent. Retrying before +reset+ gets the same
  # answer; a larger plan at locio.com.au/account/ is the other way through.
  class QuotaExhausted < Error
    attr_reader :quota

    def initialize(status, title = "", detail = "", quota: nil)
      super(status, title, detail)
      @quota = quota
    end

    # When the allowance starts again.
    def reset = quota&.reset
  end

  # No answer arrived: the connection failed, timed out, or was cut off.
  class TransportError < Error
    def initialize(message)
      super(0, message)
    end
  end
end
