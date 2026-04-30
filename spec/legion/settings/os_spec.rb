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
    # The #os instance method calls windows?/mac?/unix? without self.class,
    # so it only works when mixed into a context where those are also instance
    # methods. Create a wrapper that delegates to the class methods.
    let(:os_host) do
      mod = described_class
      Class.new do
        include mod

        define_method(:windows?) { mod.windows? }
        define_method(:mac?) { mod.mac? }
        define_method(:unix?) { mod.unix? }
      end.new
    end

    it 'returns a known platform string' do
      expect(%w[windows mac unix linux]).to include(os_host.os)
    end

    it 'returns mac on darwin' do
      skip 'only verifiable on macOS' unless described_class.mac?
      expect(os_host.os).to eq('mac')
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
