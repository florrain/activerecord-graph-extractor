#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Dry Run Analysis
# This script demonstrates how to use the dry run feature to analyze
# what would be extracted without performing the actual extraction.

require 'bundler/setup'
require 'activerecord_graph_extractor'

# This would typically be in your Rails application
# For this example, we'll assume you have User and Order models

puts "🔍 ActiveRecord Graph Extractor - Dry Run Examples"
puts "=" * 60
puts

# Example 1: Basic Dry Run Analysis
puts "1. Basic Dry Run Analysis"
puts "-" * 30

begin
  # Find a user to analyze
  user = User.first
  
  if user
    extractor = ActiveRecordGraphExtractor::Extractor.new
    
    puts "Analyzing User ##{user.id}..."
    analysis = extractor.dry_run(user)
    
    puts "✅ Analysis completed in #{analysis['analysis_time']} seconds"
    puts
    puts "📊 Summary:"
    puts "   Models involved: #{analysis['extraction_scope']['total_models']}"
    puts "   Estimated records: #{analysis['extraction_scope']['total_estimated_records']}"
    puts "   Estimated file size: #{analysis['estimated_file_size']['human_readable']}"
    puts "   Estimated extraction time: #{analysis['performance_estimates']['estimated_extraction_time_human']}"
    puts
    
    # Show model breakdown
    puts "📋 Records by Model:"
    analysis['estimated_counts_by_model'].each do |model, count|
      percentage = (count.to_f / analysis['extraction_scope']['total_estimated_records'] * 100).round(1)
      puts "   #{model.ljust(20)} #{count.to_s.rjust(8)} (#{percentage}%)"
    end
    puts
  else
    puts "❌ No users found in database"
  end
rescue => e
  puts "❌ Error: #{e.message}"
end

# Example 2: Dry Run with Custom Depth
puts "2. Dry Run with Custom Max Depth"
puts "-" * 35

begin
  user = User.first
  
  if user
    extractor = ActiveRecordGraphExtractor::Extractor.new
    
    # Compare different depths
    [1, 2, 3].each do |depth|
      analysis = extractor.dry_run(user, max_depth: depth)
      
      puts "Depth #{depth}:"
      puts "   Models: #{analysis['extraction_scope']['total_models']}"
      puts "   Records: #{analysis['extraction_scope']['total_estimated_records']}"
      puts "   File size: #{analysis['estimated_file_size']['human_readable']}"
      puts "   Time: #{analysis['performance_estimates']['estimated_extraction_time_human']}"
      puts
    end
  end
rescue => e
  puts "❌ Error: #{e.message}"
end

# Example 3: Analyzing Multiple Objects
puts "3. Multiple Objects Analysis"
puts "-" * 30

begin
  users = User.limit(3).to_a
  
  if users.any?
    extractor = ActiveRecordGraphExtractor::Extractor.new
    
    analysis = extractor.dry_run(users)
    
    puts "Analyzing #{users.size} users..."
    puts "✅ Analysis completed"
    puts
    puts "📊 Summary:"
    puts "   Root objects: #{analysis['root_objects']['count']}"
    puts "   Total estimated records: #{analysis['extraction_scope']['total_estimated_records']}"
    puts "   Estimated file size: #{analysis['estimated_file_size']['human_readable']}"
    puts
  end
rescue => e
  puts "❌ Error: #{e.message}"
end

# Example 4: Analyzing Warnings and Recommendations
puts "4. Warnings and Recommendations"
puts "-" * 35

begin
  # Try to find a user with many relationships to trigger warnings
  user = User.joins(:orders).group('users.id').having('COUNT(orders.id) > 0').first
  
  if user
    extractor = ActiveRecordGraphExtractor::Extractor.new
    
    analysis = extractor.dry_run(user, max_depth: 5)
    
    # Show warnings
    if analysis['warnings'].any?
      puts "⚠️  Warnings:"
      analysis['warnings'].each do |warning|
        puts "   #{warning['type'].upcase} (#{warning['severity']}): #{warning['message']}"
      end
      puts
    else
      puts "✅ No warnings detected"
      puts
    end
    
    # Show recommendations
    if analysis['recommendations'].any?
      puts "💡 Recommendations:"
      analysis['recommendations'].each do |rec|
        puts "   #{rec['type'].upcase}: #{rec['message']}"
        puts "   → #{rec['action']}"
        puts
      end
    else
      puts "✅ No specific recommendations"
      puts
    end
  end
rescue => e
  puts "❌ Error: #{e.message}"
end

# Example 5: Saving Analysis Report
puts "5. Saving Analysis Report"
puts "-" * 28

begin
  user = User.first
  
  if user
    extractor = ActiveRecordGraphExtractor::Extractor.new
    
    analysis = extractor.dry_run(user)
    
    # Save to file
    report_file = "dry_run_analysis_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json"
    File.write(report_file, JSON.pretty_generate(analysis))
    
    puts "📄 Analysis report saved to: #{report_file}"
    puts "   File size: #{File.size(report_file)} bytes"
    puts
    
    # Show a sample of the JSON structure
    puts "📋 Report structure:"
    analysis.keys.each do |key|
      puts "   #{key}"
    end
    puts
  end
rescue => e
  puts "❌ Error: #{e.message}"
end

# Example 6: Decision Making Based on Analysis
puts "6. Decision Making Example"
puts "-" * 28

begin
  user = User.first
  
  if user
    extractor = ActiveRecordGraphExtractor::Extractor.new
    
    analysis = extractor.dry_run(user)
    
    total_records = analysis['extraction_scope']['total_estimated_records']
    file_size_mb = analysis['estimated_file_size']['bytes'] / (1024.0 * 1024)
    extraction_time = analysis['performance_estimates']['estimated_extraction_time_seconds']
    
    puts "📊 Analysis Results:"
    puts "   Records: #{total_records}"
    puts "   File size: #{file_size_mb.round(1)} MB"
    puts "   Estimated time: #{extraction_time.round(1)} seconds"
    puts
    
    # Make decisions based on analysis
    if total_records > 10_000
      puts "🚨 Large dataset detected!"
      puts "   Recommendation: Consider using batch processing or reducing max_depth"
    elsif file_size_mb > 50
      puts "📦 Large file expected!"
      puts "   Recommendation: Consider uploading directly to S3"
    elsif extraction_time > 300 # 5 minutes
      puts "⏰ Long extraction time expected!"
      puts "   Recommendation: Run during off-peak hours"
    else
      puts "✅ Extraction looks manageable - proceed with confidence!"
    end
    puts
  end
rescue => e
  puts "❌ Error: #{e.message}"
end

puts "🎉 Dry run examples completed!"
puts
puts "💡 Tips:"
puts "   • Use dry run before large extractions to understand scope"
puts "   • Pay attention to warnings and recommendations"
puts "   • Save analysis reports for documentation"
puts "   • Compare different max_depth values to optimize performance"
puts "   • Use dry run results to make informed decisions about extraction strategy" 