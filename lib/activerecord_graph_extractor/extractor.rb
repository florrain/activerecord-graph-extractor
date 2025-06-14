# frozen_string_literal: true

require 'json'
require 'tempfile'

module ActiveRecordGraphExtractor
  class Extractor
    attr_reader :config, :relationship_analyzer

    def initialize(config = ActiveRecordGraphExtractor.configuration)
      @config = config
      @relationship_analyzer = RelationshipAnalyzer.new(config)
    end

    def extract(root_objects, options = {})
      raise ExtractionError, "Root object cannot be nil" if root_objects.nil?

      root_objects = Array(root_objects)
      
      # Validate that all objects are ActiveRecord instances
      root_objects.each do |obj|
        unless obj.is_a?(ActiveRecord::Base)
          raise ExtractionError, "Object must be an ActiveRecord object, got #{obj.class}"
        end
      end

      # Extract options
      max_depth = options[:max_depth] || config.max_depth
      custom_serializers = options[:custom_serializers] || {}

      start_time = Time.now
      records = []
      visited = Set.new
      circular_references = 0

      begin
        root_objects.each do |root_object|
          # Add the root object itself
          record_key = "#{root_object.class.name}_#{root_object.id}"
          unless visited.include?(record_key)
            records << serialize_record(root_object, custom_serializers)
            visited << record_key
          end

          # Extract related objects
          circular_references += extract_relationships(root_object, records, visited, 1, max_depth, custom_serializers)
        end

        extraction_time = Time.now - start_time
        metadata = build_metadata(start_time, records, circular_references, max_depth, root_objects)

        {
          'records' => records,
          'metadata' => metadata
        }
      rescue StandardError => e
        raise ExtractionError, "Failed to extract relationships: #{e.message}"
      end
    end

    def extract_to_file(root_objects, file_path, options = {})
      begin
        result = extract(root_objects, options)
        File.write(file_path, JSON.pretty_generate(result))
        result
      rescue Errno::ENOENT, Errno::EACCES => e
        raise FileError, "Cannot write to file #{file_path}: #{e.message}"
      rescue JSON::GeneratorError => e
        raise JSONError, "Failed to generate JSON: #{e.message}"
      end
    end

    def extract_to_s3(root_objects, s3_client, s3_key = nil, options = {})
      # Create a temporary file for the extraction
      temp_file = Tempfile.new(['extraction', '.json'])
      
      begin
        # Extract to temporary file
        result = extract_to_file(root_objects, temp_file.path, options)
        
        # Upload to S3
        upload_result = s3_client.upload_file(temp_file.path, s3_key)
        
        # Return combined result
        result.merge({
          's3_upload' => upload_result
        })
      ensure
        temp_file.close
        temp_file.unlink
      end
    end

    def extract_and_upload_to_s3(root_objects, bucket_name:, s3_key: nil, region: 'us-east-1', options: {}, **s3_options)
      s3_client = S3Client.new(bucket_name: bucket_name, region: region, **s3_options)
      extract_to_s3(root_objects, s3_client, s3_key, options)
    end

    def dry_run(root_objects, options = {})
      analyzer = DryRunAnalyzer.new(config)
      analyzer.analyze(root_objects, options)
    end

    private

    def extract_relationships(record, records, visited, current_depth, max_depth, custom_serializers)
      return 0 if current_depth > max_depth

      circular_refs = 0
      relationships = relationship_analyzer.analyze_model(record.class)

      relationships.each do |relationship_name, relationship_info|
        next unless config.relationship_included?(relationship_name)
        next unless config.model_included?(relationship_info['model_name'])

        begin
          related_objects = record.public_send(relationship_name)
          related_objects = Array(related_objects).compact

          related_objects.each do |related_object|
            record_key = "#{related_object.class.name}_#{related_object.id}"
            
            if visited.include?(record_key)
              circular_refs += 1 if config.handle_circular_references
              next
            end

            visited << record_key
            records << serialize_record(related_object, custom_serializers)

            # Recursively extract relationships
            circular_refs += extract_relationships(related_object, records, visited, current_depth + 1, max_depth, custom_serializers)
          end
        rescue ActiveRecord::StatementInvalid => e
          # Re-raise database errors 
          raise e
        rescue StandardError => e
          # Log the error but continue processing other relationships for non-DB errors
          next
        end
      end

      circular_refs
    end

    def serialize_record(record, custom_serializers)
      model_name = record.class.name
      
      # Use custom serializer if available (check both parameter and config)
      serializer = custom_serializers[model_name] || config.custom_serializers[model_name]
      if serializer
        serialized = serializer.call(record)
        # Ensure all keys are strings for consistency
        string_serialized = serialized.transform_keys(&:to_s)
        return string_serialized.merge('_model' => model_name)
      end

      # Default serialization
      attributes = record.attributes.except('updated_at', 'created_at')
      attributes['_model'] = model_name
      attributes
    end

    def build_metadata(start_time, records, circular_references, max_depth, root_objects)
      end_time = Time.now
      model_names = records.map { |r| r['_model'] }.uniq
      root_model = root_objects.first.class.name
      root_ids = root_objects.map(&:id)

      {
        'extraction_time' => start_time.iso8601,
        'total_records' => records.size,
        'models_extracted' => model_names,
        'circular_references_detected' => circular_references > 0,
        'max_depth_used' => max_depth,
        'duration_seconds' => (end_time - start_time).round(3),
        'root_model' => root_model,
        'root_ids' => root_ids
      }
    end
  end
end 