# frozen_string_literal: true

require 'sqlite3'

##
# Manages the detection and storage of relationships between XML nodes
# using an adapter pattern to support different types of relationship detection
class RelationshipManager
  attr_reader :adapters

  def initialize(db)
    @db = db
    @adapters = []
  end

  def add_adapter(adapter)
    @adapters << adapter
  end

  def detect_relationships(document_id)
    puts "Detecting relationships for document: #{document_id}"

    relationships = []
    @adapters.each do |adapter|
      adapter_relationships = adapter.detect_relationships(document_id, @db)
      relationships.concat(adapter_relationships)
    end

    store_relationships(relationships)
    relationships.length
  end

  private

  def store_relationships(relationships)
    relationships.each do |rel|
      @db.execute(
        'INSERT OR REPLACE INTO cross_references
         (source_node_id, target_node_id, reference_type, attribute_name, confidence, source_file)
         VALUES (?, ?, ?, ?, ?, ?)',
        [rel[:source_node_id], rel[:target_node_id], rel[:reference_type],
         rel[:attribute_name], rel[:confidence], rel[:source_file]]
      )
    end
  end
end
