# frozen_string_literal: true

require 'resolv'
require 'socket'
require 'legion/settings/os'
require_relative 'dns_bootstrap'

module Legion
  module Settings
    class Loader
      include Legion::Settings::OS

      class Error < RuntimeError; end
      attr_reader :warnings, :errors, :loaded_files, :settings

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

      def default_settings
        {
          client:                     client_defaults,
          cluster:                    { public_keys: {} },
          crypt:                      {
            cluster_secret:         nil,
            cluster_secret_timeout: 5,
            vault:                  { connected: false }
          },
          cache:                      { enabled: true, connected: false, driver: 'dalli' },
          extensions:                 {
            core:               %w[
              lex-node lex-tasker lex-scheduler lex-health lex-ping
              lex-telemetry lex-metering lex-log lex-audit
              lex-conditioner lex-transformer lex-exec lex-lex lex-codegen
            ],
            ai:                 %w[lex-claude lex-openai lex-gemini],
            gaia:               %w[lex-tick lex-mesh lex-apollo lex-cortex],
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
          },
          reload:                     false,
          reloading:                  false,
          auto_install_missing_lex:   true,
          default_extension_settings: {
            logger: { level: 'info', trace: false, extended: false }
          },
          logging:                    {
            level:             'info',
            location:          'stdout',
            trace:             true,
            backtrace_logging: true
          },
          transport:                  { connected: false },
          data:                       { connected: false },
          role:                       { profile: nil, extensions: [] },
          region:                     { current: nil, primary: nil, failover: nil, peers: [],
                                        default_affinity: 'prefer_local', data_residency: {} },
          process:                    { role: 'full' },
          dns:                        dns_defaults
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
        @indifferent_access = false
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
        log_debug("Loading module settings: #{mod_name}")
        @settings = deep_merge(config, @settings)
        @indifferent_access = false
      end

      def load_module_default(config)
        mod_name = config.keys.first
        log_debug("Loading module defaults: #{mod_name}")
        merged = deep_merge(@settings, config)
        deep_diff(@settings, merged) unless @loaded_files.empty?
        @settings = merged
        @indifferent_access = false
      end

      def load_file(file)
        log_debug("Trying to load file #{file}")
        if File.file?(file) && File.readable?(file)
          begin
            contents = read_config_file(file)
            config = contents.empty? ? {} : Legion::JSON.load(contents)
            merged = deep_merge(@settings, config)
            deep_diff(@settings, merged) unless @loaded_files.empty?
            @settings = merged
            # @indifferent_access = false
            @loaded_files << file
          rescue Legion::JSON::ParseError => e
            log_error("config file must be valid json: #{file}")
            log_error("  parse error: #{e.message}")
          end
        else
          log_warn("Config file does not exist or is not readable file:#{file}")
        end
      end

      def load_directory(directory)
        path = directory.gsub(/\\(?=\S)/, '/')
        if File.readable?(path) && File.executable?(path)
          files = Dir.glob(File.join(path, '**{,/*/**}/*.json')).uniq
          files.each { |file| load_file(file) }
          log_info("Settings: loaded directory #{path} (#{files.size} files)")
        else
          load_error('insufficient permissions for loading', directory: directory)
        end
      end

      def load_client_overrides
        @settings[:client][:subscriptions] ||= []
        if @settings[:client][:subscriptions].is_a?(Array)
          @settings[:client][:subscriptions] << "client:#{@settings[:client][:name]}"
          @settings[:client][:subscriptions].uniq!
          @indifferent_access = false
        else
          log_warn('unable to apply legion client overrides, reason: client subscriptions is not an array')
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

      def load_dns_from_cache(bootstrap)
        config = bootstrap.read_cache
        start_dns_background_refresh(bootstrap) if config
        config
      end

      def load_dns_first_boot(bootstrap)
        log_debug("DNS bootstrap: first boot, fetching from #{bootstrap.url}")
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
        @indifferent_access = false
      end

      def start_dns_background_refresh(bootstrap)
        Thread.new do
          fresh = bootstrap.fetch
          bootstrap.write_cache(fresh) if fresh
        rescue StandardError => e
          log_warn("DNS background refresh failed: #{e.message}")
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
        log_warn("using api port environment variable, api: #{@settings[:api]}")
        @indifferent_access = false
      end

      def load_privacy_env
        return unless ENV['LEGION_ENTERPRISE_PRIVACY'] == 'true'

        @settings[:enterprise_data_privacy] = true
        @indifferent_access = false
      end

      def read_config_file(file)
        contents = File.read(file).dup
        if contents.respond_to?(:force_encoding)
          encoding = ::Encoding::ASCII_8BIT
          contents = contents.force_encoding(encoding)
          bom = (+"\xEF\xBB\xBF").force_encoding(encoding)
          contents.sub!(bom, '')
        else
          contents.sub!(/^\357\273\277/, '')
        end
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

      def deep_diff(hash_one, hash_two)
        keys = hash_one.keys.concat(hash_two.keys).uniq
        keys.each_with_object({}) do |key, diff|
          next if hash_one[key] == hash_two[key]

          diff[key] = if hash_one[key].is_a?(Hash) && hash_two[key].is_a?(Hash)
                        deep_diff(hash_one[key], hash_two[key])
                      else
                        [hash_one[key], hash_two[key]]
                      end
        end
      end

      def create_loaded_tempfile!
        dir = ENV['LEGION_LOADED_TEMPFILE_DIR'] || Dir.tmpdir
        file_name = "legion_#{legion_service_name}_loaded_files"
        path = File.join(dir, file_name)
        File.write(path, @loaded_files.join(':'))
        path
      end

      def legion_service_name
        File.basename($PROGRAM_NAME).split('-').last
      end

      def system_hostname
        Socket.gethostname
      rescue StandardError => e
        Legion::Logging.debug("Legion::Settings::Loader#system_hostname failed: #{e.message}") if defined?(Legion::Logging)
        'unknown'
      end

      def system_address
        addresses = Socket.ip_address_list.select { |a| a.ipv4? && !a.ipv4_loopback? }
        preferred = addresses.find { |a| rfc1918?(a.ip_address) }
        (preferred || addresses.first)&.ip_address || 'unknown'
      rescue StandardError => e
        Legion::Logging.debug("Legion::Settings::Loader#system_address failed: #{e.message}") if defined?(Legion::Logging)
        'unknown'
      end

      def rfc1918?(ip)
        ip.start_with?('10.') ||
          ip.match?(/\A172\.(1[6-9]|2\d|3[01])\./) ||
          ip.start_with?('192.168.')
      end

      def log_info(message)
        defined?(Legion::Logging) ? Legion::Logging.info(message) : $stdout.puts(message)
      end

      def log_debug(message)
        Legion::Logging.debug(message) if defined?(Legion::Logging)
      end

      def log_warn(message)
        defined?(Legion::Logging) ? Legion::Logging.warn(message) : warn(message)
      end

      def log_error(message)
        defined?(Legion::Logging) ? Legion::Logging.error(message) : warn(message)
      end

      def warning(message, data = {})
        @warnings << {
          message: message
        }.merge(data)
        log_warn(message)
      end

      def load_error(message, data = {})
        @errors << {
          message: message
        }.merge(data)
        log_error(message)
        raise(Error, message)
      end

      def read_resolv_config
        config = Resolv::DNS::Config.default_config_hash
        {
          search_domains: config[:search]&.map(&:to_s)&.uniq,
          nameservers:    config[:nameserver]&.map(&:to_s)&.uniq
        }
      rescue StandardError => e
        log_warn("Failed to read resolv config: #{e.message}")
        { search_domains: [], nameservers: [] }
      end

      def detect_fqdn
        require 'timeout'
        fqdn = Timeout.timeout(1) { Addrinfo.getaddrinfo(Socket.gethostname, nil).first&.canonname }
        return nil if fqdn.nil?

        fqdn.include?('.') ? fqdn : nil
      rescue Timeout::Error
        log_debug('FQDN detection skipped (DNS timeout)')
        nil
      rescue StandardError => e
        log_debug("FQDN detection skipped (#{e.message.split(':').first})")
        nil
      end
    end
  end
end
