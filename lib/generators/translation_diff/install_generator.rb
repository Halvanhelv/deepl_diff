# Loaded only when Rails loads generators; nothing in lib/translation_diff.rb requires this file.
require "rails/generators"
require "rails/generators/active_record/migration"

# `rails generate translation_diff:install` -- writes the migration for both SQL-backed tables.
class TranslationDiff::InstallGenerator < Rails::Generators::Base
  include ActiveRecord::Generators::Migration

  source_root File.expand_path("templates", __dir__)

  def create_migration_file
    migration_template "create_translation_diff_tables.rb.erb", "db/migrate/create_translation_diff_tables.rb"
  end
end
