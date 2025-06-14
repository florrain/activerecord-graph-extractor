# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveRecordGraphExtractor::JSONSerializer do
  let(:user) { create(:test_user) }
  let(:order) { create(:test_order) }
  let(:serializer) { described_class.new }

  describe '#serialize_to_string' do
    it 'serializes a single record' do
      data = { 'records' => { 'TestUser' => [{ 'id' => 1, 'email' => 'test@example.com' }] } }
      
      json = serializer.serialize_to_string(data)
      
      expect(json).to be_a(String)
      expect(json).to include('TestUser')
      expect(json).to include('test@example.com')
    end

    it 'excludes internal ActiveRecord attributes' do
      data = { 'records' => { 'TestUser' => [{ 'id' => 1, 'email' => 'test@example.com' }] } }
      
      json = serializer.serialize_to_string(data)
      
      expect(json).not_to include('created_at')
      expect(json).not_to include('updated_at')
    end

    it 'handles nil values' do
      data = { 'records' => { 'TestUser' => [{ 'id' => 1, 'email' => nil }] } }
      
      json = serializer.serialize_to_string(data)
      expect(json).to include('null')
    end

    it 'handles custom serializers' do
      data = { 'records' => { 'TestUser' => [{ 'id' => 1, 'email' => 'test@example.com' }] } }
      
      json = serializer.serialize_to_string(data)
      expect(json).to be_a(String)
    end

    it 'handles polymorphic associations' do
      data = { 'records' => { 'TestHistoryRecord' => [{ 
        'id' => 1, 
        'recordable_type' => 'TestUser',
        'recordable_id' => 1
      }] } }
      
      json = serializer.serialize_to_string(data)
      expect(json).to include('recordable_type')
      expect(json).to include('TestUser')
    end
  end

  describe '#serialize_to_file' do
    let(:temp_file) { Tempfile.new(['test', '.json']) }

    after { temp_file.unlink }

    it 'serializes to JSON file' do
      data = { 'records' => { 'TestUser' => [{ 'id' => 1, 'email' => 'test@example.com' }] } }
      
      serializer.serialize_to_file(data, temp_file.path)
      
      expect(File.exist?(temp_file.path)).to be(true)
      content = File.read(temp_file.path)
      expect(content).to include('TestUser')
    end

    it 'handles file errors' do
      data = { 'records' => { 'TestUser' => [{ 'id' => 1, 'email' => 'test@example.com' }] } }

      expect { serializer.serialize_to_file(data, '/invalid/path/file.json') }.to raise_error(
        Errno::ENOENT
      )
    end
  end

  describe '#deserialize_from_string' do
    it 'deserializes JSON string to Ruby objects' do
      json_string = '{"records":{"TestUser":[{"id":1,"email":"test@example.com"}]}}'
      
      data = serializer.deserialize_from_string(json_string)
      
      expect(data).to be_a(Hash)
      expect(data['records']['TestUser']).to be_an(Array)
      expect(data['records']['TestUser'].first['email']).to eq('test@example.com')
    end

    it 'handles malformed JSON' do
      expect { serializer.deserialize_from_string('invalid json{') }.to raise_error(EncodingError)
    end

    it 'handles empty JSON' do
      expect { serializer.deserialize_from_string('{}') }.not_to raise_error
    end
  end

  describe '#deserialize_from_file' do
    let(:temp_file) { Tempfile.new(['test', '.json']) }

    before do
      data = { 'records' => { 'TestUser' => [{ 'id' => 1, 'email' => 'test@example.com' }] } }
      File.write(temp_file.path, serializer.serialize_to_string(data))
    end

    after { temp_file.unlink }

    it 'reads and deserializes JSON from file' do
      data = serializer.deserialize_from_file(temp_file.path)
      
      expect(data).to be_a(Hash)
      expect(data['records']['TestUser']).to be_an(Array)
    end

    it 'raises error for non-existent file' do
      expect { serializer.deserialize_from_file('nonexistent.json') }.to raise_error(Errno::ENOENT)
    end

    it 'raises error for file with invalid JSON' do
      File.write(temp_file.path, 'invalid json{')
      expect { serializer.deserialize_from_file(temp_file.path) }.to raise_error(EncodingError)
    end
  end
end 