# frozen_string_literal: true

# Loaded here rather than in spec_helper: problem.rb requires the Railtie only when Rails
# is already present, which is the behaviour that keeps the gem loadable without it.
require "rails"
require "problem/railtie"

RSpec.describe(Problem::Railtie) do
  def initializer(name) = described_class.initializers.find { |i| i.name == name }

  def app_with(problem_config)
    config = ActiveSupport::OrderedOptions.new
    config.problem = problem_config
    Struct.new(:config).new(config)
  end

  it "installs the renderer on boot" do
    expect(initializer("problem.renderer")).not_to be_nil
  end

  # Without this the prefix can only be set in config/application.rb, because a railtie
  # initializer otherwise runs before config/initializers is loaded.
  it "reads the configuration after config/initializers has been loaded" do
    expect(initializer("problem.config").after).to eq(:load_config_initializers)
  end

  it "applies config.problem.type_prefix to the gem's configuration" do
    problem_config = ActiveSupport::OrderedOptions.new
    problem_config.type_prefix = "https://example.com/problems/"

    initializer("problem.config").run(app_with(problem_config))

    expect(Problem.config.type_prefix).to eq("https://example.com/problems/")
  ensure
    Problem.config.type_prefix = nil
  end

  it "leaves the configuration alone when the application sets no prefix" do
    Problem.config.type_prefix = "https://set-in-ruby.example/"

    initializer("problem.config").run(app_with(ActiveSupport::OrderedOptions.new))

    expect(Problem.config.type_prefix).to eq("https://set-in-ruby.example/")
  ensure
    Problem.config.type_prefix = nil
  end
end
