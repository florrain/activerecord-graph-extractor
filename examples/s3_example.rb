#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Using ActiveRecord Graph Extractor with S3
# This script demonstrates how to extract ActiveRecord data and upload it to S3

require 'bundler/setup'
require 'activerecord_graph_extractor'

# Configure AWS credentials (in production, use environment variables or IAM roles)
# ENV['AWS_ACCESS_KEY_ID'] = 'your_access_key'
# ENV['AWS_SECRET_ACCESS_KEY'] = 'your_secret_key'
# ENV['AWS_REGION'] = 'us-east-1'

# Example 1: Basic S3 upload
def basic_s3_upload_example
  puts "=== Basic S3 Upload Example ==="
  
  # Assuming you have an Order model
  order = Order.find(123)
  
  extractor = ActiveRecordGraphExtractor::Extractor.new
  
  begin
    result = extractor.extract_and_upload_to_s3(
      order,
      bucket_name: 'my-extraction-bucket',
      s3_key: 'extractions/order_123.json',
      region: 'us-east-1'
    )
    
    puts "✅ Successfully uploaded to S3!"
    puts "   Bucket: #{result['s3_upload'][:bucket]}"
    puts "   Key: #{result['s3_upload'][:key]}"
    puts "   URL: #{result['s3_upload'][:url]}"
    puts "   Size: #{result['s3_upload'][:size]} bytes"
    puts "   Records: #{result['metadata']['total_records']}"
    
  rescue ActiveRecordGraphExtractor::S3Error => e
    puts "❌ S3 Error: #{e.message}"
  rescue ActiveRecordGraphExtractor::ExtractionError => e
    puts "❌ Extraction Error: #{e.message}"
  end
end

# Example 2: Using S3Client directly
def s3_client_example
  puts "\n=== S3Client Direct Usage Example ==="
  
  begin
    # Create S3 client
    s3_client = ActiveRecordGraphExtractor::S3Client.new(
      bucket_name: 'my-extraction-bucket',
      region: 'us-east-1'
    )
    
    # Extract to local file first
    order = Order.find(123)
    extractor = ActiveRecordGraphExtractor::Extractor.new
    local_file = 'temp_extraction.json'
    
    extractor.extract_to_file(order, local_file)
    
    # Upload to S3
    upload_result = s3_client.upload_file(
      local_file,
      'extractions/manual_upload.json',
      server_side_encryption: 'AES256',
      metadata: { 'extracted_by' => 'my_app', 'version' => '1.0' }
    )
    
    puts "✅ Manual upload successful!"
    puts "   URL: #{upload_result[:url]}"
    
    # List files in bucket
    files = s3_client.list_files(prefix: 'extractions/')
    puts "\n📋 Files in bucket:"
    files.each do |file|
      puts "   #{file[:key]} (#{file[:size]} bytes)"
    end
    
    # Clean up local file
    File.delete(local_file) if File.exist?(local_file)
    
  rescue ActiveRecordGraphExtractor::S3Error => e
    puts "❌ S3 Error: #{e.message}"
  end
end

# Example 3: Advanced configuration with custom serializers
def advanced_s3_example
  puts "\n=== Advanced S3 Configuration Example ==="
  
  # Configure the gem
  ActiveRecordGraphExtractor.configure do |config|
    config.max_depth = 3
    config.handle_circular_references = true
    
    # Add custom serializer for sensitive data
    config.add_custom_serializer('User') do |user|
      {
        'id' => user.id,
        'email' => user.email.gsub(/@.*/, '@***'),  # Mask email domain
        'created_at' => user.created_at,
        'status' => user.status
      }
    end
  end
  
  order = Order.find(123)
  extractor = ActiveRecordGraphExtractor::Extractor.new
  
  begin
    result = extractor.extract_and_upload_to_s3(
      order,
      bucket_name: 'secure-extraction-bucket',
      options: {
        max_depth: 2,
        exclude_models: ['PaymentMethod', 'CreditCard']  # Exclude sensitive models
      }
    )
    
    puts "✅ Secure extraction uploaded!"
    puts "   Records: #{result['metadata']['total_records']}"
    puts "   Models: #{result['metadata']['models_extracted'].join(', ')}"
    
  rescue => e
    puts "❌ Error: #{e.message}"
  end
end

# Example 4: Batch processing with error handling
def batch_processing_example
  puts "\n=== Batch Processing Example ==="
  
  s3_client = ActiveRecordGraphExtractor::S3Client.new(
    bucket_name: 'batch-extractions',
    region: 'us-east-1'
  )
  
  extractor = ActiveRecordGraphExtractor::Extractor.new
  
  # Process multiple orders
  Order.where(status: 'completed').limit(10).find_each do |order|
    begin
      result = extractor.extract_to_s3(
        order,
        s3_client,
        "batch/#{Date.current}/order_#{order.id}.json"
      )
      
      puts "✅ Processed Order #{order.id} - #{result['metadata']['total_records']} records"
      
    rescue => e
      puts "❌ Failed to process Order #{order.id}: #{e.message}"
      # Continue with next order
    end
  end
end

# Example 5: Download and analyze
def download_and_analyze_example
  puts "\n=== Download and Analyze Example ==="
  
  s3_client = ActiveRecordGraphExtractor::S3Client.new(
    bucket_name: 'my-extraction-bucket'
  )
  
  begin
    # List recent extractions
    files = s3_client.list_files(
      prefix: 'extractions/',
      max_keys: 5
    )
    
    return if files.empty?
    
    # Download the most recent file
    latest_file = files.max_by { |f| f[:last_modified] }
    local_path = "downloaded_#{File.basename(latest_file[:key])}"
    
    download_result = s3_client.download_file(latest_file[:key], local_path)
    puts "✅ Downloaded: #{download_result[:local_path]}"
    
    # Analyze the file
    data = JSON.parse(File.read(local_path))
    metadata = data['metadata']
    
    puts "\n📊 Analysis:"
    puts "   Extraction time: #{metadata['extraction_time']}"
    puts "   Total records: #{metadata['total_records']}"
    puts "   Models: #{metadata['models_extracted'].join(', ')}"
    puts "   Duration: #{metadata['duration_seconds']}s"
    
    # Clean up
    File.delete(local_path)
    
  rescue => e
    puts "❌ Error: #{e.message}"
  end
end

# Example 6: Presigned URLs for sharing
def presigned_url_example
  puts "\n=== Presigned URL Example ==="
  
  s3_client = ActiveRecordGraphExtractor::S3Client.new(
    bucket_name: 'my-extraction-bucket'
  )
  
  begin
    # Generate a presigned URL valid for 24 hours
    url = s3_client.presigned_url(
      'extractions/order_123.json',
      expires_in: 24 * 60 * 60  # 24 hours
    )
    
    puts "✅ Presigned URL generated:"
    puts "   #{url}"
    puts "   Valid for: 24 hours"
    puts "   Use this URL to download the file without AWS credentials"
    
  rescue => e
    puts "❌ Error: #{e.message}"
  end
end

# Run examples (uncomment the ones you want to test)
if __FILE__ == $0
  puts "ActiveRecord Graph Extractor S3 Examples"
  puts "========================================"
  
  # Make sure to set up your AWS credentials and have valid data before running
  puts "⚠️  Make sure to configure AWS credentials and update model/ID references"
  puts "⚠️  These examples assume you have Order model with ID 123"
  puts
  
  # Uncomment to run specific examples:
  # basic_s3_upload_example
  # s3_client_example
  # advanced_s3_example
  # batch_processing_example
  # download_and_analyze_example
  # presigned_url_example
  
  puts "✨ Examples ready to run! Uncomment the ones you want to test."
end 