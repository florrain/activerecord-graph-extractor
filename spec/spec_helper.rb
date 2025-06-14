# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  add_filter "/spec/"
  minimum_coverage 90
end

require 'bundler/setup'
require 'activerecord_graph_extractor'
require 'active_record'
require 'sqlite3'
require 'factory_bot'
require 'database_cleaner'
require 'tempfile'

# Configure ActiveRecord for testing
ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: ':memory:'
)

# Load test models
Dir[File.expand_path('support/**/*.rb', __dir__)].sort.each { |f| require f }

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Database cleaner setup
  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
    
    # Create test database schema
    CreateTestSchema.new.change
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      # Reset configuration before each test to ensure clean state
      ActiveRecordGraphExtractor.configuration.reset!
      example.run
    end
  end

  # Suppress ActiveRecord logs during tests
  config.before(:all) do
    ActiveRecord::Base.logger = nil
  end
end 