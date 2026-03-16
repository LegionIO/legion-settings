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
end
