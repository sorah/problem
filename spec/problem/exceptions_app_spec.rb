# frozen_string_literal: true

class EscapedProblem < StandardError
  include Problem::Detailable

  type "gone"
  status 410
  title "Gone"
end

RSpec.describe(Problem::ExceptionsApp) do
  # Stands in for the application's own exceptions app, e.g.
  # ActionDispatch::PublicExceptions.
  let(:wrapped) do
    ->(_env) { [500, {"content-type" => "text/html"}, ["<html>the wrapped app</html>"]] }
  end
  let(:app) { described_class.new(wrapped) }

  def call(exception, accept: "application/json", status: 500)
    env = Rack::MockRequest.env_for("/orders/1", "HTTP_ACCEPT" => accept)
    env["action_dispatch.exception"] = exception
    env["action_dispatch.request.parameters"] = {}
    env["PATH_INFO"] = "/#{status}"

    code, headers, body = app.call(env)
    [code, headers, body.join]
  end

  it "passes a request carrying no exception to the wrapped app" do
    env = Rack::MockRequest.env_for("/orders/1")

    expect(app.call(env)).to eq(wrapped.call(env))
  end

  it "passes a browser request to the wrapped app, which owns the error pages" do
    _, _, body = call(ArgumentError.new("boom"), accept: "text/html")

    expect(body).to eq("<html>the wrapped app</html>")
  end

  it "answers a non-browser request as application/problem+json" do
    status, headers, body = call(ArgumentError.new("boom"))

    expect(status).to eq(500)
    expect(headers["content-type"]).to eq("application/problem+json")
    expect(headers["content-length"]).to eq(body.bytesize.to_s)
    expect(JSON.parse(body)).to eq({"type" => "about:blank", "title" => "Internal Server Error", "status" => 500})
  end

  # A message can quote an id, a column name, a file path.
  it "publishes the status text rather than the exception's message" do
    _, _, body = call(ArgumentError.new("secret internal detail"))

    expect(body).not_to include("secret internal detail")
  end

  it "maps a status through rescue_responses, the way PublicExceptions does" do
    status, _, body = call(ActionController::BadRequest.new)

    expect(status).to eq(400)
    expect(JSON.parse(body)).to include({"title" => "Bad Request", "status" => 400})
  end

  it "renders an escaped problem under its own declaration" do
    status, _, body = call(EscapedProblem.new(detail: "it was deleted"))

    expect(status).to eq(410)
    expect(JSON.parse(body))
      .to eq({"type" => "gone", "title" => "Gone", "status" => 410, "detail" => "it was deleted"})
  end

  it "lets #problem_for publish a type from a catalogue" do
    catalogued = Class.new(described_class) do
      private def problem_for(exception, env)
        super.with(type: "https://example.com/problems/internal-server-error")
      end
    end
    env = Rack::MockRequest.env_for("/orders/1", "HTTP_ACCEPT" => "application/json")
    env["action_dispatch.exception"] = ArgumentError.new("boom")

    _, _, body = catalogued.new(wrapped).call(env)

    expect(JSON.parse(body.join)["type"]).to eq("https://example.com/problems/internal-server-error")
  end

  # Each layer claims what it recognizes; a subclass of PublicExceptions could not sit
  # in the middle of a chain like this.
  it "stacks under another wrapper" do
    outer = Class.new do
      def initialize(app) = @app = app

      def call(env)
        return [418, {"content-type" => "text/plain"}, ["claimed"]] if env["HTTP_X_CLAIM"]

        @app.call(env)
      end
    end
    env = Rack::MockRequest.env_for("/orders/1", "HTTP_ACCEPT" => "application/json", "HTTP_X_CLAIM" => "1")
    env["action_dispatch.exception"] = ArgumentError.new("boom")

    status, _, body = outer.new(app).call(env)

    expect(status).to eq(418)
    expect(body.join).to eq("claimed")
  end
end
