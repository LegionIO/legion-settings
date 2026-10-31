# legion-settings

Configuration management module for the [LegionIO](https://github.com/LegionIO/LegionIO) framework. Loads settings from JSON files, directories, and environment variables. Provides a unified `Legion::Settings[:key]` accessor used by all other Legion gems.

**Version**: 1.5.0

## Installation

```bash
gem install legion-settings
```

Or add to your Gemfile:

```ruby
gem 'legion-settings'
```

## Usage

```ruby
require 'legion/settings'

Legion::Settings.load                          # loads defaults, env, DNS bootstrap, and nearest .legionio.env
Legion::Settings.load(config_dir: './settings') # also loads all .json files in the directory

Legion::Settings[:client][:hostname]
Legion::Settings.dig(:transport, :connection, :host)
```

`[]` and `dig` will auto-load settings on first access, and implicit access follows the same overlay/project-env/base precedence as explicit `load`.

### Config Loading

`Legion::Settings.load` only consumes the paths you pass via `config_file`, `config_dir`, or `config_dirs`.

If a caller wants the canonical Legion search directories, use `Legion::Settings::Loader.default_directories`:

1. `~/.legionio/settings`
2. `/etc/legionio/settings` on Unix-like systems
3. `%APPDATA%\\legionio\\settings` on Windows when `APPDATA` is present

`LegionIO` uses those directories during daemon boot. Library consumers can choose to pass any directory set they want.

Each Legion module registers its own defaults via `merge_settings` during startup, and the nearest `.legionio.env` file is merged on top of base settings. Request overlays applied through `with_overlay` take highest precedence.

### Hot Reload

`Legion::Settings.reload!` re-reads the config files that were previously loaded, reapplies module defaults and the nearest `.legionio.env`, re-resolves secret references, and returns a hash describing the changed keys.

```ruby
changes = Legion::Settings.reload!

changes
# {
#   "llm.default_model" => { old: "old-model", new: "new-model" }
# }
```

Callbacks run only when changes are detected:

```ruby
Legion::Settings.on_reload do |changes|
  Legion::Settings.logger.info("Settings changed: #{changes.keys.join(', ')}")
end
```

`watch!` installs a SIGHUP handler when the platform supports it. Repeated signals are coalesced through one background reload worker, so rapid SIGHUP bursts do not create unbounded reload threads.

```ruby
Legion::Settings.watch! do |changes|
  Legion::Settings.logger.info("Reloaded #{changes.size} setting(s)")
end

# Later, from a shell:
# kill -HUP <daemon_pid>
```

On platforms without `HUP`, `watch!` logs and returns without raising. Direct `reload!` remains available for API endpoints, tests, or environments that use a different process-control mechanism.

### Project Environment Overrides

When present, the nearest `.legionio.env` file is loaded after base settings and module defaults. Dot notation maps to nested settings:

```dotenv
llm.default_model=claude-sonnet
cache.driver=redis
```

Hot reload picks up changes to this file as part of the same `reload!` flow.

### Secret Resolution

Settings values can reference external secret sources using URI syntax. Three schemes are supported:

| Scheme | Format | Resolution |
|--------|--------|------------|
| `vault://` | `vault://path/to/secret#key` | Reads static KV secrets from HashiCorp Vault via `Legion::Crypt` |
| `env://` | `env://ENV_VAR_NAME` | Reads from environment variable |
| `lease://` | `lease://name#key` | Reads from dynamic Vault leases via `Legion::Crypt::LeaseManager` |

Array values act as fallback chains — the first non-nil result wins:

```json
{
  "transport": {
    "connection": {
      "password": ["vault://secret/data/rabbitmq#password", "env://RABBITMQ_PASSWORD", "guest"]
    }
  }
}
```

Call `Legion::Settings.resolve_secrets!` to resolve all URIs in-place. In the LegionIO boot sequence this is called automatically after `Legion::Crypt.start`. The `env://` scheme works even when Vault is not connected.

```ruby
Legion::Settings.resolve_secrets!
# All vault://, env://, and lease:// references are now replaced with their resolved values
```

### Schema Validation

Types are inferred automatically from default values. Optional constraints can be added:

```ruby
Legion::Settings.merge_settings('mymodule', { host: 'localhost', port: 8080 })
Legion::Settings.define_schema('mymodule', { port: { required: true } })
Legion::Settings.validate!  # raises ValidationError if any settings are invalid

# In development, warn instead of raising:
# Set LEGION_DEV=true or Legion::Settings.set_prop(:dev, true)
# validate! will warn through the configured logger instead of raising
```

### Shared Task Execution Configuration

`require 'legion/settings/task_execution'` registers defaults at the root
`Legion::Settings[:task_execution]`, not under `:extensions`. Existing file,
project environment, and request-overlay scalar values win over defaults.
Arrays retain established append/union semantics. Restrictive permissions use
Boolean maps: `false` explicitly revokes an inherited permission; omitting a key
does not revoke it. Pass overlays with symbol keys (as returned by
`Legion::JSON.load`). Consumers include or
extend `Legion::Settings::TaskExecution::Helper`:

```ruby
require 'legion/settings/task_execution'
extend Legion::Settings::TaskExecution::Helper

task_execution_settings                 # current validated root configuration
task_status(name: :completed)            # "task.completed"
task_route(name: :check_subtask)          # "task.subtask.check"
task_terminal_status?(status: 'task.failed') # true

Legion::Settings.with_overlay(task_execution: { statuses: { completed: 'custom.done' } }) do
  task_terminal_status?(status: 'custom.done') # true
end
```

The helper re-registers defaults after loader replacement/reset and reads live
overlays on every call; it does not cache consumer configuration or substitute
hardcoded strings for malformed configuration. `TaskExecution.default` returns
a fresh default hash. `TaskExecution.register!` registers against the current
loader; `TaskExecution.validate!(settings:)` explicitly validates a supplied
configuration. Helper reads perform this validation automatically and raise
`TaskExecution::ConfigurationError` with the offending path. Required keys,
nonempty status/route strings, unique task status/message type/outbox status
identities, resolvable terminal names, positive integer limits, Boolean publication flags, metadata names,
safe-runner names, ordered retry delays, and heartbeat intervals shorter than
the execution lease are checked.

All defaults below are configurable:

| Section | Defaults |
|---------|----------|
| `statuses` | `queued`, `running`, `completed`, `exception`, `failed`, `skipped`, `cancelled`, `expired`, `delayed`, `dispatching`, `multiplied`, `retry_pending`, `unknown`, `blocked` map to `task.<name>` |
| `statuses` (stages) | `conditioner_queued` → `conditioner.queued`, `conditioner_failed` → `conditioner.failed`, `conditioner_exception` → `conditioner.exception`, `transformer_queued` → `transformer.queued`, `transformer_succeeded` → `transformer.succeeded`, `transformer_validation_failed` → `transformer.validation_failed`, `transformer_failed` → `transformer.failed` |
| `routes` | `check_subtask: task.subtask.check`, `conditioner: task.subtask.conditioner`, `transform: task.subtask.transform`, `task_update: task.update` |
| `message_types` | `check_subtask: check_subtask`, `subtask: subtask`, `task: task`, `dynamic: dynamic`, `transform: transform` |
| `terminal_statuses` | `completed`, `failed`, `exception`, `skipped`, `cancelled`, `expired`, `multiplied`, `conditioner_failed`, `conditioner_exception`, `transformer_validation_failed`, `transformer_failed`, `unknown`, `blocked` |
| `legacy_terminal_statuses` | `completed`, `complete`, `failed`, `error`, `cancelled`, `canceled`, `timeout`, `timed_out`, `exception`, `skipped`, `expired`, `multiplied` |
| `retry` | `max_attempts: 3`, `base_delay_seconds: 1`, `max_delay_seconds: 30`, `safe_runners: {}` |
| `execution` | `lease_seconds: 60`, `heartbeat_seconds: 20`, `max_depth: 100`, `max_fanout: 1000`, `idempotency_ttl_seconds: 86400`, `max_payload_bytes: 524288` |
| `outbox` | `lease_seconds: 30`, `batch_size: 100`, `poll_interval_seconds: 1` |
| `outbox.statuses` | `pending: pending`, `claimed: claimed`, `delivered: delivered`, `discarded: discarded` |
| `publication` | `publisher_confirm: true`, `mandatory: true`, `return_result: true`, `publish_confirm_timeout_ms: 5000`, `spool: false` |
| `ingress.trusted_internal_principal` | `id: legion-task-service`, `type: worker`, `roles: { worker: true }` |
| `protocol` | `version: 1`; `metadata_fields` listed below |

`protocol.metadata_fields` defaults to `task_id`, `parent_id`, `master_id`,
`chain_id`, `relationship_id`, `function_id`, `function`, `runner_class`,
`runner_routing_key`, `trigger_function_id`, `trigger_runner_id`, `debug`,
`engine`, `schema`, `engine_options`, `principal_id`, `principal_type`, `worker_id`,
`tenant_id`, `source`, `correlation_id`, `message_id`, `attempt_id`,
`execution_token`, `depth`, `deadline_at`, `schedule_id`, `occurrence_id`,
`definition_version`, `originating_principal_id`, and `originating_principal_type`.

Terminal lists accept symbolic keys or JSON string keys, resolved against the
current configured statuses. Legacy spellings recognize stored rows only; new
outcomes always use the configured canonical status. A blocked admission is
terminal; quiescing defers work and must not produce a blocked admission.
`safe_runners` maps explicit `Fully::Qualified::Runner#function` names to
`true`/`false`; the empty default never declares ambiguous external effects safe
to retry. Roles likewise map role names to Booleans; `{ worker: false }` disables
the inherited worker grant. Non-Boolean permissions and old Array forms are
rejected, never interpreted using Ruby truthiness.
The configured internal principal is only for authenticated/trusted actor
paths; an incoming message's `source` or principal fields are not proof of trust.
Originating principal fields preserve audit context, not authentication or roles.
Publication spooling defaults off because the transactional outbox is the
durable source of truth.

### Logging Defaults

The `logging` key includes a `transport` sub-section that controls whether log events are forwarded over the message bus:

```json
{
  "logging": {
    "level": "info",
    "format": "text",
    "log_file": "./legionio/logs/legion.log",
    "log_stdout": true,
    "trace": true,
    "async": true,
    "include_pid": false,
    "transport": {
      "enabled": true,
      "forward_logs": true,
      "forward_exceptions": true
    }
  }
}
```

When `transport.enabled` is `true`, log events and unhandled exceptions are published to the AMQP bus so a central log consumer can aggregate them.

## Requirements

- Ruby >= 3.4
- `legion-json`

## License

Apache-2.0
