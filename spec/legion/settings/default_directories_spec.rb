# frozen_string_literal: true

require 'spec_helper'
require 'legion/logging'
require 'legion/settings/loader'

Legion::Logging.setup(level: 'fatal')

RSpec.describe Legion::Settings::Loader, '.default_directories' do
  around do |example|
    original = ENV.fetch('LEGION_SETTINGS_DIRS', nil)
    example.run
  ensure
    if original
      ENV['LEGION_SETTINGS_DIRS'] = original
    else
      ENV.delete('LEGION_SETTINGS_DIRS')
    end
  end

  context 'without LEGION_SETTINGS_DIRS env var' do
    before { ENV.delete('LEGION_SETTINGS_DIRS') }

    context 'on unix' do
      before { allow(Legion::Settings::OS).to receive(:windows?).and_return(false) }

      it 'returns ~/.legionio/settings and /etc/legionio/settings' do
        dirs = described_class.default_directories
        expect(dirs).to include(File.expand_path('~/.legionio/settings'))
        expect(dirs).to include('/etc/legionio/settings')
      end

      it 'returns exactly 2 directories' do
        dirs = described_class.default_directories
        expect(dirs.size).to eq(2)
      end

      it 'does not include CWD-relative paths' do
        dirs = described_class.default_directories
        dirs.each do |d|
          expect(d).to start_with('/')
        end
      end

      it 'does not include unexpandable tilde paths' do
        dirs = described_class.default_directories
        dirs.each do |d|
          expect(d).not_to start_with('~')
        end
      end
    end

    context 'on windows' do
      before { allow(Legion::Settings::OS).to receive(:windows?).and_return(true) }

      it 'includes APPDATA path when APPDATA is set' do
        appdata = 'C:/Users/Test/AppData/Roaming'
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with('APPDATA', nil).and_return(appdata)
        dirs = described_class.default_directories
        expect(dirs).to include(File.join(appdata, 'legionio', 'settings'))
      end

      it 'omits APPDATA path when APPDATA is not set' do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with('APPDATA', nil).and_return(nil)
        dirs = described_class.default_directories
        expect(dirs.size).to eq(1)
        expect(dirs.first).to eq(File.expand_path('~/.legionio/settings'))
      end

      it 'omits APPDATA path when APPDATA is blank' do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with('APPDATA', nil).and_return('  ')
        dirs = described_class.default_directories
        expect(dirs.size).to eq(1)
        expect(dirs.first).to eq(File.expand_path('~/.legionio/settings'))
      end
    end
  end

  context 'with LEGION_SETTINGS_DIRS env var' do
    it 'returns only the directories from the env var' do
      ENV['LEGION_SETTINGS_DIRS'] = "/tmp/a#{File::PATH_SEPARATOR}/tmp/b"
      dirs = described_class.default_directories
      expect(dirs).to eq(['/tmp/a', '/tmp/b'])
    end

    it 'expands relative paths' do
      ENV['LEGION_SETTINGS_DIRS'] = './relative'
      dirs = described_class.default_directories
      expect(dirs.first).to eq(File.expand_path('./relative'))
    end

    it 'handles a single directory' do
      ENV['LEGION_SETTINGS_DIRS'] = '/tmp/only'
      dirs = described_class.default_directories
      expect(dirs).to eq(['/tmp/only'])
    end

    it 'treats blank value as unset and returns defaults' do
      ENV['LEGION_SETTINGS_DIRS'] = '   '
      allow(Legion::Settings::OS).to receive(:windows?).and_return(false)
      dirs = described_class.default_directories
      expect(dirs).to include(File.expand_path('~/.legionio/settings'))
    end

    it 'falls back to defaults when value contains only separators' do
      ENV['LEGION_SETTINGS_DIRS'] = "#{File::PATH_SEPARATOR}#{File::PATH_SEPARATOR}"
      allow(Legion::Settings::OS).to receive(:windows?).and_return(false)
      dirs = described_class.default_directories
      expect(dirs).to include(File.expand_path('~/.legionio/settings'))
      expect(dirs).to include('/etc/legionio/settings')
    end

    it 'filters out empty segments from the path list' do
      ENV['LEGION_SETTINGS_DIRS'] = "/tmp/a#{File::PATH_SEPARATOR}#{File::PATH_SEPARATOR}/tmp/b"
      dirs = described_class.default_directories
      expect(dirs).to eq(['/tmp/a', '/tmp/b'])
    end

    it 'ignores default directories entirely' do
      ENV['LEGION_SETTINGS_DIRS'] = '/custom/path'
      dirs = described_class.default_directories
      expect(dirs).not_to include(File.expand_path('~/.legionio/settings'))
      expect(dirs).not_to include('/etc/legionio/settings')
    end
  end
end
