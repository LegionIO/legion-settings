# legion-settings

The process-local, in-memory settings store for the [LegionIO](https://github.com/LegionIO/LegionIO) framework. Loads settings from JSON files, directories, and environment variables into a shared settings tree, exposed through `Legion::Settings[:key]`.

**Version**: 1.4.5

## Process-Local Settings Model

Think of `legion-settings` as **one big, process-local `Concurrent::Hash`-style object**: the settings tree for that running Ruby process.

- **Shared within the process.** Gems, extensions, actors, and worker threads use the same base settings tree through `Legion::Settings`, rather than maintaining separate copies of the application's configuration.
- **Local to that process.** Another process has its own settings object, even on the same host or when loading the same files. Changing this process's settings does not update another process or node.
- **Generic storage, component-owned meaning.** Each library owns its namespace, defaults, and behavior. Settings supplies common loading, merging, access, and reload mechanics; it does not own each component's execution policy.
- **An in-memory object, not a persistence or synchronization service.** Files, environment variables, defaults, and resolved secrets populate the tree. Runtime changes do not automatically write back to those sources or broadcast to other processes.

Request overlays provide scoped overrides without replacing the shared base tree. The `Concurrent::Hash`-style model does not mean every nested value is itself a concurrent hash or that an arbitrary sequence of reads and writes is atomic; callers must coordinate compound mutations.

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

Reload publishes the new loader and its lease bindings together. A source change is committed even when its resolved value is unchanged, so replacing a lease URI with the same literal bytes still stops rotation. Malformed files or unresolved secrets raise and leave the active loader and bindings intact.

```ruby
changes = Legion::Settings.reload!

changes
# {
#   "llm.default_model" => { old: "old-model", new: "new-model" }
# }
```

Callbacks run after publication, outside the reload and lease locks, and only when resolved values change:

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

Lease integration requires **legion-crypt 1.5.38 or newer** with **legion-settings 1.4.4 or newer**. Settings keeps Crypt optional, so environment and literal-only resolution work without Crypt. Crypt 1.5.39 and newer require Settings as a runtime dependency.

Only the winning lease in a fallback chain can rotate its destination. A winning environment, Vault, or literal value—including `false`—does not subscribe unused leases. Nested hashes and arrays use typed paths, so array indexes and keys containing dots are preserved.

Repeated resolution reevaluates the retained source declarations, including after rotation. Editing a URI or changing a resolved value replaces its source; removing a destination retires its lease binding. A fresh reload treats file contents as new declarations rather than guessing provenance from matching secret values. Vault read caches are local to each resolution, and Vault reads finish before lease publication begins.

An unresolved one-shot reference is logged and left unchanged; strict reload rejects unresolved references instead of replacing live settings.

```ruby
Legion::Settings.resolve_secrets!
# Resolvable vault://, env://, and lease:// references are replaced with their values
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

### Library Defaults

Libraries own their defaults and register them once at startup with
`Legion::Settings.register_library(:my_library, defaults)`. Existing configuration
values take precedence, including `false`, `nil`, and empty or restricted arrays.
Registration fills missing keys; it does not union default arrays into user policy.
`load(force: true)` retains registered defaults and applies them after loading user
configuration. A manually replaced loader must be bootstrapped explicitly.

Consumers read live `Legion::Settings[:component][:key]` values instead of caching
loader pointers or registering defaults during reads. LegionIO automatically injects
`Legion::Settings::Helper` into framework runners and actors; those consumers use
their native `settings[:key]` helper.

Settings and overlays are local to the process. Registration does not synchronize
configuration across processes or provide durable shared state.

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
