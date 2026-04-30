# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Settings::Extensions::Store do
  subject(:store) { described_class.new }

  describe '#register' do
    it 'stores an entry and returns a frozen copy' do
      result = store.register('lex-ollama', version: '0.3.10')
      expect(result).to be_frozen
      expect(result[:name]).to eq('lex-ollama')
      expect(result[:version]).to eq('0.3.10')
      expect(result[:registered_at]).to be_a(Time)
    end

    it 'canonical fields override caller metadata' do
      result = store.register('lex-ollama', name: 'should-be-overridden')
      expect(result[:name]).to eq('lex-ollama')
    end

    it 'overwrites on duplicate registration' do
      store.register('lex-ollama', state: :discovered)
      store.register('lex-ollama', state: :loaded)
      expect(store.all.size).to eq(1)
      expect(store.find('lex-ollama')[:state]).to eq(:loaded)
    end

    it 'normalizes symbol keys to strings' do
      store.register(:lex_ollama, tier: 1)
      expect(store.find('lex_ollama')).not_to be_nil
      expect(store.find(:lex_ollama)).not_to be_nil
    end
  end

  describe '#find' do
    it 'returns a frozen duplicate of the entry' do
      store.register('lex-ollama', state: :running)
      found = store.find('lex-ollama')
      expect(found).to be_frozen
      expect(found[:state]).to eq(:running)
    end

    it 'returns nil for unknown entries' do
      expect(store.find('nonexistent')).to be_nil
    end
  end

  describe '#all' do
    it 'returns a frozen array of frozen hashes' do
      store.register('a', {})
      store.register('b', {})
      result = store.all
      expect(result).to be_frozen
      expect(result.size).to eq(2)
      result.each { |entry| expect(entry).to be_frozen }
    end

    it 'returns empty array when store is empty' do
      expect(store.all).to eq([])
    end
  end

  describe '#update' do
    it 'merges new fields into an existing entry' do
      store.register('lex-ollama', state: :discovered)
      store.update('lex-ollama', state: :loaded, runners: %w[a b])
      found = store.find('lex-ollama')
      expect(found[:state]).to eq(:loaded)
      expect(found[:runners]).to eq(%w[a b])
      expect(found[:updated_at]).to be_a(Time)
    end

    it 'returns nil for unknown entries' do
      expect(store.update('nonexistent', state: :loaded)).to be_nil
    end

    it 'preserves existing fields not in the update' do
      store.register('lex-ollama', state: :discovered, version: '1.0')
      store.update('lex-ollama', state: :loaded)
      expect(store.find('lex-ollama')[:version]).to eq('1.0')
    end
  end

  describe '#delete' do
    it 'removes the entry and returns it' do
      store.register('lex-ollama', state: :running)
      removed = store.delete('lex-ollama')
      expect(removed[:name]).to eq('lex-ollama')
      expect(store.find('lex-ollama')).to be_nil
    end

    it 'returns nil for unknown entries' do
      expect(store.delete('nonexistent')).to be_nil
    end
  end

  describe '#delete_where' do
    it 'removes entries matching the block' do
      store.register('a', extension: 'lex-ollama')
      store.register('b', extension: 'lex-ollama')
      store.register('c', extension: 'lex-bedrock')
      store.delete_where { |v| v[:extension] == 'lex-ollama' }
      expect(store.size).to eq(1)
      expect(store.find('c')).not_to be_nil
    end
  end

  describe '#size and #any?' do
    it 'reports correct size' do
      expect(store.size).to eq(0)
      expect(store.any?).to be false
      store.register('a', {})
      expect(store.size).to eq(1)
      expect(store.any?).to be true
    end
  end

  describe '#clear' do
    it 'removes all entries' do
      store.register('a', {})
      store.register('b', {})
      store.clear
      expect(store.size).to eq(0)
    end
  end

  describe 'thread safety' do
    it 'handles concurrent registration' do
      threads = 20.times.map do |i|
        Thread.new { store.register("entry-#{i}", index: i) }
      end
      threads.each(&:value)
      expect(store.size).to eq(20)
    end

    it 'handles concurrent reads and writes' do
      5.times { |i| store.register("pre-#{i}", index: i) }
      writers = 10.times.map { |i| Thread.new { store.register("write-#{i}", index: i) } }
      readers = 10.times.map do
        Thread.new do
          store.all
          store.find('pre-0')
        end
      end
      (writers + readers).each(&:value)
      expect(store.size).to eq(15)
    end
  end
end
