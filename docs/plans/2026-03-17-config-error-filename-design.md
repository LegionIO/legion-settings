# Design: Include Filename in JSON Parse Error Messages

## Problem

When a user edits a config file and introduces a JSON syntax error, the settings loader logs:

```
ERROR config file must be valid json
```

The filename is only logged at DEBUG level on the next line:

```ruby
Legion::Logging.error('config file must be valid json')
Legion::Logging.debug("file:#{file}, error: #{e}")
```

This makes it nearly impossible for users to identify which file is broken, especially when multiple config files exist in `~/.legionio/settings/`. The settings loader silently skips the broken file, and downstream code fails with confusing errors (e.g., RubyLLM complaining about missing API keys because `llm.json` wasn't loaded).

## Proposed Solution

Change `load_file` in `loader.rb` to include the filename and parse error in the ERROR message:

```ruby
rescue Legion::JSON::ParseError => e
  Legion::Logging.error("config file must be valid json: #{file}")
  Legion::Logging.error("  parse error: #{e.message}")
end
```

This is a one-line change (plus one added line) in `loader.rb:140-142`.

### Before

```
[2026-03-17 18:27:27 -0500] ERROR config file must be valid json
```

### After

```
[2026-03-17 18:27:27 -0500] ERROR config file must be valid json: /Users/matt/.legionio/settings/llm.json
[2026-03-17 18:27:27 -0500] ERROR   parse error: unexpected token at '{ "llm": { ... '
```

## Alternatives Considered

1. **Raise instead of logging** — rejected; the current behavior of skipping broken files and continuing is correct for resilience. But the user needs to know what happened.
2. **Add a `config validate` pre-check** — already exists (`legion config validate`), but users won't run it proactively. The error message at load time is the first line of defense.
3. **Return the broken files in `loaded_files`** — would require API changes for minimal benefit.

## Constraints

- Do not change the error-handling behavior (continue loading other files)
- Do not change method signatures
- The debug line can be removed since the info is now in the error message
