# frozen_string_literal: true

require 'resolv'
require 'socket'
require 'digest'
require 'tmpdir'
require 'concurrent/hash'
require 'legion/logging'
require 'legion/settings/os'
require_relative 'dns_bootstrap'

module Legion
  module Settings
    class Loader
      include Legion::Settings::OS
      include Legion::Logging::Helper

      class Error < RuntimeError; end
      attr_reader :warnings, :errors, :loaded_files, :settings, :merged_modules

      def self.default_directories
        env_dirs = ENV.fetch('LEGION_SETTINGS_DIRS', nil)
        if env_dirs && !env_dirs.strip.empty?
          env_dirs_list = env_dirs.split(File::PATH_SEPARATOR).map(&:strip).reject(&:empty?).map { |p| File.expand_path(p) }
          return env_dirs_list unless env_dirs_list.empty?
        end

        dirs = [File.expand_path('~/.legionio/settings')]
        if OS.windows?
          appdata = ENV.fetch('APPDATA', nil)
          dirs << File.join(appdata, 'legionio', 'settings') if appdata && !appdata.strip.empty?
        else
          dirs << '/etc/legionio/settings'
        end
        dirs
      end

      def initialize
        @warnings = []
        @errors = []
        @settings = default_settings
        @indifferent_access = false
        @loaded_files = []
        @merged_modules = {}
        log.debug('Initialized Legion::Settings::Loader with default settings')
      end

      def dns_defaults
        resolv_config = read_resolv_config
        {
          fqdn:           detect_fqdn,
          default_domain: resolv_config[:search_domains]&.first,
          search_domains: resolv_config[:search_domains] || [],
          nameservers:    resolv_config[:nameservers] || [],
          bootstrap:      { enabled: true }
        }
      end

      def client_defaults
        {
          hostname: system_hostname,
          address:  system_address,
          name:     "#{::Socket.gethostname.tr('.', '_')}.#{::Process.pid}",
          ready:    false
        }
      end

      # No more per-module defaults methods in the Loader.
      # Tier 1 deps (json, logging) are called directly in default_settings.
      # Tier 2 libraries (transport, cache, etc.) self-register via
      # Legion::Settings.register_library when they load.

      def default_settings
        {
          # --- Tier 1: gemspec dependencies (always installed with legion-settings) ---
          # legion-logging: always available, has Settings.default
          logging:                    Legion::Logging::Settings.default,
          # legion-json: always available, no Settings module yet — stub
          # until legion-json adds Legion::JSON::Settings.default
          json:                       Concurrent::Hash.new,

          # --- Structural: owned by legion-settings itself ---
          client:                     client_defaults,
          cluster:                    Concurrent::Hash.new,
          dns:                        dns_defaults,
          extensions:                 Concurrent::Hash[
            core:               %w[
              lex-node lex-tasker lex-scheduler lex-health lex-ping
              lex-telemetry lex-metering lex-log lex-audit
              lex-conditioner lex-transformer lex-exec lex-lex lex-codegen
            ],
            ai:                 %w[lex-claude lex-openai lex-gemini],
            gaia:               %w[lex-tick lex-mesh lex-apollo],
            categories:         {
              core:    { type: :list, tier: 1 },
              ai:      { type: :list, tier: 2 },
              gaia:    { type: :list, tier: 3 },
              agentic: { type: :prefix, tier: 4 }
            },
            blocked:            [],
            reserved_prefixes:  %w[core ai agentic gaia],
            reserved_words:     %w[transport cache crypt data settings json logging llm rbac legion],
            agentic:            { allowed: nil, blocked: [] },
            parallel_pool_size: 24
          ],
          reload:                     false,
          reloading:                  false,
          auto_install_missing_lex:   true,
          default_extension_settings: {},
          role:                       { profile: nil, extensions: [] },
          region:                     { current: nil, primary: nil, failover: nil, peers: [],
                                        default_affinity: 'any', data_residency: {} },
          process:                    { role: 'full' },

          # --- Tier 2: stubs for libraries that self-register via register_library ---
          # These ensure Settings[:key] returns a hash (not nil) before
          # the owning library loads. The library replaces these with its
          # full defaults when it calls Legion::Settings.register_library.
          absorbers:                  Concurrent::Hash.new,
          cache:                      Concurrent::Hash.new,
          crypt:                      Concurrent::Hash.new,
          data:                       Concurrent::Hash.new,
          transport:                  Concurrent::Hash.new
        }
      end

      def to_hash
        unless @indifferent_access
          indifferent_access!
          @hexdigest = nil
        end
        @settings
      end

      def [](key)
        to_hash[key]
      end

      def dig(*keys)
        to_hash.dig(*keys)
      end

      def []=(key, value)
        @settings[key] = value
        mark_dirty!
      end

      def hexdigest
        if @hexdigest && @indifferent_access
          @hexdigest
        else
          hash = case legion_service_name
                 when 'client', 'rspec'
                   to_hash
                 else
                   to_hash.reject do |key, _value|
                     key.to_s == 'client'
                   end
                 end
          @hexdigest = Digest::SHA256.hexdigest(hash.to_s)
        end
      end

      def load_env
        load_api_env
        load_privacy_env
      end

      def load_dns_bootstrap(cache_dir: nil)
        return if ENV['LEGION_DNS_BOOTSTRAP'] == 'false'

        domain = @settings.dig(:dns, :default_domain)
        return unless domain
        return unless @settings.dig(:dns, :bootstrap, :enabled)

        dir = cache_dir || File.expand_path('~/.legionio/settings')
        bootstrap = DnsBootstrap.new(default_domain: domain, cache_dir: dir)

        config = if bootstrap.cache_exists?
                   load_dns_from_cache(bootstrap)
                 else
                   load_dns_first_boot(bootstrap)
                 end

        return unless config

        merge_dns_config(config, bootstrap)
      end

      def load_module_settings(config)
        mod_name = config.keys.first
        log.debug("Loading module settings: #{mod_name}")
        @merged_modules = deep_merge(@merged_modules, config)
        @settings = deep_merge(config, @settings)
        mark_dirty!
      end

      def load_module_default(config)
        mod_name = config.keys.first
        log.debug("Loading module defaults: #{mod_name}")
        @settings = deep_merge(config, @settings)
        mark_dirty!
      end

      def load_file(file)
        log.debug("Trying to load file #{file}")
        if File.file?(file) && File.readable?(file)
          begin
            contents = read_config_file(file)
            config = contents.empty? ? {} : Legion::JSON.load(contents)
            @settings = deep_merge(@settings, config)
            mark_dirty!
            @loaded_files << file
            log.debug("Loaded settings file #{file}")
          rescue Legion::JSON::ParseError => e
            log.error("config file must be valid json: #{file}")
            log.error("  parse error: #{e.message}")
          end
        else
          log.warn("Config file does not exist or is not readable file:#{file}")
        end
      end

      def load_directory(directory)
        path = directory.gsub(/\\(?=\S)/, '/')
        if File.readable?(path) && File.executable?(path)
          files = Dir.glob(File.join(path, '**', '*.json'))
          files.each { |file| load_file(file) }
          log.info("Settings: loaded directory #{path} (#{files.size} files)")
        else
          load_error('insufficient permissions for loading', directory: directory)
        end
      end

      def load_client_overrides
        @settings[:client][:subscriptions] ||= []
        if @settings[:client][:subscriptions].is_a?(Array)
          @settings[:client][:subscriptions] << "client:#{@settings[:client][:name]}"
          @settings[:client][:subscriptions].uniq!
          mark_dirty!
        else
          log.warn('unable to apply legion client overrides, reason: client subscriptions is not an array')
        end
      end

      def load_overrides!
        load_client_overrides if %w[client rspec].include?(legion_service_name)
      end

      def set_env!
        ENV['LEGION_LOADED_TEMPFILE'] = create_loaded_tempfile!
      end

      def validate
        Legion::Settings.validate!
      rescue Legion::Settings::ValidationError
        # errors are already collected in @errors
      end

      private

      def resolve_logger_settings
        raw_logging = instance_variable_defined?(:@settings) ? @settings&.[](:logging) : nil
        raw_logging.is_a?(Hash) ? raw_logging : Legion::Logging::Settings.default
      end

      def load_dns_from_cache(bootstrap)
        config = bootstrap.read_cache
        start_dns_background_refresh(bootstrap) if config
        config
      end

      def load_dns_first_boot(bootstrap)
        log.debug("DNS bootstrap: first boot, fetching from #{bootstrap.url}")
        config = bootstrap.fetch
        bootstrap.write_cache(config) if config
        config
      end

      def merge_dns_config(config, bootstrap)
        @settings = deep_merge(config, @settings)
        @settings[:dns] ||= {}
        @settings[:dns][:corp_bootstrap] = {
          discovered: true,
          hostname:   bootstrap.hostname,
          url:        bootstrap.url
        }
        mark_dirty!
      end

      def start_dns_background_refresh(bootstrap)
        Thread.new do
          fresh = bootstrap.fetch
          bootstrap.write_cache(fresh) if fresh
        rescue StandardError => e
          log.warn("DNS background refresh failed: #{e.message}")
        end
      end

      def setting_category(category)
        @settings[category].map do |name, details|
          details.merge(name: name.to_s)
        end
      end

      def definition_exists?(category, name)
        @settings[category].key?(name.to_sym)
      end

      def indifferent_hash
        Hash.new do |hash, key|
          hash[key.to_sym] if key.is_a?(String)
        end
      end

      def with_indifferent_access(hash)
        hash = indifferent_hash.merge(hash)
        hash.each do |key, value|
          hash[key] = with_indifferent_access(value) if value.is_a?(Hash)
        end
      end

      def indifferent_access!
        @settings = with_indifferent_access(@settings)
        @indifferent_access = true
      end

      def load_api_env
        return unless ENV['LEGION_API_PORT']

        @settings[:api] ||= {}
        @settings[:api][:port] = ENV['LEGION_API_PORT'].to_i
        log.warn("using api port environment variable, api: #{@settings[:api]}")
        mark_dirty!
      end

      def load_privacy_env
        return unless ENV['LEGION_ENTERPRISE_PRIVACY'] == 'true'

        @settings[:enterprise_data_privacy] = true
        mark_dirty!
      end

      def read_config_file(file)
        contents = File.read(file).dup
        encoding = ::Encoding::ASCII_8BIT
        contents = contents.force_encoding(encoding)
        bom = (+"\xEF\xBB\xBF").force_encoding(encoding)
        contents.sub!(bom, '')
        contents.strip
      end

      def deep_merge(hash_one, hash_two)
        merged = hash_one.dup
        hash_two.each do |key, value|
          merged[key] = if hash_one[key].is_a?(Hash) && value.is_a?(Hash)
                          deep_merge(hash_one[key], value)
                        elsif hash_one[key].is_a?(Array) && value.is_a?(Array)
                          hash_one[key].concat(value).uniq
                        else
                          value
                        end
        end
        merged
      end

      def create_loaded_tempfile!
        dir = ENV['LEGION_LOADED_TEMPFILE_DIR'] || Dir.tmpdir
        file_name = "legion_#{legion_service_name}_loaded_files"
        path = File.join(dir, file_name)
        File.write(path, @loaded_files.join(':'))
        path
      end

      public

      def mark_dirty!
        @indifferent_access = false
        @hexdigest = nil
      end

      private

      def legion_service_name
        File.basename($PROGRAM_NAME).split('-').last
      end

      def system_hostname
        Socket.gethostname
      rescue StandardError => e
        log.debug("Legion::Settings::Loader#system_hostname failed: #{e.message}")
        'unknown'
      end

      def system_address
        addresses = Socket.ip_address_list.select { |a| a.ipv4? && !a.ipv4_loopback? }
        preferred = addresses.find { |a| rfc1918?(a.ip_address) }
        (preferred || addresses.first)&.ip_address || 'unknown'
      rescue StandardError => e
        log.debug("Legion::Settings::Loader#system_address failed: #{e.message}")
        'unknown'
      end

      def rfc1918?(ip)
        ip.start_with?('10.') ||
          ip.match?(/\A172\.(1[6-9]|2\d|3[01])\./) ||
          ip.start_with?('192.168.')
      end

      def warning(message, data = {})
        @warnings << {
          message: message
        }.merge(data)
        log.warn(message)
      end

      def load_error(message, data = {})
        @errors << {
          message: message
        }.merge(data)
        log.error(message)
        raise(Error, message)
      end

      def read_resolv_config
        config = Resolv::DNS::Config.default_config_hash
        {
          search_domains: config[:search]&.map(&:to_s)&.uniq,
          nameservers:    config[:nameserver]&.map(&:to_s)&.uniq
        }
      rescue StandardError => e
        log.warn("Failed to read resolv config: #{e.message}")
        { search_domains: [], nameservers: [] }
      end

      def detect_fqdn
        require 'timeout'
        fqdn = Timeout.timeout(1) { Addrinfo.getaddrinfo(Socket.gethostname, nil).first&.canonname }
        return nil if fqdn.nil?

        fqdn.include?('.') ? fqdn : nil
      rescue Timeout::Error
        log.debug('FQDN detection skipped (DNS timeout)')
        nil
      rescue StandardError => e
        log.debug("FQDN detection skipped (#{e.message.split(':').first})")
        nil
      end
    end
  end
end
