# frozen_string_literal: true

require 'spec_helper'
require 'legion/settings/schema'
require 'legion/settings/validation_error'

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

    it 'collects type errors on merge when user config conflicts' do
      Legion::Settings.set_prop(:mymodule, { port: 'not_a_number' })
      Legion::Settings.merge_settings('mymodule', { port: 8080 })
      expect(Legion::Settings.errors).not_to be_empty
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
