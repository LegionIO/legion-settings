# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Settings::Helper do
  before do
    Legion::Settings.reset!
    Legion::Settings::Extensions.reset!
    Legion::Settings.loader = Legion::Settings::Loader.new
  end

  # --- Test classes simulating different extension structures ---

  # Single-segment: lex-github → Legion::Extensions::Github
  let(:github_runner) do
    stub_const('Legion::Extensions::Github::Runners::Repos', Class.new do
      include Legion::Settings::Helper
    end)
  end

  # Multi-segment: lex-agentic-learning → Legion::Extensions::Agentic::Learning
  let(:agentic_learning_root) do
    stub_const('Legion::Extensions::Agentic::Learning', Module.new do
      extend Legion::Settings::Helper
    end)
  end

  # Sub-module inside multi-segment: ConceptualBlending is INSIDE lex-agentic-learning
  let(:agentic_learning_sub_runner) do
    stub_const('Legion::Extensions::Agentic::Learning::ConceptualBlending::Runners::Blend',
               Class.new do
                 include Legion::Settings::Helper
               end)
  end

  # Underscore in name: lex-microsoft_teams → Legion::Extensions::MicrosoftTeams
  let(:microsoft_teams_runner) do
    stub_const('Legion::Extensions::MicrosoftTeams::Runners::Channels', Class.new do
      include Legion::Settings::Helper
    end)
  end

  # LLM provider: lex-llm-openai → Legion::Extensions::Llm::Openai
  let(:llm_openai_class) do
    stub_const('Legion::Extensions::Llm::Openai', Module.new do
      extend Legion::Settings::Helper
    end)
  end

  # Non-extension class (no Extensions:: in namespace)
  let(:non_extension_class) do
    stub_const('Legion::SomeModule::Runner', Class.new do
      include Legion::Settings::Helper
    end)
  end

  # Class with explicit segments method (LegionIO's Base mixin)
  let(:class_with_segments) do
    Class.new do
      include Legion::Settings::Helper

      def segments
        %w[agentic learning]
      end
    end
  end

  describe '#settings' do
    context 'single-segment extension (lex-github)' do
      before do
        Legion::Settings.merge_settings(:extensions, {
                                          github: { api_token: 'abc', per_page: 50 }
                                        })
      end

      it 'resolves to Settings[:extensions][:github]' do
        obj = github_runner.new
        expect(obj.settings[:api_token]).to eq('abc')
        expect(obj.settings[:per_page]).to eq(50)
      end
    end

    context 'multi-segment extension (lex-agentic-learning)' do
      before do
        Legion::Settings::Extensions.register_extension('lex-agentic-learning', {
                                                          state: :running, category: :agentic
                                                        })
        Legion::Settings.merge_settings(:extensions, {
                                          agentic: { learning: { log_level: 'debug', blend_depth: 3 } }
                                        })
      end

      it 'resolves to Settings[:extensions][:agentic][:learning]' do
        expect(agentic_learning_root.settings[:log_level]).to eq('debug')
        expect(agentic_learning_root.settings[:blend_depth]).to eq(3)
      end

      it 'sub-module resolves to the SAME gem-level settings' do
        obj = agentic_learning_sub_runner.new
        expect(obj.settings[:log_level]).to eq('debug')
      end

      it 'sub-module accesses its section via key' do
        Legion::Settings[:extensions][:agentic][:learning][:conceptual_blending] = { strategy: 'selective' }
        obj = agentic_learning_sub_runner.new
        expect(obj.settings[:conceptual_blending][:strategy]).to eq('selective')
      end
    end

    context 'underscore extension (lex-microsoft_teams)' do
      before do
        Legion::Settings.merge_settings(:extensions, {
                                          microsoft_teams: { poll_interval: 30 }
                                        })
      end

      it 'resolves to Settings[:extensions][:microsoft_teams]' do
        obj = microsoft_teams_runner.new
        expect(obj.settings[:poll_interval]).to eq(30)
      end
    end

    context 'LLM provider (lex-llm-openai)' do
      before do
        Legion::Settings::Extensions.register_extension('lex-llm-openai', {
                                                          state: :running, category: :ai
                                                        })
        Legion::Settings.merge_settings(:extensions, {
                                          llm: { openai: { api_key: 'sk-test' } }
                                        })
      end

      it 'resolves to Settings[:extensions][:llm][:openai]' do
        expect(llm_openai_class.settings[:api_key]).to eq('sk-test')
      end
    end

    context 'when extension settings do not exist yet' do
      it 'creates a thread-safe empty hash at the correct path' do
        obj = github_runner.new
        result = obj.settings
        expect(result).to be_a(Concurrent::Hash)
        expect(result).to be_empty
      end

      it 'persists the created hash so writes survive' do
        obj = github_runner.new
        obj.settings[:new_key] = 'value'
        expect(obj.settings[:new_key]).to eq('value')
      end
    end

    context 'with explicit segments method (LegionIO Base mixin)' do
      before do
        Legion::Settings.merge_settings(:extensions, {
                                          agentic: { learning: { explicit: true } }
                                        })
      end

      it 'uses segments directly when available' do
        obj = class_with_segments.new
        expect(obj.settings[:explicit]).to be true
      end
    end

    context 'non-extension class' do
      it 'falls back to last namespace part' do
        obj = non_extension_class.new
        result = obj.settings
        expect(result).to be_a(Hash)
      end
    end
  end
end
