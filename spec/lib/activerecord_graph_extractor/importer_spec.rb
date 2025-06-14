# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveRecordGraphExtractor::Importer do
  let(:importer) { described_class.new }

  describe '#import' do
    let(:data) do
      {
        'metadata' => {
          'root_model' => 'TestOrder',
          'root_id' => 1,
          'extracted_at' => Time.current.iso8601
        },
        'records' => [
          {
            '_model' => 'TestOrder',
            'id' => 1,
            'test_user_id' => 1,
            'test_partner_id' => 1,
            'test_address_id' => 1,
            'state' => 'completed',
            'total_amount' => 99.99,
            'is_gift' => false
          },
          {
            '_model' => 'TestUser',
            'id' => 1,
            'email' => 'test@example.com',
            'first_name' => 'Test',
            'last_name' => 'User'
          }
        ]
      }
    end

    it 'imports records with correct relationships' do
      result = importer.import(data)

      expect(result).to be_a(Hash)
      expect(result['metadata']).to include(
        'total_records' => 2,
        'imported_records' => 2
      )

      expect(TestOrder.count).to eq(1)
      order = TestOrder.first
      expect(order).to be_present
      expect(order.test_user).to be_present
      expect(order.state).to eq('completed')
    end

    it 'handles existing records' do
      # Create an existing user
      create(:test_user, id: 1, email: 'existing@example.com')

      result = importer.import(data, skip_existing: true)
      expect(result['metadata']['skipped_records']).to eq(1)
      expect(result['metadata']['imported_records']).to eq(1)
    end

    it 'handles validation errors' do
      # Make the data invalid
      data['records'].first['state'] = 'invalid_state'

      result = importer.import(data)
      expect(result['metadata']['errors']).to be_present
      expect(result['metadata']['imported_records']).to eq(0)
    end

    it 'handles circular dependencies' do
      # Create circular data
      circular_data = {
        'metadata' => {
          'root_model' => 'TestOrder',
          'root_id' => 1
        },
        'records' => [
          {
            '_model' => 'TestOrder',
            'id' => 1,
            'test_user_id' => 1
          },
          {
            '_model' => 'TestUser',
            'id' => 1,
            'test_order_id' => 1
          }
        ]
      }

      result = importer.import(circular_data)
      expect(result['metadata']['errors']).to be_present
    end

    it 'handles custom finders' do
      # Create a custom finder for User
      custom_finders = {
        'TestUser' => ->(attrs) { TestUser.find_by(email: attrs['email']) }
      }

      # Create an existing user with the same email
      create(:test_user, email: 'test@example.com')

      result = importer.import(data, custom_finders: custom_finders)
      expect(result['metadata']['skipped_records']).to eq(1)
      expect(result['metadata']['imported_records']).to eq(1)
    end

    it 'handles transactions' do
      # Make the data invalid after the first record
      data['records'].last['email'] = nil

      result = importer.import(data, transaction: true)
      expect(result['metadata']['errors']).to be_present
      expect(TestOrder.count).to eq(0)
      expect(TestUser.count).to eq(0)
    end

    it 'handles batch processing' do
      # Create a large dataset
      large_data = {
        'metadata' => {
          'root_model' => 'TestOrder',
          'root_id' => 1
        },
        'records' => []
      }

      # Add 100 users and orders
      100.times do |i|
        large_data['records'] << {
          '_model' => 'TestUser',
          'id' => i + 1,
          'email' => "user#{i}@example.com",
          'first_name' => "User#{i}",
          'last_name' => "Test#{i}"
        }
        large_data['records'] << {
          '_model' => 'TestOrder',
          'id' => i + 1,
          'test_user_id' => i + 1,
          'state' => 'completed',
          'total_amount' => 99.99
        }
      end

      result = importer.import(large_data, batch_size: 20)
      expect(result['metadata']['imported_records']).to eq(200)
      expect(TestUser.count).to eq(100)
      expect(TestOrder.count).to eq(100)
    end
  end

  describe '#import_from_file' do
    let(:file_path) { 'test_import.json' }

    before do
      File.write(file_path, {
        'metadata' => {
          'root_model' => 'TestOrder',
          'root_id' => 1
        },
        'records' => [
          {
            '_model' => 'TestOrder',
            'id' => 1,
            'test_user_id' => 1,
            'state' => 'completed'
          },
          {
            '_model' => 'TestUser',
            'id' => 1,
            'email' => 'test@example.com'
          }
        ]
      }.to_json)
    end

    after do
      File.delete(file_path) if File.exist?(file_path)
    end

    it 'imports from JSON file' do
      result = importer.import_from_file(file_path)
      expect(result['metadata']['imported_records']).to eq(2)
      expect(TestOrder.count).to eq(1)
      expect(TestUser.count).to eq(1)
    end

    it 'handles file errors' do
      expect { importer.import_from_file('nonexistent.json') }.to raise_error(
        ActiveRecordGraphExtractor::FileError
      )
    end

    it 'handles JSON parsing errors' do
      File.write(file_path, 'invalid json')
      expect { importer.import_from_file(file_path) }.to raise_error(
        ActiveRecordGraphExtractor::JSONError
      )
    end
  end
end 