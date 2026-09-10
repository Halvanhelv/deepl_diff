# Shipped in the gem so a host application's own `rake` sees it -- a dependency's Rakefile is never loaded.
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
