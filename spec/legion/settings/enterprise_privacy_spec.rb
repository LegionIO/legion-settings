# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Legion::Settings enterprise_data_privacy' do
  before do
    Legion::Settings.instance_variable_set(:@loader, nil)
    Legion::Settings.instance_variable_set(:@schema, nil)
    Legion::Settings.instance_variable_set(:@cross_validations, nil)
    Legion::Settings.load
  end

  after do
    ENV.delete('LEGION_ENTERPRISE_PRIVACY')
    Legion::Settings.instance_variable_set(:@loader, nil)
    Legion::Settings.instance_variable_set(:@schema, nil)
    Legion::Settings.instance_variable_set(:@cross_validations, nil)
  end

  describe '.enterprise_privacy?' do
    context 'when flag is absent' do
      it 'returns false' do
        expect(Legion::Settings.enterprise_privacy?).to be false
      end
    end

    context 'when LEGION_ENTERPRISE_PRIVACY=true' do
      it 'returns true' do
        ENV['LEGION_ENTERPRISE_PRIVACY'] = 'true'
        Legion::Settings.instance_variable_set(:@loader, nil)
        Legion::Settings.load
        expect(Legion::Settings.enterprise_privacy?).to be true
      end
    end

    context 'when LEGION_ENTERPRISE_PRIVACY is set to another value' do
      it 'returns false' do
        ENV['LEGION_ENTERPRISE_PRIVACY'] = '1'
        Legion::Settings.instance_variable_set(:@loader, nil)
        Legion::Settings.load
        expect(Legion::Settings.enterprise_privacy?).to be false
      end
    end

    context 'when Legion::Settings[:enterprise_data_privacy] is true' do
      it 'returns true' do
        Legion::Settings.set_prop(:enterprise_data_privacy, true)
        expect(Legion::Settings.enterprise_privacy?).to be true
      end
    end

    context 'when Legion::Settings[:enterprise_data_privacy] is false' do
      it 'returns false' do
        Legion::Settings.set_prop(:enterprise_data_privacy, false)
        expect(Legion::Settings.enterprise_privacy?).to be false
      end
    end
  end
end
