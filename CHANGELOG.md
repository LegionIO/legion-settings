# Legion::Settings Changelog

## [1.3.20] - 2026-03-27

### Fixed
- Add 1-second timeout to FQDN detection to prevent boot hang on slow DNS
- Downgrade FQDN detection failure log from warn to debug

### Added
- `Resolver#resolve_vault`: debug logging for vault path, key, cache hits, returned data structure, and extracted values

## [1.3.18] - 2026-03-24

### Added
- `Legion::Settings::Validators::Tls` — validates TLS settings blocks (transport, data, api, security) with warnings for weak verify modes, errors for insecure sslmode in production, and missing cert paths

## [1.3.17] - 2026-03-24

### Changed
- `load` is now idempotent: reuses existing Loader, only sets `@loaded` when config files are provided, skips on subsequent calls unless `force: true`
- `[]`, `dig`, `merge_settings`, `set_prop`, `validate!`, `resolve_secrets!`, `errors` now use lightweight `ensure_loader` (env vars only, no DNS bootstrap) instead of triggering full `load`
- Module merges via `merge_settings` at require-time no longer trigger DNS bootstrap or create a new Loader

### Added
- `loaded?` class method to check if settings have been fully loaded with config files
- `reset!` class method to clear all state (loader, schema, cross-validations) for testing
- `ensure_loader` private method: creates minimal Loader with env vars only, no DNS bootstrap

## [1.3.16] - 2026-03-24

### Fixed
- `Loader#load_module_settings` and `#load_module_default` now reset `@indifferent_access = false` after replacing `@settings` with a new plain Hash from `deep_merge`, preventing stale state where string key access silently returned nil on subsequent `to_hash` calls (fixes #4)

## [1.3.15] - 2026-03-23

### Added
- `Loader.default_directories` class method: canonical settings directory discovery with `LEGION_SETTINGS_DIRS` env var override
- Returns `~/.legionio/settings` + `/etc/legionio/settings` (unix) or `~/.legionio/settings` + optional `%APPDATA%\legionio\settings` (windows, when APPDATA is set)
- `log_info` private helper for info-level logging in Loader

### Changed
- `load_directory` logging upgraded from debug to info level

## [1.3.14] - 2026-03-22

### Added
- `Legion::Settings::Helper` module: injectable `settings` mixin for LEX extensions
- Derives extension key from `lex_filename` or class name (in priority order)
- Returns default logger config when no extension settings are configured

## [1.3.13] - 2026-03-22

### Changed
- Updated `legion-json` dependency version constraint from `>= 1.2` to `>= 1.2.0` (explicit 3-part version)

## [1.3.12] - 2026-03-22

### Changed
- Added logging to all silent rescue blocks in settings.rb, loader.rb, resolver.rb, and dns_bootstrap.rb

## [1.3.11] - 2026-03-22

### Added
- `loader.rb`: debug logging on `load_directory` (file count), `load_module_settings`, and `load_module_default` (module name)
- `loader.rb`: warn logging in `start_dns_background_refresh`, `read_resolv_config`, and `detect_fqdn` rescue blocks
- `settings.rb`: info logging on successful load (file count), validate! success, and debug on resolve_secrets! completion
- `settings.rb`: warn logging before raising `ValidationError` in production mode
- `dns_bootstrap.rb`: warn on HTTP fetch failure, debug on cache hit, warn when corrupt cache is deleted
- `agent_loader.rb`: warn on file parse failure, debug on agent loaded

## [1.3.10] - 2026-03-22

### Added
- `extensions.parallel_pool_size` setting (default: 24) to control thread pool size for parallel extension loading

## [1.3.9] - 2026-03-21

### Added
- `region` settings block: `current`, `primary`, `failover`, `peers`, `default_affinity` (prefer_local), `data_residency`
- `process` settings block: `role` (default: 'full') for process role configuration
- `:region` and `:process` added to `CORE_MODULES` for schema validation coverage
- 16 new specs (262 total, 0 failures)

## [1.3.8] - 2026-03-20

### Added
- `AgentLoader` module for loading YAML/JSON agent definitions from a directory
- `AgentLoader.load_agents(directory)` — returns validated agent definitions as symbol-keyed hashes
- `AgentLoader.load_file(path)` — parses `.yaml`, `.yml`, and `.json` agent definition files
- `AgentLoader.valid?(definition)` — validates required `name` and `runner.functions` keys

## [1.3.7] - 2026-03-20

### Added
- `enterprise_privacy?` class method: returns true when `LEGION_ENTERPRISE_PRIVACY=true` env var or `enterprise_data_privacy` setting is set
- `LEGION_ENTERPRISE_PRIVACY` env var loaded into settings via `Loader#load_privacy_env`

## [1.3.6] - 2026-03-20

### Fixed
- Guard all `Legion::Logging` calls in loader with `defined?` check to prevent `NameError` when legion-logging is not loaded (fixes CI for downstream gems like legion-transport)

## [1.3.5] - 2026-03-19

### Added
- DNS-based bootstrap discovery: auto-detect corporate config from `legion-bootstrap.<search-domain>`
- `Settings[:dns]` populated with FQDN, default domain, search domains, and nameservers
- `DnsBootstrap` class with DNS resolution, HTTPS fetch, local caching, and background refresh
- First boot blocks on fetch; subsequent boots use cache with async refresh
- Opt-out via `LEGION_DNS_BOOTSTRAP=false` environment variable

## [1.3.4] - 2026-03-18

### Fixed
- Added `logger` gem to test dependencies for Ruby 4.0 compatibility

## [1.3.3] - 2026-03-17

### Fixed
- Config JSON parse error now includes the filename at ERROR level instead of burying it in DEBUG

## [1.3.2] - 2026-03-17

### Added
- `dig(*keys)` method on `Legion::Settings` and `Legion::Settings::Loader` for nested key access

## [1.3.1] - 2026-03-16

### Added
- `lease://name#key` URI scheme in secret resolver for dynamic Vault leases
- Delegates to `Legion::Crypt::LeaseManager` for lease data lookup
- Registers reverse references for push-back on credential rotation

## [1.3.0] - 2026-03-16

### Added
- Universal secret resolver: `vault://` and `env://` URI references in any settings value
- Fallback chain support via arrays (first non-nil wins)
- `Legion::Settings.resolve_secrets!` method for explicit resolution phase
- Vault read caching within a single resolution pass

## [1.2.2] - 2026-03-16

### Added
- `role` key in default settings with `profile` and `extensions` fields for extension profile filtering

## v1.2.1

### Added
- `dev_mode?` method — returns true when `LEGION_DEV=true` env var or `Settings[:dev]` is set
- Dev mode soft validation: `validate!` warns instead of raising when dev mode is active
- Warning output via `Legion::Logging.warn` (falls back to `$stderr` if logging unavailable)

## v1.2.0
Moving from BitBucket to GitHub. All git history is reset from this point on
