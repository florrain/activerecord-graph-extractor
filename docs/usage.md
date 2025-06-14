# Usage Guide

This guide covers common usage patterns and best practices for the ActiveRecord Graph Extractor gem.

## Getting Started

### Installation

Add the gem to your application's Gemfile:

```ruby
gem 'activerecord-graph-extractor'
```

Or install directly:

```bash
gem install activerecord-graph-extractor
```

### Basic Usage

#### Extracting Data

```ruby
require 'activerecord_graph_extractor'

# Find your root object
order = Order.find(12345)

# Create extractor with default configuration
extractor = ActiveRecordGraphExtractor::Extractor.new

# Extract to file
result = extractor.extract_to_file(order, 'order_export.json')
puts "Extracted #{result['metadata']['total_records']} records"
```

#### Importing Data

```ruby
# Create importer
importer = ActiveRecordGraphExtractor::Importer.new

# Import from file
result = importer.import_from_file('order_export.json')
puts "Imported #{result['imported_records']} records"
```

## Configuration

### Global Configuration

```ruby
ActiveRecordGraphExtractor.configure do |config|
  config.max_depth = 3                           # Limit relationship depth
  config.include_relationship('user')            # Only include specific relationships
  config.include_relationship('products')
  config.exclude_model('History')                # Skip these models
  config.exclude_model('AuditLog')
  config.batch_size = 500                       # Process in batches
  config.stream_json = true                     # Use streaming for large files
end
```

### Per-Extraction Configuration

```ruby
extractor = ActiveRecordGraphExtractor::Extractor.new
result = extractor.extract(order, {
  max_depth: 3,
  custom_serializers: {
    'User' => ->(user) { { id: user.id, email: user.email } }
  }
})
```

## Progress Monitoring

### Programmatic Progress Tracking

```ruby
ActiveRecordGraphExtractor.configure do |config|
  config.progress_enabled = true
end

extractor = ActiveRecordGraphExtractor::Extractor.new
result = extractor.extract(order)
```

### CLI Progress Visualization

```bash
# Extract with beautiful progress bars
arge extract Order 12345 \
  --output export.json \
  --progress \
  --show-graph

# Import with progress
arge import export.json \
  --progress \
  --batch-size 500
```

## Advanced Configuration

### Handling Circular References

```ruby
ActiveRecordGraphExtractor.configure do |config|
  config.handle_circular_references = true
  config.max_depth = 5
end

extractor = ActiveRecordGraphExtractor::Extractor.new
result = extractor.extract(order)
```

### Memory Optimization

```ruby
# For large datasets
ActiveRecordGraphExtractor.configure do |config|
  config.stream_json = true          # Stream JSON writing/reading
  config.batch_size = 250           # Smaller batches
  config.progress_enabled = true    # Monitor progress
  config.exclude_model('History')
  config.exclude_model('AuditLog')
  config.exclude_model('UserEmailHistory')
end
```

## Error Handling

### Extraction Errors

```ruby
begin
  result = extractor.extract_to_file(order, 'export.json')
rescue ActiveRecordGraphExtractor::ExtractionError => e
  puts "Extraction failed: #{e.message}"
end
```

### Import Errors

```ruby
begin
  result = importer.import_from_file('export.json')
rescue ActiveRecordGraphExtractor::ImportError => e
  puts "Import failed: #{e.message}"
end
```

## Performance Considerations

### Extraction Performance

1. **Limit Depth**: Use `max_depth` to prevent deep traversal
2. **Filter Models**: Use `exclude_model` to skip unnecessary tables
3. **Filter Relationships**: Use `include_relationship` for specific paths
4. **Batch Size**: Adjust `batch_size` based on memory constraints
5. **Streaming**: Enable `stream_json` for large datasets

### Import Performance

1. **Skip Validations**: Use `validate_records: false` for trusted data
2. **Larger Batches**: Increase `batch_size` for faster imports
3. **Transaction Strategy**: Use `use_transactions: true` for consistency

## Best Practices

### 1. Start Small

```ruby
# Test with limited scope first
ActiveRecordGraphExtractor.configure do |config|
  config.max_depth = 2
  config.include_relationship('user')
  config.include_relationship('products')
end

extractor = ActiveRecordGraphExtractor::Extractor.new
result = extractor.extract(order)
```

### 2. Use Dry Runs

```ruby
# Always test imports with validation first
ActiveRecordGraphExtractor.configure do |config|
  config.validate_records = true
end

importer = ActiveRecordGraphExtractor::Importer.new
result = importer.import_from_file('export.json')
puts "Imported #{result['imported_records']} records"
```

### 3. Monitor Memory Usage

```ruby
ActiveRecordGraphExtractor.configure do |config|
  config.progress_enabled = true
  config.batch_size = 500  # Adjust based on memory constraints
end
```

### 4. Handle Large Datasets

```ruby
# For datasets > 10k records
ActiveRecordGraphExtractor.configure do |config|
  config.stream_json = true
  config.batch_size = 250
  config.progress_enabled = true
  config.exclude_model('History')
  config.exclude_model('AuditLog')
end
```

### 5. Version Your Exports

```ruby
timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
filename = "order_#{order.id}_#{timestamp}.json"
result = extractor.extract_to_file(order, filename)
```

## Common Patterns

### Environment Migration

```ruby
# Production -> Staging
production_order = Order.find(id)

ActiveRecordGraphExtractor.configure do |config|
  config.exclude_model('History')
  config.exclude_model('AuditLog')
  config.max_depth = 4
end

extractor = ActiveRecordGraphExtractor::Extractor.new

# Export from production
result = extractor.extract_to_file(production_order, 'prod_export.json')

# Import to staging (different environment)
ActiveRecordGraphExtractor.configure do |config|
  config.validate_records = true
end

importer = ActiveRecordGraphExtractor::Importer.new
staging_result = importer.import_from_file('prod_export.json')
```

### Test Data Setup

```ruby
# Extract test fixtures
test_orders = Order.joins(:user)
  .where(users: { email: 'test@example.com' })
  .limit(3)

extractor = ActiveRecordGraphExtractor::Extractor.new

test_orders.each_with_index do |order, i|
  ActiveRecordGraphExtractor.configure do |config|
    config.max_depth = 2
  end
  
  extractor.extract_to_file(order, "test_order_#{i + 1}.json")
end
```

### Debugging Data Issues

```ruby
# Extract with maximum detail for debugging
ActiveRecordGraphExtractor.configure do |config|
  config.max_depth = 10
  config.handle_circular_references = true
  config.progress_enabled = true
end

extractor = ActiveRecordGraphExtractor::Extractor.new
result = extractor.extract(problematic_record)
```

## CLI Quick Reference

```bash
# Basic extraction
arge extract Order 12345 -o export.json

# Advanced extraction
arge extract Order 12345 \
  --output export.json \
  --max-depth 3 \
  --include-relationships user,products,partner \
  --exclude-models History,AuditLog \
  --batch-size 500 \
  --progress \
  --show-graph \
  --stream

# Basic import
arge import export.json

# Advanced import
arge import export.json \
  --batch-size 1000 \
  --skip-validations \
  --progress

# Dry run import
arge import export.json --dry-run

# Analyze export file
arge analyze export.json

# Get help
arge help extract
arge help import
```

## Troubleshooting

### Memory Issues

If you encounter memory issues:

1. Reduce `batch_size`
2. Enable `stream_json`
3. Increase progress monitoring frequency
4. Use `exclude_model` to skip large tables

### Performance Issues

For slow extraction/import:

1. Increase `batch_size` (if memory allows)
2. Use `validate_records: false` for imports
3. Limit `max_depth`
4. Filter relationships with `include_relationship`

### Circular Reference Errors

If you hit circular references:

1. Use `handle_circular_references: true`
2. Set appropriate `max_depth`
3. Use `include_relationship` to avoid problematic paths

### Validation Errors

If import validation fails:

1. Check for missing required fields
2. Verify foreign key relationships
3. Consider `validate_records: false` if data is trusted 