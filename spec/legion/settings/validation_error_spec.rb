# frozen_string_literal: true

require 'spec_helper'
require 'legion/settings/validation_error'

RSpec.describe Legion::Settings::ValidationError do
  it 'is a StandardError' do
    expect(described_class.new([])).to be_a(StandardError)
  end

  it 'formats a single error into the message' do
    errors = [{ module: :transport, path: 'connection.host', message: 'expected String, got Integer (42)' }]
    error = described_class.new(errors)
    expect(error.message).to include('1 configuration error')
    expect(error.message).to include('[transport] connection.host: expected String, got Integer (42)')
  end

  it 'formats multiple errors into the message' do
    errors = [
      { module: :transport, path: 'connection.host', message: 'expected String, got Integer' },
      { module: :cache, path: 'driver', message: 'expected String, got Array' }
    ]
    error = described_class.new(errors)
    expect(error.message).to include('2 configuration errors')
    expect(error.message).to include('[transport]')
    expect(error.message).to include('[cache]')
  end

  it 'exposes the errors array via #errors' do
    errors = [{ module: :test, path: 'key', message: 'bad' }]
    error = described_class.new(errors)
    expect(error.errors).to eq(errors)
  end
end
