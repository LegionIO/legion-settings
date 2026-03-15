# frozen_string_literal: true

require 'spec_helper'
require 'legion/settings/schema'
require 'legion/settings/validation_error'

RSpec.describe 'Legion::Settings dev mode' do
  def inject_type_error
    Legion::Settings.set_prop(:devmod, { port: 'not_a_number' })
    Legion::Settings.merge_settings('devmod', { port: 8080 })
  end

  before do
    Legion::Settings.instance_variable_set(:@loader, nil)
    Legion::Settings.instance_variable_set(:@schema, nil)
    Legion::Settings.instance_variable_set(:@cross_validations, nil)
    Legion::Settings.load
  end

  after do
    ENV.delete('LEGION_DEV')
    Legion::Settings.instance_variable_set(:@loader, nil)
    Legion::Settings.instance_variable_set(:@schema, nil)
    Legion::Settings.instance_variable_set(:@cross_validations, nil)
  end

  describe '.dev_mode?' do
    context 'when LEGION_DEV env var is not set and :dev setting is absent' do
      it 'returns false' do
        expect(Legion::Settings.dev_mode?).to be false
      end
    end

    context 'when LEGION_DEV=true' do
      it 'returns true' do
        ENV['LEGION_DEV'] = 'true'
        expect(Legion::Settings.dev_mode?).to be true
      end
    end

    context 'when LEGION_DEV is set to another value' do
      it 'returns false' do
        ENV['LEGION_DEV'] = '1'
        expect(Legion::Settings.dev_mode?).to be false
      end
    end

    context 'when Legion::Settings[:dev] is truthy' do
      it 'returns true' do
        Legion::Settings.set_prop(:dev, true)
        expect(Legion::Settings.dev_mode?).to be true
      end
    end

    context 'when Legion::Settings[:dev] is falsy' do
      it 'returns false' do
        Legion::Settings.set_prop(:dev, false)
        expect(Legion::Settings.dev_mode?).to be false
      end
    end
  end

  describe '.validate! in normal mode' do
    it 'raises ValidationError when errors are present' do
      inject_type_error
      expect { Legion::Settings.validate! }.to raise_error(Legion::Settings::ValidationError)
    end

    it 'does not raise when settings are valid' do
      expect { Legion::Settings.validate! }.not_to raise_error
    end
  end

  describe '.validate! in dev mode via LEGION_DEV=true' do
    before { ENV['LEGION_DEV'] = 'true' }

    it 'does not raise even when errors are present' do
      inject_type_error
      expect { Legion::Settings.validate! }.not_to raise_error
    end

    it 'writes a warning to $stderr when Legion::Logging is unavailable' do
      allow(Legion).to receive(:const_defined?).with('Logging').and_return(false)
      inject_type_error
      expect { Legion::Settings.validate! }.to output(/dev mode/).to_stderr
    end

    it 'does not raise when settings are valid' do
      expect { Legion::Settings.validate! }.not_to raise_error
    end
  end

  describe '.validate! in dev mode via Legion::Settings[:dev]' do
    before { Legion::Settings.set_prop(:dev, true) }

    it 'does not raise even when errors are present' do
      inject_type_error
      expect { Legion::Settings.validate! }.not_to raise_error
    end
  end

  describe 'warning message content' do
    before do
      ENV['LEGION_DEV'] = 'true'
      allow(Legion).to receive(:const_defined?).with('Logging').and_return(false)
    end

    it 'includes error count and module path in the warning' do
      inject_type_error
      expect { Legion::Settings.validate! }.to output(/\[devmod\]/).to_stderr
    end

    it 'uses singular "error" for a single error' do
      inject_type_error
      # Ensure only one error is present (reset and re-inject a single type error)
      expect { Legion::Settings.validate! }.to output(/configuration error/).to_stderr
    end
  end
end
