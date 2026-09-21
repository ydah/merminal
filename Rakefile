# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rake"

RSpec::Core::RakeTask.new(:spec)

desc "Require at least 90% line coverage"
task :coverage do
  ruby "tools/coverage.rb"
end

desc "Check Ruby code and repository invariants"
task :lint do
  ruby "tools/lint.rb"
  sh "bundle exec rubocop --only Lint lib tools exe"
end

desc "Build an HTML gallery from original fixtures"
task :gallery do
  ruby "tools/build_gallery.rb"
end

desc "Run a small flowchart benchmark"
task :bench do
  ruby "tools/bench.rb"
end

namespace :unicode do
  desc "Regenerate Unicode tables from EAW_FILE and UCD_FILE"
  task :generate do
    eaw = ENV.fetch("EAW_FILE")
    ucd = ENV.fetch("UCD_FILE")
    ruby "tools/generate_east_asian_width.rb", eaw, ucd
    ruby "tools/generate_box_drawing.rb", ucd
  end
end

desc "Check that the gem has no runtime dependencies"
task :deps do
  abort "runtime dependencies found" unless Gem::Specification.load("mermaid_term.gemspec").runtime_dependencies.empty?
end

desc "Validate public RBS declarations"
task :types do
  sh "bundle exec rbs validate"
end

task default: :spec
