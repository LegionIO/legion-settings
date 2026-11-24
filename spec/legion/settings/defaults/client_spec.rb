# frozen_string_literal: true

require 'spec_helper'
require 'legion/settings/defaults/client'

RSpec.describe Legion::Settings::Defaults::Client do
  describe '.defaults' do
    subject(:defaults) { described_class.defaults }

    before do
      allow(Socket).to receive(:gethostname).and_return('node.example.com')
      allow(Socket).to receive(:ip_address_list).and_return([Addrinfo.ip('203.0.113.10')])
    end

    it 'returns a Concurrent::Hash with the existing client values and key order' do
      expect(defaults).to be_a(Concurrent::Hash)
      expect(defaults).to eq(hostname: 'node.example.com', address: '203.0.113.10',
                             name: "node_example_com.#{Process.pid}", ready: false)
      expect(defaults.keys).to eq(%i[hostname address name ready])
    end

    it 'matches the loader client defaults' do
      expect(defaults).to eq(Legion::Settings::Loader.new.client_defaults)
    end

    %w[10.0.0.10 172.16.0.10 192.168.1.10].each do |private_address|
      it "prefers #{private_address} over a public address while excluding loopback and IPv6" do
        allow(Socket).to receive(:ip_address_list).and_return(
          [Addrinfo.ip('127.0.0.1'), Addrinfo.ip('::1'), Addrinfo.ip('203.0.113.10'), Addrinfo.ip(private_address)]
        )

        expect(defaults[:address]).to eq(private_address)
      end
    end

    it 'uses the first eligible address when there is no private address' do
      allow(Socket).to receive(:ip_address_list).and_return(
        [Addrinfo.ip('127.0.0.1'), Addrinfo.ip('::1'), Addrinfo.ip('172.32.0.10'), Addrinfo.ip('203.0.113.10')]
      )

      expect(defaults[:address]).to eq('172.32.0.10')
    end

    it 'uses unknown when there is no eligible address' do
      allow(Socket).to receive(:ip_address_list).and_return([Addrinfo.ip('127.0.0.1'), Addrinfo.ip('::1')])

      expect(defaults[:address]).to eq('unknown')
    end

    it 'reports address discovery failures and uses unknown' do
      error = SocketError.new('address discovery failed')
      allow(Socket).to receive(:ip_address_list).and_raise(error)
      expect(described_class).to receive(:handle_exception).with(error, level: :warn, operation: :system_address)

      expect(defaults[:address]).to eq('unknown')
    end

    it 'propagates programming errors during address discovery' do
      allow(Socket).to receive(:ip_address_list).and_raise(NoMethodError, 'invalid address discovery')

      expect { defaults }.to raise_error(NoMethodError, 'invalid address discovery')
    end

    it 'returns independent hashes on repeated calls' do
      defaults[:ready] = true
      defaults[:custom] = 'local'

      another = described_class.defaults
      expect(another).not_to equal(defaults)
      expect(another[:ready]).to be(false)
      expect(another).not_to have_key(:custom)
    end

    it 'evaluates the hostname and process ID when called' do
      defaults
      allow(Socket).to receive(:gethostname).and_return('other.example.com')
      allow(Process).to receive(:pid).and_return(12_345)

      expect(described_class.defaults).to include(hostname: 'other.example.com', name: 'other_example_com.12345')
    end
  end
end
