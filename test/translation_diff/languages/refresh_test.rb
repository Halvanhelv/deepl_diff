require "test_helper"
require "tmpdir"

class LanguagesRefreshTest < Minitest::Test
  class Answering < TranslationDiff::Provider
    def cache_key = "answering"
    def languages = { source: %w[en de], target: %w[en de fr] }
  end

  class Failing < TranslationDiff::Provider
    def cache_key = "failing"
    def languages = raise(TranslationDiff::TransportError, "nobody answered")
  end

  class Silent < TranslationDiff::Provider
    def cache_key = "silent"
  end

  class Empty < TranslationDiff::Provider
    def cache_key = "empty"
    def languages = { source: [], target: [] }
  end

  class Unwritable < TranslationDiff::Provider
    def cache_key = "unwritable"
    def languages = { source: %w[en], target: %w[en] }
  end

  # api_base and languages_endpoint deliberately differ, so a regression that reads the former is caught.
  class Detailed < TranslationDiff::Provider
    def cache_key = "detailed"
    def api_base = "https://api.detailed.test"
    def languages_endpoint = "https://api.detailed.test/v9/languages?scope=translation"
    def languages = { source: %w[en], target: %w[en] }
  end

  def test_a_provider_that_answers_is_written_with_todays_date
    Dir.mktmpdir do |dir|
      report = TranslationDiff::Languages::Refresh.call(
        providers: [Answering.new(config)], directory: dir, on: "2026-09-11"
      )

      document = JSON.parse(File.read(File.join(dir, "answering.json")))

      assert_equal %w[answering], report[:updated]
      assert_equal "2026-09-11", document["captured_at"]
      assert_equal %w[de en], document["source"]
      assert_equal %w[de en fr], document["target"]
    end
  end

  # A refresh that emptied a list because a network call timed out would be worse than never running.
  def test_a_provider_whose_fetch_fails_keeps_its_previous_file_and_is_reported
    Dir.mktmpdir do |dir|
      path = File.join(dir, "failing.json")
      File.write(path, JSON.generate({ "provider" => "failing", "source" => %w[en], "target" => %w[en] }))

      report = TranslationDiff::Languages::Refresh.call(providers: [Failing.new(config)], directory: dir)

      assert_equal %w[en], JSON.parse(File.read(path))["source"]
      assert_empty report[:updated]
      assert_match(/nobody answered/, report[:failed]["failing"])
    end
  end

  def test_a_provider_that_cannot_fetch_its_languages_is_skipped_not_failed
    Dir.mktmpdir do |dir|
      report = TranslationDiff::Languages::Refresh.call(providers: [Silent.new(config)], directory: dir)

      assert_equal %w[silent], report[:skipped]
      assert_empty report[:failed]
      refute_path_exists File.join(dir, "silent.json")
    end
  end

  # A vendor answering 200 with an empty body must not blank a shipped file with ~190 codes in it.
  def test_a_provider_whose_languages_come_back_empty_keeps_its_previous_file_and_is_reported
    Dir.mktmpdir do |dir|
      path = File.join(dir, "empty.json")
      File.write(path, JSON.generate({ "provider" => "empty", "source" => %w[en], "target" => %w[en] }))
      before = File.read(path)

      report = TranslationDiff::Languages::Refresh.call(providers: [Empty.new(config)], directory: dir)

      assert_equal before, File.read(path)
      assert_empty report[:updated]
      assert_match(/empty/i, report[:failed]["empty"])
    end
  end

  # One provider's unwritable file must not cost the other providers in the same run their refresh.
  def test_a_provider_whose_file_cannot_be_written_still_lets_the_rest_of_the_run_complete
    Dir.mktmpdir do |dir|
      Dir.mkdir(File.join(dir, "unwritable.json"))

      report = TranslationDiff::Languages::Refresh.call(
        providers: [Unwritable.new(config), Answering.new(config)], directory: dir
      )

      assert_equal %w[answering], report[:updated]
      assert report[:failed].key?("unwritable")
      assert_equal %w[de en], source_for(dir, "answering")
    end
  end

  # DeepL on a free-plan key writes api-free.deepl.com through #api_base; the shipped file documents the metadata
  # URL #languages itself fetches, which #languages_endpoint names precisely and #api_base alone cannot.
  def test_the_written_endpoint_is_the_providers_own_languages_endpoint_not_its_api_base
    Dir.mktmpdir do |dir|
      TranslationDiff::Languages::Refresh.call(providers: [Detailed.new(config)], directory: dir)

      document = JSON.parse(File.read(File.join(dir, "detailed.json")))

      assert_equal "https://api.detailed.test/v9/languages?scope=translation", document["endpoint"]
    end
  end

  private

  def config = TranslationDiff::Configuration.new

  def source_for(dir, name) = JSON.parse(File.read(File.join(dir, "#{name}.json")))["source"]
end
