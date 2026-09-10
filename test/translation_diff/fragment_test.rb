require "test_helper"

class FragmentTest < Minitest::Test
  # Rendering used to hand back the slice itself, so appending to it edited the document it came from.
  def test_rendering_markup_does_not_hand_out_the_fragment_source
    fragment = TranslationDiff::Fragment.markup("<b>")

    fragment.render << "XXX"

    assert_equal "<b>", fragment.render
  end
end
