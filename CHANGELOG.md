# Legion::Settings Changelog

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
