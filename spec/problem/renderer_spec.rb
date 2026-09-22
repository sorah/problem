# frozen_string_literal: true

# Named rather than anonymous: ActionController::Metal.action needs a controller_name.
class RendererTestController < ActionController::API
  def problem_details
    render problem: Problem::Details.new(type: "bad-request", title: "Bad Request", status: 400)
  end

  def overridden_status
    render problem: Problem::Details.new(status: 400), status: 418
  end

  # A deployment's own serializer: the renderer never requires a Problem::Details.
  def custom_serializer
    shape = Data.define(:status) do
      def to_json(*) = %({"type":"custom","status":#{status}})
    end

    render problem: shape.new(status: 503)
  end
end

RSpec.describe(Problem::Renderer) do
  it "registers the application/problem+json media type" do
    expect(Mime[:problem].to_s).to eq("application/problem+json")
  end

  it "can be installed twice without re-registering the media type" do
    expect { described_class.install! }.not_to(change { Mime[:problem].to_s })
  end

  it "renders the document with the media type and the problem's own status" do
    result = call_action(RendererTestController, :problem_details)

    expect(result.status).to eq(400)
    expect(result.content_type).to include("application/problem+json")
    expect(result.json).to eq({"type" => "bad-request", "title" => "Bad Request", "status" => 400})
  end

  it "lets an explicit status option win over the problem's" do
    expect(call_action(RendererTestController, :overridden_status).status).to eq(418)
  end

  it "renders any object answering #status and #to_json" do
    result = call_action(RendererTestController, :custom_serializer)

    expect(result.status).to eq(503)
    expect(result.json).to eq({"type" => "custom", "status" => 503})
  end
end
