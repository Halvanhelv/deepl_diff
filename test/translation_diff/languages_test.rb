require "test_helper"

class LanguagesTest < Minitest::Test
  def test_a_shipped_provider_answers_for_a_pair_it_supports
    assert TranslationDiff::Languages.supports?(:deepl, from: "en", to: "ru")
    assert TranslationDiff::Languages.supports?("google", from: "en", to: "ru")
  end

  def test_a_pair_the_provider_does_not_do_is_refused
    refute TranslationDiff::Languages.supports?(:deepl, from: "en", to: "klingon")
  end

  # Three states, not two: an unknown provider has no opinion, and no opinion never refuses.
  def test_an_unknown_provider_answers_nil
    assert_nil TranslationDiff::Languages.supports?(:amazon, from: "en", to: "ru")
    assert_nil TranslationDiff::Languages.supports?(:libretranslate, from: "en", to: "ru")
    assert_nil TranslationDiff::Languages.supports?(:whatever, from: "en", to: "ru")
    assert_nil TranslationDiff::Languages.for(:whatever)
  end

  # Matching is on the primary subtag in both directions: a bare entry takes a regional code and back.
  def test_a_regional_code_matches_a_bare_entry_and_the_other_way_round
    assert TranslationDiff::Languages.supports?(:deepl, from: "en-GB", to: "ru")
    assert TranslationDiff::Languages.supports?(:deepl, from: "en", to: "pt")
    assert TranslationDiff::Languages.supports?(:deepl, from: "EN", to: "PT-BR")
  end

  def test_source_and_target_are_kept_apart
    set = TranslationDiff::Languages.for(:deepl)

    assert_includes set.target, "en-gb"
    refute_includes set.source, "en-gb"
    assert_includes set.source, "en"
  end

  def test_a_set_records_when_and_where_it_was_captured
    set = TranslationDiff::Languages.for(:azure)

    assert_equal "2026-09-10", set.captured_at
    assert_includes set.endpoint, "microsofttranslator.com"
  end

  # A nil code cannot be validated, so it is not refused -- detection has not run yet.
  def test_a_missing_code_is_not_refused
    assert TranslationDiff::Languages.supports?(:deepl, from: nil, to: "ru")
  end

  # ModernMT ships ISO 639-3 individual codes where callers write the 639-1 macrolanguage code.
  def test_a_macrolanguage_code_matches_the_vendors_iso_639_3_individual_code
    assert TranslationDiff::Languages.supports?(:modernmt, from: "en", to: "fa")
    assert TranslationDiff::Languages.supports?(:modernmt, from: "fa", to: "en")
  end

  # The alias only runs macro -> individual: a vendor publishing only "zh" has not promised to accept "cmn".
  def test_the_macro_alias_does_not_run_backwards
    refute TranslationDiff::Languages.supports?(:deepl, from: "en", to: "cmn")
    assert TranslationDiff::Languages.supports?(:deepl, from: "en", to: "zh")
  end

  # The live leaks: none of these vendors publish the individual code, so none should accept it.
  def test_deepl_does_not_accept_individual_codes_it_never_published
    refute TranslationDiff::Languages.supports?(:deepl, from: "en", to: "pes")
    refute TranslationDiff::Languages.supports?(:deepl, from: "en", to: "swh")
  end

  # Derived from the directory, not hardcoded, so a maintainer who ships amazon.json needs no second place to say so.
  def test_shipped_is_derived_from_the_data_files_actually_present
    assert_equal %i[azure deepl google modernmt], TranslationDiff::Languages::SHIPPED
  end

  # Amazon needs AWS credentials most maintainers lack; LibreTranslate's list is one private instance's own.
  def test_not_shipped_names_amazon_and_libretranslate
    assert_equal %i[amazon libretranslate], TranslationDiff::Languages::NOT_SHIPPED
  end

  def test_every_shipped_file_parses_and_carries_both_lists
    TranslationDiff::Languages::SHIPPED.each do |name|
      set = TranslationDiff::Languages.for(name)

      refute_empty set.source, name.to_s
      refute_empty set.target, name.to_s
      assert_match(/\A\d{4}-\d{2}-\d{2}\z/, set.captured_at)
    end
  end
end
