# frozen_string_literal: true

# Example adapter showing how to handle multiple ID references in attributes
# This extends the basic AttributeReferenceAdapter to handle comma/space-separated values
#
# Usage:
#   detector = RelationshipDetector.new(db)
#   detector.add_custom_adapter(MultiReferenceAdapter.new)

require_relative '../../lib/relationships/adapter'

class MultiReferenceAdapter < RelationshipAdapter
  def detect_relationships(document_id, db)
    relationships = []

    # Get all node properties for this document
    properties = db.execute(
      'SELECT np.node_id, np.property_name, np.property_value
       FROM node_properties np
       JOIN nodes n ON np.node_id = n.id
       WHERE n.document_id = ?',
      [document_id]
    )

    # Get all existing node IDs for this document
    node_ids = db.execute(
      'SELECT id FROM nodes WHERE document_id = ?',
      [document_id]
    ).flatten.to_set

    # Check each property value for multiple references
    properties.each do |property|
      node_id, property_name, property_value = property

      # Only process values that contain separators
      next unless property_value&.match?(/[,\s]/)

      relationships.concat(detect_multi_references(
                             node_id, property_name, property_value, node_ids
                           ))
    end

    relationships
  end

  private

  def detect_multi_references(source_id, property_name, property_value, node_ids)
    relationships = []

    # Split by comma or space and check each part
    referenced_ids = property_value.split(/[,\s]+/).map(&:strip).reject(&:empty?)

    referenced_ids.each do |ref_id|
      next unless node_ids.include?(ref_id)
      next unless valid_id_pattern?(ref_id)

      confidence = calculate_confidence(property_name, ref_id) * 0.8 # Lower confidence for multi-refs
      relationships << create_relationship(
        source_id, ref_id, 'multi_attribute_reference', confidence, property_name
      )
    end

    relationships
  end

  def valid_id_pattern?(value)
    # Common patterns for ID references
    patterns = [
      /^[a-zA-Z_][a-zA-Z0-9_]*$/, # Simple identifier
      /^[a-zA-Z]+_\d+$/,          # prefix_number pattern
      /^[a-zA-Z0-9]+(-[a-zA-Z0-9]+)*$/ # hyphenated identifiers
    ]

    patterns.any? { |pattern| value.match?(pattern) }
  end

  def calculate_confidence(property_name, property_value)
    reference_indicators = %w[ids refs references targets sources links]
    base_confidence = 0.6

    # Boost confidence if property name suggests multiple references
    base_confidence += 0.2 if reference_indicators.any? { |indicator| property_name.downcase.include?(indicator) }

    # Boost confidence if value follows ID patterns
    base_confidence += 0.1 if property_value.match?(/^[a-zA-Z]+_[a-zA-Z0-9]+$/)

    [base_confidence, 1.0].min
  end
end
