# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Absorber settings defaults' do
  it 'has absorbers section' do
    expect(Legion::Settings[:absorbers]).to be_a(Hash)
  end

  it 'defaults enabled to true' do
    expect(Legion::Settings[:absorbers][:enabled]).to be true
  end

  it 'defaults max_depth to 5' do
    expect(Legion::Settings[:absorbers][:max_depth]).to eq(5)
  end

  it 'has sources section' do
    expect(Legion::Settings[:absorbers][:sources]).to be_a(Hash)
  end

  it 'defaults meetings enabled' do
    expect(Legion::Settings[:absorbers][:sources][:meetings][:enabled]).to be true
  end

  it 'defaults email disabled' do
    expect(Legion::Settings[:absorbers][:sources][:email_inbox][:enabled]).to be false
  end
end
