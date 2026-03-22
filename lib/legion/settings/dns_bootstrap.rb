# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'net/http'
require 'resolv'
require 'uri'

module Legion
  module Settings
    class DnsBootstrap
      CACHE_FILENAME = '_dns_bootstrap.json'
      HOSTNAME_PREFIX = 'legion-bootstrap'
      URL_PATH = '/legion/bootstrap.json'
      HTTP_TIMEOUT = 10

      attr_reader :default_domain, :hostname, :url, :cache_path

      def initialize(default_domain:, cache_dir: nil)
        @default_domain = default_domain
        @hostname = "#{HOSTNAME_PREFIX}.#{default_domain}"
        @url = "https://#{@hostname}#{URL_PATH}"
        dir = cache_dir || File.expand_path('~/.legionio/settings')
        @cache_path = File.join(dir, CACHE_FILENAME)
      end

      def resolve?
        Resolv.getaddress(@hostname)
        true
      rescue Resolv::ResolvError, Resolv::ResolvTimeout => e
        log_debug("Legion::Settings::DnsBootstrap#resolve? could not resolve #{@hostname}: #{e.message}")
        false
      end

      def fetch
        return nil unless resolve?

        uri = URI.parse(@url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = HTTP_TIMEOUT
        http.read_timeout = HTTP_TIMEOUT
        response = http.request(Net::HTTP::Get.new(uri))
        return nil unless response.is_a?(Net::HTTPSuccess)

        ::JSON.parse(response.body, symbolize_names: true)
      rescue StandardError => e
        log_warn("DNS bootstrap fetch failed for #{@url}: #{e.message}")
        nil
      end

      def write_cache(config)
        FileUtils.mkdir_p(File.dirname(@cache_path))
        payload = config.merge(
          _dns_bootstrap_meta: {
            fetched_at: Time.now.utc.iso8601,
            hostname:   @hostname,
            url:        @url
          }
        )
        tmp = "#{@cache_path}.tmp"
        File.write(tmp, ::JSON.pretty_generate(payload))
        File.rename(tmp, @cache_path)
      end

      def read_cache
        return nil unless File.exist?(@cache_path)

        raw = ::JSON.parse(File.read(@cache_path), symbolize_names: true)
        log_debug("DNS bootstrap cache hit: #{@cache_path}")
        raw.delete(:_dns_bootstrap_meta)
        raw
      rescue ::JSON::ParserError
        log_warn("DNS bootstrap cache corrupt, deleting: #{@cache_path}")
        FileUtils.rm_f(@cache_path)
        nil
      end

      def cache_exists?
        File.exist?(@cache_path)
      end

      private

      def log_debug(message)
        Legion::Logging.debug(message) if defined?(Legion::Logging)
      end

      def log_warn(message)
        defined?(Legion::Logging) ? Legion::Logging.warn(message) : warn(message)
      end
    end
  end
end
