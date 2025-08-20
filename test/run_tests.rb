#!/usr/bin/env ruby
# frozen_string_literal: true

# Test runner for XML to SQLite3 converter
# Usage: ruby test/run_tests.rb [test_file_pattern]

require_relative 'test_helper'

# Get test pattern from command line arguments
test_pattern = ARGV.first || 'test_*.rb'

# Find all test files matching the pattern
test_files = Dir.glob(File.join(__dir__, test_pattern))
test_files.reject! { |f| f == __FILE__ } # Exclude this runner file

if test_files.empty?
  puts "No test files found matching pattern: #{test_pattern}"
  exit 1
end

puts "Running tests matching: #{test_pattern}"
puts "Found #{test_files.length} test file(s):"
test_files.each { |f| puts "  - #{File.basename(f)}" }
puts

# Run the tests
require 'minitest/autorun'

# Load all test files
test_files.each { |f| require f }

puts "\nAll tests completed!"
