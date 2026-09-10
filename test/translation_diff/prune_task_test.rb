require "test_helper"
require "rake"

class PruneTaskTest < Minitest::Test
  class PruneableDouble
    def initialize(count) = @count = count
    def prune = @count
  end

  def setup
    TranslationDiff.reset!
    Rake.application = Rake::Application.new
    load File.expand_path("../../Rakefile", __dir__)
  end

  def teardown = TranslationDiff.reset!

  def test_prunes_the_cache_store_and_the_rate_limiter_separately
    TranslationDiff.configure do |c|
      c.cache = PruneableDouble.new(3)
      c.rate_limiter = PruneableDouble.new(5)
    end

    out, = capture_io { Rake::Task["translation_diff:prune"].invoke }

    assert_includes out, "pruned 3 expired cache rows"
    assert_includes out, "pruned 5 expired rate-limit rows"
  end

  def test_reports_when_the_cache_store_does_not_support_pruning
    TranslationDiff.configure { |c| c.cache = :memory }

    out, = capture_io { Rake::Task["translation_diff:prune"].invoke }

    assert_includes out, "the configured cache store (TranslationDiff::MemoryCacheStore) does not support pruning"
  end

  def test_reports_when_there_is_no_rate_limiter_configured
    TranslationDiff.configure { |c| c.cache = :memory }

    out, = capture_io { Rake::Task["translation_diff:prune"].invoke }

    assert_includes out, "the configured rate limiter (NilClass) does not support pruning"
  end
end
