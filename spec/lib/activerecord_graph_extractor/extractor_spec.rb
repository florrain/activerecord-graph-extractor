# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveRecordGraphExtractor::Extractor do
  let(:extractor) { described_class.new }
  let(:order) { create(:test_order) }
  let(:product) { create(:test_product) }
  let(:user) { create(:test_user) }
  let(:partner) { create(:test_partner) }
  let(:address) { create(:test_address) }
  let(:profile) { create(:test_profile) }
  let(:category) { create(:test_category) }
  let(:photo) { create(:test_photo) }
  let(:admin_action) { create(:test_admin_action) }
  let(:order_flag) { create(:test_order_flag) }
  let(:history_record) { create(:test_history_record) }

  before do
    # Set up relationships
    order.update!(
      test_user: user,
      test_partner: partner,
      test_address: address,
      test_products: [product],
      test_admin_actions: [admin_action],
      test_order_flag: order_flag
    )
    product.update!(
      test_category: category,
      test_photos: [photo]
    )
    user.update!(
      test_profile: profile,
      test_history_records: [history_record]
    )
  end

  describe '#extract' do
    it 'extracts a single record with relationships' do
      result = extractor.extract(order)

      expect(result).to be_a(Hash)
      expect(result['records']).to be_an(Array)
      expect(result['records'].length).to eq(12) # Order + User + Partner + Address + Product + Category + Photo + AdminAction + OrderFlag + Profile + HistoryRecord + duplicate User

      # Verify root record
      root_record = result['records'].find { |r| r['_model'] == 'TestOrder' && r['id'] == order.id }
      expect(root_record).to be_present
      expect(root_record['test_user_id']).to eq(user.id)
      expect(root_record['test_partner_id']).to eq(partner.id)
      expect(root_record['test_address_id']).to eq(address.id)

      # Verify relationships are included
      expect(result['records'].map { |r| r['_model'] }).to include(
        'TestUser',
        'TestPartner',
        'TestAddress',
        'TestProduct',
        'TestCategory',
        'TestPhoto',
        'TestAdminAction',
        'TestOrderFlag'
      )
    end

    it 'respects max_depth setting' do
      result = extractor.extract(order, max_depth: 1)

      # Should only include direct relationships
      expect(result['records'].map { |r| r['_model'] }).to include(
        'TestOrder',
        'TestUser',
        'TestPartner',
        'TestAddress',
        'TestProduct',
        'TestAdminAction',
        'TestOrderFlag'
      )

      # Should not include nested relationships
      expect(result['records'].map { |r| r['_model'] }).not_to include(
        'TestCategory',
        'TestPhoto',
        'TestProfile',
        'TestHistoryRecord'
      )
    end

    it 'handles circular references' do
      # Create circular reference
      user.update!(test_order: order)

      result = extractor.extract(order)
      expect(result['metadata']['circular_references_detected']).to be true
      expect(result['records'].length).to eq(12) # Should not cause infinite recursion
    end

    it 'handles polymorphic associations' do
      result = extractor.extract(user)
      expect(result['records'].map { |r| r['_model'] }).to include('TestHistoryRecord')
    end

    it 'handles multiple root objects' do
      order2 = create(:test_order, test_user: user)
      result = extractor.extract([order, order2])

      expect(result['records'].select { |r| r['_model'] == 'TestOrder' }.count).to eq(2)
      expect(result['metadata']['root_model']).to eq('TestOrder')
      expect(result['metadata']['root_ids']).to contain_exactly(order.id, order2.id)
    end

    it 'handles custom serializers' do
      custom_serializers = {
        'TestUser' => ->(user) {
          {
            'id' => user.id,
            'email' => user.email,
            'full_name' => "#{user.first_name} #{user.last_name}",
            'custom_field' => 'custom_value'
          }
        }
      }

      result = extractor.extract(order, custom_serializers: custom_serializers)
      user_record = result['records'].find { |r| r['_model'] == 'TestUser' }
      expect(user_record['full_name']).to eq("#{user.first_name} #{user.last_name}")
      expect(user_record['custom_field']).to eq('custom_value')
    end

    it 'handles nil values' do
      order.update!(test_user: nil)
      result = extractor.extract(order)
      expect(result['records'].find { |r| r['_model'] == 'TestOrder' }['test_user_id']).to be_nil
    end

    it 'excludes internal ActiveRecord attributes' do
      result = extractor.extract(order)
      order_record = result['records'].find { |r| r['_model'] == 'TestOrder' }
      expect(order_record).not_to have_key('created_at')
      expect(order_record).not_to have_key('updated_at')
    end

    it 'raises error for invalid input' do
      expect { extractor.extract(nil) }.to raise_error(ActiveRecordGraphExtractor::ExtractionError)
      expect { extractor.extract('invalid') }.to raise_error(ActiveRecordGraphExtractor::ExtractionError)
    end

    it 'handles database errors gracefully' do
      allow(order).to receive(:test_user).and_raise(ActiveRecord::StatementInvalid.new('DB Error'))
      expect { extractor.extract(order) }.to raise_error(ActiveRecordGraphExtractor::ExtractionError)
    end
  end

  describe '#extract_to_file' do
    let(:file_path) { 'test_export.json' }

    after do
      File.delete(file_path) if File.exist?(file_path)
    end

    it 'extracts to JSON file' do
      extractor.extract_to_file(order, file_path)
      content = JSON.parse(File.read(file_path))
      expect(content['records']).to be_an(Array)
      expect(content['metadata']).to be_a(Hash)
    end

    it 'handles file errors' do
      expect { extractor.extract_to_file(order, '/invalid/path/file.json') }.to raise_error(
        ActiveRecordGraphExtractor::FileError
      )
    end
  end

  describe '#dry_run' do
    let(:user) { create(:test_user) }
    let(:order) { create(:test_order, test_user: user) }

    it 'performs dry run analysis' do
      result = extractor.dry_run(user)
      
      expect(result).to be_a(Hash)
      expect(result['dry_run']).to be true
      expect(result['analysis_time']).to be_a(Numeric)
      expect(result['root_objects']['count']).to eq(1)
      expect(result['root_objects']['models']).to include('TestUser')
    end

    it 'passes options to analyzer' do
      result = extractor.dry_run(user, max_depth: 2)
      
      expect(result['extraction_scope']['max_depth']).to eq(2)
    end

    it 'works with multiple objects' do
      user2 = create(:test_user)
      result = extractor.dry_run([user, user2])
      
      expect(result['root_objects']['count']).to eq(2)
    end

    it 'includes comprehensive analysis data' do
      result = extractor.dry_run(order)
      
      expected_keys = %w[
        dry_run analysis_time root_objects extraction_scope
        estimated_counts_by_model estimated_file_size depth_analysis
        relationship_analysis performance_estimates warnings recommendations
      ]
      
      expect(result.keys).to include(*expected_keys)
    end
  end
end 