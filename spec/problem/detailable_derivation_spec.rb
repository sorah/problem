# frozen_string_literal: true

# Reproduces the arrangement a deployment with its own catalogue of problems uses, and
# which the extraction this gem came from depends on: a module prepended to the error
# class's singleton overrides the DSL and calls `super` for a class the catalogue does
# not cover. It is here as a contract, not as a demonstration — the seam is invisible at
# every call site, so nothing else would notice if it broke.
module DerivationContract
  # Stands in for whatever a deployment keeps its problems in: an enum, a YAML file, a
  # database table.
  CATALOGUE = {
    invalid_credentials: {type: "invalid-credentials", status: 401, title: "Invalid Credentials"},
    throttled: {type: "too-many-requests", status: 429, title: "Try again in %{wait} seconds"},
  }.freeze

  module Typeable
    extend ActiveSupport::Concern

    module Derivation
      def type(value = nil)
        return super if value || problem_type.nil?

        CATALOGUE.fetch(problem_type).fetch(:type)
      end

      def status(value = nil)
        return super if value || problem_type.nil?

        CATALOGUE.fetch(problem_type).fetch(:status)
      end

      def title(value = nil, interpolations: {})
        return super if value || problem_type.nil?

        template = CATALOGUE.fetch(problem_type).fetch(:title)
        interpolations.empty? ? template : template % interpolations
      end
    end

    included do
      class_attribute :problem_type_value, instance_accessor: false

      singleton_class.prepend(Derivation)
    end

    class_methods do
      # Terminal fallbacks for a class that mixes in this concern alone.
      def type(_value = nil) = nil
      def status(_value = nil) = nil
      def title(_value = nil, interpolations: {}) = nil

      def problem_type(value = nil)
        return problem_type_value if value.nil?

        self.problem_type_value = value
      end
    end
  end

  # The deployment's own concern: the catalogue layer first, then the gem's literal DSL,
  # then the prepend re-applied so it wins over a ClassMethods extended later.
  module Detailable
    extend ActiveSupport::Concern

    include Typeable
    include Problem::Detailable

    included do
      singleton_class.prepend(Typeable::Derivation)
    end
  end
end

RSpec.describe("deriving the DSL from a catalogue") do
  let(:derived) do
    Class.new(StandardError) do
      include DerivationContract::Detailable

      problem_type :invalid_credentials
    end
  end

  it "derives type, status and title from the declared catalogue key" do
    expect(derived.type).to eq("invalid-credentials")
    expect(derived.status).to eq(401)
    expect(derived.title).to eq("Invalid Credentials")
  end

  it "wins over a literal declaration on the same class" do
    both = Class.new(StandardError) do
      include DerivationContract::Detailable

      type "literal"
      status 500
      problem_type :invalid_credentials
    end

    expect(both.type).to eq("invalid-credentials")
    expect(both.status).to eq(401)
  end

  # `super` has to land in the gem's ClassMethods, which is what keeps the literal DSL
  # working for a class the catalogue says nothing about.
  it "falls through to the literal DSL for a class that declares no catalogue key" do
    literal = Class.new(StandardError) do
      include DerivationContract::Detailable

      type "insufficient-balance"
      status 403
      title "Insufficient Balance"
    end

    expect(literal.type).to eq("insufficient-balance")
    expect(literal.status).to eq(403)
    expect(literal.title).to eq("Insufficient Balance")
  end

  # The `interpolations:` keyword is the whole reason the gem's #title carries one.
  it "hands the occurrence's interpolations to the derived title" do
    throttled = Class.new(StandardError) do
      include DerivationContract::Detailable

      problem_type :throttled

      def title_interpolations = {wait: 30}
    end

    expect(throttled.new.to_problem.title).to eq("Try again in 30 seconds")
  end

  # #to_problem must reach the DSL through self.class rather than read the class
  # attributes behind it, or the derivation is bypassed with no error anywhere.
  it "renders a derived problem through #to_problem" do
    problem = derived.new(detail: "wrong pin").to_problem

    expect(problem.type).to eq("invalid-credentials")
    expect(problem.status).to eq(401)
    expect(problem.title).to eq("Invalid Credentials")
    expect(problem.detail).to eq("wrong pin")
  end

  # Extending a ClassMethods onto a subclass puts it ahead of the prepend its superclass
  # holds, so the deployment's concern re-applies the prepend on every inclusion. Without
  # that, a subclass reads the literal DSL and the catalogue is silently bypassed.
  it "survives a subclass that mixes the concern in afterwards" do
    base = Class.new(StandardError) do
      include DerivationContract::Typeable

      problem_type :invalid_credentials
    end
    subclass = Class.new(base) { include DerivationContract::Detailable }

    expect(subclass.type).to eq("invalid-credentials")
  end

  it "loses the derivation when only the gem's concern is mixed into the subclass" do
    base = Class.new(StandardError) do
      include DerivationContract::Typeable

      problem_type :invalid_credentials
    end
    subclass = Class.new(base) { include Problem::Detailable }

    expect(subclass.type).to be_nil
  end

  # Included the other way round, Typeable's terminal fallbacks sit in front of the real
  # DSL and every literal declaration reads back nil.
  it "documents that the gem's concern must be included after the catalogue layer" do
    wrong_order = Class.new(StandardError) do
      include Problem::Detailable
      include DerivationContract::Typeable

      type "insufficient-balance"
    end

    expect(wrong_order.type).to be_nil
  end
end
