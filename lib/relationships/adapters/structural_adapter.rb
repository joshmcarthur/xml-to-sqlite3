# frozen_string_literal: true

require_relative '../adapter'

##
# Detects structural relationships like parent-child, siblings, ancestry
class StructuralRelationshipAdapter < RelationshipAdapter
  def detect_relationships(document_id, db)
    relationships = []

    # Get all nodes for this document
    nodes = db.execute(
      'SELECT id, parent_id, position, node_type FROM nodes WHERE document_id = ? ORDER BY parent_id, position',
      [document_id]
    )

    # Build direct parent-child relationships
    relationships.concat(detect_parent_child_relationships(nodes))

    # Build sibling relationships
    relationships.concat(detect_sibling_relationships(nodes))

    relationships
  end

  private

  def detect_parent_child_relationships(nodes)
    relationships = []

    nodes.each do |node|
      id, parent_id, = node
      next unless parent_id

      # Direct parent-child relationship
      relationships << create_relationship(parent_id, id, 'parent_child', 1.0)
      relationships << create_relationship(id, parent_id, 'child_parent', 1.0)
    end

    relationships
  end

  def detect_sibling_relationships(nodes) # rubocop:disable Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity
    relationships = []

    # Group nodes by parent
    siblings_by_parent = nodes.group_by { |node| node[1] } # parent_id

    siblings_by_parent.each do |parent_id, siblings|
      next if siblings.length < 2 || parent_id.nil?

      siblings.each_with_index do |sibling1, i|
        siblings.each_with_index do |sibling2, j|
          next if i >= j # Avoid duplicates and self-references

          id1, _, pos1, = sibling1
          id2, _, pos2, = sibling2

          relationships << create_relationship(id1, id2, 'sibling', 1.0)
          relationships << create_relationship(id2, id1, 'sibling', 1.0)

          # Adjacent sibling relationships
          if (pos1 - pos2).abs == 1
            if pos1 < pos2
              relationships << create_relationship(id1, id2, 'next_sibling', 1.0)
              relationships << create_relationship(id2, id1, 'previous_sibling', 1.0)
            else
              relationships << create_relationship(id2, id1, 'next_sibling', 1.0)
              relationships << create_relationship(id1, id2, 'previous_sibling', 1.0)
            end
          end
        end
      end
    end

    relationships
  end
end
