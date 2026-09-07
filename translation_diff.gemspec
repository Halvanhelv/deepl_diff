# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "translation_diff/version"

# rubocop:disable-next Metrics/BlockLength
Gem::Specification.new do |spec|
  spec.name          = "translation_diff"
  spec.version       = TranslationDiff::VERSION
  spec.authors       = ["Islam Gagiev"]
  spec.email         = ["omniacinis@gmail.com"]

  spec.summary = "A translation cache that sends only new or changed sentences to your provider."
  spec.description = %(
TranslationDiff extracts translatable text from HTML, splits it into
sentences, and caches each sentence by content hash. Only the sentences
missing from the cache are sent to whichever translation provider you plug
in through a small adapter contract, so re-translating a long text after a
small edit costs the price of the edit, not the whole text.
  )
  spec.homepage = "https://github.com/Halvanhelv/translation_diff"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  if spec.respond_to?(:metadata)
    spec.metadata["allowed_push_host"] = "https://rubygems.org"
    spec.metadata["homepage_uri"] = spec.homepage
    spec.metadata["source_code_uri"] = spec.homepage
    spec.metadata["rubygems_mfa_required"] = "true"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
          "public gem pushes."
  end

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "minitest", "~> 6.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rubocop", "~> 1.90"
  spec.add_development_dependency "simplecov", "~> 1.2"

  # The only gem this one loads. Everything else -- the DeepL client, the
  # connection pool, and whatever backs the cache, the rate limiter, and the
  # segmenter -- is supplied by the application and duck typed, so it stays
  # out of the gemspec.
  spec.add_dependency "ox", "~> 2.14"
end
