# ActiveRecord Graph Extractor

A gem for extracting ActiveRecord models and their relationships into a JSON format that can be imported into another environment.

## Features

- Complete graph traversal of ActiveRecord models
- Smart dependency resolution for importing
- Beautiful CLI with progress visualization
- Configurable extraction and import options
- Handles complex relationships including polymorphic associations
- Preserves referential integrity during import

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'activerecord-graph-extractor'
```

And then execute:
```bash
$ bundle install
```

Or install it yourself as:
```bash
$ gem install activerecord-graph-extractor
```

### CLI Installation

The gem includes a command-line interface called `arge` (ActiveRecord Graph Extractor). After installing the gem, you can use the CLI in several ways:

#### Option 1: Using with Bundler (Recommended for Rails projects)

If you've added the gem to your Rails application's Gemfile:

```bash
# Run CLI commands with bundle exec
$ bundle exec arge extract Order 12345 --output order.json
$ bundle exec arge s3_list --bucket my-bucket
```

#### Option 2: Global Installation

To use the `arge` command globally from anywhere in your terminal:

```bash
# Install the gem globally
$ gem install activerecord-graph-extractor

# Now you can use arge from anywhere
$ arge version
$ arge extract Order 12345 --output order.json
```

#### Option 3: Using with rbenv/RVM

If you're using rbenv or RVM, make sure the gem is installed in your current Ruby version:

```bash
# Check your current Ruby version
$ ruby -v

# Install the gem
$ gem install activerecord-graph-extractor

# Rehash to make the command available (rbenv only)
$ rbenv rehash

# Verify installation
$ arge version
```

#### Option 4: Development Setup

If you're working on the gem itself or want to use the latest development version:

```bash
# Clone the repository
$ git clone https://github.com/your-org/activerecord-graph-extractor.git
$ cd activerecord-graph-extractor

# Install dependencies
$ bundle install

# Use the CLI directly
$ bundle exec exe/arge version
$ bundle exec exe/arge extract Order 12345
```

#### Verifying Installation

To verify the CLI is properly installed:

```bash
# Check if the command is available
$ which arge
/usr/local/bin/arge

# Check the version
$ arge version
ActiveRecord Graph Extractor v1.0.0

# See all available commands
$ arge help
Commands:
  arge extract MODEL_CLASS ID          # Extract a record and its relationships
  arge extract_to_s3 MODEL_CLASS ID    # Extract and upload to S3
  arge import FILE                     # Import records from JSON file
  arge s3_list                         # List files in S3 bucket
  arge s3_download S3_KEY              # Download file from S3
  arge analyze FILE                    # Analyze a JSON export file
  arge dry_run MODEL_CLASS ID          # Analyze extraction scope without extracting
```

**Automated Verification:** You can also run our installation verification script:

```bash
# Download and run the verification script
$ curl -fsSL https://raw.githubusercontent.com/your-org/activerecord-graph-extractor/main/scripts/verify_installation.rb | ruby

# Or if you have the gem source code
$ ruby scripts/verify_installation.rb
```

This script will check your Ruby version, gem installation, CLI availability, and test all commands.

#### Troubleshooting CLI Installation

**Command not found:**
```bash
$ arge version
-bash: arge: command not found
```

Solutions:
1. **Check gem installation:** `gem list | grep activerecord-graph-extractor`
2. **Rehash your shell:** `rbenv rehash` (for rbenv) or restart your terminal
3. **Check your PATH:** `echo $PATH` should include your gem bin directory
4. **Use bundle exec:** `bundle exec arge version` if installed via Gemfile

**Permission errors:**
```bash
$ gem install activerecord-graph-extractor
ERROR: While executing gem ... (Gem::FilePermissionError)
```

Solutions:
1. **Use rbenv/RVM:** Install Ruby via rbenv or RVM instead of system Ruby
2. **Use --user-install:** `gem install --user-install activerecord-graph-extractor`
3. **Use sudo (not recommended):** `sudo gem install activerecord-graph-extractor`

**Wrong Ruby version:**
```bash
$ arge version
Your Ruby version is 2.6.0, but this gem requires >= 2.7.0
```

Solution: Upgrade your Ruby version using rbenv, RVM, or your system package manager.

## Quick Start

### Ruby API

```ruby
# Extract an Order and all related records
order = Order.find(12345)
extractor = ActiveRecordGraphExtractor::Extractor.new
data = extractor.extract(order)

# Export to a JSON file
File.write('order_12345.json', data.to_json)

# Import in another environment
importer = ActiveRecordGraphExtractor::Importer.new
importer.import_from_file('order_12345.json')
```

### CLI Usage

```bash
# Extract an Order and related records
$ arge extract Order 12345 --output order.json

# Import from a JSON file
$ arge import order_12345.json

# Extract and upload directly to S3
$ arge extract_to_s3 Order 12345 --bucket my-bucket --key extractions/order.json

# List files in S3 bucket
$ arge s3_list --bucket my-bucket --prefix extractions/

# Download from S3
$ arge s3_download extractions/order.json --bucket my-bucket --output local_order.json

# Analyze an export file
$ arge analyze order_12345.json

# Dry run analysis (analyze before extracting)
$ arge dry_run Order 12345 --max-depth 3
```

## Dry Run Analysis

Before performing large extractions, use the dry run feature to understand the scope and performance implications:

### Ruby API

```ruby
# Analyze what would be extracted
order = Order.find(12345)
extractor = ActiveRecordGraphExtractor::Extractor.new

analysis = extractor.dry_run(order)
puts "Would extract #{analysis['extraction_scope']['total_estimated_records']} records"
puts "Estimated file size: #{analysis['estimated_file_size']['human_readable']}"
puts "Estimated time: #{analysis['performance_estimates']['estimated_extraction_time_human']}"

# Check for warnings and recommendations
analysis['warnings'].each { |w| puts "⚠️  #{w['message']}" }
analysis['recommendations'].each { |r| puts "💡 #{r['message']}" }
```

### CLI Usage

```bash
# Basic dry run analysis
$ arge dry_run Order 12345

# With custom depth and save report
$ arge dry_run Order 12345 --max-depth 2 --output analysis.json
```

**Example Output:**
```
🔍 Performing dry run analysis...

✅ Dry run analysis completed!

📊 Analysis Summary:
   Models involved: 8
   Total estimated records: 1,247
   Estimated file size: 2.3 MB
   Estimated extraction time: 1.2 seconds

📋 Records by Model:
   Order                    856 (68.7%)
   Product                  234 (18.8%)
   Photo                    145 (11.6%)

💡 Recommendations:
   S3: Large file detected - consider uploading directly to S3
```

See the [Dry Run Guide](docs/dry_run.md) for comprehensive documentation.

## Configuration

### Extraction Options

```ruby
extractor = ActiveRecordGraphExtractor::Extractor.new(
  max_depth: 3,                    # Maximum depth of relationship traversal
  include_relationships: %w[products customer shipping_address],  # Only include specific relationships
  exclude_relationships: %w[audit_logs],  # Exclude specific relationships
  custom_serializers: {            # Custom serialization for specific models
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

### Import Options

```ruby
importer = ActiveRecordGraphExtractor::Importer.new(
  skip_existing: true,             # Skip records that already exist
  update_existing: false,          # Update existing records instead of skipping
  transaction: true,               # Wrap import in a transaction
  validate: true,                  # Validate records before saving
  custom_finders: {                # Custom finder methods for specific models
    'Product' => ->(attrs) { Product.find_by(product_number: attrs['product_number']) }
  }
)
```

## JSON Structure

The exported JSON has the following structure:

```json
{
  "metadata": {
    "extracted_at": "2024-03-20T10:00:00Z",
    "root_model": "Order",
    "root_id": 12345,
    "total_records": 150,
    "models": ["Order", "User", "Product", "Address"],
    "circular_references": [],
    "max_depth": 3
  },
  "records": {
    "Order": [
      {
        "id": 12345,
        "user_id": 67890,
        "state": "completed",
        "total_amount": 99.99,
        "created_at": "2024-03-19T15:30:00Z"
      }
    ],
    "User": [
      {
        "id": 67890,
        "email": "customer@example.com",
        "first_name": "John",
        "last_name": "Doe"
      }
    ]
  }
}
```

## S3 Integration

The gem includes built-in support for uploading extractions directly to Amazon S3:

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

### S3Client Operations

```ruby
# Create S3 client for advanced operations
s3_client = ActiveRecordGraphExtractor::S3Client.new(
  bucket_name: 'my-bucket',
  region: 'us-east-1'
)

# List files
files = s3_client.list_files(prefix: 'extractions/')

# Download files
s3_client.download_file('extractions/order.json', 'local_order.json')

# Generate presigned URLs
url = s3_client.presigned_url('extractions/order.json', expires_in: 3600)
```

### S3 CLI Commands

```bash
# Extract and upload to S3
$ arge extract_to_s3 Order 12345 --bucket my-bucket --region us-east-1

# List S3 files
$ arge s3_list --bucket my-bucket --prefix extractions/2024/

# Download from S3
$ arge s3_download extractions/order.json --bucket my-bucket
```

**AWS Configuration:** Set up your AWS credentials using environment variables, AWS credentials file, or IAM roles. See the [S3 Integration Guide](docs/s3_integration.md) for detailed configuration instructions.

## Advanced Usage

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

### Handling Large Datasets

```ruby
# Extract with progress tracking
extractor = ActiveRecordGraphExtractor::Extractor.new
extractor.extract(order) do |progress|
  puts "Processed #{progress.current} of #{progress.total} records"
end

# Import with batch processing
importer = ActiveRecordGraphExtractor::Importer.new(batch_size: 1000)
importer.import_from_file('large_export.json')
```

## CLI Features

The CLI provides a beautiful interface with progress visualization:

```bash
$ arge extract Order 12345
Extracting Order #12345 and related records...
[====================] 100% | 150 records processed
Export completed: order_12345.json

$ arge import order_12345.json
Importing records from order_12345.json...
[====================] 100% | 150 records imported
Import completed successfully
```

## Error Handling

### Validation Errors

```ruby
begin
  importer.import_from_file('data.json')
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

## Performance

The gem is optimized for performance:

- Smart caching of traversed records
- Efficient SQL queries using includes
- Batch processing for large datasets
- Progress tracking for long-running operations

Benchmarks:
- Small dataset (100 records): ~1 second
- Medium dataset (1,000 records): ~5 seconds
- Large dataset (10,000 records): ~30 seconds

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Quick Reference

### CLI Commands

| Command | Description | Example |
|---------|-------------|---------|
| `arge version` | Show version information | `arge version` |
| `arge help` | Show all commands | `arge help` |
| `arge extract` | Extract records to JSON file | `arge extract Order 123 --output order.json` |
| `arge import` | Import records from JSON file | `arge import order.json` |
| `arge extract_to_s3` | Extract and upload to S3 | `arge extract_to_s3 Order 123 --bucket my-bucket` |
| `arge s3_list` | List files in S3 bucket | `arge s3_list --bucket my-bucket` |
| `arge s3_download` | Download file from S3 | `arge s3_download file.json --bucket my-bucket` |
| `arge analyze` | Analyze JSON export file | `arge analyze order.json` |
| `arge dry_run` | Analyze extraction scope without extracting | `arge dry_run Order 123 --max-depth 2` |

### Installation Quick Start

```bash
# For Rails projects (recommended)
echo 'gem "activerecord-graph-extractor"' >> Gemfile
bundle install
bundle exec arge version

# For global installation
gem install activerecord-graph-extractor
arge version

# Verify installation
ruby -e "$(curl -fsSL https://raw.githubusercontent.com/your-org/activerecord-graph-extractor/main/scripts/verify_installation.rb)"
```

### Common Usage Patterns

```bash
# Basic extraction
arge extract Order 123 --output order.json

# Extract with depth limit
arge extract Order 123 --max-depth 2 --output order.json

# Extract to S3
arge extract_to_s3 Order 123 --bucket my-bucket --region us-east-1

# Import with validation
arge import order.json --validate

# Dry run before large extraction
arge dry_run Order 123 --max-depth 3 --output analysis.json

# List recent S3 extractions
arge s3_list --bucket my-bucket --prefix extractions/$(date +%Y/%m)
```

## License

The gem is available as open source under the terms of the MIT License. 