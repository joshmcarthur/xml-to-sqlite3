#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/inline'
require 'fileutils'
require 'optparse'

gemfile do
  source 'https://rubygems.org'
  gem 'nokogiri'
  gem 'sqlite3'
  gem 'async'
end
require_relative 'lib/schema/manager'
require_relative 'lib/relationships'
require_relative 'lib/async_processor'
Dir.glob(File.join(__dir__, 'db', 'migrate', '*.rb')).each do |file|
  require file
end

##
# Processes a directory of XML files and converts them to a SQLite database representing
# XML document structure.
# Intended for further post-processing, such as generating embeddings, views, graph traversal operations.
# Usage:
#   ruby main.rb -i /path/to/xml/files -o /path/to/output.sqlite3
#
# Options:
#   -i, --input DIR: Input directory containing XML files
#   -f, --force: Force overwrite of existing database
#   -o, --output FILE: Output SQLite database file
#   -v, --verbose: Verbose output
class XMLToSQLite
  attr_reader :relationship_detector

  def initialize(options = {})
    @input_dir = options[:input_dir] || 'xml_files'
    @output_db = options[:output_db] || 'db/output.sqlite3'
    @batch_size = options[:batch_size] || 1000
    @verbose = options[:verbose] || false
    @force = options[:force] || false
    @detect_relationships = options[:detect_relationships] != false # Default to true
    @concurrency = options[:concurrency] || 4
  end

  def run!
    puts 'Starting XML to SQLite conversion...'
    puts "Input directory: #{@input_dir}"
    puts "Output database: #{@output_db}"
    puts "Concurrency: #{@concurrency}"

    setup_database
    _run

    puts "Conversion complete! Database: #{@output_db}"
    print_stats
  end

  private

  def _run
    xml_files = Dir.glob(File.join(@input_dir, '**/*.xml'))
    puts "Found #{xml_files.length} XML files"

    # Process files with async
    processor = AsyncProcessor.new(@db, {
                                     concurrency: @concurrency,
                                     batch_size: @batch_size,
                                     verbose: @verbose,
                                     detect_relationships: @detect_relationships
                                   })

    processor.process_files(xml_files)

    # Commit file processing before relationship detection
    @db.commit

    processor.process_relationships(@relationship_detector, @output_db)

    create_views
    optimize_database
  end

  def setup_database
    FileUtils.rm_f(@output_db) if @force
    @db = SQLite3::Database.new(@output_db)
    @db.execute('PRAGMA foreign_keys = OFF')
    @db.execute('PRAGMA journal_mode = WAL') # Better performance

    SchemaManager.new(@output_db).migrate!
    @db.transaction # Start transaction for bulk inserts

    # Initialize relationship detector if enabled
    return unless @detect_relationships

    @relationship_detector = RelationshipDetector.new(@db)
    register_relationship_adapters
  end

  def create_views
    # Auto-generate views for each node type
    node_types = @db.execute('SELECT DISTINCT node_type FROM nodes').flatten

    node_types.each do |node_type|
      # create_node_type_view(node_type)
    end
  end

  def register_relationship_adapters
    # Register core adapters
    [
      StructuralRelationshipAdapter.new,
      AttributeReferenceAdapter.new
    ].each { |adapter| @relationship_detector.add_adapter(adapter) }
  end

  def optimize_database
    puts 'Optimizing database...'
    @db.execute('PRAGMA foreign_keys = ON')
    @db.execute('PRAGMA optimize')
    @db.execute('VACUUM')
  end

  def print_stats
    stats = @db.execute("
      SELECT
        COUNT(*) as total_nodes,
        COUNT(DISTINCT node_type) as node_types,
        COUNT(DISTINCT document_id) as documents,
        (SELECT COUNT(*) FROM cross_references) as cross_refs
      FROM nodes
    ").first

    puts "\nDatabase Statistics:"
    puts "Total nodes: #{stats[0]}"
    puts "Node types: #{stats[1]}"
    puts "Documents: #{stats[2]}"
    puts "Cross-references: #{stats[3]}"

    file_size = File.size(@output_db) / (1024 * 1024.0)
    puts "Database size: #{file_size.round(2)} MB"
  end
end

# CLI interface
options = {}
OptionParser.new do |opts|
  opts.banner = 'Usage: xml_to_sqlite.rb [options]'

  opts.on('-i', '--input DIR', 'Input directory containing XML files') do |dir|
    options[:input_dir] = dir
  end

  opts.on('-o', '--output FILE', 'Output SQLite database file') do |file|
    options[:output_db] = file
  end

  opts.on('-f', '--force', 'Force overwrite of existing database') do |f|
    options[:force] = f
  end

  opts.on('-v', '--verbose', 'Verbose output') do |v|
    options[:verbose] = v
  end

  opts.on('-c', '--concurrency N', Integer, 'Number of concurrent processors (default: 4)') do |n|
    options[:concurrency] = n
  end

  opts.on('--no-relationships', 'Disable relationship detection') do
    options[:detect_relationships] = false
  end
end.parse!

# Only run if this is the main script
XMLToSQLite.new(options).run! if __FILE__ == $PROGRAM_NAME
