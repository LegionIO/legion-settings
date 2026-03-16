# frozen_string_literal: true

module Legion
  module Settings
    module Resolver
      VAULT_PATTERN = %r{\Avault://(.+?)#(.+)\z}
      ENV_PATTERN   = %r{\Aenv://(.+)\z}
      URI_PATTERN   = %r{\A(?:vault|env)://}

      module_function

      def resolve_secrets!(settings_hash)
        return settings_hash unless settings_hash.is_a?(Hash)

        @vault_available = vault_connected?
        @vault_cache     = {}

        vault_count = count_vault_refs(settings_hash)
        log_warn("Vault not connected — #{vault_count} vault:// reference(s) will not be resolved") if vault_count.positive? && !@vault_available

        resolved = 0
        unresolved = 0
        walk(settings_hash, path: '') do |result|
          if result == :resolved
            resolved += 1
          elsif result == :unresolved
            unresolved += 1
          end
        end

        log_info("Settings resolver: #{resolved} resolved, #{unresolved} unresolved") if resolved.positive? || unresolved.positive?

        settings_hash
      end

      def resolve_value(value)
        case value
        when String
          return value unless value.match?(URI_PATTERN)

          resolve_single(value)
        when Array
          return value unless resolvable_chain?(value)

          resolve_chain(value)
        else
          value
        end
      end

      def resolve_single(str)
        if (m = str.match(VAULT_PATTERN))
          resolve_vault(m[1], m[2])
        elsif (m = str.match(ENV_PATTERN))
          ENV.fetch(m[1], nil)
        else
          str
        end
      end

      def resolve_chain(arr)
        arr.each do |entry|
          result = if entry.is_a?(String) && entry.match?(URI_PATTERN)
                     resolve_single(entry)
                   else
                     entry
                   end
          return result unless result.nil?
        end
        nil
      end

      def has_vault_refs?(hash) # rubocop:disable Naming/PredicatePrefix
        count_vault_refs(hash).positive?
      end

      def count_vault_refs(hash)
        return 0 unless hash.is_a?(Hash)

        hash.sum do |_key, value|
          case value
          when String then value.match?(VAULT_PATTERN) ? 1 : 0
          when Array  then value.count { |v| v.is_a?(String) && v.match?(VAULT_PATTERN) }
          when Hash   then count_vault_refs(value)
          else 0
          end
        end
      end

      def vault_connected?
        return false unless defined?(Legion::Crypt)
        return false unless defined?(Legion::Settings)

        Legion::Settings[:crypt][:vault][:connected] == true
      rescue StandardError
        false
      end

      def walk(hash, path:, &block)
        hash.each do |key, value|
          current_path = path.empty? ? key.to_s : "#{path}.#{key}"

          case value
          when Hash
            walk(value, path: current_path, &block)
          when String
            next unless value.match?(URI_PATTERN)

            resolved = resolve_single(value)
            if resolved.nil?
              log_warn("Settings resolver: could not resolve #{current_path} (#{value})")
              block&.call(:unresolved)
            else
              hash[key] = resolved
              block&.call(:resolved)
            end
          when Array
            next unless resolvable_chain?(value)

            resolved = resolve_chain(value)
            if resolved.nil?
              log_warn("Settings resolver: fallback chain exhausted for #{current_path}")
              block&.call(:unresolved)
            else
              hash[key] = resolved
              block&.call(:resolved)
            end
          end
        end
      end

      def resolve_vault(path, key)
        return nil unless @vault_available

        @vault_cache[path] ||= begin
          Legion::Crypt.read(path)
        rescue StandardError => e
          log_debug("Settings resolver: vault read failed for #{path}: #{e.message}")
          nil
        end

        data = @vault_cache[path]
        return nil unless data.is_a?(Hash)

        data[key.to_sym] || data[key.to_s]
      end

      def resolvable_chain?(arr)
        arr.any? { |v| v.is_a?(String) && v.match?(URI_PATTERN) }
      end

      def log_info(message)
        if defined?(Legion::Logging)
          Legion::Logging.info(message)
        else
          $stdout.puts(message)
        end
      end

      def log_warn(message)
        if defined?(Legion::Logging)
          Legion::Logging.warn(message)
        else
          warn(message)
        end
      end

      def log_debug(message)
        if defined?(Legion::Logging)
          Legion::Logging.debug(message)
        else
          $stdout.puts(message)
        end
      end
    end
  end
end
