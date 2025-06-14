#!/usr/bin/env ruby
# frozen_string_literal: true

# Installation Verification Script for ActiveRecord Graph Extractor CLI
# Run this script to verify your installation is working correctly

puts "🔍 ActiveRecord Graph Extractor CLI Installation Verification"
puts "=" * 60

# Check if the arge command is available
def check_command_availability
  print "Checking if 'arge' command is available... "
  
  result = `which arge 2>/dev/null`.strip
  if result.empty?
    puts "❌ NOT FOUND"
    puts
    puts "The 'arge' command is not available in your PATH."
    puts "This could mean:"
    puts "  1. The gem is not installed globally"
    puts "  2. You need to use 'bundle exec arge' instead"
    puts "  3. You need to run 'rbenv rehash' (if using rbenv)"
    puts
    return false
  else
    puts "✅ FOUND at #{result}"
    return true
  end
end

# Check gem installation
def check_gem_installation
  print "Checking gem installation... "
  
  begin
    require 'activerecord_graph_extractor'
    version = ActiveRecordGraphExtractor::VERSION
    puts "✅ INSTALLED (version #{version})"
    return true
  rescue LoadError
    puts "❌ NOT FOUND"
    puts
    puts "The activerecord-graph-extractor gem is not installed or not in your load path."
    puts "Try: gem install activerecord-graph-extractor"
    puts
    return false
  end
end

# Test CLI functionality
def test_cli_functionality
  print "Testing CLI functionality... "
  
  # Try to run the version command
  output = `arge version 2>&1`
  exit_code = $?.exitstatus
  
  if exit_code == 0 && output.include?("ActiveRecord Graph Extractor")
    puts "✅ WORKING"
    puts "   Output: #{output.strip}"
    return true
  else
    puts "❌ FAILED"
    puts "   Exit code: #{exit_code}"
    puts "   Output: #{output}"
    return false
  end
end

# Test CLI help
def test_cli_help
  print "Testing CLI help... "
  
  output = `arge help 2>&1`
  exit_code = $?.exitstatus
  
      expected_commands = ['extract', 'import', 'extract_to_s3', 's3_list', 's3_download', 'analyze', 'dry_run']
  
  if exit_code == 0 && expected_commands.all? { |cmd| output.include?(cmd) }
    puts "✅ ALL COMMANDS AVAILABLE"
    puts "   Available commands: #{expected_commands.join(', ')}"
    return true
  else
    puts "❌ MISSING COMMANDS"
    puts "   Expected: #{expected_commands.join(', ')}"
    puts "   Output: #{output}"
    return false
  end
end

# Check Ruby version
def check_ruby_version
  print "Checking Ruby version... "
  
  ruby_version = RUBY_VERSION
  required_version = Gem::Version.new('2.7.0')
  current_version = Gem::Version.new(ruby_version)
  
  if current_version >= required_version
    puts "✅ COMPATIBLE (#{ruby_version})"
    return true
  else
    puts "❌ TOO OLD (#{ruby_version}, requires >= 2.7.0)"
    puts
    puts "Please upgrade your Ruby version to 2.7.0 or higher."
    puts "Consider using rbenv or RVM to manage Ruby versions."
    puts
    return false
  end
end

# Check if running in Rails environment
def check_rails_environment
  print "Checking Rails environment... "
  
  if defined?(Rails)
    puts "✅ RAILS DETECTED (#{Rails.version})"
    puts "   You can use: bundle exec arge [command]"
    return true
  else
    puts "ℹ️  NO RAILS DETECTED"
    puts "   This is fine for standalone usage"
    return true
  end
end

# Main verification process
def main
  puts
  
  all_checks_passed = true
  
  # Run all checks
  all_checks_passed &= check_ruby_version
  all_checks_passed &= check_gem_installation
  all_checks_passed &= check_rails_environment
  all_checks_passed &= check_command_availability
  
  # Only test CLI if command is available
  if check_command_availability
    all_checks_passed &= test_cli_functionality
    all_checks_passed &= test_cli_help
  else
    # Try with bundle exec if direct command failed
    puts
    puts "Trying with 'bundle exec'..."
    
    bundle_output = `bundle exec arge version 2>&1`
    bundle_exit_code = $?.exitstatus
    
    if bundle_exit_code == 0
      puts "✅ 'bundle exec arge' works!"
      puts "   Use: bundle exec arge [command]"
      puts "   This is normal when the gem is installed via Gemfile"
    else
      puts "❌ 'bundle exec arge' also failed"
      puts "   Output: #{bundle_output}"
      all_checks_passed = false
    end
  end
  
  puts
  puts "=" * 60
  
  if all_checks_passed
    puts "🎉 INSTALLATION VERIFICATION SUCCESSFUL!"
    puts
    puts "Your ActiveRecord Graph Extractor CLI is properly installed and working."
    puts
    puts "Quick start:"
    puts "  arge version                    # Check version"
    puts "  arge help                       # See all commands"
    puts "  arge extract Order 123          # Extract a record (requires Rails)"
    puts "  arge extract_to_s3 Order 123    # Extract to S3 (requires AWS config)"
    puts
  else
    puts "❌ INSTALLATION VERIFICATION FAILED!"
    puts
    puts "Some checks failed. Please review the errors above and:"
    puts "  1. Make sure the gem is properly installed"
    puts "  2. Check your Ruby version (>= 2.7.0 required)"
    puts "  3. Try 'rbenv rehash' if using rbenv"
    puts "  4. Use 'bundle exec arge' if installed via Gemfile"
    puts
    puts "For more help, see the installation guide in the README."
  end
  
  puts
end

# Run the verification
main if __FILE__ == $0 