# frozen_string_literal: true

RSpec.describe("Problem.type_uri") do
  it "returns nil for a problem that declares no type" do
    expect(Problem.type_uri(nil, prefix: "https://example.com/problems/")).to be_nil
  end

  it "leaves about:blank alone, rather than prefixing it into a plausible nonsense URI" do
    expect(Problem.type_uri("about:blank", prefix: "https://example.com/problems/"))
      .to eq("about:blank")
  end

  it "leaves an absolute URI alone" do
    expect(Problem.type_uri("https://other.example/problems/x", prefix: "https://example.com/problems/"))
      .to eq("https://other.example/problems/x")
  end

  it "resolves a slug against the prefix" do
    expect(Problem.type_uri("bad-request", prefix: "https://example.com/problems/"))
      .to eq("https://example.com/problems/bad-request")
  end

  it "leaves a slug as a relative reference when no prefix is configured" do
    expect(Problem.type_uri("bad-request", prefix: nil)).to eq("bad-request")
  end

  it "falls back to the configured prefix" do
    Problem.configure { |c| c.type_prefix = "https://example.com/problems/" }

    expect(Problem.type_uri("not-found")).to eq("https://example.com/problems/not-found")
  ensure
    Problem.config.type_prefix = nil
  end
end
