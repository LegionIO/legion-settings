# frozen_string_literal: true

require 'spec_helper'
require 'concurrent/hash'
require 'legion/settings/deep_merge'

RSpec.describe Legion::Settings::DeepMerge do
  describe '.deep_merge' do
    it 'merges nested hashes recursively' do
      base = { a: { b: 1, c: 2 } }
      override = { a: { c: 3, d: 4 } }
      result = described_class.deep_merge(base, override)
      expect(result[:a]).to eq(b: 1, c: 3, d: 4)
    end

    it 'concatenates arrays uniquely' do
      base = { tags: [1, 2, 3] }
      override = { tags: [3, 4, 5] }
      result = described_class.deep_merge(base, override)
      expect(result[:tags]).to contain_exactly(1, 2, 3, 4, 5)
    end

    it 'overwrites scalars' do
      base = { name: 'old' }
      override = { name: 'new' }
      result = described_class.deep_merge(base, override)
      expect(result[:name]).to eq('new')
    end

    it 'does not mutate the base hash' do
      base = { a: { b: 1 } }
      override = { a: { c: 2 } }
      described_class.deep_merge(base, override)
      expect(base[:a]).to eq(b: 1)
    end

    it 'preserves Concurrent::Hash type through merge' do
      base = Concurrent::Hash[a: 1, b: 2]
      override = { c: 3 }
      result = described_class.deep_merge(base, override)
      expect(result).to be_a(Concurrent::Hash)
      expect(result[:a]).to eq(1)
      expect(result[:c]).to eq(3)
    end

    it 'returns a plain Hash when base is a plain Hash' do
      base = { a: 1 }
      override = { b: 2 }
      result = described_class.deep_merge(base, override)
      expect(result).to be_a(Hash)
      expect(result).not_to be_a(Concurrent::Hash)
    end

    it 'handles empty hashes' do
      expect(described_class.deep_merge({}, { a: 1 })).to eq(a: 1)
      expect(described_class.deep_merge({ a: 1 }, {})).to eq(a: 1)
    end
  end

  describe '.deep_merge!' do
    it 'mutates the base hash in place' do
      base = { a: { b: 1 } }
      override = { a: { c: 2 } }
      described_class.deep_merge!(base, override)
      expect(base[:a]).to eq(b: 1, c: 2)
    end

    it 'overwrites scalars in place' do
      base = { name: 'old' }
      described_class.deep_merge!(base, { name: 'new' })
      expect(base[:name]).to eq('new')
    end

    it 'returns the mutated base hash' do
      base = { x: 1 }
      result = described_class.deep_merge!(base, { y: 2 })
      expect(result).to equal(base)
    end
  end
end
