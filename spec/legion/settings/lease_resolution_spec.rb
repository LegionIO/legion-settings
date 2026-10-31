# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'timeout'
require 'legion/crypt/lease_manager'
require 'legion/settings/resolver'

RSpec.describe 'Settings lease resolution transactions' do
  let(:manager) { Legion::Crypt::LeaseManager.instance }
  let(:vault_client) { double('Vault client') }
  let(:tmpdir) { Dir.mktmpdir('legion_lease_resolution') }
  let(:config_file) { File.join(tmpdir, 'settings.json') }

  before do
    Legion::Settings.reset!
    manager.reset!
    manager.start({}, vault_client: vault_client)
    allow(Legion::Crypt).to receive(:vault_connected?).and_return(false)
    allow(Dir).to receive(:pwd).and_return(tmpdir)
    ENV.delete('LEGION_LEASE_SPEC_SECRET')
  end

  after do
    manager.shutdown
    manager.reset!
    Legion::Settings.reset!
    ENV.delete('LEGION_LEASE_SPEC_SECRET')
    FileUtils.rm_rf(tmpdir)
  end

  def install_lease(name:, password:)
    response = double('Vault lease response', lease_id: nil, lease_duration: 3600,
                                             renewable?: false, data: { password: password })
    manager.register_dynamic_lease(name: name, path: "database/creds/#{name}", response: response, settings_refs: [])
  end

  def write_credentials(values:)
    File.write(config_file, Legion::JSON.dump({ credentials: values }))
  end

  def load_credentials(values:)
    write_credentials(values: values)
    Legion::Settings.load(config_dir: tmpdir)
    Legion::Settings.resolve_secrets!
  end

  it 'lets only the selected lease rotate a fallback-chain destination' do
    install_lease(name: :a, password: 'a-first')
    install_lease(name: :b, password: 'b-first')
    load_credentials(values: { password: ['lease://a#password', 'lease://b#password', 'literal'] })

    expect(Legion::Settings[:credentials][:password]).to eq('a-first')
    install_lease(name: :b, password: 'b-next')
    expect(Legion::Settings[:credentials][:password]).to eq('a-first')
    install_lease(name: :a, password: 'a-next')
    expect(Legion::Settings[:credentials][:password]).to eq('a-next')
  end

  it 'rotates a selected fallback without subscribing the unavailable primary' do
    install_lease(name: :b, password: 'b-first')
    load_credentials(values: { password: ['lease://a#password', 'lease://b#password', 'literal'] })

    expect(Legion::Settings[:credentials][:password]).to eq('b-first')
    install_lease(name: :a, password: 'a-arrived')
    expect(Legion::Settings[:credentials][:password]).to eq('b-first')
    install_lease(name: :b, password: 'b-next')
    expect(Legion::Settings[:credentials][:password]).to eq('b-next')
  end

  it 'keeps an environment winner independent of an unused lease' do
    ENV['LEGION_LEASE_SPEC_SECRET'] = 'environment'
    install_lease(name: :a, password: 'a-first')
    load_credentials(values: { password: ['env://LEGION_LEASE_SPEC_SECRET', 'lease://a#password'] })

    install_lease(name: :a, password: 'a-next')

    expect(Legion::Settings[:credentials][:password]).to eq('environment')
  end

  it 'treats false as a winning literal rather than subscribing a later lease' do
    install_lease(name: :a, password: 'a-first')
    load_credentials(values: { password: [false, 'lease://a#password', 'ignored'] })

    install_lease(name: :a, password: 'a-next')

    expect(Legion::Settings[:credentials][:password]).to be(false)
  end

  it 'does not subscribe an unresolved one-shot reference' do
    load_credentials(values: { password: 'lease://a#password' })

    expect(Legion::Settings[:credentials][:password]).to eq('lease://a#password')
    install_lease(name: :a, password: 'a-arrived')
    expect(Legion::Settings[:credentials][:password]).to eq('lease://a#password')
    Legion::Settings.resolve_secrets!
    expect(Legion::Settings[:credentials][:password]).to eq('a-arrived')
  end

  it 'replaces only the edited destination when a lease source changes' do
    install_lease(name: :a, password: 'a-first')
    install_lease(name: :b, password: 'b-first')
    load_credentials(values: { changed: 'lease://a#password', retained: 'lease://a#password' })
    Legion::Settings[:credentials][:changed] = 'lease://b#password'

    Legion::Settings.resolve_secrets!
    install_lease(name: :a, password: 'a-next')

    expect(Legion::Settings[:credentials]).to eq(changed: 'b-first', retained: 'a-next')
    install_lease(name: :b, password: 'b-next')
    expect(Legion::Settings[:credentials]).to eq(changed: 'b-next', retained: 'a-next')
  end

  it 'retires lease destinations replaced by environment or literal declarations' do
    install_lease(name: :a, password: 'a-first')
    load_credentials(values: { environment: 'lease://a#password', literal: 'lease://a#password' })
    ENV['LEGION_LEASE_SPEC_SECRET'] = 'environment'
    Legion::Settings[:credentials][:environment] = 'env://LEGION_LEASE_SPEC_SECRET'
    Legion::Settings[:credentials][:literal] = 'explicit-literal'

    Legion::Settings.resolve_secrets!
    install_lease(name: :a, password: 'a-next')

    expect(Legion::Settings[:credentials]).to eq(environment: 'environment', literal: 'explicit-literal')
  end

  it 'retires a lease destination replaced by a Vault declaration' do
    install_lease(name: :a, password: 'a-first')
    load_credentials(values: { password: 'lease://a#password' })
    allow(Legion::Crypt).to receive(:vault_connected?).and_return(true)
    allow(Legion::Crypt).to receive(:read).with('secret/replacement').and_return(password: 'vault-secret')
    Legion::Settings[:credentials][:password] = 'vault://secret/replacement#password'

    Legion::Settings.resolve_secrets!
    install_lease(name: :a, password: 'a-next')

    expect(Legion::Settings[:credentials][:password]).to eq('vault-secret')
  end

  it 'retires a deleted destination during repeat resolution' do
    install_lease(name: :a, password: 'a-first')
    load_credentials(values: { removed: 'lease://a#password', retained: 'lease://a#password' })
    Legion::Settings[:credentials].delete(:removed)

    Legion::Settings.resolve_secrets!
    install_lease(name: :a, password: 'a-next')

    expect(Legion::Settings[:credentials]).to eq(retained: 'a-next')
  end

  it 'retains the declaration through repeated resolution after rotation and root rebuilding' do
    install_lease(name: :a, password: 'a-first')
    load_credentials(values: { password: 'lease://a#password' })
    install_lease(name: :a, password: 'a-second')
    expect(Legion::Settings[:credentials][:password]).to eq('a-second')

    Legion::Settings.merge_settings(:unrelated, { enabled: true })
    Legion::Settings.resolve_secrets!
    Legion::Settings.resolve_secrets!
    install_lease(name: :a, password: 'a-third')

    expect(Legion::Settings[:credentials][:password]).to eq('a-third')
    expect(Legion::Settings[:unrelated][:enabled]).to be(true)
  end

  it 'preserves module-default array declarations across reload and rotation' do
    install_lease(name: :a, password: 'a-first')
    Legion::Settings.load(config_dir: tmpdir)
    Legion::Settings.register_library(:credentials, { clients: [[{ password: 'lease://a#password' }]] })
    Legion::Settings.resolve_secrets!

    Legion::Settings.reload!
    install_lease(name: :a, password: 'a-next')

    expect(Legion::Settings[:credentials][:clients]).to eq([[{ password: 'a-next' }]])
  end

  it 'reevaluates the retained chain after rotation and retires the old lease winner' do
    install_lease(name: :a, password: 'a-first')
    load_credentials(values: { password: ['env://LEGION_LEASE_SPEC_SECRET', 'lease://a#password'] })
    install_lease(name: :a, password: 'a-second')
    ENV['LEGION_LEASE_SPEC_SECRET'] = 'environment'

    Legion::Settings.resolve_secrets!
    install_lease(name: :a, password: 'a-third')

    expect(Legion::Settings[:credentials][:password]).to eq('environment')
  end

  it 'rotates typed nested hash and array destinations without duplicate writers' do
    install_lease(name: :a, password: 'a-first')
    load_credentials(values: { clients: [{ 'db.password': 'lease://a#password' }, [{ password: 'lease://a#password' }]] })
    Legion::Settings.resolve_secrets!
    Legion::Settings.resolve_secrets!

    install_lease(name: :a, password: 'a-next')

    expect(Legion::Settings[:credentials][:clients]).to eq([{ 'db.password': 'a-next' }, [{ password: 'a-next' }]])
    expect(manager.push_to_settings(:a)).to eq(2)
  end

  it 'keeps standalone source ownership separate when a resolved hash is duplicated' do
    ENV['LEGION_LEASE_SPEC_SECRET'] = 'first'
    original = { password: 'env://LEGION_LEASE_SPEC_SECRET' }
    Legion::Settings::Resolver.resolve_secrets!(original)
    copied = original.dup
    ENV['LEGION_LEASE_SPEC_SECRET'] = 'second'

    Legion::Settings::Resolver.resolve_secrets!(copied)
    Legion::Settings::Resolver.resolve_secrets!(original)

    expect(copied[:password]).to eq('first')
    expect(original[:password]).to eq('second')
  end

  it 'retains live provenance across GC without changing Hash serialization' do
    ENV['LEGION_LEASE_SPEC_SECRET'] = 'first'
    original = { password: 'env://LEGION_LEASE_SPEC_SECRET' }
    Legion::Settings::Resolver.resolve_secrets!(original)
    copied = Marshal.load(Marshal.dump(original))
    GC.start
    ENV['LEGION_LEASE_SPEC_SECRET'] = 'second'

    Legion::Settings::Resolver.resolve_secrets!(original)
    Legion::Settings::Resolver.resolve_secrets!(copied)

    expect(original[:password]).to eq('second')
    expect(copied[:password]).to eq('first')
  end

  describe 'reload publication' do
    it 'retires a lease when a fresh literal declaration has the same resolved bytes' do
      install_lease(name: :a, password: 'same-secret')
      load_credentials(values: { password: 'lease://a#password' })
      write_credentials(values: { password: 'same-secret' })

      expect(Legion::Settings.reload!).to eq({})
      install_lease(name: :a, password: 'a-next')
      Legion::Settings.resolve_secrets!

      expect(Legion::Settings[:credentials][:password]).to eq('same-secret')
    end

    it 'switches equally valued lease sources even when the value diff is empty' do
      install_lease(name: :a, password: 'same-secret')
      install_lease(name: :b, password: 'same-secret')
      load_credentials(values: { password: 'lease://a#password' })
      write_credentials(values: { password: 'lease://b#password' })

      expect(Legion::Settings.reload!).to eq({})
      install_lease(name: :a, password: 'a-next')
      expect(Legion::Settings[:credentials][:password]).to eq('same-secret')
      install_lease(name: :b, password: 'b-next')
      expect(Legion::Settings[:credentials][:password]).to eq('b-next')
    end

    it 'retires removed destinations without preventing rotation of remaining destinations' do
      install_lease(name: :a, password: 'a-first')
      load_credentials(values: { removed: 'lease://a#password', retained: 'lease://a#password' })
      write_credentials(values: { retained: 'lease://a#password' })

      Legion::Settings.reload!
      install_lease(name: :a, password: 'a-next')

      expect(Legion::Settings[:credentials]).to eq(retained: 'a-next')
    end

    it 'preserves the active loader and bindings when a source file is malformed' do
      install_lease(name: :a, password: 'a-first')
      load_credentials(values: { password: 'lease://a#password' })
      original_loader = Legion::Settings.loader
      File.write(config_file, '{ invalid JSON')

      expect { Legion::Settings.reload! }.to raise_error(StandardError)
      expect(Legion::Settings.loader).to equal(original_loader)
      expect(Legion::Settings[:credentials][:password]).to eq('a-first')
      install_lease(name: :a, password: 'a-next')
      Legion::Settings.resolve_secrets!
      expect(Legion::Settings[:credentials][:password]).to eq('a-next')
    end

    it 'preserves all old bindings when a staged secret cannot resolve' do
      install_lease(name: :a, password: 'a-first')
      install_lease(name: :b, password: 'b-first')
      load_credentials(values: { password: 'lease://a#password' })
      original_loader = Legion::Settings.loader
      write_credentials(values: { password: 'lease://b#password', missing: 'lease://missing#password' })

      expect { Legion::Settings.reload! }.to raise_error(StandardError)
      expect(Legion::Settings.loader).to equal(original_loader)
      install_lease(name: :b, password: 'b-next')
      expect(Legion::Settings[:credentials]).to eq(password: 'a-first')
      install_lease(name: :a, password: 'a-next')
      expect(Legion::Settings[:credentials]).to eq(password: 'a-next')
    end

    it 'publishes the current lease value when rotation occurs during Vault staging' do
      install_lease(name: :a, password: 'a-first')
      load_credentials(values: { password: 'lease://a#password' })
      original_loader = Legion::Settings.loader
      write_credentials(values: { password: 'lease://a#password', token: 'vault://secret/staging#token' })
      allow(Legion::Crypt).to receive(:vault_connected?).and_return(true)
      entered = Queue.new
      release = Queue.new
      allow(Legion::Crypt).to receive(:read).with('secret/staging') do
        entered << true
        release.pop
        { token: 'vault-token' }
      end

      reloader = Thread.new { Legion::Settings.reload! }
      Timeout.timeout(5) { entered.pop }
      expect(Legion::Settings.loader).to equal(original_loader)
      expect(Legion::Settings[:credentials]).to eq(password: 'a-first')
      Timeout.timeout(5) { install_lease(name: :a, password: 'a-during-staging') }
      expect(Legion::Settings[:credentials]).to eq(password: 'a-during-staging')
      release << true
      Timeout.timeout(5) { reloader.value }

      expect(Legion::Settings[:credentials]).to eq(password: 'a-during-staging', token: 'vault-token')
      install_lease(name: :a, password: 'a-after-reload')
      expect(Legion::Settings[:credentials]).to eq(password: 'a-after-reload', token: 'vault-token')
    ensure
      release << true if release
      reloader&.kill if reloader&.alive?
      reloader&.join
    end

    it 'runs reload callbacks outside the lease transaction' do
      install_lease(name: :a, password: 'a-first')
      load_credentials(values: { password: 'lease://a#password', mode: 'old' })
      observed = nil
      Legion::Settings.on_reload do |_changes|
        Legion::Settings.resolve_secrets!
        install_lease(name: :a, password: 'a-from-callback')
        observed = Legion::Settings[:credentials].dup
      end
      write_credentials(values: { password: 'lease://a#password', mode: 'new' })

      Timeout.timeout(5) { Legion::Settings.reload! }

      expect(observed).to eq(password: 'a-from-callback', mode: 'new')
      expect(Legion::Settings[:credentials][:password]).to eq('a-from-callback')
    end

    it 'restores values and old references when publication fails' do
      install_lease(name: :a, password: 'a-first')
      install_lease(name: :b, password: 'b-first')
      load_credentials(values: { password: 'lease://a#password' })
      settings = Legion::Settings.loader.to_hash
      destination = Legion::Settings[:credentials]
      binding = { value: 'b-first' }
      publication = proc { raise IOError, 'publication failed' }

      expect do
        manager.update_settings_refs(settings: settings, publish: publication) do |fetch|
          {
            paths:       [%i[credentials password]],
            assignments: [{ container: destination, key: :password, value: fetch.call(name: :b, key: :password) }],
            references:  [{ name: :b, key: :password, path: %i[credentials password], binding: binding }]
          }
        end
      end.to raise_error(IOError)

      expect(Legion::Settings[:credentials][:password]).to eq('a-first')
      install_lease(name: :b, password: 'b-next')
      expect(Legion::Settings[:credentials][:password]).to eq('a-first')
      install_lease(name: :a, password: 'a-next')
      Legion::Settings.resolve_secrets!
      install_lease(name: :a, password: 'a-last')
      expect(Legion::Settings[:credentials][:password]).to eq('a-last')
    end
  end
end
