# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Region settings' do
  let(:loader) { Legion::Settings::Loader.new }

  describe 'default values' do
    it 'includes region key in default settings' do
      expect(loader.settings).to have_key(:region)
    end

    it 'defaults current to nil' do
      expect(loader.settings[:region][:current]).to be_nil
    end

    it 'defaults primary to nil' do
      expect(loader.settings[:region][:primary]).to be_nil
    end

    it 'defaults failover to nil' do
      expect(loader.settings[:region][:failover]).to be_nil
    end

    it 'defaults peers to empty array' do
      expect(loader.settings[:region][:peers]).to eq([])
    end

    it 'defaults default_affinity to prefer_local' do
      expect(loader.settings[:region][:default_affinity]).to eq('prefer_local')
    end

    it 'defaults data_residency to empty hash' do
      expect(loader.settings[:region][:data_residency]).to eq({})
    end
  end

  describe 'process settings' do
    it 'includes process key in default settings' do
      expect(loader.settings).to have_key(:process)
    end

    it 'defaults role to full' do
      expect(loader.settings[:process][:role]).to eq('full')
    end
  end

  describe 'CORE_MODULES' do
    it 'includes :region' do
      expect(Legion::Settings::CORE_MODULES).to include(:region)
    end

    it 'includes :process' do
      expect(Legion::Settings::CORE_MODULES).to include(:process)
    end
  end

  describe 'merge and access' do
    it 'allows setting region.current via direct mutation' do
      Legion::Settings[:region][:current] = 'us-east-2'
      expect(Legion::Settings.dig(:region, :current)).to eq('us-east-2')
    end

    it 'preserves default_affinity when merging partial config' do
      Legion::Settings.merge_settings(:region, { current: 'us-west-2' })
      expect(Legion::Settings.dig(:region, :default_affinity)).to eq('prefer_local')
    end

    it 'allows overriding default_affinity via direct mutation' do
      Legion::Settings[:region][:default_affinity] = 'any'
      expect(Legion::Settings.dig(:region, :default_affinity)).to eq('any')
    end

    it 'merges peers from config' do
      Legion::Settings.merge_settings(:region, { peers: ['us-west-2'] })
      expect(Legion::Settings.dig(:region, :peers)).to include('us-west-2')
    end

    it 'merges nested data_residency hash' do
      Legion::Settings.merge_settings(:region, { data_residency: { phi: ['us-east-2'] } })
      expect(Legion::Settings.dig(:region, :data_residency, :phi)).to eq(['us-east-2'])
    end
  end
end
