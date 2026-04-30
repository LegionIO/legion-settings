# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Settings::Extensions::Filter do
  let(:extension_store) { Legion::Settings::Extensions::Store.new }

  def tool_entry(name, **overrides)
    {
      name:         name,
      extension:    'lex-ollama',
      deferred:     false,
      sticky:       true,
      mcp_tier:     0,
      mcp_category: 'inference',
      tags:         %w[ai inference],
      source:       :discovery
    }.merge(overrides)
  end

  def ext_entry(name, **overrides)
    { name: name, state: :running, category: :ai, phase: 1 }.merge(overrides)
  end

  describe '.apply_tool_filters' do
    let(:tools) do
      [
        tool_entry('chat', extension: 'lex-ollama', deferred: false, sticky: true, mcp_tier: 0,
                           mcp_category: 'inference', tags: %w[ai inference], source: :discovery),
        tool_entry('embed', extension: 'lex-ollama', deferred: true, sticky: false, mcp_tier: 1,
                            mcp_category: 'embedding', tags: %w[ai embedding], source: :discovery),
        tool_entry('invoke', extension: 'lex-bedrock', deferred: false, sticky: false, mcp_tier: 0,
                             mcp_category: 'inference', tags: %w[ai cloud], source: :manual)
      ]
    end

    it 'returns all entries with no criteria' do
      expect(described_class.apply_tool_filters(tools, {}).size).to eq(3)
    end

    it 'filters by extension' do
      result = described_class.apply_tool_filters(tools, { extension: 'lex-ollama' })
      expect(result.size).to eq(2)
    end

    it 'filters by deferred' do
      result = described_class.apply_tool_filters(tools, { deferred: true })
      expect(result.size).to eq(1)
      expect(result.first[:name]).to eq('embed')
    end

    it 'filters by sticky' do
      result = described_class.apply_tool_filters(tools, { sticky: true })
      expect(result.size).to eq(1)
      expect(result.first[:name]).to eq('chat')
    end

    it 'filters by mcp_tier' do
      result = described_class.apply_tool_filters(tools, { mcp_tier: 0 })
      expect(result.size).to eq(2)
    end

    it 'filters by category (mcp_category)' do
      result = described_class.apply_tool_filters(tools, { category: 'embedding' })
      expect(result.size).to eq(1)
    end

    it 'filters by source' do
      result = described_class.apply_tool_filters(tools, { source: :manual })
      expect(result.size).to eq(1)
      expect(result.first[:name]).to eq('invoke')
    end

    it 'filters by tags (match any)' do
      result = described_class.apply_tool_filters(tools, { tags: ['cloud'] })
      expect(result.size).to eq(1)
      expect(result.first[:name]).to eq('invoke')
    end

    it 'filters by tags with multiple matches' do
      result = described_class.apply_tool_filters(tools, { tags: %w[cloud embedding] })
      expect(result.size).to eq(2)
    end

    it 'filters by extension state when extension_store provided' do
      extension_store.register('lex-ollama', state: :running, category: :ai)
      extension_store.register('lex-bedrock', state: :loaded, category: :ai)
      result = described_class.apply_tool_filters(tools, { state: :running }, extension_store: extension_store)
      expect(result.size).to eq(2)
      expect(result.map { |t| t[:extension] }).to all(eq('lex-ollama'))
    end

    it 'combines multiple criteria' do
      result = described_class.apply_tool_filters(tools, { extension: 'lex-ollama', deferred: false })
      expect(result.size).to eq(1)
      expect(result.first[:name]).to eq('chat')
    end

    it 'does not mutate the original entries' do
      original_size = tools.size
      described_class.apply_tool_filters(tools, { extension: 'lex-ollama' })
      expect(tools.size).to eq(original_size)
    end
  end

  describe '.apply_extension_filters' do
    let(:extensions) do
      [
        ext_entry('lex-ollama', state: :running, category: :ai, phase: 1),
        ext_entry('lex-node', state: :running, category: :core, phase: 0),
        ext_entry('lex-broken', state: :stopped, category: :ai, phase: 1)
      ]
    end

    it 'filters by state' do
      result = described_class.apply_extension_filters(extensions, { state: :running })
      expect(result.size).to eq(2)
    end

    it 'filters by category' do
      result = described_class.apply_extension_filters(extensions, { category: :ai })
      expect(result.size).to eq(2)
    end

    it 'filters by phase' do
      result = described_class.apply_extension_filters(extensions, { phase: 0 })
      expect(result.size).to eq(1)
      expect(result.first[:name]).to eq('lex-node')
    end

    it 'combines multiple criteria' do
      result = described_class.apply_extension_filters(extensions, { state: :running, category: :ai })
      expect(result.size).to eq(1)
      expect(result.first[:name]).to eq('lex-ollama')
    end

    it 'does not mutate the original entries' do
      original_size = extensions.size
      described_class.apply_extension_filters(extensions, { state: :stopped })
      expect(extensions.size).to eq(original_size)
    end
  end
end
