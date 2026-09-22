# frozen_string_literal: true

require_relative "lib/problem/version"

Gem::Specification.new do |spec|
  spec.name = "problem"
  spec.version = Problem::VERSION
  spec.authors = ["Sorah Fukumori"]
  spec.email = ["sorah@ivry.jp"]
  spec.summary = "RFC 9457 Problem Details for Rails APIs."
  spec.description = "Declares an API problem on the exception class — its type, title and " \
    "status — and renders any of them as application/problem+json, from a controller concern " \
    "for the errors a controller raises and from an exceptions app for the ones that escape it."
  spec.homepage = "https://github.com/sorah/problem"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.metadata = {
    "allowed_push_host" => "https://rubygems.org",
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true",
  }

  spec.files = Dir["lib/**/*.rb", "sig/**/*.rbs", "README.md", "LICENSE.txt", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "actionpack", ">= 7.0"

  spec.add_development_dependency "railties", ">= 7.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rbs", "~> 4.0"
  spec.add_development_dependency "rbs-inline", "~> 0.14"
  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "rubocop", "~> 1.82.0"
  spec.add_development_dependency "rubocop-shopify", "~> 2.18"
  spec.add_development_dependency "steep", "~> 2.0"
end
