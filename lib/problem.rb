# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

require "problem/version"
require "problem/document"
require "problem/details"
require "problem/detailable"
require "problem/retry_after"
require "problem/rescuable"

# RFC 9457 Problem Details for HTTP APIs.
module Problem
  # Anything a deployment sets once, rather than per error class.
  class Configuration
    # Resolves a declared type slug into the URI a client dispatches on, so an error class
    # names `"bad-request"` instead of repeating the deployment's authority. Left unset,
    # a slug goes out as-is, which RFC 9457 allows: `type` is a URI reference.
    attr_accessor :type_prefix #: String?
  end

  # A URI reference carrying a scheme is already absolute (RFC 3986 §3.1).
  ABSOLUTE_URI = /\A[a-zA-Z][a-zA-Z0-9+.\-]*:/ #: Regexp

  # @rbs self.@config: Configuration?

  # The settings in effect, created on first use.
  #: () -> Configuration
  def self.config
    @config ||= Configuration.new
  end

  # Yields the settings, for a host that is not a Rails application.
  #
  #   Problem.configure { |c| c.type_prefix = "https://api-probs.example.com/" }
  #
  #: () { (Configuration) -> void } -> void
  def self.configure
    yield(config)
  end

  # Registers the application/problem+json media type and the `problem:` renderer. Called
  # by Problem::Railtie on boot; a Rack host or a spec that never boots Rails calls it.
  #: () -> void
  def self.install!
    require "problem/renderer"
    Renderer.install!
  end

  # The type URI a declared value publishes. `about:blank` and anything already absolute
  # are returned untouched — prefixing `about:blank` would produce a URI that looks valid
  # and means nothing.
  #: (String?, ?prefix: String?) -> String?
  def self.type_uri(value, prefix: config.type_prefix)
    return if value.nil?
    return value if value == Document::ABOUT_BLANK || value.match?(ABSOLUTE_URI)

    prefix ? "#{prefix}#{value}" : value
  end
end

require "problem/railtie" if defined?(Rails::Railtie)
