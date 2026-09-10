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

  # Same recording behaviour as RecordingStore, plus write_multi, to prove the batched path is taken when offered.
  class BatchingStore < RecordingStore
    attr_reader :write_multi_calls

    def initialize(values = {})
      super
      @write_multi_calls = []
    end

    def write_multi(pairs)
      @write_multi_calls << pairs
      pairs.each { |key, value| @writes[key] = value }
    end
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

  def test_store_batches_every_translated_segment_into_one_write_multi_call
    subject = segments("One.", "Two.")
    subject.zip(%w[Один. Два.]).each { |segment, translation| segment.translation = translation }
    store = BatchingStore.new
    subject_cache = cache(store)

    subject_cache.store(subject)

    expected = subject.map { |segment| [subject_cache.key(segment), segment.translation] }
    assert_equal 1, store.write_multi_calls.size
    assert_equal expected, store.write_multi_calls.first
  end

  # A batch of nothing is not a batch: a store that opens a transaction in write_multi must not be asked to.
  def test_store_never_calls_a_batching_store_when_nothing_was_translated
    store = BatchingStore.new

    cache(store).store(segments("One."))

    assert_empty store.write_multi_calls
  end

  # The compatibility guarantee: a custom store written against today's write-only contract keeps working untouched.
  def test_store_falls_back_to_write_per_key_when_the_store_has_no_write_multi
    subject = segments("One.", "Two.")
    subject.first.translation = "Один."
    subject.last.translation = "Два."
    store = RecordingStore.new
    refute_respond_to store, :write_multi
    subject_cache = cache(store)

    subject_cache.store(subject)

    assert_equal({ subject_cache.key(subject.first) => "Один.", subject_cache.key(subject.last) => "Два." },
                 store.writes)
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

  # Four fields without options, five with: the options digest is its own field, not folded into the sentence.
  def test_the_options_digest_is_a_field_of_its_own
    segment = segments("One.").first

    assert_equal 4, cache(RecordingStore.new).key(segment).split(":").size
    assert_equal 5, cache(RecordingStore.new, options: { formality: :more }).key(segment).split(":").size
  end

  # Recovered from the pipeline being replaced by running it against a recording store: one option, two
  # options, and two whose sort order is not their literal order, which is the pair that proves the sort.
  def test_the_options_digest_matches_the_keys_the_previous_pipeline_produced
    segment = segments("One.").first

    { { formality: :more } => "null:en:ru:c09f3c46:900019fa233e608091ba641d50d69b81",
      { formality: :more, glossary_id: "g1" } => "null:en:ru:c1ee2461:900019fa233e608091ba641d50d69b81",
      { b: 2, a: 1 } => "null:en:ru:9dc867b7:900019fa233e608091ba641d50d69b81" }.each do |options, expected|
      subject_cache = TranslationDiff::SentenceCache.new(
        store: RecordingStore.new, provider: "null", from: "en", to: "ru", options: options
      )

      assert_equal expected, subject_cache.key(segment)
    end
  end

  # Container values recurse: a Hash canonicalises the way the options hash itself does, an Array in order.
  # The first two were captured from the pipeline being replaced; the third goes a level deeper than either.
  def test_container_option_values_recurse_the_way_the_previous_pipeline_did
    segment = segments("One.").first

    { { glossary: { a: 1, b: 2 } } => "null:en:ru:4dbc310c:900019fa233e608091ba641d50d69b81",
      { tags: %w[x y] } => "null:en:ru:6b1bf7d6:900019fa233e608091ba641d50d69b81",
      { glossary: { a: [1, 2] } } => "null:en:ru:1948f701:900019fa233e608091ba641d50d69b81" }.each do |options, key|
      subject_cache = TranslationDiff::SentenceCache.new(
        store: RecordingStore.new, provider: "null", from: "en", to: "ru", options: options
      )

      assert_equal key, subject_cache.key(segment)
    end
  end

  # An allowlist, not a denylist: a tidy #inspect with no address in it is still one the old pipeline refused.
  def test_a_value_outside_the_permitted_types_raises_even_when_its_inspect_is_stable
    subject_cache = cache(RecordingStore.new, options: { glossary: Struct.new(:x).new(1) })

    error = assert_raises(TranslationDiff::SentenceCache::Error) { subject_cache.key(segments("One.").first) }

    assert_includes error.message, "glossary"
  end

  # A Symbol and a String are not comparable with each other, so sorting on the raw keys raises on this hash.
  def test_mixed_option_key_types_canonicalise_instead_of_raising
    segment = segments("One.").first
    symbol_first = cache(RecordingStore.new, options: { formality: :more, "glossary" => "g" })
    string_first = cache(RecordingStore.new, options: { "glossary" => "g", formality: :more })

    assert_equal symbol_first.key(segment), string_first.key(segment)
  end

  # A value rendering as an address gives a key that can never be hit twice, so it fails where a user can see it.
  def test_an_option_with_no_stable_string_form_raises_and_names_it
    subject_cache = cache(RecordingStore.new, options: { glossary: Object.new })

    error = assert_raises(TranslationDiff::SentenceCache::Error) { subject_cache.key(segments("One.").first) }

    assert_kind_of TranslationDiff::Error, error
    assert_includes error.message, "glossary"
  end

  # One definition of padding, the one Segment already makes: the key hashes the body it cut, not a copy of its regex.
  def test_the_key_hashes_the_body_segment_cut
    segment = segments("  Padded sentence.  ").first

    key = cache(RecordingStore.new).key(segment)

    assert_equal "Padded sentence.", segment.body
    assert_equal Digest::MD5.hexdigest(segment.body), key.split(":").last
  end
end
