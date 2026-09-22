# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

require "action_controller"
require "problem/document"

module Problem
  # Registers the application/problem+json media type and the `problem:` renderer.
  #
  #   render problem: error.to_problem
  #
  # Installed by Problem::Railtie on boot; a Rack host or a spec that never boots Rails
  # calls Problem.install! itself.
  module Renderer
    # Renders whatever it is handed, so a deployment can pass its own serializer's object
    # rather than a Problem::Details as long as it answers #status and #to_json.
    #: () -> void
    def self.install!
      Mime::Type.register(Document::CONTENT_TYPE, :problem) unless Mime[:problem]

      # `self` in a renderer block is the controller instance, which RBS cannot name here.
      # steep:ignore:start
      ActionController::Renderers.add(:problem) do |problem, options|
        self.content_type = Mime[:problem]
        self.status = options[:status] || problem.status
        problem.to_json
      end
      # steep:ignore:end
    end
  end
end
