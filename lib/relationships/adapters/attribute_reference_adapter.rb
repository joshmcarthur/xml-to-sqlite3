# frozen_string_literal: true

require_relative '../adapter'

##
# Detects direct attribute references to other element IDs
# This is a core adapter that handles single, unambiguous ID references
class AttributeReferenceAdapter < RelationshipAdapter
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

    # Check each property value for direct ID references
    properties.each do |property|
      relationship = check_property(property, node_ids)
      relationships << relationship if relationship
    end

    relationships
  end

  private

  def check_property(property, node_ids = [])
    node_id, property_name, property_value = property

    # Skip if not a valid single reference
    return unless single_id_reference?(property_value)
    return unless node_ids.include?(property_value)

    confidence = calculate_reference_confidence(property_name, property_value)

    create_relationship(
      node_id, property_value, 'attribute_reference', confidence, property_name
    )
  end

  def single_id_reference?(value)
    return false if value.nil? || value.empty?

    # Common patterns for single ID references
    patterns = [
      /^[a-zA-Z_][a-zA-Z0-9_]*$/, # Simple identifier
      /^[a-zA-Z]+_\d+$/,          # prefix_number pattern
      /^[a-zA-Z0-9]+(-[a-zA-Z0-9]+)*$/ # hyphenated identifiers
    ]

    patterns.any? { |pattern| value.match?(pattern) }
  end

  def calculate_reference_confidence(property_name, property_value)
    # Higher confidence for property names that suggest references
    reference_indicators = %w[id ref reference parent child target source link]

    base_confidence = 0.8 # Higher base confidence for direct references

    # Boost confidence if property name suggests it's a reference
    base_confidence += 0.15 if reference_indicators.any? { |indicator| property_name.downcase.include?(indicator) }

    # Boost confidence if value follows clear ID patterns
    base_confidence += 0.05 if property_value.match?(/^[a-zA-Z]+_[a-zA-Z0-9]+$/)

    [base_confidence, 1.0].min
  end
end
