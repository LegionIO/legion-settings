# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Settings::Extensions::Normalizer do
  describe '.normalize_tool' do
    it 'produces canonical shape from full metadata' do
      tool_class = Class.new
      result = described_class.normalize_tool('legion.read_file', {
                                                description:   'Read a file',
                                                input_schema:  { type: 'object', properties: { path: { type: 'string' } } },
                                                tool_class:    tool_class,
                                                extension:     'lex-ollama',
                                                runner:        'ollama/inference',
                                                function:      'chat',
                                                deferred:      false,
                                                sticky:        true,
                                                mcp_tier:      0,
                                                mcp_category:  'inference',
                                                trigger_words: %w[read file],
                                                tags:          %w[filesystem io],
                                                source:        :discovery
                                              })

      expect(result[:name]).to eq('legion.read_file')
      expect(result[:description]).to eq('Read a file')
      expect(result[:input_schema]).to eq({ type: 'object', properties: { path: { type: 'string' } } })
      expect(result[:tool_class]).to eq(tool_class)
      expect(result[:extension]).to eq('lex-ollama')
      expect(result[:runner]).to eq('ollama/inference')
      expect(result[:function]).to eq('chat')
      expect(result[:deferred]).to be false
      expect(result[:sticky]).to be true
      expect(result[:mcp_tier]).to eq(0)
      expect(result[:mcp_category]).to eq('inference')
      expect(result[:trigger_words]).to eq(%w[read file])
      expect(result[:tags]).to eq(%w[filesystem io])
      expect(result[:source]).to eq(:discovery)
    end

    it 'fills defaults for missing fields' do
      result = described_class.normalize_tool('minimal', {})

      expect(result[:name]).to eq('minimal')
      expect(result[:description]).to be_nil
      expect(result[:input_schema]).to eq({})
      expect(result[:tool_class]).to be_nil
      expect(result[:dispatch_type]).to eq(:none)
      expect(result[:deferred]).to be false
      expect(result[:sticky]).to be true
      expect(result[:trigger_words]).to eq([])
      expect(result[:tags]).to eq([])
      expect(result[:source]).to eq(:unknown)
    end

    it 'reads :parameters when :input_schema is absent' do
      result = described_class.normalize_tool('t', {
                                                parameters: { type: 'object', properties: { q: { type: 'string' } } }
                                              })
      expect(result[:input_schema]).to eq({ type: 'object', properties: { q: { type: 'string' } } })
    end

    it 'reads :params_schema when both :input_schema and :parameters are absent' do
      result = described_class.normalize_tool('t', {
                                                params_schema: { type: 'object', properties: {} }
                                              })
      expect(result[:input_schema]).to eq({ type: 'object', properties: {} })
    end

    it 'prefers :input_schema over :parameters' do
      result = described_class.normalize_tool('t', {
                                                input_schema: { preferred: true },
                                                parameters:   { fallback: true }
                                              })
      expect(result[:input_schema]).to eq({ preferred: true })
    end
  end

  describe '.resolve_dispatch_type' do
    it 'returns :class_call for a class with .call' do
      tool = Class.new do
        def self.call(**); end
      end
      expect(described_class.resolve_dispatch_type({ tool_class: tool })).to eq(:class_call)
    end

    it 'returns :instance for a class with #execute' do
      tool = Class.new do
        def execute(**); end
      end
      expect(described_class.resolve_dispatch_type({ tool_class: tool })).to eq(:instance)
    end

    it 'returns :runner when tool_class is nil but extension and function are present' do
      expect(described_class.resolve_dispatch_type({
                                                     extension: 'lex-ollama', function: 'chat'
                                                   })).to eq(:runner)
    end

    it 'returns :none when tool_class is nil and no runner info' do
      expect(described_class.resolve_dispatch_type({})).to eq(:none)
    end

    it 'respects explicit dispatch_type' do
      expect(described_class.resolve_dispatch_type({
                                                     dispatch_type: 'custom', tool_class: Class.new
                                                   })).to eq(:custom)
    end
  end

  describe '.normalize_runner' do
    it 'produces canonical shape' do
      result = described_class.normalize_runner('ollama/inference/chat', {
                                                  extension:     'lex-ollama',
                                                  runner_module: 'Legion::Extensions::Ollama::Runners::Inference',
                                                  function:      'chat',
                                                  exposed:       true
                                                })

      expect(result[:name]).to eq('ollama/inference/chat')
      expect(result[:extension]).to eq('lex-ollama')
      expect(result[:runner_module]).to eq('Legion::Extensions::Ollama::Runners::Inference')
      expect(result[:function]).to eq('chat')
      expect(result[:exposed]).to be true
    end

    it 'defaults exposed to true' do
      result = described_class.normalize_runner('r', {})
      expect(result[:exposed]).to be true
    end
  end

  describe '.normalize_extension' do
    it 'produces canonical shape' do
      result = described_class.normalize_extension('lex-ollama', {
                                                     version:    '0.3.10',
                                                     state:      :loaded,
                                                     category:   :ai,
                                                     tier:       1,
                                                     phase:      1,
                                                     const_path: 'Legion::Extensions::Ollama',
                                                     runners:    %w[ollama/inference ollama/embedding]
                                                   })

      expect(result[:name]).to eq('lex-ollama')
      expect(result[:version]).to eq('0.3.10')
      expect(result[:state]).to eq(:loaded)
      expect(result[:category]).to eq(:ai)
      expect(result[:runners]).to eq(%w[ollama/inference ollama/embedding])
    end

    it 'defaults state to :discovered' do
      result = described_class.normalize_extension('lex-x', {})
      expect(result[:state]).to eq(:discovered)
      expect(result[:runners]).to eq([])
    end
  end
end
