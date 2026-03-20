# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'legion/settings/agent_loader'

RSpec.describe Legion::Settings::AgentLoader do
  let(:agents_dir) { File.join(File.dirname(__FILE__), 'assets', 'agents') }
  let(:empty_dir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(empty_dir) }

  describe '.load_agents' do
    it 'loads YAML agent definitions' do
      agents = described_class.load_agents(agents_dir)
      yaml_agent = agents.find { |a| a[:name] == 'test-agent' }
      expect(yaml_agent).not_to be_nil
      expect(yaml_agent[:runner][:functions].size).to eq(2)
    end

    it 'loads JSON agent definitions' do
      agents = described_class.load_agents(agents_dir)
      json_agent = agents.find { |a| a[:name] == 'json-agent' }
      expect(json_agent).not_to be_nil
      expect(json_agent[:runner][:functions].first[:type]).to eq('http')
    end

    it 'returns empty array for empty directory' do
      agents = described_class.load_agents(empty_dir)
      expect(agents).to eq([])
    end

    it 'returns empty array for nonexistent directory' do
      agents = described_class.load_agents('/nonexistent/path')
      expect(agents).to eq([])
    end

    it 'skips files missing required keys' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'bad.yaml'), "description: no name or runner\n")
        agents = described_class.load_agents(dir)
        expect(agents).to eq([])
      end
    end
  end

  describe '.load_file' do
    it 'parses .yaml files' do
      result = described_class.load_file(File.join(agents_dir, 'test-agent.yaml'))
      expect(result[:name]).to eq('test-agent')
    end

    it 'parses .json files' do
      result = described_class.load_file(File.join(agents_dir, 'test-agent.json'))
      expect(result[:name]).to eq('json-agent')
    end

    it 'returns nil for unknown extensions' do
      expect(described_class.load_file('/some/file.txt')).to be_nil
    end
  end

  describe '.valid?' do
    it 'returns true for agents with name and runner.functions' do
      expect(described_class.valid?({ name: 'a', runner: { functions: [{ name: 'f', type: 'llm' }] } })).to be true
    end

    it 'returns false for agents missing name' do
      expect(described_class.valid?({ runner: { functions: [{ name: 'f', type: 'llm' }] } })).to be false
    end

    it 'returns false for agents missing runner' do
      expect(described_class.valid?({ name: 'a' })).to be false
    end

    it 'returns false for agents with empty functions' do
      expect(described_class.valid?({ name: 'a', runner: { functions: [] } })).to be false
    end
  end
end
