# frozen_string_literal: true

require 'spec_helper'
require 'legion/settings/schema'

RSpec.describe Legion::Settings::Schema do
  subject(:schema) { described_class.new }

  describe '#register' do
    it 'infers string type from string defaults' do
      schema.register(:transport, { connection: { host: '127.0.0.1' } })
      constraint = schema.constraint(:transport, %i[connection host])
      expect(constraint[:type]).to eq(:string)
    end

    it 'infers integer type from integer defaults' do
      schema.register(:transport, { connection: { port: 5672 } })
      constraint = schema.constraint(:transport, %i[connection port])
      expect(constraint[:type]).to eq(:integer)
    end

    it 'infers boolean type from true' do
      schema.register(:cache, { enabled: true })
      constraint = schema.constraint(:cache, [:enabled])
      expect(constraint[:type]).to eq(:boolean)
    end

    it 'infers boolean type from false' do
      schema.register(:cache, { connected: false })
      constraint = schema.constraint(:cache, [:connected])
      expect(constraint[:type]).to eq(:boolean)
    end

    it 'infers any type from nil' do
      schema.register(:crypt, { cluster_secret: nil })
      constraint = schema.constraint(:crypt, [:cluster_secret])
      expect(constraint[:type]).to eq(:any)
    end

    it 'infers hash type from empty hash' do
      schema.register(:cluster, { public_keys: {} })
      constraint = schema.constraint(:cluster, [:public_keys])
      expect(constraint[:type]).to eq(:hash)
    end

    it 'infers float type from float defaults' do
      schema.register(:metrics, { threshold: 3.14 })
      constraint = schema.constraint(:metrics, [:threshold])
      expect(constraint[:type]).to eq(:float)
    end

    it 'infers array type from empty array' do
      schema.register(:test, { items: [] })
      constraint = schema.constraint(:test, [:items])
      expect(constraint[:type]).to eq(:array)
    end

    it 'recurses into nested hashes' do
      schema.register(:transport, { connection: { host: 'localhost', port: 5672 } })
      expect(schema.constraint(:transport, %i[connection host])[:type]).to eq(:string)
      expect(schema.constraint(:transport, %i[connection port])[:type]).to eq(:integer)
    end

    it 'tracks registered module names' do
      schema.register(:transport, { connected: false })
      schema.register(:cache, { enabled: true })
      expect(schema.registered_modules).to contain_exactly(:transport, :cache)
    end
  end

  describe '#schema_for' do
    it 'returns the schema for a registered module' do
      schema.register(:transport, { connection: { host: 'localhost' } })
      result = schema.schema_for(:transport)
      expect(result).to be_a(Hash)
      expect(result.key?(:connection)).to be true
    end

    it 'returns nil for a nonexistent module' do
      expect(schema.schema_for(:nonexistent)).to be_nil
    end
  end

  describe '#define_override' do
    it 'overrides inferred type for a nil default' do
      schema.register(:crypt, { cluster_secret: nil })
      schema.define_override(:crypt, { cluster_secret: { type: :string, required: true } })
      constraint = schema.constraint(:crypt, [:cluster_secret])
      expect(constraint[:type]).to eq(:string)
      expect(constraint[:required]).to eq(true)
    end

    it 'adds enum constraint' do
      schema.register(:cache, { driver: 'dalli' })
      schema.define_override(:cache, { driver: { enum: %w[dalli redis] } })
      constraint = schema.constraint(:cache, [:driver])
      expect(constraint[:enum]).to eq(%w[dalli redis])
    end

    it 'recurses into nested overrides without :type/:required/:enum keys' do
      schema.register(:transport, { connection: { host: 'localhost', port: 5672 } })
      schema.define_override(:transport, { connection: { host: { type: :string, required: true } } })
      constraint = schema.constraint(:transport, %i[connection host])
      expect(constraint[:type]).to eq(:string)
      expect(constraint[:required]).to eq(true)
    end

    it 'merges directly when override has :type key' do
      schema.register(:cache, { driver: 'dalli' })
      schema.define_override(:cache, { driver: { type: :string, required: true } })
      constraint = schema.constraint(:cache, [:driver])
      expect(constraint[:type]).to eq(:string)
      expect(constraint[:required]).to eq(true)
    end
  end

  describe '#validate_module' do
    it 'returns no errors for valid settings' do
      schema.register(:cache, { driver: 'dalli', enabled: true, port: 11_211 })
      errors = schema.validate_module(:cache, { driver: 'redis', enabled: false, port: 11_211 })
      expect(errors).to be_empty
    end

    it 'returns error for wrong type' do
      schema.register(:transport, { connection: { host: '127.0.0.1' } })
      errors = schema.validate_module(:transport, { connection: { host: 42 } })
      expect(errors.length).to eq(1)
      expect(errors.first[:path]).to eq('connection.host')
      expect(errors.first[:message]).to include('expected String')
    end

    it 'skips validation for :any type' do
      schema.register(:crypt, { cluster_secret: nil })
      errors = schema.validate_module(:crypt, { cluster_secret: 'some_secret' })
      expect(errors).to be_empty
    end

    it 'validates enum constraints' do
      schema.register(:cache, { driver: 'dalli' })
      schema.define_override(:cache, { driver: { enum: %w[dalli redis] } })
      errors = schema.validate_module(:cache, { driver: 'memcache' })
      expect(errors.length).to eq(1)
      expect(errors.first[:message]).to include('one of')
    end

    it 'validates required constraint' do
      schema.register(:crypt, { cluster_secret: nil })
      schema.define_override(:crypt, { cluster_secret: { type: :string, required: true } })
      errors = schema.validate_module(:crypt, { cluster_secret: nil })
      expect(errors.length).to eq(1)
      expect(errors.first[:message]).to include('required')
    end

    it 'passes float validation for Float value' do
      schema.register(:metrics, { threshold: 3.14 })
      errors = schema.validate_module(:metrics, { threshold: 2.71 })
      expect(errors).to be_empty
    end

    it 'passes float validation for Integer value' do
      schema.register(:metrics, { threshold: 3.14 })
      errors = schema.validate_module(:metrics, { threshold: 5 })
      expect(errors).to be_empty
    end

    it 'fails float validation for String value' do
      schema.register(:metrics, { threshold: 3.14 })
      errors = schema.validate_module(:metrics, { threshold: 'high' })
      expect(errors.length).to eq(1)
      expect(errors.first[:message]).to include('expected Float')
    end

    it 'passes boolean validation for true and false' do
      schema.register(:cache, { enabled: true })
      expect(schema.validate_module(:cache, { enabled: true })).to be_empty
      expect(schema.validate_module(:cache, { enabled: false })).to be_empty
    end

    it 'fails boolean validation for String value' do
      schema.register(:cache, { enabled: true })
      errors = schema.validate_module(:cache, { enabled: 'yes' })
      expect(errors.length).to eq(1)
      expect(errors.first[:message]).to include('expected Boolean')
    end

    it 'passes hash validation for Hash value' do
      schema.register(:cluster, { public_keys: {} })
      errors = schema.validate_module(:cluster, { public_keys: { node1: 'abc' } })
      expect(errors).to be_empty
    end

    it 'fails hash validation for String value' do
      schema.register(:cluster, { public_keys: {} })
      errors = schema.validate_module(:cluster, { public_keys: 'not_a_hash' })
      expect(errors.length).to eq(1)
      expect(errors.first[:message]).to include('expected Hash')
    end

    it 'includes type name and actual class in type mismatch error' do
      schema.register(:transport, { connection: { port: 5672 } })
      errors = schema.validate_module(:transport, { connection: { port: 'bad' } })
      expect(errors.first[:message]).to match(/expected Integer, got String/)
    end

    it 'allows nil for non-required fields regardless of type' do
      schema.register(:transport, { connection: { host: '127.0.0.1' } })
      errors = schema.validate_module(:transport, { connection: { host: nil } })
      expect(errors).to be_empty
    end

    it 'recurses into nested hashes' do
      schema.register(:transport, { connection: { host: '127.0.0.1', port: 5672 } })
      errors = schema.validate_module(:transport, { connection: { host: 42, port: 'bad' } })
      expect(errors.length).to eq(2)
    end

    it 'fails when a nested hash-shaped branch is replaced with a scalar' do
      schema.register(:transport, { connection: { host: '127.0.0.1', port: 5672 } })
      errors = schema.validate_module(:transport, { connection: 'oops' })
      expect(errors.length).to eq(1)
      expect(errors.first[:path]).to eq('connection')
      expect(errors.first[:message]).to include('expected Hash')
    end
  end

  describe '#detect_unknown_keys' do
    before do
      schema.register(:transport, { connected: false })
      schema.register(:cache, { enabled: true })
    end

    it 'returns no warnings for known keys' do
      settings = { transport: { connected: true }, cache: { enabled: false } }
      warnings = schema.detect_unknown_keys(settings)
      expect(warnings).to be_empty
    end

    it 'warns about unknown top-level keys' do
      settings = { transport: {}, cache: {}, trasport: {} }
      warnings = schema.detect_unknown_keys(settings)
      expect(warnings.length).to eq(1)
      expect(warnings.first[:message]).to include('trasport')
    end

    it 'suggests corrections for typos within edit distance 2' do
      settings = { transport: {}, cache: {}, tansport: {} }
      warnings = schema.detect_unknown_keys(settings)
      expect(warnings.first[:message]).to include('did you mean')
    end

    it 'skips keys listed in known_defaults' do
      settings = { transport: {}, client: {}, extensions: {} }
      warnings = schema.detect_unknown_keys(settings, known_defaults: %i[client extensions])
      expect(warnings).to be_empty
    end

    it 'warns about unknown first-level keys within a module' do
      schema.register(:cache, { driver: 'dalli', enabled: true })
      settings = { cache: { driver: 'dalli', enbled: true } }
      warnings = schema.detect_unknown_keys(settings)
      expect(warnings.length).to eq(1)
      expect(warnings.first[:path]).to eq('cache.enbled')
    end
  end
end
