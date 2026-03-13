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
  end
end
