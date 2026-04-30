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

    it 'resolves :ext_name alias to :extension' do
      result = described_class.normalize_tool('t', { ext_name: 'lex-ollama' })
      expect(result[:extension]).to eq('lex-ollama')
      expect(result).not_to have_key(:ext_name)
    end

    it 'resolves :runner_snake alias to :runner' do
      result = described_class.normalize_tool('t', { runner_snake: 'ollama_inference' })
      expect(result[:runner]).to eq('ollama_inference')
      expect(result).not_to have_key(:runner_snake)
    end

    it 'prefers :extension over :ext_name' do
      result = described_class.normalize_tool('t', { extension: 'canonical', ext_name: 'alias' })
      expect(result[:extension]).to eq('canonical')
    end

    it 'preserves extra fields not in canonical shape' do
      result = described_class.normalize_tool('t', {
                                                description: 'test',
                                                confidence:  0.9,
                                                custom_flag: true
                                              })
      expect(result[:description]).to eq('test')
      expect(result[:confidence]).to eq(0.9)
      expect(result[:custom_flag]).to be true
    end

    it 'canonical fields override extra fields with same key' do
      result = described_class.normalize_tool('t', { name: 'should-be-overridden', deferred: true })
      expect(result[:name]).to eq('t')
      expect(result[:deferred]).to be true
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

    it 'preserves extra runner fields' do
      result = described_class.normalize_runner('r', {
                                                  extension:     'lex-ollama',
                                                  class_methods: { chat: { args: [:message] } },
                                                  trigger_words: %w[ollama chat]
                                                })
      expect(result[:extension]).to eq('lex-ollama')
      expect(result[:class_methods]).to eq({ chat: { args: [:message] } })
      expect(result[:trigger_words]).to eq(%w[ollama chat])
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

    it 'includes description field' do
      result = described_class.normalize_extension('lex-ollama', { description: 'Ollama provider' })
      expect(result[:description]).to eq('Ollama provider')
    end

    it 'preserves HandleRegistry fields' do
      result = described_class.normalize_extension('lex-ollama', {
                                                     state:                    :running,
                                                     gem_name:                 'lex-ollama',
                                                     active_version:           '0.3.10',
                                                     latest_installed_version: '0.3.11',
                                                     reload_state:             :idle,
                                                     hot_reloadable:           true,
                                                     gem_dir:                  '/path/to/gem',
                                                     loaded_at:                Time.now,
                                                     actors:                   [:subscription],
                                                     tools:                    ['legion.ollama_chat']
                                                   })
      expect(result[:state]).to eq(:running)
      expect(result[:gem_name]).to eq('lex-ollama')
      expect(result[:active_version]).to eq('0.3.10')
      expect(result[:latest_installed_version]).to eq('0.3.11')
      expect(result[:reload_state]).to eq(:idle)
      expect(result[:hot_reloadable]).to be true
      expect(result[:gem_dir]).to eq('/path/to/gem')
      expect(result[:loaded_at]).to be_a(Time)
      expect(result[:actors]).to eq([:subscription])
      expect(result[:tools]).to eq(['legion.ollama_chat'])
    end

    it 'preserves Governance fields' do
      result = described_class.normalize_extension('lex-ollama', {
                                                     risk_tier:   'low',
                                                     airb_status: 'approved',
                                                     permissions: ['read'],
                                                     author:      'Esity',
                                                     checksum:    'sha256:abc'
                                                   })
      expect(result[:risk_tier]).to eq('low')
      expect(result[:airb_status]).to eq('approved')
      expect(result[:permissions]).to eq(['read'])
      expect(result[:author]).to eq('Esity')
      expect(result[:checksum]).to eq('sha256:abc')
    end
  end
end
