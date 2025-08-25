# frozen_string_literal: true

require_relative 'test_helper'

class TestRelationshipDetection < Minitest::Test
  def test_structural_relationships
    xml_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <root id="root_node">
        <parent id="parent_1">
          <child id="child_1">Content 1</child>
          <child id="child_2">Content 2</child>
          <child id="child_3">Content 3</child>
        </parent>
        <parent id="parent_2">
          <child id="child_4">Content 4</child>
        </parent>
      </root>
    XML

    xml_file = create_xml_fixture(xml_content)
    input_dir = File.dirname(xml_file)
    db = run_converter(input_dir)

    # Test parent-child relationships
    parent_child_rels = db.execute(
      "SELECT source_node_id, target_node_id FROM cross_references
       WHERE reference_type = 'parent_child' ORDER BY source_node_id, target_node_id"
    )

    expected_parent_child = [
      %w[parent_1 child_1],
      %w[parent_1 child_2],
      %w[parent_1 child_3],
      %w[parent_2 child_4],
      %w[root_node parent_1],
      %w[root_node parent_2]
    ]

    assert_equal expected_parent_child, parent_child_rels

    # Test sibling relationships
    sibling_rels = db.execute(
      "SELECT source_node_id, target_node_id FROM cross_references
       WHERE reference_type = 'sibling' ORDER BY source_node_id, target_node_id"
    )

    # Siblings should be bidirectional
    assert_includes sibling_rels, %w[child_1 child_2]
    assert_includes sibling_rels, %w[child_2 child_1]
    assert_includes sibling_rels, %w[parent_1 parent_2]
    assert_includes sibling_rels, %w[parent_2 parent_1]

    # Test adjacent sibling relationships
    next_sibling_rels = db.execute(
      "SELECT source_node_id, target_node_id FROM cross_references
       WHERE reference_type = 'next_sibling' ORDER BY source_node_id, target_node_id"
    )

    assert_includes next_sibling_rels, %w[child_1 child_2]
    assert_includes next_sibling_rels, %w[child_2 child_3]
    assert_includes next_sibling_rels, %w[parent_1 parent_2]
  end

  def test_attribute_reference_relationships
    xml_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <library id="main_library">
        <author id="author_1" name="John Doe"/>
        <category id="cat_fiction" name="Fiction"/>
        <book id="book_1" author_id="author_1" category="cat_fiction" isbn="123456789">
          <title>Test Book</title>
        </book>
        <review id="review_1" book_ref="book_1" reviewer="author_1">
          <rating>5</rating>
        </review>
      </library>
    XML

    xml_file = create_xml_fixture(xml_content)
    input_dir = File.dirname(xml_file)
    db = run_converter(input_dir)

    # Test attribute reference relationships
    attr_refs = db.execute(
      "SELECT source_node_id, target_node_id, attribute_name FROM cross_references
       WHERE reference_type = 'attribute_reference' ORDER BY source_node_id"
    )

    # Should detect book -> author and book -> category references
    expected_refs = [
      %w[book_1 author_1 author_id],
      %w[book_1 cat_fiction category],
      %w[review_1 author_1 reviewer],
      %w[review_1 book_1 book_ref]
    ]

    expected_refs.each do |expected_ref|
      assert_includes attr_refs, expected_ref, "Missing reference: #{expected_ref}"
    end
  end

  def test_hierarchical_queries_with_recursive_cte
    # Test that hierarchical queries can be done with recursive CTEs (see examples/sql_queries.md)
    xml_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <root id="root_node">
        <level1 id="level1_node">
          <level2 id="level2_node">
            <level3 id="level3_node">
              <level4 id="level4_node">Deepest</level4>
            </level3>
          </level2>
        </level1>
      </root>
    XML

    xml_file = create_xml_fixture(xml_content)
    input_dir = File.dirname(xml_file)
    db = run_converter(input_dir)

    # Test recursive CTE for finding ancestors (example from sql_queries.md)
    ancestors = db.execute(
      "WITH RECURSIVE ancestors(descendant_id, ancestor_id, depth) AS (
         SELECT target_node_id, source_node_id, 1
         FROM cross_references
         WHERE target_node_id = 'level4_node' AND reference_type = 'parent_child'
         UNION ALL
         SELECT a.descendant_id, cr.source_node_id, a.depth + 1
         FROM ancestors a
         JOIN cross_references cr ON a.ancestor_id = cr.target_node_id
         WHERE cr.reference_type = 'parent_child' AND a.depth < 10
       )
       SELECT ancestor_id, depth FROM ancestors ORDER BY depth"
    )

    # Should find all ancestors of level4_node
    expected_ancestors = [
      ['level3_node', 1],
      ['level2_node', 2],
      ['level1_node', 3],
      ['root_node', 4]
    ]

    assert_equal expected_ancestors, ancestors, 'Recursive CTE should find all ancestors'
  end

  def test_core_adapters_only
    xml_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <root id="root_node">
        <book id="book_1" type="fiction">
          <title>Science Fiction Novel</title>
        </book>
        <book id="book_2" type="fiction">
          <title>Another Fiction Book</title>
        </book>
        <magazine id="mag_1" type="fiction">
          <title>Fiction Monthly</title>
        </magazine>
      </root>
    XML

    xml_file = create_xml_fixture(xml_content)
    input_dir = File.dirname(xml_file)
    db = run_converter(input_dir)

    # Test that only core relationship types are detected
    relationship_types = db.execute(
      'SELECT DISTINCT reference_type FROM cross_references ORDER BY reference_type'
    ).flatten

    # Should only have direct structural relationship types (no ancestor detection)
    core_types = %w[child_parent next_sibling parent_child previous_sibling sibling]

    relationship_types.each do |type|
      assert_includes core_types, type, "#{type} should be a core relationship type"
    end

    # Should not have semantic or ancestor relationship types
    excluded_types = %w[same_type content_similar ancestor_descendant descendant_ancestor]
    excluded_types.each do |type|
      refute_includes relationship_types, type, "#{type} should not be detected by core adapters"
    end
  end

  def test_relationship_confidence_scoring
    xml_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <library id="main_library">
        <author id="author_1"/>
        <book id="book_1" author_id="author_1" creator="author_1" writer="author_1"/>
      </library>
    XML

    xml_file = create_xml_fixture(xml_content)
    input_dir = File.dirname(xml_file)
    db = run_converter(input_dir)

    # Check confidence scores for different attribute reference types
    attr_refs = db.execute(
      "SELECT attribute_name, confidence FROM cross_references
       WHERE reference_type = 'attribute_reference' AND source_node_id = 'book_1'
       ORDER BY confidence DESC"
    )

    # author_id should have highest confidence (contains 'id')
    # Other attributes should have lower confidence
    author_id_ref = attr_refs.find { |ref| ref[0] == 'author_id' }
    other_refs = attr_refs.select { |ref| ref[0] != 'author_id' }

    assert author_id_ref[1] > 0.8, 'author_id reference should have high confidence'
    other_refs.each do |ref|
      assert ref[1] < author_id_ref[1], "#{ref[0]} should have lower confidence than author_id"
    end
  end

  def test_single_reference_values_only
    xml_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <library id="main_library">
        <author id="author_1"/>
        <category id="cat_1"/>
        <book id="book_1" author_id="author_1" category="cat_1" authors="author_1,author_2" tags="cat_1 author_1"/>
      </library>
    XML

    xml_file = create_xml_fixture(xml_content)
    input_dir = File.dirname(xml_file)
    db = run_converter(input_dir)

    # Test that only single references are detected, not multi-value attributes
    single_refs = db.execute(
      "SELECT target_node_id, attribute_name FROM cross_references
       WHERE reference_type = 'attribute_reference' AND source_node_id = 'book_1'
       ORDER BY target_node_id"
    )

    # Should only detect single ID references (author_id and category), not multi-value ones (authors, tags)
    expected_refs = [
      %w[author_1 author_id],
      %w[cat_1 category]
    ]

    assert_equal expected_refs, single_refs, 'Should only detect single, direct ID references'

    # Verify multi-value attributes are not processed
    multi_value_refs = single_refs.select { |ref| %w[authors tags].include?(ref[1]) }
    assert_empty multi_value_refs, 'Multi-value attributes should not be processed by core adapter'
  end

  def test_relationship_detection_disabled
    xml_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <root id="root_node">
        <child id="child_1">Content</child>
      </root>
    XML

    xml_file = create_xml_fixture(xml_content)
    input_dir = File.dirname(xml_file)

    # Run converter with relationships disabled
    db = run_converter(input_dir, detect_relationships: false)

    # Should have no relationships detected
    relationships = db.execute('SELECT COUNT(*) FROM cross_references').first[0]
    assert_equal 0, relationships
  end

  def test_complex_document_relationships
    # Use the sample library fixture which has complex relationships
    input_dir = File.join(File.dirname(__FILE__), 'fixtures')
    db = run_converter(input_dir)

    # Test that relationships were detected in the complex document
    total_relationships = db.execute('SELECT COUNT(*) FROM cross_references').first[0]
    assert total_relationships > 20, 'Should detect many relationships in complex document'

    # Test specific relationships from the sample
    book_category_refs = db.execute(
      "SELECT COUNT(*) FROM cross_references
       WHERE source_node_id LIKE 'book_%'
       AND attribute_name = 'category'
       AND reference_type = 'attribute_reference'"
    ).first[0]

    assert book_category_refs >= 3, 'Should detect book->category references'

    # Test review->book relationships
    review_book_refs = db.execute(
      "SELECT COUNT(*) FROM cross_references
       WHERE source_node_id LIKE 'review_%'
       AND attribute_name = 'book_id'
       AND reference_type = 'attribute_reference'"
    ).first[0]

    assert review_book_refs >= 3, 'Should detect review->book references'
  end

  def test_multi_reference_custom_adapter
    # Test using the MultiReferenceAdapter example for multi-value attributes
    xml_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <library id="main_library">
        <author id="author_1"/>
        <author id="author_2"/>
        <category id="cat_1"/>
        <book id="book_1" author_id="author_1" authors="author_1,author_2" tags="cat_1 author_1"/>
      </library>
    XML

    xml_file = create_xml_fixture(xml_content)
    input_dir = File.dirname(xml_file)

    # Create converter but don't run it yet
    converter = XMLToSQLite.new(input_dir: input_dir, output_db: test_db_path)
    converter.send(:setup_database)

    # Load the MultiReferenceAdapter example
    require_relative '../examples/relationship_adapters/multi_reference_adapter'

    # Process the document first
    converter.send(:process_xml_file, xml_file)

    # Add multi-reference adapter and detect relationships
    detector = converter.instance_variable_get(:@relationship_detector)
    detector.add_custom_adapter(MultiReferenceAdapter.new)
    converter.send(:detect_relationships)

    db = converter.instance_variable_get(:@db)

    # Should find both core single references and multi-references
    single_refs = db.execute(
      "SELECT target_node_id, attribute_name FROM cross_references
       WHERE reference_type = 'attribute_reference' AND source_node_id = 'book_1'"
    )

    multi_refs = db.execute(
      "SELECT target_node_id, attribute_name FROM cross_references
       WHERE reference_type = 'multi_attribute_reference' AND source_node_id = 'book_1'"
    )

    # Core adapter should detect single reference
    assert_includes single_refs, %w[author_1 author_id]

    # Multi-reference adapter should detect the multi-value ones
    assert_includes multi_refs, %w[author_1 authors]
    assert_includes multi_refs, %w[author_2 authors]
    assert_includes multi_refs, %w[cat_1 tags]
  end

  def test_custom_adapter_interface
    # Test that custom adapters can be added with the basic interface
    xml_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <root id="root_node">
        <item id="item_1" special_ref="item_2"/>
        <item id="item_2"/>
      </root>
    XML

    xml_file = create_xml_fixture(xml_content)
    input_dir = File.dirname(xml_file)

    # Create converter but don't run it yet
    converter = XMLToSQLite.new(input_dir: input_dir, output_db: test_db_path)
    converter.send(:setup_database)

    # Create a simple custom adapter
    custom_adapter = Class.new(RelationshipAdapter) do
      def detect_relationships(document_id, db)
        relationships = []
        # Find all special_ref attributes
        special_refs = db.execute(
          'SELECT np.node_id, np.property_value
           FROM node_properties np
           JOIN nodes n ON np.node_id = n.id
           WHERE n.document_id = ? AND np.property_name = ?',
          [document_id, 'special_ref']
        )

        special_refs.each do |ref|
          relationships << create_relationship(
            ref[0], ref[1], 'custom_reference', 0.9, 'special_ref'
          )
        end

        relationships
      end
    end

    # Process the document first
    converter.send(:process_xml_file, xml_file)

    # Add custom adapter and detect relationships
    detector = converter.instance_variable_get(:@relationship_detector)
    detector.add_custom_adapter(custom_adapter.new)
    converter.send(:detect_relationships)

    db = converter.instance_variable_get(:@db)

    # Should find the custom relationship
    custom_rels = db.execute(
      "SELECT source_node_id, target_node_id FROM cross_references
       WHERE reference_type = 'custom_reference'"
    )

    assert_equal [%w[item_1 item_2]], custom_rels
  end
end
