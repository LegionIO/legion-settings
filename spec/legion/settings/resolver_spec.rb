# frozen_string_literal: true

require 'spec_helper'
require 'legion/logging'
Legion::Logging.setup(log_level: 'error', level: 'error', trace: false)
require 'legion/settings'
require 'legion/settings/resolver'

RSpec.describe Legion::Settings::Resolver do
  describe '.resolve_value' do
    context 'with plain strings (no URI prefix)' do
      it 'returns the string unchanged' do
        expect(described_class.resolve_value('hello')).to eq('hello')
      end

      it 'returns an empty string unchanged' do
        expect(described_class.resolve_value('')).to eq('')
      end
    end

    context 'with non-string scalars' do
      it 'returns nil unchanged' do
        expect(described_class.resolve_value(nil)).to be_nil
      end

      it 'returns integers unchanged' do
        expect(described_class.resolve_value(42)).to eq(42)
      end

      it 'returns true unchanged' do
        expect(described_class.resolve_value(true)).to eq(true)
      end

      it 'returns false unchanged' do
        expect(described_class.resolve_value(false)).to eq(false)
      end
    end

    context 'with env:// URIs' do
      after { ENV.delete('RESOLVER_TEST_VAR') }

      it 'resolves a set environment variable' do
        ENV['RESOLVER_TEST_VAR'] = 'my_secret_value'
        result = described_class.resolve_value('env://RESOLVER_TEST_VAR')
        expect(result).to eq('my_secret_value')
      end

      it 'returns nil for an unset environment variable' do
        ENV.delete('RESOLVER_TEST_VAR')
        result = described_class.resolve_value('env://RESOLVER_TEST_VAR')
        expect(result).to be_nil
      end
    end

    context 'with arrays containing URI patterns (chain resolution)' do
      after { ENV.delete('RESOLVER_CHAIN_TEST_VAR') }

      it 'resolves to the fallback value when env var is unset' do
        result = described_class.resolve_value(['env://RESOLVER_CHAIN_TEST_VAR', 'fallback_value'])
        expect(result).to eq('fallback_value')
      end

      it 'resolves to the env value when env var is set (first match wins)' do
        ENV['RESOLVER_CHAIN_TEST_VAR'] = 'from_env'
        result = described_class.resolve_value(['env://RESOLVER_CHAIN_TEST_VAR', 'ignored'])
        expect(result).to eq('from_env')
      end
    end

    context 'with plain arrays (no URI prefix)' do
      it 'returns the array unchanged when no entries have URI prefixes' do
        arr = %w[alpha beta gamma]
        expect(described_class.resolve_value(arr)).to eq(arr)
      end

      it 'returns the original array object (not a copy)' do
        arr = %w[alpha beta]
        result = described_class.resolve_value(arr)
        expect(result).to be(arr)
      end
    end
  end

  describe '.resolve_single' do
    after { ENV.delete('RESOLVER_SINGLE_VAR') }

    it 'resolves env:// to the env var value' do
      ENV['RESOLVER_SINGLE_VAR'] = 'resolved_value'
      expect(described_class.resolve_single('env://RESOLVER_SINGLE_VAR')).to eq('resolved_value')
    end

    it 'returns nil for unset env var' do
      ENV.delete('RESOLVER_SINGLE_VAR')
      expect(described_class.resolve_single('env://RESOLVER_SINGLE_VAR')).to be_nil
    end

    it 'returns the string unchanged if it has no recognized URI scheme' do
      expect(described_class.resolve_single('just_a_string')).to eq('just_a_string')
    end
  end

  describe '.resolve_chain' do
    after { ENV.delete('RESOLVER_CHAIN_VAR') }

    it 'returns first non-nil result when env var is set' do
      ENV['RESOLVER_CHAIN_VAR'] = 'from_env'
      result = described_class.resolve_chain(['env://RESOLVER_CHAIN_VAR', 'fallback_literal'])
      expect(result).to eq('from_env')
    end

    it 'falls through to a literal string when env var is unset' do
      ENV.delete('RESOLVER_CHAIN_VAR')
      result = described_class.resolve_chain(['env://RESOLVER_CHAIN_VAR', 'fallback_literal'])
      expect(result).to eq('fallback_literal')
    end

    it 'returns nil when the entire chain is exhausted' do
      ENV.delete('RESOLVER_CHAIN_VAR')
      result = described_class.resolve_chain(['env://RESOLVER_CHAIN_VAR'])
      expect(result).to be_nil
    end

    it 'returns nil when given an empty array' do
      expect(described_class.resolve_chain([])).to be_nil
    end

    it 'stops at the first non-nil value and does not evaluate further entries' do
      ENV['RESOLVER_CHAIN_VAR'] = 'first_wins'
      result = described_class.resolve_chain(['env://RESOLVER_CHAIN_VAR', 'env://SHOULD_NOT_MATTER'])
      expect(result).to eq('first_wins')
    end
  end

  describe '.resolve_secrets!' do
    context 'with env:// values in a nested hash' do
      after { ENV.delete('RESOLVER_NESTED_VAR') }

      it 'resolves env:// strings in-place' do
        ENV['RESOLVER_NESTED_VAR'] = 'nested_secret'
        settings = { database: { password: 'env://RESOLVER_NESTED_VAR' } }
        described_class.resolve_secrets!(settings)
        expect(settings[:database][:password]).to eq('nested_secret')
      end

      it 'resolves env:// strings at the top level' do
        ENV['RESOLVER_NESTED_VAR'] = 'top_level_val'
        settings = { api_key: 'env://RESOLVER_NESTED_VAR' }
        described_class.resolve_secrets!(settings)
        expect(settings[:api_key]).to eq('top_level_val')
      end

      it 'resolves env:// strings inside arrays of hashes' do
        ENV['RESOLVER_NESTED_VAR'] = 'array_hash_secret'
        settings = {
          clients: [
            { password: 'env://RESOLVER_NESTED_VAR' },
            { nested: { token: 'env://RESOLVER_NESTED_VAR' } }
          ]
        }
        described_class.resolve_secrets!(settings)
        expect(settings[:clients][0][:password]).to eq('array_hash_secret')
        expect(settings[:clients][1][:nested][:token]).to eq('array_hash_secret')
      end
    end

    context 'with fallback chain arrays in settings' do
      after { ENV.delete('RESOLVER_FALLBACK_VAR') }

      it 'resolves chain arrays to first non-nil value' do
        ENV['RESOLVER_FALLBACK_VAR'] = 'chain_resolved'
        settings = { secret: ['env://RESOLVER_FALLBACK_VAR', 'default_secret'] }
        described_class.resolve_secrets!(settings)
        expect(settings[:secret]).to eq('chain_resolved')
      end

      it 'uses literal fallback in chain when env var is unset' do
        ENV.delete('RESOLVER_FALLBACK_VAR')
        settings = { secret: ['env://RESOLVER_FALLBACK_VAR', 'default_fallback'] }
        described_class.resolve_secrets!(settings)
        expect(settings[:secret]).to eq('default_fallback')
      end
    end

    context 'with non-resolvable values' do
      it 'leaves plain strings untouched' do
        settings = { name: 'plain_value' }
        described_class.resolve_secrets!(settings)
        expect(settings[:name]).to eq('plain_value')
      end

      it 'leaves integers untouched' do
        settings = { port: 5432 }
        described_class.resolve_secrets!(settings)
        expect(settings[:port]).to eq(5432)
      end

      it 'leaves booleans untouched' do
        settings = { enabled: true }
        described_class.resolve_secrets!(settings)
        expect(settings[:enabled]).to eq(true)
      end

      it 'leaves plain string arrays untouched' do
        settings = { roles: %w[admin user] }
        described_class.resolve_secrets!(settings)
        expect(settings[:roles]).to eq(%w[admin user])
      end

      it 'returns the hash unchanged for non-hash input' do
        expect(described_class.resolve_secrets!(nil)).to be_nil
        expect(described_class.resolve_secrets!('string')).to eq('string')
      end
    end

    context 'with mixed content' do
      after { ENV.delete('RESOLVER_MIX_VAR') }

      it 'resolves only URI values and leaves others intact' do
        ENV['RESOLVER_MIX_VAR'] = 'resolved_mix'
        settings = {
          host:     'localhost',
          port:     6379,
          password: 'env://RESOLVER_MIX_VAR',
          nested:   {
            key:    'env://RESOLVER_MIX_VAR',
            static: 'unchanged'
          }
        }
        described_class.resolve_secrets!(settings)
        expect(settings[:host]).to eq('localhost')
        expect(settings[:port]).to eq(6379)
        expect(settings[:password]).to eq('resolved_mix')
        expect(settings[:nested][:key]).to eq('resolved_mix')
        expect(settings[:nested][:static]).to eq('unchanged')
      end
    end
  end

  describe '.has_vault_refs?' do
    it 'returns false for a hash with no vault:// references' do
      settings = { host: 'localhost', password: 'env://MY_VAR' }
      expect(described_class.has_vault_refs?(settings)).to eq(false)
    end

    it 'returns true for a hash with vault:// references' do
      settings = { secret: 'vault://secret/app#token' }
      expect(described_class.has_vault_refs?(settings)).to eq(true)
    end

    it 'returns true for nested vault:// references' do
      settings = { db: { password: 'vault://secret/db#password' } }
      expect(described_class.has_vault_refs?(settings)).to eq(true)
    end

    it 'returns false for a non-hash input' do
      expect(described_class.has_vault_refs?(nil)).to eq(false)
    end
  end

  describe '.count_vault_refs' do
    it 'returns 0 when no vault:// references exist' do
      settings = { host: 'localhost', key: 'env://MY_VAR' }
      expect(described_class.count_vault_refs(settings)).to eq(0)
    end

    it 'counts vault:// references in string values' do
      settings = {
        secret_a: 'vault://secret/app#token',
        secret_b: 'vault://secret/app#key'
      }
      expect(described_class.count_vault_refs(settings)).to eq(2)
    end

    it 'counts vault:// references inside arrays' do
      settings = { chain: ['vault://secret/app#token', 'env://FALLBACK', 'literal'] }
      expect(described_class.count_vault_refs(settings)).to eq(1)
    end

    it 'counts vault:// references recursively in nested hashes' do
      settings = { db: { pass: 'vault://secret/db#password', host: 'localhost' } }
      expect(described_class.count_vault_refs(settings)).to eq(1)
    end

    it 'counts vault:// references inside arrays of hashes' do
      settings = {
        clients: [
          { password: 'vault://secret/db#password' },
          { nested: { token: 'vault://secret/app#token' } }
        ]
      }
      expect(described_class.count_vault_refs(settings)).to eq(2)
    end
  end

  describe 'VAULT_PATTERN' do
    it 'matches vault://path#key' do
      m = 'vault://secret/myapp/db#password'.match(described_class::VAULT_PATTERN)
      expect(m).not_to be_nil
      expect(m[1]).to eq('secret/myapp/db')
      expect(m[2]).to eq('password')
    end

    it 'does not match vault:// without a # separator' do
      expect('vault://secret/myapp/db'.match(described_class::VAULT_PATTERN)).to be_nil
    end

    it 'does not match env:// URIs' do
      expect('env://MY_VAR'.match(described_class::VAULT_PATTERN)).to be_nil
    end
  end

  describe 'ENV_PATTERN' do
    it 'matches env://VAR_NAME' do
      m = 'env://MY_SECRET_VAR'.match(described_class::ENV_PATTERN)
      expect(m).not_to be_nil
      expect(m[1]).to eq('MY_SECRET_VAR')
    end

    it 'does not match vault:// URIs' do
      expect('vault://secret/app#key'.match(described_class::ENV_PATTERN)).to be_nil
    end
  end

  describe 'URI_PATTERN' do
    it 'matches vault:// URIs' do
      expect('vault://secret/app#key').to match(described_class::URI_PATTERN)
    end

    it 'matches env:// URIs' do
      expect('env://MY_VAR').to match(described_class::URI_PATTERN)
    end

    it 'does not match plain strings' do
      expect('plain_string').not_to match(described_class::URI_PATTERN)
    end

    it 'does not match other URI schemes' do
      expect('http://example.com').not_to match(described_class::URI_PATTERN)
    end
  end

  describe 'vault:// resolution' do
    before do
      stub_const('Legion::Crypt', Module.new)
      allow(Legion::Crypt).to receive(:read).with('secret/data/transport').and_return({
                                                                                        username: 'vault_user',
                                                                                        password: 'vault_pass'
                                                                                      })
      allow(Legion::Crypt).to receive(:read).with('secret/data/missing').and_raise(StandardError, 'not found')
    end

    context 'when vault is connected' do
      before do
        allow(Legion::Settings).to receive(:[]).and_call_original
        allow(Legion::Settings).to receive(:[]).with(:crypt).and_return({ vault: { connected: true } })
      end

      it 'resolves vault://path#key to the vault value' do
        settings = { secret: 'vault://secret/data/transport#username' }
        described_class.resolve_secrets!(settings)
        expect(settings[:secret]).to eq('vault_user')
      end

      it 'leaves the vault:// string in place when the key does not exist in the vault hash' do
        settings = { secret: 'vault://secret/data/transport#nonexistent' }
        described_class.resolve_secrets!(settings)
        expect(settings[:secret]).to eq('vault://secret/data/transport#nonexistent')
      end

      it 'does not raise when the vault path fails, and leaves the original string in place' do
        settings = { secret: 'vault://secret/data/missing#key' }
        expect { described_class.resolve_secrets!(settings) }.not_to raise_error
        expect(settings[:secret]).to eq('vault://secret/data/missing#key')
      end

      it 'only calls Legion::Crypt.read once for two keys from the same path (caching)' do
        settings = {
          user: 'vault://secret/data/transport#username',
          pass: 'vault://secret/data/transport#password'
        }
        described_class.resolve_secrets!(settings)
        expect(Legion::Crypt).to have_received(:read).with('secret/data/transport').once
        expect(settings[:user]).to eq('vault_user')
        expect(settings[:pass]).to eq('vault_pass')
      end
    end

    context 'when a clustered Vault connection is available through Legion::Crypt' do
      before do
        allow(Legion::Settings).to receive(:[]).and_call_original
        allow(Legion::Settings).to receive(:[]).with(:crypt).and_return({ vault: { connected: false } })
        allow(Legion::Crypt).to receive(:vault_connected?).and_return(true)
      end

      it 'resolves vault:// values using the connected cluster path' do
        settings = { secret: 'vault://secret/data/transport#username' }
        described_class.resolve_secrets!(settings)
        expect(settings[:secret]).to eq('vault_user')
      end
    end

    context 'when vault is not connected' do
      before do
        allow(Legion::Settings).to receive(:[]).and_call_original
        allow(Legion::Settings).to receive(:[]).with(:crypt).and_return({ vault: { connected: false } })
      end

      it 'skips vault:// resolution and leaves string in place without calling Legion::Crypt.read' do
        settings = { secret: 'vault://secret/data/transport#username' }
        described_class.resolve_secrets!(settings)
        expect(Legion::Crypt).not_to have_received(:read)
        expect(settings[:secret]).to eq('vault://secret/data/transport#username')
      end

      it 'falls through to env fallback in a chain when vault is unavailable' do
        ENV['LEGION_TEST_FALLBACK'] = 'env_fallback_value'
        settings = { secret: ['vault://secret/data/transport#username', 'env://LEGION_TEST_FALLBACK', 'default'] }
        described_class.resolve_secrets!(settings)
        expect(settings[:secret]).to eq('env_fallback_value')
      ensure
        ENV.delete('LEGION_TEST_FALLBACK')
      end
    end
  end

  describe 'mixed vault:// and env:// chain in resolve_secrets!' do
    before do
      stub_const('Legion::Crypt', Module.new)
      allow(Legion::Crypt).to receive(:read).with('secret/data/rabbitmq').and_return({
                                                                                       username: 'rabbit_vault',
                                                                                       password: 'rabbit_secret'
                                                                                     })
      allow(Legion::Settings).to receive(:[]).with(:crypt).and_return({ vault: { connected: true } })
    end

    it 'resolves vault first and skips env fallback when vault succeeds' do
      ENV['RABBITMQ_USER'] = 'env_rabbit_user'
      settings = {
        transport: {
          connection: {
            user: ['vault://secret/data/rabbitmq#username', 'env://RABBITMQ_USER', 'guest']
          }
        }
      }
      described_class.resolve_secrets!(settings)
      expect(settings[:transport][:connection][:user]).to eq('rabbit_vault')
    ensure
      ENV.delete('RABBITMQ_USER')
    end
  end

  describe 'LEASE_PATTERN' do
    it 'matches lease://name#key' do
      m = 'lease://rabbitmq#username'.match(described_class::LEASE_PATTERN)
      expect(m).not_to be_nil
      expect(m[1]).to eq('rabbitmq')
      expect(m[2]).to eq('username')
    end

    it 'matches lease names with hyphens' do
      m = 'lease://rabbitmq-primary#password'.match(described_class::LEASE_PATTERN)
      expect(m).not_to be_nil
      expect(m[1]).to eq('rabbitmq-primary')
    end

    it 'does not match lease:// without # separator' do
      expect('lease://rabbitmq'.match(described_class::LEASE_PATTERN)).to be_nil
    end

    it 'does not match vault:// URIs' do
      expect('vault://secret/app#key'.match(described_class::LEASE_PATTERN)).to be_nil
    end

    it 'does not match env:// URIs' do
      expect('env://MY_VAR'.match(described_class::LEASE_PATTERN)).to be_nil
    end
  end

  describe 'URI_PATTERN with lease://' do
    it 'matches lease:// URIs' do
      expect('lease://rabbitmq#username').to match(described_class::URI_PATTERN)
    end
  end

  describe 'lease:// resolution' do
    let(:lease_manager) { double('LeaseManager', fetch: nil, register_ref: nil) }

    before do
      stub_const('Legion::Crypt::LeaseManager', Class.new)
      allow(Legion::Crypt::LeaseManager).to receive(:instance).and_return(lease_manager)
    end

    context 'when LeaseManager is available' do
      before do
        allow(lease_manager).to receive(:fetch).with('rabbitmq', 'username').and_return('lease_user')
        allow(lease_manager).to receive(:fetch).with('rabbitmq', 'password').and_return('lease_pass')
      end

      it 'resolves lease://name#key to the LeaseManager value' do
        settings = { user: 'lease://rabbitmq#username' }
        described_class.resolve_secrets!(settings)
        expect(settings[:user]).to eq('lease_user')
      end

      it 'resolves multiple keys from the same lease' do
        settings = {
          transport: {
            connection: {
              username: 'lease://rabbitmq#username',
              password: 'lease://rabbitmq#password'
            }
          }
        }
        described_class.resolve_secrets!(settings)
        expect(settings[:transport][:connection][:username]).to eq('lease_user')
        expect(settings[:transport][:connection][:password]).to eq('lease_pass')
      end

      it 'registers references with LeaseManager for push-back' do
        settings = { user: 'lease://rabbitmq#username' }
        described_class.resolve_secrets!(settings)
        expect(lease_manager).to have_received(:register_ref).with('rabbitmq', 'username', kind_of(Array))
      end

      it 'works in fallback chains' do
        allow(lease_manager).to receive(:fetch).with('primary', 'password').and_return(nil)
        allow(lease_manager).to receive(:fetch).with('fallback', 'password').and_return('fallback_pass')
        settings = { pass: ['lease://primary#password', 'lease://fallback#password', 'default'] }
        described_class.resolve_secrets!(settings)
        expect(settings[:pass]).to eq('fallback_pass')
      end

      it 'mixes with env:// in chains' do
        ENV['LEASE_TEST_MIX'] = 'from_env'
        allow(lease_manager).to receive(:fetch).with('rabbitmq', 'password').and_return(nil)
        settings = { pass: ['lease://rabbitmq#password', 'env://LEASE_TEST_MIX', 'guest'] }
        described_class.resolve_secrets!(settings)
        expect(settings[:pass]).to eq('from_env')
      ensure
        ENV.delete('LEASE_TEST_MIX')
      end
    end

    context 'when LeaseManager is not available' do
      before do
        hide_const('Legion::Crypt::LeaseManager')
      end

      it 'leaves lease:// strings unresolved' do
        settings = { user: 'lease://rabbitmq#username' }
        described_class.resolve_secrets!(settings)
        expect(settings[:user]).to eq('lease://rabbitmq#username')
      end
    end
  end

  describe '.count_lease_refs' do
    it 'returns 0 when no lease:// references exist' do
      settings = { host: 'localhost', key: 'env://MY_VAR' }
      expect(described_class.count_lease_refs(settings)).to eq(0)
    end

    it 'counts lease:// references in string values' do
      settings = { user: 'lease://rabbitmq#username', pass: 'lease://rabbitmq#password' }
      expect(described_class.count_lease_refs(settings)).to eq(2)
    end

    it 'counts lease:// references inside arrays' do
      settings = { chain: ['lease://rabbitmq#password', 'env://FALLBACK', 'literal'] }
      expect(described_class.count_lease_refs(settings)).to eq(1)
    end

    it 'counts recursively in nested hashes' do
      settings = { db: { pass: 'lease://postgres#password', host: 'localhost' } }
      expect(described_class.count_lease_refs(settings)).to eq(1)
    end

    it 'counts lease:// references inside arrays of hashes' do
      settings = {
        clients: [
          { password: 'lease://postgres#password' },
          { nested: { token: 'lease://rabbitmq#username' } }
        ]
      }
      expect(described_class.count_lease_refs(settings)).to eq(2)
    end
  end
end

RSpec.describe 'Legion::Settings.resolve_secrets!' do
  it 'delegates to Resolver.resolve_secrets!' do
    allow(Legion::Settings::Resolver).to receive(:resolve_secrets!)
    Legion::Settings.load
    Legion::Settings.resolve_secrets!
    expect(Legion::Settings::Resolver).to have_received(:resolve_secrets!).with(kind_of(Hash))
  end
end
