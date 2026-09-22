# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

require "problem/detailable"

module Problem
  # Publishes when a rejected request may be retried, as a Retry-After response header
  # (RFC 9110 §10.2.3) and a `retry_after` extension member carrying the same seconds.
  #
  # Mixed in after Problem::Detailable, whose hooks it extends rather than replaces:
  #
  #   class Throttled < StandardError
  #     include Problem::Detailable
  #     include Problem::RetryAfter
  #
  #     status 429
  #     title "Try again in %{retry_after} seconds"
  #   end
  #
  #   raise Throttled.new(retry_after: 30)
  #
  # @rbs module-self Detailable
  module RetryAfter
    # The response header the wait is published in.
    HEADER = "Retry-After" #: String

    # Seconds to wait, or the Time to wait until.
    attr_reader :retry_after #: (Integer | Time)

    # Takes the wait as seconds or as the Time to wait until, and forwards the rest.
    #: (*untyped, retry_after: (Integer | Time), **untyped) -> void
    def initialize(*args, retry_after:, **kwargs)
      @retry_after = retry_after #: (Integer | Time)
      super(*args, **kwargs)
    end

    # A deadline that has already passed is published as 0 rather than as a negative wait.
    #: () -> Integer
    def retry_after_seconds
      value = retry_after
      value.is_a?(Time) ? [(value - Time.now).ceil, 0].max : value.to_i
    end

    # Adds the wait, so a title template can name it.
    #: () -> Hash[Symbol, untyped]
    def title_interpolations = super.merge(retry_after: retry_after_seconds)

    # Publishes the wait in the document as a `retry_after` extension member.
    #: () -> Hash[Symbol, untyped]
    def problem_extensions = super.merge(retry_after: retry_after_seconds)

    # Publishes the wait as a Retry-After header, which a generic HTTP client obeys.
    #: () -> Hash[String, String]
    def problem_headers = super.merge(HEADER => retry_after_seconds.to_s)
  end
end
