# frozen_string_literal: true

module ActiveRecordGraphExtractor
  class Configuration
    attr_accessor :max_depth, :batch_size, :progress_enabled, :stream_json,
                  :validate_records, :use_transactions, :handle_circular_references,
                  :skip_missing_models, :included_models, :excluded_models,
                  :included_relationships, :excluded_relationships,
                  :custom_serializers, :primary_key_strategy, :skip_non_primary_database_models

    def initialize
      reset!
    end

    def reset!
      @max_depth = 5
      @batch_size = 1000
      @progress_enabled = true
      @stream_json = false
      @validate_records = true
      @use_transactions = true
      @handle_circular_references = true
      @skip_missing_models = true
      @skip_non_primary_database_models = true
      @included_models = []
      @excluded_models = []
      @included_relationships = []
      @excluded_relationships = []
      @custom_serializers = {}
      @primary_key_strategy = :generate_new
    end

    def max_depth=(value)
      raise ArgumentError, 'max_depth must be positive' if value <= 0
      @max_depth = value
    end

    def batch_size=(value)
      raise ArgumentError, 'batch_size must be positive' if value <= 0
      @batch_size = value
    end

    def primary_key_strategy=(strategy)
      unless [:preserve_original, :generate_new].include?(strategy)
        raise ArgumentError, 'primary_key_strategy must be :preserve_original or :generate_new'
      end
      @primary_key_strategy = strategy
    end

    def include_model(model)
      model_name = model.is_a?(Class) ? model.name : model.to_s
      @included_models << model_name unless @included_models.include?(model_name)
    end

    def exclude_model(model)
      model_name = model.is_a?(Class) ? model.name : model.to_s
      @excluded_models << model_name unless @excluded_models.include?(model_name)
    end

    def include_relationship(relationship)
      @included_relationships << relationship.to_s unless @included_relationships.include?(relationship.to_s)
    end

    def exclude_relationship(relationship)
      @excluded_relationships << relationship.to_s unless @excluded_relationships.include?(relationship.to_s)
    end

    def add_custom_serializer(model, serializer = nil, &block)
      model_name = model.is_a?(Class) ? model.name : model.to_s
      @custom_serializers[model_name] = serializer || block
    end

    def model_included?(model_name)
      return false if @excluded_models.include?(model_name.to_s)
      return true if @included_models.empty?
      @included_models.include?(model_name.to_s)
    end

    def relationship_included?(relationship_name)
      return false if @excluded_relationships.include?(relationship_name.to_s)
      return true if @included_relationships.empty?
      @included_relationships.include?(relationship_name.to_s)
    end

    class << self
      def configure
        yield(configuration)
      end

      def configuration
        @configuration ||= new
      end

      def reset!
        @configuration = new
      end
    end
  end
end 