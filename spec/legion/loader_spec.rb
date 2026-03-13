# frozen_string_literal: true

require 'spec_helper'
require 'legion/logging'
require 'legion/settings/loader'

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

    it 'has empty extensions' do
      expect(defaults[:extensions]).to eq({})
    end

    it 'has logging settings' do
      expect(defaults[:logging]).to be_a(Hash)
      expect(defaults[:logging][:level]).to eq('info')
    end

    it 'has transport and data as not connected' do
      expect(defaults[:transport]).to eq({ connected: false })
      expect(defaults[:data]).to eq({ connected: false })
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
      expect(client[:name]).to include(Process.pid.to_s)
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
end
