# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Settings::OS do
  describe '.windows?' do
    it 'returns a boolean' do
      expect(described_class.windows?).to be(true).or be(false)
    end

    it 'returns false on non-Windows platforms' do
      skip 'only verifiable on non-Windows' if described_class.windows?
      expect(described_class.windows?).to be false
    end
  end

  describe '.mac?' do
    it 'returns a boolean' do
      expect(described_class.mac?).to be(true).or be(false)
    end

    it 'matches RUBY_PLATFORM for darwin' do
      expected = RUBY_PLATFORM.include?('darwin')
      expect(described_class.mac?).to eq(expected)
    end
  end

  describe '.unix?' do
    it 'returns a boolean' do
      expect(described_class.unix?).to be(true).or be(false)
    end

    it 'is the inverse of windows?' do
      expect(described_class.unix?).to eq(!described_class.windows?)
    end
  end

  describe '.linux?' do
    it 'returns a boolean' do
      expect(described_class.linux?).to be(true).or be(false)
    end

    it 'is unix but not mac' do
      expected = described_class.unix? && !described_class.mac?
      expect(described_class.linux?).to eq(expected)
    end
  end

  describe '#os' do
    def build_os_host(windows: false, mac: false, unix: true)
      w = windows
      m = mac
      u = unix
      Class.new do
        include Legion::Settings::OS

        define_method(:windows?) { w }
        define_method(:mac?) { m }
        define_method(:unix?) { u }
      end.new
    end

    it 'returns windows when windows? is true' do
      host = build_os_host(windows: true, mac: false, unix: false)
      expect(host.os).to eq('windows')
    end

    it 'returns mac when mac? is true' do
      host = build_os_host(windows: false, mac: true, unix: true)
      expect(host.os).to eq('mac')
    end

    it 'returns unix when unix? is true and mac? is false' do
      host = build_os_host(windows: false, mac: false, unix: true)
      expect(host.os).to eq('unix')
    end

    it 'returns linux when all platform checks are false' do
      host = build_os_host(windows: false, mac: false, unix: false)
      expect(host.os).to eq('linux')
    end

    it 'checks windows before mac' do
      host = build_os_host(windows: true, mac: true, unix: true)
      expect(host.os).to eq('windows')
    end

    it 'checks mac before unix' do
      host = build_os_host(windows: false, mac: true, unix: true)
      expect(host.os).to eq('mac')
    end
  end

  describe 'mutual exclusivity' do
    it 'at most one of mac? and linux? is true' do
      expect(described_class.mac? && described_class.linux?).to be false
    end

    it 'windows? and unix? are mutually exclusive' do
      expect(described_class.windows? && described_class.unix?).to be false
    end
  end
end
