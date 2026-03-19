# frozen_string_literal: true

require 'spec_helper'
require 'legion/logging'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'legion/settings/dns_bootstrap'

Legion::Logging.setup(level: 'fatal')

RSpec.describe Legion::Settings::DnsBootstrap do
  let(:domain) { 'example.com' }
  let(:cache_dir) { Dir.mktmpdir('legion_dns_test') }
  let(:cache_file) { File.join(cache_dir, '_dns_bootstrap.json') }
  let(:bootstrap) { described_class.new(default_domain: domain, cache_dir: cache_dir) }

  after { FileUtils.rm_rf(cache_dir) }

  describe '#initialize' do
    it 'stores the default domain' do
      expect(bootstrap.default_domain).to eq('example.com')
    end

    it 'builds the well-known hostname' do
      expect(bootstrap.hostname).to eq('legion-bootstrap.example.com')
    end

    it 'builds the well-known URL' do
      expect(bootstrap.url).to eq('https://legion-bootstrap.example.com/legion/bootstrap.json')
    end
  end

  describe '#resolve?' do
    it 'returns false when hostname does not resolve' do
      allow(Resolv).to receive(:getaddress).and_raise(Resolv::ResolvError)
      expect(bootstrap.resolve?).to be false
    end

    it 'returns true when hostname resolves' do
      allow(Resolv).to receive(:getaddress).with('legion-bootstrap.example.com').and_return('10.0.0.1')
      expect(bootstrap.resolve?).to be true
    end
  end

  describe '#fetch' do
    before do
      allow(bootstrap).to receive(:resolve?).and_return(true)
    end

    it 'returns parsed JSON on success' do
      stub_successful_fetch('{"transport":{"host":"rabbitmq.example.com"}}')
      result = bootstrap.fetch
      expect(result[:transport][:host]).to eq('rabbitmq.example.com')
    end

    it 'returns nil on HTTP error' do
      stub_failed_fetch(404)
      expect(bootstrap.fetch).to be_nil
    end

    it 'returns nil when hostname does not resolve' do
      allow(bootstrap).to receive(:resolve?).and_return(false)
      expect(bootstrap.fetch).to be_nil
    end

    it 'returns nil on network timeout' do
      stub_timeout_fetch
      expect(bootstrap.fetch).to be_nil
    end
  end

  describe '#write_cache' do
    let(:config) { { transport: { host: 'rabbitmq.example.com' } } }

    it 'writes JSON to cache file' do
      bootstrap.write_cache(config)
      expect(File.exist?(cache_file)).to be true
    end

    it 'includes _dns_bootstrap_meta' do
      bootstrap.write_cache(config)
      cached = JSON.parse(File.read(cache_file), symbolize_names: true)
      expect(cached[:_dns_bootstrap_meta]).to be_a(Hash)
      expect(cached[:_dns_bootstrap_meta][:hostname]).to eq('legion-bootstrap.example.com')
      expect(cached[:_dns_bootstrap_meta][:fetched_at]).to be_a(String)
    end

    it 'preserves the original config keys' do
      bootstrap.write_cache(config)
      cached = JSON.parse(File.read(cache_file), symbolize_names: true)
      expect(cached[:transport][:host]).to eq('rabbitmq.example.com')
    end
  end

  describe '#read_cache' do
    it 'returns nil when cache file does not exist' do
      expect(bootstrap.read_cache).to be_nil
    end

    it 'returns parsed config when cache exists' do
      config = { transport: { host: 'rabbitmq.example.com' } }
      bootstrap.write_cache(config)
      result = bootstrap.read_cache
      expect(result[:transport][:host]).to eq('rabbitmq.example.com')
    end

    it 'strips _dns_bootstrap_meta from returned config' do
      config = { transport: { host: 'rabbitmq.example.com' } }
      bootstrap.write_cache(config)
      result = bootstrap.read_cache
      expect(result).not_to have_key(:_dns_bootstrap_meta)
    end

    it 'returns nil and deletes file when cache is corrupted' do
      File.write(cache_file, 'not json{{{')
      expect(bootstrap.read_cache).to be_nil
      expect(File.exist?(cache_file)).to be false
    end
  end

  describe '#cache_exists?' do
    it 'returns false when no cache file' do
      expect(bootstrap.cache_exists?).to be false
    end

    it 'returns true when cache file exists' do
      bootstrap.write_cache({ test: true })
      expect(bootstrap.cache_exists?).to be true
    end
  end

  private

  def stub_successful_fetch(body)
    response = instance_double(Net::HTTPSuccess, body: body)
    allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    http = instance_double(Net::HTTP, request: response)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(Net::HTTP).to receive(:new).and_return(http)
  end

  def stub_failed_fetch(code)
    response = instance_double(Net::HTTPResponse, code: code.to_s, message: 'Not Found')
    allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
    http = instance_double(Net::HTTP, request: response)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(Net::HTTP).to receive(:new).and_return(http)
  end

  def stub_timeout_fetch
    http = instance_double(Net::HTTP)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:request).and_raise(Net::OpenTimeout)
    allow(Net::HTTP).to receive(:new).and_return(http)
  end
end
