# Legion::Settings Changelog

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
