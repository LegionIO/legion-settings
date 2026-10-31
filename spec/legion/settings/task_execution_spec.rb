# frozen_string_literal: true

require 'spec_helper'
require 'legion/settings/task_execution'
require 'tmpdir'

RSpec.describe Legion::Settings::TaskExecution do
  subject(:consumer) { Object.new.extend(described_class::Helper) }

  before { Legion::Settings.reset! }
  after { Legion::Settings.reset! }

  it 'preserves user JSON settings when registering after loading files' do
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'task.json')
      File.write(path, Legion::JSON.dump({ task_execution: { statuses: { completed: 'custom.done' }, retry: { max_attempts: 7 } } }))
      Legion::Settings.load(config_file: path)

      expect(consumer.task_status(name: :completed)).to eq('custom.done')
      expect(consumer.task_execution_settings.dig(:retry, :max_attempts)).to eq(7)
      expect(consumer.task_terminal_status?(status: 'custom.done')).to be(true)
      expect(consumer.task_terminal_status?(status: 'task.completed')).to be(false)
    end
  end

  it 'preserves late file settings and rereads them after reload' do
    described_class.register!
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'task.json')
      File.write(path, Legion::JSON.dump({ task_execution: { routes: { transform: 'custom.transform' } } }))
      Legion::Settings.load(config_file: path)
      expect(consumer.task_route(name: :transform)).to eq('custom.transform')

      File.write(path, Legion::JSON.dump({ task_execution: { routes: { transform: 'reloaded.transform' } } }))
      Legion::Settings.reload!
      expect(consumer.task_route(name: :transform)).to eq('reloaded.transform')
      expect(consumer.task_status(name: :queued)).to eq('task.queued')
    end
  end

  it 'registers against a replacement loader without losing its overrides' do
    described_class.register!
    Legion::Settings.loader = Legion::Settings::Loader.new
    Legion::Settings.loader.settings[:task_execution] = { statuses: { queued: 'replacement.queued' } }

    expect(consumer.task_status(name: :queued)).to eq('replacement.queued')
    expect(consumer.task_route(name: :task_update)).to eq('task.update')
  end

  it 'restores registered defaults after a forced load' do
    described_class.register!
    Legion::Settings.load(force: true)

    expect(consumer.task_terminal_status?(status: 'task.failed')).to be(true)
    expect(consumer.task_terminal_status?(status: 'task.retry_pending')).to be(false)
  end

  it 'resolves nested request overlays and restores the outer and global values' do
    original = consumer.task_route(name: :transform)
    Legion::Settings.with_overlay(task_execution: { routes: { transform: 'outer.transform' }, statuses: { completed: 'overlay.done' } }) do
      expect(consumer.task_route(name: :transform)).to eq('outer.transform')
      expect(consumer.task_terminal_status?(status: 'overlay.done')).to be(true)
      inner = Legion::JSON.load('{"task_execution":{"routes":{"transform":"inner.transform"}}}')
      Legion::Settings.with_overlay(inner) do
        expect(consumer.task_route(name: 'transform')).to eq('inner.transform')
      end
      expect(consumer.task_route(name: :transform)).to eq('outer.transform')
    end
    expect(consumer.task_route(name: :transform)).to eq(original)
    expect(consumer.task_terminal_status?(status: 'overlay.done')).to be(false)
  end

  it 'resolves JSON terminal keys using additive overlay semantics and preserves stored legacy spellings' do
    expect(consumer.task_terminal_status?(status: 'task.running')).to be(false)
    Legion::Settings.with_overlay(task_execution: { terminal_statuses: ['running'] }) do
      expect(consumer.task_terminal_status?(status: 'task.running')).to be(true)
      expect(consumer.task_terminal_status?(status: 'task.completed')).to be(true)
      expect(consumer.task_terminal_status?(status: 'timed_out')).to be(true)
      expect(consumer.task_terminal_status?(status: 'canceled')).to be(true)
    end
  end

  it 'can revoke a safe runner within nested requests without mutating the global policy' do
    described_class.register!
    Legion::Settings.loader.settings[:task_execution][:retry][:safe_runners] = { 'Example::Runner#execute': true }

    Legion::Settings.with_overlay(task_execution: { retry: { safe_runners: { 'Example::Runner#execute': false } } }) do
      expect(consumer.task_execution_settings.dig(:retry, :safe_runners, :'Example::Runner#execute')).to be(false)
      Legion::Settings.with_overlay(task_execution: { retry: { safe_runners: { 'Example::Runner#execute': true } } }) do
        expect(consumer.task_execution_settings.dig(:retry, :safe_runners, :'Example::Runner#execute')).to be(true)
      end
      expect(consumer.task_execution_settings.dig(:retry, :safe_runners, :'Example::Runner#execute')).to be(false)
    end
    expect(consumer.task_execution_settings.dig(:retry, :safe_runners, :'Example::Runner#execute')).to be(true)
  end

  it 'preserves preconfigured role revocation when registering defaults' do
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'permissions.json')
      File.write(path, Legion::JSON.dump({ task_execution: {
                                           ingress: { trusted_internal_principal: { roles: { worker: false } } },
                                           retry:   { safe_runners: { 'Example::Runner#execute': false } }
                                         } }))
      Legion::Settings.load(config_file: path)
      expect(consumer.task_execution_settings.dig(:ingress, :trusted_internal_principal, :roles, :worker)).to be(false)
      expect(consumer.task_execution_settings.dig(:retry, :safe_runners, :'Example::Runner#execute')).to be(false)
    end
  end

  it 'revokes an inherited worker role without granting it from truthy non-Boolean values' do
    Legion::Settings.with_overlay(task_execution: { ingress: { trusted_internal_principal: { roles: { worker: false } } } }) do
      expect(consumer.task_execution_settings.dig(:ingress, :trusted_internal_principal, :roles, :worker)).to be(false)
    end
    Legion::Settings.with_overlay(task_execution: { ingress: { trusted_internal_principal: { roles: { admin: 'false' } } } }) do
      expect { consumer.task_execution_settings }.to raise_error(described_class::ConfigurationError, /roles.admin/)
    end
  end

  it 'rejects non-Boolean safe-runner permissions' do
    Legion::Settings.with_overlay(task_execution: { retry: { safe_runners: { 'Example::Runner#execute': 'false' } } }) do
      expect { consumer.task_execution_settings }.to raise_error(described_class::ConfigurationError, /safe_runners/)
    end
  end

  it 'rejects malformed runner permission names' do
    Legion::Settings.with_overlay(task_execution: { retry: { safe_runners: { '*': true } } }) do
      expect { consumer.task_execution_settings }.to raise_error(described_class::ConfigurationError, /invalid permission name/)
    end
  end

  it 'rejects legacy array permission settings instead of silently granting their entries' do
    Legion::Settings.with_overlay(task_execution: { retry: { safe_runners: ['Example::Runner#execute'] } }) do
      expect { consumer.task_execution_settings }.to raise_error(described_class::ConfigurationError, /safe_runners.*Hash/)
    end
  end

  it 'rejects ambiguous string and symbol grants instead of masking a revocation' do
    described_class.register!
    Legion::Settings.loader.settings[:task_execution][:retry][:safe_runners] = { 'Example::Runner#execute': true }
    Legion::Settings.with_overlay(task_execution: { retry: { safe_runners: { 'Example::Runner#execute' => false } } }) do
      expect { consumer.task_execution_settings }.to raise_error(described_class::ConfigurationError, /duplicate permission names/)
    end
  end

  it 'does not repair removed status configuration with hidden defaults' do
    described_class.register!
    Legion::Settings.loader.settings[:task_execution][:statuses].delete(:completed)

    expect { consumer.task_status(name: :completed) }.to raise_error(described_class::ConfigurationError, /statuses.completed/)
  end

  it 'rejects unknown status names instead of emitting a guessed value' do
    expect { consumer.task_status(name: :missing) }.to raise_error(described_class::ConfigurationError, /statuses.missing/)
  end

  it 'rejects blank configured routes even in request overlays' do
    Legion::Settings.with_overlay(task_execution: { routes: { transform: ' ' } }) do
      expect { consumer.task_route(name: :transform) }.to raise_error(described_class::ConfigurationError, /routes.transform/)
    end
  end

  it 'rejects conflicting status identities' do
    Legion::Settings.with_overlay(task_execution: { statuses: { failed: 'task.completed' } }) do
      expect { consumer.task_terminal_status?(status: 'task.completed') }.to raise_error(described_class::ConfigurationError, /unique/)
    end
  end

  it 'rejects ambiguous message identifiers before the relay selects a message class' do
    Legion::Settings.with_overlay(task_execution: { message_types: { transform: 'task' } }) do
      expect { consumer.task_execution_settings }.to raise_error(described_class::ConfigurationError, /message_types.*unique/)
    end
  end

  it 'rejects outbox states that make pending and delivered intents indistinguishable' do
    Legion::Settings.with_overlay(task_execution: { outbox: { statuses: { delivered: 'pending' } } }) do
      expect { consumer.task_execution_settings }.to raise_error(described_class::ConfigurationError, /outbox.statuses.*unique/)
    end
  end

  it 'rejects terminal names which cannot be resolved' do
    Legion::Settings.with_overlay(task_execution: { terminal_statuses: [:nonexistent] }) do
      expect { consumer.task_terminal_status?(status: 'task.failed') }.to raise_error(described_class::ConfigurationError, /unknown status/)
    end
  end

  it 'rejects invalid lease policy before it reaches storage consumers' do
    Legion::Settings.with_overlay(task_execution: { execution: { lease_seconds: 0 } }) do
      expect { consumer.task_execution_settings }.to raise_error(described_class::ConfigurationError, /execution.lease_seconds/)
    end
  end

  it 'rejects heartbeats that cannot renew before the execution lease expires' do
    Legion::Settings.with_overlay(task_execution: { execution: { heartbeat_seconds: 60, lease_seconds: 60 } }) do
      expect { consumer.task_execution_settings }.to raise_error(described_class::ConfigurationError, /execution.heartbeat_seconds/)
    end
  end

  it 'rejects an inverted retry backoff range' do
    Legion::Settings.with_overlay(task_execution: { retry: { base_delay_seconds: 40, max_delay_seconds: 30 } }) do
      expect { consumer.task_execution_settings }.to raise_error(described_class::ConfigurationError, /max_delay_seconds/)
    end
  end
end
