# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "json"
require "rack/mock"
require "problem"

# Nothing boots Rails here, so the Railtie never fires.
Problem.install!

ActionController::Base.logger = nil

# Drives a controller through the full ActionController lifecycle — callbacks, rescue_from,
# rendering — with no router and no Rails application.
module ControllerHelpers
  Result = Data.define(:status, :headers, :body) do
    def json = JSON.parse(body)
    def content_type = headers["content-type"]
  end

  def call_action(controller, action, path: "/test", headers: {})
    env = Rack::MockRequest.env_for(path, method: "GET")
    headers.each { |name, value| env["HTTP_#{name.upcase.tr("-", "_")}"] = value }

    status, response_headers, body = controller.action(action).call(env)
    collected = +""
    body.each { |chunk| collected << chunk }

    Result.new(status: status, headers: response_headers, body: collected)
  end
end

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = ".rspec_status"

  config.include(ControllerHelpers)

  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
