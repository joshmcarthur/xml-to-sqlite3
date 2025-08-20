# frozen_string_literal: true

class SchemaManager
  def initialize(db_path)
    @db = SQLite3::Database.new(db_path)
    @db.execute('PRAGMA foreign_keys = ON')
  end

  def migrate!
    starting_version = current_version

    Dir.glob(File.join(__dir__, 'db', 'migrate', '*.rb')).each do |file|
      require file
    end

    migrations = [
      CreateBaseSchema
    ]

    migrations.each_with_index do |migration, index|
      version = index + 1
      next if version <= starting_version

      puts "Running migration #{version}: #{migration.name}"
      migration.up(@db)
      record_migration(version)
    end
  end

  private

  def current_version
    @db.execute('CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY)')
    result = @db.execute('SELECT MAX(version) FROM schema_migrations').first
    result.first || 0
  end

  def record_migration(version)
    @db.execute('INSERT INTO schema_migrations (version) VALUES (?)', [version])
  end
end
