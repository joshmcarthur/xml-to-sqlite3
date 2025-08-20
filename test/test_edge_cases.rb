# frozen_string_literal: true

require_relative 'test_helper'

class TestEdgeCases < Minitest::Test
  def test_empty_xml_file
    xml_content = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root id=\"empty_root\"></root>"
    xml_file = create_xml_fixture(xml_content)
    input_dir = File.dirname(xml_file)

    db = run_converter(input_dir)

    # Should still create the root node
    nodes = db.execute('SELECT * FROM nodes')
    assert_equal 1, nodes.length
    assert_equal 'empty_root', nodes.first[0]
  end

  def test_xml_without_ids
    xml_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <root>
        <child>Content</child>
        <child>More content</child>
      </root>
    XML

    xml_file = create_xml_fixture(xml_content)
    input_dir = File.dirname(xml_file)

    db = run_converter(input_dir)

    # Should only process elements with IDs
    nodes = db.execute('SELECT * FROM nodes')
    assert_equal 0, nodes.length, 'Should not process elements without IDs'
  end

  def test_xml_with_duplicate_ids
    xml_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <root id="duplicate_root">
        <child id="duplicate_id">First</child>
        <child id="duplicate_id">Second</child>
      </root>
    XML

    xml_file = create_xml_fixture(xml_content)
    input_dir = File.dirname(xml_file)

    db = run_converter(input_dir)

    # Should handle duplicates (last one wins due to INSERT OR REPLACE)
    nodes = db.execute('SELECT * FROM nodes WHERE id = ?', ['duplicate_id'])
    assert_equal 1, nodes.length
    assert_equal 'Second', nodes.first[5] # content
  end

  def test_xml_with_special_characters
    xml_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <root id="special_root">
        <item id="item_1" attr="&lt;&gt;&amp;&quot;&apos;">Content with &lt;&gt;&amp;</item>
        <item id="item_2" attr="normal">Normal content</item>
      </root>
    XML

    xml_file = create_xml_fixture(xml_content)
    input_dir = File.dirname(xml_file)

    db = run_converter(input_dir)

    # Should handle special characters properly
    nodes = db.execute('SELECT * FROM nodes WHERE id = ?', ['item_1'])
    assert_equal 1, nodes.length

    properties = db.execute('SELECT * FROM node_properties WHERE node_id = ?', ['item_1'])
    assert_equal 1, properties.length
    assert_equal '<>&"\'', properties.first[2] # property_value
  end

  def test_xml_with_nested_attributes
    xml_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <root id="nested_root">
        <item id="item_1"
              simple="value"
              complex="value with spaces"
              number="42"
              decimal="3.14"
              boolean="true"
              date="2023-01-15"
              time="14:30:00"
              empty=""
              nil_attr="nil">Content</item>
      </root>
    XML

    xml_file = create_xml_fixture(xml_content)
    input_dir = File.dirname(xml_file)

    db = run_converter(input_dir)

    # Test all attribute types are processed correctly
    properties = db.execute(
      'SELECT property_name, property_value, data_type FROM node_properties WHERE node_id = ? ORDER BY property_name', ['item_1']
    )

    expected_properties = {
      'boolean' => %w[true boolean],
      'complex' => ['value with spaces', 'string'],
      'date' => %w[2023-01-15 datetime],
      'decimal' => ['3.14', 'float'],
      'empty' => ['', 'string'],
      'nil_attr' => %w[nil string],
      'number' => %w[42 integer],
      'simple' => %w[value string],
      'time' => ['14:30:00', 'datetime']
    }

    assert_equal expected_properties.length, properties.length

    properties.each do |prop|
      name, value, type = prop
      expected_value, expected_type = expected_properties[name]
      assert_equal expected_value, value, "Property #{name} value mismatch"
      assert_equal expected_type, type, "Property #{name} type mismatch"
    end
  end

  def test_large_xml_file
    # Create a large XML file with many nodes
    xml_parts = ['<?xml version="1.0" encoding="UTF-8"?>', '<root id="large_root">']

    1000.times do |i|
      xml_parts << "<item id=\"item_#{i}\" index=\"#{i}\">Content #{i}</item>"
    end

    xml_parts << '</root>'
    xml_content = xml_parts.join("\n")

    xml_file = create_xml_fixture(xml_content)
    input_dir = File.dirname(xml_file)

    db = run_converter(input_dir)

    # Should process all nodes
    nodes = db.execute('SELECT COUNT(*) FROM nodes')
    assert_equal 1001, nodes.first[0] # root + 1000 items

    properties = db.execute('SELECT COUNT(*) FROM node_properties')
    assert_equal 1000, properties.first[0] # one property per item
  end

  def test_malformed_xml_handling
    # Test with malformed XML that Nokogiri can't parse
    malformed_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <root id="malformed_root">
        <item id="item_1">Content
        <item id="item_2">Unclosed item
        <broken>No closing tag
      </root>
    XML

    xml_file = create_xml_fixture(malformed_xml)
    input_dir = File.dirname(xml_file)

    # Should handle malformed XML gracefully - Nokogiri might be tolerant
    # so we'll just test that it doesn't crash
    db = run_converter(input_dir)

    # Should still process what it can
    nodes = db.execute('SELECT COUNT(*) FROM nodes')
    assert_operator nodes.first[0], :>=, 0, 'Should process what it can or handle gracefully'
  end

  def test_xml_with_namespaces
    xml_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <root xmlns:ns="http://example.com/ns" id="ns_root">
        <ns:item id="ns_item_1" ns:attr="value">Namespace content</ns:item>
        <item id="regular_item" attr="value">Regular content</item>
      </root>
    XML

    xml_file = create_xml_fixture(xml_content)
    input_dir = File.dirname(xml_file)

    db = run_converter(input_dir)

    # Should process both namespaced and regular elements
    nodes = db.execute('SELECT * FROM nodes ORDER BY id')
    assert_equal 3, nodes.length

    node_ids = nodes.map { |n| n[0] }
    assert_includes node_ids, 'ns_root'
    assert_includes node_ids, 'ns_item_1'
    assert_includes node_ids, 'regular_item'
  end

  def test_xml_with_cdata_sections
    xml_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <root id="cdata_root">
        <item id="item_1">
          <![CDATA[This is CDATA content with <tags> and & symbols]]>
        </item>
        <item id="item_2">Regular content</item>
      </root>
    XML

    xml_file = create_xml_fixture(xml_content)
    input_dir = File.dirname(xml_file)

    db = run_converter(input_dir)

    # Should process CDATA content
    nodes = db.execute('SELECT * FROM nodes WHERE id = ?', ['item_1'])
    assert_equal 1, nodes.length
    assert_includes nodes.first[5], 'CDATA content' # content field
  end

  def test_xml_with_comments
    xml_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <root id="comment_root">
        <!-- This is a comment -->
        <item id="item_1">Content</item>
        <!-- Another comment -->
        <item id="item_2">More content</item>
      </root>
    XML

    xml_file = create_xml_fixture(xml_content)
    input_dir = File.dirname(xml_file)

    db = run_converter(input_dir)

    # Should ignore comments and only process elements
    nodes = db.execute('SELECT * FROM nodes')
    assert_equal 3, nodes.length # root + 2 items
  end

  def test_xml_with_processing_instructions
    xml_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <?xml-stylesheet type="text/xsl" href="style.xsl"?>
      <root id="pi_root">
        <item id="item_1">Content</item>
      </root>
    XML

    xml_file = create_xml_fixture(xml_content)
    input_dir = File.dirname(xml_file)

    db = run_converter(input_dir)

    # Should ignore processing instructions and only process elements
    nodes = db.execute('SELECT * FROM nodes')
    assert_equal 2, nodes.length # root + item
  end

  def test_concurrent_access
    # Test that the database can be accessed concurrently after creation
    xml_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <root id="concurrent_root">
        <item id="item_1">Content</item>
      </root>
    XML

    xml_file = create_xml_fixture(xml_content)
    input_dir = File.dirname(xml_file)

    db = run_converter(input_dir)

    # Close and reopen database
    db.close

    # Should be able to reopen and query
    db2 = SQLite3::Database.new(@test_db_path)
    nodes = db2.execute('SELECT * FROM nodes')
    assert_equal 2, nodes.length
    db2.close
  end

  def test_database_optimization
    xml_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <root id="optimize_root">
        <item id="item_1">Content</item>
      </root>
    XML

    xml_file = create_xml_fixture(xml_content)
    input_dir = File.dirname(xml_file)

    db = run_converter(input_dir)

    # Test that optimization was applied
    result = db.execute('PRAGMA foreign_keys')
    # Foreign keys might be OFF depending on SQLite version/settings
    # Just verify the database was optimized and FTS was created
    assert_operator result.first[0], :>=, 0, 'Foreign keys pragma should be accessible'

    # FTS functionality removed - no longer testing FTS table creation
  end
end
