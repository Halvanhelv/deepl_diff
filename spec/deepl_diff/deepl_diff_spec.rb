# frozen_string_literal: true

require "spec_helper"

RSpec.describe DeepLDiff do
  it "has a version number" do
    expect(DeepLDiff::VERSION).not_to be nil
  end
end
