# Providers

A translation cache that helps translate only changes between revisions of
long texts. It ships with six providers -- DeepL, Google Cloud Translation,
Azure AI Translator, ModernMT, LibreTranslate and Amazon Translate -- but any
translation service can be plugged in by subclassing a small base class.

See the provider table in the [README](../README.md#providers).

Language pairs are checked against shipped vendor data before every call, and
a provider with no shipped data refuses nothing. Data ships for **DeepL,
Google, Azure and ModernMT**; **Amazon** and **LibreTranslate** ship none --
see [Languages](languages.md).

`Configuration#inspect` and `Provider#inspect` print `[FILTERED]` in place of
every credential option below -- `deepl_api_key`, `azure_api_key`,
`amazon_secret_access_key`, and so on -- so a Rails error page and a stray
`p config` in a console cannot leak one; `pp` and `p` both go through the
overridden `inspect`. That guarantee stops at `inspect`, though: an error
reporter that serialises object state instead of calling `inspect` is not
covered, and neither is `p provider.connection`, which prints Faraday's own
headers, `Authorization` included, untouched.

Options that carry no credential at all, like `azure_region` or
`cache_namespace`, stay visible in full. Any option whose value parses as a
URI carrying userinfo -- `redis_url` among them -- has just that userinfo
redacted: `rediss://default:AbCdEf-TOKEN@cache.example.upstash.io:6379`
prints as `rediss://default:[FILTERED]@cache.example.upstash.io:6379`. The
scheme, host, port and path stay visible, since that's what you need to
debug against -- only the credential Heroku, Upstash, Redis Cloud and Aiven
all put in the userinfo is hidden. A value that isn't a URI, or a URI with no
userinfo, is left unchanged, and a malformed value never raises out of
`inspect`.

## Configuring each provider

Every example below is complete: set the options shown and
`TranslationDiff.translate` works. The option names, and which of them are
required, come from the provider itself -- see [Configuration
options](configuration.md#configuration-options) for the full list and the environment
variables each one falls back to.

**DeepL** is the default, so `config.provider` may be omitted. A key ending
in `:fx` is a free-plan key and selects the free host on its own.

```ruby
TranslationDiff.configure do |config|
  config.provider = :deepl
  config.deepl_api_key = ENV["DEEPL_AUTH_KEY"]
end

TranslationDiff.translate("Hello there. Second sentence.", from: "en", to: "ru")
```

**Google Cloud Translation** needs an API key and nothing else -- no project,
no service account.

```ruby
TranslationDiff.configure do |config|
  config.provider = :google
  config.google_api_key = ENV["TRANSLATE_KEY"]
end
```

**Azure AI Translator** wants the region as well when the key belongs to a
multi-service Cognitive Services resource; a single-service Translator
resource needs no region.

```ruby
TranslationDiff.configure do |config|
  config.provider = :azure
  config.azure_api_key = ENV["AZURE_TRANSLATOR_KEY"]
  config.azure_region = "westeurope"
end
```

**ModernMT** takes a key and can be pointed at an adaptive memory per call,
since every unrecognised keyword reaches the provider untouched.

```ruby
TranslationDiff.configure do |config|
  config.provider = :modernmt
  config.modernmt_api_key = ENV["MMT_API_KEY"]
end

TranslationDiff.translate(text, from: "en", to: "ru", hints: "1234")
```

**LibreTranslate** inverts the usual arrangement: the base URL is required
because every instance is someone's own, and the key is optional because most
instances ask for none. It is also the only provider here you can run
yourself, which makes it the one to develop against.

```ruby
TranslationDiff.configure do |config|
  config.provider = :libretranslate
  config.libretranslate_api_base = "http://localhost:5000"
  config.libretranslate_api_key = ENV["LIBRETRANSLATE_KEY"] # optional
end
```

```bash
docker run -d --rm -p 5000:5000 libretranslate/libretranslate --load-only en,ru
```

**Amazon Translate** is signed rather than keyed, so it takes credentials and
a region. There is no environment fallback: this library does not implement
the AWS credential chain, so `AWS_ACCESS_KEY_ID` and friends are not read --
pass them explicitly.

```ruby
TranslationDiff.configure do |config|
  config.provider = :amazon
  config.amazon_access_key_id = ENV.fetch("AWS_ACCESS_KEY_ID")
  config.amazon_secret_access_key = ENV.fetch("AWS_SECRET_ACCESS_KEY")
  config.amazon_region = "eu-central-1"
end
```

Add `gem "aws-sigv4"` to your Gemfile for this one. It is Amazon's own
signing library and nothing more -- no clients, no service models -- and it
is required lazily, so an application on any other provider never installs it.

**Null** translates nothing and returns what it was given. It exists so a
pipeline can be wired up, and its cache and instrumentation exercised, before
anyone has paid for a key.

```ruby
TranslationDiff.configure { |config| config.provider = :null }
```

## Switching providers

Different providers can be used side by side without disturbing the global
configuration -- `TranslationDiff.context` yields an isolated copy, and
`provider:` overrides one call:

```ruby
formal = TranslationDiff.context do |config|
  config.provider = :deepl
  config.deepl_api_key = ENV["DEEPL_AUTH_KEY"]
end
formal.translate(contract, from: "en", to: "de", formality: :more)

TranslationDiff.translate(blog_post, from: "en", to: "de", provider: :google)
```

Both read and write the same cache, keyed per provider, so switching one
never serves you the other's translations.

## Capabilities, in full

**Every keyword other than `from:`, `to:`, `provider:`, `config:` and
`assume_supported:` is forwarded to the provider, and every provider applies
them the same way: its own defaults first, then your options, then the
fields the request cannot do without.** So `formality: :less` overrides a
default, and a keyword colliding with the language pair or the texts
themselves is overridden rather than obeyed. `assume_supported:` is reserved
because it is this library's own decision -- whether to skip language
validation for this call -- not a vendor's, and it must never reach a
payload.

**`usage.billed_characters` is `nil` when the provider said nothing about
billing and a number -- `0` included -- when it said something.** Three of
the six built-in providers report billing that way -- DeepL, Azure and
ModernMT; the other three, Google, LibreTranslate and Amazon, always answer
`nil`.

**Language codes are normalised per vendor, so switching provider needs no
other change.** A bare code (`"EN"`, `:ru`) is cased the way the vendor
documents it -- DeepL takes upper case, every other provider here takes lower
case -- whichever casing you wrote. A code carrying a script or region subtag
(`"zh-Hans"`, `"pt-BR"`) is passed through untouched, because the casing of a
subtag is its own. A provider of your own gets the same rule from
`TranslationDiff::Provider#language`; declare `def self.language_case =
:upcase` if your vendor wants upper case.

"Request size" is what `TranslationDiff::Batch` measures: the URL-escaped form of each
string (`CGI.escape(text).size`), which is never smaller than its UTF-8 byte
count. "HTML support" names the provider option that turns HTML handling on
-- every vendor spells it differently, which is exactly what
`Capabilities#html` is for. A provider whose "Detects language" column says
no makes `from:` required; passing it makes every provider's `#detect` call
unnecessary regardless of whether it has one.

### Very long texts

Every provider limits how large a single request or a single batch can be,
declared through `TranslationDiff::Capabilities#max_request_size` and
`#max_batch_size`; if your text is longer than that, TranslationDiff splits
it into multiple requests automatically. See the [provider
table](../README.md#providers) for each built-in provider's actual numbers -- DeepL, for
example, caps requests at 1,700 escaped characters and batches at 50
sentences.

### Provider caveats

**Amazon translates one text per call and honours no `notranslate`.** There
is no batch form of `TranslateText`, so a hundred sentences are a hundred
requests -- slow, but correct, and `Capabilities#max_batch_size` reflects
it. Amazon also has no HTML mode: a `notranslate` span reaches it as plain
text and is translated like everything else, tags and all. Both facts are
worth weighing before your bill and your brand names arrive, not after.

**LibreTranslate does not honour `notranslate` either -- measured, not
assumed.** Its HTML format preserves markup, but probing a real instance
(`docker run libretranslate/libretranslate --load-only en,ru`) with
`<span class="notranslate">Bold Mountain</span> is a good place.` came back
with the span tag intact and its content translated anyway -- "Bold
Mountain" became "Смелая гора". The tags survive; what they were meant to
protect does not.

ModernMT's `notranslate: false` is the conservative default rather than a
measurement: it documents an HTML format but says nothing about
`class="notranslate"`, and no key was available to probe it. A capability
that under-promises costs a warning; one that over-promises costs a
customer's protected content reaching a competitor's brand voice.

### Writing a provider

Any translation service can be a provider -- no change to this gem's own
code is required. Subclass `TranslationDiff::HTTPProvider` for a REST
service; it owns the Faraday connection, retries, timeouts and turns HTTP
status codes into this library's error hierarchy, and asks only for three
seams per operation: the URL, how to render a request, how to parse a
reply. Subclass `TranslationDiff::Provider` directly for anything that
reaches its service some other way -- signed requests, another gem, an
LLM client -- and implement `#translate` outright, the way
`TranslationDiff::Providers::Amazon` does.

Registering a provider also declares the options it needs, so
`config.acme_api_key` below does not exist until `AcmeProvider` is
registered:

```ruby
class AcmeProvider < TranslationDiff::HTTPProvider
  # Declares this provider's own configuration options.
  # TranslationDiff::Providers.register adds each one to
  # TranslationDiff::Configuration as a side effect.
  def self.configuration_options = %i[acme_api_key]
  def self.configuration_requirements = %i[acme_api_key]

  # What this provider can do, checked once by the pipeline for chunking,
  # detection and cache-key safety.
  def self.capabilities
    TranslationDiff::Capabilities.new(
      max_request_size: 10_000, max_batch_size: 100, max_text_size: nil,
      html: :format, notranslate: true, detects_language: true,
      reports_billing: false
    )
  end

  def api_base = config.acme_api_base || "https://api.acme.example/v1"
  def headers = { "Authorization" => "Bearer #{config.acme_api_key}" }
  def translate_url = "translate"

  # The three seams: build the request body, decode the reply.
  def render_translate_payload(request)
    { format: "HTML", texts: request.texts, targetLanguageCode: request.to.to_s }
      .tap { |body| body[:sourceLanguageCode] = request.from.to_s unless request.from.nil? }
  end

  def parse_translate_response(body, _headers, request)
    translations = Array(body["translations"])

    TranslationDiff::Translation::Response.build(
      request: request,
      texts: translations.map { |t| t["text"] },
      detected_source: translations.first&.dig("detectedLanguageCode")&.downcase
    )
  end

  def detect_url = "translate/v2/detect"

  def detect(text)
    response = post(detect_url, { text: text })
    response.body["languageCode"]&.downcase
  end

  # cache_key is optional: TranslationDiff::Providers.register stamps every
  # instance built through the registry with its registered name, and
  # Provider#cache_key falls back to that. Define it yourself only if this
  # provider will also be instantiated and assigned directly, bypassing the
  # registry -- see "Provider objects and cache_key" below.
end

TranslationDiff::Providers.register(:acme, AcmeProvider)

TranslationDiff.configure do |config|
  config.provider = :acme
  config.acme_api_key = ENV["ACME_API_KEY"]
end
```

`translate_url`/`render_translate_payload`/`parse_translate_response` are
the three seams `HTTPProvider#translate` calls in order; `detect` is
entirely optional -- omit it (and leave `capabilities.detects_language:
false`) if the provider has no detection endpoint, or if callers of this
gem always pass `from:` explicitly.

**`self.sensitive_options` decides which of this provider's
`configuration_options` `Configuration#inspect` and `Provider#inspect`
filter.** By default it is every declared option whose name matches
`TranslationDiff::Redaction::SENSITIVE` (`key`, `secret`, `token`,
`password`, `auth`, `credential`) -- `acme_api_key` above is caught by that
pattern for free. Override it when a credential's name doesn't match: a
provider reading `config.acme_handshake` for its credential leaks it on
every `inspect` unless it says so itself:

```ruby
def self.sensitive_options = %i[acme_handshake]
```

**Provider names must be unique.** `TranslationDiff::Providers.register`
overwrites whatever was previously registered under that name, silently --
there is no error for registering `:deepl` twice. This is deliberate: a
raise would break Rails development-mode reloading and a defensive double
`require`. It also means a typo in a name collides with a real provider
without warning, so choose names as carefully as you would a constant.

What happens when they are not unique is worth being precise about. The last
class registered under the name wins, and it also inherits the cache entries
of the one it replaced: `cache_key` falls back to the registered name, so a
class registered over `:deepl` reads and writes exactly the entries the real
DeepL provider wrote. Callers are then served one service's translations from
another service's cache, for as long as those entries live, with nothing in
the log to say so. Registering over an existing name is not a way to
substitute a service -- give the replacement its own name, or clear the cache
(`cache_namespace` is the cheapest way to do that).

**An option can declare a default.** A bare symbol in
`configuration_options` declares an option with no default. Writing
`key => default` instead declares one, and a callable default is evaluated on
every read rather than at load time -- which is what lets an environment
variable work when the application exports it after requiring this gem:

```ruby
def self.configuration_options
  [:acme_api_base, { acme_api_key: -> { ENV.fetch("ACME_API_KEY", nil) } }]
end
```

An explicitly configured value always wins over a default, and a default that
resolves to a blank string reads as unset -- the same rule assignment follows.

**Option names are unique too, and enforced.** Two providers declaring the
same `configuration_options` name would share one accessor on
`TranslationDiff::Configuration`, which would hand one service's credential
to the other, so registering the second one raises and names both providers
and the option. Prefix your options with your provider's name --
`deepl_api_key`, `google_api_key` -- the way the built-ins do. The same
provider redeclaring its own options is not a conflict: a double `require`
and a Rails reload both re-run registration.

`TranslationDiff::Providers.names` lists every registered provider;
`TranslationDiff::Providers.registered?(:acme)` checks one.

`test/support/provider_contract.rb` and `test/support/http_provider_contract.rb`
are the executable form of the provider contract: include `ProviderContract`
(and, for an `HTTPProvider` subclass, `HTTPProviderContract`) in a test class
that defines `#provider`, and they verify a provider inherits
`TranslationDiff::Provider`, that `#translate` preserves order and returns
one string per input, and that its declared capabilities are internally
consistent (a provider claiming `notranslate` must also claim an HTML mode).

### Provider objects and cache_key

A provider built through `TranslationDiff::Providers.build` (which is what
happens when `config.provider` is a symbol) is stamped with its registered
name automatically, and never needs to define `cache_key` itself --
`Provider#cache_key` falls back to that stamped name.

A provider object assigned straight to `config.provider` never passes
through the registry, so it gets no name and **must define `cache_key`
itself**, or every call through it raises. This is not pedantry: `cache_key`
is a segment of every cache entry this provider ever reads or writes, so two
providers sharing one -- or both silently falling back to an empty one --
would let a caller be served another provider's cached translation.

