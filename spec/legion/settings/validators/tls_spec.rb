# frozen_string_literal: true

require 'spec_helper'
require 'legion/settings/validators/tls'

RSpec.describe Legion::Settings::Validators::Tls do
  describe '.validate' do
    context 'with empty settings' do
      it 'returns valid with no warnings or errors' do
        result = described_class.validate({})
        expect(result[:valid]).to be true
        expect(result[:warnings]).to be_empty
        expect(result[:errors]).to be_empty
      end
    end

    context 'transport.tls enabled but verify_peer false' do
      let(:settings) do
        { transport: { tls: { enabled: true, verify: 'none' } } }
      end

      it 'adds a warning' do
        result = described_class.validate(settings)
        expect(result[:warnings]).to include(match(/verify.*none/i))
      end

      it 'is still valid' do
        result = described_class.validate(settings)
        expect(result[:valid]).to be true
      end
    end

    context 'transport.tls enabled with peer verify' do
      let(:settings) do
        { transport: { tls: { enabled: true, verify: 'peer' } } }
      end

      it 'has no warnings' do
        result = described_class.validate(settings)
        expect(result[:warnings]).to be_empty
      end
    end

    context 'data.tls sslmode is require in production' do
      let(:settings) do
        { data: { tls: { enabled: true, sslmode: 'require' } }, env: 'production' }
      end

      it 'adds an error' do
        result = described_class.validate(settings)
        expect(result[:errors]).to include(match(/verify-full/i))
      end

      it 'is not valid' do
        result = described_class.validate(settings)
        expect(result[:valid]).to be false
      end
    end

    context 'data.tls sslmode is require in non-production' do
      let(:settings) do
        { data: { tls: { enabled: true, sslmode: 'require' } }, env: 'development' }
      end

      it 'adds a warning instead of error' do
        result = described_class.validate(settings)
        expect(result[:warnings]).to include(match(/verify-full/i))
        expect(result[:errors]).to be_empty
      end
    end

    context 'data.tls sslmode is verify-full' do
      let(:settings) do
        { data: { tls: { enabled: true, sslmode: 'verify-full' } } }
      end

      it 'has no errors' do
        result = described_class.validate(settings)
        expect(result[:errors]).to be_empty
      end
    end

    context 'cert path does not exist' do
      let(:settings) do
        { transport: { tls: { enabled: true, cert: '/nonexistent/cert.pem', verify: 'peer' } } }
      end

      it 'adds a warning about missing cert' do
        result = described_class.validate(settings)
        expect(result[:warnings]).to include(match(%r{/nonexistent/cert\.pem}))
      end
    end

    context 'cert path exists' do
      let(:settings) do
        { transport: { tls: { enabled: true, cert: __FILE__, verify: 'peer' } } }
      end

      it 'has no cert warnings' do
        result = described_class.validate(settings)
        cert_warnings = result[:warnings].select { |w| w.include?('cert') }
        expect(cert_warnings).to be_empty
      end
    end

    context 'security.mtls enabled' do
      let(:settings) do
        { security: { mtls: { enabled: true, cert: '/nonexistent/client.pem', key: '/nonexistent/client.key' } } }
      end

      it 'warns about missing cert and key paths' do
        result = described_class.validate(settings)
        expect(result[:warnings].size).to be >= 2
      end
    end

    context 'api.tls enabled but cert/key missing' do
      let(:settings) do
        { api: { tls: { enabled: true } } }
      end

      it 'adds an error for missing cert' do
        result = described_class.validate(settings)
        expect(result[:errors]).to include(match(/cert/i))
      end
    end

    context 'api.tls enabled with cert and key present' do
      let(:settings) do
        { api: { tls: { enabled: true, cert: __FILE__, key: __FILE__ } } }
      end

      it 'is valid' do
        result = described_class.validate(settings)
        expect(result[:errors]).to be_empty
      end
    end
  end
end
