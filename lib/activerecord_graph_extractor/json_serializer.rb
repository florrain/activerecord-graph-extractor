# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'oj'

module ActiveRecordGraphExtractor
  class JSONSerializer
    attr_reader :config

    def initialize(config = Configuration.new)
      @config = config
    end

    def serialize_to_file(data, file_path)
      if config.stream_json
        stream_serialize_to_file(data, file_path)
      else
        File.write(file_path, serialize_to_string(data))
      end
    end

    def serialize_to_string(data)
      Oj.dump(data, mode: :compat, indent: 2)
    end

    def deserialize_from_file(file_path)
      raise Errno::ENOENT, "No such file or directory @ rb_sysopen - #{file_path}" unless File.exist?(file_path)
      
      if config.stream_json
        stream_deserialize_from_file(file_path)
      else
        Oj.load_file(file_path, mode: :compat)
      end
    end

    def deserialize_from_string(json_string)
      Oj.load(json_string, mode: :compat)
    end

    def validate_json_structure(data)
      errors = []
      
      # Check required metadata
      unless data.is_a?(Hash)
        errors << "Root data must be a hash"
        return errors
      end
      
      metadata = data['metadata']
      unless metadata.is_a?(Hash)
        errors << "Missing or invalid metadata section"
        return errors
      end
      
      required_metadata = %w[root_model root_id extracted_at schema_version]
      required_metadata.each do |field|
        unless metadata.key?(field)
          errors << "Missing required metadata field: #{field}"
        end
      end
      
      # Check records structure
      records = data['records']
      unless records.is_a?(Hash)
        errors << "Missing or invalid records section"
        return errors
      end
      
      records.each do |model_name, model_records|
        unless model_records.is_a?(Array)
          errors << "Records for #{model_name} must be an array"
          next
        end
        
        model_records.each_with_index do |record, index|
          record_errors = validate_record_structure(record, model_name, index)
          errors.concat(record_errors)
        end
      end
      
      errors
    end

    def estimate_file_size(data)
      # Rough estimation based on JSON serialization
      sample_size = [data.dig('records')&.values&.first&.size || 0, 100].min
      
      if sample_size > 0
        sample_data = data.dup
        sample_data['records'] = data['records'].transform_values do |records|
          records.first(sample_size)
        end
        
        sample_json = serialize_to_string(sample_data)
        total_records = data['records'].values.sum(&:size)
        
        (sample_json.bytesize.to_f / sample_size * total_records).round
      else
        serialize_to_string(data).bytesize
      end
    end

    private

    def stream_serialize_to_file(data, file_path)
      File.open(file_path, 'w') do |file|
        file.write('{"metadata":')
        file.write(Oj.dump(data['metadata'], mode: :compat))
        file.write(',"records":{')
        
        model_names = data['records'].keys
        model_names.each_with_index do |model_name, model_index|
          file.write('"')
          file.write(model_name)
          file.write('":[')
          
          records = data['records'][model_name]
          records.each_with_index do |record, record_index|
            file.write(Oj.dump(record, mode: :compat))
            file.write(',') unless record_index == records.size - 1
          end
          
          file.write(']')
          file.write(',') unless model_index == model_names.size - 1
        end
        
        file.write('}}')
      end
    end

    def stream_deserialize_from_file(file_path)
      # For streaming deserialization, we need to parse the JSON incrementally
      # This is a simplified implementation - for production, consider using a proper streaming JSON parser
      content = File.read(file_path)
      Oj.load(content, mode: :compat)
    end

    def validate_record_structure(record, model_name, index)
      errors = []
      
      unless record.is_a?(Hash)
        errors << "Record #{index} in #{model_name} must be a hash"
        return errors
      end
      
      unless record.key?('original_id')
        errors << "Record #{index} in #{model_name} missing original_id"
      end
      
      unless record.key?('attributes')
        errors << "Record #{index} in #{model_name} missing attributes"
      end
      
      attributes = record['attributes']
      unless attributes.is_a?(Hash)
        errors << "Record #{index} in #{model_name} attributes must be a hash"
      end
      
      if record.key?('relationships')
        relationships = record['relationships']
        unless relationships.is_a?(Hash)
          errors << "Record #{index} in #{model_name} relationships must be a hash"
        else
          relationships.each do |field, reference|
            unless reference.is_a?(Hash) && reference.key?('table') && reference.key?('original_id')
              errors << "Record #{index} in #{model_name} has invalid relationship #{field}"
            end
          end
        end
      end
      
      errors
    end
  end
end 