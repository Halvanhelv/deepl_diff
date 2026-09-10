# Loaded only when Rails already is (see the guarded require in translation_diff.rb), never on its own.
require "active_support/core_ext/module/delegation"
require "rails/railtie"

# Adds translation_diff:prune to a host Rails application's own rake tasks; the gem's dev Rakefile loads the
# same task file directly, so a host application's `rake -T` and this gem's own suite see one definition.
class TranslationDiff::Railtie < Rails::Railtie
  rake_tasks do
    load File.expand_path("tasks/translation_diff.rake", __dir__)
    Rake::Task["translation_diff:prune"].enhance(["environment"])
  end
end
