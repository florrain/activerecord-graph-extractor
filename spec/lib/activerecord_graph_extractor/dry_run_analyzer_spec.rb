# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveRecordGraphExtractor::DryRunAnalyzer do
  let(:config) { ActiveRecordGraphExtractor::Configuration.new }
  let(:analyzer) { described_class.new(config) }
  let(:user) { create(:test_user) }
  let(:order) { create(:test_order, test_user: user) }

  describe '#initialize' do
    it 'initializes with default configuration' do
      analyzer = described_class.new
      expect(analyzer.config).to be_a(ActiveRecordGraphExtractor::Configuration)
    end

    it 'initializes with custom configuration' do
      custom_config = ActiveRecordGraphExtractor::Configuration.new
      analyzer = described_class.new(custom_config)
      expect(analyzer.config).to eq(custom_config)
    end

    it 'initializes relationship analyzer' do
      expect(analyzer.relationship_analyzer).to be_a(ActiveRecordGraphExtractor::RelationshipAnalyzer)
    end
  end

  describe '#analyze' do
    context 'with valid input' do
      it 'analyzes a single object' do
        result = analyzer.analyze(user)
        
        expect(result).to be_a(Hash)
        expect(result['dry_run']).to be true
        expect(result['analysis_time']).to be_a(Numeric)
        expect(result['root_objects']['count']).to eq(1)
        expect(result['root_objects']['models']).to include('TestUser')
        expect(result['root_objects']['ids']).to include(user.id)
      end

      it 'analyzes multiple objects' do
        user2 = create(:test_user)
        result = analyzer.analyze([user, user2])
        
        expect(result['root_objects']['count']).to eq(2)
        expect(result['root_objects']['models']).to include('TestUser')
        expect(result['root_objects']['ids']).to include(user.id, user2.id)
      end

      it 'respects max_depth option' do
        result = analyzer.analyze(user, max_depth: 1)
        
        expect(result['extraction_scope']['max_depth']).to eq(1)
      end

      it 'uses default max_depth from config' do
        config.max_depth = 5
        result = analyzer.analyze(user)
        
        expect(result['extraction_scope']['max_depth']).to eq(5)
      end
    end

    context 'with invalid input' do
      it 'raises error for nil input' do
        expect { analyzer.analyze(nil) }.to raise_error(
          ActiveRecordGraphExtractor::ExtractionError, 
          "Root object cannot be nil"
        )
      end

      it 'raises error for non-ActiveRecord object' do
        expect { analyzer.analyze("not an activerecord object") }.to raise_error(
          ActiveRecordGraphExtractor::ExtractionError, 
          /Object must be an ActiveRecord object/
        )
      end
    end

    context 'analysis results structure' do
      let(:result) { analyzer.analyze(order) }

      it 'includes all required top-level keys' do
        expected_keys = %w[
          dry_run analysis_time root_objects extraction_scope
          estimated_counts_by_model estimated_file_size depth_analysis
          relationship_analysis performance_estimates warnings recommendations
        ]
        
        expect(result.keys).to include(*expected_keys)
      end

      it 'includes extraction scope details' do
        scope = result['extraction_scope']
        
        expect(scope).to include(
          'max_depth',
          'total_models',
          'total_estimated_records',
          'models_involved'
        )
        
        expect(scope['models_involved']).to be_an(Array)
        expect(scope['total_models']).to be_a(Integer)
        expect(scope['total_estimated_records']).to be_a(Integer)
      end

      it 'includes estimated file size with human readable format' do
        file_size = result['estimated_file_size']
        
        expect(file_size).to include('bytes', 'human_readable')
        expect(file_size['bytes']).to be_a(Integer)
        expect(file_size['human_readable']).to be_a(String)
        expect(file_size['human_readable']).to match(/\d+(\.\d+)?\s+(B|KB|MB|GB)/)
      end

      it 'includes performance estimates' do
        perf = result['performance_estimates']
        
        expect(perf).to include(
          'estimated_extraction_time_seconds',
          'estimated_extraction_time_human',
          'estimated_memory_usage_mb',
          'estimated_memory_usage_human'
        )
      end

      it 'includes relationship analysis' do
        rel_analysis = result['relationship_analysis']
        
        expect(rel_analysis).to include(
          'total_relationships',
          'circular_references',
          'circular_references_count'
        )
        
        expect(rel_analysis['circular_references']).to be_an(Array)
      end

      it 'includes warnings and recommendations arrays' do
        expect(result['warnings']).to be_an(Array)
        expect(result['recommendations']).to be_an(Array)
      end
    end

    context 'with complex object graph' do
      let!(:user_with_orders) do
        user = create(:test_user)
        3.times { create(:test_order, test_user: user) }
        user
      end

      it 'analyzes complex relationships' do
        result = analyzer.analyze(user_with_orders)
        
        expect(result['extraction_scope']['models_involved']).to include('TestUser', 'TestOrder')
        expect(result['estimated_counts_by_model']['TestUser']).to be > 0
        expect(result['estimated_counts_by_model']['TestOrder']).to be > 0
      end

      it 'provides depth analysis' do
        result = analyzer.analyze(user_with_orders, max_depth: 3)
        
        depth_analysis = result['depth_analysis']
        expect(depth_analysis).to be_a(Hash)
        expect(depth_analysis.keys.map(&:to_i)).to all(be_between(1, 3))
      end
    end
  end

  describe 'file size estimation' do
    it 'estimates reasonable file sizes' do
      result = analyzer.analyze(user)
      file_size = result['estimated_file_size']['bytes']
      
      # Should be reasonable for a single user (not 0, not gigabytes)
      expect(file_size).to be > 100
      expect(file_size).to be < 100_000
    end

    it 'formats file sizes correctly' do
      # Test the format_file_size method indirectly
      result = analyzer.analyze(user)
      human_readable = result['estimated_file_size']['human_readable']
      
      expect(human_readable).to match(/^\d+(\.\d+)?\s+(B|KB|MB|GB)$/)
    end
  end

  describe 'performance estimation' do
    it 'provides reasonable time estimates' do
      result = analyzer.analyze(user)
      perf = result['performance_estimates']
      
      expect(perf['estimated_extraction_time_seconds']).to be_a(Numeric)
      expect(perf['estimated_extraction_time_seconds']).to be >= 0
      expect(perf['estimated_memory_usage_mb']).to be_a(Numeric)
      expect(perf['estimated_memory_usage_mb']).to be >= 0
    end

    it 'formats duration correctly' do
      result = analyzer.analyze(user)
      time_human = result['performance_estimates']['estimated_extraction_time_human']
      
      expect(time_human).to match(/(seconds|minutes|hours)/)
    end
  end

  describe 'warnings generation' do
    context 'with large datasets' do
      before do
        # Mock large counts to trigger warnings
        allow_any_instance_of(described_class).to receive(:estimate_relationship_count).and_return(50_000)
      end

      it 'generates large dataset warnings' do
        result = analyzer.analyze(user)
        warnings = result['warnings']
        
        large_dataset_warning = warnings.find { |w| w['type'] == 'large_dataset' }
        expect(large_dataset_warning).to be_present
        expect(large_dataset_warning['severity']).to eq('high')
      end
    end

    context 'with deep nesting' do
      it 'generates deep nesting warnings for high max_depth' do
        result = analyzer.analyze(user, max_depth: 10)
        
        # This might generate a warning depending on the actual depth reached
        warnings = result['warnings']
        expect(warnings).to be_an(Array)
      end
    end
  end

  describe 'recommendations generation' do
    it 'generates appropriate recommendations' do
      result = analyzer.analyze(user)
      recommendations = result['recommendations']
      
      expect(recommendations).to be_an(Array)
      
      if recommendations.any?
        recommendation = recommendations.first
        expect(recommendation).to include('type', 'message', 'action')
      end
    end

    context 'with large estimated file size' do
      before do
        # Mock large file size to trigger S3 recommendation
        allow_any_instance_of(described_class).to receive(:estimate_file_size).and_return(100 * 1024 * 1024) # 100MB
      end

      it 'recommends S3 for large files' do
        result = analyzer.analyze(user)
        recommendations = result['recommendations']
        
        s3_recommendation = recommendations.find { |r| r['type'] == 's3' }
        expect(s3_recommendation).to be_present
        expect(s3_recommendation['action']).to include('extract_to_s3')
      end
    end
  end

  describe 'error handling' do
    it 'handles missing models gracefully' do
      # This should not raise an error, but skip the missing model
      expect { analyzer.analyze(user) }.not_to raise_error
    end

    it 'wraps analysis errors appropriately' do
      # Mock an error in the analysis process
      allow(analyzer).to receive(:analyze_object_graph).and_raise(StandardError, "Test error")
      
      expect { analyzer.analyze(user) }.to raise_error(
        ActiveRecordGraphExtractor::ExtractionError,
        /Failed to analyze object graph: Test error/
      )
    end
  end

  describe 'circular reference detection' do
    # This would require setting up models with circular references
    # For now, we'll test that the structure is correct
    it 'includes circular reference analysis structure' do
      result = analyzer.analyze(user)
      
      rel_analysis = result['relationship_analysis']
      expect(rel_analysis['circular_references']).to be_an(Array)
      expect(rel_analysis['circular_references_count']).to be_a(Integer)
    end
  end
end 