# frozen_string_literal: true

module ActiveRecordGraphExtractor
  class DryRunAnalyzer
    attr_reader :config, :relationship_analyzer

    def initialize(config = ActiveRecordGraphExtractor.configuration)
      @config = config
      @relationship_analyzer = RelationshipAnalyzer.new(config)
    end

    def analyze(root_objects, options = {})
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

      start_time = Time.now
      
      begin
        # Analyze the object graph without loading data
        analysis_result = analyze_object_graph(root_objects, max_depth)
        
        analysis_time = Time.now - start_time

        # Build comprehensive analysis report
        build_analysis_report(analysis_result, analysis_time, root_objects, max_depth)
      rescue StandardError => e
        raise ExtractionError, "Failed to analyze object graph: #{e.message}"
      end
    end

    private

    def analyze_object_graph(root_objects, max_depth)
      visited_models = Set.new
      model_counts = Hash.new(0)
      relationship_map = {}
      circular_references = []
      depth_analysis = {}
      
      root_objects.each do |root_object|
        analyze_relationships_recursively(
          root_object.class,
          visited_models,
          model_counts,
          relationship_map,
          circular_references,
          depth_analysis,
          1,
          max_depth,
          [root_object.class.name]
        )
        
        # Count the root object itself
        model_counts[root_object.class.name] += 1
      end

      {
        visited_models: visited_models,
        model_counts: model_counts,
        relationship_map: relationship_map,
        circular_references: circular_references,
        depth_analysis: depth_analysis
      }
    end

    def analyze_relationships_recursively(model_class, visited_models, model_counts, relationship_map, circular_references, depth_analysis, current_depth, max_depth, path)
      return if current_depth > max_depth

      model_name = model_class.name
      visited_models << model_name
      
      # Track depth analysis
      depth_analysis[current_depth] ||= Set.new
      depth_analysis[current_depth] << model_name

      # Get relationships for this model
      relationships = relationship_analyzer.analyze_model(model_class)
      relationship_map[model_name] = relationships

      relationships.each do |relationship_name, relationship_info|
        next unless config.relationship_included?(relationship_name)
        next unless config.model_included?(relationship_info['model_name'])

        related_model_name = relationship_info['model_name']
        
        # Check for circular references
        if path.include?(related_model_name)
          circular_references << {
            path: path + [related_model_name],
            relationship: relationship_name,
            depth: current_depth
          }
          next if config.handle_circular_references
        end

        begin
          related_model_class = related_model_name.constantize
          
          # Estimate record count for this relationship
          estimated_count = estimate_relationship_count(model_class, relationship_name, relationship_info)
          model_counts[related_model_name] += estimated_count

          # Recursively analyze deeper relationships
          analyze_relationships_recursively(
            related_model_class,
            visited_models,
            model_counts,
            relationship_map,
            circular_references,
            depth_analysis,
            current_depth + 1,
            max_depth,
            path + [related_model_name]
          )
        rescue NameError
          # Skip models that don't exist
          next
        rescue StandardError => e
          # Log error but continue analysis
          next
        end
      end
    end

    def estimate_relationship_count(model_class, relationship_name, relationship_info)
      # Try to get a sample record to estimate relationship sizes
      sample_record = model_class.first
      return 0 unless sample_record

      begin
        case relationship_info['type']
        when 'has_many', 'has_and_belongs_to_many'
          # For has_many relationships, estimate based on sample
          related_records = sample_record.public_send(relationship_name)
          if related_records.respond_to?(:count)
            sample_count = related_records.limit(100).count
            # Estimate total based on sample (with some reasonable assumptions)
            total_records = model_class.count
            return 0 if total_records == 0
            
            # Use sample count as average, but cap at reasonable limits
            average_per_record = [sample_count, 50].min # Cap at 50 per record for estimation
            return (total_records * average_per_record * 0.8).to_i # 80% factor for estimation
          end
        when 'has_one', 'belongs_to'
          # For singular relationships, estimate 1 per parent record
          total_records = model_class.count
          return (total_records * 0.9).to_i # 90% factor assuming some records might not have the relationship
        end
      rescue StandardError
        # If we can't estimate, return a conservative estimate
        return model_class.count > 0 ? [model_class.count / 10, 1].max : 0
      end

      0
    end

    def estimate_file_size(model_counts, relationship_map)
      total_size = 0
      
      model_counts.each do |model_name, count|
        next if count == 0
        
        begin
          model_class = model_name.constantize
          
          # Estimate size per record based on column types and relationships
          size_per_record = estimate_record_size(model_class, relationship_map[model_name] || {})
          total_size += count * size_per_record
        rescue NameError
          # Use default size if model doesn't exist
          total_size += count * 500 # 500 bytes default
        end
      end

      # Add JSON structure overhead (metadata, formatting, etc.)
      metadata_overhead = 2048 # 2KB for metadata
      json_formatting_overhead = total_size * 0.1 # 10% for JSON formatting
      
      (total_size + metadata_overhead + json_formatting_overhead).to_i
    end

    def estimate_record_size(model_class, relationships)
      base_size = 0
      
      # Estimate size based on column types
      model_class.columns.each do |column|
        base_size += case column.type
                    when :string, :text
                      column.limit || 255
                    when :integer, :bigint
                      8
                    when :decimal, :float
                      16
                    when :datetime, :timestamp
                      25
                    when :date
                      12
                    when :boolean
                      5
                    when :json, :jsonb
                      500 # Estimate for JSON fields
                    else
                      50 # Default for unknown types
                    end
      end

      # Add overhead for JSON structure and field names
      field_name_overhead = model_class.columns.size * 20 # Average field name length
      json_structure_overhead = 50 # Brackets, commas, etc.
      
      base_size + field_name_overhead + json_structure_overhead
    end

    def build_analysis_report(analysis_result, analysis_time, root_objects, max_depth)
      model_counts = analysis_result[:model_counts]
      total_records = model_counts.values.sum
      estimated_file_size = estimate_file_size(model_counts, analysis_result[:relationship_map])

      {
        'dry_run' => true,
        'analysis_time' => analysis_time.round(3),
        'root_objects' => {
          'models' => root_objects.map(&:class).map(&:name).uniq,
          'ids' => root_objects.map(&:id),
          'count' => root_objects.size
        },
        'extraction_scope' => {
          'max_depth' => max_depth,
          'total_models' => analysis_result[:visited_models].size,
          'total_estimated_records' => total_records,
          'models_involved' => analysis_result[:visited_models].to_a.sort
        },
        'estimated_counts_by_model' => model_counts.sort_by { |_, count| -count }.to_h,
        'estimated_file_size' => {
          'bytes' => estimated_file_size,
          'human_readable' => format_file_size(estimated_file_size)
        },
        'depth_analysis' => format_depth_analysis(analysis_result[:depth_analysis]),
        'relationship_analysis' => {
          'total_relationships' => analysis_result[:relationship_map].values.map(&:size).sum,
          'circular_references' => analysis_result[:circular_references].map do |ref|
            {
              'path' => ref[:path].join(' -> '),
              'relationship' => ref[:relationship],
              'depth' => ref[:depth]
            }
          end,
          'circular_references_count' => analysis_result[:circular_references].size
        },
        'performance_estimates' => estimate_performance(total_records, estimated_file_size),
        'warnings' => generate_warnings(analysis_result, total_records, estimated_file_size),
        'recommendations' => generate_recommendations(analysis_result, total_records, estimated_file_size, max_depth)
      }
    end

    def format_depth_analysis(depth_analysis)
      depth_analysis.transform_values(&:to_a).transform_values(&:sort)
    end

    def format_file_size(size_bytes)
      if size_bytes < 1024
        "#{size_bytes} B"
      elsif size_bytes < 1024 * 1024
        "#{(size_bytes / 1024.0).round(1)} KB"
      elsif size_bytes < 1024 * 1024 * 1024
        "#{(size_bytes / (1024.0 * 1024)).round(1)} MB"
      else
        "#{(size_bytes / (1024.0 * 1024 * 1024)).round(1)} GB"
      end
    end

    def estimate_performance(total_records, file_size_bytes)
      # Rough performance estimates based on typical hardware
      records_per_second = 1000 # Conservative estimate
      estimated_extraction_time = (total_records / records_per_second.to_f).round(1)
      
      # Memory usage estimate (records in memory + overhead)
      estimated_memory_mb = ((total_records * 1024) / (1024.0 * 1024)).round(1)
      
      {
        'estimated_extraction_time_seconds' => estimated_extraction_time,
        'estimated_extraction_time_human' => format_duration(estimated_extraction_time),
        'estimated_memory_usage_mb' => estimated_memory_mb,
        'estimated_memory_usage_human' => "#{estimated_memory_mb} MB"
      }
    end

    def format_duration(seconds)
      if seconds < 60
        "#{seconds.round(1)} seconds"
      elsif seconds < 3600
        minutes = (seconds / 60).round(1)
        "#{minutes} minutes"
      else
        hours = (seconds / 3600).round(1)
        "#{hours} hours"
      end
    end

    def generate_warnings(analysis_result, total_records, file_size_bytes)
      warnings = []
      
      # Large dataset warnings
      if total_records > 100_000
        warnings << {
          'type' => 'large_dataset',
          'message' => "Large dataset detected (#{total_records.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} records). Consider using filters or reducing max_depth.",
          'severity' => 'high'
        }
      elsif total_records > 10_000
        warnings << {
          'type' => 'medium_dataset',
          'message' => "Medium dataset detected (#{total_records.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} records). Monitor memory usage during extraction.",
          'severity' => 'medium'
        }
      end

      # Large file size warnings
      if file_size_bytes > 1024 * 1024 * 1024 # 1GB
        warnings << {
          'type' => 'large_file',
          'message' => "Estimated file size is very large (#{format_file_size(file_size_bytes)}). Consider splitting the extraction.",
          'severity' => 'high'
        }
      elsif file_size_bytes > 100 * 1024 * 1024 # 100MB
        warnings << {
          'type' => 'medium_file',
          'message' => "Estimated file size is large (#{format_file_size(file_size_bytes)}). Ensure adequate disk space.",
          'severity' => 'medium'
        }
      end

      # Circular reference warnings
      if analysis_result[:circular_references].any?
        warnings << {
          'type' => 'circular_references',
          'message' => "#{analysis_result[:circular_references].size} circular reference(s) detected. Enable handle_circular_references if needed.",
          'severity' => 'medium'
        }
      end

      # Deep nesting warnings
      max_actual_depth = analysis_result[:depth_analysis].keys.max || 0
      if max_actual_depth > 5
        warnings << {
          'type' => 'deep_nesting',
          'message' => "Deep relationship nesting detected (#{max_actual_depth} levels). This may impact performance.",
          'severity' => 'medium'
        }
      end

      warnings
    end

    def generate_recommendations(analysis_result, total_records, file_size_bytes, max_depth)
      recommendations = []

      # Performance recommendations
      if total_records > 50_000
        recommendations << {
          'type' => 'performance',
          'message' => 'Consider using batch processing or streaming for large datasets',
          'action' => 'Use extract_in_batches or enable streaming mode'
        }
      end

      # Depth recommendations
      if max_depth > 3 && analysis_result[:depth_analysis].keys.max.to_i > 3
        recommendations << {
          'type' => 'depth',
          'message' => 'Consider reducing max_depth to improve performance',
          'action' => "Try max_depth: #{[max_depth - 1, 2].max}"
        }
      end

      # Model filtering recommendations
      large_models = analysis_result[:model_counts].select { |_, count| count > total_records * 0.3 }
      if large_models.any?
        model_names = large_models.keys.join(', ')
        recommendations << {
          'type' => 'filtering',
          'message' => "Large model(s) detected: #{model_names}",
          'action' => 'Consider excluding these models or using custom filters'
        }
      end

      # S3 recommendations
      if file_size_bytes > 50 * 1024 * 1024 # 50MB
        recommendations << {
          'type' => 's3',
          'message' => 'Large file detected - consider uploading directly to S3',
          'action' => 'Use extract_to_s3 or extract_and_upload_to_s3 methods'
        }
      end

      # Memory recommendations
      estimated_memory_mb = ((total_records * 1024) / (1024.0 * 1024)).round(1)
      if estimated_memory_mb > 1000 # 1GB
        recommendations << {
          'type' => 'memory',
          'message' => 'High memory usage expected',
          'action' => 'Ensure adequate RAM or use streaming extraction'
        }
      end

      recommendations
    end
  end
end 