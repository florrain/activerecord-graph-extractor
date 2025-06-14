# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveRecordGraphExtractor::RelationshipAnalyzer do
  let(:analyzer) { described_class.new }

  describe '#analyze_model' do
    context 'with TestOrder model' do
      it 'analyzes all relationships correctly' do
        relationships = analyzer.analyze_model(TestOrder)

        expect(relationships).to be_a(Hash)
        expect(relationships).to include(
          'test_user',
          'test_partner',
          'test_address',
          'test_products',
          'test_admin_actions',
          'test_order_flag'
        )
      end

      it 'identifies belongs_to relationships' do
        relationships = analyzer.analyze_model(TestOrder)

        expect(relationships['test_user']['type']).to eq('belongs_to')
        expect(relationships['test_partner']['type']).to eq('belongs_to')
        expect(relationships['test_address']['type']).to eq('belongs_to')
      end

      it 'identifies has_many relationships' do
        relationships = analyzer.analyze_model(TestOrder)

        expect(relationships['test_products']['type']).to eq('has_many')
        expect(relationships['test_admin_actions']['type']).to eq('has_many')
      end

      it 'identifies has_one relationships' do
        relationships = analyzer.analyze_model(TestOrder)

        expect(relationships['test_order_flag']['type']).to eq('has_one')
      end

      it 'includes model class information' do
        relationships = analyzer.analyze_model(TestOrder)

        expect(relationships['test_user']['model_class']).to eq(TestUser)
        expect(relationships['test_user']['model_name']).to eq('TestUser')
      end

      it 'identifies optional relationships' do
        relationships = analyzer.analyze_model(TestOrder)

        expect(relationships['test_user']['optional']).to be false
      end
    end

    context 'with TestProduct model' do
      it 'analyzes all relationships correctly' do
        relationships = analyzer.analyze_model(TestProduct)

        expect(relationships).to be_a(Hash)
        expect(relationships).to include(
          'test_order',
          'test_category',
          'test_photos'
        )
      end

      it 'identifies belongs_to relationships' do
        relationships = analyzer.analyze_model(TestProduct)

        expect(relationships['test_order']['type']).to eq('belongs_to')
        expect(relationships['test_category']['type']).to eq('belongs_to')
      end

      it 'identifies has_many relationships' do
        relationships = analyzer.analyze_model(TestProduct)

        expect(relationships['test_photos']['type']).to eq('has_many')
      end
    end

    context 'with TestUser model' do
      it 'analyzes all relationships correctly' do
        relationships = analyzer.analyze_model(TestUser)

        expect(relationships).to be_a(Hash)
        expect(relationships).to include(
          'test_orders',
          'test_profile',
          'test_history_records'
        )
      end

      it 'identifies has_many relationships' do
        relationships = analyzer.analyze_model(TestUser)

        expect(relationships['test_orders']['type']).to eq('has_many')
        expect(relationships['test_history_records']['type']).to eq('has_many')
      end

      it 'identifies has_one relationships' do
        relationships = analyzer.analyze_model(TestUser)

        expect(relationships['test_profile']['type']).to eq('has_one')
      end
    end

    it 'handles models without relationships' do
      relationships = analyzer.analyze_model(TestOrderFlag)
      expect(relationships).to have_key('test_order')
      expect(relationships['test_order']['type']).to eq('belongs_to')
    end

    it 'handles invalid model classes' do
      expect { analyzer.analyze_model(String) }.to raise_error(
        ActiveRecordGraphExtractor::ExtractionError
      )
    end

    it 'handles complex relationships' do
      order = create(:test_order_with_relationships)
      
      # Analyze relationships for the order
      relationships = analyzer.analyze_model(order.class)
      expect(relationships).to have_key('test_user')
      expect(relationships).to have_key('test_products')
      
      # Analyze relationships for the user
      user_relationships = analyzer.analyze_model(TestUser)
      expect(user_relationships).to have_key('test_orders')
      expect(user_relationships).to have_key('test_profile')
    end

    it 'handles complex relationships with factory' do
      order = create(:test_order_with_relationships)
      
      # Analyze relationships for the order
      relationships = analyzer.analyze_model(order.class)
      expect(relationships).to have_key('test_user')
      expect(relationships).to have_key('test_products')
      
      # Analyze relationships for the user
      user_relationships = analyzer.analyze_model(TestUser)
      expect(user_relationships).to have_key('test_orders')
      expect(user_relationships).to have_key('test_profile')
    end
  end

  describe '#analyze_models' do
    it 'analyzes multiple models' do
      relationships = analyzer.analyze_models([TestOrder, TestProduct, TestUser])

      expect(relationships).to be_a(Hash)
      expect(relationships).to include(
        'TestOrder',
        'TestProduct',
        'TestUser'
      )

      expect(relationships['TestOrder']).to include(
        'test_user',
        'test_products'
      )

      expect(relationships['TestProduct']).to include(
        'test_order',
        'test_photos'
      )

      expect(relationships['TestUser']).to include(
        'test_orders',
        'test_profile'
      )
    end

    it 'handles empty model list' do
      relationships = analyzer.analyze_models([])
      expect(relationships).to be_empty
    end

    it 'handles invalid model classes' do
      expect { analyzer.analyze_models([String]) }.to raise_error(
        ActiveRecordGraphExtractor::ExtractionError
      )
    end
  end

  describe '#get_relationship_info' do
    let(:test_order) { create(:test_order) }

    it 'returns relationship information with target model' do
      info = analyzer.get_relationship_info(test_order, 'test_user')
      
      expect(info[:model_class]).to eq(TestUser)
      expect(info[:model_name]).to eq('TestUser')
      expect(info[:type]).to eq(:belongs_to)
    end

    it 'returns nil for non-existent relationships' do
      info = analyzer.get_relationship_info(test_order, 'non_existent')
      expect(info).to be_nil
    end
  end

  describe '#build_dependency_graph' do
    let(:models) { [TestUser, TestOrder, TestProduct, TestCategory] }

    it 'builds a dependency graph of models' do
      graph = analyzer.build_dependency_graph(models)
      
      expect(graph).to be_a(Hash)
      expect(graph.keys.map(&:to_s)).to include('TestUser', 'TestOrder', 'TestProduct', 'TestCategory')
    end

    it 'includes dependencies in the graph' do
      graph = analyzer.build_dependency_graph(models)
      
      # TestOrder depends on TestUser
      order_deps = graph[TestOrder]
      expect(order_deps).to include(TestUser)
      
      # TestProduct depends on TestOrder (TestCategory is optional)
      product_deps = graph[TestProduct]
      expect(product_deps).to include(TestOrder)
      expect(product_deps).not_to include(TestCategory)
    end

    it 'handles models with no dependencies' do
      graph = analyzer.build_dependency_graph([TestUser, TestCategory])
      
      expect(graph[TestUser]).to be_empty
      expect(graph[TestCategory]).to be_empty
    end
  end

  describe '#circular_reference?' do
    let(:visited) { Set.new(['TestUser', 'TestOrder']) }

    it 'detects circular references' do
      expect(analyzer.circular_reference?('TestUser', visited)).to be(true)
    end

    it 'returns false for non-circular references' do
      expect(analyzer.circular_reference?('TestProduct', visited)).to be(false)
    end
  end

  describe '#filter_relationships' do
    let(:relationships) do
      {
        'test_user' => { 'type' => 'belongs_to', 'model_name' => 'TestUser' },
        'test_products' => { 'type' => 'has_many', 'model_name' => 'TestProduct' },
        'test_partner' => { 'type' => 'belongs_to', 'model_name' => 'TestPartner' }
      }
    end

    context 'with model filters' do
      it 'excludes relationships to excluded models' do
        config = double('config')
        allow(config).to receive(:model_included?) { |model| model != 'TestPartner' }
        allow(config).to receive(:relationship_included?) { |_| true }
        analyzer = described_class.new(config)
        
        filtered = analyzer.send(:filter_relationships, relationships)
        expect(filtered.keys).not_to include('test_partner')
        expect(filtered.keys).to include('test_user', 'test_products')
      end
    end

    context 'with relationship filters' do
      it 'excludes filtered relationships' do
        config = double('config')
        allow(config).to receive(:model_included?) { |_| true }
        allow(config).to receive(:relationship_included?) { |rel| rel != 'test_products' }
        analyzer = described_class.new(config)
        
        filtered = analyzer.send(:filter_relationships, relationships)
        expect(filtered.keys).not_to include('test_products')
        expect(filtered.keys).to include('test_user', 'test_partner')
      end
    end
  end

  describe 'integration with real models' do
    it 'analyzes complex model hierarchies' do
      order = create(:test_order_with_relationships)
      
      relationships = analyzer.analyze_model(order.class)
      
      expect(relationships).to have_key('test_user')
      expect(relationships).to have_key('test_products')
      expect(relationships).to have_key('test_admin_actions')
      
      # Verify we can traverse to related models
      user_relationships = analyzer.analyze_model(TestUser)
      expect(user_relationships).to have_key('test_orders')
    end
  end
end 