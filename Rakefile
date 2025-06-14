# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

desc "Run all tests and checks"
task test: [:spec, :rubocop]

task default: :test

desc "Run tests with coverage report"
task :coverage do
  ENV['COVERAGE'] = 'true'
  Rake::Task[:spec].invoke
end

desc "Generate documentation"
task :doc do
  sh "yard doc"
end

desc "Setup development environment"
task :setup do
  sh "bundle install"
  puts "✅ Development environment setup complete!"
  puts
  puts "Available tasks:"
  puts "  rake spec      # Run tests"
  puts "  rake rubocop   # Run code style checks"
  puts "  rake test      # Run tests and style checks"
  puts "  rake coverage  # Run tests with coverage report"
end 