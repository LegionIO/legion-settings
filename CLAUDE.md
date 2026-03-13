# legion-settings: Configuration Management for LegionIO

**Repository Level 3 Documentation**
- **Category**: `/Users/miverso2/rubymine/arc/CLAUDE.md`
- **Workspace**: `/Users/miverso2/rubymine/CLAUDE.md`

## Purpose

Hash-like configuration store for the LegionIO framework. Loads settings from JSON files, directories, and environment variables. Provides a unified `Legion::Settings[:key]` accessor used by all other Legion gems.

**GitHub**: https://github.com/Optum/legion-settings
**License**: Apache-2.0

## Architecture

```
Legion::Settings (singleton module)
├── .load(config_dir:, config_file:, config_dirs:)  # Initialize loader
├── .[](:key)                                         # Hash-like accessor (auto-loads if needed)
├── .set_prop(key, value)                             # Set a value
├── .merge_settings(key, hash)                        # Merge module defaults
│
├── Loader               # Core: loads env vars, files, directories, merges settings
│   ├── .load_env        # Load environment variables
│   ├── .load_file       # Load single JSON file
│   ├── .load_directory  # Load all JSON files from directory
│   └── .load_module_settings  # Merge module-specific defaults
│
├── OS                   # OS detection helpers
└── Validators::Legion   # Settings validation
```

### Key Design Patterns

- **Auto-Load on Access**: `Legion::Settings[:key]` auto-loads if not initialized
- **Directory-Based Config**: Loads all `.json` files from config directories (default paths: `/etc/legionio`, `~/legionio`, `./settings`)
- **Module Merging**: Each Legion module registers its defaults via `merge_settings` during startup (e.g., `Legion::Settings.merge_settings('transport', Legion::Transport::Settings.default)`)
- **Lazy Logging**: Falls back to `::Logger.new($stdout)` if `Legion::Logging` isn't loaded yet

## Dependencies

| Gem | Purpose |
|-----|---------|
| `legion-json` (>= 1.2) | JSON file parsing |

## File Map

| Path | Purpose |
|------|---------|
| `lib/legion/settings.rb` | Module entry, singleton accessors, auto-load logic |
| `lib/legion/settings/loader.rb` | Config loading from env/files/directories, deep merge |
| `lib/legion/settings/os.rb` | OS detection helpers |
| `lib/legion/settings/validators/legion.rb` | Settings validation |
| `lib/legion/settings/version.rb` | VERSION constant |

## Role in LegionIO

**Core configuration gem** - every other Legion gem reads its configuration from `Legion::Settings`. Settings are organized by module key:

```ruby
Legion::Settings[:transport]  # legion-transport config
Legion::Settings[:cache]      # legion-cache config
Legion::Settings[:crypt]      # legion-crypt config
Legion::Settings[:data]       # legion-data config
Legion::Settings[:client]     # Node identity (name, hostname, ready state)
```

---

**Maintained By**: Matthew Iverson (@Esity)
