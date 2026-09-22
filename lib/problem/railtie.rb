# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

require "rails/railtie"

module Problem
  # Wires the gem into a Rails application on boot.
  #
  #   config.problem.type_prefix = "https://api-probs.example.com/"
  #
  # config.exceptions_app is deliberately left alone: replacing what an application set
  # there is not an initializer's business, so Problem::ExceptionsApp is wired by hand.
  class Railtie < ::Rails::Railtie
    config.problem = ActiveSupport::OrderedOptions.new

    # After config/initializers, so the prefix can be set there as well as in
    # config/application.rb and the environment files.
    initializer("problem.config", after: :load_config_initializers) do |app|
      prefix = app.config.problem.type_prefix
      Problem.config.type_prefix = prefix if prefix
    end

    initializer("problem.renderer") { Problem.install! }
  end
end
