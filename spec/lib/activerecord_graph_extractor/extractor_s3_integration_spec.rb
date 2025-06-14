# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveRecordGraphExtractor::Extractor, 'S3 Integration' do
  let(:extractor) { described_class.new }
  let(:test_order) { create(:test_order) }
  let(:bucket_name) { 'test-extraction-bucket' }
  let(:s3_key) { 'test/extraction.json' }
  let(:s3_client_mock) { instance_double(ActiveRecordGraphExtractor::S3Client) }

  before do
    allow(ActiveRecordGraphExtractor::S3Client).to receive(:new).and_return(s3_client_mock)
    allow(s3_client_mock).to receive(:upload_file).and_return({
      bucket: bucket_name,
      key: s3_key,
      url: "s3://#{bucket_name}/#{s3_key}",
      size: 1024
    })
  end

  describe '#extract_to_s3' do
    it 'extracts and uploads to S3 successfully' do
      result = extractor.extract_to_s3(test_order, s3_client_mock, s3_key)

      expect(result).to include('records', 'metadata', 's3_upload')
      expect(result['s3_upload']).to include(
        bucket: bucket_name,
        key: s3_key,
        url: "s3://#{bucket_name}/#{s3_key}",
        size: 1024
      )
    end

    it 'passes extraction options correctly' do
      options = { max_depth: 3, custom_serializers: {} }
      
      expect(extractor).to receive(:extract).with(test_order, options).and_call_original
      
      extractor.extract_to_s3(test_order, s3_client_mock, s3_key, options)
    end

    it 'cleans up temporary file after upload' do
      temp_files_before = Dir.glob('/tmp/extraction*.json').size
      
      extractor.extract_to_s3(test_order, s3_client_mock, s3_key)
      
      temp_files_after = Dir.glob('/tmp/extraction*.json').size
      expect(temp_files_after).to eq(temp_files_before)
    end

    context 'when S3 upload fails' do
      before do
        allow(s3_client_mock).to receive(:upload_file).and_raise(
          ActiveRecordGraphExtractor::S3Error, 'Upload failed'
        )
      end

      it 'raises S3Error and cleans up temp file' do
        temp_files_before = Dir.glob('/tmp/extraction*.json').size
        
        expect {
          extractor.extract_to_s3(test_order, s3_client_mock, s3_key)
        }.to raise_error(ActiveRecordGraphExtractor::S3Error, 'Upload failed')
        
        temp_files_after = Dir.glob('/tmp/extraction*.json').size
        expect(temp_files_after).to eq(temp_files_before)
      end
    end
  end

  describe '#extract_and_upload_to_s3' do
    before do
      # Mock S3Client initialization
      allow(ActiveRecordGraphExtractor::S3Client).to receive(:new)
        .with(bucket_name: bucket_name, region: 'us-west-2', access_key_id: 'test')
        .and_return(s3_client_mock)
    end

    it 'creates S3Client and extracts to S3' do
      result = extractor.extract_and_upload_to_s3(
        test_order,
        bucket_name: bucket_name,
        s3_key: s3_key,
        region: 'us-west-2',
        options: { max_depth: 2 },
        access_key_id: 'test'
      )

      expect(result).to include('records', 'metadata', 's3_upload')
    end

    it 'uses default region when not specified' do
      expect(ActiveRecordGraphExtractor::S3Client).to receive(:new)
        .with(bucket_name: bucket_name, region: 'us-east-1')
        .and_return(s3_client_mock)

      extractor.extract_and_upload_to_s3(test_order, bucket_name: bucket_name)
    end

    it 'auto-generates S3 key when not provided' do
      expect(s3_client_mock).to receive(:upload_file).with(anything, nil).and_return({
        bucket: bucket_name,
        key: 'auto-generated-key.json',
        url: "s3://#{bucket_name}/auto-generated-key.json",
        size: 1024
      })

      result = extractor.extract_and_upload_to_s3(test_order, bucket_name: bucket_name)
      
      expect(result['s3_upload'][:key]).to eq('auto-generated-key.json')
    end
  end

  describe 'error handling' do
    context 'when extraction fails' do
      before do
        allow(extractor).to receive(:extract).and_raise(
          ActiveRecordGraphExtractor::ExtractionError, 'Extraction failed'
        )
      end

      it 'cleans up temp file and re-raises error' do
        temp_files_before = Dir.glob('/tmp/extraction*.json').size
        
        expect {
          extractor.extract_to_s3(test_order, s3_client_mock, s3_key)
        }.to raise_error(ActiveRecordGraphExtractor::ExtractionError, 'Extraction failed')
        
        temp_files_after = Dir.glob('/tmp/extraction*.json').size
        expect(temp_files_after).to eq(temp_files_before)
      end
    end

    context 'when file write fails' do
      before do
        allow(File).to receive(:write).and_raise(Errno::EACCES, 'Permission denied')
      end

      it 'cleans up temp file and raises FileError' do
        temp_files_before = Dir.glob('/tmp/extraction*.json').size
        
        expect {
          extractor.extract_to_s3(test_order, s3_client_mock, s3_key)
        }.to raise_error(ActiveRecordGraphExtractor::FileError)
        
        temp_files_after = Dir.glob('/tmp/extraction*.json').size
        expect(temp_files_after).to eq(temp_files_before)
      end
    end
  end
end 