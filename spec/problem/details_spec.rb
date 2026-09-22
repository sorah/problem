# frozen_string_literal: true

RSpec.describe(Problem::Details) do
  describe ".new" do
    it "stores the type verbatim, without resolving it against anything" do
      expect(described_class.new(type: "bad-request", status: 400).type).to eq("bad-request")
    end

    it "defaults the optional members to nil" do
      problem = described_class.new(status: 500)

      expect(problem.type).to be_nil
      expect(problem.title).to be_nil
      expect(problem.detail).to be_nil
      expect(problem.instance).to be_nil
      expect(problem.extensions).to eq({})
    end

    it "rejects a status that is not an Integer" do
      expect { described_class.new(status: "400") }
        .to raise_error(ArgumentError, /status must be an Integer/)
    end

    it "symbolizes extension keys so a string-keyed hash serializes the same way" do
      problem = described_class.new(status: 429, extensions: {"retry_after" => 30})

      expect(problem.extensions).to eq({retry_after: 30})
    end

    it "refuses an extension that shadows an RFC 9457 member" do
      expect { described_class.new(status: 400, extensions: {status: 500}) }
        .to raise_error(ArgumentError, /shadow RFC 9457 members: status/)
    end
  end

  describe "immutability" do
    let(:problem) { described_class.new(status: 403, title: "Forbidden") }

    it "is frozen" do
      expect(problem).to be_frozen
    end

    it "compares equal to another instance with the same members" do
      expect(problem).to eq(described_class.new(status: 403, title: "Forbidden"))
    end
  end

  describe "#to_h" do
    it "renders about:blank for a problem that declares no type" do
      expect(described_class.new(status: 500).type).to be_nil
      expect(described_class.new(status: 500).to_h[:type]).to eq("about:blank")
    end

    it "omits detail and instance when they are absent" do
      hash = described_class.new(type: "not-found", title: "Not Found", status: 404).to_h

      expect(hash).to eq({type: "not-found", title: "Not Found", status: 404})
      expect(hash).not_to have_key(:detail)
      expect(hash).not_to have_key(:instance)
    end

    it "omits an empty detail, which is absent rather than blank" do
      expect(described_class.new(status: 404, detail: "").to_h).not_to have_key(:detail)
    end

    it "includes detail and instance when they are set" do
      hash = described_class.new(status: 404, detail: "no such user", instance: "/users/1").to_h

      expect(hash[:detail]).to eq("no such user")
      expect(hash[:instance]).to eq("/users/1")
    end

    it "merges extension members at the top level rather than nesting them" do
      hash = described_class.new(status: 429, extensions: {retry_after: 30}).to_h

      expect(hash).to eq({type: "about:blank", status: 429, retry_after: 30})
      expect(hash).not_to have_key(:extensions)
    end
  end

  describe "#to_json" do
    it "serializes the document rather than the Data's inspect output" do
      json = described_class.new(type: "bad-request", title: "Bad Request", status: 400).to_json

      expect(JSON.parse(json)).to eq({"type" => "bad-request", "title" => "Bad Request", "status" => 400})
    end

    it "carries extension members" do
      json = described_class.new(status: 429, extensions: {retry_after: 30}).to_json

      expect(JSON.parse(json)["retry_after"]).to eq(30)
    end
  end

  # The documented way to add a typed member: a Data cannot gain one by subclassing.
  describe "a value object built over the member list" do
    let(:traced_problem) do
      Data.define(*described_class.members, :trace_id) do
        include Problem::Document

        def to_h = super.merge(trace_id:)
      end
    end

    it "serializes the base members plus its own" do
      problem = traced_problem.new(
        type: "bad-request", title: "Bad Request", status: 400,
        detail: nil, instance: nil, extensions: {}, trace_id: "abc123"
      )

      expect(problem.to_h).to eq({type: "bad-request", title: "Bad Request", status: 400, trace_id: "abc123"})
    end
  end
end
