#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'minitest'
end

require 'minitest/autorun'
require 'minitest/pride'
require 'fileutils'
require 'tempfile'
require 'pathname'

# Add the project root to the load path
$LOAD_PATH.unshift(File.expand_path('..', __dir__))

require_relative '../main'

class Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @test_db_path = File.join(@temp_dir, 'test.sqlite3')
  end

  def teardown
    FileUtils.remove_entry(@temp_dir) if Dir.exist?(@temp_dir)
  end

  def create_xml_fixture(content, filename = 'test.xml')
    file_path = File.join(@temp_dir, filename)
    File.write(file_path, content)
    file_path
  end

  def run_converter(input_dir, options = {})
    custom_adapters = options.delete(:custom_adapters) || []
    default_options = {
      input_dir: input_dir,
      output_db: @test_db_path,
      verbose: false,
      force: true,
      concurrency: 1  # Use concurrency = 1 for tests
    }

    converter = XMLToSQLite.new(default_options.merge(options))
    converter.send(:setup_database)
    custom_adapters.each { |adapter| converter.relationship_detector.add_adapter(adapter) }
    converter.send(:_run)
    db = SQLite3::Database.new(@test_db_path)
    db.execute('PRAGMA foreign_keys = ON')
    db
  end

  def assert_table_exists(db, table_name)
    result = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name=?", [table_name])
    assert_equal 1, result.length, "Table '#{table_name}' should exist"
  end

  def assert_column_exists(db, table_name, column_name)
    result = db.execute("PRAGMA table_info(#{table_name})")
    columns = result.map { |row| row[1] }
    assert_includes columns, column_name, "Column '#{column_name}' should exist in table '#{table_name}'"
  end

  attr_reader :test_db_path
end
