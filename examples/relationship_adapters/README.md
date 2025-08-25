# Relationship Adapter Examples

This directory contains example relationship adapters that demonstrate advanced
relationship detection capabilities beyond the core adapters.

## Core Adapters (Built-in)

The core relationship system includes two essential adapters:

1. **StructuralRelationshipAdapter** - Detects document structure relationships:

   - Parent-child relationships
   - Sibling relationships (including adjacent siblings)
   - Ancestor-descendant relationships

2. **AttributeReferenceAdapter** - Detects direct ID references:
   - Single attribute values that reference other element IDs
   - High-confidence pattern matching for common ID formats

## Example Adapters

### MultiReferenceAdapter

Handles attribute values containing multiple ID references separated by commas
or spaces.

**Example XML:**

```xml
<book id="book_1" authors="author_1,author_2" tags="fiction scifi"/>
<author id="author_1"/>
<author id="author_2"/>
```

**Usage:**

```ruby
detector = RelationshipDetector.new(db)
detector.add_adapter(MultiReferenceAdapter.new)
```

**Detected relationships:**

- `book_1` → `author_1` (multi_attribute_reference via authors)
- `book_1` → `author_2` (multi_attribute_reference via authors)

### SemanticRelationshipAdapter

Detects relationships based on content similarity and element types.

**Features:**

- Groups elements of the same type (`same_type` relationships)
- Detects content similarity between elements
- Useful for finding related content across documents

**Usage:**

```ruby
detector = RelationshipDetector.new(db)
detector.add_adapter(SemanticRelationshipAdapter.new)
```

## Creating Custom Adapters

To create your own relationship adapter:

1. Inherit from `RelationshipAdapter`
2. Implement `detect_relationships(document_id, db)` method
3. Use `create_relationship(source_id, target_id, type, confidence,
   attribute_name)` helper
4. Add your adapter with `detector.add_adapter(your_adapter)`

**Example:**

```ruby
class CustomAdapter < RelationshipAdapter
  def detect_relationships(document_id, db)
    relationships = []

    # Your relationship detection logic here
    # relationships << create_relationship(source, target, 'custom_type', 0.9)

    relationships
  end
end
```

## Customizing Core Adapters

You can create your own version of the main application with custom adapter
registration:

```ruby
class CustomXMLToSQLite < XMLToSQLite
  private

  def relationship_adapters
    # Return your preferred combination of adapters
    [
      StructuralRelationshipAdapter.new,
      AttributeReferenceAdapter.new,
      MultiReferenceAdapter.new
    ]
  end
end
```

You can also access the relationship detector directly for runtime
customization:

```ruby
converter = XMLToSQLite.new(options)
converter.relationship_detector.add_adapter(MyCustomAdapter.new)
converter.run!
```

See `examples/custom_main.rb` for a complete example.

## Querying Relationships

For SQL examples and query patterns, see `examples/sql_queries.md` which
includes:

- Basic relationship queries
- Hierarchical queries with recursive CTEs
- Analytical queries for relationship summaries
- Performance tips and indexing strategies

## Performance Considerations

- Core adapters are optimized for the most common relationship types
- Example adapters may have higher computational costs
- Consider the trade-offs between relationship completeness and processing speed
- Use confidence scores to filter low-quality relationships in post-processing
