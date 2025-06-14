# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveRecordGraphExtractor::S3Client do
  let(:bucket_name) { 'test-bucket' }
  let(:region) { 'us-east-1' }
  let(:s3_client_mock) { instance_double(Aws::S3::Client) }
  let(:test_file_path) { 'test_file.json' }
  let(:test_content) { '{"test": "data"}' }
  let(:s3_key) { 'test/file.json' }

  before do
    allow(Aws::S3::Client).to receive(:new).and_return(s3_client_mock)
    allow(s3_client_mock).to receive(:head_bucket)
    
    # Create a test file
    File.write(test_file_path, test_content)
  end

  after do
    File.delete(test_file_path) if File.exist?(test_file_path)
  end

  describe '#initialize' do
    context 'with valid bucket' do
      it 'initializes successfully' do
        expect { described_class.new(bucket_name: bucket_name) }.not_to raise_error
      end

      it 'sets the correct attributes' do
        client = described_class.new(bucket_name: bucket_name, region: region)
        expect(client.bucket_name).to eq(bucket_name)
        expect(client.region).to eq(region)
      end
    end

    context 'with invalid bucket' do
      before do
        allow(s3_client_mock).to receive(:head_bucket).and_raise(Aws::S3::Errors::NotFound.new(nil, nil))
      end

      it 'raises S3Error for non-existent bucket' do
        expect {
          described_class.new(bucket_name: 'non-existent-bucket')
        }.to raise_error(ActiveRecordGraphExtractor::S3Error, /Bucket not found/)
      end
    end

    context 'with access denied' do
      before do
        allow(s3_client_mock).to receive(:head_bucket).and_raise(Aws::S3::Errors::Forbidden.new(nil, nil))
      end

      it 'raises S3Error for access denied' do
        expect {
          described_class.new(bucket_name: bucket_name)
        }.to raise_error(ActiveRecordGraphExtractor::S3Error, /Access denied/)
      end
    end
  end

  describe '#upload_file' do
    let(:client) { described_class.new(bucket_name: bucket_name) }

    context 'with valid file' do
      before do
        allow(s3_client_mock).to receive(:put_object)
      end

      it 'uploads file successfully' do
        result = client.upload_file(test_file_path, s3_key)

        expect(result).to include(
          bucket: bucket_name,
          key: s3_key,
          url: "s3://#{bucket_name}/#{s3_key}",
          size: test_content.bytesize
        )
      end

      it 'auto-generates S3 key when not provided' do
        allow(Time).to receive(:now).and_return(Time.new(2023, 12, 25))
        
        result = client.upload_file(test_file_path)
        
        expect(result[:key]).to match(%r{activerecord-graph-extractor/2023/12/25/test_file\.json})
      end

      it 'passes additional options to S3' do
        expect(s3_client_mock).to receive(:put_object).with(
          hash_including(
            bucket: bucket_name,
            key: s3_key,
            content_type: 'application/json',
            server_side_encryption: 'AES256'
          )
        )

        client.upload_file(test_file_path, s3_key, server_side_encryption: 'AES256')
      end
    end

    context 'with non-existent file' do
      it 'raises FileError' do
        expect {
          client.upload_file('non_existent_file.json', s3_key)
        }.to raise_error(ActiveRecordGraphExtractor::FileError, /File not found/)
      end
    end

    context 'with S3 error' do
      before do
        allow(s3_client_mock).to receive(:put_object).and_raise(Aws::S3::Errors::ServiceError.new(nil, 'Upload failed'))
      end

      it 'raises S3Error' do
        expect {
          client.upload_file(test_file_path, s3_key)
        }.to raise_error(ActiveRecordGraphExtractor::S3Error, /Failed to upload file to S3/)
      end
    end
  end

  describe '#download_file' do
    let(:client) { described_class.new(bucket_name: bucket_name) }
    let(:download_path) { 'downloaded_file.json' }

    after do
      File.delete(download_path) if File.exist?(download_path)
    end

    context 'with valid S3 key' do
      before do
        allow(s3_client_mock).to receive(:get_object) do |args|
          File.write(args[:response_target], test_content)
        end
      end

      it 'downloads file successfully' do
        result = client.download_file(s3_key, download_path)

        expect(result).to include(
          bucket: bucket_name,
          key: s3_key,
          local_path: download_path,
          size: test_content.bytesize
        )
        expect(File.read(download_path)).to eq(test_content)
      end

      it 'uses basename as default local path' do
        allow(s3_client_mock).to receive(:get_object) do |args|
          File.write(args[:response_target], test_content)
        end

        result = client.download_file('path/to/file.json')
        
        expect(result[:local_path]).to eq('file.json')
        File.delete('file.json') if File.exist?('file.json')
      end
    end

    context 'with non-existent S3 key' do
      before do
        allow(s3_client_mock).to receive(:get_object).and_raise(Aws::S3::Errors::NoSuchKey.new(nil, nil))
      end

      it 'raises S3Error' do
        expect {
          client.download_file('non_existent_key.json', download_path)
        }.to raise_error(ActiveRecordGraphExtractor::S3Error, /File not found in S3/)
      end
    end
  end

  describe '#file_exists?' do
    let(:client) { described_class.new(bucket_name: bucket_name) }

    context 'when file exists' do
      before do
        allow(s3_client_mock).to receive(:head_object)
      end

      it 'returns true' do
        expect(client.file_exists?(s3_key)).to be true
      end
    end

    context 'when file does not exist' do
      before do
        allow(s3_client_mock).to receive(:head_object).and_raise(Aws::S3::Errors::NotFound.new(nil, nil))
      end

      it 'returns false' do
        expect(client.file_exists?(s3_key)).to be false
      end
    end
  end

  describe '#list_files' do
    let(:client) { described_class.new(bucket_name: bucket_name) }
    let(:mock_response) do
      double('response', contents: [
        double('object', key: 'file1.json', size: 100, last_modified: Time.now),
        double('object', key: 'file2.json', size: 200, last_modified: Time.now)
      ])
    end

    before do
      allow(s3_client_mock).to receive(:list_objects_v2).and_return(mock_response)
    end

    it 'lists files successfully' do
      result = client.list_files

      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
      expect(result.first).to include(:key, :size, :last_modified, :url)
    end

    it 'accepts prefix parameter' do
      expect(s3_client_mock).to receive(:list_objects_v2).with(
        hash_including(prefix: 'test/')
      ).and_return(mock_response)

      client.list_files(prefix: 'test/')
    end

    it 'accepts max_keys parameter' do
      expect(s3_client_mock).to receive(:list_objects_v2).with(
        hash_including(max_keys: 50)
      ).and_return(mock_response)

      client.list_files(max_keys: 50)
    end
  end

  describe '#delete_file' do
    let(:client) { described_class.new(bucket_name: bucket_name) }

    context 'with valid S3 key' do
      before do
        allow(s3_client_mock).to receive(:delete_object)
      end

      it 'deletes file successfully' do
        result = client.delete_file(s3_key)
        expect(result).to be true
      end
    end

    context 'with S3 error' do
      before do
        allow(s3_client_mock).to receive(:delete_object).and_raise(Aws::S3::Errors::ServiceError.new(nil, 'Delete failed'))
      end

      it 'raises S3Error' do
        expect {
          client.delete_file(s3_key)
        }.to raise_error(ActiveRecordGraphExtractor::S3Error, /Failed to delete file/)
      end
    end
  end

  describe '#presigned_url' do
    let(:client) { described_class.new(bucket_name: bucket_name) }
    let(:presigner_mock) { instance_double(Aws::S3::Presigner) }
    let(:presigned_url) { 'https://example.com/presigned-url' }

    before do
      allow(Aws::S3::Presigner).to receive(:new).and_return(presigner_mock)
      allow(presigner_mock).to receive(:presigned_url).and_return(presigned_url)
    end

    it 'generates presigned URL successfully' do
      result = client.presigned_url(s3_key)
      expect(result).to eq(presigned_url)
    end

    it 'accepts custom expiration time' do
      expect(presigner_mock).to receive(:presigned_url).with(
        :get_object,
        bucket: bucket_name,
        key: s3_key,
        expires_in: 7200
      ).and_return(presigned_url)

      client.presigned_url(s3_key, expires_in: 7200)
    end
  end

  describe '#file_metadata' do
    let(:client) { described_class.new(bucket_name: bucket_name) }
    let(:mock_response) do
      double('response',
        content_length: 1024,
        last_modified: Time.now,
        content_type: 'application/json',
        etag: '"abc123"',
        metadata: { 'custom' => 'value' }
      )
    end

    context 'with valid S3 key' do
      before do
        allow(s3_client_mock).to receive(:head_object).and_return(mock_response)
      end

      it 'returns file metadata' do
        result = client.file_metadata(s3_key)

        expect(result).to include(
          key: s3_key,
          size: 1024,
          content_type: 'application/json',
          etag: '"abc123"'
        )
      end
    end

    context 'with non-existent S3 key' do
      before do
        allow(s3_client_mock).to receive(:head_object).and_raise(Aws::S3::Errors::NotFound.new(nil, nil))
      end

      it 'raises S3Error' do
        expect {
          client.file_metadata('non_existent_key.json')
        }.to raise_error(ActiveRecordGraphExtractor::S3Error, /File not found/)
      end
    end
  end

  describe 'private methods' do
    let(:client) { described_class.new(bucket_name: bucket_name) }

    describe '#generate_s3_key' do
      it 'generates key with timestamp and filename' do
        allow(Time).to receive(:now).and_return(Time.new(2023, 12, 25))
        
        key = client.send(:generate_s3_key, 'test_file.json')
        
        expect(key).to eq('activerecord-graph-extractor/2023/12/25/test_file.json')
      end
    end

    describe '#s3_url' do
      it 'generates S3 URL' do
        url = client.send(:s3_url, 'test/file.json')
        expect(url).to eq("s3://#{bucket_name}/test/file.json")
      end
    end
  end
end 