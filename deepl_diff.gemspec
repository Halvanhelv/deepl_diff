# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "deepl_diff/version"

# rubocop:disable-next Metrics/BlockLength
Gem::Specification.new do |spec|
  spec.name          = "deepl_diff"
  spec.version       = DeepLDiff::VERSION
  spec.authors       = ["Islam Gagiev"]
  spec.email         = ["omniacinis@gmail.com"]

  spec.summary       = %(
DeepL API wrapper for Ruby which helps to translate only changes
between revisions of long texts.

  )
  spec.description = %(
DeepL API wrapper for Ruby which helps to translate only changes
between revisions of long texts.
  )
  spec.homepage = "https://github.com/Halvanhelv/deepl_diff"
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

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "rubocop", "~> 1.90"
  spec.add_development_dependency "simplecov", "~> 1.2"

  spec.add_dependency "connection_pool", ">= 2.4", "< 4.0"
  spec.add_dependency "deepl-rb", "~> 3.9"
  spec.add_dependency "dry-initializer", "~> 3.2"
  spec.add_dependency "ox", "~> 2.14"
  spec.add_dependency "punkt-segmenter", "~> 0.9"
  spec.add_dependency "ratelimit", "~> 1.1"
  spec.add_dependency "redis", ">= 5.0", "< 7.0"
  spec.add_dependency "redis-namespace", "~> 1.11"
end
