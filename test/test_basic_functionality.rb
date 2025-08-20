# frozen_string_literal: true

require_relative 'test_helper'

class TestBasicFunctionality < Minitest::Test
  def test_database_schema_creation
    # Create a simple XML file
    xml_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <root id="test_root">
        <child id="test_child">Content</child>
      </root>
    XML

    xml_file = create_xml_fixture(xml_content)
    input_dir = File.dirname(xml_file)

    # Run converter
    db = run_converter(input_dir)

    # Test that all required tables exist
    assert_table_exists(db, 'documents')
    assert_table_exists(db, 'nodes')
    assert_table_exists(db, 'node_properties')
    assert_table_exists(db, 'cross_references')
    assert_table_exists(db, 'schema_migrations')

    # Test that all required tables exist (FTS removed)
    # No FTS table should be created by default
  end

  def test_documents_table_structure
    xml_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <root id="test_root">Content</root>
    XML

    xml_file = create_xml_fixture(xml_content)
    input_dir = File.dirname(xml_file)
    db = run_converter(input_dir)

    # Test documents table columns
    assert_column_exists(db, 'documents', 'id')
    assert_column_exists(db, 'documents', 'filename')
    assert_column_exists(db, 'documents', 'file_size')
    assert_column_exists(db, 'documents', 'parsed_at')

    # Test document was inserted
    documents = db.execute('SELECT * FROM documents')
    assert_equal 1, documents.length
    assert_equal 'test', documents.first[0] # id (filename without .xml)
    assert_equal xml_file, documents.first[1] # filename
    assert_equal File.size(xml_file), documents.first[3] # file_size
  end

  def test_nodes_table_structure
    xml_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <root id="test_root">
        <child id="test_child" attr="value">Content</child>
      </root>
    XML

    xml_file = create_xml_fixture(xml_content)
    input_dir = File.dirname(xml_file)
    db = run_converter(input_dir)

    # Test nodes table columns
    assert_column_exists(db, 'nodes', 'id')
    assert_column_exists(db, 'nodes', 'node_type')
    assert_column_exists(db, 'nodes', 'document_id')
    assert_column_exists(db, 'nodes', 'parent_id')
    assert_column_exists(db, 'nodes', 'position')
    assert_column_exists(db, 'nodes', 'content')
    assert_column_exists(db, 'nodes', 'xpath')
    assert_column_exists(db, 'nodes', 'created_at')

    # Test nodes were inserted
    nodes = db.execute('SELECT * FROM nodes ORDER BY id')
    assert_equal 2, nodes.length

    root_node = nodes.find { |n| n[0] == 'test_root' }
    child_node = nodes.find { |n| n[0] == 'test_child' }

    assert_equal 'root', root_node[1] # node_type
    assert_equal 'test', root_node[2] # document_id
    assert_nil root_node[3] # parent_id (root has no parent)
    assert_equal 0, root_node[4] # position

    assert_equal 'child', child_node[1] # node_type
    assert_equal 'test', child_node[2] # document_id
    assert_equal 'test_root', child_node[3] # parent_id
    assert_equal 0, child_node[4] # position
  end

  def test_node_properties_table_structure
    xml_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <root id="test_root">
        <child id="test_child" count="5" active="true" price="24.99">Content</child>
      </root>
    XML

    xml_file = create_xml_fixture(xml_content)
    input_dir = File.dirname(xml_file)
    db = run_converter(input_dir)

    # Test node_properties table columns
    assert_column_exists(db, 'node_properties', 'node_id')
    assert_column_exists(db, 'node_properties', 'property_name')
    assert_column_exists(db, 'node_properties', 'property_value')
    assert_column_exists(db, 'node_properties', 'data_type')

    # Test properties were inserted with correct data types
    properties = db.execute('SELECT * FROM node_properties WHERE node_id = ? ORDER BY property_name', ['test_child'])
    assert_equal 3, properties.length

    count_prop = properties.find { |p| p[1] == 'count' }
    active_prop = properties.find { |p| p[1] == 'active' }
    price_prop = properties.find { |p| p[1] == 'price' }

    assert_equal 'integer', count_prop[3] # data_type
    assert_equal 'boolean', active_prop[3] # data_type
    assert_equal 'float', price_prop[3] # data_type
  end

  def test_xpath_preservation
    xml_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <root id="test_root">
        <section id="section_1">
          <item id="item_1">Content</item>
        </section>
      </root>
    XML

    xml_file = create_xml_fixture(xml_content)
    input_dir = File.dirname(xml_file)
    db = run_converter(input_dir)

    # Test XPath expressions are preserved
    xpaths = db.execute('SELECT id, xpath FROM nodes ORDER BY id')

    item_xpath = xpaths.find { |x| x[0] == 'item_1' }
    assert_includes item_xpath[1], '/root/section/item'
  end

  def test_batch_processing
    # Create multiple XML files
    xml_files = []
    5.times do |i|
      xml_content = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <root id="root_#{i}">
          <item id="item_#{i}">Content #{i}</item>
        </root>
      XML
      xml_files << create_xml_fixture(xml_content, "test_#{i}.xml")
    end

    input_dir = @temp_dir
    db = run_converter(input_dir, batch_size: 2)

    # Test all documents were processed
    documents = db.execute('SELECT COUNT(*) FROM documents')
    assert_equal 5, documents.first[0]

    # Test all nodes were processed
    nodes = db.execute('SELECT COUNT(*) FROM nodes')
    assert_equal 10, nodes.first[0] # 5 roots + 5 items
  end

  # FTS functionality removed - no longer testing full-text search

  def test_data_type_inference
    xml_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <root id="test_root">
        <item id="item_1"
              count="42"
              price="19.99"
              active="true"
              date="2023-01-15"
              time="14:30:00"
              empty=""
              text="hello world">Content</item>
      </root>
    XML

    xml_file = create_xml_fixture(xml_content)
    input_dir = File.dirname(xml_file)
    db = run_converter(input_dir)

    properties = db.execute(
      'SELECT property_name, data_type FROM node_properties WHERE node_id = ? ORDER BY property_name', ['item_1']
    )

    expected_types = {
      'count' => 'integer',
      'price' => 'float',
      'active' => 'boolean',
      'date' => 'datetime',
      'time' => 'datetime',
      'empty' => 'string',
      'text' => 'string'
    }

    properties.each do |prop|
      assert_equal expected_types[prop[0]], prop[1], "Property #{prop[0]} should be #{expected_types[prop[0]]}"
    end
  end
end
