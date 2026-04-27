# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'json'

RSpec.describe 'Legion::Settings hot-reload' do
  let(:tmpdir) { Dir.mktmpdir('legion_reload_test') }

  before do
    Legion::Settings.reset!
    File.write(File.join(tmpdir, 'test.json'), JSON.generate({ llm: { default_model: 'old-model' } }))
    Legion::Settings.load(config_dir: tmpdir)
  end

  after do
    Legion::Settings.reset!
    FileUtils.rm_rf(tmpdir)
  end

  describe '.reload!' do
    it 'returns an empty hash when nothing changed' do
      changes = Legion::Settings.reload!
      expect(changes).to be_a(Hash)
      expect(changes).to be_empty
    end

    it 'detects changes when a config file is modified' do
      File.write(File.join(tmpdir, 'test.json'), JSON.generate({ llm: { default_model: 'new-model' } }))
      changes = Legion::Settings.reload!
      expect(changes).not_to be_empty
      expect(changes.keys).to include(match(/default_model/))
    end

    it 'includes old and new values in the changes hash' do
      File.write(File.join(tmpdir, 'test.json'), JSON.generate({ llm: { default_model: 'new-model' } }))
      changes = Legion::Settings.reload!
      model_change = changes.values.find { |v| v[:old] == 'old-model' }
      expect(model_change).not_to be_nil
      expect(model_change[:new]).to eq('new-model')
    end

    it 'detects added keys' do
      File.write(File.join(tmpdir, 'test.json'), JSON.generate({ llm: { default_model: 'old-model', new_key: 'hello' } }))
      changes = Legion::Settings.reload!
      expect(changes).not_to be_empty
    end

    it 'detects removed keys' do
      File.write(File.join(tmpdir, 'test.json'), JSON.generate({ llm: {} }))
      changes = Legion::Settings.reload!
      expect(changes).not_to be_empty
    end

    it 'updates the active loader on change' do
      File.write(File.join(tmpdir, 'test.json'), JSON.generate({ llm: { default_model: 'reloaded-model' } }))
      Legion::Settings.reload!
      expect(Legion::Settings[:llm][:default_model]).to eq('reloaded-model')
    end

    it 'does not update the loader when nothing changed' do
      original_loader = Legion::Settings.loader
      Legion::Settings.reload!
      expect(Legion::Settings.loader).to equal(original_loader)
    end

    it 'returns empty hash when loader is not initialized' do
      Legion::Settings.reset!
      expect(Legion::Settings.reload!).to eq({})
    end

    it 'is thread-safe under concurrent calls' do
      results = []
      threads = 5.times.map do
        Thread.new do
          File.write(File.join(tmpdir, 'test.json'), JSON.generate({ llm: { default_model: "thread-#{Thread.current.object_id}" } }))
          results << Legion::Settings.reload!
        end
      end
      threads.each(&:join)
      expect(results.size).to eq(5)
      results.each { |r| expect(r).to be_a(Hash) }
    end
  end

  describe '.on_reload' do
    it 'calls registered callbacks when changes are detected' do
      called_with = nil
      Legion::Settings.on_reload { |changes| called_with = changes }

      File.write(File.join(tmpdir, 'test.json'), JSON.generate({ llm: { default_model: 'callback-model' } }))
      Legion::Settings.reload!

      expect(called_with).not_to be_nil
      expect(called_with).to be_a(Hash)
    end

    it 'calls multiple callbacks in registration order' do
      call_order = []
      Legion::Settings.on_reload { |_| call_order << :first }
      Legion::Settings.on_reload { |_| call_order << :second }
      Legion::Settings.on_reload { |_| call_order << :third }

      File.write(File.join(tmpdir, 'test.json'), JSON.generate({ llm: { default_model: 'multi-cb' } }))
      Legion::Settings.reload!

      expect(call_order).to eq(%i[first second third])
    end

    it 'does not call callbacks when nothing changed' do
      called = false
      Legion::Settings.on_reload { |_| called = true }

      Legion::Settings.reload!

      expect(called).to eq(false)
    end

    it 'continues calling remaining callbacks when one raises' do
      results = []
      Legion::Settings.on_reload { |_| raise 'boom' }
      Legion::Settings.on_reload { |_| results << :survived }

      File.write(File.join(tmpdir, 'test.json'), JSON.generate({ llm: { default_model: 'error-model' } }))
      Legion::Settings.reload!

      expect(results).to eq([:survived])
    end

    it 'raises ArgumentError when called without a block' do
      expect { Legion::Settings.on_reload }.to raise_error(ArgumentError, /requires a block/)
    end
  end

  describe '.watch!' do
    it 'is a no-op on platforms without HUP signal' do
      allow(Signal).to receive(:list).and_return({})
      expect { Legion::Settings.watch! }.not_to raise_error
    end

    it 'installs a SIGHUP handler on supported platforms' do
      skip 'HUP not available' unless Signal.list.key?('HUP')
      expect { Legion::Settings.watch! }.not_to raise_error
    end

    it 'accepts an optional block passed to on_reload' do
      skip 'HUP not available' unless Signal.list.key?('HUP')
      called = false
      expect { Legion::Settings.watch! { |_| called = true } }.not_to raise_error
    end
  end

  describe '.reset!' do
    it 'clears all reload state' do
      Legion::Settings.on_reload { |_| nil }
      Legion::Settings.reload! # initializes mutex
      Legion::Settings.reset!

      # After reset, reload returns empty (no loader)
      expect(Legion::Settings.reload!).to eq({})
    end
  end
end
