# Legion::Settings Changelog

## v1.2.1

### Added
- `dev_mode?` method — returns true when `LEGION_DEV=true` env var or `Settings[:dev]` is set
- Dev mode soft validation: `validate!` warns instead of raising when dev mode is active
- Warning output via `Legion::Logging.warn` (falls back to `$stderr` if logging unavailable)

## v1.2.0
Moving from BitBucket to GitHub. All git history is reset from this point on
