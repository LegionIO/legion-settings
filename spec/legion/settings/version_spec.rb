# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Legion::Settings::VERSION' do
  it 'is defined' do
    expect(Legion::Settings::VERSION).not_to be_nil
  end

  it 'is a string' do
    expect(Legion::Settings::VERSION).to be_a(String)
  end

  it 'follows semver format' do
    expect(Legion::Settings::VERSION).to match(/\A\d+\.\d+\.\d+/)
  end

  it 'is parseable by Gem::Version' do
    expect { Gem::Version.new(Legion::Settings::VERSION) }.not_to raise_error
  end

  it 'is frozen' do
    expect(Legion::Settings::VERSION).to be_frozen
  end
end
