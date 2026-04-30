# frozen_string_literal: true

require 'spec_helper'
require 'legion/settings'
require 'legion/settings/overlay'

RSpec.describe Legion::Settings::Overlay do
  before { described_class.clear_overlay! }
  after  { described_class.clear_overlay! }

  describe '.with_overlay' do
    it 'yields the block' do
      called = false
      described_class.with_overlay(foo: 'bar') { called = true }
      expect(called).to be true
    end

    it 'returns the block return value' do
      result = described_class.with_overlay(x: 1) { 42 }
      expect(result).to eq(42)
    end

    it 'makes the overlay visible inside the block' do
      described_class.with_overlay(llm: { default_model: 'haiku' }) do
        expect(described_class.current_overlay).to include(llm: { default_model: 'haiku' })
      end
    end

    it 'cleans up the overlay after the block completes' do
      described_class.with_overlay(foo: 'bar') { nil }
      expect(described_class.current_overlay).to be_nil
    end

    it 'cleans up the overlay even when the block raises' do
      expect do
        described_class.with_overlay(foo: 'bar') { raise 'boom' }
      end.to raise_error(RuntimeError, 'boom')
      expect(described_class.current_overlay).to be_nil
    end
  end

  describe '.current_overlay' do
    it 'returns nil when no overlay is active' do
      expect(described_class.current_overlay).to be_nil
    end

    it 'returns the active overlay inside a block' do
      described_class.with_overlay(a: 1) do
        expect(described_class.current_overlay).to eq(a: 1)
      end
    end
  end

  describe '.overlay_for' do
    it 'returns nil when no overlay is active' do
      expect(described_class.overlay_for(:llm)).to be_nil
    end

    it 'returns the overlay value for a top-level symbol key' do
      described_class.with_overlay(llm: { default_model: 'opus' }) do
        expect(described_class.overlay_for(:llm)).to eq(default_model: 'opus')
      end
    end

    it 'accepts string keys' do
      described_class.with_overlay('cache' => { driver: 'redis' }) do
        expect(described_class.overlay_for('cache')).to eq(driver: 'redis')
      end
    end
  end

  describe 'nesting' do
    it 'merges inner overlay on top of outer overlay' do
      described_class.with_overlay(llm: { default_model: 'sonnet', temperature: 0.7 }) do
        described_class.with_overlay(llm: { default_model: 'haiku' }) do
          overlay = described_class.current_overlay
          expect(overlay[:llm][:default_model]).to eq('haiku')
          expect(overlay[:llm][:temperature]).to eq(0.7)
        end
      end
    end

    it 'restores the outer overlay after the inner block' do
      described_class.with_overlay(llm: { default_model: 'sonnet' }) do
        described_class.with_overlay(llm: { default_model: 'haiku' }) { nil }
        expect(described_class.current_overlay[:llm][:default_model]).to eq('sonnet')
      end
    end

    it 'adds new keys from the inner overlay without overwriting unrelated outer keys' do
      described_class.with_overlay(cache: { driver: 'redis' }) do
        described_class.with_overlay(llm: { default_model: 'opus' }) do
          overlay = described_class.current_overlay
          expect(overlay[:cache]).to eq(driver: 'redis')
          expect(overlay[:llm]).to eq(default_model: 'opus')
        end
      end
    end
  end

  describe 'thread isolation' do
    it 'overlay in one thread does not affect another thread' do
      other_overlay = nil
      described_class.with_overlay(secret: 'x') do
        t = Thread.new { other_overlay = described_class.current_overlay }
        t.join
      end
      expect(other_overlay).to be_nil
    end
  end

  describe '.clear_overlay!' do
    it 'clears any active overlay for the current thread' do
      described_class.with_overlay(foo: 'bar') do
        described_class.clear_overlay!
        expect(described_class.current_overlay).to be_nil
      end
    end
  end
end

RSpec.describe Legion::Settings do
  before { described_class.reset! }
  after  { described_class.reset! }

  describe '.with_overlay' do
    it 'delegates to Overlay.with_overlay' do
      result = nil
      described_class.with_overlay(llm: { default_model: 'haiku' }) do
        result = Legion::Settings::Overlay.current_overlay
      end
      expect(result).to include(llm: { default_model: 'haiku' })
    end

    it 'overrides [] for the duration of the block (scalar override)' do
      described_class.with_overlay(custom_overlay_key: 'injected') do
        expect(described_class[:custom_overlay_key]).to eq('injected')
      end
    end

    it 'overrides [] for a nested hash key, merging with base settings' do
      described_class.merge_settings('mymod', { host: 'localhost', port: 5672 })
      described_class.with_overlay(mymod: { port: 9999 }) do
        expect(described_class[:mymod][:port]).to eq(9999)
        expect(described_class[:mymod][:host]).to eq('localhost')
      end
    end

    it 'restores original value after the block' do
      described_class.merge_settings('mymod2', { host: 'localhost' })
      described_class.with_overlay(mymod2: { host: 'override' }) { nil }
      expect(described_class[:mymod2][:host]).to eq('localhost')
    end

    it 'does not affect [] outside the block' do
      described_class.merge_settings(:cache, { driver: 'dalli' })
      expect(described_class[:cache][:driver]).to eq('dalli')
      described_class.with_overlay(cache: { driver: 'redis' }) do
        expect(described_class[:cache][:driver]).to eq('redis')
      end
      expect(described_class[:cache][:driver]).to eq('dalli')
    end
  end

  describe 'resolution order: overlay > base' do
    it 'overlay takes precedence over global settings' do
      described_class.with_overlay(transport: { host: 'overlay-host' }) do
        expect(described_class[:transport][:host]).to eq('overlay-host')
      end
    end
  end
end
