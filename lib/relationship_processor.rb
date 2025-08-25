# frozen_string_literal: true

require 'async'
require 'async/queue'
require 'sqlite3'
require_relative 'database_writer'

##
# Handles parallel relationship detection with single-threaded writing
class RelationshipProcessor
  def initialize(db_path, verbose: false)
    @db_path = db_path
    @verbose = verbose
    @relationship_queue_size = 100
  end

  def detect_all_relationships(relationship_detector, write_db)
    puts 'Detecting relationships between nodes...'

    documents = write_db.execute('SELECT id FROM documents')
    relationship_queue = Async::Queue.new

    Async do |task|
      # Create shared database writer for relationships
      db_writer = DatabaseWriter.new(write_db, 1000, verbose: @verbose)
      writer_task = task.async { relationship_writer(relationship_queue, db_writer) }

      # Process each document's relationships in parallel
      processor_tasks = documents.map do |doc|
        task.async { detect_document_relationships(doc[0], relationship_detector, relationship_queue) }
      end

      # Wait for all relationship detection to complete
      processor_tasks.each(&:wait)

      # Signal writer to finish
      relationship_queue.enqueue(nil)
      writer_task.wait
    end
  end

  private

  def detect_document_relationships(document_id, relationship_detector, queue)
    # Each document's relationships computed independently
    read_db = SQLite3::Database.new(@db_path)
    read_db.execute('PRAGMA query_only = ON')

    begin
      relationships = []
      relationship_detector.adapters.each do |adapter|
        adapter_rels = adapter.detect_relationships(document_id, read_db)
        relationships.concat(adapter_rels)
      end

      # Queue relationships for writing
      queue.enqueue({ document_id: document_id, relationships: relationships })
    ensure
      read_db.close
    end
  end

  def relationship_writer(queue, db_writer)
    total_relationships = 0

    while (data = queue.dequeue)
      break if data.nil?

      relationships = data[:relationships]
      document_id = data[:document_id]

      # Use shared database writer for relationships
      db_writer.write_relationships(relationships, document_id)
      total_relationships += relationships.length
    end

    puts "Total relationships detected: #{total_relationships}"
  end
end
