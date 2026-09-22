# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

require "active_support/concern"
require "active_support/core_ext/class/attribute"
require "problem/details"

module Problem
  # Declares an exception class as an RFC 9457 problem.
  #
  #   class InsufficientBalance < StandardError
  #     include Problem::Detailable
  #
  #     type "insufficient-balance"
  #     status 403
  #     title "Insufficient Balance"
  #   end
  #
  #   raise InsufficientBalance.new(detail: "Required: 100, Available: 50")
  #
  # This holds only what RFC 9457 defines: a type, a title, a status, a per-occurrence
  # detail, and the conversion to Problem::Details. Each is declared literally, which is
  # all a deployment needs to render an error.
  #
  # A deployment that keeps a catalogue of its problems — a registry, an enum, a locale
  # file — derives those three from it instead, by prepending a module to the error
  # class's singleton that overrides `type`, `status` and `title` and calls `super` for a
  # class the catalogue does not cover. Three things make that work and none of them are
  # visible at the call site: ClassMethods is attached with `extend`, so a singleton
  # prepend sits ahead of it; the gem never defines those three on the including class
  # itself; and #to_problem reaches them through `self.class` rather than reading the
  # class attributes behind them.
  #
  # @rbs module-self ::Exception
  # @rbs module-self _DetailableSelf
  module Detailable
    extend ActiveSupport::Concern

    # The occurrence's own explanation, which RFC 9457 §3.1 defines as specific to this
    # occurrence rather than to the problem type.
    attr_reader :detail #: String?

    # `self` inside an ActiveSupport::Concern block is the including class, which RBS has
    # no way to name; the accessors these install are declared in sig/manual instead.
    # steep:ignore:start
    included do
      class_attribute :problem_status, instance_accessor: false
      class_attribute :problem_title, instance_accessor: false
      class_attribute :problem_uri, instance_accessor: false
      class_attribute :problem_type_prefix, instance_accessor: false
    end
    # steep:ignore:end

    # Extended into the including class by ActiveSupport::Concern, which picks up a nested
    # ClassMethods by name. Written as a module rather than a `class_methods` block so the
    # body is ordinary code that RBS can describe.
    #
    # @rbs module-self _DetailableClass
    module ClassMethods
      # Each reader doubles as its own setter so a subclass can override one declaration
      # and inherit the rest, which is what class_attribute buys over a constant.
      #: (?Integer?) -> Integer?
      def status(value = nil)
        value ? self.problem_status = value : problem_status
      end

      # The identifier this class publishes, resolved against the type prefix when the
      # occurrence is converted.
      #: (?String?) -> String?
      def type(value = nil)
        value ? self.problem_uri = value : problem_uri
      end

      # `interpolations` is part of the signature even though a literal title rarely needs
      # it: a catalogue-backed override reads a template, and this is where the occurrence
      # hands it the values.
      #: (?String?, ?interpolations: Hash[Symbol, untyped]) -> String?
      def title(value = nil, interpolations: {})
        return self.problem_title = value if value

        template = problem_title
        return template if template.nil? || interpolations.empty?

        template % interpolations
      end

      # Falls back to the global setting, so a deployment declares its authority once.
      #: (?String?) -> String?
      def type_prefix(value = nil)
        return self.problem_type_prefix = value if value

        problem_type_prefix || Problem.config.type_prefix
      end
    end

    # Intercepts `detail:` and forwards everything else to the exception, so
    # `raise Klass, "message"` keeps working.
    #: (*untyped, ?detail: String?, **untyped) -> void
    def initialize(*args, detail: nil, **kwargs)
      @detail = detail #: String?
      super(*args, **kwargs)
    end

    # Values the title template interpolates for this occurrence.
    #: () -> Hash[Symbol, untyped]
    def title_interpolations = {}

    # Extension members this occurrence publishes alongside the RFC 9457 ones.
    #: () -> Hash[Symbol, untyped]
    def problem_extensions = {}

    # A URI identifying this occurrence, which only the caller's request can supply.
    #: () -> String?
    def problem_instance = nil

    # Response headers this occurrence needs, applied by Problem::Rescuable.
    #: () -> Hash[String, String]
    def problem_headers = {}

    # This occurrence as an RFC 9457 document.
    #: () -> Details
    def to_problem
      status = self.class.status
      raise ArgumentError, "#{self.class} declares no problem status" if status.nil?

      Details.new(
        type: Problem.type_uri(self.class.type, prefix: self.class.type_prefix),
        title: self.class.title(interpolations: title_interpolations),
        status: status,
        detail: detail,
        instance: problem_instance,
        extensions: problem_extensions,
      )
    end
  end
end
