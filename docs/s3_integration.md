# S3 Integration

The ActiveRecord Graph Extractor gem provides built-in support for uploading extraction files directly to Amazon S3. This feature is useful for:

- Storing extractions in cloud storage for backup or sharing
- Integrating with data pipelines that consume from S3
- Archiving large extraction files
- Enabling remote access to extraction data

## Installation

The S3 integration requires the `aws-sdk-s3` gem, which is automatically included as a dependency when you install the activerecord-graph-extractor gem.

## Configuration

### AWS Credentials

The S3Client uses the standard AWS SDK credential chain. You can configure credentials in several ways:

1. **Environment Variables** (Recommended for production):
   ```bash
   export AWS_ACCESS_KEY_ID=your_access_key
   export AWS_SECRET_ACCESS_KEY=your_secret_key
   export AWS_REGION=us-east-1
   ```

2. **AWS Credentials File** (`~/.aws/credentials`):
   ```ini
   [default]
   aws_access_key_id = your_access_key
   aws_secret_access_key = your_secret_key
   ```

3. **IAM Roles** (Recommended for EC2/ECS):
   When running on AWS infrastructure, use IAM roles for secure, temporary credentials.

4. **Explicit Credentials** (Not recommended for production):
   ```ruby
   s3_client = ActiveRecordGraphExtractor::S3Client.new(
     bucket_name: 'my-bucket',
     access_key_id: 'your_access_key',
     secret_access_key: 'your_secret_key'
   )
   ```

### Required S3 Permissions

Your AWS credentials need the following S3 permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::your-bucket-name",
        "arn:aws:s3:::your-bucket-name/*"
      ]
    }
  ]
}
```

## Usage

### Basic S3 Upload

```ruby
# Extract and upload to S3 in one step
extractor = ActiveRecordGraphExtractor::Extractor.new
result = extractor.extract_and_upload_to_s3(
  order,
  bucket_name: 'my-extraction-bucket',
  s3_key: 'extractions/order_123.json',
  region: 'us-east-1'
)

puts "Uploaded to: #{result['s3_upload'][:url]}"
```

### Using S3Client Directly

```ruby
# Create S3 client
s3_client = ActiveRecordGraphExtractor::S3Client.new(
  bucket_name: 'my-extraction-bucket',
  region: 'us-east-1'
)

# Extract to S3
extractor = ActiveRecordGraphExtractor::Extractor.new
result = extractor.extract_to_s3(order, s3_client, 'extractions/order_123.json')
```

### Auto-Generated S3 Keys

If you don't specify an S3 key, one will be automatically generated with a timestamp:

```ruby
result = extractor.extract_and_upload_to_s3(
  order,
  bucket_name: 'my-extraction-bucket'
)

# S3 key will be something like:
# "activerecord-graph-extractor/2024/01/25/extraction_20240125_143022.json"
```

### Extraction Options

You can pass all the same extraction options when uploading to S3:

```ruby
result = extractor.extract_and_upload_to_s3(
  order,
  bucket_name: 'my-extraction-bucket',
  options: {
    max_depth: 3,
    custom_serializers: {
      'Order' => ->(order) { { id: order.id, status: order.status } }
    }
  }
)
```

## S3Client Methods

The `S3Client` class provides comprehensive S3 operations:

### Upload Files

```ruby
s3_client = ActiveRecordGraphExtractor::S3Client.new(bucket_name: 'my-bucket')

# Upload with custom options
result = s3_client.upload_file(
  'local_file.json',
  'remote/path/file.json',
  server_side_encryption: 'AES256',
  metadata: { 'extracted_by' => 'my_app' }
)
```

### Download Files

```ruby
# Download to specific path
result = s3_client.download_file('remote/file.json', 'local_file.json')

# Download using original filename
result = s3_client.download_file('remote/path/file.json')
# Downloads to './file.json'
```

### List Files

```ruby
# List all files
files = s3_client.list_files

# List with prefix filter
files = s3_client.list_files(prefix: 'extractions/2024/')

# Limit results
files = s3_client.list_files(max_keys: 10)
```

### Check File Existence

```ruby
if s3_client.file_exists?('remote/file.json')
  puts "File exists!"
end
```

### Get File Metadata

```ruby
metadata = s3_client.file_metadata('remote/file.json')
puts "Size: #{metadata[:size]} bytes"
puts "Last modified: #{metadata[:last_modified]}"
```

### Generate Presigned URLs

```ruby
# URL valid for 1 hour (default)
url = s3_client.presigned_url('remote/file.json')

# Custom expiration (24 hours)
url = s3_client.presigned_url('remote/file.json', expires_in: 86400)
```

### Delete Files

```ruby
s3_client.delete_file('remote/file.json')
```

## CLI Commands

The gem includes CLI commands for S3 operations:

### Extract to S3

```bash
# Extract and upload to S3
arge extract_to_s3 Order 123 \
  --bucket my-extraction-bucket \
  --key extractions/order_123.json \
  --region us-east-1 \
  --max-depth 3

# Auto-generate S3 key
arge extract_to_s3 Order 123 \
  --bucket my-extraction-bucket \
  --region us-east-1
```

### List S3 Files

```bash
# List all extraction files
arge s3_list --bucket my-extraction-bucket

# List with prefix filter
arge s3_list --bucket my-extraction-bucket --prefix extractions/2024/

# Limit results
arge s3_list --bucket my-extraction-bucket --max-keys 10
```

### Download from S3

```bash
# Download to specific file
arge s3_download extractions/order_123.json \
  --bucket my-extraction-bucket \
  --output local_order.json

# Download using original filename
arge s3_download extractions/order_123.json \
  --bucket my-extraction-bucket
```

## Error Handling

The S3 integration includes comprehensive error handling:

```ruby
begin
  result = extractor.extract_and_upload_to_s3(order, bucket_name: 'my-bucket')
rescue ActiveRecordGraphExtractor::S3Error => e
  puts "S3 operation failed: #{e.message}"
rescue ActiveRecordGraphExtractor::ExtractionError => e
  puts "Extraction failed: #{e.message}"
rescue ActiveRecordGraphExtractor::FileError => e
  puts "File operation failed: #{e.message}"
end
```

Common S3 errors:
- `Bucket not found` - The specified bucket doesn't exist
- `Access denied` - Insufficient permissions
- `File not found in S3` - Trying to download non-existent file
- `Failed to upload file to S3` - Network or permission issues

## Best Practices

### Security

1. **Use IAM Roles** when running on AWS infrastructure
2. **Rotate credentials** regularly
3. **Use least-privilege permissions** - only grant necessary S3 actions
4. **Enable S3 bucket encryption** for sensitive data

### Performance

1. **Use appropriate regions** - choose regions close to your application
2. **Consider S3 storage classes** for archival data (IA, Glacier)
3. **Enable S3 Transfer Acceleration** for global applications
4. **Use multipart uploads** for large files (handled automatically by AWS SDK)

### Organization

1. **Use consistent S3 key patterns**:
   ```ruby
   # Good: organized by date and model
   "extractions/2024/01/25/orders/order_123.json"
   
   # Good: include metadata in key
   "extractions/production/orders/2024-01-25/order_123_depth_3.json"
   ```

2. **Set up S3 lifecycle policies** to automatically archive or delete old extractions

3. **Use S3 bucket notifications** to trigger downstream processing

### Monitoring

1. **Enable S3 access logging** to track usage
2. **Set up CloudWatch metrics** for monitoring
3. **Use S3 inventory** for large-scale file management

## Configuration Examples

### Production Configuration

```ruby
# config/initializers/activerecord_graph_extractor.rb
ActiveRecordGraphExtractor.configure do |config|
  # S3 settings
  config.s3_bucket = ENV['EXTRACTION_S3_BUCKET']
  config.s3_region = ENV['AWS_REGION'] || 'us-east-1'
  config.s3_key_prefix = "extractions/#{Rails.env}"
  
  # Extraction settings
  config.max_depth = 5
  config.handle_circular_references = true
end
```

### Development Configuration

```ruby
# For development, you might want to use local files instead of S3
ActiveRecordGraphExtractor.configure do |config|
  if Rails.env.development?
    # Use local storage in development
    config.default_output_path = Rails.root.join('tmp', 'extractions')
  else
    # Use S3 in other environments
    config.s3_bucket = ENV['EXTRACTION_S3_BUCKET']
    config.s3_region = ENV['AWS_REGION']
  end
end
```

## Integration with Other Services

### Data Pipelines

```ruby
# Extract and trigger downstream processing
result = extractor.extract_and_upload_to_s3(order, bucket_name: 'pipeline-bucket')

# Notify processing service
ProcessingService.notify_new_extraction(
  s3_url: result['s3_upload'][:url],
  metadata: result['metadata']
)
```

### Backup and Archival

```ruby
# Regular backup job
class ExtractionBackupJob
  def perform
    critical_orders = Order.where(status: 'critical')
    
    critical_orders.find_each do |order|
      extractor.extract_and_upload_to_s3(
        order,
        bucket_name: 'backup-bucket',
        s3_key: "backups/#{Date.current}/order_#{order.id}.json"
      )
    end
  end
end
```

This S3 integration makes the ActiveRecord Graph Extractor a powerful tool for cloud-native data extraction and processing workflows. 