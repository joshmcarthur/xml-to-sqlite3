# frozen_string_literal: true

require_relative '../adapter'

##
# Detects semantic relationships based on content similarity and context
class SemanticRelationshipAdapter < RelationshipAdapter
  def detect_relationships(document_id, db)
    relationships = []

    # Get nodes with their content and types
    nodes = db.execute(
      'SELECT id, node_type, content FROM nodes WHERE document_id = ? AND content IS NOT NULL',
      [document_id]
    )

    # Detect same-type groupings
    relationships.concat(detect_type_groupings(nodes))

    # Detect content-based relationships
    relationships.concat(detect_content_relationships(nodes))

    relationships
  end

  private

  def detect_type_groupings(nodes)
    relationships = []

    # Group nodes by type
    nodes_by_type = nodes.group_by { |node| node[1] } # node_type

    nodes_by_type.each_value do |type_nodes|
      next if type_nodes.length < 2

      # Create "same_type" relationships between nodes of the same type
      type_nodes.each do |node1|
        type_nodes.each do |node2|
          next if node1[0] == node2[0] # Skip self-references

          relationships << create_relationship(
            node1[0], node2[0], 'same_type', 0.6
          )
        end
      end
    end

    relationships
  end

  def detect_content_relationships(nodes)
    relationships = []

    # Simple content similarity detection
    nodes.each do |node1|
      nodes.each do |node2|
        next if node1[0] == node2[0] # Skip self-references

        similarity = calculate_content_similarity(node1[2], node2[2])
        next if similarity < 0.7 # Only high-confidence similarities

        relationships << create_relationship(
          node1[0], node2[0], 'content_similar', similarity * 0.5 # Conservative confidence
        )
      end
    end

    relationships
  end

  def calculate_content_similarity(content1, content2)
    return 0.0 if content1.nil? || content2.nil? || content1.empty? || content2.empty?

    # Simple word-based similarity
    words1 = content1.downcase.scan(/\w+/).to_set
    words2 = content2.downcase.scan(/\w+/).to_set

    intersection = words1 & words2
    union = words1 | words2

    return 0.0 if union.empty?

    intersection.size.to_f / union.size
  end
end
