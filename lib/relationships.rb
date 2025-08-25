# frozen_string_literal: true

# Main entry point for the relationships module
# This file provides access to the relationship framework
# Core and custom adapters must be explicitly registered

require_relative 'relationships/adapter'
require_relative 'relationships/manager'
require_relative 'relationships/detector'
require_relative 'relationships/adapters/structural_adapter'
require_relative 'relationships/adapters/attribute_reference_adapter'
