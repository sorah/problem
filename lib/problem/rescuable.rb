# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

require "active_support"
require "active_support/concern"
require "problem/detailable"

module Problem
  # Renders any Problem::Detailable a controller raises as application/problem+json.
  #
  #   class ApplicationController < ActionController::API
  #     include Problem::Rescuable
  #   end
  #
  # One registration covers every error class that mixed Problem::Detailable in, because
  # rescue_from matches a Module with ===.
  #
  # Each step is its own method, so a deployment overrides the one it needs and a
  # different transport — a Connect RPC error, say — replaces only #render_problem.
  #
  # @rbs module-self _RescuableSelf
  module Rescuable
    extend ActiveSupport::Concern

    # steep:ignore:start
    included do
      rescue_from Problem::Detailable, with: :render_problem_detailable
    end
    # steep:ignore:end

    #: (detailable_error) -> void
    private def render_problem_detailable(error)
      around_problem_render do
        problem = problem_for(error)
        report_problem(error, problem) if report_problem?(error, problem)
        apply_problem_headers(error)
        render_problem(problem, error)
      end
    end

    # Wraps building, reporting and rendering. Override to re-establish per-request state
    # that has already unwound: ActionController::Rescue wraps
    # AbstractController::Callbacks, so an around_action is gone by the time a rescue_from
    # handler runs, and #problem_for may read a translation.
    #
    #   private def around_problem_render(&) = I18n.with_locale(negotiated_locale, &)
    #
    #: () { () -> void } -> void
    private def around_problem_render = yield

    # Override to fill members only the request can supply, such as `instance`.
    #: (detailable_error) -> Details
    private def problem_for(error) = error.to_problem

    # A client error the API expected is not an incident; a server-side failure is.
    #: (detailable_error, Details) -> bool
    private def report_problem?(_error, problem) = problem.status >= 500

    # A rescue_from handler swallows the exception, so nothing logs it and no error
    # reporter sees it. Reported through the registry Rails error reporters subscribe to,
    # rather than to a particular one.
    #: (detailable_error, Details) -> void
    private def report_problem(error, _problem)
      ActiveSupport.error_reporter.report(error, handled: true, severity: :error, source: "problem")
    end

    #: (detailable_error) -> void
    private def apply_problem_headers(error)
      headers = error.problem_headers
      response.headers.merge!(headers) unless headers.empty?
    end

    # The only transport-specific step.
    #: (Details, detailable_error) -> void
    private def render_problem(problem, _error) = render(problem: problem)
  end
end
