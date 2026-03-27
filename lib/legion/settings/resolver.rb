# frozen_string_literal: true

module Legion
  module Settings
    module Resolver
      VAULT_PATTERN  = %r{\Avault://(.+?)#(.+)\z}
      ENV_PATTERN    = %r{\Aenv://(.+)\z}
      LEASE_PATTERN  = %r{\Alease://(.+?)#(.+)\z}
      URI_PATTERN    = %r{\A(?:vault|env|lease)://}

      module_function

      def resolve_secrets!(settings_hash)
        return settings_hash unless settings_hash.is_a?(Hash)

        @vault_available = vault_connected?
        @vault_cache     = {}

        vault_count = count_vault_refs(settings_hash)
        log_warn("Vault not connected — #{vault_count} vault:// reference(s) will not be resolved") if vault_count.positive? && !@vault_available

        lease_count = count_lease_refs(settings_hash)
        log_warn("LeaseManager not available — #{lease_count} lease:// reference(s) will not be resolved") if lease_count.positive? && !lease_manager_available?

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
        elsif (m = str.match(LEASE_PATTERN))
          resolve_lease(m[1], m[2])
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
      rescue StandardError => e
        log_debug("Legion::Settings::Resolver#vault_connected? failed: #{e.message}")
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
              register_lease_ref(value, current_path) if value.match?(LEASE_PATTERN)
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
              register_lease_refs_from_chain(value, current_path)
              block&.call(:resolved)
            end
          end
        end
      end

      def resolve_vault(path, key)
        log_debug("resolve_vault: path=#{path}, key=#{key}, vault_available=#{@vault_available}")
        return nil unless @vault_available

        @vault_cache[path] ||= begin
          log_debug("resolve_vault: calling Legion::Crypt.read(#{path.inspect})")
          result = Legion::Crypt.read(path)
          log_debug("resolve_vault: read returned #{result.nil? ? 'nil' : "keys=#{result.keys.inspect}"}")
          result
        rescue StandardError => e
          log_warn("Settings resolver: vault read failed for #{path}: #{e.class}=#{e.message}")
          nil
        end

        data = @vault_cache[path]
        unless data.is_a?(Hash)
          log_debug("resolve_vault: data at #{path} is #{data.class}, returning nil")
          return nil
        end

        value = data[key.to_sym] || data[key.to_s]
        log_debug("resolve_vault: #{path}##{key} = #{value.nil? ? 'nil' : '<present>'}")
        value
      end

      def resolve_lease(name, key)
        return nil unless lease_manager_available?

        Legion::Crypt::LeaseManager.instance.fetch(name, key)
      rescue StandardError => e
        log_debug("Settings resolver: lease fetch failed for #{name}##{key}: #{e.message}")
        nil
      end

      def lease_manager_available?
        defined?(Legion::Crypt::LeaseManager)
      rescue StandardError => e
        log_debug("Legion::Settings::Resolver#lease_manager_available? failed: #{e.message}")
        false
      end

      def resolvable_chain?(arr)
        arr.any? { |v| v.is_a?(String) && v.match?(URI_PATTERN) }
      end

      def register_lease_ref(value, path_string)
        return unless lease_manager_available?

        m = value.match(LEASE_PATTERN)
        return unless m

        path_parts = path_string.split('.').map(&:to_sym)
        Legion::Crypt::LeaseManager.instance.register_ref(m[1], m[2], path_parts)
      rescue StandardError => e
        log_debug("Legion::Settings::Resolver#register_lease_ref failed for #{path_string}: #{e.message}")
        nil
      end

      def register_lease_refs_from_chain(arr, path_string)
        return unless lease_manager_available?

        arr.each do |entry|
          next unless entry.is_a?(String)

          register_lease_ref(entry, path_string) if entry.match?(LEASE_PATTERN)
        end
      end

      def count_lease_refs(hash)
        return 0 unless hash.is_a?(Hash)

        hash.sum do |_key, value|
          case value
          when String then value.match?(LEASE_PATTERN) ? 1 : 0
          when Array  then value.count { |v| v.is_a?(String) && v.match?(LEASE_PATTERN) }
          when Hash   then count_lease_refs(value)
          else 0
          end
        end
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
