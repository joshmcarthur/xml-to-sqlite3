#!/usr/bin/env ruby
# frozen_string_literal: true

# Example showing how to customize relationship adapters
# This demonstrates how users can register their own combination of adapters

require_relative '../main'
require_relative 'relationship_adapters/multi_reference_adapter'

class CustomXMLToSQLite < XMLToSQLite
  private

  def relationship_adapters
    # Return custom set of adapters including multi-reference support
    [
      StructuralRelationshipAdapter.new,
      AttributeReferenceAdapter.new,
      MultiReferenceAdapter.new
    ]
  end

  def register_relationship_adapters
    super
    puts "Registered custom relationship adapters (#{relationship_adapters.length} total)"
  end
end

# Example usage
if __FILE__ == $PROGRAM_NAME
  options = { input_dir: 'test/fixtures', output_db: 'test_custom.sqlite3', force: true }

  # Simple argument parsing for demo
  if ARGV.include?('--help')
    puts 'Usage: ruby examples/custom_main.rb [--help]'
    puts 'This example runs with test fixtures by default.'
    puts 'Edit the file to customize for your needs.'
    exit
  end

  # Use custom version with multi-reference support
  CustomXMLToSQLite.new(options).run!
end
