# frozen_string_literal: true

require 'nokogiri'

##
# Handles parsing of individual XML documents
# Pure computation - no database operations
class DocumentParser
  def parse_file(xml_file)
    document_id = File.basename(xml_file, '.xml')

    # Parse the XML document
    doc = Nokogiri::XML(File.open(xml_file), &:noblanks)

    # Extract document metadata
    document_info = {
      id: document_id,
      filename: xml_file,
      file_size: File.size(xml_file)
    }

    # Extract all nodes and properties for this document
    nodes = []
    properties = []

    doc.xpath('//*[@id]').each do |element|
      nodes << extract_node_data(element, document_id)
      properties.concat(extract_property_data(element))
    end

    {
      document: document_info,
      nodes: nodes,
      properties: properties,
      source_file: xml_file
    }
  end

  private

  def extract_node_data(element, document_id)
    {
      id: element['id'],
      node_type: element.name,
      document_id: document_id,
      parent_id: element.parent && element.parent['id'] ? element.parent['id'] : nil,
      position: get_position(element),
      content: element.text&.strip,
      xpath: element.path
    }
  end

  def extract_property_data(element)
    properties = []

    element.attributes.each do |name, attr|
      next if name == 'id'

      properties << {
        node_id: element['id'],
        property_name: name,
        property_value: attr.value,
        data_type: infer_type(attr.value)
      }
    end

    properties
  end

  def get_position(element)
    return 0 unless element.parent

    siblings = element.parent.children.select(&:element?)
    siblings.index(element) || 0
  end

  def infer_type(value)
    return 'string' if value.nil? || value.empty?

    case value
    when /^\d+$/
      'integer'
    when /^\d+\.\d+$/
      'float'
    when /^(true|false)$/i
      'boolean'
    when /^\d{4}-\d{2}-\d{2}/, /^\d{2}:\d{2}:\d{2}/
      'datetime'
    else
      'string'
    end
  end
end
