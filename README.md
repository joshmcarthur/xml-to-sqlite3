# XML to SQLite3 Converter

A Ruby tool for converting XML documents into a SQLite database that preserves document structure, relationships, and metadata. This tool is designed for further post-processing such as generating embeddings, creating views, and performing graph traversal operations.

## Features

### Currently Implemented

- **XML Document Processing**: Converts XML files to a structured SQLite database
- **Node Extraction**: Extracts all XML elements with their attributes, content, and hierarchical relationships
- **Document Metadata**: Tracks file information including size, filename, and parsing timestamps
- **XPath Preservation**: Stores XPath expressions for each node for precise location tracking
- **Property Storage**: Converts XML attributes to database properties with inferred data types
- **Batch Processing**: Efficiently processes large numbers of XML files with configurable batch sizes
- **Database Optimization**: Includes VACUUM and optimization operations
- **Migration System**: Database schema versioning and migration support

### Planned Features

- **Relationship Derivation**: Automatic detection and storage of relationships between nodes
- **Attribute Relationship Analysis**: Cross-referencing nodes based on shared attributes
- **View Generation**: Auto-generated views for each node type
- **Graph Traversal**: Built-in functions for navigating node relationships
- **Embedding Support**: Integration with vector databases for semantic search (planned)
- **RubyGem Packaging**: Distribution as a proper Ruby gem

## Installation

### Prerequisites

- Ruby 2.7 or higher
- SQLite3

### Setup

1. Clone the repository:

   ```bash
   git clone https://github.com/joshmcarthur/xml-to-sqlite3.git
   cd xml-to-sqlite3
   ```

2. The tool uses inline gemfile dependencies, so no additional setup is required.

## Usage

### Basic Usage

```bash
# Convert XML files from a directory to SQLite database
ruby main.rb -i /path/to/xml/files -o output.sqlite3

# With verbose output
ruby main.rb -i /path/to/xml/files -o output.sqlite3 -v

# Force overwrite existing database
ruby main.rb -i /path/to/xml/files -o output.sqlite3 -f
```

### Command Line Options

- `-i, --input DIR`: Input directory containing XML files (default: `xml_files`)
- `-o, --output FILE`: Output SQLite database file (default: `db/output.sqlite3`)
- `-f, --force`: Force overwrite of existing database
- `-v, --verbose`: Verbose output showing processing progress

### Programmatic Usage

```ruby
require_relative 'main'

converter = XMLToSQLite.new(
  input_dir: '/path/to/xml/files',
  output_db: 'output.sqlite3',
  batch_size: 1000,
  verbose: true,
  force: false
)

converter.run!
```

## Database Schema

The tool creates a comprehensive database schema that preserves XML structure:

### Documents Table

Stores metadata about processed XML files:

- `id`: Document identifier (derived from filename)
- `filename`: Full path to the XML file
- `file_size`: Size of the file in bytes
- `parsed_at`: Timestamp when the file was processed

### Nodes Table

Represents XML elements with their hierarchical relationships:

- `id`: Node identifier (from XML `id` attribute)
- `node_type`: XML element name
- `document_id`: Reference to the source document
- `parent_id`: Reference to parent node (for hierarchy)
- `position`: Position among siblings
- `content`: Text content of the element
- `xpath`: XPath expression for the element
- `created_at`: Timestamp when the node was created

### Node Properties Table

Stores XML attributes as key-value pairs:

- `node_id`: Reference to the node
- `property_name`: Attribute name
- `property_value`: Attribute value
- `data_type`: Inferred data type (string, integer, float, boolean, datetime)

### Cross References Table

- `source_node_id`: Source node reference
- `target_node_id`: Target node reference
- `reference_type`: Type of relationship
- `attribute_name`: Attribute used for the reference
- `confidence`: Confidence score for the relationship
- `source_file`: Source of the relationship

## Example Queries

### Find all nodes of a specific type

```sql
SELECT * FROM nodes WHERE node_type = 'book';
```

### Get hierarchical structure

```sql
WITH RECURSIVE node_tree AS (
  SELECT id, node_type, parent_id, content, 0 as level
  FROM nodes WHERE parent_id IS NULL
  UNION ALL
  SELECT n.id, n.node_type, n.parent_id, n.content, nt.level + 1
  FROM nodes n
  JOIN node_tree nt ON n.parent_id = nt.id
)
SELECT * FROM node_tree ORDER BY level, id;
```

### Search for nodes with specific attributes

```sql
SELECT n.*, np.property_value
FROM nodes n
JOIN node_properties np ON n.id = np.node_id
WHERE np.property_name = 'category' AND np.property_value = 'fiction';
```

### Content search (using LIKE)

```sql
SELECT * FROM nodes WHERE content LIKE '%search term%';
```

## Performance Considerations

- **Batch Processing**: The tool processes files in configurable batches to manage memory usage
- **WAL Mode**: Uses SQLite's WAL journal mode for better concurrent access
- **Indexes**: Automatic creation of indexes on frequently queried columns
- **VACUUM**: Database optimization after processing

## Development

### Project Structure

```
xml-to-sqlite3/
├── main.rb                 # Main application entry point
|   ├── lib/
│   │   ├── schema/
│   │   └── relationships/
│   │       ├── adapter.rb     # Base adapter class
│   │       ├── manager.rb     # Relationship manager
│   │       └── detector.rb    # Relationship detector
│   │       └── adapters/      # Adapter implementations
├── db/
│   └── migrate/           # Database migrations
│       └── 001_create_base_schema.rb
│       └── 002_enhance_relationships.rb
│       └── 00x_migration_name.rb
|
└── README.md
```

### Adding New Features

1. **Database Schema Changes**: Create new migration files in `db/migrate/`
2. **Core Logic**: Extend the `XMLToSQLite` class in `main.rb`

### Testing

The project includes a comprehensive test suite using Minitest that covers:

- **Basic Functionality**: Database schema creation, XML processing, node extraction
- **SQL Operations**: All SQL queries documented in the README
- **Edge Cases**: Error handling, special characters, malformed XML, etc.

#### Running Tests

```bash
# Run all tests
rake test
```

#### Test Structure

```
test/
├── test_helper.rb              # Test setup and utilities
├── test_basic_functionality.rb # Core functionality tests
├── test_sql_operations.rb      # SQL query tests
├── test_edge_cases.rb          # Edge case and error handling tests
└── fixtures/                  # XML test fixtures
    ├── sample_library.xml     # Complex library catalog example
    └── simple.xml             # Simple XML for basic tests
```

The tests use temporary databases and files to ensure isolation and cleanup.

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

See LICENSE.md for license information.

## Roadmap

### Short Term

- [x] Implement relationship derivation between nodes
- [x] Add attribute-based cross-referencing

### Medium Term

- [ ] Package as RubyGem
- [ ] Add configuration file support
- [x] Add support for custom relationship types
- [ ] Create auto-generated views for node types
- [ ] Automatically create FTS indexes for full-text search
- [ ] Add support for vectorisation of node content

## Support

For issues, questions, or contributions, please use the GitHub issue tracker or create a pull request.
