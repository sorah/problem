# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

require "i18n"
require "active_support/concern"
require "problem/detailable"

module Problem
  # Looks a problem's title up through I18n instead of declaring it in Ruby.
  #
  #   class ApiError < StandardError
  #     include Problem::I18nable
  #   end
  #
  #   class NotFound < ApiError
  #     type "not-found"
  #     status 404
  #   end
  #
  #   en:
  #     problem_details:
  #       titles:
  #         not_found: "Not Found"
  #
  # Titles are keyed by the declared type, dashes replaced, so two classes publishing one
  # type publish one title as well. That is what keeps a subclass written to be
  # indistinguishable from its parent indistinguishable in the title too.
  #
  # A class that declares a literal title keeps it, so a codebase can move over gradually.
  #
  # i18n is not a declared dependency of this gem. Referencing this module is opting in,
  # and it is autoloaded so that a host which never does pays nothing for it.
  #
  # @rbs module-self ::Exception
  # @rbs module-self _DetailableSelf
  module I18nable
    extend ActiveSupport::Concern

    # Brings the DSL this overrides, and orders the two so `super` reaches it whichever
    # way round a class mixes them in.
    include Detailable

    # Where titles live unless a class says otherwise.
    DEFAULT_SCOPE = "problem_details.titles" #: String

    # steep:ignore:start
    included do
      class_attribute :problem_title_scope, instance_accessor: false
      class_attribute :problem_title_key, instance_accessor: false
    end
    # steep:ignore:end

    # @rbs module-self _I18nableClass
    module ClassMethods
      # The I18n scope titles are looked up under.
      #: (?String?) -> String
      def title_scope(value = nil)
        return self.problem_title_scope = value if value

        problem_title_scope || DEFAULT_SCOPE
      end

      # The key within that scope, derived from the declared type unless it is set.
      #: (?(String | Symbol)?) -> String?
      def title_key(value = nil)
        return self.problem_title_key = value.to_s if value

        problem_title_key || type&.tr("-", "_")
      end

      # Falls through to the literal DSL for a class that declares a title of its own, or
      # that has no type to build a key from.
      #: (?String?, ?interpolations: Hash[Symbol, untyped]) -> String?
      def title(value = nil, interpolations: {})
        return super if value || problem_title

        key = title_key
        return super if key.nil?

        I18n.t(key, scope: title_scope, **interpolations)
      end
    end
  end
end
