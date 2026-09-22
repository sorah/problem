# frozen_string_literal: true

RSpec.describe(Problem::Detailable) do
  let(:bad_request) do
    Class.new(StandardError) do
      include Problem::Detailable

      type "bad-request"
      status 400
      title "Bad Request"
    end
  end

  # Declares nothing of its own: it must stay indistinguishable from its superclass, which
  # is how a deployment keeps a probing caller from telling two errors apart.
  let(:silent_subclass) { Class.new(bad_request) }

  let(:forbidden_subclass) do
    Class.new(bad_request) do
      type "forbidden"
      status 403
      title "Forbidden"
    end
  end

  describe "the class DSL" do
    it "reads back what the class declared" do
      expect(bad_request.type).to eq("bad-request")
      expect(bad_request.status).to eq(400)
      expect(bad_request.title).to eq("Bad Request")
    end

    it "is nil for a class that declares nothing" do
      undeclared = Class.new(StandardError) { include Problem::Detailable }

      expect(undeclared.type).to be_nil
      expect(undeclared.status).to be_nil
      expect(undeclared.title).to be_nil
    end

    it "follows the subclass declaration when it overrides" do
      expect(forbidden_subclass.type).to eq("forbidden")
      expect(forbidden_subclass.status).to eq(403)
    end

    it "inherits the superclass declaration when the subclass overrides nothing" do
      expect(silent_subclass.type).to eq("bad-request")
      expect(silent_subclass.status).to eq(400)
    end

    it "does not leak a subclass declaration back to the superclass" do
      forbidden_subclass

      expect(bad_request.status).to eq(400)
    end

    it "interpolates a literal title when the occurrence supplies values" do
      throttled = Class.new(StandardError) do
        include Problem::Detailable

        status 429
        title "Try again in %{wait} seconds"
      end

      expect(throttled.title(interpolations: {wait: 30})).to eq("Try again in 30 seconds")
    end

    it "leaves a title containing a stray format sequence alone when nothing interpolates" do
      literal = Class.new(StandardError) do
        include Problem::Detailable

        status 400
        title "100%{ of the time"
      end

      expect(literal.title).to eq("100%{ of the time")
    end
  end

  describe "#initialize" do
    it "reads back the detail" do
      expect(bad_request.new(detail: "name is required").detail).to eq("name is required")
    end

    it "defaults detail to nil" do
      expect(bad_request.new.detail).to be_nil
    end

    # `raise Klass, "boom"` has to keep working: the concern intercepts only `detail:`.
    it "forwards a positional message to the exception" do
      expect(bad_request.new("boom", detail: "x").message).to eq("boom")
    end
  end

  describe "#to_problem" do
    it "maps the declaration onto an RFC 9457 document" do
      problem = bad_request.new(detail: "name is required").to_problem

      expect(problem).to be_a(Problem::Details)
      expect(problem.type).to eq("bad-request")
      expect(problem.title).to eq("Bad Request")
      expect(problem.status).to eq(400)
      expect(problem.detail).to eq("name is required")
    end

    it "renders a subclass that declares nothing identically to its superclass" do
      expect(silent_subclass.new.to_problem).to eq(bad_request.new.to_problem)
    end

    it "resolves the type against the class's own prefix" do
      prefixed = Class.new(bad_request) { type_prefix "https://example.com/problems/" }

      expect(prefixed.new.to_problem.type).to eq("https://example.com/problems/bad-request")
    end

    it "resolves the type against the configured prefix when the class declares none" do
      Problem.configure { |c| c.type_prefix = "https://example.com/problems/" }

      expect(bad_request.new.to_problem.type).to eq("https://example.com/problems/bad-request")
    ensure
      Problem.config.type_prefix = nil
    end

    it "carries the occurrence's extension members" do
      throttled = Class.new(StandardError) do
        include Problem::Detailable

        status 429
        def problem_extensions = {retry_after: 30}
      end

      expect(throttled.new.to_problem.to_h[:retry_after]).to eq(30)
    end

    it "carries the occurrence's instance" do
      located = Class.new(bad_request) do
        def problem_instance = "/orders/1"
      end

      expect(located.new.to_problem.instance).to eq("/orders/1")
    end

    it "refuses a class that declares no status, naming the class" do
      undeclared = Class.new(StandardError) { include Problem::Detailable }

      expect { undeclared.new.to_problem }.to raise_error(ArgumentError, /declares no problem status/)
    end
  end

  describe "rescuing" do
    # One `rescue_from Problem::Detailable` covers every class that mixed the concern in,
    # because a Module is matched with ===.
    it "is rescuable through the concern itself" do
      rescued = begin
        raise bad_request.new(detail: "boom")
      rescue Problem::Detailable => e
        e
      end

      expect(rescued.to_problem.detail).to eq("boom")
    end
  end
end
