# legion-settings

Configuration management module for the [LegionIO](https://github.com/LegionIO/LegionIO) framework. Loads settings from JSON files, directories, and environment variables. Provides a unified `Legion::Settings[:key]` accessor used by all other Legion gems.

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

Legion::Settings.load(config_dir: './')  # loads all .json files in the directory

Legion::Settings[:client][:hostname]
Legion::Settings[:transport][:connection][:host]
```

### Config Paths (checked in order)

1. `/etc/legionio/`
2. `~/.legionio/settings/`
3. `~/legionio/`
4. `./settings/`

Each Legion module registers its own defaults via `merge_settings` during startup.

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
# validate! will warn to $stderr (or Legion::Logging) instead of raising
```

## Requirements

- Ruby >= 3.4
- `legion-json`

## License

Apache-2.0
