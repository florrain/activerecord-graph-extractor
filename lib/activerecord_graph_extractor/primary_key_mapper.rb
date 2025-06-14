# frozen_string_literal: true

module ActiveRecordGraphExtractor
  class PrimaryKeyMapper
    attr_reader :strategy

    def initialize(strategy = :generate_new)
      unless [:preserve_original, :generate_new].include?(strategy)
        raise ArgumentError, "Invalid strategy: #{strategy}. Must be :preserve_original or :generate_new"
      end
      @strategy = strategy
      @mappings = {}
    end

    def add_mapping(model_name, original_id, new_id)
      model_key = model_name.to_s
      @mappings[model_key] ||= {}
      @mappings[model_key][original_id] = new_id
    end

    def get_mapping(model_name, original_id)
      model_key = model_name.to_s
      @mappings.dig(model_key, original_id)
    end

    def map_foreign_key(column_name, original_value)
      return original_value if original_value.nil?

      # Try to infer the model name from the foreign key column
      model_name = infer_model_name(column_name)
      return original_value unless model_name

      # Look up the mapping
      get_mapping(model_name, original_value) || original_value
    end

    def get_all_mappings
      @mappings.dup
    end

    def should_preserve_primary_key?
      @strategy == :preserve_original
    end

    private

    def infer_model_name(column_name)
      return nil unless column_name.to_s.end_with?('_id')

      # Remove _id suffix and convert to model name
      base_name = column_name.to_s.sub(/_id$/, '')
      
      # Convert snake_case to CamelCase
      base_name.split('_').map(&:capitalize).join
    end
  end
end 