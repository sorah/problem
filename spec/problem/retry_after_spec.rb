# frozen_string_literal: true

RSpec.describe(Problem::RetryAfter) do
  let(:throttled) do
    Class.new(StandardError) do
      include Problem::Detailable
      include Problem::RetryAfter

      type "too-many-requests"
      status 429
      title "Try again in %{retry_after} seconds"
    end
  end

  it "publishes the wait as an extension member" do
    expect(throttled.new(retry_after: 30).to_problem.to_h[:retry_after]).to eq(30)
  end

  it "publishes the wait as a Retry-After header" do
    expect(throttled.new(retry_after: 30).problem_headers).to eq({"Retry-After" => "30"})
  end

  it "interpolates the wait into the title" do
    expect(throttled.new(retry_after: 30).to_problem.title).to eq("Try again in 30 seconds")
  end

  it "accepts a Time and publishes the seconds remaining" do
    error = throttled.new(retry_after: Time.now + 45)

    expect(error.retry_after_seconds).to be_within(1).of(45)
  end

  it "publishes 0 rather than a negative wait for a deadline already passed" do
    expect(throttled.new(retry_after: Time.now - 10).retry_after_seconds).to eq(0)
  end

  it "keeps the detail keyword working alongside its own" do
    expect(throttled.new(retry_after: 5, detail: "ip throttled").detail).to eq("ip throttled")
  end

  # Every hook calls super, so a second mixin's contributions survive.
  it "composes with another mixin rather than clobbering it" do
    tracked = Module.new do
      def problem_extensions = super.merge(request_id: "abc123")
    end
    klass = Class.new(throttled) { include tracked }

    expect(klass.new(retry_after: 5).problem_extensions)
      .to eq({retry_after: 5, request_id: "abc123"})
  end
end
