# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveRecordGraphExtractor do
  it 'has a version number' do
    expect(ActiveRecordGraphExtractor::VERSION).not_to be nil
  end

  describe '.configuration' do
    it 'returns the global configuration instance' do
      expect(described_class.configuration).to be_a(ActiveRecordGraphExtractor::Configuration)
    end

    it 'returns the same instance on multiple calls' do
      config1 = described_class.configuration
      config2 = described_class.configuration
      expect(config1).to equal(config2)
    end
  end

  describe '.configure' do
    before do
      described_class.configuration.reset!
    end

    it 'yields the configuration for setup' do
      expect { |b| described_class.configure(&b) }.to yield_with_args(described_class.configuration)
    end

    it 'allows configuration setup' do
      described_class.configure do |config|
        config.max_depth = 3
        config.batch_size = 500
        config.exclude_model('TestCategory')
      end

      config = described_class.configuration
      expect(config.max_depth).to eq(3)
      expect(config.batch_size).to eq(500)
      expect(config.excluded_models).to include('TestCategory')
    end
  end

  describe 'end-to-end functionality' do
    let(:user) { create(:test_user) }
    let(:partner) { create(:test_partner) }
    let(:address) { create(:test_address, test_user: user) }
    let(:category) { create(:test_category) }
    let(:order) { create(:test_order, test_user: user, test_partner: partner, test_address: address) }
    let(:product) { create(:test_product, test_order: order, test_category: category) }
    let(:photo) { create(:test_photo, test_product: product) }
    let(:admin_action) { create(:test_admin_action, test_order: order) }
    let(:order_flag) { create(:test_order_flag, test_order: order) }

    before do
      # Create the full object graph
      photo # This triggers creation of all dependencies
      admin_action
      order_flag
    end

    it 'extracts and imports a complete object graph' do
      # Reset configuration to ensure clean state
      described_class.configuration.reset!
      
      # Configure for comprehensive extraction
      described_class.configure do |config|
        config.max_depth = 5
        config.use_transactions = true
        config.validate_records = true
      end

      # Extract the data
      extractor = ActiveRecordGraphExtractor::Extractor.new
      extracted_data = extractor.extract(order)

      # Verify extraction
      expect(extracted_data['records']).not_to be_empty
      expect(extracted_data['metadata']['total_records']).to be > 5

      # Verify all models are extracted
      model_names = extracted_data['records'].map { |r| r['_model'] }.uniq
      expect(model_names).to include('TestOrder', 'TestUser', 'TestProduct', 'TestPhoto')

      # Clear the database
      [TestPhoto, TestProduct, TestOrderFlag, TestAdminAction, TestOrder, 
       TestAddress, TestUser, TestPartner, TestCategory].each(&:delete_all)

      # Import the data
      importer = ActiveRecordGraphExtractor::Importer.new
      import_result = importer.import(extracted_data)

      # Verify import
      expect(import_result['imported_records']).to eq(extracted_data['metadata']['total_records'])

      # Verify data integrity
      imported_order = TestOrder.first
      expect(imported_order.test_user).to be_present
      expect(imported_order.test_partner).to be_present
      expect(imported_order.test_address).to be_present
      expect(imported_order.test_products).not_to be_empty
      expect(imported_order.test_admin_actions).not_to be_empty
      expect(imported_order.test_order_flag).to be_present

      imported_product = imported_order.test_products.first
      expect(imported_product.test_photos).not_to be_empty
      expect(imported_product.test_category).to be_present

      # Verify original data is preserved
      expect(imported_order.state).to eq(order.state)
      expect(imported_order.test_user.email).to eq(user.email)
      expect(imported_product.product_number).to eq(product.product_number)
    end

    it 'respects configuration filters' do
      described_class.configure do |config|
        config.exclude_model('TestPhoto')
        config.exclude_relationship('test_admin_actions')
        config.max_depth = 2
      end

      extractor = ActiveRecordGraphExtractor::Extractor.new
      extracted_data = extractor.extract(order)

      # Should not include photos or admin actions
      model_names = extracted_data['records'].map { |r| r['_model'] }.uniq
      expect(model_names).not_to include('TestPhoto')
      
      # Should not include admin actions due to relationship filter
      expect(extracted_data['records'].select { |r| r['_model'] == 'TestAdminAction' }).to be_empty
    end

    it 'handles custom serializers' do
      described_class.configure do |config|
        config.add_custom_serializer('TestUser') do |user|
          {
            id: user.id,
            email: user.email,
            full_name: "#{user.first_name} #{user.last_name}",
            custom_field: 'from_serializer'
          }
        end
      end

      extractor = ActiveRecordGraphExtractor::Extractor.new
      extracted_data = extractor.extract(user)

      user_record = extracted_data['records'].find { |r| r['_model'] == 'TestUser' }
      expect(user_record['full_name']).to eq("#{user.first_name} #{user.last_name}")
      expect(user_record['custom_field']).to eq('from_serializer')
    end

    it 'handles different primary key strategies' do
      # Test with preserve_original strategy
      described_class.configure do |config|
        config.primary_key_strategy = :preserve_original
      end

      extractor = ActiveRecordGraphExtractor::Extractor.new
      extracted_data = extractor.extract(user)

      original_user_id = user.id

      # Clear and import
      TestUser.delete_all
      importer = ActiveRecordGraphExtractor::Importer.new
      import_result = importer.import(extracted_data)

      # Should preserve original ID
      imported_user = TestUser.first
      expect(imported_user.id).to eq(original_user_id)
    end

    it 'provides comprehensive metadata' do
      extractor = ActiveRecordGraphExtractor::Extractor.new
      extracted_data = extractor.extract(order)

      metadata = extracted_data['metadata']
      expect(metadata).to have_key('extraction_time')
      expect(metadata).to have_key('total_records')
      expect(metadata).to have_key('models_extracted')
      expect(metadata).to have_key('max_depth_used')
      expect(metadata['models_extracted']).to be_an(Array)
      expect(metadata['models_extracted']).not_to be_empty
    end
  end

  describe 'error handling integration' do
    it 'provides useful error messages for extraction failures' do
      expect { 
        extractor = ActiveRecordGraphExtractor::Extractor.new
        extractor.extract(nil) 
      }.to raise_error(ActiveRecordGraphExtractor::ExtractionError, /Root object cannot be nil/)
    end

    it 'provides useful error messages for import failures' do
      invalid_data = { 'invalid' => 'structure' }
      
      expect { 
        importer = ActiveRecordGraphExtractor::Importer.new
        importer.import(invalid_data) 
      }.to raise_error(ActiveRecordGraphExtractor::ImportError, /Invalid data structure/)
    end
  end

  describe 'performance characteristics' do
    it 'handles moderate-sized object graphs efficiently' do
      # Create a moderately complex object graph
      user = create(:test_user)
      orders = create_list(:test_order, 10, test_user: user)
      
      orders.each do |order|
        create_list(:test_product, 5, test_order: order)
      end

      start_time = Time.now
      extractor = ActiveRecordGraphExtractor::Extractor.new
      extracted_data = extractor.extract(user)
      extraction_time = Time.now - start_time

      # Should complete in reasonable time (less than 10 seconds)
      expect(extraction_time).to be < 10

      # Should extract all related records
      expect(extracted_data['records'].size).to be > 50 # 1 user + 10 orders + 50 products
    end
  end

  describe 'memory efficiency' do
    it 'does not hold excessive memory during operations' do
      # This is a basic test - in practice you'd use more sophisticated memory monitoring
      user = create(:test_user)
      create_list(:test_order, 20, test_user: user)

      start_memory = GC.stat[:total_allocated_objects]
      
      extractor = ActiveRecordGraphExtractor::Extractor.new
      extracted_data = extractor.extract(user)
      
      end_memory = GC.stat[:total_allocated_objects]
      memory_growth = end_memory - start_memory

      # Should not allocate an excessive number of objects
      expect(memory_growth).to be < 100_000
    end
  end
end 