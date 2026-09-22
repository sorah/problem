# frozen_string_literal: true

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

require "problem/document"

module Problem
  # The members of an RFC 9457 problem document, plus the extension members a problem
  # adds to them. Behaviour is defined on the reopening below.
  Details = Data.define(:type, :title, :status, :detail, :instance, :extensions)

  # An RFC 9457 problem document as a value object.
  #
  # `type` is stored verbatim: resolving a declared slug against a prefix is
  # Problem::Detailable's job, so a Details built by hand is never rewritten.
  #
  # Reopened rather than customized in a `Data.define` block, so the body is an ordinary
  # class body that RBS can describe and Steep can check.
  class Details
    include Document

    # `status` is required and must be the HTTP status of the response carrying it;
    # every other member is optional, and `extensions` holds the members RFC 9457 §3.2
    # lets a problem add.
    #: (status: Integer, ?type: String?, ?title: String?, ?detail: String?, ?instance: String?, ?extensions: Hash[untyped, untyped]) -> void
    def initialize(status:, type: nil, title: nil, detail: nil, instance: nil, extensions: {})
      raise ArgumentError, "status must be an Integer, got #{status.class}" unless status.is_a?(Integer)

      super(type:, title:, status:, detail:, instance:, extensions: sanitized_extensions(extensions))
    end

    # An extension that shadowed `status` would contradict the HTTP status in the same
    # response, so a collision is refused here rather than at render time.
    private def sanitized_extensions(extensions)
      sanitized = extensions.to_h { |key, value| [key.to_sym, value] }
      collisions = sanitized.keys & Document::MEMBERS

      unless collisions.empty?
        raise ArgumentError, "extension members shadow RFC 9457 members: #{collisions.join(", ")}"
      end

      sanitized.freeze
    end
  end
end
