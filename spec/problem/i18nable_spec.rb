# frozen_string_literal: true

require "i18n"

RSpec.describe(Problem::I18nable) do
  before do
    I18n.available_locales = [:en, :ja]
    I18n.default_locale = :en
    I18n.backend = I18n::Backend::Simple.new
    I18n.backend.store_translations(:en, problem_details: {
      titles: {not_found: "Not Found", throttled: "Try again in %{wait} seconds"},
    })
    I18n.backend.store_translations(:ja, problem_details: {titles: {not_found: "見つかりません"}})
  end

  let(:base) { Class.new(StandardError) { include Problem::I18nable } }

  let(:not_found) do
    Class.new(base) do
      type "not-found"
      status 404
    end
  end

  it "brings Problem::Detailable with it, so one include is enough" do
    expect(base.ancestors).to include(Problem::Detailable)
  end

  it "looks the title up from the declared type" do
    expect(not_found.title).to eq("Not Found")
  end

  it "follows the locale in effect when the problem is built" do
    expect(I18n.with_locale(:ja) { not_found.new.to_problem.title }).to eq("見つかりません")
  end

  it "renders through #to_problem" do
    expect(not_found.new(detail: "no such order").to_problem.to_h)
      .to eq({type: "not-found", title: "Not Found", status: 404, detail: "no such order"})
  end

  # A codebase moving over to I18n keeps the classes it has not moved yet.
  it "leaves a class that declares a literal title alone" do
    literal = Class.new(base) do
      type "spelled-out"
      status 400
      title "Spelled Out"
    end

    expect(literal.title).to eq("Spelled Out")
  end

  it "falls through when the class declares no type to build a key from" do
    typeless = Class.new(base) { status 500 }

    expect(typeless.title).to be_nil
  end

  it "passes the occurrence's interpolations through" do
    throttled = Class.new(base) do
      type "throttled"
      status 429

      def title_interpolations = {wait: 30}
    end

    expect(throttled.new.to_problem.title).to eq("Try again in 30 seconds")
  end

  describe "keys and scopes" do
    it "keys by the declared type with dashes replaced" do
      expect(not_found.title_key).to eq("not_found")
    end

    it "gives two classes publishing one type the same title" do
      indistinguishable = Class.new(not_found)

      expect(indistinguishable.title).to eq(not_found.title)
    end

    it "takes an explicit key" do
      renamed = Class.new(base) do
        type "gone-missing"
        status 404
        title_key :not_found
      end

      expect(renamed.title).to eq("Not Found")
    end

    it "takes a scope, inherited by subclasses" do
      I18n.backend.store_translations(:en, errors: {titles: {not_found: "Nope"}})
      scoped = Class.new(base) { title_scope "errors.titles" }
      subclass = Class.new(scoped) do
        type "not-found"
        status 404
      end

      expect(subclass.title).to eq("Nope")
    end

    it "defaults the scope to problem_details.titles" do
      expect(base.title_scope).to eq("problem_details.titles")
    end
  end

  # Whichever way round they are mixed in, the lookup has to win over the literal DSL.
  it "works when Problem::Detailable is included explicitly too" do
    both = Class.new(StandardError) do
      include Problem::Detailable
      include Problem::I18nable

      type "not-found"
      status 404
    end

    expect(both.title).to eq("Not Found")
  end
end
