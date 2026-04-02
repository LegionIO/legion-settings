# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe Legion::Settings do
  before do
    described_class.reset!
  end

  describe '.load' do
    it 'creates a new loader' do
      result = described_class.load
      expect(result).to be_a(Legion::Settings::Loader)
    end

    it 'loads from a config file' do
      config_file = File.join(File.dirname(__FILE__), 'assets', 'config.json')
      described_class.load(config_file: config_file)
      expect(described_class[:api][:port]).to eq(4567)
    end

    it 'loads from a config directory' do
      config_dir = File.join(File.dirname(__FILE__), 'assets', 'conf.d')
      described_class.load(config_dir: config_dir)
      expect(described_class[:logging][:level]).to eq('debug')
    end

    it 'loads from multiple config directories' do
      config_dir = File.join(File.dirname(__FILE__), 'assets', 'conf.d')
      described_class.load(config_dirs: [config_dir])
      expect(described_class[:cache][:namespace]).to eq('test_ns')
    end

    it 'loads .legionio.env during no-arg load' do
      dir = Dir.mktmpdir('legion_settings_load_test')
      old_dir = Dir.pwd
      old_bootstrap = ENV.fetch('LEGION_DNS_BOOTSTRAP', nil)
      ENV['LEGION_DNS_BOOTSTRAP'] = 'false'
      File.write(File.join(dir, '.legionio.env'), "project_env_key=project_value\n")

      Dir.chdir(dir) do
        described_class.load
        expect(described_class[:project_env_key]).to eq('project_value')
      end
    ensure
      ENV['LEGION_DNS_BOOTSTRAP'] = old_bootstrap
      Dir.chdir(old_dir)
      FileUtils.rm_rf(dir)
    end
  end

  describe '.[]' do
    it 'auto-loads when not initialized' do
      expect(described_class[:logging]).to be_a(Hash)
    end

    it 'returns nil for unknown keys' do
      expect(described_class[:nonexistent]).to be_nil
    end

    it 'returns expected default values' do
      expect(described_class[:cache][:driver]).to eq('dalli')
    end

    it 'auto-loads .legionio.env when accessed implicitly' do
      dir = Dir.mktmpdir('legion_settings_implicit_access_test')
      old_dir = Dir.pwd
      old_bootstrap = ENV.fetch('LEGION_DNS_BOOTSTRAP', nil)
      ENV['LEGION_DNS_BOOTSTRAP'] = 'false'
      File.write(File.join(dir, '.legionio.env'), "project_env_key=implicit_value\n")

      Dir.chdir(dir) do
        expect(described_class[:project_env_key]).to eq('implicit_value')
      end
    ensure
      ENV['LEGION_DNS_BOOTSTRAP'] = old_bootstrap
      Dir.chdir(old_dir)
      FileUtils.rm_rf(dir)
    end
  end

  describe '.dig' do
    it 'applies overlay precedence consistently with []' do
      described_class.merge_settings('m', { a: 1, b: { c: 2 } })

      described_class.with_overlay(m: { b: { c: 9 } }) do
        expect(described_class.dig(:m, :b, :c)).to eq(9)
      end
    end

    it 'auto-loads .legionio.env when accessed implicitly' do
      dir = Dir.mktmpdir('legion_settings_implicit_dig_test')
      old_dir = Dir.pwd
      old_bootstrap = ENV.fetch('LEGION_DNS_BOOTSTRAP', nil)
      ENV['LEGION_DNS_BOOTSTRAP'] = 'false'
      File.write(File.join(dir, '.legionio.env'), "project_env.key=dig_value\n")

      Dir.chdir(dir) do
        expect(described_class.dig(:project_env, :key)).to eq('dig_value')
      end
    ensure
      ENV['LEGION_DNS_BOOTSTRAP'] = old_bootstrap
      Dir.chdir(old_dir)
      FileUtils.rm_rf(dir)
    end
  end

  describe '.get' do
    it 'returns the loader' do
      expect(described_class.get).to be_a(Legion::Settings::Loader)
    end

    it 'reuses existing loader on subsequent calls' do
      first = described_class.get
      second = described_class.get
      expect(first).to equal(second)
    end
  end

  describe '.set_prop' do
    it 'sets a property on the loader' do
      described_class.set_prop(:test_key, 'test_value')
      expect(described_class[:test_key]).to eq('test_value')
    end
  end

  describe '.merge_settings' do
    it 'merges module settings into the loader' do
      described_class.merge_settings('test_module', { host: 'localhost', port: 8080 })
      expect(described_class[:test_module][:host]).to eq('localhost')
      expect(described_class[:test_module][:port]).to eq(8080)
    end

    it 'registers the schema for the module' do
      described_class.merge_settings('test_mod', { enabled: true })
      expect(described_class.schema.registered_modules).to include(:test_mod)
    end
  end

  describe '.define_schema' do
    it 'adds schema overrides and validates against them' do
      described_class.merge_settings('svc', { driver: 'http' })
      described_class.define_schema('svc', { driver: { enum: %w[http grpc] } })
      described_class.loader.settings[:svc][:driver] = 'invalid'
      expect { described_class.validate! }.to raise_error(Legion::Settings::ValidationError)
    end
  end

  describe '.add_cross_validation' do
    it 'registers and runs a cross-validation block' do
      described_class.merge_settings('mod_a', { ready: true })
      described_class.add_cross_validation do |settings, errors|
        errors << { module: :mod_a, message: 'cross validation fired' } if settings[:mod_a][:ready]
      end
      expect { described_class.validate! }.to raise_error(Legion::Settings::ValidationError)
    end
  end

  describe '.validate!' do
    it 'does not raise when there are no errors' do
      described_class.load
      expect { described_class.validate! }.not_to raise_error
    end

    it 'raises ValidationError when there are type mismatches' do
      described_class.merge_settings('typed', { port: 8080 })
      described_class.loader.settings[:typed][:port] = 'not_a_number'
      expect { described_class.validate! }.to raise_error(Legion::Settings::ValidationError)
    end

    it 'rebuilds validation errors from scratch on subsequent runs' do
      described_class.merge_settings('typed', { port: 8080 })
      described_class.loader.settings[:typed][:port] = 'not_a_number'
      expect { described_class.validate! }.to raise_error(Legion::Settings::ValidationError)

      described_class.loader.settings[:typed][:port] = 8080
      expect { described_class.validate! }.not_to raise_error
      expect(described_class.errors).to be_empty
    end
  end

  describe '.errors' do
    it 'returns an array' do
      expect(described_class.errors).to be_a(Array)
    end
  end

  describe '.schema' do
    it 'returns a Schema instance' do
      expect(described_class.schema).to be_a(Legion::Settings::Schema)
    end

    it 'is memoized' do
      expect(described_class.schema).to equal(described_class.schema)
    end
  end

  describe '.logger' do
    it 'returns a logger' do
      logger = described_class.logger
      expect(logger).to respond_to(:info)
      expect(logger).to respond_to(:warn)
      expect(logger).to respond_to(:error)
    end
  end

  describe 'CORE_MODULES' do
    it 'contains expected module names' do
      expect(Legion::Settings::CORE_MODULES).to include(:transport, :cache, :crypt, :data, :logging, :client)
    end

    it 'is frozen' do
      expect(Legion::Settings::CORE_MODULES).to be_frozen
    end
  end
end
