# legion-settings: Configuration Management for LegionIO

**Repository Level 3 Documentation**
- **Parent**: `/Users/miverso2/rubymine/legion/CLAUDE.md`

## Purpose

Hash-like configuration store for the LegionIO framework. Loads settings from JSON files, directories, and environment variables. Provides a unified `Legion::Settings[:key]` accessor used by all other Legion gems. Includes schema-based validation with type inference, enum constraints, and cross-module checks.

**GitHub**: https://github.com/LegionIO/legion-settings
**Version**: 1.3.9
**License**: Apache-2.0

## Architecture

```
Legion::Settings (singleton module)
├── .load(config_dir:, config_file:, config_dirs:)  # Initialize loader
├── .[](:key)                                         # Hash-like accessor (auto-loads if needed)
├── .set_prop(key, value)                             # Set a value
├── .merge_settings(key, hash)                        # Merge module defaults + register schema
├── .define_schema(key, overrides)                    # Add enum/required constraints
├── .add_cross_validation(&block)                     # Register cross-module validation
├── .validate!                                        # Run all validations, raise on errors
├── .schema                                           # Access Schema instance
├── .errors                                           # Access collected errors
│
├── Loader               # Core: loads env vars, files, directories, merges settings
│   ├── .load_env        # Load environment variables (LEGION_API_PORT)
│   ├── .load_dns_bootstrap  # DNS-based corporate config discovery (baseline defaults)
│   ├── .load_file       # Load single JSON file
│   ├── .load_directory  # Load all JSON files from directory
│   ├── .load_module_settings    # Merge with module priority
│   └── .load_module_default     # Merge with default priority
│
├── DnsBootstrap         # DNS-based corporate config auto-discovery
│   ├── .resolve?        # Check if legion-bootstrap.<domain> resolves
│   ├── .fetch           # HTTPS GET /legion/bootstrap.json
│   ├── .write_cache     # Atomic write to ~/.legionio/settings/_dns_bootstrap.json
│   ├── .read_cache      # Read + strip metadata, delete if corrupted
│   └── .cache_exists?   # Check for cached config
│
├── Schema               # Type inference, validation, unknown key detection
│   ├── .register        # Infer types from defaults
│   ├── .define_override # Add enum/required/type constraints
│   ├── .validate_module # Validate values against schema
│   └── .detect_unknown_keys  # Find typos via Levenshtein distance
│
├── ValidationError      # Collects all errors, raises once with formatted message
├── OS                   # OS detection helpers
└── CORE_MODULES         # [:transport, :cache, :crypt, :data, :logging, :client]
```

### Key Design Patterns

- **Auto-Load on Access**: `Legion::Settings[:key]` auto-loads if not initialized
- **DNS Bootstrap Discovery**: On load, resolves `legion-bootstrap.<search-domain>` to fetch corporate baseline config. First boot blocks; subsequent boots use cache + async refresh. Disabled via `LEGION_DNS_BOOTSTRAP=false`
- **Directory-Based Config**: Loads all `.json` files from config directories (default paths: `/etc/legionio`, `~/legionio`, `./settings`)
- **Load Priority** (lowest to highest): hardcoded defaults < DNS bootstrap < local JSON files < CLI flags < secret resolution
- **Module Merging**: Each Legion module registers its defaults via `merge_settings` during startup
- **Schema Inference**: Types are inferred from default values — no manual schema definitions needed
- **Two-Pass Validation**: Per-module on merge (catches type mismatches immediately) + cross-module on `validate!` (catches dependency conflicts)
- **Self-Service Registration**: LEX modules register schemas alongside defaults via `merge_settings` — no core changes needed
- **Fail-Fast**: `validate!` collects all errors and raises `ValidationError` once with a formatted message
- **Lazy Logging**: Falls back to `::Logger.new($stdout)` if `Legion::Logging` isn't loaded yet

## Dependencies

| Gem | Purpose |
|-----|---------|
| `legion-json` (>= 1.2) | JSON file parsing |

## File Map

| Path | Purpose |
|------|---------|
| `lib/legion/settings.rb` | Module entry, singleton accessors, schema integration, validation orchestration |
| `lib/legion/settings/loader.rb` | Config loading from env/files/directories, deep merge, indifferent access |
| `lib/legion/settings/schema.rb` | Type inference, validation logic, unknown key detection (Levenshtein) |
| `lib/legion/settings/validation_error.rb` | Error collection and formatted reporting |
| `lib/legion/settings/os.rb` | OS detection helpers |
| `lib/legion/settings/resolver.rb` | Secret resolution: `vault://` and `env://` URI references, fallback chains |
| `lib/legion/settings/dns_bootstrap.rb` | DNS-based corporate config discovery, caching, background refresh |
| `lib/legion/settings/version.rb` | VERSION constant |
| `spec/legion/settings_spec.rb` | Core settings module tests |
| `spec/legion/settings_module_spec.rb` | Module-level accessor and merge tests |
| `spec/legion/loader_spec.rb` | Loader: env/file/directory loading tests |
| `spec/legion/settings/schema_spec.rb` | Schema validation tests |
| `spec/legion/settings/validation_error_spec.rb` | Error formatting tests |
| `spec/legion/settings/integration_spec.rb` | End-to-end validation + DNS bootstrap override tests |
| `spec/legion/settings/dns_bootstrap_spec.rb` | DnsBootstrap class tests (resolve, fetch, cache) |
| `spec/legion/settings/role_defaults_spec.rb` | Role profile default settings tests |
| `spec/legion/settings/resolver_spec.rb` | Secret resolver tests (env://, vault://, lease://, fallback chains) |

## Secret Resolution

Settings values can reference external secret sources using URI syntax. Resolved in-place via `Legion::Settings.resolve_secrets!` (called automatically after `Legion::Crypt.start` in the boot sequence).

### URI Schemes

| Scheme | Format | Resolution |
|--------|--------|------------|
| `vault://` | `vault://path/to/secret#key` | `Legion::Crypt.read(path)[key]` (static KV secrets) |
| `env://` | `env://ENV_VAR_NAME` | `ENV['ENV_VAR_NAME']` |
| `lease://` | `lease://name#key` | `Legion::Crypt::LeaseManager.instance.fetch(name, key)` (dynamic Vault leases) |
| *(plain string)* | `"guest"` | Returned as-is |

### Fallback Chains

Array values are tried in order — first non-nil wins:

```json
{
  "transport": {
    "connection": {
      "password": ["vault://secret/data/rabbitmq#password", "env://RABBITMQ_PASSWORD", "guest"]
    }
  }
}
```

### Logging Strategy

- Vault not connected + vault refs exist: one summary warning with count
- Individual vault path failures: debug level
- Entire chain resolves to nil: one warning per key path
- Success: info summary with resolved counts

### Implementation

`Legion::Settings::Resolver` module with `module_function`. Called via `Legion::Settings.resolve_secrets!` which delegates to `Resolver.resolve_secrets!(@loader.to_hash)`. Vault reads are cached by path within a single resolution pass.

## Role in LegionIO

**Core configuration gem** - every other Legion gem reads its configuration from `Legion::Settings`. Settings are organized by module key:

```ruby
Legion::Settings[:transport]  # legion-transport config
Legion::Settings[:cache]      # legion-cache config
Legion::Settings[:crypt]      # legion-crypt config
Legion::Settings[:data]       # legion-data config
Legion::Settings[:client]     # Node identity (name, hostname, ready state)
Legion::Settings[:role]       # Extension profile filtering (profile, extensions)
```

### Validation Usage

```ruby
# Modules register defaults (schema inferred automatically)
Legion::Settings.merge_settings('transport', { host: 'localhost', port: 5672 })

# Optional: add constraints beyond type inference
Legion::Settings.define_schema('cache', { driver: { enum: %w[dalli redis] } })

# Optional: cross-module validation
Legion::Settings.add_cross_validation do |settings, errors|
  if settings[:crypt][:cluster_secret].nil? && settings[:transport][:connected]
    errors << { module: :crypt, path: 'crypt.cluster_secret', message: 'required when transport is connected' }
  end
end

# Validate all at once (raises ValidationError with all collected errors)
Legion::Settings.validate!
```

---

**Maintained By**: Matthew Iverson (@Esity)
