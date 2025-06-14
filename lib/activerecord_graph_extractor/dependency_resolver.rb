# frozen_string_literal: true

module ActiveRecordGraphExtractor
  class DependencyResolver
    attr_reader :dependency_graph, :resolved_order

    def initialize(dependency_graph)
      @dependency_graph = dependency_graph
      @resolved_order = []
    end

    def resolve_creation_order
      # Create a copy to avoid modifying the original
      graph = dependency_graph.dup
      visited = Set.new
      temp_visited = Set.new
      
      graph.keys.each do |model|
        next if visited.include?(model)
        
        visit_model(model, graph, visited, temp_visited)
      end
      
      # Reverse to get creation order (dependencies first)
      @resolved_order.reverse
    end

    def resolve_deletion_order
      # For deletion, we want the reverse of creation order
      resolve_creation_order.reverse
    end

    def validate_dependencies(records_data)
      missing_dependencies = {}
      
      records_data.each do |model_name, records|
        next unless dependency_graph[model_name]
        
        dependency_graph[model_name].each do |dependency|
          unless records_data.key?(dependency)
            missing_dependencies[model_name] ||= []
            missing_dependencies[model_name] << dependency
          end
        end
      end
      
      return missing_dependencies if missing_dependencies.any?
      
      # Validate foreign key references
      validate_foreign_key_references(records_data)
    end

    def group_by_dependency_level
      creation_order = resolve_creation_order
      levels = {}
      current_level = 0
      
      creation_order.each do |model_name|
        dependencies = dependency_graph[model_name] || []
        
        if dependencies.empty?
          # No dependencies - can be created first
          levels[current_level] ||= []
          levels[current_level] << model_name
        else
          # Find the maximum level of dependencies
          max_dependency_level = dependencies.map do |dep|
            find_model_level(dep, levels)
          end.max || 0
          
          model_level = max_dependency_level + 1
          levels[model_level] ||= []
          levels[model_level] << model_name
        end
      end
      
      levels
    end

    def resolve(dependency_graph)
      # Handle different input formats based on test expectations
      if dependency_graph.values.first.is_a?(Hash)
        # New format: { 'TestOrder' => { 'test_user' => { 'model_class' => 'TestUser' } } }
        return resolve_complex_graph(dependency_graph)
      end
      
      # Original format: { TestOrder => [TestUser] }
      return [] if dependency_graph.empty?

      # Check for circular dependencies
      if detect_circular_dependencies(dependency_graph)
        raise CircularDependencyError, "Circular dependency detected in model relationships"
      end

      # Perform topological sort
      topological_sort(dependency_graph)
    end

    def detect_circular_dependencies(dependency_graph)
      # Handle different formats
      if dependency_graph.values.first.is_a?(Hash)
        return detect_complex_circular_dependencies(dependency_graph)
      end
      
      # Original boolean detection
      visited = Set.new
      rec_stack = Set.new

      dependency_graph.each_key do |node|
        next if visited.include?(node)
        return true if has_cycle?(node, dependency_graph, visited, rec_stack)
      end

      false
    end

    def build_creation_order(records_by_model, dependency_graph)
      grouped_records = group_records_by_dependencies(records_by_model)
      ordered_models = resolve(dependency_graph)
      
      # Create ordered list of [model_name, records] pairs
      ordered_records = []
      
      ordered_models.each do |model_class|
        model_name = model_class.name
        if grouped_records.key?(model_name)
          ordered_records << [model_name, grouped_records[model_name]]
        end
      end
      
      # Add any remaining models not in dependency graph
      grouped_records.each do |model_name, records|
        unless ordered_records.any? { |entry| entry[0] == model_name }
          ordered_records << [model_name, records]
        end
      end
      
      ordered_records
    end

    private

    def visit_model(model, graph, visited, temp_visited)
      return if visited.include?(model)
      
      if temp_visited.include?(model)
        raise DependencyError.new(
          "Circular dependency detected involving #{model}",
          model: model
        )
      end
      
      temp_visited << model
      
      dependencies = graph[model] || []
      dependencies.each do |dependency|
        visit_model(dependency, graph, visited, temp_visited)
      end
      
      temp_visited.delete(model)
      visited << model
      @resolved_order << model
    end

    def validate_foreign_key_references(records_data)
      missing_references = {}
      
      records_data.each do |model_name, records|
        records.each do |record|
          record_relationships = record[:relationships] || {}
          
          record_relationships.each do |field, reference|
            referenced_table = reference[:table]
            referenced_id = reference[:original_id]
            
            # Check if the referenced record exists in the data
            referenced_records = records_data[referenced_table]
            if referenced_records.nil?
              missing_references[model_name] ||= []
              missing_references[model_name] << {
                record_id: record[:original_id],
                field: field,
                references: reference
              }
              next
            end
            
            # Check if specific record exists
            referenced_record = referenced_records.find do |r|
              r[:original_id] == referenced_id
            end
            
            unless referenced_record
              missing_references[model_name] ||= []
              missing_references[model_name] << {
                record_id: record[:original_id],
                field: field,
                references: reference
              }
            end
          end
        end
      end
      
      missing_references
    end

    def find_model_level(model_name, levels)
      levels.each do |level, models|
        return level if models.include?(model_name)
      end
      
      -1 # Not found, should be level 0
    end

    def topological_sort(dependency_graph)
      # Create a copy to avoid modifying original
      graph = dependency_graph.dup
      in_degree = {}
      
      # Initialize in-degree count for all nodes
      graph.each_key do |node|
        in_degree[node] = 0
      end
      
      # Calculate in-degree: how many things depend on each node
      graph.each do |node, dependencies|
        # This node depends on 'dependencies', so this node has in-degree = dependencies.count
        in_degree[node] = dependencies.count { |dep| graph.key?(dep) }
      end

      # Start with nodes that have no dependencies (in-degree 0)
      queue = in_degree.select { |_, degree| degree == 0 }.keys
      result = []

      while queue.any?
        # Sort to ensure consistent ordering
        current = queue.sort_by(&:name).first
        queue.delete(current)
        result << current

        # For each node that depends on the current node, decrease its in-degree
        graph.each do |node, dependencies|
          if dependencies.include?(current)
            in_degree[node] -= 1
            queue << node if in_degree[node] == 0 && !result.include?(node) && !queue.include?(node)
          end
        end
      end

      result
    end

    def has_cycle?(node, graph, visited, rec_stack)
      visited.add(node)
      rec_stack.add(node)

      graph[node]&.each do |neighbor|
        if !visited.include?(neighbor)
          return true if has_cycle?(neighbor, graph, visited, rec_stack)
        elsif rec_stack.include?(neighbor)
          return true
        end
      end

      rec_stack.delete(node)
      false
    end

    def group_records_by_dependencies(records)
      if records.is_a?(Array)
        # Convert array of records to hash grouped by model
        grouped = {}
        records.each do |record|
          raise InvalidRecordError, "Record missing _model key: #{record.inspect}" unless record.key?('_model')
          
          model_name = record['_model']
          grouped[model_name] ||= []
          grouped[model_name] << record
        end
        grouped
      else
        # Assume it's already grouped by model
        records
      end
    end

    def resolve_complex_graph(dependency_graph)
      # Build simple dependency graph from complex format
      simple_graph = {}
      missing_models = []
      all_referenced_models = Set.new
      
      # Collect all models that are referenced as dependencies
      dependency_graph.each do |model_name, relationships|
        simple_graph[model_name] = []
        
        relationships.each do |_relationship_name, relationship_info|
          dep_model = relationship_info['model_class']
          simple_graph[model_name] << dep_model
          all_referenced_models.add(dep_model)
        end
      end
      
      # Add missing models with no dependencies
      all_referenced_models.each do |model_name|
        unless dependency_graph.key?(model_name)
          missing_models << model_name
          simple_graph[model_name] = []  # Missing models have no dependencies
        end
      end
      
      # Detect circular dependencies
      circular_deps = detect_complex_circular_dependencies(dependency_graph)
      
      # Create levels for creation order
      levels = group_models_by_dependency_level(simple_graph)
      
      {
        'creation_order' => levels,
        'circular_dependencies' => circular_deps,
        'missing_models' => missing_models.uniq
      }
    end

    def detect_complex_circular_dependencies(dependency_graph)
      circular_deps = []
      visited = Set.new
      
      dependency_graph.each_key do |model_name|
        next if visited.include?(model_name)
        
        path = []
        circular_path = find_circular_path(model_name, dependency_graph, visited, Set.new, path)
        if circular_path
          # Remove the duplicate end node that creates the cycle
          clean_cycle = circular_path[0..-2]
          circular_deps << clean_cycle unless circular_deps.any? { |cycle| cycle.sort == clean_cycle.sort }
        end
      end
      
      circular_deps
    end
    
    def find_circular_path(model_name, dependency_graph, global_visited, local_visited, path)
      return nil if global_visited.include?(model_name)
      
      if local_visited.include?(model_name)
        # Found a cycle, extract the circular portion
        cycle_start = path.index(model_name)
        return nil unless cycle_start
        
        circular_path = path[cycle_start..-1] + [model_name]
        return circular_path
      end
      
      local_visited.add(model_name)
      path << model_name
      
      relationships = dependency_graph[model_name] || {}
      relationships.each do |_rel_name, rel_info|
        dep_model = rel_info['model_class']
        next unless dependency_graph.key?(dep_model)
        
        result = find_circular_path(dep_model, dependency_graph, global_visited, local_visited, path)
        if result
          local_visited.delete(model_name)
          path.pop
          return result
        end
      end
      
      local_visited.delete(model_name)
      path.pop
      global_visited.add(model_name)
      nil
    end
    
    def group_models_by_dependency_level(simple_graph)
      levels = []
      processed = Set.new
      
      # Continue until all models are processed
      while processed.size < simple_graph.size
        current_level = []
        
        simple_graph.each do |model_name, dependencies|
          next if processed.include?(model_name)
          
          # Check if all dependencies are already processed
          if dependencies.all? { |dep| processed.include?(dep) }
            current_level << model_name
          end
        end
        
        # If no models can be processed, we have a circular dependency
        break if current_level.empty?
        
        levels << current_level
        current_level.each { |model| processed.add(model) }
      end
      
      levels
    end
  end
end 