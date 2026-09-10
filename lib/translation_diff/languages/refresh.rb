# A maintainer's tool: re-fetches every provider's lists and rewrites the shipped files.
class TranslationDiff::Languages::Refresh
  def self.call(providers:, directory: TranslationDiff::Languages::DIRECTORY, on: Time.now.strftime("%Y-%m-%d"))
    new(providers: providers, directory: directory, on: on).call
  end

  def initialize(providers:, directory:, on:)
    @providers = providers
    @directory = directory
    @on = on
  end

  # A provider whose fetch fails keeps its previous file: an emptied list is worse than a stale one.
  def call
    report = { updated: [], failed: {}, skipped: [] }

    @providers.each do |provider|
      name = provider.cache_key
      fetched = fetch(provider, name, report)
      next if fetched.nil?

      persist(name, provider, fetched, report)
    end

    report
  end

  private

  def fetch(provider, name, report)
    fetched = provider.languages
    return report_empty(name, report) if empty?(fetched)

    fetched
  rescue NotImplementedError
    report[:skipped] << name
    nil
  rescue StandardError => e
    report[:failed][name] = "#{e.class}: #{e.message}"
    nil
  end

  # A 200 with an empty or malformed body degrades to [] through Array(...); that is not data, it's a failure.
  def empty?(fetched) = Array(fetched[:source]).empty? || Array(fetched[:target]).empty?

  def report_empty(name, report)
    report[:failed][name] = "the vendor answered with an empty source or target list"
    nil
  end

  # A write that cannot land -- a read-only checkout, a full disk -- must not cost the rest of the run.
  def persist(name, provider, fetched, report)
    write(name, provider, fetched)
    report[:updated] << name
  rescue StandardError => e
    report[:failed][name] = "#{e.class}: #{e.message}"
  end

  def write(name, provider, fetched)
    document = { "provider" => name, "captured_at" => @on,
                 "endpoint" => endpoint(provider),
                 "source" => normalise(fetched[:source]), "target" => normalise(fetched[:target]) }

    File.write(File.join(@directory, "#{name}.json"), "#{JSON.pretty_generate(document)}\n")
  end

  def normalise(codes) = Array(codes).map { |code| code.to_s.downcase }.uniq.sort

  def endpoint(provider) = provider.languages_endpoint.to_s
end
