# frozen_string_literal: true

require 'legion/logging'
require 'legion/settings/deep_merge'

module Legion
  module Settings
    # Per-project `.legionio.env` config file loader.
    #
    # Walks up from Dir.pwd searching for a `.legionio.env` file.  When found,
    # parses `KEY=VALUE` lines with dot-notation keys and merges them into the
    # loader at a priority between global settings and the request overlay.
    #
    # File format:
    #   # comment lines are ignored
    #   llm.default_model=claude-sonnet-4-5-20241022
    #   cache.driver=redis
    #
    # Keys use dot notation to address nested settings paths.
    # Values are always strings; callers should coerce as needed.
    #
    # Resolution order (lowest → highest priority):
    #   global settings < .legionio.env < request overlay (#9)
    module ProjectEnv
      extend Legion::Logging::Helper

      ENV_FILENAME = '.legionio.env'

      class << self
        # Walk up from +start_dir+ (defaults to Dir.pwd) looking for
        # `.legionio.env`.  Returns the first file found, or nil.
        #
        # @param start_dir [String, nil] directory to start the search from
        # @return [String, nil] absolute path to the file, or nil
        def find_project_env_file(start_dir: nil)
          dir = File.expand_path(start_dir || Dir.pwd)
          loop do
            candidate = File.join(dir, ENV_FILENAME)
            return candidate if File.file?(candidate) && File.readable?(candidate)

            parent = File.dirname(dir)
            break if parent == dir # filesystem root

            dir = parent
          end
          nil
        end

        # Parse a `.legionio.env` file and return a nested hash of overrides.
        #
        # @param path [String] absolute path to the file
        # @return [Hash] nested hash with symbol keys
        def parse_env_file(path)
          result = {}
          File.readlines(path, chomp: true).each_with_index do |line, idx|
            next if line.strip.empty?
            next if line.strip.start_with?('#')

            parts = line.split('=', 2)
            unless parts.length == 2
              log.warn("#{path}:#{idx + 1}: skipping malformed line (no '=' found)")
              next
            end

            raw_key, value = parts
            key_parts = raw_key.strip.split('.')
            if key_parts.empty? || key_parts.any?(&:empty?)
              log.warn("#{path}:#{idx + 1}: skipping invalid key '#{raw_key.strip}'")
              next
            end

            set_nested(result, key_parts.map(&:to_sym), value.strip)
          end
          result
        end

        # Find and load the project env file into the given settings hash,
        # merging overrides (env file values win over existing values).
        #
        # @param settings [Hash] the settings hash to merge into (mutated in place)
        # @param start_dir [String, nil] directory to start searching from
        # @return [String, nil] path to the loaded file, or nil if none found
        def load_into(settings, start_dir: nil)
          path = find_project_env_file(start_dir: start_dir)
          return nil unless path

          overrides = parse_env_file(path)
          deep_merge_into!(settings, overrides)
          log.debug("ProjectEnv: loaded #{path}")
          path
        end

        private

        def resolve_logger_settings
          raw_logging = Legion::Settings.loader&.settings&.dig(:logging) if Legion::Settings.respond_to?(:loader)
          raw_logging.is_a?(Hash) ? raw_logging : Legion::Logging::Settings.default
        end

        def set_nested(hash, keys, value)
          *parents, leaf = keys
          target = parents.reduce(hash) do |h, k|
            h[k] ||= {}
            h[k]
          end
          target[leaf] = value
        end

        def deep_merge_into!(base, overrides)
          DeepMerge.deep_merge!(base, overrides)
        end
      end
    end
  end
end
