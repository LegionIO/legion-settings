# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Absorber settings defaults' do
  it 'has absorbers section as an empty hash (defaults owned by LegionIO)' do
    expect(Legion::Settings[:absorbers]).to be_a(Hash)
  end

  it 'starts empty before LegionIO registers its defaults' do
    expect(Legion::Settings[:absorbers]).to eq({})
  end
end
