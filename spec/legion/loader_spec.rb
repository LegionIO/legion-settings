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

    it 'has cluster settings' do
      expect(defaults[:cluster]).to eq({ public_keys: {} })
    end

    it 'has crypt settings' do
      expect(defaults[:crypt]).to be_a(Hash)
      expect(defaults[:crypt][:cluster_secret]).to be_nil
      expect(defaults[:crypt][:vault]).to eq({ connected: false })
    end

    it 'has cache settings' do
      expect(defaults[:cache]).to be_a(Hash)
      expect(defaults[:cache][:enabled]).to eq(true)
      expect(defaults[:cache][:connected]).to eq(false)
      expect(defaults[:cache][:driver]).to eq('dalli')
    end

    it 'has extensions hash' do
      expect(defaults[:extensions]).to be_a(Hash)
    end

    it 'has logging settings with all structured keys' do
      logging = defaults[:logging]
      expect(logging).to be_a(Hash)
      expect(logging[:level]).to eq('info')
      expect(logging[:format]).to eq('text')
      expect(logging[:async]).to eq(true)
      expect(logging[:include_pid]).to eq(false)
      expect(logging[:log_stdout]).to eq(true)
      expect(logging[:log_file]).to eq('./legionio/logs/legion.log')
      expect(logging[:trace]).to eq(true)
      expect(logging[:transport]).to be_a(Hash)
      expect(logging[:transport][:enabled]).to eq(true)
      expect(logging[:transport][:forward_logs]).to eq(true)
      expect(logging[:transport][:forward_exceptions]).to eq(true)
    end

    it 'has transport and data as not connected' do
      expect(defaults[:transport]).to eq({ connected: false })
      expect(defaults[:data]).to eq({ connected: false })
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

  describe '#logging_defaults' do
    subject(:logging) { loader.logging_defaults }

    it 'returns a hash' do
      expect(logging).to be_a(Hash)
    end

    it 'defaults level to info' do
      expect(logging[:level]).to eq('info')
    end

    it 'defaults format to text' do
      expect(logging[:format]).to eq('text')
    end

    it 'defaults async to true' do
      expect(logging[:async]).to eq(true)
    end

    it 'defaults include_pid to false' do
      expect(logging[:include_pid]).to eq(false)
    end

    it 'defaults log_stdout to true' do
      expect(logging[:log_stdout]).to eq(true)
    end

    it 'defaults log_file to ./legionio/logs/legion.log' do
      expect(logging[:log_file]).to eq('./legionio/logs/legion.log')
    end

    it 'defaults trace to true' do
      expect(logging[:trace]).to eq(true)
    end

    it 'includes a transport sub-hash' do
      expect(logging[:transport]).to be_a(Hash)
    end

    it 'defaults transport.enabled to true' do
      expect(logging[:transport][:enabled]).to eq(true)
    end

    it 'defaults transport.forward_logs to true' do
      expect(logging[:transport][:forward_logs]).to eq(true)
    end

    it 'defaults transport.forward_exceptions to true' do
      expect(logging[:transport][:forward_exceptions]).to eq(true)
    end
  end

  describe '#absorbers_defaults' do
    subject(:absorbers) { loader.absorbers_defaults }

    it 'returns a hash' do
      expect(absorbers).to be_a(Hash)
    end

    it 'defaults enabled to true' do
      expect(absorbers[:enabled]).to be true
    end

    it 'defaults max_depth to 5' do
      expect(absorbers[:max_depth]).to eq(5)
    end

    it 'has a sources section' do
      expect(absorbers[:sources]).to be_a(Hash)
    end

    it 'defaults sources.meetings.enabled to true' do
      expect(absorbers[:sources][:meetings][:enabled]).to be true
    end

    it 'defaults sources.email_inbox.enabled to false' do
      expect(absorbers[:sources][:email_inbox][:enabled]).to be false
    end

    it 'defaults sources.github.enabled to true' do
      expect(absorbers[:sources][:github][:enabled]).to be true
    end

    it 'defaults sources.files.enabled to true' do
      expect(absorbers[:sources][:files][:enabled]).to be true
    end

    it 'defaults sources.files.extensions to expected list' do
      expect(absorbers[:sources][:files][:extensions]).to eq(%w[pdf docx txt md pptx rtf])
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
      expect(loader[:logging][:level]).to eq('info')
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
      expect(loader['logging'][:level]).to eq('info')
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
      expect(loader[:logging][:level]).to eq('info')
    end

    it 'preserves unrelated settings' do
      loader.load_module_settings({ custom_module: { enabled: true } })
      expect(loader[:cache]).to be_a(Hash)
    end
  end

  describe '#load_module_default' do
    it 'merges with default priority (existing values win)' do
      loader.load_module_default({ new_module: { key: 'value' } })
      expect(loader[:new_module]).to be_a(Hash)
      expect(loader[:new_module][:key]).to eq('value')
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
        expect(loader[:transport]).to eq({ connected: false })
      end
    end
  end

  describe 'deep merge behavior' do
    it 'merges nested hashes recursively' do
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
  end
end
