# Dry Run Analysis

The dry run feature allows you to analyze what would be extracted without performing the actual extraction. This is particularly valuable for large datasets where you want to understand the scope, performance implications, and resource requirements before committing to a full extraction.

## Overview

Dry run analysis provides:

- **Scope Analysis**: Which models and how many records would be included
- **File Size Estimation**: Predicted size of the extraction file
- **Performance Estimates**: Expected extraction time and memory usage
- **Relationship Mapping**: Understanding of the object graph structure
- **Warnings & Recommendations**: Actionable insights for optimization
- **Circular Reference Detection**: Identification of potential issues

## Usage

### Ruby API

#### Basic Dry Run

```ruby
require 'activerecord_graph_extractor'

# Create an extractor instance
extractor = ActiveRecordGraphExtractor::Extractor.new

# Find the object to analyze
user = User.find(123)

# Perform dry run analysis
analysis = extractor.dry_run(user)

# Access analysis results
puts "Total estimated records: #{analysis['extraction_scope']['total_estimated_records']}"
puts "Estimated file size: #{analysis['estimated_file_size']['human_readable']}"
puts "Estimated extraction time: #{analysis['performance_estimates']['estimated_extraction_time_human']}"
```

#### Dry Run with Options

```ruby
# Analyze with custom max_depth
analysis = extractor.dry_run(user, max_depth: 2)

# Analyze multiple objects
users = User.limit(5)
analysis = extractor.dry_run(users, max_depth: 3)
```

#### Using DryRunAnalyzer Directly

```ruby
# For more control, use the analyzer directly
analyzer = ActiveRecordGraphExtractor::DryRunAnalyzer.new
analysis = analyzer.analyze(user, max_depth: 2)
```

### CLI Usage

#### Basic Dry Run

```bash
# Analyze a specific record
arge dry_run User 123

# With custom max depth
arge dry_run User 123 --max-depth 2

# Save analysis report to file
arge dry_run User 123 --output analysis_report.json
```

#### Example CLI Output

```
🔍 Performing dry run analysis...

   Model: User
   ID: 123
   Max Depth: default

✅ Dry run analysis completed!

📊 Analysis Summary:
   Analysis time: 0.245 seconds
   Root objects: 1
   Models involved: 8
   Total estimated records: 1,247
   Estimated file size: 2.3 MB

⏱️  Performance Estimates:
   Extraction time: 1.2 seconds
   Memory usage: 1.3 MB

📋 Records by Model:
   Order                    856 (68.7%)
   Product                  234 (18.8%)
   User                       1 (0.1%)
   Address                    2 (0.2%)
   Profile                    1 (0.1%)
   Photo                    145 (11.6%)
   Category                   6 (0.5%)
   AdminAction                2 (0.2%)

🌳 Depth Analysis:
   Level 1: User
   Level 2: Order, Address, Profile
   Level 3: Product, AdminAction
   Level 4: Photo, Category

💡 Recommendations:
   S3: Large file detected - consider uploading directly to S3
   → Use extract_to_s3 or extract_and_upload_to_s3 methods
```

## Analysis Report Structure

The dry run analysis returns a comprehensive JSON structure:

```json
{
  "dry_run": true,
  "analysis_time": 0.245,
  "root_objects": {
    "models": ["User"],
    "ids": [123],
    "count": 1
  },
  "extraction_scope": {
    "max_depth": 3,
    "total_models": 8,
    "total_estimated_records": 1247,
    "models_involved": ["User", "Order", "Product", "Address", "Profile", "Photo", "Category", "AdminAction"]
  },
  "estimated_counts_by_model": {
    "Order": 856,
    "Product": 234,
    "Photo": 145,
    "Category": 6,
    "Address": 2,
    "AdminAction": 2,
    "User": 1,
    "Profile": 1
  },
  "estimated_file_size": {
    "bytes": 2415616,
    "human_readable": "2.3 MB"
  },
  "depth_analysis": {
    "1": ["User"],
    "2": ["Order", "Address", "Profile"],
    "3": ["Product", "AdminAction"],
    "4": ["Photo", "Category"]
  },
  "relationship_analysis": {
    "total_relationships": 15,
    "circular_references": [],
    "circular_references_count": 0
  },
  "performance_estimates": {
    "estimated_extraction_time_seconds": 1.2,
    "estimated_extraction_time_human": "1.2 seconds",
    "estimated_memory_usage_mb": 1.3,
    "estimated_memory_usage_human": "1.3 MB"
  },
  "warnings": [
    {
      "type": "medium_file",
      "message": "Estimated file size is large (2.3 MB). Ensure adequate disk space.",
      "severity": "medium"
    }
  ],
  "recommendations": [
    {
      "type": "s3",
      "message": "Large file detected - consider uploading directly to S3",
      "action": "Use extract_to_s3 or extract_and_upload_to_s3 methods"
    }
  ]
}
```

## Key Analysis Components

### Extraction Scope

- **total_models**: Number of different model classes involved
- **total_estimated_records**: Total number of records across all models
- **models_involved**: List of model class names that would be included

### File Size Estimation

The analyzer estimates file size based on:
- Column types and their typical sizes
- Number of columns per model
- JSON structure overhead
- Relationship data overhead

### Performance Estimates

- **Extraction Time**: Based on estimated records per second processing rate
- **Memory Usage**: Estimated peak memory consumption during extraction

### Depth Analysis

Shows which models appear at each relationship depth level, helping you understand the object graph structure.

### Warnings

Automatic warnings for:
- **Large datasets** (>10,000 records): High severity for >100,000 records
- **Large files** (>100MB): High severity for >1GB files
- **Deep nesting** (>5 levels): Performance impact warnings
- **Circular references**: Potential infinite loops

### Recommendations

Actionable suggestions based on analysis:
- **Performance**: Batch processing for large datasets
- **Depth**: Reducing max_depth for better performance
- **Filtering**: Excluding large models or using custom filters
- **S3**: Direct S3 upload for large files
- **Memory**: RAM considerations for large extractions

## Best Practices

### 1. Always Dry Run Large Extractions

```ruby
# Before extracting a potentially large dataset
analysis = extractor.dry_run(user)

if analysis['extraction_scope']['total_estimated_records'] > 10_000
  puts "⚠️  Large extraction detected!"
  puts "Consider reducing max_depth or using filters"
end
```

### 2. Use Analysis for Decision Making

```ruby
analysis = extractor.dry_run(user)

file_size_mb = analysis['estimated_file_size']['bytes'] / (1024.0 * 1024)
extraction_time = analysis['performance_estimates']['estimated_extraction_time_seconds']

if file_size_mb > 50
  # Use S3 for large files
  extractor.extract_to_s3(user, s3_client, 'my-key')
elsif extraction_time > 300 # 5 minutes
  # Schedule for off-peak hours
  puts "Consider running during off-peak hours"
else
  # Proceed with normal extraction
  extractor.extract(user, 'output.json')
end
```

### 3. Compare Different Depths

```ruby
[1, 2, 3, 4].each do |depth|
  analysis = extractor.dry_run(user, max_depth: depth)
  
  puts "Depth #{depth}:"
  puts "  Records: #{analysis['extraction_scope']['total_estimated_records']}"
  puts "  File size: #{analysis['estimated_file_size']['human_readable']}"
  puts "  Time: #{analysis['performance_estimates']['estimated_extraction_time_human']}"
  puts
end
```

### 4. Save Analysis Reports

```ruby
# Save detailed analysis for documentation
analysis = extractor.dry_run(user)
timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
File.write("analysis_#{timestamp}.json", JSON.pretty_generate(analysis))
```

### 5. Monitor Warnings and Recommendations

```ruby
analysis = extractor.dry_run(user)

# Check for high-severity warnings
high_warnings = analysis['warnings'].select { |w| w['severity'] == 'high' }
if high_warnings.any?
  puts "🚨 High severity warnings detected:"
  high_warnings.each { |w| puts "  - #{w['message']}" }
end

# Follow recommendations
analysis['recommendations'].each do |rec|
  puts "💡 #{rec['type'].upcase}: #{rec['message']}"
  puts "   Action: #{rec['action']}"
end
```

## Integration Examples

### With Rails Console

```ruby
# In Rails console
user = User.find(123)
extractor = ActiveRecordGraphExtractor::Extractor.new
analysis = extractor.dry_run(user, max_depth: 2)

# Quick summary
puts "#{analysis['extraction_scope']['total_estimated_records']} records, #{analysis['estimated_file_size']['human_readable']}"
```

### With Rake Tasks

```ruby
# lib/tasks/data_analysis.rake
namespace :data do
  desc "Analyze extraction scope for a user"
  task :analyze_user, [:user_id] => :environment do |t, args|
    user = User.find(args[:user_id])
    extractor = ActiveRecordGraphExtractor::Extractor.new
    
    analysis = extractor.dry_run(user)
    
    puts "Analysis for User #{user.id}:"
    puts "  Total records: #{analysis['extraction_scope']['total_estimated_records']}"
    puts "  File size: #{analysis['estimated_file_size']['human_readable']}"
    puts "  Extraction time: #{analysis['performance_estimates']['estimated_extraction_time_human']}"
    
    # Save report
    File.write("user_#{user.id}_analysis.json", JSON.pretty_generate(analysis))
  end
end
```

### With Background Jobs

```ruby
class DataExtractionJob < ApplicationJob
  def perform(user_id)
    user = User.find(user_id)
    extractor = ActiveRecordGraphExtractor::Extractor.new
    
    # Always dry run first
    analysis = extractor.dry_run(user)
    
    # Check if extraction is feasible
    if analysis['extraction_scope']['total_estimated_records'] > 100_000
      Rails.logger.warn "Large extraction requested for user #{user_id}"
      # Maybe split into smaller jobs or use different strategy
      return
    end
    
    # Proceed with actual extraction
    result = extractor.extract(user, "user_#{user_id}_data.json")
    Rails.logger.info "Extracted #{result.total_records} records"
  end
end
```

## Troubleshooting

### Inaccurate Estimates

Estimates are based on sampling and heuristics. They may be inaccurate if:
- Your data has unusual distribution patterns
- Relationships have highly variable cardinality
- Models have very large or very small average record sizes

### Performance Issues

If dry run analysis itself is slow:
- Reduce the max_depth for analysis
- Check for database performance issues
- Consider if your relationships are properly indexed

### Memory Usage During Analysis

Dry run analysis uses minimal memory as it doesn't load actual record data, only counts and metadata.

## Configuration

Dry run analysis respects the same configuration options as regular extraction:

```ruby
ActiveRecordGraphExtractor.configure do |config|
  config.max_depth = 3
  config.include_models = ['User', 'Order', 'Product']
  config.exclude_relationships = ['audit_logs', 'temp_data']
end

# Analysis will use these configuration settings
analysis = extractor.dry_run(user)
```

## Limitations

1. **Estimates Only**: Results are estimates based on sampling and heuristics
2. **Database Dependent**: Accuracy depends on database statistics and data distribution
3. **Static Analysis**: Cannot account for dynamic filtering or custom serializers
4. **Relationship Complexity**: Complex polymorphic relationships may not be fully analyzed

## See Also

- [Usage Guide](usage.md) - General extraction usage
- [S3 Integration](s3_integration.md) - S3 upload capabilities
- [Examples](examples.md) - More usage examples 