# frozen_string_literal: true

module RescuableProblems
  class Forbidden < StandardError
    include Problem::Detailable

    type "forbidden"
    status 403
    title "Forbidden"
  end

  class NotFound < StandardError
    include Problem::Detailable

    type "not-found"
    status 404
    title "Not Found"
  end

  # Renders exactly as Forbidden: a subclass that declares nothing must stay
  # indistinguishable to a probing caller.
  class AlsoForbidden < Forbidden; end

  class Unavailable < StandardError
    include Problem::Detailable

    type "service-unavailable"
    status 503
    title "Service Unavailable"
  end

  class Throttled < StandardError
    include Problem::Detailable
    include Problem::RetryAfter

    type "too-many-requests"
    status 429
    title "Too Many Requests"
  end
end

class RescuableTestController < ActionController::API
  include Problem::Rescuable

  def forbidden = raise(RescuableProblems::Forbidden.new(detail: "you cannot see this"))
  def not_found = raise(RescuableProblems::NotFound)
  def also_forbidden = raise(RescuableProblems::AlsoForbidden)
  def unavailable = raise(RescuableProblems::Unavailable)
  def throttled = raise(RescuableProblems::Throttled.new(retry_after: 30))
  def unhandled = raise(ArgumentError, "not a problem")
end

RSpec.describe(Problem::Rescuable) do
  it "renders a raised problem as application/problem+json" do
    result = call_action(RescuableTestController, :forbidden)

    expect(result.status).to eq(403)
    expect(result.content_type).to include("application/problem+json")
    expect(result.json).to eq({
      "type" => "forbidden",
      "title" => "Forbidden",
      "status" => 403,
      "detail" => "you cannot see this",
    })
  end

  it "omits detail when the occurrence carries none" do
    expect(call_action(RescuableTestController, :not_found).json).not_to have_key("detail")
  end

  it "renders a subclass that declares nothing as its superclass" do
    forbidden = call_action(RescuableTestController, :forbidden).json
    subclass = call_action(RescuableTestController, :also_forbidden).json

    expect(subclass["type"]).to eq(forbidden["type"])
    expect(subclass["title"]).to eq(forbidden["title"])
  end

  it "sends the headers the occurrence asks for" do
    result = call_action(RescuableTestController, :throttled)

    expect(result.headers["Retry-After"]).to eq("30")
    expect(result.json["retry_after"]).to eq(30)
  end

  # The blast radius of `rescue_from Problem::Detailable` stops at the concern.
  it "lets an exception that is not a problem propagate" do
    expect { call_action(RescuableTestController, :unhandled) }
      .to raise_error(ArgumentError, "not a problem")
  end

  describe "error reporting" do
    def reported_during(action)
      reports = []
      subscriber = Class.new do
        define_method(:report) { |error, **| reports << error }
      end.new

      ActiveSupport.error_reporter.subscribe(subscriber)
      call_action(RescuableTestController, action)
      reports
    ensure
      ActiveSupport.error_reporter.unsubscribe(subscriber)
    end

    it "reports a 5xx problem, which a rescue_from handler would otherwise swallow" do
      expect(reported_during(:unavailable).map(&:class)).to eq([RescuableProblems::Unavailable])
    end

    it "does not report a 4xx problem, which is an expected client error" do
      expect(reported_during(:forbidden)).to be_empty
    end
  end

  describe "the hooks" do
    it "lets #problem_for fill members only the request can supply" do
      controller = Class.new(RescuableTestController) do
        def self.controller_name = "instanced"

        private def problem_for(error)
          error.to_problem.with(instance: request.fullpath)
        end
      end

      expect(call_action(controller, :forbidden, path: "/orders/1").json["instance"])
        .to eq("/orders/1")
    end

    # The wrapper has to cover #problem_for, not just the render: a locale established
    # here is what the title lookup inside it reads.
    it "wraps building the problem as well as rendering it" do
      observed = []
      controller = Class.new(RescuableTestController) do
        def self.controller_name = "wrapped"

        cattr_accessor :observations

        private def around_problem_render
          observations << :before
          yield
          observations << :after
        end

        private def problem_for(error)
          observations << :problem_for
          super
        end
      end
      controller.observations = observed

      call_action(controller, :forbidden)

      expect(observed).to eq([:before, :problem_for, :after])
    end

    it "lets #report_problem? move the threshold" do
      reports = []
      subscriber = Class.new { define_method(:report) { |error, **| reports << error } }.new
      controller = Class.new(RescuableTestController) do
        def self.controller_name = "chatty"

        private def report_problem?(_error, _problem) = true
      end

      ActiveSupport.error_reporter.subscribe(subscriber)
      call_action(controller, :forbidden)

      expect(reports.map(&:class)).to eq([RescuableProblems::Forbidden])
    ensure
      ActiveSupport.error_reporter.unsubscribe(subscriber)
    end

    # What a different transport overrides: the document is built and reported the same
    # way, and only the response differs.
    it "lets #render_problem answer in another shape entirely" do
      controller = Class.new(RescuableTestController) do
        def self.controller_name = "coded"

        private def render_problem(problem, _error)
          render(json: {code: "permission_denied", message: problem.title}, status: 400)
        end
      end

      result = call_action(controller, :forbidden)

      expect(result.status).to eq(400)
      expect(result.json).to eq({"code" => "permission_denied", "message" => "Forbidden"})
    end
  end
end
