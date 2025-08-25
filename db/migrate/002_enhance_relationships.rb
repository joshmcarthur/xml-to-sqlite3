# frozen_string_literal: true

class EnhanceRelationships
  def self.up(db)
    db.execute_batch <<~SQL
      -- Add essential indexes for relationship queries
      CREATE INDEX IF NOT EXISTS idx_xrefs_type ON cross_references(reference_type);
      CREATE INDEX IF NOT EXISTS idx_xrefs_confidence ON cross_references(confidence);
      CREATE INDEX IF NOT EXISTS idx_xrefs_attribute ON cross_references(attribute_name);
      CREATE INDEX IF NOT EXISTS idx_xrefs_source_type ON cross_references(source_node_id, reference_type);
      CREATE INDEX IF NOT EXISTS idx_xrefs_target_type ON cross_references(target_node_id, reference_type);
    SQL
  end
end
