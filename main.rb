#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/inline'
require 'fileutils'
require 'optparse'

gemfile do
  source 'https://rubygems.org'
  gem 'nokogiri'
  gem 'sqlite3'
end
require_relative 'lib/schema/manager'
require_relative 'lib/relationships'
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
  end

  def run!
    puts 'Starting XML to SQLite conversion...'
    puts "Input directory: #{@input_dir}"
    puts "Output database: #{@output_db}"

    # Setup database
    setup_database

    # Process files
    xml_files = Dir.glob(File.join(@input_dir, '**/*.xml'))
    puts "Found #{xml_files.length} XML files"

    xml_files.each_with_index do |file, index|
      puts "Processing #{file} (#{index + 1}/#{xml_files.length})" if @verbose
      process_xml_file(file)

      # Commit every batch_size files
      next unless ((index + 1) % @batch_size).zero?

      @db.commit
      @db.transaction
      puts "Processed #{index + 1} files..."
    end

    # Final steps
    detect_relationships if @detect_relationships
    create_views

    @db.commit
    optimize_database

    puts "Conversion complete! Database: #{@output_db}"
    print_stats
  end

  private

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

  def detect_relationships
    puts 'Detecting relationships between nodes...'

    # Get all documents
    documents = @db.execute('SELECT id FROM documents')

    total_relationships = 0
    documents.each do |doc|
      document_id = doc[0]
      relationships_count = @relationship_detector.detect_all_relationships(document_id)
      total_relationships += relationships_count
    end

    puts "Total relationships detected: #{total_relationships}"
  end

  def create_views
    # Auto-generate views for each node type
    node_types = @db.execute('SELECT DISTINCT node_type FROM nodes').flatten

    node_types.each do |node_type|
      # create_node_type_view(node_type)
    end
  end

  def relationship_adapters
    [
    ]
  end

  def register_relationship_adapters
    relationship_adapters.each do |adapter|
      @relationship_detector.add_adapter(adapter)
    end
  end

  def optimize_database
    puts 'Optimizing database...'
    @db.execute('PRAGMA foreign_keys = ON')
    @db.execute('PRAGMA optimize')
    @db.execute('VACUUM')
  end

  def process_xml_file(xml_file)
    # First, ensure the document is recorded
    document_id = File.basename(xml_file, '.xml')
    @db.execute(
      'INSERT OR REPLACE INTO documents (id, filename, file_size) VALUES (?, ?, ?)',
      [document_id, xml_file, File.size(xml_file)]
    )

    doc = Nokogiri::XML(File.open(xml_file), &:noblanks)

    # Extract nodes and relationships
    doc.xpath('//*[@id]').each do |element|
      process_element(element, document_id)
    end
  end

  def get_position(element)
    return 0 unless element.parent

    # Get all sibling elements (not text nodes) and find the position of current element
    siblings = element.parent.children.select(&:element?)
    siblings.index(element) || 0
  end

  def infer_type(value)
    return 'string' if value.nil? || value.empty?

    # Try to infer the data type based on the value
    case value
    when /^\d+$/
      'integer'
    when /^\d+\.\d+$/
      'float'
    when /^(true|false)$/i
      'boolean'
    when /^\d{4}-\d{2}-\d{2}/, /^\d{2}:\d{2}:\d{2}/
      'datetime'
    else
      'string'
    end
  end

  def process_element(element, document_id)
    # Generate XPath for the element
    xpath = element.path

    # Handle parent_id safely
    parent_id = element.parent && element.parent['id'] ? element.parent['id'] : nil

    @db.execute(
      'INSERT OR REPLACE INTO nodes (id, node_type, document_id, parent_id, position, content, xpath)
                                    VALUES (?, ?, ?, ?, ?, ?, ?)',
      [element['id'], element.name, document_id, parent_id, get_position(element), element.text&.strip, xpath]
    )

    element.attributes.each do |name, attr|
      next if name == 'id'

      @db.execute(
        'INSERT OR REPLACE INTO node_properties (node_id, property_name, property_value, data_type)
                                                VALUES (?, ?, ?, ?)',
        [element['id'], name, attr.value, infer_type(attr.value)]
      )
    end
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

  opts.on('--no-relationships', 'Disable relationship detection') do
    options[:detect_relationships] = false
  end
end.parse!

# Only run if this is the main script
XMLToSQLite.new(options).run! if __FILE__ == $PROGRAM_NAME
