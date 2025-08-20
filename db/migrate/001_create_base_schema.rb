# frozen_string_literal: true

class CreateBaseSchema
  def self.up(db)
    db.execute_batch <<~SQL
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );

      CREATE TABLE IF NOT EXISTS documents (
        id TEXT PRIMARY KEY,
        filename TEXT UNIQUE,
        file_hash TEXT,
        file_size INTEGER,
        parsed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );

      CREATE TABLE IF NOT EXISTS nodes (
        id TEXT PRIMARY KEY,
        node_type TEXT NOT NULL,
        document_id TEXT REFERENCES documents(id),
        parent_id TEXT REFERENCES nodes(id),
        position INTEGER NOT NULL DEFAULT 0,
        content TEXT,
        xpath TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

        UNIQUE(parent_id, position)
      );

      CREATE TABLE IF NOT EXISTS node_properties (
        node_id TEXT REFERENCES nodes(id) ON DELETE CASCADE,
        property_name TEXT,
        property_value TEXT,
        data_type TEXT DEFAULT 'string',
        PRIMARY KEY (node_id, property_name)
      );

      CREATE TABLE IF NOT EXISTS cross_references (
        id INTEGER PRIMARY KEY,
        source_node_id TEXT REFERENCES nodes(id),
        target_node_id TEXT,
        reference_type TEXT,
        attribute_name TEXT,
        confidence REAL DEFAULT 1.0,
        source_file TEXT
      );

      -- Indexes
      CREATE INDEX IF NOT EXISTS idx_nodes_parent_position ON nodes(parent_id, position);
      CREATE INDEX IF NOT EXISTS idx_nodes_type ON nodes(node_type);
      CREATE INDEX IF NOT EXISTS idx_properties_name ON node_properties(property_name);
      CREATE INDEX IF NOT EXISTS idx_xrefs_source ON cross_references(source_node_id);
      CREATE INDEX IF NOT EXISTS idx_xrefs_target ON cross_references(target_node_id);
    SQL
  end
end
