# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Settings::Extensions do
  subject(:registry) { described_class }

  after { registry.reset! }

  # ----------------------------------------------------------------
  # Helpers
  # ----------------------------------------------------------------

  def sample_extension(name = 'lex-github', **overrides)
    {
      version:    '1.2.0',
      state:      :discovered,
      category:   :service,
      tier:       1,
      phase:      1,
      const_path: 'Legion::Extensions::Github',
      runners:    ['github/repos', 'github/pulls']
    }.merge(overrides).merge(name: name)
  end

  def sample_runner(name = 'github/repos/list', **overrides)
    {
      extension:     'lex-github',
      runner_module: 'Legion::Extensions::Github::Runners::Repos',
      function:      'list',
      exposed:       true
    }.merge(overrides).merge(name: name)
  end

  def sample_tool(name = 'legion.github_repos_list', **overrides)
    {
      extension:    'lex-github',
      runner:       'github/repos',
      function:     'list',
      description:  'List GitHub repositories',
      deferred:     false,
      sticky:       true,
      mcp_tier:     0,
      mcp_category: 'service',
      tags:         %w[scm service],
      source:       :discovery
    }.merge(overrides).merge(name: name)
  end

  # ================================================================
  # Registration
  # ================================================================

  describe 'extension registration' do
    it 'registers an extension and returns a frozen entry' do
      result = registry.register_extension('lex-github', sample_extension)
      expect(result).to be_frozen
      expect(result[:name]).to eq('lex-github')
      expect(result[:state]).to eq(:discovered)
      expect(result[:registered_at]).to be_a(Time)
    end

    it 'finds a registered extension by name' do
      registry.register_extension('lex-github', sample_extension)
      found = registry.find_extension('lex-github')
      expect(found).not_to be_nil
      expect(found[:name]).to eq('lex-github')
      expect(found[:category]).to eq(:service)
    end

    it 'returns nil for an unknown extension' do
      expect(registry.find_extension('nonexistent')).to be_nil
    end

    it 'lists all registered extensions' do
      registry.register_extension('lex-github', sample_extension)
      registry.register_extension('lex-bedrock', sample_extension('lex-bedrock', category: :ai))
      exts = registry.extensions
      expect(exts.size).to eq(2)
      expect(exts.map { |e| e[:name] }).to contain_exactly('lex-github', 'lex-bedrock')
    end

    it 'overwrites on duplicate registration without duplicating' do
      registry.register_extension('lex-github', sample_extension(state: :discovered))
      registry.register_extension('lex-github', sample_extension(state: :loaded))
      exts = registry.extensions
      expect(exts.size).to eq(1)
      expect(exts.first[:state]).to eq(:loaded)
    end

    it 'accepts symbol names and normalizes to string' do
      registry.register_extension(:lex_github, sample_extension)
      expect(registry.find_extension('lex_github')).not_to be_nil
      expect(registry.find_extension(:lex_github)).not_to be_nil
    end
  end

  # ================================================================
  # Runner registration
  # ================================================================

  describe 'runner registration' do
    it 'registers a runner and returns a frozen entry' do
      result = registry.register_runner('github/repos/list', sample_runner)
      expect(result).to be_frozen
      expect(result[:name]).to eq('github/repos/list')
      expect(result[:extension]).to eq('lex-github')
    end

    it 'finds a registered runner by name' do
      registry.register_runner('github/repos/list', sample_runner)
      found = registry.find_runner('github/repos/list')
      expect(found).not_to be_nil
      expect(found[:function]).to eq('list')
    end

    it 'returns nil for an unknown runner' do
      expect(registry.find_runner('nonexistent')).to be_nil
    end

    it 'lists all registered runners' do
      registry.register_runner('github/repos/list', sample_runner)
      registry.register_runner('github/pulls/create', sample_runner('github/pulls/create', function: 'embed'))
      rnrs = registry.runners
      expect(rnrs.size).to eq(2)
    end

    it 'overwrites on duplicate runner registration' do
      registry.register_runner('github/repos/list', sample_runner(exposed: true))
      registry.register_runner('github/repos/list', sample_runner(exposed: false))
      expect(registry.runners.size).to eq(1)
      expect(registry.find_runner('github/repos/list')[:exposed]).to be false
    end
  end

  # ================================================================
  # Tool registration
  # ================================================================

  describe 'tool registration' do
    it 'registers a tool and returns a frozen entry' do
      result = registry.register_tool('legion.github_repos_list', sample_tool)
      expect(result).to be_frozen
      expect(result[:name]).to eq('legion.github_repos_list')
      expect(result[:deferred]).to be false
    end

    it 'finds a registered tool by name' do
      registry.register_tool('legion.github_repos_list', sample_tool)
      found = registry.find_tool('legion.github_repos_list')
      expect(found).not_to be_nil
      expect(found[:description]).to eq('List GitHub repositories')
    end

    it 'returns nil for an unknown tool' do
      expect(registry.find_tool('nonexistent')).to be_nil
    end

    it 'lists all registered tools' do
      registry.register_tool('legion.github_repos_list', sample_tool)
      registry.register_tool('legion.bedrock_invoke', sample_tool('legion.bedrock_invoke', extension: 'lex-bedrock'))
      tls = registry.tools
      expect(tls.size).to eq(2)
    end

    it 'overwrites on duplicate tool registration' do
      registry.register_tool('legion.github_repos_list', sample_tool(deferred: false))
      registry.register_tool('legion.github_repos_list', sample_tool(deferred: true))
      expect(registry.tools.size).to eq(1)
      expect(registry.find_tool('legion.github_repos_list')[:deferred]).to be true
    end
  end

  # ================================================================
  # Transition
  # ================================================================

  describe '#transition' do
    before { registry.register_extension('lex-github', sample_extension(state: :discovered)) }

    it 'updates the extension state' do
      registry.transition('lex-github', :loaded)
      ext = registry.find_extension('lex-github')
      expect(ext[:state]).to eq(:loaded)
      expect(ext[:transitioned_at]).to be_a(Time)
    end

    it 'merges extra metadata on transition' do
      registry.transition('lex-github', :loaded, runners: %w[github/repos github/pulls])
      ext = registry.find_extension('lex-github')
      expect(ext[:runners]).to eq(%w[github/repos github/pulls])
    end

    it 'returns nil for unknown extension' do
      expect(registry.transition('nonexistent', :loaded)).to be_nil
    end

    it 'supports the full lifecycle: discovered -> loaded -> running -> stopped' do
      registry.transition('lex-github', :loaded)
      registry.transition('lex-github', :running)
      expect(registry.find_extension('lex-github')[:state]).to eq(:running)
      registry.transition('lex-github', :stopped)
      expect(registry.find_extension('lex-github')[:state]).to eq(:stopped)
    end
  end

  # ================================================================
  # filter_tools
  # ================================================================

  describe '#filter_tools' do
    before do
      registry.register_extension('lex-github', sample_extension(state: :running))
      registry.register_extension('lex-bedrock', sample_extension('lex-bedrock', state: :loaded, category: :ai))

      registry.register_tool('legion.github_repos_list', sample_tool('legion.github_repos_list',
                                                                     extension: 'lex-github', deferred: false,
                                                                     sticky: true, mcp_tier: 0, mcp_category: 'inference',
                                                                     tags: %w[ai inference], source: :discovery))
      registry.register_tool('legion.github_pulls_create', sample_tool('legion.github_pulls_create',
                                                                       extension: 'lex-github', deferred: true,
                                                                       sticky: false, mcp_tier: 1, mcp_category: 'embedding',
                                                                       tags: %w[ai embedding], source: :discovery))
      registry.register_tool('legion.bedrock_invoke', sample_tool('legion.bedrock_invoke',
                                                                  extension: 'lex-bedrock', deferred: false,
                                                                  sticky: false, mcp_tier: 0, mcp_category: 'inference',
                                                                  tags: %w[ai cloud], source: :manual))
    end

    it 'returns all tools with no criteria' do
      expect(registry.filter_tools.size).to eq(3)
    end

    it 'filters by extension' do
      result = registry.filter_tools(extension: 'lex-github')
      expect(result.size).to eq(2)
      expect(result.map { |t| t[:name] }).to all(start_with('legion.github'))
    end

    it 'filters by deferred' do
      result = registry.filter_tools(deferred: true)
      expect(result.size).to eq(1)
      expect(result.first[:name]).to eq('legion.github_pulls_create')
    end

    it 'filters by sticky' do
      result = registry.filter_tools(sticky: true)
      expect(result.size).to eq(1)
      expect(result.first[:name]).to eq('legion.github_repos_list')
    end

    it 'filters by mcp_tier' do
      result = registry.filter_tools(mcp_tier: 0)
      expect(result.size).to eq(2)
    end

    it 'filters by category (mcp_category)' do
      result = registry.filter_tools(category: 'inference')
      expect(result.size).to eq(2)
    end

    it 'filters by tags (match any)' do
      result = registry.filter_tools(tags: ['embedding'])
      expect(result.size).to eq(1)
      expect(result.first[:name]).to eq('legion.github_pulls_create')
    end

    it 'filters by tags with multiple matches' do
      result = registry.filter_tools(tags: %w[cloud embedding])
      expect(result.size).to eq(2)
    end

    it 'filters by source' do
      result = registry.filter_tools(source: :manual)
      expect(result.size).to eq(1)
      expect(result.first[:name]).to eq('legion.bedrock_invoke')
    end

    it 'filters by extension state' do
      result = registry.filter_tools(state: :running)
      expect(result.size).to eq(2)
      expect(result.map { |t| t[:extension] }).to all(eq('lex-github'))
    end

    it 'combines multiple criteria' do
      result = registry.filter_tools(extension: 'lex-github', deferred: false)
      expect(result.size).to eq(1)
      expect(result.first[:name]).to eq('legion.github_repos_list')
    end

    it 'returns frozen results' do
      result = registry.filter_tools(extension: 'lex-github')
      expect(result).to be_frozen
      expect(result.first).to be_frozen
    end
  end

  # ================================================================
  # filter_extensions
  # ================================================================

  describe '#filter_extensions' do
    before do
      registry.register_extension('lex-github', sample_extension(state: :running, category: :ai, phase: 1))
      registry.register_extension('lex-node', sample_extension('lex-node', state: :running, category: :core, phase: 0))
      registry.register_extension('lex-broken', sample_extension('lex-broken', state: :stopped, category: :ai, phase: 1))
    end

    it 'filters by state' do
      result = registry.filter_extensions(state: :running)
      expect(result.size).to eq(2)
    end

    it 'filters by category' do
      result = registry.filter_extensions(category: :ai)
      expect(result.size).to eq(2)
    end

    it 'filters by phase' do
      result = registry.filter_extensions(phase: 0)
      expect(result.size).to eq(1)
      expect(result.first[:name]).to eq('lex-node')
    end

    it 'combines multiple criteria' do
      result = registry.filter_extensions(state: :running, category: :ai)
      expect(result.size).to eq(1)
      expect(result.first[:name]).to eq('lex-github')
    end
  end

  # ================================================================
  # Unregister
  # ================================================================

  describe '#unregister_extension' do
    before do
      registry.register_extension('lex-github', sample_extension)
      registry.register_runner('github/repos/list', sample_runner(extension: 'lex-github'))
      registry.register_runner('github/pulls/create', sample_runner('github/pulls/create', extension: 'lex-github'))
      registry.register_runner('bedrock/invoke', sample_runner('bedrock/invoke', extension: 'lex-bedrock'))
      registry.register_tool('legion.github_repos_list', sample_tool('legion.github_repos_list', extension: 'lex-github'))
      registry.register_tool('legion.github_pulls_create', sample_tool('legion.github_pulls_create', extension: 'lex-github'))
      registry.register_tool('legion.bedrock_invoke', sample_tool('legion.bedrock_invoke', extension: 'lex-bedrock'))
    end

    it 'removes the extension' do
      registry.unregister_extension('lex-github')
      expect(registry.find_extension('lex-github')).to be_nil
    end

    it 'cascade-removes associated runners' do
      registry.unregister_extension('lex-github')
      expect(registry.runners.size).to eq(1)
      expect(registry.find_runner('github/repos/list')).to be_nil
      expect(registry.find_runner('bedrock/invoke')).not_to be_nil
    end

    it 'cascade-removes associated tools' do
      registry.unregister_extension('lex-github')
      expect(registry.tools.size).to eq(1)
      expect(registry.find_tool('legion.github_repos_list')).to be_nil
      expect(registry.find_tool('legion.bedrock_invoke')).not_to be_nil
    end

    it 'returns the removed extension entry' do
      removed = registry.unregister_extension('lex-github')
      expect(removed[:name]).to eq('lex-github')
    end

    it 'returns nil for unknown extension' do
      expect(registry.unregister_extension('nonexistent')).to be_nil
    end
  end

  describe '#unregister_tool' do
    it 'removes a single tool' do
      registry.register_tool('legion.github_repos_list', sample_tool('legion.github_repos_list'))
      registry.register_tool('legion.github_pulls_create', sample_tool('legion.github_pulls_create'))
      registry.unregister_tool('legion.github_repos_list')
      expect(registry.tools.size).to eq(1)
      expect(registry.find_tool('legion.github_repos_list')).to be_nil
    end

    it 'returns nil for unknown tool' do
      expect(registry.unregister_tool('nonexistent')).to be_nil
    end
  end

  # ================================================================
  # reset!
  # ================================================================

  describe '#reset!' do
    it 'clears all registries' do
      registry.register_extension('lex-github', sample_extension)
      registry.register_runner('github/repos/list', sample_runner)
      registry.register_tool('legion.github_repos_list', sample_tool)

      registry.reset!

      expect(registry.extensions).to be_empty
      expect(registry.runners).to be_empty
      expect(registry.tools).to be_empty
    end
  end

  # ================================================================
  # Frozen return values (callers cannot mutate internals)
  # ================================================================

  describe 'frozen return values' do
    before do
      registry.register_extension('lex-github', sample_extension)
      registry.register_runner('github/repos/list', sample_runner)
      registry.register_tool('legion.github_repos_list', sample_tool)
    end

    it 'extensions returns a frozen array of frozen hashes' do
      exts = registry.extensions
      expect(exts).to be_frozen
      expect(exts.first).to be_frozen
      expect { exts << {} }.to raise_error(FrozenError)
      expect { exts.first[:name] = 'hacked' }.to raise_error(FrozenError)
    end

    it 'runners returns a frozen array of frozen hashes' do
      rnrs = registry.runners
      expect(rnrs).to be_frozen
      expect(rnrs.first).to be_frozen
    end

    it 'tools returns a frozen array of frozen hashes' do
      tls = registry.tools
      expect(tls).to be_frozen
      expect(tls.first).to be_frozen
    end

    it 'find_extension returns a frozen hash' do
      found = registry.find_extension('lex-github')
      expect(found).to be_frozen
      expect { found[:name] = 'hacked' }.to raise_error(FrozenError)
    end

    it 'find_runner returns a frozen hash' do
      found = registry.find_runner('github/repos/list')
      expect(found).to be_frozen
    end

    it 'find_tool returns a frozen hash' do
      found = registry.find_tool('legion.github_repos_list')
      expect(found).to be_frozen
    end

    it 'mutating a returned hash does not affect the registry' do
      # Get the tool, verify frozen
      found = registry.find_tool('legion.github_repos_list')
      expect(found[:description]).to eq('List GitHub repositories')

      # Re-fetch and verify original value is intact
      refetched = registry.find_tool('legion.github_repos_list')
      expect(refetched[:description]).to eq('List GitHub repositories')
    end
  end

  # ================================================================
  # Thread safety
  # ================================================================

  describe 'thread safety' do
    it 'handles concurrent registration from multiple threads' do
      threads = 20.times.map do |i|
        Thread.new do
          registry.register_extension("lex-ext-#{i}", sample_extension("lex-ext-#{i}"))
          registry.register_runner("runner-#{i}", sample_runner("runner-#{i}", extension: "lex-ext-#{i}"))
          registry.register_tool("tool-#{i}", sample_tool("tool-#{i}", extension: "lex-ext-#{i}"))
        end
      end
      threads.each(&:value)

      expect(registry.extension_count).to eq(20)
      expect(registry.runner_count).to eq(20)
      expect(registry.tool_count).to eq(20)
    end

    it 'handles concurrent reads and writes' do
      # Pre-populate some data
      5.times { |i| registry.register_extension("lex-pre-#{i}", sample_extension("lex-pre-#{i}")) }

      writers = 10.times.map do |i|
        Thread.new do
          registry.register_extension("lex-write-#{i}", sample_extension("lex-write-#{i}"))
        end
      end

      readers = 10.times.map do
        Thread.new do
          registry.extensions
          registry.find_extension('lex-pre-0')
        end
      end

      (writers + readers).each(&:value)
      expect(registry.extension_count).to eq(15)
    end

    it 'handles concurrent transitions' do
      registry.register_extension('lex-github', sample_extension(state: :discovered))
      threads = 10.times.map do |i|
        Thread.new do
          state = %i[discovered loaded running stopped][i % 4]
          registry.transition('lex-github', state)
        end
      end
      threads.each(&:value)

      ext = registry.find_extension('lex-github')
      expect(%i[discovered loaded running stopped]).to include(ext[:state])
    end
  end

  # ================================================================
  # Count helpers
  # ================================================================

  describe 'count methods' do
    it 'returns correct counts' do
      expect(registry.extension_count).to eq(0)
      expect(registry.runner_count).to eq(0)
      expect(registry.tool_count).to eq(0)

      registry.register_extension('lex-a', sample_extension('lex-a'))
      registry.register_extension('lex-b', sample_extension('lex-b'))
      registry.register_runner('r1', sample_runner('r1'))
      registry.register_tool('t1', sample_tool('t1'))

      expect(registry.extension_count).to eq(2)
      expect(registry.runner_count).to eq(1)
      expect(registry.tool_count).to eq(1)
    end
  end

  # ================================================================
  # Multi-segment extension support
  # ================================================================

  describe 'multi-segment extension support' do
    # lex-agentic-learning: 2-segment nested extension with sub-runners
    let(:agentic_learning) do
      {
        version:            '0.1.10',
        state:              :running,
        category:           :agentic,
        tier:               4,
        phase:              1,
        gem_name:           'lex-agentic-learning',
        const_path:         'Legion::Extensions::Agentic::Learning',
        runners:            %w[
          agentic/learning/anchoring
          agentic/learning/hebbian
          agentic/learning/plasticity
          agentic/learning/curiosity
        ],
        mcp_tools:          true,
        mcp_tools_deferred: true,
        data_required:      false,
        llm_required:       true
      }
    end

    # lex-llm-openai: 2-segment nested LLM provider
    let(:llm_openai) do
      {
        version:    '0.1.6',
        state:      :running,
        category:   :ai,
        tier:       2,
        phase:      1,
        gem_name:   'lex-llm-openai',
        const_path: 'Legion::Extensions::Llm::Openai',
        runners:    [],
        mcp_tools:  false
      }
    end

    # lex-llm-azure-foundry: 3-segment nested (dash = 3 modules: Llm::Azure::Foundry)
    let(:llm_azure_foundry) do
      {
        version:    '0.1.3',
        state:      :loaded,
        category:   :ai,
        tier:       2,
        phase:      1,
        gem_name:   'lex-llm-azure-foundry',
        const_path: 'Legion::Extensions::Llm::Azure::Foundry',
        runners:    []
      }
    end

    # lex-microsoft_teams: underscore means CamelCase inside one module
    let(:microsoft_teams) do
      {
        version:    '0.2.0',
        state:      :running,
        category:   :service,
        tier:       1,
        phase:      1,
        gem_name:   'lex-microsoft_teams',
        const_path: 'Legion::Extensions::MicrosoftTeams',
        runners:    ['microsoft_teams/channels']
      }
    end

    it 'derives correct segments for 2-segment agentic extension' do
      registry.register_extension('lex-agentic-learning', agentic_learning)
      ext = registry.find_extension('lex-agentic-learning')
      expect(ext[:segments]).to eq(%w[agentic learning])
      expect(ext[:lex_name]).to eq('agentic_learning')
      expect(ext[:lex_slug]).to eq('agentic.learning')
    end

    it 'derives correct segments for 2-segment LLM provider' do
      registry.register_extension('lex-llm-openai', llm_openai)
      ext = registry.find_extension('lex-llm-openai')
      expect(ext[:segments]).to eq(%w[llm openai])
      expect(ext[:lex_name]).to eq('llm_openai')
      expect(ext[:lex_slug]).to eq('llm.openai')
    end

    it 'derives 3 segments for lex-llm-azure-foundry (dash = module boundary)' do
      registry.register_extension('lex-llm-azure-foundry', llm_azure_foundry)
      ext = registry.find_extension('lex-llm-azure-foundry')
      expect(ext[:segments]).to eq(%w[llm azure foundry])
      expect(ext[:lex_name]).to eq('llm_azure_foundry')
      expect(ext[:lex_slug]).to eq('llm.azure.foundry')
    end

    it 'derives single segment for lex-microsoft_teams (underscore = CamelCase)' do
      registry.register_extension('lex-microsoft_teams', microsoft_teams)
      ext = registry.find_extension('lex-microsoft_teams')
      expect(ext[:segments]).to eq(%w[microsoft_teams])
      expect(ext[:lex_name]).to eq('microsoft_teams')
      expect(ext[:lex_slug]).to eq('microsoft_teams')
      expect(ext[:const_path]).to eq('Legion::Extensions::MicrosoftTeams')
    end

    it 'registers runners for multi-segment extension' do
      registry.register_extension('lex-agentic-learning', agentic_learning)
      registry.register_runner('agentic/learning/anchoring/reinforce', {
                                 extension:     'lex-agentic-learning',
                                 runner_module: 'Legion::Extensions::Agentic::Learning::Anchoring::Runners::Anchoring',
                                 function:      'reinforce',
                                 exposed:       true
                               })
      runner = registry.find_runner('agentic/learning/anchoring/reinforce')
      expect(runner[:extension]).to eq('lex-agentic-learning')
      expect(runner[:function]).to eq('reinforce')
    end

    it 'registers tools for multi-segment extension' do
      registry.register_extension('lex-agentic-learning', agentic_learning)
      registry.register_tool('legion.agentic_learning_anchoring_reinforce', {
                               extension:    'lex-agentic-learning',
                               runner:       'agentic/learning/anchoring',
                               function:     'reinforce',
                               description:  'Reinforce an anchor point in memory',
                               input_schema: { type: 'object', properties: { anchor_id: { type: 'string' } } },
                               deferred:     true,
                               source:       :discovery
                             })
      tool = registry.find_tool('legion.agentic_learning_anchoring_reinforce')
      expect(tool[:extension]).to eq('lex-agentic-learning')
      expect(tool[:runner]).to eq('agentic/learning/anchoring')
      expect(tool[:deferred]).to be true
    end

    it 'filters tools by multi-segment extension name' do
      registry.register_extension('lex-agentic-learning', agentic_learning)
      registry.register_extension('lex-github', { state: :running, category: :service })
      registry.register_tool('legion.agentic_learning_anchoring_reinforce', {
                               extension: 'lex-agentic-learning', deferred: true, source: :discovery
                             })
      registry.register_tool('legion.github_repos_list', {
                               extension: 'lex-github', deferred: false, source: :discovery
                             })

      result = registry.filter_tools(extension: 'lex-agentic-learning')
      expect(result.size).to eq(1)
      expect(result.first[:name]).to eq('legion.agentic_learning_anchoring_reinforce')
    end

    it 'cascades unregister for multi-segment extension' do
      registry.register_extension('lex-agentic-learning', agentic_learning)
      registry.register_runner('agentic/learning/anchoring/reinforce', {
                                 extension: 'lex-agentic-learning'
                               })
      registry.register_tool('legion.agentic_learning_anchoring_reinforce', {
                               extension: 'lex-agentic-learning'
                             })

      registry.unregister_extension('lex-agentic-learning')
      expect(registry.find_extension('lex-agentic-learning')).to be_nil
      expect(registry.find_runner('agentic/learning/anchoring/reinforce')).to be_nil
      expect(registry.find_tool('legion.agentic_learning_anchoring_reinforce')).to be_nil
    end

    it 'filters extensions by requirement flags for multi-segment extensions' do
      registry.register_extension('lex-agentic-learning', agentic_learning)
      registry.register_extension('lex-llm-openai', llm_openai)

      llm_requiring = registry.filter_extensions(llm_required: true)
      expect(llm_requiring.size).to eq(1)
      expect(llm_requiring.first[:name]).to eq('lex-agentic-learning')
    end
  end
end
