# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# Not a runtime dependency of the gem (see the gemspec) -- the DeepL
# provider requires it lazily at build time. It is only here so the test
# suite, which exercises that provider against the real deepl-rb objects,
# has it available.
gem "deepl-rb", "~> 3.9", require: false
