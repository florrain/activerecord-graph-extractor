# Usage Examples

## Basic Usage

### Extract an Order and Related Records

```ruby
# Find the order to extract
order = Order.find(12345)

# Create an extractor instance
extractor = ActiveRecordGraphExtractor::Extractor.new

# Extract the order and all related records
data = extractor.extract(order)

# Export to a JSON file
File.write('order_12345.json', data.to_json)
```

### Import the Extracted Data

```ruby
# Create an importer instance
importer = ActiveRecordGraphExtractor::Importer.new

# Import from the JSON file
importer.import_from_file('order_12345.json')
```

## Configuration Examples

### Extraction Configuration

```ruby
extractor = ActiveRecordGraphExtractor::Extractor.new(
  # Control which relationships to include
  include_relationships: %w[products customer shipping_address],
  
  # Set maximum depth of relationship traversal
  max_depth: 3,
  
  # Custom serialization for specific models
  custom_serializers: {
    'User' => ->(record) {
      {
        id: record.id,
        full_name: "#{record.first_name} #{record.last_name}",
        email: record.email
      }
    }
  }
)
```

### Import Configuration

```ruby
importer = ActiveRecordGraphExtractor::Importer.new(
  # Skip records that already exist
  skip_existing: true,
  
  # Update existing records instead of skipping
  update_existing: false,
  
  # Wrap import in a transaction
  transaction: true,
  
  # Validate records before saving
  validate: true,
  
  # Custom finder methods for specific models
  custom_finders: {
    'Product' => ->(attrs) { 
      Product.find_by(product_number: attrs['product_number']) 
    }
  }
)
```

## S3 Integration

### Upload Extractions to S3

```ruby
# Extract and upload to S3 in one step
extractor = ActiveRecordGraphExtractor::Extractor.new
result = extractor.extract_and_upload_to_s3(
  order,
  bucket_name: 'my-extraction-bucket',
  s3_key: 'extractions/order_12345.json',
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
result = extractor.extract_to_s3(order, s3_client, 'extractions/order_12345.json')

# List files in bucket
files = s3_client.list_files(prefix: 'extractions/')
files.each { |file| puts "#{file[:key]} (#{file[:size]} bytes)" }

# Download a file
s3_client.download_file('extractions/order_12345.json', 'local_order.json')
```

For detailed S3 configuration and usage, see [S3 Integration Guide](s3_integration.md).

## CLI Usage

### Extract Records

```bash
# Basic extraction
$ arge extract Order 12345

# With specific relationships
$ arge extract Order 12345 --include-relationships products,customer,shipping_address

# With maximum depth
$ arge extract Order 12345 --max-depth 3

# With output file
$ arge extract Order 12345 --output order_12345.json
```

### Import Records

```bash
# Basic import
$ arge import order_12345.json

# With batch size
$ arge import order_12345.json --batch-size 1000

# With validation
$ arge import order_12345.json --validate

# With transaction
$ arge import order_12345.json --transaction
```

### S3 Operations

```bash
# Extract and upload to S3
$ arge extract_to_s3 Order 12345 --bucket my-extraction-bucket --key extractions/order_12345.json

# List files in S3 bucket
$ arge s3_list --bucket my-extraction-bucket --prefix extractions/

# Download from S3
$ arge s3_download extractions/order_12345.json --bucket my-extraction-bucket --output local_order.json
```

## Advanced Examples

### Custom Traversal Rules

```ruby
extractor = ActiveRecordGraphExtractor::Extractor.new(
  traversal_rules: {
    'Order' => {
      'products' => { max_depth: 2 },
      'customer' => { max_depth: 1 },
      'shipping_address' => { max_depth: 1 }
    }
  }
)
```

### Progress Tracking

```ruby
# Extract with progress tracking
extractor = ActiveRecordGraphExtractor::Extractor.new
extractor.extract(order) do |progress|
  puts "Processed #{progress.current} of #{progress.total} records"
end

# Import with progress tracking
importer = ActiveRecordGraphExtractor::Importer.new
importer.import_from_file('order_12345.json') do |progress|
  puts "Imported #{progress.current} of #{progress.total} records"
end
```

### Error Handling

```ruby
# Handle extraction errors
begin
  extractor.extract(order)
rescue ActiveRecordGraphExtractor::ExtractionError => e
  puts "Extraction failed: #{e.message}"
  puts "Failed records: #{e.failed_records}"
end

# Handle import errors
begin
  importer.import_from_file('order_12345.json')
rescue ActiveRecordGraphExtractor::ImportError => e
  puts "Import failed: #{e.message}"
  puts "Failed records: #{e.failed_records}"
end
```

### Circular Dependencies

```ruby
begin
  extractor.extract(order)
rescue ActiveRecordGraphExtractor::CircularDependencyError => e
  puts "Circular dependency detected: #{e.message}"
  puts "Dependency chain: #{e.dependency_chain}"
end
```

## Best Practices

1. Always specify the maximum depth to prevent infinite loops
2. Use custom serializers to control what data is exported
3. Use custom finders to handle complex record matching
4. Enable transactions for atomic imports
5. Monitor progress for large extractions/imports
6. Handle errors appropriately
7. Validate data before importing
8. Use batch processing for large datasets 