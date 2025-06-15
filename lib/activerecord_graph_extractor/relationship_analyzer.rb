# frozen_string_literal: true

module ActiveRecordGraphExtractor
  class RelationshipAnalyzer
    attr_reader :config, :visited_models, :circular_paths

    def initialize(config = ActiveRecordGraphExtractor.configuration)
      @config = config
      @visited_models = Set.new
      @circular_paths = []
      @primary_connection = ActiveRecord::Base.connection
    end

    def analyze_model(model_class)
      # Validate that this is an ActiveRecord model
      unless model_class.respond_to?(:reflect_on_all_associations)
        raise ExtractionError, "#{model_class} is not an ActiveRecord model"
      end

      relationships = {}

      model_class.reflect_on_all_associations.each do |association|
        begin
          next if association.klass.nil?

          relationship_name = association.name.to_s
          next unless config.relationship_included?(relationship_name)

          # Check if the associated model uses the primary database
          associated_model = association.klass
          model_name = associated_model.name
          
          # Skip if model is excluded
          next unless config.model_included?(model_name)
          
          # Skip if the associated model doesn't use the primary database (if enabled)
          if config.skip_non_primary_database_models
            next unless uses_primary_database?(associated_model)
          end

          relationships[relationship_name] = {
            'type' => association.macro.to_s,
            'model_class' => associated_model,
            'model_name' => model_name,
            'foreign_key' => association.foreign_key,
            'polymorphic' => association.options[:polymorphic] || false,
            'optional' => association.options[:optional] || false
          }
        rescue NameError => e
          if config.skip_missing_models
            next
          else
            raise e
          end
        rescue StandardError => e
          # Skip associations that cause database connection errors
          if e.message.include?('Unknown database') || e.message.include?('database connection')
            next
          else
            raise e unless config.skip_missing_models
          end
        end
      end

      filter_relationships(relationships)
    end

    def analyze_models(model_classes)
      # Validate input
      unless model_classes.is_a?(Array)
        raise ExtractionError, "Expected an array of model classes"
      end

      # Handle empty array
      return {} if model_classes.empty?

      # Validate each model class
      model_classes.each do |model_class|
        unless model_class.respond_to?(:reflect_on_all_associations)
          raise ExtractionError, "#{model_class} is not an ActiveRecord model"
        end
      end

      relationships = {}

      model_classes.each do |model_class|
        model_name = model_class.name
        relationships[model_name] = analyze_model(model_class)
      end

      relationships
    end

    def get_relationship_info(record, relationship_name)
      relationships = analyze_model(record.class)
      relationship = relationships[relationship_name.to_s]
      
      return nil unless relationship

      # Convert to symbols for consistency with expected API
      {
        model_class: relationship['model_class'],
        model_name: relationship['model_name'],
        type: relationship['type'].to_sym
      }
    end

    def build_dependency_graph(models)
      dependency_graph = {}

      models.each do |model_class|
        dependencies = []
        relationships = analyze_model(model_class)

        relationships.each do |name, info|
          if info['type'] == 'belongs_to' && !info['optional']
            dependencies << info['model_class'] unless dependencies.include?(info['model_class'])
          end
        end

        dependency_graph[model_class] = dependencies.uniq
      end

      dependency_graph
    end

    def circular_reference?(model_name, visited)
      visited.include?(model_name)
    end

    private

    def uses_primary_database?(model_class)
      begin
        # Check if the model inherits from a non-primary database class
        return false if inherits_from_non_primary_database?(model_class)
        
        # Get the model's connection
        model_connection = model_class.connection
        
        # Compare connection configurations
        primary_config = @primary_connection.instance_variable_get(:@config) || {}
        model_config = model_connection.instance_variable_get(:@config) || {}
        
        # Check if they're the same connection object
        return true if model_connection == @primary_connection
        
        # Check if they have the same database configuration
        if primary_config.any? && model_config.any?
          # Compare key connection parameters
          same_database = primary_config[:database] == model_config[:database]
          same_host = (primary_config[:host] || 'localhost') == (model_config[:host] || 'localhost')
          same_port = (primary_config[:port] || 5432) == (model_config[:port] || 5432)
          
          return same_database && same_host && same_port
        end
        
        # If we can't determine, check if the connection pool is the same
        primary_pool = ActiveRecord::Base.connection_pool
        model_pool = model_class.connection_pool
        
        return primary_pool == model_pool
        
      rescue StandardError => e
        # If any error occurs (including database connection errors), assume it's not the primary database
        return false
      end
    end

    def inherits_from_non_primary_database?(model_class)
      # Check if the model inherits from known non-primary database classes
      non_primary_classes = [
        'Ops::ReplicaDatabase',
        'Analytics::Base',
        'Reporting::Base',
        'DataWarehouse::Base',
        'External::Base',
        'ThirdParty::Base'
      ]
      
      ancestors = model_class.ancestors.map(&:name).compact
      non_primary_classes.any? { |non_primary_class| ancestors.include?(non_primary_class) }
    rescue StandardError
      # If we can't determine the ancestry, err on the side of caution
      false
    end

    def filter_relationships(relationships)
      relationships.select do |name, info|
        config.model_included?(info['model_name']) &&
          config.relationship_included?(name)
      end
    end

    def should_include_association?(association)
      return false unless config.relationship_included?(association.name.to_s)
      
      # Skip associations that don't have a klass (can happen with polymorphic or broken associations)
      return false unless association.klass
      
      return false unless config.model_included?(association.klass.name)
      
      # Check if the associated model uses the primary database (if enabled)
      if config.skip_non_primary_database_models
        return false unless uses_primary_database?(association.klass)
      end
      
      # Skip polymorphic associations that can't be resolved
      return false if association.polymorphic? && association.foreign_type.nil?
      
      true
    rescue NameError
      # Skip associations that reference non-existent models
      false
    rescue StandardError => e
      # Skip associations that cause database connection errors
      if e.message.include?('Unknown database') || e.message.include?('database connection')
        return false
      end
      raise e unless config.skip_missing_models
    end

    def build_relationship_info(association)
      {
        type: association.macro,
        class_name: association.klass&.name,
        foreign_key: association.foreign_key,
        primary_key: association.association_primary_key,
        polymorphic: association.polymorphic?,
        through: association.through_reflection&.name,
        source: association.source_reflection&.name,
        dependent: association.options[:dependent],
        inverse_of: association.inverse_of&.name
      }
    end

    def traverse_for_dependencies(model_class, dependency_graph, path)
      model_name = model_class.name
      
      # Detect circular references
      if path.include?(model_name)
        handle_circular_reference(model_name, path)
        return
      end
      
      return if dependency_graph.key?(model_name)
      
      dependencies = []
      current_path = path + [model_name]
      
      model_class.reflect_on_all_associations.each do |association|
        next unless should_include_association?(association)
        next if association.macro == :has_many || association.macro == :has_one
        
        # Only belongs_to creates dependencies
        if association.macro == :belongs_to
          # Skip if klass is nil (can happen with polymorphic associations)
          next unless association.klass
          
          associated_class = association.klass
          dependencies << associated_class.name
          
          # Recursively analyze dependencies
          traverse_for_dependencies(associated_class, dependency_graph, current_path)
        end
      end
      
      dependency_graph[model_name] = dependencies.uniq
    end

    def handle_circular_reference(model_name, path)
      cycle_start = path.index(model_name)
      cycle = path[cycle_start..-1] + [model_name]
      
      @circular_paths << cycle
      
      case config.circular_reference_strategy
      when :error
        raise CircularReferenceError.new(
          "Circular reference detected: #{cycle.join(' -> ')}",
          model: model_name
        )
      when :skip
        # Simply skip this path
        return
      when :break_at_depth
        return if path.length >= config.max_circular_depth
      end
    end

    def get_custom_rules(from_model, to_model)
      config.custom_traversal_rules.dig(from_model, to_model) || {}
    end
  end
end 