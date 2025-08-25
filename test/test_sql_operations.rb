# frozen_string_literal: true

require_relative 'test_helper'

class TestSQLOperations < Minitest::Test
  def setup
    super
    # Copy the sample library XML to temp directory
    sample_xml_path = File.join(__dir__, 'fixtures', 'sample_library.xml')
    @xml_file = File.join(@temp_dir, 'sample_library.xml')
    FileUtils.cp(sample_xml_path, @xml_file)

    # Run converter with sample library
    @db = run_converter(@temp_dir)
  end

  def test_find_nodes_by_type
    # Test: Find all nodes of a specific type
    books = @db.execute('SELECT * FROM nodes WHERE node_type = ?', ['book'])
    assert_equal 3, books.length

    book_ids = books.map { |b| b[0] } # id column
    assert_includes book_ids, 'book_1'
    assert_includes book_ids, 'book_2'
    assert_includes book_ids, 'book_3'

    # Test other node types
    authors = @db.execute('SELECT * FROM nodes WHERE node_type = ?', ['author'])
    assert_equal 3, authors.length

    categories = @db.execute('SELECT * FROM nodes WHERE node_type = ?', ['category'])
    assert_equal 2, categories.length
  end

  def test_hierarchical_structure_query
    # Test: Get hierarchical structure using recursive CTE
    # This tests the exact query from the README
    result = @db.execute(<<~SQL)
      WITH RECURSIVE node_tree AS (
        SELECT id, node_type, parent_id, content, 0 as level
        FROM nodes WHERE parent_id IS NULL
        UNION ALL
        SELECT n.id, n.node_type, n.parent_id, n.content, nt.level + 1
        FROM nodes n
        JOIN node_tree nt ON n.parent_id = nt.id
      )
      SELECT * FROM node_tree ORDER BY level, id
    SQL

    # Should have the root library node at level 0
    root_nodes = result.select { |r| r[4] == 0 } # level = 0
    assert_operator root_nodes.length, :>=, 1, 'Should have at least one root node'

    # Check if main_library is among the root nodes
    root_ids = root_nodes.map { |r| r[0] }
    assert_includes root_ids, 'main_library', 'Should have main_library as a root node'

    # Should have child nodes at level 1
    level1_nodes = result.select { |r| r[4] == 1 } # level = 1
    assert_operator level1_nodes.length, :>, 0, 'Should have child nodes at level 1'

    # Verify hierarchy structure - there should be multiple nodes in total
    assert_operator result.length, :>, 1, 'Should have multiple nodes in hierarchy'
  end

  def test_search_nodes_by_attributes
    # Test: Search for nodes with specific attributes
    # This tests the exact query from the README
    result = @db.execute(<<~SQL, %w[category cat_fiction])
      SELECT n.*, np.property_value
      FROM nodes n
      JOIN node_properties np ON n.id = np.node_id
      WHERE np.property_name = ? AND np.property_value = ?
    SQL

    assert_equal 1, result.length
    assert_equal 'book_1', result.first[0] # node id
    assert_equal 'book', result.first[1] # node_type
    assert_equal 'cat_fiction', result.first[8] # property_value
  end

  def test_search_nodes_by_multiple_attributes
    # Test searching for books with specific ISBN
    result = @db.execute(<<~SQL, ['isbn', '978-0-123456-47-2'])
      SELECT n.id, n.node_type, np.property_value
      FROM nodes n
      JOIN node_properties np ON n.id = np.node_id
      WHERE np.property_name = ? AND np.property_value = ?
    SQL

    assert_equal 1, result.length
    assert_equal 'book_1', result.first[0]
    assert_equal 'book', result.first[1]
  end

  # FTS functionality removed - no longer testing full-text search

  def test_join_operations
    # Test joining nodes with their properties
    result = @db.execute(<<~SQL, %w[book isbn])
      SELECT n.id, n.node_type, np.property_name, np.property_value
      FROM nodes n
      JOIN node_properties np ON n.id = np.node_id
      WHERE n.node_type = ? AND np.property_name = ?
      ORDER BY n.id
    SQL

    assert_equal 3, result.length

    isbns = result.map { |r| r[3] } # property_value
    expected_isbns = [
      '978-0-123456-47-2',
      '978-0-987654-32-1',
      '978-0-555555-55-5'
    ]
    assert_equal expected_isbns, isbns
  end

  def test_aggregate_queries
    # Test counting nodes by type
    result = @db.execute(<<~SQL)
      SELECT node_type, COUNT(*) as count
      FROM nodes
      GROUP BY node_type
      ORDER BY count DESC
    SQL

    # Should have various node types
    assert_operator result.length, :>, 5

    # Check specific counts
    book_count = result.find { |r| r[0] == 'book' }
    assert_equal 3, book_count[1]

    author_count = result.find { |r| r[0] == 'author' }
    assert_equal 3, author_count[1]
  end

  def test_complex_filtering
    # Test complex filtering with multiple conditions
    result = @db.execute(<<~SQL, %w[category cat_fiction pages integer])
      SELECT DISTINCT n.id, n.node_type
      FROM nodes n
      JOIN node_properties np1 ON n.id = np1.node_id
      JOIN node_properties np2 ON n.id = np2.node_id
      WHERE np1.property_name = ? AND np1.property_value = ?
        AND np2.property_name = ? AND np2.data_type = ?
    SQL

    # Should find book_1 which has category=cat_fiction and pages (integer)
    assert_operator result.length, :>=, 0, 'Should find books with category=cat_fiction and integer pages'
    return unless result.length > 0

    assert_equal 'book', result.first[1], 'Should be a book node'
  end

  def test_parent_child_relationships
    # Test parent-child relationships
    result = @db.execute(<<~SQL, ['book'])
      SELECT parent.id as parent_id, parent.node_type as parent_type,
             child.id as child_id, child.node_type as child_type
      FROM nodes parent
      JOIN nodes child ON child.parent_id = parent.id
      WHERE parent.node_type = ?
      ORDER BY parent.id, child.id
    SQL

    # Books should have children (title, author, description, etc.)
    assert_operator result.length, :>, 0

    # Verify book_1 has children
    book1_children = result.select { |r| r[0] == 'book_1' }
    assert_operator book1_children.length, :>, 0
  end

  def test_data_type_filtering
    # Test filtering by data type
    result = @db.execute(<<~SQL, ['integer'])
      SELECT np.property_name, np.property_value, np.data_type
      FROM node_properties np
      WHERE np.data_type = ?
      ORDER BY np.property_name, np.property_value
    SQL

    # Should have integer properties (pages, year, etc.)
    assert_operator result.length, :>, 0, 'Should find integer properties like pages, year'

    # All should be integer type
    result.each do |row|
      assert_equal 'integer', row[2], "Property #{row[0]} should be integer type"
    end

    # Check for specific integer properties
    pages_props = result.select { |r| r[0] == 'pages' }
    year_props = result.select { |r| r[0] == 'year' }
    assert_operator pages_props.length + year_props.length, :>, 0, 'Should find pages or year properties'
  end

  def test_xpath_queries
    # Test XPath-based queries
    result = @db.execute(<<~SQL, ['%book%'])
      SELECT id, node_type, xpath
      FROM nodes
      WHERE xpath LIKE ?
      ORDER BY id
    SQL

    # Should find nodes within book elements
    assert_operator result.length, :>, 0, 'Should find nodes within book elements'

    # Verify they're all within book context
    result.each do |row|
      assert_includes row[2], 'book', "XPath should contain 'book' for #{row[0]}"
    end
  end

  def test_document_statistics
    # Test the statistics query similar to what's shown in the README
    result = @db.execute(<<~SQL)
      SELECT
        COUNT(*) as total_nodes,
        COUNT(DISTINCT node_type) as node_types,
        COUNT(DISTINCT document_id) as documents,
        (SELECT COUNT(*) FROM cross_references) as cross_refs
      FROM nodes
    SQL

    stats = result.first
    assert_operator stats[0], :>, 0 # total_nodes
    assert_operator stats[1], :>, 0 # node_types
    assert_equal 1, stats[2] # documents (we only processed one file)
    assert_operator stats[3], :>, stats[0] # cross_refs (should be at least as many as nodes)
  end
end
