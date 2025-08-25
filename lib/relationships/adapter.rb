# frozen_string_literal: true

##
# Base class for relationship detection adapters
class RelationshipAdapter
  def detect_relationships(document_id, db)
    raise NotImplementedError, 'Subclasses must implement detect_relationships'
  end

  protected

  def create_relationship(source_id, target_id, type, confidence = 1.0, attribute_name = nil)
    {
      source_node_id: source_id,
      target_node_id: target_id,
      reference_type: type,
      attribute_name: attribute_name,
      confidence: confidence
    }
  end
end
