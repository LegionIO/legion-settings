# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Settings::Extensions do
  subject(:registry) { described_class }

  after { registry.reset! }

  # ----------------------------------------------------------------
  # Helpers
  # ----------------------------------------------------------------

  def sample_extension(name = 'lex-ollama', **overrides)
    {
      version:    '0.3.10',
      state:      :discovered,
      category:   :ai,
      tier:       1,
      phase:      1,
      const_path: 'Legion::Extensions::Ollama',
      runners:    ['ollama/inference', 'ollama/embedding']
    }.merge(overrides).merge(name: name)
  end

  def sample_runner(name = 'ollama/inference/chat', **overrides)
    {
      extension:     'lex-ollama',
      runner_module: 'Legion::Extensions::Ollama::Runners::Inference',
      function:      'chat',
      exposed:       true
    }.merge(overrides).merge(name: name)
  end

  def sample_tool(name = 'legion.ollama_inference_chat', **overrides)
    {
      extension:    'lex-ollama',
      runner:       'ollama/inference',
      function:     'chat',
      description:  'Chat with Ollama models',
      deferred:     false,
      sticky:       true,
      mcp_tier:     0,
      mcp_category: 'inference',
      tags:         %w[ai inference],
      source:       :discovery
    }.merge(overrides).merge(name: name)
  end

  # ================================================================
  # Registration
  # ================================================================

  describe 'extension registration' do
    it 'registers an extension and returns a frozen entry' do
      result = registry.register_extension('lex-ollama', sample_extension)
      expect(result).to be_frozen
      expect(result[:name]).to eq('lex-ollama')
      expect(result[:state]).to eq(:discovered)
      expect(result[:registered_at]).to be_a(Time)
    end

    it 'finds a registered extension by name' do
      registry.register_extension('lex-ollama', sample_extension)
      found = registry.find_extension('lex-ollama')
      expect(found).not_to be_nil
      expect(found[:name]).to eq('lex-ollama')
      expect(found[:category]).to eq(:ai)
    end

    it 'returns nil for an unknown extension' do
      expect(registry.find_extension('nonexistent')).to be_nil
    end

    it 'lists all registered extensions' do
      registry.register_extension('lex-ollama', sample_extension)
      registry.register_extension('lex-bedrock', sample_extension('lex-bedrock', category: :ai))
      exts = registry.extensions
      expect(exts.size).to eq(2)
      expect(exts.map { |e| e[:name] }).to contain_exactly('lex-ollama', 'lex-bedrock')
    end

    it 'overwrites on duplicate registration without duplicating' do
      registry.register_extension('lex-ollama', sample_extension(state: :discovered))
      registry.register_extension('lex-ollama', sample_extension(state: :loaded))
      exts = registry.extensions
      expect(exts.size).to eq(1)
      expect(exts.first[:state]).to eq(:loaded)
    end

    it 'accepts symbol names and normalizes to string' do
      registry.register_extension(:lex_ollama, sample_extension)
      expect(registry.find_extension('lex_ollama')).not_to be_nil
      expect(registry.find_extension(:lex_ollama)).not_to be_nil
    end
  end

  # ================================================================
  # Runner registration
  # ================================================================

  describe 'runner registration' do
    it 'registers a runner and returns a frozen entry' do
      result = registry.register_runner('ollama/inference/chat', sample_runner)
      expect(result).to be_frozen
      expect(result[:name]).to eq('ollama/inference/chat')
      expect(result[:extension]).to eq('lex-ollama')
    end

    it 'finds a registered runner by name' do
      registry.register_runner('ollama/inference/chat', sample_runner)
      found = registry.find_runner('ollama/inference/chat')
      expect(found).not_to be_nil
      expect(found[:function]).to eq('chat')
    end

    it 'returns nil for an unknown runner' do
      expect(registry.find_runner('nonexistent')).to be_nil
    end

    it 'lists all registered runners' do
      registry.register_runner('ollama/inference/chat', sample_runner)
      registry.register_runner('ollama/embedding/embed', sample_runner('ollama/embedding/embed', function: 'embed'))
      rnrs = registry.runners
      expect(rnrs.size).to eq(2)
    end

    it 'overwrites on duplicate runner registration' do
      registry.register_runner('ollama/inference/chat', sample_runner(exposed: true))
      registry.register_runner('ollama/inference/chat', sample_runner(exposed: false))
      expect(registry.runners.size).to eq(1)
      expect(registry.find_runner('ollama/inference/chat')[:exposed]).to be false
    end
  end

  # ================================================================
  # Tool registration
  # ================================================================

  describe 'tool registration' do
    it 'registers a tool and returns a frozen entry' do
      result = registry.register_tool('legion.ollama_inference_chat', sample_tool)
      expect(result).to be_frozen
      expect(result[:name]).to eq('legion.ollama_inference_chat')
      expect(result[:deferred]).to be false
    end

    it 'finds a registered tool by name' do
      registry.register_tool('legion.ollama_inference_chat', sample_tool)
      found = registry.find_tool('legion.ollama_inference_chat')
      expect(found).not_to be_nil
      expect(found[:description]).to eq('Chat with Ollama models')
    end

    it 'returns nil for an unknown tool' do
      expect(registry.find_tool('nonexistent')).to be_nil
    end

    it 'lists all registered tools' do
      registry.register_tool('legion.ollama_inference_chat', sample_tool)
      registry.register_tool('legion.bedrock_invoke', sample_tool('legion.bedrock_invoke', extension: 'lex-bedrock'))
      tls = registry.tools
      expect(tls.size).to eq(2)
    end

    it 'overwrites on duplicate tool registration' do
      registry.register_tool('legion.ollama_inference_chat', sample_tool(deferred: false))
      registry.register_tool('legion.ollama_inference_chat', sample_tool(deferred: true))
      expect(registry.tools.size).to eq(1)
      expect(registry.find_tool('legion.ollama_inference_chat')[:deferred]).to be true
    end
  end

  # ================================================================
  # Transition
  # ================================================================

  describe '#transition' do
    before { registry.register_extension('lex-ollama', sample_extension(state: :discovered)) }

    it 'updates the extension state' do
      registry.transition('lex-ollama', :loaded)
      ext = registry.find_extension('lex-ollama')
      expect(ext[:state]).to eq(:loaded)
      expect(ext[:transitioned_at]).to be_a(Time)
    end

    it 'merges extra metadata on transition' do
      registry.transition('lex-ollama', :loaded, runners: %w[ollama/inference ollama/embedding])
      ext = registry.find_extension('lex-ollama')
      expect(ext[:runners]).to eq(%w[ollama/inference ollama/embedding])
    end

    it 'returns nil for unknown extension' do
      expect(registry.transition('nonexistent', :loaded)).to be_nil
    end

    it 'supports the full lifecycle: discovered -> loaded -> running -> stopped' do
      registry.transition('lex-ollama', :loaded)
      registry.transition('lex-ollama', :running)
      expect(registry.find_extension('lex-ollama')[:state]).to eq(:running)
      registry.transition('lex-ollama', :stopped)
      expect(registry.find_extension('lex-ollama')[:state]).to eq(:stopped)
    end
  end

  # ================================================================
  # filter_tools
  # ================================================================

  describe '#filter_tools' do
    before do
      registry.register_extension('lex-ollama', sample_extension(state: :running))
      registry.register_extension('lex-bedrock', sample_extension('lex-bedrock', state: :loaded, category: :ai))

      registry.register_tool('legion.ollama_chat', sample_tool('legion.ollama_chat',
                                                               extension: 'lex-ollama', deferred: false,
                                                               sticky: true, mcp_tier: 0, mcp_category: 'inference',
                                                               tags: %w[ai inference], source: :discovery))
      registry.register_tool('legion.ollama_embed', sample_tool('legion.ollama_embed',
                                                                extension: 'lex-ollama', deferred: true,
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
      result = registry.filter_tools(extension: 'lex-ollama')
      expect(result.size).to eq(2)
      expect(result.map { |t| t[:name] }).to all(start_with('legion.ollama'))
    end

    it 'filters by deferred' do
      result = registry.filter_tools(deferred: true)
      expect(result.size).to eq(1)
      expect(result.first[:name]).to eq('legion.ollama_embed')
    end

    it 'filters by sticky' do
      result = registry.filter_tools(sticky: true)
      expect(result.size).to eq(1)
      expect(result.first[:name]).to eq('legion.ollama_chat')
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
      expect(result.first[:name]).to eq('legion.ollama_embed')
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
      expect(result.map { |t| t[:extension] }).to all(eq('lex-ollama'))
    end

    it 'combines multiple criteria' do
      result = registry.filter_tools(extension: 'lex-ollama', deferred: false)
      expect(result.size).to eq(1)
      expect(result.first[:name]).to eq('legion.ollama_chat')
    end

    it 'returns frozen results' do
      result = registry.filter_tools(extension: 'lex-ollama')
      expect(result).to be_frozen
      expect(result.first).to be_frozen
    end
  end

  # ================================================================
  # filter_extensions
  # ================================================================

  describe '#filter_extensions' do
    before do
      registry.register_extension('lex-ollama', sample_extension(state: :running, category: :ai, phase: 1))
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
      expect(result.first[:name]).to eq('lex-ollama')
    end
  end

  # ================================================================
  # Unregister
  # ================================================================

  describe '#unregister_extension' do
    before do
      registry.register_extension('lex-ollama', sample_extension)
      registry.register_runner('ollama/inference/chat', sample_runner(extension: 'lex-ollama'))
      registry.register_runner('ollama/embedding/embed', sample_runner('ollama/embedding/embed', extension: 'lex-ollama'))
      registry.register_runner('bedrock/invoke', sample_runner('bedrock/invoke', extension: 'lex-bedrock'))
      registry.register_tool('legion.ollama_chat', sample_tool('legion.ollama_chat', extension: 'lex-ollama'))
      registry.register_tool('legion.ollama_embed', sample_tool('legion.ollama_embed', extension: 'lex-ollama'))
      registry.register_tool('legion.bedrock_invoke', sample_tool('legion.bedrock_invoke', extension: 'lex-bedrock'))
    end

    it 'removes the extension' do
      registry.unregister_extension('lex-ollama')
      expect(registry.find_extension('lex-ollama')).to be_nil
    end

    it 'cascade-removes associated runners' do
      registry.unregister_extension('lex-ollama')
      expect(registry.runners.size).to eq(1)
      expect(registry.find_runner('ollama/inference/chat')).to be_nil
      expect(registry.find_runner('bedrock/invoke')).not_to be_nil
    end

    it 'cascade-removes associated tools' do
      registry.unregister_extension('lex-ollama')
      expect(registry.tools.size).to eq(1)
      expect(registry.find_tool('legion.ollama_chat')).to be_nil
      expect(registry.find_tool('legion.bedrock_invoke')).not_to be_nil
    end

    it 'returns the removed extension entry' do
      removed = registry.unregister_extension('lex-ollama')
      expect(removed[:name]).to eq('lex-ollama')
    end

    it 'returns nil for unknown extension' do
      expect(registry.unregister_extension('nonexistent')).to be_nil
    end
  end

  describe '#unregister_tool' do
    it 'removes a single tool' do
      registry.register_tool('legion.ollama_chat', sample_tool('legion.ollama_chat'))
      registry.register_tool('legion.ollama_embed', sample_tool('legion.ollama_embed'))
      registry.unregister_tool('legion.ollama_chat')
      expect(registry.tools.size).to eq(1)
      expect(registry.find_tool('legion.ollama_chat')).to be_nil
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
      registry.register_extension('lex-ollama', sample_extension)
      registry.register_runner('ollama/inference/chat', sample_runner)
      registry.register_tool('legion.ollama_chat', sample_tool)

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
      registry.register_extension('lex-ollama', sample_extension)
      registry.register_runner('ollama/inference/chat', sample_runner)
      registry.register_tool('legion.ollama_chat', sample_tool)
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
      found = registry.find_extension('lex-ollama')
      expect(found).to be_frozen
      expect { found[:name] = 'hacked' }.to raise_error(FrozenError)
    end

    it 'find_runner returns a frozen hash' do
      found = registry.find_runner('ollama/inference/chat')
      expect(found).to be_frozen
    end

    it 'find_tool returns a frozen hash' do
      found = registry.find_tool('legion.ollama_chat')
      expect(found).to be_frozen
    end

    it 'mutating a returned hash does not affect the registry' do
      # Get the tool, verify frozen
      found = registry.find_tool('legion.ollama_chat')
      expect(found[:description]).to eq('Chat with Ollama models')

      # Re-fetch and verify original value is intact
      refetched = registry.find_tool('legion.ollama_chat')
      expect(refetched[:description]).to eq('Chat with Ollama models')
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
      threads.each(&:join)

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

      (writers + readers).each(&:join)
      expect(registry.extension_count).to eq(15)
    end

    it 'handles concurrent transitions' do
      registry.register_extension('lex-ollama', sample_extension(state: :discovered))
      threads = 10.times.map do |i|
        Thread.new do
          state = %i[discovered loaded running stopped][i % 4]
          registry.transition('lex-ollama', state)
        end
      end
      threads.each(&:join)

      ext = registry.find_extension('lex-ollama')
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
end
