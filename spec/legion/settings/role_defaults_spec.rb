# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Settings::Loader do
  describe '#default_settings' do
    subject(:defaults) { described_class.new.settings }

    it 'includes role key with nil profile' do
      expect(defaults).to have_key(:role)
      expect(defaults[:role][:profile]).to be_nil
    end

    it 'includes empty extensions array in role' do
      expect(defaults[:role][:extensions]).to eq([])
    end
  end
end
