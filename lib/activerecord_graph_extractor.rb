# frozen_string_literal: true

require "active_record"
require "active_support"
require "yajl"

require_relative "activerecord_graph_extractor/version"
require_relative "activerecord_graph_extractor/errors"
require_relative "activerecord_graph_extractor/configuration"
require_relative "activerecord_graph_extractor/relationship_analyzer"
require_relative "activerecord_graph_extractor/dependency_resolver"
require_relative "activerecord_graph_extractor/json_serializer"
require_relative "activerecord_graph_extractor/primary_key_mapper"
require_relative "activerecord_graph_extractor/progress_tracker"
require_relative "activerecord_graph_extractor/s3_client"
require_relative "activerecord_graph_extractor/dry_run_analyzer"
require_relative "activerecord_graph_extractor/extractor"
require_relative "activerecord_graph_extractor/importer"

module ActiveRecordGraphExtractor
  class << self
    def configure
      yield(configuration)
    end

    def configuration
      @configuration ||= Configuration.new
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end 