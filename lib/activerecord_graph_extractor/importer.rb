# frozen_string_literal: true

require 'json'

module ActiveRecordGraphExtractor
  class Importer
    attr_reader :config

    def initialize(config = ActiveRecordGraphExtractor.configuration)
      @config = config
    end

    def import(data, options = {})
      validate_data_structure!(data)

      records = data['records']
      raise ImportError, "No records found in data" if records.empty?

      start_time = Time.now
      pk_mapper = PrimaryKeyMapper.new(config.primary_key_strategy)
      
      begin
        imported_count = 0
        skipped_count = 0
        errors = []
        
        use_transaction = options[:transaction] || config.use_transactions
        batch_size = options[:batch_size] || 1000
        skip_existing = options[:skip_existing] || false
        custom_finders = options[:custom_finders] || {}
        
        if use_transaction
          ActiveRecord::Base.transaction do
            imported_count, skipped_count, errors = import_records_in_order(
              records, pk_mapper, skip_existing, custom_finders, batch_size
            )
          end
        else
          imported_count, skipped_count, errors = import_records_in_order(
            records, pk_mapper, skip_existing, custom_finders, batch_size
          )
        end

        import_duration = Time.now - start_time
        
        {
          'metadata' => build_import_metadata(start_time, imported_count, skipped_count, errors, import_duration, data['records'].size),
          'imported_records' => imported_count,
          'skipped_records' => skipped_count,
          'errors' => errors,
          'primary_key_mappings' => pk_mapper.get_all_mappings
        }
      rescue StandardError => e
        raise ImportError, "Failed to import records: #{e.message}"
      end
    end

    def import_from_file(file_path, options = {})
      unless File.exist?(file_path)
        raise FileError, "File not found: #{file_path}"
      end

      begin
        file_content = File.read(file_path)
        data = JSON.parse(file_content)
        import(data, options)
      rescue JSON::ParserError => e
        raise JSONError, "Invalid JSON in file #{file_path}: #{e.message}"
      rescue => e
        raise FileError, "Error reading file #{file_path}: #{e.message}"
      end
    end

    private

    def validate_data_structure!(data)
      unless data.is_a?(Hash) && data.key?('records')
        raise ImportError, "Invalid data structure: expected Hash with 'records' key"
      end
    end

    def import_records_in_order(records, pk_mapper, skip_existing, custom_finders, batch_size)
      # Group records by model and resolve dependencies
      resolver = DependencyResolver.new({})
      analyzer = RelationshipAnalyzer.new(config)
      
      records_by_model = group_records_by_model(records)
      models = records_by_model.keys.map { |name| name.constantize rescue nil }.compact
      dependency_graph = analyzer.build_dependency_graph(models)
      
      ordered_records = resolver.build_creation_order(records_by_model, dependency_graph)
      
      import_records(ordered_records, pk_mapper, skip_existing, custom_finders, batch_size)
    end

    def group_records_by_model(records)
      grouped = {}
      
      records.each do |record|
        unless record.key?('_model')
          raise ImportError, "Record missing _model key: #{record.inspect}"
        end
        
        model_name = record['_model']
        grouped[model_name] ||= []
        grouped[model_name] << record
      end
      
      grouped
    end

    def import_records(ordered_records, pk_mapper, skip_existing, custom_finders, batch_size)
      total_imported = 0
      total_skipped = 0
      errors = []
      
      # First pass: validate all records and check for existing records
      records_to_import = []
      
      ordered_records.each do |model_name, model_records|
        model_records.each do |record_data|
          begin
            # Check for existing record if skip_existing is true
            if skip_existing || custom_finders[model_name]
              existing_record = find_existing_record(model_name, record_data, custom_finders)
              if existing_record
                total_skipped += 1
                next
              end
            end

            # Validate the record without saving
            if validate_record(model_name, record_data, pk_mapper)
              records_to_import << [model_name, record_data]
            end
          rescue ImportError, ActiveRecord::RecordInvalid => e
            errors << {
              model: model_name,
              record: record_data,
              error: e.message
            }
          rescue => e
            errors << {
              model: model_name,
              record: record_data,
              error: e.message
            }
          end
        end
      end
      
      # If there are any validation errors, don't import anything
      return [0, total_skipped, errors] if errors.any?
      
      # Second pass: actually import the records
      records_to_import.each_slice(batch_size) do |batch|
        batch.each do |model_name, record_data|
          begin
            created_record = create_record(model_name, record_data, pk_mapper)
            
            if created_record&.persisted?
              original_id = record_data['id']
              pk_mapper.add_mapping(model_name, original_id, created_record.id) if original_id
              total_imported += 1
            end
          rescue => e
            errors << {
              model: model_name,
              record: record_data,
              error: e.message
            }
          end
        end
      end
      
      [total_imported, total_skipped, errors]
    end

    def validate_record(model_name, record_data, pk_mapper)
      return true unless config.validate_records
      
      model_class = model_name.constantize
      attributes = prepare_attributes(model_name, record_data, pk_mapper)
      record = model_class.new(attributes)
      
      unless record.valid?
        raise ImportError, "Validation failed for #{model_name}: #{record.errors.full_messages.join(', ')}"
      end
      
      true
    rescue NameError
      raise ImportError, "Model class #{model_name} not found"
    end

    def find_existing_record(model_name, record_data, custom_finders)
      if custom_finders[model_name]
        custom_finders[model_name].call(record_data)
      elsif record_data['id']
        model_class = model_name.constantize
        model_class.find_by(id: record_data['id'])
      end
    rescue NameError
      nil
    end

    def create_record(model_name, record_data, pk_mapper)
      model_class = model_name.constantize
      
      attributes = prepare_attributes(model_name, record_data, pk_mapper)
      
      record = model_class.new(attributes)
      
      if config.validate_records
        unless record.valid?
          raise ImportError, "Validation failed for #{model_name}: #{record.errors.full_messages.join(', ')}"
        end
      end
      
      record.save!
      record
    rescue NameError
      raise ImportError, "Model class #{model_name} not found"
    rescue ActiveRecord::RecordInvalid => e
      raise ImportError, "Failed to create #{model_name}: #{e.message}"
    end

    def prepare_attributes(model_name, record_data, pk_mapper)
      attributes = record_data.except('_model')
      
      # Handle primary key based on strategy
      unless pk_mapper.should_preserve_primary_key?
        attributes.delete('id')
      end
      
      # Map foreign keys to new primary keys
      attributes.each do |key, value|
        if key.end_with?('_id') && value
          mapped_value = pk_mapper.get_mapping(key.sub('_id', '').classify, value)
          attributes[key] = mapped_value if mapped_value
        end
      end
      
      attributes
    end

    def build_import_metadata(start_time, imported_count, skipped_count, errors, duration, total_records)
      metadata = {
        'import_time' => start_time.iso8601,
        'total_records' => total_records,
        'imported_records' => imported_count,
        'skipped_records' => skipped_count,
        'duration_seconds' => duration.round(3),
        'primary_key_strategy' => config.primary_key_strategy.to_s
      }
      
      metadata['errors'] = errors if errors.any?
      metadata
    end
  end
end 