# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'legion/logging'
require 'legion/settings/loader'
require 'legion/settings/dns_bootstrap'

Legion::Logging.setup(level: 'fatal')

RSpec.describe Legion::Settings::Loader do
  let(:loader) { described_class.new }
  let(:assets_dir) { File.join(File.dirname(__FILE__), 'assets') }
  let(:config_file) { File.join(assets_dir, 'config.json') }
  let(:config_dir) { File.join(assets_dir, 'conf.d') }

  describe '#initialize' do
    it 'starts with empty warnings' do
      expect(loader.warnings).to eq([])
    end

    it 'starts with empty errors' do
      expect(loader.errors).to eq([])
    end

    it 'starts with empty loaded_files' do
      expect(loader.loaded_files).to eq([])
    end

    it 'starts with default settings' do
      expect(loader.settings).to be_a(Hash)
      expect(loader.settings).not_to be_empty
    end
  end

  describe '#dns_defaults' do
    subject(:dns) { loader.dns_defaults }

    it 'returns a hash' do
      expect(dns).to be_a(Hash)
    end

    it 'has a default_domain key' do
      expect(dns).to have_key(:default_domain)
    end

    it 'has a search_domains array' do
      expect(dns[:search_domains]).to be_an(Array)
    end

    it 'has a nameservers array' do
      expect(dns[:nameservers]).to be_an(Array)
    end

    it 'has an fqdn string or nil' do
      expect(dns[:fqdn]).to be_a(String).or be_nil
    end

    it 'has a bootstrap hash' do
      expect(dns[:bootstrap]).to be_a(Hash)
      expect(dns[:bootstrap][:enabled]).to eq(true)
    end
  end

  describe '#default_settings' do
    subject(:defaults) { loader.default_settings }

    it 'has client settings' do
      expect(defaults[:client]).to be_a(Hash)
      expect(defaults[:client]).to have_key(:hostname)
      expect(defaults[:client]).to have_key(:address)
      expect(defaults[:client]).to have_key(:name)
      expect(defaults[:client][:ready]).to eq(false)
    end

    it 'has cluster as empty Concurrent::Hash stub' do
      expect(defaults[:cluster]).to be_a(Concurrent::Hash)
    end

    it 'has crypt as empty Concurrent::Hash stub (module self-registers)' do
      expect(defaults[:crypt]).to be_a(Concurrent::Hash)
    end

    it 'has cache as empty Concurrent::Hash stub (module self-registers)' do
      expect(defaults[:cache]).to be_a(Concurrent::Hash)
    end

    it 'has extensions hash' do
      expect(defaults[:extensions]).to be_a(Hash)
    end

    it 'has logging with defaults from Legion::Logging::Settings' do
      expect(defaults[:logging]).to be_a(Hash)
      expect(defaults[:logging][:level]).to eq(:info)
    end

    it 'has transport and data as empty Concurrent::Hash stubs' do
      expect(defaults[:transport]).to be_a(Concurrent::Hash)
      expect(defaults[:data]).to be_a(Concurrent::Hash)
    end

    it 'has dns settings' do
      expect(defaults[:dns]).to be_a(Hash)
      expect(defaults[:dns]).to have_key(:default_domain)
      expect(defaults[:dns]).to have_key(:search_domains)
      expect(defaults[:dns]).to have_key(:nameservers)
    end

    it 'has absorbers settings' do
      expect(defaults[:absorbers]).to be_a(Hash)
    end
  end

  describe 'tier 1 defaults (gemspec dependencies)' do
    it 'pulls logging defaults directly from Legion::Logging::Settings' do
      logging = loader.to_hash[:logging]
      expect(logging[:level]).to eq(:info)
      expect(logging[:trace]).to eq(true)
    end

    it 'does not hardcode logging keys that belong to legion-logging' do
      logging = loader.to_hash[:logging]
      expect(logging).not_to have_key(:format)
      expect(logging).not_to have_key(:log_file)
      expect(logging).not_to have_key(:async)
    end
  end

  describe 'tier 2 stubs (self-registering libraries)' do
    it 'starts with empty stubs for transport, cache, crypt, data, absorbers' do
      defaults = loader.to_hash
      %i[transport cache crypt data absorbers].each do |key|
        expect(defaults[key]).to be_a(Hash)
        expect(defaults[key]).to be_empty
      end
    end
  end

  describe '#client_defaults' do
    subject(:client) { loader.client_defaults }

    it 'has a hostname string' do
      expect(client[:hostname]).to be_a(String)
    end

    it 'has an address string' do
      expect(client[:address]).to be_a(String)
    end

    it 'has a name with PID' do
      expect(client[:name]).to include(::Process.pid.to_s) # rubocop:disable Style/RedundantConstantBase
    end

    it 'has ready set to false' do
      expect(client[:ready]).to eq(false)
    end
  end

  describe '#load_file' do
    it 'loads a valid JSON file and merges settings' do
      loader.load_file(config_file)
      expect(loader[:api]).to be_a(Hash)
      expect(loader[:api][:port]).to eq(4567)
    end

    it 'tracks loaded files' do
      loader.load_file(config_file)
      expect(loader.loaded_files).to include(config_file)
    end

    it 'preserves default settings not in the file' do
      loader.load_file(config_file)
      expect(loader[:logging]).to be_a(Hash)
      expect(loader[:logging][:level]).to eq(:info)
    end

    it 'strips UTF-8 BOM from config files' do
      bom_file = File.join(assets_dir, 'bom_test.json')
      File.write(bom_file, "\xEF\xBB\xBF{\"test_bom\": true}", encoding: 'ASCII-8BIT')
      loader.load_file(bom_file)
      expect(loader[:test_bom]).to be true
    ensure
      FileUtils.rm_f(bom_file)
    end

    it 'handles an empty file without error' do
      empty_file = File.join(assets_dir, 'empty.json')
      expect { loader.load_file(empty_file) }.not_to raise_error
    end

    it 'handles invalid JSON gracefully' do
      invalid_file = File.join(assets_dir, 'invalid.json')
      expect { loader.load_file(invalid_file) }.not_to raise_error
      expect(loader.loaded_files).not_to include(invalid_file)
    end

    it 'logs the filename when JSON is invalid' do
      invalid_file = File.join(assets_dir, 'invalid.json')
      logger = instance_double('Logger', error: nil, debug: nil)
      allow(loader).to receive(:log).and_return(logger)
      expect(logger).to receive(:error).with(a_string_including(invalid_file))
      expect(logger).to receive(:error).with(a_string_matching(/parse error/))
      loader.load_file(invalid_file)
    end

    it 'handles a nonexistent file gracefully' do
      expect { loader.load_file('/tmp/nonexistent_legion_test_file.json') }.not_to raise_error
      expect(loader.loaded_files).to be_empty
    end
  end

  describe '#load_directory' do
    it 'loads all JSON files from a directory' do
      loader.load_directory(config_dir)
      expect(loader.loaded_files.size).to be >= 2
    end

    it 'merges settings from multiple files' do
      loader.load_directory(config_dir)
      expect(loader[:logging][:level]).to eq('debug')
      expect(loader[:cache][:namespace]).to eq('test_ns')
    end

    it 'raises on unreadable directory' do
      expect { loader.load_directory('/tmp/nonexistent_legion_dir') }.to raise_error(
        Legion::Settings::Loader::Error
      )
    end
  end

  describe '#load_env' do
    after { ENV.delete('LEGION_API_PORT') }

    it 'loads LEGION_API_PORT into settings' do
      ENV['LEGION_API_PORT'] = '9090'
      loader.load_env
      expect(loader[:api][:port]).to eq(9090)
    end

    it 'does nothing when LEGION_API_PORT is not set' do
      loader.load_env
      expect(loader.settings[:api]).to be_nil
    end
  end

  describe '#[]' do
    it 'provides access to settings by symbol key' do
      expect(loader[:logging]).to be_a(Hash)
    end

    it 'provides indifferent access with string keys' do
      expect(loader['logging']).to be_a(Hash)
      expect(loader['logging'][:level]).to eq(:info)
    end
  end

  describe '#[]=' do
    it 'sets a value' do
      loader[:custom] = 'test'
      expect(loader[:custom]).to eq('test')
    end
  end

  describe '#to_hash' do
    it 'returns a hash' do
      expect(loader.to_hash).to be_a(Hash)
    end

    it 'enables indifferent access' do
      hash = loader.to_hash
      expect(hash['logging']).to eq(hash[:logging])
    end
  end

  describe '#hexdigest' do
    it 'returns a SHA256 hex string' do
      digest = loader.hexdigest
      expect(digest).to be_a(String)
      expect(digest.length).to eq(64)
    end

    it 'returns the same value for identical settings' do
      loader2 = described_class.new
      expect(loader.hexdigest).to eq(loader2.hexdigest)
    end

    it 'changes when settings change' do
      original = loader.hexdigest
      loader[:custom] = 'changed'
      expect(loader.hexdigest).not_to eq(original)
    end
  end

  describe '#load_module_settings' do
    it 'merges new keys into settings' do
      loader.load_module_settings({ custom_module: { enabled: true } })
      expect(loader[:custom_module][:enabled]).to eq(true)
    end

    it 'preserves existing values (settings priority)' do
      loader.load_module_settings({ logging: { level: 'fatal' } })
      expect(loader[:logging][:level]).to eq(:info)
    end

    it 'preserves unrelated settings' do
      loader.load_module_settings({ custom_module: { enabled: true } })
      expect(loader[:cache]).to be_a(Hash)
    end

    it 'tracks merged module defaults for reload replay' do
      loader.load_module_settings({ custom_module: { enabled: true } })
      expect(loader.merged_modules[:custom_module][:enabled]).to eq(true)
    end
  end

  describe '#load_module_default' do
    it 'merges with default priority (existing values win)' do
      loader.load_module_default({ new_module: { key: 'value' } })
      expect(loader[:new_module]).to be_a(Hash)
      expect(loader[:new_module][:key]).to eq('value')
    end

    it 'does not overwrite existing scalar values' do
      loader[:custom_module] = { mode: 'runtime' }
      loader.load_module_default({ custom_module: { mode: 'default', enabled: true } })
      expect(loader[:custom_module][:mode]).to eq('runtime')
      expect(loader[:custom_module][:enabled]).to eq(true)
    end
  end

  describe '#set_env!' do
    before { require 'tmpdir' }
    after { ENV.delete('LEGION_LOADED_TEMPFILE') }

    it 'creates a tempfile and sets environment variable' do
      loader.load_file(config_file)
      loader.set_env!
      expect(ENV.fetch('LEGION_LOADED_TEMPFILE', nil)).to match(/legion_.*_loaded_files/)
      expect(File.exist?(ENV.fetch('LEGION_LOADED_TEMPFILE', nil))).to be true
    end

    it 'writes loaded file paths to the tempfile' do
      loader.load_file(config_file)
      loader.set_env!
      contents = File.read(ENV.fetch('LEGION_LOADED_TEMPFILE', nil))
      expect(contents).to include(config_file)
    end
  end

  describe '#default_settings extension categories' do
    subject(:defaults) { loader.default_settings }

    it 'includes extension category lists' do
      expect(defaults[:extensions][:core]).to be_an(Array)
      expect(defaults[:extensions][:ai]).to be_an(Array)
      expect(defaults[:extensions][:gaia]).to be_an(Array)
      expect(defaults[:extensions][:core]).to include('lex-node', 'lex-tasker')
      expect(defaults[:extensions][:ai]).to include('lex-claude', 'lex-openai', 'lex-gemini')
      expect(defaults[:extensions][:gaia]).to include('lex-tick', 'lex-apollo')
    end

    it 'includes category registry' do
      cats = defaults[:extensions][:categories]
      expect(cats[:core]).to eq({ type: :list, tier: 1 })
      expect(cats[:ai]).to eq({ type: :list, tier: 2 })
      expect(cats[:gaia]).to eq({ type: :list, tier: 3 })
      expect(cats[:agentic]).to eq({ type: :prefix, tier: 4 })
    end

    it 'includes governance defaults' do
      expect(defaults[:extensions][:blocked]).to eq([])
      expect(defaults[:extensions][:agentic]).to eq({ allowed: nil, blocked: [] })
      expect(defaults[:extensions][:reserved_prefixes]).to include('agentic', 'core', 'ai', 'gaia')
      expect(defaults[:extensions][:reserved_words]).to include('transport', 'cache', 'data')
    end

    it 'does not include lex-cortex in gaia' do
      expect(defaults[:extensions][:gaia]).not_to include('lex-cortex')
    end
  end

  describe '#load_dns_bootstrap' do
    let(:cache_dir) { Dir.mktmpdir('legion_dns_test') }

    after { FileUtils.rm_rf(cache_dir) }

    context 'when default_domain is nil' do
      it 'does nothing' do
        loader.settings[:dns] = { default_domain: nil, bootstrap: { enabled: true } }
        expect { loader.load_dns_bootstrap(cache_dir: cache_dir) }.not_to raise_error
      end
    end

    context 'when bootstrap is disabled via env var' do
      before { ENV['LEGION_DNS_BOOTSTRAP'] = 'false' }
      after { ENV.delete('LEGION_DNS_BOOTSTRAP') }

      it 'skips bootstrap' do
        loader.settings[:dns] = { default_domain: 'example.com', bootstrap: { enabled: true } }
        expect(Legion::Settings::DnsBootstrap).not_to receive(:new)
        loader.load_dns_bootstrap(cache_dir: cache_dir)
      end
    end

    context 'when cache file exists' do
      let(:cache_json) do
        meta = '"_dns_bootstrap_meta":{"fetched_at":"2026-01-01T00:00:00Z",' \
               '"hostname":"legion-bootstrap.example.com",' \
               '"url":"https://legion-bootstrap.example.com/legion/bootstrap.json"}'
        "{\"transport\":{\"host\":\"cached.example.com\"},#{meta}}"
      end

      it 'loads from cache without blocking fetch' do
        File.write(File.join(cache_dir, '_dns_bootstrap.json'), cache_json)
        loader.settings[:dns] = { default_domain: 'example.com', bootstrap: { enabled: true } }
        loader.load_dns_bootstrap(cache_dir: cache_dir)
        expect(loader[:transport][:host]).to eq('cached.example.com')
      end

      it 'populates dns.corp_bootstrap metadata' do
        File.write(File.join(cache_dir, '_dns_bootstrap.json'), cache_json)
        loader.settings[:dns] = { default_domain: 'example.com', bootstrap: { enabled: true } }
        loader.load_dns_bootstrap(cache_dir: cache_dir)
        expect(loader[:dns][:corp_bootstrap][:discovered]).to eq(true)
        expect(loader[:dns][:corp_bootstrap][:hostname]).to eq('legion-bootstrap.example.com')
      end
    end

    context 'when no cache and fetch succeeds (first boot)' do
      it 'fetches, caches, and merges config' do
        loader.settings[:dns] = { default_domain: 'example.com', bootstrap: { enabled: true } }
        bootstrap = instance_double(Legion::Settings::DnsBootstrap,
                                    default_domain: 'example.com',
                                    hostname:       'legion-bootstrap.example.com',
                                    url:            'https://legion-bootstrap.example.com/legion/bootstrap.json',
                                    cache_path:     File.join(cache_dir, '_dns_bootstrap.json'),
                                    cache_exists?:  false)
        allow(Legion::Settings::DnsBootstrap).to receive(:new).and_return(bootstrap)
        allow(bootstrap).to receive(:fetch).and_return({ transport: { host: 'fetched.example.com' } })
        allow(bootstrap).to receive(:write_cache)

        loader.load_dns_bootstrap(cache_dir: cache_dir)
        expect(bootstrap).to have_received(:fetch)
        expect(bootstrap).to have_received(:write_cache)
        expect(loader[:transport][:host]).to eq('fetched.example.com')
      end
    end

    context 'when no cache and fetch fails (first boot)' do
      it 'continues without bootstrap config' do
        loader.settings[:dns] = { default_domain: 'example.com', bootstrap: { enabled: true } }
        bootstrap = instance_double(Legion::Settings::DnsBootstrap,
                                    default_domain: 'example.com',
                                    hostname:       'legion-bootstrap.example.com',
                                    url:            'https://legion-bootstrap.example.com/legion/bootstrap.json',
                                    cache_path:     File.join(cache_dir, '_dns_bootstrap.json'),
                                    cache_exists?:  false)
        allow(Legion::Settings::DnsBootstrap).to receive(:new).and_return(bootstrap)
        allow(bootstrap).to receive(:fetch).and_return(nil)

        loader.load_dns_bootstrap(cache_dir: cache_dir)
        expect(loader[:transport]).to be_a(Hash)
      end
    end
  end

  describe 'deep merge behavior' do
    it 'merges nested hashes recursively' do
      loader.load_module_settings({ crypt: { vault: { connected: false } } })
      loader.load_module_settings({ crypt: { vault: { token: 'abc' } } })
      expect(loader[:crypt][:vault][:token]).to eq('abc')
      expect(loader[:crypt][:vault][:connected]).to eq(false)
    end

    it 'concatenates arrays uniquely' do
      loader[:test_arr] = [1, 2, 3]
      loader.load_module_default({ test_arr: [3, 4, 5] })
      expect(loader[:test_arr]).to contain_exactly(1, 2, 3, 4, 5)
    end

    it 'overwrites scalar values via load_file' do
      loader.load_file(config_file)
      expect(loader[:custom_key]).to eq('test_value')
    end
  end

  describe '#load_client_overrides' do
    context 'when subscriptions is an Array' do
      it 'appends the client name subscription and deduplicates' do
        loader.settings[:client][:subscriptions] = ['existing']
        loader.load_client_overrides
        expect(loader.settings[:client][:subscriptions]).to include("client:#{loader.settings[:client][:name]}")
        expect(loader.settings[:client][:subscriptions]).to include('existing')
      end
    end

    context 'when subscriptions is not an Array' do
      it 'logs a warning and does not crash' do
        loader.settings[:client][:subscriptions] = 'not_an_array'
        expect { loader.load_client_overrides }.not_to raise_error
      end

      it 'does not modify the non-Array subscriptions value' do
        loader.settings[:client][:subscriptions] = 'not_an_array'
        loader.load_client_overrides
        expect(loader.settings[:client][:subscriptions]).to eq('not_an_array')
      end
    end
  end

  describe '#load_overrides!' do
    context 'when legion_service_name is client or rspec' do
      it 'calls load_client_overrides' do
        allow(loader).to receive(:legion_service_name).and_return('rspec')
        expect(loader).to receive(:load_client_overrides)
        loader.load_overrides!
      end

      it 'calls load_client_overrides for client service name' do
        allow(loader).to receive(:legion_service_name).and_return('client')
        expect(loader).to receive(:load_client_overrides)
        loader.load_overrides!
      end
    end

    context 'when legion_service_name is something else' do
      it 'does not call load_client_overrides' do
        allow(loader).to receive(:legion_service_name).and_return('worker')
        expect(loader).not_to receive(:load_client_overrides)
        loader.load_overrides!
      end
    end
  end

  describe '#validate' do
    it 'does not raise when Legion::Settings.validate! raises ValidationError' do
      allow(Legion::Settings).to receive(:validate!).and_raise(
        Legion::Settings::ValidationError.new([{ module: :test, path: 'test.key', message: 'bad' }])
      )
      expect { loader.validate }.not_to raise_error
    end
  end

  describe '#setting_category' do
    it 'returns mapped entries with :name merged' do
      loader.settings[:transport] = { host: { default: 'localhost' }, port: { default: 5672 } }
      result = loader.send(:setting_category, :transport)
      expect(result).to be_an(Array)
      expect(result).to include(a_hash_including(name: 'host', default: 'localhost'))
      expect(result).to include(a_hash_including(name: 'port', default: 5672))
    end
  end

  describe '#definition_exists?' do
    it 'returns true for an existing key' do
      loader.settings[:transport] = { host: 'localhost', port: 5672 }
      expect(loader.send(:definition_exists?, :transport, :host)).to be true
    end

    it 'returns false for a missing key' do
      loader.settings[:transport] = { host: 'localhost' }
      expect(loader.send(:definition_exists?, :transport, :nonexistent)).to be false
    end
  end

  describe '#warning' do
    it 'appends to @warnings with merged data' do
      loader.send(:warning, 'test msg', extra: 'data')
      expect(loader.warnings.last).to eq({ message: 'test msg', extra: 'data' })
    end

    it 'logs a warn' do
      expect(loader.warnings).to be_empty
      loader.send(:warning, 'another warning')
      expect(loader.warnings.size).to eq(1)
      expect(loader.warnings.last[:message]).to eq('another warning')
    end
  end

  describe 'indifferent access reset' do
    it 'load_module_settings resets @indifferent_access so string keys work after to_hash' do
      loader.to_hash
      loader.load_module_settings({ extra: { key: 'value' } })
      expect(loader['extra']).to eq({ key: 'value' })
    end

    it 'load_module_default resets @indifferent_access so string keys work after to_hash' do
      loader.to_hash
      loader.load_module_default({ extra: { key: 'default_value' } })
      expect(loader['extra']).to eq({ key: 'default_value' })
    end

    it 'load_file resets @indifferent_access so string keys work after to_hash' do
      loader.to_hash
      loader.load_file(config_file)
      expect(loader['api']).to eq(loader[:api])
      expect(loader['custom_key']).to eq('test_value')
    end
  end
end
