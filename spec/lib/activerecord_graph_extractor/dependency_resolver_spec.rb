# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveRecordGraphExtractor::DependencyResolver do
  let(:resolver) { described_class.new({}) }

  describe '#resolve' do
    let(:sample_graph) do
      {
        TestUser => [TestPartner],      # User depends on Partner
        TestPartner => [],              # Partner has no dependencies
        TestOrder => [TestUser, TestAddress], # Order depends on User and Address
        TestAddress => [TestUser],      # Address depends on User
        TestProduct => [TestOrder, TestCategory], # Product depends on Order and Category
        TestCategory => []              # Category has no dependencies
      }
    end

    it 'returns models in dependency order' do
      ordered = resolver.resolve(sample_graph)
      
      # Models with no dependencies should come first (flexible order)
      no_deps_models = [TestPartner, TestCategory]
      expect(ordered[0..1]).to contain_exactly(*no_deps_models)
      
      # User should come after Partner (if Partner is a dependency)
      partner_index = ordered.index(TestPartner)
      user_index = ordered.index(TestUser)
      expect(user_index).to be > partner_index
      
      # Address should come after User
      address_index = ordered.index(TestAddress)
      expect(address_index).to be > user_index
      
      # Order should come after both User and Address
      order_index = ordered.index(TestOrder)
      expect(order_index).to be > user_index
      expect(order_index).to be > address_index
      
      # Product should come after both Order and Category
      product_index = ordered.index(TestProduct)
      expect(product_index).to be > order_index
      category_index = ordered.index(TestCategory)
      expect(product_index).to be > category_index
    end

    it 'handles models with no dependencies' do
      simple_graph = {
        TestUser => [],
        TestPartner => []
      }
      
      ordered = resolver.resolve(simple_graph)
      expect(ordered).to contain_exactly(TestUser, TestPartner)
    end

    it 'handles empty graph' do
      ordered = resolver.resolve({})
      expect(ordered).to be_empty
    end

    it 'raises error for circular dependencies' do
      circular_graph = {
        TestUser => [TestOrder],
        TestOrder => [TestUser]
      }
      
      expect { resolver.resolve(circular_graph) }.to raise_error(
        ActiveRecordGraphExtractor::CircularDependencyError,
        /Circular dependency detected/
      )
    end

    it 'handles complex dependency chains' do
      # Create a more complex dependency chain
      complex_graph = {
        TestUser => [],
        TestAddress => [TestUser],
        TestOrder => [TestAddress],
        TestProduct => [TestOrder],
        TestPhoto => [TestProduct]
      }
      
      ordered = resolver.resolve(complex_graph)
      
      # Verify the chain order
      expect(ordered.index(TestUser)).to be < ordered.index(TestAddress)
      expect(ordered.index(TestAddress)).to be < ordered.index(TestOrder)
      expect(ordered.index(TestOrder)).to be < ordered.index(TestProduct)
      expect(ordered.index(TestProduct)).to be < ordered.index(TestPhoto)
    end

    it 'detects circular dependencies' do
      graph = {
        'TestOrder' => {
          'test_user' => { 'model_class' => 'TestUser' }
        },
        'TestUser' => {
          'test_order' => { 'model_class' => 'TestOrder' }
        }
      }

      result = resolver.resolve(graph)
      expect(result['circular_dependencies']).to include(
        ['TestOrder', 'TestUser']
      )
    end

    it 'handles complex dependency chains' do
      graph = {
        'TestOrder' => {
          'test_user' => { 'model_class' => 'TestUser' },
          'test_products' => { 'model_class' => 'TestProduct' }
        },
        'TestProduct' => {
          'test_category' => { 'model_class' => 'TestCategory' },
          'test_photos' => { 'model_class' => 'TestPhoto' }
        },
        'TestUser' => {
          'test_profile' => { 'model_class' => 'TestProfile' }
        }
      }

      result = resolver.resolve(graph)
      creation_order = result['creation_order']
      
      # Verify the structure and dependency levels
      expect(creation_order).to be_an(Array)
      expect(creation_order.length).to eq(3)
      
      # Level 0: Models with no dependencies (order within level may vary)
      expect(creation_order[0]).to contain_exactly('TestProfile', 'TestCategory', 'TestPhoto')
      
      # Level 1: Models that depend on level 0 models
      expect(creation_order[1]).to contain_exactly('TestUser', 'TestProduct')
      
      # Level 2: Models that depend on level 1 models
      expect(creation_order[2]).to contain_exactly('TestOrder')
    end

    it 'handles models without dependencies' do
      graph = {
        'TestOrderFlag' => {}
      }

      result = resolver.resolve(graph)
      expect(result['creation_order'].first).to include('TestOrderFlag')
    end

    it 'handles missing models' do
      graph = {
        'TestOrder' => {
          'test_user' => { 'model_class' => 'TestUser' }
        }
      }

      result = resolver.resolve(graph)
      expect(result['missing_models']).to include('TestUser')
    end
  end

  describe '#detect_circular_dependencies' do
    it 'detects simple circular dependencies' do
      circular_graph = {
        TestUser => [TestOrder],
        TestOrder => [TestUser]
      }
      
      expect(resolver.detect_circular_dependencies(circular_graph)).to be(true)
    end

    it 'detects complex circular dependencies' do
      circular_graph = {
        TestUser => [TestAddress],
        TestAddress => [TestOrder],
        TestOrder => [TestUser]
      }
      
      expect(resolver.detect_circular_dependencies(circular_graph)).to be(true)
    end

    it 'returns false for acyclic graphs' do
      acyclic_graph = {
        TestUser => [],
        TestAddress => [TestUser],
        TestOrder => [TestAddress]
      }
      
      expect(resolver.detect_circular_dependencies(acyclic_graph)).to be(false)
    end

    it 'handles self-referencing models' do
      self_ref_graph = {
        TestUser => [TestUser]
      }
      
      expect(resolver.detect_circular_dependencies(self_ref_graph)).to be(true)
    end

    it 'detects direct circular dependencies' do
      graph = {
        'TestOrder' => {
          'test_user' => { 'model_class' => 'TestUser' }
        },
        'TestUser' => {
          'test_order' => { 'model_class' => 'TestOrder' }
        }
      }

      circular = resolver.detect_circular_dependencies(graph)
      expect(circular).to include(['TestOrder', 'TestUser'])
    end

    it 'detects indirect circular dependencies' do
      graph = {
        'TestOrder' => {
          'test_user' => { 'model_class' => 'TestUser' }
        },
        'TestUser' => {
          'test_profile' => { 'model_class' => 'TestProfile' }
        },
        'TestProfile' => {
          'test_order' => { 'model_class' => 'TestOrder' }
        }
      }

      circular = resolver.detect_circular_dependencies(graph)
      expect(circular).to include(['TestOrder', 'TestUser', 'TestProfile'])
    end

    it 'returns empty array for no circular dependencies' do
      graph = {
        'TestOrder' => {
          'test_user' => { 'model_class' => 'TestUser' }
        },
        'TestUser' => {}
      }

      circular = resolver.detect_circular_dependencies(graph)
      expect(circular).to be_empty
    end
  end

  describe '#build_creation_order' do
    let(:records_by_model) do
      {
        'TestUser' => [
          { 'id' => 1, 'email' => 'user1@example.com' },
          { 'id' => 2, 'email' => 'user2@example.com' }
        ],
        'TestOrder' => [
          { 'id' => 1, 'test_user_id' => 1, 'state' => 'processed' }
        ],
        'TestProduct' => [
          { 'id' => 1, 'test_order_id' => 1, 'item_number' => 'ITEM001' }
        ]
      }
    end

    let(:dependency_graph) do
      {
        TestUser => [],
        TestOrder => [TestUser],
        TestProduct => [TestOrder]
      }
    end

    it 'orders records by dependency graph' do
      ordered_records = resolver.build_creation_order(records_by_model, dependency_graph)
      
      expect(ordered_records).to be_an(Array)
      expect(ordered_records.size).to eq(3)
      
      # Users should be first
      expect(ordered_records[0][0]).to eq('TestUser')
      expect(ordered_records[0][1].size).to eq(2)
      
      # Orders should be second
      expect(ordered_records[1][0]).to eq('TestOrder')
      expect(ordered_records[1][1].size).to eq(1)
      
      # Products should be last
      expect(ordered_records[2][0]).to eq('TestProduct')
      expect(ordered_records[2][1].size).to eq(1)
    end

    it 'handles missing models in dependency graph' do
      partial_graph = {
        TestUser => [],
        TestOrder => [TestUser]
      }
      
      ordered_records = resolver.build_creation_order(records_by_model, partial_graph)
      
      expect(ordered_records.size).to eq(3)
      model_names = ordered_records.map(&:first)
      expect(model_names).to include('TestUser', 'TestOrder', 'TestProduct')
    end

    it 'builds correct creation order' do
      ordered_records = resolver.build_creation_order(records_by_model, dependency_graph)
      
      # Verify the overall structure
      expect(ordered_records).to be_an(Array)
      expect(ordered_records.size).to eq(3)
      
      # Each entry should be [model_name, records_array]
      ordered_records.each do |entry|
        expect(entry).to be_an(Array)
        expect(entry.size).to eq(2)
        expect(entry[0]).to be_a(String)
        expect(entry[1]).to be_an(Array)
      end
    end

    it 'handles independent models' do
      independent_records = {
        'TestUser' => [{ 'id' => 1, 'email' => 'user@example.com' }],
        'TestCategory' => [{ 'id' => 1, 'name' => 'category' }]
      }
      
      independent_graph = {
        TestUser => [],
        TestCategory => []
      }
      
      ordered_records = resolver.build_creation_order(independent_records, independent_graph)
      
      expect(ordered_records.size).to eq(2)
      model_names = ordered_records.map(&:first)
      expect(model_names).to contain_exactly('TestUser', 'TestCategory')
    end
  end

  describe 'integration with real models' do
    it 'resolves dependencies for test models correctly' do
      # Create a real dependency graph using the relationship analyzer
      analyzer = ActiveRecordGraphExtractor::RelationshipAnalyzer.new
      models = [TestUser, TestAddress, TestOrder, TestProduct, TestCategory]
      
      dependency_graph = analyzer.build_dependency_graph(models)
      ordered_models = resolver.resolve(dependency_graph)
      
      # Verify that dependencies are satisfied
      models_with_no_deps = [TestUser, TestCategory]
      models_with_no_deps.each do |model|
        expect(ordered_models.index(model)).to be < ordered_models.index(TestOrder)
      end
      
      expect(ordered_models.index(TestOrder)).to be < ordered_models.index(TestProduct)
    end

    it 'handles real record creation order' do
      # Create test data
      user = create(:test_user)
      order = create(:test_order, test_user: user)
      product = create(:test_product, test_order: order)
      
      # Simulate extracted records
      records = [
        { '_model' => 'TestProduct', 'id' => product.id, 'test_order_id' => order.id },
        { '_model' => 'TestOrder', 'id' => order.id, 'test_user_id' => user.id },
        { '_model' => 'TestUser', 'id' => user.id, 'email' => user.email }
      ]
      
      # Build dependency graph
      analyzer = ActiveRecordGraphExtractor::RelationshipAnalyzer.new
      models = [TestUser, TestOrder, TestProduct]
      dependency_graph = analyzer.build_dependency_graph(models)
      
      # Get creation order
      ordered_records = resolver.build_creation_order(
        resolver.send(:group_records_by_dependencies, records),
        dependency_graph
      )
      
      # Verify order
      expect(ordered_records[0][0]).to eq('TestUser')
      expect(ordered_records[1][0]).to eq('TestOrder')
      expect(ordered_records[2][0]).to eq('TestProduct')
    end
  end
end 