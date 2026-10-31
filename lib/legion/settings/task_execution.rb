# frozen_string_literal: true

require 'legion/settings'

module Legion
  module Settings
    module TaskExecution
      class ConfigurationError < ArgumentError; end

      class << self
        def default
          {
            statuses:                 {
              queued: 'task.queued', running: 'task.running', completed: 'task.completed',
              exception: 'task.exception', failed: 'task.failed', skipped: 'task.skipped',
              cancelled: 'task.cancelled', expired: 'task.expired', delayed: 'task.delayed',
              dispatching: 'task.dispatching', multiplied: 'task.multiplied', retry_pending: 'task.retry_pending',
              unknown: 'task.unknown', conditioner_queued: 'conditioner.queued', conditioner_failed: 'conditioner.failed',
              conditioner_exception: 'conditioner.exception', transformer_queued: 'transformer.queued',
              transformer_succeeded: 'transformer.succeeded', transformer_validation_failed: 'transformer.validation_failed',
              transformer_failed: 'transformer.failed', blocked: 'task.blocked'
            },
            routes:                   {
              check_subtask: 'task.subtask.check', conditioner: 'task.subtask.conditioner',
              transform: 'task.subtask.transform', task_update: 'task.update'
            },
            message_types:            {
              check_subtask: 'check_subtask', subtask: 'subtask', task: 'task', dynamic: 'dynamic', transform: 'transform'
            },
            terminal_statuses:        %i[completed failed exception skipped cancelled expired multiplied conditioner_failed
                                         conditioner_exception transformer_validation_failed transformer_failed unknown blocked],
            legacy_terminal_statuses: %w[completed complete failed error cancelled canceled timeout timed_out exception skipped expired multiplied],
            retry:                    { max_attempts: 3, base_delay_seconds: 1, max_delay_seconds: 30, safe_runners: {} },
            execution:                {
              lease_seconds: 60, heartbeat_seconds: 20, max_depth: 100, max_fanout: 1000,
              idempotency_ttl_seconds: 86_400, max_payload_bytes: 524_288
            },
            ingress:                  { trusted_internal_principal: { id: 'legion-task-service', type: 'worker', roles: { worker: true } } },
            outbox:                   {
              lease_seconds: 30, batch_size: 100, poll_interval_seconds: 1,
              statuses: { pending: 'pending', claimed: 'claimed', delivered: 'delivered', discarded: 'discarded' }
            },
            publication:              {
              publisher_confirm: true, mandatory: true, return_result: true, publish_confirm_timeout_ms: 5000, spool: false
            },
            protocol:                 {
              version:         1,
              metadata_fields: %i[task_id parent_id master_id chain_id relationship_id function_id function runner_class
                                  runner_routing_key trigger_function_id trigger_runner_id debug engine schema engine_options
                                  principal_id principal_type worker_id tenant_id source correlation_id message_id attempt_id
                                  execution_token depth deadline_at schedule_id occurrence_id definition_version
                                  originating_principal_id originating_principal_type]
            }
          }
        end

        def register!
          return if Legion::Settings.loader&.merged_modules&.key?(:task_execution)

          Legion::Settings.register_library(:task_execution, default)
        end

        def validate!(settings:)
          @validation_template ||= default
          validate_shape!(value: settings, template: @validation_template, path: 'task_execution')
          validate_names!(settings: settings)
          validate_policy!(settings: settings)
          settings
        end

        private

        def validate_names!(settings:)
          %i[statuses routes message_types].each do |section|
            settings.fetch(section).each { |name, value| validate_string!(value: value, path: "task_execution.#{section}.#{name}") }
          end
          [%i[statuses], %i[message_types], %i[outbox statuses]].each do |path|
            values = settings.dig(*path).values
            next if values.uniq.size == values.size

            raise ConfigurationError, "task_execution.#{path.join('.')} values must be unique"
          end
          statuses = settings.fetch(:statuses)

          settings.fetch(:terminal_statuses).each do |name|
            next if (name.is_a?(Symbol) || name.is_a?(String)) && statuses.key?(name.to_sym)

            raise ConfigurationError, "task_execution.terminal_statuses references unknown status #{name.inspect}"
          end
          settings.fetch(:legacy_terminal_statuses).each do |status|
            validate_string!(value: status, path: 'task_execution.legacy_terminal_statuses')
          end
          settings.fetch(:protocol).fetch(:metadata_fields).each do |field|
            next if field.is_a?(Symbol) || (field.is_a?(String) && !field.strip.empty?)

            raise ConfigurationError, 'task_execution.protocol.metadata_fields must contain nonempty names'
          end
        end

        def validate_policy!(settings:)
          validate_permission_map!(value: settings.fetch(:retry).fetch(:safe_runners), path: 'task_execution.retry.safe_runners',
                                   name_pattern: /\A(?:::)?[A-Z]\w*(?:::[A-Z]\w*)*#[a-z_]\w*[!?=]?\z/)
          validate_permission_map!(value: settings.fetch(:ingress).fetch(:trusted_internal_principal).fetch(:roles),
                                   path: 'task_execution.ingress.trusted_internal_principal.roles', name_pattern: /\A[a-zA-Z][\w-]*\z/)
          retry_settings = settings.fetch(:retry)
          if retry_settings.fetch(:max_delay_seconds) < retry_settings.fetch(:base_delay_seconds)
            raise ConfigurationError, 'task_execution.retry.max_delay_seconds must be >= base_delay_seconds'
          end

          execution_settings = settings.fetch(:execution)
          return if execution_settings.fetch(:heartbeat_seconds) < execution_settings.fetch(:lease_seconds)

          raise ConfigurationError, 'task_execution.execution.heartbeat_seconds must be < lease_seconds'
        end

        def validate_permission_map!(value:, path:, name_pattern:)
          names = value.keys.map(&:to_s)
          raise ConfigurationError, "#{path} contains duplicate permission names" unless names.uniq.size == names.size

          value.each do |name, enabled|
            unless (name.is_a?(String) || name.is_a?(Symbol)) && name_pattern.match?(name.to_s)
              raise ConfigurationError, "#{path} contains invalid permission name #{name.inspect}"
            end
            next if [true, false].include?(enabled)

            raise ConfigurationError, "#{path}.#{name} must be true or false"
          end
        end

        def validate_shape!(value:, template:, path:)
          case template
          when Hash
            raise ConfigurationError, "#{path} must be a Hash" unless value.is_a?(Hash)

            template.each do |key, expected|
              raise ConfigurationError, "#{path}.#{key} is missing" unless value.key?(key)

              validate_shape!(value: value[key], template: expected, path: "#{path}.#{key}")
            end
          when String
            validate_string!(value: value, path: path)
          when Integer
            raise ConfigurationError, "#{path} must be a positive Integer" unless value.is_a?(Integer) && value.positive?
          when Array
            raise ConfigurationError, "#{path} must be an Array" unless value.is_a?(Array)
          when true, false
            raise ConfigurationError, "#{path} must be true or false" unless [true, false].include?(value)
          end
        end

        def validate_string!(value:, path:)
          return if value.is_a?(String) && !value.strip.empty?

          raise ConfigurationError, "#{path} must be a nonempty String"
        end
      end

      module Helper
        def task_execution_settings
          Legion::Settings::TaskExecution.register!
          Legion::Settings::TaskExecution.validate!(settings: Legion::Settings[:task_execution])
        end

        def task_status(name:)
          task_configured_name(section: :statuses, name: name)
        end

        def task_route(name:)
          task_configured_name(section: :routes, name: name)
        end

        def task_terminal_status?(status:)
          config = task_execution_settings
          config.fetch(:terminal_statuses).any? { |name| config.fetch(:statuses).fetch(name.to_sym) == status } ||
            config.fetch(:legacy_terminal_statuses).include?(status)
        end

        private

        def task_configured_name(section:, name:)
          unless name.is_a?(String) || name.is_a?(Symbol)
            raise Legion::Settings::TaskExecution::ConfigurationError, "task_execution.#{section} name must be a String or Symbol"
          end

          task_execution_settings.fetch(section).fetch(name.to_sym) do
            raise Legion::Settings::TaskExecution::ConfigurationError, "task_execution.#{section}.#{name} is not configured"
          end
        end
      end
    end
  end
end

Legion::Settings::TaskExecution.register!
