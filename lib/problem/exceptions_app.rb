# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

require "action_dispatch"
require "action_dispatch/middleware/exception_wrapper"
require "problem/detailable"
require "problem/details"

module Problem
  # Answers an exception that escaped the controller — a routing error, an unreadable
  # body, a failure in middleware — as application/problem+json. Nothing else sees those:
  # they are raised before dispatch, so no controller rescue_from ever runs.
  #
  #   config.exceptions_app = Problem::ExceptionsApp.new(
  #     ActionDispatch::PublicExceptions.new(Rails.public_path),
  #   )
  #
  # A wrapper rather than an ActionDispatch::PublicExceptions subclass, so each layer of a
  # deployment's stack claims the requests it recognizes and passes on the rest; a
  # subclass can only ever be the innermost one.
  class ExceptionsApp
    # Wraps the exceptions app to fall back to, which keeps whatever it already answers
    # for the requests this one does not claim.
    #: (untyped app) -> void
    def initialize(app)
      @app = app
    end

    # Answers with a problem document, or hands the request to the wrapped app.
    #: (Hash[String, untyped]) -> [Integer, Hash[String, String], Array[String]]
    def call(env)
      exception = env["action_dispatch.exception"]
      return @app.call(env) if exception.nil? || html?(env)

      render_problem(problem_for(exception, env))
    end

    # Browser traffic keeps getting the wrapped app's static error pages.
    #: (Hash[String, untyped]) -> bool
    private def html?(env)
      ActionDispatch::Request.new(env).formats.first&.html? || false
    rescue ActionDispatch::Http::MimeNegotiation::InvalidType
      false
    end

    # The problem to send for an escaped exception. The title is the status's own text,
    # never the exception's message, which can quote internals.
    #
    # Override to publish a type: a deployment with a catalogue of problems maps the
    # status onto it here, so every identifier a client can see comes from one place.
    #: (Exception, Hash[String, untyped]) -> Details
    private def problem_for(exception, env)
      return exception.to_problem if exception.is_a?(Detailable)

      # Read the way ActionDispatch::PublicExceptions reads it, so `rescue_responses` stays
      # the one place the application classifies an exception.
      status = ActionDispatch::ExceptionWrapper.new(
        env["action_dispatch.backtrace_cleaner"], exception
      ).status_code

      Details.new(status: status, title: Rack::Utils::HTTP_STATUS_CODES.fetch(status, "Error"))
    end

    #: (Details) -> [Integer, Hash[String, String], Array[String]]
    private def render_problem(problem)
      body = problem.to_json

      [
        problem.status,
        {"content-type" => Document::CONTENT_TYPE, "content-length" => body.bytesize.to_s},
        [body],
      ]
    end
  end
end
