# frozen_string_literal: true

require 'aws-sdk-s3'

module ActiveRecordGraphExtractor
  class S3Client
    attr_reader :bucket_name, :region, :s3_client

    def initialize(bucket_name:, region: 'us-east-1', **options)
      @bucket_name = bucket_name
      @region = region
      
      # Initialize AWS S3 client with optional credentials
      s3_options = { region: region }
      s3_options.merge!(options) if options.any?
      
      @s3_client = Aws::S3::Client.new(s3_options)
      
      validate_bucket_access!
    end

    # Upload a file to S3
    def upload_file(local_file_path, s3_key = nil, **options)
      raise FileError, "File not found: #{local_file_path}" unless File.exist?(local_file_path)
      
      s3_key ||= generate_s3_key(local_file_path)
      
      begin
        File.open(local_file_path, 'rb') do |file|
          s3_client.put_object(
            bucket: bucket_name,
            key: s3_key,
            body: file,
            content_type: 'application/json',
            **options
          )
        end
        
        {
          bucket: bucket_name,
          key: s3_key,
          url: s3_url(s3_key),
          size: File.size(local_file_path)
        }
      rescue Aws::S3::Errors::ServiceError => e
        raise S3Error, "Failed to upload file to S3: #{e.message}"
      end
    end

    # Download a file from S3
    def download_file(s3_key, local_file_path = nil)
      local_file_path ||= File.basename(s3_key)
      
      begin
        s3_client.get_object(
          bucket: bucket_name,
          key: s3_key,
          response_target: local_file_path
        )
        
        {
          bucket: bucket_name,
          key: s3_key,
          local_path: local_file_path,
          size: File.size(local_file_path)
        }
      rescue Aws::S3::Errors::NoSuchKey
        raise S3Error, "File not found in S3: s3://#{bucket_name}/#{s3_key}"
      rescue Aws::S3::Errors::ServiceError => e
        raise S3Error, "Failed to download file from S3: #{e.message}"
      end
    end

    # Check if a file exists in S3
    def file_exists?(s3_key)
      s3_client.head_object(bucket: bucket_name, key: s3_key)
      true
    rescue Aws::S3::Errors::NotFound
      false
    rescue Aws::S3::Errors::ServiceError => e
      raise S3Error, "Failed to check file existence: #{e.message}"
    end

    # List files in S3 with optional prefix
    def list_files(prefix: nil, max_keys: 1000)
      options = {
        bucket: bucket_name,
        max_keys: max_keys
      }
      options[:prefix] = prefix if prefix

      begin
        response = s3_client.list_objects_v2(options)
        
        response.contents.map do |object|
          {
            key: object.key,
            size: object.size,
            last_modified: object.last_modified,
            url: s3_url(object.key)
          }
        end
      rescue Aws::S3::Errors::ServiceError => e
        raise S3Error, "Failed to list files: #{e.message}"
      end
    end

    # Delete a file from S3
    def delete_file(s3_key)
      begin
        s3_client.delete_object(bucket: bucket_name, key: s3_key)
        true
      rescue Aws::S3::Errors::ServiceError => e
        raise S3Error, "Failed to delete file: #{e.message}"
      end
    end

    # Generate a presigned URL for downloading
    def presigned_url(s3_key, expires_in: 3600)
      begin
        presigner = Aws::S3::Presigner.new(client: s3_client)
        presigner.presigned_url(:get_object, bucket: bucket_name, key: s3_key, expires_in: expires_in)
      rescue Aws::S3::Errors::ServiceError => e
        raise S3Error, "Failed to generate presigned URL: #{e.message}"
      end
    end

    # Get file metadata
    def file_metadata(s3_key)
      begin
        response = s3_client.head_object(bucket: bucket_name, key: s3_key)
        
        {
          key: s3_key,
          size: response.content_length,
          last_modified: response.last_modified,
          content_type: response.content_type,
          etag: response.etag,
          metadata: response.metadata
        }
      rescue Aws::S3::Errors::NotFound
        raise S3Error, "File not found: s3://#{bucket_name}/#{s3_key}"
      rescue Aws::S3::Errors::ServiceError => e
        raise S3Error, "Failed to get file metadata: #{e.message}"
      end
    end

    private

    def validate_bucket_access!
      s3_client.head_bucket(bucket: bucket_name)
    rescue Aws::S3::Errors::NotFound
      raise S3Error, "Bucket not found: #{bucket_name}"
    rescue Aws::S3::Errors::Forbidden
      raise S3Error, "Access denied to bucket: #{bucket_name}"
    rescue Aws::S3::Errors::ServiceError => e
      raise S3Error, "Failed to access bucket: #{e.message}"
    end

    def generate_s3_key(local_file_path)
      filename = File.basename(local_file_path)
      timestamp = Time.now.strftime('%Y/%m/%d')
      "activerecord-graph-extractor/#{timestamp}/#{filename}"
    end

    def s3_url(s3_key)
      "s3://#{bucket_name}/#{s3_key}"
    end
  end
end 