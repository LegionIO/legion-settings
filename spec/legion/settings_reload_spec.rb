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

    it 'replays project env overrides into the reloaded loader' do
      File.write(File.join(tmpdir, '.legionio.env'), "llm.default_model=project-model\n")
      allow(Dir).to receive(:pwd).and_return(tmpdir)

      changes = Legion::Settings.reload!

      expect(changes['llm.default_model']).to eq(old: 'old-model', new: 'project-model')
      expect(Legion::Settings[:llm][:default_model]).to eq('project-model')
    end

    it 'preserves programmatic module merges during reload' do
      Legion::Settings.merge_settings(:custom_module, { enabled: true, mode: 'default' })
      File.write(File.join(tmpdir, 'test.json'), JSON.generate({ llm: { default_model: 'module-reload-model' } }))

      Legion::Settings.reload!

      expect(Legion::Settings[:custom_module]).to include(enabled: true, mode: 'default')
    end

    it 'preserves visible settings when nothing changed' do
      Legion::Settings.reload!

      expect(Legion::Settings[:llm][:default_model]).to eq('old-model')
    end

    it 'returns empty hash when loader is not initialized' do
      Legion::Settings.reset!
      expect(Legion::Settings.reload!).to eq({})
    end

    it 'publishes one coherent update under concurrent reloads' do
      File.write(File.join(tmpdir, 'test.json'), JSON.generate({ llm: { default_model: 'concurrent-model' } }))
      ready = Queue.new
      release = Queue.new
      threads = 5.times.map do
        Thread.new do
          ready << true
          release.pop
          Legion::Settings.reload!
        end
      end
      5.times { ready.pop }
      5.times { release << true }

      results = threads.map(&:value)

      expect(results.reject(&:empty?)).to eq([{ 'llm.default_model' => { old: 'old-model', new: 'concurrent-model' } }])
      expect(Legion::Settings[:llm][:default_model]).to eq('concurrent-model')
    ensure
      threads&.each { |thread| thread.kill if thread.alive? }
      threads&.each(&:join)
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
      expect { Legion::Settings.on_reload }.to raise_error(ArgumentError)
    end
  end

  describe '.watch!' do
    it 'delivers detected configuration changes to its optional callback' do
      skip 'HUP not available' unless Signal.list.key?('HUP')

      changes = nil
      Legion::Settings.watch! { |updated| changes = updated }
      File.write(File.join(tmpdir, 'test.json'), Legion::JSON.dump({ llm: { default_model: 'watched-model' } }))
      Legion::Settings.reload!

      expect(changes.fetch('llm.default_model')).to eq(old: 'old-model', new: 'watched-model')
    end

    it 'reuses one reload worker across repeated registrations' do
      allow(Signal).to receive(:list).and_return('HUP' => 1)
      allow(Signal).to receive(:trap)

      Legion::Settings.watch!
      worker = Legion::Settings.instance_variable_get(:@reload_worker)
      Legion::Settings.watch!

      expect(Legion::Settings.instance_variable_get(:@reload_worker)).to equal(worker)
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
