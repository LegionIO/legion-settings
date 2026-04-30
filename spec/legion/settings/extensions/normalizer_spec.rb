# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Settings::Extensions::Normalizer do
  describe '.normalize_tool' do
    it 'produces complete shape from full metadata' do
      tool_class = Class.new
      result = described_class.normalize_tool('legion.read_file', {
                                                description:   'Read a file',
                                                input_schema:  { type: 'object', properties: { path: { type: 'string' } } },
                                                tool_class:    tool_class,
                                                extension:     'lex-github',
                                                runner:        'github/repos',
                                                function:      'chat',
                                                deferred:      false,
                                                sticky:        true,
                                                mcp_tier:      0,
                                                mcp_category:  'inference',
                                                trigger_words: %w[read file],
                                                tags:          %w[filesystem io],
                                                source:        :discovery,
                                                confidence:    0.95,
                                                hit_count:     10,
                                                miss_count:    1
                                              })

      expect(result[:name]).to eq('legion.read_file')
      expect(result[:description]).to eq('Read a file')
      expect(result[:input_schema]).to eq({ type: 'object', properties: { path: { type: 'string' } } })
      expect(result[:tool_class]).to eq(tool_class)
      expect(result[:extension]).to eq('lex-github')
      expect(result[:runner]).to eq('github/repos')
      expect(result[:function]).to eq('chat')
      expect(result[:deferred]).to be false
      expect(result[:sticky]).to be true
      expect(result[:mcp_tier]).to eq(0)
      expect(result[:mcp_category]).to eq('inference')
      expect(result[:trigger_words]).to eq(%w[read file])
      expect(result[:tags]).to eq(%w[filesystem io])
      expect(result[:source]).to eq(:discovery)
      expect(result[:confidence]).to eq(0.95)
      expect(result[:hit_count]).to eq(10)
      expect(result[:miss_count]).to eq(1)
    end

    it 'fills defaults for missing fields' do
      result = described_class.normalize_tool('minimal', {})

      expect(result[:name]).to eq('minimal')
      expect(result[:description]).to be_nil
      expect(result[:input_schema]).to eq({})
      expect(result[:tool_class]).to be_nil
      expect(result[:dispatch_type]).to eq(:none)
      expect(result[:extension]).to be_nil
      expect(result[:runner]).to be_nil
      expect(result[:function]).to be_nil
      expect(result[:deferred]).to be false
      expect(result[:sticky]).to be true
      expect(result[:mcp_tier]).to be_nil
      expect(result[:mcp_category]).to be_nil
      expect(result[:trigger_words]).to eq([])
      expect(result[:tags]).to eq([])
      expect(result[:source]).to eq(:unknown)
      expect(result[:confidence]).to be_nil
      expect(result[:hit_count]).to be_nil
      expect(result[:miss_count]).to be_nil
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
      result = described_class.normalize_tool('t', { ext_name: 'lex-github' })
      expect(result[:extension]).to eq('lex-github')
    end

    it 'resolves :runner_snake alias to :runner' do
      result = described_class.normalize_tool('t', { runner_snake: 'github_repos' })
      expect(result[:runner]).to eq('github_repos')
    end

    it 'prefers :extension over :ext_name' do
      result = described_class.normalize_tool('t', { extension: 'canonical', ext_name: 'alias' })
      expect(result[:extension]).to eq('canonical')
    end

    it 'does not include unknown extra fields' do
      result = described_class.normalize_tool('t', { unknown_field: 'value' })
      expect(result).not_to have_key(:unknown_field)
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
                                                     extension: 'lex-github', function: 'chat'
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
    it 'produces complete shape' do
      result = described_class.normalize_runner('github/repos/list', {
                                                  extension:     'lex-github',
                                                  runner_module: 'Legion::Extensions::Github::Runners::Repos',
                                                  function:      'chat',
                                                  exposed:       true,
                                                  functions:     { chat: { args: %i[message model], desc: 'Chat' } },
                                                  trigger_words: %w[github repos],
                                                  mcp_tools:     true,
                                                  mcp_deferred:  false
                                                })

      expect(result[:name]).to eq('github/repos/list')
      expect(result[:extension]).to eq('lex-github')
      expect(result[:runner_module]).to eq('Legion::Extensions::Github::Runners::Repos')
      expect(result[:function]).to eq('chat')
      expect(result[:exposed]).to be true
      expect(result[:functions]).to eq({ chat: { args: %i[message model], desc: 'Chat' } })
      expect(result[:trigger_words]).to eq(%w[github repos])
      expect(result[:mcp_tools]).to be true
      expect(result[:mcp_deferred]).to be false
    end

    it 'defaults exposed to true' do
      result = described_class.normalize_runner('r', {})
      expect(result[:exposed]).to be true
      expect(result[:functions]).to eq({})
      expect(result[:trigger_words]).to eq([])
    end

    it 'reads :class_methods as alias for :functions' do
      result = described_class.normalize_runner('r', {
                                                  class_methods: { chat: { args: [:msg] } }
                                                })
      expect(result[:functions]).to eq({ chat: { args: [:msg] } })
    end
  end

  describe '.normalize_extension' do
    it 'produces complete shape' do
      now = Time.now
      result = described_class.normalize_extension('lex-github', {
                                                     version:                  '0.3.10',
                                                     state:                    :running,
                                                     category:                 :ai,
                                                     tier:                     1,
                                                     phase:                    1,
                                                     const_path:               'Legion::Extensions::Github',
                                                     runners:                  %w[github/repos github/pulls],
                                                     description:              'GitHub integration provider',
                                                     gem_name:                 'lex-github',
                                                     gem_dir:                  '/path/to/gem',
                                                     active_version:           '0.3.10',
                                                     latest_installed_version: '0.3.11',
                                                     loaded_at:                now,
                                                     reload_state:             :idle,
                                                     hot_reloadable:           true,
                                                     actors:                   [:subscription],
                                                     tools:                    ['legion.github_repos_list'],
                                                     absorbers:                [],
                                                     routes:                   ['/api/github'],
                                                     risk_tier:                'low',
                                                     airb_status:              'approved',
                                                     permissions:              ['read'],
                                                     author:                   'Esity',
                                                     checksum:                 'sha256:abc',
                                                     mcp_tools:                true,
                                                     mcp_tools_deferred:       false,
                                                     sticky_tools:             true
                                                   })

      # Identity + derived fields
      expect(result[:name]).to eq('lex-github')
      expect(result[:gem_name]).to eq('lex-github')
      expect(result[:description]).to eq('GitHub integration provider')
      expect(result[:version]).to eq('0.3.10')
      expect(result[:const_path]).to eq('Legion::Extensions::Github')
      expect(result[:segments]).to eq(['github'])
      expect(result[:lex_name]).to eq('github')
      expect(result[:lex_slug]).to eq('github')

      # Lifecycle
      expect(result[:state]).to eq(:running)
      expect(result[:loaded_at]).to eq(now)
      expect(result[:last_error]).to be_nil

      # Boot classification
      expect(result[:category]).to eq(:ai)
      expect(result[:tier]).to eq(1)
      expect(result[:phase]).to eq(1)

      # Contents
      expect(result[:runners]).to eq(%w[github/repos github/pulls])
      expect(result[:actors]).to eq([:subscription])
      expect(result[:tools]).to eq(['legion.github_repos_list'])
      expect(result[:absorbers]).to eq([])
      expect(result[:routes]).to eq(['/api/github'])

      # Gem metadata
      expect(result[:gem_dir]).to eq('/path/to/gem')
      expect(result[:active_version]).to eq('0.3.10')
      expect(result[:latest_installed_version]).to eq('0.3.11')

      # Reload
      expect(result[:reload_state]).to eq(:idle)
      expect(result[:hot_reloadable]).to be true

      # Governance
      expect(result[:risk_tier]).to eq('low')
      expect(result[:airb_status]).to eq('approved')
      expect(result[:permissions]).to eq(['read'])
      expect(result[:author]).to eq('Esity')
      expect(result[:checksum]).to eq('sha256:abc')

      # Tool defaults
      expect(result[:mcp_tools]).to be true
      expect(result[:mcp_tools_deferred]).to be false
      expect(result[:sticky_tools]).to be true
    end

    it 'fills defaults for minimal registration' do
      result = described_class.normalize_extension('lex-x', {})

      expect(result[:name]).to eq('lex-x')
      expect(result[:gem_name]).to eq('lex-x')
      expect(result[:state]).to eq(:discovered)
      expect(result[:runners]).to eq([])
      expect(result[:actors]).to eq([])
      expect(result[:tools]).to eq([])
      expect(result[:absorbers]).to eq([])
      expect(result[:routes]).to eq([])
      expect(result[:permissions]).to eq([])
      expect(result[:loaded_features]).to eq([])
      expect(result[:reload_state]).to eq(:idle)
      expect(result[:hot_reloadable]).to be false

      # Requirement flag defaults match Core module
      expect(result[:data_required]).to be false
      expect(result[:cache_required]).to be false
      expect(result[:transport_required]).to be true
      expect(result[:crypt_required]).to be false
      expect(result[:vault_required]).to be false
      expect(result[:llm_required]).to be false
      expect(result[:skills_required]).to be false
      expect(result[:remote_invocable]).to be true

      # Tool behavior defaults
      expect(result[:mcp_tools]).to be true
      expect(result[:mcp_tools_deferred]).to be true
      expect(result[:sticky_tools]).to be true

      # Derived identity
      expect(result[:segments]).to eq(['x'])
      expect(result[:lex_name]).to eq('x')
      expect(result[:lex_slug]).to eq('x')
    end

    it 'derives segments from multi-part gem names' do
      result = described_class.normalize_extension('lex-llm-openai', {})
      expect(result[:segments]).to eq(%w[llm openai])
      expect(result[:lex_name]).to eq('llm_openai')
      expect(result[:lex_slug]).to eq('llm.openai')
    end

    it 'preserves explicit segments when provided' do
      result = described_class.normalize_extension('lex-github', { segments: %w[custom path] })
      expect(result[:segments]).to eq(%w[custom path])
    end

    it 'handles lex-agentic-learning segments' do
      result = described_class.normalize_extension('lex-agentic-learning', { gem_name: 'lex-agentic-learning' })
      expect(result[:segments]).to eq(%w[agentic learning])
      expect(result[:lex_name]).to eq('agentic_learning')
    end

    it 'handles lex-llm-azure-foundry as three segments (dash = module boundary)' do
      result = described_class.normalize_extension('lex-llm-azure-foundry', { gem_name: 'lex-llm-azure-foundry' })
      expect(result[:segments]).to eq(%w[llm azure foundry])
      expect(result[:lex_name]).to eq('llm_azure_foundry')
      expect(result[:lex_slug]).to eq('llm.azure.foundry')
    end

    it 'handles lex-llm-azure_foundry as two segments (underscore = CamelCase)' do
      result = described_class.normalize_extension('lex-llm-azure_foundry', { gem_name: 'lex-llm-azure_foundry' })
      expect(result[:segments]).to eq(%w[llm azure_foundry])
      expect(result[:lex_name]).to eq('llm_azure_foundry')
      expect(result[:lex_slug]).to eq('llm.azure_foundry')
    end

    it 'handles lex-microsoft_teams underscore as single segment' do
      result = described_class.normalize_extension('lex-microsoft_teams', { gem_name: 'lex-microsoft_teams' })
      expect(result[:segments]).to eq(%w[microsoft_teams])
      expect(result[:lex_name]).to eq('microsoft_teams')
      expect(result[:lex_slug]).to eq('microsoft_teams')
    end

    it 'stores requirement flags from metadata' do
      result = described_class.normalize_extension('lex-data-heavy', {
                                                     data_required:  true,
                                                     cache_required: true,
                                                     llm_required:   true
                                                   })
      expect(result[:data_required]).to be true
      expect(result[:cache_required]).to be true
      expect(result[:llm_required]).to be true
      expect(result[:transport_required]).to be true
      expect(result[:vault_required]).to be false
    end
  end
end
