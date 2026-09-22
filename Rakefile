# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

desc "Regenerate inline RBS signatures under sig/generated"
task :rbs do
  sh "rbs-inline --output=sig/generated lib"
  sh "rbs -I sig/generated -I sig/manual validate"
end

desc "Type check lib against the RBS signatures"
task steep: :rbs do
  sh "steep check"
end

task default: [:spec, :steep]
