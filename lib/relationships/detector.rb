# frozen_string_literal: true

require_relative 'manager'

##
# Main detector that orchestrates relationship adapters
# Adapters must be explicitly registered using add_adapter()
class RelationshipDetector
  def initialize(db)
    @manager = RelationshipManager.new(db)
  end

  def detect_all_relationships(document_id)
    total_relationships = @manager.detect_relationships(document_id)
    puts "Detected #{total_relationships} relationships for document #{document_id}"
    total_relationships
  end

  def add_adapter(adapter)
    @manager.add_adapter(adapter)
  end

  def adapters
    @manager.adapters
  end

  # Alias for backwards compatibility with examples
  alias add_custom_adapter add_adapter
end
