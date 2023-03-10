# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "deepl_diff/version"

# rubocop:disable Metrics/BlockLength
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

  if spec.respond_to?(:metadata)
    spec.metadata["allowed_push_host"] = "https://rubygems.org"
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

  spec.add_development_dependency "bundler", "~> 1.14"
  spec.add_development_dependency "codeclimate-test-reporter", "~> 1.0.0"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop"
  spec.add_development_dependency "simplecov"

  spec.add_dependency "connection_pool"
  spec.add_dependency "deepl-rb"
  spec.add_dependency "dry-initializer"
  spec.add_dependency "ox"
  spec.add_dependency "punkt-segmenter"
  spec.add_dependency "ratelimit"
  spec.add_dependency "redis"
  spec.add_dependency "redis-namespace"
end
# rubocop:enable Metrics/BlockLength
