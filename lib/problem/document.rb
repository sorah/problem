# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

require "json"

module Problem
  # Serializes an RFC 9457 problem document.
  #
  # Included by Problem::Details, and by any value object that carries the same readers —
  # the way to add typed members is to define a Data over Problem::Details.members rather
  # than to subclass Details, which cannot gain members.
  #
  # @rbs module-self _Document
  module Document
    # The members RFC 9457 §3.1 defines, in the order they are serialized.
    MEMBERS = %i[type title status detail instance].freeze #: Array[Symbol]

    # The type of a problem that says nothing beyond its HTTP status (RFC 9457 §4.2.1).
    ABOUT_BLANK = "about:blank" #: String

    # The media type a problem document is served as (RFC 9457 §3).
    CONTENT_TYPE = "application/problem+json" #: String

    # Extension members are members of the problem object itself, not a nested container,
    # so they merge at the top level. An absent member is omitted rather than sent as null.
    #: () -> Hash[Symbol, untyped]
    def to_h
      {
        type: type || ABOUT_BLANK,
        title: title,
        status: status,
        detail: detail,
        instance: instance,
      }.reject { |_, value| value.nil? || value == "" }.merge(extensions)
    end

    # The document with string keys, so a member whose value knows how to render itself
    # gets the chance before JSON.generate sees it.
    #: (?untyped) -> Hash[String, untyped]
    def as_json(options = nil)
      to_h.to_h { |key, value| [key.to_s, value.respond_to?(:as_json) ? value.as_json(options) : value] }
    end

    # Defined explicitly because the generic Object#to_json would serialize the Data's
    # inspect output, which looks like a response body until someone reads one.
    #: (*untyped) -> String
    def to_json(*) = JSON.generate(as_json)
  end
end
