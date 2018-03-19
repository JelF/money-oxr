require 'money/rates_store/memory'
require 'json'
require 'bigdecimal'
require 'open-uri'

module MoneyOXR
  class RatesStore < Money::RatesStore::Memory

    class UnsupportedCurrency < StandardError; end

    attr_reader :app_id, :source, :cache_path, :last_updated_at, :max_age

    def initialize(*)
      super
      @app_id = options[:app_id]
      @source = options[:source] || 'USD'
      @cache_path = options[:cache_path]
      @max_age = options[:max_age]
    end

    def get_rate(iso_from, iso_to)
      load
      super || begin
        if iso_from == source
          raise UnsupportedCurrency.new(iso_to)
        elsif inverse_rate = super(iso_to, iso_from)
          add_rate(iso_from, iso_to, 1 / inverse_rate)
        elsif iso_to == source
          raise UnsupportedCurrency.new(iso_from)
        else
          rate1 = get_rate(iso_from, source)
          rate2 = get_rate(source, iso_to)
          add_rate(iso_from, iso_to, rate1 * rate2)
        end
      end
    end

    def loaded?
      index.any?
    end

    def load
      # Loads data and ensures it is not stale.
      if !loaded? && cache_path && File.exist?(cache_path)
        load_from_cache_path
      end
      if app_id && (!loaded? || stale?)
        load_from_api
      end
    end

    def stale?
      return false if !max_age
      return true if last_updated_at.nil?
      last_updated_at + max_age < Time.now
    end

    def load_from_api
      json = get_json_from_api
      if cache_path
        write_cache_file(json)
        load_from_cache_path
      else
        load_json(json)
      end
    end

    def get_json_from_api
      open(api_uri).read
    end

    def api_uri
      "https://openexchangerates.org/api/latest.json?source=#{source}&app_id=#{app_id}"
    end

    def load_from_cache_path
      load_json(File.read(cache_path))
    end

    def write_cache_file(text)
      File.open(cache_path, 'w') { |file| file.write text }
    end

    def load_json(text)
      data = parse_json(text)
      transaction do
        @last_updated_at = Time.at(data['timestamp'])
        index.clear
        data['rates'].each do |iso_to, rate|
          add_rate(source, iso_to, rate)
        end
      end
    end

    def parse_json(text)
      # Convert text to strings so that we can use BigDecimal instead of Float
      text = text.gsub(/("[A-Z]{3}": ?)(\d+\.\d+)/, '\\1"\\2"')
      data = JSON.parse(text)
      data['rates'] = data['rates'].each_with_object({}) do |(key, value), rates|
        rates[key] = BigDecimal.new(value)
      end
      data
    end

  end
end