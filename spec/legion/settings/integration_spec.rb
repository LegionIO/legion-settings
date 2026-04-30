# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'legion/logging'
require 'legion/settings/schema'
require 'legion/settings/validation_error'

Legion::Logging.setup(log_level: 'warn', level: 'warn', trace: false)

RSpec.describe 'Settings validation integration' do
  before do
    Legion::Settings.instance_variable_set(:@loader, nil)
    Legion::Settings.instance_variable_set(:@schema, nil)
    Legion::Settings.instance_variable_set(:@cross_validations, nil)
    Legion::Settings.load
  end

  describe '.merge_settings with schema inference' do
    it 'registers schema when merging settings' do
      Legion::Settings.merge_settings('mymodule', { host: 'localhost', port: 8080 })
      expect(Legion::Settings.schema.registered_modules).to include(:mymodule)
    end

    it 'defers type error collection to validate! (not on merge)' do
      Legion::Settings.set_prop(:mymodule, { port: 'not_a_number' })
      Legion::Settings.merge_settings('mymodule', { port: 8080 })
      # Errors are NOT collected eagerly on merge anymore
      expect(Legion::Settings.errors).to be_empty
      # But validate! catches them
      expect { Legion::Settings.validate! }.to raise_error(Legion::Settings::ValidationError)
    end
  end

  describe '.define_schema' do
    it 'stores overrides for a module' do
      Legion::Settings.merge_settings('cache', { driver: 'dalli' })
      Legion::Settings.define_schema('cache', { driver: { enum: %w[dalli redis] } })
      constraint = Legion::Settings.schema.constraint(:cache, [:driver])
      expect(constraint[:enum]).to eq(%w[dalli redis])
    end
  end

  describe '.add_cross_validation' do
    it 'registers a cross-validation block' do
      called = false
      Legion::Settings.add_cross_validation { |_settings, _errors| called = true }
      Legion::Settings.validate!
      expect(called).to be true
    end

    it 'collects errors from cross-validation blocks' do
      Legion::Settings.add_cross_validation do |_settings, errors|
        errors << { module: :test, path: 'test.key', message: 'cross-module failure' }
      end
      expect { Legion::Settings.validate! }.to raise_error(Legion::Settings::ValidationError)
    end
  end

  describe '.validate!' do
    it 'does not raise when settings are valid' do
      Legion::Settings.merge_settings('valid', { name: 'test', count: 5 })
      expect { Legion::Settings.validate! }.not_to raise_error
    end

    it 'raises ValidationError with all collected errors' do
      Legion::Settings.set_prop(:badmod, { host: 42 })
      Legion::Settings.merge_settings('badmod', { host: 'localhost' })
      expect { Legion::Settings.validate! }.to raise_error(Legion::Settings::ValidationError) do |e|
        expect(e.errors.length).to be >= 1
      end
    end
  end

  describe '.errors' do
    it 'returns the loader errors array' do
      Legion::Settings.merge_settings('clean', { flag: true })
      expect(Legion::Settings.errors).to be_an(Array)
    end
  end
end

RSpec.describe 'DNS bootstrap override behavior' do
  let(:loader) { Legion::Settings::Loader.new }
  let(:cache_dir) { Dir.mktmpdir('legion_dns_override_test') }
  let(:local_dir) { Dir.mktmpdir('legion_local_test') }

  after do
    FileUtils.rm_rf(cache_dir)
    FileUtils.rm_rf(local_dir)
  end

  it 'local files override DNS bootstrap values' do
    # Seed DNS cache with transport host
    cache_file = File.join(cache_dir, '_dns_bootstrap.json')
    File.write(cache_file,
               '{"transport":{"host":"dns.example.com","port":5672},"_dns_bootstrap_meta":{"fetched_at":"2026-01-01T00:00:00Z","hostname":"test","url":"https://test"}}')

    # Create local override file
    File.write(File.join(local_dir, 'transport.json'), '{"transport":{"host":"local.example.com"}}')

    # Load in correct order: DNS bootstrap first, then local dir
    loader.load_dns_bootstrap(cache_dir: cache_dir)
    loader.load_directory(local_dir)

    # Local wins on host, DNS provides port
    expect(loader[:transport][:host]).to eq('local.example.com')
    expect(loader[:transport][:port]).to eq(5672)
  end

  it 'DNS bootstrap values remain when no local override exists' do
    cache_file = File.join(cache_dir, '_dns_bootstrap.json')
    File.write(cache_file, '{"transport":{"host":"dns.example.com"},"_dns_bootstrap_meta":{"fetched_at":"2026-01-01T00:00:00Z","hostname":"test","url":"https://test"}}')

    loader.load_dns_bootstrap(cache_dir: cache_dir)
    expect(loader[:transport][:host]).to eq('dns.example.com')
  end
end
