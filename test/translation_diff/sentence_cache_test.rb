require "test_helper"

class SentenceCacheTest < Minitest::Test
  # Records what it is asked for, so a test can assert on keys as well as
  # values. Minitest 6 has no mocking library; this is the whole contract.
  class RecordingStore
    attr_reader :reads, :writes

    def initialize(values = {})
      @values = values
      @reads = []
      @writes = {}
    end

    def read_multi(keys)
      @reads.concat(keys)
      keys.map { |k| @values[k] }
    end

    def write(key, value) = @writes[key] = value
  end

  def cache(store, **)
    TranslationDiff::SentenceCache.new(
      store: store, provider: "deepl", from: "en", to: "ru", **
    )
  end

  def segments(*sources) = sources.map { |s| TranslationDiff::Segment.new(s) }

  def test_a_hit_fills_the_segment_and_is_not_returned_as_a_miss
    subject = segments("One.")
    store = RecordingStore.new
    key = cache(store).key(subject.first)
    store = RecordingStore.new(key => "Один.")

    misses = cache(store).fill(subject)

    assert_equal "Один.", subject.first.translation
    assert_empty misses
  end

  def test_a_miss_is_returned_and_left_untranslated
    subject = segments("One.")

    misses = cache(RecordingStore.new).fill(subject)

    assert_equal subject, misses
    refute_predicate subject.first, :translated?
  end

  def test_store_writes_only_the_translated_ones
    subject = segments("One.", "Two.")
    subject.first.translation = "Один."
    store = RecordingStore.new
    subject_cache = cache(store)

    subject_cache.store(subject)

    assert_equal ["Один."], store.writes.values
  end

  # The bug this replaces: the old cache consumed the array of updates it was
  # handed, emptying a collection that belonged to its caller.
  def test_neither_operation_modifies_the_collection_it_is_given
    subject = segments("One.", "Two.")
    original = subject.dup

    subject_cache = cache(RecordingStore.new)
    subject_cache.fill(subject)
    subject_cache.store(subject)

    assert_equal original, subject
    assert_equal 2, subject.size
  end

  def test_the_same_sentence_in_two_languages_gets_two_keys
    segment = segments("One.").first
    en_ru = cache(RecordingStore.new).key(segment)
    en_de = TranslationDiff::SentenceCache.new(
      store: RecordingStore.new, provider: "deepl", from: "en", to: "de"
    ).key(segment)

    refute_equal en_ru, en_de
  end

  def test_two_providers_do_not_share_a_key
    segment = segments("One.").first
    deepl = cache(RecordingStore.new).key(segment)
    google = TranslationDiff::SentenceCache.new(
      store: RecordingStore.new, provider: "google", from: "en", to: "ru"
    ).key(segment)

    refute_equal deepl, google
  end

  def test_per_call_options_are_part_of_the_key
    segment = segments("One.").first
    plain = cache(RecordingStore.new).key(segment)
    formal = cache(RecordingStore.new, options: { formality: :more }).key(segment)

    refute_equal plain, formal
  end

  # The promise that a released cache keeps working. These values come from
  # the baseline Task 1 recorded against the pipeline being replaced.
  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
  def test_keys_match_the_ones_the_previous_pipeline_produced
    subject_cache = TranslationDiff::SentenceCache.new(
      store: RecordingStore.new, provider: "null", from: "en", to: "ru"
    )

    assert_equal "null:en:ru:9d6a2963872077db674a27a39c492e61",
                 subject_cache.key(segments("Hello there.").first)
    assert_equal "null:en:ru:1520f71fffb5adf0da75e7c17059bfd1",
                 subject_cache.key(segments("Second sentence!").first)
    assert_equal "null:en:ru:900019fa233e608091ba641d50d69b81",
                 subject_cache.key(segments("One.").first)
    assert_equal "null:en:ru:fdb02803abc46fba06ce1cc96d6399c5",
                 subject_cache.key(segments("Two.").first)
    assert_equal "null:en:ru:3f77101fc43570a61d5bc042bb908651",
                 subject_cache.key(segments("Third.").first)
    assert_equal "null:en:ru:fe3bf43723a64fb32bcac8d99bb431af",
                 subject_cache.key(segments("  Padded sentence.  ").first)
    assert_equal "null:en:ru:05d12994070fdde458e566149f42472f",
                 subject_cache.key(segments("Salt &amp; pepper.").first)
    assert_equal "null:en:ru:b5010567e209726a125c9ed59162eca5",
                 subject_cache.key(segments("Fine.").first)
  end
end
