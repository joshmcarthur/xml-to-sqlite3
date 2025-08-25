# frozen_string_literal: true

require 'async'
require 'async/queue'
require_relative 'document_parser'
require_relative 'database_writer'
require_relative 'relationship_processor'

##
# Coordinates async processing of XML documents
# Handles the producer-consumer pattern for parallel document processing
class AsyncProcessor
  def initialize(db, options = {})
    @db = db
    @concurrency = options[:concurrency] || 4
    @batch_size = options[:batch_size] || 1000
    @document_queue_size = options[:document_queue_size] || 50
    @verbose = options[:verbose] || false
    @detect_relationships = options[:detect_relationships] != false

    @document_queue = Async::Queue.new
  end

  def process_files(xml_files)
    Async do |task|
      # Start the database writer (single consumer)
      writer = DatabaseWriter.new(@db, @batch_size, verbose: @verbose)
      writer_task = task.async { writer.process_queue(@document_queue) }

      # Start document processors (multiple producers)
      processor_tasks = xml_files.map do |file|
        task.async { process_single_file(file) }
      end

      # Wait for all documents to be processed
      processor_tasks.each(&:wait)

      # Signal writer to finish
      @document_queue.enqueue(nil)
      writer_task.wait

      puts "Completed processing #{xml_files.length} files"
    end
  end

  def process_relationships(relationship_detector, output_db_path)
    return unless @detect_relationships

    processor = RelationshipProcessor.new(output_db_path, verbose: @verbose)
    processor.detect_all_relationships(relationship_detector, @db)
  end

  private

  def process_single_file(xml_file)
    puts "Processing #{xml_file}" if @verbose

    begin
      parser = DocumentParser.new
      document_data = parser.parse_file(xml_file)
      @document_queue.enqueue(document_data) if document_data
    rescue StandardError => e
      puts "Error processing #{xml_file}: #{e.message}"
    end
  end
end
