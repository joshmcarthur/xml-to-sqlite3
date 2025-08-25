# frozen_string_literal: true

##
# Single-threaded database writer
# Consumes parsed documents from queue and writes to SQLite
class DatabaseWriter
  def initialize(db, batch_size, verbose: false)
    @db = db
    @batch_size = batch_size
    @verbose = verbose
    setup_prepared_statements
  end

  def process_queue(document_queue)
    documents_written = 0

    while (document_data = document_queue.dequeue)
      break if document_data.nil? # Sentinel value

      write_document_to_database(document_data)
      documents_written += 1

      # Periodic commits for progress tracking
      if (documents_written % @batch_size).zero?
        commit_and_restart_transaction
        puts "Written #{documents_written} documents to database..." if @verbose
      end
    end

    puts "Completed writing #{documents_written} documents"
  end

  def write_relationships(relationships, document_id = nil)
    relationships.each do |rel|
      @insert_relationship.execute(
        rel[:source_node_id], rel[:target_node_id], rel[:reference_type],
        rel[:attribute_name], rel[:confidence], rel[:source_file]
      )
    end

    puts "Processed relationships for document #{document_id}: #{relationships.length} found" if document_id && @verbose
  end

  private

  def setup_prepared_statements
    @insert_document = @db.prepare(
      'INSERT OR REPLACE INTO documents (id, filename, file_size) VALUES (?, ?, ?)'
    )
    @insert_node = @db.prepare(
      'INSERT OR REPLACE INTO nodes (id, node_type, document_id, parent_id, position, content, xpath)
                                    VALUES (?, ?, ?, ?, ?, ?, ?)'
    )
    @insert_property = @db.prepare(
      'INSERT OR REPLACE INTO node_properties (node_id, property_name, property_value, data_type) VALUES (?, ?, ?, ?)'
    )
    @insert_relationship = @db.prepare(
      'INSERT OR REPLACE INTO cross_references (source_node_id, target_node_id, reference_type,
                                                attribute_name, confidence, source_file) VALUES (?, ?, ?, ?, ?, ?)'
    )
  end

  def write_document_to_database(data)
    # Write document record
    doc = data[:document]
    @insert_document.execute(doc[:id], doc[:filename], doc[:file_size])

    # Write all nodes for this document
    data[:nodes].each do |node|
      @insert_node.execute(
        node[:id], node[:node_type], node[:document_id],
        node[:parent_id], node[:position], node[:content], node[:xpath]
      )
    end

    # Write all properties for this document
    data[:properties].each do |prop|
      @insert_property.execute(
        prop[:node_id], prop[:property_name],
        prop[:property_value], prop[:data_type]
      )
    end
  end

  def commit_and_restart_transaction
    @db.commit
    @db.transaction
  end
end
