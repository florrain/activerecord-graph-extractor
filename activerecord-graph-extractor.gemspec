# frozen_string_literal: true

require_relative "lib/activerecord_graph_extractor/version"

Gem::Specification.new do |spec|
  spec.name          = "activerecord-graph-extractor"
  spec.version       = ActiveRecordGraphExtractor::VERSION
  spec.authors       = ["Florian Lorrain"]
  spec.email         = ["lorrain.florian@gmail.com"]

  spec.summary       = "Extract and import complex ActiveRecord object graphs while preserving relationships"
  spec.description   = "A Ruby gem for extracting and importing complex ActiveRecord object graphs with smart dependency resolution, beautiful CLI progress visualization, and memory-efficient streaming. Perfect for data migration, testing, and environment synchronization."
  spec.homepage      = "https://github.com/florrain/activerecord-graph-extractor"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/florrain/activerecord-graph-extractor"
  spec.metadata["changelog_uri"] = "https://github.com/florrain/activerecord-graph-extractor/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Core dependencies
  spec.add_dependency "activerecord", ">= 6.0"
  spec.add_dependency "activesupport", ">= 6.0"
  
  # CLI dependencies
  spec.add_dependency "thor", "~> 1.2"
  spec.add_dependency "tty-progressbar", "~> 0.18"
  spec.add_dependency "tty-spinner", "~> 0.9"
  spec.add_dependency "tty-tree", "~> 0.4"
  spec.add_dependency "pastel", "~> 0.8"
  spec.add_dependency "tty-prompt", "~> 0.23"
  
  # JSON streaming
  spec.add_dependency "oj", "~> 3.13"
  spec.add_dependency "yajl-ruby", ">= 1.3"
  
  # S3 support
  spec.add_dependency "aws-sdk-s3", "~> 1.0"

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rubocop", "~> 1.57"
  spec.add_development_dependency "sqlite3", "~> 1.6"
  spec.add_development_dependency "database_cleaner", "~> 2.0"
  spec.add_development_dependency "factory_bot", "~> 6.2"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "rubocop-rspec", "~> 2.25"
  spec.add_development_dependency "pry", "~> 0.14"
  spec.add_development_dependency "pry-byebug", "~> 3.10"
end 