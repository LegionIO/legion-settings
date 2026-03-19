# Implementation: Include Filename in JSON Parse Error Messages

## Phase 1: Update Error Logging

### Files to Modify

- `lib/legion/settings/loader.rb` — lines 140-142

### Changes

Replace:

```ruby
rescue Legion::JSON::ParseError => e
  Legion::Logging.error('config file must be valid json')
  Legion::Logging.debug("file:#{file}, error: #{e}")
```

With:

```ruby
rescue Legion::JSON::ParseError => e
  Legion::Logging.error("config file must be valid json: #{file}")
  Legion::Logging.error("  parse error: #{e.message}")
```

### Spec Coverage

- Add spec in `spec/legion/loader_spec.rb` that writes invalid JSON to a temp file, calls `load_file`, and asserts the error was logged with the filename

### Version Bump

- Bump patch version in `lib/legion/settings/version.rb`
- Update CHANGELOG.md
