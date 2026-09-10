require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  # The dependencies are noisy under -w; their warnings drown out our own.
  t.warning = false
end

task default: :test

namespace :languages do
  desc "Re-fetch every provider's language lists from its vendor"
  task :refresh do
    require "translation_diff"

    not_shipped = TranslationDiff::Languages::NOT_SHIPPED
    unless not_shipped.empty?
      puts "not shipping data for #{not_shipped.join(', ')}: a vendor credential or a private instance " \
           "would make the file unshareable"
    end

    skip = [:null, *not_shipped]
    providers = TranslationDiff::Providers.names.reject { |name| skip.include?(name) }.map do |name|
      TranslationDiff::Providers.build(name, TranslationDiff.config)
    rescue TranslationDiff::ConfigurationError => e
      warn "skipping #{name}: #{e.message}"
      nil
    end.compact

    report = TranslationDiff::Languages::Refresh.call(providers: providers)
    puts "updated: #{report[:updated].join(', ')}" unless report[:updated].empty?
    puts "skipped: #{report[:skipped].join(', ')}" unless report[:skipped].empty?
    report[:failed].each { |name, message| warn "failed: #{name}: #{message}" }
  end
end

namespace :translation_diff do
  desc "Delete expired rows from the SQL cache and rate-limit tables"
  task :prune do
    require "translation_diff"

    cache_store = TranslationDiff.config.cache_store
    if cache_store.respond_to?(:prune)
      puts "pruned #{cache_store.prune} expired cache rows"
    else
      puts "the configured cache store (#{cache_store.class}) does not support pruning"
    end

    rate_limiter = TranslationDiff.config.rate_limiter_instance
    if rate_limiter.respond_to?(:prune)
      puts "pruned #{rate_limiter.prune} expired rate-limit rows"
    else
      puts "the configured rate limiter (#{rate_limiter.class}) does not support pruning"
    end
  end
end
