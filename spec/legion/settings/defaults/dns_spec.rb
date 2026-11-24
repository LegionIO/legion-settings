# frozen_string_literal: true

require 'spec_helper'
require 'legion/settings/defaults/dns'

RSpec.describe Legion::Settings::Defaults::DNS do
  describe '.defaults' do
    subject(:defaults) { described_class.defaults }

    let(:resolv_config) do
      { search: %w[example.com other.example], nameserver: %w[192.0.2.53 192.0.2.54] }
    end

    before do
      allow(Resolv::DNS::Config).to receive(:default_config_hash).and_return(resolv_config)
    end

    it 'returns a Concurrent::Hash with the existing DNS values and key order' do
      expect(defaults).to be_a(Concurrent::Hash)
      expect(defaults).to eq(fqdn: nil, default_domain: 'example.com', search_domains: %w[example.com other.example],
                             nameservers: %w[192.0.2.53 192.0.2.54], bootstrap: { enabled: true })
      expect(defaults.keys).to eq(%i[fqdn default_domain search_domains nameservers bootstrap])
    end

    it 'matches the loader DNS defaults' do
      expect(defaults).to eq(Legion::Settings::Loader.new.dns_defaults)
    end

    it 'normalizes resolver entries to unique strings while preserving their order' do
      resolv_config[:search] = [:'example.com', 'example.com', 'other.example']
      resolv_config[:nameserver] = [Resolv::IPv4.create('192.0.2.53'), '192.0.2.53', '192.0.2.54']

      expect(defaults).to include(default_domain: 'example.com', search_domains: %w[example.com other.example],
                                  nameservers: %w[192.0.2.53 192.0.2.54])
      expect(resolv_config[:search].length).to eq(3)
      expect(resolv_config[:nameserver].length).to eq(3)
    end

    it 'uses empty arrays and no default domain when resolver entries are absent' do
      allow(Resolv::DNS::Config).to receive(:default_config_hash).and_return({})

      expect(defaults).to include(default_domain: nil, search_domains: [], nameservers: [])
    end

    it 'keeps the default domain nil when the search list is empty' do
      resolv_config[:search] = []

      expect(defaults[:default_domain]).to be_nil
      expect(defaults[:search_domains]).to eq([])
    end

    it 'leaves FQDN resolution lazy' do
      expect(Addrinfo).not_to receive(:getaddrinfo)

      expect(defaults[:fqdn]).to be_nil
    end

    [Resolv::ResolvError, Errno::EACCES, IOError].each do |error_class|
      it "reports #{error_class} and uses empty resolver defaults" do
        error = error_class.new('resolver configuration unavailable')
        allow(Resolv::DNS::Config).to receive(:default_config_hash).and_raise(error)
        expect(described_class).to receive(:handle_exception).with(error, level: :warn, operation: :read_resolv_config)

        expect(defaults).to eq(fqdn: nil, default_domain: nil, search_domains: [], nameservers: [], bootstrap: { enabled: true })
      end
    end

    it 'propagates programming errors while reading the resolver configuration' do
      allow(Resolv::DNS::Config).to receive(:default_config_hash).and_raise(NoMethodError, 'invalid resolver configuration')

      expect { defaults }.to raise_error(NoMethodError, 'invalid resolver configuration')
    end

    it 'returns independent hashes, arrays, and bootstrap settings on repeated calls' do
      defaults[:search_domains].clear
      defaults[:nameservers].clear
      defaults[:bootstrap][:enabled] = false

      another = described_class.defaults
      expect(another).not_to equal(defaults)
      expect(another).to include(search_domains: %w[example.com other.example], nameservers: %w[192.0.2.53 192.0.2.54],
                                 bootstrap: { enabled: true })
    end

    it 'reads the resolver configuration when called' do
      defaults
      allow(Resolv::DNS::Config).to receive(:default_config_hash).and_return(
        { search: ['updated.example'], nameserver: ['192.0.2.55'] }
      )

      expect(described_class.defaults).to include(default_domain: 'updated.example', search_domains: ['updated.example'], nameservers: ['192.0.2.55'])
    end
  end
end
